---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-4fz1x
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
    - path: beads/ga-2toqj
      hash: bead:ga-2toqj
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
    - path: doc/gascity.texi
      hash: sha256:8fe54be540cc34712f8e1b05dd8c81bd8a76268cb82db4873c3e19afe70087be
    - path: docs/key-registry.md
      hash: sha256:738777efea822eb2547c7c3e914a0ec1ac756b70f7468dcf8a67120e9e7cdd9b
    - path: docs/DESIGN-write-actions.md
      hash: sha256:112bae32bfdf84f0da5b3a63c611c6dfcfb128b8409d46d37d1cc038fcd3da7f
    - path: doc/generate-tables.el
      hash: sha256:691f3f3dd1b33f3c0812239848b672ab16cf43b6271eb95e25e387fd5631bf13
    - path: NEWS.md
      hash: sha256:b3edde85b8f21a5680f3cab7e051dfd4583f1baceaf6125a67b7adaa70d0ec03
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: covered
    - id: REQ-007
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-009
      status: not_applicable
      rationale: The per-feature ERT tests are owned by the six implementation items (ga-n6qh5, ga-kci2d, ga-obuvt, ga-grkql, ga-28pbg, ga-x9qb9); this docs item runs the shipped suite as its own gate but adds no test.
    - id: REQ-010
      status: covered
---

# Implementation summary — Docs: manual, key registry, DESIGN §10, generated tables, NEWS (REQ-010)

## Summary

Documented every behavior added by run-view-v3 steps 1–6 in the user
manual, the key registry, `docs/DESIGN-write-actions.md` §10 and
`NEWS.md`, and registered the four new run-detail keys in the generator
that produces the tracked manual tables.

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | not_applicable |
| REQ-010 | covered |

The step is documentation only: no runtime file under `lisp/` is
touched, no `gc` invocation, store key, reader path or JSON shape
changes, and no live run is mutated.

## Intended Behavior

- **Run Detail (manual).** The header example and the prose now describe
  the labelled provenance rows (`root`, `store`, `scope`, `formula` with
  the graph key and formula source on continuation lines), state that an
  absent optional fact is omitted or `(none)` rather than derived, and
  document `o`/`RET` as artifact actions on the header paths.  The
  section records that a stage header owns no artifact of its own, so
  artifact actions on a stage are the step rows' drawers inside it, and
  it keeps the `remote: not checked` and missing-local-file rules.
- **Attempt history.** The inspector example gains an `attempts` block
  and a new `attempts` line item documents one oldest-first row per
  iteration/attempt bead (number, outcome, worker, relative time,
  failure, `(none)` for healthy), the `gc.logical_bead_id` and
  `iteration.N`/`attempt.N` child-path discovery rules, the absence of a
  heading when there are no attempts, and the unchanged collapsed
  `iter N` summary.
- **Web handoff.** The key table gains `B` and `Y`, with prose stating
  the `/city/CITY/runs/ID` route, base trimming and percent-encoding,
  no fabricated scope query, and the `No dashboard URL configured; set
  gascity-dashboard-url` behavior for a nil option.  The manual states
  explicitly that `W` is not shadowed and stays the cross-view live
  toggle.
- **Needs tree.** `T` is documented with the stage-preserving behavior:
  members reordered into the global pre-order, indented by same-stage
  ancestors (capped at four), a dim `↳ needs PARENT` note for a
  cross-stage parent, the `(cycle)` fallback, the flat fallback for a
  formula without edge data, and restore-byte-for-byte on toggling back.
- **Live deltas.** The manual documents the `gascity-changed` highlight,
  the `updated HH:MM:SS` stamp, the no-mark first paint, the sticky rule
  (a no-op refresh leaves the buffer visually unchanged), and that
  point and folds survive the repaint.
- **Runs view.** The example and prose gain the `(all time)` count
  basis, the explicit `last 24h` window on Failed only, the
  `all time` / `last <window>` Closed-history basis, and the second dim
  facts line (stage, step, failure, worker inside 78 columns, fitted
  values with help-echo, same object as the row above).
- **Member rows.** `I`/`w`/`!` on a `└ …` drain-member row are
  documented as acting on the member (in-place drawer, root id copy,
  member's own failure) with `RET` still drilling in.
- **Reference and registries.** `gascity-dashboard-url` has a full
  `@defopt`/`@vindex` entry (default nil, configuration only, no
  probing), the four commands have `@deffn {Command}`/`@fnindex`/
  `@kindex` entries, `docs/key-registry.md` and DESIGN §10 list the new
  run-detail keys and record `W` as unshadowed, `NEWS.md` has one entry
  per user-visible change, and `doc/generate-tables.el`'s
  `gascity-generate-tables--extra-keys` now carries `o`, `B`, `Y` and
  `T`.

## Changed Files

- `doc/gascity.texi` — Runs view, Run Detail (header, artifacts, attempt
  history, keys, web handoff, needs tree, deltas, member rows), run
  detail command entries, and the `gascity-dashboard-url` reference
  entry.
- `docs/key-registry.md` — run-detail key paragraph extended; `W`
  recorded as unshadowed.
- `docs/DESIGN-write-actions.md` — §10 run-detail row and the recorded
  reuse paragraph extended.
- `doc/generate-tables.el` — `o`, `B`, `Y`, `T` added to the rendered
  extra keys, with the `W` rationale.
- `NEWS.md` — seven new `Unreleased` entries.
- `plans/run-view-v3/build/implementation-summary-ga-2toqj.md` — this
  artifact.

No tracked generated table changed: `make regen-doc-tables` is a no-op
against this tree (see Remaining Risks).

## Verification

Run from `/home/roman/workspace/gascity.el/worktrees/ga-2toqj` (the
source anchor's `work_dir`), after `./autogen.sh` and
`./configure --with-beads-dir=~/workspace/beads.el`:

- First verification command:
  `make regen-doc-tables && make check-doc-drift` — exit 0, no
  regenerated diff, `check-doc-drift` printed the OK marker.  The four
  new extra keys are unbound in this tree (their implementation commits
  are not in its base), so the generator omits those rows rather than
  inventing them.
- `make -C doc` — exit 0; `makeinfo` built `doc/gascity.info` with no
  warnings and no missing nodes.
- `scripts/gate.sh` — `PASS (compile clean + tests green)`: byte-compile
  with warnings as errors, then 932/932 ERT tests, 0 unexpected; the 22
  `gascity-test-manual-*` tests pass individually as well.
- `scripts/lint.sh` — exit 0 (checkdoc clean; package-lint is not
  installed locally, as the script reports).
- Final proof command:
  `GC_BEAD_ID=ga-mrvdm .gc/scripts/checks/build-artifact-valid.sh` from
  the launcher rig root, after recording this file's absolute path on
  the workflow root as `gc.implementation.summary_path` — passed with
  `build artifact valid: schema=gc.build.implementation-summary.v1`.

## Remaining Risks

- **Ordering.** The six feature commits this documentation describes
  (`ga-n6qh5`, `ga-kci2d`, `ga-obuvt`, `ga-grkql`, `ga-28pbg`,
  `ga-x9qb9`) are not in this worktree's base (`origin/main` at
  61effa2), so the tracked `doc/generated/keys.texi` and
  `doc/generated/options.texi` cannot yet show the `o`/`B`/`Y`/`T` rows
  or `gascity-dashboard-url`.  `make regen-doc-tables` must be re-run
  once those commits land, before `check-doc-drift` is treated as
  satisfied on the merged tree; the 7b step's `scripts/gate.sh` run
  enforces that.  This is a graph-ordering artifact, not a docs defect.
- **Merge overlap.** `ga-obuvt` already adds a minimal
  `@defopt gascity-dashboard-url` entry and an `options.texi` row; this
  item writes the fuller entry in the same place, so the two branches
  will textually conflict there and the fuller entry should win.
- **Illustrative examples.** The manual `@example` blocks are hand-written
  from the implementation's rendering code, not captured from a live
  run; the 7b screenshot pass is what will pin the real run-detail and
  Runs images.
- **History facts line width.** The shipped four-column facts line fits
  its values into 10/20/24/13 columns *including* their labels, so a
  stage reads `stage Rev…` and a step `step build-basic.re…`.  The
  manual documents the fitted-value/help-echo rule as shipped; the
  readability defect is filed as a follow-up bead rather than fixed
  here (this item may not change runtime behavior).
