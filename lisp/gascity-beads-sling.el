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
(require 'beads-formula)
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

;;; Backend dispatch and argv (plan §B3a, REQ-003/REQ-004/REQ-007)

(declare-function beads-formula-validate-vars "beads-formula"
                  (formula vars))
(declare-function beads-sling-shape "beads-sling" (work formula))
(declare-function gascity-command-act-async "gascity-action"
                  (command &rest args))
(declare-function gascity-store-invalidate "gascity-store"
                  (&rest args))

(defconst gascity-beads-sling--invalidate-kinds
  '(agent run session convoy status)
  "The store kinds one completed sling in a city changes, in order.
Each kind stands for the store key the launch writes: `agent' for
`(\"agent\" \"list\")', `run' for `(\"run\" \"list\")', `session' for
`(\"session\" \"list\")', `convoy' for `(\"convoy\" \"list\")' and `status'
for `(\"status\")'.")

(defun gascity-beads-sling--invalidate (dir)
  "Invalidate the cached `gc' views a sling in DIR changes.
Exactly one `gascity-store-invalidate' call per store kind, with
`:refetch t', so each entry is re-read at most once per dispatch.  The
inherited sling route is switched off at the launch (`:invalidate nil'),
which would otherwise invalidate a different, narrower set and double
up.  Called once from the single success closure, never from a timer or
a render path.  A nil DIR invalidates nothing: the store treats a nil
`:dir' as a wildcard, which would touch every city's entries."
  (when dir
    (dolist (kind gascity-beads-sling--invalidate-kinds)
      (gascity-store-invalidate :dir dir :kind kind :refetch t))))

(defun gascity-beads-sling--blank-p (value)
  "Non-nil when VALUE is nil or a whitespace-only string."
  (or (null value)
      (and (stringp value) (string-empty-p (string-trim value)))))

(defun gascity-beads-sling--first-name (&rest names)
  "Return the first non-blank string among NAMES, or nil."
  (seq-find (lambda (name)
              (and (stringp name)
                   (not (gascity-beads-sling--blank-p name))))
            names))

(defun gascity-beads-sling--var-args (values)
  "Return VALUES as `--var' arguments, in order, skipping blanks.
VALUES is the context's `:values' — a (NAME . VALUE) alist.  Only a
non-blank value is emitted, formatted as \"name=value\" (plan §B3a
step 4); a value containing a comma is split by the shared list
formatter, a pre-existing limit of the beads command builder."
  (delq nil
        (mapcar (lambda (pair)
                  (let ((name (car pair))
                        (value (cdr pair)))
                    (unless (gascity-beads-sling--blank-p value)
                      (format "%s=%s" name value))))
                values)))

(defun gascity-beads-sling--command (shape target work formula values)
  "Build the `gascity-command-sling' for SHAPE on TARGET.
WORK is the work bead (or freeform text), FORMULA the formula name,
VALUES the raw (NAME . VALUE) alist.  The single argv builder (plan
§B3a step 6): every row carries a non-empty TARGET — `gc' refuses
`--formula' without an explicit target — and the formula shape puts
the formula name in the bead slot:

  plain    (\"sling\" TARGET WORK)
  on       (\"sling\" TARGET WORK \"--on\" FORMULA \"--var\" \"k=v\" …)
  formula  (\"sling\" TARGET FORMULA \"--formula\" \"--var\" \"k=v\" …)

Never the targetless (\"sling\" \"--formula\" …) shape.  This
builder never asks for JSON itself; `gascity-beads-sling--dispatch'
sets the command's `json' slot, which appends `--json' after the
positionals (the global options come before the subcommand flags) so
the success closure receives a parsed dispatch result (plan §B3)."
  (let ((vars (gascity-beads-sling--var-args values)))
    (pcase shape
      ('plain (gascity-command-sling :target target :arg work))
      ('on (gascity-command-sling :target target :arg work
                                  :on formula :var vars))
      ('formula (gascity-command-sling :target target :arg formula
                                       :formula t :var vars))
      (_ (user-error "No sling work or formula selected")))))

(defun gascity-beads-sling--dispatch (target bead prompt context)
  "Dispatch BEAD to TARGET through the `gc' backend.
TARGET is a `beads-sling-target' whose `backend' is \"gc\", BEAD the
work, PROMPT the freeform instruction and CONTEXT the
`beads-sling--scope-context' plist.  Everything is rebuilt from
CONTEXT — this never reads transient state (plan F1) — in the §B3a
order: work, shape, target, vars, prompt, command, then one
asynchronous launch.

WORK is `(or (plist-get context :work) BEAD)'; it is required for the
`plain' and `on' shapes and ignored by `formula', whose bead slot
carries the formula name.  SHAPE comes from the context's `:shape'
and only defensively falls back to `beads-sling-shape' — never to
gascity's formula cache or `gascity-formula--needs-convoy' (F5).

TARGET resolves in order: the dispatch argument's name (authoritative
— `beads-sling--launch' resolves the target but forwards the context
unchanged, P3), the context's `:target', then
`gascity-sling--derive-target' over the work, formula, resolved city,
cached roster and target memory.  A blank answer is a `user-error'
before any spawn, for every shape, because `gc' refuses `--formula'
without an explicit target (P1).

Vars are validated client-side before the launch when the context
carries a recipe: `beads-formula-validate-vars' is fail-fast and
signals `user-error' itself, so its return value is never tested —
plan P2.  A non-blank PROMPT is dropped with a message — `gc sling' has
no prompt flag — never refused and never put in argv.

The launch is one `gascity-command-act-async' call on the resolved
city, started when the action begins — never blocking (D9): the command
asks for parsed JSON, the resolved target is recorded as the
`(city . formula)' launch memory, and the city is remembered for the
Who picker.  A formula shape (`on', `formula') hands its answer to
`gascity-sling--launch-handler' so the created workflow root is echoed
with the momentary `F' follow offer; a plain shape echoes the shared
success text for the sling and its target.  Either way the one success
closure then invalidates the launcher's cached views once per store
kind (`gascity-beads-sling--invalidate').  Failure keeps the inherited
first-stderr-line echo and city log, and invalidates nothing.  Returns
nil without blocking."
  (let* ((work (or (plist-get context :work) bead))
         (formula (plist-get context :formula))
         (values (plist-get context :values))
         (recipe (plist-get context :recipe))
         (shape (or (plist-get context :shape)
                    (beads-sling-shape work formula))))
    (cond
     ((and (memq shape '(plain on))
           (gascity-beads-sling--blank-p work))
      (user-error "No sling work selected"))
     ((and (memq shape '(on formula))
           (gascity-beads-sling--blank-p formula))
      (user-error "No sling formula selected"))
     ((not (memq shape '(plain on formula)))
      (user-error "No sling work or formula selected")))
    (let* ((city (gascity-beads-sling--city))
           (target-name
            (or (gascity-beads-sling--first-name
                 (and (beads-sling-target-p target) (oref target name))
                 (plist-get context :target))
                (gascity-beads-sling--first-name
                 (plist-get (gascity-sling--derive-target
                             (list :work work :formula formula :city city)
                             (gascity-sling--roster city)
                             gascity-sling--target-memory)
                            :target)))))
      (unless target-name
        (user-error "No sling target selected"))
      ;; Fail fast, client-side, before any process exists (P2).
      (when recipe
        (beads-formula-validate-vars recipe values))
      (unless (gascity-beads-sling--blank-p prompt)
        (message "gc sling has no prompt flag; the instruction is dropped"))
      (let ((command (gascity-beads-sling--command
                      shape target-name work formula values)))
        ;; The launch handler reads parsed JSON from the answer.
        (oset command json t)
        ;; The launch itself is the (city . formula) memory's next
        ;; default, recorded when the action starts, exactly as the
        ;; gascity sling transient records it — and the city is
        ;; remembered so a cold Who picker can resolve it next time.
        (gascity-sling--remember-target city formula target-name)
        (setq gascity-beads-sling--city city)
        (gascity-command-act-async
         command
         :target target-name
         :dir city
         ;; One explicit invalidation per dispatch, in the single success
         ;; closure below: the built-in sling route would invalidate a
         ;; different, narrower set and double up.
         :invalidate nil
         :on-success
         (let ((handler (and (memq shape '(on formula))
                             (gascity-sling--launch-handler
                              command formula work))))
           (lambda (result)
             ;; A formula shape echoes the created workflow root with the
             ;; momentary `F' follow offer; a plain shape echoes the
             ;; shared success text for the sling and its target (a
             ;; non-nil `:on-success' replaces the inherited echo).
             (if handler
                 (funcall handler result)
               (message "%s" (gascity-action--success-text
                               command target-name result)))
             (gascity-beads-sling--invalidate city))))
        nil))))

(defun gascity-beads-sling-register ()
  "Register Gas City's contributions with beads.el's sling seams.
Idempotent: the backend is replaced by name, hook functions are added
once, and the menu provider is appended once.  Performs no `gc' read
or process spawn; only the registration data structures change."
  (beads-sling-backend-register
   (beads-sling-backend
    :name "gc"
    :dispatch #'gascity-beads-sling--dispatch
    :description "Gas City (gc sling)"))
  (add-hook 'beads-sling-target-functions #'gascity-beads-sling-targets)
  (add-hook 'beads-sling-validators #'gascity-beads-sling-validate)
  (add-to-list 'beads-menu-providers #'gascity-beads-sling--menu-group)
  (add-hook 'beads-action-providers #'gascity-beads-sling-actions)
  (add-hook 'beads-after-action-functions #'gascity-beads-sling--after-action)
  (setq gascity-beads-sling--registered t))

(gascity-beads-sling-register)

(provide 'gascity-beads-sling)
;;; gascity-beads-sling.el ends here
