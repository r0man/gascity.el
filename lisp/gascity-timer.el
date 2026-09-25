;;; gascity-timer.el --- Deferred calls that survive TRAMP's timer suspension -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; TRAMP runs `accept-process-output' inside `with-tramp-suspended-timers',
;; which let-binds `timer-list' and `timer-idle-list' to nil.  A process
;; sentinel or filter that fires in that window and calls `run-at-time'
;; puts its timer on the temporary list, which is thrown away when the
;; binding unwinds: the timer never runs.  gascity defers work out of
;; sentinels on purpose (no TRAMP operation inside another), so a lost
;; timer meant a read whose completion was never delivered — a view
;; stuck at `…' forever (B1) — and every `unless (timerp …)' guard
;; wedged for good, since the dead timer still looked scheduled.
;;
;; `gascity-timer-at' is the replacement for those timers: the call is
;; recorded in a global list (a plain variable, which the suspension
;; does not touch) and also scheduled with `run-at-time' as the fast
;; path.  Whichever runs it first wins, once.  A call whose fast timer
;; was lost is run by the watchdog — a repeating timer created when this
;; file loads, never from a sentinel, so it is always on the real
;; `timer-list' — or by `gascity-timer-drain' from an entry point.  The
;; drain refuses to run inside a suspension window (`timer-list' is not
;; its toplevel value), so deferred work still never runs inside a
;; TRAMP operation, and an entry point only runs calls that are clearly
;; lost (overdue), never ones whose timer is about to fire.

;;
;; The watchdog stays armed for the whole session, deliberately.  Most
;; `gascity-timer-at' calls come from sentinels and filters, i.e. from
;; exactly the windows in which a timer is lost: a watchdog stopped
;; while idle and restarted from `gascity-timer-at' would then be lost
;; together with the call's own timer, and the call would wait for the
;; next store entry point — the B1 hang again.  An idle tick costs one
;; nil check every `gascity-timer-watchdog-interval' seconds.

;;; Code:

(require 'cl-lib)
(require 'seq)

(defcustom gascity-timer-watchdog-interval 0.5
  "Seconds between runs of the watchdog that rescues lost deferred calls.
A deferred call whose own timer was discarded by TRAMP's timer
suspension runs at most this long after it was due."
  :type 'number
  :group 'gascity)

(cl-defstruct (gascity-timer--item (:constructor gascity-timer--item-create)
                                   (:copier nil))
  "One deferred call."
  due fn args done timer)

(defvar gascity-timer--items nil
  "Deferred calls not yet run, in no particular order.")

(defvar gascity-timer--watchdog nil
  "The repeating timer running overdue deferred calls.")

(defun gascity-timer--run (item)
  "Run deferred ITEM unless it already ran or was cancelled."
  (unless (gascity-timer--item-done item)
    (setf (gascity-timer--item-done item) t)
    (setq gascity-timer--items (delq item gascity-timer--items))
    (when (timerp (gascity-timer--item-timer item))
      (cancel-timer (gascity-timer--item-timer item)))
    (condition-case err
        (apply (gascity-timer--item-fn item) (gascity-timer--item-args item))
      (error (message "gascity: deferred call failed: %s"
                      (error-message-string err))))))

(defun gascity-timer-at (secs fn &rest args)
  "Call FN with ARGS after SECS seconds, even if its timer gets lost.
Like `run-at-time' with a nil repeat, but safe to call from a process
sentinel or filter: see the commentary.  Returns a handle for
`gascity-timer-cancel' and `gascity-timer-pending-p'."
  (let ((item (gascity-timer--item-create
               :due (+ (float-time) (or secs 0)) :fn fn :args args)))
    (push item gascity-timer--items)
    (setf (gascity-timer--item-timer item)
          (run-at-time (or secs 0) nil #'gascity-timer--run item))
    item))

(defun gascity-timer-cancel (handle)
  "Cancel the deferred call HANDLE (from `gascity-timer-at'); nil is fine."
  (when (gascity-timer--item-p handle)
    (setf (gascity-timer--item-done handle) t)
    (setq gascity-timer--items (delq handle gascity-timer--items))
    (when (timerp (gascity-timer--item-timer handle))
      (cancel-timer (gascity-timer--item-timer handle)))))

(defun gascity-timer-pending-p (handle)
  "Return non-nil while the deferred call HANDLE has neither run nor been
cancelled.  The guard to use where code tested `timerp' on a timer
that could have been lost."
  (and (gascity-timer--item-p handle) (not (gascity-timer--item-done handle))))

(defun gascity-timer-suspended-p ()
  "Return non-nil inside a timer-suspension window (TRAMP's).
There `timer-list' is let-bound: it is not its toplevel value."
  (not (eq timer-list (default-toplevel-value 'timer-list))))

(defconst gascity-timer--lost-after 0.25
  "Seconds overdue after which an entry point treats a call as lost.")

(defun gascity-timer-drain (&optional grace)
  "Run the deferred calls overdue by more than GRACE seconds, oldest first.
The watchdog drains with no grace; an entry point passes
`gascity-timer--lost-after' (see `gascity-timer-rescue').  Does nothing
inside a suspension window: deferred work must not run inside a TRAMP
call."
  (unless (gascity-timer-suspended-p)
    (gascity-timer--start-watchdog)
    (gascity-timer--drain-due grace)))

(defun gascity-timer--drain-due (grace)
  "Run the deferred calls overdue by more than GRACE seconds, oldest first."
  (when gascity-timer--items
    (let* ((limit (- (float-time) (or grace 0)))
           (due (sort (seq-filter (lambda (i) (<= (gascity-timer--item-due i) limit))
                                  gascity-timer--items)
                      (lambda (a b) (< (gascity-timer--item-due a)
                                       (gascity-timer--item-due b))))))
      (mapc #'gascity-timer--run due))))

(defun gascity-timer-rescue ()
  "Run deferred calls whose timer was lost; for gascity's entry points.
Cheap when nothing is pending."
  (when gascity-timer--items
    (gascity-timer-drain gascity-timer--lost-after)))

(defun gascity-timer--start-watchdog ()
  "Start the watchdog unless it runs (idempotent).
Called at load time and from a drain outside any suspension window —
never from where a timer could be lost."
  (unless (and (timerp gascity-timer--watchdog)
               (memq gascity-timer--watchdog timer-list))
    (when (timerp gascity-timer--watchdog)
      (cancel-timer gascity-timer--watchdog))
    (setq gascity-timer--watchdog
          (run-at-time gascity-timer-watchdog-interval
                       gascity-timer-watchdog-interval
                       (lambda ()
                         (unless (gascity-timer-suspended-p)
                           (gascity-timer--drain-due 0)))))))

(gascity-timer--start-watchdog)

(provide 'gascity-timer)
;;; gascity-timer.el ends here
