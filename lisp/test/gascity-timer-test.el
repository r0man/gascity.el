;;; gascity-timer-test.el --- Deferred calls under TRAMP's timer suspension -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; B1: TRAMP's `with-tramp-suspended-timers' let-binds `timer-list' to
;; nil around `accept-process-output'; a timer a sentinel creates in that
;; window is discarded when the binding unwinds.  These tests open the
;; same window with a plain `let' and check that deferred work — a store
;; completion, the live stream's debounce flush — still runs.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(defmacro gascity-timer-test--suspended (&rest body)
  "Run BODY the way TRAMP runs a sentinel: with timers suspended."
  (declare (indent 0))
  `(let (timer-list timer-idle-list) ,@body))

(defun gascity-timer-test--wait (pred &optional secs)
  "Run timers until PRED holds or SECS (default 2) pass; return PRED."
  (let ((deadline (+ (float-time) (or secs 2))))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall pred)))

(ert-deftest gascity-test-timer-suspension-detected ()
  "Inside the window `timer-list' is not its toplevel value."
  (should-not (gascity-timer-suspended-p))
  (gascity-timer-test--suspended
    (should (gascity-timer-suspended-p))))

(ert-deftest gascity-test-timer-lost-timer-rescued-by-watchdog ()
  "A call deferred inside the window runs anyway, exactly once."
  (let ((runs 0))
    (gascity-timer-test--suspended
      (gascity-timer-at 0 (lambda () (cl-incf runs)))
      ;; Its `run-at-time' went onto the temporary list.
      (should (= (length timer-list) 1)))
    (should (gascity-timer-test--wait (lambda () (= runs 1))))
    (accept-process-output nil 0.6)
    (should (= runs 1))))

(ert-deftest gascity-test-timer-drain-refuses-inside-window ()
  "A drain inside the window runs nothing: deferred work never runs
inside a TRAMP operation; an entry point rescues only lost calls."
  (let ((runs 0) item)
    (gascity-timer-test--suspended
      (setq item (gascity-timer-at 0 (lambda () (cl-incf runs))))
      (gascity-timer-drain)
      (should (= runs 0)))
    ;; Not yet overdue enough: an entry point leaves it to its timer.
    (gascity-timer-rescue)
    (should (gascity-timer-pending-p item))
    (sleep-for 0.3)
    ;; Now clearly lost: the next entry point runs it (unless the
    ;; watchdog got there first) — once.
    (gascity-timer-rescue)
    (should (= runs 1))
    (should-not (gascity-timer-pending-p item))))

(ert-deftest gascity-test-timer-cancel ()
  "A cancelled call never runs, lost timer or not."
  (let ((runs 0) item)
    (gascity-timer-test--suspended
      (setq item (gascity-timer-at 0 (lambda () (cl-incf runs)))))
    (gascity-timer-cancel item)
    (accept-process-output nil 0.7)
    (should (= runs 0))))

(ert-deftest gascity-test-timer-store-completion-survives-suspension ()
  "B1: a remote read's completion, deferred from a sentinel that runs
while TRAMP has suspended timers, is still delivered — the view does
not hang at `…'."
  (gascity-test-ensure-mock-method)
  (let ((tramp-verbose 0)
        (default-directory "/mock::/tmp/lost-timer-city/")
        (cb nil) (got nil))
    (setf (gascity-store--host-primed
           (gascity-store--host (file-remote-p default-directory)))
          t)
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (lambda (_args callback &rest _) (setq cb callback) nil)))
      (gascity-store-fetch '("session" "list") (lambda (d) (setq got d)))
      (should cb)
      ;; The process finishes while TRAMP waits for another process.
      (gascity-timer-test--suspended
        (funcall cb 'payload)))
    (should (gascity-timer-test--wait (lambda () (eq got 'payload))))
    (let ((snap (gascity-store-get '("session" "list"))))
      (should (eq (plist-get snap :status) 'ready))
      (should-not (plist-get snap :pending)))))

(ert-deftest gascity-test-timer-store-deadline-armed-until-complete ()
  "The read's deadline stays armed until its completion has run."
  (gascity-test-ensure-mock-method)
  (let ((tramp-verbose 0)
        (gascity-remote-async-timeout 30)
        (default-directory "/mock::/tmp/lost-timer-city/")
        (cb nil) job)
    (setf (gascity-store--host-primed
           (gascity-store--host (file-remote-p default-directory)))
          t)
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (lambda (_args callback &rest _) (setq cb callback) nil)))
      (gascity-store-fetch '("status") #'ignore)
      (setq job (gascity-store-entry-job
                 (gascity-store--entry (gascity-store--dir nil) '("status"))))
      (gascity-timer-test--suspended
        (funcall cb 'payload)
        ;; Finished, not yet completed: the deadline is still pending.
        (should (gascity-timer-pending-p (gascity-store--job-timer job)))))
    (should (gascity-timer-test--wait
             (lambda () (not (gascity-timer-pending-p (gascity-store--job-timer job))))))))

(ert-deftest gascity-test-timer-live-debounce-survives-suspension ()
  "The live stream's debounce flush, armed from its filter while timers
are suspended, still runs — and the next batch arms a new one."
  (let ((stream (gascity-live--stream-create :root "/tmp/city/"))
        (gascity-live-debounce 0.05)
        (flushed nil))
    (cl-letf (((symbol-function 'gascity-live--invalidate)
               (lambda (_root _kinds types) (push types flushed))))
      (gascity-timer-test--suspended
        (gascity-live--queue stream "mail.sent"))
      (should (gascity-timer-test--wait (lambda () flushed)))
      (should (equal (car flushed) '("mail.sent")))
      (gascity-live--queue stream "session.woke")
      (should (gascity-timer-test--wait (lambda () (= (length flushed) 2)))))))

(provide 'gascity-timer-test)
;;; gascity-timer-test.el ends here
