;;; gascity-expand-test.el --- `+'/`-' on capped sections -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; `+' shows `gascity-dashboard-section-batch' more rows of the capped
;; section at point, `-' as many fewer (never below the cap), in the
;; cockpit, the rig dashboard's bead sections and an unfolded churn
;; row; the Runs view's history paging takes the same keys.  The
;; state is view state: it survives `g', `C-u g' resets it, and point
;; stays anchored.  Nothing here reads gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-cockpit-test)

(defmacro gascity-expand-test--with-cockpit (reads &rest body)
  "Mount the canned cockpit, count gc reads in READS, run BODY in it."
  (declare (indent 1))
  `(let ((,reads 0))
     (let ((orig (symbol-function 'gascity-cockpit-test--scenario-read)))
       (cl-letf (((symbol-function 'gascity-cockpit-test--scenario-read)
                  (lambda (&rest args) (cl-incf ,reads) (apply orig args))))
         (gascity-cockpit-test--with-cockpit ,@body)))))

(defun gascity-expand-test--rows (title)
  "Return the number of item rows under section TITLE (until a blank line)."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward (concat "^" title "  "))
    (forward-line 1)
    (let ((n 0))
      (while (and (not (eobp)) (not (looking-at "^$")) (not (looking-at "^  … ")))
        (setq n (1+ n))
        (forward-line 1))
      n)))

(defun gascity-expand-test--goto (regexp)
  "Move point to the start of the line matching REGEXP."
  (goto-char (point-min))
  (re-search-forward regexp)
  (beginning-of-line))

(ert-deftest gascity-test-expand-cockpit-more-less-floor ()
  "`+' adds a batch of rows to the section at point, `-' takes it back,
never below the cap; no gc read is triggered."
  (gascity-expand-test--with-cockpit reads
    (let ((gascity-dashboard-section-batch 10))
      (should (= (gascity-expand-test--rows "Work") 5))
      (let ((before reads))
        (gascity-expand-test--goto "^Work  ")
        (gascity-section-more)
        (should (= (gascity-expand-test--rows "Work") 15))
        (should (string-match-p "… [0-9]+ more +\\+ more  j b beads" (buffer-string)))
        (gascity-section-less)
        (should (= (gascity-expand-test--rows "Work") 5))
        ;; The floor: at the cap `-' changes nothing.
        (let (msg)
          (cl-letf (((symbol-function 'message)
                     (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
            (gascity-section-less))
          (should (equal msg "Already at the default size")))
        (should (= (gascity-expand-test--rows "Work") 5))
        (should (= reads before))))))

(ert-deftest gascity-test-expand-cockpit-from-row-and-more-line ()
  "The section is resolved from any of its lines: a row or the more line."
  (gascity-expand-test--with-cockpit _reads
    (gascity-expand-test--goto "^Work  ")
    (forward-line 2)
    (gascity-section-more)
    (should (= (gascity-expand-test--rows "Work") 15))
    (gascity-expand-test--goto "^  … [0-9]+ more +\\+ more  j b beads")
    (gascity-section-more)
    (should (> (gascity-expand-test--rows "Work") 15))
    ;; Other sections are untouched.
    (should (<= (gascity-expand-test--rows "Activity") 5))))

(ert-deftest gascity-test-expand-cockpit-survives-refresh-reset-by-cu-g ()
  "The expansion is view state: `g' keeps it, `C-u g' resets it."
  (gascity-expand-test--with-cockpit _reads
    (gascity-expand-test--goto "^Work  ")
    (gascity-section-more)
    (gascity-dashboard-refresh)
    (should (= (gascity-expand-test--rows "Work") 15))
    (gascity-dashboard-refresh '(4))
    (should (= (gascity-expand-test--rows "Work") 5))))

(ert-deftest gascity-test-expand-cockpit-point-anchored ()
  "Point stays on its row across the re-render."
  (gascity-expand-test--with-cockpit _reads
    (gascity-expand-test--goto "^Work  ")
    (forward-line 3)
    (let ((id (gascity-section--line-id)))
      (should id)
      (gascity-section-more)
      (should (equal (gascity-section--line-id) id))
      (gascity-section-less)
      (should (equal (gascity-section--line-id) id)))))

(ert-deftest gascity-test-expand-cockpit-no-section-here ()
  "`+' off any capped section says so."
  (gascity-expand-test--with-cockpit _reads
    (goto-char (point-min))
    (should-error (gascity-section-more) :type 'user-error)))

(ert-deftest gascity-test-expand-churn-unfold ()
  "`+' inside an unfolded churn row shows a batch more of its events."
  (gascity-expand-test--with-cockpit _reads
    (let ((gascity-dashboard-churn-unfold-rows 3)
          (gascity-dashboard-section-batch 4))
      (gascity-expand-test--goto "×[0-9]+ +order.fired/completed")
      (gascity-thing-toggle)
      (let ((count (lambda ()
                     (save-excursion
                       (gascity-expand-test--goto "×[0-9]+ +order.fired/completed")
                       (forward-line 1)
                       (let ((n 0))
                         (while (looking-at "  [0-9][0-9]:[0-9][0-9]  +order\\.")
                           (setq n (1+ n))
                           (forward-line 1))
                         n)))))
        (should (= (funcall count) 3))
        (forward-line 1)
        (gascity-section-more)
        (should (= (funcall count) 7))
        (gascity-section-less)
        (should (= (funcall count) 3))))))

(ert-deftest gascity-test-expand-rig-sections ()
  "The rig dashboard's bead sections expand by the rig view's own state."
  (let* ((beads (vconcat (cl-loop for i below 30 collect
                                  `((id . ,(format "be-%02d" i)) (status . "open")
                                    (issue_type . "task") (title . ,(format "task %d" i))))))
         (count (lambda (extra)
                  (let* ((gascity-rig--extra extra)
                         (text (gascity-test--vnode-text
                                (gascity-rig--beads-section
                                 "Ready" (list :state 'ready :data beads))))
                         (n 0) (start 0))
                    (while (string-match "task [0-9]+" text start)
                      (setq n (1+ n) start (match-end 0)))
                    n))))
    (should (= (funcall count nil) 5))
    (should (= (funcall count '(("ready" . 10))) 15))
    (should (= (funcall count '(("in progress" . 10))) 5))))

(ert-deftest gascity-test-expand-runs-less ()
  "In Runs, `-' pages the history back, never below one page."
  (let ((pages 3) msg)
    (cl-letf (((symbol-function 'gascity-dashboard--state)
               (lambda (key) (and (eq key :pages) pages)))
              ((symbol-function 'gascity-dashboard--set-state)
               (lambda (key value) (when (eq key :pages) (setq pages value))))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
      (with-temp-buffer
        (gascity-runs-less)
        (should (= pages 2))
        (gascity-runs-less)
        (should (= pages 1))
        (gascity-runs-less)
        (should (= pages 1))
        (should (equal msg "Already at the default size"))))))

(ert-deftest gascity-test-expand-keys ()
  "`+'/`-' in every vui view and in the `?' dispatch; the lists do not bind
`+' and keep Emacs's inherited `-' (negative argument)."
  (dolist (map (list gascity-dashboard-mode-map gascity-rig-dashboard-mode-map
                     gascity-agents-tree-mode-map gascity-session-detail-mode-map
                     gascity-health-mode-map gascity-run-mode-map))
    (should (eq (keymap-lookup map "+") #'gascity-section-more))
    (should (eq (keymap-lookup map "-") #'gascity-section-less)))
  (should (eq (keymap-lookup gascity-runs-mode-map "+") #'gascity-runs-more))
  (should (eq (keymap-lookup gascity-runs-mode-map "-") #'gascity-runs-less))
  (should-not (keymap-lookup gascity-agents-mode-map "+"))
  (should (eq (plist-get (cdr (transient-get-suffix 'gascity-dispatch "+")) :command)
              'gascity-section-more))
  (should (eq (plist-get (cdr (transient-get-suffix 'gascity-dispatch "-")) :command)
              'gascity-section-less)))

(provide 'gascity-expand-test)
;;; gascity-expand-test.el ends here
