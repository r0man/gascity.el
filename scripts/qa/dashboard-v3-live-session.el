;;; dashboard-v3-live-session.el --- session action → Agents views (batch) -*- lexical-binding: t; -*-
;; GCE_DIR=<city> emacs --batch -L … -l this-file
;; Opens the cockpit and the Agents table, suspends then wakes the pool
;; agent bd.dog-1 from Emacs (async actions) and times when both views
;; show the new state with no `g'; then waits for it to be active again.
(require 'gascity)
(require 'cl-lib)
(setq gascity-live-in-batch t gascity-store-refetch-hidden t)
(defvar ls-dir (getenv "GCE_DIR"))
(defvar ls-agent "bd.dog-1")
(defun ls-log (fmt &rest a) (princ (format "[%s] %s\n" (format-time-string "%T.%3N") (apply #'format fmt a))))
(defun ls-pump (secs pred)
  (let ((deadline (+ (float-time) secs)) (cap 100000))
    (while (and (> cap 0) (< (float-time) deadline) (not (funcall pred)))
      (setq cap (1- cap)) (accept-process-output nil 0.05))))
(defun ls-line (buf)
  (and (buffer-live-p buf)
       (with-current-buffer buf
         (save-excursion
           (goto-char (point-min))
           (and (search-forward ls-agent nil t)
                (buffer-substring-no-properties (line-beginning-position) (line-end-position)))))))
(defun ls-state ()
  (with-temp-buffer
    (let ((default-directory "/home/roman/bright-lights/"))
      (call-process "gc" nil t nil "session" "list" "--json"))
    (let ((d (json-parse-string (buffer-string) :object-type 'alist)))
      (alist-get 'state (seq-find (lambda (s) (equal (alist-get 'agent_name s) ls-agent))
                                  (alist-get 'sessions d))))))
(let* ((default-directory ls-dir) views)
  (save-window-excursion
    (dolist (cmd '(gascity-dashboard gascity-agents))
      (funcall cmd) (push (cons cmd (current-buffer)) views)))
  (ls-pump 60 (lambda () (and (eq 'live (plist-get (gascity-live-status ls-dir) :state))
                              (= 0 (plist-get (gascity-store-host-status ls-dir) :reads))
                              (ls-line (alist-get 'gascity-agents views)))))
  ;; Every state in the Agents table, so its state column shows the change.
  (with-current-buffer (alist-get 'gascity-agents views)
    (setq gascity-agents--filter nil)
    (gascity-agents--render))
  (ls-log "before: gc state %s" (ls-state))
  (ls-log "  agents : %s" (ls-line (alist-get 'gascity-agents views)))
  (ls-log "  cockpit: %s" (ls-line (alist-get 'gascity-dashboard views)))
  ;; A view "updated" when bd.dog-1's row text changed from what it was
  ;; before the action (a pending `…' does not count; the Agents table's
  ;; default `running' filter may drop the row, which counts).
  (dolist (step '(("suspend" gascity-session-suspend)
                  ("wake" gascity-session-wake)))
    (let* ((t0 (float-time)) agents-at cockpit-at
           (clean (lambda (l) (and l (replace-regexp-in-string " +" " " l))))
           (a0 (funcall clean (ls-line (alist-get 'gascity-agents views))))
           (c0 (funcall clean (ls-line (alist-get 'gascity-dashboard views))))
           (changed (lambda (buf before)
                      (let ((l (funcall clean (ls-line buf))))
                        (and (not (equal l before))
                             (not (and l (string-search "…" l))))))))
      (funcall (nth 1 step) ls-agent)
      (ls-log "%s returned in %.3fs" (car step) (- (float-time) t0))
      (ls-pump 15 (lambda ()
                    (unless agents-at
                      (when (funcall changed (alist-get 'gascity-agents views) a0)
                        (setq agents-at (- (float-time) t0))))
                    (unless cockpit-at
                      (when (funcall changed (alist-get 'gascity-dashboard views) c0)
                        (setq cockpit-at (- (float-time) t0))))
                    (and agents-at cockpit-at)))
      (ls-log "%s: Agents %s s, cockpit %s s" (car step)
              (and agents-at (format "%.1f" agents-at)) (and cockpit-at (format "%.1f" cockpit-at)))
      (ls-log "  agents : %s" (ls-line (alist-get 'gascity-agents views)))
      (ls-log "  cockpit: %s" (ls-line (alist-get 'gascity-dashboard views)))))
  ;; Back to active (the reconciler's pace): the cockpit row returns.
  (let ((t0 (float-time)))
    (ls-pump 240 (lambda () (let ((l (ls-line (alist-get 'gascity-dashboard views))))
                              (and l (string-search "active" l)))))
    (ls-log "cockpit shows it active again after %.1fs (gc state %s)"
            (- (float-time) t0) (ls-state))
    (ls-log "  cockpit: %s" (ls-line (alist-get 'gascity-dashboard views)))))
