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

(defvar gascity-lint--main-file
  (let ((dir (locate-dominating-file (or (car gascity-lint--files) ".")
                                     "gascity.el")))
    (when dir (expand-file-name "gascity.el" dir)))
  "The package's main file, `gascity.el', or nil when it cannot be found.

package-lint checks every linted file against the package headers of
`package-lint-main-file' (name prefix, `Package-Requires', ...).  Without
it each file is treated as its own package -- every `gascity-*' definition
would be reported as wrong-prefixed and every runtime dependency as
uninstallable -- so it must name `gascity.el', exactly as Eldev's
`eldev-project-main-file' did.")

(when (null gascity-lint--files)
  (error "lint.el: no files given"))

;; checkdoc signals on the first finding, so a failure exits non-zero before
;; package-lint runs.
(dolist (file gascity-lint--files)
  (with-current-buffer (find-file-noselect file)
    (checkdoc-batch)))

;; package-lint's batch entry point takes NO arguments: it reads the files
;; still on `command-line-args-left' (which are exactly the files passed
;; after `-l scripts/lint.el'), so it lints the same set checkdoc just
;; walked.  Passing the file list as arguments raises
;; `wrong-number-of-arguments' and aborts the lint run the moment
;; package-lint is installed (i.e. in CI), so keep the call argument-free.
(if (require 'package-lint nil t)
    (progn
      (setq package-lint-main-file gascity-lint--main-file)
      (package-lint-batch-and-exit))
  (message "lint: package-lint is not installed; skipping package metadata checks (CI installs it)"))

;;; lint.el ends here
