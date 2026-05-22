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

(provide 'gascity-error)
;;; gascity-error.el ends here
