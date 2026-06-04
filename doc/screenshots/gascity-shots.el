;;; gascity-shots.el --- gascity.el screenshot shot list -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;;; Commentary:

;; The gascity-specific half of the documentation screenshot pipeline.
;; It puts gascity.el and its non-ELPA dependency (beads.el) on the load
;; path, configures the reusable engine in `screenshot.el', and defines a
;; shot per porcelain view.  `capture.sh' runs it once per theme.
;;
;; Configuration is read from the environment so one script serves every
;; theme and selection:
;;
;;   GASCITY_REPO        repo root (default: derived from this file)
;;   BEADS_REPO          beads.el checkout (default: ~/workspace/beads.el)
;;   GASCITY_SHOT_THEME  theme symbol, e.g. ef-elea-dark
;;   GASCITY_SHOT_OUTDIR directory for the raw PNGs
;;   GASCITY_SHOT_SUFFIX appended to every shot name, e.g. -dark
;;   GASCITY_SHOT_VIEWS  space-separated view names; empty = all
;;   GASCITY_SHOT_DIR    directory `gc' resolves the city from
;;   GASCITY_SHOT_RIG    rig to feature in the rig dashboard
;;
;; Run from `capture.sh' under a graphical (headless) Emacs; it exits when
;; done.

;;; Code:

(defvar gascity-shots-dir
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory containing this file (doc/screenshots/).")

(defun gascity-shots-getenv (name default)
  "Return environment NAME, or DEFAULT when unset or empty."
  (let ((v (getenv name)))
    (if (and v (not (string-empty-p v))) v default)))

(let* ((repo (gascity-shots-getenv
              "GASCITY_REPO" (expand-file-name "../.." gascity-shots-dir)))
       (beads (gascity-shots-getenv "BEADS_REPO" (expand-file-name "~/workspace/beads.el"))))
  (add-to-list 'load-path (expand-file-name "lisp" repo))
  (add-to-list 'load-path (expand-file-name "lisp" beads))
  (add-to-list 'load-path gascity-shots-dir))

(require 'cl-lib)
(require 'screenshot)
(require 'gascity)

;;; Engine configuration

(defun gascity-shots--progress (fmt &rest args)
  "Append a progress line to GASCITY_SHOT_OUTDIR/capture.log and stderr."
  (let* ((dir (gascity-shots-getenv "GASCITY_SHOT_OUTDIR" temporary-file-directory))
         (line (concat (format-time-string "%T.%3N ") (apply #'format fmt args) "\n")))
    (ignore-errors
      (let ((coding-system-for-write 'utf-8))
        (write-region line nil (expand-file-name "capture.log" dir) t 'silent)))
    (princ line #'external-debugging-output)))

(defvar gascity-shots-rig (gascity-shots-getenv "GASCITY_SHOT_RIG" "gascity.el")
  "Rig name featured by the rig-dashboard shot.")

(setq screenshot-output-dir
      (gascity-shots-getenv "GASCITY_SHOT_OUTDIR" temporary-file-directory)
      screenshot-theme
      (intern (gascity-shots-getenv "GASCITY_SHOT_THEME" "ef-elea-dark"))
      screenshot-theme-library "ef-themes"
      screenshot-async-process-regexp "gascity-gc"
      screenshot-log-function #'gascity-shots--progress)

;;; View thunks
;;
;; Each thunk opens a porcelain view and returns the buffer to capture.
;; The vui dashboards end in `pop-to-buffer', so the selected window shows
;; the view afterwards; the tabulated lists name their own buffers.

(defun gascity-shots--session-detail-buffer ()
  "Open a session/polecat detail view for a persistent agent.
Drives the real path: list sessions, move point onto a good row, and
invoke the at-point detail command.  Falls back to the first row."
  (gascity-session-list)
  (screenshot-settle 8)
  (with-current-buffer "*gascity-sessions*"
    (let ((pos (cl-some (lambda (pat)
                          (save-excursion
                            (goto-char (point-min))
                            (re-search-forward pat nil t)))
                        '("refinery" "witness" "furiosa"))))
      (goto-char (or pos (progn (goto-char (point-min))
                                (forward-line 1) (point))))
      (beginning-of-line))
    (gascity-polecat-detail-at-point))
  (window-buffer (selected-window)))

(defun gascity-shots--dispatch-frame ()
  "Show the `gascity' dispatcher transient over the status dashboard."
  (gascity-status)
  (screenshot-settle 12)
  (switch-to-buffer "*gascity-status*")
  (delete-other-windows)
  (set-frame-size (selected-frame) 128 34)
  (redisplay t)
  (transient-setup 'gascity)
  (redisplay t)
  nil)

(defun gascity-shots-all ()
  "Return the full alist of shots: (NAME THUNK . PROPS)."
  (list
   ;; vui dashboards — auto-fit height.
   (list "status"
         (lambda () (gascity-status) "*gascity-status*")
         :settle 15)
   (list "rig-dashboard"
         (lambda () (gascity-rig-dashboard gascity-shots-rig)
           (gascity-rig-dashboard--buffer-name gascity-shots-rig))
         :settle 15)
   (list "session-detail" #'gascity-shots--session-detail-buffer :settle 15)
   ;; tabulated lists — extra row pad so short lists stay on one page.
   (list "rig-list"
         (lambda () (gascity-rig-list) "*gascity-rigs*")
         :settle 8 :row-pad 4)
   (list "session-list"
         (lambda () (gascity-session-list) "*gascity-sessions*")
         :settle 8 :row-pad 4)
   (list "convoy-list"
         (lambda () (gascity-convoy-list) "*gascity-convoys*")
         :settle 8 :row-pad 4)
   (list "mail-inbox"
         (lambda () (gascity-mail-inbox) "*gascity-mail*")
         :settle 8 :row-pad 4)
   ;; 88 orders: keep a bounded page so the [page/total] indicator shows.
   (list "order-list"
         (lambda () (gascity-order-list) "*gascity-orders*")
         :settle 8 :fixed-rows 28)
   (list "dolt-list"
         (lambda () (gascity-dolt-list) "*gascity-dolt*")
         :settle 8 :row-pad 4)
   ;; overlay UI — capture the whole frame.
   (list "dispatch" #'gascity-shots--dispatch-frame :whole-frame t)))

(defun gascity-shots-selected ()
  "Return the shots requested by GASCITY_SHOT_VIEWS (or all), suffixed."
  (let* ((suffix (gascity-shots-getenv "GASCITY_SHOT_SUFFIX" ""))
         (want (split-string (gascity-shots-getenv "GASCITY_SHOT_VIEWS" "") nil t))
         (all (gascity-shots-all))
         (chosen (if want
                     (cl-remove-if-not (lambda (s) (member (nth 0 s) want)) all)
                   all)))
    (mapcar (lambda (s)
              (cons (concat (nth 0 s) suffix) (cdr s)))
            chosen)))

;;; Entry point

(defun gascity-shots-run ()
  "Capture the selected shots, then exit."
  ;; Watchdog: the outer `timeout' is the hard backstop, but kill ourselves
  ;; first if a view wedges, so the wrapper sees a clean exit.
  (run-with-timer 90 nil (lambda ()
                           (gascity-shots--progress "WATCHDOG-KILL")
                           (kill-emacs 3)))
  (condition-case err
      (progn
        (screenshot-init)
        (set-frame-size (selected-frame) 200 58)
        (setq default-directory
              (file-name-as-directory
               (gascity-shots-getenv "GASCITY_SHOT_DIR" "/home/roman/bright-lights")))
        (gascity-shots--progress "theme=%s outdir=%s rig=%s dir=%s"
                                 screenshot-theme screenshot-output-dir
                                 gascity-shots-rig default-directory)
        (screenshot-run (gascity-shots-selected))
        (gascity-shots--progress "DONE")
        (kill-emacs 0))
    (error (gascity-shots--progress "FATAL: %S" err)
           (kill-emacs 1))))

(gascity-shots-run)

;;; gascity-shots.el ends here
