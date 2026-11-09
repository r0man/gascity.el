;;; gascity-run.el --- Run detail: one workflow run's steps -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The run detail (plans/dashboard-v3 §7.7), `*gascity-run: ID*', the
;; drill-in behind a run row of the cockpit and the Runs view:
;;
;;   root     ⬣ be-52m5  build-basic                beads.el · started 2h
;;     store    rig:beads.el   rig beads.el   city emacs-city
;;     scope    (none)
;;     formula  build-basic  contract graph.v2
;;              key graphv2-root:be-93dg:build-basic:296b212076d7ae2e:default
;;              source ~/.gc/cache/…/build-basic.formula.toml
;;     plans    requirements.md · implementation-plan.md · review-report.md
;;     convoy   be-93dg  open 0/1  project-switch-scope
;;
;;   Steps  1/10                                    C show control nodes
;;     ◆ prepare                   be-5aht   pass     run-operator      2h
;;     ⬣ requirements              be-bcb5   iter 1   ● requirements-planner-1
;;     ▾ review                    be-mqhp   loop
;;         · setup-build-basic-review  be-bdcr
;;         ▸ build-basic-review-loop   be-zdon   loop
;;     ...
;;
;; The steps are the run's bead graph arranged by `gc.step_ref' path:
;; the formula prefix stripped (`build-basic.review' → `review'),
;; iteration beads (`review.iteration.1', no prefix) hang under their
;; step, nested steps under theirs; drain members (no step ref) under
;; the run's drain step.  A step whose only children are plain
;; iterations shows its latest iteration inline (`iter N'); any other
;; step with children is a fold row (`▸'/`▾', open by default while
;; something beneath it is active or failed).  Control nodes (`gc.kind'
;; spec / scope-check / workflow-finalize) are hidden until `C'.
;;
;; The `plans' line lists the run root's `gc.build.*_path' plan files
;; (and `gc.implementation.*_path'), each a thing whose `RET' visits it
;; on the city's host (`gascity-remote-localize-path', §8.3 R6); `o'
;; visits the artifact at point explicitly.  The header's provenance
;; rows name the run's store, rig, city and scope, the formula's graph
;; key and source (run-view-v3 §B), and the business bead the run was
;; launched from (`source': the root's `gc.var.convoy_id' input convoy's
;; first tracked member; RET opens that bead, not the workflow root).
;;
;; A step's drawer is the step inspector (run-view-v2 §3): the step's
;; ref, bead, status and outcome; its attempt and iteration; the
;; stacked attempt history (run-view-v3 §A): one row per
;; iteration/attempt bead linked by `gc.logical_bead_id' or a direct
;; `….iteration.N' child path, oldest first, with its number, outcome,
;; worker, relative time and failure class/reason (`(none)' for a
;; healthy attempt; no heading when the step has none); its worker
;; with the session's liveness kept apart from the bead's claim lease
;; and heartbeat (a live session with a lapsed lease is not "gone");
;; the run's and the step's
;; artifacts with existence and age (each a thing `RET' visits); the
;; three newest matching events; and the failure class and reason
;; (`(none)' when the step and everything beneath it are healthy).  The
;; events read starts only while a drawer is open, with the cockpit's
;; key, so the store dedupes the two reads.  A remote city never stats a
;; file on the render path (R2): its artifacts read `remote: not
;; checked'.
;;
;; Reads: the Runs view's shared run-beads entry (`gascity-runs-use-beads',
;; so opening a run from Runs costs no gc call), `session list' for the
;; live assignees, `convoy status ID' for the input convoy and for the
;; source convoy (`gc.var.convoy_id'; the store dedupes them when they
;; are the same), and `events --since' only while a drawer is open.  All
;; through the store; the render is pure (§8.3 R2).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vui)
(require 'beads-thing)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-event)
(require 'gascity-context)
(require 'gascity-remote)
(require 'gascity-store)
(require 'gascity-section)
(require 'gascity-dashboard)
(require 'gascity-runs)
(require 'gascity-run-stage)
(require 'url-util)

(defconst gascity-run-buffer-name "*gascity-run: %s*"
  "Format of the run detail buffer name; %s is the run's root bead id.")

(defvar-local gascity-run--current-run nil
  "The run root bead id this buffer shows.")

(defvar-local gascity-run--current-rig nil
  "The rig store of the run this buffer shows (nil: the city store).")

(defvar-local gascity-run--city nil
  "The city name of this run detail buffer.")

;;; Step tree (pure)

(defun gascity-run--meta (bead key)
  "Return metadata KEY (a symbol) of BEAD, or nil."
  (alist-get key (alist-get 'metadata bead)))

(defun gascity-run--control-p (bead)
  "Return non-nil when BEAD is a control node (spec, scope check, finalize)."
  (member (gascity-run--meta bead 'gc.kind) gascity-dashboard--control-kinds))

(defun gascity-run--iteration-p (bead)
  "Return non-nil when BEAD is a loop iteration (`….iteration.N')."
  (let ((ref (gascity-run--meta bead 'gc.step_ref)))
    (and (stringp ref) (string-match-p "\\.iteration\\.[0-9]+\\'" ref))))

(defun gascity-run--attempt (bead)
  "Return BEAD's `gc.attempt' as a number (0 when absent)."
  (string-to-number (format "%s" (or (gascity-run--meta bead 'gc.attempt) "0"))))

(defun gascity-run--parent-path (path table)
  "Return the longest proper prefix of PATH (at dots) that is in TABLE."
  (let ((segs (split-string path "\\.")))
    (catch 'found
      (cl-loop for k from (1- (length segs)) downto 1
               for prefix = (string-join (seq-take segs k) ".")
               when (gethash prefix table) do (throw 'found prefix))
      nil)))

(defun gascity-run--needs-map (graph formula)
  "Return a hash of step path → ordered list of needed step paths.
GRAPH is the run's graph beads and FORMULA its formula name.  The
canonical edges are each bead's `blocks' dependencies, mapped through
the same `gascity-dashboard--step-path' table the tree uses, so an
iteration or nested bead normalizes to its step path.  When a bead has
no blocks edges but a `needs' list, that list is a compatibility
fallback of formula step refs (`build-basic.prepare'), not bead ids:
the FORMULA prefix is stripped and the result used directly.  Edges to
a path the graph does not contain, and self-edges, are dropped."
  (let ((by-id (make-hash-table :test 'equal))
        (by-path (make-hash-table :test 'equal))
        (needs (make-hash-table :test 'equal))
        (paths nil))
    (dolist (bead graph)
      (let ((path (gascity-dashboard--step-path bead formula)))
        (when path
          (unless (gethash path by-path)
            (push path paths))
          (puthash (alist-get 'id bead) path by-id)
          (puthash path bead by-path))))
    (dolist (path (nreverse paths))
      (let* ((bead (gethash path by-path))
             (blocks (delq nil
                           (mapcar (lambda (dep)
                                     (and (equal (alist-get 'type dep) "blocks")
                                          (let ((id (alist-get 'depends_on_id dep)))
                                            (and id (gethash id by-id)))))
                                   (append (alist-get 'dependencies bead) nil))))
             (fallback (unless blocks
                         (delq nil
                               (mapcar (lambda (need)
                                         (when (stringp need)
                                           (if (and (stringp formula)
                                                    (string-prefix-p
                                                     (concat formula ".") need))
                                               (substring need (1+ (length formula)))
                                             need)))
                                       (append (alist-get 'needs bead) nil)))))
             (deps (delete-dups (append blocks fallback))))
        (setq deps (seq-filter (lambda (dep)
                                 (and dep (not (equal dep path))))
                               deps))
        (when deps
          (puthash path deps needs))))
    needs))

(defun gascity-run--needs-forest (tree needs)
  "Return TREE as a list of (NODE . DEPTH) in deterministic needs order.
TREE is the run's top-level step nodes and NEEDS the hash from
`gascity-run--needs-map'.  A node's parent is the first needed path
that is present; roots are nodes with no present parent, and children
follow their parent's tree order.  A component with no root (a cycle)
is seeded with its first node in tree order, and the node that would
close the cycle is marked with a dim `(cycle)' help-echo.  Every
unvisited node is appended afterwards, so a malformed graph never
hides a step.  Nil when there are no present edges (the flat v2
layout), and never an error."
  (let ((nodes (seq-filter (lambda (node) (plist-get node :path)) tree)))
    (when (and needs (> (hash-table-count needs) 0) nodes)
      (let* ((present (make-hash-table :test 'equal))
             (cells (make-hash-table :test 'equal))
             (parent (make-hash-table :test 'equal))
             (children (make-hash-table :test 'equal))
             (visited (make-hash-table :test 'equal))
             (emitted (make-hash-table :test 'equal))
             (linked nil)
             (out nil))
        ;; A copied node keeps the forest free of render-time mutation of
        ;; the annotated tree (only the cycle marker ever writes).
        (dolist (node nodes)
          (puthash (plist-get node :path) (copy-sequence node) cells))
        (dolist (node nodes)
          (puthash (plist-get node :path) t present))
        (dolist (node nodes)
          (let* ((path (plist-get node :path))
                 (needed (gethash path needs))
                 (found (seq-find (lambda (p)
                                    (and (not (equal p path))
                                         (gethash p present)))
                                  needed)))
            (when found
              (setq linked t)
              (puthash path found parent)
              (puthash found (append (gethash found children) (list path))
                       children))))
        (cl-labels
            ((mark-cycle (path)
               (let ((node (gethash path emitted)))
                 (when node
                   (plist-put node :needs-note
                              (propertize (gascity-dashboard--dim "(cycle)")
                                          'help-echo
                                          "dependency cycle closes here")))))
             (emit (path depth trail)
               (let ((node (gethash path cells)))
                 (push (cons node depth) out)
                 (puthash path node emitted)
                 (puthash path t visited)
                 (dolist (kid (gethash path children))
                   (cond ((member kid trail) (mark-cycle kid))
                         ((gethash kid visited) nil)
                         (t (emit kid (1+ depth) (cons path trail))))))))
          (dolist (node nodes)
            (let ((path (plist-get node :path)))
              (unless (gethash path parent)
                (emit path 0 (list path)))))
          (dolist (node nodes)
            (let ((path (plist-get node :path)))
              (unless (gethash path visited)
                (emit path 0 (list path))))))
        (and linked (nreverse out))))))

(defun gascity-run--forest-parents (forest)
  "Return a hash step path → parent step path from FOREST's pre-order."
  (let ((parents (make-hash-table :test 'equal))
        (stack nil))
    (dolist (cell forest)
      (let* ((node (car cell))
             (depth (cdr cell))
             (path (plist-get node :path)))
        (while (and stack (>= (car (car stack)) depth))
          (pop stack))
        (when (and stack path)
          (puthash path (plist-get (cdr (car stack)) :path) parents))
        (push (cons depth node) stack)))
    parents))

(defun gascity-run-tree (root graph &optional show-control)
  "Return the step tree of run ROOT from its GRAPH beads.
A list of top-level nodes; a node is a plist (:bead :path :name
:children).  Control nodes are left out unless SHOW-CONTROL.  Children
are in formula order (blocks-dependency depth, then attempt, then id)."
  (let* ((formula (gascity-run--meta root 'gc.formula_name))
         (beads (seq-remove (lambda (b) (and (not show-control)
                                             (gascity-run--control-p b)))
                            graph))
         (depth (gascity-dashboard--depths graph))
         (table (make-hash-table :test 'equal))
         (nodes nil)
         (loose nil))
    (dolist (b beads)
      (let ((path (gascity-dashboard--step-path b formula)))
        (if path
            (let ((node (list :bead b :path path :name nil :children nil)))
              (unless (gethash path table) (puthash path node table))
              (push node nodes))
          (push (list :bead b :path nil :name nil :children nil) loose))))
    (setq nodes (nreverse nodes))
    (let* ((top nil)
           (drain (seq-find (lambda (n)
                              (and (equal (gascity-run--meta (plist-get n :bead) 'gc.kind)
                                          "drain")
                                   (not (string-search "." (plist-get n :path)))))
                            nodes))
           (order (lambda (a b)
                    (let* ((ba (plist-get a :bead)) (bb (plist-get b :bead))
                           (da (gethash (alist-get 'id ba) depth 0))
                           (db (gethash (alist-get 'id bb) depth 0)))
                      (cond ((/= da db) (< da db))
                            ((/= (gascity-run--attempt ba) (gascity-run--attempt bb))
                             (< (gascity-run--attempt ba) (gascity-run--attempt bb)))
                            (t (string< (alist-get 'id ba) (alist-get 'id bb)))))))
           (adopt (lambda (parent node)
                    (if parent
                        (plist-put parent :children
                                   (cons node (plist-get parent :children)))
                      (push node top)))))
      (dolist (n nodes)
        (let* ((path (plist-get n :path))
               (parent-path (gascity-run--parent-path path table))
               (parent (and parent-path (gethash parent-path table)))
               (rel (if parent-path (substring path (1+ (length parent-path))) path)))
          ;; A nested formula's steps carry its name too
          ;; (`iteration.1.review.acceptance-review'): the last segment
          ;; names the step, the drawer shows the whole ref.
          (plist-put n :name
                     (if (string-match "\\`iteration\\.\\([0-9]+\\)\\'" rel)
                         (concat "iteration " (match-string 1 rel))
                       (car (last (split-string rel "\\.")))))
          (funcall adopt parent n)))
      (dolist (n (nreverse loose))
        (plist-put n :name (or (alist-get 'title (plist-get n :bead)) ""))
        (funcall adopt drain n))
      (cl-labels ((sorted (list)
                    (mapcar (lambda (n)
                              (plist-put n :children (sorted (plist-get n :children))))
                            (sort list order))))
        (sorted top)))))

(defun gascity-run--latest-iteration (node)
  "Return the latest iteration child of NODE when it is only iterations.
NODE's children must all be leaf iterations; otherwise nil."
  (let ((kids (plist-get node :children)))
    (and kids
         (seq-every-p (lambda (k) (and (gascity-run--iteration-p (plist-get k :bead))
                                       (null (plist-get k :children))))
                      kids)
         (car (last (sort (copy-sequence kids)
                          (lambda (a b) (< (gascity-run--attempt (plist-get a :bead))
                                           (gascity-run--attempt (plist-get b :bead))))))))))

(defun gascity-run--derived-state (node)
  "Return NODE's own state: its latest iteration's while it runs, else its own."
  (let* ((own (gascity-dashboard--bead-state (plist-get node :bead)))
         (iter (gascity-run--latest-iteration node)))
    (if (and iter (not (eq own 'done)))
        (gascity-dashboard--bead-state (plist-get iter :bead))
      own)))

(defun gascity-run--node-state (node)
  "Return NODE's state: the one `gascity-run-annotate' stamped, else derived."
  (or (plist-get node :state) (gascity-run--derived-state node)))

(defun gascity-run-annotate (tree root graph ladder)
  "Stamp every node of TREE with its :state, agreeing with the LADDER.
A top-level step takes its LADDER state (`gascity-dashboard--ladder',
the cockpit's and the Runs view's), so the three views never disagree.
A nested step follows the same rules: its latest iteration while it
runs, and in a failed run (ROOT `gc.outcome' fail) a closed step with a
failed bead beneath it in GRAPH is failed.  Returns TREE."
  (let ((failed-paths (gascity-dashboard--failed-paths root graph))
        (by-id (make-hash-table :test 'equal)))
    (dolist (s ladder) (puthash (plist-get s :id) (plist-get s :state) by-id))
    (cl-labels ((walk (nodes top)
                  (dolist (n nodes)
                    (walk (plist-get n :children) nil)
                    (let* ((id (alist-get 'id (plist-get n :bead)))
                           (state (gascity-run--derived-state n)))
                      (when (and (eq state 'done) (plist-get n :path)
                                 (gascity-dashboard--failed-beneath-p
                                  (plist-get n :path) failed-paths))
                        (setq state 'failed))
                      (plist-put n :state
                                 (or (and top (gethash id by-id)) state))))))
      (walk tree t))
    tree))

(defun gascity-run--busy-p (node)
  "Return non-nil when NODE or anything beneath it is active or failed."
  (or (memq (gascity-run--node-state node) '(active failed))
      (seq-some #'gascity-run--busy-p (plist-get node :children))))

(defun gascity-run--fold-p (node)
  "Return non-nil when NODE renders as a fold row."
  (and (plist-get node :children) (not (gascity-run--latest-iteration node))))

(defun gascity-run--open-p (node view)
  "Return non-nil when fold NODE is expanded under VIEW state.
Open by default while busy (`gascity-run--busy-p'); a toggle in VIEW's
:expanded list flips the default."
  (let ((toggled (member (concat "fold:" (alist-get 'id (plist-get node :bead)))
                         (plist-get view :expanded))))
    (if (gascity-run--busy-p node) (not toggled) toggled)))

(defun gascity-run--worker (node ctx)
  "Return (NAME . AGENT) for NODE's shown bead in CTX, or (nil . nil).
NAME is the live session's agent name, else the parsed assignee; AGENT
is the action `gascity-agent' of a live worker, else nil."
  (let* ((iter (gascity-run--latest-iteration node))
         (shown (if iter (plist-get iter :bead) (plist-get node :bead)))
         (assignee (alist-get 'assignee shown))
         (session (gascity-dashboard--session-for-assignee
                   assignee (plist-get ctx :sessions)))
         (who (cond (session (alist-get 'agent_name session))
                    (assignee (car (gascity-dashboard--parse-assignee assignee)))))
         (agent (and session (gascity-dashboard--agent-object
                              who session (plist-get ctx :socket)))))
    (cons who agent)))

(defconst gascity-run--plan-key-rx
  "\\`gc\\.\\(build\\|implementation\\)\\..*_path\\'"
  "Metadata keys `gascity-run-plans' lists: the run's plan artifacts.")

(defconst gascity-run--artifact-key-rx
  (concat "\\`\\(?:gc\\.build\\..*_path"
          "\\|gc\\.implementation\\..*_path"
          "\\|gc\\.publish_artifact_path"
          "\\|gc\\.close_source_anchor\\.summary_path"
          "\\|code_review\\..*_path\\)\\'")
  "Metadata keys the step inspector lists as an artifact.
Pinned rather than `gc.*_path' so the per-step check script
\(`gc.check_path') and the formula inputs (`gc.var.*_path') are never
presented as artifacts.")

(defun gascity-run--artifact-paths (bead regexp &optional default-work-dir)
  "Return BEAD's metadata paths matching REGEXP as a list of (KEY . PATH).
Each path appears once, in metadata order, and only when the metadata
value is a non-empty string.  A relative path (some formulas record
`plans/…/review-report.md') is joined to BEAD's `gc.work_dir', else to
DEFAULT-WORK-DIR when that is absolute; joined as strings, no file name
handler (R2)."
  (let ((work-dir (or (gascity-run--meta bead 'gc.work_dir) default-work-dir))
        (seen nil) (out nil))
    (dolist (cell (alist-get 'metadata bead))
      (let ((key (symbol-name (car cell))) (path (cdr cell)))
        (when (and (string-match-p regexp key)
                   (stringp path) (not (string-empty-p path)))
          (when (and (not (string-prefix-p "/" path))
                     (stringp work-dir) (string-prefix-p "/" work-dir))
            (setq path (concat (file-name-as-directory work-dir) path)))
          (unless (member path seen)
            (push path seen)
            (push (cons key path) out)))))
    (nreverse out)))

(defun gascity-run-plans (root)
  "Return the plan files of run ROOT: a list of (KEY . PATH), host-local.
Every `gc.build.*_path' / `gc.implementation.*_path' metadata with a
value, each path once, in metadata order.  A relative path (some
formulas record `plans/…/review-report.md') is relative to the run's
`gc.work_dir'; joined as strings, no file name handler (R2)."
  (gascity-run--artifact-paths root gascity-run--plan-key-rx))

(defun gascity-run--short-path (path)
  "Return host-local PATH home-abbreviated, middle elided past 48 columns."
  (let ((p (gascity-dashboard--path path)))
    (if (<= (string-width p) 48)
        p
      (let ((segs (split-string p "/")))
        (concat (string-join (seq-take segs 3) "/") "/…/" (car (last segs)))))))

;;; Rendering

(defun gascity-run--file-thing (path label)
  "Return LABEL as a thing that visits host-local PATH on RET."
  (propertize label
              'gascity-run-file path
              'help-echo path
              'beads-thing (gascity-dashboard--thing 'file path)))

(defun gascity-run--label (label)
  "Return LABEL in the dim face, padded to the header's 9-column field."
  (gascity-dashboard--dim (format "%-9s" label)))

(defun gascity-run--wrap-text (text width first-prefix rest-prefix)
  "Return TEXT word-wrapped into lines of at most WIDTH columns.
FIRST-PREFIX starts the first line, REST-PREFIX every continuation.  A
newline in TEXT ends a line; a word that does not fit moves whole to
the next line and a word wider than a whole line is broken, so every
character of TEXT is kept: a long failure reason is readable in the
buffer rather than clipped (ec-elkm5.8)."
  (let ((lines nil)
        (prefix first-prefix)
        (line ""))
    (cl-labels
        ((avail () (max 1 (- width (string-width prefix))))
         (flush ()
           (push (concat prefix line) lines)
           (setq line "" prefix rest-prefix))
         (place (word)
           (let* ((a (avail))
                  (gap (if (string-empty-p line) 0 1))
                  (w (string-width word)))
             (cond
              ((<= (+ (string-width line) gap w) a)
               (setq line (concat line (if (zerop gap) "" " ") word)))
              ((and (string-empty-p line) (> w a))
               (let* ((head (truncate-string-to-width word a))
                      (tail (substring word (length head))))
                 (push (concat prefix head) lines)
                 (setq prefix rest-prefix
                       line "")
                 (unless (string-empty-p tail) (place tail))))
              (t (flush) (place word))))))
      (dolist (paragraph (split-string (or text "") "\n"))
        (dolist (word (split-string paragraph "[ \t]+" t))
          (place word))
        (flush)))
    (nreverse lines)))

(defun gascity-run--wrapped-header-line (label text)
  "Return the header row(s) for LABEL and TEXT, wrapped, never clipped.
LABEL takes the header's 9-column field after the two-space indent, so
continuation lines align under the value.  Every line carries the full
TEXT in `help-echo'."
  (let* ((prefix (concat "  " (gascity-run--label label)))
         (indent (make-string (string-width prefix) ?\s))
         (full (or text "")))
    (mapcar (lambda (line) (propertize line 'help-echo full))
            (gascity-run--wrap-text full gascity-dashboard--width
                                    prefix indent))))

(defun gascity-run--source-state (convoy-id load)
  "Return the source state of CONVOY-ID from its LOAD.
A plist (:state none|pending|unavailable|single|multi :id :title
:status :count).  No convoy id is `none'; a cold read is `pending'; a
failed read with no data is `unavailable'; exactly one tracked member
is `single' (that business bead is the source); zero or many members is
`multi' (the convoy itself, never a member pretending to be the
source)."
  (cond
   ((not (and (stringp convoy-id) (not (string-empty-p convoy-id))))
    (list :state 'none))
   ((eq (plist-get load :state) 'pending)
    (list :state 'pending))
   ((and (eq (plist-get load :state) 'error)
         (not (gascity-dashboard--data load)))
    (list :state 'unavailable))
   ((not (gascity-dashboard--data load))
    (list :state 'pending))
   (t
    (let* ((payload (gascity-dashboard--data load))
           (convoy (alist-get 'convoy payload))
           (children (append (alist-get 'children payload) nil)))
      (cond
       ((= (length children) 1)
        (let ((child (car children)))
          (list :state 'single
                :id (alist-get 'id child)
                :title (alist-get 'title child)
                :status (alist-get 'status child)
                :count 1)))
       (t
        (list :state 'multi
              :id (or (alist-get 'id convoy) convoy-id)
              :title (alist-get 'title convoy)
              :status (alist-get 'status convoy)
              :count (length children))))))))

(defun gascity-run--headline-lines (source run root)
  "Return the run detail headline for SOURCE, RUN and ROOT.
A single source is its wrapped title; a multi-member source is the
convoy title plus `— tracks N beads'; no source or an unavailable one
falls back to the formula (or the root title), never a fake source.
Every line carries the full text in `help-echo'."
  (let* ((state (plist-get source :state))
         (formula (or (gascity-runs--meta root 'gc.formula_name)
                      (plist-get run :formula)))
         (text
          (pcase state
            ('single (or (plist-get source :title) formula
                         (alist-get 'title root) (plist-get run :id)))
            ('multi (concat (or (plist-get source :title)
                                (plist-get source :id) formula "")
                            " — tracks "
                            (number-to-string (or (plist-get source :count) 0))
                            " beads"))
            (_ (or formula (alist-get 'title root) (plist-get run :id)))))
         (full (or text "")))
    (mapcar (lambda (line) (propertize line 'help-echo full))
            (gascity-run--wrap-text full gascity-dashboard--width "  " "  "))))

(defun gascity-run--identity-lines (source run ctx)
  "Return the run detail identity line for SOURCE and RUN in CTX.
Left is the source id and status (or `(no source)' / `source loading…' /
`source unavailable'); right is the run id, formula, rig and start/close
time.  A single or multi source id carries `gascity-bead' so RET opens
it."
  (let* ((state (plist-get source :state))
         (id (plist-get source :id))
         (status (or (plist-get source :status) ""))
         (thing (and (memq state '(single multi))
                     (gascity-dashboard--thing 'row "source")))
         ;; Only the source id span is the object: RET on the run half of
         ;; the line must not open the source bead by accident.
         (object (lambda (text) (propertize text 'gascity-bead id
                                            'beads-thing thing)))
         (left
          (pcase state
            ('single (concat (funcall object id) "  " status))
            ('multi (concat (funcall object id) "  " status
                            (if (string-empty-p status) "" "  ")
                            (format "%d beads" (or (plist-get source :count) 0))))
            ('pending "source loading…")
            ('unavailable "source unavailable")
            (_ "(no source)")))
         (run-state (plist-get run :state))
         (right (concat "run " (plist-get run :id) " "
                        (or (plist-get run :formula) "")
                        " · " (or (plist-get run :rig) "city")
                        " · "
                        (if (memq run-state '(done failed)) "closed" "started")
                        " "
                        (gascity-ui-time (plist-get run :time)
                                         (plist-get ctx :now)))))
    (list (gascity-dashboard--row
           (concat "  " left)
           (gascity-dashboard--dim right)))))

(defun gascity-run--plan-lines (root)
  "Return the provenance `Plans' rows of ROOT, or nil."
  (let ((plans (gascity-run-plans root))
        (lines nil)
        (row (concat "  " (gascity-dashboard--dim "Plans    ")))
        (width 0))
    (dolist (plan plans)
      (let ((name (file-name-nondirectory (cdr plan))))
        (when (and (> width 0) (> (+ width (string-width name) 3) 64))
          (setq lines (append lines (list row))
                row "           "
                width 0))
        (setq row (concat row (if (> width 0) (gascity-dashboard--dim " · ") "")
                          (gascity-run--file-thing (cdr plan) name))
              width (+ width (string-width name) 3))))
    (when plans (setq lines (append lines (list row))))
    lines))

(defun gascity-run--provenance-lines (run root ctx)
  "Return the run detail provenance rows of RUN and ROOT in CTX.
Distinct labels: Run, Source, Store, Scope, Formula, Key, Formula
source, Plans and Implementation convoy.  Absent facts are omitted; the
implementation convoy row is omitted when its id equals the source
convoy id, and no row is called `convoy' alone."
  (let* ((source (plist-get ctx :source))
         (source-id (gascity-runs--meta root 'gc.var.convoy_id))
         (impl-id (or (gascity-runs--meta root 'gc.build.implementation_convoy_id)
                      (gascity-runs--meta root 'gc.input_convoy_id)))
         (impl (plist-get ctx :implementation-convoy))
         (store (gascity-runs--meta root 'gc.root_store_ref))
         (rig (gascity-runs--meta root 'gc.var.rig_name))
         (city (plist-get ctx :city))
         (scope (gascity-runs--meta root 'gc.scope_ref))
         (key (gascity-runs--meta root 'gc.graphv2_root_key))
         (formula-source (gascity-runs--meta root 'gc.formula_source))
         (contract (gascity-runs--meta root 'gc.formula_contract))
         (graph (gascity-runs-graph (plist-get ctx :index)
                                    (alist-get 'id root)))
         (lines nil))
    (setq lines
          (append lines
                  (list (gascity-dashboard--line
                         (concat "  " (gascity-run--label "Run")
                                 (plist-get run :id) " · "
                                 (format "%d beads" (length graph)) " · formula "
                                 (or (plist-get run :formula) ""))
                         'gascity-bead (plist-get run :id)
                         'beads-thing (gascity-dashboard--thing 'row "run")))))
    (when source-id
      (let ((state (plist-get source :state)))
        (setq lines
              (append lines
                      (list (concat "  " (gascity-run--label "Source")
                                    "input convoy " source-id " · "
                                    (pcase state
                                      ('single "1 tracked member")
                                      ('multi (format "%d tracked members"
                                                      (or (plist-get source :count) 0)))
                                      ('pending "loading…")
                                      ('unavailable "unavailable")
                                      (_ "no tracked members"))))))))
    (setq lines
          (append lines
                  (list
                   (gascity-ui-truncate
                    (concat "  " (gascity-run--label "Store")
                            (or store "city store")
                            (if rig (concat "   " (gascity-dashboard--dim "rig ") rig) "")
                            (if city (concat "   " (gascity-dashboard--dim "city ") city) ""))
                    gascity-dashboard--width)
                   (gascity-ui-truncate
                    (concat "  " (gascity-run--label "Scope") (or scope "(none)"))
                    gascity-dashboard--width)
                   (gascity-ui-truncate
                    (concat "  " (gascity-run--label "Formula")
                            (or (plist-get run :formula) "")
                            (if contract
                                (concat "  " (gascity-dashboard--dim "contract ")
                                        contract)
                              ""))
                    gascity-dashboard--width))))
    (when key
      (setq lines (append lines
                          (list (concat "  " (gascity-run--label "Key")
                                        (gascity-ui-truncate key 63))))))
    (when formula-source
      (setq lines (append lines
                          (list (concat "  " (gascity-run--label "Formula source") " "
                                        (gascity-run--file-thing
                                         formula-source
                                         (gascity-ui-truncate
                                          (gascity-run--short-path formula-source)
                                          60)))))))
    (setq lines (append lines (gascity-run--plan-lines root)))
    (when (and impl-id impl (not (equal impl-id source-id)))
      (let* ((c (car impl))
             (progress (cdr impl))
             (id (or (alist-get 'id c) impl-id)))
        (setq lines
              (append lines
                      (list (gascity-dashboard--line
                             (concat "  " (gascity-run--label "Implementation convoy") " "
                                     id "  " (or (alist-get 'status c) "")
                                     (if progress
                                         (format " %s/%s"
                                                 (or (alist-get 'closed progress) "?")
                                                 (or (alist-get 'total progress) "?"))
                                       "")
                                     "  " (gascity-dashboard--dim
                                           (or (alist-get 'title c) "")))
                             'gascity-bead id
                             'beads-thing (gascity-dashboard--thing
                                           'row "implementation-convoy")))))))
    lines))

(defun gascity-run--failure-detail (root ctx)
  "Return (:class :reason :ref :id :full) for ROOT's failure in CTX, or nil.
The failed step named by CTX's run index supplies the class, ref, id
and reason; the root's own `gc.failure_class'/`gc.failure_reason' are
the fallback.  A close reason alone is not a failure -- the `close'
row shows it -- so a run that passed is never labelled failed, and
nothing is invented (ec-elkm5.8)."
  (let* ((index (plist-get ctx :index))
         (step (and index root (gascity-runs-failed-step index root)))
         (info (if step
                   (and (or (plist-get step :class) (plist-get step :reason))
                        (cons (plist-get step :class) (plist-get step :reason)))
                 (let ((class (gascity-run--meta root 'gc.failure_class))
                       (reason (gascity-run--meta root 'gc.failure_reason)))
                   (and (or class reason) (cons class reason)))))
         (class (car-safe info))
         (reason (cdr-safe info)))
    (and info
         (list :class class :reason reason
               :ref (or (plist-get step :ref)
                        (gascity-run--meta root 'gc.step_ref))
               :id (plist-get step :id)
               :full (or reason class)))))

(defun gascity-run--failure-lines (root run ctx)
  "Return the failure and close header rows of ROOT (summary RUN) in CTX.
A failed run, or an active run with a failed step, names that step, its
`gc.failure_class' and the full reason (wrapped, never clipped).  A
closed run always shows its root's close reason, `not recorded' when gc
carries none -- never fabricated, and never confused with a step's
failure (ec-elkm5.8; run-view-v3 §B, REQ-003)."
  (let* ((state (plist-get run :state))
         (failure (and (memq state '(active failed))
                       (gascity-run--failure-detail root ctx))))
    (append
     (and failure
          (append
           (and (or (plist-get failure :ref) (plist-get failure :id))
                (list (concat "  " (gascity-run--label "step")
                              (or (plist-get failure :ref) "")
                              (if-let* ((id (plist-get failure :id)))
                                  (concat "  " (gascity-dashboard--dim id))
                                ""))))
           (and (plist-get failure :class)
                (list (concat "  " (gascity-run--label "class")
                              (plist-get failure :class))))
           (and (plist-get failure :reason)
                (gascity-run--wrapped-header-line
                 "reason" (plist-get failure :reason)))))
     (and (memq state '(done failed))
          (gascity-run--wrapped-header-line
           "close" (or (gascity-runs--close-reason root) "not recorded"))))))

(defun gascity-run--header-lines (run root ctx)
  "Return the run detail headline and identity lines of RUN and ROOT in CTX.
The source headline comes from CTX's :source; the identity line names
the source id/status and the run id/formula/rig/time.  Provenance is
rendered separately, after the Work section."
  (append (gascity-run--headline-lines (plist-get ctx :source) run root)
          (gascity-run--identity-lines (plist-get ctx :source) run ctx)
          (gascity-run--failure-lines root run ctx)))

(defun gascity-run--detail (node)
  "Return the detail column of step NODE: iteration, outcome, loop, kind."
  (let* ((bead (plist-get node :bead))
         (kind (gascity-run--meta bead 'gc.kind))
         (iter (gascity-run--latest-iteration node)))
    (cond (iter (format "iter %d" (gascity-run--attempt (plist-get iter :bead))))
          ((gascity-run--fold-p node)
           (pcase kind ("ralph" "loop") ("scope" "iter") ("drain" "drain")
                  (_ (or kind ""))))
          ((gascity-run--control-p bead) kind)
          ((equal (alist-get 'status bead) "closed")
           (or (gascity-run--meta bead 'gc.outcome) "closed"))
          ((equal kind "drain") "drain")
          (t (let ((s (alist-get 'status bead))) (if (equal s "open") "" (or s "")))))))

;;; Inspector (run-view-v2 §3)

(defun gascity-run--root-bead (ctx)
  "Return CTX's run root bead from its :index, or nil."
  (seq-find (lambda (bead) (equal (alist-get 'id bead) (plist-get ctx :run-id)))
            (plist-get (plist-get ctx :index) :roots)))

(defun gascity-run--step-path (bead ctx)
  "Return BEAD's formula-prefix-stripped step path in CTX, or nil."
  (let ((root (gascity-run--root-bead ctx)))
    (and root (gascity-dashboard--step-path
               bead (gascity-runs--meta root 'gc.formula_name)))))

(defun gascity-run--under-path-p (path ancestor)
  "Return non-nil when step PATH is ANCESTOR or lies beneath it."
  (and path ancestor
       (or (equal path ancestor)
           (string-prefix-p (concat ancestor ".") path))))

(defun gascity-run--related-beads (step ctx)
  "Return STEP and the graph beads at or beneath its step path in CTX."
  (let* ((path (gascity-run--step-path step ctx))
         (root (gascity-run--root-bead ctx))
         (graph (and root (gascity-runs-graph (plist-get ctx :index)
                                              (alist-get 'id root)))))
    (append
     (list step)
     (seq-filter
      (lambda (bead)
        (and (not (equal (alist-get 'id bead) (alist-get 'id step)))
             (gascity-run--under-path-p (gascity-run--step-path bead ctx) path)))
      graph))))

(defun gascity-run--failure-text (step iteration ctx)
  "Return the inspector's failure text for STEP and ITERATION in CTX.
The class and reason come from the step, its iteration or the nearest
failed bead at or beneath its step path (`gascity-runs--failure-info'),
so a failed review loop explains the anchor step above it; `(none)'
when neither the step nor anything beneath it failed.  A healthy step
still carries a close reason, so only failed beads are candidates."
  (let* ((related (gascity-run--related-beads step ctx))
         (failed (seq-filter
                  (lambda (bead)
                    (equal (gascity-runs--meta bead 'gc.outcome) "fail"))
                  related))
         (nearest (sort failed
                        (lambda (a b)
                          (< (length (or (gascity-run--step-path a ctx) ""))
                             (length (or (gascity-run--step-path b ctx) ""))))))
         (info (gascity-runs--failure-info
                (append (and (equal (gascity-runs--meta step 'gc.outcome) "fail")
                             (list step))
                        (and iteration
                             (equal (gascity-runs--meta iteration 'gc.outcome) "fail")
                             (list iteration))
                        nearest))))
    (gascity-ui-failure-text info)))

;;; Attempt history (run-view-v3 §A, REQ-001)

(defconst gascity-run--attempt-widths
  '((number . 3) (outcome . 9) (worker . 18) (failure . 20))
  "Fixed column widths of an attempt-history row.
With the two-space indent, four separators and the nine-column time
cell, a row is at most 65 columns -- inside `gascity-dashboard--width'
at every drawer depth the step tree reaches.")

(defun gascity-run--attempt-number (bead)
  "Return BEAD's attempt number, or nil when it names none.
`gc.attempt' wins; `gc.iteration' is the fallback for payloads that
only number iterations.  A non-numeric value does not count."
  (let ((raw (or (gascity-run--meta bead 'gc.attempt)
                 (gascity-run--meta bead 'gc.iteration))))
    (and (string-match-p "\\`[0-9]+\\'" (format "%s" raw))
         (string-to-number (format "%s" raw)))))

(defun gascity-run--iteration-number (bead)
  "Return BEAD's numeric `gc.iteration', or 0 when absent or not numeric."
  (let ((raw (gascity-run--meta bead 'gc.iteration)))
    (if (and raw (string-match-p "\\`[0-9]+\\'" (format "%s" raw)))
        (string-to-number (format "%s" raw))
      0)))

(defun gascity-run--attempt-path-p (bead step-path ctx)
  "Return non-nil when BEAD is a direct iteration/attempt child of STEP-PATH.
CTX identifies the run whose formula prefix the paths are read without;
BEAD's own `gc.step_ref' decides.  Exactly one extra path segment is
allowed, so a nested formula step below an iteration
\(`step.iteration.1.review.acceptance-review') is not an attempt."
  (let ((path (gascity-run--step-path bead ctx)))
    (and path step-path
         (string-prefix-p (concat step-path ".") path)
         (string-match-p "\\`\\(?:iteration\\|attempt\\)\\.[0-9]+\\'"
                         (substring path (1+ (length step-path)))))))

(defun gascity-run--attempt-beads (step ctx)
  "Return STEP's attempt beads in CTX, oldest first.
A bead is an attempt when it is not STEP, has a numeric attempt
\(`gc.attempt', else `gc.iteration'), and either names STEP in
`gc.logical_bead_id' (the authoritative link, and the only one for a
nested loop's iterations) or sits at a direct
`STEP-PATH.iteration.N'/`STEP-PATH.attempt.N' child path (the fallback
for older payloads without the logical id).  Rows are ordered by
attempt, then iteration, then id.  Every bead comes from CTX's
already-loaded run graph, so this reads nothing."
  (let* ((step-id (alist-get 'id step))
         (step-path (gascity-run--step-path step ctx))
         (root (gascity-run--root-bead ctx))
         (graph (and root (gascity-runs-graph (plist-get ctx :index)
                                              (alist-get 'id root))))
         (attempts
          (seq-filter
           (lambda (bead)
             (and (not (equal (alist-get 'id bead) step-id))
                  (gascity-run--attempt-number bead)
                  (or (equal (gascity-run--meta bead 'gc.logical_bead_id) step-id)
                      (gascity-run--attempt-path-p bead step-path ctx))))
           graph)))
    (sort (copy-sequence attempts)
          (lambda (a b)
            (let ((na (gascity-run--attempt-number a))
                  (nb (gascity-run--attempt-number b))
                  (ia (gascity-run--iteration-number a))
                  (ib (gascity-run--iteration-number b)))
              (cond ((/= na nb) (< na nb))
                    ((/= ia ib) (< ia ib))
                    (t (string< (alist-get 'id a) (alist-get 'id b)))))))))

(defun gascity-run--failure-line (text)
  "Return the drawer's `failure  ' lines for TEXT.
TEXT (the class and reason) is word-wrapped at
`gascity-dashboard--drawer-width' so the whole reason is readable in
the buffer rather than clipped at the window edge; every line also
carries the full text in `help-echo'.  Every drawer failure -- step
inspector and drain member -- goes through here (REQ-003,
ec-elkm5.8)."
  (let ((full (or text "")))
    (mapcar (lambda (line) (propertize line 'help-echo full))
            (gascity-run--wrap-text full gascity-dashboard--drawer-width
                                    "failure  " "         "))))

(defun gascity-run--attempt-line (bead ctx)
  "Return the attempt-history row of BEAD in CTX.
Columns: number, outcome (`gc.outcome', else status, else `(none)'),
worker, relative time, and failure (`(none)' when healthy).  The
worker carries `●'/`○' only when CTX has a live-session payload; the
time is `closed_at', else `updated_at', relative to CTX's :now.  Only
an attempt whose `gc.outcome' is fail names a class/reason; a healthy
one reads `(none)' even when it carries a close reason."
  (let* ((status (alist-get 'status bead))
         (outcome (or (gascity-run--meta bead 'gc.outcome) status "(none)"))
         (facts (gascity-runs--worker-facts
                 bead (plist-get ctx :sessions) (plist-get ctx :socket)))
         (session (plist-get facts :session))
         (worker (concat (if (plist-get ctx :sessions)
                             (concat (gascity-ui-glyph (if session 'ok 'idle)) " ")
                           "")
                         (plist-get facts :display)))
         (time (if (equal status "closed")
                   (alist-get 'closed_at bead)
                 (alist-get 'updated_at bead)))
         ;; A healthy attempt is `(none)' even though its close reason is
         ;; set; only a failed attempt names a class and reason.
         (failure (if (equal (gascity-run--meta bead 'gc.outcome) "fail")
                     (gascity-ui-failure-text
                      (gascity-runs--failure-info (list bead)))
                   "(none)")))
    (concat "  "
            (gascity-ui-fit (format "%d" (gascity-run--attempt-number bead))
                            (alist-get 'number gascity-run--attempt-widths))
            " "
            (gascity-ui-fit outcome (alist-get 'outcome gascity-run--attempt-widths))
            " "
            (gascity-ui-fit worker (alist-get 'worker gascity-run--attempt-widths))
            " "
            (gascity-runs--time-cell time (plist-get ctx :now))
            " "
            (gascity-ui-truncate failure
                                 (alist-get 'failure gascity-run--attempt-widths)))))

(defun gascity-run--attempt-lines (step ctx)
  "Return STEP's stacked attempt history for CTX, or nil.
One dim `attempts' heading followed by one `gascity-run--attempt-line'
per attempt, oldest first; nil (no heading) when STEP has none.  The
facts come from CTX's run-beads index, so this reads nothing."
  (let ((attempts (gascity-run--attempt-beads step ctx)))
    (when attempts
      (cons (gascity-dashboard--dim "attempts")
            (mapcar (lambda (bead) (gascity-run--attempt-line bead ctx))
                    attempts)))))

(defun gascity-run--local-path-p (path)
  "Return non-nil when PATH can be stat'ed on the render path.
A TRAMP-prefixed PATH and a remote city (`default-directory' over
TRAMP) both count as remote, so the render never stats across the
connection (R2)."
  (and (stringp path)
       (not (file-remote-p path))
       (not (file-remote-p default-directory))))

(defun gascity-run--human-size (bytes)
  "Return BYTES as `512 B', `12 KB', `3.4 MB' or `1.2 GB'."
  (let ((n (or bytes 0)))
    (cond ((< n 1024) (format "%d B" n))
          ((< n (* 1024 1024)) (format "%d KB" (/ n 1024)))
          ((< n (* 1024 1024 1024))
           (format "%.1f MB" (/ n (* 1024.0 1024.0))))
          (t (format "%.1f GB" (/ n (* 1024.0 1024.0 1024.0)))))))

(defun gascity-run--artifact-entry (path ctx)
  "Return the inspector text of artifact PATH in CTX, or nil.
The entry is a `gascity-run-file' thing, so RET visits it on the city's
host.  A local file is annotated with its size and age; a remote city's
file is never stat'ed on the render path (R2) and says so; a missing or
unreadable file reads `missing', never signaling."
  (let* ((remote (not (gascity-run--local-path-p path)))
         (attrs (and (not remote) (ignore-errors (file-attributes path))))
         (note (cond (remote "remote: not checked")
                     ((not attrs) "missing")
                     (t (format "%s, %s"
                                (gascity-run--human-size
                                 (file-attribute-size attrs))
                                (gascity-ui-relative-time
                                 (float-time
                                  (file-attribute-modification-time attrs))
                                 (plist-get ctx :now)))))))
    (gascity-run--file-thing path (concat (file-name-nondirectory path)
                                          " (" note ")"))))

(defun gascity-run--artifact-lines (step iteration ctx)
  "Return the inspector's artifact lines for STEP and ITERATION in CTX.
The run root's plan artifacts come first (`run'), then the step bead's
and its latest iteration's artifacts (`step').  A path listed twice is
shown once."
  (let* ((root (gascity-run--root-bead ctx))
         (work-dir (and root (gascity-runs--meta root 'gc.work_dir)))
         (run-paths (and root (gascity-run--artifact-paths
                               root gascity-run--plan-key-rx)))
         (step-paths (append
                      (gascity-run--artifact-paths
                       step gascity-run--artifact-key-rx work-dir)
                      (and iteration
                           (gascity-run--artifact-paths
                            iteration gascity-run--artifact-key-rx work-dir))))
         (seen nil))
    (cl-labels ((entries (paths)
                  (delq nil
                        (mapcar
                         (lambda (cell)
                           (unless (member (cdr cell) seen)
                             (push (cdr cell) seen)
                             (gascity-run--artifact-entry (cdr cell) ctx)))
                         paths))))
      (delq nil
            (list (let ((run (entries run-paths)))
                    (and run (concat "artifacts run   " (string-join run " · "))))
                  (let ((own (entries step-paths)))
                    (and own (concat "artifacts step  " (string-join own " · ")))))))))

(defun gascity-run--lease-time (worker step)
  "Return the claim-lease expiry of WORKER, else STEP, or nil."
  (or (gascity-ui-parse-time (alist-get 'lease_expires_at worker))
      (gascity-ui-parse-time (alist-get 'lease_expires_at step))))

(defun gascity-run--heartbeat-time (worker step)
  "Return the claim heartbeat of WORKER, else STEP, or nil."
  (or (gascity-ui-parse-time (alist-get 'heartbeat_at worker))
      (gascity-ui-parse-time (alist-get 'heartbeat_at step))))

(defun gascity-run--session-text (facts ctx)
  "Return the session-liveness fact of worker FACTS at CTX, or nil.
The fact comes from the session row, not the bead: `session live ·
active 20s ago' when the row carries a real last-active stamp, else
`session live'.  No live session yields nil; the caller says
`assignee/session gone' instead."
  (when (plist-get facts :session)
    (let* ((last (plist-get facts :last-active))
           (ago (and last (not (gascity-ui-epoch-time-p last))
                     (gascity-ui-ago last (plist-get ctx :now)))))
      (concat "session live"
              (and ago (not (string-empty-p ago))
                   (concat " · active " ago))))))

(defun gascity-run--claim-note (session lease ctx)
  "Return the note qualifying a lapsed claim LEASE for SESSION at CTX.
Only a lapsed lease with a live session gets a note; with no session
the line already says `assignee/session gone'.  The cockpit's
stale-work rule (ga-o7vtw) treats a lapsed lease as the stall only
when the live session cannot show activity after the deadline.  The
inspector says the same: a session active after the deadline is the
Pi worker's missing `gc bd heartbeat' (ga-p2lfj), not a dead worker;
a quiet one is a stale claim."
  (let ((now (plist-get ctx :now)))
    (when (and lease now session (<= lease now))
      (gascity-dashboard--dim
       (if (gascity-dashboard--session-active-after-p session lease)
           "(Pi heartbeat gap)"
         "(stale claim)")))))

(defun gascity-run--claim-text (worker step session ctx)
  "Return WORKER's (else STEP's) claim fact at CTX, or nil.
The bead's claim lease and heartbeat are kept apart from session
liveness: `claim lease 3m left · heartbeat 30s ago' while the lease
holds, `claim lease lapsed 4m ago …' once it does not.  A lapsed
claim on a live SESSION is qualified by `gascity-run--claim-note'."
  (let* ((lease (gascity-run--lease-time worker step))
         (heartbeat (gascity-run--heartbeat-time worker step))
         (now (plist-get ctx :now))
         (parts nil))
    (when lease
      (push (if (>= (- lease (or now 0)) 0)
                (format "claim lease %s left"
                        (gascity-ui-duration (- lease now)))
              (format "claim lease lapsed %s ago"
                      (gascity-ui-duration (- now lease))))
            parts))
    (when heartbeat
      (push (format "heartbeat %s ago"
                    (gascity-ui-duration (- (or now 0) heartbeat)))
            parts))
    (let* ((text (and parts (string-join (nreverse parts) " · ")))
           (note (gascity-run--claim-note session lease ctx)))
      (cond ((and text note) (concat text " " note))
            (text text)
            (note note)))))

(defun gascity-run--worker-line (step iteration ctx)
  "Return the inspector's worker line for STEP and ITERATION in CTX.
The iteration bead is the worker's own bead while it runs.  The line
keeps two facts apart: the session's liveness (`session live · active
20s ago', from CTX's :sessions `●', or `○' with no live session) and
the bead's claim lease and heartbeat (from the bead that records them).
`assignee/session gone' is said when no live session matches an
assignee; a lapsed claim on a live session is a heartbeat gap, never
a dead worker.  The line carries the live worker as its
`gascity-agent' property, so v, i and t resolve from the drawer as
from the row."
  (let* ((worker (or iteration step))
         (bead (or iteration step))
         (assignee (or (alist-get 'assignee bead)
                       (alist-get 'assignee step)))
         (facts (gascity-runs--worker-facts
                 (if (alist-get 'assignee bead) bead step)
                 (plist-get ctx :sessions) (plist-get ctx :socket)))
         (session (plist-get facts :session))
         (parts
          (delq nil
                (list assignee
                      (and assignee
                           (concat (gascity-ui-glyph (if session 'ok 'idle))
                                   " " (plist-get facts :display)))
                      (if session
                          (gascity-run--session-text facts ctx)
                        (and assignee "assignee/session gone"))
                      (gascity-run--claim-text worker step session ctx))))
         (line (concat "worker   " (if parts (string-join parts "  ") "no session"))))
    (if (plist-get facts :agent)
        (propertize line 'gascity-agent (plist-get facts :agent))
      line)))

(defun gascity-run--event-ids (step iteration ctx)
  "Return the bead ids whose events belong to STEP's inspector row in CTX.
The step, its latest ITERATION, and every graph bead at or beneath the
step's step path."
  (delq nil
        (mapcar (lambda (bead) (alist-get 'id bead))
                (append (gascity-run--related-beads step ctx)
                        (and iteration (list iteration))))))

(defun gascity-run--event-lines (step iteration ctx)
  "Return the inspector's recent-event lines for STEP and ITERATION in CTX.
The three newest events (`gascity-event-time') whose `gascity-event-bead'
is the step, its iteration or a descendant.  A cold pending load emits
no line at all (it has read nothing yet, so it must not claim there is
nothing to report); a failed events load says `events unavailable'; a
ready load without a match says `(no recent events)'.  Never signals,
and never reads gc on the render path."
  (let* ((load (plist-get ctx :events))
         (ids (gascity-run--event-ids step iteration ctx))
         ;; A `:lines t' store payload is `(GOOD . BAD)', the good events
         ;; and the count of undecodable lines; never the cons itself.
         (events (car (gascity-dashboard--data load)))
         (matching
          (and events
               (seq-filter
                (lambda (event)
                  (let ((bead (gascity-event-bead event)))
                    (and bead (member (alist-get 'id bead) ids))))
                events)))
         (newest (seq-take (sort (copy-sequence matching)
                                 (lambda (a b) (> (gascity-event-time a)
                                                 (gascity-event-time b))))
                           3)))
    (cond
     ((and load (eq (plist-get load :state) 'error))
      (list "events   events unavailable"))
     ((eq (plist-get load :state) 'pending) nil)
     (newest
      (mapcar (lambda (event)
                (format "events   %s %s  %s"
                        (or (alist-get 'type event) "event")
                        (or (alist-get 'id (gascity-event-bead event)) "")
                        (gascity-ui-ago (alist-get 'ts event)
                                        (plist-get ctx :now))))
              newest))
     (t (list "events   (no recent events)")))))

(defun gascity-run--step-drawer (step iteration ctx)
  "Return the inspector lines of STEP and its latest ITERATION bead in CTX.
In order: the step's ref, bead, status and outcome; its attempt and
iteration; its stacked attempt history (one row per iteration/attempt
bead, oldest first; no heading when there is none); its worker with
the session's liveness and, separately, the
bead's claim lease and heartbeat; the run's and the step's artifacts
with existence and age; the three newest matching events; and the
failure class and reason, `(none)' when the
step is healthy.  A line appears only when the payload has the datum
\(the explicit `no session' / no-event / `(none)' fallbacks aside), so a
closed or session-less step renders cleanly.  Everything comes from the
payload in hand; the only I/O is a local file stat."
  (let* ((worker (or iteration step))
         (step-meta (alist-get 'metadata step))
         (meta (alist-get 'metadata worker))
         (ref (or (alist-get 'gc.step_ref step-meta)
                  (alist-get 'gc.step_ref meta)
                  (alist-get 'title step)))
         (outcome (alist-get 'gc.outcome step-meta))
         (step-id (alist-get 'id step))
         (iteration-id (alist-get 'id iteration))
         (attempt (or (alist-get 'gc.attempt meta)
                      (alist-get 'gc.attempt step-meta)))
         (iteration-n (or (alist-get 'gc.iteration meta)
                          (alist-get 'gc.iteration step-meta)))
         (parts (delq nil
                      (list (and attempt (format "%s" attempt))
                            (and iteration-n (format "iteration %s" iteration-n))
                            (and iteration-id (concat "iteration bead " iteration-id)))))
         (step-line (concat "step     " (or ref "?")
                            "  " (or step-id "")
                            "  " (or (alist-get 'status step) "")
                            (if outcome (concat "  outcome " outcome) "")))
         (attempt-line (and parts (concat "attempt  " (string-join parts " · ")))))
    (append
     (list (if step-id
               (propertize step-line 'gascity-bead step-id)
             step-line))
     (and attempt-line
          (list (if iteration-id
                    (propertize attempt-line 'gascity-bead iteration-id)
                  attempt-line)))
     (gascity-run--attempt-lines step ctx)
     (list (gascity-run--worker-line step iteration ctx))
     (gascity-run--artifact-lines step iteration ctx)
     (gascity-run--event-lines step iteration ctx)
     (gascity-run--failure-line
      (gascity-run--failure-text step iteration ctx)))))

(defun gascity-run--member-drawer (member index ctx)
  "Return the inline drawer lines of drain-member run MEMBER.
INDEX is the run index and CTX the render context.  The lines carry the
member's summary (root, formula, progress, time, rig), its live worker,
its own failure (the failed step of the member's graph, else the failed
beads) and a dim `RET run' hint.  Everything comes from the loaded
index, so opening or refreshing the drawer reads nothing."
  (let* ((run (gascity-runs-summary index member))
         (root (plist-get run :root))
         (state (plist-get run :state))
         (info (gascity-runs--run-failure run index root))
         (worker (and (plist-get run :worker-bead)
                      (gascity-runs--worker (plist-get run :worker-bead)
                                            (plist-get ctx :sessions)
                                            (plist-get ctx :socket)))))
    (append
     (list
      (concat "root     " (plist-get run :id) "  "
              (gascity-runs--state-glyph state) " "
              (or (and state (symbol-name state)) "?"))
      (concat "formula  " (or (plist-get run :formula) "-")
              "  " (or (plist-get run :progress) "-")
              "  " (gascity-ui-time (plist-get run :time) (plist-get ctx :now))
              "  " (or (plist-get run :rig) "city"))
      (concat "worker   " (if worker (car worker) "no live worker")))
     (gascity-run--failure-line (gascity-ui-failure-text info))
     (list (gascity-dashboard--dim "RET run")))))

(defun gascity-run--member-lines (step depth ctx)
  "Return the rows (and open drawers) of the members drain STEP fans out to.
The rows are indented at DEPTH (the step's own tree depth), so a
member sits under its drain step.  A drain step stays open while its
member runs (roots naming it in
`gc.drain_control_id', the :drains of CTX's :index) work outside this
run's graph: each gets a row with its ladder, RET opens its run detail.
The row carries the member's root id in `gascity-bead' (so `w' copies
it) and `I' toggles the member's own `member:<id>' drawer."
  (let ((index (plist-get ctx :index)))
    (mapcan
     (lambda (member)
       (let* ((run (gascity-runs-summary index member))
              (id (plist-get run :id))
              (drawer-id (concat "member:" id))
              (indent (make-string (+ 4 (* 2 depth)) ?\s)))
         (cons
          (gascity-dashboard--row
           (concat indent "└ "
                   (gascity-runs--state-glyph (plist-get run :state)) " "
                   (gascity-ui-fit id 9) " "
                   (gascity-ui-fit (plist-get run :formula) 10) " "
                   (gascity-dashboard--ladder-string (plist-get run :ladder)) "  "
                   (gascity-ui-fit (plist-get run :label) 14) " "
                   (plist-get run :progress))
           (gascity-dashboard--dim "RET run")
           'gascity-run-member id
           'gascity-run-member-rig (plist-get run :rig)
           'gascity-bead id
           'beads-thing
           (gascity-dashboard--thing
            'row drawer-id
            (lambda () (gascity-dashboard--flip :drawers drawer-id))))
          (and (gascity-dashboard--drawer-open-p drawer-id)
               (mapcar (lambda (line) (concat indent line))
                       (gascity-dashboard--drawer
                        (gascity-run--member-drawer member index ctx)))))))
     (reverse (gethash (alist-get 'id step) (plist-get index :drains))))))

;;; Stage groups (run-view-v2 §2)

(defun gascity-run--tree-flat-lines (forest ctx)
  "Return the rows of FOREST for a formula without a stage table.
The whole forest renders in pre-order with the existing two-space
indentation; every row machinery is inherited from
`gascity-run--step-lines'.  CTX is the render context."
  (mapcan (lambda (cell)
            (gascity-run--step-lines (car cell) (min (cdr cell) 4) ctx))
          forest))

(defun gascity-run--step-lines (node depth ctx)
  "Return the lines of step NODE at DEPTH (and its children) in CTX."
  (let* ((view (plist-get ctx :view))
         (iter (gascity-run--latest-iteration node))
         ;; The row names the step (the id the ladder and drawers use);
         ;; its worker and time are the latest iteration's, whose id is
         ;; in the row's drawer.
         (shown (if iter (plist-get iter :bead) (plist-get node :bead)))
         (id (alist-get 'id (plist-get node :bead)))
         (fold (gascity-run--fold-p node))
         (open (and fold (gascity-run--open-p node view)))
         (state (gascity-run--node-state node))
         (worker (gascity-run--worker node ctx))
         (who (car worker))
         (agent (cdr worker))
         (changed (and (plist-get ctx :deltas)
                       (gethash id (plist-get ctx :deltas))))
         ;; A tree note (`↳ needs PARENT', `(cycle)') takes its room
         ;; from the name column, so the row keeps the same width.
         (note (plist-get node :needs-note))
         ;; Names keep their column while they fit; a long nested name
         ;; pushes its row's columns right rather than being cut.
         (name-width (max 10 (- 25 (* 2 depth))
                          (min 30 (string-width (or (plist-get node :name) "")))))
         (name-width (if note
                         (max 10 (- name-width (1+ (string-width note))))
                       name-width))
         (time (gascity-ui-time (if (equal (alist-get 'status shown) "closed")
                                    (alist-get 'closed_at shown)
                                  (alist-get 'updated_at shown))
                                (plist-get ctx :now)))
         (detail (gascity-ui-fit
                  (if fold
                      (concat (gascity-ui-glyph
                               (pcase state ('done 'done) ('active 'active)
                                      ('failed 'failed) (_ 'pending)))
                              " " (gascity-run--detail node))
                    (gascity-run--detail node))
                  9))
         (detail (if changed (gascity-ui-changed detail) detail))
         ;; A failed step names its failure class where the worker would
         ;; sit: the row is red because of that class, and the full reason
         ;; rides in `help-echo' on the row (ec-elkm5.8).
         (failure-info
          (and (eq state 'failed)
               (let ((failed (plist-get ctx :failed-step)))
                 (if (and failed (equal (plist-get failed :id) id))
                     (cons (plist-get failed :class) (plist-get failed :reason))
                   (gascity-runs--failure-info (list (plist-get node :bead)))))))
         (failure (and failure-info
                       (or (car-safe failure-info) (cdr-safe failure-info))))
         (failure-help (and failure-info
                            (gascity-ui-failure-text failure-info)))
         (left (concat (make-string (+ 2 (* 2 depth)) ?\s)
                       (if fold
                           (gascity-ui-glyph (if open 'expanded 'folded))
                         (gascity-ui-glyph (pcase state
                                             ('done 'done) ('active 'active)
                                             ('failed 'failed) (_ 'pending))))
                       " " (gascity-ui-fit (or (plist-get node :name) "") name-width)
                       " " (gascity-ui-fit id 9)
                       ;; A fold row's first column is its fold marker,
                       ;; so its state glyph leads the detail column.
                       " " detail
                       (if note (concat " " note) "")))
         (left (if failure
                   (concat left "  "
                           (gascity-dashboard--dim
                            (gascity-ui-truncate
                             failure
                             (max 8 (- gascity-dashboard--width 2
                                       (string-width left)
                                       ;; leave the worker its room
                                       (if who 10 0))))))
                 left))
         ;; The worker gets what the row has left before the time.
         (left (if who
                   (let* ((mark (if agent (concat (gascity-ui-glyph 'ok) " ") ""))
                          (name (gascity-ui-truncate
                                 (gascity-runs-agent-name who)
                                 (max 8 (- gascity-dashboard--width 2
                                           (string-width left)
                                           (string-width mark)
                                           (string-width time))))))
                     (concat left " " mark
                             (if changed (gascity-ui-changed name) name)))
                 left))
         (thing-id (concat (if fold "fold:" "step:") id))
         (drawer-id (concat "step:" id))
         (row (apply #'gascity-dashboard--row left (gascity-dashboard--dim time)
                     'gascity-bead id
                     'beads-thing
                     (gascity-dashboard--thing
                      (if fold 'fold 'row) thing-id
                      (lambda () (gascity-dashboard--flip
                                  (if fold :expanded :drawers) thing-id)))
                     (append (and failure-help (list 'help-echo failure-help))
                             (and agent (list 'gascity-agent agent))))))
    (cons row
          (append
           (gascity-run--member-lines (plist-get node :bead) depth ctx)
           (and (gascity-dashboard--drawer-open-p drawer-id)
                (mapcar (lambda (l) (concat (make-string (* 2 depth) ?\s) l))
                        (gascity-dashboard--drawer
                         (gascity-run--step-drawer (plist-get node :bead)
                                                   (and iter (plist-get iter :bead))
                                                   ctx))))
           (and open
                (mapcan (lambda (k) (gascity-run--step-lines k (1+ depth) ctx))
                        (plist-get node :children)))))))

(defun gascity-run--node-map (tree)
  "Return a hash of step bead id → annotated tree node for TREE."
  (let ((map (make-hash-table :test 'equal)))
    (cl-labels ((walk (nodes)
                  (dolist (node nodes)
                    (puthash (alist-get 'id (plist-get node :bead)) node map)
                    (walk (plist-get node :children)))))
      (walk tree))
    map))

(defun gascity-run--work-summary (counts)
  "Return the Work section summary from COUNTS.
Every denominator is labeled; the deliverables phrase is omitted when
the run has no drain members."
  (let ((steps (plist-get counts :steps))
        (deliverables (plist-get counts :deliverables)))
    (string-join
     (delq nil
           (list (format "%d/%d steps" (car steps) (cdr steps))
                 (and (> (cdr deliverables) 0)
                      (format "%d/%d deliverables"
                              (car deliverables) (cdr deliverables)))
                 (format "%d in flight" (plist-get counts :in-flight))
                 (format "%d failed" (plist-get counts :failed))
                 (format "%d beads" (plist-get counts :beads))))
     " · ")))

(defun gascity-run--deliverable-state-word (run)
  "Return the state word of member RUN: active, pass, fail or pending."
  (pcase (plist-get run :state)
    ('active "active")
    ('failed "fail")
    ('done (if (equal (plist-get run :outcome) "fail") "fail"
             (or (plist-get run :outcome) "pass")))
    (_ "pending")))

(defun gascity-run--work-unit-done-p (unit)
  "Return non-nil when work UNIT is done."
  (pcase (plist-get unit :unit-kind)
    (:deliverable
     (let ((member (plist-get unit :member)))
       (and member (eq (gascity-runs-state member) 'done))))
    (:work (eq (plist-get (plist-get unit :step) :state) 'done))
    (_ nil)))

(defun gascity-run--drain-row (unit ctx)
  "Return the drain header row of work UNIT in CTX."
  (let* ((index (plist-get ctx :index))
         (step (plist-get unit :step))
         (id (plist-get step :id))
         (name (or (plist-get step :name) ""))
         (state (plist-get step :state))
         (members (gethash id (plist-get index :deliverables)))
         (total (length members))
         (done (seq-count (lambda (m)
                            (eq (gascity-runs-state (plist-get m :member)) 'done))
                          members))
         (inflight (seq-count (lambda (m)
                                (eq (gascity-runs-state (plist-get m :member)) 'active))
                              members))
         (bead (gascity-runs-bead index id))
         (time (gascity-ui-time (or (alist-get 'updated_at bead)
                                    (alist-get 'created_at bead))
                                (plist-get ctx :now)))
         (left (concat "  " (gascity-runs--state-glyph state) " "
                       (gascity-ui-fit name 25) " "
                       (gascity-ui-fit id 9) "  drain "
                       (format "%d/%d" done total)
                       (if (> inflight 0)
                           (format " · %d in flight" inflight)
                         ""))))
    (gascity-dashboard--row
     left (gascity-dashboard--dim time)
     'gascity-bead id
     'beads-thing (gascity-dashboard--thing
                   'row (concat "step:" id)
                   (lambda () (gascity-dashboard--flip :drawers
                                                       (concat "step:" id)))))))

(defun gascity-run--deliverable-lines (unit ctx)
  "Return the two-line deliverable row of work UNIT in CTX.
The title line carries the business bead's object; the member line
carries the member run's object and its own drawer."
  (let* ((index (plist-get ctx :index))
         (business (plist-get unit :business))
         (business-id (plist-get unit :business-id))
         (member (plist-get unit :member))
         (member-run (and member (gascity-runs-summary index member)))
         (state (if member-run
                    (plist-get member-run :state)
                  (and business (gascity-runs-state business))))
         (glyph (gascity-runs--state-glyph state))
         (number (if (plist-get unit :index)
                     (1+ (plist-get unit :index))
                   nil))
         ;; A business bead missing from the payload is an id-only row:
         ;; never a fabricated title (REQ-003).
         (full-title (or (and business (alist-get 'title business)) ""))
         (status (if business (alist-get 'status business) "(not loaded)"))
         (right (concat (or business-id "") "  " status))
         (prefix (concat "    " glyph " "
                         (if number (format "%d" number) "?") "  "))
         (room (max 1 (- gascity-dashboard--width
                         (string-width prefix) (string-width right) 2)))
         (title (gascity-ui-truncate full-title room))
         (business-thing
          (and business-id
               (gascity-dashboard--thing
                'row (concat "business:" business-id)
                (lambda () (message "Business bead; RET opens it")))))
         (title-line
          (let ((row (gascity-dashboard--row
                      (concat prefix
                              (propertize title
                                          'help-echo full-title))
                      (gascity-dashboard--dim right))))
            ;; The object spans the title and the id/status suffix, so an
            ;; id-only row (no title) still has its business object, and
            ;; no member object is ever added here (REQ-008).
            (when business-id
              (add-text-properties
               (length prefix) (length row)
               (list 'gascity-bead business-id
                     'gascity-run-business t
                     'beads-thing business-thing)
               row))
            row))
         (member-line
          (when member-run
            (let* ((id (plist-get member-run :id))
                   (formula (or (plist-get member-run :formula) ""))
                   (ladder (gascity-dashboard--ladder-string
                            (plist-get member-run :ladder)))
                   (progress (or (plist-get member-run :progress) ""))
                   (word (gascity-run--deliverable-state-word member-run))
                   (label (plist-get member-run :label))
                   (worker (gascity-runs--run-worker member-run ctx))
                   (drawer-id (concat "member:" id))
                   (left (concat "    └ "
                                 (gascity-ui-fit formula 10) " "
                                 (gascity-ui-fit id 9) "  "
                                 ladder " " progress " " word
                                 (if (and label (not (string-empty-p label)))
                                     (concat "  " (gascity-ui-truncate label 18))
                                   "")
                                 (if worker (concat "  " (car worker)) "")))
                   (right (gascity-ui-time (plist-get member-run :time)
                                           (plist-get ctx :now))))
              (cons
               (gascity-dashboard--row
                left (gascity-dashboard--dim right)
                'gascity-run-member id
                'gascity-run-member-rig (plist-get member-run :rig)
                'gascity-bead id
                'beads-thing
                (gascity-dashboard--thing
                 'row drawer-id
                 (lambda () (gascity-dashboard--flip :drawers drawer-id))))
               (and (gascity-dashboard--drawer-open-p drawer-id)
                    (mapcar (lambda (line) (concat "      " line))
                            (gascity-dashboard--drawer
                             (gascity-run--member-drawer member index ctx)))))))))
    (append (list title-line) member-line)))

(defun gascity-run--work-lines (ctx)
  "Return the Work section body of CTX.
One row per work unit in dependency order: a drain header followed by
its deliverables, or a plain work row.  Optional formula stage labels
are inserted above contiguous runs and never reorder, split or hide a
unit.  Above 40 units, done units collapse behind one `◆ N done · show'
row unless CTX's view has :work-done."
  (let* ((index (plist-get ctx :index))
         (root (gascity-run--root-bead ctx))
         (formula (and root (gascity-runs--meta root 'gc.formula_name)))
         (units (and root (gascity-runs-work-units index root)))
         (nodes (gascity-run--node-map (plist-get ctx :tree)))
         (view (plist-get ctx :view))
         (show-done (plist-get view :work-done))
         (done (seq-filter #'gascity-run--work-unit-done-p units))
         (collapse (and (> (length units) 40) (not show-done) done))
         (visible (if collapse
                      (seq-remove #'gascity-run--work-unit-done-p units)
                    units))
         (lines nil)
         (last-stage nil))
    (when collapse
      (push (gascity-dashboard--row
             (concat "  " (gascity-ui-glyph 'done) " "
                     (format "%d done" (length done)) " · show")
             nil
             'beads-thing
             (gascity-dashboard--thing
              'row "work-done"
              (lambda () (gascity-dashboard--set-state
                          :work-done (not (gascity-dashboard--state :work-done))))))
            lines))
    (dolist (unit visible)
      (let* ((step (plist-get unit :step))
             (name (or (plist-get step :name) ""))
             (stage (and formula
                         (gascity-runs--stage-label
                          formula (gascity-run-stage-anchor name)))))
        (when (and stage (not (equal stage last-stage)))
          (push (concat "  " (gascity-dashboard--dim stage)) lines))
        (setq last-stage stage)
        (pcase (plist-get unit :unit-kind)
          (:drain (push (gascity-run--drain-row unit ctx) lines))
          (:deliverable
           (dolist (line (gascity-run--deliverable-lines unit ctx))
             (push line lines)))
          (_
           (let ((node (gethash (plist-get step :id) nodes)))
             (if node
                 (let* ((row (car (gascity-run--step-lines node 0 ctx)))
                        (iter (gascity-run--latest-iteration node))
                        (drawer-id (concat "step:"
                                           (alist-get 'id (plist-get node :bead))))
                        (drawer (and (gascity-dashboard--drawer-open-p drawer-id)
                                     (gascity-dashboard--drawer
                                      (gascity-run--step-drawer
                                       (plist-get node :bead)
                                       (and iter (plist-get iter :bead))
                                       ctx)))))
                   ;; The Work spine shows the unit's own row and drawer;
                   ;; nested steps belong to Machinery.
                   (push row lines)
                   (dolist (line drawer) (push line lines)))
               (push (gascity-dashboard--row
                      (concat "  " (gascity-runs--state-glyph
                                    (plist-get step :state))
                              " " (gascity-ui-fit name 25) " "
                              (gascity-ui-fit (plist-get step :id) 9))
                      nil
                      'gascity-bead (plist-get step :id)
                      'beads-thing (gascity-dashboard--thing
                                    'row (concat "step:" (plist-get step :id))))
                     lines)))))))
    (nreverse lines)))

(defun gascity-run--model (ctx)
  "Return the annotated run model of CTX, or nil when the run is unknown.
Keys: :root the run root bead, :run its `gascity-runs-summary', :graph
its graph beads, :tree the annotated tree `gascity-run-lines' renders."
  (let* ((index (plist-get ctx :index))
         (id (plist-get ctx :run-id))
         (root (seq-find (lambda (r) (equal (alist-get 'id r) id))
                         (plist-get index :roots))))
    (when root
      (let* ((run (gascity-runs-summary index root))
             (graph (gascity-runs-graph index id))
             (tree (gascity-run-annotate
                    (gascity-run-tree root graph
                                      (plist-get (plist-get ctx :view) :control))
                    root graph (plist-get run :ladder))))
        (list :root root :run run :graph graph :tree tree)))))

(defun gascity-run--facts (tree ctx)
  "Return the compared facts of TREE in CTX: an alist STEP-ID → plist.
The plist holds :state (the ladder state), :detail
\(`gascity-run--detail'), :worker (the worker display name) and :attempt
\(the shown bead's attempt, the latest iteration's when it has one).
Pure: no read, no timer."
  (let (facts)
    (cl-labels ((walk (node)
                  (let* ((iter (gascity-run--latest-iteration node))
                         (shown (if iter (plist-get iter :bead)
                                  (plist-get node :bead)))
                         (who (car (gascity-run--worker node ctx))))
                    (push (cons (alist-get 'id (plist-get node :bead))
                                (list :state (gascity-run--node-state node)
                                      :detail (gascity-run--detail node)
                                      :worker (and who
                                                   (gascity-runs-agent-name who))
                                      :attempt (gascity-run--attempt shown)))
                          facts))
                  (mapc #'walk (plist-get node :children))))
      (mapc #'walk tree))
    (nreverse facts)))

(defun gascity-run-lines (ctx)
  "Return every run detail line for render context CTX.
CTX keys: :run-id :now :loads (:beads) :index :sessions :socket
:implementation-convoy :source (the source state plist) :events (the
drawer's events load) :failed-step (the diagnosed failure)
:deltas (a hash of changed step ids) :last-update (the delivery that
last changed the facts) :view (:collapsed :drawers :expanded
:work-done :tree :control).  The page is the source headline, identity,
Work spine, provenance and a folded Machinery section; the stage-group
IA is gone."
  (let* ((gascity-dashboard--view (plist-get ctx :view))
         (id (plist-get ctx :run-id))
         (load (plist-get (plist-get ctx :loads) :beads))
         (model (gascity-run--model ctx)))
    (cond
     (model
      (let* ((root (plist-get model :root))
             (run (plist-get model :run))
             (graph (plist-get model :graph))
             (tree (plist-get model :tree))
             (index (plist-get ctx :index))
             (control (plist-get (plist-get ctx :view) :control))
             (formula (gascity-runs--meta root 'gc.formula_name))
             (tree-view (plist-get (plist-get ctx :view) :tree))
             (needs (and tree-view (gascity-run--needs-map graph formula)))
             (forest (and needs (gascity-run--needs-forest tree needs)))
             (ctx (let ((ctx (plist-put (copy-sequence ctx) :tree tree))
                        (failed (gascity-runs-failed-step index root)))
                    (if failed (plist-put ctx :failed-step failed) ctx)))
             (counts (gascity-runs-unit-counts index root))
             (work (gascity-run--work-lines ctx))
             (provenance (gascity-run--provenance-lines run root ctx))
             (machinery-body
              (if forest
                  (gascity-run--tree-flat-lines forest ctx)
                (mapcan (lambda (n) (gascity-run--step-lines n 0 ctx)) tree)))
             (machinery-summary
              (string-join
               (delq nil
                     (list (if control "control nodes shown (C)"
                             "control nodes folded (C)")
                           (if tree-view "needs tree shown (T)"
                             "needs tree flat (T)")
                           "SPC fold"))
               " · "))
             (machinery
              (gascity-dashboard--section-lines
               "machinery" "Machinery" machinery-summary machinery-body ctx
               :loads '(:beads) :label "bd list")))
        (append
         (gascity-run--header-lines run root ctx)
         (list "")
         (gascity-dashboard--section-lines
          "work" "Work"
          (concat (gascity-run--work-summary counts)
                  (gascity-ui-updated-string (plist-get ctx :last-update)))
          work ctx
          :loads '(:beads) :label "bd list")
         provenance
         machinery
         (list (gascity-dashboard--dim
                "Keys     RET open   SPC drawer   I inspect   w copy   ! diagnose   g refresh   q bury")))))
     ((gascity-dashboard--data load)
      (list (concat (gascity-ui-glyph 'fail) " "
                    (gascity-dashboard--dim
                     (format "run %s not found in the city's stores   g retry" id)))))
     (t
      (append (list (concat (gascity-ui-glyph 'pending) " "
                            (propertize id 'face 'gascity-header))
                    "")
              (gascity-dashboard--section-lines
               "work" "Work" nil nil ctx :loads '(:beads) :label "bd list"))))))

;;; Component

(defun gascity-run--convoy-pair (payload)
  "Return (CONVOY . PROGRESS) from a `gc convoy status' PAYLOAD, or nil."
  (let ((convoy (alist-get 'convoy payload)))
    (and convoy
         (cons convoy (or (alist-get 'progress payload)
                          (alist-get 'progress convoy))))))

(vui-defcomponent gascity-run-app (run-id convoy city)
  "Root component of the run detail for RUN-ID.
CONVOY, when non-nil, is the input-convoy row the caller already holds
\(no convoy read then).  CITY names the city (for the tmux socket)."
  :state ((refresh-tick 0)
          (collapsed '("machinery"))
          (drawers nil)
          (expanded nil)
          (work-done nil)
          (tree nil)
          (control nil))
  :render
  (let* ((beads-res (gascity-runs-use-beads refresh-tick))
         (sessions-res (gascity-store-use '("session" "list") :tick refresh-tick))
         ;; The inspector's recent events: read only while a drawer is
         ;; open, with the cockpit's exact key (same window, line mode),
         ;; so the store dedupes the two reads.
         (events-res (gascity-store-use
                      (and drawers
                           (list "events" "--since"
                                 (gascity-event-since-arg gascity-dashboard-window)))
                      :tick refresh-tick :lines t))
         (last-beads (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         (last-events (vui-use-ref nil))
         ;; Run-view-v3 §D: the compared facts of the last delivery, the
         ;; ids they changed, and the delivery time of that change.
         (previous-facts (vui-use-ref nil))
         (changed-ids (vui-use-ref nil))
         (last-update (vui-use-ref nil))
         (beads-load (gascity-ui-effective-load beads-res last-beads))
         (index (gascity-runs-index
                 (plist-get (gascity-dashboard--data beads-load) :beads)))
         (root (seq-find (lambda (r) (equal (alist-get 'id r) run-id))
                         (plist-get index :roots)))
         (convoy-id (and root
                         (or (gascity-run--meta root 'gc.build.implementation_convoy_id)
                             (gascity-run--meta root 'gc.input_convoy_id))))
         (convoy-res (gascity-store-use (and convoy-id (not convoy)
                                             (list "convoy" "status" convoy-id))
                                        :tick refresh-tick))
         (last-convoy (vui-use-ref nil))
         (convoy-load (gascity-ui-effective-load convoy-res last-convoy))
         ;; The source business bead: `gc.var.convoy_id' is the synthetic
         ;; input convoy the workflow was launched from, whose first
         ;; tracked member is the bead the user slung.  Its `convoy status'
         ;; read goes through the store like every other read; when it is
         ;; the same convoy as the input-convoy row the store dedupes it.
         (source-convoy-id (and root (gascity-run--meta root 'gc.var.convoy_id)))
         (source-res (gascity-store-use
                      (and source-convoy-id
                           (list "convoy" "status" source-convoy-id))
                      :tick refresh-tick))
         (last-source (vui-use-ref nil))
         (source-load (gascity-ui-effective-load source-res last-source))
         (sessions-load (gascity-ui-effective-load sessions-res last-sessions))
         (events-load (gascity-ui-effective-load events-res last-events))
         (ctx (list :run-id run-id :now (float-time)
                    :loads (list :beads beads-load)
                    :events events-load
                    :index index
                    :sessions (append (alist-get 'sessions (gascity-dashboard--data
                                                            sessions-load))
                                      nil)
                    :city city
                    :socket (and city (gascity-resolve-tmux-socket city 'no-probe))
                    :implementation-convoy
                    (or (and convoy (cons convoy (alist-get 'progress convoy)))
                        (gascity-run--convoy-pair
                         (gascity-dashboard--data convoy-load)))
                    :source (gascity-run--source-state source-convoy-id source-load)
                    :view (list :collapsed collapsed :drawers drawers
                                :expanded expanded
                                :work-done work-done
                                :tree tree
                                :control control)))
         (model (gascity-run--model ctx))
         (facts (and model (gascity-run--facts (plist-get model :tree) ctx))))
    (setq ctx (gascity-ui-apply-delta
               ctx previous-facts changed-ids last-update facts
               (plist-get beads-res :updated-at)))
    (vui-text (string-join (gascity-run-lines ctx) "\n"))))

;;; Commands

(defun gascity-run-refresh ()
  "Re-read the run, keeping point, folds and drawers."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No run detail to refresh here")))

(defun gascity-run-visit-file (path)
  "Visit host-local PATH on the city's host (a plan file, the formula).
A local missing file is a clear `user-error' instead of a raw
`file-missing'; a remote path keeps the file-name handler's own error
and is never stat'ed here (a remote city never stats on render, R2)."
  (when (and (gascity-run--local-path-p path) (not (file-exists-p path)))
    (user-error "No such file: %s" path))
  (find-file (gascity-remote-localize-path path)))

(defun gascity-run-open-artifact ()
  "Visit the artifact at point (`o').
An artifact is a line or label carrying the `gascity-run-file' property:
the header's plan and formula-source entries and a step drawer's
artifacts.  RET does the same; `o' makes the action explicit and says
so when point is not on an artifact (run-view-v3 §B, REQ-002)."
  (interactive)
  (let ((file (gascity-run--property-at-point 'gascity-run-file)))
    (unless (and (stringp file) (not (string-empty-p file)))
      (user-error "No artifact at point"))
    (gascity-run-visit-file file)))

(defun gascity-run-activate ()
  "Act on the thing at point: open a step's bead, visit a plan file.
On a drain step's member run, open that run's detail.  RET never folds
\(§5.4)."
  (interactive)
  (let ((file (gascity-run--property-at-point 'gascity-run-file))
        (member (gascity-run--property-at-point 'gascity-run-member))
        (bead (gascity-run--property-at-point 'gascity-bead)))
    (cond (file (gascity-run-visit-file file))
          (member (gascity-run-show member nil
                                    (get-text-property (point) 'gascity-run-member-rig)))
          (bead (gascity-runs-call-with-store
                 (gascity-run--store-rig)
                 (lambda (store) (gascity-beads--show-in-store bead store))))
          ((get-text-property (point) 'gascity-section) nil)
          (t (user-error "Nothing to act on here")))))

(defun gascity-run-root-bead ()
  "Show the run's root bead in beads.el (`b')."
  (interactive)
  (let ((run gascity-run--current-run))
    (gascity-runs-call-with-store
     (gascity-run--store-rig)
     (lambda (store) (gascity-beads--show-in-store run store)))))

(defun gascity-run-toggle-control ()
  "Show or hide the control nodes (spec, scope check, finalize) (`C')."
  (interactive)
  (gascity-dashboard--set-state :control (not (gascity-dashboard--state :control))))

(defun gascity-run-toggle-tree ()
  "Toggle the needs-aware step tree (`T').
The flat dependency-ordered layout is the default and is restored
byte-for-byte when toggled back.  A boolean root state,
not `gascity-dashboard--flip' (which toggles list membership); it
re-renders with no re-read and survives refresh and `!'.  A formula
without edge data falls back to the flat layout unchanged."
  (interactive)
  (gascity-dashboard--set-state :tree (not (gascity-dashboard--state :tree))))

(defun gascity-run--property-at-point (prop)
  "Return text property PROP at point, or at the last character of the line.
Point at the end of a row then names the character before it, which is
how `re-search-forward' leaves point after matching a whole line."
  (or (get-text-property (point) prop)
      (and (> (point) (point-min))
           (get-text-property (1- (point)) prop))))

(defun gascity-run-copy-id ()
  "Copy the bead id at point to the kill ring (`w').
On a step row that is the step's bead; on the inspector's iteration
line it is the iteration bead's id; on a `└ …' drain-member row it is
the member's root id."
  (interactive)
  (let ((id (gascity-run--property-at-point 'gascity-bead)))
    (unless (and (stringp id) (not (string-empty-p id)))
      (user-error "No bead id here"))
    (kill-new id)
    (message "Copied %s" id)))

(defun gascity-run-inspect ()
  "Toggle the inspector drawer for the row at point (`I').
On a `└ …' drain-member row the drawer is the member's own summary,
keyed `member:<id>', so a member row is never reported as no step.  On
a step it opens the step inspector; works on a leaf row and on a fold
row (where SPC keeps folding)."
  (interactive)
  (let* ((business (gascity-run--property-at-point 'gascity-run-business))
         (member (gascity-run--property-at-point 'gascity-run-member))
         (thing (gascity-run--property-at-point 'beads-thing))
         (id (gascity-run--property-at-point 'gascity-bead)))
    (cond
     (business (message "Business bead; RET opens it"))
     ((and (stringp member) (not (string-empty-p member)))
      (gascity-dashboard--flip :drawers (concat "member:" member)))
     ((and (stringp id)
           (memq (plist-get thing :kind) '(row fold)))
      (gascity-dashboard--flip :drawers (concat "step:" id)))
     (t (user-error "No step here")))))

;;; Web handoff (run-view-v3 §C, REQ-004)

(defun gascity-run-web-url (run-id city &optional base)
  "Return the web dashboard URL of run RUN-ID in CITY, or nil.
BASE defaults to `gascity-dashboard-url'.  A nil or empty BASE, CITY or
RUN-ID yields nil: gascity never guesses a host.  Trailing slashes are
trimmed from BASE, then the verified route
`/city/<city>/runs/<run-id>' is appended with both segments
percent-encoded.  No scope query is added: this builder cannot derive
one, and the web app appends it only when the scope resolves."
  (let ((base (or base gascity-dashboard-url))
        (city (and city (string-trim city)))
        (run-id (and run-id (string-trim run-id))))
    (when (and (stringp base)
               city (not (string-empty-p city))
               run-id (not (string-empty-p run-id)))
      (let ((base (string-trim-right (string-trim base) "/+")))
        (and (not (string-empty-p base))
             (concat base
                     "/city/" (url-hexify-string city)
                     "/runs/" (url-hexify-string run-id)))))))

(defun gascity-run--web-url ()
  "Return this buffer's run URL, or nil when the dashboard is unconfigured."
  (unless gascity-run--current-run
    (user-error "No run detail here"))
  (gascity-run-web-url gascity-run--current-run gascity-run--city))

(defun gascity-run-browse-url ()
  "Open the current run in the configured web dashboard (`B').
The URL is `gascity-run-web-url' for this run; without a configured
`gascity-dashboard-url' nothing is opened and the echo area says how to
configure it."
  (interactive)
  (let ((url (gascity-run--web-url)))
    (if url
        (progn (browse-url url) (message "%s" url))
      (message "No dashboard URL configured; set gascity-dashboard-url"))))

(defun gascity-run-copy-url ()
  "Copy the current run's web dashboard URL (`Y').
Uses the same URL as `B'; without a configured `gascity-dashboard-url'
nothing is copied and the echo area says how to configure it."
  (interactive)
  (let ((url (gascity-run--web-url)))
    (if url
        (progn (kill-new url) (message "Copied %s" url))
      (message "No dashboard URL configured; set gascity-dashboard-url"))))

;;; Diagnose (run-view-v2 §3, absorbs ga-32wpi)

(defun gascity-run--stored-index ()
  "Return the run index from the store peek, or nil.
The run-beads payload the detail rendered is read from the store: the
command never spawns gc, so `!' stays non-blocking."
  (let ((beads (plist-get (gascity-store-peek gascity-runs-read-key) :beads)))
    (and beads (gascity-runs-index beads))))

(defun gascity-run--stored-run ()
  "Return (INDEX . ROOT) for this buffer's run from the store, or nil."
  (let* ((index (gascity-run--stored-index))
         (id gascity-run--current-run)
         (root (and index
                    (seq-find (lambda (bead)
                                (equal (alist-get 'id bead) id))
                              (plist-get index :roots)))))
    (and root (cons index root))))

(defun gascity-run--store-rig ()
  "Return the rig store of this run, or nil for the city store.
Prefer the rig `gascity-run-show' was called with (a run opened from
`gascity-runs' then needs no store read).  With none — a run opened by
id via `M-x gascity-run-show' — the rendered run-beads payload stamps
every bead with the rig store it came from (`gascity-rig'), and the run
root's stamp is the store its step beads live in too."
  (or gascity-run--current-rig
      (let ((root (cdr (gascity-run--stored-run))))
        (and root (alist-get 'gascity-rig root)))))

(defun gascity-run--failed-chain (node)
  "Return NODE followed by its deepest failed child chain.
The last node is where the failure actually lives; the nodes before it
are the folds that must be opened for that row to show."
  (let ((child (seq-find (lambda (n) (eq (plist-get n :state) 'failed))
                         (plist-get node :children))))
    (if child
        (cons node (gascity-run--failed-chain child))
      (list node))))

(defun gascity-run--node-chain (nodes id)
  "Return the tree path of bead ID in NODES, or nil.
A list of nodes from the top-level anchor down to ID."
  (let (found)
    (cl-labels ((walk (list chain)
                  (dolist (node list)
                    (let ((chain (cons node chain)))
                      (when (and (null found)
                                 (equal (alist-get 'id (plist-get node :bead))
                                        id))
                        (setq found (nreverse chain)))
                      (walk (plist-get node :children) chain)))))
      (walk nodes nil))
    found))

(defun gascity-run--update-view (&rest plist)
  "Set the root view keys in PLIST and re-render once."
  (when-let* ((root (gascity-dashboard--root)))
    (let ((state (vui-instance-state root)))
      (while plist
        (setq state (plist-put state (pop plist) (pop plist))))
      (setf (vui-instance-state root) state)
      (vui-flush-sync))))

(defun gascity-run--goto-row (id)
  "Move point to the step row of bead ID; return non-nil when found.
Drawer and header lines also carry `gascity-bead', so only a row or
fold thing counts as the step's row."
  (goto-char (point-min))
  (let ((pos (point-min)) (found nil))
    (while (and (not found) (< pos (point-max)))
      (when (and (equal (get-text-property pos 'gascity-bead) id)
                 (memq (plist-get (get-text-property pos 'beads-thing) :kind)
                       '(row fold)))
        (goto-char pos)
        (setq found t))
      (unless found
        (setq pos (next-single-property-change
                   pos 'gascity-bead nil (point-max)))))
    found))

(defun gascity-run--diagnose-message (failed)
  "Return the echo-area text for the failure plist FAILED."
  (let ((class (plist-get failed :class))
        (reason (plist-get failed :reason)))
    (concat (gascity-ui-glyph 'failed) " "
            (or (plist-get failed :ref) (plist-get failed :name) "?")
            (cond ((and class reason) (format "  %s: %s" class reason))
                  (class (format "  %s" class))
                  (reason (format "  %s" reason))
                  (t "")))))

(defun gascity-run--diagnose-member (member)
  "Echo the diagnosis of the drain-member run MEMBER (`!').
The member's own graph supplies the failed step; a healthy member is a
clear `user-error'.  Point and the buffer are left alone: the member's
steps are a separate graph, and RET is what drills in."
  (let* ((index (gascity-run--stored-index))
         (root (and index
                    (seq-find (lambda (bead)
                                (equal (alist-get 'id bead) member))
                              (plist-get index :roots))))
         (failed (and root (gascity-runs-failed-step index root))))
    (unless index
      (user-error "Run data is not loaded"))
    (unless root
      (user-error "Member run is not loaded"))
    (unless failed
      (user-error "Member run has no failed step"))
    (message "%s" (truncate-string-to-width
                    (gascity-run--diagnose-message failed)
                    (max 20 (- (frame-width) 2)) nil nil "…"))))

(defun gascity-run--diagnose-run ()
  "Jump to this buffer's run failed step and open its inspector (`!').
Expands the folded Machinery section and the folded loops above the
actual failure, opens the step's drawer, moves point to its row and
echoes `✕ REF  CLASS: REASON' truncated to the echo area.  When the row
cannot be located, point lands at the top of the buffer.  No failed
step is a `user-error'."
  (unless gascity-run--current-run
    (user-error "No run detail here"))
  (let* ((stored (gascity-run--stored-run))
         (index (car stored))
         (root (cdr stored))
         (failed (and root (gascity-runs-failed-step index root))))
    (unless failed
      (user-error "Run has no failed step"))
    (let* ((id (plist-get failed :id))
           (graph (gascity-runs-graph index (alist-get 'id root)))
           (run (gascity-runs-summary index root))
           (control (gascity-dashboard--state :control))
           (tree (gascity-run-annotate
                  (gascity-run-tree root graph control) root graph
                  (plist-get run :ladder)))
           (chain* (gascity-run--node-chain tree id))
           ;; The folds to open: the failed step's own fold plus every
           ;; nested loop down to the bead that actually failed.
           (chain (if chain*
                      (append (butlast chain*)
                              (gascity-run--failed-chain (car (last chain*))))
                    nil))
           (expanded (gascity-dashboard--state :expanded))
           (collapsed (remove "machinery" (gascity-dashboard--state :collapsed)))
           (drawers (gascity-dashboard--state :drawers)))
      (dolist (node chain)
        (when (gascity-run--fold-p node)
          (let ((key (concat "fold:" (alist-get 'id (plist-get node :bead)))))
            (unless (gascity-run--open-p node (list :expanded expanded))
              (if (gascity-run--busy-p node)
                  (setq expanded (remove key expanded))
                (setq expanded (cons key expanded)))))))
      (unless (member (concat "step:" id) drawers)
        (setq drawers (cons (concat "step:" id) drawers)))
      (gascity-run--update-view :expanded expanded
                                :collapsed collapsed
                                :drawers drawers)
      (unless (gascity-run--goto-row id)
        (goto-char (point-min)))
      (message "%s" (truncate-string-to-width
                      (gascity-run--diagnose-message failed)
                      (max 20 (- (frame-width) 2)) nil nil "…")))))

(defun gascity-run-diagnose ()
  "Diagnose the run (or drain-member run) at point (`!').
On a `└ …' member row, echo the member's own failed step, class and
reason without moving point or opening another buffer; a healthy member
is a clear `user-error'.  Elsewhere jump to the run's failed step and
open its inspector, as `gascity-run--diagnose-run' documents.  The
member's steps are a separate graph, so RET still drills in."
  (interactive)
  (let ((business (gascity-run--property-at-point 'gascity-run-business))
        (member (gascity-run--property-at-point 'gascity-run-member)))
    (cond
     (business (message "Business bead; RET opens it"))
     ((and (stringp member) (not (string-empty-p member)))
      (gascity-run--diagnose-member member))
     (t (gascity-run--diagnose-run)))))

;;; Mode

(defvar-keymap gascity-run-mode-map
  :doc "Keymap for `gascity-run-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-run-refresh
  "RET" #'gascity-run-activate
  "o"   #'gascity-run-open-artifact
  "b"   #'gascity-run-root-bead
  "C"   #'gascity-run-toggle-control
  "T"   #'gascity-run-toggle-tree
  "I"   #'gascity-run-inspect
  "w"   #'gascity-run-copy-id
  "B"   #'gascity-run-browse-url
  "Y"   #'gascity-run-copy-url
  "!"   #'gascity-run-diagnose
  "i"   #'gascity-runs-agent-detail
  "v"   #'gascity-runs-agent-peek
  "t"   #'gascity-runs-agent-tmux)

(define-derived-mode gascity-run-mode gascity-section-mode "GC-Run"
  "Major mode for the run detail (dashboard-v3 §7.7).

The page is the source headline, an identity line, the Work spine (one
row per work unit, a deliverable's business bead above its member run),
labelled provenance, and the folded Machinery section.

TAB/S-TAB move between things, SPC folds a section or a loop or opens a
step's or member's drawer; on a deliverable's business half it says
that RET opens the bead and never acts on the member.  RET opens the
bead, artifact or member run at point (`o' visits the artifact at point
explicitly), `b' the root bead, `C' shows the control nodes inside
Machinery, `T' toggles its needs-aware tree, and `I' toggles the
inspector for a step or member row (business halves say so honestly).

On a `└ …' drain-member row, `I' opens an in-place member drawer (the
member's root, formula, progress, worker and failure), `w' copies the
member's root bead id and `!' echoes the member's own failed step,
class and reason without moving point or opening a buffer; a healthy
member says so.  RET still drills into the member's run detail.

Elsewhere `w' copies the step's bead id (the iteration id on the
inspector's iteration line), `B' opens the current run in the
configured web dashboard and `Y' copies that URL (`W' stays the live
toggle), and `!' reveals and diagnoses the run's failed step by
expanding the folded Machinery section and any folded loop above it,
opening its inspector and echoing the failure class and reason.  The i, v and t
keys reach a step's live worker (detail, snapshot peek, live attach)
from a row or from an inspector line.

\\{gascity-run-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              '(:eval (gascity-runs-header-line
                       (concat "Run " (or gascity-run--current-run ""))
                       gascity-run--city))))

;;;###autoload
(defun gascity-run-show (run &optional convoy rig)
  "Show the workflow run whose root bead id is RUN.
CONVOY, when non-nil, is the implementation-convoy row the caller
already loaded (no convoy read then).  RIG names the run's rig store
\(nil: the city store); RET and `b' open beads there.  The buffer
`*gascity-run: RUN*' is created through `gascity-view-get-buffer-create'
\(host-qualified, pinned to the city); showing the same run again
refreshes it in place."
  (interactive
   (list (or (gascity-bead-at-point)
             (read-string "Run root bead id: "))))
  (setq run (and (stringp run) (string-trim run)))
  (unless (and run (not (string-empty-p run)))
    (user-error "No run root bead id"))
  (let* ((dir (gascity-context-city-for-view))
         (city (gascity-context-city-name dir))
         (buf (gascity-view-get-buffer-create (format gascity-run-buffer-name run) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-run-mode)
        (gascity-run-mode))
      (setq gascity-run--current-run run
            gascity-run--current-rig rig
            gascity-run--city city))
    (unless (gascity-section-refresh-instance buf)
      (save-window-excursion
        (vui-mount (vui-component 'gascity-run-app
                                  :run-id run :convoy convoy :city city)
                   (buffer-name buf))))
    (pop-to-buffer buf)))

(provide 'gascity-run)
;;; gascity-run.el ends here
