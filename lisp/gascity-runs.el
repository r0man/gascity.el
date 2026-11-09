;;; gascity-runs.el --- The Runs view: active, failed and past workflow runs -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The Runs view (plans/dashboard-v3 §7.6), `*gascity-runs: CITY*': the
;; city's graph.v2 workflow runs as two-line cards,
;;
;;   Runs  emacs-city   1 active · 0 waiting · 51 done · 11 failed (all time)
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
;; (`+' shows the next page), each with a dim stage/step/failure/worker
;; facts line.  `RET' opens a run's detail
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
(require 'gascity-run-stage)

(declare-function gascity-run-show "gascity-run")
(declare-function gascity-dashboard--step-ref "gascity-dashboard")
(declare-function gascity-run-tree "gascity-run")
(declare-function gascity-run-annotate "gascity-run")
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

(defalias 'gascity-runs--step-ref #'gascity-dashboard--step-ref)

(defun gascity-runs--wire-number (value)
  "Return VALUE (a number or a gc wire string) as a number, or nil.
gc emits `gc.drain_index'/`gc.drain_count' as strings; an absent or
non-numeric value is nil, and nil sorts last."
  (cond ((numberp value) value)
        ((and (stringp value) (string-match-p "\\`[0-9]+\\'" value))
         (string-to-number value))
        (t nil)))

(defun gascity-runs--deliverable-less-p (a b)
  "Return non-nil when deliverable A sorts before deliverable B.
`gc.drain_index' first (nil last), then the business id, then the
member id, so a shuffled read always yields the same order."
  (let ((ia (plist-get a :index))
        (ib (plist-get b :index)))
    (cond ((and ia ib (/= ia ib)) (< ia ib))
          ((and ia (null ib)) t)
          ((and (null ia) ib) nil)
          (t (let ((ba (or (plist-get a :business-id) ""))
                   (bb (or (plist-get b :business-id) "")))
               (if (equal ba bb)
                   (string< (or (plist-get a :member-id) "")
                            (or (plist-get b :member-id) ""))
                 (string< ba bb)))))))

(defun gascity-runs-index (beads)
  "Return the run index of BEADS: a plist (:roots ROOTS :graphs HASH ...).
ROOTS are the run root beads, HASH maps a root id to its graph beads
\(every bead whose `gc.root_bead_id' names it), :owners maps a graph
bead id to its run's id, :drains maps a drain step id to its member
run roots (`gc.drain_control_id'), and :beads maps every bead id in
BEADS to its bead (first write wins).

:deliverables maps a drain step id to its member runs, joined in the
same single pass to the business bead: one plist (:business-id ID
:member-id ID :member ROOT :index N :count N) per member.  ID is the
member root's `gc.drain_member_id' (kept even when the payload has no
such bead), N its `gc.drain_index'/`gc.drain_count' parsed from gc's
string wire values (nil, sorting last, when absent or non-numeric).
The list is ordered by index, then business id, then member id, so the
cached index never depends on the read order.

The last result is reused while BEADS is the same list (every render
of one payload), so the grouping and ladders are computed once per
read."
  (if (and beads (eq (car gascity-runs--index-cache) beads))
      (cdr gascity-runs--index-cache)
    (let ((graphs (make-hash-table :test 'equal))
          (owners (make-hash-table :test 'equal))
          (drains (make-hash-table :test 'equal))
          (deliverables (make-hash-table :test 'equal))
          (table (make-hash-table :test 'equal))
          (seen (make-hash-table :test 'equal))
          (roots nil))
      (dolist (b beads)
        (let ((id (alist-get 'id b)))
          ;; The two reads never overlap, but a store answering twice
          ;; must not double a bead.
          (unless (gethash id seen)
            (puthash id t seen)
            (puthash id b table)
            (cond ((gascity-dashboard--run-root-p b)
                   (push b roots)
                   (let ((drain (gascity-runs--meta b 'gc.drain_control_id)))
                     (when drain
                       (push b (gethash drain drains))
                       (push (list :business-id
                                   (gascity-runs--meta b 'gc.drain_member_id)
                                   :member-id id
                                   :member b
                                   :index (gascity-runs--wire-number
                                           (gascity-runs--meta b 'gc.drain_index))
                                   :count (gascity-runs--wire-number
                                           (gascity-runs--meta b 'gc.drain_count)))
                             (gethash drain deliverables)))))
                  ((gascity-dashboard--root-of b)
                   (puthash id (gascity-dashboard--root-of b) owners)
                   (push b (gethash (gascity-dashboard--root-of b) graphs)))))))
      (dolist (drain (hash-table-keys deliverables))
        (puthash drain
                 (sort (gethash drain deliverables)
                       #'gascity-runs--deliverable-less-p)
                 deliverables))
      (let ((index (list :roots (nreverse roots) :graphs graphs :drains drains
                         :owners owners :beads table
                         :deliverables deliverables
                         :ladders (make-hash-table :test 'equal)
                         :trees (make-hash-table :test 'equal))))
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

(defun gascity-runs-bead (index id)
  "Return the bead ID in INDEX, or nil when the payload has none."
  (gethash id (plist-get index :beads)))

(defun gascity-runs-deliverables (index root)
  "Return ROOT's drain steps that have deliverables in INDEX.
One plist (:step STEP :members MEMBERS) per ladder step whose members
are non-nil, in ladder order; MEMBERS are the ordered deliverables of
`gascity-runs-index'.  Nil for a formula with no drain and for an
inline drain (a drain step with no member roots), so a caller never
invents a per-item row."
  (let ((deliverables (plist-get index :deliverables))
        (steps nil))
    (dolist (step (gascity-runs-ladder index root))
      (let ((members (gethash (plist-get step :id) deliverables)))
        (when members
          (push (list :step step :members members) steps))))
    (nreverse steps)))

(defun gascity-runs--tree (index root)
  "Return ROOT's annotated step tree in INDEX (memoized in INDEX).
The tree is `gascity-run-tree' with every node stamped with its ladder
state by `gascity-run-annotate', so a work-unit row's :node carries the
same state as the ladder."
  (let* ((id (alist-get 'id root))
         (trees (plist-get index :trees)))
    (or (gethash id trees)
        (puthash id (let ((graph (gascity-runs-graph index id)))
                      (gascity-run-annotate
                       (gascity-run-tree root graph) root graph
                       (gascity-runs-ladder index root)))
                 trees))))

(defun gascity-runs--unit-state (row)
  "Return the state of work-unit ROW: its member run's, else its step's."
  (if (eq (plist-get row :unit-kind) :deliverable)
      (gascity-runs-state (plist-get row :member))
    (plist-get (plist-get row :step) :state)))

(defun gascity-runs-work-units (index root)
  "Return ROOT's work-unit spine in INDEX, in ladder order.
One row per work unit: a `:drain' row for a step with member roots,
followed by one `:deliverable' row per member, and a `:work' row for a
drain without members (an inline drain) and for every other top-level
step.  A row is a plist (:unit-kind :step :node :business
:business-id :member :member-id :index :count :order): :step is the
ladder entry, :node its annotated tree node (nil when the tree has
none), :business the bead the member's `gc.drain_member_id' names (nil
when the payload has none, with the id kept), :member the member run
root, and :order the row's 0-based position here.  No row is invented:
an inline drain is one :work row and a formula with no drain yields
only :work rows."
  (let ((nodes (make-hash-table :test 'equal))
        (units nil)
        (order 0))
    (dolist (node (gascity-runs--tree index root))
      (puthash (alist-get 'id (plist-get node :bead)) node nodes))
    (dolist (step (gascity-runs-ladder index root))
      (let* ((id (plist-get step :id))
             (node (gethash id nodes))
             (members (gethash id (plist-get index :deliverables))))
        (if members
            (progn
              (push (list :unit-kind :drain :step step :node node
                          :business nil :business-id nil
                          :member nil :member-id nil
                          :index nil :count nil :order order)
                    units)
              (setq order (1+ order))
              (dolist (member members)
                (push (list :unit-kind :deliverable :step step :node node
                            :business (gascity-runs-bead
                                       index (plist-get member :business-id))
                            :business-id (plist-get member :business-id)
                            :member (plist-get member :member)
                            :member-id (plist-get member :member-id)
                            :index (plist-get member :index)
                            :count (plist-get member :count)
                            :order order)
                      units)
                (setq order (1+ order))))
          (push (list :unit-kind :work :step step :node node
                      :business nil :business-id nil
                      :member nil :member-id nil
                      :index nil :count nil :order order)
                units)
          (setq order (1+ order)))))
    (nreverse units)))

(defun gascity-runs-unit-counts (index root)
  "Return the labeled counts of ROOT in INDEX.
A plist (:steps (DONE . TOTAL) :deliverables (DONE . TOTAL) :beads N
:in-flight N :failed N).  :steps counts the ladder's done steps,
:deliverables the member runs whose run is done, :beads the beads in
ROOT's graph, and :in-flight/:failed the work units (never the drain
headers, so a member is not counted twice) whose state is active or
failed.  The totals stay separate: a caller renders a word next to
each, never one combined ratio."
  (let* ((ladder (gascity-runs-ladder index root))
         (units (seq-remove (lambda (r) (eq (plist-get r :unit-kind) :drain))
                            (gascity-runs-work-units index root)))
         (deliverables (seq-filter (lambda (r)
                                     (eq (plist-get r :unit-kind) :deliverable))
                                   units)))
    (list :steps (cons (seq-count (lambda (s) (eq (plist-get s :state) 'done))
                                  ladder)
                       (length ladder))
          :deliverables (cons (seq-count (lambda (r)
                                          (eq (gascity-runs--unit-state r) 'done))
                                        deliverables)
                              (length deliverables))
          :beads (length (gascity-runs-graph index (alist-get 'id root)))
          :in-flight (seq-count (lambda (r)
                                  (eq (gascity-runs--unit-state r) 'active))
                                units)
          :failed (seq-count (lambda (r)
                               (eq (gascity-runs--unit-state r) 'failed))
                             units))))

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

(defun gascity-runs--close-reason (bead)
  "Return BEAD's non-empty close reason, or nil.
`gc events' payload beads keep it in `metadata', while the `gc bd list'
shape puts it at the bead's top level; prefer the event shape and keep
the top-level value as the fallback (review R2)."
  (let ((reason (or (gascity-runs--meta bead 'close_reason)
                    (alist-get 'close_reason bead))))
    (and (stringp reason) (not (string-empty-p reason)) reason)))

(defun gascity-runs--failure (graph)
  "Return why a run failed, from its GRAPH beads, or nil.
The first failed bead's `gc.failure_reason', else its close reason."
  (let ((bead (seq-find (lambda (b) (equal (gascity-runs--meta b 'gc.outcome) "fail"))
                        graph)))
    (and bead
         (or (gascity-runs--meta bead 'gc.failure_reason)
             (gascity-runs--close-reason bead)))))

(defun gascity-runs--failure-info (beads)
  "Return (CLASS . REASON) from the first of BEADS that names one.
CLASS is `gc.failure_class', REASON `gc.failure_reason' else the close
reason.  Either may be nil; nil when no bead names either."
  (let ((class nil)
        (reason nil))
    (dolist (b beads)
      (setq class (or class (gascity-runs--meta b 'gc.failure_class)))
      (setq reason
            (or reason
                (gascity-runs--meta b 'gc.failure_reason)
                (gascity-runs--close-reason b))))
    (and (or class reason) (cons class reason))))

(defun gascity-runs--failed-beads-of-run (index root)
  "Return the failed beads of run ROOT in INDEX.
A member run's failure class usually lives on its failed step, not its
root, so the graph comes first; ROOT itself is appended when it failed."
  (append
   (seq-filter (lambda (b) (equal (gascity-runs--meta b 'gc.outcome) "fail"))
               (gascity-runs-graph index (alist-get 'id root)))
   (and (equal (gascity-runs--meta root 'gc.outcome) "fail") (list root))))

(defun gascity-runs--step-failure (step graph index formula)
  "Return the failure plist of ladder STEP in GRAPH/INDEX, or nil.
FORMULA names the run's formula, used to read step paths.  A failed
member run of the step's drain (`gc.drain_control_id'), or a failed
bead beneath the step's path, marks it.  The class and reason come
from the first failed bead that names them."
  (let* ((id (plist-get step :id))
         (name (plist-get step :name))
         (bead (seq-find (lambda (b) (equal (alist-get 'id b) id)) graph))
         (members (gethash id (plist-get index :drains)))
         (member (seq-find (lambda (m) (eq (gascity-runs-state m) 'failed))
                           members))
         (member-beads (and member
                            (gascity-runs--failed-beads-of-run index member)))
         (path-beads
          ;; A done or running step with a failed bead beneath it was
          ;; retried: only a failed or pending step is judged on its
          ;; nested beads (a drain member is judged separately).
          (when (memq (plist-get step :state) '(failed pending))
            (seq-filter
             (lambda (b)
               (let ((path (gascity-dashboard--step-path b formula)))
                 (and path
                      (equal (gascity-runs--meta b 'gc.outcome) "fail")
                      (or (equal path name)
                          (string-prefix-p (concat name ".") path)))))
             graph))))
    (when (or member-beads path-beads (eq (plist-get step :state) 'failed))
      (let* ((candidates (append member-beads path-beads
                                 (and bead (list bead))))
             (info (gascity-runs--failure-info candidates))
             (ref (or (and bead (gascity-runs--meta bead 'gc.step_ref))
                      (and candidates
                           (gascity-runs--meta (car candidates) 'gc.step_ref))
                      name))
             (member-ref (and candidates
                              (gascity-runs--meta (car candidates) 'gc.step_ref))))
        (list :name name
              :id id
              :ref ref
              :member-ref (and member-ref (not (equal member-ref ref)) member-ref)
              :class (car info)
              :reason (cdr info)
              :member (and member (alist-get 'id member)))))))

(defun gascity-runs--nested-failure (ladder graph formula)
  "Return the failure plist of a failed bead beneath a pending step.
LADDER is the run's step ladder, GRAPH its beads, FORMULA its formula
name.  A step that is done or running is left alone: a retried loop in
a live run is not a failure (ga-g092a)."
  (seq-some
   (lambda (b)
     (let* ((path (gascity-dashboard--step-path b formula))
            (top (and path (car (split-string path "\\."))))
            (step (and top
                       (seq-find (lambda (s) (equal (plist-get s :name) top))
                                 ladder))))
       (when (and step (not (memq (plist-get step :state) '(done active))))
         (let* ((step-bead (seq-find (lambda (x)
                                       (equal (alist-get 'id x)
                                              (plist-get step :id)))
                                     graph))
                (info (gascity-runs--failure-info (list b))))
           (list :name (plist-get step :name)
                 :id (plist-get step :id)
                 :ref (or (and step-bead
                               (gascity-runs--meta step-bead 'gc.step_ref))
                          (and formula (concat formula "." (plist-get step :name)))
                          path)
                 :member-ref (or (gascity-runs--meta b 'gc.step_ref) path)
                 :class (car info)
                 :reason (cdr info))))))
   (seq-filter (lambda (b) (equal (gascity-runs--meta b 'gc.outcome) "fail"))
               graph)))

(defun gascity-runs-failed-step (index root)
  "Return the failed step of run ROOT in INDEX, or nil.
A plist (:name :id :ref :member-ref :class :reason :member).  The ladder is
authoritative: its first `failed' step.  An open drain step stays
`active' while any member runs, so a failed member run
\(`gc.drain_control_id') marks its drain step failed too.  In a run
still in progress a failed bead beneath a step that is neither done nor
running marks that step failed; a retried loop does not."
  (let* ((graph (gascity-runs-graph index (alist-get 'id root)))
         (ladder (gascity-runs-ladder index root))
         (formula (gascity-runs--meta root 'gc.formula_name))
         (found nil))
    (dolist (step ladder)
      (unless found
        (setq found (gascity-runs--step-failure step graph index formula))))
    (or found
        (and (eq (gascity-runs-state root) 'active)
             (gascity-runs--nested-failure ladder graph formula)))))

(defun gascity-runs--failed-step-badge (step)
  "Return the badge text of failed STEP: `✕ REF  CLASS' (or reason)."
  (let ((ref (or (plist-get step :ref) (plist-get step :name) "?"))
        (detail (or (plist-get step :class) (plist-get step :reason))))
    (concat (gascity-ui-glyph 'failed) " "
            (gascity-ui-truncate ref 28)
            (if detail
                (concat "  " (gascity-dashboard--dim
                              (gascity-ui-truncate detail 40)))
              ""))))

(defun gascity-runs--worker-bead (graph)
  "Return the in-progress bead of GRAPH that names its live worker, or nil."
  (car (gascity-dashboard--one-per-worker
        (seq-filter (lambda (b)
                      (and (equal (alist-get 'status b) "in_progress")
                           (stringp (alist-get 'assignee b))))
                    graph))))

(defun gascity-runs-member-roots (index root)
  "Return the member run roots of ROOT's drain steps in INDEX.
A member root names the drain step in `gc.drain_control_id'; INDEX's
:drains maps that step id back to the runs which drain through it.
The roots keep the ladder order of their steps, and each step's
members keep the order they were read in."
  (let ((drains (plist-get index :drains))
        (members nil))
    (dolist (step (gascity-runs-ladder index root))
      (setq members
            (append members
                    (reverse (gethash (plist-get step :id) drains)))))
    members))

(defun gascity-runs--live-worker (index root seen)
  "Return the live worker of ROOT or of a run nested in its drain steps.
INDEX is the run index; a plist (:id ID :root ROOT-BEAD :worker-bead
BEAD) is returned, where ID is the run the worker belongs to, so a
parent can report work that lives in a sub-run.  SEEN lists the run ids
already visited, so a drain cycle terminates.  Nil when neither ROOT
nor any nested member run has an in-progress bead with an assignee."
  (let ((id (alist-get 'id root)))
    (when (and (memq (gascity-runs-state root) '(active waiting))
               (not (member id seen)))
      (let ((bead (gascity-runs--worker-bead
                   (gascity-runs-graph index id))))
        (or (and bead (list :id id :root root :worker-bead bead))
            (seq-some (lambda (member)
                        (gascity-runs--live-worker
                         index member (cons id seen)))
                      (gascity-runs-member-roots index root)))))))

(defun gascity-runs--live-subrun (index root)
  "Return the nested run under ROOT whose live worker ROOT should report.
INDEX is the run index.  Used only when ROOT's own graph has no
in-progress worker: the parent card then names the member run's worker
instead of reading `no live worker' while a nested card shows that very
worker (ec-elkm5.5)."
  (seq-some (lambda (member)
              (gascity-runs--live-worker
               index member (list (alist-get 'id root))))
            (gascity-runs-member-roots index root)))

(defun gascity-runs-summary (index root)
  "Return the summary plist of run ROOT from INDEX.
Keys: :id :root :rig :formula :state :ladder :label :progress :time
:outcome :failure :failed-step :worker-bead :live-subrun :parent (the
run it drains for, or nil).  :failed-step is set for an active run
whose ladder has a failed step (ga-g092a); a failed run's reason is
:failure.  :worker-bead is ROOT's own live worker; when it has none but
a drain member run does, :live-subrun names that member (with its
:worker-bead), so a parent never reads as workerless while a nested run
is live (ec-elkm5.5)."
  (let* ((id (alist-get 'id root))
         (graph (gascity-runs-graph index id))
         (ladder (gascity-runs-ladder index root))
         (label (gascity-dashboard--ladder-label ladder))
         (state (gascity-runs-state root))
         (worker (and (eq state 'active) (gascity-runs--worker-bead graph))))
    (list :id id :root root
          :rig (alist-get 'gascity-rig root)
          :formula (or (gascity-runs--meta root 'gc.formula_name)
                       (alist-get 'title root) "")
          :state state :ladder ladder
          :label (car label) :progress (cdr label)
          :time (gascity-runs--time root)
          :outcome (gascity-runs--meta root 'gc.outcome)
          :failure (and (eq state 'failed) (gascity-runs--failure graph))
          :failed-step (and (eq state 'active)
                            (gascity-runs-failed-step index root))
          :worker-bead worker
          :live-subrun (and (eq state 'active) (null worker)
                            (gascity-runs--live-subrun index root))
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
Returns a plist.  :in-progress is the live runs, newest first;
:waiting is open but not in progress, newest first; :active is the
two combined; :failed is failed within the window (the `:window'
filter, else `gascity-runs-failed-window'); :closed is every closed
run within the `:window' filter, newest first (the history); and
:counts is an alist of state → count over RUNS after the rig and
formula filters."
  (let* ((runs (seq-filter (lambda (r) (gascity-runs--matches-p r filters)) runs))
         (window (plist-get filters :window))
         (failed-secs (gascity-runs-window-seconds
                       (or window gascity-runs-failed-window)))
         (closed-secs (gascity-runs-window-seconds window))
         (of (lambda (&rest states)
               (seq-filter (lambda (r) (memq (plist-get r :state) states)) runs))))
    (list :in-progress (gascity-runs--newest-first (funcall of 'active))
          :waiting (gascity-runs--newest-first (funcall of 'waiting))
          :active (append (gascity-runs--newest-first (funcall of 'active))
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

(defun gascity-runs--worker-facts (bead sessions socket)
  "Return the live-worker facts of in-progress BEAD.
A plist: :session (the raw live session row or nil), :display (the
session's short agent name, else the assignee's parsed role),
:agent (the action `gascity-agent' of a live worker, else nil) and
:last-active (the session's last-active stamp).
SESSIONS are the raw `session list' rows, SOCKET the tmux socket.
Both the Runs card and the run inspector read these facts, so the two
views join the same session and tell the same story as the cockpit's
Needs-you rule (ga-o7vtw)."
  (let* ((session (gascity-dashboard--session-for-assignee
                   (alist-get 'assignee bead) sessions))
         (name (if session (alist-get 'agent_name session)
                 (or (car (gascity-dashboard--parse-assignee
                           (alist-get 'assignee bead)))
                     "unassigned"))))
    (list :session session
          :display (gascity-runs-agent-name name)
          :agent (and session (gascity-dashboard--agent-object
                               name session socket))
          :last-active (and session (alist-get 'last_active session)))))

(defun gascity-runs--worker (bead sessions socket)
  "Return (TEXT . AGENT) for the worker of in-progress BEAD.
TEXT is `● name  bead' (`○' when no live session), AGENT the action
`gascity-agent' of a live worker, else nil.  SESSIONS are the raw
`session list' rows, SOCKET the city's tmux socket."
  (let* ((facts (gascity-runs--worker-facts bead sessions socket))
         (session (plist-get facts :session)))
    (cons (concat (gascity-ui-glyph (if session 'ok 'idle)) " "
                  (plist-get facts :display) "  "
                  (gascity-dashboard--dim (alist-get 'id bead)))
          (plist-get facts :agent))))

(defun gascity-runs--run-worker (run ctx)
  "Return (TEXT . AGENT) for RUN's live worker in CTX, or nil.
RUN's own in-progress worker wins; otherwise the live worker of a drain
member run is reported as `● name  SUB-RUN', so a parent card never
reads as workerless while its nested card shows a live worker
\(ec-elkm5.5).  CTX supplies the `session list' rows and the socket."
  (let ((sessions (plist-get ctx :sessions))
        (socket (plist-get ctx :socket)))
    (cond
     ((plist-get run :worker-bead)
      (gascity-runs--worker (plist-get run :worker-bead) sessions socket))
     ((plist-get run :live-subrun)
      (let* ((sub (plist-get run :live-subrun))
             (facts (gascity-runs--worker-facts
                     (plist-get sub :worker-bead) sessions socket))
             (session (plist-get facts :session)))
        (cons (concat (gascity-ui-glyph (if session 'ok 'idle)) " "
                      (plist-get facts :display) "  "
                      (gascity-dashboard--dim (plist-get sub :id)))
              (plist-get facts :agent)))))))

(defun gascity-runs--facts (runs ctx)
  "Return the compared facts of RUNS in CTX: an alist RUN-ID → plist.
The plist holds :state, :progress, :worker (the rendered worker cell,
or nil) and :failed-step (the failed step's class, or nil).  Pure;
run-view-v3 §D fingerprints the Runs cards with it."
  (mapcar
   (lambda (run)
     (let ((worker (gascity-runs--run-worker run ctx)))
       (cons (plist-get run :id)
             (list :state (plist-get run :state)
                   :progress (plist-get run :progress)
                   :worker (and worker (car worker))
                   :failed-step (plist-get (plist-get run :failed-step) :class)))))
   runs))

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
         (changed (and (plist-get ctx :deltas)
                       (gethash id (plist-get ctx :deltas))))
         (worker (gascity-runs--run-worker run ctx))
         (glyph (gascity-runs--state-glyph state))
         (progress (gascity-ui-fit (plist-get run :progress) 6))
         (line1 (gascity-dashboard--row
                 (concat (if (zerop depth) "  "
                           (concat (make-string (* 4 depth) ?\s) "└ "))
                         (if changed (gascity-ui-changed glyph) glyph) " "
                         (gascity-ui-fit id 9) " "
                         (gascity-ui-truncate (plist-get run :formula) 40))
                 (concat (gascity-dashboard--dim
                          (gascity-ui-fit (or (plist-get run :rig) "city") 10))
                         " " (gascity-runs--time-cell (plist-get run :time) now))))
         (tail (pcase state
                 ('active (if-let* ((failed (plist-get run :failed-step)))
                             (gascity-runs--failed-step-badge failed)
                           (cond ((not worker)
                                  (gascity-dashboard--dim "no live worker"))
                                 (changed (gascity-ui-changed (car worker)))
                                 (t (car worker)))))
                 ('waiting (gascity-dashboard--dim "waiting"))
                 ('failed (gascity-dashboard--dim
                           (or (plist-get run :failure) "outcome: fail")))
                 (_ (gascity-dashboard--dim (or (plist-get run :outcome) "")))))
         (prefix (concat (make-string (+ 5 (* 4 depth)) ?\s)
                         (if (plist-get run :ladder)
                             (concat (gascity-dashboard--ladder-string
                                      (plist-get run :ladder))
                                     "  " (gascity-ui-fit (plist-get run :label) 14)
                                     " " (if changed (gascity-ui-changed progress)
                                             progress)
                                     " ")
                           (gascity-dashboard--dim "no steps  "))))
         ;; Only the Failed card's failure-reason tail is unbounded; fit it
         ;; against the width the prefix leaves.  A deep member card's
         ;; prefix can already fill the view, so clamp the budget at 0.
         (line2 (concat prefix
                        (if (eq state 'failed)
                            (gascity-ui-truncate
                             tail (max 0 (- gascity-dashboard--width
                                            (string-width prefix))))
                          tail)))
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

(defun gascity-runs--stage-label (formula anchor)
  "Return the lifecycle stage label of ANCHOR in FORMULA, or nil.
ANCHOR is the prefix-stripped step name (`gascity-run-stage-anchor');
FORMULA without a stage table has no label."
  (seq-some
   (lambda (stage)
     (when (member anchor
                   (mapcar #'gascity-run-stage-anchor (nth 2 stage)))
       (nth 1 stage)))
   (gascity-run-stage-for-formula formula)))

(defun gascity-runs--run-failure (run index root)
  "Return the (CLASS . REASON) failure of RUN, or nil.
Only an active or failed RUN has one.  INDEX is the run index and ROOT
its root bead.  The failed step is consulted first (its class and
reason), then the run's failed beads, so the Runs facts line and a
drain member's drawer derive one answer (run-view-v3 R5)."
  (when (memq (plist-get run :state) '(active failed))
    (let ((failed (and root (gascity-runs-failed-step index root))))
      (or (and failed
               (or (plist-get failed :class)
                   (plist-get failed :reason))
               (cons (plist-get failed :class)
                     (plist-get failed :reason)))
          (and root
               (gascity-runs--failure-info
                (gascity-runs--failed-beads-of-run index root)))))))

(defun gascity-runs--row-facts (run index)
  "Return the history facts of RUN (a summary plist) from INDEX.
A plist (:stage :step :failure :worker), every value a string.  The
step is the run's failed step for active and failed runs, else its
last ladder step; the stage is that step's lifecycle label (the step
name when the formula has no stage table); the step reads
`FORMULA.STEP', or the failed step's own ref; the failure comes from
the failed step or the run's failed beads; the worker is the live
worker an active run reports.  A fact the run does not carry is `-'."
  (let* ((state (plist-get run :state))
         (root (plist-get run :root))
         (failed (and (memq state '(active failed)) index root
                      (gascity-runs-failed-step index root)))
         (step (or failed (car (last (plist-get run :ladder)))))
         (name (plist-get step :name))
         (stage (or (gascity-runs--stage-label
                     (plist-get run :formula)
                     (gascity-run-stage-anchor name))
                    name "-"))
         (ref (or (plist-get step :ref)
                  (and name (plist-get run :formula)
                       (concat (plist-get run :formula) "." name))
                  name "-"))
         (info (gascity-runs--run-failure run index root))
         (worker (and (plist-get run :worker-bead)
                      (plist-get (gascity-runs--worker-facts
                                  (plist-get run :worker-bead) nil nil)
                                 :display))))
    (list :stage stage
          :step ref
          :failure (gascity-ui-failure-text info "-")
          :worker (or worker "-"))))

(defconst gascity-runs--facts-columns
  '((stage "stage" 12) (step "step" 21) (failure "fail" 22) (worker "work" 12))
  "The four facts columns of a history row: (KEY LABEL WIDTH).
WIDTH includes the dim LABEL and its one trailing space, so the value
budgets are 6/16/17/7 columns: `Review' fits whole, and a long
`FORMULA.STEP' or failure reason cuts later than it used to.  With the
two-column indent and three ` · ' separators the line is
`2 + 12 + 3 + 21 + 3 + 22 + 3 + 12 = 78' columns, the view width
\(REQ-002).")

(defun gascity-runs--facts-line (facts &optional changed)
  "Return the dim four-column facts line of FACTS.
The columns are `gascity-runs--facts-columns': stage 12, step 21, fail 22
and work 12 columns, each width including its dim label, so the line is
`2 + 12 + 3 + 21 + 3 + 22 + 3 + 12 = 78' columns, the view width.  Each
value is budgeted separately from its label (6/16/17/7 columns) and
fitted (padded or `…'-truncated) inside that budget, keeping the full
text in `help-echo' when cut, so no history row can overflow.  When
CHANGED, the worker value keeps the `gascity-changed' face: the delta
promise covers the worker cell on both of the card's lines
\(run-view-v3 §D, REQ-005)."
  (let ((cell (lambda (column)
                (let* ((key (nth 0 column))
                       (label (nth 1 column))
                       (width (nth 2 column))
                       (text (gascity-ui-fit
                              (gascity-dashboard--dim
                               (or (plist-get facts
                                              (intern (concat ":"
                                                              (symbol-name key))))
                                   "-"))
                              (- width (1+ (length label))))))
                  (when (and changed (eq key 'worker))
                    (setq text (gascity-ui-changed text)))
                  (gascity-ui-fit
                   (concat (gascity-dashboard--dim (concat label " ")) text)
                   width)))))
    (concat "  " (mapconcat cell gascity-runs--facts-columns " · "))))

(defun gascity-runs--history-row (run ctx)
  "Return the lines of RUN's one-line history row (and drawer) in CTX.
The v2 row is followed by a dim four-column facts line
\(`gascity-runs--facts-line'); both belong to the same object and
drawer thing, so TAB/SPC/RET behave the same on either line.  A delta
marks the card's state glyph, its progress cell and its facts-line
worker value (run-view-v3 §D, REQ-005)."
  (let* ((id (plist-get run :id))
         (object (concat "run:" id))
         (thing (gascity-dashboard--thing
                 'row object
                 (lambda () (gascity-dashboard--flip :drawers object))))
         (props (list 'beads-thing thing
                      'gascity-bead id
                      'gascity-run-rig (or (plist-get run :rig) "")))
         (changed (and (plist-get ctx :deltas)
                       (gethash id (plist-get ctx :deltas))))
         (glyph (gascity-runs--state-glyph (plist-get run :state)))
         (progress (gascity-ui-fit (plist-get run :progress) 6))
         (row (apply #'gascity-dashboard--row
                     (concat "  " (if changed (gascity-ui-changed glyph) glyph) " "
                             (gascity-ui-fit id 9) " "
                             (gascity-ui-fit (plist-get run :formula) 13) " "
                             (gascity-ui-fit
                              (gascity-dashboard--ladder-string
                               (plist-get run :ladder))
                              12)
                             " " (if changed (gascity-ui-changed progress) progress)
                             " " (gascity-ui-fit (or (plist-get run :outcome) "") 8))
                     (concat (gascity-dashboard--dim
                              (gascity-ui-fit (or (plist-get run :rig) "city") 10))
                             " " (gascity-runs--time-cell
                                  (plist-get run :time) (plist-get ctx :now)))
                     props))
         (facts (apply #'gascity-dashboard--line
                       (gascity-runs--facts-line
                        (gascity-runs--row-facts run (plist-get ctx :index))
                        changed)
                       props)))
    (append
     (list row facts)
     (and (gascity-dashboard--drawer-open-p object)
          (gascity-dashboard--drawer
           (gascity-dashboard--run-drawer (plist-get run :ladder)))))))

(defun gascity-runs--count-line (counts)
  "Return `1 active · 0 waiting · 51 done · 11 failed (all time)' for COUNTS.
The counts are all-time: the same rig/formula-filtered run list the
sections render, unlike the Failed section's `last <window>' and the
windowed Closed history."
  (concat (mapconcat (lambda (c) (format "%d %s" (cdr c) (car c))) counts " · ")
          " (all time)"))

(defun gascity-runs--filter-summary (filters)
  "Return the dim description of the active FILTERS, or nil."
  (let ((parts (delq nil (mapcar (lambda (k)
                                   (let ((v (plist-get filters (car k))))
                                     (and v (format "%s %s" (cdr k) v))))
                                 '((:rig . "rig") (:formula . "formula")
                                   (:state . "state") (:window . "window"))))))
    (and parts (gascity-dashboard--dim (concat " filter  " (string-join parts " · ")
                                               "   x reset in /")))))

(defun gascity-runs--run-section (name title runs ctx)
  "Return the section lines of section NAME, titled TITLE, over RUNS.
RUNS render as nested two-line cards under CTX; the header counts the
top-level runs (in progress before waiting) and their sub-runs."
  (let* ((nest (gascity-runs--nest runs))
         (subs (seq-count (lambda (n) (> (cdr n) 0)) nest))
         (summary (and nest
                       (concat (number-to-string (- (length nest) subs))
                               (if (> subs 0)
                                   (format " · %d sub-run%s" subs
                                           (if (= subs 1) "" "s"))
                                 "")))))
    (gascity-dashboard--section-lines
     name title summary
     (mapcan (lambda (n) (gascity-runs--card (car n) ctx (cdr n))) nest)
     ctx :loads '(:beads) :label "bd list")))

(defun gascity-runs--title-right (left stamp)
  "Return the right column of title LEFT: STAMP and the key hint.
STAMP is the `updated HH:MM:SS' freshness text or nil
\(`gascity-ui-update-stamp').  The column shows the full
`H history  / filter' hint when it fits the view width beside LEFT and
STAMP, else the compact `H  /', and otherwise keeps STAMP alone; the
stamp and the hint never replace each other (run-view-v3 §D, REQ-006).
Nil when there is neither a stamp nor room for a hint."
  (let* ((width (string-width left))
         (stamp (or stamp ""))
         (sep (if (string-empty-p stamp) "" "  "))
         (full (concat stamp sep "H history  / filter"))
         (short (concat stamp sep "H  /"))
         (fits (lambda (s) (<= (+ width 2 (string-width s))
                               gascity-dashboard--width))))
    (cond ((funcall fits full) (gascity-dashboard--dim full))
          ((funcall fits short) (gascity-dashboard--dim short))
          ((not (string-empty-p stamp)) (gascity-dashboard--dim stamp)))))

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
         ;; The title's right column carries both the freshness stamp
         ;; (REQ-005) and the key hint (REQ-006): the helper abbreviates
         ;; the hint, never the stamp, and never drops one for the other.
         (heading
          (concat (propertize "Runs" 'face 'gascity-header) "  "
                  (propertize (or (plist-get ctx :city) "") 'face 'gascity-city)
                  (if loaded
                      (concat "   " (gascity-dashboard--dim
                                     (gascity-runs--count-line
                                      (plist-get parts :counts))))
                    "")))
         (title (gascity-dashboard--row
                 heading
                 (gascity-runs--title-right
                  heading (gascity-ui-update-stamp
                           (plist-get ctx :last-update)))))
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
                    (gascity-runs--run-section
                     "active" "Active" (plist-get parts :in-progress) ctx))))
    (let ((waiting (plist-get parts :waiting)))
      (when (and (funcall show "waiting")
                 (or waiting (equal state "waiting")))
        (setq lines
              (append lines (list "")
                      (gascity-runs--run-section
                       "waiting" "Waiting" waiting ctx)))))
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
                     "history" "Closed"
                     (concat (number-to-string (length closed))
                             (if (plist-get filters :window)
                                 (concat " · last " (plist-get filters :window))
                               " · all time"))
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
         ;; Run-view-v3 §D: the compared facts of the last delivery, the
         ;; ids they changed, and the delivery time of that change.
         (previous-facts (vui-use-ref nil))
         (changed-ids (vui-use-ref nil))
         (last-update (vui-use-ref nil))
         (loads (list :beads (gascity-ui-effective-load beads-res last-beads)
                      :sessions (gascity-ui-effective-load sessions-res last-sessions)))
         (ctx (gascity-runs-context
               loads filters
               (list :collapsed collapsed :drawers drawers :expanded expanded
                     :history history :pages pages)
               (float-time) gascity-runs--city))
         (facts (gascity-runs--facts (plist-get ctx :runs) ctx)))
    (setq ctx (gascity-ui-apply-delta
               ctx previous-facts changed-ids last-update facts
               (plist-get beads-res :updated-at)))
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

(defun gascity-runs-follow ()
  "Follow the run at point: open its detail (`F').
The persistent twin of the launch's momentary `F' follow offer
\(`gascity-sling--follow-offer'): once the echo is dismissed — or a
launch answered while the user looked elsewhere — `F' here opens the
same `gascity-run-show' the offer pointed at (ga-40tbg.4)."
  (interactive)
  (let ((run (or (gascity-runs--run-at-point)
                 (user-error "No run at point"))))
    (gascity-run-show (car run) nil (cdr run))))

(defun gascity-runs-activate ()
  "Open the run at point in the run detail (RET never folds, §5.4)."
  (interactive)
  (cond ((get-text-property (point) 'gascity-runs-more) (gascity-runs-more))
        ((gascity-runs--run-at-point) (gascity-runs-follow))
        ((get-text-property (point) 'gascity-section) nil)
        (t (user-error "Nothing to act on here"))))

(defun gascity-runs-history ()
  "Show or hide the history of closed runs (`H')."
  (interactive)
  (let ((on (not (gascity-dashboard--state :history))))
    (gascity-dashboard--set-state :history on)
    (when on
      (goto-char (point-min))
      (when (re-search-forward "^Closed\\b" nil t)
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
  :state "state" '("active" "waiting" "failed" "done"))
(gascity-filter-define-choice gascity-runs-filter-window
  :window "window" '("1h" "24h" "7d" "30d") "failed 24h, closed all")

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
  "F"   #'gascity-runs-follow
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
opens its detail, `F' follows a run (the launch offer's persistent
twin), `b' its root bead, `H' the history, `/' filters.

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
  (let* ((dir (gascity-context-city-for-view (beads-prefix-invocation-directory)))
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
