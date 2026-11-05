;;; gascity-runs-test.el --- ERT tests for the Runs view and run detail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 §7.6 (Runs) and §7.7 (run detail), from the real run
;; graphs captured in lisp/test/fixtures/v3 (three beads.el runs:
;; be-52m5 build-basic closed/skipped, be-bn2 build-basic failed,
;; be-qrpg do-work passed).  Pure tests stub the gc boundary; nothing
;; here runs gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

;;; Fixtures

(defconst gascity-runs-test--dir
  (expand-file-name "fixtures/v3/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the captured gc payloads.")

(defun gascity-runs-test--json (name)
  "Return fixture NAME decoded as the reader decodes gc JSON."
  (gascity-reader-parse-json
   (with-temp-buffer
     (insert-file-contents (expand-file-name name gascity-runs-test--dir))
     (buffer-string))))

(defun gascity-runs-test--fixture-beads ()
  "Return the beads.el run graphs fixture, stamped with their store."
  (mapcar (lambda (b) (append b (list (cons 'gascity-rig "beads.el"))))
          (append (gascity-runs-test--json "emacs-city.bd-list-all-beads.el-runs.json")
                  nil)))

(defun gascity-runs-test--ts (seconds-ago)
  "Return an ISO timestamp SECONDS-AGO seconds before now (UTC)."
  (format-time-string "%FT%TZ" (- (float-time) seconds-ago) t))

(defun gascity-runs-test--active-beads ()
  "Return the fixture with be-52m5 turned into a live run.
Its prepare step is done, requirements (and its iteration) in progress
under requirements-planner-1, everything else open."
  (mapcar
   (lambda (b)
     (let* ((meta (alist-get 'metadata b))
            (ref (alist-get 'gc.step_ref meta)))
       (cond
        ((equal (alist-get 'id b) "be-52m5")
         (append `((status . "in_progress")
                   (created_at . ,(gascity-runs-test--ts 7200))
                   (metadata . ,(cons '(gc.outcome . nil) meta)))
                 b))
        ((not (equal (alist-get 'gc.root_bead_id meta) "be-52m5")) b)
        ((equal ref "build-basic.prepare")
         (append `((metadata . ,(cons '(gc.outcome . "pass") meta))) b))
        ((member ref '("build-basic.requirements" "requirements.iteration.1"))
         (append `((status . "in_progress")
                   (assignee . "gc__requirements-planner-ec-fl8o")
                   (updated_at . ,(gascity-runs-test--ts 180))
                   (metadata . ,(cons '(gc.outcome . nil) meta)))
                 b))
        (t (append `((status . "open")
                     (metadata . ,(cons '(gc.outcome . nil) meta)))
                   b)))))
   (gascity-runs-test--fixture-beads)))

(defconst gascity-runs-test--sessions
  `((sessions . [((id . "ec-fl8o")
                  (agent_name . "beads.el/gc.requirements-planner-1")
                  (state . "active")
                  (session_name . "gc__requirements-planner-ec-fl8o")
                  (work_dir . "/home/roman/workspace/beads.el"))]))
  "A `session list' payload with the live requirements planner.")

(defun gascity-runs-test--index (beads)
  "Return the run index of BEADS, bypassing the identity cache."
  (setq gascity-runs--index-cache (cons nil nil))
  (gascity-runs-index beads))

(defun gascity-runs-test--summaries (beads)
  "Return the run summaries of BEADS."
  (let ((index (gascity-runs-test--index beads)))
    (mapcar (lambda (r) (gascity-runs-summary index r)) (plist-get index :roots))))

(defun gascity-runs-test--by-id (runs id)
  "Return the summary of run ID among RUNS."
  (seq-find (lambda (r) (equal (plist-get r :id) id)) runs))

(defun gascity-runs-test--load (data)
  "Return a ready load plist carrying DATA."
  (list :state 'ready :data data))

(cl-defun gascity-runs-test--ctx (beads &key filters view now sessions)
  "Return a Runs render context over BEADS."
  (gascity-runs-context
   (list :beads (gascity-runs-test--load (list :beads beads))
         :sessions (gascity-runs-test--load sessions))
   filters view (or now (float-time)) "emacs-city"))

(defun gascity-runs-test--text (lines)
  "Return LINES (strings) as one plain string."
  (substring-no-properties (string-join lines "\n")))

(cl-defun gascity-runs-test--header (beads id &key city convoy)
  "Return the run detail header lines of run ID over BEADS.
CITY names the buffer's city (default \"emacs-city\"); CONVOY is the
\(CONVOY . PROGRESS\) pair the component would have read."
  (let* ((index (gascity-runs-test--index beads))
         (root (seq-find (lambda (r) (equal (alist-get 'id r) id))
                         (plist-get index :roots)))
         (run (gascity-runs-summary index root))
         (ctx (list :run-id id :now (float-time)
                    :city (or city "emacs-city") :convoy convoy)))
    (gascity-run--header-lines run root ctx)))

(cl-defun gascity-runs-test--inspector-ctx (beads run-id &key now sessions events)
  "Return a run-detail context over BEADS for RUN-ID, as the inspector sees it.
NOW, SESSIONS and EVENTS are the drawer's clock, live sessions and events
load; EVENTS is an `gascity-ui-effective-load' plist."
  (list :run-id run-id
        :now (or now (float-time))
        :loads (list :beads (gascity-runs-test--load (list :beads beads)))
        :events events
        :index (gascity-runs-test--index beads)
        :sessions sessions :socket nil :convoy nil :view nil))

(defun gascity-runs-test--worker-session (id now &optional active-ago)
  "Return a live `session list' row for ID at NOW.
ACTIVE-AGO is how many seconds before NOW the session was last active
\(default 20).  The agent is the requirements planner the inspector
fixture assigns to its step."
  `((id . ,id)
    (agent_name . "beads.el/gc.requirements-planner-1")
    (state . "active")
    (last_active . ,(format-time-string
                     "%FT%TZ" (- now (or active-ago 20)) t))
    (session_name . "gc__requirements-planner-ec-fl8o")
    (work_dir . "/home/roman/workspace/beads.el")))

;;; Model: ladder, states, failure (§3.2)

(ert-deftest gascity-test-runs-summary-from-real-graphs ()
  "Each fixture run gets its state, ladder, label and progress."
  (let* ((runs (gascity-runs-test--summaries (gascity-runs-test--fixture-beads)))
         (skipped (gascity-runs-test--by-id runs "be-52m5"))
         (failed (gascity-runs-test--by-id runs "be-bn2"))
         (passed (gascity-runs-test--by-id runs "be-qrpg")))
    (should (= (length runs) 3))
    (should (eq (plist-get skipped :state) 'done))
    (should (equal (plist-get skipped :progress) "10/10"))
    (should (equal (plist-get skipped :outcome) "skipped"))
    (should (equal (plist-get skipped :rig) "beads.el"))
    ;; The failed run: the nested review loop failed, so the top-level
    ;; review step is the failed one on the ladder.
    (should (eq (plist-get failed :state) 'failed))
    (should (equal (plist-get failed :label) "review"))
    (should (equal (plist-get failed :progress) "9/10"))
    (should (equal (plist-get failed :failure) "control_dispatch_error"))
    (should (equal (substring-no-properties
                    (gascity-dashboard--ladder-string (plist-get failed :ladder)))
                   "◆◆◆◆◆◆◆✕◆◆"))
    (should (eq (plist-get passed :state) 'done))
    (should (equal (plist-get passed :formula) "do-work"))
    (should (equal (mapcar (lambda (s) (plist-get s :name)) (plist-get passed :ladder))
                   '("prepare-worktree" "implement" "close-source-anchor")))))

(defconst gascity-runs-test--latch-beads
  `((id . "bl-eh4k") (status . "in_progress") (issue_type . "task")
    (metadata . ((gc.kind . "workflow") (gc.formula_name . "e2e-demo-on")))
    (gascity-rig . "burningswell-cl"))
  "A v2 run root.")

(defun gascity-runs-test--latch-fixture ()
  "Return a run whose latch step carries both `gc.kind' workflow and a root."
  (list gascity-runs-test--latch-beads
        `((id . "bl-matt") (status . "in_progress") (issue_type . "task")
          (metadata . ((gc.kind . "workflow")
                       (gc.step_id . "e2e-demo-on.latch")
                       (gc.step_ref . "e2e-demo-on.latch")
                       (gc.root_bead_id . "bl-eh4k")))
          (gascity-rig . "burningswell-cl"))
        `((id . "bl-step") (status . "open") (issue_type . "task")
          (metadata . ((gc.root_bead_id . "bl-eh4k")
                       (gc.step_ref . "e2e-demo-on.work")))
          (gascity-rig . "burningswell-cl"))))

(ert-deftest gascity-test-runs-latch-step-is-a-graph-member ()
  "A latch step (`gc.kind' workflow plus `gc.root_bead_id') belongs to its
root's graph, not the run list: the root keeps its ladder instead of
rendering `Steps 0/0' while the latch shows up as its own run (ga-99g35)."
  (let* ((beads (gascity-runs-test--latch-fixture))
         (index (gascity-runs-test--index beads))
         (roots (mapcar (lambda (b) (alist-get 'id b)) (plist-get index :roots)))
         (run (gascity-runs-test--by-id
               (mapcar (lambda (r) (gascity-runs-summary index r))
                       (plist-get index :roots))
               "bl-eh4k")))
    (should (equal roots '("bl-eh4k")))
    (should (equal (mapcar (lambda (b) (alist-get 'id b))
                           (gascity-runs-graph index "bl-eh4k"))
                   '("bl-matt" "bl-step")))
    (should (equal (plist-get run :progress) "0/2"))
    (should (equal (mapcar (lambda (s) (plist-get s :name)) (plist-get run :ladder))
                   '("latch" "work")))
    (should-not (gascity-dashboard--run-root-p (cadr beads)))
    (should (equal (mapcar (lambda (b) (alist-get 'id b))
                           (gascity-dashboard--active-runs beads))
                   '("bl-eh4k")))))

(defun gascity-runs-test--drain-beads (member-status)
  "Return a run whose drain step `implement' has members in MEMBER-STATUS.
Shaped after burningswell's bs-8jif: the drain step stays open while
its member runs (roots naming it in `gc.drain_control_id') work."
  (let ((step (lambda (id ref status &optional kind deps)
                `((id . ,id) (status . ,status) (issue_type . "task")
                  (metadata . ((gc.root_bead_id . "bs-8jif") (gc.step_ref . ,ref)
                               ,@(and kind `((gc.kind . ,kind)))))
                  (dependencies . ,(vconcat
                                    (mapcar (lambda (d) `((type . "blocks")
                                                          (depends_on_id . ,d)))
                                            deps))))))
        (member (lambda (id status)
                  `((id . ,id) (status . ,status) (issue_type . "task")
                    (metadata . ((gc.kind . "workflow") (gc.formula_name . "do-work")
                                 (gc.drain_control_id . "bs-q2el")))))))
    (list `((id . "bs-8jif") (status . "in_progress") (issue_type . "task")
            (metadata . ((gc.kind . "workflow") (gc.formula_name . "build-basic"))))
          (funcall step "bs-4yih" "build-basic.decompose" "closed")
          (funcall step "bs-q2el" "build-basic.implement" "open" "drain"
                   '("bs-4yih" "bs-0c3f" "bs-b1o1"))
          (funcall step "bs-k89n" "build-basic.summarize" "open" nil '("bs-q2el"))
          (funcall member "bs-0c3f" member-status)
          (funcall member "bs-b1o1" "closed"))))

(ert-deftest gascity-test-runs-drain-step-active-while-members-run ()
  "An open drain step with a member run in progress is the active step
(`⬣'), in the shared ladder; with every member closed it is pending."
  (let* ((runs (gascity-runs-test--summaries (gascity-runs-test--drain-beads "in_progress")))
         (run (gascity-runs-test--by-id runs "bs-8jif")))
    (should (equal (substring-no-properties
                    (gascity-dashboard--ladder-string (plist-get run :ladder)))
                   "◆⬣·"))
    (should (equal (plist-get run :label) "implement"))
    (should (equal (plist-get run :progress) "1/3")))
  (let* ((runs (gascity-runs-test--summaries (gascity-runs-test--drain-beads "closed")))
         (run (gascity-runs-test--by-id runs "bs-8jif")))
    (should (equal (substring-no-properties
                    (gascity-dashboard--ladder-string (plist-get run :ladder)))
                   "◆··"))))

(defun gascity-runs-test--failing-drain-beads (&optional drain-outcome)
  "Return a live run whose implement drain step has a failed member run.
DRAIN-OUTCOME \"fail\" closes the drain step failed; nil leaves it open
while its members run.  The failed member run `bs-0c3f' carries the
failure class and reason on its failed prepare-worktree step."
  (let* ((root `((id . "bs-8jif") (status . "in_progress") (issue_type . "task")
                 (created_at . ,(gascity-runs-test--ts 7200))
                 (metadata . ((gc.kind . "workflow") (gc.formula_name . "build-basic")))
                 (gascity-rig . "burningswell-cl")))
         (step (lambda (id ref status &optional kind outcome deps)
                 `((id . ,id) (status . ,status) (issue_type . "task")
                   (metadata . ((gc.root_bead_id . "bs-8jif")
                                (gc.step_ref . ,ref)
                                ,@(and kind `((gc.kind . ,kind)))
                                ,@(and outcome `((gc.outcome . ,outcome)))))
                   (dependencies . ,(vconcat
                                     (mapcar (lambda (d)
                                               `((type . "blocks")
                                                 (depends_on_id . ,d)))
                                             deps)))
                   (gascity-rig . "burningswell-cl"))))
         (member (lambda (id status outcome)
                   `((id . ,id) (status . ,status) (issue_type . "task")
                     (metadata . ((gc.kind . "workflow") (gc.formula_name . "do-work")
                                  (gc.drain_control_id . "bs-q2el")
                                  ,@(and outcome `((gc.outcome . ,outcome)))))
                     (gascity-rig . "burningswell-cl")))))
    (list root
          (funcall step "bs-4yih" "build-basic.decompose" "closed" nil "pass")
          (funcall step "bs-q2el" "build-basic.implement"
                   (if drain-outcome "closed" "open") "drain" drain-outcome
                   '("bs-4yih"))
          (funcall step "bs-k89n" "build-basic.summarize" "open" nil nil
                   '("bs-q2el"))
          (funcall member "bs-0c3f" "closed" "fail")
          `((id . "bs-fail") (status . "closed") (issue_type . "task")
            (metadata . ((gc.root_bead_id . "bs-0c3f")
                         (gc.step_ref . "do-work.prepare-worktree")
                         (gc.outcome . "fail")
                         (gc.failure_class . "environment_missing_origin")
                         (gc.failure_reason . "rig checkout has no git remote")))
            (gascity-rig . "burningswell-cl"))
          (funcall member "bs-b1o1" "in_progress" nil))))

(ert-deftest gascity-test-runs-active-run-failed-drain-step ()
  "A root still in progress whose drain step failed is a failed step:
the summary names it, with the member run's failure class, while the
run state stays `active' (ga-g092a)."
  (let* ((runs (gascity-runs-test--summaries
                (gascity-runs-test--failing-drain-beads "fail")))
         (run (gascity-runs-test--by-id runs "bs-8jif"))
         (step (plist-get run :failed-step)))
    (should (eq (plist-get run :state) 'active))
    (should (equal (plist-get run :label) "implement"))
    (should step)
    (should (equal (plist-get step :name) "implement"))
    (should (equal (plist-get step :ref) "build-basic.implement"))
    (should (equal (plist-get step :member-ref) "do-work.prepare-worktree"))
    (should (equal (plist-get step :class) "environment_missing_origin"))
    (should (equal (plist-get step :reason) "rig checkout has no git remote"))
    (should (equal (plist-get step :member) "bs-0c3f"))))

(ert-deftest gascity-test-runs-active-run-failed-member-under-open-drain ()
  "An open drain step reads `active' while a member still runs, yet a
failed member run makes it the run's failed step: the summary keeps the
run active and carries the failure (ga-g092a)."
  (let* ((runs (gascity-runs-test--summaries
                (gascity-runs-test--failing-drain-beads nil)))
         (run (gascity-runs-test--by-id runs "bs-8jif"))
         (step (plist-get run :failed-step)))
    (should (eq (plist-get run :state) 'active))
    ;; The ladder step itself is active (a member is still in progress).
    (should (equal (substring-no-properties
                    (gascity-dashboard--ladder-string (plist-get run :ladder)))
                   "◆⬣·"))
    (should (equal (plist-get step :name) "implement"))
    (should (equal (plist-get step :class) "environment_missing_origin"))))

(ert-deftest gascity-test-runs-active-run-failed-nested-step ()
  "A failed bead beneath a pending top-level step marks that step failed
while the root is still in progress."
  (let* ((root `((id . "bs-nest") (status . "in_progress") (issue_type . "task")
                 (metadata . ((gc.kind . "workflow") (gc.formula_name . "build-basic")))
                 (gascity-rig . "burningswell-cl")))
         (step `((id . "bs-rev") (status . "open") (issue_type . "task")
                 (metadata . ((gc.root_bead_id . "bs-nest")
                              (gc.step_ref . "build-basic.review")))
                 (gascity-rig . "burningswell-cl")))
         (nested `((id . "bs-rev.1") (status . "closed") (issue_type . "task")
                   (metadata . ((gc.root_bead_id . "bs-nest")
                                (gc.step_ref . "build-basic.review.iteration.1")
                                (gc.outcome . "fail")
                                (gc.failure_class . "review_rejected")))
                   (gascity-rig . "burningswell-cl")))
         (runs (gascity-runs-test--summaries (list root step nested)))
         (run (gascity-runs-test--by-id runs "bs-nest"))
         (failed (plist-get run :failed-step)))
    (should (eq (plist-get run :state) 'active))
    (should (equal (plist-get failed :name) "review"))
    (should (equal (plist-get failed :ref) "build-basic.review"))
    (should (equal (plist-get failed :member-ref)
                   "build-basic.review.iteration.1"))
    (should (equal (plist-get failed :class) "review_rejected"))))

(ert-deftest gascity-test-runs-active-run-retried-loop-not-failed ()
  "A done step with a failed earlier iteration in a live run is not a
failed step: the retry succeeded, so the run stays unflagged."
  (let* ((root `((id . "bs-retry") (status . "in_progress") (issue_type . "task")
                 (metadata . ((gc.kind . "workflow") (gc.formula_name . "build-basic")))
                 (gascity-rig . "burningswell-cl")))
         (step `((id . "bs-rev") (status . "closed") (issue_type . "task")
                 (metadata . ((gc.root_bead_id . "bs-retry")
                              (gc.step_ref . "build-basic.review")
                              (gc.outcome . "pass")))
                 (gascity-rig . "burningswell-cl")))
         (failed-iter `((id . "bs-rev.1") (status . "closed") (issue_type . "task")
                        (metadata . ((gc.root_bead_id . "bs-retry")
                                     (gc.step_ref . "build-basic.review.iteration.1")
                                     (gc.outcome . "fail")
                                     (gc.failure_class . "review_rejected")))
                        (gascity-rig . "burningswell-cl")))
         (run (gascity-runs-test--by-id
               (gascity-runs-test--summaries (list root step failed-iter))
               "bs-retry")))
    (should (eq (plist-get run :state) 'active))
    (should (equal (plist-get run :progress) "1/1"))
    (should-not (plist-get run :failed-step))))

(ert-deftest gascity-test-runs-active-run-failed-step-card ()
  "The Runs card of an active run with a failed step carries the failure
summary, not just the ladder glyph (ga-g092a)."
  (let* ((beads (gascity-runs-test--failing-drain-beads "fail"))
         (ctx (gascity-runs-test--ctx beads))
         (text (gascity-runs-test--text (gascity-runs-lines ctx))))
    (should (string-match-p "^Active  1 · 1 sub-run$" text))
    (should (string-match-p
             "◆✕·  implement +1/3 +✕ build-basic.implement +environment_missing_origin"
             text))))

(ert-deftest gascity-test-runs-active-run-worker ()
  "An active run's label is its active step; its worker is the live session."
  (let* ((runs (gascity-runs-test--summaries (gascity-runs-test--active-beads)))
         (run (gascity-runs-test--by-id runs "be-52m5")))
    (should (eq (plist-get run :state) 'active))
    (should (equal (plist-get run :label) "requirements"))
    (should (equal (plist-get run :progress) "1/10"))
    (should (equal (alist-get 'id (plist-get run :worker-bead)) "be-bcb5"))
    (let ((worker (gascity-runs--worker (plist-get run :worker-bead)
                                        (append (alist-get 'sessions
                                                           gascity-runs-test--sessions)
                                                nil)
                                        "emacs-city")))
      (should (equal (substring-no-properties (car worker))
                     "● requirements-planner-1  be-bcb5"))
      (should (gascity-agent-p (cdr worker))))))

(ert-deftest gascity-test-runs-ladder-failed-only-in-failed-run ()
  "A failed bead beneath a closed step marks it failed only when the run
itself failed: a retried loop in a passing run keeps its step done."
  (let* ((beads (mapcar (lambda (b)
                          (if (equal (alist-get 'id b) "be-bn2")
                              (cons '(metadata . ((gc.kind . "workflow")
                                                  (gc.formula_name . "build-basic")
                                                  (gc.outcome . "pass")))
                                    b)
                            b))
                        (gascity-runs-test--fixture-beads)))
         (run (gascity-runs-test--by-id (gascity-runs-test--summaries beads) "be-bn2")))
    (should (eq (plist-get run :state) 'done))
    (should (equal (plist-get run :progress) "10/10"))))

(ert-deftest gascity-test-runs-window-seconds ()
  "Durations parse to seconds; anything else is no bound."
  (should (= (gascity-runs-window-seconds "24h") 86400))
  (should (= (gascity-runs-window-seconds "7d") 604800))
  (should (= (gascity-runs-window-seconds "90m") 5400))
  (should (= (gascity-runs-window-seconds "2w") 1209600))
  (should-not (gascity-runs-window-seconds "all"))
  (should-not (gascity-runs-window-seconds nil)))

(ert-deftest gascity-test-runs-failed-detection-window ()
  "Failed lists failed runs closed within the window; all closed runs are
history.  be-bn2 closed 2026-09-25T12:23:58Z."
  (let* ((runs (gascity-runs-test--summaries (gascity-runs-test--fixture-beads)))
         (at (lambda (iso) (gascity-ui-parse-time iso)))
         (ids (lambda (list) (mapcar (lambda (r) (plist-get r :id)) list))))
    (let ((parts (gascity-runs-partition runs nil (funcall at "2026-09-25T20:00:00Z"))))
      (should (equal (funcall ids (plist-get parts :failed)) '("be-bn2")))
      (should (null (plist-get parts :active)))
      ;; Newest first: be-52m5 (14:02) before be-bn2 (12:23) before be-qrpg.
      (should (equal (funcall ids (plist-get parts :closed))
                     '("be-52m5" "be-bn2" "be-qrpg")))
      (should (equal (plist-get parts :counts)
                     '((active . 0) (waiting . 0) (done . 2) (failed . 1)))))
    ;; Two days later: out of the default 24h failed window.
    (let ((parts (gascity-runs-partition runs nil (funcall at "2026-09-27T20:00:00Z"))))
      (should (null (plist-get parts :failed)))
      (should (= (length (plist-get parts :closed)) 3)))
    ;; A wider -W window brings it back and bounds the history too.
    (let ((parts (gascity-runs-partition runs '(:window "7d")
                                         (funcall at "2026-09-27T20:00:00Z"))))
      (should (equal (funcall ids (plist-get parts :failed)) '("be-bn2"))))
    (let ((parts (gascity-runs-partition runs '(:window "8h")
                                         (funcall at "2026-09-25T20:00:00Z"))))
      (should (equal (funcall ids (plist-get parts :closed)) '("be-52m5" "be-bn2"))))))

(ert-deftest gascity-test-runs-order-stable-on-equal-times ()
  "Runs with the same time sort by id, whatever the payload order."
  (let ((a (list :id "bl-70ac" :time "2026-09-23T21:21:16Z"))
        (b (list :id "bl-0q8w" :time "2026-09-23T21:21:16Z"))
        (c (list :id "bl-oyl4" :time "2026-09-24T07:47:00Z")))
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (gascity-runs--newest-first (list a b c)))
                   '("bl-oyl4" "bl-0q8w" "bl-70ac")))
    (should (equal (gascity-runs--newest-first (list b c a))
                   (gascity-runs--newest-first (list a b c))))))

(ert-deftest gascity-test-runs-filter-rig-and-formula ()
  "`-r' and `-F' narrow every section and the counts; `city' is the HQ store."
  (let* ((runs (gascity-runs-test--summaries (gascity-runs-test--fixture-beads)))
         (now (gascity-ui-parse-time "2026-09-25T20:00:00Z")))
    (should (equal (mapcar (lambda (r) (plist-get r :id))
                           (plist-get (gascity-runs-partition
                                       runs '(:formula "do-work") now)
                                      :closed))
                   '("be-qrpg")))
    (should (null (plist-get (gascity-runs-partition runs '(:rig "city") now) :closed)))
    (should (= 3 (length (plist-get (gascity-runs-partition runs '(:rig "beads.el") now)
                                    :closed))))))

;;; Rendering

(ert-deftest gascity-test-runs-render-cards ()
  "Active and Failed render two-line cards: ladder, label, progress, worker."
  (let* ((beads (gascity-runs-test--active-beads))
         (ctx (gascity-runs-test--ctx beads :sessions gascity-runs-test--sessions
                                      :filters '(:window "36500d")))
         (text (gascity-runs-test--text (gascity-runs-lines ctx))))
    (should (string-match-p
             "^Runs  emacs-city   1 active · 0 waiting · 1 done · 1 failed +H history  / filter$"
             text))
    (should (string-match-p "^Active  1$" text))
    (should (string-match-p "^  ⬣ be-52m5 +build-basic +beads.el +2h$" text))
    (should (string-match-p
             "^     ◆⬣········  requirements +1/10 +● requirements-planner-1  be-bcb5$"
             text))
    (should (string-match-p "^Failed  1 · last 36500d$" text))
    (should (string-match-p "^  ✕ be-bn2 +build-basic +beads.el" text))
    (should (string-match-p "◆◆◆◆◆◆◆✕◆◆  review +9/10 +control_dispatch_error$" text))
    ;; No history until `H'.
    (should-not (string-match-p "^Closed" text))))

(ert-deftest gascity-test-runs-card-is-one-thing ()
  "A card's two lines are one thing carrying the run and its live worker."
  (let* ((ctx (gascity-runs-test--ctx (gascity-runs-test--active-beads)
                                      :sessions gascity-runs-test--sessions))
         (card (car (gascity-runs--card
                     (gascity-runs-test--by-id (plist-get ctx :runs) "be-52m5")
                     ctx))))
    (should (string-search "\n" card))
    (let ((thing (get-text-property 0 'beads-thing card)))
      (should (eq (plist-get thing :kind) 'row))
      (should (eq (get-text-property (1- (length card)) 'beads-thing card) thing))
      (should (eq (get-text-property (string-search "\n" card) 'beads-thing card) thing)))
    (should (equal (get-text-property 0 'gascity-bead card) "be-52m5"))
    (should (equal (get-text-property 0 'gascity-run-rig card) "beads.el"))
    (should (gascity-agent-p (get-text-property 0 'gascity-agent card)))))

(defun gascity-runs-test--many-closed (n)
  "Return N closed do-work run roots (no graphs), one minute apart."
  (cl-loop for i below n
           collect `((id . ,(format "ga-h%02d" i)) (status . "closed")
                     (closed_at . ,(gascity-runs-test--ts (* 60 (1+ i))))
                     (metadata . ((gc.kind . "workflow") (gc.formula_name . "do-work")
                                  (gc.outcome . "pass")))
                     (gascity-rig . "gascity.el"))))

(defun gascity-runs-test--plain-run (id state time)
  "Return a minimal run summary ID in STATE dated TIME."
  (list :id id :state state :formula "build-basic" :rig "beads.el"
        :time time :ladder nil :label "" :progress "" :worker-bead nil
        :parent nil :outcome nil :failure nil))

(ert-deftest gascity-test-runs-partition-splits-active-waiting ()
  "`:in-progress' and `:waiting' are separate; `:active' keeps both (ga-jqt9q.2)."
  (let* ((runs (list (gascity-runs-test--plain-run "be-d" 'done "2026-09-23T10:00:00Z")
                     (gascity-runs-test--plain-run "be-a" 'active "2026-09-25T10:00:00Z")
                     (gascity-runs-test--plain-run "be-w" 'waiting "2026-09-24T10:00:00Z")))
         (parts (gascity-runs-partition runs nil
                                        (gascity-ui-parse-time "2026-09-25T20:00:00Z")))
         (ids (lambda (key) (mapcar (lambda (r) (plist-get r :id))
                                    (plist-get parts key)))))
    (should (equal (funcall ids :in-progress) '("be-a")))
    (should (equal (funcall ids :waiting) '("be-w")))
    (should (equal (funcall ids :active) '("be-a" "be-w")))
    (should (equal (plist-get parts :counts)
                   '((active . 1) (waiting . 1) (done . 1) (failed . 0))))))

(ert-deftest gascity-test-runs-waiting-section-is-separate ()
  "Waiting runs get their own section so the header matches the summary (ga-jqt9q.2)."
  (let* ((runs (list (gascity-runs-test--plain-run "be-live" 'active
                                                   (gascity-runs-test--ts 120))
                     (gascity-runs-test--plain-run "be-wait" 'waiting
                                                   (gascity-runs-test--ts 90000))))
         (ctx (list :city "emacs-city" :now (float-time) :filters nil
                    :loads (list :beads (gascity-runs-test--load (list :beads nil)))
                    :runs runs :sessions nil :socket nil :view nil))
         (text (gascity-runs-test--text (gascity-runs-lines ctx))))
    (should (string-match-p
             "^Runs  emacs-city   1 active · 1 waiting · 0 done · 0 failed" text))
    (should (string-match-p "^Active  1$" text))
    (should (string-match-p "^Waiting  1$" text))
    (should (string-match-p "^  ⬣ be-live\\b" text))
    (should (string-match-p "^  · be-wait\\b" text))
    (should (< (string-match-p "^Active" text) (string-match-p "be-live" text)))
    (should (< (string-match-p "be-live" text) (string-match-p "^Waiting" text)))
    (should (< (string-match-p "^Waiting" text) (string-match-p "be-wait" text)))))

(ert-deftest gascity-test-runs-waiting-section-hidden-when-empty ()
  "An empty Waiting section is not rendered in the default view (ga-jqt9q.2)."
  (let* ((runs (list (gascity-runs-test--plain-run "be-live" 'active
                                                   (gascity-runs-test--ts 120))))
         (ctx (list :city "emacs-city" :now (float-time) :filters nil
                    :loads (list :beads (gascity-runs-test--load (list :beads nil)))
                    :runs runs :sessions nil :socket nil :view nil))
         (text (gascity-runs-test--text (gascity-runs-lines ctx))))
    (should (string-match-p "^Active  1$" text))
    (should-not (string-match-p "^Waiting" text))
    ;; The state filter still shows an empty Waiting section.
    (let ((ctx (plist-put (copy-sequence ctx) :filters '(:state "waiting"))))
      (should (string-match-p "^Waiting  none$"
                              (gascity-runs-test--text (gascity-runs-lines ctx)))))))

(ert-deftest gascity-test-runs-history-paging ()
  "`H' shows closed runs newest first, 20 per page; `+' adds a page."
  (let* ((beads (gascity-runs-test--many-closed 45))
         (render (lambda (view)
                   (gascity-runs-test--text
                    (gascity-runs-lines (gascity-runs-test--ctx beads :view view)))))
         (rows (lambda (text) (cl-count-if (lambda (l) (string-match-p "^  ◆ ga-h" l))
                                           (split-string text "\n")))))
    (should-not (string-match-p "^Closed" (funcall render nil)))
    (let ((text (funcall render '(:history t :pages 1))))
      (should (string-match-p "^Closed  45$" text))
      (should (= (funcall rows text) 20))
      (should (string-match-p "^  ◆ ga-h00 " text))
      (should (string-match-p "^  … 25 more +\\+ more$" text)))
    (let ((text (funcall render '(:history t :pages 2))))
      (should (= (funcall rows text) 40))
      (should (string-match-p "^  … 5 more" text)))
    (let ((text (funcall render '(:history t :pages 3))))
      (should (= (funcall rows text) 45))
      (should-not (string-match-p "more$" text)))
    ;; `-s done' shows the history without `H' and hides the others.
    (let ((text (gascity-runs-test--text
                 (gascity-runs-lines (gascity-runs-test--ctx
                                      beads :filters '(:state "done"))))))
      (should (string-match-p "^Closed  45$" text))
      (should-not (string-match-p "^Active\\|^Failed" text))
      (should (string-match-p "filter  state done" text)))))

(ert-deftest gascity-test-runs-history-is-closed-not-done ()
  "Old failures count under `Closed', never a `Done' section (ga-x9gys.2).
The header counts every run all-time, while the Failed section is
windowed by `gascity-runs-failed-window'.  The history is the archive of
all closed runs, failed ones included, so it is titled `Closed': a run
is never simultaneously `failed' in the header and under `Done'."
  (let* ((beads (gascity-runs-test--fixture-beads))
         ;; Two days on: be-bn2's failure is outside the 24h Failed window.
         (now (gascity-ui-parse-time "2026-09-27T20:00:00Z"))
         (text (gascity-runs-test--text
                (gascity-runs-lines
                 (gascity-runs-test--ctx beads :now now :view '(:history t))))))
    (should (string-match-p
             "^Runs  emacs-city   0 active · 0 waiting · 2 done · 1 failed" text))
    (should (string-match-p "^Failed  none · last 24h$" text))
    ;; The all-time failed run is not lost: it is in the Closed history,
    ;; whose count reconciles with the header (2 done + 1 failed).
    (should (string-match-p "^Closed  3$" text))
    (should (string-match-p "^  ✕ be-bn2\\b" text))
    (should-not (string-match-p "^Done" text))))

(ert-deftest gascity-test-runs-render-loading-and-error ()
  "Before the read lands every section shows `…'; a failed read with no
data shows the error line; the view never blanks."
  (let* ((pending (gascity-runs-context (list :beads '(:state pending)
                                              :sessions '(:state pending))
                                        nil nil (float-time) "emacs-city"))
         (text (gascity-runs-test--text (gascity-runs-lines pending))))
    (should (string-match-p "^Active  …$" text))
    (should (string-match-p "^Failed  …$" text)))
  (let* ((err (gascity-runs-context (list :beads '(:state error :error "boom"))
                                    nil nil (float-time) "emacs-city"))
         (text (gascity-runs-test--text (gascity-runs-lines err))))
    (should (string-match-p "■ gc bd list: boom   g retry" text))))

;;; Keys, filter menu, jump

(ert-deftest gascity-test-runs-keys ()
  "The Runs and run detail maps carry the §5/§7.6/§7.7 keys."
  (dolist (pair '(("g" . gascity-runs-refresh) ("RET" . gascity-runs-activate)
                  ("F" . gascity-runs-follow)
                  ("b" . gascity-runs-root-bead) ("H" . gascity-runs-history)
                  ("+" . gascity-runs-more) ("/" . gascity-runs-filter)
                  ("i" . gascity-runs-agent-detail) ("v" . gascity-runs-agent-peek)
                  ("t" . gascity-runs-agent-tmux) ("TAB" . gascity-thing-forward)
                  ("SPC" . gascity-thing-toggle) ("q" . quit-window)
                  ("j" . gascity-jump-prefix) ("?" . gascity-dispatch)))
    (should (eq (keymap-lookup gascity-runs-mode-map (car pair)) (cdr pair))))
  (dolist (pair '(("g" . gascity-run-refresh) ("RET" . gascity-run-activate)
                  ("o" . gascity-run-open-artifact)
                  ("b" . gascity-run-root-bead) ("C" . gascity-run-toggle-control)
                  ("I" . gascity-run-inspect) ("w" . gascity-run-copy-id)
                  ("!" . gascity-run-diagnose)
                  ("i" . gascity-runs-agent-detail) ("t" . gascity-runs-agent-tmux)
                  ("SPC" . gascity-thing-toggle) ("N" . gascity-section-next)))
    (should (eq (keymap-lookup gascity-run-mode-map (car pair)) (cdr pair))))
  (should (commandp 'gascity-runs))
  (should (commandp 'gascity-run-show)))

(ert-deftest gascity-test-runs-filter-letters ()
  "The Runs `/' menu uses the §5.5 letters, `x' resets."
  (dolist (key '("-r" "-F" "-s" "-W" "x"))
    (should (transient-get-suffix 'gascity-runs-filter key))))

(ert-deftest gascity-test-runs-jump-r-opens-runs ()
  "`j r' calls the Runs command."
  (let (called)
    (cl-letf (((symbol-function 'gascity-runs)
               (lambda () (interactive) (setq called t))))
      (gascity-jump-runs)
      (should called))))

;;; Mounted views (movement, toggles, RET)

(defvar gascity-runs-test--events []
  "Events the serve stub answers for `gc events --since'.")

(defun gascity-runs-test--serve (beads)
  "Return a canned `gascity-reader-read-async' serving BEADS for beads.el."
  (lambda (args callback &optional _errback &rest _)
    (funcall
     callback
     (pcase args
       (`("rig" "list") (gascity-runs-test--json "emacs-city.rig-list.json"))
       (`("session" "list") gascity-runs-test--sessions)
       (`("convoy" "status" ,id)
        `((convoy . ((id . ,id) (status . "closed") (title . "input")))
          (progress . ((closed . 7) (total . 7)))))
       ;; The inspector's recent events: none by default, so a rendered
       ;; drawer is deterministic.  A line-mode read's payload is
       ;; (GOOD . BAD), exactly as `gascity-reader-read-async' delivers it.
       (`("events" . ,_) (cons gascity-runs-test--events 0))
       (`("bd" "list" . ,rest)
        (if (member "beads.el" rest)
            (vconcat (seq-filter
                      (lambda (b)
                        (if (member "gc.kind=workflow" rest)
                            (gascity-dashboard--run-root-p b)
                          (gascity-dashboard--root-of b)))
                      beads))
          []))
       (_ (error "Unexpected read %S" args))))
    nil))

(defmacro gascity-runs-test--with-view (beads mount &rest body)
  "Mount MOUNT (a vui component form) over BEADS; run BODY in its buffer."
  (declare (indent 2))
  `(let ((vui-render-delay nil)
         (gascity-runs-filters nil)
         (gascity-runs-failed-window "36500d")
         (buf (get-buffer-create "*gascity-runs-test*")))
     (setq gascity-runs--index-cache (cons nil nil))
     (cl-letf (((symbol-function 'gascity-reader-read-async)
                (gascity-runs-test--serve ,beads))
               ((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
               ((symbol-function 'gascity-rigs-remember) (lambda (r &rest _) r)))
       (unwind-protect
           (save-window-excursion
             (vui-mount ,mount (buffer-name buf))
             (with-current-buffer buf ,@body))
         (kill-buffer buf)))))

(ert-deftest gascity-test-runs-movement-and-toggles ()
  "TAB visits section headers and whole cards in order; SPC opens a card's
ladder drawer, folds a section; RET opens the run detail with its rig."
  (gascity-runs-test--with-view (gascity-runs-test--active-beads)
      (progn (with-current-buffer buf (gascity-runs-mode))
             (vui-component 'gascity-runs-app :initial-filters nil))
    (let* ((starts (beads-thing-starts))
           (kinds (mapcar (lambda (p) (plist-get (get-text-property p 'beads-thing) :kind))
                          starts)))
      (should (equal kinds '(section row section row)))
      ;; The title line is decoration.
      (should-not (get-text-property (point-min) 'beads-thing))
      (goto-char (point-min))
      (gascity-thing-forward 1)
      (should (looking-at "Active"))
      (gascity-thing-forward 1)
      (should (looking-at "  ⬣ be-52m5"))
      ;; The card's second line belongs to the same thing: TAB skips it.
      (gascity-thing-forward 1)
      (should (looking-at "Failed"))
      (gascity-thing-backward 1)
      (should (looking-at "  ⬣ be-52m5")))
    ;; SPC: the ladder drawer, one line per step.
    (gascity-thing-toggle)
    (should (string-match-p "│ ◆ prepare +be-5aht" (buffer-string)))
    (should (string-match-p "│ ⬣ requirements" (buffer-string)))
    (gascity-runs-refresh)
    (should (string-match-p "│ ◆ prepare" (buffer-string)))
    (goto-char (point-min))
    (re-search-forward "^  ⬣ be-52m5")
    (gascity-thing-toggle)
    (should-not (string-match-p "│ ◆ prepare" (buffer-string)))
    ;; RET on the card's second line opens the detail, scoped to the rig.
    (forward-line 1)
    (let (opened)
      (cl-letf (((symbol-function 'gascity-run-show)
                 (lambda (run &optional _convoy rig) (setq opened (list run rig)))))
        (gascity-runs-activate))
      (should (equal opened '("be-52m5" "beads.el"))))
    ;; `F' follows the same run the momentary launch offer pointed at
    ;; (ga-40tbg.4), and refuses when point holds no run.
    (let (opened)
      (cl-letf (((symbol-function 'gascity-run-show)
                 (lambda (run &optional _convoy rig) (setq opened (list run rig)))))
        (gascity-runs-follow))
      (should (equal opened '("be-52m5" "beads.el"))))
    (goto-char (point-min))
    (should-error (gascity-runs-follow) :type 'user-error)
    ;; `H' adds the history; SPC on a header folds it.
    (gascity-runs-history)
    (should (string-match-p "^Closed  2$" (buffer-string)))
    (goto-char (point-min))
    (re-search-forward "^Failed")
    (beginning-of-line)
    (gascity-thing-toggle)
    (should (string-match-p "^▸ Failed" (buffer-string)))
    (should-not (string-match-p "^  ✕ be-bn2 +build-basic +beads.el +[0-9]" (buffer-string)))))

(ert-deftest gascity-test-runs-filter-rerenders-and-remembers ()
  "A `/' change applies at once and is remembered for the city."
  (gascity-runs-test--with-view (gascity-runs-test--active-beads)
      (progn (with-current-buffer buf (gascity-runs-mode))
             (vui-component 'gascity-runs-app :initial-filters nil))
    (gascity-filter-set :state "failed")
    (should-not (string-match-p "^Active" (buffer-string)))
    (should (string-match-p "^Failed" (buffer-string)))
    (should (equal (plist-get (cdar gascity-runs-filters) :state) "failed"))
    (should (member "build-basic" gascity-runs--formulas))
    (funcall gascity-filter-reset-function)
    (should (string-match-p "^Active" (buffer-string)))))

(ert-deftest gascity-test-runs-root-bead-and-worker-keys ()
  "`b' shows the run's root bead in its rig store; `i' on a card reaches
the live worker, and says so when there is none."
  (gascity-runs-test--with-view (gascity-runs-test--active-beads)
      (progn (with-current-buffer buf (gascity-runs-mode))
             (vui-component 'gascity-runs-app :initial-filters nil))
    (goto-char (point-min))
    (re-search-forward "^  ⬣ be-52m5")
    (let (shown detail)
      (cl-letf (((symbol-function 'gascity-beads--show-in-store)
                 (lambda (id store) (setq shown (list id store))))
                ((symbol-function 'gascity-beads--rig-store-cached)
                 (lambda (rig) (concat "/stores/" rig "/")))
                ((symbol-function 'gascity-polecat-detail-at-point)
                 (lambda () (interactive)
                   (setq detail (gascity-agent-name (gascity-agent-at-point))))))
        (gascity-runs-root-bead)
        (should (equal shown '("be-52m5" "/stores/beads.el/")))
        (gascity-runs-agent-detail)
        (should (equal detail "beads.el/gc.requirements-planner-1"))
        (re-search-forward "^  ✕ be-bn2")
        (should-error (gascity-runs-agent-detail) :type 'user-error)))))

;;; Run detail

(defun gascity-runs-test--tree-names (nodes)
  "Return NODES as a nested list of names."
  (mapcar (lambda (n)
            (if (plist-get n :children)
                (cons (plist-get n :name)
                      (gascity-runs-test--tree-names (plist-get n :children)))
              (plist-get n :name)))
          nodes))

(ert-deftest gascity-test-run-tree-from-real-graph ()
  "The step tree nests iterations and loops under their step, drain members
under the drain step, and hides control nodes until asked."
  (let* ((beads (gascity-runs-test--fixture-beads))
         (index (gascity-runs-test--index beads))
         (root (seq-find (lambda (r) (equal (alist-get 'id r) "be-bn2"))
                         (plist-get index :roots)))
         (graph (gascity-runs-graph index "be-bn2"))
         (tree (gascity-run-tree root graph))
         (names (gascity-runs-test--tree-names tree)))
    (should (equal (mapcar (lambda (n) (if (consp n) (car n) n)) names)
                   '("prepare" "requirements" "plan" "plan-review" "decompose"
                     "implement" "summarize-implementation" "review" "finalize"
                     "publish")))
    (should (equal (assoc "requirements" names) '("requirements" "iteration 1")))
    (should (equal (assoc "review" names)
                   '("review" "setup-build-basic-review"
                     ("build-basic-review-loop"
                      ("iteration 1" "acceptance-review" "test-evidence-review"
                       "simplicity-review" "synthesize-review"
                       "apply-review-findings"))
                     "iteration 1")))
    ;; Eight drain members (work items, no step ref) under implement.
    (should (= 8 (length (cdr (assoc "implement" names)))))
    ;; Control nodes: spec / scope-check / workflow-finalize.
    (let ((all (flatten-tree (gascity-runs-test--tree-names
                              (gascity-run-tree root graph t)))))
      (should (member "workflow-finalize" all))
      (should (member "spec" all))
      (should (member "test-evidence-review-scope-check" all)))
    (should-not (member "spec" (flatten-tree names)))))

(ert-deftest gascity-test-run-plans-from-root-metadata ()
  "The plans line lists every gc.build.*_path once, in metadata order."
  (let* ((root (seq-find (lambda (b) (equal (alist-get 'id b) "be-52m5"))
                         (gascity-runs-test--fixture-beads)))
         (plans (gascity-run-plans root)))
    (should (equal (mapcar (lambda (p) (file-name-nondirectory (cdr p))) plans)
                   '("decomposition.md" "factory-run.md" "implementation-summary.md"
                     "implementation-plan.md" "requirements.md" "review-report.md")))
    (should (equal (cdar plans)
                   "/home/roman/workspace/beads.el/plans/project-switch-scope/decomposition.md"))))

(ert-deftest gascity-test-run-plans-relative-to-work-dir ()
  "A relative plan path is joined to the run's gc.work_dir."
  (let ((root '((id . "hw-hry")
                (metadata . ((gc.build.review_report_path
                              . "plans/x/review-report.md")
                             (gc.work_dir . "/home/roman/hello-world"))))))
    (should (equal (gascity-run-plans root)
                   '(("gc.build.review_report_path"
                      . "/home/roman/hello-world/plans/x/review-report.md"))))))

(defmacro gascity-runs-test--with-detail (beads run &rest body)
  "Mount the run detail of RUN over BEADS; run BODY in its buffer."
  (declare (indent 2))
  `(gascity-runs-test--with-view ,beads
       (progn (with-current-buffer buf
                (gascity-run-mode)
                (setq gascity-run--current-run ,run
                      gascity-run--current-rig "beads.el"))
              (vui-component 'gascity-run-app :run-id ,run :city "emacs-city"))
     ,@body))

(ert-deftest gascity-test-run-detail-renders-active-run ()
  "The detail shows the header, plans, convoy and the step list with the
active step's live worker; loops fold."
  (gascity-test-with-fixture-home
    (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
				    (let ((text (buffer-string)))
				      (should (string-match-p "^  root     ⬣ be-52m5  build-basic +beads.el · started 2h$" text))
				      (should (string-match-p "^  formula  build-basic  contract graph.v2$" text))
				      (should (string-match-p "^           source ~/.gc/cache/…/build-basic.formula.toml$"
							      (replace-regexp-in-string
							       "/home/[^/]+/" "~/" text)))
				      (should (string-match-p "^  plans    decomposition.md · factory-run.md" text))
				      (should (string-match-p "^  convoy   be-93dg  closed 7/7  input$" text))
				      ;; The summary names the graph-bead count, not the anchor
				      ;; count (37 beads: iterations, drains, nested steps).
				      (should (string-match-p
					       "^Steps  1/10 · 37 beads +C show control nodes$" text))
				      ;; Stages come first, in table order.
				      (should (string-match-p "^  ▾ ⬣ Intake +1/5$" text))
				      (should (string-match-p
					       "^    ◆ prepare +be-5aht +pass +run-operator" text))
				      (should (string-match-p
					       "^    ⬣ requirements +be-fy7m +iter 1 +● requirements-planner-1 +3m$"
					       text))
				      (should (string-match-p "^  ▾ · Implementation +0/2$" text))
				      (should (string-match-p "^  ▾ · Review +0/1$" text))
				      ;; The full five-stage group set renders (Approval has no
				      ;; members but is not dropped), matching the pure partition.
				      (should (string-match-p "^  ▾ · Approval +0/0$" text))
				      (should (string-match-p "^  ▾ · Finalization +0/2$" text))
				      ;; Quiet loops start folded.
				      (should (string-match-p "^    ▸ review +be-mqhp +· loop" text))
				      (should-not (string-match-p "setup-build-basic-review" text)))
				    ;; SPC on a fold row expands it in place; state survives a refresh.
				    (goto-char (point-min))
				    (re-search-forward "^    ▸ review")
				    (gascity-thing-toggle)
				    (should (string-match-p "^    ▾ review" (buffer-string)))
				    (should (string-match-p "^      · setup-build-basic-review" (buffer-string)))
				    (gascity-run-refresh)
				    (should (string-match-p "^    ▾ review" (buffer-string)))
				    ;; SPC on a step row opens its drawer: the step inspector's
				    ;; ref/bead/status, attempt/iteration, live worker, artifacts
				    ;; and healthy failure line.
				    (goto-char (point-min))
				    (re-search-forward "^    ⬣ requirements")
				    (gascity-thing-toggle)
				    (should (string-match-p
					     "│ step     build-basic.requirements  be-fy7m  in_progress"
					     (buffer-string)))
				    (should (string-match-p "│ attempt  1 · iteration bead be-bcb5"
							    (buffer-string)))
				    (should (string-match-p
					     "│ worker   gc__requirements-planner-ec-fl8o  ● requirements-planner-1"
					     (buffer-string)))
				    (should (string-match-p "│ artifacts run   decomposition.md (missing)"
							    (buffer-string)))
				    (should (string-match-p "│ failure  (none)" (buffer-string)))
				    ;; C shows the control nodes.
				    (gascity-run-toggle-control)
				    (should (string-match-p "C hide control nodes" (buffer-string)))
				    (should (string-match-p "workflow-finalize" (buffer-string))))))

(ert-deftest gascity-test-run-detail-keys-act ()
  "RET on a step opens its bead in the run's store, on a plan visits it on
the city's host; `b' opens the root; `i' reaches the live assignee."
  (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
    (let (shown visited detail)
      (cl-letf (((symbol-function 'gascity-beads--show-in-store)
                 (lambda (id store) (setq shown (list id store))))
                ((symbol-function 'gascity-beads--rig-store-cached)
                 (lambda (rig) (concat "/stores/" rig "/")))
                ((symbol-function 'find-file)
                 (lambda (f &rest _) (setq visited f)))
                ((symbol-function 'file-exists-p) (lambda (&rest _) t))
                ((symbol-function 'gascity-polecat-detail-at-point)
                 (lambda () (interactive)
                   (setq detail (gascity-agent-name (gascity-agent-at-point))))))
        (goto-char (point-min))
        (re-search-forward "^    ◆ prepare")
        (gascity-run-activate)
        (should (equal shown '("be-5aht" "/stores/beads.el/")))
        (gascity-run-root-bead)
        (should (equal shown '("be-52m5" "/stores/beads.el/")))
        (goto-char (point-min))
        (re-search-forward "requirements.md")
        (backward-char 2)
        (gascity-run-activate)
        (should (string-suffix-p "project-switch-scope/requirements.md" visited))
        ;; On a remote city the plan opens on its host (R6).
        (let ((default-directory "/ssh:host:/home/roman/emacs-city/"))
          (gascity-run-activate)
          (should (equal visited (concat "/ssh:host:/home/roman/workspace/beads.el/"
                                         "plans/project-switch-scope/requirements.md"))))
        (goto-char (point-min))
        (re-search-forward "^    ⬣ requirements")
        (gascity-runs-agent-detail)
        (should (equal detail "beads.el/gc.requirements-planner-1"))
        (goto-char (point-min))
        (re-search-forward "^    ◆ prepare")
        (should-error (gascity-runs-agent-detail) :type 'user-error)))))

(ert-deftest gascity-test-run-detail-acts-without-a-rig-use-the-run-s-store ()
  "RET/`b' resolve the store from the payload when no rig was passed.
This is how `M-x gascity-run-show' opens a run: the buffer knows only
its city, so the step bead's `gascity-rig' stamp must supply the store
or the delegation opens the bead in the city store and fails."
  (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
    (let (shown)
      (cl-letf (((symbol-function 'gascity-beads--show-in-store)
                 (lambda (id store) (setq shown (list id store))))
                ((symbol-function 'gascity-beads--rig-store-cached)
                 (lambda (rig) (concat "/stores/" rig "/"))))
        (setq gascity-run--current-rig nil)
        (goto-char (point-min))
        (re-search-forward "^    ◆ prepare")
        (gascity-run-activate)
        (should (equal shown '("be-5aht" "/stores/beads.el/")))
        (gascity-run-root-bead)
        (should (equal shown '("be-52m5" "/stores/beads.el/")))))))

(ert-deftest gascity-test-run-artifact-open ()
  "`o' and RET visit the header's plan and formula source and a step
  drawer's artifact; each one carries the `gascity-run-file' property
  (REQ-002)."
  (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
    (let (visited)
      (cl-letf (((symbol-function 'find-file)
                 (lambda (f &rest _) (setq visited f)))
                ((symbol-function 'file-exists-p) (lambda (&rest _) t)))
        ;; The header's plans entry.
        (goto-char (point-min))
        (re-search-forward "^  plans")
        (re-search-forward "requirements\\.md")
        (backward-char 2)
        (should (get-text-property (point) 'gascity-run-file))
        (gascity-run-open-artifact)
        (should (string-suffix-p "project-switch-scope/requirements.md" visited))
        ;; `o' visits exactly what RET visits.
        (setq visited nil)
        (gascity-run-activate)
        (should (string-suffix-p "project-switch-scope/requirements.md" visited))
        ;; The header's formula source entry.
        (setq visited nil)
        (goto-char (point-min))
        (re-search-forward "^           source")
        (re-search-forward "build-basic\\.formula\\.toml")
        (backward-char 2)
        (should (get-text-property (point) 'gascity-run-file))
        (gascity-run-open-artifact)
        (should (string-suffix-p "build-basic.formula.toml" visited))
        ;; A step drawer's artifact.
        (setq visited nil)
        (goto-char (point-min))
        (re-search-forward "^    ⬣ requirements")
        (gascity-thing-toggle)
        (re-search-forward "│ artifacts run   ")
        (re-search-forward "decomposition\\.md")
        (backward-char 2)
        (should (get-text-property (point) 'gascity-run-file))
        (gascity-run-open-artifact)
        (should (string-suffix-p "project-switch-scope/decomposition.md" visited)))
      ;; A row that is not an artifact says so.
      (goto-char (point-min))
      (re-search-forward "^    ⬣ requirements")
      (should-error (gascity-run-open-artifact) :type 'user-error))))

(ert-deftest gascity-test-run-artifact-missing ()
  "A local missing artifact is a clear `No such file' error and leaves
  the buffer intact; a remote artifact is never stat'ed on the way to
  the file-name handler (REQ-002)."
  (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
    (let ((before (buffer-string)))
      (goto-char (point-min))
      (re-search-forward "^  plans")
      (re-search-forward "requirements\\.md")
      (backward-char 2)
      (should (string-match-p
               "No such file"
               (condition-case err
                   (progn (gascity-run-open-artifact) "")
                 (user-error (error-message-string err)))))
      (should (equal (buffer-string) before))
      (should (get-text-property (point) 'gascity-run-file)))
    ;; A remote path keeps the file-name handler's own error: no local stat.
    (let ((default-directory "/ssh:host:/home/roman/emacs-city/") visited)
      (cl-letf (((symbol-function 'find-file)
                 (lambda (f &rest _) (setq visited f)))
                ((symbol-function 'file-exists-p)
                 (lambda (&rest _) (error "stat on a remote artifact"))))
        (gascity-run-visit-file "/home/roman/workspace/beads.el/plans/x.md"))
      (should (equal visited
                     "/ssh:host:/home/roman/workspace/beads.el/plans/x.md")))))

(ert-deftest gascity-test-run-header-provenance ()
  "The header names the run's root, store/rig/city, scope, formula
  \(name, contract, graph key, source) and convoy; an absent scope reads
  `(none)' rather than an invented value (REQ-003)."
  (gascity-test-with-fixture-home
    (let* ((convoy (cons '((id . "be-93dg") (status . "closed") (title . "input"))
                       '((closed . 7) (total . 7))))
           (text (gascity-runs-test--text
                  (gascity-runs-test--header
                   (gascity-runs-test--active-beads) "be-52m5" :convoy convoy))))
      (should (string-match-p
               "\\`  root     ⬣ be-52m5  build-basic +beads.el · started 2h$" text))
      (should (string-match-p "^  store    rig:beads.el   rig beads.el   city emacs-city$"
                              text))
      (should (string-match-p "^  scope    (none)$" text))
      (should (string-match-p "^  formula  build-basic  contract graph.v2$" text))
      (should (string-match-p
               "^           key graphv2-root:be-93dg:build-basic:296b212076d7ae2e:default$"
               text))
      (should (string-match-p "^           source ~/.gc/cache/…/build-basic.formula.toml$"
                              text))
      (should (string-match-p "^  plans    decomposition.md · factory-run.md" text))
      (should (string-match-p "^  convoy   be-93dg  closed 7/7  input$" text)))))

(ert-deftest gascity-test-run-header-absent ()
  "A root without optional provenance shows `(none)'/'city store' only
  where the row exists for that fact: no key or source continuation, no
  empty label, and nothing derived or invented (REQ-003)."
  (gascity-test-with-fixture-home
    (let* ((beads
            (mapcar
             (lambda (b)
               (if (equal (alist-get 'id b) "be-52m5")
                   (let ((meta (seq-remove
                                (lambda (cell)
                                  (memq (car cell)
                                        '(gc.root_store_ref gc.var.rig_name
                                          gc.graphv2_root_key gc.formula_source
                                          gc.scope_ref)))
                                (alist-get 'metadata b))))
                     (cons (cons 'metadata meta)
                           (seq-remove (lambda (cell) (eq (car cell) 'metadata)) b)))
                 b))
             (gascity-runs-test--active-beads)))
           (text (gascity-runs-test--text
                  (gascity-runs-test--header beads "be-52m5"))))
      (should (string-match-p "^  store    city store   city emacs-city$" text))
      (should (string-match-p "^  scope    (none)$" text))
      (should (string-match-p "^  formula  build-basic  contract graph.v2$" text))
      (should-not (string-match-p "^           key " text))
      (should-not (string-match-p "^           source " text))
      (should-not (string-match-p "graphv2-root" text))
      (should-not (string-match-p "^  [a-z]+ +$" text))
      (should-not (string-match-p "^  convoy " text)))))

(ert-deftest gascity-test-run-header-width ()
  "Every header row is at most 78 columns, including a real 59-column
  graph key and a longer one that is truncated with `…' (REQ-003)."
  (let* ((now (float-time))
         (time (format-time-string "%FT%TZ" (- now 3600) t))
         (key59 (concat "graphv2-root:" (make-string 46 ?a)))
         (key70 "graphv2-root:ga-c4pou:do-work:7ec5a43679a84153:drain=ga-kuvhc:ga-kci2d")
         (root
          (lambda (key)
            `((id . "hw-wide") (status . "closed") (closed_at . ,time)
              (metadata . ((gc.formula_name . "build-basic")
                           (gc.formula_contract . "graph.v2")
                           (gc.graphv2_root_key . ,key)
                           (gc.formula_source
                            . ,(concat "/home/roman/workspace/"
                                       (make-string 90 ?s)
                                       "/build-basic.formula.toml"))
                           (gc.scope_ref . ,(concat "stage." (make-string 80 ?s)))
                           (gc.root_store_ref . "rig:a-rather-long-rig-name")
                           (gc.var.rig_name . "a-rather-long-rig-name"))))))
         (run (list :id "hw-wide" :formula "build-basic" :state 'done
                    :outcome "pass" :rig "a-rather-long-rig-name" :time time)))
    (should (= 59 (length key59)))
    (dolist (key (list key59 key70))
      (let ((lines (gascity-run--header-lines
                    run (funcall root key)
                    (list :now now :city "a-rather-long-city-name"))))
        (ert-info ((format "key width %d" (length key)))
          (dolist (line lines)
            (ert-info ((format "row %S" (substring-no-properties line)))
              (should (<= (string-width line) gascity-dashboard--width))))
          (let ((key-line (seq-find (lambda (l) (string-match-p "^           key " l))
                                    lines)))
            (should key-line)
            (if (= (length key) 59)
                (should (string-match-p (concat "key " (regexp-quote key)) key-line))
              (should (string-match-p "…" key-line)))))))))

(ert-deftest gascity-test-run-detail-failed-run-opens-failure ()
  "A failed run's loop containing the failure starts expanded down to it."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    (let ((text (buffer-string)))
      (should (string-match-p "^  root     ✕ be-bn2  build-basic  fail" text))
      (should (string-match-p "^Steps  9/10 · 45 beads" text))
      (should (string-match-p "^  ▾ ✕ Review +0/1 +failed" text))
      (should (string-match-p "^    ▾ review +be-fkq +✕ loop" text))
      (should (string-match-p "^      ▾ build-basic-review-loop +be-1bn +✕ loop" text)))))

(ert-deftest gascity-test-run-detail-agrees-with-ladder ()
  "The detail's top-level steps carry the ladder's state and ids: be-bn2's
review is ✕ in both (its nested loop failed), and every row id is the
step id the ladder drawer shows.  Acceptance item 7."
  (let* ((index (gascity-runs-test--index (gascity-runs-test--fixture-beads)))
         (root (seq-find (lambda (r) (equal (alist-get 'id r) "be-bn2"))
                         (plist-get index :roots)))
         (graph (gascity-runs-graph index "be-bn2"))
         (ladder (gascity-runs-ladder index root))
         (tree (gascity-run-annotate (gascity-run-tree root graph) root graph ladder)))
    (should (equal (mapcar (lambda (n) (alist-get 'id (plist-get n :bead))) tree)
                   (mapcar (lambda (s) (plist-get s :id)) ladder)))
    (should (equal (mapcar (lambda (n) (plist-get n :state)) tree)
                   (mapcar (lambda (s) (plist-get s :state)) ladder)))
    ;; The nested loop that failed, and the step above it, are ✕.
    (let* ((review (seq-find (lambda (n) (equal (plist-get n :name) "review")) tree))
           (loop (seq-find (lambda (n) (equal (plist-get n :name)
                                              "build-basic-review-loop"))
                           (plist-get review :children))))
      (should (eq (plist-get review :state) 'failed))
      (should (eq (plist-get loop :state) 'failed))))
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    (let ((text (buffer-string)))
      ;; Rows name the step ids of the ladder drawer (be-yam, not be-59r).
      (should (string-match-p "^    ◆ requirements +be-yam +iter 1" text))
      (should (string-match-p "^    ▾ review +be-fkq +✕ loop" text))
      (should (string-match-p "^      ▾ build-basic-review-loop +be-1bn +✕ loop" text))
      (should-not (string-match-p "be-59r" text)))
    ;; The iteration id is in the drawer.
    (goto-char (point-min))
    (re-search-forward "^    ◆ requirements")
    (gascity-thing-toggle)
    (should (string-match-p "│ attempt  1 · iteration bead be-59r"
                            (buffer-string)))))

(ert-deftest gascity-test-run-detail-stage-groups ()
  "A mapped formula's anchors render under the five lifecycle stage
headers in table order; the summary names the graph-bead count, and C
adds the trailing Control group without changing stage progress."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    (let ((text (buffer-string))
          (labels '("Intake" "Implementation" "Review" "Approval" "Finalization")))
      ;; Five stage headers, in table order, with their members counted.
      (let ((positions
             (mapcar (lambda (label)
                       (string-match (concat "^  [▾▸] [^ ]+ " label " +[0-9]+/[0-9]+")
                                     text))
                     labels)))
        (should (seq-every-p #'integerp positions))
        (should (equal positions (sort (copy-sequence positions) #'<))))
      (should (string-match-p "^  ▾ ◆ Intake +5/5$" text))
      (should (string-match-p "^  ▾ ◆ Implementation +2/2$" text))
      (should (string-match-p "^  ▾ ✕ Review +0/1 +failed$" text))
      ;; Approval has no members and is not dropped.
      (should (string-match-p "^  ▾ · Approval +0/0$" text))
      (should (string-match-p "^  ▾ ◆ Finalization +2/2$" text))
      ;; Members under their own stage, at depth 1.
      (should (string-match-p "^    ◆ prepare +be-e29" text))
      (should (string-match-p "^    ▸ implement +be-jxy +◆ drain" text))
      (should (string-match-p "^    ▾ review +be-fkq +✕ loop" text))
      (should (string-match-p "^    ◆ publish +be-gez" text))
      ;; The summary counts graph beads (45), not stage anchors (10).
      (should (string-match-p "^Steps  9/10 · 45 beads" text))
      ;; A failed stage says so and carries the class and member states.
      (goto-char (point-min))
      (re-search-forward "^  ▾ ✕ Review")
      (let ((help (get-text-property (line-beginning-position) 'help-echo)))
        (should (stringp help))
        (should (string-match-p "hard: control_dispatch_error" help))
        (should (string-match-p "review failed" help)))
      ;; C adds one trailing Control group of the nested control nodes
      ;; and leaves stage progress alone.
      (should-not (string-match-p "^  [▾▸] [^ ]+ Control" text))
      (gascity-run-toggle-control)
      (let ((with-control (buffer-string)))
        (should (string-match-p "^  ▾ ◆ Control +13/13$" with-control))
        (should (string-match-p "^    ◆ workflow-finalize +be-9bp" with-control))
        (should (string-match-p "^Steps  9/10 · 45 beads" with-control))
        (should (string-match-p "^  ▾ ✕ Review +0/1 +failed$" with-control))))))

(ert-deftest gascity-test-run-detail-stage-folds-keep-point ()
  "Collapsing a stage hides its members and their drawers, leaves the
other stages alone, and survives a refresh with point on the header."
  (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
    ;; Open the requirements drawer, then collapse Intake: the drawer goes
    ;; with the members, Implementation keeps its own rows.
    (goto-char (point-min))
    (re-search-forward "^    ⬣ requirements")
    (gascity-thing-toggle)
    (should (string-match-p "│ step     build-basic.requirements" (buffer-string)))
    (goto-char (point-min))
    (re-search-forward "^  ▾ ⬣ Intake")
    (gascity-thing-toggle)
    (let ((text (buffer-string)))
      (should (string-match-p "^  ▸ ⬣ Intake" text))
      (should-not (string-match-p "^    ◆ prepare" text))
      (should-not (string-match-p "requirements.iteration.1" text))
      ;; Siblings untouched.
      (should (string-match-p "^  ▾ · Implementation +0/2$" text))
      (should (string-match-p "^    · implement" text)))
    ;; Point stays on the collapsed header across a refresh.
    (goto-char (point-min))
    (re-search-forward "^  ▸ ⬣ Intake")
    (let ((p (point)))
      (gascity-run-refresh)
      (should (string-match-p "^  ▸ ⬣ Intake" (buffer-string)))
      (should (string-match-p "Intake" (thing-at-point 'line t)))
      (should (= (point) p)))
    ;; An open drawer and its expanded stage survive a refresh too.
    (goto-char (point-min))
    (re-search-forward "^    · implement")
    (gascity-thing-toggle)
    (should (string-match-p "│ step     build-basic\\.implement" (buffer-string)))
    (gascity-run-refresh)
    (should (string-match-p "^  ▾ · Implementation +0/2$" (buffer-string)))
    (should (string-match-p "│ step     build-basic\\.implement" (buffer-string)))))

(ert-deftest gascity-test-run-detail-flat-fallback ()
  "A formula with no stage table keeps today's flat rows byte-identical
\(depth 0, no stage headers); only the summary gains the bead count."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-qrpg"
    (let ((text (buffer-string)))
      (should (string-match-p "^Steps  3/3 · 6 beads" text))
      (should-not (string-match-p "Intake\|Implementation\|Finalization" text))
      (should (string-match-p
               "^  ◆ prepare-worktree +be-pr6j +pass +run-operator" text))
      (should (string-match-p "^  ◆ implement +be-3rij +iter 1" text))
      (should (string-match-p "^  ◆ close-source-anchor +be-j571 +pass" text)))))

(ert-deftest gascity-test-run-detail-cold-store ()
  "A pending store keeps the run header and the Steps section, shows no
stage groups, and never signals."
  (let* ((ctx (list :run-id "be-bn2" :now (float-time)
                    :loads '(:beads (:state pending))
                    :index (gascity-runs-test--index nil)
                    :sessions nil :socket nil :convoy nil :view nil))
         (text (gascity-runs-test--text (gascity-run-lines ctx))))
    (should (string-match-p "^· be-bn2" text))
    (should (string-match-p "^Steps  …" text))
    (should-not (string-match-p "Intake\|Review\|Finalization" text))))

(ert-deftest gascity-test-run-detail-empty-graph ()
  "A mapped formula with an empty graph renders the five stage headers
at 0/0 and no members, never an error."
  (let* ((root `((id . "hw-empty") (status . "in_progress")
                 (issue_type . "task")
                 (metadata . ((gc.kind . "workflow")
                              (gc.formula_name . "build-basic")))))
         (index (gascity-runs-test--index (list root)))
         (ctx (list :run-id "hw-empty" :now (float-time)
                    :loads (list :beads (gascity-runs-test--load
                                         (list :beads (list root))))
                    :index index :sessions nil :socket nil :convoy nil
                    :view nil))
         (text (gascity-runs-test--text (gascity-run-lines ctx))))
    (should (string-match-p "^Steps  0/0 · 0 beads" text))
    (dolist (label '("Intake" "Implementation" "Review" "Approval"
                     "Finalization"))
      (should (string-match-p (concat "^  ▾ · " label " +0/0$") text)))
    (should-not (string-match-p "^    " text))))

(ert-deftest gascity-test-run-detail-not-found ()
  "A run id in no store renders a not-found line, never a blank pane."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-nope"
    (should (string-match-p "run be-nope not found in the city's stores   g retry"
                            (buffer-string)))))

(ert-deftest gascity-test-run-show-per-run-buffer ()
  "`gascity-run-show' opens `*gascity-run: ID*' through the view factory;
the same run again refreshes in place."
  (let ((bases nil) (mounts 0))
    (cl-letf (((symbol-function 'gascity-view-get-buffer-create)
               (lambda (base &optional _dir)
                 (push base bases)
                 (get-buffer-create (concat base "<fake>"))))
              ((symbol-function 'gascity-context-city-for-view)
               (lambda (&rest _) "/home/roman/emacs-city/"))
              ((symbol-function 'gascity-context-city-name) (lambda (&rest _) "emacs-city"))
              ((symbol-function 'gascity-section-refresh-instance)
               (lambda (_buf) (> mounts 0)))
              ((symbol-function 'vui-mount) (lambda (&rest _) (cl-incf mounts)))
              ((symbol-function 'pop-to-buffer) #'ignore))
      (unwind-protect
          (progn
            (gascity-run-show "be-52m5" nil "beads.el")
            (gascity-run-show "be-52m5" nil "beads.el")
            (should (equal bases '("*gascity-run: be-52m5*" "*gascity-run: be-52m5*")))
            (should (= mounts 1))
            (with-current-buffer "*gascity-run: be-52m5*<fake>"
              (should (derived-mode-p 'gascity-run-mode))
              (should (equal gascity-run--current-rig "beads.el"))))
        (when (get-buffer "*gascity-run: be-52m5*<fake>")
          (kill-buffer "*gascity-run: be-52m5*<fake>"))))))

;;; Inspector (run-view-v2 §3)

(defun gascity-runs-test--inspector-run (tmp now)
  "Return the beads of a synthetic live requirements run in work dir TMP.
The root records a plan artifact; the requirements step records the
same plan (deduped), a publish artifact, a check script and a formula
input (both excluded), and its iteration records a missing artifact.
NOW pins the lease and heartbeat stamps."
  (list
   `((id . "hw-live") (status . "in_progress") (issue_type . "task")
     (created_at . ,(gascity-runs-test--ts 7200))
     (updated_at . ,(gascity-runs-test--ts 60))
     (metadata . ((gc.kind . "workflow")
                  (gc.formula_name . "build-basic")
                  (gc.work_dir . ,tmp)
                  (gc.build.plan_path . "plans/requirements.md"))))
   `((id . "hw-step") (status . "in_progress")
     (assignee . "gc__requirements-planner-ec-fl8o")
     (lease_expires_at . ,(format-time-string "%FT%TZ" (+ now 180) t))
     (heartbeat_at . ,(format-time-string "%FT%TZ" (- now 30) t))
     (updated_at . ,(gascity-runs-test--ts 60))
     (metadata . ((gc.root_bead_id . "hw-live")
                  (gc.step_ref . "build-basic.requirements")
                  (gc.attempt . "2")
                  (gc.work_dir . ,tmp)
                  (gc.build.requirements_path . "plans/requirements.md")
                  (gc.publish_artifact_path . "out/publish.md")
                  (gc.check_path . ".gc/checks/nope.sh")
                  (gc.var.plan_path . "plans/nope.md"))))
   `((id . "hw-iter") (status . "in_progress")
     (assignee . "gc__requirements-planner-ec-fl8o")
     (metadata . ((gc.root_bead_id . "hw-live")
                  (gc.step_ref . "requirements.iteration.1")
                  (gc.attempt . "2")
                  (gc.iteration . "1")
                  (gc.close_source_anchor.summary_path
                   . "plans/summary.md"))))))

(ert-deftest gascity-test-run-inspector-normal ()
  "A live step's inspector shows its facts, worker with liveness and lease,
run and step artifacts with sizes/ages and RET-able paths, the three
newest matching events, and a healthy `(none)' failure; a missing
artifact says so without erroring, and check/input paths stay out."
  (let* ((now (float (floor (float-time))))
         (tmp (make-temp-file "gascity-inspector-" t)))
    (unwind-protect
        (let* ((plan (expand-file-name "plans/requirements.md" tmp))
               (publish (expand-file-name "out/publish.md" tmp)))
          (make-directory (file-name-directory plan) t)
          (make-directory (file-name-directory publish) t)
          (with-temp-file plan (insert (make-string 12345 ?x)))
          (with-temp-file publish (insert (make-string 500 ?y)))
          (set-file-times plan (seconds-to-time (- now 180)))
          (set-file-times publish (seconds-to-time (- now 180)))
          (let* ((beads (gascity-runs-test--inspector-run tmp now))
                 (step (nth 1 beads))
                 (iteration (nth 2 beads))
                 (event (lambda (type ago bead)
                          `((type . ,type)
                            (ts . ,(format-time-string "%FT%TZ" (- now ago) t))
                            (payload . ((bead . ((id . ,bead))))))))
                 (events (list (funcall event "bead.reopened" 400 "hw-step")
                               (funcall event "bead.updated" 100 "hw-step")
                               (funcall event "bead.claimed" 200 "hw-iter")
                               (funcall event "bead.closed" 300 "hw-step")
                               (funcall event "order.fired" 10 "hw-other")))
                 (ctx (gascity-runs-test--inspector-ctx
                       beads "hw-live" :now now
                       :sessions (vector (gascity-runs-test--worker-session
                                          "ec-fl8o" now 20))
                       :events (list :state 'ready :data (cons events 0))))
                 (lines (gascity-run--step-drawer step iteration ctx))
                 (text (gascity-runs-test--text lines)))
            (should (equal (nth 0 lines)
                           "step     build-basic.requirements  hw-step  in_progress"))
            (should (equal (nth 1 lines)
                           "attempt  2 · iteration 1 · iteration bead hw-iter"))
            (should (equal (substring-no-properties (nth 2 lines)) "attempts"))
            (should (equal (substring-no-properties (nth 3 lines))
                           "  2   in_progr… ● requirements-pl…           (none)"))
            (should (equal (nth 4 lines)
                           (concat "worker   gc__requirements-planner-ec-fl8o"
                                   "  ● requirements-planner-1"
                                   "  session live · active 20s ago"
                                   "  claim lease 3m left · heartbeat 30s ago")))
            (should (equal (nth 5 lines)
                           "artifacts run   requirements.md (12 KB, 3m)"))
            (should (equal (nth 6 lines)
                           "artifacts step  publish.md (500 B, 3m) · summary.md (missing)"))
            ;; The three newest matching events, newest first; older and
            ;; unrelated events are left out.
            (should (equal (mapcar (lambda (line) (nth 1 (split-string line)))
                                   (seq-take (seq-drop lines 7) 3))
                           '("bead.updated" "bead.claimed" "bead.closed")))
            (should-not (string-match-p "bead\\.reopened" text))
            (should (equal (nth 10 lines) "failure  (none)"))
            (should (= (length lines) 11))
            ;; The check script and the formula input are never artifacts.
            (should-not (string-match-p "nope\\." text))
            ;; The root plan is shown once, and RET visits the local file.
            (should-not (string-match-p "requirements\\.md" (nth 6 lines)))
            (let ((offset (string-match "requirements\\.md" (nth 5 lines))))
              (should (equal (get-text-property offset 'gascity-run-file
                                                (nth 5 lines))
                             plan)))))
      (delete-directory tmp t))))

(ert-deftest gascity-test-run-inspector-failed ()
  "The be-bn2 fixture's failed review anchor names the class and reason
of the failed review loop beneath it."
  (let* ((beads (gascity-runs-test--fixture-beads))
         (step (seq-find (lambda (b) (equal (alist-get 'id b) "be-fkq")) beads))
         (ctx (gascity-runs-test--inspector-ctx beads "be-bn2"))
         (text (gascity-runs-test--text
                (gascity-run--step-drawer step nil ctx))))
    (should (string-match-p "^step     build-basic\\.review  be-fkq" text))
    (should (string-match-p "^failure  hard: control_dispatch_error" text))))

(ert-deftest gascity-test-run-inspector-no-session-no-artifacts ()
  "A step with no worker and no artifacts renders its facts, `no session'
and `(no recent events)', without an artifact line or an error."
  (let* ((root '((id . "hw-bare") (status . "in_progress")
                 (metadata . ((gc.kind . "workflow")
                              (gc.formula_name . "build-basic")))))
         (step '((id . "hw-bare-step") (status . "open")
                 (metadata . ((gc.root_bead_id . "hw-bare")
                              (gc.step_ref . "build-basic.prepare")))))
         (ctx (gascity-runs-test--inspector-ctx (list root step) "hw-bare"))
         (text (gascity-runs-test--text
                (gascity-run--step-drawer step nil ctx))))
    (should (string-match-p "^step     build-basic\\.prepare  hw-bare-step  open"
                            text))
    (should (string-match-p "^worker   no session" text))
    (should-not (string-match-p "artifacts" text))
    (should (string-match-p "^events   (no recent events)" text))
    (should (string-match-p "^failure  (none)" text))))

(ert-deftest gascity-test-run-inspector-cold-store ()
  "With no beads in the store the detail keeps its pending state, shows no
stage groups, and the inspector still renders without signaling."
  (let* ((ctx (list :run-id "hw-cold" :now (float-time)
                    :loads '(:beads (:state pending))
                    :index (gascity-runs-test--index nil)
                    :sessions nil :socket nil :convoy nil
                    :view (list :drawers '("step:hw-cold"))))
         (text (gascity-runs-test--text (gascity-run-lines ctx)))
         (step '((id . "hw-cold") (status . "open")
                 (metadata . ((gc.step_ref . "build-basic.prepare"))))))
    (should (string-match-p "^· hw-cold" text))
    (should (string-match-p "^Steps  …" text))
    (should-not (string-match-p "Intake\\|Review\\|Finalization" text))
    (should (string-match-p "^worker   no session"
                            (gascity-runs-test--text
                             (gascity-run--step-drawer step nil ctx))))
    ;; The pending state also mounts through the component itself.
    (let ((buf (get-buffer-create "*gascity-run-test-pending*"))
          (vui-render-delay nil))
      (cl-letf (((symbol-function 'gascity-runs-use-beads)
                 (lambda (&rest _) '(:status pending)))
                ((symbol-function 'gascity-store-use)
                 (lambda (&rest _) '(:status pending)))
                ((symbol-function 'gascity-rigs-remember)
                 (lambda (r &rest _) r)))
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-run-app :run-id "hw-cold" :city nil)
                         (buffer-name buf))
              (with-current-buffer buf
                (should (string-match-p "^· hw-cold" (buffer-string)))
                (should (string-match-p "^Steps  …" (buffer-string)))
                (should-not (string-match-p "Intake" (buffer-string)))))
          (kill-buffer buf))))))

(ert-deftest gascity-test-run-inspector-remote-artifacts ()
  "Under a TRAMP city the inspector never stats an artifact, and still
labels the worker's session and claim facts apart."
  (let* ((now (float (floor (float-time))))
         (beads (gascity-runs-test--inspector-run
                 "/home/roman/workspace/beads.el" now))
         (step (append `((lease_expires_at .
                          ,(format-time-string "%FT%TZ" (- now 240) t))
                         (heartbeat_at .
                          ,(format-time-string "%FT%TZ" (- now 540) t)))
                       (nth 1 beads)))
         (iteration (nth 2 beads))
         (ctx (gascity-runs-test--inspector-ctx
               beads "hw-live" :now now
               :sessions (vector (gascity-runs-test--worker-session
                                  "ec-fl8o" now 20))))
         (calls nil)
         (default-directory "/ssh:host:/home/roman/emacs-city/"))
    (cl-letf (((symbol-function 'file-attributes)
               (lambda (path &rest _)
                 (when (string-match-p "beads\\.el" (format "%s" path))
                   (push path calls))
                 nil)))
      (let ((text (gascity-runs-test--text
                   (gascity-run--step-drawer step iteration ctx))))
        (should (string-match-p "artifacts run   requirements\\.md (remote: not checked)"
                                text))
        (should (string-match-p "publish\\.md (remote: not checked)" text))
        (should (string-match-p "summary\\.md (remote: not checked)" text))
        (should (string-match-p "session live · active 20s ago" text))
        (should (string-match-p
                 "claim lease lapsed 4m ago · heartbeat 9m ago (Pi heartbeat gap)"
                 text))
        (should-not calls)))))

(ert-deftest gascity-test-run-inspector-live-session-lapsed-lease ()
  "A live worker whose claim lease lapsed is not reported dead.
The session row is the liveness fact (`session live · active 20s ago');
the lapsed lease is the bead's claim fact, and because the session was
active after the deadline it reads as the Pi heartbeat gap (ga-p2lfj)
the cockpit leaves unflagged (ga-o7vtw)."
  (let* ((now (float (floor (float-time))))
         (step `((id . "hw-step") (status . "in_progress")
                 (assignee . "gc__requirements-planner-ec-fl8o")
                 (lease_expires_at .
                  ,(format-time-string "%FT%TZ" (- now 240) t))
                 (heartbeat_at .
                  ,(format-time-string "%FT%TZ" (- now 540) t))))
         (ctx (gascity-runs-test--inspector-ctx
               (list step) "hw-step" :now now
               :sessions (vector (gascity-runs-test--worker-session
                                  "ec-fl8o" now 20))))
         (line (substring-no-properties
                (gascity-run--worker-line step nil ctx))))
    (should (equal line
                   (concat "worker   gc__requirements-planner-ec-fl8o"
                           "  ● requirements-planner-1"
                           "  session live · active 20s ago"
                           "  claim lease lapsed 4m ago · heartbeat 9m ago"
                           " (Pi heartbeat gap)")))
    (should-not (string-match-p "assignee/session gone" line))))

(ert-deftest gascity-test-run-inspector-live-session-stale-claim ()
  "A live session silent past the claim deadline reads stale, exactly as
the cockpit's Needs you rule reads the same pair (ga-o7vtw)."
  (let* ((now (float (floor (float-time))))
         (step `((id . "hw-step") (status . "in_progress")
                 (assignee . "gc__requirements-planner-ec-fl8o")
                 (lease_expires_at .
                  ,(format-time-string "%FT%TZ" (- now 240) t))
                 (heartbeat_at .
                  ,(format-time-string "%FT%TZ" (- now 540) t))))
         (ctx (gascity-runs-test--inspector-ctx
               (list step) "hw-step" :now now
               :sessions (vector (gascity-runs-test--worker-session
                                  "ec-fl8o" now 900))))
         (line (substring-no-properties
                (gascity-run--worker-line step nil ctx))))
    (should (string-match-p "session live · active 15m ago" line))
    (should (string-match-p "claim lease lapsed 4m ago" line))
    (should (string-match-p "(stale claim)" line))
    (should-not (string-match-p "Pi heartbeat gap" line))))

(ert-deftest gascity-test-run-inspector-dead-session-lapsed-lease ()
  "With no live session, a lapsed lease says the assignee is gone and
keeps the lease age, rather than implying a live-but-lapsed claim."
  (let* ((now (float (floor (float-time))))
         (step `((id . "hw-step") (status . "in_progress")
                 (assignee . "mockup-builder-1")
                 (lease_expires_at .
                  ,(format-time-string "%FT%TZ" (- now 300) t))
                 (heartbeat_at .
                  ,(format-time-string "%FT%TZ" (- now 540) t))))
         (ctx (gascity-runs-test--inspector-ctx
               (list step) "hw-step" :now now))
         (line (substring-no-properties
                (gascity-run--worker-line step nil ctx))))
    (should (equal line
                   (concat "worker   mockup-builder-1  ○ mockup-builder-1"
                           "  assignee/session gone"
                           "  claim lease lapsed 5m ago · heartbeat 9m ago")))
    (should-not (string-match-p "session live" line))))

(ert-deftest gascity-test-run-inspector-events-render-from-line-payload ()
  "An open drawer renders the newest matching events from the store's
line-mode (GOOD . BAD) payload, and leaves unrelated events out."
  (let ((gascity-runs-test--events
         `[((type . "bead.updated")
            (ts . ,(gascity-runs-test--ts 100))
            (payload . ((bead . ((id . "be-fy7m"))))))
           ((type . "bead.claimed")
            (ts . ,(gascity-runs-test--ts 200))
            (payload . ((bead . ((id . "be-bcb5"))))))
           ((type . "order.fired")
            (ts . ,(gascity-runs-test--ts 10))
            (payload . ((bead . ((id . "be-other"))))))]))
    (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
      (goto-char (point-min))
      (re-search-forward "^    ⬣ requirements")
      (gascity-thing-toggle)
      (should (string-match-p "│ events   bead.updated be-fy7m"
                              (buffer-string)))
      (should (string-match-p "│ events   bead.claimed be-bcb5"
                              (buffer-string)))
      (should-not (string-match-p "order\\.fired" (buffer-string))))))

(ert-deftest gascity-test-run-inspector-events-read-is-store-gated ()
  "The inspector reads events only while a drawer is open, with the
cockpit's exact argv (same window, line mode)."
  (let ((reads nil))
    (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
      (let ((orig (symbol-function 'gascity-reader-read-async)))
        (cl-letf (((symbol-function 'gascity-reader-read-async)
                   (lambda (args callback &optional errback &rest _)
                     (when (equal (car-safe args) "events")
                       (push (copy-sequence args) reads))
                     (funcall orig args callback errback))))
          (should-not reads)
          (goto-char (point-min))
          (re-search-forward "^    ⬣ requirements")
          (gascity-thing-toggle)
          (should reads)
          (should (seq-every-p (lambda (args)
                                 (equal args '("events" "--since" "2h")))
                               reads)))))))

(ert-deftest gascity-test-run-inspector-events-pending-is-silent ()
  "A cold pending events load emits no events line at all: the inspector
must not claim there are no recent events before it has read them."
  (let* ((beads (gascity-runs-test--active-beads))
         (step (seq-find (lambda (b) (equal (alist-get 'id b) "be-fy7m")) beads))
         (iteration (seq-find (lambda (b) (equal (alist-get 'id b) "be-bcb5"))
                              beads))
         (pending (gascity-runs-test--inspector-ctx
                   beads "be-52m5" :events '(:state pending)))
         (ready (gascity-runs-test--inspector-ctx
                 beads "be-52m5" :events '(:state ready :data nil))))
    (should (null (gascity-run--event-lines step iteration pending)))
    (should-not (string-match-p "no recent events"
                                (gascity-runs-test--text
                                 (gascity-run--step-drawer step iteration pending))))
    ;; A load that really has no matching event still says so.
    (should (equal (gascity-run--event-lines step iteration ready)
                   '("events   (no recent events)")))))

;;; Attempt history (run-view-v3 §A, REQ-001)

(defun gascity-runs-test--attempts-run (now)
  "Return the beads of a synthetic review step with three attempts.
Attempt 1 passed NOW-2h ago in a live run-operator-1 session, attempt 2
failed `hard: control_dispatch_error' NOW-1h ago in a live
implementer-1 session, and attempt 3 passed NOW-1m ago in a live
implementer-2 session.  A nested formula step under attempt 2 and an
unrelated step are not attempts.  NOW pins every timestamp."
  (let ((ts (lambda (ago) (format-time-string "%FT%TZ" (- now ago) t))))
    (list
     `((id . "hw-attempts") (status . "in_progress") (issue_type . "task")
       (created_at . ,(funcall ts 9000))
       (metadata . ((gc.kind . "workflow")
                    (gc.formula_name . "build-basic"))))
     `((id . "hw-review") (status . "in_progress")
       (updated_at . ,(funcall ts 30))
       (metadata . ((gc.root_bead_id . "hw-attempts")
                    (gc.step_ref . "build-basic.review")
                    (gc.kind . "ralph")
                    (gc.attempt . "3"))))
     `((id . "hw-a1") (status . "closed")
       (assignee . "gc__run-operator-ec-a1")
       ;; A healthy attempt's close reason must not read as a failure.
       (close_reason . "passed with notes")
       (closed_at . ,(funcall ts 7200))
       (metadata . ((gc.root_bead_id . "hw-attempts")
                    (gc.step_ref . "review.iteration.1")
                    (gc.logical_bead_id . "hw-review")
                    (gc.attempt . "1")
                    (gc.outcome . "pass"))))
     `((id . "hw-a2") (status . "closed")
       (assignee . "gc__implementer-1-ec-a2")
       (closed_at . ,(funcall ts 3600))
       (metadata . ((gc.root_bead_id . "hw-attempts")
                    (gc.step_ref . "review.iteration.2")
                    (gc.logical_bead_id . "hw-review")
                    (gc.attempt . "2")
                    (gc.outcome . "fail")
                    (gc.failure_class . "hard")
                    (gc.failure_reason . "control_dispatch_error"))))
     `((id . "hw-a3") (status . "closed")
       (assignee . "gc__implementer-2-ec-a3")
       (closed_at . ,(funcall ts 60))
       (metadata . ((gc.root_bead_id . "hw-attempts")
                    (gc.step_ref . "review.iteration.3")
                    (gc.logical_bead_id . "hw-review")
                    (gc.attempt . "3")
                    (gc.outcome . "pass"))))
     ;; A nested formula step below an iteration has two extra path
     ;; segments (`review.iteration.2.review.acceptance-review'), so it
     ;; must never be mistaken for an attempt.
     `((id . "hw-nested") (status . "closed")
       (closed_at . ,(funcall ts 3500))
       (metadata . ((gc.root_bead_id . "hw-attempts")
                    (gc.step_ref . "review.iteration.2.review.acceptance-review")
                    (gc.attempt . "1")
                    (gc.outcome . "pass"))))
     `((id . "hw-other") (status . "open")
       (metadata . ((gc.root_bead_id . "hw-attempts")
                    (gc.step_ref . "build-basic.prepare")))))))

(defun gascity-runs-test--attempt-sessions ()
  "Return the live `session list' rows, one per attempt worker."
  [((id . "ec-a1")
    (agent_name . "gascity.el/gc.run-operator-1")
    (state . "active")
    (session_name . "gc__run-operator-ec-a1"))
   ((id . "ec-a2")
    (agent_name . "gascity.el/gc.implementer-1")
    (state . "active")
    (session_name . "gc__implementer-1-ec-a2"))
   ((id . "ec-a3")
    (agent_name . "gascity.el/gc.implementer-2")
    (state . "active")
    (session_name . "gc__implementer-2-ec-a3"))])

(ert-deftest gascity-test-run-attempt-history ()
  "A step's drawer stacks one attempt row per iteration/attempt bead,
oldest first: number, outcome, live worker, relative time and
`class: reason' (`(none)' when healthy).  Nested formula steps below an
iteration are not attempts, and no row exceeds the dashboard width."
  (let* ((now (float (floor (float-time))))
         (beads (gascity-runs-test--attempts-run now))
         (step (seq-find (lambda (b) (equal (alist-get 'id b) "hw-review"))
                         beads))
         (ctx (gascity-runs-test--inspector-ctx
               beads "hw-attempts" :now now
               :sessions (gascity-runs-test--attempt-sessions)))
         (attempts (gascity-run--attempt-beads step ctx))
         (lines (gascity-run--attempt-lines step ctx))
         (rows (mapcar #'substring-no-properties (cdr lines))))
    (should (equal (mapcar (lambda (b) (alist-get 'id b)) attempts)
                   '("hw-a1" "hw-a2" "hw-a3")))
    (should (equal (substring-no-properties (car lines)) "attempts"))
    (should (equal rows
                   '("  1   pass      ● run-operator-1          2h (none)"
                     "  2   fail      ● implementer-1           1h hard: control_dispa…"
                     "  3   pass      ● implementer-2           1m (none)")))
    (should (seq-every-p (lambda (row) (<= (string-width row) 68)) rows))
    ;; Without a live-session payload the rows name the assignee's role
    ;; and carry no liveness glyph.
    (let ((cold (gascity-run--attempt-lines
                 step (gascity-runs-test--inspector-ctx
                       beads "hw-attempts" :now now))))
      (should-not (string-match-p "[●○]"
                                  (gascity-runs-test--text cold))))))

(ert-deftest gascity-test-run-attempt-history-drawer ()
  "The drawer places the attempt block after its attempt line and before
its worker, keeping the step line and collapsed row shape unchanged."
  (let* ((now (float (floor (float-time))))
         (beads (gascity-runs-test--attempts-run now))
         (step (seq-find (lambda (b) (equal (alist-get 'id b) "hw-review"))
                         beads))
         (ctx (gascity-runs-test--inspector-ctx
               beads "hw-attempts" :now now
               :sessions (gascity-runs-test--attempt-sessions)))
         (drawer (gascity-run--step-drawer step nil ctx))
         (text (gascity-runs-test--text drawer)))
    (should (equal (substring-no-properties (nth 0 drawer))
                   "step     build-basic.review  hw-review  in_progress"))
    ;; Step line, the step's own attempt line, then the stacked block.
    (should (equal (substring-no-properties (nth 1 drawer)) "attempt  3"))
    (should (equal
             (mapcar #'substring-no-properties (seq-take (seq-drop drawer 2) 4))
             '("attempts"
               "  1   pass      ● run-operator-1          2h (none)"
               "  2   fail      ● implementer-1           1h hard: control_dispa…"
               "  3   pass      ● implementer-2           1m (none)")))
    (should (string-prefix-p "worker   " (substring-no-properties
                                          (nth 6 drawer))))
    (should (string-prefix-p "failure  " (substring-no-properties
                                          (car (last drawer)))))
    (should (string-suffix-p "hard: control_dispatch_error" text))))

(ert-deftest gascity-test-run-attempt-history-nested ()
  "A nested loop's iteration is found by `gc.logical_bead_id' alone.
The be-52m5 fixture's review step (be-mqhp) and its iteration be-wki0
are unlinked once the iteration's `gc.step_ref' is absent, so only the
logical link can find it; the review steps beneath the iteration are
never attempts of the loop above them."
  (let* ((beads (mapcar (lambda (b)
                          (if (equal (alist-get 'id b) "be-wki0")
                              (let ((copy (copy-tree b)))
                                (setf (alist-get 'metadata copy)
                                      (assq-delete-all
                                       'gc.step_ref (alist-get 'metadata copy)))
                                copy)
                            b))
                        (gascity-runs-test--fixture-beads)))
         (step (seq-find (lambda (b) (equal (alist-get 'id b) "be-mqhp")) beads))
         (ctx (gascity-runs-test--inspector-ctx beads "be-52m5"))
         (attempts (gascity-run--attempt-beads step ctx)))
    (should (equal (mapcar (lambda (b) (alist-get 'id b)) attempts)
                   '("be-wki0")))
    (should (string-match-p "1   skipped"
                            (gascity-runs-test--text
                             (gascity-run--attempt-lines step ctx))))
    ;; The nested loop's own iteration is the loop's only attempt, not
    ;; every review step beneath it.
    (let* ((loop (seq-find (lambda (b) (equal (alist-get 'id b) "be-1bn")) beads))
           (loop-ctx (gascity-runs-test--inspector-ctx beads "be-bn2")))
      (should (equal (mapcar (lambda (b) (alist-get 'id b))
                             (gascity-run--attempt-beads loop loop-ctx))
                     '("be-5v6"))))))

(ert-deftest gascity-test-run-attempt-history-empty ()
  "A step with no iteration beads renders no attempt rows and no
`attempts' heading; the rest of the drawer is unchanged."
  (let* ((beads (gascity-runs-test--fixture-beads))
         (step (seq-find (lambda (b) (equal (alist-get 'id b) "be-5aht")) beads))
         (ctx (gascity-runs-test--inspector-ctx beads "be-52m5"))
         (drawer (gascity-run--step-drawer step nil ctx)))
    (should (null (gascity-run--attempt-beads step ctx)))
    (should (null (gascity-run--attempt-lines step ctx)))
    (should-not (string-match-p "attempts" (gascity-runs-test--text drawer)))
    (should (string-prefix-p "step     build-basic.prepare  be-5aht  closed"
                             (car drawer)))))

;;; Inspector actions (run-view-v2 §3)

(ert-deftest gascity-test-run-detail-copy-id ()
  "`w' copies the bead id at point: the step's on a step row and the
iteration's on the drawer's iteration line."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    (let (copied)
      (cl-letf (((symbol-function 'kill-new)
                 (lambda (s &optional _replace) (setq copied s))))
        (goto-char (point-min))
        (re-search-forward "^    ▾ review")
        (gascity-run-copy-id)
        (should (equal copied "be-fkq"))
        ;; The requirements row shows `iter 1'; its drawer names the
        ;; iteration bead, and w there copies that id.
        (goto-char (point-min))
        (re-search-forward "^    ◆ requirements")
        (gascity-thing-toggle)
        (goto-char (point-min))
        (re-search-forward "attempt  1 · iteration bead be-59r")
        (gascity-run-copy-id)
        (should (equal copied "be-59r"))))))

(ert-deftest gascity-test-run-detail-inspect-toggles-drawer ()
  "`I' opens the inspector for a leaf step and for a fold row (without
changing the fold), closes it again, and refuses a stage header."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    (goto-char (point-min))
    (re-search-forward "^    ◆ prepare")
    (gascity-run-inspect)
    (should (string-match-p "│ step     build-basic.prepare  be-e29"
                            (buffer-string)))
    (gascity-run-inspect)
    (should-not (string-match-p "│ step     build-basic.prepare"
                                (buffer-string)))
    ;; A fold row: I opens its inspector while its children keep their
    ;; own fold state.
    (goto-char (point-min))
    (re-search-forward "^    ▾ review")
    (gascity-run-inspect)
    (let ((text (buffer-string)))
      (should (string-match-p "│ step     build-basic.review  be-fkq" text))
      (should (string-match-p "^      ▾ build-basic-review-loop" text)))
    (gascity-run-inspect)
    (should-not (string-match-p "│ step     build-basic.review" (buffer-string)))
    ;; A stage header is not a step.
    (goto-char (point-min))
    (re-search-forward "^  ▾ ✕ Review")
    (should-error (gascity-run-inspect) :type 'user-error)))

(ert-deftest gascity-test-run-detail-diagnose-reveals-collapsed-stage ()
  "`!' expands the failed step's collapsed stage, moves point to its row
and echoes the ref, class and reason, truncated to the echo area."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    ;; Collapse Review: the failing row is not on screen.
    (goto-char (point-min))
    (re-search-forward "^  ▾ ✕ Review")
    (gascity-thing-toggle)
    (should (string-match-p "^  ▸ ✕ Review" (buffer-string)))
    (should-not (string-match-p "be-fkq" (buffer-string)))
    (let (shown)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (setq shown (apply #'format format-string args)))))
        (gascity-run-diagnose))
      (should (string-match-p "^  ▾ ✕ Review" (buffer-string)))
      (should (equal (get-text-property (point) 'gascity-bead) "be-fkq"))
      (should (string-match-p
               "✕ build-basic\\.review  hard: control_dispatch_error" shown)))))

(ert-deftest gascity-test-run-detail-diagnose-expands-folded-ancestors ()
  "`!' re-opens a folded loop above the failed bead before landing on it."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    ;; Fold the failing loop: its nested rows disappear.
    (goto-char (point-min))
    (re-search-forward "^      ▾ build-basic-review-loop")
    (gascity-thing-toggle)
    (should (string-match-p "^      ▸ build-basic-review-loop" (buffer-string)))
    ;; The collapsed fold row still names its own bead; its child row is
    ;; what disappears.
    (should-not (string-match-p "be-5v6" (buffer-string)))
    (cl-letf (((symbol-function 'gascity-runs-failed-step)
               (lambda (&rest _)
                 '(:name "review" :id "be-1bn"
                   :ref "build-basic.review.build-basic-review-loop"
                   :class "hard" :reason "control_dispatch_error"))))
      (gascity-run-diagnose))
    (should (string-match-p "^      ▾ build-basic-review-loop" (buffer-string)))
    (should (equal (get-text-property (point) 'gascity-bead) "be-1bn"))))

(ert-deftest gascity-test-run-detail-diagnose-falls-back-to-stage ()
  "When the failed row cannot be located `!' lands on the containing stage
header instead of failing silently."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    (cl-letf (((symbol-function 'gascity-runs-failed-step)
               (lambda (&rest _)
                 '(:name "review" :id "be-gone" :ref "build-basic.review"))))
      (gascity-run-diagnose))
    (should (equal (get-text-property (point) 'gascity-run-stage) "review"))))

(ert-deftest gascity-test-run-detail-diagnose-without-failure ()
  "A healthy run has no failed step to jump to."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-qrpg"
    (should-error (gascity-run-diagnose) :type 'user-error)))

(ert-deftest gascity-test-run-detail-drawer-targets-resolve ()
  "Drawer bead, artifact and worker lines carry the row's identity
properties, so RET/i/v/t resolve from the drawer without new commands."
  (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
    (let (opened visited detail)
      (cl-letf (((symbol-function 'gascity-beads--show-in-store)
                 (lambda (id _store) (setq opened id)))
                ((symbol-function 'gascity-beads--rig-store-cached)
                 (lambda (rig) (concat "/stores/" rig "/")))
                ((symbol-function 'find-file)
                 (lambda (file &rest _) (setq visited file)))
                ((symbol-function 'file-exists-p) (lambda (&rest _) t))
                ((symbol-function 'gascity-polecat-detail-at-point)
                 (lambda () (interactive)
                   (setq detail (gascity-agent-name (gascity-agent-at-point))))))
        (goto-char (point-min))
        (re-search-forward "^    ⬣ requirements")
        (gascity-thing-toggle)
        ;; The step line's bead is the step.
        (goto-char (point-min))
        (re-search-forward "│ step     build-basic.requirements  be-fy7m")
        (gascity-run-activate)
        (should (equal opened "be-fy7m"))
        ;; The attempt line names the iteration bead, and RET at the end
        ;; of that line still resolves it.
        (goto-char (point-min))
        (re-search-forward "iteration bead be-bcb5")
        (gascity-run-activate)
        (should (equal opened "be-bcb5"))
        ;; The artifact label visits its file.
        (goto-char (point-min))
        (re-search-forward "decomposition\\.md (missing)")
        (goto-char (match-beginning 0))
        (gascity-run-activate)
        (should (string-suffix-p "decomposition.md" visited))
        ;; The worker line reaches the live assignee.
        (goto-char (point-min))
        (re-search-forward "│ worker   gc__requirements-planner-ec-fl8o")
        (gascity-runs-agent-detail)
        (should (equal detail "beads.el/gc.requirements-planner-1"))
        ;; `v' peeks the session id gc accepts, not the qualified agent
        ;; name (a pool worker's agent name is not a session id).  `t'
        ;; already attaches by session name; both resolve the same id.
        (let (peeked)
          (cl-letf (((symbol-function 'gascity-session-peek--show)
                     (lambda (target _lines) (setq peeked target))))
            (goto-char (point-min))
            (re-search-forward "│ worker   gc__requirements-planner-ec-fl8o")
            (gascity-runs-agent-peek))
          (should (equal peeked "gc__requirements-planner-ec-fl8o")))
        (let (attached)
          (cl-letf (((symbol-function 'gascity-terminal-attach-tmux)
                     (lambda (session &rest _) (setq attached session))))
            (goto-char (point-min))
            (re-search-forward "│ worker   gc__requirements-planner-ec-fl8o")
            (gascity-runs-agent-tmux))
          (should (equal attached "gc__requirements-planner-ec-fl8o")))))))

;;; Web handoff (run-view-v3 §C, REQ-004)

(ert-deftest gascity-test-run-web-url ()
  "The run's web URL is the verified route under the configured base.
Trailing slashes are trimmed, both path segments are percent-encoded,
and no scope query is fabricated: the web app appends it only when the
scope resolves."
  (should (equal (gascity-run-web-url "be-52m5" "emacs-city"
                                      "http://127.0.0.1:8372")
                 "http://127.0.0.1:8372/city/emacs-city/runs/be-52m5"))
  ;; A trailing slash (or several) never doubles the separator.
  (should (equal (gascity-run-web-url "be-52m5" "emacs-city"
                                      "http://127.0.0.1:8372//")
                 "http://127.0.0.1:8372/city/emacs-city/runs/be-52m5"))
  ;; Both segments are URL-hexified, so a space or slash cannot escape
  ;; its path segment.
  (should (equal (gascity-run-web-url "be 52/5" "emacs city"
                                      "http://127.0.0.1:8372")
                 "http://127.0.0.1:8372/city/emacs%20city/runs/be%2052%2F5"))
  ;; The base defaults to the defcustom.
  (let ((gascity-dashboard-url "http://127.0.0.1:8372"))
    (let ((url (gascity-run-web-url "be-52m5" "emacs-city")))
      (should (equal url
                     "http://127.0.0.1:8372/city/emacs-city/runs/be-52m5"))
      (should-not (string-match-p "\\?" url)))))

(ert-deftest gascity-test-run-web-url-browse-and-copy ()
  "`B' opens the run in the browser and `Y' copies the same URL."
  (let ((gascity-dashboard-url "http://127.0.0.1:8372")
        (browsed nil) (copied nil) (shown nil))
    (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
      (setq gascity-run--city "emacs-city")
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (url &rest _) (setq browsed url)))
                ((symbol-function 'kill-new)
                 (lambda (string &optional _replace) (setq copied string)))
                ((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (setq shown (apply #'format format-string args)))))
        (gascity-run-browse-url)
        (should (equal browsed
                       "http://127.0.0.1:8372/city/emacs-city/runs/be-bn2"))
        (should (equal shown browsed))
        (setq browsed nil)
        (gascity-run-copy-url)
        (should-not browsed)
        (should (equal copied
                       "http://127.0.0.1:8372/city/emacs-city/runs/be-bn2"))
        (should (equal shown (concat "Copied " copied)))))))

(ert-deftest gascity-test-run-web-url-absent ()
  "With no configured dashboard the builder is nil and `B'/`Y' only say
how to configure it: nothing is browsed and nothing is copied."
  (let ((gascity-dashboard-url nil))
    (should-not (gascity-run-web-url "be-52m5" "emacs-city"))
    (should-not (gascity-run-web-url "be-52m5" "emacs-city" ""))
    (should-not (gascity-run-web-url "be-52m5" "emacs-city" "//"))
    (should-not (gascity-run-web-url nil "emacs-city" "http://127.0.0.1:8372"))
    (should-not (gascity-run-web-url "be-52m5" "" "http://127.0.0.1:8372")))
  (let ((browsed nil) (copied nil) (messages nil))
    (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
      (setq gascity-run--city "emacs-city")
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (&rest _) (setq browsed t)))
                ((symbol-function 'kill-new)
                 (lambda (&rest _) (setq copied t)))
                ((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (push (apply #'format format-string args) messages))))
        (gascity-run-browse-url)
        (gascity-run-copy-url)
        (should-not browsed)
        (should-not copied)
        (should (equal messages
                       '("No dashboard URL configured; set gascity-dashboard-url"
                         "No dashboard URL configured; set gascity-dashboard-url")))))))

;;; Render guard (§8.3 R2, §8.4)

(ert-deftest gascity-test-runs-render-remote-is-io-free ()
  "Rendering Runs (with history and drawers) and the run detail on a
remote city touches no file: every read is served, the render is pure."
  (gascity-test-ensure-mock-method)
  (let ((gascity-store-synchronous-delivery t)
        (tramp-verbose 0)
        (default-directory "/mock::/home/roman/emacs-city/"))
    (setf (gascity-store--host-primed
           (gascity-store--host (file-remote-p default-directory)))
          t)
    (gascity-test-with-render-guard
      (gascity-runs-test--with-view (gascity-runs-test--active-beads)
          (progn (with-current-buffer buf (gascity-runs-mode))
                 (vui-component 'gascity-runs-app :initial-filters nil))
        (should (string-match-p "^  ⬣ be-52m5" (buffer-string)))
        (gascity-runs-history)
        (goto-char (point-min))
        (re-search-forward "^  ⬣ be-52m5")
        (gascity-thing-toggle)
        (should (string-match-p "│ ◆ prepare" (buffer-string))))
      (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
        (should (string-match-p "^Steps  9/10 · 45 beads" (buffer-string)))
        (gascity-run-toggle-control)
        (goto-char (point-min))
        (re-search-forward "^    ◆ prepare")
        (gascity-thing-toggle))
      (should (null gascity-test-render-guard-violations)))))

(provide 'gascity-runs-test)
;;; gascity-runs-test.el ends here
