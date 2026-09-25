;;; gascity-cockpit-test.el --- ERT tests for the dashboard-v3 cockpit -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Tests for dashboard-v3 phases P0 (hygiene) and P2 (the cockpit):
;; the shared visual language (`gascity-ui'), the §5.5 filter menus,
;; and the cockpit's pure selectors and rendering.  Pure tests stub the
;; gc boundary; nothing here runs gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)

;;; Relative times (§6.1)

(ert-deftest gascity-test-ui-relative-time ()
  "Relative times read `12s', `3m', `2h', `yesterday', `Sep 22'."
  (let ((now (gascity-ui-parse-time "2026-09-25T14:00:00Z")))
    (should (equal (gascity-ui-relative-time "2026-09-25T13:59:48Z" now) "12s"))
    (should (equal (gascity-ui-relative-time "2026-09-25T13:57:00Z" now) "3m"))
    (should (equal (gascity-ui-relative-time "2026-09-25T12:00:00+00:00" now) "2h"))
    ;; Local offsets and nanoseconds parse like UTC.
    (should (equal (gascity-ui-relative-time
                    "2026-09-25T15:30:00.293914966+02:00" now)
                   "30m"))
    (should (equal (gascity-ui-relative-time "2026-09-22T09:00:00Z" now)
                   (format-time-string "%b %e"
                                       (gascity-ui-parse-time
                                        "2026-09-22T09:00:00Z"))))
    (should (equal (gascity-ui-relative-time nil now) ""))
    (should (equal (gascity-ui-relative-time "garbage" now) ""))
    ;; ISO in help-echo.
    (should (equal (get-text-property
                    0 'help-echo (gascity-ui-time "2026-09-25T13:57:00Z" now))
                   "2026-09-25T13:57:00Z"))))

(ert-deftest gascity-test-ui-relative-time-yesterday ()
  "A timestamp on the previous calendar day, over 24h old, is `yesterday'."
  (let* ((now (float-time (encode-time (list 0 0 23 25 9 2026 nil -1 nil))))
         (then (float-time (encode-time (list 0 0 9 24 9 2026 nil -1 nil)))))
    (should (equal (gascity-ui-relative-time (- then 3600) now) "yesterday"))))

;;; Filter menus (§5.5)

(defconst gascity-test--filter-prefixes
  '(gascity-rig-list-filter gascity-session-list-filter
    gascity-convoy-list-filter gascity-mail-inbox-filter
    gascity-order-list-filter gascity-dolt-list-filter)
  "Every tabulated view's `/' menu.")

(defun gascity-test--prefix-has-key (prefix key)
  "Return the command bound to KEY in transient PREFIX, or nil."
  (condition-case nil
      (let ((suffix (transient-get-suffix prefix key)))
        (and suffix (plist-get (cdr suffix) :command)))
    (error nil)))

(ert-deftest gascity-test-filter-menus-apply-on-change ()
  "Every list `/' menu has `-S' sort, no Apply step, `x' reset where it filters."
  (dolist (prefix gascity-test--filter-prefixes)
    (should (eq (gascity-test--prefix-has-key prefix "-S")
                'gascity-tabulated-sort-by))
    (should-not (gascity-test--prefix-has-key prefix "a"))
    (unless (eq prefix 'gascity-dolt-list-filter)
      (should (eq (gascity-test--prefix-has-key prefix "x")
                  'gascity-filter-reset)))))

(ert-deftest gascity-test-filter-letters ()
  "Filter letters follow §5.5: `-s' state, `-r' rig, `-u' unread, `-t' type."
  (should (gascity-test--prefix-has-key 'gascity-session-list-filter "-s"))
  (should (gascity-test--prefix-has-key 'gascity-session-list-filter "-r"))
  (should (gascity-test--prefix-has-key 'gascity-rig-list-filter "-s"))
  (should (gascity-test--prefix-has-key 'gascity-convoy-list-filter "-s"))
  (should (gascity-test--prefix-has-key 'gascity-mail-inbox-filter "-u"))
  (should (gascity-test--prefix-has-key 'gascity-order-list-filter "-t")))

(ert-deftest gascity-test-filter-set-refreshes-list ()
  "A filter change stores the plist value and refreshes the list at once;
`x' clears every key."
  (let ((refreshes 0))
    (with-temp-buffer
      (cl-letf (((symbol-function 'gascity-session-list-refresh)
                 (lambda (&rest _) (cl-incf refreshes)))
                ((symbol-function 'gascity-live-attach)
                 #'ignore))
        (gascity-session-list-mode)
        (gascity-filter-set :state "active")
        (should (equal gascity-session-list--filter '(:state "active")))
        (gascity-filter-set :rig "beads")
        (should (equal (plist-get gascity-session-list--filter :rig) "beads"))
        (gascity-filter-set :state nil)
        (should (equal gascity-session-list--filter '(:rig "beads")))
        (should (= refreshes 3))
        (funcall gascity-filter-reset-function)
        (should (null gascity-session-list--filter))
        (should (= refreshes 4))
        (should (string-match-p "\\[beads\\]\\|\\[all\\]"
                                (gascity-filter-describe
                                 "rig…" (gascity-filter-value :rig))))))))

(ert-deftest gascity-test-S-is-sling-in-every-list ()
  "`S' is sling in every tabulated view; sort moved to `/ -S' (§5.3)."
  (dolist (map (list gascity-rig-list-mode-map gascity-session-list-mode-map
                     gascity-convoy-list-mode-map gascity-mail-inbox-mode-map
                     gascity-order-list-mode-map gascity-dolt-list-mode-map))
    (should (eq (keymap-lookup map "S") #'gascity-sling-dispatch))))

;;; Fixtures (real gc shapes, lisp/test/fixtures/v3)

(defconst gascity-cockpit-test--dir
  (expand-file-name "fixtures/v3/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the captured gc payloads.")

(defun gascity-cockpit-test--json (name)
  "Return fixture NAME decoded as the reader decodes gc JSON."
  (gascity-reader-parse-json
   (with-temp-buffer
     (insert-file-contents (expand-file-name name gascity-cockpit-test--dir))
     (buffer-string))))

(defun gascity-cockpit-test--jsonl (name)
  "Return fixture NAME (JSON Lines) decoded as a list of events."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name gascity-cockpit-test--dir))
    (delq nil (mapcar (lambda (line)
                        (and (not (string-empty-p line))
                             (gascity-reader-parse-json line)))
                      (split-string (buffer-string) "\n")))))

(defun gascity-cockpit-test--ts (seconds-ago)
  "Return an ISO timestamp SECONDS-AGO seconds before now (UTC)."
  (format-time-string "%FT%TZ" (- (float-time) seconds-ago) t))

(defun gascity-cockpit-test--load (data)
  "Return a ready load plist carrying DATA."
  (list :state 'ready :data data))

(cl-defun gascity-cockpit-test--ctx (&key status sessions mail events beads
                                          convoys escalations filters view)
  "Return a cockpit render context from canned payloads."
  (let ((ctx (gascity-dashboard--context
              (list :status (gascity-cockpit-test--load status)
                    :sessions (gascity-cockpit-test--load
                               (and sessions `((sessions . ,(vconcat sessions)))))
                    :mail (gascity-cockpit-test--load mail)
                    :events (gascity-cockpit-test--load (cons events 0))
                    :work (gascity-cockpit-test--load (list :beads beads))
                    :convoys (gascity-cockpit-test--load
                              `((convoys . ,(vconcat convoys))))
                    :escalations (gascity-cockpit-test--load (vconcat escalations))
                    :graphs (gascity-cockpit-test--load nil))
              filters (float-time))))
    (plist-put ctx :view view)))

(defun gascity-cockpit-test--kinds (items)
  "Return the (LEVEL KIND) pairs of Needs you ITEMS."
  (mapcar (lambda (i) (list (plist-get i :level) (plist-get i :kind))) items))

(defun gascity-cockpit-test--text (lines)
  "Return LINES (strings) as one plain string."
  (substring-no-properties (string-join lines "\n")))

;;; Needs you — one test per source (§7.1)

(ert-deftest gascity-test-cockpit-needs-you-stalled-agent ()
  "■ agent: gc status says running, no live session backs it."
  (let* ((status '((agents . [((qualified_name . "beads.el/worker")
                               (running . t))])))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :status status))))
    (should (equal (gascity-cockpit-test--kinds items) '((fail "agent"))))
    (should (string-match-p "beads.el/worker" (plist-get (car items) :text)))
    (should (gascity-agent-p (plist-get (plist-get (car items) :props)
                                        'gascity-agent)))))

(ert-deftest gascity-test-cockpit-needs-you-session-timeout ()
  "■ session: a cold-start timeout not followed by a wake of that session.
The real event carries no session_id, only the tmux name as subject;
the id is its trailing `ec-…' handle."
  (let* ((events (gascity-cockpit-test--jsonl
                  "emacs-city.events-24h-signal-sample.jsonl"))
         (timeouts (seq-filter (lambda (e) (equal (alist-get 'type e)
                                                  "session.cold_start_timeout"))
                               events))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :events timeouts))))
    (should (= (length items) (length timeouts)))
    (should (seq-every-p (lambda (i) (equal (plist-get i :kind) "session")) items))
    ;; A later wake of the same session clears it.
    (let* ((one (car timeouts))
           (woke `((type . "session.woke") (session_id . "ec-r3bc")
                   (ts . "2026-09-24T19:59:00+02:00") (seq . 1)))
           (items (gascity-dashboard--needs-you
                   (gascity-cockpit-test--ctx :events (list one woke)))))
      (should (equal (alist-get 'subject one)
                     "gc__design-implementation-reviewer-ec-r3bc"))
      (should-not items))))

(ert-deftest gascity-test-cockpit-needs-you-idle-run ()
  "■ run idle: root in progress, no step touched within the threshold."
  (let* ((root `((id . "be-52m5") (status . "in_progress") (title . "build-basic")
                 (updated_at . ,(gascity-cockpit-test--ts 7200))
                 (metadata . ((gc.kind . "workflow") (gc.formula_name . "build-basic")))
                 (gascity-rig . "beads.el")))
         (step `((id . "be-bcb5") (status . "in_progress")
                 (updated_at . ,(gascity-cockpit-test--ts 2520))
                 (metadata . ((gc.root_bead_id . "be-52m5")))))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :beads (list root step)))))
    (should (equal (gascity-cockpit-test--kinds items) '((fail "run"))))
    (should (string-match-p "be-52m5 build-basic  idle 42m"
                            (plist-get (car items) :text)))
    ;; Fresh step progress: not idle.
    (setf (alist-get 'updated_at step) (gascity-cockpit-test--ts 60))
    (should-not (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :beads (list root step))))))

(ert-deftest gascity-test-cockpit-needs-you-failed-run ()
  "■ run failed: a workflow root closed with gc.outcome fail in the window."
  (let* ((event `((type . "bead.closed") (seq . 9) (ts . "2026-09-24T22:17:42+02:00")
                  (payload . ((bead . ((id . "be-j2b") (status . "closed")
                                       (metadata . ((gc.kind . "workflow")
                                                    (gc.outcome . "fail")
                                                    (gc.formula_name . "build-basic")))))))))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :events (list event event)))))
    (should (equal (gascity-cockpit-test--kinds items) '((fail "run"))))
    (should (string-match-p "be-j2b build-basic  failed" (plist-get (car items) :text)))))

(ert-deftest gascity-test-cockpit-needs-you-dead-assignee ()
  "▲ bead: bead.dead_assignee_reopened, one row per bead."
  (let* ((events (seq-filter (lambda (e) (equal (alist-get 'type e)
                                                "bead.dead_assignee_reopened"))
                             (gascity-cockpit-test--jsonl
                              "emacs-city.events-24h-signal-sample.jsonl")))
         (ids (delete-dups (mapcar (lambda (e) (alist-get 'bead_id (alist-get 'payload e)))
                                   events)))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :events events))))
    (should (= (length items) (length ids)))
    (should (seq-every-p (lambda (i) (eq (plist-get i :level) 'watch)) items))))

(ert-deftest gascity-test-cockpit-needs-you-escalated ()
  "▲ bead: labelled gc:escalation (label-regex read) or hold:* (work read)."
  (let* ((esc '((id . "ec-e1") (status . "open") (title . "help")
                (labels . ["gc:escalation"])))
         (hold '((id . "ga-h1") (status . "open") (title . "wait")
                 (labels . ["hold:review"]) (gascity-rig . "gascity.el")))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :escalations (list esc) :beads (list hold)))))
    (should (equal (gascity-cockpit-test--kinds items) '((watch "bead") (watch "bead"))))
    (should (string-match-p "escalated" (plist-get (nth 0 items) :text)))
    (should (string-match-p "hold:review" (plist-get (nth 1 items) :text)))))

(ert-deftest gascity-test-cockpit-needs-you-mail-and-store ()
  "▲ mail: one aggregate unread row; ▲ store: warning or partial_errors."
  (let* ((mail (gascity-cockpit-test--json "emacs-city.mail-count.json"))
         (status '((summary . ((store_health . ((warning . t)
                                                 (ratio_mb_per_row . 2.5)))))))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx :mail mail :status status))))
    (should (equal (gascity-cockpit-test--kinds items)
                   '((watch "mail") (watch "store"))))
    (should (string-match-p "^5 unread" (plist-get (car items) :text))))
  (let ((items (gascity-dashboard--needs-you
                (gascity-cockpit-test--ctx
                 :status '((partial_errors . ["counting retained bead rows: list timed out"]))))))
    (should (string-match-p "list timed out" (plist-get (car items) :text)))))

(ert-deftest gascity-test-cockpit-needs-you-order ()
  "■ items precede ▲ items whatever order the sources yield them."
  (let* ((status '((agents . [((qualified_name . "w") (running . t))])))
         (items (gascity-dashboard--needs-you
                 (gascity-cockpit-test--ctx
                  :status status
                  :mail '((unread . 3))
                  :escalations '(((id . "ec-e") (status . "open")
                                  (labels . ["gc:escalation"])))))))
    (should (equal (mapcar (lambda (i) (plist-get i :level)) items)
                   '(fail watch watch)))))

;;; Noise, caps, ladder

(ert-deftest gascity-test-cockpit-noise-classes ()
  "Nudges, order churn, messages, wisps, sessions and convoys are noise."
  (should (eq (gascity-dashboard--noise '((labels . ["nudge:x"]))) 'nudge))
  (should (eq (gascity-dashboard--noise '((title . "nudge:nudge-1"))) 'nudge))
  (should (eq (gascity-dashboard--noise '((labels . ["order-tracking"]))) 'order))
  (should (eq (gascity-dashboard--noise '((labels . ["order-run:sweep"]))) 'order))
  (should (eq (gascity-dashboard--noise '((issue_type . "message"))) 'message))
  (should (eq (gascity-dashboard--noise '((id . "ec-wisp-3kvmdi"))) 'wisp))
  (should (eq (gascity-dashboard--noise '((issue_type . "session"))) 'session))
  (should (eq (gascity-dashboard--noise '((issue_type . "convoy"))) 'convoy))
  (should-not (gascity-dashboard--noise '((id . "be-3z6o") (issue_type . "task")))))

(ert-deftest gascity-test-cockpit-work-hidden-counts ()
  "Work hides noise with a named tally; a show filter brings it back (D4)."
  (let* ((beads (append
                 (cl-loop for i below 3 collect
                          `((id . ,(format "ec-wisp-n%d" i)) (status . "open")
                            (labels . ["nudge:x"])))
                 (list '((id . "ec-wisp-o") (status . "open")
                         (labels . ["order-tracking"]))
                       '((id . "ec-grfr") (status . "open") (issue_type . "session"))
                       '((id . "ga-1") (status . "open") (priority . 2) (title . "real")))))
         (ctx (gascity-cockpit-test--ctx :beads beads))
         (work (gascity-dashboard--work ctx)))
    (should (= (length (plist-get work :ready)) 1))
    (should (equal (substring-no-properties
                    (gascity-dashboard--hidden-label (plist-get work :hidden)))
                   "(3 nudge · 1 order · 1 session hidden)"))
    (let ((shown (gascity-dashboard--work
                  (gascity-cockpit-test--ctx :beads beads :filters '(:nudges t)))))
      (should (= (length (plist-get shown :ready)) 4)))))

(ert-deftest gascity-test-cockpit-section-cap ()
  "No section shows more than five rows; the rest is one `… N more' line."
  (let* ((beads (cl-loop for i below 12 collect
                         `((id . ,(format "ga-%02d" i)) (status . "open")
                           (priority . 2) (title . ,(format "bead %d" i)))))
         (lines (gascity-dashboard--work-lines
                 (gascity-cockpit-test--ctx :beads beads)))
         (text (gascity-cockpit-test--text lines)))
    (should (= (length lines) 7))       ; header + 5 rows + more
    (should (string-match-p "… 7 more +j b beads" text))
    (should (string-prefix-p "Work  12 ready" (car lines)))))

(ert-deftest gascity-test-cockpit-ladder-from-real-run ()
  "The ladder of build-basic be-52m5 is its ten top-level steps, in order."
  (let* ((beads (append (gascity-cockpit-test--json
                         "emacs-city.bd-list-all-beads.el-runs.json")
                        nil))
         (root (seq-find (lambda (b) (equal (alist-get 'id b) "be-52m5")) beads))
         (graph (seq-filter (lambda (b) (equal (gascity-dashboard--root-of b) "be-52m5"))
                            beads))
         (ladder (gascity-dashboard--ladder root graph)))
    (should (equal (mapcar (lambda (s) (plist-get s :name)) ladder)
                   '("prepare" "requirements" "plan" "plan-review" "decompose"
                     "implement" "summarize-implementation" "review"
                     "finalize" "publish")))
    (should (equal (cdr (gascity-dashboard--ladder-label ladder)) "10/10"))))

(ert-deftest gascity-test-cockpit-activity-folds-churn ()
  "Order firings fold into one ×N row per 15 minutes; signal never folds."
  (let* ((events (gascity-cockpit-test--jsonl "emacs-city.events-2h.jsonl"))
         (model (gascity-dashboard--activity events nil))
         (orders (seq-count (lambda (e) (string-prefix-p "order." (alist-get 'type e)))
                            events)))
    (should (> (cdr model) orders))    ; orders + wisp lifecycle folded
    (should (seq-every-p (lambda (row) (eq (car row) 'churn)) (car model)))
    (should (< (length (car model)) 20))
    (let ((signal '((type . "session.cold_start_timeout") (seq . 1)
                    (ts . "2026-09-25T13:03:00Z") (subject . "x"))))
      (should (eq (car (car (car (gascity-dashboard--activity (list signal) nil))))
                  'event)))
    ;; Unfold shows every event as its own row.
    (should (= (length (car (gascity-dashboard--activity events '(:unfold t))))
               (length events)))))

;;; Keys (§5, §6.2)

(defconst gascity-cockpit-test--view-maps
  '(gascity-dashboard-mode-map gascity-rig-dashboard-mode-map
    gascity-session-detail-mode-map gascity-run-mode-map
    gascity-rig-list-mode-map gascity-session-list-mode-map
    gascity-convoy-list-mode-map gascity-mail-inbox-mode-map
    gascity-order-list-mode-map gascity-dolt-list-mode-map)
  "Every gascity view keymap.")

(ert-deftest gascity-test-cockpit-global-keys-agree ()
  "The §5.1 keys mean the same thing in every view (no collision)."
  (dolist (sym gascity-cockpit-test--view-maps)
    (let ((map (symbol-value sym)))
      (should (eq (keymap-lookup map "?") 'gascity-dispatch))
      (should (eq (keymap-lookup map "j a") 'gascity-jump-agents))
      (should (eq (keymap-lookup map "j j") 'gascity-jump-cockpit))
      (should (eq (keymap-lookup map "TAB") 'gascity-thing-forward))
      (should (eq (keymap-lookup map "<tab>") 'gascity-thing-forward))
      (should (eq (keymap-lookup map "<backtab>") 'gascity-thing-backward))
      (should (eq (keymap-lookup map "S") 'gascity-sling-dispatch))
      (should (keymap-lookup map "g"))
      (should (memq (keymap-lookup map "SPC")
                    '(gascity-thing-toggle gascity-tabulated-detail-toggle)))
      (should (eq (keymap-lookup map "DEL") 'undefined)))))

(defun gascity-cockpit-test--dispatch-suffixes ()
  "Return the (KEY . COMMAND) suffixes of the `?' dispatch."
  (let (out)
    (cl-labels ((walk (node)
                  (cond ((vectorp node) (mapc #'walk node))
                        ((and (consp node) (keywordp (car-safe (cdr-safe node))))
                         nil)
                        ((consp node) (mapc #'walk node))
                        ((and (fboundp 'transient-suffix--eieio-childp)
                              (cl-typep node 'transient-suffix))
                         (push (cons (oref node key) (oref node command)) out)))))
      (walk (get 'gascity-dispatch 'transient--layout)))
    out))

(ert-deftest gascity-test-cockpit-dispatch-keys-match-views ()
  "Every `?' suffix sits under the key it has in the cockpit, uniquely."
  (let ((keys '("j j" "j a" "j r" "j b" "j m" "j e" "j h" "j c" "j o" "j v" "j d"
                "j g" "M" "s" "w" "K" "D" "R" "U" "t" "S" "c" "m" "L" "C" "O"
                "W" "g" "/")))
    (dolist (key keys)
      (let* ((suffix (transient-get-suffix 'gascity-dispatch key))
             (cmd (plist-get (cdr suffix) :command))
             (view (keymap-lookup gascity-dashboard-mode-map key)))
        (should cmd)
        (pcase key
          ("g" (should (eq view 'gascity-dashboard-refresh)))
          ("/" (should (eq view 'gascity-dashboard-filter)))
          (_ (should (eq cmd view))))))
    ;; Unique within the transient.
    (should (= (length keys) (length (delete-dups (copy-sequence keys)))))
    ;; A key the dispatch does not list is not silently rebound there.
    (should-error (transient-get-suffix 'gascity-dispatch "n"))))

(ert-deftest gascity-test-cockpit-filter-letters ()
  "The cockpit `/' menu uses the §5.5/§7.2 letters, `x' resets."
  (dolist (key '("-w" "-n" "-o" "-m" "-r" "-W" "-c" "x"))
    (should (transient-get-suffix 'gascity-dashboard-filter key))))

;;; Mounted cockpit: movement, toggles, drawers (§5.4)

(defun gascity-cockpit-test--scenario-read (args callback &optional _errback &rest _)
  "Canned `gascity-reader-read-async' for a busy emacs-city scenario."
  (funcall
   callback
   (pcase args
     (`("status") (gascity-cockpit-test--json "emacs-city.status.json"))
     (`("session" "list") (gascity-cockpit-test--json "emacs-city.session-list.json"))
     (`("mail" "count") (gascity-cockpit-test--json "emacs-city.mail-count.json"))
     (`("events" . ,_)
      (cons (append (gascity-cockpit-test--jsonl "emacs-city.events-2h.jsonl")
                    (seq-take (gascity-cockpit-test--jsonl
                               "emacs-city.events-24h-signal-sample.jsonl")
                              30))
            0))
     (`("convoy" "list") (gascity-cockpit-test--json "emacs-city.convoy-list.json"))
     (`("rig" "list") (gascity-cockpit-test--json "emacs-city.rig-list.json"))
     (`("bd" "list" "--label-regex" . ,_) [])
     (`("bd" "list" "--all" . ,_) [])
     (`("bd" "list" "--status" ,_ "-n" "0" "--rig" ,rig)
      (gascity-cockpit-test--json
       (format "emacs-city.bd-list-open-inprogress-%s.json" rig)))
     (`("bd" "list" "--status" . ,_)
      (gascity-cockpit-test--json "emacs-city.bd-list-open-inprogress.json"))
     (_ (error "Unexpected read %S" args))))
  nil)

(defmacro gascity-cockpit-test--with-cockpit (&rest body)
  "Mount the cockpit on canned payloads and run BODY in its buffer."
  (declare (indent 0))
  `(let ((vui-render-delay nil)
         (gascity-dashboard-filters nil)
         (buf (get-buffer-create "*gascity-cockpit-test*")))
     (cl-letf (((symbol-function 'gascity-reader-read-async)
                #'gascity-cockpit-test--scenario-read)
               ((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
               ((symbol-function 'gascity-rigs-remember) (lambda (r &rest _) r)))
       (unwind-protect
           (save-window-excursion
             (with-current-buffer buf (gascity-dashboard-mode))
             (vui-mount (vui-component 'gascity-dashboard-app :initial-filters nil)
                        (buffer-name buf))
             (with-current-buffer buf ,@body))
         (kill-buffer buf)))))

(defun gascity-cockpit-test--line-at-thing ()
  "Return the text of the line at point."
  (buffer-substring-no-properties (line-beginning-position) (line-end-position)))

(ert-deftest gascity-test-cockpit-renders-sections-in-order ()
  "The mounted cockpit renders the six sections, in order, under 80 lines."
  (gascity-cockpit-test--with-cockpit
    (let ((text (buffer-string)))
      (should (< (count-lines (point-min) (point-max)) 80))
      (let ((pos (mapcar (lambda (title)
                           (string-match (concat "^" title "\\b") text))
                         '("Needs you" "Moving" "Agents" "Work" "Activity" "Rigs"))))
        (should (seq-every-p #'numberp pos))
        (should (equal pos (sort (copy-sequence pos) #'<))))
      (should (string-match-p "^emacs-city  ~/emacs-city\\|^emacs-city  /home" text))
      ;; No apology line mentions a missing gc surface.
      (should-not (string-match-p "no JSON\\|not exposed\\|json_unsupported\\|(mode —)\\|api —"
                                  text)))))

(ert-deftest gascity-test-cockpit-tab-visits-things-in-order ()
  "TAB visits exactly the things (headers, rows, folds, more lines) in order,
wrapping at the end; decoration is skipped."
  (gascity-cockpit-test--with-cockpit
    (let ((starts (beads-thing-starts))
          (visited nil))
      (should (> (length starts) 8))
      (goto-char (point-min))
      (dotimes (_ (length starts))
        (gascity-thing-forward 1)
        (push (point) visited))
      (should (equal (nreverse visited) starts))
      ;; One more TAB wraps to the first thing.
      (gascity-thing-forward 1)
      (should (= (point) (car starts)))
      ;; Top lines and blank lines are not things.
      (should-not (get-text-property (point-min) 'beads-thing))
      ;; Every section header is a thing, in order.
      (should (equal (seq-keep (lambda (p)
                                 (let ((th (get-text-property p 'beads-thing)))
                                   (and (eq (plist-get th :kind) 'section)
                                        (plist-get th :id))))
                               starts)
                     '("needs-you" "moving" "agents" "work" "activity" "rigs")))
      ;; S-TAB from the first thing wraps to the last.
      (goto-char (car starts))
      (gascity-thing-backward 1)
      (should (= (point) (car (last starts)))))))

(ert-deftest gascity-test-cockpit-spc-toggles-each-kind ()
  "SPC folds a section, expands a fold row, opens a drawer; state survives g."
  (gascity-cockpit-test--with-cockpit
    ;; Section header: fold.
    (goto-char (point-min))
    (re-search-forward "^Rigs")
    (beginning-of-line)
    (gascity-thing-toggle)
    (should (string-match-p "^▸ Rigs" (buffer-string)))
    (should-not (string-match-p "~/workspace/beads.el" (buffer-string)))
    ;; Refresh keeps the fold.
    (gascity-dashboard-refresh)
    (should (string-match-p "^▸ Rigs" (buffer-string)))
    ;; Fold row: ▸ stopped expands in place.
    (goto-char (point-min))
    (re-search-forward "▸ stopped")
    (gascity-thing-toggle)
    (should (string-match-p "▾ stopped" (buffer-string)))
    (should (string-match-p "^  ○ bd.dog-1 " (buffer-string)))
    ;; Row: an agent's drawer opens beneath it.
    (goto-char (point-min))
    (re-search-forward "^  ○ mayor")
    (gascity-thing-toggle)
    (forward-line 1)
    (should (string-match-p "│ session ec-grfr" (gascity-cockpit-test--line-at-thing)))
    (gascity-dashboard-refresh)
    (should (string-match-p "│ session ec-grfr" (buffer-string)))
    ;; SPC again closes it.
    (goto-char (point-min))
    (re-search-forward "^  ○ mayor")
    (gascity-thing-toggle)
    (should-not (string-match-p "│ session ec-grfr" (buffer-string)))
    ;; A churn fold expands into its events.
    (goto-char (point-min))
    (re-search-forward "×[0-9]+ +order.fired/completed")
    (let ((before (count-lines (point-min) (point-max))))
      (gascity-thing-toggle)
      (should (> (count-lines (point-min) (point-max)) before)))))

(ert-deftest gascity-test-cockpit-ret-never-folds ()
  "RET on a section header opens its view instead of folding it."
  (gascity-cockpit-test--with-cockpit
    (let (opened)
      (cl-letf (((symbol-function 'gascity-jump-agents)
                 (lambda () (interactive) (setq opened 'agents))))
        (goto-char (point-min))
        (re-search-forward "^Agents")
        (gascity-dashboard-activate)
        (should (eq opened 'agents))
        (should-not (string-match-p "^▸ Agents" (buffer-string)))))))

(ert-deftest gascity-test-cockpit-filter-rerenders-and-remembers ()
  "A `/' change applies at once and is remembered for the city."
  (gascity-cockpit-test--with-cockpit
    (should (string-match-p "(2 session hidden)" (buffer-string)))
    (gascity-filter-set :unfold t)
    (should (plist-get (gascity-dashboard--filters) :unfold))
    (should (plist-get (alist-get (gascity-dashboard--city-key)
                                  gascity-dashboard-filters nil nil #'equal)
                       :unfold))
    (should-not (string-match-p "churn folded" (buffer-string)))
    (funcall gascity-filter-reset-function)
    (should-not (gascity-dashboard--filters))))

;;; Movement in the other views (§5.4)

(ert-deftest gascity-test-vui-views-stamp-things-and-fold ()
  "A vui view without its own stamps gets things from its row identities;
SPC on a header folds that section, and the fold is re-applied."
  (with-temp-buffer
    (gascity-section-mode)
    (let ((inhibit-read-only t))
      (insert (propertize "Agents  1 running" 'gascity-section t) "\n"
              "  " (propertize "● rig/a" 'gascity-bead "ga-1") "\n"
              "\n"
              (propertize "Ready  none" 'gascity-section t) "\n"))
    (goto-char (point-min))              ; on the first thing already
    (gascity-thing-forward 1)
    (should (looking-at "● rig/a"))
    (gascity-thing-forward 1)
    (should (looking-at "Ready"))
    (gascity-thing-forward 1)            ; wraps
    (should (looking-at "Agents"))
    (gascity-thing-toggle)
    (should (invisible-p (save-excursion (forward-line 1) (point))))
    (gascity-section--apply-folds)       ; as after a re-render
    (should (invisible-p (save-excursion (forward-line 1) (point))))
    (gascity-thing-toggle)
    (should-not (invisible-p (save-excursion (forward-line 1) (point))))))

(ert-deftest gascity-test-tabulated-detail-window ()
  "SPC shows the row's detail in a side window; `q' closes it first."
  (let ((buf (get-buffer-create "*gascity-detail-test*")))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer buf)
          (cl-letf (((symbol-function 'gascity-convoy-list-refresh) #'ignore))
            (gascity-convoy-list-mode))
          (setq tabulated-list-entries
                (list (list '((id . "ga-1ekj") (title . "sling-ga-rs12"))
                            (vector "ga-1ekj" "sling-ga-rs12" "open" "1/1"))))
          (tabulated-list-print)
          (goto-char (point-min))
          (gascity-tabulated-detail-toggle)
          (let ((win (gascity-tabulated--detail-window)))
            (should (window-live-p win))
            (should (string-match-p "ga-1ekj"
                                    (with-current-buffer (window-buffer win)
                                      (buffer-string))))
            (should (eq (selected-window) (get-buffer-window buf))))
          (gascity-tabulated-quit)
          (should-not (gascity-tabulated--detail-window))
          (should (eq (window-buffer) buf)))
      (kill-buffer buf)
      (when (get-buffer "*gascity-detail*") (kill-buffer "*gascity-detail*")))))

(ert-deftest gascity-test-rig-dashboard-keys ()
  "The rig dashboard gains `l' (git log) and keeps the agent keys (§7.13)."
  (should (eq (keymap-lookup gascity-rig-dashboard-mode-map "l")
              #'gascity-rig-dashboard-log))
  (should (eq (keymap-lookup gascity-dashboard-mode-map "l")
              #'gascity-dashboard-rig-log)))

(ert-deftest gascity-test-cockpit-jump-needs-a-command ()
  "A jump target must be a command: `gascity-mail' is also a class
constructor, so `j m' falls through to the mail inbox command."
  (let (called)
    (cl-letf (((symbol-function 'gascity-mail-inbox)
               (lambda () (interactive) (setq called 'inbox))))
      (gascity-jump-mail)
      (should (eq called 'inbox))))
  (let ((msg nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
      (gascity-jump--call '(gascity-no-such-view) "Health")
      (should (equal msg "The Health view is not available yet")))))

(ert-deftest gascity-test-cockpit-moving-run-with-worker ()
  "Moving shows an active run's ladder, active step and progress, with its
live worker nested once (a looping step and its iteration share a worker)."
  (let* ((graph (mapcar
                 (lambda (b)
                   (let ((ref (alist-get 'gc.step_ref (alist-get 'metadata b))))
                     (cond ((equal ref "build-basic.prepare")
                            (cons '(status . "closed") b))
                           ((member ref '("build-basic.requirements"
                                          "requirements.iteration.1"))
                            (append `((status . "in_progress")
                                      (assignee . "gc__requirements-planner-ec-fl8o")
                                      (updated_at . ,(gascity-cockpit-test--ts 180)))
                                    b))
                           (t (cons '(status . "open") b)))))
                 (seq-filter (lambda (b) (equal (gascity-dashboard--root-of b) "be-52m5"))
                             (append (gascity-cockpit-test--json
                                      "emacs-city.bd-list-all-beads.el-runs.json")
                                     nil))))
         (root `((id . "be-52m5") (status . "in_progress") (title . "build-basic")
                 (created_at . ,(gascity-cockpit-test--ts 7200))
                 (updated_at . ,(gascity-cockpit-test--ts 100))
                 (metadata . ((gc.kind . "workflow") (gc.formula_name . "build-basic")))
                 (gascity-rig . "beads.el")))
         (beads (cons root (seq-filter (lambda (b) (equal (alist-get 'status b)
                                                          "in_progress"))
                                       graph)))
         (graphs (let ((h (make-hash-table :test 'equal)))
                   (puthash "be-52m5" graph h) h))
         (sessions (list `((id . "ec-fl8o")
                           (agent_name . "beads.el/gc.requirements-planner-1")
                           (state . "active")
                           (session_name . "gc__requirements-planner-ec-fl8o")
                           (last_active . ,(gascity-cockpit-test--ts 180)))))
         (ctx (plist-put (gascity-cockpit-test--ctx :beads beads :sessions sessions)
                         :graphs graphs))
         (text (gascity-cockpit-test--text
                (let ((gascity-dashboard--view nil))
                  (gascity-dashboard--moving-lines ctx)))))
    (should (string-match-p "^Moving  1 run · 1 worker" text))
    (should (string-match-p
             "⬣ be-52m5 +build-basic +◆⬣········ +requirements +1/10 +2h +beads.el"
             text))
    (should (string-match-p "└ ● requirements-planner-1 +be-bcb5 +Generate requirements"
                            text))
    (should (= 1 (cl-count ?└ text)))))

(provide 'gascity-cockpit-test)
;;; gascity-cockpit-test.el ends here
