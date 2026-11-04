;;; gascity-agents.el --- The Agents view: a tabulated list -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The Agents view (dashboard-v3 §7.3), `j a' from every view:
;;
;; - `gascity-agents' is the single Agents view: a tabulated list of
;;   every agent of the city — `gc status''s configured agents joined to
;;   their live sessions, plus the named sessions (the mayor) — with
;;   state, last activity, the bead on the hook and the provider.
;;   Stalled agents (■) are pinned first.  `/' filters by state (running
;;   by default; stalled rows are always shown), rig, provider and a
;;   search string; the shared tabulated keys sort, page and bookmark.
;;   The tree alternative was retired (ga-2mmet): it rendered the same
;;   agents, and pool topology, if wanted later, reads better as a
;;   grouping option on this table than as a second view.
;;
;; The sling's Who completion (REQ-005, plans/sling-command WI-2) also
;; reads here: `gascity-agents-roster' returns the same agent plists
;; ordered city-first then per rig, over the very same store reads —
;; the sling's `T' target picker candidates (`gascity-agents-roster-candidates'),
;; the scope classifier (`gascity-agents-scope') and the target lookup
;; (`gascity-agents-roster-scope') the pre-launch validators consume.
;; Unlike the table, the roster also carries the configured agents of
;; `gc agent list' that no status or session row observes — state
;; `configured' (ga-rghou): a rig's `gc.run-operator' and its other
;; lane templates are exactly the sling targets the picker must offer.
;;
;; Reads (one named loader each, through the store — shared with the
;; cockpit, capped per host, bounded by its deadline): `gc status', `gc
;; session list', `gc agent list' (providers and pool bounds) and the
;; cockpit's work read (the hooked bead).  A refresh keeps the previous
;; rows while its reads are in flight and keeps the last good payload of
;; any read that fails.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)
(require 'transient)
(require 'vui)
(require 'beads-prefix)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-context)
(require 'gascity-domain)
(require 'gascity-store)
(require 'gascity-tabulated)
(require 'gascity-dashboard)

(declare-function gascity-polecat-detail-at-point "gascity-session")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-session-reset-at-point "gascity-action")
(declare-function gascity-session-undrain-at-point "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")

(defconst gascity-agents-buffer-name "*gascity-agents: %s*"
  "Format of the Agents view's base buffer name; %s is the city.")

;;; Reads

(defvar gascity-agents--force nil
  "Non-nil while an explicit `g' refresh reads past the store's TTL.")

(defun gascity-agents--read-status (resolve reject)
  "Read `gc status' for the Agents view; RESOLVE or REJECT."
  (gascity-store-fetch '("status") resolve reject :force gascity-agents--force))

(defun gascity-agents--read-sessions (resolve reject)
  "Read `gc session list' for the Agents view.
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch '("session" "list") resolve reject
                       :force gascity-agents--force))

(defun gascity-agents--read-agents (resolve reject)
  "Read `gc agent list' (providers, pool bounds) for the Agents view.
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch '("agent" "list") resolve reject
                       :force gascity-agents--force))

(defun gascity-agents--read-work (resolve reject)
  "Read the work beads (for each agent's hooked bead), as the cockpit does.
RESOLVE gets the payload, REJECT the failure text."
  (gascity-store-fetch '("bd" "list" :work-stores) resolve reject
                       :loader #'gascity-dashboard--read-work
                       :force gascity-agents--force))

(defconst gascity-agents--loaders
  '((:status . gascity-agents--read-status)
    (:sessions . gascity-agents--read-sessions)
    (:agents . gascity-agents--read-agents)
    (:work . gascity-agents--read-work))
  "The Agents view's reads: payload key → loader.")

;;; Model (pure)

(defun gascity-agents--providers (agent-list)
  "Return a hash: qualified agent/template name → provider, from AGENT-LIST."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (a (append (alist-get 'agents agent-list) nil))
      (when (and (alist-get 'qualified_name a) (alist-get 'provider a))
        (puthash (alist-get 'qualified_name a) (alist-get 'provider a) table)))
    table))

(defun gascity-agents--provider (agent providers)
  "Return AGENT's provider: its session's, else its template's in PROVIDERS."
  (or (plist-get agent :provider)
      (gethash (plist-get agent :name) providers)
      ;; A numbered pool member takes its template's provider.
      (let ((name (plist-get agent :name)))
        (and (stringp name) (string-match "\\`\\(.+\\)-[0-9]+\\'" name)
             (gethash (match-string 1 name) providers)))))

(defun gascity-agents--rows (data now)
  "Return the agent plists of the payloads DATA at NOW, stalled first.
DATA is a plist (:status :sessions :agents :work) of payloads (any may
be nil).  Each plist also carries :provider filled from `gc agent
list' when the agent has no session."
  (let* ((status (plist-get data :status))
         (sessions (append (alist-get 'sessions (plist-get data :sessions)) nil))
         (beads (plist-get (plist-get data :work) :beads))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status) 'no-probe))
         (providers (gascity-agents--providers (plist-get data :agents)))
         (rows (gascity-dashboard--agents status sessions beads socket now)))
    (sort (mapcar (lambda (a)
                    (plist-put (copy-sequence a) :provider
                               (gascity-agents--provider a providers)))
                  rows)
          #'gascity-dashboard--agent-order)))

(defun gascity-agents--match-p (agent filter)
  "Return non-nil when AGENT passes FILTER (a plist, §7.3).
:state `running' keeps running, idle and stalled agents; `all' or nil
keeps every one; any other value that state.  Stalled agents always
pass the state filter.  :rig, :provider and :search (a case-insensitive
substring of the name) narrow further."
  (let ((state (plist-get filter :state))
        (rig (plist-get filter :rig))
        (provider (plist-get filter :provider))
        (search (plist-get filter :search))
        (s (plist-get agent :state)))
    (and (or (null state) (equal state "all") (eq s 'stalled)
             (if (equal state "running")
                 (memq s '(running idle stalled))
               (equal state (symbol-name s))))
         (or (null rig)
             (equal rig (or (plist-get agent :rig) "city")))
         (or (null provider) (equal provider (plist-get agent :provider)))
         (or (null search)
             (let ((case-fold-search t))
               (string-match-p (regexp-quote search) (plist-get agent :name)))))))

(defun gascity-agents--state-label (agent)
  "Return AGENT's state column: active, idle, stopped, stalled, suspended."
  (pcase (plist-get agent :state)
    ('running "active")
    (s (symbol-name s))))

(defun gascity-agents--entry (agent now)
  "Return the tabulated entry of AGENT at NOW; its id is the action object."
  (let* ((state (plist-get agent :state))
         (name (plist-get agent :name))
         (rig (plist-get agent :rig))
         (short (if (and rig (string-prefix-p (concat rig "/") name))
                    (substring name (1+ (length rig)))
                  name)))
    (list (plist-get agent :object)
          (vector (gascity-ui-glyph (pcase state ('stalled 'fail)
                                      ('running 'ok) (_ 'idle)))
                  (propertize short 'face (if (eq state 'stalled)
                                              'gascity-failed
                                            'default))
                  (or rig "—")
                  (gascity-agents--state-label agent)
                  (let ((ts (plist-get agent :active)))
                    (if ts (gascity-ui-time ts now) "—"))
                  (or (plist-get agent :bead) "")
                  (or (plist-get agent :provider) "")))))

(defun gascity-agents--summary (rows)
  "Return `3 running · 1 idle · 3 stopped' for agent ROWS."
  (let ((count (lambda (states) (seq-count (lambda (a) (memq (plist-get a :state) states))
                                           rows))))
    (string-join
     (delq nil (list (let ((n (funcall count '(stalled)))) (and (> n 0) (format "%d stalled" n)))
                     (let ((n (funcall count '(running)))) (and (> n 0) (format "%d running" n)))
                     (let ((n (funcall count '(idle)))) (and (> n 0) (format "%d idle" n)))
                     (let ((n (funcall count '(stopped suspended))))
                       (and (> n 0) (format "%d stopped" n)))))
     " · ")))

;;; Roster — the sling's Who completion (REQ-005)

;; The completion-facing half of the sling's Who stage (plans/
;; sling-command, WI-2): candidates over the same loaders the table
;; refreshes with, so the `T' picker never opens a new gc call site.
;; The scope classifier feeds the pre-launch validators in
;; `gascity-formula.el'; a cold roster never dead-ends — completion
;; over nil is free entry, and the scope-dependent checks degrade.

(defun gascity-agents-scope (agent)
  "Return AGENT's sling scope: its rig's name, or \"city\".
The classifier behind the Who annotation and the REQ-010 validators:
the roster plist's `:rig' wins; a name with a slash prefix names its
rig on its own (a qualified agent joined without a rig); everything
else is city-scoped.  Pure."
  (or (plist-get agent :rig)
      (let ((name (plist-get agent :name)))
        (if (and (stringp name)
                 (string-search "/" name))
            (substring name 0 (string-search "/" name))
          "city"))))

(defun gascity-agents--configured-row (agent)
  "Return AGENT's sling roster row, or nil when it names no agent.
AGENT is one `gc agent list' entry — a configured agent or pool
template, whether or not any status or session row observes it.  The
row names it by its qualified name and normalizes `:rig' from that
name's slash prefix (the list's own `scope' is absent on some rows).
Its state is `configured' — the config exists, no status or session
row observes it — or `suspended' when the config is suspended; a live
or status row for the same name always wins over it.  The action
object and provider are filled as the observed rows' are."
  (let ((name (alist-get 'qualified_name agent)))
    (when (stringp name)
      (let ((rig (gascity-dashboard--rig-of name)))
        (list :name name
              :rig rig
              :state (if (alist-get 'suspended agent) 'suspended 'configured)
              :provider (alist-get 'provider agent)
              :object (gascity-dashboard--agent-object name nil nil nil rig))))))

(defun gascity-agents--roster (data)
  "Return the agent plists of DATA, city agents first then per rig.
DATA is the Agents view's reads plist (:status :sessions :agents
:work — any may be nil: a cold or failed read degrades to the rows
the rest still join).  The `T' picker's candidate order (mockup §6c):
city agents first, then each rig's in `gc status''s rig order; within
a group the dashboard's row order (stalled first) is kept, and
agents of rigs the status payload does not name follow, grouped by
scope in row order.  Observed rows come first within a group; the
`gc agent list' agents no status or session row observes follow them
with state `configured' (ga-rghou): the Who picker must offer every
config `gc sling' accepts, not only the ones with live state.  The
Agents table itself stays observed-only.  Deduplicated by qualified
name, live/status rows first.  Pure."
  (let* ((rows (gascity-agents--rows data (float-time)))
         (observed (make-hash-table :test 'equal))
         (rigs (delete-dups
                (seq-keep (lambda (rig) (alist-get 'name rig))
                          (append (alist-get 'rigs (plist-get data :status))
                                  nil))))
         (scope (lambda (agent) (gascity-agents-scope agent))))
    ;; The configured agents no observed row names (ga-rghou): a rig's
    ;; `gc.run-operator' and its other lane templates have no live
    ;; session most of the time, yet they are exactly the Who
    ;; roster's entries.  Append them before grouping so they land in
    ;; their rig's (or the city's) group, after the observed rows.
    (dolist (row rows)
      (puthash (plist-get row :name) t observed))
    (dolist (agent (append (alist-get 'agents (plist-get data :agents)) nil))
      (let ((name (alist-get 'qualified_name agent)))
        (when (and (stringp name) (not (gethash name observed)))
          (when-let* ((row (gascity-agents--configured-row agent)))
            (puthash name t observed)
            (setq rows (append rows (list row)))))))
    (append
     (seq-filter (lambda (a) (equal (funcall scope a) "city")) rows)
     (apply #'append
            (mapcar (lambda (rig)
                      (seq-filter (lambda (a) (equal (funcall scope a) rig)) rows))
                    rigs))
     ;; Rigs `gc status' did not name still show, grouped after the
     ;; known ones — never dropped.
     (let ((left (seq-remove (lambda (a)
                               (or (equal (funcall scope a) "city")
                                   (member (funcall scope a) rigs)))
                             rows))
           (scopes nil))
       (dolist (a left)
         (cl-pushnew (funcall scope a) scopes :test #'equal))
       (apply #'append
              (mapcar (lambda (rig)
                        (seq-filter (lambda (a) (equal (funcall scope a) rig))
                                    left))
                      (nreverse scopes)))))))

(defun gascity-agents-roster-candidates (roster)
  "Return ROSTER's completion candidates: \\(name . \"<rig|city> · state\").
The `T' picker annotates each agent with its scope and live state
\\(mockup §6c) — the state through `gascity-agents--state-label'.
Pure over the roster plists."
  (mapcar (lambda (agent)
            (cons (plist-get agent :name)
                  (format "%s · %s"
                          (gascity-agents-scope agent)
                          (gascity-agents--state-label agent))))
          roster))

(defun gascity-agents-roster-scope (target roster)
  "Return the scope of the roster agent named TARGET, or nil.
ROSTER is `gascity-agents--roster''s joined list.  A roster row named
TARGET classifies through `gascity-agents-scope'.  Without one, a
TARGET that names a rig itself — a slash prefix — is rig-scoped on
its own: the pool instances the joined roster carries
\\(`…/gc.implementation-worker-1') never match a config-name target
exactly, and the Who default names configs, so the classifier falls
back to the name's own prefix (the plan's scope classifier: roster
`:rig', or the name's slash prefix).  Free entry — a typed name no
roster row carries and no slash names — cannot be classified, so nil:
the scope-dependent validators (REQ-010) degrade instead of
dead-ending; gc stays the authority.  Pure."
  (or (when-let* ((agent (seq-find (lambda (a)
                                     (equal (plist-get a :name) target))
                                   roster)))
        (gascity-agents-scope agent))
      (and (stringp target)
           (string-search "/" target)
           (substring target 0 (string-search "/" target)))))

(defun gascity-agents--read-roster (done &optional cached)
  "Read the roster's payloads through the store; call DONE with them.
The same four reads the Agents table refreshes with
\(`gascity-agents--loaders'), collected outside a view buffer: every
read's answer lands in the plist DONE receives, keyed like the
loaders — a failed read's key stays absent, so the roster degrades to
what the rest still join.  CACHED honors the store's TTL (a silent
prefetch); the default forces past it.  DONE is called once, from
whatever read answered last.  Returns nil."
  (let* ((outstanding (length gascity-agents--loaders))
         (data nil)
         (gascity-agents--force (not cached))
         (finish (lambda ()
                   (when (zerop (setq outstanding (1- outstanding)))
                     (funcall done data)))))
    (pcase-dolist (`(,key . ,loader) gascity-agents--loaders)
      (funcall loader
               (lambda (payload)
                 (setq data (plist-put data key payload))
                 (funcall finish))
               (lambda (_err) (funcall finish))))
    nil))

(defun gascity-agents-roster (&optional cached)
  "Return this city's agent roster: plists, city agents first then per rig.
The completion-facing Who accessor (REQ-005) over the same store
reads the Agents view uses — never a new gc call site.  A cold store
is read first and waited on, deadline-bounded (`C-g' quits), like the
formula picker's `gascity-formula-choices-wait': the `T' read is
input collection (D9).  CACHED keeps the store's TTL; the default
forces a fresh read.  Returns nil when nothing answered — completion
over nil is free entry, so a cold roster never dead-ends a dispatch."
  (let ((done nil)
        (data nil)
        (deadline (+ (float-time)
                     (if (numberp gascity-remote-async-timeout)
                         (1+ gascity-remote-async-timeout)
                       31))))
    (gascity-agents--read-roster (lambda (d) (setq data d done t)) cached)
    (with-local-quit
      (while (and (not done) (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (gascity-agents--roster data)))

;;; Table

(defun gascity-agents--stalled-entry-p (entry)
  "Return non-nil when tabulated ENTRY is a stalled agent's row."
  (equal (gascity-tabulated--cell-string entry 3) "stalled"))

(defun gascity-agents--pinned-sorter (n &optional base)
  "Return a sort predicate for column N that keeps stalled rows first.
BASE compares two entries within a group (default: the column's text).
`tabulated-list' flips a descending sort by swapping the arguments, so
the pin reads the sort direction to stay on top either way (§7.3)."
  (let ((base (or base (lambda (a b) (string< (gascity-tabulated--cell-string a n)
                                              (gascity-tabulated--cell-string b n))))))
    (lambda (a b)
      (let ((sa (gascity-agents--stalled-entry-p a))
            (sb (gascity-agents--stalled-entry-p b)))
        (if (eq (not sa) (not sb))
            (funcall base a b)
          ;; Descending calls (pred b a): answer for the swapped pair.
          (if (cdr tabulated-list-sort-key) sb sa))))))

(defvar-local gascity-agents--filter '(:state "running")
  "The Agents table's filter plist (§7.3); state defaults to running.")

(defvar-local gascity-agents--data nil
  "Last good payload of each read: a plist keyed like `gascity-agents--loaders'.")

(defvar-local gascity-agents--errors nil
  "Errors of the reads of the last refresh: a plist keyed like the data.")

(defvar-local gascity-agents--generation 0
  "Refresh counter; a read of an older refresh is ignored.")

(defvar-local gascity-agents--by-object nil
  "Hash: a row's action object → its agent plist, for the detail window.")

(defun gascity-agents--detail-lines (id _entry)
  "Return the §5.4 detail of the agent row whose action object is ID.
Session id and tmux name, workdir, hooked bead, created, state and last
activity — from the rows in hand, no gc call."
  (let ((agent (and gascity-agents--by-object (gethash id gascity-agents--by-object))))
    (if (null agent)
        (list "No detail for this row")
      (append
       (list (concat (propertize (plist-get agent :name) 'face 'gascity-header)
                     "  " (gascity-agents--state-label agent)
                     (if (plist-get agent :active)
                         (concat " · last active "
                                 (gascity-ui-ago (plist-get agent :active)))
                       ""))
             "")
       (gascity-dashboard--agent-drawer agent)
       (and (plist-get agent :provider)
            (list (concat "provider " (plist-get agent :provider))))))))

(defun gascity-agents--render ()
  "Rebuild the table from `gascity-agents--data' (no gc call)."
  (let* ((now (float-time))
         (rows (gascity-agents--rows gascity-agents--data now))
         (shown (seq-filter (lambda (a) (gascity-agents--match-p a gascity-agents--filter))
                            rows))
         (_ (let ((table (make-hash-table :test 'eq)))
              (dolist (a rows) (puthash (plist-get a :object) a table))
              (setq gascity-agents--by-object table)))
         (errors (delq nil (cl-loop for (_k v) on gascity-agents--errors by #'cddr
                                    collect v))))
    (setq gascity-tabulated--filter-description
          (gascity-tabulated--format-filter gascity-agents--filter))
    (gascity-tabulated--init-paged
     (concat "Agents  " (gascity-agents--summary rows)
             (if errors (gascity-ui-partial-mark (string-join errors "\n")) ""))
     (mapcar (lambda (a) (gascity-agents--entry a now)) shown))))

(defconst gascity-agents--store-reads
  '((:status ("status"))
    (:sessions ("session" "list"))
    (:agents ("agent" "list"))
    (:work ("bd" "list" :work-stores) gascity-dashboard--read-work))
  "The store entries behind `gascity-agents--loaders': (KEY ARGS [LOADER]).")

(defvar-local gascity-agents--subs nil
  "This table's store subscriptions (see `gascity-agents--subscribe').")

(defun gascity-agents--subscribe ()
  "Repaint this table whenever one of its store entries gets new data.
Whoever caused the read — the live stream's invalidation, a completed
action, another view — the rows follow (dashboard-v3 §8.2).  Idempotent."
  (unless gascity-agents--subs
    (let ((buf (current-buffer)))
      (setq gascity-agents--subs
            (mapcar
             (lambda (spec)
               (let ((key (nth 0 spec)))
                 (gascity-store-subscribe
                  (nth 1 spec)
                  (lambda (snapshot)
                    (when (and (buffer-live-p buf)
                               (eq (plist-get snapshot :status) 'ready)
                               (not (plist-get snapshot :pending)))
                      (with-current-buffer buf
                        (unless (eq (plist-get gascity-agents--data key)
                                    (plist-get snapshot :data))
                          (setq gascity-agents--data
                                (plist-put gascity-agents--data key
                                           (plist-get snapshot :data)))
                          (gascity-agents--render)))))
                  :loader (nth 2 spec) :buffer buf)))
             gascity-agents--store-reads)))))

(defun gascity-agents-refresh (&optional cached)
  "Re-read the Agents table's payloads; the old rows stay until they land.
With CACHED (opening the view), fresh store entries answer at once."
  (interactive)
  (let ((gen (cl-incf gascity-agents--generation))
        (buf (current-buffer))
        (gascity-agents--force (not cached)))
    (setq gascity-agents--errors nil)
    (gascity-tabulated--set-loading)
    (pcase-dolist (`(,key . ,loader) gascity-agents--loaders)
      (funcall
       loader
       (lambda (data)
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (when (= gen gascity-agents--generation)
               (setq gascity-agents--data (plist-put gascity-agents--data key data))
               (gascity-agents--render)))))
       (lambda (err)
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (when (= gen gascity-agents--generation)
               (setq gascity-agents--errors
                     (plist-put gascity-agents--errors key
                                (format "gc %s: %s" (substring (symbol-name key) 1)
                                        (or (gascity-ui-first-line (format "%s" err))
                                            "failed"))))
               (gascity-agents--render)))))))))

(gascity-filter-define-choice gascity-agents-filter-state
  :state "state" '("running" "idle" "stopped" "stalled" "suspended" "all") "all")
(gascity-filter-define-choice gascity-agents-filter-rig
  :rig "rig" (cons "city" (mapcar #'gascity-rig-name
                                  (seq-remove #'gascity-rig-hq (gascity-rigs-cached)))))
(gascity-filter-define-choice gascity-agents-filter-provider
  :provider "provider"
  (delete-dups (delq nil (mapcar (lambda (a) (plist-get a :provider))
                                 (gascity-agents--rows gascity-agents--data
                                                       (float-time))))))
(gascity-filter-define-choice gascity-agents-filter-search
  :search "search" nil "")

(beads-define-prefix gascity-agents-filter ()
  "Filter the Agents table; each change applies at once (§7.3, §5.5)."
  ["Filter agents"
   ("-s" gascity-agents-filter-state)
   ("-r" gascity-agents-filter-rig)
   ("-p" gascity-agents-filter-provider)
   ("-q" gascity-agents-filter-search)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

(defvar-keymap gascity-agents-mode-map
  :doc "Keymap for `gascity-agents-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-agents-refresh
  "/"   #'gascity-agents-filter
  "RET" #'gascity-tmux-at-point
  "t"   #'gascity-tmux-at-point
  "i"   #'gascity-polecat-detail-at-point
  "d"   #'gascity-dired-at-point
  "v"   #'gascity-session-peek-at-point
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "R"   #'gascity-session-reset-at-point
  "U"   #'gascity-session-undrain-at-point
  "n"   #'next-line
  "p"   #'previous-line)

(define-derived-mode gascity-agents-mode tabulated-list-mode "GC-Agents"
  "Major mode for the Agents table (dashboard-v3 §7.3).
RET attaches the agent's terminal and `i' opens its detail; the §5.3
agent keys act on the row at point.

\\{gascity-agents-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        `[("" 1 nil)
          ("Agent" 34 ,(gascity-agents--pinned-sorter 1))
          ("Rig" 12 ,(gascity-agents--pinned-sorter 2))
          ("State" 9 ,(gascity-agents--pinned-sorter 3))
          ("Active" 9 ,(gascity-agents--pinned-sorter
                        4 (gascity-tabulated--time-sorter 4)))
          ("Bead" 10 ,(gascity-agents--pinned-sorter 5))
          ("Prov" 6 ,(gascity-agents--pinned-sorter 6))])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key nil)
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things)
  (setq-local gascity-tabulated-detail-function #'gascity-agents--detail-lines)
  (gascity-tabulated--install-filter
   'gascity-agents--filter
   (lambda () (gascity-agents--render)))
  ;; `x' resets to every state, not to nothing shown.
  (setq-local gascity-filter-reset-function
              (lambda () (setq gascity-agents--filter nil) (gascity-agents--render)))
  ;; The city's live event stream re-reads what this table shows (§8.2);
  ;; the store subscriptions repaint it.
  (gascity-tabulated-attach-live)
  (gascity-agents--subscribe))

(defun gascity-agents--city (dir)
  "Return the city name for the buffer names of a view opened in DIR."
  (or (gascity-context-city-name dir) "city"))

;;;###autoload
(defun gascity-agents ()
  "Show the city's agents in a table (`j a', dashboard-v3 §7.3)."
  (interactive)
  (let* ((dir (gascity-context-city-for-view (beads-prefix-invocation-directory)))
         (buf (gascity-view-get-buffer-create
               (format gascity-agents-buffer-name (gascity-agents--city dir)) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-agents-mode)
        (gascity-agents-mode)
        (gascity-agents--render))
      (gascity-agents-refresh 'cached))
    (pop-to-buffer buf)))

(provide 'gascity-agents)
;;; gascity-agents.el ends here
