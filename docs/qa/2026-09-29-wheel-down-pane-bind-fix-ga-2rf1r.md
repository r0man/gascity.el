# QA: copy-mode WheelDownPane bind fix (ga-2rf1r)

Date: 2026-09-29 · Bead: ga-2rf1r (P2 bug) · Ride: PR #2
`publish/agent-scrolling-ga-jwtp` · Environment: tmux 3.7c, socket
`emacs-city` (live city)

## Defect

`gascity-terminal--mouse-ensure-script` bound copy-mode `WheelDownPane`
with the compound command split across argv words. tmux 3.7c splits
commands from argv only at words *ending* in a plain `;`, so the `if`
ran immediately at bind time (failing "not in a mode") and the key was
bound to bare `select-pane`: wheeling into copy-mode never exited back
to the live tail at the bottom (the E8 fix never took effect). The
intermediate repair idea — passing `\;` as its own argv word — does not
work either (the escaped form converts to a literal `;` argument, and
at *fire* time it is not a separator: "command select-pane: too many
arguments"). Verified against tmux source 3.7c
(`cmd_parse_from_arguments` in cmd-parse.y, `cmd_bind_key_exec` in
cmd-bind-key.c).

## Fix

The whole compound reaches tmux as ONE argv word, with the
scroll-or-cancel chain expressed as an unquoted brace group (brace
groups parse into structured command lists; quoted ones stay strings
and fail at fire time):

```
tmux -L SOCKET bind -T copy-mode WheelDownPane \
  'if -F '"'"'#{==:#{scroll_position},0}'"'"' '\''send -X cancel'\'' { select-pane; send -X -N 5 scroll-down }'
```

`scroll_position` counts lines scrolled up from the bottom, so
`==0` means "at the bottom": the binding cancels copy-mode there and
selects + scrolls otherwise. Factored as
`gascity-terminal--mouse-wheel-command`; the teardown mirror's
`unbind -T copy-mode WheelDownPane` is unchanged (key tables are
server-global — no `-t` exists for them).

## ERT

`gascity-test-terminal-mouse-ensure-script` now (a) asserts the
installed binding's VALUE via `list-keys` on a scratch socket (the
shape of the trap: the old checks only saw that the command ran),
and (b) fires the same command through the copy-mode key table —
bound to `C-o`, which `send-keys` dispatches like a real key —
asserting scroll keeps copy-mode (pos 10 → 5, `pane_in_mode` 1) and
the bottom fire leaves it (`pane_in_mode` 0).

`scripts/gate.sh`: PASS (compile clean, 748 tests green).

## Live check (2026-09-29, socket `emacs-city`, tmux 3.7c)

Fresh session `gc-live-wheel-check` on the live city socket; the exact
pre-step fragment was run as the attach pre-step would:

- `tmux -L emacs-city list-keys -T copy-mode` shows the binding:
  `bind-key -T copy-mode WheelDownPane if-shell -F
  "#{==:#{scroll_position},0}" "send -X cancel" { select-pane ;
  send-keys -X -N 5 scroll-down }`
- Fired through the same key table (`C-o` bound to the identical
  command, dispatched with `send-keys`; the mouse event itself cannot
  be scripted): after scroll-up pos=10/in_mode=1 → fire → pos=5/
  in_mode=1; wheeling to the bottom in 5-line steps, the fire at
  `scroll_position` 0 exits copy-mode (`pane_in_mode` 0). RESULT: PASS.
- Cleanup killed only the fresh session. The socket-global binding was
  left installed: it matches the intended post-fix behavior, and every
  attach pre-step reinstalls it.

Scripted evidence (wrapped in `timeout(1)`, bounded loops):
`/tmp/gc-live-check.sh` reproduction of the pass above.
