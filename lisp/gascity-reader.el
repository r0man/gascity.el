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

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'gascity-custom)
(require 'gascity-error)

;; Defined in gascity.el, which loads this module; guarded by `fboundp'
;; at every call site so this module is usable standalone.
(declare-function gascity--log "gascity")

;;; Low-level invocation

(defun gascity-reader-run (args)
  "Run the `gc' executable with ARGS, a list of strings.
Return a plist (:exit-code CODE :stdout OUT :stderr ERR), where
CODE is the integer exit status.  This does not signal on a
non-zero exit — callers inspect :exit-code.  It signals
`gascity-command-error' only when the executable itself cannot be
launched (e.g. `gc' is not installed)."
  (let ((stderr-file (make-temp-file "gascity-stderr-")))
    (when (fboundp 'gascity--log)
      (gascity--log 'info "Running: %s %s"
                    gascity-executable (mapconcat #'identity args " ")))
    (unwind-protect
        (with-temp-buffer
          (let* ((exit-code
                  (condition-case err
                      (apply #'process-file gascity-executable nil
                             (list (current-buffer) stderr-file) nil args)
                    (file-error
                     (signal 'gascity-command-error
                             (list (format "Cannot run %s: %s"
                                           gascity-executable
                                           (error-message-string err))
                                   :command (mapconcat
                                             #'identity
                                             (cons gascity-executable args) " ")
                                   :exit-code nil :stdout "" :stderr "")))))
                 (stdout (buffer-string))
                 (stderr (with-temp-buffer
                           (insert-file-contents stderr-file)
                           (buffer-string))))
            (when (fboundp 'gascity--log)
              (gascity--log 'info "Exit code: %s" exit-code)
              (gascity--log 'verbose "Stdout: %s" stdout))
            (list :exit-code exit-code :stdout stdout :stderr stderr)))
      (when (file-exists-p stderr-file)
        (delete-file stderr-file)))))

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

(defun gascity-reader-read (&rest args)
  "Run `gc ARGS... --json' and return the parsed JSON payload.
ARGS are the subcommand tokens and any flags; `--json' is appended
unless already present.  Signals `gascity-command-error' on a
non-zero exit and `gascity-json-parse-error' on malformed JSON."
  (let* ((full-args (if (member "--json" args)
                        args
                      (append args (list "--json"))))
         (result (gascity-reader-run full-args))
         (exit-code (plist-get result :exit-code))
         (stdout (plist-get result :stdout))
         (stderr (plist-get result :stderr)))
    (unless (eql exit-code 0)
      (signal 'gascity-command-error
              (list (format "gc %s failed (exit %s)"
                            (mapconcat #'identity args " ") exit-code)
                    :command (mapconcat #'identity
                                        (cons gascity-executable full-args) " ")
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

Standard error is captured separately so a stray warning on stderr never
corrupts the JSON parsed from stdout.  Returns the process object, or
nil when it could not be started.  Designed to drive `vui-use-async',
whose returned process is auto-killed on key change or unmount."
  (let* ((full-args (if (member "--json" args)
                        args
                      (append args (list "--json"))))
         (output "")
         (stderr-buffer (generate-new-buffer " *gascity-gc-stderr*")))
    (when (fboundp 'gascity--log)
      (gascity--log 'info "Running async: %s %s"
                    gascity-executable (mapconcat #'identity full-args " ")))
    (condition-case err
        (make-process
         :name "gascity-gc"
         :command (cons gascity-executable full-args)
         :noquery t
         :connection-type 'pipe
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
                       (funcall errback
                                (format "gc %s failed (exit %s)"
                                        (mapconcat #'identity args " ") code))))
                    (t
                     (condition-case perr
                         (let ((data (gascity-reader-parse-json output)))
                           (funcall callback data))
                       (gascity-json-parse-error
                        (when errback
                          (funcall errback (error-message-string perr)))))))
                 (when (buffer-live-p stderr-buffer)
                   (kill-buffer stderr-buffer)))))))
      (error
       (when (buffer-live-p stderr-buffer)
         (kill-buffer stderr-buffer))
       (when errback
         (funcall errback (format "Cannot run %s: %s"
                                  gascity-executable
                                  (error-message-string err))))
       nil))))

;; Named per-subcommand reads are the `gascity-command-*!' bang
;; functions (see `gascity-command'/`gascity-types'); there is no
;; parallel set of `gascity-reader-*' accessors.

(provide 'gascity-reader)
;;; gascity-reader.el ends here
