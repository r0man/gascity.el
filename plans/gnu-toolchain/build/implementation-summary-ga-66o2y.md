---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-vaaym
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
    - path: beads/ga-66o2y
      hash: bead:ga-66o2y
      title: "W8 source anchor: CI conversion and Pages publish workflow"
      ids:
        - REQ-007
        - REQ-016
        - REQ-017
        - REQ-022
        - REQ-023
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved plan: §6 CI, §8 GitHub Pages, decisions D6/D8"
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "REQ-007/REQ-016/REQ-017/REQ-022/REQ-023 definitions"
    - path: .github/workflows/test.yml
      hash: sha256:cb7339846d8c3c80e82b4db7ec3bdb3aaa543e07bf1d61fadd2fc7312bb41705
      title: "test workflow converted to autotools"
    - path: .github/workflows/lint.yml
      hash: sha256:f6b6df102af3e88562e5b6c58b29a1f46886b26a5ce6cb19a80e4b9a0c448be3
      title: "lint workflow converted to make lint"
    - path: .github/workflows/pages.yml
      hash: sha256:d3e9b6273872a2c5ae61f54d7b6d44991d0049f3baaff8f2fe81a89a900a4c68
      title: "new GitHub Pages publish workflow (D6 shared shape)"
    - path: lisp/gascity-ui.el
      hash: sha256:490034a207e943dd7634533dd18593e0007511740241e07bebd2dc86df1ddefc
      title: "package-lint false-positive fix in the timestamp rx"
  coverage:
    - id: REQ-007
      status: covered
    - id: REQ-016
      status: covered
    - id: REQ-017
      status: covered
    - id: REQ-022
      status: covered
    - id: REQ-023
      status: covered
---

# Implementation Summary: W8 — CI conversion and Pages publish workflow (source anchor ga-66o2y)

## Summary

Completed W8 of the approved GNU-toolchain plan
(`plans/gnu-toolchain/implementation-plan.md` §6, §8, decisions D6/D8, work
item W8) for source anchor bead `ga-66o2y`, in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-66o2y`. W8 depends on W1–W7;
the dependency worktree tips `df9b73e` (W1–W6) and `272f063` (W1+W7) were
merged into this worktree as `0ec834d`, so the CI jobs were verified against
the real autotools build and the full manual. Implementation commit
`689a7e7` changes the three workflows below; it also carries one
behaviour-preserving `rx` rewrite required to keep the newly-installed
package-lint step green.

CI no longer installs Eldev anywhere. `test.yml` bootstraps the GNU build
system and runs `make` (whole-package byte-compile with warnings as errors)
and `make check` (the whole ERT suite) across the preserved
29.4/30.2/31.1/snapshot matrix with 29.4 still `continue-on-error`.
`lint.yml` installs `package-lint` from MELPA into a throwaway directory and
runs `make lint` on Emacs 31.1, where any finding is fatal. `pages.yml` is new
and publishes the built split-HTML manual to GitHub Pages on push to `main`
using the shared cross-repo shape beads.el mirrors.

Dependency resolution matches local dev and Guix (plan D2): `configure
--with-beads-dir` points at a cloned `github.com/r0man/beads.el`, and because
a fresh beads.el clone does not vendor the `vui` it declares, each job clones
the pinned `vui` release (`v1.4.0`) to `$HOME/workspace/vui`, which is exactly
the sibling path `configure` searches (`$beads_dir/../vui`). No extra
`--with-vui-dir` flag is needed and the configure command stays the one the
work item specifies.

## Intended Behavior

- `test.yml`: triggers `push`/`pull_request` on `main` and
  `workflow_dispatch`; matrix `29.4`/`30.2`/`31.1`/`snapshot`,
  `fail-fast: false`, `continue-on-error: ${{ matrix.emacs_version == '29.4'
  }}`. Steps: checkout, set up Emacs, install Texinfo, clone beads.el, clone
  vui.el, install gc v1.4.2, then `./autogen.sh && ./configure
  --with-beads-dir="$HOME/workspace/beads.el" && make && make check`. The
  Eldev cache/install and the `Eldev`-keyed cache are gone (REQ-007).
- `lint.yml`: Emacs 31.1 only; same Texinfo/clone/gc steps; install
  package-lint 20260903.2119 (or newer) from MELPA into
  `$RUNNER_TEMP/package-lint`; `make EMACSLOADPATH="$PACKAGE_LINT_DIR" lint`,
  so `scripts/lint.el` loads package-lint while still seeing beads/vui from
  the configured build. Findings remain fatal (REQ-008).
- `pages.yml`: `push` to `main` plus `workflow_dispatch`; workflow-level
  `permissions: {contents: read, pages: write, id-token: write}`;
  `concurrency: {group: pages, cancel-in-progress: false}`; `build` job runs
  `actions/configure-pages@v5` then `./autogen.sh && ./configure
  --with-beads-dir=… && make html` and uploads `doc/gascity.html` with
  `actions/upload-pages-artifact@v3`; `deploy` job runs on the
  `github-pages` environment with `actions/deploy-pages@v4`. Pull requests do
  not deploy, and a broken `make html` fails the build job instead of
  shipping stale HTML (REQ-016, REQ-017, REQ-022, REQ-023).
- `lisp/gascity-ui.el`: the RFC 3339 zone-sign character class is written as
  the `rx` string `"[+-]"` instead of `(any "+-")`. The current package-lint
  release (`20260903.2119`) reads the `rx` symbol `any` as the Emacs 31.1
  function `any` and errors with "You should depend on (emacs \"31.1\")",
  which would make the new fatal lint job red on a clean tree. `"[+-]"`
  compiles to the identical regexp, so no runtime behaviour changes.

## Changed Files

- `.github/workflows/test.yml` — Eldev replaced by the autotools bootstrap;
  beads.el and pinned vui.el clones added; matrix and gc v1.4.2 install
  preserved; Texinfo install added because `configure` hard-requires
  `makeinfo`.
- `.github/workflows/lint.yml` — Eldev and its cache replaced by the
  `./autogen.sh`/`./configure` bootstrap plus a temp-dir package-lint install
  and `make EMACSLOADPATH=… lint` on 31.1.
- `.github/workflows/pages.yml` — new D6-shaped build-then-deploy Pages
  workflow uploading `doc/gascity.html`.
- `lisp/gascity-ui.el` — one-token, behaviour-preserving `rx` rewrite that
  removes the package-lint false positive blocking the lint job.
- `plans/gnu-toolchain/build/implementation-summary-ga-66o2y.md` — this
  summary.

## Verification

First verification (whole gate) and lint, from the worktree root, after
merging W1–W7:

```sh
scripts/gate.sh                                         # exit 0
# >>> gate: PASS (compile clean + tests green)
# Ran 776 tests, 776 results as expected, 0 unexpected

make EMACSLOADPATH="$HOME/.../package-lint-20260903.2119/" lint  # exit 0
```

Workflow validation with the current actionlint (1.7.7), the plan's CI proof
command:

```sh
guix shell actionlint -- actionlint .github/workflows/test.yml \
  .github/workflows/lint.yml .github/workflows/pages.yml   # exit 0, no findings
```

Falsification proofs required by the work item and plan:

```sh
# injected checkdoc violation -> fatal lint (REQ-008)
printf '\n(defun gascity-lint-injected () "bad" nil)\n' >> lisp/gascity-error.el
make EMACSLOADPATH="$PLDIR" lint        # exit 2: "First sentence should end with punctuation"
git checkout -- lisp/gascity-error.el
make EMACSLOADPATH="$PLDIR" lint        # exit 0

# forced make html failure -> the Pages build job fails, does not deploy (REQ-017)
rm -rf doc/gascity.html doc/gascity.info*
make MAKEINFO=false html                # exit 2
make html                               # exit 0; doc/gascity.html/index.html present
```

The final proof command is the local actionlint pass plus the clean
`make lint` above: all three workflows are valid, and the fatal lint job is
green on the clean tree with package-lint installed (the exact CI
environment).

CI dependency resolution was also exercised without the local `.eldev` vui:
a fresh `git clone --depth 1` of beads.el plus a `--branch v1.4.0` clone of
vui.el in a scratch workspace, then `./configure
--with-beads-dir=<fresh beads.el>` reported `checking for vui.el...
/home/.../workspace/vui` and `make && make check` was green (776/776).

| ID | Status |
| --- | --- |
| REQ-007 | covered |
| REQ-016 | covered |
| REQ-017 | covered |
| REQ-022 | covered |
| REQ-023 | covered |

## Remaining Risks

- The test suite's `gascity-test-local-reader-read-async-generic-envelope-stderr-wins`
  failed once under gate load (776 → 1 unexpected) and passed on every other
  full run, including the final gate. It exercises two real async gc processes
  and their stderr ordering, so it is timing-sensitive; the flake predates
  this change and is not caused by W8. Re-running the suite is the recovery.
- The workflows cannot be executed end to end locally (no GitHub runner); the
  Pages deploy and the four-Emacs matrix are validated by actionlint plus the
  equivalent local commands on Emacs 31.1. The actions themselves
  (`configure-pages@v5`, `upload-pages-artifact@v3`, `deploy-pages@v4`) are
  the versions D6 pins and beads.el will mirror (REQ-022).
- `vui.el` is cloned from its upstream repository at tag `v1.4.0` because a
  fresh beads.el checkout no longer carries the `.eldev` vui that configure's
  first search path expects. If beads.el later vendors or pins vui
  differently, the sibling clone must follow; the alternative is passing
  `--with-vui-dir` explicitly (documented in configure.ac).
- The `gascity-ui.el` rewrite is outside the workflow files but is required
  for the converted lint job to be green: package-lint's `any` finding is a
  real false positive on an `rx` form, not a gascity defect. If an upstream
  package-lint fixes the `rx` handling, the string form remains correct.
- The Lint job installs the current MELPA package-lint release rather than a
  pin, so a future package-lint could surface new findings; that matches the
  pre-W8 Eldev behavior and keeps the bar honest. The gc v1.4.2 and vui
  v1.4.0 pins keep everything else reproducible.
