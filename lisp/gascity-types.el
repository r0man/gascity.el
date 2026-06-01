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

(provide 'gascity-types)
;;; gascity-types.el ends here
