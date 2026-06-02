;;; gascity-error.el --- Error conditions for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Error conditions raised throughout gascity.el.
;;
;; Hierarchy:
;;
;;   error
;;     `- gascity-error                 base for all gascity errors
;;         |- gascity-command-error     a `gc' invocation failed
;;         |- gascity-json-parse-error  `gc' output was not valid JSON
;;         `- gascity-validation-error  a command failed local validation

;;; Code:

(require 'subr-x)

(define-error 'gascity-error
  "Gas City error"
  'error)

(define-error 'gascity-command-error
  "Gas City command execution error"
  'gascity-error)

(define-error 'gascity-json-parse-error
  "Gas City JSON parse error"
  'gascity-error)

(define-error 'gascity-validation-error
  "Gas City command validation error"
  'gascity-error)

(defun gascity-error-detail (err)
  "Return a one-line detail string from a `gascity-error' condition ERR.
For a `gascity-command-error' carrying a non-empty stderr, return that
stderr (trimmed); otherwise fall back to the condition's message.  Every
`gascity-error' is signalled as (SYMBOL MESSAGE . PLIST), so the message
is `cadr' and any attached plist (such as a command error's :stderr)
begins at `cddr'.  Callers use this to surface a clean echo-area line
instead of the raw condition-data plist that `error-message-string'
would render verbatim."
  (let ((stderr (plist-get (cddr err) :stderr)))
    (if (and (stringp stderr) (not (string-empty-p (string-trim stderr))))
        (string-trim stderr)
      (or (cadr err) "unknown error"))))

(provide 'gascity-error)
;;; gascity-error.el ends here
