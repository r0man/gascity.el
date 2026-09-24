;;; gascity-dashboard.el --- city-level vui dashboard -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The city dashboard (REQ-001…REQ-013 of plans/city-dashboard): one
;; buffer that answers "what is happening in this city right now?" —
;; the native Emacs counterpart of the supervisor's web SPA, scaled up
;; from the rig dashboard (`gascity-rig.el') and reusing the status
;; dashboard's joins (`gascity-status.el').  It is additive: the magit
;; status dashboard stays the default, and `gascity-status.el' itself
;; is untouched (REQ-001).
;;
;; Sections, each backed by an INDEPENDENT `gascity-reader-read-async'
;; read so one slow or failing `gc … --json' call never blanks the
;; others (REQ-010):
;;
;; - cockpit        city name, controller state, health, counters and
;;                  store health — one `gc status' read, rendered by the
;;                  status dashboard's own header vnode.  gc exposes no
;;                  API URL in any `--json' payload yet, so the gap
;;                  renders as a dim "(api —)" placeholder, the same
;;                  em-dash convention as the status board's "(mode —)"
;;                  (ga-jhwz) — never a hand-parsed city.toml.
;; - work in flight in-progress beads joined to live sessions by
;;                  parsing the session handle out of the bead's
;;                  assignee (REQ-003) — the port of the SPA's
;;                  `work-in-flight.ts'.  A bead whose session is not
;;                  live (or whose assignee carries no recognizable
;;                  handle) degrades to an unjoined row.
;; - runs           the workflow-run census (REQ-014): one `gc bd list'
;;                  read, grouped client-side by `gc.graphv2_root_key' —
;;                  root vs step discrimination, per-run progress and
;;                  current step, closed runs excluded by default.  A run
;;                  row is stamped with its root bead id for `RET'.
;; - mail           the unread count from one `gc mail count' read,
;;                  rendered dim in the cockpit; `m' opens the existing
;;                  mail inbox (`default-directory' is pinned to the
;;                  city by the view factory, so the inbox scopes to
;;                  the same city).
;; - needs you      agents blocking the operator, exactly one reason and
;;                  one next action each (REQ-004) — the port of the
;;                  SPA's `needsYou.ts' minus the pending branch (`errored'
;;                  > `rate-limited' > `stalled'; reset/nudge; no clocks,
;;                  no age thresholds).  Pending interactions need the
;;                  supervisor API; out of scope by user directive, so
;;                  only the CLI-derivable reasons remain.  The section
;;                  count and the agent roster's highlighting read the
;;                  same selector output, so they cannot disagree.
;; - agents         the full `gc status' roster, needs-you rows marked.
;; - sessions       live sessions, the named-session derivation, and
;;                the run census from `gc status''s summary (REQ-006).
;; - beads          ready / in-progress / blocked beads plus convoys
;;                (REQ-007); `/` opens a filter transient.  `RET'
;;                opens a bead or convoy in beads.el, scoped to the
;;                store owning its id prefix (DESIGN.md §4.3).
;; - activity       the real events feed (plan S3): `gc events --since'
;;                read as JSON Lines through the reader's :lines mode,
;;                chatty types excluded by default (`/` → events
;;                submenu toggles), capped to the most recent
;;                `gascity-dashboard-events-limit' events; a decode
;;                error degrades to a dim inline line, never a blank.
;; - rigs           per-rig summary rows; `RET' opens the rig dashboard.
;;
;; Rendering contract (REQ-010): the skeleton with per-section pending
;;                state renders immediately; refresh is stale-while-
;;                revalidate (the last payload keeps rendering while a
;;                reload is pending; a pending section with nil data
;;                must not unmount its subtree); a failing section
;;                renders its error inline, dim, with a retry hint.
;;                No synchronous `gc' call anywhere in the module —
;;                even the tmux socket resolves from the payload via
;;                `gascity-resolve-tmux-socket''s `no-probe' mode.
;;
;;                Collapse state and the `/` bead filter are lifted to
;;                the root component, so they survive a refresh.
;;                `g' refreshes in place preserving point; `N'/`P'
;;                jump sections (inherited); the agent action keys
;;                (`d'/`t'/`i'/`M'/`s'/`K'/`w'/`D') mean the same thing
;;                here as in the status dashboard, rig dashboard and
;;                session detail (REQ-012, DESIGN-write-actions.md §10).
;;
;;                TRAMP parity (REQ-011): every read goes through the
;;                remote-aware reader plumbing; the buffer is created
;;                through `gascity-view-get-buffer-create' (host-
;;                qualified name, pinned `default-directory', I/O-free
;;                project instance); gc's reported paths are re-
;;                prefixed by the plumbing the status board already
;;                uses.  There are no local-path assumptions here.

;;; Code:

(require 'seq)
(require 'transient)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-context)            ; pin-directory (view keyed to its city)
(require 'gascity-domain)             ; typed objects + at-point visit generic
(require 'gascity-reader)             ; gascity-reader-read-async (per-section)
(require 'gascity-section)
(require 'gascity-tabulated)          ; shared cell formatters (--str)
(require 'gascity-status)             ; header vnode, session-map join

;; Detail/list openers and agent actions live in sibling modules loaded
;; alongside this one; reference them by name (resolved at call time).
(declare-function gascity-mail-inbox "gascity-tabulated")
(declare-function gascity-polecat-detail-at-point "gascity-session")
(declare-function gascity-rig-dashboard "gascity-rig")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")

;;; Buffer

(defconst gascity-dashboard-buffer-name "*gascity-dashboard*"
  "Base name of the city dashboard buffer.
The view-buffer factory (`gascity-view-get-buffer-create') qualifies it
with the city root for a local city and the TRAMP prefix for a remote
one, so dashboards of different cities — or of the same city in local
and remote access modes — coexist.")

;;; Pure selectors — the SPA projections, ported (REQ-003, REQ-004)

;; The trailing supervisor session-handle gate, ported from the SPA's
;; `work-in-flight.ts'.  The prefix is `gc'/`td'/`th' literally or any
;;                4-letter city code — deliberately narrower than the
;;                supervisor's own session-id gate — and the id body is
;;                tightened to `[a-z0-9]' (no internal hyphen) with at
;;                most 32 characters so the match binds to the MINIMAL
;;                trailing handle: without that, a role like
;;                `scix-worker' (whose `scix' is itself a 4-letter
;;                token) would let a greedy body swallow
;;                `scix-worker-gc-335812' whole.  A single rx anchored
;;                at end-of-string, tested against each boundary-
;;                delimited candidate.
(defconst gascity-dashboard--session-handle-rx
  "\\`\\(?:gc\\|td\\|th\\|[a-z]\\{4\\}\\)-[a-z0-9]\\{1,32\\}\\'"
  "The trailing supervisor session-handle gate, anchored at end-of-string.
Matches `gc-335825', `td-9abc', `th-1a2b' or `<4-letter-city-code>-<body>'.")

(defun gascity-dashboard--bare-session-id-p (value)
  "Return non-nil when VALUE itself is a bare supervisor session id.
The assignee IS a session id with no role prefix.  Same alphabet as
`gascity-dashboard--session-handle-rx' but whole-string, plus the id
body's at-least-one-digit rule: live session ids always carry a numeric
handle (`gc-335825', `td-9abc'), and requiring a digit keeps a plain
4-letter-prefixed *role* like `scix-worker' (prefix `scix' + body
`worker') from masquerading as one."
  (and (stringp value)
       (not (string-empty-p value))
       (string-match-p gascity-dashboard--session-handle-rx value)
       (let ((dash (string-search "-" value)))
         (and dash
              (string-match-p "[0-9]" (substring value (1+ dash)))))))

(defun gascity-dashboard--parse-assignee (assignee)
  "Split a bead ASSIGNEE into its worker role and embedded session id.
Returns (ROLE . SESSION-ID); SESSION-ID is nil when the assignee carries
no recognizable session handle, in which case ROLE is the whole (trimmed)
assignee.  Port of the SPA's `parseAssignee': a bare session id names the
row with the id itself; otherwise scan from the end of the string for the
first (`-'/`_'/`/') boundary whose remainder passes the session-handle
gate — the minimal trailing handle, so `scix-worker-gc-335812' yields
role `scix-worker' and id `gc-335812', never the whole string.  Pure over
strings."
  (let ((trimmed (and (stringp assignee) (string-trim assignee))))
    (cond
     ((not trimmed) (cons "" nil))
     ((gascity-dashboard--bare-session-id-p trimmed) (cons trimmed trimmed))
     (t
      (or (catch 'handle
            (let ((i (1- (length trimmed))))
              (while (>= i 0)
                (when (memq (aref trimmed i) '(?- ?_ ?/))
                  (let ((candidate (substring trimmed (1+ i))))
                    (unless (string-empty-p candidate)
                      (when (string-match-p
                             gascity-dashboard--session-handle-rx candidate)
                        (throw 'handle
                               (cons (substring trimmed 0 i) candidate))))))
                (setq i (1- i)))
              nil))
          (cons trimmed nil))))))

(defun gascity-dashboard--work-in-flight (bead-rows session-rows)
  "Join in-progress BEAD-ROWS to live SESSION-ROWS via the assignee parser.
BEAD-ROWS and SESSION-ROWS are the raw decoded payload alists of `gc bd
list --status in_progress' and `gc session list'.  A session row is live
when its state is \"active\" and it is not closed.  Returns one row per
bead, in payload order, each row

  (BEAD ROLE SESSION-ID SESSION)

where BEAD is the raw bead alist, ROLE/SESSION-ID the
`gascity-dashboard--parse-assignee' result and SESSION the live session
alist joined on the id, or nil — a bead whose session is not live, or
whose assignee carries no recognizable handle, degrades to an unjoined
row (SESSION-ID nil or SESSION nil).  A bead appears at most once (first
payload occurrence wins).  Port of the SPA's work-in-flight projection."
  (let ((live (make-hash-table :test 'equal))
        (seen (make-hash-table :test 'equal))
        (rows nil))
    (dolist (session (append session-rows nil))
      (let ((id (alist-get 'id session)))
        (when (and (stringp id) (not (string-empty-p id))
                   (equal (downcase (or (alist-get 'state session) ""))
                          "active")
                   (not (alist-get 'closed session)))
          (puthash id session live))))
    (dolist (bead (append bead-rows nil))
      (let* ((id (alist-get 'id bead))
             (parsed (gascity-dashboard--parse-assignee
                      (or (alist-get 'assignee bead) "")))
             (session-id (cdr parsed)))
        (when (and (stringp id) (not (string-empty-p id))
                   (not (gethash id seen)))
          (puthash id t seen)
          (push (list bead (car parsed) session-id
                      (and session-id (gethash session-id live)))
                rows))))
    (nreverse rows)))

;; Free-form supervisor `state' strings, matched case-insensitively —
;;                the SPA's `needsYou.ts' sets, so the dashboard
;;                classifies a state the same way the web SPA does.
(defconst gascity-dashboard--failure-states
  '("failed" "errored" "stuck" "crashed")
  "Supervisor states that mean the agent exited in a failure state.")

(defconst gascity-dashboard--rate-limited-states
  '("rate-limited" "rate_limited" "waiting")
  "Supervisor states that mean the agent is throttled by a provider limit.")

(defconst gascity-dashboard--needs-you-actions
  '(("errored" . "reset")
    ("rate-limited" . "nudge")
    ("stalled" . "nudge"))
  "The one next operator step for each needs-you reason.
No reply action exists: pending interactions need the supervisor API;
out of scope by user directive.")

(defun gascity-dashboard--needs-you-reason (agent)
  "Return the one needs-you reason for AGENT, or nil when it blocks nobody.
AGENT is a raw `gc status' agent entry, optionally enriched with a
`state' string and a `session' id (nil when it has no live session) by
the dashboard's join.  First match wins: errored > rate-limited >
stalled.  There is deliberately no pending-interaction reason: the
data plane is the `gc' CLI, and pending interactions need the
supervisor API — out of scope by user directive."
  (let ((state (downcase (or (alist-get 'state agent) ""))))
    (cond ((member state gascity-dashboard--failure-states) "errored")
          ((member state gascity-dashboard--rate-limited-states)
           "rate-limited")
          ((gascity-dashboard--stalled-p agent state) "stalled"))))

(defun gascity-dashboard--stalled-p (agent state)
  "Return non-nil when AGENT is stalled: detached, or running with no session.
STATE is AGENT's lowercased `state' (\"\" when absent).  A detached agent
lost its session; one claiming to run with no live session backing the
claim is stalled by definition.  No clocks, no age thresholds."
  (or (equal state "detached")
      (and (alist-get 'running agent)
           (not (alist-get 'session agent)))))

(defun gascity-dashboard--needs-you-detail (agent reason)
  "Return the structural why-phrase for AGENT's needs-you REASON.
Mirrors the SPA's `needsYouDetail' minus its pending branch: pending
interactions need the supervisor API; out of scope by user directive."
  (let ((state (downcase (or (alist-get 'state agent) ""))))
    (pcase reason
      ("errored" (format "Exited %s." (or (alist-get 'state agent) "?")))
      ("rate-limited" "Throttled by a provider limit.")
      ("stalled" (if (equal state "detached")
                     "Detached from its session."
                   "Running with no live session.")))))

(defun gascity-dashboard--needs-you (agents)
  "Project the AGENTS roster into the rows that need the operator.
AGENTS is a list (or vector) of raw `gc status' agent entries, optionally
enriched with `state'/`session' keys.  Returns one (NAME REASON DETAIL
ACTION) row per blocking agent, NAME being the qualified name, in roster
order.  The badge and section counts read this same output, so a badge
and its page cannot disagree (REQ-004).  Port of the SPA's `needsYou.ts'
minus its pending branch — no clock, no age threshold, nothing that can
flap, and nothing the CLI data plane cannot derive."
  (let ((rows nil))
    (dolist (agent (append agents nil) (nreverse rows))
      (let* ((name (alist-get 'qualified_name agent))
             (reason (gascity-dashboard--needs-you-reason agent)))
        (when reason
          (push (list name
                      reason
                      (gascity-dashboard--needs-you-detail agent reason)
                      (cdr (assoc reason gascity-dashboard--needs-you-actions)))
                rows))))))

;;; Data shaping (pure)

(defun gascity-dashboard--agent-session-id (agent session-rows)
  "Return the live session id joined to AGENT from SESSION-ROWS.
AGENT is a raw `gc status' agent entry; the join key is its qualified
name against the session rows' `agent_name' — the same join the status
board's session map uses.  SESSION-ROWS hold the RAW `gc session list'
alists (the work-in-flight selector's shape — the typed decode never
keeps the payload's `id', which is what the enrichment records), already
narrowed to live rows (state \"active\", not closed)."
  (let ((qname (alist-get 'qualified_name agent)))
    (when (stringp qname)
      (seq-find (lambda (s) (equal (alist-get 'agent_name s) qname))
                (append session-rows nil)))))

;; Workflow-run projection (REQ-014)
;;
;; A workflow run is a bead whose metadata carries `gc.graphv2_root_key';
;; steps carry the same key plus `gc.root_bead_id'.  Root vs step is
;; decided by the verified live shape: roots carry `gc.kind: workflow'
;; (the tracker the steps TRACK); when `gc.kind' is absent the fallback
;; is the same key WITHOUT `gc.root_bead_id' — roots have no step anchor.

(defun gascity-dashboard--bead-meta (bead)
  "Return BEAD's raw metadata alist (nil when absent)."
  (let ((meta (alist-get 'metadata bead)))
    (and (listp meta) meta)))

(defun gascity-dashboard--root-key (bead)
  "Return BEAD's `gc.graphv2_root_key' metadata value, or nil."
  (alist-get 'gc.graphv2_root_key (gascity-dashboard--bead-meta bead)))

(defun gascity-dashboard--run-root-p (bead)
  "Return non-nil when BEAD is a workflow-run root.
Verified live: roots carry `gc.kind: workflow'; the fallback for a
metadata shape without `gc.kind' is the same root key WITHOUT
`gc.root_bead_id' (a root tracks its steps, it is not one)."
  (and (gascity-dashboard--root-key bead)
       (or (equal (alist-get 'gc.kind (gascity-dashboard--bead-meta bead))
                  "workflow")
           (not (alist-get 'gc.root_bead_id
                           (gascity-dashboard--bead-meta bead))))))

(defun gascity-dashboard--run-current-step (steps)
  "Return the first non-closed STEP with a non-empty `assignee', or nil.
STEPS is the run's step-bead list, payload order — the graph's own
readiness order.  Pure over the raw decoded alists."
  (seq-find (lambda (step)
              (and (not (equal (alist-get 'status step) "closed"))
                   (let ((assignee (alist-get 'assignee step)))
                     (and (stringp assignee) (not (string-empty-p assignee))))))
            (append steps nil)))

(defun gascity-dashboard--workflow-runs (bead-rows)
  "Group raw BEAD-ROWS into workflow-run rows, keyed by `gc.graphv2_root_key'.
BEAD-ROWS is the raw decoded `gc bd list --json' payload (a bare array
or an `issues'-wrapped object).  One row per run root, payload order:

  (ROOT CLOSED TOTAL CURRENT UPDATED)

where ROOT is the raw root bead alist, CLOSED/TOTAL the closed/total
step counts (steps = beads sharing the root's `gc.graphv2_root_key'
that are NOT run roots — verified live, every step carries
`gc.root_bead_id'), CURRENT the first non-closed step with a non-empty
`assignee' (nil when none — the run's steps are queued or closed), and
UPDATED the root's raw `updated_at'.  Runs whose root is closed are
EXCLUDED from the default view (the caller surfaces a dim \"N closed
runs\" line); steps with no root in the payload are skipped.  Pure over
the decoded payload (REQ-014)."
  (let* ((beads (append (if (vectorp bead-rows)
                            bead-rows
                          (or (alist-get 'issues bead-rows) bead-rows))
                        nil))
         (steps (make-hash-table :test 'equal))
         (roots nil)
         (seen (make-hash-table :test 'equal))
         (root-keys (make-hash-table :test 'equal))
         (closed-runs 0)
         (rows nil))
    (dolist (bead beads)
      (let ((key (gascity-dashboard--root-key bead)))
        (when (and key (not (gethash bead seen)))
          (puthash bead t seen)
          (if (gascity-dashboard--run-root-p bead)
              (unless (gethash key root-keys)
                (puthash key t root-keys)
                (push bead roots))
            (let* ((root-id (alist-get 'gc.root_bead_id
                                       (gascity-dashboard--bead-meta bead)))
                   (bucket (gethash root-id steps)))
              (puthash root-id (cons bead (or bucket nil)) steps))))))
    (dolist (root (nreverse roots) (list :rows (nreverse rows)
                                         :closed-count closed-runs))
      (let* ((steps-of-run (append (gethash (alist-get 'id root) steps) nil))
             (closed (seq-count (lambda (step)
                                  (equal (alist-get 'status step) "closed"))
                                steps-of-run)))
        (if (equal (alist-get 'status root) "closed")
            (setq closed-runs (1+ closed-runs))
          (push (list root
                      closed
                      (length steps-of-run)
                      (gascity-dashboard--run-current-step steps-of-run)
                      (alist-get 'updated_at root))
                rows))))))

(defun gascity-dashboard--run-row (row)
  "Return a vnode for one workflow-run ROW (see `--workflow-runs').
Columns: run id, formula, phase, progress closed/total, current step
(id), updated.  The row is stamped with the root bead id under
`gascity-bead', so `RET' lands on the run (the S2 drill-in's hook).
Missing pieces render as em dashes, the dashboard's established
gap-marker convention."
  (let* ((root (nth 0 row))
         (closed (nth 1 row))
         (total (nth 2 row))
         (current (nth 3 row))
         (updated (nth 4 row))
         (meta (gascity-dashboard--bead-meta root))
         (id (gascity-tabulated--str (alist-get 'id root))))
    (vui-text
     (format "  %-12s %-16s %-12s %s/%-4s %-12s %s"
             id
             (or (alist-get 'gc.formula_name meta) "—")
             (gascity-tabulated--str (alist-get 'status root))
             (or closed 0)
             (or total 0)
             (if current
                 (gascity-tabulated--str (alist-get 'id current))
               "—")
             (if (and (stringp updated) (not (string-empty-p updated)))
                 (substring updated 0 (min 16 (length updated)))
               "—"))
     :face (gascity-section-state-face
            (member (gascity-tabulated--str (alist-get 'status root))
                    '("in_progress" "active"))
            nil)
     'gascity-bead id)))

(defun gascity-dashboard--bead-in-filter-p (bead prefix)
  "Return non-nil when BEAD passes the rig-prefix PREFIX filter.
A nil PREFIX (the \"all\" filter) passes everything; otherwise the bead's
id must carry that prefix (`ga-…' for the gascity.el rig, say)."
  (or (not prefix)
      (let ((id (alist-get 'id bead)))
        (and (stringp id) (string-prefix-p prefix id)))))

(defun gascity-dashboard--rig-prefix (rig-name rigs)
  "Return rig RIG-NAME's bead prefix from the RIGS alists, or nil."
  (when-let* ((rig (seq-find (lambda (r) (equal (alist-get 'name r) rig-name))
                             (append rigs nil))))
    (alist-get 'prefix rig)))

;;; Rendering (vnodes)

(defun gascity-dashboard--effective-load (res ref)
  "Return the normalized load plist for async result RES with snapshot REF.
`ready' adopts fresh data (and refreshes the REF cache); any other state
keeps rendering the cached snapshot — the stale-while-revalidate rule —
and only reports `error'/`pending' when no snapshot is in hand.  When a
refresh FAILED over a good snapshot the error rides along in `:error',
so the section renders its stale rows AND the failure dimly, with a
retry hint — a failing section never swallows its error.  A pending
state with nil data must not unmount a section: callers render the
section header regardless and a loading line inside."
  (let ((state (plist-get res :status)))
    (cond ((eq state 'ready)
           (list :state 'ready :data (setcar ref (plist-get res :data))))
          ((car ref)
           (list :state 'stale :data (car ref)
                 :error (and (eq state 'error) (plist-get res :error))))
          ((eq state 'error)
           (list :state 'error :error (plist-get res :error)))
          (t (list :state 'pending)))))

(defun gascity-dashboard--header (name label &optional count collapsed)
  "Return the section header vnode for section NAME.
LABEL is the display title, COUNT the row count (nil renders a `?'), and
COLLAPSED whether the section is collapsed.  The header is stamped with
`gascity-section' (the `N'/`P' navigation property) and with
`gascity-dashboard-section' NAME (the collapse toggle's identity, lifted
to the root component so it survives a refresh)."
  (vui-text (format "%s %s%s" (if collapsed "▶" "▼") label
                    (format " (%s)" (or count "?")))
            :face 'gascity-header
            'gascity-section t
            'gascity-dashboard-section name))

(defun gascity-dashboard--section-body (load rows-fn)
  "Return the body vnodes for a section load and its ROWS-FN.
LOAD is a `gascity-dashboard--effective-load' plist; ROWS-FN receives the
load's data when usable data is in hand (fresh or stale) and returns the
row vnodes.  A first, dataless load renders a pending line; a failed one
renders the error dimly, with a retry hint — a failing section never
swallows its error nor blanks the dashboard (REQ-010).  When the load
holds a stale snapshot over a failed refresh, the rows keep rendering
and the error is appended dimly below them."
  (append
   (pcase (plist-get load :state)
     ('pending (list (vui-text "  loading…" :face 'gascity-dim)))
     ('error
      (list (vui-text (format "  gc error: %s"
                              (or (plist-get load :error) "?"))
                      :face 'gascity-dim)
            (vui-text "  press g to retry" :face 'gascity-dim)))
     (_ (or (and rows-fn (funcall rows-fn (plist-get load :data)))
            (list (vui-text "  (none)" :face 'gascity-dim)))))
   (and (plist-get load :error)
        (eq (plist-get load :state) 'stale)
        (list (vui-text (format "  gc error: %s (showing last good data)"
                                (or (plist-get load :error) "?"))
                        :face 'gascity-dim)
              (vui-text "  press g to retry" :face 'gascity-dim)))))

(defun gascity-dashboard--section (name label load collapsed rows-fn &optional count-fn)
  "Return a full section vnode: header plus body.
NAME/LABEL/COLLAPSED as in `gascity-dashboard--header'; LOAD a
`gascity-dashboard--effective-load' plist; ROWS-FN the body builder.  The
header count is COUNT-FN applied to the load's data (default: its
length), so a count and the rows it counts always come from the same
payload — computed whenever the load holds usable data, so an empty
section reads \"(0)\", not a missing count.  A collapsed section still
renders its header — `N'/`P' keep working and the count stays visible."
  (let ((count (and (memq (plist-get load :state) '(ready stale))
                    (funcall (or count-fn #'length)
                             (plist-get load :data)))))
    (apply #'vui-vstack
           (gascity-dashboard--header name label count collapsed)
           (unless collapsed
             (gascity-dashboard--section-body load rows-fn)))))

(defun gascity-dashboard--cockpit-vnode (status mail-count)
  "Return the cockpit section vnode for STATUS and MAIL-COUNT.
STATUS is the `gc status' payload; the header vnode (city, controller,
health, counters, store health) is the status dashboard's own, fed by
one async read (REQ-002).  MAIL-COUNT is the `gc mail count' payload
(total/unread) — a dim header line whose unread count the mail inbox
(`m') acts on.  The API URL and a costs surface appear in no `gc --json'
payload yet (`gc costs --json' is json_unsupported), so both render as
dim pointers rather than fake or hand-parsed data (ga-jhwz convention)."
  (vui-vstack
   (gascity-status--header-vnode status)
   (vui-text (format "  mail %s unread"
                     (or (alist-get 'unread mail-count) 0))
             :face 'gascity-dim)
   (vui-text "  api — (gc exposes no API URL in --json yet)"
             :face 'gascity-dim)
   (vui-text "  costs — run `gc costs' in a shell; no JSON surface"
             :face 'gascity-dim)))

(defun gascity-dashboard--agent-for (session-alist socket)
  "Return the action `gascity-agent' for a raw live SESSION-ALIST.
SOCKET is the city's tmux socket.  The session payload's `id' is not a
`gascity-session' slot, so rows carrying a live id build their action
object straight from the raw alist (the work-in-flight join's shape)."
  (make-instance 'gascity-agent
                 :name (or (alist-get 'agent_name session-alist)
                           (alist-get 'name session-alist))
                 :rig (alist-get 'rig session-alist)
                 :work-dir (alist-get 'work_dir session-alist)
                 :session-name (alist-get 'session_name session-alist)
                 :socket socket
                 :running (equal (downcase (or (alist-get 'state
                                                          session-alist)
                                               ""))
                                 "active")))

(defun gascity-dashboard--wif-row (row socket)
  "Return a vnode for one work-in-flight ROW on tmux SOCKET.
ROW is a `gascity-dashboard--work-in-flight' entry (BEAD ROLE SESSION-ID
SESSION).  A joined row names the session and carries both the action
agent (`d'/`t'/`i'/`M'/`s'/`K'/`w'/`D') and the bead id (`RET' opens the
bead in beads.el); an unjoined row degrades to its role and no session."
  (let* ((bead (nth 0 row))
         (role (nth 1 row))
         (session-id (nth 2 row))
         (session (nth 3 row))
         (id (gascity-tabulated--str (alist-get 'id bead)))
         (title (gascity-tabulated--str (alist-get 'title bead)))
         (who (or role "?")))
    (if session
        (vui-text (format "  %-10s %-38s → %s %s" id who
                          (gascity-tabulated--str
                           (or (alist-get 'agent_name session)
                               (alist-get 'name session)
                               session-id))
                          title)
                  'gascity-agent (gascity-dashboard--agent-for session socket)
                  'gascity-bead id)
      (vui-text (format "  %-10s %-38s   %s" id who title)
                'gascity-bead id))))

(defun gascity-dashboard--needs-you-row (row agent-map)
  "Return a vnode for one needs-you ROW.
ROW is (NAME REASON DETAIL ACTION).  The row carries the joined action
`gascity-agent' from AGENT-MAP (keyed on qualified name, as the status
board builds it) so the standard action keys work on it; a name with no
roster entry renders without an action object."
  (let ((name (nth 0 row)))
    (vui-text (format "  %s — %s (%s) → %s" name (nth 1 row)
                      (nth 2 row) (nth 3 row))
              :face 'gascity-failed
              'gascity-agent (gethash name agent-map))))

(defun gascity-dashboard--agent-row (agent needs-you-map session-map socket)
  "Return a roster vnode for AGENT, marking it when NEEDS-YOU-MAP flags it.
NEEDS-YOU-MAP is the hash of the `gascity-dashboard--needs-you' output —
the SAME selector output the needs-you section renders — so the roster's
highlight and the needs-you count cannot disagree (REQ-004).  The row
carries the action `gascity-agent' (joined with SESSION-MAP, tmux SOCKET)
for the shared action keys."
  (let* ((qname (alist-get 'qualified_name agent))
         (running (alist-get 'running agent))
         (suspended (alist-get 'suspended agent))
         (reason (and qname (gethash qname needs-you-map)))
         (obj (gascity-status--agent agent nil session-map socket)))
    (if reason
        (vui-text (format "  ● !%s %s" (nth 1 reason) qname)
                  :face 'gascity-failed
                  'gascity-agent obj)
      (vui-text (format "  %s %s" (if running "●" "○")
                        (or qname (alist-get 'name agent) "?"))
                :face (gascity-section-state-face running suspended)
                'gascity-agent obj))))

(defun gascity-dashboard--session-row (session socket)
  "Return a vnode for a live typed SESSION row on tmux SOCKET."
  (vui-text (format "  ● %-38s %-8s %s"
                    (gascity-session-qualified-name session)
                    (or (gascity-session-state session) "?")
                    (or (gascity-session-provider session) ""))
            :face 'gascity-running
            'gascity-agent (gascity-agent-from-session session socket)))

(defun gascity-dashboard--bead-row (bead)
  "Return a vnode for BEAD, stamped with its id for `RET'."
  (let ((id (gascity-tabulated--str (alist-get 'id bead))))
    (vui-text (format "  %-12s %-12s %s"
                      id
                      (gascity-tabulated--str (alist-get 'status bead))
                      (gascity-tabulated--str (alist-get 'title bead)))
              'gascity-bead id)))

(defun gascity-dashboard--convoy-row (convoy)
  "Return a vnode for a raw CONVOY alist, stamped with its id for `RET'.
A convoy is a bead: `RET' opens it in beads.el like any other id
(DESIGN.md §4.3), scoped to the store owning its prefix."
  (let* ((id (gascity-tabulated--str (alist-get 'id convoy)))
         (progress (alist-get 'progress convoy))
         (done (alist-get 'closed progress))
         (total (alist-get 'total progress)))
    (vui-text (format "  %-12s %-12s %s/%s  %s"
                      id
                      (gascity-tabulated--str (alist-get 'status convoy))
                      (or done "?") (or total "?")
                      (gascity-tabulated--str (alist-get 'title convoy)))
              'gascity-bead id)))

(defun gascity-dashboard--bead-group (title load filter-prefix rows-fn)
  "Return the vnodes for one bead sub-group under the Beads section.
TITLE is the sub-group label (\"Ready\"…); LOAD the group's normalized
load; FILTER-PREFIX the active rig prefix (nil = all); ROWS-FN builds the
rows from the payload's bead list.  The filter is applied here, so a
`/` rig filter narrows every group from one place."
  (let* ((beads (seq-filter (lambda (b)
                              (gascity-dashboard--bead-in-filter-p b filter-prefix))
                            (and rows-fn (plist-get load :data)
                                 (funcall rows-fn (plist-get load :data)))))
         (count (length beads)))
    (apply #'vui-vstack
           (vui-text (format "  %s (%d)" title count)
                     :face 'gascity-header)
           (pcase (plist-get load :state)
             ('pending (list (vui-text "    loading…" :face 'gascity-dim)))
             ('error
              (list (vui-text (format "    gc error: %s"
                                      (or (plist-get load :error) "?"))
                              :face 'gascity-dim)
                    (vui-text "    press g to retry" :face 'gascity-dim)))
             (_ (or (mapcar #'gascity-dashboard--bead-row beads)
                    (list (vui-text "    (none)" :face 'gascity-dim)))))
           (and (plist-get load :error)
                (eq (plist-get load :state) 'stale)
                (list (vui-text (format "    gc error: %s (showing last good data)"
                                        (or (plist-get load :error) "?"))
                                :face 'gascity-dim)
                      (vui-text "    press g to retry" :face 'gascity-dim))))))

(defun gascity-dashboard--rig-row (rig)
  "Return a vnode for the typed RIG row; `RET' opens its dashboard."
  (let ((name (gascity-rig-name rig)))
    (vui-text (format "  %-16s prefix %-6s %s"
                      name
                      (or (gascity-rig-prefix rig) "—")
                      (or (gascity-rig-path rig) ""))
              :face (gascity-section-state-face
                     (gascity-rig-running rig)
                     (gascity-rig-suspended rig))
              'gascity-rig name)))

;;; Activity feed (events JSONL, plan S3)

(defcustom gascity-dashboard-events-limit 500
  "Maximum number of recent events the Activity section renders.
The cap keeps the MOST RECENT events (the payload's tail — `gc events'
emits ascending sequence numbers); anything older is summarized in a
dim trailing \"N older events hidden\" line."
  :type 'natnum
  :group 'gascity)

(defconst gascity-dashboard--events-chatty-default
  '("order.fired" "order.completed" "bead.updated")
  "The chatty event types the Activity feed excludes by default.
Toggled as a set by `gascity-dashboard-events-toggle-chatty'.")

(defun gascity-dashboard--events-visible (events excluded)
  "Return EVENTS in payload order, minus the EXCLUDED types.
EVENTS are the decoded `gc events' JSONL alists."
  (seq-filter (lambda (event)
                (not (member (alist-get 'type event) excluded)))
              events))

(defun gascity-dashboard--events-cap (events limit)
  "Return the most recent LIMIT events, payload order preserved.
Events arrive oldest-first (ascending `seq'), so the cap keeps the
tail.  A nil LIMIT or a shorter list passes through unchanged."
  (if (and limit (> (length events) limit))
      (nthcdr (- (length events) limit) events)
    events))

(defun gascity-dashboard--events-view (data excluded limit)
  "Project the JSONL events payload DATA into the rendered view.
DATA is the reader's (EVENTS . BAD) cons — EVENTS the decoded
per-line alists in feed order, BAD the count of malformed lines.  A
nil or non-cons payload (still pending, or an unexpected shape)
degrades to an empty feed — never an error.  Returns a plist
\(:events :hidden :bad): :events the EXCLUDED-type-filtered events
capped to the most recent LIMIT, :hidden how many visible events the
cap dropped, :bad the payload's malformed-line count."
  (let* ((events (and (consp data) (append (car data) nil)))
         (visible (gascity-dashboard--events-visible events excluded))
         (capped (gascity-dashboard--events-cap visible limit)))
    (list :events capped
          :hidden (- (length visible) (length capped))
          :bad (or (and (consp data) (cdr data)) 0))))

(defun gascity-dashboard--event-ts (event)
  "Return EVENT's ts formatted HH:MM:SS, or the raw value.
`gc events' emits RFC3339 with nanoseconds and an offset
\(\"2026-09-24T13:59:12.293914966+02:00\"); only the clock time is
rendered.  A missing or unexpected shape degrades to the raw value."
  (let ((ts (alist-get 'ts event)))
    (if (and (stringp ts)
             (string-match
              "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T\\([0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\)"
              ts))
        (match-string 1 ts)
      ts)))

(defun gascity-dashboard--event-summary (event)
  "Return the first line of EVENT's payload summary, or nil.
The payload's `title' wins over `summary'; only a non-empty first line
counts.  A payload of an unexpected shape (a JSON scalar) degrades to
no summary."
  (let* ((payload (alist-get 'payload event))
         (text (and (listp payload)
                    (or (alist-get 'title payload)
                        (alist-get 'summary payload)))))
    (when (stringp text)
      (let ((line (string-trim (car (split-string text "\n")))))
        (unless (string-empty-p line) line)))))

(defun gascity-dashboard--event-row (event)
  "Return one Activity row vnode for EVENT.
Columns: clock time (HH:MM:SS), type, subject, then the first line of
the payload's title/summary when present.  An event whose `ok' is nil
renders in the failed face."
  (let* ((summary (gascity-dashboard--event-summary event))
         (text (format "  %-8s %-18s %s%s"
                       (or (gascity-dashboard--event-ts event) "?")
                       (or (alist-get 'type event) "?")
                       (or (alist-get 'subject event) "?")
                       (if summary (concat " — " summary) ""))))
    (if (alist-get 'ok event)
        (vui-text text)
      (vui-text text :face 'gascity-failed))))

(defun gascity-dashboard--events-rows (view)
  "Return the Activity section's body vnodes for the processed VIEW.
A trailing dim line reports events hidden by the limit cap; a
non-zero malformed-line count renders a dim inline line — a decode
error degrades the feed, never blanks it.  VIEW may be nil (the
section's first, dataless render): empty body, the \"(none)\" line."
  (let ((events (plist-get view :events))
        (hidden (plist-get view :hidden))
        (bad (plist-get view :bad)))
    (append (mapcar #'gascity-dashboard--event-row events)
            (and hidden (> hidden 0)
                 (list (vui-text
                        (format "  %d older events hidden" hidden)
                        :face 'gascity-dim)))
            (and bad (> bad 0)
                 (list (vui-text
                        (format "  %d malformed event lines skipped" bad)
                        :face 'gascity-dim))))))

;;; Component

(vui-defcomponent gascity-dashboard-app ()
  "Root component of the city dashboard."
  ;; Collapse state (`collapsed'), the `/` bead filter (`bead-rig') and
  ;; the Activity feed's excluded event types (`event-types-excluded')
  ;; live here, in the root component, rather than per section: the
  ;; keymap commands (`gascity-dashboard-activate',
  ;; `gascity-dashboard-filter-*') flip them and all survive an
  ;; in-place refresh, since `g' only bumps `refresh-tick'.
  :state ((refresh-tick 0) (collapsed nil) (bead-rig nil)
          (event-types-excluded
           '("order.fired" "order.completed" "bead.updated")))
  :render
  ;; All async hooks run unconditionally, in order, every render.  Each
  ;; section's load is independent: one failure never blanks the others.
  (let* ((status-res
          (vui-use-async (list 'status refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("status") resolve reject))))
         (mail-res
          (vui-use-async (list 'mail-count refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("mail" "count") resolve reject))))
         (sessions-res
          (vui-use-async (list 'sessions refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("session" "list") resolve reject))))
         (ready-res
          (vui-use-async (list 'ready refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("bd" "ready") resolve reject))))
         (inprog-res
          (vui-use-async (list 'inprog refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("bd" "list" "--status" "in_progress")
                            resolve reject))))
         (blocked-res
          (vui-use-async (list 'blocked refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("bd" "list" "--status" "blocked")
                            resolve reject))))
         (convoy-res
          (vui-use-async (list 'convoy refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("convoy" "list") resolve reject))))
         ;; The Activity feed: JSON Lines, not one --json payload
         ;; (plan S3).  Same per-section independence as every other
         ;; read; a malformed line is a decode-error count in the
         ;; payload, a read failure the standard dim error line.
         (events-res
          (vui-use-async (list 'events refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("events" "--since" "2h") resolve reject
                            :lines t))))
         (status-state (plist-get status-res :status))
         (last-status (vui-use-ref nil))
         (last-mail (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         (last-ready (vui-use-ref nil))
         (last-inprog (vui-use-ref nil))
         (last-blocked (vui-use-ref nil))
         (last-convoy (vui-use-ref nil))
         (last-events (vui-use-ref nil))
         ;; Stale-while-revalidate: on `ready' adopt fresh data, else
         ;; keep rendering the last snapshot (see
         ;; `gascity-dashboard--effective-load').
         (status (gascity-dashboard--effective-load status-res last-status))
         (mail-count (gascity-dashboard--effective-load mail-res last-mail))
         (sessions-load (gascity-dashboard--effective-load sessions-res
                                                           last-sessions))
         (ready-load (gascity-dashboard--effective-load ready-res
                                                        last-ready))
         (inprog-load (gascity-dashboard--effective-load inprog-res
                                                         last-inprog))
         (blocked-load (gascity-dashboard--effective-load blocked-res
                                                          last-blocked))
         (convoy-load (gascity-dashboard--effective-load convoy-res
                                                         last-convoy))
         (events-load (gascity-dashboard--effective-load events-res
                                                         last-events)))
    (cond
     ((and (eq status-state 'error) (null (plist-get status :data)))
      (gascity-status--error-vnode (plist-get status-res :error)))
     ((and (eq status-state 'pending) (null (plist-get status :data)))
      (vui-text "Loading city dashboard…" :face 'gascity-dim))
     (t
      (gascity-dashboard--content-vnode
       (plist-get status :data) (plist-get mail-count :data)
       sessions-load ready-load inprog-load
       blocked-load convoy-load
       :collapsed collapsed :bead-rig bead-rig
       :events-load events-load
       :event-types-excluded event-types-excluded)))))

(cl-defun gascity-dashboard--content-vnode (status mail-count sessions-load
                                            ready-load inprog-load
                                            blocked-load convoy-load
                                            &key collapsed bead-rig
                                            events-load event-types-excluded)
  "Return the dashboard body vnode.
STATUS is the `gc status' payload; MAIL-COUNT the `gc mail count'
payload (unread count for the cockpit header); the five LOAD arguments
are the normalized loads of `gc session list', `gc bd ready', the
in-progress and blocked `gc bd list' reads and `gc convoy list'.  The
Runs section reuses the in-progress load's full `gc bd list' payload
(REQ-014: zero extra reads; the in-progress read carries every run and
step for the small stores this view targets).  EVENTS-LOAD is the
normalized JSONL events load; EVENT-TYPES-EXCLUDED the Activity feed's
excluded types (root state, survives a refresh).  COLLAPSED is the
root's list of collapsed section names; BEAD-RIG the active `/` rig
filter (a rig name, or nil for all).  Each section renders from its own
load, so a failing one degrades alone (REQ-010); the needs-you rows are
computed once per render and feed both the needs-you section and the
roster's highlighting (REQ-004's single-selector rule)."
  (let* (;; The full in-progress `gc bd list' payload, decoded to bead rows
         ;; once: the Runs section groups it into workflow runs (REQ-014,
         ;; one read serving both sections).
         (beads-load (list :state (plist-get inprog-load :state)
                           :error (plist-get inprog-load :error)
                           :data (and (plist-get inprog-load :data)
                                      (gascity-section-beads
                                       (plist-get inprog-load :data)))))
         ;; Decode the session rows once: the typed list feeds the session
         ;; section, the named-session derivation and the join map.
         (sessions (and (plist-get sessions-load :data)
                        (alist-get 'sessions (plist-get sessions-load :data))))
         (session-rows (gascity-domain-decode-list 'gascity-session
                                                   (or sessions [])))
         (live-rows (seq-filter #'gascity-session-running-p session-rows))
         (session-map (gascity-status--session-map-rows session-rows))
         (named-sessions
          (gascity-domain-named-sessions-from-sessions session-rows))
         (agents (append (alist-get 'agents status) nil))
         (rigs (gascity-rigs-remember
                (gascity-domain-decode-list
                 'gascity-rig (alist-get 'rigs status))))
         ;; Render: no synchronous gc fallback (`no-probe').
         (socket (gascity-resolve-tmux-socket
                  (alist-get 'city_name status) 'no-probe))
         ;; The RAW session alists: the enrichment joins on them (their
         ;; `id' is the live session handle the needs-you stall test
         ;; needs) and the work-in-flight selector consumes the same
         ;; list — the typed decode exists alongside, never instead.
         (raw-session-rows
          (append (alist-get 'sessions (plist-get sessions-load :data)) nil))
         ;; Enrich the roster with each agent's live session id (nil when
         ;; none), then run the ONE needs-you selector whose output both
         ;; the needs-you section and the roster highlight read.
         (enriched (mapcar (lambda (agent)
                             (let ((session (gascity-dashboard--agent-session-id
                                             agent raw-session-rows)))
                               (append agent
                                       (list (cons 'session
                                                   (and session
                                                        (alist-get 'id session)))))))
                           agents))
         (needs-you-rows (gascity-dashboard--needs-you enriched))
         (needs-you-map (make-hash-table :test 'equal))
         (filter-prefix (gascity-dashboard--rig-prefix bead-rig
                                                       (alist-get 'rigs status))))
    (dolist (row needs-you-rows)
      (puthash (nth 0 row) row needs-you-map))
    (vui-vstack
     :spacing 1
     (gascity-dashboard--cockpit-vnode status mail-count)
     (gascity-dashboard--section
      "runs" "Runs"
      (list :state (plist-get beads-load :state)
            :error (plist-get beads-load :error)
            :data (and (plist-get beads-load :data)
                       (gascity-dashboard--workflow-runs
                        (plist-get beads-load :data))))
      (member "runs" collapsed)
      (lambda (result)
        (append
         (mapcar #'gascity-dashboard--run-row (plist-get result :rows))
         (and (plist-get result :closed-count)
              (> (plist-get result :closed-count) 0)
              (list (vui-text
                     (format "  %d closed run%s hidden"
                             (plist-get result :closed-count)
                             (if (= (plist-get result :closed-count) 1)
                                 "" "s"))
                     :face 'gascity-dim)))))
      (lambda (result) (length (plist-get result :rows))))
     (gascity-dashboard--section
      "work" "Work in flight"
      (list :state (plist-get inprog-load :state)
            :error (plist-get inprog-load :error)
            :data (gascity-dashboard--work-in-flight
                   (and (plist-get inprog-load :data)
                        (gascity-section-beads (plist-get inprog-load :data)))
                   raw-session-rows))
      (member "work" collapsed)
      (lambda (rows) (mapcar (lambda (row)
                               (gascity-dashboard--wif-row row socket))
                             rows)))
     (gascity-dashboard--section
      "needs-you" "Needs you" (list :state 'ready :data needs-you-rows)
      (member "needs-you" collapsed)
      (lambda (rows)
        (let ((agent-map (make-hash-table :test 'equal)))
          ;; action objects from the session join
          (dolist (s live-rows agent-map)
            (puthash (gascity-session-qualified-name s)
                     (gascity-agent-from-session s socket)
                     agent-map))
          (mapcar (lambda (row)
                    (gascity-dashboard--needs-you-row row agent-map))
                  rows)))
      #'length)
     (gascity-dashboard--section
      "agents" "Agents" (list :state 'ready :data agents)
      (member "agents" collapsed)
      (lambda (rows) (mapcar (lambda (agent)
                               (gascity-dashboard--agent-row
                                agent needs-you-map session-map socket))
                             rows)))
     (gascity-dashboard--section
      "sessions" "Sessions" sessions-load
      (member "sessions" collapsed)
      (lambda (data)
        (let ((summary (alist-get 'summary data)))
          (append
           (list (vui-text (format "  agents %s/%s running · sessions %s"
                                   (or (alist-get 'running_agents
                                                  (alist-get 'summary status))
                                       0)
                                   (or (alist-get 'total_agents
                                                  (alist-get 'summary status))
                                       0)
                                   (gascity-status--sessions-label
                                    status summary))
                           :face 'gascity-dim))
           (mapcar (lambda (s) (gascity-dashboard--session-row s socket))
                   live-rows)
           (when named-sessions
             (cons (vui-text "  Named sessions" :face 'gascity-dim)
                   (mapcar (lambda (named)
                             (gascity-status--named-session-row
                              named socket))
                           named-sessions))))))
      (lambda (_) (length live-rows)))
     (vui-vstack
      (gascity-dashboard--header "beads" "Beads"
                                 (and (or (plist-get ready-load :data)
                                          (plist-get inprog-load :data)
                                          (plist-get blocked-load :data))
                                      (format "/%s" (or bead-rig "all")))
                                 (member "beads" collapsed))
      (unless (member "beads" collapsed)
        (list
         (gascity-dashboard--bead-group
          "Ready" ready-load filter-prefix #'gascity-section-beads)
         (gascity-dashboard--bead-group
          "In progress" inprog-load filter-prefix #'gascity-section-beads)
         (gascity-dashboard--bead-group
          "Blocked" blocked-load filter-prefix #'gascity-section-beads)
         (gascity-dashboard--bead-group
          "Convoys" convoy-load filter-prefix
          (lambda (data)
            (append (alist-get 'convoys data) nil))))))
     (gascity-dashboard--section
      "activity" "Activity"
      (list :state (plist-get events-load :state)
            :error (plist-get events-load :error)
            :data (and (plist-get events-load :data)
                       (gascity-dashboard--events-view
                        (plist-get events-load :data)
                        event-types-excluded
                        gascity-dashboard-events-limit)))
      (member "activity" collapsed)
      #'gascity-dashboard--events-rows
      (lambda (view) (length (plist-get view :events))))
     (gascity-dashboard--section
      "rigs" "Rigs" (list :state 'ready :data rigs)
      (member "rigs" collapsed)
      (lambda (rows) (mapcar #'gascity-dashboard--rig-row rows)))
     (vui-text (concat "g refresh · / filter · RET open/toggle · i detail · "
                       "b beads · d dired · t tmux · M/s/K/w/D session · "
                       "N/P section · q bury")
               :face 'gascity-dim))))

;;; State flips (root component, survive a refresh)

(defun gascity-dashboard--flip-collapsed (name)
  "Toggle section NAME's membership in the root component's collapsed list."
  (gascity-dashboard--set-state
   :collapsed
   (let ((current (and (boundp 'vui--root-instance) vui--root-instance
                       (plist-get (vui-instance-state vui--root-instance)
                                  :collapsed))))
     (if (member name current) (remove name current) (cons name current)))))

(defun gascity-dashboard--set-bead-rig (rig)
  "Set the `/` bead filter to rig RIG (nil clears it) and re-render."
  (gascity-dashboard--set-state :bead-rig rig))

(defun gascity-dashboard--set-state (key value)
  "Set KEY to VALUE in the root component's state and re-render in place.
Mirrors `gascity-status--toggle-collapsed': no re-fetch, since the
`vui-use-async' keys are unchanged."
  (when (and (boundp 'vui--root-instance) vui--root-instance)
    (setf (vui-instance-state vui--root-instance)
          (plist-put (vui-instance-state vui--root-instance) key value))
    (vui-flush-sync)))

;;; Commands

(defun gascity-dashboard-activate ()
  "Activate the thing at point in the city dashboard.
On a section header this toggles its collapse; on an agent row it
attaches the agent's terminal (the porcelain's primary action); on a
bead or convoy row it opens beads.el scoped to the owning store; on a
rig row it opens the rig dashboard."
  (interactive)
  (let ((section (get-text-property (point) 'gascity-dashboard-section)))
    (cond
     (section (gascity-dashboard--flip-collapsed section))
     ((and (get-text-property (point) 'gascity-rig)
           (not (gascity-agent-at-point)))
      (gascity-rig-dashboard (get-text-property (point) 'gascity-rig)))
     (t
      (let ((obj (gascity-object-at-point)))
        (cond
         (obj (gascity-at-point-visit obj))
         ((widget-at (point)) (widget-button-press (point)))
         (t (user-error "Nothing to open here"))))))))

(defun gascity-dashboard-refresh ()
  "Reload the city dashboard's data, preserving point and collapse state."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No city dashboard to refresh here")))

;;; Bead filter (`/`)

(defun gascity-dashboard--filter-rig-names ()
  "Return the rig names offered by the `/` bead filter.
Sourced from the I/O-free rig memo (`gascity-rigs-cached') — the same
list this dashboard's own status read keeps warm via
`gascity-rigs-remember' — never the synchronous gc executor (AC-5)."
  (delq nil (mapcar #'gascity-rig-name (gascity-rigs-cached))))

;;;###autoload
(defun gascity-dashboard-filter-rig ()
  "Filter the dashboard's bead sections by rig, via completion.
The filter narrows the ready/in-progress/blocked and convoy groups to the
chosen rig's id prefix, client-side; state is lifted to the root
component, so it survives a refresh.  The candidates come from the
I/O-free rig memo — no synchronous gc call here (AC-5)."
  (interactive)
  (let ((rig (completing-read
              "Filter beads by rig (empty = all): "
              (gascity-dashboard--filter-rig-names))))
    (gascity-dashboard--set-bead-rig (and (not (string-empty-p rig)) rig))))

(defun gascity-dashboard-filter-clear ()
  "Clear the dashboard's bead filter."
  (interactive)
  (gascity-dashboard--set-bead-rig nil))

(defun gascity-dashboard-events-toggle-chatty ()
  "Toggle the Activity feed's default-chatty types as a set.
When any of them is currently excluded, remove all of them; otherwise
add all.  Root-component state, so it survives a refresh."
  (interactive)
  (gascity-dashboard--set-state
   :event-types-excluded
   (gascity-dashboard--events-toggle-chatty
    (gascity-dashboard--events-excluded))))

(defun gascity-dashboard-events-filter-clear ()
  "Clear the Activity feed's type filter: exclude no event types."
  (interactive)
  (gascity-dashboard--set-state :event-types-excluded nil))

(defun gascity-dashboard--events-toggle-chatty (excluded)
  "Return EXCLUDED with the default-chatty types toggled as a set.
Any member currently excluded removes all of them; none present adds
the full default set, preserving other exclusions."
  (if (seq-some (lambda (type) (member type excluded))
                gascity-dashboard--events-chatty-default)
      (seq-remove (lambda (type)
                    (member type gascity-dashboard--events-chatty-default))
                  excluded)
    (append excluded gascity-dashboard--events-chatty-default)))

(transient-define-prefix gascity-dashboard-events-filter-dispatch ()
  "Filter the Activity feed's event types."
  ["Events filter"
   ("t" "Toggle default-chatty types" gascity-dashboard-events-toggle-chatty)
   ("c" "Clear excluded types" gascity-dashboard-events-filter-clear)])

(transient-define-prefix gascity-dashboard-filter-dispatch ()
  "Filter the city dashboard's sections."
  ["Filter"
   ("r" "Beads by rig…" gascity-dashboard-filter-rig)
   ("e" "Events…" gascity-dashboard-events-filter-dispatch)
   ("c" "Clear bead filter" gascity-dashboard-filter-clear)])

(defun gascity-dashboard--events-excluded ()
  "Return the root component's current excluded event types.
Outside a live dashboard root (a command typed elsewhere, tests) this
falls back to the default chatty exclusion instead of nil — the
commands below then behave sensibly from any buffer.  Inside a live
root a nil state is respected: the user cleared the filter, and the
toggle must be able to re-add the chatty set from there."
  (let ((current (and (boundp 'vui--root-instance) vui--root-instance
                      (plist-get (vui-instance-state vui--root-instance)
                                 :event-types-excluded))))
    (if (and (boundp 'vui--root-instance) vui--root-instance)
        current
      gascity-dashboard--events-chatty-default)))

;;; Mode

(defvar-keymap gascity-city-dashboard-mode-map
  :doc "Keymap for `gascity-city-dashboard-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-dashboard-refresh
  "/"   #'gascity-dashboard-filter-dispatch
  ;; `TAB' toggles the section at point — the magit-section convention.
  ;; It shadows the vui chain's `widget-forward' (harmless: this view
  ;; renders no widgets) and mirrors the status dashboard's toggle.
  "TAB" #'gascity-dashboard-activate
  "RET" #'gascity-dashboard-activate
  "i"   #'gascity-polecat-detail-at-point
  "b"   #'gascity-beads-at-point
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  ;; The shared agent action keys (DESIGN-write-actions.md §10): they
  ;; mean the same thing here as in the status dashboard, rig dashboard
  ;; and session detail.  `N'/`P' section jumps and `n'/`p' line
  ;; movement are inherited from `gascity-section-mode-map'.
  ;; `m' opens the existing mail inbox; the buffer's `default-directory'
  ;; is pinned to the city by `gascity-view-get-buffer-create', so the
  ;; inbox scopes to the same city the dashboard reads.
  "m"   #'gascity-mail-inbox
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point)

(define-derived-mode gascity-city-dashboard-mode gascity-section-mode "GC-City"
  "Major mode for the gascity city dashboard.

Sections: cockpit (with the mail-unread header and the costs pointer),
work in flight, needs-you agents, the roster, sessions, beads (+convoys),
the activity pointer and the rigs.  Pending interactions need the
supervisor API; out of scope by user directive, so the needs-you reasons
are only the CLI-derivable ones (errored / rate-limited / stalled).

\\{gascity-city-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              (concat " City dashboard  (g refresh · / filter · RET open/toggle"
                      " · i detail · b beads · d dired · t tmux · M/s/K/w/D session"
                      " · N/P section · q bury)")))

;;;###autoload
(defun gascity-dashboard ()
  "Show the city-level vui dashboard.
One buffer answering \"what is happening in this city right now?\": the
cockpit (mail-unread header, costs pointer), work in flight, needs-you
agents, the roster, sessions, beads (+convoys), the workflow runs, the
activity feed and the rigs — each section backed by its own async
`gc … --json' read, refresh stale-while-revalidate.  `m' opens the
existing mail inbox.  The
buffer is keyed to the city it is opened for via
`gascity-view-get-buffer-create' (host-qualified name, pinned
`default-directory'), so local and TRAMP access modes coexist (REQ-011).
The magit status dashboard (`gascity-status') stays the default and
unchanged."
  (interactive)
  (let ((buf (gascity-view-get-buffer-create gascity-dashboard-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-city-dashboard-mode)
        (gascity-city-dashboard-mode)))
    (unless (gascity-section-refresh-instance buf)
      ;; vui-mount switch-to-buffers internally; contain that so the buffer is
      ;; displayed once, via pop-to-buffer, on both the cold and refresh paths.
      (save-window-excursion
        (vui-mount (vui-component 'gascity-dashboard-app)
                   (buffer-name buf))))
    (pop-to-buffer buf)))

(provide 'gascity-dashboard)
;;; gascity-dashboard.el ends here
