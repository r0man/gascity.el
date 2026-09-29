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
