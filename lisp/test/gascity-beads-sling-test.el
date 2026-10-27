;;; gascity-beads-sling-test.el --- Gas City registration on beads.el sling -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Tests for the downstream registration module
;; (`gascity-beads-sling'): load order, the idempotent registration of
;; beads.el's six sling seams, the load-time inertness requirement (no gc
;; spawn or store read while registering), the cache-only city resolution
;; and target provider (B2), and the post-mutation refresh hook (B5b):
;; one invalidation per city kind and per affected rig root, for every
;; delivered action, with no beads read, mutation or timer.
;;
;; Non-blocking guard decision (B6): `gascity-beads-sling--dispatch' is
;; deliberately absent from `gascity-test-store--verbs'.  It is not an
;; interactive, input-free verb: beads.el's sling transient gathers the
;; shape, target, formula and vars before calling the registered backend,
;; so there is no prompt to answer and nothing for the guard to pin.  Its
;; non-blocking launch is covered here by
;; `gascity-test-beads-sling-dispatch-async-launch' instead.  Do not read
;; this omission as an oversight; add guard entries only for new
;; interactive input-free verbs.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)
(require 'beads-menu)
(require 'beads-actions)

(declare-function gascity-beads-sling-register "gascity-beads-sling" ())
(declare-function gascity-beads-sling-targets "gascity-beads-sling" ())
(declare-function gascity-beads-sling-validate "gascity-beads-sling" (context))
(declare-function gascity-beads-sling-actions "gascity-beads-sling" (context))
(declare-function gascity-beads-sling--menu-group "gascity-beads-sling" ())
(declare-function beads-sling-backend-get "beads-sling" (name))
(declare-function beads-menu-provider-groups "beads-menu" ())
(declare-function beads-actions-provider-actions "beads-actions" (context))

(defvar gascity-beads-sling--registered)

(defun gascity-beads-sling-test--count (function functions)
  "Return how many times FUNCTION appears in FUNCTIONS."
  (seq-count (lambda (fn) (eq fn function)) functions))

(ert-deftest gascity-test-beads-sling-load-order ()
  "The entry point loads the registration module after the action layer."
  (should (featurep 'gascity-beads-sling))
  (should gascity-beads-sling--registered))

(ert-deftest gascity-test-beads-sling-register-idempotent ()
  "Registering twice leaves one backend, one menu group and one hook entry."
  (gascity-beads-sling-register)
  (gascity-beads-sling-register)
  (let ((backend (beads-sling-backend-get "gc")))
    (should backend)
    (should (eq (oref backend dispatch) #'gascity-beads-sling--dispatch))
    (should (equal (oref backend name) "gc"))
    (should (equal (oref backend description) "Gas City (gc sling)")))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling--menu-group beads-menu-providers)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling-targets
                beads-sling-target-functions)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling-validate beads-sling-validators)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling-actions beads-action-providers)))
  (should (= 1 (gascity-beads-sling-test--count
                #'gascity-beads-sling--after-action
                beads-after-action-functions))))

(ert-deftest gascity-test-beads-sling-no-spawn-at-load ()
  "Registration only touches the registration tables, never the gc boundary."
  (cl-letf (((symbol-function 'gascity-reader-read)
             (lambda (&rest _) (error "registration spawned a sync read")))
            ((symbol-function 'gascity-reader-read-async)
             (lambda (&rest _) (error "registration spawned an async read")))
            ((symbol-function 'gascity-reader-run-async)
             (lambda (&rest _) (error "registration spawned an action"))))
    (gascity-beads-sling-register)
    (should (beads-sling-backend-get "gc"))))

;;; Target provider and city resolution (plan §B2, REQ-002/REQ-007)

(defconst gascity-beads-sling-test--city "/tmp/beads-sling-city/"
  "The warm city of the provider tests.")

(defconst gascity-beads-sling-test--other-city "/tmp/beads-sling-other-city/"
  "A second known city, for the resolution-order test.")

(defconst gascity-beads-sling-test--rig "/tmp/beads-sling-rig/"
  "A rig repository outside every city tree (plan F4).")

(defconst gascity-beads-sling-test--agents
  '((agents . [((name . "dog-1") (qualified_name . "bd.dog-1")
                (scope . "city"))
               ((name . "implementation-worker")
                (qualified_name . "gascity.el/gc.implementation-worker")
                (scope . "rig"))]))
  "A `gc agent list' payload: one city-scoped and one rig-scoped agent.")

(defun gascity-beads-sling-test--rigs (city)
  "Return the memoized rig list for CITY, or nil for another city."
  (when (equal city gascity-beads-sling-test--city)
    (list (gascity-rig :name "gascity.el"
                       :prefix "gce"
                       :path (directory-file-name gascity-beads-sling-test--rig)))))

(ert-deftest gascity-test-beads-sling-provider-warm ()
  "A warm store yields one gc target per roster agent, from cache only."
  (let ((gascity-context-city gascity-beads-sling-test--city)
        (gascity-beads-sling--city nil)
        (reads nil)
        (peeks nil))
    (cl-letf (((symbol-function 'gascity-store-get)
               (lambda (args &optional dir)
                 (push (list args dir) reads)
                 (list :status 'ready
                       :data gascity-beads-sling-test--agents)))
              ((symbol-function 'gascity-store-peek)
               (lambda (&rest _) (push :peek peeks) nil))
              ((symbol-function 'gascity-reader-read)
               (lambda (&rest _) (error "Provider spawned a sync read")))
              ((symbol-function 'gascity-reader-read-async)
               (lambda (&rest _) (error "Provider spawned an async read")))
              ((symbol-function 'gascity-reader-run-async)
               (lambda (&rest _) (error "Provider ran an action")))
              ((symbol-function 'file-exists-p)
               (lambda (&rest _) (error "Provider probed the file system"))))
      (let* ((targets (gascity-beads-sling-targets))
             (city-target (seq-find (lambda (target)
                                      (equal (oref target name) "bd.dog-1"))
                                    targets))
             (rig-target (seq-find (lambda (target)
                                     (equal (oref target name)
                                            "gascity.el/gc.implementation-worker"))
                                   targets)))
        (should (equal (mapcar (lambda (target) (oref target name)) targets)
                       '("bd.dog-1" "gascity.el/gc.implementation-worker")))
        (should (eq (oref city-target kind) 'agent))
        (should (equal (oref city-target backend) "gc"))
        (should-not (oref city-target scope))
        (should (equal (oref rig-target scope) "gascity.el"))
        (should (equal (oref city-target description) "bd.dog-1"))
        (should (equal (oref city-target metadata)
                       (list :rig nil
                             :city gascity-beads-sling-test--city
                             :qualified-name "bd.dog-1"
                             :source 'roster)))
        (should (equal reads
                       (list (list '("agent" "list")
                                   gascity-beads-sling-test--city))))
        (should-not peeks)))))

(ert-deftest gascity-test-beads-sling-provider-cold ()
  "A cold store answers nil in the same call, without spawning anything."
  (let ((gascity-context-city gascity-beads-sling-test--city)
        (gascity-beads-sling--city nil)
        (spawns nil))
    (cl-letf (((symbol-function 'gascity-store-get)
               (lambda (&rest _) nil))
              ((symbol-function 'gascity-store-peek)
               (lambda (&rest _) (push :peek spawns) nil))
              ((symbol-function 'gascity-reader-read)
               (lambda (&rest _) (push :read spawns) nil))
              ((symbol-function 'gascity-reader-read-async)
               (lambda (&rest _) (push :read-async spawns) nil))
              ((symbol-function 'gascity-reader-run-async)
               (lambda (&rest _) (push :run spawns) nil)))
      (should-not (gascity-beads-sling-targets))
      (should-not spawns))))

(ert-deftest gascity-test-beads-sling-provider-rig-outside-city ()
  "A bead buffer in a rig repository still resolves its city (plan F4)."
  (let ((default-directory gascity-beads-sling-test--rig)
        (gascity-context-city nil)
        (gascity-beads-sling--city nil))
    (cl-letf (((symbol-function 'gascity-context-known-city-roots)
               (lambda () (list gascity-beads-sling-test--city)))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional dir)
                 (gascity-beads-sling-test--rigs dir)))
              ((symbol-function 'gascity-store-get)
               (lambda (&rest _)
                 (list :status 'ready
                       :data gascity-beads-sling-test--agents)))
              ((symbol-function 'gascity-reader-read)
               (lambda (&rest _) (error "Provider spawned a sync read")))
              ((symbol-function 'gascity-reader-run-async)
               (lambda (&rest _) (error "Provider ran an action")))
              ((symbol-function 'file-exists-p)
               (lambda (&rest _) (error "Provider probed the file system"))))
      (should (equal (mapcar (lambda (target) (oref target name))
                             (gascity-beads-sling-targets))
                     '("bd.dog-1" "gascity.el/gc.implementation-worker"))))))

(ert-deftest gascity-test-beads-sling-provider-unknown-city ()
  "No warm city means nil, and nothing is probed to find one."
  (let ((default-directory "/tmp/beads-sling-elsewhere/")
        (gascity-context-city nil)
        (gascity-beads-sling--city nil))
    (cl-letf (((symbol-function 'gascity-context-known-city-roots) #'ignore)
              ((symbol-function 'gascity-store-get)
               (lambda (&rest _) (error "An unresolved city read the store")))
              ((symbol-function 'file-exists-p)
               (lambda (&rest _) (error "Resolved the city with file-exists-p")))
              ((symbol-function 'file-truename)
               (lambda (&rest _) (error "Resolved the city with file-truename")))
              ((symbol-function 'file-in-directory-p)
               (lambda (&rest _) (error "Used file-in-directory-p"))))
      (should-not (gascity-beads-sling--city))
      (should-not (gascity-beads-sling-targets)))))

(ert-deftest gascity-test-beads-sling-city-resolution-order ()
  "The override wins, then a known city that owns DIR, then the memory."
  (let ((dir gascity-beads-sling-test--rig)
        (gascity-beads-sling--city gascity-beads-sling-test--other-city))
    (cl-letf (((symbol-function 'gascity-rigs-cached)
               (lambda (&optional city) (gascity-beads-sling-test--rigs city))))
      ;; 1. `gascity-context-city' is authoritative.
      (let ((gascity-context-city gascity-beads-sling-test--city))
        (cl-letf (((symbol-function 'gascity-context-known-city-roots)
                   (lambda () (list gascity-beads-sling-test--other-city))))
          (should (equal (gascity-beads-sling--city dir)
                         gascity-beads-sling-test--city))))
      ;; 2. A known root whose rig memo owns DIR, and the city root itself.
      (let ((gascity-context-city nil))
        (cl-letf (((symbol-function 'gascity-context-known-city-roots)
                   (lambda () (list gascity-beads-sling-test--city))))
          (should (equal (gascity-beads-sling--city dir)
                         gascity-beads-sling-test--city))
          (should (equal (gascity-beads-sling--city
                          (concat gascity-beads-sling-test--city "beads/"))
                         gascity-beads-sling-test--city))))
      ;; 3. Nothing known matches: the remembered city answers.
      (let ((gascity-context-city nil))
        (cl-letf (((symbol-function 'gascity-context-known-city-roots) #'ignore))
          (should (equal (gascity-beads-sling--city dir)
                         gascity-beads-sling-test--other-city)))))))

;;; Backend dispatch and argv (plan §B3a, REQ-003/REQ-004/REQ-007)

(defconst gascity-beads-sling-test--target-name
  "gascity.el/gc.implementation-worker"
  "The gc sling target the dispatch tests pick.")

(defun gascity-beads-sling-test--target (&optional name)
  "Return a gc `beads-sling-target' named NAME, or the default one."
  (beads-sling-target
   :name (or name gascity-beads-sling-test--target-name)
   :kind 'agent
   :scope "gascity.el"
   :backend "gc"
   :description (or name gascity-beads-sling-test--target-name)))

(defmacro gascity-beads-sling-test--with-launch (&rest body)
  "Run BODY with the dispatch's launch seam captured in `launched'.
`launched' is a plist of the last `gascity-command-act-async' call —
`:command', its `:argv' (`gascity-command-arguments'), `:args' (the
keyword arguments, including the `:on-success' closure), `:target' and
`:dir' — and `launch-count' counts the calls, so a test can prove a
dispatch started exactly nothing.  The city resolver and the Who
derivation are stubbed to the test fixtures, so no store or file is
read."
  (declare (indent 0) (debug t))
  `(let ((launched nil)
         (launch-count 0))
     (cl-letf (((symbol-function 'gascity-command-act-async)
                (lambda (command &rest args)
                  (setq launch-count (1+ launch-count))
                  (setq launched
                        (list :command command
                              :argv (gascity-command-arguments command)
                              :args args
                              :target (plist-get args :target)
                              :dir (plist-get args :dir)))
                  nil))
               ((symbol-function 'gascity-beads-sling--city)
                (lambda (&rest _) gascity-beads-sling-test--city))
               ((symbol-function 'gascity-sling--roster) #'ignore)
               ((symbol-function 'gascity-sling--derive-target)
                (lambda (&rest _) nil)))
       ,@body)))

(ert-deftest gascity-test-beads-sling-dispatch-plain-argv ()
  "A plain dispatch slings the bare bead to the chosen target."
  (gascity-beads-sling-test--with-launch
    (should-not (gascity-beads-sling--dispatch
                 (gascity-beads-sling-test--target) "ga-1" nil
                 (list :work "ga-1" :shape 'plain)))
    (should (= 1 launch-count))
    ;; `--json' rides after the positionals (the global options come
    ;; first): the launch asks for a parsed dispatch result (plan §B3,
    ;; `json t') so a formula shape can echo the created workflow root.
    (should (equal (plist-get launched :argv)
                   (list "sling" gascity-beads-sling-test--target-name
                         "ga-1" "--json")))
    (should (equal (plist-get launched :target)
                   gascity-beads-sling-test--target-name))
    (should (equal (plist-get launched :dir)
                   gascity-beads-sling-test--city))
    (should-not (gascity-command-validate (plist-get launched :command)))))

(ert-deftest gascity-test-beads-sling-dispatch-on-argv ()
  "A targeted formula dispatch emits `--on' plus only non-blank vars."
  (gascity-beads-sling-test--with-launch
    (should-not (gascity-beads-sling--dispatch
                 (gascity-beads-sling-test--target) "ga-1" nil
                 (list :work "ga-1" :formula "mol-x" :shape 'on
                       :values '(("alpha" . "one") ("blank" . "")
                                 ("beta" . "two")))))
    (should (= 1 launch-count))
    (should (equal (plist-get launched :argv)
                   (list "sling" gascity-beads-sling-test--target-name "ga-1"
                         "--json" "--on" "mol-x"
                         "--var" "alpha=one" "--var" "beta=two")))))

(ert-deftest gascity-test-beads-sling-dispatch-formula-argv ()
  "A formula dispatch puts the target first, then the formula name."
  (gascity-beads-sling-test--with-launch
    (should-not (gascity-beads-sling--dispatch
                 (gascity-beads-sling-test--target) nil nil
                 (list :work nil :formula "mol-x" :shape 'formula
                       :values '(("alpha" . "one")))))
    (should (= 1 launch-count))
    (should (equal (plist-get launched :argv)
                   (list "sling" gascity-beads-sling-test--target-name
                         "mol-x" "--json" "--formula" "--var" "alpha=one")))
    ;; Never the targetless shape gc refuses (`gc sling --formula …').
    (should-not (equal (seq-take (plist-get launched :argv) 2)
                       '("sling" "--formula")))))

(ert-deftest gascity-test-beads-sling-dispatch-formula-ignores-work ()
  "A formula dispatch keeps the work bead out of argv; the formula name is slot 2."
  (gascity-beads-sling-test--with-launch
    (gascity-beads-sling--dispatch
     (gascity-beads-sling-test--target) "ga-1" nil
     (list :work "ga-1" :formula "mol-x" :shape 'formula))
    (should (equal (plist-get launched :argv)
                   (list "sling" gascity-beads-sling-test--target-name
                         "mol-x" "--json" "--formula")))))

(ert-deftest gascity-test-beads-sling-dispatch-target-arg-wins ()
  "The dispatch TARGET argument beats the context's target."
  (gascity-beads-sling-test--with-launch
    (gascity-beads-sling--dispatch
     (gascity-beads-sling-test--target) "ga-1" nil
     (list :work "ga-1" :shape 'plain :target "other/agent"))
    (should (equal (plist-get launched :argv)
                   (list "sling" gascity-beads-sling-test--target-name
                         "ga-1" "--json")))))

(ert-deftest gascity-test-beads-sling-dispatch-skips-derivation ()
  "An explicit target is authoritative; the roster is never read for it."
  (gascity-beads-sling-test--with-launch
    (cl-letf (((symbol-function 'gascity-sling--roster)
               (lambda (&rest _)
                 (error "Read the roster for an explicitly chosen target")))
              ((symbol-function 'gascity-sling--derive-target)
               (lambda (&rest _)
                 (error "Derived a target the dispatch already chose"))))
      (gascity-beads-sling--dispatch
       (gascity-beads-sling-test--target) "ga-1" nil
       (list :work "ga-1" :shape 'plain :target "other/agent")))
    (should (= 1 launch-count))
    (should (equal (plist-get launched :argv)
                   (list "sling" gascity-beads-sling-test--target-name
                         "ga-1" "--json")))))

(ert-deftest gascity-test-beads-sling-dispatch-resolves-context-target ()
  "A nil TARGET falls back to the context's target name."
  (gascity-beads-sling-test--with-launch
    (gascity-beads-sling--dispatch
     nil "ga-1" nil
     (list :work "ga-1" :shape 'plain :target "context/agent"))
    (should (equal (plist-get launched :argv)
                   (list "sling" "context/agent" "ga-1" "--json")))))

(ert-deftest gascity-test-beads-sling-dispatch-resolves-derived-target ()
  "With no explicit target, the Who derivation's answer is used."
  (gascity-beads-sling-test--with-launch
    (cl-letf (((symbol-function 'gascity-sling--derive-target)
               (lambda (_scope _roster _memory)
                 (list :target "derived/agent" :source 'implementation-worker))))
      (gascity-beads-sling--dispatch nil "ga-1" nil
                                     (list :work "ga-1" :shape 'plain)))
    (should (equal (plist-get launched :argv)
                   (list "sling" "derived/agent" "ga-1" "--json")))))

(ert-deftest gascity-test-beads-sling-dispatch-missing-target ()
  "Every shape refuses, before any launch, when no target resolves."
  (gascity-beads-sling-test--with-launch
    (dolist (context (list (list :work "ga-1" :shape 'plain)
                           (list :work "ga-1" :formula "mol-x" :shape 'on)
                           (list :formula "mol-x" :shape 'formula)))
      (should-error (gascity-beads-sling--dispatch nil "ga-1" nil context)
                    :type 'user-error
                    :exclude-subtypes t))
    (should (= 0 launch-count))))

(ert-deftest gascity-test-beads-sling-dispatch-missing-work ()
  "A plain or `on' dispatch without work errors out before the launch."
  (gascity-beads-sling-test--with-launch
    (should-error (gascity-beads-sling--dispatch
                   (gascity-beads-sling-test--target) nil nil
                   (list :shape 'plain))
                  :type 'user-error)
    (should-error (gascity-beads-sling--dispatch
                   (gascity-beads-sling-test--target) "  " nil
                   (list :work "  " :formula "mol-x" :shape 'on))
                  :type 'user-error)
    (should (= 0 launch-count))))

(ert-deftest gascity-test-beads-sling-dispatch-missing-formula ()
  "An `on' or formula dispatch without a formula errors before the launch."
  (gascity-beads-sling-test--with-launch
    (should-error (gascity-beads-sling--dispatch
                   (gascity-beads-sling-test--target) "ga-1" nil
                   (list :work "ga-1" :shape 'on))
                  :type 'user-error)
    (should-error (gascity-beads-sling--dispatch
                   (gascity-beads-sling-test--target) nil nil
                   (list :formula "" :shape 'formula))
                  :type 'user-error)
    (should (= 0 launch-count))))

(ert-deftest gascity-test-beads-sling-dispatch-prompt-dropped ()
  "A non-blank prompt is dropped with a message, never refused or passed."
  (gascity-beads-sling-test--with-launch
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (format &rest args)
                   (push (apply #'format format args) messages))))
        (gascity-beads-sling--dispatch
         (gascity-beads-sling-test--target) "ga-1" "do the thing"
         (list :work "ga-1" :shape 'plain)))
      (should (seq-some (lambda (msg) (string-match-p "no prompt flag" msg))
                        messages)))
    (should (= 1 launch-count))
    (should (equal (plist-get launched :argv)
                   (list "sling" gascity-beads-sling-test--target-name
                         "ga-1" "--json")))))

(ert-deftest gascity-test-beads-sling-dispatch-validates-recipe-vars ()
  "The dispatch hands the beads recipe and raw values to the shared check."
  (gascity-beads-sling-test--with-launch
    (let ((recipe (list :name "mol-x"))
          (values '(("alpha" . "one")))
          (checked nil))
      (cl-letf (((symbol-function 'beads-formula-validate-vars)
                 (lambda (formula vars)
                   (setq checked (list formula vars))
                   (user-error "Missing required formula vars: beta"))))
        (should-error (gascity-beads-sling--dispatch
                       (gascity-beads-sling-test--target) "ga-1" nil
                       (list :work "ga-1" :formula "mol-x" :shape 'on
                             :recipe recipe :values values))
                      :type 'user-error))
      (should (equal checked (list recipe values))))
    (should (= 0 launch-count))))

;;; Async launch, echo and one invalidation (plan §B3b, REQ-003/REQ-004)

(defconst gascity-beads-sling-test--result
  '((id . "ga-9") (status . "open"))
  "The parsed payload a successful launch answers with.")

(defconst gascity-beads-sling-test--invalidate-kinds
  '(agent run session convoy status)
  "The store kinds one sling dispatch invalidates, in order.")

(defun gascity-beads-sling-test--succeed (launched &optional result)
  "Invoke the captured LAUNCH's `:on-success' closure with RESULT.
Signals a test failure when the dispatch registered no closure."
  (let ((on-success (plist-get (plist-get launched :args) :on-success)))
    (should on-success)
    (funcall on-success result)))

(defun gascity-beads-sling-test--dispatch-shape (shape)
  "Dispatch the test target for SHAPE with a plain or formula context.
The launch itself is captured by the enclosing
`gascity-beads-sling-test--with-launch'."
  (gascity-beads-sling--dispatch
   (gascity-beads-sling-test--target) "ga-1" nil
   (list :work "ga-1"
         :shape shape
         :formula (unless (eq shape 'plain) "mol-x"))))

(ert-deftest gascity-test-beads-sling-dispatch-async-launch ()
  "One non-blocking launch: json payload, city pin, explicit invalidation off."
  (gascity-beads-sling-test--with-launch
    (let ((result (gascity-beads-sling-test--dispatch-shape 'plain)))
      (should-not result)
      (should (= 1 launch-count))
      (let ((args (plist-get launched :args)))
        ;; The payload must be parsed JSON for the launch handler (step 2).
        (should (eq (slot-value (plist-get launched :command) 'json) t))
        (should (plist-member args :invalidate))
        (should-not (plist-get args :invalidate))
        (should-not (plist-member args :on-error))
        (should (functionp (plist-get args :on-success)))
        (should (equal (plist-get args :target)
                       gascity-beads-sling-test--target-name))
        (should (equal (plist-get args :dir)
                       gascity-beads-sling-test--city))))))

(ert-deftest gascity-test-beads-sling-dispatch-echo-plain ()
  "A plain launch echoes the shared success text for the sling and target."
  (gascity-beads-sling-test--with-launch
    (let ((messages nil))
      (cl-letf (((symbol-function 'gascity-beads-sling--invalidate) #'ignore)
                ((symbol-function 'message)
                 (lambda (format &rest args)
                   (push (apply #'format format args) messages))))
        (gascity-beads-sling-test--dispatch-shape 'plain)
        (should-not messages)
        (gascity-beads-sling-test--succeed
         launched gascity-beads-sling-test--result))
      (should (equal messages
                     (list (gascity-action--success-text
                            (plist-get launched :command)
                            gascity-beads-sling-test--target-name
                            gascity-beads-sling-test--result)))))))

(ert-deftest gascity-test-beads-sling-dispatch-echo-formula ()
  "The `on' and formula shapes echo through the launch handler."
  (gascity-beads-sling-test--with-launch
    (let ((handler-calls nil)
          (handled nil)
          (messages nil))
      (cl-letf (((symbol-function 'gascity-sling--launch-handler)
                 (lambda (command formula arg)
                   (push (list command formula arg) handler-calls)
                   (lambda (result) (push result handled))))
                ((symbol-function 'gascity-beads-sling--invalidate) #'ignore)
                ((symbol-function 'message)
                 (lambda (format &rest args)
                   (push (apply #'format format args) messages))))
        (dolist (shape '(on formula))
          (setq handler-calls nil
                handled nil
                messages nil)
          (gascity-beads-sling-test--dispatch-shape shape)
          (should (= 1 (length handler-calls)))
          (should (eq (caar handler-calls) (plist-get launched :command)))
          (should (equal (nth 1 (car handler-calls)) "mol-x"))
          (should (equal (nth 2 (car handler-calls)) "ga-1"))
          (gascity-beads-sling-test--succeed
           launched gascity-beads-sling-test--result)
          (should (equal handled (list gascity-beads-sling-test--result)))
          (should-not messages))))))

(ert-deftest gascity-test-beads-sling-dispatch-invalidate-once ()
  "Success invalidates exactly one call per store kind, and nothing else."
  (gascity-beads-sling-test--with-launch
    (let ((calls nil))
      (cl-letf (((symbol-function 'gascity-store-invalidate)
                 (lambda (&rest args) (push args calls)))
                ((symbol-function 'gascity-sling--launch-handler)
                 (lambda (&rest _) #'ignore))
                ((symbol-function 'message) #'ignore))
        (dolist (shape '(plain on formula))
          (setq calls nil)
          (gascity-beads-sling-test--dispatch-shape shape)
          ;; Nothing is invalidated at launch time: only the answer does it.
          (should-not calls)
          (gascity-beads-sling-test--succeed
           launched gascity-beads-sling-test--result)
          (should (= (length calls)
                     (length gascity-beads-sling-test--invalidate-kinds)))
          (should (equal (mapcar (lambda (call) (plist-get call :kind))
                                 (reverse calls))
                         gascity-beads-sling-test--invalidate-kinds))
          (dolist (call calls)
            (should (eq (plist-get call :refetch) t))
            (should (equal (plist-get call :dir)
                           gascity-beads-sling-test--city))))))))

(ert-deftest gascity-test-beads-sling-invalidate-requires-dir ()
  "An unresolved city invalidates nothing: nil `:dir' is a wildcard."
  (let ((calls nil))
    (cl-letf (((symbol-function 'gascity-store-invalidate)
               (lambda (&rest args) (push args calls))))
      (gascity-beads-sling--invalidate nil)
      (should-not calls))))

(ert-deftest gascity-test-beads-sling-dispatch-remembers-target ()
  "The launch start records the Who memory and the resolved city."
  (gascity-beads-sling-test--with-launch
    (let ((gascity-sling--target-memory nil)
          (gascity-beads-sling--city nil))
      (gascity-beads-sling-test--dispatch-shape 'on)
      (should (equal gascity-beads-sling--city
                     gascity-beads-sling-test--city))
      (should (equal (gascity-sling--memory-target
                      (list :city gascity-beads-sling-test--city
                            :formula "mol-x")
                      gascity-sling--target-memory)
                     gascity-beads-sling-test--target-name))
      ;; A plain launch records under the nil formula, as the transient does.
      (gascity-beads-sling-test--dispatch-shape 'plain)
      (should (equal (gascity-sling--memory-target
                      (list :city gascity-beads-sling-test--city
                            :formula nil)
                      gascity-sling--target-memory)
                     gascity-beads-sling-test--target-name)))))

;;; B4 — advisory validators

(defconst gascity-beads-sling-test--validator-city "/tmp/gascity-beads-sling-city/"
  "The city root the validator fixtures run in.")

(defconst gascity-beads-sling-test--cross-store-warning
  "cross-store route:"
  "Substring unique to `gascity-sling--cross-store-warning'.")

(defconst gascity-beads-sling-test--v2-warning
  "formulas v2 target:"
  "Substring unique to `gascity-sling--v2-trap-warning'.")

(defconst gascity-beads-sling-test--missing-vars-warning
  "Missing required vars:"
  "Substring unique to `gascity-sling--missing-vars-warning'.")

(defconst gascity-beads-sling-test--missing-target-warning
  "No target"
  "Substring unique to `gascity-sling--missing-target-warning'.")

(defun gascity-beads-sling-test--validator-rigs ()
  "Return a rig memo with the city HQ and three rig stores."
  (list (gascity-domain-decode
         'gascity-rig '((name . "bright-lights") (prefix . "bl") (hq . t)))
        (gascity-domain-decode
         'gascity-rig '((name . "hello-world") (prefix . "hw")))
        (gascity-domain-decode
         'gascity-rig '((name . "gascity.el") (prefix . "gce")))))

(defun gascity-beads-sling-test--recipe (name steps &optional vars)
  "Decode a `gascity-formula' NAME with raw STEPS and VARS."
  (gascity-domain-decode
   'gascity-formula `((name . ,name) (steps . ,steps)
                      ,@(and vars `((vars . ,vars))))))

(defun gascity-beads-sling-test--v2-recipe ()
  "Return a formula whose steps name a binding-qualified run target."
  (gascity-beads-sling-test--recipe
   "build-basic"
   (vector '((id . "run") (title . "Run")
             (metadata . ((gc.run_target . "gc.run-operator")))))
   (vector '((name . "artifact_root") (required . t)))))

(defmacro gascity-beads-sling-test--with-cache (&rest body)
  "Run BODY with the validator's cached city, rigs and recipes stubbed.
No read may escape: `gascity-rigs-cached' and the scope key answer
from the fixture, and the recipe cache starts empty."
  (declare (indent 0) (debug t))
  `(let ((gascity-context-city gascity-beads-sling-test--validator-city)
         (default-directory gascity-beads-sling-test--validator-city)
         (gascity-formula-recipe-cache nil))
     (cl-letf (((symbol-function 'gascity-rigs-cached)
                (lambda (&optional _dir) (gascity-beads-sling-test--validator-rigs)))
               ((symbol-function 'gascity-context-scope-key)
                (lambda (&optional _dir) gascity-beads-sling-test--validator-city)))
       ,@body)))

(defun gascity-beads-sling-test--warnings (string)
  "Return the warning substrings present in STRING."
  (seq-filter (lambda (needle) (string-search needle string))
              (list gascity-beads-sling-test--cross-store-warning
                    gascity-beads-sling-test--v2-warning
                    gascity-beads-sling-test--missing-vars-warning
                    gascity-beads-sling-test--missing-target-warning)))

(ert-deftest gascity-test-beads-sling-validate-clean ()
  "A routable bead with a same-store target produces no warning."
  (gascity-beads-sling-test--with-cache
    (should-not (gascity-beads-sling-validate
                 '(:work "hw-ab12" :target "hello-world/polecat"
                   :shape plain)))))

(ert-deftest gascity-test-beads-sling-validate-cross-store ()
  "A bead and a rig-scoped target in different stores warn once."
  (gascity-beads-sling-test--with-cache
    (let ((warning (gascity-beads-sling-validate
                    '(:work "hw-ab12"
                      :target "gascity.el/gc.implementation-worker"
                      :shape plain))))
      (should warning)
      (should (equal (gascity-beads-sling-test--warnings warning)
                     (list gascity-beads-sling-test--cross-store-warning))))))

(ert-deftest gascity-test-beads-sling-validate-missing-vars ()
  "A formula context missing a required var warns once."
  (gascity-beads-sling-test--with-cache
    (let ((warning (gascity-beads-sling-validate
                    (list :work "hw-ab12" :target "mayor" :shape 'formula
                          :recipe (gascity-beads-sling-test--v2-recipe)
                          :values nil))))
      (should warning)
      (should (equal (gascity-beads-sling-test--warnings warning)
                     (list gascity-beads-sling-test--missing-vars-warning))))))

(ert-deftest gascity-test-beads-sling-validate-missing-target ()
  "Every shape, formula included, warns when no target is resolved."
  (gascity-beads-sling-test--with-cache
    (dolist (shape '(plain on formula))
      (let ((warning (gascity-beads-sling-validate
                      (list :work "hw-ab12" :target nil :shape shape))))
        (should warning)
        (should (equal (gascity-beads-sling-test--warnings warning)
                       (list gascity-beads-sling-test--missing-target-warning)))))))

(ert-deftest gascity-test-beads-sling-validate-cold-recipe ()
  "No warm gascity recipe means no v2-trap warning and no read."
  (gascity-beads-sling-test--with-cache
    (let ((warning (gascity-beads-sling-validate
                    (list :work "hw-ab12" :target "mayor" :shape 'formula
                          :formula "build-basic" :recipe nil :values nil))))
      (should-not warning))))

(ert-deftest gascity-test-beads-sling-validate-warm-recipe-trap ()
  "A warm scope-keyed recipe with a city target warns exactly once."
  (gascity-beads-sling-test--with-cache
    (let ((gascity-formula-recipe-cache
           (list (cons (cons gascity-beads-sling-test--validator-city "build-basic")
                       (gascity-beads-sling-test--v2-recipe)))))
      (let ((warning (gascity-beads-sling-validate
                      (list :work "hw-ab12" :target "mayor" :shape 'formula
                            :formula "build-basic" :recipe nil :values nil))))
        (should warning)
        (should (equal (gascity-beads-sling-test--warnings warning)
                       (list gascity-beads-sling-test--v2-warning)))))))

(ert-deftest gascity-test-beads-sling-validate-warm-recipe-rig-target ()
  "A warm recipe with a rig-scoped target does not trap."
  (gascity-beads-sling-test--with-cache
    (let ((gascity-formula-recipe-cache
           (list (cons (cons gascity-beads-sling-test--validator-city "build-basic")
                       (gascity-beads-sling-test--v2-recipe)))))
      (should-not (gascity-beads-sling-validate
                   (list :work "hw-ab12" :target "hello-world/polecat"
                         :shape 'formula :formula "build-basic"
                         :recipe nil :values nil))))))

(ert-deftest gascity-test-beads-sling-validate-joins-warnings ()
  "Independent warnings are joined into one string with \"; \"."
  (gascity-beads-sling-test--with-cache
    (let ((warning (gascity-beads-sling-validate
                    (list :work "hw-ab12"
                          :target "gascity.el/gc.implementation-worker"
                          :shape 'formula
                          :recipe (gascity-beads-sling-test--v2-recipe)
                          :values nil))))
      (should warning)
      (should (equal (gascity-beads-sling-test--warnings warning)
                     (list gascity-beads-sling-test--cross-store-warning
                           gascity-beads-sling-test--missing-vars-warning)))
      (should (= 2 (length (split-string warning "; " t)))))))

(ert-deftest gascity-test-beads-sling-menu-and-actions ()
  "The `[City]' group is registered once and the actions are additive.
The five group keys are the reviewed free set from the plan (P4); the
beads.el `beads-dispatch' keys in the same menu are
l c / i u x o e r b d # C s m G w S T a F v D H R Y t X L k . W ! * g q,
so none of E J K A Q collides.  `V' is additive and never redefines
beads.el's `S', `RET' or `TAB'."
  (gascity-beads-sling-register)
  (gascity-beads-sling-register)
  (let* ((groups (beads-menu-provider-groups))
         (city (seq-filter (lambda (group)
                             (and (vectorp group)
                                  (equal (aref group 0) "City")))
                           groups)))
    (should (= 1 (length city)))
    (let* ((group (car city))
           (suffixes (seq-drop group 1)))
      (should (equal (mapcar #'car suffixes) '("E" "J" "K" "A" "Q")))
      (should (equal (mapcar (lambda (suffix) (nth 2 suffix)) suffixes)
                     '(gascity-dashboard
                       gascity-rig-dashboard-at-point
                       gascity-rig-dashboard
                       gascity-agents
                       gascity-sling-dispatch)))))
  (should (equal (beads-actions-provider-actions :list)
                 '(("V" . gascity-dashboard))))
  (should (equal (beads-actions-provider-actions :show)
                 '(("V" . gascity-dashboard))))
  (should-not (beads-actions-provider-actions :status))
  (should-not (beads-actions-provider-actions :dashboard))
  (should-not (assoc "S" (beads-actions-provider-actions :list)))
  (should-not (assoc "RET" (beads-actions-provider-actions :list)))
  (should-not (assoc "TAB" (beads-actions-provider-actions :list))))

;;; Post-mutation refresh (plan §B5b, REQ-008)

(defconst gascity-beads-sling-test--rig-two "/tmp/beads-sling-rig-two/"
  "A second rig repository, owning another bead-id prefix.")

(defun gascity-beads-sling-test--two-rigs (city)
  "Return CITY's memoized rigs: a `gce' and a `bs' repository."
  (when (equal city gascity-beads-sling-test--city)
    (append (gascity-beads-sling-test--rigs city)
            (list (gascity-rig
                   :name "beads.el"
                   :prefix "bs"
                   :path (directory-file-name
                          gascity-beads-sling-test--rig-two))))))

(defun gascity-beads-sling-test--with-after-action-stubs (rigs body)
  "Call BODY with the rig memo stubbed to RIGS and return the invalidations.
Each `gascity-store-invalidate' call is recorded as its ARGS plist, in
call order."
  (let ((calls nil))
    (cl-letf (((symbol-function 'gascity-store-invalidate)
               (lambda (&rest args) (push args calls)))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional city) (funcall rigs city))))
      (funcall body))
    (nreverse calls)))

(ert-deftest gascity-test-beads-sling-after-action-refreshes-both-roots ()
  "One city invalidation and one per affected rig root, with gc's kinds."
  (let ((gascity-beads-sling--city gascity-beads-sling-test--city)
        (default-directory gascity-beads-sling-test--rig))
    (let ((calls (gascity-beads-sling-test--with-after-action-stubs
                  #'gascity-beads-sling-test--two-rigs
                  (lambda ()
                    (gascity-beads-sling--after-action
                     'close '("gce-1" "bs-2" "gce-3"))))))
      (should (equal
               calls
               (list (list :dir gascity-beads-sling-test--city
                           :kind '(status run session convoy agent)
                           :refetch t)
                     (list :dir gascity-beads-sling-test--rig
                           :kind '(bd) :refetch t)
                     (list :dir gascity-beads-sling-test--rig-two
                           :kind '(bd) :refetch t)))))))

(ert-deftest gascity-test-beads-sling-after-action-no-allow-list ()
  "Every delivered mutation refreshes; there is no action allow-list."
  (let ((gascity-beads-sling--city gascity-beads-sling-test--city)
        (default-directory gascity-beads-sling-test--rig))
    (dolist (action '(close claim reopen set-status set-priority
                      create update force-close))
      (let ((calls (gascity-beads-sling-test--with-after-action-stubs
                    #'gascity-beads-sling-test--rigs
                    (lambda ()
                      (gascity-beads-sling--after-action action '("gce-1"))))))
        (should (= 2 (length calls)))
        (should (equal gascity-beads-sling-test--city
                       (plist-get (car calls) :dir)))
        (should (equal gascity-beads-sling-test--rig
                       (plist-get (cadr calls) :dir)))))))

(ert-deftest gascity-test-beads-sling-after-action-empty-issues ()
  "An empty ISSUES list invalidates nothing and resolves no city."
  (let ((calls nil))
    (cl-letf (((symbol-function 'gascity-store-invalidate)
               (lambda (&rest args) (push args calls)))
              ((symbol-function 'gascity-context-known-city-roots)
               (lambda () (error "An empty mutation resolved a city")))
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&rest _) (error "An empty mutation read the rig memo"))))
      (gascity-beads-sling--after-action 'close nil)
      (gascity-beads-sling--after-action 'close '()))
    (should-not calls)))

(ert-deftest gascity-test-beads-sling-after-action-unresolved-city ()
  "No resolvable city means no invalidation at all, never a broad one."
  (let ((gascity-beads-sling--city nil)
        (gascity-context-city nil)
        (default-directory gascity-beads-sling-test--rig)
        (calls nil))
    (cl-letf (((symbol-function 'gascity-store-invalidate)
               (lambda (&rest args) (push args calls)))
              ((symbol-function 'gascity-context-known-city-roots) #'ignore)
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&optional _city) nil)))
      (gascity-beads-sling--after-action 'close '("gce-1")))
    (should-not calls)))

(ert-deftest gascity-test-beads-sling-after-action-unknown-prefix ()
  "An id whose prefix is not in the rig memo contributes no rig root."
  (let ((gascity-beads-sling--city gascity-beads-sling-test--city)
        (default-directory gascity-beads-sling-test--rig))
    (let ((calls (gascity-beads-sling-test--with-after-action-stubs
                  #'gascity-beads-sling-test--rigs
                  (lambda ()
                    (gascity-beads-sling--after-action
                     'close '("zz-1" "ga-2" "nohyphen"))))))
      (should (= 1 (length calls)))
      (should (equal gascity-beads-sling-test--city
                     (plist-get (car calls) :dir))))))

(ert-deftest gascity-test-beads-sling-after-action-city-root-order ()
  "A remembered city governs DIR or is skipped; containment also matches."
  ;; A remembered city that does not govern DIR is skipped.
  (let ((default-directory gascity-beads-sling-test--rig)
        (gascity-beads-sling--city gascity-beads-sling-test--other-city))
    (cl-letf (((symbol-function 'gascity-rigs-cached)
               (lambda (&optional city) (gascity-beads-sling-test--rigs city)))
              ((symbol-function 'gascity-context-known-city-roots)
               (lambda () (list gascity-beads-sling-test--city))))
      (should (equal (gascity-beads-sling--after-action-city-root)
                     gascity-beads-sling-test--city))))
  ;; A remembered city that governs DIR answers before a known root.
  (let ((default-directory gascity-beads-sling-test--rig)
        (gascity-beads-sling--city gascity-beads-sling-test--city))
    (cl-letf (((symbol-function 'gascity-rigs-cached)
               (lambda (&optional city) (gascity-beads-sling-test--rigs city)))
              ((symbol-function 'gascity-context-known-city-roots)
               (lambda () (list gascity-beads-sling-test--other-city))))
      (should (equal (gascity-beads-sling--after-action-city-root)
                     gascity-beads-sling-test--city))))
  ;; A city-store bead buffer (inside the city tree) resolves its city.
  (let ((default-directory (concat gascity-beads-sling-test--city "beads/"))
        (gascity-beads-sling--city nil))
    (cl-letf (((symbol-function 'gascity-context-known-city-roots)
               (lambda () (list gascity-beads-sling-test--city))))
      (should (equal (gascity-beads-sling--after-action-city-root)
                     gascity-beads-sling-test--city)))))

(ert-deftest gascity-test-beads-sling-after-action-kind-routes ()
  "The city kinds are the aggregate payloads; the rig kind is the `bd' argv."
  (should (equal gascity-beads-sling--city-refresh-kinds
                 '(status run session convoy agent)))
  (should (equal gascity-beads-sling--rig-refresh-kinds '(bd)))
  (should (eq 'bd (gascity-store-kind '("bd" "list"))))
  (should-not (eq 'bead (gascity-store-kind '("bd" "list")))))

(ert-deftest gascity-test-beads-sling-after-action-is-cache-only ()
  "The hook never reads or mutates beads, spawns gc, or starts a timer."
  (let ((gascity-beads-sling--city gascity-beads-sling-test--city)
        (default-directory gascity-beads-sling-test--rig))
    (let ((calls nil))
      (cl-letf (((symbol-function 'gascity-store-invalidate)
                 (lambda (&rest args) (push args calls)))
                ((symbol-function 'gascity-rigs-cached)
                 (lambda (&optional city) (gascity-beads-sling-test--rigs city)))
                ((symbol-function 'gascity-store-get)
                 (lambda (&rest _) (error "The hook read the store")))
                ((symbol-function 'gascity-store-peek)
                 (lambda (&rest _) (error "The hook peeked at the store")))
                ((symbol-function 'gascity-reader-read)
                 (lambda (&rest _) (error "The hook spawned a sync read")))
                ((symbol-function 'gascity-reader-read-async)
                 (lambda (&rest _) (error "The hook spawned an async read")))
                ((symbol-function 'gascity-reader-run-async)
                 (lambda (&rest _) (error "The hook ran an action")))
                ((symbol-function 'beads-execute)
                 (lambda (&rest _) (error "The hook mutated beads")))
                ((symbol-function 'beads-refresh-show)
                 (lambda (&rest _) (error "The hook refreshed a beads buffer")))
                ((symbol-function 'run-at-time)
                 (lambda (&rest _) (error "The hook started a timer"))))
        (gascity-beads-sling--after-action 'claim '("gce-1")))
      (should (= 2 (length calls))))))

;;; B6 — remaining plan-table coverage (REQ-003/REQ-007/REQ-009)

(ert-deftest gascity-test-beads-sling-dispatch-formula-argv-with-target ()
  "The formula shape always carries a real target and never the targetless
\(`sling' `--formula') shape gc refuses."
  (gascity-beads-sling-test--with-launch
    (gascity-beads-sling--dispatch
     (gascity-beads-sling-test--target) nil nil
     (list :formula "mol-x" :shape 'formula))
    (should (= 1 launch-count))
    (let ((argv (plist-get launched :argv)))
      (should (equal (seq-take argv 3)
                     (list "sling" gascity-beads-sling-test--target-name
                           "mol-x")))
      (should (equal (nth 3 argv) "--json"))
      (should (equal (nth 4 argv) "--formula"))
      ;; No positional slot is empty, and `--formula' is never the
      ;; subcommand's first argument (P1).
      (should-not (seq-some #'gascity-beads-sling--blank-p argv))
      (should-not (equal (seq-take argv 2) '("sling" "--formula"))))))

(ert-deftest gascity-test-beads-sling-dispatch-formula-uses-resolved-target ()
  "A formula dispatch with no explicit target uses the Who derivation."
  (gascity-beads-sling-test--with-launch
    (cl-letf (((symbol-function 'gascity-sling--derive-target)
               (lambda (_scope _roster _memory)
                 (list :target "derived/agent" :source 'implementation-worker))))
      (gascity-beads-sling--dispatch nil nil nil
                                     (list :formula "mol-x" :shape 'formula)))
    (should (= 1 launch-count))
    (should (equal (plist-get launched :argv)
                   (list "sling" "derived/agent" "mol-x" "--json"
                         "--formula")))
    (should (equal (plist-get launched :target) "derived/agent"))))

(ert-deftest gascity-test-beads-sling-dispatch-invalid ()
  "An unknown shape is refused before any launch."
  (gascity-beads-sling-test--with-launch
    (should-error (gascity-beads-sling--dispatch
                   (gascity-beads-sling-test--target) "ga-1" nil
                   (list :work "ga-1" :shape 'bogus))
                  :type 'user-error)
    (should (= 0 launch-count))))

(ert-deftest gascity-test-beads-sling-delegation-s-then-dispatch ()
  "beads' `S' seeds the transient, then a gc target dispatch runs the
expected argv: the delegation contract end to end with a stubbed gc."
  (let ((scope nil))
    (cl-letf (((symbol-function 'beads-sling--bead-at-point)
               (lambda () "ga-1"))
              ((symbol-function 'transient-setup)
               (lambda (_name _levels _suffixes &rest args)
                 (setq scope (plist-get args :scope)))))
      ;; `S' opens the sling transient with the bead at point.
      (beads-sling-for-issue)
      (should (equal (plist-get scope :work) "ga-1"))))
  ;; The Who picker's gc target, dispatched exactly as the beads
  ;; transient's `s' does: through the registered backend.
  (gascity-beads-sling-test--with-launch
    (let* ((target (gascity-beads-sling-test--target
                    "gascity.el/gc.implementation-worker"))
           (context (list :work "ga-1" :shape 'plain
                          :target (oref target name))))
      (should (equal (oref target backend) "gc"))
      (beads-sling-dispatch target "ga-1" nil context)
      (should (= 1 launch-count))
      (should (equal (plist-get launched :argv)
                     (list "sling" "gascity.el/gc.implementation-worker"
                           "ga-1" "--json"))))))
