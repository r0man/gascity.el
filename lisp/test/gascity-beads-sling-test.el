;;; gascity-beads-sling-test.el --- beads.el sling seam tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Workstream B's registration module against beads.el's public seams.
;; B5a covers the `[City]' dispatch menu group and the additive bead
;; action provider: one group after repeated registration, the reviewed
;; free keys E/J/K/A/Q, and a `V' cockpit action that never shadows a
;; beads.el binding.
;;
;; B5b covers the after-action refresh: a beads mutation invalidates the
;; bead-derived store kinds exactly once, for the mutation's store root,
;; without reading beads or running from a timer.
;;
;; The provider/backend/validator/idempotence coverage lands with B6
;; (`ga-hbeuz').  Everything stubs the gc boundary, so the suite is
;; offline and asserts that menu rendering spawns nothing.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'gascity)
(require 'gascity-test-helpers)

(defun gascity-test-beads-sling--city-groups ()
  "Return the `[City]' groups currently contributed to the beads menu."
  (seq-filter (lambda (group) (equal (aref group 0) "City"))
              (beads-menu-provider-groups)))

(defun gascity-test-beads-sling--suffixes (group)
  "Return GROUP's suffix specs as a list."
  (append (seq-drop (append group nil) 1) nil))

(ert-deftest gascity-test-beads-sling-menu-and-actions ()
  "One `[City]' group with free keys and an additive `V' action (B5a)."
  (gascity-test-with-store-stubs reads actions
    (gascity-beads-sling-register)
    (gascity-beads-sling-register)
    (should-not reads)
    (should-not actions)
    (let* ((groups (gascity-test-beads-sling--city-groups))
           (group (car groups))
           (suffixes (gascity-test-beads-sling--suffixes group)))
      (should (= 1 (length groups)))
      (should (equal (mapcar #'car suffixes) '("E" "J" "K" "A" "Q")))
      (should (equal (mapcar (lambda (suffix) (nth 1 suffix)) suffixes)
                     '("Cockpit" "Rig dashboard"
                       "Rig dashboard…" "Agents" "Sling (gascity menu)")))
      (should (eq (nth 2 (assoc "E" suffixes)) 'gascity-dashboard))
      (should (eq (nth 2 (assoc "J" suffixes))
                  'gascity-rig-dashboard-at-point))
      (should (eq (nth 2 (assoc "K" suffixes)) 'gascity-rig-dashboard))
      (should (eq (nth 2 (assoc "A" suffixes)) 'gascity-agents))
      (should (eq (nth 2 (assoc "Q" suffixes)) 'gascity-sling-dispatch))
      ;; Every chosen key is free in `beads-dispatch' and none of the
      ;; beads.el keys (notably the delegated `S') is shadowed here.
      (should-not (seq-intersection (mapcar #'car suffixes)
                                    '("S" "RET" "TAB"))))
    (should (equal (gascity-beads-sling--actions :list)
                   '(("V" . gascity-dashboard))))
    (should (equal (gascity-beads-sling--actions :show)
                   '(("V" . gascity-dashboard))))
    (should-not (gascity-beads-sling--actions :menu))
    (let ((contributed (beads-actions-provider-actions :list)))
      (should (member '("V" . gascity-dashboard) contributed))
      (should-not (assoc "S" contributed))
      (should-not (assoc "RET" contributed))
      (should-not (assoc "TAB" contributed)))))

(ert-deftest gascity-beads-sling-test-after-action-invalidates-once ()
  "Every beads mutation invalidates the bead-derived kinds exactly once."
  (dolist (action '(close claim reopen set-status set-priority create update))
    (let (calls)
      (cl-letf (((symbol-function 'gascity-store-invalidate)
                 (lambda (&rest args) (push args calls)))
                ((symbol-function 'gascity-beads-sling--after-action-root)
                 (lambda (&optional _dir) "/city/")))
        (gascity-beads-sling--after-action action '("ga-1")))
      (should (= 1 (length calls)))
      (let ((args (car calls)))
        (should (equal "/city/" (plist-get args :dir)))
        (should (equal '(bd convoy) (plist-get args :kind)))
        (should (eq t (plist-get args :refetch)))))))

(ert-deftest gascity-beads-sling-test-after-action-kind-route ()
  "The invalidated kinds are the ones gc routes its `bead.*' events to."
  (should (equal (alist-get "bead." gascity-store-event-routes nil nil #'equal)
                 gascity-beads-sling--after-action-kinds)))

(ert-deftest gascity-beads-sling-test-after-action-root-from-rig-memo ()
  "A rig-repo directory resolves to the city root that owns it.
The beads delegation contract pins the mutating buffer to the rig's
repository, outside the city tree; the memoized rigs bridge the two."
  (cl-letf (((symbol-function 'gascity-context-city-root-cached)
             (lambda (&optional _dir) nil))
            ((symbol-function 'gascity-context-known-city-roots)
             (lambda () '("/city/")))
            ((symbol-function 'gascity-context-remember-city-root)
             (lambda (root) root))
            ((symbol-function 'gascity-rigs-cached)
             (lambda (&optional _root) '(fake-rig)))
            ((symbol-function 'gascity-rig-path)
             (lambda (_rig) "/city/rigs/gastown.el")))
    (should (equal "/city/"
                   (gascity-beads-sling--after-action-root
                    "/city/rigs/gastown.el/worktrees/ga-1/")))))

(ert-deftest gascity-beads-sling-test-after-action-root-inside-city ()
  "A directory inside a known city tree resolves to that city root."
  (cl-letf (((symbol-function 'gascity-context-city-root-cached)
             (lambda (&optional _dir) nil))
            ((symbol-function 'gascity-context-known-city-roots)
             (lambda () '("/city/")))
            ((symbol-function 'gascity-rigs-cached)
             (lambda (&optional _root) nil)))
    (should (equal "/city/"
                   (gascity-beads-sling--after-action-root
                    "/city/rigs/gastown.el/")))))

(ert-deftest gascity-beads-sling-test-after-action-root-cold ()
  "With no known city the mutation's own directory is the store root.
Cache-only: no file walk and no gc spawn, so a beads-only session is
harmless."
  (cl-letf (((symbol-function 'gascity-context-city-root-cached)
             (lambda (&optional _dir) nil))
            ((symbol-function 'gascity-context-known-city-roots)
             (lambda () nil))
            ((symbol-function 'gascity-rigs-cached)
             (lambda (&optional _root) (error "no read expected"))))
    (should (equal (file-name-as-directory (expand-file-name "/rig/"))
                   (gascity-beads-sling--after-action-root "/rig/")))))

(provide 'gascity-beads-sling-test)
;;; gascity-beads-sling-test.el ends here
