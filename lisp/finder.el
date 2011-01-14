;;; finder.el --- topic & keyword-based code finder

;; Copyright (C) 1992, 1997, 1998, 1999, 2001, 2002, 2003, 2004, 2005,
;;   2006, 2007, 2008, 2009, 2010, 2011  Free Software Foundation, Inc.

;; Author: Eric S. Raymond <esr@snark.thyrsus.com>
;; Created: 16 Jun 1992
;; Version: 1.0
;; Keywords: help

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This mode uses the Keywords library header to provide code-finding
;; services by keyword.

;;; Code:

(require 'package)
(require 'lisp-mnt)
(require 'find-func) ;for find-library(-suffixes)
(require 'finder-inf nil t)

;; These are supposed to correspond to top-level customization groups,
;; says rms.
(defvar finder-known-keywords
  '((abbrev	. "abbreviation handling, typing shortcuts, and macros")
    (bib	. "bibliography processors")
    (c		. "C and related programming languages")
    (calendar	. "calendar and time management tools")
    (comm	. "communications, networking, and remote file access")
    (convenience . "convenience features for faster editing")
    (data	. "editing data (non-text) files")
    (docs	. "Emacs documentation facilities")
    (emulations	. "emulations of other editors")
    (extensions	. "Emacs Lisp language extensions")
    (faces	. "fonts and colors for text")
    (files      . "file editing and manipulation")
    (frames     . "Emacs frames and window systems")
    (games	. "games, jokes and amusements")
    (hardware	. "interfacing with system hardware")
    (help	. "on-line help systems")
    (hypermedia . "links between text or other media types")
    (i18n	. "internationalization and character-set support")
    (internal	. "code for Emacs internals, build process, defaults")
    (languages	. "specialized modes for editing programming languages")
    (lisp	. "Lisp support, including Emacs Lisp")
    (local	. "code local to your site")
    (maint	. "Emacs development tools and aids")
    (mail	. "email reading and posting")
    (matching	. "searching, matching, and sorting")
    (mouse	. "mouse support")
    (multimedia . "images and sound")
    (news	. "USENET news reading and posting")
    (outlines   . "hierarchical outlining and note taking")
    (processes	. "processes, subshells, and compilation")
    (terminals	. "text terminals (ttys)")
    (tex	. "the TeX document formatter")
    (tools	. "programming tools")
    (unix	. "UNIX feature interfaces and emulators")
    (vc		. "version control")
    (wp		. "word processing")))

(defvar finder-mode-map
  (let ((map (make-sparse-keymap))
	(menu-map (make-sparse-keymap "Finder")))
    (define-key map " "	'finder-select)
    (define-key map "f"	'finder-select)
    (define-key map [follow-link] 'mouse-face)
    (define-key map [mouse-2]	'finder-mouse-select)
    (define-key map "\C-m"	'finder-select)
    (define-key map "?"	'finder-summary)
    (define-key map "n" 'next-line)
    (define-key map "p" 'previous-line)
    (define-key map "q"	'finder-exit)
    (define-key map "d"	'finder-list-keywords)

    (define-key map [menu-bar finder-mode]
      (cons "Finder" menu-map))
    (define-key menu-map [finder-exit]
      '(menu-item "Quit" finder-exit
		  :help "Exit Finder mode"))
    (define-key menu-map [finder-summary]
      '(menu-item "Summary" finder-summary
		  :help "Summary item on current line in a finder buffer"))
    (define-key menu-map [finder-list-keywords]
      '(menu-item "List keywords" finder-list-keywords
		  :help "Display descriptions of the keywords in the Finder buffer"))
    (define-key menu-map [finder-select]
      '(menu-item "Select" finder-select
		  :help "Select item on current line in a finder buffer"))
    map))

(defvar finder-mode-syntax-table
  (let ((st (make-syntax-table emacs-lisp-mode-syntax-table)))
    (modify-syntax-entry ?\; ".   " st)
    st)
  "Syntax table used while in `finder-mode'.")

(defvar finder-font-lock-keywords
  '(("`\\([^'`]+\\)'" 1 font-lock-constant-face prepend))
  "Font-lock keywords for Finder mode.")

(defvar finder-headmark nil
  "Internal finder-mode variable, local in finder buffer.")

;;; Code for regenerating the keyword list.

(defvar finder-keywords-hash nil
  "Hash table mapping keywords to lists of package names.
Keywords and package names both should be symbols.")

(defvar generated-finder-keywords-file "finder-inf.el"
  "The function `finder-compile-keywords' writes keywords into this file.")

;; Skip autogenerated files, because they will never contain anything
;; useful, and because in parallel builds of Emacs they may get
;; modified while we are trying to read them.
;; http://lists.gnu.org/archive/html/emacs-pretest-bug/2007-01/msg00469.html
;; ldefs-boot is not auto-generated, but has nothing useful.
(defvar finder-no-scan-regexp "\\(^\\.#\\|\\(loaddefs\\|ldefs-boot\\|\
cus-load\\|finder-inf\\|esh-groups\\|subdirs\\)\\.el$\\)"
  "Regexp matching file names not to scan for keywords.")

(autoload 'autoload-rubric "autoload")

(defvar finder--builtins-alist
  '(("calc" . calc)
    ("ede"  . ede)
    ("erc"  . erc)
    ("eshell" . eshell)
    ("gnus" . gnus)
    ("international" . emacs)
    ("language" . emacs)
    ("mh-e" . mh-e)
    ("semantic" . semantic)
    ("analyze" . semantic)
    ("bovine" . semantic)
    ("decorate" . semantic)
    ("symref" . semantic)
    ("wisent" . semantic)
    ("nxml" . nxml)
    ("org"  . org)
    ("srecode" . srecode)
    ("term" . emacs)
    ("url"  . url))
  "Alist of built-in package directories.
Each element should have the form (DIR . PACKAGE), where DIR is a
directory name and PACKAGE is the name of a package (a symbol).
When generating `package--builtins', Emacs assumes any file in
DIR is part of the package PACKAGE.")

(defun finder-compile-keywords (&rest dirs)
  "Regenerate list of built-in Emacs packages.
This recomputes `package--builtins' and `finder-keywords-hash',
and prints them into the file `generated-finder-keywords-file'.

Optional DIRS is a list of Emacs Lisp directories to compile
from; the default is `load-path'."
  ;; Allow compressed files also.
  (setq package--builtins nil)
  (setq finder-keywords-hash (make-hash-table :test 'eq))
  (let ((el-file-regexp "^\\([^=].*\\)\\.el\\(\\.\\(gz\\|Z\\)\\)?$")
	package-override files base-name processed
	summary keywords package version entry desc)
    (dolist (d (or dirs load-path))
      (when (file-exists-p (directory-file-name d))
	(message "Directory %s" d)
	(setq package-override
	      (intern-soft
	       (cdr-safe
		(assoc (file-name-nondirectory (directory-file-name d))
		       finder--builtins-alist))))
	(setq files (directory-files d nil el-file-regexp))
	(dolist (f files)
	  (unless (or (string-match finder-no-scan-regexp f)
		      (null (setq base-name
				  (and (string-match el-file-regexp f)
				       (intern (match-string 1 f)))))
		      (memq base-name processed))
	    (push base-name processed)
	    (with-temp-buffer
	      (insert-file-contents (expand-file-name f d))
	      (setq summary  (lm-synopsis)
		    keywords (mapcar 'intern (lm-keywords-list))
		    package  (or package-override
				 (let ((str (lm-header "package")))
				   (if str (intern str)))
				 base-name)
		    version  (lm-header "version")))
	    (when summary
	      (setq version (ignore-errors (version-to-list version)))
	      (setq entry (assq package package--builtins))
	      (cond ((null entry)
		     (push (cons package (vector version nil summary))
			   package--builtins))
		    ((eq base-name package)
		     (setq desc (cdr entry))
		     (aset desc 0 version)
		     (aset desc 2 summary)))
	      (dolist (kw keywords)
		(puthash kw
			 (cons package
			       (delq package
				     (gethash kw finder-keywords-hash)))
			 finder-keywords-hash))))))))

  (setq package--builtins
	(sort package--builtins
	      (lambda (a b) (string< (symbol-name (car a))
				     (symbol-name (car b))))))

  (save-excursion
    (find-file generated-finder-keywords-file)
    (setq buffer-undo-list t)
    (erase-buffer)
    (insert (autoload-rubric generated-finder-keywords-file
                             "keyword-to-package mapping" t))
    (search-backward "")
    (insert "(setq package--builtins '(\n")
    (dolist (package package--builtins)
      (insert "  ")
      (prin1 package (current-buffer))
      (insert "\n"))
    (insert "))\n\n")
    ;; Insert hash table.
    (insert "(setq finder-keywords-hash\n      ")
    (prin1 finder-keywords-hash (current-buffer))
    (insert ")\n")
    (basic-save-buffer)))

(defun finder-compile-keywords-make-dist ()
  "Regenerate `finder-inf.el' for the Emacs distribution."
  (apply 'finder-compile-keywords command-line-args-left)
  (kill-emacs))

;;; Now the retrieval code

(defun finder-insert-at-column (column &rest strings)
  "Insert, at column COLUMN, other args STRINGS."
  (if (>= (current-column) column) (insert "\n"))
  (move-to-column column t)
  (apply 'insert strings))

(defvar finder-help-echo nil)

(defun finder-mouse-face-on-line ()
  "Put `mouse-face' and `help-echo' properties on the previous line."
  (save-excursion
    (forward-line -1)
    ;; If finder-insert-at-column moved us to a new line, go back one more.
    (if (looking-at "[ \t]") (forward-line -1))
    (unless finder-help-echo
      (setq finder-help-echo
	    (let* ((keys1 (where-is-internal 'finder-select
					     finder-mode-map))
		   (keys (nconc (where-is-internal
				 'finder-mouse-select finder-mode-map)
				keys1)))
	      (concat (mapconcat 'key-description keys ", ")
		      ": select item"))))
    (add-text-properties
     (line-beginning-position) (line-end-position)
     '(mouse-face highlight
		  help-echo finder-help-echo))))

(defun finder-unknown-keywords ()
  "Return an alist of unknown keywords and number of their occurrences.
Unknown keywords are those present in `finder-keywords-hash' but
not `finder-known-keywords'."
  (let (alist)
    (maphash (lambda (kw packages)
	       (unless (assq kw finder-known-keywords)
		 (push (cons kw (length packages)) alist)))
	     finder-keywords-hash)
    (sort alist (lambda (a b) (string< (car a) (car b))))))

;;;###autoload
(defun finder-list-keywords ()
  "Display descriptions of the keywords in the Finder buffer."
  (interactive)
  (if (get-buffer "*Finder*")
      (pop-to-buffer "*Finder*")
    (pop-to-buffer (get-buffer-create "*Finder*"))
    (finder-mode)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (dolist (assoc finder-known-keywords)
	(let ((keyword (car assoc)))
	  (insert (propertize (symbol-name keyword)
			      'font-lock-face 'font-lock-constant-face))
	  (finder-insert-at-column 14 (concat (cdr assoc) "\n"))
	  (finder-mouse-face-on-line)))
      (goto-char (point-min))
      (setq finder-headmark (point)
	    buffer-read-only t)
      (set-buffer-modified-p nil)
      (balance-windows)
      (finder-summary))))

(defun finder-list-matches (key)
  (let* ((id (intern key))
	 (packages (gethash id finder-keywords-hash)))
    (unless packages
      (error "No packages matching key `%s'" key))
    (package--list-packages packages)))

(define-button-type 'finder-xref 'action #'finder-goto-xref)

(defun finder-goto-xref (button)
  "Jump to a lisp file for the BUTTON at point."
  (let* ((file (button-get button 'xref))
         (lib (locate-library file)))
    (if lib (finder-commentary lib)
      (message "Unable to locate `%s'" file))))

;;;###autoload
(defun finder-commentary (file)
  "Display FILE's commentary section.
FILE should be in a form suitable for passing to `locate-library'."
  (interactive
   (list
    (completing-read "Library name: "
		     (apply-partially 'locate-file-completion-table
                                      (or find-function-source-path load-path)
                                      (find-library-suffixes)))))
  (let ((str (lm-commentary (find-library-name file))))
    (or str (error "Can't find any Commentary section"))
    ;; This used to use *Finder* but that would clobber the
    ;; directory of categories.
    (pop-to-buffer "*Finder-package*")
    (setq buffer-read-only nil
          buffer-undo-list t)
    (erase-buffer)
    (insert str)
    (goto-char (point-min))
    (delete-blank-lines)
    (goto-char (point-max))
    (delete-blank-lines)
    (goto-char (point-min))
    (while (re-search-forward "^;+ ?" nil t)
      (replace-match "" nil nil))
    (goto-char (point-min))
    (while (re-search-forward "\\<\\([-[:alnum:]]+\\.el\\)\\>" nil t)
      (if (locate-library (match-string 1))
          (make-text-button (match-beginning 1) (match-end 1)
                            'xref (match-string-no-properties 1)
                            'help-echo "Read this file's commentary"
                            :type 'finder-xref)))
    (goto-char (point-min))
    (setq buffer-read-only t)
    (set-buffer-modified-p nil)
    (shrink-window-if-larger-than-buffer)
    (finder-mode)
    (finder-summary)))

(defun finder-current-item ()
  (let ((key (save-excursion
	       (beginning-of-line)
	       (current-word))))
    (if (or (and finder-headmark (< (point) finder-headmark))
	    (zerop (length key)))
	(error "No keyword or filename on this line")
      key)))

(defun finder-select ()
  "Select item on current line in a finder buffer."
  (interactive)
  (let ((key (finder-current-item)))
      (if (string-match "\\.el$" key)
	  (finder-commentary key)
	(finder-list-matches key))))

(defun finder-mouse-select (event)
  "Select item in a finder buffer with the mouse."
  (interactive "e")
  (with-current-buffer (window-buffer (posn-window (event-start event)))
    (goto-char (posn-point (event-start event)))
    (finder-select)))

;;;###autoload
(defun finder-by-keyword ()
  "Find packages matching a given keyword."
  (interactive)
  (finder-list-keywords))

(define-derived-mode finder-mode nil "Finder"
  "Major mode for browsing package documentation.
\\<finder-mode-map>
\\[finder-select]	more help for the item on the current line
\\[finder-exit]	exit Finder mode and kill the Finder buffer."
  :syntax-table finder-mode-syntax-table
  (setq buffer-read-only t
	buffer-undo-list t)
  (set (make-local-variable 'finder-headmark) nil))

(defun finder-summary ()
  "Summarize basic Finder commands."
  (interactive)
  (message "%s"
   (substitute-command-keys
    "\\<finder-mode-map>\\[finder-select] = select, \
\\[finder-mouse-select] = select, \\[finder-list-keywords] = to \
finder directory, \\[finder-exit] = quit, \\[finder-summary] = help")))

(defun finder-exit ()
  "Exit Finder mode.
Delete the window and kill all Finder-related buffers."
  (interactive)
  (ignore-errors (delete-window))
  (let ((buf "*Finder*"))
    (and (get-buffer buf) (kill-buffer buf))))


(provide 'finder)

;; arch-tag: ec85ff49-8cb8-41f5-a63f-9131d53ce2c5
;;; finder.el ends here
