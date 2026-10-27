;;; gascity-beads-sling.el --- Register Gas City on beads.el's sling seams -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Gas City Contributors
;; Keywords: tools, processes
;; URL: https://github.com/r0man/gascity.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; gascity.el extends beads.el the way forge extends magit: beads.el owns
;; the generic sling porcelain, its extension hooks and the one-way
;; dependency guard; this module registers gc-specific behavior on those
;; public seams.  The dependency stays one-way -- beads.el never requires
;; gascity.el.
;;
;; The six beads.el seams this module consumes are:
;;
;; - `beads-sling-target-functions' -- contribute the cached gc roster as
;;   Who-picker targets (`gascity-beads-sling-targets').
;; - `beads-sling-backend-register' -- register the named "gc" backend
;;   whose dispatch runs `gc sling' (`gascity-beads-sling--dispatch').
;; - `beads-sling-validators' -- advisory cross-store, target-trap and
;;   missing-var warnings (`gascity-beads-sling--validate-*').
;; - `beads-menu-providers' -- splice the `[City]' group into the beads
;;   dispatch menu (`gascity-beads-sling--menu-group').
;; - `beads-action-providers' -- add the city cockpit to the bead action
;;   bars (`gascity-beads-sling--actions').
;; - `beads-after-action-functions' -- refresh the cached gc views after a
;;   beads mutation (`gascity-beads-sling--after-action').
;;
;; Registration happens once, from `gascity-beads-sling-register', and is
;; idempotent: the backend is replaced by name, the hooks dedupe by
;; function and the provider lists use `add-to-list'.  Loading this module
;; spawns no `gc' process, performs no synchronous read and does no file
;; I/O; every read afterwards goes through `gascity-store-get' or a cached
;; memo only.
;;
;; Cold-start limitation: the target provider can only name a city from
;; `gascity-context-city', a known city root whose memoized rigs contain
;; the beads buffer's (rig-repo) directory, or a city a previous dispatch
;; remembered.  In a fresh Emacs with no gascity view open and no
;; `gascity-context-city' set, the Who picker therefore shows only
;; beads.el's local targets until a city becomes known.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'beads-actions)
(require 'beads-formula)
(require 'beads-menu)
(require 'beads-sling)
(require 'gascity-action)
(require 'gascity-agents)
(require 'gascity-context)
(require 'gascity-dashboard)
(require 'gascity-formula)
(require 'gascity-rig)
(require 'gascity-store)

(defvar gascity-beads-sling--remembered-city nil
  "The city root the last successful sling target lookup or dispatch used.
Rule 3 of `gascity-beads-sling--city-for-directory': a beads buffer
pinned to a rig repo outside the city tree cannot walk up to `city.toml',
so a city the user has already acted on stands in until a known root or
the `gascity-context-city' override answers.")

;;; City resolution (cache-only)

(defun gascity-beads-sling--city-rigs (city)
  "Return CITY's memoized rig list, or nil when the memo is cold.
CITY is recorded as its own root first (`gascity-context-remember-city-root'
is a pure memo write), so the rig lookup never walks the file system
over TRAMP -- that walk is a synchronous round trip."
  (when city
    (gascity-context-remember-city-root city)
    (gascity-rigs-cached city)))

(defun gascity-beads-sling--rig-owns-directory-p (rig dir)
  "Return non-nil when RIG's repository path contains DIR.
Both are compared host-local, so a rig path reported without the TRAMP
prefix still matches a remote `default-directory'."
  (let ((path (ignore-errors (gascity-rig-path rig))))
    (and (stringp path)
         (not (string-empty-p path))
         (string-prefix-p (file-name-as-directory (file-local-name path))
                          (file-name-as-directory (file-local-name dir))))))

(defun gascity-beads-sling--root-owns-directory-p (root dir)
  "Return non-nil when one of ROOT's memoized rigs contains DIR."
  (seq-some (lambda (rig)
              (gascity-beads-sling--rig-owns-directory-p rig dir))
            (gascity-beads-sling--city-rigs root)))

(defun gascity-beads-sling--city-for-directory (&optional dir)
  "Return the known city root governing DIR, or nil.
Cache-only, in the documented order: the `gascity-context-city'
override, a known city root whose memoized rig contains DIR (a beads
buffer pins `default-directory' to its rig repository, which lives
outside the city tree, so the `city.toml' walk cannot answer), then the
city the last target lookup or dispatch remembered.  Never walks the
file system and never spawns `gc'; a fresh session with no view open
answers nil and the provider contributes no city targets."
  (let ((dir (file-name-as-directory
              (expand-file-name (or dir default-directory)))))
    (or (when (and (boundp 'gascity-context-city) gascity-context-city)
          (file-name-as-directory
           (expand-file-name gascity-context-city)))
        (seq-find (lambda (root)
                    (gascity-beads-sling--root-owns-directory-p root dir))
                  (gascity-context-known-city-roots))
        gascity-beads-sling--remembered-city)))

(defun gascity-beads-sling--remember-city (city)
  "Remember CITY as the last city a sling target lookup or dispatch used."
  (when (and (stringp city) (not (string-empty-p city)))
    (setq gascity-beads-sling--remembered-city
          (file-name-as-directory (expand-file-name city)))))

;;; Target provider

(defun gascity-beads-sling--agent-role (city name)
  "Return the role carried by CITY's cached agent named NAME, or nil.
A metadata lookup over the same `gc agent list' payload the roster reads;
the payload carries no role today, so the caller falls back to NAME."
  (let* ((data (plist-get (gascity-store-get '("agent" "list") city) :data))
         (agent (seq-find (lambda (a)
                            (equal (alist-get 'qualified_name a) name))
                          (append (alist-get 'agents data) nil))))
    (or (alist-get 'role agent)
        (alist-get 'role (alist-get 'metadata agent)))))

(defun gascity-beads-sling-targets ()
  "Return the cached `gc agent list' roster as beads.el sling targets.
One `beads-sling-target' per configured agent (`:backend \"gc\"',
`:kind agent, `:scope' the rig name or nil, `:metadata' carrying
`:rig' `:city' `:qualified-name' and `:source').  Reads only the
payload store with an explicit city directory; a cold store or an
unknown city answers nil, and no path here spawns `gc' or blocks."
  (when-let* ((city (gascity-beads-sling--city-for-directory)))
    (gascity-beads-sling--remember-city city)
    (mapcar
     (lambda (agent)
       (let ((name (plist-get agent :name))
             (rig (plist-get agent :rig)))
         (beads-sling-target
          :name name
          :kind 'agent
          :scope rig
          :backend "gc"
          :description (or (gascity-beads-sling--agent-role city name) name)
          :metadata (list :rig rig
                          :city city
                          :qualified-name name
                          :source 'roster))))
     (gascity-sling--roster city))))

;;; Backend: command construction, launch and refresh

(defun gascity-beads-sling--target-scope (name)
  "Return the sling scope of target NAME: its rig prefix, or \"city\".
Mirrors `gascity-agents-scope' over a name alone (a qualified name
carries its rig before the slash; an unqualified one is city-scoped)."
  (cond ((or (null name) (and (stringp name) (string-empty-p name))) nil)
        ((string-search "/" name)
         (substring name 0 (string-search "/" name)))
        (t "city")))

(defun gascity-beads-sling--resolve-target (context bead city)
  "Return the Who target for CONTEXT, BEAD and CITY.
The context `:target' (a name beads.el already resolved) wins.  For the
plain and `on' shapes a missing target derives exactly as
`gascity-sling-dispatch' does -- the work bead's rig default, the
per-(city, formula) memory, then the implementation-worker convention --
over the cached roster and target memory.  The formula-only shape stays
untargeted when the context names no target: a derived real target would
silently turn `--formula' into the targeted `--on' shape.  Never an
empty-string target."
  (let ((target (plist-get context :target)))
    (cond
     ((and (stringp target) (not (string-empty-p (string-trim target))))
      (string-trim target))
     ((memq (plist-get context :shape) '(plain on))
      (plist-get
       (gascity-sling--derive-target
        (list :work bead
              :formula (plist-get context :formula)
              :city city)
        (gascity-sling--roster city)
        gascity-sling--target-memory)
       :target))
     (t nil))))

(defun gascity-beads-sling--command (target bead context)
  "Build the `gascity-command-sling' for TARGET, BEAD and CONTEXT.
The context `:shape' decides `--on' versus `--formula'; the resolved
`:values' alist becomes repeated `--var' arguments in its own order.
Positional slot 1 is the target, slot 2 the bead or formula, so an
absent target drops out instead of becoming an empty argument: `plain'
is `(\"sling\" TARGET BEAD)', `on' is
`(\"sling\" TARGET BEAD \"--on\" FORMULA \"--var\" k=v ...)', and
`formula' is `(\"sling\" [TARGET] FORMULA \"--formula\" \"--var\" k=v ...)'."
  (let* ((shape (plist-get context :shape))
         (formula (plist-get context :formula))
         (varlist (mapcar (lambda (pair) (format "%s=%s" (car pair) (cdr pair)))
                          (plist-get context :values)))
         (arg (pcase shape
                ((or 'plain 'on) bead)
                ('formula formula)
                (_ (user-error
                    "Nothing to sling -- pick work or a formula")))))
    (apply #'gascity-command-sling
           (append
            (when (gascity-formula--nonblank target)
              (list :target target))
            (list :arg arg)
            (pcase shape
              ('plain nil)
              ('on (list :on formula))
              ('formula (list :formula t)))
            (when varlist (list :var varlist))))))

(defun gascity-beads-sling--validate-launch (shape target bead context &optional city)
  "Refuse SHAPE with TARGET, BEAD and CONTEXT before any process starts.
Signals `user-error' for missing work or target (plain and `on' need
both; the formula-only shape may be targetless) and runs beads.el's
`beads-formula-validate-vars' over the context recipe and resolved
values, the same seam the formula launch uses.  When CITY names a
warm `gascity-formula' recipe for the context formula, apply gc's
convoy rule to the formula-only shape: a formula that needs a target
convoy cannot run targetless (`--formula'), so refuse before the
process starts.  A cold recipe cache skips the check and leaves the
refusal to gc, exactly as `gascity-sling-formula--command' does."
  (when (memq shape '(plain on))
    (when (or (not (stringp bead)) (string-empty-p (string-trim bead)))
      (user-error "No work to sling"))
    (when (or (not (stringp target)) (string-empty-p (string-trim target)))
      (user-error "No sling target selected"))
    (when (eq shape 'on)
      (when (gascity-formula--blank (plist-get context :formula))
        (user-error "No formula selected for a targeted sling"))))
  (when (and (eq shape 'formula)
             (gascity-formula--blank (plist-get context :formula)))
    (user-error "No formula selected"))
  (when-let* ((recipe (plist-get context :recipe)))
    (beads-formula-validate-vars recipe (plist-get context :values)))
  (when (and (eq shape 'formula)
             city
             (not (gascity-formula--blank (plist-get context :formula))))
    (when-let* ((recipe (gascity-beads-sling--cached-gascity-recipe
                         (plist-get context :formula) city)))
      (when (gascity-formula--needs-convoy recipe)
        (user-error "Formula %s requires a target convoy -- pick work with A"
                    (plist-get context :formula))))))

(defconst gascity-beads-sling--invalidate-kinds
  '(agent run session convoy status)
  "The store kinds a completed sling in one city changes.
Each kind stands for one store key the launch writes: `agent' for
`(\"agent\" \"list\")', `run' for `(\"run\" \"list\")', `session' for
`(\"session\" \"list\")', `convoy' for `(\"convoy\" \"list\")' and `status'
for `(\"status\")'.")

(defun gascity-beads-sling--invalidate (city)
  "Invalidate the cached `gc' views a sling in CITY changes.
One call per kind; `gascity-store-invalidate' dedupes in-flight
refetches, so each entry is re-read at most once."
  (dolist (kind gascity-beads-sling--invalidate-kinds)
    (gascity-store-invalidate :dir city :kind kind :refetch t)))

(defun gascity-beads-sling--dispatch (_target bead prompt context)
  "Launch BEAD to the context's target through `gc sling' with CONTEXT.
The registered `\"gc\"' backend (`beads-sling-dispatch' calls it as
`(_TARGET BEAD PROMPT CONTEXT)').  Builds the command with
`gascity-command-sling', refuses a missing work/target or a missing
required formula var with a `user-error' before any process starts,
drops PROMPT with a message (`gc sling' has no prompt flag), records the
resolved target as the launch memory, then starts `gc' on the action
lane and returns nil.  On success a formula shape echoes the created
workflow root with the `F' follow offer while a plain shape names the
slung bead and its target (`Slung BEAD to TARGET'), and one invalidation
per store kind refreshes the launcher's cached views; a failure keeps
the inherited first-stderr-line echo and city log."
  (let* ((dir (or (gascity-beads-sling--city-for-directory)
                  (file-name-as-directory (expand-file-name default-directory))))
         (shape (plist-get context :shape))
         (formula (plist-get context :formula))
         (target (gascity-beads-sling--resolve-target context bead dir)))
    (gascity-beads-sling--remember-city dir)
    (gascity-beads-sling--validate-launch shape target bead context dir)
    (when (and (stringp prompt) (not (string-empty-p (string-trim prompt))))
      (message "gc sling has no prompt flag -- dropping the prompt for %s"
               bead))
    (let ((command (gascity-beads-sling--command target bead context))
          (default-directory dir))
      (oset command json t)
      ;; The launch itself is the (city, formula) memory's next default
      ;; (`gascity-sling--derived-target' rule 2), recorded when the
      ;; action starts, exactly as the gascity transient records it.
      (gascity-sling--remember-target dir formula target)
      (gascity-command-act-async
       command
       :target (or target bead)
       :dir dir
       ;; One explicit invalidation per dispatch, in the single success
       ;; closure below: the built-in sling route would invalidate a
       ;; different, narrower set and double up.
       :invalidate nil
       :on-success
       (let ((handler (and (memq shape '(on formula))
                           (gascity-sling--launch-handler
                            command formula bead))))
         (lambda (result)
           ;; A formula shape echoes the created workflow root with the
           ;; momentary `F' follow offer; a plain shape names the bead
           ;; and its Who (a non-nil `:on-success' replaces the
           ;; inherited echo).
           (if handler
               (funcall handler result)
             (message "Slung %s to %s" bead (or target bead)))
           (gascity-beads-sling--invalidate dir))))
      nil)))

;;; Validators (advisory only)

(defun gascity-beads-sling--cached-gascity-recipe (formula city)
  "Return the cached `gascity-formula' for FORMULA in CITY, or nil.
Reads `gascity-formula-recipe-cache' directly: the trap detector needs
the gascity recipe shape (raw step alists), and the beads recipe the
context carries has step objects without `metadata'.  A cold cache is
nil -- never a read."
  (when (and formula city)
    (gascity-context-remember-city-root city)
    (cdr (assoc (cons (gascity-context-scope-key city) formula)
                gascity-formula-recipe-cache))))

(defun gascity-beads-sling--validate-cross-store (context)
  "Warn when CONTEXT routes a bead to another store's rig agent."
  (let* ((work (plist-get context :work))
         (target (plist-get context :target))
         (scope (gascity-beads-sling--target-scope target))
         (city (gascity-beads-sling--city-for-directory)))
    (when city
      (gascity-sling--cross-store-warning
       work scope (gascity-beads-sling--city-rigs city)))))

(defun gascity-beads-sling--validate-target-trap (context)
  "Warn about CONTEXT's target routing: missing, or the formulas-v2 trap.
The trap needs a `gascity-formula' recipe, so it fires only when one is
already cached for the city; the beads recipe is never passed to the
gascity accessors.  The scope comes from the cached roster
\(`gascity-agents-roster-scope' over `gascity-sling--roster', cache-only),
not from the target string alone: the trap is precisely a city-scoped
target on a formula whose steps need a rig-scoped one, and a free-entry
name no roster row carries stays unclassified (no false positive).  The
suggested rig reuses `gascity-sling--footer-rig', so the advisory words
the same remedy the gascity sling footer shows."
  (let* ((shape (plist-get context :shape))
         (target (plist-get context :target))
         (city (gascity-beads-sling--city-for-directory))
         (roster (and city (gascity-sling--roster city)))
         (scope (and (stringp target)
                     (gascity-agents-roster-scope target roster)))
         (recipe (gascity-beads-sling--cached-gascity-recipe
                  (plist-get context :formula) city)))
    (cond
     ((and (memq shape '(plain on))
           (gascity-sling--missing-target-p target))
      gascity-sling--missing-target-warning)
     ((gascity-sling--v2-trap-p recipe scope)
      (gascity-sling--v2-trap-warning
       (gascity-sling--footer-rig roster))))))

(defun gascity-beads-sling--validate-vars (context)
  "Warn about CONTEXT's missing required formula vars."
  (gascity-sling--missing-vars-warning
   (gascity-sling--missing-required-vars
    (plist-get context :recipe)
    (plist-get context :values))))

;;; Menu, action bars and post-mutation refresh

(defun gascity-beads-sling--menu-group ()
  "Return the `[City]' dispatch group in the beads menu.
A provider returns a list of transient group vectors.  The keys
E/J/K/A/Q are free in `beads-dispatch' (audited against its taken set
in `docs/key-registry.md'); `add-to-list' keeps a single group."
  (list ["City"
         ("E" "Cockpit" gascity-dashboard)
         ("J" "Rig dashboard" gascity-rig-dashboard-at-point)
         ("K" "Rig dashboard…" gascity-rig-dashboard)
         ("A" "Agents" gascity-agents)
         ("Q" "Sling (gascity menu)" gascity-sling-dispatch)]))

(defun gascity-beads-sling--actions (context)
  "Return the additive action-bar entries for beads CONTEXT.
The city cockpit on the list and show bars; `S' stays beads.el's
sling, so no contributed key shadows a beads.el binding."
  (pcase context
    ((or :list :show) '(("V" . gascity-dashboard)))
    (_ nil)))

(defconst gascity-beads-sling--after-action-kinds '(bd convoy)
  "Store read kinds a beads mutation invalidates.
`gc' routes its own `bead.*' events to exactly these kinds
\(`gascity-store-event-routes'): every bead-derived payload (`bd':
lists, ready work, runs, session work lists, dashboard work) and convoy
progress (`convoy').  Agent, session and status payloads are not
derived from beads; the views read their beads through `bd' keys.")

(defun gascity-beads-sling--root-contains-directory-p (root dir)
  "Non-nil when directory DIR is ROOT or below it.
Both names are compared host-local, so a memoized city root reported
without the TRAMP prefix still matches a remote DIR.  Pure: no file
access (a TRAMP name is only dissected, never expanded on its host)."
  (let ((root (file-name-as-directory
               (file-local-name (expand-file-name root))))
        (dir (file-name-as-directory
              (file-local-name (expand-file-name dir)))))
    (string-prefix-p root dir)))

(defun gascity-beads-sling--after-action-root (&optional dir)
  "Return the store root whose entries a beads mutation in DIR changes.
DIR defaults to `default-directory', the directory beads.el pinned the
mutating buffer to: the owning rig's repository (beads delegation
contract, DESIGN.md §4.3), which lives outside the city tree.  The
resolver is cache-only, in order: the memoized city root governing DIR,
a known city root that contains DIR or one of its memoized rigs, the
city a sling lookup remembered when it also governs DIR, then DIR
itself.  Never walks the file system and never spawns `gc', so the hook
stays harmless in a beads-only session with no city."
  (let ((dir (file-name-as-directory
              (expand-file-name (or dir default-directory)))))
    (or (gascity-context-city-root-cached dir)
        (seq-find (lambda (root)
                    (or (gascity-beads-sling--root-contains-directory-p
                         root dir)
                        (gascity-beads-sling--root-owns-directory-p root dir)))
                  (gascity-context-known-city-roots))
        (when (and gascity-beads-sling--remembered-city
                   (gascity-beads-sling--root-owns-directory-p
                    gascity-beads-sling--remembered-city dir))
          gascity-beads-sling--remembered-city)
        dir)))

(defun gascity-beads-sling--after-action (action issues)
  "Invalidate the cached `gc' views after beads ACTION on ISSUES.
ACTION is the mutation symbol (close, claim, reopen, status and priority
updates all run it) and ISSUES the affected bead ids; every run of the
hook follows a successful mutation, so neither steers the invalidation.
One `gascity-store-invalidate' call names the mutation's store root
\(`gascity-beads-sling--after-action-root'), the bead-derived kinds and
`:refetch t'.  The store joins a read already in flight and re-reads a
matching entry at most once, so duplicates collapse there.  The hook
neither mutates beads nor asks beads.el for a read and never runs from a
timer, so it cannot loop."
  (ignore action issues)
  (gascity-store-invalidate
   :dir (gascity-beads-sling--after-action-root)
   :kind gascity-beads-sling--after-action-kinds
   :refetch t))

;;; Registration

(defvar gascity-beads-sling--registered nil
  "Non-nil once `gascity-beads-sling-register' has run.
Re-evaluating this module does not re-register; a caller may invoke the
function again, which replaces the backend and dedupes every hook entry.")

(defun gascity-beads-sling-register ()
  "Register gascity's beads.el sling integration; idempotent.
Registers the `\"gc\"' backend (replaced by name), adds the target
provider and the validators (hooks dedupe by function), and adds the
`[City]' menu group, the action entries and the after-action hook
\(`add-to-list' dedupes).  Never spawns `gc'."
  (beads-sling-backend-register
   (beads-sling-backend
    :name "gc"
    :dispatch #'gascity-beads-sling--dispatch
    :description "Gas City: route the bead through `gc sling'."))
  (add-hook 'beads-sling-target-functions #'gascity-beads-sling-targets)
  (add-hook 'beads-sling-validators
            #'gascity-beads-sling--validate-cross-store)
  (add-hook 'beads-sling-validators
            #'gascity-beads-sling--validate-target-trap)
  (add-hook 'beads-sling-validators
            #'gascity-beads-sling--validate-vars)
  (add-to-list 'beads-menu-providers #'gascity-beads-sling--menu-group)
  (add-to-list 'beads-action-providers #'gascity-beads-sling--actions)
  (add-to-list 'beads-after-action-functions
               #'gascity-beads-sling--after-action)
  (setq gascity-beads-sling--registered t))

(unless gascity-beads-sling--registered
  (gascity-beads-sling-register))

(provide 'gascity-beads-sling)
;;; gascity-beads-sling.el ends here
