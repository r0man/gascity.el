;;; guix.scm --- Guix package definition for emacs-gascity

;; A development environment for gascity.el.
;; Use with: guix shell -D -f guix.scm
;;
;; Note: beads.el is not packaged for Guix.  gascity.el depends on it at
;; build time via a sibling checkout on the load path (see the Eldev
;; file); this definition wires only the Guix-available dependencies.

(use-modules
 (guix packages)
 (guix gexp)
 (guix build-system emacs)
 ((guix licenses) #:prefix license:)
 (gnu packages emacs)
 (gnu packages emacs-xyz)
 (gnu packages emacs-build)
 (guix git-download))

(define %source-dir (dirname (current-filename)))

(define emacs-gascity
  (package
    (name "emacs-gascity")
    (version "0.1.0")
    (source (local-file %source-dir
                        "emacs-gascity-checkout"
                        #:recursive? #t
                        #:select? (git-predicate %source-dir)))
    (build-system emacs-build-system)
    (arguments
     (list
      #:emacs emacs            ; full Emacs with GnuTLS support
      #:tests? #f              ; tests require the gc CLI and a city
      #:lisp-directory "lisp"
      #:exclude #~(cons ".*-test\\.el$" %default-exclude)))
    (propagated-inputs
     (list emacs-transient emacs-vui emacs-sesman))
    (native-inputs
     (list emacs-eldev emacs-package-lint))
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
