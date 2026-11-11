;;; gascity-status.el --- status/session joins shared by the dashboard views -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The joins the rig dashboard (and the cockpit's agent actions) use to
;; turn flat `gc' payloads into typed objects:
;;
;; - `gc session list --json' rows join on the qualified agent name
;;   (`gascity-status--session-map-rows') so an agent row can find its
;;   session's worktree, tmux name and last activity.
;; - `gascity-status--agent' bridges a raw `gc status' / `gc rig status'
;;   agent entry to the typed action object (`gascity-agent'), carrying
;;   the session data and the tmux socket the agent keys attach through.
;;
;; - `gascity-status--agent-state' is the one running/idle/unknown rule
;;   the cockpit, the Agents view and the rig dashboard share (ec-elkm5.9,
;;   ec-elkm5.10).  A live session outranks a partial probe's not-running
;;   row (the session list observed it alive), so a partial status never
;;   turns an unanswered agent into a definite `stopped'.  `idle' is the
;;   live agent with no hooked work and no recent activity; it is a
;;   liveness-plus-work verdict, identical on every surface.
;; - `gascity-status--hook-work' is the in-progress-bead join behind that
;;   verdict (a bead's assignee session, the agent's qualified name, or a
;;   `gc.routed_to' pool slot), so the rig dashboard and the cockpit hook
;;   the same bead to the same agent.
;; - `gascity-store-payload-degraded-p' marks a `gc status' payload whose
;;   liveness probe timed out (`partial') as degraded evidence, so one
;;   flaky probe cannot flip a settled roster to `unknown' on one surface
;;   while another still renders `stopped' (ga-0onhi).
;;
;; The former agent-tree toolkit (city -> rig -> pool -> agent grouping
;; and its vnodes) was retired with the Agents tree (ga-2mmet); only the
;; joins still consumed by the rig dashboard remain here.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'gascity-ui)                 ; relative-time parsing for the idle age
(require 'gascity-domain)             ; typed session/agent objects
(require 'gascity-store)              ; the degraded-payload rule (ga-0onhi)

;;; Data shaping (pure)

(defun gascity-status--session-map (sessions)
  "Return a hash table mapping a session's qualified agent name to its object.
SESSIONS is the vector (or list) from `gc session list'; each row is decoded
into a `gascity-session' and keyed on its qualified name
\(`gascity-session-qualified-name', which prefers `agent_name' — always the
qualified name — over the volatile `name').  The qualified name is the
reliable join key against a status agent's `qualified_name'.

Thin wrapper over `gascity-status--session-map-rows': callers that already
hold the decoded `gascity-session' rows use that directly."
  (gascity-status--session-map-rows
   (gascity-domain-decode-list 'gascity-session sessions)))

(defun gascity-status--session-map-rows (session-rows)
  "Return the join map for already-decoded SESSION-ROWS.
Same map `gascity-status--session-map' builds, but over the typed
`gascity-session' list a caller decoded once (no double decode, no plist
detour)."
  (let ((map (make-hash-table :test 'equal)))
    (seq-do (lambda (s)
              (let ((key (gascity-session-qualified-name s)))
                (when key (puthash key s map))))
            session-rows)
    map))

;;; Agent state — one normalization (ec-elkm5.9, ec-elkm5.10)

(defconst gascity-status--agent-idle-threshold-default 3600
  "Fallback idle threshold in seconds.
Used when `gascity-dashboard-agent-idle-threshold' is not yet bound; the
user-visible option lives in `gascity-dashboard'.")

(defun gascity-status--agent-idle-threshold ()
  "Return the seconds of inactivity after which a live agent is idle."
  (if (boundp 'gascity-dashboard-agent-idle-threshold)
      (symbol-value 'gascity-dashboard-agent-idle-threshold)
    gascity-status--agent-idle-threshold-default))

(defun gascity-status--rig-of (qname)
  "Return the rig part of qualified agent name QNAME, or nil (city scope)."
  (and (stringp qname) (string-search "/" qname)
       (substring qname 0 (string-search "/" qname))))

(defun gascity-status--live-session-p (session)
  "Return non-nil when SESSION is live.
SESSION is a raw `gc session list' row or a typed `gascity-session'."
  (cond ((null session) nil)
        ((gascity-session-p session) (gascity-session-running-p session))
        (t (and (equal (downcase (or (alist-get 'state session) "")) "active")
                (not (alist-get 'closed session))))))

(defun gascity-status--session-last-active (session)
  "Return SESSION's last-active timestamp (raw row or typed session)."
  (if (gascity-session-p session)
      (gascity-session-last-active session)
    (alist-get 'last_active session)))

(defun gascity-status--agent-state (agent session bead now &optional partial)
  "Return the one normalized state for an agent.
AGENT is a raw `gc status' / `gc rig status' alist, or nil for an agent
known only by its live session.  SESSION is its session (a raw `gc session
list' row or a typed `gascity-session'), nil when there is none.  BEAD is
the in-progress bead it holds, nil when none.  NOW is the current time and
PARTIAL non-nil when gc reports the status probe did not answer for every
agent.

The states are `suspended', `unknown', `stalled', `stopped', `idle' and
`running'.  A live session is evidence the agent is alive and outranks a
partial probe's not-running row.  Without one, a non-running row in a
partial payload is `unknown', never `stopped' — the probe never answered,
so it is no evidence of death (ec-elkm5.9).  `idle' is the live agent with
no hooked work and no activity for `gascity-status--agent-idle-threshold'
seconds; `running' is the live agent with work or fresh activity, so the
cockpit, the Agents view and the rig dashboard agree (ec-elkm5.10).  Pure."
  (let* ((running (and agent (alist-get 'running agent)))
         (live (gascity-status--live-session-p session))
         (active (and live (gascity-status--session-last-active session)))
         (age (and active (gascity-ui-parse-time active)
                   (- now (gascity-ui-parse-time active)))))
    (cond
     ((and agent (alist-get 'suspended agent)) 'suspended)
     (live
      (if (or bead (not age)
              (<= age (gascity-status--agent-idle-threshold)))
          'running
        'idle))
     ((and partial (not running)) 'unknown)
     (running 'stalled)
     (t 'stopped))))

(cl-defmethod gascity-store-payload-degraded-p ((_kind (eql 'status)) payload)
  "Return non-nil when PAYLOAD is a degraded `gc status' payload.
gc marks a status payload `partial' when its liveness probe timed out
for any agent; every agent it did not observe then reads `running: nil'
with nothing learned, which `gascity-status--agent-state' reports as
`unknown' (ec-elkm5.9).  That is honest for a cold store, but it must not
replace a fully observed payload: doing so flips a settled roster to
`unknown' and lets two views that rendered at different moments disagree
about the same agent (ga-0onhi).  The store holds the last non-degraded
payload for `gascity-store-degraded-grace' seconds instead.  Pure."
  (and (consp payload)
       (or (alist-get 'partial payload)
           (alist-get 'partial_errors payload))
       t))

(defun gascity-status--state-label (state)
  "Return the user-facing label of agent STATE (`running' reads active)."
  (if (eq state 'running) "active" (symbol-name state)))

(defun gascity-status--state-glyph (state)
  "Return the `gascity-ui-glyph' kind for agent STATE."
  (pcase state
    ('stalled 'fail)
    ('unknown 'watch)
    ('running 'ok)
    (_ 'idle)))

(defun gascity-status--state-rank (state &optional running-first)
  "Return the Agents ordering rank of STATE.
The default order puts the attention states first (`stalled', `unknown'),
then running, idle, suspended and stopped.  With RUNNING-FIRST, running
ranks first and the attention states come after it: the cockpit Agents
section's order, so no live agent is hidden behind one that needs
attention or is idle (ga-boawq)."
  (if running-first
      (pcase state
        ('running 0) ('stalled 1) ('unknown 2) ('idle 3) ('suspended 4) (_ 5))
    (pcase state
      ('stalled 0) ('unknown 1) ('running 2) ('idle 3) ('suspended 4) (_ 5))))

(defun gascity-status--agent-order (a b &optional running-first)
  "Return non-nil when agent plist A sorts before B.
One order for the cockpit, the Agents view and the rig dashboard: stalled
and unknown first (the states that need a human), then running by most
recent activity, then idle, suspended and stopped.  With RUNNING-FIRST,
running agents lead, then stalled and unknown, then idle (ga-boawq).
The cockpit's Agents section passes RUNNING-FIRST; the Agents view and
the rig dashboard (see `gascity-agents' and `gascity-rig') call the
default order."
  (let ((rank-a (gascity-status--state-rank (plist-get a :state) running-first))
        (rank-b (gascity-status--state-rank (plist-get b :state) running-first)))
    (if (/= rank-a rank-b)
        (< rank-a rank-b)
      (> (or (gascity-ui-parse-time (plist-get a :active)) 0)
         (or (gascity-ui-parse-time (plist-get b :active)) 0)))))

(defun gascity-status--state-summary (states)
  "Return `3 running · 1 idle · 3 stopped' for the agent STATES.
Unknown is counted apart from stopped: it is a degraded verdict, not a
definite dead state (ec-elkm5.9).  Suspended is folded into stopped, as
the cockpit's stopped fold and the Agents view always did."
  (let ((count (lambda (wanted) (seq-count (lambda (state) (memq state wanted)) states))))
    (string-join
     (delq nil
           (list (let ((n (funcall count '(stalled))))
                   (and (> n 0) (format "%d stalled" n)))
                 (let ((n (funcall count '(running))))
                   (and (> n 0) (format "%d running" n)))
                 (let ((n (funcall count '(idle))))
                   (and (> n 0) (format "%d idle" n)))
                 (let ((n (funcall count '(unknown))))
                   (and (> n 0) (format "%d unknown" n)))
                 (let ((n (funcall count '(stopped suspended))))
                   (and (> n 0) (format "%d stopped" n)))))
     " · ")))

;;; Hook join — the in-progress bead an agent holds

;; The trailing supervisor session handle of a bead assignee
;; (`gc__implementation-worker-ec-56em' -> `ec-56em'): a 2-4 letter city
;; prefix, then a `[a-z0-9]' body.  gc's own session ids are bead ids of
;; the city store (`ec-fl8o', `bl-rpq'), so two-letter prefixes are the
;; common case; the old 4-letter-only gate missed them (dashboard-v3 §2).
(defconst gascity-status--session-handle-rx
  "\\`\\(?:gc\\|td\\|th\\|[a-z]\\{2,4\\}\\)-[a-z0-9]\\{1,32\\}\\'"
  "The trailing supervisor session-handle gate, anchored at both ends.")

(defun gascity-status--bare-session-id-p (value)
  "Return non-nil when VALUE itself is a bare supervisor session id.
Same alphabet as `gascity-status--session-handle-rx', plus the rule that
the id body carries a digit, which keeps a role such as `scix-worker'
from passing as an id."
  (and (stringp value)
       (string-match-p gascity-status--session-handle-rx value)
       (let ((dash (string-search "-" value)))
         (and dash (string-match-p "[0-9]" (substring value (1+ dash)))))))

(defun gascity-status--parse-assignee (assignee)
  "Split bead ASSIGNEE into (ROLE . SESSION-ID).
SESSION-ID is the minimal trailing session handle, or nil when there is
none (ROLE is then the whole trimmed assignee).  A bare session id names
itself: (ID . ID)."
  (let ((trimmed (and (stringp assignee) (string-trim assignee))))
    (cond
     ((not trimmed) (cons "" nil))
     ((gascity-status--bare-session-id-p trimmed) (cons trimmed trimmed))
     (t
      (or (catch 'handle
            (let ((i (1- (length trimmed))))
              (while (>= i 0)
                (when (memq (aref trimmed i) '(?- ?_ ?/))
                  (let ((candidate (substring trimmed (1+ i))))
                    (when (and (not (string-empty-p candidate))
                               (string-match-p
                                gascity-status--session-handle-rx candidate))
                      (throw 'handle
                             (cons (substring trimmed 0 i) candidate)))))
                (setq i (1- i)))
              nil))
          (cons trimmed nil))))))

(defun gascity-status--session-for-assignee (assignee sessions &optional any)
  "Return the session in SESSIONS a bead ASSIGNEE refers to, or nil.
Joins on the tmux `session_name', the session `id', the id parsed from the
assignee's trailing handle, then the qualified agent name.  Only live
sessions match unless ANY is non-nil (a stalled agent's closed session row
still names its last bead)."
  (when (and (stringp assignee) (not (string-empty-p assignee)))
    (let* ((pool (or (and any sessions)
                     (seq-filter #'gascity-status--live-session-p sessions)))
           (id (cdr (gascity-status--parse-assignee assignee)))
           (ids (delq nil (list assignee id))))
      (or (seq-find (lambda (s) (equal (alist-get 'session_name s) assignee)) pool)
          (seq-find (lambda (s) (member (alist-get 'id s) ids)) pool)
          (seq-find (lambda (s) (equal (alist-get 'agent_name s) assignee)) pool)))))

(defun gascity-status--routed-to-agent-p (pool name)
  "Return non-nil when routed-to POOL names agent NAME.
A pool slot is the pool's qualified name with a `-N' ordinal."
  (and (stringp pool) (not (string-empty-p pool)) (stringp name)
       (or (equal pool name) (string-prefix-p (concat pool "-") name))))

(defun gascity-status--hook-work (names beads sessions)
  "Return a hash: agent NAME -> the in-progress BEAD it holds.
NAMES is the candidate qualified agent names, BEADS the work beads and
SESSIONS the raw `gc session list' rows.  The joins widen in the order the
cockpit documents (plan §4, plan-review F2): the live session a bead's
assignee names; any session row, live or closed; an assignee equal to
NAME; and a bead whose `gc.routed_to' names one of NAME's pool slots (the
first free slot wins, so two slots never claim the same bead).  Pure."
  (let ((live (seq-filter #'gascity-status--live-session-p sessions))
        (hooked (make-hash-table :test 'equal))
        (used (make-hash-table :test 'equal)))
    (cl-labels
        ((in-progress-p (bead) (equal (alist-get 'status bead) "in_progress"))
         (meta (bead)
           (let ((m (alist-get 'metadata bead))) (and (listp m) m)))
         (hook (bead name)
           (when (and name (member name names)
                      (not (gethash name hooked))
                      (not (gethash (alist-get 'id bead) used)))
             (puthash name bead hooked)
             (puthash (alist-get 'id bead) t used)
             t)))
      ;; (1) The in-progress bead each live session works on.
      (dolist (bead beads)
        (when (in-progress-p bead)
          (let ((s (gascity-status--session-for-assignee
                    (alist-get 'assignee bead) live)))
            (when s (hook bead (alist-get 'agent_name s))))))
      ;; (2) Any session row, live or closed: a stalled agent's last
      ;; session is closed, and its id can still name the bead's assignee.
      (dolist (bead beads)
        (when (in-progress-p bead)
          (let ((s (gascity-status--session-for-assignee
                    (alist-get 'assignee bead) sessions t)))
            (when s (hook bead (alist-get 'agent_name s))))))
      ;; (3) The bead's assignee is the agent's qualified name.
      (dolist (bead beads)
        (when (in-progress-p bead)
          (let ((assignee (alist-get 'assignee bead)))
            (when (stringp assignee) (hook bead assignee)))))
      ;; (4) The bead is routed to a pool the agent is a slot of.
      (dolist (bead beads)
        (when (in-progress-p bead)
          (let ((pool (alist-get 'gc.routed_to (meta bead))))
            (when (stringp pool)
              (seq-some (lambda (n)
                          (and (gascity-status--routed-to-agent-p pool n)
                               (hook bead n)))
                        names))))))
    hooked))

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

(provide 'gascity-status)
;;; gascity-status.el ends here
