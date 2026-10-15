---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-xh7gq
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
    - path: beads/ga-kp5b0
      hash: bead:ga-kp5b0
      title: "W4 source anchor: Generated documentation tables and drift gate"
      ids:
        - REQ-014
        - REQ-015
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved plan: section 4 generated tables, decision D4"
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "REQ-014 generated tables, REQ-015 screenshot/manual wiring"
    - path: plans/gnu-toolchain/decomposition.md
      hash: sha256:b1eb1eee2d7310ed63f9348eba55e1219b11f6ac2e44c815a0ad7c28e82f3b58
      title: "W4 work item (F1 drift-gate decision)"
    - path: doc/generate-tables.el
      hash: sha256:f2aa2720af8bafdb4f8ab6f36cd23265fe5669db5daf677af2aadeaca786b857
      title: "Generator for the two tracked Texinfo includes"
    - path: doc/generated/keys.texi
      hash: sha256:d7e51ea6015c9dade2c89992c85e6c49b12ee47694200e21d87833a7aedc7ae5
      title: "Tracked effective key-registry table"
    - path: doc/generated/commands.texi
      hash: sha256:edf63f674d5e03fdb82e499bb5e89f35dcaa891cec1ae2ff2451605dd9338c36
      title: "Tracked command/dispatch table"
    - path: Makefile.am
      hash: sha256:95f107692cc96ccf08bf813a47e5e8d7adbacabc65d0d2f35420e84b3d255f92
      title: "check-doc-drift, regen-doc-tables, check-local wiring"
    - path: doc/Makefile.am
      hash: sha256:ca3caa35f5762e5fa955bfd4e5cd8438970de3dc06d3f13b5de4c5088da9704d
      title: "gascity_TEXINFOS and EXTRA_DIST carry the includes + generator"
    - path: doc/gascity.texi
      hash: sha256:083cd00af31ba18b85f3eaf0233001db34c13a74dfc2c2abd1a6b6861e990768
      title: "Generated Reference Tables appendix with both @include lines"
    - path: lisp/test/gascity-manual-test.el
      hash: sha256:5d767535b470eb76c99f7f349b9bdd15a529768f2afe29591196d1f05e9e4b57
      title: "Includes-in-TEXINFOS/@include assertions"
  coverage:
    - id: REQ-014
      status: covered
    - id: REQ-015
      status: covered
---

# Implementation Summary: W4 — Generated documentation tables and drift gate (source anchor ga-kp5b0)

## Summary

Added the manual's machine-generated reference tables and the drift gate
(plan section 4, decision D4; requirements REQ-014/REQ-015), on top of the
W3 manual integration this branch builds on (commits `1496eb1`, `89d9511`).

`doc/generate-tables.el` renders two tracked Texinfo includes from the
running code: `doc/generated/keys.texi`, the effective binding of every
registry key in every view (`keymap-lookup` local-over-inherited), and
`doc/generated/commands.texi`, every concrete `gascity-command` class with
its `gc` subcommand and summary plus the live `gascity-dispatch` transient
menu.  Both are committed artifacts: a normal `make` never rewrites them,
`make regen-doc-tables` refreshes them, and `make check-doc-drift`
(wired into `make check`) regenerates into a fresh temporary directory and
fails on any `diff`, so the gate needs no `git` and works under `make
distcheck`.  `doc/gascity.texi` includes both tables in a new "Generated
Reference Tables" appendix, and the manual ERT test asserts the includes
are listed in `gascity_TEXINFOS` and `@include`d.

## Intended Behavior

- **Generated key table (REQ-014).** `doc/generated/keys.texi` is produced
  by `doc/generate-tables.el` from each view's *effective* keymap, so a
  parent-map redefinition changes the artifact.  The view and key lists
  mirror `gascity-key-registry-test`; the registry test remains the
  semantic guard.
- **Generated command table (REQ-014).** `doc/generated/commands.texi`
  enumerates every concrete `gascity-command` class (via `gascity-defcommand`)
  and renders the live `gascity-dispatch` transient layout, so a renamed
  subcommand, changed docstring or rebound dispatch key is drift.
- **Tracked, never overwritten by `make`.**  The includes are the committed
  artifact a clean checkout builds the manual from; `make` and `make info`
  only read them.  They ship in `make dist` through
  `doc/Makefile.am`'s `gascity_TEXINFOS`/`EXTRA_DIST` and the top-level
  `EXTRA_DIST`.
- **Drift gate (REQ-014, D4).** `make check-doc-drift` regenerates into a
  fresh `mktemp -d` and `diff -u`s each file against the tracked copy,
  naming the stale file and pointing at `make regen-doc-tables`.  It is a
  prerequisite of `check-local`, so `make check` fails on drift; the gate
  never uses `git diff`.
- **Maintainer rewrite (REQ-014).** `make regen-doc-tables` regenerates the
  tracked copies in place.
- **Manual integration (REQ-014/REQ-015).** `doc/gascity.texi` gains a
  "Generated Reference Tables" appendix that `@include`s both files; the
  existing `@shot`/manifest coverage checks in
  `lisp/test/gascity-manual-test.el` still hold, and a new test asserts the
  includes are in `gascity_TEXINFOS` and included by the manual.

## Changed Files

- `doc/generate-tables.el` (new) — generator; takes the output directory as
  its one positional argument and writes `keys.texi` and `commands.texi`.
- `doc/generated/keys.texi` — regenerated tracked key-registry table.
- `doc/generated/commands.texi` — regenerated tracked command/dispatch table.
- `Makefile.am` — `regen-doc-tables` and `check-doc-drift` targets;
  `check-local: all-local check-doc-drift`; `.PHONY`; `EXTRA_DIST` entries.
- `doc/Makefile.am` — `generate-tables.el` in `EXTRA_DIST`; comment updated
  from "tracked placeholders" to the drift-gate contract.
- `doc/gascity.texi` — new "Generated Reference Tables" appendix with the
  two `@include` lines.
- `lisp/test/gascity-manual-test.el` — new
  `gascity-test-manual-generated-tables-tracked` test.
- `.gitignore` — ignore the `make dist` tarball.
- `plans/gnu-toolchain/build/implementation-summary-ga-kp5b0.md` (new) —
  this summary.

No runtime Elisp behavior, `gc` CLI surface, keymap, transient or beads.el
delegation boundary changes (REQ-020): the generator only reads the
keymaps and the dispatch layout.

## Verification

First verification (clean build + manual + full suite), from the worktree
root after `./autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el"`:

```
$ make                       # exit 0, byte-compile warnings-as-errors clean
$ make info                  # exit 0, gascity.info built (includes render)
$ make html                  # exit 0, 78 HTML pages incl.
                             #   Effective-Key-Bindings.html and
                             #   Generated-Command-Reference.html
$ make check                 # exit 0
Ran 773 tests, 773 results as expected, 0 unexpected
  passed gascity-test-manual-generated-tables-tracked
```

Final proof commands and observed results (the F1 drift contract):

```
$ make check-doc-drift                    # exit 0 (fresh tree, no drift)

# hand-edit doc/generated/keys.texi (append a comment line)
$ make check-doc-drift                    # exit 2
--- ./doc/generated/keys.texi ...
+++ /tmp/tmp.*/keys.texi ...
-@c hand-edit drift probe
check-doc-drift: doc/generated/keys.texi is stale; run 'make regen-doc-tables'

$ make regen-doc-tables                   # exit 0
$ diff doc/generated/keys.texi <backup>   # byte-identical (restored)
$ make check-doc-drift                    # exit 0 again

# a plain `make' must not rewrite the tracked includes
$ make                                    # exit 0
$ sha256sum doc/generated/*.texi          # unchanged before/after

$ make dist                               # exit 0; tarball contains
doc/generate-tables.el, doc/generated/keys.texi, doc/generated/commands.texi
```

The generator is deterministic: three consecutive runs into separate
directories produced byte-identical `keys.texi` and `commands.texi`.

### Coverage

| ID | Status |
| --- | --- |
| REQ-014 | covered |
| REQ-015 | covered |

## Remaining Risks

- **Concurrent worktree writer.**  As with W1/W2, another
  `gascity.el/gc.implementation-worker` session wrote into the same
  `worktrees/ga-kp5b0` path during this run (it produced the first version
  of `doc/generate-tables.el`).  This is the same runtime dispatch bug the
  W1 summary records (a workflow-root latch bead being routed to a worker);
  the committed tree was regenerated and verified after the last write and
  is coherent as of commit `573d2b3`.
- **`commands.texi` group ordering** depends on the transient layout
  traversal, which the generator sorts deterministically for classes; the
  dispatch suffixes keep layout order.  A future transient reorganisation
  is drift by design and must be regenerated.
- **`make check` async flake.**  Under the tokenizer's heavy parallel load
  the pre-existing `gascity-test-local-reader-read-async-generic-envelope-stderr-wins`
  test occasionally fails; it passes in isolation and in the recorded clean
  run.  It is unrelated to this change (no runtime source touched).
- **`keys.texi` size.**  The effective-key table is ~1.8k lines; it is a
  reference appendix and builds into the split HTML tree without trouble,
  but is intentionally not printed in the single-page manual.
