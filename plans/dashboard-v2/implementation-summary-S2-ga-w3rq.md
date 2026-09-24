---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-um77
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
    - path: beads/ga-xmh3
      hash: bead:ga-xmh3
      ids:
        - ga-xmh3
    - path: plans/dashboard-v2/implementation-plan.md
      hash: sha256:1bfc7e2197246d56c347e345290144c9721a520a915a9115fd6b95cb50e4bd9f
    - path: plans/dashboard-v2/requirements.md
      hash: sha256:912141fa0e63c3d5615b7131e0bcb54e832776f594f7778afd17632217259a07
    - path: lisp/gascity-run.el
      hash: git:63c8998ceb6d39ebf36b684644387c24c26e1e29
  coverage:
    - id: ga-xmh3
      status: covered
      rationale: >-
        gascity-run-show implements S2 of plans/dashboard-v2: its own
        independent async bd list read filtered client-side to the run,
        input-convoy join via gc.input_convoy_id (caller row or own
        gc convoy status read), one section per step (id, title, kind,
        status, assignee) in payload order, header with phase,
        closed/total progress and formula, stale-while-revalidate and
        inline error rendering, g/q keys, and ERT coverage for the step
        graph, convoy join present/absent, and failure rendering.  The
        gate (scripts/gate.sh) is green.
---

# Implementation Summary — Dashboard v2 S2: Run detail (step graph + input convoy)

## Summary

Implemented the run-detail drill-in of the Dashboard v2 plan
(plans/dashboard-v2/implementation-plan.md §S2) in the gascity.el worktree
`/home/roman/workspace/gascity.el/worktrees/ga-xmh3`, committed as
`63c8998 feat(ui): run detail view — step graph + input convoy (ga-xmh3)`:

- New module `lisp/gascity-run.el` (required from `lisp/gascity.el`):
  `gascity-run-show` opens a run-detail buffer for a workflow run's root
  bead id (or the run/step row at point — a step id climbs to its run
  via `gc.root_bead_id`), created through `gascity-view-get-buffer-create`
  (base name `*gascity-run*`, host-qualified, pinned `default-directory`),
  with `gascity-run-mode` deriving `gascity-section-mode`.
- Data: the view runs its own async `gc bd list` read (all statuses, so
  closed steps count toward progress) and filters client-side to the run:
  the root row is matched by id; steps are rows whose metadata carries
  `gc.root_bead_id` = the run id (verified live: only the workflow bead
  itself carries `gc.graphv2_root_key`, so the requirements' "same root
  key" sketch does not hold for steps).
- Input convoy: joined on the run root's `gc.input_convoy_id` — a caller
  holding the dashboard's already-loaded `convoy list` row passes it as
  the optional CONVOY argument (no extra read); otherwise the view makes
  its own independent async `gc convoy status <id> --json` read, so a
  convoy failure dims one section while the step graph keeps rendering.
- Rendering: one section per step (step id, title, kind from `gc.kind`
  else `gc.control_for`, status, assignee) in payload order; header shows
  phase (root status), progress closed/total, formula; a dim convoy row
  when an input convoy exists.  Loads go through
  `gascity-dashboard--effective-load` (stale-while-revalidate); failures
  render the standard inline error with a retry hint, never a blank pane.
  `g` refreshes in place, `RET` opens the bead at point in beads.el,
  `q` buries.
- Tests in `lisp/test/gascity-test.el`: selectors (step join, progress,
  kind, convoy pair), step-graph rendering fixtures, convoy join
  present/absent, inline failure and not-found rendering, view keying
  through `gascity-view-get-buffer-create`, and mode/keymap wiring.

## Intended Behavior

Satisfies AC 2 of plans/dashboard-v2/requirements.md: `RET` on a run row
opens a run-detail rendering of the full step graph (step id, title,
kind, status, assignee) plus the input convoy row.  Every read flows
through `gascity-reader-read-async` (no synchronous gc in render paths);
the step graph and the convoy are independent loads per the per-section
failure rule; buffers are keyed and pinned per city so local and TRAMP
access modes coexist (REQ-011); `q` buries and `g` refreshes everywhere.

## Changed Files

- `lisp/gascity-run.el` — new run-detail view (selectors, vnodes,
  `gascity-run-app` component, `gascity-run-mode`, `gascity-run-show`).
- `lisp/gascity.el` — load-order `require` of `gascity-run`.
- `lisp/test/gascity-test.el` — new ERT fixtures (see Summary).

## Verification

- First verification command: `eldev compile --warnings-as-errors`
  (run inside the worktree) — observed PASS (byte-compilation clean,
  warnings as errors).
- Final proof command: `scripts/gate.sh` (run inside the worktree at
  commit `63c8998`) — observed PASS: "gate: PASS (compile clean + tests
  green)", `Ran 388 tests, 388 results as expected, 0 unexpected`.
- Live-store sanity for the selectors' live assumptions (step join on
  `gc.root_bead_id`, root metadata `gc.input_convoy_id`, `gc convoy
  status` payload shape) was verified against the live `emacs-city`
  store during implementation.

| ID | Status |
| --- | --- |
| ga-xmh3 | covered |

## Remaining Risks

- TRAMP parity for the new view is exercised interactively at S5 (the
  plan's acceptance gate); the implementation keeps to the shared
  reader/view-buffer plumbing, so no local-path assumptions are known.
- The convoy join reads `gc convoy status <id> --json` when opened
  outside the dashboard; if gc changes that payload shape, the dim convoy
  section degrades to its inline error rather than blanking the graph.
- `bd list --all` grows with the store; the view filters client-side per
  the plan's "stores are small" rationale and does not cap the payload.
