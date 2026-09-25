# Dashboard v3 P4 — Events view and mail: live pass

2026-09-25 · branch `v3-comms` · gc 1.4.2 · Emacs 31.1 (`emacs -nw` in
tmux `v3-comms`, byte-compiled, opened by keystrokes like a user).
Cities: `~/emacs-city` read only; `~/bright-lights` locally and as
`/ssh:localhost:/home/roman/bright-lights` (store ssh-pipe transport).

## Events (`gascity-events`, §7.8)

| Check | Local emacs-city | Remote bright-lights |
|---|---|---|
| Open, 2h window | 1507 events, 1481 folded into ×N rows, ■ `session.cold_start_timeout`, ▲ `bead.dead_assignee_reopened` rows; max stall 190 ms at open | 1536 events, header `bright-lights @localhost`; max stall 52 ms |
| SPC on ×N | unfolds in place (▾ + child rows), SPC again folds | same |
| `/ -l attention` | 7 rows, all ■; header `signal ≥ attention` | — |
| `/ -W 24h` | 15.5k events (13 MB): **1058 ms stall** at first, fixed (below) to ~190 ms | 9550 events, max stall 73 ms |
| `/ -t session.woke` (server `--type`) | 42 rows; header `type=session.woke` | — |
| RET bead event | `ec-6leu` opens in beads.el (city store) | — |
| RET session event | live agent → `*gascity-agent: beads.el/gc.publisher-1*`; closed session → echo `Session bd__dog-ec-lpwt is gone` | — |
| `j e` from cockpit / inbox | opens the view | — |

Fixes made during the pass (all committed on the branch):

- 24h stall: `iso8601-parse` over 15k timestamps took 0.55 s → a
  direct RFC 3339 path in `gascity-ui-parse-time`; the 13 MB JSONL
  parse moved out of the sentinel into the process filter
  (incremental); SPC reuses the fold.  1058 ms → ~190 ms (what is left
  is folding/rendering 15k events once).
- `7d` window: gc rejects `--since 7d` (`unknown unit "d"`); days are
  sent as hours.  On emacs-city `--since 168h` then times out inside
  gc itself (`context deadline exceeded` from the supervisor API); the
  view shows that error in its header and keeps the previous rows.
- Time column narrowed to `HH:MM` while every row is today.

## Mail (`gascity-mail`, §7.9)

bright-lights human inbox before: 4 unread / 4 (`Dolt health advisory`
wisps), mayor inbox 0.

| Check | Local | Remote |
|---|---|---|
| Open | `4 unread / 4`, ● + bold rows, relative When | same, `@localhost` |
| RET | thread-style buffer from the payload, no gc call, still unread (gc count 4/4) | — |
| `r` | thread opens at once with `…`, row shows `…`, then thread fills, row loses ●, gc unread 3 | same; max stall 5 ms |
| open thread after mark-read | kept `● unread` → **fixed**: settled actions re-render threads | fixed |
| `u` in thread | `Marked unread …`, 4/4 | same |
| region `r` (2 rows) / region `u` (3 rows) | `…` on each row, `Marked read 2 messages` / `Marked unread 3 messages` | — |
| `c c` compose to mayor | Notify line toggles with C-c C-n; C-c C-c closes the draft at once; body `line one with "quotes" and $HOME and \`ticks\`` + `# a markdown heading` arrived byte-exact | body with `'single' "double" $PATH; rm -rf nothing && echo \`x\`` arrived byte-exact over the ssh pipe |
| `R` reply + `a` archive | reply landed in the human inbox (5/5), `a` → `Archive message …? (y/n)` → `Archived …`, 4/4 | — |

## State changes on bright-lights, and their restoration

- Sent 2 test messages to mayor (`bl-wisp-tasrqg`, `bl-wisp-9yhi48`) →
  archived both (`gc mail archive`); mayor inbox 0 again.
- Replied once (`bl-wisp-29sxgr`, to human) → archived from the UI.
- Mark read/unread round trips on the 4 human messages → all unread.
- **gc sweep race:** 21 s after `bl-wisp-a7gsqc` had been marked unread
  again, gc's mail sweeper closed it (`close_reason: mail gc-swept: read
  mail bead past gc retention window`; `bead.closed` by
  cache-reconcile).  It had been read for 8 s.  Reopened with `gc bd
  reopen`; metadata `mail.read: false`; still open minutes later.
  Final state: 4 unread / 4, mayor 0 — as before the pass.

## Not covered live

- Live append (`gascity-events--append`): `gascity-live` is not on main
  yet; covered by ERT (debounce, seq dedup, type filter, merge after an
  in-flight read).
- `Send mail to:` prompt takes ~3 s to appear remotely: its completion
  table (`gascity-action--session-names`) is a synchronous `gc session
  list`, input-gathering code that predates this branch.
