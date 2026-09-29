---
schema: gc.build.decomposition.v1
workflow:
  id: ga-eavt
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
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
        - REQ-015
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: beads/ga-emog
      hash: bead:ga-emog
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: covered
    - id: REQ-007
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-009
      status: covered
    - id: REQ-010
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
    - id: REQ-015
      status: covered
---

# Sling Command Redesign — Decomposition

Decomposition of the approved requirements
(`plans/sling-command/requirements.md`, REQ-001…REQ-015) and implementation
plan (`plans/sling-command/implementation-plan.md`, WI-1…WI-12) for the
`build-basic` workflow rooted at bead `ga-eavt`. Each plan work item became
one work-item bead; the twelve beads are linked by a freshly created
implementation convoy that the `implement` stage will drain.

## Summary

The plan's twelve work items (WI-1…WI-12) map one-to-one to work-item
beads. Each bead's description restates the plan's deliverables for that
item — files, new/changed functions, REQ trace, tests, and acceptance — and
carries `gc.root_bead_id=ga-eavt`, `gc.build.work_item=WI-<n>`, and
`gc.trace.requirements=<REQ ids>` metadata for traceability back to the
requirements and the plan section. The beads are created independent
(no inter-bead dependencies): the plan's six-wave sequencing is recorded
below and enforced by the implement stage's drain order, not by bd
dependency edges, so the convoy drains without artificial gate blocking.
Every requirement REQ-001…REQ-015 is covered by at least one work item (see
Coverage).

Plan sequencing (waves, each ending with `scripts/gate.sh` green and one
commit per work item):

1. WI-1, WI-2 — pure foundations (shape inference, roster accessor,
   validators), testable offline before UI churn.
2. WI-3, WI-4 — the adaptive transient: new layout, pickers, derived
   default, reserved-key set change.
3. WI-5 — typed vars, generated against the final reserved set.
4. WI-6, WI-7, WI-8 — footer, preview buffer, follow offer.
5. WI-9, WI-10 — state/memory adaptation and the full ERT pass.
6. WI-11, WI-12 — live verification pass; documentation and screenshots
   from that session.

## Selected Downstream Formulas

- **`implement`** (`gc.var.implementation_formula`) — drains the
  implementation convoy `ga-04j2` recorded on the workflow root as
  `gc.input_convoy_id` / `gc.build.implementation_convoy_id`. Per-item
  formula `do-work-item` (`gc.var.implementation_item_formula`), execution
  target `gc.implementation-worker`
  (`gc.var.implementation_target`), drain policy `separate`
  (`gc.var.drain_policy`).
- **`review`** (`gc.var.code_review_formula`) — agent-mode code review of
  the implementation (`gc.var.review_mode=agent`).
- **`fix-loop-base`** (`gc.var.review_fix_formula`) — review-driven repair
  iterations, up to `gc.var.max_iterations=10`.
- Publish: the workflow opens a PR and pushes (`gc.var.open_pr=true`,
  `gc.var.push=true`) on `main`.

## Implementation Convoy

A new implementation convoy was created for these work units; the source /
launch convoy `ga-ix9n` (`gc.var.convoy_id`, containing only `ga-emog`) is
**not** reused.

- Name: `sling-command-implementation`
- Convoy id: `ga-04j2`
- Verified via `gc convoy list --json`: status `open`, 12 children,
  progress 0/12 closed.
- Children (WI order): `ga-510r` (WI-1), `ga-0okd` (WI-2), `ga-ntop`
  (WI-3), `ga-f7a4` (WI-4), `ga-o6eh` (WI-5), `ga-pkpi` (WI-6),
  `ga-ub2r` (WI-7), `ga-f4w0` (WI-8), `ga-me2n` (WI-9), `ga-gonl`
  (WI-10), `ga-3wpi` (WI-11), `ga-1wl7` (WI-12).

The workflow root `ga-eavt` records `gc.input_convoy_id=ga-04j2` and
`gc.build.implementation_convoy_id=ga-04j2` for the `implement` stage.

## Work Items

Each work item is one decomposition unit sized per the plan's handoff
criteria (files, functions, REQ trace, and tests named; no further
planning pass required).

| WI | Bead | Title | Requirements |
| --- | --- | --- | --- |
| WI-1 | ga-510r | Shape inference and the one-sentence header | REQ-001, REQ-002 |
| WI-2 | ga-0okd | Roster accessor and the client-side validators | REQ-005, REQ-010 |
| WI-3 | ga-ntop | Derived Who default | REQ-005 |
| WI-4 | ga-f7a4 | Adaptive layout and the three pickers | REQ-001, REQ-003, REQ-004, REQ-011 |
| WI-5 | ga-o6eh | Typed How vars | REQ-006 |
| WI-6 | ga-pkpi | Live footer | REQ-007, REQ-010 |
| WI-7 | ga-ub2r | P full preview buffer | REQ-008 |
| WI-8 | ga-f4w0 | Launch and follow offer | REQ-009 |
| WI-9 | ga-me2n | State and memory preserved | REQ-012 |
| WI-10 | ga-gonl | ERT consolidation | REQ-013 |
| WI-11 | ga-3wpi | End-to-end verification | REQ-014 |
| WI-12 | ga-1wl7 | Documentation | REQ-015 |

Traceability: each bead's `gc.trace.requirements` metadata names its REQ
ids; the plan section of the same name is the authoritative description.
The E2E pass (WI-11) and the documentation chapter (WI-12) close the loop
to REQ-014/REQ-015, including the bright-lights TRAMP acceptance gate and
the screenshots from that same session.

### Coverage

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-014 | covered |
| REQ-015 | covered |
