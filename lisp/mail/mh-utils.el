;;; mh-utils.el --- MH-E code needed for both sending and reading

;; Copyright (C) 1993, 1995, 1997, 2000, 2001, 2002 Free Software Foundation, Inc.

;; Author: Bill Wohler <wohler@newt.com>
;; Maintainer: Bill Wohler <wohler@newt.com>
;; Keywords: mail
;; See: mh-e.el

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

;; Internal support for MH-E package.

;;; Change Log:

;; $Id: mh-utils.el,v 1.193 2003/01/08 00:27:31 satyaki Exp $

;;; Code:

;; Is this XEmacs-land? Located here since needed by mh-customize.el.
(defvar mh-xemacs-flag (featurep 'xemacs)
  "Non-nil means the current Emacs is XEmacs.")

(require 'cl)
(require 'gnus-util)
(require 'font-lock)
(require 'mh-loaddefs)
(require 'mh-customize)

(load "mm-decode" t t)                  ; Non-fatal dependency
(load "mm-view" t t)                    ; Non-fatal dependency
(load "executable" t t)                 ; Non-fatal dependency on
                                        ; executable-find

;; Shush the byte-compiler
(defvar font-lock-auto-fontify)
(defvar font-lock-defaults)
(defvar mark-active)
(defvar tool-bar-mode)

;;; Autoloads
(autoload 'gnus-article-highlight-citation "gnus-cite")
(autoload 'mail-header-end "sendmail")
(autoload 'Info-goto-node "info")
(unless (fboundp 'make-hash-table)
  (autoload 'make-hash-table "cl"))

;;; Set for local environment:
;;; mh-progs and mh-lib used to be set in paths.el, which tried to
;;; figure out at build time which of several possible directories MH
;;; was installed into.  But if you installed MH after building Emacs,
;;; this would almost certainly be wrong, so now we do it at run time.

(defvar mh-progs nil
  "Directory containing MH commands, such as inc, repl, and rmm.")

(defvar mh-lib nil
  "Directory containing the MH library.
This directory contains, among other things, the components file.")

(defvar mh-lib-progs nil
  "Directory containing MH helper programs.
This directory contains, among other things, the mhl program.")

(defvar mh-nmh-flag nil
  "Non-nil means nmh is installed on this system instead of MH.")

;;;###autoload
(put 'mh-progs 'risky-local-variable t)
;;;###autoload
(put 'mh-lib 'risky-local-variable t)
;;;###autoload
(put 'mh-lib-progs 'risky-local-variable t)
;;;###autoload
(put 'mh-nmh-flag 'risky-local-variable t)

;;; CL Replacements
(defun mh-search-from-end (char string)
  "Return the position of last occurrence of CHAR in STRING.
If CHAR is not present in STRING then return nil. The function is used in lieu
of `search' in the CL package."
  (loop for index from (1- (length string)) downto 0
        when (equal (aref string index) char) return index
        finally return nil))

;;; Macro to generate correct code for different emacs variants

(defmacro mh-mark-active-p (check-transient-mark-mode-flag)
  "A macro that expands into appropriate code in XEmacs and nil in GNU Emacs.
In GNU Emacs if CHECK-TRANSIENT-MARK-MODE-FLAG is non-nil then check if
variable `transient-mark-mode' is active."
  (cond (mh-xemacs-flag                 ;XEmacs
         `(and (boundp 'zmacs-regions) zmacs-regions (region-active-p)))
        ((not check-transient-mark-mode-flag) ;GNU Emacs
         `(and (boundp 'mark-active) mark-active))
        (t                              ;GNU Emacs
         `(and (boundp 'transient-mark-mode) transient-mark-mode
               (boundp 'mark-active) mark-active))))

;;; Additional header fields that might someday be added:
;;; "Sender: " "Reply-to: "

(defvar mh-scan-msg-number-regexp "^ *\\([0-9]+\\)"
  "Regexp to find the number of a message in a scan line.
The message's number must be surrounded with \\( \\)")

(defvar mh-scan-msg-overflow-regexp "^\\?[0-9]"
  "Regexp to find a scan line in which the message number overflowed.
The message's number is left truncated in this case.")

(defvar mh-scan-msg-format-regexp "%\\([0-9]*\\)(msg)"
  "Regexp to find message number width in an scan format.
The message number width must be surrounded with \\( \\).")

(defvar mh-scan-msg-format-string "%d"
  "Format string for width of the message number in a scan format.
Use `0%d' for zero-filled message numbers.")

(defvar mh-scan-msg-search-regexp "^[^0-9]*%d[^0-9]"
  "Format string containing a regexp matching the scan listing for a message.
The desired message's number will be an argument to format.")

(defvar mh-default-folder-for-message-function nil
  "Function to select a default folder for refiling or Fcc.
If set to a function, that function is called with no arguments by
`\\[mh-refile-msg]' and `\\[mh-to-fcc]' to get a default when
prompting the user for a folder.  The function is called from within a
`save-excursion', with point at the start of the message.  It should
return the folder to offer as the refile or Fcc folder, as a string
with a leading `+' sign.  It can also return an empty string to use no
default, or nil to calculate the default the usual way.
NOTE: This variable is not an ordinary hook;
It may not be a list of functions.")

(defvar mh-show-buffer-mode-line-buffer-id "{show-%s} %d"
  "Format string to produce `mode-line-buffer-identification' for show buffers.
First argument is folder name.  Second is message number.")

(defvar mh-cmd-note 4
  "Column to insert notation.
Use `mh-set-cmd-note' to modify it.
This value may be dynamically updated if `mh-adaptive-cmd-note-flag' is
non-nil and `mh-scan-format-file' is t.
Note that the first column is column number 0.")
(make-variable-buffer-local 'mh-cmd-note)

(defvar mh-note-seq "%"
  "String whose first character is used to notate messages in a sequence.")

(defvar mh-mail-header-separator "--------"
  "*Line used by MH to separate headers from text in messages being composed.
This variable should not be used directly in programs. Programs should use
`mail-header-separator' instead. `mail-header-separator' is initialized to
`mh-mail-header-separator' in `mh-letter-mode'; in other contexts, you may
have to perform this initialization yourself.

Do not make this a regexp as it may be the argument to `insert' and it is
passed through `regexp-quote' before being used by functions like
`re-search-forward'.")

;; Variables for MIME display

;; Structure to keep track of MIME handles on a per buffer basis.
(defstruct (mh-buffer-data (:conc-name mh-mime-)
                           (:constructor mh-make-buffer-data))
  (handles ())                          ; List of MIME handles
  (handles-cache (make-hash-table))     ; Cache to avoid multiple decodes of
                                        ; nested messages
  (parts-count 0)                       ; The button number is generated from
                                        ; this number
  (part-index-hash (make-hash-table)))  ; Avoid incrementing the part number
                                        ; for nested messages
;;; This has to be a macro, since we do: (setf (mh-buffer-data) ...)
(defmacro mh-buffer-data ()
  "Convenience macro to get the MIME data structures of the current buffer."
  `(gethash (current-buffer) mh-globals-hash))

(defvar mh-globals-hash (make-hash-table)
  "Keeps track of MIME data on a per buffer basis.")

(defvar mh-gnus-pgp-support-flag (not (not (locate-library "mml2015")))
  "Non-nil means installed Gnus has PGP support.")

(defvar mh-mm-inline-media-tests
  `(("image/jpeg"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'jpeg handle)))
    ("image/png"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'png handle)))
    ("image/gif"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'gif handle)))
    ("image/tiff"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'tiff handle)) )
    ("image/xbm"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'xbm handle)))
    ("image/x-xbitmap"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'xbm handle)))
    ("image/xpm"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'xpm handle)))
    ("image/x-pixmap"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'xpm handle)))
    ("image/bmp"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'bmp handle)))
    ("image/x-portable-bitmap"
     mm-inline-image
     (lambda (handle)
       (mm-valid-and-fit-image-p 'pbm handle)))
    ("text/plain" mm-inline-text identity)
    ("text/enriched" mm-inline-text identity)
    ("text/richtext" mm-inline-text identity)
    ("text/x-patch" mm-display-patch-inline
     (lambda (handle)
       (locate-library "diff-mode")))
    ("application/emacs-lisp" mm-display-elisp-inline identity)
    ("application/x-emacs-lisp" mm-display-elisp-inline identity)
    ("text/html"
     ,(if (fboundp 'mm-inline-text-html) 'mm-inline-text-html 'mm-inline-text)
     (lambda (handle)
       (or (and (boundp 'mm-inline-text-html-renderer)
                mm-inline-text-html-renderer)
           (and (boundp 'mm-text-html-renderer) mm-text-html-renderer))))
    ("text/x-vcard"
     mm-inline-text-vcard
     (lambda (handle)
       (or (featurep 'vcard)
           (locate-library "vcard"))))
    ("message/delivery-status" mm-inline-text identity)
    ("message/rfc822" mh-mm-inline-message identity)
    ;;("message/partial" mm-inline-partial identity)
    ;;("message/external-body" mm-inline-external-body identity)
    ("text/.*" mm-inline-text identity)
    ("audio/wav" mm-inline-audio
     (lambda (handle)
       (and (or (featurep 'nas-sound) (featurep 'native-sound))
            (device-sound-enabled-p))))
    ("audio/au"
     mm-inline-audio
     (lambda (handle)
       (and (or (featurep 'nas-sound) (featurep 'native-sound))
            (device-sound-enabled-p))))
    ("application/pgp-signature" ignore identity)
    ("application/x-pkcs7-signature" ignore identity)
    ("application/pkcs7-signature" ignore identity)
    ("application/x-pkcs7-mime" ignore identity)
    ("application/pkcs7-mime" ignore identity)
    ("multipart/alternative" ignore identity)
    ("multipart/mixed" ignore identity)
    ("multipart/related" ignore identity)
    ;; Disable audio and image
    ("audio/.*" ignore ignore)
    ("image/.*" ignore ignore)
    ;; Default to displaying as text
    (".*" mm-inline-text mm-readable-p))
  "Alist of media types/tests saying whether types can be displayed inline.")

;; Needed by mh-comp.el and mh-mime.el
(defvar mh-mhn-compose-insert-flag nil
  "Non-nil means MIME insertion was done.
Triggers an automatic call to `mh-edit-mhn' in `mh-send-letter'.
This variable is buffer-local.")
(make-variable-buffer-local 'mh-mhn-compose-insert-flag)

(defvar mh-mml-compose-insert-flag nil
  "Non-nil means that a MIME insertion was done.
This buffer-local variable is used to remember if a MIME insertion was done.
Triggers an automatic call to `mh-mml-to-mime' in `mh-send-letter'.")
(make-variable-buffer-local 'mh-mml-compose-insert-flag)

;; Copy of `goto-address-mail-regexp'
(defvar mh-address-mail-regexp
  "[-a-zA-Z0-9._]+@[-a-zA-z0-9_]+\\.+[a-zA-Z0-9]+"
  "A regular expression probably matching an e-mail address.")

;; From goto-addr.el, which we don't want to force-load on users.
;;;###mh-autoload
(defun mh-goto-address-find-address-at-point ()
  "Find e-mail address around or before point.
Then search backwards to beginning of line for the start of an e-mail
address.  If no e-mail address found, return nil."
  (re-search-backward "[^-_A-z0-9.@]" (line-beginning-position) 'lim)
  (if (or (looking-at mh-address-mail-regexp)	; already at start
	  (and (re-search-forward mh-address-mail-regexp
				  (line-end-position) 'lim)
	       (goto-char (match-beginning 0))))
      (match-string-no-properties 0)))

(defun mh-in-header-p ()
  "Return non-nil if the point is in the header of a draft message."
  (< (point) (mail-header-end)))

(defun mh-header-field-beginning ()
  "Move to the beginning of the current header field.
Handles RFC 822 continuation lines."
  (beginning-of-line)
  (while (looking-at "^[ \t]")
    (forward-line -1)))

(defun mh-header-field-end ()
  "Move to the end of the current header field.
Handles RFC 822 continuation lines."
  (forward-line 1)
  (while (looking-at "^[ \t]")
    (forward-line 1))
  (backward-char 1))                    ;to end of previous line

(defun mh-letter-header-font-lock (limit)
  "Return the entire mail header to font-lock.
Argument LIMIT limits search."
  (if (= (point) limit)
      nil
    (let* ((mail-header-end (save-match-data (mail-header-end)))
           (lesser-limit (if (< mail-header-end limit) mail-header-end limit)))
      (when (mh-in-header-p)
        (set-match-data (list 1 lesser-limit))
        (goto-char lesser-limit)
        t))))

(defun mh-header-field-font-lock (field limit)
  "Return the value of a header field FIELD to font-lock.
Argument LIMIT limits search."
  (if (= (point) limit)
      nil
    (let* ((mail-header-end (mail-header-end))
           (lesser-limit (if (< mail-header-end limit) mail-header-end limit))
           (case-fold-search t))
      (when (and (< (point) mail-header-end) ;Only within header
                 (re-search-forward (format "^%s" field) lesser-limit t))
        (let ((match-one-b (match-beginning 0))
              (match-one-e (match-end 0)))
          (mh-header-field-end)
          (if (> (point) limit)         ;Don't search for end beyond limit
              (goto-char limit))
          (set-match-data (list match-one-b match-one-e
                                (1+ match-one-e) (point)))
          t)))))

(defun mh-header-to-font-lock (limit)
  "Return the value of a header field To to font-lock.
Argument LIMIT limits search."
  (mh-header-field-font-lock "To:" limit))

(defun mh-header-cc-font-lock (limit)
  "Return the value of a header field cc to font-lock.
Argument LIMIT limits search."
  (mh-header-field-font-lock "cc:" limit))

(defun mh-header-subject-font-lock (limit)
  "Return the value of a header field Subject to font-lock.
Argument LIMIT limits search."
  (mh-header-field-font-lock "Subject:" limit))

(eval-and-compile
  ;; Otherwise byte-compilation fails on `mh-show-font-lock-keywords-with-cite'
  (defvar mh-show-font-lock-keywords
    '(("^\\(From:\\|Sender:\\)\\(.*\\)"  (1 'default) (2 mh-show-from-face))
      (mh-header-to-font-lock            (0 'default) (1 mh-show-to-face))
      (mh-header-cc-font-lock            (0 'default) (1 mh-show-cc-face))
      ("^\\(Reply-To:\\|Return-Path:\\)\\(.*\\)$"
       (1 'default) (2 mh-show-from-face))
      (mh-header-subject-font-lock       (0 'default) (1 mh-show-subject-face))
      ("^\\(Apparently-To:\\|Newsgroups:\\)\\(.*\\)"
       (1 'default) (2 mh-show-cc-face))
      ("^\\(In-reply-to\\|Date\\):\\(.*\\)$"
       (1 'default) (2 mh-show-date-face))
      (mh-letter-header-font-lock        (0 mh-show-header-face append t)))
    "Additional expressions to highlight in MH-show mode."))

(defvar mh-show-font-lock-keywords-with-cite
  (eval-when-compile
    (let* ((cite-chars "[>|}]")
           (cite-prefix "A-Za-z")
           (cite-suffix (concat cite-prefix "0-9_.@-`'\"")))
      (append
       mh-show-font-lock-keywords
       (list
        ;; Use MATCH-ANCHORED to effectively anchor the regexp left side.
        `(,cite-chars
          (,(concat "\\=[ \t]*"
                    "\\(\\([" cite-prefix "]+[" cite-suffix "]*\\)?"
                    "\\(" cite-chars "[ \t]*\\)\\)+"
                    "\\(.*\\)")
           (beginning-of-line) (end-of-line)
           (2 font-lock-constant-face nil t)
           (4 font-lock-comment-face nil t)))))))
  "Additional expressions to highlight in MH-show mode.")

(defun mh-show-font-lock-fontify-region (beg end loudly)
  "Limit font-lock in `mh-show-mode' to the header.
Used when `mh-highlight-citation-p' is set to gnus, leaving the body to be
dealt with by gnus highlighting. The region between BEG and END is
given over to be fontified and LOUDLY controls if a user sees a
message about the fontification operation."
  (let ((header-end (mail-header-end)))
    (cond
     ((and (< beg header-end)(< end header-end))
      (font-lock-default-fontify-region beg end loudly))
     ((and (< beg header-end)(>= end header-end))
      (font-lock-default-fontify-region beg header-end loudly))
     (t
      nil))))

;; Needed to help shush the byte-compiler.
(if mh-xemacs-flag
    (progn
      (eval-and-compile
        (require 'gnus)
        (require 'gnus-art)
        (require 'gnus-cite))))

(defun mh-gnus-article-highlight-citation ()
  "Highlight cited text in current buffer using gnus."
  (interactive)
  ;; Requiring gnus-cite should have been sufficient. However for Emacs21.1,
  ;; recursive-load-depth-limit is only 10, so an error occurs. Also it may be
  ;; better to have an autoload at top-level (though that won't work because
  ;; of recursive-load-depth-limit). That gets rid of a compiler warning as
  ;; well.
  (unless mh-xemacs-flag
    (require 'gnus-art)
    (require 'gnus-cite))
  ;; Don't allow Gnus to create buttons while highlighting, maybe this is bad
  ;; style?
  (flet ((gnus-article-add-button (&rest args) nil))
    (let* ((modified (buffer-modified-p))
           (gnus-article-buffer (buffer-name))
           (gnus-cite-face-list `(,@(cdr gnus-cite-face-list)
                                    ,(car gnus-cite-face-list))))
      (gnus-article-highlight-citation t)
      (set-buffer-modified-p modified))))

;;; Internal bookkeeping variables:

;; The value of `mh-folder-list-change-hook' is called whenever
;; mh-folder-list variable is set.
;; List of folder names for completion.
(defvar mh-folder-list nil)

;; Cached value of the `Path:' component in the user's MH profile.
;; User's mail folder directory.
(defvar mh-user-path nil)

;; An mh-draft-folder of nil means do not use a draft folder.
;; Cached value of the `Draft-Folder:' component in the user's MH profile.
;; Name of folder containing draft messages.
(defvar mh-draft-folder nil)

;; Cached value of the `Unseen-Sequence:' component in the user's MH profile.
;; Name of the Unseen sequence.
(defvar mh-unseen-seq nil)

;; Cached value of the `Previous-Sequence:' component in the user's MH
;; profile.
;; Name of the Previous sequence.
(defvar mh-previous-seq nil)

;; Cached value of the `Inbox:' component in the user's MH profile,
;; or "+inbox" if no such component.
;; Name of the Inbox folder.
(defvar mh-inbox nil)

;; Name of MH-E scratch buffer.
(defconst mh-temp-buffer " *mh-temp*")

;; Name of the MH-E folder list buffer.
(defconst mh-temp-folders-buffer "*Folders*")

;; Name of the MH-E sequences list buffer.
(defconst mh-temp-sequences-buffer "*Sequences*")

;; Window configuration before MH-E command.
(defvar mh-previous-window-config nil)

;;Non-nil means next SPC or whatever goes to next undeleted message.
(defvar mh-page-to-next-msg-flag nil)

;;; Internal variables local to a folder.

;; Name of current folder, a string.
(defvar mh-current-folder nil)

;; Buffer that displays message for this folder.
(defvar mh-show-buffer nil)

;; Full path of directory for this folder.
(defvar mh-folder-filename nil)
  
;;Number of msgs in buffer.
(defvar mh-msg-count nil)

;; If non-nil, show the message in a separate window.
(defvar mh-showing-mode nil)

(defvar mh-show-mode-map (make-sparse-keymap)
  "Keymap used by the show buffer.")

(defvar mh-show-folder-buffer nil
  "Keeps track of folder whose message is being displayed.")

;;; This holds a documentation string used by describe-mode.
(defun mh-showing-mode (&optional arg)
  "Change whether messages should be displayed.
With arg, display messages iff ARG is positive."
  (setq mh-showing-mode
        (if (null arg)
            (not mh-showing-mode)
          (> (prefix-numeric-value arg) 0))))

;; The sequences of this folder.  An alist of (seq . msgs).
(defvar mh-seq-list nil)

;; List of displayed messages to be removed from the Unseen sequence.
(defvar mh-seen-list nil)

;; If non-nil, show buffer contains message with all headers.
;; If nil, show buffer contains message processed normally.
;; Showing message with headers or normally.
(defvar mh-showing-with-headers nil)


;;; MH-E macros

(defmacro with-mh-folder-updating (save-modification-flag &rest body)
  "Format is (with-mh-folder-updating (SAVE-MODIFICATION-FLAG) &body BODY).
Execute BODY, which can modify the folder buffer without having to
worry about file locking or the read-only flag, and return its result.
If SAVE-MODIFICATION-FLAG is non-nil, the buffer's modification
flag is unchanged, otherwise it is cleared."
  (setq save-modification-flag (car save-modification-flag)) ; CL style
  `(prog1
       (let ((mh-folder-updating-mod-flag (buffer-modified-p))
             (buffer-read-only nil)
             (buffer-file-name nil))    ;don't let the buffer get locked
         (prog1
             (progn
               ,@body)
           (mh-set-folder-modified-p mh-folder-updating-mod-flag)))
     ,@(if (not save-modification-flag)
           '((mh-set-folder-modified-p nil)))))

(put 'with-mh-folder-updating 'lisp-indent-hook 1)

(defmacro mh-in-show-buffer (show-buffer &rest body)
  "Format is (mh-in-show-buffer (SHOW-BUFFER) &body BODY).
Display buffer SHOW-BUFFER in other window and execute BODY in it.
Stronger than `save-excursion', weaker than `save-window-excursion'."
  (setq show-buffer (car show-buffer))  ; CL style
  `(let ((mh-in-show-buffer-saved-window (selected-window)))
     (switch-to-buffer-other-window ,show-buffer)
     (if mh-bury-show-buffer-flag (bury-buffer (current-buffer)))
     (unwind-protect
         (progn
           ,@body)
       (select-window mh-in-show-buffer-saved-window))))

(put 'mh-in-show-buffer 'lisp-indent-hook 1)

(defmacro mh-make-seq (name msgs)
  "Create sequence NAME with the given MSGS."
  (list 'cons name msgs))

(defmacro mh-seq-name (sequence)
  "Extract sequence name from the given SEQUENCE."
  (list 'car sequence))

(defmacro mh-seq-msgs (sequence)
  "Extract messages from the given SEQUENCE."
  (list 'cdr sequence))

(defun mh-recenter (arg)
  "Like recenter but with three improvements:
- At the end of the buffer it tries to show fewer empty lines.
- operates only if the current buffer is in the selected window.
  (Commands like `save-some-buffers' can make this false.)
- nil ARG means recenter as if prefix argument had been given."
  (cond ((not (eq (get-buffer-window (current-buffer)) (selected-window)))
         nil)
        ((= (point-max) (save-excursion
                          (forward-line (- (/ (window-height) 2) 2))
                          (point)))
         (let ((lines-from-end 2))
           (save-excursion
             (while (> (point-max) (progn (forward-line) (point)))
               (incf lines-from-end)))
           (recenter (- lines-from-end))))
        ;; '(4) is the same as C-u prefix argument.
        (t (recenter (or arg '(4))))))

(defun mh-start-of-uncleaned-message ()
  "Position uninteresting headers off the top of the window."
  (let ((case-fold-search t))
    (re-search-forward
     "^To:\\|^Cc:\\|^From:\\|^Subject:\\|^Date:" nil t)
    (beginning-of-line)
    (mh-recenter 0)))

(defun mh-invalidate-show-buffer ()
  "Invalidate the show buffer so we must update it to use it."
  (if (get-buffer mh-show-buffer)
      (save-excursion
        (set-buffer mh-show-buffer)
        (mh-unvisit-file))))

(defun mh-unvisit-file ()
  "Separate current buffer from the message file it was visiting."
  (or (not (buffer-modified-p))
      (null buffer-file-name)           ;we've been here before
      (yes-or-no-p (format "Message %s modified; flush changes? "
                           (file-name-nondirectory buffer-file-name)))
      (error "Flushing changes not confirmed"))
  (clear-visited-file-modtime)
  (unlock-buffer)
  (setq buffer-file-name nil))
  
;;;###mh-autoload
(defun mh-get-msg-num (error-if-no-message)
  "Return the message number of the displayed message.
If the argument ERROR-IF-NO-MESSAGE is non-nil, then complain if the cursor is
not pointing to a message."
  (save-excursion
    (beginning-of-line)
    (cond ((looking-at mh-scan-msg-number-regexp)
           (string-to-int (buffer-substring (match-beginning 1)
                                            (match-end 1))))
          (error-if-no-message
           (error "Cursor not pointing to message"))
          (t nil))))

(defun mh-folder-name-p (name)
  "Return non-nil if NAME is the name of a folder.
A name (a string or symbol) can be a folder name if it begins with \"+\"."
  (if (symbolp name)
      (eq (aref (symbol-name name) 0) ?+)
    (and (> (length name) 0)
         (eq (aref name 0) ?+))))


(defun mh-expand-file-name (filename &optional default)
  "Expand FILENAME like `expand-file-name', but also handle MH folder names.
Any filename that starts with '+' is treated as a folder name.
See `expand-file-name' for description of DEFAULT."
  (if (mh-folder-name-p filename)
      (expand-file-name (substring filename 1) mh-user-path)
    (expand-file-name filename default)))


(defun mh-msg-filename (msg &optional folder)
  "Return the file name of MSG in FOLDER (default current folder)."
  (expand-file-name (int-to-string msg)
                    (if folder
                        (mh-expand-file-name folder)
                      mh-folder-filename)))

;;; Infrastructure to generate show-buffer functions from folder functions
;;; XEmacs does not have deactivate-mark? What is the equivalent of
;;; transient-mark-mode for XEmacs? Should we be restoring the mark in the
;;; folder buffer after the operation has been carried out.
(defmacro mh-defun-show-buffer (function original-function
                                         &optional dont-return)
  "Define FUNCTION to run ORIGINAL-FUNCTION in folder buffer.
If the buffer we start in is still visible and DONT-RETURN is nil then switch
to it after that."
  `(defun ,function ()
     ,(format "Calls %s from the message's folder.\n%s\nSee `%s' for more info.\n"
              original-function
              (if dont-return ""
                "When function completes, returns to the show buffer if it is
still visible.\n")
              original-function)
     (interactive)
     (when (buffer-live-p (get-buffer mh-show-folder-buffer))
       (let ((config (current-window-configuration))
             (folder-buffer mh-show-folder-buffer)
             (normal-exit nil)
             ,@(if dont-return () '((cur-buffer-name (buffer-name)))))
         (pop-to-buffer mh-show-folder-buffer nil)
         (unless (equal (buffer-name
                         (window-buffer (frame-first-window (selected-frame))))
                        folder-buffer)
           (delete-other-windows))
         (mh-goto-cur-msg t)
         (and (fboundp 'deactivate-mark) (deactivate-mark))
         (unwind-protect
             (prog1 (call-interactively (function ,original-function))
               (setq normal-exit t))
           (and (fboundp 'deactivate-mark) (deactivate-mark))
           (cond ((not normal-exit)
                  (set-window-configuration config))
                 ,(if dont-return
                      `(t (setq mh-previous-window-config config))
                    `((and (get-buffer cur-buffer-name)
                           (window-live-p (get-buffer-window
                                           (get-buffer cur-buffer-name))))
                      (pop-to-buffer (get-buffer cur-buffer-name) nil)))))))))

;;; Generate interactive functions for the show buffer from the corresponding
;;; folder functions.
(mh-defun-show-buffer mh-show-previous-undeleted-msg
                      mh-previous-undeleted-msg)
(mh-defun-show-buffer mh-show-next-undeleted-msg
                      mh-next-undeleted-msg)
(mh-defun-show-buffer mh-show-quit mh-quit)
(mh-defun-show-buffer mh-show-delete-msg mh-delete-msg)
(mh-defun-show-buffer mh-show-refile-msg mh-refile-msg)
(mh-defun-show-buffer mh-show-undo mh-undo)
(mh-defun-show-buffer mh-show-execute-commands mh-execute-commands)
(mh-defun-show-buffer mh-show-reply mh-reply t)
(mh-defun-show-buffer mh-show-redistribute mh-redistribute)
(mh-defun-show-buffer mh-show-forward mh-forward t)
(mh-defun-show-buffer mh-show-header-display mh-header-display)
(mh-defun-show-buffer mh-show-refile-or-write-again
                      mh-refile-or-write-again)
(mh-defun-show-buffer mh-show-show mh-show)
(mh-defun-show-buffer mh-show-write-message-to-file
                      mh-write-msg-to-file)
(mh-defun-show-buffer mh-show-extract-rejected-mail
                      mh-extract-rejected-mail t)
(mh-defun-show-buffer mh-show-delete-msg-no-motion
                      mh-delete-msg-no-motion)
(mh-defun-show-buffer mh-show-first-msg mh-first-msg)
(mh-defun-show-buffer mh-show-last-msg mh-last-msg)
(mh-defun-show-buffer mh-show-copy-msg mh-copy-msg)
(mh-defun-show-buffer mh-show-edit-again mh-edit-again t)
(mh-defun-show-buffer mh-show-goto-msg mh-goto-msg)
(mh-defun-show-buffer mh-show-inc-folder mh-inc-folder)
(mh-defun-show-buffer mh-show-delete-subject-or-thread
                      mh-delete-subject-or-thread)
(mh-defun-show-buffer mh-show-delete-subject mh-delete-subject)
(mh-defun-show-buffer mh-show-print-msg mh-print-msg)
(mh-defun-show-buffer mh-show-send mh-send t)
(mh-defun-show-buffer mh-show-toggle-showing mh-toggle-showing t)
(mh-defun-show-buffer mh-show-pipe-msg mh-pipe-msg t)
(mh-defun-show-buffer mh-show-sort-folder mh-sort-folder)
(mh-defun-show-buffer mh-show-visit-folder mh-visit-folder t)
(mh-defun-show-buffer mh-show-rescan-folder mh-rescan-folder)
(mh-defun-show-buffer mh-show-pack-folder mh-pack-folder)
(mh-defun-show-buffer mh-show-kill-folder mh-kill-folder t)
(mh-defun-show-buffer mh-show-list-folders mh-list-folders t)
(mh-defun-show-buffer mh-show-search-folder mh-search-folder t)
(mh-defun-show-buffer mh-show-undo-folder mh-undo-folder)
(mh-defun-show-buffer mh-show-delete-msg-from-seq
                      mh-delete-msg-from-seq)
(mh-defun-show-buffer mh-show-delete-seq mh-delete-seq)
(mh-defun-show-buffer mh-show-list-sequences mh-list-sequences)
(mh-defun-show-buffer mh-show-narrow-to-seq mh-narrow-to-seq)
(mh-defun-show-buffer mh-show-put-msg-in-seq mh-put-msg-in-seq)
(mh-defun-show-buffer mh-show-msg-is-in-seq mh-msg-is-in-seq)
(mh-defun-show-buffer mh-show-widen mh-widen)
(mh-defun-show-buffer mh-show-narrow-to-subject
                      mh-narrow-to-subject)
(mh-defun-show-buffer mh-show-store-msg mh-store-msg)
(mh-defun-show-buffer mh-show-page-digest mh-page-digest)
(mh-defun-show-buffer mh-show-page-digest-backwards
                      mh-page-digest-backwards)
(mh-defun-show-buffer mh-show-burst-digest mh-burst-digest)
(mh-defun-show-buffer mh-show-page-msg mh-page-msg)
(mh-defun-show-buffer mh-show-previous-page mh-previous-page)
(mh-defun-show-buffer mh-show-modify mh-modify t)
(mh-defun-show-buffer mh-show-next-button mh-next-button)
(mh-defun-show-buffer mh-show-prev-button mh-prev-button)
(mh-defun-show-buffer mh-show-toggle-mime-part mh-folder-toggle-mime-part)
(mh-defun-show-buffer mh-show-save-mime-part mh-folder-save-mime-part)
(mh-defun-show-buffer mh-show-inline-mime-part mh-folder-inline-mime-part)
(mh-defun-show-buffer mh-show-toggle-threads mh-toggle-threads)
(mh-defun-show-buffer mh-show-thread-delete mh-thread-delete)
(mh-defun-show-buffer mh-show-thread-refile mh-thread-refile)
(mh-defun-show-buffer mh-show-update-sequences mh-update-sequences)
(mh-defun-show-buffer mh-show-next-unread-msg mh-next-unread-msg)
(mh-defun-show-buffer mh-show-previous-unread-msg mh-previous-unread-msg)
(mh-defun-show-buffer mh-show-thread-ancestor mh-thread-ancestor)
(mh-defun-show-buffer mh-show-thread-next-sibling mh-thread-next-sibling)
(mh-defun-show-buffer mh-show-thread-previous-sibling
                      mh-thread-previous-sibling)
(mh-defun-show-buffer mh-show-index-visit-folder mh-index-visit-folder t)

;;; Populate mh-show-mode-map
(gnus-define-keys mh-show-mode-map
  " "    mh-show-page-msg
  "!"    mh-show-refile-or-write-again
  ","    mh-show-header-display
  "."    mh-show-show
  ">"    mh-show-write-message-to-file
  "?"    mh-help
  "E"    mh-show-extract-rejected-mail
  "M"    mh-show-modify
  "\177" mh-show-previous-page
  "\C-d" mh-show-delete-msg-no-motion
  "\t"   mh-show-next-button
  [backtab] mh-show-prev-button
  "\M-\t" mh-show-prev-button
  "\ed"  mh-show-redistribute
  "^"    mh-show-refile-msg
  "c"    mh-show-copy-msg
  "d"    mh-show-delete-msg
  "e"    mh-show-edit-again
  "f"    mh-show-forward
  "g"    mh-show-goto-msg
  "i"    mh-show-inc-folder
  "k"    mh-show-delete-subject-or-thread
  "l"    mh-show-print-msg
  "m"    mh-show-send
  "n"    mh-show-next-undeleted-msg
  "\M-n" mh-show-next-unread-msg
  "o"    mh-show-refile-msg
  "p"    mh-show-previous-undeleted-msg
  "\M-p" mh-show-previous-unread-msg
  "q"    mh-show-quit
  "r"    mh-show-reply
  "s"    mh-show-send
  "t"    mh-show-toggle-showing
  "u"    mh-show-undo
  "x"    mh-show-execute-commands
  "v"    mh-show-index-visit-folder
  "|"    mh-show-pipe-msg)

(gnus-define-keys (mh-show-folder-map "F" mh-show-mode-map)
  "?"    mh-prefix-help
  "S"    mh-show-sort-folder
  "f"    mh-show-visit-folder
  "i"    mh-index-search
  "k"    mh-show-kill-folder
  "l"    mh-show-list-folders
  "o"    mh-show-visit-folder
  "r"    mh-show-rescan-folder
  "s"    mh-show-search-folder
  "t"    mh-show-toggle-threads
  "u"    mh-show-undo-folder
  "v"    mh-show-visit-folder)

(gnus-define-keys (mh-show-sequence-map "S" mh-show-mode-map)
  "?"    mh-prefix-help
  "d"    mh-show-delete-msg-from-seq
  "k"    mh-show-delete-seq
  "l"    mh-show-list-sequences
  "n"    mh-show-narrow-to-seq
  "p"    mh-show-put-msg-in-seq
  "s"    mh-show-msg-is-in-seq
  "w"    mh-show-widen)

(gnus-define-keys (mh-show-thread-map "T" mh-show-mode-map)
  "?"    mh-prefix-help
  "u"    mh-show-thread-ancestor
  "p"    mh-show-thread-previous-sibling
  "n"    mh-show-thread-next-sibling
  "t"    mh-show-toggle-threads
  "d"    mh-show-thread-delete
  "o"    mh-show-thread-refile)

(gnus-define-keys (mh-show-limit-map "/" mh-show-mode-map)
  "?"    mh-prefix-help
  "s"    mh-show-narrow-to-subject
  "w"    mh-show-widen)

(gnus-define-keys (mh-show-extract-map "X" mh-show-mode-map)
  "?"    mh-prefix-help
  "s"    mh-show-store-msg
  "u"    mh-show-store-msg)

;; Untested...
(gnus-define-keys (mh-show-digest-map "D" mh-show-mode-map)
  "?"    mh-prefix-help
  " "    mh-show-page-digest
  "\177" mh-show-page-digest-backwards
  "b"    mh-show-burst-digest)

(gnus-define-keys (mh-show-mime-map "K" mh-show-mode-map)
  "?"           mh-prefix-help
  "a"           mh-mime-save-parts
  "v"           mh-show-toggle-mime-part
  "o"           mh-show-save-mime-part
  "i"           mh-show-inline-mime-part
  "\t"          mh-show-next-button
  [backtab]     mh-show-prev-button
  "\M-\t"       mh-show-prev-button)

(easy-menu-define
  mh-show-sequence-menu mh-show-mode-map "Menu for MH-E folder-sequence."
  '("Sequence"
    ["Add Message to Sequence..."       mh-show-put-msg-in-seq t]
    ["List Sequences for Message"       mh-show-msg-is-in-seq t]
    ["Delete Message from Sequence..."  mh-show-delete-msg-from-seq t]
    ["List Sequences in Folder..."      mh-show-list-sequences t]
    ["Delete Sequence..."               mh-show-delete-seq t]
    ["Narrow to Sequence..."            mh-show-narrow-to-seq t]
    ["Widen from Sequence"              mh-show-widen t]
    "--"
    ["Narrow to Subject Sequence"       mh-show-narrow-to-subject t]
    ["Delete Rest of Same Subject"      mh-show-delete-subject t]
    "--"
    ["Push State Out to MH"             mh-show-update-sequences t]))

(easy-menu-define
  mh-show-message-menu mh-show-mode-map "Menu for MH-E folder-message."
  '("Message"
    ["Show Message"                     mh-show-show t]
    ["Show Message with Header"         mh-show-header-display t]
    ["Next Message"                     mh-show-next-undeleted-msg t]
    ["Previous Message"                 mh-show-previous-undeleted-msg t]
    ["Go to First Message"              mh-show-first-msg t]
    ["Go to Last Message"               mh-show-last-msg t]
    ["Go to Message by Number..."       mh-show-goto-msg t]
    ["Modify Message"                   mh-show-modify t]
    ["Delete Message"                   mh-show-delete-msg t]
    ["Refile Message"                   mh-show-refile-msg t]
    ["Undo Delete/Refile"               mh-show-undo t]
    ["Process Delete/Refile"            mh-show-execute-commands t]
    "--"
    ["Compose a New Message"            mh-send t]
    ["Reply to Message..."              mh-show-reply t]
    ["Forward Message..."               mh-show-forward t]
    ["Redistribute Message..."          mh-show-redistribute t]
    ["Edit Message Again"               mh-show-edit-again t]
    ["Re-edit a Bounced Message"        mh-show-extract-rejected-mail t]
    "--"
    ["Copy Message to Folder..."        mh-show-copy-msg t]
    ["Print Message"                    mh-show-print-msg t]
    ["Write Message to File..."         mh-show-write-msg-to-file t]
    ["Pipe Message to Command..."       mh-show-pipe-msg t]
    ["Unpack Uuencoded Message..."      mh-show-store-msg t]
    ["Burst Digest Message"             mh-show-burst-digest t]))

(easy-menu-define
  mh-show-folder-menu mh-show-mode-map  "Menu for MH-E folder."
  '("Folder"
    ["Incorporate New Mail"             mh-show-inc-folder t]
    ["Toggle Show/Folder"               mh-show-toggle-showing t]
    ["Execute Delete/Refile"            mh-show-execute-commands t]
    ["Rescan Folder"                    mh-show-rescan-folder t]
    ["Thread Folder"                    mh-show-toggle-threads t]
    ["Pack Folder"                      mh-show-pack-folder t]
    ["Sort Folder"                      mh-show-sort-folder t]
    "--"
    ["List Folders"                     mh-show-list-folders t]
    ["Visit a Folder..."                mh-show-visit-folder t]
    ["Search a Folder..."               mh-show-search-folder t]
    ["Indexed Search..."                mh-index-search t]
    "--"
    ["Quit MH-E"                        mh-quit t]))


;;; Ensure new buffers won't get this mode if default-major-mode is nil.
(put 'mh-show-mode 'mode-class 'special)

(define-derived-mode mh-show-mode text-mode "MH-Show"
  "Major mode for showing messages in MH-E.\\<mh-show-mode-map>
The value of `mh-show-mode-hook' is a list of functions to
be called, with no arguments, upon entry to this mode."
  (set (make-local-variable 'mail-header-separator) mh-mail-header-separator)
  (setq paragraph-start (default-value 'paragraph-start))
  (mh-show-unquote-From)
  (mh-show-xface)
  (mh-show-addr)
  (make-local-variable 'font-lock-defaults)
  ;;(set (make-local-variable 'font-lock-support-mode) nil)
  (cond
   ((equal mh-highlight-citation-p 'font-lock)
    (setq font-lock-defaults '(mh-show-font-lock-keywords-with-cite t)))
   ((equal mh-highlight-citation-p 'gnus)
    (setq font-lock-defaults '((mh-show-font-lock-keywords)
                               t nil nil nil
                               (font-lock-fontify-region-function
                                . mh-show-font-lock-fontify-region)))
    (mh-gnus-article-highlight-citation))
   (t
    (setq font-lock-defaults '(mh-show-font-lock-keywords t))))
  (if (and mh-xemacs-flag
           font-lock-auto-fontify)
      (turn-on-font-lock))
  (if (and (boundp 'tool-bar-mode) tool-bar-mode)
      (set (make-local-variable 'tool-bar-map) mh-show-tool-bar-map))
  (when mh-decode-mime-flag
    (add-hook 'kill-buffer-hook 'mh-mime-cleanup nil t))
  (easy-menu-add mh-show-sequence-menu)
  (easy-menu-add mh-show-message-menu)
  (easy-menu-add mh-show-folder-menu)
  (make-local-variable 'mh-show-folder-buffer)
  (buffer-disable-undo)
  (setq buffer-read-only t)
  (use-local-map mh-show-mode-map)
  (run-hooks 'mh-show-mode-hook))

(defun mh-show-addr ()
  "Use `goto-address'."
  (when mh-show-use-goto-addr-flag
    (if (not (featurep 'goto-addr))
        (load "goto-addr" t t))
    (if (fboundp 'goto-address)
        (goto-address))))

(defvar mh-show-xface-function
  (cond ((and mh-xemacs-flag (locate-library "x-face"))
         (load "x-face" t t)
         (if (fboundp 'x-face-xmas-wl-display-x-face)
             #'x-face-xmas-wl-display-x-face
           #'ignore))
        ((and (not mh-xemacs-flag) (>= emacs-major-version 21))
         (load "x-face-e21" t t)
         (if (fboundp 'x-face-decode-message-header)
             #'x-face-decode-message-header
           #'ignore))
        (t #'ignore))
  "Determine at run time what function should be called to display X-Face.")

(defun mh-show-xface ()
  "Display X-Face."
  (when (and mh-show-use-xface-flag
             (or mh-decode-mime-flag mhl-formfile
                 mh-clean-message-header-flag))
    (funcall mh-show-xface-function)))

(defun mh-maybe-show (&optional msg)
  "Display message at cursor, but only if in show mode.
If optional arg MSG is non-nil, display that message instead."
  (if mh-showing-mode (mh-show msg)))

(defun mh-show (&optional message)
  "Show message at cursor.
If optional argument MESSAGE is non-nil, display that message instead.
Force a two-window display with the folder window on top (size
`mh-summary-height') and the show buffer below it.
If the message is already visible, display the start of the message.

Display of the message is controlled by setting the variables
`mh-clean-message-header-flag' and `mhl-formfile'.  The default behavior is
to scroll uninteresting headers off the top of the window.
Type \"\\[mh-header-display]\" to see the message with all its headers."
  (interactive)
  (and mh-showing-with-headers
       (or mhl-formfile mh-clean-message-header-flag)
       (mh-invalidate-show-buffer))
  (mh-show-msg message))

(defun mh-show-mouse (EVENT)
  "Move point to mouse EVENT and show message."
  (interactive "e")
  (mouse-set-point EVENT)
  (mh-show))

(defun mh-show-msg (msg)
  "Show MSG.
The value of `mh-show-hook' is a list of functions to be called, with no
arguments, after the message has been displayed."
  (if (not msg)
      (setq msg (mh-get-msg-num t)))
  (mh-showing-mode t)
  (setq mh-page-to-next-msg-flag nil)
  (let ((folder mh-current-folder)
        (clean-message-header mh-clean-message-header-flag)
        (show-window (get-buffer-window mh-show-buffer)))
    (if (not (eq (next-window (minibuffer-window)) (selected-window)))
        (delete-other-windows))         ; force ourself to the top window
    (mh-in-show-buffer (mh-show-buffer)
      (if (and show-window
               (equal (mh-msg-filename msg folder) buffer-file-name))
          (progn                        ;just back up to start
            (goto-char (point-min))
            (if (not clean-message-header)
                (mh-start-of-uncleaned-message)))
        (mh-display-msg msg folder))))
  (if (not (= (1+ (window-height)) (frame-height))) ;not horizontally split
      (shrink-window (- (window-height) mh-summary-height)))
  (mh-recenter nil)
  (if (not (memq msg mh-seen-list))
      (setq mh-seen-list (cons msg mh-seen-list)))
  (when mh-update-sequences-after-mh-show-flag
    (mh-update-sequences))
  (run-hooks 'mh-show-hook))

(defun mh-modify (&optional message)
  "Edit message at cursor.
If optional argument MESSAGE is non-nil, edit that message instead.
Force a two-window display with the folder window on top (size
`mh-summary-height') and the message editing buffer below it.

The message is displayed in raw form."
  (interactive)
  (let* ((message (or message (mh-get-msg-num t)))
         (msg-filename (mh-msg-filename message))
         edit-buffer)
    (when (not (file-exists-p msg-filename))
      (error "Message %d does not exist" message))

    ;; Invalidate the show buffer if it is showing the same message that is
    ;; to be edited.
    (when (and (buffer-live-p (get-buffer mh-show-buffer))
               (equal (save-excursion (set-buffer mh-show-buffer)
                                      buffer-file-name)
                      msg-filename))
      (mh-invalidate-show-buffer))

    ;; Edit message
    (find-file msg-filename)
    (setq edit-buffer (current-buffer))

    ;; Set buffer properties
    (mh-letter-mode)
    (use-local-map text-mode-map)

    ;; Just show the edit buffer...
    (delete-other-windows)
    (switch-to-buffer edit-buffer)))

(defun mh-decode-quoted-printable ()
  "Run mimedecode on current buffer, replacing its contents."
  (let ((case-fold-search t))
    (goto-char (point-min))
    (when (and (re-search-forward
                "^content-transfer-encoding:[ \t]*quoted-printable"
                (if mh-decode-mime-flag (mail-header-end) nil) t)
               (search-forward "\n\n" nil t))
      (message "Converting quoted-printable characters...")
      (let ((modified (buffer-modified-p))
            (command "mimedecode"))
        (shell-command-on-region (point-min) (point-max) command t t)
        (if (fboundp 'deactivate-mark)
            (deactivate-mark))
        (set-buffer-modified-p modified))
      (message "Converting quoted-printable characters... done."))))

(defun mh-show-unquote-From ()
  "Decode >From at beginning of lines for `mh-show-mode'."
  (save-excursion
    (let ((modified (buffer-modified-p))
          (case-fold-search nil))
      (goto-char (mail-header-end))
      (while (re-search-forward "^>From" nil t)
        (replace-match "From"))
      (set-buffer-modified-p modified))))

(defun mh-msg-folder (folder-name)
  "Return the name of the buffer for FOLDER-NAME."
  folder-name)

(defun mh-display-msg (msg-num folder-name)
  "Display MSG-NUM of FOLDER-NAME.
Sets the current buffer to the show buffer."
  (let ((folder (mh-msg-folder folder-name)))
    (set-buffer folder)
    ;; When Gnus uses external displayers it has to keep handles longer. So
    ;; we will delete these handles when mh-quit is called on the folder. It
    ;; would be nicer if there are weak pointers in emacs lisp, then we could
    ;; get the garbage collector to do this for us.
    (unless (mh-buffer-data)
      (setf (mh-buffer-data) (mh-make-buffer-data)))
    ;; Bind variables in folder buffer in case they are local
    (let ((formfile mhl-formfile)
          (clean-message-header mh-clean-message-header-flag)
          (invisible-headers mh-invisible-headers)
          (visible-headers mh-visible-headers)
          (msg-filename (mh-msg-filename msg-num folder-name))
          (show-buffer mh-show-buffer)
          (mm-inline-media-tests mh-mm-inline-media-tests))
      (if (not (file-exists-p msg-filename))
          (error "Message %d does not exist" msg-num))
      (if (and (> mh-show-maximum-size 0)
               (> (elt (file-attributes msg-filename) 7)
                  mh-show-maximum-size)
               (not (y-or-n-p
                     (format
                      "Message %d (%d bytes) exceeds %d bytes. Display it? "
                      msg-num (elt (file-attributes msg-filename) 7)
                      mh-show-maximum-size))))
          (error "Message %d not displayed" msg-num))
      (set-buffer show-buffer)
      (cond ((not (equal msg-filename buffer-file-name))
             (mh-unvisit-file)
             (setq buffer-read-only nil)
             (erase-buffer)
             ;; Changing contents, so this hook needs to be reinitialized.
             ;; pgp.el uses this.
             (if (boundp 'write-contents-hooks) ;Emacs 19
                 (kill-local-variable 'write-contents-hooks))
             (if formfile
                 (mh-exec-lib-cmd-output "mhl" "-nobell" "-noclear"
                                         (if (stringp formfile)
                                             (list "-form" formfile))
                                         msg-filename)
               (insert-file-contents msg-filename))
             (if mh-decode-quoted-printable-flag
                 (mh-decode-quoted-printable))
             ;; Cleanup old mime handles
             (mh-mime-cleanup)
             ;; Use mm to display buffer
             (when (and mh-decode-mime-flag (not formfile))
               (mh-add-missing-mime-version-header)
               (setf (mh-buffer-data) (mh-make-buffer-data))
               (mh-mime-display))
             ;; Header cleanup
             (goto-char (point-min))
             (cond (clean-message-header
                    (mh-clean-msg-header (point-min)
                                         invisible-headers
                                         visible-headers)
                    (goto-char (point-min)))
                   (t
                    (mh-start-of-uncleaned-message)))
             ;; the parts of visiting we want to do (no locking)
             (or (eq buffer-undo-list t) ;don't save undo info for prev msgs
                 (setq buffer-undo-list nil))
             (set-buffer-auto-saved)
             ;; the parts of set-visited-file-name we want to do (no locking)
             (setq buffer-file-name msg-filename)
             (setq buffer-backed-up nil)
             (auto-save-mode 1)
             (set-mark nil)
             (mh-show-mode)
             (unwind-protect
                 (when (and mh-decode-mime-flag (not formfile))
                   (setq buffer-read-only nil)
                   (mh-display-smileys)
                   (mh-display-emphasis))
               (setq buffer-read-only t))
             (set-buffer-modified-p nil)
             (setq mh-show-folder-buffer folder)
             (setq mode-line-buffer-identification
                   (list (format mh-show-buffer-mode-line-buffer-id
                                 folder-name msg-num)))
             (set-buffer folder)
             (setq mh-showing-with-headers nil))))))

(defun mh-clean-msg-header (start invisible-headers visible-headers)
  "Flush extraneous lines in message header.
Header is cleaned from START to the end of the message header.
INVISIBLE-HEADERS contains a regular expression specifying lines to delete
from the header. VISIBLE-HEADERS contains a regular expression specifying the
lines to display. INVISIBLE-HEADERS is ignored if VISIBLE-HEADERS is non-nil."
  (let ((case-fold-search t)
        (after-change-functions nil))   ;Work around emacs-20 font-lock bug
                                        ;causing an endless loop.
    (save-restriction
      (goto-char start)
      (if (search-forward "\n\n" nil 'move)
          (backward-char 1))
      (narrow-to-region start (point))
      (goto-char (point-min))
      (if visible-headers
          (while (< (point) (point-max))
            (cond ((looking-at visible-headers)
                   (forward-line 1)
                   (while (looking-at "[ \t]") (forward-line 1)))
                  (t
                   (mh-delete-line 1)
                   (while (looking-at "[ \t]")
                     (mh-delete-line 1)))))
        (while (re-search-forward invisible-headers nil t)
          (beginning-of-line)
          (mh-delete-line 1)
          (while (looking-at "[ \t]")
            (mh-delete-line 1))))
      (unlock-buffer))))

(defun mh-delete-line (lines)
  "Delete the next LINES lines."
  (delete-region (point) (progn (forward-line lines) (point))))

(defun mh-notate (msg notation offset)
  "Mark MSG with the character NOTATION at position OFFSET.
Null MSG means the message at cursor."
  (save-excursion
    (if (or (null msg)
            (mh-goto-msg msg t t))
        (with-mh-folder-updating (t)
          (beginning-of-line)
          (forward-char offset)
          (delete-char 1)
          (insert notation)))))

(defun mh-find-msg-get-num (step)
  "Return the message number of the message nearest the cursor.
Jumps over non-message lines, such as inc errors.
If we have to search, STEP tells whether to search forward or backward."
  (or (mh-get-msg-num nil)
      (let ((msg-num nil)
            (nreverses 0))
        (while (and (not msg-num)
                    (< nreverses 2))
          (cond ((eobp)
                 (setq step -1)
                 (setq nreverses (1+ nreverses)))
                ((bobp)
                 (setq step 1)
                 (setq nreverses (1+ nreverses))))
          (forward-line step)
          (setq msg-num (mh-get-msg-num nil)))
        msg-num)))

(defun mh-goto-msg (number &optional no-error-if-no-message dont-show)
  "Position the cursor at message NUMBER.
Optional non-nil second argument NO-ERROR-IF-NO-MESSAGE means return nil
instead of signaling an error if message does not exist; in this case, the
cursor is positioned near where the message would have been.
Non-nil third argument DONT-SHOW means not to show the message."
  (interactive "NGo to message: ")
  (setq number (prefix-numeric-value number))
  (let ((point (point))
        (return-value t))
    (goto-char (point-min))
    (unless (re-search-forward (format "^[ ]*%s[^0-9]+" number) nil t)
      (goto-char point)
      (unless no-error-if-no-message
        (error "No message %d" number))
      (setq return-value nil))
    (beginning-of-line)
    (or dont-show (not return-value) (mh-maybe-show number))
    return-value))

(defun mh-msg-search-pat (n)
  "Return a search pattern for message N in the scan listing."
  (format mh-scan-msg-search-regexp n))

(defun mh-get-profile-field (field)
  "Find and return the value of FIELD in the current buffer.
Returns nil if the field is not in the buffer."
  (let ((case-fold-search t))
    (goto-char (point-min))
    (cond ((not (re-search-forward (format "^%s" field) nil t)) nil)
          ((looking-at "[\t ]*$") nil)
          (t
           (re-search-forward "[\t ]*\\([^\t \n].*\\)$" nil t)
           (let ((start (match-beginning 1)))
             (end-of-line)
             (buffer-substring start (point)))))))

(defvar mail-user-agent)
(defvar read-mail-command)

(defvar mh-find-path-run nil
  "Non-nil if `mh-find-path' has been run already.")

(defun mh-find-path ()
  "Set `mh-progs', `mh-lib', and `mh-lib-progs' variables.
Set `mh-user-path', `mh-draft-folder', `mh-unseen-seq', `mh-previous-seq',
`mh-inbox' from user's MH profile.
The value of `mh-find-path-hook' is a list of functions to be called, with no
arguments, after these variable have been set."
  (mh-find-progs)
  (unless mh-find-path-run
    (setq mh-find-path-run t)
    (setq read-mail-command 'mh-rmail)
    (setq mail-user-agent 'mh-e-user-agent))
  (save-excursion
    ;; Be sure profile is fully expanded before switching buffers
    (let ((profile (expand-file-name (or (getenv "MH") "~/.mh_profile"))))
      (set-buffer (get-buffer-create mh-temp-buffer))
      (setq buffer-offer-save nil)      ;for people who set default to t
      (erase-buffer)
      (condition-case err
          (insert-file-contents profile)
        (file-error
         (mh-install profile err)))
      (setq mh-user-path (mh-get-profile-field "Path:"))
      (if (not mh-user-path)
          (setq mh-user-path "Mail"))
      (setq mh-user-path
            (file-name-as-directory
             (expand-file-name mh-user-path (expand-file-name "~"))))
      (setq mh-draft-folder (mh-get-profile-field "Draft-Folder:"))
      (if mh-draft-folder
          (progn
            (if (not (mh-folder-name-p mh-draft-folder))
                (setq mh-draft-folder (format "+%s" mh-draft-folder)))
            (if (not (file-exists-p (mh-expand-file-name mh-draft-folder)))
                (error "Draft folder \"%s\" not found.  Create it and try again"
                       (mh-expand-file-name mh-draft-folder)))))
      (setq mh-inbox (mh-get-profile-field "Inbox:"))
      (cond ((not mh-inbox)
             (setq mh-inbox "+inbox"))
            ((not (mh-folder-name-p mh-inbox))
             (setq mh-inbox (format "+%s" mh-inbox))))
      (setq mh-unseen-seq (mh-get-profile-field "Unseen-Sequence:"))
      (if mh-unseen-seq
          (setq mh-unseen-seq (intern mh-unseen-seq))
        (setq mh-unseen-seq 'unseen))   ;old MH default?
      (setq mh-previous-seq (mh-get-profile-field "Previous-Sequence:"))
      (if mh-previous-seq
          (setq mh-previous-seq (intern mh-previous-seq)))
      (run-hooks 'mh-find-path-hook)))
  (and mh-auto-folder-collect-flag
       (let ((mh-no-install t))         ;only get folders if MH installed
         (condition-case err
             (mh-make-folder-list-background)
           (file-error)))))             ;so don't complain if not installed

(defun mh-file-command-p (file)
  "Return t if file FILE is the name of a executable regular file."
  (and (file-regular-p file) (file-executable-p file)))

(defun mh-find-progs ()
  "Find the directories for the installed MH/nmh binaries and config files.
Set the `mh-progs' and `mh-lib', and `mh-lib-progs' variables to the
directory names and set `mh-nmh-flag' if we detect nmh instead of MH."
  (unless (and mh-progs mh-lib mh-lib-progs)
    (let ((path (or (mh-path-search exec-path "mhparam")
                    (mh-path-search '("/usr/local/nmh/bin" ; nmh default
                                      "/usr/local/bin/mh/"
                                      "/usr/local/mh/"
                                      "/usr/bin/mh/" ;Ultrix 4.2, Linux
                                      "/usr/new/mh/" ;Ultrix <4.2
                                      "/usr/contrib/mh/bin/" ;BSDI
                                      "/usr/pkg/bin/" ; NetBSD
                                      "/usr/local/bin/"
                                      )
                                    "mhparam"))))
      (if (not path)
          (error "Unable to find the `mhparam' command"))
      (save-excursion
        (let ((tmp-buffer (get-buffer-create mh-temp-buffer)))
          (set-buffer tmp-buffer)
          (unwind-protect
              (progn
                (call-process (expand-file-name "mhparam" path)
                              nil '(t nil) nil "libdir" "etcdir")
                (goto-char (point-min))
                (if (search-forward-regexp "^libdir:\\s-\\(\\S-+\\)\\s-*$"
                                           nil t)
                    (setq mh-lib-progs (match-string 1)
                          mh-lib mh-lib-progs
                          mh-progs path))
                (goto-char (point-min))
                (if (search-forward-regexp "^etcdir:\\s-\\(\\S-+\\)\\s-*$"
                                           nil t)
                    (setq mh-lib (match-string 1)
                          mh-nmh-flag t)))
            (kill-buffer tmp-buffer))))
      (unless (and mh-progs mh-lib mh-lib-progs)
        (error "Unable to determine paths from `mhparam' command")))))

(defun mh-path-search (path file)
  "Search PATH, a list of directory names, for FILE.
Returns the element of PATH that contains FILE, or nil if not found."
  (while (and path
              (not (funcall 'mh-file-command-p
                            (expand-file-name file (car path)))))
    (setq path (cdr path)))
  (car path))

(defvar mh-no-install nil)              ;do not run install-mh

(defun mh-install (profile error-val)
  "Initialize the MH environment.
This is called if we fail to read the PROFILE file. ERROR-VAL is the error
that made this call necessary."
  (if (or (getenv "MH")
          (file-exists-p profile)
          mh-no-install)
      (signal (car error-val)
              (list (format "Cannot read MH profile \"%s\"" profile)
                    (car (cdr (cdr error-val))))))
  ;; The "install-mh" command will output a short note which
  ;; mh-exec-cmd will display to the user.
  ;; The MH 5 version of install-mh might try prompt the user
  ;; for information, which would fail here.
  (mh-exec-cmd (expand-file-name "install-mh" mh-lib-progs) "-auto")
  ;; now try again to read the profile file
  (erase-buffer)
  (condition-case err
      (insert-file-contents profile)
    (file-error
     (signal (car err)                  ;re-signal with more specific msg
             (list (format "Cannot read MH profile \"%s\"" profile)
                   (car (cdr (cdr err))))))))

(defun mh-set-folder-modified-p (flag)
  "Mark current folder as modified or unmodified according to FLAG."
  (set-buffer-modified-p flag))

(defun mh-find-seq (name)
  "Return sequence NAME."
  (assoc name mh-seq-list))

(defun mh-seq-to-msgs (seq)
  "Return a list of the messages in SEQ."
  (mh-seq-msgs (mh-find-seq seq)))

(defun mh-update-scan-format (fmt width)
  "Return a scan format with the (msg) width in the FMT replaced with WIDTH.

The message number width portion of the format is discovered using
`mh-scan-msg-format-regexp'. Its replacement is controlled with
`mh-scan-msg-format-string'."
  (or (and
       (string-match mh-scan-msg-format-regexp fmt)
       (let ((begin (match-beginning 1))
             (end (match-end 1)))
         (concat (substring fmt 0 begin)
                 (format mh-scan-msg-format-string width)
                 (substring fmt end))))
      fmt))
       
(defun mh-message-number-width (folder)
  "Return the widest message number in this FOLDER."
  (or mh-progs (mh-find-path))
  (let ((tmp-buffer (get-buffer-create mh-temp-buffer))
        (width 0))
    (save-excursion
      (set-buffer tmp-buffer)
      (erase-buffer)
      (apply 'call-process
             (expand-file-name "scan" mh-progs) nil '(t nil) nil
             (list folder "last" "-format" "%(msg)"))
      (goto-char (point-min))
      (if (re-search-forward mh-scan-msg-number-regexp nil 0 1)
          (setq width (length (buffer-substring
                               (match-beginning 1) (match-end 1))))))
    width))

(defun mh-add-msgs-to-seq (msgs seq &optional internal-flag)
  "Add MSGS to SEQ.
Remove duplicates and keep sequence sorted. If optional INTERNAL-FLAG is
non-nil, do not mark the message in the scan listing or inform MH of the
addition."
  (let ((entry (mh-find-seq seq)))
    (if (and msgs (atom msgs)) (setq msgs (list msgs)))
    (if (null entry)
        (setq mh-seq-list
              (cons (mh-make-seq seq (mh-canonicalize-sequence msgs))
                    mh-seq-list))
      (if msgs (setcdr entry (mh-canonicalize-sequence
                              (append msgs (mh-seq-msgs entry))))))
    (cond ((not internal-flag)
           (mh-add-to-sequence seq msgs)
           (mh-notate-seq seq mh-note-seq (1+ mh-cmd-note))))))

(defun mh-canonicalize-sequence (msgs)
  "Sort MSGS in decreasing order and remove duplicates."
  (let* ((sorted-msgs (sort (copy-sequence msgs) '>))
         (head sorted-msgs))
    (while (cdr head)
      (if (= (car head) (cadr head))
          (setcdr head (cddr head))
        (setq head (cdr head))))
    sorted-msgs))

(defvar mh-folder-hist nil)
(defvar mh-speed-folder-map)

(defun mh-prompt-for-folder (prompt default can-create
                                    &optional default-string)
  "Prompt for a folder name with PROMPT.
Returns the folder's name as a string. DEFAULT is used if the folder exists
and the user types return. If the CAN-CREATE flag is t, then a folder is
created if it doesn't already exist. If optional argument DEFAULT-STRING is
non-nil, use it in the prompt instead of DEFAULT.
The value of `mh-folder-list-change-hook' is a list of functions to be called,
with no arguments, whenever the cached folder list `mh-folder-list' is
changed."
  (if (null default)
      (setq default ""))
  (let* ((default-string (cond (default-string (format " [%s]? "
                                                       default-string))
                               ((equal "" default) "? ")
                               (t (format " [%s]? " default))))
         (prompt (format "%s folder%s" prompt default-string))
         read-name folder-name)
    (if (null mh-folder-list)
        (mh-set-folder-list))
    (while (and (setq read-name (completing-read prompt mh-folder-list nil nil
                                                 "+" 'mh-folder-hist))
                (equal read-name "")
                (equal default "")))
    (cond ((or (equal read-name "") (equal read-name "+"))
           (setq read-name default))
          ((not (mh-folder-name-p read-name))
           (setq read-name (format "+%s" read-name))))
    (if (or (not read-name) (equal "" read-name))
        (error "No folder specified"))
    (setq folder-name read-name)
    (cond ((and (> (length folder-name) 0)
                (eq (aref folder-name (1- (length folder-name))) ?/))
           (setq folder-name (substring folder-name 0 -1))))
    (let ((new-file-flag
           (not (file-exists-p (mh-expand-file-name folder-name)))))
      (cond ((and new-file-flag
                  (y-or-n-p
                   (format "Folder %s does not exist.  Create it? "
                           folder-name)))
             (message "Creating %s" folder-name)
             (mh-exec-cmd-error nil "folder" folder-name)
             (when (boundp 'mh-speed-folder-map)
               (mh-speed-add-folder folder-name))
             (message "Creating %s...done" folder-name)
             (setq mh-folder-list (cons (list read-name) mh-folder-list))
             (run-hooks 'mh-folder-list-change-hook))
            (new-file-flag
             (error "Folder %s is not created" folder-name))
            ((not (file-directory-p (mh-expand-file-name folder-name)))
             (error "\"%s\" is not a directory"
                    (mh-expand-file-name folder-name)))
            ((and (null (assoc read-name mh-folder-list))
                  (null (assoc (concat read-name "/") mh-folder-list)))
             (setq mh-folder-list (cons (list read-name) mh-folder-list))
             (run-hooks 'mh-folder-list-change-hook))))
    folder-name))

(defvar mh-make-folder-list-process nil) ;The background process collecting
                                         ;the folder list.

(defvar mh-folder-list-temp nil)        ;mh-folder-list as it is being built.

(defvar mh-folder-list-partial-line "") ;Start of last incomplete line from
                                        ;folder process.

(defun mh-set-folder-list ()
  "Set `mh-folder-list' correctly.
A useful function for the command line or for when you need to
sync by hand.  Format is in a form suitable for completing read.
The value of `mh-folder-list-change-hook' is a list of functions to be called,
with no arguments, once the list of folders has been created."
  (message "Collecting folder names...")
  (if (not mh-make-folder-list-process)
      (mh-make-folder-list-background))
  (while (eq (process-status mh-make-folder-list-process) 'run)
    (accept-process-output mh-make-folder-list-process))
  (setq mh-folder-list mh-folder-list-temp)
  (run-hooks 'mh-folder-list-change-hook)
  (setq mh-folder-list-temp nil)
  (delete-process mh-make-folder-list-process)
  (setq mh-make-folder-list-process nil)
  (message "Collecting folder names...done"))

(defun mh-make-folder-list-background ()
  "Start a background process to compute a list of the user's folders.
Call `mh-set-folder-list' to wait for the result."
  (cond
   ((not mh-make-folder-list-process)
    (unless mh-inbox
      (mh-find-path))
    (let ((process-connection-type nil))
      (setq mh-make-folder-list-process
            (start-process "folders" nil (expand-file-name "folders" mh-progs)
                           "-fast"
                           (if mh-recursive-folders-flag
                               "-recurse"
                             "-norecurse")))
      (set-process-filter mh-make-folder-list-process
                          'mh-make-folder-list-filter)
      (process-kill-without-query mh-make-folder-list-process)))))

(defun mh-make-folder-list-filter (process output)
  "Given the PROCESS \"folders -fast\", parse OUTPUT.
See also `set-process-filter'."
  (let ((position 0)
        line-end
        new-folder
        (prevailing-match-data (match-data)))
    (unwind-protect
        ;; make sure got complete line
        (while (setq line-end (string-match "\n" output position))
          (setq new-folder (format "+%s%s"
                                   mh-folder-list-partial-line
                                   (substring output position line-end)))
          (setq mh-folder-list-partial-line "")
          ;; is new folder a subfolder of previous?
          (if (and mh-folder-list-temp
                   (string-match
                    (regexp-quote
                     (concat (car (car mh-folder-list-temp)) "/"))
                    new-folder))
              ;; append slash to parent folder for better completion
              ;; (undone by mh-prompt-for-folder)
              (setq mh-folder-list-temp
                    (cons
                     (list new-folder)
                     (cons
                      (list (concat (car (car mh-folder-list-temp)) "/"))
                      (cdr mh-folder-list-temp))))
            (setq mh-folder-list-temp
                  (cons (list new-folder)
                        mh-folder-list-temp)))
          (setq position (1+ line-end)))
      (set-match-data prevailing-match-data))
    (setq mh-folder-list-partial-line (substring output position))))

;;; Issue commands to MH.

(defun mh-exec-cmd (command &rest args)
  "Execute mh-command COMMAND with ARGS.
The side effects are what is desired.
Any output is assumed to be an error and is shown to the user.
The output is not read or parsed by MH-E."
  (save-excursion
    (set-buffer (get-buffer-create mh-temp-buffer))
    (erase-buffer)
    (apply 'call-process
           (expand-file-name command mh-progs) nil t nil
           (mh-list-to-string args))
    (if (> (buffer-size) 0)
        (save-window-excursion
          (switch-to-buffer-other-window mh-temp-buffer)
          (sit-for 5)))))

(defun mh-exec-cmd-error (env command &rest args)
  "In environment ENV, execute mh-command COMMAND with ARGS.
ENV is nil or a string of space-separated \"var=value\" elements.
Signals an error if process does not complete successfully."
  (save-excursion
    (set-buffer (get-buffer-create mh-temp-buffer))
    (erase-buffer)
    (let ((status
           (if env
               ;; the shell hacks necessary here shows just how broken Unix is
               (apply 'call-process "/bin/sh" nil t nil "-c"
                      (format "%s %s ${1+\"$@\"}"
                              env
                              (expand-file-name command mh-progs))
                      command
                      (mh-list-to-string args))
             (apply 'call-process
                    (expand-file-name command mh-progs) nil t nil
                    (mh-list-to-string args)))))
      (mh-handle-process-error command status))))

(defun mh-exec-cmd-daemon (command &rest args)
  "Execute MH command COMMAND with ARGS in the background.
Any output from command is displayed in an asynchronous pop-up window."
  (save-excursion
    (set-buffer (get-buffer-create mh-temp-buffer))
    (erase-buffer))
  (let* ((process-connection-type nil)
         (process (apply 'start-process
                         command nil
                         (expand-file-name command mh-progs)
                         (mh-list-to-string args))))
    (set-process-filter process 'mh-process-daemon)))

(defun mh-process-daemon (process output)
  "PROCESS daemon that puts OUTPUT into a temporary buffer."
  (set-buffer (get-buffer-create mh-temp-buffer))
  (insert-before-markers output)
  (display-buffer mh-temp-buffer))

(defun mh-exec-cmd-quiet (raise-error command &rest args)
  "Signal RAISE-ERROR if COMMAND with ARGS fails.
Execute MH command COMMAND with ARGS.  ARGS is a list of strings.
Return at start of mh-temp buffer, where output can be parsed and used.
Returns value of `call-process', which is 0 for success, unless RAISE-ERROR is
non-nil, in which case an error is signaled if `call-process' returns non-0."
  (set-buffer (get-buffer-create mh-temp-buffer))
  (erase-buffer)
  (let ((value
         (apply 'call-process
                (expand-file-name command mh-progs) nil t nil
                args)))
    (goto-char (point-min))
    (if raise-error
        (mh-handle-process-error command value)
      value)))

(defun mh-profile-component (component)
  "Return COMPONENT value from mhparam, or nil if unset."
  (save-excursion
    (mh-exec-cmd-quiet nil "mhparam" "-components" component)
    (mh-get-profile-field (concat component ":"))))

(defun mh-exchange-point-and-mark-preserving-active-mark ()
  "Put the mark where point is now, and point where the mark is now.
This command works even when the mark is not active, and preserves whether the
mark is active or not."
  (interactive nil)
  (let ((is-active (and (boundp 'mark-active) mark-active)))
    (let ((omark (mark t)))
      (if (null omark)
          (error "No mark set in this buffer"))
      (set-mark (point))
      (goto-char omark)
      (if (boundp 'mark-active)
          (setq mark-active is-active))
      nil)))

(defun mh-exec-cmd-output (command display &rest args)
  "Execute MH command COMMAND with DISPLAY flag and ARGS.
Put the output into buffer after point.  Set mark after inserted text.
Output is expected to be shown to user, not parsed by MH-E."
  (push-mark (point) t)
  (apply 'call-process
         (expand-file-name command mh-progs) nil t display
         (mh-list-to-string args))

  ;; The following is used instead of 'exchange-point-and-mark because the
  ;; latter activates the current region (between point and mark), which
  ;; turns on highlighting.  So prior to this bug fix, doing "inc" would
  ;; highlight a region containing the new messages, which is undesirable.
  ;; The bug wasn't seen in emacs21 but still occurred in XEmacs21.4.
  (mh-exchange-point-and-mark-preserving-active-mark))

(defun mh-exec-lib-cmd-output (command &rest args)
  "Execute MH library command COMMAND with ARGS.
Put the output into buffer after point.  Set mark after inserted text."
  (apply 'mh-exec-cmd-output (expand-file-name command mh-lib-progs) nil args))

(defun mh-handle-process-error (command status)
  "Raise error if COMMAND returned non-zero STATUS, otherwise return STATUS.
STATUS is return value from `call-process'.
Program output is in current buffer.
If output is too long to include in error message, display the buffer."
  (cond ((eq status 0)                  ;success
         status)
        ((stringp status)               ;kill string
         (error "%s: %s" command status))
        (t                              ;exit code
         (cond
          ((= (buffer-size) 0)          ;program produced no error message
           (error "%s: exit code %d" command status))
          (t
           ;; will error message fit on one line?
           (goto-line 2)
           (if (and (< (buffer-size) (frame-width))
                    (eobp))
               (error "%s"
                      (buffer-substring 1 (progn (goto-char 1)
                                                 (end-of-line)
                                                 (point))))
             (display-buffer (current-buffer))
             (error "%s failed with status %d.  See error message in other window"
                    command status)))))))

(defun mh-list-to-string (l)
  "Flatten the list L and make every element of the new list into a string."
  (nreverse (mh-list-to-string-1 l)))

(defun mh-list-to-string-1 (l)
  "Flatten the list L and make every element of the new list into a string."
  (let ((new-list nil))
    (while l
      (cond ((null (car l)))
            ((symbolp (car l))
             (setq new-list (cons (symbol-name (car l)) new-list)))
            ((numberp (car l))
             (setq new-list (cons (int-to-string (car l)) new-list)))
            ((equal (car l) ""))
            ((stringp (car l)) (setq new-list (cons (car l) new-list)))
            ((listp (car l))
             (setq new-list (nconc (mh-list-to-string-1 (car l))
                                   new-list)))
            (t (error "Bad element in mh-list-to-string: %s" (car l))))
      (setq l (cdr l)))
    new-list))

(provide 'mh-utils)

;;; Local Variables:
;;; indent-tabs-mode: nil
;;; sentence-end-double-space: nil
;;; End:

;;; mh-utils.el ends here
