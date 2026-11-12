;;; gascity-run-stage-test.el --- ERT tests for the run stage table -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The run-view work spine §1.3 and §1.7: the
;; optional stage table the run detail's Work spine consumes through
;; `gascity-runs--stage-label'.  The stage-group information architecture
;; is gone (REQ-009, OOS-005), so only the table and the anchor/label
;; lookup are covered here.  Offline; nothing here runs gc.

;;; Code:

(require 'ert)
(require 'subr-x)
(require 'gascity)

;;; The table

(defconst gascity-run-stage-test--build-base
  '(("intake" "Intake" ("prepare" "requirements" "plan" "plan-review" "decompose"))
    ("implementation" "Implementation"
     ("implement" "implement-same-session" "summarize-implementation"))
    ("review" "Review" ("review"))
    ("approval" "Approval" nil)
    ("finalization" "Finalization" ("finalize" "publish")))
  "The Emacs-authored build-base stage table, pinned.")

(ert-deftest gascity-test-run-stage-build-base-table ()
  "build-base's table pins build-base's declared steps, in order.
build-basic extends build-base and carries an identical table."
  (let ((table (gascity-run-stage-for-formula "build-base")))
    (should (equal table gascity-run-stage-test--build-base))
    (should (equal (apply #'append (mapcar #'caddr table))
                   '("prepare" "requirements" "plan" "plan-review" "decompose"
                     "implement" "implement-same-session"
                     "summarize-implementation" "review" "finalize"
                     "publish")))
    (should (equal (gascity-run-stage-for-formula "build-basic") table))))

(defconst gascity-run-stage-test--ported
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
      ("approve-merge" "verify-merge-approval" "merge-and-finalize"))))
  "The four stagesForFormula tables, ported verbatim (pinned literals).")

(ert-deftest gascity-test-run-stage-ported-formula-tables ()
  "The four gc formulas' stage tables match stagesForFormula exactly."
  (dolist (case gascity-run-stage-test--ported)
    (should (equal (gascity-run-stage-for-formula (car case)) (cdr case)))))

;;; Anchors

(ert-deftest gascity-test-run-stage-anchor-normalizes ()
  "The anchor is the first segment after attempt/iteration normalization."
  (should (equal (gascity-run-stage-anchor "review") "review"))
  (should (equal (gascity-run-stage-anchor "review.iteration.1") "review"))
  (should (equal (gascity-run-stage-anchor "review.attempt.2") "review"))
  (should (equal (gascity-run-stage-anchor
                  "review.iteration.1.review.test-evidence.attempt.3")
                 "review"))
  (should (equal (gascity-run-stage-anchor
                  "design-review.persona-gen-claude")
                 "design-review"))
  ;; The raw ref is out of contract: its first segment is the formula.
  (should (equal (gascity-run-stage-anchor "build-basic.review")
                 "build-basic"))
  (should-not (gascity-run-stage-anchor nil))
  (should-not (gascity-run-stage-anchor "")))

;;; Labels (what the Work spine consumes)

(ert-deftest gascity-test-run-stage-labels-build-basic ()
  "Build-basic anchors label their lifecycle stage, and nothing else.
A label is optional enrichment: an anchor the table does not name has
no label rather than a guessed one (REQ-009)."
  (should (equal (gascity-runs--stage-label "build-basic" "prepare") "Intake"))
  (should (equal (gascity-runs--stage-label "build-basic" "decompose") "Intake"))
  (should (equal (gascity-runs--stage-label "build-basic" "implement")
                 "Implementation"))
  (should (equal (gascity-runs--stage-label "build-basic" "summarize-implementation")
                 "Implementation"))
  (should (equal (gascity-runs--stage-label "build-basic" "review") "Review"))
  (should (equal (gascity-runs--stage-label "build-basic" "publish")
                 "Finalization"))
  (should-not (gascity-runs--stage-label "build-basic" "unknown-step"))
  (should-not (gascity-runs--stage-label "do-work" "prepare"))
  (should-not (gascity-runs--stage-label nil "prepare")))

(ert-deftest gascity-test-run-stage-labels-normalize-anchors ()
  "Iteration and attempt paths label through their top-level anchor.
`gascity-runs--stage-label' takes the anchor its caller derives, so a
nested step is never a second stage (REQ-009)."
  (dolist (name '("review" "review.iteration.1" "review.attempt.2"))
    (should (equal (gascity-runs--stage-label
                    "build-basic" (gascity-run-stage-anchor name))
                   "Review")))
  (should (equal (gascity-runs--stage-label
                  "mol-adopt-pr-v2"
                  (gascity-run-stage-anchor "review-pipeline.review-claude"))
                 "Review loop"))
  (should (equal (gascity-runs--stage-label
                  "mol-adopt-pr-v2" (gascity-run-stage-anchor "cleanup-worktree"))
                 "Cleanup")))

(ert-deftest gascity-test-run-stage-ported-label-tables ()
  "The ported tables expose every declared id through its anchor.
When several stages share an anchor (the design-review table), the
first matching stage wins, so the label is one of that anchor's
stages rather than necessarily the id's own row."
  (dolist (case gascity-run-stage-test--ported)
    (let ((formula (car case)))
      (dolist (stage (cdr case))
        (dolist (id (nth 2 stage))
          (let* ((anchor (gascity-run-stage-anchor id))
                 (label (gascity-runs--stage-label formula anchor))
                 (owners (seq-filter
                          (lambda (s)
                            (member anchor
                                    (mapcar #'gascity-run-stage-anchor (nth 2 s))))
                          (cdr case))))
            (should label)
            (should (member label (mapcar (lambda (s) (nth 1 s)) owners)))))))))

(provide 'gascity-run-stage-test)
;;; gascity-run-stage-test.el ends here
