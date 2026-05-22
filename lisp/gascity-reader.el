;;; gascity-reader.el --- gc -> JSON bridge for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The data plane.  Every gascity view is a function of `gc ... --json'
;; output, and this module is the single place that runs `gc' and turns
;; its JSON into Elisp data.
;;
;; Layers, lowest first:
;;
;; - `gascity-reader-run'        run `gc' with a list of args, capturing
;;                               stdout/stderr/exit-code.  The one and
;;                               only `process-file' call site.
;; - `gascity-reader-parse-json' decode a JSON string to alist/vector.
;; - `gascity-reader-read'       run `gc ARGS... --json' and return the
;;                               parsed payload, signalling on failure.
;; - typed accessors             `gascity-reader-status', `-rigs',
;;                               `-sessions', `-convoys', ... — each a
;;                               thin wrapper returning decoded data.

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

;;; Typed accessors

(defun gascity-reader-status ()
  "Return `gc status' as an alist."
  (gascity-reader-read "status"))

(defun gascity-reader-rigs ()
  "Return the rigs registered in the city as a vector of alists."
  (alist-get 'rigs (gascity-reader-read "rig" "list")))

(defun gascity-reader-sessions ()
  "Return the city's sessions as a vector of alists."
  (alist-get 'sessions (gascity-reader-read "session" "list")))

(defun gascity-reader-convoys ()
  "Return the city's convoys as a vector of alists."
  (alist-get 'convoys (gascity-reader-read "convoy" "list")))

(provide 'gascity-reader)
;;; gascity-reader.el ends here
