#!/usr/bin/env bash
# gascity-fixture.sh --- deterministic Gas City seed data.
#
# Seeds one Gas City workspace (created by `fixture.sh --create') with a
# fixed, reproducible set of objects so the screenshot pipeline never reads a
# live store.  The demo *issues* come from the vendored canonical dataset
# (`fixtures/beads-fixture.jsonl`, demo-1 ... demo-12); this script adds only
# the deterministic role objects the dataset does not carry (sessions, mail, a
# run graph, orders, events, usage).  Every role id is documented and every
# timestamp is pinned, so two seed runs produce the same data.
#
# Usage:
#   gascity-fixture.sh --city <dir> [--rig <dir>]
#   gascity-fixture.sh --help
#
# The city directory is a Gas City workspace with a `demo-rig' rig (prefix
# `demo') registered; `--rig' is the shared demo project (the rig's source
# checkout, default `${TMPDIR:-/tmp}/demo-project').  Seeding is idempotent:
# re-importing updates the same records.
#
# Isolation: the four variables below can reroute `bd'/`gc' at the shared
# production store.  They are unset before every `bd'/`gc' call and hardcoded
# here because a POSIX shell cannot read beads.el's Lisp constant
# `beads-test-isolation-env-vars' (lisp/test/beads-integration-test.el).  Keep
# the two lists in sync; the WI-6 `:unit' test asserts the equality by reading
# both `fixture.sh print-isolation-vars' and
# `gascity-fixture.sh print-isolation-vars', so the process that actually runs
# `gc bd import' (this one) cannot drift from the tested list.  `gc' is always
# invoked with an explicit `--city' as well, so a leaked `GC_CITY' cannot
# redirect it either.

set -euo pipefail

readonly FIXTURE_PREFIX="demo"
readonly FIXTURE_RIG_NAME="demo-rig"
readonly FIXTURE_PROJECT_NAME="demo-project"

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
# The canonical demo dataset, vendored byte for byte from beads.el.  Resolved
# from this script's own directory so the seed works from any cwd (bd/gc may
# change directory before reading the file).
readonly FIXTURE_FILE="$SCRIPT_DIR/beads-fixture.jsonl"

# Pinned clock used for every seeded timestamp.  A fixed epoch (not "now")
# keeps two seed runs byte-identical.  The shared dataset keeps its own pinned
# timestamps (2025-01-01 ... 2025-01-06); role data starts at this epoch.
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
Usage: gascity-fixture.sh --city <city-dir> [--rig <demo-project>]

Seed a Gas City workspace created by `fixture.sh --create' with the shared
demo dataset (demo-1 ... demo-12), sessions, mail, a run graph, orders, and
pinned events.

  --city <dir>   Gas City workspace to seed (required).
  --rig <dir>    Shared demo project (the demo-rig checkout; default:
                 ${TMPDIR:-/tmp}/demo-project).
  print-isolation-vars
                 Print the hardcoded isolation variable names and exit.
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

# The drift-test seam: print the hardcoded list so the WI-6 `:unit' test can
# compare it to beads.el's `beads-test-isolation-env-vars' (see the comment at
# the top of this file).
print_isolation_vars() {
  printf '%s\n' "${ISOLATION_ENV_VARS[@]}"
}

# Run `gc' against the fixture city, never a leaked GC_CITY.
gc_fixture() {
  gc --city "$CITY" "$@"
}

# ---------------------------------------------------------------------------
# Beads
# ---------------------------------------------------------------------------

# Import the canonical demo dataset, then add the two work_dir joins the
# dataset does not carry.
seed_beads() {
  local jsonl="$CITY/.gc/fixture-beads.jsonl"
  [ -r "$FIXTURE_FILE" ] || die "vendored demo dataset not found: $FIXTURE_FILE"

  # `gc bd --rig <name>' answers from the rig's beads store; the ids carry the
  # rig prefix (`demo').  All chatter goes to stderr.
  gc_fixture bd --rig "$FIXTURE_RIG_NAME" import "$FIXTURE_FILE" --quiet 1>&2

  # The Agent Detail "Work" section joins a session to its work bead through
  # the bead's work_dir metadata, and the shared dataset has none.  Add it with
  # a metadata overlay generated from the vendored file (which is never
  # edited): `bd update' would stamp updated_at with the wall clock, and the
  # fixture must stay byte-reproducible, so the overlay re-imports the two
  # canonical records verbatim plus work_dir and their pinned timestamps.
  python3 - "$FIXTURE_FILE" "$jsonl" "$RIG" <<'PY'
import json
import sys

source, destination, work_dir = sys.argv[1:4]
targets = {"demo-3", "demo-4"}
with open(source, encoding="utf-8") as handle, \
        open(destination, "w", encoding="utf-8") as out:
    for line in handle:
        record = json.loads(line)
        if record.get("_type") == "issue" and record.get("id") in targets:
            metadata = dict(record.get("metadata") or {})
            metadata["work_dir"] = work_dir
            record["metadata"] = metadata
            out.write(json.dumps(record, separators=(",", ":")) + "\n")
PY
  gc_fixture bd --rig "$FIXTURE_RIG_NAME" import "$jsonl" --quiet \
    --allow-stale 1>&2
  rm -f -- "$jsonl"
}

# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------

# Two deterministic session rows.  `gc session list' reads the city (HQ) store
# (a `--rig' import lands in the rig store and stays invisible), and enriches
# each row with the runtime: with no controller running, gc reports the honest
# `asleep' state, which is what is pinned here and in `--verify'.  Never fake
# an active provider.
seed_sessions() {
  local jsonl="$CITY/.gc/fixture-sessions.jsonl"
  cat >"$jsonl" <<JSONL
{"_type":"issue","id":"demo-session-dev","title":"demo-3: Fix crash when opening an empty store","description":"Implementation session for demo-3, the in-progress demo bug.","status":"open","priority":2,"issue_type":"session","owner":"demo","created_by":"demo","created_at":"2025-01-05T10:00:00Z","updated_at":"2025-01-05T10:00:00Z","labels":["gc:session"],"metadata":{"work_dir":"$RIG","state":"asleep","session_name":"demo-agent","agent_name":"demo-rig/gc.implementation-worker","template":"demo-rig/gc.implementation-worker","provider":"claude"}}
{"_type":"issue","id":"demo-session-review","title":"demo-4: Write the Dolt migration guide","description":"Review session for demo-4, the blocked demo task.","status":"open","priority":2,"issue_type":"session","owner":"demo","created_by":"demo","created_at":"2025-01-05T11:00:00Z","updated_at":"2025-01-05T11:00:00Z","labels":["gc:session"],"metadata":{"work_dir":"$RIG","state":"asleep","session_name":"demo-reviewer","agent_name":"demo-rig/gc.reviewer","template":"demo-rig/gc.reviewer","provider":"claude"}}
JSONL

  gc_fixture bd import "$jsonl" --quiet 1>&2
  rm -f -- "$jsonl"
}

# ---------------------------------------------------------------------------
# Mail
# ---------------------------------------------------------------------------

# The shared dataset has no mail; this is the deterministic role message the
# Mail views and the run narrative refer to.  It names the two demo issues the
# run is built on: demo-10 (the epic) and demo-11 (its child).
seed_mail() {
  local jsonl="$CITY/.gc/fixture-mail.jsonl"
  cat >"$jsonl" <<'JSONL'
{"_type":"issue","id":"demo-mail-review","title":"Review demo-10 and demo-11","description":"Fixture mail: the demo-10 epic and its demo-11 child are ready for review.","status":"open","priority":2,"issue_type":"message","assignee":"human","owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","labels":["mail"],"comments":[{"author":"demo","text":"Second message in the thread: demo-11 is a child of demo-10, so review them together.","created_at":"2025-01-01T00:05:00Z"}]}
JSONL

  gc_fixture bd --rig "$FIXTURE_RIG_NAME" import "$jsonl" --quiet 1>&2
  rm -f -- "$jsonl"
}

# ---------------------------------------------------------------------------
# Run graph
# ---------------------------------------------------------------------------

# One deterministic `build-basic' workflow graph, so the Runs view and the run
# detail have real, reproducible data without a controller.  The root is
# `in-progress' (the Runs view's Active section has no age window; a closed run
# pinned to 2025 would be outside Failed's 24h window), eight anchors are done,
# and the review loop's first iteration is closed failed: the run detail's
# Review stage fails while the run is still active, which is exactly the
# ga-g092a state.  The run is built on the shared demo: demo-10 (the epic) and
# demo-11 (its child), so the run detail names the same issues as the manual.
# Every id is role-addressed (`demo-run', `demo-<role>' step ids) and every
# timestamp is pinned, so `capture.sh --verify' can assert the images are
# byte-identical.
seed_run_graph() {
  local jsonl="$CITY/.gc/fixture-run.jsonl"
  cat >"$jsonl" <<'JSONL'
{"_type":"issue","id":"demo-convoy","title":"input convoy for demo-10","status":"open","issue_type":"convoy","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","metadata":{"gc.synthetic":"true"},"dependencies":[{"issue_id":"demo-convoy","depends_on_id":"demo-10","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-impl-convoy","title":"implementation convoy for demo-run","status":"open","issue_type":"convoy","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","metadata":{"gc.synthetic":"true"},"dependencies":[{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-1","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-2","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-3","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-4","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-5","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-6","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-7","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"},{"issue_id":"demo-impl-convoy","depends_on_id":"demo-member-8","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-run","title":"build-basic on demo-10","description":"Deterministic fixture run for the Runs view and the run-detail screenshot.","status":"in_progress","issue_type":"task","assignee":"demo-rig/gc.run-operator","started_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:21:00Z","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"build-basic","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.var.convoy_id":"demo-convoy","gc.input_convoy_id":"demo-convoy","gc.build.implementation_convoy_id":"demo-impl-convoy","gc.graphv2_root_key":"graphv2-root:demo-convoy:build-basic:0000000000000000:default"}}
{"_type":"issue","id":"demo-prep","title":"Prepare worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:01:00Z","updated_at":"2025-01-01T00:02:00Z","close_reason":"worktree ready","closed_at":"2025-01-01T00:02:00Z","metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.prepare","gc.attempt":"1","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-reqs","title":"Requirements","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:02:00Z","updated_at":"2025-01-01T00:04:00Z","close_reason":"requirements approved","closed_at":"2025-01-01T00:04:00Z","dependencies":[{"issue_id":"demo-reqs","depends_on_id":"demo-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.requirements","gc.attempt":"1","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-plan","title":"Implementation plan","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:04:00Z","updated_at":"2025-01-01T00:06:00Z","close_reason":"plan approved","closed_at":"2025-01-01T00:06:00Z","dependencies":[{"issue_id":"demo-plan","depends_on_id":"demo-reqs","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.plan","gc.attempt":"1","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-plrv","title":"Plan review","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:06:00Z","updated_at":"2025-01-01T00:08:00Z","close_reason":"plan review approved","closed_at":"2025-01-01T00:08:00Z","dependencies":[{"issue_id":"demo-plrv","depends_on_id":"demo-plan","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.plan-review","gc.attempt":"1","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-dcmp","title":"Decompose into work items","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:08:00Z","updated_at":"2025-01-01T00:10:00Z","close_reason":"three work items created","closed_at":"2025-01-01T00:10:00Z","dependencies":[{"issue_id":"demo-dcmp","depends_on_id":"demo-plrv","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.decompose","gc.attempt":"1","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-impl","title":"Implement work items","status":"in_progress","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:14:00Z","dependencies":[{"issue_id":"demo-impl","depends_on_id":"demo-dcmp","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.implement","gc.attempt":"1"}}
{"_type":"issue","id":"demo-isms","title":"Implement same session","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:14:00Z","updated_at":"2025-01-01T00:15:00Z","close_reason":"filled the gaps from the same session","closed_at":"2025-01-01T00:15:00Z","dependencies":[{"issue_id":"demo-isms","depends_on_id":"demo-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.implement-same-session","gc.attempt":"1","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-sumi","title":"Summarize implementation","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:15:00Z","updated_at":"2025-01-01T00:16:00Z","close_reason":"implementation summary recorded","closed_at":"2025-01-01T00:16:00Z","dependencies":[{"issue_id":"demo-sumi","depends_on_id":"demo-isms","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.summarize-implementation","gc.attempt":"1","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-revw","title":"Review","status":"open","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:16:00Z","updated_at":"2025-01-01T00:20:00Z","dependencies":[{"issue_id":"demo-revw","depends_on_id":"demo-sumi","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.review","gc.attempt":"1","gc.work_beads":"demo-10,demo-11"},"description":"Review the work on demo-10 and demo-11."}
{"_type":"issue","id":"demo-finz","title":"Finalize","status":"open","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:16:00Z","updated_at":"2025-01-01T00:16:00Z","dependencies":[{"issue_id":"demo-finz","depends_on_id":"demo-revw","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.finalize","gc.attempt":"1"}}
{"_type":"issue","id":"demo-publ","title":"Publish","status":"open","issue_type":"task","assignee":"demo-rig/gc.run-operator","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:16:00Z","updated_at":"2025-01-01T00:16:00Z","dependencies":[{"issue_id":"demo-publ","depends_on_id":"demo-finz","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}],"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"step","gc.step_ref":"build-basic.publish","gc.attempt":"1"}}
{"_type":"issue","id":"demo-rev1","title":"Review iteration 1","status":"closed","issue_type":"task","assignee":"demo-rig/gc.reviewer","created_at":"2025-01-01T00:16:00Z","updated_at":"2025-01-01T00:20:00Z","closed_at":"2025-01-01T00:20:00Z","close_reason":"two blocking findings: the render path stats a file and the header is not frozen","owner":"demo","created_by":"demo","priority":2,"metadata":{"gc.root_bead_id":"demo-run","gc.kind":"ralph","gc.step_ref":"review.iteration.1","gc.logical_bead_id":"demo-revw","gc.outcome":"fail","gc.failure_class":"code_review","gc.attempt":"1"},"dependencies":[{"issue_id":"demo-rev1","depends_on_id":"demo-revw","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-biz-1","title":"Retarget the demo fixture to the shared contract","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-1","gc.drain_member_id":"demo-biz-1","gc.drain_control_id":"demo-impl","gc.drain_index":"0","gc.drain_count":"8","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"work unit shipped"}
{"_type":"issue","id":"demo-biz-2","title":"Remove third-party themes from the capture path","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-2","gc.drain_member_id":"demo-biz-2","gc.drain_control_id":"demo-impl","gc.drain_index":"1","gc.drain_count":"8","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"work unit shipped"}
{"_type":"issue","id":"demo-biz-3","title":"Complete the warning-free Texinfo structure","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-3","gc.drain_member_id":"demo-biz-3","gc.drain_control_id":"demo-impl","gc.drain_index":"2","gc.drain_count":"8","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"work unit shipped"}
{"_type":"issue","id":"demo-biz-4","title":"Regenerate and verify every screenshot","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-4","gc.drain_member_id":"demo-biz-4","gc.drain_control_id":"demo-impl","gc.drain_index":"3","gc.drain_count":"8","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"work unit shipped"}
{"_type":"issue","id":"demo-biz-5","title":"Complete reference and keybinding coverage","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-5","gc.drain_member_id":"demo-biz-5","gc.drain_control_id":"demo-impl","gc.drain_index":"4","gc.drain_count":"8","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"work unit shipped"}
{"_type":"issue","id":"demo-biz-6","title":"Write the shared walkthrough and Tested-with section","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-6","gc.drain_member_id":"demo-biz-6","gc.drain_control_id":"demo-impl","gc.drain_index":"5","gc.drain_count":"8","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"work unit shipped"}
{"_type":"issue","id":"demo-biz-7","title":"Run the black-box QA pass and commit the report","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-7","gc.drain_member_id":"demo-biz-7","gc.drain_control_id":"demo-impl","gc.drain_index":"6","gc.drain_count":"8","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"work unit shipped"}
{"_type":"issue","id":"demo-biz-8","title":"Pin the new manual contracts in tests and land green gates","status":"open","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-8","gc.drain_member_id":"demo-biz-8","gc.drain_control_id":"demo-impl","gc.drain_index":"7","gc.drain_count":"8"}}
{"_type":"issue","id":"demo-member-1","title":"do-work demo-biz-1","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-1","gc.drain_index":"0","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"item source anchor closed"}
{"_type":"issue","id":"demo-member-1-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-1","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-1-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-1","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-1-impl","depends_on_id":"demo-member-1-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-1-close","title":"Close owned source anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-1","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"source anchor closed","dependencies":[{"issue_id":"demo-member-1-close","depends_on_id":"demo-member-1-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-2","title":"do-work demo-biz-2","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-2","gc.drain_index":"1","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-2","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"item source anchor closed"}
{"_type":"issue","id":"demo-member-2-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-2","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-2-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-2","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-2-impl","depends_on_id":"demo-member-2-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-2-close","title":"Close owned source anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-2","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"source anchor closed","dependencies":[{"issue_id":"demo-member-2-close","depends_on_id":"demo-member-2-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-3","title":"do-work demo-biz-3","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-3","gc.drain_index":"2","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-3","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"item source anchor closed"}
{"_type":"issue","id":"demo-member-3-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-3","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-3-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-3","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-3-impl","depends_on_id":"demo-member-3-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-3-close","title":"Close owned source anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-3","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"source anchor closed","dependencies":[{"issue_id":"demo-member-3-close","depends_on_id":"demo-member-3-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-4","title":"do-work demo-biz-4","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-4","gc.drain_index":"3","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-4","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"item source anchor closed"}
{"_type":"issue","id":"demo-member-4-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-4","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-4-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-4","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-4-impl","depends_on_id":"demo-member-4-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-4-close","title":"Close owned source anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-4","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"source anchor closed","dependencies":[{"issue_id":"demo-member-4-close","depends_on_id":"demo-member-4-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-5","title":"do-work demo-biz-5","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-5","gc.drain_index":"4","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-5","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"item source anchor closed"}
{"_type":"issue","id":"demo-member-5-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-5","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-5-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-5","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-5-impl","depends_on_id":"demo-member-5-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-5-close","title":"Close owned source anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-5","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"source anchor closed","dependencies":[{"issue_id":"demo-member-5-close","depends_on_id":"demo-member-5-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-6","title":"do-work demo-biz-6","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-6","gc.drain_index":"5","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-6","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"item source anchor closed"}
{"_type":"issue","id":"demo-member-6-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-6","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-6-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-6","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-6-impl","depends_on_id":"demo-member-6-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-6-close","title":"Close owned source anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-6","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"source anchor closed","dependencies":[{"issue_id":"demo-member-6-close","depends_on_id":"demo-member-6-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-7","title":"do-work demo-biz-7","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-7","gc.drain_index":"6","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-7","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"item source anchor closed"}
{"_type":"issue","id":"demo-member-7-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-7","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-7-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-7","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-7-impl","depends_on_id":"demo-member-7-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-7-close","title":"Close owned source anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-7","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:20:00Z","close_reason":"source anchor closed","dependencies":[{"issue_id":"demo-member-7-close","depends_on_id":"demo-member-7-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-8","title":"do-work demo-biz-8","status":"in_progress","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.drain_control_id":"demo-impl","gc.drain_member_id":"demo-biz-8","gc.drain_index":"7","gc.drain_count":"8","gc.drain_member_access":"exclusive","gc.var.issue":"demo-biz-8"}}
{"_type":"issue","id":"demo-member-8-prep","title":"Prepare item worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:11:00Z","metadata":{"gc.root_bead_id":"demo-member-8","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:11:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-member-8-impl","title":"Implement owned work","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:11:00Z","updated_at":"2025-01-01T00:18:00Z","metadata":{"gc.root_bead_id":"demo-member-8","gc.kind":"step","gc.step_ref":"do-work.implement","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:18:00Z","close_reason":"implementation landed","dependencies":[{"issue_id":"demo-member-8-impl","depends_on_id":"demo-member-8-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-member-8-close","title":"Close owned source anchor","status":"open","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:18:00Z","updated_at":"2025-01-01T00:20:00Z","metadata":{"gc.root_bead_id":"demo-member-8","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.attempt":"1"},"dependencies":[{"issue_id":"demo-member-8-close","depends_on_id":"demo-member-8-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-flat-convoy","title":"input convoy for demo-flat-src","status":"closed","issue_type":"convoy","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z","metadata":{"gc.synthetic":"true"},"dependencies":[{"issue_id":"demo-flat-convoy","depends_on_id":"demo-flat-src","type":"tracks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-flat-src","title":"drain unit 6 for demo-flat-src","status":"closed","issue_type":"task","priority":2,"owner":"demo","created_by":"demo","created_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:00:00Z"}
{"_type":"issue","id":"demo-flat","title":"do-work on demo-flat-src","status":"closed","issue_type":"task","assignee":"demo-rig/gc.workflow-finalize","closed_at":"2025-01-01T00:22:00Z","updated_at":"2025-01-01T00:22:00Z","created_at":"2025-01-01T00:00:00Z","owner":"demo","created_by":"demo","priority":2,"close_reason":"drain item failed: close-source-anchor failed","metadata":{"gc.kind":"workflow","gc.formula_name":"do-work","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.var.convoy_id":"demo-flat-convoy","gc.input_convoy_id":"demo-flat-convoy","gc.var.issue":"demo-flat-src","gc.outcome":"fail","gc.drain_control_id":"demo-flat-drain","gc.drain_member_id":"demo-flat-src","gc.drain_index":"6","gc.drain_count":"7"}}
{"_type":"issue","id":"demo-flat-prep","title":"prepare-worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:01:00Z","updated_at":"2025-01-01T00:02:00Z","metadata":{"gc.root_bead_id":"demo-flat","gc.kind":"step","gc.step_ref":"do-work.prepare-worktree","gc.outcome":"pass","gc.attempt":"1"},"closed_at":"2025-01-01T00:02:00Z","close_reason":"worktree ready"}
{"_type":"issue","id":"demo-flat-impl","title":"implement","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:02:00Z","updated_at":"2025-01-01T00:10:00Z","metadata":{"gc.root_bead_id":"demo-flat","gc.kind":"ralph","gc.step_ref":"do-work.implement","gc.outcome":"skipped","gc.attempt":"1"},"closed_at":"2025-01-01T00:10:00Z","close_reason":"iteration failed","dependencies":[{"issue_id":"demo-flat-impl","depends_on_id":"demo-flat-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-flat-close","title":"close-source-anchor","status":"closed","issue_type":"task","assignee":"demo-rig/gc.implementation-worker","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:10:00Z","updated_at":"2025-01-01T00:12:00Z","metadata":{"gc.root_bead_id":"demo-flat","gc.kind":"step","gc.step_ref":"do-work.close-source-anchor","gc.outcome":"fail","gc.attempt":"1"},"closed_at":"2025-01-01T00:12:00Z","close_reason":"the owned source anchor has no implementation commit","dependencies":[{"issue_id":"demo-flat-close","depends_on_id":"demo-flat-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-flat-iter1","title":"implement iteration 1","status":"closed","issue_type":"task","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:02:00Z","updated_at":"2025-01-01T00:10:00Z","closed_at":"2025-01-01T00:10:00Z","close_reason":"verification failed: no worktree change","metadata":{"gc.root_bead_id":"demo-flat","gc.kind":"ralph","gc.step_ref":"implement.iteration.1","gc.logical_bead_id":"demo-flat-impl","gc.outcome":"fail","gc.failure_class":"verification","gc.attempt":"1"},"dependencies":[{"issue_id":"demo-flat-iter1","depends_on_id":"demo-flat-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-std","title":"review demo-report","status":"closed","issue_type":"task","assignee":"demo-rig/gc.reviewer","closed_at":"2025-01-02T00:00:00Z","updated_at":"2025-01-02T00:00:00Z","created_at":"2025-01-01T00:00:00Z","owner":"demo","created_by":"demo","priority":2,"close_reason":"review report approved","metadata":{"gc.kind":"workflow","gc.formula_name":"review","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig","gc.outcome":"pass"}}
{"_type":"issue","id":"demo-std-ctx","title":"validate report context","status":"closed","issue_type":"task","assignee":"demo-rig/gc.reviewer","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:01:00Z","updated_at":"2025-01-01T00:02:00Z","metadata":{"gc.root_bead_id":"demo-std","gc.kind":"step","gc.step_ref":"review.validate-context","gc.outcome":"pass","gc.attempt":"1"},"closed_at":"2025-01-01T00:02:00Z","close_reason":"context valid"}
{"_type":"issue","id":"demo-std-report","title":"write review report","status":"closed","issue_type":"task","assignee":"demo-rig/gc.reviewer","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:02:00Z","updated_at":"2025-01-01T00:03:00Z","metadata":{"gc.root_bead_id":"demo-std","gc.kind":"ralph","gc.step_ref":"review.write-report","gc.outcome":"pass","gc.attempt":"1"},"closed_at":"2025-01-01T00:03:00Z","close_reason":"report written","dependencies":[{"issue_id":"demo-std-report","depends_on_id":"demo-std-ctx","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-std-finz","title":"Finalize workflow","status":"closed","issue_type":"task","assignee":"demo-rig/gc.reviewer","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:03:00Z","updated_at":"2025-01-01T00:04:00Z","metadata":{"gc.root_bead_id":"demo-std","gc.kind":"workflow-finalize","gc.step_ref":"review.workflow-finalize","gc.outcome":"pass","gc.attempt":"1"},"closed_at":"2025-01-01T00:04:00Z","close_reason":"workflow finalized","dependencies":[{"issue_id":"demo-std-finz","depends_on_id":"demo-std-report","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-std-iter1","title":"write-review-report iteration 1","status":"closed","issue_type":"task","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:02:00Z","updated_at":"2025-01-01T00:03:00Z","closed_at":"2025-01-01T00:03:00Z","close_reason":"report approved","metadata":{"gc.root_bead_id":"demo-std","gc.kind":"ralph","gc.step_ref":"write-report.iteration.1","gc.logical_bead_id":"demo-std-report","gc.outcome":"pass","gc.attempt":"1"},"dependencies":[{"issue_id":"demo-std-iter1","depends_on_id":"demo-std-report","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-inline","title":"build-basic with an inline drain","status":"in_progress","issue_type":"task","assignee":"demo-rig/gc.run-operator","started_at":"2025-01-01T00:00:00Z","updated_at":"2025-01-01T00:06:00Z","created_at":"2025-01-01T00:00:00Z","owner":"demo","created_by":"demo","priority":2,"metadata":{"gc.kind":"workflow","gc.formula_name":"build-basic","gc.formula_contract":"graph.v2","gc.root_store_ref":"rig:demo-rig","gc.var.rig_name":"demo-rig"}}
{"_type":"issue","id":"demo-inline-prep","title":"Prepare worktree","status":"closed","issue_type":"task","assignee":"demo-rig/gc.run-operator","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:01:00Z","updated_at":"2025-01-01T00:02:00Z","metadata":{"gc.root_bead_id":"demo-inline","gc.kind":"step","gc.step_ref":"build-basic.prepare","gc.attempt":"1","gc.outcome":"pass"},"closed_at":"2025-01-01T00:02:00Z","close_reason":"done"}
{"_type":"issue","id":"demo-inline-impl","title":"Implement work items","status":"in_progress","issue_type":"task","assignee":"demo-rig/gc.run-operator","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:02:00Z","updated_at":"2025-01-01T00:06:00Z","metadata":{"gc.root_bead_id":"demo-inline","gc.kind":"drain","gc.step_ref":"build-basic.implement","gc.attempt":"1","gc.drain_count":"8"},"dependencies":[{"issue_id":"demo-inline-impl","depends_on_id":"demo-inline-prep","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-inline-sumi","title":"Summarize implementation","status":"open","issue_type":"task","assignee":"demo-rig/gc.run-operator","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:06:00Z","updated_at":"2025-01-01T00:06:00Z","metadata":{"gc.root_bead_id":"demo-inline","gc.kind":"step","gc.step_ref":"build-basic.summarize-implementation","gc.attempt":"1"},"dependencies":[{"issue_id":"demo-inline-sumi","depends_on_id":"demo-inline-impl","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
{"_type":"issue","id":"demo-inline-finz","title":"Finalize","status":"open","issue_type":"task","assignee":"demo-rig/gc.run-operator","owner":"demo","created_by":"demo","priority":2,"created_at":"2025-01-01T00:06:00Z","updated_at":"2025-01-01T00:06:00Z","metadata":{"gc.root_bead_id":"demo-inline","gc.kind":"step","gc.step_ref":"build-basic.finalize","gc.attempt":"1"},"dependencies":[{"issue_id":"demo-inline-finz","depends_on_id":"demo-inline-sumi","type":"blocks","created_at":"2025-01-01T00:00:00Z","created_by":"demo","metadata":"{}"}]}
JSONL

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
# Usage facts
# ---------------------------------------------------------------------------

# The `costs' view reads the city's local usage sink `.gc/usage.jsonl'
# (`gc costs').  Two pinned compute facts give the view real rows: fixed
# run ids (`demo-run-*'), fixed wall-seconds and a fixed epoch.  No token
# pricing is invented, so gc reports the wall-seconds it can price and the
# rest as unpriced, exactly as it would for a real city.
seed_usage() {
  cat >"$CITY/.gc/usage.jsonl" <<'JSONL'
{"run_id":"demo-run-build","session_id":"demo-run-build","worker":"demo-rig/gc.implementation-worker","city":"gascity-fixture","kind":"compute","wall_seconds":42.5,"upstream_req_id":"demo-run-build:2025-01-01T00:00:00Z","at":1735689600000,"idempotency_key":"demo-run-build"}
{"run_id":"demo-run-review","session_id":"demo-run-review","worker":"demo-rig/gc.reviewer","city":"gascity-fixture","kind":"compute","wall_seconds":17.25,"upstream_req_id":"demo-run-review:2025-01-01T00:00:01Z","at":1735689601000,"idempotency_key":"demo-run-review"}
JSONL
}

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

# The event log is the city's .gc/events.jsonl; `gc events' reads it without a
# running controller.  Every line pins seq, ts, actor, subject, and message so
# the events view renders the same data on every run.  Subjects are the shared
# demo ids the seeded roles own.
seed_events() {
  cat >"$CITY/.gc/events.jsonl" <<'JSONL'
{"seq":1,"type":"city.created","ts":"2025-01-01T00:00:00Z","actor":"demo","subject":"demo-rig","message":"Fixture city created"}
{"seq":2,"type":"bead.created","ts":"2025-01-01T00:00:01Z","actor":"demo","subject":"demo-3","message":"Shared demo issue demo-3 created"}
{"seq":3,"type":"bead.updated","ts":"2025-01-01T00:00:02Z","actor":"demo","subject":"demo-3","message":"Shared demo issue demo-3 moved to in_progress"}
{"seq":4,"type":"mail.sent","ts":"2025-01-01T00:00:03Z","actor":"demo","subject":"demo-mail-review","message":"Fixture mail demo-mail-review sent"}
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
      print-isolation-vars) print_isolation_vars; exit 0 ;;
      help | --help | -h) usage; exit 0 ;;
      *) die "unknown argument: $1 (see --help)" ;;
    esac
  done

  [ -n "$CITY" ] || die "--city is required"
  [ -d "$CITY" ] || die "city directory does not exist: $CITY"
  [ -f "$CITY/city.toml" ] || die "not a Gas City workspace: $CITY"
  [ -n "$RIG" ] || RIG="${TMPDIR:-/tmp}/$FIXTURE_PROJECT_NAME"
  [ -d "$RIG" ] || die "demo project does not exist: $RIG"

  require_tool gc
  require_tool python3

  seed_beads
  seed_sessions
  seed_mail
  seed_run_graph
  seed_orders
  seed_events
  seed_usage
  printf 'gascity-fixture.sh: seeded the shared demo and role data for %s (project %s) at %s\n' \
    "$FIXTURE_RIG_NAME" "$RIG" "$CITY" >&2
}

main "$@"
