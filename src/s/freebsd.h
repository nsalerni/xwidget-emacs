/* System description header for FreeBSD systems.
   This file describes the parameters that system description files
   should define or not.
   Copyright (C) 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002,
                 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010
                 Free Software Foundation, Inc.

Author: Shawn M. Carey
(according to authors.el)

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.  */

/* Get most of the stuff from bsd-common */
#include "bsd-common.h"

/* For mem-limits.h. */
#define BSD4_2

#define PENDING_OUTPUT_COUNT(FILE) ((FILE)->_p - (FILE)->_bf._base)

#define LIBS_SYSTEM -lutil
#if __FreeBSD_version < 400000
#define LIBS_TERMCAP -ltermcap
#else
#define TERMINFO
#define LIBS_TERMCAP -lncurses
#endif

/* Let `ld' find image libs and similar things in /usr/local/lib.  The
   system compiler, GCC, has apparently been modified to not look
   there, contrary to what a stock GCC would do.  */

#define LD_SWITCH_SYSTEM  -L/usr/local/lib
#define START_FILES pre-crt0.o /usr/lib/crt1.o /usr/lib/crti.o /usr/lib/crtbegin.o
#define LIB_STANDARD -lgcc -lc -lgcc /usr/lib/crtend.o /usr/lib/crtn.o
#undef LIB_GCC
#define LIB_GCC

#define HAVE_GETLOADAVG 1
#define DECLARE_GETPWUID_WITH_UID_T

/* this silences a few compilation warnings */
#undef BSD_SYSTEM
#if __FreeBSD__ == 1
#define BSD_SYSTEM 199103
#elif __FreeBSD__ == 2
#define BSD_SYSTEM 199306
#elif __FreeBSD__ >= 3
#define BSD_SYSTEM 199506
#endif

/* Don't close pty in process.c to make it as controlling terminal.
   It is already a controlling terminal of subprocess, because we did
   ioctl TIOCSCTTY.  */
#define DONT_REOPEN_PTY

/* The following is needed to make `configure' find Xpm, Xaw3d and
   image include and library files if using /usr/bin/gcc.  That
   compiler seems to be modified to not find headers in
   /usr/local/include or libs in /usr/local/lib by default.  */

#define C_SWITCH_SYSTEM -I/usr/X11R6/include -I/usr/local/include -L/usr/local/lib

/* Circumvent a bug in FreeBSD.  In the following sequence of
   writes/reads on a PTY, read(2) returns bogus data:

   write(2)  1022 bytes
   write(2)   954 bytes, get EAGAIN
   read(2)   1024 bytes in process_read_output
   read(2)     11 bytes in process_read_output

   That is, read(2) returns more bytes than have ever been written
   successfully.  The 1033 bytes read are the 1022 bytes written
   successfully after processing (for example with CRs added if the
   terminal is set up that way which it is here).  The same bytes will
   be seen again in a later read(2), without the CRs.  */

#define BROKEN_PTY_READ_AFTER_EAGAIN 1

/* Tell that garbage collector that setjmp is known to save all
   registers relevant for conservative garbage collection in the
   jmp_buf.  */

#define GC_SETJMP_WORKS 1

/* Use the GC_MAKE_GCPROS_NOOPS (see lisp.h) method for marking the
   stack.  */

#define GC_MARK_STACK 	GC_MAKE_GCPROS_NOOPS

/* Define USE_MMAP_FOR_BUFFERS to let Emacs use mmap(2) to allocate
   buffer text.  This overrides REL_ALLOC.  */

#define USE_MMAP_FOR_BUFFERS	1

/* Use sigprocmask(2) and friends instead of sigblock(2); the man page
   of sigblock says it is obsolete.  */

#define POSIX_SIGNALS		1

/* The `combreloc' setting became the default, and it seems to be
   incompatible with unexec.  Symptom is an immediate SEGV in
   XtInitializeWidget when starting Emacs under X11.  */

#if defined __FreeBSD_version && __FreeBSD_version >= 500042
#define LD_SWITCH_SYSTEM_TEMACS -znocombreloc
#endif

/* arch-tag: 426529ca-b7c4-448f-b10a-d4dcdc9c78eb
   (do not change this comment) */
