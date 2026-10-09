# Deterministic screenshot fixture

`fixture.sh` builds a throwaway Gas City workspace and rig under
`mktemp -d`, seeds it with role-addressed data (`gascity-fixture.sh`), and
removes it again. The screenshot pipeline captures against this fixture, never
against a live store. See `../README.md` for the pipeline as a whole.

```
doc/screenshots/
├── fixture.sh                     lifecycle: --create / --seed / --teardown / --verify
├── fixtures/
│   ├── city.toml                  minimal city config (no live provider)
│   ├── gascity-fixture.sh         deterministic role-addressed seed data
│   └── README.md                  this file
```

## Lifecycle

```sh
doc/screenshots/fixture.sh --create     # prints FIXTURE_CITY=<path>, FIXTURE_RIG=<path>
doc/screenshots/fixture.sh --seed       # seeds beads, mail, orders, pinned events
doc/screenshots/fixture.sh --teardown   # removes the temp tree, reports the path
doc/screenshots/fixture.sh --verify     # create + seed + assert + teardown
```

`--create` records the fixture path in `${TMPDIR:-/tmp}/gascity-fixture.current`
so `--seed` and `--teardown` need no argument. Pass `--city <dir>` (or set
`FIXTURE_STATE`) to address a fixture explicitly or run two side by side.

A capture run consumes the fixture by pointing the engine at it:

```sh
FIXTURE_CITY=...                     # from --create
GASCITY_SHOT_DIR="$FIXTURE_CITY" \
  doc/screenshots/capture.sh --scope cockpit
```

## Isolation

Two independent layers keep the fixture away from any real store:

1. **Environment.** The four variables that can reroute `bd`/`gc` at a shared
   production store are hardcoded in `fixture.sh` and `gascity-fixture.sh` and
   unset before every `bd`/`gc` call: `BEADS_DIR`, `BEADS_DOLT_PORT`,
   `BEADS_DOLT_SERVER_PORT`, `GC_DOLT_PORT`. They mirror beads.el's
   `beads-test-isolation-env-vars`
   (`lisp/test/beads-integration-test.el`); the WI-6 `:unit` test asserts the
   two lists are equal by reading `fixture.sh print-isolation-vars`.
2. **Explicit `--city`.** Every `gc` call passes `--city "$CITY"`, so a leaked
   `GC_CITY`/`GC_CITY_PATH` from a Gas Town agent shell cannot redirect it at
   `~/emacs-city`.

`--teardown` additionally refuses to delete anything that is not under
`TMPDIR` with the `gascity-fixture.` prefix and the `.gascity-fixture-city`
marker, so a stray argument cannot `rm -rf` a real checkout. `--verify`
asserts the repository's own `.beads` mtime is unchanged across the run.

Never seeded, never touched: the repository `.beads/`, `~/emacs-city`,
`~/bright-lights`, and any live agent workspace.

## What is seeded, by view

| View(s) | Fixture state | Mechanism |
| --- | --- | --- |
| `cockpit`, `health` | one city, one `demo-rig`, fixture orders, pinned events | `gc init` + `gc rig add` + seed |
| `rig-list`, `rig-dashboard` | `demo-rig` (prefix `demo`) with a git history | `gc rig add` |
| `order-list` | `demo-health` (cooldown) + `demo-nightly` (cron) | `orders/*.toml` |
| `events` | 6 events, seq 1-6, pinned epochs | `.gc/events.jsonl` |
| `session-list`, `agents`, `agent-detail`, `runs`, `run-detail`, `costs` | *excluded* — see below | — |
| `mail-inbox`, `mail-thread` | a `demo-mail-thread` message bead | `bd import` |
| `cities` | the fixture city only | `gc init` |
| `convoy-list`, `dolt-list` | one bounded page from the seeded store | `bd import` |

Beads are role-addressed: every id is `demo-<role>` (`demo-epic-manual`,
`demo-task-fixture`, `demo-bug-render`, `demo-mail-thread`, ...), with labels,
statuses, `blocks` and `parent-child` dependencies, and comments. No literal
run-generated id is ever written, so `--verify` can assert the ids are roles.

## Exclusions and risks (no silent fake)

The plan's "no silent fake" rule: anything the fixture cannot produce from
offline `gc`/`bd` commands is excluded with a reason rather than synthesized.

- **Sessions, agents, runs, costs** need a running controller (`gc session
  list`, `gc costs`). The fixture deliberately runs `gc init --no-start` with
  no live provider, so these stores are empty. Excluded; if a future view
  needs them, seed them from a deterministic `gc agent-script` run (see
  `examples/lifecycle`) and record the added controller cost here.
- **Mail** is seeded as a message bead, but `gc mail inbox` resolves the
  *current agent's* session, which does not exist without a controller, so the
  live mail view is excluded too. The bead stays as fixture data for a future
  session-backed capture.
- **Bookmarks** are Emacs-side (`gascity-bookmark.el`), not a `gc` store, so
  they cannot be seeded from this fixture; excluded.
- **Runtime-only cockpit signals** (`controller.running`, live agent counts)
  read `false`/empty offline. The cockpit still renders its config-derived
  sections; the capture records that degraded state rather than faking a
  running controller.
- **Relative timestamps.** Events pin absolute epochs, but a view that renders
  "3 months ago" drifts with wall-clock time; the WI-2 normalization hook owns
  mapping those back to role/relative tokens before export (plan D4).
- **`gc init`/`gc rig add` generated data.** City/rig registration writes
  run-dependent values (paths, possibly ids). They are not part of any
  committed image directly; the WI-2 normalization hook is the backstop, and
  `--verify` covers reproducibility at the image level.
