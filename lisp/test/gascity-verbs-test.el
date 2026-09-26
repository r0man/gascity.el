;;; gascity-verbs-test.el --- Row verbs: session-less agents, rig rows -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; QA's destructive-actions pass on bright-lights
;; (docs/qa/2026-09-26-dashboard-v3-extended.md):
;;
;; D-1: a pool slot (`bd.dog-1') has no session until work arrives, so
;; the session verbs refuse it with the reason instead of sending gc a
;; call that fails with "session not found".
;; D-2: `s'/`r'/`R' on a rig row of a vui view (the cockpit's Rigs, the
;; rig dashboard's title line) act on the rig (§5.3).
;; D-3: a session gc reports `asleep' (after a reset) is no running
;; agent in the roster the follow-up re-reads repaint.
;;
;; The gc boundary is stubbed; nothing here runs gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(defconst gascity-verbs-test--sessions
  '((sessions . [((id . "bl-rpq") (alias . "mayor") (agent_name . "mayor")
                  (session_name . "mayor") (state . "asleep"))]))
  "A `session list' payload: the mayor (asleep), no pool slot.")

(defconst gascity-verbs-test--session-verbs
  '(gascity-session-nudge-at-point gascity-session-suspend-at-point
    gascity-session-kill-at-point gascity-session-wake-at-point
    gascity-session-drain-at-point gascity-session-reset-at-point
    gascity-session-undrain-at-point gascity-session-peek-at-point
    gascity-tmux-at-point gascity-dashboard-suspend gascity-dashboard-reset)
  "Every agent verb that acts on the agent's session (M s K w D R U v t).")

(defmacro gascity-verbs-test--with-row (name sessions ran &rest body)
  "Run BODY on an agent row NAME, `session list' SESSIONS in the store.
RAN collects what reached gc (commands, attaches, peeks)."
  (declare (indent 3))
  `(let ((,ran nil))
     (cl-letf (((symbol-function 'gascity-store-get)
                (lambda (args &optional _dir)
                  (and ,sessions (equal args '("session" "list"))
                       (list :status 'ready :data ,sessions))))
               ((symbol-function 'gascity-command-execute-interactive)
                (lambda (cmd) (push cmd ,ran)))
               ((symbol-function 'gascity-agent-attach-tmux)
                (lambda (agent) (push agent ,ran)))
               ((symbol-function 'gascity-session-peek--show)
                (lambda (target _lines) (push target ,ran)))
               ((symbol-function 'gascity-action--confirm) (lambda (&rest _) t))
               ((symbol-function 'read-string) (lambda (&rest _) "hi")))
       (with-temp-buffer
         (insert (propertize "  ○ dog-1  stopped"
                             'gascity-agent (gascity-agent :name ,name :running nil)
                             'gascity-rig nil))
         (goto-char (point-min))
         ,@body))))

(ert-deftest gascity-test-verbs-pool-slot-refused-with-reason ()
  "Every session verb on a session-less pool slot says why and calls no gc."
  (gascity-verbs-test--with-row "bd.dog-1" gascity-verbs-test--sessions ran
    (dolist (verb gascity-verbs-test--session-verbs)
      (let ((err (should-error (funcall verb) :type 'user-error)))
        (should (equal (cadr err)
                       "bd.dog-1 has no session; pool slots start when work arrives"))))
    (should-not ran)))

(ert-deftest gascity-test-verbs-agent-with-session-runs ()
  "An agent with a session row — asleep included (wake is for it) — runs."
  (gascity-verbs-test--with-row "mayor" gascity-verbs-test--sessions ran
    (dolist (verb gascity-verbs-test--session-verbs)
      (funcall verb))
    (should (= (length ran) (length gascity-verbs-test--session-verbs)))))

(ert-deftest gascity-test-verbs-no-session-list-in-hand-runs ()
  "With no `session list' in the store the verb is not second-guessed."
  (gascity-verbs-test--with-row "bd.dog-1" nil ran
    (gascity-session-wake-at-point)
    (should (= (length ran) 1))))

(ert-deftest gascity-test-verbs-pool-slot-drawer-says-how-it-starts ()
  "The cockpit/Agents drawer of a session-less pool slot explains it."
  (cl-letf (((symbol-function 'gascity-store-get)
             (lambda (&rest _) (list :status 'ready :data gascity-verbs-test--sessions))))
    (should (member "no session; pool slots start when work arrives"
                    (gascity-dashboard--agent-drawer
                     (list :name "bd.dog-1" :state 'stopped))))
    ;; A stopped agent that has a session keeps the plain line.
    (should (member "stopped, no session"
                    (gascity-dashboard--agent-drawer
                     (list :name "mayor" :state 'stopped))))))

;;; D-2: rig rows

(defmacro gascity-verbs-test--on-rig-row (ran &rest body)
  "Run BODY on a cockpit Rigs row for hello-world; RAN collects gc commands."
  (declare (indent 1))
  `(let ((,ran nil))
     (cl-letf (((symbol-function 'gascity-command-execute-interactive)
                (lambda (cmd) (push cmd ,ran)))
               ((symbol-function 'gascity-action--confirm) (lambda (&rest _) t)))
       (with-temp-buffer
         (insert (propertize "  ○ hello-world  stopped"
                             'gascity-rig "hello-world"
                             'gascity-rig-dir "/home/roman/hello-world"))
         (goto-char (point-min))
         ,@body))))

(ert-deftest gascity-test-verbs-rig-row-dispatches-rig-verbs ()
  "`s' `r' `R' on a Rigs row suspend, resume and restart the rig (§5.3)."
  (gascity-verbs-test--on-rig-row ran
    (gascity-dashboard-suspend)
    (gascity-rig-resume-at-point)
    (gascity-dashboard-reset)
    (should (equal (mapcar #'eieio-object-class (reverse ran))
                   '(gascity-command-rig-suspend gascity-command-rig-resume
                     gascity-command-rig-restart)))
    (should (seq-every-p (lambda (c) (equal (oref c name) "hello-world")) ran))))

(ert-deftest gascity-test-verbs-agent-row-rig-is-not-the-rig-at-point ()
  "An agent row carries its rig too, but the rig verbs do not take it."
  (with-temp-buffer
    (insert (propertize "row" 'gascity-rig "hello-world"
                        'gascity-agent (gascity-agent :name "hello-world/w-1")))
    (goto-char (point-min))
    (should-error (gascity-rig-resume-at-point) :type 'user-error)))

(ert-deftest gascity-test-verbs-rig-dashboard-keys ()
  "The rig dashboard's `s'/`R' decide by row, `r' resumes its rig."
  (should (eq (keymap-lookup gascity-rig-dashboard-mode-map "s") #'gascity-dashboard-suspend))
  (should (eq (keymap-lookup gascity-rig-dashboard-mode-map "R") #'gascity-dashboard-reset))
  (should (eq (keymap-lookup gascity-rig-dashboard-mode-map "r") #'gascity-rig-resume-at-point))
  ;; Its title line is a rig row.
  (let ((props (vui-vnode-text-properties
                (gascity-rig--header-vnode '((name . "hello-world") (path . "/tmp/hw"))
                                           "bright-lights"))))
    (should (equal (plist-get props 'gascity-rig) "hello-world"))
    (should-not (plist-get props 'gascity-agent))))

;;; D-3: an asleep session is no running agent

(ert-deftest gascity-test-verbs-asleep-session-not-running ()
  "After a reset gc reports the session `asleep': the re-read roster shows
the agent as not running (the action's follow-up re-reads repaint it)."
  (let* ((status '((agents . [((qualified_name . "core.control-dispatcher")
                                (running . t))])))
         (row (lambda (state)
                (car (gascity-dashboard--agents
                      status
                      (list `((id . "bl-bbo2") (alias . "core.control-dispatcher")
                              (agent_name . "core.control-dispatcher")
                              (state . ,state)))
                      nil "bright-lights" (float-time))))))
    (should (eq (plist-get (funcall row "active") :state) 'running))
    (should-not (eq (plist-get (funcall row "asleep") :state) 'running))))

;;; D-4: city-wide prompts name the city

(defun gascity-verbs-test--prompts (dir)
  "Return the confirm prompts of the city-wide verbs run in city DIR."
  (let ((default-directory dir) prompts)
    (cl-letf (((symbol-function 'gascity-context-city-root-cached) (lambda (&rest _) dir))
              ((symbol-function 'gascity-action--confirm)
               (lambda (fmt &rest args) (push (apply #'format fmt args) prompts) nil)))
      (gascity-start)
      (gascity-stop)
      (gascity-stop t)
      (gascity-session-prune "" "")
      (gascity-health-doctor-fix))
    (nreverse prompts)))

(ert-deftest gascity-test-verbs-city-prompts-name-the-city ()
  "Start, stop, prune and doctor --fix name the city, `@host' when remote
\(QA D-4: \"Stop the Gas City?\" with several cities open)."
  (should (equal (gascity-verbs-test--prompts "/home/roman/bright-lights/")
                 '("Start bright-lights under the supervisor? "
                   "Stop bright-lights? "
                   "Stop bright-lights (force-kill, no grace)? "
                   "Prune dormant sessions of bright-lights? "
                   "Run gc doctor --fix in bright-lights? ")))
  (should (equal (car (gascity-verbs-test--prompts
                       "/ssh:gascity@burningswell.com:/home/gascity/burningswell/"))
                 "Start burningswell@burningswell.com under the supervisor? ")))

(provide 'gascity-verbs-test)
;;; gascity-verbs-test.el ends here
