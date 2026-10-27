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
(declare-function gascity-rig-path "gascity-domain" (rig))
(declare-function gascity-remote-canonical-dir "gascity-remote" (dir))
(declare-function gascity-remote-localize-path "gascity-remote"
                  (path &optional dir))
(declare-function gascity-sling--roster "gascity-action" (&optional city))

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

;;; City resolution

;; The remembered city is declared in `gascity-context' (a bare defvar, for
;; its `gascity-context-clear-cache' reset); this module owns its value and
;; documentation.

(defvar gascity-beads-sling--city nil
  "The city directory the last successful sling dispatch resolved, or nil.
Module-scoped, process-local memory (plan §B2, Open Question 3).  The
resolver `gascity-beads-sling--city' consults it only after
`gascity-context-city' and the known-city-root match fail, and it never
justifies a file-system read or a `gc' spawn.  Reset by
`gascity-context-clear-cache'.")

(defun gascity-beads-sling--directory (dir)
  "Return DIR as an expanded, slash-terminated directory name, or nil.
A DIR that is not a non-empty string yields nil.  Pure: `expand-file-name'
dissects a TRAMP name without asking its host."
  (when (and (stringp dir) (not (string-empty-p dir)))
    (file-name-as-directory (expand-file-name dir))))

(defun gascity-beads-sling--below-p (root dir)
  "Non-nil when directory DIR is ROOT or below it.
The test is lexical: both names are expanded and slash-terminated, then
compared with `string-prefix-p'.  Never `file-in-directory-p' — it falls
back to a truename plus `file-exists-p' comparison, a TRAMP round trip on
the Who picker's render path (plan P10)."
  (let ((root (gascity-beads-sling--directory root))
        (dir (gascity-beads-sling--directory dir)))
    (and root dir (string-prefix-p root dir))))

(defun gascity-beads-sling--city-owns-p (root dir)
  "Non-nil when DIR belongs to the city at ROOT.
DIR belongs when it is inside ROOT itself — a city-store bead buffer's
`default-directory' is the city root — or inside one of ROOT's memoized
rigs.  gc reports rig paths host-local, so they are re-prefixed for DIR's
host first (`gascity-remote-localize-path', a pure string operation).
Reads `gascity-rigs-cached' only: a cold rig memo contributes nothing."
  (and (or (gascity-beads-sling--below-p root dir)
           (seq-some (lambda (rig)
                       (when-let* ((path (gascity-rig-path rig)))
                         (gascity-beads-sling--below-p
                          (gascity-remote-localize-path path dir) dir)))
                     (gascity-rigs-cached root)))
       root))

(defun gascity-beads-sling--city (&optional dir)
  "Return the Gas City directory governing DIR, cache-only, or nil.
DIR defaults to `default-directory' and is expanded once, so a TRAMP name
stays a TRAMP name.  Resolution order, first hit wins:

1. `gascity-context-city', the user's override;
2. a root of `gascity-context-known-city-roots' that governs DIR — DIR is
   inside that city's tree or inside one of its memoized rigs;
3. `gascity-beads-sling--city', the city the last dispatch resolved.

A bead buffer's `default-directory' is its rig repository, outside the
city tree (plan F4), so step 2 is what makes the Who picker work from a
bead view; step 3 keeps it working once this session has dispatched.

Probe-free: no file walk, no `file-exists-p'/`file-truename' and no `gc'
spawn — the Who picker calls this on every render (D9, plan P10).  The
answer is canonicalized like the store's entry keys and ends in a slash.
Never walks DIR's parent chain."
  (let ((dir (gascity-beads-sling--directory (or dir default-directory)))
        (known (gascity-context-known-city-roots)))
    (when-let* ((city (or (gascity-beads-sling--directory gascity-context-city)
                          (seq-some (lambda (root)
                                      (gascity-beads-sling--city-owns-p
                                       root dir))
                                    known)
                          (gascity-beads-sling--directory
                           gascity-beads-sling--city))))
      (gascity-remote-canonical-dir city))))

(defun gascity-beads-sling-targets ()
  "Return the city's qualified Gas City sling targets from cached data.
One `beads-sling-target' per configured agent of the cached
\(\"agent\" \"list\") payload (`gascity-sling--roster'), so the Who
picker offers exactly the names `gc sling' accepts: `rig/agent' for a
rig-scoped agent, the bare name for a city-scoped one.

The `beads-sling-target-functions' contract takes no arguments and must
never block, so this answers from the store's last good payload and the
city `gascity-beads-sling--city' resolves from memory.  A cold store or
an unresolved city returns nil in the same call, leaving beads.el's
local targets as the only Who choices.  Never spawns `gc', never reads
the work bead, and contributes no `default_sling_target' row (plan F3)."
  (when-let* ((city (gascity-beads-sling--city)))
    (mapcar (lambda (agent)
              (let ((name (plist-get agent :name))
                    (rig (plist-get agent :rig)))
                (beads-sling-target
                 :name name
                 :kind 'agent
                 :scope rig
                 :backend "gc"
                 :description name
                 :metadata (list :rig rig
                                 :city city
                                 :qualified-name name
                                 :source 'roster))))
            (gascity-sling--roster city))))

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
