;;; gascity-terminal.el --- Terminal backend + tmux attach -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Interactive-command support for gascity, built on beads.el's terminal
;; module rather than a private reimplementation.  `beads-terminal-spawn'
;; provides the vterm / eat / term backends; gascity selects one via
;; `gascity-terminal-backend' and hands it an argv to run.
;;
;; The one action the read-only porcelain needs is attaching to an
;; agent's tmux session: `gascity-terminal-attach-tmux' guards that the
;; session exists, then opens `env -u TMUX tmux attach-session -t
;; SESSION' in a terminal buffer.  (`env -u TMUX' lets the attach nest
;; when Emacs itself runs inside tmux.)  Session and socket names are
;; shell-quoted before interpolation.
;;
;; Attaching is idempotent: when the agent's terminal buffer is already
;; open with a live process, `gascity-terminal-run' raises that window
;; instead of starting a second backend process in it (which would
;; otherwise error, e.g. ghostel's "already has a running ghostel
;; process").
;;
;; One status line, not two: a tmux client inside an Emacs buffer shows
;; both tmux's own status bar and the Emacs mode line.  On attach,
;; `gascity-terminal--status-install' turns the session's tmux status bar
;; off (scoped to that session) and mirrors its information — the friendly
;; name from `status-left' and the window list — in a buffer-local mode
;; line segment, refreshed on a timer.  Killing the buffer cancels the
;; timer and removes the tmux override (`set-option -u'), so an external
;; `tmux attach' sees its bar again.  Honour `gascity-terminal-mode-line-status'
;; to disable the whole behaviour.

;;; Code:

(require 'beads-terminal)
(require 'gascity-custom)

(declare-function gascity--log "gascity")

;;; Backend selection

(defun gascity-terminal--backend-class ()
  "Return the `beads-terminal' class for `gascity-terminal-backend'.
Maps the user's backend choice to a concrete beads terminal class, or
`beads-terminal-auto' (which probes vterm > eat > term) when unset."
  (pcase gascity-terminal-backend
    ('vterm 'beads-terminal-vterm)
    ('eat   'beads-terminal-eat)
    ('term  'beads-terminal-term)
    (_      'beads-terminal-auto)))

;;; Running a command in a terminal

(defun gascity-terminal--working-dir (dir)
  "Return a usable working directory from DIR, falling back to \"~/\"."
  (let ((d (or dir default-directory)))
    (if (and d (file-directory-p d)) (file-name-as-directory d) "~/")))

(defun gascity-terminal--live-buffer (buffer-name)
  "Return the buffer named BUFFER-NAME when it hosts a live process, else nil.
A terminal buffer whose process has already exited is treated as absent,
so the caller spawns a fresh one; only a buffer with a running process is
worth reusing."
  (when-let* ((buf (get-buffer buffer-name))
              (proc (get-buffer-process buf)))
    (and (process-live-p proc) buf)))

(defun gascity-terminal-run (argv buffer-name &optional dir)
  "Display the terminal buffer named BUFFER-NAME, spawning ARGV if needed.
If a buffer named BUFFER-NAME already hosts a live process, reuse it: pop
to it and raise its window without launching a second process.  This is
what keeps `t' on an agent whose terminal is already open from erroring
\(e.g. ghostel's \"already has a running ghostel process\").  The check is
on the Emacs buffer and its process, so it behaves identically across the
vterm / eat / term / ghostel backends.

Otherwise spawn ARGV in a fresh terminal buffer.  ARGV is a (PROGRAM .
ARGS) list run with no intervening shell via beads.el's
`beads-terminal-spawn', using the backend from `gascity-terminal-backend'.
beads sets the working directory from DIR (its WORKING-DIR contract); nil
or a missing DIR falls back to the home directory.  Returns the buffer and
pops to it."
  (let ((existing (gascity-terminal--live-buffer buffer-name)))
    (if existing
        ;; Reuse the live terminal — raise its window, don't re-exec.
        (progn (pop-to-buffer existing) existing)
      ;; No live terminal: spawn a fresh one.
      (let* ((default-dir (gascity-terminal--working-dir dir))
             (terminal (make-instance (gascity-terminal--backend-class)))
             (buf (beads-terminal-spawn terminal buffer-name argv default-dir
                                        '(("CLICOLOR_FORCE" . "1")))))
        (when (and buf (buffer-live-p buf))
          (pop-to-buffer buf))
        buf))))

;;; tmux

(defun gascity-terminal--socket-args (socket)
  "Return a `(\"-L\" SOCKET)' list for a real SOCKET, else nil.
nil, the empty string, and the literal \"default\" all mean \"use the
default tmux server\" — no -L flag."
  (when (and socket (stringp socket)
             (not (string-empty-p socket))
             (not (string= socket "default")))
    (list "-L" socket)))

(defun gascity-terminal-tmux-session-exists-p (session &optional socket)
  "Return non-nil when tmux SESSION exists (on optional SOCKET)."
  (and session (stringp session) (not (string-empty-p session))
       (eq 0 (apply #'call-process "tmux" nil nil nil
                    (append (gascity-terminal--socket-args socket)
                            (list "has-session" "-t" session))))))

(defun gascity-terminal-pane-cwd (session &optional socket)
  "Return the working directory of tmux SESSION's active pane, or nil.
Runs `tmux [-L SOCKET] display-message -t SESSION -p #{pane_current_path}'
and returns the trimmed path it reports.  Returns nil when SESSION is
empty, tmux is unavailable, the session is gone, or the pane reports no
path; the caller validates that the path exists on disk.  This lets
`gascity-agent-dired' open an agent's live working directory even when its
session bead recorded no `work_dir' (mirroring gastown)."
  (when (and session (stringp session) (not (string-empty-p session)))
    (with-temp-buffer
      (when (eq 0 (apply #'call-process "tmux" nil t nil
                         (append (gascity-terminal--socket-args socket)
                                 (list "display-message" "-t" session
                                       "-p" "#{pane_current_path}"))))
        (let ((path (string-trim (buffer-string))))
          (unless (string-empty-p path) path))))))

;;; tmux status in the mode line

(defvar-local gascity-terminal--status-session nil
  "tmux session name mirrored in this buffer's mode line, or nil.")

(defvar-local gascity-terminal--status-socket nil
  "tmux -L socket for `gascity-terminal--status-session', or nil.")

(defvar-local gascity-terminal--status-string nil
  "Cached mode-line status string for this buffer, or nil.
Recomputed by `gascity-terminal--status-refresh' and read by the
`gascity-terminal--status-segment' mode-line construct.")

(defvar-local gascity-terminal--status-timer nil
  "Repeating timer refreshing this buffer's tmux status, or nil.")

(defconst gascity-terminal--status-mode-line-segment
  '(:eval (gascity-terminal--status-segment))
  "Mode-line construct that renders the buffer's tmux status string.")

(defun gascity-terminal--tmux (socket &rest args)
  "Run \"tmux [-L SOCKET] ARGS\" and return trimmed stdout, or nil.
Returns nil when tmux is unavailable or exits non-zero (e.g. the session
is gone), so callers treat a missing session uniformly."
  (with-temp-buffer
    (when (eq 0 (apply #'call-process "tmux" nil t nil
                       (append (gascity-terminal--socket-args socket) args)))
      (string-trim (buffer-string)))))

(defun gascity-terminal--window-list (session socket)
  "Return tmux SESSION's windows on SOCKET as a list of plists, or nil.
Each plist has `:active' (t for the current window) and `:label'
\(\"index:name\" plus tmux's window-flags, e.g. \"1:claude*\").  Returns
nil when the session is gone or lists no windows; this doubles as the
session-existence probe, since `display-message' exits 0 even for a
missing target."
  (let ((out (gascity-terminal--tmux
              socket "list-windows" "-t" session "-F"
              "#{window_active}\t#{window_index}:#{window_name}#{window_flags}")))
    (when (and out (not (string-empty-p out)))
      (mapcar (lambda (line)
                (let ((parts (split-string line "\t")))
                  (list :active (equal (car parts) "1")
                        :label (string-join (cdr parts) "\t"))))
              (split-string out "\n" t)))))

(defun gascity-terminal--status-string (session socket)
  "Return the mode-line status string for tmux SESSION on SOCKET, or nil.
Mirrors tmux's status bar without its chrome: the friendly name from the
session's `status-left' (falling back to a truncated SESSION) followed by
the window list, the current window emphasised.  Returns nil when the
session no longer exists.  The session's `status-right' is deliberately
omitted: it is the agent's own `#()' status script, which does not run
while the bar is off, and its residual clock duplicates `display-time'."
  (let ((windows (gascity-terminal--window-list session socket)))
    (when windows
      (let* ((left (gascity-terminal--tmux
                    socket "display-message" "-p" "-t" session
                    "#{E:status-left}"))
             (name (if (and left (not (string-empty-p left)))
                       left
                     (truncate-string-to-width session 24 nil nil "…"))))
        (concat
         (propertize name 'face 'gascity-city)
         "  "
         (mapconcat
          (lambda (w)
            (propertize (plist-get w :label)
                        'face (if (plist-get w :active)
                                  'gascity-header 'default)))
          windows " "))))))

(defun gascity-terminal--status-segment ()
  "Mode-line segment for this buffer's cached tmux status, or \"\".
Read on every redisplay; the value is refreshed out-of-band by
`gascity-terminal--status-refresh', not recomputed here."
  (if (and gascity-terminal--status-string
           (not (string-empty-p gascity-terminal--status-string)))
      (concat " " gascity-terminal--status-string)
    ""))

(defun gascity-terminal--status-refresh ()
  "Recompute this buffer's cached tmux status and update the mode line.
When the session has gone, clear the cache and stop the refresh timer —
there is nothing left to poll."
  (let ((s (and gascity-terminal--status-session
                (gascity-terminal--status-string
                 gascity-terminal--status-session
                 gascity-terminal--status-socket))))
    (setq gascity-terminal--status-string s)
    (unless s
      (when (timerp gascity-terminal--status-timer)
        (cancel-timer gascity-terminal--status-timer))
      (setq gascity-terminal--status-timer nil))
    (force-mode-line-update)))

(defun gascity-terminal--status-tick (buffer)
  "Timer callback: refresh BUFFER's tmux status while it is live."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (gascity-terminal--status-refresh))))

(defun gascity-terminal--status-teardown ()
  "Tear down the tmux status mirror for the current buffer.
Cancels the refresh timer and removes the session's tmux `status'
override (`set-option -u') so a later `tmux attach' shows its own status
bar again.  Run from `kill-buffer-hook'."
  (when (timerp gascity-terminal--status-timer)
    (cancel-timer gascity-terminal--status-timer))
  (setq gascity-terminal--status-timer nil)
  (when (and gascity-terminal--status-session
             (stringp gascity-terminal--status-session)
             (not (string-empty-p gascity-terminal--status-session)))
    (ignore-errors
      (gascity-terminal--tmux gascity-terminal--status-socket
                              "set-option" "-t"
                              gascity-terminal--status-session
                              "-u" "status"))))

(defun gascity-terminal--status-install (buffer session socket)
  "Hide tmux SESSION's status bar and mirror it in BUFFER's mode line.
Turns the session's tmux status bar off (scoped to the session via
`set-option -t'), splices a buffer-local mode-line segment showing the
session's friendly name and window list into the mode line before its
trailing fill, starts a refresh timer, and arranges teardown on buffer
kill.  Idempotent: safe to re-run when reattaching to a live terminal."
  (when (and (buffer-live-p buffer)
             session (stringp session) (not (string-empty-p session)))
    (with-current-buffer buffer
      (setq gascity-terminal--status-session session
            gascity-terminal--status-socket socket)
      ;; Scope: turn this session's tmux status bar off.  Reverted on
      ;; teardown via `set-option -u'.  Best-effort (nil on failure).
      (gascity-terminal--tmux socket "set-option" "-t" session "status" "off")
      ;; Splice our segment into the mode line exactly once, just before
      ;; the trailing fill (`mode-line-end-spaces') so it stays visible.
      ;; Appending after the fill (`%-') renders it off-screen; prepend as
      ;; a fallback when that anchor is absent.
      (let ((mlf (if (listp mode-line-format)
                     mode-line-format
                   (list mode-line-format))))
        (unless (member gascity-terminal--status-mode-line-segment mlf)
          (let ((tail (member 'mode-line-end-spaces mlf)))
            (setq-local mode-line-format
                        (if tail
                            (append (butlast mlf (length tail))
                                    (cons gascity-terminal--status-mode-line-segment
                                          tail))
                          (cons gascity-terminal--status-mode-line-segment mlf))))))
      ;; (Re)start the refresh timer; paint once now so the segment is
      ;; populated before the first redisplay.
      (when (timerp gascity-terminal--status-timer)
        (cancel-timer gascity-terminal--status-timer))
      (let ((interval (if (and (numberp gascity-terminal-status-interval)
                               (> gascity-terminal-status-interval 0))
                          gascity-terminal-status-interval
                        5)))
        (setq gascity-terminal--status-timer
              (run-with-timer interval interval
                              #'gascity-terminal--status-tick buffer)))
      (gascity-terminal--status-refresh)
      ;; Tear down when the terminal buffer is killed.
      (add-hook 'kill-buffer-hook #'gascity-terminal--status-teardown nil t))))

(defun gascity-terminal-attach-tmux (session &optional socket dir)
  "Attach to tmux SESSION in a terminal buffer.
SOCKET selects a non-default tmux server when set.  DIR is the working
directory for the spawned terminal.  Signals a `user-error' when SESSION
is empty or does not exist (e.g. the agent has stopped).

When `gascity-terminal-mode-line-status' is non-nil, the session's tmux
status bar is hidden and mirrored in the terminal buffer's mode line (see
`gascity-terminal--status-install')."
  (unless (and session (stringp session) (not (string-empty-p session)))
    (user-error "No tmux session for this agent"))
  (unless (gascity-terminal-tmux-session-exists-p session socket)
    (user-error "Can't find tmux session: %s (agent may have stopped)" session))
  ;; A clean argv, no shell: `env -u TMUX' lets the attach nest when Emacs runs
  ;; inside tmux, and an argv (vs a format-built shell string) means every
  ;; backend behaves identically with no quoting/injection surface.
  (let ((argv (append (list "env" "-u" "TMUX" "tmux")
                      (gascity-terminal--socket-args socket)
                      (list "attach-session" "-t" session)))
        (buf-name (format "*gc-agent-%s*" session)))
    (when (fboundp 'gascity--log)
      (gascity--log 'info "tmux attach: %s" (mapconcat #'identity argv " ")))
    (let ((buf (gascity-terminal-run argv buf-name dir)))
      (when (and gascity-terminal-mode-line-status (buffer-live-p buf))
        (gascity-terminal--status-install buf session socket))
      buf)))

(provide 'gascity-terminal)
;;; gascity-terminal.el ends here
