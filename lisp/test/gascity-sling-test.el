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

;;; WI-6: the live footer (REQ-007/REQ-010, mockup §1–§5)

;; The footer composes the WI-2 validators (gascity-formula) and the
;; WI-1 shape inference — sibling work items of the same redesign
;; that land as their own commits, so these tests stub each one AT ITS
;; CONTRACT: the predicates with WI-2's real decision rules (or a
;; captured-args stand-in), the builders with their canonical mockup
;; wording — the exact strings of gascity-formula's real builders —
;; the shape rule with WI-1's real body.  At integration the real
;; functions take over; the wording pinning stays meaningful because
;; the stubs mirror them verbatim.

(defconst gascity-sling-test--roster
  (list (list :name "mayor" :rig nil)
        (list :name "hello-world/gc.implementation-worker"
              :rig "hello-world"))
  "A two-agent roster: the city-scoped mayor and one rig-scoped agent
(mockup §6c shape — rows are agent plists, scope from WI-2's
`gascity-agents-scope').")

(defun gascity-sling-test--recipe (&optional vars)
  "Decode a minimal build-basic-like recipe with VARS (a raw vector)."
  (gascity-domain-decode
   'gascity-formula
   `((name . "build-basic") ,@(and vars `((vars . ,vars))))))

(defvar gascity-sling-test--footer-values nil
  "The `gascity-sling-formula--current-values' answer inside the tests.
Let-bound by a test to pin the footer's var count; the live infix
reader is stubbed so no transient state is touched.")

(defmacro gascity-sling-test--with-footer-deps (&rest body)
  "Run BODY with the footer's WI-1/WI-2 contract stubbed.
Nothing fires (every predicate answers nil), every builder words the
mockup-exact warning, the shape rule is WI-1's real one, and
`gascity-sling-formula--current-values' answers
`gascity-sling-test--footer-values' (let-bind it).  A test fires a
check by rebinding its predicate inside BODY."
  (declare (indent 0))
  `(let ((gascity-sling--missing-target-warning
          "No target — T to choose, or s will prompt"))
     (cl-letf
         (;; WI-1's shape rule, verbatim.
          ((symbol-function 'gascity-sling--shape)
           (lambda (work formula)
             (cond ((not formula) 'plain)
                   ((not (gascity-formula--blank work)) 'on)
                   (t 'formula))))
          ;; WI-2's scope classifier and lookup, verbatim.
          ((symbol-function 'gascity-agents-scope)
           (lambda (agent)
             (or (plist-get agent :rig)
                 (let ((name (plist-get agent :name)))
                   (if (and (stringp name) (string-search "/" name))
                       (substring name 0 (string-search "/" name))
                     "city")))))
          ((symbol-function 'gascity-agents-roster-scope)
           (lambda (target roster)
             (when-let* ((agent (seq-find (lambda (a)
                                            (equal (plist-get a :name) target))
                                          roster)))
               (gascity-agents-scope agent))))
          ;; WI-2's builders, canonical mockup wording.
          ((symbol-function 'gascity-sling--v2-trap-warning)
           (lambda (&optional rig)
             (format
              "formulas v2 target: this formula needs a rig-scoped target — the chosen city agent will fail with \"unknown formulas v2 target\" (bl-bdj); pick a %s with T"
              (if (gascity-formula--nonblank rig)
                  (format "%s/* agent" rig)
                "rig-scoped agent"))))
          ;; Verbatim WI-2 (gascity-formula): the bead named in full,
          ;; both stores the bead's prefix resolves to — here pinned to
          ;; hello-world, the mockup §5b store.
          ((symbol-function 'gascity-sling--cross-store-warning)
           (lambda (work scope _rigs)
             (format
              "cross-store route: bead %s lives in the %s store but the target reads the %s store — gc will refuse (pick a city agent or a %s agent)"
              work "hello-world" scope "hello-world")))
          ((symbol-function 'gascity-sling--missing-work-warning)
           (lambda (recipe)
             (format "%s drains a bead — pick work with A (or point at one)"
                     (or (gascity-formula-name recipe) "formula"))))
          ((symbol-function 'gascity-sling--missing-vars-warning)
           (lambda (names)
             (and names
                  (format "Missing required vars: %s"
                          (mapconcat #'identity names ", ")))))
          ((symbol-function 'gascity-sling--missing-target-p)
           (lambda (target) (gascity-formula--blank target)))
          ;; The live infix values: the test's let-bound fixture.
          ((symbol-function 'gascity-sling-formula--current-values)
           (lambda () gascity-sling-test--footer-values))
          ;; Nothing fires by default.
          ((symbol-function 'gascity-sling--v2-trap-p)
           (lambda (&rest _) nil))
          ((symbol-function 'gascity-sling--cross-store-p)
           (lambda (&rest _) nil))
          ((symbol-function 'gascity-sling--missing-work-p)
           (lambda (&rest _) nil))
          ((symbol-function 'gascity-sling--missing-required-vars)
           (lambda (&rest _) nil)))
       ,@body)))

(ert-deftest gascity-test-sling-footer-ready-plain-sentence ()
  "Mockup §1: a fully answered plain dispatch reads
`✓ Ready — plain route · target mayor (city) · no vars'.  The shape
comes from the WI-1 rule (no formula is the plain shape), the target
word from the roster (mayor is city-scoped), and the plain shape has
no vars at all."
  (gascity-sling-test--with-footer-deps
    (should
     (equal
      (gascity-sling--footer
       (list :city gascity-sling-test--city :formula nil
             :target "mayor" :arg "bl-5ja")
       gascity-sling-test--roster nil)
      "✓ Ready — plain route · target mayor (city) · no vars"))))

(ert-deftest gascity-test-sling-footer-ready-formula-sentence ()
  "Mockup §3: a formula without work is the targetless `--formula'
shape; pancakes declares no vars, so `0 vars' (not `no vars': a
formula is in scope, it just has nothing to answer)."
  (gascity-sling-test--with-footer-deps
    (should
     (equal
      (gascity-sling--footer
       (list :city gascity-sling-test--city :formula "pancakes"
             :target "mayor" :arg nil)
       gascity-sling-test--roster
       (gascity-domain-decode 'gascity-formula '((name . "pancakes"))))
      "✓ Ready — formula run · target mayor (city) · 0 vars"))))

(ert-deftest gascity-test-sling-footer-ready-on-sentence ()
  "Mockup §4: formula plus work is the targeted `--on' shape; the
vars word counts non-blank answers against the declared vars (2 of
3), and a rig-scoped target renders as just `rig-scoped' — the
qualification a v2 launch needs; the name sits in the Who line."
  (let ((gascity-sling-test--footer-values
         '(("artifact_root" . "plans/e2e-sling-v2/")
           ("push" . "true"))))
    (gascity-sling-test--with-footer-deps
      (should
       (equal
        (gascity-sling--footer
         (list :city gascity-sling-test--city :formula "build-basic"
               :target "hello-world/gc.implementation-worker"
               :arg "bl-5ja")
         gascity-sling-test--roster
         (gascity-sling-test--recipe
          (vector '((name . "artifact_root"))
                  '((name . "push"))
                  '((name . "context_path")))))
        "✓ Ready — on run · target rig-scoped · 2 of 3 vars set")))))

(ert-deftest gascity-test-sling-footer-v2-trap-warning ()
  "Mockup §5a: a city-scoped target on a v2 formula warns verbatim —
and the footer feeds the validator the RECIPE and the target's
ROSTER-SCOPE (never the raw target name); the suggestion rig is the
first rig-scoped roster row (hello-world), a cold roster degrades to
the generic wording.  The warning is a string — it never blocks `s'."
  (let ((recipe (gascity-sling-test--recipe))
        (trap-args nil))
    (gascity-sling-test--with-footer-deps
      (cl-letf (((symbol-function 'gascity-sling--v2-trap-p)
                 (lambda (r scope)
                   (setq trap-args (list r scope))
                   t)))
        (should
         (equal
          (gascity-sling--footer
           (list :city gascity-sling-test--city :formula "build-basic"
                 :target "mayor" :arg "bl-5ja")
           gascity-sling-test--roster recipe)
          "⚠ formulas v2 target: this formula needs a rig-scoped target — the chosen city agent will fail with \"unknown formulas v2 target\" (bl-bdj); pick a hello-world/* agent with T"))))
    (should (eq (nth 0 trap-args) recipe))
    (should (equal (nth 1 trap-args) "city"))
    ;; Cold roster: the suggestion stays generic.
    (gascity-sling-test--with-footer-deps
      (cl-letf (((symbol-function 'gascity-sling--v2-trap-p)
                 (lambda (&rest _) t)))
        (should
         (equal
          (gascity-sling--footer
           (list :city gascity-sling-test--city :formula "build-basic"
                 :target "mayor" :arg "bl-5ja")
           nil recipe)
          "⚠ formulas v2 target: this formula needs a rig-scoped target — the chosen city agent will fail with \"unknown formulas v2 target\" (bl-bdj); pick a rig-scoped agent with T"))))))

(ert-deftest gascity-test-sling-footer-cross-store-warning ()
  "Mockup §5b: a rig-scoped target reading another store than the
work bead warns verbatim — and the footer feeds the validator the
WORK, the target's roster scope and the rig memo
(`gascity-rigs-cached' of the scope's city — nil here, a cold memo,
never a gc read)."
  (let ((cross-args nil))
    (gascity-sling-test--with-footer-deps
      (cl-letf (((symbol-function 'gascity-sling--cross-store-p)
                 (lambda (work scope rigs)
                   (setq cross-args (list work scope rigs))
                   t)))
        (should
         (equal
          (gascity-sling--footer
           (list :city gascity-sling-test--city :formula nil
                 :target "gascity.el/implementation-worker"
                 :arg "hw-ab12")
           (list (list :name "gascity.el/implementation-worker"
                       :rig "gascity.el"))
           nil)
          "⚠ cross-store route: bead hw-ab12 lives in the hello-world store but the target reads the gascity.el store — gc will refuse (pick a city agent or a hello-world agent)"))))
    (should (equal (nth 0 cross-args) "hw-ab12"))
    (should (equal (nth 1 cross-args) "gascity.el"))
    (should (null (nth 2 cross-args)))))

(ert-deftest gascity-test-sling-footer-missing-pieces-stack ()
  "Mockup §5c: the three missing pieces stack as `⚠' lines in order —
missing work for a drain formula, missing required vars, missing
target — the footer prefixes and joins them; no check ever refuses."
  (let ((recipe (gascity-sling-test--recipe)))
    (gascity-sling-test--with-footer-deps
      (cl-letf (((symbol-function 'gascity-sling--missing-work-p)
                 (lambda (r work)
                   (and (eq r recipe) (gascity-formula--blank work))))
                ((symbol-function 'gascity-sling--missing-required-vars)
                 (lambda (r _values)
                   (and (eq r recipe) '("artifact_root")))))
        (should
         (equal
          (gascity-sling--footer
           (list :city gascity-sling-test--city :formula "build-basic"
                 :target nil :arg nil)
           nil recipe)
          "⚠ build-basic drains a bead — pick work with A (or point at one)\n⚠ Missing required vars: artifact_root\n⚠ No target — T to choose, or s will prompt"))))))

(ert-deftest gascity-test-sling-footer-recomputes-across-scope-changes ()
  "REQ-007: the footer is a pure function of the scope — each answer
that lands (the re-setups of a pick, a target, an arg) recomputes it:
the warnings of §5c peel away one by one until the ready sentence
remains, on the same recipe."
  (let ((recipe (gascity-sling-test--recipe)))
    (gascity-sling-test--with-footer-deps
      (cl-letf (((symbol-function 'gascity-sling--missing-work-p)
                 (lambda (r work)
                   (and (eq r recipe) (gascity-formula--blank work)))))
        (let ((base (list :city gascity-sling-test--city
                          :formula "build-basic" :target nil :arg nil)))
          ;; Nothing answered: missing work, missing target.
          (should (equal (gascity-sling--footer base nil recipe)
                         "⚠ build-basic drains a bead — pick work with A (or point at one)\n⚠ No target — T to choose, or s will prompt"))
          ;; The target lands: the missing-target warning goes.
          (should (equal (gascity-sling--footer
                          (plist-put (copy-sequence base) :target "mayor")
                          gascity-sling-test--roster recipe)
                         "⚠ build-basic drains a bead — pick work with A (or point at one)"))
          ;; The work lands: ready.
          (should (equal (gascity-sling--footer
                          (plist-put (plist-put (copy-sequence base)
                                               :target "mayor")
                                     :arg "bl-5ja")
                          gascity-sling-test--roster recipe)
                         "✓ Ready — on run · target mayor (city) · 0 vars")))))))

(ert-deftest gascity-test-sling-footer-info-renders-in-every-setup ()
  "REQ-007: the footer renders as part of every transient setup — the
header group of `gascity-sling--children-specs' carries the footer
`:info' spec on every shape, and its description FUNCTION computes
`gascity-sling--footer' for the live scope (a function, so every
redraw recomputes it; the spec must not be a group's first element).
Parse-time stays pure: no roster read, no footer call — the spec is
built without touching the WI-2 surface, so no other menu test sees
the footer's dependencies."
  (let ((recipe (gascity-domain-decode 'gascity-formula
                                       '((name . "build-basic")))))
    (gascity-sling-test--with-city
      (gascity-test-with-store-stubs _reads _actions
        (gascity-sling-test--with-footer-deps
          (cl-letf (((symbol-function 'gascity-formula-recipe-cached)
                     (lambda (_name) recipe))
                    ((symbol-function 'gascity-context-city-name)
                     (lambda (&optional _dir) "testcity"))
                    ((symbol-function 'gascity-agents--roster)
                     (lambda (_data) gascity-sling-test--roster)))
            (dolist (scope (list
                            (list :city gascity-sling-test--city
                                  :formula "build-basic" :target "mayor"
                                  :arg "bl-5ja")
                            (list :city gascity-sling-test--city
                                  :formula nil :target "mayor"
                                  :arg "bl-5ja")))
              (let* ((groups (gascity-sling--children-specs scope))
                     (footer (aref (nth 0 groups) 2)))
                (should (eq (car footer) :info))
                (should (functionp (cadr footer)))
                ;; The description function renders the live footer of
                ;; this scope — re-evaluated at every format.
                (should
                 (equal (funcall (cadr footer))
                        (gascity-sling--footer
                         scope gascity-sling-test--roster
                         (and (plist-get scope :formula) recipe))))))))))))

(ert-deftest gascity-test-sling-footer-roster-cached-peeks-the-store ()
  "The footer's render path reads the roster from the store's cache —
peeking `status', `session list' and `agent list' (scheduling
background refreshes, never blocking, D9) — and joins them through
WI-2's `gascity-agents--roster'.  The work-bead read stays out: the
footer classifies targets, it does not link beads."
  (gascity-sling-test--with-city
    (gascity-test-with-store-stubs reads _actions
      (let (data)
        (cl-letf (((symbol-function 'gascity-agents--roster)
                   (lambda (payload)
                     (setq data payload)
                     gascity-sling-test--roster)))
          (should (equal
                   (gascity-sling--roster-cached gascity-sling-test--city)
                   gascity-sling-test--roster))
          (should (member '("status") (mapcar #'car reads)))
          (should (member '("session" "list") (mapcar #'car reads)))
          (should (member '("agent" "list") (mapcar #'car reads)))
          ;; The bead-linking join is not the footer's business.
          (should-not (member '("bd" "list") (mapcar #'car reads)))
          ;; The join sees exactly the peeks, keyed like the loaders.
          (should (plist-member data :status))
          (should (plist-member data :sessions))
          (should (plist-member data :agents))
          (should-not (plist-member data :work)))))))

(provide 'gascity-sling-test)
;;; gascity-sling-test.el ends here
