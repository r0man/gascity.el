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
;; to the Guix profile directories in `gascity-remote-search-path'), so
;; a Guix host works with zero setup.

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
(declare-function tramp-direct-async-process-p "tramp" (&rest args))

;;; Low-level invocation

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

Runs where `default-directory' points: on a remote TRAMP directory,
`process-file' dispatches through TRAMP and gc runs on that host.  The
stderr capture file is then created host-side (`make-nearby-temp-file')
and its full name handed to `process-file' — TRAMP reduces a same-host
name to its local part itself; handing it the local part instead would
make TRAMP copy stderr back into a *local* file of that name, and the
readback of the remote name would find nothing.  `gascity-executable'
is resolved under `with-connection-local-variables', honouring a
per-host connection-local value; a bare name on a remote directory is
then resolved to an absolute host path by
`gascity-remote-find-executable' (`tramp-remote-path', falling back
to `gascity-remote-search-path')."
  (with-connection-local-variables
   ;; Capture the executable HERE: `with-connection-local-variables'
   ;; applies a connection-local value buffer-locally in the current
   ;; buffer, so a read inside `with-temp-buffer' below would silently
   ;; fall back to the global default.
   (let ((executable (gascity-remote-find-executable gascity-executable))
         (stderr-file (make-nearby-temp-file "gascity-stderr-")))
     (when (fboundp 'gascity--log)
       (gascity--log 'info "Running: %s %s"
                     executable (mapconcat #'identity args " ")))
     (unwind-protect
         (with-temp-buffer
           (let* ((exit-code
                   (condition-case err
                       (apply #'process-file executable nil
                              (list (current-buffer) stderr-file) nil args)
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
                  (stdout (buffer-string))
                  (stderr (with-temp-buffer
                            (insert-file-contents stderr-file)
                            (buffer-string))))
             (when (fboundp 'gascity--log)
               (gascity--log 'info "Exit code: %s" exit-code)
               (gascity--log 'verbose "Stdout: %s" stdout))
             (list :exit-code exit-code :stdout stdout :stderr stderr
                   :executable executable)))
       (when (file-exists-p stderr-file)
         (delete-file stderr-file))))))

;;; JSON parsing

(defun gascity-reader-parse-json (string)
  "Parse STRING as JSON and return Elisp data.
JSON objects become alists keyed by symbols and arrays become
vectors.  Both `null' and `false' decode to nil, so ordinary Elisp
truth tests work directly on decoded booleans — convenient for a
porcelain that renders flags like \"running\" and \"suspended\".
Signals `gascity-json-parse-error' on malformed input."
  (condition-case err
      (let ((json-object-type 'alist)
            (json-array-type 'vector)
            (json-key-type 'symbol)
            (json-null nil)
            (json-false nil))
        (json-read-from-string string))
    (error
     (signal 'gascity-json-parse-error
             (list (format "Failed to parse gc JSON output: %s"
                           (error-message-string err))
                   :input string
                   :parse-error err)))))

;;; High-level reader

(defun gascity-reader--exit-error-message (executable args exit-code stderr
                                                      remote)
  "Return the error message for EXECUTABLE run with ARGS exiting EXIT-CODE.
On a remote directory a missing gc does not raise a spawn error —
TRAMP hands the command line to the remote shell, which reports
\"command not found\" on stderr and exits 127 (126 for a
non-executable).  When REMOTE (the remote identification captured at
spawn time, since a sentinel may fire with an unrelated
`default-directory') is non-nil and EXIT-CODE is one of those, surface
the remote setup hint (`gascity-remote-spawn-error-hint') with the
shell's own STDERR words as the reason; otherwise the plain
\"gc … failed (exit N)\" message.  EXECUTABLE is likewise captured at
spawn time (it may be a connection-local value)."
  (if (and remote (memq exit-code '(126 127)))
      (gascity-remote-spawn-error-hint
       executable
       (let ((s (and (stringp stderr) (string-trim stderr))))
         (if (and s (not (string-empty-p s))) s (format "exit %s" exit-code)))
       remote 'gascity-executable)
    (format "gc %s failed (exit %s)"
            (mapconcat #'identity args " ") exit-code)))

(defun gascity-reader-read (&rest args)
  "Run `gc ARGS... --json' and return the parsed JSON payload.
ARGS are the subcommand tokens and any flags; `--json' is appended
unless already present.  Signals `gascity-command-error' on a
non-zero exit and `gascity-json-parse-error' on malformed JSON.
A 127/126 exit on a remote directory — the remote shell's \"command
not found\" — signals with the remote setup hint (see
`gascity-reader--exit-error-message')."
  (let* ((full-args (if (member "--json" args)
                        args
                      (append args (list "--json"))))
         (result (gascity-reader-run full-args))
         (exit-code (plist-get result :exit-code))
         (stdout (plist-get result :stdout))
         (stderr (plist-get result :stderr))
         (executable (plist-get result :executable)))
    (unless (eql exit-code 0)
      (signal 'gascity-command-error
              (list (gascity-reader--exit-error-message
                     executable args exit-code stderr
                     (file-remote-p default-directory))
                    :command (mapconcat #'identity
                                        (cons executable full-args) " ")
                    :exit-code exit-code :stdout stdout :stderr stderr)))
    (gascity-reader-parse-json stdout)))

;;; Asynchronous reader

(defun gascity-reader-read-async (args callback &optional errback)
  "Run `gc ARGS... --json' asynchronously and parse its output.
ARGS are the subcommand tokens and any flags (strings); `--json' is
appended unless already present.

On a clean exit CALLBACK is called with the decoded payload
\(alist/vector).  On any failure — the executable cannot be launched, a
non-zero exit, or malformed JSON — ERRBACK, when non-nil, is called with
a human-readable error string; CALLBACK is not.

Standard error is separated so a stray warning on stderr never corrupts
the JSON parsed from stdout — but never via a string `:stderr': tramp-sh
happens to accept a file name there, while TRAMP's direct-async handler
\(`tramp-handle-make-process', enabled per connection through the
connection-local variable `tramp-direct-async-process') accepts only nil
or a buffer and signals `wrong-type-argument bufferp'.  Locally, stderr
is captured in a hidden scratch buffer (killed on exit — its content is
never read).  On a remote directory the separation happens ON the host
instead: the command is wrapped as

  /bin/sh -c \"exec \\\"$0\\\" \\\"$@\\\" 2>/dev/null\" GC ARGS...

which behaves identically under tramp-sh and direct-async, and GC is
pre-resolved to an absolute host path (`gascity-remote-find-executable')
so resolution cannot differ between the handlers either (direct-async
resolves against the login shell's PATH, not `tramp-remote-path').  A
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

Runs where `default-directory' points: `:file-handler t' dispatches
through TRAMP on a remote directory, so gc runs on that host
\(`gascity-executable' resolved connection-locally, as in
`gascity-reader-run')."
  (with-connection-local-variables
   (let* ((full-args (if (member "--json" args)
                         args
                       (append args (list "--json"))))
          (output "")
          ;; Both captured now: the sentinel fires with whatever buffer
          ;; (and so `default-directory' and any connection-locally
          ;; applied `gascity-executable') happens to be current then.
          (remote (file-remote-p default-directory))
          (executable (gascity-remote-find-executable gascity-executable))
          ;; Remotely, stderr separation happens on the host via this
          ;; wrapper — a string :stderr crashes direct-async, a buffer
          ;; is tramp-sh's fifo machinery (see the docstring).
          (command (if remote
                       (append
                        (list "/bin/sh" "-c" "exec \"$0\" \"$@\" 2>/dev/null")
                        (cons executable full-args))
                     (cons executable full-args)))
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
         (make-process
          :name "gascity-gc"
          :command command
          :noquery t
          :connection-type 'pipe
          :file-handler t
          :stderr stderr-buffer
          :filter (lambda (_proc chunk) (setq output (concat output chunk)))
          :sentinel
          (lambda (proc _event)
            (when (memq (process-status proc) '(exit signal))
              (let ((code (process-exit-status proc)))
                (unwind-protect
                    (cond
                     ((not (eql code 0))
                      (when (fboundp 'gascity--log)
                        (gascity--log 'error "Async gc exited %s: %s" code
                                      (mapconcat #'identity args " ")))
                      (when errback
                        ;; Stderr is not captured here; a remote 127
                        ;; still gets the setup hint, with the exit
                        ;; code as the reason.
                        (funcall errback
                                 (gascity-reader--exit-error-message
                                  executable args code nil remote))))
                     (t
                      (condition-case perr
                          (let ((data (gascity-reader-parse-json output)))
                            (funcall callback data))
                        (gascity-json-parse-error
                         (when errback
                           (funcall errback
                                    (error-message-string perr)))))))
                  (when (and (bufferp stderr-buffer)
                             (buffer-live-p stderr-buffer))
                    (kill-buffer stderr-buffer)))))))
       (error
        (when (and (bufferp stderr-buffer) (buffer-live-p stderr-buffer))
          (kill-buffer stderr-buffer))
        (when errback
          (funcall errback (gascity-remote-spawn-error-hint
                            executable
                            (error-message-string err)
                            remote 'gascity-executable)))
        nil)))))

;; Named per-subcommand reads are the `gascity-command-*!' bang
;; functions (see `gascity-command'/`gascity-types'); there is no
;; parallel set of `gascity-reader-*' accessors.

(provide 'gascity-reader)
;;; gascity-reader.el ends here
