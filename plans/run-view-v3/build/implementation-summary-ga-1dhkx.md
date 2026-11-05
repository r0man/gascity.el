---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-ssgfn
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
    - path: beads/ga-1dhkx
      hash: bead:ga-1dhkx
      title: "Screenshots and gates: deterministic run-view images, gate.sh, lint.sh (REQ-009, REQ-010)"
      ids:
        - REQ-009
        - REQ-010
    - path: doc/screenshots/capture.sh
      hash: git:61effa21b5114feb9174c593cbf4811f827a2124
    - path: lisp/gascity-run.el
      hash: git:62a2f0b07c7e24f4d82b2028d5ab036737376f02
    - path: lisp/gascity-runs.el
      hash: git:f5e26c6fef5d04b45f99e8583b22f10279aa9286
    - path: lisp/gascity-run-stage.el
      hash: git:cdcd9f307d00ba5ab3c1c87bd57b24730db25e8d
    - path: doc/images/run-detail-dark.png
      hash: sha256:759d3ccf099d9429ebd1d42338ce1cc47076db72c1abca774c3ceaa35b1e65db
    - path: doc/images/run-detail-dark-thumb.png
      hash: sha256:260bd31e31ad1eca57f47b6f76d9ddbbf3f9838d850697ddd58bacf38427061c
    - path: doc/images/runs-dark.png
      hash: sha256:b3e568a7c2a20b2d67e3383c6a7efb9cc2742b5e8ccb1dbf2cd8a1d3a8150765
    - path: doc/images/runs-dark-thumb.png
      hash: sha256:baebd6289e81f429535cb762e6009c98b3f65929c5d9a5ae3c3188e55a75b568
  coverage:
    - id: REQ-009
      status: covered
    - id: REQ-010
      status: covered
---

# Implementation Summary: deterministic run-view screenshots and full gates (ga-1dhkx)

## Summary

Regenerated the two run-view screenshots (`runs`, `run-detail`) for the
run-view-v3 states from the throwaway deterministic fixture city, proved the
capture is byte-identical across two runs and leaves the other 48 committed
images untouched, and ran the full quality gate (byte-compile with warnings as
errors, whole ERT suite, lint, generated-table drift).

The committed slice is **images only** plus this summary: four PNGs under
`doc/images/` (`<view>-dark.png` and `<view>-dark-thumb.png` for `runs` and
`run-detail`). No production source, fixture, manual, or generated-table file
changed.

**Integration context (important for reviewers).** This item is task-map step
7b of the approved run-view-v3 plan, which runs *after* the six source items
(REQ-001..REQ-008). At dispatch time `origin/main` was still `61effa2`
(`fix(run-view): separate session liveness from a claim lease`) and the six
closed source items were only in their own per-item worktrees, so the item
worktree `/home/roman/workspace/gascity.el/worktrees/ga-1dhkx` did not contain
the v3 source. To produce images of the *new* states without duplicating the
six pending merge requests, the capture was run in a scratch tree
(`/tmp/v3-integration`) built from `61effa2` plus the six closed item commits,
merged in task-map order:

| Step | Bead | Commit | Subject |
| --- | --- | --- | --- |
| 1 | ga-n6qh5 | 880b134 | feat(run-view): stack iteration/attempt history in the step drawer |
| 2 | ga-kci2d | 32975ca | feat(run-view): actionable artifacts and header provenance |
| 3 | ga-obuvt | d43c515 | feat(run-view): web handoff B/Y and gascity-dashboard-url |
| 4 | ga-grkql | 8709d1e | feat(run-view): live deltas and last-update stamp |
| 5 | ga-28pbg | f5e26c6 | feat(runs): label time bases and add history facts lines |
| 6 | ga-x9qb9 | 62a2f0b | feat(run-view): needs-aware step tree toggle |

The six merge cleanly except for three independent-feature overlaps, which the
scratch tree resolves as the union of both features (delta styling carried into
the facts-line row, freshness stamp kept in the title's right column with the
key hint as fallback, needs-note room in the step row's name column, and both
test suites kept). The scratch tree byte-compiles clean, passes 960/960 ERT,
`make check-doc-drift`, and `scripts/lint.sh`, and its merged tree hash is
`8d3f5d119fcf2cc7f5dd85829cca474aa953ac6e`. Those merge resolutions are
**not** committed here; they belong to the six source items' own merge requests.

## Intended Behavior

The fixture (`doc/screenshots/fixture.sh` + `fixtures/`) seeds one active
`build-basic` `demo-run` graph with pinned role ids and timestamps; nothing is
captured from a live store and no live run is touched.

- **`run-detail-dark.png`** shows the run view v3 states the manual documents:
  the header's root/store/scope/formula + contract provenance rows, the
  stage-grouped step tree with the failed `revew` step, and the open step
  inspector with `step`, `attempt 1 · iteration bead …`, the new `attempts`
  block (the fixture's failed iteration: outcome, worker, pinned time, and
  `code_review: …` class/reason), the worker line with the session and claim
  facts kept apart, the `events unavailable` state, and the `failure` line.
- **`runs-dark.png`** shows the Runs view v3 states: the all-time count line
  (`1 active · 0 waiting · 0 done · 0 failed (all time)`), the `Failed none ·
  last 24h` section label, and the history row followed by the dim four-column
  facts line (`review`, `8/11`, `✕ build-basic.review`, `code_review`).
- Both are captured in the single standard dark theme
  (`ef-deuteranopia-dark`), as the manifest and README fix it; no new theme is
  introduced.
- The first paint marks no delta and shows no `updated HH:MM:SS` stamp (the
  plan's sticky-delta rule: a delivery that changes nothing visible leaves the
  buffer unchanged), so the images are not dependent on delivery timing.
- `gascity-dashboard-url` is nil and the fixture has no live controller, so
  the web-handoff (`B`/`Y`) and live-session states are not in these images;
  they are covered by ERT and the row-8 live acceptance item.

## Changed Files

- `doc/images/run-detail-dark.png` — regenerated full image (32123 bytes).
- `doc/images/run-detail-dark-thumb.png` — regenerated preview (34070 bytes).
- `doc/images/runs-dark.png` — regenerated full image (12288 bytes).
- `doc/images/runs-dark-thumb.png` — regenerated preview (13956 bytes).
- `plans/run-view-v3/build/implementation-summary-ga-1dhkx.md` — this artifact.

No source fix was required to make either view deterministic; no exclusion was
needed, so `doc/screenshots/fixtures/README.md` is unchanged.

## Verification

Scratch integration tree: `/tmp/v3-integration` (`61effa2` + the six merges
above, tree `8d3f5d11`), fixture city `/tmp/gascity-fixture`, headless sway.

- **First verification command — scope resolution and first capture.**
  `./doc/screenshots/capture.sh --list-scope --scope changed` → **no views
  selected** (the scratch tree is committed, and the resolver diffs the
  working tree against `HEAD`); `GASCITY_SHOT_BASE=61effa2
  ./doc/screenshots/capture.sh --list-scope --scope changed` → **`runs`,
  `run-detail`**, the item's intended selection.
  `./doc/screenshots/capture.sh --scope runs,run-detail` → **PASS**, producing
  `run-detail-dark` full=32123 thumb=34070 and `runs-dark` full=12288
  thumb=13956 (raw 110550 / 33727 bytes).
- **Determinism and isolation (final proof for the images).**
  `rm -rf /tmp/gascity-shots/verify-a /tmp/gascity-shots/verify-b &&
  ./doc/screenshots/capture.sh --verify run-detail,runs` → **PASS**:
  `verify: byte-identical for 2 image(s) (scope run-detail,runs)`, and
  `isolation: OK; 48 non-selected image(s) byte-identical`.
- **Quality gates (final proof for REQ-009).**
  `./scripts/gate.sh` → **PASS** (`byte-compile-error-on-warn` clean, then
  `Ran 960 tests, 960 results as expected, 0 unexpected`);
  `./scripts/lint.sh` → **PASS** (checkdoc clean; package-lint is not installed
  locally, so the wrapper skips the package metadata half as it documents);
  `make check-doc-drift` → **PASS** (exit 0, no drift).
  On the committed item worktree (`61effa2` + four PNGs + this summary),
  `BEADS_DIR=$HOME/workspace/beads.el ./scripts/gate.sh` → **PASS**
  (`Ran 932 tests, 932 results as expected`) and `./scripts/lint.sh` →
  **PASS**; the 932 vs 960 count is exactly the six source items' new tests
  that are not in this branch.
- **Visual inspection.** Both committed images were rendered and read back: the
  run detail shows the provenance rows, `attempts` block and failure line; the
  Runs view shows the all-time counts and the facts line. No rendering
  overflow, placeholder, or live-store value appears.

## Remaining Risks

- **Local integration, not merged main.** The images were captured from the
  union of the six closed source commits, not from `origin/main` (which still
  lacks them at `61effa2`). If the refinery's merged main resolves the same
  three overlaps differently in any rendered fact, the images must be
  regenerated with `./doc/screenshots/capture.sh --scope runs,run-detail` and
  re-verified. The row-8 live acceptance item should re-run
  `--verify run-detail,runs` on merged main as the closing check.
- **`--scope changed` in the item branch.** The committed item branch contains
  no run-view source change, so plain `--scope changed` selects nothing there
  until the six source merges land. Reproduce the selection with
  `GASCITY_SHOT_BASE=61effa2 ... --scope changed`, or use the explicit
  `--scope runs,run-detail` as recorded above.
- **Single-attempt fixture.** The fixture's failed review loop has one
  iteration, so the `attempts` block shows one row; multi-attempt stacking and
  the healthy `(none)` rendering are covered by
  `gascity-test-run-attempt-history*` ERT, not by the image.
- **No delta/web/live states in the image.** First paint has no `updated`
  stamp by design, `gascity-dashboard-url` is nil in the fixture, and the
  fixture has no live controller; those states are ERT- and live-acceptance
  covered rather than screenshot-covered.
- **Environment.** The committed bytes are from Emacs 31.1 (pgtk), ef-themes
  2.2.1, sway 1.11 and ImageMagick 6 on this host; a different stack may
  recompress differently, so regenerating elsewhere should be followed by the
  same `--verify` check before replacing the committed images.

## Coverage

| ID | Status |
| --- | --- |
| REQ-009 | covered |
| REQ-010 | covered |
