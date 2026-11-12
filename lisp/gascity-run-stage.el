;;; gascity-run-stage.el --- Formula stage table for the run detail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The optional stage labels behind the run detail's Work spine
;; (run-view work spine §1.3): formula name →
;; ordered lifecycle stages, and the anchor lookup that labels a work
;; unit.  This is enrichment only (REQ-009, OOS-005): a label may head a
;; contiguous run of units, and it never reorders, splits or hides one.
;; No store or process code lives here; labels are a pure function of the
;; formula name and the step's anchor.
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

(require 'subr-x)

;;; Formula stage table

(defconst gascity-run-stage-base-stages
  '(("intake" "Intake"
     ("prepare" "requirements" "plan" "plan-review" "decompose"))
    ("implementation" "Implementation"
     ("implement" "implement-same-session" "summarize-implementation"))
    ("review" "Review" ("review"))
    ("approval" "Approval" nil)
    ("finalization" "Finalization" ("finalize" "publish")))
  "The five-stage lifecycle shared by `build-base' and `build-basic'.
Emacs-authored (see the Commentary): the starter workflow is the base
lifecycle with a shorter plan and review, so one table carries both and
the relationship is visible in the data.")

(defconst gascity-run-stage-formulas
  `(("mol-adopt-pr-v2"
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
    ("build-base" . ,gascity-run-stage-base-stages)
    ("build-basic" . ,gascity-run-stage-base-stages))
  "Formula name → ordered (KEY LABEL STEP-IDS) lifecycle stages.
`mol-*' entries are gc's `stagesForFormula' tables; `build-base' and
`build-basic' share the Emacs-authored `gascity-run-stage-base-stages';
the Commentary explains why that table is not gc's.  A formula absent
here has no stage table and keeps the flat step view.
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

;;; Anchors

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

(provide 'gascity-run-stage)
;;; gascity-run-stage.el ends here
