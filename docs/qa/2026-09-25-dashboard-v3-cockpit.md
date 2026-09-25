# Dashboard v3 P0/P2 — cockpit dogfood (2026-09-25)

Branch `v3-cockpit`. gc 1.4.2, Emacs 31.1. Cities: `~/emacs-city` (read
only) and `~/bright-lights`, local and `/ssh:localhost:` (tramp-sh).

## Method

- Batch render (`emacs --batch`, `timeout 120/180`): open the cockpit with
  `gascity-dashboard`, wait (capped loop) until no read is pending, print the
  buffer and the header line.
- Interactive pass in a fresh `emacs -nw -Q` inside tmux session
  `v3-cockpit-e2e` (server `v3-cockpit-e2e`, every call through
  `scripts/e2e-harness.sh` helpers), views opened by keystrokes (`M-x cd`,
  `M-x gascity-dashboard`), then TAB/S-TAB/SPC/RET/`?`/`j m`/SPC-detail/`q`.
  Session killed afterwards.

## Results

| Check | Local | Remote (`/ssh:localhost:`) |
|---|---|---|
| emacs-city cockpit ≤ 80 lines, defaults | 38 lines | — |
| No line mentions a missing gc surface | yes | yes |
| bright-lights body identical local vs remote | — | identical except live ages (`active 2s`/`4s`) when all reads succeed |
| TAB/S-TAB visit things in order, wrap | yes | yes |
| SPC folds a section / opens a drawer / expands `▸ stopped` | yes | yes (fold) |
| RET on a header opens its view; never folds | yes | — |
| `?` dispatch renders §6.2 layout | yes | — |
| `j m` jumps to the mail inbox | yes (after fix 0d531bf) | — |
| Lists: SPC detail side window, `q` closes it first | yes | — |

## Findings

1. **Fixed** — `j m` failed: `gascity-mail` is also the mail class's
   constructor (a function, not a command); jumps now require `commandp`.
2. **Fixed** — a stalled agent's drawer opened in Needs you *and* Agents
   (shared drawer id); Needs-you rows now have their own ids.
3. **Fixed** — a looping step and its iteration listed the same worker
   twice under a run.
4. **Open (P1, §8.3 R3/R5)** — over tramp-sh every concurrent async read
   opens its own `gascity-gc<N>` connection with a synchronous setup.  The
   cockpit's ~9 concurrent reads (7 + 1 per store + run graphs) contended
   with other agents' TRAMP sessions to localhost: one interactive open
   blocked in "Setup connection gascity-gc<2> … failed" until `C-g`; 1 of 3
   batch remote renders hit the 180 s timeout, one took 41 s with the convoy
   and escalation reads failing (`◐` on Needs you, `0 convoys`).  Needs the
   store's per-host cap and read deadlines; the cockpit's loaders are one
   named function each (`gascity-dashboard--read-*`) for that swap.

## Rendered cockpits

### emacs-city (local)
```
header-line: emacs-city  ○ live off  ↻ 0s ago ? help  j jump  g refresh
emacs-city  ~/emacs-city                                          supervisor ●
 agents 3/6 ●   sessions 3   runs 0   ready 39   mail ▲5   dolt 109 MB ●

Needs you  8
  ■ session  bd__dog  cold start timeout                      2m       ec-srpu
  ■ session  bd__dog  cold start timeout                      3m       ec-79pj
  ■ session  bd__dog  cold start timeout                      5m       ec-9t4b
  ■ session  bd__dog  cold start timeout                      6m       ec-hyax
  ■ session  bd__dog  cold start timeout                      8m       ec-usd0
  … 3 more                                                          j e events

Moving  none

Agents  1 running · 2 idle · 3 stopped                                 j a all
  ● bd.dog-1                           pi   ec-6leu   active  3s
  ○ mayor                              pi             idle    5h
  ○ gascity.el/core.control-dispatcher                idle    10h
  ▸ stopped  bd.dog-2 · core.control-dispatcher · beads.el/core.control-…

Work  39 ready · 0 in progress · 0 blocked · 6 convoys  (3 session · 1 order hidden)
  ga-uc7y   P1  City dashboard for gascity.el: vui.el, async-firs…  gascity.el
  be-bx5    P1  Sync beads.el with bd 1.3.x: command-class audit,…    beads.el
  ga-7pq7   P1  Dashboard v2: runs view from workflow beads, hone…  gascity.el
  be-ioj    P1  CI/CD: fix stale workflows (dead steveyegge/beads…    beads.el
  ga-ik26   P2  capability(gc): add a JSON surface for gc costs (…  gascity.el
  … 34 more                                                          j b beads

Activity  last 2h                                          (1487 churn folded)
  20:11   ×187 order.fired/completed        (15 orders)
  20:11   ×54  bead.updated                 (7 beads)
  20:11        bead.created                 ec-lpwt bd.dog-1
  20:10   ▲    bead.dead_assignee_reopened  ec-6leu
  20:10   ×54  wisp created/closed          (order, nudge)
  … 34 more                                                         j e events

Rigs  2
  beads.el     be   ~/workspace/beads.el       0/1 agents   0 in progress
  gascity.el   ga   ~/workspace/gascity.el     1/1 agents   0 in progress
```

### bright-lights (local)
```
header-line: bright-lights  ○ live off  ↻ 0s ago ? help  j jump  g refresh
bright-lights  ~/bright-lights                                    supervisor ●
 agents 3/5 ●   sessions 3   runs 0   ready 6   mail ▲4   dolt 73 MB ●

Needs you  1
  ▲ mail     4 unread                                                j m inbox

Moving  none

Agents  1 running · 2 idle · 2 stopped                                 j a all
  ● bd.dog-1                           pi   bl-syjk   active  2s
  ○ mayor                              pi             idle    3h
  ○ core.control-dispatcher                           idle    10h
  ▸ stopped  bd.dog-2 · hello-world/core.control-dispatcher

Work  6 ready · 0 in progress · 0 blocked · 7 convoys  (3 session · 1 order hidden)
  bl-bdj    P1  Formula v2 step targets (gc.run-operator) fail to…        city
  bl-pa2    P2  hello                                                     city
  bl-5ja    P2  e2e sling-v2: verify unified plain sling over TRA…        city
  bl-m0s    P2  hello                                                     city
  hw-aij    P2  Build a python hello world program                  hello-world
  … 1 more                                                           j b beads

Activity  last 2h                                          (1396 churn folded)
  20:15   ×8   order.fired/completed        (4 orders)
  20:15   ×1   wisp created/closed          (order)
  20:14   ×56  wisp created/closed          (order, message)
  20:14   ×168 order.fired/completed        (14 orders)
  20:08   ×21  bead.updated                 (1 beads)
  … 16 more                                                         j e events

Rigs  1
  hello-world  hw   ~/hello-world              0/1 agents   0 in progress
```

### bright-lights (`/ssh:localhost:/home/roman/bright-lights`)
```
header-line: bright-lights @localhost  ○ live off  ↻ 2s ago ? help  j jump  g refresh
bright-lights  ~/bright-lights                                    supervisor ●
 agents 3/5 ●   sessions 3   runs 0   ready 6   mail ▲4   dolt 73 MB ●

Needs you  1
  ▲ mail     4 unread                                                j m inbox

Moving  none

Agents  1 running · 2 idle · 2 stopped                                 j a all
  ● bd.dog-1                           pi   bl-syjk   active  4s
  ○ mayor                              pi             idle    3h
  ○ core.control-dispatcher                           idle    10h
  ▸ stopped  bd.dog-2 · hello-world/core.control-dispatcher

Work  6 ready · 0 in progress · 0 blocked · 7 convoys  (3 session · 1 order hidden)
  bl-bdj    P1  Formula v2 step targets (gc.run-operator) fail to…        city
  bl-pa2    P2  hello                                                     city
  bl-5ja    P2  e2e sling-v2: verify unified plain sling over TRA…        city
  bl-m0s    P2  hello                                                     city
  hw-aij    P2  Build a python hello world program                  hello-world
  … 1 more                                                           j b beads

Activity  last 2h                                          (1396 churn folded)
  20:15   ×8   order.fired/completed        (4 orders)
  20:15   ×1   wisp created/closed          (order)
  20:14   ×56  wisp created/closed          (order, message)
  20:14   ×168 order.fired/completed        (14 orders)
  20:08   ×21  bead.updated                 (1 beads)
  … 16 more                                                         j e events

Rigs  1
  hello-world  hw   ~/hello-world              0/1 agents   0 in progress
```
