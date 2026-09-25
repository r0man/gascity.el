;;; dashboard-v3-tramp-matrix.el --- dashboard-v3 §8.4 matrix driver (batch) -*- lexical-binding: t; -*-
;;
;; Opens every view of a city in one batch Emacs and records, per view:
;; the time the opening command blocked, the time until the store settled,
;; the peak concurrent remote gc processes, and every main-loop gap
;; > 200 ms; then refreshes everything at once (contention) and checks the
;; live stream advances.  Buffers are dumped to MX_OUT-MODE-VIEW.txt, the
;; log to MX_OUT-MODE.log (appended per line: batch stdout is buffered).
;;
;;   MX_MODE=local|ssh|ssh-da|tramp|tramp-da|mock  MX_OUT=/tmp/mx/out \
;;   [MX_DEADLINE=90] timeout 1200 emacs -Q --batch -L lisp ... -l THIS
;;
;; ssh = default ssh-pipe transport; -da = TRAMP direct-async enabled for
;; ssh:localhost; tramp = `gascity-remote-transport' 'tramp; mock = the
;; tramp-tests "mock" method (a non-ssh method: polling live).
;; See docs/qa/2026-09-25-dashboard-v3-tramp-matrix.md.
(require 'cl-lib)
(require 'tramp)
(defvar mx-mode (getenv "MX_MODE"))
(defvar mx-out (getenv "MX_OUT"))
(setq tramp-verbose 1)
(pcase mx-mode
  ((or "ssh-da" "tramp-da")
   (connection-local-set-profile-variables 'mx-da '((tramp-direct-async-process . t)))
   (connection-local-set-profiles '(:application tramp :protocol "ssh" :machine "localhost") 'mx-da)))
(require 'gascity)
(setq gascity-live-in-batch t)
(when (member mx-mode '("tramp" "tramp-da")) (setq gascity-remote-transport 'tramp))
(when (equal mx-mode "mock")
  (add-to-list 'tramp-methods '("mock" (tramp-login-program "sh") (tramp-login-args (("-i")))
                                (tramp-direct-async ("-c")) (tramp-remote-shell "/bin/sh")
                                (tramp-remote-shell-args ("-c")) (tramp-connection-timeout 10)))
  (add-to-list 'tramp-default-host-alist `("\\`mock\\'" nil ,(system-name))))
(defvar mx-dir (pcase mx-mode
                 ("local" "/home/roman/bright-lights/")
                 ("mock" "/mock::/home/roman/bright-lights/")
                 (_ "/ssh:localhost:/home/roman/bright-lights/")))
(defvar mx-phase "init")
(defvar mx-last (float-time))
(defvar mx-gaps nil)
(defvar mx-maxgc 0)
(defvar mx-phase-maxgc 0)
(defun mx-gc-count ()
  "Live gascity gc processes that reach the remote host (ssh pipe or TRAMP)."
  (cl-count-if (lambda (p) (and (process-live-p p)
                                (string-match-p "\\`gascity-gc\\(-action\\)?\\(<[0-9]+>\\)?\\'" (process-name p))
                                (or (equal mx-mode "local")
                                    (process-get p 'remote-command)
                                    (string-match-p "ssh\\'" (or (car (process-command p)) "")))))
               (process-list)))
(run-with-timer 0.02 0.02
  (lambda ()
    (let* ((now (float-time)) (gap (- now mx-last)) (n (mx-gc-count)))
      (when (> gap 0.2) (push (list mx-phase (/ (round (* gap 1000)) 1000.0)) mx-gaps))
      (setq mx-last now mx-maxgc (max mx-maxgc n) mx-phase-maxgc (max mx-phase-maxgc n)))))
(defun mx-log (fmt &rest args)
  (let ((line (concat (format-time-string "%T ") (apply #'format fmt args) "\n")))
    (let ((coding-system-for-write 'utf-8) (inhibit-message t))
      (write-region line nil (format "%s-%s.log" mx-out mx-mode) t 'silent))))
(defun mx-pump (secs pred)
  (let ((deadline (+ (float-time) secs)) (cap 200000))
    (while (and (> cap 0) (< (float-time) deadline) (not (funcall pred)))
      (setq cap (1- cap))
      (accept-process-output nil 0.05))))
(defun mx-settled-p (buf)
  (let ((st (gascity-store-host-status mx-dir)))
    (and (buffer-live-p buf)
         (not (gascity-store-buffer-pending-p buf))
         (= 0 (plist-get st :reads)) (= 0 (plist-get st :queued))
         (not (with-current-buffer buf (save-excursion (goto-char (point-min))
                                                       (re-search-forward "^\\(  \\|[A-Z][A-Za-z ]*  \\)…$" nil t)))))))
(defvar mx-results nil)
(defun mx-view (name opener)
  (setq mx-phase name mx-phase-maxgc 0)
  (let* ((default-directory mx-dir)
         (t0 (float-time))
         (buf (condition-case err
                  (save-window-excursion (funcall opener) (current-buffer))
                (error (mx-log "%s: OPEN ERROR %S" name err) nil)))
         (t1 (float-time)))
    (when buf
      ;; settle: stable for 1s
      (let ((stable 0) (deadline (+ t0 (string-to-number (or (getenv "MX_DEADLINE") "90")))))
        (while (and (< stable 3) (< (float-time) deadline))
          (mx-pump 0.35 (lambda () nil))
          (setq stable (if (mx-settled-p buf) (1+ stable) 0))))
      (let ((ready (- (float-time) t0 1.05)))
        (with-current-buffer buf
          (let ((text (buffer-substring-no-properties (point-min) (point-max))))
            (with-temp-file (format "%s-%s-%s.txt" mx-out mx-mode name) (insert text))
            (push (list name (- t1 t0) ready mx-phase-maxgc (count-lines (point-min) (point-max))
                        (string-match-p "■ gc\\|failed\\|timed out\\|◐" text))
                  mx-results)
            (mx-log "%-14s open %.3fs  ready %.1fs  maxgc %d  lines %d%s" name (- t1 t0) ready mx-phase-maxgc
                    (count-lines (point-min) (point-max))
                    (if (string-match "■ gc[^\n]*\\|◐" text) (concat "  ERR: " (match-string 0 text)) ""))))))))
(let ((default-directory mx-dir))
  (mx-view "cockpit" #'gascity-dashboard)
  (mx-view "agents" #'gascity-agents)
  (mx-view "agents-tree" #'gascity-agents-tree)
  (mx-view "agent-detail" (lambda () (gascity-polecat-detail (make-instance 'gascity-agent :name "mayor"))))
  (mx-view "runs" #'gascity-runs)
  (mx-view "run-detail" (lambda () (gascity-run-show "hw-hry" nil "hello-world")))
  (mx-view "health" #'gascity-health)
  (mx-view "cities" #'gascity-cities)
  (mx-view "rig" (lambda () (gascity-rig-dashboard "hello-world")))
  (mx-view "mail" #'gascity-mail-inbox)
  (mx-view "convoys" #'gascity-convoy-list)
  (mx-view "orders" #'gascity-order-list)
  (mx-view "dolt" #'gascity-dolt-list)
  (mx-view "sessions" #'gascity-session-list)
  ;; contention: open everything again at once, refresh all
  (setq mx-phase "contention" mx-phase-maxgc 0)
  (let ((t0 (float-time)))
    (dolist (b (buffer-list))
      (when (string-prefix-p "*gascity" (buffer-name b))
        (with-current-buffer b
          (let ((g (keymap-lookup (current-local-map) "g")))
            (when (commandp g) (ignore-errors (call-interactively g)))))))
    (mx-log "contention refresh-all dispatched in %.3fs" (- (float-time) t0))
    (mx-pump 60 (lambda () (let ((st (gascity-store-host-status mx-dir)))
                             (and (> (- (float-time) t0) 2) (= 0 (plist-get st :reads)) (= 0 (plist-get st :queued))))))
    (mx-log "contention settled in %.1fs maxgc %d" (- (float-time) t0) mx-phase-maxgc))
  (setq mx-phase "live")
  (mx-pump 5 (lambda () nil))
  (let ((seq0 (plist-get (gascity-live-status mx-dir) :seq)) (t0 (float-time)))
    (mx-log "live status %S" (gascity-live-status mx-dir))
    (mx-pump 75 (lambda () (let ((s (plist-get (gascity-live-status mx-dir) :seq)))
                             (and s seq0 (> s seq0)))))
    (mx-log "live seq %S -> %S after %.0fs; status %S" seq0
            (plist-get (gascity-live-status mx-dir) :seq) (- (float-time) t0)
            (gascity-live-status mx-dir)))
  (mx-log "host status %S" (gascity-store-host-status mx-dir))
  (mx-log "max concurrent gascity-gc overall: %d" mx-maxgc)
  (mx-log "stalls>200ms: %S" (reverse mx-gaps))
  (when (get-buffer "*gascity-log*")
    (with-current-buffer "*gascity-log*" (mx-log "LOG:\n%s" (buffer-substring-no-properties (max 1 (- (point-max) 3000)) (point-max))))))
