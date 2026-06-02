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
  "A rig entry keeps the alist as its id and lays out columns."
  (let* ((rig '((name . "gascity.el") (prefix . "gce") (running . t) (suspended)
                (default_branch . "main") (beads . "initialized")))
         (entry (gascity-rig-list--entry rig)))
    (should (eq (car entry) rig))
    (should (equal (gascity-test--plain-cols entry)
                   '("gascity.el" "gce" "running" "main" "initialized")))))

(defun gascity-test--rig-list-buffer ()
  "Render a rig-list buffer with an HQ row and a plain rig row.
The HQ row (`bright-lights') carries `hq', as `gc rig list' marks the city
HQ; the plain row (`gascity.el') does not.  Leaves the buffer current."
  (gascity-rig-list-mode)
  (setq tabulated-list-entries
        (list (gascity-rig-list--entry '((name . "bright-lights") (prefix . "bl")
                                         (hq . t)))
              (gascity-rig-list--entry '((name . "gascity.el") (prefix . "gce")
                                         (running . t) (default_branch . "main")))))
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
                            '((name . "gascity.el") (prefix . "gce") (running . t)
                              (default_branch . "main") (beads . "initialized")))))
                   "initialized"))))

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
  "A Dolt entry lays out name and commits, but not `open_beads' (gce-x72).
`gc dolt health' reports `open_beads' as 0 for every database, so the
column was a row of zeros; it was dropped here as it was from the rig
dashboard (gce-ziz).  The field is dropped regardless of its value, so a
non-zero `open_beads' in the input must still not surface."
  (should (equal (gascity-test--plain-cols
                  (gascity-dolt-list--entry
                   '((name . "beads") (commits . 42) (open_beads . 7))))
                 '("beads" "42"))))

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
         (entries (mapcar #'gascity-convoy-list--entry convoys))
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

;;; Status dashboard refresh — collapse preservation (vui integration, gce-gie)

(defun gascity-test--buffer-contains-p (needle)
  "Return non-nil when the current buffer's text contains NEEDLE."
  (save-excursion
    (goto-char (point-min))
    (and (search-forward needle nil t) t)))

(defun gascity-test--press-header (name)
  "Press the collapsible rig header button whose label contains NAME.
NAME is matched against the buffer's visible text; the rig name appears
only in its header button, so the first match lands inside that widget."
  (goto-char (point-min))
  (unless (search-forward name nil t)
    (error "rig header %S not found in dashboard" name))
  (widget-button-press (match-beginning 0)))

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

(ert-deftest gascity-test-bead-show-passes-directory ()
  "`gascity-bead-show' makes beads.el resolve the store with `--directory' (-C).
beads.el's cwd-mode `bd' can be misrouted by the shared Dolt server, so the
store is passed explicitly on the one `beads-command-show' that `beads-show'
issues — this is what lets a city-level convoy open (gce-bhr)."
  (let (exec-call seen-dir)
    (cl-letf (((symbol-function 'gascity-command-rig-list!)
               (lambda (&rest _)
                 '((rigs . [((name . "example-town-cl") (path . "/r/bs") (prefix . "bs"))]))))
              ;; Record the command class and args beads.el is asked to run.
              ((symbol-function 'beads-execute)
               (lambda (class &rest args) (setq exec-call (cons class args))))
              ;; Stand in for beads.el's `beads-show': capture the directory it
              ;; runs in and issue the one `beads-command-show' the real one does.
              ((symbol-function 'beads-show)
               (lambda (id)
                 (setq seen-dir default-directory)
                 (beads-execute 'beads-command-show :issue-ids (list id)
                                :include-dependents t))))
      (gascity-bead-show "bs-0q2z")
      ;; Buffer stays scoped to the prefix-routed store for naming...
      (should (equal seen-dir "/r/bs/"))
      ;; ...and the show carries `:directory' so `bd' uses -C, not cwd-mode.
      (should (eq (car exec-call) 'beads-command-show))
      (should (equal (plist-get (cdr exec-call) :directory) "/r/bs/")))))

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
`from'/`subject'/`created_at' (date + time) become the columns, the whole
message alist is the id, and a non-`read' message shows the ● marker."
  (let* ((message '((id . "msg-1") (from . "mayor/") (to . "gce/furiosa")
                    (subject . "Re: status") (body . "...")
                    (created_at . "2026-06-01T19:18:18Z") (read . nil)))
         (entry (gascity-mail-inbox--entry message)))
    (should (eq (car entry) message))
    (should (equal (gascity-test--plain-cols entry)
                   '("mayor/" "Re: status" "2026-06-01 19:18" "●"))))
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

(provide 'gascity-test)
;;; gascity-test.el ends here
