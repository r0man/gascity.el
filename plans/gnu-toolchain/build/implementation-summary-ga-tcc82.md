---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-a12ha
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
    - path: beads/ga-tcc82
      hash: bead:ga-tcc82
      title: "W2 source anchor: Autotools check and lint targets"
      ids:
        - REQ-003
        - REQ-008
        - REQ-021
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved plan: §3 top-level Makefile.am, decision D3"
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "REQ-003/REQ-008/REQ-021 definitions"
    - path: scripts/lint.el
      hash: sha256:c47fb4be2e63898d47b1bda80950376a19631bef46b2dd9fc58d2c515476ffc2
      title: "checkdoc + package-lint batch driver (fixed)"
    - path: scripts/lint.sh
      hash: sha256:a1eb6760c4f242a7b74f50fca6069c32d0f4353c03a1384bd5320707194e5759
      title: "CI lint job's exact command, thin exec wrapper (D3)"
    - path: scripts/run-tests.el
      hash: sha256:f0ec59426f67bf60f67e9244b582d668b5792e1be4eb5fda97ebd15682185bd3
      title: "single-invocation ERT loader for make check"
    - path: Makefile.am
      hash: sha256:10734452031ec67a44c1cab5349f9dcb988863907aabd846b70b4d42ed30a064
      title: "check-local and lint targets"
    - path: scripts/gate.sh
      hash: sha256:e96beca6bc3ba3099c5879c5b15e4b34f0781d8c697744e0ee8f0a104c364628
      title: "warnings-as-errors then ERT, autotools-adapted"
  coverage:
    - id: REQ-003
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-021
      status: covered
---

# Implementation Summary: W2 — Autotools check and lint targets (source anchor ga-tcc82)

## Summary

Completed W2 of the approved GNU-toolchain plan
(`plans/gnu-toolchain/implementation-plan.md` §3, decision D3, work item W2)
for source anchor bead `ga-tcc82`, in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-tcc82`. W2 depends on W1
(`ga-d4att`); W1's autotools skeleton commit `87dcf8a` is merged into this
worktree as `013142f`, so `make check` and `make lint` exist on the real
build. W1's skeleton already carried the check/lint rules (needed for
`scripts/gate.sh` and `SUBDIRS = doc`), so W2's delta is the lint-mechanism
correctness work: `make check` and `make lint` were exercised end to end and
two real defects in `scripts/lint.el` were fixed. Gate:
`scripts/gate.sh` PASS (byte-compile with `--warnings-as-errors` clean +
772/772 ERT tests) and `make lint` PASS without package-lint.

## Intended Behavior

- `make check` runs the whole `lisp/test/*.el` set exactly once through
  `scripts/run-tests.el` in one `$(EMACS) --batch -Q -L lisp -L lisp/test`
  invocation; any ERT failure makes `make` exit non-zero (REQ-003).
- `make lint` runs `checkdoc` over every `lisp/*.el` in one
  `$(EMACS) --batch` invocation and then hands the same files to
  package-lint; any finding is fatal, preserving the `eldev -p -dtT lint`
  bar without Eldev (REQ-008).
- `scripts/lint.sh` is exactly the CI lint job's command from the repo root,
  a thin `exec make lint` wrapper (plan D3).
- `scripts/gate.sh` keeps its semantics on autotools: whole-package
  warnings-as-errors byte-compile, then the ERT suite; lint stays outside it
  because checkdoc's rules differ across 29.4/30.2/31.1 (REQ-021).

## Changed Files

- `scripts/lint.el` — fixed the package-lint handoff. The batch entry point
  `package-lint-batch-and-exit` takes **no** arguments (it reads
  `command-line-args-left`); the previous `(apply #'package-lint-batch-and-exit
  gascity-lint--files)` raised `wrong-number-of-arguments` the moment
  package-lint was installed, i.e. in CI but never in the local no-package-lint
  run. Also set `package-lint-main-file` to the package's `lisp/gascity.el`, as
  Eldev's `eldev-project-main-file` did, so package-lint checks files against
  the real package headers instead of treating each file as its own package.
- `scripts/lint.sh` — re-expressed as the pure `exec make lint` thin wrapper
  (plan D3); the build must be configured first, as its header documents.

W1 files the targets rest on, verified unchanged in this step: `Makefile.am`
(`check-local`, `lint`), `scripts/run-tests.el`, `scripts/gate.sh`.

## Verification

First verification (compile + full suite), from the worktree root:

```sh
./autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el" && make   # exit 0
make check                                                                        # exit 0
```

Observed: byte-compile clean with warnings as errors; `Ran 772 tests, 772
results as expected, 0 unexpected`. `./scripts/gate.sh` also PASS
(compile clean + 772/772).

Clean lint and the falsification proofs:

```sh
make lint          # exit 0 (package-lint absent locally); checkdoc clean
```

Injected test failure: appending `(ert-deftest gascity-test-injected-failure
() (should (= 1 2)))` to `lisp/test/gascity-test.el` made `make check` exit 2
with `Ran 773 tests, 771 results as expected, 2 unexpected` and
`FAILED gascity-test-injected-failure`.

Final proof command: injected checkdoc violation (a defun whose docstring is
not a proper sentence) appended to `lisp/gascity-error.el`:

```sh
make lint         # exit 2
./scripts/lint.sh # exit 2
```

Observed for both: `Error: user-error ("First sentence should end with
punctuation")` from `checkdoc-batch`; removing the violation returned both to
exit 0. This is the W2 contract proof.

Regression proof for the package-lint fix (package-lint 20260903.2119
installed from MELPA into a temp dir, `EMACSLOADPATH` pointed at it):

```sh
make EMACSLOADPATH="$PLDIR" lint   # exit 2, package-lint runs
```

Observed: package-lint now executes and reports findings
(`gascity-ui.el:149 ... if you need 'any'`, and the two local-dependency
installability lines on `gascity.el:7`); it no longer aborts with
`wrong-number-of-arguments`. Before the fix the same invocation crashed before
linting a single file.

| ID | Status |
| --- | --- |
| REQ-003 | covered |
| REQ-008 | covered |
| REQ-021 | covered |

## Remaining Risks

- Running package-lint against this tree with the current package-lint
  release surfaces three findings that are environmental or upstream, not
  produced by this step: `beads` and `vui` "not installable" because
  package-lint only consults `package-archive-contents`/`package-alist` and
  neither local dependency is registered there, and a `rx` false positive
  where `(any "+-")` is read as the Emacs 31.1 function `any`. Eldev hid both
  by managing a package environment (local `beads` dependency, archive
  `vui`). The load-bearing fix here is that package-lint now *runs* instead
  of crashing; making its clean-tree verdict green is CI package-environment
  work (W5: install package-lint from MELPA, register the local beads/vui
  inputs) and, for `any`, a package-lint/`rx` upstream issue.
- `scripts/lint.sh` no longer bootstraps `autotools`; it assumes
  `./autogen.sh && ./configure` have run, per plan D3's "thin wrapper". A
  fresh-checkout caller must configure first (the script header and README say
  so). `scripts/gate.sh` still bootstraps for the compile/test path.
- `make check` loads every `.el` under `lisp/test` (including
  `gascity-test-helpers.el`) via `directory-files`, which is the plan's
  accepted alternative to a build-time generated loader; ordering is
  alphabetical and each file is loaded once via its feature guard.
