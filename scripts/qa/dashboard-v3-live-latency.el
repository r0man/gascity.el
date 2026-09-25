;;; dashboard-v3-live-latency.el --- event → view latency, N events (batch) -*- lexical-binding: t; -*-
;; GCE_DIR=<city> [GCE_N=5] emacs --batch -L … -l this-file
;; Opens the cockpit, mail inbox and Agents; sends N mails from a shell
;; outside Emacs (8 s apart) and measures, per mail, the time until the
;; inbox and the cockpit's mail count show it; logs each debounced
;; batch (event types, reads started).  Archives every mail afterwards.
(require 'gascity)
(require 'cl-lib)
(setq gascity-live-in-batch t gascity-store-refetch-hidden t)
(defvar lt-dir (getenv "GCE_DIR"))
(defvar lt-n (string-to-number (or (getenv "GCE_N") "5")))
(defvar lt-t0 nil)
(defvar lt-batch-log nil)
(defun lt-log (fmt &rest a) (princ (format "[%s] %s\n" (format-time-string "%T.%3N") (apply #'format fmt a))))
(defun lt-pump (secs pred)
  (let ((deadline (+ (float-time) secs)) (cap 100000))
    (while (and (> cap 0) (< (float-time) deadline) (not (funcall pred)))
      (setq cap (1- cap)) (accept-process-output nil 0.05))))
(defun lt-gc (&rest args)
  (with-temp-buffer
    (let ((default-directory "/home/roman/bright-lights/"))
      (apply #'call-process "gc" nil t nil args))
    (buffer-string)))
(add-hook 'gascity-live-invalidate-functions
          (lambda (_root _kinds types)
            (when lt-t0
              (lt-log "  batch +%.1fs types=%S reads-in-flight=%S"
                      (- (float-time) lt-t0) types
                      (plist-get (gascity-store-host-status lt-dir) :reads)))))
(advice-add 'gascity-store--start :before
            (lambda (job) (when (and lt-t0 (gascity-store--job-entry job))
                            (lt-log "    start +%.1fs %S" (- (float-time) lt-t0)
                                    (gascity-store-entry-args (gascity-store--job-entry job))))))
(let* ((default-directory lt-dir) views inbox-lat count-lat subjects)
  (save-window-excursion
    (dolist (cmd '(gascity-dashboard gascity-mail-inbox gascity-agents))
      (funcall cmd) (push (cons cmd (current-buffer)) views)))
  (lt-pump 60 (lambda () (and (eq 'live (plist-get (gascity-live-status lt-dir) :state))
                              (= 0 (plist-get (gascity-store-host-status lt-dir) :reads)))))
  (dotimes (i lt-n)
    (let* ((subject (format "v3-latency %d-%d" i (random 100000)))
           (unread0 (alist-get 'unread (plist-get (gascity-store-get '("mail" "count") lt-dir) :data)))
           inbox-at count-at)
      (push subject subjects)
      (lt-gc "mail" "send" "human" "-s" subject "-m" "latency check; archived right after")
      (setq lt-t0 (float-time))
      (lt-log "sent %s" subject)
      ;; GCE_BURST=1: an order.* / bead.* burst lands in the same batch
      ;; (synthetic events handed to the stream, as an order sweep does).
      (when (getenv "GCE_BURST")
        (let ((stream (gethash (gascity-live--root lt-dir) gascity-live--streams)))
          (dotimes (k 12)
            (gascity-live--deliver
             stream (list `((type . ,(nth (% k 3) '("order.fired" "bead.created" "bead.closed")))
                            (subject . "burst")))))))
      (lt-pump 20 (lambda ()
                    (unless inbox-at
                      (when (with-current-buffer (alist-get 'gascity-mail-inbox views)
                              (string-search subject (buffer-string)))
                        (setq inbox-at (- (float-time) lt-t0))))
                    (unless count-at
                      (let ((u (alist-get 'unread (plist-get (gascity-store-get '("mail" "count") lt-dir) :data))))
                        (when (and u unread0 (> u unread0)) (setq count-at (- (float-time) lt-t0)))))
                    (and inbox-at count-at)))
      (lt-log "event %d: inbox %.1fs  count %.1fs" i (or inbox-at -1) (or count-at -1))
      (push inbox-at inbox-lat) (push count-at count-lat)
      (setq lt-t0 nil)
      (lt-pump 8 #'ignore)))
  (let ((f (lambda (l) (let ((s (sort (delq nil (copy-sequence l)) #'<)))
                         (format "p50 %.1fs max %.1fs (n=%d)" (nth (/ (length s) 2) s) (car (last s)) (length s))))))
    (lt-log "INBOX %s" (funcall f inbox-lat))
    (lt-log "COUNT %s" (funcall f count-lat)))
  ;; Restore.
  (let ((inbox (json-parse-string (lt-gc "mail" "inbox" "--json") :object-type 'alist)))
    (seq-doseq (m (alist-get 'messages inbox))
      (when (member (alist-get 'subject m) subjects)
        (lt-gc "mail" "archive" (alist-get 'id m)))))
  (lt-log "restored: %s" (string-trim (lt-gc "mail" "count" "--json"))))
