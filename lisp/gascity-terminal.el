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
;; agent's tmux session: `gascity-terminal-attach-tmux' opens `env -u
;; TMUX tmux attach-session -t SESSION' in a terminal buffer.  (`env -u
;; TMUX' lets the attach nest when Emacs itself runs inside tmux.)
;; Session and socket names are shell-quoted before interpolation.
;;
;; Nothing here blocks Emacs (dashboard-v3 D9, §8.3 R2): every tmux call
;; the attach and the status mirror make is ONE asynchronous host script
;; (`gascity-terminal--run-async') — a local `sh -c' for a local city, a
;; local no-pty `ssh -T' pipe for a remote one (gascity's ControlMaster,
;; the pure PATH fragment, so a Guix profile tmux is found), never
;; `process-file' over TRAMP.  The attach runs one pre-step on the host
;; (`gascity-terminal--attach-script'): does the session exist, where
;; is tmux, does the host have terminfo for the TERM the local backend
;; advertises, does the agent's directory exist, and turn the session's
;; status bar off — then opens the terminal from its callback.  The
;; terminal itself is a LOCAL process (beads.el's local-argv contract):
;; for a remote city the tmux command is wrapped into a local `ssh -t
;; HOST …' argv (`gascity-terminal--attach-argv' via
;; `gascity-remote-ssh-argv') carrying the tmux path the pre-step found
;; — `ssh HOST cmd' is no login shell, so profile PATHs may be absent
;; there.  When the host lacks the backend TERM's terminfo the remote
;; command forces `gascity-terminal-remote-term' via its env prefix —
;; host-side only, the local terminal's TERM is never touched (gce-25q).
;; The status-mirror timer runs in the terminal buffer, whose
;; `default-directory' is LOCAL (it hosts a local ssh); the remote
;; context is carried buffer-locally (`gascity-terminal--status-directory').
;; The synchronous helpers (`gascity-terminal--tmux',
;; `gascity-terminal-tmux-session-exists-p', `gascity-terminal-pane-cwd')
;; remain for user-initiated one-offs such as Dired's pane-cwd fallback.
;;
;; The attach buffer is also a place the user READS bead ids — agent
;; transcripts are full of them — so it is wired for beads.el's eldoc
;; (`gascity-terminal--beads-integrate'): the id-prefix allowlist and a
;; store resolver, both from the rig memo, never a fresh gc.  And like
;; every gascity buffer it gets the I/O-free project of
;; `gascity-context-install-project', because its pinned remote
;; `default-directory' would otherwise send `project-mode-line' up the
;; host's directory tree on every redisplay.
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
(require 'seq)
(require 'beads-terminal)
(require 'gascity-custom)
(require 'gascity-context)          ; install-project, rig memo (no cycle)
(require 'gascity-remote)

(declare-function gascity--log "gascity")

;; The spawn-free bead-store resolver lives in gascity-section (which
;; requires this module); it is only ever handed on as a function value.
(declare-function gascity-beads--bead-path-cached "gascity-section" (id))
(declare-function gascity-bead-show-at-point "gascity-section")

;; beads.el's buffer-local eldoc contract (Part A of gce-eldoc).  Both
;; are referenced by name and `boundp'-guarded, so this file
;; byte-compiles with `--warnings-as-errors' and runs against an older
;; beads.el that lacks them (the wiring is then a no-op).
(defvar beads-eldoc-directory)
(defvar beads-issue-id-prefixes)

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
what keeps the t key on an agent whose terminal is already open from erroring
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
this — see `gascity-terminal-attach-tmux').  On a remote directory the
probe is bounded by `gascity-remote-sync-timeout'
\(`gascity-remote-with-timeout'): a wedged channel answers nil —
uniformly with the other failure modes — instead of hanging forever;
the local probe never needs the bound (no network, blocking C code that
runs no timers)."
  (and session (stringp session) (not (string-empty-p session))
       (condition-case nil
           (gascity-remote-with-timeout gascity-remote-sync-timeout
             (eq 0 (apply #'process-file (gascity-remote-find-executable "tmux")
                          nil nil nil
                          (append (gascity-terminal--socket-args socket)
                                  (list "has-session" "-t" session)))))
         ;; A wedged channel degrades to "does not exist" — uniformly
         ;; with the non-zero-exit and spawn-failure answers — instead of
         ;; signalling into attach/peek call sites that expect a boolean.
         (gascity-remote-sync-timeout nil))))

(defun gascity-terminal-pane-cwd (session &optional socket)
  "Return the working directory of tmux SESSION's active pane, or nil.
Runs `tmux [-L SOCKET] display-message -t SESSION -p #{pane_current_path}'
— via `process-file', so a remote city's tmux answers on its own host,
reporting a host-local path (the caller localizes it) — and returns the
trimmed path.  Returns nil when SESSION is empty, tmux is unavailable,
the session is gone, or the pane reports no path; the caller validates
that the path exists on disk.  This lets `gascity-agent-dired' open an
agent's live working directory even when its session bead recorded no
`work_dir' (mirroring gastown).  A remote probe is bounded by
`gascity-remote-sync-timeout': a timeout answers nil, uniformly with
the other failure modes, instead of hanging on a dead channel."
  (when (and session (stringp session) (not (string-empty-p session)))
    (with-temp-buffer
      (when (eq 0 (condition-case nil
                      (gascity-remote-with-timeout
                          gascity-remote-sync-timeout
                        (apply #'process-file
                               (gascity-remote-find-executable "tmux")
                               nil t nil
                               (append (gascity-terminal--socket-args socket)
                                       (list "display-message" "-t" session
                                             "-p" "#{pane_current_path}"))))
                    (file-error nil)
                    (gascity-remote-sync-timeout nil)))
        (let ((path (string-trim (buffer-string))))
          (unless (string-empty-p path) path))))))

;;; Host commands without TRAMP (dashboard-v3 D9, §8.3 R2/R4)

;; Every tmux call of the attach pre-step and the status mirror runs as
;; ONE asynchronous local process: `sh -c SCRIPT' for a local city, and
;; for a remote (ssh-family) city a local `ssh -T' pipe to the host
;; (`gascity-remote-ssh-pipe-argv', gascity's own ControlMaster, the pure
;; PATH fragment so a Guix profile tmux is found) — never `process-file'
;; over TRAMP, which blocks the command loop (and, from a timer, can
;; wedge it).  The callback runs from `run-at-time' 0, never inside the
;; sentinel.

(defun gascity-terminal--sh (&rest words)
  "Return WORDS joined into one sh command line, each shell-quoted.
A word that is a cons (:raw . STRING) is spliced unquoted."
  (mapconcat (lambda (w) (if (and (consp w) (eq (car w) :raw))
                             (cdr w)
                           (shell-quote-argument w)))
             words " "))

(defun gascity-terminal--tmux-sh (socket &rest args)
  "Return an sh command line running tmux [-L SOCKET] ARGS (quoted)."
  (apply #'gascity-terminal--sh
         (append (list "tmux") (gascity-terminal--socket-args socket) args)))

(defun gascity-terminal--host-argv (dir script)
  "Return the local argv running sh SCRIPT on DIR's host.
Locally `sh -c SCRIPT'; for a remote DIR a no-pty ssh to the host
\(no host resolution: nothing here touches TRAMP)."
  (let ((argv (list "sh" "-c" script)))
    (if (gascity-remote-prefix dir)
        (gascity-remote-ssh-pipe-argv dir argv :resolve nil)
      argv)))

(defun gascity-terminal--run-async (dir script callback)
  "Run sh SCRIPT on DIR's host asynchronously; call CALLBACK when done.
CALLBACK receives (EXIT . STDOUT): EXIT the exit status, or nil when the
process could not start or was killed at its deadline
\(`gascity-remote-async-timeout').  The process is local (a local shell,
or a local ssh for a remote DIR) and is started from a local directory,
so starting it does no remote I/O.  Returns the process, or nil."
  (let* ((out "")
         (done nil)
         (timer nil)
         (finish (lambda (exit)
                   (unless done
                     (setq done t)
                     (when (timerp timer) (cancel-timer timer))
                     (let ((result (cons exit out)))
                       (run-at-time 0 nil callback result)))))
         (proc (condition-case err
                   (let ((default-directory
                          (if (gascity-remote-prefix dir)
                              (file-name-as-directory temporary-file-directory)
                            dir)))
                     (make-process
                      :name "gascity-tmux"
                      :command (gascity-terminal--host-argv dir script)
                      :connection-type 'pipe
                      :noquery t
                      :file-handler nil
                      :stderr (get-buffer-create " *gascity-tmux-stderr*")
                      :filter (lambda (_p chunk) (setq out (concat out chunk)))
                      :sentinel (lambda (p _event)
                                  (unless (process-live-p p)
                                    (funcall finish (process-exit-status p))))))
                 (error
                  (setq out (error-message-string err))
                  (funcall finish nil)
                  nil))))
    (when (and proc (not done)
               (numberp gascity-remote-async-timeout)
               (> gascity-remote-async-timeout 0))
      (setq timer (run-at-time gascity-remote-async-timeout nil
                               (lambda ()
                                 (when (process-live-p proc)
                                   (delete-process proc))
                                 (funcall finish nil)))))
    proc))

(defun gascity-terminal--lines (out)
  "Return OUT split into its non-empty lines."
  (split-string (or out "") "\n" t))

(defun gascity-terminal--tagged (lines tag)
  "Return the rest of the first of LINES that starts with TAG, or nil."
  (seq-some (lambda (l) (and (string-prefix-p tag l) (substring l (length tag))))
            lines))

;;; tmux status in the mode line

(defvar-local gascity-terminal--status-session nil
  "Tmux session name mirrored in this buffer's mode line, or nil.")

(defvar-local gascity-terminal--status-socket nil
  "Tmux -L socket for `gascity-terminal--status-session', or nil.")

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
the session is gone), so callers treat a missing session uniformly.
A remote call is bounded by `gascity-remote-sync-timeout': a wedged
channel answers nil — uniformly with the other failure modes — instead
of hanging, which is what lets the status-mirror tick keep degrading
gracefully after the link dies (the timer path itself adds the
connection-lock and `non-essential' guards on top)."
  (with-temp-buffer
    (when (eq 0 (condition-case nil
                    (gascity-remote-with-timeout
                        gascity-remote-sync-timeout
                      (apply #'process-file
                             (gascity-remote-find-executable "tmux")
                             nil t nil
                             (append (gascity-terminal--socket-args socket) args)))
                  (file-error nil)
                  (gascity-remote-sync-timeout nil)))
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

;;; The status mirror, asynchronous

(defvar-local gascity-terminal--status-process nil
  "The status query in flight for this buffer, or nil.")

(defconst gascity-terminal--status-sep "gascity-status-left"
  "Line separating the window list from `status-left' in a status query.")

(defun gascity-terminal--status-script (session socket)
  "Return the sh script querying tmux SESSION's windows and status-left.
It exits 3 when the session is gone (`list-windows' fails)."
  (concat (gascity-terminal--tmux-sh
           socket "list-windows" "-t" session "-F"
           "#{window_active}\t#{window_index}:#{window_name}#{window_flags}")
          " 2>/dev/null || exit 3; echo "
          gascity-terminal--status-sep "; "
          (gascity-terminal--tmux-sh socket "display-message" "-p" "-t" session
                                     "#{E:status-left}")
          " 2>/dev/null; exit 0"))

(defun gascity-terminal--status-format (session out)
  "Return the mode-line status string for SESSION from query OUT, or nil.
OUT is the stdout of `gascity-terminal--status-script': window lines
\(\"ACTIVE\tINDEX:NAMEFLAGS\"), the separator, then `status-left'."
  (let* ((lines (split-string (or out "") "\n"))
         (sep (seq-position lines gascity-terminal--status-sep))
         (wlines (seq-remove #'string-empty-p (seq-take lines (or sep (length lines)))))
         (left (and sep (string-trim (string-join (nthcdr (1+ sep) lines) "\n"))))
         (windows (mapcar (lambda (line)
                            (let ((parts (split-string line "\t")))
                              (list :active (equal (car parts) "1")
                                    :label (string-join (cdr parts) "\t"))))
                          wlines)))
    (when windows
      (concat
       (propertize (if (and left (not (string-empty-p left)))
                       left
                     (truncate-string-to-width session 24 nil nil "…"))
                   'face 'gascity-city)
       "  "
       (mapconcat (lambda (w)
                    (propertize (plist-get w :label)
                                'face (if (plist-get w :active)
                                          'gascity-header 'default)))
                  windows " ")))))

(defun gascity-terminal--status-stop ()
  "Stop this buffer's status refresh timer."
  (when (timerp gascity-terminal--status-timer)
    (cancel-timer gascity-terminal--status-timer))
  (setq gascity-terminal--status-timer nil))

(defun gascity-terminal--status-refresh ()
  "Start one asynchronous status query for this buffer's tmux session.
The mode line keeps showing the last result until the answer comes;
a query still in flight makes this a no-op (a slow link is never
stacked up).  When the session has gone, the mirror clears and its
timer stops.  Runs no TRAMP and no synchronous process: the query is
one local process (`gascity-terminal--run-async') to the host."
  (when (and gascity-terminal--status-session
             (not (process-live-p gascity-terminal--status-process)))
    (let ((buffer (current-buffer))
          (session gascity-terminal--status-session)
          (dir (or gascity-terminal--status-directory default-directory)))
      (setq gascity-terminal--status-process
            (gascity-terminal--run-async
             dir
             (gascity-terminal--status-script session gascity-terminal--status-socket)
             (lambda (result)
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (setq gascity-terminal--status-process nil)
                   (cond
                    ((eql (car result) 0)
                     (setq gascity-terminal--status-string
                           (gascity-terminal--status-format session (cdr result))))
                    ((eql (car result) 3)
                     ;; The session is gone: nothing left to mirror.
                     (setq gascity-terminal--status-string nil)
                     (gascity-terminal--status-stop)))
                   ;; Any other failure (timeout, dropped link) keeps the
                   ;; last result; the next tick retries.
                   (force-mode-line-update)))))))))

(defun gascity-terminal--status-tick (buffer)
  "Timer callback: refresh BUFFER's tmux status while it is live.
Asynchronous and skipped while the previous query is in flight
\(`gascity-terminal--status-refresh'); no TRAMP, so no connection lock
to respect."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (gascity-terminal--status-refresh))))

(defun gascity-terminal--status-teardown ()
  "Tear down the tmux status mirror for the current buffer.
Cancels the refresh timer and, in the background, removes the session's
tmux `status' override (`set-option -u') so a later `tmux attach' shows
its own status bar again.  Run from `kill-buffer-hook'; never blocks."
  (gascity-terminal--status-stop)
  (when (process-live-p gascity-terminal--status-process)
    (delete-process gascity-terminal--status-process))
  (when (and gascity-terminal--status-session
             (stringp gascity-terminal--status-session)
             (not (string-empty-p gascity-terminal--status-session)))
    (ignore-errors
      (gascity-terminal--run-async
       (or gascity-terminal--status-directory default-directory)
       (concat (gascity-terminal--tmux-sh gascity-terminal--status-socket
                                          "set-option" "-t"
                                          gascity-terminal--status-session
                                          "-u" "status")
               " >/dev/null 2>&1")
       #'ignore))))

(defun gascity-terminal--status-install (buffer session socket &optional dir status-off)
  "Hide tmux SESSION's status bar and mirror it in BUFFER's mode line.
Splices a buffer-local mode-line segment showing the session's friendly
name and window list into the mode line before its trailing fill,
starts a refresh timer, and arranges teardown on buffer kill.  The
session's tmux status bar is turned off (scoped via `set-option -t') in
the background — unless STATUS-OFF says the caller already did (the
attach pre-step does, in its one host round trip).  DIR, when a remote
TRAMP directory, is the city context the tmux queries run on; it is
stored buffer-locally so the refresh and teardown reach the city's host
from this otherwise-local buffer.  Nothing here blocks: every tmux call
is an asynchronous local process.  Idempotent: safe to re-run when
reattaching to a live terminal."
  (when (and (buffer-live-p buffer)
             session (stringp session) (not (string-empty-p session)))
    (with-current-buffer buffer
      (setq gascity-terminal--status-session session
            gascity-terminal--status-socket socket
            gascity-terminal--status-directory (and dir (file-remote-p dir)
                                                    dir))
      (unless status-off
        (gascity-terminal--run-async
         (or gascity-terminal--status-directory default-directory)
         (concat (gascity-terminal--tmux-sh socket "set-option" "-t" session
                                            "status" "off")
                 " >/dev/null 2>&1")
         #'ignore))
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
      ;; (Re)start the refresh timer; query once now, in the background.
      (gascity-terminal--status-stop)
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

(defvar-keymap gascity-terminal-attach-map
  :doc "Keys gascity adds to its tmux attach buffers.
Active wherever `gascity-terminal--attach-keys' is set (see
`gascity-terminal--install-keys').  Only `C-c'-prefixed keys belong
here: vterm forwards everything else to the pty
\(`vterm-keymap-exceptions'), and the backends' copy modes own the
plain keys."
  "C-c b" #'gascity-bead-show-at-point)

(defvar-local gascity-terminal--attach-keys nil
  "Non-nil in a gascity attach buffer: activates `gascity-terminal-attach-map'.")

;; An emulation map rather than a layer over the local map: vterm's
;; copy mode swaps the buffer's local map for its own (and back), which
;; would drop a local layer exactly when point can reach an id.
;; `emulation-mode-map-alists' outranks local and minor-mode maps in
;; every state, and the map binds so little that nothing is shadowed.
(add-to-list 'emulation-mode-map-alists
             `((gascity-terminal--attach-keys . ,gascity-terminal-attach-map)))

(defun gascity-terminal--install-keys (buffer)
  "Activate `gascity-terminal-attach-map' in BUFFER.  Returns BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq gascity-terminal--attach-keys t)))
  buffer)

(defun gascity-terminal--project-root (dir store)
  "Return the project root for an attach buffer pinned to DIR.
STORE, when non-nil, is the agent's rig store directory; it is the root
when DIR sits under it (a polecat worktree inside the rig checkout), so
`project-name' shows the rig, not the worktree leaf.  Otherwise DIR
itself.  Both are directory names already; the comparison is a string
prefix — no file access."
  (let ((dir (file-name-as-directory dir)))
    (if (and store (stringp store)
             (string-prefix-p (file-name-as-directory store) dir))
        (file-name-as-directory store)
      dir)))

(defun gascity-terminal--beads-integrate (buffer store)
  "Wire beads.el's eldoc in the attach BUFFER to the agent's STORE.
STORE is the agent's rig store directory (nil when unknown).  Sets,
buffer-locally, `beads-eldoc-directory' — STORE when known, else the
spawn-free per-id resolver `gascity-beads--bead-path-cached', so
`bd show' runs against the store owning the id's prefix rather than
the buffer's own directory (which for a remote attach is the city
root, whose `bd' answers \"no issues found\" for a rig's bead) — and
`beads-issue-id-prefixes' to the city's real prefixes from the rig
memo, when it is warm, so a random hyphenated token in the transcript
never costs a `bd show'.  Nothing here spawns gc: the memo is read,
never filled.  A no-op when beads-eldoc is absent or predates the
variables (soft `require', `boundp' guards)."
  (when (buffer-live-p buffer)
    (require 'beads-eldoc nil t)
    (with-current-buffer buffer
      (when (boundp 'beads-eldoc-directory)
        (setq-local beads-eldoc-directory
                    (or store #'gascity-beads--bead-path-cached)))
      (when-let* (((boundp 'beads-issue-id-prefixes))
                  (prefixes (gascity-rigs-cached-prefixes)))
        (setq-local beads-issue-id-prefixes prefixes)))))

(defun gascity-terminal--term-probe-sh (term)
  "Return an sh test that succeeds when the host has terminfo for TERM.
`infocmp TERM', then an existence sweep of the standard compiled-entry
locations — the host-side twin of `gascity-remote-terminfo-p'."
  (let ((leaf (format "%s/%s" (substring term 0 1) term)))
    (concat "{ infocmp " (shell-quote-argument term) " >/dev/null 2>&1"
            " || [ -e \"$HOME\"/.terminfo/" (shell-quote-argument leaf) " ]"
            (mapconcat (lambda (d) (concat " || [ -e " (shell-quote-argument
                                                       (concat d "/" leaf))
                                           " ]"))
                       '("/usr/share/terminfo" "/lib/terminfo" "/etc/terminfo"
                         "/usr/local/share/terminfo")
                       "")
            "; }")))

(defun gascity-terminal--attach-script (session socket &rest opts)
  "Return the attach pre-step: one sh script, one host round trip.
It prints `gascity-no-session' and stops when SESSION is missing on
SOCKET; else `gascity-tmux:PATH' (tmux as the host resolves it), and
per OPTS: :term TERM → `gascity-term-ok'/`gascity-term-missing';
:dir DIR (host-local) → `gascity-dir-ok' when it exists; :status-off →
turns the session's tmux status bar off."
  (let ((term (plist-get opts :term))
        (dir (plist-get opts :dir)))
    (concat
     (gascity-terminal--tmux-sh socket "has-session" "-t" session)
     " >/dev/null 2>&1 || { echo gascity-no-session; exit 0; }; "
     "echo gascity-tmux:$(command -v tmux); "
     (if term
         (concat "if " (gascity-terminal--term-probe-sh term)
                 "; then echo gascity-term-ok; else echo gascity-term-missing; fi; ")
       "")
     (if dir
         (concat "[ -d " (shell-quote-argument dir) " ] && echo gascity-dir-ok; ")
       "")
     (if (plist-get opts :status-off)
         (concat (gascity-terminal--tmux-sh socket "set-option" "-t" session
                                            "status" "off")
                 " >/dev/null 2>&1; ")
       "")
     "echo gascity-ok")))

(defun gascity-terminal--term-to-probe (remote)
  "Return (FORCE . PROBE) deciding the TERM of a REMOTE attach.
FORCE is the fallback TERM to force without probing (the backend's TERM
is unknown), PROBE the backend TERM whose terminfo the host must be
asked about; both nil when nothing needs forcing — the fallback is off,
the backend already advertises it, or a previous probe found the entry
\(cached per connection in `gascity-remote--executable-cache')."
  (when-let* ((fallback gascity-terminal-remote-term))
    (let ((client
           ;; Backend detection is local, and may load the backend
           ;; package: never with a remote `default-directory' (its
           ;; defcustoms expand `~' through the TRAMP handler).
           (let ((default-directory (file-name-as-directory
                                     temporary-file-directory)))
             (gascity-terminal--client-term))))
      (cond ((null client) (cons fallback nil))
            ((equal client fallback) nil)
            ((gethash (cons (gascity-remote-prefix remote) (cons :terminfo client))
                      gascity-remote--executable-cache)
             nil)
            (t (cons nil client))))))

(defun gascity-terminal-attach-tmux (session &optional socket dir store)
  "Attach to tmux SESSION in a terminal buffer, without blocking Emacs.
SOCKET selects a non-default tmux server when set.  DIR is the working
directory for the spawned terminal.  STORE is the agent's rig store
directory when the caller knows it (`gascity-agent-attach-tmux' passes
the memoized one); it scopes the buffer's project and beads eldoc.
Signals a `user-error' when SESSION is empty, or at once for a remote
method plain ssh cannot reach.

A live terminal for SESSION is raised at once.  Otherwise ONE
asynchronous pre-step on the city's host (`gascity-terminal--run-async':
a local shell, or a local `ssh -T' pipe for a remote city — never TRAMP)
checks that the session exists, resolves tmux there, asks for terminfo
of the TERM the local backend advertises when it may be missing
\(`gascity-terminal--term-to-probe'), checks DIR, and turns the
session's tmux status bar off; when it answers, the terminal opens.  A
missing session is echoed (\"Can't find tmux session …\"), never
signalled from the callback.  The command returns at once (D9).

When `default-directory' is remote (a view of a remote city), the
terminal is a LOCAL ssh running tmux there (`gascity-terminal--attach-argv'
— ssh methods only) with the tmux path the pre-step found (`ssh HOST
cmd' runs no login shell, so a Guix profile tmux may be off its PATH),
and forcing `gascity-terminal-remote-term' when the host lacks terminfo
for the backend's TERM (gce-25q).  The buffer name is city-qualified so
local and remote attaches — and two same-host cities' attaches —
coexist; its `default-directory' is pinned to DIR on the host when the
pre-step found it there, else to the city directory the attach came
from.

Pinned local or remote, the buffer then gets gascity's I/O-free
`project' (`gascity-context-install-project'), beads eldoc wired to the
agent's store (`gascity-terminal--beads-integrate') and, when
`gascity-terminal-mode-line-status' is non-nil, the asynchronous tmux
status mirror (`gascity-terminal--status-install').  Returns the live
terminal buffer when one was raised, else nil."
  (unless (and session (stringp session) (not (string-empty-p session)))
    (user-error "No tmux session for this agent"))
  (let* ((origin default-directory)
         (remote (and (file-remote-p origin) origin))
         ;; Built first: an unsupported TRAMP method fails here with its
         ;; clear `user-error', before anything runs.
         (_ (gascity-terminal--attach-argv session socket remote))
         (buf-name (gascity-remote-buffer-name
                    (format "*gc-agent-%s*" session) nil
                    (or (gascity-context-city-root)
                        (gascity-remote-prefix origin))))
         (existing (gascity-terminal--live-buffer buf-name)))
    (if existing
        (gascity-terminal-run nil buf-name)
      (let* ((term (and remote (gascity-terminal--term-to-probe remote)))
             (host-dir (and remote dir (stringp dir) (not (string-empty-p dir))
                            (file-local-name
                             (or (gascity-remote-localize-path dir remote) dir))))
             (status-off gascity-terminal-mode-line-status)
             (script (gascity-terminal--attach-script
                      session socket :term (cdr term) :dir host-dir
                      :status-off status-off)))
        (message "Attaching %s…" session)
        (gascity-terminal--run-async
         origin script
         (lambda (result)
           (let ((default-directory origin))
             (gascity-terminal--attach-finish
              result session socket dir store remote buf-name term host-dir
              status-off))))
        nil))))

(defun gascity-terminal--attach-finish (result session socket dir store remote
                                               buf-name term host-dir status-off)
  "Open the attach terminal after the pre-step answered RESULT.
RESULT is (EXIT . STDOUT) of `gascity-terminal--attach-script'; the other
arguments are the attach's, see `gascity-terminal-attach-tmux'.  Runs
from a timer: reports problems in the echo area, never signals."
  (let ((lines (gascity-terminal--lines (cdr result))))
    (cond
     ((member "gascity-no-session" lines)
      (message "Can't find tmux session: %s (agent may have stopped)" session))
     ((not (member "gascity-ok" lines))
      (message "tmux attach %s failed: %s" session
               (if (car result)
                   (or (car (last lines)) (format "exit %s" (car result)))
                 "no answer from the host (timed out)")))
     (t
      (let* ((tmux (gascity-terminal--tagged lines "gascity-tmux:"))
             (tmux (and tmux (not (string-empty-p tmux)) tmux))
             (term-ok (member "gascity-term-ok" lines))
             (forced (cond ((car term) (car term))
                           ((and (cdr term) (not term-ok)) gascity-terminal-remote-term))))
        (when (and remote (cdr term) term-ok)
          (puthash (cons (gascity-remote-prefix remote) (cons :terminfo (cdr term)))
                   t gascity-remote--executable-cache))
        (let* ((argv (gascity-terminal--attach-argv
                      session socket remote (and remote tmux) forced))
               (buf (progn
                      (when (fboundp 'gascity--log)
                        (gascity--log 'info "tmux attach: %s"
                                      (mapconcat #'identity argv " ")))
                      (gascity-terminal-run argv buf-name (if remote "~/" dir)))))
          (when (and remote (buffer-live-p buf))
            ;; The local ssh spawned from a local directory, but the
            ;; buffer belongs to the city: pin the agent's directory on
            ;; the host when the pre-step found it, else the city
            ;; directory the attach came from.
            (with-current-buffer buf
              (setq default-directory
                    (if (and host-dir (member "gascity-dir-ok" lines))
                        (file-name-as-directory
                         (concat (gascity-remote-prefix remote) host-dir))
                      remote))))
          (when (buffer-live-p buf)
            (gascity-context-install-project
             buf (gascity-terminal--project-root
                  (buffer-local-value 'default-directory buf) store))
            (gascity-terminal--install-keys buf)
            (gascity-terminal--beads-integrate buf store)
            (when gascity-terminal-mode-line-status
              (gascity-terminal--status-install buf session socket remote
                                                status-off)))
          buf))))))

;;; Backend preload

;; The first attach of a session loads the terminal backend's library
;; (vterm, eat, term …) while deciding the TERM — ~240 ms of blocked
;; command loop on a cold Emacs (docs/qa/2026-09-25-dashboard-v3-terminal-async.md).
;; The first gascity view to open schedules that load for the next idle
;; moment instead, once per session.

(defvar gascity-terminal--preload-state nil
  "nil (not scheduled), `scheduled', or `done'.")

(defun gascity-terminal--backend-loaded-p ()
  "Return non-nil when the configured backend's library is already loaded.
The `auto' backend counts as loaded once any known backend is."
  (pcase gascity-terminal-backend
    ('vterm (featurep 'vterm))
    ('eat (featurep 'eat))
    ('term (featurep 'term))
    (_ (seq-some #'featurep '(vterm eat ghostel term)))))

(defun gascity-terminal-preload-backend ()
  "Load the terminal backend's library now, unless it already is.
Resolves the backend exactly as an attach would (loading its package),
from a local `default-directory'.  Errors are swallowed: a preload must
never disturb the user; the attach reports any real problem later."
  (setq gascity-terminal--preload-state 'done)
  (unless (gascity-terminal--backend-loaded-p)
    (let ((default-directory (file-name-as-directory temporary-file-directory))
          (inhibit-message t))
      (ignore-errors (gascity-terminal--client-term)))))

(defun gascity-terminal--schedule-preload (&rest _)
  "Schedule the one-shot backend preload for the next idle moment.
On `gascity-view-created-functions': the first gascity view opened in
an interactive session schedules it; later views do nothing."
  (unless (or gascity-terminal--preload-state noninteractive
              (gascity-terminal--backend-loaded-p))
    (setq gascity-terminal--preload-state 'scheduled)
    (run-with-idle-timer 2 nil #'gascity-terminal-preload-backend)))

(add-hook 'gascity-view-created-functions #'gascity-terminal--schedule-preload)

(provide 'gascity-terminal)
;;; gascity-terminal.el ends here
