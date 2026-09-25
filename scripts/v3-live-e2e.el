;;; v3-live-e2e.el --- Live check of the gc event stream (dashboard-v3 P3)  -*- lexical-binding: t; -*-
;; Run: E2E_DIR=/tmp timeout 400 emacs -Q --batch -L lisp -L ~/workspace/beads.el/lisp \
;;        -L .eldev/31.1/packages/vui-1.4.0 -L .eldev/31.1/packages/sesman-0.3.2 -l scripts/v3-live-e2e.el
;; Afterwards: ssh -o ControlPath=$XDG_RUNTIME_DIR/v3live-%C -O exit localhost
(require 'gascity)
(setq gascity-live-in-batch t gascity-live-debounce 0.5)
(defvar e2e-cm (expand-file-name "v3live-%C" (getenv "XDG_RUNTIME_DIR")))
;; Private ssh master for the remote stream, so `ssh -O exit' only
;; affects this test (the user's shared master stays up).
(advice-add 'gascity-live-command :filter-return
            (lambda (argv)
              (if (equal (car argv) "ssh")
                  (append (list "ssh" "-o" "ControlMaster=auto"
                                "-o" (concat "ControlPath=" e2e-cm)
                                "-o" "ControlPersist=60")
                          (cdr argv))
                argv)))
(defun e2e-wait (pred secs)
  (let ((deadline (+ (float-time) secs)))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.1))
    (funcall pred)))
(defun e2e-log (fmt &rest args) (princ (apply #'format (concat fmt "\n") args)))
(defun e2e-contiguous (seqs)
  (let ((s (sort (delete-dups (copy-sequence seqs)) #'<)))
    (and s (= (length s) (1+ (- (car (last s)) (car s)))))))
(defun e2e-run (root label)
  (let* ((buf (generate-new-buffer (format "e2e-%s" label)))
         (seqs nil) (invals 0) stream (ok t))
    (with-current-buffer buf
      (setq default-directory root)
      (setq stream (gascity-live-attach nil :refresh (lambda () (cl-incf invals))))
      (gascity-live-subscribe (lambda (e) (push (alist-get 'seq e) seqs))))
    (e2e-log "[%s] attached; header=%s" label (gascity-live-header-string root))
    ;; 1. an event arrives
    (unless (e2e-wait (lambda () seqs) 60) (setq ok nil))
    (e2e-log "[%s] first event: %s  (seq %S)" label (if seqs "yes" "NO") (car seqs))
    (e2e-wait (lambda () (> invals 0)) 10)
    (e2e-log "[%s] invalidations: %d" label invals)
    ;; 2. kill the gc stream → resume with no missed seq
    (let ((before (length seqs)) (last-seq (car seqs)))
      (call-process "pkill" nil nil nil "-f" "^(/[^ ]*/)?g[c] events --follow.*--city /home/roman/bright-lights")
      (e2e-wait (lambda () (not (eq (gascity-live--stream-state stream) 'live))) 10)
      (e2e-log "[%s] after pkill: %s (%s)" label (gascity-live--stream-state stream)
               (gascity-live--stream-reason stream))
      (unless (e2e-wait (lambda () (and (eq (gascity-live--stream-state stream) 'live)
                                        (> (length seqs) (+ before 2))))
                        60)
        (setq ok nil))
      (e2e-log "[%s] resumed: state=%s events %d→%d, last-before=%S contiguous=%S"
               label (gascity-live--stream-state stream) before (length seqs) last-seq
               (e2e-contiguous seqs))
      (unless (e2e-contiguous seqs) (setq ok nil)))
    ;; 3. remote only: kill the ssh master → offline → recovery
    (when (file-remote-p root)
      (let ((before (length seqs)))
        (call-process "ssh" nil nil nil "-o" (concat "ControlPath=" e2e-cm)
                      "-O" "exit" "localhost")
        (e2e-wait (lambda () (memq (gascity-live--stream-state stream) '(offline reconnecting))) 15)
        (e2e-log "[%s] after ssh -O exit: %s  header=%s reason=%s" label
                 (gascity-live--stream-state stream)
                 (substring-no-properties (or (gascity-live-header-string root) ""))
                 (gascity-live--stream-reason stream))
        (unless (eq (gascity-live--stream-state stream) 'offline) (setq ok nil))
        (unless (e2e-wait (lambda () (and (eq (gascity-live--stream-state stream) 'live)
                                          (> (length seqs) (+ before 2))))
                          60)
          (setq ok nil))
        (e2e-log "[%s] recovered: %s events %d→%d contiguous=%S" label
                 (gascity-live--stream-state stream) before (length seqs) (e2e-contiguous seqs))
        (unless (e2e-contiguous seqs) (setq ok nil))))
    ;; 4. kill the view → no processes left
    (kill-buffer buf)
    (e2e-wait (lambda () (null (seq-filter (lambda (p) (and (process-live-p p) (string-match-p "gascity-live" (process-name p)))) (process-list)))) 5)
    (let ((left (seq-filter #'process-live-p (process-list))))
      (e2e-log "[%s] processes left in Emacs: %S; streams: %d" label
               (mapcar #'process-name left) (hash-table-count gascity-live--streams))
      (when (seq-some (lambda (p) (string-match-p "gascity-live" (process-name p))) left)
        (setq ok nil)))
    (e2e-log "[%s] RESULT: %s" label (if ok "PASS" "FAIL"))
    ok))
(let ((local (e2e-run "/home/roman/bright-lights/" "local"))
      (remote (e2e-run "/ssh:localhost:/home/roman/bright-lights/" "remote")))
  (kill-emacs (if (and local remote) 0 1)))
