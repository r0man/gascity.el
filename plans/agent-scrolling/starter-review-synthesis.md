# Starter review synthesis — build-basic ga-jwtp (agent-scrolling)

Synthesizer: `gascity.el/gc.review-synthesizer-1` (bead ga-gizu,
`gc.step_id=review.synthesize-review`), 2026-09-29. Fan-in of the three
starter review lanes for the agent-scrolling implementation (commits
`36e4f6e..b088d2c`, aggregate tip in `worktrees/ga-q3vr`):

- Acceptance and correctness — ga-m0ul, verdict **approve**
- Test evidence — ga-uotm, verdict **approve** (`code_review.test_evidence_verdict=approve`)
- Simplicity and maintainability — ga-zxf6, verdict **approve**

Worktree authority: `## Implementation Worktrees` in
`plans/agent-scrolling/review-context.md` (the file named by
`gc.build.code_review_context_path` on the root bead). The launcher
checkout `/home/roman/workspace/gascity.el` is unchanged pending publish;
that is expected and is not a finding.

## Verdict

**approve** — no required fixes, no missing evidence. All three lanes
approved independently; all acceptance criteria REQ-001…REQ-014 have unit
and (where required) live e2e evidence, re-executed from the owning
worktrees by the test-evidence lane. The residual items below are
advisory; none blocks the review loop from approving or the publish step.

Classification summary:

| Classification | Count | Items |
| --- | --- | --- |
| Required fix | 0 | — |
| Missing evidence | 0 | — |
| Residual risk | 9 | R1–R9 below |

## Required fixes

None. All three lanes found nothing that must change before approval.

## Missing evidence

None. Every recorded proof command was re-executed from its implementation
worktree and passed with the recorded outcome (gate PASS, 748/748 tests,
0 unexpected at `worktrees/ga-q3vr` b088d2c; docs build clean). The one
coverage gap that exists — ghostel/eat not re-driven in the live pass —
is a documented residual risk (R4), not a missing proof: the live e2e
report `docs/qa/2026-09-29-agent-scrolling-e2e.md` honestly records the
limitation, and the affected paths carry dedicated unit tests.

## Residual risks

Each item keeps its source lane. Anchors: code findings name the file in
the implementation worktree that owns it; artifact findings name the
launcher artifact-root file (no implementation worktree owns those).

- **R1 · Re-toggle `q` can reach the agent's pty** (lanes: acceptance-B,
  test-evidence-3; deduped). After an out-of-band copy-mode exit, the
  leading `q` of a re-toggle lands on the agent pty — the documented cost
  of the optimistic design (DESIGN-agent-scrolling.md risk column,
  option d), not a defect.
  Anchor: `gascity-terminal-scroll-toggle`,
  `lisp/gascity-terminal.el:948` in `worktrees/ga-q3vr` (HEAD b088d2c;
  byte-identical code at `worktrees/ga-lk9y` b884d9c).
  Disposition: accept as designed; the async `pane_in_mode` resync
  remains the designed future refinement if it ever matters. No action
  for this build.

- **R2 · Publish-stage exposure** (lane: test-evidence-3). All commits
  live only in the source-anchor worktrees; nothing is on `main` yet.
  Anchor: aggregate chain `adbc52e → 01381c0 → 33ca47f → 71f38df →
  8bde552 → b088d2c` on top of `main` 36e4f6e, tip in
  `worktrees/ga-q3vr` (HEAD b088d2c).
  Disposition: expected at this stage; the publish step (`ga-zkq6`) owns
  the merge/push. No review action.

- **R3 · Requirements artifact wording drift on re-toggle semantics**
  (lane: acceptance-A). `requirements.md` says "`C-c s` while active
  exits cleanly (sends `q`, deactivates)" while the design doc, approved
  plan, and implementation all agree a re-toggle sends `q` **and
  re-enters** — the implementation is correct per the design; the
  requirements sentence is the outlier.
  Anchor: Behavior Requirements section of
  `plans/agent-scrolling/requirements.md` — launcher artifact root
  (`/home/roman/workspace/gascity.el/plans/agent-scrolling/`), no
  implementation worktree owns this file.
  Disposition: one-line fix to the requirements artifact if it is ever
  revised; not required for this build.

- **R4 · Live-pass backend coverage gap: ghostel/eat** (lanes:
  test-evidence-3, acceptance-§7; deduped). The live e2e pass did not
  re-drive ghostel/eat; the eat spawn bug is upstream. Paths are covered
  by unit tests (`-adapter-dispatch` ghostel control/escape split,
  `-backend-reports-mouse`, wheel tests).
  Anchor: `docs/qa/2026-09-29-agent-scrolling-e2e.md` (deviation record)
  and `lisp/gascity-terminal.el` in `worktrees/ga-q3vr` (HEAD b088d2c).
  Disposition: accept and document; revisit if a live ghostel/eat pass
  becomes cheap.

- **R5 · tmux-side limitations** (lanes: test-evidence-3, acceptance-§
  coverage disposition). Known tmux limitations (e.g. copy-mode-vi
  interplay) are documented in the manual's `~/.tmux.conf` note rather
  than worked around in code.
  Anchor: `doc/gascity.texi` (scroll sub-mode section) in
  `worktrees/ga-q3vr` (HEAD b088d2c).
  Disposition: accept as documented.

- **R6 · Bookkeeping drift in review artifacts** (lanes: acceptance-C,
  test-evidence-1; deduped as one class). Two harmless label drifts:
  (a) `review-context.md` lists WI-3 at `930dc5f` while the canonical
  summary cites `71f38df` (both in the aggregate chain — source-anchor
  head vs linear-chain position); (b) WI-2's recorded gate count 745 was
  true at its own head `33ca47f`, while the aggregate tip now stands at
  748 — pre-declared by the context file. Cosmetic only; the chain is
  coherent and verified.
  Anchor: `plans/agent-scrolling/review-context.md` and
  `plans/agent-scrolling/implementation-summary.md` — launcher artifact
  root; no implementation worktree owns these files.
  Disposition: no action; fix opportunistically if the artifacts are
  ever regenerated.

- **R7 · Parallel gate runs contend on Eldev state** (lane:
  test-evidence-2). Three concurrent `scripts/gate.sh` runs across
  sibling worktrees failed one compile step; serially they pass.
  Environment contention, not a product issue.
  Anchor: process observation — applies to any worktree
  (`worktrees/ga-*`), no product file owns it.
  Disposition: reviewers run gates serially; optionally note in
  contributor docs later.

- **R8 · Duplicated escape bytes for C-Up/C-Down** (lane: simplicity-1).
  `"\e[1;5A"` / `"\e[1;5B"` appear both in
  `gascity-terminal--scroll-sequence` (`lisp/gascity-terminal.el:846-847`)
  and inline in `gascity-terminal-scroll-wheel` (same file, :1009). If a
  tmux version quirk ever changes them, two places must move together.
  Anchor: `lisp/gascity-terminal.el` in `worktrees/ga-q3vr` (HEAD
  b088d2c; byte-identical at `worktrees/ga-lk9y` b884d9c).
  Disposition: smallest useful fix — hoist the two sequences into
  `defconst`s next to `gascity-terminal--copy-mode-entry` (:822) and use
  them in both spots. Optional follow-up; the fix lane may take it
  without another planning pass.

- **R9 · Cosmetic naming/style debt in `gascity-terminal.el`** (lane:
  simplicity-2+3; deduped). (a) `--status-install` / `--status-teardown`
  now also install/restore the mouse ensure, not just the status mirror
  (`lisp/gascity-terminal.el:684,708`); a future rename to e.g.
  `--attach-overrides-install` would make the call site self-describing.
  (b) One doubled blank line between `gascity-terminal--scroll-wheel-first`
  and `gascity-terminal-scroll-toggle` (:946-947) where the file
  otherwise uses single blank lines. Docstrings already state the real
  duty, so this is cosmetic.
  Anchor: `lisp/gascity-terminal.el` in `worktrees/ga-q3vr` (HEAD
  b088d2c).
  Disposition: optional follow-up only; no action required.

## For the fix lane

Nothing in R1–R9 is required before approval. If the fix lane
(`ga-prcc`, Apply starter review findings) takes optional items, the
highest-value one is **R8** (hoist the C-Up/C-Down byte constants in
`lisp/gascity-terminal.el` of `worktrees/ga-q3vr`), then **R9**; all
worktree-resolved paths above are already scoped to the correct
implementation worktree, so no additional planning pass is needed.