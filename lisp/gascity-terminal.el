;;; gascity-terminal.el --- gascity shim over beads.el's tmux terminal -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; tmux terminal support for gascity, now owned by beads.el
;; (`beads-terminal' + `beads-terminal-tmux', WI-14).  This module is the
;; compatibility shim (WI-15): every symbol gascity's own code and history
;; used forwards to the `beads-terminal-tmux-*' implementation, and the
;; gascity custom options are aliases of the beads ones, so nothing else
;; in gascity has to move.
;;
;; What cannot live in beads stays here, wrapped around the attach:
;;
;; - the rig-store buffer qualification (`gascity-remote-buffer-name'
;;   with the city root) so local and remote attaches -- and two
;;   same-host cities' attachments -- coexist;
;; - the I/O-free `project' of `gascity-context-install-project'
;;   (project.el's VC walk over TRAMP on every redisplay was a real
;;   hang, dashboard-v3 D9);
;; - the rig-scoped beads eldoc (`gascity-terminal--beads-integrate'):
;;   the per-id rig memorandums and the city's real id prefixes;
;; - the gascity key map (`C-c b' -> `gascity-bead-show-at-point');
;; - the debug log of the attach argv.
;;
;; beads.el stays free of gascity: the only gascity-specific parameter
;; is the tmux SOCKET, passed through `beads-terminal-attach'.

;;; Code:

(require 'beads-terminal)
(require 'beads-terminal-tmux)
(require 'gascity-custom)
(require 'gascity-context)
(require 'gascity-remote)

(declare-function gascity--log "gascity")
(declare-function gascity-bead-show-at-point "gascity-section")
(declare-function gascity-beads--bead-path-cached "gascity-section" (id))
(declare-function gascity-rigs-cached-prefixes "gascity-context")

;;; Forwarded surface: every symbol gascity's own code and history used
;;; is a thin forward to the beads.el implementation (WI-14/WI-15).

(defalias 'gascity-terminal--arm-preload #'beads-terminal-tmux--arm-preload)
(defalias 'gascity-terminal--arm-wheel #'beads-terminal-tmux--arm-wheel)
(defalias 'gascity-terminal--attach-argv #'beads-terminal-tmux--attach-argv)
(defalias 'gascity-terminal--attach-script #'beads-terminal-tmux--attach-script)
(defalias 'gascity-terminal--backend-class #'beads-terminal-tmux--backend-class)
(defalias 'gascity-terminal--backend-loaded-p #'beads-terminal-tmux--backend-loaded-p)
(defalias 'gascity-terminal--backend-reports-mouse-p #'beads-terminal-tmux--backend-reports-mouse-p)
(defalias 'gascity-terminal--client-term #'beads-terminal-tmux--client-term)
(defalias 'gascity-terminal--ghostel-available-p #'beads-terminal-tmux--ghostel-available-p)
(defalias 'gascity-terminal--ghostel-control-key #'beads-terminal-tmux--ghostel-control-key)
(defalias 'gascity-terminal--ghostel-send #'beads-terminal-tmux--ghostel-send)
(defalias 'gascity-terminal--host-argv #'beads-terminal-tmux--host-argv)
(defalias 'gascity-terminal--lines #'beads-terminal-tmux--lines)
(defalias 'gascity-terminal--live-buffer #'beads-terminal-tmux--live-buffer)
(defalias 'gascity-terminal--mouse-ensure-script #'beads-terminal-tmux--mouse-ensure-script)
(defalias 'gascity-terminal--mouse-teardown-script #'beads-terminal-tmux--mouse-teardown-script)
(defalias 'gascity-terminal-pane-cwd #'beads-terminal-tmux-pane-cwd)
(defalias 'gascity-terminal-preload-backend #'beads-terminal-tmux-preload-backend)
(defalias 'gascity-terminal--preload-when-idle #'beads-terminal-tmux--preload-when-idle)
(defalias 'gascity-terminal--remote-term #'beads-terminal-tmux--remote-term)
(defalias 'gascity-terminal-run #'beads-terminal-tmux-run)
(defalias 'gascity-terminal--run-async #'beads-terminal-tmux--run-async)
(defalias 'gascity-terminal--schedule-preload #'beads-terminal-tmux--schedule-preload)
(defalias 'gascity-terminal--scroll-backend #'beads-terminal-tmux--scroll-backend)
(defalias 'gascity-terminal-scroll-key #'beads-terminal-tmux-scroll-key)
(defalias 'gascity-terminal--scroll-sequence #'beads-terminal-tmux--scroll-sequence)
(defalias 'gascity-terminal-scroll-toggle #'beads-terminal-tmux-scroll-toggle)
(defalias 'gascity-terminal-scroll-wheel #'beads-terminal-tmux-scroll-wheel)
(defalias 'gascity-terminal--send-raw #'beads-terminal-tmux--send-raw)
(defalias 'gascity-terminal--sh #'beads-terminal-tmux--sh)
(defalias 'gascity-terminal--socket-args #'beads-terminal-tmux--socket-args)
(defalias 'gascity-terminal--status-format #'beads-terminal-tmux--status-format)
(defalias 'gascity-terminal--status-install #'beads-terminal-tmux--status-install)
(defalias 'gascity-terminal--status-refresh #'beads-terminal-tmux--status-refresh)
(defalias 'gascity-terminal--status-script #'beads-terminal-tmux--status-script)
(defalias 'gascity-terminal--status-segment #'beads-terminal-tmux--status-segment)
(defalias 'gascity-terminal--status-stop #'beads-terminal-tmux--status-stop)
(defalias 'gascity-terminal--status-string #'beads-terminal-tmux--status-string)
(defalias 'gascity-terminal--status-teardown #'beads-terminal-tmux--status-teardown)
(defalias 'gascity-terminal--status-tick #'beads-terminal-tmux--status-tick)
(defalias 'gascity-terminal--tagged #'beads-terminal-tmux--tagged)
(defalias 'gascity-terminal--teardown-script #'beads-terminal-tmux--teardown-script)
(defalias 'gascity-terminal--term-probe-sh #'beads-terminal-tmux--term-probe-sh)
(defalias 'gascity-terminal--term-to-probe #'beads-terminal-tmux--term-to-probe)
(defalias 'gascity-terminal--tmux #'beads-terminal-tmux--tmux)
(defalias 'gascity-terminal--tmux-sh #'beads-terminal-tmux--tmux-sh)
(defalias 'gascity-terminal--unshadow-keys #'beads-terminal-tmux--unshadow-keys)
(defalias 'gascity-terminal--wheel-mouse-sequence #'beads-terminal-tmux--wheel-mouse-sequence)
(defalias 'gascity-terminal--window-list #'beads-terminal-tmux--window-list)
(defalias 'gascity-terminal--working-dir #'beads-terminal-tmux--working-dir)
(defalias 'gascity-terminal-tmux-session-exists-p #'beads-terminal-tmux-session-exists-p)

;;; Buffer-local state and modes follow their implementation.

(defvaralias 'gascity-terminal-scroll-mode 'beads-terminal-tmux-scroll-mode)
(defvaralias 'gascity-terminal-wheel-mode 'beads-terminal-tmux-wheel-mode)
(defvaralias 'gascity-terminal--scroll-wheel-first
  'beads-terminal-tmux--scroll-wheel-first)
(defvaralias 'gascity-terminal--preload-state
  'beads-terminal-tmux--preload-state)
(defvaralias 'gascity-terminal--status-session
  'beads-terminal-tmux--status-session)
(defvaralias 'gascity-terminal--status-socket
  'beads-terminal-tmux--status-socket)
(defvaralias 'gascity-terminal--status-directory
  'beads-terminal-tmux--status-directory)
(defvaralias 'gascity-terminal--status-string
  'beads-terminal-tmux--status-string)
(defvaralias 'gascity-terminal--status-timer
  'beads-terminal-tmux--status-timer)
(defvaralias 'gascity-terminal--status-mirrored
  'beads-terminal-tmux--status-mirrored)
(defvaralias 'gascity-terminal--status-process
  'beads-terminal-tmux--status-process)

;;; The gascity key map on top of beads' attach buffer

;; beads.el's own attach map binds `C-c b' to `beads-show-at-point'; in a
;; gascity city the id belongs to a rig store, so gascity keeps its own
;; map binding `C-c b' to `gascity-bead-show-at-point'.  The scroll
;; sub-mode itself is beads' (`gascity-terminal-scroll-toggle' and
;; `gascity-terminal-scroll-mode' are aliases).
(defvar-keymap gascity-terminal-attach-map
  :doc "Keys gascity adds to its tmux attach buffers.
Active wherever `gascity-terminal--attach-keys' is set (see
`gascity-terminal--install-keys').  Only `C-c'-prefixed keys belong
here: vterm forwards everything else to the pty
\(`vterm-keymap-exceptions'), and the backends' copy modes own the
plain keys."
  "C-c b" #'gascity-bead-show-at-point
  "C-c s" #'gascity-terminal-scroll-toggle)

(defvar-local gascity-terminal--attach-keys nil
  "Non-nil in a gascity attach buffer: activates `gascity-terminal-attach-map'.")

;; An emulation map rather than a layer over the local map: vterm's copy
;; mode swaps the buffer's local map for its own (and back), which would
;; drop a local layer exactly when point can reach an id.
;; `emulation-mode-map-alists' outranks local and minor-mode maps in every
;; state, and the map binds so little that nothing is shadowed.
(add-to-list 'emulation-mode-map-alists
             `((gascity-terminal--attach-keys . ,gascity-terminal-attach-map)))

(defun gascity-terminal--install-keys (buffer)
  "Wire BUFFER as an attach buffer.  Returns BUFFER.
Activates `gascity-terminal-attach-map' and arms the out-of-the-box
wheel mode when the backend needs it (`gascity-terminal--arm-wheel')."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq gascity-terminal--attach-keys t)
      (gascity-terminal--arm-wheel buffer)))
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
and forcing `beads-terminal-tmux-remote-term' when the host lacks terminfo
for the backend's TERM (gce-25q).  The buffer name is city-qualified so
local and remote attaches — and two same-host cities' attaches —
coexist; its `default-directory' is pinned to DIR on the host when the
pre-step found it there, else to the city directory the attach came
from.

Pinned local or remote, the buffer then gets gascity's I/O-free
`project' (`gascity-context-install-project'), beads eldoc wired to the
agent's store (`gascity-terminal--beads-integrate') and, when
`beads-terminal-tmux-mode-line-status' is non-nil, the asynchronous tmux
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
             (status-off beads-terminal-tmux-mode-line-status)
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
RESULT is (EXIT . STDOUT) of `gascity-terminal--attach-script'.
SESSION, SOCKET, DIR, STORE, REMOTE, BUF-NAME, TERM, HOST-DIR and
STATUS-OFF are the attach's, see `gascity-terminal-attach-tmux'.  Runs
from a timer: reports problems in the echo area, never signals."
  (let ((lines (gascity-terminal--lines (cdr result))))
    (cond
     ((member "beads-no-session" lines)
      (message "Can't find tmux session: %s (agent may have stopped)" session))
     ((not (member "beads-ok" lines))
      (message "tmux attach %s failed: %s" session
               (if (car result)
                   (or (car (last lines)) (format "exit %s" (car result)))
                 "no answer from the host (timed out)")))
     (t
      (let* ((tmux (gascity-terminal--tagged lines "beads-tmux:"))
             (tmux (and tmux (not (string-empty-p tmux)) tmux))
             (term-ok (member "beads-term-ok" lines))
             (forced (cond ((car term) (car term))
                           ((and (cdr term) (not term-ok)) beads-terminal-tmux-remote-term))))
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
                    (if (and host-dir (member "beads-dir-ok" lines))
                        (file-name-as-directory
                         (concat (gascity-remote-prefix remote) host-dir))
                      remote))))
          (when (buffer-live-p buf)
            (gascity-context-install-project
             buf (gascity-terminal--project-root
                  (buffer-local-value 'default-directory buf) store))
            (gascity-terminal--install-keys buf)
            (gascity-terminal--beads-integrate buf store)
            (gascity-terminal--status-install buf session socket remote
                                              status-off))
          buf))))))

;;; Backend preload

;; The first attach of a session loads the terminal backend's library
;; (vterm, eat, term ...) while deciding the TERM: ~240 ms of blocked
;; command loop on a cold Emacs.  The first gascity view to open
;; schedules that load ahead of time, on genuine idle, once per session.
(add-hook 'gascity-view-created-functions #'beads-terminal-tmux--schedule-preload)

(provide 'gascity-terminal)
;;; gascity-terminal.el ends here
