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
;; `eldev test' without the graphical capture stack.  Only bash is
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

(provide 'gascity-manual-test)
;;; gascity-manual-test.el ends here
