;;; run-tests.el --- Load and run the gascity ERT suite -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The `make check' driver: loads every ERT test file under the directory
;; named by the GASCITY_TEST_DIR environment variable (set by Makefile.am)
;; and runs the whole suite once.  A test file whose feature is already
;; loaded is skipped, so a `require' between test files never redefines a
;; test.

;;; Code:

(require 'ert)

(defvar gascity-run-tests-directory (getenv "GASCITY_TEST_DIR")
  "Directory holding the ERT test files to load.")

(unless (and gascity-run-tests-directory
             (file-directory-p gascity-run-tests-directory))
  (error "GASCITY_TEST_DIR is unset or not a directory: %s"
         gascity-run-tests-directory))

(dolist (file (directory-files gascity-run-tests-directory t "\\.el\\'"))
  (let ((feature (intern (file-name-base file))))
    (unless (featurep feature)
      (load file nil t))))

(ert-run-tests-batch-and-exit)

;;; run-tests.el ends here
