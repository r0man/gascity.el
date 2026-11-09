---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-yes6q
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
    - path: beads/ga-b384r
      hash: "bead:ga-b384r"
    - path: plans/run-view-work-spine/requirements.md
      hash: "sha256:745731192aa80e492e0b33bdeb3fb49daeb022ad66839d23366fd2ea6ff5289d"
      ids: &ids
        - REQ-007
        - REQ-010
        - REQ-011
        - REQ-012
    - path: plans/run-view-work-spine/implementation-plan.md
      hash: "sha256:54eea7c01c944a3dcbab1dcf941deda57bc3e2a18331b999d3fdac64340b5527"
    - path: plans/run-rendering-alternatives/design.md
      hash: "sha256:823b7c92df7d88a5562176d0b29be42c527eee117b52f5ace83c78b7d255ed50"
    - path: lisp/gascity-runs.el
      hash: "git:5c63beb0fff98ec9f784909e4465928afedf31af"
    - path: lisp/test/gascity-runs-test.el
      hash: "git:5c63beb0fff98ec9f784909e4465928afedf31af"
  coverage:
    - id: REQ-007
      status: covered
    - id: REQ-010
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-012
      status: covered
---

# Runs card: name each run's source business bead

## Summary

Each Runs card is now three lines (plan §2.3, design §4.3 phase 2). Line 1
names the run's source business bead — the single tracked member of the
root's `gc.var.convoy_id` input convoy — with its id and status right-aligned,
or says `source loading…`, `source unavailable` or `(no source)` honestly.
Line 2 carries the run's identity (root id, formula, rig, time) with the
labeled `N/M steps` and `N beads` counts. Line 3 carries the work: the step
ladder, labeled `N/M deliverables`, the active step label and the state tail
(a word as well as the glyph).

The source is read through one async, TTL'd, deduped, visible-first
`("convoy" "status" CONVOY)` store read per visible run. The read is started
from a vui effect over the visible convoy ids, never on the render path; a
buffer-local cache holds `:loading` / `:unavailable` / the resolved plist and
bounds re-reads. `g` clears it and re-reads the visible ids once. The whole
card keeps one `gascity-bead` (the run root), so `RET`, `SPC` and the `/`
filter behave exactly as before.

`gascity-runs-summary` gains `:units`, `:deliverable-progress` (`"7/8"`,
denominator `gc.drain_count` when present), `:deliverable-counts` and
`:beads`; `gascity-runs-context` computes the partition once and adds
`:parts`, `:sources`, `:visible-runs` and `:visible-convoys`, so the renderer
and the source effect agree on what is visible.

This worktree was seeded by `prepare-worktree` with the dependency work
(WP-0/WP-1, beads ga-2i1hs and ga-4hsxy); this commit carries that stack plus
WP-2.

## Intended Behavior

- Two active `build-basic` runs are distinguishable by their source title/id;
  a card names the formula exactly once.
- A cold read renders `source loading…` and the rest of the card immediately;
  a failed or timed-out read renders `source unavailable`; a run without an
  input convoy renders `(no source)`. No value is guessed.
- A drain run shows `7/8 deliverables` beside its ladder; a run without drain
  members omits the deliverable phrase and keeps its state word.
- Only visible convoys are read: the Active/Waiting and Failed sections plus
  the closed history pages `H`/`+` show. Off-screen history is read when it
  scrolls into view on the next effect.
- No `gc` call, no TRAMP I/O on render, redisplay, timers or eldoc; the card
  remains a pure function of the render context.

## Changed Files

- `lisp/gascity-runs.el` — three-line card, source cache/effect, visible-run
  and visible-convoy helpers, summary counters, context partition.
- `lisp/test/gascity-runs-test.el` — seven card-source ERT cases (ready, multi,
  loading, loading-is-async, unavailable, no-source, deliverable progress,
  visible-only effect) and the updated layout assertions.
- `lisp/test/gascity-subruns-test.el` — the nested Runs card assertion follows
  the three-line shape.

## Verification

- First verification command (red before the implementation, green after):
  `find lisp -name '*.elc' -delete && make check` —
  observed: 17 unexpected failures before the implementation, then
  `Ran 1072 tests, 1072 results as expected, 0 unexpected`.
- Final proof command: `scripts/gate.sh` — observed
  `>>> gate: PASS (compile clean + tests green)` (byte-compile with
  warnings-as-errors and the whole ERT suite).
- `scripts/lint.sh` — observed clean checkdoc/package-lint run (the local
  environment lacks package-lint, as documented; the CI job installs it).

## Remaining Risks

- Card read fan-out: one async process per visible run, as the design accepts.
  Mitigated by the visible window, the store's TTL and dedupe, and the
  buffer-local cache; a `g` re-reads the visible ids once.
- The source cache is per buffer and refreshed on `g`/live re-read; a live
  convoy change repaints through the store's event invalidation on the next
  visible re-read, not by polling.
- The interactive tmux pass (local `emacs-city` and
  `/ssh:localhost:~/bright-lights`) is recorded by the WP-3 documentation
  bead; this bead's ERT and gate evidence is green.

| ID | Status |
| --- | --- |
| REQ-007 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
