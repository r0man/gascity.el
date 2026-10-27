;;; gascity-beads-sling.el --- Gas City registration on beads.el sling seams -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Gas City's downstream registration on beads.el's public sling seams
;; (plans/beads-sling-integration/implementation-plan.md, workstream B).
;; The dependency stays one-way: gascity.el requires beads.el; beads.el
;; never requires gascity.el.
;;
;; This module consumes exactly six beads.el seams:
;;
;; - `beads-sling-target-functions'   contributes the cached Gas City
;;                                    agent targets to the Who picker;
;; - `beads-sling-backend-register'   registers the `gc' backend that
;;                                    runs `gc sling' for those targets;
;; - `beads-sling-validators'         contributes advisory, cached-data
;;                                    pre-launch warnings;
;; - `beads-menu-providers'           appends the `[City]' group to
;;                                    beads.el's dispatch menu;
;; - `beads-action-providers'         appends Gas City actions to the
;;                                    bead list/detail action bars;
;; - `beads-after-action-functions'   refreshes Gas City's store after a
;;                                    beads mutation.
;;
;; The module renders no bead UI and owns no bead store: beads.el remains
;; the bead porcelain and gascity.el remains a function of `gc --json'
;; output.  Loading it only registers the contributions above; there is
;; no `gc' spawn, synchronous read, file walk or timer at load time.
;;
;; Cold-start limitation: in a fresh Emacs with no Gas City view open and
;; no `gascity-context-city' override, no city is known yet, so the Who
;; picker shows only beads.el's local targets until a Gas City view or a
;; dispatch has resolved one.  The backend still resolves the city for
;; the launch itself.

;;; Code:

(require 'beads-sling)
(require 'gascity-action)
(require 'gascity-formula)
(require 'gascity-store)
(require 'gascity-context)
(require 'gascity-agents)
(require 'gascity-rig)
(require 'gascity-dashboard)

(declare-function beads-sling-backend-register "beads-sling"
                  (backend))
(declare-function gascity-agents "gascity-agents" ())
(declare-function gascity-dashboard "gascity-dashboard" ())
(declare-function gascity-rig-dashboard-at-point "gascity-rig" ())

;; `beads-menu' and `beads-actions' are not runtime dependencies of this
;; module: their variables are declared here with their documented empty
;; defaults, so a package load order that has not pulled those features in
;; yet still registers cleanly.
(defvar beads-action-providers nil)
(defvar beads-after-action-functions nil)
(defvar beads-menu-providers nil)
(defvar beads-sling-target-functions)
(defvar beads-sling-validators)

(defvar gascity-beads-sling--registered nil
  "Non-nil once `gascity-beads-sling-register' has run.
The flag records that this module installed its contributions; the
registration function remains safe to call again, because every seam
replaces or dedupes by identity.")

(defun gascity-beads-sling-targets ()
  "Return Gas City sling targets from cached data.
The `beads-sling-target-functions' provider contract takes no
arguments and must never block, so this answers from the store's last
good payload only.  Until the city roster is resolved this returns
nil and beads.el's local targets remain the only Who choices."
  nil)

(defun gascity-beads-sling-validate (context)
  "Return advisory warnings for sling CONTEXT, or nil.
Part of `beads-sling-validators': warnings never refuse a dispatch,
because `gc' remains the authority.  Every input is cached data; an
input that is not available yields no warning."
  (ignore context)
  nil)

(defun gascity-beads-sling--menu-group ()
  "Return the `[City]' group for beads.el's dispatch menu.
Pure: beads.el calls providers on every menu render, so building the
group must not read the store, spawn `gc' or depend on the current
buffer."
  ["[City]"
   ("C" "Cockpit" gascity-dashboard)
   ("R" "Rig dashboard" gascity-rig-dashboard-at-point)
   ("A" "Agents" gascity-agents)])

(defun gascity-beads-sling-actions (context)
  "Return Gas City actions to append for beads CONTEXT.
CONTEXT is `:list' or `:show'.  The contributions are additive conses
of the form (KEY . COMMAND); nil until a city-backed action applies."
  (ignore context)
  nil)

(defun gascity-beads-sling--after-action (action issues)
  "Refresh Gas City store entries affected by a beads mutation.
ACTION is the mutation symbol and ISSUES the affected bead ids.  Part
of `beads-after-action-functions'; it only invalidates cached entries
and never reads or mutates beads, so it cannot loop."
  (ignore action issues)
  nil)

(declare-function gascity-command-act-async "gascity-action"
                  (command &rest args))

(defun gascity-beads-sling--dispatch (target bead prompt context)
  "Dispatch BEAD to TARGET through the `gc' backend.
TARGET is a `beads-sling-target' whose `backend' is \"gc\", BEAD the
work, PROMPT the freeform instruction and CONTEXT the
`beads-sling--scope-context' plist.  The registration skeleton does
not start a process; the command construction and asynchronous launch
land with the backend work item."
  (ignore target bead prompt context)
  (user-error "Gas City sling dispatch is not wired in this build; use M-x gascity-sling-dispatch"))

(defun gascity-beads-sling-register ()
  "Register Gas City's contributions with beads.el's sling seams.
Idempotent: the backend is replaced by name, hook functions are added
once, and the menu provider is appended once.  Performs no `gc' read
or process spawn; only the registration data structures change."
  (beads-sling-backend-register
   (beads-sling-backend
    :name "gc"
    :dispatch #'gascity-beads-sling--dispatch
    :description "Route the work to a Gas City agent (gc sling)."))
  (add-hook 'beads-sling-target-functions #'gascity-beads-sling-targets)
  (add-hook 'beads-sling-validators #'gascity-beads-sling-validate)
  (add-to-list 'beads-menu-providers #'gascity-beads-sling--menu-group)
  (add-hook 'beads-action-providers #'gascity-beads-sling-actions)
  (add-hook 'beads-after-action-functions #'gascity-beads-sling--after-action)
  (setq gascity-beads-sling--registered t))

(gascity-beads-sling-register)

(provide 'gascity-beads-sling)
;;; gascity-beads-sling.el ends here
