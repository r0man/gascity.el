;;; gascity-comms-test.el --- Tests for the Events view and mail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 §7.8 (Events) and §7.9 (mail inbox, thread, compose),
;; driven from the real gc payloads in fixtures/v3.  The gc boundary is
;; stubbed: reads at `gascity-events--read' / `gascity-store-fetch',
;; actions at the store's async runner (`gascity-test-with-store-stubs').

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

;;; Fixtures

(defconst gascity-comms-test--dir
  (expand-file-name "fixtures/v3/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the captured gc payloads.")

(defun gascity-comms-test--read (name)
  "Return the text of fixture NAME."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name gascity-comms-test--dir))
    (buffer-string)))

(defun gascity-comms-test--events (name)
  "Return fixture NAME (JSON Lines) decoded as the reader decodes it."
  (car (gascity-reader--parse-json-lines (gascity-comms-test--read name))))

(defun gascity-comms-test--json (name)
  "Return fixture NAME decoded as gc JSON."
  (gascity-reader-parse-json (gascity-comms-test--read name)))

(defmacro gascity-comms-test--with-view-buffer (&rest body)
  "Run BODY in a fresh buffer that is killed afterwards WITH its hooks.
`with-temp-buffer' inhibits buffer hooks, so a view's
`gascity-live-detach' (on `kill-buffer-hook') would never run and its
city would stay in the live stream table for later tests."
  (declare (indent 0))
  `(let ((buf (generate-new-buffer " *gascity-comms-test*")))
     (unwind-protect (with-current-buffer buf ,@body)
       (when (buffer-live-p buf) (kill-buffer buf)))))

(defmacro gascity-comms-test--with-events (spec &rest body)
  "Run BODY in a fresh Events buffer whose reads are recorded, not run.
SPEC is (READS): a variable collecting (ARGS CALLBACK ERRBACK FORCE),
newest first."
  (declare (indent 1))
  (let ((reads (car spec)))
    `(let ((,reads nil)
           (default-directory "/tmp/gascity-comms-city/"))
       (cl-letf (((symbol-function 'gascity-events--read)
                  (lambda (args cb eb &optional force)
                    (push (list args cb eb force) ,reads)))
                 ;; One page: batch has no real window height.
                 ((symbol-function 'beads-pager-window-page-size)
                  (lambda (&rest _) 10000)))
         (with-temp-buffer
           (gascity-events-mode)
           (setq gascity-events--city "emacs-city")
           ,@body)))))

(defun gascity-comms-test--rows ()
  "Return the plain column lists of every entry of the Events buffer."
  (mapcar (lambda (e) (cl-map 'list (lambda (c) (if (stringp c) (substring-no-properties c) c))
                              (cadr e)))
          gascity-tabulated--all-entries))

(defun gascity-comms-test--type (event-type &optional seq subject)
  "Return a minimal event of EVENT-TYPE, timestamped now."
  (list (cons 'seq (or seq 1)) (cons 'type event-type)
        (cons 'ts (format-time-string "%FT%T%z"))
        (cons 'actor "gc") (cons 'subject (or subject "x")) '(ok . t)
        '(payload)))

;;; Reader: native JSON Lines

(ert-deftest gascity-test-comms-jsonl-native-parse ()
  "The 2h fixture decodes line by line, natively, with no bad lines;
`null'/`false' are nil as in the single-payload decoder."
  (let ((parsed (gascity-reader--parse-json-lines
                 (gascity-comms-test--read "emacs-city.events-2h.jsonl"))))
    (should (= (length (car parsed)) 1366))
    (should (= (cdr parsed) 0))
    (should (equal (alist-get 'type (car (car parsed))) "order.fired")))
  (let ((parsed (gascity-reader--parse-json-lines
                 "{\"a\":null,\"b\":false,\"c\":[1]}\nnot json\n[1]\n")))
    (should (equal (car parsed) '(((a) (b) (c . [1])))))
    (should (= (cdr parsed) 2))))

(ert-deftest gascity-test-comms-jsonl-feeder-matches-whole-parse ()
  "Decoding JSON Lines chunk by chunk (any split, chatter first) gives
what decoding the whole output gives."
  (let* ((text (concat "Warning: no xauth data\n"
                       (gascity-comms-test--read
                        "emacs-city.events-24h-signal-sample.jsonl")
                       "garbage line\n{\"seq\":9,\"type\":\"x\"}"))
         (whole (gascity-reader--parse-json-lines text)))
    (dolist (size '(1 7 100 4096 100000))
      (let ((feed (gascity-reader--jsonl-feeder))
            (i 0))
        (while (< i (length text))
          (funcall feed (substring text i (min (length text) (+ i size))))
          (setq i (+ i size)))
        (should (equal (funcall feed nil) whole))))
    (should (= (cdr whole) 1))
    (should (= (length (car whole)) 86))))

;;; Event model

(ert-deftest gascity-test-comms-signal-levels ()
  "The signal table classifies the real signal types (§7.8)."
  (let ((levels (mapcar (lambda (e) (cons (alist-get 'type e) (gascity-event-level e)))
                        (gascity-comms-test--events
                         "emacs-city.events-24h-signal-sample.jsonl"))))
    (should (eq (cdr (assoc "session.cold_start_timeout" levels)) 'attention))
    (should (eq (cdr (assoc "order.failed" levels)) 'attention))
    (should (eq (cdr (assoc "dolt.compact.quarantine" levels)) 'attention))
    (should (eq (cdr (assoc "bead.dead_assignee_reopened" levels)) 'watch))
    (should-not (cdr (assoc "session.woke" levels)))
    (should-not (cdr (assoc "order.fired" levels))))
  ;; User-extensible.
  (let ((gascity-event-levels '(("\\.woke\\'" . watch))))
    (should (eq (gascity-event-level '((type . "session.woke"))) 'watch))))

(ert-deftest gascity-test-comms-since-arg ()
  "Day windows become hours (gc durations have no `d')."
  (should (equal (gascity-event-since-arg "7d") "168h"))
  (should (equal (gascity-event-since-arg "2h") "2h"))
  (should (= (gascity-ui-duration-seconds "7d") 604800))
  (should (= (gascity-ui-duration-seconds "junk") 86400)))

(ert-deftest gascity-test-comms-parse-time-fast-path ()
  "gc's RFC 3339 timestamps parse without `iso8601-parse', to the same
second, in either zone form; other shapes still go through it."
  (dolist (ts '("2026-09-25T20:12:13.123456789+02:00" "2026-09-24T17:52:14Z"
                "2024-02-29T23:59:59-05:30" "1999-12-31T23:59:59.5Z"))
    (should (= (gascity-ui-parse-time ts)
               (float-time (encode-time (iso8601-parse ts))))))
  (should (= (gascity-ui-parse-time "2026-09-25T20:12:13+0200")
             (float-time (encode-time (iso8601-parse "2026-09-25T20:12:13+0200")))))
  (should-not (gascity-ui-parse-time "yesterday")))

(ert-deftest gascity-test-comms-fold-quiet-window ()
  "A quiet 2h window is almost all churn: order firings fold per bucket,
and nothing is lost (rows + folded account for every event)."
  (let* ((events (gascity-comms-test--events "emacs-city.events-2h.jsonl"))
         (model (gascity-events--rows events nil)))
    (should (= (cadr model) 1366))
    (should (> (cddr model) 1300))
    (should (< (length (car model)) 40))
    (should (= (+ (cddr model)
                  (seq-count (lambda (r) (eq (car r) 'event)) (car model)))
               1366))))

(ert-deftest gascity-test-comms-level-filter ()
  "`-l attention' keeps ■ only; `watch' keeps ■ and ▲."
  (let ((events (gascity-comms-test--events "emacs-city.events-24h-signal-sample.jsonl")))
    (dolist (row (car (gascity-events--rows events '(:level "attention"))))
      (should (eq (car row) 'event))
      (should (eq (gascity-event-level (nth 1 row)) 'attention)))
    (let ((levels (delete-dups
                   (mapcar (lambda (r) (gascity-event-level (nth 1 r)))
                           (car (gascity-events--rows events '(:level "watch")))))))
      (should (memq 'watch levels))
      (should (memq 'attention levels))
      (should-not (memq nil levels)))))

(ert-deftest gascity-test-comms-actor-search-filters ()
  "`-a' matches the actor exactly; `-q' searches type, subject, message."
  (let ((events (gascity-comms-test--events "emacs-city.events-24h-signal-sample.jsonl")))
    (should (seq-every-p (lambda (e) (equal (alist-get 'actor e) "mayor"))
                         (seq-filter (lambda (e) (gascity-events--match-p e '(:actor "mayor")))
                                     events)))
    (should (seq-some (lambda (e) (gascity-events--match-p e '(:search "STRANDED")))
                      events))
    (should-not (seq-some (lambda (e) (gascity-events--match-p e '(:search "no-such-text")))
                          events))))

;;; Events view

(ert-deftest gascity-test-comms-events-view-renders ()
  "The view reads `gc events --since 2h' (JSON Lines) and renders churn
rows with ×N, signal rows with their glyph, and the header summary."
  (gascity-comms-test--with-events (reads)
    (gascity-events-refresh)
    (should (equal (car (car reads)) '("events" "--since" "2h")))
    (should (string-search "…" (gascity-events--header-line)))
    (funcall (nth 1 (car reads))
             (cons (gascity-comms-test--events "emacs-city.events-24h-signal-sample.jsonl") 0))
    (let ((rows (gascity-comms-test--rows)))
      (should (seq-some (lambda (r) (string-match-p "×[0-9]+" (nth 2 r))) rows))
      (should (seq-some (lambda (r) (and (equal (nth 1 r) "■")
                                         (equal (nth 2 r) "session.cold_start_timeout")))
                        rows))
      (should (seq-some (lambda (r) (and (equal (nth 1 r) "▲")
                                         (equal (nth 2 r) "bead.dead_assignee_reopened")
                                         (equal (nth 3 r) "ga-9xje")))
                        rows)))
    (let ((header (gascity-events--header-line)))
      (should (string-search "emacs-city" header))
      (should (string-search "last 2h" header))
      (should (string-search "signal ≥ event" header))
      (should (string-match-p "([0-9]+ churn folded)" header)))))

(ert-deftest gascity-test-comms-events-error-keeps-rows ()
  "A failed re-read keeps the rows and says so in the header (§6.1)."
  (gascity-comms-test--with-events (reads)
    (gascity-events-refresh)
    (funcall (nth 1 (car reads))
             (cons (gascity-comms-test--events "emacs-city.events-24h-signal-sample.jsonl") 0))
    (let ((n (length gascity-tabulated--all-entries)))
      (gascity-events-refresh t)
      (funcall (nth 2 (car reads)) "supervisor down")
      (should (= (length gascity-tabulated--all-entries) n))
      (should (string-search "gc events: supervisor down" (gascity-events--header-line))))))

(ert-deftest gascity-test-comms-events-spc-unfolds-churn ()
  "SPC on a ×N row unfolds its events in place; SPC again folds them."
  (gascity-comms-test--with-events (reads)
    (gascity-events-refresh)
    (funcall (nth 1 (car reads))
             (cons (gascity-comms-test--events "emacs-city.events-2h.jsonl") 0))
    (let ((n (length gascity-tabulated--all-entries)))
      (goto-char (point-min))
      (while (not (gascity-events--churn-p (tabulated-list-get-id))) (forward-line 1))
      (let ((size (length (nth 4 (tabulated-list-get-id)))))
        (gascity-events-toggle)
        (should (= (length gascity-tabulated--all-entries) (+ n size)))
        (goto-char (point-min))
        (while (not (gascity-events--churn-p (tabulated-list-get-id))) (forward-line 1))
        (gascity-events-toggle)
        (should (= (length gascity-tabulated--all-entries) n))))))

(ert-deftest gascity-test-comms-events-ret ()
  "RET: a ×N row narrows to its group; a bead event opens the bead
scoped to its store; a session event opens the agent's detail."
  (gascity-comms-test--with-events (reads)
    (gascity-events-refresh)
    (funcall (nth 1 (car reads))
             (cons (gascity-comms-test--events "emacs-city.events-24h-signal-sample.jsonl") 0))
    (let (shown opened sid)
      (cl-letf (((symbol-function 'gascity-bead-show)
                 (lambda (id &optional dir) (setq shown (list id dir))))
                ((symbol-function 'gascity-beads--bead-path-cached)
                 (lambda (_) "/tmp/rig/"))
                ((symbol-function 'gascity-events--open-agent)
                 (lambda (name) (setq opened name)))
                ((symbol-function 'gascity-store-fetch)
                 (lambda (args cb &rest _)
                   (should (equal args '("session" "list")))
                   (funcall cb `((sessions . [((id . ,sid)
                                               (agent_name . "beads.el/gc.run-operator-1"))]))))))
        (cl-flet ((goto (pred)
                    (goto-char (point-min))
                    (while (and (not (eobp)) (not (funcall pred (tabulated-list-get-id))))
                      (forward-line 1))
                    (should-not (eobp))))
          (goto (lambda (row) (and (consp row) (not (gascity-events--churn-p row))
                                   (equal (alist-get 'type row) "bead.dead_assignee_reopened"))))
          (let ((id (alist-get 'bead_id (alist-get 'payload (tabulated-list-get-id)))))
            (should id)
            (gascity-events-visit)
            (should (equal shown (list id "/tmp/rig/"))))
          (goto (lambda (row) (and (consp row) (not (gascity-events--churn-p row))
                                   (equal (alist-get 'type row) "session.stranded"))))
          (setq sid (alist-get 'session_id (tabulated-list-get-id)))
          (gascity-events-visit)
          (should (equal opened "beads.el/gc.run-operator-1"))
          (goto #'gascity-events--churn-p)
          (let ((group (nth 2 (tabulated-list-get-id))))
            (gascity-events-visit)
            (should (equal (plist-get gascity-events--filter :group) group))
            (should (seq-every-p (lambda (e) (not (gascity-events--churn-p (car e))))
                                 gascity-tabulated--all-entries))))))))

(ert-deftest gascity-test-comms-events-filter-rereads-on-argv-change ()
  "Window and type change the gc argv (a re-read, `--type' server-side);
the other filters re-render the rows in hand."
  (gascity-comms-test--with-events (reads)
    (gascity-events-refresh)
    (funcall (nth 1 (car reads)) (cons nil 0))
    (gascity-events--set-filter :window "7d")
    (should (equal (car (car reads)) '("events" "--since" "168h")))
    (gascity-events--set-filter :type "session.woke")
    (should (equal (car (car reads)) '("events" "--since" "168h" "--type" "session.woke")))
    (let ((n (length reads)))
      (gascity-events--set-filter :actor "gc")
      (gascity-events--set-filter :level "watch")
      (gascity-events--set-filter :unfold t)
      (should (= (length reads) n)))
    (should (string-search "actor=gc" (gascity-events--header-line)))
    (should (string-search "signal ≥ watch" (gascity-events--header-line)))
    (funcall gascity-filter-reset-function)
    (should (null gascity-events--filter))
    (should (equal (car (car reads)) '("events" "--since" "2h")))))

(ert-deftest gascity-test-comms-events-append ()
  "Live events append in one debounced render; duplicates (by seq) and
events outside the type filter are dropped; a read in flight merges
the queue when it lands."
  (gascity-comms-test--with-events (reads)
    (let ((gascity-events-append-delay 0))
      (gascity-events-refresh)
      ;; Arrives while the first read is in flight: queued, merged on landing.
      (gascity-events--append (list (gascity-comms-test--type "session.woke" 10)))
      (funcall (nth 1 (car reads))
               (cons (list (gascity-comms-test--type "session.stopped" 5)) 0))
      (should (equal (mapcar (lambda (e) (alist-get 'seq e)) gascity-events--events)
                     '(5 10)))
      (gascity-events--append (list (gascity-comms-test--type "session.woke" 10)
                                    (gascity-comms-test--type "session.crashed" 11)))
      (gascity-events--flush (current-buffer))
      (should (equal (mapcar (lambda (e) (alist-get 'seq e)) gascity-events--events)
                     '(5 10 11)))
      (should (equal (nth 2 (car (gascity-comms-test--rows))) "session.crashed"))
      (setq gascity-events--filter '(:type "session.woke"))
      (gascity-events--append (list (gascity-comms-test--type "session.stopped" 12)
                                    (gascity-comms-test--type "session.woke" 13)))
      (gascity-events--flush (current-buffer))
      (should (equal (mapcar (lambda (e) (alist-get 'seq e)) gascity-events--events)
                     '(5 10 11 13))))))

(ert-deftest gascity-test-comms-events-live-subscription ()
  "The view subscribes to its city's raw live events and appends them."
  (let (subscribed attached)
    (cl-letf (((symbol-function 'gascity-live-attach)
               (lambda (&rest _) (setq attached t)))
              ((symbol-function 'gascity-live-subscribe)
               (lambda (fn &optional buffer) (setq subscribed (cons fn buffer)) 'handle))
              ((symbol-function 'gascity-live-unsubscribe) #'ignore))
      (gascity-comms-test--with-events (reads)
        (let ((gascity-events-append-delay 0))
          (gascity-events--live-setup)
          (should attached)
          (should (eq (cdr subscribed) (current-buffer)))
          (gascity-events-refresh)
          (funcall (nth 1 (car reads)) (cons nil 0))
          (funcall (car subscribed) (gascity-comms-test--type "session.crashed" 7))
          (gascity-events--flush (current-buffer))
          (should (equal (nth 2 (car (gascity-comms-test--rows))) "session.crashed")))))))

(ert-deftest gascity-test-comms-events-render-guard ()
  "Rendering a remote city's Events buffer does no file I/O (§8.3 R2)."
  (gascity-comms-test--with-events (reads)
    (setq default-directory "/mock::/tmp/gascity-comms-city/")
    (gascity-events-refresh)
    (let ((payload (cons (gascity-comms-test--events "emacs-city.events-24h-signal-sample.jsonl") 0)))
      (gascity-test-ensure-mock-method)
      (gascity-test-with-render-guard
        (funcall (nth 1 (car reads)) payload)
        (gascity-events--header-line)
        (should (null gascity-test-render-guard-violations))))))

(ert-deftest gascity-test-comms-events-keys ()
  "The Events view binds the §5/§7.8 keys and the filter letters."
  (should (eq (keymap-lookup gascity-events-mode-map "SPC") #'gascity-events-toggle))
  (should (eq (keymap-lookup gascity-events-mode-map "RET") #'gascity-events-visit))
  (should (eq (keymap-lookup gascity-events-mode-map "W") #'gascity-events-toggle-live))
  (should (eq (keymap-lookup gascity-events-mode-map "/") #'gascity-events-filter))
  (dolist (key '("-W" "-t" "-a" "-l" "-c" "-q" "x"))
    (should (gascity-test--prefix-has-key 'gascity-events-filter key)))
  (should (commandp 'gascity-events)))

;;; Mail inbox

(defmacro gascity-comms-test--with-inbox (spec &rest body)
  "Run BODY in a fresh inbox holding the bright-lights inbox fixture.
SPEC is (READS ACTIONS), recorded by `gascity-test-with-store-stubs'."
  (declare (indent 1))
  `(let ((default-directory "/tmp/gascity-comms-city/"))
     (gascity-test-with-store-stubs ,(car spec) ,(cadr spec)
      (cl-letf (((symbol-function 'beads-pager-window-page-size)
                 (lambda (&rest _) 10000)))
       (gascity-comms-test--with-view-buffer
         (gascity-mail-inbox-mode)
         (setq gascity-mail--city "bright-lights")
         (gascity-mail-inbox-refresh)
         (funcall (nth 1 (car ,(car spec)))
                  (gascity-comms-test--json "bright-lights.mail-inbox.json"))
         ,@body)))))

(defun gascity-comms-test--finish (action &optional code)
  "Answer the parked store ACTION with exit CODE (default 0)."
  (funcall (nth 1 action)
           (list :exit-code (or code 0) :stdout "{}"
                 :stderr (if (eql code 1) "boom\n" ""))))

(ert-deftest gascity-test-comms-inbox-renders ()
  "Every unread message shows ● and bold; the header counts unread / total."
  (gascity-comms-test--with-inbox (reads _actions)
    (should (= (length gascity-tabulated--all-entries) 4))
    (dolist (e gascity-tabulated--all-entries)
      (should (equal (substring-no-properties (aref (cadr e) 0)) "●"))
      (should (eq (get-text-property 0 'face (aref (cadr e) 2)) 'bold)))
    (should (string-search "4 unread / 4" (gascity-mail-inbox--header-line)))
    (should (string-search "bright-lights" (gascity-mail-inbox--header-line)))))

(ert-deftest gascity-test-comms-inbox-render-guard ()
  "Rendering a remote city's inbox and its header does no file I/O (R2)."
  (let ((default-directory "/mock::/tmp/gascity-comms-city/"))
    (gascity-test-ensure-mock-method)
    (gascity-test-with-store-stubs _reads _actions
      (cl-letf (((symbol-function 'beads-pager-window-page-size)
                 (lambda (&rest _) 10000)))
        (gascity-comms-test--with-view-buffer
          (gascity-mail-inbox-mode)
          (let ((payload (gascity-comms-test--json "bright-lights.mail-inbox.json")))
            (gascity-test-with-render-guard
              ;; What the store delivers a remote read to (from a timer).
              (gascity-mail--paint (current-buffer) payload)
              (gascity-mail-inbox--header-line)
              (should (= (length gascity-tabulated--all-entries) 4))
              (should (null gascity-test-render-guard-violations)))))))))

(ert-deftest gascity-test-comms-events-time-column-fits ()
  "The Time column is `HH:MM' wide while all rows are today, wider else."
  (gascity-comms-test--with-events (reads)
    (gascity-events-refresh)
    (funcall (nth 1 (car reads)) (cons (list (gascity-comms-test--type "x.y" 1)) 0))
    (should (= (nth 1 (aref tabulated-list-format 0)) 5))
    (gascity-events-refresh t)
    (funcall (nth 1 (car reads))
             (cons (list '((seq . 2) (type . "x.y") (ts . "2020-01-01T00:00:00Z"))) 0))
    (should (= (nth 1 (aref tabulated-list-format 0)) 12))))

(ert-deftest gascity-test-comms-inbox-ret-no-gc ()
  "RET shows the message from the payload: no gc call, stays unread."
  (gascity-comms-test--with-inbox (reads actions)
    (let ((n (length reads)))
      (cl-letf (((symbol-function 'pop-to-buffer) (lambda (b &rest _) b)))
        (goto-char (point-min))
        (forward-line 1)
        (let* ((m (tabulated-list-get-id))
               (buf (gascity-mail-inbox-show)))
          (unwind-protect
              (progn
                (should (= (length reads) n))
                (should (null actions))
                (should (gascity-mail--unread-p m))
                (should (string-search "Latency:" (with-current-buffer buf (buffer-string)))))
            (kill-buffer buf)))))))

(ert-deftest gascity-test-comms-inbox-read-opens-thread ()
  "`r' opens the thread at once with `…', fills it from `gc mail
thread', and marks the message read with a separate async call."
  (gascity-comms-test--with-inbox (reads actions)
    (cl-letf (((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b)))
      (let ((inbox (current-buffer)))
        (goto-char (point-min))
        (while (not (and (tabulated-list-get-id)
                                (equal (gascity-mail-id (tabulated-list-get-id))
                                       "bl-wisp-a7gsqc")))
          (forward-line 1))
        (gascity-mail-read-at-point)
        (let ((thread (current-buffer)))
          (unwind-protect
              (progn
                (should (derived-mode-p 'gascity-mail-thread-mode))
                (should (string-search "…" (buffer-string)))
                (should (equal (car (car reads)) '("mail" "thread" "thread-b1b8bd38a599")))
                (should (equal (car (car actions)) '("mail" "mark-read" "bl-wisp-a7gsqc")))
                ;; The row is pending meanwhile.
                (with-current-buffer inbox
                  (should (seq-some (lambda (e) (equal (substring-no-properties
                                                        (aref (cadr e) 0))
                                                       "…"))
                                    tabulated-list-entries)))
                (funcall (nth 1 (car reads))
                         (gascity-comms-test--json "bright-lights.mail-thread.json"))
                (should-not (string-search "\n…\n" (buffer-string)))
                (should (string-search "Dolt health advisory" (buffer-string)))
                (should (string-search "From  human" (buffer-string)))
                (should (string-search "R reply  a archive  u unread  q quit" (buffer-string)))
                (gascity-comms-test--finish (car actions))
                ;; Read here: kept in the list, without ●.
                (with-current-buffer inbox
                  (let ((row (seq-find (lambda (e) (equal (gascity-mail-id (car e))
                                                          "bl-wisp-a7gsqc"))
                                       gascity-tabulated--all-entries)))
                    (should row)
                    (should (equal (substring-no-properties (aref (cadr row) 0)) " ")))
                  (should (string-search "3 unread / 4" (gascity-mail-inbox--header-line)))))
            (kill-buffer thread)))))))

(ert-deftest gascity-test-comms-inbox-bulk-archive ()
  "`a' on a region archives every row in it: one call per message, `…'
until each returns, one summary naming the failures and the log."
  (gascity-comms-test--with-inbox (_reads actions)
    (let (echo)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                ((symbol-function 'message)
                 (lambda (fmt &rest args) (setq echo (apply #'format fmt args)))))
        (transient-mark-mode 1)
        (goto-char (point-min))
        (forward-line 1)
        (set-mark (point))
        (forward-line 3)
        (activate-mark)
        (gascity-mail-archive-at-point)
        (should (= (length actions) 3))
        (should (= 3 (seq-count (lambda (e) (equal (substring-no-properties (aref (cadr e) 0))
                                                   "…"))
                                tabulated-list-entries)))
        (gascity-comms-test--finish (nth 0 actions))
        (gascity-comms-test--finish (nth 1 actions) 1)
        (gascity-comms-test--finish (nth 2 actions))
        (should (string-match-p
                 "\\`Archived 2 of 3; 1 failed, see \\*gascity-log: gascity-comms-city\\*\\'"
                 echo))
        (should (= (length gascity-tabulated--all-entries) 2))))))

(ert-deftest gascity-test-comms-inbox-unread-after-read ()
  "`u' on a message read here marks it unread again (async, one call)."
  (gascity-comms-test--with-inbox (_reads actions)
    (cl-letf (((symbol-function 'message) #'ignore))
      (goto-char (point-min))
      (forward-line 1)
      (let ((id (gascity-mail-id (tabulated-list-get-id))))
        (gascity-mail-mark-read-at-point)
        (gascity-comms-test--finish (car actions))
        (should-not (gascity-mail--unread-p (gascity-mail-message :id id)))
        (goto-char (point-min))
        (while (not (and (tabulated-list-get-id)
                                (equal (gascity-mail-id (tabulated-list-get-id)) id)))
          (forward-line 1))
        (gascity-mail-mark-unread-at-point)
        (should (equal (car (car actions)) (list "mail" "mark-unread" id)))
        (gascity-comms-test--finish (car actions))
        (should (gascity-mail--unread-p (gascity-mail-message :id id :read t)))))))

(ert-deftest gascity-test-comms-inbox-filters ()
  "`-u' unread only, `-a' from, `-q' search; applied to the rows in hand."
  (gascity-comms-test--with-inbox (reads _actions)
    (let ((n (length reads)))
      (gascity-mail--set-filter :search "12h old")
      (should (= (length gascity-tabulated--all-entries) 2))
      (gascity-mail--set-filter :from "nobody")
      (should (= (length gascity-tabulated--all-entries) 0))
      (should (string-search "from=nobody" (gascity-mail-inbox--header-line)))
      (funcall gascity-filter-reset-function)
      (should (= (length gascity-tabulated--all-entries) 4))
      (should (= (length reads) n)))))

(ert-deftest gascity-test-comms-inbox-error-keeps-rows ()
  "A failed inbox re-read keeps the rows and shows the error in the header."
  (gascity-comms-test--with-inbox (reads _actions)
    (cl-letf (((symbol-function 'message) #'ignore))
      (gascity-mail-inbox-refresh t)
      (funcall (nth 2 (car reads)) "gc mail inbox failed: boom")
      (should (= (length gascity-tabulated--all-entries) 4))
      (should (string-search "boom" (gascity-mail-inbox--header-line))))))

(ert-deftest gascity-test-comms-mail-command-and-keys ()
  "`gascity-mail' is the inbox command (`j m'); the class is
`gascity-mail-message'; the inbox binds the §5.3 mail keys."
  (should (commandp 'gascity-mail))
  (should (gascity-mail-message-p (gascity-mail-message :id "x")))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "RET") #'gascity-mail-inbox-show))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "r") #'gascity-mail-read-at-point))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "a") #'gascity-mail-archive-at-point))
  (should (eq (keymap-lookup gascity-mail-inbox-mode-map "u")
              #'gascity-mail-mark-unread-at-point))
  (should (eq (keymap-lookup gascity-mail-thread-mode-map "R") #'gascity-mail-reply-at-point))
  (should (eq (keymap-lookup gascity-mail-thread-mode-map "a")
              #'gascity-mail-archive-at-point))
  (dolist (key '("-u" "-a" "-W" "-q" "x"))
    (should (gascity-test--prefix-has-key 'gascity-mail-inbox-filter key))))

;;; Compose

(ert-deftest gascity-test-comms-compose-notify-and-async-send ()
  "C-c C-n toggles Notify; C-c C-c closes the draft at once and starts
`gc mail reply … --notify --message BODY' (the body is argv)."
  (let ((default-directory "/tmp/gascity-comms-city/")
        (m (gascity-mail-message :id "bl-1" :from "mayor" :subject "hi"))
        (popped nil))
    (gascity-test-with-store-stubs _reads actions
      (cl-letf (((symbol-function 'gascity-mail-at-point) (lambda () m))
                ((symbol-function 'read-string) (lambda (_p d &rest _) d))
                ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (setq popped b))))
        (gascity-mail-reply-at-point)
        (let ((buf popped))
          (with-current-buffer buf
            (should (string-search "Notify: no" (buffer-string)))
            (should (string-search "--text follows this line--" (buffer-string)))
            (gascity-compose-toggle-notify)
            (should (string-search "Notify: yes" (buffer-string)))
            (goto-char (point-max))
            (insert "line one\n# not a comment")
            (gascity-compose-finish))
          (should-not (buffer-live-p buf))
          (should (= (length actions) 1))
          (let ((args (car (car actions))))
            (should (equal (seq-take args 3) '("mail" "reply" "bl-1")))
            (should (member "--notify" args))
            (should (equal (cadr (member "--message" args))
                           "line one\n# not a comment"))
            (should (equal (cadr (member "--subject" args)) "RE: hi"))))))))

(ert-deftest gascity-test-comms-compose-failure-keeps-draft ()
  "A failed send puts the body on the kill ring."
  (let ((default-directory "/tmp/gascity-comms-city/")
        (kill-ring nil)
        (popped nil))
    (gascity-test-with-store-stubs _reads actions
      (cl-letf (((symbol-function 'pop-to-buffer) (lambda (b &rest _) (setq popped b)))
                ((symbol-function 'message) #'ignore))
        (gascity-mail-send "mayor" "subject")
        (with-current-buffer popped
          (goto-char (point-max))
          (insert "precious body")
          (gascity-compose-finish))
        (gascity-comms-test--finish (car actions) 1)
        (should (equal (car kill-ring) "precious body"))))))

(provide 'gascity-comms-test)
;;; gascity-comms-test.el ends here
