# Dolt section city targeting — e2e QA report (ga-hvob)

Date: 2026-09-22. Runner: `gascity.el/gc.implementation-worker-2` (pi session
`ec-ewid`), bead ga-hvob.

## What was fixed

`gc dolt health|list` are Gas City pack commands: their cobra leaves parse
the argument tail blindly, so the advertised global `--city` flag is
rejected (`unknown flag: --city`) and the city is resolved from the
environment/cwd only. The rig dashboard's Dolt section (and
`gascity-dolt-list`) therefore hit the machine-global dolt server or failed
outright, rendering `(unavailable)`.

Fix (gascity.el only, per the bead's constraint): the reader carves the
dolt namespace out of `--city` argv targeting and pins the city by
*environment* instead — gc's first explicit context tier
(`resolveExplicitCityPathEnv` steps 4/5, above both the ambient env and the
cwd walk-up). `gascity-reader--city-env-overrides` answers
`GC_CITY`/`GC_CITY_PATH`/`GC_CITY_RUNTIME_DIR` from the view's pinned
`default-directory` (host-local values), prepends them to
`process-environment` around the spawn (local `make-process` copies the
binding; TRAMP's dispatch forwards the changed entry on the remote command
line as `env GC_CITY=…`), and the pack dispatch re-projects the canonical
pack env (port, state dir) for *that* city. The full anchor set is needed
because a spawned gc appends its projection — on this stack a duplicated
variable resolves to the FIRST entry, so ambient anchors (a
session-launched Emacs carries emacs-city's) would otherwise shadow it.

The full identity-anchor set, not a bare `GC_CITY`, is load-bearing: gc's
dolt health reads `GC_DOLT_PORT` from the pack state dir, which only the
canonical re-projection of `GC_CITY_RUNTIME_DIR` yields.

## Acceptance evidence (batch Emacs against real gc, ambient emacs-city
anchors + worker GC_DIR/GC_RIG present)

| Probe | `default-directory` | dolt server port | databases |
| --- | --- | --- | --- |
| local, repo rig | `~/workspace/gascity.el/` | 37081 (emacs-city) | be, ga, hq |
| local | `/home/roman/bright-lights/` | 41586 (bright-lights) | hq, hw |
| TRAMP | `/ssh:localhost:/home/roman/bright-lights/` | 41586 (bright-lights) | hq, hw |
| TRAMP async (the rig dashboard's call shape) | same | 41586 | hq, hw |
| local async | same | 41586 | hq, hw |

The rig-dashboard vnode path end to end (`gascity-rig--db-for-prefix` +
`gascity-rig--dolt-vnode` on the real payload): the `ga` rig renders
`Dolt ga: 1051 commits` (emacs-city), the `hello-world` (`hw`) rig renders
`Dolt hw: 137 commits` from bright-lights's own server, local and TRAMP.
Bright-lights's databases (`hq`, `hw`) — never emacs-city's (`be`, `ga`,
`hq`) — appear for every bright-lights pin.

Negative controls:

- Non-dolt reads keep `--city` argv targeting and touch no env vars
  (`gascity-test-env-city-other-subcommands-unchanged`).
- Reads outside any city are unchanged
  (`gascity-test-env-city-outside-city-unchanged`).
- `status`/`session list` with the worker's ambient `GC_RIG=gascity.el`
  against bright-lights still report bright-lights (step-2 precedence
  verified, unchanged by this fix).

## Live tmux-Emacs TRAMP pass

The standing `gce-e2e` tmux Emacs (started via `scripts/e2e-harness.sh`,
loaded from the working tree but with stale byte-compiled modules) was
evaluated live: after reloading `gascity-reader.el` from source, the real
async rig-dashboard read over
`/ssh:localhost:/home/roman/bright-lights/` resolved bright-lights's dolt
server (port 41586, `hq`/`hw`) — the previously `(unavailable)` Dolt
section's data path. A cached stale-`elc` Emacs shows the old failure
(`gc --city … dolt health` rejected), which is the pre-fix behavior this
bead closes; recompiled installs pick the new reader up.

## ERT

`scripts/gate.sh` passes: `eldev compile --warnings-as-errors` clean +
336/336 tests, including the new env-city suite
(`gascity-test-env-city-*`, 6 tests): override shape and anchor order,
host-local values over TRAMP, per-subcommand carving-out, outside-city
boundary, ambient-anchor shielding, async binding, and the
`gascity-command-execute` bang-function path.
