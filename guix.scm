;;; guix.scm --- Guix package definition for emacs-gascity

;; Build and development-environment definition for gascity.el.
;;
;; Use with:   guix shell -D -f guix.scm
;; Build with: guix build -f guix.scm
;;
;; gascity.el is a GNU-style autotools project (see configure.ac and
;; Makefile.am); this definition packages it through `gnu-build-system',
;; i.e. the same ./configure && make && make install flow used from a
;; checkout.
;;
;; beads.el and vui are not packaged for Guix.  The sibling beads.el
;; checkout is passed to the build as a `local-file' input whose store
;; path becomes --with-beads-dir, and the vui it bundles under
;; .eldev/*/packages/vui-* becomes --with-vui-dir.  The bundled vui
;; deliberately shadows Guix's emacs-vui (plan decision R2): it is the
;; exact vui this beads.el was built against.
;;
;; R1 --- the beads.el checkout is read at *evaluation* time, when the
;; `local-file' is copied into the store, so it must exist before
;; `guix build' or `guix shell' is run.  The sibling default is
;; ../beads.el; set GASCITY_BEADS_DIR to point elsewhere.  Pin the
;; dependency with `git-fetch' instead of `local-file' if a hermetic,
;; checkout-free build is required.

;; SPDX-License-Identifier: GPL-3.0-or-later

(use-modules
 (guix packages)
 (guix gexp)
 (guix build-system gnu)
 ((guix licenses) #:prefix license:)
 (gnu packages autotools)
 (gnu packages emacs)
 (gnu packages emacs-xyz)
 (gnu packages emacs-build)
 (gnu packages texinfo)
 (guix git-download)
 (ice-9 ftw)
 (srfi srfi-1))

(define %source-dir (dirname (current-filename)))

;; beads.el is not on ELPA/MELPA.  Resolve the sibling checkout the same
;; way configure's default does (../beads.el), with an environment
;; override for CI and package-manager automation.
(define %beads-dir
  (or (getenv "GASCITY_BEADS_DIR")
      (string-append %source-dir "/../beads.el")))

(unless (file-exists? (string-append %beads-dir "/lisp/beads-meta.el"))
  (error "guix.scm: no beads.el checkout at ~a (set GASCITY_BEADS_DIR)"
         %beads-dir))

;; The directory holding vui.el inside the beads.el checkout, relative to
;; its root (e.g. ".eldev/31.1/packages/vui-1.4.0"), or #f when the
;; checkout does not bundle vui.
(define (bundled-vui-relative root)
  (define (entries dir)
    (scandir dir (lambda (name) (not (member name '("." ".."))))))
  (let ((eldev (string-append root "/.eldev")))
    (and (file-exists? eldev)
         (any (lambda (emacs)
                (let* ((packages (string-append eldev "/" emacs "/packages"))
                       (vui (and (file-exists? packages)
                                 (find (lambda (candidate)
                                         (and (string-prefix? "vui-" candidate)
                                              (file-exists?
                                               (string-append packages "/"
                                                              candidate "/vui.el"))))
                                       (entries packages)))))
                  (and vui (string-append ".eldev/" emacs "/packages/" vui))))
              (entries eldev)))))

(define %vui-subdir
  (or (bundled-vui-relative %beads-dir)
      (error "guix.scm: no vui bundled under ~a/.eldev/*/packages/vui-*; set GASCITY_BEADS_DIR to a beads.el checkout that bundles vui"
             %beads-dir)))

(define beads-checkout
  ;; Copy the sibling checkout to the store.  `.git' and `worktrees' are
  ;; large and unused by the build, so prune them; the bundled `.eldev'
  ;; (and thus vui) is kept, because configure resolves --with-vui-dir
  ;; from it.
  (local-file %beads-dir
              "beads.el-checkout"
              #:recursive? #t
              #:select? (lambda (file stat)
                          (and (not (string-suffix? "/.git" file))
                               (not (string-suffix? "/worktrees" file))))))

;; NOTE: `emacs-utils' below is the build-side Guile module
;; `(guix build emacs-utils)', imported through #:modules; it is not a
;; Guix package, so it does not appear in native-inputs.
(define emacs-gascity
  (package
    (name "emacs-gascity")
    (version "0.1.0")
    (source (local-file %source-dir
                        "emacs-gascity-checkout"
                        #:recursive? #t
                        #:select? (git-predicate %source-dir)))
    (build-system gnu-build-system)
    (arguments
     (list
      ;; The ERT suite needs the `gc' CLI and a live city, which are not
      ;; available in the Guix build sandbox.  Byte-compilation,
      ;; documentation and installation are still exercised by the normal
      ;; build.
      #:tests? #f
      #:modules '((guix build gnu-build-system)
                  (guix build utils)
                  (guix build gremlin)
                  (guix elf)
                  (guix build emacs-utils)
                  (ice-9 ftw)
                  (srfi srfi-1))
      #:imported-modules `(,@%default-gnu-imported-modules
                           (guix build emacs-utils))
      #:configure-flags
      #~(list (string-append "--with-beads-dir=" #$beads-checkout)
              (string-append "--with-vui-dir="
                             #$beads-checkout "/" #$%vui-subdir))
      #:phases
      #~(modify-phases %standard-phases
          ;; gnu-build-system does not use emacs-build-system's
          ;; expand-load-path, so build EMACSLOADPATH explicitly from every
          ;; input's share/emacs/site-lisp directory and the versioned
          ;; sub-directory Guix installs each ELPA package into
          ;; (transient.el, sesman.el and the like).  Byte-compilation then
          ;; finds the ELPA dependencies, while the Makefile prepends the
          ;; beads.el checkout's lisp/ and its bundled vui (R2).
          (add-after 'set-paths 'set-emacs-load-path
            (lambda* (#:key inputs #:allow-other-keys)
              (let* ((dirs
                      (delete-duplicates
                       (append-map
                        (lambda (entry)
                          (let* ((dir (cdr entry))
                                 (site (string-append dir
                                                      "/share/emacs/site-lisp")))
                            (if (file-exists? site)
                                (cons site
                                      (map (lambda (sub)
                                             (string-append site "/" sub))
                                           (filter
                                            (lambda (sub)
                                              (file-is-directory?
                                               (string-append site "/" sub)))
                                            (scandir site
                                                     (lambda (name)
                                                       (not (member name
                                                                    '("." ".."))))))))
                                '())))
                        inputs)))
                     (inherited (getenv "EMACSLOADPATH"))
                     (value (string-join
                             (if inherited (append dirs (list inherited)) dirs)
                             ":")))
                (setenv "EMACSLOADPATH" value)
                #t)))
          ;; `make install' already installs gascity-autoloads.el; regenerate
          ;; it with emacs-utils so the installed autoloads are canonical,
          ;; the way other Emacs packages are built.
          (add-after 'install 'emacs-autoloads
            (lambda* (#:key outputs #:allow-other-keys)
              (emacs-generate-autoloads
               "gascity"
               (string-append (assoc-ref outputs "out")
                              "/share/emacs/site-lisp"))
              #t)))))
    (native-inputs
     (list autoconf automake texinfo emacs emacs-package-lint))
    (propagated-inputs
     (list emacs-transient emacs-vui emacs-sesman))
    (home-page "https://github.com/r0man/gascity.el")
    (synopsis "Magit-style Emacs porcelain for Gas City")
    (description
     "This package provides a keyboard-first, transient-based Emacs
interface for the Gas City (@code{gc}) multi-agent workspace manager,
inspired by Magit.  Every view is a function of @code{gc ... --json}
output: gascity renders gc's state and dispatches its commands.

It is built on beads.el's command infrastructure (for auto-generated
transient menus from EIEIO slot metadata) and vui rendering layer, and
delegates all bead UI to beads.el.

Requires the gc CLI tool to be installed and available in PATH.")
    (license license:gpl3+)))

emacs-gascity
