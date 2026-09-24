---
schema: gc.build.requirements.v1
workflow:
  id: ga-uxhh
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: requirements
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-7pq7
      hash: bead:ga-7pq7
      ids:
        - ga-7pq7
    - path: lisp/gascity-dashboard.el
      hash: git:5ae47af99a60b29267eab5d4a034248a44922371
  coverage:
    - id: ga-7pq7
      status: covered
---

# Requirements — Dashboard v2 (runs, honest needs-you, activity, mail)

## Problem Statement

The vui city dashboard (`lisp/gascity-dashboard.el`, landed on `main` at
`bbd6091..5ae47af`) shows sessions and basic city state, but it cannot answer
the questions a mayor actually asks at a glance: *what workflow runs are in
flight and where are they stuck?* The Go web dashboard answers this from the
supervisor REST API, but for gascity.el the user has directed that the data
plane is the `gc` CLI only — no HTTP calls anywhere. Today the CLI can supply
most of this surface (`gc bd list/show --json`, `gc convoy list/status --json`,
`gc events --json` JSONL, `gc mail count --json`), and two surfaces it cannot
supply (pending interactions, costs) must be represented honestly — as
removed dead code and a dim pointer, never as fake data.

This workflow builds **Dashboard v2**: feature parity with the Go dashboard's
run/activity/cost surfaces where the `gc` CLI allows it, honest limitation
markers where it does not, and zero supervisor API contact.

## W6H

- **Who** — the city mayor (user) driving gascity.el from Emacs, locally and
  over TRAMP (`/ssh:localhost:/home/roman/bright-lights`).
- **What** — a runs view (workflow runs + step graphs + input convoys), an
  activity feed from `gc events` JSONL, a mail-unread header, an honest
  needs-you selector, and a costs dim pointer — all inside the existing vui
  dashboard.
- **When** — every dashboard load and refresh; async, stale-while-revalidate
  per existing conventions.
- **Where** — `lisp/gascity-dashboard.el` (and its tests in
  `lisp/test/gascity-test.el`); no other data source but `gc`/`bd` CLI JSON.
- **Why** — without a runs view, formula-v2 workflows (the dominant work unit)
  are invisible in Emacs; and the current `awaiting-input` reason is
  dishonest dead code (pending is hardcoded `nil` and can never fire).
- **How** — extend the existing async-first vui architecture: one independent
  async read per new section through `gascity-reader-read-async` /
  `vui-use-async`, JSONL decode for events, client-side grouping of decoded
  rows. Magit-grade inline error surfacing, never a blank pane.

## User Stories

- As a mayor, when I open the city dashboard I see a **Runs** section
  (replacing/extending "Work in flight") listing open workflow runs with: run
  id, formula name, phase (root bead status), progress (closed/total steps),
  current step (non-closed steps with an active assignee), and updated time.
- As a mayor, I press `RET` on a run row and drill into a **run-detail**
  rendering of the step graph: step id, title, kind, status, assignee.
- As a mayor, I see the input convoys feeding each run (from
  `gc convoy list --json`, joined on `gc.input_convoy_id`).
- As a mayor, I see a recent **Activity** section with the last N events
  (ts, type, subject, first-line summary) from `gc events --since <window>`
  JSONL, with chatty types (`order.fired`, `order.completed`, `bead.updated`)
  excluded by default and a state-variable filter to change that.
- As a mayor, I see a cockpit header line "mail N unread" from
  `gc mail count --json`, with a key (`m`) opening the existing mail reader.
- As a mayor, I never see a "respond"/needs-you reason the dashboard cannot
  actually detect; the reasons shown (`errored`, `rate-limited`, `stalled`)
  are all derivable from `gc status` + `gc session list --json`.
- As a mayor, for costs I see a dim pointer row in the cockpit ("costs — run
  `gc costs` in a shell; no JSON surface") instead of an empty or fake panel.

## Technical Stories

- **Workflow-run discovery.** A workflow run is a bead whose metadata carries
  `gc.graphv2_root_key` (plus `gc.formula_name`,
  `gc.formula_contract: graph.v2`); step beads carry the same root key and
  `gc.input_convoy_id`. Discovery reads the full `gc bd list --json` payload
  and filters client-side (stores are small); `bd query` cannot filter on
  metadata fields, so `bd sql` is only a fallback, wrapped via
  `gc bd … --json`.
- **Progress computation.** Per-run progress = closed/total step count from
  the step graph (`gc bd show <root> --json` TRACKS/TRACKED BY relationships
  or the step beads sharing the root key); `gc convoy list --json` progress
  `{closed,total}` and `gc convoy status <id>` tracked-bead tables feed the
  current-step column.
- **Events JSONL.** Parse `gc events --since <window>` as JSON Lines (one DTO
  per line: `actor`, `payload`, `run_id`, `seq`, `subject`, `ts`, `type`)
  through the reader's async JSONL plumbing (same path as peek). A decode
  error renders a dim inline line, never a blank section.
- **Honest needs-you.** Delete the `awaiting-input` selector arm and its
  prompt rendering; keep `errored`/`rate-limited`/`stalled` (all derivable).
  Comment + doc note: "Pending interactions need the supervisor API; out of
  scope by user directive." No fake data, no dead code paths.
- **Transcript.** No transcript pane. Verify the existing `t` (tmux attach)
  path works for live sessions from the dashboard via the gascity-session
  plumbing; regression-test it.
- **Costs gap.** `gc costs --json` returns `json_unsupported`; `gc usage`
  does not exist. No JSON surface ⇒ no panel. Add a dim pointer row and file
  a bead requesting the CLI capability (do not implement it here).
- **Test coverage.** Add ERT fixtures for the new selectors: runs grouping
  (root-key grouping, progress fraction, current step), events JSONL decode,
  mail-count integration. Keep the whole `scripts/gate.sh` gate green
  (currently 380+ tests).

## Behavior Requirements

- Every new read goes through `gascity-reader`'s async plumbing
  (`vui-use-async` / `gascity-reader-read-async`), with per-section
  independent loads: one section's failure must never blank the others.
- No synchronous `gc` in render paths (including eldoc/prefix paths — use
  `gascity-rigs-cached`-style memos where needed).
- Zero HTTP: grep the new code for `url` / `http` and find nothing that calls
  the supervisor API.
- TRAMP correctness: identical behavior on
  `/ssh:localhost:/home/roman/bright-lights` — buffer keying, host-qualified
  names, and PATH resolution via `gascity-remote` all keep working.
- Stale-while-revalidate: a pending reload keeps rendering the last payload;
  a pending state with nil data renders a loading line, not an unmount.
- Activity feed noise control: the chatty-type exclusion is a state variable
  (user-filterable), applied before render.
- Section failure renders a dim inline error line; JSONL decode errors ditto.
- The dashboard footer legend is updated for all new keys/sections.

## Coverage Matrix

| ID | Status |
| --- | --- |
| ga-7pq7 | covered |

## Example Mapping

| Example | Given | When | Then |
|---|---|---|---|
| Runs listed | 3 open workflow roots, 1 closed | dashboard loads | Runs section shows 3 rows with progress fractions; closed run absent (or clearly marked closed) |
| Run detail | run root with 37 steps, 12 closed | `RET` on the row | Step graph shows all 37 steps with per-step status/assignee; progress shows 12/37 |
| Convoy join | run root carries `gc.input_convoy_id` | run detail renders | Input convoy row appears joined from `gc convoy list --json` |
| Events window | 944 `order.fired` + 1195 `bead.updated` events in 2h | feed renders | Chatty types hidden by default; a smaller mixed sample renders with ts/type/subject/summary |
| Events decode error | one malformed line in JSONL | feed renders | Dim inline error line; other events still render |
| Mail unread | 4 unread, 9 total | dashboard loads | Header shows "mail 4 unread"; `m` opens mail reader |
| Needs-you honesty | `gc session list --json` has no pending field | session errors | `awaiting-input` never appears; `errored` fires from derivable state |
| Costs gap | `gc costs --json` unsupported | cockpit renders | Dim pointer row visible; a capability-request bead exists |
| Remote parity | dashboard opened over TRAMP | all sections load | Same data as local city; no TRAMP sync stalls |

## Acceptance Criteria

1. Runs section renders open workflow runs grouped by `gc.graphv2_root_key`
   with columns: run id, formula name, phase, progress (closed/total), current
   step, updated. Verified against a live city (`emacs-city`) with at least
   one real formula-v2 run.
2. `RET` on a run row opens a run-detail rendering of the full step graph
   (step id, title, kind, status, assignee) plus the input convoy row.
3. Activity section renders the last N events from `gc events --since`
   JSONL with ts/type/subject/summary columns and a state-variable type
   filter that excludes `order.fired`/`order.completed`/`bead.updated` by
   default.
4. Cockpit header shows mail unread count from `gc mail count --json`;
   `m` opens the existing mail reader.
5. No `awaiting-input` code path remains; `errored`/`rate-limited`/`stalled`
   still fire from derivable state; a code comment and doc note state the
   supervisor-API limitation.
6. A costs dim pointer row is rendered, and a capability-request bead for a
   costs JSON surface is filed (not implemented).
7. The transcript surface remains tmux-only (`t` attach works for live
   sessions from the dashboard; regression-tested).
8. `grep -in "url\|http"` over changed code returns no supervisor API usage;
   all reads flow through gascity-reader async plumbing; no synchronous gc in
   render paths.
9. The feature works identically on `/ssh:localhost:/home/roman/bright-lights`
   (status dashboard, runs, activity, mail).
10. `scripts/gate.sh` passes: whole-package byte-compile with
    `--warnings-as-errors` and the full ERT suite, including new ERT for runs
    grouping, events JSONL decode, and mail-count integration with fixture
    payloads.
11. Footer legend documents the new keys/sections.
12. A short delivery report lists: sections added, exact CLI recipes used,
    and the two documented CLI gaps (pending, costs) with their dim-pointer
    treatment.

## Out Of Scope

- Any supervisor HTTP API call (REST `/runs`, `/session/{id}/pending`,
  readiness/waits) — user directive.
- Usage/cost panels from CLI data (`gc costs --json` is
  json_unsupported; `gc usage` does not exist) — dim pointer only.
- A transcript pane (tmux attach is the answer).
- Implementing the missing CLI capabilities (file a request bead instead).
- Changes to the Go web dashboard repo (`~/workspace/gascity` is READ-ONLY
  for this workflow).
- Upstream PRs; work lands as local commits on `main`.

## Open Questions

- Exact default event window (`--since`) and N (event count cap): proposed
  last ~500 events / 2h window, tuned during implementation; filter state is
  user-adjustable so this is not blocking.
- Whether the Runs section fully replaces "Work in flight" or extends it
  alongside non-formula work rows: implementer to pick based on visual
  density, guided by "replace/extend" latitude in the target bead.
- Whether closed runs should be listed dimly or omitted: proposed omit with a
  dim marker when the root is still open but steps are closed; final choice
  deferred to plan review.
