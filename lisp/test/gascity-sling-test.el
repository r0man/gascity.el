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
  "The header carries the `derived' tag (REQ-005): a target only
DERIVED renders `Target: NAME (derived)'; one set with `-T' renders
plain; nothing derivable keeps `Target: (none)'."
  (let ((info (lambda (scope) (nth 1 (gascity-sling--scope-info scope)))))
    (gascity-sling-test--with-agent-list gascity-sling-test--agent-list
      (should (string-match-p
               "Target: hello-world/gc.implementation-worker (derived)"
               (funcall info (list :city gascity-sling-test--city :formula nil
                                   :target nil :arg "hw-12"))))
      ;; A set target renders without the tag — `-T' overrides.
      (should (string-match-p
               "Target: sess-7"
               (funcall info (list :city gascity-sling-test--city :formula nil
                                   :target "sess-7" :arg "hw-12")))))
    ;; Nothing derivable (cold cache): the old hint.
    (should (string-match-p "Target: (none)"
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
