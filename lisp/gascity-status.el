;;; gascity-status.el --- vui status dashboard -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The agent-tree toolkit: the joins and vnodes the retired status board
;; (`gascity-status', removed by dashboard-v3 D3 — the cockpit replaces
;; it) used to lay a city out as city -> rig -> pool -> agent, kept for
;; the Agents view's tree mode (dashboard-v3 §7.3) and the rig
;; dashboard.
;;
;; - `gc status --json' reports agents flat; the tree is rebuilt by
;;   splitting each qualified name on "/" (`gascity-status--rig-agents',
;;   `gascity-status--city-agent-p').
;; - `gc session list --json' rows join on the qualified agent name
;;   (`gascity-status--session-map') for each agent's worktree and tmux
;;   target (`gascity-status--agent' builds the action object).
;; - `gc agent list --json' carries each pool's {min,max}, which groups a
;;   flat run of members under their template
;;   (`gascity-status--pool-templates', `gascity-status--group-agents').
;;
;; The components (`gascity-status-rig', `gascity-status-pool') render a
;; collapsible rig/pool with its members; collapse state is supplied by
;; the parent.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-domain)             ; typed session/agent objects
(require 'gascity-section)


;;; Data shaping (pure)

(defun gascity-status--city-agent-p (agent)
  "Return non-nil when AGENT (an alist) is a city-scope agent."
  (let ((scope (alist-get 'scope agent))
        (qname (alist-get 'qualified_name agent)))
    (or (equal scope "city")
        (and (stringp qname) (not (string-search "/" qname))))))

(defun gascity-status--rig-agents (rig-name agents)
  "Return the AGENTS whose qualified name is scoped to RIG-NAME."
  (let ((prefix (concat rig-name "/")))
    (seq-filter (lambda (a)
                  (let ((q (alist-get 'qualified_name a)))
                    (and (stringp q) (string-prefix-p prefix q))))
                agents)))

(defun gascity-status--session-map (sessions)
  "Return a hash table mapping a session's qualified agent name to its object.
SESSIONS is the vector (or list) from `gc session list'; each row is decoded
into a `gascity-session' and keyed on its qualified name
\(`gascity-session-qualified-name', which prefers `agent_name' — always the
qualified name — over the volatile `name').  The qualified name is the
reliable join key against a status agent's `qualified_name'.

Thin wrapper over `gascity-status--session-map-rows': callers that already
hold the decoded `gascity-session' rows (the dashboard, which decodes once
for the map and the named-session derivation alike) use that directly."
  (gascity-status--session-map-rows
   (gascity-domain-decode-list 'gascity-session sessions)))

(defun gascity-status--session-map-rows (session-rows)
  "Return the join map for already-decoded SESSION-ROWS.
Same map `gascity-status--session-map' builds, but over the typed
`gascity-session' list a caller decoded once — the dashboard decodes the
`gc session list' payload a single time and feeds both this map and the
named-session derivation (no double decode, no plist detour; plan-review
finding F2)."
  (let ((map (make-hash-table :test 'equal)))
    (seq-do (lambda (s)
              (let ((key (gascity-session-qualified-name s)))
                (when key (puthash key s map))))
            session-rows)
    map))

(defun gascity-status--agent (agent rig-name session-map socket)
  "Build the action `gascity-agent' for AGENT under RIG-NAME.
AGENT is a raw `gc status' agent entry; this bridges it to the typed action
object, enriching it with the worktree and tmux name from the matching
`gascity-session' in SESSION-MAP (keyed on the agent's qualified name) and
recording the tmux SOCKET for attach."
  (let* ((qname (alist-get 'qualified_name agent))
         (session (and qname (gethash qname session-map))))
    (make-instance 'gascity-agent
                   :name qname
                   :rig rig-name
                   :work-dir (and session (gascity-session-work-dir session))
                   :session-name (and session (gascity-session-session-name session))
                   :socket socket
                   :running (and (alist-get 'running agent) t))))

;;; Pool grouping
;;
;; `gc status' reports agents flat: every member of a scaled pool is a
;; sibling of every singleton, so gastown.dog-1/-2/-3 read as three
;; unrelated agents and a rig's five polecats as five.  `gc status' the
;; *command* does not print them that way — it nests the members under
;; their template with the pool's bounds — because it holds the city
;; config the status payload omits.  The dashboard reconstructs that
;; grouping from a second read, `gc agent list --json', which reports the
;; configured agents (the templates) with their `pool' {min,max} but
;; without any members.  Joining the two is what the functions below do.

(defun gascity-status--pool-templates (agents)
  "Return the pool templates configured in AGENTS.
AGENTS is the `agents' vector of `gc agent list --json' — the *configured*
agents, which unlike `gc status''s agent list carry a `pool' block but no
per-member rows.  Each element of the result is (QUALIFIED-NAME MIN MAX),
the shape `gascity-status--pool-of' and the pool header consume."
  (seq-keep (lambda (a)
              (let ((qname (alist-get 'qualified_name a))
                    (pool (alist-get 'pool a)))
                (when (and (stringp qname) pool)
                  (list qname
                        (or (alist-get 'min pool) 0)
                        (or (alist-get 'max pool) 1)))))
            (append agents nil)))

(defun gascity-status--scaled-p (template)
  "Return non-nil when TEMPLATE is a scaled pool rather than a singleton.
TEMPLATE is an entry of `gascity-status--pool-templates'.  Every configured
agent has a pool; the singletons (mayor, deacon, a rig's refinery/witness)
are the ones capped at exactly one member, and `gc status' prints those as
a plain row named after the template itself.  A max of -1 means unbounded,
which is scaled."
  (not (eql (nth 2 template) 1)))

(defun gascity-status--numbered-pool (qname templates)
  "Return the template in TEMPLATES of which QNAME is a numbered member.
The reconciler names the members of a numbered pool `TEMPLATE-N'
\(bd.dog -> bd.dog-1, gastown.dog -> gastown.dog-3), so the template is
recovered by stripping the numeric suffix.  Returns nil when QNAME carries
no such suffix or names no configured template."
  (when (string-match "\\`\\(.+\\)-[0-9]+\\'" qname)
    (assoc (match-string 1 qname) templates)))

(defun gascity-status--namespace-pool (qname templates)
  "Return the one scaled template in TEMPLATES sharing QNAME's namespace.
The fallback for a *named* pool member.  Polecats are named from a roster
\(gascity.el/gastown.furiosa under gascity.el/gastown.polecat), so neither
the name nor a numeric suffix reveals the pool; `gc' exposes the link only
on a live session's `template' field, which a stopped member does not have.
What a member does keep is its namespace — the rig prefix and dotted
namespace it shares with its template, \"gascity.el/gastown.\" — so match
on that, but only when exactly one scaled pool lives there: an ambiguous
namespace leaves the agent standalone rather than guessing it into the
wrong group."
  (let* ((ns (and (string-match "\\`\\(.*[/.]\\)[^/.]+\\'" qname)
                  (match-string 1 qname)))
         (matches (and ns
                       (seq-filter (lambda (tpl)
                                     (and (gascity-status--scaled-p tpl)
                                          (string-prefix-p ns (car tpl))))
                                   templates))))
    (and (= (length matches) 1) (car matches))))

(defun gascity-status--pool-of (qname session templates)
  "Return the pool template QNAME belongs to, or nil when it stands alone.
QNAME is a status agent's qualified name, SESSION its `gascity-session' (or
nil when it is not running) and TEMPLATES the value of
`gascity-status--pool-templates'.  Four rules, in order:

1. QNAME *is* a configured template — a singleton, printed as its own row.
2. QNAME is `TEMPLATE-N', a numbered member (`gascity-status--numbered-pool').
3. SESSION names its `template' — authoritative, but only while it runs.
4. QNAME's namespace holds exactly one scaled pool
   \(`gascity-status--namespace-pool') — the stopped named member.

A nil result means \"render flat\", which is also what an empty TEMPLATES
gives: when the `gc agent list' read fails or is still in flight the
dashboard falls back to the ungrouped list it showed before."
  (unless (assoc qname templates)
    (or (gascity-status--numbered-pool qname templates)
        (let ((tpl (and session (gascity-session-template session))))
          (and tpl (not (equal tpl qname)) (assoc tpl templates)))
        (gascity-status--namespace-pool qname templates))))

(defun gascity-status--group-agents (agents templates session-map)
  "Group AGENTS under their pool templates, preserving the payload order.
AGENTS is a list or vector of raw `gc status' agent entries, TEMPLATES the
value of `gascity-status--pool-templates' and SESSION-MAP that of
`gascity-status--session-map'.  Returns an ordered list whose elements are

  (agent ENTRY)                     a standalone agent row, or
  (pool NAME MIN MAX MEMBERS)       a pool and the members found for it,

with each pool taking the position of its first member — the order
`gc status' itself prints.  Members keep their payload order within the
group, and a pool with no members never appears: this groups the agents
that exist, it does not invent rows for a pool's unfilled slots."
  (let ((groups nil)
        (index (make-hash-table :test 'equal)))
    (seq-do
     (lambda (entry)
       (let* ((qname (alist-get 'qualified_name entry))
              (session (and qname (gethash qname session-map)))
              (template (and (stringp qname)
                             (gascity-status--pool-of qname session templates))))
         (if (null template)
             (push (list 'agent entry) groups)
           (let ((group (gethash (car template) index)))
             (unless group
               (setq group (list 'pool (car template)
                                 (nth 1 template) (nth 2 template) nil))
               (puthash (car template) group index)
               (push group groups))
             (setf (nth 4 group) (cons entry (nth 4 group)))))))
     (append agents nil))
    (dolist (group groups)
      (when (eq (car group) 'pool)
        (setf (nth 4 group) (nreverse (nth 4 group)))))
    (nreverse groups)))

(defun gascity-status--group-key (group)
  "Return the reconciliation key for GROUP, a `gascity-status--group-agents' entry.
Namespaced by kind so a pool and an agent can never collide on a key."
  (pcase (car group)
    ('pool (concat "pool:" (nth 1 group)))
    (_ (concat "agent:" (or (alist-get 'qualified_name (nth 1 group)) "?")))))

(defun gascity-status--pool-label (min max)
  "Return the bounds clause of a pool header, given its MIN and MAX.
`scaled 0–2' (dashboard-v3 §7.3); an unbounded pool (gc reports max as
-1) reads `scaled 1–∞'."
  (format "scaled %s–%s"
          (or min 0)
          (if (and (numberp max) (< max 0)) "∞" (or max 1))))

(defun gascity-status--short-name (qname rig-name)
  "Return QNAME without its RIG-NAME prefix, or unchanged when it has none.
Inside a rig section the rows are already scoped to that rig, so a pool
header reads \"gastown.polecat\", not \"gascity.el/gastown.polecat\" — the
same shortening `gc status' applies to the member rows beneath it."
  (if (and rig-name (string-prefix-p (concat rig-name "/") qname))
      (substring qname (1+ (length rig-name)))
    qname))

;;; Rendering (vnodes)

(defun gascity-status--agent-row (agent rig-name session-map socket &optional indent)
  "Return a vnode for AGENT (a raw `gc status' agent entry) under RIG-NAME.
SESSION-MAP and SOCKET join the row to its live session.  Stamps the row
with the action `gascity-agent' as a text property so the d/t/RET action
keys act on it.  INDENT is the row's leading width
in columns, defaulting to 2; a pool's members are rendered at 4, nested under
their template's header."
  (let* ((qname (alist-get 'qualified_name agent))
         (name (or (alist-get 'name agent) qname "?"))
         (running (alist-get 'running agent))
         (suspended (alist-get 'suspended agent))
         (obj (gascity-status--agent agent rig-name session-map socket)))
    (vui-text (format "%s%s %s"
                      (make-string (or indent 2) ?\s)
                      (if running "●" "○")
                      name)
              :face (gascity-section-state-face running suspended)
              'gascity-agent obj)))

(defun gascity-status--agent-group-vnodes (groups rig-name session-map socket
                                                  collapsed-pools)
  "Return the row vnodes for GROUPS under RIG-NAME.
SESSION-MAP and SOCKET join the agent rows to their sessions.  GROUPS
is a `gascity-status--group-agents' result: standalone agents render
as rows, pools as `gascity-status-pool' components told whether they are in
COLLAPSED-POOLS (the app's list of collapsed pool names — lifted there, like
the rigs', so the keymap can toggle the pool at point and the state survives
a refresh).  The keyed `vui-list' reconciles each group in place."
  (vui-list groups
            (lambda (group)
              (pcase (car group)
                ('pool (vui-component 'gascity-status-pool
                                      :pool group :rig-name rig-name
                                      :session-map session-map :socket socket
                                      :collapsed (and (member (nth 1 group)
                                                              collapsed-pools)
                                                      t)))
                (_ (gascity-status--agent-row (nth 1 group) rig-name
                                              session-map socket))))
            #'gascity-status--group-key))

(defun gascity-status--controller-label (controller)
  "Return a one-line label for the CONTROLLER block of a `gc status' payload.
Mirrors `gc status''s \"Controller: supervisor-managed (PID 16949)\": the
mode it runs under and the PID that holds authority, which a bare up/down
does not tell you.  A controller that is not running is simply \"down\"."
  (let ((running (and controller (alist-get 'running controller)))
        (mode (and controller (alist-get 'mode controller)))
        (pid (and controller (alist-get 'pid controller))))
    (if (not running)
        "down"
      (concat (or mode "up")
              (and (integerp pid) (> pid 0) (format " (PID %d)" pid))))))

(defun gascity-status--sessions-label (status session-summary)
  "Return the sessions clause of the header: \"9 active, 0 suspended\".
SESSION-SUMMARY is the `summary' block of `gc session list --json', the only
payload that counts *suspended* sessions; STATUS's own
`summary.active_sessions' is the fallback while that read is in flight."
  (let ((active (or (alist-get 'active session-summary)
                    (alist-get 'active_sessions (alist-get 'summary status))
                    0))
        (suspended (alist-get 'suspended session-summary)))
    (if suspended
        (format "%s active, %s suspended" active suspended)
      (format "%s active" active))))

(defun gascity-status--format-bytes (bytes)
  "Return BYTES as a human-readable decimal size, e.g. \"227.1 MB\".
Decimal units (kB/MB/GB), matching how `gc status' sizes the store."
  (cond
   ((not (numberp bytes)) "?")
   ((>= bytes 1000000000) (format "%.1f GB" (/ bytes 1e9)))
   ((>= bytes 1000000) (format "%.1f MB" (/ bytes 1e6)))
   ((>= bytes 1000) (format "%.1f kB" (/ bytes 1e3)))
   (t (format "%d B" bytes))))

(defun gascity-status--ratio-label (ratio threshold)
  "Return the store's MB-per-row RATIO, with THRESHOLD when gc reports one."
  (if (numberp ratio)
      (format "%.2f MB/row%s" ratio
              (if (numberp threshold)
                  (format " (threshold %.1f MB/row)" threshold)
                ""))
    "ratio ?"))

(defun gascity-status--named-session-row (named socket)
  "Return a row vnode for NAMED, a `gascity-named-session'.
Mirrors `gc status''s \"mayor                   awake (always)\": the
identity, the CLI-shaped awake/asleep token
\(`gascity-named-session-label'), and the mode in parentheses when gc
exposes it in JSON; with no mode (gc 1.4.2) the row shows none — missing
data renders nothing (dashboard-v3 §4.4).
The row is stamped with the action `gascity-agent' — enriched from
NAMED's own `gascity-session' row (always set by the derivation) plus
the tmux SOCKET — so the standard text
properties and action keys (d/t/RET/i/M/s/K/w/D) act on
it like on any agent row."
  (let* ((identity (gascity-named-session-identity named))
         (session (gascity-named-session-session named))
         (awake (gascity-named-session-awake named))
         (mode (gascity-named-session-mode named))
         ;; The action object: the derivation guarantees the session slot,
         ;; so the row always carries an actionable object at point.
         (obj (gascity-agent-from-session session socket)))
    (vui-text (format "  %s %s%s"
                      identity
                      (gascity-named-session-label named)
                      (if mode (format " (%s)" mode) ""))
              :face (gascity-section-state-face awake)
              'gascity-agent obj)))

(defun gascity-status--named-sessions-vnode (named-sessions socket)
  "Return the named-sessions section vnode, or nil when there is nothing to show.
SOCKET is the shared tmux socket the rows' action keys attach through.
NAMED-SESSIONS is the `gascity-domain-named-sessions-from-sessions'
derivation over the dashboard's decoded `gc session list' rows.  A nil or
empty derivation — no canonical city-scoped row, which is also what a
pending or failed session load with no snapshot in hand yields — returns
nil, so nothing unmounts (the stale-while-revalidate rule: the section's
absence must never blank its neighbors).  Otherwise this is a dim
\"Named sessions\" header and one row per derived object."
  (when named-sessions
    (vui-vstack
     (vui-text "Named sessions" :face 'gascity-dim 'gascity-section t)
     (vui-list named-sessions
               (lambda (named)
                 (gascity-status--named-session-row named socket))
               (lambda (named)
                 (or (gascity-named-session-identity named) "?"))))))

;;; Components

(defvar-local gascity-status-toggle-function nil
  "Function of (KIND NAME) folding a rig (KIND `rig') or pool (`pool').
The view that hosts these components sets it; the headers' SPC thing
calls it (dashboard-v3 §5.4).")

(defun gascity-status--fold-thing (kind name)
  "Return the `beads-thing' value of the KIND header NAME (SPC folds it)."
  (list :kind 'fold :id (format "%s:%s" kind name)
        :toggle (lambda ()
                  (if gascity-status-toggle-function
                      (funcall gascity-status-toggle-function kind name)
                    (message "Nothing to toggle here")))))

(vui-defcomponent gascity-status-rig (rig agents templates session-map socket
                                          collapsed collapsed-pools)
  "A collapsible section for one RIG (a `gascity-rig') and its scoped AGENTS.
TEMPLATES and COLLAPSED-POOLS are passed through to
`gascity-status--agent-group-vnodes', which nests the rig's pool members
under their template.  COLLAPSED is supplied by the parent from the app's
`collapsed-rigs' state (lifted there so the keymap can toggle the rig at
point and the state survives a refresh).  The header is stamped with
`gascity-rig' (the rig name, for the toggle) and `gascity-rig-dir' (its
`path', for `d'); the path is also shown, dimmed, beside the name — `gc
status' prints it and it is the fastest way to tell two checkouts apart."
  :render
  (let* ((name (gascity-rig-name rig))
         (path (gascity-rig-path rig))
         (suspended (gascity-rig-suspended rig))
         (groups (gascity-status--group-agents
                  (gascity-status--rig-agents name agents)
                  templates session-map))
         (header (format "%s %s%s"
                         (if collapsed "▸" "▾")
                         name
                         (if suspended "  (suspended)" ""))))
    (vui-vstack
     (vui-hstack
      :spacing 2
      (vui-text header
                :face (if suspended 'gascity-suspended 'gascity-rig)
                'gascity-rig name
                'gascity-rig-dir path
                'gascity-section t
                'beads-thing (gascity-status--fold-thing 'rig name))
      (when path
        (vui-text (gascity-ui-path path)
                  :face 'gascity-dim
                  'gascity-rig name
                  'gascity-rig-dir path)))
     (unless collapsed
       (if groups
           (gascity-status--agent-group-vnodes groups name session-map socket
                                               collapsed-pools)
         (vui-text "  (no agents)" :face 'gascity-dim))))))

(vui-defcomponent gascity-status-pool (pool rig-name session-map socket collapsed)
  "A collapsible group for one scaled POOL and the members found for it.
POOL is a (pool NAME MIN MAX MEMBERS) entry from
`gascity-status--group-agents'; its members render indented beneath a header
carrying the pool's bounds, the way `gc status' prints a scaled pool.
COLLAPSED is supplied by the parent from the app's `collapsed-pools' state
\(lifted there, like the rigs', so the keymap can toggle the pool at point
and the state survives a refresh).  The header is stamped with
`gascity-pool' — the template's qualified name — so RET, TAB and a left
click toggle it."
  :render
  (let ((name (nth 1 pool)))
    (vui-vstack
     (vui-hstack
      :spacing 2
      (vui-text (format "  %s %s"
                        (if collapsed "▸" "▾")
                        (gascity-status--short-name name rig-name))
                :face 'gascity-header
                'gascity-pool name
                'beads-thing (gascity-status--fold-thing 'pool name))
      (vui-text (gascity-status--pool-label (nth 2 pool) (nth 3 pool))
                :face 'gascity-dim
                'gascity-pool name))
     (unless collapsed
       (vui-list (nth 4 pool)
                 (lambda (agent)
                   (gascity-status--agent-row agent rig-name session-map socket 4))
                 (lambda (agent)
                   (or (alist-get 'qualified_name agent) "?")))))))

(provide 'gascity-status)
;;; gascity-status.el ends here
