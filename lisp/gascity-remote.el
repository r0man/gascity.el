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
;; - Executables.  Nothing guix-related is on `tramp-remote-path' by
;;   default, so on a host that installs gc/tmux via Guix profiles a
;;   bare program name resolves to nothing until the user configures
;;   TRAMP.  `gascity-remote-find-executable' closes that gap with zero
;;   setup: it falls back to probing `gascity-remote-search-path' (the
;;   standard Guix profile bins) and returns an absolute host-local
;;   path, cached per connection.  Resolving gc itself is not enough,
;;   though: gc spawns subprocesses (git for pack imports, dolt), and
;;   they inherit the spawned process's bare PATH.
;;   `gascity-remote-path-assignment' closes that second gap — a
;;   \"PATH=dirs:$PATH\" sh fragment every remote invocation site
;;   splices before the command, prepending the same profile
;;   directories to the PATH gc's children resolve against.
;;
;; This module depends only on `gascity-custom' (the defcustom home),
;; so every other module can require it.

;;; Code:

(require 'cl-lib)
(require 'tramp)
(require 'gascity-custom)

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

;;; Finding executables on the host

(defvar gascity-remote--executable-cache (make-hash-table :test 'equal)
  "Cache mapping (REMOTE-PREFIX . NAME) to a resolved host-local path.
Only successful resolutions are cached — a miss is re-probed on the
next call, so installing the program on the host heals itself.  The
per-connection PATH fragment of `gascity-remote-path-assignment' lives
here too, under the un-collidable key (REMOTE-PREFIX . :path), as do
positive terminfo probes of `gascity-remote-terminfo-p', under
\(REMOTE-PREFIX . (:terminfo . TERM)).  Cleared by
`gascity-remote-forget-executables' (via
`gascity-context-clear-cache').")

(defun gascity-remote-forget-executables ()
  "Forget cached remote executable resolutions.
Called from `gascity-context-clear-cache' — the one user-facing cache
entry point — e.g. after a program moved on the host."
  (clrhash gascity-remote--executable-cache))

(defun gascity-remote-find-executable (name &optional dir)
  "Return NAME resolved for DIR's host (default `default-directory').
For a local DIR, or when NAME already carries a directory (an absolute
path, or `~/…' — e.g. a connection-local `gascity-executable'), NAME is
returned unchanged.  For a remote DIR a bare NAME is resolved to an
absolute host-local path (`file-local-name' form, valid in
`process-file', `make-process', and remote shell command lines):

1. `executable-find' on the host, which searches `tramp-remote-path'
   and so honours any user setup such as `tramp-own-remote-path';
2. each `gascity-remote-search-path' entry in order — `~' expanded on
   the host — testing NAME for executability there; first hit wins.
   The defaults cover Guix profiles with zero configuration.

Successful resolutions are cached per (connection × NAME); clear with
`gascity-context-clear-cache'.  An unresolvable NAME (and any probe
error, e.g. a dropped connection) returns NAME unchanged, so the
launch fails exactly where it always did — the remote shell's
\"command not found\" (exit 127) — and
`gascity-remote-spawn-error-hint' names the setup paths."
  (let ((remote (file-remote-p (or dir default-directory))))
    (if (or (not remote) (file-name-absolute-p name))
        name
      (let ((key (cons remote name)))
        (or (gethash key gascity-remote--executable-cache)
            (let* ((default-directory (or dir default-directory))
                   (found
                    (condition-case nil
                        (or (executable-find name t)
                            (cl-some
                             (lambda (entry)
                               (let ((candidate
                                      (expand-file-name
                                       name (expand-file-name
                                             (concat remote entry)))))
                                 (and (file-executable-p candidate)
                                      (file-local-name candidate))))
                             gascity-remote-search-path))
                      ;; A probe error (unreachable host, dead
                      ;; connection) must surface as the launch failure
                      ;; the callers already handle, not here.
                      (error nil))))
              (when found
                (puthash key found gascity-remote--executable-cache))
              (or found name)))))))

;;; Terminfo on the host

(defun gascity-remote--terminfo-candidates (term remote)
  "Return TRAMP file names where TERM's terminfo entry may live on REMOTE.
The compiled-entry locations ncurses consults: the user's ~/.terminfo
first, then the common system databases, each keyed by TERM's first
character (the Linux layout; the hex-keyed macOS layout is out of scope
— cities are Linux hosts).  A pure function of its inputs; the `~' is
left for the TRAMP handlers to expand host-side."
  (let ((leaf (format "%s/%s" (substring term 0 1) term)))
    (mapcar (lambda (dir) (format "%s%s/%s" remote dir leaf))
            '("~/.terminfo" "/usr/share/terminfo" "/lib/terminfo"
              "/etc/terminfo" "/usr/local/share/terminfo"))))

(defun gascity-remote-terminfo-p (term &optional dir)
  "Return non-nil when DIR's host likely has a terminfo entry for TERM.
For a local DIR (default `default-directory') this is trivially t: the
local terminal backend owns TERM and its terminfo (beads.el's env
contract).  For a remote DIR the probe is best-effort, on the host:
first `infocmp TERM' there (resolved like any remote executable; exit 0
is authoritative — it searches the same ncurses paths a linked client
does), then an existence sweep of the standard compiled-entry
locations (`gascity-remote--terminfo-candidates').

Heuristic by design: the exact search path of the host tmux's own
ncurses (e.g. a Guix store database) cannot be read from here, so a
present-but-unfound entry reports missing.  That failure mode is
benign — the caller then forces `gascity-terminal-remote-term' onto
the remote command, which narrows capabilities slightly but always
attaches, where a missing entry kills the attach outright (gce-25q).
Probe errors (a dropped connection) also report missing for the same
reason.

Positive results are cached per (connection × TERM) in
`gascity-remote--executable-cache'; a miss is re-probed on the next
call, so installing the entry on the host heals itself.  Clear with
`gascity-context-clear-cache'."
  (let ((remote (file-remote-p (or dir default-directory))))
    (if (not remote)
        t
      (let ((key (cons remote (cons :terminfo term))))
        (or (gethash key gascity-remote--executable-cache)
            (let* ((default-directory (or dir default-directory))
                   (found
                    (condition-case nil
                        (or (eq 0 (process-file
                                   (gascity-remote-find-executable "infocmp")
                                   nil nil nil term))
                            (and (cl-some
                                  #'file-exists-p
                                  (gascity-remote--terminfo-candidates
                                   term remote))
                                 t))
                      ;; A probe error must not kill the attach flow;
                      ;; "missing" only forces the safe fallback TERM.
                      (error nil))))
              (when found
                (puthash key t gascity-remote--executable-cache))
              found))))))

;;; PATH export for gc's subprocesses

(defun gascity-remote-path-assignment (&optional dir)
  "Return a \"PATH=DIRS:$PATH\" sh fragment for DIR's host, or nil.
DIRS are the `gascity-remote-search-path' entries expanded on DIR's
host (default `default-directory'; a `~' becomes the remote home),
shell-quoted and colon-joined.  Returns nil for a local DIR, an empty
search path, or when host-side expansion fails (e.g. a dropped
connection) — callers then run the command unaugmented, and the launch
fails exactly where it always did.

Every remote invocation site splices this fragment before the command
it hands the remote shell.  Resolving gc itself to an absolute profile
path (`gascity-remote-find-executable') is not enough: gc spawns
subprocesses (git for pack imports, dolt), and those children inherit
the spawned process's PATH — `tramp-remote-path' for tramp-sh, the
login environment for direct-async — which omits the profile
directories, so a real city fails with \"git: executable file not
found in $PATH\".  The assignment must be evaluated BY the remote
shell, where $PATH expands to whatever the process actually inherited;
exporting PATH through `process-environment' cannot express that:
every TRAMP handler (tramp-sh process-file/make-process and
direct-async alike, verified on Emacs 30/TRAMP 2.7) forwards env
entries shell-quoted, so a $PATH in the value arrives literal and the
inherited tail is lost.

Nonexistent directories are kept: a dead PATH entry is harmless, and
filtering would cost an existence probe per entry per connection while
masking a profile created later.  The fragment is cached per
connection alongside the executable resolutions; clear with
`gascity-context-clear-cache' after changing
`gascity-remote-search-path'."
  (let ((remote (file-remote-p (or dir default-directory))))
    (when (and remote gascity-remote-search-path)
      (let ((key (cons remote :path)))
        (or (gethash key gascity-remote--executable-cache)
            (when-let* ((dirs
                         (condition-case nil
                             (mapcar (lambda (entry)
                                       (shell-quote-argument
                                        (file-local-name
                                         (expand-file-name
                                          (concat remote entry)))))
                                     gascity-remote-search-path)
                           ;; Expanding `~' needs the connection; a
                           ;; probe error must surface as the launch
                           ;; failure the callers already handle.
                           (error nil))))
              (puthash key
                       (format "PATH=%s:$PATH"
                               (mapconcat #'identity dirs ":"))
                       gascity-remote--executable-cache)))))))

;;; Spawn diagnostics

(defun gascity-remote-spawn-error-hint (program reason &optional dir var)
  "Return a message for failing to launch PROGRAM in DIR, naming the host.
REASON is the underlying error string.  For a local DIR (default
`default-directory') this is just \"Cannot run PROGRAM: REASON\"; for a
remote DIR the message names the host and the three setup paths: remote
programs resolve against `tramp-remote-path' (not the local variable
`exec-path'), which omits non-default profile directories unless
`tramp-own-remote-path' is added; `gascity-remote-search-path' is the
probed fallback (a hit there needs no setup at all, so reaching this
hint means the program was in none of its directories); and VAR, when
non-nil, is a defcustom symbol (e.g. `gascity-executable') the user can
set connection-locally to an absolute remote path."
  (let ((remote (file-remote-p (or dir default-directory))))
    (if (not remote)
        (format "Cannot run %s: %s" program reason)
      (format (concat "Cannot run %s on %s: %s — put it on TRAMP's remote"
                      " path: (add-to-list 'tramp-remote-path"
                      " 'tramp-own-remote-path) or add its directory to"
                      " `gascity-remote-search-path'%s")
              program remote reason
              (if var
                  (format ", or set %s connection-locally for this host" var)
                "")))))

(provide 'gascity-remote)
;;; gascity-remote.el ends here
