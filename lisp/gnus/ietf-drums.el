;;; ietf-drums.el --- functions for parsing RFC822bis headers
;; Copyright (C) 1998, 1999, 2000, 2002
;;        Free Software Foundation, Inc.

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>
;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; DRUMS is an IETF Working Group that works (or worked) on the
;; successor to RFC822, "Standard For The Format Of Arpa Internet Text
;; Messages".  This library is based on
;; draft-ietf-drums-msg-fmt-05.txt, released on 1998-08-05.

;;; Code:

(eval-when-compile (require 'cl))
(require 'time-date)
(require 'mm-util)

(defvar ietf-drums-no-ws-ctl-token "\001-\010\013\014\016-\037\177"
  "US-ASCII control characters excluding CR, LF and white space.")
(defvar ietf-drums-text-token "\001-\011\013\014\016-\177"
  "US-ASCII characters excluding CR and LF.")
(defvar ietf-drums-specials-token "()<>[]:;@\\,.\""
  "Special characters.")
(defvar ietf-drums-quote-token "\\"
  "Quote character.")
(defvar ietf-drums-wsp-token " \t"
  "White space.")
(defvar ietf-drums-fws-regexp
  (concat "[" ietf-drums-wsp-token "]*\n[" ietf-drums-wsp-token "]+")
  "Folding white space.")
(defvar ietf-drums-atext-token "-^a-zA-Z0-9!#$%&'*+/=?_`{|}~"
  "Textual token.")
(defvar ietf-drums-dot-atext-token "-^a-zA-Z0-9!#$%&'*+/=?_`{|}~."
  "Textual token including full stop.")
(defvar ietf-drums-qtext-token
  (concat ietf-drums-no-ws-ctl-token "\041\043-\133\135-\177")
  "Non-white-space control characters, plus the rest of ASCII excluding
backslash and doublequote.")
(defvar ietf-drums-tspecials "][()<>@,;:\\\"/?="
  "Tspecials.")

(defvar ietf-drums-syntax-table
  (let ((table (copy-syntax-table emacs-lisp-mode-syntax-table)))
    (modify-syntax-entry ?\\ "/" table)
    (modify-syntax-entry ?< "(" table)
    (modify-syntax-entry ?> ")" table)
    (modify-syntax-entry ?@ "w" table)
    (modify-syntax-entry ?/ "w" table)
    (modify-syntax-entry ?= " " table)
    (modify-syntax-entry ?* " " table)
    (modify-syntax-entry ?\; " " table)
    (modify-syntax-entry ?\' " " table)
    table))

(defun ietf-drums-token-to-list (token)
  "Translate TOKEN into a list of characters."
  (let ((i 0)
	b e c out range)
    (while (< i (length token))
      (setq c (mm-char-int (aref token i)))
      (incf i)
      (cond
       ((eq c (mm-char-int ?-))
	(if b
	    (setq range t)
	  (push c out)))
       (range
	(while (<= b c)
	  (push (mm-make-char 'ascii b) out)
	  (incf b))
	(setq range nil))
       ((= i (length token))
	(push (mm-make-char 'ascii c) out))
       (t
	(when b
	  (push (mm-make-char 'ascii b) out))
	(setq b c))))
    (nreverse out)))

(defsubst ietf-drums-init (string)
  (set-syntax-table ietf-drums-syntax-table)
  (insert string)
  (ietf-drums-unfold-fws)
  (goto-char (point-min)))

(defun ietf-drums-remove-comments (string)
  "Remove comments from STRING."
  (with-temp-buffer
    (let (c)
      (ietf-drums-init string)
      (while (not (eobp))
	(setq c (char-after))
	(cond
	 ((eq c ?\")
	  (forward-sexp 1))
	 ((eq c ?\()
	  (delete-region (point) (progn (forward-sexp 1) (point))))
	 (t
	  (forward-char 1))))
      (buffer-string))))

(defun ietf-drums-remove-whitespace (string)
  "Remove whitespace from STRING."
  (with-temp-buffer
    (ietf-drums-init string)
    (let (c)
      (while (not (eobp))
	(setq c (char-after))
	(cond
	 ((eq c ?\")
	  (forward-sexp 1))
	 ((eq c ?\()
	  (forward-sexp 1))
	 ((memq c '(?\  ?\t ?\n))
	  (delete-char 1))
	 (t
	  (forward-char 1))))
      (buffer-string))))

(defun ietf-drums-get-comment (string)
  "Return the first comment in STRING."
  (with-temp-buffer
    (ietf-drums-init string)
    (let (result c)
      (while (not (eobp))
	(setq c (char-after))
	(cond
	 ((eq c ?\")
	  (forward-sexp 1))
	 ((eq c ?\()
	  (setq result
		(buffer-substring
		 (1+ (point))
		 (progn (forward-sexp 1) (1- (point))))))
	 (t
	  (forward-char 1))))
      result)))

(defun ietf-drums-strip (string)
  "Remove comments and whitespace from STRING."
  (ietf-drums-remove-whitespace (ietf-drums-remove-comments string)))

(defun ietf-drums-parse-address (string)
  "Parse STRING and return a MAILBOX / DISPLAY-NAME pair."
  (with-temp-buffer
    (let (display-name mailbox c display-string)
      (ietf-drums-init string)
      (while (not (eobp))
	(setq c (char-after))
	(cond
	 ((or (eq c ? )
	      (eq c ?\t))
	  (forward-char 1))
	 ((eq c ?\()
	  (forward-sexp 1))
	 ((eq c ?\")
	  (push (buffer-substring
		 (1+ (point)) (progn (forward-sexp 1) (1- (point))))
		display-name))
	 ((looking-at (concat "[" ietf-drums-atext-token "@" "]"))
	  (push (buffer-substring (point) (progn (forward-sexp 1) (point)))
		display-name))
	 ((eq c ?<)
	  (setq mailbox
		(ietf-drums-remove-whitespace
		 (ietf-drums-remove-comments
		  (buffer-substring
		   (1+ (point))
		   (progn (forward-sexp 1) (1- (point))))))))
	 (t (error "Unknown symbol: %c" c))))
      ;; If we found no display-name, then we look for comments.
      (if display-name
	  (setq display-string
		(mapconcat 'identity (reverse display-name) " "))
	(setq display-string (ietf-drums-get-comment string)))
      (if (not mailbox)
	  (when (string-match "@" display-string)
	    (cons
	     (mapconcat 'identity (nreverse display-name) "")
	     (ietf-drums-get-comment string)))
	(cons mailbox display-string)))))

(defun ietf-drums-parse-addresses (string)
  "Parse STRING and return a list of MAILBOX / DISPLAY-NAME pairs."
  (with-temp-buffer
    (ietf-drums-init string)
    (let ((beg (point))
	  pairs c)
      (while (not (eobp))
	(setq c (char-after))
	(cond
	 ((memq c '(?\" ?< ?\())
	  (forward-sexp 1))
	 ((eq c ?,)
	  (push (ietf-drums-parse-address (buffer-substring beg (point)))
		pairs)
	  (forward-char 1)
	  (setq beg (point)))
	 (t
	  (forward-char 1))))
      (push (ietf-drums-parse-address (buffer-substring beg (point)))
	    pairs)
      (nreverse pairs))))

(defun ietf-drums-unfold-fws ()
  "Unfold folding white space in the current buffer."
  (goto-char (point-min))
  (while (re-search-forward ietf-drums-fws-regexp nil t)
    (replace-match " " t t))
  (goto-char (point-min)))

(defun ietf-drums-parse-date (string)
  "Return an Emacs time spec from STRING."
  (apply 'encode-time (parse-time-string string)))

(defun ietf-drums-narrow-to-header ()
  "Narrow to the header section in the current buffer."
  (narrow-to-region
   (goto-char (point-min))
   (if (re-search-forward "^\r?$" nil 1)
       (match-beginning 0)
     (point-max)))
  (goto-char (point-min)))

(defun ietf-drums-quote-string (string)
  "Quote string if it needs quoting to be displayed in a header."
  (if (string-match (concat "[^" ietf-drums-atext-token "]") string)
      (concat "\"" string "\"")
    string))

(provide 'ietf-drums)

;;; ietf-drums.el ends here
