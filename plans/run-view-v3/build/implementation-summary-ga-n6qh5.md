---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-if2yk
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
    - path: beads/ga-n6qh5
      hash: bead:ga-n6qh5
      title: "Run view: stacked iteration/attempt history (REQ-001)"
      ids:
        - REQ-001
    - path: plans/run-view-v3/build/implementation-plan.md
      hash: sha256:6767d03a6a7844226d19ff898e2e3dc26c0c06ac2ee8b3cbda44fc67ef54e5cb
      title: "Approved plan §A (attempt history), task-map step 1"
    - path: plans/run-view-v3/build/requirements.md
      hash: sha256:319e8e225757eefa22607a21aab0a3acb8a607cb364da9d8e9eb9c1f427d789d
      title: "Approved requirements (REQ-001, AC1)"
    - path: lisp/gascity-run.el
      hash: sha256:75e3ea47b3b99f8178ee4bd9ac2a3e3cff8e44db00a0b83faeaa559a9ac6dc67
    - path: lisp/test/gascity-runs-test.el
      hash: sha256:1a28c4473c64225081a0f9567b83db02e25329451f877c0bc5835bc30788a0a8
  coverage:
    - id: REQ-001
      status: covered
---

# Implementation Summary: Run view v3 §A — stacked iteration/attempt history (ga-n6qh5)

## Summary

Implemented plan §A (task-map step 1) of the approved run-view-v3 plan in
the item worktree `/home/roman/workspace/gascity.el/worktrees/ga-n6qh5`,
in `lisp/gascity-run.el` and `lisp/test/gascity-runs-test.el`.

A step's inspector drawer now stacks one row per iteration/attempt bead
beneath its existing `attempt` line: attempt number, outcome, worker,
relative time, and the failure class/reason (`(none)` for a healthy
attempt).  The collapsed step row keeps the v2 `iter N` summary, and the
whole block is derived from CTX's already-loaded run-beads index — no new
`gc` read on render, redisplay, timers, or eldoc.

No user-facing key, option, generator input, or doc table changes in this
slice; the manual/key-registry/NEWS/screenshot work is task-map step 7a/7b.

## Intended Behavior

- **Discovery (`gascity-run--attempt-beads`).** From `CTX`'s run graph, a
  bead qualifies when it is not the step, names a numeric attempt
  (`gc.attempt`, else `gc.iteration`), and either:
  - its `gc.logical_bead_id` equals the step id (authoritative; the only
    link for a nested loop's iterations), or
  - its step path is a direct `STEP-PATH.iteration.N` /
    `STEP-PATH.attempt.N` child (fallback for older payloads without the
    logical id; exactly one extra segment, so a nested formula step below
    an iteration is never an attempt).

  Rows are deduplicated by construction and sorted by attempt, then
  iteration, then id.
- **Rendering (`gascity-run--attempt-lines`).** One dim `attempts`
  heading, only when at least one attempt exists, then one fixed-column
  row per attempt: number (3), outcome (9), worker (18), relative time
  (9, `closed_at` else `updated_at` via `gascity-ui-time`), failure
  (20, `gascity-ui-truncate` with the full text in `help-echo`).  A
  worker carries `●`/`○` only when the render has a live-session payload;
  otherwise the assignee's parsed role is shown.
- **Healthy attempts.** Only an attempt whose `gc.outcome` is `fail`
  reads a class/reason (through `gascity-runs--failure-info`, including
  its close-reason fallback); every other attempt reads `(none)` even
  when it carries a close reason.  `gascity-run--failure-string` is
  shared with the drawer's existing `failure` line, so both use the same
  `class: reason` shape.
- **Drawer order.** `step`, `attempt`, the attempt block, `worker`,
  `artifacts`, `events`, `failure`; the step and collapsed-row shapes are
  unchanged.
- **Purity.** Every fact comes from CTX's `:index`/beads payload,
  `:sessions`, and `:now`; the only helper that touches the filesystem in
  the drawer remains the pre-existing local artifact stat.

## Changed Files

- `lisp/gascity-run.el` — new `gascity-run--attempt-number`,
  `gascity-run--iteration-number`, `gascity-run--attempt-path-p`,
  `gascity-run--attempt-beads`, `gascity-run--attempt-line`,
  `gascity-run--attempt-lines`, the shared `gascity-run--failure-string`,
  the drawer wiring, and the module commentary.
- `lisp/test/gascity-runs-test.el` — four new ERT tests
  (`gascity-test-run-attempt-history`, `-drawer`, `-nested`, `-empty`)
  and the updated line indexes in `gascity-test-run-inspector-normal`
  (the block adds two lines to that synthetic drawer).
- `plans/run-view-v3/build/implementation-summary-ga-n6qh5.md` — this
  artifact.

## Verification

- **First verification command (focused ERT, red first then green).**
  Run from the worktree root with the dev load path:
  `EMACSLOADPATH="$HOME/workspace/beads.el/lisp:$HOME/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0:$EMACSLOADPATH:" emacs --batch -Q -L lisp -L lisp/test -l lisp/test/gascity-runs-test.el --eval '(ert-run-tests-batch-and-exit "gascity-test-run-attempt")'`
  → **PASS** (4/4: rows/order/outcome/worker/time/`(none)`, drawer
  placement, nested `gc.logical_bead_id` link, empty step).
  The same command failed before the implementation with
  `void-function gascity-run--attempt-beads` (red).
- **Final proof command.** `BEADS_DIR="$HOME/workspace/beads.el"
  ./scripts/gate.sh` → **PASS**: byte-compile with warnings as errors
  clean, `Ran 936 tests, 936 results as expected, 0 unexpected`.
  `./scripts/lint.sh` → **PASS** (checkdoc clean; package-lint is not
  installed locally and is skipped, as the wrapper documents).
- **Interactive acceptance (tmux, non-graphical Emacs 31.1).** Mounted
  the `be-bn2` fixture detail in `emacs -nw` inside tmux with the
  requirements drawer open and captured the pane: it shows
  `│ attempts` followed by
  `│   1   pass      requirements-plan…    Sep 24 (none)`, with the
  drawer's worker/artifacts/events/failure lines intact below.
- **Design constraints checked.** No new `gc` read on render (the store
  payload only); every attempt row is 65 columns or less (pinned by
  `gascity-test-run-attempt-history`); the whole package byte-compiles
  with warnings as errors in the same gate run.

| ID | Status |
| --- | --- |
| REQ-001 | covered |

## Remaining Risks

- **Discovery depends on the payload's links.** A payload that carries
  neither `gc.logical_bead_id` nor a direct `iteration.N`/`attempt.N`
  child path shows no history; this matches the documented fallback and
  no backfill is attempted (out of scope).
- **Fixed-width truncation.** A very long worker or failure text is cut
  at the pinned widths, with the full text in `help-echo`; a step nested
  deeper than the current tree (five levels) could be nearer the
  78-column limit, though no existing formula reaches it.
- **Healthy close reasons are hidden.** A passing attempt's close reason
  is deliberately not rendered in the failure column; if a future
  requirement wants it, the row needs another column.
- **Docs/screenshots pending by design.** The manual, key registry,
  NEWS, generated tables, and deterministic screenshots are task-map
  steps 7a/7b; this slice adds no key or user option and no
  doc-registry input, so `make check-doc-drift` is unaffected (it passes
  in the gate).
- **Nested-loop UX.** Attempt rows are grouped under the step drawer, and
  the older nested loop's own iteration still renders as a nested step
  row; the two are visually distinct but a future tree toggle (§E3) must
  keep them so.
