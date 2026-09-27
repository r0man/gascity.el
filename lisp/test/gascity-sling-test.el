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

(provide 'gascity-sling-test)
;;; gascity-sling-test.el ends here
