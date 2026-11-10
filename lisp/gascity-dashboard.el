;;; gascity-dashboard.el --- The city cockpit -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The city cockpit (plans/dashboard-v3 §7.1): one short, magit-style
;; triage buffer per city that answers, top to bottom, "what needs me,
;; what is moving, who is working, what is queued, what just happened".
;; It replaces both the old city dashboard and the retired status board
;; (D3).
;;
;;   header line   city, `@host' for a remote city, live state, age
;;   top lines     city + path; agents · sessions · runs · ready · mail
;;                 · dolt, with `◐' when gc reports partial errors
;;   Needs you     stalled agents, in-progress work whose holder is gone
;;                 or lease lapsed, crashed sessions, idle/failed runs,
;;                 reopened and escalated beads, unread mail, store health
;;   Moving        active runs with their step ladder and live workers
;;   Agents        running, then idle; stopped folded into one line
;;   Work          in-progress work with its assignee and age (oldest
;;                 first), then ready beads by priority; noise hidden
;;                 with a count
;;   Activity      recent events, churn folded into ×N rows per 15 min
;;   Rigs          one row per rig
;;
;; No section shows more than `gascity-dashboard-section-rows' rows; the
;; rest is a `… N more' line that opens the dedicated view (§4.2).
;; Hidden noise is always counted (D4), missing data renders nothing
;; (§4.4).
;;
;; Every section reads through one small, named loader
;; (`gascity-dashboard--read-*'), each an independent async gc call, so
;; one failure never blanks the others; a refresh keeps rendering the
;; last good payload while the reload is in flight (stale-while-
;; revalidate).  Everything the render computes is pure over those
;; payloads: no gc, no TRAMP I/O at render time (§8.3 R2).
;;
;; View state — folded sections, open inline drawers, expanded folds and
;; the filters — lives in the root component, so it survives a refresh;
;; the filters are also remembered per city for the session
;; (`gascity-dashboard-filters').
;;
;; Keys (§5): TAB/S-TAB move between things, SPC toggles the thing at
;; point (fold a section, expand a fold row, open a row's drawer), RET
;; acts on it (never folds), `?' dispatches, `j' jumps to a view, `/'
;; filters, `W' toggles live refresh; the agent, bead and rig keys mean
;; what they mean in every other view.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'transient)
(require 'beads-prefix)
(require 'beads-thing)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-event)
(require 'gascity-context)
(require 'gascity-domain)
(require 'gascity-remote)
(require 'gascity-reader)
(require 'gascity-store)              ; section reads (shared, scheduled)
(require 'gascity-status)             ; one agent-state rule (ec-elkm5.9/.10)
(require 'gascity-pulse)              ; Needs you totals for lighter/Cities
(require 'gascity-live)               ; live refresh from the event stream
(require 'gascity-command)
(require 'gascity-command-status)
(require 'gascity-section)
(require 'gascity-tabulated)

;; Openers and verbs live in sibling modules loaded alongside this one.
(declare-function gascity-mail-inbox "gascity-mail")
(declare-function gascity-rig-list "gascity-tabulated")
(declare-function gascity-convoy-list "gascity-tabulated")
(declare-function gascity-order-list "gascity-tabulated")
(declare-function gascity-dolt-list "gascity-tabulated")
(declare-function gascity-polecat-detail-at-point "gascity-session")
(declare-function gascity-polecat-detail "gascity-session")
(declare-function gascity-rig-dashboard "gascity-rig")
(declare-function gascity-run-show "gascity-run")
(declare-function gascity-runs-read-beads "gascity-runs")
(declare-function gascity-runs-index "gascity-runs")
(declare-function gascity-runs-ladder "gascity-runs")
(declare-function gascity-runs-last-activity "gascity-runs")
(declare-function gascity-runs-parent-id "gascity-runs")
(declare-function gascity-runs-graph "gascity-runs")
(declare-function gascity-runs-failed-step "gascity-runs")
(declare-function gascity-runs-summary "gascity-runs")
(declare-function gascity-runs-state "gascity-runs")
(declare-function gascity-runs-window-seconds "gascity-runs")
(declare-function gascity-runs--close-reason "gascity-runs")
(declare-function gascity-runs--failure-info "gascity-runs")
(declare-function gascity-runs--run-failure "gascity-runs")
(declare-function gascity-runs--time "gascity-runs")
(declare-function gascity-runs-timing "gascity-runs")
(declare-function gascity-runs--timing-cell "gascity-runs")
(declare-function gascity-runs--within-p "gascity-runs")
(defvar gascity-runs-failed-window)
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-session-reset-at-point "gascity-action")
(declare-function gascity-session-undrain-at-point "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")
(declare-function gascity-rig-suspend-at-point "gascity-action")
(declare-function gascity-rig-resume-at-point "gascity-action")
(declare-function gascity-rig-restart-at-point "gascity-action")
(declare-function gascity-bead-dispatch "gascity-action")
(declare-function gascity-sling-dispatch "gascity-action")
(declare-function gascity-mail-dispatch "gascity-action")
(declare-function gascity-lifecycle-dispatch "gascity-action")
(declare-function gascity-order-run "gascity-action")
(declare-function gascity-reload "gascity-action")
(declare-function magit-log-all "magit-log")
(declare-function vc-print-root-log "vc")
;; Views built by later dashboard-v3 phases (§5.2); the jump commands
;; call them when they exist and say so when they do not yet.
(declare-function gascity-agents "gascity-agents")
(declare-function gascity-runs "gascity-runs")
(declare-function gascity-events "gascity-events" (&optional filter))
(declare-function gascity-health "gascity-health")
(declare-function gascity-cities "gascity-cities")
(declare-function gascity-mail "gascity-mail")
(declare-function gascity-costs "gascity-costs")

;;; Options

(defcustom gascity-dashboard-section-rows 5
  "Maximum number of rows a cockpit section shows (dashboard-v3 §4.2).
The rest collapse into a `… N more' line that opens the full view.
The Agents section starts at `gascity-dashboard-agent-rows' instead."
  :type 'natnum
  :group 'gascity)

(defcustom gascity-dashboard-agent-rows 8
  "Base number of Agents rows the cockpit's Agents section shows.
The rest collapse into a `… N more' line that opens the Agents view.
Only that section reads it: every other cockpit section starts at
`gascity-dashboard-section-rows'.  The `▸ stopped' fold counts as one
of these rows, and the section's expansion (`+') adds to it (ga-boawq)."
  :type 'natnum
  :group 'gascity)

(defcustom gascity-dashboard-run-idle-threshold 1800
  "Seconds without step progress after which an active run needs you.
A run whose root is in progress but none of whose in-progress step
beads was updated within this many seconds shows in Needs you as idle."
  :type 'natnum
  :group 'gascity)

(defcustom gascity-dashboard-agent-idle-threshold 3600
  "Seconds of inactivity after which a live agent with no work is idle.
Only the Agents section's running/idle split reads it."
  :type 'natnum
  :group 'gascity)

(defcustom gascity-dashboard-churn-unfold-rows 20
  "Most events SPC unfolds under a cockpit `×N' churn row.
The rest is a `… N more' line whose RET opens the Events view narrowed
to that churn group."
  :type 'natnum
  :group 'gascity)

(defcustom gascity-dashboard-window "2h"
  "Default `gc events --since' window of the cockpit's Activity section."
  :type 'string
  :group 'gascity)

(defvar gascity-dashboard-filters nil
  "Cockpit filters remembered per city for the session.
An alist (CITY-ROOT . PLIST); PLIST keys are `:wisps', `:nudges',
`:orders', `:messages' (show that noise), `:rig' (a rig name),
`:window' (a `gc events --since' duration) and `:unfold' (unfold
churn).  See `gascity-dashboard-filter'.")

(defconst gascity-dashboard-buffer-name "*gascity: %s*"
  "Format of the cockpit buffer's base name; %s is the city name.")

(defconst gascity-dashboard--runs-key '("bd" "list" :runs)
  "Store key of the run beads, shared with the Runs view.
The same entry as `gascity-runs-read-key', read by `gascity-runs-read-beads'.")

(defconst gascity-dashboard--width 78
  "Column where right-aligned cockpit hints end.")

(defconst gascity-dashboard--drawer-width (- gascity-dashboard--width 4)
  "Columns available inside a drawer line (the `  │ ' prefix is 4).")

(defun gascity-dashboard--drawer-value (prefix value &optional full)
  "Return PREFIX followed by VALUE cut to `gascity-dashboard--drawer-width'.
FULL (default VALUE) rides in `help-echo' when VALUE is cut, so the
complete text stays available from a rendered drawer line; a caller
that shows one line of a multi-line reason passes the whole text.
This is the one place a drawer value is bounded: fit once, never
re-fit an already-cut string."
  (let* ((value (or value ""))
         (full (or full value))
         (budget (max 0 (- gascity-dashboard--drawer-width
                           (string-width prefix))))
         (cut (gascity-ui-truncate value budget)))
    (concat prefix
            (cond ((zerop budget) "")
                  ((or (not (equal cut value)) (not (equal full value)))
                   (propertize cut 'help-echo full))
                  (t cut)))))

(defvar gascity-dashboard--view nil
  "The root view state while a cockpit renders (dynamically bound).
A plist (:collapsed :drawers :expanded) of the root component.")

(defvar-local gascity-dashboard--city nil
  "The city name this cockpit shows (for the header line).")

(defconst gascity-dashboard--jumps
  '(("j j" . gascity-jump-cockpit)
    ("j a" . gascity-jump-agents)
    ("j r" . gascity-jump-runs)
    ("j b" . gascity-jump-beads)
    ("j m" . gascity-jump-mail)
    ("j e" . gascity-jump-events)
    ("j h" . gascity-jump-health)
    ("j c" . gascity-jump-cities)
    ("j o" . gascity-jump-orders)
    ("j v" . gascity-jump-convoys)
    ("j d" . gascity-jump-dolt)
    ("j g" . gascity-jump-rig)
    ("j l" . gascity-jump-rigs)
    ("j s" . gascity-jump-sessions)
    ("j $" . gascity-jump-costs))
  "The `j' jump prefix (§5.2): key → command.")

;;; Noise (D4)

(defun gascity-dashboard--labels (bead)
  "Return BEAD's labels as a list of strings."
  (append (alist-get 'labels bead) nil))

(defun gascity-dashboard--meta (bead)
  "Return BEAD's metadata alist (nil when absent)."
  (let ((meta (alist-get 'metadata bead)))
    (and (listp meta) meta)))

(defalias 'gascity-dashboard--hidden-label #'gascity-ui-hidden-label
  "The `(N hidden)' tally (shared with the rig dashboard).")

;;; Sessions and agents

;; The assignee and session joins are shared with the rig dashboard through
;; `gascity-status' (ec-elkm5.10): one implementation, so a bead hooks the
;; same agent and an agent reads the same state on every surface.  These
;; aliases keep the existing call sites (runs, run, session detail) on the
;; dashboard prefix.
(defalias 'gascity-dashboard--bare-session-id-p
  #'gascity-status--bare-session-id-p
  "Bare supervisor session id predicate (shared with the rig dashboard).")

(defalias 'gascity-dashboard--parse-assignee #'gascity-status--parse-assignee
  "Split a bead assignee into (ROLE . SESSION-ID).")

(defalias 'gascity-dashboard--live-session-p #'gascity-status--live-session-p
  "Return non-nil when a raw session alist is live.")

(defalias 'gascity-dashboard--session-for-assignee
  #'gascity-status--session-for-assignee
  "Return the session a bead assignee refers to.")

(defalias 'gascity-dashboard--routed-to-agent-p
  #'gascity-status--routed-to-agent-p
  "Return non-nil when a routed-to pool names an agent slot.")

(defun gascity-dashboard--real-time (ts)
  "Return TS when it is a real timestamp, else nil.
gc's 1970 epoch placeholder and malformed values count as absent, so a
stall duration is never computed from them (plan section 4)."
  (when (and ts (gascity-ui-parse-time ts) (not (gascity-ui-epoch-time-p ts)))
    ts))

(defun gascity-dashboard--agent-stall (agent)
  "Return AGENT's stall evidence (:since :source :lease :heartbeat).
The chain is the session's `last_active', its `created_at', the hooked
bead's claim (`started_at' or `gc.claimed_at'), then the bead's
`updated_at' and `created_at' (plan decision 1).  TS is the payload
timestamp, nil when nothing real is available; :lease and :heartbeat
read the hooked bead, then its metadata for older stores."
  (let* ((session (plist-get agent :session))
         (bead (plist-get agent :bead-data))
         (meta (and bead (gascity-dashboard--meta bead)))
         (claimed (and bead (gascity-dashboard--claimed-at bead)))
         (claim-source (and bead
                            (or (alist-get 'started_at bead)
                                (alist-get 'gc.claimed_at meta))
                            "claimed"))
         (chain (list (cons (and session (alist-get 'last_active session))
                            "last active")
                      (cons (and session (alist-get 'created_at session))
                            "created")
                      ;; `gascity-dashboard--claimed-at' also falls back to
                      ;; `updated_at'; the source labels keep claim and
                      ;; update apart.
                      (cons (and claim-source claimed) claim-source)
                      (cons (and bead (alist-get 'updated_at bead)) "updated")
                      (cons (and bead (alist-get 'created_at bead)) "created")))
         (pick (seq-find (lambda (entry)
                           (gascity-dashboard--real-time (car entry)))
                         chain)))
    (list :since (and pick (car pick))
          :source (and pick (cdr pick))
          :lease (or (gascity-dashboard--real-time
                      (and bead (alist-get 'lease_expires_at bead)))
                     (gascity-dashboard--real-time
                      (alist-get 'gc.lease_expires_at meta)))
          :heartbeat (or (gascity-dashboard--real-time
                          (and bead (alist-get 'heartbeat_at bead)))
                         (gascity-dashboard--real-time
                          (alist-get 'gc.heartbeat_at meta))))))

(defun gascity-dashboard--stall-age (stall now)
  "Return the stall age of STALL at NOW: a duration string or `unknown'."
  (let ((since (plist-get stall :since)))
    (if since
        (gascity-ui-duration (- now (gascity-ui-parse-time since)))
      "unknown")))

(defun gascity-dashboard--agent-object (name session socket &optional running rig)
  "Return the action `gascity-agent' for agent NAME.
SESSION is its raw live session alist (or nil), SOCKET the city's tmux
socket; RUNNING and RIG fill in when there is no session."
  (make-instance 'gascity-agent
                 :name name
                 :rig (or (and session (alist-get 'rig session)) rig)
                 :work-dir (and session (alist-get 'work_dir session))
                 :session-name (and session (alist-get 'session_name session))
                 :socket socket
                 :running (and (if session
                                   (gascity-dashboard--live-session-p session)
                                 running)
                               t)))

(defun gascity-dashboard--rig-of (qname)
  "Return the rig part of qualified agent name QNAME, or nil (city scope)."
  (and (stringp qname) (string-search "/" qname)
       (substring qname 0 (string-search "/" qname))))

(defun gascity-dashboard--agents (status sessions beads socket now)
  "Return the cockpit's agent roster, one plist per agent.
STATUS is the `gc status' payload, SESSIONS the raw `gc session list'
rows, BEADS the work beads (for each agent's hooked bead), SOCKET the
tmux socket and NOW the time.  The roster is `gc status''s configured
agents joined to their live sessions, plus every live session with no
status agent (the mayor and other named sessions — one list, §7.1).

Each plist carries :name :rig :state :provider :bead (the in-progress
bead id) :title :bead-data (that bead's raw alist) :active (last-active
timestamp) :session :object (the action `gascity-agent').  The state is
`gascity-status--agent-state''s one verdict — `suspended', `unknown',
`stalled', `stopped', `idle' or `running' — shared with the Agents view
and the rig dashboard, so a partial `gc status' never labels an
unanswered agent `stopped' (ec-elkm5.9) and a live agent with no work
reads `idle' everywhere (ec-elkm5.10).

The hooked bead is joined in four widening steps, first match wins: the
live session a bead's assignee names; any session row, live or closed;
an assignee equal to the agent's qualified name; and the `gc.routed_to'
pool naming one of the agent's slots (plan section 4, plan-review F2)."
  (let* ((live (seq-filter #'gascity-status--live-session-p sessions))
         (by-name (make-hash-table :test 'equal))
         (seen (make-hash-table :test 'equal))
         (names (delete-dups
                 (delq nil (append
                            (mapcar (lambda (a) (alist-get 'qualified_name a))
                                    (append (alist-get 'agents status) nil))
                            (mapcar (lambda (s) (alist-get 'agent_name s))
                                    live)))))
         (hooked (gascity-status--hook-work names beads sessions))
         (partial (alist-get 'partial status))
         (rows nil))
    (dolist (s live)
      (puthash (alist-get 'agent_name s) s by-name))
    (cl-flet ((row (name agent session)
                (let* ((bead (gethash name hooked))
                       (active (and session (alist-get 'last_active session)))
                       (state (gascity-status--agent-state
                               agent session bead now partial)))
                  (list :name name
                        :rig (or (and session (alist-get 'rig session))
                                 (gascity-dashboard--rig-of name))
                        :state state
                        :provider (and session (alist-get 'provider session))
                        :bead (and bead (alist-get 'id bead))
                        :title (and bead (alist-get 'title bead))
                        :bead-data bead
                        :active active
                        :created (and session (alist-get 'created_at session))
                        :session session
                        :object (gascity-dashboard--agent-object
                                 name session socket
                                 (or (and agent (alist-get 'running agent))
                                     (and session t))
                                 (gascity-dashboard--rig-of name))))))
      (dolist (agent (append (alist-get 'agents status) nil))
        (let ((name (alist-get 'qualified_name agent)))
          (when (and name (not (gethash name seen)))
            (puthash name t seen)
            (push (row name agent (gethash name by-name)) rows))))
      (dolist (s live)
        (let ((name (alist-get 'agent_name s)))
          (when (and name (not (gethash name seen)))
            (puthash name t seen)
            (push (row name nil s) rows)))))
    (nreverse rows)))

(defun gascity-dashboard-agent-counts (agents)
  "Return (RUNNING . TOTAL) for the agent plists AGENTS.
The one agent count every view shows (the cockpit top line, the Agents
section, the Cities rows): running is the agents actively working —
idle, stalled and stopped ones are not."
  (cons (seq-count (lambda (a) (eq (plist-get a :state) 'running)) agents)
        (length agents)))

(defun gascity-dashboard-city-agent-counts (status sessions-payload)
  "Return (RUNNING . TOTAL) for a city's STATUS and SESSIONS-PAYLOAD.
The cockpit's roster (`gascity-dashboard--agents') over the two payloads,
counted by `gascity-dashboard-agent-counts'."
  (gascity-dashboard-agent-counts
   (gascity-dashboard--agents status
                              (append (alist-get 'sessions sessions-payload) nil)
                              nil nil (float-time))))

(defun gascity-dashboard--agent-order (a b &optional running-first)
  "Return non-nil when agent plist A sorts before B in the Agents section.
The shared order (ec-elkm5.10): stalled and unknown first, then running
by most recent activity, then idle, suspended and stopped.  With
RUNNING-FIRST, running leads, then stalled/unknown, then idle: the
cockpit section never spends its rows on a non-working agent while a
live one is hidden (ga-boawq).  The Agents view and the rig dashboard
call the default order; only `gascity-dashboard--agents-lines' passes
RUNNING-FIRST."
  (gascity-status--agent-order a b running-first))

;;; Runs (§3.2, §7.6)

(defun gascity-dashboard--run-root-p (bead)
  "Return non-nil when BEAD is a workflow run root (`gc.kind' workflow).
A workflow-latch step carries `gc.kind' workflow too but names the run it
belongs to in `gc.root_bead_id'; such a bead is a graph member, not a
run root (ga-99g35), so the run root keeps its ladder instead of
rendering `Steps 0/0' while its latch shows up as a run of its own."
  (and (equal (alist-get 'gc.kind (gascity-dashboard--meta bead)) "workflow")
       (null (gascity-dashboard--root-of bead))))

(defun gascity-dashboard--root-of (bead)
  "Return the run root id BEAD belongs to, or nil."
  (alist-get 'gc.root_bead_id (gascity-dashboard--meta bead)))

(defun gascity-dashboard--active-runs (beads)
  "Return the in-progress run roots among BEADS, newest update first."
  (sort (seq-filter (lambda (b)
                      (and (gascity-dashboard--run-root-p b)
                           (equal (alist-get 'status b) "in_progress")))
                    beads)
        (lambda (a b)
          (> (or (gascity-ui-parse-time (alist-get 'updated_at a)) 0)
             (or (gascity-ui-parse-time (alist-get 'updated_at b)) 0)))))

(defun gascity-dashboard--live-worker-of (beads sessions)
  "Return the live session working one of BEADS, or nil.
BEADS are a run's beads (its in-progress steps and, when the Runs read
is in hand, every graph bead); SESSIONS the raw `session list' rows.
An in-progress bead whose assignee joins a live session is proved work,
not an idle run (ec-elkm5.3)."
  (seq-some (lambda (bead)
              (and (equal (alist-get 'status bead) "in_progress")
                   (stringp (alist-get 'assignee bead))
                   (gascity-dashboard--session-for-assignee
                    (alist-get 'assignee bead) sessions)))
            beads))

(defun gascity-dashboard--drain-members (index beads)
  "Return the member run roots of the drain steps among BEADS in INDEX."
  (let ((drains (plist-get index :drains)))
    (seq-mapcat (lambda (b) (gethash (alist-get 'id b) drains)) beads)))

(defun gascity-dashboard--run-live-worker (root beads index sessions
                                                &optional seen)
  "Return a live session working run ROOT, its BEADS, or a drain member.
BEADS are ROOT's own beads (the work read plus the Runs graph); INDEX
is the Runs index (nil before it lands), SESSIONS the raw `session
list' rows.  An open drain step's member runs work outside ROOT's
graph, so a live worker there keeps ROOT out of the idle section too.
SEEN guards a cyclic drain graph."
  (let ((id (alist-get 'id root)))
    (unless (member id seen)
      (or (gascity-dashboard--live-worker-of beads sessions)
          (when index
            (let ((seen (cons id seen)))
              (seq-some
               (lambda (member)
                 (and (equal (alist-get 'status member) "in_progress")
                      (gascity-dashboard--run-live-worker
                       member (gascity-runs-graph index (alist-get 'id member))
                       index sessions seen)))
               (gascity-dashboard--drain-members
                index (gascity-runs-graph index id)))))))))

(defun gascity-dashboard--run-idle-evidence (root steps index)
  "Return (:time TIME :text TEXT) for run ROOT's latest activity.
STEPS are the run's beads (the work read plus, when INDEX is in hand,
the Runs graph); INDEX is the Runs index, whose
`gascity-runs-last-activity' also covers in-progress drain members.
TIME is 0 when nothing carries a real timestamp.  TEXT names where TIME
came from (`run updated', `step ID updated', `drain member activity'),
so the idle drawer states evidence instead of inventing it."
  (let* ((root-time (or (gascity-ui-parse-time (alist-get 'updated_at root))
                        0))
         (in-progress (seq-filter
                       (lambda (b)
                         (equal (alist-get 'status b) "in_progress"))
                       steps))
         (step (car (sort (copy-sequence in-progress)
                          (lambda (a b)
                            (> (or (gascity-ui-parse-time
                                    (alist-get 'updated_at a)) 0)
                               (or (gascity-ui-parse-time
                                    (alist-get 'updated_at b)) 0))))))
         (step-time (or (and step (gascity-ui-parse-time
                                   (alist-get 'updated_at step)))
                        0))
         (member-time (or (and index (gascity-runs-last-activity index root))
                          0))
         (time root-time)
         (text "run updated"))
    (when (> step-time time)
      (setq time step-time
            text (format "step %s updated" (or (alist-get 'id step) "?"))))
    (when (> member-time (max root-time step-time))
      (setq time member-time
            text "drain member activity"))
    (list :time time :text text)))

(defun gascity-dashboard--idle-run-drawer (root steps index now idle)
  "Return the drawer lines of idle run ROOT.
STEPS are the run's beads (graph beads included when INDEX is in hand),
NOW the render time and IDLE its seconds without activity.  The lines
state the reason, the last activity and the worker's liveness, then the
next action -- the failed-run drawer standard (ga-shl0s), and only
evidence the payload carries (ec-elkm5.4)."
  (let* ((evidence (gascity-dashboard--run-idle-evidence root steps index))
         (last (plist-get evidence :time))
         (busy (seq-filter (lambda (b)
                             (equal (alist-get 'status b) "in_progress"))
                           steps))
         (worker (car (sort (copy-sequence busy)
                            (lambda (a b)
                              (> (or (gascity-ui-parse-time
                                      (alist-get 'updated_at a)) 0)
                                 (or (gascity-ui-parse-time
                                      (alist-get 'updated_at b)) 0))))))
         (who (and worker (alist-get 'assignee worker))))
    (delq nil
          (list
           (gascity-dashboard--drawer-value
            "run      " (format "%s  %s"
                                 (alist-get 'id root)
                                 (or (alist-get 'gc.formula_name
                                                (gascity-dashboard--meta root))
                                     (alist-get 'title root) "")))
           (gascity-dashboard--drawer-value
            "idle     " (format "%s  (threshold %s)"
                                 (gascity-ui-duration idle)
                                 (gascity-ui-duration
                                  gascity-dashboard-run-idle-threshold)))
           (and (> last 0)
                (gascity-dashboard--drawer-value
                 "last     " (format "%s %s ago" (plist-get evidence :text)
                                     (gascity-ui-duration (max 0 (- now last))))))
           (gascity-dashboard--drawer-value
            "reason   " (format "no step or live worker activity within %s"
                                (gascity-ui-duration
                                 gascity-dashboard-run-idle-threshold)))
           (gascity-dashboard--drawer-value
            "worker   " (cond ((null worker) "no in-progress step")
                              ((not (stringp who)) "unassigned step")
                              (t (format "%s  no live session" who))))
           (gascity-dashboard--dim "RET run detail  b root bead")))))

(defconst gascity-dashboard--control-kinds
  '("spec" "scope-check" "workflow-finalize")
  "Step `gc.kind' values that are control nodes, not ladder steps.")

(defun gascity-dashboard--top-level-step-p (bead formula)
  "Return non-nil when BEAD is a top-level step of a FORMULA run.
Its `gc.step_ref' is exactly `<formula>.<step>' and its `gc.kind' is no
control kind (§3.2)."
  (let* ((meta (gascity-dashboard--meta bead))
         (ref (alist-get 'gc.step_ref meta)))
    (and (stringp ref) (stringp formula)
         (string-prefix-p (concat formula ".") ref)
         (not (string-search "." (substring ref (1+ (length formula)))))
         (not (member (alist-get 'gc.kind meta)
                      gascity-dashboard--control-kinds)))))

(defun gascity-dashboard--bead-state (bead)
  "Return BEAD's ladder state: `done' `failed' `active' or `pending'."
  (let ((status (alist-get 'status bead))
        (outcome (alist-get 'gc.outcome (gascity-dashboard--meta bead))))
    (cond ((equal status "closed")
           (if (equal outcome "fail") 'failed 'done))
          ((equal status "in_progress") 'active)
          (t 'pending))))

(defun gascity-dashboard--depths (beads)
  "Return a hash of bead id → blocks-dependency depth within BEADS."
  (let ((by-id (make-hash-table :test 'equal))
        (depth (make-hash-table :test 'equal)))
    (dolist (b beads) (puthash (alist-get 'id b) b by-id))
    (cl-labels ((d (id trail)
                  (or (gethash id depth)
                      (let* ((b (gethash id by-id))
                             (deps (and b
                                        (seq-keep
                                         (lambda (dep)
                                           (and (equal (alist-get 'type dep) "blocks")
                                                (alist-get 'depends_on_id dep)))
                                         (append (alist-get 'dependencies b) nil))))
                             (v (if (or (null deps) (member id trail))
                                    0
                                  (1+ (apply #'max
                                             (mapcar (lambda (x)
                                                       (if (gethash x by-id)
                                                           (d x (cons id trail))
                                                         -1))
                                                     deps))))))
                        (puthash id v depth)))))
      (dolist (b beads) (d (alist-get 'id b) nil)))
    depth))

(defun gascity-dashboard--step-path (bead formula)
  "Return BEAD's step path: its `gc.step_ref' without the FORMULA prefix.
Top-level and nested steps carry the prefix (`build-basic.review'),
iteration beads do not (`review.iteration.1'); stripping it puts both
on one path tree (`review', `review.iteration.1').  Nil without a ref."
  (let ((ref (alist-get 'gc.step_ref (gascity-dashboard--meta bead))))
    (and (stringp ref)
         (if (and (stringp formula) (string-prefix-p (concat formula ".") ref))
             (substring ref (1+ (length formula)))
           ref))))

(defun gascity-dashboard--step-ref (bead formula)
  "Return BEAD's ordered step reference under FORMULA.
`gc.step_ref' with the FORMULA prefix stripped when it carries that
prefix, else `gc.step_id', else the bead id: one total helper for the
ladder's order and its `:name', so a bead without a prefixed ref (a
foreign or unknown-kind step) can never break the ladder."
  (let* ((meta (gascity-dashboard--meta bead))
         (ref (alist-get 'gc.step_ref meta))
         (step (alist-get 'gc.step_id meta)))
    (cond ((and (stringp ref) (stringp formula)
                (string-prefix-p (concat formula ".") ref))
           (substring ref (1+ (length formula))))
          ((and (stringp ref) (not (string-empty-p ref))) ref)
          ((and (stringp step) (not (string-empty-p step))) step)
          (t (alist-get 'id bead)))))

(defun gascity-dashboard--failed-paths (root graph)
  "Return the step paths of GRAPH's failed beads when run ROOT failed.
Nil for a run that did not fail (a retried loop in a passing run keeps
its step done).  The ladder and the run detail both read it."
  (let ((formula (alist-get 'gc.formula_name (gascity-dashboard--meta root))))
    (and (equal (alist-get 'gc.outcome (gascity-dashboard--meta root)) "fail")
         (delq nil (mapcar (lambda (b)
                             (and (equal (alist-get 'gc.outcome
                                                    (gascity-dashboard--meta b))
                                         "fail")
                                  (gascity-dashboard--step-path b formula)))
                           graph)))))

(defun gascity-dashboard--failed-beneath-p (path failed-paths)
  "Return non-nil when a path in FAILED-PATHS lies beneath step PATH."
  (seq-some (lambda (p) (string-prefix-p (concat path ".") p)) failed-paths))

(defun gascity-dashboard--ladder (root graph &optional drains)
  "Return the step ladder of run ROOT from its GRAPH beads.
GRAPH is every bead anchored to ROOT (`gc.root_bead_id'), any status.
Returns a list of plists (:name :id :state), one per top-level step, in
formula order: blocks-dependency depth, then the step reference
\(`gascity-dashboard--step-ref'), then the bead id, so the order is
total and never depends on the payload's read order.  A step's state is its
latest iteration bead's (`gc.logical_bead_id' → step, max
`gc.attempt'), else its own.  In a failed run (root `gc.outcome'
fail) a closed step with a failed bead beneath it (a nested loop that
failed) is the failed step.  A drain step stays open while its member
runs work, outside GRAPH: DRAINS maps a drain step id to its member run
roots (`gc.drain_control_id'), and an open drain with a member in
progress is active."
  (let* ((formula (alist-get 'gc.formula_name (gascity-dashboard--meta root)))
         (failed-paths (gascity-dashboard--failed-paths root graph))
         (steps (seq-filter (lambda (b)
                              (gascity-dashboard--top-level-step-p b formula))
                            graph))
         (depth (gascity-dashboard--depths graph))
         (latest (make-hash-table :test 'equal)))
    (dolist (b graph)
      (let* ((meta (gascity-dashboard--meta b))
             (step (alist-get 'gc.logical_bead_id meta))
             (attempt (string-to-number
                       (format "%s" (or (alist-get 'gc.attempt meta) "0")))))
        (when step
          (let ((prev (gethash step latest)))
            (when (or (null prev) (>= attempt (car prev)))
              (puthash step (cons attempt b) latest))))))
    (mapcar (lambda (step)
              (let* ((id (alist-get 'id step))
                     (iter (cdr (gethash id latest)))
                     (own (gascity-dashboard--bead-state step))
                     (state (if (and iter (not (eq own 'done)))
                                (gascity-dashboard--bead-state iter)
                              own))
                     (name (gascity-dashboard--step-ref step formula)))
                (when (and (eq state 'done)
                           (gascity-dashboard--failed-beneath-p name failed-paths))
                  (setq state 'failed))
                (when (and (eq state 'pending) drains
                           (seq-some (lambda (m) (equal (alist-get 'status m) "in_progress"))
                                     (gethash id drains)))
                  (setq state 'active))
                (list :name name :id id :state state)))
            (sort steps
                  (lambda (a b)
                    (let ((da (gethash (alist-get 'id a) depth 0))
                          (db (gethash (alist-get 'id b) depth 0)))
                      (cond ((/= da db) (< da db))
                            (t (let ((ra (gascity-dashboard--step-ref a formula))
                                     (rb (gascity-dashboard--step-ref b formula)))
                                 (if (equal ra rb)
                                     (string< (or (alist-get 'id a) "")
                                              (or (alist-get 'id b) ""))
                                   (string< ra rb)))))))))))

(defun gascity-dashboard--ladder-string (ladder)
  "Return LADDER as glyphs `◆⬣········' with every step in `help-echo'."
  (let ((echo (mapconcat (lambda (s) (format "%s %s" (plist-get s :state)
                                             (plist-get s :name)))
                         ladder "\n")))
    (propertize
     (mapconcat (lambda (s)
                  (gascity-ui-glyph (pcase (plist-get s :state)
                                      ('done 'done) ('active 'active)
                                      ('failed 'failed) (_ 'pending))))
                ladder "")
     'help-echo echo)))

(defun gascity-dashboard--ladder-label (ladder)
  "Return (LABEL . PROGRESS) for LADDER: the active step and `done/total'."
  (let ((current (or (seq-find (lambda (s) (eq (plist-get s :state) 'failed)) ladder)
                     (seq-find (lambda (s) (eq (plist-get s :state) 'active)) ladder)
                     (seq-find (lambda (s) (eq (plist-get s :state) 'pending)) ladder))))
    (cons (or (and current (plist-get current :name)) "")
          (format "%d/%d"
                  (seq-count (lambda (s) (eq (plist-get s :state) 'done)) ladder)
                  (length ladder)))))

;;; Needs you (§7.1)

(defun gascity-dashboard--session-id-of (event)
  "Return the session id an EVENT is about.
Its `session_id', else the trailing handle of its `subject' (a tmux
session name)."
  (or (alist-get 'session_id event)
      (cdr (gascity-dashboard--parse-assignee (alist-get 'subject event)))))

(defun gascity-dashboard--session-agent (subject agents)
  "Return (LABEL . AGENT) for the tmux session name SUBJECT.
gc names a session `<pack>__<template>-<id>' (`bd__dog-ec-usd0'); the
label is the agent that ran it — the one agent of AGENTS named after
the template, else the pool (`bd.dog') — never the tmux prefix.  AGENT
is that agent's plist when exactly one matches, else nil."
  (let* ((role (car (gascity-dashboard--parse-assignee subject)))
         (template (replace-regexp-in-string "__" "." (or role "")))
         (short (lambda (a) (let ((n (plist-get a :name)))
                              (if (string-search "/" n)
                                  (substring n (1+ (string-search "/" n)))
                                n))))
         (exact (seq-filter (lambda (a) (equal (funcall short a) template)) agents))
         (members (seq-filter (lambda (a) (string-prefix-p (concat template "-")
                                                           (funcall short a)))
                              agents)))
    (cond ((= (length exact) 1) (cons (plist-get (car exact) :name) (car exact)))
          ((= (length members) 1) (cons (plist-get (car members) :name) (car members)))
          (t (cons (if (string-empty-p template) (or subject "?") template) nil)))))

(defun gascity-dashboard--claimed-at (bead)
  "Return BEAD's claim timestamp: `started_at', `gc.claimed_at', `updated_at'."
  (or (alist-get 'started_at bead)
      (alist-get 'gc.claimed_at (gascity-dashboard--meta bead))
      (alist-get 'updated_at bead)))

(defun gascity-dashboard--session-active-after-p (session timestamp)
  "Return non-nil when live SESSION was active after TIMESTAMP.
A session whose `last_active' is unknown cannot show activity, so it
answers nil (no evidence either way)."
  (let ((active (and session (gascity-ui-parse-time
                              (alist-get 'last_active session)))))
    (and active timestamp (> active timestamp))))

(defun gascity-dashboard--stale-work (ctx)
  "Return the in-progress work of CTX whose holder is gone or lease lapsed.
Each entry is a plist :bead :assignee :dead :root :claimed :lease,
with :lease the seconds left before `lease_expires_at' (negative once
lapsed) and :claimed the float claim time.

Only real work counts: an in-progress wisp, session, convoy, nudge or
message bead is never flagged (its holder is not a worker).  An entry
is stale when either

  - its assignee has no live session behind it (`gone'), or
  - its lease has lapsed and the holder cannot show activity after that
deadline.  `gc bd heartbeat' keeps a claim's lease alive; a worker that
dies stops heartbeating.  pi workers in practice do not heartbeat, so an
active worker's lease lapses while it works: a live session whose
`last_active' is after `lease_expires_at' is not condemned for it (the
Work row still shows the lease).  A holder silent past its own deadline
is the stall `gc bd reclaim' is about.

Pure over CTX's work and session payloads: no extra gc read
\(dashboard-v3 §8.3 R2, ga-o7vtw)."
  (let ((sessions (plist-get ctx :sessions))
        (now (plist-get ctx :now))
        (out nil))
    (dolist (bead (plist-get ctx :beads))
      (when (and (equal (alist-get 'status bead) "in_progress")
                 (null (gascity-event-noise bead)))
        (let* ((assignee (alist-get 'assignee bead))
               (assigned (and (stringp assignee) (not (string-empty-p assignee))))
               (live (and assigned (gascity-dashboard--session-for-assignee
                                    assignee sessions)))
               (lease (gascity-ui-parse-time (alist-get 'lease_expires_at bead)))
               (left (and lease (- lease now)))
               (dead (and assigned (not live)))
               (lapsed (and left (<= left 0)
                            (not (gascity-dashboard--session-active-after-p
                                  live lease)))))
          (when (or dead lapsed)
            (push (list :bead bead
                        :assignee (and assigned assignee)
                        :dead dead
                        :root (gascity-dashboard--root-of bead)
                        :claimed (gascity-ui-parse-time
                                  (gascity-dashboard--claimed-at bead))
                        :lease left)
                  out)))))
    (nreverse out)))

(defun gascity-dashboard--stale-work-text (entry now)
  "Return the one-line Needs you text of stale-work ENTRY at NOW.
Names the bead, the assignee (and `gone' when its session is), the age
since it was claimed and the lease's expiry."
  (let* ((bead (plist-get entry :bead))
         (assignee (plist-get entry :assignee))
         (claimed (plist-get entry :claimed))
         (left (plist-get entry :lease)))
    (concat (or (alist-get 'id bead) "?")
            "  " (cond ((null assignee) "unassigned")
                        ((plist-get entry :dead) (concat assignee " gone"))
                        (t assignee))
            (if claimed
                (format "  age %s" (gascity-ui-duration (- now claimed)))
              "")
            (if left
                (format "  lease %s %s"
                        (if (<= left 0) "lapsed" "in")
                        (gascity-ui-duration (abs left)))
              ""))))

(defun gascity-dashboard--stale-work-drawer (entry now)
  "Return the drawer lines of stale-work ENTRY at NOW."
  (let* ((bead (plist-get entry :bead))
         (claimed (plist-get entry :claimed))
         (left (plist-get entry :lease)))
    (append
     (list (or (alist-get 'title bead) "?"))
     (list (concat (format "run %s" (or (plist-get entry :root) "none"))
                   (if left
                       (format " · lease %s %s"
                               (if (<= left 0) "lapsed" "expires in")
                               (gascity-ui-duration (abs left)))
                     "")
                   (if claimed
                       (format " · claimed %s ago"
                               (gascity-ui-duration (- now claimed)))
                     "")))
     (gascity-dashboard--bead-drawer bead))))

(defun gascity-dashboard--stale-work-items (ctx)
  "Return CTX's Needs you fail items for stale in-progress work.
One item per `gascity-dashboard--stale-work' entry; its row names the
bead, assignee, age and lease, and its drawer the run and the step."
  (let ((now (plist-get ctx :now)))
    (mapcar
     (lambda (entry)
       (let* ((bead (plist-get entry :bead))
              (id (alist-get 'id bead))
              (rig (alist-get 'gascity-rig bead)))
         (list :level 'fail :kind "work"
               :id (concat "stale-work:" id)
               :text (gascity-dashboard--stale-work-text entry now)
               ;; The text carries the age and lease: a wider cell, no
               ;; separate time column (`gascity-dashboard--needs-you-lines').
               :width 56
               :right (or (plist-get entry :root) rig "city")
               :drawer (lambda () (gascity-dashboard--stale-work-drawer entry now))
               :props (list 'gascity-bead id
                            'gascity-run-rig (or rig "")))))
     (gascity-dashboard--stale-work ctx))))

(defun gascity-dashboard--needs-you-items (ctx)
  "Return CTX's Needs you items, computed once per render.
The render stores them in CTX (`:needs-you'); the section and the pulse
both read them."
  (or (plist-get ctx :needs-you) (gascity-dashboard--needs-you ctx)))

(defun gascity-dashboard--needs-you (ctx)
  "Return the Needs you items for cockpit context CTX, ■ before ▲.
Each item is a plist (:level fail|watch :kind KIND :id ID :text TEXT
:right RIGHT :time TS :props PROPS), PROPS being the at-point text
properties of its row.  Sources, in priority order: stalled agents,
in-progress work whose holder is gone or lease lapsed, crashed/timed-out
sessions not woken since, idle runs (no step activity and no live
worker), failed runs (the Runs view's failed window), reopened beads,
escalated/held beads, unread mail, store health."
  (let* ((now (plist-get ctx :now))
         (events (plist-get ctx :events))
         (sessions (plist-get ctx :sessions))
         (beads (plist-get ctx :beads))
         (run-beads (plist-get ctx :run-beads))
         (run-index (and run-beads (gascity-runs-index run-beads)))
         (items nil))
    (cl-flet ((add (&rest item) (push item items)))
      ;; ■ stalled agents: gc says running, no live session.
      (dolist (a (plist-get ctx :agents))
        (when (eq (plist-get a :state) 'stalled)
          (let* ((name (plist-get a :name))
                 (stall (gascity-dashboard--agent-stall a))
                 (rig (gascity-dashboard--rig-of name))
                 ;; 20 fitted name columns plus the whole reason; the honest
                 ;; `unknown' token is longer than any duration, so the cell
                 ;; grows for it instead of cutting the age (REQ-005).
                 (text (concat (gascity-ui-fit name 20)
                               "  running, no live session  "
                               (gascity-dashboard--stall-age stall now))))
            (add :level 'fail :kind "agent" :id (concat "agent:" name)
                 ;; Fit the name, never the reason: the reason stays whole
                 ;; and the age rides along as a token (REQ-005).
                 :text text
                 :width (max 51 (string-width text))
                 ;; A rig-qualified name carries its rig; a city-scope
                 ;; agent (mayor, bd.dog-1) keeps its scope.
                 :right (and (null rig) (or (plist-get a :rig) "city"))
                 :drawer (lambda () (gascity-dashboard--agent-drawer a))
                 :props (list 'gascity-agent (plist-get a :object))))))
      ;; ■ in-progress work whose assignee session is gone or whose lease
      ;; has lapsed: the stall a run's own idle check cannot see when the
      ;; step still looks freshly claimed (ga-o7vtw).
      (dolist (item (gascity-dashboard--stale-work-items ctx))
        (apply #'add item))
      ;; ■ sessions that crashed or timed out and were not woken since,
      ;; one row per agent (or pool) and signal type, ×N (QA #6).
      (let ((woke (make-hash-table :test 'equal))
            (seen (make-hash-table :test 'equal))
            (groups nil))
        (dolist (e events)
          (when (equal (alist-get 'type e) "session.woke")
            (let ((id (gascity-dashboard--session-id-of e)))
              (when id
                (puthash id (max (gethash id woke 0)
                                 (gascity-event-time e))
                         woke)))))
        (dolist (e (reverse events))
          (when (member (alist-get 'type e)
                        '("session.crashed" "session.cold_start_timeout"))
            (let* ((id (gascity-dashboard--session-id-of e))
                   (key (or id (alist-get 'subject e))))
              (unless (or (gethash key seen)
                          (and id (> (gethash id woke 0)
                                     (gascity-event-time e))))
                (puthash key t seen)
                (let* ((who (gascity-dashboard--session-agent
                             (alist-get 'subject e) (plist-get ctx :all-agents)))
                       (gkey (cons (car who) (alist-get 'type e)))
                       (group (assoc gkey groups)))
                  ;; Newest first: the first event seen is the latest.
                  (if group
                      (setcdr group (append (cdr group) (list e)))
                    (setq groups (append groups (list (list gkey who e))))))))))
        (pcase-dolist (`((,label . ,type) ,who . ,evs) groups)
          (let* ((latest (car evs))
                 (agent (cdr who)))
            (add :level 'fail :kind "session"
                 :id (format "session:%s:%s" label type)
                 :text (format "%s  %s%s" label
                               (if (equal type "session.crashed")
                                   "crashed" "cold start timeout")
                               (if (cdr evs) (format " ×%d" (length evs)) ""))
                 :right (or (gascity-dashboard--session-id-of latest) "")
                 :time (alist-get 'ts latest)
                 ;; RET: that agent's detail, else the Agents view.
                 :props (list 'gascity-dashboard-event latest
                              'gascity-dashboard-target
                              (if agent
                                  (let ((obj (plist-get agent :object)))
                                    (lambda () (interactive)
                                      (gascity-polecat-detail obj)))
                                #'gascity-jump-agents))))))
      ;; ■ idle runs: no in-progress step touched within the threshold —
      ;; nor, behind an open drain step, any in-progress member run
      ;; (`gascity-runs-last-activity' over the Runs view's index).  A
      ;; run with an open drain step waits for that index: judged on
      ;; its own steps alone it would look idle while its members work.
      ;; A live worker session keeps a run out of this section however
      ;; stale its step beads look (ec-elkm5.3): the worker's liveness,
      ;; not the bead's `updated_at', is the authority.
      (dolist (root (gascity-dashboard--active-runs beads))
        (let* ((id (alist-get 'id root))
               (graph (and run-index (gascity-runs-graph run-index id)))
               (steps (seq-filter (lambda (b)
                                    (and (equal (gascity-dashboard--root-of b) id)
                                         (not (equal (alist-get 'status b) "closed"))))
                                  beads))
               (all-steps (append steps graph))
               (draining (seq-some (lambda (b) (equal (alist-get 'gc.kind
                                                                 (gascity-dashboard--meta b))
                                                      "drain"))
                                   steps))
               (evidence (gascity-dashboard--run-idle-evidence
                          root all-steps run-index))
               (last (plist-get evidence :time))
               (idle (- now last))
               (worker (gascity-dashboard--run-live-worker
                        root all-steps run-index sessions)))
          (when (and (not worker)
                     (> last 0) (> idle gascity-dashboard-run-idle-threshold)
                     (or run-index (not draining)))
            (add :level 'fail :kind "run" :id (concat "run:" id)
                 :text (format "%s %s  idle %s" id
                               (or (alist-get 'gc.formula_name
                                              (gascity-dashboard--meta root))
                                   (alist-get 'title root) "")
                               (gascity-ui-duration idle))
                 :right (or (alist-get 'gascity-rig root) "city")
                 :drawer (lambda ()
                           (gascity-dashboard--idle-run-drawer
                            root all-steps run-index now idle))
                 :props (list 'gascity-bead id
                              'gascity-run-rig
                              (or (alist-get 'gascity-rig root) ""))))))
      ;; ■ active runs with a failed step: the root is still in
      ;; progress (a drain step failed, or a nested step failed) yet
      ;; the run reads `active' everywhere else (ga-g092a).  The Runs
      ;; read carries the closed failed step the work read drops.
      (when run-index
        (let ((seen (make-hash-table :test 'equal)))
          (dolist (root (gascity-dashboard--active-runs run-beads))
            (let* ((id (alist-get 'id root))
                   (step (gascity-runs-failed-step run-index root)))
              (when (and step (not (gethash id seen)))
                (puthash id t seen)
                (add :level 'fail :kind "run"
                     :id (concat "failed-step:" id)
                     :text (format "%s %s %s" id (gascity-ui-glyph 'failed)
                                   (or (plist-get step :ref)
                                       (plist-get step :name) "?"))
                     :right (or (plist-get step :class)
                                (alist-get 'gascity-rig root) "city")
                     :props (list 'gascity-bead id
                                  'gascity-run-rig
                                  (or (alist-get 'gascity-rig root) ""))
                     :drawer (lambda ()
                               (gascity-dashboard--failed-step-drawer root step))))))))
      ;; ■ runs that failed in the Runs view's failed window.  That read
      ;; is the source (one window, one deduction: a run in the Runs
      ;; Failed section is here too, and vice versa); the 2h events read
      ;; is only the fallback before the Runs read lands, so a run is
      ;; never counted twice (ec-elkm5.2).  The row carries the failure
      ;; class (the rig moves to the drawer) and the drawer explains the
      ;; failure (REQ-001).
      (let ((seen (make-hash-table :test 'equal)))
        (when run-index
          (let ((window (gascity-runs-window-seconds
                         gascity-runs-failed-window)))
            (dolist (root (gascity-dashboard--failed-run-roots
                           run-index window now))
              (puthash (alist-get 'id root) t seen)
              (apply #'add (gascity-dashboard--failed-run-item
                            root ctx run-index (gascity-runs--time root))))))
        (dolist (e (reverse events))
          (let* ((bead (gascity-event-bead e))
                 (meta (and bead (gascity-dashboard--meta bead)))
                 (id (and bead (alist-get 'id bead))))
            (when (and (equal (alist-get 'type e) "bead.closed")
                       (equal (alist-get 'gc.kind meta) "workflow")
                       (equal (alist-get 'gc.outcome meta) "fail")
                       (not (gethash id seen)))
              (puthash id t seen)
              (apply #'add (gascity-dashboard--failed-run-item
                            bead ctx run-index (alist-get 'ts e)))))))
      ;; ▲ beads reopened after their assignee died.
      (let ((seen (make-hash-table :test 'equal)))
        (dolist (e (reverse events))
          (when (equal (alist-get 'type e) "bead.dead_assignee_reopened")
            (let* ((payload (alist-get 'payload e))
                   (id (or (and (listp payload) (alist-get 'bead_id payload))
                           (alist-get 'subject e))))
              (unless (gethash id seen)
                (puthash id t seen)
                (add :level 'watch :kind "bead" :id (concat "reopened:" id)
                     :text (format "%s  dead assignee reopened" id)
                     :right (or (gascity-dashboard--store-of-id id ctx) "")
                     :time (alist-get 'ts e)
                     :props (list 'gascity-bead id)))))))
      ;; ▲ escalated or held beads (open).
      (let ((seen (make-hash-table :test 'equal)))
        (dolist (b (append (plist-get ctx :escalations) beads))
          (let ((labels (gascity-dashboard--labels b))
                (id (alist-get 'id b)))
            (when (and (not (equal (alist-get 'status b) "closed"))
                       (not (gethash id seen))
                       (seq-some (lambda (l) (or (equal l "gc:escalation")
                                                 (string-prefix-p "hold:" l)))
                                 labels))
              (puthash id t seen)
              (add :level 'watch :kind "bead" :id (concat "escalated:" id)
                   :text (format "%s  %s  %s" id
                                 (if (member "gc:escalation" labels) "escalated"
                                   (seq-find (lambda (l) (string-prefix-p "hold:" l))
                                             labels))
                                 (or (alist-get 'title b) ""))
                   :right (or (alist-get 'gascity-rig b) "city")
                   :props (list 'gascity-bead id))))))
      ;; ▲ unread mail for the operator (one aggregate row).
      (let ((unread (alist-get 'unread (plist-get ctx :mail))))
        (when (and (numberp unread) (> unread 0))
          (add :level 'watch :kind "mail" :id "mail"
               :text (format "%d unread" unread)
               :right "j m inbox"
               :props (list 'gascity-dashboard-target #'gascity-jump-mail))))
      ;; ▲ store health.
      (let* ((status (plist-get ctx :status))
             (health (alist-get 'store_health (alist-get 'summary status)))
             (partial (gascity-dashboard--partial-errors status)))
        (when (or partial (and health (alist-get 'warning health)))
          (add :level 'watch :kind "store" :id "store"
               :text (if partial
                         (format "health: %s"
                                 (gascity-dashboard--store-health-message
                                  (car partial)))
                       (format "%s per row over threshold"
                               (gascity-dashboard--ratio health)))
               :right "j h health"
               :props (list 'gascity-dashboard-target #'gascity-jump-health)))))
    (let ((items (nreverse items)))
      (append (seq-filter (lambda (i) (eq (plist-get i :level) 'fail)) items)
              (seq-remove (lambda (i) (eq (plist-get i :level) 'fail)) items)))))

(defun gascity-dashboard--partial-errors (status)
  "Return STATUS's `partial_errors' as a list of strings (nil when none)."
  (mapcar (lambda (e) (if (stringp e) e
                        (or (alist-get 'message e) (format "%s" e))))
          (append (alist-get 'partial_errors status) nil)))

(defun gascity-dashboard--store-health-message (message)
  "Return store-health partial MESSAGE without a leading label.
`gc status --json' already prefixes these messages with \"store
health: \"; a view that prepends its own label rendered the text
twice (ga-jqt9q.1).  MESSAGE is returned unchanged when it carries
no label, so a payload from a gc that omits it still displays."
  (let ((label "store health: "))
    (if (string-prefix-p label message)
        (substring message (length label))
      message)))

(defun gascity-dashboard--ratio (health)
  "Return store HEALTH's MB-per-row ratio as a short string."
  (let ((ratio (alist-get 'ratio_mb_per_row health)))
    (if (numberp ratio) (format "%.2f MB" ratio) "?")))

(defun gascity-dashboard--store-of-id (id ctx)
  "Return the rig owning bead ID's prefix in CTX, or nil."
  (when-let* ((prefix (gascity-beads--id-prefix id)))
    (car (seq-find (lambda (r) (equal (cdr r) prefix))
                   (plist-get ctx :rig-prefixes)))))

;;; Formatting

(defun gascity-dashboard--bytes (bytes)
  "Return BYTES as a short decimal size (`370 MB')."
  (cond ((not (numberp bytes)) "?")
        ((>= bytes 1e9) (format "%.1f GB" (/ bytes 1e9)))
        ((>= bytes 1e6) (format "%d MB" (round (/ bytes 1e6))))
        ((>= bytes 1e3) (format "%d kB" (round (/ bytes 1e3))))
        (t (format "%d B" bytes))))

(defun gascity-dashboard--home ()
  "Return the home directory display paths abbreviate to `~', host-local.
Pure string work (§8.3 R2): a remote city's home is `/home/USER/' of the
TRAMP user (default the local login), a local one `~' expanded."
  (if (file-remote-p default-directory)
      (format "/home/%s/" (or (file-remote-p default-directory 'user)
                              user-login-name))
    (file-name-as-directory (expand-file-name "~"))))

(defun gascity-dashboard--path (path)
  "Return host-local PATH with the home prefix shown as `~/'."
  (let ((home (gascity-dashboard--home)))
    (cond ((not (stringp path)) "")
          ((string-prefix-p home path) (concat "~/" (substring path (length home))))
          (t path))))

(defun gascity-dashboard--line (text &rest props)
  "Return TEXT with PROPS added over its whole length (faces kept)."
  (let ((s (copy-sequence text)))
    (when props (add-text-properties 0 (length s) props s))
    s))

(defun gascity-dashboard--row (left right &rest props)
  "Return a row: LEFT, then RIGHT right-aligned at the cockpit width.
PROPS are the row's text properties (its thing and object)."
  (apply #'gascity-dashboard--line
         (if (and right (not (string-empty-p right)))
             (gascity-ui-right-align left right gascity-dashboard--width)
           left)
         props))

(defun gascity-dashboard--dim (text)
  "Return TEXT in the dim face."
  (propertize (or text "") 'face 'gascity-dim))

(defun gascity-dashboard--thing (kind id &optional toggle)
  "Return a `beads-thing' value of KIND for ID, toggled by TOGGLE."
  (list :kind kind :id id :toggle toggle))

;;; Cockpit context

(defun gascity-dashboard--data (load)
  "Return LOAD's usable data (fresh or stale), or nil."
  (and (memq (plist-get load :state) '(ready stale)) (plist-get load :data)))

(defun gascity-dashboard--context (loads filters now)
  "Return the render context from the section LOADS under FILTERS at NOW.
LOADS is a plist of `gascity-dashboard--effective-load' results keyed
:status :sessions :mail :events :work :convoys :escalations :runs :rigs."
  (let* ((status (gascity-dashboard--data (plist-get loads :status)))
         (sessions (append (alist-get 'sessions
                                      (gascity-dashboard--data
                                       (plist-get loads :sessions)))
                           nil))
         (work (gascity-dashboard--data (plist-get loads :work)))
         (beads (plist-get work :beads))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status)
                                              'no-probe))
         (rig (plist-get filters :rig))
         ;; `gc status' omits the city HQ rig; `gc rig list' carries it
         ;; (WI-11 finding F4).  Prefer the full list so the Rigs section
         ;; agrees with `gascity-rig-list' (ga-jqt9q.4), and fall back to
         ;; the status rows while the rig-list read is in flight or failed.
         (rig-list (gascity-dashboard--data (plist-get loads :rigs)))
         (rigs (or (append (alist-get 'rigs rig-list) nil)
                   (append (alist-get 'rigs status) nil)))
         (agents (gascity-dashboard--agents status sessions beads socket now))
         (events (car (gascity-dashboard--data (plist-get loads :events)))))
    (list :now now
          :filters filters
          :loads loads
          :status status
          :sessions sessions
          :socket socket
          :mail (gascity-dashboard--data (plist-get loads :mail))
          :events events
          :beads beads
          :work-errors (plist-get work :errors)
          :convoys (append (alist-get 'convoys
                                      (gascity-dashboard--data
                                       (plist-get loads :convoys)))
                           nil)
          :escalations (append (gascity-dashboard--data
                                (plist-get loads :escalations))
                               nil)
          :run-beads (plist-get (gascity-dashboard--data (plist-get loads :runs))
                                :beads)
          :rigs rigs
          :rig-prefixes (mapcar (lambda (r) (cons (alist-get 'name r)
                                                  (alist-get 'prefix r)))
                                rigs)
          :agents (if rig
                      (seq-filter (lambda (a) (equal (plist-get a :rig) rig))
                                  agents)
                    agents)
          :all-agents agents)))

(defun gascity-dashboard--in-rig-p (bead ctx)
  "Return non-nil when BEAD passes CTX's rig filter."
  (let ((rig (plist-get (plist-get ctx :filters) :rig)))
    (or (null rig) (equal (alist-get 'gascity-rig bead) rig))))

;;; Section chrome

(defun gascity-dashboard--section-lines (name title summary body ctx
                                              &rest opts)
  "Return the lines of section NAME: header TITLE SUMMARY, then BODY.
BODY is a list of row strings; CTX the render context.  OPTS: :loads
\(the load keys this section reads — their states decide `…', the
error line or `◐'), :hint (right-aligned on the header), :hidden (a
right-aligned tally), :label (the gc read named in an error line).
A folded section (root state) shows only its header, `▸'-marked."
  (let* ((state (plist-get ctx :view))
         (folded (member name (plist-get state :collapsed)))
         (loads (mapcar (lambda (k) (plist-get (plist-get ctx :loads) k))
                        (plist-get opts :loads)))
         (dataless (and loads (seq-every-p
                                (lambda (l) (not (gascity-dashboard--data l)))
                                loads)))
         (errors (delq nil (mapcar (lambda (l) (plist-get l :error)) loads)))
         (pending (and dataless (seq-some (lambda (l) (eq (plist-get l :state)
                                                          'pending))
                                          loads)))
         (summary (cond (pending (gascity-dashboard--dim "…"))
                        ((and dataless errors) nil)
                        ((and (null body) (member summary '(nil ""))) "none")
                        (t summary)))
         (right (string-join (delq nil (list (plist-get opts :hidden)
                                             (and (plist-get opts :hint)
                                                  (gascity-dashboard--dim
                                                   (plist-get opts :hint)))))
                             "  "))
         (partial (and errors (not dataless)
                       (gascity-ui-stale-mark loads)))
         (header (gascity-dashboard--row
                  (concat (if folded (concat (gascity-ui-glyph 'folded) " ") "")
                          (propertize title 'face 'gascity-header)
                          (if (and summary (not (string-empty-p summary)))
                              (concat "  " (let ((s (copy-sequence summary)))
                                             (add-face-text-property
                                              0 (length s) 'gascity-dim t s)
                                             s))
                            "")
                          (or partial ""))
                  (if folded "" right)
                  'gascity-section t
                  'gascity-dashboard-section name
                  'beads-thing (gascity-dashboard--thing
                                'section name
                                (lambda () (gascity-dashboard--flip :collapsed name))))))
    (gascity-dashboard--expand-stamp
     name
     (cons header
          (cond (folded nil)
                (pending nil)
                ((and dataless errors)
                 (list (gascity-dashboard--line
                        (concat "  " (gascity-ui-glyph 'fail) " "
                                (gascity-dashboard--dim
                                 (format "gc %s: %s   g retry"
                                         (or (plist-get opts :label) name)
                                         (or (gascity-ui-first-line (car errors))
                                             "failed")))))))
                (t body))))))

(defun gascity-dashboard--expand-stamp (key lines)
  "Mark LINES as part of the `+'/`-' expandable section KEY.
Lines already marked (an unfolded churn row's own) keep theirs."
  (mapcar (lambda (line)
            (if (or (string-empty-p line)
                    (text-property-not-all 0 (length line) 'gascity-expand-key nil line))
                line
              (gascity-dashboard--line line 'gascity-expand-key key)))
          lines))

(defun gascity-dashboard--cap-groups (groups name target &optional fold)
  "Flatten GROUPS (the lines of one item each), capped for section NAME.
Shows at most `gascity-dashboard-section-rows' items, then a `… N more'
line whose RET runs TARGET (§4.2).  With FOLD, SPC on the more line
expands the section in place instead of leaving it."
  (let* ((max (+ gascity-dashboard-section-rows
                 (gascity-section-extra name (plist-get gascity-dashboard--view :extra))))
         (total (length groups))
         (id (concat "more:" name))
         (expanded (and fold (member id (plist-get gascity-dashboard--view
                                                   :expanded)))))
    (if (or expanded (<= total max))
        (apply #'append groups)
      (append (apply #'append (seq-take groups max))
              (list (gascity-dashboard--row
                     (gascity-dashboard--dim (format "  … %d more" (- total max)))
                     (gascity-dashboard--dim
                      (concat "+ more  " (gascity-dashboard--target-hint target)))
                     'gascity-dashboard-target target
                     'gascity-expand-more t
                     'beads-thing (gascity-dashboard--thing
                                   'more id
                                   (and fold
                                        (lambda ()
                                          (gascity-dashboard--flip :expanded id))))))))))

(defconst gascity-dashboard--hints
  '((gascity-jump-agents . "j a all")
    (gascity-jump-runs . "j r runs")
    (gascity-jump-beads . "j b beads")
    (gascity-jump-mail . "j m inbox")
    (gascity-jump-events . "j e events")
    (gascity-jump-health . "j h health")
    (gascity-rig-list . "rig list"))
  "The right-aligned hint naming where a `… N more' line leads.")

(defun gascity-dashboard--target-hint (target)
  "Return the `j …' hint for jump TARGET."
  (or (alist-get target gascity-dashboard--hints)
      (car (rassq target gascity-dashboard--jumps))
      ""))

(defun gascity-dashboard--drawer-open-p (id)
  "Return non-nil when the inline drawer of ID is open."
  (member id (plist-get gascity-dashboard--view :drawers)))

(defun gascity-dashboard--drawer (lines)
  "Return drawer LINES (strings) as dim `│'-prefixed decoration rows."
  (mapcar (lambda (l) (concat "  " (gascity-dashboard--dim "│ ") l)) lines))

(defun gascity-dashboard--object-row (id left right drawer-fn &rest props)
  "Return the row for object ID (LEFT/RIGHT) and its drawer when open.
DRAWER-FN returns the drawer's lines; PROPS are the row's object
properties.  The row is a thing whose SPC toggles the drawer."
  (cons (apply #'gascity-dashboard--row left right
               'beads-thing (gascity-dashboard--thing
                             'row id (lambda () (gascity-dashboard--flip :drawers id)))
               props)
        (and (gascity-dashboard--drawer-open-p id)
             (gascity-dashboard--drawer (funcall drawer-fn)))))

;;; Top lines

(defun gascity-dashboard--top-lines (ctx)
  "Return the two top lines (city/path, summary) of CTX, decoration only."
  (let* ((status (plist-get ctx :status))
         (city (or (alist-get 'city_name status)
                   (gascity-context-city-name) "?"))
         (controller (alist-get 'controller status))
         (health (alist-get 'health status))
         (right (cond ((null status) "")
                      ((alist-get 'suspended status)
                       (propertize "city suspended" 'face 'gascity-suspended))
                      ((not (alist-get 'running controller))
                       (concat (gascity-ui-glyph 'fail)
                               (propertize " controller down" 'face 'gascity-failed)))
                      ((alist-get 'degraded health)
                       (concat (gascity-ui-glyph 'watch)
                               (propertize
                                (format " degraded%s"
                                        (let ((sig (append (alist-get 'signals health) nil)))
                                          (if sig (format " (%s)" (string-join sig ", ")) "")))
                                'face 'gascity-warning)))
                      (t (gascity-dashboard--dim
                          (format "%s %s" (or (alist-get 'mode controller) "controller")
                                  (gascity-ui-glyph 'ok))))))
         (line1 (gascity-ui-right-align
                 (concat (propertize city 'face 'gascity-city) "  "
                         (gascity-dashboard--dim
                          (gascity-dashboard--path
                           (or (alist-get 'city_path status)
                               (file-local-name default-directory)))))
                 right gascity-dashboard--width)))
    (if (null status)
        (list line1)
      (list line1 (gascity-dashboard--summary-line ctx)))))

(defun gascity-dashboard--summary-line (ctx)
  "Return the cockpit's summary line for CTX (§7.1 top line)."
  (let* ((status (plist-get ctx :status))
         (agents (plist-get ctx :all-agents))
         ;; The Agents section's own count (QA #7): idle is not running.
         (running (car (gascity-dashboard-agent-counts agents)))
         (sessions (seq-count #'gascity-dashboard--live-session-p
                              (plist-get ctx :sessions)))
         (beads (plist-get ctx :beads))
         (runs (length (gascity-dashboard--active-runs beads)))
         (failed (gascity-dashboard--runs-closed ctx "fail"))
         (done (gascity-dashboard--runs-closed ctx "pass"))
         (ready (length (plist-get (gascity-dashboard--work ctx) :ready)))
         (unread (alist-get 'unread (plist-get ctx :mail)))
         (health (alist-get 'store_health (alist-get 'summary status)))
         (partial (gascity-dashboard--partial-errors status))
         (parts
          (delq nil
                (list
                 (format "agents %d/%d %s" running (length agents)
                         (gascity-ui-glyph
                          (cond ((alist-get 'degraded (alist-get 'health status))
                                 'watch)
                                ((> running 0) 'ok)
                                (t 'idle))))
                 (and (plist-get ctx :sessions) (format "sessions %d" sessions))
                 (and beads
                      (concat (format "runs %d" runs)
                              (if (> runs 0) (concat " " (gascity-ui-glyph 'active)) "")
                              (if (> failed 0)
                                  (format " · %d %s" failed (gascity-ui-glyph 'failed))
                                "")
                              (if (> done 0) (format " · %d done" done) "")))
                 (and beads (format "ready %d" ready))
                 (and (numberp unread)
                      (if (> unread 0)
                          (concat "mail " (gascity-ui-glyph 'watch)
                                  (propertize (number-to-string unread)
                                              'face 'gascity-warning))
                        "mail 0"))
                 (and health
                      (concat "dolt "
                              (gascity-dashboard--bytes (alist-get 'size_bytes health))
                              " "
                              (cond (partial
                                     (propertize (gascity-ui-glyph 'partial)
                                                 'help-echo
                                                 (concat "store health: "
                                                         (mapconcat
                                                          #'gascity-dashboard--store-health-message
                                                          partial "; "))))
                                    ((alist-get 'warning health)
                                     (gascity-ui-glyph 'watch))
                                    (t (gascity-ui-glyph 'ok)))))))))
    (concat " " (string-join parts "   "))))

(defun gascity-dashboard--runs-closed (ctx outcome)
  "Return how many runs closed with OUTCOME in CTX's event window."
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (e (plist-get ctx :events))
      (let* ((bead (gascity-event-bead e))
             (meta (and bead (gascity-dashboard--meta bead))))
        (when (and (equal (alist-get 'type e) "bead.closed")
                   (equal (alist-get 'gc.kind meta) "workflow")
                   (equal (alist-get 'gc.outcome meta) outcome))
          (puthash (alist-get 'id bead) t seen))))
    (hash-table-count seen)))

;;; Sections

(defun gascity-dashboard--needs-you-lines (ctx)
  "Return the Needs you section lines for CTX."
  (let* ((items (gascity-dashboard--needs-you-items ctx))
         (groups (mapcar
                (lambda (item)
                  (apply
                   #'gascity-dashboard--object-row
                   ;; Own drawer ids: the same agent in Agents keeps its own.
                   (concat "needs:" (plist-get item :id))
                   (concat "  " (gascity-ui-glyph (plist-get item :level)) " "
                           (gascity-ui-fit (plist-get item :kind) 8) " "
                           (gascity-ui-fit (plist-get item :text)
                                           (or (plist-get item :width) 48))
                           (if (plist-get item :time)
                               (concat " " (gascity-ui-fit
                                            (gascity-ui-time (plist-get item :time)
                                                             (plist-get ctx :now))
                                            4))
                             ""))
                   (gascity-dashboard--dim (plist-get item :right))
                   (lambda () (gascity-dashboard--needs-you-drawer item))
                   (plist-get item :props)))
                items)))
    (gascity-dashboard--section-lines
     "needs-you" "Needs you"
     (and items (number-to-string (length items)))
     (gascity-dashboard--cap-groups groups "needs-you" #'gascity-jump-events t)
     ctx :loads '(:status :sessions :events :work :runs :mail :escalations)
     :label "status")))

(defun gascity-dashboard--failed-step-drawer (root step)
  "Return the drawer lines of a failed STEP in run ROOT.
The Needs-you row names the run and the step ref; the drawer adds the
failure class, reason and member run (ga-g092a)."
  (delq nil
        (list (format "run      %s  %s"
                      (alist-get 'id root)
                      (or (alist-get 'gc.formula_name
                                     (gascity-dashboard--meta root))
                          (alist-get 'title root) ""))
              (format "step     %s  %s" (or (plist-get step :name) "")
                      (or (plist-get step :ref) ""))
              (and (plist-get step :class)
                   (format "class    %s" (plist-get step :class)))
              (and (plist-get step :reason)
                   (format "reason   %s" (plist-get step :reason)))
              (and (plist-get step :member)
                   (format "member   %s%s" (plist-get step :member)
                           (if (plist-get step :member-ref)
                               (concat "  " (plist-get step :member-ref))
                             ""))))))

(defun gascity-dashboard--failed-run-detail (bead index)
  "Return (:class CLASS :ref REF :reason REASON :full FULL) for failed run BEAD.
INDEX is the Runs index, or nil before that read lands.  The failed
step is consulted first (its class, ref and reason), then the run's own
failure, then the event bead itself (`gc.failure_class'/
`gc.failure_reason', falling back to its close reason).  REASON is the
first line of the failure reason -- what a drawer can show in one row
-- and FULL is the complete text, for `help-echo'."
  (let* ((step (and index bead (gascity-runs-failed-step index bead)))
         (run (and index bead (gascity-runs-summary index bead)))
         (info (or (and step
                        (or (plist-get step :class) (plist-get step :reason))
                        (cons (plist-get step :class) (plist-get step :reason)))
                   (and run (gascity-runs--run-failure run index bead))
                   (gascity-runs--failure-info (list bead))))
         (meta (gascity-dashboard--meta bead))
         (class (or (car-safe info)
                    (alist-get 'gc.failure_class meta)))
         (reason (or (cdr-safe info)
                     (alist-get 'gc.failure_reason meta)
                     (gascity-runs--close-reason bead)))
         (ref (or (plist-get step :ref)
                  (alist-get 'gc.step_ref meta))))
    (list :class class :ref ref
          :reason (gascity-ui-first-line reason)
          :full reason)))

(defun gascity-dashboard--failed-run-drawer (bead index)
  "Return the drawer lines of failed run BEAD in INDEX (REQ-001).
The run id and formula, the failure class, the failed step ref and the
first line of the reason (the full reason in `help-echo'), then the
RET/b hint.  Always the run line and the hint, even when the failure
names no class or reason.  Pure over the cockpit context: no gc read."
  (let* ((detail (gascity-dashboard--failed-run-detail bead index))
         (meta (gascity-dashboard--meta bead))
         (class (plist-get detail :class))
         (ref (plist-get detail :ref))
         (reason (plist-get detail :reason))
         (full (plist-get detail :full)))
    (delq nil
          (list (gascity-dashboard--drawer-value
                 "run      " (format "%s  %s" (alist-get 'id bead)
                                      (or (alist-get 'gc.formula_name meta) "")))
                (and class
                     (gascity-dashboard--drawer-value "class    " class))
                (and ref
                     (gascity-dashboard--drawer-value "step     " ref))
                (and reason
                     (gascity-dashboard--drawer-value "reason   " reason full))
                (gascity-dashboard--dim "RET run detail  b root bead")))))

(defun gascity-dashboard--failed-run-roots (index window now)
  "Return INDEX's run roots failed within WINDOW seconds of NOW.
WINDOW nil means no bound.  The roots come oldest first, so the
Needs-you list (newest first after its `nreverse') reads like the Runs
Failed section.  This is the Runs view's deduction: a failed run the
Runs Failed section shows is in Needs you too, never a second source
with its own window (ec-elkm5.2)."
  (sort (seq-filter
         (lambda (root)
           (and (eq (gascity-runs-state root) 'failed)
                (gascity-runs--within-p
                 (list :time (gascity-runs--time root)) window now)))
         (plist-get index :roots))
        (lambda (a b)
          (< (or (gascity-ui-parse-time (gascity-runs--time a)) 0)
             (or (gascity-ui-parse-time (gascity-runs--time b)) 0)))))

(defun gascity-dashboard--failed-run-item (bead ctx index time)
  "Return the Needs you item of failed run BEAD (its root) at TIME.
INDEX is the Runs index (nil before it lands); CTX supplies the rig
when BEAD carries none.  The row carries the failure class, the drawer
explains it (REQ-001)."
  (let* ((id (alist-get 'id bead))
         (meta (gascity-dashboard--meta bead))
         (detail (gascity-dashboard--failed-run-detail bead index))
         (rig (or (alist-get 'gascity-rig bead)
                  (gascity-dashboard--store-of-id id ctx)))
         ;; Class first, then the rig, then the city.  The class is cut to
         ;; 20 columns with the full text in `help-echo' (Decisions 3).
         (right (gascity-ui-truncate
                 (or (plist-get detail :class) rig "city") 20)))
    (list :level 'fail :kind "run" :id (concat "failed:" id)
          :text (format "%s %s  failed" id
                        (or (alist-get 'gc.formula_name meta) ""))
          ;; `gascity-ui-right-align' never clips, so the left cell gives
          ;; back what the right cell takes: 18 + WIDTH + 2 + RIGHT = 78.
          :width (max 20 (- 58 (string-width right)))
          :right right
          :time time
          :drawer (lambda () (gascity-dashboard--failed-run-drawer bead index))
          :props (list 'gascity-bead id
                       'gascity-run-rig (or rig "")))))

(defun gascity-dashboard--needs-you-drawer (item)
  "Return the drawer lines of a Needs you ITEM."
  (let ((event (plist-get (plist-get item :props) 'gascity-dashboard-event)))
    (cond ((plist-get item :drawer) (funcall (plist-get item :drawer)))
          (event (gascity-event-fields event))
          (t (list (format "%s  %s" (plist-get item :kind) (plist-get item :text)))))))

(defun gascity-dashboard--moving-lines (ctx)
  "Return the Moving section lines for CTX: runs with their workers.
A drain member run (`gascity-runs-parent-id') nests under the run it
drains for when that run is active here too, recursively; workers nest
under the run they work for.  The cap, `+'/`-' and `… N more' count the
top-level runs; a member whose parent is not shown stays top-level."
  (let* ((beads (seq-filter (lambda (b) (gascity-dashboard--in-rig-p b ctx))
                            (plist-get ctx :beads)))
         (runs (gascity-dashboard--active-runs beads))
         (sessions (plist-get ctx :sessions))
         (run-beads (plist-get ctx :run-beads))
         (index (and run-beads (gascity-runs-index run-beads)))
         (now (plist-get ctx :now))
         (in-progress (seq-filter
                       (lambda (b)
                         (and (equal (alist-get 'status b) "in_progress")
                              (not (gascity-dashboard--run-root-p b))
                              (not (gascity-event-noise b))))
                       beads))
         (run-ids (mapcar (lambda (r) (alist-get 'id r)) runs))
         (flat (seq-remove (lambda (b) (member (gascity-dashboard--root-of b) run-ids))
                           in-progress))
         (children (make-hash-table :test 'equal))
         (top nil)
         (sub-runs 0)
         (workers 0)
         (items nil))
    ;; Nest each member under its parent when the parent is shown.
    (dolist (root runs)
      (let ((parent (and index (gascity-runs-parent-id index root))))
        (if (and parent (member parent run-ids)
                 (not (equal parent (alist-get 'id root))))
            (push root (gethash parent children))
          (push root top))))
    (cl-labels
        ((group (root depth seen)
           (let* ((id (alist-get 'id root))
                  ;; The Runs view's ladder for this run (same entry, same
                  ;; rule); `…' until that read lands — never a partial one.
                  (ladder (and index (gascity-runs-ladder index root)))
                  (label (if index (gascity-dashboard--ladder-label ladder) (cons "" "")))
                  (rig (alist-get 'gascity-rig root))
                  (timing (gascity-runs-timing root now))
                  (under (concat (make-string (* 4 (1+ depth)) ?\s) "└ "))
                  (nested (gascity-dashboard--one-per-worker
                           (seq-filter (lambda (b) (equal (gascity-dashboard--root-of b) id))
                                       in-progress))))
             (append
              (gascity-dashboard--object-row
               (concat "run:" id)
               (concat (if (zerop depth) "  "
                         (concat (make-string (* 4 depth) ?\s) "└ "))
                       (gascity-ui-glyph 'active) " "
                       (gascity-ui-fit id 9) " "
                       (gascity-ui-fit (or (alist-get 'gc.formula_name
                                                      (gascity-dashboard--meta root))
                                           (alist-get 'title root) "")
                                       12)
                       " " (if index (gascity-dashboard--ladder-string ladder)
                             (gascity-dashboard--dim "…"))
                       "  " (gascity-ui-fit (car label) 14)
                       " " (gascity-ui-fit (cdr label) 6)
                       " " (gascity-runs--timing-cell root now))
               (gascity-dashboard--dim (or rig "city"))
               (lambda () (gascity-dashboard--run-drawer ladder))
               'help-echo (plist-get timing :help)
               'gascity-bead id 'gascity-run-rig (or rig ""))
              (mapcan (lambda (b)
                        (setq workers (1+ workers))
                        (gascity-dashboard--worker-row b sessions ctx under t))
                      (seq-take nested 3))
              (mapcan (lambda (member)
                        (unless (member (alist-get 'id member) seen)
                          (setq sub-runs (1+ sub-runs))
                          (group member (1+ depth) (cons id seen))))
                      (reverse (gethash id children)))))))
      (dolist (root (nreverse top))
        (push (group root 0 nil) items)))
    (dolist (b flat)
      (when (gascity-dashboard--session-for-assignee (alist-get 'assignee b) sessions)
        (setq workers (1+ workers)))
      (push (gascity-dashboard--worker-row b sessions ctx "  ") items))
    (setq items (nreverse items))
    (let ((top-runs (- (length runs) sub-runs)))
      (gascity-dashboard--section-lines
       "moving" "Moving"
       (and items
            (concat (format "%d run%s" top-runs (if (= top-runs 1) "" "s"))
                    (if (> sub-runs 0)
                        (format " · %d sub-run%s" sub-runs (if (= sub-runs 1) "" "s"))
                      "")
                    (format " · %d worker%s" workers (if (= workers 1) "" "s"))))
       (gascity-dashboard--cap-groups items "moving" #'gascity-jump-runs)
       ctx :loads '(:work :runs) :label "bd list"))))

(defun gascity-dashboard--one-per-worker (beads)
  "Return BEADS with one bead per assignee, the most specific kept.
A looping step and its current iteration are both in progress under
the same worker; the iteration (it carries `gc.logical_bead_id') names
what the worker does now."
  (let ((seen (make-hash-table :test 'equal))
        (out nil))
    (dolist (b (sort (copy-sequence beads)
                     (lambda (a _) (alist-get 'gc.logical_bead_id
                                              (gascity-dashboard--meta a)))))
      (let ((who (or (alist-get 'assignee b) (alist-get 'id b))))
        (unless (gethash who seen)
          (puthash who t seen)
          (push b out))))
    (nreverse out)))

(defun gascity-dashboard--worker-row (bead sessions ctx indent &optional nested)
  "Return the lines of in-progress BEAD's worker, joined to SESSIONS.
CTX is the render context; INDENT prefixes the row.  NESTED marks a
worker drawn under its run (not a top-level row of the section).  An
in-progress bead nobody holds (no assignee) reads `unassigned' (dim):
it stays in Moving, since Work lists only ready beads, but counts as
no worker."
  (let* ((session (gascity-dashboard--session-for-assignee
                   (alist-get 'assignee bead) sessions))
         (id (alist-get 'id bead))
         (role (car (gascity-dashboard--parse-assignee (alist-get 'assignee bead))))
         (name (cond (session (alist-get 'agent_name session))
                     ((and role (not (string-empty-p role))) role)))
         (agent (and session (gascity-dashboard--agent-object
                              name session (plist-get ctx :socket)))))
    (apply #'gascity-dashboard--object-row
           (concat "work:" id)
           (concat indent (gascity-ui-pending-glyph
                           name (gascity-ui-glyph (if session 'ok 'idle)))
                   " "
                   (if name
                       (gascity-ui-fit (gascity-dashboard--short-agent name) 24)
                     (gascity-dashboard--dim (gascity-ui-fit "unassigned" 24)))
                   " "
                   (gascity-ui-fit id 9) " "
                   (gascity-ui-fit (or (alist-get 'title bead) "") 26) " "
                   (gascity-ui-time (or (and session (alist-get 'last_active session))
                                        (alist-get 'updated_at bead))
                                    (plist-get ctx :now)))
           nil
           (lambda () (gascity-dashboard--bead-drawer bead))
           'gascity-bead id
           'gascity-dashboard-nested nested
           (and agent (list 'gascity-agent agent)))))

(defun gascity-dashboard--short-agent (name)
  "Return agent NAME without its rig and pool-template prefix.
`beads.el/gc.requirements-planner-1' reads `requirements-planner-1'."
  (let ((short (if (and (stringp name) (string-search "/" name))
                   (substring name (1+ (string-search "/" name)))
                 (or name ""))))
    (if (string-match "\\`[a-z]+\\.\\(.+\\)\\'" short)
        (match-string 1 short)
      short)))

(defun gascity-dashboard--run-drawer (ladder)
  "Return the drawer lines of a run: one per LADDER step."
  (mapcar (lambda (s)
            (concat (gascity-ui-glyph (pcase (plist-get s :state)
                                        ('done 'done) ('active 'active)
                                        ('failed 'failed) (_ 'pending)))
                    " " (gascity-ui-fit (plist-get s :name) 26)
                    " " (or (plist-get s :id) "")))
          ladder))

(defun gascity-dashboard--bead-drawer (bead)
  "Return the drawer lines of BEAD: status line, labels, description."
  (append
   (list (format "%s · P%s · %s"
                 (or (alist-get 'status bead) "?")
                 (or (alist-get 'priority bead) "?")
                 (or (alist-get 'assignee bead) "unassigned")))
   (let ((labels (gascity-dashboard--labels bead)))
     (and labels (list (concat "labels " (string-join labels ", ")))))
   (let ((desc (alist-get 'description bead)))
     (and (stringp desc)
          (seq-take (seq-remove #'string-empty-p
                                (mapcar #'string-trim (split-string desc "\n")))
                    3)))))

(defun gascity-dashboard--agents-lines (ctx)
  "Return the Agents section lines for CTX."
  (let* ((agents (sort (copy-sequence (plist-get ctx :agents))
                       (lambda (a b) (gascity-dashboard--agent-order a b t))))
         (awake (seq-remove (lambda (a) (memq (plist-get a :state) '(stopped suspended)))
                            agents))
         (asleep (seq-filter (lambda (a) (memq (plist-get a :state) '(stopped suspended)))
                             agents))
         (summary (gascity-status--state-summary
                   (mapcar (lambda (a) (plist-get a :state)) agents)))
         (gascity-dashboard-section-rows
          ;; Only this section starts at `gascity-dashboard-agent-rows',
          ;; and the `▸ stopped' fold is one of its rows (ga-boawq).
          (max 1 (if asleep
                     (1- gascity-dashboard-agent-rows)
                   gascity-dashboard-agent-rows)))
         (rows (gascity-dashboard--cap-groups
                (mapcar (lambda (a) (gascity-dashboard--agent-row a ctx)) awake)
                "agents" #'gascity-jump-agents)))
    (gascity-dashboard--section-lines
     "agents" "Agents" summary
     (append rows (and asleep (gascity-dashboard--stopped-fold asleep ctx)))
     ctx :loads '(:status :sessions) :label "status" :hint "j a all")))

(defun gascity-dashboard--agent-row (agent ctx)
  "Return the lines of AGENT's row (and drawer) in CTX.
A stalled agent's time slot says how long it has been stalled; every
other state keeps the last-active time."
  (let* ((state (plist-get agent :state))
         (name (plist-get agent :name))
         (stall (and (eq state 'stalled)
                     (gascity-dashboard--agent-stall agent))))
    (gascity-dashboard--object-row
     (concat "agent:" name)
     (concat "  " (gascity-ui-pending-glyph
                   name (gascity-ui-glyph (gascity-status--state-glyph state)))
             " " (gascity-ui-fit name 34)
             " " (gascity-ui-fit (or (plist-get agent :provider) "") 4)
             " " (gascity-ui-fit (or (plist-get agent :bead) "") 9)
             " " (gascity-ui-fit (gascity-status--state-label state) 8)
             ;; The state cell already says `stalled'; the slot says how
             ;; long (plan section 4, plan-review R6).
             (if stall
                 (gascity-dashboard--dim
                  (gascity-ui-truncate
                   (gascity-dashboard--stall-age stall (plist-get ctx :now))
                   15))
               (gascity-ui-time (plist-get agent :active) (plist-get ctx :now))))
     nil
     (lambda () (gascity-dashboard--agent-drawer agent))
     'gascity-agent (plist-get agent :object))))

(defun gascity-dashboard--agent-drawer (agent)
  "Return AGENT's drawer lines: session, workdir, hooked bead, created.
A stalled agent adds its stall age and source, the hooked bead's lease
and heartbeat when it carries them, and keeps the explanation last
\(REQ-005)."
  (let* ((session (plist-get agent :session))
         (now (float-time))
         (stalled (eq (plist-get agent :state) 'stalled))
         (stall (and stalled (gascity-dashboard--agent-stall agent)))
         (since (and stall (plist-get stall :since)))
         (source (and stall (plist-get stall :source)))
         (lease (and stall (plist-get stall :lease)))
         (heartbeat (and stall (plist-get stall :heartbeat)))
         (left (and lease (- (gascity-ui-parse-time lease) now))))
    (delq nil
          (list (and session
                     (format "session %s · %s"
                             (or (alist-get 'id session) "?")
                             (or (alist-get 'session_name session) "?")))
                (and session (alist-get 'work_dir session)
                     (concat "workdir " (gascity-dashboard--path
                                         (alist-get 'work_dir session))))
                (and (plist-get agent :bead)
                     (format "bead    %s %s" (plist-get agent :bead)
                             (or (plist-get agent :title) "")))
                (and (plist-get agent :created)
                     (concat "created " (gascity-ui-ago (plist-get agent :created))))
                (and stalled
                     (gascity-dashboard--drawer-value
                      "stalled   "
                      (format "%s (since %s, %s)"
                              (gascity-dashboard--stall-age stall now)
                              (if since
                                  (propertize (gascity-ui-relative-time since now)
                                              'help-echo since)
                                "unknown")
                              (or source "unknown"))))
                (and lease
                     (gascity-dashboard--drawer-value
                      "lease     "
                      (if (and left (<= left 0))
                          (format "expired %s ago"
                                  (gascity-ui-duration (abs left)))
                        (format "expires in %s"
                                (gascity-ui-duration (max 0 (or left 0)))))))
                (and heartbeat
                     (gascity-dashboard--drawer-value
                      "heartbeat " (gascity-ui-ago heartbeat now)))
                (and (not session)
                     (pcase (plist-get agent :state)
                       ('stalled "gc says running; no live session backs it")
                       ('unknown
                        "state unknown: gc status is partial; no session observed")
                       ((guard (gascity-agent-sessionless-p (plist-get agent :name)))
                        (gascity-agent-sessionless-hint (plist-get agent :name)))
                       (state (format "%s, no session" state))))))))

(defun gascity-dashboard--stopped-fold (asleep ctx)
  "Return the `▸ stopped' fold row for ASLEEP agents (expanded in place).
CTX is the render context."
  (let* ((id "fold:stopped")
         (open (member id (plist-get gascity-dashboard--view :expanded)))
         (toggle (lambda () (gascity-dashboard--flip :expanded id))))
    (cons (gascity-dashboard--row
           (concat "  " (gascity-ui-glyph (if open 'expanded 'folded)) " "
                   (gascity-dashboard--dim "stopped  ")
                   (gascity-ui-truncate
                    (gascity-dashboard--dim
                     (mapconcat (lambda (a) (plist-get a :name)) asleep " · "))
                    60))
           nil
           'beads-thing (gascity-dashboard--thing 'fold id toggle))
          (and open
               (mapcan (lambda (a) (gascity-dashboard--agent-row a ctx)) asleep)))))

(defun gascity-dashboard--work (ctx)
  "Return the Work model of CTX: :ready :in-progress :blocked :hidden."
  (let ((filters (plist-get ctx :filters))
        (ready nil) (in-progress 0) (in-progress-beads nil)
        (blocked 0) (hidden nil))
    (dolist (b (plist-get ctx :beads))
      (when (gascity-dashboard--in-rig-p b ctx)
        (let ((noise (gascity-event-noise b))
              (status (alist-get 'status b)))
          (cond
           ((eq noise 'convoy))
           ((and noise (not (gascity-event-noise-shown-p noise filters)))
            (setf (alist-get noise hidden) (1+ (alist-get noise hidden 0))))
           ((equal status "in_progress")
            (unless (gascity-dashboard--run-root-p b)
              (setq in-progress (1+ in-progress))
              (push b in-progress-beads)))
           ((equal status "blocked") (setq blocked (1+ blocked)))
           ((equal status "open")
            (unless (or (gascity-dashboard--root-of b)
                        (gascity-dashboard--run-root-p b))
              (push b ready)))))))
    (list :ready (sort ready
                       (lambda (a b)
                         (let ((pa (or (alist-get 'priority a) 4))
                               (pb (or (alist-get 'priority b) 4)))
                           (if (/= pa pb) (< pa pb)
                             (string< (or (alist-get 'created_at a) "")
                                      (or (alist-get 'created_at b) ""))))))
          :in-progress in-progress
          ;; The section lists the oldest claimed first: a step nobody is
          ;; moving is the one that needs the operator (ga-o7vtw).
          :in-progress-beads
          (sort in-progress-beads
                (lambda (a b)
                  (< (or (gascity-ui-parse-time (gascity-dashboard--claimed-at a))
                         1e300)
                     (or (gascity-ui-parse-time (gascity-dashboard--claimed-at b))
                         1e300))))
          :blocked blocked
          :hidden (nreverse hidden))))

(defun gascity-dashboard--work-in-progress-row (bead ctx)
  "Return the Work row of in-progress BEAD in CTX.
The row carries the assignee and the age since it was claimed; `gone'
after the assignee marks a holder with no live session (the Needs you
row's reason).  The id starts in the ready rows' id column."
  (let* ((id (alist-get 'id bead))
         (assignee (alist-get 'assignee bead))
         (live (and assignee (gascity-dashboard--session-for-assignee
                              assignee (plist-get ctx :sessions))))
         (claimed (gascity-ui-parse-time (gascity-dashboard--claimed-at bead)))
         (rig (alist-get 'gascity-rig bead)))
    (gascity-dashboard--object-row
     (concat "work-row:" id)
     (concat "  " (gascity-ui-fit id 9)
             " " (gascity-ui-fit (cond ((null assignee) "unassigned")
                                        (live assignee)
                                        (t (concat assignee " gone")))
                                  20)
             " " (gascity-ui-fit
                    (if claimed
                        (gascity-ui-duration (- (plist-get ctx :now) claimed))
                      "")
                    4)
             " " (gascity-ui-fit (or (alist-get 'title bead) "") 24))
     (gascity-dashboard--dim (or rig "city"))
     (lambda () (gascity-dashboard--bead-drawer bead))
     'gascity-bead id
     'gascity-run-rig (or rig ""))))

(defun gascity-dashboard--work-lines (ctx)
  "Return the Work section lines for CTX.
In-progress work leads (oldest claim first, with assignee and age), then
the ready beads by priority: the section counts in-progress work but
used to list only ready rows (ga-o7vtw)."
  (let* ((work (gascity-dashboard--work ctx))
         (ready (plist-get work :ready))
         (convoys (seq-count (lambda (c) (not (equal (alist-get 'status c) "closed")))
                             (plist-get ctx :convoys)))
         (have (plist-get ctx :beads))
         (summary (and (or have (gascity-dashboard--data
                                 (plist-get (plist-get ctx :loads) :work)))
                       (format "%d ready · %d in progress · %d blocked · %d convoys"
                               (length ready) (plist-get work :in-progress)
                               (plist-get work :blocked) convoys)))
         (rows (append
                (mapcar (lambda (b)
                          (gascity-dashboard--work-in-progress-row b ctx))
                        (plist-get work :in-progress-beads))
                (mapcar
                (lambda (b)
                  (let ((id (alist-get 'id b)))
                    (gascity-dashboard--object-row
                     (concat "bead:" id)
                     (concat "  " (gascity-ui-fit id 9)
                             " " (gascity-ui-fit (format "P%s" (or (alist-get 'priority b) "?")) 3)
                             " " (gascity-ui-fit (or (alist-get 'title b) "") 50))
                     (gascity-dashboard--dim (or (alist-get 'gascity-rig b) "city"))
                     (lambda () (gascity-dashboard--bead-drawer b))
                     'gascity-bead id)))
                ready))))
    (gascity-dashboard--section-lines
     "work" "Work" summary
     (gascity-dashboard--cap-groups rows "work" #'gascity-jump-beads)
     ;; The convoy count rides in the summary: its failure marks ◐ too.
     ctx :loads '(:work :convoys) :label "bd list"
     :hidden (gascity-dashboard--hidden-label (plist-get work :hidden)))))

(defvar-local gascity-dashboard--activity-memo nil
  "The last Activity fold: (KEY . MODEL), KEY led by the events payload.")

(defun gascity-dashboard--activity-model (ctx)
  "Return the Activity fold of CTX's events, (ROWS . FOLDED).
Computed once per events payload (compared by identity) and fold
filters, then reused by every render until either changes: a render
triggered by another section's read, a drawer toggled or a pending row
does not refold 1.5k events."
  (let* ((filters (plist-get ctx :filters))
         (events (plist-get ctx :events))
         (key (list (plist-get filters :rig) (gascity-event-fold-key filters)
                    (plist-get ctx :rig-prefixes))))
    (if (and gascity-dashboard--activity-memo
             (eq (car (car gascity-dashboard--activity-memo)) events)
             (equal (cdr (car gascity-dashboard--activity-memo)) key))
        (cdr gascity-dashboard--activity-memo)
      (let ((model (gascity-event-fold
                    (if (plist-get filters :rig)
                        (seq-filter (lambda (e) (gascity-dashboard--event-in-rig-p e ctx))
                                    events)
                      events)
                    filters)))
        (setq gascity-dashboard--activity-memo (cons (cons events key) model))
        model))))

(defun gascity-dashboard--activity-lines (ctx)
  "Return the Activity section lines for CTX."
  (let* ((filters (plist-get ctx :filters))
         (window (or (plist-get filters :window) gascity-dashboard-window))
         (model (gascity-dashboard--activity-model ctx))
         (rows (mapcar (lambda (row) (gascity-dashboard--activity-row row ctx))
                       (car model))))
    (gascity-dashboard--section-lines
     "activity" "Activity" (and rows (concat "last " window))
     (gascity-dashboard--cap-groups rows "activity" #'gascity-jump-events)
     ctx :loads '(:events) :label "events"
     :hidden (and (> (cdr model) 0)
                  (gascity-dashboard--dim (format "(%d churn folded)" (cdr model)))))))

(defun gascity-dashboard--event-in-rig-p (event ctx)
  "Return non-nil when EVENT passes CTX's rig filter (best effort)."
  (let ((rig (plist-get (plist-get ctx :filters) :rig)))
    (or (null rig)
        (let ((text (format "%s %s" (or (alist-get 'subject event) "")
                            (or (alist-get 'message event) ""))))
          (or (string-search (concat rig "/") text)
              (let ((prefix (cdr (assoc rig (plist-get ctx :rig-prefixes)))))
                (and prefix (string-match-p (concat "\\_<" (regexp-quote prefix) "-")
                                            text))))))))

(defun gascity-dashboard--activity-row (row ctx)
  "Return the lines of Activity ROW (an event or a churn fold) in CTX."
  (pcase row
    (`(event ,event)
     (let* ((level (gascity-event-level event))
            (id (format "event:%s" (alist-get 'seq event)))
            (bead (gascity-event-bead event)))
       (apply #'gascity-dashboard--object-row
              id
              (concat "  " (gascity-ui-clock (alist-get 'ts event)) "   "
                      (gascity-event-level-glyph level)
                      "    " (gascity-ui-fit (or (alist-get 'type event) "") 28)
                      " " (gascity-ui-truncate
                           (gascity-event-subject event) 30))
              nil
              (lambda () (gascity-event-fields event))
              'gascity-dashboard-event event
              (and bead (list 'gascity-bead (alist-get 'id bead))))))
    (`(churn ,key ,group ,time ,events)
     (let* ((id (concat "churn:" key))
            (open (or (member id (plist-get gascity-dashboard--view :expanded))
                      (plist-get (plist-get ctx :filters) :unfold)))
            ;; RET: the Events view narrowed to this churn group (§7.8).
            (target (gascity-dashboard--events-target group ctx))
            (shown (seq-take events (+ gascity-dashboard-churn-unfold-rows
                                       (gascity-section-extra
                                        id (plist-get gascity-dashboard--view :extra)))))
            (more (- (length events) (length shown))))
       (funcall
        (if open (lambda (lines) (gascity-dashboard--expand-stamp id lines)) #'identity)
        (cons (gascity-dashboard--row
              (concat "  " (format-time-string "%H:%M" time) "   "
                      (gascity-dashboard--dim (format "×%-3d" (length events)))
                      " " (gascity-ui-fit group 28)
                      " " (gascity-dashboard--dim
                           (gascity-event-churn-detail group events)))
              nil
              'gascity-dashboard-target target
              'beads-thing (gascity-dashboard--thing
                            'fold id (lambda () (gascity-dashboard--flip :expanded id))))
             (and open
                  (append
                   (mapcan (lambda (e) (gascity-dashboard--activity-row (list 'event e) ctx))
                           shown)
                   (and (> more 0)
                        (list (gascity-dashboard--row
                               (gascity-dashboard--dim (format "      … %d more" more))
                               (gascity-dashboard--dim "+ more  RET j e events")
                               'gascity-dashboard-target target
                               'gascity-expand-more t
                               'beads-thing (gascity-dashboard--thing
                                             'more (concat id ":more")))))))))))))

(defun gascity-dashboard--events-target (group ctx)
  "Return the command opening the Events view narrowed to churn GROUP.
The Events window follows the cockpit's (CTX's filters)."
  (let ((window (plist-get (plist-get ctx :filters) :window)))
    (lambda ()
      (interactive)
      (gascity-events (append (list :group group)
                              (and window (list :window window)))))))

(defun gascity-dashboard--rigs-lines (ctx)
  "Return the Rigs section lines for CTX.
The city HQ row is marked `(HQ)' and counts the city-scope agents (those
with no rig), not zero: gc reports city-level agents (the mayor, pool
slots, city dispatchers) without a rig, so matching the HQ row by name
always read 0/0 while the top line counted them (ga-4mvlw.2).  Per-rig
rows keep counting only their own agents."
  (let* ((agents (plist-get ctx :all-agents))
         (beads (plist-get ctx :beads))
         (rows (mapcar
                (lambda (rig)
                  (let* ((name (alist-get 'name rig))
                         (hq (and (alist-get 'hq rig) t))
                         (mine (seq-filter (lambda (a)
                                             (if hq
                                                 (null (plist-get a :rig))
                                               (equal (plist-get a :rig) name)))
                                           agents))
                         (up (seq-count (lambda (a) (memq (plist-get a :state)
                                                          '(running idle stalled)))
                                        mine))
                         (wip (seq-count (lambda (b)
                                           (and (equal (alist-get 'gascity-rig b) name)
                                                (equal (alist-get 'status b) "in_progress")
                                                (not (gascity-event-noise b))))
                                         beads))
                         (marks (delq nil
                                      (list (and hq
                                                 (propertize "(HQ)" 'face 'gascity-dim))
                                            (and (alist-get 'suspended rig)
                                                 (propertize "suspended"
                                                             'face 'gascity-suspended))))))
                    (gascity-dashboard--object-row
                     (concat "rig:" name)
                     (concat "  " (gascity-ui-fit name 12)
                             " " (gascity-ui-fit (or (alist-get 'prefix rig) "") 4)
                             " " (gascity-ui-fit (gascity-dashboard--path
                                                  (alist-get 'path rig))
                                                 26)
                             " " (gascity-ui-fit (format "%d/%d agents" up (length mine)) 12)
                             " " (format "%d in progress" wip))
                     (and marks (string-join marks " "))
                     (lambda ()
                       (list (concat "path    " (or (alist-get 'path rig) ""))
                             (format "prefix  %s" (or (alist-get 'prefix rig) ""))
                             (format "agents  %d running / %d" up (length mine))
                             (format "work    %d in progress" wip)))
                     'gascity-rig name
                     'gascity-rig-dir (alist-get 'path rig))))
                (plist-get ctx :rigs))))
    (gascity-dashboard--section-lines
     "rigs" "Rigs" (and rows (number-to-string (length rows)))
     (gascity-dashboard--cap-groups rows "rigs" #'gascity-rig-list)
     ctx :loads '(:status :rigs) :label "status/rig list")))

(defun gascity-dashboard--lines (ctx)
  "Return every cockpit line for render context CTX."
  (let ((gascity-dashboard--view (plist-get ctx :view)))
    (append (gascity-dashboard--top-lines ctx)
            (list "")
            (gascity-dashboard--needs-you-lines ctx)
            (list "")
            (gascity-dashboard--moving-lines ctx)
            (list "")
            (gascity-dashboard--agents-lines ctx)
            (list "")
            (gascity-dashboard--work-lines ctx)
            (list "")
            (gascity-dashboard--activity-lines ctx)
            (list "")
            (gascity-dashboard--rigs-lines ctx))))

;;; Reads — one small loader per section read (the store swaps these)

(defun gascity-dashboard--read-status (resolve reject)
  "Read `gc status' for the cockpit; RESOLVE with the payload or REJECT."
  (gascity-store-fetch '("status") resolve reject))

(defun gascity-dashboard--read-sessions (resolve reject)
  "Read `gc session list' for the cockpit.
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch '("session" "list") resolve reject))

(defun gascity-dashboard--read-mail (resolve reject)
  "Read `gc mail count' for the cockpit.
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch '("mail" "count") resolve reject))

(defun gascity-dashboard--read-events (window resolve reject)
  "Read `gc events --since WINDOW' (JSON Lines) for the cockpit.
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch (list "events" "--since" (gascity-event-since-arg window))
                       resolve reject
                       :lines t))

(defun gascity-dashboard--read-convoys (resolve reject)
  "Read `gc convoy list' for the cockpit.
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch '("convoy" "list") resolve reject))

(defun gascity-dashboard--read-escalations (resolve reject)
  "Read the city store's escalated and held beads (one label-regex read).
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch
   '("bd" "list" "--label-regex" "^(gc:escalation|hold:.*)$" "-n" "0")
   resolve reject))

(defconst gascity-dashboard--work-args
  '("bd" "list" "--status" "in_progress,open,blocked" "-n" "0")
  "The per-store work read: split client-side into Moving, Work, runs.")

(defun gascity-dashboard--read-work-stores (names dir resolve reject
                                                  &optional argvs)
  "Read the work beads of the city store and the rig stores NAMES in DIR.
See `gascity-dashboard--read-work' for RESOLVE, REJECT and ARGVS."
  (let* ((default-directory dir)
         (force gascity-store-loader-force)
         (argvs (or argvs (list gascity-dashboard--work-args)))
         (stores (cons nil names))
         (pending (* (length stores) (length argvs)))
         (batches (make-hash-table :test 'equal))
         (errors nil)
         (settle
          (lambda ()
            (setq pending (1- pending))
            (when (zerop pending)
              (if (= (length errors) (* (length stores) (length argvs)))
                  (funcall reject (car errors))
                (funcall resolve
                         (list :beads (apply #'append
                                             (mapcar (lambda (n) (gethash n batches))
                                                     stores))
                               :errors errors)))))))
    (dolist (name stores)
      (dolist (args argvs)
        (gascity-store-fetch
         (append args (and name (list "--rig" name)))
         (lambda (payload)
           (puthash name
                    (append (gethash name batches)
                            (mapcar (lambda (b)
                                      (append b (list (cons 'gascity-rig name))))
                                    (gascity-section-beads payload)))
                    batches)
           (funcall settle))
         (lambda (err)
           (push (format "%s: %s" (or name "city") err) errors)
           (funcall settle))
         :force force)))))

(defun gascity-dashboard--read-work (resolve reject &optional argvs)
  "Read the work beads of the city store and every rig store.
One `bd list --status in_progress,open,blocked' read per store, all
async; RESOLVE gets (:beads BEADS :errors ERRORS), BEADS stamped with
`(gascity-rig . NAME)' (nil for the city store), ERRORS the failures of
the stores that did not answer.  REJECT only when every store failed.
The rigs come from the rig memo, else one `gc rig list' read.  Reads
started from a callback run in the loader's directory: a sentinel's
current buffer is arbitrary, and the city must not be lost.
ARGVS, when non-nil, replaces the one per-store read by these `bd'
argvs, all read in every store and concatenated (the Runs view reads
its run roots and step beads this way)."
  (let ((dir default-directory)
        (cached (gascity-rigs-cached)))
    (if cached
        (gascity-dashboard--read-work-stores
         (gascity-dashboard--rig-store-names cached) dir resolve reject argvs)
      (let ((force gascity-store-loader-force))
        (gascity-store-fetch
         '("rig" "list")
         (lambda (payload)
           (let ((gascity-store-loader-force force))
             (gascity-dashboard--read-work-stores
              (gascity-dashboard--rig-store-names
               (gascity-domain-decode-list 'gascity-rig (alist-get 'rigs payload)))
              dir resolve reject argvs)))
         reject :force force)))))

(defun gascity-dashboard--rig-store-names (rigs)
  "Return the names of RIGS that are rig stores (the city HQ excluded)."
  (delq nil (mapcar (lambda (r) (and (not (gascity-rig-hq r)) (gascity-rig-name r)))
                    rigs)))

;;; Component

(defalias 'gascity-dashboard--effective-load #'gascity-ui-effective-load
  "Stale-while-revalidate load normalization (see `gascity-ui-effective-load').")

(defalias 'gascity-dashboard--section #'gascity-ui-section
  "The §6.1 section vnode (kept for the run detail view).")

(defvar-local gascity-dashboard--refreshed-at nil
  "Time of the cockpit's last successful status read (for the header).
The store's `:fetched-at' of the `gc status' entry, set on render.")

(vui-defcomponent gascity-dashboard-app (initial-filters)
  "Root component of the city cockpit.
INITIAL-FILTERS seeds the filter state (remembered per city)."
  :state ((refresh-tick 0)
          (collapsed nil)
          (drawers nil)
          (expanded nil)
          (extra nil)
          (filters (copy-sequence initial-filters)))
  :render
  ;; Every async hook runs unconditionally, in order, every render.
  (let* ((window (or (plist-get filters :window) gascity-dashboard-window))
         ;; Every read goes through the store (dashboard-v3 §8.3 R3):
         ;; shared with the other views, deduplicated, scheduled per
         ;; host; `refresh-tick' forces a re-read.
         (status-res (gascity-store-use '("status") :tick refresh-tick))
         (sessions-res (gascity-store-use '("session" "list") :tick refresh-tick))
         (mail-res (gascity-store-use '("mail" "count") :tick refresh-tick))
         (events-res (gascity-store-use (list "events" "--since" window)
                                        :tick refresh-tick :lines t))
         (work-res (gascity-store-use '("bd" "list" :work-stores)
                                      :tick refresh-tick
                                      :loader #'gascity-dashboard--read-work))
         (convoys-res (gascity-store-use '("convoy" "list") :tick refresh-tick))
         (escalations-res (gascity-store-use
                           '("bd" "list" "--label-regex"
                             "^(gc:escalation|hold:.*)$" "-n" "0")
                           :tick refresh-tick))
         (last-status (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         (last-mail (vui-use-ref nil))
         (last-events (vui-use-ref nil))
         (last-work (vui-use-ref nil))
         (last-convoys (vui-use-ref nil))
         (last-escalations (vui-use-ref nil))
         (last-runs (vui-use-ref nil))
         (last-rigs (vui-use-ref nil))
         (work (gascity-dashboard--effective-load work-res last-work))
         ;; The full rig list seeds the rig memo (`gascity-rigs-remember'):
         ;; `gc status' omits the city HQ rig, so a status-only memo
         ;; lacks the HQ prefix and prefix-routing checks (the sling
         ;; §5b cross-store warning, the work reads) degrade until
         ;; some `gc rig list' warms it (WI-11 finding F4).  Shared
         ;; with every other rig-list read through the store.
         (rigs-res (gascity-store-use '("rig" "list") :tick refresh-tick))
         (rigs (gascity-dashboard--effective-load rigs-res last-rigs))
         ;; Every run bead, the Runs view's own store entry: the Moving
         ;; ladders are computed from the very data the Runs view shows
         ;; (§3.2 one ladder rule), and share its read.
         (runs-res (gascity-store-use gascity-dashboard--runs-key
                                      :tick refresh-tick
                                      :loader #'gascity-runs-read-beads))
         (loads (list :status (gascity-dashboard--effective-load status-res last-status)
                      :sessions (gascity-dashboard--effective-load sessions-res
                                                                   last-sessions)
                      :mail (gascity-dashboard--effective-load mail-res last-mail)
                      :events (gascity-dashboard--effective-load events-res last-events)
                      :work work
                      :convoys (gascity-dashboard--effective-load convoys-res
                                                                  last-convoys)
                      :escalations (gascity-dashboard--effective-load escalations-res
                                                                      last-escalations)
                      :rigs rigs
                      :runs (gascity-dashboard--effective-load runs-res
                                                               last-runs)))
         (ctx (gascity-dashboard--context loads filters (float-time))))
    ;; Once per render: the section and the pulse both read them.
    (setq ctx (plist-put ctx :needs-you (gascity-dashboard--needs-you ctx)))
    ;; `↻' is the last change of anything the cockpit shows: a read, or
    ;; events the live stream appended (store `:updated-at').
    (let ((at (apply #'max 0 (delq nil (mapcar (lambda (r) (plist-get r :updated-at))
                                               (list status-res sessions-res mail-res
                                                     events-res work-res convoys-res
                                                     escalations-res rigs-res))))))
      (when (> at 0)
        (setq gascity-dashboard--refreshed-at at)))
    (when-let* ((status (plist-get ctx :status)))
      ;; Seed the rig memo: the full `gc rig list' answers when it has
      ;; landed — it carries the HQ rig `gc status' omits (F4) — and
      ;; the status payload is the fallback until then.
      (let* ((full (plist-get rigs :data))
             (rig-list-rigs (and full (alist-get 'rigs full))))
        (gascity-dashboard--remember-rigs
         rig-list-rigs (alist-get 'rigs status)))
      (gascity-dashboard--publish ctx))
    (setq ctx (plist-put ctx :view (list :collapsed collapsed :drawers drawers
                                         :expanded expanded :extra extra)))
    ;; One text vnode: the lines are plain propertized strings (blank
    ;; separator lines included, which vui would drop as empty vnodes).
    (vui-text (string-join (gascity-dashboard--lines ctx) "\n"))))

;;; Pulse (§7.11, §7.12): what other views may show without a gc call

(defun gascity-dashboard--remember-rigs (rig-list-rigs status-rigs)
  "Seed the rig memo from the cockpit's rig reads.
RIG-LIST-RIGS is the raw `rigs' vector of `gc rig list', STATUS-RIGS
that of `gc status'.  The full rig list is preferred whenever it has
landed: `gc status' omits the city HQ rig, so a status-only memo lacks
the HQ's id prefix and the prefix-routing checks that read
`gascity-rigs-cached' degrade until some rig-list read warms it
\(WI-11 finding F4).  Falls back to the status rows while the rig-list
read is still in flight.  Returns the remembered rig objects."
  (let ((raw (if (and rig-list-rigs (not (seq-empty-p rig-list-rigs)))
                 rig-list-rigs
               status-rigs)))
    (gascity-rigs-remember
     (gascity-domain-decode-list 'gascity-rig raw))))

(defun gascity-dashboard--publish (ctx)
  "Publish this cockpit's Needs you totals, runs and store size (CTX).
The mode-line lighter and the Cities view read them from
`gascity-pulse'; publishing is in-memory only."
  (let ((items (gascity-dashboard--needs-you-items ctx))
        (status (plist-get ctx :status)))
    (gascity-pulse-record-store-size default-directory status)
    (gascity-pulse-publish
     default-directory (current-buffer)
     (or (alist-get 'city_name status) gascity-dashboard--city)
     :fail (seq-count (lambda (i) (eq (plist-get i :level) 'fail)) items)
     :watch (seq-count (lambda (i) (eq (plist-get i :level) 'watch)) items)
     :runs (and (gascity-dashboard--data (plist-get (plist-get ctx :loads) :work))
                (length (gascity-dashboard--active-runs (plist-get ctx :beads)))))))

;;; View state (root component, survives a refresh)

(defun gascity-dashboard--root ()
  "Return the cockpit's root vui instance in this buffer, or nil."
  (and (boundp 'vui--root-instance) vui--root-instance))

(defun gascity-dashboard--state (key)
  "Return root state KEY of this buffer's cockpit."
  (when-let* ((root (gascity-dashboard--root)))
    (plist-get (vui-instance-state root) key)))

(defun gascity-dashboard--set-state (key value)
  "Set root state KEY to VALUE and re-render in place (no re-read)."
  (when-let* ((root (gascity-dashboard--root)))
    (setf (vui-instance-state root)
          (plist-put (vui-instance-state root) key value))
    (vui-flush-sync)))

(defun gascity-dashboard--flip (key id)
  "Toggle ID's membership in root state list KEY and re-render."
  (let ((current (gascity-dashboard--state key)))
    (gascity-dashboard--set-state
     key (if (member id current) (remove id current) (cons id current)))))

;;; Commands

(defun gascity-dashboard-refresh (&optional reset)
  "Re-read every cockpit section, keeping point, folds and drawers.
Also reconnects the city's live stream when it is down.  With a prefix
argument RESET (`C-u g'), sections expanded with `+' return to their cap."
  (interactive "P")
  (when reset (gascity-section-reset-extra))
  (gascity-live-reconnect)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No cockpit to refresh here")))

(defconst gascity-dashboard--section-targets
  '(("needs-you" . gascity-jump-events)
    ("moving" . gascity-jump-runs)
    ("agents" . gascity-jump-agents)
    ("work" . gascity-jump-beads)
    ("activity" . gascity-jump-events)
    ("rigs" . gascity-rig-list))
  "The view RET on a section header opens (§5.4).")

(defun gascity-dashboard-activate ()
  "Act on the thing at point (RET never folds, §5.4).
A section header or `… N more' line opens its view; a run opens run
detail; a rig its dashboard; an agent attaches; a bead opens in
beads.el; an event opens its bead."
  (interactive)
  (let ((section (get-text-property (point) 'gascity-dashboard-section))
        (target (get-text-property (point) 'gascity-dashboard-target))
        (run-rig (get-text-property (point) 'gascity-run-rig))
        (agent (get-text-property (point) 'gascity-agent))
        (bead (get-text-property (point) 'gascity-bead))
        (rig (get-text-property (point) 'gascity-rig)))
    (cond
     (section (call-interactively
               (cdr (assoc section gascity-dashboard--section-targets))))
     (target (call-interactively target))
     (run-rig (gascity-run-show bead nil (and (not (string-empty-p run-rig)) run-rig)))
     (agent (gascity-at-point-visit agent))
     (bead (gascity-bead-show bead))
     (rig (gascity-rig-dashboard rig))
     (t (user-error "Nothing to act on here")))))

(defun gascity-dashboard-suspend ()
  "Suspend the agent or rig at point (`s', §5.3)."
  (interactive)
  (if (gascity-rig-row-p)
      (gascity-rig-suspend-at-point)
    (gascity-session-suspend-at-point)))

(defun gascity-dashboard-reset ()
  "Reset the agent, or restart the rig, at point (`R', confirmed)."
  (interactive)
  (if (gascity-rig-row-p)
      (gascity-rig-restart-at-point)
    (gascity-session-reset-at-point)))

(defun gascity-dashboard-rig-log ()
  "Show the git log of the rig at point (`l').
Uses `magit-log-all' when magit is installed, else `vc-print-root-log'."
  (interactive)
  (let* ((rig (or (get-text-property (point) 'gascity-rig)
                  (user-error "No rig at point")))
         (dir (gascity-remote-localize-path
               (get-text-property (point) 'gascity-rig-dir))))
    (unless dir (user-error "No directory for rig %s" rig))
    (let ((default-directory (file-name-as-directory dir)))
      (if (require 'magit-log nil t)
          (magit-log-all)
        (vc-print-root-log)))))

;;; Live refresh (`W')
;;
;; The cockpit joins its city's event stream (`gascity-live-attach',
;; dashboard-v3 §8.2).  Events invalidate the store entries they touch
;; and the sections reading them repaint (`gascity-store-use'); there
;; is no timer.

(defun gascity-dashboard-toggle-live ()
  "Toggle this city's live event stream (`W', dashboard-v3 §5.1)."
  (interactive)
  (gascity-live-toggle)
  (force-mode-line-update))


;;; Header line

(defun gascity-dashboard--header-line ()
  "Return the cockpit header line: city, @host, live state, age, hints.
Pure: reads buffer-local state and the TRAMP name only (§8.3 R2)."
  (let* ((city (or gascity-dashboard--city "?"))
         (host (file-remote-p default-directory 'host))
         (offline (and host (gascity-store-offline-p)))
         (live (cond
                (offline
                 ;; The store paused this host (§8.3 R5): one state for
                 ;; the whole city, never an error per section.
                 (propertize (concat (gascity-ui-glyph 'idle)
                                     (propertize (concat " offline @" host)
                                                 'face 'gascity-failed))
                             'help-echo
                             (or (plist-get (gascity-store-host-status) :reason)
                                 "host unreachable; retrying")))
                ;; The city's event stream (§8.2, R4).
                ((gascity-live-header-string))
                (t (propertize "○ live off" 'face 'gascity-dim))))
         (age (and gascity-dashboard--refreshed-at
                   (gascity-dashboard--dim
                    (format "↻ %s ago"
                            (gascity-ui-duration
                             (- (float-time) gascity-dashboard--refreshed-at))))))
         (hints (gascity-dashboard--dim "? help  j jump  g refresh")))
    (concat " " (propertize city 'face 'gascity-city)
            (if host (concat " " (propertize (concat "@" host) 'face 'gascity-dim)) "")
            "  " live
            (if age (concat "  " age) "")
            (propertize " " 'display
                        `(space :align-to (- right ,(1+ (string-width hints)))))
            hints)))

;;; Filter (`/', §7.2)

(defun gascity-dashboard--city-key ()
  "Return the key the filters of this city are remembered under."
  (or (gascity-context-city-root) default-directory))

(defun gascity-dashboard--filters ()
  "Return this cockpit's filter plist."
  (gascity-dashboard--state :filters))

(defun gascity-dashboard--set-filter (key value)
  "Set cockpit filter KEY to VALUE, remember it for the city, re-render."
  (let ((filters (plist-put (copy-sequence (gascity-dashboard--filters)) key value)))
    (setf (alist-get (gascity-dashboard--city-key) gascity-dashboard-filters
                     nil nil #'equal)
          filters)
    (gascity-dashboard--set-state :filters filters)))

(defun gascity-dashboard--install-filter ()
  "Wire the `/' menu builders (`gascity-filter-*') to the cockpit state."
  (setq-local gascity-filter-get-function
              (lambda (key) (plist-get (gascity-dashboard--filters) key)))
  (setq-local gascity-filter-set-function #'gascity-dashboard--set-filter)
  (setq-local gascity-filter-reset-function
              (lambda ()
                (setf (alist-get (gascity-dashboard--city-key)
                                 gascity-dashboard-filters nil nil #'equal)
                      nil)
                (gascity-dashboard--set-state :filters nil))))

(gascity-filter-define-toggle gascity-dashboard-filter-wisps :wisps "show wisps")
(gascity-filter-define-toggle gascity-dashboard-filter-nudges :nudges "show nudge beads")
(gascity-filter-define-toggle gascity-dashboard-filter-orders :orders "show order churn")
(gascity-filter-define-toggle gascity-dashboard-filter-messages :messages
  "show message beads")
(gascity-filter-define-toggle gascity-dashboard-filter-unfold :unfold "unfold churn")
(gascity-filter-define-choice gascity-dashboard-filter-rig
  :rig "rig" (mapcar #'gascity-rig-name (gascity-rigs-cached)))
(gascity-filter-define-choice gascity-dashboard-filter-window
  :window "window" '("1h" "2h" "6h" "24h") gascity-dashboard-window)

(beads-define-prefix gascity-dashboard-filter ()
  "Filter the cockpit; each change applies at once (§7.2)."
  [:description (lambda () (concat "Filter  " (or gascity-dashboard--city "")))
   ["Noise"
    ("-w" gascity-dashboard-filter-wisps)
    ("-n" gascity-dashboard-filter-nudges)
    ("-o" gascity-dashboard-filter-orders)
    ("-m" gascity-dashboard-filter-messages)]
   ["Scope"
    ("-r" gascity-dashboard-filter-rig)]
   ["Activity"
    ("-W" gascity-dashboard-filter-window)
    ("-c" gascity-dashboard-filter-unfold)]]
  [("x" gascity-filter-reset)])

;;; Jump prefix `j' (§5.2) and the `?' dispatch (§6.2)

(defvar-local gascity-jump-city-function nil
  "Function of no arguments returning the city a jump should act on, or nil.
The Cities list binds it (as it binds `gascity-live-city-function'): the
list belongs to no city, so its city-scoped `j'/`?' jumps run with
`default-directory' bound to the city on the row at point instead of
the list's contextless one (§7.11).  Nil in every other view: there a
jump uses the view's own pinned city directory.")

(defun gascity-jump--scoped (fn)
  "Call FN with `default-directory' at the city this jump targets.
In a view that scopes jumps (`gascity-jump-city-function' non-nil, the
Cities list) that is the city at point, and point must hold one, else
FN would open a contextless view whose gc reads fail and whose live
indicator spins.  Elsewhere FN runs in the view's own directory."
  (let ((dir (if gascity-jump-city-function
                 (or (funcall gascity-jump-city-function)
                     (user-error "No city selected — RET to open one"))
               default-directory)))
    (let ((default-directory dir))
      (funcall fn))))

(defun gascity-jump--call (candidates name)
  "Call the first defined command of CANDIDATES, else say NAME is pending.
Views built by later phases are reached by name; until one exists the
jump echoes instead of failing."
  ;; `commandp', not `fboundp': a jump target must be interactive.
  (let ((cmd (seq-find #'commandp candidates)))
    (if cmd
        (call-interactively cmd)
      (message "The %s view is not available yet" name))))

(defun gascity-jump--scoped-call (candidates name)
  "Scoped `gascity-jump--call': the city at point in a multi-city view.
CANDIDATES is the jump target list passed through to
`gascity-jump--call'; NAME names the target for messages."
  (gascity-jump--scoped
   (lambda () (gascity-jump--call candidates name))))

(defun gascity-jump-cockpit ()
  "Jump to this city's cockpit (`j j')."
  (interactive)
  (gascity-jump--scoped #'gascity-dashboard))

(defun gascity-jump-agents ()
  "Jump to the Agents view (`j a')."
  (interactive)
  (gascity-jump--scoped-call '(gascity-agents gascity-session-list) "Agents"))

(defun gascity-jump-sessions ()
  "Jump to the Sessions view (`j s').
The flat `gc session list' table, not the Agents view (`j a'): every
runtime session the city reports, with the sessions' own filters and
bookmark."
  (interactive)
  (gascity-jump--scoped-call '(gascity-session-list) "Sessions"))

(defun gascity-jump-runs ()
  "Jump to the Runs view (`j r')."
  (interactive)
  (gascity-jump--scoped-call '(gascity-runs) "Runs"))

(defun gascity-jump-events ()
  "Jump to the Events view (`j e')."
  (interactive)
  (gascity-jump--scoped-call '(gascity-events) "Events"))

(defun gascity-jump-health ()
  "Jump to the Health view (`j h')."
  (interactive)
  (gascity-jump--scoped-call '(gascity-health) "Health"))

(defun gascity-jump-cities ()
  "Jump to the Cities view (`j c').
The Cities list is every city, not one: this jump is never scoped to
`gascity-jump-city-function'."
  (interactive)
  (gascity-jump--call '(gascity-cities) "Cities"))

(defun gascity-jump-mail ()
  "Jump to the Mail inbox (`j m')."
  (interactive)
  (gascity-jump--scoped-call '(gascity-mail gascity-mail-inbox) "Mail"))

(defun gascity-jump-costs ()
  "Show `gc costs' output (`j $')."
  (interactive)
  (gascity-jump--scoped-call '(gascity-costs) "Costs"))

(defun gascity-jump-orders ()
  "Jump to this city's Orders view (`j o')."
  (interactive)
  (gascity-jump--scoped #'gascity-order-list))

(defun gascity-jump-convoys ()
  "Jump to this city's Convoys view (`j v')."
  (interactive)
  (gascity-jump--scoped #'gascity-convoy-list))

(defun gascity-jump-dolt ()
  "Jump to this city's Dolt view (`j d')."
  (interactive)
  (gascity-jump--scoped #'gascity-dolt-list))

(defun gascity-jump-rigs ()
  "Jump to this city's Rigs list (`j l')."
  (interactive)
  (gascity-jump--scoped #'gascity-rig-list))

(defun gascity-jump-rig ()
  "Open the rig dashboard of the rig at point, else prompt (`j g').
The prompt reads the rig memo only — never a synchronous `gc' — and
refreshes it in the background (`gascity-rig-names-for-prompt'), so a
cold memo fills in for the next prompt; \"city\" opens the cockpit."
  (interactive)
  (gascity-jump--scoped
   (lambda ()
     (let ((rig (or (gascity-rig-at-point)
                    (completing-read "Rig: "
                                     (cons "city" (gascity-rig-names-for-prompt))
                                     nil t))))
       (if (equal rig "city")
           (gascity-dashboard)
         (gascity-rig-dashboard rig))))))

(defun gascity-jump-beads ()
  "Open beads.el for the rig at point, else chosen: a rig or the city (`j b').
Candidates come from the rig memo only (§8.5), refreshed in the
background for the next prompt.  A blank answer (RET on an empty prompt)
selects the city: an empty string is truthy in Elisp, so a rig named \"\"
would otherwise reach `gascity-rig-beads' and report a bogus unresolved
store (ga-40tbg.2)."
  (interactive)
  (gascity-jump--scoped
   (lambda ()
     (let ((rig (or (gascity-rig-at-point)
                    (let ((choice (completing-read
                                   "Beads for: "
                                   (cons "city" (progn
                                                  ;; Background refresh of the memo.
                                                  (gascity-rig-names-for-prompt)
                                                  (gascity-dashboard--rig-store-names
                                                   (gascity-rigs-cached))))
                                   nil t)))
                      (and (not (equal choice "city"))
                           (not (equal choice ""))
                           choice)))))
       (if rig
           (gascity-rig-beads rig)
         (let ((store (gascity-beads--city-store)))
           (unless (fboundp 'beads-dashboard) (require 'beads-dashboard nil t))
           (beads-dashboard :directory store)))))))

(defvar-keymap gascity-jump-map
  :doc "The `j' jump prefix of every gascity view (dashboard-v3 §5.2)."
  "j" #'gascity-jump-cockpit
  "a" #'gascity-jump-agents
  "r" #'gascity-jump-runs
  "b" #'gascity-jump-beads
  "m" #'gascity-jump-mail
  "e" #'gascity-jump-events
  "h" #'gascity-jump-health
  "c" #'gascity-jump-cities
  "o" #'gascity-jump-orders
  "v" #'gascity-jump-convoys
  "d" #'gascity-jump-dolt
  "g" #'gascity-jump-rig
  "l" #'gascity-jump-rigs
  "s" #'gascity-jump-sessions
  "$" #'gascity-jump-costs)

(defalias 'gascity-jump-prefix gascity-jump-map
  "The `j' jump prefix bound in every gascity view (§5.2).")

(beads-define-prefix gascity-dispatch ()
  "Dispatch every gascity verb and view (dashboard-v3 §6.2).
Every suffix sits under the key it has in the views, so this menu
teaches the view keys."
  [:description gascity-dispatch--title
   ["Jump"
    ("j j" "cockpit" gascity-jump-cockpit)
    ("j a" "agents" gascity-jump-agents)
    ("j r" "runs" gascity-jump-runs)
    ("j b" "beads" gascity-jump-beads)
    ("j m" "mail" gascity-jump-mail)
    ("j e" "events" gascity-jump-events)
    ("j h" "health" gascity-jump-health)
    ("j c" "cities" gascity-jump-cities)
    ("j o" "orders" gascity-jump-orders)
    ("j v" "convoys" gascity-jump-convoys)
    ("j d" "dolt" gascity-jump-dolt)
    ("j g" "rig dashboard" gascity-jump-rig)
    ("j l" "rigs" gascity-jump-rigs)
    ("j s" "sessions" gascity-jump-sessions)
    ("j $" "costs" gascity-jump-costs)]
   ["Agent at point"
    ("M" "nudge…" gascity-session-nudge-at-point)
    ("s" "suspend" gascity-dashboard-suspend)
    ("w" "wake" gascity-session-wake-at-point)
    ("K" "kill" gascity-session-kill-at-point)
    ("D" "drain" gascity-session-drain-at-point)
    ("R" "reset" gascity-dashboard-reset)
    ("U" "undrain" gascity-session-undrain-at-point)
    ("t" "attach" gascity-tmux-at-point)]
   ["Work"
    ("S" "sling…" gascity-sling-dispatch)
    ("c" "bead actions…" gascity-bead-dispatch)
    ("m" "mail actions…" gascity-mail-dispatch)]
   ["City"
    ("L" "reload" gascity-reload)
    ("C" "lifecycle…" gascity-lifecycle-dispatch)
    ("O" "run order…" gascity-order-run)
    ("W" "toggle live" gascity-live-toggle)
    ("+" "more rows" gascity-section-more)
    ("-" "fewer rows" gascity-section-less)
    ("g" "refresh" gascity-dispatch-refresh)
    ("/" "filter…" gascity-dispatch-filter)]])

(defun gascity-dispatch--title ()
  "Return the `?' dispatch heading: the city, its path, live state."
  (let ((root (gascity-context-city-root-cached)))
    (concat "Gas City  "
            (propertize (if root (file-name-nondirectory (directory-file-name root)) "")
                        'face 'gascity-city)
            (if root (concat "  " (gascity-dashboard--path (file-local-name root))) "")
            (let ((live (and root (gascity-live-header-string root))))
              (if live (concat "   " live) "")))))

(defun gascity-dispatch-refresh ()
  "Refresh the view the dispatch was opened from (`g')."
  (interactive)
  (let ((cmd (keymap-lookup (current-local-map) "g")))
    (if (and cmd (not (eq cmd 'gascity-dispatch-refresh)))
        (call-interactively cmd)
      (user-error "Nothing to refresh here"))))

(defun gascity-dispatch-filter ()
  "Open the filter menu of the view the dispatch was opened from (`/')."
  (interactive)
  (let ((cmd (keymap-lookup (current-local-map) "/")))
    (if (and cmd (not (eq cmd 'gascity-dispatch-filter)))
        (call-interactively cmd)
      (user-error "This view has no filter"))))

;;; Mode

(defvar-keymap gascity-dashboard-mode-map
  :doc "Keymap for `gascity-dashboard-mode', the city cockpit."
  :parent gascity-section-mode-map
  "g"   #'gascity-dashboard-refresh
  "/"   #'gascity-dashboard-filter
  "RET" #'gascity-dashboard-activate
  "i"   #'gascity-polecat-detail-at-point
  "v"   #'gascity-session-peek-at-point
  "b"   #'gascity-beads-at-point
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  "l"   #'gascity-dashboard-rig-log
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-dashboard-suspend
  "r"   #'gascity-rig-resume-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "R"   #'gascity-dashboard-reset
  "U"   #'gascity-session-undrain-at-point
  "S"   #'gascity-sling-dispatch
  "c"   #'gascity-bead-dispatch
  "m"   #'gascity-mail-dispatch
  "L"   #'gascity-reload
  "C"   #'gascity-lifecycle-dispatch
  "O"   #'gascity-order-run)

(define-derived-mode gascity-dashboard-mode gascity-section-mode "GC-Cockpit"
  "Major mode for the city cockpit (dashboard-v3 §7.1).

TAB/S-TAB move between things, SPC toggles the thing at point, RET
acts on it, `?' shows every verb, `j' jumps to a view.

\\{gascity-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format '(:eval (gascity-dashboard--header-line)))
  (gascity-dashboard--install-filter)
  (gascity-live-attach (current-buffer)))

(defun gascity-dashboard--translate-runtime-error (err)
  "Re-signal ERR, translating a raw runtime-directory failure.
A `files--ensure-directory' failure under /run/user is not actionable
as a file error: it means gc's runtime directory is unusable (gc 1.5.1
cannot find the supervisor without XDG_RUNTIME_DIR under a clean
environment).  Signal a `user-error' naming the fix instead; every
other file error is re-signalled unchanged (ga-x40e)."
  (let ((message (error-message-string err)))
    (if (string-match-p "/run/user/[0-9]+" message)
        (user-error
         "Cannot use the runtime directory: %s; set XDG_RUNTIME_DIR=/run/user/%d"
         message (user-uid))
      (signal (car err) (cdr err)))))

;;;###autoload
(defun gascity-dashboard ()
  "Show the city cockpit: what needs you, what is moving, who works.
The buffer is keyed to the city it is opened for (host-qualified name,
pinned `default-directory'), so local and remote cockpits coexist.
Called from the menu of `project-switch-project', it opens the cockpit
of the chosen project's city."
  (interactive)
  (condition-case err
      (let* ((dir (gascity-context-city-for-view (beads-prefix-invocation-directory)))
             (city (or (gascity-context-city-name dir) "city"))
             (buf (gascity-view-get-buffer-create
                   (format gascity-dashboard-buffer-name city) dir)))
        (with-current-buffer buf
          (unless (derived-mode-p 'gascity-dashboard-mode)
            (gascity-dashboard-mode))
          (setq gascity-dashboard--city city))
        (unless (gascity-section-refresh-instance buf)
          (let ((filters (with-current-buffer buf
                           (alist-get (gascity-dashboard--city-key)
                                      gascity-dashboard-filters nil nil #'equal))))
            ;; vui-mount switch-to-buffers internally; display once, below.
            (save-window-excursion
              (vui-mount (vui-component 'gascity-dashboard-app
                                        :initial-filters filters)
                         (buffer-name buf)))))
        (pop-to-buffer buf))
    (file-error
     (gascity-dashboard--translate-runtime-error err))))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-status))
  "Open the cockpit instead of streaming raw `gc status' output."
  (gascity-dashboard))

(provide 'gascity-dashboard)
;;; gascity-dashboard.el ends here
