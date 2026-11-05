# Run inspector: session liveness vs. claim lease (ga-v8hah)

Date: 2026-11-05

## Problem

The run inspector's worker line showed the bead's lease and heartbeat as if
they described the worker's session:

```
worker   bu-wisp-nfmhu4  ● mockup-builder-1  lease expired 4m ago  heartbeat 9m ago
```

A live Pi worker on `bs-1h871x` (`bs-mockup-unit`) read as a dead assignee.
The lease is bead claim metadata; Pi workers do not currently run
`gc bd heartbeat` (ga-p2lfj), so every in-progress bead's lease lapses about
five minutes after the claim even while its session works.

## Change

`gascity-run--worker-line` now names the two facts separately:

- session liveness from the `session list` row:
  `session live · active 20s ago`
- claim state from the bead:
  `claim lease 3m left · heartbeat 30s ago`

Three cases are distinguished:

| session | lease | line |
| --- | --- | --- |
| live, active after the deadline | lapsed | `session live · active 20s ago  claim lease lapsed 4m ago · heartbeat 9m ago (Pi heartbeat gap)` |
| live, quiet past the deadline | lapsed | `session live · active 15m ago  claim lease lapsed 4m ago … (stale claim)` |
| no live session | lapsed | `○ name  assignee/session gone  claim lease lapsed 5m ago · heartbeat 9m ago` |

The live-and-quiet case uses the same `gascity-dashboard--session-active-after-p`
guard as the cockpit's Needs-you stale-work rule (ga-o7vtw), so the two views
cannot contradict each other.  The session join and agent action object come
from the shared `gascity-runs--worker-facts` (also used by the Runs card); the
render adds no gc read and never touches the heartbeat implementation itself.

## Tests

`make check` (932 tests, all pass) adds:

- `gascity-test-run-inspector-live-session-lapsed-lease` — the live + lapsed
  case reads as a heartbeat gap, never "gone".
- `gascity-test-run-inspector-live-session-stale-claim` — live but quiet past
  the deadline reads `(stale claim)`, matching the cockpit rule.
- `gascity-test-run-inspector-dead-session-lapsed-lease` — no live session
  reads `assignee/session gone` with the lease age.
- `gascity-test-run-inspector-normal` — the live + fresh lease case now
  includes the session's last-active fact.
- `gascity-test-run-inspector-remote-artifacts` — the same labeling over
  TRAMP, with the existing no-stat guard; the cold-store test continues to
  render `worker   no session` without signaling.

## Live read-only acceptance (emacs-city, 2026-11-05)

There was no active workflow run in emacs-city or beads.el at acceptance time
(all 295 runs were closed), so the live worker line was read from the four
in-progress Pi claims in those rigs.  This is the exact
`gascity-run--worker-line` the run drawer calls, using the live
`session list` and `bd list` payloads; the run-step path is covered by the ERT
above.  Every claim's lease had lapsed while its session was active:

```
LIVE CLAIM beads.el be-uvqor
  assignee=ec-wisp-m3rb22 lease=2026-11-05T11:46:54Z heartbeat=2026-11-05T11:41:54Z
  worker   ec-wisp-m3rb22  ● implementation-worker-3  session live · active 0s ago  claim lease lapsed 1m ago · heartbeat 6m ago (Pi heartbeat gap)

LIVE CLAIM beads.el be-9pquh
  assignee=ec-wisp-iltqrj lease=2026-11-05T11:46:40Z heartbeat=2026-11-05T11:41:40Z
  worker   ec-wisp-iltqrj  ● implementation-worker-1  session live · active 0s ago  claim lease lapsed 1m ago · heartbeat 6m ago (Pi heartbeat gap)

LIVE CLAIM beads.el be-30wgt
  assignee=ec-wisp-3w0yx7 lease=2026-11-05T11:46:54Z heartbeat=2026-11-05T11:41:54Z
  worker   ec-wisp-3w0yx7  ● implementation-worker-2  session live · active 0s ago  claim lease lapsed 1m ago · heartbeat 6m ago (Pi heartbeat gap)

LIVE CLAIM gascity.el ga-v8hah
  assignee=ec-wisp-01xgqo lease=2026-11-05T11:46:39Z heartbeat=2026-11-05T11:41:39Z
  worker   ec-wisp-01xgqo  ● implementation-worker-1  session live · active 0s ago  claim lease lapsed 1m ago · heartbeat 6m ago (Pi heartbeat gap)
```

Before the change the same data rendered as `● name  lease expired 1m ago
heartbeat 6m ago`, with no session fact.  A live session with a fresh lease
and a dead session with no lease are covered by the ERT cases, because neither
occurred in the live payloads at acceptance time.

## Gates

- `scripts/gate.sh` — compile clean (warnings as errors) + 932/932 ERT.
- `scripts/lint.sh` — clean.
- `make -C doc` — manual builds with the updated worker item.

## Follow-up

The root cause (Pi worker sessions do not renew their claim lease) is
ga-p2lfj and is deliberately not implemented here; this change only stops the
UI from presenting the gap as a dead assignee.  The cockpit guard is
ga-o7vtw.
