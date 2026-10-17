;;; generate-tables.el --- Generate the manual's drift-gated tables -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Plan D4 (REQ-014): the manual embeds three generated Texinfo tables,
;; `doc/generated/keys.texi', `doc/generated/commands.texi' and
;; `doc/generated/options.texi'.  All are *committed* artifacts: a clean
;; checkout builds the manual from them, and a normal `make' never
;; rewrites them.  This script regenerates them into a caller-supplied
;; directory; the Makefile targets are
;;
;;   make regen-doc-tables   -- rewrite the tracked includes
;;   make check-doc-drift    -- regenerate into a temp dir and diff
;;
;; Because the drift check is a plain `diff' against the tracked files,
;; it needs no git and works inside `make distcheck'.
;;
;; The key table is the *effective* binding of every contract key in
;; every view: `keymap-lookup' returns the local-over-inherited command,
;; so a parent-map redefinition changes the generated output.  Its
;; semantic guard is `lisp/test/gascity-key-registry-test.el' (F1/F4);
;; the view and key lists below are derived from that test's registry,
;; so a new view or contract key is picked up automatically.
;;
;; The command table enumerates every concrete `gascity-command' class
;; (via `gascity-defcommand') and reads the live `gascity-dispatch'
;; transient layout, so a renamed subcommand, a changed docstring or a
;; rebound dispatch key all show up as drift.
;;
;; The option table enumerates every `gascity-*' user option (`defcustom')
;; with its standard default and its type.  The minor modes and hooks
;; `define-minor-mode' also makes customizable are excluded, so the table
;; is the option surface; a missing or complex `:type' is rendered as a
;; deterministic fallback string (plan-review O3).
;;
;; Usage (the Makefile does this):
;;
;;   emacs --batch -Q -L lisp -L lisp/test -l doc/generate-tables.el OUTDIR
;;
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'cl-lib)
(require 'gascity)
;; The effective-key registry (F1/F4/F11) is the single source of truth
;; for which views exist and which keys are rendered.  It is a pure
;; `defconst' file: loading it registers its ERT tests but runs none, so
;; the generator stays a deterministic batch script.
(require 'gascity-key-registry-test)

(defconst gascity-generate-tables--views
  (mapcar (lambda (view) (list (nth 0 view) (nth 1 view)))
          gascity-key-registry--views)
  "Every view as (NAME MAP), derived from `gascity-key-registry--views'.")

(defconst gascity-generate-tables--extra-keys
  '("S")
  "Rendered keys the navigation registry does not model (the sling key).")

(defconst gascity-generate-tables--keys
  (delete-dups
   (append gascity-key-registry--contract
           gascity-key-registry--vui-contract
           (mapcar (lambda (row) (concat "a " (car row)))
                   gascity-key-registry--namespaced-verbs)
           gascity-key-registry--forbidden
           (mapcar #'car gascity-key-registry--agent-only-verbs)
           gascity-generate-tables--extra-keys))
  "The keys rendered per view, derived from the key registry:
`--contract', `--vui-contract', the `a' namespacing (F1), the reserved
keys, the agent-only aliases and the extra rendered keys.")

(defconst gascity-generate-tables--header
  ;; The comment header every generated file starts with.  Kept here so
  ;; both outputs stay recognisable as tracked generated artifacts.
  '("@c This tracked include is the committed artifact the manual builds"
    "@c from.  It is produced by doc/generate-tables.el and refreshed with"
    "@c `make regen-doc-tables'; `make check-doc-drift' fails when it no"
    "@c longer matches the live %s.  Do not edit by hand."
    "@c"
    "@c SPDX-License-Identifier: GPL-3.0-or-later")
  "Format lines of the generated-file header comment; %s names the source.")

;;; Texinfo helpers

(defun gascity-generate-tables--one-line (text)
  "Return TEXT's first trimmed line, or the empty string."
  (if (or (null text) (not (stringp text)))
      ""
    (string-trim (car (split-string text "\n")))))

(defun gascity-generate-tables--escape (text)
  "Escape TEXT for Texinfo and collapse it to one line."
  (let ((trimmed (gascity-generate-tables--one-line text)))
    (setq trimmed (replace-regexp-in-string "@" "@@" trimmed))
    (setq trimmed (replace-regexp-in-string "{" "@{" trimmed))
    (setq trimmed (replace-regexp-in-string "}" "@}" trimmed))
    trimmed))

(defun gascity-generate-tables--command (binding)
  "Return `(NAME . DOC)' for a keymap BINDING, normalizing lambdas.
An integer BINDING is a `lookup-key' partial-prefix result, not a
command, so it is skipped."
  (cond
   ((null binding) nil)
   ((integerp binding) nil)
   ((and (consp binding) (eq (car binding) 'lambda))
    (cons "lambda" ""))
   ((symbolp binding)
    (cons (symbol-name binding)
          (gascity-generate-tables--one-line
           (ignore-errors (documentation binding)))))
   (t (cons "keymap" ""))))

(defun gascity-generate-tables--header-lines (kind)
  "Return the generated header comment lines for KIND."
  (mapcar (lambda (line) (format line kind))
          gascity-generate-tables--header))

;;; keys.texi

(defun gascity-generate-tables--keys-content ()
  "Return the body of `doc/generated/keys.texi' as a string."
  (with-temp-buffer
    (insert "@node Effective Key Bindings\n")
    (insert "@section Effective Key Bindings\n")
    (insert "@cindex key bindings, generated\n")
    (insert "@cindex effective keymap\n\n")
    (insert (concat
             "These tables are generated from each view's @emph{effective} "
             "keymap\n(`keymap-lookup' over the mode's map, local bindings over "
             "inherited ones).\nA key a view binds is listed with the command it "
             "runs; an unbound key is\nomitted.  The semantic contract behind "
             "these tables is\n@code{gascity-key-registry-test}; "
             "@xref{Key Index}, for the alphabetical index.\n\n"))
    (insert "@multitable @columnfractions .15 .12 .33 .40\n")
    (insert "@headitem View @tab Key @tab Command @tab Meaning\n")
    (dolist (view gascity-generate-tables--views)
      (let* ((name (car view))
             (map (symbol-value (cadr view))))
        (dolist (key gascity-generate-tables--keys)
          (let ((binding (keymap-lookup map key)))
            (when binding
              (let* ((cmd (gascity-generate-tables--command binding)))
                (insert (format "@item @code{%s}\n" name))
                (insert (format "@tab @kbd{%s}\n" (gascity-generate-tables--escape key)))
                (insert (format "@tab @code{%s}\n" (car cmd)))
                (insert (format "@tab %s\n" (cdr cmd)))))))))
    (insert "@end multitable\n")
    (buffer-string)))

;;; commands.texi

(defun gascity-generate-tables--classes ()
  "Return every concrete `gascity-command' class as (CLASS SUBCOMMAND DOC).
Sorted by subcommand, then class name."
  (let (rows)
    (mapatoms
     (lambda (symbol)
       (when (and (string-prefix-p "gascity-command-" (symbol-name symbol))
                  (class-p (find-class symbol nil))
                  (not (class-abstract-p symbol))
                  ;; A class with children is a base (`global-options',
                  ;; `action', `bd-action'), not a `gc' leaf command.
                  (null (eieio--class-children (find-class symbol nil))))
         (let* ((class (find-class symbol nil))
                (object (condition-case nil (funcall symbol) (error nil)))
                (subcommand (and (cl-typep object 'gascity-command)
                                 (gascity-command-subcommand object)))
                (doc (eieio--class-option class :documentation)))
           (when subcommand
             (push (list symbol subcommand doc) rows))))))
    (sort rows
          (lambda (a b)
            (let ((sa (nth 1 a)) (sb (nth 1 b)))
              (if (equal sa sb)
                  (string< (symbol-name (car a)) (symbol-name (car b)))
                (string< sa sb)))))))

(defun gascity-generate-tables--suffixes (layout)
  "Return every dispatch suffix in LAYOUT as (GROUP KEY DESC COMMAND)."
  (let (rows)
    (cl-labels
        ((walk (raw group)
           ;; Transient layout nodes are vectors that print like lists;
           ;; normalize so the `transient-column*' branches below match.
           (let ((node (if (vectorp raw) (append raw nil) raw)))
             (cond
              ((and (consp node) (eq (car node) 'transient-suffix))
               (let ((plist (cdr node)))
                 (push (list group
                             (plist-get plist :key)
                             (plist-get plist :description)
                             (plist-get plist :command))
                       rows)))
              ((and (consp node) (eq (car node) 'transient-column))
               (let ((desc (or (plist-get (nth 1 node) :description) group)))
                 (mapc (lambda (child) (walk child desc)) (nth 2 node))))
              ((and (consp node) (eq (car node) 'transient-columns))
               (mapc (lambda (child) (walk child group)) (nth 2 node)))
              ((consp node)
               (mapc (lambda (child) (walk child group)) node))))))
      (walk layout nil))
    (nreverse rows)))

(defun gascity-generate-tables--commands-content ()
  "Return the body of `doc/generated/commands.texi' as a string."
  (with-temp-buffer
    (insert "@node Generated Command Reference\n")
    (insert "@section Generated Command Reference\n")
    (insert "@cindex command reference, generated\n")
    (insert "@cindex dispatch, generated\n\n")
    (insert "Every concrete @code{gascity-command} class, its @command{gc}\n")
    (insert "subcommand and its summary.  The table is generated from the\n")
    (insert "classes' `:documentation' option, so a renamed subcommand or a\n")
    (insert "changed docstring is drift.\n\n")
    (insert "@multitable @columnfractions .36 .64\n")
    (insert "@headitem Command class @tab @command{gc} subcommand and summary\n")
    (dolist (row (gascity-generate-tables--classes))
      (insert (format "@item @code{%s}\n" (car row)))
      (insert (format "@tab @code{gc %s} --- %s\n"
                      (gascity-generate-tables--escape (nth 1 row))
                      (gascity-generate-tables--escape (nth 2 row)))))
    (insert "@end multitable\n\n")
    (insert "@subsection The dispatch menu\n\n")
    (insert (concat
             "The one dispatch, @code{gascity-dispatch} (bound to @kbd{?} "
             "everywhere),\ngenerated from its transient layout.  Its suffixes "
             "sit under the keys they\nhave in the views, so the menu teaches "
             "the view keys.\n\n"))
    (insert "@multitable @columnfractions .16 .10 .32 .42\n")
    (insert "@headitem Group @tab Key @tab Command @tab Meaning\n")
    (dolist (row (gascity-generate-tables--suffixes
                  (get 'gascity-dispatch 'transient--layout)))
      (insert (format "@item %s\n" (gascity-generate-tables--escape (nth 0 row))))
      (insert (format "@tab @kbd{%s}\n" (gascity-generate-tables--escape (nth 1 row))))
      (insert (format "@tab @code{%s}\n" (nth 3 row)))
      (insert (format "@tab %s\n" (gascity-generate-tables--escape (nth 2 row)))))
    (insert "@end multitable\n")
    (buffer-string)))

;;; options.texi

(defun gascity-generate-tables--optionp (symbol)
  "Return non-nil when SYMBOL is a `gascity-*' user option.
`define-minor-mode' also installs a customizable variable and a `-hook'
variable; both are excluded so the table is the `defcustom' surface."
  (and (string-prefix-p "gascity-" (symbol-name symbol))
       (get symbol 'standard-value)
       (not (memq symbol minor-mode-list))
       (not (eq (get symbol 'custom-type) 'hook))))

(defun gascity-generate-tables--option-default (symbol)
  "Return SYMBOL's standard default value as a display string."
  (condition-case nil
      (format "%S" (eval (car (get symbol 'standard-value)) t))
    (error "unspecified")))

(defun gascity-generate-tables--option-type (type)
  "Return a deterministic display string for custom TYPE.
A missing type is `unspecified'.  A list widget is named by its head
(for example `choice' or `alist'); `repeat' is spelled `repeat of
ELEMENT' so the element type stays visible."
  (cond
   ((null type) "unspecified")
   ((symbolp type) (symbol-name type))
   ((and (consp type) (eq (car type) 'repeat) (symbolp (cadr type)))
    (format "repeat of %s" (cadr type)))
   ((and (consp type) (symbolp (car type)))
    (symbol-name (car type)))
   (t "unspecified")))

(defun gascity-generate-tables--options ()
  "Return every `gascity-*' user option as (NAME DEFAULT TYPE).
Sorted by name; DEFAULT and TYPE are display strings."
  (let (rows)
    (mapatoms
     (lambda (symbol)
       (when (gascity-generate-tables--optionp symbol)
         (push (list (symbol-name symbol)
                     (gascity-generate-tables--option-default symbol)
                     (gascity-generate-tables--option-type
                      (get symbol 'custom-type)))
               rows))))
    (sort rows (lambda (a b) (string< (car a) (car b))))))

(defun gascity-generate-tables--options-content ()
  "Return the body of `doc/generated/options.texi' as a string."
  (with-temp-buffer
    (insert "@node Generated User Option Reference\n")
    (insert "@section Generated User Option Reference\n")
    (insert "@cindex user option reference, generated\n")
    (insert "@cindex customization, generated\n\n")
    (insert (concat
             "Every @code{gascity-*} user option (@code{defcustom}), its "
             "standard\ndefault and its type, generated from the live "
             "definitions.  A renamed\noption, a changed default or a changed "
             "type is drift.  The annotated entries\nare in "
             "@ref{Customization and Theming}; this table only enumerates "
             "them.\n\n"))
    (insert "@multitable @columnfractions .42 .33 .25\n")
    (insert "@headitem User option @tab Default @tab Type\n")
    (dolist (row (gascity-generate-tables--options))
      (insert (format "@item @code{%s}\n" (nth 0 row)))
      (insert (format "@tab @code{%s}\n"
                      (gascity-generate-tables--escape (nth 1 row))))
      (insert (format "@tab @code{%s}\n"
                      (gascity-generate-tables--escape (nth 2 row)))))
    (insert "@end multitable\n")
    (buffer-string)))

;;; Writer

(defun gascity-generate-tables--write (file kind content)
  "Write FILE with the KIND header and CONTENT."
  (with-temp-file file
    (insert (format "@c %s.texi --- generated %s tables for gascity.el\n"
                    kind kind))
    (insert "@c\n")
    (insert (mapconcat #'identity (gascity-generate-tables--header-lines kind)
                       "\n"))
    (insert "\n\n")
    (insert content)))

(defun gascity-generate-tables (outdir)
  "Generate `keys.texi', `commands.texi' and `options.texi' under OUTDIR."
  (unless (file-directory-p outdir)
    (make-directory outdir t))
  (gascity-generate-tables--write (expand-file-name "keys.texi" outdir)
                                  "keys"
                                  (gascity-generate-tables--keys-content))
  (gascity-generate-tables--write (expand-file-name "commands.texi" outdir)
                                  "commands"
                                  (gascity-generate-tables--commands-content))
  (gascity-generate-tables--write (expand-file-name "options.texi" outdir)
                                  "options"
                                  (gascity-generate-tables--options-content)))

;;; Command line

(when (and (boundp 'command-line-args-left) command-line-args-left)
  (let ((outdir (pop command-line-args-left)))
    (setq command-line-args-left nil)
    (unless outdir
      (error "gascity-generate-tables: expected an output directory"))
    (gascity-generate-tables outdir)))

(provide 'generate-tables)
;;; generate-tables.el ends here