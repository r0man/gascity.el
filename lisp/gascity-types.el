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
   (dry-run :initarg :dry-run :type boolean :initform nil
            :long-option "dry-run" :option-type :boolean
            :documentation "Show what would be done without executing."))
  :documentation "Route a bead (or task text/formula) to a session or agent.")

;;; Orders

(gascity-defcommand gascity-command-order-run (gascity-command-action)
  ((name :initarg :name :type string :initform "" :positional 1
         :documentation "Order to execute manually."))
  :documentation "Execute an order manually, bypassing its trigger conditions.")

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

(provide 'gascity-types)
;;; gascity-types.el ends here
