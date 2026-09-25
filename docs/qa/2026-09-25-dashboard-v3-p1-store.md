# dashboard-v3 P1 — store, scheduler, async actions: live pass

Date: 2026-09-25 · Branch `v3-store` · gc 1.4.2 · Emacs 31.1 (batch)
City: `bright-lights`, local (`~/bright-lights`) and TRAMP
(`/ssh:localhost:/home/roman/bright-lights`).

Driver: `scripts/qa/dashboard-v3-p1-live.el`, run as batch Emacs under
`timeout 300` with the worktree's `lisp/`, beads.el and vui on the load
path (`GCE_DIR=<city dir> emacs --batch -L … -l scripts/qa/dashboard-v3-p1-live.el`).
A 50 ms repeating timer records every main-loop gap > 250 ms and the
number of live `gascity-gc` processes; on the host a 20 ms sampler
counted `gc` processes carrying `--city /home/roman/bright-lights`
(3 long-lived ones exist at baseline).

Phases: open the city dashboard → wait idle; open status + session list +
rig list + mail inbox at once (contention); kill and reopen the dashboard
(warm store); actions: `mail mark-read` then `mark-unread` on
`bl-wisp-lu30rp` (restored: unread again, verified with
`gc mail inbox --json`), `session suspend no-such-session-xyz` (failure).

## Results

| Measure | Local | Remote (ssh transport) | Remote (tramp-sh, before fix) |
|---|---|---|---|
| `gascity-dashboard` returns | 4 ms | 0.96 s first contact (city.toml walk 0.88 s — §8.5 exception), 6 ms warm | 0.8 s |
| status+sessions+rigs+mail open | 23 ms | 30 ms | 17.6 s |
| main-loop stalls > 250 ms | none | only the first-contact one above | 0.8–21 s, 8 during the dashboard load |
| max concurrent remote gc (Emacs) | — (local uncapped: 19) | **3** reads (+1 action lane) | 3 |
| max concurrent gc on host | — | baseline 3 + **3** | — |
| warm reopen spawns | — | 2 (entries past TTL) | 3 |
| action verb returns | 1 ms | 2–3 ms | 0.44–0.5 s |
| success echo | `Marked read bl-wisp-lu30rp` | same | same |
| failure echo | `gc session suspend no-such-session-xyz failed: gc session suspend: session not found: "no-such-session-xyz"` | same | same |
| log | `*gascity-log: bright-lights*` with exit + full stderr | `*gascity-log: bright-lights@localhost*` | same |

## Finding: tramp-sh `make-process` blocks the main loop

Profiling the remote dashboard (advice timing every call > 100 ms) showed
each tramp-sh async `make-process` taking ~0.5 s synchronously (remote
shell setup over the pooled connection), one 10.6 s under contention.
The scheduler cap bounds the number of processes but not this setup
cost, so on tramp-sh no view could meet the 200 ms stall budget. Fix
(commit "feat(reader): run remote async gc over a local ssh pipe"): for
single-hop ssh-family cities async reads and actions are local
`ssh -T -o BatchMode=yes` pipe processes with a shared ControlMaster
(`gascity-remote-transport`, default `ssh`; `tramp` restores the old
path). Remote dashboard content matched the local one (status, agents,
sessions, work, runs, convoys, activity, rigs).

## Not covered here

- TRAMP direct-async mode: with the ssh transport it is bypassed for
  ssh-family methods (the transport is the same idea); non-ssh methods
  still use TRAMP's `make-process` and were exercised only through the
  ERT `/mock::` tests.
- `○ offline` header / reconnect on a dropped connection: the store side
  (offline state, paused queues, backoff probe) is covered by ERT
  (`gascity-test-store-offline-pauses-and-recovers`); the header
  rendering is P2/P3.
- First-contact sync work (city.toml discovery, gc resolution) is still
  synchronous but bounded by `gascity-remote-with-timeout` and cached.

## Re-run after rebasing onto the v3 cockpit (main 1dd13e4)

Remote, ssh transport: cockpit returns in 1.0 s (first contact) / 0.14 s
warm fresh mount; the four other views open in 28 ms; max 3 concurrent
remote reads in Emacs (4 with one action on its own lane); host peak
7 `gc --city bright-lights` processes against a baseline of 2–3
(3 reads + 1 action + the city's own). Stalls: the first-contact one
(1.0 s) and one 262 ms render on the warm reopen. Actions unchanged
(1–7 ms to return); `bl-wisp-lu30rp` left unread as found.
