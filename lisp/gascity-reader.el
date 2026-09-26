;;; gascity-reader.el --- gc -> JSON bridge for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The data plane.  Every gascity view is a function of `gc ... --json'
;; output, and this module is the single place that runs `gc' and turns
;; its JSON into Elisp data.  It is the *only* read API: the typed,
;; named-command layer (`gascity-command-*!' bang functions, built on
;; `gascity-command'/`gascity-types') and the views both reach `gc'
;; through these primitives.  There is deliberately no second set of
;; per-subcommand sync accessors here — a `gc status' read is
;; `(gascity-command-status!)', a rig list is
;; `(gascity-command-rig-list!)', and so on.
;;
;; Layers, lowest first:
;;
;; - `gascity-reader-run'        run `gc' with a list of args, capturing
;;                               stdout/stderr/exit-code.  The one and
;;                               only `process-file' call site.
;; - `gascity-reader-parse-json' decode a JSON string to alist/vector.
;; - `gascity-reader-read'       run `gc ARGS... --json' and return the
;;                               parsed payload, signalling on failure.
;; - `gascity-reader-read-async' the make-process variant backing
;;                               `vui-use-async' (status dashboard, detail
;;                               views), with stderr captured separately.
;;
;; Both runners execute where `default-directory' points: on a remote
;; TRAMP directory they dispatch through the TRAMP process primitives
;; (`process-file', `make-process' with `:file-handler'), so every view
;; opened on a remote city reads THAT city's gc.  `gascity-executable'
;; is resolved under `with-connection-local-variables', so a per-host
;; absolute path can be set via connection-local profiles (see the
;; defcustom); a bare name is then resolved on the host by
;; `gascity-remote-find-executable' (`tramp-remote-path', falling back
;; to the Guix profile directories in `beads-remote-search-path'), so
;; a Guix host works with zero setup.  Remote commands run through the
;; /bin/sh wrapper of `gascity-reader--command', which also exports
;; those directories on PATH — gc spawns subprocesses (git for pack
;; imports, dolt), and they must resolve on the host too (gce-k5d).

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'files-x)                    ; with-connection-local-variables
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-remote)

;; Defined in gascity.el, which loads this module; guarded by `fboundp'
;; at every call site so this module is usable standalone.
(declare-function gascity--log "gascity")

;; Internal, but the exact predicate TRAMP's own `make-process' dispatch
;; consults; `fboundp'-guarded at the call site for older TRAMPs.
(declare-function tramp-dissect-file-name "tramp" (name &optional nodefault))
(declare-function tramp-file-name-hop "tramp" (vec))
(declare-function tramp-file-name-method "tramp" (vec))
(declare-function tramp-tramp-file-p "tramp" (name))
(declare-function tramp-direct-async-process-p "tramp" (&rest args))

;;; City targeting

(defvar gascity-reader-city-args-function nil
  "Function producing the leading city-targeting argv tokens, or nil.
When non-nil, a function of no arguments returning a list of strings
that both runners prepend to the argv of every gc invocation, or nil
to leave gc's own auto-discovery in place (the default).

The reader cannot `require' `gascity-context.el' (load-order cycle:
context requires reader), so the value is installed by `gascity.el'
after both modules load — normally `gascity-context-city-args'.  It
is called in the CALLING buffer, whose `default-directory' the view
factory pinned to the city root, before any buffer switch — the same
discipline the executable capture already follows — and must never
spawn gc: it runs on every UI path, timers and eldoc included.

The tokens LEAD the argv: gc parses the global flag before the
subcommand, and the error text built from the argv then names the
real invocation.

Subcommands whose leaf never accepts the flag (the `dolt' pack
commands, `gascity-reader-env-city-subcommands') are carved out below:
for those the tokens are withheld and the city identity travels by
environment instead (see `gascity-reader--city-env-pair').")

;; The gc-side classification is "any leaf under the dolt namespace":
;; `gc dolt <leaf>' resolves its city entirely through the environment
;; and cwd (the pack-command dispatch re-projects the canonical env),
;; and its argument parsing owns the tail blindly, so no --city can be
;; accepted without the gc-side change this works around.  A list of
;; first tokens covers every subcommand at once; widen it from real
;; rejections only.
(defconst gascity-reader-env-city-subcommands '("dolt")
  "Subcommands whose city targeting goes by environment, not `--city'.
`gc dolt …' subcommands are pack commands: the cobra leaf parses its
argument tail blindly, so the advertised global `--city' flag is
rejected with \"unknown flag: --city\" (gc#gc-6ahc2) even though the
help text lists it, and the pack script resolves its city from the
identity env (GC_CITY/GC_CITY_PATH — resolveExplicitCityPathEnv steps
4/5, above cwd) which the dispatch re-projects canonically.  For these
the reader withholds the `--city' tokens and overrides the identity
env instead — which also shields the read from an ambient
GC_CITY/GC_CITY_PATH projected for a different city (a session-launched
Emacs carries emacs-city's anchors, and an unanchored dolt read would
then hit the wrong machine-global dolt server).  See
`gascity-reader--city-env-pair'.")

;; Defined in gascity-context.el, which loads after this module; same
;; load-order-cycle guard as `gascity-context-city-args' below.
(declare-function gascity-context-city-root "gascity-context" (&optional dir))

(defun gascity-reader--city-env-pair (args)
  "Return the (VAR . HOST-LOCAL-VALUE) city env override for ARGS.
ARGS is the caller's argv (the subcommand leading).  When the
subcommand belongs to `gascity-reader-env-city-subcommands' and a city
root is pinned for the calling buffer, return (\"GC_CITY\" . ROOT):
env resolution is the very first explicit tier of gc's context
resolution, above both the ambient env and the cwd walk-up, so the
pack dispatch re-projects the canonical env (GC_CITY_PATH,
GC_PACK_STATE_DIR, the dolt port) for THIS city.  The value is the
host-local form (`file-local-name') — the consumer is the host-side
gc process.  Anything else returns nil and the invocation targets by
`--city' argv or gc's own discovery as before."
  (when (member (car args) gascity-reader-env-city-subcommands)
    (when-let* ((root (gascity-context-city-root)))
      (cons "GC_CITY" (file-local-name root)))))

(defun gascity-reader--city-env-overrides (args)
  "Return the env-city override list for ARGS, or nil.
`gascity-reader--city-env-pair' answers the targeting var; for a real
override the caller needs gc's full identity anchor set (GC_CITY,
GC_CITY_PATH, GC_CITY_RUNTIME_DIR): a spawned gc projects the city's
runtime env by APPENDING to the inherited environment, and on this
stack a duplicated variable resolves to the FIRST entry in the child —
so ambient anchors (a session-launched Emacs carries emacs-city's)
would shadow gc's own projection and the pack script would read the
wrong city's runtime dir.  Prepending the anchors here puts the view's
city first instead, healing the dispatch for exactly this read."
  (when-let* ((pair (gascity-reader--city-env-pair args)))
    (let ((root (cdr pair)))
      (list (cons "GC_CITY" root)
            (cons "GC_CITY_PATH" root)
            (cons "GC_CITY_RUNTIME_DIR"
                  (concat (directory-file-name root) "/.gc/runtime"))))))

(defconst gascity-reader-supervisor-subcommands '("cities")
  "The gc subcommands that act at supervisor scope, never on one city.
They take no `--city', so the reader neither adds the tokens nor walks
up for a city root to compute them — over TRAMP that walk is
synchronous I/O (the Cities view reads `gc cities' from a host's `/').")

(defun gascity-reader--city-args (&optional args)
  "Return the city-targeting argv tokens for the current buffer, or nil.
Calls `gascity-reader-city-args-function' — nil when unset or the
function answers nil, and never for a supervisor-scope ARGS
\(`gascity-reader-supervisor-subcommands').  Both runners call this in
the calling buffer before any buffer switch, next to the executable
capture."
  (unless (member (car args) gascity-reader-supervisor-subcommands)
    (let ((f gascity-reader-city-args-function))
      (and f (funcall f)))))

;;; Low-level invocation

(defun gascity-reader--command (executable args &optional stderr)
  "Return the argv running EXECUTABLE with ARGS where `default-directory' points.
Locally that is (EXECUTABLE . ARGS) unchanged.  On a remote directory
the command is wrapped as

  /bin/sh -c \"[PATH=…:$PATH ]exec \\\"$0\\\" \\\"$@\\\"[ 2>/dev/null]\"
  EXECUTABLE ARGS…

— the one remote shape for both runners.  The wrapper splices
`gascity-remote-path-assignment', so EXECUTABLE and every subprocess
it spawns (gc forks git for pack imports, dolt, …) resolve against the
profile directories — resolving gc itself to an absolute path is not
enough, its children inherit the process PATH (gce-k5d).  The
assignment must be evaluated by the remote shell, where $PATH expands
to whatever the process actually inherited: every TRAMP handler
forwards `process-environment' entries shell-quoted, so the env route
would deliver a literal $PATH and lose the inherited tail.
EXECUTABLE rides as $0, so exit codes, signals, and the remote
\"command not found\" 127/126 are exactly the unwrapped ones.

STDERR selects what the wrapper does with standard error on the host:

- nil: leave it to the caller's `process-file' destination.
- t (the async runner): `2>/dev/null' — separated ON the host,
  identically under tramp-sh and direct-async (gce-qke).
- a string DELIM (the sync runner): CAPTURE mode.  The command runs
  with stderr redirected to a host-side `mktemp' file; afterwards the
  wrapper prints a newline, DELIM, a newline, then that file, and exits
  with the command's own status — so ONE stdout stream carries both,
  and `gascity-reader--split-output' cuts it at the first
  \"\\nDELIM\\n\".  When `mktemp' fails the wrapper degrades to the
  discard form (no DELIM printed: the whole stream is stdout).  DELIM
  must be printable ASCII — control characters do not survive the
  tramp-sh pty (gce-m6k) — and unique per call.  This replaces the
  `(BUFFER FILE)' destination of `process-file', whose remote FILE
  costs a host-side temp file plus its readback and deletion: three
  extra channel round trips per synchronous read (\"Renaming
  /ssh:…/tramp.X to /tmp/gascity-stderr-Y\" in `*Messages*').

Reads `default-directory' and (via the assignment) possibly
connection-local variables — call it before any buffer switch, next to
the `gascity-remote-find-executable' capture."
  (if (not (file-remote-p default-directory))
      (cons executable args)
    (let* ((assignment (gascity-remote-path-assignment))
           (prefix (if assignment (concat assignment " ") "")))
      (append (list "/bin/sh" "-c"
                    (if (stringp stderr)
                        (concat "t=$(mktemp) || " prefix
                                "exec \"$0\" \"$@\" 2>/dev/null; "
                                prefix "\"$0\" \"$@\" 2>\"$t\"; rc=$?; "
                                "printf '\\n%s\\n' " stderr "; "
                                "cat \"$t\"; rm -f \"$t\"; exit $rc")
                      (concat prefix "exec \"$0\" \"$@\""
                              (and stderr " 2>/dev/null"))))
              (cons executable args)))))

(defun gascity-reader--stderr-delimiter ()
  "Return a fresh stderr delimiter for one capture-mode remote command.
Printable ASCII with a random 32-bit tag — a control character would
not survive the tramp-sh pty (gce-m6k), and a fixed token could appear
in gc's own output."
  (format "GASCITY-STDERR-%08x" (random (ash 1 32))))

(defun gascity-reader--split-output (output delimiter)
  "Split OUTPUT of a capture-mode command into (STDOUT . STDERR).
OUTPUT is the whole stream the wrapper of `gascity-reader--command'
wrote; DELIMITER the token it was given.  Cut at the first
\"\\nDELIMITER\\n\": before it is stdout, after it stderr.  With no
marker (the `mktemp' fallback ran, or the command exec'd away) the
whole OUTPUT is stdout and stderr is empty."
  (let* ((marker (concat "\n" delimiter "\n"))
         (at (string-search marker output)))
    (if at
        (cons (substring output 0 at)
              (substring output (+ at (length marker))))
      (cons output ""))))

(defun gascity-reader--run-ssh (args)
  "Run gc ARGS synchronously over the ssh pipe transport; return the plist.
The ssh-transport body of `gascity-reader-run': the same local pipe
process as the async readers (`gascity-reader--spawn-ssh', no TRAMP
I/O), waited for with `accept-process-output' until its sentinel
answers, under a deadline of `gascity-remote-sync-timeout' that deletes it —
a local process wait always returns, so the bound holds (TRAMP's
suspended `with-timeout' is never involved).  Signals
`gascity-remote-sync-timeout' on expiry and `gascity-command-error'
when ssh cannot be launched."
  (let* ((result nil)
         (proc (gascity-reader--spawn-ssh
                args (gascity-reader--city-env-overrides args)
                (lambda (r) (setq result r))))
         (secs gascity-remote-sync-timeout)
         (deadline (and (numberp secs) (> secs 0) (+ (float-time) secs))))
    ;; Not JUST-THIS-ONE: the result arrives through the sentinel (after
    ;; the stderr pipe drains), which a process-restricted wait does not
    ;; always run.
    (while (and (not result) proc
                (or (not deadline) (< (float-time) deadline)))
      ;; Once PROC has exited, wait on no process in particular: a wait
      ;; on a dead PROC can keep returning without running its pending
      ;; sentinel, and the result would never arrive (seen under load).
      (accept-process-output (and (process-live-p proc) proc) 0.05))
    (cond
     (result
      (if (plist-get result :exit-code)
          result
        (signal 'gascity-command-error
                (list (plist-get result :stderr)
                      :command (mapconcat #'identity (cons gascity-executable args) " ")
                      :exit-code nil :stdout "" :stderr (plist-get result :stderr)))))
     (t
      (when (process-live-p proc) (delete-process proc))
      (gascity-remote--timeout-signal secs)))))

(defun gascity-reader-run (args)
  "Run the `gc' executable with ARGS, a list of strings.
Return a plist (:exit-code CODE :stdout OUT :stderr ERR :executable
EXE), where CODE is the integer exit status and EXE the executable
actually invoked (the connection-local `gascity-executable' when one
applies).  This does not signal on a non-zero exit — callers inspect
:exit-code.  It signals
`gascity-command-error' only when the executable itself cannot be
launched (e.g. `gc' is not installed, or — on a remote
`default-directory' — not on `tramp-remote-path').

Runs where `default-directory' points.  Locally, stderr is captured
through a temp file handed to `process-file' as usual.  On a remote
TRAMP directory `process-file' dispatches through TRAMP and gc runs on
that host — and the temp-file route is NOT used there: a host-side
capture file (`make-nearby-temp-file', its readback, its deletion) is
three extra channel round trips per synchronous read, each a UI stall
on a slow link.  Instead the command runs in the capture mode of
`gascity-reader--command': stderr is diverted on the host and appended
to stdout behind a per-call delimiter (`gascity-reader--stderr-delimiter'),
the whole stream arrives in one `process-file', and
`gascity-reader--split-output' separates the two — one round trip, no
files.  `gascity-executable' is resolved under
`with-connection-local-variables', honouring a per-host
connection-local value; a bare name on a remote directory is then
resolved to an absolute host path by `gascity-remote-find-executable'
\(`tramp-remote-path', falling back to `beads-remote-search-path').
The remote wrapper also exports the search-path directories on PATH so
gc's own subprocesses (git, dolt) resolve too (gce-k5d).  An env-city
override (`gascity-reader--city-env-pair') is applied as a
`process-environment' entry: locally `make-process' copies the binding
at spawn; over TRAMP the dispatch emits the changed entry on the
remote command line (\"env GC_CITY=… …\"), so gc's pack-command city
resolution sees the view's city either way.

For an ssh-transport city (`gascity-remote-ssh-transport-p') the run
goes over a local ssh pipe instead (`gascity-reader--run-ssh'): no
TRAMP I/O, a deadline that always holds."
  (if (gascity-remote-ssh-transport-p)
      (gascity-reader--run-ssh args)
  (with-connection-local-variables
   ;; Bounded when remote (`gascity-remote-with-timeout'): the
   ;; executable resolution ahead of the spawn and the `process-file'
   ;; itself are the synchronous channel round trips a half-dead
   ;; connection stalls on, and this runner is reachable from
   ;; interactive paths (peek, transients, action verbs) that must
   ;; error out instead of hanging.  On timeout the connection is
   ;; drained and `gascity-remote-sync-timeout' — a `gascity-error'
   ;; child — propagates to the caller's existing handlers.
   (gascity-remote-with-timeout gascity-remote-sync-timeout
   ;; Capture the executable, command and env-city override HERE:
   ;; `with-connection-local-variables' applies a connection-local
   ;; value buffer-locally in the current buffer, so a read inside
   ;; `with-temp-buffer' below would silently fall back to the global
   ;; default; the env-city override answers from the same pinned
   ;; `default-directory' and must be captured before any switch too.
   (let* ((executable (gascity-remote-find-executable gascity-executable))
          (delimiter (and (file-remote-p default-directory)
                          (gascity-reader--stderr-delimiter)))
          (city-env (gascity-reader--city-env-overrides args))
          (command (gascity-reader--command executable args delimiter))
          (stderr-file (and (not delimiter)
                            (make-nearby-temp-file "gascity-stderr-")))
          result)
     (when (fboundp 'gascity--log)
       (gascity--log 'info "Running: %s %s"
                     executable (mapconcat #'identity args " ")))
     (unwind-protect
         (with-temp-buffer
           ;; Only the override entry goes through TRAMP's
           ;; "difference to the toplevel" filter — a plain literal
           ;; value survives shell quoting; PATH is left to the
           ;; remote wrapper's host-evaluated assignment.
           (let ((process-environment
                  (if city-env
                      (append (gascity-reader--env-entries city-env)
                              process-environment)
                    process-environment)))
             (let* ((exit-code
                     (condition-case err
                         (apply #'gascity-remote-call-unshared #'process-file (car command) nil
                                (list (current-buffer) stderr-file) nil
                                (cdr command))
                       (file-error
                        (signal 'gascity-command-error
                                (list (gascity-remote-spawn-error-hint
                                       executable
                                       (error-message-string err)
                                       nil 'gascity-executable)
                                      :command (mapconcat
                                                #'identity
                                                (cons executable args) " ")
                                      :exit-code nil :stdout "" :stderr "")))))
                    (output (if delimiter
                                (gascity-reader--split-output
                                 (buffer-string) delimiter)
                              (cons (buffer-string)
                                    (with-temp-buffer
                                      (insert-file-contents stderr-file)
                                      (buffer-string)))))
                    (stdout (car output))
                    (stderr (cdr output)))
               (when (fboundp 'gascity--log)
                 (gascity--log 'info "Exit code: %s" exit-code)
                 (gascity--log 'verbose "Stdout: %s" stdout))
               (setq result (list :exit-code exit-code :stdout stdout
                                  :stderr stderr :executable executable)))))
       (when (and stderr-file (file-exists-p stderr-file))
         (delete-file stderr-file))
       result))))))

(defun gascity-reader--env-entries (city-env)
  "Return CITY-ENV (a list of (VAR . VALUE)) as environment entries.
Order preserved: earlier entries win in `process-environment', and
the identity anchors must lead (see `gascity-reader--city-env-overrides')."
  (mapcar (lambda (pair) (format "%s=%s" (car pair) (cdr pair)))
          city-env))

(defun gascity-reader--run-with-env (args city-env)
  "Run `gascity-reader-run' on ARGS with CITY-ENV overrides, or nil.
CITY-ENV is a list of (VAR . VALUE) environment overrides prepended to
`process-environment'.  Nil passes through unchanged — the plain
runner is still the one call site every non-env read shares."
  (if (not city-env)
      (gascity-reader-run args)
    (let ((process-environment
           (append (gascity-reader--env-entries city-env)
                   process-environment)))
      (gascity-reader-run args))))

;;; JSON parsing

(defun gascity-reader-parse-json (string)
  "Parse STRING as JSON and return Elisp data.
JSON objects become alists keyed by symbols and arrays become
vectors.  Both `null' and `false' decode to nil, so ordinary Elisp
truth tests work directly on decoded booleans — convenient for a
porcelain that renders flags like \"running\" and \"suspended\".
Leading non-JSON content is skipped: on a remote directory the TRAMP
transport can prepend chatter to gc's stdout (an ssh client warning
such as \"Warning: No xauth data …\", a login banner) before the JSON
payload, so parsing starts at the first `{'/`[' instead of failing on
unrelated transport output.  Signals `gascity-json-parse-error' on
malformed input."
  (condition-case err
      ;; Native parser (dashboard-v3 QA F3: json.el's reader was most of
      ;; a 600-850 ms cockpit stall).  Same shape as before: objects as
      ;; symbol-keyed alists, arrays as vectors, null AND false as nil.
      ;; `json-parse-buffer' reads ONE value and ignores what follows,
      ;; as json.el did — trailing transport chatter stays harmless.
      (with-temp-buffer
        (insert string)
        (goto-char (point-min))
        (skip-chars-forward " \t\n\r")
        (unless (memq (char-after) '(?{ ?\[))
          (when (re-search-forward "[{\\[]" nil t)
            (goto-char (match-beginning 0))))
        (json-parse-buffer :object-type 'alist :array-type 'array
                           :null-object nil :false-object nil))
    (error
     (signal 'gascity-json-parse-error
             (list (format "Failed to parse gc JSON output: %s"
                           (error-message-string err))
                   :input string
                   :parse-error err)))))

;;; JSON Lines

(defun gascity-reader--parse-json-lines (output)
  "Decode OUTPUT as JSON Lines into (GOOD . BAD).
Each non-empty line is decoded independently, with the decoding of
`gascity-reader-parse-json' but the native parser; GOOD is the list of
decoded values in feed order, BAD the count of lines that failed to
decode.  A malformed line is a per-line decode-error marker (the BAD
count), never a whole-feed failure — a stream feed must survive one
bad line (plan S3).
Leading lines before the first `{'-starting line are transport chatter
\(an ssh client warning or login banner — the same hazard
`gascity-reader-parse-json' documents for single-payload output, which
TRAMP can prepend to gc's stdout) and are ignored, not counted bad.
Empty output decodes to (nil . 0)."
  (let* ((lines (split-string output "\n"))
         ;; Skip transport chatter: everything before the first line
         ;; that starts a JSON object (see `gascity-reader-parse-json').
         (start (cl-position-if
                 (lambda (line) (string-match-p "\\`[[:space:]]*{" line))
                 lines))
         (good nil)
         (bad 0))
    ;; No object line at all: pure transport chatter (or an empty
    ;; feed) — the single-payload path's "parse from the first `{'"
    ;; answer with nothing after it is no events and no errors.
    (when start
      (dolist (line (nthcdr start lines))
        (setq line (string-trim line))
        (unless (string-empty-p line)
          (condition-case nil
              ;; Native `json-parse-string', ~25x faster than json.el:
              ;; a day of `gc events' is 15k lines (dashboard-v3 §7.8).
              ;; Same decoding as `gascity-reader-parse-json'.
              (let ((decoded (json-parse-string line
                                                :object-type 'alist
                                                :array-type 'array
                                                :null-object nil
                                                :false-object nil)))
                ;; A JSONL DTO line is an object; a decoded scalar or
                ;; array (valid JSON, wrong shape) is a malformed EVENT
                ;; line — count it bad rather than crash the renderer.
                (if (consp decoded)
                    (push decoded good)
                  (cl-incf bad)))
            (json-error (cl-incf bad))))))
    (cons (nreverse good) bad)))

;;; Incremental JSON Lines

(defun gascity-reader--jsonl-feeder ()
  "Return a closure decoding JSON Lines incrementally, chunk by chunk.
Call it with each output CHUNK as it arrives: complete lines are
decoded at once (spreading a day of `gc events' — 13 MB — over the
process's output instead of one long stall in its sentinel).  Call it
with nil to finish: it returns (GOOD . BAD) exactly as
`gascity-reader--parse-json-lines' would for the whole output,
transport chatter before the first object line included."
  (let ((partial "") (good nil) (bad 0) (started nil))
    (cl-flet ((line (text)
                (let ((text (string-trim text)))
                  (when (and (not started) (string-prefix-p "{" text))
                    (setq started t))
                  (when (and started (not (string-empty-p text)))
                    (condition-case nil
                        (let ((decoded (json-parse-string text
                                                          :object-type 'alist
                                                          :array-type 'array
                                                          :null-object nil
                                                          :false-object nil)))
                          (if (consp decoded) (push decoded good) (cl-incf bad)))
                      (json-error (cl-incf bad)))))))
      (lambda (chunk)
        (if chunk
            (let ((start 0) end
                  (text (concat partial chunk)))
              (while (setq end (string-search "\n" text start))
                (line (substring text start end))
                (setq start (1+ end)))
              (setq partial (substring text start))
              nil)
          (line partial)
          (setq partial "")
          (cons (reverse good) bad))))))

;;; High-level reader

(defconst gascity-reader--generic-envelope-message
  "command failed; see stderr for diagnostics"
  "The gc sentinel envelope message.
It is the envelope's own text when the
actionable diagnostic went to stderr instead (plan decision D4).  A
specific stderr therefore outranks it in the failure message.")

(defconst gascity-reader-exit-9-hint
  "process killed (SIGKILL) — exit 9 is the signal status Emacs reports for a torn-down gc process, not an exit code gc defines: typically an auto-refresh superseded this read or the view unmounted while it was in flight (the successor tears the process down), occasionally an external kill (OOM, timeout); refresh to retry"
  "The characterization shipped for a bare exit 9.
See
`gascity-reader--failure-message').  Derived from the gc source census
\(git gascity: no `os.Exit(9)' anywhere — gc's own failures exit 1, or a
commandExitError code nothing sets to 9) and an Emacs reproduction:
`delete-process'/`kill-process' on a live async read SIGKILL it and its
sentinel then observes (signal . 9), which the failure branch renders as
\"exit 9\".  On a remote sync read the /bin/sh wrapper would report a
SIGKILLed gc as 137, so a raw 9 there still means the LOCAL process Emacs
spawned was killed (ssh/transport teardown, OOM).")

(defun gascity-reader--error-envelope-message (stdout)
  "Return gc's JSON error envelope message from STDOUT, or nil.
STDOUT is the standard output of a failed `gc' run.  When it parses as
an error envelope — an object with a top-level `message' or a nested
`error' object carrying `message' (the reproduced shape:
\n{\"ok\":false,\"error\":{\"code\":…,\"message\":…}}) — return that
message as a string, nil otherwise.  Every decoding accident degrades
to nil: garbage or empty output, a parse failure, a vector payload,
non-string or empty message values, an `error' value that is not an
object.  Parse failure of a *failure* output must never mask the
exit-code message the caller falls back to."
  (when (and (stringp stdout) (not (string-empty-p stdout)))
    (let ((payload (condition-case nil
                       (gascity-reader-parse-json stdout)
                     (error nil)))
          msg)
      (when (consp payload)     ; nil and vector payloads are not envelopes
        (setq msg (cdr (assq 'message payload)))
        (unless (and (stringp msg) (not (string-empty-p msg)))
          (let ((err (cdr (assq 'error payload))))
            (setq msg (and (consp err) (cdr (assq 'message err))))))
        (and (stringp msg) (not (string-empty-p msg)) msg)))))

(defun gascity-reader--failure-message (executable args exit-code stdout
                                                 stderr remote)
  "Return the error message for EXECUTABLE run with ARGS exiting EXIT-CODE.
On a remote directory a missing gc does not raise a spawn error —
TRAMP hands the command line to the remote shell, which reports
\"command not found\" on stderr and exits 127 (126 for a
non-executable).  When REMOTE (the remote identification captured at
spawn time, since a sentinel may fire with an unrelated
`default-directory') is non-nil and EXIT-CODE is one of those, surface
the remote setup hint (`gascity-remote-spawn-error-hint') with the
shell's own STDERR words as the reason.  Otherwise the text is
\"gc <args> failed: <reason> (exit N)\", with the reason picked by
informativeness: the JSON error envelope's message (STDOUT,
`gascity-reader--error-envelope-message') when present and not the
generic sentinel phrase, else trimmed non-empty STDERR (the envelope can
be generic while the actionable text went to stderr), else the envelope
message as-is, else — when neither carries anything — the exit code.
EXIT-CODE 9 — Emacs reports a SIGKILLed process by its signal number —
gets the characterized `gascity-reader-exit-9-hint' instead of the bare
exit code (a buffer must never show a bare \"failed (exit 9)\").
EXECUTABLE is captured at spawn time (it may be a connection-local
value)."
  (if (and remote (memq exit-code '(126 127)))
      (gascity-remote-spawn-error-hint
       executable
       (let ((s (and (stringp stderr) (string-trim stderr))))
         (if (and s (not (string-empty-p s))) s (format "exit %s" exit-code)))
       remote 'gascity-executable)
    (let* ((envelope (gascity-reader--error-envelope-message stdout))
           (err (and (stringp stderr) (string-trim stderr)))
           (reason (cond ((and envelope
                               (not (equal envelope
                                           gascity-reader--generic-envelope-message)))
                          envelope)
                         ((and err (not (string-empty-p err))) err)
                         (envelope envelope))))
      (cond (reason
             (format "gc %s failed: %s (exit %s)"
                     (mapconcat #'identity args " ") reason exit-code))
            ((eql exit-code 9)
             (format "gc %s failed (exit 9 — %s)"
                     (mapconcat #'identity args " ")
                     gascity-reader-exit-9-hint))
            (t
             (format "gc %s failed (exit %s)"
                     (mapconcat #'identity args " ") exit-code))))))

(defun gascity-reader--read-1 (args full-args &optional city-env)
  "Run `gc' with FULL-ARGS once and return the parsed JSON payload.
ARGS are the original tokens (for error messages), FULL-ARGS the argv
including `--json'.  CITY-ENV, when non-nil, is a (VAR . VALUE)
environment override (the env-city targeting) applied around the
spawn.  The single-attempt body of `gascity-reader-read', which
retries it on a remote parse error."
  (let* ((result (gascity-reader--run-with-env full-args city-env))
         (exit-code (plist-get result :exit-code))
         (stdout (plist-get result :stdout))
         (stderr (plist-get result :stderr))
         (executable (plist-get result :executable)))
    (unless (eql exit-code 0)
      (let ((envelope (gascity-reader--error-envelope-message stdout)))
        (signal 'gascity-command-error
                (list (gascity-reader--failure-message
                       executable args exit-code stdout stderr
                       (file-remote-p default-directory))
                      :command (mapconcat #'identity
                                          (cons executable full-args) " ")
                      :exit-code exit-code :stdout stdout :stderr stderr
                      ;; The envelope message, when stdout carried one —
                      ;; even the generic sentinel phrase — so callers can
                      ;; show the envelope text even when a specific stderr
                      ;; won the human-readable message.
                      :message envelope))))
    (gascity-reader-parse-json stdout)))

(defun gascity-reader-read (&rest args)
  "Run `gc ARGS... --json' and return the parsed JSON payload.
ARGS are the subcommand tokens and any flags; `--json' is appended
unless already present.  Signals `gascity-command-error' on a
non-zero exit and `gascity-json-parse-error' on malformed JSON.
A 127/126 exit on a remote directory — the remote shell's \"command
not found\" — signals with the remote setup hint (see
`gascity-reader--failure-message').

On a remote directory a parse error is retried once, after draining the
TRAMP channel (`gascity-remote-drain-connection'): the sync read shares
tramp-sh's connection channel with every other `process-file' user (the
terminal status-mirror's tmux probes above all), and a channel command
abandoned mid-flight by a quit leaves output behind that the next
command harvests as its own stdout — gc's \"JSON\" is then tmux chatter
\(\"Invalid number format\", gce-desync).  The channel self-heals after
one bad read, so a drained retry returns the real payload; a second
parse failure signals as usual — real malformed gc output is never
masked, and a local parse error (no shared channel) never retries.

When `gascity-reader-city-args-function' is installed (gascity.el wires
`gascity-context-city-args' into it), its tokens are prepended to ARGS
first: the read explicitly targets the calling buffer's pinned city,
and the error text below names that real argv
\(plans/sessions-list-city-targeting, D1/D2/D3).  Subcommands whose
leaves never accept the flag (the dolt pack commands) get the city by
environment instead — see `gascity-reader--city-env-pair'."
  ;; The city-targeting tokens are captured HERE, in the calling
  ;; buffer, before any buffer switch: `default-directory' is the
  ;; pinned city root, and the drain/retry wrapper's error messages
  ;; below are built from the prepended ARGS so they show the real
  ;; argv (plans/sessions-list-city-targeting, D1/D3).  The env-city
  ;; override is captured next to the tokens, answered from the same
  ;; directory.
  (let* (;; The env-city override is answered on the CALLER's argv — the
         ;; subcommand decides — before the tokens are prepended, because
         ;; a hit also withholds the tokens (the pack leaves reject
         ;; `--city'; same pinned `default-directory').
         (city-env (gascity-reader--city-env-overrides args))
         (args (if city-env
                   args
                 (append (gascity-reader--city-args args) args)))
         (full-args (if (member "--json" args)
                        args
                      (append args (list "--json")))))
    (if (not (file-remote-p default-directory))
        (gascity-reader--read-1 args full-args city-env)
      (condition-case nil
          (gascity-reader--read-1 args full-args city-env)
        (gascity-json-parse-error
         (when (fboundp 'gascity--log)
           (gascity--log 'error
                         "Stale TRAMP channel output for gc %s; draining and retrying"
                         (mapconcat #'identity args " ")))
         (gascity-remote-drain-connection)
         (gascity-reader--read-1 args full-args city-env))))))

;;; ssh pipe transport (dashboard-v3 §8.3 R3/R4, §8.5)

(defun gascity-reader--ssh-pipe-p (&optional dir)
  "Return non-nil when async gc for DIR runs over the ssh pipe transport."
  (gascity-remote-ssh-transport-p dir))

(defun gascity-reader--ssh-command (executable args city-env)
  "Return the local ssh argv running EXECUTABLE ARGS in `default-directory'.
Built by `gascity-remote-ssh-pipe-argv' without host resolution: cd to
the city directory, the CITY-ENV assignments, the pure PATH fragment,
exec — no TRAMP round trip, so the first-connection handshake happens
in the ssh process, never inside a command."
  (gascity-remote-ssh-pipe-argv default-directory (cons executable args)
                                :cd t :env city-env :resolve nil))

(defun gascity-reader--spawn-ssh (args city-env callback &optional feed)
  "Start gc ARGS over the ssh pipe transport; CALLBACK gets the result plist.
FEED, when non-nil, also receives every stdout chunk as it arrives.
ARGS already carry any city-targeting tokens; CITY-ENV the env-city
overrides.  CALLBACK receives (:exit-code CODE :stdout OUT :stderr ERR
:executable EXE) exactly once (CODE nil when ssh could not be
launched).  The command is built without any TRAMP round trip
\(`gascity-reader--ssh-command'), so nothing here blocks.  The process
is local — its sentinel does no TRAMP operation.  Returns
the process, or nil when none was started."
  ;; The executable is `gascity-executable' as configured (connection-
  ;; locally too): an absolute host path is used as is, a bare name is
  ;; found on the remote PATH the command extends — no TRAMP probe.
  (let* ((executable (with-connection-local-variables gascity-executable)))
    (when executable
      (let* ((command (gascity-reader--ssh-command executable args city-env))
             (default-directory temporary-file-directory)
             (out nil) (err nil)
             ;; Its OWN buffer: by default a pipe's buffer is named
             ;; after the process, so concurrent reads shared one
             ;; "gascity-gc-stderr" buffer — and the first to finish
             ;; killed it, with every other read's stderr pipe (QA L-1).
             (stderr-proc (make-pipe-process
                           :name "gascity-gc-stderr" :noquery t
                           :buffer (generate-new-buffer " *gascity-gc-stderr*")
                           :filter (lambda (_p chunk) (push chunk err)))))
        (when (fboundp 'gascity--log)
          (gascity--log 'info "Running over ssh: %s" (mapconcat #'identity command " ")))
        (condition-case e
            (make-process
             :name "gascity-gc" :command command :noquery t
             :connection-type 'pipe :file-handler nil
             :stderr stderr-proc
             :filter (lambda (_p chunk)
                       (push chunk out)
                       (when feed (funcall feed chunk)))
             :sentinel
             (lambda (proc _event)
               (when (memq (process-status proc) '(exit signal))
                 ;; Drain the stderr pipe (local; bounded).
                 (let ((n 20))
                   (while (and (> n 0) (process-live-p stderr-proc)
                               (accept-process-output stderr-proc 0.01 nil t))
                     (setq n (1- n))))
                 (gascity-reader--kill-pipe stderr-proc)
                 (funcall callback (list :exit-code (process-exit-status proc)
                                         :stdout (apply #'concat (nreverse out))
                                         :stderr (apply #'concat (reverse err))
                                         :executable executable)))))
          (error
           (gascity-reader--kill-pipe stderr-proc)
           (funcall callback (list :exit-code nil :stdout ""
                                   :stderr (format "Cannot run ssh: %s"
                                                   (error-message-string e))
                                   :executable executable))
           nil))))))

(defun gascity-reader--kill-pipe (proc)
  "Delete pipe process PROC and its own buffer.
The buffer outlives the process otherwise (QA #11).  Each pipe has a
buffer of its own (`gascity-reader--spawn-ssh'), so this never touches
another read's pipe (QA L-1)."
  (when (processp proc)
    (let ((buf (process-buffer proc)))
      (when (process-live-p proc) (delete-process proc))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;;; Asynchronous reader

(defvar gascity-reader-skip-dir-probe nil
  "Non-nil skips the up-front directory probe of `gascity-reader-read-async'.
The probe is one synchronous TRAMP round trip per async read (gce-q84:
a missing remote directory would otherwise wedge a channel forever).
The store (`gascity-store') binds this to t for a directory that has
already answered a read this session — the probe then costs nothing
on every later read of a known-good city (dashboard-v3 §8.5).")

(defun gascity-reader--remote-dir-absent-bounded-p ()
  "One bounded `file-directory-p' round trip (see the wrapper)."
  (condition-case nil
      (gascity-remote-with-timeout
          gascity-remote-sync-timeout
        (not (file-directory-p default-directory)))
    (gascity-remote-sync-timeout 'timed-out)
    (error nil)))

(defun gascity-reader--remote-dir-absent-p (&optional may-reconnect)
  "One bounded directory probe of `default-directory' (ga-eyw9).
Returns t when `file-directory-p' answers nil, the symbol `timed-out'
when the probe hit `gascity-remote-sync-timeout', and nil when the
directory exists or the probe ERRORED — an error must fall through to
the spawn, whose own failure carries the real reason; only a clean
negative is ever reported.  The round trip is bounded by
`gascity-remote-with-timeout' so a wedged channel degrades the tick
instead of freezing it.

Unless MAY-RECONNECT, `non-essential' is bound so the probe can never
make TRAMP establish a NEW connection.  Only the cache-flush retry
passes it: a manual refresh then may re-establish a dropped
connection, while a timer tick — which binds `non-essential' itself —
keeps its no-reconnect guarantee (the retry declines to override the
caller's binding)."
  (and (file-remote-p default-directory)
       (if may-reconnect
           (gascity-reader--remote-dir-absent-bounded-p)
         (let ((non-essential t))
           (gascity-reader--remote-dir-absent-bounded-p)))))

(defun gascity-reader--async-dir-probe ()
  "Verdict for the up-front async-spawn directory probe (ga-eyw9).
Returns `absent' only when TWO bounded probes
\(`gascity-reader--remote-dir-absent-p'), separated by a flush of
TRAMP's cached file properties (`gascity-remote-flush-file-cache'),
both say `default-directory' does not exist; `timed-out' when a probe
hit the sync-timeout bound; nil when the directory exists, no probe
was needed (a local directory), or the first probe's negative was
reversed by the retry.

The retry exists because a first \"absent\" can be SPURIOUS: a stale
or wedged TRAMP connection can misparse a channel command and cache a
negative file attribute, so a healthy remote city then reports \"no
such directory\" as ground truth on every auto-refresh tick (the
niri workspace-4 incident of 2026-09-23: seven identical errors over
~35s against a verified-intact city).  A retry that reverses the
verdict is logged, so recurring misparses stay visible in
`gascity--log'."
  (let ((probe (gascity-reader--remote-dir-absent-p)))
    (cond
     ((eq probe 'timed-out) 'timed-out)
     (probe
      ;; First probe said absent — possibly a cached-negative misparse.
      (gascity-remote-flush-file-cache default-directory)
      (let ((retry (gascity-reader--remote-dir-absent-p 'may-reconnect)))
        (cond
         ;; Two agreeing negatives: report absence as ground truth.
         ((eq retry t) 'absent)
         ;; The retry wedged the same way: a dead connection again.
         ((eq retry 'timed-out) 'timed-out)
         ;; Reversed: the flush cleared poisoned cache state — proceed
         ;; with the spawn.
         (t
          (when (fboundp 'gascity--log)
            (gascity--log
             'info
             "Directory probe reversed on retry after TRAMP cache flush\
(cached-negative state?): %s"
             default-directory))
          nil))))
     (t nil))))

(defun gascity-reader-read-async (args callback &optional errback &key lines)
  "Run `gc ARGS...' asynchronously and parse its output.
ARGS are the subcommand tokens and any flags (strings).

The default decodes the whole output as ONE JSON payload: `--json' is
appended unless already present, and on a clean exit CALLBACK is called
with the decoded payload (alist/vector).

With LINES non-nil the output is JSON Lines (one JSON value per line,
the shape `gc events' emits): `--json' is NOT appended (the JSONL
leaves emit lines natively), each non-empty line is decoded
independently, and CALLBACK receives a cons (GOOD . BAD) — GOOD the
list of decoded values in feed order, BAD the count of lines that
failed to decode.  A malformed line is a per-line decode-error marker
in the payload, never a whole-feed failure.

On any failure — the executable cannot be launched, a non-zero exit,
or (in single-payload mode) malformed JSON — ERRBACK, when non-nil, is
called with a human-readable error string; CALLBACK is not.

Standard error is separated so a stray warning on stderr never corrupts
the JSON parsed from stdout — but never via a string `:stderr': tramp-sh
happens to accept a file name there, while TRAMP's direct-async handler
\(`tramp-handle-make-process', enabled per connection through the
connection-local variable `tramp-direct-async-process') accepts only nil
or a buffer and signals `wrong-type-argument bufferp'.  Locally, stderr
is captured in a hidden scratch buffer (killed on exit — its content is
never read).  On a remote directory the separation happens ON the host
instead: the command is wrapped (`gascity-reader--command') as

  /bin/sh -c \"PATH=…:$PATH exec \\\"$0\\\" \\\"$@\\\" 2>/dev/null\"
  GC ARGS...

which behaves identically under tramp-sh and direct-async, and GC is
pre-resolved to an absolute host path (`gascity-remote-find-executable')
so resolution cannot differ between the handlers either (direct-async
resolves against the login shell's PATH, not `tramp-remote-path').  The
PATH assignment (`gascity-remote-path-assignment') prepends the
search-path profile directories for gc's own subprocesses — git, dolt —
which inherit the process PATH no matter how gc itself was resolved
\(gce-k5d).  A
`:stderr' BUFFER over tramp-sh would be backed by a remote named pipe
plus a reader process whose cleanup runs TRAMP operations from process
sentinels — under the dashboard's parallel loads those fire inside each
other's TRAMP calls and raise \"Forbidden reentrant call of Tramp\" —
and would not work at all on a host without mkfifo/mknod; the wrapper
sidesteps that whole class.  Under direct-async, though, the spawned
process is a fresh LOCAL login program (e.g. ssh) whose own stderr
chatter — host-key warnings, banners — would merge into the stdout pipe,
so exactly there a local scratch buffer is passed after all: the
direct-async handler hands `:stderr' to the local `make-process'
unchanged, plain local plumbing with no fifo involved.  Returns the
process object, or nil when it could not be started.  Designed to drive
`vui-use-async', whose returned process is auto-killed on key change or
unmount.

A remote directory that does not exist is detected up front and
reported through ERRBACK without spawning anything: no TRAMP
`make-process' handler signals a missing working directory — tramp-sh
sends \"cd DIR && exec gc …\" to a fresh channel shell, the failed cd
short-circuits the exec, and the interactive channel idles at its
prompt forever, so the sentinel never fires and every attempt leaks a
wedged channel process (gce-q84).  Locally the spawn itself signals
`file-missing', reaching ERRBACK through the launch-error handler
below.  A directory probe error (unreachable host, dead connection)
falls through to the spawn, whose own failure carries the real reason;
a clean negative is retried once past a TRAMP cache flush before it is
reported (`gascity-reader--async-dir-probe').

The city-targeting tokens (see `gascity-reader-city-args-function')
lead the argv here too, computed in the calling buffer before any
buffer switch — the sentinel's error messages close over the prepended
ARGS (D1/D2/D3).  Subcommands whose leaves never accept the flag (the
dolt pack commands) get the city by environment instead: an
env-city override entry (`gascity-reader--city-env-pair') is bound in
`process-environment' around the spawn — the TRAMP dispatch forwards
the changed entry to the remote command line (\"env GC_CITY=…\"),
and a local make-process copies the binding — so the read targets the
view's city either way.

Runs where `default-directory' points: `:file-handler t' dispatches
through TRAMP on a remote directory, so gc runs on that host
\(`gascity-executable' resolved connection-locally, as in
`gascity-reader-run').

Connection reuse note (W1, REQ-002): the default handler on an ssh
connection is tramp-sh, which multiplexes every async read over the ONE
pooled ssh connection — measured: N = 10 consecutive async reads
spawned one ssh process total and zero new host logins
\(see `gascity-remote.el''s commentary and the W1 summary).  gascity
never enables direct-async itself; it only keeps working when the user
turns it on, at the cost of a fresh ssh per read."
  ;; The up-front directory probe is bounded (`non-essential' +
  ;; `gascity-remote-with-timeout'): async reads are reachable from
  ;; auto-refresh timers, and this probe is the one synchronous TRAMP
  ;; round trip on that path (the cache-flush retry adds a second only
  ;; when the first answered "absent") — a half-dead connection must
  ;; degrade the view (errback, nil), not freeze the tick on a
  ;; reconnect.  An ordinary probe error (unreachable host) still falls
  ;; through to the spawn, whose own failure carries the real reason.  A
  ;; clean negative answer is retried once past a TRAMP cache flush
  ;; before it is believed (`gascity-reader--async-dir-probe').
  (if (gascity-reader--ssh-pipe-p)
      (gascity-reader--read-async-ssh args callback errback lines)
  (let ((probe (and (not gascity-reader-skip-dir-probe)
                    (gascity-reader--async-dir-probe))))
    (cond
     ((eq probe 'timed-out)
      (when (fboundp 'gascity--log)
        (gascity--log 'error
                      "Async gc not started: directory probe timed out: %s"
                      default-directory))
      (when errback
        (funcall errback
                 (format "gc %s failed: no such directory (probe timed out): %s"
                         (mapconcat #'identity args " ")
                         default-directory)))
      nil)
     ((eq probe 'absent)
      (progn
        (when (fboundp 'gascity--log)
          (gascity--log 'error "Async gc not started: no such directory: %s"
                        default-directory))
        (when errback
          (funcall errback (format "gc %s failed: no such directory: %s"
                                   (mapconcat #'identity args " ")
                                   default-directory)))
        nil))
     (t
      (with-connection-local-variables
     ;; `args' is shadowed with the city-targeting tokens prepended: the
     ;; sentinel's error text (which closes over this binding) then shows
     ;; the real argv, and `full-args' is built from it (D1).
     (let* (;; The env-city override is answered on the CALLER's argv —
            ;; the subcommand decides — before the tokens are prepended,
            ;; because a hit also withholds the tokens (the pack leaves
            ;; reject `--city'; same pinned `default-directory').
            (city-env (gascity-reader--city-env-overrides args))
            (args (if city-env
                       args
                     (append (gascity-reader--city-args args) args)))
            ;; JSONL leaves emit their lines natively; appending --json
            ;; there would be a rejected flag.
            (full-args (if (or lines (member "--json" args))
                           args
                         (append args (list "--json"))))
            (output nil)
            ;; JSON Lines decode as they arrive, not in the sentinel.
            (feed (and lines (gascity-reader--jsonl-feeder)))
            ;; Both captured now: the sentinel fires with whatever buffer
            ;; (and so `default-directory' and any connection-locally
            ;; applied `gascity-executable') happens to be current then.
            (remote (file-remote-p default-directory))
            ;; First contact with a host resolves gc there — synchronous
            ;; channel round trips, cached per connection afterwards; a
            ;; wedged connection must not freeze the caller (§8.5).
            (executable (gascity-reader--bounded-executable))
            ;; Remotely, stderr separation and the PATH export for gc's
            ;; subprocesses both happen on the host via the /bin/sh
            ;; wrapper — a string :stderr crashes direct-async, a buffer
            ;; is tramp-sh's fifo machinery (see the docstring).
            (command (gascity-reader--command executable full-args t))
            ;; Local runs capture the process's stderr; so do remote
            ;; direct-async runs, whose LOCAL login program (ssh) has
            ;; stderr chatter of its own — there TRAMP passes the buffer
            ;; to the local `make-process' as-is.  The tramp-sh path must
            ;; get nil.  `tramp-direct-async-process-p' is the very
            ;; predicate TRAMP's dispatch consults.
            (stderr-buffer (when (or (not remote)
                                     (and (fboundp 'tramp-direct-async-process-p)
                                          (tramp-direct-async-process-p)))
                             (generate-new-buffer " *gascity-gc-stderr*"))))
       (when (fboundp 'gascity--log)
         (gascity--log 'info "Running async: %s %s"
                       executable (mapconcat #'identity full-args " ")))
       (condition-case err
           (let ((process-environment
                  (if city-env
                      (append (gascity-reader--env-entries city-env)
                              process-environment)
                    process-environment)))
             (gascity-remote-call-unshared #'make-process
              :name "gascity-gc"
              :command command
              :noquery t
              :connection-type 'pipe
              :file-handler t
              :stderr stderr-buffer
              ;; Chunks are consed and joined once: repeated `concat'
              ;; is quadratic on a large payload (QA F3).
              :filter (lambda (_proc chunk)
                        (push chunk output)
                        (when feed (funcall feed chunk)))
              :sentinel
              (lambda (proc _event)
                (when (memq (process-status proc) '(exit signal))
                  (setq output (apply #'concat (nreverse output)))
                  (let ((code (process-exit-status proc)))
                    (unwind-protect
                        (cond
                         ((not (eql code 0))
                          (when (fboundp 'gascity--log)
                            (gascity--log 'error "Async gc exited %s: %s" code
                                          (mapconcat #'identity args " ")))
                          (when errback
                            ;; The same envelope-aware message builder as the
                            ;; sync path, fed with the accumulated output (and
                            ;; no stderr: it is not captured here) — a remote
                            ;; 127 still gets the setup hint via REMOTE.
                            (funcall errback
                                     (gascity-reader--failure-message
                                      executable args code output nil remote))))
                         (t
                          (condition-case perr
                              (let ((data (if lines
                                              (funcall feed nil)
                                            (gascity-reader-parse-json
                                             output))))
                                (funcall callback data))
                            (gascity-json-parse-error
                             (when errback
                               (funcall errback
                                        (error-message-string perr)))))))
                      (when (and (bufferp stderr-buffer)
                                 (buffer-live-p stderr-buffer))
                        (kill-buffer stderr-buffer))))))))
         (error
          (when (and (bufferp stderr-buffer) (buffer-live-p stderr-buffer))
            (kill-buffer stderr-buffer))
          (when errback
            (funcall errback (gascity-remote-spawn-error-hint
                              executable
                              (error-message-string err)
                              remote 'gascity-executable)))
          nil)))))))))

(defun gascity-reader--read-async-ssh (args callback errback lines)
  "The ssh-transport branch of `gascity-reader-read-async'.
ARGS, CALLBACK, ERRBACK and LINES as there.  No directory probe: a
missing directory fails the remote `cd' with an error exit instead of
wedging a TRAMP channel (gce-q84 cannot happen here)."
  (let* ((targeted (gascity-reader--targeted-args args))
         (city-env (car targeted))
         (args (cdr targeted))
         (full-args (if (or lines (member "--json" args))
                        args
                      (append args (list "--json"))))
         (remote (file-remote-p default-directory))
         (feed (and lines (gascity-reader--jsonl-feeder))))
    (gascity-reader--spawn-ssh
     full-args city-env
     (lambda (result)
       (let ((code (plist-get result :exit-code))
             (stdout (plist-get result :stdout))
             (stderr (plist-get result :stderr)))
         (cond
          ((null code)
           (when errback (funcall errback stderr)))
          ((not (eql code 0))
           (when errback
             (funcall errback
                      (gascity-reader--failure-message
                       (plist-get result :executable) args code stdout
                       stderr remote))))
          (t
           (condition-case perr
               (funcall callback
                        (if lines
                            (funcall feed nil)
                          (gascity-reader-parse-json stdout)))
             (gascity-json-parse-error
              (when errback (funcall errback (error-message-string perr)))))))))
     feed)))

;;; Asynchronous runner (actions)

(defun gascity-reader--bounded-executable ()
  "Return `gascity-executable' resolved for `default-directory', bounded.
The first resolution on a remote host is a chain of synchronous channel
round trips (`gascity-remote-find-executable', cached per connection
afterwards) — one of the explicit sync exceptions of dashboard-v3
§8.5, so it runs under `gascity-remote-with-timeout'.  Also primes the
per-connection PATH fragment (`gascity-remote-path-assignment') inside
the same bound, so the command builder that follows only reads the
cache."
  (gascity-remote-with-timeout gascity-remote-sync-timeout
    (prog1 (gascity-remote-find-executable gascity-executable)
      (gascity-remote-path-assignment))))

(defun gascity-reader--targeted-args (args)
  "Return (CITY-ENV . ARGV) — ARGS with the calling buffer's city targeting.
The env-city override (`gascity-reader--city-env-overrides') is
answered on the caller's ARGS first; when it fires the `--city' tokens
are withheld, otherwise they lead the argv — the same rule both reader
entry points and `gascity-command-execute' apply."
  (let ((city-env (gascity-reader--city-env-overrides args)))
    (cons city-env
          (if city-env args (append (gascity-reader--city-args args) args)))))

(defun gascity-reader-run-async (args callback)
  "Start `gc ARGS...' asynchronously; call CALLBACK with its result plist.
The non-blocking twin of `gascity-reader-run' for the mutating verbs
\(dashboard-v3 D9, §8.5): ARGS are passed through verbatim (no
`--json' is appended) behind the calling buffer's city-targeting tokens
\(`gascity-reader--targeted-args').  CALLBACK receives exactly once a
plist (:exit-code CODE :stdout OUT :stderr ERR :executable EXE); CODE
is nil when the process could not be launched, ERR then carrying the
reason.

Standard error is captured on the running host by the capture-mode
wrapper of `gascity-reader--command' — stdout, a random delimiter line,
then the stderr file — locally and remotely alike, so ONE output
stream carries both and no stderr pipe, fifo or remote temp file is
involved (the \"Forbidden reentrant call of Tramp\" class).  Under
direct-async the local login program's own chatter goes to a scratch
buffer that is discarded.  The sentinel only concatenates and splits
strings; it does no file operation.  Returns the process, or nil when
none was started (CALLBACK has then already been called)."
  (if (gascity-reader--ssh-pipe-p)
      (let ((targeted (gascity-reader--targeted-args args)))
        (gascity-reader--spawn-ssh (cdr targeted) (car targeted) callback))
  (with-connection-local-variables
   (let* ((targeted (gascity-reader--targeted-args args))
          (city-env (car targeted))
          (argv (cdr targeted))
          (remote (file-remote-p default-directory))
          (executable
           (condition-case err
               (gascity-reader--bounded-executable)
             (gascity-remote-sync-timeout
              (funcall callback
                       (list :exit-code nil :stdout ""
                             :stderr (error-message-string err)
                             :executable gascity-executable))
              nil)))
          (delimiter (gascity-reader--stderr-delimiter))
          (command (and executable
                        (if remote
                            (gascity-reader--command executable argv delimiter)
                          (gascity-reader--capture-command
                           executable argv delimiter))))
          (stderr-buffer (and executable remote
                              (fboundp 'tramp-direct-async-process-p)
                              (tramp-direct-async-process-p)
                              (generate-new-buffer " *gascity-gc-stderr*")))
          (output nil))
     (when executable
       (when (fboundp 'gascity--log)
         (gascity--log 'info "Running async action: %s %s"
                       executable (mapconcat #'identity argv " ")))
       (condition-case err
           (let ((process-environment
                  (if city-env
                      (append (gascity-reader--env-entries city-env)
                              process-environment)
                    process-environment)))
             (gascity-remote-call-unshared #'make-process
              :name "gascity-gc-action"
              :command command
              :noquery t
              :connection-type 'pipe
              :file-handler t
              :stderr stderr-buffer
              :filter (lambda (_proc chunk) (push chunk output))
              :sentinel
              (lambda (proc _event)
                (when (memq (process-status proc) '(exit signal))
                  (setq output (apply #'concat (nreverse output)))
                  (when (buffer-live-p stderr-buffer)
                    (kill-buffer stderr-buffer))
                  (let ((split (gascity-reader--split-output output delimiter)))
                    (funcall callback
                             (list :exit-code (process-exit-status proc)
                                   :stdout (car split)
                                   :stderr (cdr split)
                                   :executable executable)))))))
         (error
          (when (buffer-live-p stderr-buffer)
            (kill-buffer stderr-buffer))
          (funcall callback
                   (list :exit-code nil :stdout ""
                         :stderr (gascity-remote-spawn-error-hint
                                  executable (error-message-string err)
                                  remote 'gascity-executable)
                         :executable executable))
          nil)))))))

(defun gascity-reader--capture-command (executable args delimiter)
  "Return the LOCAL capture-mode argv running EXECUTABLE with ARGS.
The local counterpart of the remote capture wrapper in
`gascity-reader--command' (same /bin/sh script, no PATH assignment):
stdout, then \"\\nDELIMITER\\n\", then the command's stderr, exiting
with the command's own status.  DELIMITER separates the two streams."
  (append (list "/bin/sh" "-c"
                (concat "t=$(mktemp) || exec \"$0\" \"$@\" 2>/dev/null; "
                        "\"$0\" \"$@\" 2>\"$t\"; rc=$?; "
                        "printf '\\n%s\\n' " delimiter "; "
                        "cat \"$t\"; rm -f \"$t\"; exit $rc"))
          (cons executable args)))

;; Named per-subcommand reads are the `gascity-command-*!' bang
;; functions (see `gascity-command'/`gascity-types'); there is no
;; parallel set of `gascity-reader-*' accessors.

(provide 'gascity-reader)
;;; gascity-reader.el ends here
