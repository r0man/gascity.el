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

;;; WI-7 (REQ-008): the `P' full preview buffer

(defconst gascity-sling-test--preview-recipe
  '((name . "do-work")
    (description . "Full lifecycle")
    (vars . [((name . "summary_path") (required . t))
             ((name . "mode") (pattern . "\\`[a-z]+\\'"))])
    (steps . [((id . "prepare") (title . "Prepare"))
              ((id . "implement") (title . "Implement")
               (metadata . ((gc.kind . "drain"))))])
    (deps . [((step_id . "implement") (depends_on_id . "prepare"))]))
  "A compiled `gc formula show' payload for the preview: one required
var, one pattern var, a drain step (so the formula needs a convoy),
and two steps of which one needs the other.")

(defun gascity-sling-test--preview-buffer ()
  "Return the live full-preview buffer, whatever city qualified it."
  (seq-find (lambda (b)
              (and (buffer-live-p b)
                   (string-prefix-p "*gc-sling: preview*" (buffer-name b))))
            (buffer-list)))

(defmacro gascity-sling-test--with-preview (reads actions values &rest body)
  "Run BODY with the full preview's gc boundary stubbed and fixtures set.
READS and ACTIONS record the store spawns
(`gascity-test-with-store-stubs'); the recipe cache answers from the
`gascity-sling-test--preview-recipe' fixture, the live var values are
VALUES, and the preview buffer plus the remembered menu state die with
the test."
  (declare (indent 3))
  `(let ((gascity-sling--remembered gascity-sling--remembered))
     (unwind-protect
         (let ((default-directory gascity-sling-test--city))
           (gascity-test-with-store-stubs ,reads ,actions
             (cl-letf (((symbol-function 'gascity-formula-recipe-cached)
                        (lambda (_name)
                          (gascity-domain-decode 'gascity-formula
                                                 gascity-sling-test--preview-recipe)))
                       ((symbol-function 'gascity-sling-formula--current-values)
                        (lambda () ,values))
                       ((symbol-function 'gascity-context-city-name)
                        (lambda (&optional _dir) "testcity"))
                       ((symbol-function 'pop-to-buffer)
                        (lambda (b &rest _) b)))
               ,@body)))
       (dolist (b (buffer-list))
         (when (and (buffer-live-p b)
                    (string-prefix-p "*gc-sling: preview*" (buffer-name b)))
           (let ((kill-buffer-query-functions nil))
             (kill-buffer b)))))))

(ert-deftest gascity-test-sling-full-preview-renders-sections ()
  "`P' paints the preview buffer at once, client-side (REQ-008): the
header sentence, the Validation checks with their full text, the
cached recipe's steps → needs DAG, and the Routing plan section
pending on the async dry run — exactly one gc spawn (the dry run,
the `p' command), nothing synchronous, and the buffer stays pinned
to the entered-from city."
  (gascity-sling-test--with-preview reads actions
      '(("summary_path" . "build/summary.md"))
    (let ((scope (list :city gascity-sling-test--city :formula "do-work"
                       :target "rig/agent" :arg "bl-1")))
      (gascity-sling--full-preview scope nil)
      (let ((buf (gascity-sling-test--preview-buffer)))
        (should buf)
        (with-current-buffer buf
          (should (eq major-mode 'gascity-sling-preview-mode))
          (should (equal default-directory gascity-sling-test--city))
          (let ((text (buffer-string)))
            (should (string-search "Sling preview — testcity" text))
            (should (string-search
                     "Run do-work against bead bl-1, drained by rig/agent" text))
            (should (string-search "Validation" text))
            (should (string-search "✓ target rig/agent" text))
            (should (string-search "✓ work bl-1 (the formula requires it)" text))
            (should (string-search "✓ required vars set: summary_path" text))
            (should (string-search "Recipe — do-work (steps → needs)" text))
            (should (string-search "needs nothing" text))
            (should (string-search "Implement" text))
            (should (string-search "needs prepare" text))
            (should (string-search "Routing plan (gc sling … --dry-run)" text))
            ;; First paint: the section waits on the dry run.
            (should (string-search "…" text)))))
      ;; One spawn, the dry run itself — the same command `p' shows,
      ;; built by the shared `gascity-sling-formula--command'.
      (should (null reads))
      (should (= (length actions) 1))
      (should (equal (car (car actions))
                     '("sling" "rig/agent" "bl-1" "--on" "do-work"
                       "--var" "summary_path=build/summary.md" "--dry-run"))))))

(ert-deftest gascity-test-sling-full-preview-fills-plan-when-answered ()
  "The Routing plan section fills with gc's dry-run stdout when the
async call answers (D9) — first paint never blocks on it — and a
failed dry run fills its first stderr line instead."
  (gascity-sling-test--with-preview reads actions
      '(("summary_path" . "build/summary.md"))
    (let ((scope (list :city gascity-sling-test--city :formula "do-work"
                       :target "rig/agent" :arg "bl-1")))
      (gascity-sling--full-preview scope nil)
      ;; gc answers: the captured stdout replaces the placeholder.
      (funcall (nth 1 (car actions))
               (list :exit-code 0
                     :stdout "Target:\n  Session config: rig/agent (min=0)\n"
                     :stderr "" :executable "gc"))
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (should (string-search "Session config: rig/agent" (buffer-string)))
        ;; The pending line is gone (the heading keeps its own …).
        (should-not (string-search "\n  …\n" (buffer-string))))
      ;; A failing dry run: the failure's line lands in the section.
      (gascity-sling--full-preview scope nil)
      (funcall (nth 1 (car actions))
               (list :exit-code 1 :stdout "" :stderr "boom\n" :executable "gc"))
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (should (string-search "failed: boom" (buffer-string)))
        (should-not (string-search "\n  …\n" (buffer-string)))))))

(ert-deftest gascity-test-sling-full-preview-launches-from-the-buffer ()
  "The preview buffer binds `s' to launching exactly what was
previewed (REQ-008): the dry-run command without `--dry-run', reported
as JSON — no prompts, the call started and the buffer quits — and the
city's remembered menu state is cleared like the menu's own `s'
(bug S-2).  `q' quits."
  (gascity-sling-test--with-preview reads actions
      '(("summary_path" . "build/summary.md"))
    (let ((scope (list :city gascity-sling-test--city :formula "do-work"
                       :target "rig/agent" :arg "bl-1")))
      (gascity-sling--full-preview scope nil)
      ;; What `P' holds is remembered for the city (S-2).
      (should (assoc gascity-sling-test--city gascity-sling--remembered))
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (should (eq (key-binding "s") #'gascity-sling-preview-launch))
        (should (eq (key-binding "q") #'quit-window))
        (cl-letf (((symbol-function 'quit-window) #'ignore))
          (call-interactively #'gascity-sling-preview-launch)))
      ;; The launch: exactly the previewed command, minus `--dry-run',
      ;; as JSON (most recent spawn first).
      (should (= (length actions) 2))
      (let ((args (car (car actions))))
        (should (equal (seq-take args 3) '("sling" "rig/agent" "bl-1")))
        (should (equal (cadr (member "--on" args)) "do-work"))
        (should (member "--json" args))
        (should-not (member "--dry-run" args)))
      ;; A real launch forgets the city's remembered state (S-2).
      (should-not (assoc gascity-sling-test--city gascity-sling--remembered)))))

(ert-deftest gascity-test-sling-full-preview-warnings-never-a-gate ()
  "A dispatch that cannot run yet still previews (REQ-008): a missing
target, missing work for the convoy-requiring formula and a missing
required var render as full-text warnings, no dry run is asked for
at all, and the buffer's `s' stays bound — the preview is never a
gate; the menu's `s' works the same."
  (gascity-sling-test--with-preview reads actions nil
    (let ((scope (list :city gascity-sling-test--city :formula "do-work"
                       :target nil :arg nil)))
      (gascity-sling--full-preview scope nil)
      (should (null reads))
      (should (null actions))
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (let ((text (buffer-string)))
          (should (string-search "⚠ no target" text))
          (should (string-search
                   "⚠ no work — do-work requires a target convoy" text))
          (should (string-search "⚠ missing required var: summary_path" text))
          (should (string-search "(no routing plan — no target" text))
          ;; The client-side sections still render in full.
          (should (string-search "Recipe — do-work (steps → needs)" text))
          (should (string-search "needs prepare" text))
          ;; Never a gate: the launch binding is live.
          (should (eq (key-binding "s") #'gascity-sling-preview-launch)))))))

(ert-deftest gascity-test-sling-full-preview-plain-path ()
  "`P' previews the plain dispatch too: the recipe section says there
is none, the dry run carries the menu's routing flags, and `s'
launches the plain command with `--json' — the plain path of
`gascity-sling--run' unchanged."
  (gascity-sling-test--with-preview reads actions nil
    (let ((scope (list :city gascity-sling-test--city :formula nil
                       :target "sess-1" :arg "gce-1")))
      (gascity-sling--full-preview scope '("--nudge" "--merge=direct"))
      (let ((args (car (car actions))))
        (should (= (length actions) 1))
        (should (equal (seq-take args 3) '("sling" "sess-1" "gce-1")))
        (should (member "--nudge" args))
        (should (member "direct" args))
        (should (member "--dry-run" args)))
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (let ((text (buffer-string)))
          (should (string-search "Sling gce-1 to sess-1" text))
          (should (string-search "✓ target sess-1" text))
          (should (string-search
                   "(no formula picked — this dispatch is plain)" text))))
      ;; Launch: the plain command, JSON, no dry run, flags kept.
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (cl-letf (((symbol-function 'quit-window) #'ignore))
          (call-interactively #'gascity-sling-preview-launch)))
      (should (= (length actions) 2))
      (let ((args (car (car actions))))
        (should (equal (seq-take args 3) '("sling" "sess-1" "gce-1")))
        (should (member "--nudge" args))
        (should (member "--json" args))
        (should-not (member "--dry-run" args))))))

(ert-deftest gascity-test-sling-full-preview-pattern-warning ()
  "A set var that fails its declared pattern warns in full text — the
`gascity-formula--validate-values' rules mirrored client-side — and
keeps the dry run from launching."
  (gascity-sling-test--with-preview reads actions
      '(("summary_path" . "build/summary.md") ("mode" . "Not-Valid!"))
    (let ((scope (list :city gascity-sling-test--city :formula "do-work"
                       :target "rig/agent" :arg "bl-1")))
      (gascity-sling--full-preview scope nil)
      ;; The pattern failure refuses the command build: no dry run.
      (should (null actions))
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (should (string-search "⚠ var mode does not match pattern" (buffer-string)))
        (should (string-search "(no routing plan — see Validation above)"
                                (buffer-string)))))))

(ert-deftest gascity-test-sling-full-preview-validation-hook ()
  "Further checks (the sling redesign's roster-based warnings) join
the Validation section through
`gascity-sling-preview-validation-functions' — pure, in the city pin —
without touching the preview itself."
  (gascity-sling-test--with-preview reads actions nil
    (let ((gascity-sling-preview-validation-functions
           (list (lambda (_scope _recipe _values)
                   '("✓ no cross-store route")))))
      (gascity-sling--full-preview
       (list :city gascity-sling-test--city :formula nil
             :target "sess-1" :arg "gce-1")
       nil)
      (with-current-buffer (gascity-sling-test--preview-buffer)
        (should (string-search "✓ no cross-store route" (buffer-string)))))))

(ert-deftest gascity-test-sling-full-preview-suffix-is-wired ()
  "`P' is the menu's full-preview suffix (REQ-008) and a non-transient
one: the buffer it opens is the interactive surface, while the
menu's state is remembered for the city (bug S-2)."
  (should (commandp 'gascity-sling-dispatch-full-preview))
  ;; A non-transient suffix: one press opens the buffer and leaves the menu.
  ;; The Actions group is the fifth child group of the stacked layout.
  (let* ((groups (gascity-sling--children-specs
                  (list :formula nil :target nil :arg nil)))
         (actions (seq-find #'vectorp (nthcdr 4 groups)))
         (spec (and actions
                    (seq-find (lambda (s)
                                (and (consp s) (equal (car s) "P")))
                              (append actions nil)))))
    (should (equal (list "P" "Full preview…"
                         'gascity-sling-dispatch-full-preview)
                   spec)))
  ;; The reserved set stays in sync with the binding (OQ-2).
  (should (member "P" gascity-sling--reserved-keys))
  (let ((bound nil))
    (cl-letf (((symbol-function 'gascity-formula-recipe-cached)
               (lambda (_name) nil))
              ((symbol-function 'gascity-context-city-name)
               (lambda (&optional _dir) "testcity")))
      (dolist (group (gascity-sling--children-specs
                      (list :formula nil :target nil :arg nil)))
        (when (vectorp group)
          (dolist (spec (append group nil))
            (when (and (consp spec) (stringp (car spec))
                       (equal (car spec) "P"))
              (setq bound (nth 2 spec))))))
      (should (eq bound 'gascity-sling-dispatch-full-preview)))))

(provide 'gascity-sling-test)
;;; gascity-sling-test.el ends here
