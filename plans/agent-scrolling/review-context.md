# Review context — build-basic ga-jwtp (agent-scrolling starter factory review)

Review lanes: acceptance and correctness, test evidence, simplicity and
maintainability (three lanes, then a synthesis step). Prepared by the
setup step `ga-qik8` for the review loop `build-basic.review.build-basic-review-loop`.

This file gathers the review inputs: the requirements artifact, the
implementation plan, the decomposition artifact, the canonical
implementation summary, the per-item implementation summaries and QA
evidence, and the verification commands. The implementation source of
truth is the closed source-anchor worktrees listed below — NOT the
launcher checkout. The launcher rig root may remain unchanged until the
publish step; that is expected, not a review failure.

Launcher rig root (workflow root metadata gc.work_dir, for contrast
only): /home/roman/workspace/gascity.el

Aggregated implementation chain (all four items, in order, on top of
main 36e4f6e): adbc52e (WI-1) -> 01381c0 / 33ca47f (WI-2) ->
71f38df (WI-3) -> 8bde552 (WI-4 lock-in) -> b088d2c (WI-4 summary
artifact). The tips of the four anchor worktrees are listed in the next
section; the ga-lk9y and ga-q3vr worktrees carry the aggregate chain.

## Implementation Worktrees

All four source anchors resolve from the implementation summary's
trace.upstream entries (paths beads/<source-anchor-id>); each
gc bd show <id> --json metadata.work_dir was verified to be an
absolute, existing git worktree different from the launcher root.

### WI-1 — source anchor ga-7xhp

- Implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-7xhp
  (HEAD adbc52e, clean)
- Launcher root (contrast): /home/roman/workspace/gascity.el
- Scope: tmux mouse ensure + bottom-cancel binding (P0, plan steps 1-4);
  requirements REQ-001, REQ-005, REQ-012, REQ-013
- Changed files: lisp/gascity-custom.el; lisp/gascity-terminal.el;
  lisp/test/gascity-test.el; plans/agent-scrolling/implementation-wi-1-summary.md
- Proof commands: eldev test gascity-test-terminal (27/27);
  scripts/gate.sh -> PASS, compile clean, 739/739 tests, 0 unexpected

### WI-2 — source anchor ga-lk9y

- Implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-lk9y
  (HEAD b884d9c — the aggregate chain tip including WI-3 and WI-4
  lock-in; clean)
- Launcher root (contrast): /home/roman/workspace/gascity.el
- Scope: gascity-terminal-scroll-mode + translation table (P1, plan
  steps 5-11); requirements REQ-002, REQ-006, REQ-007, REQ-008,
  REQ-009, REQ-010
- Changed files: lisp/gascity-terminal.el; lisp/test/gascity-test.el;
  plans/agent-scrolling/implementation-wi-2-summary.md (amended to the
  locked M-< / M-> byte table during the WI-4 live pass)
- Proof commands: eldev test gascity-test-terminal-scroll (6/6 new);
  scripts/gate.sh -> PASS, compile clean, 745/745 tests, 0 unexpected

### WI-3 — source anchor ga-lb0b

- Implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-lb0b
  (HEAD 930dc5f, clean)
- Launcher root (contrast): /home/roman/workspace/gascity.el
- Scope: wheel translation for non-reporting backends (P2, plan steps
  12-13); requirements REQ-003, REQ-004, REQ-011
- Changed files: lisp/gascity-terminal.el; lisp/test/gascity-test.el;
  plans/agent-scrolling/implementation-wi-3-summary.md
- Proof commands: eldev test gascity-test-terminal-scroll (11/11);
  scripts/gate.sh -> PASS, compile clean, 750/750 tests, 0 unexpected

### WI-4 — source anchor ga-q3vr

- Implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-q3vr
  (HEAD b088d2c — aggregate chain tip plus the WI-4 summary artifact;
  clean). The live e2e acceptance pass was driven from the byte-identical
  tree of worktrees/ga-lk9y at b884d9c.
- Launcher root (contrast): /home/roman/workspace/gascity.el
- Scope: docs, live TRAMP e2e pass, gate (P3, plan steps 14-16);
  requirements REQ-014 plus the e2e halves of REQ-001, REQ-002,
  REQ-008, REQ-012, REQ-013
- Changed files: doc/gascity.texi; lisp/gascity-terminal.el;
  lisp/test/gascity-test.el; docs/qa/2026-09-29-agent-scrolling-e2e.md;
  plans/agent-scrolling/implementation-wi-2-summary.md (amendment)
- Proof commands: live e2e over /ssh:localhost:/home/roman/bright-lights
  (PASS, step/probe table in the QA report); scripts/gate.sh -> PASS,
  compile clean, 748/748 tests, 0 unexpected (authoritative final count);
  make -C doc clean


---

# Artifact excerpt: requirements (plans/agent-scrolling/requirements.md)

---
schema: gc.build.requirements.v1
workflow:
  id: ga-jwtp
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: requirements
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-hhi0
      hash: bead:ga-hhi0
    - path: docs/DESIGN-agent-scrolling.md
      hash: sha256:f099424db8379e20daf6d23fd7399db65fd25c3c2d7e7dea6fb8f92f984c0870
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
    - path: docs/qa/2026-09-29-agent-scroll-mouse-experiments.md
      hash: sha256:d77552fa7a3f40807b11ffb2a71b79663e7e979c1673196f7c4b25e1fc9dbe1a
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

# Requirements — Agent buffers: transparent mouse + Emacs scrolling

Source of truth: `docs/DESIGN-agent-scrolling.md` (evidence E1–E9 in
`docs/qa/2026-09-29-agent-scroll-mouse-experiments.md`). This artifact
states the requested outcome, constraints, non-goals, acceptance
criteria, and open questions for implementing that design in the
gascity.el rig (workflow `ga-jwtp`, formula `build-basic`).

Coverage matrix:

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

## Problem Statement

gascity's agent attach buffers embed the agent session through a tmux
client (`gascity-terminal-attach-tmux` over beads.el's
`beads-terminal-spawn`). Today the user cannot scroll the transcript
with Emacs conventions: they must press `C-b [` and drive tmux
copy-mode with tmux keys, and the mouse wheel does nothing on most
terminal backends (ghostel/eat pass wheel bytes to tmux but nothing
guarantees `mouse on`; vterm/term do not report the wheel at all).
Goal: make reading an agent transcript feel like a native Emacs buffer
— transparent mouse-wheel scrolling and an explicit Emacs-keys scroll
sub-mode — without stealing any key from the live agent.

## W6H

- **Who:** every gascity.el user who opens an agent attach buffer
  (local or TRAMP city, any terminal backend gascity supports:
  ghostel, vterm, eat, ansi-term, term).
- **What:** three coordinated layers from the design — D1
  `gascity-terminal-scroll-mode` (Emacs-key scroll sub-mode), D2
  transparent mouse (wheel → tmux scroll), D3 a session-scoped tmux
  binding so wheeling to the bottom leaves copy mode and returns to
  the live tail.
- **When:** while an attach buffer is alive; tmux-side changes are
  installed by the existing attach pre-step and undone on teardown
  (`kill-buffer`), so they never outlive the buffer.
- **Where:** inside the attach buffer only (`gascity-terminal.el` +
  its test file); no dashboard, list, or session-detail view changes.
- **Why:** transcript reading is the primary interaction with an
  agent; tmux-key-only scrolling is a real usability gap and the mouse
  is inert on most backends.
- **How:** buffer-local minor mode with a per-backend raw-key adapter
  that sends byte sequences to the tmux client pty; the attach pre-step
  additionally runs one session-scoped `set-option mouse on` and one
  `bind -T copy-mode WheelDownPane …` fragment. No global keybindings,
  no side-channel `tmux send-keys` per wheel notch, no non-alt-screen
  re-attach.

## User Stories

- As a user on a mouse-reporting backend (ghostel or eat), I wheel over
  an attach buffer and the transcript scrolls through tmux copy mode;
  when I wheel to the bottom the view snaps back to the live tail.
- As a user on vterm or term (no wheel reporting), I press `C-c s`
  once and from then on the wheel scrolls the transcript through the
  scroll sub-mode's wheel translation.
- As a Magit-style user, in the scroll sub-mode I press `C-p`/`C-n` to
  move a line, `C-v`/`M-v`/`PageUp`/`PageDown` to page, `M-<`/`M->` to
  jump to the top/bottom, and `q` or `Esc` to leave the mode and hand
  keys back to the agent.
- As a remote-city user, I get all of the above identically on
  `/ssh:localhost:…` (bright-lights) because the tmux client is a
  local process in both shapes and bytes travel over the local pty.
- As a user who attached an external `tmux` client to the same
  session, my defaults are untouched: the gascity-installed options and
  bindings are session-scoped and restored on buffer kill.

## Technical Stories

- `gascity-terminal-scroll-mode`, a buffer-local minor mode for attach
  buffers, entered with `C-c s` in `gascity-terminal-attach-map`
  (which owns only `C-c` keys; no §10 collision).
- A translation table (pure function, testable) mapping Emacs keys to
  tmux byte sequences: `C-p`/`C-n` → `\e[1;5A`/`\e[1;5B`, `C-v`/`M-v`
  and PageDown/PageUp → `\e[6~`/`\e[5~`, `M-<` → `g 0 RET` via the
  goto prompt, `M->` → `M-Up`/`M-Down`-equivalents until position
  settles, `q` → `q`, `Esc` → `\e`. The last two also deactivate the
  minor mode.
- A per-backend raw-key adapter selected from the buffer's major mode:
  vterm → `vterm-send-string`; term/ansi-term →
  `term-send-raw-string`; eat → `eat-self-input`; ghostel →
  `ghostel-send-key` for control bytes and `ghostel-send-string` for
  escape sequences.
- Optimistic state with self-healing: activation assumes copy mode is
  on; re-toggling `C-c s` sends `q` first when the mode thinks it is
  active, recovering from an out-of-band copy-mode exit. No async
  `pane_in_mode` resync is required for v1.
- Mode-line indication: the existing status mirror segment gains a
  `[scroll]` marker while the mode is active
  (`gascity-terminal--status-string`).
- Attach pre-step (`gascity-terminal--attach-script`) additionally
  runs `set-option -t SESSION mouse on` when `show-options -g mouse`
  reports off, and installs the D3 binding:
  `bind -T copy-mode WheelDownPane select-pane \; if -F
  '#{==:#{scroll_position},0}' 'send -X cancel' 'send -X -N 5
  scroll-down'`; teardown unbinds and restores exactly like the
  existing `status` mirror restore. Gated by new custom
  `gascity-terminal-ensure-mouse` (default t).
- Wheel bindings for non-reporting backends live in the same
  scroll-mode map: first notch sends `C-b` `[` then 3 × C-Up (≈10
  lines/notch, matching tmux's `-N 5` feel); while already in copy
  mode the notch sends only C-Up/C-Down. On ghostel/eat the native
  tmux passthrough wins and the Emacs wheel binding must not
  interfere.
- All tmux-side changes ride the pre-step's existing single host round
  trip (`gascity-terminal--run-async`, local and remote alike); no new
  synchronous gc or tmux call anywhere on render, redisplay, or
  timers (dashboard-v3 D9).

## Behavior Requirements

- Entering the scroll sub-mode never sends keys the agent could see as
  input other than the copy-mode entry bytes (`C-b` `[`); while the
  mode is active the agent receives nothing (E9).
- Wheel scrolling on mouse-reporting backends works without the user
  enabling anything; when the agent TUI claims mouse, wheel bytes are
  a correct pass-through (E5).
- Wheel-down past the bottom of copy mode cancels copy mode (D3
  binding), returning to the live tail; the binding is removed on
  teardown so external clients see default bindings again.
- Scroll-mode toggle is idempotent and recoverable: `C-c s` while
  active exits cleanly (sends `q`, deactivates); after an
  out-of-band exit a re-toggle re-enters copy mode and re-arms.
- Behavior is identical for local and remote (TRAMP) cities; the
  remote path adds no TRAMP round trips beyond the existing pre-step.

## Example Mapping

- **Rule:** user presses `C-c s` in an attach buffer.
  - Example: ghostel buffer, mode activates, `C-p` sends `\e[1;5A`,
    viewport scrolls one line, mode line shows `[scroll]`.
- **Rule:** user wheels on a mouse-reporting backend.
  - Example: eat buffer with `mouse` off in tmux → attach pre-step
    sets `mouse on`; wheel enters copy mode automatically and scrolls.
- **Rule:** user wheels on vterm after enabling the scroll sub-mode.
  - Example: first notch sends `C-b` `[` + 3 × C-Up; subsequent
    notches send C-Up/C-Down only.
- **Rule:** user wheels to the bottom of the transcript.
  - Example: D3 binding cancels copy mode at position 0; the live
    tail resumes.
- **Rule:** buffer is killed.
  - Example: teardown restores `status` and unbinds WheelDownPane;
    an external `tmux attach` sees default bindings.

## Acceptance Criteria

1. On ghostel and eat: attach an agent; wheel scrolls the transcript
   without any setup; wheeling to the bottom returns to the live
   tail; when the agent claims mouse the wheel is a pass-through.
2. On vterm and term: `C-c s` then wheel scrolls the transcript; the
   translation table (`C-p`/`C-n`/`C-v`/`M-v`/PageUp/PageDown`/`M-<`/
   `M->`/`q`/`Esc`) drives tmux copy mode exactly per the design's
   byte table; the agent receives no keys while the mode is active.
3. `C-c s` re-syncs after an out-of-band copy-mode exit; the mode
   line shows the `[scroll]` marker while active and none otherwise.
4. Attach pre-step emits `mouse on` and the D3 WheelDownPane binding
   when `gascity-terminal-ensure-mouse` is on; teardown restores
   (`-u`/unbind fragments); with the option nil nothing changes.
5. No new synchronous gc/tmux calls; all changes ride the existing
   async pre-step round trip; the non-blocking verb guard in
   `lisp/test/gascity-store-test.el` needs no additions (the mode
   sends raw bytes and spawns nothing).
6. ERT suite passes: table-driven translation tests, per-backend
   adapter dispatch, attach-script fragment assertions, teardown
   restore assertions — all pure `cl-letf` stubs.
7. Live e2e acceptance gate passes over TRAMP (`/ssh:localhost:
   /home/roman/bright-lights`): fresh Emacs in tmux, attach a
   bright-lights agent, drive `C-c s` and wheel events, assert
   host-side `pane_in_mode`/`scroll_position` after each step
   (E4–E8 probes), recorded under `docs/qa/`.
8. Documentation updated: `doc/gascity.texi` and the attach buffer
   commentary describe the scroll sub-mode and mouse behavior; the
   gate (`scripts/gate.sh`) is green.

## Out Of Scope

- Scrolling the Emacs buffer itself for attach buffers (the client is
  always on the alt screen; E2 rules it out).
- Driving tmux scrollback via per-notch side-channel `tmux send-keys`
  processes, or `cat | less`-style non-alt-screen re-attach.
- Async `pane_in_mode` resync of scroll-mode state (design: optional
  refinement, not needed for v1).
- Any change to dashboards, lists, session detail, the status mirror
  installation, project pinning, or eldoc wiring beyond the
  `[scroll]` marker.
- Backend library feature work (ghostel scrollback, eat mouse
  configuration) — only their existing raw-key APIs are used.

## Open Questions

- **`M->` bottom jump mechanism.** The design lists `End` or repeated
  `C-Down` until position settles as candidates; the exact byte
  strategy should be picked empirically during implementation and
  locked into the translation table (autonomous run — resolved in
  implementation, not blocking).
- **Wheel notch → line count on translated backends.** The design
  fixes ≈10 lines per notch (3 × C-Up after entry); if the feel is
  wrong in the live pass, adjust the constant there.
- **Ghostel strictness.** E1 shows ghostel availability is strict
  about being already loaded; no action is required, but if the live
  pass surfaces a new ghostel quirk in semi-char mode (E6), record it
  in the QA report rather than expanding this artifact.


---

# Artifact excerpt: decomposition (plans/agent-scrolling/decomposition.md)

---
schema: gc.build.decomposition.v1
workflow:
  id: ga-jwtp
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: decompose
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/agent-scrolling/requirements.md
      hash: sha256:f06b0f208f018008eb80c7f9123d84d508da9464ab2c37ce4e322488efba1fd4
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
    - path: plans/agent-scrolling/implementation-plan.md
      hash: sha256:4f92f8d9fb9268c8685e0405814a330b34e3997c6555bb10f5a428601a8be923
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
    - path: docs/DESIGN-agent-scrolling.md
      hash: sha256:f099424db8379e20daf6d23fd7399db65fd25c3c2d7e7dea6fb8f92f984c0870
    - path: docs/qa/2026-09-29-agent-scroll-mouse-experiments.md
      hash: sha256:d77552fa7a3f40807b11ffb2a71b79663e7e979c1673196f7c4b25e1fc9dbe1a
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

# Decomposition — Agent buffers: transparent mouse + Emacs scrolling

## Summary

The approved plan (phases P0–P3) decomposes into **four runnable
implementation work items** on a single dependency chain: the tmux-side
mouse ensure + bottom-cancel binding (WI-1), the
`gascity-terminal-scroll-mode` keyboard layer with its translation table
and per-backend adapters (WI-2), wheel translation for backends that do
not report mouse (WI-3), and documentation plus the live TRAMP e2e
acceptance pass and gate (WI-4). The order follows the plan's phase
sequencing (P0 and P1 independent, P2 builds on P1's map, P3 closes);
each item owns the tests for its slice per the house convention (ERT
stubs the process boundary with `cl-letf`; no live processes in unit
tests). All changes stay in `lisp/gascity-terminal.el`, its test files,
`doc/gascity.texi`, and `docs/qa/`; no dashboard, list, or session-detail
view is touched.

## Selected Downstream Formulas

The drain policy on the workflow root is `separate`, so the
implementation convoy drains through the following formulas (workflow
root `ga-jwtp` metadata `gc.var.*`):

- **Implementation drain:** `do-work` (formula `implement`,
  `drain_policy == separate`) — one implementation session per convoy
  bead, running under `gc.implementation-worker`.
- **Per-item fallback:** `do-work-item` (`gc.var.implementation_item_formula`)
  is the single-lane item formula for a `same-session` drain; it is not
  active under the recorded `separate` policy but each bead satisfies
  its contract anyway (self-contained work item with its own
  verification).
- **Code review:** `review` (`gc.var.code_review_formula`).
- **Review fix loop:** `fix-loop-base` (`gc.var.review_fix_formula`).

Each work item below carries its own expected files, verification
expectations, and requirement/plan traceability so any implementation
formula can drain it without knowing the planning methodology.

## Implementation Convoy

A **new** implementation convoy was created for this continuation — it
reuses neither the original launch convoy (`ga-9269`, "input convoy for
ga-ym98", recorded as `gc.var.convoy_id`) nor any planning or
workflow-control convoy, as the decompose step contract requires:

- **Convoy ID: `ga-dta4`** — title "agent-scrolling-implementation".
- Members and drain order (dependency DAG; a bead is ready when its
  dependencies close):

| WI | Bead | Title | Depends on |
|----|------|-------|------------|
| WI-1 | `ga-7xhp` | tmux mouse ensure + bottom-cancel binding (plan P0) | — |
| WI-2 | `ga-lk9y` | `gascity-terminal-scroll-mode` + translation table (plan P1) | WI-1 |
| WI-3 | `ga-lb0b` | wheel translation for non-reporting backends (plan P2) | WI-1, WI-2 |
| WI-4 | `ga-q3vr` | docs, live TRAMP e2e pass, gate (plan P3) | WI-1, WI-2, WI-3 |

The convoy identity is recorded on the workflow root bead (`ga-jwtp`) as
`gc.input_convoy_id=ga-dta4` (drain contract) and
`gc.build.implementation_convoy_id=ga-dta4` (continuation reporting);
the recorded convoy is verified distinct from the original launch convoy
`ga-9269` (`gc.var.convoy_id`) and from every workflow-control bead.

### Requirement and plan traceability

Every requirement (REQ-001…REQ-014) and plan phase maps to at least one
owning work item; each bead description restates its slice:

| Plan phase | Requirements | Work item |
|------------|--------------|-----------|
| P0 (mouse ensure + WheelDownPane binding + teardown restore, steps 1–4) | REQ-001, REQ-005, REQ-012, REQ-013 | WI-1 |
| P1 (scroll sub-mode, translation table, adapters, toggle semantics, `[scroll]` marker, steps 5–11) | REQ-002, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010 | WI-2 |
| P2 (wheel translation on vterm/term, first-notch entry bytes, step 12–13) | REQ-003, REQ-004, REQ-011 | WI-3 |
| P3 (texi + commentary docs, live TRAMP e2e pass, QA report, gate, commit, steps 14–16) | REQ-014 (+ e2e halves of REQ-001, REQ-002, REQ-008, REQ-012, REQ-013) | WI-4 |

The plan's two open questions are carried, not dropped: the `M->`
bottom-jump mechanism (requirements Open Question 1) is locked
empirically inside WI-2's translation table; the wheel notch line count
(Open Question 2) is a single adjustable constant owned by WI-3. The
plan-review (P2) verdict advisories, if any, are adopted at the owning
item during implementation.

## Work Items

### WI-1 — `ga-7xhp`: tmux mouse ensure + bottom-cancel binding (plan P0)

- **Requirements:** REQ-001, REQ-005, REQ-012, REQ-013.
- **Expected files:** `lisp/gascity-terminal.el` (custom
  `gascity-terminal-ensure-mouse`; `gascity-terminal--attach-script`
  gains the `set-option -t <SESSION> mouse on` fragment and the D3
  `bind -T copy-mode WheelDownPane select-pane \; if -F
  '#{==:#{scroll_position},0}' 'send -X cancel' 'send -X -N 5
  scroll-down'` fragment on the existing single
  `gascity-terminal--run-async` round trip; `gascity-terminal--status-teardown`
  gains `set-option -u mouse` and `unbind -T copy-mode WheelDownPane`,
  gated by the same custom);
  `lisp/test/` (script-fragment string assertions with the option t and
  nil, in the existing attach-script test style).
- **Formula assets:** none — this is a code work item drained by the
  implementation formula.
- **Verification:** whole-package `eldev compile --warnings-as-errors`;
  new attach-script/teardown fragment tests; existing terminal ERT
  suite green. Accept (from the plan): wheel scrolls a bright-lights
  transcript; wheeling to the bottom returns to the live tail; after
  buffer kill an external `tmux attach` sees default bindings.
- **Dependencies:** none (first item).

### WI-2 — `ga-lk9y`: `gascity-terminal-scroll-mode` + translation table (plan P1)

- **Requirements:** REQ-002, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010.
- **Expected files:** `lisp/gascity-terminal.el`
  (`gascity-terminal-scroll-mode` + `gascity-terminal-scroll-mode-map`,
  `C-c s` toggle in `gascity-terminal-attach-map` — no §10 collision;
  pure `gascity-terminal--scroll-sequence` implementing the D1 byte
  table, with the `M->` bottom-jump mechanism locked empirically;
  per-backend raw-key adapter `gascity-terminal--send-raw` — vterm →
  `vterm-send-string`, term/ansi-term → `term-send-raw-string`, eat →
  `eat-self-input`, ghostel → `ghostel-send-key`/`ghostel-send-string`
  split, unknown backend → deactivate with an echo-area message, never
  error; optimistic + self-healing toggle: entry sends `C-b` `[`,
  re-toggle sends `q` first; `gascity-terminal--status-string` appends
  `[scroll]` while active);
  `lisp/test/` (table-driven sequence cases, adapter dispatch per
  backend major mode, toggle idempotence/self-healing, marker
  presence).
- **Formula assets:** none.
- **Verification:** whole-package `eldev compile --warnings-as-errors`;
  new table-driven/dispatch/toggle/marker ERT tests; existing suite
  green. The agent receives no keys while the mode is active (E9).
- **Dependencies:** depends on WI-1 (builds on the attach pre-step
  fragments it asserts against).

### WI-3 — `ga-lb0b`: wheel translation for non-reporting backends (plan P2)

- **Requirements:** REQ-003, REQ-004, REQ-011.
- **Expected files:** `lisp/gascity-terminal.el` (pure predicate
  `gascity-terminal--backend-reports-mouse-p` on the backend class;
  `<mouse-4>`/`<mouse-5>` bindings in `gascity-terminal-scroll-mode-map`
  for non-reporting backends only — first notch sends `C-b` `[` then
  3 × C-Up (≈10 lines/notch, adjustable constant per requirements Open
  Question 2), subsequent notches send only C-Up/C-Down; ghostel/eat
  native passthrough never intercepted);
  `lisp/test/` (wheel-sequence construction first notch vs subsequent;
  no-interference assertion — the map is empty of wheel bindings when
  the backend reports mouse).
- **Formula assets:** none.
- **Verification:** whole-package `eldev compile --warnings-as-errors`;
  new wheel-sequence and predicate ERT tests; existing suite green.
- **Dependencies:** depends on WI-1 and WI-2 (uses the P1 scroll-mode
  map and toggle state).

### WI-4 — `ga-q3vr`: docs, live TRAMP e2e pass, gate (plan P3)

- **Requirements:** REQ-014 (+ the e2e halves of REQ-001, REQ-002,
  REQ-008, REQ-012, REQ-013).
- **Expected files / formula assets:** `doc/gascity.texi` (scroll
  sub-mode `C-c s`, per-backend mouse behaviour,
  `gascity-terminal-ensure-mouse`); attach buffer commentary in
  `lisp/gascity-terminal.el`; new QA report under `docs/qa/`
  (suggested `docs/qa/2026-09-29-agent-scrolling-e2e.md`) recording the
  tmux-Emacs run — a bright-lights outage is recorded as a blocker in
  the QA report, never silently skipped; residual fixes only if the e2e
  pass exposes a gap.
- **Verification:** `scripts/gate.sh` green; the live e2e acceptance
  gate through `scripts/e2e-harness.sh` — fresh Emacs in tmux connected
  to `/ssh:localhost:/home/roman/bright-lights`, attach a bright-lights
  agent, drive `C-c s`, translated keys, and wheel events, assert
  host-side `pane_in_mode`/`scroll_position` after each step (E4–E8
  probes), teardown leaves default bindings for an external `tmux
  attach`; commit subject shape `feat(terminal): …` citing
  DESIGN-agent-scrolling.md and DESIGN-write-actions.md §10 where keys
  are added.
- **Dependencies:** depends on WI-1, WI-2, WI-3 (all code landed
  first).

### Skipped work

- **Async `pane_in_mode` resync of scroll-mode state** — optional
  refinement in the design, explicitly a non-goal for v1 in the
  requirements and plan; no work item carries it.
- **Emacs-buffer scrolling of attach buffers, per-notch side-channel
  `tmux send-keys` processes, non-alt-screen re-attach, backend library
  feature work (ghostel scrollback, eat mouse configuration), changes to
  dashboards/lists/session detail/status-mirror mechanics beyond the
  `[scroll]` marker** — out of scope by the requirements artifact and
  plan Non-Goals; no work item carries them.
- **New store/async verbs** — none are needed; the non-blocking verb
  guard in `lisp/test/gascity-store-test.el` requires no additions
  (REQ-014, tracked in WI-2/WI-3 verification).

### Blocked work

None at decomposition time. Every work item is runnable once its
dependencies close, and WI-1 has no upstream blocker. The only
conditional risk is the WI-4 e2e environment: if
`/ssh:localhost:/home/roman/bright-lights` is unreachable at e2e time,
WI-4 records it as a blocker in the QA report rather than skipping;
that is a runtime contingency recorded in the bead, not a blocked work
item.

## Verification

- Each work item carries its own verification expectations (above) and
  its bead description repeats them; every item ends with
  whole-package `eldev compile --warnings-as-errors` and the relevant
  ERT run.
- WI-2/WI-3 run the targeted ERT slices; WI-4 runs the full ERT suite
  via `scripts/gate.sh` and the interactive tmux-Emacs TRAMP pass —
  the acceptance gate for REQ-001/REQ-002/REQ-008/REQ-012/REQ-013
  end-to-end.
- Coverage disposition for every upstream ID:

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

REQ-001 → WI-1 (tmux mouse) + WI-4 (e2e); REQ-002 → WI-2 (sub-mode +
byte table) + WI-4 (e2e); REQ-003 → WI-3 (wheel translation); REQ-004 →
WI-3 (passthrough untouched); REQ-005 → WI-1 (mouse on fragment);
REQ-006 → WI-2 (per-backend adapters); REQ-007 → WI-2 (unknown backend
fallback); REQ-008 → WI-2 (toggle semantics) + WI-4 (e2e re-sync);
REQ-009 → WI-2 (no agent-visible keys); REQ-010 → WI-2 (`[scroll]`
marker); REQ-011 → WI-3 (notch constants); REQ-012 → WI-1 (bottom
cancel) + WI-4 (e2e); REQ-013 → WI-1 (teardown restore) + WI-4 (e2e
external client); REQ-014 → WI-4 (docs + gate).


---

# Artifact excerpt: implementation plan (plans/agent-scrolling/implementation-plan.md)

---
schema: gc.build.plan.v1
workflow:
  id: ga-jwtp
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: plan
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-qbg2
      hash: bead:ga-qbg2
    - path: plans/agent-scrolling/requirements.md
      hash: sha256:f06b0f208f018008eb80c7f9123d84d508da9464ab2c37ce4e322488efba1fd4
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
    - path: docs/DESIGN-agent-scrolling.md
      hash: sha256:f099424db8379e20daf6d23fd7399db65fd25c3c2d7e7dea6fb8f92f984c0870
    - path: docs/qa/2026-09-29-agent-scroll-mouse-experiments.md
      hash: sha256:d77552fa7a3f40807b11ffb2a71b79663e7e979c1673196f7c4b25e1fc9dbe1a
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

# Implementation Plan — Agent buffers: transparent mouse + Emacs scrolling

This plan implements the approved requirements in
`plans/agent-scrolling/requirements.md` (trace REQ-001–REQ-014) from the
design `docs/DESIGN-agent-scrolling.md` (D1/D2/D3 layers, evidence E1–E9
in `docs/qa/2026-09-29-agent-scroll-mouse-experiments.md`). All changes
live in `lisp/gascity-terminal.el` (+ `doc/gascity.texi` and the attach
commentary); no dashboard, list, or session-detail view is touched.

Coverage matrix:

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

## Summary

Make reading an agent attach transcript feel native: (1) the attach
pre-step ensures tmux `mouse on` (session-scoped) and installs one
session-scoped `copy-mode` `WheelDownPane` binding that cancels copy
mode at the bottom, restoring both on teardown (D2/D3); (2) a new
buffer-local minor mode `gascity-terminal-scroll-mode`, toggled with
`C-c s` in `gascity-terminal-attach-map`, translates Emacs scroll keys
to tmux copy-mode byte sequences through a per-backend raw-key adapter
(D1) and arms `<wheel-up>`/`<wheel-down>` translation on backends that
do not report mouse (vterm, term). The agent never receives keys while
the scroll mode is active; a `[scroll]` marker appears in the existing
status-mirror mode-line segment.

Delivered in four phases (P0 tmux-side mouse, P1 scroll sub-mode, P2
wheel translation, P3 docs/polish), each independently buildable and
testable; final acceptance is the live TRAMP e2e pass against
`bright-lights`.

## Current System

- **Attach buffer.** `gascity-terminal-run` (gascity-terminal.el) calls
  beads.el's `beads-terminal-spawn` — backends ghostel (5), vterm (10),
  eat (20), ansi-term (40), term (50); `gascity-terminal--backend-class`
  maps `gascity-terminal-backend` (`auto` → first available).
  The argv is `env -u TMUX tmux [-L SOCKET] attach-session -t SESSION`,
  wrapped into a local `ssh -t HOST …` for remote cities; the tmux
  client is a local process in every shape (no TRAMP in the input path).
- **Keymaps.** `gascity-terminal-attach-map` owns only the `C-c` prefix
  (`C-c b` bead-at-point) via an `emulation-mode-map-alists` entry keyed
  on `gascity-terminal--attach-keys`, deliberately above local/minor
  maps so it survives backend copy modes. Everything else belongs to the
  pty; `gascity-terminal--unshadow-keys` +
  `gascity-terminal-unshadow-minor-modes` (default
  `(pixel-scroll-precision-mode)`) neutralise global minor-mode keymaps
  in terminal buffers.
- **tmux-side state gascity touches.** Only `status off` — set
  session-scoped by the attach pre-step `gascity-terminal--attach-script`
  (one host round trip via `gascity-terminal--run-async`, local and
  remote alike), mirrored into the mode line by
  `gascity-terminal--status-install`, and restored by the kill-buffer
  hook `gascity-terminal--status-teardown`. gascity sets no `mouse`
  option today; `mode-keys emacs` is the tmux default.
- **What is missing.** No scroll sub-mode exists; the user must press
  `C-b [` and drive tmux copy-mode with tmux keys. The mouse wheel is
  inert on vterm/term, works only if the user's `~/.tmux.conf` sets
  `mouse on` on ghostel/eat, and wheeling to the bottom of copy mode
  never returns to the live tail (tmux 3.7c, E8).
- **Repo conventions that bind the implementation.** Non-blocking D9
  (no sync gc/tmux on render, redisplay, timers, or eldoc; every process
  has a deadline); key additions must check
  `docs/DESIGN-write-actions.md` §10; tests are pure `cl-letf` stubs in
  `lisp/test/`; the quality gate is `scripts/gate.sh` (whole-package
  byte-compile with `--warnings-as-errors` + ERT).

## Proposed Implementation

### Phase P0 — mouse for everyone who can have it (tmux-side, D2 + D3)

1. Add custom `gascity-terminal-ensure-mouse` (defcustom, boolean,
   default t) in gascity-terminal.el.
2. Extend `gascity-terminal--attach-script` so its single tmux fragment
   additionally runs, when the custom is non-nil:
   - `set-option -t <SESSION> mouse on` (session-scoped; unconditional
     set is fine — the pre-step already runs once per attach);
   - the D3 binding fragment:
     `bind -T copy-mode WheelDownPane select-pane \; if -F
     '#{==:#{scroll_position},0}' 'send -X cancel' 'send -X -N 5
     scroll-down'`.
   All of it rides the pre-step's existing one
   `gascity-terminal--run-async` round trip — no new process paths,
   local or remote (D9).
3. Extend the teardown path (`gascity-terminal--status-teardown`
   fragments) to restore exactly like the `status` mirror: emit
   `set-option -u mouse` (session-scoped unset) and
   `unbind -T copy-mode WheelDownPane`, gated by the same custom.
4. Tests: string assertions on `gascity-terminal--attach-script` and the
   teardown fragments with the option t and nil (nothing changes when
   nil), following the existing script-fragment test style in
   `lisp/test/`.

*Accept:* attach to a bright-lights agent (local and
`/ssh:localhost:/home/roman/bright-lights`); wheel scrolls the
transcript; wheeling to the bottom returns to the live tail; after
buffer kill an external `tmux attach` sees default bindings.

### Phase P1 — `gascity-terminal-scroll-mode` (keyboard layer, D1)

5. Add `gascity-terminal-scroll-mode`, a buffer-local minor mode for
   attach buffers, plus `gascity-terminal-scroll-mode-map`. Bind `C-c s`
   in `gascity-terminal-attach-map` to a toggle command (no §10
   collision — the attach map owns only `C-c` keys).
6. Add the pure translation function
   `gascity-terminal--scroll-sequence KEY` returning the byte sequence
   for the D1 table: `C-p`/`C-n` → `\e[1;5A`/`\e[1;5B`; `C-v`/`M-v` and
   `PageDown`/`PageUp` → `\e[6~`/`\e[5~`; `M-<` → `g` `0` `RET` via the
   goto prompt; `M->` → repeated C-Down (`\e[1;5B`) until position
   settles — the design leaves the bottom-jump mechanism to be locked
   empirically (requirements Open Question 1); `q` → `q`; `Esc` → `\e`.
   The `q`/`Esc` entries also deactivate the minor mode. Keep the table
   a single pure function so tests are table-driven.
7. Add the per-backend raw-key adapter
   `gascity-terminal--send-raw BUFFER SEQ` selected from the buffer's
   major mode: vterm → `vterm-send-string`; term/ansi-term →
   `term-send-raw-string`; eat → `eat-self-input`; ghostel →
   `ghostel-send-key` for control bytes, `ghostel-send-string` for
   escape sequences (E6: ghostel strictness in semi-char mode).
   Unknown backend → deactivate with an echo-area message, never error.
8. Toggle semantics, optimistic + self-healing: activation sends
   `C-b` `[` (copy-mode entry bytes — the only bytes the agent can see
   on entry) and arms the map; re-toggling while it thinks it is active
   sends `q` first (recovering from an out-of-band copy-mode exit), then
   re-enters. No async `pane_in_mode` resync in v1.
9. Mode-line indication: extend `gascity-terminal--status-string` to
   append `[scroll]` while the mode is active in that buffer (same
   status-mirror segment, no new segment).
10. Echo-area feedback on toggle (P3 polish): "scroll mode on/off" —
    report, never block.
11. Tests (pure `cl-letf`): table-driven
    `gascity-terminal--scroll-sequence` cases; adapter dispatch per
    backend major mode; toggle idempotence and the self-healing `q`
    first re-toggle; `[scroll]` marker presence.

*Accept:* on ghostel, vterm, and term, `C-c s` then
`C-p`/`C-n`/`C-v`/`M-v`/`PageUp`/`PageDown`/`M-<`/`M->`/`q`/`Esc` drive
tmux copy mode per the E6 byte table; the agent receives no keys while
the mode is active (E9); the marker shows exactly while active.

### Phase P2 — wheel translation for non-reporting backends (D2, Emacs side)

12. Bind `<mouse-4>`/`<mouse-5>` (wheel up/down) in
    `gascity-terminal-scroll-mode-map`: when the mode was just entered
    and copy mode is (optimistically) not yet on, the first notch sends
    `C-b` `[` then 3 × `\e[1;5A` (≈10 lines/notch, matching tmux's
    `-N 5` feel; constant stays adjustable per requirements Open
    Question 2); while already in copy mode, notches send only
    C-Up/C-Down. Wheel events only fire through this map when the minor
    mode is on, so ghostel/eat's native tmux mouse passthrough (E5)
    is never intercepted — their wheel keeps working with the mode off,
    and with the mode on the passthrough still wins because those
    backends report mouse natively to tmux, not to Emacs.
13. Tests: wheel-sequence construction (first notch vs subsequent),
    no interference assertion for ghostel/eat (the map is empty of
    wheel bindings when `gascity-terminal--backend-reports-mouse-p`
    — a small pure predicate on the backend class).

*Accept:* vterm attach, `C-c s` once, wheel scrolls the transcript;
eat/ghostel behaviour unchanged.

### Phase P3 — documentation, QA, gate

14. `doc/gascity.texi`: describe the scroll sub-mode (`C-c s`), the
    mouse behaviour per backend, and `gascity-terminal-ensure-mouse`;
    update the attach buffer commentary in gascity-terminal.el.
15. Run the live e2e acceptance gate through `scripts/e2e-harness.sh`:
    fresh Emacs in tmux, connect to
    `/ssh:localhost:/home/roman/bright-lights`, attach a bright-lights
    agent, drive `C-c s` and wheel events, assert host-side
    `pane_in_mode`/`scroll_position` after each step (E4–E8 probes),
    record under `docs/qa/`.
16. Run `scripts/gate.sh` (whole-package compile with
    `--warnings-as-errors` + full ERT); commit per repo conventions
    (`feat(terminal): …`, body citing DESIGN-agent-scrolling.md and
    DESIGN-write-actions.md §10 where keys are added).

### Sequencing and risk notes

- P0 and P1 are independent; P2 depends on P1's map; P3 closes.
- Risks: ghostel raw-send quirks in semi-char mode (E6) — mitigated by
  the control-byte/escape-sequence split adapter, fallback to echo-area
  deactivation; `M->` bottom-jump feel — locked empirically in the live
  pass per the requirements' open questions; wheel notch line count —
  a single adjustable constant.
- Non-goals guard: no Emacs-buffer scrolling of attach buffers (E2),
  no per-notch `tmux send-keys` side-channel processes, no async
  `pane_in_mode` resync, no backend library feature work.

## Non-Goals

- Scrolling the Emacs buffer itself for attach buffers — the tmux
  client is always on the alt screen (E2); scrolling happens inside
  tmux copy mode only.
- Driving tmux scrollback via per-notch side-channel `tmux send-keys`
  processes, or `cat | less`-style non-alt-screen re-attach — rejected
  by the design (process churn per notch; fights the client contract).
- Async `pane_in_mode` resync of scroll-mode state — optional future
  refinement, not v1; optimistic + self-healing toggle suffices.
- Any change to dashboards, lists, session detail, the status-mirror
  installation mechanics, project pinning, or eldoc wiring beyond the
  `[scroll]` marker in the existing status string.
- Backend library feature work (ghostel scrollback, eat mouse
  configuration) — only existing raw-key APIs are used.
- Any new synchronous gc or tmux call anywhere on render, redisplay,
  or timers (D9); all tmux-side changes ride the existing async
  pre-step round trip.

## Verification

- **Unit (ERT, pure `cl-letf` stubs, `lisp/test/`):**
  - `gascity-terminal--scroll-sequence` table-driven cases for every
    D1 key (REQ-002, REQ-009);
  - raw-key adapter dispatch per backend major mode, including the
    ghostel control/escape split and the unknown-backend fallback
    (REQ-006, REQ-007);
  - toggle semantics: entry sends `C-b [`, re-toggle sends `q` first,
    `q`/`Esc` deactivate (REQ-008, REQ-010);
  - wheel sequences for non-reporting backends: first notch = entry +
    3 × C-Up, subsequent = C-Up/Down only; no wheel bindings for
    mouse-reporting backends (REQ-003, REQ-004, REQ-011);
  - attach-script fragment assertions: `mouse on` + WheelDownPane
    binding emitted when `gascity-terminal-ensure-mouse` is t, nothing
    when nil; teardown emits `-u`/unbind restore fragments
    (REQ-005, REQ-012, REQ-013);
  - `[scroll]` marker present exactly while the mode is active
    (REQ-010);
  - no new store/async verbs: the non-blocking verb guard in
    `lisp/test/gascity-store-test.el` needs no additions (REQ-014).
- **Gate:** `scripts/gate.sh` green (whole-package byte-compile with
  `--warnings-as-errors` + full ERT suite).
- **Live e2e acceptance gate (TRAMP):** fresh Emacs inside tmux via
  `scripts/e2e-harness.sh`, connected to
  `/ssh:localhost:/home/roman/bright-lights`; attach a bright-lights
  agent; drive `C-c s`, translated keys, and wheel events; assert
  host-side `pane_in_mode` and `scroll_position` after each step
  (E4–E8 probes); verify teardown leaves default bindings for an
  external `tmux attach`; record the run under `docs/qa/`
  (REQ-001, REQ-013, REQ-014).
- **Traceability:** every requirement REQ-001–REQ-014 maps to the unit
  or e2e checks above (see the coverage matrix).


---

# Artifact excerpt: plan review report (plans/agent-scrolling/plan-review-report.md)

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


---

# Artifact excerpt: canonical implementation summary (plans/agent-scrolling/implementation-summary.md)

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


---

# Artifact excerpt: WI-1 implementation summary (worktrees/ga-7xhp/plans/agent-scrolling/implementation-wi-1-summary.md)

---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-m2hf, formula: do-work}
methodology: {pack: gascity, name: build-basic}
producer: {formula: do-work, stage: implement, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-7xhp
      hash: bead:ga-7xhp
    - path: lisp/gascity-custom.el
      hash: sha256:b7d8cface228695a23e80b898d72db7bb6706173b289f6e60f00f48f720c3e07
    - path: lisp/gascity-terminal.el
      hash: sha256:a6e76ca13f35c0b86f0548e34bc531ee459c02fe6b4bf8a97e64400b1d74f7a3
    - path: lisp/test/gascity-test.el
      hash: sha256:895c84a703c71061888ea092aeb450c679892ab75e421f6c2647c3a6c2cb8fc4
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
---

## Summary

WI-1 (phase P0, steps 1–4) of the agent-scrolling plan: tmux-side
transparent mouse for gascity attach buffers. Added the
`gascity-terminal-ensure-mouse` custom (default t); the attach pre-step's
existing single `gascity-terminal--run-async` round trip now also turns the
session's tmux `mouse` option on (session-scoped) and installs one
copy-mode `WheelDownPane` binding that leaves copy mode when the scroll
position is at the bottom (`if -F '#{==:#{scroll_position},0}' →
`send -X cancel' else `send -X -N 5 scroll-down'). The buffer-teardown
fragments restore both in the same background round trip
(`set-option -u mouse`, `unbind -T copy-mode WheelDownPane`), gated by the
same custom. No new process paths, local or remote (dashboard-v3 D9).

## Intended Behavior

With `gascity-terminal-ensure-mouse` at its default `t`, attaching to an
agent session (local or remote ssh-family city) ensures tmux mouse
scrolling is on for that session, and wheeling through the transcript
returns to the live tail at the bottom instead of staying parked in copy
mode (REQ-001, REQ-005, REQ-012). Killing the terminal buffer restores the
session's `mouse` option and removes the binding, so an external
`tmux attach` sees tmux's defaults (REQ-013). With the custom nil, the
attach script and teardown are byte-identical to the previous behavior.
The status mirror remains optional and independent; the session/socket
locals and the kill-buffer teardown are now installed even when the
mirror is off, because the mouse ensure must be restored regardless.

## Changed Files

- `lisp/gascity-custom.el` — new `gascity-terminal-ensure-mouse` defcustom.
- `lisp/gascity-terminal.el` — mouse ensure/teardown sh fragments, unified
  teardown script, mirror-gated status install, attach pre-step extension.
- `lisp/test/gascity-test.el` — string-fragment tests for the ensure
  script, the attach script (t and nil), the teardown restore, and the
  no-mirror install path.

## Verification

- First verification command: `eldev test gascity-test-terminal` — 27/27
  tests passed, including the five new mouse attach-script/teardown
  fragment tests.
- Final proof command: `scripts/gate.sh` (whole-package
  `eldev compile --warnings-as-errors` + `eldev test`) — PASS:
  compile clean, 739/739 tests passed, 0 unexpected.

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-005 | covered |
| REQ-012 | covered |
| REQ-013 | covered |

## Remaining Risks

- The plan's acceptance pass (live wheel on a bright-lights agent, local
  and over `/ssh:localhost:/home/roman/bright-lights`, plus an external
  `tmux attach` after buffer kill) is an interactive check and has not run
  inside this step; the tmux fragment strings are covered by unit tests
  only.
- The D3 binding is session-scoped; a concurrently attached external
  `tmux` client shares the session, so it sees the binding while a
  gascity attach buffer is open. Teardown restores the default on kill.


---

# Artifact excerpt: WI-2 implementation summary (worktrees/ga-lk9y/plans/agent-scrolling/implementation-wi-2-summary.md)

---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-un0e5, formula: do-work}
methodology: {pack: gascity, name: build-basic}
producer: {formula: do-work, stage: implement, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-lk9y
      hash: bead:ga-lk9y
    - path: lisp/gascity-terminal.el
      hash: sha256:829ca95282d175195b4bcdc2ead2e4a96316ccf33e8cc29090101fa81ae4ce1f
    - path: lisp/test/gascity-test.el
      hash: sha256:bf3334232ecb3ba687f0e4590796f5578b6606c9d8d56a461591f7438a838c4e
  coverage:
    - id: REQ-002
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
---

## Summary

WI-2 (phase P1, steps 5–11) of the agent-scrolling plan:
`gascity-terminal-scroll-mode`, the Emacs-keys scroll sub-mode for gascity
tmux attach buffers (design layer D1). `C-c s` in the attach map toggles
the buffer-local minor mode; activation sends the tmux copy-mode entry
bytes `C-b [`. While active, the mode map's keys translate through the
pure table `gascity-terminal--scroll-sequence` — `C-p`/`C-n` → C-Up/
C-Down bytes (`\e[1;5A`/`\e[1;5B`), `C-v`/`M-v` and PageDown/PageUp →
`\e[6~`/`\e[5~`, `M-<`/`M->` → tmux's own copy-mode `history-top`/
`history-bottom` bytes (`\e<`/`\e>`, locked empirically in the live
pass — see the QA report; the goto-prompt burst left a stuck modal
prompt and a C-Down run cannot settle a deep scrollback), `q` → `q`,
Esc → `\e` — and the
bytes reach the pty through the per-backend raw-key adapter
`gascity-terminal--send-raw` (vterm → `vterm-send-string`, term/
ansi-term → `term-send-raw-string`, eat → `eat-self-input` one
character event per byte, ghostel → `ghostel-send-key` for control
bytes / `ghostel-send-string` for escape sequences, per the E6
semi-char strictness). Unknown backends never error: the toggle and any
send deactivate the mode with an echo-area message (REQ-007). The `q`
and Esc translations leave copy mode and deactivate the mode, handing
the keys back to the agent (REQ-009). Toggle semantics are optimistic
and self-healing: a re-toggle sends `q` first (recovering from an
out-of-band copy-mode exit) then re-enters; no async `pane_in_mode`
resync in v1 (REQ-008). The status mirror's existing segment gains a
live `[scroll]` marker while the mode is active — same segment, no new
one (REQ-010).

## Intended Behavior

In an attach buffer (local or remote ssh-family city), `C-c s` turns
tmux copy mode on and arms the Emacs scroll keys; the user scrolls the
transcript with Magit-style keys while the agent's pty receives none of
them except the explicit byte translations (REQ-002, REQ-009). `q` or
Esc leaves copy mode and the mode deactivates itself; `C-c s` again
recovers from any out-of-band copy-mode exit by sending `q` first
(REQ-008). Each key's bytes go through the backend's own raw-key API,
including ghostel's control/escape split (REQ-006). A backend without
an adapter is reported and refused gracefully (REQ-007). The mode-line
status segment shows `[scroll]` exactly while the mode is active
(REQ-010). No new process paths: everything is byte sends into the
existing pty (dashboard-v3 D9).

## Changed Files

- `lisp/gascity-terminal.el` — the minor mode + map, the pure
  translation table, the per-backend raw-key adapter (with the ghostel
  control-byte splitter), the toggle with optimistic/self-healing
  semantics, the `C-c s` binding in `gascity-terminal-attach-map`, and
  the `[scroll]` marker in `gascity-terminal--status-segment`.
- `lisp/test/gascity-test.el` — table-driven translation tests, adapter
  dispatch tests (including the ghostel split and the unknown-backend
  fallback), toggle idempotence/self-healing tests, and the
  `[scroll]` marker test.

## Verification

- First verification command: `eldev test gascity-test-terminal-scroll` —
  6/6 new scroll tests passed (sequence table, adapter dispatch, unknown
  backend, toggle, marker, bindings).
- Final proof command: `scripts/gate.sh` (whole-package
  `eldev compile --warnings-as-errors` + `eldev test`) — PASS:
  compile clean, 745/745 tests passed, 0 unexpected.

| ID | Status |
| --- | --- |
| REQ-002 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |

- Addendum (post-e2e): the `M-<`/`M->` translations were locked to
  tmux's native `history-top`/`history-bottom` bytes during the WI-4
  live pass; the originally documented goto-prompt and repeated-
  C-Down mechanisms were rejected empirically
  (docs/qa/2026-09-29-agent-scrolling-e2e.md).

## Remaining Risks

- The plan's interactive acceptance (live `C-c s` scroll on a
  bright-lights agent, local and over
  `/ssh:localhost:/home/roman/bright-lights`) has not run inside this
  step; per the AGENTS.md end-to-end protocol it is the reviewer's/
  finalize stage's acceptance gate. All byte tables and dispatch paths
  are covered by unit tests.
- The `M->` bottom-jump mechanism (100 × C-Down) is locked per
  requirements Open Question 1 and the D1 design note, but the exact
  feel (surplus press latency) is only confirmed live in WI-4's pass.
- In ghostel buffers the entry bytes `C-b [` go through
  `ghostel-send-key` + `ghostel-send-string`; the semi-char strictness
  that motivates this is documented from evidence E6 but not exercised
  by a live ghostel session in CI.


---

# Artifact excerpt: WI-3 implementation summary (worktrees/ga-lb0b/plans/agent-scrolling/implementation-wi-3-summary.md)

---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-g4dmp, formula: do-work}
methodology: {pack: gascity, name: build-basic}
producer: {formula: do-work, stage: implement, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-lb0b
      hash: bead:ga-lb0b
    - path: lisp/gascity-terminal.el
      hash: sha256:93682ee57bff52c9ec6d5a6121f547bc35addc9a9fd0b53d72f1151775bd5a15
    - path: lisp/test/gascity-test.el
      hash: sha256:431d8f6d1e77b593d4f7baa8f2160b7419bc5f339b406b440de7d60de8d42dec
  coverage:
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-011
      status: covered
---

## Summary

WI-3 (phase P2, steps 12–13) of the agent-scrolling plan: wheel
translation for non-mouse-reporting backends (vterm, term), on top of
the P1 scroll-mode map (design layer D2). The pure predicate
`gascity-terminal--backend-reports-mouse-p` classifies the backend:
ghostel and eat report the mouse natively (E5), vterm/term/unknown do
not. `<mouse-4>`/`<mouse-5>` are bound in
`gascity-terminal-scroll-mode-map` to `gascity-terminal-scroll-wheel-up` /
`-wheel-down`, which gate on the predicate — on a reporting backend
they send nothing, so ghostel/eat's native tmux passthrough is never
interfered with (REQ-004); on vterm/term a notch sends
`gascity-terminal--wheel-lines` (3, ≈10 lines, tmux `-N 5` feel,
adjustable per requirements Open Question 2) C-Up/C-Down bytes through
the P1 raw-key adapter (REQ-003). The pure sequence constructors
`gascity-terminal--wheel-up-sequence` / `--wheel-down-sequence` carry
the REQ-011 table: the first notch while copy mode is (optimistically)
not yet on self-heals by sending the copy-mode entry bytes `C-b [`
before the C-Up run; while already in copy mode, notches send only
C-Up/C-Down. The optimistic belief is a buffer-local
`gascity-terminal--scroll-copy-on`, set by the `C-c s` toggle after
the entry bytes and reset by the `q`/Esc translations. No new process
paths — wheel notches are plain byte sends into the existing pty
(dashboard-v3 D9).

## Intended Behavior

On vterm or term, `C-c s` once and the wheel scrolls the transcript
through tmux copy mode: each notch ≈10 lines, the first notch
guaranteeing copy mode is entered even when the optimistic state has
it off (REQ-003, REQ-011). On ghostel/eat the wheel keeps working
exactly as before — the Emacs binding is inert for them, both with the
scroll mode off (the map is not consulted) and with it on (the
command gates on the predicate) (REQ-004). The translation reuses the
P1 table constants and adapter, so behaviour is identical to the key
bindings.

## Changed Files

- `lisp/gascity-terminal.el` — the backend mouse predicate, the
  optimistic copy-mode belief flag, the pure wheel sequence
  constructors with the `gascity-terminal--wheel-lines` constant, the
  wheel commands + `gascity-terminal--scroll-wheel` dispatcher, the
  `<mouse-4>`/`<mouse-5>` bindings in the scroll-mode map, and the
  belief wiring in the toggle/`q` paths.
- `lisp/test/gascity-test.el` — predicate, wheel-sequence, dispatch,
  no-interference and bindings tests (table-driven, pure `cl-letf`).

## Verification

- First verification command: `eldev test gascity-test-terminal-scroll`
  — 11/11 scroll tests passed (6 P1 + 5 new wheel/predicate tests).
- Final proof command: `scripts/gate.sh` (whole-package
  `eldev compile --warnings-as-errors` + `eldev test`) — PASS:
  compile clean, 750/750 tests passed, 0 unexpected.

| ID | Status |
| --- | --- |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-011 | covered |

## Remaining Risks

- The plan's interactive acceptance (vterm attach, one `C-c s`, wheel
  scrolls; eat/ghostel unchanged) has not run inside this step — it is
  the P3 live e2e gate (plan steps 14–16). All sequences and dispatch
  paths are unit-tested.
- The `<mouse-4>`/`<mouse-5>` event names are the terminal-emitter
  forms; GUI frames emit `<wheel-up>`/`<wheel-down>`, which terminal
  attach buffers do not receive. If a future backend surfaces wheel
  events under those names, the map needs the extra pair.
- The optimistic copy-mode belief cannot detect an out-of-band copy
  mode exit (no `pane_in_mode` resync in v1); the first wheel-up notch
  self-heals it, matching the D1/D2 optimistic design.


---

# Artifact excerpt: WI-4 implementation summary (worktrees/ga-q3vr/plans/agent-scrolling/implementation-wi-4-summary.md)

---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-x5to4, formula: do-work}
methodology: {pack: gascity, name: build-basic}
producer: {formula: do-work, stage: implement, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-q3vr
      hash: bead:ga-q3vr
    - path: plans/agent-scrolling/requirements.md
      hash: sha256:f06b0f208f018008eb80c7f9123d84d508da9464ab2c37ce4e322488efba1fd4
    - path: docs/DESIGN-agent-scrolling.md
      hash: sha256:f099424db8379e20daf6d23fd7399db65fd25c3c2d7e7dea6fb8f92f984c0870
    - path: docs/qa/2026-09-29-agent-scroll-mouse-experiments.md
      hash: sha256:d77552fa7a3f40807b11ffb2a71b79663e7e979c1673196f7c4b25e1fc9dbe1a
    - path: doc/gascity.texi
      hash: sha256:41b153b7f0136bc1e00e651aa9ab947308045e01b67cd35f844da224206cb340
    - path: lisp/gascity-terminal.el
      hash: sha256:5fecaf5c7a8d6d977ea01a03763d6977c9da5cffce56b946054e62e19069f27d
    - path: docs/qa/2026-09-29-agent-scrolling-e2e.md
      hash: sha256:2e5abb055362ef3a365cdd38620a1f13de105a918080f834639fb6bb405dd7da
  coverage:
    - id: REQ-014
      status: covered
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
---

## Summary

WI-4 (phase P3, steps 14–16) — the closing work item of the
agent-scrolling decomposition (workflow `ga-jwtp`, source anchor bead
`ga-q3vr`): documentation, the live e2e acceptance pass, and the quality
gate. The code phases (WI-1 mouse ensure + wheel-exit binding `adbc52e`,
WI-2 scroll sub-mode `01381c0`/`33ca47f`, WI-3 wheel translation
`71f38df`) were already landed on top of the prepared worktree; this
item locked them:

- `doc/gascity.texi`: the "Attached terminals" section now documents the
  scroll sub-mode (`C-c s`, `gascity-terminal-scroll-toggle` /
  `gascity-terminal-scroll-mode`) with its key table, the per-backend
  mouse behaviour (ghostel/eat report the wheel natively to tmux and are
  never intercepted; vterm/term get the wheel only through the armed
  scroll sub-mode), and the new `gascity-terminal-ensure-mouse` option
  gating the session-scoped `mouse on` and the copy-mode
  `WheelDownPane` exit-at-bottom binding.
- `lisp/gascity-terminal.el`: the attach buffer commentary gained the
  keyboard-layer paragraph (D1 — the toggle, the translation table, the
  per-backend raw-key adapter, the `[scroll]` mode-line marker, the
  self-healing re-toggle) alongside the existing D2/D3 mouse paragraph.
- Empirical lock (requirements Open Question 1, from the live pass): the
  translation table sends tmux's own copy-mode `history-top`/
  `history-bottom` bytes (`\e<`/`\e>`) for `M-<`/`M->`; the
  goto-prompt burst leaves a stuck modal prompt and a repeated C-Down
  run cannot settle a deep scrollback, so neither survived.
  `gascity-terminal--scroll-bottom-repeat` was removed and the
  table-driven tests and the WI-2 summary were amended to match.
- Live e2e acceptance pass recorded in
  `docs/qa/2026-09-29-agent-scrolling-e2e.md` (see Verification).

## Intended Behavior

A user reading an agent transcript in a gascity attach buffer:

- wheels over the buffer and the transcript scrolls — natively through
  tmux on mouse-reporting backends (ghostel/eat, pass-through when the
  agent TUI claims the mouse), through the scroll sub-mode's wheel
  translation on vterm/term after one `C-c s`;
- presses `C-c s` for Emacs-keys scrolling: `C-p`/`C-n` a line,
  `C-v`/`M-v`/PageUp/PageDown a page, `M-<`/`M->` history top/bottom,
  `q`/Esc back to the live agent; the agent receives no keys while the
  mode is on, and the mode line shows `[scroll]` exactly while it is;
- wheeling to the bottom of the history returns to the live tail (the
  session-scoped D3 binding);
- attaches an external `tmux` client and sees tmux defaults after the
  buffer is killed (teardown restores `mouse` and unbinds
  `WheelDownPane`); setting `gascity-terminal-ensure-mouse` to nil
  disables all tmux-side changes;
- reads how all of this works in the manual (`doc/gascity.texi`) and the
  attach buffer commentary.

REQ-014 (docs + green gate) and the e2e halves of REQ-001, REQ-002,
REQ-008, REQ-012 and REQ-013 are owned by this item; the coverage table
traces exactly those. The full requirement matrix lives in the approved
plan (`plans/agent-scrolling/implementation-plan.md`); the code halves
of the other requirements were covered by the WI-1..WI-3 summaries.

| ID | Status |
| --- | --- |
| REQ-014 | covered |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-008 | covered |
| REQ-012 | covered |
| REQ-013 | covered |

## Changed Files

- `doc/gascity.texi` — Attached terminals section rewritten: mouse
  scrolling subsection (per-backend wheel behaviour,
  `gascity-terminal-ensure-mouse`, the D3 bottom-exit binding,
  `history-limit` note) and scroll sub-mode subsection (the `C-c s`
  toggle, the translated key table, self-healing re-toggle, `[scroll]`
  marker).
- `lisp/gascity-terminal.el` — attach buffer commentary: keyboard-layer
  (D1) paragraph; the `M-<`/`M->` table entries locked to `\e<`/`\e>`
  and `gascity-terminal--scroll-bottom-repeat` removed.
- `lisp/test/gascity-test.el` — table-driven translation tests amended
  to the locked byte table.
- `docs/qa/2026-09-29-agent-scrolling-e2e.md` — new live e2e QA report.
- `plans/agent-scrolling/implementation-wi-2-summary.md` — WI-2 summary
  amended to the locked table (its described mechanism changed in the
  live pass).

Committed in the item worktree as `8bde552`
(`docs(agent-scrolling): WI-4 lock-in — texi, commentary, live TRAMP
e2e pass (ga-q3vr)`, cherry-picked unchanged from the parallel
lock-in attempt whose tree is byte-identical: parent `71f38df`).

## Verification

- First verification command — the live e2e acceptance gate, run
  through `scripts/e2e-harness.sh` rules (every emacs/tmux call under
  `timeout(1)`, sessions verified before `send-keys`): fresh
  `emacs -Q` in tmux (server socket `gce-e2e`) with gascity loaded from
  the worktree, city `/ssh:localhost:/home/roman/bright-lights` over
  TRAMP, disposable `scroll-e2e` session on the city's bright-lights
  socket. Host-side probes `tmux -L bright-lights display-message -p
  '#{pane_in_mode} #{scroll_position}'` after each step — **PASS**:
  `C-c s` enters copy mode (`pane_in_mode 1`, agent sees only `C-b [`);
  3 × `C-p` → `scroll_position 3`, `C-n` back; `C-v`/`M-v` page a pane
  apart; `M-<`/`M->` land top/bottom with copy mode still on; first
  wheel notch re-arms entry then +3 per notch; wheel-down −3 and, at
  the bottom, exits copy mode (D3 binding, `pane_in_mode 0`); `q`
  deactivates the minor mode; the self-healing `C-c s` re-toggle
  recovers from a host-side out-of-band `-X cancel`; fresh attach
  shows `mouse on` + `WheelDownPane` bound; `kill-buffer` restores
  both. Full step/probe table in
  `docs/qa/2026-09-29-agent-scrolling-e2e.md`. The pass was driven by
  the parallel lock-in attempt from the `worktrees/ga-lk9y` worktree at
  commit `b884d9c`, whose tree is byte-identical to this worktree's
  `8bde552` (same parent `71f38df`, cherry-pick with no diff); the
  disposable sessions and the e2e Emacs were torn down, and the city's
  own sessions (`mayor`, `core__control-dispatcher-bl-pbib`) were
  untouched.
- Gate command — `scripts/gate.sh` in the item worktree
  (`eldev compile --warnings-as-errors` + full ERT): **PASS** — compile
  clean, "Ran 748 tests, 748 results as expected, 0 unexpected".
- Docs build — `make -C doc`: `gascity.info` and the HTML manual build
  without errors.
- Final proof command (from the launcher rig root, after recording
  `gc.implementation.summary_path` on the workflow root):
  `GC_BEAD_ID=ga-sntw1 .gc/scripts/checks/build-artifact-valid.sh` —
  observed: "build artifact valid:
  schema=gc.build.implementation-summary.v1 path=<this summary>".

## Remaining Risks

- The pass ran on tmux 3.7c with the vterm backend (fresh `emacs -Q`
  resolves vterm); ghostel/eat were exercised in the research probes
  (E4/E5) but not re-driven in this acceptance pass — their contract
  (native passthrough, no interception) is enforced by
  `gascity-terminal--backend-reports-mouse-p` and covered by pure ERT
  tests.
- eat 0.9.4 fails to spawn in this environment (upstream
  `eat-term-get-suitable-term-name` bug, recorded in the experiments
  report); the eat adapter path is covered by stubbed tests only.
- The `M-<`/`M->` lock relies on tmux's default copy-mode emacs table
  binding `M-<`/`M->`; a host with those rebound would scroll
  differently (tmux-side, out of gascity's control, consistent with the
  manual's note about personal `~/.tmux.conf`).
- The e2e Emacs needed `gascity-store` loaded explicitly when loading
  only `gascity-terminal.el` (load-order note in the QA report); in the
  package the load order always loads it first.


---

# Artifact excerpt: live e2e QA report (worktrees/ga-q3vr/docs/qa/2026-09-29-agent-scrolling-e2e.md)

# QA — agent-scrolling live e2e pass (WI-4, workflow ga-jwtp)

Date: 2026-09-29 · Bead: ga-q3vr · Driver: `gascity.el/gc.implementation-worker-1`
(harness rules of `scripts/e2e-harness.sh` applied throughout: every
emacsclient/tmux call bounded, sessions verified before `send-keys`).

## Setup

- Fresh GUI `emacs -Q` (vterm backend available) inside tmux, server
  socket `gce-e2e`; gascity loaded from the worktree
  `worktrees/ga-lk9y` on top of WI-1 (`adbc52e`), plus WI-2 (`01381c0`)
  and WI-3 (`71f38df`).
- City: `bright-lights` at `/home/roman/bright-lights`, opened as
  `/ssh:localhost:/home/roman/bright-lights` — every step below ran
  over TRAMP; the tmux client is a local `ssh -t` vterm process.
- Disposable session `scroll-e2e` on the city's `bright-lights` socket
  (500 lines of scrollback via `seq 1 500; exec cat`); the city's own
  sessions (`core__control-dispatcher-bl-pbib`, `mayor`) were never
  touched and were still intact afterwards.

## Results

| Step | Probe (host side, `display-message`) | Result |
| --- | --- | --- |
| baseline | `pane_in_mode` | 0 |
| `C-c s` | `pane_in_mode` | 1 — copy mode entered; agent sees only `C-b [` (REQ-002) |
| 3 × `C-p` | `scroll_position` | 3 — viewport scroll, E7 translation confirmed |
| `C-n` | `scroll_position` | 2 |
| `C-v` / `M-v` | `scroll_position` | page down / up land a pane apart |
| `M-<` | `scroll_position` | history-top, copy mode stays on (locked table) |
| `M->` | `scroll_position` | history-bottom (0), copy mode stays on (locked table) |
| first `<wheel-up>` notch | `pane_in_mode`, `scroll_position` | entry re-armed + C-Up run (REQ-011) |
| 2 × later notch | `scroll_position` | +3 per notch, exactly `gascity-terminal--scroll-wheel-notch` |
| `<wheel-down>` notch | `scroll_position` | −3 per notch |
| `q` | `pane_in_mode` | 0, `gascity-terminal-scroll-mode` deactivated (REQ-009) |
| `C-c s` again | `pane_in_mode` | 1 |
| host-side `-X cancel` (out-of-band exit) | `pane_in_mode` | 0, minor mode still armed |
| `C-c s` (self-healing re-toggle) | `pane_in_mode` | 1 — q first, then re-entry (REQ-008) |
| fresh attach | `show-options mouse`, `list-keys copy-mode` | `mouse on`, `WheelDownPane` bound (WI-1 ensure, REQ-005) |
| `kill-buffer` | same probes | `mouse` unset, `WheelDownPane` unbound — an external `tmux attach` sees defaults (REQ-013) |

## The M-< / M-> lock (requirements Open Question 1)

The v1 table's planned bottom-jump mechanisms both failed live:

- **goto-prompt burst (`g` `0` `RET`).** Worked once (prompt opened),
  but when the submit did not land the modal prompt stayed open and
  **silently swallowed every following byte** — the vterm buffer sat at
  `(goto line) 1;5B[[[q` while every "dead" keystroke was being typed
  into the prompt. Worst possible failure mode for a scroll feature:
  no error, no feedback, keys leaking into a hidden prompt. Not used.
- **Repeated C-Down (`\e[1;5B` run).** Fragile: with the prompt open or
  after any desync the sequences typed literal `1;5B` into it; and a
  run cannot settle a deep scrollback cheaply. Not used.
- **Locked: tmux's own copy-mode emacs bindings.** The host tmux binds
  `M-<` → `history-top` and `M->` → `history-bottom`; the table now
  sends the single modified-key bytes `\e<` / `\e>`. Verified live:
  jump to top (432) / bottom (0), copy mode stays on, no prompt, no
  leak. This also resolves the mechanism for arbitrary
  `history-limit`.

## Deviations from the bead text

- WI-2's bead prescribed "repeated C-Down until position settles" for
  `M->` and the goto prompt for `M-<`. The live pass (which the bead
  deferred to, per requirements Open Question 1) locked both to tmux's
  native `history-top`/`history-bottom` bytes instead; the translation
  table and its tests were amended accordingly (`\e<` / `\e>`).
- `gascity-terminal--scroll-bottom-repeat` was removed (the constant's
  mechanism did not survive contact with the host).

## Environment notes (not product bugs)

- The e2e Emacs loaded only `gascity-terminal.el` at first, so
  `gascity-remote-async-timeout` (defined in `gascity-store.el`) was
  void and one attach's deadline-timer setup and one kill-buffer
  teardown silently failed. After `require`ing `gascity-store`, attach
  ensure and kill-buffer teardown both verified end to end. In the
  package the load order (gascity.el) always loads gascity-store first;
  noted here only because the first teardown failure looked like a
  product bug.
- A live attach buffer is raised without a new pre-step (the idempotent
  reuse contract), so re-attaching never re-ensures `mouse on` — the
  option survives from the first attach and is restored only at
  teardown, as designed.

## Hygiene

Disposable sessions (`scroll-e2e`) and the e2e Emacs killed at the end;
the city's own sessions untouched. `scripts/gate.sh` PASS after the
table lock: compile clean (`--warnings-as-errors`), 748/748 tests.
