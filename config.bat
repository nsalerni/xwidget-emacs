@echo off
rem   ----------------------------------------------------------------------
rem   Configuration script for MSDOS
rem   Copyright (C) 1994 Free Software Foundation, Inc.

rem   This file is part of GNU Emacs.

rem   GNU Emacs is free software; you can redistribute it and/or modify
rem   it under the terms of the GNU General Public License as published by
rem   the Free Software Foundation; either version 2, or (at your option)
rem   any later version.

rem   GNU Emacs is distributed in the hope that it will be useful,
rem   but WITHOUT ANY WARRANTY; without even the implied warranty of
rem   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
rem   GNU General Public License for more details.

rem   You should have received a copy of the GNU General Public License
rem   along with GNU Emacs; see the file COPYING.  If not, write to
rem   the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
rem   ----------------------------------------------------------------------
rem   YOU'LL NEED THE FOLLOWING UTILITIES TO MAKE EMACS:
rem
rem   + msdos version 3 or better.
rem   + djgpp version 1.12maint1 or later (version 2.0 or later recommended).
rem   + make utility that allows breaking of the 128 chars limit on
rem     command lines.  ndmake (as of version 4.5) won't work due to a
rem     line length limit.  The make that comes with djgpp does work.
rem   + rm and mv (from GNU file utilities).
rem   + sed (you can use the port that comes with DJGPP).
rem
rem   You should be able to get all the above utilities from any SimTel
rem   repository, e.g. ftp.coast.net, in the directories
rem   "SimTel/vendors/djgpp" and "SimTel/vendors/gnu/gnuish/dos_only".  As
rem   usual, please use your local mirroring site to reduce trans-Atlantic
rem   traffic.
rem   ----------------------------------------------------------------------
set X11=
set nodebug=
set djgpp_ver=
:again
if "%1" == "" goto usage
if "%1" == "--with-x" goto withx
if "%1" == "--no-debug" goto nodebug
if "%1" == "msdos" goto msdos
:usage
echo Usage: config [--with-x] [--no-debug] msdos
echo [Read the script before you run it.]
goto end
rem   ----------------------------------------------------------------------
:withx
set X11=Y
shift
goto again
rem   ----------------------------------------------------------------------
:nodebug
set nodebug=Y
shift
goto again
rem   ----------------------------------------------------------------------
:msdos
Echo Checking whether 'sed' is available...
sed -e "w junk.$$$" <Nul
If Exist junk.$$$ Goto sedOk
Echo To configure 'Emacs' you need to have 'sed'!
Goto End
:sedOk
Echo Checking whether 'rm' is available...
rm -f junk.$$$
If Not Exist junk.$$$ Goto rmOk
Echo To configure 'Emacs' you need to have 'rm'!
Goto End
:rmOk
Echo Checking whether 'mv' is available...
rm -f junk.1 junk.2
echo foo >junk.1
mv junk.1 junk.2
If Exist junk.2 Goto mvOk
Echo To configure 'Emacs' you need to have 'mv'!
rm -f junk.1
Goto End
:mvOk
rm -f junk.2
Echo Checking whether 'gcc' is available...
echo main(){} >junk.c
gcc -c junk.c
if exist junk.o goto gccOk
Echo To configure 'Emacs' you need to have 'gcc'!
rm -f junk.c
Goto End
:gccOk
rm -f junk.c junk.o
Echo Checking what version of DJGPP is installed...
If Not "%DJGPP%" == "" goto djgppOk
Echo To compile 'Emacs' under MS-DOS you MUST have DJGPP installed!
Goto End
:djgppOk
echo int main()           >junk.c
echo #ifdef __DJGPP__    >>junk.c
echo {return (__DJGPP__)*10;} >>junk.c
echo #else               >>junk.c
echo #ifdef __GO32__     >>junk.c
echo {return 10;}         >>junk.c
echo #else               >>junk.c
echo {return 0;}         >>junk.c
echo #endif              >>junk.c
echo #endif              >>junk.c
gcc -o junk.exe junk.c
junk
If ErrorLevel 10 Goto go32Ok
rm -f junk.c junk junk.exe
Echo To compile 'Emacs' under MS-DOS you MUST have DJGPP installed!
Goto End
:go32Ok
set djgpp_ver=1
If ErrorLevel 20 set djgpp_ver=2
rm -f junk.c junk junk.exe
Echo Configuring for DJGPP Version %DJGPP_VER% ...
Rem   ----------------------------------------------------------------------
Echo Configuring the source directory...
cd src

rem   Create "paths.h"
sed -f ../msdos/sed4.inp <paths.in >paths.tmp
update paths.tmp paths.h >nul
rm -f paths.tmp

rem   Create "config.h"
rm -f config.h2 config.tmp
cp config.in config.tmp
if "%X11%" == "" goto src4
sed -f ../msdos/sed2x.inp <config.in >config.tmp
:src4
sed -f ../msdos/sed2.inp <config.tmp >config.h2
update config.h2 config.h >nul
rm -f config.tmp config.h2

rem   On my system dir.h gets in the way.  It's a VMS file so who cares.
if exist dir.h ren dir.h vmsdir.h

rem   Create "makefile" from "makefile.in".
rm -f makefile junk.c
sed -e "1,/cpp stuff/s@^# .*$@@" <makefile.in >junk.c
If "%DJGPP_VER%" == "1" Goto mfV1
gcc -E junk.c | sed -f ../msdos/sed1v2.inp >makefile
goto mfDone
:mfV1
gcc -E junk.c | sed -f ../msdos/sed1.inp >makefile
:mfDone
rm -f junk.c

if "%X11%" == "" goto src5
mv makefile makefile.tmp
sed -f ../msdos/sed1x.inp <makefile.tmp >makefile
rm -f makefile.tmp
:src5

if "%nodebug%" == "" goto src6
sed -e "/^CFLAGS *=/s/ *-g//" <makefile >makefile.tmp
sed -e "/^LDFLAGS *=/s/=/=-s/" <makefile.tmp >makefile
rm -f makefile.tmp
:src6
cd ..
rem   ----------------------------------------------------------------------
Echo Configuring the library source directory...
cd lib-src
rem   Create "makefile" from "makefile.in".
sed -e "1,/cpp stuff/s@^# .*$@@" <makefile.in >junk.c
gcc -E -I. -I../src junk.c | sed -e "s/^ /	/" -e "/^#/d" -e "/^[ 	]*$/d" >makefile.new
If "%DJGPP_VER%" == "2" goto libsrc-v2
sed -f ../msdos/sed3.inp <makefile.new >makefile
Goto libsrc2
:libsrc-v2
sed -f ../msdos/sed3v2.inp <makefile.new >makefile
:libsrc2
rm -f makefile.new junk.c
if "%nodebug%" == "" goto libsrc3
sed -e "/^CFLAGS *=/s/ *-g//" <makefile >makefile.tmp
sed -e "/^ALL_CFLAGS *=/s/=/= -s/" <makefile.tmp >makefile
rm -f makefile.tmp
:libsrc3
cd ..
rem   ----------------------------------------------------------------------
if "%X11%" == "" goto oldx1
Echo Configuring the oldxmenu directory...
cd oldxmenu
sed -f ../msdos/sed5x.inp <makefile.in >makefile
if "%nodebug%" == "" goto oldx2
sed -e "/^CFLAGS *=/s/ *-g//" <makefile >makefile.tmp
mv -f makefile.tmp makefile
:oldx2
cd ..
:oldx1
rem   ----------------------------------------------------------------------
Echo Configuring the main directory...
If "%DJGPP_VER%" == "2" copy msdos\mainmake.v2 makefile >nul
If "%DJGPP_VER%" == "1" copy msdos\mainmake makefile >nul
rem   ----------------------------------------------------------------------
:end
set X11=
set nodebug=
set djgpp_ver=
