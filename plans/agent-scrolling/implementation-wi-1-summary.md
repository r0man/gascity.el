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
