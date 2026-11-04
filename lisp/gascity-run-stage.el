;;; gascity-run-stage.el --- Formula stage table for the run detail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The stage mapping behind the run detail's stage groups
;; (plans/run-view-v2/build/implementation-plan.md §1): formula name →
;; ordered lifecycle stages, and the pure functions that assign a run's
;; top-level anchor steps to them.  No store or process code lives here;
;; grouping is a pure function of the decoded step tree and the formula
;; name.
;;
;; The four per-formula tables below are a verbatim port of gc's
;; `stagesForFormula' in internal/runproj/phasemapping.go (gc 1.5.1,
;; checkout 74501bba5, itself a port of shared/src/runs/phaseMapping.ts).
;; The stage keys and labels of the generic ladder (`intake'/Intake …
;; `finalization'/Finalization) are gc's `runStages'.
;;
;; The build-base (and identical build-basic) entry is NOT gc's mapping:
;; gc's `stagesForFormula' has no build-base entry.  Its membership is
;; Emacs-authored from build-base's declared step order and description
;; ("requirements, design review, decomposition, implementation, review,
;; and publish"): `plan-review' is the design review before
;; implementation, hence Intake, while gc's token classifier would bucket
;; it as Review (the implementation gate); the table wins and a test pins
;; the choice.  Approval stays present with zero members, as on the web
;; ladder.  This is a disclosed deviation from gc's data, not a private
;; taxonomy: the shape is gc's table and the manual says a mapped
;; formula's stage status derives from anchor membership.
;;
;; TODO(upstream): propose a build-basic/build-base entry for gc's
;; `stagesForFormula'; once gc ships one this Emacs-authored entry can be
;; deleted and the four ported tables kept as the diff.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'gascity-ui)
(require 'gascity-dashboard)            ; `gascity-dashboard--control-kinds'

;;; Formula stage table

(defconst gascity-run-stage-formulas
  '(("mol-adopt-pr-v2"
     ("preflight" "Preflight" ("preflight"))
     ("rebase" "Worktree / rebase" ("rebase-check"))
     ("pre-review-ci" "Pre-review CI"
      ("pre-review-ci" "repair-pre-review-ci-failures"))
     ("review" "Review loop"
      ("review-loop"
       "review-pipeline.review-claude"
       "review-pipeline.review-codex"
       "review-pipeline.review-gemini"
       "review-pipeline.synthesize"
       "review-pipeline.quality-scorecard"
       "apply-fixes"))
     ("ci" "Pre-approval CI"
      ("pre-approval-ci" "repair-pre-approval-ci-failures"
       "repair-ci-failures"))
     ("approval" "Human approval" ("human-approval"))
     ("finalize" "Merge-ready" ("finalize"))
     ("cleanup" "Cleanup" ("cleanup-worktree")))
    ("mol-design-review-v2"
     ("setup" "Setup" ("design-review.setup"))
     ("personas" "Personas"
      ("design-review.persona-gen-claude"
       "design-review.persona-gen-codex"
       "design-review.persona-gen-gemini"
       "design-review.persona-synthesis"))
     ("fanout" "Persona fanout"
      ("design-review.prepare-review-items"
       "design-review.persona-review-fanout"))
     ("synthesis" "Synthesis" ("design-review.global-synthesis"))
     ("apply" "Apply findings" ("design-review.apply-design-changes"))
     ("finalize" "Finalize" ("finalize")))
    ("mol-bug-report-flow-v2"
     ("intake" "Intake" ("bootstrap-run" "refresh-intake"))
     ("repro" "Reproduction"
      ("historical-baseline" "reported-build-repro" "main-repro"))
     ("audit" "Audit"
      ("code-path-audit" "coverage-audit" "related-refs-audit"))
     ("classify" "Classify"
      ("investigation-synthesis" "followup-evidence" "normalize-outcome"))
     ("approval" "Human approval"
      ("approve-classification" "verify-classification-approval"))
     ("publish" "Publish" ("publish-classification"))
     ("dispatch" "Dispatch fix" ("dispatch-implementation")))
    ("mol-bug-report-implementation-v2"
     ("plan" "Plan approval"
      ("approve-fix-plan" "approve-test-hardening-plan"
       "verify-selected-plan-approval"))
     ("design" "Design review"
      ("prepare-design-review-doc" "design-review"))
     ("implement" "Implement"
      ("implement-change" "prepare-review-context"))
     ("review" "Code review" ("code-review-loop" "apply-code-fixes"))
     ("pr" "Open PR"
      ("approve-pr-open" "verify-pr-open-approval" "open-or-update-pr"))
     ("ci" "CI" ("wait-for-ci"))
     ("merge" "Merge"
      ("approve-merge" "verify-merge-approval" "merge-and-finalize")))
    ("build-base"
     ("intake" "Intake"
      ("prepare" "requirements" "plan" "plan-review" "decompose"))
     ("implementation" "Implementation"
      ("implement" "implement-same-session" "summarize-implementation"))
     ("review" "Review" ("review"))
     ("approval" "Approval" nil)
     ("finalization" "Finalization" ("finalize" "publish")))
    ("build-basic"
     ("intake" "Intake"
      ("prepare" "requirements" "plan" "plan-review" "decompose"))
     ("implementation" "Implementation"
      ("implement" "implement-same-session" "summarize-implementation"))
     ("review" "Review" ("review"))
     ("approval" "Approval" nil)
     ("finalization" "Finalization" ("finalize" "publish"))))
  "Formula name → ordered (KEY LABEL STEP-IDS) lifecycle stages.
`mol-*' entries are gc's `stagesForFormula' tables; `build-base' and
`build-basic' are Emacs-authored (see the module commentary).  A
formula absent here has no stage table and keeps the flat step view.
STEP-IDS may be nested (`review-pipeline.review-claude'); matching is
by their top-level anchor, so such an id belongs to the anchor
`review-pipeline'.")

(defun gascity-run-stage-for-formula (formula)
  "Return FORMULA's ordered stage table, or nil when it has none.
A table is a list of (KEY LABEL STEP-IDS) entries.  Nil means FORMULA
has no authoritative stage mapping and the run detail keeps its flat
step table rather than guessing."
  (and (stringp formula)
       (cdr (assoc formula gascity-run-stage-formulas))))

;;; Anchors and nodes

(defun gascity-run-stage-anchor (step-id)
  "Return the top-level anchor of STEP-ID.
STEP-ID is a formula-prefix-stripped step path or node name, e.g. the
`gascity-dashboard--step-path' output (`review', `review.iteration.1'),
never the raw `gc.step_ref' (whose first segment is the formula).  A
trailing `.attempt.N' and any `.iteration.N' segment are normalized
away first; the anchor is the first remaining dot-separated segment."
  (when (and (stringp step-id) (not (string-empty-p step-id)))
    (let ((id (replace-regexp-in-string
               "\\.attempt\\.[0-9]+\\'" "" step-id)))
      (setq id (replace-regexp-in-string "\\.iteration\\.[0-9]+" "" id))
      (unless (string-empty-p id)
        (car (split-string id "\\."))))))

(defun gascity-run-stage--meta (bead key)
  "Return metadata KEY (a symbol) of BEAD, or nil."
  (alist-get key (alist-get 'metadata bead)))

(defun gascity-run-stage--control-p (node)
  "Return non-nil when NODE's bead is a control node.
Control nodes are the `gascity-dashboard--control-kinds' of `gc.kind';
they are never ladder anchors."
  (member (gascity-run-stage--meta (plist-get node :bead) 'gc.kind)
          gascity-dashboard--control-kinds))

(defun gascity-run-stage--without-control (nodes)
  "Return NODES without control nodes at any depth."
  (seq-keep
   (lambda (node)
     (unless (gascity-run-stage--control-p node)
       (let ((copy (copy-sequence node)))
         (plist-put copy :children
                    (gascity-run-stage--without-control
                     (plist-get node :children)))
         copy)))
   nodes))

(defun gascity-run-stage--node-path (node)
  "Return NODE's tree path, falling back to its name."
  (or (plist-get node :path) (plist-get node :name)))

;;; Stage state and progress

(defun gascity-run-stage-state (nodes)
  "Return the stage state of NODES: `failed', `active', `done' or `pending'.
NODES are annotated tree nodes (:state is the ladder state stamped by
`gascity-run-annotate').  A stage fails if any member failed, is active
if any member runs, is done only when every member is done, and is
pending otherwise, including when it has no members."
  (let ((states (mapcar (lambda (node) (plist-get node :state)) nodes)))
    (cond ((memq 'failed states) 'failed)
          ((memq 'active states) 'active)
          ((and states (seq-every-p (lambda (state) (eq state 'done)) states))
           'done)
          (t 'pending))))

(defun gascity-run-stage--done (nodes)
  "Return the number of NODES whose state is done."
  (seq-count (lambda (node) (eq (plist-get node :state) 'done)) nodes))

(defun gascity-run-stage-progress (nodes)
  "Return NODES as a `DONE/TOTAL' progress string."
  (format "%d/%d" (gascity-run-stage--done nodes) (length nodes)))

(defun gascity-run-stage-glyph (state)
  "Return the glyph for stage STATE, propertized with its face.
STATE is a `gascity-run-stage-state' value (`done', `active',
`failed', `pending').  gc's `RunStage' status vocabulary (`complete',
`blocked') is accepted too: the ported stage tables come from gc's
phase mapping, so a status read straight from it must render."
  (gascity-ui-glyph (pcase state
                      ('complete 'done)
                      ('blocked 'failed)
                      (_ state))))

;;; Grouping

(defun gascity-run-stage--group (key label members)
  "Return the stage plist of KEY and LABEL over MEMBERS (tree nodes)."
  (list :key key :label label
        :state (gascity-run-stage-state members)
        :done (gascity-run-stage--done members)
        :total (length members)
        :anchors members))

(defun gascity-run-stage-groups (tree formula)
  "Return TREE's top-level anchors grouped by FORMULA's stages.
Nil when FORMULA has no stage table (the flat fallback).  Otherwise a
list of plists (:key :label :state :done :total :anchors) in table
order.  Each top-level node of TREE is assigned to the first stage
whose STEP-IDS contains its anchor (see `gascity-run-stage-anchor';
nested ids match by anchor), so first match wins and tree order is
preserved within a stage.  Control nodes are removed at every depth
first; iteration beads and nested steps are children, never anchors.
Unmatched anchors collect in a trailing (\"other\" \"Other\") group when
any remain, so no present anchor is dropped."
  (let ((table (gascity-run-stage-for-formula formula)))
    (when table
      (let ((remaining (gascity-run-stage--without-control tree))
            (groups nil))
        (dolist (stage table)
          (let* ((key (nth 0 stage))
                 (label (nth 1 stage))
                 (anchors (mapcar #'gascity-run-stage-anchor (nth 2 stage)))
                 (members (seq-filter
                           (lambda (node)
                             (member (gascity-run-stage-anchor
                                      (gascity-run-stage--node-path node))
                                     anchors))
                           remaining)))
            (setq remaining (seq-difference remaining members #'eq))
            (push (gascity-run-stage--group key label members) groups)))
        (when remaining
          (push (gascity-run-stage--group "other" "Other" remaining) groups))
        (nreverse groups)))))

(provide 'gascity-run-stage)
;;; gascity-run-stage.el ends here
