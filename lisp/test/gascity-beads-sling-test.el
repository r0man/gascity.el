;;; gascity-beads-sling-test.el --- beads.el sling seam tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Workstream B's registration module against beads.el's public seams.
;;
;; B5a covers the `[City]' dispatch menu group and the additive bead
;; action provider: one group after repeated registration, the reviewed
;; free keys E/J/K/A/Q, and a `V' cockpit action that never shadows a
;; beads.el binding.
;;
;; B5b covers the after-action refresh: a beads mutation invalidates the
;; bead-derived store kinds exactly once, for the mutation's store root,
;; without reading beads or running from a timer.
;;
;; B6 (`ga-hbeuz') covers the rest of the downstream contract
;; (REQ-002..REQ-009, AC-4..AC-8, AC-10, AC-12, AC-13):
;;
;; - the target provider: qualified gc names, `:backend "gc"', rig and
;;   city targets, the metadata carrier, a rig-repo directory resolved
;;   through the rig memo, and a cold store that answers nil without
;;   spawning gc or breaking the beads transient;
;; - the backend argv shapes: plain, `on' (stable var order) and
;;   `formula' (targeted and targetless, never an empty-string target),
;;   the targetless `on' refusal before the runner, plus the success and
;;   failure echoes and the single invalidation per store kind;
;; - the advisory validators: cross-store, city-scoped target trap and
;;   missing required vars each warn once and never refuse, a clean
;;   input is silent, and the gascity-recipe-only trap stays silent on a
;;   cold gascity recipe cache;
;; - registration idempotence (one backend, one `[City]' group, a stable
;;   target list) and the delegation contract (beads' `S' seeds the
;;   transient, then a `gc' target dispatch reaches the stubbed runner
;;   with the expected argv).
;;
;; Everything stubs the gc boundary (`gascity-test-with-store-stubs',
;; `cl-letf' on the reader functions and the payload store), so the
;; suite is offline and asserts that providers, validators and menu
;; rendering spawn nothing.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'gascity)
(require 'gascity-test-helpers)

(defconst gascity-test-beads-sling--city "/tmp/beads-sling-city/"
  "The local city directory the suite's cached payloads answer for.")

(defconst gascity-test-beads-sling--agent-list
  '((agents . [((name . "mayor")
                (qualified_name . "mayor")
                (scope . "city")
                (role . "Mayor"))
               ((name . "implementation-worker")
                (qualified_name . "gascity.el/gc.implementation-worker")
                (scope . "rig")
                (role . "worker"))]))
  "A `gc agent list' payload: one city-level and one rig agent.
The rig row is the sling derivation's implementation-worker
convention; the city row has no slash prefix.")

(defmacro gascity-test-beads-sling--with-cached-store (payload &rest body)
  "Run BODY with `gc agent list' answered from PAYLOAD (nil: cold).
Only the payload store is stubbed; every other read still goes through
whatever the calling test stubs."
  (declare (indent 1) (debug t))
  `(cl-letf (((symbol-function 'gascity-store-get)
              (lambda (args &optional _dir)
                (when (equal (append args nil) '("agent" "list"))
                  (and ,payload (list :status 'ready :data ,payload))))))
     ,@body))

(defmacro gascity-test-beads-sling--with-no-spawn (&rest body)
  "Run BODY with every gc runner signalling instead of spawning.
The provider and validator paths are cache-only (REQ-007, D9); a read
or run here is a test failure, not a slow test."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'gascity-reader-read)
              (lambda (&rest _) (error "Synchronous gc read")))
             ((symbol-function 'gascity-reader-read-async)
              (lambda (&rest _) (error "Asynchronous gc read")))
             ((symbol-function 'gascity-reader-run-async)
              (lambda (&rest _) (error "Asynchronous gc run"))))
     ,@body))

(defmacro gascity-test-beads-sling--with-city (&rest body)
  "Run BODY in the suite's city with an empty formula recipe cache."
  (declare (indent 0) (debug t))
  `(let ((default-directory gascity-test-beads-sling--city)
         (gascity-context-city gascity-test-beads-sling--city)
         (gascity-beads-sling--remembered-city nil)
         (gascity-formula-recipe-cache nil))
     ,@body))

(defun gascity-test-beads-sling--city-groups ()
  "Return the `[City]' groups currently contributed to the beads menu."
  (seq-filter (lambda (group) (equal (aref group 0) "City"))
              (beads-menu-provider-groups)))

(defun gascity-test-beads-sling--suffixes (group)
  "Return GROUP's suffix specs as a list."
  (append (seq-drop (append group nil) 1) nil))

(defun gascity-test-beads-sling--target (name &optional targets)
  "Return the collected target named NAME, or nil.
TARGETS defaults to what `gascity-beads-sling-targets' contributes.
Compares the target objects' `name' slots, not the names."
  (seq-find (lambda (target) (equal (oref target name) name))
            (or targets (gascity-beads-sling-targets))))

(defun gascity-test-beads-sling--recipe (name steps &optional vars)
  "Decode a `gascity-formula' NAME with raw STEPS and VARS.
STEPS stay raw step alists so the gascity trap detector reads their
`metadata' exactly as it reads a cached recipe's."
  (gascity-domain-decode
   'gascity-formula `((name . ,name)
                      (steps . ,steps)
                      ,@(and vars `((vars . ,vars))))))

;;; The [City] menu group and additive actions (B5a)

(ert-deftest gascity-test-beads-sling-menu-and-actions ()
  "One `[City]' group with free keys and an additive `V' action (B5a)."
  (gascity-test-with-store-stubs reads actions
    (gascity-beads-sling-register)
    (gascity-beads-sling-register)
    (should-not reads)
    (should-not actions)
    (let* ((groups (gascity-test-beads-sling--city-groups))
           (group (car groups))
           (suffixes (gascity-test-beads-sling--suffixes group)))
      (should (= 1 (length groups)))
      (should (equal (mapcar #'car suffixes) '("E" "J" "K" "A" "Q")))
      (should (equal (mapcar (lambda (suffix) (nth 1 suffix)) suffixes)
                     '("Cockpit" "Rig dashboard"
                       "Rig dashboard…" "Agents" "Sling (gascity menu)")))
      (should (eq (nth 2 (assoc "E" suffixes)) 'gascity-dashboard))
      (should (eq (nth 2 (assoc "J" suffixes))
                  'gascity-rig-dashboard-at-point))
      (should (eq (nth 2 (assoc "K" suffixes)) 'gascity-rig-dashboard))
      (should (eq (nth 2 (assoc "A" suffixes)) 'gascity-agents))
      (should (eq (nth 2 (assoc "Q" suffixes)) 'gascity-sling-dispatch))
      ;; Every chosen key is free in `beads-dispatch' and none of the
      ;; beads.el keys (notably the delegated `S') is shadowed here.
      (should-not (seq-intersection (mapcar #'car suffixes)
                                    '("S" "RET" "TAB"))))
    (should (equal (gascity-beads-sling--actions :list)
                   '(("V" . gascity-dashboard))))
    (should (equal (gascity-beads-sling--actions :show)
                   '(("V" . gascity-dashboard))))
    (should-not (gascity-beads-sling--actions :menu))
    (let ((contributed (beads-actions-provider-actions :list)))
      (should (member '("V" . gascity-dashboard) contributed))
      (should-not (assoc "S" contributed))
      (should-not (assoc "RET" contributed))
      (should-not (assoc "TAB" contributed)))))

;;; Target provider (REQ-002, REQ-007; AC-4, AC-5)

(ert-deftest gascity-test-beads-sling-provider-warm-roster ()
  "A warm `gc agent list' yields qualified gc targets, cache-only.
Every target names its `gc' backend and carries rig, city, qualified
name and source in `:metadata'; one rig agent and one city-level
target are present, and no reader ran."
  (gascity-test-beads-sling--with-city
    (gascity-test-beads-sling--with-cached-store
        gascity-test-beads-sling--agent-list
      (gascity-test-beads-sling--with-no-spawn
        (let* ((targets (gascity-beads-sling-targets))
               (worker (gascity-test-beads-sling--target
                        "gascity.el/gc.implementation-worker" targets))
               (mayor (gascity-test-beads-sling--target "mayor" targets)))
          (should (= 2 (length targets)))
          (should (seq-every-p #'beads-sling-target-p targets))
          (dolist (target targets)
            (should (equal (oref target backend) "gc")))
          ;; The rig agent: qualified name, rig scope, the metadata
          ;; carrier, and the payload's role as its description.
          (should (equal (oref worker kind) 'agent))
          (should (equal (oref worker scope) "gascity.el"))
          (should (equal (oref worker description) "worker"))
          (should (equal (plist-get (oref worker metadata) :rig)
                         "gascity.el"))
          (should (equal (plist-get (oref worker metadata) :city)
                         gascity-test-beads-sling--city))
          (should (equal (plist-get (oref worker metadata) :qualified-name)
                         "gascity.el/gc.implementation-worker"))
          (should (eq (plist-get (oref worker metadata) :source) 'roster))
          ;; The city-level target has no rig scope.
          (should (null (oref mayor scope)))
          (should (null (plist-get (oref mayor metadata) :rig)))
          (should (equal (plist-get (oref mayor metadata) :city)
                         gascity-test-beads-sling--city))
          (should (equal (oref mayor description) "Mayor")))))))

(ert-deftest gascity-test-beads-sling-provider-rig-repo-directory ()
  "AC-4 extension: a rig repository outside the city tree resolves.
The beads delegation contract pins `default-directory' to the rig's
repository, which lives outside the city tree; the memoized rigs — not
a file-system walk — bridge it to the city, and the provider still
answers from the cache with no spawn."
  (let ((default-directory "/work/gascity.el/")
        (gascity-context-city nil)
        (gascity-beads-sling--remembered-city nil)
        (gascity-formula-recipe-cache nil))
    (cl-letf (((symbol-function 'gascity-context-known-city-roots)
               (lambda () (list gascity-test-beads-sling--city)))
              ((symbol-function 'gascity-context-remember-city-root)
               (lambda (root) root))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional _root)
                 (list (gascity-rig :name "gascity.el" :prefix "ga"
                                    :path "/work/gascity.el")))))
      (gascity-test-beads-sling--with-cached-store
          gascity-test-beads-sling--agent-list
        (gascity-test-beads-sling--with-no-spawn
          (let* ((targets (gascity-beads-sling-targets))
                 (worker (gascity-test-beads-sling--target
                          "gascity.el/gc.implementation-worker" targets)))
            (should (= 2 (length targets)))
            (should (equal (plist-get (oref worker metadata) :city)
                           gascity-test-beads-sling--city))))))))

(ert-deftest gascity-test-beads-sling-provider-cold-store ()
  "AC-5: a cold store answers nil in the same call and still renders.
The provider contributes nothing, no reader runs, and beads' sling
transient still parses and shows its Who stage."
  (gascity-test-beads-sling--with-city
    (gascity-test-beads-sling--with-cached-store nil
      (gascity-test-beads-sling--with-no-spawn
        (should-not (gascity-beads-sling-targets))
        ;; A cold store must not break the menu's render path, which
        ;; peeks the target list for its default.  The active transient
        ;; state is bound locally: a batch `transient-quit-all' cannot
        ;; restore `overriding-terminal-local-map', and a leaked map
        ;; would shadow every later test's key lookups.
        (let ((overriding-terminal-local-map overriding-terminal-local-map)
              (transient--prefix nil)
              (beads-sling-target-functions
               (list #'gascity-beads-sling-targets)))
          (unwind-protect
              (progn
                (transient-setup
                 'beads-sling--transient nil nil
                 :scope (list :work "ga-1" :work-title nil
                              :directory gascity-test-beads-sling--city
                              :formula nil :recipe nil :target nil))
                (with-current-buffer " *transient*"
                  (should (string-match-p "Who" (buffer-string)))))
            (ignore-errors (transient-quit-all))))))))

;;; Backend argv shapes (REQ-003, REQ-004, REQ-007; AC-6, AC-7, AC-8)

(ert-deftest gascity-test-beads-sling-backend-plain-argv ()
  "The plain shape runs exactly `gc sling TARGET BEAD' (as JSON)."
  (let ((default-directory gascity-test-beads-sling--city))
    (gascity-test-with-store-stubs reads actions
      (gascity-test-beads-sling--with-cached-store nil
        (should-not
         (gascity-beads-sling--dispatch
          nil "ga-1" nil
          (list :work "ga-1" :shape 'plain
                :target "gascity.el/gc.implementation-worker")))
        (should-not reads)
        (should (= 1 (length actions)))
        (should (equal (car (car actions))
                       '("sling" "gascity.el/gc.implementation-worker"
                         "ga-1" "--json")))
        ;; Started, not run: the target is pending on the action lane.
        (should (gascity-store-action-pending-p
                 "gascity.el/gc.implementation-worker"
                 gascity-test-beads-sling--city))))))

(ert-deftest gascity-test-beads-sling-backend-on-argv ()
  "The `on' shape runs `--on FORMULA' with each set var, in order."
  (let ((default-directory gascity-test-beads-sling--city))
    (gascity-test-with-store-stubs _reads actions
      (gascity-test-beads-sling--with-cached-store nil
        (gascity-beads-sling--dispatch
         nil "ga-1" nil
         (list :work "ga-1" :shape 'on :formula "do-work"
               :target "gascity.el/gc.implementation-worker"
               :values '(("artifact_root" . "plans/beads-sling/")
                         ("summary_path" . "plans/beads-sling/summary.md"))))
        (should (= 1 (length actions)))
        ;; `--json' follows the positionals (the backend asks for the
        ;; parsed payload); the routing flags keep their own order.
        (should (equal (car (car actions))
                       '("sling" "gascity.el/gc.implementation-worker"
                         "ga-1" "--json" "--on" "do-work"
                         "--var" "artifact_root=plans/beads-sling/"
                         "--var" "summary_path=plans/beads-sling/summary.md")))))))

(ert-deftest gascity-test-beads-sling-backend-formula-argv ()
  "The `formula' shape emits `--formula', never an empty target.
An explicit target is positional; a targetless launch starts with the
formula instead."
  (let ((default-directory gascity-test-beads-sling--city))
    (gascity-test-with-store-stubs _reads actions
      (gascity-test-beads-sling--with-cached-store nil
        ;; Targeted formula-only run.
        (gascity-beads-sling--dispatch
         nil "ga-1" nil
         (list :shape 'formula :formula "do-work"
               :target "gascity.el/gc.implementation-worker"))
        (should (equal (car (car actions))
                       '("sling" "gascity.el/gc.implementation-worker"
                         "do-work" "--json" "--formula")))
        ;; Targetless formula-only run: the formula is the first
        ;; positional argument; no empty string is emitted.
        (gascity-store-clear)
        (gascity-beads-sling--dispatch
         nil nil nil
         (list :shape 'formula :formula "do-work"))
        (should (= 2 (length actions)))
        (should (equal (car (car actions))
                       '("sling" "do-work" "--json" "--formula")))
        (should-not (member "" (car (car actions))))))))

(ert-deftest gascity-test-beads-sling-backend-targetless-on-refuses ()
  "A targetless `on' sling refuses with `user-error' before the runner."
  (let ((default-directory gascity-test-beads-sling--city))
    (gascity-test-with-store-stubs _reads actions
      (gascity-test-beads-sling--with-cached-store nil
        (should-error
         (gascity-beads-sling--dispatch
          nil "ga-1" nil
          (list :work "ga-1" :shape 'on :formula "do-work" :target nil))
         :type 'user-error)
        (should-not actions)))))

(ert-deftest gascity-test-beads-sling-backend-plain-echo-and-invalidate ()
  "A completed plain sling echoes the bead and its Who, then refreshes.
The registered backend suppresses the runner's own invalidation and
invalidates each affected store kind exactly once."
  (let ((default-directory gascity-test-beads-sling--city)
        (messages nil)
        (invalidations nil))
    (gascity-test-with-store-stubs _reads actions
      (gascity-test-beads-sling--with-cached-store nil
        (cl-letf (((symbol-function 'message)
                   (lambda (format-string &rest args)
                     (push (apply #'format format-string args) messages)))
                  ((symbol-function 'gascity-store-invalidate)
                   (lambda (&rest args) (push args invalidations))))
          (gascity-beads-sling--dispatch
           nil "ga-1" nil
           (list :work "ga-1" :shape 'plain
                 :target "gascity.el/gc.implementation-worker"))
          (should (= 1 (length actions)))
          ;; The action answers successfully.
          (funcall (nth 1 (car actions))
                   (list :exit-code 0 :stdout "{}" :stderr ""
                         :executable "gc"))
          (should (equal messages
                         '("Slung ga-1 to gascity.el/gc.implementation-worker")))
          ;; One invalidation per affected store kind, for this city.
          (setq invalidations (nreverse invalidations))
          (should (equal (mapcar (lambda (args) (plist-get args :kind))
                                 invalidations)
                         gascity-beads-sling--invalidate-kinds))
          (dolist (args invalidations)
            (should (equal (plist-get args :dir)
                           gascity-test-beads-sling--city))
            (should (eq (plist-get args :refetch) t))))))))

(ert-deftest gascity-test-beads-sling-backend-failure-echo ()
  "A failed sling keeps the inherited first-stderr-line echo.
No success closure runs, so nothing is invalidated."
  (let ((default-directory gascity-test-beads-sling--city)
        (messages nil)
        (invalidations nil))
    (gascity-test-with-store-stubs _reads actions
      (gascity-test-beads-sling--with-cached-store nil
        (cl-letf (((symbol-function 'message)
                   (lambda (format-string &rest args)
                     (push (apply #'format format-string args) messages)))
                  ((symbol-function 'gascity-store-invalidate)
                   (lambda (&rest args) (push args invalidations))))
          (gascity-beads-sling--dispatch
           nil "ga-1" nil
           (list :work "ga-1" :shape 'plain
                 :target "gascity.el/gc.implementation-worker"))
          (funcall (nth 1 (car actions))
                   (list :exit-code 1 :stdout "" :stderr "no such target\n"))
          ;; The inherited echo names the first stderr line; the whole
          ;; stderr lands in the city's action log.
          (should (seq-some
                   (lambda (text) (string-match-p "failed: no such target" text))
                   messages))
          (with-current-buffer
              (get-buffer-create
               (gascity-store-log-buffer-name gascity-test-beads-sling--city))
            (should (string-match-p "no such target" (buffer-string))))
          (should-not invalidations))))))

;;; Advisory validators (REQ-005, AC-10)

(ert-deftest gascity-test-beads-sling-validator-cross-store ()
  "A cross-store route yields exactly one warning, never a refusal.
The route is written by `gascity-sling--cross-store-warning' and the
whole validator hook stays advisory."
  (gascity-test-beads-sling--with-city
    (cl-letf (((symbol-function 'gascity-context-remember-city-root)
               (lambda (root) root))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional _root)
                 (list (gascity-rig :name "gascity.el" :prefix "ga")
                       (gascity-rig :name "hello-world" :prefix "hw")))))
      (gascity-test-beads-sling--with-cached-store nil
        (gascity-test-beads-sling--with-no-spawn
          (let* ((context (list :work "ga-1" :shape 'plain
                                :target "hello-world/gc.implementation-worker"))
                 (warnings (beads-sling-validate context)))
            (should (= 1 (length warnings)))
            (should (string-match-p
                     (concat "cross-store route: bead ga-1 lives in the "
                             "gascity.el store but the target reads the "
                             "hello-world store")
                     (car warnings)))))))))

(ert-deftest gascity-test-beads-sling-validator-missing-vars ()
  "A missing required formula var yields exactly one warning, never a refusal."
  (gascity-test-beads-sling--with-city
    (gascity-test-beads-sling--with-cached-store nil
      (gascity-test-beads-sling--with-no-spawn
        (let* ((recipe (beads-formula
                        :name "do-work"
                        :vars (list (beads-formula-var
                                     :name "artifact_root" :required t))))
               (context (list :work "ga-1" :shape 'on :formula "do-work"
                              :recipe recipe :target "gascity.el/agent"
                              :values nil))
               (warnings (beads-sling-validate context)))
          ;; The single warning is the vars one (the route is same-store
          ;; and the target is not city-scoped).
          (should (equal warnings
                         '("Missing required vars: artifact_root"))))))))

(ert-deftest gascity-test-beads-sling-validator-clean-input ()
  "A clean, same-store, fully-answered input produces no warnings."
  (gascity-test-beads-sling--with-city
    (cl-letf (((symbol-function 'gascity-context-remember-city-root)
               (lambda (root) root))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional _root)
                 (list (gascity-rig :name "gascity.el" :prefix "ga")))))
      (gascity-test-beads-sling--with-cached-store nil
        (gascity-test-beads-sling--with-no-spawn
          (should-not
           (beads-sling-validate
            (list :work "ga-1" :shape 'plain :target "gascity.el/agent"))))))))

(ert-deftest gascity-test-beads-sling-validator-trap-needs-warm-gascity-cache ()
  "The v2 target trap is silent on a cold gascity recipe cache, and
fires once the recipe is cached — from cached data only."
  (gascity-test-beads-sling--with-city
    (cl-letf (((symbol-function 'gascity-context-scope-key)
               (lambda (&optional _dir) gascity-test-beads-sling--city))
              ((symbol-function 'gascity-context-remember-city-root)
               (lambda (root) root)))
      (gascity-test-beads-sling--with-cached-store
          gascity-test-beads-sling--agent-list
        (gascity-test-beads-sling--with-no-spawn
          (let* ((recipe
                  (gascity-test-beads-sling--recipe
                   "build-basic"
                   '(((id . "s1")
                      (metadata . ((gc.run_target . "gc.run-operator")))))))
                 (context (list :work "ga-1" :shape 'on :formula "build-basic"
                                :target "mayor" :values nil))
                 (cold gascity-formula-recipe-cache))
            ;; Cold gascity cache: the beads recipe alone never fires the
            ;; gascity-only trap.
            (should (null gascity-formula-recipe-cache))
            (should-not (gascity-beads-sling--validate-target-trap context))
            ;; Warm gascity cache: a city-scoped target on a v2 formula
            ;; warns once, suggesting a rig the roster has agents for.
            (let ((gascity-formula-recipe-cache
                   `((,(cons gascity-test-beads-sling--city "build-basic")
                      . ,recipe))))
              (let ((warning (gascity-beads-sling--validate-target-trap
                              context)))
                (should (stringp warning))
                (should (string-match-p "formulas v2 target" warning))
                (should (string-match-p "gascity.el/\\* agent" warning))))
            (setq gascity-formula-recipe-cache cold)))))))

;;; Registration idempotence and the delegation contract (REQ-007,
;;; REQ-008; AC-12, AC-13)

(ert-deftest gascity-test-beads-sling-registration-idempotent ()
  "Registering twice leaves one backend, one `[City]' group, a stable
target list, and spawns no gc process."
  (gascity-test-beads-sling--with-city
    (gascity-test-beads-sling--with-cached-store
        gascity-test-beads-sling--agent-list
      (gascity-test-beads-sling--with-no-spawn
        (let ((beads-sling-target-functions
               (list #'gascity-beads-sling-targets)))
          (gascity-beads-sling-register)
          (let ((targets-after-first (length (beads-sling-targets))))
            (gascity-beads-sling-register)
            (should (equal (length (beads-sling-targets))
                           targets-after-first))
            ;; One provider entry, one backend, one menu group.
            (should (= 1 (seq-count
                          (lambda (function)
                            (eq function #'gascity-beads-sling-targets))
                          beads-sling-target-functions)))
            (should (= 1 (length
                          (seq-filter
                           (lambda (backend)
                             (equal (oref backend name) "gc"))
                           (beads-sling-backend-list)))))
            (should (= 1 (length (gascity-test-beads-sling--city-groups))))
            (should gascity-beads-sling--registered)))))))

(ert-deftest gascity-test-beads-sling-delegation-s-then-dispatch ()
  "beads' `S' seeds the transient, then a gc target dispatch runs the
expected argv: the delegation contract end to end with a stubbed gc."
  (gascity-test-beads-sling--with-city
    (gascity-test-beads-sling--with-cached-store
        gascity-test-beads-sling--agent-list
      (gascity-test-with-store-stubs _reads actions
        (let ((scope nil))
          (cl-letf (((symbol-function 'beads-sling--bead-at-point)
                     (lambda () "ga-1"))
                    ((symbol-function 'transient-setup)
                     (lambda (_name _levels _suffixes &rest args)
                       (setq scope (plist-get args :scope)))))
            ;; `S' opens the sling transient with the bead at point.
            (beads-sling-for-issue)
            (should (equal (plist-get scope :work) "ga-1"))))
        ;; The Who picker's gc target, then dispatch exactly as the
        ;; beads transient's `s' does: through the registered backend.
        (let* ((target (gascity-test-beads-sling--target
                        "gascity.el/gc.implementation-worker"))
               (context (list :work "ga-1" :shape 'plain
                              :target (oref target name))))
          (should (equal (oref target backend) "gc"))
          (beads-sling-dispatch target "ga-1" nil context)
          (should (= 1 (length actions)))
          (should (equal (car (car actions))
                         '("sling" "gascity.el/gc.implementation-worker"
                           "ga-1" "--json"))))))))

;;; After-action refresh (B5b)

(ert-deftest gascity-test-beads-sling-after-action-invalidates-once ()
  "Every beads mutation invalidates the bead-derived kinds exactly once."
  (dolist (action '(close claim reopen set-status set-priority create update))
    (let (calls)
      (cl-letf (((symbol-function 'gascity-store-invalidate)
                 (lambda (&rest args) (push args calls)))
                ((symbol-function 'gascity-beads-sling--after-action-root)
                 (lambda (&optional _dir) "/city/")))
        (gascity-beads-sling--after-action action '("ga-1")))
      (should (= 1 (length calls)))
      (let ((args (car calls)))
        (should (equal "/city/" (plist-get args :dir)))
        (should (equal '(bd convoy) (plist-get args :kind)))
        (should (eq t (plist-get args :refetch)))))))

(ert-deftest gascity-test-beads-sling-after-action-kind-route ()
  "The invalidated kinds are the ones gc routes its `bead.*' events to."
  (should (equal (alist-get "bead." gascity-store-event-routes nil nil #'equal)
                 gascity-beads-sling--after-action-kinds)))

(ert-deftest gascity-test-beads-sling-after-action-root-from-rig-memo ()
  "A rig-repo directory resolves to the city root that owns it.
The beads delegation contract pins the mutating buffer to the rig's
repository, outside the city tree; the memoized rigs bridge the two."
  (cl-letf (((symbol-function 'gascity-context-city-root-cached)
             (lambda (&optional _dir) nil))
            ((symbol-function 'gascity-context-known-city-roots)
             (lambda () '("/city/")))
            ((symbol-function 'gascity-context-remember-city-root)
             (lambda (root) root))
            ((symbol-function 'gascity-rigs-cached)
             (lambda (&optional _root) '(fake-rig)))
            ((symbol-function 'gascity-rig-path)
             (lambda (_rig) "/city/rigs/gastown.el")))
    (should (equal "/city/"
                   (gascity-beads-sling--after-action-root
                    "/city/rigs/gastown.el/worktrees/ga-1/")))))

(ert-deftest gascity-test-beads-sling-after-action-root-inside-city ()
  "A directory inside a known city tree resolves to that city root."
  (cl-letf (((symbol-function 'gascity-context-city-root-cached)
             (lambda (&optional _dir) nil))
            ((symbol-function 'gascity-context-known-city-roots)
             (lambda () '("/city/")))
            ((symbol-function 'gascity-rigs-cached)
             (lambda (&optional _root) nil)))
    (should (equal "/city/"
                   (gascity-beads-sling--after-action-root
                    "/city/rigs/gastown.el/")))))

(ert-deftest gascity-test-beads-sling-after-action-root-cold ()
  "With no known city the mutation's own directory is the store root.
Cache-only: no file walk and no gc spawn, so a beads-only session is
harmless."
  (cl-letf (((symbol-function 'gascity-context-city-root-cached)
             (lambda (&optional _dir) nil))
            ((symbol-function 'gascity-context-known-city-roots)
             (lambda () nil))
            ((symbol-function 'gascity-rigs-cached)
             (lambda (&optional _root) (error "no read expected"))))
    (should (equal (file-name-as-directory (expand-file-name "/rig/"))
                   (gascity-beads-sling--after-action-root "/rig/")))))

(provide 'gascity-beads-sling-test)
;;; gascity-beads-sling-test.el ends here
