# Fixture pack-import cache warm-up (ga-dkxzm)

Bead: `ga-dkxzm` (follow-up to the P7 black-box QA, `ga-dsqrf`).
Date: 2026-11-11. Scope: fixture only (`doc/screenshots/fixture.sh`,
`doc/gascity.texi`, `doc/screenshots/README.md`); no runtime change.

## Defect

A freshly recreated fixture (`fixture.sh --teardown; --create; --seed`)
left the fixture `GC_HOME`'s pack-import cache cold.  The first cockpit
paint then showed `store health: runtime status probe incomplete` in
Needs you and every agent as `unknown` until the reader ran
`gc import install` (the manual's documented first-run step) and/or
refreshed.

## Reproduction

With a scratch `TMPDIR` (so the shared `/tmp` fixture was untouched):

```sh
export TMPDIR=$(mktemp -d)
doc/screenshots/fixture.sh --create
find "$TMPDIR/gascity-fixture/gc-home/cache"   # empty: no cache
```

`gc import status --json` against the fixture city listed the two
bundled imports (`pack:bd`, `pack:core`) but the cache directory did not
exist.  Running `gc import install` with the fixture `GC_HOME` created
it in 0.12 s, proving the install is offline: the gc binary ships the
bundled pack cache, and the fixture's only imports are those bundled
packs.

## Fix

`fixture.sh --create` now calls `install_fixture_imports` after
`seed_gc_home`:

```sh
GC_HOME="$home" gc --city "$city" import install 1>&2
```

The install runs with the fixture `GC_HOME`, so the cache lands under
the fixture and never the caller's `~/.gc`.  Its output goes to stderr,
keeping `--create`'s `FIXTURE_*` stdout contract machine-readable.
`--verify` now asserts the cache exists and holds at least one repo, so
a regression fails the live fixture check.

The manual's demo recipe no longer asks the reader to run
`gc import install`; it states that `--create` warms the cache and that
the install needs no network.  The warm-up-row note stays (the status
probe can still be slow on first paint), but the cold-cache cause is
gone.

## Evidence

| Check | Result |
| --- | --- |
| `fixture.sh --create` (scratch `TMPDIR`) | `Installed 2 remote import(s) into …/gc-home/cache/repos` |
| `gc import status --json` after create | `ok: true`, 2 imports (`pack:bd`, `pack:core`) |
| `fixture.sh --verify` (scratch `TMPDIR`) | `fixture.sh: PASS` (84 beads, 2 sessions, dataset digest OK) |
| `scripts/gate.sh` | PASS (compile clean, 1100/1100 ERT) |
| `scripts/lint.sh` | exit 0 (no checkdoc/package-lint findings) |
| `make -C doc` | up to date, warning-free |

The new ERT test `gascity-test-manual-fixture-warms-pack-cache` pins the
fixture call and the manual text.
