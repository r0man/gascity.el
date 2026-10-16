## Makefile.am --- top-level autotools build for gascity.el
##
## SPDX-License-Identifier: GPL-3.0-or-later

ACLOCAL_AMFLAGS = -I m4

SUBDIRS = doc

EMACS = @EMACS@
beads_dir = @beads_dir@
vui_dir = @vui_dir@
transient_dir = @transient_dir@

## R2 --- vui precedence.  The beads.el checkout's `lisp' directory and
## the vui it bundles are prepended to EMACSLOADPATH, so the bundled vui
## deliberately shadows any separately installed `vui' (for example
## Guix's `emacs-vui'): it is the exact vui this beads.el was built
## against.  `transient_dir' (from `--with-transient-dir') is prepended
## when configure was given one, so a transient >= 0.10.1 shadows Emacs
## 29/30's older bundled copy.
##
## The trailing colon is deliberate: setting EMACSLOADPATH *replaces*
## Emacs's standard load path, and a trailing empty element re-adds it
## (checkdoc, simple.el, and Emacs 31+'s bundled transient) after the
## dependencies.  Without it `make lint' invoked with a non-empty
## EMACSLOADPATH fails with "Cannot open load file: checkdoc".
AM_EMACSLOADPATH = $(beads_dir)/lisp:$(vui_dir)$(if $(transient_dir),:$(transient_dir),):$$EMACSLOADPATH:

GASCITY_LISP_FILES = $(filter-out %/gascity-autoloads.el, \
  $(sort $(wildcard $(top_srcdir)/lisp/*.el)))
ELCFILES = $(GASCITY_LISP_FILES:.el=.elc)
AUTOLOADS = $(top_srcdir)/lisp/gascity-autoloads.el

.PHONY: byte-compile lint screenshots check-doc-drift check-leak regen-doc-tables

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
check-local: all-local check-doc-drift check-leak
	GASCITY_TEST_DIR='$(top_srcdir)/lisp/test' \
	  EMACSLOADPATH="$(AM_EMACSLOADPATH)" \
	  $(EMACS) --batch -Q -L '$(top_srcdir)/lisp' -L '$(top_srcdir)/lisp/test' \
	    -l '$(top_srcdir)/scripts/run-tests.el'

## Generated manual tables (REQ-014, plan decision D4).  The tracked
## includes under doc/generated/ are the committed artifact a clean
## checkout builds the manual from.  A normal `make' never rewrites them.
## `regen-doc-tables' is the maintainer target that does; `check-doc-drift'
## regenerates into a fresh temporary directory and compares byte for byte,
## so it also works inside `make distcheck' (no `git diff' as the gate).
regen-doc-tables:
	EMACSLOADPATH="$(AM_EMACSLOADPATH)" \
	  $(EMACS) --batch -Q -L '$(top_srcdir)/lisp' -L '$(top_srcdir)/lisp/test' \
	    -l '$(top_srcdir)/doc/generate-tables.el' '$(top_srcdir)/doc/generated'

check-doc-drift:
	@directory="$$(mktemp -d)"; \
	trap 'rm -rf "$$directory"' EXIT; \
	EMACSLOADPATH="$(AM_EMACSLOADPATH)" \
	  $(EMACS) --batch -Q -L '$(top_srcdir)/lisp' -L '$(top_srcdir)/lisp/test' \
	    -l '$(top_srcdir)/doc/generate-tables.el' "$$directory" >/dev/null; \
	status=0; \
	tracked="$(notdir $(wildcard $(top_srcdir)/doc/generated/*.texi))"; \
	for file in $$tracked; do \
	  if ! diff -u "$(top_srcdir)/doc/generated/$$file" "$$directory/$$file"; then \
	    echo "check-doc-drift: doc/generated/$$file is stale; run 'make regen-doc-tables'" >&2; \
	    status=1; \
	  fi; \
	done; \
	for file in "$$directory"/*.texi; do \
	  base="$${file##*/}"; \
	  case " $$tracked " in \
	    *" $$base "*) ;; \
	    *) echo "check-doc-drift: doc/generated/$$base is missing; run 'make regen-doc-tables'" >&2; status=1 ;; \
	  esac; \
	done; \
	exit $$status

## `check-leak' keeps the maintainer's private host name out of the
## manual sources (REQ-009, plan D4).  It is the offline half of the
## gate; the Pages workflow also runs the same script with `--html'
## over the generated pages (plan D5).
check-leak:
	$(top_srcdir)/scripts/check-no-burningswell.sh

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
  doc/generate-tables.el \
  doc/generated/keys.texi \
  doc/generated/commands.texi \
  doc/generated/options.texi \
  doc/screenshots
