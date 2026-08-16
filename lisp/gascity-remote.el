;;; gascity-remote.el --- Remote (TRAMP) city helpers -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Helpers for managing a remote Gas City over TRAMP from a local Emacs.
;; A gascity view opened on a remote `default-directory' (e.g.
;; /ssh:user@host:/home/user/city/) must keep three things straight:
;;
;; - Paths.  `gc … --json' reports paths (worktree, work_dir,
;;   pane_current_path, …) as absolute paths on the machine running gc.
;;   Opening one locally is wrong; `gascity-remote-localize-path'
;;   re-prefixes it with the view's TRAMP prefix.
;;
;; - Buffer identity.  A local and a remote dashboard must coexist, so
;;   `gascity-remote-buffer-name' qualifies a view's buffer name with
;;   the remote prefix — the single keying scheme for every gascity
;;   buffer (status, lists, rig dashboard, agent detail, terminal).
;;
;; - Interactive attach.  `gc' reads run remotely through the TRAMP
;;   process primitives (`process-file' / `make-process :file-handler'),
;;   but a tmux attach needs a LOCAL terminal running ssh:
;;   `gascity-remote-ssh-argv' converts a TRAMP name into the local ssh
;;   argv that runs a command on the city's host.  beads.el's
;;   `beads-terminal-spawn' keeps receiving a plain local argv.
;;
;; This module has no gascity dependencies, so every other module can
;; require it.

;;; Code:

(require 'cl-lib)
(require 'tramp)

;;; Paths

(defun gascity-remote-localize-path (path &optional dir)
  "Return PATH openable from DIR's host (default `default-directory').
gc reports paths (an agent's worktree, a rig's repo, a tmux pane's cwd)
as host-local absolute paths on the machine running gc.  When DIR is a
remote TRAMP name, re-prefix PATH with DIR's remote prefix so
`find-file'/`dired' open it on that host.  A local DIR — or a nil, empty,
or already-remote PATH — returns PATH unchanged."
  (let ((remote (and (stringp path)
                     (not (string-empty-p path))
                     (not (file-remote-p path))
                     (file-remote-p (or dir default-directory)))))
    (if remote (concat remote path) path)))

;;; Buffer identity

(defun gascity-remote-buffer-name (base &optional dir)
  "Return BASE qualified by DIR's remote prefix, so views key per host.
BASE is a gascity buffer name (\"*gascity-status*\").  For a local DIR
\(default `default-directory') BASE is returned unchanged; for a remote
DIR the TRAMP prefix is spliced in before the trailing `*', e.g.
\"*gascity-status@/ssh:user@host:*\" — so a local and a remote view of
the same kind coexist.  This is the one buffer-keying scheme for every
gascity view (status dashboard, lists, rig dashboard, agent detail, and
terminal attach buffers)."
  (let ((remote (file-remote-p (or dir default-directory))))
    (cond ((not remote) base)
          ((string-suffix-p "*" base)
           (format "%s@%s*" (substring base 0 -1) remote))
          (t (format "%s@%s" base remote)))))

;;; Local ssh argv for a remote host

(defconst gascity-remote-ssh-methods '("ssh" "sshx" "scp" "scpx")
  "TRAMP methods whose host a plain local `ssh' can reach.
These all authenticate over ssh with the same user/host/port triple, so
an interactive attach can bypass TRAMP and run `ssh' directly.")

(defun gascity-remote-ssh-argv (name argv)
  "Return a local ssh argv running ARGV on the host of TRAMP file NAME.
NAME is a remote TRAMP file name (or bare prefix) using an ssh-based
method (`gascity-remote-ssh-methods'); ARGV is the (PROGRAM . ARGS) list
to run there.  The result is (\"ssh\" \"-t\" [\"-l\" USER] [\"-p\" PORT]
HOST TOKENS...), each remote token shell-quoted for the remote POSIX
shell — ssh joins them with spaces and hands the line to the login
shell.  Signals a `user-error' for a non-ssh method or a multi-hop
name (neither maps onto one plain ssh invocation)."
  (unless (tramp-tramp-file-p name)
    (user-error "Not a remote TRAMP name: %s" name))
  (let* ((vec (tramp-dissect-file-name name))
         (method (tramp-file-name-method vec))
         (user (tramp-file-name-user vec))
         (host (tramp-file-name-host vec))
         (port (tramp-file-name-port vec))
         (hop (tramp-file-name-hop vec)))
    (when hop
      (user-error "Multi-hop TRAMP name not supported for a direct ssh: %s"
                  name))
    (unless (member method gascity-remote-ssh-methods)
      (user-error "TRAMP method %s cannot be reached with plain ssh (need %s)"
                  method (mapconcat #'identity gascity-remote-ssh-methods "/")))
    (append (list "ssh" "-t")
            (and user (list "-l" user))
            (and port (list "-p" (format "%s" port)))
            (list host)
            (mapcar #'shell-quote-argument argv))))

;;; Spawn diagnostics

(defun gascity-remote-spawn-error-hint (program reason &optional dir var)
  "Return a message for failing to launch PROGRAM in DIR, naming the host.
REASON is the underlying error string.  For a local DIR (default
`default-directory') this is just \"Cannot run PROGRAM: REASON\"; for a
remote DIR the message names the host and explains the fix: remote
programs resolve against `tramp-remote-path' (not the local variable
`exec-path'), which omits non-default profile directories unless
`tramp-own-remote-path' is added.  VAR, when non-nil, is a defcustom
symbol (e.g. `gascity-executable') the user can instead set
connection-locally to an absolute remote path."
  (let ((remote (file-remote-p (or dir default-directory))))
    (if (not remote)
        (format "Cannot run %s: %s" program reason)
      (format (concat "Cannot run %s on %s: %s — put it on TRAMP's remote"
                      " path: (add-to-list 'tramp-remote-path"
                      " 'tramp-own-remote-path)%s")
              program remote reason
              (if var
                  (format ", or set %s connection-locally for this host" var)
                "")))))

(provide 'gascity-remote)
;;; gascity-remote.el ends here
