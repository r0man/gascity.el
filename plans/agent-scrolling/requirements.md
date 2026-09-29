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
