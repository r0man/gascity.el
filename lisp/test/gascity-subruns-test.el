;;; gascity-subruns-test.el --- Drain member runs nest under their parent -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; A drain step fans out into member runs (roots naming it in
;; `gc.drain_control_id'); burningswell's Moving listed bs-8jif and its
;; member bs-0c3f as two flat runs.  The member nests under its parent
;; in the cockpit's Moving, the Runs view's Active section and the run
;; detail's drain step.  The fixture is shaped like bs-8jif → bs-q2el →
;; bs-0c3f.  Nothing here runs gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)
(require 'gascity-cockpit-test)
(require 'gascity-runs-test)

(defun gascity-subruns-test--bead (id status &rest meta)
  "Return bead ID in STATUS with metadata META (a plist of symbol keys).
META may carry :deps (blocks dependencies), :assignee and :rig."
  (let ((deps (plist-get meta :deps))
        (assignee (plist-get meta :assignee))
        (metadata (cl-loop for (k v) on meta by #'cddr
                           unless (memq k '(:deps :assignee :rig))
                           collect (cons k v))))
    `((id . ,id) (status . ,status) (issue_type . "task")
      (title . ,(format "bead %s" id))
      (created_at . ,(gascity-cockpit-test--ts 3600))
      (updated_at . ,(gascity-cockpit-test--ts 60))
      ,@(and assignee `((assignee . ,assignee)))
      (metadata . ,metadata)
      (dependencies . ,(vconcat (mapcar (lambda (d) `((type . "blocks") (depends_on_id . ,d)))
                                        deps)))
      (gascity-rig . "burningswell-cl"))))

(defun gascity-subruns-test--beads ()
  "Return the fixture: bs-8jif draining into bs-0c3f, bs-plain, an orphan."
  (let ((b #'gascity-subruns-test--bead))
    (list
     ;; bs-8jif build-basic: decompose done, implement (a drain) open.
     (funcall b "bs-8jif" "in_progress" 'gc.kind "workflow" 'gc.formula_name "build-basic")
     (funcall b "bs-4yih" "closed" 'gc.root_bead_id "bs-8jif"
              'gc.step_ref "build-basic.decompose")
     (funcall b "bs-q2el" "open" 'gc.root_bead_id "bs-8jif" 'gc.kind "drain"
              'gc.step_ref "build-basic.implement" :deps '("bs-4yih"))
     (funcall b "bs-k89n" "open" 'gc.root_bead_id "bs-8jif"
              'gc.step_ref "build-basic.summarize" :deps '("bs-q2el"))
     ;; bs-0c3f do-work: bs-q2el's member, its worker on bs-9z5v.
     (funcall b "bs-0c3f" "in_progress" 'gc.kind "workflow" 'gc.formula_name "do-work"
              'gc.drain_control_id "bs-q2el")
     (funcall b "bs-pw1" "closed" 'gc.root_bead_id "bs-0c3f"
              'gc.step_ref "do-work.prepare-worktree")
     (funcall b "bs-9z5v" "in_progress" 'gc.root_bead_id "bs-0c3f"
              'gc.step_ref "do-work.implement" :deps '("bs-pw1")
              :assignee "gc__implementation-worker-bu-b61o")
     (funcall b "bs-cl1" "open" 'gc.root_bead_id "bs-0c3f"
              'gc.step_ref "do-work.close-source-anchor" :deps '("bs-9z5v"))
     ;; bs-plain: a run with no drain.
     (funcall b "bs-plain" "in_progress" 'gc.kind "workflow" 'gc.formula_name "do-work")
     ;; bs-orph: a member whose parent run (bs-old) is closed.
     (funcall b "bs-old" "closed" 'gc.kind "workflow" 'gc.formula_name "build-basic")
     (funcall b "bs-oldd" "closed" 'gc.root_bead_id "bs-old" 'gc.kind "drain"
              'gc.step_ref "build-basic.implement")
     (funcall b "bs-orph" "in_progress" 'gc.kind "workflow" 'gc.formula_name "do-work"
              'gc.drain_control_id "bs-oldd"))))

(defconst gascity-subruns-test--sessions
  (list '((id . "bu-b61o") (agent_name . "burningswell-cl/gc.implementation-worker-3")
          (state . "active") (session_name . "gc__implementation-worker-bu-b61o")))
  "The live implementation worker.")

(defun gascity-subruns-test--moving (&optional rows)
  "Return the Moving lines of the fixture, at most ROWS top-level runs."
  (setq gascity-runs--index-cache (cons nil nil))
  (let* ((beads (gascity-subruns-test--beads))
         (work (seq-remove (lambda (b) (equal (alist-get 'status b) "closed")) beads))
         (ctx (plist-put (gascity-cockpit-test--ctx
                          :beads work :sessions gascity-subruns-test--sessions)
                         :run-beads beads))
         (gascity-dashboard-section-rows (or rows 5))
         (gascity-dashboard--view nil))
    (gascity-dashboard--moving-lines ctx)))

(ert-deftest gascity-test-subruns-index-parent ()
  "The index names a member run's parent through its drain step."
  (let ((index (gascity-runs-test--index (gascity-subruns-test--beads))))
    (cl-flet ((root (id) (seq-find (lambda (r) (equal (alist-get 'id r) id))
                                   (plist-get index :roots))))
      (should (equal (gascity-runs-parent-id index (root "bs-0c3f")) "bs-8jif"))
      (should (equal (gascity-runs-parent-id index (root "bs-orph")) "bs-old"))
      (should-not (gascity-runs-parent-id index (root "bs-8jif")))
      (should-not (gascity-runs-parent-id index (root "bs-plain"))))))

(ert-deftest gascity-test-subruns-moving-nests-member-and-worker ()
  "Moving counts top-level runs, sub-runs and workers; the member run
nests under bs-8jif and its worker under the member; the orphan (its
parent closed) stays top-level."
  (let ((text (gascity-cockpit-test--text (gascity-subruns-test--moving))))
    (should (string-match-p "^Moving  3 runs · 1 sub-run · 1 worker" text))
    (should (string-match-p
             (concat "^  ⬣ bs-8jif +build-basic +◆⬣· +implement +1/3.*\n"
                     "    └ ⬣ bs-0c3f +do-work +◆⬣· +implement +1/3.*\n"
                     "        └ ● implementation-worker-3 +bs-9z5v")
             text))
    (should (string-match-p "^  ⬣ bs-plain " text))
    (should (string-match-p "^  ⬣ bs-orph " text))
    (should (= 1 (cl-count-if (lambda (l) (string-match-p "bs-0c3f" l))
                              (split-string text "\n"))))))

(ert-deftest gascity-test-subruns-moving-cap-counts-top-level ()
  "The cap and `… N more' count top-level runs; a shown parent keeps its
sub-run and worker rows."
  (let ((text (gascity-cockpit-test--text (gascity-subruns-test--moving 1))))
    (should (string-match-p "└ ⬣ bs-0c3f" text))
    (should (string-match-p "└ ● implementation-worker-3" text))
    (should (string-match-p "… 2 more" text))))

(ert-deftest gascity-test-subruns-moving-rows-act ()
  "A nested sub-run row is a thing whose RET opens its run detail."
  (with-temp-buffer
    (insert (string-join (gascity-subruns-test--moving) "\n"))
    (goto-char (point-min))
    (re-search-forward "└ ⬣ bs-0c3f")
    (should (get-text-property (point) 'beads-thing))
    (let (shown)
      (cl-letf (((symbol-function 'gascity-run-show)
                 (lambda (id _convoy rig) (setq shown (list id rig)))))
        (gascity-dashboard-activate))
      (should (equal shown '("bs-0c3f" "burningswell-cl"))))))

(ert-deftest gascity-test-subruns-runs-view-nests-cards ()
  "The Runs view's Active section nests the member's card under its
parent's and counts it as a sub-run."
  (let* ((beads (gascity-subruns-test--beads))
         (ctx (gascity-runs-test--ctx beads))
         (text (gascity-runs-test--text (gascity-runs-lines ctx))))
    (should (string-match-p "^Active  3 · 1 sub-run" text))
    (should (string-match-p
             (concat "^  ⬣ bs-8jif .*\n     ◆⬣· +implement.*\n"
                     "    └ ⬣ bs-0c3f .*\n         ◆⬣· +implement")
             text))
    (should (string-match-p "^  ⬣ bs-orph " text))))

(ert-deftest gascity-test-subruns-run-detail-lists-members ()
  "Run detail lists the drain step's member runs with their ladders;
RET on one opens its run detail."
  (let* ((index (gascity-runs-test--index (gascity-subruns-test--beads)))
         (lines (gascity-run-lines (list :run-id "bs-8jif" :now (float-time)
                                         :loads (list :beads (list :state 'ready
                                                                   :data '(:beads t)))
                                         :index index :view nil)))
         (text (gascity-runs-test--text lines)))
    (should (string-match-p "implement +bs-q2el.*\n +└ ⬣ bs-0c3f +do-work +◆⬣· +implement +1/3"
                            text))
    (with-temp-buffer
      (insert (string-join lines "\n"))
      (goto-char (point-min))
      (re-search-forward "└ ⬣ bs-0c3f")
      (should (get-text-property (point) 'beads-thing))
      (let (shown)
        (cl-letf (((symbol-function 'gascity-run-show)
                   (lambda (id _convoy rig) (setq shown (list id rig)))))
          (gascity-run-activate))
        (should (equal shown '("bs-0c3f" "burningswell-cl")))))))

(provide 'gascity-subruns-test)
;;; gascity-subruns-test.el ends here
