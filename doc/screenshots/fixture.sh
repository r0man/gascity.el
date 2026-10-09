#!/usr/bin/env bash
# fixture.sh --- deterministic, throwaway Gas City fixture for the screenshot
# pipeline.
#
# Lifecycle (one temp city + one rig per run):
#
#   fixture.sh --create    Create the city + rig; print FIXTURE_CITY and
#                          FIXTURE_RIG (machine-readable) and remember the
#                          fixture so --seed/--teardown need no argument.
#   fixture.sh --seed      Seed the fixture with role-addressed data
#                          (delegates to fixtures/gascity-fixture.sh).
#   fixture.sh --teardown  Remove the fixture and print the removed path.
#   fixture.sh --verify    create + seed + assert + teardown, in one shot.
#   fixture.sh print-isolation-vars
#                          Print the hardcoded isolation variable names.
#
# The fixture lives under `mktemp -d' (TMPDIR, default /tmp) and is removed by
# --teardown.  It never touches the repository's own .beads store, the live
# city (~/emacs-city), or the remote test city (~/bright-lights); a marker file
# and a path-prefix check make --teardown refuse to delete anything else.
#
# Isolation: the four variables below can reroute `bd'/`gc' at a shared
# production store.  They are unset before every `bd'/`gc' call and hardcoded
# here because a POSIX shell cannot read beads.el's Lisp constant
# `beads-test-isolation-env-vars' (lisp/test/beads-integration-test.el).  Keep
# the two lists in sync; the WI-6 `:unit' test asserts the equality by reading
# `fixture.sh print-isolation-vars'.  Every `gc' call also passes an explicit
# `--city' so a leaked `GC_CITY' cannot redirect it either.

set -euo pipefail

readonly FIXTURE_PREFIX="demo"
readonly FIXTURE_RIG_NAME="demo-rig"

readonly ISOLATION_ENV_VARS=(
  BEADS_DIR
  BEADS_DOLT_PORT
  BEADS_DOLT_SERVER_PORT
  GC_DOLT_PORT
)

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
readonly REPO="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
readonly SEED_SCRIPT="$SCRIPT_DIR/fixtures/gascity-fixture.sh"
readonly CITY_CONFIG="$SCRIPT_DIR/fixtures/city.toml"

readonly TMP_ROOT="${TMPDIR:-/tmp}"
readonly FIXTURE_DIR_PREFIX="gascity-fixture."
readonly FIXTURE_MARKER=".gascity-fixture-city"
# Where --create records the current fixture for --seed/--teardown.  Override
# with FIXTURE_STATE to run two fixtures side by side.
readonly STATE_FILE="${FIXTURE_STATE:-$TMP_ROOT/gascity-fixture.current}"

# Pinned git identity/date for the throwaway rig's single commit, so the rig
# repo (and the commit hash) is identical on every create.
readonly FIXTURE_GIT_DATE="2025-01-01T00:00:00Z"

CITY=""

die() {
  printf 'fixture.sh: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "required tool not found on PATH: $1"
}

usage() {
  cat <<'EOF'
Usage: fixture.sh <command> [--city <dir>]

Commands:
  --create, create       Create the throwaway city + rig and print
                         FIXTURE_CITY=<path> / FIXTURE_RIG=<path>.
  --seed, seed           Seed the fixture (beads, mail, orders, events).
  --teardown, teardown   Remove the fixture and report the removed path.
  --verify, verify       create + seed + assert role ids + teardown.
  print-isolation-vars   Print the hardcoded isolation variable names.
  help, --help, -h       Show this help.

--seed and --teardown use the fixture remembered by --create; pass --city to
address one explicitly.  The recorded fixture is the only thing removed, and
only when it sits under TMPDIR with the fixture marker.
EOF
}

unset_isolation_vars() {
  local var
  for var in "${ISOLATION_ENV_VARS[@]}"; do
    unset "$var"
  done
}

# `gc init' takes no --city, so a GC_CITY/GC_DIR leaked from a Gas Town agent
# shell could redirect it at a real city.  Neutralize the location/identity
# variables too; the four store-routing names stay in ISOLATION_ENV_VARS so the
# drift test compares exactly that list.
unset_gc_location_vars() {
  unset GC_CITY GC_CITY_PATH GC_CITY_RUNTIME_DIR GC_CITY_NAME \
    GC_DIR GC_RIG GC_RIG_ROOT GC_BEADS_SCOPE_ROOT \
    GC_SESSION_ID GC_SESSION_NAME GC_AGENT GC_ALIAS
}

print_isolation_vars() {
  printf '%s\n' "${ISOLATION_ENV_VARS[@]}"
}

record_fixture() {
  printf '%s\n' "$1" >"$STATE_FILE"
}

recall_fixture() {
  [ -n "$CITY" ] || {
    [ -r "$STATE_FILE" ] || die "no fixture recorded; run --create first"
    CITY=$(cat "$STATE_FILE")
  }
  [ -n "$CITY" ] || die "recorded fixture is empty"
}

# ---------------------------------------------------------------------------
# create
# ---------------------------------------------------------------------------

create_rig() {
  local rig="$1"
  mkdir -p "$rig"
  git -C "$rig" init -q
  git -C "$rig" config user.email "fixture@gascity.invalid"
  git -C "$rig" config user.name "Gascity Fixture"
  printf '# demo-rig\n\nDeterministic fixture rig for the screenshot pipeline.\n' \
    >"$rig/README.md"
  git -C "$rig" add -A
  GIT_AUTHOR_DATE="$FIXTURE_GIT_DATE" \
  GIT_COMMITTER_DATE="$FIXTURE_GIT_DATE" \
    git -C "$rig" commit -qm "fixture: initial commit"
}

create_fixture() {
  require_tool gc
  require_tool git
  require_tool mktemp
  [ -r "$CITY_CONFIG" ] || die "city config not found: $CITY_CONFIG"

  local city rig
  city=$(mktemp -d "$TMP_ROOT/$FIXTURE_DIR_PREFIX"XXXXXX) \
    || die "mktemp -d failed under $TMP_ROOT"
  rig="$city/rig"

  if ! {
    create_rig "$rig"
    # --no-start: no controller/registration.  --skip-provider-readiness: the
    # builtin provider is never contacted.  --file: minimal config with no
    # live provider.  Explicit path: never the launcher checkout.
    (cd "$city" && gc init --no-start --skip-provider-readiness \
      --file "$CITY_CONFIG" "$city" 1>&2)
    gc --city "$city" rig add "$rig" --name "$FIXTURE_RIG_NAME" \
      --prefix "$FIXTURE_PREFIX" --default-branch main 1>&2
  }; then
    rm -rf -- "$city"
    die "failed to create fixture city in $city"
  fi

  [ -f "$city/city.toml" ] || {
    rm -rf -- "$city"
    die "fixture city has no city.toml: $city"
  }
  : >"$city/$FIXTURE_MARKER"
  record_fixture "$city"
  printf 'FIXTURE_CITY=%s\nFIXTURE_RIG=%s\nFIXTURE_RIG_NAME=%s\n' \
    "$city" "$rig" "$FIXTURE_RIG_NAME"
}

# ---------------------------------------------------------------------------
# seed
# ---------------------------------------------------------------------------

seed_fixture() {
  recall_fixture
  require_tool gc
  [ -d "$CITY" ] || die "fixture city is gone: $CITY"
  [ -f "$CITY/$FIXTURE_MARKER" ] \
    || die "not a fixture city (missing $FIXTURE_MARKER): $CITY"
  [ -r "$SEED_SCRIPT" ] || die "seed script not found: $SEED_SCRIPT"
  bash "$SEED_SCRIPT" --city "$CITY" --rig "$CITY/rig"
}

# ---------------------------------------------------------------------------
# teardown
# ---------------------------------------------------------------------------

teardown_fixture() {
  recall_fixture

  case "$CITY" in
    "$TMP_ROOT/$FIXTURE_DIR_PREFIX"*) ;;
    *) die "refusing to remove unexpected path: $CITY" ;;
  esac

  [ -d "$CITY" ] || {
    printf 'fixture.sh: already gone: %s\n' "$CITY" >&2
    rm -f -- "$STATE_FILE"
    return 0
  }
  [ -f "$CITY/$FIXTURE_MARKER" ] \
    || die "refusing to remove $CITY: missing $FIXTURE_MARKER (not a fixture city)"

  rm -rf -- "$CITY"
  rm -f -- "$STATE_FILE"
  printf 'fixture.sh: removed %s\n' "$CITY" >&2
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------

# Create, seed, assert the fixture is role-addressed and the repository store
# was untouched, then tear down.  Exits non-zero on the first failure.
verify_fixture() {
  require_tool python3
  require_tool gc

  local repo_beads="$REPO/.beads"
  local before_mtime=""
  [ -e "$repo_beads" ] && before_mtime=$(stat -c '%Y' "$repo_beads")

  local created city
  created=$(create_fixture)
  city=$(printf '%s\n' "$created" | sed -n 's/^FIXTURE_CITY=//p')
  [ -n "$city" ] || die "create did not print FIXTURE_CITY"
  trap 'rm -rf -- "${city:-}"' EXIT

  seed_fixture

  # Assert the seeded store is role-addressed: every rig bead id is
  # `demo-<role>`, and the required roles exist.
  gc --city "$city" bd --rig "$FIXTURE_RIG_NAME" export \
    | python3 -c '
import json
import re
import sys

prefix = sys.argv[1]
required = {
    "demo-epic-manual",
    "demo-task-manual",
    "demo-task-fixture",
    "demo-task-capture",
    "demo-bug-render",
    "demo-chore-cleanup",
}
ids = set()
role_re = re.compile(rf"^{re.escape(prefix)}-[a-z0-9][a-z0-9-]*$")
errors = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    issue = json.loads(line)
    ident = issue.get("id", "")
    ids.add(ident)
    if not role_re.match(ident):
        errors.append(f"non role id (run-generated?): {ident}")
missing = sorted(required - ids)
if missing:
    errors.append(f"missing role ids: {missing}")
if errors:
    for error in errors:
        print(f"fixture.sh: verify: {error}", file=sys.stderr)
    sys.exit(1)
print(f"fixture.sh: verify: {len(ids)} role-keyed beads OK", file=sys.stderr)
' "$FIXTURE_PREFIX"

  # `bd export` drops type=message rows, so the mail fixture bead is checked
  # directly.  It is a message addressed to `human' (a seeded mail thread).
  local mail_type
  mail_type=$(gc --city "$city" bd --rig "$FIXTURE_RIG_NAME" show demo-mail-thread --json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d; print(d.get("issue_type",""))')
  [ "$mail_type" = "message" ] \
    || die "mail fixture bead demo-mail-thread is missing or not a message"

  # Orders and events must be present and pinned.
  [ -f "$city/orders/demo-health.toml" ] || die "missing fixture order demo-health"
  [ -f "$city/orders/demo-nightly.toml" ] || die "missing fixture order demo-nightly"
  [ -s "$city/.gc/events.jsonl" ] || die "fixture event log is empty"

  # The repository's own .beads store must be untouched.
  local after_mtime=""
  [ -e "$repo_beads" ] && after_mtime=$(stat -c '%Y' "$repo_beads")
  if [ "$before_mtime" != "$after_mtime" ]; then
    die "repository .beads mtime changed ($before_mtime -> $after_mtime): isolation failed"
  fi

  teardown_fixture
  trap - EXIT
  printf 'fixture.sh: PASS\n'
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  unset_isolation_vars
  unset_gc_location_vars
  local command=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --city) CITY="${2:-}"; shift 2 ;;
      --city=*) CITY="${1#--city=}"; shift ;;
      -* | *)
        [ -z "$command" ] || die "unexpected argument: $1"
        command="$1"; shift ;;
    esac
  done

  case "${command:-create}" in
    --create | create) create_fixture ;;
    --seed | seed) seed_fixture ;;
    --teardown | teardown) teardown_fixture ;;
    --verify | verify) verify_fixture ;;
    print-isolation-vars) print_isolation_vars ;;
    help | --help | -h) usage ;;
    *) die "unknown command: $command (see --help)" ;;
  esac
}

main "$@"
