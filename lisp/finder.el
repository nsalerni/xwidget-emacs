;;; finder.el --- topic & keyword-based code finder

;; Copyright (C) 1992 Free Software Foundation, Inc.

;; Author: Eric S. Raymond <esr@snark.thyrsus.com>
;; Created: 16 Jun 1992
;; Version: 1.0
;; Keywords: help

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 1, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

;; Commentary:

;; This mode uses the Keywords library header to provide code-finding
;; services by keyword.
;;
;; Things to do:
;;    1. Support multiple keywords per search.  This could be extremely hairy;
;; there doesn't seem to be any way to get completing-read to exit on
;; an EOL with no substring pending, which is what we'd want to end the loop.
;;    2. Search by string in synopsis line?
;;    3. Function to check finder-package-info for unknown keywords.

;;; Code:

(require 'lisp-mnt)
(require 'finder-inf)
(require 'picture)

(defvar finder-known-keywords
  '(
    (abbrev	. "abbreviation handling, typing shortcuts, macros")
    (bib	. "code related to the bib(1) bibliography processor")
    (c		. "C and C++ language support")
    (calendar	. "calendar and time management support")
    (comm	. "communications, networking, remote access to files")
    (docs	. "support for Emacs documentation")
    (emulations	. "emulations of other editors")
    (extensions	. "Emacs Lisp language extensions")
    (games	. "games, jokes and amusements")
    (hardware	. "support for interfacing with exotic hardware")
    (help	. "support for on-line help systems")
    (i14n	. "internationalization and alternate character-set support")
    (internal	. "code for Emacs internals, build process, defaults")
    (languages	. "specialized modes for editing programming languages")
    (lisp	. "Lisp support, including Emacs Lisp")
    (local	. "code local to your site")
    (maint	. "maintenance aids for the Emacs development group")
    (mail	. "modes for electronic-mail handling")
    (news	. "support for netnews reading and posting")
    (processes	. "process, subshell, compilation, and job control support")
    (terminals	. "support for terminal types")
    (tex	. "code related to the TeX formatter")
    (tools	. "programming tools")
    (unix	. "front-ends/assistants for, or emulators of, UNIX features")
    (vms	. "support code for vms")
    (wp		. "word processing")
    ))

;;; Code for regenerating the keyword list.

(defvar finder-package-info nil
  "Assoc list mapping file names to description & keyword lists.")

(defun finder-compile-keywords (&rest dirs)
  "Regenerate the keywords association list into the file finder-inf.el.
Optional arguments are a list of Emacs Lisp directories to compile from; no
arguments compiles from `load-path'."
  (save-excursion
    (let ((processed nil))
      (find-file "finder-inf.el")
      (erase-buffer)
      (insert ";;; finder-inf.el --- keyword-to-package mapping\n")
      (insert ";; Keywords: help\n")
      (insert ";;; Commentary:\n")
      (insert ";; Don't edit this file.  It's generated by finder.el\n\n")
      (insert ";;; Code:\n")
      (insert "\n(setq finder-package-info '(\n")
      (mapcar
       (function
	(lambda (d)
	  (mapcar
	   (function
	    (lambda (f) 
	      (if (and (string-match "\\.el$" f) (not (member f processed)))
		  (let (summary keystart)
		    (setq processed (cons f processed))
		    (save-excursion
		      (set-buffer (get-buffer-create "*finder-scratch*"))
		      (erase-buffer)
		      (insert-file-contents
		       (concat (file-name-as-directory (or d ".")) f))
		      (setq summary (lm-synopsis))
		      (setq keywords (lm-keywords)))
		    (insert
		     (format "    (\"%s\"\n        " f))
		    (prin1 summary (current-buffer))
		    (insert
		     "\n        ")
		    (setq keystart (point))
		    (insert
		     (if keywords (format "(%s)" keywords) "nil")
		     ")\n")
		    (subst-char-in-region keystart (point) ?, ? )
		    )
		)))
	   (directory-files (or d ".")))
	  ))
       (or dirs load-path))
      (insert "))\n\n(provide 'finder-inf)\n\n;;; finder-inf.el ends here\n")
      (kill-buffer "*finder-scratch*")
      (eval-current-buffer) ;; So we get the new keyword list immediately
      (basic-save-buffer)
      )))

;;; Now the retrieval code

(defun finder-by-keyword ()
  "Find packages matching a given keyword."
  (interactive)
  (pop-to-buffer "*Help*")
  (erase-buffer)
  (mapcar
   (function (lambda (x)
	       (insert (symbol-name (car x)))
	       (insert-at-column 14 (cdr x) "\n")
	       ))
   finder-known-keywords)
  (goto-char (point-min))
  (let (key
	(known (mapcar (function (lambda (x) (car x))) finder-known-keywords)))
    (let ((key (completing-read
		"Package keyword: "
		(vconcat known)
		(function (lambda (arg) (memq arg known)))
		t))
	  id)
      (erase-buffer)
      (if (equal key "")
	  (delete-window (get-buffer-window "*Help*"))
	(setq id (intern key))
	(insert
	 "The following packages match the keyword `" key "':\n\n")
	(mapcar
	 (function (lambda (x)
		     (if (memq id (car (cdr (cdr x))))
			 (progn
			   (insert (car x))
			   (insert-at-column 16 (car (cdr x)) "\n")
			   ))
		     ))
	 finder-package-info)
	(goto-char (point-min))
	))))

(provide 'finder)

;;; finder.el ends here
