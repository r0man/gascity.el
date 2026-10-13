---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-hzei5
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-d4att
      hash: bead:ga-d4att
      title: "W1 — Autotools skeleton and dependency resolution"
      ids:
        - REQ-001
        - REQ-002
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-009
        - REQ-021
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "Approved requirements (REQ-001..REQ-023, AC-1..AC-10)"
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved implementation plan (W1, decisions D2/D7, risk R2)"
    - path: Eldev
      hash: git:78ac5ba24c37f2936d5a0f20c730f37f9167aeaf
      title: "Build system removed by this change"
    - path: doc/Makefile
      hash: git:47dc0c572689a04d3b93c1ba523ffc6f5be2ba78
      title: "Standalone manual build folded into info_TEXINFOS"
    - path: scripts/gate.sh
      hash: sha256:e96beca6bc3ba3099c5879c5b15e4b34f0781d8c697744e0ee8f0a104c364628
      title: "Quality gate re-expressed on autotools (make + make check)"
    - path: configure.ac
      hash: sha256:a10e6457928abe810987a50e7ccdcdef7a6231d8b22ab0267e0d432fa66a2e7f
      title: "Autotools configuration and dependency resolution"
    - path: Makefile.am
      hash: sha256:10734452031ec67a44c1cab5349f9dcb988863907aabd846b70b4d42ed30a064
      title: "Top-level batched byte-compile, install, dist, check, lint"
    - path: doc/Makefile.am
      hash: sha256:23ff984c4654d663541dfc29918a8b67df42d91cbadc97c306315098f88cac46
      title: "info_TEXINFOS manual build"
    - path: autogen.sh
      hash: sha256:f0bf6fa058ad371915dbce29e2d9443f96a4fd1c4e437bb810f2193e711b3941
      title: "Bootstrap script"
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: covered
    - id: REQ-009
      status: covered
    - id: REQ-021
      status: covered
---

# Implementation Summary: W1 — Autotools skeleton and dependency resolution (source anchor ga-d4att)

## Summary

Replaced the Eldev build system with a real GNU autotools build for
gascity.el (plan W1, requirements REQ-001/002/004/005/006/009/021).
From a clean checkout `./autogen.sh && ./configure
--with-beads-dir="$HOME/workspace/beads.el" && make` bootstraps the
build, byte-compiles every `lisp/*.el` in a single Emacs invocation with
`byte-compile-error-on-warn t`, generates and installs
`gascity-autoloads.el`, and builds/installs the Info manual.  `Eldev`
and `.eldev/` are removed and no autotools path invokes `eldev`.

The non-ELPA `beads.el`/`vui` dependencies are resolved by
`--with-beads-dir`/`--with-vui-dir` (plan D2), with a sibling
`../beads.el` default, a `beads.el` bundled-vui search
(`.eldev/*/packages/vui-*`, then `../vui`, then `vui`), and hard
configure errors that name the missing option and file.

The gates were carried over in the same worktree: `make check`
(single-invocation ERT via `scripts/run-tests.el`), `make lint`
(`scripts/lint.el`, checkdoc + package-lint when present), and
`scripts/gate.sh`/`scripts/lint.sh` re-expressed on the autotools
commands.  The committed tree is coherent: `make`, `make check`,
`make lint`, `make html`, `make dist` and `make install DESTDIR=…` all
succeed on Emacs 31.1.

## Intended Behavior

- **Autotools skeleton (REQ-001).** `configure.ac`, `Makefile.am`,
  `doc/Makefile.am`, `m4/`, git-ignored `build-aux/` (with
  `build-aux/.gitkeep`) and executable `autogen.sh`
  (`autoreconf --install --force --verbose`) produce `configure` and
  `Makefile.in` from a clean checkout.  `AC_CONFIG_AUX_DIR([build-aux])`
  keeps autoreconf output out of the tree; `AM_INIT_AUTOMAKE([foreign
  -Wall -Werror -Wno-portability])` keeps every non-portability automake
  warning fatal while allowing the GNU make `$(wildcard)`/`$(sort)`
  file discovery the plan specifies.
- **Warnings-as-errors byte-compile (REQ-002).** `make` (via
  `all-local`/`byte-compile`) compiles the whole package in one Emacs
  invocation with `byte-compile-error-on-warn t`; a missing forward
  `declare-function` is a hard build failure.
- **Install (REQ-004).** `install-data-local` copies `*.el`, `*.elc`
  and the generated `gascity-autoloads.el` into `$(lispdir)` in one
  pass; automake's Texinfo machinery installs `gascity.info` and its
  `dir` entry into `$(infodir)`.
- **Manual/dist (REQ-005).** `doc/Makefile.am` declares
  `info_TEXINFOS = gascity.texi`; `make info`, `make html`, `make pdf`
  (needs TeX) and `make dist` are all automake targets.  `EXTRA_DIST`
  ships the screenshots, scripts, `guix.scm`, CI workflows and `m4/`.
- **Eldev removal (REQ-006).** `Eldev` and `doc/Makefile` are deleted;
  the gate scripts call `make`/`make check`/`make lint`; no build, test
  or documentation path invokes `eldev`.
- **Dependency resolution (REQ-009).** `configure` locates the
  `beads.el` checkout and the vui it bundles, `AC_SUBST`s
  `beads_dir`/`vui_dir`, and `Makefile.am` prepends them to
  `EMACSLOADPATH` (appending the caller's load path so site packages
  such as `sesman` remain resolvable).  R2 is documented in both files:
  the beads-bundled vui intentionally shadows any Guix `emacs-vui`.
- **Quality gate (REQ-021).** `scripts/gate.sh` keeps the
  warnings-as-errors-then-ERT semantics (`make` + `make check`);
  `scripts/lint.sh` runs `make lint`.  Lint stays out of `make check`
  because checkdoc rules differ across the supported Emacs versions.

## Changed Files

- `configure.ac` (new) — `AC_INIT`, `AM_INIT_AUTOMAKE`, tool probes,
  `--with-beads-dir`/`--with-vui-dir` resolution, `AC_SUBST`.
- `Makefile.am` (new) — batched byte-compile, autoloads, `check-local`,
  `lint`, `screenshots`, install/uninstall, `EXTRA_DIST`.
- `doc/Makefile.am` (new) — `info_TEXINFOS = gascity.texi`, explicit
  `gascity_TEXINFOS` (stylesheet, lightbox, screenshots), `EXTRA_DIST`.
- `autogen.sh` (new, executable) — `autoreconf --install --force --verbose`.
- `m4/.gitkeep`, `build-aux/.gitkeep` (new) — keep macro/aux dirs.
- `.gitignore` — autotools outputs, `build-aux/*` (except `.gitkeep`),
  `lisp/gascity-autoloads.el`, stale Eldev state.
- `NEWS.md` — "Toolchain: autotools replaces Eldev" entry.
- `scripts/gate.sh`, `scripts/lint.sh` — autotools-backed gate/lint.
- `scripts/lint.el`, `scripts/run-tests.el` (new) — lint and ERT drivers.
- `Eldev`, `doc/Makefile` — deleted.
- `plans/gnu-toolchain/build/implementation-summary-ga-d4att.md` (new) —
  this summary.

No runtime Elisp, `gc` CLI surface, keymap, transient or beads.el
delegation boundary is changed (REQ-020).

## Verification

First verification command (offline gate, from the worktree):

```
$ ./autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el" && make
autogen exit=0
configure exit=0
make exit=0
elc count: 34
```

Final proof commands and observed results:

```
$ make check
Ran 772 tests, 772 results as expected, 0 unexpected (41.2 sec)
exit=0

$ ./configure --with-beads-dir=/nonexistent
checking for beads.el... configure: error: beads.el not found: /nonexistent/lisp/beads-meta.el is missing.
  Use --with-beads-dir=DIR to point at a beads.el checkout.
exit=1

$ make install DESTDIR=/tmp/gascity-stage
install exit=0
/tmp/gascity-stage/usr/local/share/emacs/site-lisp/gascity-autoloads.el
  34 .elc files under .../site-lisp/
/tmp/gascity-stage/usr/local/share/info/gascity.info
/tmp/gascity-stage/usr/local/share/info/dir:
* gascity: (gascity).           Magit-style Emacs porcelain for Gas City.

$ make html    # exit=0, doc/gascity.html/ (split pages)
$ make dist    # exit=0, gascity-0.1.0.tar.gz (107 entries incl. gascity.texi,
               # doc/images/*, scripts/gate.sh, guix.scm, autogen.sh)
$ make lint    # exit=0 (checkdoc clean; package-lint skipped locally, CI installs it)

# warnings-as-errors regression: delete (declare-function gascity-agents-roster …)
$ make
lisp/gascity-action.el:2571:25: Error: the function ‘gascity-agents-roster’ is not known to be defined.
make: *** [Makefile:774: byte-compile] Error 1
exit=2   # restored the declaration, make exit=0
```

Notes and caveats: `make pdf` cannot be exercised in this container —
`texi2pdf` is present but no TeX distribution is installed, so it exits
non-zero at the TeX step (plan R3 keeps `texi2pdf` optional).  `sesman`
is resolved from the host Emacs load path appended by
`$(EMACSLOADPATH)`; in a bare CI runner the workflow must provide it
(W8).  `git grep -i eldev` still matches `.github/workflows/*.yml` and
`guix.scm` (W8/W9 own those files) and historical prose under `plans/`,
`docs/` and `NEWS.md`; no file written by this change invokes `eldev`
apart from the documented beads.el `.eldev/*` vui search path.

### Coverage

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-009 | covered |
| REQ-021 | covered |

## Remaining Risks

- **Concurrent worktree writer.** `gascity.el/gc.implementation-worker-1`
  (session claiming the workflow root `ga-hzei5`) was writing into the
  same `worktrees/ga-d4att` path during this run and produced the
  `scripts/lint.el`/`scripts/run-tests.el`/`gate.sh`/`lint.sh` gate
  changes integrated here.  This is a runtime dispatch bug (the workflow
  root is a latch bead that should not be routed); it should be fixed to
  give each work item its own worktree.  The committed tree is coherent
  and verified as of this summary.
- **`make pdf` unverified.** TeX is absent in this environment; the
  target is wired through automake and R3 treats `texi2pdf` as optional.
- **CI `sesman`/`vui` provisioning.** `configure` resolves beads.el/vui,
  but a bare runner still needs `sesman` (and `transient` on Emacs 29)
  available; W8 must install or vendor them so `make check` runs.
- **VPATH builds.** Autoloads are generated into `$(top_srcdir)/lisp`;
  out-of-tree builds are not exercised (`make distcheck` is not part of
  this gate).
