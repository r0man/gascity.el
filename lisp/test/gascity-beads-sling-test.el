;;; gascity-beads-sling-test.el --- Gas City registration on beads.el sling -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Tests for the downstream registration module
;; (`gascity-beads-sling'): load order, the idempotent registration of
;; beads.el's six sling seams, and the load-time inertness requirement
;; (no gc spawn or store read while registering).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(declare-function gascity-beads-sling-register "gascity-beads-sling" ())
(declare-function gascity-beads-sling-targets "gascity-beads-sling" ())
(declare-function gascity-beads-sling-validate "gascity-beads-sling" (context))
(declare-function gascity-beads-sling-actions "gascity-beads-sling" (context))
(declare-function gascity-beads-sling--menu-group "gascity-beads-sling" ())
(declare-function beads-sling-backend-get "beads-sling" (name))

(defvar gascity-beads-sling--registered)

(defun gascity-beads-sling-test--count (function functions)
  "Return how many times FUNCTION appears in FUNCTIONS."
  (seq-count (lambda (fn) (eq fn function)) functions))

(ert-deftest gascity-test-beads-sling-load-order ()
  "The entry point loads the registration module after the action layer."
  (should (featurep 'gascity-beads-sling))
  (should gascity-beads-sling--registered))

(ert-deftest gascity-test-beads-sling-register-idempotent ()
  "Registering twice leaves one backend, one menu group and one hook entry."
  (gascity-beads-sling-register)
  (gascity-beads-sling-register)
  (should (beads-sling-backend-get "gc"))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling--menu-group beads-menu-providers)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling-targets
                beads-sling-target-functions)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling-validate beads-sling-validators)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling-actions beads-action-providers)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling--after-action
                beads-after-action-functions))))

(ert-deftest gascity-test-beads-sling-no-spawn-at-load ()
  "Registration only touches the registration tables, never the gc boundary."
  (cl-letf (((symbol-function 'gascity-reader-read)
             (lambda (&rest _) (error "registration spawned a sync read")))
            ((symbol-function 'gascity-reader-read-async)
             (lambda (&rest _) (error "registration spawned an async read")))
            ((symbol-function 'gascity-reader-run-async)
             (lambda (&rest _) (error "registration spawned an action"))))
    (gascity-beads-sling-register)
    (should (beads-sling-backend-get "gc"))))
