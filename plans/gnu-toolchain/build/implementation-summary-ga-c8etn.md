---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-ehtmx
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
    - path: beads/ga-c8etn
      hash: bead:ga-c8etn
      title: "W6 source anchor: Manual quality, indexes, contributing, troubleshooting"
      ids:
        - REQ-013
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved plan section 4: manual quality pass (concept, reference, examples, indexes, contributing, troubleshooting)"
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "REQ-013 Guix/PostgreSQL manual quality; AC-6"
    - path: plans/gnu-toolchain/decomposition.md
      hash: sha256:b1eb1eee2d7310ed63f9348eba55e1219b11f6ac2e44c815a0ad7c28e82f3b58
      title: "W6 work item: manual quality, indexes, contributing, troubleshooting"
    - path: doc/gascity.texi
      hash: sha256:18bd4b5d80743913f3d1b4e8d23e388fbed854130d23bdf8cc01169c51749d0f
      title: "Manual: Terminology, Worked Examples, Troubleshooting, autotools install and lint/drift nodes"
    - path: lisp/test/gascity-manual-test.el
      hash: sha256:0dea149bf2515fed13ce1ccb7dead6b2a7603193f75ba2c76cedc22b8350731a
      title: "gascity-test-manual-quality-sections mechanical review checklist"
  coverage:
    - id: REQ-013
      status: covered
---

# Implementation Summary: W6 — Manual quality, indexes, contributing, troubleshooting (source anchor ga-c8etn)

## Summary

Raised `doc/gascity.texi` to the Guix/PostgreSQL quality bar the plan's
section 4 requires (REQ-013, AC-6).  The manual already had a task guide, a
concept introduction (W5) and a view/key reference (W5); this change adds the
missing quality elements around them:

- **Concept and terminology.**  `Introduction` gains a **Terminology**
  section: a glossary that defines city, host, rig, agent, session, polecat,
  bead, convoy, order, sling, formula, run, step, store and view once, with a
  `@cindex` entry for each so the vocabulary is consistent and searchable.
- **Worked examples.**  A new **Worked Examples** chapter walks three jobs
  end to end with exact keys: routing a bead through a formula, recovering a
  stalled agent, and opening and driving a remote city over TRAMP.
- **Troubleshooting.**  A new **Troubleshooting** chapter maps eight
  symptoms to cause and fix: a failed section, `gc` not found, no city,
  offline/slow remote cities, a stopped live stream, a missing terminal
  backend, beads in the wrong store, and where action errors go.
- **Build and quality nodes.**  `Installation` gains **Building and
  installing with autotools** (`./autogen.sh`, `configure`, `make`,
  `make check`, `make install`, the `--with-beads-dir`/`--with-vui-dir`
  options, and the Guix path).  `Contributing` gains **Linting and
  documentation drift** (`make lint`, `make check-doc-drift`,
  `make regen-doc-tables`, and the key-registry completeness assertion).
- **Indexes and cross-references.**  The entry-point table now carries
  `@findex` entries for every view-opening command, plus the session and rig
  dispatchers; the variable index was already folded into the function index
  with `@syncodeindex vr fn`, so every `@defvr`/`@vindex` user option now
  prints in the Command and Variable Index.  The new prose cross-references
  use only real nodes.
- **Mechanical checklist.**  `gascity-test-manual-quality-sections` asserts
  every required node and index element is present, so the W6 quality
  contract cannot silently regress.

The change builds on the W1–W5 stack.  The dispatch worktree was created
from `origin/main`; to match the plan's "W5 and W6 depend on W1–W4" the
worktree was advanced onto W5 (`96bc37d`) and the W2 lint (`6059406`) and W4
doc-drift (`ed12e93`) branches were merged, so the new lint and drift nodes
document targets that exist in the tree.

## Intended Behavior

- **A concept section, a reference section and worked examples are present
  (REQ-013).**  Introduction/`Terminology` define the model and vocabulary;
  `View and Key Reference` (W5) and `Generated Reference Tables` (W4) are the
  reference; `Worked Examples` is the end-to-end tutorial layer.
- **Contributing and troubleshooting sections are present (REQ-013).**
  `Contributing` documents the module layout, the manual build, the lint and
  drift gates and the screenshots; `Troubleshooting` covers the common
  failures with the keys or options that fix them.
- **The two required nodes exist (plan section 4).**  *Building and
  installing with autotools* and *Linting and documentation drift* are
  reachable from the Top menu and their chapter menus.
- **The index is complete (REQ-013).**  View-opening commands, the session
  and rig dispatch transients and the W5 agent verbs carry `@findex`
  entries; `@defvr` user options and `@vindex` variables flow into the one
  Command and Variable Index via `@syncodeindex vr fn`.
- **Cross-references resolve.**  `makeinfo` reports no missing-node or
  undefined-reference warnings for either the Info or the HTML build.
- **No runtime change (REQ-020).**  Only the manual source and one ERT file
  change; no Elisp behaviour, keymap, transient or `gc` CLI surface is
  touched.

## Changed Files

- `doc/gascity.texi` (modified) — `Terminology`; `Worked Examples` and
  `Troubleshooting` chapters; `Building and installing with autotools`;
  `Linting and documentation drift`; explicit `@node`/menu wiring for the
  Introduction and Installation sections; `@findex` entries for the entry
  points and dispatchers; Top-menu entries for the two new chapters.
- `lisp/test/gascity-manual-test.el` (modified) — new
  `gascity-test-manual-quality-sections` assertion.
- `plans/gnu-toolchain/build/implementation-summary-ga-c8etn.md` (new) —
  this summary.

The worktree branch also carries the W1–W5 ancestors it was advanced onto
(autotools skeleton, lint, manual integration, generated tables and drift
gate, reference completeness); only the files above are authored by W6.

## Verification

First verification command (the manual selector, including the new
checklist and the W5 completeness assertion), from the worktree root:

```
$ emacs -Q --batch -L lisp -L lisp/test -l lisp/test/gascity-manual-test.el \
    --eval '(ert-run-tests-batch-and-exit "gascity-test-manual")'
Running 12 tests
   passed  gascity-test-manual-quality-sections
   passed  gascity-test-manual-key-registry-coverage
   ...
Ran 12 tests, 12 results as expected, 0 unexpected
exit=0
```

Final proof command (the autotools build's manual and test targets plus the
CI lint bar), from the worktree root after
`./autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el"`:

```
$ make info
exit=0          # no missing-node / undefined-reference warnings
$ make html
exit=0          # no warnings; doc/gascity.html/Worked-Examples.html,
                # Troubleshooting.html, Building-and-installing-with-autotools.html,
                # Linting-and-documentation-drift.html, Terminology.html all present
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 775 tests, 775 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)
$ scripts/lint.sh
lint: package-lint is not installed; skipping package metadata checks
exit=0
```

### Coverage

| ID | Status |
| --- | --- |
| REQ-013 | covered |

## Remaining Risks

- **The worktree base is an integration of closed sibling items.**  W6 was
  dispatched on a worktree created from `origin/main`; it was advanced onto
  W5 and the W2/W4 branches were merged to satisfy the plan's W1–W4
  dependency and to make the new build/lint nodes accurate.  A final
  integrator should confirm the merge order against the drain unit's
  expected base.
- **The quality-sections test checks presence, not prose.**  It proves every
  required node and index element exists; it does not judge the writing.
- **`@fnindex` is spelled `@findex`.**  The two commands populate the same
  function index, so the FiX requirement's "@fnindex" intent is met with the
  canonical spelling.
- **The variable index is folded, not separate.**  `@syncodeindex vr fn`
  (pre-existing, Guix convention) prints user options in the Command and
  Variable Index rather than a dedicated Variable Index node; adding a second
  `@printindex` warns under Info.
