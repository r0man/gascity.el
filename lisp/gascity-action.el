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
(require 'gascity-timer)
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
(declare-function gascity-dashboard--rig-of "gascity-dashboard" (qname))
(declare-function gascity-rig-dashboard-refresh "gascity-rig")
(declare-function gascity-polecat-detail-refresh "gascity-session")

;; The formula sling's machinery lives in gascity-formula, which loads
;; before this module; the unified sling prefix drives it from here
;; (cross-file verb wiring — a missing declaration is only caught by the
;; `--warnings-as-errors' compile gate).
(declare-function gascity-sling-formula--bead-or-convoy-at-point "gascity-formula")
(declare-function gascity-sling--header-sentence "gascity-formula")
(declare-function gascity-sling-formula--read-formula "gascity-formula")
(declare-function gascity-sling-formula--current-values "gascity-formula")
(declare-function gascity-sling-formula--dispatch "gascity-formula")
(declare-function gascity-sling-formula--command "gascity-formula")
(declare-function gascity-sling-formula--show-recipe "gascity-formula")
(declare-function gascity-sling-formula--var-children "gascity-formula")
(declare-function gascity-formula--nonblank "gascity-formula")
(declare-function gascity-sling-formula--work-title-at-point "gascity-formula")
(declare-function gascity-formula-recipe-cached "gascity-formula")
(declare-function gascity-formula--needs-convoy "gascity-formula")
(declare-function gascity-formula--blank "gascity-formula")
(declare-function gascity-agents-roster "gascity-agents")
(declare-function gascity-agents-roster-candidates "gascity-agents")
(declare-function gascity-agents--roster "gascity-agents")
(declare-function gascity-formula-invalidate "gascity-formula")
(declare-function gascity-formula-refresh-async "gascity-formula")
(declare-function gascity-mail-inbox-refresh "gascity-mail")
;; The live footer (REQ-007/REQ-010, plans/sling-command WI-6) also
;; reaches into the sibling work items of the sling redesign, which
;; land as their own commits: the shape sentence (WI-1) and the
;; client-side validators with their warning builders (WI-2) in
;; gascity-formula, the roster accessors in gascity-agents.  Declared
;; here so the whole-package compile gate sees the wiring; the
;; footer's tests stub each one at its contract.
(declare-function gascity-sling--shape (work formula) "gascity-formula")
(declare-function gascity-sling--v2-trap-p (recipe scope) "gascity-formula")
(declare-function gascity-sling--v2-trap-warning
                  (&optional rig) "gascity-formula")
(declare-function gascity-sling--cross-store-p (work scope rigs) "gascity-formula")
(declare-function gascity-sling--cross-store-warning
                  (work scope rigs) "gascity-formula")
(declare-function gascity-sling--missing-work-p (recipe work) "gascity-formula")
(declare-function gascity-sling--missing-work-warning (recipe) "gascity-formula")
(declare-function gascity-sling--missing-required-vars
                  (recipe values) "gascity-formula")
(declare-function gascity-sling--missing-vars-warning (names) "gascity-formula")
(declare-function gascity-sling--missing-target-p (target) "gascity-formula")
(declare-function gascity-agents-scope (agent) "gascity-agents")
(declare-function gascity-agents-roster-scope (target roster) "gascity-agents")
(declare-function gascity-agents--roster (data) "gascity-agents")

;; The launch follow offer's pieces live in later-loading modules: the
;; run detail its `F' jump opens, and the composite per-store read its
;; fallback resolves the newest run root through (cross-file wiring —
;; a missing declaration is only caught by the `--warnings-as-errors'
;; compile gate).
(declare-function gascity-run-show "gascity-run")
(declare-function gascity-dashboard--read-work "gascity-dashboard")

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
                                             (dir default-directory)
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
       (gascity-command-arguments command)
       :target target
       :dir dir
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
`async-shell-command' base method.  DIR (default the calling buffer's
directory) pins the call to the city it must hit — a buffer whose
`default-directory' may have moved (a preview filled from anywhere)
passes its own pin."
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

(defun gascity-action--read-session (prompt &optional default)
  "Read a session alias with PROMPT, defaulting to DEFAULT, else point.
DEFAULT, when non-nil (e.g. the sling menu's derived Who target), wins
over the agent at point — RET keeps it."
  (completing-read prompt (gascity-action--session-names) nil nil nil nil
                   (or default (gascity-action--agent-at-point-name))))

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
  "Return the name of the rig at point, or signal a `user-error'.
A rig list row, else a rig row of a vui view: a line carrying a
`gascity-rig' name and no agent (the cockpit's Rigs rows, the rig
dashboard's title line).  An agent row's rig is not the rig at point:
the verbs there act on the agent."
  (let* ((rig (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id)))
         (name (cond ((gascity-rig-p rig) (gascity-rig-name rig))
                     ((gascity-rig-row-p) (get-text-property (point) 'gascity-rig)))))
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
  "Return the session alias at point, or signal a `user-error'.
Every session verb (nudge, suspend, kill, wake, drain, reset, undrain,
peek) resolves its target here, so an agent with no session (a pool
slot, `gascity-agent-sessionless-p') is refused with the reason rather
than sent to gc to fail with \"session not found\"."
  (gascity-agent-check-session
   (or (gascity-action--agent-at-point-name)
       (user-error "No session at point"))))

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

(defun gascity-action--city-label (&optional dir)
  "Return the city DIR governs as confirm prompts name it: NAME[@HOST].
The city root's name (memoized, else found by walking up: this runs
while gathering input), plus `@host' for a remote city, so a prompt
never leaves open which of several open cities it acts on."
  (let* ((dir (or dir default-directory))
         (root (or (gascity-context-city-root-cached dir)
                   (gascity-context-city-root dir)))
         (host (file-remote-p dir 'host)))
    (concat (if root
                (file-name-nondirectory (directory-file-name (file-local-name root)))
              "this city")
            (if host (concat "@" host) ""))))

;;;###autoload
(defun gascity-start ()
  "Start the Gas City under the machine-wide supervisor (streams output)."
  (interactive)
  (when (gascity-action--confirm "Start %s under the supervisor? "
                                 (gascity-action--city-label))
    (gascity-command-execute-interactive (gascity-command-start))))

;;;###autoload
(defun gascity-stop (&optional force)
  "Stop all agent sessions in the city.  With prefix arg FORCE, force-kill."
  (interactive "P")
  (when (gascity-action--confirm "Stop %s%s? " (gascity-action--city-label)
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
           "Prune dormant sessions of %s%s%s? "
           (gascity-action--city-label)
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

;;; Async text views (peek, sling dry runs)

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
;; (`gascity-sling-dispatch', DESIGN-write-actions §10): the staged
;; mockup layout — header (scope sentence plus the live footer), What
;; (`A' the work picker, `f' pick), the picked formula's full-width
;; How vars group, Who (`T'), the Routing flags (settled plain shape
;; only), then Actions (`s P r g x q').  `f' picks a
;; formula in place (the same prefix re-setups with the new scope); `T'
;; sets a visible target agent (roster completion, §6c); `A' picks the
;; work (bead/convoy or text) in place; `s'/`P' sling or open the
;; full preview.  With a formula picked the formula path runs
;; (validated vars, shape via `gascity-formula--needs-convoy', routing
;; flags ignored — they are consumed only by the plain path); without
;; one the plain flag path runs as before.  The generated variable
;; keys avoid the single-letter static bindings collected in
;; `gascity-sling--reserved-keys' (mockup §10).

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
empty) scope key (ga-4ia4, bright-lights dogfood §5).

Every reader the menu gains — the work picker, the agent picker, a
file or directory completion — runs under the same pin (REQ-012): a
new reader never reads from the ambient `default-directory' as given,
only through this function, so a completion offered from a reused
minibuffer still resolves against the entered-from city."
  (or (plist-get (or scope (transient-scope)) :city)
      default-directory))

(defvar gascity-sling--remembered nil
  "The sling menu's last state per city: an alist CITY-DIR → (SCOPE . VALUE).
SCOPE is the menu scope (formula, target, arg), VALUE its infix values
\(flags and formula vars).  Saved whenever the menu is set up again
\(pick, target, arg, refresh, preview), restored when `S' re-enters the
menu for that city, cleared by `x' and by a real sling — so a preview
followed by `S s' slings what was previewed (bug S-2).")

(defun gascity-sling--remember (scope value)
  "Remember SCOPE and VALUE as the sling menu state of SCOPE's city."
  (let ((city (plist-get scope :city)))
    (when city
      (setf (alist-get city gascity-sling--remembered nil nil #'equal)
            (cons (copy-sequence scope) (copy-sequence value))))))

(defun gascity-sling--forget (&optional city)
  "Forget the remembered sling menu state of CITY (default: the scope's)."
  (let ((city (or city (plist-get (ignore-errors (transient-scope)) :city))))
    (setq gascity-sling--remembered
          (seq-remove (lambda (e) (equal (car e) city)) gascity-sling--remembered))))

;;; Derived Who default (plan WI-3, REQ-005)
;;
;; `s' never asks Who again when a target is derivable.  The answer
;; is computed client-side, in the design's order: the work bead's rig
;; default, the per-(city, formula) launch memory, then the
;; implementation-worker convention — the roster's exactly one
;; rig-scoped `gc.implementation-worker'.  Every input is cached
;; data (`gascity-store-get', the rig memo): the derivation runs from
;; the menu's render path too, so it must never spawn gc (D9).

(defvar gascity-sling--target-memory nil
  "The sling menu's per-((city . formula)) launch target memory.
An alist ((DIR . FORMULA) . TARGET): the target of every real launch
is recorded (`gascity-sling--remember-target') and the next dispatch
of the same city and formula derives it (rule 2 of the Who default,
plan WI-3).  Plain launches record under FORMULA nil.  Unlike the
remembered menu state (`gascity-sling--remembered', cleared after a
launch) this is a memory, like the per-(formula,var) history: it
survives launches.")

(defun gascity-sling--remember-target (city formula target)
  "Record TARGET as CITY's launch target memory for FORMULA.
The target of a real launch — set with `-T', derived, or read at
dispatch — becomes the next launch's derived default (WI-3 rule 2).
CITY is the city directory, FORMULA the formula name or nil (a plain
sling); an empty TARGET records nothing."
  (when (and city (stringp target) (not (string-empty-p target)))
    (setf (alist-get (cons city formula) gascity-sling--target-memory
                     nil nil #'equal)
          target)))

(defun gascity-sling--memory-target (scope memory)
  "Return the launch target remembered for SCOPE in MEMORY, or nil.
Pure: the (city . formula) pair of SCOPE against the alist — a hit is
the same city and the same formula; another formula, another city or
no entry is a miss."
  (cdr (assoc (cons (plist-get scope :city) (plist-get scope :formula))
              memory #'equal)))

(defun gascity-sling--work (scope)
  "Return SCOPE's work answer: a bead or convoy id, or freeform text.
`:work' generalizes `:arg' (plan WI-4); both are read, `:work' first,
so the derivation keeps working on either side of that rename."
  (or (plist-get scope :work) (plist-get scope :arg)))

(defun gascity-sling--work-rig (scope)
  "Return the memoized `gascity-rig' owning SCOPE's work bead, or nil.
The bead id's prefix routes to its rig — the same prefix routing the
bd verbs use — resolved against the rig memo (`gascity-rigs-cached')
alone: never a gc read (D9).  Freeform text, a prefixless id, an
unknown prefix or a cold memo all give nil (rule 1 skips fail-soft)."
  (when-let* ((work (gascity-sling--work scope))
              (prefix (gascity-beads--id-prefix work))
              (city (plist-get scope :city)))
    (seq-find (lambda (r) (equal (gascity-rig-prefix r) prefix))
              (gascity-rigs-cached city))))

(defun gascity-sling--rig-default-target (scope)
  "Return the work bead's rig default sling target for SCOPE, or nil.
`default_sling_target' first, then the first of
`default_sling_targets' — gc picks one of the list at random
server-side; a default the menu SHOWS must be deterministic.  The
rig's data comes from the memo, so a rig reporting no defaults — today
none do — gives nil and the derivation falls through (Open
Implementation Details: fail-soft)."
  (when-let* ((rig (gascity-sling--work-rig scope)))
    (or (gascity-rig-default-sling-target rig)
        (car (gascity-rig-default-sling-targets rig)))))

(defconst gascity-sling--implementation-worker "gc.implementation-worker"
  "The agent name of the Who convention rule (WI-3).
The derivation's third rule looks for the roster's exactly one
RIG-SCOPED agent of this name — the worker this very package's runs
are dispatched to — when that is unambiguous.  The match is on the
roster's configured template (a pool): slinging to it routes the
bead to an eligible session of the pool, so a live instance's
suffixed name never counts.")

(defun gascity-sling--implementation-worker-target (roster)
  "Return ROSTER's single rig-scoped implementation worker, or nil.
Exactly one `<rig>/gc.implementation-worker' derives that name (the
convention rule, WI-3); two or more — one per rig — are ambiguous, and
a city-scoped worker never counts: both skip the rule.  ROSTER is a
list of agent plists (`:name' the qualified name, `:rig' the rig).
Duplicate entries of the same agent are one."
  (let ((names (delete-dups
                (delq nil
                      (mapcar
                       (lambda (a)
                         (let ((name (plist-get a :name)))
                           (and (stringp name)
                                (string-match
                                 (format "\\`\\(.+\\)/%s\\'"
                                         (regexp-quote
                                          gascity-sling--implementation-worker))
                                 name)
                                name)))
                       roster)))))
    (pcase names (`(,only) only) (_ nil))))

(defun gascity-sling--derive-target (scope roster memory)
  "Return the derived Who target for SCOPE, ROSTER and MEMORY, or nil.
The design's order (REQ-005): (1) the work bead's rig
`default_sling_target'/`default_sling_targets', fail-soft when the
rig data carries none; (2) the per-(city, formula) target memory;
(3) the implementation-worker convention — ROSTER's exactly one
rig-scoped `gc.implementation-worker' when unambiguous.  Pure over
its inputs: SCOPE is the menu's scope plist, ROSTER a list of agent
plists (`:name' `:rig'), MEMORY the `gascity-sling--target-memory'
alist.  The answer is `(:target NAME :source SOURCE)' with SOURCE one
of `rig-default', `memory' or `implementation-worker' — the header's
derived tag and the `T' picker's seed render from it — or nil when no
rule derives.  A target set in the scope wins over the derivation;
this function never consults it."
  (or (when-let* ((target (gascity-sling--rig-default-target scope)))
        (list :target target :source 'rig-default))
      (when-let* ((target (gascity-sling--memory-target scope memory)))
        (list :target target :source 'memory))
      (when-let* ((target (gascity-sling--implementation-worker-target roster)))
        (list :target target :source 'implementation-worker))))


(defun gascity-sling--roster (&optional city)
  "Return CITY's agent roster for the Who derivation, or nil when cold.
One plist per configured agent of the `gc agent list' payload — `:name'
the qualified name, `:rig' its slash prefix, nil for a city-scoped
agent.  Those names are the sling targets (a singleton agent or a
pool template, `mayor', `gascity.el/gc.implementation-worker'), so
they are the convention rule's roster; live sessions carry instance
suffixes (`…/gc.implementation-worker-18') and name no config, so the
session join is deliberately not read here — unlike the Who picker
and the footer, whose joined list (`gascity-agents--roster', review
R3/S1) classifies live targets too.  Read from the store's cache only
\(`gascity-store-get': never a spawn, never a block — the header
renders through this, D9); a cold or failed read is an empty roster
and the roster rule skips fail-soft.  CITY defaults to the live
scope's city."
  (let* ((dir (or city (gascity-sling--city-dir)))
         (data (plist-get (gascity-store-get '("agent" "list") dir) :data)))
    (delq nil
          (mapcar (lambda (a)
                    (let ((name (alist-get 'qualified_name a)))
                      (and (stringp name)
                           (list :name name
                                 :rig (gascity-dashboard--rig-of name)))))
                  (append (alist-get 'agents data) nil)))))

(defun gascity-sling--derived-target (&optional scope)
  "Return the derived Who target of SCOPE (default the live scope).
Gathers the derivation's inputs from session state — the roster from
the cached `gc agent list' payload (`gascity-sling--roster'), the
memory from `gascity-sling--target-memory' — and runs
`gascity-sling--derive-target' over them.  See that function for the
answer's shape and the rule order.  Pure over cached data, never a
gc read (D9): the header and footer render through this."
  (let ((scope (or scope (ignore-errors (transient-scope)))))
    (when scope
      (gascity-sling--derive-target
       scope (gascity-sling--roster (gascity-sling--city-dir scope))
       gascity-sling--target-memory))))
(defun gascity-sling--resetup (scope)
  "Set the sling menu up again with SCOPE and the current values; remember both."
  (let ((value (transient-args 'gascity-sling-dispatch)))
    (gascity-sling--remember scope value)
    (transient-setup 'gascity-sling-dispatch nil nil :scope scope :value value)))

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
Otherwise the plain path runs on the redesign's What → Who order: the
work — what the scope holds, else the smart picker (the `A'
completion, mockup §6a, with the freeform fallthrough) — then the
target, parse the flags and act or preview.  A target set through
`T' wins; with none set, the Who default
is derived (WI-3: the rig default, the (city, formula) launch
memory, then the implementation-worker convention), and only when
nothing derives does the agent completion run (mockup §6c, over the
roster's cached peek).
With PREVIEW non-nil, force `--dry-run' and show gc's
routing plan instead of executing.  A real launch — plain or
formula — records its target as the (city, formula) pair's launch
memory (`gascity-sling--target-memory', REQ-012; a plain sling
records under FORMULA nil); a preview records nothing."
  (let ((default-directory (gascity-sling--city-dir)))
    (let* ((scope (transient-scope))
           (formula (plist-get scope :formula))
           ;; The plain path's work: what the scope holds (seeded at
           ;; point, picked with `A'), else the smart picker (mockup
           ;; §6a) — the What answer before the Who one.  `:arg' is
           ;; the legacy name; `gascity-sling--work' reads both.
           (arg (if formula
                    (gascity-sling--work scope)
                  (or (gascity-sling--work scope)
                      (gascity-sling--read-work))))
           ;; The work just read belongs to the scope the derivation
           ;; sees: a bead id picked here can still rig-default its
           ;; target (rule 1 keys off the work bead).
           (scope (plist-put (copy-sequence scope) :work arg))
           (target (or (plist-get scope :target)
                       ;; The derived Who default (WI-3): a derivable
                       ;; target is used without prompting (REQ-005);
                       ;; only when nothing derives does the agent
                       ;; completion run (mockup §6c, the roster's
                       ;; cached peek — no spawn on the dispatch path).
                       (plist-get (gascity-sling--derived-target scope) :target)
                       (gascity-sling--read-agent
                        "Target agent: " nil
                        (gascity-sling--roster-cached
                         (gascity-sling--city-dir scope))))))
      (if formula
          (progn
            (gascity-sling-formula--dispatch
             (gascity-formula-recipe-cached formula)
             target arg (gascity-sling-formula--current-values) preview))
        (let* ((plist (gascity-sling--parse-transient-args args))
               (command (apply #'gascity-command-sling
                               :target target :arg arg
                               (append (when preview (list :dry-run t))
                                       plist))))
          (if preview
              (gascity-sling--show-plan command)
            ;; `gc sling --json': the dispatch result is summarized
            ;; from the payload when the async call answers (D9).
            (oset command json t)
            (gascity-command-act-async command))))
      ;; A real launch — never a preview — remembers its target as the
      ;; (city, formula) pair's launch memory (REQ-012, WI-3): the Who
      ;; default derivation reads it back (rule 2); a plain launch
      ;; records under FORMULA nil.  Recording runs after the
      ;; dispatch, so a validation `user-error' records nothing, and a
      ;; preview is not a choice — it records nothing.
      (unless preview
        (gascity-sling--remember-target
         (gascity-sling--city-dir scope) formula target))
      ;; What was read goes into the scope: a preview keeps the menu
      ;; open showing it, and the `s' that follows slings exactly it.
      ;; SCOPE is already the work-updated copy; the target lands on it.
      (plist-put scope :target target))))

;;; The work picker's read (mockup §6a) — WI-4
;;
;; `A' (and a cold `s') complete over the city's work: the open,
;; in-progress and blocked beads of every store — the dashboard's own
;; per-store read, no new gc call site — plus the city's convoys,
;; each row annotated `title · status · store'.

(defconst gascity-sling--work-choices-key
  '("bd" "list" :sling-work-choices)
  "Store key of the work picker's composite read (kind `bd').")

(defun gascity-sling--read-work-choices (resolve reject)
  "Load the work picker's candidates; RESOLVE gets the combined payload.
The beads are every store's `bd list --status in_progress,open,blocked'
\(`gascity-dashboard--read-work', each row stamped with its
\`(gascity-rig . NAME)' store); the convoys are the city store's
`gc convoy list'.  REJECT only when every read failed — a partial
answer is still completion candidates."
  (let* ((dir (gascity-sling--city-dir))
         beads convoys errors
         (pending 2)
         (settle (lambda ()
                   (when (zerop (setq pending (1- pending)))
                     (if (and (null beads) (null convoys)
                              (= (length errors) 2))
                         (funcall reject (car errors))
                       (funcall resolve
                                (list :beads beads :convoys convoys
                                      :errors errors)))))))
    (let ((default-directory dir))
      (gascity-dashboard--read-work
       (lambda (payload)
         (setq beads (plist-get payload :beads))
         (setq errors (append errors (plist-get payload :errors)))
         (funcall settle))
       (lambda (err)
         (setq errors (append errors (list err)))
         (funcall settle)))
      (gascity-store-fetch
       '("convoy" "list")
       (lambda (payload)
         (setq convoys (append (alist-get 'convoys payload) nil))
         (funcall settle))
       (lambda (err)
         (setq errors (append errors (list err)))
         (funcall settle))))))

(defun gascity-sling--work-choices (payload)
  "Return the work picker's completion candidates from PAYLOAD.
The mockup §6a rows: (ID . \"title · status · store\") — the open
beads of every store first, then the convoys (`convoy' in the
status's place: `gc convoy list' reports none).  A row without an id
is skipped, never guessed at.  Pure."
  (let ((store (lambda (row)
                 (or (cdr (assq 'gascity-rig row)) "city"))))
    (delq nil
          (append
           (mapcar
            (lambda (b)
              (and (alist-get 'id b)
                   (cons (alist-get 'id b)
                         (format "%s · %s · %s"
                                 (or (alist-get 'title b) (alist-get 'id b))
                                 (or (alist-get 'status b) "?")
                                 (funcall store b)))))
            (plist-get payload :beads))
           (mapcar
            (lambda (c)
              (and (alist-get 'id c)
                   (cons (alist-get 'id c)
                         (format "%s · convoy · %s"
                                 (or (alist-get 'title c) (alist-get 'id c))
                                 (funcall store c)))))
            (plist-get payload :convoys))))))

(defun gascity-sling--work-choices-wait ()
  "Return the work picker's candidates, reading through the store first.
Input collection (D9): the entry prefetch usually answered; when the
store is cold, wait for the composite read — deadline-bounded,
`C-g' quits — rather than read gc synchronously.  Nothing answered
is nil: the picker falls through to freeform text (never a dead
end)."
  (let ((done nil) (payload nil)
        (deadline (+ (float-time)
                     (if (numberp gascity-remote-async-timeout)
                         (1+ gascity-remote-async-timeout)
                       31))))
    (gascity-store-fetch
     gascity-sling--work-choices-key
     (lambda (p) (setq payload p done t))
     (lambda (_err) (setq done t))
     :loader #'gascity-sling--read-work-choices)
    (with-local-quit
      (while (and (not done) (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (and payload (gascity-sling--work-choices payload))))

;;; The launch follow offer (plans/sling-command WI-8, REQ-009)
;;
;; A successful formula sling creates a workflow, and its root —
;; reported by the `gc sling --json' payload — is offered for one
;; keypress: `F' jumps to the run view, any other key dismisses and
;; runs its own binding, the user staying put.  The plain route never
;; offers (it creates no workflow of its own) and keeps its plain
;; echo.  Nothing here blocks: the offer runs from the act's
;; `:on-success' callback, once the launch has answered (D9).

(defconst gascity-sling--run-roots-key
  '("bd" "list" :sling-run-roots)
  "Store key of the follow offer's run-roots read (kind `bd').")

(defconst gascity-sling--run-roots-argv
  '("bd" "list" "--all" "-n" "0" "--brief"
    "--metadata-field" "gc.kind=workflow")
  "The per-store read behind `gascity-sling--run-roots-key': every run
root bead of a store — the Runs view's own roots argv (all statuses,
no row limit, no free text).")

(defun gascity-sling--read-run-roots (resolve reject)
  "Read the run roots of the city store and each rig store.
The loader of `gascity-sling--run-roots-key', the fallback read of the
follow offer.  RESOLVE gets (:beads BEADS :errors ERRORS), every
root stamped with its `gascity-rig' store (nil: the city store),
REJECT only when every store failed — `gascity-dashboard--read-work'."
  (gascity-dashboard--read-work resolve reject
                                (list gascity-sling--run-roots-argv)))

(defun gascity-sling--launched-root (result)
  "Return the root bead id of the workflow sling RESULT created, or nil.
`gc sling --json' names it in `molecule_id' — the payload schema's
\"Created molecule/root workflow bead ID\", the field the WI-11 e2e
pass confirms live.  No other field is documented to be a bead id, so
none is read: the follow offer never guesses (REQ-009).  A non-alist
RESULT (a failed JSON parse hands back raw stdout) yields nil."
  (and (consp result)
       (let ((root (alist-get 'molecule_id result)))
         (and (stringp root) (not (string-empty-p root)) root))))

(defun gascity-sling--launched-formula (result formula)
  "Return the formula of a successful sling RESULT, else FORMULA (its name)."
  (or (and (consp result)
           (let ((name (alist-get 'formula result)))
             (and (stringp name) (not (string-empty-p name)) name)))
      formula))

(defun gascity-sling--launched-work (result arg)
  "Return the work a successful sling RESULT acted on.
The payload's `bead_id' — \"Created or selected work bead ID\" — when
it answers, else ARG: the convoy routed `--on', or the freeform text.
With neither answering (not possible from the dispatch's own shapes,
which always carry one) the echo shows `…'."
  (or (and (consp result)
           (let ((bead (alist-get 'bead_id result)))
             (and (stringp bead) (not (string-empty-p bead)) bead)))
      (and (stringp arg) (not (string-empty-p arg)) arg)
      "…"))

(defun gascity-sling--root-rig (id dir)
  "Return the name of the rig store owning bead ID, or nil.
ID's prefix (`gascity-beads--id-prefix') picks the rig from DIR's
host's rig memo (`gascity-rigs-cached') — no gc call: the offer lands
from a store callback (D9).  A cold memo or a city-store bead yields
nil, which `gascity-run-show' reads as the city store."
  (when-let* ((prefix (gascity-beads--id-prefix id))
              (rig (seq-find (lambda (r) (equal (gascity-rig-prefix r) prefix))
                             (gascity-rigs-cached dir))))
    (gascity-rig-name rig)))

(defun gascity-sling--newest-run-root (beads since)
  "Return (ID . RIG) of the newest of BEADS created at or after SINCE.
BEADS are the fallback read's run-root rows, each stamped with its
`gascity-rig' store (nil: the city store); SINCE is epoch seconds.
The newest is by `created_at', parsed with `gascity-ui-parse-time'; a
row without an id or a parseable timestamp is skipped, never guessed
at.  Nil when nothing was created since SINCE."
  (let ((newest nil)
        (at -1.0))
    (dolist (b (and (listp beads) beads))
      (when-let* ((id (alist-get 'id b))
                  (created (gascity-ui-parse-time (alist-get 'created_at b))))
        (when (and (stringp id) (not (string-empty-p id))
                   (>= created since) (> created at))
          (setq at created
                newest (cons id (cdr (assq 'gascity-rig b)))))))
    newest))

(defun gascity-sling--follow-offer (root formula work &optional rig)
  "Echo the launch of the workflow ROOT and offer to follow it (`F').
`Launched workflow <id> (<formula> on <work>) — F: run view' in the
echo area, then a momentary keymap: the next `F' jumps to
`gascity-run-show' on ROOT — RIG, when non-nil, the owning rig
store, so `b'/RET open its beads in the right one — and any other
key dismisses the map and runs its own binding: the user stays put
(REQ-009).  No map is installed over an active minibuffer, whose
input it would hijack."
  (message "Launched workflow %s (%s on %s) — F: run view" root formula work)
  (unless (active-minibuffer-window)
    (let ((map (make-sparse-keymap)))
      (define-key map "F"
                  (lambda ()
                    (interactive)
                    (gascity-run-show root nil rig)))
      (set-transient-map map))))

(defun gascity-sling--resolve-launched-root (started dir then)
  "Resolve the run root created since STARTED, passing it to THEN.
The follow offer's fallback (REQ-009), taken when the payload does
not name the root: the run roots of the city's stores are read once
through the store, in DIR — the city the sling was entered from (a
store callback's `default-directory' is arbitrary; the completed
action has already invalidated the `bd' kind, so the read answers
post-launch).  THEN is called with the (ID . RIG) of the newest root
created at or after STARTED — the launch's start in epoch seconds,
less a two-second allowance for whole-second rounding and trivial
clock skew (the bead is stamped by gc, possibly on another host) —
or nil when the launch created none or the read failed: never a guess."
  (let ((default-directory dir))
    (gascity-store-fetch
     gascity-sling--run-roots-key
     (lambda (payload)
       (funcall then (gascity-sling--newest-run-root
                      (plist-get payload :beads)
                      (- started 2))))
     (lambda (_err) (funcall then nil))
     :loader #'gascity-sling--read-run-roots)))

(defun gascity-sling--launch-handler (command formula arg)
  "Return the `:on-success' handler of a formula sling (WI-8, REQ-009).
COMMAND is the sling being acted on, FORMULA its name, ARG the
bead/convoy it was slung on.  When gc answers, the workflow root the
launch created — named by the payload (`gascity-sling--launched-root')
— is echoed with the momentary `F' follow offer
(`gascity-sling--follow-offer'); a payload without it resolves the
newest run root through the store first, and a launch that resolves
no root at all keeps the plain success echo.  The launch itself
never blocks: this handler runs only once the action has answered
(D9)."
  (let* ((target (gascity-action--command-target command))
         (dir default-directory)
         (started (float-time)))
    (lambda (result)
      (if-let* ((root (gascity-sling--launched-root result)))
          (gascity-sling--follow-offer
           root
           (gascity-sling--launched-formula result formula)
           (gascity-sling--launched-work result arg)
           (gascity-sling--root-rig root dir))
        (gascity-sling--resolve-launched-root
         started dir
         (lambda (run)
           (if run
               (gascity-sling--follow-offer
                (car run)
                (gascity-sling--launched-formula result formula)
                (gascity-sling--launched-work result arg)
                (cdr run))
             (message "%s" (gascity-action--success-text
                             command target result)))))))))

(transient-define-suffix gascity-sling-dispatch-run (args)
  "Sling for real using the dispatch flags ARGS.
The city's remembered menu state is cleared: the next `S' starts fresh."
  (interactive (list (transient-args 'gascity-sling-dispatch)))
  (let ((city (plist-get (transient-scope) :city)))
    (gascity-sling--run args nil)
    (gascity-sling--forget city)))

(transient-define-suffix gascity-sling-dispatch-preview (args)
  "Preview the sling (gc `--dry-run' routing plan) for the dispatch ARGS.
The menu stays open with its formula, target, arg and vars — the target
and arg read for the preview now in the header — so `s' slings exactly
what was previewed (bug S-2).  The state is also remembered for the
city, so re-entering `S' after leaving restores it."
  :transient t
  (interactive (list (transient-args 'gascity-sling-dispatch)))
  (gascity-sling--resetup (gascity-sling--run args t)))

;;; ============================================================
;;; Sling — the full preview buffer (`P', REQ-008, mockup §8)
;;; ============================================================
;;
;; `p' shows gc's `--dry-run' routing plan alone; `P' opens the whole
;; picture in one city-pinned buffer: the header sentence, every
;; client-side validation check with its full text, the cached
;; recipe's step DAG (steps → needs), and the routing plan filling in
;; when the async dry run answers — the first paint is client-side and
;; never blocks on the dry run (D9).  Nothing is read or prompted to
;; open it: a missing target or work is a validation warning, and the
;; routing plan section keeps its reason.  `s' launches directly from
;; the buffer (completing a missing piece the way the menu's `s'
;; would); `q' quits; the menu's `r' keeps the server-substituted
;; recipe preview.  The preview is never a gate: the menu's `s' works
;; anytime, with or without `P'.  The menu exits on `P' — the buffer
;; is the interactive surface — but its state is remembered per city
;; (bug S-2), so a later `S s' slings exactly what was previewed.

(defconst gascity-sling-preview-buffer-name "*gc-sling: preview*"
  "Base name of the full sling preview buffer (`P', REQ-008).
Host-qualified and city-pinned by `gascity-view-get-buffer-create'
like every view, so a local and a remote preview coexist.")

(defvar-local gascity-sling-preview--data nil
  "The dispatch this preview buffer previews, as a plist:
`:city' the pinned city directory, `:scope' the menu scope it came
from, and `:launch' a thunk starting the real sling (no `--dry-run')
— exactly what the menu's `s' would sling.  Set when the buffer is
painted; `gascity-sling-preview-launch' reads it.")

(defvar-local gascity-sling-preview--plan-marker nil
  "Marker at the Routing plan section's answer, or nil.
The async dry run's stdout (or its failure line) replaces the buffer
from this marker down (`gascity-sling--preview-fill-plan').")

(defvar gascity-sling-preview-validation-functions nil
  "Abnormal hook adding validation lines to the full preview buffer.
Each function is called with (SCOPE RECIPE VALUES) inside the city
pin and returns a list of full-text check lines (`✓ …' / `⚠ …'), nil
when it has nothing to say.  Pure, cached data only — nothing here
may run gc (REQ-008/010); the roster-based checks of the sling
redesign (the bl-bdj trap, cross-store routing) belong here.")

(defvar-keymap gascity-sling-preview-mode-map
  :doc "Keymap of the full sling preview buffer (REQ-008).
`s' launches the previewed sling from here; `q' quits."
  "s" #'gascity-sling-preview-launch
  "q" #'quit-window)

(define-derived-mode gascity-sling-preview-mode special-mode "GC-Sling-Preview"
  "Read-only full preview of the pending sling (REQ-008, mockup §8).
The buffer holds everything gascity can compute client-side — the
header sentence, the validation checks in full, the cached recipe's
steps → needs DAG — plus gc's `--dry-run' routing plan when it
answers.  `s' launches exactly what was previewed, completing a
missing target or work the way the menu's `s' would (D9); `q' quits.
The preview is never a gate: the menu's `s' works anytime.

The buffer is created through `gascity-view-get-buffer-create', so
it is host-qualified and its `default-directory' stays pinned to
the city the menu was entered from — a local and a remote preview
coexist, and the launch keeps hitting the entered-from city.

\\{gascity-sling-preview-mode-map}")

(defun gascity-sling--preview-header (scope recipe)
  "Return the preview buffer's header sentence for the SCOPE dispatch.
The one-sentence summary, mockup §1–§4 wording: plain (`Sling WORK to
TARGET'), formula (`Run FORMULA (formula) on TARGET'), targeted
(`Run FORMULA against bead WORK, drained by TARGET' — the drain
clause consults `gascity-formula--needs-convoy' on RECIPE).  The
sling redesign's own sentence renderer (WI-1) owns the final
wording; this stays close to it so the buffer reads as the menu's
fuller twin.  Missing pieces read as their mockup §2 hints."
  (let ((formula (plist-get scope :formula))
        (work (gascity-sling--work scope))
        (target (plist-get scope :target)))
    (cond
     ((and formula recipe (gascity-formula--needs-convoy recipe))
      (format "Run %s against bead %s, drained by %s"
              formula
              (if (gascity-formula--nonblank work) work "(no work — A or point at a bead)")
              (if (gascity-formula--nonblank target) target "(no target — T or default)")))
     (formula
      (format "Run %s (formula) on %s"
              formula
              (if (gascity-formula--nonblank target) target "(no target — T or default)")))
     (t
      (format "Sling %s to %s"
              (if (gascity-formula--nonblank work) work "(no work — A or point at a bead)")
              (if (gascity-formula--nonblank target) target "(no target — T or default)"))))))

(defun gascity-sling--preview-validation-lines (scope recipe values)
  "Return the Validation section's check lines for the SCOPE dispatch.
RECIPE is the cached recipe (nil on the plain path), VALUES the
collected formula var values.  One full-text line per check, `✓' when
it passes and `⚠' when it has something to say: the target every
dispatch needs, the work a convoy-requiring formula needs, and
required vars and patterns — the same rules
`gascity-sling-formula--command' enforces at dispatch, spelled out
before any gc call.  Pure, cached data only, and never a gate
(REQ-008): `s' stays available whatever this says.  Further checks
join through `gascity-sling-preview-validation-functions'."
  (let ((formula (plist-get scope :formula))
        (work (gascity-sling--work scope))
        (target (plist-get scope :target))
        (lines nil))
    (setq lines
          (list (if (gascity-formula--nonblank target)
                    (format "✓ target %s" target)
                  "⚠ no target — set one with T (launching asks otherwise)")))
    (when (and formula recipe (gascity-formula--needs-convoy recipe))
      (setq lines
            (append lines
                    (if (gascity-formula--nonblank work)
                        (list (format "✓ work %s (the formula requires it)" work))
                      (list (format "⚠ no work — %s requires a target convoy (A, or point at a bead)"
                                    formula))))))
    (when formula
      (let* ((vars (or (and recipe (gascity-formula-vars recipe)) '()))
             (required (delq nil
                             (mapcar (lambda (var)
                                       (and (gascity-formula-var-required var)
                                            (gascity-formula-var-name var)))
                                     vars)))
             (missing (delq nil
                            (mapcar (lambda (name)
                                      (and (gascity-formula--blank
                                           (cdr (assoc name values)))
                                           name))
                                    required))))
        (setq lines
              (append lines
                      (if required
                          (if missing
                              (mapcar (lambda (name)
                                        (format "⚠ missing required var: %s" name))
                                      missing)
                            (list (format "✓ required vars set: %s"
                                          (mapconcat #'identity required ", "))))
                        '("✓ no required vars"))))
        (dolist (var vars)
          (let ((pattern (gascity-formula-var-pattern var))
                (value (cdr (assoc (gascity-formula-var-name var) values))))
            ;; A blank value is the required check's business; a
            ;; pattern that does not compile as an Emacs regexp
            ;; degrades to no check (REQ-016) — the
            ;; `gascity-formula--validate-values' rules, mirrored.
            (when (and pattern (gascity-formula--nonblank value))
              (condition-case nil
                  (unless (string-match pattern value)
                    (setq lines
                          (append lines
                                  (list (format "⚠ var %s does not match pattern %s"
                                                (gascity-formula-var-name var)
                                                pattern)))))
                (invalid-regexp nil)))))))
    (dolist (fn gascity-sling-preview-validation-functions)
      (let ((extra (funcall fn scope recipe values)))
        (when (stringp extra) (setq extra (list extra)))
        (setq lines (append lines extra))))
    lines))

(defun gascity-sling--preview-recipe-lines (scope recipe)
  "Return the Recipe section's `steps → needs' lines for the SCOPE dispatch.
The step/dependency data of the CACHED recipe — the same payload
`gascity-sling-formula--render-recipe' renders — straight from gc's
compiled recipe, never re-substituted (REQ-012): one line per step,
the steps it depends on behind `needs'.  Without a formula the plain
dispatch has no recipe and the section says so."
  (if (not (plist-get scope :formula))
      '("  (no formula picked — this dispatch is plain)")
    (let* ((steps (or (and recipe (gascity-formula-steps recipe)) '()))
           (deps (or (and recipe (gascity-formula-deps recipe)) '())))
      (if (not steps)
          '("  (no steps)")
        (mapcar
         (lambda (step)
           (let* ((id (or (alist-get 'id step) ""))
                  (title (or (alist-get 'title step) id))
                  (needs (delq nil
                               (mapcar (lambda (dep)
                                         (and (equal (alist-get 'step_id dep) id)
                                              (or (alist-get 'depends_on_id dep) "?")))
                                       deps))))
             (format "  %-24s needs %s"
                     title
                     (if needs (mapconcat #'identity needs ", ") "nothing"))))
         steps)))))

(defun gascity-sling--preview-fill-plan (buf text)
  "Fill BUF's Routing plan section with the dry run's TEXT answer.
TEXT is gc's captured stdout, the failure's first line, or the reason
no plan was asked for; blank stdout shows the `(no plan output)'
placeholder of `gascity-sling--show-plan'.  The section shows `…'
until the async dry run answers; a killed BUF is left alone — a late
answer must not resurrect it (D9)."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (when (and (markerp gascity-sling-preview--plan-marker)
                 (marker-position gascity-sling-preview--plan-marker))
        (let ((inhibit-read-only t)
              (body (if (and (stringp text)
                             (not (string-empty-p (string-trim text))))
                        text
                      "(no plan output)")))
          (save-excursion
            (goto-char gascity-sling-preview--plan-marker)
            (delete-region (point) (point-max))
            (insert body)
            (unless (string-suffix-p "\n" body) (insert "\n"))))))))

(defun gascity-sling--preview-start-plan (buf command)
  "Start the `--dry-run' sling COMMAND filling BUF's Routing plan section.
Read-only like `gascity-sling--show-plan' — a view target on the
store's action lane, no cache invalidation — through
`gascity-command-act-async', so gc's captured stdout (or its
failure's first line, also echoed) lands in the section when gc
answers (D9: first paint never waited for it)."
  (with-current-buffer buf
    (gascity-command-act-async
     command
     :target (list 'view (buffer-name buf))
     :dir default-directory
     :invalidate nil
     :on-success (lambda (text)
                   (gascity-sling--preview-fill-plan buf text))
     :on-error (lambda (msg)
                 (message "%s" msg)
                 (gascity-sling--preview-fill-plan buf msg)))))

(defun gascity-sling--preview-paint (buf scope recipe values)
  "Paint BUF's client-side sections for the SCOPE dispatch; return BUF.
The header sentence, Validation, the cached recipe's steps → needs
DAG and the Routing plan heading with its `…' placeholder —
everything gascity can compute without gc, so the first paint never
blocks (REQ-008, D9).  The plan marker is left where the dry run's
answer will replace from."
  (with-current-buffer buf
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (format "Sling preview — %s  (s launch · q quit)\n"
                     (or (gascity-context-city-name) "gc"))
              (make-string 72 ?─) "\n"
              "  " (gascity-sling--preview-header scope recipe) "\n")
      (insert "\nValidation\n")
      (dolist (line (gascity-sling--preview-validation-lines scope recipe values))
        (insert "  " line "\n"))
      (insert "\n" (format "Recipe — %s (steps → needs)\n"
                           (or (plist-get scope :formula) "none picked (plain dispatch)")))
      (dolist (line (gascity-sling--preview-recipe-lines scope recipe))
        (insert line "\n"))
      (insert "\nRouting plan (gc sling … --dry-run)\n")
      (setq gascity-sling-preview--plan-marker (copy-marker (point)))
      (insert "  …\n")
      (goto-char (point-min))))
  buf)

(defun gascity-sling--full-preview (scope args)
  "Open the full preview buffer (REQ-008) for the menu SCOPE and ARGS.
Resolves the same dispatch the menu's `s'/`p' would run — without
reading or prompting anything — paints every client-side section at
once, then starts the `--dry-run' whose answer fills the Routing
plan section.  A dispatch that cannot be built yet (no target, no
work, a failing validation) still previews: the warning is in
Validation and the routing plan section keeps its reason — the
preview is never a gate.  Returns SCOPE, remembered per city (bug
S-2), so a later `S s' slings exactly what was previewed."
  (let* ((default-directory (gascity-sling--city-dir scope))
         (formula (plist-get scope :formula))
         (recipe (and formula (gascity-formula-recipe-cached formula)))
         (values (and formula (gascity-sling-formula--current-values)))
         (target (plist-get scope :target))
         (arg (gascity-sling--work scope))
         (buf (gascity-view-get-buffer-create
               gascity-sling-preview-buffer-name)))
    (with-current-buffer buf
      (gascity-sling-preview-mode)
      (setq gascity-sling-preview--data
            (list :city (gascity-sling--city-dir scope)
                  :scope scope
                  :launch (if formula
                              ;; The proven dispatch path, completing a
                              ;; missing target the way `s' does.
                              (lambda ()
                                (gascity-sling-formula--dispatch
                                 recipe
                                 (or target
                                     (gascity-sling--read-agent
                                      "Target agent: " nil
                                      (gascity-sling--roster-cached
                                       (gascity-sling--city-dir scope))))
                                 arg values))
                            ;; The plain path, exactly `gascity-sling--run':
                            ;; the city pin travels with the launch (the
                            ;; buffer is host-pinned, but its caller may
                            ;; not be).
                            (lambda ()
                              (let* ((default-directory
                                      (gascity-sling--city-dir scope))
                                     (arg (or arg
                                              (gascity-sling--read-work)))
                                     (command
                                      (apply #'gascity-command-sling
                                             :target
                                             (or target
                                                 (gascity-sling--read-agent
                                                  "Target agent: " nil
                                                  (gascity-sling--roster-cached
                                                   (gascity-sling--city-dir scope))))
                                             :arg arg
                                             (gascity-sling--parse-transient-args args))))
                                (oset command json t)
                                (gascity-command-act-async
                                 command :dir (gascity-sling--city-dir scope)))))))
      (gascity-sling--preview-paint buf scope recipe values)
      (pop-to-buffer buf)
      ;; The dry run: started after first paint, its answer fills in.
      ;; A dispatch that cannot be built keeps its reason here — the
      ;; validation lines above spell out why.
      (let* ((reason (cond
                      ((not (gascity-formula--nonblank target))
                       "(no routing plan — no target; set one with T in the menu)")
                      ((and (not formula) (not (gascity-formula--nonblank arg)))
                       "(no routing plan — no work; pick one with A or point at a bead)")
                      (t nil)))
             (command (and (not reason)
                           (condition-case nil
                               (if formula
                                   (gascity-sling-formula--command
                                    recipe target arg values t)
                                 (apply #'gascity-command-sling
                                        :target target :arg arg
                                        (append (list :dry-run t)
                                                (gascity-sling--parse-transient-args args))))
                             (user-error nil)))))
        (if command
            (gascity-sling--preview-start-plan buf command)
          (gascity-sling--preview-fill-plan
           buf (or reason "(no routing plan — see Validation above)")))))
    ;; What the menu held is remembered for the city (bug S-2): a
    ;; later `S s' slings exactly what was previewed.
    (gascity-sling--remember scope args)
    scope))

(transient-define-suffix gascity-sling-dispatch-full-preview (args)
  "Open the full preview buffer for the dispatch ARGS (REQ-008).
Everything computable client-side renders at once — the header
sentence, the validation checks with their full text, the cached
recipe's steps → needs DAG — and gc's `--dry-run' routing plan fills
its section in when the async call answers.  The menu exits: the
buffer is the interactive surface now — `s' there launches exactly
what was previewed, `q' quits — while the state is remembered for
the city (bug S-2), so a later `S s' slings the same dispatch.  The
preview is never a gate: the menu's `s' works anytime."
  (interactive (list (transient-args 'gascity-sling-dispatch)))
  (gascity-sling--full-preview (transient-scope) args))

(defun gascity-sling-preview-launch ()
  "Launch the sling this buffer previews (REQ-008).
`s' in the preview buffer: no input is gathered beyond what the
menu's own `s' would read — a missing target (or, on the plain
path, work) is completed with the same one-shot prompts, then the
call starts and returns (D9); gc's answer is echoed and the buffer
quits.  The city's remembered menu state is cleared, like the
menu's `s' (a real launch forgets, bug S-2)."
  (interactive)
  (let ((data gascity-sling-preview--data))
    (unless (and data (functionp (plist-get data :launch)))
      (user-error "This buffer previews nothing — open it with P in the sling menu"))
    (funcall (plist-get data :launch))
    (gascity-sling--forget (plist-get data :city))
    (quit-window)))

(transient-define-suffix gascity-sling-dispatch-reset ()
  "Clear the formula, target, arg and values; forget the city's saved state."
  :transient t
  (interactive)
  (let ((scope (transient-scope)))
    (gascity-sling--forget (plist-get scope :city))
    (transient-setup 'gascity-sling-dispatch nil nil
                     :scope (list :city (plist-get scope :city)
                                  :formula nil :target nil :arg nil))))

(defconst gascity-sling--reserved-keys
  '("A" "f" "T" "c" "a" "n" "m" "t" "s" "P" "r" "g" "x" "q")
  "Every single letter statically bound in `gascity-sling-dispatch'
— exactly the mockup §10 key summary: the What stage (`A' work
picker, `f' formula pick), the Who stage (`T' target), the routing
flags `-c -a -n -m -t' (rendered on the settled plain shape only)
and the Actions (`s', `P' the full preview, `r', `g', `x', `q').  The
old `p' dry-run suffix is freed — `P' previews everything.  The
generated variable infix keys avoid exactly this list; it lives
beside the layout it keys so a re-binding cannot silently collide
\(OQ-2), and a test asserts the two stay in sync.")

(defun gascity-sling--scope-info (scope &optional recipe)
  "Return the raw info spec describing SCOPE — the menu's header line.
One sentence, the inferred shape (REQ-002): no field list, no shape
flag — the shape is inferred from the scope's work + formula and the
wording is the signed-off mockup §1–§4 (e.g. \='Sling bead bl-5ja to
mayor\=', \='Run pancakes (formula) on mayor\', \='Run build-basic
against bead bl-5ja, drained by …\').  RECIPE is the picked formula's
cached recipe — the \='drained by\=' clause consults
`gascity-formula--needs-convoy' on it; nil (or a formula-less scope)
degrades without reading gc (D9).  A target only DERIVED — not set
with `-T' — renders in the sentence from the Who default derivation
(WI-3, REQ-005): what `s' would launch, no tag in the sentence.  The
`(:info …)' suffix form is passed unwrapped; nesting it as
`((:info …))' parses as an argument spec and crashes setup (founded in
the tmux-Emacs TRAMP e2e pass).  A leading `(:info …)' as the FIRST
element of its group vector also breaks setup — it parses as a group
argument — so the group title carries the city name and this spec
carries the sentence."
  (list :info
        (gascity-sling--header-sentence
         (or (plist-get scope :work) (plist-get scope :arg))
         (plist-get scope :formula)
         (or (plist-get scope :target)
             (when-let* ((derived (gascity-sling--derived-target scope)))
               (plist-get derived :target)))
         recipe)))

;; The live footer (REQ-007/REQ-010, mockup §1–§5, plans/sling-command
;; WI-6): the second header line, always visible, recomputed as each
;; answer changes.  The footer composes; the WI-2 validators decide and
;; their builders word (`gascity-sling--v2-trap-warning' & co.), the
;; WI-1 shape inference names the shape.  Full warning detail lives in
;; the `P' buffer (WI-7); the footer never blocks `s' — gc stays the
;; authority.

(defvar gascity-sling--missing-target-warning nil
  "The missing-target footer warning, mockup §5c wording.
Defined as a constant beside the WI-2 validators (gascity-formula);
the predeclaration keeps the whole-package compile gate green while
the work items land as their own commits.")

(defun gascity-sling--footer-rig (roster)
  "Return the scope of ROSTER's first rig-scoped agent, or nil.
The bl-bdj trap's suggestion names a rig the city actually has agents
for (mockup §5a: \='pick a hello-world/* agent with T\='): the first
rig-scoped row of WI-2's roster order.  A cold roster or an all-city
one degrades to nil — `gascity-sling--v2-trap-warning' then stays
generic.  Pure."
  (cl-loop for agent in roster
           for scope = (gascity-agents-scope agent)
           thereis (and (not (equal scope "city")) scope)))

(defun gascity-sling--footer--target-word (target scope)
  "Return TARGET as the footer's target word, at SCOPE.
`mayor (city)' for a city-scoped agent (mockup §1/§3); just
`rig-scoped' when the roster classifies the target under a rig — the
qualification is what a v2 launch needs, the name sits in the Who
line (§4/§5a); the bare name when neither (free entry, a cold
roster — never a guess)."
  (cond ((equal scope "city") (format "%s (city)" target))
        (scope "rig-scoped")
        (t (or target "(none)"))))

(defun gascity-sling--footer--vars-word (recipe values)
  "Return the footer's var word: how much of RECIPE is answered.
`no vars' on the plain shape (no formula, mockup §1), `0 vars' for a
formula that declares none (§3), `N of M vars set' counting the
non-blank answers of VALUES against the M declared (§4)."
  (let ((vars (and recipe (gascity-formula-vars recipe))))
    (cond
     ((null recipe) "no vars")
     ((null vars) "0 vars")
     (t (format "%d of %d vars set" (length values) (length vars))))))

(defun gascity-sling--footer (scope roster recipe)
  "Return the live footer line(s) of the sling menu for SCOPE.
`✓ Ready — <shape> · target <name> (<scope>) · <vars>' when every
client-side check is clean (mockup §1/§3/§4), or one `⚠ <reason>'
line per warning — §5c stacks its three, in the order below.  Pure
over cached data, never a gc read (D9): ROSTER is the WI-2 roster
the render path peeks from the store (`gascity-sling--roster-cached'),
RECIPE the picked formula's cached recipe (nil without a formula),
the live infix values `gascity-sling-formula--current-values'.

The WI-2 validators decide and their builders word (REQ-010); this
function composes them, target-first: the bl-bdj trap (§5a, a v2
formula whose binding-qualified step targets need a rig-scoped agent),
the cross-store route (§5b, work bead and target in different stores,
the rig memo `gascity-rigs-cached' resolving the prefix), then §5c's
missing pieces — missing work for a drain formula, missing required
vars, missing target.  Each degrades silently when its input is cold
(free entry, a cold roster or memo): a cold roster never dead-ends,
gc answers at launch.  Warnings never block `s'."
  (let* ((work (or (plist-get scope :work) (plist-get scope :arg)))
         ;; What `s' would launch: the set target wins, the Who
         ;; default (WI-3) answers next — a derivation is a target for
         ;; every check here, not only for the header sentence (the
         ;; WI-11 bright-lights pass: a derived rig-scoped target on a
         ;; city bead was refused by gc at launch while the footer
         ;; stayed silent about the cross-store route).
         (target (or (plist-get scope :target)
                     (plist-get (gascity-sling--derived-target scope) :target)))
         (target-scope (and target (gascity-agents-roster-scope target roster)))
         (rigs (gascity-rigs-cached (gascity-sling--city-dir scope)))
         (values (gascity-sling-formula--current-values))
         (warnings
          (delq nil
                (list
                 ;; §5a — a city target on a v2 formula.
                 (when (gascity-sling--v2-trap-p recipe target-scope)
                   (gascity-sling--v2-trap-warning
                    (gascity-sling--footer-rig roster)))
                 ;; §5b — the work bead and a rig-scoped target read
                 ;; different stores.
                 (when (gascity-sling--cross-store-p work target-scope rigs)
                   (gascity-sling--cross-store-warning work target-scope rigs))
                 ;; §5c — the missing pieces, in mockup order.
                 (when (gascity-sling--missing-work-p recipe work)
                   (gascity-sling--missing-work-warning recipe))
                 (gascity-sling--missing-vars-warning
                  (gascity-sling--missing-required-vars recipe values))
                 (when (gascity-sling--missing-target-p target)
                   gascity-sling--missing-target-warning)))))
    (if warnings
        (mapconcat (lambda (w) (concat "⚠ " w)) warnings "\n")
      (format "✓ Ready — %s · target %s · %s"
              (pcase (gascity-sling--shape work (plist-get scope :formula))
                ('plain "plain route")
                ('formula "formula run")
                ('on "on run")
                (_ "run"))
              (gascity-sling--footer--target-word target target-scope)
              (gascity-sling--footer--vars-word recipe values)))))


(defun gascity-sling--roster-cached (&optional city)
  "Return CITY's agent roster from the store's cache, or nil when cold.
The Who surface's one list for input-gathering paths (review R3/S1):
peeks the store's entries — `gc status', `gc session list', `gc agent
list' — and joins them with WI-2's single builder
`gascity-agents--roster'; the Who picker and the footer answer from
this list, and `gascity-store-peek' schedules background refreshes
when stale (§8.5): never blocking, never a synchronous gc (D9).  The
render path's derivation answers from its own config-only snapshot
(`gascity-sling--roster') — pool instances never name configs.  The
work-bead read
stays out: the Who surface classifies targets, it does not link
beads.  A cold store degrades to a nil roster: the scope-dependent
checks stay silent, free entry keeps working and the Who picker falls
back to the blocking accessor.
CITY defaults to the live scope's pin (`gascity-sling--city-dir')."
  (let ((dir (or city (gascity-sling--city-dir))))
    (gascity-agents--roster
     (list :status (gascity-store-peek '("status") dir)
           :sessions (gascity-store-peek '("session" "list") dir)
           :agents (gascity-store-peek '("agent" "list") dir)))))

(defun gascity-sling--footer-info (scope recipe)
  "Return the `(:info …)' spec rendering the live footer for SCOPE.
REQ-007: the footer renders as part of every transient setup, and
its description is a FUNCTION — transient evaluates it at format
time, on every setup AND every redraw — so it recomputes as each
answer changes: a var infix edit redraws the menu and the count
follows without a re-setup (mockup §1 note).  SCOPE and RECIPE are
captured here — a re-pick re-setups and re-creates the closure with
fresh ones — while the roster and the live values are read at format
time, all cached, no gc on the render path (D9).  Like
`gascity-sling--scope-info' the spec is passed unwrapped and must not
be a group's first element (a leading `(:info …)' parses as a group
argument and breaks setup)."
  (list :info
        (lambda ()
          (gascity-sling--footer
           scope
           (gascity-sling--roster-cached (plist-get scope :city))
           recipe))))

(defun gascity-sling--children-specs (scope)
  "Return the raw stacked layout specs for SCOPE (REQ-A, mockup §1–§4).
The staged mockup layout: sibling groups — no `transient-columns'
anywhere, so each renders full width and stacks vertically — the
header group (city title, the one-sentence shape header and the live
footer, WI-6), What (`A' the work picker, `f' the formula picker),
the picked formula's full-width `How — <formula> vars' group (absent
until a formula with vars is picked, REQ-A/REQ-B), Who (`T' the
target), the Routing flags — rendered only on the settled plain
shape, work chosen and no formula, the only path that consumes them
\(F-5) — and Actions (`s P r g x q', mockup §10).  The generated
infix keys avoid `gascity-sling--reserved-keys' (REQ-D).  The recipe
read and the header's city name run pinned to the scope's `:city'
\(`gascity-sling--city-dir'): transient can run setup with the menu
buffer current, whose directory must not key the recipe cache nor name
the header (ga-4ia4)."
  (let* ((default-directory (gascity-sling--city-dir scope))
         (formula (plist-get scope :formula))
         (work (gascity-sling--work scope))
         (recipe (and formula
                      (gascity-formula-recipe-cached
                       (plist-get scope :formula)))))
    (append
     (list
      (vector (format "Sling — %s" (gascity-context-city-name))
              (gascity-sling--scope-info scope recipe)
              (gascity-sling--footer-info scope recipe))
      ;; The What stage (mockup §2): the work picker on `A' and the
      ;; formula picker on `f'.
      (vector "What"
              '("A" "Work (bead/convoy or text; C-u freeform)…"
                gascity-sling-dispatch-work)
              '("f" "Formula…" gascity-sling-dispatch-pick)))
     ;; The picked formula's full-width How group (mockup §4), between
     ;; What and Who; absent until a formula with vars is picked
     ;; (REQ-A/REQ-B).
     (when-let* ((group (gascity-sling-formula--var-children
                         recipe gascity-sling--reserved-keys scope)))
       (list group))
     (list
      ;; The Who stage (mockup §1): one target line.
      (vector "Who"
              '("T" "Target agent…" gascity-sling-dispatch-target)))
     ;; Routing flags render only on the settled plain shape — work
     ;; chosen, no formula — the only path that consumes them (F-5,
     ;; mockup §1 vs §2).
     (when (and (gascity-formula--nonblank work) (not formula))
       (list
        (vector "Routing flags"
                '("-c" "Skip auto-convoy" "--no-convoy")
                '("-a" "Reassign (clear human assignee)" "--reassign")
                '("-n" "Nudge target after routing" "--nudge")
                '("-m" "Merge strategy" "--merge=" :choices ("direct" "mr" "local"))
                '("-t" "Wisp root title" "--title="))))
     (list
      (vector "Actions"
              '("s" "Sling…" gascity-sling-dispatch-run)
              '("P" "Full preview…" gascity-sling-dispatch-full-preview)
              '("r" "Preview recipe…" gascity-sling-dispatch-recipe)
              '("g" "Refresh catalog" gascity-sling-dispatch-refresh)
              '("x" "Reset (clear work, formula, target)" gascity-sling-dispatch-reset)
              '("q" "Quit" transient-quit-one))))))

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
      (gascity-sling--resetup
       (plist-put (copy-sequence (transient-scope)) :formula name)))))

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
       ;; A process callback: rebuild from a timer (one TRAMP's timer
       ;; suspension cannot lose), and only while the menu is still the
       ;; active transient.
       (gascity-timer-at
        0
        (lambda ()
          (when-let* ((prefix (transient-active-prefix 'gascity-sling-dispatch)))
            (condition-case nil
                (transient-setup 'gascity-sling-dispatch nil nil
                                 :scope (oref prefix scope)
                                 :value (transient-args 'gascity-sling-dispatch))
              (error nil)))
          (message "Formulas refreshed")))))))

(transient-define-suffix gascity-sling-dispatch-work (&optional freeform)
  "Read the work — the smart picker (mockup §6a) — and show it in the
header.  A completing-read over the city's open/in-progress/blocked
beads and its convoys, each row annotated `title · status · store'
\(`gascity-sling--work-choices-wait'); an empty RET falls through to
the freeform `Bead id or task text' prompt, and `C-u' goes straight
to freeform.  The answer lives in the scope's `:work' — the slot the
derivation, the header sentence and the dispatch read (`:arg' is the
legacy name, still read) — so it survives a formula re-pick; set var
values carry across the re-setup like re-pick/refresh.  The plain
path keeps its own picker fallback — this is purely scope editing,
not dispatch."
  :transient t
  (interactive "P")
  (let ((default-directory (gascity-sling--city-dir)))
    (let* ((picked (and (not freeform)
                        (condition-case nil
                            (completing-read
                             "Work (bead or convoy; RET-empty or C-u for freeform text): "
                             (gascity-sling--work-choices-wait)
                             nil nil (gascity-sling--work (transient-scope)))
                          (error nil))))
           (work (if (and picked (not (string-empty-p picked)))
                     picked
                   (read-string "Bead id or task text: "
                                (plist-get (transient-scope) :work)))))
      (gascity-sling--resetup
       (plist-put (copy-sequence (transient-scope)) :work work)))))

(defun gascity-sling--read-work (&optional initial)
  "Read the What answer at dispatch (mockup §6a): the work picker.
A completing-read over the city's open beads and convoys — the same
smart picker `A' edits the scope with; an empty pick falls through to
the freeform `Bead id or task text' prompt, seeded from the bead at
point or INITIAL.  A cold choices read degrades to the freeform
prompt (never a dead end); the dispatch is input collection (D9)."
  (let* ((choices (condition-case nil
                     (gascity-sling--work-choices-wait)
                   (error nil)))
         (picked (completing-read
                  "Work (bead or convoy; RET-empty or C-u for freeform text): "
                  choices nil nil initial)))
    (if (and picked (not (string-empty-p picked)))
        picked
      (read-string "Bead id or task text: " (gascity-bead-at-point)))))

(transient-define-suffix gascity-sling-dispatch-target ()
  "Read the sling target — completion over the agent roster (§6c).
Agents, not sessions: city agents first then per rig, each candidate
annotated with its scope and live state (`gascity-agents-roster-
candidates', WI-2's accessor — the same joined roster the footer and
the derivation answer from).  The derived Who default seeds the read —
RET keeps it — so a derivable target costs no typing; free entry
still works (a cold roster is never a dead end, REQ-005).  The set
target wins at dispatch.  The read is synchronous but strictly
user-initiated — it runs only on this binding press (OQ-1, F-4)."
  :transient t
  (interactive)
  (let ((default-directory (gascity-sling--city-dir)))
    (let* ((roster (or (gascity-sling--roster-cached)
                       (gascity-agents-roster 'cached)))
           (target (gascity-sling--read-agent
                    "Target agent: "
                    (plist-get (gascity-sling--derived-target) :target)
                    roster)))
      (gascity-sling--resetup
       (plist-put (copy-sequence (transient-scope)) :target target)))))

(defun gascity-sling--read-agent (prompt &optional initial roster)
  "Read the Who answer with PROMPT over the agent roster (mockup §6c).
The candidates annotate scope and live state
\(`gascity-agents-roster-candidates'); INITIAL — the derived Who
default, when one derives — seeds the read and RET keeps it; free
entry (require-match nil) uses a typed name verbatim, and a cold
roster (ROSTER nil) completes over nothing, never a dead end.
When ROSTER is nil the blocking accessor answers (input collection,
D9)."
  (completing-read
   prompt
   (gascity-agents-roster-candidates
    (or roster (gascity-agents-roster 'cached)))
   nil nil initial))

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
  (let* ((at-point (gascity-sling-formula--bead-or-convoy-at-point))
         (at-point-title (and at-point
                              (gascity-sling-formula--work-title-at-point)))
         (saved (cdr (assoc default-directory gascity-sling--remembered)))
         ;; The city's last menu state (after a preview, say) comes
         ;; back; a bead or convoy at point still names the work — and
         ;; its title seeds the artifact_root convention default
         ;; (REQ-006, `gascity-sling-formula--var-seed').
         (scope (if saved
                    (let ((scope (copy-sequence (car saved))))
                      (when at-point
                        (setq scope (plist-put scope :work at-point)))
                      (when at-point-title
                        (setq scope (plist-put scope :work-title at-point-title)))
                      scope)
                  (list :city default-directory
                        :formula nil :target nil :work at-point
                        :work-title at-point-title))))
    ;; Warm the formula caches (catalog + `gc formula list') through the
    ;; store so `-f' answers from memory (bug S-1, D9), and `gc agent
    ;; list' the same way — the derived Who default's convention rule
    ;; (WI-3) reads it from the store's cache, so a cold session
    ;; requests the entry once, here (async, TTL-gated; a warm entry
    ;; is free).  The work picker's composite read (the `A'
    ;; candidates, WI-4) warms the same way.
    (let ((default-directory (plist-get scope :city)))
      (ignore-errors (gascity-formula-refresh-async nil #'ignore 'cached))
      (ignore-errors (gascity-store-request '("agent" "list")))
      (ignore-errors (gascity-store-request
                      gascity-sling--work-choices-key
                      :loader #'gascity-sling--read-work-choices)))
    (transient-setup 'gascity-sling-dispatch nil nil
                     :scope scope :value (cdr saved))))

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

(provide 'gascity-action)
;;; gascity-action.el ends here
