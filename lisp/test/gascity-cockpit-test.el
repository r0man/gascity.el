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
                ((symbol-function 'gascity-session-list--auto-refresh-setup)
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

(provide 'gascity-cockpit-test)
;;; gascity-cockpit-test.el ends here
