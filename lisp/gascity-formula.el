;;; gascity-formula.el --- Formula metadata for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The formula-metadata module for the formula-aware sling UI (plans/
;; formula-sling-ui/build/implementation-plan.md, Phase 2).  gascity never
;; reimplements gc logic — this module only reads, decodes, caches and
;; checks what `gc formula' reports; the transient and recipe preview that
;; consume it arrive in the next work item.
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
;; `gascity-formula-history-<formula>-<var>'.  Because the infixes use it
;; as `minibuffer-history-variable', savehist tracks it automatically —
;; no persistence machinery of its own.

;;; Code:

(require 'cl-lib)
(require 'gascity-error)
(require 'gascity-domain)   ; typed payload classes + decode
(require 'gascity-types)    ; formula-catalog/formula-show bang executors

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

(provide 'gascity-formula)

;;; gascity-formula.el ends here
