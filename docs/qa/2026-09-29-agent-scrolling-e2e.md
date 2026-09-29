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
