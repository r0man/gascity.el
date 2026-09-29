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
`\e[6~`/`\e[5~`, `M-<` → `g` `0` `RET` via the goto prompt, `M->` → a run
of C-Down (`\e[1;5B`, `gascity-terminal--scroll-bottom-repeat` = 100
presses) that settles at the bottom, `q` → `q`, Esc → `\e` — and the
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
