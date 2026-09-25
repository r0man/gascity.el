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
;; - Nothing leaks: a test that leaves a live stream in
;;   `gascity-live--streams', a live gascity process or a new repeating
;;   timer behind fails (`gascity-test-leak-check'), and the leftovers
;;   are cleared.  `with-temp-buffer' inhibits `kill-buffer-hook', so a
;;   view mode entered in one never detaches by itself.
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
(require 'gascity-live)

;;; Fresh store per test

(defvar gascity-sling--remembered)

(defun gascity-test--reset-store (&rest _)
  "Clear the payload store and its scheduler before an ERT test.
Also the sling menu's remembered per-city state, another session-wide
table a test could leak into the next."
  (gascity-store-clear)
  (setq gascity-sling--remembered nil))

(advice-add 'ert-run-test :before #'gascity-test--reset-store)

;;; Nothing leaks out of a test

(defvar gascity-test-leak-check 'fail
  "What the per-test leak check does: `fail' the leaking test, `report'
the leak with `message', or nil to skip the check.")

(defvar gascity-test--leak-report nil
  "Leaks recorded in `report' mode, newest first: (TEST . LEAKS).")

(defun gascity-test--repeating-timers ()
  "Return the active repeating timers."
  (seq-filter #'timer--repeat-delay (append timer-list timer-idle-list)))

(defun gascity-test--leaks (timers-before)
  "Return a description of the state the test just run left behind.
TIMERS-BEFORE are the repeating timers active before it.  Checks the
live stream table (`gascity-live--streams'), live processes the stream
and store start, and new repeating timers; then clears them all so the
next test starts clean."
  (let (leaks)
    (when (and (boundp 'gascity-live--streams)
               (> (hash-table-count gascity-live--streams) 0))
      (let (roots)
        (maphash (lambda (root _) (push root roots)) gascity-live--streams)
        (push (cons 'live-streams roots) leaks))
      (gascity-live-stop-all))
    (let ((procs (seq-filter
                  (lambda (p) (and (process-live-p p)
                                   (string-match-p "\\`gascity-\\(live\\|gc\\)"
                                                   (process-name p))))
                  (process-list))))
      (when procs
        (push (cons 'processes (mapcar #'process-name procs)) leaks)
        (mapc #'delete-process procs)))
    (let ((timers (seq-remove (lambda (tm) (memq tm timers-before))
                              (gascity-test--repeating-timers))))
      (when timers
        (push (cons 'repeating-timers
                    (mapcar (lambda (tm) (timer--function tm)) timers))
              leaks)
        (mapc #'cancel-timer timers)))
    leaks))

(defun gascity-test--check-leaks (run test)
  "Around advice for `ert-run-test': RUN TEST, then check for leaks.
A passing test that leaves a live stream, a stream or store process, or
a new repeating timer behind fails (`gascity-test-leak-check')."
  (when (and (boundp 'gascity-live--streams)
             (> (hash-table-count gascity-live--streams) 0))
    (gascity-live-stop-all))
  (let* ((before (gascity-test--repeating-timers))
         (result (funcall run test))
         (leaks (and gascity-test-leak-check
                     (gascity-test--leaks before))))
    (when leaks
      (pcase gascity-test-leak-check
        ('report
         (push (cons (ert-test-name test) leaks) gascity-test--leak-report)
         (message "LEAK %s: %S" (ert-test-name test) leaks))
        ('fail
         (when (ert-test-passed-p result)
           (setq result (make-ert-test-failed
                         :condition (list 'gascity-test-leak leaks)
                         :backtrace nil :infos nil))
           (setf (ert-test-most-recent-result test) result)))))
    result))

(advice-add 'ert-run-test :around #'gascity-test--check-leaks)

;; Tests park the async reader's callbacks and fire them synchronously,
;; so reads requested during a vui mount must spawn inline there; the
;; production timer dispatch is tested on its own
;; (`gascity-test-store-render-dispatch-is-deferred').
(setq gascity-store-inline-render-dispatch t)

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
rendering.  `expand-file-name' is allowed when no `~' needs the remote
home (see `gascity-test--render-guard-pure-p').")

(defvar gascity-test-render-guard-violations nil
  "Operations the render guard refused, most recent first.
Kept so a test can assert on them even when the code under test
swallowed the signal (`ignore-errors').")

(defun gascity-test--render-guard-pure-p (operation args)
  "Return non-nil when OPERATION on ARGS needs no I/O."
  (or (and (memq operation gascity-test-render-guard-pure-operations)
           ;; `file-remote-p' on a host-only name ("/ssh:h:") expands its
           ;; empty localname — the remote home, a round trip — once
           ;; the connection exists; treat it as I/O always.
           (not (and (eq operation 'file-remote-p)
                     (stringp (car args))
                     (string-match-p "\\`/[^/:|]+:[^/:|]*:\\'" (car args)))))
      (and (eq operation 'expand-file-name)
           (let* ((tilde "\\`\\(?:/[^/:]+:[^/:]*:\\)?~")
                  (host-only "\\`/[^/:|]+:[^/:|]*:\\'")
                  (remote-no-slash "\\`/[^/:|]+:[^/:|]*:[^/]")
                  (name (car args))
                  (dir (or (cadr args) default-directory)))
             ;; Pure when nothing needs the remote home: an absolute
             ;; NAME, or a relative one joined to an absolute DIR.
             ;; A host-only name ("/ssh:h:") has an EMPTY localname:
             ;; expanding it asks the host for its home directory.
             (and (stringp name)
                  (not (string-match-p tilde name))
                  (not (string-match-p host-only name))
                  (or (and (file-name-absolute-p name)
                           (not (string-match-p remote-no-slash name)))
                      (and (stringp dir)
                           (file-name-absolute-p dir)
                           (not (string-match-p tilde dir))
                           (not (string-match-p host-only dir))
                           (not (string-match-p remote-no-slash dir)))))))))

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

(defmacro gascity-test-with-temp-view (&rest body)
  "Like `with-temp-buffer', but the buffer dies with its `kill-buffer-hook'.
`with-temp-buffer' inhibits buffer hooks, so a view mode entered in it
never detaches from its city's live stream (`gascity-live-attach') and
leaks it; use this for any test that enters a gascity view mode."
  (declare (indent 0) (debug t))
  (let ((buf (make-symbol "buf")))
    `(let ((,buf (generate-new-buffer " *gascity-test-view*")))
       (unwind-protect
           (with-current-buffer ,buf ,@body)
         (when (buffer-live-p ,buf)
           (let ((kill-buffer-query-functions nil))
             (kill-buffer ,buf)))))))

(provide 'gascity-test-helpers)
;;; gascity-test-helpers.el ends here
