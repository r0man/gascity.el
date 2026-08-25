;;; gascity-domain.el --- Typed domain objects for gc read payloads -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Typed EIEIO domain objects for the read-only `gc … --json' payloads the
;; porcelain renders: rigs, sessions, agents, convoys, mail messages, and
;; orders (plan §3.1 / §1G).  Before this module the views threaded raw
;; `alist'/`plist' values through every row mapper and at-point handler,
;; re-typing the same JSON keys at each call site (`(alist-get 'work_dir s)`,
;; `(plist-get agent :name)`, …).  Here each entity is a class whose slots
;; carry the JSON contract as metadata — `:json-key' names the `gc' field and
;; `:type' coerces it — so a payload is decoded once into a typed object and
;; read everywhere through named accessors.
;;
;; Decoding reuses beads.el's library-neutral reflective decoder
;; `beads-from-json' (beads-meta.el): it walks a class's slot metadata, maps
;; each `:json-key' to the slot initarg, coerces by `:type', and recurses into
;; nested EIEIO classes (so a convoy's `progress' becomes a `gascity-progress').
;; Nothing in that decoder is beads-specific.  `require'ing `beads-meta' also
;; installs the advice that preserves `:json-key' on the slot descriptors, so
;; the classes below must be defined after it loads.
;;
;; A note on booleans: gascity's JSON reader decodes both `false' and `null'
;; to nil (`gascity-reader-parse-json'), unlike beads.el which keeps a
;; `:json-false' sentinel.  So boolean slots are typed `(or null boolean)',
;; never bare `boolean': the nullable wrapper short-circuits a nil value
;; through unchanged, whereas the bare-boolean coercion `(not (eq v :json-false))'
;; would turn gascity's nil (a decoded `false') into t.
;;
;; `gascity-agent' is the one synthesized type.  An "agent" as the views act
;; on it (open its worktree, attach its tmux) is not a single `gc' payload: it
;; merges a `gc session list' row (worktree, tmux name) with, on the
;; dashboards, a `gc status' agent entry (running state) plus the resolved tmux
;; socket.  So it is assembled by builders (`gascity-agent-from-session' and
;; the status board's join) rather than decoded directly; its slots still
;; carry the contract so the type is uniform with the rest.
;;
;; The "object at point" is one of these typed instances (or a bead-id string,
;; whose detail view belongs to beads.el).  `gascity-at-point-visit' is the
;; generic that dispatches the default drill-in action on it, one method per
;; class — replacing the per-payload-kind `cond' the views used to carry.  The
;; methods themselves live with the actions they invoke (in `gascity-section',
;; `gascity-tabulated', `gascity-rig'); here we declare the contract and a
;; default that reports an unhandled object.

;;; Code:

(require 'cl-lib)
(require 'eieio)
;; `beads-from-json' (the reflective JSON->object decoder) and the advice that
;; preserves the `:json-key' slot property the classes below rely on.
(require 'beads-meta)

;;; ============================================================
;;; Classes
;;; ============================================================
;;
;; One class per read payload.  Every slot declares `:initarg' (so
;; `beads-from-json'/`make-instance' can set it), `:initform nil' (so an
;; absent JSON key leaves the accessor returning nil rather than unbound),
;; `:type' (the coercion contract), `:json-key' (the `gc' field name — stated
;; explicitly even when it matches the default slot->underscore mapping, so
;; the shape of `gc' output is documented at the slot), and `:accessor'.

;;; Rig — `gc rig list' -> `rigs' vector

(defclass gascity-rig ()
  ((name
    :initarg :name :initform nil :type (or null string) :json-key name
    :accessor gascity-rig-name
    :documentation "Rig name, e.g. \"gascity.el\".")
   (prefix
    :initarg :prefix :initform nil :type (or null string) :json-key prefix
    :accessor gascity-rig-prefix
    :documentation "Bead-id store prefix, e.g. \"gce\".")
   (path
    :initarg :path :initform nil :type (or null string) :json-key path
    :accessor gascity-rig-path
    :documentation "Absolute repo path (the directory holding `.beads/').")
   (default-branch
    :initarg :default-branch :initform nil :type (or null string)
    :json-key default_branch :accessor gascity-rig-default-branch
    :documentation "The rig's default git branch.")
   (store
    :initarg :store :initform nil :type (or null string) :json-key beads
    :accessor gascity-rig-store
    :documentation "Bead-store status string (the `beads' field, e.g.
\"initialized\") — a status, never a count.  Named `store' so its accessor
does not collide with the `gascity-rig-beads' command.")
   (hq
    :initarg :hq :initform nil :type (or null boolean) :json-key hq
    :accessor gascity-rig-hq
    :documentation "Non-nil when this row is the city HQ, which `gc rig list'
includes for its beads even though it is not a `city.toml' rig.")
   (running
    :initarg :running :initform nil :type (or null boolean) :json-key running
    :accessor gascity-rig-running
    :documentation "Non-nil when the rig has running agents.")
   (suspended
    :initarg :suspended :initform nil :type (or null boolean) :json-key suspended
    :accessor gascity-rig-suspended
    :documentation "Non-nil when the rig is suspended."))
  :documentation "A rig as reported by `gc rig list'.")

;;; Session — `gc session list' -> `sessions' vector

(defclass gascity-session ()
  ((agent-name
    :initarg :agent-name :initform nil :type (or null string) :json-key agent_name
    :accessor gascity-session-agent-name
    :documentation "Qualified agent name — always set, the reliable join key.")
   (name
    :initarg :name :initform nil :type (or null string) :json-key name
    :accessor gascity-session-name
    :documentation "Display name; degrades to the raw tmux id for non-active
sessions, so `agent-name' is preferred (see `gascity-session-qualified-name').")
   (alias
    :initarg :alias :initform nil :type (or null string) :json-key alias
    :accessor gascity-session-alias
    :documentation "Optional session alias.")
   (rig
    :initarg :rig :initform nil :type (or null string) :json-key rig
    :accessor gascity-session-rig
    :documentation "The rig this session belongs to.")
   (template
    :initarg :template :initform nil :type (or null string) :json-key template
    :accessor gascity-session-template
    :documentation "Qualified name of the pool template this session was
spawned from, e.g. \"gascity.el/gastown.polecat\" for a polecat.  The join
key that nests a pool member under its template on the status board: a named
member's own name (\"gastown.furiosa\") carries no trace of its pool, and
`gc agent list' reports the templates without their members.")
   (state
    :initarg :state :initform nil :type (or null string) :json-key state
    :accessor gascity-session-state
    :documentation "Lifecycle state, e.g. \"active\", \"suspended\".")
   (provider
    :initarg :provider :initform nil :type (or null string) :json-key provider
    :accessor gascity-session-provider
    :documentation "Agent provider/model family, e.g. \"claude\".")
   (work-dir
    :initarg :work-dir :initform nil :type (or null string) :json-key work_dir
    :accessor gascity-session-work-dir
    :documentation "The session's worktree directory (for Dired).")
   (session-name
    :initarg :session-name :initform nil :type (or null string) :json-key session_name
    :accessor gascity-session-session-name
    :documentation "The tmux session target (for attach).")
   (attached
    :initarg :attached :initform nil :type (or null boolean) :json-key attached
    :accessor gascity-session-attached
    :documentation "Non-nil when a client is attached to the tmux session.")
   (last-active
    :initarg :last-active :initform nil :type (or null string) :json-key last_active
    :accessor gascity-session-last-active
    :documentation "ISO-8601 timestamp of last activity."))
  :documentation "An agent session as reported by `gc session list'.")

;;; Agent — the synthesized action object carried at point

(defclass gascity-agent ()
  ((name
    :initarg :name :initform nil :type (or null string) :json-key agent_name
    :accessor gascity-agent-name
    :documentation "Qualified agent name (the session's `agent_name', or a
status agent's `qualified_name').")
   (rig
    :initarg :rig :initform nil :type (or null string) :json-key rig
    :accessor gascity-agent-rig
    :documentation "The rig the agent belongs to.")
   (work-dir
    :initarg :work-dir :initform nil :type (or null string) :json-key work_dir
    :accessor gascity-agent-work-dir
    :documentation "The agent's worktree directory (for Dired).")
   (session-name
    :initarg :session-name :initform nil :type (or null string) :json-key session_name
    :accessor gascity-agent-session-name
    :documentation "The tmux session target (for attach).")
   (socket
    :initarg :socket :initform nil :type (or null string) :json-key socket
    :accessor gascity-agent-socket
    :documentation "The tmux -L socket (the city name); resolved per view, not
carried in `gc --json'.")
   (running
    :initarg :running :initform nil :type (or null boolean) :json-key running
    :accessor gascity-agent-running
    :documentation "Non-nil when the agent is running."))
  :documentation "An agent as the views act on it: open its worktree, attach
its tmux session, open its detail view.  Synthesized — it merges a
`gascity-session' (worktree, tmux name) with, on the dashboards, a `gc status'
agent entry (running) plus the resolved tmux socket — so it is built by
`gascity-agent-from-session' and the status board's join rather than decoded
from a single payload.")

;;; Convoy — `gc convoy list' -> `convoys' vector (with nested progress)

(defclass gascity-progress ()
  ((closed
    :initarg :closed :initform nil :type (or null integer) :json-key closed
    :accessor gascity-progress-closed
    :documentation "Count of closed/done child beads.")
   (total
    :initarg :total :initform nil :type (or null integer) :json-key total
    :accessor gascity-progress-total
    :documentation "Total count of child beads."))
  :documentation "A closed/total progress pair (a convoy's `progress' object).")

(defclass gascity-convoy ()
  ((id
    :initarg :id :initform nil :type (or null string) :json-key id
    :accessor gascity-convoy-id
    :documentation "The convoy's bead id (its store prefix routes `RET' to
beads.el).")
   (title
    :initarg :title :initform nil :type (or null string) :json-key title
    :accessor gascity-convoy-title
    :documentation "Convoy title.")
   (status
    :initarg :status :initform nil :type (or null string) :json-key status
    :accessor gascity-convoy-status
    :documentation "Convoy status, e.g. \"open\".")
   (progress
    :initarg :progress :initform nil :type (or null gascity-progress) :json-key progress
    :accessor gascity-convoy-progress
    :documentation "Nested closed/total progress, decoded into a
`gascity-progress'."))
  :documentation "A convoy as reported by `gc convoy list'.")

;;; Mail — `gc mail inbox' -> `messages' vector (v1 mail_message schema)

(defclass gascity-mail ()
  ((id
    :initarg :id :initform nil :type (or null string) :json-key id
    :accessor gascity-mail-id
    :documentation "Message id.")
   (from
    :initarg :from :initform nil :type (or null string) :json-key from
    :accessor gascity-mail-from
    :documentation "Sender address.")
   (to
    :initarg :to :initform nil :type (or null string) :json-key to
    :accessor gascity-mail-to
    :documentation "Recipient address.")
   (subject
    :initarg :subject :initform nil :type (or null string) :json-key subject
    :accessor gascity-mail-subject
    :documentation "Message subject.")
   (body
    :initarg :body :initform nil :type (or null string) :json-key body
    :accessor gascity-mail-body
    :documentation "Message body.")
   (created-at
    :initarg :created-at :initform nil :type (or null string) :json-key created_at
    :accessor gascity-mail-created-at
    :documentation "ISO-8601 creation timestamp.")
   (read
    :initarg :read :initform nil :type (or null boolean) :json-key read
    :accessor gascity-mail-read
    :documentation "Non-nil when the message has been read; unread is its
negation (gc decodes `false' to nil)."))
  :documentation "A mail message as reported by `gc mail inbox'.")

;;; Order — `gc order list' -> `orders' vector

(defclass gascity-order ()
  ((name
    :initarg :name :initform nil :type (or null string) :json-key name
    :accessor gascity-order-name
    :documentation "Order name.")
   (scoped-name
    :initarg :scoped-name :initform nil :type (or null string) :json-key scoped_name
    :accessor gascity-order-scoped-name
    :documentation "Rig-qualified name; preferred for display when set.")
   (rig
    :initarg :rig :initform nil :type (or null string) :json-key rig
    :accessor gascity-order-rig
    :documentation "The rig the order is scoped to, or nil for city-wide.")
   (type
    :initarg :type :initform nil :type (or null string) :json-key type
    :accessor gascity-order-type
    :documentation "Order type, e.g. \"schedule\", \"cooldown\".")
   (trigger
    :initarg :trigger :initform nil :type (or null string) :json-key trigger
    :accessor gascity-order-trigger
    :documentation "What fires the order.")
   (interval
    :initarg :interval :initform nil :type (or null string) :json-key interval
    :accessor gascity-order-interval
    :documentation "Interval cadence, when interval-driven.")
   (schedule
    :initarg :schedule :initform nil :type (or null string) :json-key schedule
    :accessor gascity-order-schedule
    :documentation "Cron-style schedule, when schedule-driven.")
   (enabled
    :initarg :enabled :initform nil :type (or null boolean) :json-key enabled
    :accessor gascity-order-enabled
    :documentation "Non-nil when the order is enabled.")
   (source
    :initarg :source :initform nil :type (or null string) :json-key source
    :accessor gascity-order-source
    :documentation "Path to the order's source file (for `RET')."))
  :documentation "An order (scheduled/cooldown job) as reported by `gc order list'.")

;;; ============================================================
;;; Decoding
;;; ============================================================

(defun gascity-domain-decode (class alist)
  "Decode ALIST, a `gc --json' object, into an instance of CLASS, or nil.
Thin guarded wrapper over the library-neutral reflective decoder
`beads-from-json': nil ALIST yields nil (rather than an empty instance)."
  (and alist (beads-from-json class alist)))

(defun gascity-domain-decode-list (class seq)
  "Decode SEQ into a list of CLASS instances.
SEQ is the vector (or list) `gc --json' returns for a homogeneous list —
e.g. the `rigs'/`sessions'/`convoys' field of its envelope.  Each element is
decoded via `beads-from-json'.  A nil SEQ yields nil."
  (mapcar (lambda (x) (beads-from-json class x)) (append seq nil)))

;;; ============================================================
;;; Derived values and builders
;;; ============================================================

(cl-defmethod gascity-session-qualified-name ((session gascity-session))
  "Return SESSION's qualified agent name.
Prefers `agent-name' (always qualified) over `name', which degrades to the
raw tmux id for non-active sessions."
  (or (gascity-session-agent-name session) (gascity-session-name session)))

(cl-defmethod gascity-session-running-p ((session gascity-session))
  "Return non-nil when SESSION is active (its `state' is \"active\")."
  (equal (gascity-session-state session) "active"))

(cl-defmethod gascity-rig-status-label ((rig gascity-rig))
  "Return RIG's status label: \"suspended\", \"running\", or \"stopped\"."
  (cond ((gascity-rig-suspended rig) "suspended")
        ((gascity-rig-running rig) "running")
        (t "stopped")))

(cl-defmethod gascity-order-display-name ((order gascity-order))
  "Return ORDER's display name: its `scoped-name', else its `name'."
  (or (gascity-order-scoped-name order) (gascity-order-name order)))

(cl-defmethod gascity-order-cadence ((order gascity-order))
  "Return ORDER's cadence: its `interval', else its `schedule'."
  (or (gascity-order-interval order) (gascity-order-schedule order)))

(defun gascity-agent-from-session (session socket)
  "Build the action `gascity-agent' for SESSION on tmux SOCKET.
SESSION is a `gascity-session'.  The agent's running state is derived from
the session's state; the worktree and tmux name come from the session, and
SOCKET (the city's tmux -L socket) is recorded for attach."
  (make-instance 'gascity-agent
                 :name (gascity-session-qualified-name session)
                 :rig (gascity-session-rig session)
                 :work-dir (gascity-session-work-dir session)
                 :session-name (gascity-session-session-name session)
                 :socket socket
                 :running (gascity-session-running-p session)))

;;; ============================================================
;;; At-point dispatch
;;; ============================================================

(cl-defgeneric gascity-at-point-visit (obj)
  "Perform the default drill-in action on the object OBJ at point.
OBJ is a typed domain object (`gascity-agent', `gascity-rig', …) or a bead-id
string.  One method per kind dispatches the right action — attach an agent's
terminal, open a rig's dashboard, open a bead/convoy in beads.el, and so on —
replacing the per-payload-kind `cond' the views used to carry.  The methods
live with the actions they invoke (`gascity-section', `gascity-tabulated',
`gascity-rig'); the default below reports an object nothing knows how to visit.")

(cl-defmethod gascity-at-point-visit (_obj)
  "Default: report that there is nothing here to open."
  (user-error "Nothing here to open"))

(provide 'gascity-domain)
;;; gascity-domain.el ends here
