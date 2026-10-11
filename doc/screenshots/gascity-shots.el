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

;; gc reads its user-level state (the machine-wide city registry) from
;; GC_HOME, defaulting to ~/.gc.  The fixture provides a throwaway GC_HOME
;; registering only the fixture city, so the Cities view lists the fixture
;; and never the developer's live cities.  capture.sh exports it; the
;; fallback keeps a standalone `emacs -l gascity-shots.el' run working.
(let ((gc-home (getenv "GASCITY_SHOT_GC_HOME")))
  (when (and gc-home (not (string-empty-p gc-home)))
    (setenv "GC_HOME" gc-home)))

(let* ((repo (gascity-shots-getenv
              "GASCITY_REPO" (expand-file-name "../.." gascity-shots-dir)))
       (beads (gascity-shots-getenv "BEADS_REPO" (expand-file-name "~/workspace/beads.el"))))
  (add-to-list 'load-path (expand-file-name "lisp" repo))
  (add-to-list 'load-path (expand-file-name "lisp" beads))
  (add-to-list 'load-path gascity-shots-dir)
  ;; vui is not on ELPA; beads.el vendors it under its Eldev package dir.
  (dolist (vui (file-expand-wildcards
                (expand-file-name ".eldev/*/packages/vui-*" beads)))
    (add-to-list 'load-path vui)))

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

;;; Deterministic role ids and terminal normalization (defense in depth)
;;
;; The fixture pins bead ids to `demo-<role>' (see fixtures/README.md), and
;; pins timestamps/ports, but a view can still render a run-generated id,
;; an ephemeral port, or a clock value.  The engine is reused verbatim, so
;; the normalization is installed as advice from this call site rather
;; than a change to screenshot.el.

(defvar gascity-shots-role-prefix "demo"
  "Fixture id prefix.  Ids outside it are left alone by normalization.")

(defvar gascity-shots-normalization-rules
  `((,(concat "\\b" (regexp-quote gascity-shots-role-prefix) "-[0-9a-f]\\{6,\\}\\b")
     . ,(concat gascity-shots-role-prefix "-role"))
    ("/tmp/gascity-fixture\\.[A-Za-z0-9]\\{6,\\}" . "/tmp/gascity-fixture")
    ("[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9:.]\\{8,\\}Z?"
     . "1970-01-01T00:00:00Z"))
  "Post-render text rules mapping generated values to stable tokens.
Each entry is (REGEXP . REPLACEMENT); REPLACEMENT is a literal string.
The default covers run-generated `<prefix>-<hash>' bead ids, the throwaway
fixture path, and ISO-8601 timestamps.  Any drift the fixture genuinely
cannot pin must be enumerated in README.md and asserted by `--verify', not
silently normalized here.")

(defun gascity-shots--normalize-buffer (buffer)
  "Apply `gascity-shots-normalization-rules' to BUFFER's text.
Text properties are preserved and the buffer is left unmodified."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (inhibit-modification-hooks t)
            (was-modified (buffer-modified-p)))
        (save-excursion
          (dolist (rule gascity-shots-normalization-rules)
            (goto-char (point-min))
            (while (re-search-forward (car rule) nil t)
              (replace-match (cdr rule) t t))))
        (set-buffer-modified-p was-modified)))))

(defun gascity-shots--normalize-frame (frame)
  "Normalize every buffer displayed in a window of FRAME."
  (dolist (window (window-list frame nil))
    (gascity-shots--normalize-buffer (window-buffer window))))

;; The engine is copied verbatim, so the normalization is a post-render
;; hook installed from this call site rather than a change to the engine.
(advice-add 'screenshot-export :before
            (lambda (buffer _name &optional _fixed-rows)
              (gascity-shots--normalize-buffer (get-buffer buffer))))
(advice-add 'screenshot-export-frame :before
            (lambda (_name)
              (gascity-shots--normalize-frame (selected-frame))))

;;; View thunks
;;
;; Each thunk opens a porcelain view and returns the buffer to capture.
;; The vui dashboards end in `pop-to-buffer', so the selected window shows
;; the view afterwards; the tabulated lists name their own buffers.

(defun gascity-shots--selected-buffer ()
  "Return the buffer the selected window shows (views pop to theirs)."
  (window-buffer (selected-window)))

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

(defun gascity-shots--agents-tree-buffer ()
  "Open the Agents tree (`T')."
  (gascity-agents-tree)
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

(defun gascity-shots--bookmarks-buffer ()
  "Open the Emacs Bookmark List showing fixture-owned gascity bookmarks.
`emacs -Q' would otherwise list the developer's own bookmarks, so the
list is built in-session from the fixture views: the cockpit and the
fixture rig dashboard are bookmarked through the normal
`bookmark-make-record-function', then listed.  `bookmark-default-file' is
pointed at a throwaway path, so nothing is read from or written to the
user's bookmark file."
  (require 'bookmark)
  (setq bookmark-default-file
        (gascity-shots-getenv "GASCITY_SHOT_BOOKMARKS"
                              (expand-file-name "gascity-shots-bookmarks.el"
                                                temporary-file-directory))
        bookmark-alist nil)
  (with-current-buffer (gascity-shots--await (gascity-shots--cockpit-buffer))
    (bookmark-set "gascity: cockpit (fixture)"))
  (with-current-buffer
      (gascity-shots--await
       (funcall (lambda () (gascity-rig-dashboard gascity-shots-rig)
                  (gascity-shots--selected-buffer))))
    (bookmark-set (format "gascity-rig: %s (fixture)" gascity-shots-rig)))
  (bookmark-bmenu-list)
  (or (get-buffer "*Bookmark List*") (gascity-shots--selected-buffer)))

(defun gascity-shots--remote-cities-buffer ()
  "Open the Cities list, which includes the remote hosts (`j c').
The fixture city plus one fixture remote context is what the manual's
Remote Cities chapter shows; the command is the same list as `cities'."
  (gascity-cities)
  (gascity-shots--selected-buffer))

(defun gascity-shots--terminal-attach-buffer ()
  "Open a terminal attached to the fixture's fixed tmux session.
The session name comes from GASCITY_SHOT_TERMINAL_SESSION (default
`demo-agent'); when tmux is present and the session is absent it is created
first, so the attach has something to render.  The attach runs a pre-step
asynchronously (D9), so this waits for the live terminal buffer and
returns it, rather than the buffer that happened to be selected before.
Environment-dependent (a host without tmux logs the shot as skipped rather
than failing the run)."
  (let* ((session (gascity-shots-getenv "GASCITY_SHOT_TERMINAL_SESSION" "demo-agent"))
         (tmux (executable-find "tmux")))
    (when tmux
      (unless (eq 0 (call-process tmux nil nil nil "has-session" "-t" session))
        (ignore-errors
          (call-process tmux nil nil nil "new-session" "-d" "-s" session))))
    (gascity-terminal-attach-tmux session)
    (let ((deadline (+ (float-time) 20)) found)
      (while (and (not found) (< (float-time) deadline))
        (accept-process-output nil 0.2)
        (setq found (cl-find-if
                     (lambda (b)
                       (string-match-p (format "\\*gc-agent-.*%s\\*"
                                               (regexp-quote session))
                                       (buffer-name b)))
                     (buffer-list))))
      (if found
          (progn (switch-to-buffer found) found)
        (gascity-shots--selected-buffer)))))

(defun gascity-shots--sling-frame (&optional scope)
  "Show the sling dispatch transient over the fixture cockpit.
SCOPE is a plist merged over the base scope (`:city' plus nils); nil is
the cold menu.  Returns nil so the whole frame is captured
\(:whole-frame)."
  (switch-to-buffer (gascity-shots--await (gascity-shots--cockpit-buffer)))
  (delete-other-windows)
  (set-frame-size (selected-frame) 150 46)
  (redisplay t)
  (transient-setup 'gascity-sling-dispatch nil nil
                   :scope (append scope
                                  (list :city default-directory
                                        :formula nil :target nil :work nil
                                        :work-title nil))
                   :value nil)
  (redisplay t)
  nil)

(defun gascity-shots--sling-plain-frame ()
  "The sling menu pre-seeded with fixture work: the plain shape."
  (gascity-shots--sling-frame
   (list :work "demo-task-manual"
         :work-title "Write the task-organized manual")))

(defun gascity-shots--sling-cold-frame ()
  "The sling menu with nothing pre-seeded."
  (gascity-shots--sling-frame))

(defun gascity-shots--sling-formula-frame ()
  "The formula shape: a formula picked with no work attached."
  (gascity-shots--sling-frame (list :formula "mol-do-work")))

(defun gascity-shots--sling-on-frame ()
  "The targeted shape: a formula picked with fixture work in scope."
  (gascity-shots--sling-frame
   (list :work "demo-task-manual"
         :work-title "Write the task-organized manual"
         :formula "mol-do-work")))

(defun gascity-shots--sling-preview-buffer ()
  "The full preview buffer (`P') for a fixture dispatch."
  (switch-to-buffer (gascity-shots--await (gascity-shots--cockpit-buffer)))
  (gascity-sling--full-preview
   (list :city default-directory
         :work "demo-task-manual"
         :work-title "Write the task-organized manual"
         :formula "mol-do-work"
         :target "demo-rig/gc.implementation-worker")
   nil)
  (gascity-shots--await (gascity-shots--selected-buffer)))

(defun gascity-shots-all ()
  "Return the full alist of shots: (NAME THUNK . PROPS)."
  (list
   ;; vui views — auto-fit height.
   (list "cockpit" #'gascity-shots--cockpit-buffer :settle 15)
   (list "agents-tree" #'gascity-shots--agents-tree-buffer :settle 12)
   (list "runs" (gascity-shots--view #'gascity-runs) :settle 15)
   (list "health" (gascity-shots--view #'gascity-health) :settle 15)
   (list "costs" (gascity-shots--view #'gascity-costs) :settle 12)
   (list "rig-dashboard"
         (lambda () (gascity-rig-dashboard gascity-shots-rig)
           (gascity-shots--selected-buffer))
         :settle 15)
   ;; tabulated lists — extra row pad so short lists stay on one page.
   (list "agents" (gascity-shots--view #'gascity-agents) :settle 12 :row-pad 2)
   (list "events" (gascity-shots--view #'gascity-events) :settle 12 :fixed-rows 30)
   (list "mail-inbox" (gascity-shots--view #'gascity-mail) :settle 8 :fixed-rows 14)
   (list "bookmarks" #'gascity-shots--bookmarks-buffer :settle 6 :fixed-rows 20)
   (list "cities" (gascity-shots--view #'gascity-cities) :settle 15 :row-pad 2
         :col-pad 6)
   (list "remote-cities" #'gascity-shots--remote-cities-buffer :settle 15
         :row-pad 2 :col-pad 6)
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
   (list "sling-plain" #'gascity-shots--sling-plain-frame :whole-frame t)
   (list "sling-cold" #'gascity-shots--sling-cold-frame :whole-frame t)
   (list "sling-formula" #'gascity-shots--sling-formula-frame :whole-frame t)
   (list "sling-on" #'gascity-shots--sling-on-frame :whole-frame t)
   (list "sling-preview" #'gascity-shots--sling-preview-buffer :settle 15)
   (list "terminal-attach" #'gascity-shots--terminal-attach-buffer :settle 12)
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
               (gascity-shots-getenv "GASCITY_SHOT_DIR" (expand-file-name "~/emacs-city"))))
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
