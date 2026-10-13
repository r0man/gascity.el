;;; generate-tables.el --- Generate the manual's drift-gated tables -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Plan D4 (REQ-014): the manual embeds two generated Texinfo tables,
;; `doc/generated/keys.texi' and `doc/generated/commands.texi'.  Both are
;; *committed* artifacts: a clean checkout builds the manual from them,
;; and a normal `make' never rewrites them.  This script regenerates them
;; into a caller-supplied directory; the Makefile targets are
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
;; the view list below mirrors that test's registry.
;;
;; The command table enumerates every concrete `gascity-command' class
;; (via `gascity-defcommand') and reads the live `gascity-dispatch'
;; transient layout, so a renamed subcommand, a changed docstring or a
;; rebound dispatch key all show up as drift.
;;
;; Usage (the Makefile does this):
;;
;;   emacs --batch -Q -L lisp -L lisp/test -l doc/generate-tables.el OUTDIR
;;
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'cl-lib)
(require 'gascity)

(defconst gascity-generate-tables--views
  '((cockpit        gascity-dashboard-mode-map)
    (rig-dashboard  gascity-rig-dashboard-mode-map)
    (agent-detail   gascity-session-detail-mode-map)
    (agents-tree    gascity-agents-tree-mode-map)
    (agents         gascity-agents-mode-map)
    (session-list   gascity-session-list-mode-map)
    (runs           gascity-runs-mode-map)
    (run-detail     gascity-run-mode-map)
    (health         gascity-health-mode-map)
    (cities         gascity-cities-mode-map)
    (rig-list       gascity-rig-list-mode-map)
    (convoy-list    gascity-convoy-list-mode-map)
    (order-list     gascity-order-list-mode-map)
    (dolt-list      gascity-dolt-list-mode-map)
    (events         gascity-events-mode-map)
    (mail-inbox     gascity-mail-inbox-mode-map)
    (mail-thread    gascity-mail-thread-mode-map))
  "Every view: (NAME MAP).  MAP is resolved at generation time.
Mirrors `gascity-key-registry--views' in
lisp/test/gascity-key-registry-test.el, which asserts the semantics.")

(defconst gascity-generate-tables--keys
  '("RET" "TAB" "S-TAB" "SPC"
    "n" "p" "N" "P"
    "q" "g" "?" "j"
    "a n" "a s" "a w" "a k" "a D" "a r" "a u" "a t" "a d" "a i" "a v"
    "d" "s" "w" "i" "t" "D" "C" "#" "K" "M" "R" "U" "S")
  "The keys rendered per view: the navigation contract, the `a'
namespacing (F1), the agent-only aliases and the reserved keys.")

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
  "Generate `keys.texi' and `commands.texi' under OUTDIR."
  (unless (file-directory-p outdir)
    (make-directory outdir t))
  (gascity-generate-tables--write (expand-file-name "keys.texi" outdir)
                                  "keys"
                                  (gascity-generate-tables--keys-content))
  (gascity-generate-tables--write (expand-file-name "commands.texi" outdir)
                                  "commands"
                                  (gascity-generate-tables--commands-content)))

;;; Command line

(when (and (boundp 'command-line-args-left) command-line-args-left)
  (let ((outdir (pop command-line-args-left)))
    (setq command-line-args-left nil)
    (unless outdir
      (error "gascity-generate-tables: expected an output directory"))
    (gascity-generate-tables outdir)))

(provide 'generate-tables)
;;; generate-tables.el ends here