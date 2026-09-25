;;; gascity-invariants-test.el --- Regression invariants for the vui views -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The invariants the retired status board and v2 dashboard tests
;; guarded, re-established on the dashboard-v3 cockpit:
;;
;; - one failing read never blanks another section;
;; - a refresh whose reads are pending keeps the last snapshot, folds
;;   and drawers (the SWR "pending unmounts the tree" bug class);
;; - a refresh that fails over good data keeps the rows and marks ◐;
;; - rendering, refresh, motion and toggles never run gc synchronously;
;; - the store fan-out degrades partially, handles no rigs, and keeps
;;   its city when started from a callback (QA F5);
;; - point, and a non-selected window's point, stay on their row
;;   across a refresh that reorders rows;
;; - the rig prompts read the rig memo, never a sync `gc rig list'.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-cockpit-test)

;;; A controllable read stub

(defvar gascity-inv--mode nil
  "Function of ARGS returning how the stub answers a read:
nil (answer from the scenario), `park', or (error . MESSAGE).")

(defvar gascity-inv--parked nil
  "Parked reads: a list of (ARGS CALLBACK . ERRBACK).")

(defun gascity-inv--read (args callback &optional errback &rest rest)
  "Stub `gascity-reader-read-async': ARGS CALLBACK ERRBACK REST."
  (let ((how (and gascity-inv--mode (funcall gascity-inv--mode args))))
    (pcase how
      ('park (push (cons args (cons callback errback)) gascity-inv--parked) nil)
      (`(error . ,msg) (when errback (funcall errback msg)) nil)
      (_ (apply #'gascity-cockpit-test--scenario-read args callback errback rest)))))

(defun gascity-inv--release ()
  "Answer every parked read from the scenario."
  (let ((parked (reverse gascity-inv--parked)))
    (setq gascity-inv--parked nil)
    (dolist (p parked)
      (gascity-cockpit-test--scenario-read (car p) (cadr p) (cddr p)))))

(defmacro gascity-inv--with-cockpit (&rest body)
  "Mount the cockpit on the controllable stub and run BODY in its buffer."
  (declare (indent 0))
  `(let ((vui-render-delay nil)
         (gascity-dashboard-live nil)
         (gascity-dashboard-filters nil)
         (gascity-inv--mode nil)
         (gascity-inv--parked nil)
         (buf (get-buffer-create "*gascity-inv-test*")))
     (cl-letf (((symbol-function 'gascity-reader-read-async) #'gascity-inv--read)
               ((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
               ((symbol-function 'gascity-rigs-remember) (lambda (r &rest _) r)))
       (unwind-protect
           (save-window-excursion
             (with-current-buffer buf (gascity-dashboard-mode))
             (vui-mount (vui-component 'gascity-dashboard-app :initial-filters nil)
                        (buffer-name buf))
             (with-current-buffer buf ,@body))
         (kill-buffer buf)))))

(defun gascity-inv--has (regexp)
  "Return non-nil when the current buffer matches REGEXP."
  (save-excursion (goto-char (point-min)) (re-search-forward regexp nil t)))

;;; Section isolation, SWR

(ert-deftest gascity-test-cockpit-section-failure-isolated ()
  "A failing read shows its own ■ line; every other section still renders."
  (let ((vui-render-delay nil))
    (cl-letf (((symbol-function 'gascity-reader-read-async) #'gascity-inv--read))
      (gascity-inv--with-cockpit
        ;; Re-mount with the events read failing from the start.
        (setq gascity-inv--mode (lambda (args) (and (equal (car args) "events")
                                                    '(error . "gc events: supervisor down"))))
        (gascity-dashboard-refresh)
        (should (gascity-inv--has "^Activity  ◐\\|^Activity"))
        (should (gascity-inv--has "^Work  [0-9]+ ready"))
        (should (gascity-inv--has "^Rigs  2"))
        (should (gascity-inv--has "^Agents  "))))))

(ert-deftest gascity-test-cockpit-first-load-error-line ()
  "With no data yet, a failed read renders `■ gc …: reason   g retry'."
  (let ((vui-render-delay nil)
        (gascity-dashboard-live nil)
        (gascity-inv--mode (lambda (args) (and (equal (car args) "events")
                                               '(error . "supervisor down\nmore"))))
        (buf (get-buffer-create "*gascity-inv-test*")))
    (cl-letf (((symbol-function 'gascity-reader-read-async) #'gascity-inv--read)
              ((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
              ((symbol-function 'gascity-rigs-remember) (lambda (r &rest _) r)))
      (unwind-protect
          (save-window-excursion
            (with-current-buffer buf (gascity-dashboard-mode))
            (vui-mount (vui-component 'gascity-dashboard-app :initial-filters nil)
                       (buffer-name buf))
            (with-current-buffer buf
              (should (gascity-inv--has "■ gc events: supervisor down   g retry"))
              (should-not (gascity-inv--has "^more"))
              (should (gascity-inv--has "^Work  [0-9]+ ready"))))
        (kill-buffer buf)))))

(ert-deftest gascity-test-cockpit-pending-refresh-keeps-snapshot ()
  "A refresh whose reads are all pending keeps rows, folds and drawers;
fresh data then reconciles in place (the SWR unmount bug class)."
  (gascity-inv--with-cockpit
    (goto-char (point-min))
    (re-search-forward "^Rigs")
    (gascity-thing-toggle)                  ; fold Rigs
    (goto-char (point-min))
    (re-search-forward "^  ○ mayor")
    (gascity-thing-toggle)                  ; open mayor's drawer
    (should (gascity-inv--has "│ session ec-grfr"))
    (setq gascity-inv--mode (lambda (_) 'park))
    (gascity-dashboard-refresh)
    (should gascity-inv--parked)
    ;; Nothing unmounted while pending.
    (should (gascity-inv--has "^▸ Rigs"))
    (should (gascity-inv--has "│ session ec-grfr"))
    (should (gascity-inv--has "^Work  [0-9]+ ready"))
    (should-not (gascity-inv--has "^Work  …"))
    (setq gascity-inv--mode nil)
    (gascity-inv--release)
    (should (gascity-inv--has "^▸ Rigs"))
    (should (gascity-inv--has "│ session ec-grfr"))))

(ert-deftest gascity-test-cockpit-stale-refresh-error-inline ()
  "A refresh that fails over good data keeps the rows and marks the
header ◐ with the error as help-echo."
  (gascity-inv--with-cockpit
    (should (gascity-inv--has "^Work  [0-9]+ ready"))
    (setq gascity-inv--mode (lambda (args) (and (equal args '("convoy" "list"))
                                                '(error . "convoy boom"))))
    (gascity-dashboard-refresh)
    (goto-char (point-min))
    (should (re-search-forward "^Work  .*◐" nil t))
    (should (string-match-p "convoy boom"
                            (or (get-text-property (1- (point)) 'help-echo) "")))
    (should (gascity-inv--has "^  ga-uc7y\\|^  [a-z]+-[a-z0-9]+ +P[0-9]"))))

(ert-deftest gascity-test-cockpit-render-never-reads-sync ()
  "Mount, refresh, motion, toggles and filters never run gc synchronously."
  (let ((boom (lambda (&rest args) (error "Sync gc at render: %S" args))))
    (cl-letf (((symbol-function 'gascity-reader-read) boom)
              ((symbol-function 'gascity-reader-run) boom)
              ((symbol-function 'process-file) boom)
              ((symbol-function 'call-process) boom))
      (gascity-inv--with-cockpit
        (dotimes (_ 12) (gascity-thing-forward 1))
        (goto-char (point-min))
        (re-search-forward "^Agents")
        (gascity-thing-toggle)
        (gascity-filter-set :unfold t)
        (gascity-dashboard-refresh)
        (should (gascity-inv--has "^▸ Agents"))
        (should (stringp (gascity-dashboard--header-line)))))))

;;; Store fan-out (QA F5, F6)

(defun gascity-inv--fanout (stub names)
  "Run the work fan-out over NAMES with read STUB; return (RESOLVED . REJECTED)."
  (let (resolved rejected)
    (cl-letf (((symbol-function 'gascity-reader-read-async) stub))
      (gascity-dashboard--read-work-stores
       names default-directory
       (lambda (v) (setq resolved v))
       (lambda (e) (setq rejected e))))
    (cons resolved rejected)))

(ert-deftest gascity-test-cockpit-fanout-partial-failure-degrades ()
  "One failing store degrades to :errors; the others' beads still resolve."
  (let ((result (gascity-inv--fanout
                 (lambda (args cb &optional eb &rest _)
                   (if (member "beads.el" args)
                       (funcall eb "rig not found")
                     (funcall cb (vector `((id . ,(or (car (last args)) "c")))))))
                 '("beads.el" "gascity.el"))))
    (should-not (cdr result))
    (should (= (length (plist-get (car result) :beads)) 2))
    (should (equal (plist-get (car result) :errors) '("beads.el: rig not found")))
    ;; Stamped with the owning store (nil for the city store).
    (should (member '(gascity-rig . "gascity.el")
                    (car (last (plist-get (car result) :beads))))))
  (let ((result (gascity-inv--fanout
                 (lambda (_args _cb &optional eb &rest _) (funcall eb "down"))
                 '("beads.el"))))
    (should-not (car result))
    (should (cdr result))))

(ert-deftest gascity-test-cockpit-fanout-no-rigs-reads-city-store ()
  "No rigs: exactly one read, of the city store, without `--rig' (QA F6)."
  (let* ((reads nil)
         (result (gascity-inv--fanout
                  (lambda (args cb &rest _) (push args reads) (funcall cb []))
                  nil)))
    (should (equal (plist-get (car result) :beads) nil))
    (should (= (length reads) 1))
    (should-not (member "--rig" (car reads))))
  ;; The HQ row of `gc rig list' is the city store, never `--rig <city>'.
  (should (equal (gascity-dashboard--rig-store-names
                  (list (gascity-domain-decode 'gascity-rig
                                               '((name . "emacs-city") (hq . t)))
                        (gascity-domain-decode 'gascity-rig
                                               '((name . "beads.el")))))
                 '("beads.el"))))

(ert-deftest gascity-test-cockpit-fanout-keeps-city-from-callback ()
  "Store reads started from the rig-list callback run in the loader's
directory, whatever buffer is current when the callback fires (QA F5)."
  (let ((dirs nil)
        (rig-list-cb nil))
    (cl-letf (((symbol-function 'gascity-rigs-cached) (lambda (&rest _) nil))
              ((symbol-function 'gascity-reader-read-async)
               (lambda (args cb &rest _)
                 (if (equal args '("rig" "list"))
                     (setq rig-list-cb cb)
                   (push default-directory dirs)
                   (funcall cb [])))))
      (let ((default-directory "/tmp/city/"))
        (gascity-dashboard--read-work #'ignore #'ignore))
      (with-temp-buffer
        (setq default-directory "/elsewhere/")
        (funcall rig-list-cb '((rigs . [((name . "beads.el"))])))))
    (should (= (length dirs) 2))
    (should (seq-every-p (lambda (d) (equal d "/tmp/city/")) dirs))))

;;; Point across a refresh

(ert-deftest gascity-test-cockpit-refresh-preserves-cursor-on-row ()
  "Point follows its row by semantic id when a refresh reorders rows."
  (gascity-inv--with-cockpit
    (goto-char (point-min))
    (re-search-forward "^  ○ mayor")
    (beginning-of-line)
    (let ((id (gascity-section--line-id)))
      (should (equal id '(thing . "agent:mayor")))
      ;; The refresh brings a new, more recently active agent above mayor.
      (let ((orig (symbol-function 'gascity-cockpit-test--scenario-read)))
        (cl-letf (((symbol-function 'gascity-cockpit-test--scenario-read)
                   (lambda (args cb &rest rest)
                     (if (equal args '("session" "list"))
                         (let ((data (gascity-cockpit-test--json
                                      "emacs-city.session-list.json")))
                           (setf (alist-get 'sessions data)
                                 (vconcat
                                  (list `((id . "ec-new1") (agent_name . "aaa/new")
                                          (state . "active")
                                          (last_active . ,(gascity-cockpit-test--ts 5))))
                                  (alist-get 'sessions data)))
                           (funcall cb data))
                       (apply orig args cb rest)))))
          (gascity-dashboard-refresh)))
      (should (gascity-inv--has "aaa/new"))
      (should (equal (gascity-section--line-id) id)))))

(ert-deftest gascity-test-cockpit-refresh-preserves-window-point-non-selected ()
  "A cockpit in a non-selected window keeps its window-point on its row."
  (gascity-inv--with-cockpit
    (let ((buf (current-buffer))
          (other (get-buffer-create "*gascity-inv-other*")))
      (unwind-protect
          (let (target)
            (goto-char (point-min))
            (re-search-forward "^  ○ mayor")
            (setq target (line-beginning-position))
            (set-window-buffer (selected-window) other)
            (let ((win (split-window (selected-window) nil 'below)))
              (set-window-buffer win buf)
              (set-window-point win target)
              (gascity-dashboard-refresh)
              (let ((wp (window-point win)))
                (should (> wp 1))
                (with-current-buffer buf
                  (save-excursion
                    (goto-char wp)
                    (should (equal (gascity-section--line-id)
                                   '(thing . "agent:mayor"))))))))
        (kill-buffer other)))))

;;; Prompts read the rig memo only

(ert-deftest gascity-test-cockpit-rig-prompts-no-sync-gc ()
  "The `/ -r', `j g' and `j b' prompts offer the memoized rigs; no sync gc."
  (let ((boom (lambda (&rest args) (error "Sync gc: %S" args)))
        (offered nil))
    (cl-letf (((symbol-function 'gascity-reader-read) boom)
              ((symbol-function 'gascity-reader-run) boom)
              ((symbol-function 'gascity-rigs-cached)
               (lambda (&rest _)
                 (list (gascity-domain-decode 'gascity-rig '((name . "beads.el")))
                       (gascity-domain-decode 'gascity-rig
                                              '((name . "emacs-city") (hq . t))))))
              ((symbol-function 'completing-read)
               (lambda (_p coll &rest _) (setq offered coll) "beads.el"))
              ((symbol-function 'gascity-rig-dashboard) #'ignore)
              ((symbol-function 'gascity-rig-beads) #'ignore)
              ((symbol-function 'gascity-rig-at-point) (lambda () nil)))
      (with-temp-buffer
        (let ((set nil))
          (setq-local gascity-filter-set-function (lambda (k v) (setq set (cons k v))))
          (call-interactively #'gascity-dashboard-filter-rig)
          (should (member "beads.el" offered))
          (should (equal set '(:rig . "beads.el")))))
      (call-interactively #'gascity-jump-rig)
      (should (member "beads.el" offered))
      (call-interactively #'gascity-jump-beads)
      (should (equal offered '("city" "beads.el"))))))

(provide 'gascity-invariants-test)
;;; gascity-invariants-test.el ends here
