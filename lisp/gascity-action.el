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
;; `gascity-command-action' — STARTS the gc call and returns
;; (`gascity-command-act-async' on the store's action lane, dashboard-v3
;; D9, §8.5): input is gathered first, the result is echoed when gc
;; answers, and the originating view refreshes then.  City start/stop
;; are long-running, so they keep the base streaming backend
;; (`async-shell-command'); the dispatcher confirms them first.
;; `gascity-command-act' remains the synchronous runner for callers
;; that need the result inline.

;;; Code:

(require 'cl-lib)
(require 'transient)
(require 'beads-prefix)
(require 'view)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-error)
(require 'gascity-reader)
(require 'gascity-store)
(require 'gascity-context)
(require 'gascity-command)
(require 'gascity-types)
(require 'gascity-compose)   ; multi-line body buffer (mail send/reply)
(require 'gascity-domain)    ; typed at-point objects (agent/rig/order)
(require 'gascity-section)   ; gascity-agent-at-point
(require 'gascity-tabulated) ; list refresh commands + command runners

;; Detail-view refresh commands live in gascity-rig / gascity-session,
;; which require this module; `gascity--refresh-current-view' calls them
;; by name after a mutation made from a detail buffer.
(declare-function gascity-dashboard-refresh "gascity-dashboard")
(declare-function gascity-rig-dashboard-refresh "gascity-rig")
(declare-function gascity-polecat-detail-refresh "gascity-session")

;; The formula sling's machinery lives in gascity-formula, which loads
;; before this module; the unified sling prefix drives it from here
;; (cross-file verb wiring — a missing declaration is only caught by the
;; `--warnings-as-errors' compile gate).
(declare-function gascity-sling-formula--bead-or-convoy-at-point "gascity-formula")
(declare-function gascity-sling-formula--read-formula "gascity-formula")
(declare-function gascity-sling-formula--current-values "gascity-formula")
(declare-function gascity-sling-formula--dispatch "gascity-formula")
(declare-function gascity-sling-formula--show-recipe "gascity-formula")
(declare-function gascity-sling-formula--var-children "gascity-formula")
(declare-function gascity-formula-recipe-cached "gascity-formula")
(declare-function gascity-formula-invalidate "gascity-formula")
(declare-function gascity-formula-refresh-async "gascity-formula")

;;; ============================================================
;;; Synchronous action runner (inline-result callers only)
;;; ============================================================

(defun gascity-action--summarize (result)
  "Return a short human summary of a mutation RESULT (alist, string, or nil).
Beyond plain stdout and the generic `message'/`ok' shapes, recognises the
payload-returning mutations the write surface adds: `mail send'/`reply'
yield the sent message — summarised as \"sent\" — and `bd create' yields a
new bead id (`id', or `issue' carrying one) summarised as \"created <id>\".

The send/reply check comes *before* the `id' clause because the live
`gc mail send/reply --json' object carries a top-level `id' (the new
message's id) and an `action' of \"send\"/\"reply\" but no `message_id';
without the action guard a sent message would mis-summarise as \"created
<message-id>\".  The legacy `message_id' shape is still honoured.  All of
these win over the generic `message'/`ok' clauses so a payload that also
carries a server `message' still reads as the action it was."
  (cond
   ((stringp result)
    (or (car (split-string (string-trim result) "\n" t)) "done"))
   ((and (consp result)
         (or (alist-get 'message_id result)
             (member (alist-get 'action result) '("send" "reply"))))
    "sent")
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
          (message "GC %s: %s" sub (gascity-action--summarize result))
          result)
      (gascity-validation-error
       (user-error "GC %s: %s" sub (cadr err)))
      (gascity-command-error
       (user-error "GC %s failed: %s" sub (gascity-error-detail err)))
      ;; Defensive catch-all for any other gascity error (e.g. a JSON
      ;; parse error should a subclass re-enable --json).  Listed last so
      ;; the specific handlers above win.
      (gascity-error
       (user-error "GC %s failed: %s" sub (or (cadr err) "unexpected error"))))))

;;; ============================================================
;;; Asynchronous action runner (dashboard-v3 D9, §8.5)
;;; ============================================================

(defconst gascity-action--done-verbs
  '(("session suspend" . "Suspended")
    ("session wake" . "Woke")
    ("session kill" . "Killed the runtime of")
    ("session reset" . "Reset")
    ("session nudge" . "Nudged")
    ("session close" . "Closed")
    ("session pin" . "Pinned")
    ("session unpin" . "Unpinned")
    ("session rename" . "Renamed")
    ("runtime drain" . "Draining")
    ("runtime undrain" . "Undrained")
    ("rig suspend" . "Suspended rig")
    ("rig resume" . "Resumed rig")
    ("rig restart" . "Restarted rig")
    ("rig remove" . "Removed rig")
    ("mail archive" . "Archived")
    ("mail mark-read" . "Marked read")
    ("mail mark-unread" . "Marked unread")
    ("order run" . "Ran order"))
  "Success echo verbs by gc subcommand: \"<verb> <target>\".
Subcommands not listed echo \"GC <sub>: <summary>\" instead.")

(defun gascity-action--command-target (command)
  "Return the object id COMMAND acts on, or nil.
The first non-blank of its `target', `name' or `id' slot: the session,
rig, order, message or bead the action serializes on (§8.5)."
  (cl-some (lambda (slot)
             (and (slot-exists-p command slot)
                  (slot-boundp command slot)
                  (let ((v (slot-value command slot)))
                    (and (stringp v) (not (string-empty-p v)) v))))
           '(target name id)))

(defun gascity-action--success-text (command target result)
  "Return the success echo for COMMAND on TARGET with parsed RESULT."
  (let* ((sub (or (gascity-command-subcommand command) "command"))
         (verb (cdr (assoc sub gascity-action--done-verbs))))
    (if (and verb target)
        (format "%s %s" verb target)
      (format "GC %s: %s" sub (gascity-action--summarize result)))))

(cl-defun gascity-command-act-async (command &key target on-success on-error
                                             (origin (current-buffer))
                                             (invalidate t))
  "Start mutating COMMAND and return at once; report when it finishes.
The D9 runner behind every input-free verb: COMMAND is validated here
\(a `user-error' on failure, before anything runs), then handed to
`gascity-store-action', which runs it asynchronously on the action lane
of the calling buffer's host, serialized per TARGET (default: the
command's own target/name/id, see `gascity-action--command-target').
On success ON-SUCCESS is called with the parsed result (JSON when the
command asks for it, else stdout); without it the success text
\(`gascity-action--success-text', e.g. \"Suspended mayor\") is
echoed.  Either way ORIGIN (default the current buffer) is then
refreshed if still live.  On failure the first stderr line is echoed
\(or passed to ON-ERROR) and the full stderr lands in the city's
`*gascity-log: CITY*' buffer — never a modal error.  With INVALIDATE
nil (read-only verbs such as peek) the store's caches are left alone.
Returns nil."
  (let ((sub (or (gascity-command-subcommand command) "command")))
    (when-let* ((msg (gascity-command-validate command)))
      (user-error "GC %s: Command validation failed: %s" sub msg))
    (let* ((target (or target (gascity-action--command-target command)))
           (refresh (lambda ()
                      (when (and invalidate (buffer-live-p origin))
                        (with-current-buffer origin
                          (gascity--refresh-current-view))))))
      (gascity-store-action
       (cdr (gascity-command-line command))
       :target target
       :json (and (slot-exists-p command 'json) (slot-value command 'json))
       :invalidate invalidate
       :on-success (lambda (result)
                     (if on-success
                         (funcall on-success result)
                       (message "%s" (gascity-action--success-text
                                      command target result)))
                     (funcall refresh))
       :on-error on-error)
      nil)))

(cl-defmethod gascity-command-execute-interactive ((command gascity-command-action))
  "Start mutating COMMAND asynchronously via `gascity-command-act-async'.
The interactive backend of the quick mutations (dashboard-v3 D9): input
was gathered by the caller, the gc call now runs in the background and
reports in the echo area.  City start/stop keep the streaming
`async-shell-command' base method."
  (gascity-command-act-async command))

(defun gascity-action--bead-store (id)
  "Return the store directory owning bead ID, preferring the rig memo.
`gascity-beads--bead-path-cached' answers without spawning gc; only a
cold memo falls back to the `gc rig list' read of
`gascity-beads--bead-path'."
  (or (gascity-beads--bead-path-cached id)
      (gascity-beads--bead-path id)))

;;; ============================================================
;;; Helpers — confirmation, completion, target-at-point, refresh
;;; ============================================================

(defun gascity-action--confirm (format-string &rest args)
  "Ask a yes/no question built from FORMAT-STRING and ARGS."
  (yes-or-no-p (apply #'format format-string args)))

(defun gascity-action--rig-names ()
  "Return the city's rig names for completion, never blocking (§8.5)."
  (gascity-rig-names-for-prompt))

(defun gascity-action--session-names ()
  "Return the city's session aliases (qualified agent names) for completion.
Prefers `agent_name' (always qualified) over the volatile `name'.  From
the store's last `gc session list' payload, refreshed in the
background (`gascity-store-peek'); nil when cold — free entry works."
  (delq nil (mapcar (lambda (s) (or (alist-get 'agent_name s)
                                    (alist-get 'name s)))
                    (append (alist-get 'sessions
                                       (gascity-store-peek '("session" "list")))
                            nil))))

(defun gascity-action--order-names ()
  "Return the city's order names for completion, from the store (§8.5)."
  (delq nil (mapcar (lambda (o) (or (alist-get 'name o)
                                    (alist-get 'scoped_name o)))
                    (append (alist-get 'orders
                                       (gascity-store-peek '("order" "list")))
                            nil))))

(defun gascity-action--agent-at-point-name ()
  "Return the qualified name of the session/agent at point, or nil."
  (let ((agent (gascity-agent-at-point)))
    (and agent (gascity-agent-name agent))))

(defun gascity-action--read-rig (prompt)
  "Read a rig name with PROMPT, defaulting to the contextual rig."
  (completing-read prompt (gascity-action--rig-names) nil nil nil nil
                   (gascity-context-rig-name-cached)))

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
   ((derived-mode-p 'gascity-dashboard-mode) (gascity-dashboard-refresh))
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
(defun gascity-rig-add (path &optional name prefix)
  "Register PATH as a rig (prompted), then refresh.
With a prefix argument, also prompt for NAME and bead PREFIX; otherwise gc
defaults the name to PATH's basename and the prefix from the name."
  (interactive
   (let ((path (read-directory-name "Add rig at path: ")))
     (if current-prefix-arg
         (list path
               (read-string "Rig name (empty = basename): ")
               (read-string "Bead prefix (empty = derived): "))
       (list path nil nil))))
  (gascity-command-execute-interactive
   (gascity-command-rig-add
    :path path
    :name (and (stringp name) (not (string-empty-p name)) name)
    :prefix (and (stringp prefix) (not (string-empty-p prefix)) prefix))))

;;;###autoload
(defun gascity-rig-remove (name)
  "Remove rig NAME from the city configuration (prompted, confirmed), then refresh."
  (interactive (list (gascity-action--read-rig "Remove rig: ")))
  (when (gascity-action--confirm "Remove rig %s from the city config? " name)
    (gascity-command-execute-interactive (gascity-command-rig-remove :name name))))

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
(defun gascity-order-run (name &optional rig)
  "Run order NAME manually (prompted), bypassing its trigger.
With a prefix argument, also prompt for a RIG to disambiguate same-name
orders across rigs (`gc order run --rig', DESIGN-write-actions.md §11 #9)."
  (interactive
   (list (gascity-action--read-order "Run order: ")
         (and current-prefix-arg (gascity-action--read-rig "Disambiguate rig: "))))
  (gascity-command-execute-interactive
   (gascity-command-order-run :name name :rig rig)))

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
   (gascity-command-rig-suspend :name (gascity-action--rig-at-point))))

;;;###autoload
(defun gascity-rig-resume-at-point ()
  "Resume the rig at point and refresh the list."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-rig-resume :name (gascity-action--rig-at-point))))

;;;###autoload
(defun gascity-rig-restart-at-point ()
  "Restart the rig at point (kill its agent sessions) and refresh the list."
  (interactive)
  (let ((name (gascity-action--rig-at-point)))
    (when (gascity-action--confirm "Restart (kill agent sessions of) rig %s? " name)
      (gascity-command-execute-interactive (gascity-command-rig-restart :name name)))))

;;;###autoload
(defun gascity-order-run-at-point ()
  "Run the order at point manually and refresh the list.
Passes the order's own rig as `--rig' so a same-name order in another rig
is never run by mistake (DESIGN-write-actions.md §11 #9)."
  (interactive)
  (let* ((order (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id)))
         (name (gascity-action--order-at-point))
         (rig (and (gascity-order-p order) (gascity-order-rig order))))
    (gascity-command-execute-interactive
     (gascity-command-order-run :name name :rig rig))))

;;;###autoload
(defun gascity-session-nudge-at-point ()
  "Nudge the session/agent at point with a prompted message, then refresh."
  (interactive)
  (let ((target (gascity-action--session-at-point)))
    (gascity-command-execute-interactive
     (gascity-command-session-nudge
      :target target :message (read-string (format "Message to %s: " target))))))

;;;###autoload
(defun gascity-session-suspend-at-point ()
  "Suspend the session/agent at point and refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-session-suspend :target (gascity-action--session-at-point))))

;;;###autoload
(defun gascity-session-kill-at-point ()
  "Force-kill the runtime of the session/agent at point and refresh."
  (interactive)
  (let ((target (gascity-action--session-at-point)))
    (when (gascity-action--confirm "Force-kill the runtime of session %s? " target)
      (gascity-command-execute-interactive (gascity-command-session-kill :target target)))))

;;;###autoload
(defun gascity-session-wake-at-point ()
  "Wake the session/agent at point and refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-session-wake :target (gascity-action--session-at-point))))

;;;###autoload
(defun gascity-session-drain-at-point ()
  "Signal the session/agent at point to drain (wind down gracefully), then refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-runtime-drain :target (gascity-action--session-at-point))))

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
    :id id :text text :directory (gascity-action--bead-store id))))

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

;;; Bead — close / reopen / assign (gc bd close|reopen|assign), store-routed

(defun gascity-action--read-assignee (prompt)
  "Read an assignee with PROMPT — a session alias, completing over live names.
Free entry is allowed so the refinery, `mayor', or a human address can be
typed; the completion table is the city's session aliases for convenience."
  (completing-read prompt (gascity-action--session-names) nil nil nil nil
                   (gascity-action--agent-at-point-name)))

(defconst gascity-action--bead-statuses
  '("open" "in_progress" "blocked" "deferred" "closed" "pinned" "hooked")
  "Built-in bead statuses offered for completion by `gascity-action--read-status'.
Free entry is still allowed for any configured custom status.")

(defconst gascity-action--bead-priorities '("0" "1" "2" "3" "4")
  "Bead priorities (0 = highest) offered for completion.")

(defconst gascity-action--bead-types
  '("task" "bug" "feature" "epic" "chore" "decision")
  "Built-in bead types offered for completion by `gascity-action--read-type'.")

(defun gascity-action--read-status (prompt)
  "Read a bead status with PROMPT, completing over the built-in set (free entry)."
  (completing-read prompt gascity-action--bead-statuses))

(defun gascity-action--read-priority (prompt)
  "Read a bead priority with PROMPT, completing over 0-4 (0 = highest, free entry)."
  (completing-read prompt gascity-action--bead-priorities))

(defun gascity-action--read-type (prompt)
  "Read a bead type with PROMPT, completing over the built-in types (free entry)."
  (completing-read prompt gascity-action--bead-types nil nil nil nil "task"))

(defun gascity-bead-close--run (id reason)
  "Close bead ID with REASON — store-routed by ID's prefix — then refresh.
REASON may be empty, in which case no `-r' is sent."
  (gascity-command-execute-interactive
   (gascity-command-bd-close
    :id id
    :reason (and (stringp reason) (not (string-empty-p reason)) reason)
    :directory (gascity-action--bead-store id))))

;;;###autoload
(defun gascity-bead-close (id reason)
  "Close bead ID with a REASON (both prompted, confirmed).
ID defaults to the bead reference at point."
  (interactive
   (let ((id (gascity-action--read-bead "Close bead: ")))
     (list id (read-string (format "Reason for closing %s: " id)))))
  (when (gascity-action--confirm "Close bead %s? " id)
    (gascity-bead-close--run id reason)))

;;;###autoload
(defun gascity-bead-close-at-point ()
  "Close the bead reference at point with a prompted reason (confirmed)."
  (interactive)
  (let ((id (or (gascity-bead-at-point) (user-error "No bead at point"))))
    (when (gascity-action--confirm "Close bead %s? " id)
      (gascity-bead-close--run
       id (read-string (format "Reason for closing %s: " id))))))

(defun gascity-bead-reopen--run (id)
  "Reopen closed bead ID — store-routed by ID's prefix — then refresh."
  (gascity-command-execute-interactive
   (gascity-command-bd-reopen :id id :directory (gascity-action--bead-store id))))

;;;###autoload
(defun gascity-bead-reopen (id)
  "Reopen closed bead ID (prompted; defaults to the bead reference at point)."
  (interactive (list (gascity-action--read-bead "Reopen bead: ")))
  (gascity-bead-reopen--run id))

;;;###autoload
(defun gascity-bead-reopen-at-point ()
  "Reopen the closed bead reference at point, then refresh."
  (interactive)
  (gascity-bead-reopen--run
   (or (gascity-bead-at-point) (user-error "No bead at point"))))

(defun gascity-bead-assign--run (id name)
  "Assign bead ID to NAME — store-routed by ID's prefix — then refresh."
  (gascity-command-execute-interactive
   (gascity-command-bd-assign
    :id id :name name :directory (gascity-action--bead-store id))))

;;;###autoload
(defun gascity-bead-assign (id name)
  "Assign bead ID to assignee NAME (both prompted).
ID defaults to the bead reference at point; NAME completes over session
aliases but accepts any address (refinery, mayor, human)."
  (interactive
   (let ((id (gascity-action--read-bead "Assign bead: ")))
     (list id (gascity-action--read-assignee (format "Assign %s to: " id)))))
  (gascity-bead-assign--run id name))

;;;###autoload
(defun gascity-bead-assign-at-point ()
  "Assign the bead reference at point to a prompted assignee, then refresh."
  (interactive)
  (let ((id (or (gascity-bead-at-point) (user-error "No bead at point"))))
    (gascity-bead-assign--run
     id (gascity-action--read-assignee (format "Assign %s to: " id)))))

;;; Bead — update (status / priority / description), deps, create (phase 3)
;;
;; `gc bd update' is the general bead-mutation verb; the focused
;; set-status / set-priority commands set one field each, and the
;; description edit drives it from the compose buffer.  Deps use `gc bd
;; dep add/remove'; create is quick-capture (`gc bd create', json-on ->
;; summarised id, then hand off to beads.el).  Every verb is store-routed
;; by `-C' (existing beads resolve it from the id prefix; create resolves
;; it from the contextual rig).

(defun gascity-bead-update--run (id &rest props)
  "Run `gc bd update ID' with PROPS — store-routed by ID's prefix — then refresh.
PROPS is a plist of `:status'/`:priority'/`:assignee'/`:description' values;
nil entries are dropped by the command line so only supplied fields change."
  (gascity-command-execute-interactive
   (apply #'gascity-command-bd-update
          :id id :directory (gascity-action--bead-store id) props)))

;;;###autoload
(defun gascity-bead-set-status (id status)
  "Set bead ID's STATUS (both prompted; ID defaults to the bead at point)."
  (interactive
   (let ((id (gascity-action--read-bead "Set status of bead: ")))
     (list id (gascity-action--read-status (format "Status of %s: " id)))))
  (gascity-bead-update--run id :status status))

;;;###autoload
(defun gascity-bead-set-status-at-point ()
  "Set the status of the bead reference at point (prompted), then refresh."
  (interactive)
  (let ((id (or (gascity-bead-at-point) (user-error "No bead at point"))))
    (gascity-bead-update--run
     id :status (gascity-action--read-status (format "Status of %s: " id)))))

;;;###autoload
(defun gascity-bead-set-priority (id priority)
  "Set bead ID's PRIORITY (both prompted; ID defaults to the bead at point)."
  (interactive
   (let ((id (gascity-action--read-bead "Set priority of bead: ")))
     (list id (gascity-action--read-priority (format "Priority of %s: " id)))))
  (gascity-bead-update--run id :priority priority))

;;;###autoload
(defun gascity-bead-set-priority-at-point ()
  "Set the priority of the bead reference at point (prompted), then refresh."
  (interactive)
  (let ((id (or (gascity-bead-at-point) (user-error "No bead at point"))))
    (gascity-bead-update--run
     id :priority (gascity-action--read-priority (format "Priority of %s: " id)))))

;;;###autoload
(defun gascity-bead-describe-at-point ()
  "Edit the description of the bead at point in a compose buffer.
\\<gascity-compose-mode-map>\\[gascity-compose-finish] replaces the bead's
description with the buffer body via `gc bd update --description';
\\[gascity-compose-abort] aborts.  The longer-body counterpart to the
focused field edits \(DESIGN-write-actions.md §6)."
  (interactive)
  (let* ((id (or (gascity-bead-at-point) (user-error "No bead at point")))
         (dir (gascity-action--bead-store id))
         (origin (current-buffer)))
    (gascity-compose
     :buffer-name (format "*gc-bead %s description*" id)
     :header (list (cons "Bead" id) (cons "Field" "description"))
     :origin origin
     :finish (lambda (body)
               (gascity-command-act-async
                (gascity-command-bd-update
                 :id id :description body :directory dir)
                :origin origin)))))

;;;###autoload
(defun gascity-bead-note-compose-at-point ()
  "Append a multi-line note to the bead at point via a compose buffer.
\\<gascity-compose-mode-map>\\[gascity-compose-finish] appends the buffer
body with `gc bd note'; \\[gascity-compose-abort] aborts.  The one-line
`gascity-bead-note-at-point' stays the quick minibuffer path."
  (interactive)
  (let* ((id (or (gascity-bead-at-point) (user-error "No bead at point")))
         (dir (gascity-action--bead-store id))
         (origin (current-buffer)))
    (gascity-compose
     :buffer-name (format "*gc-bead %s note*" id)
     :header (list (cons "Bead" id) (cons "Field" "note (append)"))
     :origin origin
     :finish (lambda (body)
               (gascity-command-act-async
                (gascity-command-bd-note
                 :id id :text body :directory dir)
                :origin origin)))))

(defun gascity-bead-dep-add--run (id dependency)
  "Add a dependency — ID depends on DEPENDENCY — store-routed, then refresh."
  (gascity-command-execute-interactive
   (gascity-command-bd-dep-add
    :id id :dependency dependency :directory (gascity-action--bead-store id))))

;;;###autoload
(defun gascity-bead-dep-add (id dependency)
  "Make bead ID depend on DEPENDENCY (both prompted).
ID defaults to the bead reference at point."
  (interactive
   (let ((id (gascity-action--read-bead "Add dependency to bead: ")))
     (list id (read-string (format "%s depends on: " id)))))
  (gascity-bead-dep-add--run id dependency))

;;;###autoload
(defun gascity-bead-dep-add-at-point ()
  "Add a dependency to the bead at point (prompted for the depended-on id)."
  (interactive)
  (let ((id (or (gascity-bead-at-point) (user-error "No bead at point"))))
    (gascity-bead-dep-add--run id (read-string (format "%s depends on: " id)))))

(defun gascity-bead-dep-remove--run (id dependency)
  "Remove ID's dependency on DEPENDENCY — store-routed, then refresh."
  (gascity-command-execute-interactive
   (gascity-command-bd-dep-remove
    :id id :dependency dependency :directory (gascity-action--bead-store id))))

;;;###autoload
(defun gascity-bead-dep-remove (id dependency)
  "Remove bead ID's dependency on DEPENDENCY (both prompted).
ID defaults to the bead reference at point."
  (interactive
   (let ((id (gascity-action--read-bead "Remove dependency from bead: ")))
     (list id (read-string (format "%s no longer depends on: " id)))))
  (gascity-bead-dep-remove--run id dependency))

;;;###autoload
(defun gascity-bead-dep-remove-at-point ()
  "Remove a dependency from the bead at point (prompted)."
  (interactive)
  (let ((id (or (gascity-bead-at-point) (user-error "No bead at point"))))
    (gascity-bead-dep-remove--run
     id (read-string (format "%s no longer depends on: " id)))))

(defun gascity-bead-create--read-store ()
  "Prompt for a quick-capture bead's destination store.
Completes over \"city\" plus the city's rig names; the default is the
contextual answer — the rig at point, else \"city\" when a city root
resolves.  Returns the chosen rig name, \"city\", or nil when no
destination resolves (the create then runs against the ambient
directory, as before).  The prompt names the default, so the destination
is never a mystery."
  (let* ((rig (gascity-context-rig-name))
         (city (and (gascity-context-city-root) "city"))
         (choices (append (when city (list city))
                          (mapcar #'gascity-rig-name
                                  (ignore-errors (gascity-rigs)))))
         (default (or rig city)))
    (when choices
      (completing-read
       (format "Create in store (default %s): " (or default (car choices)))
       choices nil t nil nil default))))

;;;###autoload
(defun gascity-bead-create (title type priority assignee &optional store)
  "Quick-capture a new bead: TITLE/TYPE/PRIORITY/ASSIGNEE (all prompted).
The destination store is prompted first (STORE, a rig name or \"city\",
skips the prompt): a rig at point creates in that rig's store — the
historic behavior — while a city context with no rig creates in the
CITY root's own store, where gc routes prefix-less city beads; neither
resolvable means the ambient directory.  On success the new id and its
destination are echoed for hand-off to beads.el for deeper authoring
\(DESIGN.md §4.3).  An empty ASSIGNEE leaves the bead unassigned."
  (interactive
   (let ((store (gascity-bead-create--read-store)))
     (list (read-string "New bead title: ")
           (gascity-action--read-type "Type: ")
           (gascity-action--read-priority "Priority: ")
           (gascity-action--read-assignee "Assignee (empty for none): ")
           store)))
  (let* ((dir (gascity-beads--create-store store))
         ;; The label mirrors the resolution: an explicit choice, else the
         ;; contextual rig, else the city, else the ambient directory.
         (label (cond ((and (stringp store) (not (string-empty-p store)))
                       store)
                      (dir (or (gascity-context-rig-name) "city"))
                      (t "ambient"))))
    (gascity-command-act-async
     (gascity-command-bd-create
      :title title
      :type (and (stringp type) (not (string-empty-p type)) type)
      :priority (and (stringp priority) (not (string-empty-p priority)) priority)
      :assignee (and (stringp assignee) (not (string-empty-p assignee)) assignee)
      ;; gc runs on the store's host (the city-pinned buffer's
      ;; `default-directory'), so `-C' must be host-local.
      :directory (and dir (file-local-name dir)))
     :target title
     :on-success (lambda (result)
                   (message "gc bd create: %s in %s store"
                            (gascity-action--summarize result) label)))))

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
      (gascity-command-execute-interactive (gascity-command-session-reset :target target)))))

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
   (gascity-command-runtime-undrain :target (gascity-action--session-at-point))))

;;; Session — rename / close / pin / unpin / prune (phase 3 lifecycle)
;;
;; Prompted commands (with at-point defaults via `--read-session'),
;; mirroring the shipped session verbs; close and the city-wide prune
;; confirm first.  Reached from `gascity-session-dispatch'.

;;;###autoload
(defun gascity-session-rename (target title)
  "Rename session TARGET to TITLE (both prompted), then refresh."
  (interactive
   (let ((target (gascity-action--read-session "Rename session: ")))
     (list target (read-string (format "New title for %s: " target)))))
  (gascity-command-execute-interactive
   (gascity-command-session-rename :target target :title title)))

;;;###autoload
(defun gascity-session-close (target)
  "Close session TARGET permanently (prompted, confirmed), then refresh."
  (interactive (list (gascity-action--read-session "Close session: ")))
  (when (gascity-action--confirm "Close session %s permanently? " target)
    (gascity-command-execute-interactive (gascity-command-session-close :target target))))

;;;###autoload
(defun gascity-session-pin (target)
  "Pin session TARGET awake (prompted), then refresh."
  (interactive (list (gascity-action--read-session "Pin session: ")))
  (gascity-command-execute-interactive (gascity-command-session-pin :target target)))

;;;###autoload
(defun gascity-session-unpin (target)
  "Remove the awake pin on session TARGET (prompted), then refresh."
  (interactive (list (gascity-action--read-session "Unpin session: ")))
  (gascity-command-execute-interactive (gascity-command-session-unpin :target target)))

;;;###autoload
(defun gascity-session-prune (before state)
  "Close dormant sessions older than BEFORE in STATE (prompted, confirmed).
BEFORE is a duration (e.g. 7d, 24h); STATE is a comma-separated state list
\(suspended, asleep, drained).  Empty answers defer to gc's defaults (7d,
suspended).  City-wide, so confirm first."
  (interactive
   (list (read-string "Prune sessions older than (empty = gc default 7d): ")
         (read-string "States to prune (empty = gc default suspended): ")))
  (let ((before (and (stringp before) (not (string-empty-p before)) before))
        (state (and (stringp state) (not (string-empty-p state)) state)))
    (when (gascity-action--confirm
           "Prune dormant sessions%s%s? "
           (if before (format " older than %s" before) "")
           (if state (format " in state %s" state) ""))
      (gascity-command-execute-interactive
       (gascity-command-session-prune :before before :state state)))))

;;; City — reload config (gc reload)

;;;###autoload
(defun gascity-reload (&optional soft)
  "Re-read the city config and process one reload tick (`gc reload').
With a prefix arg SOFT, pass `--soft' — absorb config drift on open
sessions instead of draining them.  City-level (gc has no `rig reload')."
  (interactive "P")
  (gascity-command-execute-interactive (gascity-command-reload :soft (and soft t))))

;;; Mail — read / archive / mark-read / mark-unread (at point in the inbox)

(defun gascity-mail--id-at-point ()
  "Return the message id of the mail at point, or signal a `user-error'."
  (let* ((message (gascity-mail-at-point))
         (id (and message (gascity-mail-id message))))
    (if (and id (stringp id) (not (string-empty-p id)))
        id
      (user-error "No message at point"))))

(defun gascity-action--fill-text (buf text empty)
  "Replace read-only view BUF's text with TEXT, or EMPTY when TEXT is blank.
TEXT `:pending' shows the `…' placeholder of a call still in flight
\(dashboard-v3 §8.5: the view opens at once and fills in).  A killed
BUF is left alone — the late answer of an async call must not
resurrect it.  Returns BUF."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (cond ((eq text :pending) "…")
                      ((and (stringp text) (not (string-empty-p (string-trim text))))
                       text)
                      (t empty)))
        (goto-char (point-min)))
      (unless view-mode (view-mode 1))))
  buf)

(defun gascity-action--async-text-view (buffer-name command empty &optional origin)
  "Pop view buffer BUFFER-NAME at once and fill it with COMMAND's output.
The buffer (keyed and pinned by `gascity-view-get-buffer-create') shows
`…' until the async call answers; then its stdout, or EMPTY when blank.
A failure replaces the placeholder with the failure line (also echoed
and logged by the store).  COMMAND is a read-only verb (peek, mail
read, a sling dry run), so the store's caches are not invalidated
unless the verb itself mutates (mail read marks the message read);
ORIGIN, when non-nil, is the view refreshed after such a mutation."
  (let ((buf (gascity-view-get-buffer-create buffer-name)))
    (gascity-action--fill-text buf :pending empty)
    (pop-to-buffer buf)
    (with-current-buffer buf
      (gascity-command-act-async
       command
       ;; A view read, not a mutation of the target: it must not mark
       ;; the target's row pending, nor queue behind its actions.
       :target (list 'view buffer-name)
       :origin origin
       :invalidate (gascity-command-mail-read-p command)
       :on-success (lambda (text) (gascity-action--fill-text buf text empty))
       :on-error (lambda (msg)
                   (message "%s" msg)
                   (gascity-action--fill-text buf msg empty))))
    buf))

(defun gascity-mail--show-body (id text)
  "Pop a read-only view buffer showing body TEXT of message ID.
The buffer is keyed and pinned to the inbox's city
\(`gascity-view-get-buffer-create'), so a remote city's message body
carries that host's `default-directory'."
  (let ((buf (gascity-view-get-buffer-create (format "*gc-mail: %s*" id))))
    (gascity-action--fill-text buf text "(no message body)")
    (pop-to-buffer buf)))

;;;###autoload
(defun gascity-mail-read-at-point ()
  "Read the message at point and mark it read, show its body, then refresh.
`RET' shows the cached fields without contacting gc; this `r' action runs
`gc mail read', which also marks the message read, so the default
unread-filtered inbox drops it on refresh.  The body buffer opens at
once with `…' and fills in when gc answers (D9)."
  (interactive)
  (let ((id (gascity-mail--id-at-point)))
    (gascity-action--async-text-view
     (format "*gc-mail: %s*" id)
     (gascity-command-mail-read :id id)
     "(no message body)"
     ;; Marking read changes the inbox: refresh it once gc has answered.
     (current-buffer))))

;;;###autoload
(defun gascity-mail-archive-at-point ()
  "Archive the message at point (confirmed) and refresh."
  (interactive)
  (let ((id (gascity-mail--id-at-point)))
    (when (gascity-action--confirm "Archive message %s? " id)
      (gascity-command-execute-interactive (gascity-command-mail-archive :id id)))))

;;;###autoload
(defun gascity-mail-mark-read-at-point ()
  "Mark the message at point read without opening it, then refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-mail-mark-read :id (gascity-mail--id-at-point))))

;;;###autoload
(defun gascity-mail-mark-unread-at-point ()
  "Mark the message at point unread and refresh."
  (interactive)
  (gascity-command-execute-interactive
   (gascity-command-mail-mark-unread :id (gascity-mail--id-at-point))))

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
Pops a read-only view buffer at once — `…' until the async capture
answers (dashboard-v3 §8.5) — then the captured text.  An invalid
command is a `user-error'; a gc failure replaces the placeholder."
  (gascity-action--async-text-view
   (gascity-session-peek--buffer-name target)
   (gascity-command-session-peek
    :target target :lines (number-to-string lines))
   "(no output captured)"))

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
;;; Sling — the one unified transient-backed command
;;; ============================================================
;;
;; Sling is the lone flag-heavy verb, so it gets one transient
;; (`gascity-sling-dispatch', DESIGN-write-actions §10): sections stack
;; vertically — header, Formula, Destination, Routing flags, Actions,
;; then the picked formula's full-width Variables section.  `-f' picks a
;; formula in place (the same prefix re-setups with the new scope); `-T'
;; sets a visible target session; `A' edits the sling arg (bead id or
;; task text) in place; `s'/`p' sling or preview.  With a
;; formula picked the formula path runs (validated vars, shape via
;; `gascity-formula--needs-convoy', routing flags ignored — they are
;; consumed only by the plain path); without one the plain flag path
;; runs as before.  The generated variable keys avoid the single-letter
;; static bindings collected in `gascity-sling--reserved-keys'.

(defun gascity-sling--parse-transient-args (args)
  "Parse flat transient ARGS into a `gascity-command-sling' initarg plist.
ARGS is the list `transient-args' returns — switch strings (\"--formula\")
and `option=value' strings (\"--merge=direct\").  This is the PLAIN path's
parser: its routing flags only.  It matches the equals form
\"--var=\" which no infix currently emits — the formula Variables
infixes set the space form and their values flow through
`gascity-sling-formula--current-values' instead (F-1: the two formats
are deliberately not unified; the plain path never receives var
args).  Unknown entries are ignored."
  (let (plist vars)
    (dolist (a args)
      (cond
       ((equal a "--formula")   (setq plist (plist-put plist :formula t)))
       ((string-prefix-p "--on=" a)
        (setq plist (plist-put plist :on (substring a (length "--on=")))))
       ((equal a "--nudge")     (setq plist (plist-put plist :nudge t)))
       ((equal a "--no-convoy") (setq plist (plist-put plist :no-convoy t)))
       ((equal a "--reassign")  (setq plist (plist-put plist :reassign t)))
       ((equal a "--dry-run")   (setq plist (plist-put plist :dry-run t)))
       ((string-prefix-p "--merge=" a)
        (setq plist (plist-put plist :merge (substring a (length "--merge=")))))
       ((string-prefix-p "--title=" a)
        (setq plist (plist-put plist :title (substring a (length "--title=")))))
       ((string-prefix-p "--var=" a)
        (push (substring a (length "--var=")) vars))))
    (when vars (setq plist (plist-put plist :var (nreverse vars))))
    plist))

(defun gascity-sling--city-dir (&optional scope)
  "Return the city directory the sling transient was entered from.
The prefix seeds the scope's `:city' with the `default-directory' of
the buffer it was invoked from — a view buffer that
`gascity-view-get-buffer-create' pinned to its city — and every
re-setup carries the scope (and the pin) along.  With SCOPE nil the
live transient scope is read; menu setup passes the scope explicitly
so it never needs live transient state.  Falls back to the current
buffer's `default-directory' when the scope carries no `:city' (tests,
or a prefix invoked outside a pinned view — same behavior as before
the pin existed).

Suffixes must run their gc-touching reads and completions inside
`(let ((default-directory (gascity-sling--city-dir))) …)': transient
can execute a suffix with a foreign `current-buffer' (the menu buffer,
or the reused minibuffer a `completing-read' inherits), and the formula
catalog/recipe caches key off `gascity-context-scope-key' of whatever
directory is current at call time — an unpinned read both queries
another city and memoizes its catalog under the wrong (possibly
empty) scope key (ga-4ia4, bright-lights dogfood §5)."
  (or (plist-get (or scope (transient-scope)) :city)
      default-directory))

(defun gascity-sling--show-plan (command)
  "Run COMMAND (a `--dry-run' sling) and show gc's routing plan.
Pops a read-only view buffer at once with `…', filled with gc's
captured stdout when the async dry run answers (D9); an invalid
command is a clean `user-error'."
  (gascity-action--async-text-view "*gc-sling: dry-run*" command
                                   "(no plan output)"))

(defun gascity-sling--run (args preview)
  "Build and run a sling from transient ARGS (its flag list).
With a formula picked in the scope, the formula path runs: the
collected var values are validated client-side and the sling shape
`gascity-formula--needs-convoy' detects is chosen; the routing flags
are ignored there — they are consumed only by the plain path (F-5).
Otherwise the plain path runs unchanged: prompt bead/text (seeded from
the bead at point) then target, parse the flags and act or preview.
A target set through `-T' wins; with none set, the formula path reads
it once via `gascity-action--read-session' (REQ-B's dispatch
fallback).  With PREVIEW non-nil, force `--dry-run' and show gc's
routing plan instead of executing."
  (let ((default-directory (gascity-sling--city-dir)))
    (let* ((scope (transient-scope))
           (formula (plist-get scope :formula)))
      (if formula
          (gascity-sling-formula--dispatch
           (gascity-formula-recipe-cached formula)
           (or (plist-get scope :target)
               (gascity-action--read-session "Sling to target: "))
           (plist-get scope :arg)
           (gascity-sling-formula--current-values)
           preview)
        (let* ((plist (gascity-sling--parse-transient-args args))
               (arg (read-string "Bead id or task text: " (gascity-bead-at-point)))
               (target (gascity-action--read-session "Sling to target: "))
               (command (apply #'gascity-command-sling
                               :target target :arg arg
                               (append (when preview (list :dry-run t))
                                       plist))))
          (if preview
              (gascity-sling--show-plan command)
            ;; `gc sling --json': the dispatch result is summarized
            ;; from the payload when the async call answers (D9).
            (oset command json t)
            (gascity-command-act-async command)))))))

(transient-define-suffix gascity-sling-dispatch-run (args)
  "Sling for real using the dispatch flags ARGS."
  (interactive (list (transient-args 'gascity-sling-dispatch)))
  (gascity-sling--run args nil))

(transient-define-suffix gascity-sling-dispatch-preview (args)
  "Preview the sling (gc `--dry-run' routing plan) for the dispatch ARGS."
  (interactive (list (transient-args 'gascity-sling-dispatch)))
  (gascity-sling--run args t))

(defconst gascity-sling--reserved-keys
  '("f" "g" "T" "A" "c" "a" "n" "m" "t" "s" "p" "r" "q")
  "Every single letter statically bound in `gascity-sling-dispatch':
the Formula group (`-f' pick, `g' refresh), the Destination `-T' and
`A' (arg edit), the routing flags `-c -a -n -m -t' and the Actions
\(`s', `p', `r', `q').
The generated variable infix keys avoid exactly this list; it lives
beside the layout it keys so a re-binding cannot silently collide
\(OQ-2), and a test asserts the two stay in sync.")

(defun gascity-sling--scope-info (scope)
  "Return the raw info spec describing SCOPE — the menu's header line.
The `(:info …)' suffix form is passed unwrapped; nesting it as
`((:info …))' parses as an argument spec and crashes setup (founded in
the tmux-Emacs TRAMP e2e pass).  A leading `(:info …)' as the FIRST
element of its group vector also breaks setup — it parses as a group
argument — so the group title carries the city name and this spec
carries the scope.  With no formula picked the header hints at `-f'
\(OQ-3)."
  (list :info
        (format "Arg: %s · Formula: %s · Target: %s"
                (or (plist-get scope :arg)
                    "(none — point at a bead or convoy)")
                (or (plist-get scope :formula) "(none — -f to pick)")
                (or (plist-get scope :target) "(none)"))))

(defun gascity-sling--children-specs (scope)
  "Return the raw stacked layout specs for SCOPE (REQ-C).
The sections are sibling groups — no `transient-columns' anywhere, so
each renders full width and stacks vertically: the header info line,
Formula, Destination, Routing flags, Actions, then the picked
formula's Variables section last (absent until a formula with vars is
picked, REQ-A/REQ-B).  The generated infix keys avoid
`gascity-sling--reserved-keys' (REQ-D).  The recipe read and the
header's city name run pinned to the scope's `:city'
\(`gascity-sling--city-dir'): transient can run setup with the menu
buffer current, whose directory must not key the recipe cache nor name
the header (ga-4ia4)."
  (let* ((default-directory (gascity-sling--city-dir scope))
         (recipe (and (plist-get scope :formula)
                      (gascity-formula-recipe-cached
                       (plist-get scope :formula)))))
    (append
     (list
      (vector (format "Sling — %s" (gascity-context-city-name))
              (gascity-sling--scope-info scope))
      (vector "Formula"
              '("-f" "Pick formula…" gascity-sling-dispatch-pick)
              '("g" "Refresh catalog" gascity-sling-dispatch-refresh))
      (vector "Destination"
              '("-T" "Target session…" gascity-sling-dispatch-target)
              '("A" "Edit arg (bead/text)…" gascity-sling-dispatch-arg))
      (vector "Routing flags"
              '("-c" "Skip auto-convoy" "--no-convoy")
              '("-a" "Reassign (clear human assignee)" "--reassign")
              '("-n" "Nudge target after routing" "--nudge")
              '("-m" "Merge strategy" "--merge=" :choices ("direct" "mr" "local"))
              '("-t" "Wisp root title" "--title="))
      (vector "Actions"
              '("s" "Sling…" gascity-sling-dispatch-run)
              '("p" "Preview (dry-run)…" gascity-sling-dispatch-preview)
              '("r" "Preview recipe…" gascity-sling-dispatch-recipe)
              '("q" "Quit" transient-quit-one)))
     (when-let* ((group (gascity-sling-formula--var-children
                         recipe gascity-sling--reserved-keys)))
       (list group)))))

(defun gascity-sling--setup-children (_children)
  "Parse `gascity-sling--children-specs' for the live scope."
  (transient-parse-suffixes
   'gascity-sling-dispatch
   (gascity-sling--children-specs (transient-scope))))

(transient-define-suffix gascity-sling-dispatch-pick ()
  "Pick a formula from the cached catalog; rebuild this menu in place.
One transient, one `-f' press (REQ-A): the same prefix re-setups with
the picked formula in the scope and the current infix values carried
over, so a variable the previous and new formulas share keeps its
value (vars absent from the new formula drop with their infixes).
The catalog read and its `completing-read' run pinned to the city
directory the transient was entered from (`gascity-sling--city-dir'):
the catalog cache keys off `gascity-context-scope-key' of whatever
directory is current at call time, and the reused minibuffer inherits
its `default-directory' from the buffer current at entry, so an
unpinned read serves another city's catalog and memoizes it under the
wrong scope key (ga-4ia4, bright-lights dogfood §5)."
  (interactive)
  (let ((default-directory (gascity-sling--city-dir)))
    (let ((name (gascity-sling-formula--read-formula)))
      (transient-setup 'gascity-sling-dispatch nil nil
                       :scope (plist-put (copy-sequence (transient-scope))
                                         :formula name)
                       :value (transient-args 'gascity-sling-dispatch)))))

(transient-define-suffix gascity-sling-dispatch-refresh ()
  "Re-read this city's formulas in the background, then rebuild the menu.
`gascity-formula-refresh-async' re-reads the catalog and the picked
formula's recipe without blocking (dashboard-v3 D9, §8.5) — a formula
edited mid-session is no longer served stale — and swaps each cache
entry as it arrives.  The reads are pinned to the city the transient
was entered from (`gascity-sling--city-dir').  When they have answered
and the menu is still open, it is set up again with its scope and the
infix values carried over, like a re-pick.  The menu stays open
meanwhile."
  :transient t
  (interactive)
  (let ((default-directory (gascity-sling--city-dir)))
    (message "Refreshing formulas…")
    (gascity-formula-refresh-async
     (plist-get (transient-scope) :formula)
     (lambda ()
       ;; A process callback: rebuild from a timer, and only while the
       ;; menu is still the active transient.
       (run-at-time
        0 nil
        (lambda ()
          (when-let* ((prefix (transient-active-prefix 'gascity-sling-dispatch)))
            (condition-case nil
                (transient-setup 'gascity-sling-dispatch nil nil
                                 :scope (oref prefix scope)
                                 :value (transient-args 'gascity-sling-dispatch))
              (error nil)))
          (message "Formulas refreshed")))))))

(transient-define-suffix gascity-sling-dispatch-arg ()
  "Read the bead id / task text; show it in the header.
The sling arg is seeded once at entry from the bead or convoy at
point and is often nil (empty area under point) — this suffix sets it
in place, so a formula dispatch can use the edited arg without
quitting and re-invoking on the right row.  The set arg lives in the
scope, so it also survives a formula re-pick; set var values carry
across the re-setup like re-pick/refresh.  The plain path keeps its
own read-string fallback — this is purely scope editing, not
dispatch."
  :transient t
  (interactive)
  (let ((arg (read-string "Bead id or task text: "
                          (plist-get (transient-scope) :arg))))
    (transient-setup 'gascity-sling-dispatch nil nil
                     :scope (plist-put (copy-sequence (transient-scope))
                                       :arg arg)
                     :value (transient-args 'gascity-sling-dispatch))))

(transient-define-suffix gascity-sling-dispatch-target ()
  "Read the sling target with session completion; the header shows it.
The read is synchronous but strictly user-initiated — it runs only on
this binding press (OQ-1, F-4), never during setup or redisplay.  The
set target wins at dispatch; an unset one is read once there."
  :transient t
  (interactive)
  (let ((default-directory (gascity-sling--city-dir)))
    (let ((target (gascity-action--read-session "Sling to target: ")))
      (transient-setup 'gascity-sling-dispatch nil nil
                       :scope (plist-put (copy-sequence (transient-scope))
                                         :target target)
                       :value (transient-args 'gascity-sling-dispatch)))))

(transient-define-suffix gascity-sling-dispatch-recipe ()
  "Preview the picked formula's recipe with the current var values.
Re-runs `gc formula show' with the currently-set values so gc
substitutes server-side — never a client-side `{{var}}' substitution.
The menu stays open."
  :transient t
  (interactive)
  (let ((name (plist-get (transient-scope) :formula)))
    (unless name
      (user-error "No formula chosen — pick one first (-f)"))
    (let ((default-directory (gascity-sling--city-dir)))
      (gascity-sling-formula--show-recipe
       name (gascity-sling-formula--current-values)))))

;;;###autoload (autoload 'gascity-sling-dispatch "gascity-action" nil t)
(beads-define-prefix gascity-sling-dispatch ()
  "Sling a bead/text or a formula, in one menu (DESIGN-write-actions §10).
The scope plist `(formula target arg)' is seeded at entry: arg from
the bead or convoy at point, target nil — never prompted up front
\(set it with `-T', or edit the arg in place with `A'; REQ-B) — and
formula nil (`-f' picks in place and
re-renders this menu with a full-width Variables section, REQ-A).
`s'/`p' dispatch: with a formula picked the formula path runs
\(validated vars, shape via `gascity-formula--needs-convoy', routing
flags ignored); without one the plain flag path runs as before
\(REQ-G).
The scope also pins the `default-directory' of the view buffer the
transient was entered from (`:city', read back by
`gascity-sling--city-dir'): suffix commands, the minibuffers their
reads open, and the menu's own setup can all run with a foreign
current-buffer directory, and the formula caches key off
`gascity-context-scope-key' of that directory — the pin keeps every
catalog/recipe read and dispatch on the entered-from city
\(ga-4ia4, bright-lights dogfood §5)."
  [ :class transient-subgroups :setup-children gascity-sling--setup-children ]
  (interactive)
  (transient-setup 'gascity-sling-dispatch nil nil
                   :scope (list :city default-directory
                                :formula nil :target nil
                                :arg (gascity-sling-formula--bead-or-convoy-at-point))))

;;; ============================================================
;;; Mail — send / reply via the compose buffer (gascity-compose §6)
;;; ============================================================

(defun gascity-mail--reply-subject (subject)
  "Return a default reply subject for SUBJECT (prefix \"RE: \" once)."
  (let ((s (or subject "")))
    (if (string-match-p "\\`[Rr][Ee]: " s) s (concat "RE: " s))))

;;;###autoload
(defun gascity-mail-send (to subject)
  "Compose and send a new message to TO with SUBJECT (both prompted).
Opens a `gascity-compose' buffer for the body; in it,
\\<gascity-compose-mode-map>\\[gascity-compose-finish] sends and
\\[gascity-compose-abort] aborts.  TO completes over session aliases but
accepts any address."
  (interactive
   (let ((to (gascity-action--read-assignee "Send mail to: ")))
     (list to (read-string (format "Subject (to %s): " to)))))
  (let ((origin (current-buffer)))
    (gascity-compose
     :buffer-name (format "*gc-mail to %s*" to)
     :header (list (cons "To" to) (cons "Subject" subject))
     :origin origin
     :finish (lambda (body)
               (gascity-command-act-async
                (gascity-command-mail-send
                 :to to :subject subject :message body)
                :target to :origin origin)))))

;;;###autoload
(defun gascity-mail-reply-at-point ()
  "Reply to the message at point — compose the body, then send to its sender.
The subject defaults to the original prefixed with \"RE: \"."
  (interactive)
  (let* ((message (or (gascity-mail-at-point) (user-error "No message at point")))
         (id (gascity-mail-id message))
         (subject (read-string
                   "Reply subject: "
                   (gascity-mail--reply-subject (gascity-mail-subject message))))
         (origin (current-buffer)))
    (gascity-compose
     :buffer-name (format "*gc-mail reply %s*" id)
     :header (list (cons "To" (or (gascity-mail-from message) "(sender)"))
                   (cons "Subject" subject))
     :origin origin
     :finish (lambda (body)
               (gascity-command-act-async
                (gascity-command-mail-reply
                 :id id :subject subject :message body)
                :origin origin)))))

;;; ============================================================
;;; Sub-transients — hand-built command-dispatch backends
;;; ============================================================

(beads-define-prefix gascity-rig-dispatch ()
  "Dispatch rig-control actions (a hand-built command backend)."
  ["Rig control"
   ("s" "Suspend rig…" gascity-rig-suspend)
   ("r" "Resume rig…" gascity-rig-resume)
   ("R" "Restart rig…" gascity-rig-restart)
   ("a" "Add rig…" gascity-rig-add)
   ("x" "Remove rig…" gascity-rig-remove)])

(beads-define-prefix gascity-session-dispatch ()
  "Dispatch session-control actions (a hand-built command backend)."
  ["Session control"
   ("n" "Nudge…" gascity-session-nudge)
   ("s" "Suspend…" gascity-session-suspend)
   ("k" "Kill runtime…" gascity-session-kill)
   ("w" "Wake…" gascity-session-wake)
   ("D" "Drain…" gascity-session-drain)
   ("R" "Reset (fresh restart)…" gascity-session-reset)
   ("U" "Undrain…" gascity-session-undrain)
   ("v" "Peek output…" gascity-session-peek)]
  ["Lifecycle"
   ("m" "Rename…" gascity-session-rename)
   ("c" "Close…" gascity-session-close)
   ("p" "Pin awake…" gascity-session-pin)
   ("P" "Unpin…" gascity-session-unpin)
   ("x" "Prune dormant…" gascity-session-prune)])

(beads-define-prefix gascity-lifecycle-dispatch ()
  "Dispatch city-lifecycle actions (a hand-built command backend)."
  ["City lifecycle"
   ("S" "Start city" gascity-start)
   ("K" "Stop city" gascity-stop)])

;;;###autoload (autoload 'gascity-bead-dispatch "gascity-action" nil t)
(beads-define-prefix gascity-bead-dispatch ()
  "Dispatch bead actions on the reference at point (hand-built backend).
The verbs resolve their subject with `gascity-bead-at-point'; each `gc bd'
write is store-routed by the bead id's prefix.  `RET'/`b' still open the
bead in beads.el; this menu is targeted command dispatch (DESIGN §4)."
  ["Bead"
   ("s" "Sling / route…" gascity-sling-dispatch)
   ("c" "Close…" gascity-bead-close-at-point)
   ("o" "Note…" gascity-bead-note-at-point)
   ("O" "Note (compose)…" gascity-bead-note-compose-at-point)
   ("e" "Describe (compose)…" gascity-bead-describe-at-point)
   ("u" "Set status…" gascity-bead-set-status-at-point)
   ("p" "Set priority…" gascity-bead-set-priority-at-point)
   ("a" "Assign…" gascity-bead-assign-at-point)
   ("r" "Reopen" gascity-bead-reopen-at-point)
   ("d" "Add dependency…" gascity-bead-dep-add-at-point)
   ("D" "Remove dependency…" gascity-bead-dep-remove-at-point)
   ("n" "Create…" gascity-bead-create)
   ("v" "Visit (beads.el)" gascity-bead-visit)])

;;;###autoload (autoload 'gascity-mail-dispatch "gascity-action" nil t)
(beads-define-prefix gascity-mail-dispatch ()
  "Dispatch mail actions in the inbox (a hand-built command backend).
`read'/`archive'/`reply' act on the message at point; `send' composes a
fresh message to a prompted recipient."
  ["Mail"
   ("r" "Read…" gascity-mail-read-at-point)
   ("R" "Reply…" gascity-mail-reply-at-point)
   ("s" "Send…" gascity-mail-send)
   ("a" "Archive…" gascity-mail-archive-at-point)
   ("u" "Mark unread" gascity-mail-mark-unread-at-point)])

(provide 'gascity-action)
;;; gascity-action.el ends here
