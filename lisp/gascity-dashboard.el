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
;;   Needs you     stalled agents, crashed sessions, idle/failed runs,
;;                 reopened and escalated beads, unread mail, store health
;;   Moving        active runs with their step ladder and live workers
;;   Agents        running, then idle; stopped folded into one line
;;   Work          ready beads by priority, noise hidden with a count
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
The rest collapse into a `… N more' line that opens the full view."
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

(defconst gascity-dashboard--width 78
  "Column where right-aligned cockpit hints end.")

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
    ("j o" . gascity-order-list)
    ("j v" . gascity-convoy-list)
    ("j d" . gascity-dolt-list)
    ("j g" . gascity-jump-rig)
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

;; The trailing supervisor session handle of a bead assignee
;; (`gc__implementation-worker-ec-56em' → `ec-56em'): a 2–4 letter city
;; prefix, then a `[a-z0-9]' body.  gc's own session ids are bead ids of
;; the city store (`ec-fl8o', `bl-rpq'), so two-letter prefixes are the
;; common case; the old 4-letter-only gate missed them (dashboard-v3 §2).
(defconst gascity-dashboard--session-handle-rx
  "\\`\\(?:gc\\|td\\|th\\|[a-z]\\{2,4\\}\\)-[a-z0-9]\\{1,32\\}\\'"
  "The trailing supervisor session-handle gate, anchored at both ends.")

(defun gascity-dashboard--bare-session-id-p (value)
  "Return non-nil when VALUE itself is a bare supervisor session id.
Same alphabet as `gascity-dashboard--session-handle-rx', plus the rule
that the id body carries a digit, which keeps a role such as
`scix-worker' from passing as an id."
  (and (stringp value)
       (string-match-p gascity-dashboard--session-handle-rx value)
       (let ((dash (string-search "-" value)))
         (and dash (string-match-p "[0-9]" (substring value (1+ dash)))))))

(defun gascity-dashboard--parse-assignee (assignee)
  "Split bead ASSIGNEE into (ROLE . SESSION-ID).
SESSION-ID is the minimal trailing session handle, or nil when there is
none (ROLE is then the whole trimmed assignee).  A bare session id
names itself: (ID . ID)."
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
                    (when (and (not (string-empty-p candidate))
                               (string-match-p
                                gascity-dashboard--session-handle-rx candidate))
                      (throw 'handle
                             (cons (substring trimmed 0 i) candidate)))))
                (setq i (1- i)))
              nil))
          (cons trimmed nil))))))

(defun gascity-dashboard--live-session-p (session)
  "Return non-nil when raw SESSION alist is live (active, not closed)."
  (and (equal (downcase (or (alist-get 'state session) "")) "active")
       (not (alist-get 'closed session))))

(defun gascity-dashboard--session-for-assignee (assignee sessions)
  "Return the live session in SESSIONS a bead ASSIGNEE refers to, or nil.
Joins on the tmux `session_name' (what gc assigns work to), then on the
session id parsed from the assignee's trailing handle, then on the
qualified agent name."
  (when (and (stringp assignee) (not (string-empty-p assignee)))
    (let ((live (seq-filter #'gascity-dashboard--live-session-p sessions))
          (id (cdr (gascity-dashboard--parse-assignee assignee))))
      (or (seq-find (lambda (s) (equal (alist-get 'session_name s) assignee)) live)
          (and id (seq-find (lambda (s) (equal (alist-get 'id s) id)) live))
          (seq-find (lambda (s) (equal (alist-get 'agent_name s) assignee)) live)))))

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

Each plist carries :name :rig :state (`stalled' `running' `idle'
`stopped' `suspended') :provider :bead (the in-progress bead id) :title
:active (last-active timestamp) :session :object (the action
`gascity-agent')."
  (let* ((live (seq-filter #'gascity-dashboard--live-session-p sessions))
         (by-name (make-hash-table :test 'equal))
         (seen (make-hash-table :test 'equal))
         (hooked (make-hash-table :test 'equal))
         (rows nil))
    (dolist (s live)
      (puthash (alist-get 'agent_name s) s by-name))
    ;; The in-progress bead each live session works on.
    (dolist (bead beads)
      (when (equal (alist-get 'status bead) "in_progress")
        (let ((s (gascity-dashboard--session-for-assignee
                  (alist-get 'assignee bead) live)))
          (when (and s (not (gethash (alist-get 'agent_name s) hooked)))
            (puthash (alist-get 'agent_name s) bead hooked)))))
    (cl-flet ((row (name agent session)
                (let* ((bead (gethash name hooked))
                       (running (if agent (alist-get 'running agent)
                                  (and session t)))
                       (active (and session (alist-get 'last_active session)))
                       (age (and active (gascity-ui-parse-time active)
                                 (- now (gascity-ui-parse-time active))))
                       (state (cond
                               ((and agent (alist-get 'suspended agent)) 'suspended)
                               ((and running (not session)) 'stalled)
                               ((not session) 'stopped)
                               ((and (not bead) age
                                     (> age gascity-dashboard-agent-idle-threshold))
                                'idle)
                               (t 'running))))
                  (list :name name
                        :rig (or (and session (alist-get 'rig session))
                                 (gascity-dashboard--rig-of name))
                        :state state
                        :provider (and session (alist-get 'provider session))
                        :bead (and bead (alist-get 'id bead))
                        :title (and bead (alist-get 'title bead))
                        :active active
                        :created (and session (alist-get 'created_at session))
                        :session session
                        :object (gascity-dashboard--agent-object
                                 name session socket running
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

(defun gascity-dashboard--agent-order (a b)
  "Return non-nil when agent plist A sorts before B in the Agents section.
Stalled first, then running by most recent activity, then idle."
  (let ((rank (lambda (x) (pcase (plist-get x :state)
                            ('stalled 0) ('running 1) ('idle 2)
                            ('suspended 3) (_ 4))))
        (time (lambda (x) (or (gascity-ui-parse-time (plist-get x :active)) 0))))
    (if (/= (funcall rank a) (funcall rank b))
        (< (funcall rank a) (funcall rank b))
      (> (funcall time a) (funcall time b)))))

;;; Runs (§3.2, §7.6)

(defun gascity-dashboard--run-root-p (bead)
  "Return non-nil when BEAD is a workflow run root (`gc.kind' workflow)."
  (equal (alist-get 'gc.kind (gascity-dashboard--meta bead)) "workflow"))

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

(defun gascity-dashboard--ladder (root graph)
  "Return the step ladder of run ROOT from its GRAPH beads.
GRAPH is every bead anchored to ROOT (`gc.root_bead_id'), any status.
Returns a list of plists (:name :id :state), one per top-level step, in
formula order (by blocks-dependency depth).  A step's state is its
latest iteration bead's (`gc.logical_bead_id' → step, max
`gc.attempt'), else its own.  In a failed run (root `gc.outcome'
fail) a closed step with a failed bead beneath it (a nested loop that
failed) is the failed step."
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
                     (name (substring (alist-get 'gc.step_ref
                                                 (gascity-dashboard--meta step))
                                      (1+ (length formula)))))
                (when (and (eq state 'done)
                           (gascity-dashboard--failed-beneath-p name failed-paths))
                  (setq state 'failed))
                (list :name name :id id :state state)))
            (sort steps (lambda (a b)
                          (let ((da (gethash (alist-get 'id a) depth 0))
                                (db (gethash (alist-get 'id b) depth 0)))
                            (if (/= da db) (< da db)
                              (string< (alist-get 'id a) (alist-get 'id b)))))))))

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
crashed/timed-out sessions not woken since, idle runs, failed runs,
reopened beads, escalated/held beads, unread mail, store health."
  (let* ((now (plist-get ctx :now))
         (events (plist-get ctx :events))
         (beads (plist-get ctx :beads))
         (items nil))
    (cl-flet ((add (&rest item) (push item items)))
      ;; ■ stalled agents: gc says running, no live session.
      (dolist (a (plist-get ctx :agents))
        (when (eq (plist-get a :state) 'stalled)
          (add :level 'fail :kind "agent" :id (concat "agent:" (plist-get a :name))
               :text (format "%s  running, no live session" (plist-get a :name))
               :right (or (plist-get a :rig) "city")
               :drawer (lambda () (gascity-dashboard--agent-drawer a))
               :props (list 'gascity-agent (plist-get a :object)))))
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
      ;; ■ idle runs: no in-progress step touched within the threshold.
      (dolist (root (gascity-dashboard--active-runs beads))
        (let* ((id (alist-get 'id root))
               (steps (seq-filter (lambda (b)
                                    (and (equal (gascity-dashboard--root-of b) id)
                                         (equal (alist-get 'status b) "in_progress")))
                                  beads))
               (last (apply #'max
                            (or (gascity-ui-parse-time (alist-get 'updated_at root)) 0)
                            (mapcar (lambda (b)
                                      (or (gascity-ui-parse-time
                                           (alist-get 'updated_at b))
                                          0))
                                    steps)))
               (idle (- now last)))
          (when (and (> last 0) (> idle gascity-dashboard-run-idle-threshold))
            (add :level 'fail :kind "run" :id (concat "run:" id)
                 :text (format "%s %s  idle %s" id
                               (or (alist-get 'gc.formula_name
                                              (gascity-dashboard--meta root))
                                   (alist-get 'title root) "")
                               (gascity-ui-duration idle))
                 :right (or (alist-get 'gascity-rig root) "city")
                 :props (list 'gascity-bead id
                              'gascity-run-rig (or (alist-get 'gascity-rig root) ""))))))
      ;; ■ runs that failed in the window (root closed, gc.outcome fail).
      (let ((seen (make-hash-table :test 'equal)))
        (dolist (e (reverse events))
          (let* ((bead (gascity-event-bead e))
                 (meta (and bead (gascity-dashboard--meta bead)))
                 (id (and bead (alist-get 'id bead))))
            (when (and (equal (alist-get 'type e) "bead.closed")
                       (equal (alist-get 'gc.kind meta) "workflow")
                       (equal (alist-get 'gc.outcome meta) "fail")
                       (not (gethash id seen)))
              (puthash id t seen)
              (add :level 'fail :kind "run" :id (concat "failed:" id)
                   :text (format "%s %s  failed" id
                                 (or (alist-get 'gc.formula_name meta) ""))
                   :right (or (gascity-dashboard--store-of-id id ctx) "")
                   :time (alist-get 'ts e)
                   :props (list 'gascity-bead id
                                'gascity-run-rig
                                (or (gascity-dashboard--store-of-id id ctx) "")))))))
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
                         (format "health: %s" (car partial))
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
:status :sessions :mail :events :work :convoys :escalations :graphs."
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
         (rigs (append (alist-get 'rigs status) nil))
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
          :graphs (gascity-dashboard--data (plist-get loads :graphs))
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
                (t body)))))

(defun gascity-dashboard--cap-groups (groups name target &optional fold)
  "Flatten GROUPS (the lines of one item each), capped for section NAME.
Shows at most `gascity-dashboard-section-rows' items, then a `… N more'
line whose RET runs TARGET (§4.2).  With FOLD, SPC on the more line
expands the section in place instead of leaving it."
  (let* ((max gascity-dashboard-section-rows)
         (total (length groups))
         (id (concat "more:" name))
         (expanded (and fold (member id (plist-get gascity-dashboard--view
                                                   :expanded)))))
    (if (or expanded (<= total max))
        (apply #'append groups)
      (append (apply #'append (seq-take groups max))
              (list (gascity-dashboard--row
                     (gascity-dashboard--dim (format "  … %d more" (- total max)))
                     (gascity-dashboard--dim (gascity-dashboard--target-hint target))
                     'gascity-dashboard-target target
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
                                                         (string-join partial "; "))))
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
                           (gascity-ui-fit (plist-get item :text) 48)
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
     ctx :loads '(:status :sessions :events :work :mail :escalations)
     :label "status")))

(defun gascity-dashboard--needs-you-drawer (item)
  "Return the drawer lines of a Needs you ITEM."
  (let ((event (plist-get (plist-get item :props) 'gascity-dashboard-event)))
    (cond ((plist-get item :drawer) (funcall (plist-get item :drawer)))
          (event (gascity-event-fields event))
          (t (list (format "%s  %s" (plist-get item :kind) (plist-get item :text)))))))

(defun gascity-dashboard--moving-lines (ctx)
  "Return the Moving section lines for CTX: runs with their workers."
  (let* ((beads (seq-filter (lambda (b) (gascity-dashboard--in-rig-p b ctx))
                            (plist-get ctx :beads)))
         (runs (gascity-dashboard--active-runs beads))
         (sessions (plist-get ctx :sessions))
         (graphs (plist-get ctx :graphs))
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
         (workers 0)
         (items nil))
    (dolist (root runs)
      (let* ((id (alist-get 'id root))
             (graph (or (gethash id (or graphs (make-hash-table)))
                        (seq-filter (lambda (b) (equal (gascity-dashboard--root-of b) id))
                                    beads)))
             (ladder (gascity-dashboard--ladder root graph))
             (label (gascity-dashboard--ladder-label ladder))
             (rig (alist-get 'gascity-rig root))
             (nested (gascity-dashboard--one-per-worker
                      (seq-filter (lambda (b) (equal (gascity-dashboard--root-of b) id))
                                  in-progress))))
        (push (append
               (gascity-dashboard--object-row
                (concat "run:" id)
                (concat "  " (gascity-ui-glyph 'active) " "
                        (gascity-ui-fit id 9) " "
                        (gascity-ui-fit (or (alist-get 'gc.formula_name
                                                       (gascity-dashboard--meta root))
                                            (alist-get 'title root) "")
                                        12)
                        " " (gascity-dashboard--ladder-string ladder)
                        "  " (gascity-ui-fit (car label) 14)
                        " " (gascity-ui-fit (cdr label) 6)
                        " " (gascity-ui-time (alist-get 'created_at root) now))
                (gascity-dashboard--dim (or rig "city"))
                (lambda () (gascity-dashboard--run-drawer ladder))
                'gascity-bead id 'gascity-run-rig (or rig ""))
               (mapcan (lambda (b)
                         (setq workers (1+ workers))
                         (gascity-dashboard--worker-row b sessions ctx "    └ " t))
                       (seq-take nested 3)))
              items)))
    (dolist (b flat)
      (when (gascity-dashboard--session-for-assignee (alist-get 'assignee b) sessions)
        (setq workers (1+ workers)))
      (push (gascity-dashboard--worker-row b sessions ctx "  ") items))
    (setq items (nreverse items))
    (gascity-dashboard--section-lines
     "moving" "Moving"
     (and items
          (format "%d run%s · %d worker%s" (length runs) (if (= (length runs) 1) "" "s")
                  workers (if (= workers 1) "" "s")))
     (gascity-dashboard--cap-groups items "moving" #'gascity-jump-runs)
     ctx :loads '(:work) :label "bd list")))

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
worker drawn under its run (not a top-level row of the section)."
  (let* ((session (gascity-dashboard--session-for-assignee
                   (alist-get 'assignee bead) sessions))
         (id (alist-get 'id bead))
         (name (if session (alist-get 'agent_name session)
                 (or (car (gascity-dashboard--parse-assignee
                           (alist-get 'assignee bead)))
                     "unassigned")))
         (agent (and session (gascity-dashboard--agent-object
                              name session (plist-get ctx :socket)))))
    (apply #'gascity-dashboard--object-row
           (concat "work:" id)
           (concat indent (gascity-ui-pending-glyph
                           name (gascity-ui-glyph (if session 'ok 'idle)))
                   " "
                   (gascity-ui-fit (gascity-dashboard--short-agent name) 24) " "
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
                       #'gascity-dashboard--agent-order))
         (awake (seq-remove (lambda (a) (memq (plist-get a :state) '(stopped suspended)))
                            agents))
         (asleep (seq-filter (lambda (a) (memq (plist-get a :state) '(stopped suspended)))
                             agents))
         (count (lambda (state) (seq-count (lambda (a) (eq (plist-get a :state) state))
                                           agents)))
         (summary (string-join
                   (delq nil
                         (list (and (> (funcall count 'stalled) 0)
                                    (format "%d stalled" (funcall count 'stalled)))
                               (and (> (funcall count 'running) 0)
                                    (format "%d running" (funcall count 'running)))
                               (and (> (funcall count 'idle) 0)
                                    (format "%d idle" (funcall count 'idle)))
                               (and asleep (format "%d stopped" (length asleep)))))
                   " · "))
         (gascity-dashboard-section-rows
          ;; The `▸ stopped' fold is one of the section's rows.
          (if asleep (max 1 (1- gascity-dashboard-section-rows))
            gascity-dashboard-section-rows))
         (rows (gascity-dashboard--cap-groups
                (mapcar (lambda (a) (gascity-dashboard--agent-row a ctx)) awake)
                "agents" #'gascity-jump-agents)))
    (gascity-dashboard--section-lines
     "agents" "Agents" summary
     (append rows (and asleep (gascity-dashboard--stopped-fold asleep ctx)))
     ctx :loads '(:status :sessions) :label "status" :hint "j a all")))

(defun gascity-dashboard--agent-row (agent ctx)
  "Return the lines of AGENT's row (and drawer) in CTX."
  (let* ((state (plist-get agent :state))
         (name (plist-get agent :name)))
    (gascity-dashboard--object-row
     (concat "agent:" name)
     (concat "  " (gascity-ui-pending-glyph
                   name (gascity-ui-glyph (pcase state ('stalled 'fail)
                                            ('running 'ok) (_ 'idle))))
             " " (gascity-ui-fit name 34)
             " " (gascity-ui-fit (or (plist-get agent :provider) "") 4)
             " " (gascity-ui-fit (or (plist-get agent :bead) "") 9)
             " " (gascity-ui-fit (symbol-name (if (eq state 'running) 'active state)) 8)
             (gascity-ui-time (plist-get agent :active) (plist-get ctx :now)))
     nil
     (lambda () (gascity-dashboard--agent-drawer agent))
     'gascity-agent (plist-get agent :object))))

(defun gascity-dashboard--agent-drawer (agent)
  "Return AGENT's drawer lines: session, workdir, hooked bead, created."
  (let ((session (plist-get agent :session)))
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
                (and (not session)
                     (pcase (plist-get agent :state)
                       ('stalled "gc says running; no live session backs it")
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
        (ready nil) (in-progress 0) (blocked 0) (hidden nil))
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
              (setq in-progress (1+ in-progress))))
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
          :blocked blocked
          :hidden (nreverse hidden))))

(defun gascity-dashboard--work-lines (ctx)
  "Return the Work section lines for CTX."
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
         (rows (mapcar
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
                ready)))
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
            (shown (seq-take events gascity-dashboard-churn-unfold-rows))
            (more (- (length events) (length shown))))
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
                               (gascity-dashboard--dim "RET j e events")
                               'gascity-dashboard-target target
                               'beads-thing (gascity-dashboard--thing
                                             'more (concat id ":more"))))))))))))

(defun gascity-dashboard--events-target (group ctx)
  "Return the command opening the Events view narrowed to churn GROUP.
The Events window follows the cockpit's (CTX's filters)."
  (let ((window (plist-get (plist-get ctx :filters) :window)))
    (lambda ()
      (interactive)
      (gascity-events (append (list :group group)
                              (and window (list :window window)))))))

(defun gascity-dashboard--rigs-lines (ctx)
  "Return the Rigs section lines for CTX."
  (let* ((agents (plist-get ctx :all-agents))
         (beads (plist-get ctx :beads))
         (rows (mapcar
                (lambda (rig)
                  (let* ((name (alist-get 'name rig))
                         (mine (seq-filter (lambda (a) (equal (plist-get a :rig) name))
                                           agents))
                         (up (seq-count (lambda (a) (memq (plist-get a :state)
                                                          '(running idle stalled)))
                                        mine))
                         (wip (seq-count (lambda (b)
                                           (and (equal (alist-get 'gascity-rig b) name)
                                                (equal (alist-get 'status b) "in_progress")
                                                (not (gascity-event-noise b))))
                                         beads)))
                    (gascity-dashboard--object-row
                     (concat "rig:" name)
                     (concat "  " (gascity-ui-fit name 12)
                             " " (gascity-ui-fit (or (alist-get 'prefix rig) "") 4)
                             " " (gascity-ui-fit (gascity-dashboard--path
                                                  (alist-get 'path rig))
                                                 26)
                             " " (gascity-ui-fit (format "%d/%d agents" up (length mine)) 12)
                             " " (format "%d in progress" wip))
                     (and (alist-get 'suspended rig)
                          (propertize "suspended" 'face 'gascity-suspended))
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
     ctx :loads '(:status) :label "status")))

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

(defun gascity-dashboard--read-graphs (runs resolve reject)
  "Read the full step graph of each active run in RUNS.
RUNS is a list of (ID . RIG); one `bd list --all --metadata-field
gc.root_bead_id=ID' read per run.  RESOLVE gets a hash ID → beads; a
failed read leaves its run on the partial ladder the work read gives,
so REJECT is never called."
  (let ((table (make-hash-table :test 'equal))
        (force gascity-store-loader-force)
        (pending (length runs)))
    (if (null runs)
        (funcall resolve table)
      (dolist (run runs)
        (let ((settle (lambda ()
                        (setq pending (1- pending))
                        (when (zerop pending) (funcall resolve table)))))
          (gascity-store-fetch
           (append (list "bd" "list" "--all" "-n" "0" "--brief"
                         "--metadata-field" (concat "gc.root_bead_id=" (car run)))
                   (and (cdr run) (list "--rig" (cdr run))))
           (lambda (payload)
             (puthash (car run) (gascity-section-beads payload) table)
             (funcall settle))
           (lambda (_err) (funcall settle))
           :force force)))
      (ignore reject))))

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
         (last-graphs (vui-use-ref nil))
         (work (gascity-dashboard--effective-load work-res last-work))
         ;; The active runs' full graphs: keyed on the run set, so a new
         ;; or finished run re-reads, a refresh re-reads too.
         (runs (mapcar (lambda (r) (cons (alist-get 'id r) (alist-get 'gascity-rig r)))
                       (seq-take (gascity-dashboard--active-runs
                                  (plist-get (gascity-dashboard--data work) :beads))
                                 gascity-dashboard-section-rows)))
         (graphs-res (gascity-store-use (list "bd" "list" :graphs runs)
                                        :tick refresh-tick
                                        :loader (lambda (resolve reject)
                                                  (gascity-dashboard--read-graphs
                                                   runs resolve reject))))
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
                      :graphs (gascity-dashboard--effective-load graphs-res
                                                                 last-graphs)))
         (ctx (gascity-dashboard--context loads filters (float-time))))
    ;; Once per render: the section and the pulse both read them.
    (setq ctx (plist-put ctx :needs-you (gascity-dashboard--needs-you ctx)))
    ;; `↻' is the last change of anything the cockpit shows: a read, or
    ;; events the live stream appended (store `:updated-at').
    (let ((at (apply #'max 0 (delq nil (mapcar (lambda (r) (plist-get r :updated-at))
                                               (list status-res sessions-res mail-res
                                                     events-res work-res convoys-res
                                                     escalations-res))))))
      (when (> at 0)
        (setq gascity-dashboard--refreshed-at at)))
    (when-let* ((status (plist-get ctx :status)))
      ;; Seed the rig memo from the payload in hand: the rig prompts
      ;; and the next work read then never spawn `gc rig list'.
      (gascity-rigs-remember
       (gascity-domain-decode-list 'gascity-rig (alist-get 'rigs status)))
      (gascity-dashboard--publish ctx))
    (setq ctx (plist-put ctx :view (list :collapsed collapsed :drawers drawers
                                         :expanded expanded)))
    ;; One text vnode: the lines are plain propertized strings (blank
    ;; separator lines included, which vui would drop as empty vnodes).
    (vui-text (string-join (gascity-dashboard--lines ctx) "\n"))))

;;; Pulse (§7.11, §7.12): what other views may show without a gc call

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

(defun gascity-dashboard-refresh ()
  "Re-read every cockpit section, keeping point, folds and drawers.
Also reconnects the city's live stream when it is down."
  (interactive)
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

(defun gascity-dashboard--rig-row-p ()
  "Return non-nil when point is on a Rigs row (not an agent)."
  (and (get-text-property (point) 'gascity-rig)
       (not (get-text-property (point) 'gascity-agent))))

(defun gascity-dashboard-suspend ()
  "Suspend the agent or rig at point (`s', §5.3)."
  (interactive)
  (if (gascity-dashboard--rig-row-p)
      (gascity-rig-suspend-at-point)
    (gascity-session-suspend-at-point)))

(defun gascity-dashboard-reset ()
  "Reset the agent, or restart the rig, at point (`R', confirmed)."
  (interactive)
  (if (gascity-dashboard--rig-row-p)
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

(defun gascity-jump--call (candidates name)
  "Call the first defined command of CANDIDATES, else say NAME is pending.
Views built by later phases are reached by name; until one exists the
jump echoes instead of failing."
  ;; `commandp', not `fboundp': a jump target must be interactive.
  (let ((cmd (seq-find #'commandp candidates)))
    (if cmd
        (call-interactively cmd)
      (message "The %s view is not available yet" name))))

(defun gascity-jump-cockpit ()
  "Jump to this city's cockpit (`j j')."
  (interactive)
  (gascity-dashboard))

(defun gascity-jump-agents ()
  "Jump to the Agents view (`j a')."
  (interactive)
  (gascity-jump--call '(gascity-agents gascity-session-list) "Agents"))

(defun gascity-jump-runs ()
  "Jump to the Runs view (`j r')."
  (interactive)
  (gascity-jump--call '(gascity-runs) "Runs"))

(defun gascity-jump-events ()
  "Jump to the Events view (`j e')."
  (interactive)
  (gascity-jump--call '(gascity-events) "Events"))

(defun gascity-jump-health ()
  "Jump to the Health view (`j h')."
  (interactive)
  (gascity-jump--call '(gascity-health) "Health"))

(defun gascity-jump-cities ()
  "Jump to the Cities view (`j c')."
  (interactive)
  (gascity-jump--call '(gascity-cities) "Cities"))

(defun gascity-jump-mail ()
  "Jump to the Mail inbox (`j m')."
  (interactive)
  (gascity-jump--call '(gascity-mail gascity-mail-inbox) "Mail"))

(defun gascity-jump-costs ()
  "Show `gc costs' output (`j $')."
  (interactive)
  (gascity-jump--call '(gascity-costs) "Costs"))

(defun gascity-jump-rig ()
  "Open the rig dashboard of the rig at point, else prompt (`j g').
The prompt reads the rig memo only — never a synchronous `gc' — and
refreshes it in the background (`gascity-rig-names-for-prompt'), so a
cold memo fills in for the next prompt; \"city\" opens the cockpit."
  (interactive)
  (let ((rig (or (gascity-rig-at-point)
                 (completing-read "Rig: "
                                  (cons "city" (gascity-rig-names-for-prompt))
                                  nil t))))
    (if (equal rig "city")
        (gascity-dashboard)
      (gascity-rig-dashboard rig))))

(defun gascity-jump-beads ()
  "Open beads.el for the rig at point, else chosen: a rig or the city (`j b').
Candidates come from the rig memo only (§8.5), refreshed in the
background for the next prompt."
  (interactive)
  (let ((rig (or (gascity-rig-at-point)
                 (let ((choice (completing-read
                                "Beads for: "
                                (cons "city" (progn
                                               ;; Background refresh of the memo.
                                               (gascity-rig-names-for-prompt)
                                               (gascity-dashboard--rig-store-names
                                                (gascity-rigs-cached))))
                                nil t)))
                   (and (not (equal choice "city")) choice)))))
    (if rig
        (gascity-rig-beads rig)
      (let ((store (gascity-beads--city-store)))
        (unless (fboundp 'beads-dashboard) (require 'beads-dashboard nil t))
        (beads-dashboard :directory store)))))

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
  "o" #'gascity-order-list
  "v" #'gascity-convoy-list
  "d" #'gascity-dolt-list
  "g" #'gascity-jump-rig
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
    ("j o" "orders" gascity-order-list)
    ("j v" "convoys" gascity-convoy-list)
    ("j d" "dolt" gascity-dolt-list)
    ("j g" "rig dashboard" gascity-jump-rig)
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

;;;###autoload
(defun gascity-dashboard ()
  "Show the city cockpit: what needs you, what is moving, who works.
The buffer is keyed to the city it is opened for (host-qualified name,
pinned `default-directory'), so local and remote cockpits coexist.
Called from the menu of `project-switch-project', it opens the cockpit
of the chosen project's city."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
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
    (pop-to-buffer buf)))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-status))
  "Open the cockpit instead of streaming raw `gc status' output."
  (gascity-dashboard))

(provide 'gascity-dashboard)
;;; gascity-dashboard.el ends here
