# Test Evidence Report — Starter review: test evidence (build-basic, workflow ga-jwtp)

Reviewer: `gascity.el/gc.gap-analyst-1` (bead ga-uotm), 2026-09-29.
Authority for command locations: `## Implementation Worktrees` in
`plans/agent-scrolling/review-context.md` (`gc.build.code_review_context_path`
on the workflow root). Every proof command below was executed with
`cd "$WORKTREE"`, `pwd -P` verified equal to the listed worktree, never from
the launcher rig root.

## Verdict: `code_review.test_evidence_verdict=approve`

Every accepted task recorded an intended behavior, a first verification
command, a proof command, changed files, and remaining risks; every recorded
command was re-executed from its implementation worktree and passed with the
recorded outcome; the commands cover the acceptance criteria claimed by the
requirements and plan (REQ-001…REQ-014). No missing proof and no product
defects were found.

## Worktree state verification

All four worktrees exist, are clean, and their HEADs match the context file:

| Worktree | Context HEAD | Actual HEAD | Status |
| --- | --- | --- | --- |
| `worktrees/ga-7xhp` (WI-1) | `adbc52e` | `adbc52e2221af…` | clean |
| `worktrees/ga-lk9y` (WI-2) | `b884d9c` | `b884d9c9c5afa…` | clean |
| `worktrees/ga-lb0b` (WI-3) | `930dc5f` | `930dc5fbc60f…` | clean |
| `worktrees/ga-q3vr` (WI-4) | `b088d2c` | `b088d2caf766…` | clean |

Artifact hashes in the canonical implementation summary's `trace.upstream`
match the final trees byte-for-byte: `docs/qa/2026-09-29-agent-scrolling-e2e.md`
= `2e5abb05…`, `doc/gascity.texi` = `41b153b7…`,
`lisp/gascity-terminal.el` (WI-4 trace) = `5fecaf5c…`.

## Per-item evidence re-execution

### WI-1 — ga-7xhp (P0: tmux mouse ensure + bottom-cancel binding; REQ-001, REQ-005, REQ-012, REQ-013)

- Recorded first verification: `eldev test gascity-test-terminal` (27/27).
  **Re-run from `worktrees/ga-7xhp`: PASS — Ran 27 tests, 27 as expected,
  0 unexpected.**
- Recorded proof: `scripts/gate.sh` → compile clean, 739/739.
  **Re-run: PASS — Ran 739 tests, 739 as expected, 0 unexpected; gate PASS.**
- Coverage check: the fragment tests exist and assert the acceptance
  criteria — `gascity-test-terminal-mouse-ensure-script` (REQ-005 `mouse on`
  + `WheelDownPane`), `gascity-test-terminal-attach-script-mouse` (custom
  t/nil emission, REQ-001), `gascity-test-terminal-status-teardown-restores-mouse`
  (REQ-013 restore). REQ-012's exit-at-bottom `if -F '#{==:#{scroll_position},0}'`
  fragment is asserted in the ensure-script test.

### WI-2 — ga-lk9y (P1: scroll sub-mode + translation table; REQ-002, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010)

- Recorded first verification: `eldev test gascity-test-terminal-scroll`
  (6/6 at the item's own head `33ca47f`).
  **Re-run from `worktrees/ga-lk9y` (aggregate tip `b884d9c`): PASS —
  Ran 9 tests, 9 as expected** (the item's 6 plus the WI-3 wheel tests the
  aggregate tip carries).
- Recorded proof: `scripts/gate.sh` → compile clean, 745/745 at `33ca47f`.
  **Re-run at the current tip: PASS — Ran 748 tests, 748 as expected,
  gate PASS.** The 745 → 748 drift is the documented WI-4 table-lock
  amendment (the context file itself states the worktree head is the
  aggregate chain tip including the WI-4 lock-in), not a failure.
- Coverage check: `gascity-test-terminal-scroll-sequence` (REQ-002 table),
  `-adapter-dispatch` incl. ghostel control/escape split (REQ-006),
  `-unknown-backend` graceful refusal (REQ-007), `-toggle` self-healing
  `q`-first re-entry (REQ-008), `q`/Esc deactivate (REQ-009),
  `-status-marker` `[scroll]` exactly while active (REQ-010). The locked
  table is asserted: `(gascity-terminal--scroll-sequence ?\M-<) → "\e<"` /
  `?\M-> → "\e>"`, matching `lisp/gascity-terminal.el`.

### WI-3 — ga-lb0b (P2: wheel translation for non-reporting backends; REQ-003, REQ-004, REQ-011)

- Recorded first verification: `eldev test gascity-test-terminal-scroll`
  (11/11). **Re-run from `worktrees/ga-lb0b`: PASS — Ran 11 tests,
  11 as expected, 0 unexpected.**
- Recorded proof: `scripts/gate.sh` → compile clean, 750/750.
  **Re-run: PASS — Ran 750 tests, 750 as expected, 0 unexpected; gate PASS.**
- Coverage check: `-backend-reports-mouse` (REQ-004 predicate: ghostel/eat
  report, vterm/term/unknown do not), `-wheel-sequence` (REQ-011 first
  notch = entry bytes + 3 × C-Up, later notches = C-Up/Down only),
  `-wheel-map-selection` / `-wheel-dispatch` / `-wheel-no-interference`
  (REQ-003 notch arithmetic; REQ-004 reporting backends send nothing).

### WI-4 — ga-q3vr (P3: docs, live TRAMP e2e pass, gate; REQ-014 + e2e halves of REQ-001/002/008/012/013)

- Recorded proof: `scripts/gate.sh` → compile clean, 748/748 (authoritative
  final count). **Re-run from `worktrees/ga-q3vr`: PASS — Ran 748 tests,
  748 as expected, 0 unexpected; `>>> gate: PASS (compile clean + tests
  green)`.**
- Docs build: recorded `make -C doc` clean. **Re-run: clean full rebuild
  after `make -C doc clean`; `doc/gascity.info` produced (124,518 bytes).**
- Live e2e evidence: `docs/qa/2026-09-29-agent-scrolling-e2e.md` present in
  the final tree with the full step/probe table — copy-mode entry, line/
  page/top/bottom scrolling, wheel notch arithmetic, self-healing re-toggle,
  ensure/teardown lifecycle — each row mapped to a REQ half claimed by this
  item. **Hygiene re-verified live:** `tmux -L bright-lights list-sessions`
  shows only the city's own sessions (`core__control-dispatcher-bl-pbib`,
  `mayor`); the disposable `scroll-e2e` session was torn down as claimed.
  The documented deviation (M-</M-> locked to `\e<`/`\e>` instead of the
  bead's original mechanisms) is recorded in the QA report and reflected in
  the tests — acceptable, the bead deferred the mechanism to the live pass
  per requirements Open Question 1.
- Artifact gate: the canonical implementation summary
  (`plans/agent-scrolling/implementation-summary.md`, schema
  `gc.build.implementation-summary.v1`) records
  `GC_BEAD_ID=… build-artifact-valid.sh` → "build artifact valid"; its
  trace hashes were independently re-verified above.

## Acceptance-criteria coverage summary

| REQ | Claimed by | Evidence re-verified |
| --- | --- | --- |
| REQ-001 | WI-1 + WI-4 e2e | fragment tests 27/27; QA report entry |
| REQ-002 | WI-2 + WI-4 e2e | scroll-sequence/toggle tests; QA `pane_in_mode 1` |
| REQ-003 | WI-3 | wheel-notch/dispatch tests |
| REQ-004 | WI-3 | backend-reports-mouse + no-interference tests |
| REQ-005 | WI-1 + WI-4 e2e | mouse-ensure script tests; QA fresh-attach probes |
| REQ-006 | WI-2 | adapter-dispatch (ghostel split) tests |
| REQ-007 | WI-2 | unknown-backend graceful refusal test |
| REQ-008 | WI-2 + WI-4 e2e | toggle self-healing test; QA re-toggle probe |
| REQ-009 | WI-2 | q/Esc deactivate tests |
| REQ-010 | WI-2 | status-marker test |
| REQ-011 | WI-3 | wheel-sequence first-notch entry test |
| REQ-012 | WI-1 + WI-4 e2e | bottom-cancel fragment; QA wheel-down exit probe |
| REQ-013 | WI-1 + WI-4 e2e | teardown restore test; QA kill-buffer probes |
| REQ-014 | WI-4 | gate 748/748 + docs build + QA report present |

## Findings (non-blocking, for the record)

1. **WI-2 proof count drift is documented, not a defect.** The item's
   recorded 745 was true at its own head; the worktree now stands at the
   aggregate tip `b884d9c` with the WI-4 amendments (748). The context
   file pre-declares this; no action needed.
2. **Parallel gate runs contend on Eldev state.** Running three
   `scripts/gate.sh` invocations concurrently across sibling worktrees
   failed one compile step (`Child Eldev process for local sources 'beads'
   exited with error code 1`); serially it passes. Environment contention,
   not a product issue; future reviewers should run gates serially.
3. **Remaining risks in the summaries are honest and correctly scoped** to
   the publish stage (commits not yet on `main`), live-pass backend coverage
   (ghostel/eat not re-driven; eat spawn bug upstream), and the documented
   tmux-side limitations. None are test-evidence gaps.

No missing proof was found; the fix lane needs no action from this lane.
