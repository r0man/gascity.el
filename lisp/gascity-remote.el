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
;; - Buffer identity.  A local and a remote dashboard must coexist, and
;;   so must two cities on one host, so `gascity-remote-buffer-name'
;;   qualifies a view's buffer name with one qualifier segment — the
;;   single keying scheme for every gascity buffer (status, lists, rig
;;   dashboard, agent detail, terminal).  The view factory passes the
;;   governing city root as the qualifier (`gascity-context-scope-key'
;;   is the scheme's owner: the city root embeds the remote prefix, so
;;   same-host cities differ in the path part); without a qualifier the
;;   name degrades to today's host-only shape — the remote prefix,
;;   unchanged for a local directory.
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
;;   setup: it falls back to probing `beads-remote-search-path' (the
;;   standard Guix profile bins) and returns an absolute host-local
;;   path, cached per connection.  Resolving gc itself is not enough,
;;   though: gc spawns subprocesses (git for pack imports, dolt), and
;;   they inherit the spawned process's bare PATH.
;;   `gascity-remote-path-assignment' closes that second gap — a
;;   \"PATH=dirs:$PATH\" sh fragment every remote invocation site
;;   splices before the command, prepending the same profile
;;   directories to the PATH gc's children resolve against.  Both
;;   (and the per-connection cache and ssh argv builders) live in
;;   beads.el's `beads-remote', shared with bd; the gascity functions
;;   are thin wrappers (dashboard-v3 §12 B4).
;;
;; - Connection reuse.  Async reads (`gascity-reader-read-async') run
;;   through TRAMP's `make-process' :file-handler, so their handler is
;;   whatever the connection has — by default the tramp-sh channel
;;   handler, which multiplexes every spawn over the ONE pooled ssh
;;   connection.  This is measured, not assumed (W1, ga-o98t — see
;;   plans/tramp-history-flood/implementation-summary-ga-o98t.md; REQ-002):
;;   on a live /ssh:localhost: city, N = 10 consecutive async reads spawned
;;   exactly one ssh process (at connection establishment, before the
;;   burst) and appended zero new ssh login lines to the host's
;;   `~/.bash_history', i.e. no fresh login per read.  Do not enable
;;   direct-async (`tramp-direct-async-process') connection-locally to
;;   "speed this up": that handler spawns a fresh local ssh PER READ,
;;   which is exactly the per-refresh login flood the pooling avoids.
;;   The direct-async support in `gascity-reader.el' stays — it exists
;;   so a connection where the user DID enable it still behaves
;;   correctly — but gascity itself never turns it on.
;; - History.  Every shell TRAMP opens on the host appends to the
;;   growing ~/.tramp_history (`tramp-histfile-override').
;;   `gascity-remote-silence-shell-history' — wired from the view
;;   buffer factory — points HISTFILE at /dev/null in the buffers
;;   gascity owns, by appending one entry to the buffer-local
;;   `tramp-remote-process-environment' (gascity-remote.el's history
;;   hygiene section documents the user-run truncation command for an
;;   already-bloated file).
;;
;; This module depends on `gascity-custom' (the defcustom home) and
;; `gascity-error' (the timeout condition is a `gascity-error' child, so
;; the action layer's existing error handlers catch and display it
;; cleanly); every other module can require it.

;;; Code:

(require 'cl-lib)
(require 'tramp)
(require 'gascity-custom)
(require 'gascity-error)
(require 'beads-remote)
(require 'gascity-timer)

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

;;; Pure name operations

(defun gascity-remote-prefix (name)
  "Return NAME's TRAMP prefix (\"/method:user@host:\"), or nil when local.
Pure: NAME is only dissected (`tramp-dissect-file-name'), never
expanded.  Use this instead of `file-remote-p' wherever NAME may be a
host-only name such as \"/ssh:host:\" — a scheduler host key, a
configured host: TRAMP's `file-remote-p' expands its argument, and
expanding an EMPTY localname asks the host for its home directory, a
synchronous round trip (`tramp-get-home-directory') that wedged a
timer at 100% CPU (P1 bug on f80fab1)."
  (when (and (stringp name) (tramp-tramp-file-p name))
    (when-let* ((vec (ignore-errors (tramp-dissect-file-name name))))
      (tramp-make-tramp-file-name vec 'noloc))))

(defun gascity-remote-canonical-dir (dir)
  "Return the canonical spelling of directory DIR, for cache and table keys.
A remote DIR becomes its dissected TRAMP prefix plus localname, so
\"/mock::/c/\" and \"/mock:HOST:/c/\" (TRAMP's default host filled in,
also /sudo::) are one directory; a local DIR is expanded.  Pure:
dissection only (`gascity-remote-prefix'), no I/O.  The one
canonicaliser of the store's entry keys and the live stream table."
  (let ((dir (file-name-as-directory dir)))
    (if-let* ((prefix (gascity-remote-prefix dir))
              (vec (ignore-errors (tramp-dissect-file-name dir))))
        (concat prefix (file-name-as-directory (tramp-file-name-localname vec)))
      (expand-file-name dir))))

;;; Buffer identity

(defun gascity-remote-buffer-name (base &optional dir qualifier)
  "Return BASE qualified by QUALIFIER, or by DIR's remote prefix.
QUALIFIER, when non-nil, is spliced in verbatim before the trailing
`*' — the view factory passes the governing city root
\(`gascity-context-scope-key'), so two cities on one host get distinct
buffer names and a remote city's name carries host and city path.
Without QUALIFIER the behavior is the host-only qualification: DIR's
TRAMP prefix spliced before the trailing `*' (e.g.
\"*gascity-sessions@/ssh:user@host:*\"), and a local DIR (default
`default-directory') returns BASE unchanged.  This is the one
buffer-keying scheme for every gascity view (status dashboard, lists,
rig dashboard, agent detail, and terminal attach buffers)."
  (let ((qualifier (or qualifier (file-remote-p (or dir default-directory)))))
    (cond ((not qualifier) base)
          ((string-suffix-p "*" base)
           (format "%s@%s*" (substring base 0 -1) qualifier))
          (t (format "%s@%s" base qualifier)))))

;;; Channel hygiene

(defun gascity-remote-connection-locked-p (&optional dir)
  "Return non-nil when DIR's TRAMP channel is mid-command.
DIR defaults to `default-directory'; a local DIR (or one with no
established connection) returns nil.  This reads the per-connection
\"locked\" property that TRAMP >= 2.6 sets around every channel
roundtrip (`with-tramp-locked-connection') — the old global
`tramp-locked' variable no longer exists there.  Timer code probing the
same host must skip its probe while this is set: a fresh channel command
from inside another one interleaves output on the shared connection
process (or signals \"Forbidden reentrant call of Tramp\")."
  ;; Pure: dissect, never `file-remote-p' — DIR may be a host-only
  ;; scheduler key (see `gascity-remote-prefix').
  (when-let* ((name (or dir default-directory))
              ((tramp-tramp-file-p name))
              (vec (ignore-errors (tramp-dissect-file-name name)))
              (proc (tramp-get-connection-process vec)))
    (tramp-get-connection-property proc "locked")))

(defun gascity-remote-drain-connection (&optional dir)
  "Best-effort: consume pending stale output on DIR's TRAMP channel.
DIR defaults to `default-directory'; a local DIR is a no-op.  When a
channel command is abandoned mid-flight (tramp-sh catches `C-g' inside
`process-file' and returns -1, but the remote command keeps running),
its output arrives on the shared connection later and the next
channel command harvests it as its own stdout — the session list then
tries to parse tmux status-probe chatter as `gc' JSON (gce parse-error
\"Invalid number format\").  Draining reads the connection until it has
been quiet for a moment, so a retried command starts on a clean
channel.  Quits propagate (`with-local-quit') — the user can always
abort the wait; errors are swallowed, draining is advisory."
  (when-let* ((name (or dir default-directory))
              ((tramp-tramp-file-p name))
              (vec (ignore-errors (tramp-dissect-file-name name)))
              (proc (tramp-get-connection-process vec)))
    (when (process-live-p proc)
      (ignore-error error
        (with-local-quit
          ;; Stop after a quiet tenth of a second; a still-running
          ;; abandoned command keeps the loop alive while it talks.
          ;; JUST-THIS-ONE: never dispatch other processes' output
          ;; (filters running arbitrary code) from this cleanup path.
          (let ((rounds 50))
            (while (and (> rounds 0)
                        (accept-process-output proc 0.1 nil t))
              (setq rounds (1- rounds)))))))))

;;; Property hygiene

(defun gascity-remote-flush-file-cache (&optional dir)
  "Flush TRAMP's cached file properties for remote directory DIR.
DIR defaults to `default-directory'; a local DIR is a no-op.  Drops the
directory's own cached attribute entry (`file-directory-p' consults it)
plus every per-file property cached for its contents, so a cached-NEGATIVE
answer cannot survive the call: a channel command misparsed on a
half-dead connection can leave `file-directory-p' answering nil for a
healthy remote directory (the \"no such directory\" false negatives,
ga-eyw9), and a probe that retries after this flush sees the directory
as it is now, not as the poisoned cache had it.  Best-effort: any TRAMP
error is swallowed — flushing is advisory hygiene, never a failure.
Returns DIR when a remote flush was attempted, nil when nothing was
flushed (a local DIR)."
  (when-let* ((dir (or dir default-directory))
              ((file-remote-p dir)))
    (prog1 dir
      (ignore-errors
        (with-parsed-tramp-file-name (directory-file-name dir) nil
          ;; The directory's own attributes (`file-directory-p' reads
          ;; these)…
          (tramp-flush-file-properties v localname)
          ;; …and anything cached for the files inside it.
          (tramp-flush-directory-properties v localname))))))

;;; Synchronous-call timeout

(define-error 'gascity-remote-sync-timeout
  "Gas City synchronous remote call timed out"
  'gascity-error)

(defun gascity-remote--kill-connection (remote)
  "Delete the TRAMP connection process of REMOTE (a TRAMP prefix), if any.
A TRAMP wait (`tramp-wait-for-regexp', `accept-process-output' on the
connection) returns — with an error — once its process is gone; this is
what bounds a synchronous TRAMP call.  No remote I/O."
  (when-let* ((vec (ignore-errors (tramp-dissect-file-name remote)))
              (proc (ignore-errors (tramp-get-connection-process vec))))
    (when (process-live-p proc)
      (delete-process proc))))

(defun gascity-remote--timeout-signal (secs)
  "Signal `gascity-remote-sync-timeout' for a bound of SECS."
  (signal 'gascity-remote-sync-timeout
          (list (format "synchronous remote call timed out after %s seconds\
 (connection wedged?); raise or disable `gascity-remote-sync-timeout' to suit"
                        secs))))

(defun gascity-remote-call-with-timeout (secs fn)
  "Call FN, abandoning it after SECS on a remote `default-directory'.
The function behind `gascity-remote-with-timeout'.  Two bounds run:
`with-timeout' (fires in any wait that runs timers) and a plain timer
that deletes the directory's TRAMP connection process.  The second is
the one that holds inside TRAMP: TRAMP suspends `with-timeout' timers
\(`with-timeout-suspend') while it waits for its connection, so a wedged
channel (ControlMaster deadlock, dead link) would otherwise block
forever; deleting the connection process makes that wait return.
Either way `gascity-remote-sync-timeout' is signalled (after a
`gascity-remote-drain-connection' of a still-live channel).  A nil,
zero or negative SECS, or a local directory, calls FN unbounded."
  (if (not (and (numberp secs) (> secs 0) (file-remote-p default-directory)))
      (funcall fn)
    (let* ((remote (file-remote-p default-directory))
           (fired nil)
           (killer (run-at-time secs nil
                                (lambda ()
                                  (setq fired t)
                                  (gascity-remote--kill-connection remote)))))
      (unwind-protect
          (condition-case err
              (with-timeout (secs (setq fired t)
                                  (gascity-remote--timeout-signal secs))
                (funcall fn))
            (gascity-remote-sync-timeout
             ;; The abandoned channel command keeps its output in flight;
             ;; drain so a retried command starts clean (gce-desync).
             (ignore-error error (gascity-remote-drain-connection))
             (signal (car err) (cdr err)))
            (error
             ;; The killer timer unwound a TRAMP wait: report the bound,
             ;; not TRAMP's \"process died\" error.
             (if fired
                 (gascity-remote--timeout-signal secs)
               (signal (car err) (cdr err)))))
        (cancel-timer killer)))))

(defmacro gascity-remote-with-timeout (seconds &rest body)
  "Run BODY, abandoning it after SECONDS on a remote directory.
SECONDS is evaluated (typically `gascity-remote-sync-timeout'); a nil,
zero, or negative value — or a LOCAL `default-directory' — runs BODY
unbounded.  See `gascity-remote-call-with-timeout': the bound holds
inside TRAMP's own waits (it deletes the connection process, which
unwinds them), and expiry signals `gascity-remote-sync-timeout', a
`gascity-error' child the action layer's handlers display cleanly."
  (declare (indent 1))
  `(gascity-remote-call-with-timeout ,seconds (lambda () ,@body)))

;;; History hygiene

(defconst gascity-remote-history-silencer "HISTFILE=/dev/null"
  "The environment entry gascity appends to `tramp-remote-process-environment'.
TRAMP overrides HISTFILE itself (`tramp-histfile-override', by default
\"~/.tramp_history\"), so every shell it opens on the remote host — the
connection's login shell and the inner shells spawned for the\n`make-process :file-handler' reads behind the auto-refreshing views —
appends its history to a growing ~/.tramp_history.  Pointing HISTFILE
at the null device silences those shells.  The override is applied
buffer-locally in the buffers gascity owns
\(`gascity-remote-silence-shell-history', wired from the view-buffer
factory), never globally: the user's other TRAMP usage outside
gascity.el buffers keeps the untouched global
`tramp-remote-process-environment'.

An existing ~/.tramp_history is left alone by this override — shrinking
it is a USER-run command (never executed by this package, and never by
any workflow or agent on the user's behalf):

  : > ~/.tramp_history")

(defun gascity-remote-history-environment (&optional environment)
  "Return ENVIRONMENT (default the current `tramp-remote-process-environment')
with `gascity-remote-history-silencer' appended.  The append — never a
wholesale rebind — preserves every entry already present, including
TRAMP's own defaults (\"HISTORY=\", \"ENV=''\", …), and is idempotent: a
value that already carries the silencer passes through unchanged.  The
result is the environment TRAMP reads when spawning a remote process
from the calling buffer (its connection-local machinery applies the
variable buffer-locally, exactly where gascity's views pin their
`default-directory')."
  (let ((environment (or environment tramp-remote-process-environment)))
    (if (member gascity-remote-history-silencer environment)
        environment
      (append environment (list gascity-remote-history-silencer)))))

(defun gascity-remote-silence-shell-history (&optional buffer)
  "Silence remote shell history in BUFFER (default the current one).
No-op for a local BUFFER.  Buffer-locally extends
`tramp-remote-process-environment' with the HISTFILE silencer
\(`gascity-remote-history-environment'): TRAMP reads that variable in
the buffer a remote process is spawned from, so the override governs
every inner shell gascity starts from its own view buffers — and only
those.  A buffer-local value never reaches the user's other TRAMP
buffers (a criteria-registered connection-local profile would: file
visits apply those to every remote buffer on the host), and the global
default keeps TRAMP's own entries untouched."
  (with-current-buffer (or buffer (current-buffer))
    (when (file-remote-p default-directory)
      (setq-local tramp-remote-process-environment
                  (gascity-remote-history-environment)))))

;;; Local ssh argv for a remote host

(defun gascity-remote-ssh-argv (name argv)
  "Return a local ssh argv running ARGV with a tty on the host of NAME.
Thin wrapper over `beads-remote-ssh-argv' (the tmux attach path): NAME
is a TRAMP name with an ssh-family method, ARGV is (PROGRAM . ARGS);
the result is (\"ssh\" \"-t\" [\"-l\" USER] [\"-p\" PORT] HOST TOKENS...).
Signals a `user-error' for a non-ssh method or a multi-hop name."
  (beads-remote-ssh-argv name argv))

(defcustom gascity-remote-ssh-options
  '("-o" "ControlMaster=auto" "-o" "ControlPersist=60")
  "Extra ssh options of `gascity-remote-ssh-pipe-argv'.
Spliced in after \"ssh\" for every no-pty pipe process (async reads,
actions, the live event stream).  Unless a ControlPath is given here, a
gascity-own one is added (`gascity-remote-ssh-control-path'), distinct
from TRAMP's \"tramp.%C\", so concurrent processes to one host share a
single ssh master: the first process performs the handshake — in the
background, it is a process — and the others multiplex over it."
  :type '(repeat string)
  :group 'gascity)

(defun gascity-remote-ssh-control-path ()
  "Return the ControlPath of gascity's ssh masters (never TRAMP's).
beads.el's `beads-remote-ssh-control-path', so gc and bd pipe processes
to a host share one master."
  beads-remote-ssh-control-path)

(defun gascity-remote-pure-path-assignment ()
  "Return a \"PATH=DIRS:$PATH\" fragment built WITHOUT touching the host.
beads.el's `beads-remote-pure-path-assignment': a `~/'-relative
`beads-remote-search-path' entry becomes \"$HOME\"/… for the remote
shell to expand (§8.3 R2).  Nil when the search path is empty."
  (beads-remote-pure-path-assignment))

(defconst gascity-remote-exit-reporter
  (concat "exec 3<&0; "
          "\"$0\" \"$@\" </dev/null & p=$!; "
          "{ cat >/dev/null; kill $p; } <&3 >/dev/null 2>&1 & w=$!; "
          "wait $p; s=$?; kill $w 2>/dev/null; "
          "echo \"gascity-live-exit $s\" >&2")
  "Host-side sh script running a long-lived gc ($0 and $@) over ssh.
A watcher kills gc as soon as the session's stdin reaches EOF — the
local ssh went away: with no pty there is no SIGHUP, and gc would
otherwise linger on the host until its next write fails.  The script
also reports gc's exit status as a last \"gascity-live-exit N\" stderr
line, so a gc that died is told apart from a dropped connection (ssh
exits 255 without it).  Used by every remote stream: the live event
stream (`gascity-live') and the agent log follower.")

(cl-defun gascity-remote-ssh-stream-argv (dir executable args &key cd env)
  "Return the local ssh argv running long-lived EXECUTABLE ARGS on DIR's host.
The command runs under `gascity-remote-exit-reporter' with the session's
stdin kept open (no \"-n\"), so killing the local process stops gc on
the host too; built with `gascity-remote-ssh-pipe-argv' without host
resolution (no TRAMP round trip).  CD and ENV are passed through."
  (gascity-remote-ssh-pipe-argv
   dir
   (append (list "/bin/sh" "-c" gascity-remote-exit-reporter executable) args)
   :cd cd :env env :resolve nil :stdin t))

(cl-defun gascity-remote-ssh-pipe-argv (dir argv &key cd env (resolve t) stdin)
  "Return a local no-pty ssh argv running ARGV on the host of DIR.
The one builder of every process gascity runs on a remote host without
TRAMP: async reads and actions (`gascity-reader', dashboard-v3 §8.3 R3)
and long-lived streams (`gc events --follow', R4).  The result is
`beads-remote-ssh-pipe-argv' (BatchMode, keep-alives, TRAMP user, port
and host, one shell-quoted command) with `gascity-remote-ssh-options'
and gascity's own ControlPath spliced in after \"ssh\", plus \"-n\" and
\"-o ForwardX11=no\" (unless already present).  STDIN non-nil omits
\"-n\": the live event stream keeps the session's stdin open so a
host-side watcher notices, by EOF, that the stream was stopped.

The remote command is: `cd' to CD (a TRAMP or host-local directory
name; t means DIR), then the ENV assignments (an alist of (VAR .
VALUE)), then the PATH fragment, then exec ARGV.

With RESOLVE (the default) ARGV's program is resolved on the host
\(`gascity-remote-find-executable') and the PATH fragment is
`gascity-remote-path-assignment' — both cached per connection, but the
first call for a host is synchronous TRAMP I/O.  With RESOLVE nil
nothing touches the host: the program is used as given (a bare name is
found on the remote PATH) and the fragment is
`gascity-remote-pure-path-assignment' — the first-connection handshake
then happens entirely inside the ssh process.  Signals a `user-error'
for a non-ssh method or a multi-hop DIR."
  (let* ((cd (if (eq cd t) dir cd))
         (prefix
          (mapconcat
           #'identity
           (delq nil
                 (list (and cd (concat "cd " (shell-quote-argument
                                              (file-local-name cd))
                                       " &&"))
                       (and env
                            (mapconcat (lambda (pair)
                                         (concat (car pair) "="
                                                 (shell-quote-argument (cdr pair))))
                                       env " "))
                       (if resolve
                           (gascity-remote-path-assignment dir)
                         (gascity-remote-pure-path-assignment))))
           " "))
         (argv (beads-remote-ssh-pipe-argv
                dir
                (if resolve
                    (cons (gascity-remote-find-executable (car argv) dir) (cdr argv))
                  argv)
                (and (not (string-empty-p prefix)) prefix)))
         (options (append
                   ;; Always: stdin from /dev/null (a remote read of stdin
                   ;; can never wait on us) and no X11 forwarding — a
                   ;; `ForwardX11 yes' in ~/.ssh/config makes the master
                   ;; print xauth warnings (QA F8 root cause, item 3).
                   (unless (or stdin (member "-n" argv)) (list "-n"))
                   (unless (member "ForwardX11=no" argv)
                     (list "-o" "ForwardX11=no"))
                   gascity-remote-ssh-options
                   (unless (cl-some (lambda (o) (string-prefix-p "ControlPath" o))
                                    gascity-remote-ssh-options)
                     (list "-o" (concat "ControlPath="
                                        (gascity-remote-ssh-control-path)))))))
    (append (list (car argv)) options (cdr argv))))

;;; Finding executables on the host

(defvaralias 'gascity-remote--executable-cache 'beads-remote--cache
  "Per-connection resolution cache, shared with beads.el.
Executable resolutions and the PATH fragment are `beads-remote''s;
gascity stores its positive terminfo probes here too, under
\(REMOTE-PREFIX . (:terminfo . TERM)).")

(defun gascity-remote-forget-executables ()
  "Forget cached remote executable resolutions.
Called from `gascity-context-clear-cache' — the one user-facing cache
entry point — e.g. after a program moved on the host."
  (beads-remote-forget))

(defcustom gascity-remote-transport 'ssh
  "How asynchronous gc processes reach a remote city.
`ssh' (the default): for a single-hop ssh-family TRAMP city
\(`beads-remote-ssh-methods'), each async read and action runs as a LOCAL
`ssh -T' pipe process (`beads-remote-ssh-pipe-argv') — starting it never
blocks Emacs, stdout is byte-exact and stderr separate.  A tramp-sh
`make-process' instead sets up a remote shell synchronously, ~0.5s of
frozen main loop per spawn (seconds under contention).  ssh runs with
BatchMode (it never prompts: key or agent authentication, or a
ControlMaster, is required) plus `gascity-remote-ssh-options'.
`tramp': always use TRAMP's `make-process' (other methods always do).
For an ssh-family host (not in direct-async mode) gascity's own TRAMP
processes then run with `tramp-use-connection-share' bound to
`suppress' (`gascity-remote-call-unshared'): each gets its own ssh
connection, because a ControlMaster mux session writes into a pty and
blocks when it fills while TRAMP waits on another channel — the
seconds-long stalls and \"Process has died\" of a tramp-sh city
under load.  Direct-async processes (no pty) are left alone.

`tramp' is a fallback without the responsiveness guarantees of
dashboard-v3 §8.3 R9: every tramp-sh spawn still blocks Emacs while
TRAMP starts a remote shell (about 0.7 s each, several seconds when
many views refresh at once).  For an ssh-family host use `ssh' (the
default), or TRAMP direct-async (connection-local
`tramp-direct-async-process'), which starts processes without that
setup."
  :type '(choice (const :tag "Local ssh pipe" ssh)
                 (const :tag "TRAMP make-process" tramp))
  :group 'gascity)

(defvar tramp-use-connection-share)     ; tramp-sh
(declare-function tramp-direct-async-process-p "tramp")

(defun gascity-remote-connection-share (&optional dir)
  "Return the `tramp-use-connection-share' gascity spawns with in DIR.
`suppress' for an ssh-family TRAMP DIR (default `default-directory')
that is not in direct-async mode: every tramp-sh process then gets its
own ssh connection instead of a ControlMaster mux session with a pty,
which the master can block on while TRAMP waits on another channel
\(the F8 ControlMaster deadlock, qa/f8-root-cause.md).  Otherwise the
user's value, unchanged — direct-async processes have no pty."
  (let ((dir (or dir default-directory)))
    (if (and (file-remote-p dir)
             (member (file-remote-p dir 'method) beads-remote-ssh-methods)
             (not (let ((default-directory dir))
                    (ignore-errors (tramp-direct-async-process-p)))))
        'suppress
      tramp-use-connection-share)))

(defun gascity-remote-call-unshared (fn &rest args)
  "Call FN with ARGS, TRAMP connection sharing suppressed where needed.
FN is `make-process' or `process-file' as gascity calls them over TRAMP;
`tramp-use-connection-share' is bound per `gascity-remote-connection-share'."
  (let ((tramp-use-connection-share (gascity-remote-connection-share)))
    (apply fn args)))

(defun gascity-remote-ssh-transport-p (&optional dir)
  "Return non-nil when DIR's city is reached over the ssh pipe transport.
DIR (default `default-directory') must be a single-hop ssh-family
TRAMP name and `gascity-remote-transport' `ssh'.  Pure: name
dissection only."
  ;; Pure: dissect only — DIR may be a host-only scheduler key, which
  ;; `file-remote-p' would expand over TRAMP (`gascity-remote-prefix').
  (let ((dir (or dir default-directory)))
    (and (eq gascity-remote-transport 'ssh)
         (tramp-tramp-file-p dir)
         (when-let* ((vec (ignore-errors (tramp-dissect-file-name dir))))
           (and (member (tramp-file-name-method vec) beads-remote-ssh-methods)
                (not (tramp-file-name-hop vec)))))))

(defconst gascity-remote-prewarm-programs '("gc" "tmux" "infocmp" "bd")
  "Programs `gascity-remote-prewarm' resolves on an ssh-transport host.")

(defvar gascity-remote--prewarming (make-hash-table :test 'equal)
  "Hosts (TRAMP prefixes) with a prewarm in flight or done.")

(defun gascity-remote-prewarm (&optional dir)
  "Resolve gascity's programs on DIR's host in the background.
For an ssh-transport city: one local ssh pipe process
\(`gascity-remote-ssh-pipe-argv' with `:resolve nil' — no TRAMP I/O)
runs `command -v' for `gascity-remote-prewarm-programs' (and a bare
`gascity-executable') under the extended PATH and stores each absolute
answer in the per-connection executable cache shared with beads.el.
Once per host; a failed prewarm (exit, or the
`gascity-remote-sync-timeout' deadline) may run again later.  Returns
nil at once."
  (let* ((dir (or dir default-directory))
         (remote (gascity-remote-prefix dir)))
    (when (and (gascity-remote-ssh-transport-p dir)
               (not (gethash remote gascity-remote--prewarming)))
      (puthash remote t gascity-remote--prewarming)
      (let* ((names (delete-dups
                     (append gascity-remote-prewarm-programs
                             (and (stringp gascity-executable)
                                  (not (file-name-absolute-p gascity-executable))
                                  (list gascity-executable)))))
             (script (concat "for n in "
                             (mapconcat #'shell-quote-argument names " ")
                             "; do printf '%s %s\\n' \"$n\" "
                             "\"$(command -v \"$n\" 2>/dev/null)\"; done"))
             (chunks nil))
        (condition-case nil
            (let* ((default-directory temporary-file-directory)
                   (proc
                    (make-process
                     :name "gascity-prewarm" :noquery t
                     :command (gascity-remote-ssh-pipe-argv
                               dir (list "sh" "-c" script) :resolve nil)
                     :connection-type 'pipe :file-handler nil :stderr nil
                     :filter (lambda (_p chunk) (push chunk chunks))
                     :sentinel
                     (lambda (p _e)
                       (when (memq (process-status p) '(exit signal))
                         (if (not (eql (process-exit-status p) 0))
                             (remhash remote gascity-remote--prewarming)
                           (dolist (line (split-string
                                          (apply #'concat (nreverse chunks))
                                          "\n" t))
                             (let ((pair (split-string line " " t)))
                               (when (and (= (length pair) 2)
                                          (file-name-absolute-p (cadr pair)))
                                 (puthash (cons remote (car pair)) (cadr pair)
                                          beads-remote--cache))))))))))
              (gascity-timer-at (or gascity-remote-sync-timeout 30)
                                (lambda ()
                                  (when (process-live-p proc) (delete-process proc)))))
          (error (remhash remote gascity-remote--prewarming)))
        nil))))

(defun gascity-remote-find-executable (name &optional dir)
  "Return NAME resolved for DIR's host (default `default-directory').
Local DIRs and names with a directory pass through.  For an
ssh-transport city (`gascity-remote-ssh-transport-p') this NEVER does
TRAMP I/O: the answer is the per-connection cache, filled in the
background by `gascity-remote-prewarm' (started here on a miss); until
then the bare NAME comes back — gascity's own ssh commands find it on
the PATH they extend.  Other remote DIRs use
`beads-remote-find-executable' (TRAMP: `tramp-remote-path', then
`beads-remote-search-path', cached; synchronous on a miss).  An
unresolvable NAME comes back unchanged, so the launch fails with exit
127 and `gascity-remote-spawn-error-hint' names the setup paths."
  (let ((dir (or dir default-directory)))
    (if (and (gascity-remote-ssh-transport-p dir)
             (not (file-name-absolute-p name)))
        (let ((cached (gethash (cons (gascity-remote-prefix dir) name)
                               beads-remote--cache)))
          (if (stringp cached)
              cached
            (gascity-remote-prewarm dir)
            name))
      (beads-remote-find-executable name dir))))

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
                        (or (eq 0 (gascity-remote-call-unshared
                                   #'process-file
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
For an ssh-transport city the pure fragment
\(`gascity-remote-pure-path-assignment', no I/O); otherwise
`beads-remote-path-assignment': the `beads-remote-search-path' entries
expanded on the host over TRAMP.  Every remote
gc invocation site splices it before the command, so gc's own
children (git, dolt) resolve on the host too.  Nil for a local DIR."
  (if (gascity-remote-ssh-transport-p (or dir default-directory))
      ;; Pure for ssh-transport cities: every consumer splices the
      ;; fragment into a string a remote shell evaluates, which expands
      ;; the "$HOME" form — no TRAMP round trip for the remote home.
      (gascity-remote-pure-path-assignment)
    (beads-remote-path-assignment dir)))

;;; Spawn diagnostics

(defun gascity-remote-spawn-error-hint (program reason &optional dir var)
  "Return a message for failing to launch PROGRAM in DIR, naming the host.
REASON is the underlying error string.  For a local DIR (default
`default-directory') this is just \"Cannot run PROGRAM: REASON\"; for a
remote DIR the message names the host and the three setup paths: remote
programs resolve against `tramp-remote-path' (not the local variable
`exec-path'), which omits non-default profile directories unless
`tramp-own-remote-path' is added; `beads-remote-search-path' is the
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
                      " `beads-remote-search-path'%s")
              program remote reason
              (if var
                  (format ", or set %s connection-locally for this host" var)
                "")))))

(provide 'gascity-remote)
;;; gascity-remote.el ends here
