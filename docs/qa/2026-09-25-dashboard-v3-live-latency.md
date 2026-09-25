# dashboard-v3 live latency — churn and session events

Date: 2026-09-25 · branch `v3-integrate` · bright-lights, local and
`/ssh:localhost:/home/roman/bright-lights` (ssh transport). Batch Emacs
under `timeout`; host load average 10–29 (other agents' work).

## 1. Mail under an order/bead burst (`scripts/qa/dashboard-v3-live-latency.el`)

5 mails from a shell outside Emacs, 8–10 s apart; with `GCE_BURST=1`
12 synthetic `order.fired`/`bead.created`/`bead.closed` events are
handed to the stream in the same debounce window.  Time from gc
committing the mail to the inbox view / the cockpit's count showing it,
no `g`.

| run | inbox p50 / max | count p50 / max |
|---|---|---|
| local, no burst (before) | 3.4 / 3.6 s | 3.5 / 3.7 s |
| local, burst (before) | 3.7 / 4.2 s | 3.7 / 4.3 s |
| remote, burst (before) | 4.9 / 6.0 s | 4.9 / 5.9 s |
| remote, burst (after) | 3.8 / 4.0 s | 4.0 / 4.2 s |
| local, burst (after) | 3.4 / 3.6 s | 3.5 / 3.7 s |
| local, no burst (after) | 3.7 / 3.8 s | 3.7 / 3.9 s |

The debounce is a fixed window (first event arms 2.5 s, later ones join).
The cost was what a churny batch re-read: per-type invalidation re-ran
entries, and the heavy bd/events reads were requested before the mail
reads, so on the capped remote host mail queued behind them.  Fixed by
one invalidation per batch, background kinds yielding in the queue, and
background re-reads waiting for the light reads of their batch.  One
local run at load 29 measured p50 7.4 s; the same code at load ~20
measured 3.4 s (gc read time under host load, not Emacs).

## 2. Session suspend / wake of pool agent bd.dog-1 (`scripts/qa/dashboard-v3-live-session.el`)

Actions started from Emacs (async); Agents table (all states) and the
cockpit's Agents section, no `g`.

| | local | remote |
|---|---|---|
| suspend → Agents / cockpit | 1.9–2.6 s / 1.9–2.6 s | 2.2–2.9 s / 2.2–2.9 s |
| wake → Agents | 1.5–1.7 s | 1.3–1.6 s |
| wake → cockpit (next visible change) | 1.5–4.2 s | 9.4 s |
| agent active again in the cockpit | 19 s | 35 s |

gc 1.4.2 emits no `session.*` event for the `gc session suspend` /
`wake` calls themselves (documented gc gap, D6); the reconciler's own
transitions do arrive later as `session.woke` / `session.stopped`, but
seconds to minutes after the call.  Views follow because a completed
action invalidates what it touched even while the stream is live, and
re-invalidates it 5/15/45/90/180 s later
(`gascity-store-action-followups`) for the transitions the reconciler
finishes afterwards.  A suspend done OUTSIDE Emacs stays invisible
until the next event touching sessions or a `g`.

Restored: bd.dog-1 active after each run (`gc session list`); it then
finished its patrol and gc stopped it (`session.stopped`, 22:03:55) —
the pool member's normal idle state (pool min 0), as before the runs
began its patrol.
