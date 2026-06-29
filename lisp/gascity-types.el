;;; gascity-types.el --- Concrete gc command classes -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Concrete `gascity-command' classes for the read-only `gc' surface the
;; porcelain renders: the city `status' (in `gascity-command-status'),
;; the homogeneous lists (rigs, sessions, convoys, mail, orders), and
;; Dolt health.  Each is defined with `gascity-defcommand', which also
;; generates a NAME! convenience function returning the parsed payload.
;;
;; These classes are the *execution + parse* layer only: they run a `gc'
;; subcommand and decode its `--json' output.  The porcelain itself (the
;; status dashboard and the tabulated lists) is hand-built in
;; `gascity-status' and `gascity-tabulated' in the deliberate
;; magit/forge style — it does not auto-generate its UI from these
;; classes.  Transient menus, when they arrive, are a command-dispatch
;; backend, not the primary interface.
;;
;; The subcommand is derived from each class name by
;; `gascity-command-subcommand' (`gascity-command-rig-list' -> "rig
;; list"); `--json' is emitted by default (see
;; `gascity-command-global-options').  Each list class also declares its
;; filter slots here.  `gc' list subcommands expose almost no filter
;; flags, so most filters are client-side: the slots carry no
;; `:long-option', never reach the command line, and `gascity-tabulated'
;; reads them to filter the decoded rows.  The session `state' slot is
;; the lone server-side exception (`gc session list --state').  The
;; per-view `gascity-command-execute-interactive' methods that open
;; buffers are added by the view modules.

;;; Code:

(require 'gascity-command)

;;; Rigs

(gascity-defcommand gascity-command-rig-list (gascity-command-global-options)
  ((status
    :initarg :status
    :initform nil
    :documentation "Client-side status filter: \"running\", \"suspended\",
or \"stopped\".  Carries no `:long-option' (`gc rig list' has no status
flag), so it never reaches the command line; `gascity-rig-list-refresh'
reads it to filter the decoded rows."))
  :documentation "List the rigs registered in the city.
Payload: an alist with a `rigs' vector and a `summary'.")

;;; Sessions

(gascity-defcommand gascity-command-session-list (gascity-command-global-options)
  ((state
    :initarg :state
    :initform nil
    :long-option "state"
    :option-type :string
    :documentation "Server-side `--state' filter: \"active\", \"suspended\",
\"closed\", or \"all\".  `gc session list' supports this flag, so it is
emitted on the command line when set.")
   (rig
    :initarg :rig
    :initform nil
    :documentation "Client-side rig filter (case-insensitive substring on
the decoded `rig').  Carries no `:long-option': `gc''s global `--rig'
selects a rig context, not a session filter, so this is applied to the
decoded rows instead."))
  :documentation "List the city's agent sessions.
Payload: an alist with a `sessions' vector and a `summary'.  Each
session carries `work_dir' (its worktree, for Dired) and `session_name'
\(its tmux target, for attach).")

;;; Convoys

(gascity-defcommand gascity-command-convoy-list (gascity-command-global-options)
  ((status
    :initarg :status
    :initform nil
    :documentation "Client-side status filter.  Carries no `:long-option'
(`gc convoy list' has no status flag); `gascity-convoy-list-refresh'
reads it to filter the decoded rows."))
  :documentation "List the city's convoys.
Payload: an alist with a `convoys' vector and a `summary'.")

;;; Mail

(gascity-defcommand gascity-command-mail-inbox (gascity-command-global-options)
  ((unread
    :initarg :unread
    :initform nil
    :documentation "Client-side unread-only filter.  Carries no
`:long-option'; `gascity-mail-inbox-refresh' reads it to keep only
unread messages among the decoded rows."))
  :documentation "Show the current agent's mail inbox.
Payload: an alist with a `messages' vector plus `recipient'.")

;;; Orders

(gascity-defcommand gascity-command-order-list (gascity-command-global-options)
  ((enabled
    :initarg :enabled
    :initform nil
    :documentation "Client-side enabled-only filter.  Carries no
`:long-option'; `gascity-order-list-refresh' reads it to keep only
enabled orders.")
   (type
    :initarg :type
    :initform nil
    :documentation "Client-side type filter (exact match on the decoded
`type').  Carries no `:long-option'."))
  :documentation "List the city's orders (scheduled/cooldown jobs).
Payload: an alist with an `orders' vector and a `summary'.")

;;; Dolt

(gascity-defcommand gascity-command-dolt-health (gascity-command-global-options)
  ()
  :documentation "Report Dolt server health and per-database stats.
Payload: an alist with `server', a `databases' vector, and more.  Used
in place of `gc dolt list', which does not support `--json'.")

;;; Session output (read-only)

(gascity-defcommand gascity-command-session-peek (gascity-command-global-options)
  ((target
    :initarg :target :type string :initform "" :positional 1
    :documentation "Session id or alias to peek at.")
   (lines
    :initarg :lines :type string :initform "50"
    :long-option "lines" :option-type :string
    :documentation "How many trailing output lines `gc' should capture.")
   (json
    :initarg :json :type boolean :initform nil
    :long-option "json" :option-type :boolean
    :documentation "Off: capture the human-readable text snapshot (not JSONL),
which the detail view renders verbatim in a read-only buffer."))
  :documentation "View a session's recent output without attaching.
Read-only.  The polecat/session detail view's `peek' action runs this
and shows the captured text in a view buffer.")

;;; ============================================================
;;; Mutating commands (P1 — command dispatch)
;;; ============================================================
;;
;; Write/mutate `gc' subcommands, modelled like the read-only classes
;; above: slot metadata declares positional arguments (`:positional N',
;; emitted first in order) and option flags, and `gascity-command-line'
;; builds the line.  Quick mutations inherit from `gascity-command-action',
;; whose interactive execution (in `gascity-action') runs synchronously
;; and reports the outcome; the long-running lifecycle commands
;; (`start'/`stop') inherit from `gascity-command-global-options' and
;; stream via the base `async-shell-command' backend.
;;
;; Required positional arguments are enforced by `gascity-command-validate'
;; so a missing target fails locally with a clear message rather than a
;; confusing `gc' usage error.

;;; Rig control

(gascity-defcommand gascity-command-rig-suspend (gascity-command-action)
  ((name :initarg :name :type string :initform "" :positional 1
         :documentation "Rig to suspend; empty means the contextual rig."))
  :documentation "Suspend a rig (the reconciler then skips its agents).")

(gascity-defcommand gascity-command-rig-resume (gascity-command-action)
  ((name :initarg :name :type string :initform "" :positional 1
         :documentation "Rig to resume; empty means the contextual rig."))
  :documentation "Resume a suspended rig.")

(gascity-defcommand gascity-command-rig-restart (gascity-command-action)
  ((name :initarg :name :type string :initform "" :positional 1
         :documentation "Rig whose agent sessions to kill (reconciler restarts)."))
  ;; `gc rig restart' has no --json flag at all; the action base already
  ;; defaults --json off, so nothing extra is needed here.
  :documentation "Restart a rig by killing its agent sessions.")

;;; Session control

(gascity-defcommand gascity-command-session-nudge (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias (e.g. a qualified agent name).")
   (message :initarg :message :type string :initform "" :positional 2
            :documentation "Message text; `gc' joins multi-word input."))
  :documentation "Send a text message to a running session.")

(gascity-defcommand gascity-command-session-suspend (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias to suspend."))
  :documentation "Suspend a session (stop its runtime; the bead persists).")

(gascity-defcommand gascity-command-session-kill (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias to force-kill."))
  :documentation "Force-kill a session's runtime (the reconciler restarts it).")

(gascity-defcommand gascity-command-session-wake (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias to wake."))
  :documentation "Wake a session and clear holds.")

(gascity-defcommand gascity-command-runtime-drain (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias to signal to drain."))
  :documentation "Signal a session to drain — wind down its work gracefully.
Sets a drain flag; the agent finishes its current task, then exits.  Cancel
with `gc runtime undrain'.  Distinct from suspend (stops the runtime now) and
kill (force-kills the runtime).")

(gascity-defcommand gascity-command-runtime-undrain (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias whose drain flag to clear."))
  :documentation "Clear a session's drain flag — the inverse of `runtime drain'.
The reconciler stops winding the agent down; it resumes taking work.")

(gascity-defcommand gascity-command-session-reset (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias to restart fresh."))
  :documentation "Restart a session fresh while preserving its bead.
Distinct from `session kill' (force-kill; the reconciler restarts) and
`rig restart' (kills a rig's whole agent set).")

;;; Dispatch

(gascity-defcommand gascity-command-sling (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Target agent qualified name.")
   (arg :initarg :arg :type string :initform "" :positional 2
        :documentation "Bead id, formula name (with --formula), or task text.")
   (formula :initarg :formula :type boolean :initform nil
            :long-option "formula" :option-type :boolean
            :documentation "Treat ARG as a formula name.")
   (nudge :initarg :nudge :type boolean :initform nil
          :long-option "nudge" :option-type :boolean
          :documentation "Nudge the target after routing.")
   (no-convoy :initarg :no-convoy :type boolean :initform nil
              :long-option "no-convoy" :option-type :boolean
              :documentation "Skip auto-convoy creation.")
   (reassign :initarg :reassign :type boolean :initform nil
             :long-option "reassign" :option-type :boolean
             :documentation "Clear any existing human assignee before routing
\(human->pool handoff).")
   (merge :initarg :merge :initform nil
          :long-option "merge" :option-type :string
          :documentation "Merge strategy: \"direct\", \"mr\", or \"local\".")
   (title :initarg :title :initform nil
          :long-option "title" :option-type :string
          :documentation "Wisp root bead title (with --formula).")
   (var :initarg :var :initform nil
        :long-option "var" :option-type :list
        :documentation "Formula variable substitutions, each a \"key=value\"
string.  Emitted as a repeated `--var' (gc's stringArray flag).")
   (dry-run :initarg :dry-run :type boolean :initform nil
            :long-option "dry-run" :option-type :boolean
            :documentation "Show what would be done without executing."))
  :documentation "Route a bead (or task text/formula) to a session or agent.
The flag-heavy verb, so it backs the `gascity-sling-dispatch' transient;
`--dry-run' doubles as the preview affordance.")

;;; Orders

(gascity-defcommand gascity-command-order-run (gascity-command-action)
  ((name :initarg :name :type string :initform "" :positional 1
         :documentation "Order to execute manually.")
   (rig :initarg :rig :initform nil
        :long-option "rig" :option-type :string
        :documentation "Rig name to disambiguate same-name orders across rigs."))
  :documentation "Execute an order manually, bypassing its trigger conditions.")

;;; Bead writes (gc bd …) — store-routed via `-C' (gascity-command-bd-action)

(gascity-defcommand gascity-command-bd-note (gascity-command-bd-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Bead id to append a note to.")
   (text :initarg :text :type string :initform "" :positional 2
         :documentation "Note text; gc joins multi-word input.  The note is
appended to the bead's discussion, never overwriting prior notes."))
  :documentation "Append a note to a bead (`gc bd note <id> <text>').
Inherits the `-C' store-routing slot from `gascity-command-bd-action'; the
caller resolves it from ID's prefix with `gascity-beads--bead-path'.")

(gascity-defcommand gascity-command-bd-close (gascity-command-bd-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Bead id to close.")
   (reason :initarg :reason :initform nil
           :long-option "reason" :option-type :string
           :documentation "Optional reason recorded on the close event (`-r')."))
  :documentation "Close a bead (`gc bd close <id> -r <reason>').
Store-routed by `-C' (inherited).  The porcelain confirms before running.")

(gascity-defcommand gascity-command-bd-reopen (gascity-command-bd-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Bead id to reopen."))
  :documentation "Reopen a closed bead (`gc bd reopen <id>') — clears
`closed_at' and emits a Reopened event.  Store-routed by `-C' (inherited).")

(gascity-defcommand gascity-command-bd-assign (gascity-command-bd-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Bead id to assign.")
   (name :initarg :name :type string :initform "" :positional 2
         :documentation "Assignee (agent qualified name, refinery, or human)."))
  :documentation "Assign a bead to an agent or human (`gc bd assign <id> <name>').
Store-routed by `-C' (inherited).")

;;; City config

(gascity-defcommand gascity-command-reload (gascity-command-action)
  ((soft :initarg :soft :type boolean :initform nil
         :long-option "soft" :option-type :boolean
         :documentation "Absorb config drift on open sessions instead of
draining them."))
  :documentation "Re-read effective config and process one reload tick
\(`gc reload').  City-level (gc has no `rig reload').  With `--soft' it
absorbs drift on open sessions rather than draining them.")

;;; Mail actions (gc mail …)

(gascity-defcommand gascity-command-mail-read (gascity-command-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Message id to read.  `gc mail read' also marks it read."))
  :documentation "Read a message and mark it read (`gc mail read <id>').
\(--json off: the captured human-readable body is shown verbatim.)")

(gascity-defcommand gascity-command-mail-archive (gascity-command-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Message id to archive (close its message bead)."))
  :documentation "Archive a message without reading it (`gc mail archive <id>').")

(gascity-defcommand gascity-command-mail-mark-read (gascity-command-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Message id to mark read."))
  ;; `mail-mark-read' has an internal hyphen the class-name->subcommand
  ;; derivation would split into "mail mark read"; pin the real token.
  :cli-command "mail mark-read"
  :documentation "Mark a message read without opening it (`gc mail mark-read <id>').")

(gascity-defcommand gascity-command-mail-mark-unread (gascity-command-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Message id to mark unread."))
  :cli-command "mail mark-unread"
  :documentation "Mark a message unread (`gc mail mark-unread <id>').")

(gascity-defcommand gascity-command-mail-send (gascity-command-action)
  ((to :initarg :to :type string :initform "" :positional 1
       :documentation "Recipient address (session alias, mayor/, human, …).")
   (subject :initarg :subject :initform nil
            :long-option "subject" :option-type :string
            :documentation "Message subject line (`-s'/`--subject').")
   (message :initarg :message :initform nil
            :long-option "message" :option-type :string
            :documentation "Message body text (`-m'/`--message'); from the
compose buffer.")
   (json :initarg :json :type boolean :initform t
         :long-option "json" :option-type :boolean
         :documentation "On: the JSON result carries the new message, which
`gascity-action--summarize' renders as \"sent\"."))
  :documentation "Send a message to a session alias or human
\(`gc mail send <to> -s … -m …').  Body-bearing, so it is driven from the
compose buffer (`gascity-compose').")

(gascity-defcommand gascity-command-mail-reply (gascity-command-action)
  ((id :initarg :id :type string :initform "" :positional 1
       :documentation "Message id to reply to; the reply goes to its sender.")
   (subject :initarg :subject :initform nil
            :long-option "subject" :option-type :string
            :documentation "Reply subject line (`-s'/`--subject').")
   (message :initarg :message :initform nil
            :long-option "message" :option-type :string
            :documentation "Reply body text (`-m'/`--message'); from the
compose buffer.")
   (json :initarg :json :type boolean :initform t
         :long-option "json" :option-type :boolean
         :documentation "On: the JSON result carries the reply, which
`gascity-action--summarize' renders as \"sent\"."))
  :documentation "Reply to a message, addressed to its original sender
\(`gc mail reply <id> -s … -m …').  Body-bearing, driven from the compose
buffer (`gascity-compose').")

;;; City lifecycle (streaming; not `gascity-command-action')

(gascity-defcommand gascity-command-start (gascity-command-global-options)
  ((json :initarg :json :type boolean :initform nil
         :long-option "json" :option-type :boolean
         :documentation "Off: lifecycle output streams to a buffer."))
  :documentation "Start the city under the machine-wide supervisor.")

(gascity-defcommand gascity-command-stop (gascity-command-global-options)
  ((force :initarg :force :type boolean :initform nil
          :long-option "force" :option-type :boolean
          :documentation "Skip the interrupt grace period; force-kill sessions.")
   (json :initarg :json :type boolean :initform nil
         :long-option "json" :option-type :boolean
         :documentation "Off: lifecycle output streams to a buffer."))
  :documentation "Stop all agent sessions in the city (graceful shutdown).")

;;; Validation — required positional arguments

(cl-defmethod gascity-command-validate ((command gascity-command-session-nudge))
  "Require a session target and a message."
  (cond ((gascity-command--blank-p command 'target) "a session target is required")
        ((gascity-command--blank-p command 'message) "a message is required")))

(cl-defmethod gascity-command-validate ((command gascity-command-session-suspend))
  "Require a session target."
  (and (gascity-command--blank-p command 'target) "a session target is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-session-kill))
  "Require a session target."
  (and (gascity-command--blank-p command 'target) "a session target is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-session-wake))
  "Require a session target."
  (and (gascity-command--blank-p command 'target) "a session target is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-sling))
  "Require both a target and a bead/text argument."
  (cond ((gascity-command--blank-p command 'target) "a sling target is required")
        ((gascity-command--blank-p command 'arg) "a bead id or task text is required")))

(cl-defmethod gascity-command-validate ((command gascity-command-order-run))
  "Require an order name."
  (and (gascity-command--blank-p command 'name) "an order name is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-session-peek))
  "Require a session target."
  (and (gascity-command--blank-p command 'target) "a session target is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-runtime-drain))
  "Require a session target."
  (and (gascity-command--blank-p command 'target) "a session target is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-runtime-undrain))
  "Require a session target."
  (and (gascity-command--blank-p command 'target) "a session target is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-session-reset))
  "Require a session target."
  (and (gascity-command--blank-p command 'target) "a session target is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-bd-note))
  "Require a bead id and note text."
  (cond ((gascity-command--blank-p command 'id) "a bead id is required")
        ((gascity-command--blank-p command 'text) "note text is required")))

(cl-defmethod gascity-command-validate ((command gascity-command-mail-read))
  "Require a message id."
  (and (gascity-command--blank-p command 'id) "a message id is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-mail-archive))
  "Require a message id."
  (and (gascity-command--blank-p command 'id) "a message id is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-mail-mark-read))
  "Require a message id."
  (and (gascity-command--blank-p command 'id) "a message id is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-mail-mark-unread))
  "Require a message id."
  (and (gascity-command--blank-p command 'id) "a message id is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-bd-close))
  "Require a bead id (the reason is optional)."
  (and (gascity-command--blank-p command 'id) "a bead id is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-bd-reopen))
  "Require a bead id."
  (and (gascity-command--blank-p command 'id) "a bead id is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-bd-assign))
  "Require a bead id and an assignee name."
  (cond ((gascity-command--blank-p command 'id) "a bead id is required")
        ((gascity-command--blank-p command 'name) "an assignee is required")))

(cl-defmethod gascity-command-validate ((command gascity-command-mail-send))
  "Require a recipient (subject/body come from the compose buffer)."
  (and (gascity-command--blank-p command 'to) "a recipient is required"))

(cl-defmethod gascity-command-validate ((command gascity-command-mail-reply))
  "Require the id of the message being replied to."
  (and (gascity-command--blank-p command 'id) "a message id is required"))

(provide 'gascity-types)
;;; gascity-types.el ends here
