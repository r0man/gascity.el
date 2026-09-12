;;; gascity-formula.el --- Formula metadata for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The formula module for the formula-aware sling UI (plans/
;; formula-sling-ui/build/implementation-plan.md).  gascity never
;; reimplements gc logic — this module reads, decodes, caches and checks
;; what `gc formula' reports, and owns the transient that slings a formula
;; with generated variable infixes plus the recipe preview backed by a
;; fresh server-side substituted read.
;;
;; Everything here reads through the single gc call site: `gascity-formula-
;; catalog' and `gascity-formula-recipe' call the generated bang executors
;; `gascity-command-formula-catalog!' / `gascity-command-formula-show!'
;; (`lisp/gascity-types.el'), which run `gc' where `default-directory'
;; points — the path every view buffer pins.  Over TRAMP that is the
;; remote host's gc, transparently.
;;
;; Caches (plan decision D3): the catalog and the per-formula compiled
;; recipes are memoized for the Emacs session, keyed by the city identity
;; `(concat (file-remote-p dir) dir)' — a local city and
;; /ssh:localhost:/home/roman/bright-lights never share an entry.  Nothing
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
;; History (REQ-010/011): `gascity-formula--history-var' returns an
;; ordinary minibuffer history variable per (formula, var), named
;; `gascity-formula-history-<formula>-<var>'.  The transient's generated
;; infixes read with it as `minibuffer-history-variable', so savehist
;; tracks it automatically — no persistence machinery of its own.
;;
;; The transient itself (`gascity-sling-formula-dispatch') keeps a scope
;; plist `(formula target arg)' set at entry (`gascity-sling-formula', or
;; the `-f' entry of `gascity-sling-dispatch'): the bead or convoy at
;; point seeds `arg', `gascity-action--read-session' seeds `target', and
;; the picker seeds `formula'.  Its Variables section is generated per
;; setup from the chosen formula's `vars[]' — enum vars are fixed-choice
;; options, "true"/"false"-defaulted vars are toggles, everything else is
;; a string option — and the dispatch suffix validates client-side before
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

;; Action verbs are wired across files: this module is loaded before
;; `gascity-action' (which carries the sling entry and runners) and
;; before `gascity-section' (the at-point ladder).
(declare-function gascity-action--read-session "gascity-action")
(declare-function gascity-command-act "gascity-action")
(declare-function gascity--refresh-current-view "gascity-action")
(declare-function gascity-object-at-point "gascity-section")
(declare-function gascity-view-get-buffer-create "gascity-context")

;;; ============================================================
;;; Caches (plan D3, REQ-003/REQ-014)
;;; ============================================================

(defvar gascity-formula-catalog-cache nil
  "Per-city formula catalog memo.
An alist of (CITY-KEY . ENTRIES), ENTRIES a list of
`gascity-formula-catalog-entry'.  CITY-KEY is
`gascity-formula--city-key''s remote-qualified directory, so a local
and a remote city never cross-contaminate.  Session-lifetime; cleared
per city by `gascity-formula-invalidate'.")

(defvar gascity-formula-recipe-cache nil
  "Per-(city, formula) compiled-recipe memo.
An alist of ((CITY-KEY . FORMULA-NAME) . RECIPE), RECIPE a
`gascity-formula'.  Session-lifetime; cleared per city by
`gascity-formula-invalidate'.")

(defun gascity-formula--city-key (&optional dir)
  "Return the cache identity of DIR's city.
DIR defaults to `default-directory'.  The remote prefix is prepended so
a local city and the same city over TRAMP never share a cache entry."
  (let ((dir (expand-file-name (or dir default-directory))))
    (concat (file-remote-p dir) dir)))

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
broken catalog) and memoizes under `gascity-formula--city-key'.  Only
user-initiated code — transient setup and previews — may call this;
nothing on a redisplay path re-reads gc."
  (let ((key (gascity-formula--city-key)))
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
Cache entries are keyed (city-key . NAME) under
`gascity-formula-recipe-cache'; a miss reads through
`gascity-formula-recipe' and memoizes.  The cached read carries no
`--var' substitutions — defaults only; the recipe preview re-runs the
uncached `gascity-command-formula-show!' when it wants current values
applied server-side."
  (let ((key (cons (gascity-formula--city-key) name)))
    (or (cdr (assoc key gascity-formula-recipe-cache))
        (let ((recipe (gascity-formula-recipe name)))
          (push (cons key recipe) gascity-formula-recipe-cache)
          recipe))))

(defun gascity-formula-invalidate ()
  "Forget this city's cached formula catalog and recipes.
Clears the entries keyed by `gascity-formula--city-key' from both
caches, leaving other cities' entries untouched.  Called by an explicit
refresh binding and by re-picking \"refresh catalog\" in the picker."
  (let ((key (gascity-formula--city-key)))
    (setq gascity-formula-catalog-cache
          (seq-filter (lambda (entry) (not (equal (car entry) key)))
                      gascity-formula-catalog-cache))
    (setq gascity-formula-recipe-cache
          (seq-filter (lambda (entry) (not (equal (caar entry) key)))
                      gascity-formula-recipe-cache)))
  nil)

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
(`gascity-formula--enum-metadata-keys') consults FORMULA's
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
;;; Validation (REQ-008/009)
;;; ============================================================

(defun gascity-formula--validate-values (formula values)
  "Check VALUES against FORMULA's declared vars, before any gc call.
VALUES is an alist of (VAR-NAME . VALUE); a var absent from it counts
as empty.  A missing required var signals `user-error' naming every
missing var; a value that fails its var's `pattern' signals
`user-error' naming the var and the pattern.  Nothing here runs gc —
the point is to fail fast, client-side (REQ-008/009)."
  (let ((vars (or (gascity-formula-vars formula) '()))
        (missing nil))
    (dolist (var vars)
      (when (and (gascity-formula-var-required var)
                 (gascity-formula--blank
                  (cdr (assoc (gascity-formula-var-name var) values))))
        (push (gascity-formula-var-name var) missing)))
    (when missing
      (user-error "Missing required formula vars: %s"
                  (mapconcat #'identity (nreverse missing) ", ")))
    (dolist (var vars)
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
;;; Formula sling transient (REQ-001, REQ-004..009, REQ-012/013/015)
;;; ============================================================

;; The formula-aware sling: scope `(formula target arg)' set at entry,
;; a catalog picker, generated per-var infixes, a dispatch suffix that
;; validates before any gc call, and a recipe preview backed by a fresh
;; server-side substituted read.  The non-formula sling transient
;; (`gascity-sling-dispatch') keeps its bindings and enters here via
;; its `-f' toggle.

(defvar gascity-sling-formula-picker-history nil
  "Minibuffer history of `gascity-sling-formula--read-formula' picks.
An ordinary history variable: savehist tracks it like any other.")

(defconst gascity-sling-formula--reserved-keys '("p" "s" "r" "q")
  "Static suffix keys of `gascity-sling-formula-dispatch' the generated
variable infix keys must avoid.")

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
    :documentation "Declared choice list, when the var is an enum."))
  :abstract t
  :documentation "Base class of the generated formula-var infixes.
One infix per declared var, class per shape (REQ-004..007): an enum
restricted to its declared choices, a `true'/`false'-defaulted toggle,
or a plain string option; absent fields degrade (REQ-016).")

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
var) history (REQ-010), and `pattern' validation on entry (REQ-009).")

(cl-defmethod transient-prompt ((obj gascity-sling-formula--var-option))
  "Return OBJ's var description as the read prompt (REQ-007).
A var without a description degrades to a generic prompt (REQ-016)."
  (format "%s: "
          (or (oref obj var-description)
              (format "Formula var %s" (oref obj var-name)))))

(cl-defmethod transient-init-value ((obj gascity-sling-formula--var-option))
  "Seed OBJ's value from the transient value, else the var's default.
`cl-call-next-method' extracts a value the user already set in this
transient (it survives the re-setup a formula re-pick performs); an
unset var falls back to its declared default (REQ-007)."
  (cl-call-next-method)
  (when (null (oref obj value))
    (oset obj value (oref obj var-default))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--enum-option))
  "Read one of the var's declared choices only (REQ-005).
Illegal values are unrepresentable; history is per (formula, var)."
  (completing-read (transient-prompt obj)
                   (oref obj var-choices) nil t
                   (or (oref obj value) (oref obj var-default))
                   (gascity-sling-formula--history obj)))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--bool-option))
  "Cycle the boolean var true -> false -> true (REQ-006).
Nothing is read: illegal values are unrepresentable by construction."
  (pcase (oref obj value)
    ("true" "false")
    ("false" "true")
    (_ (or (oref obj var-default) "true"))))

(cl-defmethod transient-infix-read ((obj gascity-sling-formula--string-option))
  "Read the string var, validating its `pattern' on entry (REQ-009).
An empty entry unsets the var (transient's own empty-value rule); the
required check stays with dispatch.  History is per (formula, var)."
  (let ((value (read-from-minibuffer
                (transient-prompt obj)
                (or (oref obj value) (oref obj var-default))
                nil nil (gascity-sling-formula--history obj))))
    (when (and (stringp value) (not (string-empty-p value)))
      (gascity-sling-formula--check-pattern
       (oref obj var-name) (oref obj var-pattern) value)
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

(defun gascity-sling-formula--var-keys (vars)
  "Return one unique transient key per var in VARS.
Prefers the var name's own letters (`drain_policy' -> \"d\"), then
digits, then the sanitized name; the static suffix keys are avoided so
no two suffixes of the transient collide."
  (let ((used (copy-sequence gascity-sling-formula--reserved-keys))
        keys)
    (dolist (var vars)
      (let ((key (gascity-sling-formula--var-key
                  (gascity-formula--sanitize
                   (or (gascity-formula-var-name var) ""))
                  used)))
        (push key keys)
        (cl-pushnew key used :test #'equal)))
    (nreverse keys)))

(defun gascity-sling-formula--var-key (name used)
  "Return an unused transient key for NAME, avoiding USED.
Falls back from NAME's own alphanumeric characters to digits, then to
NAME itself — a collision only over ten single-character keys is
practically unreachable, but never breaks the transient."
  (or (when-let* ((char (seq-find (lambda (char)
                              (and (not (member (string char) used))
                                   (string-match-p "[[:alnum:]]" (string char))))
                            (append name nil))))
        (string char))
      (seq-find (lambda (key) (not (member key used)))
                '("1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))
      name))

(defun gascity-sling-formula--var-infix-spec (var key formula)
  "Return the raw transient infix spec for VAR bound to KEY.
FORMULA supplies the methodology mapping enum resolution consults.  The
infix class follows the var's shape: an enum becomes a fixed-choices
option (illegal values unrepresentable), a `true'/`false' default a
toggle, everything else a string option (REQ-005..007)."
  (let* ((name (gascity-formula-var-name var))
         (choices (gascity-formula--enum-choices var formula))
         (class (cond (choices 'gascity-sling-formula--enum-option)
                      ((member (gascity-formula-var-default var)
                               '("true" "false"))
                       'gascity-sling-formula--bool-option)
                      (t 'gascity-sling-formula--string-option))))
    (list key
          (gascity-sling-formula--var-description var)
          'gascity-sling-formula--set-var
          :class class
          :argument (format "--var %s=" name)
          :var-name name
          :var-description (gascity-formula-var-description var)
          :var-default (gascity-formula-var-default var)
          :var-required (gascity-formula-var-required var)
          :var-pattern (gascity-formula-var-pattern var)
          :var-choices choices)))

(defun gascity-sling-formula--var-infixes (formula)
  "Return the raw transient infix specs for FORMULA's vars, or nil.
Pure: no transient state, no gc.  One infix per declared var — the
count `gascity-test-formula-var-infixes-match-vars' pins (REQ-004)."
  (let ((vars (gascity-formula-vars formula)))
    (when vars
      (let ((keys (gascity-sling-formula--var-keys vars)))
        (cl-mapcar (lambda (var key)
                     (gascity-sling-formula--var-infix-spec var key formula))
                   vars keys)))))

(defun gascity-sling-formula--var-children (formula)
  "Return the raw \"Variables\" group spec for FORMULA, or nil.
A formula without vars renders no Variables section (REQ-004)."
  (when-let* ((infixes (gascity-sling-formula--var-infixes formula)))
    (apply #'vector "Variables" infixes)))

;;; ---- Scope helpers -------------------------------------------

(defun gascity-sling-formula--bead-or-convoy-at-point ()
  "Return the bead or convoy id at point, or nil.
A bead reference is the bead-id string at point; a convoy list row
carries the typed `gascity-convoy' whose id is the bead id to route
(REQ-013's pre-seeding)."
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
                        (or (gascity-formula-vars recipe) '()))))
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
           (transient-args 'gascity-sling-formula-dispatch)))))

;;; ---- Picker, dispatch, preview -------------------------------

(defun gascity-sling-formula--read-formula ()
  "Read a formula name from the cached catalog (REQ-001).
Each candidate is annotated with the formula's `description' via the
completion `:annotation-function'.  An empty or unreadable catalog is
`gascity-formula-catalog''s clear `user-error' (REQ-002)."
  (let ((entries (gascity-formula-catalog-cached)))
    (let ((completion-extra-properties
           (list :annotation-function
                 (lambda (candidate)
                   (when-let* ((entry (seq-find
                                       (lambda (e)
                                         (equal
                                          (gascity-formula-catalog-entry-name e)
                                          candidate))
                                       entries)))
                     (concat "  "
                             (or (gascity-formula-catalog-entry-description entry)
                                 "")))))))
      (completing-read "Formula: "
                       (mapcar #'gascity-formula-catalog-entry-name entries)
                       nil t nil 'gascity-sling-formula-picker-history))))

(transient-define-suffix gascity-sling-formula-pick ()
  "Pick a formula from the catalog; rebuild the Variables section (REQ-004).
The previously set infix values are carried into the re-setup, so a
variable the two formulas share keeps its value."
  (interactive)
  (let ((name (gascity-sling-formula--read-formula)))
    (transient-setup 'gascity-sling-formula-dispatch nil nil
                     :scope (plist-put (copy-sequence (transient-scope))
                                       :formula name)
                     :value (transient-args 'gascity-sling-formula-dispatch))))

(transient-define-suffix gascity-sling-formula-run ()
  "Sling the chosen formula with the collected var values (REQ-013).
Validation runs first: a missing required var refuses with no gc call
(REQ-008).  The shape follows `gascity-formula--needs-convoy' —
targetless `--formula', or `--on' pre-seeded from the bead or convoy at
point.  Acts and refreshes the originating view."
  (interactive)
  (let ((scope (transient-scope)))
    (unless (plist-get scope :formula)
      (user-error "No formula chosen — pick one first (p)"))
    (gascity-sling-formula--dispatch
     (gascity-sling-formula--scope-recipe)
     (plist-get scope :target)
     (plist-get scope :arg)
     (gascity-sling-formula--current-values))))

(defun gascity-sling-formula--dispatch (recipe target arg values)
  "Validate and sling RECIPE with VALUES; return the command acted on.
TARGET is the session target, ARG the bead/convoy pre-seeded at point.
Validation runs first — a missing required var refuses before any gc
invocation (REQ-008), and a convoy-requiring formula with no bead or
convoy at point refuses too (REQ-013).  On success the sling runs
through `gascity-command-act' and the originating view refreshes."
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
                                (when varlist (list :var varlist)))))
                    (apply #'gascity-command-sling
                           (append
                            (when (gascity-formula--nonblank target)
                              (list :target target))
                            (list :arg name :formula t)
                            (when varlist (list :var varlist)))))))
    (gascity-command-act command)
    (gascity--refresh-current-view)
    command))

(transient-define-suffix gascity-sling-formula-preview ()
  "Preview the recipe with the current var values (REQ-012, F-1).
Re-runs `gc formula show' with the currently-set values so gc
substitutes server-side — never a client-side `{{var}}' substitution.
The menu stays open."
  :transient t
  (interactive)
  (let ((name (plist-get (transient-scope) :formula)))
    (unless name
      (user-error "No formula chosen — pick one first (p)"))
    (gascity-sling-formula--show-recipe
     name (gascity-sling-formula--current-values))))

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
                     (user-error "gc formula show failed: %s"
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

;;; ---- The prefix -----------------------------------------------

(defun gascity-sling-formula--scope-info (scope)
  "Return the raw info spec describing SCOPE for the transient header."
  (list :info (format "Formula: %s · Arg: %s · Target: %s"
                      (or (plist-get scope :formula) "(none — pick one)")
                      (or (plist-get scope :arg) "(none — point at a bead or convoy)")
                      (or (plist-get scope :target) "(none)"))))

(defun gascity-sling-formula--static-children (scope)
  "Return the raw \"Formula\" column: the SCOPE info line and actions."
  (list
   (apply #'vector "Formula"
          (list (gascity-sling-formula--scope-info scope))
          '("-f" "Pick formula…" gascity-sling-formula-pick)
          '("s" "Sling…" gascity-sling-formula-run)
          '("r" "Preview recipe…" gascity-sling-formula-preview)
          '("q" "Quit" transient-quit-one))))

(defun gascity-sling-formula--setup-children (_children)
  "Generate `gascity-sling-formula-dispatch''s layout per setup.
The static actions are constant; the scope info line and the scoped
formula's Variables section are generated fresh — a different formula
re-runs `transient-setup' and lands here (REQ-004)."
  (let* ((scope (transient-scope))
         (name (plist-get scope :formula))
         (recipe (and name (gascity-formula-recipe-cached name))))
    (transient-parse-suffixes
     'gascity-sling-formula-dispatch
     (append (gascity-sling-formula--static-children scope)
             (when-let* ((group (gascity-sling-formula--var-children recipe)))
               (list group))))))

;;;###autoload (autoload 'gascity-sling-formula-dispatch "gascity-formula" nil t)
(transient-define-prefix gascity-sling-formula-dispatch ()
  "Sling a formula with generated variable infixes (DESIGN §5.2, formula flow).
The scope plist `(formula target arg)' is set at entry:
`gascity-sling-formula' seeds arg from the bead or convoy at point and
reads the target once.  The Variables section is generated from the
chosen formula's `vars[]'; dispatch validates client-side first and
picks the sling shape `gascity-formula--needs-convoy' detects."
  [ :class transient-columns
    :setup-children gascity-sling-formula--setup-children ])

;;;###autoload
(defun gascity-sling-formula ()
  "Open the formula-aware sling transient for this city.
The bead or convoy at point seeds the targeted arg (REQ-013) and the
sling target is read up front.  Reached directly and as the `-f' entry
of `gascity-sling-dispatch' (REQ-015)."
  (interactive)
  (let* ((arg (gascity-sling-formula--bead-or-convoy-at-point))
         (target (gascity-action--read-session "Sling to target: ")))
    (transient-setup 'gascity-sling-formula-dispatch nil nil
                     :scope (list :formula nil :target target :arg arg))))

(provide 'gascity-formula)

;;; gascity-formula.el ends here
