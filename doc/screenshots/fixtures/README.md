# Deterministic screenshot fixture

`fixture.sh` builds a throwaway Gas City city and the shared demo project, seeds
them with data (`gascity-fixture.sh`), and removes them again.  Both paths are
fixed under `TMPDIR`:

| Artifact | Path | Marker |
| --- | --- | --- |
| city | `${TMPDIR:-/tmp}/gascity-fixture` | `.gascity-fixture-city` |
| project | `${TMPDIR:-/tmp}/demo-project` | `.gascity-fixture-project` |

The project path is the one the beads.el manual shares, so both manuals
describe one demo project with one stable basename.  The paths are fixed, not
`mktemp -d`, because gc derives the city name and the header/mode-line text
from the directory basename; a random suffix would show up in a committed image
and break byte-reproducibility.  `--create` removes a stale fixture at either
path first, but only when the path carries the matching marker: a directory
without it is never adopted or deleted (the beads.el fixture owns the same
`demo-project` path with its own marker).  The screenshot pipeline captures
against this fixture, never against a live store.  See `../README.md` for the
pipeline as a whole.

```
doc/screenshots/
├── fixture.sh                     lifecycle: --create / --seed / --teardown / --verify
├── fixtures/
│   ├── beads-fixture.jsonl        canonical demo issues, beads.el copy (unmodified)
│   ├── city.toml                  minimal city config (no live provider)
│   ├── gascity-fixture.sh         deterministic seed data: sessions, mail, run graph, orders, events
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

**This file is the only source of demo issue text.**  `gascity-fixture.sh`
consumes it with `bd import` and only adds the fixture state the canonical file
does not carry (sessions, mail, the `demo-run` workflow graph, orders, events,
usage).  The dataset's pinned timestamps span `2025-01-01T09:00:00Z` …
`2025-01-06T16:00:00Z` (it is not all one day); every role object the seed adds
is pinned to a documented 2025 timestamp too, so no wall clock ever reaches the
store.

`gascity-test-manual-fixture-digest` hashes the tracked file against the
`sha256` above, so a drift in either the copy or this README fails
`make check`.  CI has no sibling beads.el checkout, so the digest literal ---
not a live comparison --- is the cross-repo contract.

Role ids added on top of the dataset (everything else in the store is
canonical):

| Id | Kind | Purpose |
| --- | --- | --- |
| `demo-session-dev` | session bead | one session row, work bead `demo-3`, agent `demo-rig/gc.implementation-worker` |
| `demo-session-review` | session bead | one session row, work bead `demo-4`, agent `demo-rig/gc.reviewer` |
| `demo-mail-review` | message bead | mail naming `demo-10` and `demo-11` |
| `demo-run` | run root | `build-basic on demo-10`, built on `demo-10`/`demo-11` |
| `demo-prep`, `demo-reqs`, `demo-plan`, `demo-plrv`, `demo-dcmp`, `demo-impl`, `demo-isms`, `demo-sumi`, `demo-revw`, `demo-rev1`, `demo-finz`, `demo-publ` | run graph | the run's steps; `demo-rev1` is the failed review iteration |

The pre-P2 role-addressed issue set is gone: `demo-epic-manual`,
`demo-task-manual`, `demo-task-fixture`, `demo-task-capture`, `demo-bug-render`,
`demo-chore-cleanup` and `demo-mail-thread` no longer exist.  Their roles are
carried by the canonical `demo-1` … `demo-12` issues (and `demo-mail-review`
for the mail role).

## Lifecycle

```sh
doc/screenshots/fixture.sh --create     # prints FIXTURE_CITY=, FIXTURE_PROJECT=, FIXTURE_RIG=, ...
doc/screenshots/fixture.sh --seed       # seeds demo beads, sessions, mail, run, orders, events
doc/screenshots/fixture.sh --teardown   # removes the city and the project, reports both
doc/screenshots/fixture.sh --verify     # create + seed + assert + teardown
doc/screenshots/fixture.sh --self-test  # offline teardown-guard check, no city
```

`--create` prints `FIXTURE_CITY`, `FIXTURE_PROJECT`, `FIXTURE_RIG`,
`FIXTURE_RIG_NAME` and `FIXTURE_GC_HOME`.  `FIXTURE_RIG` is an alias of
`FIXTURE_PROJECT`: the rig's source checkout *is* the shared project, outside
the city tree.  The command records the city path in
`${TMPDIR:-/tmp}/gascity-fixture.current` so `--seed` and `--teardown` need no
argument.  Pass `--city <dir>` (or set `FIXTURE_STATE`) to address a fixture
explicitly.  `FIXTURE_STATE` isolates only the city/state file: the demo
project is one fixed `$TMPDIR/demo-project` checkout, so give each parallel
fixture its own `TMPDIR` or let runs serialize on the lock.  Mutating commands
(`--create`, `--seed`, `--teardown`, `--verify`) hold an advisory `flock` on
`${TMPDIR:-/tmp}/demo-project.lock` for their duration and wait at most
`FIXTURE_LOCK_TIMEOUT` seconds (default 600) before failing with a message
naming the lock; the lock is shared with beads.el's pipeline, which uses the
same project path.  `capture.sh` holds the lock for a whole capture run and
exports `FIXTURE_LOCK_HELD=1`, so its nested fixture calls skip acquisition
instead of deadlocking (see `../README.md`).  A capture run that created the
fixture tears it down on exit (`teardown_project`); to remove one by hand use
`doc/screenshots/fixture.sh --teardown --city DIR`.  `--self-test` runs the
teardown marker guard, repeated-teardown idempotence, and the lock
serialization checks in a scratch `TMPDIR`, without creating a city, so
`make check` can assert the guard without `gc`.  `--verify` and
`--self-test` are unaffected in their data and image output: the lock only
orders whole runs.

The project is one pinned README commit (`2025-01-01T00:00:00Z`, one file).
`gc rig add` runs `bd init`, which initializes the rig's `.beads` store in the
checkout and commits it; `--create` drops that wall-clock commit with a mixed
reset, so the project history stays the single synthetic README commit and the
store stays in the working tree, untracked and gitignored.  The store is
created by gc (the fixture never authors it), and nothing commits it.

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
`TMPDIR` with the expected path prefix and marker: the city needs
`.gascity-fixture-city`, the project needs `.gascity-fixture-project`.
`--verify` exercises that refusal as a negative test (it removes the project
marker, runs teardown in a subshell, and asserts the city and the project both
survive) and asserts the repository's own `.beads` mtime is unchanged across
the run.

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
| `rig-list`, `rig-dashboard` | `demo-rig` (prefix `demo`) at the shared `demo-project` checkout | `gc rig add` |
| `order-list` | `demo-health` (cooldown) + `demo-nightly` (cron) | `orders/*.toml` |
| `events` | 6 events, seq 1-6, pinned epochs | `.gc/events.jsonl` |
| `costs` | 2 pinned compute facts (`demo-run-build`, `demo-run-review`) | `.gc/usage.jsonl` |
| `cities`, `remote-cities` | the fixture city only, under a fixture `GC_HOME` | `gc-home/cities.toml` |
| `mail-inbox` | a `demo-mail-review` message bead naming `demo-10`/`demo-11` | `bd import` |
| `convoy-list`, `dolt-list` | one bounded page from the seeded store | `bd import` |
| `bookmarks` | two gascity bookmarks set in-session | the shot list, not the fixture |
| `runs`, `run-detail` | a source-bearing rich `build-basic on demo-10` run (`demo-run`) with eight deliverables (`demo-biz-1..8`) and their member runs (`demo-member-1..8`; the last is on `close-source-anchor`), a flat `do-work` run (`demo-flat`), a standalone `review` run (`demo-std`) and an inline drain (`demo-inline`); the rich run's review loop's iteration 1 is closed failed, source `demo-10` | `bd import` |
| `session-list` | two seeded session rows, enriched to `asleep` (no runtime) | `bd import` into the city store |
| `agents` | the config-derived agents, all `stopped` (no controller) | the city's agent config |

The run fixture adds role-addressed beads (`demo-biz-*`, `demo-member-*` and the two convoys) without renaming the canonical `demo-1` … `demo-12` data; `demo-convoy` tracks the canonical `demo-10` epic.

## Sessions

Sessions are beads (`issue_type: session`, label `gc:session`) and
`gc session list` reads the city (HQ) store, so the seed imports
`demo-session-dev` and `demo-session-review` there (a `--rig` import would land
in the rig store and stay invisible).  Their metadata pins `session_name`
(`demo-agent`, `demo-reviewer`), `agent_name`/`template`
(`demo-rig/gc.implementation-worker`, `demo-rig/gc.reviewer`), `provider`
(`claude`) and `work_dir` (`${TMPDIR:-/tmp}/demo-project`); the titles name
`demo-3` and `demo-4`.

**Determinism trade-off.** `gc session list` enriches a session row with the
runtime.  No controller runs in the fixture, so gc reports the honest
`asleep` state (and a zero `last_active`) rather than a fabricated running
provider; the seed and `--verify` pin exactly what gc emits.  If a future gc
version changes the enrichment, `--verify` fails loudly instead of silently
capturing a different state.  `work_dir` is set on `demo-3`/`demo-4` with a
metadata overlay generated from the vendored dataset (`bd update` would stamp
`updated_at` with the wall clock), so the Agent Detail "Work" join has a
visible anchor without mutating the dataset file.  `--verify` asserts the
session rows and the pinned timestamps.

## Exclusions and risks (no silent fake)

The plan's "no silent fake" rule: anything the fixture cannot produce from
offline `gc`/`bd` commands is excluded with a reason rather than synthesized.

- **Runtime-only cockpit signals** (`controller.running`, live agent counts)
  read `false`/empty offline. The cockpit still renders its config-derived
  sections; the capture records that degraded state rather than faking a
  running controller.
- **`agent-detail`** is still out of the 25-view capture manifest.  The seeded
  session rows give it a real row to open (store-level `gc session list
  --json --state all` returns both), but whether the view renders is Phase 7's
  manual-only check.  Follow-up bead `ga-9ewjs` tracks capturing it (and
  `mail-thread`) once that check passes; this phase deliberately does not add
  a view or change the image count.
- **`mail-thread`** stays out of the manifest.  The `demo-mail-review` message
  bead exists, but `gc mail inbox` resolves the *current agent's* session /
  the supervisor API, which the offline fixture does not have: `gc mail inbox
  human --json` returns an empty inbox even with the bead present.  The bead
  stays as fixture data for a future session-backed capture; the follow-up
  bead above covers it.
- **Runs and run-detail** need no controller: the fixture seeds the rich
  `build-basic on demo-10` run (with its source convoy, business beads and
  member runs), the flat `do-work` run, the standalone `review` run and the
  inline-drain run with `bd import` (above), so both views render real store
  data.  The rich run and its eighth member are `in_progress` (Active, with
  the member as a sub-run); the flat run is closed failed and the standalone
  is closed done, so both sit in the Closed history (the Failed section only
  looks back 24h, and every fixture timestamp is pinned to 2025-01-01).  The
  review loop's failed iteration gives the rich run detail a failed machinery
  step and an inspector failure.  With no session, the inspector honestly
  reads `no session` and the member line says `no live worker`.
- **Events over the API.** Every `gc` call in the capture inherits the
  fixture `GC_HOME`, and `gc events` then resolves through the supervisor API,
  which does not exist for this city: it fails with
  `could not auto-discover the supervisor API`. The cockpit's Activity
  section and the run detail's inspector show that honest
  `events unavailable` state rather than a fabricated empty log; the local
  `.gc/events.jsonl` still feeds the Events view, which does not need the
  API.
- **Bookmarks** are Emacs-side (`gascity-bookmark.el`), not a `gc` store, so
  the fixture cannot write them; the shot list sets two real gascity
  bookmarks in-session (`bookmark-default-file` pointed at a throwaway path)
  before opening `bookmark-bmenu-list`. The developer's own bookmark file is
  never read or written.
- **Relative timestamps.** Events pin absolute epochs, but a view that renders
  "3 months ago" drifts with wall-clock time; the WI-2 normalization hook owns
  mapping those back to role/relative tokens before export (plan D4).
- **`gc init`/`gc rig add` generated data.** City/rig registration writes
  run-dependent values (paths, a random project id inside `.beads`).  They are
  not part of any committed image directly; the project's git history is
  pinned and `.beads` is untracked, and `--verify` covers reproducibility at
  the store and image level.
