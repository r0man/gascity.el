;;; gascity-status.el --- vui status dashboard -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The town status dashboard: an interactive, hand-built (magit/forge
;; style) overview of the city, its rigs, and their agents — the same
;; information as `gc status', rendered with vui.
;;
;; Three `gc' reads run asynchronously and are joined client-side:
;;
;;   `gc status --json'        the city header (path, controller, health,
;;                             suspended), the flat agent list, the rigs,
;;                             and the summary counters + store health;
;;   `gc session list --json'  each agent's worktree (`work_dir', for
;;                             Dired), tmux target (`session_name', for
;;                             attach), pool `template', and the
;;                             active/suspended session counts;
;;   `gc agent list --json'    the *configured* agents — the only surface
;;                             carrying each pool's {min,max}, which turns
;;                             a flat run of members into a group.
;;
;; The city -> rig -> agent tree is assembled from the status agent list
;; (which is flat) by splitting each agent's qualified name on \"/\";
;; within a scope, the members of a scaled pool nest under their template
;; (see `gascity-status--pool-of').  Controller-down does not blank the
;; view — sessions are trusted independently — and a failed `gc agent
;; list' costs only the grouping, not the rows.
;;
;; TODO (gc-side JSON gap, gce-8ey): `gc status' also prints an API URL
;; and a \"Named sessions\" block (each named agent's mode — always /
;; on_demand — and its awake state).  Neither is reachable from `--json':
;; the API URL appears in no payload, and `gc agent list --json' reports
;; `mode', `wake_mode' and `idle_timeout' as null.  Both render here as
;; soon as gc exposes them; hand-parsing city.toml or .gc/system/packs is
;; not an option — the reconciler owns and rewrites those files.
;;
;; Rig sections and pool groups are collapsible (their collapse state
;; lifted to the root component, so it survives an in-place refresh).
;; `g' refreshes, `q' buries, `d' opens an agent's worktree in Dired, `t'
;; (or RET) attaches to its tmux session, `i' opens an agent's detail
;; view, `b' opens the beads board (the rig's store on a rig header, the
;; agent's worktree on an agent row), and RET (or TAB) toggles the rig or
;; pool header at point.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-context)            ; pin-directory (view keyed to its city)
(require 'gascity-domain)             ; typed session/agent objects
(require 'gascity-reader)
(require 'gascity-command)
(require 'gascity-command-status)
(require 'gascity-section)

;; Session actions on the agent at point live in gascity-action, and the
;; polecat-detail opener in gascity-session — both loaded after this
;; module via gascity.el; the dashboard keymap binds to them.
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
;; Write verbs (DESIGN-write-actions.md phase 1): session reset/undrain, the
;; bead-note action, and the city-config reload bound on the dashboard.
(declare-function gascity-session-reset-at-point "gascity-action")
(declare-function gascity-session-undrain-at-point "gascity-action")
(declare-function gascity-bead-note-at-point "gascity-action")
(declare-function gascity-reload "gascity-action")
;; Write verbs (DESIGN-write-actions.md phase 2): the bead-dispatch (`c') and
;; sling (`S') menus bound on a bead reference.
(declare-function gascity-bead-dispatch "gascity-action")
(declare-function gascity-sling-dispatch "gascity-action")
(declare-function gascity-polecat-detail-at-point "gascity-session")

;;; Buffer

(defconst gascity-status-buffer-name "*gascity-status*"
  "Base name of the gascity status dashboard buffer.
For a remote city the live buffer's name is this qualified by the TRAMP
prefix (via `gascity-view-get-buffer-create'), so a local and a remote
dashboard coexist.")

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
reliable join key against a status agent's `qualified_name'."
  (let ((map (make-hash-table :test 'equal)))
    (seq-do (lambda (s)
              (let ((key (gascity-session-qualified-name s)))
                (when key (puthash key s map))))
            (gascity-domain-decode-list 'gascity-session sessions))
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
Mirrors `gc status''s \"scaled (min=0, max=5)\"; an unbounded pool (gc
reports max as -1) reads as \"max=∞\"."
  (format "scaled (min=%s, max=%s)"
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
Stamps the row with the action `gascity-agent' (carrying the tmux SOCKET) as
a text property so `d'/`t'/RET act on it.  INDENT is the row's leading width
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
GROUPS is a `gascity-status--group-agents' result: standalone agents render
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

(defun gascity-status--header-vnode (status &optional session-summary)
  "Return the dashboard header vnode for the STATUS alist.
Renders what `gc status' puts above its agent list: the city and its path,
the controller's mode and PID, health, whether the city is suspended, and
the agent/session counters.  SESSION-SUMMARY, when the `gc session list'
read has landed, supplies the suspended-session count."
  (let* ((city (alist-get 'city_name status))
         (path (alist-get 'city_path status))
         (controller (alist-get 'controller status))
         (health (alist-get 'health status))
         (degraded (and health (alist-get 'degraded health)))
         (suspended (alist-get 'suspended status))
         (summary (alist-get 'summary status))
         (running-agents (or (and summary (alist-get 'running_agents summary)) 0))
         (total-agents (or (and summary (alist-get 'total_agents summary)) 0)))
    (vui-vstack
     ;; Nested so the path sits two columns off the city name — the gap the
     ;; rig headers use — while the label keeps its single space.
     (vui-hstack
      :spacing 2
      (vui-hstack :spacing 1
                  (vui-text "Gas City:" :face 'gascity-header 'gascity-section t)
                  (vui-text (or city "?") :face 'gascity-city))
      (when path (vui-text path :face 'gascity-dim)))
     (vui-text (format "  controller %s · health %s · %s"
                       (gascity-status--controller-label controller)
                       (if degraded "degraded" "ok")
                       (if suspended "city suspended" "not suspended"))
               :face (cond (degraded 'gascity-failed)
                           (suspended 'gascity-suspended)
                           (t 'gascity-dim)))
     (vui-text (format "  agents %s/%s running · sessions %s"
                       running-agents total-agents
                       (gascity-status--sessions-label status session-summary))
               :face 'gascity-dim))))

(defun gascity-status--store-health-vnode (status)
  "Return the store-health section vnode for STATUS, or nil when it is absent.
Mirrors `gc status''s \"Store health\" block: the beads store's path, size,
live row count, and the size-per-row ratio gc watches.  gc sets `warning'
once that ratio crosses `threshold_mb_per_row' — the signal that the store
has accumulated garbage and wants a `gc dolt gc' — so a warning store is
rendered in the failed face rather than dimmed away."
  (let ((health (alist-get 'store_health (alist-get 'summary status))))
    (when health
      (let ((path (alist-get 'path health))
            (rows (alist-get 'live_rows health))
            (warning (alist-get 'warning health)))
        (vui-vstack
         (vui-text "Store health" :face 'gascity-header 'gascity-section t)
         (when path (vui-text (format "  %s" path) :face 'gascity-dim))
         (vui-text (format "  %s · %s live rows · %s"
                           (gascity-status--format-bytes
                            (alist-get 'size_bytes health))
                           (or rows 0)
                           (gascity-status--ratio-label
                            (alist-get 'ratio_mb_per_row health)
                            (alist-get 'threshold_mb_per_row health)))
                   :face (if warning 'gascity-failed 'gascity-dim)))))))

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

(cl-defun gascity-status--content-vnode (status sessions
                                         &key templates session-summary
                                              sessions-state sessions-error
                                              collapsed-rigs collapsed-pools)
  "Return the dashboard body vnode from STATUS and SESSIONS data.
TEMPLATES is the `gascity-status--pool-templates' value of the `gc agent
list' read; nil (that read still in flight, or failed) simply renders every
agent flat.  SESSION-SUMMARY is the session payload's `summary' block, which
carries the counts the header reports.  SESSIONS-STATE/SESSIONS-ERROR
describe the `gc session list' load so a one-line hint can warn that
`d'/`t' are disabled when it did not succeed.  COLLAPSED-RIGS and
COLLAPSED-POOLS are the app's lists of collapsed rig and pool names; each
section is told whether it is collapsed (lifted there so the keymap can
toggle the section at point — see `gascity-status--toggle-rig' and
`gascity-status--toggle-pool')."
  (let* ((session-map (gascity-status--session-map (or sessions [])))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status)))
         (agents (alist-get 'agents status))
         (rigs (gascity-domain-decode-list 'gascity-rig (alist-get 'rigs status)))
         (city-agents (seq-filter #'gascity-status--city-agent-p agents)))
    (vui-vstack
     :spacing 1
     (gascity-status--header-vnode status session-summary)
     (gascity-status--sessions-note-vnode sessions-state sessions-error)
     (when city-agents
       (vui-vstack
        (vui-text "City" :face 'gascity-header 'gascity-section t)
        (gascity-status--agent-group-vnodes
         (gascity-status--group-agents city-agents templates session-map)
         nil session-map socket collapsed-pools)))
     ;; `:spacing 1' renders a blank line between rig groups for visual
     ;; separation; the keyed `vui-list' still reconciles each rig in place,
     ;; so collapse state and point survive a refresh.
     (vui-list rigs
               (lambda (rig)
                 (vui-component 'gascity-status-rig
                                :rig rig :agents agents :templates templates
                                :session-map session-map :socket socket
                                :collapsed-pools collapsed-pools
                                :collapsed (and (member (gascity-rig-name rig)
                                                        collapsed-rigs)
                                                t)))
               (lambda (rig) (gascity-rig-name rig))
               :spacing 1)
     (gascity-status--store-health-vnode status))))

(defun gascity-status--error-vnode (message)
  "Return a vnode reporting MESSAGE and how to retry."
  (vui-vstack
   (vui-text (format "Could not load Gas City status: %s" (or message "?"))
             :face 'gascity-failed)
   (vui-text "Press g to retry." :face 'gascity-dim)))

(defun gascity-status--sessions-note-vnode (state error)
  "Return a one-line hint vnode when sessions are unavailable, else nil.
STATE is the `vui-use-async' status of the `gc session list' load and
ERROR its message.  The dashboard renders even when that load has not
succeeded, but without it agent rows carry no `work_dir'/`session_name',
so `d' (Dired) and `t' (tmux attach) silently no-op.  Surface why instead
of degrading invisibly; a `ready' load needs no note (returns nil)."
  (pcase state
    ('error
     (vui-text (format "  Sessions unavailable — d/t disabled (%s)"
                       (or error "load failed"))
               :face 'gascity-failed))
    ('pending
     (vui-text "  Sessions loading — d/t available once ready"
               :face 'gascity-dim))))

;;; Components

;; Collapsible headers are property-carrying text (the magit/forge idiom this
;; dashboard follows), not widgets: a `gascity-rig' (name) / `gascity-rig-dir'
;; (path) text property lets the keymap commands act on the rig at point —
;; RET toggles collapse, `d' opens its directory — and a `gascity-pool'
;; property (the template's qualified name) does the same for a pool group.
;; This keymap restores the click-to-toggle the old header button gave; only
;; `mouse-1' is bound, so RET and `n'/`p' fall through to the buffer keymap.
;; The binding is a quoted symbol (not #') so the command may be defined later
;; in the file without a byte-compile forward-reference warning.
(defvar gascity-status-header-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] 'gascity-status-mouse-1)
    map)
  "Keymap placed on collapsible header text so a left click toggles it.")

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
                         (if collapsed "▶" "▼")
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
                'mouse-face 'highlight
                'keymap gascity-status-header-keymap)
      (when path
        (vui-text path
                  :face 'gascity-dim
                  'gascity-rig name
                  'gascity-rig-dir path
                  'mouse-face 'highlight
                  'keymap gascity-status-header-keymap)))
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
                        (if collapsed "▶" "▼")
                        (gascity-status--short-name name rig-name))
                :face 'gascity-header
                'gascity-pool name
                'mouse-face 'highlight
                'keymap gascity-status-header-keymap)
      (vui-text (gascity-status--pool-label (nth 2 pool) (nth 3 pool))
                :face 'gascity-dim
                'gascity-pool name
                'mouse-face 'highlight
                'keymap gascity-status-header-keymap))
     (unless collapsed
       (vui-list (nth 4 pool)
                 (lambda (agent)
                   (gascity-status--agent-row agent rig-name session-map socket 4))
                 (lambda (agent)
                   (or (alist-get 'qualified_name agent) "?")))))))

(vui-defcomponent gascity-status-app ()
  "Root component of the gascity status dashboard."
  :state ((refresh-tick 0) (collapsed-rigs nil) (collapsed-pools nil))
  :render
  ;; Collapse state (`collapsed-rigs' and `collapsed-pools', lists of the
  ;; collapsed rig and pool-template names) lives here, in the root
  ;; component, rather than per section: a keymap command
  ;; (`gascity-status--toggle-rig' / `--toggle-pool', reached via
  ;; RET/TAB/`mouse-1' on a header) can then flip the section at point, and
  ;; the lists survive a refresh since `g' only bumps `refresh-tick'.
  ;;
  ;; Stale-while-revalidate.  `g' refreshes by bumping `refresh-tick',
  ;; which changes every `vui-use-async' key and so restarts each load as
  ;; 'pending with nil data.  Rendering the pending branch (a bare
  ;; "Loading…" line) replaces the whole tree and blanks the view, losing
  ;; point, on *every* refresh.  Instead, cache the last good payload in a
  ;; ref and keep rendering it while the refreshed load is in flight,
  ;; swapping in fresh data only on 'ready.  Keyed children then reconcile
  ;; in place, so point survives a refresh.  The fallback screens (loading /
  ;; error) show only on the first, dataless load — never over a snapshot we
  ;; can still show.
  (let* ((status-res
          (vui-use-async (list 'status refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async '("status") resolve reject))))
         (sessions-res
          (vui-use-async (list 'sessions refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("session" "list") resolve reject))))
         ;; The third read: `gc agent list' is the only surface carrying each
         ;; pool's {min,max}, so it is what turns a flat run of members into a
         ;; group.  It is strictly an enrichment — every other section renders
         ;; without it, so its failure costs the grouping, nothing more.
         (agents-res
          (vui-use-async (list 'agents refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("agent" "list") resolve reject))))
         (status-state (plist-get status-res :status))
         (sessions-state (plist-get sessions-res :status))
         (agents-state (plist-get agents-res :status))
         (last-status (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         (last-templates (vui-use-ref nil))
         ;; `setcar' both refreshes the cache and returns the new value, so
         ;; on 'ready we adopt fresh data; otherwise we reuse the snapshot.
         (status (if (eq status-state 'ready)
                     (setcar last-status (plist-get status-res :data))
                   (car last-status)))
         ;; Cache the whole session payload, not just its `sessions' vector:
         ;; its `summary' block carries the active/suspended counts the
         ;; header reports.
         (sessions-payload (if (eq sessions-state 'ready)
                               (setcar last-sessions (plist-get sessions-res :data))
                             (car last-sessions)))
         (sessions (alist-get 'sessions sessions-payload))
         (session-summary (alist-get 'summary sessions-payload))
         (templates (if (eq agents-state 'ready)
                        (setcar last-templates
                                (gascity-status--pool-templates
                                 (alist-get 'agents (plist-get agents-res :data))))
                      (car last-templates)))
         ;; The sessions hint reflects whether usable data is in hand, not
         ;; the raw load state: a refresh still holding a snapshot keeps
         ;; `d'/`t' working, so it needs no "loading" note.
         (sessions-note-state (if sessions 'ready sessions-state)))
    (cond
     ((and (eq status-state 'error) (null status))
      (gascity-status--error-vnode (plist-get status-res :error)))
     ((and (eq status-state 'pending) (null status))
      (vui-text "Loading Gas City status…" :face 'gascity-dim))
     (t
      (gascity-status--content-vnode
       status sessions
       :templates templates
       :session-summary session-summary
       :sessions-state sessions-note-state
       :sessions-error (plist-get sessions-res :error)
       :collapsed-rigs collapsed-rigs
       :collapsed-pools collapsed-pools)))))

;;; Commands

(defun gascity-status-activate ()
  "Activate the thing at point.
On a rig or pool header this toggles its collapse; on an agent row it visits
the agent via `gascity-at-point-visit' — attaching its tmux terminal, the
primary action.  `i' opens the agent's detail/info view instead."
  (interactive)
  (let ((obj (gascity-object-at-point)))
    (cond
     ((get-text-property (point) 'gascity-rig)
      (gascity-status--toggle-rig (get-text-property (point) 'gascity-rig)))
     ((get-text-property (point) 'gascity-pool)
      (gascity-status--toggle-pool (get-text-property (point) 'gascity-pool)))
     (obj (gascity-at-point-visit obj))
     (t (user-error "Nothing to activate here")))))

(defun gascity-status-mouse-1 (event)
  "Move point to the header clicked by mouse EVENT and activate it.
Bound on rig- and pool-header text via `gascity-status-header-keymap', this
restores the click-to-toggle the old header button provided."
  (interactive "e")
  (mouse-set-point event)
  (gascity-status-activate))

(defun gascity-status-toggle-section ()
  "Toggle collapse of the section at point.
The magit-section convention binds `TAB' to \"toggle the visibility of the
section at point\"; this is the dashboard's `TAB'.  The status board's
collapsible sections are its rig headers (stamped with a `gascity-rig' text
property) and its pool groups (`gascity-pool'); on either, this flips the
collapse — the same toggle `RET' performs on a header
\(`gascity-status-activate').  Elsewhere (an agent row, the city block)
there is nothing collapsible, so it signals a clean `user-error' rather than
acting on something unrelated — `TAB' toggles, never attaches."
  (interactive)
  (let ((rig (get-text-property (point) 'gascity-rig))
        (pool (get-text-property (point) 'gascity-pool)))
    (cond (rig (gascity-status--toggle-rig rig))
          (pool (gascity-status--toggle-pool pool))
          (t (user-error "No section to toggle here")))))

(defun gascity-status--toggle-collapsed (key name)
  "Toggle NAME's membership in the root component's KEY collapse list.
KEY is `:collapsed-rigs' or `:collapsed-pools'.  Flips NAME in the root
`gascity-status-app' component's state and re-renders in place via
`vui-flush-sync' — no re-fetch, since the `vui-use-async' keys are
unchanged.  Mirrors `gascity-status--refresh-instance'."
  (when (and (boundp 'vui--root-instance) vui--root-instance)
    (let* ((instance vui--root-instance)
           (state (vui-instance-state instance))
           (collapsed (plist-get state key)))
      (setf (vui-instance-state instance)
            (plist-put state key
                       (if (member name collapsed)
                           (remove name collapsed)
                         (cons name collapsed))))
      (vui-flush-sync))))

(defun gascity-status--toggle-rig (name)
  "Toggle whether rig NAME is collapsed in the status dashboard."
  (gascity-status--toggle-collapsed :collapsed-rigs name))

(defun gascity-status--toggle-pool (name)
  "Toggle whether the pool named NAME is collapsed in the status dashboard.
NAME is the pool template's qualified name — the `gascity-pool' property its
header carries."
  (gascity-status--toggle-collapsed :collapsed-pools name))

(defun gascity-status--refresh-instance (buffer)
  "Bump the refresh tick of the dashboard mounted in BUFFER.
Returns non-nil when a live instance was refreshed in place (preserving
collapse state and point); nil when BUFFER has no mounted instance."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (when (and (boundp 'vui--root-instance) vui--root-instance)
           (let* ((instance vui--root-instance)
                  (state (vui-instance-state instance))
                  (tick (or (plist-get state :refresh-tick) 0)))
             (setf (vui-instance-state instance)
                   (plist-put state :refresh-tick (1+ tick)))
             (vui-flush-sync)
             t)))))

(defun gascity-status-refresh ()
  "Reload the status dashboard's data, preserving expanded rigs."
  (interactive)
  (unless (gascity-status--refresh-instance (current-buffer))
    (gascity-status)))

;;; Auto-refresh timer

;; A buffer-local repeating timer re-renders the dashboard on an interval,
;; mirroring the tmux status-line timer in gascity-terminal.el: the timer is
;; created at mode-enable (guarded by `gascity-status-auto-refresh' and a
;; positive interval), torn down from `kill-buffer-hook', and its tick is a
;; no-op unless the buffer is currently displayed.  A buried dashboard must
;; not poll `gc'.  The tick refreshes in place via
;; `gascity-status--refresh-instance', so collapsed rigs and point survive
;; — never a full `gascity-status' remount.

(defvar-local gascity-status--refresh-timer nil
  "Repeating timer auto-refreshing this dashboard buffer, or nil.")

(defun gascity-status--loads-pending-p (buffer)
  "Return non-nil when BUFFER's mounted dashboard has a load in flight.
Inspects the root vui instance's async-hook cache for an entry still in
the `pending' state.  Used by the auto-refresh tick: bumping the refresh
tick changes every `vui-use-async' key, which KILLS the in-flight gc
process and restarts the load — so on a link where a read takes longer
than the refresh interval (a remote city over ssh, say), an unguarded
timer would restart the loads forever and the dashboard would never
show data."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (when (and (boundp 'vui--root-instance) vui--root-instance)
           (let ((asyncs (vui-instance-asyncs vui--root-instance))
                 (pending nil))
             (when asyncs
               (maphash (lambda (_id entry)
                          (when (eq (plist-get entry :status) 'pending)
                            (setq pending t)))
                        asyncs))
             pending)))))

(defun gascity-status--auto-refresh-tick (buffer)
  "Refresh the dashboard in BUFFER, but only while it is visible and idle.
Timer callback.  When BUFFER is live, shown in a window on some visible
frame, and has no load still in flight (`gascity-status--loads-pending-p'
— refreshing mid-flight cancels and restarts the fetch, so a slow link
would otherwise never complete one), refresh it in place with
`gascity-status--refresh-instance' (which preserves collapse state and
point).  When BUFFER is buried or its frame is invisible, do nothing —
no `gc' fetch and no refresh tick — so an out-of-sight dashboard costs
nothing."
  (when (and (buffer-live-p buffer)
             (get-buffer-window buffer 'visible)
             ;; TRAMP mid-operation: a timer can fire inside another TRAMP
             ;; call's `accept-process-output', where spawning the refresh
             ;; processes signals "Forbidden reentrant call of Tramp" and
             ;; needlessly errors the loads.  Skip; the next tick retries.
             (not (bound-and-true-p tramp-locked))
             (not (gascity-status--loads-pending-p buffer)))
    ;; `non-essential': a timer must never make TRAMP establish a NEW
    ;; connection — on a dropped link that is a multi-second freeze per
    ;; tick.  A live connection is unaffected; after a drop the tick
    ;; degrades to an error state and a manual `g' reconnects.
    (let ((non-essential t))
      (gascity-status--refresh-instance buffer))))

(defun gascity-status--auto-refresh-teardown ()
  "Cancel the current buffer's auto-refresh timer.
Run from `kill-buffer-hook' so killing the dashboard leaves no live timer."
  (when (timerp gascity-status--refresh-timer)
    (cancel-timer gascity-status--refresh-timer))
  (setq gascity-status--refresh-timer nil))

(defun gascity-status--auto-refresh-setup (buffer)
  "Start BUFFER's auto-refresh timer per `gascity-status-auto-refresh'.
Idempotent: cancels any existing timer first, so re-running never leaks a
second one.  Creates a repeating timer only when `gascity-status-auto-refresh'
is non-nil and `gascity-status-auto-refresh-interval' is a positive number;
otherwise the dashboard stays manual-refresh only.  When a timer is created,
arrange teardown on `kill-buffer-hook' so the timer dies with the buffer."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (timerp gascity-status--refresh-timer)
        (cancel-timer gascity-status--refresh-timer))
      (setq gascity-status--refresh-timer nil)
      (when (and gascity-status-auto-refresh
                 (numberp gascity-status-auto-refresh-interval)
                 (> gascity-status-auto-refresh-interval 0))
        (setq gascity-status--refresh-timer
              (run-with-timer gascity-status-auto-refresh-interval
                              gascity-status-auto-refresh-interval
                              #'gascity-status--auto-refresh-tick buffer))
        (add-hook 'kill-buffer-hook
                  #'gascity-status--auto-refresh-teardown nil t)))))

(defun gascity-status-toggle-auto-refresh ()
  "Toggle automatic refresh of the Gas City status dashboard.
Flips `gascity-status-auto-refresh' and (re)starts or cancels the current
buffer's refresh timer to match.  While on, the dashboard re-renders every
`gascity-status-auto-refresh-interval' seconds whenever it is visible."
  (interactive)
  (setq gascity-status-auto-refresh (not gascity-status-auto-refresh))
  (gascity-status--auto-refresh-setup (current-buffer))
  (message "Gas City auto-refresh %s"
           (if gascity-status-auto-refresh
               (format "on (every %ss while visible)"
                       gascity-status-auto-refresh-interval)
             "off")))

;;; Mode

(defvar-keymap gascity-dashboard-mode-map
  :doc "Keymap for `gascity-dashboard-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-status-refresh
  ;; `G' (capital of manual refresh `g') toggles auto-refresh on/off live.
  "G"   #'gascity-status-toggle-auto-refresh
  ;; `TAB' toggles the rig section at point — the magit-section convention
  ;; (TAB = toggle visibility).  It shadows the vui chain's `widget-forward'
  ;; (harmless: this view renders no widgets) and is bound here, not in the
  ;; shared `gascity-section-mode-map', because the status board is the only
  ;; dashboard with collapsible sections.  `RET' still toggles too (on a
  ;; header) and attaches the agent's terminal (on a row).
  "TAB" #'gascity-status-toggle-section
  "RET" #'gascity-status-activate
  "i"   #'gascity-polecat-detail-at-point
  "b"   #'gascity-beads-at-point
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  ;; Nudge moves off `N' (now next-section, inherited from
  ;; `gascity-section-mode-map') to `M' (Message).  Line movement (`n'/`p')
  ;; and section jumps (`N'/`P') are both inherited from the shared map.
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  ;; Write verbs: `R' resets the agent at point fresh, `U' clears its drain
  ;; flag, `L' reloads the city config (prefix arg -> --soft).  Phase 2
  ;; promotes `c' to the bead-dispatch menu (note moved to its `o') and adds
  ;; `S' for the sling/route flag transient on a bead reference.
  "R"   #'gascity-session-reset-at-point
  "U"   #'gascity-session-undrain-at-point
  "c"   #'gascity-bead-dispatch
  "S"   #'gascity-sling-dispatch
  "L"   #'gascity-reload)

(define-derived-mode gascity-dashboard-mode gascity-section-mode "GC-Status"
  "Major mode for the gascity status dashboard.

\\{gascity-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              (concat " Gas City  (g refresh · G auto · TAB toggle · RET tmux/toggle"
                      " · i detail · b beads · d dired · t tmux · M/s/K/w/D/R/U session"
                      " · c note · L reload · N/P section · q bury)"))
  ;; Start the visibility-gated auto-refresh timer (no-op when
  ;; `gascity-status-auto-refresh' is nil or the interval is non-positive).
  (gascity-status--auto-refresh-setup (current-buffer)))

;;;###autoload
(defun gascity-status ()
  "Show the Gas City status dashboard.
The dashboard is keyed to the city it is opened for: its buffer name is
host-qualified for a remote city (so a local and a remote dashboard
coexist) and its `default-directory' is pinned to that city's root, so
the refresh timer and every at-point action keep resolving the same gc
— and, remotely, the same host — no matter where a refresh is invoked
from."
  (interactive)
  (let ((buf (gascity-view-get-buffer-create gascity-status-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-dashboard-mode)
        (gascity-dashboard-mode)))
    (unless (gascity-status--refresh-instance buf)
      ;; vui-mount switch-to-buffers internally; contain that so the buffer is
      ;; displayed once, via pop-to-buffer, on both the cold and refresh paths.
      (save-window-excursion
        (vui-mount (vui-component 'gascity-status-app) (buffer-name buf))))
    (pop-to-buffer buf)))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-status))
  "Open the status dashboard instead of streaming raw output."
  (gascity-status))

(provide 'gascity-status)
;;; gascity-status.el ends here
