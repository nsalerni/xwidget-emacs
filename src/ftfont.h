/* ftfont.h -- Interface definition for Freetype font backend.
   Copyright (C) 2007
     National Institute of Advanced Industrial Science and Technology (AIST)
     Registration Number H13PRO009

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
the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA.  */

#ifndef EMACS_FTFONT_H
#define EMACS_FTFONT_H

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_SIZES_H

#ifdef HAVE_LIBOTF
#include <otf.h>
#ifdef HAVE_M17N_FLT
#include <m17n-flt.h>
extern Lisp_Object ftfont_shape_by_flt P_ ((Lisp_Object, struct font *,
					    FT_Face, OTF *));
#endif	/* HAVE_LIBOTF */
#endif	/* HAVE_M17N_FLT */

#endif	/* EMACS_FTFONT_H */

/* arch-tag: cec13d1c-7156-4997-9ebd-e989040c3d78
   (do not change this comment) */
