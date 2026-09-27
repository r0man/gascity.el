;;; gascity-sling-test.el --- Sling picker union, menu state and the redesign suite -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The sling command's own suite.  Two generations live here side by
;; side because the sling redesign (plans/sling-command/) lands as
;; parallel work items while this suite (WI-10, REQ-013) is written
;; against the redesign's specified behavior:
;;
;; - The S-1/S-2 regressions (picker union, preview keeps the menu)
;;   exercise retained plumbing and hold under both layouts; their
;;   layout-coupled halves (the old `p' preview, the `:arg' scope key)
;;   are ported to the redesign (`P' full preview, `A'/`T' pickers,
;;   scope `:work') and skip until the redesigned layout is loaded
;;   (`gascity-test-sling-redesign-p').
;; - The new tests pin the redesign's plan-specified contracts: shape
;;   inference, the header sentence, typed-var heuristics, the Who
;;   default derivation, the bl-bdj trap and cross-store warnings,
;;   the follow offer, the live footer and the reserved-key set.
;;
;; Everything stubs the gc boundary (`gascity-test-with-store-stubs',
;; `cl-letf' on the reader functions) so the suite stays offline and
;; fast.  Where the plan leaves an implementation name unpinned (the
;; header renderer, the `A' work-picker suffix), the tests assert
;; through pinned surfaces (`gascity-sling--children-specs', the
;; store boundary) instead; the assumptions are recorded in the WI-10
;; implementation summary's Remaining Risks.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

;; Redesign APIs (plans/sling-command WI-1..WI-9).  These exist only
;; once the redesign lands; the tests that use them skip otherwise.
(declare-function gascity-sling--shape "gascity-formula")
(declare-function gascity-sling--binding-targets-p "gascity-formula")
(declare-function gascity-sling--v2-trap-p "gascity-formula")
(declare-function gascity-sling--cross-store-p "gascity-formula")
(declare-function gascity-sling--title-slug "gascity-formula")
(declare-function gascity-sling-formula--var-class "gascity-formula")
(declare-function gascity-sling--derive-target "gascity-action")
(declare-function gascity-sling--footer "gascity-action")
(declare-function gascity-sling-dispatch-preview "gascity-action")

(defconst gascity-sling-test--city "/tmp/sling-city/")

(defconst gascity-sling-test--catalog
  '((formulas . [((name . "do-work") (description . "Do one bead"))
                 ((name . "build-basic") (description . "Full build"))]))
  "A `gc formula catalog' payload.")

(defconst gascity-sling-test--list
  `((city_path . "/tmp/sling-city")
    (formulas . [((name . "build-basic") (source . "/pack/build-basic.formula.toml"))
                 ((name . "do-work") (source . "/pack/do-work.formula.toml"))
                 ((name . "e2e-demo")
                  (source . "/tmp/sling-city/formulas/e2e-demo.formula.toml"))
                 ((name . "mol-extra") (source . "/pack/mol-extra.formula.toml"))]))
  "A `gc formula list' payload: two catalog formulas, one city, one pack.")

;;; Fixtures for the redesign tests

(defun gascity-sling-test--recipe (steps &optional vars)
  "Decode a `gascity-formula' named do-work with STEPS and VARS.
STEPS is the raw step alist vector; VARS the raw var alist vector."
  (gascity-domain-decode
   'gascity-formula `((name . "do-work")
                      (steps . ,(or steps (vector)))
                      (vars . ,(or vars (vector))))))

(defconst gascity-sling-test--drain-steps
  (vector '((id . "drain") (title . "Drain unit")
            (metadata . ((gc.kind . "drain")))))
  "Steps making `gascity-formula--needs-convoy' true (the `--on' shape).")

(defconst gascity-sling-test--v2-steps
  (vector '((id . "run") (title . "Run operator")
            (metadata . ((gc.run_target . "gc.run-operator")))))
  "Steps naming a binding-qualified run target (the bl-bdj trap shape).")

(defconst gascity-sling-test--roster
  '((:name "mayor" :state "active")
    (:name "hello-world/gc.implementation-worker" :rig "hello-world" :state "idle")
    (:name "hello-world/gc.run-operator" :rig "hello-world" :state "stopped"))
  "A roster as the agents loaders produce: one city agent, two
rig-scoped ones (`:rig' absent means the city store).")

(defmacro gascity-sling-test--with-city (&rest body)
  "Run BODY in the test city with empty formula caches and a stable key."
  (declare (indent 0))
  `(let ((default-directory gascity-sling-test--city)
         (gascity-formula-catalog-cache nil)
         (gascity-formula-list-cache nil)
         (gascity-formula-recipe-cache nil))
     (cl-letf (((symbol-function 'gascity-context-scope-key)
                (lambda (&optional _) gascity-sling-test--city))
               ((symbol-function 'gascity-command-formula-catalog!)
                (lambda (&rest _) (error "Synchronous catalog read"))))
       ,@body)))

(defun gascity-sling-test--answer (args callback &optional _errback &rest _)
  "Answer the formula reads from a timer, as a process sentinel would."
  (let ((payload (pcase args
                   (`("formula" "catalog") gascity-sling-test--catalog)
                   (`("formula" "list") gascity-sling-test--list)
                   (_ nil))))
    (run-at-time 0 nil (lambda () (funcall callback payload)))
    nil))

;;; S-1: the picker offers every formula the city can run

(ert-deftest gascity-test-sling-choices-union ()
  "The picker's choices are the catalog plus `gc formula list': catalog
entries carry their description, a city formula `(city)', a pack
formula outside the catalog `(not in catalog)'."
  (gascity-sling-test--with-city
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               #'gascity-sling-test--answer))
      (let (done)
        (gascity-formula-refresh-async nil (lambda () (setq done t)))
        (let ((n 0)) (while (and (not done) (< (cl-incf n) 100))
                       (accept-process-output nil 0.01)))
        (should done)))
    (should (equal (gascity-formula-choices)
                   '(("build-basic" . "Full build")
                     ("do-work" . "Do one bead")
                     ("e2e-demo" . "(city)")
                     ("mol-extra" . "(not in catalog)"))))))

(ert-deftest gascity-test-sling-picker-offers-city-formulas ()
  "`f' offers e2e-demo (a city formula) with its annotation, without a
synchronous gc read: a cold cache waits on the store reads."
  (gascity-sling-test--with-city
    (let (offered annotate)
      (cl-letf (((symbol-function 'gascity-reader-read-async)
                 #'gascity-sling-test--answer)
                ((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (setq offered collection
                         annotate (plist-get completion-extra-properties
                                             :annotation-function))
                   "e2e-demo")))
        (should (equal (gascity-sling-formula--read-formula) "e2e-demo")))
      (should (member "e2e-demo" offered))
      (should (member "do-work" offered))
      (should (equal (funcall annotate "e2e-demo") "  (city)"))
      (should (equal (funcall annotate "do-work") "  Do one bead")))))

(ert-deftest gascity-test-sling-picker-nothing-to-offer ()
  "Both reads failing is a clear `user-error', never an empty picker."
  (gascity-sling-test--with-city
    (let ((gascity-remote-async-timeout 1))
      (cl-letf (((symbol-function 'gascity-reader-read-async)
                 (lambda (_args _cb &optional errback &rest _)
                   (run-at-time 0 nil (lambda () (funcall errback "boom")))
                   nil)))
        (should-error (gascity-sling-formula--read-formula) :type 'user-error)))))

(ert-deftest gascity-test-sling-entry-prefetches-formulas ()
  "Entering the sling menu starts the catalog and list reads through the
store (no process in the stub), so `f' answers from memory."
  (gascity-sling-test--with-city
    (gascity-test-with-store-stubs reads _actions
      (cl-letf (((symbol-function 'transient-setup) #'ignore)
                ((symbol-function 'gascity-sling-formula--bead-or-convoy-at-point)
                 (lambda () nil)))
        (gascity-sling-dispatch)
        (should (member '("formula" "catalog") (mapcar #'car reads)))
        (should (member '("formula" "list") (mapcar #'car reads)))))))

;;; S-2: preview keeps the menu state; `s' slings what was previewed

(defmacro gascity-sling-test--with-menu (scope-var &rest body)
  "Run BODY with a fake live sling menu whose scope is SCOPE-VAR.
`transient-setup' re-setups update SCOPE-VAR; `transient-args' is nil."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'transient-scope) (lambda () ,scope-var))
             ((symbol-function 'transient-args) (lambda (_p) nil))
             ((symbol-function 'transient-setup)
              (lambda (_name _l _s &rest args)
                (setq ,scope-var (plist-get args :scope)))))
     ,@body))

(ert-deftest gascity-test-sling-preview-keeps-state-and-s-slings-it ()
  "Plain path: `P' opens the full preview without prompting — the
routing plan is the dry run of the same sling, started through the
store — and the menu keeps its scope (work and target stay); `s' then
slings the same command without prompting, and forgets the city's
state (S-2, ported to the redesign: `p'→`P', scope `:work')."
  (skip-unless (and (fboundp 'gascity-sling-dispatch-preview)
                    (gascity-test-sling-redesign-p)))
  (let ((scope (list :city gascity-sling-test--city :formula nil
                     :target "sess-1" :work "gce-1"))
        (preview-buf nil))
    (gascity-sling-test--with-menu scope
      (gascity-test-with-store-stubs _reads actions
        (cl-letf (((symbol-function 'read-string)
                   (lambda (&rest _) (error "`P' and `s' must not prompt")))
                  ((symbol-function 'completing-read)
                   (lambda (&rest _) (error "`P' and `s' must not prompt")))
                  ((symbol-function 'gascity-view-get-buffer-create)
                   (lambda (_name &rest _)
                     (setq preview-buf (generate-new-buffer " *gc-sling-preview*"))
                     preview-buf))
                  ((symbol-function 'pop-to-buffer) (lambda (b &rest _) b)))
          (call-interactively #'gascity-sling-dispatch-preview)
          ;; The preview's routing plan is the dry run of this sling.
          (should (member '("sling" "sess-1" "gce-1" "--dry-run")
                         (mapcar #'car actions)))
          ;; The menu keeps its state: the scope still carries the work
          ;; and target the preview showed (S-2).
          (should (equal (plist-get scope :work) "gce-1"))
          (should (equal (plist-get scope :target) "sess-1"))
          ;; `s' right after: no prompt, the previewed command without
          ;; the dry run, as a real `--json' sling.
          (call-interactively #'gascity-sling-dispatch-run)
          (should (member '("sling" "sess-1" "gce-1" "--json")
                         (mapcar #'car actions)))
          (should-not (assoc gascity-sling-test--city
                             gascity-sling--remembered)))))
    (when (buffer-live-p preview-buf)
      (let ((kill-buffer-query-functions nil))
        (kill-buffer preview-buf)))))

(ert-deftest gascity-test-sling-preview-is-transient ()
  "`P' stays in the menu (a transient suffix), like `g', `r' and `A'."
  (skip-unless (fboundp 'gascity-sling-dispatch-preview))
  (should (oref (get 'gascity-sling-dispatch-preview 'transient--suffix)
                transient)))

(ert-deftest gascity-test-sling-reentry-restores-and-x-resets ()
  "Re-entering `S' in the same city restores the remembered formula,
target and work (a bead at point still names the work); `x' clears
everything and forgets the city (ported to the redesign's `:work'
scope key; the remembered-state contract itself is unchanged)."
  (skip-unless (gascity-test-sling-redesign-p))
  (let ((gascity-sling--remembered
         (list (cons gascity-sling-test--city
                     (cons (list :city gascity-sling-test--city
                                 :formula "e2e-demo" :target "mayor"
                                 :work "bl-1")
                           '("--var name=x")))))
        (captured nil))
    (gascity-test-with-store-stubs _reads _actions
      (cl-letf (((symbol-function 'transient-setup)
                 (lambda (_name _l _s &rest args) (setq captured args)))
                ((symbol-function 'gascity-formula-refresh-async) #'ignore)
                ((symbol-function 'gascity-sling-formula--bead-or-convoy-at-point)
                 (lambda () nil)))
        (let ((default-directory gascity-sling-test--city))
          (gascity-sling-dispatch))
        (should (equal (plist-get (plist-get captured :scope) :formula)
                       "e2e-demo"))
        (should (equal (plist-get (plist-get captured :scope) :target)
                       "mayor"))
        (should (equal (plist-get (plist-get captured :scope) :work) "bl-1"))
        (should (equal (plist-get captured :value) '("--var name=x")))
        ;; A bead at point wins the work.
        (cl-letf (((symbol-function 'gascity-sling-formula--bead-or-convoy-at-point)
                   (lambda () "bl-9")))
          (let ((default-directory gascity-sling-test--city))
            (gascity-sling-dispatch))
          (should (equal (plist-get (plist-get captured :scope) :work)
                         "bl-9")))
        ;; `x' resets work, formula and target, and forgets the city.
        (let ((scope (plist-get captured :scope)))
          (gascity-sling-test--with-menu scope
            (call-interactively #'gascity-sling-dispatch-reset)
            (should (null (plist-get scope :formula)))
            (should (null (plist-get scope :target)))
            (should (null (plist-get scope :work)))
            (should (equal (plist-get scope :city) gascity-sling-test--city))
            (should-not (assoc gascity-sling-test--city
                               gascity-sling--remembered))))))))

;;; The redesign: shape inference and the header sentence (WI-1)

(ert-deftest gascity-test-sling-shape-inference ()
  "The shape is inferred from (work, formula), never chosen via flags:
formula nil is always the plain route; a formula without work is the
targetless `--formula' shape; a formula with work is the targeted
`--on' drain (mockup §6b)."
  (skip-unless (fboundp 'gascity-sling--shape))
  (should (eq (gascity-sling--shape nil nil) 'plain))
  (should (eq (gascity-sling--shape "bl-5ja" nil) 'plain))
  (should (eq (gascity-sling--shape nil "do-work") 'formula))
  (should (eq (gascity-sling--shape "bl-5ja" "do-work") 'on)))

(ert-deftest gascity-test-sling-header-sentence ()
  "The first header line is one sentence naming the shape, the work
and the target, with the mockup §1–§4 wording: plain names the bead
and the target; a formula without work says `(formula) on'; a drain
formula with work says `against bead …, drained by …'; a cold entry
shows both pick hints."
  (skip-unless (gascity-test-sling-redesign-p))
  ;; Plain: "Sling bead bl-5ja to mayor" (mockup §1).
  (should (string-match-p
           "Sling bead bl-5ja to mayor"
           (gascity-test-sling-header-text
            (list :city gascity-sling-test--city :formula nil
                  :work "bl-5ja" :target "mayor")
            nil)))
  ;; Formula without work: "Run pancakes (formula) on mayor" (§3).
  (should (string-match-p
           "Run do-work (formula) on mayor"
           (gascity-test-sling-header-text
            (list :city gascity-sling-test--city :formula "do-work"
                  :work nil :target "mayor")
            (gascity-sling-test--recipe nil))))
  ;; Drain formula with work: "Run build-basic against bead bl-5ja,
  ;; drained by hello-world/gc.implementation-worker" (§4).
  (should (string-match-p
           "Run do-work against bead bl-5ja, drained by hello-world/gc.implementation-worker"
           (gascity-test-sling-header-text
            (list :city gascity-sling-test--city :formula "do-work"
                  :work "bl-5ja"
                  :target "hello-world/gc.implementation-worker")
            (gascity-sling-test--recipe gascity-sling-test--drain-steps))))
  ;; Cold entry: both hints in one sentence (§2).
  (should (string-match-p
           "(no work — A or point at a bead)"
           (gascity-test-sling-header-text
            (list :city gascity-sling-test--city :formula nil
                  :work nil :target nil)
            nil))))

;;; The redesign: typed How vars (WI-5)

(ert-deftest gascity-test-sling-var-class-heuristics ()
  "The typed-var heuristic picks the infix class from the var's name
and declared default: `context_path' and any `*_path' read a file,
`artifact_root' a directory, `*_target' the agent roster, an
all-digit default (or the `max_*'/`*_iterations' convention) a
numeric entry; `rig_name' and anything unrecognized fail soft to the
string option (mockup §4's [file]/[dir]/[agent]/[numeric] tags)."
  (skip-unless (fboundp 'gascity-sling-formula--var-class))
  (cl-flet ((class (var) (gascity-sling-formula--var-class
                          (gascity-domain-decode
                           'gascity-formula-var var))))
    (should (eq (class '((name . "context_path")))
                'gascity-sling-formula--file-option))
    (should (eq (class '((name . "summary_path")))
                'gascity-sling-formula--file-option))
    (should (eq (class '((name . "artifact_root")))
                'gascity-sling-formula--directory-option))
    (should (eq (class '((name . "implementation_target")))
                'gascity-sling-formula--agent-option))
    ;; Numeric by all-digit declared default…
    (should (eq (class '((name . "width") (default . "10")))
                'gascity-sling-formula--numeric-option))
    ;; …and by the max_*/`*_iterations' naming convention.
    (should (eq (class '((name . "max_iterations") (default . "10")))
                'gascity-sling-formula--numeric-option))
    ;; `rig_name' stays an editable string (auto-derived, not typed).
    (should (eq (class '((name . "rig_name")))
                'gascity-sling-formula--string-option))
    ;; Unrecognized names fail soft to the string option.
    (should (eq (class '((name . "flavor")))
                'gascity-sling-formula--string-option))))

(ert-deftest gascity-test-sling-title-slug ()
  "`plans/<slug>/' seeds from the work bead's TITLE, downcased with
non-alphanumeric runs collapsed to a single dash — the mockup §4
slug, never the bare bead id."
  (skip-unless (fboundp 'gascity-sling--title-slug))
  (should (equal
           (gascity-sling--title-slug
            "e2e sling-v2: verify unified plain sling over TRAMP")
           "e2e-sling-v2-verify-unified-plain-sling-over-tramp"))
  ;; A punctuation run collapses to one dash, edges are trimmed.
  (should (equal (gascity-sling--title-slug "Sling: redesign!! (v2)")
                 "sling-redesign-v2")))

;;; The redesign: the derived Who default (WI-3)

(ert-deftest gascity-test-sling-derive-target-precedence ()
  "The Who default derivation order: per-(city, formula) target
memory first, then the implementation-worker convention — the
roster's exactly one rig-scoped `gc.implementation-worker'; an
ambiguous roster (two rig-scoped workers, or only a city-scoped one)
derives nothing and leaves `T' to ask."
  (skip-unless (fboundp 'gascity-sling--derive-target))
  (let ((scope (list :city gascity-sling-test--city :formula "do-work"
                     :work nil :target nil))
        (one-worker '((:name "mayor" :state "active")
                      (:name "hello-world/gc.implementation-worker"
                       :rig "hello-world" :state "idle"))))
    ;; A memory hit for this (city, formula) wins.
    (should (equal "mayor"
                   (gascity-sling--derive-target
                    scope one-worker
                    (list (cons (cons gascity-sling-test--city "do-work")
                                "mayor")))))
    ;; No memory: the single rig-scoped implementation-worker.
    (should (equal "hello-world/gc.implementation-worker"
                   (gascity-sling--derive-target scope one-worker nil)))
    ;; Two rig-scoped workers are ambiguous: nothing is derived.
    (should-not (gascity-sling--derive-target
                 scope
                 (append one-worker
                         '((:name "other/gc.implementation-worker"
                            :rig "other" :state "idle")))
                 nil))
    ;; A city-scoped worker alone does not satisfy the convention.
    (should-not (gascity-sling--derive-target
                 scope '((:name "gc.implementation-worker" :state "idle"))
                 nil))))

;;; The redesign: client-side validation (WI-2, WI-6)

(ert-deftest gascity-test-sling-v2-trap-warning ()
  "The bl-bdj trap: a formula whose steps name binding-qualified run
targets (a value with `.' and no `/') fails against a city-scoped
target agent — the client warns, because gc's dry run does not
exercise the instantiation failure.  A rig-scoped target is fine; a
slash-qualified run target is a cross-rig route, not this trap.  The
footer carries the §5a wording verbatim."
  (skip-unless (and (fboundp 'gascity-sling--v2-trap-p)
                    (fboundp 'gascity-sling--binding-targets-p)
                    (fboundp 'gascity-sling--footer)))
  (let ((v2 (gascity-sling-test--recipe gascity-sling-test--v2-steps))
        (routed (gascity-sling-test--recipe
                 (vector '((id . "run") (title . "Run it")
                           (metadata . ((gc.run_target
                                         . "gascity.el/worker"))))))))
    (gascity-test-with-store-stubs _reads _actions
      (cl-letf (((symbol-function 'gascity-agents-roster)
                 (lambda (&optional _) gascity-sling-test--roster)))
        ;; Binding-qualified run targets are detectable in the recipe.
        (should (gascity-sling--binding-targets-p v2))
        (should-not (gascity-sling--binding-targets-p routed))
        ;; The trap fires for a city-scoped target only.
        (should (gascity-sling--v2-trap-p v2 "mayor"))
        (should-not (gascity-sling--v2-trap-p
                     v2 "hello-world/gc.implementation-worker"))
        ;; The footer warns with the mockup §5a wording.
        (let ((footer (gascity-sling--footer
                       (list :city gascity-sling-test--city :formula "do-work"
                             :work "bl-5ja" :target "mayor")
                       v2)))
          (should (string-prefix-p "⚠" footer))
          (should (string-match-p "formulas v2 target" footer))
          (should (string-match-p "(bl-bdj)" footer)))
        ;; A rig-scoped target on the same formula is clean (§5a's ✓).
        (should (string-prefix-p
                 "✓"
                 (gascity-sling--footer
                  (list :city gascity-sling-test--city :formula "do-work"
                        :work "bl-5ja"
                        :target "hello-world/gc.implementation-worker")
                  v2)))))))

(ert-deftest gascity-test-sling-cross-store-warning ()
  "A work bead whose store (its id prefix, routed through the rig
memo) differs from the target's store — a rig-scoped agent names its
rig — is warned about before launch: gc refuses cross-store routes."
  (skip-unless (fboundp 'gascity-sling--cross-store-p))
  (let ((rigs (list (gascity-domain-decode
                     'gascity-rig '((name . "hello-world")
                                    (prefix . "hw"))))))
    ;; A hello-world bead against another rig's agent: refused (§5b).
    (should (gascity-sling--cross-store-p
             "hw-ab12" "gascity.el/gc.implementation-worker" rigs))
    ;; The same rig's agent reads the bead's store: fine.
    (should-not (gascity-sling--cross-store-p
                 "hw-ab12" "hello-world/gc.run-operator" rigs))
    ;; A city bead (no rig owns the prefix) to a city agent: fine.
    (should-not (gascity-sling--cross-store-p "bl-5ja" "mayor" rigs))))

(ert-deftest gascity-test-sling-footer-recompute ()
  "The live footer is a pure function of (scope, roster, recipe):
the §1/§3 ready sentences name the shape, the target and its scope,
and the var count; a cold entry warns that no work is chosen.  It
recomputes as each answer changes and never blocks `s'."
  (skip-unless (fboundp 'gascity-sling--footer))
  (gascity-test-with-store-stubs _reads _actions
    (cl-letf (((symbol-function 'gascity-agents-roster)
               (lambda (&optional _) gascity-sling-test--roster)))
      ;; §1: a fully answered plain dispatch.
      (let ((footer (gascity-sling--footer
                     (list :city gascity-sling-test--city :formula nil
                           :work "bl-5ja" :target "mayor")
                     nil)))
        (should (string-prefix-p "✓" footer))
        (should (string-match-p "plain route" footer))
        (should (string-match-p "target mayor (city)" footer))
        (should (string-match-p "no vars" footer)))
      ;; §3: a formula run without work.
      (let ((footer (gascity-sling--footer
                     (list :city gascity-sling-test--city :formula "do-work"
                           :work nil :target "mayor")
                     (gascity-sling-test--recipe nil))))
        (should (string-prefix-p "✓" footer))
        (should (string-match-p "formula run" footer))
        (should (string-match-p "0 vars" footer)))
      ;; §2: a cold entry has nothing to launch yet.
      (should (string-prefix-p
               "⚠"
               (gascity-sling--footer
                (list :city gascity-sling-test--city :formula nil
                      :work nil :target nil)
                nil))))))

;;; The redesign: the follow offer (WI-8)

(ert-deftest gascity-test-sling-follow-offer ()
  "A formula-path launch echoes `Launched workflow <id> (<formula>
on <work>) — F: run view' and offers a momentary `F' that jumps to
`gascity-run-show' on the created workflow root; any other key
dismisses it.  A plain-route launch offers nothing (§9)."
  (skip-unless (gascity-test-sling-redesign-p))
  (let ((messages nil) (maps nil) (shown nil)
        (scope (list :city gascity-sling-test--city :formula "do-work"
                     :work "gce-1" :target "sess-1")))
    (gascity-sling-test--with-menu scope
      (gascity-test-with-store-stubs _reads _actions
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (push (apply #'format fmt args) messages)))
                  ((symbol-function 'set-transient-map)
                   (lambda (map &rest _) (push map maps) nil))
                  ((symbol-function 'gascity-run-show)
                   (lambda (run &rest _) (push run shown)))
                  ((symbol-function 'gascity-formula-recipe-cached)
                   (lambda (_name)
                     (gascity-sling-test--recipe
                      gascity-sling-test--drain-steps)))
                  ;; Answer the launch at once like the store would:
                  ;; whichever field names the created workflow root,
                  ;; the offer finds the same id (the plan leaves the
                  ;; field to the e2e pass).
                  ((symbol-function 'gascity-command-act-async)
                   (lambda (command &rest rest)
                     (let ((on-success (plist-get rest :on-success)))
                       (when on-success
                         (funcall on-success
                                  '((id . "bl-9xyz")
                                    (workflow_id . "bl-9xyz")
                                    (root_bead_id . "bl-9xyz")
                                    (workflow_root_id . "bl-9xyz"))))
                     command))))
          ;; The formula path: the offer.
          (call-interactively #'gascity-sling-dispatch-run)
          (should (cl-some (lambda (m)
                             (string-match-p
                              "Launched workflow bl-9xyz (do-work on gce-1)" m))
                           messages))
          ;; The momentary map: `F' jumps to the run view.
          (should maps)
          (let ((binding (lookup-key (car maps) "F")))
            (should binding)
            (funcall binding)
            (should (member "bl-9xyz" shown)))
          ;; The plain route on the same stubs: no offer at all.
          (setq messages nil maps nil shown nil)
          (setq scope (list :city gascity-sling-test--city :formula nil
                            :work "gce-1" :target "sess-1"))
          (call-interactively #'gascity-sling-dispatch-run)
          (should-not maps)
          (should-not (cl-some (lambda (m)
                                (string-match-p "Launched workflow" m))
                              messages)))))))

;;; The redesign: the reserved set (WI-4)

(ert-deftest gascity-test-sling-reserved-set-matches-mockups ()
  "The redesigned reserved set is exactly the mockup §10 key summary
— `A f T c a n m t s P r g x q' — with `p' freed and `P' added; the
generated var keys avoid it and `gascity-test-sling-reserved-keys-
complete' keeps it in sync with the bound layout."
  (skip-unless (gascity-test-sling-redesign-p))
  (let ((mockups '("A" "f" "T" "c" "a" "n" "m" "t" "s" "P" "r" "g" "x" "q")))
    (should (= (length gascity-sling--reserved-keys) (length mockups)))
    (should-not (cl-set-difference gascity-sling--reserved-keys mockups
                                  :test #'equal))
    (should-not (cl-set-difference mockups gascity-sling--reserved-keys
                                   :test #'equal))
    (should-not (member "p" gascity-sling--reserved-keys))))

(provide 'gascity-sling-test)
;;; gascity-sling-test.el ends here
