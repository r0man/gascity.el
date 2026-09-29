# Plan Review — implementation-plan.md (build-basic, workflow ga-jwtp)

Reviewer: gc.review-synthesizer-1 (bead ga-6bqx), 2026-09-29.
Reviewed artifact: `plans/agent-scrolling/implementation-plan.md` (schema
gc.build.plan.v1, status approved, attempt 1) against
`plans/agent-scrolling/requirements.md` (REQ-001–REQ-014),
`docs/DESIGN-agent-scrolling.md`, and the current tree state of
`lisp/gascity-terminal.el` / `docs/DESIGN-write-actions.md` §10.

## Verdict

**pass** — no blockers for decomposition. Zero required changes; four
advisory findings below should ride along to the implementer (they can be
resolved inside the implementation beads without re-opening the plan).

## Design review

- **Layer fidelity.** The plan implements the design's D1/D2/D3 layers
  exactly: tmux-side mouse ensure + WheelDownPane bottom-exit binding (D2/D3)
  as pre-step fragments; `gascity-terminal-scroll-mode` with the E6/E7 byte
  table (D1); wheel translation only for non-reporting backends. Nothing in
  the plan contradicts a design rejection (no side-channel `send-keys` per
  notch, no non-alt-screen re-attach, no Emacs-buffer scrolling, no async
  resync in v1 — all correctly in Non-Goals).
- **§10 keybinding check.** `C-c s` in `gascity-terminal-attach-map` is
  collision-free: the reserved map in DESIGN-write-actions.md §10 governs
  *view* keymaps (base `]` `[` `G` `S` `RET` `q`; common `g` `/` `b` `d` `t`
  `i` `s` `r` `R` `N` `K` `w` `D` …), and the attach map owns only the
  `C-c` prefix (`C-c b` today; compose's `C-c C-c`/`C-c C-k` live in a
  different buffer class). No conflict.
- **Repository grounding verified against the tree.** The plan's claims
  about the current system check out in `lisp/gascity-terminal.el`:
  `gascity-terminal--attach-script` already takes `&rest opts` plists (the
  P0 fragments slot in as new opts), `gascity-terminal--status-teardown`
  already emits the `set-option -u` restore pattern the P0 teardown
  mirrors, and the marker rides the existing
  `gascity-terminal--status-string` buffer-local. Backend APIs named by the
  adapter exist: `vterm-send-string`, `term-send-raw-string`,
  `eat-self-input`, and ghostel's `ghostel-send-key`/`ghostel-send-string`
  (ghostel 0.39.0 in Guix) — the E6 control-byte/escape-sequence split is
  implementable as written.
- **D9 compliance.** Every tmux-side change rides the existing single
  pre-step `gascity-terminal--run-async` round trip; the scroll mode sends
  raw bytes and spawns nothing; no new store verbs, so the non-blocking
  verb guard needs no additions (correctly stated in Verification).

## Implementation readiness pass

- **Requirements traceability.** All 14 REQs map to concrete checks: the
  Verification section assigns each REQ to a named unit test group or the
  e2e gate, and the front-matter coverage list matches the Markdown table
  pair-for-pair (REQ-001…REQ-014, all `covered`). No orphan requirements,
  no invented ones.
- **Task boundaries.** 16 numbered steps in 4 phases; P0/P1 independent,
  P2 depends only on P1's map, P3 closes. Each phase has its own *Accept*
  line and can become a single implementation bead with an unambiguous
  done-state. Step 13's `gascity-terminal--backend-reports-mouse-p` and
  step 6's `gascity-terminal--scroll-sequence` are pinned as pure functions
  — good seams for the table-driven tests.
- **Test commands.** Named: `scripts/gate.sh` (whole-package
  `eldev compile --warnings-as-errors` + ERT), pure `cl-letf` tests in
  `lisp/test/` in the existing script-fragment assertion style, and the
  live e2e acceptance through `scripts/e2e-harness.sh` against
  `/ssh:localhost:/home/roman/bright-lights` with E4–E8 host-side probes.
  A decomposition bead can lift these verbatim.
- **Risk.** Contained to `lisp/gascity-terminal.el` (+ texi + attach
  commentary); no migrations, no data formats; public surface additions are
  one defcustom and one minor mode (documented in P3). Rollback = revert;
  the teardown restore (`set-option -u mouse`, unbind WheelDownPane) keeps
  no persistent state. Risks that remain are exactly the requirements' open
  questions (M-> mechanism, wheel notch constant, ghostel semi-char quirks),
  each with an empirical-locking venue named (the live e2e pass). Explicit
  enough for an implementer.

## Advisory findings (non-blocking)

1. **Wheel event naming inconsistency (P1 step 6 vs P2 step 12).** Step 6
   says the mode "arms `<wheel-up>`/`<wheel-down>`", step 12 binds
   `<mouse-4>`/`<mouse-5>`. In Emacs the two are aliases of the same
   underlying input, but which one arrives depends on event conversion
   (mwheel) and on terminal-Emacs vs GUI. The implementer should bind **both
   aliases** in `gascity-terminal-scroll-mode-map` and assert the map is
   empty of all four for mouse-reporting backends.
2. **P0 deviates from the requirement's conditional probe.** The
   requirements' Technical Stories say the pre-step sets `mouse on` "when
   `show-options -g mouse` reports off"; the plan deliberately sets it
   unconditionally ("idempotent, pre-step runs once"). The plan's version is
   better (fewer parse branches in one shell fragment; teardown's `-u mouse`
   drops the session override and the global value resurfaces either way),
   but the deviation should be recorded in the QA report during P3 rather
   than silently absorbed.
3. **`M->` "until position settles" is not realizable as a pure function.**
   A pure `gascity-terminal--scroll-sequence` cannot observe position, so
   the v1 mechanism must be a **fixed bounded sequence** (e.g. a constant
   burst of C-Down) chosen in the live pass — consistent with Open Question
   1, but the plan should not imply feedback-driven repetition inside the
   pure table. (Already listed as an empirical lock in P1 step 8/6; this
   makes the constraint explicit for the implementer.)
4. **`[scroll]` marker depends on the status mirror being installed.** The
   marker rides `gascity-terminal--status-string`, which exists only when
   `gascity-terminal-mode-line-status` is non-nil; with the mirror disabled
   the mode still works but shows no mode-line indication (echo-area
   toggle feedback remains). Acceptable for v1; worth one sentence in the
   texi docs.
5. **D3 binding covers only the `copy-mode` table (mode-keys emacs).** A
   user whose `~/.tmux.conf` sets `mode-keys vi` wheels under the
   `copy-mode-vi` table, where the binding is absent — bottom-exit silently
   doesn't apply for them. The design/QA experiments ran on the default
   emacs mode-keys. Either bind the same fragment in `copy-mode-vi` too, or
   document the limitation; decide cheaply during P0's live pass.

## Recommendation

Proceed to decomposition unchanged. Carry findings 1–5 as notes on the
implementation beads (they are one-line constraints, not plan edits); each
has a natural resolution point inside P0/P1/P2/P3 as marked above.
