;; copyright 2003 stefan kersten <steve@k-hornz.de>
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
;; USA

(defun sclang-regexp-group (regexp)
  (concat "\\(" regexp "\\)"))

(defun sclang-regexp-concat (&rest regexps)
  (mapconcat 'sclang-regexp-group regexps "\\|"))

(defconst sclang-symbol-regexp "\\(\\sw\\|\\s_\\)*")
(defconst sclang-identifier-regexp (concat "[a-z]" sclang-symbol-regexp))

(defconst sclang-method-name-special-chars "-!%&*+/<=>?@|")

(defconst sclang-method-name-plain-regexp (concat sclang-identifier-regexp "_?"))

(defconst sclang-method-name-special-regexp (concat
					     "[" (regexp-quote sclang-method-name-special-chars) "]+"
					     ))

(defconst sclang-method-name-regexp (sclang-regexp-concat
				     sclang-method-name-special-regexp
				     sclang-method-name-plain-regexp
				     ))

(defconst sclang-class-name-regexp "\\(Meta_\\)?[A-Z]\\(\\sw\\|\\s_\\)*")

(defconst sclang-symbol-name-regexp (sclang-regexp-concat
				     sclang-method-name-regexp
				     sclang-class-name-regexp
				     ))

(defconst sclang-class-definition-regexp (concat
					  "^\\s *"
					  (sclang-regexp-group sclang-class-name-regexp)
					  "\\(\\s *:\\s *"
					  (sclang-regexp-group sclang-class-name-regexp)
					  "\\)?\\s *{"))

(defconst sclang-method-definition-regexp (concat
					   "^\\s *\\*?"
					   (sclang-regexp-group sclang-method-name-regexp)
					   "\\s *{"))

(defconst sclang-beginning-of-defun-regexp (concat
					    "^"
					    (sclang-regexp-group
					     (sclang-regexp-concat
					      "\\s("
					      sclang-class-definition-regexp
;; 					      sclang-method-definition-regexp
					      ))))

(defvar sclang-symbol-table nil
  "Obarray of all defined symbols.")

(defvar sclang-symbol-history nil)

;; =====================================================================
;; regexp building
;; =====================================================================

;; (defun sclang-make-class-definition-regexp (name)
;;   (concat
;;    "\\(" (regexp-quote name) "\\)"
;;    "\\(\\s *:\\s *\\(" sclang-class-name-regexp "\\)\\)?"
;;    "\\s *{"))

;; (defun sclang-make-method-definition-regexp (name)
;;   (concat "\\(" (regexp-quote name) "\\)\\s *{"))

;; =====================================================================
;; string matching
;; =====================================================================

(defun sclang-string-match (regexp string)
  (let ((case-fold-search nil))
    (string-match regexp string)))

(defun sclang-symbol-match (symbol-regexp string)
  (sclang-string-match (concat "^" symbol-regexp "$") string))

;; =====================================================================
;; symbol name predicates
;; =====================================================================

(defun sclang-class-name-p (string)
  (sclang-symbol-match sclang-class-name-regexp string))

(defun sclang-meta-class-name-p (string)
  (and (sclang-class-name-p string)
       (match-string 1 string)))

(defun sclang-method-name-p (string)
  (sclang-symbol-match sclang-method-name-regexp string))

(defun sclang-symbol-name-p (string)
  (sclang-symbol-match sclang-symbol-name-regexp string))

(defun sclang-method-name-setter-p (method-name)
  (string-match "_$" method-name))

(defun sclang-method-name-getter-p (method-name)
  (not (sclang-method-name-setter-p method-name)))

;; =====================================================================
;; symbol name manipulation
;; =====================================================================

(defun sclang-method-name-setter (method-name)
  (if (sclang-method-name-setter-p method-name)
      method-name
    (concat method-name "_")))

(defun sclang-method-name-getter (method-name)
  (if (sclang-method-name-setter-p method-name)
      (substring method-name 0 (1- (length method-name)))
    method-name))

;; =====================================================================
;; symbol table access
;; =====================================================================

(sclang-set-command-handler
 'symbolTable
 (lambda (data)
   (setq sclang-symbol-table (sort data 'string<))
   (sclang-update-font-lock)))

(add-hook 'sclang-library-startup-hook
	  (lambda () (sclang-perform-command 'symbolTable)))

(defun sclang-make-symbol-completion-table ()
  (mapcar (lambda (s) (cons s nil)) sclang-symbol-table))

(defun sclang-make-symbol-completion-predicate (predicate)
  (and predicate
       (lambda (assoc) (funcall predicate (car assoc)))))

(defun sclang-get-symbol (string)
  (car (member string sclang-symbol-table)))

(defun sclang-read-symbol (prompt &optional default predicate require-match inherit-input-method)
  (let ((symbol (sclang-get-symbol default)))
    (completing-read (sclang-make-prompt-string prompt symbol)
		     (sclang-make-symbol-completion-table)
		     (sclang-make-symbol-completion-predicate predicate)
		     require-match nil
		     'sclang-symbol-history symbol
		     inherit-input-method)))

;; =====================================================================
;; buffer movement
;; =====================================================================

(defun sclang-point-in-comment-p ()
  "Return non-nil if point is inside a comment.

Use font-lock information is font-lock-mode is enabled."
  (if font-lock-mode
      ;; use available information in font-lock-mode
      (eq (get-text-property (point) 'face) 'font-lock-comment-face)
    ;; else parse from the beginning
    (not (null (nth 4 (parse-partial-sexp (point-min) (point)))))))

(defun sclang-beginning-of-defun (&optional arg)
  (interactive "p")
  (let ((case-fold-search nil)
	(arg (or arg (prefix-numeric-value current-prefix-arg)))
	(orig (point))
	(success t))
    (while (and success (> arg 0))
      (if (setq success (re-search-backward sclang-beginning-of-defun-regexp
					    nil 'move))
	  (unless (sclang-point-in-comment-p)
	    (goto-char (match-beginning 0))
	    (setq arg (1- arg)))))
    (while (and success (< arg 0))
      (if (setq success (re-search-forward sclang-beginning-of-defun-regexp nil t))
	  (unless (sclang-point-in-comment-p)
	    (goto-char (match-end 0))
	    (setq arg (1+ arg)))))
    (when success
	(beginning-of-line) t)))

(defun sclang-point-in-defun-p ()
  "Return non-nil if point is inside a defun.
Return value is nil or (values beg end) of defun."
  (save-excursion
    (let ((orig (point))
	  beg end)
      (and (sclang-beginning-of-defun 1)
	   (setq beg (point))
	   (condition-case nil (forward-list 1) (error nil))
	   (setq end (point))
	   (> (point) orig)
	   (values beg end)))))

(defun sclang-end-of-defun (&optional arg)
  (interactive "p")
  (let ((case-fold-search nil)
	(arg (or arg (prefix-numeric-value current-prefix-arg)))
	(success t)
	n cur)
    (while (and success (> arg 0))
      (setq n (if (sclang-point-in-defun-p) 1 -1))
      (setq cur (point))
      (if (and (sclang-beginning-of-defun n)
	       (condition-case nil (forward-list 1) (error nil)))
	  (progn
	    (setq arg (1- arg)))
	(goto-char cur)
	(setq success nil)))
    (while (and success (< arg 0))
      (setq n (if (sclang-point-in-defun-p) 2 1))
      (setq cur (point))
      (if (and (sclang-beginning-of-defun n)
	       (condition-case nil (forward-list 1) (error nil)))
	  (progn
	    (backward-char 1)
	    (setq arg (1+ arg)))
	(goto-char cur)
	(setq success nil)))
    (when success
      (forward-line 1) t)))

;; =====================================================================
;; buffer object access
;; =====================================================================

(defun sclang-symbol-at-point ()
  "Answer the symbol at point, or nil if not a valid symbol."
  (save-excursion
    (with-syntax-table sclang-mode-syntax-table
      (let (beg end)
	(cond ((looking-at sclang-method-name-special-regexp)
	       (skip-chars-backward sclang-method-name-special-chars)
	       (setq beg (point))
	       (skip-chars-forward sclang-method-name-special-chars)
	       (setq end (point)))
	      (t
	       (skip-syntax-backward "w_")
	       (setq beg (point))
	       (skip-syntax-forward "w_")
	       (setq end (point))))
	(goto-char beg)
	(if (looking-at sclang-method-name-regexp)
	    (buffer-substring-no-properties beg end))))))

(defun sclang-line-at-point ()
  (let (beg end)
    (save-excursion
      (beginning-of-line)
      (setq beg (point))
      (end-of-line)
      (setq end (point)))
    (unless (eq beg end)
      (buffer-substring-no-properties beg end))))

(defun sclang-defun-at-point ()
  (save-excursion
    (with-syntax-table sclang-mode-syntax-table
      (multiple-value-bind
	  (beg end) (sclang-point-in-defun-p)
	(and beg end (buffer-substring-no-properties beg end))))))

;; =====================================================================
;; symbol completion
;; =====================================================================

(defun sclang-complete-symbol (&optional predicate)
  "Perform completion on symbol preceding point.
Compare that symbol against the known symbols.

When called from a program, optional arg PREDICATE is a predicate
determining which symbols are considered.
If PREDICATE is nil, the context determines which symbols are
considered.  If the symbol starts with an upper case letter,
class name completion is performed, otherwise only selector names
are considered."
  (interactive)
  (let* ((buffer (current-buffer))
	 (end (point))
	 (beg (save-excursion
		(backward-sexp 1)
		(skip-syntax-forward "'")
		(point)))
	 (pattern (buffer-substring-no-properties beg end))
	 (case-fold-search nil)
	 (table (sclang-make-symbol-completion-table))
	 (predicate (or predicate
			(if (sclang-class-name-p pattern)
			    'sclang-class-name-p
			  'sclang-method-name-p)))
	 (completion (try-completion pattern table (lambda (assoc) (funcall predicate (car assoc))))))
    (cond ((eq completion t))
	  ((null completion)
	   (message "Can't find completion for '%s'" pattern)
	   (ding))
	  ((not (string= pattern completion))
	   (delete-region beg end)
	   (insert completion))
	  (t
	   (message "Making completion list...")
	   (let* ((list (all-completions pattern table (lambda (assoc) (funcall predicate (car assoc)))))
		  (win (selected-window))
		  (buffer-name "*Completions*")
		  (same-window-buffer-names (list buffer-name)))
	     (setq list (sort list 'string<))
	     (with-sclang-browser
	      buffer-name
	      (add-hook 'sclang-browser-show-hook (lambda () (sclang-browser-next-link)))
	      (setq sclang-browser-link-function
		    (lambda (arg)
		      (sclang-browser-quit)
		      (with-current-buffer (car arg)
			(delete-region (car (cdr arg)) (point))
			(insert (cdr (cdr arg))))))
	      ;; (setq view-exit-action 'kill-buffer)
	      (insert (format "Completions for '%s':\n\n" pattern))
	      (dolist (x list)
		(insert (sclang-browser-make-link x (cons buffer (cons beg x))))
		(insert " \n"))
	      ))
	   (message "Making completion list...%s" "done")))))

;; =====================================================================
;; browsing definitions
;; =====================================================================

(defcustom sclang-symbol-definition-marker-ring-length 32
  "*Length of marker ring `sclang-symbol-definition-marker-ring'."
  :group 'sclang-interface
  :version "21.3"
  :type 'integer)

(defvar sclang-symbol-definition-marker-ring
  (make-ring sclang-symbol-definition-marker-ring-length)
  "Ring of markers which are locations from which \\[sclang-find-symbol-definitions] was invoked.")

(add-hook 'sclang-library-startup-hook
	  (lambda ()
	    (setq sclang-symbol-definition-marker-ring
		  (make-ring sclang-symbol-definition-marker-ring-length))))

(sclang-set-command-handler
 'classDefinitions
 (lambda (assoc)
   (let ((name (car assoc))
	 (data (cdr assoc)))
     (if data
	 (sclang-browse-definitions
	  name data
	  "*Definitions*" (format "Definitions of '%s'\n" name))
       (message "No definitions of '%s'" name)))))

(sclang-set-command-handler
 'methodDefinitions
 (lambda (assoc)
   (let ((name (car assoc))
	 (data (cdr assoc)))
     (if data
	 (sclang-browse-definitions
	  name data
	  "*Definitions*" (format "Definitions of '%s'\n" name))
       (message "No definitions of '%s'" name)))))

(sclang-set-command-handler
 'methodReferences
 (lambda (assoc)
   (let ((name (car assoc))
	 (data (cdr assoc)))
     (if data
	 (sclang-browse-definitions
	  name data
	  "*References*" (format "References to '%s'\n" name))
       (message "No references to '%s'" name)))))

(defun sclang-open-definition (file pos &optional search-func)
  (let ((buffer (find-file file)))
    (when (bufferp buffer)
      (with-current-buffer buffer
	(goto-char (or pos (point-min)))
	(when (functionp search-func)
	  (funcall search-func))))
	;;       (back-to-indentation)
	;;       ;; skip classvar, classmethod clutter
;; 	(and regexp (re-search-forward regexp nil t)
;; 	     (goto-char (match-beginning 0)))))
      buffer))

(defun sclang-pop-symbol-definition-mark ()
  (interactive)
  (let ((find-tag-marker-ring sclang-symbol-definition-marker-ring))
    (pop-tag-mark)))

(defun sclang-browse-definitions (name definitions buffer-name header &optional regexp)
  (if (cdr definitions)
      (let ((same-window-buffer-names (list buffer-name)))
	(with-sclang-browser
	 buffer-name
	 ;; (setq view-exit-action 'kill-buffer)
	 (setq sclang-browser-link-function
	       (lambda (data)
		 (sclang-browser-quit)
		 (apply 'sclang-open-definition data)))
	 (add-hook 'sclang-browser-show-hook (lambda () (sclang-browser-next-link)))
	 (insert header)
	 (insert "\n")
	 (let ((max-width 0)
	       format-string)
	   (dolist (def definitions)
	     (setq max-width (max (length (file-name-nondirectory (nth 1 def))) max-width)))
	   (setq format-string (format "%%-%ds  %%s" max-width))
	   (dolist (def definitions)
	     (let ((string (format format-string
				   (propertize (file-name-nondirectory (nth 1 def)) 'face 'bold)
				   (nth 0 def)))
		   (data (list (nth 1 def) (nth 2 def) regexp)))
	       (insert (sclang-browser-make-link string data))
	       (insert "\n"))))))
  ;; single definition: jump directly
  (let ((def (car definitions)))
    (sclang-open-definition (nth 1 def) (nth 2 def) regexp))))

(defun sclang-find-definitions (name)
  "Find all definitions of symbol NAME."
  (interactive
   (list
    (let ((name (sclang-symbol-at-point)))
      (if current-prefix-arg
	  (sclang-read-symbol "Find definitions of: " name nil t)
	(unless name (message "No symbol at point"))
	name))))
  (if (sclang-get-symbol name)
      (progn
	(ring-insert sclang-symbol-definition-marker-ring (point-marker))
	(if (sclang-class-name-p name)
	    (sclang-perform-command 'classDefinitions name)
	  (sclang-perform-command 'methodDefinitions name)))
    (message "'%s' is undefined" name)))

(defun sclang-find-references (name)
  "Find all references to symbol NAME."
  (interactive
   (list
    (let ((name (sclang-symbol-at-point)))
      (if current-prefix-arg
	  (sclang-read-symbol "Find references to: " name nil t)
	(unless name (message "No symbol at point"))
	name))))
  (if (sclang-get-symbol name)
      (progn
	(ring-insert sclang-symbol-definition-marker-ring (point-marker))
	(sclang-perform-command 'methodReferences name))
    (message "'%s' is undefined" name)))

(defun sclang-dump-interface (class)
  "Dump interface of class CLASS."
  (interactive
   (list
    (let ((class (sclang-symbol-at-point)))
      (if current-prefix-arg
	  (sclang-read-symbol "Dump interface of: " class 'sclang-class-name-p t)
	(unless name (message "No class at point"))
	name))))
  (and (sclang-get-symbol class)
       (sclang-class-name-p class)
       (sclang-send-string (format "%s.dumpFullInterface" class))))

;; =====================================================================
;; sc-code formatting
;; =====================================================================

(defun sclang-list-to-string (list)
  (unless (listp list) (setq list (list list)))
  (mapconcat 'sclang-object-to-string list ", "))

(defun sclang-object-to-string (obj)
  (cond ((null obj)
	 "nil")
	((eq t obj)
	 "true")
	((symbolp obj)
	 (format "'%s'" obj))
	((listp obj)
	 (format "[ %s ]" (sclang-list-to-string obj)))
	(t (format "%S" obj))))

(defun sclang-format (string &rest args)
  "format chars:
     %s - print string
     %o - print object
     %l - print list"
  (let ((case-fold-search nil)
	(i 0))
    (save-match-data
      (while (and (< i (length string))
		  (string-match "%[los%]" string i))
	(let* ((start (car (match-data)))
	       (format (aref string (1+ start)))
	       (arg (if args
			(pop args)
		      (error "Not enough arguments for format string")))
	       (repl (cond ((eq ?o format)
			    (sclang-object-to-string arg))
			   ((eq ?l format)
			    (sclang-list-to-string arg))
			   ((eq ?s format)
			    (format "%s" arg))
			   ((eq ?% format)
			    (push arg args)
			    "%"))))
	  (setq string (replace-match repl t t string))
	  (setq i (+ start (length repl)))))))
  string)

;; =====================================================================
;; module setup
;; =====================================================================

(provide 'sclang-language)

;; EOF