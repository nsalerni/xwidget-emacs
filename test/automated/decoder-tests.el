;;; decoder-tests.el --- test for text decoder

;; Copyright (C) 2013 Free Software Foundation, Inc.

;; Author: Kenichi Handa <handa@gnu.org>

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

;;; Code:

(require 'ert)

;;; Check ASCII optimizing decoder

;; Directory to hold test data files.
(defvar decoder-tests-workdir
  (expand-file-name "decoder-tests" temporary-file-directory))

;; Return the contents (specified by CONTENT-TYPE; ascii, latin, or
;; binary) of a test file.
(defun decoder-tests-file-contents (content-type)
  (let* ((ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZ\n")
	 (latin (concat ascii "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏ\n"))
	 (binary (string-to-multibyte
		  (concat (string-as-unibyte latin)
			  (unibyte-string #xC0 #xC1 ?\n)))))
    (cond ((eq content-type 'ascii) ascii)
	  ((eq content-type 'latin) latin)
	  ((eq content-type 'binary) binary)
	  (t
	   (error "Invalid file content type: %s" content-type)))))

;; Return the name of test file whose contents specified by
;; CONTENT-TYPE and whose encoding specified by CODING-SYSTEM.
(defun decoder-tests-filename (content-type coding-system)
  (expand-file-name (format "%s-%s" content-type coding-system)
		    decoder-tests-workdir))

;; Generate a test file whose contents specified by CONTENT-TYPE and
;; whose encoding specified by CODING-SYSTEM.
(defun decoder-tests-gen-file (content-type coding-system)
  (or (file-directory-p decoder-tests-workdir)
      (mkdir decoder-tests-workdir t))
  (let ((file (decoder-tests-filename content-type coding-system)))
    (with-temp-file file
      (set-buffer-file-coding-system coding-system)
      (insert (decoder-tests-file-contents content-type)))))

;; Remove all generated test files.
(defun decoder-tests-remove-files ()
  (delete-directory decoder-tests-workdir t))

;;; The following three functions are filters for contents of a test
;;; file.

;; Convert all LFs to CR LF sequences in the string STR.
(defun decoder-tests-lf-to-crlf (str)
  (with-temp-buffer
    (insert str)
    (goto-char (point-min))
    (while (search-forward "\n" nil t)
      (delete-char -1)
      (insert "\r\n"))
    (buffer-string)))

;; Convert all LFs to CRs in the string STR.
(defun decoder-tests-lf-to-cr (str)
  (with-temp-buffer
    (insert str)
    (subst-char-in-region (point-min) (point-max) ?\n ?\r)
    (buffer-string)))

;; Convert all LFs to LF LF sequences in the string STR.
(defun decoder-tests-lf-to-lflf (str)
  (with-temp-buffer
    (insert str)
    (goto-char (point-min))
    (while (search-forward "\n" nil t)
      (insert "\n"))
    (buffer-string)))

;; Prepend the UTF-8 BOM to STR.
(defun decoder-tests-add-bom (str)
  (concat "\xfeff" str))

;; Test the decoding of a file whose contents and encoding are
;; specified by CONTENT-TYPE and WRITE-CODING.  The test passes if the
;; file is read by READ-CODING and detected as DETECTED-CODING and the
;; contents is correctly decoded.
;; Optional 5th arg TRANSLATOR is a function to translate the original
;; file contents to match with the expected result of decoding.  For
;; instance, when a file of dos eol-type is read by unix eol-type,
;; `decode-test-lf-to-crlf' must be specified.

(defun decoder-tests (content-type write-coding read-coding detected-coding
				   &optional translator)
  (prefer-coding-system 'utf-8-auto)
  (let ((filename (decoder-tests-filename content-type write-coding)))
    (with-temp-buffer
      (let ((coding-system-for-read read-coding)
	    (contents (decoder-tests-file-contents content-type))
	    (disable-ascii-optimization nil))
	(if translator
	    (setq contents (funcall translator contents)))
	(insert-file-contents filename)
	(if (and (coding-system-equal buffer-file-coding-system detected-coding)
		 (string= (buffer-string) contents))
	    nil
	  (list buffer-file-coding-system
		(string-to-list (buffer-string))
		(string-to-list contents)))))))

(ert-deftest ert-test-decoder-ascii ()
  (unwind-protect
      (progn
	(dolist (eol-type '(unix dos mac))
	  (decoder-tests-gen-file 'ascii eol-type))
	(should-not (decoder-tests 'ascii 'unix 'undecided 'unix))
	(should-not (decoder-tests 'ascii 'dos 'undecided 'dos))
	(should-not (decoder-tests 'ascii 'dos 'dos 'dos))
	(should-not (decoder-tests 'ascii 'mac 'undecided 'mac))
	(should-not (decoder-tests 'ascii 'mac 'mac 'mac))
	(should-not (decoder-tests 'ascii 'dos 'utf-8 'utf-8-dos))
	(should-not (decoder-tests 'ascii 'dos 'unix 'unix
				   'decoder-tests-lf-to-crlf))
	(should-not (decoder-tests 'ascii 'mac 'dos 'dos
				   'decoder-tests-lf-to-cr))
	(should-not (decoder-tests 'ascii 'dos 'mac 'mac
				   'decoder-tests-lf-to-lflf)))
    (decoder-tests-remove-files)))

(ert-deftest ert-test-decoder-latin ()
  (unwind-protect
      (progn
	(dolist (coding '("utf-8" "utf-8-with-signature"))
	  (dolist (eol-type '("unix" "dos" "mac"))
	    (decoder-tests-gen-file 'latin
				    (intern (concat coding "-" eol-type)))))
	(should-not (decoder-tests 'latin 'utf-8-unix 'undecided 'utf-8-unix))
	(should-not (decoder-tests 'latin 'utf-8-unix 'utf-8-unix 'utf-8-unix))
	(should-not (decoder-tests 'latin 'utf-8-dos 'undecided 'utf-8-dos))
	(should-not (decoder-tests 'latin 'utf-8-dos 'utf-8-dos 'utf-8-dos))
	(should-not (decoder-tests 'latin 'utf-8-mac 'undecided 'utf-8-mac))
	(should-not (decoder-tests 'latin 'utf-8-mac 'utf-8-mac 'utf-8-mac))
	(should-not (decoder-tests 'latin 'utf-8-dos 'unix 'utf-8-unix
				   'decoder-tests-lf-to-crlf))
	(should-not (decoder-tests 'latin 'utf-8-mac 'dos 'utf-8-dos
				   'decoder-tests-lf-to-cr))
	(should-not (decoder-tests 'latin 'utf-8-dos 'mac 'utf-8-mac
				   'decoder-tests-lf-to-lflf))
	(should-not (decoder-tests 'latin 'utf-8-with-signature-unix 'undecided
				   'utf-8-with-signature-unix))
	(should-not (decoder-tests 'latin 'utf-8-with-signature-unix 'utf-8-auto
				   'utf-8-with-signature-unix))
	(should-not (decoder-tests 'latin 'utf-8-with-signature-dos 'undecided
				   'utf-8-with-signature-dos))
	(should-not (decoder-tests 'latin 'utf-8-with-signature-unix 'utf-8
				   'utf-8-unix 'decoder-tests-add-bom))
	(should-not (decoder-tests 'latin 'utf-8-with-signature-unix 'utf-8
				   'utf-8-unix 'decoder-tests-add-bom)))
    (decoder-tests-remove-files)))

(ert-deftest ert-test-decoder-binary ()
  (unwind-protect
      (progn
	(dolist (eol-type '("unix" "dos" "mac"))
	  (decoder-tests-gen-file 'binary
				  (intern (concat "raw-text" "-" eol-type))))
	(should-not (decoder-tests 'binary 'raw-text-unix 'undecided
				   'raw-text-unix))
	(should-not (decoder-tests 'binary 'raw-text-dos 'undecided
				   'raw-text-dos))
	(should-not (decoder-tests 'binary 'raw-text-mac 'undecided
				   'raw-text-mac))
	(should-not (decoder-tests 'binary 'raw-text-dos 'unix
				   'raw-text-unix 'decoder-tests-lf-to-crlf))
	(should-not (decoder-tests 'binary 'raw-text-mac 'dos
				   'raw-text-dos 'decoder-tests-lf-to-cr))
	(should-not (decoder-tests 'binary 'raw-text-dos 'mac
				   'raw-text-mac 'decoder-tests-lf-to-lflf)))
    (decoder-tests-remove-files)))



;;; The following is for benchmark testing of the new optimized
;;; decoder, not for regression testing.

(defun generate-ascii-file ()
  (dotimes (i 100000)
    (insert-char ?a 80)
    (insert "\n")))

(defun generate-rarely-nonascii-file ()
  (dotimes (i 100000)
    (if (/= i 50000)
	(insert-char ?a 80)
      (insert ?À)
      (insert-char ?a 79))
    (insert "\n")))

(defun generate-mostly-nonascii-file ()
  (dotimes (i 30000)
    (insert-char ?a 80)
    (insert "\n"))
  (dotimes (i 20000)
    (insert-char ?À 80)
    (insert "\n"))
  (dotimes (i 10000)
    (insert-char ?あ 80)
    (insert "\n")))


(defvar test-file-list
  '((generate-ascii-file
     ("~/ascii-tag-utf-8-unix.unix" ";; -*- coding: utf-8-unix; -*-" unix)
     ("~/ascii-tag-utf-8.unix" ";; -*- coding: utf-8; -*-" unix)
     ("~/ascii-tag-none.unix" "" unix)
     ("~/ascii-tag-utf-8-dos.dos" ";; -*- coding: utf-8-dos; -*-" dos)
     ("~/ascii-tag-utf-8.dos" ";; -*- coding: utf-8; -*-" dos)
     ("~/ascii-tag-none.dos" "" dos))
    (generate-rarely-nonascii-file
     ("~/utf-8-r-tag-utf-8-unix.unix" ";; -*- coding: utf-8-unix; -*-" utf-8-unix)
     ("~/utf-8-r-tag-utf-8.unix" ";; -*- coding: utf-8; -*-" utf-8-unix)
     ("~/utf-8-r-tag-none.unix" "" utf-8-unix)
     ("~/utf-8-r-tag-utf-8-dos.dos" ";; -*- coding: utf-8-dos; -*-" utf-8-dos)
     ("~/utf-8-r-tag-utf-8.dos" ";; -*- coding: utf-8; -*-" utf-8-dos)
     ("~/utf-8-r-tag-none.dos" "" utf-8-dos))
    (generate-mostly-nonascii-file
     ("~/utf-8-m-tag-utf-8-unix.unix" ";; -*- coding: utf-8-unix; -*-" utf-8-unix)
     ("~/utf-8-m-tag-utf-8.unix" ";; -*- coding: utf-8; -*-" utf-8-unix)
     ("~/utf-8-m-tag-none.unix" "" utf-8-unix)
     ("~/utf-8-m-tag-utf-8-dos.dos" ";; -*- coding: utf-8-dos; -*-" utf-8-dos)
     ("~/utf-8-m-tag-utf-8.dos" ";; -*- coding: utf-8; -*-" utf-8-dos)
     ("~/utf-8-m-tag-none.dos" "" utf-8-dos))))

(defun generate-benchmark-test-file ()
  (interactive)
  (with-temp-buffer
    (message "Generating data...")
    (dolist (files test-file-list)
      (delete-region (point-min) (point-max))
      (funcall (car files))
      (dolist (file (cdr files))
	(message "Writing %s..." (car file))
	(goto-char (point-min))
	(insert (nth 1 file) "\n")
	(let ((coding-system-for-write (nth 2 file)))
	  (write-region (point-min) (point-max) (car file)))
	(delete-region (point-min) (point))))))

(defun benchmark-decoder ()
  (let ((gc-cons-threshold 4000000))
    (insert "Without optimization:\n")
    (dolist (files test-file-list)
      (dolist (file (cdr files))
	(let* ((disable-ascii-optimization t)
	       (result (benchmark-run 10
			 (with-temp-buffer (insert-file-contents (car file))))))
	  (insert (format "%s: %s\n"  (car file) result)))))
    (insert "With optimization:\n")
    (dolist (files test-file-list)
      (dolist (file (cdr files))
	(let* ((disable-ascii-optimization nil)
	       (result (benchmark-run 10
			 (with-temp-buffer (insert-file-contents (car file))))))
	  (insert (format "%s: %s\n" (car file) result)))))))
