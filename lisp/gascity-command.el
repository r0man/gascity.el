;;; gascity-command.el --- EIEIO command classes for Gas City -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The command layer.  Each `gc' subcommand is modelled as an EIEIO
;; class whose slots declare the CLI options; beads.el's `beads-meta'
;; engine infers the command line and (later phases) the transient menu
;; from that slot metadata.
;;
;; Class hierarchy:
;;
;;   gascity-command                 abstract base (machinery only)
;;     `- gascity-command-global-options   --verbose / --json
;;         `- gascity-command-status, gascity-command-rig-list, ...
;;
;; Define a command with `gascity-defcommand', which also generates a
;; NAME! convenience function that executes the command and returns the
;; parsed result:
;;
;;   (gascity-defcommand gascity-command-status (gascity-command-global-options)
;;     ()
;;     :documentation \"Show the Gas City town status.\")
;;
;;   (gascity-command-status!)   ;; => alist parsed from `gc status --json'
;;
;; Process execution is delegated to `gascity-reader' (the single gc
;; invocation site); this module wraps the result in a
;; `gascity-command-execution' object and parses it.

;;; Code:

(require 'eieio)
(require 'cl-lib)
(require 'files-x)       ; with-connection-local-variables
(require 'beads-meta)    ; slot-metadata engine + command-line builder
(require 'beads-command) ; bridge generics (beads-command-validate / -execute-interactive / -preview)
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-reader)

(declare-function gascity--log "gascity")

;;; ============================================================
;;; Command definition macro
;;; ============================================================

(defmacro gascity-defcommand (name superclasses slots &rest options)
  "Define a gascity command class NAME with a generated NAME! function.

NAME is the class symbol (e.g. `gascity-command-status').
SUPERCLASSES, SLOTS and OPTIONS are as for `defclass'.

In addition to the class, this defines a NAME! convenience function
that constructs the command from its arguments, executes it, and
returns the parsed result.

Custom keyword options (stripped before reaching `defclass'):

  :cli-command STR    Explicit CLI subcommand string.  When omitted,
                      the subcommand is derived from the class name by
                      `gascity-command-subcommand'.
  :global-section SYM Also generate a transient menu, including SYM as
                      its global-options section.  The prefix name is
                      derived by stripping \"-command-\" from NAME, and
                      the short docstring is the first sentence of
                      :documentation.

This is a thin wrapper over beads.el's reusable `beads-meta-defcommand'
engine, which performs the shared class/CLI/transient codegen (the same
engine `beads-defcommand' wraps).  gascity supplies only its
library-specific pieces: it forwards the caller's :global-section and
adds the NAME! bang function via :extra-forms.

When no :global-section (and no explicit :transient) is given it passes
:transient nil, so a plain command expands to just its class and NAME!
function — as before.  The engine would otherwise auto-generate a
transient whose derived prefix (NAME minus \"-command-\") would clobber
gascity's hand-written view commands such as `gascity-status' and
`gascity-rig-list'."
  (declare (indent 2))
  (let* ((gs-result (beads-meta-extract-option :global-section options))
         (global-section (car gs-result))
         (rest-options (cdr gs-result))
         (bang-fn (intern (concat (symbol-name name) "!"))))
    `(beads-meta-defcommand ,name ,superclasses ,slots
       :global-section ,global-section
       ,@(when (and (not global-section)
                    (not (plist-member rest-options :transient)))
           '(:transient nil))
       :extra-forms ((defun ,bang-fn (&rest args)
                       ,(format "Execute `%s' and return its parsed result.\n\nARGS are passed to the class constructor."
                                name)
                       (oref (gascity-command-execute (apply #',name args)) result)))
       ,@rest-options)))

;;; ============================================================
;;; Base classes
;;; ============================================================

(defclass gascity-command ()
  ()
  :abstract t
  :documentation "Abstract base class for all `gc' commands.
Concrete commands inherit from `gascity-command-global-options'.")

(defclass gascity-command-global-options (gascity-command)
  ((verbose
    :initarg :verbose
    :type boolean
    :initform nil
    :documentation "Enable verbose `gc' output."
    :long-option "verbose"
    :short-option "v"
    :option-type :boolean)
   (json
    :initarg :json
    :type boolean
    :initform t
    :documentation "Request machine-readable JSON output."
    :long-option "json"
    :option-type :boolean))
  :documentation "Global `gc' CLI flags shared by every command.
`--json' defaults on because gascity parses command output;
interactive/streaming commands set :json nil.")

(defclass gascity-command-action (gascity-command-global-options)
  ((json
    :initarg :json
    :type boolean
    :initform nil
    :documentation "Off by default for mutations.
Actions report success from gc's exit status (and a one-line summary of
its plain stdout); they do not parse a JSON payload, so `--json' — whose
support and shape vary across the mutating subcommands — stays off and
an exit-0 command with empty or JSONL output never reads as a failure."
    :long-option "json"
    :option-type :boolean))
  :abstract t
  :documentation "Base for mutating `gc' commands (suspend, nudge, sling, …).
Concrete actions inherit from this; `gascity-action' specializes
`gascity-command-execute-interactive' on it to run the command
synchronously and report the outcome in the echo area, rather than the
streaming `async-shell-command' backend used for read/long-running
commands.  `--json' is off by default (see the `json' slot); positional
and option slots are declared per concrete command.")

(defclass gascity-command-bd-action (gascity-command-action)
  ((store-directory
    :initarg :directory
    :initform nil
    ;; Slot name is `store-directory', not `directory': beads-meta reserves
    ;; `directory' as a *global* bd option (it is in
    ;; `beads-meta--global-option-slots'), so a slot literally named
    ;; `directory' is skipped by `beads-meta-build-command-line' and never
    ;; emitted.  Under a non-reserved name the builder emits it normally.
    ;; Short option only — no `:long-option' — so it renders as `-C <dir>'
    ;; (this base is a plain `defclass', which skips long-option inference,
    ;; so the slot name never back-fills a `--store-directory').  The
    ;; `:initarg' stays `:directory' so callers read naturally.  gc accepts
    ;; both `-C' and `--directory'.
    :short-option "C"
    :option-type :string
    :documentation "Store directory (-C), resolved from the bead id's prefix
via `gascity-beads--bead-path'.  Pins a `gc bd' write to the right rig's
database despite the shared Dolt server's working-directory misrouting
(the same hazard `gascity-beads--show-in-store' fixes for reads, gce-bhr).
Nil emits no flag, deferring to gc's own prefix/ambient routing."))
  :abstract t
  :documentation "Base for `gc bd' mutations (note, and later close/priority/…).
Adds the optional `-C'/`directory' store-routing slot to
`gascity-command-action'; concrete bead verbs add their positionals.
Callers resolve the directory once with `gascity-beads--bead-path' from
the subject bead id and pass it as `:directory'.")

(defclass gascity-command-execution ()
  ((command
    :initarg :command
    :type gascity-command
    :documentation "The command that produced this result.")
   (exit-code
    :initarg :exit-code
    :initform nil
    :documentation "Process exit status; 0 indicates success.")
   (stdout
    :initarg :stdout
    :initform nil
    :documentation "Captured standard output.")
   (stderr
    :initarg :stderr
    :initform nil
    :documentation "Captured standard error.")
   (result
    :initarg :result
    :initform nil
    :documentation "Parsed result: alist/vector for JSON, else stdout."))
  :documentation "Outcome of executing a `gascity-command'.")

;;; ============================================================
;;; Generic methods
;;; ============================================================

(cl-defgeneric gascity-command-execute (command)
  "Execute COMMAND and return a `gascity-command-execution' object.")

(cl-defgeneric gascity-command-line (command)
  "Return COMMAND's full command line as a list of strings.
The list starts with the executable.")

(cl-defgeneric gascity-command-validate (command)
  "Return an error string for COMMAND, or nil when it is valid.")

(cl-defgeneric gascity-command-subcommand (command)
  "Return the `gc' subcommand string for COMMAND, or nil.")

(cl-defgeneric gascity-command-parse (command execution)
  "Parse EXECUTION's output for COMMAND and return the result.")

(cl-defgeneric gascity-command-execute-interactive (command)
  "Execute COMMAND interactively, streaming its output to the user.")

(cl-defgeneric gascity-command-preview (command)
  "Show, without running, the command line COMMAND would execute.")

;;; ============================================================
;;; Bridge methods for beads-meta-generated transients
;;; ============================================================
;;
;; beads-meta-define-transient (emitted by `beads-meta-defcommand' when
;; gascity-defcommand forwards a :global-section) generates suffixes that
;; call the beads-command-* generics.  Delegate those to the
;; gascity-command-* methods so generated menus drive gascity commands.

(declare-function beads-command-validate "beads-command")
(declare-function beads-command-execute-interactive "beads-command")
(declare-function beads-command-preview "beads-command")

(cl-defmethod beads-command-validate ((command gascity-command))
  "Delegate validation of COMMAND to `gascity-command-validate'."
  (gascity-command-validate command))

(cl-defmethod beads-command-execute-interactive ((command gascity-command))
  "Delegate interactive execution of COMMAND to gascity."
  (gascity-command-execute-interactive command))

(cl-defmethod beads-command-preview ((command gascity-command))
  "Delegate preview of COMMAND to `gascity-command-preview'."
  (gascity-command-preview command))

;;; ============================================================
;;; Command-line construction
;;; ============================================================

(cl-defmethod gascity-command-line :around ((_command gascity-command))
  "Prepend the executable to the argument list built by the primary method.
`gascity-executable' is read under `with-connection-local-variables', so
a per-host value set via connection-local profiles governs previews and
interactive execution for a remote city just as it does the reader."
  (with-connection-local-variables
   (cons gascity-executable (cl-call-next-method))))

(cl-defmethod gascity-command-line ((command gascity-command))
  "Build COMMAND's argument list from its slot metadata.
Order: subcommand tokens, global flags, then the option/positional
arguments inferred by `beads-meta-build-command-line'."
  (let ((subcommand (gascity-command-subcommand command))
        (global-args (gascity-command--global-options command)))
    (if subcommand
        (append (split-string subcommand)
                global-args
                (beads-meta-build-command-line command))
      global-args)))

(cl-defmethod gascity-command-validate ((_command gascity-command))
  "Default: COMMAND is valid (return nil)."
  nil)

(defun gascity-command--slot (command slot)
  "Return COMMAND's SLOT value, or nil when COMMAND has no such slot.
SLOT is passed as a runtime value rather than a literal so the byte
compiler does not check it against a method's specializer class.  This
is how methods read slots — such as the macro-injected, class-allocated
`cli-command' — that are not statically declared on `gascity-command'."
  (and (slot-exists-p command slot)
       (slot-value command slot)))

(defun gascity-command--blank-p (command slot)
  "Return non-nil when COMMAND's SLOT is unbound, nil, or a blank string.
Used by the mutating commands' `gascity-command-validate' methods to
reject missing required positional arguments before `gc' is invoked."
  (let ((value (and (slot-boundp command slot) (slot-value command slot))))
    (or (null value)
        (and (stringp value) (string-empty-p (string-trim value))))))

(cl-defmethod gascity-command-subcommand ((command gascity-command))
  "Derive the `gc' subcommand string for COMMAND.
Honours a class-allocated `cli-command' slot (set via :cli-command in
`gascity-defcommand'); otherwise strips the `gascity-command-' prefix
from the class name and turns hyphens into spaces, e.g.
`gascity-command-rig-list' -> \"rig list\".  Returns nil for the
abstract `gascity-command' class itself."
  (let ((class-name (symbol-name (eieio-object-class command))))
    (unless (equal class-name "gascity-command")
      (or (gascity-command--slot command 'cli-command)
          (when (string-match "\\`gascity-command-\\(.+\\)\\'" class-name)
            (replace-regexp-in-string
             "-" " " (match-string 1 class-name)))))))

(cl-defmethod gascity-command-parse ((command gascity-command) execution)
  "Parse EXECUTION's stdout for COMMAND.
When the command requested JSON, decode it via
`gascity-reader-parse-json'; otherwise return the raw stdout string.
Slots are read with `slot-value' because the `json' slot lives on the
`gascity-command-global-options' subclass, not the abstract
specializer this method dispatches on."
  (let ((stdout (slot-value execution 'stdout)))
    (if (not (slot-value command 'json))
        stdout
      (gascity-reader-parse-json stdout))))

(cl-defmethod gascity-command-preview ((command gascity-command))
  "Echo and return the shell-quoted command line for COMMAND."
  (let ((cmd-string (mapconcat #'shell-quote-argument
                               (gascity-command-line command) " ")))
    (message "Command: %s" cmd-string)
    cmd-string))

(cl-defmethod gascity-command-execute-interactive ((command gascity-command))
  "Run COMMAND asynchronously, streaming output to a buffer.
A deliberately minimal P0 backend built on `async-shell-command';
richer vterm/eat/term backends arrive with `gascity-terminal'.

`async-shell-command' is TRAMP-aware: invoked from a buffer whose
`default-directory' is a remote city (every gascity view pins its
city's root), the command runs on that host, in its POSIX shell —
which is what the `shell-quote-argument' quoting here targets."
  (let* ((cmd-line (gascity-command-line command))
         (cmd-string (mapconcat #'shell-quote-argument cmd-line " "))
         (buffer-name (format "*gc %s*"
                              (or (gascity-command-subcommand command)
                                  "command"))))
    (async-shell-command cmd-string buffer-name)))

;;; ============================================================
;;; Execution
;;; ============================================================

(cl-defmethod gascity-command-execute ((command gascity-command))
  "Run COMMAND and return a `gascity-command-execution' object.
Validates COMMAND, runs it via `gascity-reader-run', then parses the
output.  Signals `gascity-validation-error' when validation fails and
`gascity-command-error' on a non-zero exit."
  (when-let ((error-msg (gascity-command-validate command)))
    (signal 'gascity-validation-error
            (list (format "Command validation failed: %s" error-msg)
                  :command command
                  :error error-msg)))
  (let* ((cmd-line (gascity-command-line command))
         (cmd-string (mapconcat #'shell-quote-argument cmd-line " "))
         ;; cmd-line starts with the executable; gascity-reader-run
         ;; re-adds it, so hand it only the argument tail.
         (run (gascity-reader-run (cdr cmd-line)))
         (exit-code (plist-get run :exit-code))
         (execution (gascity-command-execution
                     :command command
                     :exit-code exit-code
                     :stdout (plist-get run :stdout)
                     :stderr (plist-get run :stderr))))
    (if (eql exit-code 0)
        (progn
          (oset execution result (gascity-command-parse command execution))
          execution)
      (signal 'gascity-command-error
              (list (format "Command failed with exit code %s" exit-code)
                    :command cmd-string
                    :exit-code exit-code
                    :stdout (oref execution stdout)
                    :stderr (oref execution stderr))))))

;;; ============================================================
;;; Global-options helper
;;; ============================================================

(defconst gascity-command--global-option-slots '(verbose)
  "Slots emitted as global flags by `gascity-command--global-options'.
`json' is intentionally absent: it is not in beads-meta's own
global-slot exclusion list, so `beads-meta-build-command-line'
already emits it.  `verbose' is in that list (it shadows bd's own
--verbose) and so must be emitted here instead.")

(defun gascity-command--global-options (command)
  "Build the global-flag arguments for COMMAND from slot metadata."
  (let ((result nil)
        (class-name (eieio-object-class command)))
    (dolist (slot-name gascity-command--global-option-slots)
      (when (and (slot-exists-p command slot-name)
                 (slot-boundp command slot-name))
        (let* ((value (eieio-oref command slot-name))
               (long-opt (beads-meta-slot-property class-name slot-name
                                                   :long-option))
               (option-type (or (beads-meta-slot-property class-name slot-name
                                                          :option-type)
                                :string)))
          (when (and value long-opt)
            (pcase option-type
              (:boolean
               (push (concat "--" long-opt) result))
              (_
               (push (concat "--" long-opt) result)
               (push (if (stringp value) value (format "%s" value))
                     result)))))))
    (nreverse result)))

(provide 'gascity-command)
;;; gascity-command.el ends here
