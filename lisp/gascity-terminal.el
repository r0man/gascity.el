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
;; Remote cities: the tmux server runs on the city's host, so the
;; existence/pane probes go through `process-file' — on a remote
;; `default-directory' they run tmux on that host, with the tmux
;; program resolved by `gascity-remote-find-executable' (so a Guix
;; host's profile tmux is found with zero setup).  The attach itself
;; cannot: the terminal backend spawns LOCAL processes (beads.el's
;; local-argv contract), so for a remote city the tmux command is
;; wrapped into a local `ssh -t HOST …' argv
;; (`gascity-terminal--attach-argv' via `gascity-remote-ssh-argv'),
;; carrying the same resolved tmux — `ssh HOST cmd' is no login shell,
;; so profile PATHs may be absent there too.  ssh also forwards the
;; TERM the local backend advertises (ghostel's xterm-ghostty, say);
;; on a host without that terminfo entry the remote tmux client dies
;; instantly with "missing or unsuitable terminal", so when the host
;; appears to lack it (`gascity-remote-terminfo-p') the remote command
;; forces `gascity-terminal-remote-term' via its env prefix — host-side
;; only, the local terminal's TERM is never touched (gce-25q).
;; The status-mirror timer runs in the terminal buffer, whose
;; `default-directory' is LOCAL (it hosts a local ssh); the remote
;; context is carried buffer-locally (`gascity-terminal--status-directory')
;; and bound around every probe.
;;
;; Keys belong to the pty: a terminal buffer is a full-screen program,
;; and the backend's own keymap is only the buffer's LOCAL map, which
;; every enabled minor-mode map outranks.  A global minor mode binding
;; the same key wins and the program never sees it — with
;; `pixel-scroll-precision-mode' on, PageUp/PageDown scroll the Emacs
;; window (which shows only the visible screen, tmux being on the
;; alternate screen) instead of paging tmux's copy-mode.
;; `gascity-terminal--unshadow-keys' hands each mode in
;; `gascity-terminal-unshadow-minor-modes' an empty keymap through the
;; buffer's `minor-mode-overriding-map-alist', so the backend's
;; forwarding wins in gascity's terminals and nowhere else.
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

(require 'cl-lib)
(require 'beads-terminal)
(require 'gascity-custom)
(require 'gascity-remote)

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

(defun gascity-terminal--client-term ()
  "Return the TERM the selected terminal backend advertises, or nil.
This is the value ssh forwards on a remote attach: the backend exports
TERM to the processes it spawns, and beads.el's env contract keeps
callers from overriding it locally.  The `auto' backend resolves to
the first available concrete terminal exactly as `beads-terminal-spawn'
would (priority order over `beads-terminal-list').  Each backend's
TERM comes from its own variable when bound, else from its documented
default — the package can be available yet not loaded.  Returns nil
for a backend this map does not know; callers treat that as \"assume
the host cannot render it\" and force the fallback."
  (let* ((class (gascity-terminal--backend-class))
         (terminal
          (if (eq class 'beads-terminal-auto)
              (cl-find-if (lambda (term)
                            (and (not (cl-typep term 'beads-terminal-auto))
                                 (beads-terminal-available-p term)))
                          (beads-terminal-list))
            (make-instance class))))
    (pcase (and terminal (oref terminal name))
      ("ghostel" (or (bound-and-true-p ghostel-term) "xterm-ghostty"))
      ("vterm" (or (bound-and-true-p vterm-term-environment-variable)
                   "xterm-256color"))
      ("eat" (or (bound-and-true-p eat-term-name) "xterm-256color"))
      ((or "term" "ansi-term") (or (bound-and-true-p term-term-name)
                                   "eterm-color"))
      (_ nil))))

(defun gascity-terminal--remote-term (&optional dir)
  "Return the TERM to force on DIR's host in a remote attach, or nil.
Nil means keep the TERM ssh forwards natively, because the fallback is
off (`gascity-terminal-remote-term' nil), the backend already
advertises the fallback (forcing would change nothing — no probe is
made), or DIR's host has terminfo for the backend's TERM
\(`gascity-remote-terminfo-p').  An unknown backend TERM forces the
fallback without probing — the safe default: a missing entry kills the
attach outright (gce-25q), a needlessly forced fallback merely narrows
the capabilities tmux sees."
  (when-let* ((fallback gascity-terminal-remote-term))
    (let ((client (gascity-terminal--client-term)))
      (unless (or (equal client fallback)
                  (and client (gascity-remote-terminfo-p client dir)))
        fallback))))

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

(defun gascity-terminal--unshadow-keys (buffer)
  "Suppress `gascity-terminal-unshadow-minor-modes' inside BUFFER.
Gives each named minor mode an empty keymap in BUFFER's
`minor-mode-overriding-map-alist', so keys the mode binds globally reach
the terminal instead — the backend forwards them from the buffer's local
map, which a minor-mode map would otherwise outrank.  Buffer-local, so
the modes are untouched everywhere else.

Idempotent, and conservative: an entry another package already made for
the same mode is left as it found it.  A nil option, a dead BUFFER, or a
non-symbol entry is a no-op."
  (when (and (buffer-live-p buffer) gascity-terminal-unshadow-minor-modes)
    (with-current-buffer buffer
      (dolist (mode gascity-terminal-unshadow-minor-modes)
        (when (and mode (symbolp mode)
                   (not (assq mode minor-mode-overriding-map-alist)))
          (setq-local minor-mode-overriding-map-alist
                      (cons (cons mode (make-sparse-keymap))
                            minor-mode-overriding-map-alist))))))
  buffer)

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
pops to it.

Either way the buffer is unshadowed (`gascity-terminal--unshadow-keys')
so keys the terminal should own are not swallowed by a global minor
mode."
  (let ((existing (gascity-terminal--live-buffer buffer-name)))
    (if existing
        ;; Reuse the live terminal — raise its window, don't re-exec.
        (progn (gascity-terminal--unshadow-keys existing)
               (pop-to-buffer existing)
               existing)
      ;; No live terminal: spawn a fresh one.
      (let* ((default-dir (gascity-terminal--working-dir dir))
             (terminal (make-instance (gascity-terminal--backend-class)))
             (buf (beads-terminal-spawn terminal buffer-name argv default-dir
                                        '(("CLICOLOR_FORCE" . "1")))))
        (when (and buf (buffer-live-p buf))
          (gascity-terminal--unshadow-keys buf)
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
  "Return non-nil when tmux SESSION exists (on optional SOCKET).
Probes via `process-file', so on a remote `default-directory' the
city's own tmux server is asked, on its host — tmux resolved there by
`gascity-remote-find-executable'.  Signals a `file-error' when tmux
itself cannot be run there (callers that need a clean message wrap
this — see `gascity-terminal-attach-tmux')."
  (and session (stringp session) (not (string-empty-p session))
       (eq 0 (apply #'process-file (gascity-remote-find-executable "tmux")
                    nil nil nil
                    (append (gascity-terminal--socket-args socket)
                            (list "has-session" "-t" session))))))

(defun gascity-terminal-pane-cwd (session &optional socket)
  "Return the working directory of tmux SESSION's active pane, or nil.
Runs `tmux [-L SOCKET] display-message -t SESSION -p #{pane_current_path}'
— via `process-file', so a remote city's tmux answers on its own host,
reporting a host-local path (the caller localizes it) — and returns the
trimmed path.  Returns nil when SESSION is empty, tmux is unavailable,
the session is gone, or the pane reports no path; the caller validates
that the path exists on disk.  This lets `gascity-agent-dired' open an
agent's live working directory even when its session bead recorded no
`work_dir' (mirroring gastown)."
  (when (and session (stringp session) (not (string-empty-p session)))
    (with-temp-buffer
      (when (eq 0 (condition-case nil
                      (apply #'process-file
                             (gascity-remote-find-executable "tmux")
                             nil t nil
                             (append (gascity-terminal--socket-args socket)
                                     (list "display-message" "-t" session
                                           "-p" "#{pane_current_path}")))
                    (file-error nil)))
        (let ((path (string-trim (buffer-string))))
          (unless (string-empty-p path) path))))))

;;; tmux status in the mode line

(defvar-local gascity-terminal--status-session nil
  "tmux session name mirrored in this buffer's mode line, or nil.")

(defvar-local gascity-terminal--status-socket nil
  "tmux -L socket for `gascity-terminal--status-session', or nil.")

(defvar-local gascity-terminal--status-directory nil
  "Directory whose host this buffer's tmux status probes run on, or nil.
For a remote city this is the remote (TRAMP) directory the attach was
invoked from; the status refresh and teardown bind `default-directory'
to it so their tmux calls reach the city's host — the terminal buffer
itself has a LOCAL `default-directory', since for a remote attach it
hosts a local ssh.  Nil means probe wherever `default-directory' points
\(a local city).")

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
Runs via `process-file' where `default-directory' points, so a remote
city's tmux server is probed on its own host — tmux resolved there by
`gascity-remote-find-executable'.  Returns nil when tmux is
unavailable, the remote connection fails, or tmux exits non-zero (e.g.
the session is gone), so callers treat a missing session uniformly."
  (with-temp-buffer
    (when (eq 0 (condition-case nil
                    (apply #'process-file
                           (gascity-remote-find-executable "tmux")
                           nil t nil
                           (append (gascity-terminal--socket-args socket) args))
                  (file-error nil)))
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
Probes run against `gascity-terminal--status-directory' when set (the
remote city the attach came from) — the terminal buffer's own
`default-directory' is local for a remote attach.  `non-essential' is
bound so TRAMP never establishes a NEW connection from this timer path
\(a dropped link must degrade the mirror, not freeze Emacs on a
reconnect timeout).  When the session has gone (or the remote is
unreachable), clear the cache and stop the refresh timer — there is
nothing left to poll."
  (let* ((default-directory (or gascity-terminal--status-directory
                                default-directory))
         (non-essential t)
         (s (and gascity-terminal--status-session
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
  "Timer callback: refresh BUFFER's tmux status while it is live.
Skipped while BUFFER's remote channel is mid-command
\(`gascity-remote-connection-locked-p'): a timer can fire inside
another TRAMP call's `accept-process-output', where a fresh remote
probe signals \"Forbidden reentrant call of Tramp\" — which the probe
layer would misread as the session being gone and stop the mirror for
good.  (The old guard read `tramp-locked', a variable TRAMP >= 2.6
no longer has; the lock lives on the connection process now.)  The
next tick simply retries."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (unless (gascity-remote-connection-locked-p
               (or gascity-terminal--status-directory default-directory))
        (gascity-terminal--status-refresh)))))

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
      ;; `non-essential' as in the refresh: never let killing a terminal
      ;; buffer block on re-establishing a dropped remote connection.
      (let ((default-directory (or gascity-terminal--status-directory
                                   default-directory))
            (non-essential t))
        (gascity-terminal--tmux gascity-terminal--status-socket
                                "set-option" "-t"
                                gascity-terminal--status-session
                                "-u" "status")))))

(defun gascity-terminal--status-install (buffer session socket &optional dir)
  "Hide tmux SESSION's status bar and mirror it in BUFFER's mode line.
Turns the session's tmux status bar off (scoped to the session via
`set-option -t'), splices a buffer-local mode-line segment showing the
session's friendly name and window list into the mode line before its
trailing fill, starts a refresh timer, and arranges teardown on buffer
kill.  DIR, when a remote TRAMP directory, is the city context the tmux
probes must run in; it is stored buffer-locally so the refresh timer and
teardown reach the city's host from this otherwise-local buffer.
Idempotent: safe to re-run when reattaching to a live terminal."
  (when (and (buffer-live-p buffer)
             session (stringp session) (not (string-empty-p session)))
    (with-current-buffer buffer
      (setq gascity-terminal--status-session session
            gascity-terminal--status-socket socket
            gascity-terminal--status-directory (and dir (file-remote-p dir)
                                                    dir))
      ;; Scope: turn this session's tmux status bar off.  Reverted on
      ;; teardown via `set-option -u'.  Best-effort (nil on failure).
      (let ((default-directory (or gascity-terminal--status-directory
                                   default-directory)))
        (gascity-terminal--tmux socket "set-option" "-t" session
                                "status" "off"))
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

(defun gascity-terminal--attach-argv (session socket &optional remote
                                              program term)
  "Return the local argv that attaches tmux SESSION on SOCKET.
A pure function of its inputs.  The local shape is `env -u TMUX tmux
[-L SOCKET] attach-session -t SESSION' — a clean argv, no shell: `env -u
TMUX' lets the attach nest when Emacs runs inside tmux, and an argv (vs
a format-built shell string) means every backend behaves identically
with no quoting/injection surface.  With REMOTE (a TRAMP name for the
city's host) the same command is wrapped into a local `ssh -t' argv via
`gascity-remote-ssh-argv' — the city's tmux server runs on the city's
host, while the terminal backend only spawns local processes — which
signals a `user-error' for non-ssh methods and multi-hop names.
PROGRAM overrides the tmux program name; the remote attach passes the
resolved host path so the ssh side runs the same tmux the probes did.
TERM, when non-nil, is spliced into the env prefix as `TERM=TERM' —
the remote attach passes `gascity-terminal--remote-term' so a host
without terminfo for the client's TERM gets a name it can render
instead of killing the attach (gce-25q).  The assignment runs
host-side, after ssh, overriding the forwarded value; the local
terminal's own TERM (owned by the backend) is never touched, and a
local attach passes no TERM at all."
  (let ((argv (append (list "env" "-u" "TMUX")
                      (and term (list (concat "TERM=" term)))
                      (list (or program "tmux"))
                      (gascity-terminal--socket-args socket)
                      (list "attach-session" "-t" session))))
    (if remote (gascity-remote-ssh-argv remote argv) argv)))

(defun gascity-terminal-attach-tmux (session &optional socket dir)
  "Attach to tmux SESSION in a terminal buffer.
SOCKET selects a non-default tmux server when set.  DIR is the working
directory for the spawned terminal.  Signals a `user-error' when SESSION
is empty or does not exist (e.g. the agent has stopped).

When `default-directory' is remote (a view of a remote city), the
existence probe runs on the city's host, the spawned terminal is a
LOCAL ssh running tmux there (`gascity-terminal--attach-argv' — ssh
methods only, a `user-error' otherwise) with tmux resolved to the same
host path the probes use (`gascity-remote-find-executable' — `ssh HOST
cmd' runs no login shell, so a Guix profile tmux may be off its PATH),
and the buffer name is host-qualified so local and remote attaches
coexist.  When the host seems to lack terminfo for the TERM the local
backend advertises, the remote command forces
`gascity-terminal-remote-term' instead of dying with \"missing or
unsuitable terminal\" (`gascity-terminal--remote-term').
DIR (a host-local path on the city) cannot be the spawn
directory — the backend spawns the local ssh from the local home — but
the buffer's `default-directory' is then pinned remotely: to DIR
re-prefixed for the host when that directory exists there, else to the
remote `default-directory' the attach was invoked from.  The pin does
not affect the running ssh; it makes `dired'/`find-file' from the
attach buffer default to the agent's directory on the city's host
instead of the local home.

When `gascity-terminal-mode-line-status' is non-nil, the session's tmux
status bar is hidden and mirrored in the terminal buffer's mode line (see
`gascity-terminal--status-install')."
  (unless (and session (stringp session) (not (string-empty-p session)))
    (user-error "No tmux session for this agent"))
  (let* ((remote (and (file-remote-p default-directory) default-directory))
         ;; Build the argv before probing: an unsupported TRAMP method
         ;; should fail with its clear `user-error', not after a remote
         ;; round trip — so this validation pass stays unresolved.
         (argv (gascity-terminal--attach-argv session socket remote))
         (buf-name (gascity-remote-buffer-name
                    (format "*gc-agent-%s*" session))))
    (unless (condition-case err
                (gascity-terminal-tmux-session-exists-p session socket)
              (file-error
               (user-error "%s" (gascity-remote-spawn-error-hint
                                 "tmux" (error-message-string err)))))
      (user-error "Can't find tmux session: %s (agent may have stopped)" session))
    ;; Method validated, session exists: swap in the host-resolved tmux
    ;; for the ssh side (a cache hit — the probe above resolved it), and
    ;; force a renderable TERM when the host lacks terminfo for the
    ;; client's — probed now, on the warm connection, never during the
    ;; validation pass above.
    (when remote
      (setq argv (gascity-terminal--attach-argv
                  session socket remote
                  (gascity-remote-find-executable "tmux" remote)
                  (gascity-terminal--remote-term remote))))
    (when (fboundp 'gascity--log)
      (gascity--log 'info "tmux attach: %s" (mapconcat #'identity argv " ")))
    (let ((buf (gascity-terminal-run argv buf-name (if remote "~/" dir))))
      (when (and remote (buffer-live-p buf))
        ;; The local ssh had to spawn from a local directory, but the
        ;; buffer must belong to the city: pin the agent's directory on
        ;; the host (else the city context the attach came from), so
        ;; user commands (dired, find-file) default remotely.
        ;; `non-essential' keeps the existence probe off any NEW
        ;; connection (the city's is already open from the session
        ;; probe above), and a probe error just falls back to REMOTE.
        (with-current-buffer buf
          (setq default-directory
                (or (let ((non-essential t))
                      (ignore-errors
                        (when-let* ((localized (gascity-remote-localize-path
                                                dir remote))
                                    ((stringp localized))
                                    ((file-remote-p localized))
                                    ((file-directory-p localized)))
                          (file-name-as-directory localized))))
                    remote))))
      (when (and gascity-terminal-mode-line-status (buffer-live-p buf))
        (gascity-terminal--status-install buf session socket remote))
      buf)))

(provide 'gascity-terminal)
;;; gascity-terminal.el ends here
