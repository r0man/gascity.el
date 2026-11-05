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
;; live assignees, `convoy status ID' for the input convoy, and
;; `events --since' only while a drawer is open.  All through the store;
;; the render is pure (§8.3 R2).

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
    (gascity-run--failure-string info)))

(defun gascity-run--failure-string (info)
  "Return failure INFO (CLASS . REASON) as text, `(none)' when healthy.
CLASS and REASON are joined `class: reason'; either alone is shown as
is.  The step inspector and the attempt history share this shape."
  (cond ((and (car info) (cdr info)) (format "%s: %s" (car info) (cdr info)))
        ((car info) (car info))
        ((cdr info) (cdr info))
        (t "(none)")))

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
                     (gascity-run--failure-string
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
     (list (concat "failure  " (gascity-run--failure-text step iteration ctx))))))

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

;;; Stage groups (run-view-v2 §2)

(defun gascity-run--control-nodes (nodes)
  "Return the control nodes of tree NODES at every depth, in tree order."
  (mapcan (lambda (node)
            (append (and (gascity-run--control-p (plist-get node :bead))
                         (list node))
                    (gascity-run--control-nodes (plist-get node :children))))
          nodes))

(defun gascity-run--control-group (tree)
  "Return the trailing stage group of TREE's control nodes.
The group exists so `C' can show the control nodes of a mapped run in
one place; it is separate from the formula stages, so it never counts
in their progress."
  (let ((nodes (gascity-run--control-nodes tree)))
    (list :key "control" :label "Control"
          :state (gascity-run-stage-state nodes)
          :done (seq-count (lambda (node)
                             (eq (gascity-run--node-state node) 'done))
                           nodes)
          :total (length nodes)
          :anchors nodes)))

(defvar gascity-run-stage--label-width 14
  "Width of the stage label column in the run detail.")

(defun gascity-run-stage-header-line (group ctx)
  "Return the header row of stage GROUP in render context CTX.
GROUP is one of `gascity-run-stage-groups' plists.  The row is a fold
thing keyed `stage:<KEY>': SPC flips its membership in CTX's
:stage-collapsed list, so stages start open and fold independently of
the step folds.  A failed stage appends the dim word `failed' and
carries its failure class and members' name/state pairs in
`help-echo'; the Control group is non-foldable when it is empty."
  (let* ((key (plist-get group :key))
         (members (plist-get group :anchors))
         (state (plist-get group :state))
         (thing (concat "stage:" key))
         (foldable (or members (not (equal key "control"))))
         (collapsed (and foldable
                         (member thing
                                 (plist-get (plist-get ctx :view)
                                            :stage-collapsed))))
         (failed-step (plist-get ctx :failed-step))
         (failure (and (eq state 'failed)
                       failed-step
                       (member (plist-get failed-step :id)
                               (mapcar (lambda (node)
                                         (alist-get 'id (plist-get node :bead)))
                                       members))
                       failed-step))
         (help
          (and (eq state 'failed)
               (string-join
                (delq nil
                      (list (and failure
                                 (let ((class (plist-get failure :class))
                                       (reason (plist-get failure :reason)))
                                   (cond ((and class reason) (concat class ": " reason))
                                         (t (or class reason)))))
                            (and members
                                 (mapconcat
                                  (lambda (node)
                                    (format "%s %s"
                                            (or (plist-get node :name) "")
                                            (gascity-run--node-state node)))
                                  members ", "))))
                " · "))))
    (gascity-dashboard--row
     (concat "  "
             (if foldable
                 (gascity-ui-glyph (if collapsed 'folded 'expanded))
               " ")
             " " (gascity-run-stage-glyph state) " "
             (gascity-ui-fit (or (plist-get group :label) "")
                             gascity-run-stage--label-width)
             " " (gascity-dashboard--dim
                  (format "%d/%d" (plist-get group :done)
                          (plist-get group :total)))
             (if (eq state 'failed)
                 (concat "  " (gascity-dashboard--dim "failed"))
               ""))
     nil
     'gascity-run-stage key
     'help-echo help
     'beads-thing
     (and foldable
          (gascity-dashboard--thing
           'fold thing
           (lambda () (gascity-dashboard--flip :stage-collapsed thing)))))))

(defun gascity-run--stage-lines (groups ctx)
  "Return the rows of stage GROUPS in render context CTX.
Each group emits its `gascity-run-stage-header-line' then, unless the
stage is collapsed, its members through the existing
`gascity-run--step-lines' at depth 1: columns, drawers, drain-member
rows, RET and the step fold machinery are inherited, not duplicated."
  (let ((lines nil)
        (collapsed (plist-get (plist-get ctx :view) :stage-collapsed)))
    (dolist (group groups)
      (push (gascity-run-stage-header-line group ctx) lines)
      (unless (member (concat "stage:" (plist-get group :key)) collapsed)
        (dolist (node (plist-get group :anchors))
          (dolist (line (gascity-run--step-lines node 1 ctx))
            (push line lines)))))
    (nreverse lines)))

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
         (thing-id (concat (if fold "fold:" "step:") id))
         (drawer-id (concat "step:" id))
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
           (and (gascity-dashboard--drawer-open-p drawer-id)
                (mapcar (lambda (l) (concat (make-string (* 2 depth) ?\s) l))
                        (gascity-dashboard--drawer
                         (gascity-run--step-drawer (plist-get node :bead)
                                                   (and iter (plist-get iter :bead))
                                                   ctx))))
           (and open
                (mapcan (lambda (k) (gascity-run--step-lines k (1+ depth) ctx))
                        (plist-get node :children)))))))

(defun gascity-run-lines (ctx)
  "Return every run detail line for render context CTX.
CTX keys: :run-id :now :loads (:beads) :index :sessions :socket :convoy
:events (the drawer's events load) :failed-step (the diagnosed failure)
:view (:collapsed :drawers :expanded :stage-collapsed :control).  A
formula with a stage table renders its top-level anchors under stage
headers; one without keeps the flat step rows (run-view-v2 §2)."
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
                    (plist-get run :ladder)))
             (formula (gascity-runs--meta root 'gc.formula_name))
             (groups (gascity-run-stage-groups tree formula))
             (ctx (if groups
                      (let ((failed (gascity-runs-failed-step index root)))
                        (if failed
                            (plist-put (copy-sequence ctx) :failed-step failed)
                          ctx))
                    ctx))
             (body
              (cond
               (groups
                ;; Control nodes of a mapped run are lifted out of the
                ;; tree (most are nested) into one trailing group, so
                ;; they never enter a formula stage's progress.
                (append
                 (gascity-run--stage-lines groups ctx)
                 (and control
                      (gascity-run--stage-lines
                       (list (gascity-run--control-group tree)) ctx))))
               (t (mapcan (lambda (n) (gascity-run--step-lines n 0 ctx)) tree))))
             (summary (format "%s · %d beads" (plist-get run :progress)
                              (length graph))))
        (append
         (gascity-run--header-lines run root ctx)
         (list "")
         (gascity-dashboard--section-lines
          "steps" "Steps" summary body
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
          (stage-collapsed nil)
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
         (events-load (gascity-ui-effective-load events-res last-events))
         (ctx (list :run-id run-id :now (float-time)
                    :loads (list :beads beads-load)
                    :events events-load
                    :index index
                    :sessions (append (alist-get 'sessions (gascity-dashboard--data
                                                            sessions-load))
                                      nil)
                    :socket (and city (gascity-resolve-tmux-socket city 'no-probe))
                    :convoy (or (and convoy (cons convoy (alist-get 'progress convoy)))
                                (gascity-run--convoy-pair
                                 (gascity-dashboard--data convoy-load)))
                    :view (list :collapsed collapsed :drawers drawers
                                :expanded expanded
                                :stage-collapsed stage-collapsed
                                :control control))))
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

(defun gascity-run--property-at-point (prop)
  "Return text property PROP at point, or at the last character of the line.
Point at the end of a row then names the character before it, which is
how `re-search-forward' leaves point after matching a whole line."
  (or (get-text-property (point) prop)
      (and (eolp) (> (point) (point-min))
           (get-text-property (1- (point)) prop))))

(defun gascity-run-copy-id ()
  "Copy the bead id at point to the kill ring (`w').
On a step row that is the step's bead; on the inspector's iteration
line it is the iteration bead's id."
  (interactive)
  (let ((id (gascity-run--property-at-point 'gascity-bead)))
    (unless (and (stringp id) (not (string-empty-p id)))
      (user-error "No bead id here"))
    (kill-new id)
    (message "Copied %s" id)))

(defun gascity-run-inspect ()
  "Toggle the step inspector drawer for the step at point (`I').
Works on a leaf row and on a fold row (where SPC keeps folding)."
  (interactive)
  (let* ((thing (gascity-run--property-at-point 'beads-thing))
         (id (gascity-run--property-at-point 'gascity-bead)))
    (unless (and (stringp id)
                 (memq (plist-get thing :kind) '(row fold)))
      (user-error "No step here"))
    (gascity-dashboard--flip :drawers (concat "step:" id))))

;;; Diagnose (run-view-v2 §3, absorbs ga-32wpi)

(defun gascity-run--stored-run ()
  "Return (INDEX . ROOT) for this buffer's run from the store, or nil.
The run-beads payload the detail rendered is read from the store: the
command never spawns gc, so `!' stays non-blocking."
  (let* ((beads (plist-get (gascity-store-peek gascity-runs-read-key) :beads))
         (index (and beads (gascity-runs-index beads)))
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

(defun gascity-run--stage-of-name (groups name)
  "Return the stage of GROUPS whose anchor is named NAME, or nil."
  (and name
       (seq-find (lambda (group)
                   (seq-some (lambda (node)
                               (equal (plist-get node :name) name))
                             (plist-get group :anchors)))
                 groups)))

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

(defun gascity-run--goto-stage (key)
  "Move point to the header of the stage KEY; return non-nil when found."
  (goto-char (point-min))
  (let ((match (text-property-search-forward 'gascity-run-stage key #'equal)))
    (when match
      (goto-char (prop-match-beginning match))
      t)))

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

(defun gascity-run-diagnose ()
  "Jump to the run's failed step and open its inspector (`!').
Expands the failed step's stage and the folded loops above the actual
failure, opens the step's drawer, moves point to its row and echoes
`✕ REF  CLASS: REASON' truncated to the echo area.  When the row cannot
be located, point lands on the containing stage header instead.  No
failed step is a `user-error'."
  (interactive)
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
           (formula (gascity-runs--meta root 'gc.formula_name))
           (groups (gascity-run-stage-groups tree formula))
           (stage* (seq-find (lambda (group)
                               (seq-some
                                (lambda (node)
                                  (equal (alist-get 'id (plist-get node :bead))
                                         id))
                                (plist-get group :anchors)))
                             groups))
           (chain* (gascity-run--node-chain tree id))
           ;; The folds to open: the failed step's own fold plus every
           ;; nested loop down to the bead that actually failed.
           (chain (if chain*
                      (append (butlast chain*)
                              (gascity-run--failed-chain (car (last chain*))))
                    nil))
           (stage (or stage*
                      (gascity-run--stage-of-name
                       groups (gascity-run-stage-anchor
                               (or (plist-get failed :name) "")))))
           (expanded (gascity-dashboard--state :expanded))
           (stage-collapsed (gascity-dashboard--state :stage-collapsed))
           (drawers (gascity-dashboard--state :drawers)))
      (dolist (node chain)
        (when (gascity-run--fold-p node)
          (let ((key (concat "fold:" (alist-get 'id (plist-get node :bead)))))
            (unless (gascity-run--open-p node (list :expanded expanded))
              (if (gascity-run--busy-p node)
                  (setq expanded (remove key expanded))
                (setq expanded (cons key expanded)))))))
      (when stage
        (setq stage-collapsed
              (remove (concat "stage:" (plist-get stage :key)) stage-collapsed)))
      (unless (member (concat "step:" id) drawers)
        (setq drawers (cons (concat "step:" id) drawers)))
      (gascity-run--update-view :expanded expanded
                                :stage-collapsed stage-collapsed
                                :drawers drawers)
      (unless (gascity-run--goto-row id)
        (unless (and stage (gascity-run--goto-stage (plist-get stage :key)))
          (goto-char (point-min))))
      (message "%s" (truncate-string-to-width
                      (gascity-run--diagnose-message failed)
                      (max 20 (- (frame-width) 2)) nil nil "…")))))

;;; Mode

(defvar-keymap gascity-run-mode-map
  :doc "Keymap for `gascity-run-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-run-refresh
  "RET" #'gascity-run-activate
  "b"   #'gascity-run-root-bead
  "C"   #'gascity-run-toggle-control
  "I"   #'gascity-run-inspect
  "w"   #'gascity-run-copy-id
  "!"   #'gascity-run-diagnose
  "i"   #'gascity-runs-agent-detail
  "v"   #'gascity-runs-agent-peek
  "t"   #'gascity-runs-agent-tmux)

(define-derived-mode gascity-run-mode gascity-section-mode "GC-Run"
  "Major mode for the run detail (dashboard-v3 §7.7).

TAB/S-TAB move between steps, SPC folds a stage or a loop or opens a
step's inspector drawer, RET opens the step's bead or visits an
artifact, `b' the root bead, `C' shows the control nodes, and `I'
toggles the inspector for any step row (fold rows included).

`w' copies the step's bead id (the iteration id on the inspector's
iteration line) and `!' reveals and diagnoses the run's failed step by
expanding its stage and any folded loop above it, opening its inspector
and echoing the failure class and reason.  The i, v and t keys reach a
step's live worker (detail, snapshot peek, live attach) from a row or
from an inspector line.

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
