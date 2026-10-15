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

(defun gascity-lint--register-local-package (name)
  "Register the local source checkout of package NAME with package.el.

NAME is a runtime dependency this project resolves from a source checkout
rather than a package archive: `beads' and the `vui' that checkout bundles.
package-lint decides installability from `package-alist', so without a
descriptor it would report the dependency as \"not installable\" even though
the build finds it on `EMACSLOADPATH'.  The descriptor is parsed from the
package's own main file, so its version tracks the checkout.

This mirrors Eldev's internal-pseudoarchive handling
\(`eldev--linter-package-present-archives') for `eldev -p -dtT lint'."
  (when-let* ((file (locate-library (symbol-name name)))
              (desc (with-current-buffer (find-file-noselect file)
                      (ignore-errors (package-buffer-info)))))
    (push desc (alist-get name package-alist nil nil #'eq))))

(defun gascity-lint--package-lint ()
  "Run package-lint over every file in `gascity-lint--files'.

This reproduces `package-lint-batch-and-exit' but controls the order around
`package-initialize': that function resets `package-alist', so the local
source-checkout dependencies must be registered *after* it, which is not
possible through the batch entry point.  Errors and warnings are fatal,
matching `package-lint-batch-fail-on-warnings'."
  (package-initialize)
  (setq package-lint-main-file gascity-lint--main-file)
  (dolist (name '(beads vui transient))
    (gascity-lint--register-local-package name))
  (let ((failed nil))
    (dolist (file gascity-lint--files)
      (with-temp-buffer
        (insert-file-contents file t)
        (emacs-lisp-mode)
        (pcase-dolist (`(,line ,col ,type ,message) (package-lint-buffer))
          (when (memq type '(error warning))
            (setq failed t))
          (message "%s:%d:%d: %s: %s" file line col type message))))
    (when failed
      (kill-emacs 1))))

(if (require 'package-lint nil t)
    (gascity-lint--package-lint)
  (message "lint: package-lint is not installed; skipping package metadata checks (CI installs it)"))

;;; lint.el ends here
