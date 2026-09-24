---
schema: gc.build.decomposition.v1
workflow:
  id: ga-uxhh
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: decompose
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/dashboard-v2/requirements.md
      hash: sha256:912141fa0e63c3d5615b7131e0bcb54e832776f594f7778afd17632217259a07
      ids:
        - ga-7pq7
    - path: plans/dashboard-v2/implementation-plan.md
      hash: sha256:1bfc7e2197246d56c347e345290144c9721a520a915a9115fd6b95cb50e4bd9f
    - path: lisp/gascity-dashboard.el
      hash: git:5ae47af99a60b29267eab5d4a034248a44922371
  coverage:
    - id: ga-7pq7
      status: covered
      rationale: >-
        All five work items (S1-S5) together cover every acceptance criterion
        of the Dashboard v2 target bead ga-7pq7; per-criterion mapping is
        recorded in the Work Items section.
---

# Decomposition — Dashboard v2 (runs, honest needs-you, activity, mail)

## Summary

The approved requirements (plans/dashboard-v2/requirements.md) and
implementation plan (plans/dashboard-v2/implementation-plan.md) are decomposed
into five work-item beads, one per plan step S1–S5, tracked by the new
implementation convoy `ga-up47` (`dashboard-v2-impl`):

- `ga-89p2` — S1 Runs section (list + selectors)
- `ga-xmh3` — S2 Run detail (step graph + input convoy)
- `ga-30zs` — S3 Activity feed (events JSONL)
- `ga-refs` — S4 Mail header, honest needs-you, costs pointer
- `ga-gmbh` — S5 Verification, e2e, capability bead, delivery report

S1–S4 are independently mergeable behind a green `scripts/gate.sh`; S5 closes
with the interactive e2e acceptance gate over TRAMP and the delivery report.
Each work item's description carries the plan section it implements, the ERT
fixtures required, and its gate; acceptance criteria are verified once, at S5,
against the live city. Traceability: every work item cites its acceptance
criteria from requirements.md and the target bead `ga-7pq7`; the plan steps
(S1–S5) are the plan-section traceability anchors.

## Selected Downstream Formulas

| Formula | Stage consumer | Work items |
| --- | --- | --- |
| `implement` | drains convoy `ga-up47` work items via `do-work-item` | ga-89p2, ga-xmh3, ga-30zs, ga-refs, ga-gmbh |

The `implement` formula (implementation stage of `build-basic`) drains the
implementation convoy; `review` and `publish` stages consume its output. No
other downstream formulas are selected; decomposition, planning, and review-fix
formulas are upstream or self, not selected downstream.

## Implementation Convoy

- Convoy id: `ga-up47`
- Title: `dashboard-v2-impl`
- Tracked work items: `ga-89p2`, `ga-xmh3`, `ga-30zs`, `ga-refs`, `ga-gmbh`
- Status: open, progress 0/5 closed
- Created with `gc convoy create dashboard-v2-impl ga-89p2 ga-xmh3 ga-30zs ga-refs ga-gmbh --json` after the work-item beads existed; verified via `gc convoy list --json` (`child_ids` match). The source/launch convoy `ga-qcci` (from `gc.var.convoy_id`) is **not** reused.
- The `implement` formula drains this convoy; downstream stage consumers read it from the workflow root bead metadata `gc.input_convoy_id` / `gc.build.implementation_convoy_id`.

## Work Items

Each bead was created with `gc bd create ... --json` with the workflow-root
metadata (`gc.root_bead_id=ga-uxhh`, `gc.formula_name=build-basic`,
`gc.formula_contract=graph.v2`) attached. The full descriptions live on the
beads; summaries with traceability:

### ga-89p2 — S1 Runs section (list + selectors)

Implements plan §S1. One async `bd list` read; pure selector
`gascity-dashboard--workflow-runs` groups beads by `gc.graphv2_root_key`
(root vs step discrimination: `gc.kind == "workflow"` preferred, fall back to
lacking `gc.ralph_step_id`); run rows: run id, formula, phase, progress
closed/total, current step, updated; Runs section added above Work in flight;
run rows stamped with the root bead id for the S2 `RET` drill-in; closed runs
excluded from the default view with a dim "N closed runs" line. ERT fixtures:
root-vs-step discrimination, grouping, progress fraction, current-step pick,
closed-run exclusion. Gate: `scripts/gate.sh`.
**Covers AC 1** (requirements.md §Acceptance Criteria), trace `ga-7pq7`.

### ga-xmh3 — S2 Run detail (step graph + input convoy)

Implements plan §S2. `gascity-run-show` opens `*gascity-run*` via
`gascity-view-get-buffer-create`, mode deriving `gascity-section-mode`; own
independent async `bd list` read filtered client-side to the run; input convoy
joined via `gc.input_convoy_id` (fallback `gc convoy status <id> --json`);
per-step sections (step id, title, kind, status, assignee) in payload order;
header phase/progress/formula; dim convoy row when present; `g`/`q` keys.
ERT: rendering fixtures, convoy join present/absent, failure → inline error
vnode. Gate: `scripts/gate.sh`.
**Covers AC 2**, trace `ga-7pq7`.

### ga-30zs — S3 Activity feed (events JSONL)

Implements plan §S3. JSONL support next to `gascity-reader-read-async`
(good/bad line split; malformed lines are decode-error markers, never a
whole-feed failure); `("events" "--since" "2h")` async section load; cap
`gascity-dashboard-events-limit` (default 500); lifted filter state
`event-types-excluded` (default `order.fired`, `order.completed`,
`bead.updated`); `/` transient events submenu; rows ts/type/subject/summary;
"N older events hidden" cap line; decode errors render dim inline. ERT: JSONL
decode good/bad split, chatty-type exclusion, filter toggling, N-cap trimming,
ts formatting. Gate: `scripts/gate.sh`.
**Covers AC 3**, trace `ga-7pq7`.

### ga-refs — S4 Mail header, honest needs-you, costs pointer

Implements plan §S4. Async `("mail" "count")` read; cockpit "mail N unread"
(dim when zero) with `m` → `gascity-mail-inbox`; delete the `awaiting-input`
arm, prompt-line helper, and `respond` action mapping (honest needs-you);
header comment + docstring note the supervisor-API limitation;
`errored`/`rate-limited`/`stalled` stay derivable; costs dim pointer row in
the cockpit. ERT: mail fixtures, needs-you honesty fixtures, costs pointer
exactly one dim row. Gate: `scripts/gate.sh`.
**Covers AC 4, 5, 6 (pointer rendering)**, trace `ga-7pq7`.

### ga-gmbh — S5 Verification, e2e, capability bead, delivery report

Implements plan §S5. Whole-gate (`scripts/gate.sh`) + honesty greps (no
`awaiting-input`/`respond`, no `url`/`http` API usage); full ERT; TRAMP parity
pass over `/ssh:localhost:/home/roman/bright-lights`; interactive e2e
acceptance gate in tmux Emacs via `scripts/e2e-harness.sh` helpers, recorded
in `docs/qa/`; file the costs-JSON capability bead (and pending-interactions
bead if not covered); delivery report at the artifact root; footer legend +
header line updated. All twelve acceptance criteria verified once, here,
against the live city.
**Covers AC 6 (capability bead), 7–12**, trace `ga-7pq7`.

## Coverage Matrix

| ID | Status |
| --- | --- |
| ga-7pq7 | covered |
