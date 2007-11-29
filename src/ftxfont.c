/* ftxfont.c -- FreeType font driver on X (without using XFT).
   Copyright (C) 2006 Free Software Foundation, Inc.
   Copyright (C) 2006
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

#include <config.h>
#include <stdio.h>
#include <X11/Xlib.h>

#include "lisp.h"
#include "dispextern.h"
#include "xterm.h"
#include "frame.h"
#include "blockinput.h"
#include "character.h"
#include "charset.h"
#include "fontset.h"
#include "font.h"

/* FTX font driver.  */

static Lisp_Object Qftx;

/* Prototypes for helper function.  */
static GC *ftxfont_get_gcs P_ ((FRAME_PTR, unsigned long, unsigned long));
static int ftxfont_draw_bitmap P_ ((FRAME_PTR, GC, GC *, struct font *,
				    unsigned, int, int, XPoint *, int, int *,
				    int));
static void ftxfont_draw_backgrond P_ ((FRAME_PTR, struct font *, GC,
					int, int, int));
static Font ftxfont_default_fid P_ ((FRAME_PTR));

struct ftxfont_frame_data
{
  /* Background and foreground colors.  */
  XColor colors[2];
  /* GCs interporationg the above colors.  gcs[0] is for a color
   closest to BACKGROUND, and gcs[5] is for a color closest to
   FOREGROUND.  */
  GC gcs[6];
  struct ftxfont_frame_data *next;
};


/* Return an array of 6 GCs for antialiasing.  */

static GC *
ftxfont_get_gcs (f, foreground, background)
     FRAME_PTR f;
     unsigned long foreground, background;
{
  XColor color;
  XGCValues xgcv;
  int i;
  struct ftxfont_frame_data *data = font_get_frame_data (f, &ftxfont_driver);
  struct ftxfont_frame_data *prev = NULL, *this = NULL, *new;

  if (data)
    {
      for (this = data; this; prev = this, this = this->next)
	{
	  if (this->colors[0].pixel < background)
	    continue;
	  if (this->colors[0].pixel > background)
	    break;
	  if (this->colors[1].pixel < foreground)
	    continue;
	  if (this->colors[1].pixel > foreground)
	    break;
	  return this->gcs;
	}
    }

  new = malloc (sizeof (struct ftxfont_frame_data));
  if (! new)
    return NULL;
  new->next = this;
  if (prev)
    {
      prev->next = new;
    }
  else if (font_put_frame_data (f, &ftxfont_driver, new) < 0)
    {
      free (new);
      return NULL;
    }

  new->colors[0].pixel = background;
  new->colors[1].pixel = foreground;

  BLOCK_INPUT;
  XQueryColors (FRAME_X_DISPLAY (f), FRAME_X_COLORMAP (f), new->colors, 2);
  for (i = 1; i < 7; i++)
    {
      /* Interpolate colors linearly.  Any better algorithm?  */
      color.red
	= (new->colors[1].red * i + new->colors[0].red * (8 - i)) / 8;
      color.green
	= (new->colors[1].green * i + new->colors[0].green * (8 - i)) / 8;
      color.blue
	= (new->colors[1].blue * i + new->colors[0].blue * (8 - i)) / 8;
      if (! x_alloc_nearest_color (f, FRAME_X_COLORMAP (f), &color))
	break;
      xgcv.foreground = color.pixel;
      new->gcs[i - 1] = XCreateGC (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f),
				   GCForeground, &xgcv);
    }
  UNBLOCK_INPUT;

  if (i < 7)
    {
      BLOCK_INPUT;
      for (i--; i >= 0; i--)
	XFreeGC (FRAME_X_DISPLAY (f), new->gcs[i]);
      UNBLOCK_INPUT;
      if (prev)
	prev->next = new->next;
      else if (data)
	font_put_frame_data (f, &ftxfont_driver, new->next);
      free (new);
      return NULL;
    }
  return new->gcs;
}

static int
ftxfont_draw_bitmap (f, gc_fore, gcs, font, code, x, y, p, size, n, flush)
     FRAME_PTR f;
     GC gc_fore, *gcs;
     struct font *font;
     unsigned code;
     int x, y;
     XPoint *p;
     int size, *n;
     int flush;
{
  struct font_bitmap bitmap;
  unsigned char *b;
  int i, j;

  if (ftfont_driver.get_bitmap (font, code, &bitmap, size > 0x100 ? 1 : 8) < 0)
    return 0;
  if (size > 0x100)
    {
      for (i = 0, b = bitmap.buffer; i < bitmap.rows;
	   i++, b += bitmap.pitch)
	{
	  for (j = 0; j < bitmap.width; j++)
	    if (b[j / 8] & (1 << (7 - (j % 8))))
	      {
		p[n[0]].x = x + bitmap.left + j;
		p[n[0]].y = y - bitmap.top + i;
		if (++n[0] == size)
		  {
		    XDrawPoints (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f),
				 gc_fore, p, size, CoordModeOrigin);
		    n[0] = 0;
		  }
	      }
	}
      if (flush && n[0] > 0)
	XDrawPoints (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f),
		     gc_fore, p, n[0], CoordModeOrigin);
    }
  else
    {
      for (i = 0, b = bitmap.buffer; i < bitmap.rows;
	   i++, b += bitmap.pitch)
	{
	  for (j = 0; j < bitmap.width; j++)
	    {
	      int idx = (bitmap.bits_per_pixel == 1
			 ? ((b[j / 8] & (1 << (7 - (j % 8)))) ? 6 : -1)
			 : (b[j] >> 5) - 1);

	      if (idx >= 0)
		{
		  XPoint *pp = p + size * idx;

		  pp[n[idx]].x = x + bitmap.left + j;
		  pp[n[idx]].y = y - bitmap.top + i;
		  if (++(n[idx]) == size)
		    {
		      XDrawPoints (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f),
				   idx == 6 ? gc_fore : gcs[idx], pp, size,
				   CoordModeOrigin);
		      n[idx] = 0;
		    }
		}
	    }
	}
      if (flush)
	{
	  for (i = 0; i < 6; i++)
	    if (n[i] > 0)
	      XDrawPoints (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f),
			   gcs[i], p + 0x100 * i, n[i], CoordModeOrigin);
	  if (n[6] > 0)
	    XDrawPoints (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f),
			 gc_fore, p + 0x600, n[6], CoordModeOrigin);
	}
    }

  if (ftfont_driver.free_bitmap)
    ftfont_driver.free_bitmap (font, &bitmap);

  return bitmap.advance;
}

static void
ftxfont_draw_backgrond (f, font, gc, x, y, width)
     FRAME_PTR f;
     struct font *font;
     GC gc;
     int x, y, width;
{
  XGCValues xgcv;

  XGetGCValues (FRAME_X_DISPLAY (f), gc,
		GCForeground | GCBackground, &xgcv);
  XSetForeground (FRAME_X_DISPLAY (f), gc, xgcv.background);
  XFillRectangle (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f), gc,
		  x, y - font->ascent, width, y + font->descent);
  XSetForeground (FRAME_X_DISPLAY (f), gc, xgcv.foreground);
}

/* Return the default Font ID on frame F.  */

static Font
ftxfont_default_fid (f)
     FRAME_PTR f;
{
  static int fid_known;
  static Font fid;

  if (! fid_known)
    {
      fid = XLoadFont (FRAME_X_DISPLAY (f), "fixed");
      if (! fid)
	{
	  fid = XLoadFont (FRAME_X_DISPLAY (f), "*");
	  if (! fid)
	    abort ();
	}
      fid_known = 1;
    }
  return fid;
}

/* Prototypes for font-driver methods.  */
static Lisp_Object ftxfont_list P_ ((Lisp_Object, Lisp_Object));
static Lisp_Object ftxfont_match P_ ((Lisp_Object, Lisp_Object));
static struct font *ftxfont_open P_ ((FRAME_PTR, Lisp_Object, int));
static void ftxfont_close P_ ((FRAME_PTR, struct font *));
static int ftxfont_draw P_ ((struct glyph_string *, int, int, int, int, int));

struct font_driver ftxfont_driver;

static Lisp_Object
ftxfont_list (frame, spec)
     Lisp_Object frame;
     Lisp_Object spec;
{
  Lisp_Object val = ftfont_driver.list (frame, spec);
  
  if (! NILP (val))
    {
      int i;

      for (i = 0; i < ASIZE (val); i++)
	ASET (AREF (val, i), FONT_TYPE_INDEX, Qftx);
    }
  return val;
}

static Lisp_Object
ftxfont_match (frame, spec)
     Lisp_Object frame;
     Lisp_Object spec;
{
  Lisp_Object entity = ftfont_driver.match (frame, spec);

  if (VECTORP (entity))
    ASET (entity, FONT_TYPE_INDEX, Qftx);
  return entity;
}

static struct font *
ftxfont_open (f, entity, pixel_size)
     FRAME_PTR f;
     Lisp_Object entity;
     int pixel_size;
{
  Display_Info *dpyinfo = FRAME_X_DISPLAY_INFO (f);
  struct font *font;
  XFontStruct *xfont = malloc (sizeof (XFontStruct));
  
  if (! xfont)
    return NULL;
  font = ftfont_driver.open (f, entity, pixel_size);
  if (! font)
    {
      free (xfont);
      return NULL;
    }

  xfont->fid = ftxfont_default_fid (f);
  xfont->ascent = font->ascent;
  xfont->descent = font->descent;
  xfont->max_bounds.width = font->font.size;
  xfont->min_bounds.width = font->min_width;
  font->font.font = xfont;
  font->driver = &ftxfont_driver;

  dpyinfo->n_fonts++;

  /* Set global flag fonts_changed_p to non-zero if the font loaded
     has a character with a smaller width than any other character
     before, or if the font loaded has a smaller height than any other
     font loaded before.  If this happens, it will make a glyph matrix
     reallocation necessary.  */
  if (dpyinfo->n_fonts == 1)
    {
      dpyinfo->smallest_font_height = font->font.height;
      dpyinfo->smallest_char_width = font->min_width;
      fonts_changed_p = 1;
    }
  else
    {
      if (dpyinfo->smallest_font_height > font->font.height)
	dpyinfo->smallest_font_height = font->font.height, fonts_changed_p |= 1;
      if (dpyinfo->smallest_char_width > font->min_width)
	dpyinfo->smallest_char_width = font->min_width, fonts_changed_p |= 1;
    }

  return font;
}

static void
ftxfont_close (f, font)
     FRAME_PTR f;
     struct font *font;
{
  ftfont_driver.close (f, font);
  FRAME_X_DISPLAY_INFO (f)->n_fonts--;
}

static int
ftxfont_draw (s, from, to, x, y, with_background)
     struct glyph_string *s;
     int from, to, x, y, with_background;
{
  FRAME_PTR f = s->f;
  struct face *face = s->face;
  struct font *font = (struct font *) face->font_info;
  XPoint p[0x700];
  int n[7];
  unsigned *code;
  int len = to - from;
  int i;
  GC *gcs;

  n[0] = n[1] = n[2] = n[3] = n[4] = n[5] = n[6] = 0;

  BLOCK_INPUT;
  if (with_background)
    ftxfont_draw_backgrond (f, font, s->gc, x, y, s->width);
  code = alloca (sizeof (unsigned) * len);
  for (i = 0; i < len; i++)
    code[i] = ((XCHAR2B_BYTE1 (s->char2b + from + i) << 8)
	       | XCHAR2B_BYTE2 (s->char2b + from + i));

  if (face->gc == s->gc)
    {
      gcs = ftxfont_get_gcs (f, face->foreground, face->background);
    }
  else
    {
      XGCValues xgcv;
      unsigned long mask = GCForeground | GCBackground;

      XGetGCValues (FRAME_X_DISPLAY (f), s->gc, mask, &xgcv);
      gcs = ftxfont_get_gcs (f, xgcv.foreground, xgcv.background);
    }

  if (gcs)
    {
      if (s->num_clips)
	for (i = 0; i < 6; i++)
	  XSetClipRectangles (FRAME_X_DISPLAY (f), gcs[i], 0, 0,
			      s->clip, s->num_clips, Unsorted);

      for (i = 0; i < len; i++)
	x += ftxfont_draw_bitmap (f, s->gc, gcs, font, code[i], x, y,
				  p, 0x100, n, i + 1 == len);
      if (s->num_clips)
	for (i = 0; i < 6; i++)
	  XSetClipMask (FRAME_X_DISPLAY (f), gcs[i], None);
    }
  else
    {
      /* We can't draw with antialiasing.
	 s->gc should already have a proper clipping setting. */
      for (i = 0; i < len; i++)
	x += ftxfont_draw_bitmap (f, s->gc, NULL, font, code[i], x, y,
				  p, 0x700, n, i + 1 == len);
    }

  UNBLOCK_INPUT;

  return len;
}

static int
ftxfont_end_for_frame (f)
     FRAME_PTR f;
{
  struct ftxfont_frame_data *data = font_get_frame_data (f, &ftxfont_driver);
  
  BLOCK_INPUT;
  while (data)
    {
      struct ftxfont_frame_data *next = data->next;
      int i;
      
      for (i = 0; i < 6; i++)
	XFreeGC (FRAME_X_DISPLAY (f), data->gcs[i]);
      free (data);
      data = next;
    }
  UNBLOCK_INPUT;
  return 0;
}



void
syms_of_ftxfont ()
{
  DEFSYM (Qftx, "ftx");

  ftxfont_driver = ftfont_driver;
  ftxfont_driver.type = Qftx;
  ftxfont_driver.list = ftxfont_list;
  ftxfont_driver.match = ftxfont_match;
  ftxfont_driver.open = ftxfont_open;
  ftxfont_driver.close = ftxfont_close;
  ftxfont_driver.draw = ftxfont_draw;
  ftxfont_driver.end_for_frame = ftxfont_end_for_frame;
  register_font_driver (&ftxfont_driver, NULL);
}

/* arch-tag: 59bd3469-5330-413f-b29d-1aa36492abe8
   (do not change this comment) */
