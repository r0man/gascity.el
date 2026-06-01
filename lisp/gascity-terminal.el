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

(defun gascity-terminal-run (argv buffer-name &optional dir)
  "Spawn ARGV in a terminal buffer named BUFFER-NAME.
ARGV is a (PROGRAM . ARGS) list run with no intervening shell via
beads.el's `beads-terminal-spawn', using the backend from
`gascity-terminal-backend'.  beads sets the working directory from DIR
\(its WORKING-DIR contract); nil or a missing DIR falls back to the home
directory.  Returns the spawned buffer and pops to it."
  (let* ((default-dir (gascity-terminal--working-dir dir))
         (terminal (make-instance (gascity-terminal--backend-class)))
         (buf (beads-terminal-spawn terminal buffer-name argv default-dir
                                    '(("CLICOLOR_FORCE" . "1")))))
    (when (and buf (buffer-live-p buf))
      (pop-to-buffer buf))
    buf))

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

(defun gascity-terminal-attach-tmux (session &optional socket dir)
  "Attach to tmux SESSION in a terminal buffer.
SOCKET selects a non-default tmux server when set.  DIR is the working
directory for the spawned terminal.  Signals a `user-error' when SESSION
is empty or does not exist (e.g. the agent has stopped)."
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
    (gascity-terminal-run argv buf-name dir)))

(provide 'gascity-terminal)
;;; gascity-terminal.el ends here
