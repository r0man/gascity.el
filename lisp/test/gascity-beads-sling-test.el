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

;;; Target provider and city resolution (plan §B2, REQ-002/REQ-007)

(defconst gascity-beads-sling-test--city "/tmp/beads-sling-city/"
  "The warm city of the provider tests.")

(defconst gascity-beads-sling-test--other-city "/tmp/beads-sling-other-city/"
  "A second known city, for the resolution-order test.")

(defconst gascity-beads-sling-test--rig "/tmp/beads-sling-rig/"
  "A rig repository outside every city tree (plan F4).")

(defconst gascity-beads-sling-test--agents
  '((agents . [((name . "dog-1") (qualified_name . "bd.dog-1")
                (scope . "city"))
               ((name . "implementation-worker")
                (qualified_name . "gascity.el/gc.implementation-worker")
                (scope . "rig"))]))
  "A `gc agent list' payload: one city-scoped and one rig-scoped agent.")

(defun gascity-beads-sling-test--rigs (city)
  "Return the memoized rig list for CITY, or nil for another city."
  (when (equal city gascity-beads-sling-test--city)
    (list (gascity-rig :name "gascity.el"
                       :prefix "gce"
                       :path (directory-file-name gascity-beads-sling-test--rig)))))

(ert-deftest gascity-test-beads-sling-provider-warm ()
  "A warm store yields one gc target per roster agent, from cache only."
  (let ((gascity-context-city gascity-beads-sling-test--city)
        (gascity-beads-sling--city nil)
        (reads nil)
        (peeks nil))
    (cl-letf (((symbol-function 'gascity-store-get)
               (lambda (args &optional dir)
                 (push (list args dir) reads)
                 (list :status 'ready
                       :data gascity-beads-sling-test--agents)))
              ((symbol-function 'gascity-store-peek)
               (lambda (&rest _) (push :peek peeks) nil))
              ((symbol-function 'gascity-reader-read)
               (lambda (&rest _) (error "Provider spawned a sync read")))
              ((symbol-function 'gascity-reader-read-async)
               (lambda (&rest _) (error "Provider spawned an async read")))
              ((symbol-function 'gascity-reader-run-async)
               (lambda (&rest _) (error "Provider ran an action")))
              ((symbol-function 'file-exists-p)
               (lambda (&rest _) (error "Provider probed the file system"))))
      (let* ((targets (gascity-beads-sling-targets))
             (city-target (seq-find (lambda (target)
                                      (equal (oref target name) "bd.dog-1"))
                                    targets))
             (rig-target (seq-find (lambda (target)
                                     (equal (oref target name)
                                            "gascity.el/gc.implementation-worker"))
                                   targets)))
        (should (equal (mapcar (lambda (target) (oref target name)) targets)
                       '("bd.dog-1" "gascity.el/gc.implementation-worker")))
        (should (eq (oref city-target kind) 'agent))
        (should (equal (oref city-target backend) "gc"))
        (should-not (oref city-target scope))
        (should (equal (oref rig-target scope) "gascity.el"))
        (should (equal (oref city-target description) "bd.dog-1"))
        (should (equal (oref city-target metadata)
                       (list :rig nil
                             :city gascity-beads-sling-test--city
                             :qualified-name "bd.dog-1"
                             :source 'roster)))
        (should (equal reads
                       (list (list '("agent" "list")
                                   gascity-beads-sling-test--city))))
        (should-not peeks)))))

(ert-deftest gascity-test-beads-sling-provider-cold ()
  "A cold store answers nil in the same call, without spawning anything."
  (let ((gascity-context-city gascity-beads-sling-test--city)
        (gascity-beads-sling--city nil)
        (spawns nil))
    (cl-letf (((symbol-function 'gascity-store-get)
               (lambda (&rest _) nil))
              ((symbol-function 'gascity-store-peek)
               (lambda (&rest _) (push :peek spawns) nil))
              ((symbol-function 'gascity-reader-read)
               (lambda (&rest _) (push :read spawns) nil))
              ((symbol-function 'gascity-reader-read-async)
               (lambda (&rest _) (push :read-async spawns) nil))
              ((symbol-function 'gascity-reader-run-async)
               (lambda (&rest _) (push :run spawns) nil)))
      (should-not (gascity-beads-sling-targets))
      (should-not spawns))))

(ert-deftest gascity-test-beads-sling-provider-rig-outside-city ()
  "A bead buffer in a rig repository still resolves its city (plan F4)."
  (let ((default-directory gascity-beads-sling-test--rig)
        (gascity-context-city nil)
        (gascity-beads-sling--city nil))
    (cl-letf (((symbol-function 'gascity-context-known-city-roots)
               (lambda () (list gascity-beads-sling-test--city)))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional dir)
                 (gascity-beads-sling-test--rigs dir)))
              ((symbol-function 'gascity-store-get)
               (lambda (&rest _)
                 (list :status 'ready
                       :data gascity-beads-sling-test--agents)))
              ((symbol-function 'gascity-reader-read)
               (lambda (&rest _) (error "Provider spawned a sync read")))
              ((symbol-function 'gascity-reader-run-async)
               (lambda (&rest _) (error "Provider ran an action")))
              ((symbol-function 'file-exists-p)
               (lambda (&rest _) (error "Provider probed the file system"))))
      (should (equal (mapcar (lambda (target) (oref target name))
                             (gascity-beads-sling-targets))
                     '("bd.dog-1" "gascity.el/gc.implementation-worker"))))))

(ert-deftest gascity-test-beads-sling-provider-unknown-city ()
  "No warm city means nil, and nothing is probed to find one."
  (let ((default-directory "/tmp/beads-sling-elsewhere/")
        (gascity-context-city nil)
        (gascity-beads-sling--city nil))
    (cl-letf (((symbol-function 'gascity-context-known-city-roots) #'ignore)
              ((symbol-function 'gascity-store-get)
               (lambda (&rest _) (error "An unresolved city read the store")))
              ((symbol-function 'file-exists-p)
               (lambda (&rest _) (error "Resolved the city with file-exists-p")))
              ((symbol-function 'file-truename)
               (lambda (&rest _) (error "Resolved the city with file-truename")))
              ((symbol-function 'file-in-directory-p)
               (lambda (&rest _) (error "Used file-in-directory-p"))))
      (should-not (gascity-beads-sling--city))
      (should-not (gascity-beads-sling-targets)))))

(ert-deftest gascity-test-beads-sling-city-resolution-order ()
  "The override wins, then a known city that owns DIR, then the memory."
  (let ((dir gascity-beads-sling-test--rig)
        (gascity-beads-sling--city gascity-beads-sling-test--other-city))
    (cl-letf (((symbol-function 'gascity-rigs-cached)
               (lambda (&optional city) (gascity-beads-sling-test--rigs city))))
      ;; 1. `gascity-context-city' is authoritative.
      (let ((gascity-context-city gascity-beads-sling-test--city))
        (cl-letf (((symbol-function 'gascity-context-known-city-roots)
                   (lambda () (list gascity-beads-sling-test--other-city))))
          (should (equal (gascity-beads-sling--city dir)
                         gascity-beads-sling-test--city))))
      ;; 2. A known root whose rig memo owns DIR, and the city root itself.
      (let ((gascity-context-city nil))
        (cl-letf (((symbol-function 'gascity-context-known-city-roots)
                   (lambda () (list gascity-beads-sling-test--city))))
          (should (equal (gascity-beads-sling--city dir)
                         gascity-beads-sling-test--city))
          (should (equal (gascity-beads-sling--city
                          (concat gascity-beads-sling-test--city "beads/"))
                         gascity-beads-sling-test--city))))
      ;; 3. Nothing known matches: the remembered city answers.
      (let ((gascity-context-city nil))
        (cl-letf (((symbol-function 'gascity-context-known-city-roots) #'ignore))
          (should (equal (gascity-beads-sling--city dir)
                         gascity-beads-sling-test--other-city)))))))
