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
;; - needs you      agents blocking the operator, exactly one reason and
;;                  one next action each (REQ-004) — the port of the
;;                  SPA's `needsYou.ts' (`awaiting-input' > `errored' >
;;                  `rate-limited' > `stalled'; respond/reset/nudge; no
;;                clocks, no age thresholds).  The section count and
;;                  the agent roster's highlighting read the same
;;                selector output, so they cannot disagree.
;; - agents         the full `gc status' roster, needs-you rows marked.
;; - sessions       live sessions, the named-session derivation, and
;;                the run census from `gc status''s summary (REQ-006).
;; - beads          ready / in-progress / blocked beads plus convoys
;;                (REQ-007); `/` opens a filter transient.  `RET'
;;                opens a bead or convoy in beads.el, scoped to the
;;                store owning its id prefix (DESIGN.md §4.3).
;; - activity       gc's documented events gap (ga-69kj): `gc event'
;;                has no JSON support, so this renders the documented
;;                pointer and never reads `.gc/events.jsonl' (REQ-008).
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
(require 'gascity-status)             ; header vnode, session-map join, events pointer

;; Detail/list openers and agent actions live in sibling modules loaded
;; alongside this one; reference them by name (resolved at call time).
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
  '(("awaiting-input" . "respond")
    ("errored" . "reset")
    ("rate-limited" . "nudge")
    ("stalled" . "nudge"))
  "The one next operator step for each needs-you reason.")

(defun gascity-dashboard--needs-you-reason (agent pending)
  "Return the one needs-you reason for AGENT, or nil when it blocks nobody.
AGENT is a raw `gc status' agent entry, optionally enriched with a
`state' string and a `session' id (nil when it has no live session) by
the dashboard's join.  PENDING is the operator-interaction list, an
alist of (AGENT-NAME . PROMPT).  First match wins, in the SPA's
precedence order: awaiting-input > errored > rate-limited > stalled."
  (let* ((name (alist-get 'qualified_name agent))
         (state (downcase (or (alist-get 'state agent) ""))))
    (cond ((and name (assoc name pending)) "awaiting-input")
          ((member state gascity-dashboard--failure-states) "errored")
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

(defun gascity-dashboard--prompt-line (prompt)
  "Return the first line of PROMPT, for a one-line row detail.
Only the line before the first newline counts — a prompt starting with
an empty line degrades to \"Awaiting your decision.\" like the SPA's
`promptLine', whose `split(\\n, 1)' never skips a leading empty line."
  (let ((line (and (stringp prompt)
                   (car (split-string prompt "\n")))))
    (setq line (and line (string-trim line)))
    (if (and line (not (string-empty-p line)))
        line
      "Awaiting your decision.")))

(defun gascity-dashboard--needs-you-detail (agent reason prompt)
  "Return the structural why-phrase for AGENT's needs-you REASON.
PROMPT is the pending interaction's prompt when the reason is
`awaiting-input'.  Mirrors the SPA's `needsYouDetail'."
  (let ((state (downcase (or (alist-get 'state agent) ""))))
    (pcase reason
      ("awaiting-input" (gascity-dashboard--prompt-line prompt))
      ("errored" (format "Exited %s." (or (alist-get 'state agent) "?")))
      ("rate-limited" "Throttled by a provider limit.")
      ("stalled" (if (equal state "detached")
                     "Detached from its session."
                   "Running with no live session.")))))

(defun gascity-dashboard--needs-you (agents pending)
  "Project the AGENTS roster into the rows that need the operator.
AGENTS is a list (or vector) of raw `gc status' agent entries, optionally
enriched with `state'/`session' keys; PENDING the operator-interaction
alist of (AGENT-NAME . PROMPT).  Returns one (NAME REASON DETAIL ACTION)
row per blocking agent, NAME being the qualified name, in roster order.
The badge and section counts read this same output, so a badge and its
page cannot disagree (REQ-004).  Port of the SPA's `needsYou.ts': no
clock, no age threshold, nothing that can flap."
  (let ((rows nil))
    (dolist (agent (append agents nil) (nreverse rows))
      (let* ((name (alist-get 'qualified_name agent))
             (reason (gascity-dashboard--needs-you-reason agent pending)))
        (when reason
          (push (list name
                      reason
                      (gascity-dashboard--needs-you-detail
                       agent reason
                       (cdr (assoc name pending)))
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

(defun gascity-dashboard--cockpit-vnode (status)
  "Return the cockpit section vnode for the `gc status' payload STATUS.
Reuses the status dashboard's header vnode (city, controller, health,
counters, store health) — one async read feeds it (REQ-002).  The API
URL appears in no `gc --json' payload yet, so it renders as a dim
placeholder rather than a hand-parsed city.toml (ga-jhwz convention)."
  (vui-vstack
   (gascity-status--header-vnode status)
   (vui-text "  api — (gc exposes no API URL in --json yet)"
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

;;; Component

(vui-defcomponent gascity-dashboard-app ()
  "Root component of the city dashboard."
  ;; Collapse state (`collapsed') and the `/` bead filter (`bead-rig')
  ;; live here, in the root component, rather than per section: the
  ;; keymap commands (`gascity-dashboard-activate',
  ;; `gascity-dashboard-filter-*') flip them and both survive an
  ;; in-place refresh, since `g' only bumps `refresh-tick'.
  :state ((refresh-tick 0) (collapsed nil) (bead-rig nil))
  :render
  ;; All async hooks run unconditionally, in order, every render.  Each
  ;; section's load is independent: one failure never blanks the others.
  (let* ((status-res
          (vui-use-async (list 'status refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("status") resolve reject))))
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
         (status-state (plist-get status-res :status))
         (last-status (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         (last-ready (vui-use-ref nil))
         (last-inprog (vui-use-ref nil))
         (last-blocked (vui-use-ref nil))
         (last-convoy (vui-use-ref nil))
         ;; Stale-while-revalidate: on `ready' adopt fresh data, else
         ;; keep rendering the last snapshot (see
         ;; `gascity-dashboard--effective-load').
         (status (gascity-dashboard--effective-load status-res last-status))
         (sessions-load (gascity-dashboard--effective-load sessions-res
                                                           last-sessions))
         (ready-load (gascity-dashboard--effective-load ready-res
                                                        last-ready))
         (inprog-load (gascity-dashboard--effective-load inprog-res
                                                         last-inprog))
         (blocked-load (gascity-dashboard--effective-load blocked-res
                                                          last-blocked))
         (convoy-load (gascity-dashboard--effective-load convoy-res
                                                         last-convoy)))
    (cond
     ((and (eq status-state 'error) (null (plist-get status :data)))
      (gascity-status--error-vnode (plist-get status-res :error)))
     ((and (eq status-state 'pending) (null (plist-get status :data)))
      (vui-text "Loading city dashboard…" :face 'gascity-dim))
     (t
      (gascity-dashboard--content-vnode
       (plist-get status :data) sessions-load ready-load inprog-load
       blocked-load convoy-load
       :collapsed collapsed :bead-rig bead-rig)))))

(cl-defun gascity-dashboard--content-vnode (status sessions-load ready-load
                                            inprog-load blocked-load
                                            convoy-load
                                            &key collapsed bead-rig)
  "Return the dashboard body vnode.
STATUS is the `gc status' payload; the five LOAD arguments are the
normalized loads of `gc session list', `gc bd ready', the in-progress and
blocked `gc bd list' reads and `gc convoy list'.  COLLAPSED is the root's
list of collapsed section names; BEAD-RIG the active `/` rig filter (a
rig name, or nil for all).  Each section renders from its own load, so a
failing one degrades alone (REQ-010); the needs-you rows are computed
once per render and feed both the needs-you section and the roster's
highlighting (REQ-004's single-selector rule)."
  (let* (;; Decode the session rows once: the typed list feeds the session
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
         (pending nil)     ; gc exposes no pending-interaction read yet
         (needs-you-rows (gascity-dashboard--needs-you enriched pending))
         (needs-you-map (make-hash-table :test 'equal))
         (filter-prefix (gascity-dashboard--rig-prefix bead-rig
                                                       (alist-get 'rigs status))))
    (dolist (row needs-you-rows)
      (puthash (nth 0 row) row needs-you-map))
    (vui-vstack
     :spacing 1
     (gascity-dashboard--cockpit-vnode status)
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
     (vui-vstack
      (vui-text "Activity" :face 'gascity-header 'gascity-section t)
      ;; The documented events gap (ga-69kj): `gc event' has no JSON
      ;; support, so render the documented pointer — never read
      ;; `.gc/events.jsonl' directly (REQ-008).
      (gascity-status--events-pointer-vnode))
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

(transient-define-prefix gascity-dashboard-filter-dispatch ()
  "Filter the city dashboard's bead sections."
  ["Bead filter"
   ("r" "Rig…" gascity-dashboard-filter-rig)
   ("c" "Clear filter" gascity-dashboard-filter-clear)])

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
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point)

(define-derived-mode gascity-city-dashboard-mode gascity-section-mode "GC-City"
  "Major mode for the gascity city dashboard.

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
cockpit, work in flight, needs-you agents, the roster, sessions, beads
(+convoys), the activity pointer and the rigs — each section backed by
its own async `gc … --json' read, refresh stale-while-revalidate.  The
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
