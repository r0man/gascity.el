---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-jwtp, formula: build-basic}
methodology: {pack: gascity, name: build-basic}
producer: {formula: build-basic, stage: implement, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-lb0b
      hash: bead:ga-lb0b
    - path: plans/agent-scrolling/implementation-plan.md
      hash: bead:ga-jwtp
    - path: lisp/gascity-terminal.el
      hash: sha256:32b26178b872f0801adf4fb8a3f2a298efa29d4713a5e8fb4a1ac9355418ed4f
    - path: lisp/test/gascity-test.el
      hash: sha256:ba929c1e8d48a3997dc96129dcd7e39130e8edd05b4d9007344d31d22655264f
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
translation for backends that do not report the mouse, layered on the
WI-2 scroll-mode map. Added the pure predicate
`gascity-terminal--backend-reports-mouse-p` (ghostel, eat → t;
vterm, term/ansi-term, unknown → nil, per E4/E5). The scroll mode's
buffer-local effective map now carries the wheel bindings
(`gascity-terminal-scroll-wheel-map`, D1 keys as parent plus
`<mouse-4>`/`<mouse-5>`/`<wheel-up>`/`<wheel-down>`) ONLY on
non-reporting backends, installed buffer-locally through
`minor-mode-overriding-map-alist` in the mode body and removed on
deactivate — so ghostel/eat's native tmux passthrough is never
intercepted, with the mode on or off (REQ-004; their base map has no
wheel bindings at all). `gascity-terminal-scroll-wheel` sends one
notch as `gascity-terminal--scroll-wheel-notch` (3, adjustable per
requirements Open Question 2) C-Ups or C-Downs; the first notch after
(re-)entry re-sends the copy-mode entry bytes before the run (REQ-011,
armed by the toggle, cleared by the first notch) — uniform with the
toggle's self-healing. Wheel-down relies on the D3 binding to leave
copy mode at the bottom.

## Intended Behavior

On vterm/term, `C-c s` arms wheel scrolling: each notch scrolls ≈10
lines of the transcript through tmux copy mode, no tmux-side
dependencies and no per-notch processes (REQ-003). On ghostel/eat
nothing changes with the mode on or off — the wheel keeps flowing
through the backends' native mouse reporting to tmux (E5, REQ-004).
Purely byte sends; no new process paths, timers, or sync calls
(dashboard-v3 D9).

## Changed Files

- `lisp/gascity-terminal.el` — the mouse-reporting predicate, the
  `gascity-terminal--copy-mode-entry` constant (one source of truth
  for the entry bytes, now shared with the toggle), the notch
  constant, the first-notch state, the wheel map and command, and the
  per-backend effective-map selection in the minor mode body.
- `lisp/test/gascity-test.el` — three new tests: the predicate table;
  the effective-map selection (base map never carries wheel bindings;
  ghostel installs no extension, vterm installs the wheel map,
  deactivation removes it); and notch sequencing (first = entry +
  run, later = run only, down = the C-Down mirror).

## Verification

- First verification command: `eldev test gascity-test-terminal` —
  36/36 tests passed, including the three new wheel tests.
- Final proof command: `scripts/gate.sh` (whole-package
  `eldev compile --warnings-as-errors` + `eldev test`) — PASS:
  compile clean, 748/748 tests passed, 0 unexpected.

| ID | Status |
| --- | --- |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-011 | covered |

## Remaining Risks

- The notch line count (3 × C-Up ≈ 10 lines) and the first-notch
  re-entry heuristic are v1 guesses the live e2e pass (WI-4) tunes per
  requirements Open Question 2; both are single adjustable constants.
- After the D3 binding exits copy mode at the bottom, wheel-down
  notches keep sending C-Down bytes that land in the agent's editor
  (the known optimistic-desync leak, v1 accepted); an up-notch's
  first-notch re-entry recovers it.
- GUI Emacs may deliver `wheel-up`/`wheel-down` rather than the
  legacy `mouse-4`/`mouse-5`; both pairs are bound to be safe.
