# Real gc payloads for dashboard v3 tests

Captured 2026-09-25 with gc 1.4.2 / bd 1.3.0 from the two live cities on
the dev host, **read-only commands only** (see `plans/dashboard-v3/design.md`
§8.1). Raw stdout, unedited, except where "trimmed" is noted. Both cities
were quiet at capture time: no in-progress beads, no active run, no
escalation/hold labels. Checked for secrets: none (only internal ids such
as `session_key`, `instance_token`).

File names: `<city>.<what>.<ext>`; `.json` = one JSON document, `.jsonl` =
one JSON object per line.

## Files

| File | Command (run in the city dir) | Notes |
|---|---|---|
| `{bright-lights,emacs-city}.status.json` | `gc status --json` | pretty-printed. `agents[]` = configured agents only (`name`, `qualified_name`, `scope` city/rig, `running`, `suspended`); the mayor is **not** in it. `summary.store_health` {path, size_bytes, live_rows, ratio_mb_per_row, warning, threshold_mb_per_row}. **No** `partial_errors`, no gc version, no uptime, no supervisor pid beyond `controller.pid`; `health` {usable, degraded} |
| `*.session-list.json` | `gc session list --json` | `{ok, schema_version, filters, sessions[], summary}` envelope. Session `id` is a bead id (`bl-rpq`, `ec-grfr`); `name`/`alias`/`agent_name` = qualified agent; `session_name` = tmux window name; `provider` only on provider sessions; `last_active` carries a local offset (`+02:00`) while `created_at` is `Z` |
| `*.agent-list.json` | `gc agent list --json` | `{agents[], city_name, city_path, ok, schema_version}`. Config-level: one row per template (`gc.requirements-planner`, `pi`, `mayor`, …), `pool` {min, max(-1 = unbounded)}, `dir` = rig, `scope`, `provider`, huge `work_query` shell string, `sling_query`. **No runtime state** (no running/session) — join with `session list` / `status` |
| `*.mail-inbox.json` | `gc mail inbox --json` | `{messages[], recipient:"human", recipients[]}`; message {id (a wisp bead id), from, to, subject, body, created_at, read, thread_id}. No identity flag |
| `*.mail-count.json` | `gc mail count --json` | `{total, unread, recipient, recipients}` |
| `bright-lights.mail-thread.json` | `gc mail thread thread-b1b8bd38a599 --json` | `{messages[], thread_id}`; every inbox thread was single-message at capture |
| `*.events-2h.jsonl` | `gc events --since 2h` | JSONL by default — **gc events has no `--json` flag**. Quiet window: ~95% `order.fired`/`order.completed`, rest `bead.created`/`bead.closed` of wisps |
| `emacs-city.events-24h-signal-sample.jsonl` | `gc events --since 24h`, **trimmed** to the first ≤6 per type (≤4 for rare types, 2 `bead.updated`) | covers `session.cold_start_timeout`, `session.stranded`, `session.stopped`/`woke`, `session.drain_acked_with_assigned_work`, `bead.dead_assignee_reopened`, `bead.claim_rejected`, `order.failed`, `dolt.compact.quarantine`, `mail.*`, `convoy.*`, `controller.started`, `mol-dog-*`. The untrimmed 24h stream was 13.6 MB / 15.5k lines (bead.updated payloads carry the whole bead) |
| `*.convoy-list.json` | `gc convoy list --json` | help says "JSONL" but it is **one** object `{convoys[], summary}`; convoy {id, title, status, progress {closed,total}, owned, fields, child_ids?} |
| `*.bd-list-open-inprogress.json` | `gc bd list --status in_progress,open --json` | city (HQ) store. Plain array. **Default limit 50** (`-n 0` = unlimited). Excludes wisps and ephemeral beads; includes `convoy` and `session` type beads |
| `emacs-city.bd-list-open-inprogress-{beads.el,gascity.el}.json` | `gc bd list --rig <rig> --status in_progress,open --json -n 0` | per-rig store |
| `*.bd-ready.json` | `gc bd ready --json` | what today's dashboard "Ready" uses: emacs-city = 73 rows, **71 are `ec-wisp-*` chores** (nudge/mail wisps) + 2 `session` beads (the mayor session bead `ec-grfr` shows up as "work") |
| `emacs-city.bd-list-all-beads.el-runs.json` | `gc bd list --rig beads.el --all --json -n 0`, **trimmed** to three run graphs | root + every bead with `metadata."gc.root_bead_id"` = root: `be-52m5` build-basic (closed, `gc.outcome` skipped, 37 step beads), `be-bn2` build-basic (fail, 45), `be-qrpg` do-work (pass, 6). 91 beads |
| `*.escalation-hold.json` | `gc bd list --label-regex '^(gc:escalation\|hold:.*)$' --json -n 0` | `[]` in both cities (flag works, nothing labelled) |
| `bright-lights.session-logs-mayor-tail10.json` | `gc session logs mayor --json --tail 10` | help says JSONL; it is **one** object `{entries[], entry_count, provider, tail, target, transcript_path}`; entry {uuid, parent_uuid, type user/assistant/tool_result, role, timestamp, text? , blocks?, message} |
| `bright-lights.session-peek-mayor.json` / `.txt` | `gc session peek mayor [--json] --lines 20` | JSON: one object `{output (string, pane text), lines, line_count, session_id, target}` |
| `*.rig-list.json` | `gc rig list --json` | HQ appears as a rig (`hq: true`, name = city name, path = city); `running`, `beads` state, `default_branch` only on git rigs. bright-lights adds `summary` |
| `*.rig-status-<rig>.json` | `gc rig status <rig> --json` | **rig name required** (no-arg form fails: `missing rig name`, exit 1 with `{ok:false,error:{code:"command_failed"}}` on stdout). {agents[] with runtime_session_name/status/draining, rig{…}} |
| `*.version.json` | `gc version --json` | `{version:"1.4.2", commit:"unknown", …}`; no bd/dolt versions (doctor has them: `bd:check-bd`, `dolt-version` messages) |
| `cities.json` | `gc cities --json` | `{cities[{name,path}], registry_path}` — same from either city |
| `bright-lights.doctor.json` | `gc doctor --json` (~40 s) | `{ok, passed, warned, failed, blocking_failed, fixed, results[]}`; result {name, status ok/warning/…, severity blocking/advisory, message, fix_hint?, details[]?} |

## Shape quirks implementers should know

- **Run graph metadata.** Step beads link to the run by
  `metadata."gc.root_bead_id"` (not by parent). Root: `gc.kind` =
  `workflow`, `gc.formula_name`, `gc.outcome` (pass/fail/skipped),
  `gc.build.*_path` plan files, `gc.graphv2_vars.v1` (JSON string).
  `gc.step_ref` forms seen:
  - top-level steps: exactly `<formula>.<step>` (`build-basic.prepare`,
    `build-basic.requirements`, `build-basic.implement`, …);
    their `gc.kind` is `ralph` (loop controller), `drain`, or absent;
  - control nodes: `gc.kind` `spec` (`build-basic.plan.spec`),
    `scope-check`, `workflow-finalize` (`build-basic.workflow-finalize`);
  - nested steps: `build-basic.review.setup-build-basic-review`,
    `build-basic.review.build-basic-review-loop` (3+ segments);
  - **iteration beads do not carry the formula prefix**:
    `requirements.iteration.1`, `review.iteration.1`,
    `review.build-basic-review-loop.iteration.1.review.acceptance-review`
    (`gc.kind` `scope` or absent).
  So "top-level" = `step_ref` with exactly two dot-segments whose first is
  the formula, minus spec/scope-check/workflow-finalize; this yields the
  10 steps of build-basic. An iteration bead points at its step bead with
  `gc.logical_bead_id` (be-bcb5 → be-fy7m `build-basic.requirements`),
  names it in `gc.control_for`/`gc.ralph_step_id` (`requirements`), and
  numbers itself in `gc.attempt`; the latest iteration = max `gc.attempt`.
  Every graph bead has a `tracks` dependency on the root; step order is
  given by `blocks` dependencies.
- **bd list vs bd ready noise.** `bd list --status open` already excludes
  wisps; `bd ready` does not (71/73 rows wisps in emacs-city). Both return
  `session` type beads (the mayor, control-dispatcher session beads) —
  filter `issue_type = session` (and `convoy`) out of "Work".
- **Default limit 50** on `gc bd list`; pass `-n 0` where counts matter.
- **Events.** Every line has `seq`, `type`, `ts`, `actor`, `ok`,
  `payload` (object, often `{}`); optional `subject`, `message`,
  `session_id`, `run_id`. `ts` mixes offsets (`+02:00` from the controller,
  `Z` from gc) — parse, don't string-compare. `bead.*` payloads carry the
  whole bead (`payload.bead`), `mail.sent` the whole message.
  `bead.dead_assignee_reopened.payload` = {bead_id, dead_assignee,
  routed_to}. `session.cold_start_timeout` has no session_id, only
  `subject` = tmux session name. Non-dotted-family types exist
  (`mol-dog-stale-db.scan`, `dolt.compact.quarantine`).
- **Single objects despite "JSONL" in help:** `convoy list`, `convoy
  status`, `session logs --json`, `session peek --json`, `cities`.
- **Status has no `partial_errors`** field in these captures (not even
  empty), and no store-health warning; don't depend on it existing.
- **Mayor** appears in `session list` and `agent list`, never in
  `status.agents`.
