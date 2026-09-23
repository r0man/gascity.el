;;; ga-eyw9-acceptance.el --- scripted TRAMP acceptance for ga-eyw9 -*- lexical-binding: t; -*-

;; Batch-Emacs acceptance check for bead ga-eyw9 against the real
;; bright-lights city over TRAMP (/ssh:localhost:/home/roman/bright-lights):
;;
;;   1. open the session list for the remote city, wait for a live read;
;;   2. kill the pooled TRAMP connection mid-session (the dropped-link
;;      incident);
;;   3. run several auto-refresh ticks and collect every visible error;
;;   4. require the failure episode to produce at most ONE visible error
;;      line (dedupe + backoff), then a manual refresh (`g' path) to
;;      reconnect and self-heal silently — stale marker cleared.
;;
;; Run from the repo root via the ERT wrapper
;; `gascity-test-remote-ga-eyw9-acceptance-live' (it skips itself when
;; the city is not reachable), or standalone:
;;   eldev -s emacs --batch -l scripts/ga-eyw9-acceptance.el -f ga-eyw9--main

(require 'tramp)
(require 'gascity)

(defconst ga-eyw9--city "/ssh:localhost:/home/roman/bright-lights/")

(defvar ga-eyw9--messages nil
  "Every echo-area message text recorded during the run.")

(defvar ga-eyw9--buffer nil
  "The host-qualified session-list buffer (names are keyed to the city).")

(defun ga-eyw9--note (fmt &rest args)
  (message "ga-eyw9: %s" (apply #'format fmt args)))

;; Capture every echo-area message with its text.
(advice-add 'message :before
            (lambda (fmt &rest args)
              (when (stringp fmt)
                (push (apply #'format fmt args) ga-eyw9--messages))))

(defun ga-eyw9--open-list ()
  "Open the session-list buffer for the remote city and wait for rows.
The buffer name is host-qualified by `gascity-view-get-buffer-create',
so keep the buffer object, not the unqualified name."
  (let ((default-directory ga-eyw9--city))
    (setq ga-eyw9--buffer (gascity-view-get-buffer-create
                           gascity-session-list-buffer-name))
    (with-current-buffer ga-eyw9--buffer
      ;; Like `gascity-tabulated--show': ensure the mode (which seeds
      ;; `tabulated-list-format' and the auto-refresh timer) is set up.
      (unless (derived-mode-p 'gascity-session-list-mode)
        (gascity-session-list-mode))
      (gascity-session-list-refresh))
    ;; Pump until the refresh settles (cap ~30s).
    (let ((deadline (+ (float-time) 30)))
      (while (and (< (float-time) deadline)
                  (process-live-p
                   (buffer-local-value 'gascity-tabulated--refresh-process
                                       ga-eyw9--buffer)))
        (accept-process-output nil 0.2)))))

(defun ga-eyw9--tick (buffer)
  "One auto-refresh tick against BUFFER, with a settle wait."
  (gascity-session-list--auto-refresh-tick buffer)
  (let ((deadline (+ (float-time) 30)))
    (while (and (< (float-time) deadline)
                (process-live-p
                 (buffer-local-value 'gascity-tabulated--refresh-process buffer)))
      (accept-process-output nil 0.2))))

(defun ga-eyw9-run ()
  "Run the full acceptance flow; return the number of failed checks."
  (let ((failures 0))
    (setq ga-eyw9--messages nil)
    ;; Phase 1: open the list against the live city.
    (ga-eyw9--open-list)
    (let* ((buf ga-eyw9--buffer)
           (alive (and buf (buffer-live-p buf)
                       (file-directory-p ga-eyw9--city))))
      (unless alive
        (error "ga-eyw9: could not open a live session list for %s" ga-eyw9--city))
      (ga-eyw9--note "phase 1 ok: session list live against %s" ga-eyw9--city)
      ;; Phase 2: kill the pooled connection (the dropped-link event).
      (let* ((vec (tramp-dissect-file-name ga-eyw9--city))
             (proc (tramp-get-connection-process vec)))
        (when (process-live-p proc)
          (delete-process proc)
          (ga-eyw9--note "phase 2 ok: killed TRAMP connection %s"
                         (process-name proc)))
        (sit-for 1))
      ;; Phase 3: run 8 auto-refresh ticks with a visible buffer.
      (cl-letf (((symbol-function 'get-buffer-window)
                 (lambda (&rest _) 'visible-window)))
        (let ((before-ticks (length ga-eyw9--messages)))
          (dotimes (_ 8) (ga-eyw9--tick buf) (sit-for 0.3))
          (let* ((episode (cl-subseq ga-eyw9--messages 0
                                     (- (length ga-eyw9--messages)
                                        before-ticks)))
                 (errors (cl-remove-if-not
                          (lambda (m) (string-match-p "gascity: " m)) episode)))
            (ga-eyw9--note "phase 3: %d echo-area messages, %d error lines \
in episode"
                           (length episode) (length errors))
            (dolist (e errors) (ga-eyw9--note "  episode error: %s" e))
            (when (> (length errors) 1)
              (cl-incf failures)
              (ga-eyw9--note
               "FAIL: more than one visible error in the episode")))
          ;; Phase 4: self-heal — the manual refresh (`g' path) may
          ;; re-establish the connection; confirm the stale marker
          ;; cleared and no new error line was needed.
          (with-current-buffer buf
            (let ((gascity-remote-sync-timeout 30))
              (gascity-session-list-refresh)))
          (let ((deadline (+ (float-time) 60)))
            (while (and (< (float-time) deadline)
                        (process-live-p
                         (buffer-local-value
                          'gascity-tabulated--refresh-process buf)))
              (accept-process-output nil 0.2)))
          (with-current-buffer buf
            (if gascity-tabulated--stale-errors
                (progn (cl-incf failures)
                       (ga-eyw9--note
                        "FAIL: stale marker %s survived a successful refresh"
                        gascity-tabulated--stale-errors))
              (ga-eyw9--note "phase 4 ok: view healed, stale marker cleared"))))))
    (if (zerop failures)
        (progn (ga-eyw9--note "ACCEPTANCE PASS") failures)
      (ga-eyw9--note "ACCEPTANCE FAIL (%d checks)" failures)
      failures)))

(defun ga-eyw9--main ()
  "Standalone entry: run and exit nonzero on failure."
  (when (> (ga-eyw9-run) 0) (kill-emacs 1)))
