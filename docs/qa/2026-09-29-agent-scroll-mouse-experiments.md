# Agent buffer scroll/mouse experiments — bead ga-n21o

Date: 2026-09-29. Research + plan only (no product code touched). All
experiments validate load-bearing assumptions for the agent-buffer scrolling
design in `docs/DESIGN-agent-scrolling.md`.

Environment: Emacs 31.1, GUI (Wayland/sway), tmux 3.7c, this repo's `lisp/`
+ sibling `~/workspace/beads.el`. Testbed: disposable tmux sessions on the
bright-lights city socket (`tmux -L bright-lights`), attached through
`gascity-terminal-attach-tmux` exactly as the porcelain attaches real agents
(remote shape: `/ssh:localhost:/home/roman/bright-lights` — local ssh client,
identical byte path for all key/mouse injection).

Harness: a fresh `emacs -Q` GUI instance under tmux (`gce-e2e-scroll`),
driven by `emacsclient -s ga-n21o -e` evals; every emacs/tmux call wrapped in
`timeout(1)` per the e2e-harness rules. Wheel events were synthetic
(`(list 'wheel-up (posn-at-x-y 5 5 WIN) '(1) 3 nil)` pushed to
`unread-command-events`); tmux state probed host-side via
`tmux display-message -p '#{pane_in_mode} #{scroll_position} …'`.

## E1 — which backend does an attach resolve to?

- Fresh GUI `emacs -Q` (no init): `beads-terminal-auto` → **vterm**.
- With `ghostel` loaded (its `beads-terminal-available-p` is strict:
  requires the feature AND `ghostel-exec` already bound — a fresh Emacs
  never loads it), `auto` → **ghostel**.
- In the experiment the first attach resolved to `vterm-mode`; a second
  attach with `gascity-terminal-backend 'ghostel` resolved to
  `ghostel-mode` (`alt-screen t`, `mouse-tracking t`,
  `ghostel--input-mode semi-char`).
- `eat` 0.9.4 failed to spawn here (`Wrong type argument: arrayp,
  eat-term-get-suitable-term-name`) — noted as an environment caveat; eat
  would follow the same mouse contract per its source (`eat-enable-mouse`,
  SGR mouse encoding in `eat--t-*` functions).

## E2 — the tmux client owns the whole screen (alt screen)

With `ghostel`, the attach buffer reports `ghostel-alt-screen-p = t`. The
tmux client switches the outer terminal to the alternate screen, so:

- the Emacs window shows only the visible screen;
- `scroll-up-command`/wheel-without-tracking scroll a buffer with nothing
  above it;
- ghostel's own 5 MB scrollback (`ghostel-max-scrollback`) is irrelevant
  for attach buffers.

This is why Emacs-native scrolling of the attach buffer is dead today, and
why the `unshadow-keys` comment says "the buffer holds only the visible
screen".

## E3 — vterm: wheel never reaches tmux

vterm attach buffer, `mouse on` on the tmux server, 339 lines of pane
history. Injected 3 × `wheel-up` then 3 × `wheel-down`:

    pane_in_mode stayed 0, scroll_position stayed 0

vterm does not implement xterm mouse reporting, so wheel events fall
through to mwheel scrolling of a screen-only buffer: a no-op. **Mouse
scrolling cannot work over a vterm attach without Emacs-side translation.**

## E4 — ghostel + `mouse on`: wheel already scrolls the transcript

ghostel attach buffer, tmux `mouse on` (the user's `~/.tmux.conf`; gc does
not set it). Injected 3 × `wheel-up`:

    pane_in_mode 1, scroll_position 10   ← copy mode entered, scrolled

The tmux client requests mouse tracking from the client terminal
(`ghostel--mouse-tracking-p = t`), ghostel forwards wheel as SGR mouse
button 4, and tmux's default `WheelUpPane → send -X -N 5 scroll-up`
binding scrolls the scrollback automatically. **With a mouse-reporting
backend (ghostel/eat), transparent wheel scrolling already works — zero new
Emacs code.** The dependency chain is: backend forwards mouse ⇐ backend
supports it; tmux interprets wheel ⇐ `mouse on` (not guaranteed by gc).

## E5 — the mouse collision: an app claiming mouse wins (correctly)

Enabled mouse reporting in the test pane's app
(`printf '\033[?1000h\033[?1006h'` → `mouse_any_flag 1`), injected 3 ×
`wheel-up`:

    pane_in_mode stayed 0   ← event went to the app, not copy mode

Disabled again (`\033[?1000l\033[?1006l` → `mouse_any_flag 0`): wheel
scrolls copy mode again. So the wheel is a *pass-through* when the agent
TUI wants mouse input (e.g. pi's fullscreen transcript scrolling,
`--tui-mode fullscreen`) and a *scrollback control* otherwise. tmux picks
correctly by itself; nothing to implement, just to document.

## E6 — the keyboard path works on every backend, via raw bytes

All from the attach buffer (raw bytes through the pty — identical for
local and remote cities, since the tmux client is a local process either
way):

| Bytes | Result |
|---|---|
| `C-b` `[` | copy mode entered (`pane_in_mode 1`) |
| `\e[1;5A` / `\e[1;5B` (C-Up/C-Down) | `scroll_position` ±1 — true viewport scroll |
| `\e[5~` / `\e[6~` (PPage/NPage) | page up/down (position jumped ~pane height) |
| `M-v` / `C-v` | page up/down (tmux copy-mode emacs table) |
| `q` | copy mode exited (`pane_in_mode 0`) |

Backends' raw-send APIs used and verified: `vterm-send-string` (works for
control bytes and escape sequences), `ghostel-send-key` (key name +
modifier string), `ghostel-send-string` (escape sequences pass; **control
bytes did not** in semi-char mode — `C-b` needed `ghostel-send-key`).
Design consequence: the scroll feature needs a small per-backend raw-key
adapter, not a raw-bytes assumption.

## E7 — C-p/C-n in copy mode are cursor moves, not scrolls

tmux's copy-mode emacs table binds `C-p`/`C-n` to `cursor-up`/`cursor-down`
(verified in `list-keys -T copy-mode`). Three `C-p`s moved the cursor but
left `scroll_position 0`. The viewport-scroll keys are `C-Up`/`C-Down`.
An Emacs-flavoured scroll mode must therefore translate
`C-p`/`C-n` → `C-Up`/`C-Down` bytes, not forward them as-is.

## E8 — wheel-down at the bottom does NOT exit copy mode (tmux 3.7c)

From `scroll_position 3`, injected 3 × `wheel-down` (each −5 lines by
tmux's `WheelDownPane` binding), then one more:

    pane_in_mode 1, scroll_position 0   ← still in copy mode

tmux 3.7c's default `WheelDownPane` binding has no exit-at-bottom logic.
UX gap: after mouse-scrolling up, the user must press `q`/Esc to return to
the live tail. Fix is a one-line session-scoped tmux binding installed at
attach (see design doc §D3):

    bind -T copy-mode WheelDownPane select-pane \
      \; if -F '#{==:#{scroll_position},0}' 'send -X cancel' 'send -X -N 5 scroll-down'

## E9 — the C-n/C-p collision with the agents' own keys

From pi 0.87 keybindings docs (`keybindings.md`): the prompt editor binds
`ctrl+p`/`ctrl+n` to history previous/next, `ctrl+p` cycles models, and
session selectors use both. So a *normal-mode* transparent `C-n`/`C-p`
scrolling binding would eat the agents' editor keys on the way through.
The design scopes every Emacs scroll keybinding to an explicit, user-
toggled scroll sub-mode (copy mode active — the agent receives nothing
while it is on).

## Testbed hygiene

All disposable sessions (`scroll-test`, `scroll-eat`, `t2`, the experiment
Emacs) killed at the end; the bright-lights city's own sessions
(`mayor`, `core__control-dispatcher-bl-pbib`) untouched. No product files
modified.
