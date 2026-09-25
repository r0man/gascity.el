;;; gascity-comms-test.el --- Tests for the Events view and mail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 §7.8 (Events), driven from the real gc payloads in
;; fixtures/v3.  The gc boundary is stubbed: reads at
;; `gascity-events--read' / `gascity-store-fetch'.

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

(provide 'gascity-comms-test)
;;; gascity-comms-test.el ends here
