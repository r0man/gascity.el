;;; gascity-run-stage-test.el --- ERT tests for the run stage table -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; run-view-v2 §1 (plans/run-view-v2/build/implementation-plan.md): the
;; pure stage mapping behind the run detail's stage groups.  Offline: the
;; real run graphs come from lisp/test/fixtures/v3 through the builders in
;; gascity-runs-test; nothing here runs gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'gascity)
(require 'gascity-runs-test)

;;; Helpers

(defun gascity-run-stage-test--group (groups key)
  "Return the stage plist of KEY among GROUPS, or nil."
  (seq-find (lambda (group) (equal (plist-get group :key) key)) groups))

(defun gascity-run-stage-test--names (group)
  "Return GROUP's member names."
  (mapcar (lambda (node) (plist-get node :name)) (plist-get group :anchors)))

(cl-defun gascity-run-stage-test--tree (run beads &optional show-control)
  "Return RUN's annotated step tree over BEADS.
SHOW-CONTROL keeps the control nodes in the tree."
  (let* ((index (gascity-runs-test--index beads))
         (root (seq-find (lambda (bead) (equal (alist-get 'id bead) run))
                         (plist-get index :roots)))
         (graph (gascity-runs-graph index run))
         (ladder (plist-get (gascity-runs-summary index root) :ladder)))
    (gascity-run-annotate (gascity-run-tree root graph show-control)
                          root graph ladder)))

(defun gascity-run-stage-test--node (name &optional state)
  "Return a tree node whose path and name are NAME, stamped STATE."
  (list :path name :name name :state (or state 'done)))

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

;;; Grouping

(ert-deftest gascity-test-run-stage-build-basic-partition ()
  "Every present build-basic anchor lands in exactly one stage; other is empty."
  (dolist (case '(("be-bn2" . gascity-runs-test--fixture-beads)
                  ("be-52m5" . gascity-runs-test--active-beads)))
    (let* ((tree (gascity-run-stage-test--tree
                  (car case) (funcall (cdr case))))
           (groups (gascity-run-stage-groups tree "build-basic")))
      (should (equal (mapcar (lambda (group) (plist-get group :key)) groups)
                     '("intake" "implementation" "review" "approval"
                       "finalization")))
      (should (equal (mapcar #'gascity-run-stage-test--names groups)
                     '(("prepare" "requirements" "plan" "plan-review"
                        "decompose")
                       ("implement" "summarize-implementation")
                       ("review")
                       nil
                       ("finalize" "publish"))))
      (let ((all (apply #'append
                        (mapcar #'gascity-run-stage-test--names groups))))
        (should (equal all (mapcar (lambda (node) (plist-get node :name))
                                   tree)))
        (should (= (length all)
                   (length (delete-dups (copy-sequence all))))))
      (should-not (gascity-run-stage-test--group groups "other"))
      (should (= (apply #'+ (mapcar (lambda (group) (plist-get group :total))
                                    groups))
                 (length tree))))))

(ert-deftest gascity-test-run-stage-lifecycle-order ()
  "Groups follow the lifecycle table order; members keep tree order."
  (let* ((tree (mapcar #'gascity-run-stage-test--node
                       '("publish" "finalize" "review"
                         "summarize-implementation" "implement" "decompose"
                         "plan-review" "plan" "requirements" "prepare")))
         (groups (gascity-run-stage-groups tree "build-basic")))
    (should (equal (mapcar (lambda (group) (plist-get group :key)) groups)
                   '("intake" "implementation" "review" "approval"
                     "finalization")))
    (should (equal (gascity-run-stage-test--names (car groups))
                   '("decompose" "plan-review" "plan" "requirements"
                     "prepare")))
    (should (equal (gascity-run-stage-test--names (nth 1 groups))
                   '("summarize-implementation" "implement")))))

(ert-deftest gascity-test-run-stage-excludes-control-and-iterations ()
  "Control nodes, iterations and nested steps never become anchors or members.
Showing the control nodes (C) leaves the stage groups unchanged."
  (let* ((beads (gascity-runs-test--fixture-beads))
         (shown (gascity-run-stage-groups
                 (gascity-run-stage-test--tree "be-bn2" beads t)
                 "build-basic"))
         (hidden (gascity-run-stage-groups
                  (gascity-run-stage-test--tree "be-bn2" beads)
                  "build-basic")))
    (should (equal shown hidden))
    (dolist (group shown)
      (should-not (member (plist-get group :key) '("other")))
      (dolist (node (plist-get group :anchors))
        (should (equal (plist-get node :path) (plist-get node :name)))
        (should-not (string-search "." (or (plist-get node :path) "")))
        (should-not (gascity-run-stage--control-p node))
        (should-not (string-prefix-p "iteration "
                                     (or (plist-get node :name) "")))))
    ;; The control kinds are in the control-inclusive tree only.
    (let ((names (flatten-tree
                  (gascity-runs-test--tree-names
                   (gascity-run-stage-test--tree "be-bn2" beads t)))))
      (should (member "spec" names))
      (should (member "workflow-finalize" names)))
    (should (= 10 (apply #'+
                         (mapcar (lambda (group) (plist-get group :total))
                                 shown))))))

(ert-deftest gascity-test-run-stage-status-and-counts ()
  "Stage state precedence is failed > active > done(all) > pending.
Groups carry done/total counts; glyphs translate gc's words."
  (let ((done (gascity-run-stage-test--node "done" 'done))
        (active (gascity-run-stage-test--node "active" 'active))
        (failed (gascity-run-stage-test--node "failed" 'failed))
        (pending (gascity-run-stage-test--node "pending" 'pending)))
    (should (eq (gascity-run-stage-state (list done done active)) 'active))
    (should (eq (gascity-run-stage-state (list done done)) 'done))
    (should (eq (gascity-run-stage-state (list failed done active)) 'failed))
    (should (eq (gascity-run-stage-state (list done pending)) 'pending))
    (should (eq (gascity-run-stage-state nil) 'pending))
    ;; A group carries the same state and counts.
    (let* ((tree (list (gascity-run-stage-test--node "prepare" 'done)
                       (gascity-run-stage-test--node "requirements" 'done)
                       (gascity-run-stage-test--node "plan" 'active)))
           (intake (car (gascity-run-stage-groups tree "build-basic"))))
      (should (eq (plist-get intake :state) 'active))
      (should (= (plist-get intake :done) 2))
      (should (= (plist-get intake :total) 3)))
    ;; Glyphs: the module's states plus gc's RunStage vocabulary.
    (should (equal (substring-no-properties
                    (gascity-run-stage-glyph 'done)) "◆"))
    (should (equal (substring-no-properties
                    (gascity-run-stage-glyph 'complete)) "◆"))
    (should (equal (substring-no-properties
                    (gascity-run-stage-glyph 'failed)) "✕"))
    (should (equal (substring-no-properties
                    (gascity-run-stage-glyph 'blocked)) "✕"))
    (should (equal (substring-no-properties
                    (gascity-run-stage-glyph 'active)) "⬣"))
    (should (equal (substring-no-properties
                    (gascity-run-stage-glyph 'pending)) "·"))))

(ert-deftest gascity-test-run-stage-unknown-formula ()
  "A formula without a table has no groups; the caller keeps the flat table."
  (let ((tree (list (gascity-run-stage-test--node "prepare"))))
    (should-not (gascity-run-stage-for-formula "do-work"))
    (should-not (gascity-run-stage-for-formula nil))
    (should-not (gascity-run-stage-groups tree "do-work"))
    (should-not (gascity-run-stage-groups tree nil))))

(ert-deftest gascity-test-run-stage-ported-formula-anchor-progress ()
  "Ported tables group anchors, not primary step issues.
mol-adopt-pr-v2's seven review-pipeline.* ids are one top-level anchor."
  (let* ((anchors '("preflight" "rebase-check" "pre-review-ci"
                    "repair-pre-review-ci-failures" "review-loop"
                    "review-pipeline" "apply-fixes" "pre-approval-ci"
                    "repair-pre-approval-ci-failures" "repair-ci-failures"
                    "human-approval" "finalize" "cleanup-worktree"))
         (tree (mapcar #'gascity-run-stage-test--node anchors))
         (groups (gascity-run-stage-groups tree "mol-adopt-pr-v2"))
         (review (gascity-run-stage-test--group groups "review")))
    (should (= (length (nth 2 (assoc "review"
                                     (gascity-run-stage-for-formula
                                      "mol-adopt-pr-v2"))))
               7))
    (should (= (plist-get review :total) 3))
    (should (equal (gascity-run-stage-test--names review)
                   '("review-loop" "review-pipeline" "apply-fixes")))
    (should (equal (mapcar (lambda (group) (plist-get group :total)) groups)
                   '(1 1 2 3 3 1 1 1)))
    (should-not (gascity-run-stage-test--group groups "other"))
    ;; All design-review.* ids share one anchor, so the first stage listing
    ;; it (Setup) takes it and the later stages stay empty.
    (let* ((design (mapcar #'gascity-run-stage-test--node
                           '("design-review" "finalize")))
           (design-groups (gascity-run-stage-groups
                           design "mol-design-review-v2")))
      (should (equal (mapcar (lambda (group) (plist-get group :total))
                             design-groups)
                     '(1 0 0 0 0 1))))))

(provide 'gascity-run-stage-test)
;;; gascity-run-stage-test.el ends here
