;;; gascity-formula.el --- Formula metadata for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The formula module for the formula-aware sling UI (plans/
;; formula-sling-ui/build/implementation-plan.md, unified into the one
;; sling transient by plans/sling-transient-v2).  gascity never
;; reimplements gc logic — this module reads, decodes, caches and checks
;; what `gc formula' reports, and owns the reusable machinery of the
;; formula sling: the generated variable infixes, the deterministic
;; variable-key assignment and the recipe preview backed by a fresh
;; server-side substituted read.  The transient itself is the unified
;; `gascity-sling-dispatch' (`lisp/gascity-action.el').
;;
;; Everything here reads through the single gc call site: `gascity-formula-
;; catalog' and `gascity-formula-recipe' call the generated bang executors
;; `gascity-command-formula-catalog!' / `gascity-command-formula-show!'
;; (`lisp/gascity-types.el'), which run `gc' where `default-directory'
;; points — the path every view buffer pins.  Over TRAMP that is the
;; remote host's gc, transparently.
;;
;; Caches (plan decision D3): the catalog and the per-formula compiled
;; recipes are memoized for the Emacs session, keyed by the ONE
;; city-scoped identity `gascity-context-scope-key' — the governing city
;; root (which embeds the remote prefix), so a local city and its
;; remote `/ssh:HOST:DIR' alias never share an entry, a rig
;; repo inside a city shares its city's entry, and
;; `gascity-context-city' overrides are honoured (REQ-009/REQ-003: one
;; keying scheme across the package).  Nothing
;; re-reads gc from redisplay-time code: the caches are consulted only
;; from user-initiated transient setup and previews.  Invalidation is
;; explicit, via `gascity-formula-invalidate'.
;;
;; The pure helpers enforce gc's declared constraints client-side so
;; mistakes surface before a gc round trip (REQ-008/009):
;; `gascity-formula--validate-values' checks `required' and `pattern' over
;; a var→value alist; `gascity-formula--enum-choices' resolves a var's
;; allowed values (`vars[].enum' when declared, else the built-in name →
;; `metadata.gc.methodology' mapping — plan decision D1); and
;; `gascity-formula--needs-convoy' detects which sling shape a formula
;; requires (drain step or `{{convoy_id}}' reference — plan decision D2,
;; matching gc's own documented sling rule verbatim).  Absent payload
;; fields degrade silently everywhere (REQ-016): no `enum' → string input,
;; no `pattern' → no check, no metadata → no choices.
;;
;; The sling redesign's pre-launch validators (REQ-010, mockup §5;
;; plans/sling-command WI-2) live here too: `gascity-sling--v2-trap-p'
;; (the bl-bdj \"unknown formulas v2 target\" trap),
;; `gascity-sling--cross-store-p' and the §5c missing-pieces checks —
;; pure predicates over the cached recipe, the roster's scope string
;; and the rig memo, each with its mockup-worded warning builder.  They
;; only ever warn (the live footer, the `P' preview): gc stays the
;; authority.
;;
;; History (REQ-010/011): `gascity-formula--history-var' returns an
;; ordinary minibuffer history variable per (formula, var), named
;; `gascity-formula-history-<formula>-<var>'.  The transient's generated
;; infixes read with it as `minibuffer-history-variable', so savehist
;; tracks it automatically — no persistence machinery of its own.
;;
;; The unified sling transient (`gascity-sling-dispatch') keeps a scope
;; plist `(formula target arg)' — the bead or convoy at point seeds
;; `arg' at entry, the `-T' Destination suffix seeds `target', and the
;; `-f' picker seeds `formula' in place.  The Variables section is
;; generated per setup from the chosen formula's `vars[]' — enum vars
;; are fixed-choice options, "true"/"false"-defaulted vars are toggles,
;; the typed conventions of the sling redesign read file, directory,
;; agent and numeric vars through their own infix classes (REQ-006),
;; and everything else is a string option — and the dispatch suffix
;; validates client-side before
;; any gc call, choosing the shape `gascity-formula--needs-convoy'
;; detects.  The recipe preview re-runs `gc formula show' with the
;; current values so gc substitutes server-side.

;;; Code:

(require 'cl-lib)
(require 'transient)
(require 'view)             ; view-mode for the recipe preview buffer
(require 'gascity-error)
(require 'gascity-domain)   ; typed payload classes + decode
(require 'gascity-types)    ; formula-catalog/formula-show bang executors
(require 'gascity-context)  ; the shared city-scoped cache key
(require 'gascity-store)    ; async catalog refresh (shared reads)

;; Action verbs are wired across files: this module is loaded before
;; `gascity-action' (which carries the sling entry and runners) and
;; before `gascity-section' (the at-point ladder).
(declare-function gascity-command-act-async "gascity-action")
(declare-function gascity-sling--show-plan "gascity-action")
(declare-function gascity-sling--launch-handler "gascity-action")
(declare-function gascity-sling--city-dir "gascity-action")
(declare-function gascity-object-at-point "gascity-section")
(declare-function gascity-beads--rig-path "gascity-section")
(declare-function gascity-beads--bead-path-cached "gascity-section")
(declare-function gascity-view-get-buffer-create "gascity-context")

;;; ============================================================
;;; Caches (plan D3, REQ-003/REQ-014)
;;; ============================================================

(defvar gascity-formula-catalog-cache nil
  "Per-city formula catalog memo.
An alist of (CITY-KEY . ENTRIES), ENTRIES a list of
`gascity-formula-catalog-entry'.  CITY-KEY is
`gascity-context-scope-key' of the calling directory — the governing
city root, which embeds the remote prefix — so a local and a remote
city never cross-contaminate.  Session-lifetime; cleared per city by
`gascity-formula-invalidate'.")

(defvar gascity-formula-list-cache nil
  "Per-city memo of `gc formula list': every formula the city can run.
An alist of (CITY-KEY . (CITY-PATH . ROWS)), ROWS the payload's raw
`formulas' rows ((name . N) (source . PATH)) and CITY-PATH its
`city_path'.  The catalog lists only formulas that opt in with a
`[catalog]' block; this list also has the city's own formulas, so the
picker offers the union (bug S-1).  Keyed like the catalog cache.")

(defvar gascity-formula-recipe-cache nil
  "Per-(city, formula) compiled-recipe memo.
An alist of ((CITY-KEY . FORMULA-NAME) . RECIPE), RECIPE a
`gascity-formula'.  CITY-KEY is `gascity-context-scope-key' — the one
city-scoped keying identity (REQ-009/REQ-003).  Session-lifetime;
cleared per city by `gascity-formula-invalidate'.")

;;; ============================================================
;;; Catalog and recipe reads (REQ-001/002/003)
;;; ============================================================

(defun gascity-formula-catalog ()
  "Read `gc formula catalog --json' and return the typed entries.
Runs through `gascity-command-formula-catalog!' where `default-directory'
points (the view's pinned city — over TRAMP, the remote host's gc), and
decodes the envelope's `formulas' into a list of
`gascity-formula-catalog-entry'.

An empty or unreadable catalog signals `user-error' with a clear
message — the caller's picker shows it instead of a cryptic error or a
blank completion list (REQ-002)."
  (condition-case err
      (let ((entries (gascity-domain-decode-list
                      'gascity-formula-catalog-entry
                      (alist-get 'formulas
                                 (gascity-command-formula-catalog!)))))
        (when (null entries)
          (user-error "The formula catalog is empty — no formulas are installed in this city"))
        entries)
    (gascity-command-error
     (user-error "Cannot read the formula catalog: %s" (gascity-error-detail err)))))

(defun gascity-formula-catalog-cached ()
  "Return the current city's formula catalog, through the session cache.
A cache hit is returned as-is; a miss reads through
`gascity-formula-catalog' (which signals `user-error' on an empty or
broken catalog) and memoizes under `gascity-context-scope-key'.  Only
user-initiated code — transient setup and previews — may call this;
nothing on a redisplay path re-reads gc."
  (let ((key (gascity-context-scope-key)))
    (or (cdr (assoc key gascity-formula-catalog-cache))
        (let ((entries (gascity-formula-catalog)))
          (push (cons key entries) gascity-formula-catalog-cache)
          entries))))

(defun gascity-formula-recipe (name)
  "Read `gc formula show NAME --json' and return the decoded recipe.
A `gascity-formula'.  Signals `user-error' with gc's detail when the
formula does not exist or the read fails."
  (condition-case err
      (gascity-domain-decode 'gascity-formula
                             (gascity-command-formula-show! :name name))
    (gascity-command-error
     (user-error "Cannot read formula %s: %s" name (gascity-error-detail err)))))

(defun gascity-formula-recipe-cached (name)
  "Return formula NAME's compiled recipe, through the session cache.
Cache entries are keyed ((`gascity-context-scope-key' . NAME)) under
`gascity-formula-recipe-cache'; a miss reads through
`gascity-formula-recipe' and memoizes.  The cached read carries no
`--var' substitutions — defaults only; the recipe preview re-runs the
uncached `gascity-command-formula-show!' when it wants current values
applied server-side."
  (let ((key (cons (gascity-context-scope-key) name)))
    (or (cdr (assoc key gascity-formula-recipe-cache))
        (let ((recipe (gascity-formula-recipe name)))
          (push (cons key recipe) gascity-formula-recipe-cache)
          recipe))))

(defun gascity-formula-invalidate ()
  "Forget this city's cached formula catalog and recipes.
Clears the entries keyed by `gascity-context-scope-key' from both
caches, leaving other cities' entries untouched.  Called by the unified
sling transient's refresh binding (`gascity-sling-dispatch-refresh') so
a catalog edited mid-session is re-read from gc on the next pick."
  (let ((key (gascity-context-scope-key)))
    (setq gascity-formula-catalog-cache
          (seq-filter (lambda (entry) (not (equal (car entry) key)))
                      gascity-formula-catalog-cache))
    (setq gascity-formula-list-cache
          (seq-filter (lambda (entry) (not (equal (car entry) key)))
                      gascity-formula-list-cache))
    (setq gascity-formula-recipe-cache
          (seq-filter (lambda (entry) (not (equal (caar entry) key)))
                      gascity-formula-recipe-cache)))
  nil)

(defun gascity-formula-refresh-async (formula done &optional cached)
  "Re-read this city's formulas, and FORMULA's recipe, without blocking.
The async `g' of the sling transient (dashboard-v3 §8.5): the catalog,
`gc formula list' and the recipe are read through the store (forced
unless CACHED, deadline-bounded), and each answer replaces its cache
entry only when it arrives — until then the menu keeps the entries it
has.  FORMULA nil skips the recipe.  DONE is called once with no
arguments after every read has answered; a failed read is echoed
\(unless CACHED: the silent prefetch on menu entry) and leaves its old
entry in place.  Returns nil."
  (let* ((key (gascity-context-scope-key))
         (outstanding (if formula 3 2))
         (force (not cached))
         (finish (lambda ()
                   (when (zerop (setq outstanding (1- outstanding)))
                     (funcall done)))))
    (gascity-store-fetch
     '("formula" "list")
     (lambda (payload)
       (setq gascity-formula-list-cache
             (cons (cons key (cons (alist-get 'city_path payload)
                                   (append (alist-get 'formulas payload) nil)))
                   (seq-remove (lambda (e) (equal (car e) key))
                               gascity-formula-list-cache)))
       (funcall finish))
     (lambda (msg)
       (unless cached (message "Cannot refresh the formula list: %s" msg))
       (funcall finish))
     :force force)
    (gascity-store-fetch
     '("formula" "catalog")
     (lambda (payload)
       (let ((entries (gascity-domain-decode-list
                       'gascity-formula-catalog-entry
                       (alist-get 'formulas payload))))
         (setq gascity-formula-catalog-cache
               (cons (cons key entries)
                     (seq-remove (lambda (e) (equal (car e) key))
                                 gascity-formula-catalog-cache))))
       (funcall finish))
     (lambda (msg)
       (unless cached (message "Cannot refresh the formula catalog: %s" msg))
       (funcall finish))
     :force force)
    (when formula
      (gascity-store-fetch
       (list "formula" "show" formula)
       (lambda (payload)
         (let ((rkey (cons key formula)))
           (setq gascity-formula-recipe-cache
                 (cons (cons rkey (gascity-domain-decode 'gascity-formula payload))
                       (seq-remove (lambda (e) (equal (car e) rkey))
                                   gascity-formula-recipe-cache))))
         (funcall finish))
       (lambda (msg)
         (unless cached (message "Cannot refresh formula %s: %s" formula msg))
         (funcall finish))
       :force force))
    nil))

(defun gascity-formula-choices ()
  "Return this city's pickable formulas as (NAME . ANNOTATION), or nil.
The union of the catalog (annotated with its description) and `gc
formula list' (bug S-1): a formula outside the catalog is annotated
`(city)' when its source lies in the city's tree, else `(not in
catalog)'.  Catalog entries first, then the rest, each by name.  Nil
while neither read has answered.  Pure over the caches."
  (let* ((key (gascity-context-scope-key))
         (catalog (cdr (assoc key gascity-formula-catalog-cache)))
         (listed (cdr (assoc key gascity-formula-list-cache)))
         (city-path (car listed))
         (names (mapcar #'gascity-formula-catalog-entry-name catalog))
         (extra nil))
    (dolist (row (cdr listed))
      (let ((name (alist-get 'name row))
            (source (alist-get 'source row)))
        (unless (or (null name) (member name names)
                    (assoc name extra))
          (push (cons name
                      (if (and (stringp city-path) (stringp source)
                               (string-prefix-p (file-name-as-directory city-path)
                                                source))
                          "(city)"
                        "(not in catalog)"))
                extra))))
    (append
     (mapcar (lambda (e)
               (cons (gascity-formula-catalog-entry-name e)
                     (or (gascity-formula-catalog-entry-description e) "")))
             (sort (copy-sequence catalog)
                   (lambda (a b) (string< (gascity-formula-catalog-entry-name a)
                                          (gascity-formula-catalog-entry-name b)))))
     (sort extra (lambda (a b) (string< (car a) (car b)))))))

(defun gascity-formula-choices-wait ()
  "Return `gascity-formula-choices', reading the formulas first when cold.
The picker is input collection (D9): when the menu's prefetch has not
answered yet, wait for the store reads — deadline-bounded by the store,
`C-g' quits — rather than read gc synchronously.  Signals `user-error'
when there is still nothing to offer."
  (or (gascity-formula-choices)
      (let ((done nil)
            (deadline (+ (float-time)
                         (if (numberp gascity-remote-async-timeout)
                             (1+ gascity-remote-async-timeout)
                           31))))
        (message "Reading formulas…")
        (gascity-formula-refresh-async nil (lambda () (setq done t)) 'cached)
        (with-local-quit
          (while (and (not done) (< (float-time) deadline))
            (accept-process-output nil 0.05)))
        (or (gascity-formula-choices)
            (user-error "No formulas to pick — gc formula catalog/list returned none or failed")))))

;;; ============================================================
;;; Enum mapping (plan D1, REQ-005)
;;; ============================================================

(defvar gascity-formula--enum-metadata-keys
  '(("drain_policy" . allowed_drain_policies)
    ("interaction_mode" . interaction_modes)
    ("review_mode" . review_modes))
  "Built-in mapping of formula var name to its methodology choice key.
No shipped gc formula declares `vars[].enum' (plan D1); enum-like value
sets live in the formula's `metadata.gc.methodology' instead, and this
maps the known var names onto them.  A var with neither an explicit
`enum' nor an entry here degrades to plain string input.")

(defun gascity-formula--methodology (formula)
  "Return FORMULA's `metadata.gc.methodology' alist, or nil.
The raw metadata is gc's nested JSON object; anything absent or shaped
differently degrades to nil (REQ-016)."
  (when-let* ((metadata (gascity-formula-metadata formula))
              (gc-meta (alist-get 'gc metadata)))
    (alist-get 'methodology gc-meta)))

(defun gascity-formula--enum-choices (var formula)
  "Return the list of values FORMULA's VAR allows, or nil.
VAR is a `gascity-formula-var', FORMULA its `gascity-formula'.  An
explicit `vars[].enum' wins when gc ever ships it; otherwise the
built-in name → methodology-key mapping
\(`gascity-formula--enum-metadata-keys') consults FORMULA's
`metadata.gc.methodology'.  A var with neither returns nil — the caller
degrades to plain string input (REQ-016)."
  (or (gascity-formula-var-enum var)
      (when-let* ((var-name (gascity-formula-var-name var))
                  (key (cdr (assoc var-name
                                   gascity-formula--enum-metadata-keys)))
                  (choices (alist-get key (gascity-formula--methodology formula))))
        (append choices nil))))

;;; ============================================================
;;; Shape detection (plan D2, REQ-013 detection half)
;;; ============================================================

(defun gascity-formula--needs-convoy (formula)
  "Return non-nil when FORMULA requires the targeted `--on' sling shape.
Applies gc's own documented sling rule verbatim (plan D2): a formula
requires a target convoy iff any `steps[]' entry has a `gc.kind' step
metadata of \"drain\", or any step's title, description or metadata
values contain the literal `{{convoy_id}}' (case-sensitive scan).
Otherwise the targetless `--formula' shape is offered."
  (seq-some #'gascity-formula--step-needs-convoy
            (gascity-formula-steps formula)))

(defun gascity-formula--step-needs-convoy (step)
  "Return non-nil when one raw STEP alist needs a target convoy."
  (or (equal (alist-get 'gc.kind (alist-get 'metadata step)) "drain")
      (gascity-formula--mentions-convoy (alist-get 'title step))
      (gascity-formula--mentions-convoy (alist-get 'description step))
      (gascity-formula--value-mentions-convoy (alist-get 'metadata step))))

(defun gascity-formula--mentions-convoy (string)
  "Return non-nil when STRING contains the literal `{{convoy_id}}'.
A non-string (an absent field, per REQ-016) does not."
  (and (stringp string)
       (string-search "{{convoy_id}}" string)))

(defun gascity-formula--value-mentions-convoy (value)
  "Return non-nil when VALUE (or anything nested in it) mentions `{{convoy_id}}'.
Walks VALUE's strings — the scan spans a step's metadata values
recursively, across nested alists and JSON arrays."
  (cond ((stringp value)
         (gascity-formula--mentions-convoy value))
        ((consp value)
         (or (gascity-formula--value-mentions-convoy (car value))
             (gascity-formula--value-mentions-convoy (cdr value))))
        ((vectorp value)
         (seq-some #'gascity-formula--value-mentions-convoy value))))

;;; ============================================================
;;; Shape inference and the header sentence (sling WI-1,
;;; REQ-001/002)
;;; ============================================================

;; Pure display functions: the shape shown in the sling menu's header
;; is inferred from the work + formula selections — never a flag, never
;; a toggle — and rendered as one sentence.  Dispatch keeps
;; `gascity-formula--needs-convoy' as the AUTHORITATIVE shape rule: a
;; mismatch between the inferred display shape and what gc accepts is
;; the live footer's business (WI-2/WI-6), not a new blocking prompt.

(defun gascity-sling--shape (work formula)
  "Return the sling shape inferred from WORK and FORMULA.
One of the symbols `plain', `formula' or `on': no formula picked is the
plain path; a formula with a chosen work is the targeted `--on' shape;
a formula without work is the targetless `--formula' shape.  Display
only — dispatch re-derives the shape through
`gascity-formula--needs-convoy', gc's own documented rule (plan D2)."
  (cond ((not formula) 'plain)
        ((not (gascity-formula--blank work)) 'on)
        (t 'formula)))

(defun gascity-sling--work-id-p (work)
  "Return non-nil when WORK reads as a bead or convoy id.
The scope's work slot holds either a bead/convoy id (pre-seeded from
point or picked) or freeform task text.  A bare id — one dash joining
two alphanumeric runs, e.g. `bl-5ja', `hw-conv' — gets the \"bead\"
qualifier in the header sentence; anything else (task text usually has
spaces) is rendered as the text itself.  A display heuristic only."
  (and (stringp work)
       (string-match-p "\\`[a-z0-9]+-[a-z0-9]+\\'" work)))

(defconst gascity-sling--no-work-hint "(no work — A or point at a bead)"
  "The header sentence's stand-in for a missing work selection.
Mockup §2 wording: the What stage is unanswered, `A' or pointing at a
bead answers it.")

(defconst gascity-sling--no-target-hint "(no target — T or default)"
  "The header sentence's stand-in for a missing target.
Mockup §2 wording: the Who stage has no derived default, `T' answers
it.")

(defun gascity-sling--work-phrase (work)
  "Return WORK as the header sentence's work phrase.
`bead <id>' for a bare bead/convoy id, the freeform task text as
entered, or the mockup §2 no-work hint when blank."
  (cond ((gascity-formula--blank work) gascity-sling--no-work-hint)
        ((gascity-sling--work-id-p work) (format "bead %s" work))
        (t work)))

(defun gascity-sling--target-phrase (target)
  "Return TARGET as the header sentence's target phrase.
The agent name, or the mockup §2 no-target hint when blank."
  (if (gascity-formula--blank target)
      gascity-sling--no-target-hint
    target))

(defun gascity-sling--header-sentence (work formula target &optional recipe)
  "Return the one-sentence header for the sling scope (REQ-002).
WORK is the bead/convoy id or freeform task text, FORMULA the picked
formula name (nil for the plain path), TARGET the chosen agent, and
RECIPE the picked formula's cached recipe — the \"drained by\" clause
consults `gascity-formula--needs-convoy' on it (mockup §4/§5a); a
non-convoy formula's target renders as \"on <target>\" like the
`--formula' shape.  With RECIPE nil the \"on\" shape degrades to the
non-convoy wording rather than reading gc — nothing on a render path
may run a synchronous read (D9).  The exact wordings are mockup
§1–§4:

  Sling bead bl-5ja to mayor
  Run pancakes (formula) on mayor
  Run build-basic against bead bl-5ja, drained by mayor"
  (let ((target-phrase (gascity-sling--target-phrase target)))
    (pcase (gascity-sling--shape work formula)
      ('plain
       (format "Sling %s to %s"
               (gascity-sling--work-phrase work) target-phrase))
      ('formula
       (format "Run %s (formula) on %s" formula target-phrase))
      ('on
       (format "Run %s against %s, %s %s"
               formula (gascity-sling--work-phrase work)
               (if (and recipe (gascity-formula--needs-convoy recipe))
                   "drained by" "on")
               target-phrase)))))
;;; Sling validators (REQ-010, mockup §5) — pure, never blocking
;;; ============================================================

;; The client-side pre-launch checks of the sling redesign (plans/
;; sling-command, WI-2).  gc stays the authority: every predicate feeds
;; the live footer's ⚠ (WI-6) and the `P' preview, nothing here ever
;; refuses a dispatch.  All are pure over cached data — the recipe, the
;; scope string `gascity-agents-roster-scope' classifies from the
;; roster, and the rig memo the caller passes (the same prefix→rig
;; routing the bd verbs use).  Anything unresolvable — free entry, a
;; cold roster or memo — degrades to no warning: a cold roster never
;; dead-ends, gc answers at launch.

(defun gascity-sling--binding-qualified-target-p (value)
  "Return non-nil when VALUE is a binding-qualified run target.
A string containing a `.' and no `/': \"gc.run-operator\" qualifies,
\"mayor\" and \"hello-world/polecat\" do not, and a non-string (an
absent or null field, REQ-016) never does."
  (and (stringp value)
       (string-search "." value)
       (not (string-search "/" value))))

(defun gascity-sling--binding-targets-p (recipe)
  "Return non-nil when any step of RECIPE carries a binding-qualified run target.
A step `metadata[\"gc.run_target\"]' whose value qualifies
\(`gascity-sling--binding-qualified-target-p') — build-basic's
\"gc.run-operator\" steps (23 of 38 against bright-lights).  Pure
over the cached recipe; a nil RECIPE (no formula picked) is no."
  (and recipe
       (seq-some (lambda (step)
                   (gascity-sling--binding-qualified-target-p
                    (alist-get 'gc.run_target (alist-get 'metadata step))))
                 (gascity-formula-steps recipe))))

(defun gascity-sling--v2-trap-p (recipe scope)
  "Return non-nil when RECIPE at SCOPE is the bl-bdj trap (REQ-010).
A formula whose steps name binding-qualified run targets needs a
rig-scoped target: gc fails its instantiation with \"unknown formulas
v2 target\" (bl-bdj) — the trap fires at launch, a dry run never
exercises it, so the client warns first.  SCOPE \"city\" (from
`gascity-agents-roster-scope') traps; a rig name does not; nil (free
entry, a cold roster) degrades to no warning."
  (and (gascity-sling--binding-targets-p recipe)
       (equal scope "city")))

(defun gascity-sling--v2-trap-warning (&optional rig)
  "Return the bl-bdj trap's footer warning (mockup §5a wording).
RIG names the agent to suggest — \"pick a hello-world/* agent with
T\"; without one the suggestion stays generic."
  (format "formulas v2 target: this formula needs a rig-scoped target — the chosen city agent will fail with \"unknown formulas v2 target\" (bl-bdj); pick a %s with T"
          (if (gascity-formula--nonblank rig)
              (format "%s/* agent" rig)
            "rig-scoped agent")))

(defun gascity-sling--bead-prefix (bead)
  "Return BEAD's store prefix — the id part before the first hyphen.
\"hw-ab12\" → \"hw\".  nil when BEAD is nil or not a bead id: freeform
work text never resolves to a store (gc creates its bead in the
target's store at launch)."
  (when (and (stringp bead)
             (string-match "\\`\\([[:alnum:]]+\\)-[[:alnum:]]+\\'" bead))
    (match-string 1 bead)))

(defun gascity-sling--bead-store (bead rigs)
  "Return BEAD's store — the name of the rig whose id prefix it carries.
RIGS is the rig memo (`gascity-rigs-cached': the same prefix→rig
routing the bd verbs use, the city HQ included as a rig row).  nil
when BEAD is not a bead id, or its prefix matches no rig (a foreign
prefix or a cold memo): an unresolvable store degrades, never
guesses."
  (when-let* ((prefix (gascity-sling--bead-prefix bead)))
    (when-let* ((rig (seq-find (lambda (rig)
                                 (equal (gascity-rig-prefix rig) prefix))
                               rigs)))
      (gascity-rig-name rig))))

(defun gascity-sling--cross-store-p (work scope rigs)
  "Return non-nil when WORK and a rig-scoped SCOPE read different stores.
gc refuses a bead routed to another rig's agent (\"Cross-rig … without
--force, sling would refuse\", verified by dry run against
bright-lights): WORK's store resolves from its id prefix against RIGS,
and SCOPE — the target's, a rig-scoped agent naming its rig — must
match it.  A city-scoped target never fires: the mayor routes beads
of every store (mockup §5b's remedy).  Anything unresolvable —
freeform work, a cold memo, free entry — degrades to no warning."
  (when-let* ((store (gascity-sling--bead-store work rigs)))
    (and (gascity-formula--nonblank scope)
         (not (equal scope "city"))
         (not (equal scope store)))))

(defun gascity-sling--cross-store-warning (work scope rigs)
  "Return the cross-store route's footer warning (mockup §5b wording).
WORK is the slung bead; SCOPE the menu's scope plist; RIGS the rig
list the store split comes from.  The message names the bead, its
store and the target's, and suggests a city agent or one of the
bead's store.  nil when the route is not cross-store
\(`gascity-sling--cross-store-p')."
  (when (gascity-sling--cross-store-p work scope rigs)
    (let ((store (gascity-sling--bead-store work rigs)))
      (format "cross-store route: bead %s lives in the %s store but the target reads the %s store — gc will refuse (pick a city agent or a %s agent)"
              work store scope store))))

(defun gascity-sling--missing-work-p (recipe work)
  "Return non-nil when RECIPE drains a bead but no work is in scope (§5c).
A convoy-requiring formula (plan D2) with blank WORK — gc would
refuse at dispatch (\"requires a target convoy\"), so the footer says
it first.  A nil RECIPE (the plain shape) never fires: freeform text
is its work."
  (and recipe
       (gascity-formula--needs-convoy recipe)
       (gascity-formula--blank work)))

(defun gascity-sling--missing-work-warning (recipe)
  "Return the missing-work footer warning (mockup §5c wording).
RECIPE names the drain formula the warning is about."
  (format "%s drains a bead — pick work with A (or point at one)"
          (or (gascity-formula-name recipe) "formula")))

(defun gascity-sling--missing-required-vars (recipe values)
  "Return RECIPE's required vars missing from VALUES, in declared order.
The non-signaling half of `gascity-formula--validate-values': the
live footer warns (mockup §5c) while dispatch still refuses with the
`user-error'.  VALUES is a (VAR-NAME . VALUE) alist; a var absent
from it counts as empty."
  (delq nil
        (mapcar (lambda (var)
                  (and (gascity-formula-var-required var)
                       (gascity-formula--blank
                        (cdr (assoc (gascity-formula-var-name var) values)))
                       (gascity-formula-var-name var)))
                (or (and recipe (gascity-formula-vars recipe)) '()))))

(defun gascity-sling--missing-vars-warning (names)
  "Return the missing-vars footer warning (mockup §5c wording), or nil.
NAMES are the missing required vars."
  (and names
       (format "Missing required vars: %s" (mapconcat #'identity names ", "))))

(defun gascity-sling--missing-target-p (target)
  "Return non-nil when no target is in scope (mockup §5c).
Blank TARGET: WI-3's derived default answers this before the footer
renders, and `s' prompts when nothing is derivable."
  (gascity-formula--blank target))

(defconst gascity-sling--missing-target-warning
  "No target — T to choose, or s will prompt"
  "The missing-target footer warning (mockup §5c wording).")

;;; ============================================================
;;; Validation (REQ-008/009)
;;; ============================================================

(defun gascity-formula--validate-values (formula values)
  "Check VALUES against FORMULA's declared vars, before any gc call.
VALUES is an alist of (VAR-NAME . VALUE); a var absent from it counts
as empty.  A missing required var signals `user-error' naming every
missing var (the same list `gascity-sling--missing-required-vars'
collects for the live footer's ⚠); a value that fails its var's
`pattern' signals `user-error' naming the var and the pattern.
Nothing here runs gc — the point is to fail fast, client-side
\(REQ-008/009)."
  (let ((missing (gascity-sling--missing-required-vars formula values)))
    (when missing
      (user-error "Missing required formula vars: %s"
                  (mapconcat #'identity missing ", ")))
    (dolist (var (or (gascity-formula-vars formula) '()))
      (let ((pattern (gascity-formula-var-pattern var))
            (value (cdr (assoc (gascity-formula-var-name var) values))))
        ;; Only a value actually entered is pattern-checked; a blank one
        ;; is the required check's business.  A pattern that does not
        ;; compile as an Emacs regexp degrades to no validation (REQ-016).
        (when (and pattern (gascity-formula--nonblank value))
          (condition-case _err
              (unless (string-match pattern value)
                (user-error "Var %s does not match pattern %s"
                            (gascity-formula-var-name var) pattern))
            (invalid-regexp nil)))))))

(defun gascity-formula--blank (value)
  "Return non-nil when VALUE is nil or all whitespace."
  (or (null value)
      (and (stringp value) (string-empty-p (string-trim value)))))

(defun gascity-formula--nonblank (value)
  "Return non-nil when VALUE is a string with non-whitespace content."
  (and (stringp value) (not (string-empty-p (string-trim value)))))

;;; ============================================================
;;; History registry (REQ-010/011)
;;; ============================================================

(defun gascity-formula--history-var (formula var)
  "Return the minibuffer history symbol for FORMULA's VAR.
An ordinary history variable named
`gascity-formula-history-<formula>-<var>', with non-word characters
sanitized to hyphens.  Distinct per (formula, var): the same variable
name in two formulas keeps two histories.  Used as
`minibuffer-history-variable', so savehist tracks it with no extra
persistence machinery (REQ-010/011)."
  (intern (format "gascity-formula-history-%s-%s"
                  (gascity-formula--sanitize formula)
                  (gascity-formula--sanitize var))))

(defun gascity-formula--sanitize (name)
  "Return NAME with every non-word character replaced by a hyphen."
  (replace-regexp-in-string "[^[:alnum:]_]+" "-" (or name "")))

;;; ============================================================
;;; Formula sling machinery (unified-prefix backend)
;;; ============================================================

;; The formula sling's reusable pieces: the deterministic variable-key
;; assignment, the generated per-var infixes and their client-side
;; checks, and the recipe preview.  The transient that drives them is
;; the unified `gascity-sling-dispatch' (`lisp/gascity-action.el').

(defvar gascity-sling-formula-picker-history nil
  "Minibuffer history of `gascity-sling-formula--read-formula' picks.
An ordinary history variable: savehist tracks it like any other.")

(defalias 'gascity-sling-formula--set-var #'transient--default-infix-command
  "The shared infix command of every generated variable infix.
Transient's own default infix command; the live suffix object is
disambiguated per key by `transient-suffix-object'.")
(put 'gascity-sling-formula--set-var 'interactive-only t)
(put 'gascity-sling-formula--set-var 'completion-predicate
     #'transient--suffix-only)

;;; ---- Generated infix classes ---------------------------------

;; Slots carry the var's payload, so the shared methods need no
;; per-instance closures in the generated specs.
(defclass gascity-sling-formula--var-option (transient-option)
  ((var-name
    :initarg :var-name :initform nil
    :documentation "Variable name — the `--var name=' key.")
   (var-description
    :initarg :var-description :initform nil
    :documentation "The var's description; the read prompt.")
   (var-default
    :initarg :var-default :initform nil
    :documentation "The var's default; the initial value when unset.")
   (var-required
    :initarg :var-required :initform nil
    :documentation "Non-nil when dispatch refuses to run without a value.")
   (var-pattern
    :initarg :var-pattern :initform nil
    :documentation "Regexp the value must match, when declared.")
   (var-choices
    :initarg :var-choices :initform nil
    :documentation "Declared choice list, when the var is an enum.")
   (var-seed
    :initarg :var-seed :initform nil
    :documentation "The scope-derived initial value (REQ-006): the
`plans/<slug>/' artifact_root seed, the chosen target's rig for
`rig_name', the chosen target itself for `*_target' vars.  Overrides
the declared default when non-nil and stays editable like any value."))
  :abstract t
  :documentation "Base class of the generated formula-var infixes.
One infix per declared var, class per shape (REQ-004..007): an enum
restricted to its declared choices, a `true'/`false'-defaulted toggle,
a typed file, directory, agent or numeric option (REQ-006), or a plain
string option; absent fields degrade (REQ-016).")

(defclass gascity-sling-formula--enum-option (gascity-sling-formula--var-option)
  ()
  :documentation "A var with declared choices: input is restricted to
them (`completing-read' with `require-match'), so illegal values are
unrepresentable by construction (REQ-005).")

(defclass gascity-sling-formula--bool-option (gascity-sling-formula--var-option)
  ()
  :documentation "A var whose default is `true'/`false': a toggle whose
value serializes to `name=true' / `name=false' (REQ-006).")

(defclass gascity-sling-formula--string-option (gascity-sling-formula--var-option)
  ()
  :documentation "A plain string var: minibuffer read with the var's
description as prompt and its default as initial value, per-(formula
var) history (REQ-010), and `pattern' validation on entry (REQ-009).
Also the fail-soft class of the class heuristic: anything the typed
conventions do not recognize reads here (REQ-006, REQ-016).")

(defclass gascity-sling-formula--file-option (gascity-sling-formula--var-option)
  ()
  :documentation "A var naming a file (REQ-006: `context_path' and
any `*_path'): `read-file-name' completing against the target rig's
workdir, the read's `default-directory' pinned to it so completion is
TRAMP-safe and never touches the menu buffer's directory.  An empty
answer unsets the var.")

(defclass gascity-sling-formula--directory-option (gascity-sling-formula--var-option)
  ()
  :documentation "A var naming a directory (REQ-006:
`artifact_root'): `read-directory-name' over the target rig's workdir;
the artifact root seeds `plans/<slug>/' from the work bead's title
\(`gascity-sling--title-slug'), editable like any value.")

(defclass gascity-sling-formula--agent-option (gascity-sling-formula--var-option)
  ()
  :documentation "A var naming a sling target agent (REQ-006: any
`*_target'): the roster completion the Who picker shares, free entry
always possible — the roster is a convenience, gc the authority
\(REQ-016).")

(defclass gascity-sling-formula--numeric-option (gascity-sling-formula--var-option)
  ()
  :documentation "A numeric var (REQ-006): any non-digit entry is
refused with a `user-error' before any gc call could run.")

(defclass gascity-sling-formula--function-option (gascity-sling-formula--var-option)
  ((var-reader
    :initarg :var-reader :initform nil
    :documentation "The override reader of
`gascity-sling-var-readers': called with this option object,
returning the value (REQ-006)."))
  :documentation "A var whose reader the override alist replaces with
a site-local function: the custom typed read of last resort (REQ-006).")

(cl-defmethod transient-prompt ((obj gascity-sling-formula--var-option))
  "Return OBJ's var description as the read prompt (REQ-007).
A var without a description degrades to a generic prompt (REQ-016)."
  (format "%s: "
          (or (oref obj var-description)
              (format "Formula var %s" (oref obj var-name)))))

(cl-defmethod transient-init-value ((obj gascity-sling-formula--var-option))
  "Seed OBJ's value from the most specific fallback available.
The order is the transient value, else the var's seed, else its
default.  The next method extracts a value the user already set in
this transient \(it survives the re-setup a formula re-pick
performs\); an unset var falls back to its scope-derived seed first
— the convention defaults the How group shows (REQ-006) — then to
its declared default \(REQ-007\)."
  (cl-call-next-method)
  (when (null (oref obj value))
    (oset obj value (or (oref obj var-seed)
                        (oref obj var-default)))))

(defun gascity-sling-formula--read-guarded (obj read)
  "Run infix READ for OBJ, surviving a refused or aborted entry (F1).
A validation `user-error' (an illegal numeric, a pattern mismatch) or
an aborted read (`C-g', which signals `quit') reports in the echo
area and leaves OBJ's value unchanged, so the menu stays open
instead of quitting the whole transient with its answers (WI-11
finding F1).  A successful READ's value is returned as-is."
  (condition-case err
      (funcall read)
    ((user-error quit)
     (message "%s" (error-message-string err))
     (oref obj value))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--enum-option))
  "Read one of the var's declared choices from OBJ only (REQ-005).
Illegal values are unrepresentable; history is per (formula, var).
An aborted read reports and keeps the current value (F1)."
  (gascity-sling-formula--read-guarded
   obj
   (lambda ()
     (completing-read (transient-prompt obj)
                      (oref obj var-choices) nil t
                      (or (oref obj value) (oref obj var-default))
                      (gascity-sling-formula--history obj)))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--bool-option))
  "Cycle the boolean var of OBJ true -> false -> true (REQ-006).
Nothing is read: illegal values are unrepresentable by construction."
  (pcase (oref obj value)
    ("true" "false")
    ("false" "true")
    (_ (or (oref obj var-default) "true"))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--string-option))
  "Read the string var of OBJ through the shared string read (REQ-009).
An aborted read keeps the current value (F1)."
  (gascity-sling-formula--read-guarded
   obj (lambda () (gascity-sling-formula--read-string obj))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--file-option))
  "Read the file var of OBJ through the shared file read (REQ-006).
An aborted read keeps the current value (F1)."
  (gascity-sling-formula--read-guarded
   obj (lambda () (gascity-sling-formula--read-file obj))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--directory-option))
  "Read the directory var of OBJ through the shared directory read (REQ-006).
An aborted read keeps the current value (F1)."
  (gascity-sling-formula--read-guarded
   obj (lambda () (gascity-sling-formula--read-directory obj))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--agent-option))
  "Read the agent var of OBJ through the shared roster read (REQ-006).
An aborted read keeps the current value (F1)."
  (gascity-sling-formula--read-guarded
   obj (lambda () (gascity-sling-formula--read-agent obj))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--numeric-option))
  "Read the numeric var of OBJ through the shared numeric read (REQ-006).
A refused non-numeric entry reports and keeps the current value, so
the menu stays open (F1)."
  (gascity-sling-formula--read-guarded
   obj (lambda () (gascity-sling-formula--read-numeric obj))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--function-option))
  "Read OBJ's var through its override reader (REQ-006).
The reader is `gascity-sling-var-readers' entry for this var's name,
called with OBJ itself; an absent reader degrades to the string read
\(REQ-016).  An aborted read keeps the current value (F1)."
  (gascity-sling-formula--read-guarded
   obj
   (lambda ()
     (if (functionp (oref obj var-reader))
         (funcall (oref obj var-reader) obj)
       (gascity-sling-formula--read-string obj)))))

;;; ---- The typed readers (REQ-006) -----------------------------

;; The named functions behind the typed classes — the class methods
;; delegate here, and the override alist `gascity-sling-var-readers'
;; points var names at them.  All take the live infix object, whose
;; slots carry the var's payload (name, default, pattern …), and return
;; the value or nil to unset.

(defun gascity-sling-formula--var-initial (obj)
  "Return OBJ's read-time initial input, its most specific fallback.
That is the current value, else the declared default, else the
scope-derived seed (REQ-006/007).  The current value already carries
the seed at setup
\\(`transient-init-value'); the later fallbacks cover objects built
without one."
  (or (oref obj value)
      (and (gascity-formula--nonblank (oref obj var-default))
           (oref obj var-default))
      (oref obj var-seed)))

(defun gascity-sling-formula--read-string (obj)
  "Read the string var of OBJ, validating its `pattern' on entry (REQ-009).
An empty entry unsets the var (transient's own empty-value rule); the
required check stays with dispatch.  History is per (formula, var)."
  (let ((value (read-from-minibuffer
                (transient-prompt obj)
                (gascity-sling-formula--var-initial obj)
                nil nil (gascity-sling-formula--history obj))))
    (when (and (stringp value) (not (string-empty-p value)))
      (gascity-sling-formula--check-pattern
       (oref obj var-name) (oref obj var-pattern) value)
      value)))

(defun gascity-sling-formula--read-file (obj)
  "Read the file var of OBJ relative to the target rig's workdir (REQ-006).
`read-file-name' completes against the workdir
\(`gascity-sling-formula--rig-workdir'), which is also the read's
pinned `default-directory' — over TRAMP that is the rig's host-local
path re-prefixed (`gascity-remote-localize-path' through the store
helper), so completion never touches the menu buffer's directory.
The returned name is reduced to its host-local form
\(`file-local-name'), since gc runs host-side and cannot consume a
`/ssh:HOST:…' name (WI-11 finding F3).
The current value (or declared default or seed) pre-fills the
minibuffer as the plain-RET answer; an erased, empty answer unsets
the var.  File names keep `file-name-history' — `read-file-name' has
no history argument — the per-(formula,var) history applies to the
minibuffer-read types."
  (let* ((dir (gascity-sling-formula--rig-workdir))
         (default-directory dir)
         (insert-default-directory nil)
         (value (file-local-name
                 (read-file-name (transient-prompt obj) dir nil nil
                                 (gascity-sling-formula--var-initial obj)))))
    (if (and (stringp value) (string-empty-p value))
        nil value)))

(defun gascity-sling-formula--read-directory (obj)
  "Read the directory var of OBJ over the target rig's workdir (REQ-006).
`read-directory-name' with the same pinned workdir, defaulting and
empty-answer rules as the file read (`gascity-sling-formula--read-file').
The returned name is host-localized like the file read's
\(`file-local-name'), since gc runs host-side and cannot consume a
`/ssh:HOST:…' name (WI-11 finding F3)."
  (let* ((dir (gascity-sling-formula--rig-workdir))
         (default-directory dir)
         (insert-default-directory nil)
         (value (file-local-name
                 (read-directory-name (transient-prompt obj) dir nil nil
                                      (gascity-sling-formula--var-initial obj)))))
    (if (and (stringp value) (string-empty-p value))
        nil value)))

(defun gascity-sling-formula--read-agent (obj)
  "Read the agent var of OBJ with the roster completion (REQ-006).
Candidates are the sling city's qualified agent names
\(`gascity-sling-formula--agent-candidates'); free entry always works
— the roster is a convenience, gc the authority (REQ-016).  History is
per (formula, var)."
  (let ((value (completing-read
                (transient-prompt obj)
                (gascity-sling-formula--agent-candidates)
                nil nil
                (gascity-sling-formula--var-initial obj)
                (gascity-sling-formula--history obj))))
    (if (string-empty-p value) nil value)))

(defun gascity-sling-formula--read-numeric (obj)
  "Read the numeric var of OBJ, refusing anything else (REQ-006).
An all-digit entry returns; any other non-empty entry signals a
`user-error' — \"Var %s must be numeric (got %s)\" — before any gc
call could run.  An empty answer unsets the var.  History is per
\(formula, var)."
  (let ((value (read-from-minibuffer
                (transient-prompt obj)
                (gascity-sling-formula--var-initial obj)
                nil nil (gascity-sling-formula--history obj))))
    (when (and (stringp value) (not (string-empty-p value)))
      (unless (string-match-p "\\`[0-9]+\\'" value)
        (user-error "Var %s must be numeric (got %s)"
                    (or (oref obj var-name) "var") value))
      value)))

(defun gascity-sling-formula--check-pattern (name pattern value)
  "Signal `user-error' when PATTERN rejects NAME's VALUE (REQ-009).
The message names the var and the pattern.  A pattern that does not
compile as an Emacs regexp degrades to no validation (REQ-016)."
  (when (and pattern (gascity-formula--nonblank value))
    (condition-case _err
        (unless (string-match pattern value)
          (user-error "Var %s does not match pattern %s" name pattern))
      (invalid-regexp nil))))

(defun gascity-sling-formula--history (obj)
  "Return OBJ's var minibuffer history variable (REQ-010/011).
An ordinary variable named `gascity-formula-history-<formula>-<var>'
via `gascity-formula--history-var', so savehist tracks it; the same
variable name in two formulas keeps two histories.  The infixes pass it
as the read's HISTORY argument, which makes it the read's
`minibuffer-history-variable'."
  (let ((sym (gascity-formula--history-var
              (or (plist-get (transient-scope) :formula) "")
              (or (oref obj var-name) ""))))
    (unless (boundp sym)
      (set sym nil))
    sym))

;;; ---- The class heuristic (REQ-006) ---------------------------

(defcustom gascity-sling-var-readers nil
  "Alist of formula var names to the readers overriding the heuristic.
Each entry is (VAR-NAME . READER): the var named VAR-NAME — a
formula schema's declared var name, matched exactly — reads through
READER instead of the naming conventions
`gascity-sling-formula--var-class' would pick (REQ-006).  READER is
one of the typed readers (`gascity-sling-formula--read-file',
`gascity-sling-formula--read-directory',
`gascity-sling-formula--read-agent',
`gascity-sling-formula--read-numeric', or
`gascity-sling-formula--read-string' to force plain string entry),
any other function of one infix object (wrapped as the var's custom
reader), or an infix class symbol (a subclass of
`gascity-sling-formula--var-option') for a direct class pick.  An
unmatched var simply falls through to the heuristic, fail-soft
\(REQ-016)."
  :type '(alist :key-type (string :tag "Var name")
                :value-type (choice (function :tag "Reader function")
                                    (symbol :tag "Infix class")))
  :group 'gascity)

(defconst gascity-sling-formula--reader-classes
  '((gascity-sling-formula--read-file . gascity-sling-formula--file-option)
    (gascity-sling-formula--read-directory . gascity-sling-formula--directory-option)
    (gascity-sling-formula--read-agent . gascity-sling-formula--agent-option)
    (gascity-sling-formula--read-numeric . gascity-sling-formula--numeric-option)
    (gascity-sling-formula--read-string . gascity-sling-formula--string-option))
  "The typed readers and the infix classes reading with them (REQ-006).
The override alist's reader symbols resolve to their classes here —
`gascity-sling-formula--var-class' consults it first.")

(defun gascity-sling-formula--var-class (var formula)
  "Return the infix class that reads FORMULA's VAR (REQ-006).
The override alist `gascity-sling-var-readers' first — a var mapped
to one of the typed readers reads as that type no matter what any
convention says; a mapped infix class passes through; any other
function wraps as the var's custom reader (the function-option
class).  Without an override, the var's declared shape wins — a
declared choice list reads as the restricted enum option, a
`true'/`false' default as the toggle — then the naming conventions:
`context_path' and any `*_path' a file option (completion relative
to the target rig's workdir), `artifact_root' a directory option (the
`plans/<slug>/' seed), any `*_target' an agent option (the roster
completion), and numeric vars — an all-digit declared default, a
`max_' prefix or an `_iterations' suffix — a numeric option refusing
non-digits.  Anything unrecognized fails soft to the plain string
option (REQ-016).  Pure."
  (let* ((name (or (gascity-formula-var-name var) ""))
         (default (gascity-formula-var-default var))
         (override (cdr (assoc name gascity-sling-var-readers))))
    (or (cdr (assq override gascity-sling-formula--reader-classes))
        (and (symbolp override)
             (ignore-errors
               (and (child-of-class-p override
                                     'gascity-sling-formula--var-option)
                    override)))
        (and (functionp override)
             'gascity-sling-formula--function-option)
        (and (gascity-formula--enum-choices var formula)
             'gascity-sling-formula--enum-option)
        (and (member default '("true" "false"))
             'gascity-sling-formula--bool-option)
        (and (or (equal name "context_path")
                 (string-suffix-p "_path" name))
             'gascity-sling-formula--file-option)
        (and (equal name "artifact_root")
             'gascity-sling-formula--directory-option)
        (and (string-suffix-p "_target" name)
             'gascity-sling-formula--agent-option)
        (and (or (and (gascity-formula--nonblank default)
                      (string-match-p "\\`[0-9]+\\'" default))
                 (string-prefix-p "max_" name)
                 (string-suffix-p "_iterations" name))
             'gascity-sling-formula--numeric-option)
        'gascity-sling-formula--string-option)))

(defun gascity-sling-formula--class-tag (class)
  "Return CLASS's type tag for the infix description, or nil (REQ-006).
The mockups' `[file]' / `[dir]' / `[agent]' / `[numeric]' markers: the
typed reader is visible in the menu line itself.  Enum, bool and
string carry no tag — their reads are the long-standing ones."
  (pcase class
    ('gascity-sling-formula--file-option "[file]")
    ('gascity-sling-formula--directory-option "[dir]")
    ('gascity-sling-formula--agent-option "[agent]")
    ('gascity-sling-formula--numeric-option "[numeric]")
    (_ nil)))

;;; ---- Pure children generation (REQ-004..009) -----------------

(defun gascity-sling-formula--var-description (var)
  "Return the infix description for VAR (self-documenting, REQ-007).
Carries the var's description and default; required vars are marked
\"(required)\" (REQ-008).  Absent fields degrade (REQ-016)."
  (concat (or (gascity-formula-var-name var) "var")
          (and (gascity-formula-var-required var) " (required)")
          (when-let* ((description (gascity-formula-var-description var)))
            (concat " — " description))
          (when-let* ((default (gascity-formula-var-default var))
                      ((not (string-empty-p default))))
            (concat " [default: " default "]"))))

(defun gascity-sling-formula--char-combos (chars)
  "Return two-character strings drawn from CHARS in positional order.
Positions pair as 1+2, 1+3, 2+3, … — the second stage of the
deterministic var-key assignment (REQ-D)."
  (let (combos)
    (cl-dotimes (i (length chars))
      (cl-do ((j (1+ i) (1+ j)))
          ((>= j (length chars)))
        (push (format "%c%c" (nth i chars) (nth j chars)) combos)))
    (nreverse combos)))

(defun gascity-sling-formula--var-key-natural (name used)
  "Return NAME's natural key candidate avoiding USED, or nil (REQ-006).
The two natural stages of the deterministic assignment: the name's
own first alphanumeric character — itself unbound and not the prefix
of a longer key already assigned — else the first two-letter
combination of the name's own characters (positionally: 1+2, 1+3,
2+3, …) whose first character is unbound (transient binds keys with
`kbd', so a combo under a bound first character is an
unrepresentable prefix chain).  Nil when neither exists: the caller
falls to the positional `<char><digit>' stage, and the How group
renders those vars grouped in the mockups' `…' overflow
\(`gascity-sling-formula--var-children').  Pure."
  (let* ((chars (seq-filter
                 (lambda (char)
                   (string-match-p "[[:alnum:]]" (string char)))
                 (append name nil)))
         (free-single
          (lambda (key)
            (and (not (member key used))
                 (not (seq-some
                       (lambda (other)
                         (and (> (length other) 1)
                              (string-prefix-p key other)))
                       used)))))
         (free-combo
          (lambda (key)
            (and (not (member (substring key 0 1) used))
                 (not (member key used))))))
    (or (seq-find free-single (and chars (list (string (car chars)))))
        (seq-find free-combo (gascity-sling-formula--char-combos chars)))))

(defun gascity-sling-formula--var-key (name used)
  "Return an unused transient key for NAME, avoiding USED (REQ-D).
Tries, in order: the name's own first alphanumeric character; an
unused two-letter combination drawn from the name's characters
\(positionally: 1+2, 1+3, 2+3, …); a positional key built from the
name's first usable character and an incrementing digit (`d1', `d2',
…).  Transient binds suffix keys with `kbd', so a multi-character key
is a prefix chain: a candidate's FIRST character must itself be
unbound — a combo like `re' under the statically bound `r' would be
an unrepresentable key sequence (founded in the TRAMP e2e pass) — and
a single-character candidate must not be the prefix of a key already
assigned to an earlier var.  Every candidate is checked against USED —
the reserved single-letter bindings plus the keys assigned to earlier
vars of the same formula — so uniqueness is by construction.  A name
with no alphanumeric character degrades to `v'-prefixed positional
keys.  Pure: the same NAME and USED always yield the same key."
  (or (gascity-sling-formula--var-key-natural name used)
      (let* ((chars (seq-filter
                     (lambda (char)
                       (string-match-p "[[:alnum:]]" (string char)))
                     (append name nil)))
             (prefix (or (seq-find (lambda (p) (not (member p used)))
                                   (append (mapcar #'string chars)
                                           '("v" "z" "k" "j" "h")))
                       "v")))
        (let ((n 1))
          (while (member (format "%s%d" prefix n) used)
            (setq n (1+ n)))
          (format "%s%d" prefix n)))))

(defun gascity-sling-formula--assign-var-keys (vars reserved)
  "Return one (KEY . NATURAL-P) per var of VARS, avoiding RESERVED.
The assignment loop behind `gascity-sling-formula--var-keys' — its
deterministic contract — with NATURAL-P marking a key drawn from the
name's own characters (`gascity-sling-formula--var-key-natural'); a
nil NATURAL-P marks the positional `<char><digit>' stage, whose vars
the How group renders in the mockups' grouped `…' overflow
\(REQ-006)."
  (let ((used (copy-sequence reserved))
        assigned)
    (dolist (var vars)
      (let* ((name (gascity-formula--sanitize
                    (or (gascity-formula-var-name var) "")))
             (key (gascity-sling-formula--var-key name used)))
        (push (cons key
                    (and (gascity-sling-formula--var-key-natural name used) t))
              assigned)
        (cl-pushnew key used :test #'equal)))
    (nreverse assigned)))

(defun gascity-sling-formula--var-keys (vars reserved)
  "Return one unique transient key per var in VARS, avoiding RESERVED.
RESERVED is the unified prefix's single-letter static bindings
\(`gascity-sling--reserved-keys'); the caller supplies it because this
module loads before the one that defines the prefix (F-2).  Keys are
assigned per formula, in declared var order, by
`gascity-sling-formula--var-key' — so the same var list against the
same reserved set always yields the same keys, and no key collides
with a static binding or an earlier var's key."
  (mapcar #'car (gascity-sling-formula--assign-var-keys vars reserved)))

(defun gascity-sling-formula--var-infix-spec (var key formula &optional scope)
  "Return the raw transient infix spec for VAR bound to KEY.
FORMULA supplies the methodology mapping enum resolution consults;
SCOPE (optional — data, never live transient state) the derived seeds
\(REQ-006).  The infix class follows `gascity-sling-formula--var-class'
and the description carries the typed reader's tag (REQ-006: the
mockups' `[file]'-style markers)."
  (let* ((name (gascity-formula-var-name var))
         (choices (gascity-formula--enum-choices var formula))
         (class (gascity-sling-formula--var-class var formula))
         (override (cdr (assoc name gascity-sling-var-readers)))
         (tag (gascity-sling-formula--class-tag class)))
    (apply
     #'list key
     (concat (gascity-sling-formula--var-description var)
             (and tag (concat "  " tag)))
     'gascity-sling-formula--set-var
     :class class
     :argument (format "--var %s=" name)
     :var-name name
     :var-description (gascity-formula-var-description var)
     :var-default (gascity-formula-var-default var)
     :var-required (gascity-formula-var-required var)
     :var-pattern (gascity-formula-var-pattern var)
     :var-choices choices
     :var-seed (gascity-sling-formula--var-seed var scope)
     (and (eq class 'gascity-sling-formula--function-option)
          (list :var-reader override)))))

(defun gascity-sling-formula--var-infix-assignments (formula reserved
                                                           &optional scope)
  "Return one (KEY INFIX-SPEC NATURAL-P) per var of FORMULA, or nil.
RESERVED is the statically bound letter list; SCOPE, when non-nil,
the menu's scope plist.  The shared workhorse of the flat infix list
\(`gascity-sling-formula--var-infixes') and the overflow-split group
\(`gascity-sling-formula--var-children'); NATURAL-P marks the natural
key stage, the vars the `…' overflow groups when the natural
candidates run out (REQ-006, mockup §4)."
  (let ((vars (and formula (gascity-formula-vars formula))))
    (when vars
      (let ((assigned (gascity-sling-formula--assign-var-keys vars reserved)))
        (cl-mapcar (lambda (var ass)
                     (list (car ass)
                           (gascity-sling-formula--var-infix-spec
                            var (car ass) formula scope)
                           (cdr ass)))
                   vars assigned)))))

(defun gascity-sling-formula--var-infixes (formula reserved &optional scope)
  "Return the raw transient infix specs for FORMULA's vars, or nil.
Pure: no transient state, no gc.  One infix per declared var (REQ-004);
keys avoid RESERVED (the unified prefix's static bindings); SCOPE
feeds the var seeds.  A var
whose natural candidates are exhausted renders through the `…'
overflow group of `gascity-sling-formula--var-children' (REQ-006).  A
nil FORMULA (no formula picked yet — the transient's initial setup)
degrades to no Variables section (REQ-016)."
  (when-let* ((assignments
              (gascity-sling-formula--var-infix-assignments
               formula reserved scope)))
    (mapcar (lambda (a) (nth 1 a)) assignments)))

(defun gascity-sling-formula--var-children (formula reserved &optional scope)
  "Return the raw \"Variables\" group spec for FORMULA, or nil.
RESERVED is inherited by the per-var key assignment; SCOPE (optional)
grows the per-var seeds (REQ-006: the `plans/<slug>/' artifact_root
seed from the work bead's title, the chosen target's rig for
`rig_name', the chosen target for `*_target' vars).  The group is
titled `How — <formula> vars' (mockup §4) so a re-pick is
visible in the section heading.  A formula without vars renders no
How section (REQ-004).
A var set that exhausts the natural key candidates — the deterministic
assignment falls to its positional `<char><digit>' stage — renders
those vars grouped under a `…  (N more vars)' subgroup instead of
inline rows: the mockups' grouped-overflow fallback (REQ-006).  Every
var keeps its deterministic key and stays settable; only the placement
groups."
  (when-let* ((assignments
              (gascity-sling-formula--var-infix-assignments
               formula reserved scope)))
    (let ((main (delq nil (mapcar (lambda (a) (and (nth 2 a) (nth 1 a)))
                                  assignments)))
          (overflow (delq nil (mapcar (lambda (a) (and (null (nth 2 a))
                                                       (nth 1 a)))
                                      assignments))))
      (if (null overflow)
          (apply #'vector
                 (format "How — %s vars"
                         (or (gascity-formula-name formula) "formula"))
                 main)
        (apply #'vector
               (format "How — %s vars"
                       (or (gascity-formula-name formula) "formula"))
               :class 'transient-subgroups
               (list (apply #'vector main)
                     (apply #'vector
                            (format "…  (%d more vars)" (length overflow))
                            overflow)))))))

;;; ---- Scope seeds and the completion workdir (REQ-006) --------

(defconst gascity-sling--bead-id-regexp
  "\\`[a-zA-Z][a-zA-Z0-9._-]*-[0-9a-z]+\\(\\.[0-9]+\\)*\\'"
  "Match a whole bead id with its optional numeric child suffixes.
The shape is PREFIX-HASH: this is beads.el's `beads-issue-id-regexp',
anchored;
HASH is lowercase base-36 and PREFIX is letters, digits, dots,
underscores or hyphens.  The artifact-root slug never derives from
the bare id — it names nothing a human would recognize under
`plans/' (REQ-006) — so an id-shaped work waits for its title or
falls back further.")

(defun gascity-sling--slug (text)
  "Return TEXT's repo-practice slug (REQ-006).
Downcased, every non-alphanumeric run collapsed to one `-' (\"Dashboard
v3: cockpit + views\" → \"dashboard-v3-cockpit-views\"), edge dashes
trimmed.  A nil or all-symbol TEXT slugs to the empty string."
  (string-trim (replace-regexp-in-string
                "[^[:alnum:]]+" "-"
                (downcase (or text "")))
               "-" "-"))

(defun gascity-sling--title-slug (work &optional formula title)
  "Return the `artifact_root' seed of WORK: a `plans/<slug>/' path (REQ-006).
The slug comes from the work BEAD's TITLE — never the bare bead id,
which names nothing a human would recognize under plans/ — falling
back to freeform task text, then the FORMULA name; nothing derivable
yields nil and the var keeps its declared default (REQ-016 fail-soft).
Downcased, non-alphanumeric runs collapse to one `-' (repo practice:
\"Dashboard v3: …\" → `plans/dashboard-v3/').  Pure: no gc, no store,
no transient state."
  (let ((slug (seq-find (lambda (s) (and s (not (string-empty-p s))))
                        (list (gascity-sling--slug title)
                              (and (gascity-formula--nonblank work)
                                   (not (string-match-p
                                         gascity-sling--bead-id-regexp work))
                                   (gascity-sling--slug work))
                              (gascity-sling--slug formula)))))
    (and slug (format "plans/%s/" slug))))

(defun gascity-sling-formula--target-rig (&optional target)
  "Return the rig name of the sling TARGET, or nil (REQ-005/006).
A qualified agent name carries its rig — the slash prefix
\(\"hello-world/gc.implementation-worker\" → \"hello-world\"), the same
scope classification the roster uses.  Anything else — a bare session
name, a nil target — yields nil, fail-soft."
  (and (stringp target)
       (string-match "\\`\\([^/[:space:]]+\\)/[^/]+\\'" target)
       (match-string 1 target)))

(defun gascity-sling-formula--rig-workdir (&optional scope)
  "Return SCOPE's completion workdir: the target rig's repo (REQ-006).
The workdir is the repo the chosen target agent works in:
the target's rig when it names one (`gascity-sling-formula--target-rig'),
else the work bead's owning rig (the id-prefix routing the bd verbs
use), each resolved I/O-free through the rig memo
\(`gascity-beads--rig-path' / `gascity-beads--bead-path-cached') and
re-prefixed for a remote city.  Neither resolves — no target, a
city-scoped target, a cold rig memo — and completion degrades to the
city directory the transient was entered from
\(`gascity-sling--city-dir'): it stays on the entered city, never a
foreign buffer's directory (REQ-016).  The memo reads run pinned to
that city, so the memo key is the entered city's host."
  (let* ((city (gascity-sling--city-dir scope))
         (default-directory city)
         (scope (or scope (ignore-errors (transient-scope))))
         (target (and scope (plist-get scope :target)))
         (work (and scope (or (plist-get scope :work)
                              (plist-get scope :arg)))))
    (file-name-as-directory
     (or (gascity-beads--rig-path
          (gascity-sling-formula--target-rig target))
         (and work (gascity-beads--bead-path-cached work))
         city))))

(defun gascity-sling-formula--agent-candidates ()
  "Return the agent names agent vars complete over, or nil when cold.
The sling city's session roster — qualified agent names — read through
the store pinned to the city (`gascity-store-peek': the last good
payload, never a blocking read, with a background refresh scheduled
when stale so the next prompt sees current data — §8.5/D9).  Pool
sessions sharing one agent collapse to one candidate; a cold store
yields nil and free entry still answers (REQ-016)."
  (let* ((default-directory (gascity-sling--city-dir))
         (payload (gascity-store-peek '("session" "list")))
         (sessions (append (alist-get 'sessions payload) nil)))
    (delete-dups
     (delq nil
           (mapcar (lambda (session)
                     (let ((name (alist-get 'agent_name session)))
                       (and (stringp name) name)))
                   sessions)))))

(defun gascity-sling-formula--var-seed (var scope)
  "Return VAR's scope-derived initial value, or nil (REQ-006).
The convention defaults the How group shows: `artifact_root' seeds
`plans/<slug>/' from the work bead's title
\(`gascity-sling--title-slug'), `rig_name' the chosen target's rig,
and any `*_target' var the chosen target itself when it is a
qualified agent name.  A target set with `T'/`:target' wins, and a
derived Who default (`:derived-target', injected by the menu's setup
from `gascity-sling--derived-target') answers in its place, so the
var seed names what `s' would actually launch instead of the declared
default (WI-11 finding F5).  A seed overrides the var's declared
default — the convention IS the default — and stays editable like
any value; nothing derivable leaves the var to its declared default
\(REQ-016 fail-soft).  Pure: SCOPE is data, no reads."
  (when scope
    (let* ((name (or (gascity-formula-var-name var) ""))
           (target (or (plist-get scope :target)
                       (plist-get scope :derived-target)))
           (work (or (plist-get scope :work) (plist-get scope :arg)))
           (formula (plist-get scope :formula))
           (title (plist-get scope :work-title)))
      (cond
       ((equal name "artifact_root")
        (gascity-sling--title-slug work formula title))
       ((equal name "rig_name")
        (gascity-sling-formula--target-rig target))
       ((and (string-suffix-p "_target" name)
             (gascity-sling-formula--target-rig target))
        target)))))

(defun gascity-sling-formula--work-title-at-point ()
  "Return the title of the work at point, or nil (REQ-006).
A convoy row carries its typed `gascity-convoy' whose title is the
work bead's title — the artifact_root seed's source; a bare bead-id
string names nothing readable without a store read (forbidden on the
setup path), so it yields nil and the seed falls back fail-soft
\(REQ-016)."
  (let ((obj (gascity-object-at-point)))
    (and (gascity-convoy-p obj) (gascity-convoy-title obj))))

;;; ---- Scope helpers -------------------------------------------

(defun gascity-sling-formula--bead-or-convoy-at-point ()
  "Return the bead or convoy id at point, or nil.
A bead reference is the bead-id string at point; a convoy list row
carries the typed `gascity-convoy' whose id is the bead id to route
\(REQ-013's pre-seeding)."
  (let ((obj (gascity-object-at-point)))
    (cond ((stringp obj) (and (not (string-empty-p obj)) obj))
          ((gascity-convoy-p obj) (gascity-convoy-id obj))
          (t nil))))

(defun gascity-sling-formula--scope-recipe ()
  "Return the scoped formula's cached recipe, or nil when none chosen.
Through `gascity-formula-recipe-cached' (defaults only); the preview
reads fresh instead."
  (when-let* ((name (plist-get (transient-scope) :formula)))
    (gascity-formula-recipe-cached name)))

(defun gascity-sling-formula--current-values ()
  "Return the currently set formula var values as a (NAME . VALUE) alist.
Parses the transient's `--var name=value' args, keeping only values of
the infixes generated from the scoped formula — a value set for a
formula the user has since re-picked never leaks into the next
dispatch.  An empty entered value counts as unset, which is dispatch's
required-var business (REQ-008)."
  (let* ((recipe (gascity-sling-formula--scope-recipe))
         (names (mapcar #'gascity-formula-var-name
                        (or (and recipe (gascity-formula-vars recipe)) '()))))
    (delq nil
          (mapcar
           (lambda (arg)
             (and (string-prefix-p "--var " arg)
                  (let* ((kv (substring arg (length "--var ")))
                         (split (string-search "=" kv)))
                    (and split
                         (member (substring kv 0 split) names)
                         (let ((value (substring kv (1+ split))))
                           (and (gascity-formula--nonblank value)
                                (cons (substring kv 0 split) value)))))))
           (transient-args 'gascity-sling-dispatch)))))

;;; ---- Picker, dispatch, preview -------------------------------

(defun gascity-sling-formula--read-formula ()
  "Read a formula name from every formula the city can run (REQ-001, S-1).
The candidates are `gascity-formula-choices': the catalog, annotated
with each formula's `description', plus the formulas only `gc formula
list' has (the city's own), annotated `(city)'.  The reads go through
the store (`gascity-formula-choices-wait'); nothing to offer is a clear
`user-error' (REQ-002)."
  (let* ((choices (gascity-formula-choices-wait))
         (completion-extra-properties
          (list :annotation-function
                (lambda (candidate)
                  (when-let* ((note (cdr (assoc candidate choices))))
                    (concat "  " note))))))
    (completing-read "Formula: " (mapcar #'car choices)
                     nil t nil 'gascity-sling-formula-picker-history)))

(defun gascity-sling-formula--command (recipe target arg values &optional dry-run)
  "Validate RECIPE's VALUES against TARGET and ARG; return the command.
The result is a `gascity-command-sling' to act on.  The one command
builder behind the dispatch and the full preview
buffer's routing plan (sling-command WI-7): exactly the command
`gascity-sling-formula--dispatch' starts, with `--dry-run' when
DRY-RUN is non-nil.  Validation runs first — a missing required var
refuses before any gc invocation (REQ-008), and a convoy-requiring
formula with no bead or convoy at point refuses too (REQ-013)."
  (gascity-formula--validate-values recipe values)
  (let* ((name (gascity-formula-name recipe))
         (varlist (mapcar (lambda (kv) (format "%s=%s" (car kv) (cdr kv)))
                          values))
         (command (if (gascity-formula--needs-convoy recipe)
                      (if (gascity-formula--blank arg)
                          (user-error
                           "Formula %s requires a target convoy — point at a bead or convoy and try again"
                           name)
                        (apply #'gascity-command-sling
                               (append
                                (when (gascity-formula--nonblank target)
                                  (list :target target))
                                (list :arg arg :on name)
                                (when varlist (list :var varlist))
                                (when dry-run (list :dry-run t)))))
                    (apply #'gascity-command-sling
                           (append
                            (when (gascity-formula--nonblank target)
                              (list :target target))
                            (list :arg name :formula t)
                            (when varlist (list :var varlist))
                            (when dry-run (list :dry-run t)))))))
    command))

(defun gascity-sling-formula--dispatch (recipe target arg values &optional dry-run)
  "Validate and sling RECIPE with VALUES; return the command acted on.
TARGET is the session target, ARG the bead/convoy pre-seeded at point.
Validation and the command shape live in
`gascity-sling-formula--command'.  On success the sling is started
through `gascity-command-act-async' (D9) and the originating view
refreshes once gc answers, and the launch handler echoes the created
workflow root with the momentary `F' follow jump
\(`gascity-sling--launch-handler', REQ-009).
With DRY-RUN non-nil the same command carries `--dry-run' and gc's
routing plan is shown instead of acting."
  (let* ((name (gascity-formula-name recipe))
         (command (gascity-sling-formula--command recipe target arg values dry-run)))
    (if dry-run
        (gascity-sling--show-plan command)
      ;; Started asynchronously (D9): `gc sling --json' reports its
      ;; dispatch in the echo area and refreshes the view when it lands;
      ;; the formula path alone attaches the launch handler — the echo
      ;; of the created workflow root and the momentary `F' follow jump
      ;; (REQ-009).  The plain route keeps the plain act and echo.
      (oset command json t)
      (gascity-command-act-async command
        :on-success (gascity-sling--launch-handler command name arg)))
    command))

(defun gascity-sling-formula--show-recipe (name values)
  "Re-run `gc formula show NAME' with VALUES and render the recipe.
VALUES go out as repeated `--var k=v' flags so gc substitutes them
server-side (REQ-012 as revised by plan-review F-1).  A gc failure
surfaces as a clean `user-error'."
  (let* ((varargs (mapcar (lambda (kv) (format "%s=%s" (car kv) (cdr kv)))
                          values))
         (payload (condition-case err
                      (apply #'gascity-command-formula-show! :name name
                             (when varargs (list :var varargs)))
                    (gascity-command-error
                     (user-error "GC formula show failed: %s"
                                 (gascity-error-detail err))))))
    (gascity-sling-formula--render-recipe
     (gascity-domain-decode 'gascity-formula payload))))

(defun gascity-sling-formula--format-step (step)
  "Return the preview line for one raw STEP alist.
TITLE and the `gc.kind' step metadata are gc's own; gascity renders,
never re-substitutes (REQ-012)."
  (let* ((id (or (alist-get 'id step) ""))
         (title (or (alist-get 'title step) id))
         (kind (alist-get 'gc.kind (alist-get 'metadata step))))
    (format "  %s%s%s\n"
            title
            (if (and id (not (equal id title))) (format " [%s]" id) "")
            (if kind (format " (%s)" kind) ""))))

(defun gascity-sling-formula--render-recipe (recipe)
  "Render RECIPE into a host-qualified read-only view buffer (REQ-012).
Steps, dependency edges and substituted titles come straight from gc's
compiled recipe.  The buffer goes through
`gascity-view-get-buffer-create' like every other view, so a local and
a remote preview coexist (REQ-014)."
  (let* ((name (or (gascity-formula-name recipe) "formula"))
         (buf (gascity-view-get-buffer-create (format "*gc-formula: %s*" name))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Formula: " name "\n")
        (when-let* ((description (gascity-formula-description recipe)))
          (insert "\n" description "\n"))
        (insert "\nSteps:\n")
        (if (gascity-formula-steps recipe)
            (dolist (step (gascity-formula-steps recipe))
              (insert (gascity-sling-formula--format-step step)))
          (insert "  (no steps)\n"))
        (insert "\nDependencies:\n")
        (if (gascity-formula-deps recipe)
            (dolist (dep (gascity-formula-deps recipe))
              (insert (format "  %s depends on %s\n"
                              (or (alist-get 'step_id dep) "?")
                              (or (alist-get 'depends_on_id dep) "?"))))
          (insert "  (no dependencies)\n"))
        (goto-char (point-min)))
      (view-mode 1))
    (pop-to-buffer buf)))

(provide 'gascity-formula)

;;; gascity-formula.el ends here
