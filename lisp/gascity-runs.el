;;; gascity-runs.el --- The Runs view: active, failed and past workflow runs -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The Runs view (plans/dashboard-v3 §7.6), `*gascity-runs: CITY*': the
;; city's graph.v2 workflow runs as two-line cards,
;;
;;   Runs  emacs-city   1 active · 0 waiting · 51 done · 11 failed
;;
;;   Active  1
;;     ⬣ be-52m5  build-basic                              beads.el   2h
;;        ◆⬣········  requirements   1/10   ● requirements-planner-1  be-bcb5
;;
;;   Failed  1 · last 24h
;;     ✕ be-bn2   build-basic                              beads.el   2h
;;        ◆◆◆◆◆◆◆✕◆◆  review         9/10   control_dispatch_error
;;
;; and, on `H', the history of closed runs, newest first, 20 per page
;; (`+' shows the next page).  `RET' opens a run's detail
;; (gascity-run.el), `b' its root bead in beads.el, `SPC' opens the
;; card's drawer (the full step ladder), `/' filters by rig, formula,
;; state and window (§5.5), each change applied at once.
;;
;; gc has no run summary (§11 gap 4): a run is derived from the bead
;; graph (§3.2).  The root is the bead with `gc.kind' workflow, every
;; step, iteration and control node carries `gc.root_bead_id' = the
;; root.  One composite store read collects both, from the city store
;; and every rig store (`gascity-runs-read-beads'); Runs and the run
;; detail share it.  The ladder is the cockpit's
;; (`gascity-dashboard--ladder'), so both views always agree.
;;
;; Everything the render computes is pure over the payloads in hand:
;; no gc, no TRAMP I/O (§8.3 R2).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'transient)
(require 'beads-prefix)
(require 'beads-thing)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-context)
(require 'gascity-remote)
(require 'gascity-store)
(require 'gascity-section)
(require 'gascity-dashboard)

(declare-function gascity-run-show "gascity-run")
(declare-function gascity-polecat-detail-at-point "gascity-session")
(declare-function gascity-session-peek-at-point "gascity-action")

;;; Options

(defcustom gascity-runs-history-page 20
  "Closed runs shown per history page of the Runs view (`H', `+')."
  :type 'integer
  :group 'gascity)

(defcustom gascity-runs-failed-window "24h"
  "How far back the Runs view's Failed section looks by default.
A duration such as \"24h\", \"7d\" or \"90m\"; the `/ -W' filter
overrides it."
  :type 'string
  :group 'gascity)

(defvar gascity-runs-filters nil
  "Runs view filters remembered per city: an alist CITY-KEY → plist.")

(defconst gascity-runs-buffer-name "*gascity-runs: %s*"
  "Format of the Runs view buffer name; %s is the city name.")

;;; Reads (§8.1): one composite store entry, shared with the run detail

(defconst gascity-runs--argvs
  '(("bd" "list" "--all" "-n" "0" "--brief"
     "--metadata-field" "gc.kind=workflow")
    ("bd" "list" "--all" "-n" "0" "--brief"
     "--has-metadata-key" "gc.root_bead_id"))
  "The per-store reads behind the Runs view: run roots, then graph beads.
Every status (`--all', closed runs are the history), no row limit, no
free text (`--brief').  Filtered to the run beads: an unfiltered
`--all' read of emacs-city's store is 3.4 MB of mostly wisps, these two
are 15 kB.")

(defconst gascity-runs-read-key '("bd" "list" :runs)
  "Store key of the composite run-beads read (kind `bd').")

(defun gascity-runs-read-beads (resolve reject)
  "Read every run bead of the city store and each rig store.
The loader of the `gascity-runs-read-key' entry: RESOLVE gets
\(:beads BEADS :errors ERRORS) with BEADS stamped with their store
\(`gascity-rig'), REJECT only when every store failed."
  (gascity-dashboard--read-work resolve reject gascity-runs--argvs))

(defun gascity-runs-use-beads (tick)
  "Return the shared run-beads store snapshot, from inside a component.
TICK is the component's refresh counter."
  (gascity-store-use gascity-runs-read-key :tick tick
                     :loader #'gascity-runs-read-beads))

;;; Model (pure)

(defun gascity-runs--meta (bead key)
  "Return metadata KEY (a symbol) of BEAD."
  (alist-get key (alist-get 'metadata bead)))

(defvar gascity-runs--index-cache (cons nil nil)
  "(BEADS . INDEX): the index of the last bead list, reused by identity.")

(defun gascity-runs-index (beads)
  "Return the run index of BEADS: a plist (:roots ROOTS :graphs HASH ...).
ROOTS are the run root beads, HASH maps a root id to its graph beads
\(every bead whose `gc.root_bead_id' names it), :owners maps a graph
bead id to its run's id, :drains maps a drain step id to its member
run roots (`gc.drain_control_id').  The last result is
reused while BEADS is the same list (every render of one payload), so
the grouping and ladders are computed once per read."
  (if (and beads (eq (car gascity-runs--index-cache) beads))
      (cdr gascity-runs--index-cache)
    (let ((graphs (make-hash-table :test 'equal))
          (owners (make-hash-table :test 'equal))
          (drains (make-hash-table :test 'equal))
          (seen (make-hash-table :test 'equal))
          (roots nil))
      (dolist (b beads)
        (let ((id (alist-get 'id b)))
          ;; The two reads never overlap, but a store answering twice
          ;; must not double a bead.
          (unless (gethash id seen)
            (puthash id t seen)
            (cond ((gascity-dashboard--run-root-p b)
                   (push b roots)
                   (let ((drain (gascity-runs--meta b 'gc.drain_control_id)))
                     (when drain (push b (gethash drain drains)))))
                  ((gascity-dashboard--root-of b)
                   (puthash id (gascity-dashboard--root-of b) owners)
                   (push b (gethash (gascity-dashboard--root-of b) graphs)))))))
      (let ((index (list :roots (nreverse roots) :graphs graphs :drains drains
                         :owners owners
                         :ladders (make-hash-table :test 'equal))))
        (setq gascity-runs--index-cache (cons beads index))
        index))))

(defun gascity-runs-graph (index id)
  "Return the graph beads of run ID in INDEX."
  (reverse (gethash id (plist-get index :graphs))))

(defun gascity-runs-parent-id (index root)
  "Return the id of the run ROOT drains for, or nil for a top-level run.
A member run's `gc.drain_control_id' names a drain step; the run that
step belongs to (its `gc.root_bead_id', found in INDEX's graphs) is the
parent.  Nil when ROOT is no member, or its drain step is not in INDEX."
  (let ((drain (gascity-runs--meta root 'gc.drain_control_id)))
    (and drain (gethash drain (plist-get index :owners)))))

(defun gascity-runs-ladder (index root)
  "Return the step ladder of ROOT (memoized in INDEX)."
  (let ((id (alist-get 'id root))
        (ladders (plist-get index :ladders)))
    (or (gethash id ladders)
        (puthash id (gascity-dashboard--ladder root (gascity-runs-graph index id)
                                               (plist-get index :drains))
                 ladders))))

(defun gascity-runs-last-activity (index root)
  "Return when run ROOT's live work was last touched, in seconds (0: never).
The latest `updated_at' of ROOT itself, its in-progress beads, and —
since a drain step stays open while its member runs work outside
ROOT's graph — every in-progress member run of an open drain step
\(INDEX's :drains, `gc.drain_control_id'), recursively.  The cockpit's
\"run idle\" rule reads it (§7.1), so a run whose drain members are busy
is never idle."
  (let ((drains (plist-get index :drains))
        (seen (make-hash-table :test 'equal)))
    (cl-labels ((time (b) (or (gascity-ui-parse-time (alist-get 'updated_at b)) 0))
                (run (root)
                  (let ((id (alist-get 'id root)))
                    (if (gethash id seen)
                        0
                      (puthash id t seen)
                      (apply #'max (time root)
                             (mapcar
                              (lambda (b)
                                (max (if (equal (alist-get 'status b) "in_progress")
                                         (time b)
                                       0)
                                     (if (equal (alist-get 'status b) "closed")
                                         0
                                       (apply #'max 0
                                              (mapcar (lambda (m)
                                                        (if (equal (alist-get 'status m)
                                                                   "in_progress")
                                                            (run m)
                                                          0))
                                                      (gethash (alist-get 'id b) drains))))))
                              (gascity-runs-graph index id)))))))
      (run root))))

(defun gascity-runs-state (root)
  "Return the state of run ROOT: `active' `waiting' `failed' or `done'."
  (let ((status (alist-get 'status root)))
    (cond ((equal status "in_progress") 'active)
          ((equal status "closed")
           (if (equal (gascity-runs--meta root 'gc.outcome) "fail") 'failed 'done))
          (t 'waiting))))

(defun gascity-runs--time (root)
  "Return the time a run ROOT is dated by: closed, else created."
  (if (equal (alist-get 'status root) "closed")
      (or (alist-get 'closed_at root) (alist-get 'updated_at root))
    (alist-get 'created_at root)))

(defun gascity-runs--failure (graph)
  "Return why a run failed, from its GRAPH beads, or nil.
The first failed bead's `gc.failure_reason', else its close reason."
  (let ((bead (seq-find (lambda (b) (equal (gascity-runs--meta b 'gc.outcome) "fail"))
                        graph)))
    (and bead
         (or (gascity-runs--meta bead 'gc.failure_reason)
             (let ((reason (alist-get 'close_reason bead)))
               (and (stringp reason) (not (string-empty-p reason)) reason))))))

(defun gascity-runs--worker-bead (graph)
  "Return the in-progress bead of GRAPH that names its live worker, or nil."
  (car (gascity-dashboard--one-per-worker
        (seq-filter (lambda (b)
                      (and (equal (alist-get 'status b) "in_progress")
                           (stringp (alist-get 'assignee b))))
                    graph))))

(defun gascity-runs-summary (index root)
  "Return the summary plist of run ROOT from INDEX.
Keys: :id :root :rig :formula :state :ladder :label :progress :time
:outcome :failure :worker-bead :parent (the run it drains for, or nil)."
  (let* ((id (alist-get 'id root))
         (graph (gascity-runs-graph index id))
         (ladder (gascity-runs-ladder index root))
         (label (gascity-dashboard--ladder-label ladder))
         (state (gascity-runs-state root)))
    (list :id id :root root
          :rig (alist-get 'gascity-rig root)
          :formula (or (gascity-runs--meta root 'gc.formula_name)
                       (alist-get 'title root) "")
          :state state :ladder ladder
          :label (car label) :progress (cdr label)
          :time (gascity-runs--time root)
          :outcome (gascity-runs--meta root 'gc.outcome)
          :failure (and (eq state 'failed) (gascity-runs--failure graph))
          :worker-bead (and (eq state 'active) (gascity-runs--worker-bead graph))
          :parent (gascity-runs-parent-id index root))))

(defun gascity-runs-window-seconds (window)
  "Return WINDOW (\"24h\", \"7d\", \"90m\", \"2w\") in seconds, or nil."
  (when (and (stringp window)
             (string-match "\\`\\([0-9]+\\)\\([mhdw]\\)\\'" window))
    (* (string-to-number (match-string 1 window))
       (pcase (match-string 2 window)
         ("m" 60) ("h" 3600) ("d" 86400) ("w" 604800)))))

(defun gascity-runs--within-p (run seconds now)
  "Return non-nil when RUN's time is at most SECONDS before NOW.
A nil SECONDS means no bound."
  (or (null seconds)
      (let ((time (gascity-ui-parse-time (plist-get run :time))))
        (and time (<= (- now time) seconds)))))

(defun gascity-runs--matches-p (run filters)
  "Return non-nil when RUN passes the rig and formula FILTERS."
  (let ((rig (plist-get filters :rig))
        (formula (plist-get filters :formula)))
    (and (or (null rig)
             (equal rig (or (plist-get run :rig) "city")))
         (or (null formula) (equal formula (plist-get run :formula))))))

(defun gascity-runs--newest-first (runs)
  "Return RUNS sorted by their time, newest first, then by id.
The id breaks ties (runs slung together share a second), so the order
does not depend on which store answered first."
  (sort (copy-sequence runs)
        (lambda (a b)
          (let ((ta (or (gascity-ui-parse-time (plist-get a :time)) 0))
                (tb (or (gascity-ui-parse-time (plist-get b :time)) 0)))
            (if (= ta tb)
                (string< (plist-get a :id) (plist-get b :id))
              (> ta tb))))))

(defun gascity-runs-partition (runs filters now)
  "Split RUNS (summaries) into the view's sections under FILTERS at NOW.
Returns a plist: :active (in progress, then waiting, newest first),
:failed (failed within the window: the `:window' filter, else
`gascity-runs-failed-window'), :closed (every closed run within the
`:window' filter, newest first: the history) and :counts, an alist of
state → count over RUNS after the rig and formula filters."
  (let* ((runs (seq-filter (lambda (r) (gascity-runs--matches-p r filters)) runs))
         (window (plist-get filters :window))
         (failed-secs (gascity-runs-window-seconds
                       (or window gascity-runs-failed-window)))
         (closed-secs (gascity-runs-window-seconds window))
         (of (lambda (&rest states)
               (seq-filter (lambda (r) (memq (plist-get r :state) states)) runs))))
    (list :active (append (gascity-runs--newest-first (funcall of 'active))
                          (gascity-runs--newest-first (funcall of 'waiting)))
          :failed (gascity-runs--newest-first
                   (seq-filter (lambda (r) (gascity-runs--within-p r failed-secs now))
                               (funcall of 'failed)))
          :closed (gascity-runs--newest-first
                   (seq-filter (lambda (r) (gascity-runs--within-p r closed-secs now))
                               (funcall of 'done 'failed)))
          :counts (mapcar (lambda (s) (cons s (length (funcall of s))))
                          '(active waiting done failed)))))

;;; Rendering (lines of propertized strings, like the cockpit)

(defun gascity-runs--state-glyph (state)
  "Return the glyph of a run STATE."
  (gascity-ui-glyph (pcase state
                      ('active 'active) ('failed 'failed)
                      ('done 'done) (_ 'pending))))

(defun gascity-runs-agent-name (name)
  "Return agent NAME for display: rig, pool template and `gc__' dropped.
An assignee without a live session is its tmux name
\(`gc__run-operator-ec-x688' parses to `gc__run-operator'), shown as
`run-operator'."
  (let ((short (gascity-dashboard--short-agent name)))
    (if (string-match "\\`gc__\\(.+\\)\\'" short) (match-string 1 short) short)))

(defun gascity-runs--time-cell (ts now)
  "Return TS relative to NOW, left-padded to 9 columns (no trailing pad).
The rig column before it then lines up whatever the time's width."
  (let ((time (gascity-ui-time ts now)))
    (concat (make-string (max 0 (- 9 (string-width time))) ?\s) time)))

(defun gascity-runs--worker (bead sessions socket)
  "Return (TEXT . AGENT) for the worker of in-progress BEAD.
TEXT is `● name  bead' (`○' when no live session), AGENT the action
`gascity-agent' of a live worker, else nil.  SESSIONS are the raw
`session list' rows, SOCKET the city's tmux socket."
  (let* ((session (gascity-dashboard--session-for-assignee
                   (alist-get 'assignee bead) sessions))
         (name (if session (alist-get 'agent_name session)
                 (or (car (gascity-dashboard--parse-assignee
                           (alist-get 'assignee bead)))
                     "unassigned"))))
    (cons (concat (gascity-ui-glyph (if session 'ok 'idle)) " "
                  (gascity-runs-agent-name name) "  "
                  (gascity-dashboard--dim (alist-get 'id bead)))
          (and session (gascity-dashboard--agent-object name session socket)))))

(defun gascity-runs--nest (runs)
  "Return RUNS as a list of (RUN . DEPTH), each member under its parent.
A member run (:parent) follows the run it drains for when that run is
in RUNS, recursively, one level deeper; one whose parent is not in RUNS
stays at depth 0 where it was."
  (let* ((ids (mapcar (lambda (r) (plist-get r :id)) runs))
         (nested-p (lambda (r) (let ((p (plist-get r :parent)))
                                 (and p (member p ids) (not (equal p (plist-get r :id)))))))
         (out nil))
    (cl-labels ((walk (run depth seen)
                  (push (cons run depth) out)
                  (dolist (m runs)
                    (when (and (equal (plist-get m :parent) (plist-get run :id))
                               (funcall nested-p m)
                               (not (member (plist-get m :id) seen)))
                      (walk m (1+ depth) (cons (plist-get run :id) seen))))))
      (dolist (r runs)
        (unless (funcall nested-p r) (walk r 0 nil))))
    (nreverse out)))

(defun gascity-runs--card (run ctx &optional depth)
  "Return the lines of RUN's two-line card (and its open drawer) in CTX.
DEPTH nests a member run's card under its parent's (`└', indented)."
  (let* ((depth (or depth 0))
         (id (plist-get run :id))
         (state (plist-get run :state))
         (now (plist-get ctx :now))
         (worker (and (plist-get run :worker-bead)
                      (gascity-runs--worker (plist-get run :worker-bead)
                                            (plist-get ctx :sessions)
                                            (plist-get ctx :socket))))
         (line1 (gascity-dashboard--row
                 (concat (if (zerop depth) "  "
                           (concat (make-string (* 4 depth) ?\s) "└ "))
                         (gascity-runs--state-glyph state) " "
                         (gascity-ui-fit id 9) " "
                         (gascity-ui-truncate (plist-get run :formula) 40))
                 (concat (gascity-dashboard--dim
                          (gascity-ui-fit (or (plist-get run :rig) "city") 10))
                         " " (gascity-runs--time-cell (plist-get run :time) now))))
         (tail (pcase state
                 ('active (if worker (car worker)
                            (gascity-dashboard--dim "no live worker")))
                 ('waiting (gascity-dashboard--dim "waiting"))
                 ('failed (gascity-dashboard--dim
                           (or (plist-get run :failure) "outcome: fail")))
                 (_ (gascity-dashboard--dim (or (plist-get run :outcome) "")))))
         (line2 (concat (make-string (+ 5 (* 4 depth)) ?\s)
                        (if (plist-get run :ladder)
                            (concat (gascity-dashboard--ladder-string
                                     (plist-get run :ladder))
                                    "  " (gascity-ui-fit (plist-get run :label) 14)
                                    " " (gascity-ui-fit (plist-get run :progress) 6)
                                    " ")
                          (gascity-dashboard--dim "no steps  "))
                        tail))
         (drawer-id (concat "run:" id)))
    (cons (apply #'gascity-dashboard--line (concat line1 "\n" line2)
                 'beads-thing (gascity-dashboard--thing
                               'row drawer-id
                               (lambda () (gascity-dashboard--flip :drawers drawer-id)))
                 'gascity-bead id
                 'gascity-run-rig (or (plist-get run :rig) "")
                 (and (cdr worker) (list 'gascity-agent (cdr worker))))
          (and (gascity-dashboard--drawer-open-p drawer-id)
               (gascity-dashboard--drawer
                (or (gascity-dashboard--run-drawer (plist-get run :ladder))
                    (list (gascity-dashboard--dim "no steps yet"))))))))

(defun gascity-runs--history-row (run ctx)
  "Return the lines of RUN's one-line history row (and drawer) in CTX."
  (let ((id (plist-get run :id)))
    (gascity-dashboard--object-row
     (concat "run:" id)
     (concat "  " (gascity-runs--state-glyph (plist-get run :state)) " "
             (gascity-ui-fit id 9) " "
             (gascity-ui-fit (plist-get run :formula) 13) " "
             (gascity-ui-fit (gascity-dashboard--ladder-string (plist-get run :ladder))
                             12)
             " " (gascity-ui-fit (plist-get run :progress) 6)
             " " (gascity-ui-fit (or (plist-get run :outcome) "") 8))
     (concat (gascity-dashboard--dim (gascity-ui-fit (or (plist-get run :rig) "city") 10))
             " " (gascity-runs--time-cell (plist-get run :time) (plist-get ctx :now)))
     (lambda () (gascity-dashboard--run-drawer (plist-get run :ladder)))
     'gascity-bead id
     'gascity-run-rig (or (plist-get run :rig) ""))))

(defun gascity-runs--count-line (counts)
  "Return `1 active · 0 waiting · 51 done · 11 failed' for COUNTS."
  (mapconcat (lambda (c) (format "%d %s" (cdr c) (car c))) counts " · "))

(defun gascity-runs--filter-summary (filters)
  "Return the dim description of the active FILTERS, or nil."
  (let ((parts (delq nil (mapcar (lambda (k)
                                   (let ((v (plist-get filters (car k))))
                                     (and v (format "%s %s" (cdr k) v))))
                                 '((:rig . "rig") (:formula . "formula")
                                   (:state . "state") (:window . "window"))))))
    (and parts (gascity-dashboard--dim (concat " filter  " (string-join parts " · ")
                                               "   x reset in /")))))

(defun gascity-runs-lines (ctx)
  "Return every Runs view line for render context CTX.
CTX keys: :city :now :filters :loads (:beads) :runs (summaries)
:sessions :socket :view (:collapsed :drawers :expanded :history
:pages)."
  (let* ((gascity-dashboard--view (plist-get ctx :view))
         (filters (plist-get ctx :filters))
         (view (plist-get ctx :view))
         (parts (gascity-runs-partition (plist-get ctx :runs) filters
                                        (plist-get ctx :now)))
         (state (plist-get filters :state))
         (show (lambda (s) (or (null state) (equal state s))))
         (history (or (plist-get view :history) (equal state "done")))
         (loaded (gascity-dashboard--data (plist-get (plist-get ctx :loads) :beads)))
         (title (gascity-dashboard--row
                 (concat (propertize "Runs" 'face 'gascity-header) "  "
                         (propertize (or (plist-get ctx :city) "") 'face 'gascity-city)
                         (if loaded
                             (concat "   " (gascity-dashboard--dim
                                            (gascity-runs--count-line
                                             (plist-get parts :counts))))
                           ""))
                 (gascity-dashboard--dim "H history  / filter")))
         (window (or (plist-get filters :window) gascity-runs-failed-window))
         (failed (plist-get parts :failed))
         (closed (plist-get parts :closed))
         (shown (* (max 1 (or (plist-get view :pages) 1)) gascity-runs-history-page))
         (lines (list title)))
    (when-let* ((f (gascity-runs--filter-summary filters)))
      (setq lines (append lines (list f))))
    (when (funcall show "active")
      (setq lines
            (append lines (list "")
                    (gascity-dashboard--section-lines
                     "active" "Active"
                     (let* ((nest (gascity-runs--nest (plist-get parts :active)))
                            (subs (seq-count (lambda (n) (> (cdr n) 0)) nest)))
                       (and nest
                            (concat (number-to-string (- (length nest) subs))
                                    (if (> subs 0)
                                        (format " · %d sub-run%s" subs
                                                (if (= subs 1) "" "s"))
                                      ""))))
                     (mapcan (lambda (n) (gascity-runs--card (car n) ctx (cdr n)))
                             (gascity-runs--nest (plist-get parts :active)))
                     ctx :loads '(:beads) :label "bd list"))))
    (when (funcall show "failed")
      (setq lines
            (append lines (list "")
                    (gascity-dashboard--section-lines
                     "failed" "Failed"
                     (concat (if failed (format "%d · " (length failed)) "none · ")
                             "last " window)
                     (mapcan (lambda (r) (gascity-runs--card r ctx)) failed)
                     ctx :loads '(:beads) :label "bd list"))))
    (when history
      (setq lines
            (append lines (list "")
                    (gascity-dashboard--section-lines
                     "history" "Done"
                     (and closed
                          (concat (number-to-string (length closed))
                                  (if (plist-get filters :window)
                                      (concat " · last " (plist-get filters :window))
                                    "")))
                     (append
                      (mapcan (lambda (r) (gascity-runs--history-row r ctx))
                              (seq-take closed shown))
                      (when (> (length closed) shown)
                        (list (gascity-dashboard--row
                               (gascity-dashboard--dim
                                (format "  … %d more" (- (length closed) shown)))
                               (gascity-dashboard--dim "+ more")
                               'gascity-runs-more t
                               'beads-thing (gascity-dashboard--thing
                                             'more "more:history"
                                             #'gascity-runs-more)))))
                     ctx :loads '(:beads) :label "bd list"))))
    lines))

;;; Component

(defun gascity-runs-context (loads filters view now &optional city)
  "Return the render context for LOADS (:beads :sessions) under FILTERS.
VIEW is the root view state, NOW the render time, CITY the city name."
  (let* ((beads (plist-get (gascity-dashboard--data (plist-get loads :beads)) :beads))
         (index (gascity-runs-index beads))
         (sessions (append (alist-get 'sessions (gascity-dashboard--data
                                                 (plist-get loads :sessions)))
                           nil)))
    (list :city city :now now :filters filters :view view :loads loads
          :index index
          :runs (mapcar (lambda (root) (gascity-runs-summary index root))
                        (plist-get index :roots))
          :sessions sessions
          :socket (and city (gascity-resolve-tmux-socket city 'no-probe)))))

(defvar-local gascity-runs--city nil
  "The city name of this Runs buffer.")

(defvar-local gascity-runs--formulas nil
  "The formulas of the runs last rendered here (the `-F' candidates).")

(vui-defcomponent gascity-runs-app (initial-filters)
  "Root component of the Runs view.
INITIAL-FILTERS seeds the filter state (remembered per city)."
  :state ((refresh-tick 0)
          (collapsed nil)
          (drawers nil)
          (expanded nil)
          (history nil)
          (pages 1)
          (filters (copy-sequence initial-filters)))
  :render
  (let* ((beads-res (gascity-runs-use-beads refresh-tick))
         (sessions-res (gascity-store-use '("session" "list") :tick refresh-tick))
         (last-beads (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         (loads (list :beads (gascity-ui-effective-load beads-res last-beads)
                      :sessions (gascity-ui-effective-load sessions-res last-sessions)))
         (ctx (gascity-runs-context
               loads filters
               (list :collapsed collapsed :drawers drawers :expanded expanded
                     :history history :pages pages)
               (float-time) gascity-runs--city)))
    (setq gascity-runs--formulas
          (delete-dups (mapcar (lambda (r) (plist-get r :formula))
                               (plist-get ctx :runs))))
    (vui-text (string-join (gascity-runs-lines ctx) "\n"))))

;;; Commands

(defun gascity-runs-refresh ()
  "Re-read the runs, keeping point, folds and drawers."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No Runs view to refresh here")))

(defun gascity-runs--run-at-point ()
  "Return (ID . RIG) of the run at point, or nil.
RIG is nil for a run of the city store."
  (let ((rig (get-text-property (point) 'gascity-run-rig))
        (id (get-text-property (point) 'gascity-bead)))
    (and rig id (cons id (and (not (string-empty-p rig)) rig)))))

(defun gascity-runs-store (rig)
  "Return the bead store directory of RIG (nil: the city store), or nil.
Answered from the rig memo only; nil when RIG is not memoized yet —
see `gascity-runs-call-with-store', which never blocks for it."
  (if (and rig (not (string-empty-p rig)))
      (gascity-beads--rig-store-cached rig)
    (gascity-beads--city-store)))

(defun gascity-runs-call-with-store (rig fn)
  "Call FN with the bead store directory of RIG (nil: the city store).
Never blocks: a cold rig memo is filled through the store first
\(`gascity-beads-call-with-rig-store')."
  (if (or (null rig) (string-empty-p rig))
      (funcall fn (gascity-beads--city-store))
    (gascity-beads-call-with-rig-store rig fn)))

(defun gascity-runs-root-bead ()
  "Show the root bead of the run at point in beads.el (`b')."
  (interactive)
  (let ((run (or (gascity-runs--run-at-point) (user-error "No run at point"))))
    (gascity-runs-call-with-store
     (cdr run) (lambda (store) (gascity-beads--show-in-store (car run) store)))))

(defun gascity-runs-activate ()
  "Open the run at point in the run detail (RET never folds, §5.4)."
  (interactive)
  (cond ((get-text-property (point) 'gascity-runs-more) (gascity-runs-more))
        ((gascity-runs--run-at-point)
         (let ((run (gascity-runs--run-at-point)))
           (gascity-run-show (car run) nil (cdr run))))
        ((get-text-property (point) 'gascity-section) nil)
        (t (user-error "Nothing to act on here"))))

(defun gascity-runs-history ()
  "Show or hide the history of closed runs (`H')."
  (interactive)
  (let ((on (not (gascity-dashboard--state :history))))
    (gascity-dashboard--set-state :history on)
    (when on
      (goto-char (point-min))
      (when (re-search-forward "^Done\\b" nil t)
        (beginning-of-line)))))

(defun gascity-runs-more ()
  "Show the next page of the history (`+')."
  (interactive)
  (let ((pos (point)))
    (unless (gascity-dashboard--state :history)
      (gascity-dashboard--set-state :history t))
    (gascity-dashboard--set-state :pages (1+ (or (gascity-dashboard--state :pages) 1)))
    (goto-char (min pos (point-max)))))

(defun gascity-runs-less ()
  "Show one history page fewer (`-'), down to one page."
  (interactive)
  (let ((pos (point))
        (pages (or (gascity-dashboard--state :pages) 1)))
    (if (<= pages 1)
        (message "Already at the default size")
      (gascity-dashboard--set-state :pages (1- pages))
      (goto-char (min pos (point-max))))))

(defun gascity-runs--agent-command (command)
  "Call COMMAND on the live worker at point, or explain there is none."
  (if (get-text-property (point) 'gascity-agent)
      (call-interactively command)
    (user-error "No live worker here")))

(defun gascity-runs-agent-detail ()
  "Open the detail of the live worker at point (`i')."
  (interactive)
  (gascity-runs--agent-command #'gascity-polecat-detail-at-point))

(defun gascity-runs-agent-peek ()
  "Peek at the live worker at point (`v')."
  (interactive)
  (gascity-runs--agent-command #'gascity-session-peek-at-point))

(defun gascity-runs-agent-tmux ()
  "Attach the live worker at point (the t key)."
  (interactive)
  (gascity-runs--agent-command #'gascity-tmux-at-point))

;;; Filter (`/', §5.5)

(defun gascity-runs--city-key ()
  "Return the key the filters of this city are remembered under."
  (or (gascity-context-city-root) default-directory))

(defun gascity-runs--set-filter (key value)
  "Set Runs filter KEY to VALUE, remember it for the city, re-render."
  (let ((filters (plist-put (copy-sequence (gascity-dashboard--state :filters))
                            key value)))
    (setf (alist-get (gascity-runs--city-key) gascity-runs-filters nil nil #'equal)
          filters)
    (gascity-dashboard--set-state :filters filters)))

(defun gascity-runs--install-filter ()
  "Wire the `/' menu builders (`gascity-filter-*') to the Runs state."
  (setq-local gascity-filter-get-function
              (lambda (key) (plist-get (gascity-dashboard--state :filters) key)))
  (setq-local gascity-filter-set-function #'gascity-runs--set-filter)
  (setq-local gascity-filter-reset-function
              (lambda ()
                (setf (alist-get (gascity-runs--city-key) gascity-runs-filters
                                 nil nil #'equal)
                      nil)
                (gascity-dashboard--set-state :filters nil))))

(gascity-filter-define-choice gascity-runs-filter-rig
  :rig "rig" (cons "city" (gascity-dashboard--rig-store-names (gascity-rigs-cached))))
(gascity-filter-define-choice gascity-runs-filter-formula
  :formula "formula" gascity-runs--formulas)
(gascity-filter-define-choice gascity-runs-filter-state
  :state "state" '("active" "failed" "done"))
(gascity-filter-define-choice gascity-runs-filter-window
  :window "window" '("1h" "24h" "7d" "30d") "failed 24h, done all")

(beads-define-prefix gascity-runs-filter ()
  "Filter the Runs view; each change applies at once (§5.5)."
  [:description (lambda () (concat "Filter runs  " (or gascity-runs--city "")))
   ["Scope"
    ("-r" gascity-runs-filter-rig)
    ("-F" gascity-runs-filter-formula)]
   ["State"
    ("-s" gascity-runs-filter-state)
    ("-W" gascity-runs-filter-window)]]
  [("x" gascity-filter-reset)])

;;; Mode

(defun gascity-runs-header-line (title &optional city)
  "Return a view header line: CITY, `@host' when remote, TITLE, live, hints.
The shared `gascity-ui-header-line'.  Pure (§8.3 R2)."
  (gascity-ui-header-line title city))

(defvar-keymap gascity-runs-mode-map
  :doc "Keymap for `gascity-runs-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-runs-refresh
  "RET" #'gascity-runs-activate
  "b"   #'gascity-runs-root-bead
  "H"   #'gascity-runs-history
  "+"   #'gascity-runs-more
  "-"   #'gascity-runs-less
  "/"   #'gascity-runs-filter
  "i"   #'gascity-runs-agent-detail
  "v"   #'gascity-runs-agent-peek
  "t"   #'gascity-runs-agent-tmux)

(define-derived-mode gascity-runs-mode gascity-section-mode "GC-Runs"
  "Major mode for the Runs view (dashboard-v3 §7.6).

TAB/S-TAB move between runs, SPC opens a run's step ladder, RET
opens its detail, `b' its root bead, `H' the history, `/' filters.

\\{gascity-runs-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              '(:eval (gascity-runs-header-line "Runs" gascity-runs--city)))
  (gascity-runs--install-filter))

;;;###autoload
(defun gascity-runs ()
  "Show the city's workflow runs: active, failed, and on `H' the history.
The buffer is keyed to the city (host-qualified name, pinned
`default-directory'); `j r' reaches it from every view."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
         (city (or (gascity-context-city-name dir) "city"))
         (buf (gascity-view-get-buffer-create
               (format gascity-runs-buffer-name city) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-runs-mode)
        (gascity-runs-mode))
      (setq gascity-runs--city city))
    (unless (gascity-section-refresh-instance buf)
      (let ((filters (with-current-buffer buf
                       (alist-get (gascity-runs--city-key)
                                  gascity-runs-filters nil nil #'equal))))
        (save-window-excursion
          (vui-mount (vui-component 'gascity-runs-app :initial-filters filters)
                     (buffer-name buf)))))
    (pop-to-buffer buf)))

(provide 'gascity-runs)
;;; gascity-runs.el ends here
