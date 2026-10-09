#!/usr/bin/env bash
# gascity-fixture.sh --- deterministic, role-addressed Gas City seed data.
#
# Seeds one Gas City workspace (created by `fixture.sh --create') with a
# fixed, reproducible set of objects so the screenshot pipeline never reads a
# live store.  Every object is addressed by *role* (`demo-<role>'), never by a
# run-generated id, and every timestamp is pinned, so two seed runs produce the
# same data.
#
# Usage:
#   gascity-fixture.sh --city <dir> [--rig <dir>]
#   gascity-fixture.sh --help
#
# The city directory is a Gas City workspace with a `demo-rig' rig (prefix
# `demo') registered; `--rig' is the rig's source repository path (defaults to
# `<city>/rig', where `fixture.sh --create' puts it).  Seeding is idempotent:
# re-running upserts the same role ids.
#
# Isolation: the four variables below can reroute `bd'/`gc' at the shared
# production store.  They are unset before every `bd'/`gc' call and hardcoded
# here because a POSIX shell cannot read beads.el's Lisp constant
# `beads-test-isolation-env-vars' (lisp/test/beads-integration-test.el).  Keep
# the two lists in sync; the WI-6 `:unit' test asserts the equality by reading
# `fixture.sh print-isolation-vars'.  `gc' is always invoked with an explicit
# `--city' as well, so a leaked `GC_CITY' cannot redirect it either.

set -euo pipefail

readonly FIXTURE_PREFIX="demo"
readonly FIXTURE_RIG_NAME="demo-rig"

# Hardcoded isolation list.  One name per array entry, in the same order as
# `beads-test-isolation-env-vars' in
# ~/workspace/beads.el/lisp/test/beads-integration-test.el.
readonly ISOLATION_ENV_VARS=(
  BEADS_DIR
  BEADS_DOLT_PORT
  BEADS_DOLT_SERVER_PORT
  GC_DOLT_PORT
)

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR

# Pinned clock used for every seeded timestamp.  A fixed epoch (not "now")
# keeps two seed runs byte-identical.
readonly FIXTURE_EPOCH="2025-01-01T00:00:00Z"

CITY=""
RIG=""

die() {
  printf 'gascity-fixture.sh: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "required tool not found on PATH: $1"
}

usage() {
  cat <<'EOF'
Usage: gascity-fixture.sh --city <city-dir> [--rig <rig-repo>]

Seed a Gas City workspace created by `fixture.sh --create' with the
role-addressed fixture: beads, a mail thread, orders, and pinned events.

  --city <dir>   Gas City workspace to seed (required).
  --rig <dir>    Rig source repository (default: <city>/rig).
  --help, -h     Show this help.

Environment: the four isolation variables (BEADS_DIR, BEADS_DOLT_PORT,
BEADS_DOLT_SERVER_PORT, GC_DOLT_PORT) are unset before every bd/gc call.
EOF
}

unset_isolation_vars() {
  local var
  for var in "${ISOLATION_ENV_VARS[@]}"; do
    unset "$var"
  done
}

# Defense in depth: even though every `gc' call passes an explicit --city, a
# leaked GC_CITY/GC_DIR is unset so it cannot redirect a command.
unset_gc_location_vars() {
  unset GC_CITY GC_CITY_PATH GC_CITY_RUNTIME_DIR GC_CITY_NAME \
    GC_DIR GC_RIG GC_RIG_ROOT GC_BEADS_SCOPE_ROOT \
    GC_SESSION_ID GC_SESSION_NAME GC_AGENT GC_ALIAS
}

# Run `gc' against the fixture city, never a leaked GC_CITY.
gc_fixture() {
  gc --city "$CITY" "$@"
}

# ---------------------------------------------------------------------------
# Beads
# ---------------------------------------------------------------------------

# Role-addressed issue set.  Ids are `demo-<role>'; labels, statuses,
# dependencies (blocks and parent-child), and comments are all carried so the
# importer expresses them without post-import writes.  Timestamps are pinned to
# FIXTURE_EPOCH.
seed_beads() {
  local jsonl="$CITY/.gc/fixture-beads.jsonl"
  cat >"$jsonl" <<'JSONL'
{"_type":"issue","id":"demo-epic-manual","title":"Epic: user manual and reproducible screenshots","description":"Track the task-organized manual and the fixture-driven screenshot pipeline.","status":"open","priority":2,"issue_type":"epic","assignee":"demo","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","labels":["docs","epic"]}
{"_type":"issue","id":"demo-task-manual","title":"Write the task-organized manual","description":"Author the Task Guide and keep the reference chapters.","status":"in_progress","priority":2,"issue_type":"task","assignee":"demo","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","labels":["docs","manual"],"dependencies":[{"issue_id":"demo-task-manual","depends_on_id":"demo-epic-manual","type":"parent-child","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-task-fixture","title":"Build the deterministic fixture","description":"Create the throwaway city + rig and the role-addressed seed data.","status":"in_progress","priority":1,"issue_type":"task","assignee":"demo","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","labels":["docs","screenshots"],"dependencies":[{"issue_id":"demo-task-fixture","depends_on_id":"demo-epic-manual","type":"parent-child","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-task-capture","title":"Capture the fixture views","description":"Extend capture.sh with scope and verify and capture every documented view.","status":"open","priority":2,"issue_type":"task","assignee":"demo","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","labels":["docs","screenshots"],"dependencies":[{"issue_id":"demo-task-capture","depends_on_id":"demo-task-fixture","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-task-capture","depends_on_id":"demo-epic-manual","type":"parent-child","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-bug-render","title":"Cockpit drops the events section when the API is down","description":"Opening a city with no controller blanks the events section instead of showing the empty state.","status":"blocked","priority":0,"issue_type":"bug","assignee":"demo","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","labels":["cockpit","bug"],"dependencies":[{"issue_id":"demo-bug-render","depends_on_id":"demo-task-capture","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-chore-cleanup","title":"Remove the legacy screenshot mockups","description":"Replace the sling mockup captions with real captures once the fixture lands.","status":"closed","priority":3,"issue_type":"chore","assignee":"demo","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-02T00:00:00Z","closed_at":"2025-01-02T00:00:00Z","labels":["cleanup"]}
{"_type":"issue","id":"demo-mail-thread","title":"Screenshot fixture review","description":"Fixture is seeded and reproducible; please verify the cockpit capture.","status":"open","priority":2,"issue_type":"message","assignee":"human","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","labels":["mail"],"comments":[{"author":"demo","text":"Second message in the thread: the fixture never touches a live store.","created_at":"2025-01-01T00:05:00Z"}]}
JSONL

  # `gc bd --rig <name>' answers from the rig's beads store; the ids carry the
  # rig prefix (`demo').  All chatter goes to stderr.
  gc_fixture bd --rig "$FIXTURE_RIG_NAME" import "$jsonl" --quiet 1>&2
  rm -f -- "$jsonl"
}

# ---------------------------------------------------------------------------
# Orders
# ---------------------------------------------------------------------------

# Two deterministic city orders so the order list has fixture-owned rows
# alongside the pack-provided ones.  Orders are flat orders/<name>.toml files.
seed_orders() {
  local dir="$CITY/orders"
  mkdir -p "$dir"
  cat >"$dir/demo-health.toml" <<'TOML'
[order]
description = "Fixture order: periodic health check"
trigger = "cooldown"
interval = "5m"
exec = "gc status --json"
timeout = "30s"
TOML
  cat >"$dir/demo-nightly.toml" <<'TOML'
[order]
description = "Fixture order: nightly manual rebuild"
trigger = "cron"
schedule = "0 3 * * *"
exec = "make -C doc"
timeout = "10m"
TOML
}

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

# The event log is the city's .gc/events.jsonl; `gc events' reads it without a
# running controller.  Every line pins seq, ts, actor, subject, and message so
# the events view renders the same data on every run.
seed_events() {
  cat >"$CITY/.gc/events.jsonl" <<'JSONL'
{"seq":1,"type":"city.created","ts":"2025-01-01T00:00:00Z","actor":"demo","subject":"demo-rig","message":"Fixture city created"}
{"seq":2,"type":"bead.created","ts":"2025-01-01T00:00:01Z","actor":"demo","subject":"demo-task-fixture","message":"Fixture task created"}
{"seq":3,"type":"bead.updated","ts":"2025-01-01T00:00:02Z","actor":"demo","subject":"demo-task-fixture","message":"Fixture task moved to in_progress"}
{"seq":4,"type":"mail.sent","ts":"2025-01-01T00:00:03Z","actor":"demo","subject":"demo-mail-thread","message":"Fixture mail sent"}
{"seq":5,"type":"order.fired","ts":"2025-01-01T00:00:04Z","actor":"demo","subject":"demo-health","message":"Fixture order fired"}
{"seq":6,"type":"city.health","ts":"2025-01-01T00:00:05Z","actor":"demo","subject":"demo-rig","message":"Fixture health observation"}
JSONL
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  unset_isolation_vars
  unset_gc_location_vars

  while [ $# -gt 0 ]; do
    case "$1" in
      --city) CITY="${2:-}"; shift 2 ;;
      --city=*) CITY="${1#--city=}"; shift ;;
      --rig) RIG="${2:-}"; shift 2 ;;
      --rig=*) RIG="${1#--rig=}"; shift ;;
      help | --help | -h) usage; exit 0 ;;
      *) die "unknown argument: $1 (see --help)" ;;
    esac
  done

  [ -n "$CITY" ] || die "--city is required"
  [ -d "$CITY" ] || die "city directory does not exist: $CITY"
  [ -f "$CITY/city.toml" ] || die "not a Gas City workspace: $CITY"
  [ -n "$RIG" ] || RIG="$CITY/rig"
  [ -d "$RIG" ] || die "rig repository does not exist: $RIG"

  require_tool gc

  seed_beads
  seed_orders
  seed_events
  printf 'gascity-fixture.sh: seeded %s (rig %s) at %s\n' \
    "$FIXTURE_RIG_NAME" "$RIG" "$CITY" >&2
}

main "$@"
