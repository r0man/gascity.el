;;; gascity-manual-test.el --- ERT tests for the manual and screenshot pipeline -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; WI-6 of plans/user-manual (REQ-006, REQ-007, REQ-008): the
;; machine-checkable half of the manual and the reproducible screenshot
;; pipeline.  The tests read the tracked sources --- capture.sh's
;; manifest and scope resolver, gascity-shots.el's shot list,
;; doc/gascity.texi's `@shot' macro and area map, and fixture.sh's
;; isolation variables --- instead of a live city, so they run under
;; `make check' without the graphical capture stack.  Only bash is
;; spawned; the parts that need sway, a GUI Emacs or ImageMagick stay in
;; `capture.sh --self-test' and are skipped there without those tools.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

;;; Locations and process helpers

(defconst gascity-manual-test--root
  (expand-file-name "../.."
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Repository root: the directory holding doc/ and lisp/.")

(defun gascity-manual-test--read (path)
  "Return the contents of repo-relative PATH as a string."
  (with-temp-buffer
    (insert-file-contents (expand-file-name path gascity-manual-test--root))
    (buffer-string)))

(defun gascity-manual-test--call (&rest argv)
  "Run ARGV in the repository root.
The first element of ARGV is the program; the rest are its arguments.
Return a plist with :status, the captured :stdout and the captured
:stderr."
  (let ((errfile (make-temp-file "gascity-manual-err")))
    (unwind-protect
        (with-temp-buffer
          (let ((default-directory gascity-manual-test--root))
            (list :status (apply #'call-process (car argv) nil (list t errfile) nil
                                 (cdr argv))
                  :stdout (buffer-string)
                  :stderr (with-temp-buffer
                            (insert-file-contents errfile)
                            (buffer-string)))))
      (delete-file errfile))))

;;; Parsers for the tracked sources

(defun gascity-manual-test--manifest ()
  "Parse capture.sh's MANIFEST into (THEME SUFFIX VIEW ...) rows."
  (let* ((text (gascity-manual-test--read "doc/screenshots/capture.sh"))
         (start (string-match "read -r -d '' MANIFEST <<'EOF'[^\n]*\n" text)))
    (should start)
    (let* ((body (substring text (match-end 0)))
           (end (string-match "^EOF" body)))
      (should end)
      (mapcar (lambda (line) (split-string line "[ \t]+" t))
              (split-string (substring body 0 end) "\n" t)))))

(defun gascity-manual-test--views ()
  "Return the manifest view names, deduplicated, in manifest order."
  (let (views)
    (dolist (row (gascity-manual-test--manifest))
      (dolist (view (cddr row))
        (unless (member view views) (push view views))))
    (nreverse views)))

(defun gascity-manual-test--output-names ()
  "Return every committed image base name (VIEW+SUFFIX) in the manifest."
  (let (names)
    (dolist (row (gascity-manual-test--manifest))
      (let ((suffix (nth 1 row)))
        (dolist (view (cddr row))
          (push (concat view suffix) names))))
    (nreverse names)))

(defun gascity-manual-test--shot-names ()
  "Return the view names defined in gascity-shots.el's shot list."
  (let* ((text (gascity-manual-test--read "doc/screenshots/gascity-shots.el"))
         (start (string-match "(defun gascity-shots-all" text))
         (end (string-match "(defun gascity-shots--wrapped" text))
         names)
    (should start)
    (should end)
    (let ((region (substring text start end)))
      (while (string-match "(list \"\\([^\"]+\\)\"" region)
        (push (match-string 1 region) names)
        (setq region (substring region (match-end 0)))))
    (nreverse names)))

(defun gascity-manual-test--texi-shots ()
  "Return the image base names embedded by `@shot' in doc/gascity.texi."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) names)
    (while (string-match "@shot{\\([^,}]+\\)" text)
      (let ((name (string-trim (match-string 1 text))))
        ;; The macro's own documentation comment spells `@shot{NAME,
        ;; CAPTION}'; only the real `<view>-<theme>' names count.
        (when (string-match-p "^[a-z0-9-]+\\(-dark\\|-light\\)$" name)
          (push name names)))
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--area-map ()
  "Return the image base names in the manual's Area to Screenshot Map."
  (let* ((text (gascity-manual-test--read "doc/gascity.texi"))
         (start (string-match "@node Area to Screenshot Map" text))
         (end (string-match "@end multitable" text))
         names)
    (should start)
    (should end)
    (dolist (line (split-string (substring text start end) "\n"))
      (when (string-prefix-p "@item " line)
        (let ((columns (split-string line "@tab")))
          (dolist (name (split-string (nth 1 columns) "," t "[ \t\n]+"))
            (push (string-trim name) names)))))
    (nreverse names)))

(defun gascity-manual-test--view-sources ()
  "Return the view names declared in capture.sh's VIEW_SOURCES map."
  (let* ((text (gascity-manual-test--read "doc/screenshots/capture.sh"))
         (start (string-match "declare -A VIEW_SOURCES=(" text))
         (end (string-match "^)" text (or start 0)))
         (region (and start (substring text start (or end (length text)))))    
         keys)
    (should start)
    (should end)
    (while (string-match "\\[\\([a-z0-9-]+\\)\\]=" region)
      (push (match-string 1 region) keys)
      (setq region (substring region (match-end 0))))
    (nreverse keys)))

(defun gascity-manual-test--formula-scope-section ()
  "Return the `[vars.scope]' section of the tracked formula, or nil."
  (let* ((text (gascity-manual-test--read
                ".beads/formulas/user-manual-screenshots.formula.toml"))
         (start (string-match "^\\[vars\\.scope\\]" text)))
    (and start
         (substring text start (or (string-match "^\\[" text (match-end 0))
                                   (length text))))))

(defun gascity-manual-test--beads-isolation-vars ()
  "Return beads.el's `beads-test-isolation-env-vars', or nil when unavailable."
  (let ((dir (expand-file-name "~/workspace/beads.el/lisp/test/")))
    (when (file-directory-p dir)
      (add-to-list 'load-path dir)
      (require 'beads-integration-test nil t)
      (and (boundp 'beads-test-isolation-env-vars)
           (symbol-value 'beads-test-isolation-env-vars)))))

(defun gascity-manual-test--key-registry-const (name)
  "Return the value of the key-registry test's NAME `defconst'.
NAME is a symbol; its literal `(defconst NAME VALUE ...)' form is read
from `gascity-key-registry-test.el' so this file need not load the
package just to learn the registered surface."
  (let* ((text (gascity-manual-test--read
                "lisp/test/gascity-key-registry-test.el"))
         (start (string-match (concat "(defconst "
                                      (regexp-quote (symbol-name name))
                                      "\\b")
                              text)))
    (should start)
    (let ((form (read (substring text start))))
      (should (eq (car form) 'defconst))
      (eval (nth 2 form) t))))

(defun gascity-manual-test--deffn-blocks ()
  "Return the text of every `@deffn @dots{} @end deffn' block in the manual.
The reference coverage test asserts a definition entry, not a bare
mention, so it must look inside these blocks."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) blocks)
    (while (string-match "^@deffn " text)
      (let ((start (match-beginning 0))
            (end (string-match "^@end deffn" text (match-end 0))))
        (if end
            (progn
              (push (substring text start end) blocks)
              (setq text (substring text end)))
          (setq text (substring text (match-end 0))))))
    (nreverse blocks)))

(defun gascity-manual-test--deffn-names ()
  "Return every name defined by a `@deffn @dots{}' line in the manual."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) names)
    (while (string-match "^@deffn {[^}]*} \\([^ \n]+\\)" text)
      (push (match-string 1 text) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--keymap-defvr-names ()
  "Return every name defined by `@defvr {Keymap} NAME' in the manual."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) names)
    (while (string-match "^@defvr {Keymap} \\([^ \n]+\\)" text)
      (push (match-string 1 text) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--index-lines (kind)
  "Return the entries of the `@KINDindex' index in the manual.
KIND is \"fn\", \"v\", \"k\" or \"c\"; a key entry keeps any
`@r{(...)}' qualifier it carries."
  (let* ((text (gascity-manual-test--read "doc/gascity.texi"))
         (regexp (concat "^@" kind "index \\(.+\\)$"))
         names)
    (while (string-match regexp text)
      (push (string-trim (match-string 1 text)) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defconst gascity-manual-test--concepts
  '("bead" "rig" "city" "sling" "convoy" "polecat" "workflow"
    "store" "live refresh")
  "The core vocabulary the manual must define and cross-link (REQ-003).")

(defun gascity-manual-test--info-index-node (text node)
  "Return the region of built Info TEXT for index NODE, or nil."
  (when (string-match (concat "Node: " (regexp-quote node) "\\b") text)
    (let ((start (match-beginning 0)))
      (if (string-match "\nFile: " text (match-end 0))
          (substring text start (match-beginning 0))
        (substring text start)))))

(defun gascity-manual-test--generated-commands ()
  "Return every `gascity-command-*' class in the generated command table."
  (let ((text (gascity-manual-test--read "doc/generated/commands.texi")) names)
    (while (string-match "^@item @code{\\(gascity-command-[^}]+\\)}" text)
      (push (match-string 1 text) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--generated-options ()
  "Return every `gascity-*' user option in the generated option table."
  (let ((text (gascity-manual-test--read "doc/generated/options.texi")) names)
    (while (string-match "^@item @code{\\(gascity-[^}\n]+\\)}" text)
      (push (match-string 1 text) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--defopt-names ()
  "Return every name defined by a `@defopt' line in the manual."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) names)
    (while (string-match "^@defopt \\([^ \n]+\\)" text)
      (push (match-string 1 text) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--user-option-defvr-names ()
  "Return every name defined by `@defvr {User Option} NAME' in the manual."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) names)
    (while (string-match "^@defvr {User Option} \\([^ \n]+\\)" text)
      (push (match-string 1 text) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--nodes ()
  "Return every `@node' name in doc/gascity.texi, in order."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) names)
    (while (string-match "^@node \\(.+\\)$" text)
      (push (string-trim (match-string 1 text)) names)
      (setq text (substring text (match-end 0))))
    (nreverse names)))

(defun gascity-manual-test--menu-targets ()
  "Return every node named by a menu entry in doc/gascity.texi.
Handle both the `* Node::  description' form and the
`* Label: Node.  description' form used when the menu label differs
from the node name."
  (let ((text (gascity-manual-test--read "doc/gascity.texi")) targets)
    (dolist (line (split-string text "\n"))
      (when (string-match "\\`\\* \\(.*\\)" line)
        (let ((entry (match-string 1 line)))
          (cond
           ((string-match "\\`\\(.*?\\)::" entry)
            (push (string-trim (match-string 1 entry)) targets))
           ((string-match "\\`\\(.*?\\): \\(.*?\\)\\.\\s-*" entry)
            (push (string-trim (match-string 2 entry)) targets))))))
    targets))

;;; Tests

(ert-deftest gascity-test-manual-fixture-parses ()
  "The fixture config and every pipeline script are well-formed (REQ-003)."
  (let ((toml (gascity-manual-test--read "doc/screenshots/fixtures/city.toml")))
    (dolist (section '("[workspace]" "[providers.claude]" "[daemon]"))
      (should (string-match-p (regexp-quote section) toml)))
    (should (string-match-p "^name = \"gascity-fixture\"" toml)))
  (dolist (script '("doc/screenshots/capture.sh"
                    "doc/screenshots/fixture.sh"
                    "doc/screenshots/fixtures/gascity-fixture.sh"))
    (should (equal 0 (plist-get (gascity-manual-test--call "bash" "-n" script)
                                :status)))))

(ert-deftest gascity-test-manual-scope-parser ()
  "The capture scope resolver maps all, changed and subset scopes (REQ-002)."
  (let* ((all (gascity-manual-test--views))
         (res (gascity-manual-test--call "bash" "doc/screenshots/capture.sh"
                                         "--list-scope" "--scope" "all")))
    (should (equal 0 (plist-get res :status)))
    (should (equal all (split-string (plist-get res :stdout) "\n" t))))
  (let ((res (gascity-manual-test--call "bash" "doc/screenshots/capture.sh"
                                        "--list-scope" "--scope" "cockpit,health")))
    (should (equal 0 (plist-get res :status)))
    (should (equal '("cockpit" "health")
                   (split-string (plist-get res :stdout) "\n" t))))
  (let ((process-environment
         (cons "GASCITY_SHOT_CHANGED_FILES=lisp/gascity-health.el"
               process-environment)))
    (let* ((res (gascity-manual-test--call "bash" "doc/screenshots/capture.sh"
                                           "--list-scope" "--scope" "changed"))
           (views (split-string (plist-get res :stdout) "\n" t)))
      (should (equal 0 (plist-get res :status)))
      (should (member "health" views))))
  (let ((res (gascity-manual-test--call "bash" "doc/screenshots/capture.sh"
                                        "--list-scope" "--scope" "nope")))
    (should-not (equal 0 (plist-get res :status)))
    (should (string-match-p "nope" (plist-get res :stderr)))))

(ert-deftest gascity-test-manual-capture-root-resolution ()
  "capture.sh finds the repo root from any working directory (REQ-015).
It resolves the root with `git rev-parse --show-toplevel' (or its own
parent-parent), so `make screenshots' can run it by absolute path."
  (let ((text (gascity-manual-test--read "doc/screenshots/capture.sh")))
    (should (string-match-p "rev-parse --show-toplevel" text)))
  (let* ((script (expand-file-name "doc/screenshots/capture.sh"
                                   gascity-manual-test--root))
         (tmp (make-temp-file "gascity-capture-cwd" t))
         (errfile (make-temp-file "gascity-manual-err"))
         (views (gascity-manual-test--views)))
    (unwind-protect
        (with-temp-buffer
          (let ((default-directory (file-name-as-directory tmp)))
            (should (equal 0 (call-process
                              "bash" nil (list t errfile) nil script
                              "--list-scope" "--scope" "all")))
            (should (equal views (split-string (buffer-string) "\n" t)))))
      (delete-file errfile)
      (delete-directory tmp t))))

(ert-deftest gascity-test-manual-manifest-views-have-shots ()
  "Every manifest view has a shot thunk, and vice versa (REQ-001, REQ-006)."
  (let ((views (gascity-manual-test--views))
        (shots (gascity-manual-test--shot-names)))
    (dolist (view views)
      (should (member view shots)))
    (dolist (shot shots)
      (should (member shot views)))))

(ert-deftest gascity-test-manual-texi-shots-resolve ()
  "Every manifest image is embedded by `@shot' and exists on disk (REQ-001)."
  (let ((outputs (gascity-manual-test--output-names))
        (shots (gascity-manual-test--texi-shots)))
    (dolist (name outputs)
      (should (member name shots))
      (should (file-exists-p
               (expand-file-name (concat "doc/images/" name ".png")
                                 gascity-manual-test--root)))
      (should (file-exists-p
               (expand-file-name (concat "doc/images/" name "-thumb.png")
                                 gascity-manual-test--root))))
    (dolist (name shots)
      (should (member name outputs)))))

(ert-deftest gascity-test-manual-area-map-resolves ()
  "Every Area to Screenshot Map entry names a manifest image (REQ-001)."
  (let ((outputs (gascity-manual-test--output-names)))
    (dolist (name (gascity-manual-test--area-map))
      (should (member name outputs)))))

(ert-deftest gascity-test-manual-isolation-vars-match-beads ()
  "Every fixture script's isolation variables equal beads.el's constant.
This covers `gascity-fixture.sh', the process that actually runs
`gc bd import' while seeding, so it cannot drift from the tested list
(REQ-006, AC-6)."
  (let ((beads (gascity-manual-test--beads-isolation-vars)))
    (skip-unless beads)
    (dolist (script '("doc/screenshots/fixture.sh"
                      "doc/screenshots/fixtures/gascity-fixture.sh"))
      (let ((res (gascity-manual-test--call "bash" script
                                            "print-isolation-vars")))
        (should (equal 0 (plist-get res :status)))
        (should (equal beads (split-string (plist-get res :stdout) "\n" t)))))))

(ert-deftest gascity-test-manual-view-sources-cover-manifest ()
  "Every manifest view has a VIEW_SOURCES entry (REQ-002).
Without this, `--scope changed' silently skips a view added to the
manifest but forgotten in the map."
  (let ((sources (gascity-manual-test--view-sources)))
    (dolist (view (gascity-manual-test--views))
      (should (member view sources)))))

(ert-deftest gascity-test-manual-formula-scope-var ()
  "The tracked formula declares one `scope' variable with a value set.
Asserts the var name, its default, and the documented values
(REQ-002, AC-3), instead of relying on a `gc formula show' that can
resolve a sibling repository's formula."
  (let ((text (gascity-manual-test--read
               ".beads/formulas/user-manual-screenshots.formula.toml"))
        (section (gascity-manual-test--formula-scope-section)))
    (should (string-match-p (regexp-quote "formula = \"user-manual-screenshots\"")
                            text))
    (should section)
    (should (string-match-p "default = \"all\"" section))
    ;; The description is the machine-readable value set: all, changed, subset.
    (should (string-match-p "`all`" section))
    (should (string-match-p "`changed`" section))
    (should (string-match-p "comma-separated" section))))

(ert-deftest gascity-test-manual-formula-alias-equal ()
  "The tracked formula's two file names are byte-identical (REQ-002)."
  (should (equal (gascity-manual-test--read
                  ".beads/formulas/user-manual-screenshots.formula.toml")
                 (gascity-manual-test--read
                  ".beads/formulas/user-manual-screenshots.toml"))))

(ert-deftest gascity-test-manual-key-registry-coverage ()
  "Every registered view, key and verb has a reference entry (REQ-002, REQ-003).
The key registry is the coverage checklist: each view must have a
`@deffn {Command}' entry naming its view, mode and keymap; every
universal and vui contract key must carry a `@kindex'; and every agent
verb must have a `@deffn {Command}' entry with its `@kindex' key(s).  A
new view, keymap or agent command -- or a removed reference entry --
fails this test until `doc/gascity.texi' documents it."
  (let* ((texi (gascity-manual-test--read "doc/gascity.texi"))
         (blocks (gascity-manual-test--deffn-blocks))
         (views (gascity-manual-test--key-registry-const
                 'gascity-key-registry--views))
         (contract (gascity-manual-test--key-registry-const
                    'gascity-key-registry--contract))
         (vui-contract (gascity-manual-test--key-registry-const
                        'gascity-key-registry--vui-contract))
         (namespaced (gascity-manual-test--key-registry-const
                      'gascity-key-registry--namespaced-verbs))
         (agent-only (gascity-manual-test--key-registry-const
                      'gascity-key-registry--agent-only-verbs))
         (command-block-p
          (lambda (regexp)
            (cl-some (lambda (block)
                       (and (string-match-p "\\`@deffn {Command} " block)
                            (string-match-p regexp block)))
                     blocks))))
    ;; Every view has a definition entry naming its view, mode and keymap.
    (dolist (view views)
      (let* ((name (symbol-name (car view)))
             (map (symbol-name (nth 1 view)))
             (mode (string-remove-suffix "-map" map)))
        (ert-info ((format "view %s" name))
          (should (funcall command-block-p
                           (concat "@code{" (regexp-quote name) "}"))))
        (ert-info ((format "view %s mode" name))
          (should (funcall command-block-p
                           (concat "@code{" (regexp-quote mode) "}"))))
        (ert-info ((format "view %s map" name))
          (should (funcall command-block-p
                           (concat "@code{" (regexp-quote map) "}"))))
        ;; Widen the assertion to functions: the view's own definition
        ;; block carries the command's `@fnindex' entry (REQ-003, D8).
        (let ((block (cl-find-if
                      (lambda (b) (string-match-p (regexp-quote map) b))
                      blocks)))
          (ert-info ((format "view %s fnindex" name))
            (should block)
            (should (string-match "\\`@deffn {Command} \\([^ \n]+\\)" block))
            (should (string-match-p
                     (regexp-quote (concat "@fnindex " (match-string 1 block)))
                     block))))))
    ;; Every universal and vui contract key is in the key index.
    (dolist (key (append contract vui-contract))
      (ert-info ((format "key %s" key))
        (should (string-match-p (regexp-quote (concat "@kindex " key)) texi))))
    ;; Every namespaced (`a' prefix) verb has an entry and its key index.
    (dolist (entry namespaced)
      (let ((key (car entry))
            (cmd (symbol-name (cdr entry))))
        (ert-info ((format "a %s -> %s" key cmd))
          (should (funcall command-block-p
                           (concat "@deffn {Command} " (regexp-quote cmd))))
          (should (string-match-p
                   (regexp-quote (concat "@kindex a " key)) texi)))))
    ;; Every agent-only bare alias has its command entry and key index.
    (dolist (entry agent-only)
      (let ((key (car entry)))
        (dolist (cmd (cdr entry))
          (ert-info ((format "bare %s -> %s" key (symbol-name cmd)))
            (should (funcall command-block-p
                             (concat "@deffn {Command} "
                                     (regexp-quote (symbol-name cmd)))))
            (should (string-match-p
                     (regexp-quote (concat "@kindex " key)) texi))))))))

(ert-deftest gascity-test-manual-command-coverage ()
  "Every generated command class has a reference entry (REQ-002, REQ-003).
The command registry, as emitted to `doc/generated/commands.texi', is the
coverage checklist: every concrete `gascity-command-*' class must have a
`@deffn {Command}' entry and an `@fnindex' entry in the Command and
Variable Reference chapter.  A new command class -- or a removed
reference entry -- fails this test until `doc/gascity.texi' documents it."
  (let ((commands (gascity-manual-test--generated-commands))
        (blocks (gascity-manual-test--deffn-blocks))
        (texi (gascity-manual-test--read "doc/gascity.texi")))
    (should (> (length commands) 40))
    (dolist (command commands)
      (ert-info ((format "command %s" command))
        (should (cl-some (lambda (block)
                           (string-match-p
                            (concat "\\`@deffn {Command} "
                                    (regexp-quote command) "\\b")
                            block))
                         blocks))
        (should (string-match-p
                 (regexp-quote (concat "@fnindex " command)) texi))))))

(ert-deftest gascity-test-manual-reference-coverage ()
  "Every registered view/key/verb and generated option has a reference entry.
The key registry in `gascity-key-registry-test.el' and the generated
`doc/generated/options.texi' table are the checklists: every view needs a
`@deffn {Command}' entry naming its mode, every universal and vui
contract key a `@kindex', every namespaced and agent-only agent verb its
command entry and key index, and every `gascity-*' user option a
`@defopt'/`@defvr {User Option}' entry and a `@vindex'.  A new view, key,
verb or option -- or a removed reference entry -- fails this test until
`doc/gascity.texi' documents it.  Per plan-review O1 the entries are
hand-written; `options.texi' is only the enumeration (REQ-002, REQ-003)."
  (let* ((texi (gascity-manual-test--read "doc/gascity.texi"))
         (blocks (gascity-manual-test--deffn-blocks))
         (options (gascity-manual-test--generated-options))
         (defopt (gascity-manual-test--defopt-names))
         (defvr (gascity-manual-test--user-option-defvr-names))
         (views (gascity-manual-test--key-registry-const
                 'gascity-key-registry--views))
         (contract (gascity-manual-test--key-registry-const
                    'gascity-key-registry--contract))
         (vui-contract (gascity-manual-test--key-registry-const
                        'gascity-key-registry--vui-contract))
         (namespaced (gascity-manual-test--key-registry-const
                      'gascity-key-registry--namespaced-verbs))
         (agent-only (gascity-manual-test--key-registry-const
                      'gascity-key-registry--agent-only-verbs))
         (command-block-p
          (lambda (regexp)
            (cl-some (lambda (block)
                       (and (string-match-p "\\`@deffn {Command} " block)
                            (string-match-p regexp block)))
                     blocks))))
    ;; Every `@deffn' reference entry carries its explicit function index
    ;; entry, and every option and keymap definition its variable index
    ;; entry, so both printed indexes are complete (REQ-003, D8).
    (dolist (name (gascity-manual-test--deffn-names))
      (ert-info ((format "function index %s" name))
        (should (member name (gascity-manual-test--index-lines "fn")))))
    (dolist (name (append (gascity-manual-test--defopt-names)
                          (gascity-manual-test--user-option-defvr-names)
                          (gascity-manual-test--keymap-defvr-names)))
      (ert-info ((format "variable index %s" name))
        (should (member name (gascity-manual-test--index-lines "v")))))
    ;; Every generated user option has a definition and a variable index
    ;; entry, written once by hand in the reference chapters.
    (should (> (length options) 30))
    (dolist (option options)
      (ert-info ((format "option %s" option))
        (should (or (member option defopt) (member option defvr)))
        (should (string-match-p
                 (regexp-quote (concat "@vindex " option)) texi))))
    ;; Every view has a definition entry naming its view and mode.
    (dolist (view views)
      (let* ((name (symbol-name (car view)))
             (map (symbol-name (nth 1 view)))
             (mode (string-remove-suffix "-map" map)))
        (ert-info ((format "view %s" name))
          (should (funcall command-block-p
                           (concat "@code{" (regexp-quote name) "}"))))
        (ert-info ((format "view %s mode" name))
          (should (funcall command-block-p
                           (concat "@code{" (regexp-quote mode) "}"))))))
    ;; Every universal and vui contract key is in the key index.
    (dolist (key (append contract vui-contract))
      (ert-info ((format "key %s" key))
        (should (string-match-p (regexp-quote (concat "@kindex " key)) texi))))
    ;; Every namespaced (`a' prefix) verb has an entry and its key index.
    (dolist (entry namespaced)
      (let ((key (car entry))
            (cmd (symbol-name (cdr entry))))
        (ert-info ((format "a %s -> %s" key cmd))
          (should (funcall command-block-p
                           (concat "@deffn {Command} " (regexp-quote cmd))))
          (should (string-match-p
                   (regexp-quote (concat "@kindex a " key)) texi)))))
    ;; Every agent-only bare alias has its command entry and key index.
    (dolist (entry agent-only)
      (let ((key (car entry)))
        (dolist (cmd (cdr entry))
          (ert-info ((format "bare %s -> %s" key (symbol-name cmd)))
            (should (funcall command-block-p
                             (concat "@deffn {Command} "
                                     (regexp-quote (symbol-name cmd)))))
            (should (string-match-p
                     (regexp-quote (concat "@kindex " key)) texi))))))))

(ert-deftest gascity-test-manual-generated-tables-tracked ()
  "The generated reference tables are shipped and included (REQ-014).
A normal `make' builds the manual from the tracked `doc/generated/*.texi';
if either file drops out of `gascity_TEXINFOS' it stops shipping, and
`make check-doc-drift' would have nothing to compare against.  Each file
must also be `@include'd by `doc/gascity.texi' or the generated tables
never reach the built manual."
  (let ((makefile (gascity-manual-test--read "doc/Makefile.am"))
        (texi (gascity-manual-test--read "doc/gascity.texi")))
    (dolist (include '("generated/keys.texi"
                       "generated/commands.texi"
                       "generated/options.texi"))
      (ert-info ((format "%s" include))
        (should (string-match-p (regexp-quote include) makefile))
        (should (string-match-p (regexp-quote (concat "@include " include))
                                texi))))))

(ert-deftest gascity-test-manual-nodes-reachable ()
  "Every `@node' is named by some menu entry (REQ-001, REQ-004).
BR-2 requires a complete `@menu'/`@node' tree with no dead ends, so a
section that is moved or added without a matching menu entry fails
here rather than building a manual a reader cannot navigate."
  (let ((nodes (gascity-manual-test--nodes))
        (targets (gascity-manual-test--menu-targets)))
    (should (> (length nodes) 1))
    (dolist (node nodes)
      (unless (equal node "Top")
        (ert-info ((format "node %s" node))
          (should (member node targets)))))))

(ert-deftest gascity-test-manual-quality-sections ()
  "The manual carries the Guix/PostgreSQL quality elements (REQ-013).
A review checklist in test form: a concept section, a task-organized
reference, worked examples, complete indexes, correct cross-references,
a contributing chapter and a troubleshooting chapter, plus the two
required autotools/lint nodes."
  (let ((texi (gascity-manual-test--read "doc/gascity.texi")))
    ;; Concept, terminology, examples, reference, troubleshooting, contributing.
    (dolist (node '("@node Introduction"
                    "@node Terminology"
                    "@node Worked Examples"
                    "@node View and Key Reference"
                    "@node Troubleshooting"
                    "@node Contributing"))
      (ert-info ((format "node %s" node))
        (should (string-match-p (regexp-quote node) texi))))
    ;; The two nodes W6 is required to add.
    (dolist (node '("@node Building and installing with autotools"
                    "@node Linting and documentation drift"))
      (ert-info ((format "new node %s" node))
        (should (string-match-p (regexp-quote node) texi))))
    ;; Concept, function and variable index entries all appear.
    (dolist (index '("@cindex " "@fnindex " "@vindex " "@kindex "))
      (should (string-match-p (regexp-quote index) texi)))
    ;; Both printed indexes are wired: the variable index is folded into
    ;; the function index (`@syncodeindex vr fn'), and the key index prints.
    (should (string-match-p "@syncodeindex vr fn" texi))
    (should (string-match-p "@printindex fn" texi))
    ;; Cross-references are present.
    (should (string-match-p "@xref{" texi))
    (should (string-match-p "@pxref{" texi))))

(ert-deftest gascity-test-manual-reference-entry-indexes ()
  "Every reference entry has its explicit printed-index entry (REQ-003).
The manual has four reference entry kinds: `@deffn', `@defopt',
`@defvr {User Option}' and `@defvr {Keymap}'.  Each `@deffn' name must
appear on a `@fnindex' line and each option or keymap name on a
`@vindex' line, so the printed indexes name every entry a reader can
look up.  A definition added without its index entry fails here."
  (let ((fnindex (gascity-manual-test--index-lines "fn"))
        (vindex (gascity-manual-test--index-lines "v"))
        (deffn (gascity-manual-test--deffn-names))
        (defopt (gascity-manual-test--defopt-names))
        (defvr (gascity-manual-test--user-option-defvr-names))
        (keymaps (gascity-manual-test--keymap-defvr-names)))
    (should (> (length deffn) 80))
    (dolist (name deffn)
      (ert-info ((format "@deffn %s fnindex" name))
        (should (member name fnindex))))
    (should (> (length keymaps) 15))
    (dolist (name (append defopt defvr keymaps))
      (ert-info ((format "definition %s vindex" name))
        (should (member name vindex))))))

(ert-deftest gascity-test-manual-concepts-cross-referenced ()
  "Every core concept is defined once and cross-linked (REQ-003, D8).
The Terminology section is the single definition point; the task
chapters must cross-reference it the first time they lean on a concept.
The Introduction names the chapter, and the body carries at least one
`@pxref{Terminology}' per concept, so the cross-reference web the
Concepts chapter promises actually exists."
  (let ((texi (gascity-manual-test--read "doc/gascity.texi")))
    (dolist (concept gascity-manual-test--concepts)
      (ert-info ((format "concept %s cindex" concept))
        (should (string-match-p
                 (regexp-quote (concat "@cindex " concept)) texi))))
    ;; The Introduction names the Concepts chapter...
    (should (string-match-p (regexp-quote "@ref{Concepts") texi))
    ;; ...and the task chapters each link back to the Terminology section.
    (should (>= (length (split-string texi "@pxref{Terminology}" t))
                (1+ (length gascity-manual-test--concepts))))))

(ert-deftest gascity-test-manual-info-indexes-populated ()
  "Both printed indexes are populated in the built Info output (REQ-003).
Building the manual with `makeinfo' and reading the two generated index
nodes proves the `@printindex' lines are wired to entries, not merely
that index commands appear in the source.  Skipped when `makeinfo' is
not installed."
  (skip-unless (executable-find "makeinfo"))
  (let* ((info (make-temp-file "gascity-manual" nil ".info"))
         (res (gascity-manual-test--call "makeinfo" "--no-split"
                                         "-o" info "doc/gascity.texi")))
    (unwind-protect
        (progn
          (should (equal 0 (plist-get res :status)))
          (let* ((text (with-temp-buffer
                         (insert-file-contents info)
                         (buffer-string)))
                 (key (gascity-manual-test--info-index-node text "Key Index"))
                 (fn (gascity-manual-test--info-index-node
                      text "Command and Variable Index")))
            (should key)
            (should (string-match-p "^\\* .*:\\s-+" key))
            (should fn)
            (should (string-match-p "^\\* .*:\\s-+" fn))))
      (delete-file info))))

(provide 'gascity-manual-test)
;;; gascity-manual-test.el ends here
