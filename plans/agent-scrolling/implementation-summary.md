---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-jwtp, formula: build-basic}
methodology: {pack: gascity, name: build-basic}
producer: {formula: build-basic, stage: summarize-implementation, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-jwtp
      hash: bead:ga-jwtp
    - path: beads/ga-dta4
      hash: bead:ga-dta4
    - path: plans/agent-scrolling/requirements.md
      hash: sha256:f06b0f208f018008eb80c7f9123d84d508da9464ab2c37ce4e322488efba1fd4
    - path: plans/agent-scrolling/decomposition.md
      hash: sha256:375df3ce56df32d90d922f50c4b62ceb9d420cfa2de7777f8508db62874bbf51
    - path: plans/agent-scrolling/implementation-plan.md
      hash: sha256:4f92f8d9fb9268c8685e0405814a330b34e3997c6555bb10f5a428601a8be923
    - path: docs/DESIGN-agent-scrolling.md
      hash: sha256:f099424db8379e20daf6d23fd7399db65fd25c3c2d7e7dea6fb8f92f984c0870
    - path: beads/ga-7xhp
      hash: bead:ga-7xhp
    - path: plans/agent-scrolling/implementation-wi-1-summary.md
      hash: sha256:260ea2523cac1cd1fc428617b41f2face8ad215c7560edb8b1d47c42e75aa963
      ids: [REQ-001, REQ-005, REQ-012, REQ-013]
    - path: beads/ga-lk9y
      hash: bead:ga-lk9y
    - path: plans/agent-scrolling/implementation-wi-2-summary.md
      hash: sha256:9495348008ffc77011764c5751d0dc6d0b9cef754af743ac79f6c7b5c9063621
      ids: [REQ-002, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010]
    - path: beads/ga-lb0b
      hash: bead:ga-lb0b
    - path: plans/agent-scrolling/implementation-wi-3-summary.md
      hash: sha256:055ad4ace0246af4d2bbbb9084da496462d631600d55c3cb83dbf03a004e91c9
      ids: [REQ-003, REQ-004, REQ-011]
    - path: beads/ga-q3vr
      hash: bead:ga-q3vr
    - path: plans/agent-scrolling/implementation-wi-4-summary.md
      hash: sha256:d08cb5363eb3d4cdd2675b45c5aee013686b2e94fa14267d59178111e740a836
    - path: docs/qa/2026-09-29-agent-scrolling-e2e.md
      hash: sha256:2e5abb055362ef3a365cdd38620a1f13de105a918080f834639fb6bb405dd7da
      ids: [REQ-014, REQ-001, REQ-002, REQ-008, REQ-012, REQ-013]
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
      status: covered
    - id: REQ-010
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
---

## Summary

The agent-scrolling build (workflow root `ga-jwtp`, formula `build-basic`,
launcher rig root `/home/roman/workspace/gascity.el`) implemented
transparent tmux mouse scrolling plus an Emacs-keys scroll sub-mode for
gascity terminal attach buffers, per the approved decomposition
(`plans/agent-scrolling/decomposition.md`) and implementation plan
(`plans/agent-scrolling/implementation-plan.md`).

All four implementation work items ran in the implementation convoy
`ga-dta4` (`agent-scrolling-implementation`, closed: all children closed)
and closed with `gc.outcome=pass`:

- **WI-1** (source anchor `ga-7xhp`, head `adbc52e`, phase P0, plan
  steps 1–4): tmux-side transparent mouse — the
  `gascity-terminal-ensure-mouse` custom turns the session's `mouse`
  option on and installs the copy-mode `WheelDownPane`
  exit-at-bottom binding in the attach pre-step's single async round
  trip; buffer teardown restores both (item summary:
  `plans/agent-scrolling/implementation-wi-1-summary.md`).
- **WI-2** (source anchor `ga-lk9y`, head `33ca47f`, phase P1, plan
  steps 5–11): `gascity-terminal-scroll-mode` — `C-c s` toggles the
  buffer-local minor mode, a pure translation table maps Magit-style
  keys (`C-p`/`C-n`, `C-v`/`M-v`, PageUp/PageDown, `M-<`/`M->`, `q`,
  Esc) to tmux copy-mode byte sequences through a per-backend raw-key
  adapter (vterm, term, eat, ghostel), with an optimistic self-healing
  re-toggle and a `[scroll]` mode-line marker (item summary:
  `plans/agent-scrolling/implementation-wi-2-summary.md`).
- **WI-3** (source anchor `ga-lb0b`, head `71f38df`, phase P2, plan
  steps 12–13): wheel translation for non-mouse-reporting backends —
  `gascity-terminal--backend-reports-mouse-p` gates `<mouse-4>`/
  `<mouse-5>` bindings so vterm/term scroll ≈10 lines per notch (first
  notch re-arms copy-mode entry, REQ-011) while ghostel/eat keep their
  native tmux passthrough untouched (item summary:
  `plans/agent-scrolling/implementation-wi-3-summary.md`).
- **WI-4** (source anchor `ga-q3vr`, heads `8bde552` / live-pass tree
  `b884d9c`, phase P3, plan steps 14–16): docs (`doc/gascity.texi`
  scroll sub-mode + per-backend wheel + `gascity-terminal-ensure-mouse`,
  attach-buffer commentary), the empirical lock of `M-<`/`M->` to
  tmux's native `history-top`/`history-bottom` bytes (requirements
  Open Question 1), the live TRAMP e2e acceptance pass recorded in
  `docs/qa/2026-09-29-agent-scrolling-e2e.md`, and the final quality
  gate (item summary:
  `plans/agent-scrolling/implementation-wi-4-summary.md`).

The work is feature-complete and accepted by the build's own gates;
landing the commits on `main` is owned by the downstream publish stage
(see Remaining Risks).

## Intended Behavior

In a gascity attach buffer (local or remote ssh-family city over
TRAMP), with `gascity-terminal-ensure-mouse` at its default `t`:

- Attaching ensures tmux `mouse on` for the agent session and installs
  the session-scoped copy-mode `WheelDownPane` binding that exits copy
  mode at the bottom of the history, so wheeling through the transcript
  always returns to the live tail (REQ-001, REQ-005, REQ-012).
- On backends that report the mouse natively to tmux (ghostel, eat)
  the wheel keeps working through tmux's own passthrough and gascity
  never intercepts it (REQ-004).
- `C-c s` enters tmux copy mode and arms the Emacs-keys scroll
  sub-mode: `C-p`/`C-n` scroll a line, `C-v`/`M-v` and PageUp/PageDown
  a page, `M-<`/`M->` jump to history top/bottom, `q` or Esc leaves
  copy mode and hands the keys back to the agent; the agent receives
  none of these keys while the mode is on, and the mode line shows
  `[scroll]` exactly while it is (REQ-002, REQ-006, REQ-009, REQ-010).
  An unknown backend reports and refuses gracefully instead of
  erroring (REQ-007). A re-toggle recovers from an out-of-band
  copy-mode exit by sending `q` first, then re-entering (REQ-008).
- On vterm/term, with the scroll mode armed, the wheel scrolls the
  transcript through tmux copy mode at ≈10 lines per notch; the first
  notch guarantees copy mode is entered (REQ-003, REQ-011).
- Killing the attach buffer restores the session's `mouse` option and
  unbinds `WheelDownPane`, so an external `tmux attach` sees tmux
  defaults; setting the custom to nil disables all tmux-side changes
  (REQ-013).
- The manual (`doc/gascity.texi`) documents all of the above, and the
  live acceptance pass verified the behaviour end to end over
  `/ssh:localhost:/home/roman/bright-lights` (REQ-014 and the e2e
  halves of REQ-001, REQ-002, REQ-008, REQ-012, REQ-013).

## Changed Files

Across the four source-anchor worktree heads (`adbc52e` → `33ca47f` →
`71f38df` → `8bde552`/`b884d9c`, all on top of `main` at `36e4f6e`):

- `lisp/gascity-terminal.el` — attach/teardown sh fragments for the
  tmux mouse ensure and `WheelDownPane` binding (WI-1); the
  `gascity-terminal-scroll-mode` minor mode, the pure translation
  table `gascity-terminal--scroll-sequence`, the per-backend raw-key
  adapter `gascity-terminal--send-raw`, the self-healing `C-c s`
  toggle, and the `[scroll]` status segment (WI-2); the backend mouse
  predicate, wheel sequence constructors and `<mouse-4>`/`<mouse-5>`
  bindings (WI-3); the locked `M-<`/`M->` table entries and the
  keyboard-layer attach commentary (WI-4).
- `lisp/gascity-custom.el` — the `gascity-terminal-ensure-mouse`
  defcustom (WI-1).
- `lisp/test/gascity-test.el` — attach-script/teardown fragment tests,
  table-driven translation/adapter/toggle/marker tests, wheel
  sequence/dispatch/no-interference tests (WI-1..WI-3), amended to the
  locked byte table (WI-4).
- `doc/gascity.texi` — "Attached terminals": mouse scrolling and
  scroll sub-mode subsections (WI-4).
- `docs/qa/2026-09-29-agent-scrolling-e2e.md` — the live e2e QA report
  (WI-4).
- Per-item summary artifacts under `plans/agent-scrolling/`:
  `implementation-wi-1-summary.md`, `implementation-wi-2-summary.md`
  (amended to the locked table), `implementation-wi-3-summary.md`,
  `implementation-wi-4-summary.md`.

## Verification

First verification commands (per item, from the item worktrees):

- WI-1: `eldev test gascity-test-terminal` — 27/27 passed (5 new
  mouse fragment tests).
- WI-2: `eldev test gascity-test-terminal-scroll` — 6/6 new scroll
  tests passed.
- WI-3: `eldev test gascity-test-terminal-scroll` — 11/11 scroll tests
  passed (6 P1 + 5 new wheel/predicate tests).
- WI-4: the live e2e acceptance gate, run through
  `scripts/e2e-harness.sh` rules — fresh `emacs -Q` in tmux over
  `/ssh:localhost:/home/roman/bright-lights`, disposable session
  `scroll-e2e`, host-side `display-message` probes after each step:
  **PASS** (copy-mode entry, line/page/top/bottom scrolling, wheel
  notch arithmetic, self-healing re-toggle, ensure/teardown lifecycle;
  full step/probe table in `docs/qa/2026-09-29-agent-scrolling-e2e.md`).

Final proof commands (whole-package quality gate `scripts/gate.sh` =
`eldev compile --warnings-as-errors` + full ERT, per item worktree):

- WI-1: PASS — compile clean, 739/739 tests, 0 unexpected.
- WI-2: PASS — compile clean, 745/745 tests, 0 unexpected.
- WI-3: PASS — compile clean, 750/750 tests, 0 unexpected.
- WI-4 (after the `M-<`/`M->` table lock, the authoritative final
  count): PASS — compile clean, 748/748 tests, 0 unexpected. Docs
  build `make -C doc` clean. The item-to-item count drift (739 → 750
  → 748) reflects tests added by later items and the WI-4 table-lock
  amendments, not failures.
- Artifact gate: `GC_BEAD_ID=ga-3v9s .gc/scripts/checks/build-artifact-valid.sh`
  from the launcher rig root — validates this summary against
  `gc.build.implementation-summary.v1`; observed: "build artifact
  valid".

Observed failures found and fixed during the build: the v1 `M-<`/`M->`
mechanisms (goto-prompt burst, repeated C-Down run) failed the live
pass and were replaced by tmux's native `history-top`/`history-bottom`
bytes, with tests and the WI-2 summary amended; the dead
`gascity-terminal--scroll-bottom-repeat` constant was removed.

## Remaining Risks

- The implementation commits live in the detached-HEAD source-anchor
  worktrees (`worktrees/ga-7xhp` `adbc52e`, `worktrees/ga-lk9y`
  `b884d9c`, `worktrees/ga-lb0b` `930dc5f`, `worktrees/ga-q3vr`
  `f10458a`), not yet merged to `main` — landing them (push,
  open PR) is the publish stage's contract (`open_pr=true`,
  `push=true`).
- The live e2e pass ran with the vterm backend on tmux 3.7c; ghostel/
  eat were exercised in the research probes but not re-driven in the
  acceptance pass — their no-interception contract is enforced by
  `gascity-terminal--backend-reports-mouse-p` and covered by pure ERT
  tests. eat 0.9.4 fails to spawn in this environment (upstream bug,
  recorded in the experiments report), so the eat adapter path is
  stubbed-test-only.
- The `M-<`/`M->` lock relies on tmux's default copy-mode emacs table;
  a host with those keys rebound would scroll differently (tmux-side,
  out of gascity's control).
- The optimistic copy-mode belief cannot detect an out-of-band
  copy-mode exit (no `pane_in_mode` resync in v1); the first wheel-up
  notch and the self-healing `C-c s` re-toggle both recover it.
- The D3 bottom-exit binding is session-scoped, so a concurrently
  attached external tmux client shares it while a gascity attach
  buffer is open; teardown restores the default on kill.

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
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-014 | covered |
