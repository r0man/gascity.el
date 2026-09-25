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
    (should-not (string-match-p "^Done" text))))

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

(ert-deftest gascity-test-runs-history-paging ()
  "`H' shows closed runs newest first, 20 per page; `+' adds a page."
  (let* ((beads (gascity-runs-test--many-closed 45))
         (render (lambda (view)
                   (gascity-runs-test--text
                    (gascity-runs-lines (gascity-runs-test--ctx beads :view view)))))
         (rows (lambda (text) (cl-count-if (lambda (l) (string-match-p "^  ◆ ga-h" l))
                                           (split-string text "\n")))))
    (should-not (string-match-p "^Done" (funcall render nil)))
    (let ((text (funcall render '(:history t :pages 1))))
      (should (string-match-p "^Done  45$" text))
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
      (should (string-match-p "^Done  45$" text))
      (should-not (string-match-p "^Active\\|^Failed" text))
      (should (string-match-p "filter  state done" text)))))

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
                  ("b" . gascity-runs-root-bead) ("H" . gascity-runs-history)
                  ("+" . gascity-runs-more) ("/" . gascity-runs-filter)
                  ("i" . gascity-runs-agent-detail) ("v" . gascity-runs-agent-peek)
                  ("t" . gascity-runs-agent-tmux) ("TAB" . gascity-thing-forward)
                  ("SPC" . gascity-thing-toggle) ("q" . quit-window)
                  ("j" . gascity-jump-prefix) ("?" . gascity-dispatch)))
    (should (eq (keymap-lookup gascity-runs-mode-map (car pair)) (cdr pair))))
  (dolist (pair '(("g" . gascity-run-refresh) ("RET" . gascity-run-activate)
                  ("b" . gascity-run-root-bead) ("C" . gascity-run-toggle-control)
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
    ;; `H' adds the history; SPC on a header folds it.
    (gascity-runs-history)
    (should (string-match-p "^Done  2$" (buffer-string)))
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
  (gascity-runs-test--with-detail (gascity-runs-test--active-beads) "be-52m5"
    (let ((text (buffer-string)))
      (should (string-match-p "^⬣ be-52m5  build-basic +beads.el · started 2h$" text))
      (should (string-match-p "^  formula  build-basic (graph.v2)   source ~/.gc/cache/…/build-basic.formula.toml$"
                              (replace-regexp-in-string
                               "/home/[^/]+/" "~/" text)))
      (should (string-match-p "^  plans    decomposition.md · factory-run.md" text))
      (should (string-match-p "^  convoy   be-93dg  closed 7/7  input$" text))
      (should (string-match-p "^Steps  1/10 +C show control nodes$" text))
      (should (string-match-p "^  ◆ prepare +be-5aht +pass +run-operator" text))
      (should (string-match-p
               "^  ⬣ requirements +be-fy7m +iter 1 +● requirements-planner-1 +3m$" text))
      ;; Quiet loops start folded.
      (should (string-match-p "^  ▸ review +be-mqhp +· loop" text))
      (should-not (string-match-p "setup-build-basic-review" text)))
    ;; SPC on a fold row expands it in place; state survives a refresh.
    (goto-char (point-min))
    (re-search-forward "^  ▸ review")
    (gascity-thing-toggle)
    (should (string-match-p "^  ▾ review" (buffer-string)))
    (should (string-match-p "^    · setup-build-basic-review" (buffer-string)))
    (gascity-run-refresh)
    (should (string-match-p "^  ▾ review" (buffer-string)))
    ;; SPC on a step row opens its drawer.
    (goto-char (point-min))
    (re-search-forward "^  ⬣ requirements")
    (gascity-thing-toggle)
    (should (string-match-p "│ ref      requirements.iteration.1" (buffer-string)))
    (should (string-match-p "│ iteration be-bcb5 (attempt 1) of step be-fy7m"
                            (buffer-string)))
    ;; C shows the control nodes.
    (gascity-run-toggle-control)
    (should (string-match-p "C hide control nodes" (buffer-string)))
    (should (string-match-p "workflow-finalize" (buffer-string)))))

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
                ((symbol-function 'gascity-polecat-detail-at-point)
                 (lambda () (interactive)
                   (setq detail (gascity-agent-name (gascity-agent-at-point))))))
        (goto-char (point-min))
        (re-search-forward "^  ◆ prepare")
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
        (re-search-forward "^  ⬣ requirements")
        (gascity-runs-agent-detail)
        (should (equal detail "beads.el/gc.requirements-planner-1"))
        (goto-char (point-min))
        (re-search-forward "^  ◆ prepare")
        (should-error (gascity-runs-agent-detail) :type 'user-error)))))

(ert-deftest gascity-test-run-detail-failed-run-opens-failure ()
  "A failed run's loop containing the failure starts expanded down to it."
  (gascity-runs-test--with-detail (gascity-runs-test--fixture-beads) "be-bn2"
    (let ((text (buffer-string)))
      (should (string-match-p "^✕ be-bn2  build-basic  fail" text))
      (should (string-match-p "^Steps  9/10" text))
      (should (string-match-p "^  ▾ review +be-fkq +✕ loop" text))
      (should (string-match-p "^    ▾ build-basic-review-loop +be-1bn +✕ loop" text)))))

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
      (should (string-match-p "^  ◆ requirements +be-yam +iter 1" text))
      (should (string-match-p "^  ▾ review +be-fkq +✕ loop" text))
      (should (string-match-p "^    ▾ build-basic-review-loop +be-1bn +✕ loop" text))
      (should-not (string-match-p "be-59r" text)))
    ;; The iteration id is in the drawer.
    (goto-char (point-min))
    (re-search-forward "^  ◆ requirements")
    (gascity-thing-toggle)
    (should (string-match-p "│ iteration be-59r (attempt 1) of step be-yam"
                            (buffer-string)))))

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
        (should (string-match-p "^Steps  9/10" (buffer-string)))
        (gascity-run-toggle-control)
        (goto-char (point-min))
        (re-search-forward "^  ◆ prepare")
        (gascity-thing-toggle))
      (should (null gascity-test-render-guard-violations)))))

(provide 'gascity-runs-test)
;;; gascity-runs-test.el ends here
