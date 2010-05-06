/* R2 AIX machine/system dependent defines
   Copyright (C) 1988, 2001, 2002, 2003, 2004, 2005, 2006, 2007,
                 2008, 2009, 2010  Free Software Foundation, Inc.

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


/* The following line tells the configuration script what sort of
   operating system this machine is likely to run.
   USUAL-OPSYS="aix3-1"  */

/* Now define a symbol for the cpu type, if your compiler
   does not define it automatically.  */

/* The data segment in this machine always starts at address 0x20000000.
   An address of data cannot be stored correctly in a Lisp object;
   we always lose the high bits.  We must tell XPNTR to add them back.  */

#define TEXT_START 0x10000000
#define DATA_START 0x20000000
#define WORDS_BIG_ENDIAN
#define DATA_SEG_BITS 0x20000000

#ifndef NLIST_STRUCT
/* AIX supposedly doesn't use this interface, but on the RS/6000
   it apparently does.  */
#define NLIST_STRUCT
#endif

#undef ADDR_CORRECT
#define ADDR_CORRECT(x) ((int)(x))

#define START_FILES
/*** BUILD 9008 - FIONREAD problem still exists in X-Windows. ***/
#define BROKEN_FIONREAD
/* As we define BROKEN_FIONREAD, SIGIO will be undefined in systty.h.
   But, on AIX, SIGAIO, SIGPTY, and SIGPOLL are defined as SIGIO,
   which causes compilation error at init_signals in sysdep.c.  So, we
   define these macros so that syssignal.h detects them and undefine
   SIGAIO, SIGPTY and SIGPOLL.  */
#define BROKEN_SIGAIO
#define BROKEN_SIGPTY
#define BROKEN_SIGPOLL

/* arch-tag: 028318ee-a7ae-4a08-804d-cc1e6588d003
   (do not change this comment) */
