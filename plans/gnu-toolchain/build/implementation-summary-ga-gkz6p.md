---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-c28zp
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
    - path: beads/ga-gkz6p
      hash: bead:ga-gkz6p
      title: "W9 source anchor: Guix package conversion and README rewrite"
      ids:
        - REQ-010
        - REQ-018
        - REQ-019
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved plan sections 7 (Guix) and 9 (README rewrite)"
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "REQ-010 (guix shell + guix build), REQ-018 (concise README), REQ-019 (tables to manual); AC-5, AC-9"
    - path: plans/gnu-toolchain/decomposition.md
      hash: sha256:b1eb1eee2d7310ed63f9348eba55e1219b11f6ac2e44c815a0ad7c28e82f3b58
      title: "W9 work item: Guix package conversion and README rewrite"
    - path: guix.scm
      hash: sha256:c0362a3dfbfa0d628d4d3a4394b753ca15d15275e80b1d9c5642d7ee3a15d6ef
      title: "Guix package through gnu-build-system and the autotools flow"
    - path: README.md
      hash: sha256:c88b80db25504ffb3c860e697a151247450af7a05fab54c936090f090b1b699b
      title: "Concise README: badges, Guix/autotools install, quick start, manual pointers, contributing, license"
  coverage:
    - id: REQ-010
      status: covered
    - id: REQ-018
      status: covered
    - id: REQ-019
      status: covered
---

# Implementation Summary: W9 — Guix package conversion and README rewrite (source anchor ga-gkz6p)

## Summary

Converted `guix.scm` from `emacs-build-system` to `gnu-build-system` so the
package is built through the same `./configure && make && make install` flow
as a checkout (REQ-010, plan section 7), and rewrote `README.md` as a concise
standard project README with the long view/key tables left to the manual
(REQ-018, REQ-019, plan section 9).

`guix.scm`:

- `gnu-build-system`; `autoconf`, `automake`, `texinfo`, `emacs` (full,
  GnuTLS), `emacs-package-lint`, plus the ELPA dependencies
  (`emacs-transient`, `emacs-vui`, `emacs-sesman`) as `native-inputs` so
  byte-compilation has them on `EMACSLOADPATH`; `propagated-inputs` keeps the
  three for runtime. No `emacs-eldev`.
- `beads.el` and its bundled `vui` stay outside Guix. The sibling checkout
  (`../beads.el`, `GASCITY_BEADS_DIR` overrides it) is a `local-file` input
  copied to the store; its store path becomes `--with-beads-dir` and the
  `.eldev/*/packages/vui-*` it bundles becomes `--with-vui-dir`. `.git` and
  `worktrees` are pruned from the copy.
- `#:tests? #f` is retained: the ERT suite needs the `gc` CLI and a live
  city, which the sandbox does not have.
- The `(guix build emacs-utils)` build module (not a package, so it is
  imported through `#:modules`/`#:imported-modules`) drives an
  `emacs-autoloads` phase after `install`.
- An `expand-emacs-load-path` phase runs **before `configure`**: gnu-build-
  system does not expand the versioned subdirectory of each ELPA directory
  Guix puts on `EMACSLOADPATH`, and automake bakes the configure-time
  `EMACSLOADPATH` into the generated `Makefile`, so the expansion must happen
  before configure for `emacs-transient`/`emacs-sesman` to be found. The
  Makefile still prepends the beads checkout's `lisp/` and its bundled vui,
  so the bundled vui shadows Guix's `emacs-vui` (R2).

`README.md` (3.1 KB) now has: a one-paragraph description, a status note,
CI/Lint/Pages badges, the cockpit screenshot link, an install section for
Guix and for the autotools build (naming the `--with-beads-dir` sibling
default, its failure mode, and the evaluation-time `local-file` requirement),
a quick-start paragraph, manual pointers (GitHub Pages and `M-x info`), a
contributing note (`scripts/gate.sh`, `scripts/lint.sh`), and the license.
No table remains; the moved reference lives in `doc/gascity.texi`.

## Intended Behavior

- **`guix build -f guix.scm` packages the autotools project (REQ-010,
  AC-5).** The build runs `autoreconf` (bootstrap), `./configure` with
  `--with-beads-dir`/`--with-vui-dir`, `make` (warnings-as-errors
  byte-compilation plus the Info manual), `make install` (Lisp sources,
  byte-code, `gascity-autoloads.el`, Info), then regenerates the autoloads.
- **`guix shell -D -f guix.scm` stays a usable development environment
  (REQ-010, AC-5).** Inputs and native inputs resolve, so a local
  `./autogen.sh && ./configure --with-beads-dir=… && make && make check`
  runs inside the shell.
- **The README is concise and standard (REQ-018, AC-9).** Every required
  section is present; there is no coverage badge (D9: no service wired, a
  fake badge is worse than none) and no long dispatch/key table.
- **The long tables are in the manual (REQ-019, AC-9).** The README keeps
  only short install/contributing snippets and links to the manual.
- **No runtime change (REQ-020).** Only `guix.scm`, `README.md` and this
  summary change; no Elisp, keymap, transient or `gc` CLI surface is touched.

## Changed Files

- `guix.scm` (modified) — `gnu-build-system` conversion, `local-file`
  beads/vui inputs and `--with-*` configure flags, native/propagated inputs,
  `expand-emacs-load-path` and `emacs-autoloads` phases, `#:tests? #f`
  justification.
- `README.md` (rewritten) — concise standard README; long tables removed.
- `plans/gnu-toolchain/build/implementation-summary-ga-gkz6p.md` (new) —
  this summary.

The worktree was advanced from `origin/main` (`a8059ef`) onto the closed
W1–W6 convoy tip (`df9b73e`), because W9 depends on W1, W3 and W6 and the
autotools/`configure` and manual tree they produced are build prerequisites.
No files from those items are authored here.

## Verification

First verification command (offline quality gate, worktree root):

```
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 775 tests, 775 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)
$ scripts/lint.sh
lint: package-lint is not installed; skipping package metadata checks (CI installs it)
exit=0
```

Final proof commands (Guix both ways, worktree root):

```
$ guix build -f guix.scm
...
phase `emacs-autoloads' succeeded after 0.0 seconds
phase `compress-documentation' succeeded after 0.0 seconds
successfully built /gnu/store/kxix7pxwd1f8lr2zsjlk9vhhny6glvyd-emacs-gascity-0.1.0.drv
/gnu/store/2s7f5n1r1c6zqjg8w527whn48xfq4s8p-emacs-gascity-0.1.0
exit=0        # 34 .elc + gascity-autoloads.el + share/info/gascity.info.gz
$ guix shell -D -f guix.scm -- sh -c \
    './autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el" \
     && make && make check'
...
Ran 775 tests, 775 results as expected, 0 unexpected
exit=0
```

README review checklist (REQ-018/REQ-019, AC-9): one-paragraph description
✓; status note ✓; CI/Lint/Pages badges ✓; cockpit screenshot link ✓; Guix
install ✓; autotools/"Building from source" install naming the sibling
default and failure mode ✓; quick start ✓; manual pointers to GitHub Pages
and `M-x info` ✓; contributing ✓; license ✓; no table remains ✓; 3101 bytes
(< ~4 KB) ✓.

### Coverage

| ID | Status |
| --- | --- |
| REQ-010 | covered |
| REQ-018 | covered |
| REQ-019 | covered |

## Remaining Risks

- **R1 — the `local-file` dependency is read at evaluation time.**  The
  sibling `../beads.el` checkout (or `GASCITY_BEADS_DIR`) must exist before
  `guix build`/`guix shell`, and it must bundle `vui` under
  `.eldev/*/packages/vui-*`; evaluation fails loudly otherwise.  The README
  and the `guix.scm` header say so and name `git-fetch` as the hermetic
  alternative.  This build is therefore not hermetic without that pin.
- **Pages badge is forward-looking.**  `README.md` links
  `.github/workflows/pages.yml`, which sibling item W8 (`ga-66o2y`) adds.
  Until W8 lands the badge and Pages URL are inert; the plan (D9) mandates
  the badge, so this is intentional ordering, not an error.
- **Cross-repo contract not yet observable.**  REQ-022 asks the README
  shape and target names to match beads.el's parallel migration, but
  `beads.el` is still Eldev-based, so there is nothing to compare against
  yet; the divergence/consistency pass belongs to the integration step.
- **`emacs-utils` is a build module, not a Guix package.**  The W9 text
  lists it among the `native-inputs`; adding a non-existent package would
  fail evaluation, so it is imported as `(guix build emacs-utils)` via
  `#:modules`/`#:imported-modules` and documented as such.
- **Expand-load-path is a workaround.**  Because the automake-generated
  `Makefile` freezes `EMACSLOADPATH` at configure time, the Guix phase
  expands the ELPA subdirectories before `configure`.  This is correct for
  gnu-build-system today; if W1's `Makefile.am` ever switches to
  `$(EMACSLOADPATH)` from the environment instead of the make variable, the
  phase can run anywhere before `build`.
- **Worktree base diverges from `origin/main` by design.**  The commit sits
  on `df9b73e` (W1–W6), not on `a8059ef`, to satisfy the W1/W3/W6
  dependency; an integrator should confirm the drain unit's merge order.
- **`make lint` skipped package-lint locally.**  `scripts/lint.sh` ran
  clean but skipped the package metadata checks (package-lint is not
  installed here); CI installs it and remains the authority.
