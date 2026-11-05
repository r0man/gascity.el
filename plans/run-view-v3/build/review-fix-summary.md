# run-view-v3 — starter review fixes (`build-basic`, root `ga-hsbfs`)

- Fix bead: `ga-qizrn` (step `review.build-basic-review-loop.iteration.1.review.apply-review-findings`)
- Review synthesis: `plans/run-view-v3/build/review-report.md` (`ga-16vdd`), verdict `iterate`
- Launcher rig root (not the reviewed code): `/home/roman/workspace/gascity.el`
- Implementation anchor used for this pass: the integration worktree below,
  resolved from the review context's `## Implementation Worktrees` section
  (each feature anchor's `worktree` is merged into it; no launcher checkout
  was edited)
- Integrated branch: `run-view-v3-integration`
- Worktree: `/home/roman/workspace/gascity.el/worktrees/rv3-integration`
- Code HEAD this pass ran on: `2192c4dd3e113f2848acd94189685f407aeb162e`
- Code tree: `01748982146a1fce20bf62203330de5c69c7a42c`
- Branch tip after the report commit is one docs-only commit above it; the
  tree hash above is the verified shipping code tree.
- QA report: `docs/qa/2026-11-05-run-view-v3.md`

Verdict after this pass: **`done`** — acceptance, test evidence and
simplicity all approve on the integrated tree.

## R1 — integrate the eight commits on one branch

Created the worktree from `61effa2` and merged in plan order: `880b134`
(fast-forward), `32975ca`, `d43c515`, `8709d1e`, `f5e26c6`, `62a2f0b`,
`ee62fd4`, `a371e2c`. The `/tmp` scratch tree was **not** reused.

Conflicts resolved (both synthesis decisions preserved):

- `lisp/gascity-run.el` mode docstring: merged the member-row paragraph
  (REQ-007) with the artifacts/web paragraph (REQ-002/004) and the `T`
  sentence (REQ-008).
- `lisp/gascity-run.el` step rows: kept the `gascity-run--worker` derivation
  and the delta `changed` flag (REQ-005) **and** the `needs-note` column
  (REQ-008); the delta-applied `detail` cell feeds the merged `left`.
- `lisp/gascity-run.el` app context: `:tree` (REQ-008) beside `:control`, and
  the sticky-delta advance retained.
- `lisp/gascity-runs.el` history row: the delta glyph/progress cells and the
  facts line now share one object/thing, and the facts line's **worker cell**
  keeps `gascity-changed` while the line stays dim (REQ-005 promise on both
  card lines).
- `lisp/gascity-runs.el` title: `gascity-runs--title-right` combines the
  freshness stamp **and** the key hint — full hint when it fits beside the
  stamp, else the compact `H  /`, else the stamp alone; neither replaces the
  other.
- `lisp/test/gascity-runs-test.el`: both appended test blocks kept (attempt
  history and member rows).

## R2 — regenerate the tracked doc tables

`make regen-doc-tables` on the union adds the four missing `run-detail` rows
(`o`, `B`, `Y`, `T`) to `doc/generated/keys.texi` (+16 lines, no other diff).
`make check-doc-drift` exits 0 on the integrated tree.

## R3 — the planned zero-spawn ERT test

New `gascity-test-run-detail-actions-are-io-free` in
`lisp/test/gascity-store-test.el`: renders the failed-run fixture, then
answers `w`, `I`, `!`, `T`, `o`, `B` and `Y` with
`gascity-reader-run`/`-read`/`-run-async` armed, store fetches counted and
`process-file`/`call-process`/`make-process` signalling. The only read is the
inspector's pre-existing recent-events drawer read; the only host actions are
the browser and the artifact visit (stubbed and asserted). Fails if any verb
starts a process or a run/bead read.

Fresh run before this test: 960; after: **961/961**.

## R4 — one sticky-delta state machine

`gascity-ui-apply-delta` now owns the previous-facts/changed-ids/last-update
refs and the advance rule; `gascity-run-app` and `gascity-runs-app` call it
and keep no local copy. Both delta test sets stay green.

## R5 — one failure formatter, one run-failure derivation

- `gascity-ui-failure-text` (optional empty label: `(none)` for inspector and
  attempt lines, `-` for table cells) replaces `gascity-run--failure-string`
  and `gascity-runs--failure-text`.
- `gascity-runs--run-failure` returns the `(CLASS . REASON)` pair (failed step
  first, then failed beads) for the Runs facts line and the drain-member
  drawer. Labels unchanged.

## E2 — screenshots and counts on the shipping tree

`doc/screenshots/capture.sh --verify run-detail,runs` → byte-identical for 2
images; isolation OK (48 non-selected images untouched). Sizes match the
committed `a371e2c` images: run-detail-dark 32123/34070, runs-dark
12288/13956. Gate counts: 961/961; lint exit 0; `make -C doc` exit 0;
`make check-doc-drift` exit 0.

## E1 — live acceptance

Executed against the live `ga-hsbfs` run, locally and over TRAMP; the nine
sections, the observed evidence and the residual risks are in
`docs/qa/2026-11-05-run-view-v3.md`. No `BLOCKED` sections remain and no
workflow was mutated.
