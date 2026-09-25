;;; gascity-agents-test.el --- ERT tests for the Agents view and detail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 P4: the Agents table and tree (§7.3) and the agent
;; detail (§7.4), on the real gc shapes in fixtures/v3.  The gc
;; boundary is stubbed; nothing here runs gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)
(require 'gascity-cockpit-test)

(defun gascity-agents-test--read (args callback &optional _errback &rest _)
  "Canned `gascity-reader-read-async' for emacs-city: ARGS CALLBACK."
  (funcall callback
           (pcase args
             (`("agent" "list") (gascity-cockpit-test--json "emacs-city.agent-list.json"))
             (`("bd" "list" "--status" . ,_) [])
             (`("rig" "list") (gascity-cockpit-test--json "emacs-city.rig-list.json"))
             (_ (let (out)
                  (gascity-cockpit-test--scenario-read args (lambda (d) (setq out d)))
                  out))))
  nil)

(defun gascity-agents-test--data (&rest overrides)
  "Return an Agents payload plist from the fixtures, with OVERRIDES."
  (append overrides
          (list :status (gascity-cockpit-test--json "emacs-city.status.json")
                :sessions (gascity-cockpit-test--json "emacs-city.session-list.json")
                :agents (gascity-cockpit-test--json "emacs-city.agent-list.json")
                :work nil)))

;;; Model

(ert-deftest gascity-test-agents-rows-merge-and-order ()
  "Rows merge status agents with named sessions; stalled pin first;
stopped agents take their template's provider from `gc agent list'."
  (let* ((status (gascity-cockpit-test--json "emacs-city.status.json"))
         (_ (setf (alist-get 'running (aref (alist-get 'agents status) 0)) t))
         (rows (gascity-agents--rows (gascity-agents-test--data :status status)
                                     (float-time))))
    (should (member "mayor" (mapcar (lambda (a) (plist-get a :name)) rows)))
    (should (eq (plist-get (car rows) :state) 'stalled))
    (should (equal (plist-get (car rows) :name) "bd.dog-1"))
    (let ((dog2 (seq-find (lambda (a) (equal (plist-get a :name) "bd.dog-2")) rows)))
      (should (eq (plist-get dog2 :state) 'stopped)))
    ;; A numbered member takes its template's configured provider.
    (let ((providers (make-hash-table :test 'equal)))
      (puthash "bd.dog" "pi" providers)
      (should (equal (gascity-agents--provider '(:name "bd.dog-2") providers) "pi"))
      (should (equal (gascity-agents--provider '(:name "x" :provider "claude") providers)
                     "claude")))))

(ert-deftest gascity-test-agents-filter-match ()
  "State `running' keeps live agents and always the stalled ones."
  (let ((running '(:name "a" :state running :provider "pi"))
        (idle '(:name "b/x" :rig "b" :state idle))
        (stopped '(:name "c" :state stopped))
        (stalled '(:name "d" :state stalled)))
    (should (gascity-agents--match-p running '(:state "running")))
    (should (gascity-agents--match-p idle '(:state "running")))
    (should-not (gascity-agents--match-p stopped '(:state "running")))
    (should (gascity-agents--match-p stalled '(:state "stopped")))
    (should (gascity-agents--match-p stopped nil))
    (should (gascity-agents--match-p idle '(:rig "b")))
    (should (gascity-agents--match-p stopped '(:rig "city")))
    (should-not (gascity-agents--match-p idle '(:rig "city")))
    (should (gascity-agents--match-p running '(:provider "pi")))
    (should (gascity-agents--match-p idle '(:search "B/X")))
    (should-not (gascity-agents--match-p idle '(:search "zzz")))))

(ert-deftest gascity-test-agents-entry ()
  "An entry's id is the action agent; stalled rows carry ■."
  (let* ((agent (list :name "beads.el/gc.w-1" :rig "beads.el" :state 'stalled
                      :object (make-instance 'gascity-agent :name "beads.el/gc.w-1")))
         (entry (gascity-agents--entry agent (float-time))))
    (should (gascity-agent-p (car entry)))
    (should (equal (substring-no-properties (aref (cadr entry) 0)) "■"))
    (should (equal (substring-no-properties (aref (cadr entry) 1)) "gc.w-1"))
    (should (equal (aref (cadr entry) 3) "stalled"))))

;;; Table

(defmacro gascity-agents-test--with-table (&rest body)
  "Open the Agents table on canned reads and run BODY in it."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'gascity-reader-read-async) #'gascity-agents-test--read)
             ((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
             ((symbol-function 'gascity-view-get-buffer-create)
              (lambda (&rest _) (get-buffer-create "*gascity-agents-test*")))
             ((symbol-function 'pop-to-buffer) #'ignore))
     (unwind-protect
         (progn (gascity-agents)
                (with-current-buffer "*gascity-agents-test*" ,@body))
       (kill-buffer "*gascity-agents-test*"))))

(ert-deftest gascity-test-agents-table-default-running ()
  "The table opens filtered to running agents; `x' shows every state."
  (gascity-agents-test--with-table
    (should (derived-mode-p 'gascity-agents-mode))
    (should (string-match-p "mayor" (buffer-string)))
    (should-not (string-match-p "bd\\.dog-2" (buffer-string)))
    (should (string-match-p "Agents  .*stopped" (format "%s" mode-name)))
    (funcall gascity-filter-reset-function)
    (should (string-match-p "bd\\.dog-2" (buffer-string)))
    (gascity-filter-set :state "stopped")
    (should-not (string-match-p "mayor" (buffer-string)))))

(ert-deftest gascity-test-agents-table-keeps-rows-on-failed-read ()
  "A failed refresh keeps the last rows and marks the mode line ◐."
  (gascity-agents-test--with-table
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (lambda (args cb &optional eb &rest _)
                 (if (equal args '("session" "list"))
                     (funcall eb "boom")
                   (gascity-agents-test--read args cb)))))
      (gascity-agents-refresh))
    (should (string-match-p "mayor" (buffer-string)))
    (should (string-match-p "◐" (format "%s" mode-name)))))

(ert-deftest gascity-test-agents-keys ()
  "§5.3 agent keys and `T' in the table and tree."
  (dolist (map (list gascity-agents-mode-map gascity-agents-tree-mode-map))
    (should (eq (keymap-lookup map "RET") #'gascity-tmux-at-point))
    (should (eq (keymap-lookup map "i") #'gascity-polecat-detail-at-point))
    (should (eq (keymap-lookup map "M") #'gascity-session-nudge-at-point))
    (should (eq (keymap-lookup map "S") 'gascity-sling-dispatch))
    (should (keymap-lookup map "T")))
  (should (eq (keymap-lookup gascity-agents-mode-map "/") #'gascity-agents-filter))
  (dolist (key '("-s" "-r" "-p" "-q" "-S" "x"))
    (should (transient-get-suffix 'gascity-agents-filter key)))
  (should (eq (keymap-lookup gascity-dashboard-mode-map "j a") 'gascity-jump-agents)))

;;; Tree

(ert-deftest gascity-test-agents-tree-folds ()
  "The tree groups pools, puts the mayor in the city, and SPC folds a rig."
  (let ((vui-render-delay nil)
        (buf (get-buffer-create "*gascity-agents-tree-test*")))
    (cl-letf (((symbol-function 'gascity-reader-read-async) #'gascity-agents-test--read))
      (unwind-protect
          (save-window-excursion
            (with-current-buffer buf (gascity-agents-tree-mode))
            (vui-mount (vui-component 'gascity-agents-tree-app) (buffer-name buf))
            (with-current-buffer buf
              (should (string-match-p "▾ bd.dog  scaled 0–2" (buffer-string)))
              ;; Idle is ○ in the tree as in the table (§6.1, QA A3).
              (should (string-match-p "^  ○ mayor +idle" (buffer-string)))
              (goto-char (point-min))
              (re-search-forward "▾ beads.el")
              (beginning-of-line)
              (gascity-thing-toggle)
              (should (string-match-p "▸ beads.el" (buffer-string)))
              (gascity-agents-tree-refresh)
              (should (string-match-p "▸ beads.el" (buffer-string)))))
        (kill-buffer buf)))))

;;; Agent detail (§7.4)

(ert-deftest gascity-test-agent-detail-transcript-summary ()
  "Transcript rows summarize text, tool calls and results."
  (let ((entries (append (alist-get 'entries (gascity-cockpit-test--json
                                              "bright-lights.session-logs-mayor-tail10.json"))
                         nil)))
    (should (equal (car (gascity-session--entry-summary (nth 0 entries))) "user"))
    (should (string-prefix-p "[bright-lights] mayor"
                             (cdr (gascity-session--entry-summary (nth 0 entries)))))
    (should (string-prefix-p "bash: gc mail inbox"
                             (cdr (gascity-session--entry-summary (nth 1 entries)))))
    (should (equal (gascity-session--entry-summary (nth 2 entries))
                   '("tool" . "result")))
    (should (string-prefix-p "Morning check"
                             (cdr (gascity-session--entry-summary (nth 3 entries)))))))

(ert-deftest gascity-test-agent-detail-operator-mail ()
  "Mail with operator keeps messages from or to the agent, newest first."
  (let* ((inbox '((messages . [((from . "mayor/") (subject . "a")
                                (created_at . "2026-09-25T10:00:00Z"))
                               ((from . "human") (to . "beads.el/gc.w-1")
                                (subject . "b") (created_at . "2026-09-25T11:00:00Z"))
                               ((from . "other") (subject . "c"))])))
         (mayor (gascity-session--operator-mail
                 inbox (make-instance 'gascity-agent :name "mayor")))
         (worker (gascity-session--operator-mail
                  inbox (make-instance 'gascity-agent :name "beads.el/gc.w-1"))))
    (should (equal (mapcar (lambda (m) (alist-get 'subject m)) mayor) '("a")))
    (should (equal (mapcar (lambda (m) (alist-get 'subject m)) worker) '("b")))))

(ert-deftest gascity-test-agent-detail-graph-formula ()
  "The run formula comes from the graph's step refs."
  (let ((graph (seq-filter (lambda (b) (equal (gascity-dashboard--root-of b) "be-52m5"))
                           (append (gascity-cockpit-test--json
                                    "emacs-city.bd-list-all-beads.el-runs.json")
                                   nil))))
    (should (equal (gascity-session--graph-formula graph) "build-basic"))
    (should (equal (gascity-session--graph-formula
                    '(((metadata . ((gc.step_ref . "do-work.prepare"))))))
                   "do-work"))))

(ert-deftest gascity-test-agent-detail-renders ()
  "The mounted detail shows header, Work, Run, Transcript and Mail."
  (let* ((vui-render-delay nil)
         (graph (seq-filter (lambda (b) (equal (gascity-dashboard--root-of b) "be-52m5"))
                            (append (gascity-cockpit-test--json
                                     "emacs-city.bd-list-all-beads.el-runs.json")
                                    nil)))
         (hook `[((id . "be-bcb5") (status . "in_progress") (title . "Generate requirements")
                  (assignee . "gc__requirements-planner-ec-fl8o")
                  (metadata . ((gc.root_bead_id . "be-52m5"))))])
         (agent (make-instance 'gascity-agent :name "beads.el/gc.requirements-planner-1"
                               :rig "beads.el"
                               :session-name "gc__requirements-planner-ec-fl8o"
                               :socket "emacs-city"))
         (buf (get-buffer-create "*gascity-agent-test*")))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (lambda (args cb &optional _eb &rest _)
                 (funcall cb
                          (pcase args
                            (`("session" "list")
                             `((sessions . [((id . "ec-fl8o")
                                             (agent_name . "beads.el/gc.requirements-planner-1")
                                             (state . "active") (provider . "pi")
                                             (template . "beads.el/gc.requirements-planner")
                                             (session_name . "gc__requirements-planner-ec-fl8o")
                                             (work_dir . "/home/roman/workspace/beads.el")
                                             (last_active . ,(gascity-cockpit-test--ts 180)))])))
                            (`("bd" "list" "--assignee" "gc__requirements-planner-ec-fl8o" . ,_)
                             hook)
                            (`("bd" "list" "--all" . ,_) (vconcat graph))
                            (`("bd" . ,_) [])
                            (`("session" "logs" "ec-fl8o" "--tail" "10")
                             (gascity-cockpit-test--json
                              "bright-lights.session-logs-mayor-tail10.json"))
                            (`("mail" "inbox")
                             '((messages . [((from . "beads.el/gc.requirements-planner-1")
                                             (subject . "context cycle")
                                             (created_at . "2026-09-25T12:26:00Z"))])))
                            (_ (error "Unexpected read %S" args))))
                 nil)))
      (unwind-protect
          (save-window-excursion
            (with-current-buffer buf
              (gascity-session-detail-mode)
              (setq-local gascity-section--agent agent))
            (vui-mount (vui-component 'gascity-session-detail-app :agent agent)
                       (buffer-name buf))
            (with-current-buffer buf
              (let ((text (buffer-string)))
                (should (string-match-p "^● beads.el/gc.requirements-planner-1 .*active · last active 3m"
                                        text))
                (should (string-match-p "session  ec-fl8o  gc__requirements-planner-ec-fl8o"
                                        text))
                (should (string-match-p "provider pi" text))
                (should (string-match-p "workdir  ~/workspace/beads.el\\|workdir  /home" text))
                (should (string-match-p "^Work  1" text))
                (should (string-match-p "⬣ be-bcb5 .*run be-52m5" text))
                (should (string-match-p "⬣ be-52m5 +build-basic +[◆⬣·✕]\\{10\\}" text))
                (should (string-match-p "^Transcript .*f follow  v peek" text))
                (should (string-match-p "bash: gc mail inbox" text))
                (should (string-match-p "^Mail with operator  1" text))
                (should (string-match-p "context cycle" text)))
              ;; RET on the run row opens run detail, scoped to the rig.
              (goto-char (point-min))
              (re-search-forward "⬣ be-52m5")
              (let (shown)
                (cl-letf (((symbol-function 'gascity-run-show)
                           (lambda (id _c rig) (setq shown (list id rig)))))
                  (gascity-session-detail-activate))
                (should (equal shown '("be-52m5" "beads.el"))))))
        (kill-buffer buf)))))

(ert-deftest gascity-test-agent-detail-log-argv ()
  "`f' follows locally with gc; remotely through a no-pty ssh whose command
runs gc under the host watcher and keeps stdin open, so killing the
local follower stops gc on the host (no leaked `session logs -f')."
  (cl-letf (((symbol-function 'gascity-reader--city-args)
             (lambda () '("--city" "/home/u/city")))
            ((symbol-function 'gascity-reader--city-env-overrides) #'ignore))
    (should (equal (gascity-session--log-argv "ec-fl8o" "/tmp/")
                   (list gascity-executable "--city" "/home/u/city"
                         "session" "logs" "ec-fl8o" "-f")))
    (cl-letf (((symbol-function 'gascity-reader--ssh-pipe-p) (lambda (&rest _) t)))
      (let* ((argv (gascity-session--log-argv "ec-fl8o" "/ssh:h:/home/u/city/"))
             (command (car (last argv))))
        (should (equal (car argv) "ssh"))
        (should-not (member "-n" argv))
        (should (string-search (shell-quote-argument gascity-remote-exit-reporter)
                               command))
        (should (string-search "session logs ec-fl8o -f" command))
        (should (string-search "/bin/sh -c" command))))))

(ert-deftest gascity-test-remote-exit-reporter-shared ()
  "The live stream and the log follower share one host watcher."
  (should (eq gascity-live--exit-reporter gascity-remote-exit-reporter))
  ;; The watcher really kills its child at stdin EOF (run locally).
  (let* ((script gascity-remote-exit-reporter)
         (proc (make-process :name "watch-test" :connection-type 'pipe
                             :command (list "/bin/sh" "-c" script "sleep" "30")
                             :noquery t)))
    (unwind-protect
        (progn
          (process-send-eof proc)
          (let ((i 0))
            (while (and (process-live-p proc) (< i 50))
              (accept-process-output proc 0.1)
              (setq i (1+ i))))
          (should-not (process-live-p proc)))
      (when (process-live-p proc) (delete-process proc)))))

(ert-deftest gascity-test-agent-detail-follow-log-buffer ()
  "`f' opens `*gascity-log: TARGET*' fed by a local pipe process; `q' kills it."
  (let (spawned)
    (cl-letf (((symbol-function 'gascity-view-get-buffer-create)
               (lambda (name &rest _) (get-buffer-create name)))
              ((symbol-function 'gascity-session--log-argv)
               (lambda (&rest _) '("cat")))
              ((symbol-function 'make-process)
               (lambda (&rest plist) (setq spawned plist) nil))
              ((symbol-function 'pop-to-buffer) #'ignore))
      (with-temp-buffer
        (setq-local gascity-section--agent
                    (make-instance 'gascity-agent :name "mayor" :session-name "mayor"))
        (gascity-session-follow-log))
      (should (eq (plist-get spawned :connection-type) 'pipe))
      (should (equal (plist-get spawned :command) '("cat")))
      (with-current-buffer "*gascity-log: mayor*"
        (should (derived-mode-p 'gascity-log-mode))
        (should (eq (keymap-lookup gascity-log-mode-map "q") #'kill-current-buffer)))
      (kill-buffer "*gascity-log: mayor*"))))

(ert-deftest gascity-test-agent-detail-follow-log-stderr-goes-with-it ()
  "The follower's hidden stderr buffer is killed when the follower ends;
its last line lands in the end note (QA #11)."
  (cl-letf (((symbol-function 'gascity-view-get-buffer-create)
             (lambda (name &rest _) (get-buffer-create name)))
            ((symbol-function 'gascity-session--log-argv)
             (lambda (&rest _) '("sh" "-c" "echo out; echo 'no such session' >&2")))
            ((symbol-function 'pop-to-buffer) #'ignore))
    (with-temp-buffer
      (setq default-directory temporary-file-directory)
      (setq-local gascity-section--agent
                  (make-instance 'gascity-agent :name "mayor" :session-name "mayor"))
      (gascity-session-follow-log))
    (let ((deadline (+ (float-time) 5)))
      (while (and (get-buffer " *gascity-log-stderr: mayor*")
                  (< (float-time) deadline))
        (accept-process-output nil 0.05)))
    (should-not (get-buffer " *gascity-log-stderr: mayor*"))
    (with-current-buffer "*gascity-log: mayor*"
      (should (string-search "no such session" (buffer-string))))
    (kill-buffer "*gascity-log: mayor*")))

(ert-deftest gascity-test-agent-peek-opens-at-once ()
  "`v' shows `…' before gc answers, then the captured pane (§8.5)."
  (let (on-success)
    (cl-letf (((symbol-function 'gascity-view-get-buffer-create)
               (lambda (name &rest _) (get-buffer-create name)))
              ((symbol-function 'pop-to-buffer) #'ignore)
              ((symbol-function 'gascity-command-act-async)
               (lambda (_cmd &rest keys) (setq on-success (plist-get keys :on-success)))))
      (gascity-session-peek--show "mayor" 20)
      (with-current-buffer (gascity-session-peek--buffer-name "mayor")
        (should (string-match-p "…" (buffer-string)))
        (funcall on-success "pane text")
        (should (string-match-p "pane text" (buffer-string))))
      (kill-buffer (gascity-session-peek--buffer-name "mayor")))))

(ert-deftest gascity-test-agent-detail-keys ()
  "The detail binds `f' follow, `v' peek and the §5.3 agent keys."
  (let ((map gascity-session-detail-mode-map))
    (should (eq (keymap-lookup map "f") #'gascity-session-follow-log))
    (should (eq (keymap-lookup map "v") #'gascity-session-peek-at-point))
    (dolist (key '("M" "s" "K" "w" "D" "R" "U" "t" "d"))
      (should (keymap-lookup map key)))
    (should (eq (keymap-lookup map "S") #'gascity-sling-dispatch))))

(ert-deftest gascity-test-agents-sort-keeps-stalled-pinned ()
  "A header-click sort, either direction, keeps stalled rows first."
  (gascity-test-with-temp-view
    (cl-letf (((symbol-function 'gascity-agents-refresh) #'ignore))
      (gascity-agents-mode))
    (let* ((mk (lambda (name state)
                 (list name (vector "" name "—" state "—" "" ""))))
           (entries (list (funcall mk "b" "active") (funcall mk "z" "stalled")
                          (funcall mk "a" "stopped") (funcall mk "c" "stalled"))))
      (dolist (dir '(nil t))
        (setq tabulated-list-sort-key (cons "Agent" dir))
        (let* ((sorted (sort (copy-sequence entries) (tabulated-list--get-sorter)))
               (names (mapcar #'car sorted)))
          (should (equal (seq-take names 2) (if dir '("z" "c") '("c" "z"))))
          (should (equal (seq-drop names 2) (if dir '("b" "a") '("a" "b")))))))))

(ert-deftest gascity-test-agents-tree-row-state-and-age ()
  "Tree rows show the state and the relative last activity (§7.3)."
  (let* ((session (gascity-domain-decode
                   'gascity-session
                   `((agent_name . "mayor") (name . "mayor") (state . "active")
                     (last_active . ,(gascity-cockpit-test--ts 480)))))
         (map (gascity-status--session-map-rows (list session)))
         (live (gascity-test--vnode-text-plain
                (gascity-status--agent-row '((qualified_name . "mayor") (name . "mayor")
                                             (running . t))
                                           nil map nil)))
         (stopped (gascity-test--vnode-text-plain
                   (gascity-status--agent-row '((qualified_name . "bd.dog-1")
                                                (name . "bd.dog-1"))
                                              nil map nil 4))))
    (should (string-match-p "^  ● mayor +active +8m$" live))
    (should (string-match-p "^    ○ bd.dog-1 +stopped *$" stopped))))

(defun gascity-test--vnode-text-plain (vnode)
  "Return the plain content of text VNODE."
  (substring-no-properties (vui-vnode-text-content vnode)))

(ert-deftest gascity-test-agent-detail-no-bookkeeping-beads ()
  "The detail lists no session/convoy/wisp beads, and a shared city-root
work_dir attributes nothing by path (QA acceptance #2: the mayor showed
other agents' session beads)."
  (let ((mayor-dir "/home/roman/bright-lights")
        (session '((id . "bl-5a5i") (issue_type . "session") (status . "open")
                   (metadata . ((work_dir . "/home/roman/bright-lights")))))
        (dog '((id . "bl-mwo2") (issue_type . "session") (status . "closed")
               (metadata . ((work_dir . "/home/roman/bright-lights/.gc/agents/bd.dog-1")))))
        (work '((id . "bl-w1") (issue_type . "task") (status . "open")
                (metadata . ((work_dir . "/home/roman/bright-lights"))))))
    (should-not (gascity-session--agent-bead-p session))
    (should-not (gascity-session--agent-bead-p dog))
    (should (gascity-session--agent-bead-p work))
    ;; The city root is shared: no path attribution at all.
    (should-not (gascity-session--worked-here-p work mayor-dir t))
    (should-not (gascity-session--worked-here-p dog mayor-dir t))
    ;; A polecat's own worktree still attributes by path.
    (should (gascity-session--worked-here-p
             '((metadata . ((work_dir . "/w/agent/worktrees/x")))) "/w/agent"))))

(ert-deftest gascity-test-agents-detail-window-lines ()
  "SPC on an Agents row shows the §5.4 detail: session id and tmux name,
workdir, hooked bead, created — not the row's columns again (QA #9)."
  (gascity-agents-test--with-table
    (goto-char (point-min))
    (while (and (not (eobp))
                (not (equal (gascity-agent-name (tabulated-list-get-id)) "mayor")))
      (forward-line 1))
    (let ((lines (funcall gascity-tabulated-detail-function
                          (tabulated-list-get-id) (tabulated-list-get-entry))))
      (should (string-prefix-p "mayor" (car lines)))
      (should (seq-find (lambda (l) (string-match-p "^session ec-grfr · mayor" l)) lines))
      (should (seq-find (lambda (l) (string-match-p "^workdir ~/emacs-city\\|^workdir /home" l))
                        lines))
      (should (seq-find (lambda (l) (string-match-p "^created " l)) lines))
      (should (seq-find (lambda (l) (string-match-p "^provider pi" l)) lines))
      (should-not (seq-find (lambda (l) (string-match-p "●" l)) lines)))))

(ert-deftest gascity-test-rig-ready-capped-and-noise-hidden ()
  "The rig dashboard's bead sections follow the cockpit rules: noise
hidden with a named tally, at most five rows, a `… N more' line whose
RET opens the rig's beads (QA re-check)."
  (let* ((beads (vconcat
                 (cl-loop for i below 8 collect
                          `((id . ,(format "be-%02d" i)) (status . "open")
                            (issue_type . "task") (priority . 2)
                            (title . ,(format "task %d" i))))
                 (list '((id . "be-c1") (issue_type . "convoy") (status . "open"))
                       '((id . "be-c2") (issue_type . "convoy") (status . "open"))
                       '((id . "be-s1") (issue_type . "session") (status . "open")))))
         (text (gascity-test--vnode-text
                (gascity-rig--beads-section "Ready" (list :state 'ready :data beads)))))
    (should (string-match-p "^Ready  8  (2 convoy · 1 session hidden)" text))
    (should (= 5 (let ((n 0) (start 0))
                   (while (string-match "task [0-9]" text start)
                     (setq n (1+ n) start (match-end 0)))
                   n)))
    (should (string-match-p "… 3 more +b beads" text))
    (should-not (string-match-p "be-c1\\|be-s1" text)))
  ;; RET on the more line opens the rig's beads.
  (with-temp-buffer
    (insert (propertize "  … 3 more" 'gascity-rig-more t))
    (goto-char (point-min))
    (let (opened)
      (cl-letf (((symbol-function 'gascity-rig-dashboard-beads)
                 (lambda () (setq opened t))))
        (gascity-rig-dashboard-activate))
      (should opened))))

(provide 'gascity-agents-test)
;;; gascity-agents-test.el ends here
