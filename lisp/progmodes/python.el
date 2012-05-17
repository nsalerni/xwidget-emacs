;;; python.el -- Python's flying circus support for Emacs

;; Copyright (C) 2010 Free Software Foundation, Inc.

;; Author: Fabián E. Gallina <fabian@anue.biz>
;; Maintainer: FSF
;; Created: Jul 2010
;; Keywords: languages

;; This file is NOT part of GNU Emacs.

;; python.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; python.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with python.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Major mode for editing Python files with some fontification and
;; indentation bits extracted from original Dave Love's python.el
;; found in GNU/Emacs.

;; While it probably has less features than Dave Love's python.el and
;; PSF's python-mode.el it provides the main stuff you'll need while
;; keeping it simple :)

;; Implements Syntax highlighting, Indentation, Movement, Shell
;; interaction, Shell completion, Pdb tracking, Symbol completion,
;; Eldoc.

;; Syntax highlighting: Fontification of code is provided and supports
;; python's triple quoted strings properly.

;; Indentation: Automatic indentation with indentation cycling is
;; provided, it allows you to navigate different available levels of
;; indentation by hitting <tab> several times.

;; Movement: `beginning-of-defun' and `end-of-defun' functions are
;; properly implemented.  A `beginning-of-innermost-defun' is defined
;; to navigate nested defuns.

;; Shell interaction: is provided and allows you easily execute any
;; block of code of your current buffer in an inferior Python process.

;; Shell completion: hitting tab will try to complete the current
;; word. Shell completion is implemented in a manner that if you
;; change the `python-shell-interpreter' to any other (for example
;; IPython) it should be easy to integrate another way to calculate
;; completions. You just need to especify your custom
;; `python-shell-completion-setup-code' and
;; `python-shell-completion-strings-code'

;; Pdb tracking: when you execute a block of code that contains some
;; call to pdb (or ipdb) it will prompt the block of code and will
;; follow the execution of pdb marking the current line with an arrow.

;; Symbol completion: you can complete the symbol at point. It uses
;; the shell completion in background so you should run
;; `python-shell-send-buffer' from time to time to get better results.

;; Eldoc: returns documentation for object at point by using the
;; inferior python subprocess to inspect its documentation. As you
;; might guessed you should run `python-shell-send-buffer' from time
;; to time to get better results too.

;;; Installation:

;; Add this to your .emacs:

;; (add-to-list 'load-path "/folder/containing/file")
;; (require 'python)

;;; TODO:

;; Ordered by priority:

;; Better decorator support for beginning of defun

;; Fix shell autocompletion when: obj.<tab>

;; Remove garbage prompts left from calls to `comint-send-string' and
;; other comint related cleanups.

;; Review code and cleanup

;;; Code:

(require 'comint)
(require 'ansi-color)
(require 'outline)

(eval-when-compile
  (require 'cl))

(autoload 'comint-mode "comint")

;;;###autoload
(add-to-list 'auto-mode-alist (cons (purecopy "\\.py\\'")  'python-mode))
;;;###autoload
(add-to-list 'interpreter-mode-alist (cons (purecopy "python") 'python-mode))

(defgroup python nil
  "Python Language's flying circus support for Emacs."
  :group 'languages
  :version "23.2"
  :link '(emacs-commentary-link "python"))


;;; Bindings

(defvar python-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Indent specific
    (define-key map "\177" 'python-indent-dedent-line-backspace)
    (define-key map (kbd "<backtab>") 'python-indent-dedent-line)
    (define-key map "\C-c<" 'python-indent-shift-left)
    (define-key map "\C-c>" 'python-indent-shift-right)
    ;; Shell interaction
    (define-key map "\C-c\C-s" 'python-shell-send-string)
    (define-key map "\C-c\C-r" 'python-shell-send-region)
    (define-key map "\C-\M-x" 'python-shell-send-defun)
    (define-key map "\C-c\C-c" 'python-shell-send-buffer)
    (define-key map "\C-c\C-l" 'python-shell-send-file)
    (define-key map "\C-c\C-z" 'python-shell-switch-to-shell)
    ;; Utilities
    (substitute-key-definition 'complete-symbol 'completion-at-point
			       map global-map)
    (easy-menu-define python-menu map "Python Mode menu"
      `("Python"
	:help "Python-specific Features"
	["Shift region left" python-indent-shift-left :active mark-active
	 :help "Shift region left by a single indentation step"]
	["Shift region right" python-indent-shift-right :active mark-active
	 :help "Shift region right by a single indentation step"]
	"-"
	["Mark def/class" mark-defun
	 :help "Mark outermost definition around point"]
	"-"
	["Start of def/class" beginning-of-defun
	 :help "Go to start of outermost definition around point"]
	["Start of def/class" python-beginning-of-innermost-defun
	 :help "Go to start of innermost definition around point"]
	["End of def/class" end-of-defun
	 :help "Go to end of definition around point"]
        "-"
	["Start interpreter" run-python
	 :help "Run inferior Python process in a separate buffer"]
	["Switch to shell" python-shell-switch-to-shell
	 :help "Switch to running inferior Python process"]
	["Eval string" python-shell-send-string
	 :help "Eval string in inferior Python session"]
	["Eval buffer" python-shell-send-buffer
	 :help "Eval buffer in inferior Python session"]
	["Eval region" python-shell-send-region
	 :help "Eval region in inferior Python session"]
	["Eval defun" python-shell-send-defun
	 :help "Eval defun in inferior Python session"]
	["Eval file" python-shell-send-file
	 :help "Eval file in inferior Python session"]
	["Debugger" pdb :help "Run pdb under GUD"]
        "-"
	["Complete symbol" completion-at-point
	 :help "Complete symbol before point"]))
    map)
  "Keymap for `python-mode'.")


;;; Python specialized rx

(defconst python-rx-constituents
  (list
   `(block-start          . ,(rx symbol-start
                               (or "def" "class" "if" "elif" "else" "try"
                                   "except" "finally" "for" "while" "with")
                               symbol-end))
   `(defun                . ,(rx symbol-start (or "def" "class") symbol-end))
   `(open-paren           . ,(rx (or "{" "[" "(")))
   `(close-paren          . ,(rx (or "}" "]" ")")))
   `(simple-operator      . ,(rx (any ?+ ?- ?/ ?& ?^ ?~ ?| ?* ?< ?> ?= ?%)))
   `(not-simple-operator  . ,(rx (not (any ?+ ?- ?/ ?& ?^ ?~ ?| ?* ?< ?> ?= ?%))))
   `(operator             . ,(rx (or "+" "-" "/" "&" "^" "~" "|" "*" "<" ">"
                                     "=" "%" "**" "//" "<<" ">>" "<=" "!="
                                     "==" ">=" "is" "not")))
   `(assignment-operator  . ,(rx (or "=" "+=" "-=" "*=" "/=" "//=" "%=" "**="
                                     ">>=" "<<=" "&=" "^=" "|=")))))

(defmacro python-rx (&rest regexps)
 "Python mode especialized rx macro which supports common python named regexps."
 (let ((rx-constituents (append python-rx-constituents rx-constituents)))
   (cond ((null regexps)
          (error "No regexp"))
         ((cdr regexps)
          (rx-to-string `(and ,@regexps) t))
         (t
          (rx-to-string (car regexps) t)))))


;;; Font-lock and syntax

(defvar python-font-lock-keywords
  ;; Keywords
  `(,(rx symbol-start
         (or "and" "del" "from" "not" "while" "as" "elif" "global" "or" "with"
             "assert" "else" "if" "pass" "yield" "break" "except" "import"
             "print" "class" "exec" "in" "raise" "continue" "finally" "is"
             "return" "def" "for" "lambda" "try" "self")
         symbol-end)
    ;; functions
    (,(rx symbol-start "def" (1+ space) (group (1+ (or word ?_))))
     (1 font-lock-function-name-face))
    ;; classes
    (,(rx symbol-start "class" (1+ space) (group (1+ (or word ?_))))
     (1 font-lock-type-face))
    ;; Constants
    (,(rx symbol-start (group "None" symbol-end))
     (1 font-lock-constant-face))
    ;; Decorators.
    (,(rx line-start (* (any " \t")) (group "@" (1+ (or word ?_))
                                            (0+ "." (1+ (or word ?_)))))
     (1 font-lock-type-face))
    ;; Builtin Exceptions
    (,(rx symbol-start
          (or "ArithmeticError" "AssertionError" "AttributeError"
              "BaseException" "BufferError" "BytesWarning" "DeprecationWarning"
              "EOFError" "EnvironmentError" "Exception" "FloatingPointError"
              "FutureWarning" "GeneratorExit" "IOError" "ImportError"
              "ImportWarning" "IndentationError" "IndexError" "KeyError"
              "KeyboardInterrupt" "LookupError" "MemoryError" "NameError"
              "NotImplemented" "NotImplementedError" "OSError" "OverflowError"
              "PendingDeprecationWarning" "ReferenceError" "RuntimeError"
              "RuntimeWarning" "StandardError" "StopIteration" "SyntaxError"
              "SyntaxWarning" "SystemError" "SystemExit" "TabError" "TypeError"
              "UnboundLocalError" "UnicodeDecodeError" "UnicodeEncodeError"
              "UnicodeError" "UnicodeTranslateError" "UnicodeWarning"
              "UserWarning" "ValueError" "Warning" "ZeroDivisionError")
          symbol-end) . font-lock-type-face)
    ;; Builtins
    (,(rx (or line-start (not (any ". \t"))) (* (any " \t")) symbol-start
	  (group
           (or "_" "__debug__" "__doc__" "__import__" "__name__" "__package__"
               "abs" "all" "any" "apply" "basestring" "bin" "bool" "buffer"
               "bytearray" "bytes" "callable" "chr" "classmethod" "cmp" "coerce"
               "compile" "complex" "copyright" "credits" "delattr" "dict" "dir"
               "divmod" "enumerate" "eval" "execfile" "exit" "file" "filter"
               "float" "format" "frozenset" "getattr" "globals" "hasattr" "hash"
               "help" "hex" "id" "input" "int" "intern" "isinstance" "issubclass"
               "iter" "len" "license" "list" "locals" "long" "map" "max" "min"
               "next" "object" "oct" "open" "ord" "pow" "print" "property" "quit"
               "range" "raw_input" "reduce" "reload" "repr" "reversed" "round"
               "set" "setattr" "slice" "sorted" "staticmethod" "str" "sum"
               "super" "tuple" "type" "unichr" "unicode" "vars" "xrange" "zip"
               "True" "False" "Ellipsis")) symbol-end)
     (1 font-lock-builtin-face))
    ;; asignations
    ;; support for a = b = c = 5
    (,(lambda (limit)
        (let ((re (python-rx (group (+ (any word ?. ?_))) (* space)
                             assignment-operator)))
          (when (re-search-forward re limit t)
            (while (and (not (equal (nth 0 (syntax-ppss)) 0))
                        (re-search-forward re limit t)))
            (if (equal (nth 0 (syntax-ppss)) 0)
                t
              (set-match-data nil)))))
     (1 font-lock-variable-name-face nil nil))
    ;; support for a, b, c = (1, 2, 3)
    (,(lambda (limit)
        (let ((re (python-rx (group (+ (any word ?. ?_))) (* space)
                             (* ?, (* space) (+ (any word ?. ?_)) (* space))
                             ?, (* space) (+ (any word ?. ?_)) (* space)
                             assignment-operator)))
          (when (and (re-search-forward re limit t)
                     (goto-char (nth 3 (match-data))))
            (while (and (not (equal (nth 0 (syntax-ppss)) 0))
                        (re-search-forward re limit t))
              (goto-char (nth 3 (match-data))))
            (if (equal (nth 0 (syntax-ppss)) 0)
                t
              (set-match-data nil)))))
     (1 font-lock-variable-name-face nil nil))))

;; Fixme: Is there a better way?
(defconst python-font-lock-syntactic-keywords
  ;; First avoid a sequence preceded by an odd number of backslashes.
  `((,(rx (not (any ?\\))
	  ?\\ (* (and ?\\ ?\\))
	  (group (syntax string-quote))
	  (backref 1)
	  (group (backref 1)))
     (2 ,(string-to-syntax "\"")))	; dummy
    (,(rx (group (optional (any "uUrR"))) ; prefix gets syntax property
	  (optional (any "rR"))		  ; possible second prefix
	  (group (syntax string-quote))   ; maybe gets property
	  (backref 2)			  ; per first quote
	  (group (backref 2)))		  ; maybe gets property
     (1 (python-quote-syntax 1))
     (2 (python-quote-syntax 2))
     (3 (python-quote-syntax 3))))
  "Make outer chars of triple-quote strings into generic string delimiters.")

(defun python-quote-syntax (n)
  "Put `syntax-table' property correctly on triple quote.
Used for syntactic keywords.  N is the match number (1, 2 or 3)."
  ;; Given a triple quote, we have to check the context to know
  ;; whether this is an opening or closing triple or whether it's
  ;; quoted anyhow, and should be ignored.  (For that we need to do
  ;; the same job as `syntax-ppss' to be correct and it seems to be OK
  ;; to use it here despite initial worries.)  We also have to sort
  ;; out a possible prefix -- well, we don't _have_ to, but I think it
  ;; should be treated as part of the string.

  ;; Test cases:
  ;;  ur"""ar""" x='"' # """
  ;; x = ''' """ ' a
  ;; '''
  ;; x '"""' x """ \"""" x
  (save-excursion
    (goto-char (match-beginning 0))
    (cond
     ;; Consider property for the last char if in a fenced string.
     ((= n 3)
      (let* ((font-lock-syntactic-keywords nil)
	     (syntax (syntax-ppss)))
	(when (eq t (nth 3 syntax))	; after unclosed fence
	  (goto-char (nth 8 syntax))	; fence position
	  (skip-chars-forward "uUrR")	; skip any prefix
	  ;; Is it a matching sequence?
	  (if (eq (char-after) (char-after (match-beginning 2)))
	      (eval-when-compile (string-to-syntax "|"))))))
     ;; Consider property for initial char, accounting for prefixes.
     ((or (and (= n 2)			; leading quote (not prefix)
	       (= (match-beginning 1) (match-end 1))) ; prefix is null
	  (and (= n 1)			; prefix
	       (/= (match-beginning 1) (match-end 1)))) ; non-empty
      (let ((font-lock-syntactic-keywords nil))
	(unless (eq 'string (syntax-ppss-context (syntax-ppss)))
	  (eval-when-compile (string-to-syntax "|")))))
     ;; Otherwise (we're in a non-matching string) the property is
     ;; nil, which is OK.
     )))

(defvar python-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Give punctuation syntax to ASCII that normally has symbol
    ;; syntax or has word syntax and isn't a letter.
    (let ((symbol (string-to-syntax "_"))
	  (sst (standard-syntax-table)))
      (dotimes (i 128)
	(unless (= i ?_)
	  (if (equal symbol (aref sst i))
	      (modify-syntax-entry i "." table)))))
    (modify-syntax-entry ?$ "." table)
    (modify-syntax-entry ?% "." table)
    ;; exceptions
    (modify-syntax-entry ?# "<" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?' "\"" table)
    (modify-syntax-entry ?` "$" table)
    table)
  "Syntax table for Python files.")

(defvar python-dotty-syntax-table
  (let ((table (make-syntax-table python-mode-syntax-table)))
    (modify-syntax-entry ?. "w" table)
    (modify-syntax-entry ?_ "w" table)
    table)
  "Dotty syntax table for Python files.
It makes underscores and dots word constituent chars.")


;;; Indentation

(defcustom python-indent-offset 4
  "Default indentation offset for Python."
  :group 'python
  :type 'integer
  :safe 'integerp)

(defcustom python-indent-guess-indent-offset t
  "Non-nil tells Python mode to guess `python-indent-offset' value."
  :type 'boolean
  :group 'python)

(defvar python-indent-current-level 0
  "Current indentation level `python-indent-line-function' is using.")

(defvar python-indent-levels '(0)
  "Levels of indentation available for `python-indent-line-function'.")

(defvar python-indent-dedenters '("else" "elif" "except" "finally")
  "List of words that should be dedented.
These make `python-indent-calculate-indentation' subtract the value of
`python-indent-offset'.")

(defun python-indent-guess-indent-offset ()
  "Guess and set the value for `python-indent-offset' given the current buffer."
  (let ((guessed-indentation (save-excursion
                               (goto-char (point-min))
                               (re-search-forward ":\\s-*\n" nil t)
                               (while (and (not (eobp)) (forward-comment 1)))
                               (current-indentation))))
    (when (not (equal guessed-indentation 0))
      (setq python-indent-offset guessed-indentation))))

(defun python-indent-context (&optional stop)
  "Return information on indentation context.
Optional argument STOP serves to stop recursive calls.

Returns a cons with the form:

\(STATUS . START)

Where status can be any of the following symbols:

 * inside-paren: If point in between (), {} or []
 * inside-string: If point is inside a string
 * after-backslash: Previous line ends in a backslash
 * after-beginning-of-block: Point is after beginning of block
 * after-line: Point is after normal line
 * no-indent: Point is at beginning of buffer or other special case

START is the buffer position where the sexp starts."
  (save-restriction
    (widen)
    (let ((ppss (save-excursion (beginning-of-line) (syntax-ppss)))
          (start))
      (cons
       (cond
        ;; Inside a paren
        ((setq start (nth 1 ppss))
         'inside-paren)
        ;; Inside string
        ((setq start (when (and (nth 3 ppss))
                       (nth 8 ppss)))
         'inside-string)
        ;; After backslash
        ((setq start (when (not (syntax-ppss-context ppss))
                       (let ((line-beg-pos (line-beginning-position)))
                         (when (eq ?\\ (char-before (1- line-beg-pos)))
                           (- line-beg-pos 2)))))
         'after-backslash)
        ;; After beginning of block
        ((setq start (save-excursion
                       (let ((block-regexp (python-rx block-start))
                             (block-start-line-end ":[[:space:]]*$"))
                         (back-to-indentation)
                         (while (and (forward-comment -1) (not (bobp))))
                         (back-to-indentation)
                         (when (or (python-info-continuation-line-p)
                                   (and (not (looking-at block-regexp))
                                        (save-excursion
                                          (re-search-forward
                                           block-start-line-end
                                           (line-end-position) t))))
                           (while (and (forward-line -1)
                                       (python-info-continuation-line-p)
                                       (not (bobp))))
                           (when (not (looking-at block-regexp))
                             (forward-line 1)))
                         (back-to-indentation)
                         (when (and (looking-at block-regexp)
                                    (or (re-search-forward
                                         block-start-line-end
                                         (line-end-position) t)
                                        (python-info-continuation-line-p)))
                           (point-marker)))))
         'after-beginning-of-block)
        ;; After normal line
        ((setq start (save-excursion
                       (while (and (forward-comment -1) (not (bobp))))
                       (while (and (not (back-to-indentation))
                                   (not (bobp))
                                   (if (> (nth 0 (syntax-ppss)) 0)
                                       (forward-line -1)
                                     (if (save-excursion
                                           (forward-line -1)
                                           (python-info-line-ends-backslash-p))
                                         (forward-line -1)))))
                       (point-marker)))
         'after-line)
        ;; Do not indent
        (t 'no-indent))
       start))))

(defun python-indent-calculate-indentation ()
  "Calculate correct indentation offset for the current line."
  (let* ((indentation-context (python-indent-context))
         (context-status (car indentation-context))
         (context-start (cdr indentation-context)))
    (save-restriction
      (widen)
      (save-excursion
        (case context-status
          ('no-indent 0)
          ('after-beginning-of-block
           (goto-char context-start)
           (+ (current-indentation) python-indent-offset))
          ('after-line
           (-
            (save-excursion
              (goto-char context-start)
              (current-indentation))
            (if (progn
                  (back-to-indentation)
                  (looking-at (regexp-opt python-indent-dedenters)))
                python-indent-offset
              0)))
          ('inside-string
           (goto-char context-start)
           (current-indentation))
          ('after-backslash
           (let* ((block-continuation
                   (save-excursion
                     (forward-line -1)
                     (python-info-block-continuation-line-p)))
                  (assignment-continuation
                   (save-excursion
                     (forward-line -1)
                     (python-info-assignment-continuation-line-p)))
                  (indentation (cond (block-continuation
                                      (goto-char block-continuation)
                                      (re-search-forward
                                       (python-rx block-start (* space))
                                       (line-end-position) t)
                                      (current-column))
                                     (assignment-continuation
                                      (goto-char assignment-continuation)
                                      (re-search-forward
                                       (python-rx simple-operator)
                                       (line-end-position) t)
                                      (forward-char 1)
                                      (re-search-forward
                                       (python-rx (* space))
                                       (line-end-position) t)
                                      (current-column))
                                     (t
                                      (goto-char context-start)
                                      (current-indentation)))))
             indentation))
          ('inside-paren
           (-
            (save-excursion
              (goto-char context-start)
              (forward-char)
              (if (looking-at "[[:space:]]*$")
                  (+ (current-indentation) python-indent-offset)
                (forward-comment 1)
                (current-column)))
            (if (progn
                  (back-to-indentation)
                  (looking-at (regexp-opt '(")" "]" "}"))))
                python-indent-offset
              0))))))))

(defun python-indent-calculate-levels ()
  "Calculate `python-indent-levels' and reset `python-indent-current-level'."
  (let* ((indentation (python-indent-calculate-indentation))
         (remainder (% indentation python-indent-offset))
         (steps (/ (- indentation remainder) python-indent-offset)))
    (setq python-indent-levels '())
    (setq python-indent-levels (cons 0 python-indent-levels))
    (dotimes (step steps)
      (setq python-indent-levels
            (cons (* python-indent-offset (1+ step)) python-indent-levels)))
    (when (not (eq 0 remainder))
      (setq python-indent-levels
            (cons (+ (* python-indent-offset steps) remainder)
                  python-indent-levels)))
    (setq python-indent-levels (nreverse python-indent-levels))
    (setq python-indent-current-level (1- (length python-indent-levels)))))

(defun python-indent-toggle-levels ()
  "Toggle `python-indent-current-level' over `python-indent-levels'."
  (setq python-indent-current-level (1- python-indent-current-level))
  (when (< python-indent-current-level 0)
    (setq python-indent-current-level (1- (length python-indent-levels)))))

(defun python-indent-line (&optional force-toggle)
  "Internal implementation of `python-indent-line-function'.

Uses the offset calculated in
`python-indent-calculate-indentation' and available levels
indicated by the variable `python-indent-levels'.

When the variable `last-command' is equal to
`indent-for-tab-command' or FORCE-TOGGLE is non-nil:

* Cycles levels indicated in the variable `python-indent-levels'
  by setting the current level in the variable
  `python-indent-current-level'.

When the variable `last-command' is not equal to
`indent-for-tab-command' and FORCE-TOGGLE is nil:

* calculates possible indentation levels and saves it in the
  variable `python-indent-levels'.

* sets the variable `python-indent-current-level' correctly so
  offset is equal to (`nth' `python-indent-current-level'
  `python-indent-levels')"
  (if (or (and (eq this-command 'indent-for-tab-command)
               (eq last-command this-command))
          force-toggle)
      (python-indent-toggle-levels)
    (python-indent-calculate-levels))
  (beginning-of-line)
  (delete-horizontal-space)
  (indent-to (nth python-indent-current-level python-indent-levels))
  (save-restriction
    (widen)
    (let ((closing-block-point (python-info-closing-block)))
      (when closing-block-point
        (message "Closes %s" (buffer-substring
                              closing-block-point
                              (save-excursion
                                (goto-char closing-block-point)
                                (line-end-position))))))))

(defun python-indent-line-function ()
  "`indent-line-function' for Python mode.
Internally just calls `python-indent-line'."
  (python-indent-line))

(defun python-indent-dedent-line ()
  "Dedent current line."
  (interactive "*")
  (when (and (not (syntax-ppss-context (syntax-ppss)))
             (<= (point-marker) (save-excursion
                                  (back-to-indentation)
                                  (point-marker)))
             (> (current-column) 0))
    (python-indent-line t)
    t))

(defun python-indent-dedent-line-backspace (arg)
  "Dedent current line.
Argument ARG is passed to `backward-delete-char-untabify' when
point is not in between the indentation."
  (interactive "*p")
  (when (not (python-indent-dedent-line))
    (backward-delete-char-untabify arg)))

(defun python-indent-region (start end)
  "Indent a python region automagically.

Called from a program, START and END specify the region to indent."
  (save-excursion
    (goto-char end)
    (setq end (point-marker))
    (goto-char start)
    (or (bolp) (forward-line 1))
    (while (< (point) end)
      (or (and (bolp) (eolp))
          (let (word)
	    (forward-line -1)
	    (back-to-indentation)
	    (setq word (current-word))
	    (forward-line 1)
	    (when word
	      (beginning-of-line)
	      (delete-horizontal-space)
	      (indent-to (python-indent-calculate-indentation)))))
      (forward-line 1))
    (move-marker end nil)))

(defun python-indent-shift-left (start end &optional count)
  "Shift lines contained in region START END by COUNT columns to the left.

COUNT defaults to `python-indent-offset'.

If region isn't active, the current line is shifted.

The shifted region includes the lines in which START and END lie.

An error is signaled if any lines in the region are indented less
than COUNT columns."
  (interactive
   (if mark-active
       (list (region-beginning) (region-end) current-prefix-arg)
     (list (line-beginning-position) (line-end-position) current-prefix-arg)))
  (if count
      (setq count (prefix-numeric-value count))
    (setq count python-indent-offset))
  (when (> count 0)
    (save-excursion
      (goto-char start)
      (while (< (point) end)
	(if (and (< (current-indentation) count)
		 (not (looking-at "[ \t]*$")))
	    (error "Can't shift all lines enough"))
	(forward-line))
      (indent-rigidly start end (- count)))))

(add-to-list 'debug-ignored-errors "^Can't shift all lines enough")

(defun python-indent-shift-right (start end &optional count)
  "Shift lines contained in region START END by COUNT columns to the left.

COUNT defaults to `python-indent-offset'.

If region isn't active, the current line is shifted.

The shifted region includes the lines in which START and END
lie."
  (interactive
   (if mark-active
       (list (region-beginning) (region-end) current-prefix-arg)
     (list (line-beginning-position) (line-end-position) current-prefix-arg)))
  (if count
      (setq count (prefix-numeric-value count))
    (setq count python-indent-offset))
  (indent-rigidly start end count))


;;; Navigation

(defvar python-beginning-of-defun-regexp
  "^\\(def\\|class\\)[[:space:]]+[[:word:]]+"
  "Regular expresion matching beginning of outermost class or function.")

(defvar python-beginning-of-innermost-defun-regexp
  "^[[:space:]]*\\(def\\|class\\)[[:space:]]+[[:word:]]+"
  "Regular expresion matching beginning of innermost class or function.")

(defun python-beginning-of-defun (&optional innermost)
  "Move point to the beginning of innermost/outermost def or class.
If INNERMOST is non-nil then move to the beginning of the
innermost definition."
  (let ((starting-point (point-marker))
        (nonblank-line-indent)
        (defun-indent)
        (defun-point)
        (regexp (if innermost
                    python-beginning-of-innermost-defun-regexp
                  python-beginning-of-defun-regexp)))
    (back-to-indentation)
    (if (and (not (looking-at "@"))
             (not (looking-at regexp)))
        (forward-comment -1)
      (while (and (not (eobp))
                  (forward-line 1)
                  (not (back-to-indentation))
                  (looking-at "@"))))
    (when (not (looking-at regexp))
        (re-search-backward regexp nil t))
    (setq nonblank-line-indent (+ (current-indentation) python-indent-offset))
    (setq defun-indent (current-indentation))
    (setq defun-point (point-marker))
    (if (> nonblank-line-indent defun-indent)
        (progn
          (goto-char defun-point)
          (forward-line -1)
          (while (and (looking-at "@")
                      (forward-line -1)
                      (not (bobp))
                      (not (back-to-indentation))))
          (forward-line 1)
          (point-marker))
      (if innermost
          (python-beginning-of-defun)
        (goto-char starting-point)
        nil))))

(defun python-beginning-of-defun-function ()
  "Move point to the beginning of outermost def or class.
Returns nil if point is not in a def or class."
  (python-beginning-of-defun nil))

(defun python-beginning-of-innermost-defun ()
  "Move point to the beginning of innermost def or class.
Returns nil if point is not in a def or class."
  (interactive)
  (python-beginning-of-defun t))

(defun python-end-of-defun-function ()
  "Move point to the end of def or class.
Returns nil if point is not in a def or class."
  (let ((starting-point (point-marker))
        (defun-regexp (python-rx defun))
        (beg-defun-indent))
    (back-to-indentation)
    (if (looking-at "@")
	(while (and (not (eobp))
		    (forward-line 1)
		    (not (back-to-indentation))
		    (looking-at "@")))
      (while (and (not (bobp))
		  (not (progn (back-to-indentation) (current-word)))
		  (forward-line -1))))
    (when (or (not (equal (current-indentation) 0))
              (string-match defun-regexp (current-word)))
      (setq beg-defun-indent (save-excursion
        		       (or (looking-at defun-regexp)
        			   (python-beginning-of-innermost-defun))
        		       (current-indentation)))
      (while (and (forward-line 1)
        	  (not (eobp))
        	  (or (not (current-word))
                      (> (current-indentation) beg-defun-indent))))
      (while (and (forward-comment -1)
        	  (not (bobp))))
      (forward-line 1)
      (point-marker))))


;;; Shell integration

(defvar python-shell-buffer-name "Python"
  "Default buffer name for Python interpreter.")

(defcustom python-shell-interpreter "python"
  "Default Python interpreter for shell."
  :group 'python
  :type 'string
  :safe 'stringp)

(defcustom python-shell-interpreter-args "-i"
  "Default arguments for the Python interpreter."
  :group 'python
  :type 'string
  :safe 'stringp)

(defcustom python-shell-prompt-regexp ">>> "
  "Regex matching top\-level input prompt of python shell.
The regex should not contain a caret (^) at the beginning."
  :type 'string
  :group 'python
  :safe 'stringp)

(defcustom python-shell-prompt-block-regexp "[.][.][.] "
  "Regex matching block input prompt of python shell.
The regex should not contain a caret (^) at the beginning."
  :type 'string
  :group 'python
  :safe 'stringp)

(defcustom python-shell-prompt-pdb-regexp "[(<]*[Ii]?[Pp]db[>)]+ "
  "Regex matching pdb input prompt of python shell.
The regex should not contain a caret (^) at the beginning."
  :type 'string
  :group 'python
  :safe 'stringp)

(defcustom python-shell-compilation-regexp-alist
  `((,(rx line-start (1+ (any " \t")) "File \""
	  (group (1+ (not (any "\"<")))) ; avoid `<stdin>' &c
	  "\", line " (group (1+ digit)))
     1 2)
    (,(rx " in file " (group (1+ not-newline)) " on line "
	  (group (1+ digit)))
     1 2)
    (,(rx line-start "> " (group (1+ (not (any "(\"<"))))
	  "(" (group (1+ digit)) ")" (1+ (not (any "("))) "()")
     1 2))
  "`compilation-error-regexp-alist' for inferior Python."
  :type '(alist string)
  :group 'python)

(defun python-shell-get-process-name (dedicated)
  "Calculate the appropiate process name for inferior Python process.

If DEDICATED is t and the variable `buffer-file-name' is non-nil
returns a string with the form
`python-shell-buffer-name'[variable `buffer-file-name'] else
returns the value of `python-shell-buffer-name'.

After calculating the process name add the buffer name for the
process in the `same-window-buffer-names' list"
  (let ((process-name
         (if (and dedicated
                  buffer-file-name)
             (format "%s[%s]" python-shell-buffer-name buffer-file-name)
           (format "%s" python-shell-buffer-name))))
    (add-to-list 'same-window-buffer-names (purecopy
                                            (format "*%s*" process-name)))
    process-name))

(defun python-shell-parse-command ()
  "Calculates the string used to execute the inferior Python process."
  (format "%s %s" python-shell-interpreter python-shell-interpreter-args))

(defun python-comint-output-filter-function (output)
  "Hook run after content is put into comint buffer.
OUTPUT is a string with the contents of the buffer."
  (ansi-color-filter-apply output))

(defvar inferior-python-mode-current-file nil
  "Current file from which a region was sent.")
(make-variable-buffer-local 'inferior-python-mode-current-file)

(defvar inferior-python-mode-current-temp-file nil
  "Current temp file sent to process.")
(make-variable-buffer-local 'inferior-python-mode-current-file)

(define-derived-mode inferior-python-mode comint-mode "Inferior Python"
  "Major mode for Python inferior process."
  (set-syntax-table python-mode-syntax-table)
  (setq mode-line-process '(":%s"))
  (setq comint-prompt-regexp (format "^\\(?:%s\\|%s\\|%s\\)"
                                     python-shell-prompt-regexp
                                     python-shell-prompt-block-regexp
                                     python-shell-prompt-pdb-regexp))
  (make-local-variable 'comint-output-filter-functions)
  (add-hook 'comint-output-filter-functions
            'python-comint-output-filter-function)
  (add-hook 'comint-output-filter-functions
            'python-pdbtrack-comint-output-filter-function)
  (set (make-local-variable 'compilation-error-regexp-alist)
       python-shell-compilation-regexp-alist)
  (compilation-shell-minor-mode 1))

(defun run-python (dedicated cmd)
  "Run an inferior Python process.

Input and output via buffer *\\[python-shell-buffer-name]*.

If there is a process already running in
*\\[python-shell-buffer-name]*, switch to that buffer.

With argument, allows you to:

 * Define DEDICATED so a dedicated process for the current buffer
   is open.

 * Define CMD so you can edit the command used to call the
interpreter (default is value of `python-shell-interpreter' and
arguments defined in `python-shell-interpreter-args').

Runs the hook `inferior-python-mode-hook' (after the
`comint-mode-hook' is run).

\(Type \\[describe-mode] in the process buffer for a list of
commands.)"
  (interactive
   (if current-prefix-arg
       (list
        (y-or-n-p "Make dedicated process? ")
        (read-string "Run Python: " (python-shell-parse-command)))
     (list nil (python-shell-parse-command))))
  (let* ((proc-name (python-shell-get-process-name dedicated))
         (proc-buffer-name (format "*%s*" proc-name)))
    (when (not (comint-check-proc proc-buffer-name))
      (let ((cmdlist (split-string-and-unquote cmd)))
        (set-buffer
         (apply 'make-comint proc-name (car cmdlist) nil
                (cdr cmdlist)))
        (inferior-python-mode)))
    (pop-to-buffer proc-buffer-name))
  dedicated)

(defun python-shell-get-process ()
  "Get inferior Python process for current buffer and return it."
  (let* ((dedicated-proc-name (python-shell-get-process-name t))
         (dedicated-proc-buffer-name (format "*%s*" dedicated-proc-name))
         (global-proc-name  (python-shell-get-process-name nil))
         (global-proc-buffer-name (format "*%s*" global-proc-name))
         (dedicated-running (comint-check-proc dedicated-proc-buffer-name))
         (global-running (comint-check-proc global-proc-buffer-name)))
    ;; Always prefer dedicated
    (get-buffer-process (or (and dedicated-running dedicated-proc-buffer-name)
                            (and global-running global-proc-buffer-name)))))

(defun python-shell-get-or-create-process ()
  "Get or create an inferior Python process for current buffer and return it."
  (let* ((dedicated-proc-name (python-shell-get-process-name t))
         (dedicated-proc-buffer-name (format "*%s*" dedicated-proc-name))
         (global-proc-name  (python-shell-get-process-name nil))
         (global-proc-buffer-name (format "*%s*" global-proc-name))
         (dedicated-running (comint-check-proc dedicated-proc-buffer-name))
         (global-running (comint-check-proc global-proc-buffer-name))
         (current-prefix-arg 4))
    (when (and (not dedicated-running) (not global-running))
      (if (call-interactively 'run-python)
          (setq dedicated-running t)
        (setq global-running t)))
    ;; Always prefer dedicated
    (get-buffer-process (if dedicated-running
                            dedicated-proc-buffer-name
                          global-proc-buffer-name))))

(defun python-shell-send-string (string)
  "Send STRING to inferior Python process."
  (interactive "sPython command: ")
  (let ((process (python-shell-get-or-create-process)))
    (message (format "Sent: %s..." string))
    (comint-send-string process string)
    (when (or (not (string-match "\n$" string))
              (string-match "\n[ \t].*\n?$" string))
      (comint-send-string process "\n"))))

(defun python-shell-send-region (start end)
  "Send the region delimited by START and END to inferior Python process."
  (interactive "r")
  (let* ((contents (buffer-substring start end))
         (current-file (buffer-file-name))
         (process (python-shell-get-or-create-process))
         (temp-file (make-temp-file "py")))
    (with-temp-file temp-file
      (insert contents)
      (delete-trailing-whitespace)
      (goto-char (point-min))
      (message (format "Sent: %s..."
                       (buffer-substring (point-min)
                                         (line-end-position)))))
    (with-current-buffer (process-buffer process)
      (setq inferior-python-mode-current-file current-file)
      (setq inferior-python-mode-current-temp-file temp-file))
    (python-shell-send-file temp-file process)))

(defun python-shell-send-buffer ()
  "Send the entire buffer to inferior Python process."
  (interactive)
  (save-restriction
    (widen)
    (python-shell-send-region (point-min) (point-max))))

(defun python-shell-send-defun (arg)
  "Send the (inner|outer)most def or class to inferior Python process.
When argument ARG is non-nil sends the innermost defun."
  (interactive "P")
  (save-excursion
    (python-shell-send-region (progn
                            (or (if arg
                                    (python-beginning-of-innermost-defun)
                                  (python-beginning-of-defun-function))
                                (progn (beginning-of-line) (point-marker))))
                          (progn
                            (or (python-end-of-defun-function)
                                (progn (end-of-line) (point-marker)))))))

(defun python-shell-send-file (file-name &optional process)
  "Send FILE-NAME to inferior Python process."
  (interactive "fFile to send: ")
  (let ((process (or process (python-shell-get-or-create-process))))
    (accept-process-output process)
    (with-current-buffer (process-buffer process)
      (delete-region (save-excursion
                       (move-to-column 0)
                       (point-marker))
                     (line-end-position)))
    (comint-send-string
     process
     (format "execfile('%s')\n" (expand-file-name file-name)))))

(defun python-shell-switch-to-shell ()
  "Switch to inferior Python process buffer."
  (interactive)
  (pop-to-buffer (process-buffer (python-shell-get-or-create-process)) t))


;;; Shell completion

(defvar python-shell-completion-setup-code
  "try:
    import readline
except ImportError:
    def __COMPLETER_all_completions(text): []
else:
    import rlcompleter
    readline.set_completer(rlcompleter.Completer().complete)
    def __COMPLETER_all_completions(text):
        import sys
        completions = []
        try:
            i = 0
            while True:
                res = readline.get_completer()(text, i)
                if not res: break
                i += 1
                completions.append(res)
        except NameError:
            pass
        return completions"
  "Code used to setup completion in inferior Python processes.")

(defvar python-shell-completion-strings-code
  "';'.join(__COMPLETER_all_completions('''%s'''))\n"
  "Python code used to get a string of completions separated by semicolons.")

(defun python-shell-completion-setup ()
  "Send `python-shell-completion-setup-code' to inferior Python process.
Also binds <tab> to `python-shell-complete-or-indent' in the
`inferior-python-mode-map' and adds
`python-shell-completion-complete-at-point' to the
`comint-dynamic-complete-functions' list.
It is specially designed to be added to the
`inferior-python-mode-hook'."
  (when python-shell-completion-setup-code
    (let ((temp-file (make-temp-file "py"))
          (process (get-buffer-process (current-buffer))))
      (with-temp-file temp-file
        (insert python-shell-completion-setup-code)
        (delete-trailing-whitespace)
        (goto-char (point-min)))
      (python-shell-send-file temp-file process)
      (message (format "Completion setup code sent.")))
    (add-to-list (make-local-variable
                  'comint-dynamic-complete-functions)
                 'python-shell-completion-complete-at-point)
    (define-key inferior-python-mode-map (kbd "<tab>")
      'python-shell-completion-complete-or-indent)))

(defun python-shell-completion-complete-at-point ()
  "Perform completion at point in inferior Python process."
  (interactive)
  (when (and comint-last-prompt-overlay
             (> (point-marker) (overlay-end comint-last-prompt-overlay)))
    (let* ((process (get-buffer-process (current-buffer)))
           (input (comint-word (current-word)))
           (completions (when input
                          (delete-region (point-marker)
                                         (progn
                                           (forward-char (- (length input)))
                                           (point-marker)))
                          (process-send-string
                           process
                           (format
                            python-shell-completion-strings-code input))
                          (accept-process-output process)
                          (save-excursion
                            (re-search-backward comint-prompt-regexp
                                                comint-last-input-end t)
                            (split-string
                             (buffer-substring-no-properties
                              (point-marker) comint-last-input-end)
                             ";\\|\"\\|'\\|(" t))))
           (completion (when completions (try-completion input completions))))
      (when completions
        (save-excursion
          (forward-line -1)
          (kill-line 1)))
      (cond ((eq completion t)
             (when input (insert input)))
            ((null completion)
             (when input (insert input))
             (message "Can't find completion for \"%s\"" input)
             (ding))
            ((not (string= input completion))
             (insert completion))
            (t
             (message "Making completion list...")
             (when input (insert input))
             (with-output-to-temp-buffer "*Python Completions*"
               (display-completion-list
                (all-completions input completions))))))))

(defun python-shell-completion-complete-or-indent ()
  "Complete or indent depending on the context.
If content before pointer is all whitespace indent.  If not try to
complete."
  (interactive)
  (if (string-match "^[[:space:]]*$"
                    (buffer-substring (comint-line-beginning-position)
                                      (point-marker)))
      (indent-for-tab-command)
    (comint-dynamic-complete)))

(add-hook 'inferior-python-mode-hook
          #'python-shell-completion-setup)


;;; PDB Track integration

(defvar python-pdbtrack-stacktrace-info-regexp
  "> %s(\\([0-9]+\\))\\([?a-zA-Z0-9_<>]+\\)()"
  "Regexp matching stacktrace information.
It is used to extract the current line and module beign
inspected.
The regexp should not start with a caret (^) and can contain a
string placeholder (\%s) which is replaced with the filename
beign inspected (so other files in the debugging process are not
opened)")

(defvar python-pdbtrack-tracking-buffers '()
  "Alist containing elements of form (#<buffer> . #<buffer>).
The car of each element of the alist is the tracking buffer and
the cdr is the tracked buffer.")

(defun python-pdbtrack-get-or-add-tracking-buffers ()
  "Get/Add a tracked buffer for the current buffer.
Internally it uses the `python-pdbtrack-tracking-buffers' alist.
Returns a cons with the form:
 * (#<tracking buffer> . #< tracked buffer>)."
  (or
   (assq (current-buffer) python-pdbtrack-tracking-buffers)
   (let* ((file (with-current-buffer (current-buffer)
                  (or inferior-python-mode-current-file
                      inferior-python-mode-current-temp-file)))
          (tracking-buffers
           `(,(current-buffer) .
             ,(or (get-file-buffer file)
                  (find-file-noselect file)))))
     (set-buffer (cdr tracking-buffers))
     (python-mode)
     (set-buffer (car tracking-buffers))
     (setq python-pdbtrack-tracking-buffers
           (cons tracking-buffers python-pdbtrack-tracking-buffers))
     tracking-buffers)))

(defun python-pdbtrack-comint-output-filter-function (output)
  "Move overlay arrow to current pdb line in tracked buffer.
Argument OUTPUT is a string with the output from the comint process."
  (when (not (string= output ""))
    (let ((full-output (ansi-color-filter-apply
                        (buffer-substring comint-last-input-end
                                          (point-max)))))
      (if (string-match python-shell-prompt-pdb-regexp full-output)
          (let* ((tracking-buffers (python-pdbtrack-get-or-add-tracking-buffers))
                 (line-num
                  (save-excursion
                    (string-match
                     (format python-pdbtrack-stacktrace-info-regexp
                             (regexp-quote
                              inferior-python-mode-current-temp-file))
                     full-output)
                    (string-to-number (or (match-string-no-properties 1 full-output) ""))))
                 (tracked-buffer-window (get-buffer-window (cdr tracking-buffers)))
                 (tracked-buffer-line-pos))
            (when line-num
              (with-current-buffer (cdr tracking-buffers)
                (set (make-local-variable 'overlay-arrow-string) "=>")
                (set (make-local-variable 'overlay-arrow-position) (make-marker))
                (setq tracked-buffer-line-pos (progn
                                                (goto-char (point-min))
                                                (forward-line (1- line-num))
                                                (point-marker)))
                (when tracked-buffer-window
                  (set-window-point tracked-buffer-window tracked-buffer-line-pos))
                (set-marker overlay-arrow-position tracked-buffer-line-pos)))
            (pop-to-buffer (cdr tracking-buffers))
            (switch-to-buffer-other-window (car tracking-buffers)))
        (let ((tracking-buffers (assq (current-buffer)
                                      python-pdbtrack-tracking-buffers)))
          (when tracking-buffers
            (if inferior-python-mode-current-file
                (with-current-buffer (cdr tracking-buffers)
                  (set-marker overlay-arrow-position nil))
              (kill-buffer (cdr tracking-buffers)))
            (setq python-pdbtrack-tracking-buffers
                  (assq-delete-all (current-buffer)
                                   python-pdbtrack-tracking-buffers)))))))
  output)


;;; Symbol completion

(defun python-completion-complete-at-point ()
  "Complete current symbol at point.
For this to work the best as possible you should call
`python-shell-send-buffer' from time to time so context in
inferior python process is updated properly."
  (interactive)
  (let ((process (python-shell-get-process)))
    (if (not process)
        (error "Completion needs an inferior Python process running.")
      (let* ((input (when (comint-word (current-word))
                      (with-syntax-table python-dotty-syntax-table
                        (buffer-substring (point-marker)
                                          (save-excursion
                                            (forward-word -1)
                                            (point-marker))))))
             (completions (when input
                            (delete-region (point-marker)
                                           (progn
                                             (forward-char (- (length input)))
                                             (point-marker)))
                            (process-send-string
                             process
                             (format
                              python-shell-completion-strings-code input))
                            (accept-process-output process)
                            (with-current-buffer (process-buffer process)
                              (save-excursion
                                (re-search-backward comint-prompt-regexp
                                                    comint-last-input-end t)
                                (split-string
                                 (buffer-substring-no-properties
                                  (point-marker) comint-last-input-end)
                                 ";\\|\"\\|'\\|(" t)))))
             (completion (when completions
                           (try-completion input completions))))
        (with-current-buffer (process-buffer process)
          (save-excursion
            (forward-line -1)
            (kill-line 1)))
        (when completions
          (cond ((eq completion t)
                 (insert input))
                ((null completion)
                 (insert input)
                 (message "Can't find completion for \"%s\"" input)
                 (ding))
                ((not (string= input completion))
                 (insert completion))
                (t
                 (message "Making completion list...")
                 (insert input)
                 (with-output-to-temp-buffer "*Python Completions*"
                   (display-completion-list
                    (all-completions input completions))))))))))

(add-to-list 'debug-ignored-errors "^Completion needs an inferior Python process running.")


;;; Fill paragraph

(defun python-fill-paragraph-function (&optional justify)
  "`fill-paragraph-function' handling multi-line strings and possibly comments.
If any of the current line is in or at the end of a multi-line string,
fill the string or the paragraph of it that point is in, preserving
the string's indentation."
  (interactive "P")
  (save-excursion
    (back-to-indentation)
    (cond
     ;; Comments
     ((fill-comment-paragraph justify))
     ;; Docstrings
     ((save-excursion (skip-chars-forward "\"'uUrR")
                      (nth 3 (syntax-ppss)))
      (let ((marker (point-marker))
            (string-start-marker
             (progn
               (skip-chars-forward "\"'uUrR")
               (goto-char (nth 8 (syntax-ppss)))
               (skip-chars-forward "\"'uUrR")
               (point-marker)))
            (reg-start (line-beginning-position))
            (string-end-marker
             (progn
               (while (nth 3 (syntax-ppss)) (goto-char (1+ (point-marker))))
               (skip-chars-backward "\"'")
               (point-marker)))
            (reg-end (line-end-position))
            (fill-paragraph-function))
        (save-restriction
          (narrow-to-region reg-start reg-end)
          (save-excursion
            (goto-char string-start-marker)
            (delete-region (point-marker) (progn
                                            (skip-syntax-forward "> ")
                                            (point-marker)))
            (goto-char string-end-marker)
            (delete-region (point-marker) (progn
                                            (skip-syntax-backward "> ")
                                            (point-marker)))
            (save-excursion
              (goto-char marker)
              (fill-paragraph justify))
            ;; If there is a newline in the docstring lets put triple
            ;; quote in it's own line to follow pep 8
            (when (save-excursion
                    (re-search-backward "\n" string-start-marker t))
              (newline)
              (newline-and-indent))
            (fill-paragraph justify)))) t)
     ;; Decorators
     ((equal (char-after (save-excursion
                           (back-to-indentation)
                           (point-marker))) ?@) t)
     ;; Parens
     ((or (> (nth 0 (syntax-ppss)) 0)
          (looking-at (python-rx open-paren))
          (save-excursion
            (skip-syntax-forward "^(" (line-end-position))
            (looking-at (python-rx open-paren))))
      (save-restriction
        (narrow-to-region (progn
                            (while (> (nth 0 (syntax-ppss)) 0)
                              (goto-char (1- (point-marker))))
                            (point-marker)
                            (line-beginning-position))
                          (progn
                            (when (not (> (nth 0 (syntax-ppss)) 0))
                              (end-of-line)
                              (when (not (> (nth 0 (syntax-ppss)) 0))
                                (skip-syntax-backward "^)")))
                            (while (> (nth 0 (syntax-ppss)) 0)
                              (goto-char (1+ (point-marker))))
                            (point-marker)))
        (let ((paragraph-start "\f\\|[ \t]*$")
              (paragraph-separate ",")
              (fill-paragraph-function))
          (goto-char (point-min))
          (fill-paragraph justify))
        (while (not (eobp))
          (forward-line 1)
          (python-indent-line)
          (goto-char (line-end-position)))) t)
     (t t))))


;;; Eldoc

(defvar python-eldoc-setup-code
  "def __PYDOC_get_help(obj):
    try:
        import pydoc
        obj = eval(obj, globals())
        return pydoc.getdoc(obj)
    except:
        return ''"
  "Python code to setup documentation retrieval.")

(defvar python-eldoc-string-code
  "print __PYDOC_get_help('''%s''')\n"
  "Python code used to get a string with the documentation of an object.")

(defun python-eldoc-setup ()
  "Send `python-eldoc-setup-code' to inferior Python process.
It is specially designed to be added to the
`inferior-python-mode-hook'."
  (when python-eldoc-setup-code
    (let ((temp-file (make-temp-file "py")))
      (with-temp-file temp-file
        (insert python-eldoc-setup-code)
        (delete-trailing-whitespace)
        (goto-char (point-min)))
      (python-shell-send-file temp-file (get-buffer-process (current-buffer)))
      (message (format "Completion setup code sent.")))))

(defun python-eldoc-function ()
  "`eldoc-documentation-function' for Python.
For this to work the best as possible you should call
`python-shell-send-buffer' from time to time so context in
inferior python process is updated properly."
  (interactive)
  (let ((process (python-shell-get-process)))
    (if (not process)
        "Eldoc needs an inferior Python process running."
      (let* ((current-defun (python-info-current-defun))
             (input (with-syntax-table python-dotty-syntax-table
                      (if (not current-defun)
                          (current-word)
                        (concat current-defun "." (current-word)))))
             (ppss (syntax-ppss))
             (help (when (and input
                              (not (string= input (concat current-defun ".")))
                              (eq nil (nth 3 ppss))
                              (eq nil (nth 4 ppss)))
                     (when (string-match (concat
                                          (regexp-quote (concat current-defun "."))
                                          "self\\.") input)
                       (with-temp-buffer
                         (insert input)
                         (goto-char (point-min))
                         (forward-word)
                         (forward-char)
                         (delete-region (point-marker) (search-forward "self."))
                         (setq input (buffer-substring (point-min) (point-max)))))
                     (process-send-string
                      process (format python-eldoc-string-code input))
                     (accept-process-output process)
                     (with-current-buffer (process-buffer process)
                       (when comint-last-prompt-overlay
                         (save-excursion
                           (goto-char comint-last-input-end)
                           (re-search-forward comint-prompt-regexp
                                              (line-end-position) t)
                           (buffer-substring-no-properties
                            (point-marker)
                            (overlay-start comint-last-prompt-overlay))))))))
        (with-current-buffer (process-buffer process)
          (when comint-last-prompt-overlay
            (delete-region comint-last-input-end
                           (overlay-start comint-last-prompt-overlay))))
        (when (and help
                   (not (string= help "\n")))
          help)))))

(add-hook 'inferior-python-mode-hook
          #'python-eldoc-setup)


;;; Misc helpers

(defun python-info-current-defun ()
  "Return name of surrounding function with Python compatible dotty syntax.
This function is compatible to be used as
`add-log-current-defun-function' since it returns nil if point is
not inside a defun."
  (let ((names '()))
    (save-restriction
      (widen)
      (save-excursion
        (beginning-of-line)
        (when (not (>= (current-indentation) python-indent-offset))
          (while (and (not (eobp)) (forward-comment 1))))
        (while (and (not (equal 0 (current-indentation)))
                         (python-beginning-of-innermost-defun))
          (back-to-indentation)
          (looking-at "\\(?:def\\|class\\) +\\([^(]+\\)[^:]+:\\s-*\n")
          (setq names (cons (match-string-no-properties 1) names)))))
    (when names
      (mapconcat (lambda (string) string) names "."))))

(defun python-info-closing-block ()
  "Return the point of the block that the current line closes."
  (let ((closing-word (save-excursion
                        (back-to-indentation)
                        (current-word)))
        (indentation (current-indentation)))
    (when (member closing-word python-indent-dedenters)
      (save-excursion
        (forward-line -1)
        (while (and (> (current-indentation) indentation)
                    (not (bobp))
                    (not (back-to-indentation))
                    (forward-line -1)))
        (back-to-indentation)
        (cond
         ((not (equal indentation (current-indentation))) nil)
         ((string= closing-word "elif")
          (when (member (current-word) '("if" "elif"))
            (point-marker)))
         ((string= closing-word "else")
          (when (member (current-word) '("if" "elif" "except" "for" "while"))
            (point-marker)))
         ((string= closing-word "except")
          (when (member (current-word) '("try"))
            (point-marker)))
         ((string= closing-word "finally")
          (when (member (current-word) '("except" "else"))
            (point-marker))))))))

(defun python-info-line-ends-backslash-p ()
    "Return non-nil if current line ends with backslash."
    (string=  (or (ignore-errors
                      (buffer-substring
                       (line-end-position)
                       (- (line-end-position) 1))) "") "\\"))

(defun python-info-continuation-line-p ()
  "Return non-nil if current line is continuation of another."
  (or (python-info-line-ends-backslash-p)
      (string-match ",[[:space:]]*$" (buffer-substring
                                      (line-beginning-position)
                                      (line-end-position)))
      (save-excursion
        (let ((innermost-paren (progn
                                 (goto-char (line-end-position))
                                 (nth 1 (syntax-ppss)))))
          (when (and innermost-paren
                     (and (<= (line-beginning-position) innermost-paren)
                          (>= (line-end-position) innermost-paren)))
            (goto-char innermost-paren)
            (looking-at (python-rx open-paren (* space) line-end)))))
      (save-excursion
        (back-to-indentation)
        (nth 1 (syntax-ppss)))))

(defun python-info-block-continuation-line-p ()
  "Return non-nil if current line is a continuation of a block."
  (save-excursion
    (while (and (not (bobp))
                (python-info-continuation-line-p))
      (forward-line -1))
    (forward-line 1)
    (back-to-indentation)
    (when (looking-at (python-rx block-start))
      (point-marker))))

(defun python-info-assignment-continuation-line-p ()
  "Return non-nil if current line is a continuation of an assignment."
  (save-excursion
    (while (and (not (bobp))
                (python-info-continuation-line-p))
      (forward-line -1))
    (forward-line 1)
    (back-to-indentation)
    (when (and (not (looking-at (python-rx block-start)))
               (save-excursion
                 (and (re-search-forward (python-rx not-simple-operator
                                                    assignment-operator
                                                    not-simple-operator)
                                         (line-end-position) t)
                      (not (syntax-ppss-context (syntax-ppss))))))
      (point-marker))))


;;;###autoload
(define-derived-mode python-mode fundamental-mode "Python"
  "A major mode for editing Python files."
  (set (make-local-variable 'tab-width) 8)
  (set (make-local-variable 'indent-tabs-mode) nil)

  (set (make-local-variable 'comment-start) "# ")
  (set (make-local-variable 'comment-start-skip) "#+\\s-*")

  (set (make-local-variable 'parse-sexp-lookup-properties) t)
  (set (make-local-variable 'parse-sexp-ignore-comments) t)

  (set (make-local-variable 'font-lock-defaults)
       '(python-font-lock-keywords
         nil nil nil nil
         (font-lock-syntactic-keywords . python-font-lock-syntactic-keywords)))

  (set (make-local-variable 'indent-line-function) #'python-indent-line-function)
  (set (make-local-variable 'indent-region-function) #'python-indent-region)

  (set (make-local-variable 'paragraph-start) "\\s-*$")
  (set (make-local-variable 'fill-paragraph-function) 'python-fill-paragraph-function)

  (set (make-local-variable 'beginning-of-defun-function)
       #'python-beginning-of-defun-function)
  (set (make-local-variable 'end-of-defun-function)
       #'python-end-of-defun-function)

  (add-hook 'completion-at-point-functions
            'python-completion-complete-at-point nil 'local)

  (set (make-local-variable 'add-log-current-defun-function)
       #'python-info-current-defun)

  (set (make-local-variable 'eldoc-documentation-function)
       #'python-eldoc-function)

  (add-to-list 'hs-special-modes-alist
	       `(python-mode "^\\s-*\\(?:def\\|class\\)\\>" nil "#"
                             ,(lambda (arg)
                                (python-end-of-defun-function)) nil))

  (set (make-local-variable 'outline-regexp)
       (python-rx (* space) block-start))
  (set (make-local-variable 'outline-heading-end-regexp) ":\\s-*\n")
  (set (make-local-variable 'outline-level)
       #'(lambda ()
           "`outline-level' function for Python mode."
           (1+ (/ (current-indentation) python-indent-offset))))

  (when python-indent-guess-indent-offset
    (python-indent-guess-indent-offset)))


(provide 'python)
;;; python.el ends here
