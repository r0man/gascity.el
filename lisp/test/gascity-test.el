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

(defun gascity-test--vnode-text (vnode)
  "Concatenate the text content of VNODE's subtree, depth-first.
Containers join their children with a space — enough to assert what a
small hand-built vnode renders without mounting it in a buffer."
  (cond
   ((null vnode) "")
   ((vui-vnode-text-p vnode) (or (vui-vnode-text-content vnode) ""))
   ((vui-vnode-vstack-p vnode)
    (mapconcat #'gascity-test--vnode-text (vui-vnode-vstack-children vnode) " "))
   ((vui-vnode-hstack-p vnode)
    (mapconcat #'gascity-test--vnode-text (vui-vnode-hstack-children vnode) " "))
   ((vui-vnode-fragment-p vnode)
    (mapconcat #'gascity-test--vnode-text (vui-vnode-fragment-children vnode) " "))
   (t "")))

(defun gascity-test--agent (&rest initargs)
  "Build a `gascity-agent' from INITARGS (e.g. :name, :session-name, :socket).
A concise stand-in for the action object a real view builds and stamps."
  (apply #'make-instance 'gascity-agent initargs))

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
                 "2026-06-01 19:18"))
  (should (equal (gascity-tabulated--format-timestamp "") ""))
  (should (equal (gascity-tabulated--format-timestamp nil) ""))
  (should (equal (gascity-tabulated--str 42) "42"))
  (should (equal (gascity-tabulated--str nil) ""))
  (should (equal (gascity-tabulated--str t) "yes")))

(ert-deftest gascity-test-tabulated-format-timestamp ()
  "`--format-timestamp' keeps HH:MM so same-day recency is visible.
It reshapes the wall-clock as written (no parsing), so output is stable
regardless of the system clock or time zone."
  ;; `created_at' shape: UTC `Z' -> date + UTC time.
  (should (equal (gascity-tabulated--format-timestamp "2026-06-02T15:30:20Z")
                 "2026-06-02 15:30"))
  ;; `last_active' shape: a local UTC offset -> date + that local time
  ;; (the offset's own wall clock, not normalized to UTC).
  (should (equal (gascity-tabulated--format-timestamp "2026-06-02T17:35:41+02:00")
                 "2026-06-02 17:35"))
  ;; The point of the fix: two same-day instants now render distinctly.
  (should-not (equal (gascity-tabulated--format-timestamp "2026-06-02T09:03:00Z")
                     (gascity-tabulated--format-timestamp "2026-06-02T16:54:00Z")))
  ;; A timestamp with no seconds still yields HH:MM.
  (should (equal (gascity-tabulated--format-timestamp "2026-06-02T17:35")
                 "2026-06-02 17:35"))
  ;; A date-only value keeps the date (no spurious " 00:00").
  (should (equal (gascity-tabulated--format-timestamp "2026-06-02") "2026-06-02"))
  ;; Empty / nil -> empty string.
  (should (equal (gascity-tabulated--format-timestamp "") ""))
  (should (equal (gascity-tabulated--format-timestamp nil) ""))
  ;; An unrecognized shape falls back to the old bare date-prefix behavior.
  (should (equal (gascity-tabulated--format-timestamp "not-a-timestamp")
                 "not-a-time")))

;;; Tabulated column truncation (keeps rows aligned)

(ert-deftest gascity-test-tabulated-truncate-fits ()
  "A value at or under the width is returned unchanged (and coerced)."
  (should (equal (gascity-tabulated--truncate "short" 26) "short"))
  (should (equal (gascity-tabulated--truncate "" 5) ""))
  (should (equal (gascity-tabulated--truncate 42 5) "42"))
  ;; Exactly at the width is not truncated — no ellipsis.
  (should (equal (gascity-tabulated--truncate "0123456789" 10) "0123456789")))

(ert-deftest gascity-test-tabulated-truncate-overflow ()
  "An over-wide value is cut to the width with an ellipsis.
The full value is kept as a `help-echo' so it stays discoverable, and the
result never exceeds the column width (so later columns stay aligned)."
  (let* ((full "example-town-cl/gastown.furiosa") ; 31 columns wide
         (out (gascity-tabulated--truncate full 26)))
    (should (= (string-width out) 26))
    (should-not (equal (substring-no-properties out) full))
    (should (string-prefix-p "example-town-cl/gastown"
                             (substring-no-properties out)))
    ;; Ends in an ellipsis, not a hard cut.
    (should (string-suffix-p (truncate-string-ellipsis)
                             (substring-no-properties out)))
    ;; Full value recoverable via help-echo.
    (should (equal (get-text-property 0 'help-echo out) full))))

(ert-deftest gascity-test-tabulated-truncate-row ()
  "Over-wide non-last cells are truncated to their column widths.
Short cells and the last column are left intact (the last column has
nothing after it to misalign), and the input vector is never mutated.
Drives the two formats the dogfood pass flagged: sessions (Agent 26) and
orders (Order 28)."
  (with-temp-buffer
    (setq-local tabulated-list-format
                [("Agent" 26 t) ("Rig" 14 t) ("State" 9 t)
                 ("Provider" 9 t) ("Working dir" 40 t)])
    (let* ((cols (vector "example-town-cl/gastown.furiosa" "gascity.el"
                         "active" "claude"
                         "/home/roman/some/very/long/working/directory/that/overflows"))
           (orig (copy-sequence cols))
           (out (gascity-tabulated--truncate-row cols)))
      (should (= (string-width (aref out 0)) 26))   ; Agent: truncated to 26
      (should (equal (aref out 1) "gascity.el"))    ; Rig (fits 14): unchanged
      (should (equal (aref out 4) (aref orig 4)))    ; Working dir (last): intact
      (should (equal cols orig))))                   ; input not mutated
  (with-temp-buffer
    (setq-local tabulated-list-format
                [("Order" 28 t) ("Rig" 14 t) ("Type" 8 t)
                 ("Trigger" 10 t) ("Schedule" 12 t) ("On" 3 nil)])
    (let ((out (gascity-tabulated--truncate-row
                (vector "cross-rig-deps:rig:example-town-cl" "rig" "cron"
                        "schedule" "5m" "●"))))
      (should (= (string-width (aref out 0)) 28))    ; Order: truncated to 28
      (should (equal (aref out 5) "●")))))           ; marker (last): intact

(ert-deftest gascity-test-tabulated-refresh-display-aligns ()
  "Rendering a page lines later columns up regardless of cell length.
Regression for the dogfood overflow (gce-l5x): a long Agent name must not
push the Rig column to the right of where a short name leaves it.  Walks
the real `gascity-tabulated--refresh-display' path into a rendered buffer
and compares the in-line offset of the Rig value on a long-name row and a
short-name row."
  (with-temp-buffer
    (tabulated-list-mode)
    (setq-local tabulated-list-format
                [("Agent" 26 t) ("Rig" 14 t) ("State" 9 t)
                 ("Provider" 9 t) ("Working dir" 40 t)]
                tabulated-list-padding 1)
    (tabulated-list-init-header)
    (setq gascity-tabulated--all-entries
          (list (list 'long (vector "example-town-cl/gastown.furiosa"
                                    "rig-a" "active" "claude" "/wd/a"))
                (list 'short (vector "x" "rig-b" "active" "claude" "/wd/b")))
          gascity-tabulated--current-page 1
          gascity-tabulated--page-size 100
          gascity-tabulated--base-name "Sessions")
    (gascity-tabulated--refresh-display)
    (let ((rig-offset
           (lambda (rig)
             (goto-char (point-min))
             (search-forward rig)
             (- (match-beginning 0) (line-beginning-position)))))
      ;; Same column on both rows -> the long name did not shift the layout.
      (should (= (funcall rig-offset "rig-a") (funcall rig-offset "rig-b"))))
    ;; Row ids are preserved verbatim, so RET/d/t still act on the full data.
    (should (equal (mapcar #'car tabulated-list-entries) '(long short)))))

(ert-deftest gascity-test-tabulated-refresh-reports-clean-error ()
  "A `gc' failure during refresh echoes one clean line, not the condition plist.
Regression for gce-dfe: the refresh path rendered the caught error with
`error-message-string', which dumps a `gascity-command-error''s entire
data plist (:command, :exit-code, :stdout, :stderr) into the echo area.
It must instead surface just the detail via `gascity-error-detail', and
still degrade the list to empty rows."
  (with-temp-buffer
    (tabulated-list-mode)
    (setq-local tabulated-list-format [("Col" 10 t)])
    (tabulated-list-init-header)
    (let (msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (gascity-tabulated--refresh
         "Things"
         (lambda ()
           ;; Mirrors the observed missing-binary failure: empty stderr, so
           ;; the detail falls back to the (clean) message.
           (signal 'gascity-command-error
                   (list "Cannot run gc: No such file or directory"
                         :command "gc rig list --json"
                         :exit-code nil :stdout "" :stderr "")))))
      (let ((reported (seq-find (lambda (m) (string-prefix-p "gascity:" m)) msgs)))
        (should (equal reported
                       "gascity: Cannot run gc: No such file or directory"))
        ;; None of the condition-internal plist keys leak into the message.
        (should-not (string-match-p ":command\\|:exit-code\\|:stdout\\|:stderr"
                                    reported))))
    ;; The list degrades gracefully to no rows.
    (should (null tabulated-list-entries))))

;;; Tabulated entry builders

(ert-deftest gascity-test-rig-entry ()
  "A rig entry carries the typed `gascity-rig' as its id and lays out columns."
  (let* ((rig (gascity-domain-decode
               'gascity-rig
               '((name . "gascity.el") (prefix . "gce") (running . t) (suspended)
                 (default_branch . "main") (beads . "initialized"))))
         (entry (gascity-rig-list--entry rig)))
    (should (eq (car entry) rig))
    (should (gascity-rig-p (car entry)))
    (should (equal (gascity-test--plain-cols entry)
                   '("gascity.el" "gce" "running" "main" "initialized")))))

(defun gascity-test--rig-list-buffer ()
  "Render a rig-list buffer with an HQ row and a plain rig row.
The HQ row (`bright-lights') carries `hq', as `gc rig list' marks the city
HQ; the plain row (`gascity.el') does not.  Leaves the buffer current."
  (gascity-rig-list-mode)
  (setq tabulated-list-entries
        (list (gascity-rig-list--entry
               (gascity-domain-decode 'gascity-rig
                                      '((name . "bright-lights") (prefix . "bl")
                                        (hq . t))))
              (gascity-rig-list--entry
               (gascity-domain-decode 'gascity-rig
                                      '((name . "gascity.el") (prefix . "gce")
                                        (running . t) (default_branch . "main"))))))
  (tabulated-list-print))

(defun gascity-test--goto-rig-row (name)
  "Move point onto the rig-list row whose name cell is NAME."
  (goto-char (point-min))
  (search-forward name)
  (beginning-of-line))

(ert-deftest gascity-test-rig-at-point-hq-p ()
  "The HQ predicate is true only on a rig row that carries `hq'.
`gc rig list' lists the city HQ (with `hq') even though it is not a
`city.toml' rig, so the rig dashboard must distinguish it from a real rig."
  (with-temp-buffer
    (gascity-test--rig-list-buffer)
    (gascity-test--goto-rig-row "bright-lights")
    (should (gascity-rig-at-point-hq-p))
    (gascity-test--goto-rig-row "gascity.el")
    (should-not (gascity-rig-at-point-hq-p)))
  ;; Outside a tabulated list there is no rig alist, hence no `hq' to read.
  (with-temp-buffer
    (should-not (gascity-rig-at-point-hq-p))))

(ert-deftest gascity-test-rig-dashboard-at-point-refuses-hq ()
  "RET on the HQ row signals a user-error and never mounts a dashboard.
Regression for gce-6bq: the HQ has no rig dashboard (`gc rig status'
rejects it), so opening one only produced an un-retryable error screen."
  (with-temp-buffer
    (gascity-test--rig-list-buffer)
    (gascity-test--goto-rig-row "bright-lights")
    (let (opened)
      (cl-letf (((symbol-function 'gascity-rig-dashboard)
                 (lambda (rig) (push rig opened))))
        (should-error (gascity-rig-dashboard-at-point) :type 'user-error)
        (should (null opened))))))

(ert-deftest gascity-test-rig-dashboard-at-point-opens-plain-rig ()
  "RET on a non-HQ rig row opens its dashboard with the rig name.
The HQ guard must not disturb the normal path: a real rig still routes to
`gascity-rig-dashboard'."
  (with-temp-buffer
    (gascity-test--rig-list-buffer)
    (gascity-test--goto-rig-row "gascity.el")
    (let (opened)
      (cl-letf (((symbol-function 'gascity-rig-dashboard)
                 (lambda (rig) (push rig opened))))
        (gascity-rig-dashboard-at-point)
        (should (equal opened '("gascity.el")))))))

;;; gce-4hk — RET on an agent attaches its terminal; `i' opens its info view

(defun gascity-test--with-agent-at-point (thunk)
  "Call THUNK in a temp buffer with an agent plist as the `gascity-agent' prop.
This stands in for an agent row in the status or rig dashboard, where the
action keys resolve the subject via `gascity-agent-at-point'."
  (with-temp-buffer
    (insert (propertize "agent-row"
                        'gascity-agent
                        (gascity-test--agent :name "rig/agent" :session-name "tm")))
    (goto-char (point-min))
    (funcall thunk)))

(ert-deftest gascity-test-status-activate-agent-attaches-terminal ()
  "RET on an agent in the status dashboard attaches its terminal, not the info view.
Primary action is the tmux attach (`gascity-tmux-at-point'); the detail/info
view moves to `i' (`gascity-polecat-detail-at-point') — gce-4hk."
  (gascity-test--with-agent-at-point
   (lambda ()
     (let (tmux info)
       (cl-letf (((symbol-function 'gascity-agent-attach-tmux) (lambda (_a) (setq tmux t)))
                 ((symbol-function 'gascity-polecat-detail-at-point)
                  (lambda () (setq info t))))
         (gascity-status-activate)
         (should tmux)
         (should-not info)))))
  ;; `i' opens the info view; RET (via activate) and `t' both attach.
  (should (eq (keymap-lookup gascity-dashboard-mode-map "i")
              #'gascity-polecat-detail-at-point))
  (should (eq (keymap-lookup gascity-dashboard-mode-map "t")
              #'gascity-tmux-at-point))
  (should (eq (keymap-lookup gascity-dashboard-mode-map "RET")
              #'gascity-status-activate)))

(ert-deftest gascity-test-rig-dashboard-activate-agent-attaches-terminal ()
  "RET on an agent in the rig dashboard attaches its terminal, not the info view.
A bead at point still opens in beads.el; only the agent branch changes to the
tmux attach, with the detail/info view on `i' — gce-4hk."
  (gascity-test--with-agent-at-point
   (lambda ()
     (let (tmux info)
       (cl-letf (((symbol-function 'gascity-agent-attach-tmux) (lambda (_a) (setq tmux t)))
                 ((symbol-function 'gascity-polecat-detail-at-point)
                  (lambda () (setq info t))))
         (gascity-rig-dashboard-activate)
         (should tmux)
         (should-not info)))))
  (should (eq (keymap-lookup gascity-rig-dashboard-mode-map "i")
              #'gascity-polecat-detail-at-point))
  (should (eq (keymap-lookup gascity-rig-dashboard-mode-map "t")
              #'gascity-tmux-at-point))
  (should (eq (keymap-lookup gascity-rig-dashboard-mode-map "RET")
              #'gascity-rig-dashboard-activate)))

(ert-deftest gascity-test-session-list-ret-attaches-terminal ()
  "In the session list RET attaches the agent's terminal; `i' opens its detail.
RET is bound directly to the tmux attach (a synonym for `t'), and the
session/polecat detail view — the old RET target — moves to `i' (gce-4hk)."
  (should (eq (keymap-lookup gascity-session-list-mode-map "RET")
              #'gascity-tmux-at-point))
  (should (eq (keymap-lookup gascity-session-list-mode-map "t")
              #'gascity-tmux-at-point))
  (should (eq (keymap-lookup gascity-session-list-mode-map "i")
              #'gascity-polecat-detail-at-point)))

(ert-deftest gascity-test-rig-list-store-column-header ()
  "The rig list's bead-store column is headed \"Store\", not \"Beads\".
The cell renders `gc rig list''s `beads' field — a store-STATUS string
\(\"initialized\") for every rig, never a count — so a \"Beads\" header
implied a count it never showed.  Pin the status-accurate label, and pin
the faithful rendering of the underlying value alongside it (gce-79f)."
  (with-temp-buffer
    (gascity-rig-list-mode)
    (let ((headers (mapcar #'car (append tabulated-list-format nil))))
      (should (member "Store" headers))
      (should-not (member "Beads" headers)))
    ;; The fifth column still faithfully shows the store-status value.
    (should (equal (nth 4 (gascity-test--plain-cols
                           (gascity-rig-list--entry
                            (gascity-domain-decode
                             'gascity-rig
                             '((name . "gascity.el") (prefix . "gce") (running . t)
                               (default_branch . "main") (beads . "initialized"))))))
                   "initialized"))))

(ert-deftest gascity-test-session-entry-id-is-agent ()
  "A session entry's id is the typed agent action object, with the socket."
  (let* ((s (gascity-domain-decode
             'gascity-session
             '((agent_name . "gascity.el/gastown.furiosa") (rig . "gascity.el")
               (state . "active") (provider . "claude")
               (work_dir . "/wd") (session_name . "tm"))))
         (id (car (gascity-session-list--entry s "sock"))))
    (should (gascity-agent-p id))
    (should (equal (gascity-agent-name id) "gascity.el/gastown.furiosa"))
    (should (equal (gascity-agent-session-name id) "tm"))
    (should (equal (gascity-agent-work-dir id) "/wd"))
    (should (equal (gascity-agent-socket id) "sock"))
    (should (eq (gascity-agent-running id) t))))

(ert-deftest gascity-test-session-name-prefers-agent-name ()
  "The qualified `agent_name' is preferred over the volatile `name'.
For non-active sessions gc sets `name' to the raw tmux id, so display
and joins must use `agent_name'."
  (should (equal (gascity-session-qualified-name
                  (gascity-domain-decode
                   'gascity-session
                   '((name . "gastown__polecat-bl-xyz")
                     (agent_name . "gascity.el/gastown.nux"))))
                 "gascity.el/gastown.nux"))
  (should (equal (gascity-session-qualified-name
                  (gascity-domain-decode 'gascity-session '((name . "rig/agent"))))
                 "rig/agent")))

(ert-deftest gascity-test-session-map-joins-on-agent-name ()
  "The status<->session join keys on `agent_name', surviving a volatile name."
  (let ((smap (gascity-status--session-map
               (vector '((name . "gastown__polecat-bl-xyz")
                         (agent_name . "gascity.el/gastown.nux")
                         (work_dir . "/wd/nux") (session_name . "tm-nux"))))))
    ;; Join on the qualified name (what a status agent's qualified_name is),
    ;; not the raw tmux id in `name'.  The map stores typed `gascity-session's.
    (should (equal (gascity-session-work-dir (gethash "gascity.el/gastown.nux" smap))
                   "/wd/nux"))
    (should (null (gethash "gastown__polecat-bl-xyz" smap)))))

(ert-deftest gascity-test-convoy-entry ()
  "A convoy entry renders progress as closed/total and carries the typed convoy.
The nested `progress' object decodes into a `gascity-progress'."
  (let* ((c (gascity-domain-decode
             'gascity-convoy
             '((id . "bs-0q2z") (title . "x") (status . "open")
               (progress . ((closed . 1) (total . 3))))))
         (entry (gascity-convoy-list--entry c)))
    (should (gascity-convoy-p (car entry)))
    (should (equal (gascity-convoy-id (car entry)) "bs-0q2z"))
    (should (equal (gascity-test--plain-cols entry)
                   '("bs-0q2z" "x" "open" "1/3")))))

(ert-deftest gascity-test-dolt-entry ()
  "A Dolt entry lays out name and commits, but not `open_beads' (gce-x72).
`gc dolt health' reports `open_beads' as 0 for every database, so the
column was a row of zeros; it was dropped here as it was from the rig
dashboard (gce-ziz).  The field is dropped regardless of its value, so a
non-zero `open_beads' in the input must still not surface."
  (should (equal (gascity-test--plain-cols
                  (gascity-dolt-list--entry
                   '((name . "beads") (commits . 42) (open_beads . 7))))
                 '("beads" "42"))))

;;; Typed domain objects + at-point dispatch (gce-fjt)

(ert-deftest gascity-test-domain-decode-rig ()
  "A rig payload decodes into a typed `gascity-rig'; a `false' stays nil.
Pins the `beads'->`store' slot rename and the `(or null boolean)' coercion
that keeps a decoded `false' (which gascity reads as nil) from becoming t."
  (let ((r (gascity-domain-decode
            'gascity-rig
            '((name . "gascity.el") (prefix . "gce") (path . "/p")
              (default_branch . "main") (beads . "initialized")
              (running . t) (suspended . nil) (hq . nil)))))
    (should (gascity-rig-p r))
    (should (equal (gascity-rig-name r) "gascity.el"))
    (should (equal (gascity-rig-prefix r) "gce"))
    (should (equal (gascity-rig-path r) "/p"))
    (should (equal (gascity-rig-default-branch r) "main"))
    (should (equal (gascity-rig-store r) "initialized"))
    (should (eq (gascity-rig-running r) t))
    (should (null (gascity-rig-suspended r)))
    (should (null (gascity-rig-hq r)))
    (should (equal (gascity-rig-status-label r) "running"))))

(ert-deftest gascity-test-domain-decode-session-and-agent ()
  "A session decodes; the action agent is built from it with the tmux socket."
  (let* ((s (gascity-domain-decode
             'gascity-session
             '((agent_name . "gascity.el/gastown.nux") (name . "raw-tmux")
               (rig . "gascity.el") (state . "active")
               (work_dir . "/wd") (session_name . "tm") (provider . "claude"))))
         (a (gascity-agent-from-session s "sock")))
    (should (equal (gascity-session-qualified-name s) "gascity.el/gastown.nux"))
    (should (gascity-session-running-p s))
    (should (gascity-agent-p a))
    (should (equal (gascity-agent-name a) "gascity.el/gastown.nux"))
    (should (equal (gascity-agent-rig a) "gascity.el"))
    (should (equal (gascity-agent-work-dir a) "/wd"))
    (should (equal (gascity-agent-session-name a) "tm"))
    (should (equal (gascity-agent-socket a) "sock"))
    (should (eq (gascity-agent-running a) t))))

(ert-deftest gascity-test-domain-decode-convoy-nested-progress ()
  "A convoy's nested `progress' object decodes into a `gascity-progress'.
Exercises `beads-from-json''s recursion into a nested EIEIO class."
  (let ((c (gascity-domain-decode
            'gascity-convoy
            '((id . "bs-1") (title . "t") (status . "open")
              (progress . ((closed . 2) (total . 5)))))))
    (should (gascity-progress-p (gascity-convoy-progress c)))
    (should (= (gascity-progress-closed (gascity-convoy-progress c)) 2))
    (should (= (gascity-progress-total (gascity-convoy-progress c)) 5))))

(ert-deftest gascity-test-domain-decode-list ()
  "`gascity-domain-decode-list' maps a vector to typed objects; nil/empty -> nil."
  (let ((rigs (gascity-domain-decode-list
               'gascity-rig (vector '((name . "a")) '((name . "b"))))))
    (should (= (length rigs) 2))
    (should (seq-every-p #'gascity-rig-p rigs))
    (should (equal (mapcar #'gascity-rig-name rigs) '("a" "b"))))
  (should (null (gascity-domain-decode-list 'gascity-rig nil)))
  (should (null (gascity-domain-decode-list 'gascity-rig []))))

(ert-deftest gascity-test-at-point-visit-dispatch ()
  "`gascity-at-point-visit' dispatches the right action per object class."
  ;; agent -> attach its tmux terminal
  (let (attached)
    (cl-letf (((symbol-function 'gascity-agent-attach-tmux)
               (lambda (a) (setq attached (gascity-agent-name a)))))
      (gascity-at-point-visit (gascity-test--agent :name "rig/a" :session-name "tm"))
      (should (equal attached "rig/a"))))
  ;; a bare bead-id string -> open in beads.el
  (let (shown)
    (cl-letf (((symbol-function 'gascity-bead-show) (lambda (id) (setq shown id))))
      (gascity-at-point-visit "gce-abc")
      (should (equal shown "gce-abc"))))
  ;; convoy -> open its bead in beads.el
  (let (shown)
    (cl-letf (((symbol-function 'gascity-bead-show) (lambda (id) (setq shown id))))
      (gascity-at-point-visit (gascity-domain-decode 'gascity-convoy '((id . "bs-9"))))
      (should (equal shown "bs-9"))))
  ;; rig -> open its dashboard by name; the HQ is refused
  (let (opened)
    (cl-letf (((symbol-function 'gascity-rig-dashboard) (lambda (n) (setq opened n))))
      (gascity-at-point-visit
       (gascity-domain-decode 'gascity-rig '((name . "gascity.el"))))
      (should (equal opened "gascity.el"))
      (should-error (gascity-at-point-visit
                     (gascity-domain-decode 'gascity-rig '((name . "bl") (hq . t))))
                    :type 'user-error)))
  ;; order -> open its source file
  (let (visited)
    (cl-letf (((symbol-function 'find-file) (lambda (f) (setq visited f)))
              ((symbol-function 'file-readable-p) (lambda (_) t)))
      (gascity-at-point-visit (gascity-domain-decode 'gascity-order '((source . "/s.el"))))
      (should (equal visited "/s.el"))))
  ;; an object no method knows how to visit signals a `user-error'
  (should-error (gascity-at-point-visit 42) :type 'user-error))

(ert-deftest gascity-test-object-at-point ()
  "`gascity-object-at-point' returns the typed object at point.
It is the single ladder the per-kind resolvers narrow."
  ;; vui agent row: a `gascity-agent' text property
  (with-temp-buffer
    (insert (propertize "x" 'gascity-agent (gascity-test--agent :name "rig/a")))
    (goto-char (point-min))
    (should (gascity-agent-p (gascity-object-at-point)))
    (should (equal (gascity-agent-name (gascity-agent-at-point)) "rig/a")))
  ;; vui bead row: a `gascity-bead' text-property string
  (with-temp-buffer
    (insert (propertize "x" 'gascity-bead "gce-1"))
    (goto-char (point-min))
    (should (equal (gascity-object-at-point) "gce-1"))
    (should (equal (gascity-bead-at-point) "gce-1")))
  ;; tabulated rig list: the entry id is the typed rig
  (with-temp-buffer
    (gascity-rig-list-mode)
    (setq tabulated-list-entries
          (list (gascity-rig-list--entry
                 (gascity-domain-decode 'gascity-rig
                                        '((name . "gascity.el") (prefix . "gce"))))))
    (tabulated-list-print)
    (goto-char (point-min))
    (should (gascity-rig-p (gascity-object-at-point)))
    (should (equal (gascity-rig-at-point) "gascity.el"))))

;;; Numeric column sorting (gce-94g)

(ert-deftest gascity-test-tabulated-progress-fraction ()
  "A \"closed/total\" string parses to a completion fraction.
Zero or missing totals (and unparseable input) yield 0.0 so a convoy
with nothing to do sorts below any with real progress."
  (should (= (gascity-tabulated--progress-fraction "1/4") 0.25))
  (should (= (gascity-tabulated--progress-fraction "3/3") 1.0))
  (should (= (gascity-tabulated--progress-fraction "0/0") 0.0))
  (should (= (gascity-tabulated--progress-fraction "5/0") 0.0))
  (should (= (gascity-tabulated--progress-fraction "") 0.0)))

(ert-deftest gascity-test-tabulated-numeric-sorter ()
  "The Dolt \"Commits\" column sorts numerically, not lexically.
Regression for gce-94g: the column declared the default `t' sorter, so
\"110\" sorted before \"8\".  Build entries with the real entry-builder
and pull the sorter out of the live mode's `tabulated-list-format' — that
also guards the backquoted-vector wiring, since a literal list left in the
sort slot would not be `functionp'.  (The \"Open beads\" column this test
also covered was dropped in gce-x72.)"
  (let* ((dbs '(((name . "a") (commits . 110))
                ((name . "b") (commits . 161))
                ((name . "c") (commits . 2351))
                ((name . "d") (commits . 8))))
         (entries (mapcar #'gascity-dolt-list--entry dbs))
         (commits-sorter (with-temp-buffer
                           (gascity-dolt-list-mode)
                           (nth 2 (aref tabulated-list-format 1)))))
    (should (functionp commits-sorter))
    ;; The exact case from the bug report.
    (should (equal (mapcar (lambda (e) (aref (cadr e) 1))
                           (sort (copy-sequence entries) commits-sorter))
                   '("8" "110" "161" "2351")))))

(ert-deftest gascity-test-convoy-progress-sort ()
  "The convoy \"Progress\" column sorts by completion fraction.
\"1/1\" (100%) sorts above \"50/100\" (50%) even though 1 < 50, and a
zero-total convoy sinks to the bottom (gce-94g)."
  (let* ((convoys '(((id . "a") (title . "t") (status . "open")
                     (progress . ((closed . 1) (total . 1))))
                    ((id . "b") (title . "t") (status . "open")
                     (progress . ((closed . 50) (total . 100))))
                    ((id . "c") (title . "t") (status . "open")
                     (progress . ((closed . 3) (total . 100))))
                    ((id . "d") (title . "t") (status . "open")
                     (progress . ((closed . 0) (total . 0))))))
         (entries (mapcar #'gascity-convoy-list--entry
                          (gascity-domain-decode-list 'gascity-convoy convoys)))
         (sorter (with-temp-buffer
                   (gascity-convoy-list-mode)
                   (nth 2 (aref tabulated-list-format 3)))))
    (should (functionp sorter))
    (should (equal (mapcar (lambda (e) (aref (cadr e) 3))
                           (sort (copy-sequence entries) sorter))
                   '("0/0" "3/100" "50/100" "1/1")))))

;;; Paged list sorting spans page boundaries (gce-dzs)

(defun gascity-test--setup-paged-keys (&optional page-size)
  "Set up the current buffer as a paged list of scrambled single-letter keys.
Installs a `Key'/`X' format sorted ascending by `Key', loads six rows
whose gc-return order (f d b a c e) differs from sorted order (a..f) — so
a per-page sort is distinguishable from a global one — sets PAGE-SIZE (2
by default, giving three pages), and renders page 1.  Each row's id is its
own key, so the first/last visible row reads off `tabulated-list-entries'
directly.  Shared fixture for the gce-dzs paging-sort tests."
  (tabulated-list-mode)
  (setq-local tabulated-list-format [("Key" 10 t) ("X" 6 t)]
              tabulated-list-sort-key (cons "Key" nil)
              tabulated-list-padding 1)
  (tabulated-list-init-header)
  (setq gascity-tabulated--all-entries
        (mapcar (lambda (k) (list k (vector k "-")))
                '("f" "d" "b" "a" "c" "e"))
        gascity-tabulated--current-page 1
        gascity-tabulated--page-size (or page-size 2)
        gascity-tabulated--base-name "Keys")
  (gascity-tabulated--refresh-display))

(ert-deftest gascity-test-tabulated-sort-spans-pages ()
  "The default sort orders the whole dataset, not each page in isolation.
Regression for gce-dzs: `gascity-tabulated--refresh-display' sliced
`gascity-tabulated--all-entries' in gc-return order and let
`tabulated-list-print' sort only the visible page, so on a >1-page list
the order was wrong across page boundaries (page 1 ended mid-alphabet and
later items belonging within it were stranded on page 2).  With the
scrambled fixture, a per-page sort would surface \"d\" first and \"e\"
last; the global sort must instead put the dataset minimum on page 1's
first row and the maximum on the last page's last row."
  (with-temp-buffer
    (gascity-test--setup-paged-keys)
    (should (= (gascity-tabulated--total-pages) 3))
    ;; Page 1 first row = global minimum.
    (should (equal (car (car tabulated-list-entries)) "a"))
    ;; Last page's last row = global maximum.
    (gascity-tabulated-goto-page 3)
    (should (equal (car (car (last tabulated-list-entries))) "f"))))

(ert-deftest gascity-test-tabulated-sort-command-spans-pages ()
  "`gascity-tabulated-sort' (the `S' key) re-sorts every page, then shows page 1.
Regression for gce-dzs: the inherited `tabulated-list-sort' reordered only
the visible slice, so toggling the sort changed one page.  The wrapper
flips `tabulated-list-sort-key', re-sorts `gascity-tabulated--all-entries'
globally, and returns to page 1 — so a descending toggle puts the global
maximum on the first row of page 1 and the minimum on the last page."
  (with-temp-buffer
    (gascity-test--setup-paged-keys)
    ;; Move off page 1 so the page-1 reset is observable.
    (gascity-tabulated-goto-page 2)
    (should (= gascity-tabulated--current-page 2))
    ;; Put point on the first row's "Key" cell, past the leading padding
    ;; (`tabulated-list-print' leaves point on the padding, which carries no
    ;; column name), so the no-prefix call toggles that column (asc -> desc).
    (goto-char (point-min))
    (forward-char tabulated-list-padding)
    (gascity-tabulated-sort)
    (should (eq (cdr tabulated-list-sort-key) t))   ; now descending
    (should (= gascity-tabulated--current-page 1))   ; reset to page 1
    (should (equal (car (car tabulated-list-entries)) "f")) ; global max first
    ;; Last page now holds the global minimum.
    (gascity-tabulated-goto-page 3)
    (should (equal (car (car (last tabulated-list-entries))) "a"))))

(ert-deftest gascity-test-tabulated-sort-from-padding-column ()
  "`S' from column 0 (the leading padding) sorts by the default key, spanning pages.
Regression for gce-a8d: every gascity list sets `tabulated-list-padding' to
1, so column 0 of each row is a one-char left margin carrying no
`tabulated-list-column-name'.  Point rests there right after the list opens
\(and `n'/`p' keep it there), so the inherited `tabulated-list-sort' signaled
\"Cannot sort by nil\".  `gascity-tabulated-sort' now falls back to the column
named in `tabulated-list-sort-key', so `S' from the padding toggles that
column and re-sorts the whole dataset — the same result as `S' on the
column's cell (see `gascity-test-tabulated-sort-command-spans-pages') but
without first moving point off the padding."
  (with-temp-buffer
    (gascity-test--setup-paged-keys)
    ;; Move off page 1 so the page-1 reset is observable.
    (gascity-tabulated-goto-page 2)
    (should (= gascity-tabulated--current-page 2))
    ;; Point on the leading padding (column 0): no column name, the cursor's
    ;; resting place after the list opens and the exact spot that used to
    ;; signal "Cannot sort by nil".
    (goto-char (point-min))
    (should-not (get-text-property (point) 'tabulated-list-column-name))
    (gascity-tabulated-sort)
    (should (equal (car tabulated-list-sort-key) "Key")) ; sorted by the default column
    (should (eq (cdr tabulated-list-sort-key) t))        ; toggled ascending -> descending
    (should (= gascity-tabulated--current-page 1))       ; reset to page 1
    (should (equal (car (car tabulated-list-entries)) "f")) ; global max first
    ;; Last page now holds the global minimum.
    (gascity-tabulated-goto-page 3)
    (should (equal (car (car (last tabulated-list-entries))) "a"))))

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

(ert-deftest gascity-test-status-agent-join ()
  "An agent is joined to its session for work-dir, tmux name, and socket.
The join yields a typed `gascity-agent'."
  (let* ((furiosa '((name . "furiosa")
                    (qualified_name . "gascity.el/gastown.furiosa")
                    (running . t)))
         (smap (gascity-status--session-map
                (vector '((agent_name . "gascity.el/gastown.furiosa")
                          (work_dir . "/wd") (session_name . "tm")))))
         (obj (gascity-status--agent furiosa "gascity.el" smap "sock")))
    (should (gascity-agent-p obj))
    (should (equal (gascity-agent-work-dir obj) "/wd"))
    (should (equal (gascity-agent-session-name obj) "tm"))
    (should (equal (gascity-agent-socket obj) "sock"))
    (should (eq (gascity-agent-running obj) t))))

(ert-deftest gascity-test-status-sessions-note ()
  "A sessions-load hint appears only when that load is not ready.
Without it, a failed/pending session load degrades silently — agent rows
lose `work_dir'/`session_name', so `d'/`t' no-op with no explanation."
  (should (null (gascity-status--sessions-note-vnode 'ready nil)))
  (should (null (gascity-status--sessions-note-vnode nil nil)))
  (should (gascity-status--sessions-note-vnode 'error "boom"))
  (should (gascity-status--sessions-note-vnode 'pending nil)))

;;; Status dashboard refresh — collapse preservation (vui integration, gce-gie)

(defun gascity-test--buffer-contains-p (needle)
  "Return non-nil when the current buffer's text contains NEEDLE."
  (save-excursion
    (goto-char (point-min))
    (and (search-forward needle nil t) t)))

(defun gascity-test--press-header (name &optional command)
  "Run COMMAND on the collapsible rig header whose label contains NAME.
NAME is matched against the buffer's visible text; the rig name appears
only in its header, so the first match lands on that header.  COMMAND
defaults to `gascity-status-activate' (what `RET' runs); pass
`gascity-status-toggle-section' to exercise the `TAB' toggle instead.  Both
flip the rig's collapse via the `gascity-rig' text property on the header."
  (goto-char (point-min))
  (unless (search-forward name nil t)
    (error "rig header %S not found in dashboard" name))
  (goto-char (match-beginning 0))
  (funcall (or command #'gascity-status-activate)))

(defun gascity-test--status-async-stub (status-box sessions-box)
  "Return a `gascity-reader-read-async' stub that parks resolve callbacks.
The `status' load's callback is stored in the car of STATUS-BOX and the
`session list' load's in SESSIONS-BOX, so a test can fire them on demand
and drive the dashboard through pending -> ready transitions
deterministically — no live `gc', no process timing."
  (lambda (args callback &optional _errback)
    (cond
     ((equal args '("status")) (setcar status-box callback))
     ((equal args '("session" "list")) (setcar sessions-box callback))
     (t (error "unexpected async args: %S" args)))
    nil))

(ert-deftest gascity-test-status-refresh-preserves-collapse ()
  "A `g' refresh preserves a rig section's collapsed state (gce-gie).
Regression: the refresh bumped `refresh-tick', restarting the status load
as 'pending, whose bare \"Loading…\" branch replaced the whole tree and
unmounted every keyed rig component — resetting its component-local
collapse `:state'.  Stale-while-revalidate keeps the prior snapshot
mounted, so the collapse survives both the in-flight refresh and the
arrival of fresh data."
  (let ((status-box (list nil))
        (sessions-box (list nil))
        (vui-render-delay nil)            ; render synchronously, no timers
        (status '((ok . t) (city_name . "bright-lights")
                  (controller . ((running . t)))
                  (rigs . [((name . "gascity.el")) ((name . "other"))])
                  (agents . [((name . "furiosa")
                              (qualified_name . "gascity.el/gastown.furiosa")
                              (running . t))])))
        (sessions '((sessions . []))))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (gascity-test--status-async-stub status-box sessions-box)))
      (save-window-excursion
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-status-app) "*gascity-status-test*")
              (with-current-buffer "*gascity-status-test*"
                ;; Cold load resolves -> dashboard renders, rig expanded (▼).
                (funcall (car status-box) status)
                (funcall (car sessions-box) sessions)
                (should (gascity-test--buffer-contains-p "▼ gascity.el"))
                ;; Collapse the rig via its header button (▶).
                (gascity-test--press-header "gascity.el")
                (should (gascity-test--buffer-contains-p "▶ gascity.el"))
                (should-not (gascity-test--buffer-contains-p "▼ gascity.el"))
                ;; Refresh restarts the loads as 'pending.  The stale snapshot
                ;; keeps the tree mounted -> still collapsed, no blank.
                (gascity-status--refresh-instance (current-buffer))
                (should (gascity-test--buffer-contains-p "▶ gascity.el"))
                (should-not (gascity-test--buffer-contains-p "Loading Gas City status"))
                ;; Fresh data arrives -> collapse still preserved.
                (funcall (car status-box) status)
                (funcall (car sessions-box) sessions)
                (should (gascity-test--buffer-contains-p "▶ gascity.el"))))
          (when (get-buffer "*gascity-status-test*")
            (kill-buffer "*gascity-status-test*")))))))

(ert-deftest gascity-test-status-refresh-stale-while-revalidate ()
  "The loading line shows only on the first, dataless load (gce-gie).
Once a snapshot exists, an in-flight refresh keeps the previous content
visible instead of blanking to \"Loading…\" — the same whole-tree unmount
that lost collapse state also flickered the view on every refresh."
  (let ((status-box (list nil))
        (sessions-box (list nil))
        (vui-render-delay nil)
        (status '((ok . t) (city_name . "bright-lights")
                  (controller . ((running . t)))
                  (rigs . [((name . "gascity.el"))])
                  (agents . [])))
        (sessions '((sessions . []))))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (gascity-test--status-async-stub status-box sessions-box)))
      (save-window-excursion
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-status-app) "*gascity-status-test*")
              (with-current-buffer "*gascity-status-test*"
                ;; First load, no data yet -> loading line shown.
                (should (gascity-test--buffer-contains-p "Loading Gas City status"))
                ;; Resolve -> content replaces the loading line.
                (funcall (car status-box) status)
                (funcall (car sessions-box) sessions)
                (should (gascity-test--buffer-contains-p "Gas City:"))
                (should-not (gascity-test--buffer-contains-p "Loading Gas City status"))
                ;; Refresh, leave the new load pending -> previous content
                ;; stays put, no flicker back to the loading line.
                (gascity-status--refresh-instance (current-buffer))
                (should (gascity-test--buffer-contains-p "Gas City:"))
                (should (gascity-test--buffer-contains-p "gascity.el"))
                (should-not (gascity-test--buffer-contains-p "Loading Gas City status"))))
          (when (get-buffer "*gascity-status-test*")
            (kill-buffer "*gascity-status-test*")))))))

;;; Status dashboard refresh — semantic cursor preservation (gce-9am, §11.7)

;; These two mount the real `gascity-status-app' in a `gascity-dashboard-mode'
;; buffer (so `gascity-section--around-rerender' — gated on
;; `gascity-section-mode' — actually fires) and drive it through a refresh with
;; the parked-callback stub.  `gascity-status-auto-refresh' is bound nil so
;; entering the mode starts no live timer.

(ert-deftest gascity-test-status-refresh-preserves-cursor-on-row ()
  "Point follows the same agent row across a refresh, even when rows reorder.
`gascity-section--around-rerender' restores point by the row's SEMANTIC id
\(here the agent's qualified name), not by a widget path or line number, so it
stays on that row after vui `erase-buffer's and rebuilds the tree with the
agents in a different order (gce-9am, §11.7)."
  (let ((status-box (list nil))
        (sessions-box (list nil))
        (vui-render-delay nil)                ; render synchronously, no timers
        (gascity-status-auto-refresh nil)     ; mode starts no auto-refresh timer
        ;; Cold load: furiosa then nux.  Refresh: nux then furiosa.
        (status-a '((ok . t) (city_name . "bright-lights")
                    (controller . ((running . t)))
                    (rigs . [((name . "gascity.el"))])
                    (agents . [((name . "furiosa")
                                (qualified_name . "gascity.el/gastown.furiosa")
                                (running . t))
                               ((name . "nux")
                                (qualified_name . "gascity.el/gastown.nux")
                                (running . t))])))
        (status-b '((ok . t) (city_name . "bright-lights")
                    (controller . ((running . t)))
                    (rigs . [((name . "gascity.el"))])
                    (agents . [((name . "nux")
                                (qualified_name . "gascity.el/gastown.nux")
                                (running . t))
                               ((name . "furiosa")
                                (qualified_name . "gascity.el/gastown.furiosa")
                                (running . t))])))
        (sessions '((sessions . []))))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (gascity-test--status-async-stub status-box sessions-box)))
      (save-window-excursion
        (unwind-protect
            (progn
              (with-current-buffer (get-buffer-create "*gascity-status-test*")
                (gascity-dashboard-mode))
              (vui-mount (vui-component 'gascity-status-app) "*gascity-status-test*")
              (with-current-buffer "*gascity-status-test*"
                (funcall (car status-box) status-a)
                (funcall (car sessions-box) sessions)
                ;; Land on the SECOND agent row (nux), so a naive "stay at the
                ;; top" would fail.
                (goto-char (point-min))
                (should (search-forward "nux" nil t))
                (goto-char (match-beginning 0))
                (let ((id (gascity-section--line-id)))
                  (should (equal id '(agent . "gascity.el/gastown.nux")))
                  ;; Refresh, then let the reordered data arrive: nux moves up a
                  ;; line, furiosa moves down.
                  (gascity-status--refresh-instance (current-buffer))
                  (funcall (car status-box) status-b)
                  (funcall (car sessions-box) sessions)
                  ;; Point is still on the nux row — it followed the id to the
                  ;; row's new position, not the old line number or point-min.
                  (should (equal (gascity-section--line-id) id))
                  (should (string-search
                           "nux" (buffer-substring (line-beginning-position)
                                                   (line-end-position)))))))
          (when (get-buffer "*gascity-status-test*")
            (kill-buffer "*gascity-status-test*")))))))

(ert-deftest gascity-test-status-refresh-preserves-window-point-non-selected ()
  "A dashboard in a NON-selected window keeps its window-point across a refresh.
Regression (gce-9am, §11.7): `erase-buffer' resets every `window-point' to 1
and vui restores only `window-start', so a status buffer shown in a window
other than the selected one jumped to buffer top on each tick.
`gascity-section--around-rerender' calls `set-window-point' for every window
showing the buffer, restoring them to the semantic row."
  (let ((status-box (list nil))
        (sessions-box (list nil))
        (vui-render-delay nil)
        (gascity-status-auto-refresh nil)
        (status '((ok . t) (city_name . "bright-lights")
                  (controller . ((running . t)))
                  (rigs . [((name . "gascity.el"))])
                  (agents . [((name . "furiosa")
                              (qualified_name . "gascity.el/gastown.furiosa")
                              (running . t))])))
        (sessions '((sessions . []))))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (gascity-test--status-async-stub status-box sessions-box)))
      (save-window-excursion
        (let ((buf (get-buffer-create "*gascity-status-test*"))
              (other (get-buffer-create "*gascity-other-test*")))
          (unwind-protect
              (progn
                (with-current-buffer buf (gascity-dashboard-mode))
                (vui-mount (vui-component 'gascity-status-app)
                           "*gascity-status-test*")
                (funcall (car status-box) status)
                (funcall (car sessions-box) sessions)
                (let (target-pos)
                  ;; Put point on the furiosa row and remember it.
                  (with-current-buffer buf
                    (goto-char (point-min))
                    (should (search-forward "furiosa" nil t))
                    (goto-char (match-beginning 0))
                    (setq target-pos (point))
                    (should (equal (gascity-section--line-id)
                                   '(agent . "gascity.el/gastown.furiosa"))))
                  ;; Selected window shows OTHER; buf lives in a split below it.
                  (with-current-buffer other (insert "placeholder"))
                  (set-window-buffer (selected-window) other)
                  (let ((status-window (split-window (selected-window) nil 'below)))
                    (set-window-buffer status-window buf)
                    (set-window-point status-window target-pos)
                    (should-not (eq (selected-window) status-window))
                    ;; Refresh while buf is in the non-selected window.
                    (gascity-status--refresh-instance buf)
                    (funcall (car status-box) status)
                    (funcall (car sessions-box) sessions)
                    ;; window-point stayed on the furiosa row, not reset to 1.
                    (let ((wp (window-point status-window)))
                      (should (> wp 1))
                      (with-current-buffer buf
                        (save-excursion
                          (goto-char wp)
                          (should (equal (gascity-section--line-id)
                                         '(agent . "gascity.el/gastown.furiosa")))))))))
            (when (buffer-live-p buf) (kill-buffer buf))
            (when (buffer-live-p other) (kill-buffer other))))))))

;;; gce-pt6 — auto-refresh the status dashboard on a timer, only when visible

(ert-deftest gascity-test-status-auto-refresh-creates-timer-when-on ()
  "`gascity-status--auto-refresh-setup' starts a repeating timer when
`gascity-status-auto-refresh' is on and the interval is positive (gce-pt6)."
  (let ((buf (generate-new-buffer "*gascity-status-auto-on*"))
        (gascity-status-auto-refresh t)
        (gascity-status-auto-refresh-interval 3600)) ; never fires in-test
    (unwind-protect
        (progn
          (gascity-status--auto-refresh-setup buf)
          (should (timerp (buffer-local-value 'gascity-status--refresh-timer buf))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-status-auto-refresh-no-timer-when-off ()
  "No timer is created when `gascity-status-auto-refresh' is nil (gce-pt6)."
  (let ((buf (generate-new-buffer "*gascity-status-auto-off*"))
        (gascity-status-auto-refresh nil)
        (gascity-status-auto-refresh-interval 3600))
    (unwind-protect
        (progn
          (gascity-status--auto-refresh-setup buf)
          (should-not (buffer-local-value 'gascity-status--refresh-timer buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-status-auto-refresh-no-timer-when-interval-nonpositive ()
  "A non-positive interval disables the timer even with auto-refresh on (gce-pt6)."
  (let ((buf (generate-new-buffer "*gascity-status-auto-zero*"))
        (gascity-status-auto-refresh t)
        (gascity-status-auto-refresh-interval 0))
    (unwind-protect
        (progn
          (gascity-status--auto-refresh-setup buf)
          (should-not (buffer-local-value 'gascity-status--refresh-timer buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-status-auto-refresh-tick-noop-when-buried ()
  "The timer tick does nothing when the dashboard is not displayed (gce-pt6).
A buried buffer must not refresh — and therefore must not fetch from `gc'."
  (let ((buf (generate-new-buffer "*gascity-status-buried*"))
        (refreshed nil))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer-window) (lambda (&rest _) nil))
                  ((symbol-function 'gascity-status--refresh-instance)
                   (lambda (b) (setq refreshed b))))
          (gascity-status--auto-refresh-tick buf)
          (should-not refreshed))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-status-auto-refresh-tick-refreshes-when-visible ()
  "The timer tick refreshes the dashboard in place when it is visible (gce-pt6).
It calls `gascity-status--refresh-instance' (collapse + point preserved),
not a full `gascity-status' remount."
  (let ((buf (generate-new-buffer "*gascity-status-visible*"))
        (refreshed nil))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer-window)
                   (lambda (b &rest _) (and (eq b buf) 'a-window)))
                  ((symbol-function 'gascity-status--refresh-instance)
                   (lambda (b) (setq refreshed b))))
          (gascity-status--auto-refresh-tick buf)
          (should (eq refreshed buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-status-auto-refresh-teardown-cancels-timer ()
  "Killing the dashboard cancels its auto-refresh timer via `kill-buffer-hook'
— no leaked timers (gce-pt6)."
  (let ((buf (generate-new-buffer "*gascity-status-teardown*"))
        (gascity-status-auto-refresh t)
        (gascity-status-auto-refresh-interval 3600)
        timer)
    (unwind-protect
        (progn
          (gascity-status--auto-refresh-setup buf)
          (setq timer (buffer-local-value 'gascity-status--refresh-timer buf))
          (should (timerp timer))
          (should (memq timer timer-list))
          (kill-buffer buf)
          (should-not (memq timer timer-list)))
      (when (timerp timer) (cancel-timer timer))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-status-dashboard-mode-starts-timer ()
  "Enabling `gascity-dashboard-mode' starts the auto-refresh timer when
`gascity-status-auto-refresh' is on (gce-pt6) — the mode is the wiring point."
  (let ((buf (generate-new-buffer "*gascity-status-mode*"))
        (gascity-status-auto-refresh t)
        (gascity-status-auto-refresh-interval 3600))
    (unwind-protect
        (with-current-buffer buf
          (gascity-dashboard-mode)
          (should (timerp gascity-status--refresh-timer)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-status-auto-refresh-toggle ()
  "`G' is bound to the auto-refresh toggle, which flips the variable and
restarts/cancels the buffer's timer to match (gce-pt6)."
  (should (eq (keymap-lookup gascity-dashboard-mode-map "G")
              #'gascity-status-toggle-auto-refresh))
  (let ((buf (generate-new-buffer "*gascity-status-toggle*"))
        (gascity-status-auto-refresh nil)
        (gascity-status-auto-refresh-interval 3600))
    (unwind-protect
        (with-current-buffer buf
          ;; Off -> on: a timer appears.
          (gascity-status-toggle-auto-refresh)
          (should gascity-status-auto-refresh)
          (should (timerp gascity-status--refresh-timer))
          ;; On -> off: the timer is cancelled.
          (gascity-status-toggle-auto-refresh)
          (should-not gascity-status-auto-refresh)
          (should-not (timerp gascity-status--refresh-timer)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;;; gce-x0c — blank line between rig groups; header carries rig path

(defun gascity-test--blank-line-above-p (needle)
  "Return non-nil when the line above the one holding NEEDLE is blank.
Used to assert rig sections are visually separated by a blank row."
  (save-excursion
    (goto-char (point-min))
    (and (search-forward needle nil t)
         (progn (forward-line 0) (forward-line -1)
                (looking-at-p "[ \t]*$")))))

(ert-deftest gascity-test-status-blank-line-between-rigs ()
  "A blank line separates rig groups, and each rig header carries its name
and `path' so `d'/RET act on the rig at point (gce-x0c)."
  (let ((status-box (list nil))
        (sessions-box (list nil))
        (vui-render-delay nil)
        (status '((ok . t) (city_name . "bright-lights")
                  (controller . ((running . t)))
                  (rigs . [((name . "rig-a") (path . "/p/a"))
                           ((name . "rig-b") (path . "/p/b"))])
                  (agents . [])))
        (sessions '((sessions . []))))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (gascity-test--status-async-stub status-box sessions-box)))
      (save-window-excursion
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-status-app) "*gascity-status-test*")
              (with-current-buffer "*gascity-status-test*"
                (funcall (car status-box) status)
                (funcall (car sessions-box) sessions)
                ;; Both rigs render, separated by a blank line.
                (should (gascity-test--buffer-contains-p "▼ rig-a"))
                (should (gascity-test--buffer-contains-p "▼ rig-b"))
                (should (gascity-test--blank-line-above-p "▼ rig-b"))
                ;; The header carries the rig name + path (for `d' and RET).
                (goto-char (point-min))
                (search-forward "rig-a")
                (goto-char (match-beginning 0))
                (should (equal (get-text-property (point) 'gascity-rig) "rig-a"))
                (should (equal (get-text-property (point) 'gascity-rig-dir) "/p/a"))))
          (when (get-buffer "*gascity-status-test*")
            (kill-buffer "*gascity-status-test*")))))))

;;; gce-ed4 — TAB toggles a rig section's collapse (magit convention)

(ert-deftest gascity-test-status-tab-toggles-section ()
  "TAB toggles a rig section's collapse in the status dashboard (gce-ed4).
The magit-section convention binds TAB to \"toggle the visibility of the
section at point\".  The status board is the only dashboard with
collapsible sections, so the binding lives in its map (not the shared
`gascity-section-mode-map'); pressing TAB on a rig header flips its
collapse (▼ <-> ▶) exactly as RET does, while RET keeps its prior job —
toggle on a header, attach a terminal on a row.  Off a rig header there is
nothing collapsible, so TAB signals a clean `user-error' rather than
toggling or attaching something unrelated."
  ;; Bindings: TAB -> the section toggle; RET unchanged.
  (should (eq (keymap-lookup gascity-dashboard-mode-map "TAB")
              #'gascity-status-toggle-section))
  (should (eq (keymap-lookup gascity-dashboard-mode-map "RET")
              #'gascity-status-activate))
  ;; Off a rig header (an agent row, say): a clean user-error, no toggle.
  (with-temp-buffer
    (insert "  ● furiosa")
    (goto-char (point-min))
    (should-error (gascity-status-toggle-section) :type 'user-error))
  ;; End-to-end: TAB on the header collapses (▼ -> ▶), TAB again expands.
  (let ((status-box (list nil))
        (sessions-box (list nil))
        (vui-render-delay nil)            ; render synchronously, no timers
        (status '((ok . t) (city_name . "bright-lights")
                  (controller . ((running . t)))
                  (rigs . [((name . "gascity.el"))])
                  (agents . [])))
        (sessions '((sessions . []))))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (gascity-test--status-async-stub status-box sessions-box)))
      (save-window-excursion
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-status-app) "*gascity-status-test*")
              (with-current-buffer "*gascity-status-test*"
                (funcall (car status-box) status)
                (funcall (car sessions-box) sessions)
                (should (gascity-test--buffer-contains-p "▼ gascity.el"))
                ;; TAB collapses the rig.
                (gascity-test--press-header
                 "gascity.el" #'gascity-status-toggle-section)
                (should (gascity-test--buffer-contains-p "▶ gascity.el"))
                (should-not (gascity-test--buffer-contains-p "▼ gascity.el"))
                ;; TAB again expands it.
                (gascity-test--press-header
                 "gascity.el" #'gascity-status-toggle-section)
                (should (gascity-test--buffer-contains-p "▼ gascity.el"))
                (should-not (gascity-test--buffer-contains-p "▶ gascity.el"))))
          (when (get-buffer "*gascity-status-test*")
            (kill-buffer "*gascity-status-test*")))))))

;;; tmux socket resolution

(ert-deftest gascity-test-resolve-tmux-socket ()
  "The override wins; otherwise the city name is the socket."
  (let ((gascity-tmux-socket "override"))
    (should (equal (gascity-resolve-tmux-socket "city") "override")))
  (let ((gascity-tmux-socket nil))
    (should (equal (gascity-resolve-tmux-socket "bright-lights") "bright-lights"))))

(ert-deftest gascity-test-resolve-tmux-socket-gc-fallback ()
  "With no override or arg and outside the city tree, fall back to gc.
This is the session-list path (gce-rdk): it resolves the socket with no
city-name in hand, so when directory context fails the gc-backed lookup
must keep the socket correct instead of silently targeting the default
tmux server."
  (gascity-context-clear-cache)
  (unwind-protect
      (let ((gascity-tmux-socket nil))
        (cl-letf (((symbol-function 'gascity-context-city-name)
                   (lambda (&rest _) nil))   ; simulate "outside the city tree"
                  ((symbol-function 'gascity-reader-read)
                   (lambda (&rest _) '((city_name . "bright-lights")))))
          (should (equal (gascity-resolve-tmux-socket) "bright-lights"))))
    (gascity-context-clear-cache)))

(ert-deftest gascity-test-context-gc-city-name ()
  "Reads `city_name' from `gc status', caches per dir, and is nil-safe."
  (gascity-context-clear-cache)
  (unwind-protect
      (let ((calls 0))
        (cl-letf (((symbol-function 'gascity-reader-read)
                   (lambda (&rest _)
                     (setq calls (1+ calls))
                     '((city_name . "bright-lights")))))
          ;; First call queries gc; the second is served from the cache.
          (should (equal (gascity-context-gc-city-name "/tmp/outside")
                         "bright-lights"))
          (should (equal (gascity-context-gc-city-name "/tmp/outside")
                         "bright-lights"))
          (should (= calls 1)))
        ;; A gc failure resolves to nil rather than raising.
        (cl-letf (((symbol-function 'gascity-reader-read)
                   (lambda (&rest _)
                     (signal 'gascity-command-error '("boom")))))
          (should (null (gascity-context-gc-city-name "/tmp/elsewhere")))))
    (gascity-context-clear-cache)))

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

(ert-deftest gascity-test-terminal-live-buffer ()
  "`gascity-terminal--live-buffer' returns the buffer only when it hosts a
live process: nil for a missing buffer, a process-less buffer, or a dead
process; the buffer itself while the process runs."
  ;; Missing buffer.
  (should (null (gascity-terminal--live-buffer "*gc-agent-absent-xyz*")))
  ;; Buffer with no process.
  (let ((buf (generate-new-buffer "*gc-agent-noproc*")))
    (unwind-protect
        (should (null (gascity-terminal--live-buffer (buffer-name buf))))
      (kill-buffer buf)))
  ;; A live process makes the buffer reusable; once it dies, it does not.
  (let* ((buf (generate-new-buffer "*gc-agent-live*"))
         (proc (make-pipe-process :name "gc-test-live" :buffer buf :noquery t)))
    (unwind-protect
        (progn
          (should (eq (gascity-terminal--live-buffer (buffer-name buf)) buf))
          (delete-process proc)
          (should (null (gascity-terminal--live-buffer (buffer-name buf)))))
      (when (process-live-p proc) (delete-process proc))
      (kill-buffer buf))))

(ert-deftest gascity-test-terminal-run-reuses-live-buffer ()
  "`gascity-terminal-run' reuses a buffer that already hosts a live process:
it pops to that buffer and does NOT spawn a second terminal (the bug where
pressing `t' on an already-open agent terminal errored)."
  (let* ((buf (generate-new-buffer "*gc-agent-reuse*"))
         (name (buffer-name buf))
         (proc (make-pipe-process :name "gc-test-reuse" :buffer buf :noquery t))
         spawned popped)
    (unwind-protect
        (cl-letf (((symbol-function 'beads-terminal-spawn)
                   (lambda (&rest _) (setq spawned t) (error "must not re-spawn")))
                  ((symbol-function 'pop-to-buffer)
                   (lambda (b &rest _) (setq popped b) b)))
          (let ((ret (gascity-terminal-run '("env") name)))
            (should (eq ret buf))
            (should (eq popped buf))
            (should-not spawned)))
      (when (process-live-p proc) (delete-process proc))
      (kill-buffer buf))))

(ert-deftest gascity-test-terminal-run-spawns-when-not-live ()
  "With no existing live-process buffer, `gascity-terminal-run' spawns a
fresh terminal via `beads-terminal-spawn' and pops to the new buffer."
  (let ((name "*gc-agent-fresh*")
        spawn-args popped)
    (unwind-protect
        (cl-letf (((symbol-function 'beads-terminal-spawn)
                   (lambda (_term buffer-name argv dir _env)
                     (setq spawn-args (list buffer-name argv dir))
                     (get-buffer-create buffer-name)))
                  ((symbol-function 'pop-to-buffer)
                   (lambda (b &rest _) (setq popped b) b)))
          (let ((ret (gascity-terminal-run '("echo" "hi") name "/tmp")))
            (should (bufferp ret))
            (should (equal (nth 0 spawn-args) name))
            (should (equal (nth 1 spawn-args) '("echo" "hi")))
            (should (string-prefix-p "/tmp" (nth 2 spawn-args)))
            (should (eq popped ret))))
      (when (get-buffer name) (kill-buffer name)))))

;;; tmux status in the mode line (gce-hjj)

(ert-deftest gascity-test-terminal-window-list ()
  "`gascity-terminal--window-list' parses tmux output into :active/:label plists."
  (cl-letf (((symbol-function 'call-process)
             (lambda (_prog _in buf _disp &rest args)
               (should (equal (car args) "list-windows"))
               (when (eq buf t) (insert "0\t0:bash-\n1\t1:claude*\n"))
               0)))
    (let ((ws (gascity-terminal--window-list "sess" nil)))
      (should (= (length ws) 2))
      (should (equal (plist-get (nth 0 ws) :label) "0:bash-"))
      (should (null (plist-get (nth 0 ws) :active)))
      (should (equal (plist-get (nth 1 ws) :label) "1:claude*"))
      (should (eq (plist-get (nth 1 ws) :active) t))))
  ;; A missing session (tmux exit non-zero) yields nil — this is the
  ;; session-existence probe.
  (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1)))
    (should (null (gascity-terminal--window-list "gone" nil)))))

(ert-deftest gascity-test-terminal-status-string ()
  "`gascity-terminal--status-string' shows the `status-left' name and the
window list with the current window emphasised; nil when the session is gone."
  (cl-letf (((symbol-function 'call-process)
             (lambda (_prog _in buf _disp &rest args)
               (when (eq buf t)
                 (cond
                  ((equal (car args) "list-windows")
                   (insert "0\t0:bash\n1\t1:claude*\n"))
                  ((equal (car args) "display-message")
                   ;; `status-left' value, with trailing space to trim.
                   (insert "gastown.mayor \n"))))
               0)))
    (let ((s (gascity-terminal--status-string "sess" nil)))
      (should (stringp s))
      ;; Friendly name (trimmed) faced as the session identity.
      (should (string-match "gastown.mayor" s))
      (should (eq (get-text-property (string-match "gastown.mayor" s) 'face s)
                  'gascity-city))
      ;; Active window emphasised; inactive window not.
      (should (string-match "1:claude" s))
      (should (eq (get-text-property (string-match "1:claude" s) 'face s)
                  'gascity-header))
      (should (string-match "0:bash" s))
      (should (eq (get-text-property (string-match "0:bash" s) 'face s)
                  'default))))
  (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1)))
    (should (null (gascity-terminal--status-string "gone" nil)))))

(ert-deftest gascity-test-terminal-status-install-teardown ()
  "Install turns the session's tmux status bar off, adds a mode-line segment
and a refresh timer; teardown (via `kill-buffer-hook') cancels the timer and
reverts the override with `set-option -u'.  All tmux ops are session-scoped."
  (let ((buf (generate-new-buffer "*gc-agent-install-test*"))
        (cmds nil)
        (gascity-terminal-status-interval 3600)) ; far enough to never fire
    (unwind-protect
        (cl-letf (((symbol-function 'call-process)
                   (lambda (_prog _in bufarg _disp &rest args)
                     (push args cmds)
                     ;; SOCKET is non-nil here, so args start with
                     ;; ("-L" "sock" …); match the subcommand by membership.
                     (when (eq bufarg t)
                       (cond
                        ((member "list-windows" args)
                         (insert "1\t1:claude*\n"))
                        ((member "display-message" args)
                         (insert "gastown.mayor\n"))))
                     0)))
          (gascity-terminal--status-install buf "sess" "sock")
          (with-current-buffer buf
            (should (member '("-L" "sock" "set-option" "-t" "sess" "status" "off")
                            cmds))
            ;; Segment present AND before the trailing fill, or it renders
            ;; off-screen (gce-hjj regression: appending after
            ;; `mode-line-end-spaces' hid it).
            (let ((seg (member gascity-terminal--status-mode-line-segment
                               mode-line-format))
                  (end (member 'mode-line-end-spaces mode-line-format)))
              (should seg)
              (should end)
              (should (> (length seg) (length end))))
            (should (timerp gascity-terminal--status-timer))
            (should (equal gascity-terminal--status-session "sess"))
            (should (stringp gascity-terminal--status-string)))
          ;; Killing the buffer must revert the override, scoped to the session.
          (setq cmds nil)
          (kill-buffer buf)
          (should (member '("-L" "sock" "set-option" "-t" "sess" "-u" "status")
                          cmds)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-terminal-attach-honours-status-toggle ()
  "`gascity-terminal-attach-tmux' installs the status mirror only when
`gascity-terminal-mode-line-status' is non-nil."
  (let ((buf (generate-new-buffer "*gc-agent-toggle*")) installed)
    (unwind-protect
        (cl-letf (((symbol-function 'gascity-terminal-tmux-session-exists-p)
                   (lambda (&rest _) t))
                  ((symbol-function 'gascity-terminal-run)
                   (lambda (&rest _) buf))
                  ((symbol-function 'gascity-terminal--status-install)
                   (lambda (&rest _) (setq installed t))))
          (let ((gascity-terminal-mode-line-status t))
            (setq installed nil)
            (gascity-terminal-attach-tmux "sess" "sock" nil)
            (should installed))
          (let ((gascity-terminal-mode-line-status nil))
            (setq installed nil)
            (gascity-terminal-attach-tmux "sess" "sock" nil)
            (should-not installed)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest gascity-test-agent-dired-prefers-recorded-work-dir ()
  "A recorded `:work-dir' is used directly, without a tmux pane query."
  (let (opened)
    (cl-letf (((symbol-function 'dired) (lambda (d) (setq opened d)))
              ((symbol-function 'file-directory-p) (lambda (_) t))
              ((symbol-function 'gascity-terminal-pane-cwd)
               (lambda (&rest _) (error "pane cwd must not be queried"))))
      (gascity-agent-dired (gascity-test--agent :name "a" :work-dir "/wd" :session-name "tm"))
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
      (gascity-agent-dired (gascity-test--agent :name "a" :work-dir "" :session-name "tm"
                                                :socket "sock"))
      (should (equal opened "/live/pane"))
      (should (equal pane-args '("tm" "sock"))))))

(ert-deftest gascity-test-agent-dired-errors-when-unresolvable ()
  "With neither a recorded nor a live working directory, signal a `user-error'."
  (cl-letf (((symbol-function 'gascity-terminal-pane-cwd) (lambda (&rest _) nil)))
    (should-error (gascity-agent-dired (gascity-test--agent :name "a" :session-name "tm"))
                  :type 'user-error)))

;;; gce-x0c — `d' on a rig header opens its directory

(ert-deftest gascity-test-rig-dired-opens-path ()
  "`gascity-rig-dired' opens Dired on an existing rig directory."
  (let (opened)
    (cl-letf (((symbol-function 'dired) (lambda (d) (setq opened d)))
              ((symbol-function 'file-directory-p) (lambda (_) t)))
      (gascity-rig-dired "gascity.el" "/home/roman/workspace/gascity.el")
      (should (equal opened "/home/roman/workspace/gascity.el")))))

(ert-deftest gascity-test-rig-dired-errors-without-path ()
  "A rig with no recorded directory no-ops gracefully with a `user-error'."
  (cl-letf (((symbol-function 'dired) (lambda (&rest _) (error "dired must not run"))))
    (should-error (gascity-rig-dired "hq" nil) :type 'user-error)
    (should-error (gascity-rig-dired "hq" "") :type 'user-error)))

(ert-deftest gascity-test-rig-dired-errors-when-missing ()
  "A recorded directory that is absent on disk signals a `user-error'."
  (cl-letf (((symbol-function 'file-directory-p) (lambda (_) nil))
            ((symbol-function 'dired) (lambda (&rest _) (error "dired must not run"))))
    (should-error (gascity-rig-dired "r" "/nope") :type 'user-error)))

(ert-deftest gascity-test-dired-at-point-routes-agent-and-rig ()
  "`d' reuses one action: an agent row opens its worktree, a rig header its
directory; neither at point is a clean `user-error' (gce-x0c)."
  ;; Agent row -> agent worktree (the agent at point wins).
  (let (opened)
    (cl-letf (((symbol-function 'dired) (lambda (d) (setq opened d)))
              ((symbol-function 'file-directory-p) (lambda (_) t)))
      (with-temp-buffer
        (insert (propertize "agent"
                            'gascity-agent (gascity-test--agent :name "r/a" :work-dir "/wd" :session-name "tm")))
        (goto-char (point-min))
        (gascity-dired-at-point)
        (should (equal opened "/wd")))))
  ;; Rig header -> rig directory.
  (let (opened)
    (cl-letf (((symbol-function 'dired) (lambda (d) (setq opened d)))
              ((symbol-function 'file-directory-p) (lambda (_) t)))
      (with-temp-buffer
        (insert (propertize "▼ rig" 'gascity-rig "rig" 'gascity-rig-dir "/rig/dir"))
        (goto-char (point-min))
        (gascity-dired-at-point)
        (should (equal opened "/rig/dir")))))
  ;; Neither -> clean error, not a backtrace.
  (with-temp-buffer
    (insert "plain")
    (goto-char (point-min))
    (should-error (gascity-dired-at-point) :type 'user-error)))

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

(ert-deftest gascity-test-error-detail ()
  "Error detail prefers gc's stderr, falling back to the message."
  (should (equal (gascity-error-detail
                  '(gascity-command-error "msg" :command "c" :stderr "  rig not found  "))
                 "rig not found"))
  (should (equal (gascity-error-detail
                  '(gascity-command-error "the message" :command "c" :stderr ""))
                 "the message"))
  ;; The refresh path catches the base `gascity-error', so a subclass
  ;; without a :stderr (e.g. a JSON parse error) must still degrade to its
  ;; clean message rather than the raw condition plist.
  (should (equal (gascity-error-detail
                  '(gascity-json-parse-error "Failed to parse gc JSON output: bad"
                                             :input "{bad" :parse-error nil))
                 "Failed to parse gc JSON output: bad")))

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

;;; `q' buries in the vui views (gce-0d5)

(ert-deftest gascity-test-vui-q-buries ()
  "`q' buries in every vui view rather than self-inserting (gce-0d5).
Regression: the vui keymap chain (`gascity-section-mode-map' ->
`beads-section-mode-map' -> `vui-mode-map' -> `widget-keymap') bound no
`q', so pressing it in the status dashboard, rig dashboard, or
session/polecat detail fell through to the global `self-insert-command'
and errored \"Text is read-only\" — even though every view's header line
promises \"q bury\".  `gascity-section-mode' binds `q' to `quit-window'
and the three derived views inherit it.  Resolving the real key with
`key-binding' (not peeking the mode map) is what catches the global
fall-through a future vui change could reintroduce."
  ;; gascity owns the binding directly: looked up through
  ;; `gascity-section-mode-map' it resolves to `quit-window', shadowing
  ;; whatever the vui chain happens to bind `q' to (or leaves unbound).
  ;; This is what makes the fix independent of the loaded vui build.
  (should (eq (keymap-lookup gascity-section-mode-map "q") #'quit-window))
  (dolist (mode '(gascity-section-mode
                  gascity-dashboard-mode
                  gascity-rig-dashboard-mode
                  gascity-session-detail-mode))
    (with-temp-buffer
      (funcall mode)
      (let ((binding (key-binding (kbd "q"))))
        (should (eq binding #'quit-window))
        (should-not (eq binding #'self-insert-command))))))

;;; Bead-UI delegation / store scoping (DESIGN.md §4.3, §9.1)

(ert-deftest gascity-test-beads-id-prefix ()
  "A bead id's store prefix is the text before the first hyphen."
  (should (equal (gascity-beads--id-prefix "gce-afq") "gce"))
  (should (equal (gascity-beads--id-prefix "bl-1jp") "bl"))
  (should (equal (gascity-beads--id-prefix "exc-12ab") "exc"))
  (should (null (gascity-beads--id-prefix "noprefix")))
  (should (null (gascity-beads--id-prefix "")))
  (should (null (gascity-beads--id-prefix nil))))

(ert-deftest gascity-test-beads-rig-path-from-object ()
  "A `gascity-rig''s store directory is its `path', a directory name."
  (should (equal (gascity-beads--rig-path
                  (gascity-domain-decode 'gascity-rig
                                         '((name . "gascity.el")
                                           (path . "/home/x/gascity.el")
                                           (prefix . "gce"))))
                 "/home/x/gascity.el/"))
  (should (null (gascity-beads--rig-path
                 (gascity-domain-decode 'gascity-rig '((name . "x") (path))))))
  (should (null (gascity-beads--rig-path
                 (gascity-domain-decode 'gascity-rig '((name . "x") (path . "")))))))

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
               (lambda (id &rest _) (setq seen-id id seen-dir default-directory))))
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

(ert-deftest gascity-test-bead-show-passes-directory ()
  "`gascity-bead-show' makes beads.el resolve the store with `--directory' (-C).
beads.el's cwd-mode `bd' can be misrouted by the shared Dolt server, so the
store is handed to `beads-show' via its `:directory' keyword, which forwards
it to `bd' as -C — this is what lets a city-level convoy open (gce-bhr)."
  (let (seen-dir seen-directory)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "example-town-cl") (path . "/r/bs") (prefix . "bs"))]))))
              ;; Capture the directory beads.el runs in (for buffer naming) and
              ;; the `:directory' it is told to scope `bd' to.
              ((symbol-function 'beads-show)
               (lambda (_id &rest args)
                 (setq seen-dir default-directory
                       seen-directory (plist-get args :directory)))))
      (gascity-bead-show "bs-0q2z")
      ;; Buffer stays scoped to the prefix-routed store for naming...
      (should (equal seen-dir "/r/bs/"))
      ;; ...and the show carries `:directory' so `bd' uses -C, not cwd-mode.
      (should (equal seen-directory "/r/bs/")))))

(ert-deftest gascity-test-rig-beads-scopes-default-directory ()
  "`gascity-rig-beads' opens the board with `default-directory' at the store."
  (let (seen-dir)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))]))))
              ((symbol-function 'beads-dashboard)
               (lambda (&rest args)
                 (setq seen-dir (or (plist-get args :directory) default-directory)))))
      (gascity-rig-beads "gascity.el")
      (should (equal seen-dir "/r/gce/"))
      ;; A `gascity-rig' works directly, no rig-list lookup needed.
      (setq seen-dir nil)
      (gascity-rig-beads (gascity-domain-decode
                          'gascity-rig '((name . "x") (path . "/r/x") (prefix . "x"))))
      (should (equal seen-dir "/r/x/")))))

(ert-deftest gascity-test-rig-beads-unresolved-errors ()
  "`gascity-rig-beads' errors when the rig's store cannot be resolved."
  (cl-letf (((symbol-function 'gascity-command-rig-list!)
             (lambda (&rest _) '((rigs . [])))))
    (should-error (gascity-rig-beads "ghost") :type 'user-error)))

;;; gce-3ip — `b' opens the beads board (rig store, or agent worktree)

(ert-deftest gascity-test-agent-beads-scopes-worktree ()
  "`gascity-agent-beads' opens the board with `default-directory' at the
agent's recorded worktree, without querying the tmux pane."
  (let (seen-dir)
    (cl-letf (((symbol-function 'file-directory-p) (lambda (_) t))
              ((symbol-function 'gascity-terminal-pane-cwd)
               (lambda (&rest _) (error "pane cwd must not be queried")))
              ((symbol-function 'beads-dashboard)
               (lambda (&rest args)
                 (setq seen-dir (or (plist-get args :directory) default-directory)))))
      (gascity-agent-beads (gascity-test--agent :name "r/a" :work-dir "/wd" :session-name "tm"))
      (should (equal seen-dir "/wd/")))))

(ert-deftest gascity-test-agent-beads-falls-back-to-pane-cwd ()
  "With no recorded work-dir, the board scopes to the live tmux pane cwd."
  (let (seen-dir pane-args)
    (cl-letf (((symbol-function 'file-directory-p) (lambda (_) t))
              ((symbol-function 'gascity-terminal-pane-cwd)
               (lambda (session socket)
                 (setq pane-args (list session socket))
                 "/live/pane"))
              ((symbol-function 'beads-dashboard)
               (lambda (&rest args)
                 (setq seen-dir (or (plist-get args :directory) default-directory)))))
      (gascity-agent-beads (gascity-test--agent :name "a" :work-dir "" :session-name "tm" :socket "sock"))
      (should (equal seen-dir "/live/pane/"))
      (should (equal pane-args '("tm" "sock"))))))

(ert-deftest gascity-test-agent-beads-errors-when-unresolvable ()
  "With neither a recorded nor a live working directory, signal a `user-error'."
  (cl-letf (((symbol-function 'gascity-terminal-pane-cwd) (lambda (&rest _) nil))
            ((symbol-function 'beads-dashboard)
             (lambda () (error "board must not open"))))
    (should-error (gascity-agent-beads (gascity-test--agent :name "a" :session-name "tm"))
                  :type 'user-error)))

(ert-deftest gascity-test-beads-at-point-routes-agent-and-rig ()
  "`b' reuses one action: an agent row opens its worktree's beads, a rig
header the rig's store; neither at point is a clean `user-error' (gce-3ip)."
  ;; Agent row -> the agent's worktree (the agent at point wins over its rig).
  (let (seen-dir)
    (cl-letf (((symbol-function 'file-directory-p) (lambda (_) t))
              ((symbol-function 'gascity-terminal-pane-cwd)
               (lambda (&rest _) (error "pane cwd must not be queried")))
              ((symbol-function 'beads-dashboard)
               (lambda (&rest args)
                 (setq seen-dir (or (plist-get args :directory) default-directory)))))
      (with-temp-buffer
        (insert (propertize "agent"
                            'gascity-agent (gascity-test--agent
                                            :name "rig/a" :rig "rig"
                                            :work-dir "/wd" :session-name "tm")))
        (goto-char (point-min))
        (gascity-beads-at-point)
        (should (equal seen-dir "/wd/")))))
  ;; Rig header -> the rig's store.
  (let (seen-dir)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "rig") (path . "/rig/store") (prefix . "r"))]))))
              ((symbol-function 'beads-dashboard)
               (lambda (&rest args)
                 (setq seen-dir (or (plist-get args :directory) default-directory)))))
      (with-temp-buffer
        (insert (propertize "▼ rig" 'gascity-rig "rig"))
        (goto-char (point-min))
        (gascity-beads-at-point)
        (should (equal seen-dir "/rig/store/")))))
  ;; Neither -> clean error, not a backtrace.
  (with-temp-buffer
    (insert "plain")
    (goto-char (point-min))
    (should-error (gascity-beads-at-point) :type 'user-error)))

(ert-deftest gascity-test-status-dashboard-binds-b-to-beads ()
  "`b' in the status dashboard opens the context-sensitive beads board (gce-3ip)."
  (should (eq (keymap-lookup gascity-dashboard-mode-map "b")
              #'gascity-beads-at-point)))

(ert-deftest gascity-test-rig-db-for-prefix ()
  "The rig's Dolt database is matched on its bead prefix."
  (let ((dbs [((name . "hq")) ((name . "gce") (commits . 5)) ((name . "beads"))]))
    (should (equal (alist-get 'commits (gascity-rig--db-for-prefix dbs "gce")) 5))
    (should (null (gascity-rig--db-for-prefix dbs "nope")))
    (should (null (gascity-rig--db-for-prefix dbs nil)))
    (should (null (gascity-rig--db-for-prefix dbs "")))))

(ert-deftest gascity-test-rig-dolt-vnode ()
  "The rig dashboard Dolt line shows commits but not `open_beads' (gce-ziz).
`gc dolt health' reports `open_beads' as 0 for every database, so showing
it here contradicted the Ready/In-progress sections rendered just above.
The Dolt commit count stays; open-bead counts live in the bead sections,
which read live `bd' data.  The field is dropped regardless of its value,
so a non-zero `open_beads' here must still not surface."
  (let ((text (gascity-test--vnode-text
               (gascity-rig--dolt-vnode
                '((name . "gce") (commits . 225) (open_beads . 7))
                '(:status ready)))))
    (should (string-match-p "gce: 225 commits" text))
    (should-not (string-match-p "open beads" text))
    (should-not (string-match-p "\\b7\\b" text)))
  ;; No database for the rig → dim placeholder, still no bead count.
  (let ((text (gascity-test--vnode-text
               (gascity-rig--dolt-vnode nil '(:status ready)))))
    (should (string-match-p "no database" text))
    (should-not (string-match-p "open beads" text))))

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
                  (gascity-test--agent :name "gascity.el/gastown.furiosa"
                                       :session-name "gastown__polecat-bl-xyz"))
                 '("gascity.el/gastown.furiosa" "gastown__polecat-bl-xyz")))
  (should (equal (gascity-session--assignee-keys
                  (gascity-test--agent :name "a" :session-name "a")) '("a")))
  (should (equal (gascity-session--assignee-keys
                  (gascity-test--agent :name "a" :session-name "")) '("a")))
  (should (null (gascity-session--assignee-keys (gascity-test--agent :name nil)))))

(ert-deftest gascity-test-session-bead-args ()
  "Per-key bead args filter server-side by assignee and scope to the rig."
  (should (equal (gascity-session--bead-args "k" "gascity.el")
                 '("bd" "list" "--assignee" "k" "--rig" "gascity.el"
                   "--status" "open,in_progress,blocked,deferred,closed"
                   "--sort" "updated" "--reverse" "--limit" "50")))
  ;; A nil rig drops the --rig scope.
  (should-not (member "--rig" (gascity-session--bead-args "k" nil))))

(ert-deftest gascity-test-session-worked-args ()
  "Worked-history args select beads carrying a `work_dir', newest first.
This is the read that recovers a polecat's handed-off work, which no longer
matches its assignee."
  (should (equal (gascity-session--worked-args "gascity.el")
                 '("bd" "list" "--has-metadata-key" "work_dir" "--rig" "gascity.el"
                   "--status" "open,in_progress,blocked,deferred,closed"
                   "--sort" "updated" "--reverse" "--limit" "100")))
  ;; A nil rig drops the --rig scope.
  (should-not (member "--rig" (gascity-session--worked-args nil))))

(ert-deftest gascity-test-session-worked-here-p ()
  "A bead is the agent's history when its `work_dir' is within the agent's.
The match is by directory boundary, so a sibling agent sharing a name prefix
never counts, and a missing or empty path on either side never matches."
  (let* ((base "/w/.gc/worktrees/r/polecats/gastown.furiosa")
         (with-wd (lambda (wd) `((metadata . ((work_dir . ,wd)))))))
    ;; Nested under the agent's worktree — its handed-off work.
    (should (gascity-session--worked-here-p
             (funcall with-wd (concat base "/worktrees/gce-cu7")) base))
    ;; The agent's worktree itself.
    (should (gascity-session--worked-here-p (funcall with-wd base) base))
    ;; A sibling agent sharing a name prefix must not match.
    (should-not (gascity-session--worked-here-p
                 (funcall with-wd "/w/.gc/worktrees/r/polecats/gastown.furiosa-2/worktrees/z")
                 base))
    ;; Unrelated path, missing metadata, empty/nil paths: never a match.
    (should-not (gascity-session--worked-here-p (funcall with-wd "/elsewhere/x") base))
    (should-not (gascity-session--worked-here-p '((id . "n")) base))
    (should-not (gascity-session--worked-here-p (funcall with-wd "") base))
    (should-not (gascity-session--worked-here-p (funcall with-wd "/a") ""))
    (should-not (gascity-session--worked-here-p (funcall with-wd "/a") nil))))

(ert-deftest gascity-test-session-handed-off-work-surfaces-in-history ()
  "A polecat's finished bead lands in history even though it was handed off.
The closed bead, reassigned to the refinery, matches no assignee key — only
its `work_dir' nests under the agent's worktree.  By assignee alone history
would be empty; the worktree read is what surfaces it, while the open hook
bead (matched by assignee) stays on the hook."
  (let* ((work-dir "/w/polecats/gastown.furiosa")
         ;; Open hook bead, found via the runtime-session assignee key.
         (by-assignee (list '((id . "hook") (status . "in_progress"))))
         ;; Worktree read returns every bead with a `work_dir'; only the one
         ;; built under this agent survives the client-side filter.
         (raw-worked
          (list `((id . "done") (status . "closed")
                  (metadata . ((work_dir . ,(concat work-dir "/worktrees/done")))))
                '((id . "other") (status . "closed")
                  (metadata . ((work_dir . "/w/polecats/gastown.max/worktrees/o"))))))
         (worked (seq-filter (lambda (b) (gascity-session--worked-here-p b work-dir))
                             raw-worked))
         (merged (gascity-session--merge-beads (list by-assignee nil worked))))
    (should (equal (mapcar (lambda (b) (alist-get 'id b)) worked) '("done")))
    (should (equal (mapcar (lambda (b) (alist-get 'id b))
                           (gascity-session--hook-beads merged))
                   '("hook")))
    (should (equal (mapcar (lambda (b) (alist-get 'id b))
                           (gascity-session--history-beads merged 10))
                   '("done")))))

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
  (let ((run (gascity-domain-decode 'gascity-rig '((name . "a") (running . t))))
        (susp (gascity-domain-decode 'gascity-rig '((name . "b") (suspended . t))))
        (stop (gascity-domain-decode 'gascity-rig '((name . "c")))))
    (should (gascity-rig-list--match-p run nil))
    (should (gascity-rig-list--match-p run "running"))
    (should-not (gascity-rig-list--match-p run "suspended"))
    (should (gascity-rig-list--match-p susp "suspended"))
    (should (gascity-rig-list--match-p stop "stopped"))
    (should-not (gascity-rig-list--match-p stop "running"))))

(ert-deftest gascity-test-session-filter-match ()
  "Session rig filter is a case-insensitive substring; nil/empty match all."
  (let ((s (gascity-domain-decode 'gascity-session '((rig . "gascity.el")))))
    (should (gascity-session-list--match-p s nil))
    (should (gascity-session-list--match-p s ""))
    (should (gascity-session-list--match-p s "gascity"))
    (should (gascity-session-list--match-p s "GASCITY"))
    (should-not (gascity-session-list--match-p s "guix"))))

(ert-deftest gascity-test-convoy-filter-match ()
  "Convoy status filter matches the `status' field exactly; nil matches all."
  (let ((c (gascity-domain-decode 'gascity-convoy '((id . "x") (status . "open")))))
    (should (gascity-convoy-list--match-p c nil))
    (should (gascity-convoy-list--match-p c "open"))
    (should-not (gascity-convoy-list--match-p c "closed"))))

(ert-deftest gascity-test-mail-filter-match ()
  "Mail unread-only filter keeps unread messages; nil keeps all.
Unread is the negation of the v1 `read' boolean (gc decodes `false' to nil)."
  (let ((unread (gascity-domain-decode 'gascity-mail '((read . nil))))
        (seen (gascity-domain-decode 'gascity-mail '((read . t)))))
    (should (gascity-mail-inbox--match-p unread nil))
    (should (gascity-mail-inbox--match-p seen nil))
    (should (gascity-mail-inbox--match-p unread t))
    (should-not (gascity-mail-inbox--match-p seen t))))

(ert-deftest gascity-test-mail-entry ()
  "A mail entry reads the v1 schema keys and marks unread rows.
`from'/`subject'/`created_at' (date + time) become the columns, the typed
message is the id, and a non-`read' message shows the ● marker."
  (let* ((message (gascity-domain-decode
                   'gascity-mail
                   '((id . "msg-1") (from . "mayor/") (to . "gce/furiosa")
                     (subject . "Re: status") (body . "...")
                     (created_at . "2026-06-01T19:18:18Z") (read . nil))))
         (entry (gascity-mail-inbox--entry message)))
    (should (eq (car entry) message))
    (should (gascity-mail-p (car entry)))
    (should (equal (gascity-test--plain-cols entry)
                   '("mayor/" "Re: status" "2026-06-01 19:18" "●"))))
  ;; A read message clears the marker.
  (should (equal (nth 3 (gascity-test--plain-cols
                         (gascity-mail-inbox--entry
                          (gascity-domain-decode
                           'gascity-mail
                           '((from . "a") (subject . "s")
                             (created_at . "2026-06-01T00:00:00Z") (read . t))))))
                 "")))

(ert-deftest gascity-test-order-filter-match ()
  "Order filter ANDs enabled-only and exact type; nil/empty values match all."
  (let ((on (gascity-domain-decode 'gascity-order '((enabled . t) (type . "schedule"))))
        (off (gascity-domain-decode 'gascity-order '((enabled) (type . "cooldown")))))
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

;;; Filter mode-line indicator (gce-ey4)

(ert-deftest gascity-test-tabulated-format-filter ()
  "Filter plists render to a mode-line description (gce-ey4).
A string value shows as \"key=value\", a boolean t as the bare key, a nil
value is skipped, and an empty or all-nil plist yields nil (no indicator,
so an unfiltered list stays clean)."
  (should (null (gascity-tabulated--format-filter nil)))
  (should (null (gascity-tabulated--format-filter '(:state nil))))
  (should (equal (gascity-tabulated--format-filter '(:status "running"))
                 "status=running"))
  ;; The session list's combined state + rig filter (the bug's example).
  (should (equal (gascity-tabulated--format-filter '(:state "active" :rig "gascity"))
                 "state=active rig=gascity"))
  ;; Boolean flags (mail :unread, order :enabled) show as the bare key.
  (should (equal (gascity-tabulated--format-filter '(:unread t)) "unread"))
  (should (equal (gascity-tabulated--format-filter '(:enabled t :type "schedule"))
                 "enabled type=schedule"))
  ;; A nil value among real ones is dropped, not rendered as a bare "key=".
  (should (equal (gascity-tabulated--format-filter '(:state "active" :rig nil))
                 "state=active")))

(ert-deftest gascity-test-tabulated-refresh-shows-filter-in-mode-name ()
  "An active filter is appended to the mode line; none leaves it clean (gce-ey4).
Regression: a filtered list read identically to a complete one
\(\"Things [1/1]\"), so a partial view could be mistaken for the whole.
The active filter plist threads through `gascity-tabulated--refresh', and
its description is shown after the page indicator and re-derived on every
refresh — so it tracks the filter across `g' and clears with `/ c'."
  (with-temp-buffer
    (tabulated-list-mode)
    (setq-local tabulated-list-format [("Col" 10 t)])
    (tabulated-list-init-header)
    ;; No filter -> just the page indicator, and no stored description.
    (gascity-tabulated--refresh "Things" (lambda () nil))
    (should (equal mode-name "Things [1/1]"))
    (should (null gascity-tabulated--filter-description))
    ;; A filter -> its description appended in parens, page indicator intact.
    (gascity-tabulated--refresh "Things" (lambda () nil)
                                '(:state "active" :rig "gascity"))
    (should (equal mode-name "Things [1/1] (state=active rig=gascity)"))
    ;; A later filter-free refresh (mirrors `/ c') drops the suffix again.
    (gascity-tabulated--refresh "Things" (lambda () nil))
    (should (equal mode-name "Things [1/1]"))
    (should (null gascity-tabulated--filter-description))))

;;; gce-xkr — N/P jump between top-level sections (city/rig/…)

(defun gascity-test--section-labels (vnode)
  "Return the text of VNODE-subtree nodes carrying the `gascity-section' prop.
Walks the vnode tree the dashboards build and collects the content of
every text node stamped as a navigable section header — so a test can
assert which headers a render helper marks, without mounting a buffer."
  (cond
   ((null vnode) nil)
   ((vui-vnode-text-p vnode)
    (and (plist-get (vui-vnode-text-properties vnode) 'gascity-section)
         (list (vui-vnode-text-content vnode))))
   ((vui-vnode-vstack-p vnode)
    (mapcan #'gascity-test--section-labels (vui-vnode-vstack-children vnode)))
   ((vui-vnode-hstack-p vnode)
    (mapcan #'gascity-test--section-labels (vui-vnode-hstack-children vnode)))
   ((vui-vnode-fragment-p vnode)
    (mapcan #'gascity-test--section-labels (vui-vnode-fragment-children vnode)))
   (t nil)))

(ert-deftest gascity-test-section-nav-walks-headers ()
  "`N'/`P' jump between `gascity-section' headers and stop (no wrap) at the ends.
Stands in for a rendered dashboard: header lines carry the
`gascity-section' text property; content and footer rows do not.  From a
content row, `P' lands on the section above and `N' on the one below."
  (with-temp-buffer
    (insert (propertize "City" 'gascity-section t) "\n")
    (insert "  o agent\n")
    (insert (propertize "rig-a" 'gascity-section t) "\n")
    (insert "  o pol\n")
    (insert (propertize "rig-b" 'gascity-section t) "\n")
    (insert "footer (not a section)\n")
    (cl-flet ((line () (string-trim (thing-at-point 'line t))))
      ;; Forward from the first header, stopping at the last.
      (goto-char (point-min))
      (should (equal (line) "City"))
      (gascity-section-next) (should (equal (line) "rig-a"))
      (gascity-section-next) (should (equal (line) "rig-b"))
      (should-error (gascity-section-next) :type 'user-error)
      (should (equal (line) "rig-b"))      ; point unmoved when it stops
      ;; Backward, symmetric.
      (gascity-section-previous) (should (equal (line) "rig-a"))
      (gascity-section-previous) (should (equal (line) "City"))
      (should-error (gascity-section-previous) :type 'user-error)
      (should (equal (line) "City"))
      ;; From a content row: `P' -> the section above, `N' -> the one below.
      (goto-char (point-min)) (forward-line 1)
      (should (equal (line) "o agent"))
      (gascity-section-previous) (should (equal (line) "City"))
      (goto-char (point-min)) (forward-line 1)
      (gascity-section-next) (should (equal (line) "rig-a"))
      ;; From the footer (below the last header): `P' -> last header, `N' stops.
      (goto-char (point-max))
      (gascity-section-previous) (should (equal (line) "rig-b"))
      (goto-char (point-max))
      (should-error (gascity-section-next) :type 'user-error))))

(ert-deftest gascity-test-section-headers-stamped ()
  "Each dashboard stamps its top-level header lines with `gascity-section'.
This is what `gascity-section-next'/`-previous' walk, so a missing stamp
silently drops a section from N/P navigation."
  ;; Rig dashboard: header, agents, beads, orders, dolt.
  (should (equal (gascity-test--section-labels
                  (gascity-rig--header-vnode '((name . "gce")) "bl"))
                 '("Rig:")))
  (should (equal (gascity-test--section-labels
                  (gascity-rig--agents-vnode
                   [] "gce" (make-hash-table :test 'equal) nil))
                 '("Agents (0)")))
  (should (equal (gascity-test--section-labels
                  (gascity-rig--beads-section "Ready" nil '(:status ready)))
                 '("Ready (0)")))
  (should (equal (gascity-test--section-labels
                  (gascity-rig--orders-vnode nil '(:status ready)))
                 '("Orders (0)")))
  (should (equal (gascity-test--section-labels
                  (gascity-rig--dolt-vnode nil '(:status ready)))
                 '("Dolt")))
  ;; Session/polecat detail: state header + the two bead sections.
  (should (equal (gascity-test--section-labels
                  (gascity-session--state-vnode (gascity-test--agent :name "rig/agent") nil))
                 '("Agent:")))
  (should (equal (gascity-test--section-labels
                  (gascity-session--beads-section "On hook" nil 'ready ""))
                 '("On hook (0)")))
  ;; Status dashboard header (the city line).
  (should (equal (gascity-test--section-labels
                  (gascity-status--header-vnode '((city_name . "bl"))))
                 '("Gas City:"))))

(ert-deftest gascity-test-section-nav-keys ()
  "`N'/`P' are section nav in the shared map; dashboards inherit them, nudge -> `M'.
The at-point nudge that lived on `N' moves to `M' (Message) so `N'/`P'
can be section navigation, bound once on the shared parent map and
inherited by every vui dashboard.  The flat session list has no sections,
so it only relocates nudge to `M' (it does not inherit the shared map)."
  ;; Shared parent map binds the navigation directly.
  (should (eq (keymap-lookup gascity-section-mode-map "N") #'gascity-section-next))
  (should (eq (keymap-lookup gascity-section-mode-map "P") #'gascity-section-previous))
  ;; The three vui dashboards inherit N/P (no longer shadowed by nudge) and
  ;; bind the relocated nudge on M.
  (dolist (map (list gascity-dashboard-mode-map
                     gascity-rig-dashboard-mode-map
                     gascity-session-detail-mode-map))
    (should (eq (keymap-lookup map "N") #'gascity-section-next))
    (should (eq (keymap-lookup map "P") #'gascity-section-previous))
    (should (eq (keymap-lookup map "M") #'gascity-session-nudge-at-point)))
  ;; The session list keeps nudge reachable (on M) but binds no section nav.
  (should (eq (keymap-lookup gascity-session-list-mode-map "M")
              #'gascity-session-nudge-at-point))
  (should-not (eq (keymap-lookup gascity-session-list-mode-map "N")
                  #'gascity-session-nudge-at-point)))


;;; gce-3n8 — `n'/`p' are next/previous line/item uniformly; peek off `p'

(ert-deftest gascity-test-np-line-movement-uniform ()
  "`n'/`p' move next/previous line/item in every dashboard mode (gce-3n8).
The three vui dashboards inherit `n'/`p' from the shared
`gascity-section-mode-map' — the fine-grained counterpart to the `N'/`P'
section jumps bound beside them — while the flat session list binds them
locally (it does not inherit that map).  No dashboard mode leaves `n'/`p'
meaning anything other than line/item movement."
  ;; The shared parent binds line movement directly, beside `N'/`P'.
  (should (eq (keymap-lookup gascity-section-mode-map "n") #'next-line))
  (should (eq (keymap-lookup gascity-section-mode-map "p") #'previous-line))
  ;; Every dashboard map resolves `n'/`p' to line movement — inherited for
  ;; the vui dashboards, bound locally for the flat session list.
  (dolist (map (list gascity-dashboard-mode-map
                     gascity-rig-dashboard-mode-map
                     gascity-session-detail-mode-map
                     gascity-session-list-mode-map))
    (should (eq (keymap-lookup map "n") #'next-line))
    (should (eq (keymap-lookup map "p") #'previous-line))))

(ert-deftest gascity-test-peek-relocated-off-p ()
  "Peek moves off `p' to `v' wherever `p' used to shadow line movement.
The rig dashboard, session-detail, and session-list maps bound
`gascity-session-peek-at-point' on `p'; that conflicted with the
`p' = previous-line convention, so peek relocates to `v' (gce-3n8).
`p' in those maps no longer peeks."
  (dolist (map (list gascity-rig-dashboard-mode-map
                     gascity-session-detail-mode-map
                     gascity-session-list-mode-map))
    (should (eq (keymap-lookup map "v") #'gascity-session-peek-at-point))
    (should-not (eq (keymap-lookup map "p")
                    #'gascity-session-peek-at-point))))

;;; ============================================================
;;; Write actions — phase 1 (gce-7rs.1)
;;; ============================================================
;;
;; Safe additive + lifecycle-completion verbs and their plumbing
;; (DESIGN-write-actions.md §3, §7, §12 phase 1): bead note (store-routed
;; by `-C'), session reset/undrain, city reload, mail read/archive/
;; mark-read/mark-unread, plus the summarize and refresh-dispatch
;; extensions and the new key bindings.

(ert-deftest gascity-test-write-command-lines ()
  "Phase-1 write verbs derive their positional `gc' lines with `--json' OFF."
  ;; Bead note: positionals then the `-C' store pin when a directory is set.
  (should (equal (gascity-command-line
                  (gascity-command-bd-note :id "gce-1" :text "a note"))
                 '("gc" "bd" "note" "gce-1" "a note")))
  (should (equal (gascity-command-line
                  (gascity-command-bd-note :id "gce-1" :text "a note"
                                           :directory "/r/gce/"))
                 '("gc" "bd" "note" "gce-1" "a note" "-C" "/r/gce/")))
  ;; Session reset / runtime undrain: single positional target.
  (should (equal (gascity-command-line (gascity-command-session-reset :target "rig/a"))
                 '("gc" "session" "reset" "rig/a")))
  (should (equal (gascity-command-line (gascity-command-runtime-undrain :target "rig/a"))
                 '("gc" "runtime" "undrain" "rig/a")))
  ;; City reload: bare, and `--soft' via the flag.
  (should (equal (gascity-command-line (gascity-command-reload)) '("gc" "reload")))
  (should (equal (gascity-command-line (gascity-command-reload :soft t))
                 '("gc" "reload" "--soft")))
  ;; Mail verbs: single positional id; mark-read/unread keep their hyphen.
  (should (equal (gascity-command-line (gascity-command-mail-read :id "m1"))
                 '("gc" "mail" "read" "m1")))
  (should (equal (gascity-command-line (gascity-command-mail-archive :id "m1"))
                 '("gc" "mail" "archive" "m1")))
  (should (equal (gascity-command-line (gascity-command-mail-mark-read :id "m1"))
                 '("gc" "mail" "mark-read" "m1")))
  (should (equal (gascity-command-line (gascity-command-mail-mark-unread :id "m1"))
                 '("gc" "mail" "mark-unread" "m1")))
  ;; No phase-1 write verb emits --json (they report from gc's exit status).
  (dolist (cmd (list (gascity-command-bd-note :id "x" :text "y" :directory "/d/")
                     (gascity-command-session-reset :target "x")
                     (gascity-command-runtime-undrain :target "x")
                     (gascity-command-reload :soft t)
                     (gascity-command-mail-read :id "m")
                     (gascity-command-mail-archive :id "m")
                     (gascity-command-mail-mark-read :id "m")
                     (gascity-command-mail-mark-unread :id "m")))
    (should-not (member "--json" (gascity-command-line cmd)))))

(ert-deftest gascity-test-write-subcommand-derivation ()
  "Phase-1 subcommands derive from class names; hyphenated tokens are pinned."
  (should (equal (gascity-command-subcommand (gascity-command-bd-note)) "bd note"))
  (should (equal (gascity-command-subcommand (gascity-command-session-reset))
                 "session reset"))
  (should (equal (gascity-command-subcommand (gascity-command-runtime-undrain))
                 "runtime undrain"))
  (should (equal (gascity-command-subcommand (gascity-command-reload)) "reload"))
  (should (equal (gascity-command-subcommand (gascity-command-mail-read)) "mail read"))
  ;; `:cli-command' overrides the hyphen-splitting derivation.
  (should (equal (gascity-command-subcommand (gascity-command-mail-mark-read))
                 "mail mark-read"))
  (should (equal (gascity-command-subcommand (gascity-command-mail-mark-unread))
                 "mail mark-unread")))

(ert-deftest gascity-test-write-validation ()
  "Required positionals are enforced before gc is invoked."
  ;; Bead note needs both id and text.
  (should (gascity-command-validate (gascity-command-bd-note :id "gce-1")))
  (should (gascity-command-validate (gascity-command-bd-note :text "x")))
  (should-not (gascity-command-validate (gascity-command-bd-note :id "gce-1" :text "x")))
  ;; Session reset / undrain need a target.
  (should (gascity-command-validate (gascity-command-session-reset)))
  (should-not (gascity-command-validate (gascity-command-session-reset :target "x")))
  (should (gascity-command-validate (gascity-command-runtime-undrain)))
  (should-not (gascity-command-validate (gascity-command-runtime-undrain :target "x")))
  ;; Mail verbs need an id.
  (dolist (cmd (list (gascity-command-mail-read) (gascity-command-mail-archive)
                     (gascity-command-mail-mark-read) (gascity-command-mail-mark-unread)))
    (should (gascity-command-validate cmd)))
  (should-not (gascity-command-validate (gascity-command-mail-read :id "m1")))
  ;; Reload requires nothing.
  (should-not (gascity-command-validate (gascity-command-reload))))

(ert-deftest gascity-test-bd-note-store-routing ()
  "`gascity-bead-note--run' resolves the bead's store and pins it with `-C'.
Reuses `gascity-beads--bead-path' (the read-side gce-bhr routing): a known
id prefix maps to its rig store; an unknown prefix degrades to no `-C', so
gc applies its own prefix/ambient routing."
  (let (line)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))]))))
              ((symbol-function 'gascity-command-execute-interactive)
               (lambda (cmd) (setq line (gascity-command-line cmd))))
              ((symbol-function 'gascity--refresh-current-view) #'ignore))
      (gascity-bead-note--run "gce-afq" "a note")
      (should (equal line '("gc" "bd" "note" "gce-afq" "a note" "-C" "/r/gce/")))
      (gascity-bead-note--run "zz-9" "x")
      (should (equal line '("gc" "bd" "note" "zz-9" "x"))))))

(ert-deftest gascity-test-action-summarize-payloads ()
  "Payload-returning mutations summarise to their action: created / sent.
The specific send/reply and `id'/`issue' shapes win over the generic
`message'/`ok' clauses so a payload that also carries a server `message'
still reads as the action it was (DESIGN-write-actions.md §3.2b)."
  (should (equal (gascity-action--summarize '((id . "gce-9") (ok . t))) "created gce-9"))
  (should (equal (gascity-action--summarize '((issue . ((id . "gce-9"))))) "created gce-9"))
  (should (equal (gascity-action--summarize '((issue . "gce-9"))) "created gce-9"))
  ;; Live `gc mail send/reply --json' carries a top-level `id' (the message
  ;; id) plus `action' "send"/"reply" and NO `message_id'; the action guard
  ;; must beat the `id'->"created" clause so a sent mail reads as "sent".
  (should (equal (gascity-action--summarize
                  '((command . "mail.send") (action . "send") (id . "bl-wisp-1")))
                 "sent"))
  (should (equal (gascity-action--summarize
                  '((command . "mail.reply") (action . "reply") (id . "bl-wisp-2")))
                 "sent"))
  ;; The legacy `message_id' shape is still honoured.
  (should (equal (gascity-action--summarize '((message_id . "x") (message . "Sent to y")))
                 "sent"))
  ;; The pre-existing shapes still summarise as before.
  (should (equal (gascity-action--summarize '((message . "routed"))) "routed"))
  (should (equal (gascity-action--summarize '((ok . t))) "ok")))

(ert-deftest gascity-test-refresh-dispatch-mail-convoy ()
  "`gascity--refresh-current-view' resolves the mail-inbox and convoy modes.
These were the two gaps in the mode-dispatch table (§3.3); a mutation made
from either list now refreshes it in place like every other view."
  (let (refreshed)
    (cl-letf (((symbol-function 'gascity-mail-inbox-refresh)
               (lambda () (setq refreshed 'mail)))
              ((symbol-function 'gascity-convoy-list-refresh)
               (lambda () (setq refreshed 'convoy))))
      (with-temp-buffer
        (gascity-mail-inbox-mode)
        (gascity--refresh-current-view)
        (should (eq refreshed 'mail)))
      (setq refreshed nil)
      (with-temp-buffer
        (gascity-convoy-list-mode)
        (gascity--refresh-current-view)
        (should (eq refreshed 'convoy))))))

(ert-deftest gascity-test-mail-at-point ()
  "`gascity-mail-at-point' narrows to a mail message; `--id-at-point' guards."
  (cl-letf (((symbol-function 'gascity-object-at-point)
             (lambda () (gascity-mail :id "m1"))))
    (should (gascity-mail-p (gascity-mail-at-point)))
    (should (equal (gascity-mail--id-at-point) "m1")))
  ;; A non-mail object at point yields nil / a clean error.
  (cl-letf (((symbol-function 'gascity-object-at-point)
             (lambda () (gascity-test--agent :name "rig/a"))))
    (should (null (gascity-mail-at-point))))
  (cl-letf (((symbol-function 'gascity-mail-at-point) (lambda () nil)))
    (should-error (gascity-mail--id-at-point) :type 'user-error)))

(ert-deftest gascity-test-write-keys-bound ()
  "Write keys land in the right keymaps without shadowing shipped ones.
Reset/undrain reach every agent view; reload is city-level (status
dashboard only); mail verbs live in the inbox.  Phase 2: `c' on the three
bead-bearing vui views opens `gascity-bead-dispatch' (note moved to its
`o'), `S' opens the sling/route transient, and the inbox gains `R' reply
and `c' mail-dispatch."
  (dolist (map (list gascity-dashboard-mode-map gascity-rig-dashboard-mode-map
                     gascity-session-detail-mode-map gascity-session-list-mode-map))
    (should (eq (keymap-lookup map "R") #'gascity-session-reset-at-point))
    (should (eq (keymap-lookup map "U") #'gascity-session-undrain-at-point)))
  ;; `c' is the bead-dispatch menu and `S' the sling transient on the three
  ;; views that carry bead references (not the flat session list).
  (dolist (map (list gascity-dashboard-mode-map gascity-rig-dashboard-mode-map
                     gascity-session-detail-mode-map))
    (should (eq (keymap-lookup map "c") #'gascity-bead-dispatch))
    (should (eq (keymap-lookup map "S") #'gascity-sling-dispatch)))
  (should (eq (keymap-lookup gascity-dashboard-mode-map "L") #'gascity-reload))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "r")
              #'gascity-mail-read-at-point))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "R")
              #'gascity-mail-reply-at-point))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "a")
              #'gascity-mail-archive-at-point))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "u")
              #'gascity-mail-mark-unread-at-point))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "c")
              #'gascity-mail-dispatch))
  ;; `RET' in the inbox stays the cheap cached-field view, not the gc read.
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "RET")
              #'gascity-mail-inbox-show)))

(ert-deftest gascity-test-write-confirm-gating ()
  "Destructive write verbs gate on `yes-or-no-p'; a `no' skips the run."
  ;; Session reset (at point) — `no' answer must not execute.
  (gascity-test--with-agent-at-point
   (lambda ()
     (let (ran)
       (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
                 ((symbol-function 'gascity-command-execute-interactive)
                  (lambda (&rest _) (setq ran t)))
                 ((symbol-function 'gascity--refresh-current-view) #'ignore))
         (gascity-session-reset-at-point)
         (should-not ran)
         ;; A `yes' answer does run it.
         (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
           (gascity-session-reset-at-point)
           (should ran))))))
  ;; Mail archive (at point) — `no' answer must not execute.
  (let (ran)
    (cl-letf (((symbol-function 'gascity-mail-at-point)
               (lambda () (gascity-mail :id "m1")))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil))
              ((symbol-function 'gascity-command-execute-interactive)
               (lambda (&rest _) (setq ran t)))
              ((symbol-function 'gascity--refresh-current-view) #'ignore))
      (gascity-mail-archive-at-point)
      (should-not ran))))

(ert-deftest gascity-test-bd-action-is-abstract ()
  "The `-C' bead-write base is abstract — only concrete verbs instantiate.
Every phase-2 bead verb (close/reopen/assign) inherits the store-routing
base alongside the phase-1 note."
  (should-error (gascity-command-bd-action) :type 'error)
  (dolist (cmd (list (gascity-command-bd-note :id "x" :text "y")
                     (gascity-command-bd-close :id "x")
                     (gascity-command-bd-reopen :id "x")
                     (gascity-command-bd-assign :id "x" :name "y")))
    (should (object-of-class-p cmd 'gascity-command-bd-action))))

;;; Phase 2 — dispatch transients, close/reopen/assign, richer sling, compose

(ert-deftest gascity-test-bd-write-command-lines ()
  "Close/reopen/assign build the right `gc bd' line; `-C' precedes `--reason'."
  (should (equal (gascity-command-line
                  (gascity-command-bd-close :id "gce-1" :reason "done"
                                            :directory "/r/gce/"))
                 '("gc" "bd" "close" "gce-1" "-C" "/r/gce/" "--reason" "done")))
  ;; No reason -> no --reason; nil directory -> no -C.
  (should (equal (gascity-command-line (gascity-command-bd-close :id "gce-1"))
                 '("gc" "bd" "close" "gce-1")))
  (should (equal (gascity-command-line
                  (gascity-command-bd-reopen :id "gce-1" :directory "/r/gce/"))
                 '("gc" "bd" "reopen" "gce-1" "-C" "/r/gce/")))
  (should (equal (gascity-command-line
                  (gascity-command-bd-assign :id "gce-1" :name "rig/x"
                                             :directory "/r/gce/"))
                 '("gc" "bd" "assign" "gce-1" "rig/x" "-C" "/r/gce/"))))

(ert-deftest gascity-test-bd-write-validation ()
  "Phase-2 write verbs reject missing required positionals before gc runs."
  (should (gascity-command-validate (gascity-command-bd-close)))
  (should-not (gascity-command-validate (gascity-command-bd-close :id "x")))
  (should (gascity-command-validate (gascity-command-bd-reopen)))
  (should-not (gascity-command-validate (gascity-command-bd-reopen :id "x")))
  (should (gascity-command-validate (gascity-command-bd-assign :id "x")))
  (should (gascity-command-validate (gascity-command-bd-assign :name "y")))
  (should-not (gascity-command-validate (gascity-command-bd-assign :id "x" :name "y")))
  (should (gascity-command-validate (gascity-command-mail-send)))
  (should-not (gascity-command-validate (gascity-command-mail-send :to "mayor")))
  (should (gascity-command-validate (gascity-command-mail-reply)))
  (should-not (gascity-command-validate (gascity-command-mail-reply :id "m1"))))

(ert-deftest gascity-test-bd-write-store-routing ()
  "Close/reopen/assign resolve the bead store and pin it with `-C', like note.
An empty close reason drops `--reason'; an unknown id prefix degrades to no
`-C' (gc's own prefix/ambient routing)."
  (let (line)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))]))))
              ((symbol-function 'gascity-command-execute-interactive)
               (lambda (cmd) (setq line (gascity-command-line cmd))))
              ((symbol-function 'gascity--refresh-current-view) #'ignore))
      (gascity-bead-close--run "gce-afq" "done")
      (should (equal line '("gc" "bd" "close" "gce-afq" "-C" "/r/gce/" "--reason" "done")))
      (gascity-bead-close--run "gce-afq" "")
      (should (equal line '("gc" "bd" "close" "gce-afq" "-C" "/r/gce/")))
      (gascity-bead-assign--run "gce-afq" "gascity.el/gastown.refinery")
      (should (equal line '("gc" "bd" "assign" "gce-afq"
                            "gascity.el/gastown.refinery" "-C" "/r/gce/")))
      (gascity-bead-reopen--run "zz-9")
      (should (equal line '("gc" "bd" "reopen" "zz-9"))))))

(ert-deftest gascity-test-bd-close-confirm-gating ()
  "`gascity-bead-close-at-point' gates on `yes-or-no-p'; a `no' skips the run."
  (cl-letf (((symbol-function 'gascity-bead-at-point) (lambda () "gce-1"))
            ((symbol-function 'gascity-beads--bead-path) (lambda (_) nil))
            ((symbol-function 'read-string) (lambda (&rest _) "because"))
            ((symbol-function 'gascity--refresh-current-view) #'ignore))
    (let (ran)
      (cl-letf (((symbol-function 'gascity-command-execute-interactive)
                 (lambda (&rest _) (setq ran t)))
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (gascity-bead-close-at-point)
        (should-not ran)
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
          (gascity-bead-close-at-point)
          (should ran))))))

(ert-deftest gascity-test-sling-rich-command-line ()
  "Sling emits every new infix in declaration order; defaults stay off.
`--var' becomes a repeated flag (gc's stringArray); `--merge'/`--title'
take a value; the booleans are absent unless set."
  (should (equal
           (gascity-command-line
            (gascity-command-sling :target "t" :arg "b" :formula t :nudge t
                                   :no-convoy t :reassign t :merge "direct"
                                   :title "Root" :var '("a=1" "b=2") :dry-run t))
           '("gc" "sling" "t" "b" "--formula" "--nudge" "--no-convoy"
             "--reassign" "--merge" "direct" "--title" "Root"
             "--var" "a=1" "--var" "b=2" "--dry-run")))
  (should (equal (gascity-command-line (gascity-command-sling :target "t" :arg "b"))
                 '("gc" "sling" "t" "b")))
  (should (equal (gascity-command-line
                  (gascity-command-sling :target "t" :arg "b" :merge "mr"))
                 '("gc" "sling" "t" "b" "--merge" "mr")))
  ;; A single var still emits one --var pair.
  (should (equal (gascity-command-line
                  (gascity-command-sling :target "t" :arg "b" :var '("k=v")))
                 '("gc" "sling" "t" "b" "--var" "k=v"))))

(ert-deftest gascity-test-sling-parse-transient-args ()
  "The pure transient-arg parser maps switches/options to sling initargs."
  (let ((p (gascity-sling--parse-transient-args
            '("--formula" "--no-convoy" "--reassign" "--nudge"
              "--merge=direct" "--title=Root" "--var=a=1" "--var=b=2"))))
    (should (eq (plist-get p :formula) t))
    (should (eq (plist-get p :no-convoy) t))
    (should (eq (plist-get p :reassign) t))
    (should (eq (plist-get p :nudge) t))
    (should (equal (plist-get p :merge) "direct"))
    (should (equal (plist-get p :title) "Root"))
    (should (equal (plist-get p :var) '("a=1" "b=2"))))
  ;; Empty -> empty plist; unknown entries ignored.
  (should (null (gascity-sling--parse-transient-args nil)))
  (should (null (gascity-sling--parse-transient-args '("--bogus"))))
  ;; Parsed args drive a real command line end to end.
  (should (equal (gascity-command-line
                  (apply #'gascity-command-sling :target "t" :arg "b"
                         (gascity-sling--parse-transient-args
                          '("--formula" "--merge=local" "--var=x=1"))))
                 '("gc" "sling" "t" "b" "--formula" "--merge" "local" "--var" "x=1"))))

(ert-deftest gascity-test-order-run-rig ()
  "Order run emits `--rig' only when a rig is supplied (DESIGN §11 #9)."
  (should (equal (gascity-command-line (gascity-command-order-run :name "o1"))
                 '("gc" "order" "run" "o1")))
  (should (equal (gascity-command-line
                  (gascity-command-order-run :name "o1" :rig "gascity.el"))
                 '("gc" "order" "run" "o1" "--rig" "gascity.el"))))

(ert-deftest gascity-test-mail-compose-command-lines ()
  "Mail send/reply request JSON (for the `sent' summary) and carry s/m."
  (should (equal (gascity-command-line
                  (gascity-command-mail-send :to "mayor" :subject "Hi" :message "yo"))
                 '("gc" "mail" "send" "mayor" "--json" "--subject" "Hi"
                   "--message" "yo")))
  (should (equal (gascity-command-line
                  (gascity-command-mail-reply :id "m1" :subject "RE" :message "yo"))
                 '("gc" "mail" "reply" "m1" "--json" "--subject" "RE"
                   "--message" "yo")))
  (should (equal (gascity-command-subcommand (gascity-command-mail-send)) "mail send"))
  (should (equal (gascity-command-subcommand (gascity-command-mail-reply)) "mail reply"))
  ;; The reply default subject prefixes RE: once, idempotently.
  (should (equal (gascity-mail--reply-subject "Build green") "RE: Build green"))
  (should (equal (gascity-mail--reply-subject "RE: Build green") "RE: Build green"))
  (should (equal (gascity-mail--reply-subject nil) "RE: ")))

(ert-deftest gascity-test-compose-finish ()
  "`gascity-compose-finish' runs its closure with the body, then discards.
`gascity-compose-abort' discards without calling the closure.  The
read-only header is excluded from the body."
  (let (received)
    (let ((buf (gascity-compose
                :buffer-name "*gc-test-compose*"
                :header '(("To" . "mayor") ("Subject" . "Hi"))
                :finish (lambda (body) (setq received body)))))
      (with-current-buffer buf
        (goto-char (point-max))
        (insert "line one\nline two")
        (gascity-compose-finish))
      (should (equal received "line one\nline two"))
      (should-not (buffer-live-p buf))))
  (let (called)
    (let ((buf (gascity-compose
                :buffer-name "*gc-test-compose-2*"
                :header '(("To" . "x"))
                :finish (lambda (_body) (setq called t)))))
      (with-current-buffer buf
        (gascity-compose-abort))
      (should-not called)
      (should-not (buffer-live-p buf)))))

;;; Phase 3 — bead update/create/deps, session lifecycle, rig composition

(ert-deftest gascity-test-bd-author-command-lines ()
  "Update/create/dep build the right `gc bd' line; `-C' precedes the flags.
Only fields that are set are emitted (update); create flips `--json' on (for
the new-id payload) right after the title; deps emit two positionals."
  ;; update: -C, then only the supplied --status/--priority.
  (should (equal (gascity-command-line
                  (gascity-command-bd-update :id "gce-1" :status "open"
                                             :priority "1" :directory "/r/gce/"))
                 '("gc" "bd" "update" "gce-1" "-C" "/r/gce/"
                   "--status" "open" "--priority" "1")))
  ;; update: description only (the compose path).
  (should (equal (gascity-command-line
                  (gascity-command-bd-update :id "gce-1" :description "body"
                                             :directory "/r/gce/"))
                 '("gc" "bd" "update" "gce-1" "-C" "/r/gce/" "--description" "body")))
  ;; update: no directory -> no -C.
  (should (equal (gascity-command-line
                  (gascity-command-bd-update :id "gce-1" :status "closed"))
                 '("gc" "bd" "update" "gce-1" "--status" "closed")))
  ;; create: --json right after the title, then -C, then the flags.
  (should (equal (gascity-command-line
                  (gascity-command-bd-create :title "Hello world" :type "task"
                                             :priority "2" :assignee "x"
                                             :directory "/r/gce/"))
                 '("gc" "bd" "create" "Hello world" "--json" "-C" "/r/gce/"
                   "--type" "task" "--priority" "2" "--assignee" "x")))
  (should (equal (gascity-command-line (gascity-command-bd-create :title "T"))
                 '("gc" "bd" "create" "T" "--json")))
  ;; dep add/remove: id + dependency positionals, then -C.
  (should (equal (gascity-command-line
                  (gascity-command-bd-dep-add :id "gce-1" :dependency "gce-2"
                                              :directory "/r/gce/"))
                 '("gc" "bd" "dep" "add" "gce-1" "gce-2" "-C" "/r/gce/")))
  (should (equal (gascity-command-line
                  (gascity-command-bd-dep-remove :id "gce-1" :dependency "gce-2"
                                                 :directory "/r/gce/"))
                 '("gc" "bd" "dep" "remove" "gce-1" "gce-2" "-C" "/r/gce/")))
  (should (equal (gascity-command-subcommand (gascity-command-bd-dep-add)) "bd dep add"))
  (should (equal (gascity-command-subcommand (gascity-command-bd-dep-remove))
                 "bd dep remove")))

(ert-deftest gascity-test-bd-author-validation ()
  "Update needs an id and ≥1 field; create needs a title; deps need both ids."
  (should (gascity-command-validate (gascity-command-bd-update)))
  ;; id but no field -> still invalid (an empty update is a no-op).
  (should (gascity-command-validate (gascity-command-bd-update :id "x")))
  (should-not (gascity-command-validate
               (gascity-command-bd-update :id "x" :status "open")))
  (should-not (gascity-command-validate
               (gascity-command-bd-update :id "x" :priority "1")))
  (should-not (gascity-command-validate
               (gascity-command-bd-update :id "x" :description "d")))
  (should (gascity-command-validate (gascity-command-bd-create)))
  (should-not (gascity-command-validate (gascity-command-bd-create :title "T")))
  (should (gascity-command-validate (gascity-command-bd-dep-add :id "x")))
  (should (gascity-command-validate (gascity-command-bd-dep-add :dependency "y")))
  (should-not (gascity-command-validate
               (gascity-command-bd-dep-add :id "x" :dependency "y")))
  (should (gascity-command-validate (gascity-command-bd-dep-remove :id "x")))
  (should-not (gascity-command-validate
               (gascity-command-bd-dep-remove :id "x" :dependency "y"))))

(ert-deftest gascity-test-bd-author-is-bd-action ()
  "Update/create/dep verbs inherit the `-C' store-routing base."
  (dolist (cmd (list (gascity-command-bd-update :id "x" :status "open")
                     (gascity-command-bd-create :title "t")
                     (gascity-command-bd-dep-add :id "x" :dependency "y")
                     (gascity-command-bd-dep-remove :id "x" :dependency "y")))
    (should (object-of-class-p cmd 'gascity-command-bd-action))))

(ert-deftest gascity-test-bd-author-store-routing ()
  "Update/dep runners resolve the bead store from the id prefix and pin `-C'.
Create resolves its store from the contextual rig (no existing id) and
surfaces the new id payload through `gascity-command-act'."
  (let (line created)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))]))))
              ((symbol-function 'gascity-command-execute-interactive)
               (lambda (cmd) (setq line (gascity-command-line cmd))))
              ((symbol-function 'gascity--refresh-current-view) #'ignore))
      (gascity-bead-update--run "gce-afq" :status "in_progress")
      (should (equal line '("gc" "bd" "update" "gce-afq" "-C" "/r/gce/"
                            "--status" "in_progress")))
      (gascity-bead-update--run "gce-afq" :priority "0")
      (should (equal line '("gc" "bd" "update" "gce-afq" "-C" "/r/gce/"
                            "--priority" "0")))
      (gascity-bead-dep-add--run "gce-afq" "gce-1")
      (should (equal line '("gc" "bd" "dep" "add" "gce-afq" "gce-1" "-C" "/r/gce/")))
      (gascity-bead-dep-remove--run "gce-afq" "gce-1")
      (should (equal line '("gc" "bd" "dep" "remove" "gce-afq" "gce-1" "-C" "/r/gce/")))
      ;; An unknown id prefix degrades to no -C.
      (gascity-bead-update--run "zz-9" :status "open")
      (should (equal line '("gc" "bd" "update" "zz-9" "--status" "open"))))
    ;; Create: store from the contextual rig; act surfaces the created id.
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "gascity.el") (path . "/r/gce") (prefix . "gce"))]))))
              ((symbol-function 'gascity-context-rig-name) (lambda (&rest _) "gascity.el"))
              ((symbol-function 'gascity-command-act)
               (lambda (cmd) (setq created (gascity-command-line cmd)) '((id . "gce-new"))))
              ((symbol-function 'gascity--refresh-current-view) #'ignore))
      (gascity-bead-create "New bead" "task" "2" "")
      (should (equal created '("gc" "bd" "create" "New bead" "--json" "-C" "/r/gce/"
                               "--type" "task" "--priority" "2")))
      ;; The created-id payload summarises as "created <id>".
      (should (equal (gascity-action--summarize '((id . "gce-new"))) "created gce-new")))))

(ert-deftest gascity-test-bd-compose-edits ()
  "Describe/note-compose open a compose buffer whose finish builds the verb.
`describe' replaces the description via `gc bd update'; `note (compose)'
appends via `gc bd note'.  Both are store-routed by the id prefix."
  (cl-letf (((symbol-function 'gascity-bead-at-point) (lambda () "gce-1"))
            ((symbol-function 'gascity-beads--bead-path) (lambda (_) "/r/gce/"))
            ((symbol-function 'gascity--refresh-current-view) #'ignore))
    (let (acted)
      (cl-letf (((symbol-function 'gascity-command-act)
                 (lambda (cmd) (setq acted (gascity-command-line cmd)))))
        ;; Description edit -> gc bd update --description <body>.
        (gascity-bead-describe-at-point)
        (with-current-buffer "*gc-bead gce-1 description*"
          (goto-char (point-max))
          (insert "a longer\ndescription")
          (gascity-compose-finish))
        (should (equal acted '("gc" "bd" "update" "gce-1" "-C" "/r/gce/"
                               "--description" "a longer\ndescription")))
        ;; Long note -> gc bd note <id> <body>.
        (gascity-bead-note-compose-at-point)
        (with-current-buffer "*gc-bead gce-1 note*"
          (goto-char (point-max))
          (insert "multi\nline note")
          (gascity-compose-finish))
        (should (equal acted '("gc" "bd" "note" "gce-1" "multi\nline note"
                               "-C" "/r/gce/")))))))

(ert-deftest gascity-test-session-lifecycle-command-lines ()
  "Rename/close/pin/unpin/prune build the right `gc session' line (no --json)."
  (should (equal (gascity-command-line
                  (gascity-command-session-rename :target "rig/a" :title "New name"))
                 '("gc" "session" "rename" "rig/a" "New name")))
  (should (equal (gascity-command-line (gascity-command-session-close :target "rig/a"))
                 '("gc" "session" "close" "rig/a")))
  (should (equal (gascity-command-line (gascity-command-session-pin :target "rig/a"))
                 '("gc" "session" "pin" "rig/a")))
  (should (equal (gascity-command-line (gascity-command-session-unpin :target "rig/a"))
                 '("gc" "session" "unpin" "rig/a")))
  (should (equal (gascity-command-line (gascity-command-session-prune))
                 '("gc" "session" "prune")))
  (should (equal (gascity-command-line
                  (gascity-command-session-prune :before "7d" :state "suspended,asleep"))
                 '("gc" "session" "prune" "--before" "7d" "--state" "suspended,asleep")))
  (dolist (cmd (list (gascity-command-session-rename :target "a" :title "b")
                     (gascity-command-session-close :target "a")
                     (gascity-command-session-prune)))
    (should-not (member "--json" (gascity-command-line cmd)))))

(ert-deftest gascity-test-session-lifecycle-validation ()
  "Rename needs target+title; close/pin/unpin need a target; prune needs nothing."
  (should (gascity-command-validate (gascity-command-session-rename :target "a")))
  (should (gascity-command-validate (gascity-command-session-rename :title "b")))
  (should-not (gascity-command-validate
               (gascity-command-session-rename :target "a" :title "b")))
  (dolist (cmd (list (gascity-command-session-close) (gascity-command-session-pin)
                     (gascity-command-session-unpin)))
    (should (gascity-command-validate cmd)))
  (should-not (gascity-command-validate (gascity-command-session-close :target "a")))
  (should-not (gascity-command-validate (gascity-command-session-pin :target "a")))
  (should-not (gascity-command-validate (gascity-command-session-unpin :target "a")))
  (should-not (gascity-command-validate (gascity-command-session-prune))))

(ert-deftest gascity-test-rig-compose-command-lines ()
  "Rig add/remove build the right `gc rig' line; optional name/prefix emit flags."
  (should (equal (gascity-command-line (gascity-command-rig-add :path "/p/x"))
                 '("gc" "rig" "add" "/p/x")))
  (should (equal (gascity-command-line
                  (gascity-command-rig-add :path "/p/x" :name "myrig" :prefix "mr"))
                 '("gc" "rig" "add" "/p/x" "--name" "myrig" "--prefix" "mr")))
  (should (equal (gascity-command-line (gascity-command-rig-remove :name "myrig"))
                 '("gc" "rig" "remove" "myrig")))
  (should (equal (gascity-command-subcommand (gascity-command-rig-add)) "rig add"))
  (should (equal (gascity-command-subcommand (gascity-command-rig-remove)) "rig remove")))

(ert-deftest gascity-test-rig-compose-validation ()
  "Rig add needs a path; rig remove needs a name."
  (should (gascity-command-validate (gascity-command-rig-add)))
  (should-not (gascity-command-validate (gascity-command-rig-add :path "/p")))
  (should (gascity-command-validate (gascity-command-rig-remove)))
  (should-not (gascity-command-validate (gascity-command-rig-remove :name "r"))))

(ert-deftest gascity-test-phase3-confirm-gating ()
  "Destructive phase-3 verbs gate on `yes-or-no-p'; a `no' skips the run.
Covers session close, session prune (city-wide), and rig remove."
  (dolist (probe
           (list
            (list #'gascity-session-close "rig/a")
            (list #'gascity-rig-remove "myrig")))
    (let ((fn (nth 0 probe)) (arg (nth 1 probe)) ran)
      (cl-letf (((symbol-function 'gascity-command-execute-interactive)
                 (lambda (&rest _) (setq ran t)))
                ((symbol-function 'gascity--refresh-current-view) #'ignore)
                ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
        (funcall fn arg)
        (should-not ran)
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
          (funcall fn arg)
          (should ran)))))
  ;; Prune takes flag args, not a target; gate it the same way.
  (let (ran)
    (cl-letf (((symbol-function 'gascity-command-execute-interactive)
               (lambda (&rest _) (setq ran t)))
              ((symbol-function 'gascity--refresh-current-view) #'ignore)
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) nil)))
      (gascity-session-prune "7d" "suspended")
      (should-not ran)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t)))
        (gascity-session-prune "7d" "suspended")
        (should ran)))))

(ert-deftest gascity-test-phase3-dispatch-entries ()
  "The phase-3 verbs are wired into their dispatch transients.
The dispatchers are the access path (bound to `c'/`R'/`A' in the views and
the main `gascity' menu); assert each new suffix command is reachable."
  (dolist (cmd '(gascity-bead-set-status-at-point gascity-bead-set-priority-at-point
                 gascity-bead-describe-at-point gascity-bead-note-compose-at-point
                 gascity-bead-dep-add-at-point gascity-bead-dep-remove-at-point
                 gascity-bead-create
                 gascity-session-rename gascity-session-close gascity-session-pin
                 gascity-session-unpin gascity-session-prune
                 gascity-rig-add gascity-rig-remove))
    (should (commandp cmd))))

;;; ============================================================
;;; Remote cities (TRAMP) — gce-90t
;;; ============================================================
;;
;; Offline coverage of the remote code paths via the standard TRAMP
;; "mock" method (the tramp-tests.el pattern): a real local `sh' behind
;; the full TRAMP file-name machinery, so `process-file' redirection,
;; `make-process :file-handler', and connection-local resolution all
;; exercise the same tramp-sh handlers a real ssh city would — with no
;; network.

(require 'tramp)

(defconst gascity-test--mock-directory
  (format "/mock::%s" temporary-file-directory)
  "TRAMP name of the local temp directory behind the mock method.")

(defun gascity-test--ensure-mock-method ()
  "Register the tramp-tests.el \"mock\" method (idempotent).
A real local `sh' behind the full TRAMP machinery — remote-flavored
code paths, no network."
  (unless (assoc "mock" tramp-methods)
    (add-to-list 'tramp-methods
                 '("mock"
                   (tramp-login-program "sh")
                   (tramp-login-args (("-i")))
                   (tramp-direct-async ("-c"))
                   (tramp-remote-shell "/bin/sh")
                   (tramp-remote-shell-args ("-c"))
                   (tramp-connection-timeout 10)))
    (add-to-list 'tramp-default-host-alist
                 `("\\`mock\\'" nil ,(system-name)))))

(defmacro gascity-test--with-mock-remote (&rest body)
  "Run BODY with a remote `default-directory' via the TRAMP mock method.
Skips the calling test when the mock connection cannot be established
\(e.g. no local sh)."
  (declare (indent 0) (debug t))
  `(progn
     (gascity-test--ensure-mock-method)
     (let ((tramp-verbose 0)
           (default-directory gascity-test--mock-directory))
       (skip-unless (ignore-errors (file-directory-p default-directory)))
       ,@body)))

(defun gascity-test--wait-for (box &optional timeout)
  "Pump the event loop until BOX's car is non-nil or TIMEOUT (10s) lapses.
Return BOX's car."
  (let ((deadline (+ (float-time) (or timeout 10))))
    (while (and (null (car box)) (< (float-time) deadline))
      (accept-process-output nil 0.1))
    (car box)))

(ert-deftest gascity-test-remote-localize-path ()
  "Host-local gc paths are re-prefixed for a remote view; locals untouched."
  ;; Local context: unchanged.
  (let ((default-directory "/"))
    (should (equal (gascity-remote-localize-path "/wd") "/wd")))
  ;; Remote context: prefixed with the view's TRAMP prefix.
  (let ((default-directory "/ssh:u@h:/home/u/city/"))
    (should (equal (gascity-remote-localize-path "/wd") "/ssh:u@h:/wd"))
    ;; An already-remote path passes through; nil/empty degrade unchanged.
    (should (equal (gascity-remote-localize-path "/ssh:u@h:/x") "/ssh:u@h:/x"))
    (should (null (gascity-remote-localize-path nil)))
    (should (equal (gascity-remote-localize-path "") "")))
  ;; Explicit DIR overrides `default-directory'.
  (should (equal (gascity-remote-localize-path "/wd" "/ssh:u@h:/city/")
                 "/ssh:u@h:/wd")))

(ert-deftest gascity-test-remote-buffer-name ()
  "View buffer names are host-qualified for a remote city, bare locally."
  (let ((default-directory "/"))
    (should (equal (gascity-remote-buffer-name "*gascity-status*")
                   "*gascity-status*")))
  (let ((default-directory "/ssh:u@h:/city/"))
    (should (equal (gascity-remote-buffer-name "*gascity-status*")
                   "*gascity-status@/ssh:u@h:*"))
    ;; A base without the trailing star still gets qualified.
    (should (equal (gascity-remote-buffer-name "plain") "plain@/ssh:u@h:"))))

(ert-deftest gascity-test-remote-ssh-argv ()
  "The local ssh argv carries user/port, quotes remote tokens, and rejects
methods/names one plain ssh cannot reach."
  (should (equal (gascity-remote-ssh-argv
                  "/ssh:user@example.com:/home/user/city/"
                  '("env" "-u" "TMUX" "tmux" "attach-session" "-t"
                    "gastown__mayor"))
                 '("ssh" "-t" "-l" "user" "example.com"
                   "env" "-u" "TMUX" "tmux" "attach-session" "-t"
                   "gastown__mayor")))
  ;; No user: no -l.  sshx counts as ssh-reachable.
  (should (equal (gascity-remote-ssh-argv "/sshx:h:/x" '("true"))
                 '("ssh" "-t" "h" "true")))
  ;; A #port becomes -p.
  (let ((argv (gascity-remote-ssh-argv "/ssh:u@h#2222:/x" '("true"))))
    (should (equal (seq-take argv 7) '("ssh" "-t" "-l" "u" "-p" "2222" "h"))))
  ;; Remote tokens are quoted for the remote POSIX shell (ssh joins them).
  (should (member (shell-quote-argument "a b")
                  (gascity-remote-ssh-argv "/ssh:u@h:/x" '("echo" "a b"))))
  ;; Non-ssh methods, multi-hop chains, and local names are refused.
  (should-error (gascity-remote-ssh-argv "/sudo:root@localhost:/etc" '("true"))
                :type 'user-error)
  (should-error (gascity-remote-ssh-argv "/ssh:a@b|ssh:c@d:/x" '("true"))
                :type 'user-error)
  (should-error (gascity-remote-ssh-argv "/home/x" '("true"))
                :type 'user-error))

(ert-deftest gascity-test-terminal-attach-argv ()
  "Attach argv: direct tmux locally; wrapped in local ssh for a remote city."
  (should (equal (gascity-terminal--attach-argv "sess" "sock")
                 '("env" "-u" "TMUX" "tmux" "-L" "sock"
                   "attach-session" "-t" "sess")))
  (should (equal (gascity-terminal--attach-argv "sess" nil "/ssh:u@h:/city/")
                 '("ssh" "-t" "-l" "u" "h"
                   "env" "-u" "TMUX" "tmux" "attach-session" "-t" "sess")))
  ;; A resolved PROGRAM (a host path from `gascity-remote-find-executable')
  ;; replaces the bare tmux in the remote command.
  (should (equal (gascity-terminal--attach-argv
                  "sess" nil "/ssh:u@h:/city/"
                  "/home/user/.guix-home/profile/bin/tmux")
                 '("ssh" "-t" "-l" "u" "h"
                   "env" "-u" "TMUX" "/home/user/.guix-home/profile/bin/tmux"
                   "attach-session" "-t" "sess"))))

(ert-deftest gascity-test-remote-reader-run ()
  "`gascity-reader-run' on a remote directory runs on the host: stdout and
stderr separate, exit code preserved.  The stderr capture file is created
host-side and read back through its full TRAMP name (gce-90t audit #1 —
handing `process-file' the local part instead would make TRAMP copy
stderr back to a LOCAL file of that name and the readback find nothing)."
  (gascity-test--with-mock-remote
    (let* ((gascity-executable "/bin/sh")
           (result (gascity-reader-run
                    '("-c" "echo OUT; echo ERR >&2; exit 3"))))
      (should (equal (plist-get result :exit-code) 3))
      (should (equal (plist-get result :stdout) "OUT\n"))
      (should (equal (plist-get result :stderr) "ERR\n")))))

(ert-deftest gascity-test-remote-reader-read-missing-gc-hint ()
  "A remote \"command not found\" names the host and both setup paths.
TRAMP raises no spawn error for a missing remote program — the remote
shell reports it on stderr and exits 127 — so the hint rides the
non-zero-exit path of `gascity-reader-read' (gce-90t audit #6)."
  (gascity-test--with-mock-remote
    (let* ((gascity-executable "gascity-test-absent-gc")
           (err (should-error (gascity-reader-read "status")
                              :type 'gascity-command-error))
           (msg (cadr err)))
      (should (string-match-p "mock" msg))
      ;; All three setup paths are named (gce-qke).
      (should (string-match-p "tramp-own-remote-path" msg))
      (should (string-match-p "gascity-remote-search-path" msg))
      (should (string-match-p "gascity-executable" msg)))))

(ert-deftest gascity-test-remote-find-executable ()
  "Bare names resolve on the host with zero setup (gce-qke): a
`tramp-remote-path' hit (`executable-find') wins, else the
`gascity-remote-search-path' profile directories are probed in order,
first hit wins.  Hits are cached per (connection × name) until
`gascity-context-clear-cache'; misses are NOT cached, so installing
the program heals itself.  Local directories and names that already
carry a directory pass through untouched."
  ;; Local: untouched, no resolution.
  (let ((default-directory "/"))
    (should (equal (gascity-remote-find-executable "gc") "gc")))
  (gascity-test--with-mock-remote
    (gascity-context-clear-cache)
    ;; Absolute (e.g. a connection-local `gascity-executable'): as-is.
    (should (equal (gascity-remote-find-executable "/opt/bin/gc")
                   "/opt/bin/gc"))
    ;; A host PATH hit wins; the profile directories are never probed.
    (let ((probed nil))
      (cl-letf (((symbol-function 'executable-find)
                 (lambda (&rest _) "/usr/bin/gc"))
                ((symbol-function 'file-executable-p)
                 (lambda (f) (push f probed) nil)))
        (should (equal (gascity-remote-find-executable "gc") "/usr/bin/gc"))
        (should (null probed))))
    (gascity-context-clear-cache)
    ;; Probe order, first-hit-wins, caching, self-healing miss — over
    ;; real directories behind the mock method's file machinery.  All
    ;; file mutations go through the TRAMP names: that keeps TRAMP's
    ;; own file-property cache coherent, so what these assertions see
    ;; is gascity's cache, not TRAMP's.
    (let* ((remote (file-remote-p default-directory))
           (tmp (make-temp-file "gascity-test-profiles" t))
           (dir-a (expand-file-name "a/bin" tmp))
           (dir-b (expand-file-name "b/bin" tmp))
           (tool-a (expand-file-name "gascity-test-tool" dir-a))
           (tool-b (expand-file-name "gascity-test-tool" dir-b))
           (gascity-remote-search-path (list dir-a dir-b)))
      (unwind-protect
          (progn
            (make-directory dir-a t)
            (make-directory dir-b t)
            (write-region "#!/bin/sh\n" nil (concat remote tool-b))
            (set-file-modes (concat remote tool-b) #o755)
            ;; Not on the host PATH, absent from dir-a -> dir-b's hit.
            (should (equal (gascity-remote-find-executable
                            "gascity-test-tool")
                           tool-b))
            ;; Cached: deleting the file does not change the answer...
            (delete-file (concat remote tool-b))
            (should (equal (gascity-remote-find-executable
                            "gascity-test-tool")
                           tool-b))
            ;; ...until invalidated — then the miss passes through
            ;; unchanged (the launch error path owns the hint).
            (gascity-context-clear-cache)
            (should (equal (gascity-remote-find-executable
                            "gascity-test-tool")
                           "gascity-test-tool"))
            ;; The miss was NOT cached: installing the tool (now in
            ;; BOTH directories) is picked up with no cache clear, and
            ;; the earlier entry wins.
            (write-region "#!/bin/sh\n" nil (concat remote tool-a))
            (set-file-modes (concat remote tool-a) #o755)
            (write-region "#!/bin/sh\n" nil (concat remote tool-b))
            (set-file-modes (concat remote tool-b) #o755)
            (should (equal (gascity-remote-find-executable
                            "gascity-test-tool")
                           tool-a)))
        (delete-directory tmp t)
        (gascity-context-clear-cache)))))

(ert-deftest gascity-test-remote-path-assignment ()
  "The PATH fragment (gce-k5d): nil locally and for an empty search path;
entries expanded on the host (`~' -> remote home) in order,
shell-quoted, nonexistent ones kept (a dead PATH entry is harmless and
filtering would mask a profile created later); cached per connection
until `gascity-context-clear-cache'."
  (let ((default-directory "/"))
    (should-not (gascity-remote-path-assignment)))
  (gascity-test--with-mock-remote
    (gascity-context-clear-cache)
    (unwind-protect
        (let* ((remote (file-remote-p default-directory))
               (home (file-local-name
                      (expand-file-name (concat remote "~")))))
          (let ((gascity-remote-search-path nil))
            (should-not (gascity-remote-path-assignment)))
          ;; Order kept, `~' expanded host-side, a nonexistent entry
          ;; and one needing shell quoting both ride along verbatim.
          (let ((gascity-remote-search-path
                 '("~/gascity-test-absent/bin" "/opt/gascity test/bin")))
            (should (equal (gascity-remote-path-assignment)
                           (format "PATH=%s/gascity-test-absent/bin:%s:$PATH"
                                   home
                                   (shell-quote-argument
                                    "/opt/gascity test/bin")))))
          ;; Cached per connection: a changed search path answers stale
          ;; until the one cache entry point clears it.
          (let ((gascity-remote-search-path '("/gascity-test-other/bin")))
            (should (string-match-p "gascity-test-absent"
                                    (gascity-remote-path-assignment)))
            (gascity-context-clear-cache)
            (should (equal (gascity-remote-path-assignment)
                           "PATH=/gascity-test-other/bin:$PATH"))))
      (gascity-context-clear-cache))))

(defmacro gascity-test--with-fake-remote-gc (&rest body)
  "Run BODY with a fake remote gc resolved via the search path.
Binds `gascity-remote-search-path' to (DIR-A \"~/gascity-test-absent/bin\")
— DIR-A a fresh host directory holding the `gascity-test-gc' script,
the `~' entry a nonexistent one — and `gascity-executable' to the bare
script name, so the zero-config chain (search-path resolution + PATH
export) is exercised end to end.  The script mirrors the gce-k5d
failure exactly: gc's own subprocesses — git for pack imports, dolt —
must resolve, not just gc itself.  It invokes `gascity-test-child' (a
second DIR-A script, findable ONLY through the exported PATH) by bare
name and prints the PATH a child inherits, as
{\"path\": \"...\", \"child\": \"...\"} JSON on stdout, after noise on
stderr.  BODY sees REMOTE, DIR-A, FAKE-GC, and PATH-PREFIX (the
expected leading PATH entries, colon-terminated)."
  (declare (indent 0) (debug t))
  `(gascity-test--with-mock-remote
     (gascity-context-clear-cache)
     (let* ((remote (file-remote-p default-directory))
            (tmp (make-temp-file "gascity-test-path" t))
            (dir-a (expand-file-name "profile/bin" tmp))
            (fake-gc (expand-file-name "gascity-test-gc" dir-a))
            (child (expand-file-name "gascity-test-child" dir-a))
            (home (file-local-name (expand-file-name (concat remote "~"))))
            (path-prefix (concat dir-a ":" home "/gascity-test-absent/bin:"))
            (gascity-remote-search-path
             (list dir-a "~/gascity-test-absent/bin"))
            (gascity-executable "gascity-test-gc"))
       (ignore remote dir-a fake-gc path-prefix)
       (unwind-protect
           (progn
             (make-directory dir-a t)
             (write-region "#!/bin/sh\necho FOUND\n" nil (concat remote child))
             (set-file-modes (concat remote child) #o755)
             (write-region
              (concat "#!/bin/sh\n"
                      "echo GARBAGE-ON-STDERR >&2\n"
                      "printf '{\"path\":\"%s\",\"child\":\"%s\"}' "
                      "\"$(sh -c 'echo \"$PATH\"')\" "
                      "\"$(gascity-test-child 2>/dev/null || echo MISSING)\"\n")
              nil (concat remote fake-gc))
             (set-file-modes (concat remote fake-gc) #o755)
             ,@body)
         (delete-directory tmp t)
         (gascity-context-clear-cache)))))

(defun gascity-test--check-export (data path-prefix)
  "Assert the fake gc's DATA proves the PATH export (gce-k5d).
DATA is the decoded {\"path\", \"child\"} payload.  The bare-named
`gascity-test-child' must have RESOLVED — the very failure gc's git
child hits without the export — and the child PATH must start with
PATH-PREFIX (search-path directories in order, `~' expanded host-side)
with no literal $PATH surviving (the refuted `process-environment'
route would leave one — every TRAMP handler forwards env values
shell-quoted) and the tail the process would have inherited anyway
still following."
  (let ((path (alist-get 'path data)))
    (should (equal (alist-get 'child data) "FOUND"))
    (should (stringp path))
    (should (string-prefix-p path-prefix path))
    (should-not (string-match-p (regexp-quote "$PATH") path))
    (should (> (length path) (length path-prefix)))))

(ert-deftest gascity-test-remote-reader-run-exports-search-path ()
  "Sync reads export the search-path directories to gc's CHILDREN.
The gce-k5d gap: `gascity-remote-find-executable' resolving gc to an
absolute profile path is not enough — gc spawns git (pack imports) and
dolt, and those inherit the process PATH, which lacks the profile
directories.  The /bin/sh wrapper's PATH assignment fixes that for
`process-file'; the remote shell evaluates it, so the inherited tail
survives."
  (gascity-test--with-fake-remote-gc
    (let ((result (gascity-reader-run '("status"))))
      ;; Resolved via the search path, run succeeded, stderr separate.
      (should (equal (plist-get result :executable) fake-gc))
      (should (equal (plist-get result :exit-code) 0))
      (should (equal (plist-get result :stderr) "GARBAGE-ON-STDERR\n"))
      (gascity-test--check-export
       (gascity-reader-parse-json (plist-get result :stdout))
       path-prefix))))

(ert-deftest gascity-test-remote-reader-read-async-exports-search-path ()
  "Async reads export the search-path directories to gc's children
\(gce-k5d) — the PATH assignment rides the same host-side /bin/sh
wrapper that separates stderr, so the tramp-sh path gets it for free."
  (gascity-test--with-fake-remote-gc
    (let ((result (list nil)))
      (gascity-reader-read-async
       '("status")
       (lambda (data) (setcar result data))
       (lambda (msg) (setcar result (cons :error msg))))
      (should (gascity-test--wait-for result))
      (gascity-test--check-export (car result) path-prefix))))

(ert-deftest gascity-test-remote-reader-read-async-direct-async-exports-search-path ()
  "Direct-async reads export the search-path directories too (gce-k5d).
TRAMP's direct-async handler spawns through the login program, whose
environment (login shell PATH, plus TRAMP's own env-injected remote
path) also lacks the profile directories — and it forwards
`process-environment' entries shell-quoted, so only the wrapper's
shell-evaluated assignment can prepend while keeping the inherited
tail.  The handler is spied to prove the dispatch took that path."
  (gascity-test--with-fake-remote-gc
    (unwind-protect
        (progn
          (connection-local-set-profile-variables
           'gascity-test-direct-async-path
           '((tramp-direct-async-process . t)))
          (connection-local-set-profiles
           '(:application tramp :protocol "mock")
           'gascity-test-direct-async-path)
          (let* ((result (list nil))
                 (direct-calls 0)
                 (real-direct (symbol-function 'tramp-handle-make-process)))
            (cl-letf (((symbol-function 'tramp-handle-make-process)
                       (lambda (&rest args)
                         (cl-incf direct-calls)
                         (apply real-direct args))))
              (gascity-reader-read-async
               '("status")
               (lambda (data) (setcar result data))
               (lambda (msg) (setcar result (cons :error msg))))
              (should (gascity-test--wait-for result)))
            (should (> direct-calls 0))
            (gascity-test--check-export (car result) path-prefix)))
      ;; `connection-local-set-profiles' persists beyond a let (see
      ;; gascity-test-remote-connection-local-executable); tear the
      ;; registration down so later mock tests stay non-direct.
      (setq connection-local-criteria-alist
            (delq nil
                  (mapcar
                   (lambda (e)
                     (let ((ps (remq 'gascity-test-direct-async-path
                                     (cdr e))))
                       (and ps (cons (car e) ps))))
                   connection-local-criteria-alist)))
      (setq connection-local-profile-alist
            (assq-delete-all 'gascity-test-direct-async-path
                             connection-local-profile-alist)))))

(ert-deftest gascity-test-remote-interactive-command-exports-search-path ()
  "The interactive `async-shell-command' backend prefixes the remote
line with the PATH assignment (gce-k5d) — the remote shell's PATH
omits the profile directories just as `tramp-remote-path' does, and
gc's subprocesses must resolve there too.  A local line stays bare."
  (gascity-test--with-mock-remote
    (gascity-context-clear-cache)
    (unwind-protect
        (let ((gascity-remote-search-path '("/gascity-test-profile/bin"))
              (lines nil))
          ;; session-peek streams through the BASE backend — status and
          ;; the list commands specialize `execute-interactive' into
          ;; their views and never reach `async-shell-command'.
          (cl-letf (((symbol-function 'async-shell-command)
                     (lambda (line &rest _) (push line lines))))
            (gascity-command-execute-interactive
             (gascity-command-session-peek :target "gastown__mayor"))
            (should (string-prefix-p
                     "PATH=/gascity-test-profile/bin:$PATH "
                     (car lines)))
            (should (string-match-p " session peek" (car lines)))
            ;; Locally the very same command line is unprefixed.
            (let ((default-directory "/"))
              (gascity-command-execute-interactive
               (gascity-command-session-peek :target "gastown__mayor"))
              (should-not (string-match-p "PATH=" (car lines))))))
      (gascity-context-clear-cache))))

(ert-deftest gascity-test-remote-reader-read-async ()
  "Async reads dispatch through the TRAMP file handler (gce-90t audit #2):
gc runs on the host and stderr noise never corrupts the parsed JSON.
Separation happens ON the host via the /bin/sh exec wrapper — without
TRAMP's named-pipe machinery, whose sentinel-time cleanup raises
reentrancy errors under parallel loads — and `make-process' never sees
a string `:stderr' (gce-qke: tramp-sh tolerated the old remote
null-device NAME, the direct-async handler crashes on any string)."
  (gascity-test--with-mock-remote
    (let* ((gascity-executable "/bin/sh")
           (result (list nil))
           (stderrs nil)
           (real-make-process (symbol-function 'make-process)))
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest args)
                   (push (plist-get args :stderr) stderrs)
                   (apply real-make-process args))))
        (gascity-reader-read-async
         '("-c" "echo GARBAGE-ON-STDERR >&2; echo '{\"city_name\":\"mock-city\"}'"
           "--json")
         (lambda (data) (setcar result data))
         (lambda (msg) (setcar result (cons :error msg))))
        (should (gascity-test--wait-for result)))
      (should (equal (alist-get 'city_name (car result)) "mock-city"))
      (should stderrs)
      (should (cl-notany #'stringp stderrs)))))

(ert-deftest gascity-test-remote-reader-read-async-direct-async ()
  "The gce-qke P1 regression: async reads survive TRAMP direct-async.
With the connection-local `tramp-direct-async-process' enabled, TRAMP
dispatches `make-process' to `tramp-handle-make-process', which accepts
only nil or a buffer as `:stderr' — the old code's remote null-device
STRING made every dashboard load signal `wrong-type-argument bufferp'.
This drives one read end-to-end through the direct handler (spied, to
prove the dispatch really took that path): the JSON must arrive intact
despite garbage on the command's stderr AND the login program's own
chatter (which direct-async merges into stdout unless a LOCAL scratch
buffer captures it — the mock method's `sh -i' reliably emits \"no job
control\" noise), and no `make-process' call may see a string
`:stderr'."
  (gascity-test--with-mock-remote
    (unwind-protect
        (progn
          (connection-local-set-profile-variables
           'gascity-test-direct-async '((tramp-direct-async-process . t)))
          (connection-local-set-profiles
           '(:application tramp :protocol "mock") 'gascity-test-direct-async)
          (let* ((gascity-executable "/bin/sh")
                 (result (list nil))
                 (direct-calls 0)
                 (stderrs nil)
                 (real-direct (symbol-function 'tramp-handle-make-process))
                 (real-make-process (symbol-function 'make-process)))
            (cl-letf (((symbol-function 'tramp-handle-make-process)
                       (lambda (&rest args)
                         (cl-incf direct-calls)
                         (apply real-direct args)))
                      ((symbol-function 'make-process)
                       (lambda (&rest args)
                         (push (plist-get args :stderr) stderrs)
                         (apply real-make-process args))))
              (gascity-reader-read-async
               '("-c"
                 "echo GARBAGE-ON-STDERR >&2; echo '{\"city_name\":\"mock-city\"}'"
                 "--json")
               (lambda (data) (setcar result data))
               (lambda (msg) (setcar result (cons :error msg))))
              (should (gascity-test--wait-for result)))
            (should (equal (alist-get 'city_name (car result)) "mock-city"))
            (should (> direct-calls 0))
            (should stderrs)
            (should (cl-notany #'stringp stderrs))))
      ;; `connection-local-set-profiles' persists beyond a let (see
      ;; gascity-test-remote-connection-local-executable); tear the
      ;; registration down so later mock tests stay non-direct.
      (setq connection-local-criteria-alist
            (delq nil
                  (mapcar (lambda (e)
                            (let ((ps (remq 'gascity-test-direct-async (cdr e))))
                              (and ps (cons (car e) ps))))
                          connection-local-criteria-alist)))
      (setq connection-local-profile-alist
            (assq-delete-all 'gascity-test-direct-async
                             connection-local-profile-alist)))))

(ert-deftest gascity-test-remote-reader-read-async-error ()
  "A non-zero remote exit reaches the errback, not the callback."
  (gascity-test--with-mock-remote
    (let ((gascity-executable "/bin/sh")
          (result (list nil)))
      (gascity-reader-read-async
       '("-c" "exit 7" "--json")
       (lambda (_data) (setcar result '(:unexpected-success)))
       (lambda (msg) (setcar result (cons :error msg))))
      (should (gascity-test--wait-for result))
      (should (eq (car (car result)) :error))
      (should (string-match-p "exit 7" (cdr (car result)))))))

(ert-deftest gascity-test-remote-connection-local-executable ()
  "A connection-local `gascity-executable' governs command lines and runs.
The invocation sites read the variable under
`with-connection-local-variables', so a per-host absolute path set via
connection-local profiles wins on that host and only there (gce-90t
audit #6).  The registration is torn down explicitly in unwind-protect:
`connection-local-set-profiles' persists via `custom-set-variables', so
a dynamic let of copied alists does NOT contain it — the residue would
apply the profile to every later mock-method test in this file."
  (gascity-test--with-mock-remote
    (let ((echo (executable-find "echo")))
      (skip-unless echo)
      (unwind-protect
          (progn
            (connection-local-set-profile-variables
             'gascity-test-remote-gc `((gascity-executable . ,echo)))
            (connection-local-set-profiles
             '(:application tramp :protocol "mock") 'gascity-test-remote-gc)
            ;; The command layer resolves the per-host value…
            (should (equal (car (gascity-command-line (gascity-command-status)))
                           echo))
            ;; …the reader actually invokes it — a regression guard for the
            ;; `with-temp-buffer' trap: the connection-local value is applied
            ;; buffer-locally, so the runner must capture it before switching
            ;; buffers…
            (let ((run (gascity-reader-run '("hello"))))
              (should (equal (plist-get run :exit-code) 0))
              (should (equal (plist-get run :stdout) "hello\n"))
              (should (equal (plist-get run :executable) echo)))
            ;; …and a local directory still sees the global default.
            (let ((default-directory "/"))
              (should (equal (car (gascity-command-line (gascity-command-status)))
                             "gc"))))
        (setq connection-local-criteria-alist
              (delq nil
                    (mapcar (lambda (e)
                              (let ((ps (remq 'gascity-test-remote-gc (cdr e))))
                                (and ps (cons (car e) ps))))
                            connection-local-criteria-alist)))
        (setq connection-local-profile-alist
              (assq-delete-all 'gascity-test-remote-gc
                               connection-local-profile-alist))))))

(ert-deftest gascity-test-context-pin-directory ()
  "Views pin the city root when inside a city tree, else the directory itself."
  (let* ((tmp (make-temp-file "gascity-test-pin" t))
         (city (file-name-as-directory (expand-file-name "town" tmp))))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "town/deep/nest" tmp) t)
          (write-region "" nil (expand-file-name "town/city.toml" tmp))
          (let ((default-directory (file-name-as-directory
                                    (expand-file-name "town/deep/nest" tmp))))
            (should (equal (gascity-context-pin-directory) city)))
          (let ((default-directory (file-name-as-directory tmp)))
            (should (equal (gascity-context-pin-directory)
                           (file-name-as-directory tmp)))))
      (delete-directory tmp t))))

(ert-deftest gascity-test-remote-view-identity ()
  "A view opened on a remote city gets a host-qualified buffer name and a
`default-directory' pinned to that city (gce-90t audit #7), so refresh
timers keep hitting the same host and a local view coexists."
  (gascity-test--with-mock-remote
    (let ((remote-prefix (file-remote-p default-directory))
          (buf nil))
      (cl-letf (((symbol-function 'pop-to-buffer) (lambda (b &rest _) b)))
        (unwind-protect
            (progn
              (setq buf (gascity-tabulated--show "*gascity-test-view*"
                                                 #'fundamental-mode
                                                 #'ignore))
              (should (equal (buffer-name buf)
                             (format "*gascity-test-view@%s*" remote-prefix)))
              (should (equal (file-remote-p
                              (buffer-local-value 'default-directory buf))
                             remote-prefix)))
          (when (buffer-live-p buf) (kill-buffer buf)))))))

(ert-deftest gascity-test-remote-attach-spawns-local-ssh ()
  "Attaching from a remote view spawns a LOCAL ssh argv in a local dir.
`beads-terminal-spawn' keeps its local-argv contract (gce-90t audit #4):
the tmux command is wrapped in `ssh -t HOST …', the working directory is
local (never the city's host-local path), and the terminal buffer name
is host-qualified."
  (let ((default-directory "/ssh:u@h:/city/")
        spawn)
    (cl-letf (((symbol-function 'gascity-terminal-tmux-session-exists-p)
               (lambda (&rest _) t))
              ;; The post-probe tmux resolution must not open a real
              ;; connection to the fictitious host; a resolved host
              ;; path must land in the ssh argv.
              ((symbol-function 'gascity-remote-find-executable)
               (lambda (name &optional _dir)
                 (concat "/opt/bin/" name)))
              ((symbol-function 'gascity-terminal--status-install)
               (lambda (&rest _) nil))
              ((symbol-function 'beads-terminal-spawn)
               (lambda (_term buffer-name argv dir _env)
                 (setq spawn (list buffer-name argv dir))
                 (get-buffer-create buffer-name)))
              ((symbol-function 'pop-to-buffer) (lambda (b &rest _) b)))
      (unwind-protect
          (progn
            (gascity-terminal-attach-tmux "sess" "sock" "/remote/wd")
            (should (equal (nth 1 spawn)
                           '("ssh" "-t" "-l" "u" "h"
                             "env" "-u" "TMUX" "/opt/bin/tmux" "-L" "sock"
                             "attach-session" "-t" "sess")))
            (should-not (file-remote-p (nth 2 spawn)))
            (should (equal (nth 0 spawn) "*gc-agent-sess@/ssh:u@h:*")))
        (when (get-buffer "*gc-agent-sess@/ssh:u@h:*")
          (kill-buffer "*gc-agent-sess@/ssh:u@h:*"))))))

(ert-deftest gascity-test-status-tick-skips-inflight-load ()
  "The auto-refresh tick never restarts loads still in flight (gce-90t #9).
Bumping the refresh tick changes every `vui-use-async' key, which KILLS
the in-flight gc process and restarts the load — so on a link where a
read takes longer than the interval (a remote city over ssh), an
unguarded timer would starve the dashboard forever."
  (let ((status-box (list nil))
        (sessions-box (list nil))
        (vui-render-delay nil)
        (refreshes 0))
    (cl-letf (((symbol-function 'gascity-reader-read-async)
               (gascity-test--status-async-stub status-box sessions-box)))
      (save-window-excursion
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-status-app)
                         "*gascity-status-test*")
              (let ((buf (get-buffer "*gascity-status-test*")))
                ;; Cold loads parked -> in flight -> the tick must skip.
                (should (gascity-status--loads-pending-p buf))
                (cl-letf (((symbol-function 'get-buffer-window)
                           (lambda (&rest _) t))
                          ((symbol-function 'gascity-status--refresh-instance)
                           (lambda (&rest _) (cl-incf refreshes) t)))
                  (gascity-status--auto-refresh-tick buf)
                  (should (= refreshes 0))
                  ;; Resolve both loads -> idle -> the next tick refreshes.
                  (funcall (car status-box)
                           '((city_name . "x") (rigs . []) (agents . [])))
                  (funcall (car sessions-box) '((sessions . [])))
                  (should-not (gascity-status--loads-pending-p buf))
                  (gascity-status--auto-refresh-tick buf)
                  (should (= refreshes 1)))))
          (when (get-buffer "*gascity-status-test*")
            (kill-buffer "*gascity-status-test*")))))))

(provide 'gascity-test)
;;; gascity-test.el ends here
