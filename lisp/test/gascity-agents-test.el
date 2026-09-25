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
              (should (string-match-p "^  ● mayor" (buffer-string)))
              (goto-char (point-min))
              (re-search-forward "▾ beads.el")
              (beginning-of-line)
              (gascity-thing-toggle)
              (should (string-match-p "▸ beads.el" (buffer-string)))
              (gascity-agents-tree-refresh)
              (should (string-match-p "▸ beads.el" (buffer-string)))))
        (kill-buffer buf)))))

(provide 'gascity-agents-test)
;;; gascity-agents-test.el ends here
