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
(require 'view)
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-reader)
(require 'gascity-context)
(require 'gascity-command)
(require 'gascity-types)
(require 'gascity-domain)    ; typed at-point objects (agent/rig/order)
(require 'gascity-section)   ; gascity-agent-at-point
(require 'gascity-tabulated) ; list refresh commands + command runners
(require 'gascity-status)    ; gascity-status-refresh

;; Detail-view refresh commands live in gascity-rig / gascity-session,
;; which require this module; `gascity--refresh-current-view' calls them
;; by name after a mutation made from a detail buffer.
(declare-function gascity-rig-dashboard-refresh "gascity-rig")
(declare-function gascity-polecat-detail-refresh "gascity-session")

;;; ============================================================
;;; Synchronous action runner
;;; ============================================================

(defun gascity-action--summarize (result)
  "Return a short human summary of a mutation RESULT (alist, string, or nil).
Beyond plain stdout and the generic `message'/`ok' shapes, recognises the
two payload-returning mutations the write surface adds: `create' yields a
new bead id (`id', or `issue' carrying one) summarised as \"created <id>\",
and `send'/`reply' yield a `message_id' summarised as \"sent\".  These
specific shapes are checked before the generic `message'/`ok' clauses so a
payload that also carries a server `message' still reads as the action it
was."
  (cond
   ((stringp result)
    (or (car (split-string (string-trim result) "\n" t)) "done"))
   ((and (consp result) (alist-get 'message_id result)) "sent")
   ((and (consp result) (alist-get 'id result))
    (format "created %s" (alist-get 'id result)))
   ((and (consp result) (alist-get 'issue result))
    (let ((issue (alist-get 'issue result)))
      (format "created %s" (if (consp issue) (alist-get 'id issue) issue))))
   ((and (consp result) (stringp (alist-get 'message result)))
    (alist-get 'message result))
   ((and (consp result) (assq 'ok result))
    (if (alist-get 'ok result) "ok" "failed"))
   (t "done")))

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
       (user-error "gc %s failed: %s" sub (gascity-error-detail err)))
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
                        (append (alist-get 'rigs (gascity-command-rig-list!)) nil)))
    (gascity-error nil)))

(defun gascity-action--session-names ()
  "Return the city's session aliases (qualified agent names) or nil.
Prefers `agent_name' (always qualified) over the volatile `name'."
  (condition-case nil
      (delq nil (mapcar (lambda (s) (or (alist-get 'agent_name s)
                                        (alist-get 'name s)))
                        (append (alist-get 'sessions (gascity-command-session-list!)) nil)))
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
    (and agent (gascity-agent-name agent))))

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

(defun gascity-action--read-bead (prompt)
  "Read a bead id with PROMPT, defaulting to the bead reference at point.
Bead ids have no cheap city-wide completion source (they live in per-rig
stores), so this is a plain `read-string'; the at-point default covers the
common case of acting on the bead already under point."
  (read-string prompt nil nil (gascity-bead-at-point)))

(defun gascity-action--rig-at-point ()
  "Return the name of the rig at point, or signal a `user-error'."
  (let* ((rig (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id)))
         (name (and (gascity-rig-p rig) (gascity-rig-name rig))))
    (or name (user-error "No rig at point"))))

(defun gascity-action--order-at-point ()
  "Return the name of the order at point, or signal a `user-error'.
Prefers the plain `name' (what `gc order run' expects) over the
display-oriented `scoped-name'."
  (let* ((order (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id)))
         (name (and (gascity-order-p order)
                    (or (gascity-order-name order) (gascity-order-scoped-name order)))))
    (or name (user-error "No order at point"))))

(defun gascity-action--session-at-point ()
  "Return the session alias at point, or signal a `user-error'."
  (or (gascity-action--agent-at-point-name)
      (user-error "No session at point")))

(defun gascity--refresh-current-view ()
  "Refresh the current gascity list, dashboard, or detail view after a mutation."
  (cond
   ((derived-mode-p 'gascity-dashboard-mode) (gascity-status-refresh))
   ((derived-mode-p 'gascity-rig-list-mode) (gascity-rig-list-refresh))
   ((derived-mode-p 'gascity-session-list-mode) (gascity-session-list-refresh))
   ((derived-mode-p 'gascity-order-list-mode) (gascity-order-list-refresh))
   ((derived-mode-p 'gascity-convoy-list-mode) (gascity-convoy-list-refresh))
   ((derived-mode-p 'gascity-mail-inbox-mode) (gascity-mail-inbox-refresh))
   ((derived-mode-p 'gascity-rig-dashboard-mode) (gascity-rig-dashboard-refresh))
   ((derived-mode-p 'gascity-session-detail-mode) (gascity-polecat-detail-refresh))))

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
(defun gascity-session-drain (target)
  "Signal session TARGET to drain — wind down gracefully (prompted)."
  (interactive (list (gascity-action--read-session "Drain session: ")))
  (gascity-command-execute-interactive (gascity-command-runtime-drain :target target)))

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

;;;###autoload
(defun gascity-session-drain-at-point ()
  "Signal the session/agent at point to drain (wind down gracefully), then refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-runtime-drain :target (gascity-action--session-at-point)))
  (gascity--refresh-current-view))

;;; ============================================================
;;; Write verbs — bead note, session reset/undrain, city reload, mail
;;; ============================================================
;;
;; The safe additive / lifecycle-completion slice (DESIGN-write-actions.md
;; §7, §12 phase 1).  Each is a `gascity-command-action' run through
;; `gascity-command-act'; bead writes additionally pin their store with
;; `-C' resolved from the bead id's prefix (`gascity-beads--bead-path').

;;; Bead — note (gc bd note)

(defun gascity-bead-note--run (id text)
  "Append note TEXT to bead ID — store-routed by ID's prefix — then refresh.
Resolves ID's store with `gascity-beads--bead-path' and passes it as `-C'
so the write lands in the owning rig's database even when the shared Dolt
server would misroute the working directory (gce-bhr)."
  (gascity-command-execute-interactive
   (gascity-command-bd-note
    :id id :text text :directory (gascity-beads--bead-path id)))
  (gascity--refresh-current-view))

;;;###autoload
(defun gascity-bead-note (id text)
  "Append a one-line note TEXT to bead ID (both prompted).
ID defaults to the bead reference at point."
  (interactive
   (let ((id (gascity-action--read-bead "Note on bead: ")))
     (list id (read-string (format "Note on %s: " id)))))
  (gascity-bead-note--run id text))

;;;###autoload
(defun gascity-bead-note-at-point ()
  "Append a prompted note to the bead reference at point, then refresh."
  (interactive)
  (let ((id (or (gascity-bead-at-point) (user-error "No bead at point"))))
    (gascity-bead-note--run id (read-string (format "Note on %s: " id)))))

;;; Session — reset (fresh restart) and undrain (clear the drain flag)

;;;###autoload
(defun gascity-session-reset (target)
  "Restart session TARGET fresh while preserving its bead (prompted)."
  (interactive (list (gascity-action--read-session "Reset session: ")))
  (when (gascity-action--confirm "Restart session %s fresh (keep its bead)? " target)
    (gascity-command-execute-interactive (gascity-command-session-reset :target target))))

;;;###autoload
(defun gascity-session-reset-at-point ()
  "Restart the session/agent at point fresh (confirmed) and refresh."
  (interactive)
  (let ((target (gascity-action--session-at-point)))
    (when (gascity-action--confirm "Restart session %s fresh (keep its bead)? " target)
      (gascity-command-execute-interactive (gascity-command-session-reset :target target))
      (gascity--refresh-current-view))))

;;;###autoload
(defun gascity-session-undrain (target)
  "Clear the drain flag on session TARGET (prompted) — the inverse of drain."
  (interactive (list (gascity-action--read-session "Undrain session: ")))
  (gascity-command-execute-interactive (gascity-command-runtime-undrain :target target)))

;;;###autoload
(defun gascity-session-undrain-at-point ()
  "Clear the drain flag on the session/agent at point and refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-runtime-undrain :target (gascity-action--session-at-point)))
  (gascity--refresh-current-view))

;;; City — reload config (gc reload)

;;;###autoload
(defun gascity-reload (&optional soft)
  "Re-read the city config and process one reload tick (`gc reload').
With a prefix arg SOFT, pass `--soft' — absorb config drift on open
sessions instead of draining them.  City-level (gc has no `rig reload')."
  (interactive "P")
  (gascity-command-execute-interactive (gascity-command-reload :soft (and soft t)))
  (gascity--refresh-current-view))

;;; Mail — read / archive / mark-read / mark-unread (at point in the inbox)

(defun gascity-mail--id-at-point ()
  "Return the message id of the mail at point, or signal a `user-error'."
  (let* ((message (gascity-mail-at-point))
         (id (and message (gascity-mail-id message))))
    (if (and id (stringp id) (not (string-empty-p id)))
        id
      (user-error "No message at point"))))

(defun gascity-mail--show-body (id text)
  "Pop a read-only view buffer showing body TEXT of message ID."
  (let ((buf (get-buffer-create (format "*gc-mail: %s*" id))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (if (and (stringp text) (not (string-empty-p (string-trim text))))
                    text
                  "(no message body)"))
        (goto-char (point-min)))
      (view-mode 1))
    (pop-to-buffer buf)))

;;;###autoload
(defun gascity-mail-read-at-point ()
  "Read the message at point and mark it read, show its body, then refresh.
`RET' shows the cached fields without contacting gc; this `r' action runs
`gc mail read', which also marks the message read, so the default
unread-filtered inbox drops it on refresh."
  (interactive)
  (let* ((id (gascity-mail--id-at-point))
         (text (gascity-command-act (gascity-command-mail-read :id id))))
    (gascity-mail--show-body id text)
    (gascity--refresh-current-view)))

;;;###autoload
(defun gascity-mail-archive-at-point ()
  "Archive the message at point (confirmed) and refresh."
  (interactive)
  (let ((id (gascity-mail--id-at-point)))
    (when (gascity-action--confirm "Archive message %s? " id)
      (gascity-command-execute-interactive (gascity-command-mail-archive :id id))
      (gascity--refresh-current-view))))

;;;###autoload
(defun gascity-mail-mark-read-at-point ()
  "Mark the message at point read without opening it, then refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-mail-mark-read :id (gascity-mail--id-at-point)))
  (gascity--refresh-current-view))

;;;###autoload
(defun gascity-mail-mark-unread-at-point ()
  "Mark the message at point unread and refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-mail-mark-unread :id (gascity-mail--id-at-point)))
  (gascity--refresh-current-view))

;;; ============================================================
;;; Peek — read-only output capture (no mutation, no refresh)
;;; ============================================================
;;
;; `gc session peek' is read-only, so it does not go through the
;; `gascity-command-action' summary path: instead its captured text
;; (json off) is shown verbatim in a read-only view buffer.  A gc
;; failure (e.g. a stopped session) surfaces as a clean `user-error'.

(defconst gascity-session-peek-lines 50
  "Default number of trailing output lines `gascity-session-peek' captures.")

(defun gascity-session-peek--buffer-name (target)
  "Return the peek buffer name for session TARGET."
  (format "*gc-peek: %s*" target))

(defun gascity-session-peek--show (target lines)
  "Capture TARGET's last LINES of output via `gc session peek' and show it.
Pops a read-only view buffer with the captured text.  A validation or gc
error surfaces as a `user-error'."
  (let* ((cmd (gascity-command-session-peek
               :target target :lines (number-to-string lines)))
         (text (condition-case err
                   (oref (gascity-command-execute cmd) result)
                 (gascity-validation-error
                  (user-error "gc session peek: %s" (cadr err)))
                 (gascity-command-error
                  (user-error "gc session peek failed: %s"
                              (gascity-error-detail err))))))
    (let ((buf (get-buffer-create (gascity-session-peek--buffer-name target))))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (if (and (stringp text) (not (string-empty-p (string-trim text))))
                      text
                    "(no output captured)"))
          (goto-char (point-min)))
        (view-mode 1))
      (pop-to-buffer buf))))

;;;###autoload
(defun gascity-session-peek (target &optional lines)
  "Show recent output of session TARGET without attaching (prompted).
With a prefix argument, capture that many trailing LINES instead of the
`gascity-session-peek-lines' default."
  (interactive
   (list (gascity-action--read-session "Peek session: ")
         (and current-prefix-arg (prefix-numeric-value current-prefix-arg))))
  (gascity-session-peek--show target (or lines gascity-session-peek-lines)))

;;;###autoload
(defun gascity-session-peek-at-point ()
  "Show recent output of the session/agent at point without attaching."
  (interactive)
  (gascity-session-peek--show (gascity-action--session-at-point)
                              gascity-session-peek-lines))

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
   ("w" "Wake…" gascity-session-wake)
   ("D" "Drain…" gascity-session-drain)
   ("v" "Peek output…" gascity-session-peek)])

(transient-define-prefix gascity-lifecycle-dispatch ()
  "Dispatch city-lifecycle actions (a hand-built command backend)."
  ["City lifecycle"
   ("S" "Start city" gascity-start)
   ("K" "Stop city" gascity-stop)])

(provide 'gascity-action)
;;; gascity-action.el ends here
