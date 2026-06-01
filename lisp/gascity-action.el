;;; gascity-action.el --- Mutating-command dispatch for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The write/mutate layer of the porcelain (DESIGN.md §7 P1).  It turns
;; the mutating `gascity-command' classes (in `gascity-types') into
;; user-facing actions, reached two ways — both deliberately hand-built,
;; never an auto-generated UI:
;;
;; - **At point** in a list or the dashboard: a key acts on the rig,
;;   session, or order under point, then refreshes the view.  Session
;;   actions resolve their target with `gascity-agent-at-point', so the
;;   same command works in the session list and the status dashboard.
;; - **By prompt** from the `gascity' dispatcher's sub-transients
;;   (`gascity-rig-dispatch', `gascity-session-dispatch',
;;   `gascity-lifecycle-dispatch') or via `M-x': the command reads its
;;   arguments with completion over live `gc' data.
;;
;; Both paths build a command object and run it through
;; `gascity-command-execute-interactive'.  For the quick mutations
;; (everything but city start/stop) that method — specialized here on
;; `gascity-command-action' — runs synchronously via `gascity-command-act'
;; and reports the outcome in the echo area, refreshing the originating
;; view.  City start/stop are long-running, so they keep the base
;; streaming backend (`async-shell-command'); the dispatcher confirms
;; them first.

;;; Code:

(require 'cl-lib)
(require 'transient)
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-reader)
(require 'gascity-context)
(require 'gascity-command)
(require 'gascity-types)
(require 'gascity-section)   ; gascity-agent-at-point
(require 'gascity-tabulated) ; list refresh commands + command runners
(require 'gascity-status)    ; gascity-status-refresh

;;; ============================================================
;;; Synchronous action runner
;;; ============================================================

(defun gascity-action--summarize (result)
  "Return a short human summary of a mutation RESULT (alist, string, or nil)."
  (cond
   ((stringp result)
    (or (car (split-string (string-trim result) "\n" t)) "done"))
   ((and (consp result) (stringp (alist-get 'message result)))
    (alist-get 'message result))
   ((and (consp result) (assq 'ok result))
    (if (alist-get 'ok result) "ok" "failed"))
   (t "done")))

(defun gascity-action--error-detail (err)
  "Return gc's stderr (else the message) from a `gascity-command-error' ERR.
The error data is (MESSAGE . PLIST), so the plist begins at `cddr'."
  (let ((stderr (plist-get (cddr err) :stderr)))
    (if (and (stringp stderr) (not (string-empty-p (string-trim stderr))))
        (string-trim stderr)
      (or (cadr err) "unknown error"))))

(defun gascity-command-act (command)
  "Execute mutating COMMAND, report the outcome, and return its result.
Runs COMMAND through `gascity-command-execute' (validated, synchronous).
On success echoes a one-line summary and returns the parsed result.  A
`gascity-validation-error' or `gascity-command-error' is re-signalled as
a `user-error' carrying gc's stderr, so failures surface as a clean
message in the echo area rather than a backtrace."
  (let ((sub (or (gascity-command-subcommand command) "command")))
    (condition-case err
        (let* ((execution (gascity-command-execute command))
               (result (oref execution result)))
          (message "gc %s: %s" sub (gascity-action--summarize result))
          result)
      (gascity-validation-error
       (user-error "gc %s: %s" sub (cadr err)))
      (gascity-command-error
       (user-error "gc %s failed: %s" sub (gascity-action--error-detail err)))
      ;; Defensive catch-all for any other gascity error (e.g. a JSON
      ;; parse error should a subclass re-enable --json).  Listed last so
      ;; the specific handlers above win.
      (gascity-error
       (user-error "gc %s failed: %s" sub (or (cadr err) "unexpected error"))))))

(cl-defmethod gascity-command-execute-interactive ((command gascity-command-action))
  "Run a mutating COMMAND synchronously and report via `gascity-command-act'.
This is the interactive backend for the quick mutations; the streaming
`async-shell-command' base method still serves read/long-running ones."
  (gascity-command-act command))

;;; ============================================================
;;; Helpers — confirmation, completion, target-at-point, refresh
;;; ============================================================

(defun gascity-action--confirm (format-string &rest args)
  "Ask a yes/no question built from FORMAT-STRING and ARGS."
  (yes-or-no-p (apply #'format format-string args)))

(defun gascity-action--rig-names ()
  "Return the city's rig names, or nil when `gc' is unreachable."
  (condition-case nil
      (delq nil (mapcar (lambda (r) (alist-get 'name r))
                        (append (gascity-reader-rigs) nil)))
    (gascity-error nil)))

(defun gascity-action--session-names ()
  "Return the city's session aliases (qualified agent names) or nil.
Prefers `agent_name' (always qualified) over the volatile `name'."
  (condition-case nil
      (delq nil (mapcar (lambda (s) (or (alist-get 'agent_name s)
                                        (alist-get 'name s)))
                        (append (gascity-reader-sessions) nil)))
    (gascity-error nil)))

(defun gascity-action--order-names ()
  "Return the city's order names, or nil when `gc' is unreachable."
  (condition-case nil
      (delq nil (mapcar (lambda (o) (or (alist-get 'name o)
                                        (alist-get 'scoped_name o)))
                        (append (alist-get 'orders (gascity-command-order-list!)) nil)))
    (gascity-error nil)))

(defun gascity-action--agent-at-point-name ()
  "Return the qualified name of the session/agent at point, or nil."
  (let ((agent (gascity-agent-at-point)))
    (and agent (plist-get agent :name))))

(defun gascity-action--read-rig (prompt)
  "Read a rig name with PROMPT, defaulting to the contextual rig."
  (completing-read prompt (gascity-action--rig-names) nil nil nil nil
                   (gascity-context-rig-name)))

(defun gascity-action--read-session (prompt)
  "Read a session alias with PROMPT, defaulting to the session at point."
  (completing-read prompt (gascity-action--session-names) nil nil nil nil
                   (gascity-action--agent-at-point-name)))

(defun gascity-action--read-order (prompt)
  "Read an order name with PROMPT."
  (completing-read prompt (gascity-action--order-names)))

(defun gascity-action--rig-at-point ()
  "Return the name of the rig at point, or signal a `user-error'."
  (let* ((rig (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id)))
         (name (and (consp rig) (alist-get 'name rig))))
    (or name (user-error "No rig at point"))))

(defun gascity-action--order-at-point ()
  "Return the name of the order at point, or signal a `user-error'."
  (let* ((order (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id)))
         (name (and (consp order) (or (alist-get 'name order)
                                      (alist-get 'scoped_name order)))))
    (or name (user-error "No order at point"))))

(defun gascity-action--session-at-point ()
  "Return the session alias at point, or signal a `user-error'."
  (or (gascity-action--agent-at-point-name)
      (user-error "No session at point")))

(defun gascity--refresh-current-view ()
  "Refresh the current gascity list or dashboard after a mutation."
  (cond
   ((derived-mode-p 'gascity-dashboard-mode) (gascity-status-refresh))
   ((derived-mode-p 'gascity-rig-list-mode) (gascity-rig-list-refresh))
   ((derived-mode-p 'gascity-session-list-mode) (gascity-session-list-refresh))
   ((derived-mode-p 'gascity-order-list-mode) (gascity-order-list-refresh))))

;;; ============================================================
;;; Prompted actions — the sub-transient / `M-x' surface
;;; ============================================================

;;;###autoload
(defun gascity-rig-suspend (name)
  "Suspend rig NAME (prompted; defaults to the contextual rig)."
  (interactive (list (gascity-action--read-rig "Suspend rig: ")))
  (gascity-command-execute-interactive (gascity-command-rig-suspend :name name)))

;;;###autoload
(defun gascity-rig-resume (name)
  "Resume suspended rig NAME (prompted; defaults to the contextual rig)."
  (interactive (list (gascity-action--read-rig "Resume rig: ")))
  (gascity-command-execute-interactive (gascity-command-rig-resume :name name)))

;;;###autoload
(defun gascity-rig-restart (name)
  "Restart rig NAME by killing its agent sessions (the reconciler restarts them)."
  (interactive (list (gascity-action--read-rig "Restart rig: ")))
  (when (gascity-action--confirm "Restart (kill agent sessions of) rig %s? " name)
    (gascity-command-execute-interactive (gascity-command-rig-restart :name name))))

;;;###autoload
(defun gascity-session-nudge (target message)
  "Send MESSAGE to session TARGET (both prompted)."
  (interactive
   (let ((target (gascity-action--read-session "Nudge session: ")))
     (list target (read-string (format "Message to %s: " target)))))
  (gascity-command-execute-interactive
   (gascity-command-session-nudge :target target :message message)))

;;;###autoload
(defun gascity-session-suspend (target)
  "Suspend session TARGET (prompted)."
  (interactive (list (gascity-action--read-session "Suspend session: ")))
  (gascity-command-execute-interactive (gascity-command-session-suspend :target target)))

;;;###autoload
(defun gascity-session-kill (target)
  "Force-kill session TARGET's runtime (prompted; the reconciler restarts it)."
  (interactive (list (gascity-action--read-session "Kill session runtime: ")))
  (when (gascity-action--confirm "Force-kill the runtime of session %s? " target)
    (gascity-command-execute-interactive (gascity-command-session-kill :target target))))

;;;###autoload
(defun gascity-session-wake (target)
  "Wake session TARGET (prompted) and clear holds."
  (interactive (list (gascity-action--read-session "Wake session: ")))
  (gascity-command-execute-interactive (gascity-command-session-wake :target target)))

;;;###autoload
(defun gascity-sling (target arg)
  "Route bead id or task text ARG to session/agent TARGET (both prompted)."
  (interactive
   (let ((target (gascity-action--read-session "Sling to target: ")))
     (list target (read-string "Bead id or task text: "))))
  (gascity-command-execute-interactive (gascity-command-sling :target target :arg arg)))

;;;###autoload
(defun gascity-order-run (name)
  "Run order NAME manually (prompted), bypassing its trigger."
  (interactive (list (gascity-action--read-order "Run order: ")))
  (gascity-command-execute-interactive (gascity-command-order-run :name name)))

;;;###autoload
(defun gascity-start ()
  "Start the Gas City under the machine-wide supervisor (streams output)."
  (interactive)
  (when (gascity-action--confirm "Start the Gas City under the supervisor? ")
    (gascity-command-execute-interactive (gascity-command-start))))

;;;###autoload
(defun gascity-stop (&optional force)
  "Stop all agent sessions in the city.  With prefix arg FORCE, force-kill."
  (interactive "P")
  (when (gascity-action--confirm "Stop the Gas City%s? "
                                 (if force " (force-kill, no grace)" ""))
    (gascity-command-execute-interactive (gascity-command-stop :force (and force t)))))

;;; ============================================================
;;; At-point actions — bound in the list / dashboard keymaps
;;; ============================================================

;;;###autoload
(defun gascity-rig-suspend-at-point ()
  "Suspend the rig at point and refresh the list."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-rig-suspend :name (gascity-action--rig-at-point)))
  (gascity--refresh-current-view))

;;;###autoload
(defun gascity-rig-resume-at-point ()
  "Resume the rig at point and refresh the list."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-rig-resume :name (gascity-action--rig-at-point)))
  (gascity--refresh-current-view))

;;;###autoload
(defun gascity-rig-restart-at-point ()
  "Restart the rig at point (kill its agent sessions) and refresh the list."
  (interactive)
  (let ((name (gascity-action--rig-at-point)))
    (when (gascity-action--confirm "Restart (kill agent sessions of) rig %s? " name)
      (gascity-command-execute-interactive (gascity-command-rig-restart :name name))
      (gascity--refresh-current-view))))

;;;###autoload
(defun gascity-order-run-at-point ()
  "Run the order at point manually and refresh the list."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-order-run :name (gascity-action--order-at-point)))
  (gascity--refresh-current-view))

;;;###autoload
(defun gascity-session-nudge-at-point ()
  "Nudge the session/agent at point with a prompted message, then refresh."
  (interactive)
  (let ((target (gascity-action--session-at-point)))
    (gascity-command-execute-interactive
     (gascity-command-session-nudge
      :target target :message (read-string (format "Message to %s: " target))))
    (gascity--refresh-current-view)))

;;;###autoload
(defun gascity-session-suspend-at-point ()
  "Suspend the session/agent at point and refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-session-suspend :target (gascity-action--session-at-point)))
  (gascity--refresh-current-view))

;;;###autoload
(defun gascity-session-kill-at-point ()
  "Force-kill the runtime of the session/agent at point and refresh."
  (interactive)
  (let ((target (gascity-action--session-at-point)))
    (when (gascity-action--confirm "Force-kill the runtime of session %s? " target)
      (gascity-command-execute-interactive (gascity-command-session-kill :target target))
      (gascity--refresh-current-view))))

;;;###autoload
(defun gascity-session-wake-at-point ()
  "Wake the session/agent at point and refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-session-wake :target (gascity-action--session-at-point)))
  (gascity--refresh-current-view))

;;; ============================================================
;;; Sub-transients — hand-built command-dispatch backends
;;; ============================================================

(transient-define-prefix gascity-rig-dispatch ()
  "Dispatch rig-control actions (a hand-built command backend)."
  ["Rig control"
   ("s" "Suspend rig…" gascity-rig-suspend)
   ("r" "Resume rig…" gascity-rig-resume)
   ("R" "Restart rig…" gascity-rig-restart)])

(transient-define-prefix gascity-session-dispatch ()
  "Dispatch session-control actions (a hand-built command backend)."
  ["Session control"
   ("n" "Nudge…" gascity-session-nudge)
   ("s" "Suspend…" gascity-session-suspend)
   ("k" "Kill runtime…" gascity-session-kill)
   ("w" "Wake…" gascity-session-wake)])

(transient-define-prefix gascity-lifecycle-dispatch ()
  "Dispatch city-lifecycle actions (a hand-built command backend)."
  ["City lifecycle"
   ("S" "Start city" gascity-start)
   ("K" "Stop city" gascity-stop)])

(provide 'gascity-action)
;;; gascity-action.el ends here
