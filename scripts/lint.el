;;; lint.el --- Batch checkdoc + package-lint for gascity.el -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The `make lint' driver.  Runs checkdoc over every file named on the command
;; line, then delegates to package-lint when it is installed.  Any finding is
;; fatal (non-zero exit): this is the `eldev -p -dtT lint' bar preserved
;; without Eldev.  Lint is not part of `make check' because checkdoc's rules
;; differ across the supported Emacs versions (29.4/30.2 flag docstring verbs
;; that 31.1 accepts); CI installs package-lint and runs this on 31.1.

;;; Code:

(require 'checkdoc)

(defvar gascity-lint--files command-line-args-left
  "The Lisp files to lint, from the command line.")

(when (null gascity-lint--files)
  (error "lint.el: no files given"))

;; checkdoc signals on the first finding, so a failure exits non-zero before
;; package-lint runs.
(dolist (file gascity-lint--files)
  (with-current-buffer (find-file-noselect file)
    (checkdoc-batch)))

(if (require 'package-lint nil t)
    (apply #'package-lint-batch-and-exit gascity-lint--files)
  (message "lint: package-lint is not installed; skipping package metadata checks (CI installs it)"))

;;; lint.el ends here
