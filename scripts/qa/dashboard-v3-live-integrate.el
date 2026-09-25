;;; dashboard-v3-live-integrate.el --- live stream reaches every view (batch) -*- lexical-binding: t; -*-
;; GCE_DIR=<city dir> emacs --batch -L … -l this-file
;; Opens the cockpit, mail inbox, Agents, Runs, Health and session list,
;; sends one mail from a shell OUTSIDE Emacs, and measures how long each
;; mail-dependent view takes to show it with no `g'; then archives it.
(require 'gascity)
(require 'cl-lib)
(setq gascity-live-in-batch t
      ;; Batch has no visible windows; let invalidations reach every view.
      gascity-store-refetch-hidden t)
(defvar li-dir (getenv "GCE_DIR"))
(defun li-log (fmt &rest a) (princ (format "[%s] %s\n" (format-time-string "%T.%3N") (apply #'format fmt a))))
(defun li-pump (secs pred)
  (let ((deadline (+ (float-time) secs)) (cap 100000))
    (while (and (> cap 0) (< (float-time) deadline) (not (funcall pred)))
      (setq cap (1- cap)) (accept-process-output nil 0.05))))
(defun li-gc (&rest args)
  (with-temp-buffer
    (let ((default-directory "/home/roman/bright-lights/"))
      (apply #'call-process "gc" nil t nil args))
    (buffer-string)))
(defun li-buf-has (buf s) (and (buffer-live-p buf) (with-current-buffer buf (string-search s (buffer-string)))))
(let* ((default-directory li-dir)
       (subject (format "v3-integrate check %d" (random 100000)))
       views)
  (save-window-excursion
    (dolist (cmd '(gascity-dashboard gascity-mail-inbox gascity-agents gascity-runs
                   gascity-health gascity-session-list))
      (funcall cmd)
      (push (cons cmd (current-buffer)) views)))
  (li-log "opened %d views" (length views))
  (li-pump 60 (lambda () (let ((st (gascity-store-host-status li-dir)))
                           (and (= 0 (plist-get st :reads)) (= 0 (plist-get st :queued))
                                (eq 'live (plist-get (gascity-live-status li-dir) :state))))))
  (li-log "live state: %S" (plist-get (gascity-live-status li-dir) :state))
  (dolist (v views)
    (with-current-buffer (cdr v)
      (li-log "%-22s header/mode: %s" (car v)
              (substring-no-properties (or (gascity-ui-live-string) "-")))))
  (let ((unread0 (alist-get 'unread (plist-get (gascity-store-get '("mail" "count") li-dir) :data)))
        t0 inbox-at count-at cockpit-at)
    (li-log "baseline unread %S; sending %S" unread0 subject)
    (li-gc "mail" "send" "human" "-s" subject "-m" "dashboard-v3 integration check; archived right after")
    ;; Measured from the moment gc has committed the message.
    (setq t0 (float-time))
    (li-pump 15 (lambda ()
                  (unless inbox-at
                    (when (li-buf-has (alist-get 'gascity-mail-inbox views) subject)
                      (setq inbox-at (- (float-time) t0))))
                  (unless count-at
                    (let ((u (alist-get 'unread (plist-get (gascity-store-get '("mail" "count") li-dir) :data))))
                      (when (and u unread0 (> u unread0)) (setq count-at (- (float-time) t0)))))
                  (unless cockpit-at
                    (when (and count-at (li-buf-has (alist-get 'gascity-dashboard views)
                                                    (format "%d unread" (1+ unread0))))
                      (setq cockpit-at (- (float-time) t0))))
                  (and inbox-at count-at cockpit-at)))
    (li-log "mail inbox view shows it after %s s" (and inbox-at (format "%.1f" inbox-at)))
    (li-log "store mail count updated after %s s" (and count-at (format "%.1f" count-at)))
    (li-log "cockpit header shows it after %s s" (and cockpit-at (format "%.1f" cockpit-at)))
    ;; Restore: archive the check message.
    (let* ((inbox (json-parse-string (li-gc "mail" "inbox" "--json") :object-type 'alist))
           (msg (seq-find (lambda (m) (equal (alist-get 'subject m) subject))
                          (alist-get 'messages inbox))))
      (when msg
        (li-gc "mail" "archive" (alist-get 'id msg))
        (li-log "archived %s" (alist-get 'id msg))))
    (li-pump 10 (lambda () (not (li-buf-has (alist-get 'gascity-mail-inbox views) subject))))
    (li-log "after archive: inbox still shows it = %S; unread now %S"
            (and (li-buf-has (alist-get 'gascity-mail-inbox views) subject) t)
            (alist-get 'unread (plist-get (gascity-store-get '("mail" "count") li-dir) :data)))))
