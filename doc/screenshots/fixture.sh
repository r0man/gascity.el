#!/usr/bin/env bash
# fixture.sh --- deterministic, throwaway Gas City fixture for the screenshot
# pipeline.
#
# Lifecycle (one temp city + one shared demo project per run):
#
#   fixture.sh --create    Create the demo project and the city + rig; print
#                          FIXTURE_CITY, FIXTURE_PROJECT, FIXTURE_RIG (an alias
#                          of FIXTURE_PROJECT), FIXTURE_RIG_NAME and
#                          FIXTURE_GC_HOME (machine-readable) and remember the
#                          fixture so --seed/--teardown need no argument.
#   fixture.sh --seed      Seed the fixture with the shared demo dataset and
#                          deterministic role data (delegates to
#                          fixtures/gascity-fixture.sh).
#   fixture.sh --teardown  Remove the city and the project.
#   fixture.sh --verify    create + seed + assert + teardown, in one shot.
#   fixture.sh --self-test Offline teardown-guard/idempotence check; no city.
#   fixture.sh print-isolation-vars
#                          Print the hardcoded isolation variable names.
#
# The fixture lives at fixed paths under TMPDIR (default:
# `/tmp/gascity-fixture' for the city and `/tmp/demo-project' for the project,
# the path the beads.el manual shares).  It is removed by --teardown.  It
# never touches the repository's own .beads store, the live city
# (~/emacs-city), or the remote test city (~/bright-lights); marker files and a
# path-prefix check make --teardown refuse to delete anything else.
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
# A FIXED directory name, not `mktemp -d': gc derives the city name and every
# header/mode line from the directory basename, and header lines are not buffer
# text, so a random suffix could not be normalized out of a committed image.
# A stable path keeps every capture byte-reproducible.  `--create' removes a
# stale fixture at this path first.  `FIXTURE_STATE' only isolates the city
# record and its state file: the demo-project checkout below is one fixed path
# per $TMPDIR, so parallel fixtures need separate `TMPDIR's (or must run
# serially).
readonly FIXTURE_DIR_PREFIX="gascity-fixture"
readonly FIXTURE_MARKER=".gascity-fixture-city"
# The shared demo project: the same path the beads.el manual uses, so both
# manuals describe one project with one stable basename.  It is the rig's
# source repository (NOT under the city tree) and carries its own marker so
# --teardown can refuse a non-fixture path.
readonly FIXTURE_PROJECT_NAME="demo-project"
readonly FIXTURE_PROJECT_MARKER=".gascity-fixture-project"
readonly FIXTURE_PROJECT="$TMP_ROOT/$FIXTURE_PROJECT_NAME"
# Name the fixture city in the fixture `GC_HOME' registry, so the Cities
# view (`gc cities', which reads `$GC_HOME/cities.toml') lists the fixture
# and never the machine's live cities.  capture.sh exports GC_HOME to the
# engine; see doc/screenshots/README.md.
readonly FIXTURE_CITY_NAME="gascity-fixture"
# Where --create records the current fixture for --seed/--teardown.  Override
# with FIXTURE_STATE to keep two city records side by side; the shared project
# checkout still needs its own `TMPDIR' for true isolation.
readonly STATE_FILE="${FIXTURE_STATE:-$TMP_ROOT/gascity-fixture.current}"

# Pinned git identity/date for the throwaway project's single commit, so the
# project repo (and the commit hash) is identical on every create.
readonly FIXTURE_GIT_DATE="2025-01-01T00:00:00Z"

CITY=""
# Set while this process created FIXTURE_PROJECT, so a failure cleanup can
# remove it even if the marker write itself failed.  A pre-existing path
# without the marker is never adopted (see create_fixture).
PROJECT_CREATED=""

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
  --create, create       Create the demo project and the throwaway city + rig
                         and print FIXTURE_CITY=<path> / FIXTURE_PROJECT=<path>
                         / FIXTURE_RIG=<path> / FIXTURE_RIG_NAME=<name> /
                         FIXTURE_GC_HOME=<path>.  FIXTURE_RIG is an alias of
                         FIXTURE_PROJECT (the rig is the project checkout).
  --seed, seed           Seed the fixture (demo beads, sessions, mail, run,
                         orders, events).
  --teardown, teardown   Remove the city and the project; report what was
                         removed.
  --verify, verify       create + seed + assert the fixture; teardown.
  --self-test, self-test Offline teardown-guard/idempotence check; no city.
  print-isolation-vars   Print the hardcoded isolation variable names.
  help, --help, -h       Show this help.

--seed and --teardown use the fixture remembered by --create; pass --city to
address one explicitly.  The recorded city and the shared project at
${TMPDIR:-/tmp}/demo-project are the only things removed, and only when they
sit under TMPDIR with their fixture markers.
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

# Remove the artifacts this process created.  The city needs its marker; the
# project needs its marker or the PROJECT_CREATED flag (a create that failed
# before committing still owns the directory it made).
remove_fixture_paths() {
  local city="${1:-}"
  if [ -n "$city" ] && [ -d "$city" ] && [ -f "$city/$FIXTURE_MARKER" ]; then
    rm -rf -- "$city"
  fi
  if [ -d "$FIXTURE_PROJECT" ] \
    && { [ -n "${PROJECT_CREATED:-}" ] \
         || [ -f "$FIXTURE_PROJECT/$FIXTURE_PROJECT_MARKER" ]; }; then
    rm -rf -- "$FIXTURE_PROJECT"
  fi
  PROJECT_CREATED=""
}

# ---------------------------------------------------------------------------
# create
# ---------------------------------------------------------------------------

# One README commit, pinned identity and dates.  The project is a plain git
# checkout: no `.beads' is committed (gc initializes the rig's store into the
# checkout when `rig add' runs; that store is gitignored by gc's own
# .gitignore, so the repository history stays a single README commit).
create_project() {
  mkdir -p "$FIXTURE_PROJECT"
  # Write the marker before anything can fail: every cleanup path is
  # marker-guarded, so a half-built project is still ours to remove.
  : >"$FIXTURE_PROJECT/$FIXTURE_PROJECT_MARKER"
  PROJECT_CREATED=1
  git -C "$FIXTURE_PROJECT" init -q
  git -C "$FIXTURE_PROJECT" config user.email "fixture@gascity.invalid"
  git -C "$FIXTURE_PROJECT" config user.name "Gascity Fixture"
  printf '# demo-project\n\nDeterministic fixture project shared with the beads.el\nmanual; it is the source checkout of the demo-rig rig.\n' \
    >"$FIXTURE_PROJECT/README.md"
  # Add only the README: the marker is a lifecycle file, not project content.
  git -C "$FIXTURE_PROJECT" add README.md
  GIT_AUTHOR_DATE="$FIXTURE_GIT_DATE" \
  GIT_COMMITTER_DATE="$FIXTURE_GIT_DATE" \
    git -C "$FIXTURE_PROJECT" commit -qm "fixture: initial commit"
}

create_fixture() {
  require_tool gc
  require_tool git
  require_tool mktemp
  [ -r "$CITY_CONFIG" ] || die "city config not found: $CITY_CONFIG"

  local city="$TMP_ROOT/$FIXTURE_DIR_PREFIX"
  if [ -e "$city" ]; then
    [ -f "$city/$FIXTURE_MARKER" ] \
      || die "refusing to reuse non-fixture path: $city"
    rm -rf -- "$city"
  fi
  if [ -e "$FIXTURE_PROJECT" ]; then
    [ -f "$FIXTURE_PROJECT/$FIXTURE_PROJECT_MARKER" ] \
      || die "refusing to reuse non-fixture project path: $FIXTURE_PROJECT"
    rm -rf -- "$FIXTURE_PROJECT"
  fi
  mkdir -p "$city" || die "mkdir failed under $TMP_ROOT"

  if ! {
    create_project
    # --no-start: no controller/registration.  --skip-provider-readiness: the
    # builtin provider is never contacted.  --file: minimal config with no
    # live provider.  Explicit path: never the launcher checkout.
    (cd "$city" && gc init --no-start --skip-provider-readiness \
      --file "$CITY_CONFIG" "$city" 1>&2)
    gc --city "$city" rig add "$FIXTURE_PROJECT" \
      --name "$FIXTURE_RIG_NAME" --prefix "$FIXTURE_PREFIX" \
      --default-branch main 1>&2
  }; then
    remove_fixture_paths "$city"
    die "failed to create fixture city in $city"
  fi

  [ -f "$city/city.toml" ] || {
    remove_fixture_paths "$city"
    die "fixture city has no city.toml: $city"
  }
  # `gc rig add' runs `bd init', which commits the new store as "bd init:
  # initialize beads issue tracking" onto the project.  That commit carries a
  # wall-clock date, so drop it: the project history stays the one synthetic
  # README commit, and the rig's store remains in the working tree (untracked
  # and gitignored), where gc expects it.  No view renders the dropped commit.
  if [ "$(git -C "$FIXTURE_PROJECT" log -1 --format=%s 2>/dev/null)" \
       = "bd init: initialize beads issue tracking" ]; then
    git -C "$FIXTURE_PROJECT" reset --mixed --quiet HEAD~1
  fi
  [ "$(git -C "$FIXTURE_PROJECT" rev-list --count HEAD 2>/dev/null)" = "1" ] || {
    remove_fixture_paths "$city"
    die "demo project history is not the single README commit"
  }
  : >"$city/$FIXTURE_MARKER"
  seed_gc_home "$city"
  record_fixture "$city"
  printf 'FIXTURE_CITY=%s\nFIXTURE_PROJECT=%s\nFIXTURE_RIG=%s\nFIXTURE_RIG_NAME=%s\nFIXTURE_GC_HOME=%s\n' \
    "$city" "$FIXTURE_PROJECT" "$FIXTURE_PROJECT" "$FIXTURE_RIG_NAME" "$city/gc-home"
}

# A throwaway `GC_HOME' (gc's user-level state dir, normally ~/.gc) whose
# `cities.toml' registers only the fixture city.  Every view that reads the
# machine-wide city registry is then scoped to the fixture instead of the
# developer's live cities.
seed_gc_home() {
  local city="$1" home="$city/gc-home"
  mkdir -p "$home"
  cat >"$home/cities.toml" <<EOF
[[cities]]
  path = "$city"
  name = "$FIXTURE_CITY_NAME"
EOF
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
  [ -f "$FIXTURE_PROJECT/$FIXTURE_PROJECT_MARKER" ] \
    || die "fixture project is missing or unmarked: $FIXTURE_PROJECT"
  [ -r "$SEED_SCRIPT" ] || die "seed script not found: $SEED_SCRIPT"
  bash "$SEED_SCRIPT" --city "$CITY" --rig "$FIXTURE_PROJECT"
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
  case "$FIXTURE_PROJECT" in
    "$TMP_ROOT/$FIXTURE_PROJECT_NAME") ;;
    *) die "refusing to remove unexpected project path: $FIXTURE_PROJECT" ;;
  esac

  if [ -e "$CITY" ] && [ ! -f "$CITY/$FIXTURE_MARKER" ]; then
    die "refusing to remove $CITY: missing $FIXTURE_MARKER (not a fixture city)"
  fi
  if [ -e "$FIXTURE_PROJECT" ] \
    && [ ! -f "$FIXTURE_PROJECT/$FIXTURE_PROJECT_MARKER" ]; then
    die "refusing to remove $FIXTURE_PROJECT: missing $FIXTURE_PROJECT_MARKER (not a fixture project)"
  fi

  if [ -d "$CITY" ]; then
    rm -rf -- "$CITY"
    printf 'fixture.sh: removed %s\n' "$CITY" >&2
  else
    printf 'fixture.sh: already gone: %s\n' "$CITY" >&2
  fi
  if [ -d "$FIXTURE_PROJECT" ]; then
    rm -rf -- "$FIXTURE_PROJECT"
    printf 'fixture.sh: removed %s\n' "$FIXTURE_PROJECT" >&2
  else
    printf 'fixture.sh: already gone: %s\n' "$FIXTURE_PROJECT" >&2
  fi
  rm -f -- "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

# Offline checks for the teardown guard, run by `make check'.  The shared
# `${TMPDIR}/demo-project' path is also beads.el's fixture path, so a project
# without our marker must never be deleted; a repeated teardown must also be
# harmless.  Every subprocess runs with TMPDIR pointed at a scratch directory,
# so the real fixture and the real demo-project are untouched.
self_test_fixture() {
  require_tool mktemp
  local scratch city project err script
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/gascity-fixture-self-test.XXXXXX") \
    || die "self-test: mktemp failed"
  trap 'rm -rf -- "$scratch"' EXIT
  script="$SCRIPT_DIR/fixture.sh"
  city="$scratch/$FIXTURE_DIR_PREFIX"
  project="$scratch/$FIXTURE_PROJECT_NAME"
  err="$scratch/teardown.err"

  # A marked city and project are removed together.
  mkdir -p "$city" "$project"
  : >"$city/$FIXTURE_MARKER"
  : >"$project/$FIXTURE_PROJECT_MARKER"
  TMPDIR="$scratch" bash "$script" --teardown --city "$city" >/dev/null 2>&1 \
    || die "self-test: teardown of a marked fixture failed"
  [ ! -e "$city" ] && [ ! -e "$project" ] \
    || die "self-test: a marked fixture was not removed"

  # A project without our marker is refused; neither path is removed.
  mkdir -p "$city" "$project"
  : >"$city/$FIXTURE_MARKER"
  if TMPDIR="$scratch" bash "$script" --teardown --city "$city" \
      >/dev/null 2>"$err"; then
    die "self-test: teardown accepted a non-marker project"
  fi
  if ! grep -q "missing $FIXTURE_PROJECT_MARKER" "$err"; then
    die "self-test: teardown refused for the wrong reason: $(cat "$err")"
  fi
  [ -d "$city" ] && [ -d "$project" ] \
    || die "self-test: teardown removed a non-marker project or the city"

  # Restoring the marker makes teardown succeed, and a second teardown is a
  # no-op (idempotent).
  : >"$project/$FIXTURE_PROJECT_MARKER"
  TMPDIR="$scratch" bash "$script" --teardown --city "$city" >/dev/null 2>&1 \
    || die "self-test: teardown after restoring the marker failed"
  TMPDIR="$scratch" bash "$script" --teardown --city "$city" >/dev/null 2>&1 \
    || die "self-test: a second teardown failed (not idempotent)"
  rm -rf -- "$scratch"
  trap - EXIT
  printf 'fixture.sh: self-test: PASS\n' >&2
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------

# Create, seed, assert the shared demo fixture and the repository store was
# untouched, then tear down.  Exits non-zero on the first failure.
verify_fixture() {
  require_tool python3
  require_tool gc
  require_tool git

  local repo_beads="$REPO/.beads"
  local before_mtime=""
  [ -e "$repo_beads" ] && before_mtime=$(stat -c '%Y' "$repo_beads")

  local created city project
  created=$(create_fixture)
  city=$(printf '%s\n' "$created" | sed -n 's/^FIXTURE_CITY=//p')
  project=$(printf '%s\n' "$created" | sed -n 's/^FIXTURE_PROJECT=//p')
  [ -n "$city" ] || die "create did not print FIXTURE_CITY"
  [ -n "$project" ] || die "create did not print FIXTURE_PROJECT"
  trap 'remove_fixture_paths "${city:-}"' EXIT

  seed_fixture

  # Every assertion about gc's own state lives in one python process so a
  # failure reports all findings at once instead of the first one.  The
  # isolation variables are already unset in this shell; python inherits them.
  python3 - "$REPO" "$city" "$project" "$FIXTURE_RIG_NAME" <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys

repo, city, project, rig_name = sys.argv[1:5]
errors = []


def fail(message):
    errors.append(message)


def gc(*args):
    """Run gc against the fixture city; return stdout or report the failure."""
    result = subprocess.run(["gc", "--city", city, *args],
                            capture_output=True, text=True)
    if result.returncode != 0:
        fail("gc %s failed (%d): %s"
             % (" ".join(args), result.returncode, result.stderr.strip()))
        return ""
    return result.stdout


def git(*args):
    result = subprocess.run(["git", "-C", project, *args],
                            capture_output=True, text=True)
    if result.returncode != 0:
        fail("git %s failed (%d): %s"
             % (" ".join(args), result.returncode, result.stderr.strip()))
    return result.stdout


# --- The shared demo dataset ------------------------------------------------
fixture_dir = os.path.join(repo, "doc", "screenshots", "fixtures")
dataset_path = os.path.join(fixture_dir, "beads-fixture.jsonl")
readme_path = os.path.join(fixture_dir, "README.md")

with open(dataset_path, "rb") as handle:
    dataset_digest = hashlib.sha256(handle.read()).hexdigest()
with open(readme_path, encoding="utf-8") as handle:
    readme = handle.read()
digest_match = re.search(r"sha256[^0-9a-f\n]*([0-9a-f]{64})", readme)
if digest_match is None:
    fail("fixtures/README.md records no sha256 digest literal")
elif digest_match.group(1) != dataset_digest:
    fail("vendored dataset sha256 %s != fixtures/README.md %s"
         % (dataset_digest, digest_match.group(1)))

canonical = {}
with open(dataset_path, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        record = json.loads(line)
        if record.get("_type") == "issue":
            canonical[record["id"]] = record
canonical_ids = {"demo-%d" % number for number in range(1, 13)}
if set(canonical) != canonical_ids:
    fail("canonical dataset ids: %s" % sorted(canonical))

# The canonical file spans more than one day: pin the span instead of
# pretending every timestamp is 2025-01-01.
timestamp_keys = ("created_at", "updated_at", "started_at", "closed_at")
canonical_timestamps = sorted(
    value
    for record in canonical.values()
    for key in timestamp_keys
    if (value := record.get(key))
)
if (canonical_timestamps[:1] != ["2025-01-01T09:00:00Z"]
        or canonical_timestamps[-1:] != ["2025-01-06T16:00:00Z"]):
    fail("canonical timestamp span changed: %s"
         % [canonical_timestamps[:1], canonical_timestamps[-1:]])

# --- The shared demo project ------------------------------------------------
if not os.path.isdir(project):
    fail("FIXTURE_PROJECT is not a directory: %s" % project)
if not os.path.isfile(os.path.join(project, ".gascity-fixture-project")):
    fail("FIXTURE_PROJECT has no .gascity-fixture-project marker: %s" % project)
# gc's `rig add' initializes the rig's `.beads' store inside the checkout; it
# is gitignored.  What must never happen is a committed `.beads' directory
# (the project history stays one README commit).
tracked = git("ls-tree", "-r", "--name-only", "HEAD").splitlines()
if any(path == ".beads" or path.startswith(".beads/") for path in tracked):
    fail("project git tree tracks .beads")
if git("rev-list", "--count", "HEAD").strip() != "1":
    fail("project must have exactly one commit (README)")
# 2025-01-01T00:00:00Z as an epoch: pin the date regardless of how git
# renders the zone (+00:00 vs Z).
if git("log", "-1", "--format=%at").strip() != "1735689600":
    fail("project author timestamp is not 2025-01-01T00:00:00Z")
if git("log", "-1", "--format=%ct").strip() != "1735689600":
    fail("project committer timestamp is not 2025-01-01T00:00:00Z")

try:
    rigs = json.loads(gc("rig", "list", "--json"))["rigs"]
except (ValueError, KeyError):
    rigs = []
    fail("gc rig list --json did not parse")
demo_rigs = [rig for rig in rigs if rig.get("name") == rig_name]
if len(demo_rigs) != 1:
    fail("rig list has %d %s entries" % (len(demo_rigs), rig_name))
else:
    demo_rig = demo_rigs[0]
    if os.path.realpath(demo_rig.get("path", "")) != os.path.realpath(project):
        fail("rig %s path %s != FIXTURE_PROJECT %s"
             % (rig_name, demo_rig.get("path"), project))
    if demo_rig.get("prefix") != "demo":
        fail("rig %s prefix %r != demo" % (rig_name, demo_rig.get("prefix")))
    if demo_rig.get("default_branch") != "main":
        fail("rig %s default branch %r != main"
             % (rig_name, demo_rig.get("default_branch")))

# --- The seeded bead set ----------------------------------------------------
run_ids = {
    "demo-run",
    "demo-prep",
    "demo-reqs",
    "demo-plan",
    "demo-plrv",
    "demo-dcmp",
    "demo-impl",
    "demo-isms",
    "demo-sumi",
    "demo-revw",
    "demo-rev1",
    "demo-finz",
    "demo-publ",
}
# The rig export carries the canonical dataset plus the role run graph.  The
# mail bead is a message (`bd export' drops message rows) and the session
# beads live in the city store, which exports on its own; both are checked
# separately below.
session_ids = {"demo-session-dev", "demo-session-review"}
expected_ids = canonical_ids | run_ids

export_rows = []
for line in gc("bd", "--rig", rig_name, "export").splitlines():
    line = line.strip()
    if line:
        export_rows.append(json.loads(line))
rows_by_id = {row.get("id"): row for row in export_rows}
if set(rows_by_id) != expected_ids:
    fail("rig beads differ: %s" % (sorted(expected_ids ^ set(rows_by_id)),))

city_export = gc("bd", "export")
city_ids = set()
for line in city_export.splitlines():
    if line.strip():
        city_ids.add(json.loads(line).get("id"))
if city_ids != session_ids:
    fail("city store beads differ: %s (want the session rows)"
         % sorted(city_ids))

for bead_id, key, value in (
        ("demo-10", "issue_type", "epic"),
        ("demo-11", "issue_type", "task"),
        ("demo-3", "status", "in_progress"),
        ("demo-4", "status", "blocked"),
        ("demo-6", "status", "closed"),
):
    row = rows_by_id.get(bead_id) or {}
    if row.get(key) != value:
        fail("%s %s %r != %r" % (bead_id, key, row.get(key), value))

parents = (rows_by_id.get("demo-11") or {}).get("dependencies") or []
if not any(dep.get("type") == "parent-child"
           and dep.get("depends_on_id") == "demo-10" for dep in parents):
    fail("demo-11 is not a child of demo-10")

# The Agent Detail "Work" join needs work_dir on the two work beads.
for bead_id in ("demo-3", "demo-4"):
    metadata = (rows_by_id.get(bead_id) or {}).get("metadata") or {}
    if metadata.get("work_dir") != project:
        fail("%s work_dir %r != FIXTURE_PROJECT %s"
             % (bead_id, metadata.get("work_dir"), project))

root = rows_by_id.get("demo-run") or {}
if root.get("title") != "build-basic on demo-10":
    fail("demo-run title %r != build-basic on demo-10" % root.get("title"))
review = rows_by_id.get("demo-revw") or {}
review_text = " ".join([str(review.get("description") or ""),
                        str((review.get("metadata") or {}).get("gc.work_beads") or "")])
if "demo-10" not in review_text or "demo-11" not in review_text:
    fail("demo-revw does not name demo-10 and demo-11")
iteration = rows_by_id.get("demo-rev1") or {}
if iteration.get("status") != "closed":
    fail("demo-rev1 status %r != closed" % iteration.get("status"))
if (iteration.get("metadata") or {}).get("gc.outcome") != "fail":
    fail("demo-rev1 gc.outcome %r != fail"
         % (iteration.get("metadata") or {}).get("gc.outcome"))

# Every timestamp is pinned: the dataset's 2025 values or a documented role
# timestamp in 2025, never the wall clock (today is 2026).
for row in export_rows:
    for key in timestamp_keys:
        value = row.get(key)
        if value and not value.startswith("2025-"):
            fail("%s %s is not a pinned 2025 timestamp: %s"
                 % (row.get("id"), key, value))
    for dep in row.get("dependencies") or []:
        value = dep.get("created_at")
        if value and not value.startswith("2025-"):
            fail("%s dependency %s created_at is not pinned: %s"
                 % (row.get("id"), dep.get("depends_on_id"), value))

# --- Sessions ---------------------------------------------------------------
try:
    session_payload = json.loads(gc("session", "list", "--json", "--state", "all"))
except (ValueError, TypeError):
    session_payload = {}
    fail("gc session list --json did not parse")
sessions = {row.get("id"): row for row in session_payload.get("sessions") or []}
expected_sessions = {
    "demo-session-dev": {
        "title": "demo-3: Fix crash when opening an empty store",
        "agent_name": "demo-rig/gc.implementation-worker",
        "session_name": "demo-agent",
        "created_at": "2025-01-05T10:00:00Z",
    },
    "demo-session-review": {
        "title": "demo-4: Write the Dolt migration guide",
        "agent_name": "demo-rig/gc.reviewer",
        "session_name": "demo-reviewer",
        "created_at": "2025-01-05T11:00:00Z",
    },
}
if set(sessions) != set(expected_sessions):
    fail("session list ids differ: %s" % sorted(sessions))
for session_id, expected in expected_sessions.items():
    row = sessions.get(session_id) or {}
    for key, value in expected.items():
        if row.get(key) != value:
            fail("%s %s %r != %r" % (session_id, key, row.get(key), value))
    if row.get("work_dir") != project:
        fail("%s work_dir %r != FIXTURE_PROJECT %s"
             % (session_id, row.get("work_dir"), project))
    # No runtime is running, so gc reports the honest enriched state; never
    # fake an active provider.
    if row.get("state") != "asleep":
        fail("%s state %r != asleep" % (session_id, row.get("state")))
    last_active = row.get("last_active") or ""
    if last_active != "0001-01-01T00:00:00Z" and not last_active.startswith("2025-"):
        fail("%s last_active is not pinned: %s" % (session_id, last_active))

# --- Mail, orders, events ---------------------------------------------------
try:
    mail_payload = json.loads(
        gc("bd", "--rig", rig_name, "show", "demo-mail-review", "--json"))
except (ValueError, TypeError):
    mail_payload = None
mail = None
if isinstance(mail_payload, list) and len(mail_payload) == 1:
    mail = mail_payload[0]
elif isinstance(mail_payload, dict):
    mail = mail_payload
if not mail:
    fail("demo-mail-review is missing")
else:
    if mail.get("issue_type") != "message":
        fail("demo-mail-review issue_type %r != message"
             % mail.get("issue_type"))
    body = " ".join(
        [str(mail.get("description") or "")]
        + [str(comment.get("text") or "")
           for comment in mail.get("comments") or []])
    if "demo-10" not in body or "demo-11" not in body:
        fail("demo-mail-review does not name demo-10 and demo-11")

for order in ("demo-health", "demo-nightly"):
    if not os.path.isfile(os.path.join(city, "orders", order + ".toml")):
        fail("missing fixture order %s" % order)

events_path = os.path.join(city, ".gc", "events.jsonl")
if not os.path.isfile(events_path) or os.path.getsize(events_path) == 0:
    fail("fixture event log is missing or empty")
else:
    event_rows = []
    with open(events_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                event_rows.append(json.loads(line))
    if [event.get("seq") for event in event_rows] != [1, 2, 3, 4, 5, 6]:
        fail("event log seq is not 1..6: %s"
             % [event.get("seq") for event in event_rows])
    allowed_subjects = expected_ids | {"demo-mail-review", "demo-health",
                                       "demo-nightly", "demo-rig"}
    for event in event_rows:
        if not str(event.get("ts", "")).startswith("2025-"):
            fail("event seq %s ts is not pinned: %r"
                 % (event.get("seq"), event.get("ts")))
        if event.get("subject") not in allowed_subjects:
            fail("event seq %s subject %r is not a documented id"
                 % (event.get("seq"), event.get("subject")))

if errors:
    for error in errors:
        print("fixture.sh: verify: %s" % error, file=sys.stderr)
    sys.exit(1)
print("fixture.sh: verify: %d beads, %d sessions, dataset %s... OK"
      % (len(rows_by_id), len(sessions), dataset_digest[:12]), file=sys.stderr)
PY

  # A negative test for the teardown guard: the shared project path is also
  # the beads.el fixture's path, so a project without our marker must never be
  # deleted (and the city must survive a refusal).
  local err="$city/teardown.err"
  rm -f -- "$project/$FIXTURE_PROJECT_MARKER"
  if ( teardown_fixture ) >/dev/null 2>"$err"; then
    die "teardown accepted a non-marker project: $project"
  fi
  grep -q "missing $FIXTURE_PROJECT_MARKER" "$err" \
    || die "teardown refused for the wrong reason: $(cat "$err")"
  [ -d "$project" ] || die "teardown removed a non-marker project: $project"
  [ -d "$city" ] || die "teardown removed the city before refusing the project"
  : >"$project/$FIXTURE_PROJECT_MARKER"
  rm -f -- "$err"

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
    --self-test | self-test) self_test_fixture ;;
    --verify | verify) verify_fixture ;;
    print-isolation-vars) print_isolation_vars ;;
    help | --help | -h) usage ;;
    *) die "unknown command: $command (see --help)" ;;
  esac
}

main "$@"
