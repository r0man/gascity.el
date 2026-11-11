# Rig dashboard says `unknown` where the cockpit says `stopped` (ga-0onhi)

Bead: `ga-0onhi` (filed from the P7 black-box pass, `ga-dsqrf`; see
`docs/qa/2026-11-08-manual-demo-consistency.md`). Date: 2026-11-11.
Scope: runtime (`lisp/`), no gc/beads.el change.

## Symptom

Against the demo fixture (`/tmp/gascity-fixture`, rig `/tmp/demo-project`,
controller down) the same idle agent read:

- cockpit/Agents table: `○ stopped` (`agents 0/4`, `Agents 4 stopped`);
- rig dashboard (`j g`): `Agents 1 unknown`,
  `demo-rig/core.control-dispatcher  unknown`.

`gc status --city /tmp/gascity-fixture --json` reported the agents
`running: false` and *no* `partial` field, and committed screenshots of
both views showed `stopped`.

## Root cause

All three surfaces already classify agents through one rule,
`gascity-status--agent-state` (`gascity-status.el`), and the rig dashboard
joins the same `gc status` rows as the cockpit (ec-elkm5.9/.10).  With one
payload they always agree; that was verified live (below).  The only input
that turns a settled `stopped` into `unknown` is the payload's `partial`
flag: `gc` sets it when a liveness probe times out, and every agent the
probe never reached then reads `unknown` (by design, ec-elkm5.9).

So the two views were rendering **different payloads of the same store
entry**: the store publishes every successful read, so one flaky status
probe (Emacs-side `gc status` invocations probe separately, and the
fixture's supervisor is down) replaced a fully observed roster with a
partial one.  A view that refreshed after that read showed `unknown`; a
view that had rendered the settled payload a moment earlier still showed
`stopped`.  That is the QA pair, and it is timing-dependent rather than a
join bug: no agent row was ever lost.

## Fix

A degraded answer no longer replaces a complete one in the payload store
(`gascity-store.el`):

- `gascity-store-payload-degraded-p` is a new generic; the `status` method
  (`gascity-status.el`) reports a `gc status` payload as degraded when
  `partial` (or `partial_errors`) is set.
- `gascity-store--complete-read` keeps the last non-degraded payload for
  at most `gascity-store-degraded-grace` (default 30 s) and answers
  callers and subscribers with it.  The normal TTL still refreshes, so a
  complete probe lands immediately.  After the grace window the degraded
  payload is accepted, so a probe that never answers again is shown as
  `unknown` instead of freezing the views on a stale roster.
- A cold store has no better payload, so a partial first answer is taken
  exactly as before (the documented `unknown` first paint).

Only `status` declares the rule; every other kind is unchanged.  The
old behavior (`grace 0`) is kept reachable through the option.

## Tests (ERT)

`lisp/test/gascity-store-test.el`:

- `gascity-test-store-partial-status-keeps-last-good-roster` — the store,
  the caller and the subscriber keep the good roster on a partial
  refresh; other kinds are untouched; a cold store takes the partial one.
- `gascity-test-store-partial-status-accepted-after-grace` — the partial
  payload is adopted once `gascity-store-degraded-grace` has elapsed.

Both failed before the change and pass after it.  The existing shared-
classifier tests (unknown renders/counts/agrees across surfaces) still
pass, so the `partial` → `unknown` rule itself is unchanged.

## Live acceptance (non-graphical Emacs daemon, real fixture)

Server `gc-0onhi`, `GC_HOME=/tmp/gascity-fixture/gc-home`, default
directory `/tmp/gascity-fixture`, demo fixture created/seeded with
`doc/screenshots/fixture.sh` and `gc import install` run; `demo-agent`
and `demo-reviewer` started on the city tmux socket.

1. `gascity-dashboard`, then `gascity-rig-dashboard "demo-rig"`; after the
   reads settled:
   - cockpit: ` agents 0/4 ▲   sessions 0   runs 3 ⬣   ready 9`,
     `Agents  4 stopped`;
   - rig dashboard: `Agents  1 stopped |   ○ demo-rig/core.control-dispatcher         stopped`.
2. Injected the QA condition: settled the store's `status` entry with the
   same payload plus `partial: true` and
   `partial_errors: ["runtime status probe incomplete"]` through
   `gascity-store--complete-read`.  Result: `:held t` (the store kept the
   complete payload), and both views still read `stopped` after they
   repainted.
3. Positive control (`gascity-store-degraded-grace` = 0, i.e. the old
   behavior): the same injection was accepted (`:now-partial t`) and both
   views repainted to `unknown` (`Agents 4 unknown` /
   `Agents 1 unknown | ▲ demo-rig/core.control-dispatcher unknown`).
   This reproduces the QA divergence mechanism and shows the option is
   what prevents it.

## Gates

- `scripts/gate.sh`: PASS (byte-compile clean, `1095/1095` ERT results as
  expected, 0 unexpected).
- `scripts/lint.sh`: PASS (exit 0, no checkdoc/package-lint warnings).
- `make -C doc`: warning-free (the new option and the behavior are
  documented in “The store and scheduling” and the cockpit's Agents
  item).
- `make regen-doc-tables` rerun for `doc/generated/options.texi`.

## Notes

- The historical P7 report (`docs/qa/2026-11-08-manual-demo-consistency.md`)
  keeps its `unknown` captures; it recorded the passes at the time and
  this report records the fix.
- No manual text claimed the two views disagree, so no manual correction
  was owed; the tour's `stopped` states are now the stable reading.
