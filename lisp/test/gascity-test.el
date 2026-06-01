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
  "Vector/timestamp/string/field helpers behave."
  (should (equal (gascity-tabulated--vector->list [1 2 3]) '(1 2 3)))
  (should (equal (gascity-tabulated--vector->list '(1 2)) '(1 2)))
  (should (equal (gascity-tabulated--format-timestamp "2026-06-01T19:18:18Z")
                 "2026-06-01"))
  (should (equal (gascity-tabulated--format-timestamp "") ""))
  (should (equal (gascity-tabulated--format-timestamp nil) ""))
  (should (equal (gascity-tabulated--str 42) "42"))
  (should (equal (gascity-tabulated--str nil) ""))
  (should (equal (gascity-tabulated--str t) "yes"))
  (should (equal (gascity-tabulated--field '((a . "") (b . "hit")) '(a b)) "hit"))
  (should (equal (gascity-tabulated--field '((a . "x")) '(z)) "")))

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

(provide 'gascity-test)
;;; gascity-test.el ends here
