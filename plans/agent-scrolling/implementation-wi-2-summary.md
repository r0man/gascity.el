---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-jwtp, formula: build-basic}
methodology: {pack: gascity, name: build-basic}
producer: {formula: build-basic, stage: implement, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-lk9y
      hash: bead:ga-lk9y
    - path: plans/agent-scrolling/implementation-plan.md
      hash: bead:ga-jwtp
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

WI-2 (phase P1, steps 5–11) of the agent-scrolling plan: the
`gascity-terminal-scroll-mode` Emacs-keys scroll sub-mode for attach
buffers (design layer D1). `C-c s` in `gascity-terminal-attach-map`
toggles a buffer-local minor mode whose keys are translated by the pure
table `gascity-terminal--scroll-sequence` — C-p/C-n → C-Up/C-Down bytes
(E7: C-p/C-n in tmux copy mode are cursor moves, not scrolls), C-v/M-v
and PageDown/PageUp → PPage/NPage, M-< → `g` `0` `RET` through the goto
prompt, M-> → `gascity-terminal--scroll-bottom-repeat` (100) C-Downs
settling at the bottom per requirements Open Question 1, q → `q`, Esc →
`\e` — and sent through the per-backend raw-key adapter
`gascity-terminal--send-raw` (vterm → `vterm-send-string`; term/
ansi-term → `term-send-raw-string`; eat → `eat-self-input`, one
character event per byte; ghostel → `ghostel-send-key` for control
bytes, `ghostel-send-string` for escape sequences and printable runs,
per E6's semi-char strictness). While the mode is active the agent
receives no keys (E9); the status mirror's existing segment gains a
`[scroll]` marker (REQ-010), evaluated live in
`gascity-terminal--status-segment` so it never lags a refresh tick.

## Intended Behavior

In any attach buffer (local or remote ssh-family city — the tmux client
is a local process either way), `C-c s` sends the copy-mode entry bytes
`C-b [` and arms the map; C-p/C-n/C-v/M-v/PageUp/PageDown/M-< then drive
tmux copy mode with Magit-flavoured keys, and q/Esc leave copy mode and
deactivate the mode. The toggle is optimistic + self-healing (REQ-008):
re-toggling while the mode thinks it is active sends `q` first,
recovering from an out-of-band copy-mode exit, then re-enters; there is
no async `pane_in_mode` resync in v1. On a backend with no raw-key
adapter the mode deactivates with an echo-area message instead of
erroring (REQ-007). Purely byte sends: no new processes, so the
non-blocking rule (dashboard-v3 D9) costs nothing.

## Changed Files

- `lisp/gascity-terminal.el` — the scroll section (translation table,
  backend probe, ghostel control/escape split, raw-key adapter, key
  command, toggle, keymap, minor mode), the `C-c s` binding in
  `gascity-terminal-attach-map`, and the `[scroll]` marker in
  `gascity-terminal--status-segment`.
- `lisp/test/gascity-test.el` — six new tests: table-driven translation
  cases; adapter dispatch per backend major mode including the ghostel
  control/escape split; the unknown-backend fallback (never errors);
  toggle idempotence and the self-healing q-first re-toggle plus the
  q/Esc deactivations; the `[scroll]` marker; the `C-c s` and D1
  keymap bindings.

## Verification

- First verification command: `eldev test gascity-test-terminal` —
  33/33 tests passed, including the six new scroll-mode tests.
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

- The M-> bottom-jump constant (100 C-Downs) covers ~100 lines of
  distance per press run; the live e2e pass (WI-4) locks the feel per
  requirements Open Question 1 and may adjust
  `gascity-terminal--scroll-bottom-repeat`.
- Optimistic state: after an out-of-band copy-mode exit (e.g. the D3
  wheel binding leaving at the bottom) the next translated key can land
  in the agent's editor once; a re-toggle (`C-c s`) recovers. Accepted
  by the design for v1.
- Echo-area feedback on toggle (step 6) reports "scroll mode on/off";
  the plan defers full documentation (doc/gascity.texi) to WI-4.
