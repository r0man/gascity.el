;;; gascity-test.el --- Tests for gascity P0 -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; ERT tests for the P0 foundation.  The pure tests (JSON decoding,
;; command-line construction, subcommand derivation) run anywhere.  The
;; round-trip integration test needs a live `gc' and a city, and skips
;; itself otherwise.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)

(defun gascity-test--plain-cols (entry)
  "Return ENTRY's column vector as a list of property-stripped values."
  (cl-map 'list (lambda (c) (if (stringp c) (substring-no-properties c) c))
          (cadr entry)))

;;; gascity-reader-parse-json

(ert-deftest gascity-test-parse-json-object ()
  "JSON objects decode to symbol-keyed alists."
  (let ((r (gascity-reader-parse-json "{\"a\":1,\"b\":\"x\"}")))
    (should (equal (alist-get 'a r) 1))
    (should (equal (alist-get 'b r) "x"))))

(ert-deftest gascity-test-parse-json-array-is-vector ()
  "JSON arrays decode to vectors."
  (should (equal (gascity-reader-parse-json "[1,2,3]") [1 2 3])))

(ert-deftest gascity-test-parse-json-booleans-and-null ()
  "Both false and null decode to nil; true decodes to t."
  (let ((r (gascity-reader-parse-json
            "{\"yes\":true,\"no\":false,\"nada\":null}")))
    (should (eq (cdr (assq 'yes r)) t))
    (should (assq 'no r))                ; key present ...
    (should (null (cdr (assq 'no r))))   ; ... value nil
    (should (assq 'nada r))
    (should (null (cdr (assq 'nada r))))))

(ert-deftest gascity-test-parse-json-invalid-signals ()
  "Malformed JSON signals `gascity-json-parse-error'."
  (should-error (gascity-reader-parse-json "{not json")
                :type 'gascity-json-parse-error))

;;; gascity-command-line / subcommand

(ert-deftest gascity-test-status-command-line ()
  "Status defaults to JSON output."
  (should (equal (gascity-command-line (gascity-command-status))
                 '("gc" "status" "--json"))))

(ert-deftest gascity-test-status-command-line-no-json ()
  "Disabling :json drops the flag."
  (should (equal (gascity-command-line (gascity-command-status :json nil))
                 '("gc" "status"))))

(ert-deftest gascity-test-status-command-line-verbose ()
  "The verbose global flag is emitted when set."
  (should (member "--verbose"
                  (gascity-command-line (gascity-command-status :verbose t)))))

(ert-deftest gascity-test-subcommand-derivation ()
  "The subcommand is derived from the class name."
  (should (equal (gascity-command-subcommand (gascity-command-status))
                 "status")))

(ert-deftest gascity-test-executable-honoured ()
  "`gascity-executable' leads the command line."
  (let ((gascity-executable "/usr/local/bin/gc"))
    (should (equal (car (gascity-command-line (gascity-command-status)))
                   "/usr/local/bin/gc"))))

;;; List command classes — command-line derivation

(ert-deftest gascity-test-list-command-lines ()
  "The read-only list commands derive the right `gc' subcommands."
  (should (equal (gascity-command-line (gascity-command-rig-list))
                 '("gc" "rig" "list" "--json")))
  (should (equal (gascity-command-line (gascity-command-session-list))
                 '("gc" "session" "list" "--json")))
  (should (equal (gascity-command-line (gascity-command-convoy-list))
                 '("gc" "convoy" "list" "--json")))
  (should (equal (gascity-command-line (gascity-command-mail-inbox))
                 '("gc" "mail" "inbox" "--json")))
  (should (equal (gascity-command-line (gascity-command-order-list))
                 '("gc" "order" "list" "--json")))
  (should (equal (gascity-command-line (gascity-command-dolt-health))
                 '("gc" "dolt" "health" "--json"))))

;;; Tabulated helpers

(ert-deftest gascity-test-tabulated-helpers ()
  "Vector/timestamp/string helpers behave."
  (should (equal (gascity-tabulated--vector->list [1 2 3]) '(1 2 3)))
  (should (equal (gascity-tabulated--vector->list '(1 2)) '(1 2)))
  (should (equal (gascity-tabulated--format-timestamp "2026-06-01T19:18:18Z")
                 "2026-06-01"))
  (should (equal (gascity-tabulated--format-timestamp "") ""))
  (should (equal (gascity-tabulated--format-timestamp nil) ""))
  (should (equal (gascity-tabulated--str 42) "42"))
  (should (equal (gascity-tabulated--str nil) ""))
  (should (equal (gascity-tabulated--str t) "yes")))

;;; Tabulated entry builders

(ert-deftest gascity-test-rig-entry ()
  "A rig entry keeps the alist as its id and lays out columns."
  (let* ((rig '((name . "gascity.el") (prefix . "gce") (running . t) (suspended)
                (default_branch . "main") (beads . "initialized")))
         (entry (gascity-rig-list--entry rig)))
    (should (eq (car entry) rig))
    (should (equal (gascity-test--plain-cols entry)
                   '("gascity.el" "gce" "running" "main" "initialized")))))

(ert-deftest gascity-test-session-entry-id-is-agent-plist ()
  "A session entry's id is the agent action plist, with the passed socket."
  (let* ((s '((agent_name . "gascity.el/gastown.furiosa") (rig . "gascity.el")
              (state . "active") (provider . "claude")
              (work_dir . "/wd") (session_name . "tm")))
         (id (car (gascity-session-list--entry s "sock"))))
    (should (equal (plist-get id :name) "gascity.el/gastown.furiosa"))
    (should (equal (plist-get id :session-name) "tm"))
    (should (equal (plist-get id :work-dir) "/wd"))
    (should (equal (plist-get id :socket) "sock"))
    (should (eq (plist-get id :running) t))))

(ert-deftest gascity-test-session-name-prefers-agent-name ()
  "The qualified `agent_name' is preferred over the volatile `name'.
For non-active sessions gc sets `name' to the raw tmux id, so display
and joins must use `agent_name'."
  (should (equal (gascity-session-list--name
                  '((name . "gastown__polecat-bl-xyz")
                    (agent_name . "gascity.el/gastown.nux")))
                 "gascity.el/gastown.nux"))
  (should (equal (gascity-session-list--name '((name . "rig/agent")))
                 "rig/agent")))

(ert-deftest gascity-test-session-map-joins-on-agent-name ()
  "The status<->session join keys on `agent_name', surviving a volatile name."
  (let ((smap (gascity-status--session-map
               (vector '((name . "gastown__polecat-bl-xyz")
                         (agent_name . "gascity.el/gastown.nux")
                         (work_dir . "/wd/nux") (session_name . "tm-nux"))))))
    ;; Join on the qualified name (what a status agent's qualified_name is),
    ;; not the raw tmux id in `name'.
    (should (equal (alist-get 'work_dir (gethash "gascity.el/gastown.nux" smap))
                   "/wd/nux"))
    (should (null (gethash "gastown__polecat-bl-xyz" smap)))))

(ert-deftest gascity-test-convoy-entry ()
  "A convoy entry renders progress as closed/total and ids by bead id."
  (let* ((c '((id . "bs-0q2z") (title . "x") (status . "open")
              (progress . ((closed . 1) (total . 3)))))
         (entry (gascity-convoy-list--entry c)))
    (should (equal (car entry) "bs-0q2z"))
    (should (equal (gascity-test--plain-cols entry)
                   '("bs-0q2z" "x" "open" "1/3")))))

(ert-deftest gascity-test-dolt-entry ()
  "A Dolt entry lays out name, commits, and open beads."
  (should (equal (gascity-test--plain-cols
                  (gascity-dolt-list--entry
                   '((name . "beads") (commits . 42) (open_beads . 7))))
                 '("beads" "42" "7"))))

;;; Status tree assembly

(ert-deftest gascity-test-status-tree ()
  "City vs rig agents are partitioned by qualified name."
  (let ((mayor '((name . "mayor") (qualified_name . "gastown.mayor")
                 (scope . "city") (running . t)))
        (furiosa '((name . "furiosa")
                   (qualified_name . "gascity.el/gastown.furiosa")
                   (scope . "rig") (running . t))))
    (should (gascity-status--city-agent-p mayor))
    (should-not (gascity-status--city-agent-p furiosa))
    (should (equal (mapcar (lambda (a) (alist-get 'name a))
                           (gascity-status--rig-agents
                            "gascity.el" (vector mayor furiosa)))
                   '("furiosa")))))

(ert-deftest gascity-test-status-agent-plist-join ()
  "An agent is joined to its session for work-dir, tmux name, and socket."
  (let* ((furiosa '((name . "furiosa")
                    (qualified_name . "gascity.el/gastown.furiosa")
                    (running . t)))
         (smap (gascity-status--session-map
                (vector '((name . "gascity.el/gastown.furiosa")
                          (work_dir . "/wd") (session_name . "tm")))))
         (plist (gascity-status--agent-plist furiosa "gascity.el" smap "sock")))
    (should (equal (plist-get plist :work-dir) "/wd"))
    (should (equal (plist-get plist :session-name) "tm"))
    (should (equal (plist-get plist :socket) "sock"))
    (should (eq (plist-get plist :running) t))))

(ert-deftest gascity-test-status-sessions-note ()
  "A sessions-load hint appears only when that load is not ready.
Without it, a failed/pending session load degrades silently — agent rows
lose `work_dir'/`session_name', so `d'/`t' no-op with no explanation."
  (should (null (gascity-status--sessions-note-vnode 'ready nil)))
  (should (null (gascity-status--sessions-note-vnode nil nil)))
  (should (gascity-status--sessions-note-vnode 'error "boom"))
  (should (gascity-status--sessions-note-vnode 'pending nil)))

;;; tmux socket resolution

(ert-deftest gascity-test-resolve-tmux-socket ()
  "The override wins; otherwise the city name is the socket."
  (let ((gascity-tmux-socket "override"))
    (should (equal (gascity-resolve-tmux-socket "city") "override")))
  (let ((gascity-tmux-socket nil))
    (should (equal (gascity-resolve-tmux-socket "bright-lights") "bright-lights"))))

(ert-deftest gascity-test-terminal-socket-args ()
  "A real socket yields -L NAME; nil/empty/\"default\" yield nothing."
  (should (equal (gascity-terminal--socket-args "bright-lights")
                 '("-L" "bright-lights")))
  (should (null (gascity-terminal--socket-args "default")))
  (should (null (gascity-terminal--socket-args "")))
  (should (null (gascity-terminal--socket-args nil))))

(ert-deftest gascity-test-terminal-pane-cwd ()
  "The pane-cwd query returns the trimmed path, passing the socket; nil on miss."
  (should (null (gascity-terminal-pane-cwd "")))
  (should (null (gascity-terminal-pane-cwd nil)))
  ;; Success: trimmed stdout is the path, with `-L SOCKET' in the argv.
  (let (seen-args)
    (cl-letf (((symbol-function 'call-process)
               (lambda (_prog _in buf _disp &rest args)
                 (setq seen-args args)
                 (when (eq buf t) (insert "/live/wd\n"))
                 0)))
      (should (equal (gascity-terminal-pane-cwd "tm" "sock") "/live/wd"))
      (should (equal seen-args
                     '("-L" "sock" "display-message" "-t" "tm"
                       "-p" "#{pane_current_path}")))))
  ;; A missing session (non-zero exit) yields nil.
  (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1)))
    (should (null (gascity-terminal-pane-cwd "gone"))))
  ;; An empty pane path yields nil.
  (cl-letf (((symbol-function 'call-process)
             (lambda (_prog _in buf _disp &rest _)
               (when (eq buf t) (insert "   \n"))
               0)))
    (should (null (gascity-terminal-pane-cwd "tm")))))

(ert-deftest gascity-test-agent-dired-prefers-recorded-work-dir ()
  "A recorded `:work-dir' is used directly, without a tmux pane query."
  (let (opened)
    (cl-letf (((symbol-function 'dired) (lambda (d) (setq opened d)))
              ((symbol-function 'file-directory-p) (lambda (_) t))
              ((symbol-function 'gascity-terminal-pane-cwd)
               (lambda (&rest _) (error "pane cwd must not be queried"))))
      (gascity-agent-dired '(:name "a" :work-dir "/wd" :session-name "tm"))
      (should (equal opened "/wd")))))

(ert-deftest gascity-test-agent-dired-falls-back-to-pane-cwd ()
  "With no recorded work-dir, dired falls back to the live tmux pane cwd."
  (let (opened pane-args)
    (cl-letf (((symbol-function 'dired) (lambda (d) (setq opened d)))
              ((symbol-function 'file-directory-p) (lambda (_) t))
              ((symbol-function 'gascity-terminal-pane-cwd)
               (lambda (session socket)
                 (setq pane-args (list session socket))
                 "/live/pane")))
      (gascity-agent-dired '(:name "a" :work-dir "" :session-name "tm" :socket "sock"))
      (should (equal opened "/live/pane"))
      (should (equal pane-args '("tm" "sock"))))))

(ert-deftest gascity-test-agent-dired-errors-when-unresolvable ()
  "With neither a recorded nor a live working directory, signal a `user-error'."
  (cl-letf (((symbol-function 'gascity-terminal-pane-cwd) (lambda (&rest _) nil)))
    (should-error (gascity-agent-dired '(:name "a" :session-name "tm"))
                  :type 'user-error)))

;;; ============================================================
;;; Mutating commands (P1 — command dispatch)
;;; ============================================================

(ert-deftest gascity-test-mutate-command-lines ()
  "Mutating classes derive positional `gc' lines with `--json' OFF.
Actions report from gc's exit status, so an exit-0 command with empty or
JSONL output never mis-reads as a failure."
  (should (equal (gascity-command-line (gascity-command-rig-suspend :name "gascity.el"))
                 '("gc" "rig" "suspend" "gascity.el")))
  (should (equal (gascity-command-line (gascity-command-rig-resume :name "gascity.el"))
                 '("gc" "rig" "resume" "gascity.el")))
  (should (equal (gascity-command-line (gascity-command-rig-restart :name "r"))
                 '("gc" "rig" "restart" "r")))
  (should (equal (gascity-command-line
                  (gascity-command-session-nudge :target "mayor" :message "hi there"))
                 '("gc" "session" "nudge" "mayor" "hi there")))
  (should (equal (gascity-command-line (gascity-command-session-suspend :target "rig/agent"))
                 '("gc" "session" "suspend" "rig/agent")))
  (should (equal (gascity-command-line (gascity-command-session-kill :target "rig/agent"))
                 '("gc" "session" "kill" "rig/agent")))
  (should (equal (gascity-command-line (gascity-command-session-wake :target "rig/agent"))
                 '("gc" "session" "wake" "rig/agent")))
  (should (equal (gascity-command-line (gascity-command-order-run :name "patrol"))
                 '("gc" "order" "run" "patrol")))
  ;; No action command emits --json.
  (dolist (cmd (list (gascity-command-rig-suspend :name "x")
                     (gascity-command-session-nudge :target "x" :message "y")
                     (gascity-command-order-run :name "x")
                     (gascity-command-sling :target "t" :arg "a")))
    (should-not (member "--json" (gascity-command-line cmd)))))

(ert-deftest gascity-test-lifecycle-command-lines ()
  "City lifecycle commands stream (no --json); stop honours --force."
  (should (equal (gascity-command-line (gascity-command-start)) '("gc" "start")))
  (should (equal (gascity-command-line (gascity-command-stop)) '("gc" "stop")))
  (should (equal (gascity-command-line (gascity-command-stop :force t))
                 '("gc" "stop" "--force")))
  (should-not (member "--json" (gascity-command-line (gascity-command-start)))))

(ert-deftest gascity-test-sling-command-line ()
  "Sling emits target/arg positionals first, then its flags (no --json)."
  (let ((line (gascity-command-line
               (gascity-command-sling :target "mayor" :arg "gce-1"
                                      :formula t :nudge t))))
    (should (equal (cl-subseq line 0 4) '("gc" "sling" "mayor" "gce-1")))
    (should (member "--formula" line))
    (should (member "--nudge" line))
    (should-not (member "--json" line))
    (should-not (member "--dry-run" line)))
  (should (equal (gascity-command-line (gascity-command-sling :target "t" :arg "x"))
                 '("gc" "sling" "t" "x")))
  (should (equal (gascity-command-line
                  (gascity-command-sling :target "t" :arg "x" :dry-run t))
                 '("gc" "sling" "t" "x" "--dry-run"))))

(ert-deftest gascity-test-mutate-subcommand-derivation ()
  "Subcommands derive from the mutating class names."
  (should (equal (gascity-command-subcommand (gascity-command-rig-suspend)) "rig suspend"))
  (should (equal (gascity-command-subcommand (gascity-command-session-nudge)) "session nudge"))
  (should (equal (gascity-command-subcommand (gascity-command-order-run)) "order run"))
  (should (equal (gascity-command-subcommand (gascity-command-sling)) "sling")))

(ert-deftest gascity-test-mutate-validation ()
  "Required positional arguments are enforced before execution."
  (should (gascity-command-validate (gascity-command-session-nudge :target "x")))
  (should (gascity-command-validate (gascity-command-session-nudge :message "y")))
  (should-not (gascity-command-validate
               (gascity-command-session-nudge :target "x" :message "y")))
  (should (gascity-command-validate (gascity-command-session-kill)))
  (should-not (gascity-command-validate (gascity-command-session-kill :target "x")))
  (should (gascity-command-validate (gascity-command-sling :target "x")))
  (should-not (gascity-command-validate (gascity-command-sling :target "x" :arg "y")))
  (should (gascity-command-validate (gascity-command-order-run))))

(ert-deftest gascity-test-action-summarize ()
  "A mutation result is summarised to one human line."
  (should (equal (gascity-action--summarize "suspended\nmore") "suspended"))
  (should (equal (gascity-action--summarize "   ") "done"))
  (should (equal (gascity-action--summarize '((message . "routed bead"))) "routed bead"))
  (should (equal (gascity-action--summarize '((ok . t))) "ok"))
  (should (equal (gascity-action--summarize '((ok))) "failed"))
  (should (equal (gascity-action--summarize nil) "done")))

(ert-deftest gascity-test-action-error-detail ()
  "Error detail prefers gc's stderr, falling back to the message."
  (should (equal (gascity-action--error-detail
                  '(gascity-command-error "msg" :command "c" :stderr "  rig not found  "))
                 "rig not found"))
  (should (equal (gascity-action--error-detail
                  '(gascity-command-error "the message" :command "c" :stderr ""))
                 "the message")))

(ert-deftest gascity-test-action-routes-through-act ()
  "`execute-interactive' on an action command delegates to `gascity-command-act'."
  (let ((seen nil)
        (cmd (gascity-command-rig-suspend :name "x")))
    (cl-letf (((symbol-function 'gascity-command-act)
               (lambda (c) (setq seen c) 'stub-result)))
      (should (eq (gascity-command-execute-interactive cmd) 'stub-result))
      (should (eq seen cmd)))))

(ert-deftest gascity-test-act-reports-success ()
  "`gascity-command-act' returns the parsed result on success (executor stubbed)."
  (cl-letf (((symbol-function 'gascity-command-execute)
             (lambda (command)
               (gascity-command-execution
                :command command :exit-code 0
                :result "Suspended rig x"))))
    (should (equal (gascity-command-act (gascity-command-rig-suspend :name "x"))
                   "Suspended rig x"))))

(ert-deftest gascity-test-act-surfaces-command-error ()
  "A `gascity-command-error' becomes a `user-error' carrying gc's stderr."
  (cl-letf (((symbol-function 'gascity-command-execute)
             (lambda (_command)
               (signal 'gascity-command-error
                       (list "Command failed" :command "gc rig suspend x"
                             :exit-code 1 :stdout "" :stderr "rig not found")))))
    (let ((err (should-error (gascity-command-act (gascity-command-rig-suspend :name "x"))
                             :type 'user-error)))
      (should (string-match-p "rig not found" (error-message-string err))))))

(ert-deftest gascity-test-act-surfaces-validation-error ()
  "A missing required argument fails locally as a `user-error' (no gc call)."
  (let ((err (should-error (gascity-command-act (gascity-command-order-run))
                           :type 'user-error)))
    (should (string-match-p "order name is required" (error-message-string err)))))

;;; P4 — detail-view command lines (peek / drain)

(ert-deftest gascity-test-peek-command-line ()
  "Session peek captures plain text (no --json) with target + lines."
  (should (equal (gascity-command-line (gascity-command-session-peek :target "rig/agent"))
                 '("gc" "session" "peek" "rig/agent" "--lines" "50")))
  (should (equal (gascity-command-line
                  (gascity-command-session-peek :target "a" :lines "20"))
                 '("gc" "session" "peek" "a" "--lines" "20")))
  (should-not (member "--json"
                      (gascity-command-line (gascity-command-session-peek :target "a"))))
  (should (equal (gascity-command-subcommand (gascity-command-session-peek))
                 "session peek")))

(ert-deftest gascity-test-drain-command-line ()
  "Runtime drain is a positional mutation (no --json)."
  (should (equal (gascity-command-line (gascity-command-runtime-drain :target "rig/agent"))
                 '("gc" "runtime" "drain" "rig/agent")))
  (should-not (member "--json"
                      (gascity-command-line (gascity-command-runtime-drain :target "x"))))
  (should (equal (gascity-command-subcommand (gascity-command-runtime-drain))
                 "runtime drain")))

(ert-deftest gascity-test-peek-drain-validation ()
  "Peek and drain require a session target before gc is invoked."
  (should (gascity-command-validate (gascity-command-session-peek)))
  (should-not (gascity-command-validate (gascity-command-session-peek :target "x")))
  (should (gascity-command-validate (gascity-command-runtime-drain)))
  (should-not (gascity-command-validate (gascity-command-runtime-drain :target "x"))))

;;; P4 — detail-view data shaping (pure)

(ert-deftest gascity-test-section-beads ()
  "Bead payloads decode from a bare array or an {issues} wrapper."
  (should (equal (gascity-section-beads [((id . "a")) ((id . "b"))])
                 '(((id . "a")) ((id . "b")))))
  (should (equal (gascity-section-beads '((issues . [((id . "c"))])))
                 '(((id . "c")))))
  (should (null (gascity-section-beads []))))

;;; Bead-UI delegation / store scoping (DESIGN.md §4.3, §9.1)

(ert-deftest gascity-test-beads-id-prefix ()
  "A bead id's store prefix is the text before the first hyphen."
  (should (equal (gascity-beads--id-prefix "gce-afq") "gce"))
  (should (equal (gascity-beads--id-prefix "bl-1jp") "bl"))
  (should (equal (gascity-beads--id-prefix "exc-12ab") "gxc"))
  (should (null (gascity-beads--id-prefix "noprefix")))
  (should (null (gascity-beads--id-prefix "")))
  (should (null (gascity-beads--id-prefix nil))))

(ert-deftest gascity-test-beads-rig-path-from-alist ()
  "A rig alist's store directory is its `path', a directory name."
  (should (equal (gascity-beads--rig-path '((name . "gascity.el")
                                            (path . "/home/x/gascity.el")
                                            (prefix . "gce")))
                 "/home/x/gascity.el/"))
  (should (null (gascity-beads--rig-path '((name . "x") (path)))))
  (should (null (gascity-beads--rig-path '((name . "x") (path . ""))))))

(ert-deftest gascity-test-beads-rig-path-from-name ()
  "A rig name resolves to its `path' via the rig list."
  (cl-letf (((symbol-function 'gascity-command-rig-list!)
             (lambda (&rest _)
               '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))
                          ((name . "bright-lights") (path . "/r/bl") (prefix . "bl"))])))))
    (should (equal (gascity-beads--rig-path "gascity.el") "/r/gce/"))
    (should (equal (gascity-beads--rig-path "bright-lights") "/r/bl/"))
    (should (null (gascity-beads--rig-path "nope")))))

(ert-deftest gascity-test-beads-bead-path ()
  "A bead id maps to the store of the rig whose prefix it carries."
  (cl-letf (((symbol-function 'gascity-command-rig-list!)
             (lambda (&rest _)
               '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))
                          ((name . "bright-lights") (path . "/r/bl") (prefix . "bl"))])))))
    (should (equal (gascity-beads--bead-path "gce-afq") "/r/gce/"))
    (should (equal (gascity-beads--bead-path "bl-1") "/r/bl/"))
    (should (null (gascity-beads--bead-path "zz-9")))       ; unknown prefix
    (should (null (gascity-beads--bead-path "noprefix")))))  ; no prefix at all

(ert-deftest gascity-test-bead-show-scopes-default-directory ()
  "`gascity-bead-show' binds `default-directory' to the bead's rig store."
  (let (seen-dir seen-id)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))]))))
              ((symbol-function 'beads-show)
               (lambda (id) (setq seen-id id seen-dir default-directory))))
      ;; Prefix resolution picks the owning rig's store.
      (gascity-bead-show "gce-afq")
      (should (equal seen-id "gce-afq"))
      (should (equal seen-dir "/r/gce/"))
      ;; An explicit directory wins over prefix resolution.
      (gascity-bead-show "gce-afq" "/explicit")
      (should (equal seen-dir "/explicit/"))
      ;; An unresolvable prefix degrades to the ambient directory.
      (let ((default-directory "/ambient/"))
        (gascity-bead-show "zz-9")
        (should (equal seen-dir "/ambient/"))))))

(ert-deftest gascity-test-bead-show-rejects-empty ()
  "`gascity-bead-show' refuses a nil or empty id before touching beads.el."
  (should-error (gascity-bead-show nil) :type 'user-error)
  (should-error (gascity-bead-show "") :type 'user-error))

(ert-deftest gascity-test-rig-beads-scopes-default-directory ()
  "`gascity-rig-beads' opens the board with `default-directory' at the store."
  (let (seen-dir)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))]))))
              ((symbol-function 'beads-dashboard)
               (lambda () (setq seen-dir default-directory))))
      (gascity-rig-beads "gascity.el")
      (should (equal seen-dir "/r/gce/"))
      ;; A rig alist works directly, no rig-list lookup needed.
      (setq seen-dir nil)
      (gascity-rig-beads '((name . "x") (path . "/r/x") (prefix . "x")))
      (should (equal seen-dir "/r/x/")))))

(ert-deftest gascity-test-rig-beads-unresolved-errors ()
  "`gascity-rig-beads' errors when the rig's store cannot be resolved."
  (cl-letf (((symbol-function 'gascity-command-rig-list!)
             (lambda (&rest _) '((rigs . [])))))
    (should-error (gascity-rig-beads "ghost") :type 'user-error)))

(ert-deftest gascity-test-rig-db-for-prefix ()
  "The rig's Dolt database is matched on its bead prefix."
  (let ((dbs [((name . "hq")) ((name . "gce") (commits . 5)) ((name . "beads"))]))
    (should (equal (alist-get 'commits (gascity-rig--db-for-prefix dbs "gce")) 5))
    (should (null (gascity-rig--db-for-prefix dbs "nope")))
    (should (null (gascity-rig--db-for-prefix dbs nil)))
    (should (null (gascity-rig--db-for-prefix dbs "")))))

(ert-deftest gascity-test-rig-orders-filter ()
  "Only orders scoped to the rig are kept; city-wide (rig=nil) are dropped."
  (let ((orders [((name . "a") (rig . "gascity.el"))
                 ((name . "b") (rig))
                 ((name . "c") (rig . "other"))]))
    (should (equal (mapcar (lambda (o) (alist-get 'name o))
                           (gascity-rig--rig-orders orders "gascity.el"))
                   '("a")))))

(ert-deftest gascity-test-session-find ()
  "A session is found by qualified name, volatile name, or alias."
  (let ((sessions (vector '((agent_name . "gascity.el/gastown.furiosa") (state . "active"))
                          '((name . "raw-tmux-id") (alias . "rig/other")))))
    (should (equal (alist-get
                    'state (gascity-session--find sessions "gascity.el/gastown.furiosa"))
                   "active"))
    (should (gascity-session--find sessions "rig/other"))
    (should (null (gascity-session--find sessions "nobody")))))

(ert-deftest gascity-test-session-assignee-keys ()
  "Both the qualified name and the runtime session name are candidate keys.
Nils and empty strings are dropped; duplicates collapse."
  (should (equal (gascity-session--assignee-keys
                  '(:name "gascity.el/gastown.furiosa"
                          :session-name "gastown__polecat-bl-xyz"))
                 '("gascity.el/gastown.furiosa" "gastown__polecat-bl-xyz")))
  (should (equal (gascity-session--assignee-keys '(:name "a" :session-name "a")) '("a")))
  (should (equal (gascity-session--assignee-keys '(:name "a" :session-name "")) '("a")))
  (should (null (gascity-session--assignee-keys '(:name nil)))))

(ert-deftest gascity-test-session-bead-args ()
  "Per-key bead args filter server-side by assignee and scope to the rig."
  (should (equal (gascity-session--bead-args "k" "gascity.el")
                 '("bd" "list" "--assignee" "k" "--rig" "gascity.el"
                   "--status" "open,in_progress,blocked,deferred,closed"
                   "--sort" "updated" "--reverse" "--limit" "50")))
  ;; A nil rig drops the --rig scope.
  (should-not (member "--rig" (gascity-session--bead-args "k" nil))))

(ert-deftest gascity-test-session-combined-status ()
  "Combined bead status: pending if any pending; error only if all errored."
  (should (eq (gascity-session--combined-status '((:status pending) (:status ready)))
              'pending))
  (should (eq (gascity-session--combined-status '((:status error) (:status error)))
              'error))
  (should (eq (gascity-session--combined-status '((:status error) (:status ready)))
              'ready)))

(ert-deftest gascity-test-session-beads-merge-and-partition ()
  "Per-key bead lists merge (de-duped by id), then split into hook vs history."
  (let* ((from-runtime (list '((id . "x") (status . "in_progress"))))
         (from-qualified (list '((id . "y") (status . "closed"))
                               '((id . "x") (status . "in_progress")))) ; dup id
         (merged (gascity-session--merge-beads (list from-runtime from-qualified))))
    (should (equal (mapcar (lambda (b) (alist-get 'id b)) merged) '("x" "y")))
    (should (equal (mapcar (lambda (b) (alist-get 'id b))
                           (gascity-session--hook-beads merged))
                   '("x")))
    (should (equal (mapcar (lambda (b) (alist-get 'id b))
                           (gascity-session--history-beads merged))
                   '("y")))
    (should (= (length (gascity-session--history-beads
                        (list '((status . "open")) '((status . "open"))
                              '((status . "open")))
                        2))
               2))))

;;; Round-trip integration (acceptance) — needs a live gc + city

(ert-deftest gascity-test-status-round-trip ()
  "`(gascity-command-status!)' round-trips `gc status --json' to an alist."
  (skip-unless (executable-find gascity-executable))
  (let ((result (condition-case nil
                    (gascity-command-status!)
                  (gascity-error 'unavailable))))
    (when (eq result 'unavailable)
      (ert-skip "gc status did not succeed in this environment"))
    (should (consp result))
    (should (assq 'ok result))))

;;; Pagination

(ert-deftest gascity-test-paged-total-pages ()
  "Total pages is ceil(entries/size), and never below 1."
  (with-temp-buffer
    (setq gascity-tabulated--page-size 10)
    (setq gascity-tabulated--all-entries nil)
    (should (= (gascity-tabulated--total-pages) 1))
    (setq gascity-tabulated--all-entries (number-sequence 1 10))
    (should (= (gascity-tabulated--total-pages) 1))
    (setq gascity-tabulated--all-entries (number-sequence 1 11))
    (should (= (gascity-tabulated--total-pages) 2))
    (setq gascity-tabulated--all-entries (number-sequence 1 25))
    (should (= (gascity-tabulated--total-pages) 3))))

(ert-deftest gascity-test-paged-page-slice ()
  "Each page slices the right window; a page past the end is empty, not an error."
  (with-temp-buffer
    (setq gascity-tabulated--page-size 10
          gascity-tabulated--all-entries (number-sequence 1 25))
    (setq gascity-tabulated--current-page 1)
    (should (equal (gascity-tabulated--page-slice) (number-sequence 1 10)))
    (setq gascity-tabulated--current-page 2)
    (should (equal (gascity-tabulated--page-slice) (number-sequence 11 20)))
    (setq gascity-tabulated--current-page 3)
    (should (equal (gascity-tabulated--page-slice) (number-sequence 21 25)))
    (setq gascity-tabulated--current-page 4)
    (should (null (gascity-tabulated--page-slice)))))

(ert-deftest gascity-test-paged-effective-size ()
  "Effective size honours an explicit page size, else computes a positive one."
  (with-temp-buffer
    (setq gascity-tabulated--page-size 7)
    (should (= (gascity-tabulated--effective-page-size) 7))
    (setq gascity-tabulated--page-size nil)
    (should (>= (gascity-tabulated--effective-page-size) 1))))

;;; Filter predicates (client-side)

(ert-deftest gascity-test-rig-filter-match ()
  "Rig status filter matches the derived status label; nil matches every rig."
  (let ((run '((name . "a") (running . t)))
        (susp '((name . "b") (suspended . t)))
        (stop '((name . "c"))))
    (should (gascity-rig-list--match-p run nil))
    (should (gascity-rig-list--match-p run "running"))
    (should-not (gascity-rig-list--match-p run "suspended"))
    (should (gascity-rig-list--match-p susp "suspended"))
    (should (gascity-rig-list--match-p stop "stopped"))
    (should-not (gascity-rig-list--match-p stop "running"))))

(ert-deftest gascity-test-session-filter-match ()
  "Session rig filter is a case-insensitive substring; nil/empty match all."
  (let ((s '((rig . "gascity.el"))))
    (should (gascity-session-list--match-p s nil))
    (should (gascity-session-list--match-p s ""))
    (should (gascity-session-list--match-p s "gascity"))
    (should (gascity-session-list--match-p s "GASCITY"))
    (should-not (gascity-session-list--match-p s "guix"))))

(ert-deftest gascity-test-convoy-filter-match ()
  "Convoy status filter matches the `status' field exactly; nil matches all."
  (let ((c '((id . "x") (status . "open"))))
    (should (gascity-convoy-list--match-p c nil))
    (should (gascity-convoy-list--match-p c "open"))
    (should-not (gascity-convoy-list--match-p c "closed"))))

(ert-deftest gascity-test-mail-filter-match ()
  "Mail unread-only filter keeps unread messages; nil keeps all.
Unread is the negation of the v1 `read' boolean (gc decodes `false' to nil)."
  (let ((unread '((read . nil)))
        (seen '((read . t))))
    (should (gascity-mail-inbox--match-p unread nil))
    (should (gascity-mail-inbox--match-p seen nil))
    (should (gascity-mail-inbox--match-p unread t))
    (should-not (gascity-mail-inbox--match-p seen t))))

(ert-deftest gascity-test-mail-entry ()
  "A mail entry reads the v1 schema keys and marks unread rows.
`from'/`subject'/`created_at' (date-only) become the columns, the whole
message alist is the id, and a non-`read' message shows the ● marker."
  (let* ((message '((id . "msg-1") (from . "mayor/") (to . "gce/furiosa")
                    (subject . "Re: status") (body . "...")
                    (created_at . "2026-06-01T19:18:18Z") (read . nil)))
         (entry (gascity-mail-inbox--entry message)))
    (should (eq (car entry) message))
    (should (equal (gascity-test--plain-cols entry)
                   '("mayor/" "Re: status" "2026-06-01" "●"))))
  ;; A read message clears the marker.
  (should (equal (nth 3 (gascity-test--plain-cols
                         (gascity-mail-inbox--entry
                          '((from . "a") (subject . "s")
                            (created_at . "2026-06-01T00:00:00Z") (read . t)))))
                 "")))

(ert-deftest gascity-test-order-filter-match ()
  "Order filter ANDs enabled-only and exact type; nil/empty values match all."
  (let ((on '((enabled . t) (type . "schedule")))
        (off '((enabled) (type . "cooldown"))))
    (should (gascity-order-list--match-p on nil nil))
    (should (gascity-order-list--match-p on t nil))
    (should-not (gascity-order-list--match-p off t nil))
    (should (gascity-order-list--match-p on nil "schedule"))
    (should (gascity-order-list--match-p on t "schedule"))
    (should-not (gascity-order-list--match-p on nil "cooldown"))
    (should (gascity-order-list--match-p off nil ""))))

;;; Filter slots <-> command line

(ert-deftest gascity-test-client-filter-slots-do-not-leak ()
  "Client-side filter slots never reach the `gc' command line."
  (should (equal (gascity-command-line (gascity-command-rig-list :status "running"))
                 '("gc" "rig" "list" "--json")))
  (should (equal (gascity-command-line (gascity-command-convoy-list :status "open"))
                 '("gc" "convoy" "list" "--json")))
  (should (equal (gascity-command-line (gascity-command-mail-inbox :unread t))
                 '("gc" "mail" "inbox" "--json")))
  (should (equal (gascity-command-line
                  (gascity-command-order-list :enabled t :type "schedule"))
                 '("gc" "order" "list" "--json")))
  (should (equal (gascity-command-line (gascity-command-session-list :rig "gascity.el"))
                 '("gc" "session" "list" "--json"))))

(ert-deftest gascity-test-session-state-is-server-side ()
  "The session `--state' filter IS emitted (`gc session list' supports it)."
  (let ((line (gascity-command-line (gascity-command-session-list :state "active"))))
    (should (member "--state" line))
    (should (member "active" line))
    (should (member "--json" line)))
  (should (equal (gascity-command-line (gascity-command-session-list))
                 '("gc" "session" "list" "--json"))))

(provide 'gascity-test)
;;; gascity-test.el ends here
