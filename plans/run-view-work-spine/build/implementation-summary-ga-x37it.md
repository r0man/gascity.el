---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-b373v
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
    - path: beads/ga-x37it
      hash: bead:ga-x37it
      ids:
        - REQ-013
        - REQ-014
    - path: plans/run-view-work-spine/implementation-plan.md
      hash: sha256:54eea7c01c944a3dcbab1dcf941deda57bc3e2a18331b999d3fdac64340b5527
    - path: plans/run-rendering-alternatives/design.md
      hash: sha256:823b7c92df7d88a5562176d0b29be42c527eee117b52f5ace83c78b7d255ed50
    - path: docs/qa/2026-11-09-run-view-work-spine.md
      hash: sha256:b2623529d0454c3f1d5177d2ab38cc313c26a1d35234d4466dcc704f073de77a
    - path: doc/gascity.texi
      hash: sha256:99d67428ace59377cff5070b3cdec0596bc055013505efe9a69cec9e69b2cedd
    - path: doc/screenshots/fixtures/gascity-fixture.sh
      hash: sha256:a82daceb10a0d5da207b5f3cad4c650a9e2707103b68fe89f77ef12239dd596d
    - path: NEWS.md
      hash: sha256:d425b8ca08776cba0557dd70365cc44272173462f781c01207e4fc5478f279ae
  coverage:
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
---

# WP-3 — Polish, manual, screenshots, release notes, QA

## Coverage

| ID | Status |
| --- | --- |
| REQ-013 | covered |
| REQ-014 | covered |

## Summary

Implemented plan WP-3 (`plans/run-view-work-spine/implementation-plan.md`
§WP-3, design §4.3 phase 3) as a documentation/evidence change on top of the
latest `origin/main`: the run-detail manual now documents the source
headline, identity line, Work spine, labeled denominators, the two convoy
labels and the folded Machinery section; the Runs manual documents the
three-line source card and its loading/unavailable states.

The deterministic screenshot fixture now carries a source-bearing rich run
(`demo-run` on the canonical `demo-10` epic), a flat `do-work` run, a
standalone `review` run and an inline drain.  The rich run has eight
deliverables (`demo-biz-1..8`) paired with their member runs
(`demo-member-1..8`), the last still active on `close-source-anchor`.  The
business beads are anchored under their member runs, so the root detail's
Machinery contains only the run's own steps.  `demo-convoy` tracks `demo-10`,
so `gc convoy status` resolves the source deterministically.

`NEWS.md` records the new detail and card, and rewrites the superseded
`ga-uf8kr` entry so it no longer describes the removed `source` row.  The
interactive tmux/TRAMP acceptance pass is committed in
`docs/qa/2026-11-09-run-view-work-spine.md`.  The two changed views were
captured in the built-in default theme and verified byte-identical.

The commit subject is
`docs(run-view): document the work spine and refresh the screenshots (ga-036m5)`.

## Intended Behavior

- The manual's `Run Detail` node matches the shipped keys: `RET` on either
  half of a deliverable row, `SPC` on Machinery/a drawer, `C` control nodes,
  `T` the needs tree, `I` the inspector, `w` copy and `!` diagnose.  The
  sample shows the source headline, identity line, Work spine, provenance
  and folded Machinery, not the old stage groups.
- The `gascity-runs` node describes the three-line card: source title/id/
  status, root/formula/rig/time plus labeled counts, then the ladder and
  `N/M deliverables`.  It documents `source loading…` and
  `source unavailable` without promising a synchronous read.
- The fixture produces the four plan shapes deterministically and with
  `demo-<role>` ids only.  The rich run's source title comes from the
  canonical `demo-10` epic; the member runs and business beads are joined by
  `gc.drain_member_id`, never by position.
- The committed `runs-default`/`run-detail-default` images show the real
  shipped layout, no `source loading…` placeholder, and the failed Review
  inspector in the detail.
- The QA report records the local `emacs-city` rich/flat/standalone runs, the
  `bright-lights` TRAMP pass, the key sequence, the non-blocking evidence and
  the member-change/live-refresh check.

## Changed Files

- `NEWS.md` — the two new entries and the reworded `ga-uf8kr` entry.
- `doc/gascity.texi` — the Run Detail sample/prose/key table and the Runs
  card shape; the image table and `@shot` captions use the default theme.
- `doc/screenshots/fixtures/gascity-fixture.sh` — convoys, eight rich
  deliverables/member runs, flat/standalone/inline-drain runs; business
  beads anchored under their member runs; source `demo-10`.
- `doc/screenshots/fixtures/README.md` — the run fixture and exclusion
  notes, merged with the shared demo-project/session conventions.
- `doc/screenshots/gascity-shots.el` — waits for the per-visible-card source
  read before capturing the Runs view, so no image can show a loading state.
- `doc/images/runs-default.png`, `doc/images/runs-default-thumb.png`,
  `doc/images/run-detail-default.png`,
  `doc/images/run-detail-default-thumb.png` — regenerated changed views.
- `docs/qa/2026-11-09-run-view-work-spine.md` — the executed acceptance
  report.
- `plans/run-view-work-spine/build/implementation-summary-ga-x37it.md` —
  this artifact.

## Verification

First verification command (from the item worktree):

```sh
find lisp -name '*.elc' -delete && scripts/gate.sh
```

Observed: **PASS** — `>>> gate: make (byte-compile, warnings as errors)`
clean, `Ran 1057 tests, 1057 results as expected, 0 unexpected`, then
`>>> gate: PASS (compile clean + tests green)`.

Docs verification:

```sh
make -C doc
doc/screenshots/capture.sh --scope runs,run-detail
doc/screenshots/capture.sh --verify all
doc/screenshots/capture.sh --check-isolation cockpit
```

Observed: `make -C doc` **PASS** (no makeinfo warnings/errors);
`--scope runs,run-detail` produced
`run-detail-default full= 83378 thumb= 81513` and
`runs-default full= 20206 thumb= 19357`; `--verify all` **PASS**
`byte-identical for 25 image(s) (scope all)`; `--check-isolation cockpit`
**PASS** `OK; 56 non-selected image(s) byte-identical (scope cockpit)`.

Final proof command:

```sh
scripts/lint.sh
```

Observed: **PASS** — checkdoc clean; package-lint is not installed locally
(CI installs it), as expected.

Artifact validation (from the launcher rig root; the summary is recorded on
the workflow root):

```sh
cd /home/roman/workspace/gascity.el && \
  GC_RIG_ROOT=/home/roman/workspace/gascity.el/worktrees/ga-x37it \
  GC_BEAD_ID=ga-10ra6 .gc/scripts/checks/build-artifact-valid.sh
```

Observed: `build artifact valid: schema=gc.build.implementation-summary.v1`.

## Remaining Risks

- The manual's live `be-0kjzs` sample was replaced by the deterministic
  fixture sample so the manual, fixture and images agree; the live run has
  since closed at 10/10.  The sample documents the layout and keys, not a
  moving count.
- The QA report's live-refresh check exercises the store invalidation route,
  not a separately provoked member state transition; the ERT delta tests are
  the regression guard for the face/stamp details.
- The fixture's review loop uses canonical `demo-10`/`demo-11` titles and the
  run root is `build-basic on demo-10`; a future canonical dataset rename
  must update the fixture's `demo-convoy` tracks edge with it.
