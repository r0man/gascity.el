;;; gascity-exec-test.el --- No host resolution where the executable is dropped -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Tabulated list refreshes and async actions hand gc's argv tail to the
;; store, which adds the executable itself.  Building it through
;; `gascity-command-line' resolved `gc' on the host first
;; (`gascity-remote-find-executable', synchronous `file-executable-p'
;; probes over TRAMP: 0.14 s when opening the session list of
;; /ssh:localhost:, dashboard-v3 TRAMP matrix) only to drop it.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(ert-deftest gascity-test-exec-arguments-are-the-line-tail ()
  "`gascity-command-arguments' is `gascity-command-line' minus the executable."
  (cl-letf (((symbol-function 'gascity-remote-find-executable) #'identity))
    (dolist (cmd (list (gascity-command-session-list) (gascity-command-rig-list)
                       (gascity-command-status :verbose t)))
      (should (equal (gascity-command-arguments cmd)
                     (cdr (gascity-command-line cmd))))
      (should (equal (car (gascity-command-line cmd)) gascity-executable)))))

(ert-deftest gascity-test-exec-list-and-action-do-not-resolve ()
  "A remote list refresh and an async action never resolve the executable."
  (gascity-test-ensure-mock-method)
  (let ((default-directory "/mock::/tmp/exec-city/")
        (gascity-store-synchronous-delivery t)
        (tramp-verbose 0))
    ;; A primed host dispatches at once (no first-contact timer).
    (setf (gascity-store--host-primed
           (gascity-store--host (file-remote-p default-directory)))
          t)
    (cl-letf (((symbol-function 'gascity-remote-find-executable)
               (lambda (&rest _) (error "Resolved the executable")))
              ((symbol-function 'gascity-context-city-root) (lambda (&rest _) nil)))
      (gascity-test-with-store-stubs reads actions
        (with-temp-buffer
          (gascity-tabulated--refresh-async
           "Sessions" (gascity-command-session-list) (lambda (_) nil)))
        (gascity-command-act-async (gascity-command-session-suspend :target "r/a"))
        ;; Both reached the process boundary, argv without executable.
        (should (equal (car (car (last reads))) '("session" "list")))
        (should (equal (car (car actions)) '("session" "suspend" "r/a")))))))

(provide 'gascity-exec-test)
;;; gascity-exec-test.el ends here
