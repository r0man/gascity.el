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
  "Entering the sling menu starts the catalog and list reads through the
store (no process in the stub), so `-f' answers from memory."
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

(provide 'gascity-sling-test)
;;; gascity-sling-test.el ends here
