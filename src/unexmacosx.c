/* Dump Emacs in Mach-O format for use on Mac OS X.
   Copyright (C) 2001, 2002 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs; see the file COPYING.  If not, write to
the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
Boston, MA 02111-1307, USA.  */

/* Contributed by Andrew Choi (akochoi@mac.com).  */

/* Documentation note.

   Consult the following documents/files for a description of the
   Mach-O format: the file loader.h, man pages for Mach-O and ld, old
   NEXTSTEP documents of the Mach-O format.  The tool otool dumps the
   mach header (-h option) and the load commands (-l option) in a
   Mach-O file.  The tool nm on Mac OS X displays the symbol table in
   a Mach-O file.  For examples of unexec for the Mach-O format, see
   the file unexnext.c in the GNU Emacs distribution, the file
   unexdyld.c in the Darwin port of GNU Emacs 20.7, and unexdyld.c in
   the Darwin port of XEmacs 21.1.  Also the Darwin Libc source
   contains the source code for malloc_freezedry and malloc_jumpstart.
   Read that to see what they do.  This file was written completely
   from scratch, making use of information from the above sources.  */

/* The Mac OS X implementation of unexec makes use of Darwin's `zone'
   memory allocator.  All calls to malloc, realloc, and free in Emacs
   are redirected to unexec_malloc, unexec_realloc, and unexec_free in
   this file.  When temacs is run, all memory requests are handled in
   the zone EmacsZone.  The Darwin memory allocator library calls
   maintain the data structures to manage this zone.  Dumping writes
   its contents to data segments of the executable file.  When emacs
   is run, the loader recreates the contents of the zone in memory.
   However since the initialization routine of the zone memory
   allocator is run again, this `zone' can no longer be used as a
   heap.  That is why emacs uses the ordinary malloc system call to
   allocate memory.  Also, when a block of memory needs to be
   reallocated and the new size is larger than the old one, a new
   block must be obtained by malloc and the old contents copied to
   it.  */

/* Peculiarity of the Mach-O files generated by ld in Mac OS X
   (possible causes of future bugs if changed).

   The file offset of the start of the __TEXT segment is zero.  Since
   the Mach header and load commands are located at the beginning of a
   Mach-O file, copying the contents of the __TEXT segment from the
   input file overwrites them in the output file.  Despite this,
   unexec works fine as written below because the segment load command
   for __TEXT appears, and is therefore processed, before all other
   load commands except the segment load command for __PAGEZERO, which
   remains unchanged.

   Although the file offset of the start of the __TEXT segment is
   zero, none of the sections it contains actually start there.  In
   fact, the earliest one starts a few hundred bytes beyond the end of
   the last load command.  The linker option -headerpad controls the
   minimum size of this padding.  Its setting can be changed in
   s/darwin.h.  A value of 0x300, e.g., leaves room for about 15
   additional load commands for the newly created __DATA segments (at
   56 bytes each).  Unexec fails if there is not enough room for these
   new segments.

   The __TEXT segment contains the sections __text, __cstring,
   __picsymbol_stub, and __const and the __DATA segment contains the
   sections __data, __la_symbol_ptr, __nl_symbol_ptr, __dyld, __bss,
   and __common.  The other segments do not contain any sections.
   These sections are copied from the input file to the output file,
   except for __data, __bss, and __common, which are dumped from
   memory.  The types of the sections __bss and __common are changed
   from S_ZEROFILL to S_REGULAR.  Note that the number of sections and
   their relative order in the input and output files remain
   unchanged.  Otherwise all n_sect fields in the nlist records in the
   symbol table (specified by the LC_SYMTAB load command) will have to
   be changed accordingly.
*/

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <stdarg.h>
#include <sys/types.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <objc/malloc.h>

#define VERBOSE 1

/* Size of buffer used to copy data from the input file to the output
   file in function unexec_copy.  */
#define UNEXEC_COPY_BUFSZ 1024

/* Regions with memory addresses above this value are assumed to be
   mapped to dynamically loaded libraries and will not be dumped.  */
#define VM_DATA_TOP (20 * 1024 * 1024)

/* Used by malloc_freezedry and malloc_jumpstart.  */
int malloc_cookie;

/* Type of an element on the list of regions to be dumped.  */
struct region_t {
  vm_address_t address;
  vm_size_t size;
  vm_prot_t protection;
  vm_prot_t max_protection;

  struct region_t *next;
};

/* Head and tail of the list of regions to be dumped.  */
struct region_t *region_list_head = 0;
struct region_t *region_list_tail = 0;

/* Pointer to array of load commands.  */
struct load_command **lca;

/* Number of load commands.  */
int nlc;

/* The highest VM address of segments loaded by the input file.
   Regions with addresses beyond this are assumed to be allocated
   dynamically and thus require dumping.  */
vm_address_t infile_lc_highest_addr = 0;

/* The lowest file offset used by the all sections in the __TEXT
   segments.  This leaves room at the beginning of the file to store
   the Mach-O header.  Check this value against header size to ensure
   the added load commands for the new __DATA segments did not
   overwrite any of the sections in the __TEXT segment.  */
unsigned long text_seg_lowest_offset = 0x10000000;

/* Mach header.  */
struct mach_header mh;

/* Offset at which the next load command should be written.  */
unsigned long curr_header_offset = sizeof (struct mach_header);

/* Current adjustment that needs to be made to offset values because
   of additional data segments.  */
unsigned long delta = 0;

int infd, outfd;

int in_dumped_exec = 0;

malloc_zone_t *emacs_zone;

/* Read n bytes from infd into memory starting at address dest.
   Return true if successful, false otherwise.  */
static int
unexec_read (void *dest, size_t n)
{
  return n == read (infd, dest, n);
}

/* Write n bytes from memory starting at address src to outfd starting
   at offset dest.  Return true if successful, false otherwise.  */
static int
unexec_write (off_t dest, const void *src, size_t count)
{
  if (lseek (outfd, dest, SEEK_SET) != dest)
    return 0;

  return write (outfd, src, count) == count;
}

/* Copy n bytes from starting offset src in infd to starting offset
   dest in outfd.  Return true if successful, false otherwise.  */
static int
unexec_copy (off_t dest, off_t src, ssize_t count)
{
  ssize_t bytes_read;

  char buf[UNEXEC_COPY_BUFSZ];

  if (lseek (infd, src, SEEK_SET) != src)
    return 0;

  if (lseek (outfd, dest, SEEK_SET) != dest)
    return 0;

  while (count > 0)
    {
      bytes_read = read (infd, buf, UNEXEC_COPY_BUFSZ);
      if (bytes_read <= 0)
	return 0;
      if (write (outfd, buf, bytes_read) != bytes_read)
	return 0;
      count -= bytes_read;
    }

  return 1;
}

/* Debugging and informational messages routines.  */

static void
unexec_error (char *format, ...)
{
  va_list ap;

  va_start (ap, format);
  fprintf (stderr, "unexec: ");
  vfprintf (stderr, format, ap);
  fprintf (stderr, "\n");
  va_end (ap);
  exit (1);
}

static void
print_prot (vm_prot_t prot)
{
  if (prot == VM_PROT_NONE)
    printf ("none");
  else
    {
      putchar (prot & VM_PROT_READ ? 'r' : ' ');
      putchar (prot & VM_PROT_WRITE ? 'w' : ' ');
      putchar (prot & VM_PROT_EXECUTE ? 'x' : ' ');
      putchar (' ');
    }
}

static void
print_region (vm_address_t address, vm_size_t size, vm_prot_t prot,
	      vm_prot_t max_prot)
{
  printf ("%#10x %#8x ", address, size);
  print_prot (prot);
  putchar (' ');
  print_prot (max_prot);
  putchar ('\n');
}

static void
print_region_list ()
{
  struct region_t *r;

  printf ("   address     size prot maxp\n");

  for (r = region_list_head; r; r = r->next)
    print_region (r->address, r->size, r->protection, r->max_protection);
}

void
print_regions ()
{
  task_t target_task = mach_task_self ();
  vm_address_t address = (vm_address_t) 0;
  vm_size_t size;
  struct vm_region_basic_info info;
  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
  mach_port_t object_name;

  printf ("   address     size prot maxp\n");

  while (vm_region (target_task, &address, &size, VM_REGION_BASIC_INFO,
		    (vm_region_info_t) &info, &info_count, &object_name)
	 == KERN_SUCCESS && info_count == VM_REGION_BASIC_INFO_COUNT)
    {
      print_region (address, size, info.protection, info.max_protection);

      if (object_name != MACH_PORT_NULL)
	mach_port_deallocate (target_task, object_name);

      address += size;
    }
}

/* Build the list of regions that need to be dumped.  Regions with
   addresses above VM_DATA_TOP are omitted.  Adjacent regions with
   identical protection are merged.  Note that non-writable regions
   cannot be omitted because they some regions created at run time are
   read-only.  */
static void
build_region_list ()
{
  task_t target_task = mach_task_self ();
  vm_address_t address = (vm_address_t) 0;
  vm_size_t size;
  struct vm_region_basic_info info;
  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
  mach_port_t object_name;
  struct region_t *r;

#if VERBOSE
  printf ("--- List of All Regions ---\n");
  printf ("   address     size prot maxp\n");
#endif

  while (vm_region (target_task, &address, &size, VM_REGION_BASIC_INFO,
		    (vm_region_info_t) &info, &info_count, &object_name)
	 == KERN_SUCCESS && info_count == VM_REGION_BASIC_INFO_COUNT)
    {
      /* Done when we reach addresses of shared libraries, which are
	 loaded in high memory.  */
      if (address >= VM_DATA_TOP)
	break;

#if VERBOSE
      print_region (address, size, info.protection, info.max_protection);
#endif

      /* If a region immediately follows the previous one (the one
	 most recently added to the list) and has identical
	 protection, merge it with the latter.  Otherwise create a
	 new list element for it.  */
      if (region_list_tail
	  && info.protection == region_list_tail->protection
	  && info.max_protection == region_list_tail->max_protection
	  && region_list_tail->address + region_list_tail->size == address)
	{
	  region_list_tail->size += size;
	}
      else
	{
	  r = (struct region_t *) malloc (sizeof (struct region_t));

	  if (!r)
	    unexec_error ("cannot allocate region structure");

	  r->address = address;
	  r->size = size;
	  r->protection = info.protection;
	  r->max_protection = info.max_protection;

	  r->next = 0;
	  if (region_list_head == 0)
	    {
	      region_list_head = r;
	      region_list_tail = r;
	    }
	  else
	    {
	      region_list_tail->next = r;
	      region_list_tail = r;
	    }

	  /* Deallocate (unused) object name returned by
	     vm_region.  */
	  if (object_name != MACH_PORT_NULL)
	    mach_port_deallocate (target_task, object_name);
	}

      address += size;
    }

  printf ("--- List of Regions to be Dumped ---\n");
  print_region_list ();
}


#define MAX_UNEXEC_REGIONS 30

int num_unexec_regions;
vm_range_t unexec_regions[MAX_UNEXEC_REGIONS];

static void
unexec_regions_recorder (task_t task, void *rr, unsigned type,
			 vm_range_t *ranges, unsigned num)
{
  while (num && num_unexec_regions < MAX_UNEXEC_REGIONS)
    {
      unexec_regions[num_unexec_regions++] = *ranges;
      printf ("%#8x (sz: %#8x)\n", ranges->address, ranges->size);
      ranges++; num--;
    }
  if (num_unexec_regions == MAX_UNEXEC_REGIONS)
    fprintf (stderr, "malloc_freezedry_recorder: too many regions\n");
}

static kern_return_t
unexec_reader (task_t task, vm_address_t address, vm_size_t size, void **ptr)
{
  *ptr = (void *) address;
  return KERN_SUCCESS;
}

void
find_emacs_zone_regions ()
{
  num_unexec_regions = 0;

  emacs_zone->introspect->enumerator (mach_task_self(), 0,
				      MALLOC_PTR_REGION_RANGE_TYPE
				      | MALLOC_ADMIN_REGION_RANGE_TYPE,
				      (vm_address_t) emacs_zone,
				      unexec_reader,
				      unexec_regions_recorder);
}


/* More informational messages routines.  */

static void
print_load_command_name (int lc)
{
  switch (lc)
    {
    case LC_SEGMENT:
      printf ("LC_SEGMENT       ");
      break;
    case LC_LOAD_DYLINKER:
      printf ("LC_LOAD_DYLINKER ");
      break;
    case LC_LOAD_DYLIB:
      printf ("LC_LOAD_DYLIB    ");
      break;
    case LC_SYMTAB:
      printf ("LC_SYMTAB        ");
      break;
    case LC_DYSYMTAB:
      printf ("LC_DYSYMTAB      ");
      break;
    case LC_UNIXTHREAD:
      printf ("LC_UNIXTHREAD    ");
      break;
    case LC_PREBOUND_DYLIB:
      printf ("LC_PREBOUND_DYLIB");
      break;
    case LC_TWOLEVEL_HINTS:
      printf ("LC_TWOLEVEL_HINTS");
      break;
    default:
      printf ("unknown          ");
    }
}

static void
print_load_command (struct load_command *lc)
{
  print_load_command_name (lc->cmd);
  printf ("%8d", lc->cmdsize);

  if (lc->cmd == LC_SEGMENT)
    {
      struct segment_command *scp;
      struct section *sectp;
      int j;

      scp = (struct segment_command *) lc;
      printf (" %-16.16s %#10x %#8x\n",
	      scp->segname, scp->vmaddr, scp->vmsize);

      sectp = (struct section *) (scp + 1);
      for (j = 0; j < scp->nsects; j++)
	{
	  printf ("                           %-16.16s %#10x %#8x\n",
		  sectp->sectname, sectp->addr, sectp->size);
	  sectp++;
	}
    }
  else
    printf ("\n");
}

/* Read header and load commands from input file.  Store the latter in
   the global array lca.  Store the total number of load commands in
   global variable nlc.  */
static void
read_load_commands ()
{
  int n, i, j;

  if (!unexec_read (&mh, sizeof (struct mach_header)))
    unexec_error ("cannot read mach-o header");

  if (mh.magic != MH_MAGIC)
    unexec_error ("input file not in Mach-O format");

  if (mh.filetype != MH_EXECUTE)
    unexec_error ("input Mach-O file is not an executable object file");

#if VERBOSE
  printf ("--- Header Information ---\n");
  printf ("Magic = 0x%08x\n", mh.magic);
  printf ("CPUType = %d\n", mh.cputype);
  printf ("CPUSubType = %d\n", mh.cpusubtype);
  printf ("FileType = 0x%x\n", mh.filetype);
  printf ("NCmds = %d\n", mh.ncmds);
  printf ("SizeOfCmds = %d\n", mh.sizeofcmds);
  printf ("Flags = 0x%08x\n", mh.flags);
#endif

  nlc = mh.ncmds;
  lca = (struct load_command **) malloc (nlc * sizeof (struct load_command *));

  for (i = 0; i < nlc; i++)
    {
      struct load_command lc;
      /* Load commands are variable-size: so read the command type and
	 size first and then read the rest.  */
      if (!unexec_read (&lc, sizeof (struct load_command)))
        unexec_error ("cannot read load command");
      lca[i] = (struct load_command *) malloc (lc.cmdsize);
      memcpy (lca[i], &lc, sizeof (struct load_command));
      if (!unexec_read (lca[i] + 1, lc.cmdsize - sizeof (struct load_command)))
        unexec_error ("cannot read content of load command");
      if (lc.cmd == LC_SEGMENT)
	{
	  struct segment_command *scp = (struct segment_command *) lca[i];

	  if (scp->vmaddr + scp->vmsize > infile_lc_highest_addr)
	    infile_lc_highest_addr = scp->vmaddr + scp->vmsize;

	  if (strncmp (scp->segname, SEG_TEXT, 16) == 0)
	    {
	      struct section *sectp = (struct section *) (scp + 1);
	      int j;

	      for (j = 0; j < scp->nsects; j++)
		if (sectp->offset < text_seg_lowest_offset)
		  text_seg_lowest_offset = sectp->offset;
	    }
	}
    }

  printf ("Highest address of load commands in input file: %#8x\n",
	  infile_lc_highest_addr);

  printf ("Lowest offset of all sections in __TEXT segment: %#8x\n",
	  text_seg_lowest_offset);

  printf ("--- List of Load Commands in Input File ---\n");
  printf ("# cmd              cmdsize name                address     size\n");

  for (i = 0; i < nlc; i++)
    {
      printf ("%1d ", i);
      print_load_command (lca[i]);
    }
}

/* Copy a LC_SEGMENT load command other than the __DATA segment from
   the input file to the output file, adjusting the file offset of the
   segment and the file offsets of sections contained in it.  */
static void
copy_segment (struct load_command *lc)
{
  struct segment_command *scp = (struct segment_command *) lc;
  unsigned long old_fileoff = scp->fileoff;
  struct section *sectp;
  int j;

  scp->fileoff += delta;

  sectp = (struct section *) (scp + 1);
  for (j = 0; j < scp->nsects; j++)
    {
      sectp->offset += delta;
      sectp++;
    }

  printf ("Writing segment %-16.16s at %#8x - %#8x (sz: %#8x)\n",
	  scp->segname, scp->fileoff, scp->fileoff + scp->filesize,
	  scp->filesize);

  if (!unexec_copy (scp->fileoff, old_fileoff, scp->filesize))
    unexec_error ("cannot copy segment from input to output file");
  if (!unexec_write (curr_header_offset, lc, lc->cmdsize))
    unexec_error ("cannot write load command to header");

  curr_header_offset += lc->cmdsize;
}

/* Copy a LC_SEGMENT load command for the __DATA segment in the input
   file to the output file.  We assume that only one such segment load
   command exists in the input file and it contains the sections
   __data, __bss, __common, __la_symbol_ptr, __nl_symbol_ptr, and
   __dyld.  The first three of these should be dumped from memory and
   the rest should be copied from the input file.  Note that the
   sections __bss and __common contain no data in the input file
   because their flag fields have the value S_ZEROFILL.  Dumping these
   from memory makes it necessary to adjust file offset fields in
   subsequently dumped load commands.  Then, create new __DATA segment
   load commands for regions on the region list other than the one
   corresponding to the __DATA segment in the input file.  */
static void
copy_data_segment (struct load_command *lc)
{
  struct segment_command *scp = (struct segment_command *) lc;
  struct section *sectp;
  int j;
  unsigned long header_offset, file_offset, old_file_offset;
  struct region_t *r;

  printf ("Writing segment %-16.16s at %#8x - %#8x (sz: %#8x)\n",
	  scp->segname, scp->fileoff, scp->fileoff + scp->filesize,
	  scp->filesize);

  if (delta != 0)
    unexec_error ("cannot handle multiple DATA segments in input file");

  /* Offsets in the output file for writing the next section structure
     and segment data block, respectively.  */
  header_offset = curr_header_offset + sizeof (struct segment_command);

  sectp = (struct section *) (scp + 1);
  for (j = 0; j < scp->nsects; j++)
    {
      old_file_offset = sectp->offset;
      sectp->offset = sectp->addr - scp->vmaddr + scp->fileoff;
      /* The __data section is dumped from memory.  The __bss and
	 __common sections are also dumped from memory but their flag
	 fields require changing (from S_ZEROFILL to S_REGULAR).  The
	 other three kinds of sections are just copied from the input
	 file.  */
      if (strncmp (sectp->sectname, SECT_DATA, 16) == 0)
	{
	  if (!unexec_write (sectp->offset, (void *) sectp->addr, sectp->size))
	    unexec_error ("cannot write section %s", SECT_DATA);
	  if (!unexec_write (header_offset, sectp, sizeof (struct section)))
	    unexec_error ("cannot write section %s's header", SECT_DATA);
	}
      else if (strncmp (sectp->sectname, SECT_BSS, 16) == 0
	       || strncmp (sectp->sectname, SECT_COMMON, 16) == 0)
	{
	  sectp->flags = S_REGULAR;
	  if (!unexec_write (sectp->offset, (void *) sectp->addr, sectp->size))
	    unexec_error ("cannot write section %s", SECT_DATA);
	  if (!unexec_write (header_offset, sectp, sizeof (struct section)))
	    unexec_error ("cannot write section %s's header", SECT_DATA);
	}
      else if (strncmp (sectp->sectname, "__la_symbol_ptr", 16) == 0
	       || strncmp (sectp->sectname, "__nl_symbol_ptr", 16) == 0
	       || strncmp (sectp->sectname, "__dyld", 16) == 0
	       || strncmp (sectp->sectname, "__const", 16) == 0)
	{
	  if (!unexec_copy (sectp->offset, old_file_offset, sectp->size))
	    unexec_error ("cannot copy section %s", sectp->sectname);
	  if (!unexec_write (header_offset, sectp, sizeof (struct section)))
	    unexec_error ("cannot write section %s's header", sectp->sectname);
	}
      else
	unexec_error ("unrecognized section name in __DATA segment");

      printf ("        section %-16.16s at %#8x - %#8x (sz: %#8x)\n",
	      sectp->sectname, sectp->offset, sectp->offset + sectp->size,
	      sectp->size);

      header_offset += sizeof (struct section);
      sectp++;
    }

  /* The new filesize of the segment is set to its vmsize because data
     blocks for segments must start at region boundaries.  Note that
     this may leave unused locations at the end of the segment data
     block because the total of the sizes of all sections in the
     segment is generally smaller than vmsize.  */
  delta = scp->vmsize - scp->filesize;
  scp->filesize = scp->vmsize;
  if (!unexec_write (curr_header_offset, scp, sizeof (struct segment_command)))
    unexec_error ("cannot write header of __DATA segment");
  curr_header_offset += lc->cmdsize;

  /* Create new __DATA segment load commands for regions on the region
     list that do not corresponding to any segment load commands in
     the input file.
     */
  file_offset = scp->fileoff + scp->filesize;
  for (j = 0; j < num_unexec_regions; j++)
    {
      struct segment_command sc;

      sc.cmd = LC_SEGMENT;
      sc.cmdsize = sizeof (struct segment_command);
      strncpy (sc.segname, SEG_DATA, 16);
      sc.vmaddr = unexec_regions[j].address;
      sc.vmsize = unexec_regions[j].size;
      sc.fileoff = file_offset;
      sc.filesize = unexec_regions[j].size;
      sc.maxprot = VM_PROT_READ | VM_PROT_WRITE;
      sc.initprot = VM_PROT_READ | VM_PROT_WRITE;
      sc.nsects = 0;
      sc.flags = 0;

      printf ("Writing segment %-16.16s at %#8x - %#8x (sz: %#8x)\n",
	      sc.segname, sc.fileoff, sc.fileoff + sc.filesize,
	      sc.filesize);

      if (!unexec_write (sc.fileoff, (void *) sc.vmaddr, sc.vmsize))
	unexec_error ("cannot write new __DATA segment");
      delta += sc.filesize;
      file_offset += sc.filesize;

      if (!unexec_write (curr_header_offset, &sc, sc.cmdsize))
	unexec_error ("cannot write new __DATA segment's header");
      curr_header_offset += sc.cmdsize;
      mh.ncmds++;
    }
}

/* Copy a LC_SYMTAB load command from the input file to the output
   file, adjusting the file offset fields.  */
static void
copy_symtab (struct load_command *lc)
{
  struct symtab_command *stp = (struct symtab_command *) lc;

  stp->symoff += delta;
  stp->stroff += delta;

  printf ("Writing LC_SYMTAB command\n");

  if (!unexec_write (curr_header_offset, lc, lc->cmdsize))
    unexec_error ("cannot write symtab command to header");

  curr_header_offset += lc->cmdsize;
}

/* Copy a LC_DYSYMTAB load command from the input file to the output
   file, adjusting the file offset fields.  */
static void
copy_dysymtab (struct load_command *lc)
{
  struct dysymtab_command *dstp = (struct dysymtab_command *) lc;

  /* If Mach-O executable is not prebound, relocation entries need
     fixing up.  This is not supported currently.  */
  if (!(mh.flags & MH_PREBOUND) && (dstp->nextrel != 0 || dstp->nlocrel != 0))
    unexec_error ("cannot handle LC_DYSYMTAB with relocation entries");

  if (dstp->nextrel > 0) {
    dstp->extreloff += delta;
  }

  if (dstp->nlocrel > 0) {
    dstp->locreloff += delta;
  }

  if (dstp->nindirectsyms > 0)
    dstp->indirectsymoff += delta;

  printf ("Writing LC_DYSYMTAB command\n");

  if (!unexec_write (curr_header_offset, lc, lc->cmdsize))
    unexec_error ("cannot write symtab command to header");

  curr_header_offset += lc->cmdsize;
}

/* Copy a LC_TWOLEVEL_HINTS load command from the input file to the output
   file, adjusting the file offset fields.  */
static void
copy_twolevelhints (struct load_command *lc)
{
  struct twolevel_hints_command *tlhp = (struct twolevel_hints_command *) lc;

  if (tlhp->nhints > 0) {
    tlhp->offset += delta;
  }

  printf ("Writing LC_TWOLEVEL_HINTS command\n");

  if (!unexec_write (curr_header_offset, lc, lc->cmdsize))
    unexec_error ("cannot write two level hint command to header");

  curr_header_offset += lc->cmdsize;
}

/* Copy other kinds of load commands from the input file to the output
   file, ones that do not require adjustments of file offsets.  */
static void
copy_other (struct load_command *lc)
{
  printf ("Writing ");
  print_load_command_name (lc->cmd);
  printf (" command\n");

  if (!unexec_write (curr_header_offset, lc, lc->cmdsize))
    unexec_error ("cannot write symtab command to header");

  curr_header_offset += lc->cmdsize;
}

/* Loop through all load commands and dump them.  Then write the Mach
   header.  */
static void
dump_it ()
{
  int i;

  printf ("--- Load Commands written to Output File ---\n");

  for (i = 0; i < nlc; i++)
    switch (lca[i]->cmd)
      {
      case LC_SEGMENT:
	{
	  struct segment_command *scp = (struct segment_command *) lca[i];
	  if (strncmp (scp->segname, SEG_DATA, 16) == 0)
	    {
	      copy_data_segment (lca[i]);
	    }
	  else
	    {
	      copy_segment (lca[i]);
	    }
	}
	break;
      case LC_SYMTAB:
	copy_symtab (lca[i]);
	break;
      case LC_DYSYMTAB:
	copy_dysymtab (lca[i]);
	break;
      case LC_TWOLEVEL_HINTS:
	copy_twolevelhints (lca[i]);
	break;
      default:
	copy_other (lca[i]);
	break;
      }

  if (curr_header_offset > text_seg_lowest_offset)
    unexec_error ("not enough room for load commands for new __DATA segments");

  printf ("%d unused bytes follow Mach-O header\n",
	  text_seg_lowest_offset - curr_header_offset);

  mh.sizeofcmds = curr_header_offset - sizeof (struct mach_header);
  if (!unexec_write (0, &mh, sizeof (struct mach_header)))
    unexec_error ("cannot write final header contents");
}

/* Take a snapshot of Emacs and make a Mach-O format executable file
   from it.  The file names of the output and input files are outfile
   and infile, respectively.  The three other parameters are
   ignored.  */
void
unexec (char *outfile, char *infile, void *start_data, void *start_bss,
        void *entry_address)
{
  infd = open (infile, O_RDONLY, 0);
  if (infd < 0)
    {
      unexec_error ("cannot open input file `%s'", infile);
    }

  outfd = open (outfile, O_WRONLY | O_TRUNC | O_CREAT, 0755);
  if (outfd < 0)
    {
      close (infd);
      unexec_error ("cannot open output file `%s'", outfile);
    }

  build_region_list ();
  read_load_commands ();

  find_emacs_zone_regions ();

  in_dumped_exec = 1;

  dump_it ();

  close (outfd);
}


void
unexec_init_emacs_zone ()
{
  emacs_zone = malloc_create_zone (0, 0);
  malloc_set_zone_name (emacs_zone, "EmacsZone");
}

int
ptr_in_unexec_regions (void *ptr)
{
  int i;

  for (i = 0; i < num_unexec_regions; i++)
    if ((vm_address_t) ptr - unexec_regions[i].address
	< unexec_regions[i].size)
      return 1;

  return 0;
}

void *
unexec_malloc (size_t size)
{
  if (in_dumped_exec)
    return malloc (size);
  else
    return malloc_zone_malloc (emacs_zone, size);
}

void *
unexec_realloc (void *old_ptr, size_t new_size)
{
  if (in_dumped_exec)
    if (ptr_in_unexec_regions (old_ptr))
      {
	char *p = malloc (new_size);
	/* 2002-04-15 T. Ikegami <ikegami@adam.uprr.pr>.  The original
	   code to get size failed to reallocate read_buffer
	   (lread.c).  */
	int old_size = malloc_default_zone()->size (emacs_zone, old_ptr);
	int size = new_size > old_size ? old_size : new_size;

	if (size)
	  memcpy (p, old_ptr, size);
	return p;
      }
    else
      return realloc (old_ptr, new_size);
  else
    return malloc_zone_realloc (emacs_zone, old_ptr, new_size);
}

void
unexec_free (void *ptr)
{
  if (in_dumped_exec)
    {
      if (!ptr_in_unexec_regions (ptr))
	free (ptr);
    }
  else
    malloc_zone_free (emacs_zone, ptr);
}
