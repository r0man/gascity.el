;;; gascity-run.el --- Run detail: one workflow run's steps -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The run detail (plans/dashboard-v3 §7.7), `*gascity-run: ID*', the
;; drill-in behind a run row of the cockpit and the Runs view:
;;
;;   ⬣ be-52m5  build-basic                       beads.el · started 2h
;;     formula  build-basic (graph.v2)   source ~/.gc/cache/…/build-basic.formula.toml
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
;; on the city's host (`gascity-remote-localize-path', §8.3 R6).
;;
;; Reads: the Runs view's shared run-beads entry (`gascity-runs-use-beads',
;; so opening a run from Runs costs no gc call), `session list' for the
;; live assignees, `convoy status ID' for the input convoy.  All through
;; the store; the render is pure (§8.3 R2).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vui)
(require 'beads-thing)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-context)
(require 'gascity-remote)
(require 'gascity-store)
(require 'gascity-section)
(require 'gascity-dashboard)
(require 'gascity-runs)

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

(defun gascity-run-plans (root)
  "Return the plan files of run ROOT: a list of (KEY . PATH), host-local.
Every `gc.build.*_path' / `gc.implementation.*_path' metadata with a
value, each path once, in metadata order.  A relative path (some
formulas record `plans/…/review-report.md') is relative to the run's
`gc.work_dir'; joined as strings, no file name handler (R2)."
  (let ((seen nil) (out nil)
        (work-dir (gascity-run--meta root 'gc.work_dir)))
    (dolist (cell (alist-get 'metadata root))
      (let ((key (symbol-name (car cell))) (path (cdr cell)))
        (when (and (stringp path) (not (string-empty-p path))
                   (not (string-prefix-p "/" path))
                   (stringp work-dir) (string-prefix-p "/" work-dir))
          (setq path (concat (file-name-as-directory work-dir) path)))
        (when (and (string-match-p "\\`gc\\.\\(build\\|implementation\\)\\..*_path\\'" key)
                   (stringp path) (not (string-empty-p path))
                   (not (member path seen)))
          (push path seen)
          (push (cons key path) out))))
    (nreverse out)))

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

(defun gascity-run--header-lines (run root ctx)
  "Return the header lines of RUN (a summary) with ROOT in CTX."
  (let* ((now (plist-get ctx :now))
         (state (plist-get run :state))
         (source (gascity-run--meta root 'gc.formula_source))
         (contract (gascity-run--meta root 'gc.formula_contract))
         (plans (gascity-run-plans root))
         (convoy (plist-get ctx :convoy))
         (lines
          (list
           (gascity-dashboard--row
            (concat (gascity-runs--state-glyph state) " "
                    (propertize (plist-get run :id) 'face 'gascity-header) "  "
                    (plist-get run :formula)
                    (if (plist-get run :outcome)
                        (concat "  " (gascity-dashboard--dim (plist-get run :outcome)))
                      ""))
            (gascity-dashboard--dim
             (format "%s · %s %s" (or (plist-get run :rig) "city")
                     (if (memq state '(done failed)) "closed" "started")
                     (gascity-ui-time (plist-get run :time) now)))
            'gascity-bead (plist-get run :id)
            'beads-thing (gascity-dashboard--thing 'row "root"))
           (concat "  " (gascity-dashboard--dim "formula  ")
                   (plist-get run :formula)
                   (if contract (gascity-dashboard--dim (format " (%s)" contract)) "")
                   (if source
                       (concat "   " (gascity-dashboard--dim "source ")
                               (gascity-run--file-thing
                                source (gascity-run--short-path source)))
                     "")))))
    (when plans
      (let ((row (concat "  " (gascity-dashboard--dim "plans    ")))
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
        (setq lines (append lines (list row)))))
    (when convoy
      (let* ((c (car convoy))
             (progress (cdr convoy))
             (id (alist-get 'id c)))
        (setq lines
              (append
               lines
               (list (gascity-dashboard--line
                      (concat "  " (gascity-dashboard--dim "convoy   ")
                              id "  " (or (alist-get 'status c) "")
                              (if progress
                                  (format " %s/%s" (or (alist-get 'closed progress) "?")
                                          (or (alist-get 'total progress) "?"))
                                "")
                              "  " (gascity-dashboard--dim (or (alist-get 'title c) "")))
                      'gascity-bead id
                      'beads-thing (gascity-dashboard--thing 'row "convoy")))))))
    lines))

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

(defun gascity-run--step-drawer (step &optional iteration)
  "Return the drawer lines of STEP and its latest ITERATION bead.
All from the payload in hand; the iteration's status, assignee and
failure are what the worker is on, so they come from it when present."
  (let* ((bead (or iteration step))
         (meta (alist-get 'metadata bead)))
    (delq nil
          (list (string-join
                 (delq nil (list (alist-get 'status bead)
                                 (and (alist-get 'gc.outcome meta)
                                      (concat "outcome " (alist-get 'gc.outcome meta)))
                                 (and (alist-get 'gc.attempt meta)
                                      (format "attempt %s" (alist-get 'gc.attempt meta)))
                                 (and (alist-get 'gc.kind meta)
                                      (concat "kind " (alist-get 'gc.kind meta)))))
                 " · ")
                (and iteration
                     (format "iteration %s (attempt %s) of step %s"
                             (alist-get 'id iteration)
                             (or (alist-get 'gc.attempt meta) "?")
                             (alist-get 'id step)))
                (and (alist-get 'gc.step_ref meta)
                     (concat "ref      " (alist-get 'gc.step_ref meta)))
                (and (alist-get 'assignee bead)
                     (concat "assignee " (alist-get 'assignee bead)))
                (and (alist-get 'gc.failure_reason meta)
                     (concat "failure  " (alist-get 'gc.failure_reason meta)))
                (and (alist-get 'title bead)
                     (concat "title    " (alist-get 'title bead)))))))

(defun gascity-run--member-lines (step depth ctx)
  "Return the rows of the member runs drain STEP at DEPTH fans out to.
A drain step stays open while its member runs (roots naming it in
`gc.drain_control_id', the :drains of CTX's :index) work outside this
run's graph: each gets a row with its ladder, RET opens its run detail."
  (let ((index (plist-get ctx :index)))
    (mapcar
     (lambda (member)
       (let* ((run (gascity-runs-summary index member))
              (id (plist-get run :id)))
         (gascity-dashboard--row
          (concat (make-string (+ 4 (* 2 depth)) ?\s) "└ "
                  (gascity-runs--state-glyph (plist-get run :state)) " "
                  (gascity-ui-fit id 9) " "
                  (gascity-ui-fit (plist-get run :formula) 10) " "
                  (gascity-dashboard--ladder-string (plist-get run :ladder)) "  "
                  (gascity-ui-fit (plist-get run :label) 14) " "
                  (plist-get run :progress))
          (gascity-dashboard--dim "RET run")
          'gascity-run-member id
          'gascity-run-member-rig (plist-get run :rig)
          'beads-thing (gascity-dashboard--thing 'row (concat "sub:" id)))))
     (reverse (gethash (alist-get 'id step) (plist-get index :drains))))))

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
         (assignee (alist-get 'assignee shown))
         (session (gascity-dashboard--session-for-assignee
                   assignee (plist-get ctx :sessions)))
         (who (cond (session (alist-get 'agent_name session))
                    (assignee (car (gascity-dashboard--parse-assignee assignee)))))
         (agent (and session (gascity-dashboard--agent-object
                              who session (plist-get ctx :socket))))
         ;; Names keep their column while they fit; a long nested name
         ;; pushes its row's columns right rather than being cut.
         (name-width (max 10 (- 25 (* 2 depth))
                          (min 30 (string-width (or (plist-get node :name) "")))))
         (time (gascity-ui-time (if (equal (alist-get 'status shown) "closed")
                                    (alist-get 'closed_at shown)
                                  (alist-get 'updated_at shown))
                                (plist-get ctx :now)))
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
                       " " (gascity-ui-fit
                            (if fold
                                (concat (gascity-ui-glyph
                                         (pcase state ('done 'done) ('active 'active)
                                                ('failed 'failed) (_ 'pending)))
                                        " " (gascity-run--detail node))
                              (gascity-run--detail node))
                            9)))
         ;; The worker gets what the row has left before the time.
         (left (if who
                   (let ((mark (if session (concat (gascity-ui-glyph 'ok) " ") "")))
                     (concat left " " mark
                             (gascity-ui-truncate
                              (gascity-runs-agent-name who)
                              (max 8 (- gascity-dashboard--width 2 (string-width left)
                                        (string-width mark) (string-width time))))))
                 left))
         (thing-id (concat (if fold "fold:" "step:")
                           (alist-get 'id (plist-get node :bead))))
         (row (apply #'gascity-dashboard--row left (gascity-dashboard--dim time)
                     'gascity-bead id
                     'beads-thing
                     (gascity-dashboard--thing
                      (if fold 'fold 'row) thing-id
                      (lambda () (gascity-dashboard--flip
                                  (if fold :expanded :drawers) thing-id)))
                     (and agent (list 'gascity-agent agent)))))
    (cons row
          (append
           (gascity-run--member-lines (plist-get node :bead) depth ctx)
           (and (not fold) (gascity-dashboard--drawer-open-p thing-id)
                (mapcar (lambda (l) (concat (make-string (* 2 depth) ?\s) l))
                        (gascity-dashboard--drawer
                         (gascity-run--step-drawer (plist-get node :bead)
                                                   (and iter (plist-get iter :bead))))))
           (and open
                (mapcan (lambda (k) (gascity-run--step-lines k (1+ depth) ctx))
                        (plist-get node :children)))))))

(defun gascity-run-lines (ctx)
  "Return every run detail line for render context CTX.
CTX keys: :run-id :now :loads (:beads) :index :sessions :socket :convoy
:view (:collapsed :drawers :expanded :control)."
  (let* ((gascity-dashboard--view (plist-get ctx :view))
         (id (plist-get ctx :run-id))
         (index (plist-get ctx :index))
         (load (plist-get (plist-get ctx :loads) :beads))
         (root (seq-find (lambda (r) (equal (alist-get 'id r) id))
                         (plist-get index :roots))))
    (cond
     (root
      (let* ((run (gascity-runs-summary index root))
             (control (plist-get (plist-get ctx :view) :control))
             (graph (gascity-runs-graph index id))
             (tree (gascity-run-annotate
                    (gascity-run-tree root graph control) root graph
                    (plist-get run :ladder))))
        (append
         (gascity-run--header-lines run root ctx)
         (list "")
         (gascity-dashboard--section-lines
          "steps" "Steps" (plist-get run :progress)
          (mapcan (lambda (n) (gascity-run--step-lines n 0 ctx)) tree)
          ctx :loads '(:beads) :label "bd list"
          :hint (if control "C hide control nodes" "C show control nodes")))))
     ((gascity-dashboard--data load)
      (list (concat (gascity-ui-glyph 'fail) " "
                    (gascity-dashboard--dim
                     (format "run %s not found in the city's stores   g retry" id)))))
     (t
      (append (list (concat (gascity-ui-glyph 'pending) " "
                            (propertize id 'face 'gascity-header))
                    "")
              (gascity-dashboard--section-lines
               "steps" "Steps" nil nil ctx :loads '(:beads) :label "bd list"))))))

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
          (collapsed nil)
          (drawers nil)
          (expanded nil)
          (control nil))
  :render
  (let* ((beads-res (gascity-runs-use-beads refresh-tick))
         (sessions-res (gascity-store-use '("session" "list") :tick refresh-tick))
         (last-beads (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         (beads-load (gascity-ui-effective-load beads-res last-beads))
         (index (gascity-runs-index
                 (plist-get (gascity-dashboard--data beads-load) :beads)))
         (root (seq-find (lambda (r) (equal (alist-get 'id r) run-id))
                         (plist-get index :roots)))
         (convoy-id (and root (gascity-run--meta root 'gc.input_convoy_id)))
         (convoy-res (gascity-store-use (and convoy-id (not convoy)
                                             (list "convoy" "status" convoy-id))
                                        :tick refresh-tick))
         (last-convoy (vui-use-ref nil))
         (convoy-load (gascity-ui-effective-load convoy-res last-convoy))
         (sessions-load (gascity-ui-effective-load sessions-res last-sessions))
         (ctx (list :run-id run-id :now (float-time)
                    :loads (list :beads beads-load)
                    :index index
                    :sessions (append (alist-get 'sessions (gascity-dashboard--data
                                                            sessions-load))
                                      nil)
                    :socket (and city (gascity-resolve-tmux-socket city 'no-probe))
                    :convoy (or (and convoy (cons convoy (alist-get 'progress convoy)))
                                (gascity-run--convoy-pair
                                 (gascity-dashboard--data convoy-load)))
                    :view (list :collapsed collapsed :drawers drawers
                                :expanded expanded :control control))))
    (vui-text (string-join (gascity-run-lines ctx) "\n"))))

;;; Commands

(defun gascity-run-refresh ()
  "Re-read the run, keeping point, folds and drawers."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No run detail to refresh here")))

(defun gascity-run-visit-file (path)
  "Visit host-local PATH on the city's host (a plan file, the formula)."
  (find-file (gascity-remote-localize-path path)))

(defun gascity-run-activate ()
  "Act on the thing at point: open a step's bead, visit a plan file.
On a drain step's member run, open that run's detail.  RET never folds
\(§5.4)."
  (interactive)
  (let ((file (get-text-property (point) 'gascity-run-file))
        (member (get-text-property (point) 'gascity-run-member))
        (bead (get-text-property (point) 'gascity-bead)))
    (cond (file (gascity-run-visit-file file))
          (member (gascity-run-show member nil
                                    (get-text-property (point) 'gascity-run-member-rig)))
          (bead (gascity-runs-call-with-store
                 gascity-run--current-rig
                 (lambda (store) (gascity-beads--show-in-store bead store))))
          ((get-text-property (point) 'gascity-section) nil)
          (t (user-error "Nothing to act on here")))))

(defun gascity-run-root-bead ()
  "Show the run's root bead in beads.el (`b')."
  (interactive)
  (let ((run gascity-run--current-run))
    (gascity-runs-call-with-store
     gascity-run--current-rig
     (lambda (store) (gascity-beads--show-in-store run store)))))

(defun gascity-run-toggle-control ()
  "Show or hide the control nodes (spec, scope check, finalize) (`C')."
  (interactive)
  (gascity-dashboard--set-state :control (not (gascity-dashboard--state :control))))

;;; Mode

(defvar-keymap gascity-run-mode-map
  :doc "Keymap for `gascity-run-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-run-refresh
  "RET" #'gascity-run-activate
  "b"   #'gascity-run-root-bead
  "C"   #'gascity-run-toggle-control
  "i"   #'gascity-runs-agent-detail
  "v"   #'gascity-runs-agent-peek
  "t"   #'gascity-runs-agent-tmux)

(define-derived-mode gascity-run-mode gascity-section-mode "GC-Run"
  "Major mode for the run detail (dashboard-v3 §7.7).

TAB/S-TAB move between steps, SPC folds a loop or opens a step's
drawer, RET opens the step's bead or visits a plan file, `b' the root
bead, `C' shows the control nodes, and the i, v and t keys reach a
step's live worker.

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
CONVOY, when non-nil, is the input-convoy row the caller already
loaded (no convoy read then).  RIG names the run's rig store (nil: the
city store); RET and `b' open beads there.  The buffer
`*gascity-run: RUN*' is created through `gascity-view-get-buffer-create'
\(host-qualified, pinned to the city); showing the same run again
refreshes it in place."
  (interactive
   (list (or (gascity-bead-at-point)
             (read-string "Run root bead id: "))))
  (setq run (and (stringp run) (string-trim run)))
  (unless (and run (not (string-empty-p run)))
    (user-error "No run root bead id"))
  (let* ((city (gascity-context-city-name))
         (buf (gascity-view-get-buffer-create (format gascity-run-buffer-name run))))
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
