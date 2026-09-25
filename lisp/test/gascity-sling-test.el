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

(provide 'gascity-sling-test)
;;; gascity-sling-test.el ends here
