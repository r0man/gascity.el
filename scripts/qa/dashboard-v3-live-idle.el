;;; dashboard-v3-live-idle.el --- gc spawns of an idle cockpit (batch) -*- lexical-binding: t; -*-
;; GCE_DIR=<city> [GCE_SECS=60] emacs --batch -L … -l this-file
;; Opens the cockpit with its live stream, waits until the first paint
;; settles, then counts every gc process started over GCE_SECS seconds
;; (the stream itself excluded) and the events the stream delivered.
(require 'gascity)
(require 'cl-lib)
(setq gascity-live-in-batch t gascity-store-refetch-hidden t)
(defvar li-dir (getenv "GCE_DIR"))
(defvar li-secs (string-to-number (or (getenv "GCE_SECS") "60")))
(defvar li-spawns nil)
(defvar li-events 0)
(defvar li-counting nil)
(advice-add 'make-process :before
            (lambda (&rest a)
              (when li-counting
                (let* ((cmd (plist-get a :command))
                       (s (mapconcat #'identity cmd " ")))
                  (when (and (string-match-p "\\bgc\\b\\|/gc " s)
                             (not (string-match-p "events --follow" s)))
                    (push (if (string-match "\\(?:gc\\|exec [^ ]*gc\\)'? \\(.*\\)" s)
                              (replace-regexp-in-string "--city [^ ]+ " "" (match-string 1 s))
                            s)
                          li-spawns))))))
(advice-add 'gascity-live--deliver :before
            (lambda (_s events) (when li-counting (cl-incf li-events (length events)))))
(defun li-pump (secs pred)
  (let ((deadline (+ (float-time) secs)) (cap 100000))
    (while (and (> cap 0) (< (float-time) deadline) (not (funcall pred)))
      (setq cap (1- cap)) (accept-process-output nil 0.05))))
(let ((default-directory li-dir))
  (save-window-excursion (gascity-dashboard))
  (li-pump 60 (lambda () (and (eq 'live (plist-get (gascity-live-status li-dir) :state))
                              (= 0 (plist-get (gascity-store-host-status li-dir) :reads)))))
  (li-pump 5 #'ignore)
  (setq li-counting t)
  (li-pump li-secs #'ignore)
  (setq li-counting nil)
  (princ (format "IDLE %ds: %d gc spawns, %d events delivered\n" li-secs (length li-spawns) li-events))
  (let ((c (make-hash-table :test 'equal)))
    (dolist (s li-spawns) (puthash (substring s 0 (min 70 (length s))) (1+ (gethash (substring s 0 (min 70 (length s))) c 0)) c))
    (maphash (lambda (k v) (princ (format "  %3d  %s\n" v k))) c)))
