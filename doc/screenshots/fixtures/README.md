# Deterministic screenshot fixture

`fixture.sh` builds a throwaway Gas City workspace and rig at a fixed path
under `TMPDIR` (`${TMPDIR:-/tmp}/gascity-fixture`), seeds it with demo data
(`gascity-fixture.sh`), and removes it again. The path is
fixed, not `mktemp -d`, because gc derives the city name and the
header/mode-line text from the directory basename; a random suffix would show
up in a committed image and break byte-reproducibility. `--create` removes a
stale fixture at that path first. The screenshot pipeline captures against
this fixture, never against a live store. See `../README.md` for the pipeline
as a whole.

```
doc/screenshots/
├── fixture.sh                     lifecycle: --create / --seed / --teardown / --verify
├── fixtures/
│   ├── beads-fixture.jsonl        canonical demo issues, beads.el copy (unmodified)
│   ├── city.toml                  minimal city config (no live provider)
│   ├── gascity-fixture.sh         deterministic seed data: demo run graph, orders, events, mail
│   └── README.md                  this file
```

## The shared demo dataset

`beads-fixture.jsonl` is the canonical demo issue set, vendored byte for byte
from `beads.el/docs/manual/screenshots/fixtures/beads-fixture.jsonl`; beads.el
is unmodified and the copy is never hand-edited.

| Field | Value |
| --- | --- |
| file | `doc/screenshots/fixtures/beads-fixture.jsonl` |
| source | `beads.el/docs/manual/screenshots/fixtures/beads-fixture.jsonl` (unmodified) |
| sha256 | `6504c508bd25f3a2efc8a0e99bc940767b3306ae41352077fa446d2d6c319ca8` |
| ids | `demo-1` … `demo-12` (`demo-10` epic, `demo-11`/`demo-12` its children, `demo-4` blocked, `demo-3` in progress, `demo-6` closed) |

**This file is the only source of demo beads.**  Demo issue text is never
authored in `gascity-fixture.sh`: the seed script consumes the JSONL with
`bd import` and only adds the fixture state the canonical file does not carry
(the `demo-run` workflow graph, orders, events and mail).

`gascity-test-manual-fixture-digest` hashes the tracked file against the
`sha256` above, so a drift in either the copy or this README fails
`make check`.  CI has no sibling beads.el checkout, so the digest literal ---
not a live comparison --- is the cross-repo contract.

## Lifecycle

```sh
doc/screenshots/fixture.sh --create     # prints FIXTURE_CITY=<path>, FIXTURE_RIG=<path>
doc/screenshots/fixture.sh --seed       # seeds beads, mail, orders, pinned events
doc/screenshots/fixture.sh --teardown   # removes the temp tree, reports the path
doc/screenshots/fixture.sh --verify     # create + seed + assert + teardown
```

`--create` records the fixture path in `${TMPDIR:-/tmp}/gascity-fixture.current`
so `--seed` and `--teardown` need no argument. Pass `--city <dir>` (or set
`FIXTURE_STATE`) to address a fixture explicitly; set `FIXTURE_STATE` and pass
`--city` to run two fixtures side by side.

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

3. **Fixture `GC_HOME`.** `--create` writes `gc-home/cities.toml` naming only
   the fixture city. `capture.sh` exports `GC_HOME` to the capture Emacs, so
   `gc cities` (the Cities view) lists the fixture and never the machine's
   live cities. The same directory also namespaces the fixture's tmux server
   (`TMUX_TMPDIR`) for the terminal-attach shot, so the developer's tmux
   sessions are untouched.

Never seeded, never touched: the repository `.beads/`, `~/emacs-city`,
`~/bright-lights`, and any live agent workspace.

## What is seeded, by view

| View(s) | Fixture state | Mechanism |
| --- | --- | --- |
| `cockpit`, `health` | one city, one `demo-rig`, fixture orders, pinned events | `gc init` + `gc rig add` + seed |
| `rig-list`, `rig-dashboard` | `demo-rig` (prefix `demo`) with a git history | `gc rig add` |
| `order-list` | `demo-health` (cooldown) + `demo-nightly` (cron) | `orders/*.toml` |
| `events` | 6 events, seq 1-6, pinned epochs | `.gc/events.jsonl` |
| `costs` | 2 pinned compute facts (`demo-run-build`, `demo-run-review`) | `.gc/usage.jsonl` |
| `cities`, `remote-cities` | the fixture city only, under a fixture `GC_HOME` | `gc-home/cities.toml` |
| `mail-inbox` | a `demo-mail-thread` message bead | `bd import` |
| `convoy-list`, `dolt-list` | one bounded page from the seeded store | `bd import` |
| `bookmarks` | two gascity bookmarks set in-session | the shot list, not the fixture |
| `runs`, `run-detail` | one active `build-basic` run (`demo-run` root, 12 role-addressed graph beads; the review loop's iteration 1 is closed failed) | `bd import` |
| `session-list` | no live controller: the sessions table renders its honest empty state | `gc init --no-start` |
| `agents` | the config-derived agents, all `stopped` (no controller) | the city's agent config |

Demo issues are exactly the vendored `demo-1` … `demo-12` set described above,
with labels, statuses, `blocks` and `parent-child` dependencies, and comments.
No literal run-generated id is ever written.  The seeded run graph keeps its
role ids (`demo-run`, `demo-prep`/`demo-reqs`/... for the run's steps) and its
`gc.*` metadata, so `--verify` can still assert the ids are roles.

## Exclusions and risks (no silent fake)

The plan's "no silent fake" rule: anything the fixture cannot produce from
offline `gc`/`bd` commands is excluded with a reason rather than synthesized.

- **Sessions** need a running controller (`gc session list`). The fixture
  deliberately runs `gc init --no-start` with no live provider, so the store
  is empty and `session-list` renders its honest empty state. `agent-detail`
  needs a session and is therefore **not in the capture manifest** (see
  below). If a future view needs a live session, seed one from a
  deterministic `gc agent-script` run (see `examples/lifecycle`) and record
  the added controller cost here. The cockpit and Agents still render their
  config-derived sections and show their degraded (`controller down`,
  `stopped`) state — a real state, not a fake.
- **Runs and run-detail** need no controller: the fixture seeds one
  `build-basic` workflow graph with `bd import` (above), so both views render
  real store data. The run is `in_progress`, which keeps it in the Runs
  view's Active section (the Failed section only looks back 24h, and every
  fixture timestamp is pinned to 2025-01-01), and its review loop's failed
  iteration gives the run detail a failed stage and an inspector failure.
  With no session, the inspector honestly reads `no session`.
- **Events over the API.** Every `gc` call in the capture inherits the
  fixture `GC_HOME`, and `gc events` then resolves through the supervisor API,
  which does not exist for this city: it fails with
  `could not auto-discover the supervisor API`. The cockpit's Activity
  section and the run detail's inspector show that honest
  `events unavailable` state rather than a fabricated empty log; the local
  `.gc/events.jsonl` still feeds the Events view, which does not need the
  API.
- **Mail** is seeded as a message bead, but `gc mail inbox` resolves the
  *current agent's* session, which does not exist without a controller, so the
  live `mail-thread` view is not in the capture manifest. The bead stays as
  fixture data for a future session-backed capture.
- **Dropped views (`agent-detail`, `mail-thread`).** These two need a live
  session (above) and cannot be produced from the offline fixture, so they
  remain out of the capture manifest and the manual rather than shipping
  their pre-workflow live-store captures. Regenerate and re-add them here
  once a deterministic controller seed exists. `run-detail` is captured: the
  seeded run graph gives it real, deterministic data.
- **Bookmarks** are Emacs-side (`gascity-bookmark.el`), not a `gc` store, so
  the fixture cannot write them; the shot list sets two real gascity
  bookmarks in-session (`bookmark-default-file` pointed at a throwaway path)
  before opening `bookmark-bmenu-list`. The developer's own bookmark file is
  never read or written.
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
