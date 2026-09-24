---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-u33h
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-89p2
      hash: bead:ga-89p2
      ids:
        - ga-89p2
    - path: plans/dashboard-v2/implementation-plan.md
      hash: sha256:1bfc7e2197246d56c347e345290144c9721a520a915a9115fd6b95cb50e4bd9f
    - path: lisp/gascity-dashboard.el
      hash: git:b4e6f0fd07b6edf2e80de9474d26a91798aec10c
  coverage:
    - id: ga-89p2
      status: covered
      rationale: >-
        S1 of the Dashboard v2 plan is implemented in full: workflow-run
        discovery from one `gc bd list' read, client-side grouping by
        `gc.graphv2_root_key' with verified-live root-vs-step
        discrimination, per-run progress/current-step/updated columns, a
        Runs section above Work in flight, closed runs excluded behind a
        dim count line, run rows stamped with the root bead id for the
        S2 drill-in, and ERT fixtures for every selector behavior.
---

# Implementation Summary — Dashboard v2 S1 (Runs section)

Coverage:

| ID | Status |
| --- | --- |
| ga-89p2 | covered |

## Summary

Dashboard v2 step S1 (bead ga-89p2, source anchor of the do-work drain
unit) is implemented in `lisp/gascity-dashboard.el`: a **Runs** section
above "Work in flight" that groups the city's workflow runs from the
in-progress `gc bd list` payload, client-side, with zero extra gc reads
(the in-progress read already carries every run root and step for the
small stores this view targets — verified live in `emacs-city`).

New pure selectors (all fixture-tested):

- `gascity-dashboard--workflow-runs` — groups raw decoded bead rows by
  `gc.graphv2_root_key`, returning `(:rows … :closed-count N)`; one
  `(ROOT CLOSED TOTAL CURRENT UPDATED)` row per non-closed run root, in
  payload order. Root-vs-step discrimination follows the verified live
  shape: roots carry `gc.kind: workflow` (the tracker the steps TRACK);
  the fallback for a `gc.kind`-less payload shape is the same root key
  WITHOUT `gc.root_bead_id` (a root tracks steps, it is never one of
  them). Steps join to their run on the metadata's `gc.root_bead_id`.
- `gascity-dashboard--run-root-p`, `--root-key`, `--bead-meta`,
  `--run-current-step` — the discrimination and current-step helpers
  (first non-closed step with a non-empty `assignee`).
- `gascity-dashboard--run-row` — one row vnode: run id, formula
  (`gc.formula_name`), phase (root status), progress `closed/total`,
  current step id, updated (root `updated_at` trimmed to the minute);
  stamped with the root bead id under `gascity-bead` so `RET` lands on
  the run (the S2 drill-in's hook; S2 renders the detail buffer).

Closed runs are excluded from the default view; when any exist the
section appends a dim "N closed runs hidden" line (the requirements'
explicit latitude). A failing `gc bd list` read renders the section's
error dimly with a retry hint while every other section keeps its own
payload — the established per-section failure rule (REQ-010).

## Intended Behavior

- Opening (or refreshing) the city dashboard issues the same reads as
  before plus none: the Runs section reuses the in-progress read's full
  payload. A mayor sees every open workflow run with id, formula, phase,
  progress fraction, current step and updated time, without drilling.
- A workflow run is a bead whose metadata carries `gc.graphv2_root_key`.
  A step is a bead with the same key plus `gc.root_bead_id`. A run root
  is `gc.kind == "workflow"` (verified live in `emacs-city`: all six
  roots carry it; steps carry `gc.root_bead_id`, none carry the step
  anchors `gc.ralph_step_id`/`gc.logical_bead_id` on roots), with the
  key-without-anchor fallback for resilience.
- Closed runs disappear from the list; their count shows dimly below
  the live rows so the census stays honest.
- `RET` on a run row carries the root bead id (stamped `gascity-bead`),
  which `gascity-dashboard-activate` already dispatches to beads.el;
  S2 will re-dispatch it to the run-detail view.
- Runs render above "Work in flight" (which keeps showing live
  bead×session joins runs do not carry).

## Changed Files

- `lisp/gascity-dashboard.el` — the workflow-run projection (selectors
  + row renderer), the Runs section in
  `gascity-dashboard--content-vnode`, and the module header's section
  list; 167 lines added, no existing behavior changed.
- `lisp/test/gascity-test.el` — the `gascity-test--runs-beads` fixture
  payload and seven ERT tests (discrimination, grouping/progress,
  closed-run exclusion, wrapped-payload shape, row stamping, mounted
  rendering + ordering, inline error path); 183 lines added.
- `plans/dashboard-v2/` — the approved plan bundle copied into the
  worktree (untracked in the launcher checkout), so the artifact root
  travels with the branch.
- Commit: `b4e6f0f` `feat(dashboard): Runs section — workflow-run census
  from one bd list read` on the item worktree `main` work branch.

## Verification

1. **First verification command** — the whole-package gate, from the
   item worktree `/home/roman/workspace/gascity.el/worktrees/ga-89p2`:

   ```
   scripts/gate.sh
   ```

   Observed: **PASS** — `>>> gate: PASS (compile clean + tests green)`;
   byte-compile with `--warnings-as-errors` clean, `Ran 387 tests, 387
   results as expected, 0 unexpected` (380 prior + 7 new).

2. **Final proof command** — the artifact validator, from the launcher
   rig root `/home/roman/workspace/gascity.el`:

   ```
   GC_BEAD_ID=ga-s71l .gc/scripts/checks/build-artifact-valid.sh
   ```

   Observed: **pass** — `build artifact valid:
   schema=gc.build.implementation-summary.v1 path=…/implementation-summary-s1.md`
   (run after recording `gc.implementation.summary_path` on the
   workflow root ga-u33h; see the closure notes in the step bead).

Unit evidence per requirement piece: root-vs-step discrimination
(including the `gc.kind`-less fallback, both directions), grouping with
progress `1/3` and current-step pick (`ga-step2`, skipping the closed
and unassigned steps), zero-step run rendering `0/0` with no current
step, closed-run exclusion with count 1, `issues`-wrapped payload
tolerance, `gascity-bead` stamping on the run row vnode, mounted
buffer showing "▼ Runs" above "▼ Work in flight" with closed runs
hidden, and the `gc error: …` + `press g to retry` inline failure.

## Remaining Risks

- **Bead-store window.** The read stays
  `("bd" "list" "--status" "in_progress")`: closed run roots vanish
  from that payload once the root closes, so a run whose root closed
  but whose steps are in flight would drop out of both Runs and the
  S2 drill-in source. Verified live that roots close last (steps close
  first), so the practical window is narrow; if it matters, S2 can
  widen the read to all statuses client-side.
- **Ordering is payload order.** `bd list` returns beads newest-first,
  so run rows are not sorted by activity; accepted for S1 (the plan
  leaves row order to the implementer), revisitable in S2 polish.
- **TRAMP parity deferred to S5.** The section reads through the same
  remote-aware plumbing as every other section, but the live
  `/ssh:localhost:/home/roman/bright-lights` pass is S5's acceptance
  gate, per the plan's verification split.
- **Emacs 30.1 `when-let*` deprecation warnings** surface from
  beads.el's own files under Emacs 31; pre-existing, not from this
  change (the gate treats them as warnings, and this package's files
  compile clean).
