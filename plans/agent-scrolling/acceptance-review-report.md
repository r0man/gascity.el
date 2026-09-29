# Acceptance review — build-basic ga-jwtp (agent-scrolling starter factory review)

Reviewer: `gascity.el/gc.implementation-reviewer-1` (bead ga-m0ul, lane
`review.acceptance-review`), 2026-09-29.
Review target: the implementation worktrees listed in
`plans/agent-scrolling/review-context.md` (## Implementation Worktrees) —
NOT the launcher rig root `/home/roman/workspace/gascity.el`, whose
checkout is unchanged pending publish (expected, not a finding).

## Verdict

**approve** — the factory built the requested behavior, all acceptance
criteria have both unit and (where required) live evidence, and no
out-of-scope change was made. Findings below are advisory only; none is
required before publish.

## Worktree verification (all four anchors)

Each recorded worktree was verified to exist, be clean, and match the
recorded HEAD before review:

| WI | Worktree | HEAD | Clean |
|----|----------|------|-------|
| WI-1 | `worktrees/ga-7xhp` | `adbc52e` | yes |
| WI-2 | `worktrees/ga-lk9y` | `b884d9c` (aggregate chain tip incl. WI-4 lock-in) | yes |
| WI-3 | `worktrees/ga-lb0b` | `930dc5f` | yes |
| WI-4 | `worktrees/ga-q3vr` | `b088d2c` (8bde552 lock-in + summary artifact) | yes |

Aggregate chain in `worktrees/ga-q3vr`: `adbc52e → 01381c0 → 33ca47f →
71f38df → 8bde552 → b088d2c` on top of `main` at `36e4f6e`. The aggregate
diffstat touches exactly the in-scope files — `lisp/gascity-terminal.el`,
`lisp/gascity-custom.el`, `lisp/test/gascity-test.el`, `doc/gascity.texi`,
`docs/qa/2026-09-29-agent-scrolling-e2e.md`, and the per-item summary
artifacts under `plans/agent-scrolling/`. No dashboard, list,
session-detail, store, or reader file is touched; no out-of-scope change
found.

## Acceptance criteria disposition

1. **Ghostel/eat native wheel + D3 bottom-exit (REQ-001, REQ-005,
   REQ-012).** The ensure fragment (`gascity-terminal--mouse-ensure-script`)
   emits `set-option -t SESSION mouse on` and the exact D3 binding
   (`bind -T copy-mode WheelDownPane select-pane \; if -F
   '#{==:#{scroll_position},0}' 'send -X cancel' 'send -X -N 5
   scroll-down'`), riding the pre-step's existing single
   `gascity-terminal--run-async` round trip (D9 compliant). Live e2e
   evidence: QA report rows "fresh attach" (`mouse on`, `WheelDownPane`
   bound) and the wheel-notch rows ending in `pane_in_mode 0` at the
   bottom. Unit tests assert the fragment strings byte-for-byte.
2. **vterm/term scroll sub-mode + byte table (REQ-002, REQ-006,
   REQ-009).** `gascity-terminal--scroll-sequence` is pure and table-driven;
   the map binds C-p/C-n/C-v/M-v/next/prior/M-</M->/q/Esc; the adapter
   dispatch matches the design's per-backend split (vterm →
   `vterm-send-string`, term → `term-send-raw-string`, eat →
   `eat-self-input` per byte, ghostel → `ghostel-send-key` for control
   bytes / `ghostel-send-string` for escape sequences, per E6). No key
   reaches the pty except translated bytes (E9). Verified by
   `gascity-test-terminal-scroll-adapter-dispatch` and the live pass.
3. **Re-toggle self-healing + `[scroll]` marker (REQ-008, REQ-010).**
   `gascity-terminal-scroll-toggle` sends `q` first on re-toggle then
   re-enters — exactly the design's "State sync (optimistic +
   self-healing)" (DESIGN-agent-scrolling.md:95-99, "C-c s sends q first
   if it thinks it is active"). The live pass exercised the out-of-band
   `-X cancel` recovery. The marker rides the existing status segment and
   is tested both ways. See Advisory A below on one wording mismatch in
   the requirements artifact.
4. **Ensure gating + teardown restore (REQ-013).** With
   `gascity-terminal-ensure-mouse` nil, the attach script is byte-identical
   to the previous behavior (tested), and the teardown emits nothing
   mouse-related. The teardown also correctly restores the `status`
   override only when the mirror was installed
   (`gascity-terminal--status-mirrored`), while the mouse ensure is
   restored regardless — a subtle and correct separation. The e2e pass
   verified `kill-buffer` → `mouse` unset, `WheelDownPane` unbound.
5. **No new sync calls / non-blocking (D9).** The scroll mode sends raw
   bytes and spawns nothing; teardown rides `gascity-terminal--run-async`;
   the non-blocking verb guard in `lisp/test/gascity-store-test.el`
   needed no additions (confirmed — the aggregate diff does not touch it).
6. **ERT suite.** Whole-package gate run by this reviewer in
   `worktrees/ga-q3vr` (pwd verified via `pwd -P` before executing):
   `scripts/gate.sh` → **PASS**, compile clean with
   `--warnings-as-errors`, 748/748 tests, 0 unexpected. Targeted slices:
   `gascity-test-terminal` 36/36, `gascity-test-terminal-scroll` 9/9.
7. **Live e2e acceptance gate (REQ-014 and e2e halves).**
   `docs/qa/2026-09-29-agent-scrolling-e2e.md` records the full
   step/probe table over `/ssh:localhost:/home/roman/bright-lights`
   (fresh tmux Emacs, host-side `pane_in_mode`/`scroll_position` probes
   E4–E8 style), including the failure-driven `M-<`/`M->` lock to tmux's
   native `history-top`/`history-bottom` bytes. PASS per the report; the
   report also honestly records the eat-spawn environment limitation.
8. **Docs.** `doc/gascity.texi` gained the scroll sub-mode subsection
   (key table, self-healing re-toggle, `[scroll]` marker), the
   `gascity-terminal-ensure-mouse` `@defvr`, and the per-backend wheel
   paragraph; `make -C doc` builds clean in the worktree. The attach
   buffer commentary documents the D1 layer.

Coverage matrix REQ-001…REQ-014: all covered, each requirement traces to
at least one owning work item, unit test group, or the e2e pass (verified
against the decomposition's traceability table). The plan's five advisory
findings were all adopted: both wheel event aliases bound
(`<mouse-4>`/`<mouse-5>`/`<wheel-up>`/`<wheel-down>`, never installed for
ghostel/eat — plan-review finding 1); the unconditional `mouse on` is
documented as a deliberate deviation (texi/QA; finding 2); the bottom
jump is a fixed byte pair, not a feedback loop (finding 3); the
`[scroll]`-mirror dependency is documented (finding 4); the copy-mode-vi
limitation is documented in the manual's `~/.tmux.conf` note (finding 5).

## Advisory findings (non-blocking)

- **A — Requirements wording vs. implemented toggle semantics.**
  `requirements.md` (Behavior Requirements) says "`C-c s` while active
  exits cleanly (sends `q`, deactivates)", while the design doc (the
  artifact's own source of truth), the approved plan (step 8), and the
  implementation agree that a re-toggle sends `q` first **and
  re-enters** — the only recoverable semantics without a `pane_in_mode`
  resync. The implementation is correct per the design; the requirements
  artifact's sentence is the outlier. No action needed for this build;
  worth a one-line fix to the requirements artifact if it is ever
  revised.
- **B — Re-toggle `q` can reach the agent.** When the user re-toggles
  after an out-of-band copy-mode exit, the leading `q` lands on the
  agent's pty (the mode cannot know copy mode already ended). This is the
  documented cost of the optimistic design (DESIGN-agent-scrolling.md
  risk column, option d), not a defect; the async resync remains the
  designed future refinement if it ever matters.
- **C — WI-3 HEAD label drift in the context.** `review-context.md` lists
  the WI-3 worktree at `930dc5f` while the canonical summary cites
  `71f38df` for the WI-3 commit; both are in the aggregate chain
  (`930dc5f` is the WI-3 source-anchor head, `71f38df` the same change in
  the linear chain). Cosmetic bookkeeping inconsistency only; the chain
  itself is coherent and verified.

## Proof commands executed by this review

From `worktrees/ga-q3vr` (pwd verified with `pwd -P`):

- `scripts/gate.sh` → PASS (compile clean, 748/748, 0 unexpected)
- `eldev test gascity-test-terminal` → 36/36
- `eldev test gascity-test-terminal-scroll` → 9/9
- `make -C doc` → clean
