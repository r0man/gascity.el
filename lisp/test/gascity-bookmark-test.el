;;; gascity-bookmark-test.el --- Bookmarks for every gascity view -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Records are made from buffer state alone (a remote view is recorded
;; under the render guard, its host never contacted); a jump binds the
;; recorded city and opens the view through its usual entry command,
;; with its arguments and filters.  Nothing here runs gc.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(defconst gascity-bookmark-test--remote
  "/ssh:gascity@burningswell.com:/home/gascity/burningswell/"
  "A remote city root; the tests never connect to it.")

(defun gascity-bookmark-test--setup (kind)
  "Set this buffer up as a KIND view with some state; return nothing.
The view's mode is entered in a local directory; the caller then
points `default-directory' at the city."
  (pcase kind
    ('rig (setq-local gascity-rig-dashboard--rig-name "burningswell-cl"))
    ('agent (setq-local gascity-section--agent
                        (make-instance 'gascity-agent :name "burningswell-cl/gc.run-operator-1"
                                       :rig "burningswell-cl"
                                       :session-name "gc__run-operator-bu-v67b"
                                       :socket "burningswell")))
    ('run (setq gascity-run--current-run "bs-8jif"
                gascity-run--current-rig "burningswell-cl"))
    ('events (setq gascity-events--filter '(:window "1h" :unfold t)))
    ('agents (setq gascity-agents--filter '(:state "stalled" :rig "burningswell-cl")))
    ('mail (setq gascity-mail-inbox--filter '(:unread t)))
    ('mail-thread (setq gascity-mail-thread--id "bu-th1"
                        gascity-mail-thread--messages
                        (list (make-instance 'gascity-mail-message
                                             :id "bu-m1" :thread-id "bu-th1"
                                             :from "mayor" :to "human"
                                             :subject "context cycle"
                                             :body "secret body"))))
    ('sessions (setq gascity-session-list--filter '(:state "active")))))

(defun gascity-bookmark-test--record (kind dir)
  "Return the record of a KIND view pinned to DIR, made under the guard."
  (gascity-test-with-temp-view
    (let ((default-directory temporary-file-directory))
      (funcall (plist-get (alist-get kind gascity-bookmark-kinds) :mode)))
    (gascity-bookmark-test--setup kind)
    (setq default-directory dir)
    (cl-letf (((symbol-function 'gascity-dashboard--state)
               (lambda (key) (and (eq key :filters) '(:rig "burningswell-cl")))))
      (gascity-test-with-render-guard
        (prog1 (funcall bookmark-make-record-function)
          (should-not gascity-test-render-guard-violations))))))

(ert-deftest gascity-test-bookmark-every-view-records-without-io ()
  "Every view kind sets `bookmark-make-record-function'; a remote view's
record names the kind, the city and the handler with no I/O."
  (gascity-context-remember-city-root gascity-bookmark-test--remote)
  (dolist (kind (mapcar #'car gascity-bookmark-kinds))
    (let ((rec (gascity-bookmark-test--record kind gascity-bookmark-test--remote)))
      (should (stringp (car rec)))
      (should (eq (bookmark-prop-get rec 'gascity-view) kind))
      (should (equal (bookmark-prop-get rec 'filename) gascity-bookmark-test--remote))
      (should (equal (bookmark-prop-get rec 'location) gascity-bookmark-test--remote))
      (should (eq (bookmark-prop-get rec 'handler) 'gascity-bookmark-jump))
      (should (eq (and (bookmark-prop-get rec 'gascity-city-root) t)
                  (not (eq kind 'cities)))))))

(ert-deftest gascity-test-bookmark-records-args-and-filters ()
  "A record keeps the view's arguments and filters, never a mail body."
  (gascity-context-remember-city-root gascity-bookmark-test--remote)
  (let ((rec (lambda (kind) (gascity-bookmark-test--record
                             kind gascity-bookmark-test--remote))))
    (should (equal (bookmark-prop-get (funcall rec 'run) 'gascity-args)
                   '(:run "bs-8jif" :rig "burningswell-cl")))
    (should (equal (bookmark-prop-get (funcall rec 'rig) 'gascity-args)
                   '(:rig "burningswell-cl")))
    (should (equal (plist-get (bookmark-prop-get (funcall rec 'agent) 'gascity-args)
                              :session-name)
                   "gc__run-operator-bu-v67b"))
    (should (equal (bookmark-prop-get (funcall rec 'events) 'gascity-filters)
                   '(:window "1h" :unfold t)))
    (should (equal (bookmark-prop-get (funcall rec 'dashboard) 'gascity-filters)
                   '(:rig "burningswell-cl")))
    (should (equal (bookmark-prop-get (funcall rec 'sessions) 'gascity-filters)
                   '(:state "active")))
    (let ((thread (funcall rec 'mail-thread)))
      (should (equal (plist-get (bookmark-prop-get thread 'gascity-args) :thread) "bu-th1"))
      (should-not (string-match-p "secret body" (prin1-to-string thread))))))

(ert-deftest gascity-test-bookmark-default-names ()
  "Default names: the view, then its object or city, `@host' when remote."
  (gascity-context-remember-city-root gascity-bookmark-test--remote)
  (gascity-context-remember-city-root "/home/roman/bright-lights/")
  (let ((name (lambda (kind dir) (car (gascity-bookmark-test--record kind dir)))))
    (should (equal (funcall name 'dashboard gascity-bookmark-test--remote)
                   "gascity: burningswell@burningswell.com"))
    (should (equal (funcall name 'dashboard "/home/roman/bright-lights/")
                   "gascity: bright-lights"))
    (should (equal (funcall name 'runs "/home/roman/bright-lights/")
                   "gascity-runs: bright-lights"))
    (should (equal (funcall name 'run gascity-bookmark-test--remote)
                   "gascity-run: bs-8jif@burningswell.com"))
    (should (equal (funcall name 'rig gascity-bookmark-test--remote)
                   "gascity-rig: burningswell-cl@burningswell.com"))
    (should (equal (funcall name 'agent "/home/roman/bright-lights/")
                   "gascity-agent: burningswell-cl/gc.run-operator-1"))
    (should (equal (funcall name 'mail-thread "/home/roman/bright-lights/")
                   "gascity-mail-thread: bu-th1"))
    (should (equal (funcall name 'sessions gascity-bookmark-test--remote)
                   "gascity-sessions: burningswell@burningswell.com"))))

;;; Jumping

(defun gascity-bookmark-test--jump (rec)
  "Jump to REC the way `bookmark-jump' does; return the displayed buffer."
  (let ((shown nil))
    (save-window-excursion
      (bookmark-jump rec (lambda (buf) (setq shown buf))))
    shown))

(ert-deftest gascity-test-bookmark-jump-opens-view-with-args ()
  "The handler binds the recorded city (memoizing its root, so nothing
walks) and calls the view's entry command with the recorded arguments;
bookmark.el gets the view's buffer to display."
  (gascity-context-remember-city-root gascity-bookmark-test--remote)
  (let* ((rec (gascity-bookmark-test--record 'run gascity-bookmark-test--remote))
         (called nil)
         (view (get-buffer-create " *gascity-bookmark-run*")))
    (clrhash gascity-context--root-cache)
    (unwind-protect
        (cl-letf (((symbol-function 'gascity-run-show)
                   (lambda (run convoy rig)
                     (setq called (list default-directory
                                        (gascity-context-city-root-cached)
                                        run convoy rig))
                     (pop-to-buffer view))))
          (should (eq (gascity-bookmark-test--jump rec) view))
          (should (equal called (list gascity-bookmark-test--remote
                                      gascity-bookmark-test--remote
                                      "bs-8jif" nil "burningswell-cl"))))
      (kill-buffer view))))

(ert-deftest gascity-test-bookmark-jump-agent-and-thread ()
  "The agent detail and a mail thread reopen from their recorded args."
  (let ((dir "/home/roman/bright-lights/")
        agent message)
    (gascity-context-remember-city-root dir)
    (cl-letf (((symbol-function 'gascity-polecat-detail)
               (lambda (a) (setq agent a) (set-buffer (get-buffer-create " *bm-a*"))))
              ((symbol-function 'gascity-mail-thread-show)
               (lambda (m) (setq message m) (set-buffer (get-buffer-create " *bm-t*")))))
      (gascity-bookmark-test--jump (gascity-bookmark-test--record 'agent dir))
      (gascity-bookmark-test--jump (gascity-bookmark-test--record 'mail-thread dir)))
    (should (equal (gascity-agent-session-name agent) "gc__run-operator-bu-v67b"))
    (should (equal (gascity-mail-thread-id message) "bu-th1"))
    (should (equal (gascity-mail-subject message) "context cycle"))
    (should-not (gascity-mail-body message))
    (kill-buffer " *bm-a*")
    (kill-buffer " *bm-t*")))

(defun gascity-bookmark-test--jump-cockpit (dir)
  "Bookmark a cockpit in DIR, kill it, jump back.
Returns (RECORD . NEW-BUFFER).  Every gc read is parked (never answered)."
  (gascity-test-with-store-stubs reads _actions
    (let ((vui-render-delay nil) rec buf)
      (gascity-context-remember-city-root dir)
      (let ((default-directory dir))
        (save-window-excursion (gascity-dashboard) (setq buf (current-buffer))))
      (with-current-buffer buf (setq rec (bookmark-make-record)))
      (let ((kill-buffer-query-functions nil)) (kill-buffer buf))
      (ignore reads)
      (cons rec (gascity-bookmark-test--jump rec)))))

(ert-deftest gascity-test-bookmark-jump-cockpit-local-and-remote ()
  "A real cockpit jump, local and over /mock::, opens at once with `…'."
  (gascity-test-ensure-mock-method)
  (dolist (dir (list (file-name-as-directory temporary-file-directory)
                     gascity-test-mock-directory))
    (let* ((tramp-verbose 0)
           (_ (when (file-remote-p dir)
                (skip-unless (ignore-errors (file-directory-p dir)))))
           (jump (gascity-bookmark-test--jump-cockpit dir))
           (buf (cdr jump)))
      (unwind-protect
          (with-current-buffer buf
            (should (derived-mode-p 'gascity-dashboard-mode))
            (should (equal default-directory
                           (bookmark-prop-get (car jump) 'filename)))
            (should (equal (file-remote-p default-directory 'method)
                           (file-remote-p dir 'method)))
            (should (string-match-p "…" (buffer-string))))
        (let ((kill-buffer-query-functions nil)) (kill-buffer buf))))))

(ert-deftest gascity-test-bookmark-jump-restores-filters ()
  "The recorded filters are applied through the view's own setter."
  (let ((dir (file-name-as-directory temporary-file-directory)))
    (gascity-context-remember-city-root dir)
    (gascity-test-with-store-stubs _reads _actions
      (let ((rec (gascity-bookmark-test--record 'events dir))
            buf)
        (unwind-protect
            (progn
              (setq buf (gascity-bookmark-test--jump rec))
              (with-current-buffer buf
                (should (derived-mode-p 'gascity-events-mode))
                (should (equal (plist-get gascity-events--filter :window) "1h"))
                (should (eq (plist-get gascity-events--filter :unfold) t))))
          (when (buffer-live-p buf)
            (let ((kill-buffer-query-functions nil)) (kill-buffer buf))))))))

(provide 'gascity-bookmark-test)
;;; gascity-bookmark-test.el ends here
