;;; gascity-beads-sling-test.el --- beads.el sling seam tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Workstream B's registration module against beads.el's public seams.
;; B5a covers the `[City]' dispatch menu group and the additive bead
;; action provider: one group after repeated registration, the reviewed
;; free keys E/J/K/A/Q, and a `V' cockpit action that never shadows a
;; beads.el binding.  Everything stubs the gc boundary, so the suite is
;; offline and asserts that menu rendering spawns nothing.

;;; Code:

(require 'ert)
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

(provide 'gascity-beads-sling-test)
;;; gascity-beads-sling-test.el ends here
