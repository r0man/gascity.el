dnl configure.ac --- autotools configuration for gascity.el
dnl
dnl gascity.el is an Emacs package whose non-ELPA dependencies are
dnl resolved from a checkout rather than a package archive.  See
dnl README.md ("Building from source") and the "Building and installing
dnl with autotools" node of doc/gascity.texi.
dnl
dnl SPDX-License-Identifier: GPL-3.0-or-later

AC_INIT([gascity.el],
        [0.1.0],
        [https://github.com/r0man/gascity.el/issues],
        [gascity],
        [https://github.com/r0man/gascity.el])

AC_CONFIG_AUX_DIR([build-aux])
AC_CONFIG_MACRO_DIRS([m4])
dnl -Wall -Werror keeps every other automake warning fatal.  -Wno-portability
dnl only silences the GNU make `$(wildcard)'/`$(sort)' extensions the build
dnl uses to find lisp/*.el and lisp/test/*-test.el without a hand-maintained
dnl file list.
AM_INIT_AUTOMAKE([foreign -Wall -Werror -Wno-portability])

AC_PROG_MAKE_SET
AC_PROG_INSTALL

dnl Emacs drives byte-compilation, autoload generation and install.
AC_PATH_PROG([EMACS], [emacs], [no])
AS_IF([test "x$EMACS" = xno],
  [AC_MSG_ERROR([emacs not found; an Emacs installation is required to build gascity.el])])

dnl Texinfo tooling.  makeinfo is required: the manual is a first-class
dnl build product and `make install' installs gascity.info.  texi2pdf is
dnl optional because `make pdf' additionally needs a TeX installation.
dnl Automake already provides the `TEXI2PDF' variable, so there is
dnl nothing to substitute here.
AC_PATH_PROG([MAKEINFO], [makeinfo], [no])
AS_IF([test "x$MAKEINFO" = xno],
  [AC_MSG_ERROR([makeinfo not found; install GNU Texinfo to build the gascity manual])])


AM_PATH_LISPDIR

dnl --------------------------------------------------------------------
dnl Non-ELPA dependency resolution (REQ-009, plan D2).
dnl
dnl beads.el is not on ELPA/MELPA, so `configure' locates a checkout of
dnl it (default: ../beads.el beside this source tree) and the `vui' that
dnl checkout bundles.  Both directories are exported to the build as
dnl EMACSLOADPATH entries.
dnl
dnl R2 --- vui precedence: the vui bundled in the beads.el checkout is
dnl deliberately used in preference to any separately installed `vui'
dnl (for example Guix's `emacs-vui'), because it is the exact vui that
dnl this beads.el was built against.  The Makefile prepends it to
dnl EMACSLOADPATH so it shadows the site copy.
dnl --------------------------------------------------------------------

AC_ARG_WITH([beads-dir],
  [AS_HELP_STRING([--with-beads-dir=DIR],
                  [beads.el checkout containing lisp/beads-meta.el
                   (default: SRCDIR/../beads.el)])],
  [gascity_beads_dir="$withval"],
  [gascity_beads_dir="$srcdir/../beads.el"])

AC_MSG_CHECKING([for beads.el])
gascity_beads_dir_abs=`cd "$gascity_beads_dir" >/dev/null 2>&1 && pwd`
if test -z "$gascity_beads_dir_abs" \
   || test ! -f "$gascity_beads_dir_abs/lisp/beads-meta.el"; then
  AC_MSG_ERROR([beads.el not found: $gascity_beads_dir/lisp/beads-meta.el is missing.
  Use --with-beads-dir=DIR to point at a beads.el checkout.])
fi
AC_MSG_RESULT([$gascity_beads_dir_abs])

AC_ARG_WITH([vui-dir],
  [AS_HELP_STRING([--with-vui-dir=DIR],
                  [directory containing vui.el (default: the vui bundled in
                   the beads.el checkout found above)])],
  [gascity_vui_dir="$withval"],
  [gascity_vui_dir=""])

AC_MSG_CHECKING([for vui.el])
if test -z "$gascity_vui_dir"; then
  for gascity_vui_candidate in \
      "$gascity_beads_dir_abs"/.eldev/*/packages/vui-* \
      "$gascity_beads_dir_abs"/../vui \
      "$gascity_beads_dir_abs"/vui; do
    if test -f "$gascity_vui_candidate/vui.el"; then
      gascity_vui_dir="$gascity_vui_candidate"
      break
    fi
  done
fi
gascity_vui_dir_abs=`cd "$gascity_vui_dir" >/dev/null 2>&1 && pwd`
if test -z "$gascity_vui_dir_abs" \
   || test ! -f "$gascity_vui_dir_abs/vui.el"; then
  AC_MSG_ERROR([vui.el not found: looked in the vui bundled under
  $gascity_beads_dir_abs, $gascity_beads_dir_abs/../vui and
  $gascity_beads_dir_abs/vui.
  Use --with-vui-dir=DIR to point at a directory containing vui.el.])
fi
AC_MSG_RESULT([$gascity_vui_dir_abs])

dnl --------------------------------------------------------------------
dnl transient (runtime dependency).
dnl
dnl `transient-define-group' is newer than the transient bundled with
dnl Emacs 29/30 (0.7, which lacks the macro).  beads.el's
dnl `beads-define-prefix' expands to `transient-define-group', so the build
dnl must put transient >= 0.10.1 (the version in Package-Requires) ahead of
dnl the bundled copy.  One comes from the ambient EMACSLOADPATH
dnl (scripts/ci-deps does this for CI) or from this explicit option; when
dnl neither is given, Emacs 31+'s bundled transient is new enough.
dnl --------------------------------------------------------------------

AC_ARG_WITH([transient-dir],
  [AS_HELP_STRING([--with-transient-dir=DIR],
                  [directory containing transient.el, prepended to
                   EMACSLOADPATH (default: the ambient EMACSLOADPATH,
                   else Emacs's bundled transient)])],
  [gascity_transient_dir="$withval"],
  [gascity_transient_dir=""])

if test -n "$gascity_transient_dir"; then
  AC_MSG_CHECKING([for transient.el])
  gascity_transient_dir_abs=`cd "$gascity_transient_dir" >/dev/null 2>&1 && pwd`
  if test -z "$gascity_transient_dir_abs" \
     || test ! -f "$gascity_transient_dir_abs/transient.el"; then
    AC_MSG_ERROR([transient.el not found in $gascity_transient_dir.
  Use --with-transient-dir=DIR to point at a directory containing transient.el.])
  fi
  gascity_transient_dir="$gascity_transient_dir_abs"
  AC_MSG_RESULT([$gascity_transient_dir])
else
  gascity_transient_dir=""
fi

AC_SUBST([beads_dir], [$gascity_beads_dir_abs])
AC_SUBST([vui_dir], [$gascity_vui_dir_abs])
AC_SUBST([transient_dir], [$gascity_transient_dir])

AC_CONFIG_FILES([Makefile doc/Makefile])
AC_OUTPUT
