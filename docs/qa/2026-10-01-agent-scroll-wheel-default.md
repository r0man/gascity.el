# QA — agent-buffer wheel out of the box + deterministic backend (ga-eqpxs)

Date: 2026-10-01 · Bead: ga-eqpxs · Driver: `gascity.el/gc.implementation-worker-1`
(harness rules of `scripts/e2e-harness.sh` applied: every emacsclient/tmux
call bounded, sessions verified before use).

## Symptom and root cause

Scrolling an agent (tmux attach) buffer with the mouse "not always"
worked.  Two independent causes, both confirmed:

1. **Backend choice was load-order dependent.**  `gascity-terminal-backend`
   unset resolved through beads.el's `beads-terminal-auto`, whose ghostel
   availability is `(featurep 'ghostel)` — true only once something else
   had loaded ghostel.  A fresh `emacs -Q` therefore picked **vterm**, on
   which the wheel never reaches tmux (E3); after any earlier ghostel use
   it flipped to ghostel (native mouse passthrough) and the wheel worked.
2. **The wheel translation was armed only by `C-c s`.**  On vterm/term the
   vui `gascity-terminal-scroll-mode` map carried the wheel notches, but
   only while the user had toggled the mode; out of the box the wheel fell
   through to global `mwheel-scroll` on a transcript-less alt-screen buffer —
   a no-op.

## Fix A — deterministic backend (ga-eqpxs FIX A)

`gascity-terminal--ghostel-available-p` probes by **attempting the load**
(from a local `default-directory`, never TRAMP) and then asks
`beads-terminal-available-p`; `gascity-terminal--backend-class` uses it
when the backend is unset, so ghostel wins whenever it is installed and
the choice no longer depends on load order.  beads.el is untouched.
Explicit `vterm`/`eat`/`term` are never overridden.

Batch evidence, fresh `emacs -Q --batch` with `lisp/` on `load-path`:

    fresh-backend-class=beads-terminal-ghostel ghostel-avail=t client-term="xterm-ghostty"

(i.e. the first attach now resolves to ghostel, whose native mouse
passthrough was already verified in E4/E5.)

## Fix B — wheel armed on attach, injected as tmux's own mouse event

A wheel-only minor mode (`gascity-terminal-wheel-mode`, map
`gascity-terminal-wheel-map`) is enabled by `gascity-terminal--arm-wheel`
in every attach buffer whose backend does **not** report the mouse
(vterm/term), from `gascity-terminal--install-keys`.  It carries no D1
keyboard bindings, so the agent keeps every key; ghostel/eat never get it.

A notch is injected as the SGR mouse event a reporting terminal would send
(`gascity-terminal--wheel-mouse-sequence`: button 64 up / 65 down at the
pane's top-left), so **tmux's own** WheelUpPane/WheelDownPane handling runs
— enter copy mode, scroll, and leave at the bottom (the D3 behaviour) —
with no Emacs-side copy-mode state.  With the explicit `C-c s` scroll mode
active the D2 key translation is kept, so a mouse-claiming agent cannot
steal an explicit scroll request.

### Tmux-level check (raw pty, default bindings, no config)

Injecting `\e[<64;2;2M` / `\e[<65;2;2M` into a tmux client pty
(socket/session disposable, `-f /dev/null`):

    init:     mode=0 pos= hist=278
    3up:      mode=1 pos=10
    1down:    mode=1 pos=5
    6down:    mode=0 pos=          ← wheel-down to the bottom leaves copy mode

### Live e2e through a real vterm

Fresh `emacs -nw -Q` in a tmux session (`gce-eqpxs`, server socket
`gce-eqpxs`), gascity loaded from the worktree; a disposable target session
`live` on socket `ga-eqpxs` (400 lines, `mouse on`, `sleep 600`).  The
attach buffer was spawned as a real vterm running
`env -u TMUX tmux -L ga-eqpxs attach-session -t live`; `gascity-terminal--install-keys`
armed the wheel automatically.

    armed:      (vterm-mode t)          ← wheel mode on, no C-c s
    initial:    mode=0 pos=
    1 × wheel-up:   mode=1 pos=0        ← entered copy mode
    +3 wheel-up:    mode=1 pos=15       ← scrolls (5/notch, tmux default)
    1 × wheel-down: mode=1 pos=10
    1 × wheel-down: mode=1 pos=5
    further down:   mode=0 pos=          ← back to the live tail at the bottom

`scripts/gate.sh`: PASS (compile clean + 775/775 ERT, incl. the new
backend-selection, wheel-armed-default and wheel-injection tests).
`scripts/lint.sh`: clean.

## Out of scope / untouched

- beads.el (availability policy lives on the gascity side).
- The attach pre-step's tmux mouse/status logic (`gascity-terminal-ensure-mouse`
  still installs `mouse on` + the D3 `WheelDownPane` binding; that is what
  makes the injected event meaningful).
- ghostel/eat are not double-driven — their native passthrough wins.
