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

(defun gascity-shots--selected-buffer ()
  "Return the buffer the selected window shows (views pop to theirs)."
  (window-buffer (selected-window)))

(defun gascity-shots--goto (buffer regexps &optional prop)
  "In BUFFER, move point to the first line matching one of REGEXPS.
With PROP, only a line carrying text property PROP counts.  Falls back
to the first line that carries PROP (or the second line)."
  (with-current-buffer buffer
    (goto-char (point-min))
    (let ((pos (cl-some (lambda (re)
                          (save-excursion
                            (goto-char (point-min))
                            (let (found)
                              (while (and (not found) (re-search-forward re nil t))
                                (when (or (null prop)
                                          (get-text-property (line-beginning-position) prop)
                                          (get-text-property (point) prop))
                                  (setq found (line-beginning-position))))
                              found)))
                        regexps)))
      (goto-char (or pos
                     (and prop (let ((p (text-property-not-all
                                         (point-min) (point-max) prop nil)))
                                 (and p (save-excursion (goto-char p)
                                                        (line-beginning-position)))))
                     (progn (forward-line 1) (point))))
      (beginning-of-line)
      (set-window-point (get-buffer-window buffer) (point)))))

(defun gascity-shots--cockpit-buffer ()
  "Open the city cockpit and return its (city-keyed) buffer."
  (gascity-dashboard)
  (gascity-shots--selected-buffer))

(defun gascity-shots--dispatch-frame ()
  "Show the `?' dispatch transient over the city cockpit."
  (let ((buf (gascity-shots--await (gascity-shots--cockpit-buffer))))
    (switch-to-buffer buf))
  (delete-other-windows)
  (set-frame-size (selected-frame) 128 40)
  (redisplay t)
  (transient-setup 'gascity-dispatch)
  (redisplay t)
  nil)

(defun gascity-shots--lighter-frame ()
  "Show the mode-line lighter under a short cockpit window."
  (gascity-mode-line-mode 1)
  (let ((buf (gascity-shots--await (gascity-shots--cockpit-buffer))))
    (switch-to-buffer buf)
    (delete-other-windows)
    (gascity-mode-line-update)
    (message nil)
    (goto-char (point-min))
    (set-frame-size (selected-frame) 100 8)
    (redisplay t))
  nil)

(defun gascity-shots--agent-detail-buffer ()
  "Open the detail of a running agent through the Agents table (`i')."
  (gascity-agents)
  (let ((table (gascity-shots--await (gascity-shots--selected-buffer))))
    (gascity-shots--goto table '("● .*active" "mayor" "●") 'tabulated-list-id)
    (with-current-buffer table (gascity-polecat-detail-at-point)))
  (gascity-shots--selected-buffer))

(defun gascity-shots--agents-tree-buffer ()
  "Open the Agents tree (`T')."
  (gascity-agents-tree)
  (gascity-shots--selected-buffer))

(defun gascity-shots--run-detail-buffer ()
  "Open a run's detail through the Runs view's history (`H', `RET')."
  (gascity-runs)
  (let ((runs (gascity-shots--await (gascity-shots--selected-buffer))))
    (with-current-buffer runs
      (unless (text-property-not-all (point-min) (point-max) 'gascity-run-rig nil)
        (gascity-runs-history)
        (gascity-shots--await runs)))
    (gascity-shots--goto runs '("^  [⬣✕◆] ") 'gascity-run-rig)
    (with-current-buffer runs (gascity-runs-activate)))
  (gascity-shots--selected-buffer))

(defun gascity-shots--mail-thread-buffer ()
  "Open a message from the inbox the cheap way (`RET': cached, no gc call,
stays unread)."
  (gascity-mail)
  (let* ((inbox (gascity-shots--await (gascity-shots--selected-buffer))))
    (gascity-shots--goto inbox '(".") 'tabulated-list-id)
    (with-current-buffer inbox
      (let ((message (tabulated-list-get-id)))
        (gascity-mail-thread-show message inbox t))))
  (gascity-shots--selected-buffer))

(defun gascity-shots--loading-p (buffer)
  "Return non-nil while BUFFER still shows data being loaded.
A read the buffer subscribes to is in flight in the store, or a
section still shows its `…' loading marker (two spaces then `…' at the
end of a line; a truncated cell's `…' follows a letter), or a list's
mode line says loading."
  (and (buffer-live-p buffer)
       (or (gascity-store-buffer-pending-p buffer)
           (with-current-buffer buffer
             (or (save-excursion
                   (goto-char (point-min))
                   (re-search-forward "\\(?:^\\|  \\)…$" nil t))
                 (and (stringp mode-name)
                      (string-match-p "loading" mode-name)))))))

(defun gascity-shots--await (buffer &optional seconds)
  "Wait (at most SECONDS, default 40) until BUFFER has finished loading.
Then clear the echo area, so the export shows no stray message."
  (let ((deadline (+ (float-time) (or seconds 40))))
    (while (and (gascity-shots--loading-p buffer) (< (float-time) deadline))
      (accept-process-output nil 0.1))
    (when (gascity-shots--loading-p buffer)
      (gascity-shots--progress "still loading after %ss: %s"
                               (or seconds 40) (buffer-name buffer)))
    ;; One more beat for the last render to land.
    (accept-process-output nil 0.3)
    (message nil)
    buffer))

(defun gascity-shots--ready (thunk)
  "Wrap view THUNK: call it, then wait for its buffer to finish loading."
  (lambda () (gascity-shots--await (funcall thunk))))

(defun gascity-shots--view (command)
  "Return a thunk calling COMMAND and returning the buffer it shows."
  (lambda () (call-interactively command) (gascity-shots--selected-buffer)))

(defun gascity-shots-all ()
  "Return the full alist of shots: (NAME THUNK . PROPS)."
  (list
   ;; vui views — auto-fit height.
   (list "cockpit" #'gascity-shots--cockpit-buffer :settle 15)
   (list "agents-tree" #'gascity-shots--agents-tree-buffer :settle 12)
   (list "agent-detail" #'gascity-shots--agent-detail-buffer :settle 15)
   (list "runs" (gascity-shots--view #'gascity-runs) :settle 15)
   (list "run-detail" #'gascity-shots--run-detail-buffer :settle 15)
   (list "health" (gascity-shots--view #'gascity-health) :settle 15)
   (list "rig-dashboard"
         (lambda () (gascity-rig-dashboard gascity-shots-rig)
           (gascity-shots--selected-buffer))
         :settle 15)
   (list "mail-thread" #'gascity-shots--mail-thread-buffer :settle 6)
   ;; tabulated lists — extra row pad so short lists stay on one page.
   (list "agents" (gascity-shots--view #'gascity-agents) :settle 12 :row-pad 2)
   (list "events" (gascity-shots--view #'gascity-events) :settle 12 :fixed-rows 30)
   (list "mail-inbox" (gascity-shots--view #'gascity-mail) :settle 8 :fixed-rows 14)
   (list "cities" (gascity-shots--view #'gascity-cities) :settle 15 :row-pad 2
         :col-pad 6)
   (list "rig-list" (gascity-shots--view #'gascity-rig-list) :settle 8 :row-pad 4)
   (list "session-list" (gascity-shots--view #'gascity-session-list)
         :settle 8 :row-pad 4)
   (list "convoy-list" (gascity-shots--view #'gascity-convoy-list)
         :settle 8 :row-pad 4)
   ;; many orders: keep a bounded page so the [page/total] indicator shows.
   (list "order-list" (gascity-shots--view #'gascity-order-list)
         :settle 8 :fixed-rows 28)
   (list "dolt-list" (gascity-shots--view #'gascity-dolt-list) :settle 8 :row-pad 4)
   ;; overlay / frame UI — capture the whole frame.
   (list "dispatch" #'gascity-shots--dispatch-frame :whole-frame t)
   (list "lighter" #'gascity-shots--lighter-frame :whole-frame t)))

(defun gascity-shots--wrapped ()
  "Return `gascity-shots-all' with every buffer thunk waiting for its data."
  (mapcar (lambda (shot)
            (if (plist-get (cddr shot) :whole-frame)
                shot
              (cons (car shot) (cons (gascity-shots--ready (cadr shot)) (cddr shot)))))
          (gascity-shots-all)))

(defun gascity-shots-selected ()
  "Return the shots requested by GASCITY_SHOT_VIEWS (or all), suffixed."
  (let* ((suffix (gascity-shots-getenv "GASCITY_SHOT_SUFFIX" ""))
         (want (split-string (gascity-shots-getenv "GASCITY_SHOT_VIEWS" "") nil t))
         (all (gascity-shots--wrapped))
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
  (run-with-timer (string-to-number
                   (gascity-shots-getenv "GASCITY_SHOT_WATCHDOG" "400"))
                  nil (lambda ()
                           (gascity-shots--progress "WATCHDOG-KILL")
                           (kill-emacs 3)))
  (condition-case err
      (progn
        (screenshot-init)
        (set-frame-size (selected-frame) 200 58)
        (setq default-directory
              (file-name-as-directory
               (gascity-shots-getenv "GASCITY_SHOT_DIR" "/home/roman/emacs-city")))
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
