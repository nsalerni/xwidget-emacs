;;; log-view.el --- Major mode for browsing CVS log output

;; Copyright (C) 1999-2000  Free Software Foundation, Inc.

;; Author: Stefan Monnier <monnier@cs.yale.edu>
;; Keywords: pcl-cvs cvs log
;; Version: $Name:  $
;; Revision: $Id: log-view.el,v 1.1 2000/03/11 03:42:28 monnier Exp $

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Todo:

;; - add compatibility with cvs-log.el
;; - add ability to modify a log-entry (via cvs-mode-admin ;-)

;;; Code:

(eval-when-compile (require 'cl))
;;(require 'pcvs-defs)
(require 'pcvs-util)


(defgroup log-view nil
  "Major mode for browsing log output for PCL-CVS."
  :group 'pcl-cvs
  :prefix "log-view-")

(easy-mmode-defmap log-view-mode-map
  '(("n" . log-view-msg-next)
    ("p" . log-view-msg-prev)
    ("N" . log-view-file-next)
    ("P" . log-view-file-prev)
    ("M-n" . log-view-file-next)
    ("M-p" . log-view-file-prev))
  "Log-View's keymap."
  :group 'log-view
  :inherit 'cvs-mode-map)

(defvar log-view-mode-hook nil
  "Hook run at the end of `log-view-mode'.")

(defface log-view-file-face
  '((((class color) (background light))
     (:background "grey70" :bold t))
    (t (:bold t)))
  "Face for the file header line in `log-view-mode'."
  :group 'log-view)
(defvar log-view-file-face 'log-view-file-face)

(defface log-view-message-face
  '((((class color) (background light))
     (:background "grey85"))
    (t (:bold t)))
  "Face for the message header line in `log-view-mode'."
  :group 'log-view)
(defvar log-view-message-face 'log-view-message-face)

(defconst log-view-file-re
  (concat "^\\("
	  "Working file: \\(.+\\)"
	  "\\|SCCS/s\\.\\(.+\\):"
	  "\\)\n"))
(defconst log-view-message-re "^\\(revision \\([.0-9]+\\)\\|D \\([.0-9]+\\) .*\\)$")

(defconst log-view-font-lock-keywords
  `((,log-view-file-re
     (2 'cvs-filename-face nil t)
     (3 'cvs-filename-face nil t)
     (0 'log-view-file-face append))
    (,log-view-message-re . log-view-message-face)))
(defconst log-view-font-lock-defaults
  '(log-view-font-lock-keywords t nil nil nil))

;;;; 
;;;; Actual code
;;;; 

;;;###autoload
(define-derived-mode log-view-mode fundamental-mode "Log-View"
  "Major mode for browsing CVS log output."
  (set (make-local-variable 'font-lock-defaults) log-view-font-lock-defaults)
  (set (make-local-variable 'cvs-minor-wrap-function) 'log-view-minor-wrap))

;;;;
;;;; Navigation
;;;;

;; define log-view-{msg,file}-{next,prev}
(easy-mmode-define-navigation log-view-msg log-view-message-re "log message")
(easy-mmode-define-navigation log-view-file log-view-file-re "file")

;;;;
;;;; Linkage to PCL-CVS (mostly copied from cvs-status.el)
;;;;

(defconst log-view-dir-re "^cvs[.ex]* [a-z]+: Logging \\(.+\\)$")

(defun log-view-current-file ()
  (save-excursion
    (forward-line 1)
    (or (re-search-backward log-view-file-re nil t)
	(re-search-forward log-view-file-re))
    (let* ((file (or (match-string 2) (match-string 3)))
	   (cvsdir (and (re-search-backward log-view-dir-re nil t)
			(match-string 1)))
	   (pcldir (and (re-search-backward cvs-pcl-cvs-dirchange-re nil t)
			(match-string 1)))
	   (dir ""))
      (let ((default-directory ""))
	(when pcldir (setq dir (expand-file-name pcldir dir)))
	(when cvsdir (setq dir (expand-file-name cvsdir dir)))
	(expand-file-name file dir)))))

(defun log-view-current-tag ()
  (save-excursion
    (forward-line 1)
    (let ((pt (point)))
      (when (re-search-backward log-view-message-re nil t)
	(let ((rev (or (match-string 2) (match-string 3))))
	  (unless (re-search-forward log-view-file-re pt t)
	    rev))))))

(defun log-view-minor-wrap (buf f)
  (let ((data (with-current-buffer buf
		(cons
		 (cons (log-view-current-file)
		       (log-view-current-tag))
		 (when (ignore-errors (mark))
		   ;; `mark-active' is not provided by XEmacs :-(
		   (save-excursion
		     (goto-char (mark))
		     (cons (log-view-current-file)
			   (log-view-current-tag))))))))
    (let ((cvs-branch-prefix (cdar data))
	  (cvs-secondary-branch-prefix (and (cdar data) (cddr data)))
	  (cvs-minor-current-files
	   (cons (caar data)
		 (when (and (cadr data) (not (equal (caar data) (cadr data))))
		   (list (cadr data)))))
	  ;; FIXME:  I need to force because the fileinfos are UNKNOWN
	  (cvs-force-command "/F"))
      (funcall f))))

(provide 'log-view)

;;; Change Log:
;; $Log$

;;; log-view.el ends here
