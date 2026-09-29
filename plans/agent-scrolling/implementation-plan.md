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
