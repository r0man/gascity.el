## Makefile.am --- top-level autotools build for gascity.el
##
## SPDX-License-Identifier: GPL-3.0-or-later

ACLOCAL_AMFLAGS = -I m4

SUBDIRS = doc

EMACS = @EMACS@
beads_dir = @beads_dir@
vui_dir = @vui_dir@

## R2 --- vui precedence.  The beads.el checkout's `lisp' directory and
## the vui it bundles are prepended to EMACSLOADPATH, so the bundled vui
## deliberately shadows any separately installed `vui' (for example
## Guix's `emacs-vui'): it is the exact vui this beads.el was built
## against.  The trailing $(EMACSLOADPATH) preserves the caller's own
## load path (site-lisp, Guix profiles, ...).
AM_EMACSLOADPATH = $(beads_dir)/lisp:$(vui_dir):$$EMACSLOADPATH

GASCITY_LISP_FILES = $(filter-out %/gascity-autoloads.el, \
  $(sort $(wildcard $(top_srcdir)/lisp/*.el)))
ELCFILES = $(GASCITY_LISP_FILES:.el=.elc)
AUTOLOADS = $(top_srcdir)/lisp/gascity-autoloads.el

.PHONY: byte-compile lint screenshots

## Byte-compile the whole package in a single Emacs invocation, with
## warnings promoted to errors (REQ-002).  The single invocation over
## every file is what makes a missing forward `declare-function' fatal:
## an undefined cross-file reference is only a warning otherwise.
byte-compile:
	EMACSLOADPATH="$(AM_EMACSLOADPATH)" \
	  $(EMACS) --batch -Q -L '$(top_srcdir)/lisp' \
	    --eval '(setq byte-compile-error-on-warn t)' \
	    -f batch-byte-compile $(GASCITY_LISP_FILES)

## Autoloads, generated in one Emacs invocation.  `loaddefs-generate'
## writes names relative to the output file, so it is generated beside
## the sources and installed with them.
$(AUTOLOADS): $(GASCITY_LISP_FILES)
	EMACSLOADPATH="$(AM_EMACSLOADPATH)" \
	  $(EMACS) --batch -Q -L '$(top_srcdir)/lisp' \
	    --eval "(loaddefs-generate \"$(top_srcdir)/lisp\" \"$(AUTOLOADS)\")"

all-local: byte-compile $(AUTOLOADS)

## `make check' runs the whole ERT suite exactly once (REQ-003, REQ-021).
## scripts/run-tests.el loads each test file unless its feature is already
## present, so a file pulled in through `require' is not evaluated twice.
check-local: all-local
	GASCITY_TEST_DIR='$(top_srcdir)/lisp/test' \
	  EMACSLOADPATH="$(AM_EMACSLOADPATH)" \
	  $(EMACS) --batch -Q -L '$(top_srcdir)/lisp' -L '$(top_srcdir)/lisp/test' \
	    -l '$(top_srcdir)/scripts/run-tests.el'

## `make lint' is the `eldev -p -dtT lint' bar preserved without Eldev
## (REQ-008, REQ-021): scripts/lint.el checkdocs every source and runs
## package-lint when it is installed; any finding is fatal.  Lint is
## deliberately not part of `make check': checkdoc's rules differ across
## the supported Emacs versions (29.4/30.2 flag docstring verbs that 31.1
## accepts), so CI runs it on the one version it agrees on.
lint:
	EMACSLOADPATH="$(AM_EMACSLOADPATH)" \
	  $(EMACS) --batch -Q -L '$(top_srcdir)/lisp' \
	    -l '$(top_srcdir)/scripts/lint.el' $(GASCITY_LISP_FILES)

## The screenshot pipeline stays a local/graphical target (REQ-015).
screenshots:
	cd '$(top_srcdir)/doc/screenshots' && ./capture.sh

clean-local:
	rm -f $(ELCFILES) $(AUTOLOADS)

## `make install' installs the Lisp sources, their byte-code and the
## generated autoloads into lispdir in one pass (REQ-004).  The Info
## manual and its `dir' entry are installed by automake's own Texinfo
## machinery from doc/Makefile.am.
install-data-local: all-local
	$(MKDIR_P) '$(DESTDIR)$(lispdir)'
	$(INSTALL_DATA) $(GASCITY_LISP_FILES) '$(DESTDIR)$(lispdir)/'
	$(INSTALL_DATA) $(ELCFILES) '$(DESTDIR)$(lispdir)/'
	$(INSTALL_DATA) $(AUTOLOADS) '$(DESTDIR)$(lispdir)/'

uninstall-local:
	rm -f \
	  $(addprefix '$(DESTDIR)$(lispdir)'/,$(notdir $(GASCITY_LISP_FILES))) \
	  $(addprefix '$(DESTDIR)$(lispdir)'/,$(notdir $(ELCFILES))) \
	  $(addprefix '$(DESTDIR)$(lispdir)'/,$(notdir $(AUTOLOADS)))

## `make dist' ships everything a clean checkout needs to build the
## package and its manual: the screenshot pipeline, the helper scripts,
## the Guix definition, the CI workflows and the local m4 macros
## (REQ-005).
EXTRA_DIST = \
  NEWS.md \
  README.md \
  AGENTS.md \
  guix.scm \
  autogen.sh \
  m4 \
  scripts \
  .github/workflows \
  doc/screenshots
