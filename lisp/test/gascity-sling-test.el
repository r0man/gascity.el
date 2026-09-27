;;; gascity-sling-test.el --- Sling picker union and menu state (S-1, S-2) -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Bugs S-1 and S-2 of the dashboard-v3 formula e2e
;; (docs/qa/2026-09-25-dashboard-v3-e2e-scenarios.md):
;;
;; - S-1: the formula picker offered only `gc formula catalog' (opt-in
;;   pack formulas), so the city's own formulas could not be slung.  It
;;   now offers the union with `gc formula list', read through the store.
;; - S-2: `p' closed the sling menu and lost formula, target and vars; a
;;   following `S s' became a plain sling.  Preview now keeps the menu,
;;   and the state is remembered per city.
;;
;; - WI-9 (REQ-012): a real launch records the per-(city,formula)
;;   target memory (the Who default's memory tier — previews never
;;   record), `x' clears the infix values alongside the scope, and
;;   the remembered state still re-opens at `S'.
;; The launch follow offer of the sling redesign (plans/sling-command,
;; WI-8 / REQ-009): a successful formula sling echoes
;; `Launched workflow <id> (<formula> on <work>) — F: run view' and
;; binds `F', for one keypress, to `gascity-run-show' on the created
;; workflow root — named by the `gc sling --json' payload, else the
;; newest run root resolved through the store, never a guess.  The
;; plain route keeps its plain echo and no offer.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

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

(defun gascity-sling-test--recipe (name steps &optional vars)
  "Decode a `gascity-formula' NAME with raw STEPS and VARS."
  (gascity-domain-decode
   'gascity-formula `((name . ,name) (steps . ,steps)
                      ,@(and vars `((vars . ,vars))))))

(defconst gascity-sling-test--build-basic
  (gascity-sling-test--recipe
   "build-basic"
   (vector '((id . "requirements") (title . "Requirements")
             (metadata . ((gc.kind . "work")
                          (gc.run_target . "gc.requirements-planner"))))
           '((id . "run") (title . "Run")
             (metadata . ((gc.run_target . "gc.run-operator"))))
           '((id . "publish") (title . "Publish")
             (metadata . ((gc.run_target . "mayor"))))
           '((id . "drain") (title . "Drain")
             (metadata . ((gc.kind . "drain")
                          (gc.run_target . "{{implementation_target}}")))))
   (vector '((name . "artifact_root") (required . t))
           '((name . "implementation_target") (required . t))))
  "A build-basic-shaped recipe: two binding-qualified run targets, a
plain-agent one, a `{{implementation_target}}' placeholder, a drain
step and two required vars.")

(defconst gascity-sling-test--pancakes
  (gascity-sling-test--recipe
   "pancakes"
   (vector '((id . "cook") (title . "Cook")
             (metadata . ((gc.kind . "work") (gc.run_target . "mayor"))))))
  "A plain v1-shaped recipe: only plain-agent run targets, no drain.")

(defun gascity-sling-test--rigs ()
  "The bright-lights-shaped rig memo: the city HQ row and one rig."
  (list (gascity-domain-decode
         'gascity-rig '((name . "bright-lights") (prefix . "bl") (hq . t)))
        (gascity-domain-decode
         'gascity-rig '((name . "hello-world") (prefix . "hw")))))

;;; REQ-010: the client-side validators (WI-2 — pure, never blocking)

(ert-deftest gascity-test-sling-binding-targets-p ()
  "A binding-qualified run target contains a `.' and no `/'."
  (should (gascity-sling--binding-qualified-target-p "gc.run-operator"))
  (should-not (gascity-sling--binding-qualified-target-p "mayor"))
  (should-not (gascity-sling--binding-qualified-target-p
               "hello-world/polecat"))
  (should-not (gascity-sling--binding-qualified-target-p nil))
  ;; Over recipes: build-basic's steps carry them, a plain one does not,
  ;; and no formula picked is no.
  (should (gascity-sling--binding-targets-p gascity-sling-test--build-basic))
  (should-not (gascity-sling--binding-targets-p gascity-sling-test--pancakes))
  (should-not (gascity-sling--binding-targets-p nil)))

(ert-deftest gascity-test-sling-v2-trap-p-and-warning ()
  "The bl-bdj trap: binding-qualified run targets with a city-scoped
target warn with the mockup §5a wording; a rig scope and free entry
degrade."
  (should (gascity-sling--v2-trap-p gascity-sling-test--build-basic "city"))
  (should-not (gascity-sling--v2-trap-p
               gascity-sling-test--build-basic "hello-world"))
  ;; Free entry (an unclassifiable target) never dead-ends: no warning.
  (should-not (gascity-sling--v2-trap-p gascity-sling-test--build-basic nil))
  ;; A plain formula with a city target is no trap at all.
  (should-not (gascity-sling--v2-trap-p gascity-sling-test--pancakes "city"))
  (should-not (gascity-sling--v2-trap-p nil "city"))
  (should (equal (gascity-sling--v2-trap-warning "hello-world")
                 "formulas v2 target: this formula needs a rig-scoped target — the chosen city agent will fail with \"unknown formulas v2 target\" (bl-bdj); pick a hello-world/* agent with T"))
  ;; Without a rig to suggest the wording stays generic.
  (should (equal (gascity-sling--v2-trap-warning)
                 "formulas v2 target: this formula needs a rig-scoped target — the chosen city agent will fail with \"unknown formulas v2 target\" (bl-bdj); pick a rig-scoped agent with T")))

(ert-deftest gascity-test-sling-cross-store-p-and-warning ()
  "Cross-store: a bead and a rig-scoped target in different stores warn
with the mockup §5b wording; a city target never fires and everything
unresolvable degrades."
  (let ((rigs (gascity-sling-test--rigs)))
    ;; The store resolves from the bead's id prefix via the rig memo.
    (should (equal (gascity-sling--bead-store "hw-ab12" rigs) "hello-world"))
    (should (equal (gascity-sling--bead-store "bl-5ja" rigs) "bright-lights"))
    ;; Freeform work text, a foreign prefix and a cold memo resolve to
    ;; nothing — never a guess.
    (should-not (gascity-sling--bead-store "fix the flaky test" rigs))
    (should-not (gascity-sling--bead-store "zz-9" rigs))
    (should-not (gascity-sling--bead-store "hw-ab12" nil))
    ;; The mockup §5b case: an hw bead slung at another rig's agent.
    (should (gascity-sling--cross-store-p "hw-ab12" "gascity.el" rigs))
    ;; Same store, and the city agent (gc's own remedy) — no warning.
    (should-not (gascity-sling--cross-store-p "hw-ab12" "hello-world" rigs))
    (should-not (gascity-sling--cross-store-p "hw-ab12" "city" rigs))
    ;; Unresolvable sides degrade: free entry, freeform work, cold memo.
    (should-not (gascity-sling--cross-store-p "hw-ab12" nil rigs))
    (should-not (gascity-sling--cross-store-p "fix the login" "gascity.el" rigs))
    (should-not (gascity-sling--cross-store-p "hw-ab12" "gascity.el" nil))
    ;; The mockup §5b wording, verbatim.
    (should (equal (gascity-sling--cross-store-warning "hw-ab12" "gascity.el" rigs)
                   "cross-store route: bead hw-ab12 lives in the hello-world store but the target reads the gascity.el store — gc will refuse (pick a city agent or a hello-world agent)"))
    ;; A clean route builds no warning.
    (should-not (gascity-sling--cross-store-warning "hw-ab12" "hello-world" rigs))))

(ert-deftest gascity-test-sling-missing-pieces ()
  "The mockup §5c checks: a drain formula without work, missing
required vars and no target — pure, and `validate-values' still
refuses what the footer only warns about."
  ;; No work for a drain formula...
  (should (gascity-sling--missing-work-p gascity-sling-test--build-basic nil))
  (should (gascity-sling--missing-work-p gascity-sling-test--build-basic ""))
  (should-not (gascity-sling--missing-work-p
               gascity-sling-test--build-basic "bl-5ja"))
  ;; ...but a plain shape never fires: freeform text is its work.
  (should-not (gascity-sling--missing-work-p nil nil))
  (should-not (gascity-sling--missing-work-p gascity-sling-test--pancakes nil))
  (should (equal (gascity-sling--missing-work-warning
                   gascity-sling-test--build-basic)
                 "build-basic drains a bead — pick work with A (or point at one)"))
  ;; Missing required vars, in declared order; the footer's wording.
  (should (equal (gascity-sling--missing-required-vars
                   gascity-sling-test--build-basic nil)
                 '("artifact_root" "implementation_target")))
  (should (equal (gascity-sling--missing-required-vars
                   gascity-sling-test--build-basic
                   '(("artifact_root" . "plans/e2e/") ("implementation_target" . "x")))
                 nil))
  ;; A blank value counts as unset.
  (should (equal (gascity-sling--missing-required-vars
                   gascity-sling-test--build-basic
                   '(("artifact_root" . " ") ("implementation_target" . "gc.w")))
                 '("artifact_root")))
  (should (equal (gascity-sling--missing-vars-warning
                   '("artifact_root" "implementation_target"))
                 "Missing required vars: artifact_root, implementation_target"))
  (should-not (gascity-sling--missing-vars-warning nil))
  ;; No target.
  (should (gascity-sling--missing-target-p nil))
  (should (gascity-sling--missing-target-p " "))
  (should-not (gascity-sling--missing-target-p "mayor"))
  (should (equal gascity-sling--missing-target-warning
                 "No target — T to choose, or s will prompt"))
  ;; The signaling half still refuses at dispatch (REQ-008/009).
  (should-error (gascity-formula--validate-values
                 gascity-sling-test--build-basic nil)
                :type 'user-error))

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
  "`-f' offers e2e-demo (a city formula) with its annotation, without a
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
  "Entering the sling menu starts the catalog, list and agent-list
reads through the store (no process in the stub): `-f' answers from
memory, and the Who default's convention rule finds its roster (WI-3)."
  (gascity-sling-test--with-city
    (gascity-test-with-store-stubs reads _actions
      (cl-letf (((symbol-function 'transient-setup) #'ignore)
                ((symbol-function 'gascity-sling-formula--bead-or-convoy-at-point)
                 (lambda () nil)))
        (gascity-sling-dispatch)
        (should (member '("formula" "catalog") (mapcar #'car reads)))
        (should (member '("formula" "list") (mapcar #'car reads)))
        ;; `gc agent list' too — the derived Who default's roster source
        ;; (WI-3): requested once at entry, async, so the derivation
        ;; answers from the store's cache.
        (should (member '("agent" "list") (mapcar #'car reads)))))))

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
  "Plain path: `p' reads arg and target once, keeps the menu open with
them in the scope, and remembers them for the city; `s' then slings the
same command without prompting, and forgets the city's state."
  (let ((scope (list :city gascity-sling-test--city :formula nil
                     :target nil :arg nil))
        previewed acted prompts)
    (gascity-sling-test--with-menu scope
      (cl-letf (((symbol-function 'read-string)
                 (lambda (p &rest _) (push p prompts) "gce-1"))
                ((symbol-function 'gascity-action--read-session)
                 (lambda (p) (push p prompts) "sess-1"))
                ((symbol-function 'gascity-sling--show-plan)
                 (lambda (c) (setq previewed c)))
                ((symbol-function 'gascity-command-act-async)
                 (lambda (c &rest _) (setq acted c))))
        (call-interactively #'gascity-sling-dispatch-preview)
        (should (equal (gascity-command-line previewed)
                       '("gc" "sling" "sess-1" "gce-1" "--dry-run")))
        (should (equal (plist-get scope :arg) "gce-1"))
        (should (equal (plist-get scope :target) "sess-1"))
        (should (assoc gascity-sling-test--city gascity-sling--remembered))
        ;; `s' right after: no prompt, the previewed command minus --dry-run.
        (setq prompts nil)
        (call-interactively #'gascity-sling-dispatch-run)
        (should-not prompts)
        (should (equal (gascity-command-line acted)
                       '("gc" "sling" "sess-1" "gce-1" "--json")))
        (should-not (assoc gascity-sling-test--city gascity-sling--remembered))))))

(ert-deftest gascity-test-sling-preview-is-transient ()
  "`p' stays in the menu (a transient suffix), like `g', `-T' and `A'."
  (should (oref (get 'gascity-sling-dispatch-preview 'transient--suffix)
                transient)))

(ert-deftest gascity-test-sling-reentry-restores-and-x-resets ()
  "Re-entering `S' in the same city restores the remembered formula,
target and values (a bead at point still names the arg); `x' clears
everything and forgets the city."
  (let ((gascity-sling--remembered
         (list (cons gascity-sling-test--city
                     (cons (list :city gascity-sling-test--city
                                 :formula "e2e-demo" :target "mayor" :arg "bl-1")
                           '("--var name=x")))))
        captured)
    (cl-letf (((symbol-function 'transient-setup)
               (lambda (_name _l _s &rest args) (setq captured args)))
              ((symbol-function 'gascity-formula-refresh-async) #'ignore)
              ((symbol-function 'gascity-sling-formula--bead-or-convoy-at-point)
               (lambda () nil)))
      (let ((default-directory gascity-sling-test--city))
        (gascity-sling-dispatch))
      (should (equal (plist-get (plist-get captured :scope) :formula) "e2e-demo"))
      (should (equal (plist-get (plist-get captured :scope) :target) "mayor"))
      (should (equal (plist-get (plist-get captured :scope) :arg) "bl-1"))
      (should (equal (plist-get captured :value) '("--var name=x")))
      ;; A bead at point wins the arg.
      (cl-letf (((symbol-function 'gascity-sling-formula--bead-or-convoy-at-point)
                 (lambda () "bl-9")))
        (let ((default-directory gascity-sling-test--city))
          (gascity-sling-dispatch))
        (should (equal (plist-get (plist-get captured :scope) :arg) "bl-9")))
      ;; `x' resets.
      (let ((scope (plist-get captured :scope)))
        (gascity-sling-test--with-menu scope
          (call-interactively #'gascity-sling-dispatch-reset)
          (should (null (plist-get scope :formula)))
          (should (null (plist-get scope :target)))
          (should (equal (plist-get scope :city) gascity-sling-test--city))
          (should-not (assoc gascity-sling-test--city gascity-sling--remembered)))))))

;;; WI-1: shape inference and the one-sentence header (REQ-001/002)

(defun gascity-sling-test--recipe (name &optional steps)
  "Decode a minimal `gascity-formula' named NAME with raw STEPS."
  (gascity-domain-decode
   'gascity-formula `((name . ,name) ,@(when steps `((steps . ,steps))))))

(defconst gascity-sling-test--drain-recipe
  (gascity-sling-test--recipe
   "build-basic"
   '(((id . "implement") (title . "Implement owned work") (type . "task"))
     ((id . "drain") (title . "Drain the convoy") (type . "drain")
      (metadata . ((gc.kind . "drain"))))))
  "A recipe with a `gc.kind=drain' step — `needs-convoy' is true.")

(defconst gascity-sling-test--plain-recipe
  (gascity-sling-test--recipe
   "pancakes"
   '(((id . "mix") (title . "Mix the batter") (type . "task"))))
  "A recipe with no drain step and no `{{convoy_id}}' — targetless.")

(ert-deftest gascity-test-sling-shape-inference ()
  "The displayed shape is inferred from work + formula, never a flag:
no formula is the plain path regardless of work; a formula with work is
the `--on' shape; a formula without work is `--formula'.  A blank
work string counts as no work (WI-1, REQ-001/002)."
  (should (eq (gascity-sling--shape nil nil) 'plain))
  (should (eq (gascity-sling--shape "bl-5ja" nil) 'plain))
  (should (eq (gascity-sling--shape " " nil) 'plain))
  (should (eq (gascity-sling--shape "bl-5ja" "build-basic") 'on))
  (should (eq (gascity-sling--shape nil "pancakes") 'formula))
  (should (eq (gascity-sling--shape "" "pancakes") 'formula))
  (should (eq (gascity-sling--shape "   " "pancakes") 'formula)))

(ert-deftest gascity-test-sling-header-sentence-mockups ()
  "The header sentence renders the exact mockup §1–§4 wordings for the
shape × work-presence combinations, and the `drained by' clause
consults `gascity-formula--needs-convoy' on the cached recipe (§4/§5a);
a non-convoy recipe renders `on <target>' like the `--formula' shape.
A nil recipe degrades to the same wording without reading gc (D9)."
  ;; §1 — plain, fully pre-seeded.
  (should (equal (gascity-sling--header-sentence "bl-5ja" nil "mayor")
                 "Sling bead bl-5ja to mayor"))
  ;; §2 — cold entry, both hints.
  (should (equal (gascity-sling--header-sentence nil nil nil)
                 "Sling (no work — A or point at a bead) to (no target — T or default)"))
  ;; §3 — formula without work: the targetless --formula shape.
  (should (equal (gascity-sling--header-sentence nil "pancakes" "mayor")
                 "Run pancakes (formula) on mayor"))
  ;; §4 — formula with work: the --on shape, drained by the target
  ;; (needs-convoy on the cached recipe).
  (should (equal (gascity-sling--header-sentence
                  "bl-5ja" "build-basic"
                  "hello-world/gc.implementation-worker"
                  gascity-sling-test--drain-recipe)
                 "Run build-basic against bead bl-5ja, drained by hello-world/gc.implementation-worker"))
  ;; §5a — the same drain recipe with a city-scoped target.
  (should (equal (gascity-sling--header-sentence
                  "bl-5ja" "build-basic" "mayor"
                  gascity-sling-test--drain-recipe)
                 "Run build-basic against bead bl-5ja, drained by mayor")))

(ert-deftest gascity-test-sling-header-sentence-partial-scopes ()
  "The mockup hints stand in for each missing half of the sentence —
plain without target, plain without work, formula without target — and
freeform task text renders as the text itself, not `bead <id>' (the
id heuristic: one dash joining two alphanumeric runs)."
  (should (equal (gascity-sling--header-sentence "bl-5ja" nil nil)
                 "Sling bead bl-5ja to (no target — T or default)"))
  (should (equal (gascity-sling--header-sentence nil nil "mayor")
                 "Sling (no work — A or point at a bead) to mayor"))
  (should (equal (gascity-sling--header-sentence nil "pancakes" nil)
                 "Run pancakes (formula) on (no target — T or default)"))
  (should (equal
           (gascity-sling--header-sentence "fix the flaky timer test" nil "mayor")
           "Sling fix the flaky timer test to mayor")))

(ert-deftest gascity-test-sling-header-sentence-non-convoy-recipe ()
  "The `on' shape with a recipe that needs no convoy keeps the §3
`on <target>' preposition; a missing recipe degrades to the same
wording — no synchronous gc read on the render path (D9, WI-1)."
  (should (equal (gascity-sling--header-sentence
                  "bl-5ja" "pancakes" "mayor"
                  gascity-sling-test--plain-recipe)
                 "Run pancakes against bead bl-5ja, on mayor"))
  ;; Recipe nil (cold cache): degrade, never read gc.
  (should (equal (gascity-sling--header-sentence
                  "bl-5ja" "pancakes" "mayor" nil)
                 "Run pancakes against bead bl-5ja, on mayor")))

(ert-deftest gascity-test-sling-scope-info-renders-the-sentence ()
  "The menu header carries the sentence (the old field list is gone):
`gascity-sling--scope-info' wraps it in the raw unwrapped `(:info …)'
spec, reads the work from `:work' or the legacy `:arg' slot, and
passes the cached recipe through for the `drained by' clause (WI-1)."
  (should (equal (gascity-sling--scope-info
                   (list :formula nil :target nil :arg nil) nil)
                 (list :info "Sling (no work — A or point at a bead) to (no target — T or default)")))
  (should (equal (gascity-sling--scope-info
                   (list :formula nil :target "mayor" :work "bl-5ja") nil)
                 (list :info "Sling bead bl-5ja to mayor")))
  (should (equal (gascity-sling--scope-info
                   (list :formula "build-basic" :target "mayor" :arg "bl-5ja")
                   gascity-sling-test--drain-recipe)
                 (list :info "Run build-basic against bead bl-5ja, drained by mayor"))))
;;; WI-9 (REQ-012): launch memory and menu state

(ert-deftest gascity-test-sling-launch-records-target-memory ()
  "A real formula sling records its target under (city . formula) in
`gascity-sling--target-memory' — the Who default derivation's memory
tier — while the post-launch forget clears only the open-menu state:
launch memory and menu state are two different things."
  (let ((gascity-sling--target-memory nil)
        (gascity-sling--remembered
         (list (cons gascity-sling-test--city
                     (cons (list :city gascity-sling-test--city
                                 :formula "e2e-demo" :target "mayor" :arg "bl-1")
                           nil))))
        (scope (list :city gascity-sling-test--city :formula "e2e-demo"
                     :target "mayor" :arg "bl-1"))
        dispatched)
    (gascity-sling-test--with-menu scope
      (cl-letf (((symbol-function 'gascity-formula-recipe-cached)
                 (lambda (_name) nil))
                ((symbol-function 'gascity-sling-formula--current-values)
                 (lambda () nil))
                ((symbol-function 'gascity-sling-formula--dispatch)
                 (lambda (&rest _) (push t dispatched))))
        (call-interactively #'gascity-sling-dispatch-run)
        (should (= (length dispatched) 1))
        (should (equal (cdr (assoc (cons gascity-sling-test--city "e2e-demo")
                                   gascity-sling--target-memory))
                       "mayor"))
        ;; The real launch forgets the menu state, never the memory.
        (should-not (assoc gascity-sling-test--city
                           gascity-sling--remembered))))))

(ert-deftest gascity-test-sling-preview-records-no-target-memory ()
  "`p' previews without touching the launch memory: only a real `s'
records the (city, formula) target."
  (let ((gascity-sling--target-memory nil)
        (scope (list :city gascity-sling-test--city :formula "e2e-demo"
                     :target "mayor" :arg "bl-1"))
        previewed)
    (gascity-sling-test--with-menu scope
      (cl-letf (((symbol-function 'gascity-formula-recipe-cached)
                 (lambda (_name) nil))
                ((symbol-function 'gascity-sling-formula--current-values)
                 (lambda () nil))
                ((symbol-function 'gascity-sling-formula--dispatch)
                 (lambda (_r _t _a _v &optional preview)
                   (setq previewed preview))))
        (call-interactively #'gascity-sling-dispatch-preview)
        (should previewed)
        (should (null gascity-sling--target-memory))))))

(ert-deftest gascity-test-sling-plain-launch-records-nil-formula-memory ()
  "A plain launch has no formula, so its target records under the
(city, nil) pair (WI-3's rule 2 reads it back for the next plain
sling) — never under a formula."
  (let ((gascity-sling--target-memory nil)
        (scope (list :city gascity-sling-test--city :formula nil
                     :target nil :arg nil)))
    (gascity-sling-test--with-menu scope
      (cl-letf (((symbol-function 'read-string)
                 (lambda (_p &rest _) "gce-1"))
                ((symbol-function 'gascity-action--read-session)
                 (lambda (_p) "sess-1"))
                ((symbol-function 'gascity-command-act-async)
                 (lambda (&rest _))))
        (call-interactively #'gascity-sling-dispatch-run)
        (should (equal (cdr (assoc (cons gascity-sling-test--city nil)
                                   gascity-sling--target-memory #'equal))
                       "sess-1"))))))

(ert-deftest gascity-test-sling-refused-launch-records-no-target-memory ()
  "A launch the validation refuses records no target memory: the
recording runs after the dispatch, so a `user-error' thrown before any
gc invocation never reaches it."
  (let ((gascity-sling--target-memory nil)
        (scope (list :city gascity-sling-test--city :formula "e2e-demo"
                     :target "mayor" :arg "bl-1")))
    (gascity-sling-test--with-menu scope
      (cl-letf (((symbol-function 'gascity-formula-recipe-cached)
                 (lambda (_name) nil))
                ((symbol-function 'gascity-sling-formula--current-values)
                 (lambda () nil))
                ((symbol-function 'gascity-sling-formula--dispatch)
                 (lambda (&rest _)
                   (user-error "Var summary_path must be set"))))
        (should-error (call-interactively #'gascity-sling-dispatch-run)
                      :type 'user-error)
        (should (null gascity-sling--target-memory))))))

(ert-deftest gascity-test-sling-blank-target-records-no-target-memory ()
  "A blank target records no memory: the dispatch's own shape building
drops it, so it was never a target the launch really used."
  (let ((gascity-sling--target-memory nil)
        (scope (list :city gascity-sling-test--city :formula "e2e-demo"
                     :target nil :arg "bl-1"))
        dispatched)
    (gascity-sling-test--with-menu scope
      (cl-letf (((symbol-function 'gascity-formula-recipe-cached)
                 (lambda (_name) nil))
                ((symbol-function 'gascity-sling-formula--current-values)
                 (lambda () nil))
                ((symbol-function 'gascity-action--read-session)
                 (lambda (_p) ""))
                ((symbol-function 'gascity-sling-formula--dispatch)
                 (lambda (&rest _) (push t dispatched))))
        (call-interactively #'gascity-sling-dispatch-run)
        (should (= (length dispatched) 1))
        (should (null gascity-sling--target-memory))))))

(ert-deftest gascity-test-sling-reset-clears-values-too ()
  "`x' clears the infix values alongside the scope: the re-setup carries
no `:value', so no var or routing flag survives the reset (REQ-012).
The per-(city, formula) launch memory is not menu state — `x' keeps it."
  (let ((gascity-sling--target-memory
         (list (cons (cons gascity-sling-test--city "e2e-demo") "mayor")))
        (scope (list :city gascity-sling-test--city :formula "e2e-demo"
                     :target "mayor" :arg "bl-1"))
        captured)
    (cl-letf (((symbol-function 'transient-scope) (lambda () scope))
              ((symbol-function 'transient-setup)
               (lambda (_name _l _s &rest args) (setq captured args))))
      (call-interactively #'gascity-sling-dispatch-reset)
      (dolist (key '(:formula :target :arg))
        (should (null (plist-get (plist-get captured :scope) key))))
      (should (equal (plist-get (plist-get captured :scope) :city)
                     gascity-sling-test--city))
      (should (null (plist-get captured :value)))
      (should-not (assoc gascity-sling-test--city
                         gascity-sling--remembered))
      ;; Launch memory survives the reset: only the menu state is cleared.
      (should (equal (cdr (assoc (cons gascity-sling-test--city "e2e-demo")
                                  gascity-sling--target-memory))
                     "mayor")))))
;;; The launch follow offer (WI-8, REQ-009)

(defconst gascity-sling-test--launched
  '((schema_version . "1") (ok . t) (success . t) (target . "mayor")
    (routed . t) (queued) (dry_run) (method . "on-formula")
    (molecule_id . "ga-1") (workflow_id . "wf-77")
    (convoy_id . "ga-2") (bead_id . "gce-9") (formula . "do-work"))
  "A successful formula `gc sling --json' payload, as gascity decodes
it (false and null both read nil): the created workflow root bead is
`molecule_id', the work bead `bead_id'.")

(ert-deftest gascity-test-sling-launched-root-is-the-payload-root ()
  "The created workflow root comes from the payload's `molecule_id' —
the schema's \"Created molecule/root workflow bead ID\" — and nothing
else: a blank or absent root, or a non-alist result (a failed JSON
parse hands back raw stdout), yields nil rather than an id the offer
would be guessing at."
  (should (equal (gascity-sling--launched-root gascity-sling-test--launched)
                 "ga-1"))
  (should-not (gascity-sling--launched-root
                '((ok . t) (workflow_id . "wf-77") (bead_id . "gce-9"))))
  (should-not (gascity-sling--launched-root
                '((molecule_id . "") (workflow_id . "wf-77"))))
  (should-not (gascity-sling--launched-root "raw stdout")))

(ert-deftest gascity-test-sling-launched-formula-and-work ()
  "The echo's parenthetical names the payload's own formula and work
bead, falling back to the dispatch's formula name and arg when the
payload does not carry them."
  (should (equal (gascity-sling--launched-formula
                  gascity-sling-test--launched "fallback")
                 "do-work"))
  (should (equal (gascity-sling--launched-formula "raw stdout" "fb")
                 "fb"))
  (should (equal (gascity-sling--launched-work
                  gascity-sling-test--launched "fallback")
                 "gce-9"))
  (should (equal (gascity-sling--launched-work
                  '((ok . t) (bead_id . "")) "gce-arg")
                 "gce-arg")))

(ert-deftest gascity-test-sling-newest-run-root-since-launch ()
  "The fallback picks the newest run root created at or after the
launch — carrying its rig store — never an older run, never a row it
cannot date, and nothing when the launch created none."
  (let ((beads `(((id . "ga-old") (created_at . "2026-09-27T10:00:00Z"))
                 ((id . "ga-new") (created_at . "2026-09-27T11:00:00Z")
                  (gascity-rig . "gascity.el"))
                 ((id . "ga-mid") (created_at . "2026-09-27T10:30:00Z"))
                 ((id . "ga-undated")))))
    (should (equal (gascity-sling--newest-run-root
                    beads (gascity-ui-parse-time "2026-09-27T10:15:00Z"))
                   '("ga-new" . "gascity.el")))
    ;; A root created exactly at SINCE counts: the launch's own second.
    (should (equal (gascity-sling--newest-run-root
                    beads (gascity-ui-parse-time "2026-09-27T11:00:00Z"))
                   '("ga-new" . "gascity.el")))
    ;; Nothing created since: no offer is better than a guess.
    (should-not (gascity-sling--newest-run-root
                 beads (gascity-ui-parse-time "2026-09-27T12:00:00Z")))
    (should-not (gascity-sling--newest-run-root nil 0.0))))

(ert-deftest gascity-test-sling-follow-offer-binds-one-F-jump ()
  "The offer echoes `Launched workflow <id> (<formula> on <work>) — F:
run view' and installs exactly one momentary binding: `F' jumps to
`gascity-run-show' on the root — in the owning rig store when known —
and any other key falls through to its own binding, the map holding
nothing else."
  (let ((shown nil)
        (echos nil)
        (pch pre-command-hook)
        (otlm overriding-terminal-local-map))
    (cl-letf (((symbol-function 'gascity-run-show)
               (lambda (run &optional _convoy rig)
                 (push (list run rig) shown)))
              ((symbol-function 'message)
               (lambda (format &rest args)
                 (push (apply #'format format args) echos))))
      (unwind-protect
          (progn
            (gascity-sling--follow-offer "ga-1" "do-work" "gce-9" "gascity.el")
            (should (equal (car echos)
                           "Launched workflow ga-1 (do-work on gce-9) — F: run view"))
            (let ((map overriding-terminal-local-map))
              (should (keymapp map))
              ;; Only `F': any other key dismisses and runs its own
              ;; binding.
              (should (commandp (lookup-key map "F")))
              (should-not (lookup-key map "x"))
              ;; The jump.
              (call-interactively (lookup-key map "F"))
              (should (equal shown '(("ga-1" "gascity.el"))))))
        ;; Restore the momentary state by hand: batch tests send no
        ;; keys, so the map and its pre-command hook would linger.
        (setq pre-command-hook pch
              overriding-terminal-local-map otlm)))))

(defun gascity-sling-test--dispatched-handler ()
  "Return the launch handler a formula dispatch attaches, with the
act stubbed to capture it."
  (let ((handlers nil))
    (cl-letf (((symbol-function 'gascity-command-act-async)
               (lambda (_command &rest kwargs)
                 (when-let* ((handler (plist-get kwargs :on-success)))
                   (push handler handlers)))))
      (gascity-sling-formula--dispatch
       (gascity-domain-decode 'gascity-formula '((name . "do-work")))
       "sess-1" "gce-9" nil))
    (car handlers)))

(ert-deftest gascity-test-sling-formula-launch-attaches-the-offer-plain-does-not ()
  "`s' dispatches exactly as today in both paths (D9): the formula
path alone attaches the launch handler — the follow offer, REQ-009 —
while the plain route keeps the plain act and its plain echo, with no
handler and no offer."
  ;; The formula path rides the handler along on the act.
  (should (functionp (gascity-sling-test--dispatched-handler)))
  ;; The plain path: no handler on the act, no offer at all.
  (let ((kwargs nil)
        (offers nil)
        (scope (list :city gascity-sling-test--city :formula nil
                     :target "sess-9" :arg "gce-abc")))
    (cl-letf (((symbol-function 'gascity-command-act-async)
               (lambda (_command &rest kw) (push kw kwargs)))
              ((symbol-function 'gascity-sling--follow-offer)
               (lambda (&rest _) (push t offers)))
              ((symbol-function 'gascity--refresh-current-view) #'ignore))
      (gascity-sling-test--with-menu scope
        (call-interactively #'gascity-sling-dispatch-run))
      (should (= (length kwargs) 1))
      (should-not (plist-get (car kwargs) :on-success))
      (should-not offers))))

(ert-deftest gascity-test-sling-launch-handler-offers-the-created-root ()
  "The handler turns the payload's created root into the echo plus the
`F' jump — without touching the store (the payload already answered)
or blocking anything (D9): the offer is its whole report."
  (let ((maps nil)
        (shown nil)
        (echos nil)
        (fetches nil))
    (cl-letf (((symbol-function 'set-transient-map)
               (lambda (map &rest _) (push map maps)))
              ((symbol-function 'gascity-run-show)
               (lambda (run &optional _convoy rig)
                 (push (list run rig) shown)))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional _dir) nil))
              ((symbol-function 'message)
               (lambda (format &rest args)
                 (push (apply #'format format args) echos)))
              ((symbol-function 'gascity-store-fetch)
               (lambda (&rest args) (push args fetches))))
      (let ((default-directory gascity-sling-test--city))
        (funcall (gascity-sling--launch-handler
                  (gascity-command-sling :target "sess-1" :arg "gce-9"
                                         :on "do-work")
                  "do-work" "gce-9")
                 gascity-sling-test--launched))
      (should (null fetches))
      (should (equal (car echos)
                     "Launched workflow ga-1 (do-work on gce-9) — F: run view"))
      (should (= (length maps) 1))
      (should (commandp (lookup-key (car maps) "F")))
      (call-interactively (lookup-key (car maps) "F"))
      ;; A cold rig memo: the jump opens the run in the city store.
      (should (equal shown '(("ga-1" nil)))))))

(ert-deftest gascity-test-sling-launch-handler-fallback-resolves-newest ()
  "A payload without a root (the field WI-11 confirms on a live
launch) does not guess and does not give up: the newest run root
created since the launch is resolved through the store — one
run-roots read of the city's stores — and the offer names it."
  (let ((now (current-time))
        (maps nil)
        (echos nil)
        (fetches nil))
    (cl-letf (((symbol-function 'set-transient-map)
               (lambda (map &rest _) (push map maps)))
              ((symbol-function 'message)
               (lambda (format &rest args)
                 (push (apply #'format format args) echos)))
              ((symbol-function 'gascity-store-fetch)
               (lambda (args callback &optional _errback &rest _)
                 (push args fetches)
                 (funcall callback
                          `(:beads
                            (((id . "ga-old")
                              (created_at
                               . ,(format-time-string
                                   "%Y-%m-%dT%H:%M:%SZ"
                                   (time-subtract now 3600) t)))
                             ((id . "ga-new")
                              (created_at
                               . ,(format-time-string
                                   "%Y-%m-%dT%H:%M:%SZ" (time-add now 30) t))
                              (gascity-rig . "gascity.el")))
                            :errors nil)))))
      (funcall (gascity-sling--launch-handler
                (gascity-command-sling :target "sess-1" :arg "gce-9"
                                       :on "do-work")
                "do-work" "gce-9")
               '((ok . t) (success . t) (target . "mayor")
                 (routed . t) (queued) (dry_run) (method . "on-formula")
                 (bead_id . "gce-9")))
      (should (equal (car fetches) gascity-sling--run-roots-key))
      (should (equal (car echos)
                     "Launched workflow ga-new (do-work on gce-9) — F: run view"))
      (should (= (length maps) 1)))))

(ert-deftest gascity-test-sling-launch-handler-no-root-plain-echo ()
  "A launch that resolves no root — no payload field, and no run root
created since it started — keeps the plain success echo and never
offers a jump: better no offer than a wrong one."
  (let ((now (current-time))
        (maps nil)
        (echos nil))
    (cl-letf (((symbol-function 'set-transient-map)
               (lambda (map &rest _) (push map maps)))
              ((symbol-function 'message)
               (lambda (format &rest args)
                 (push (apply #'format format args) echos)))
              ((symbol-function 'gascity-store-fetch)
               (lambda (_args callback &optional _errback &rest _)
                 (funcall callback
                          `(:beads
                            (((id . "ga-old")
                              (created_at
                               . ,(format-time-string
                                   "%Y-%m-%dT%H:%M:%SZ"
                                   (time-subtract now 3600) t))))
                            :errors nil)))))
      (funcall (gascity-sling--launch-handler
                (gascity-command-sling :target "sess-1" :arg "gce-9"
                                       :on "do-work")
                "do-work" "gce-9")
               '((ok . t) (success . t) (target . "mayor")
                 (routed . t) (queued) (dry_run) (method . "on-formula")))
      (should (equal (car echos) "GC sling: ok"))
      (should-not maps))))
;;; WI-3: the derived Who default (REQ-005)

(defconst gascity-sling-test--agent-list
  '((agents . [((name . "dog-1") (qualified_name . "bd.dog-1")
                (scope . "city"))
               ((name . "implementation-worker")
                (qualified_name . "hello-world/gc.implementation-worker")
                (scope . "rig"))
               ((name . "run-operator")
                (qualified_name . "hello-world/gc.run-operator")
                (scope . "rig"))]))
  "A `gc agent list' payload for the roster: one city-scoped agent,
two rig-scoped ones, and exactly one rig-scoped
`gc.implementation-worker' template.")

(defmacro gascity-sling-test--with-agent-list (payload &rest body)
  "Run BODY with the store's cached `gc agent list' payload as PAYLOAD.
The derivation reads the cache (`gascity-store-get'), never spawns —
this stub feeds it."
  (declare (indent 1) (debug t))
  `(cl-letf (((symbol-function 'gascity-store-get)
              (lambda (_args &optional _dir)
                (list :status 'ready :data ,payload))))
     ,@body))

(ert-deftest gascity-test-sling-derive-target-precedence ()
  "The rules fire in the design's order (REQ-005): the work bead's rig
default beats the target memory, the memory beats the
implementation-worker convention; each rule falls through on a miss."
  (let* ((city gascity-sling-test--city)
         (scope (list :city city :formula "build-basic" :target nil :arg "hw-12"))
         (roster (list (list :name "hello-world/gc.implementation-worker"
                             :rig "hello-world")))
         (memory (list (cons (cons city "build-basic") "hello-world/gc.reviewer"))))
    ;; Rule 1 over rules 2 and 3: the rig's default target answers.
    (cl-letf (((symbol-function 'gascity-rigs-cached)
               (lambda (&rest _)
                 (list (gascity-rig :name "hello-world" :prefix "hw"
                                   :default-sling-target
                                   "hello-world/gc.run-operator")))))
      (should (equal (gascity-sling--derive-target scope roster memory)
                     '(:target "hello-world/gc.run-operator"
                       :source rig-default))))
    ;; The plural default backs the singular, deterministically: its
    ;; first element, never gc's random pick — a shown default must
    ;; not flicker between renders.
    (cl-letf (((symbol-function 'gascity-rigs-cached)
               (lambda (&rest _)
                 (list (gascity-rig :name "hello-world" :prefix "hw"
                                   :default-sling-targets
                                   '("hello-world/gc.first"
                                     "hello-world/gc.second"))))))
      (should (equal (gascity-sling--derive-target scope roster memory)
                     '(:target "hello-world/gc.first" :source rig-default))))
    ;; Rule 1 misses (the rig reports no defaults): the memory.
    (cl-letf (((symbol-function 'gascity-rigs-cached)
               (lambda (&rest _)
                 (list (gascity-rig :name "hello-world" :prefix "hw")))))
      (should (equal (gascity-sling--derive-target scope roster memory)
                     '(:target "hello-world/gc.reviewer" :source memory)))
      ;; Rules 1 and 2 miss: the convention — the roster's single
      ;; rig-scoped implementation worker.
      (should (equal (gascity-sling--derive-target scope roster nil)
                     '(:target "hello-world/gc.implementation-worker"
                       :source implementation-worker))))
    ;; Nothing derives at all: nil, never a prompt-blocking default.
    (cl-letf (((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil)))
      (should-not (gascity-sling--derive-target scope nil nil)))))

(ert-deftest gascity-test-sling-derive-target-rig-default-fail-soft ()
  "Rule 1 skips fail-soft (Open Implementation Details): freeform
work text, a prefixless id, an unknown prefix or a cold rig memo never
error — the later rules still answer."
  (let* ((city gascity-sling-test--city)
         (memory (list (cons (cons city "build-basic") "hello-world/gc.reviewer")))
         (roster (list (list :name "hello-world/gc.implementation-worker"
                             :rig "hello-world"))))
    (dolist (work '("fix the docs"        ; freeform text — no prefix
                    "plaincity"            ; prefixless id
                    "zzz-9"))              ; a prefix no rig owns
      (let ((scope (list :city city :formula "build-basic" :target nil :arg work)))
        (cl-letf (((symbol-function 'gascity-rigs-cached)
                   (lambda (&rest _)
                     (list (gascity-rig :name "hello-world" :prefix "hw"
                                       :default-sling-target "hw/gc.one")))))
          ;; The rig default exists, but the work is not its bead:
          ;; the memory answers.
          (should (equal (gascity-sling--derive-target scope roster memory)
                         '(:target "hello-world/gc.reviewer" :source memory))))))
    ;; A cold rig memo with a real work bead: rule 1 still misses.
    (let ((scope (list :city city :formula "build-basic" :target nil :arg "hw-12")))
      (cl-letf (((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil)))
        (should (equal (gascity-sling--derive-target scope roster memory)
                       '(:target "hello-world/gc.reviewer" :source memory)))))))

(ert-deftest gascity-test-sling-derive-target-exactly-one-worker ()
  "The convention's exactly-one rule: one rig-scoped
`gc.implementation-worker' template derives; two (one per rig) are
ambiguous and skip; the same agent twice is still one; a city-scoped
worker never counts; a live session's suffixed instance is not the
template; none derives nothing."
  (let* ((one (list (list :name "hello-world/gc.implementation-worker"
                          :rig "hello-world")
                    (list :name "hello-world/gc.run-operator" :rig "hello-world")
                    (list :name "bd.dog-1" :rig nil)))
         (worker #'gascity-sling--implementation-worker-target))
    (should (equal (funcall worker one)
                   "hello-world/gc.implementation-worker"))
    ;; The same agent twice (a configured agent joined to its live
    ;; session) is still exactly one.
    (should (equal (funcall worker (append one (list (car one))))
                   "hello-world/gc.implementation-worker"))
    ;; Two rigs, one worker each: ambiguous — no default.
    (should-not (funcall worker
                         (append one
                                 (list (list :name
                                             "other-rig/gc.implementation-worker"
                                             :rig "other-rig")))))
    ;; A city-scoped worker does not count.
    (should-not (funcall worker
                         (list (list :name "gc.implementation-worker" :rig nil))))
    ;; A live session instance (a pool slot, `-18') is not the
    ;; template — never a convention answer.
    (should-not (funcall worker
                         (list (list :name
                                     "hello-world/gc.implementation-worker-18"
                                     :rig "hello-world"))))
    ;; None at all.
    (should-not (funcall worker
                         (list (list :name "hello-world/gc.run-operator"
                                     :rig "hello-world"))))))

(ert-deftest gascity-test-sling-target-memory-hit-and-miss ()
  "The per-(city, formula) target memory: a launch records its target,
the same pair derives it back (hit), another formula or another city
misses, a plain launch records under a nil formula, and an empty
target records nothing."
  (let ((city gascity-sling-test--city)
        (gascity-sling--target-memory nil))
    (gascity-sling--remember-target city "build-basic" "hello-world/gc.run-operator")
    ;; Hit: same city, same formula.
    (should (equal (gascity-sling--memory-target
                    (list :city city :formula "build-basic")
                    gascity-sling--target-memory)
                   "hello-world/gc.run-operator"))
    ;; Miss: another formula.
    (should-not (gascity-sling--memory-target
                 (list :city city :formula "do-work")
                 gascity-sling--target-memory))
    ;; Miss: another city.
    (should-not (gascity-sling--memory-target
                 (list :city "/other/city/" :formula "build-basic")
                 gascity-sling--target-memory))
    ;; A plain launch (no formula) records under nil.
    (gascity-sling--remember-target city nil "mayor")
    (should (equal (gascity-sling--memory-target
                    (list :city city :formula nil)
                    gascity-sling--target-memory)
                   "mayor"))
    ;; An empty target records nothing.
    (gascity-sling--remember-target city "e2e-demo" "")
    (should-not (gascity-sling--memory-target
                 (list :city city :formula "e2e-demo")
                 gascity-sling--target-memory))))

(ert-deftest gascity-test-sling-roster-reads-agent-list ()
  "The derivation's roster is the configured agents of `gc agent
list' — the sling targets (singleton agents and pool templates), not
the live sessions — read from the store's cache only, never a spawn
(D9): a warmed entry answers one plist per agent (`:name' the
qualified name, `:rig' its slash prefix, nil for city scope), a cold
store answers nil, and the full derivation fires the convention rule
over the warmed roster."
  (gascity-test-with-store-stubs reads _actions
    ;; Cold: no entry, no roster — the rule skips fail-soft.
    (should-not (gascity-sling--roster gascity-sling-test--city))
    ;; Warm the entry as the menu entry does; the stub parks the read.
    (gascity-store-request '("agent" "list") :dir gascity-sling-test--city)
    (should (member '("agent" "list") (mapcar #'car reads)))
    (funcall (nth 1 (car reads)) gascity-sling-test--agent-list)
    (should (equal (gascity-sling--roster gascity-sling-test--city)
                   (list (list :name "bd.dog-1" :rig nil)
                         (list :name "hello-world/gc.implementation-worker"
                               :rig "hello-world")
                         (list :name "hello-world/gc.run-operator"
                               :rig "hello-world"))))
    ;; The full derivation over the warmed roster: the single worker
    ;; template, tagged with its source.
    (cl-letf (((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil)))
      (should (equal (gascity-sling--derived-target
                      (list :city gascity-sling-test--city :formula nil
                            :target nil :arg nil))
                     '(:target "hello-world/gc.implementation-worker"
                       :source implementation-worker))))))

(ert-deftest gascity-test-sling-run-uses-derived-without-prompting ()
  "REQ-005: `s' with no set target and a derivable one launches on it
without prompting, and the launch records it as the city's (city,
formula) target memory."
  (let ((scope (list :city gascity-sling-test--city :formula "build-basic"
                     :target nil :arg "hw-12"))
        (gascity-sling--target-memory nil)
        dispatched)
    (gascity-sling-test--with-menu scope
      (gascity-sling-test--with-agent-list gascity-sling-test--agent-list
        (cl-letf (((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
                  ((symbol-function 'gascity-action--read-session)
                   (lambda (&rest _) (error "a derivable target must not prompt")))
                  ((symbol-function 'gascity-formula-recipe-cached)
                   (lambda (_name) nil))
                  ((symbol-function 'gascity-sling-formula--current-values)
                   (lambda () nil))
                  ((symbol-function 'gascity-sling-formula--dispatch)
                   (lambda (_recipe target _arg _values &optional _dry)
                     (setq dispatched target))))
          (call-interactively #'gascity-sling-dispatch-run)
          (should (equal dispatched "hello-world/gc.implementation-worker"))
          ;; The launch is remembered: the next launch derives it.
          (should (equal (cdr (assoc (cons gascity-sling-test--city "build-basic")
                                     gascity-sling--target-memory #'equal))
                         "hello-world/gc.implementation-worker")))))))

(ert-deftest gascity-test-sling-preview-uses-derived-but-records-nothing ()
  "`p' previews with the derived target — no prompt — but records no
memory: only a real launch is a choice (WI-3)."
  (let ((scope (list :city gascity-sling-test--city :formula nil
                     :target nil :arg "hw-12"))
        (gascity-sling--target-memory nil)
        shown)
    (gascity-sling-test--with-menu scope
      (gascity-sling-test--with-agent-list gascity-sling-test--agent-list
        (cl-letf (((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
                  ((symbol-function 'gascity-action--read-session)
                   (lambda (&rest _) (error "a derivable target must not prompt")))
                  ((symbol-function 'gascity-sling--show-plan)
                   (lambda (command) (setq shown command)))
                  ((symbol-function 'gascity-command-act-async)
                   (lambda (&rest _) (error "a preview must not act"))))
          (call-interactively #'gascity-sling-dispatch-preview)
          (should (equal (gascity-command-line shown)
                         '("gc" "sling" "hello-world/gc.implementation-worker"
                           "hw-12" "--dry-run")))
          (should-not gascity-sling--target-memory))))))

(ert-deftest gascity-test-sling-header-derived-tag ()
  "A target only DERIVED renders in the header sentence (REQ-005,
adapted to the merged one-sentence header of WI-1): what `s' would
launch, no field list; one set with `-T' renders plain; nothing
derivable keeps the no-target hint."
  (let ((info (lambda (scope) (nth 1 (gascity-sling--scope-info scope)))))
    (gascity-sling-test--with-agent-list gascity-sling-test--agent-list
      (should (string-match-p
               "Sling hw-12 to hello-world/gc.implementation-worker"
               (funcall info (list :city gascity-sling-test--city :formula nil
                                   :target nil :arg "hw-12"))))
      ;; A set target renders without derivation — `-T' overrides.
      (should (string-match-p
               "Sling bead hw-12 to sess-7"
               (funcall info (list :city gascity-sling-test--city :formula nil
                                   :target "sess-7" :arg "hw-12")))))
    ;; Nothing derivable (cold cache): the no-target hint.
    (should (string-match-p "to (no target — T or default)"
                            (funcall info (list :city gascity-sling-test--city
                                                :formula nil :target nil
                                                :arg nil))))))

(ert-deftest gascity-test-sling-target-read-seeds-derived ()
  "`-T' — the Who picker — is seeded with the derived target (WI-3):
RET keeps it, so a derivable target costs no typing."
  (let (seeded)
    (gascity-sling-test--with-agent-list gascity-sling-test--agent-list
      (cl-letf (((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
                ((symbol-function 'gascity-action--read-session)
                 (lambda (_prompt &optional default) (setq seeded default) "picked"))
                ((symbol-function 'transient-scope)
                 (lambda () (list :city gascity-sling-test--city :formula nil
                                  :target nil :arg nil)))
                ((symbol-function 'transient-args) (lambda (_p) nil))
                ((symbol-function 'transient-setup) (lambda (&rest _))))
        (call-interactively #'gascity-sling-dispatch-target)
        (should (equal seeded "hello-world/gc.implementation-worker"))))))

(provide 'gascity-sling-test)
;;; gascity-sling-test.el ends here
