;;; gascity-test-helpers.el --- Shared ERT fixtures for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Fixtures every gascity test file may use (dashboard-v3 §8.4):
;;
;; - A fresh payload store per test.  `gascity-store' keeps payloads,
;;   scheduler and host state in global tables; a payload cached by one
;;   test (fresh for its TTL) would otherwise answer the next test's
;;   read without calling its stub.  Loading this file installs an
;;   advice that clears the store before every ERT test.
;;
;; - `gascity-test-with-mock-remote': a remote `default-directory'
;;   through TRAMP's "mock" method — a local sh behind the full tramp-sh
;;   machinery.  The method is not built into TRAMP; it is defined here
;;   the way tramp-tests.el defines it.
;;
;; - `gascity-test-with-render-guard': a file-name handler that signals
;;   `gascity-test-render-guard-io' on every file operation that can do
;;   I/O on a remote name, while pure name operations pass (R2).  Wrap a
;;   view render in it with a remote `default-directory' to prove the
;;   render touches only in-memory payloads.
;;
;; - `gascity-test-with-store-stubs': stub the gc boundary of the store
;;   (async reads and async actions) with recording functions.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'tramp)
(require 'gascity-store)

;;; Fresh store per test

(defun gascity-test--reset-store (&rest _)
  "Clear the payload store and its scheduler before an ERT test."
  (gascity-store-clear))

(advice-add 'ert-run-test :before #'gascity-test--reset-store)

;;; TRAMP mock method

(defconst gascity-test-mock-directory
  (format "/mock::%s" temporary-file-directory)
  "TRAMP name of the local temp directory behind the mock method.")

(defun gascity-test-ensure-mock-method ()
  "Register the tramp-tests.el \"mock\" method (idempotent).
A real local `sh' behind the full TRAMP machinery: remote-flavored code
paths — `process-file' redirection, `make-process :file-handler',
connection-local resolution — with no network."
  (unless (assoc "mock" tramp-methods)
    (add-to-list 'tramp-methods
                 '("mock"
                   (tramp-login-program "sh")
                   (tramp-login-args (("-i")))
                   (tramp-direct-async ("-c"))
                   (tramp-remote-shell "/bin/sh")
                   (tramp-remote-shell-args ("-c"))
                   (tramp-connection-timeout 10)))
    (add-to-list 'tramp-default-host-alist
                 `("\\`mock\\'" nil ,(system-name)))))

(defmacro gascity-test-with-mock-remote (&rest body)
  "Run BODY with `default-directory' on the TRAMP mock method.
Skips the calling test when the mock connection cannot be
established (no local sh).  BODY sees a real TRAMP connection."
  (declare (indent 0) (debug t))
  `(progn
     (gascity-test-ensure-mock-method)
     (let ((tramp-verbose 0)
           (default-directory gascity-test-mock-directory))
       (skip-unless (ignore-errors (file-directory-p default-directory)))
       ,@body)))

;;; Render guard (R2)

(define-error 'gascity-test-render-guard-io
  "File I/O on a remote name during a guarded render")

(defconst gascity-test-render-guard-pure-operations
  '(file-remote-p file-name-directory file-name-nondirectory
    file-name-as-directory directory-file-name file-name-sans-versions
    substitute-in-file-name unhandled-file-name-directory
    file-name-case-insensitive-p)
  "File-name handler operations the render guard lets through.
Pure name manipulation: gascity-remote calls these constantly while
rendering.  `expand-file-name' is allowed only on an absolute name
without `~' (see `gascity-test--render-guard-handler').")

(defvar gascity-test-render-guard-violations nil
  "Operations the render guard refused, most recent first.
Kept so a test can assert on them even when the code under test
swallowed the signal (`ignore-errors').")

(defun gascity-test--render-guard-pure-p (operation args)
  "Return non-nil when OPERATION on ARGS needs no I/O."
  (or (memq operation gascity-test-render-guard-pure-operations)
      (and (eq operation 'expand-file-name)
           (let ((name (car args)))
             (and (stringp name)
                  (file-name-absolute-p name)
                  (not (string-match-p "\\`\\(?:/[^/:]+:[^/:]*:\\)?~" name)))))))

(defun gascity-test--render-guard-handler (operation &rest args)
  "File-name handler signalling on OPERATION unless it is pure.
ARGS are the operation's arguments."
  (if (gascity-test--render-guard-pure-p operation args)
      (let ((inhibit-file-name-handlers
             (cons 'gascity-test--render-guard-handler
                   (and (eq inhibit-file-name-operation operation)
                        inhibit-file-name-handlers)))
            (inhibit-file-name-operation operation))
        (apply operation args))
    (push (cons operation args) gascity-test-render-guard-violations)
    (signal 'gascity-test-render-guard-io (cons operation args))))

(defmacro gascity-test-with-render-guard (&rest body)
  "Run BODY with every I/O file operation on a remote name signalling.
A file-name handler matching every TRAMP name is installed ahead of
TRAMP's own; pure name operations fall through to TRAMP, anything
else — `file-exists-p', `file-attributes', `process-file',
`make-process' with a file handler, `abbreviate-file-name', … —
signals `gascity-test-render-guard-io' and is recorded in
`gascity-test-render-guard-violations', which starts empty.  Use it
with a remote `default-directory' (`gascity-test-with-mock-remote', or
just a /mock:: name when no connection is wanted) around a view
render fed from canned payloads (dashboard-v3 §8.4)."
  (declare (indent 0) (debug t))
  `(let ((file-name-handler-alist
          (cons (cons "\\`/[^/|:]+:" #'gascity-test--render-guard-handler)
                file-name-handler-alist))
         (gascity-test-render-guard-violations nil))
     ,@body))

;;; Store boundary stubs

(defmacro gascity-test-with-store-stubs (reads actions &rest body)
  "Run BODY recording store-side gc spawns instead of running them.
READS names a variable that collects (ARGS CALLBACK ERRBACK) for every
`gascity-reader-read-async' call (most recent first); ACTIONS one
that collects (ARGS CALLBACK) for every `gascity-reader-run-async'
call.  Neither stub calls back — the test fires the parked callbacks —
and both return nil (no process was started)."
  (declare (indent 2) (debug t))
  `(let ((,reads nil) (,actions nil))
     (cl-letf (((symbol-function 'gascity-reader-read-async)
                (lambda (args callback &optional errback &rest _)
                  (push (list args callback errback) ,reads)
                  nil))
               ((symbol-function 'gascity-reader-run-async)
                (lambda (args callback)
                  (push (list args callback) ,actions)
                  nil)))
       ,@body)))

(provide 'gascity-test-helpers)
;;; gascity-test-helpers.el ends here
