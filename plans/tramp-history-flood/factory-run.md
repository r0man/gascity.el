---
schema: gc.build.final-report.v1
workflow:
  id: ga-2ea1
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: finalize
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
    - path: plans/tramp-history-flood/decomposition.md
      hash: sha256:34dc45352f7a834f3bc225aa57008aa05fb9330b8e019a664d2276761245ad91
    - path: plans/tramp-history-flood/plan-review.md
      hash: sha256:1d6b68a92f140d92768e2eb75018abd059901435a5e856a6401df22b9822c54c
    - path: plans/tramp-history-flood/implementation-summary.md
      hash: sha256:75cddc09ec077f474704df67fb75439ee636f15cc6621342c88472e6750c080c
      ids:
        - ga-o98t
        - ga-sfnj
        - ga-5b9m
        - ga-x4j3
        - ga-ldrg
    - path: plans/tramp-history-flood/review-report.md
      hash: sha256:79066fa4966c9e25274646a9900ab2e4d96781f18dd65e5ffe02fae06bf6924b
    - path: beads/ga-w8sg
      hash: bead:ga-w8sg
    - path: beads/ga-o1gy
      hash: bead:ga-o1gy
  coverage:
    - id: ga-o98t
      status: covered
    - id: ga-sfnj
      status: covered
    - id: ga-5b9m
      status: covered
    - id: ga-x4j3
      status: covered
    - id: ga-ldrg
      status: covered
    - id: AC-6
      status: out_of_scope
      rationale: publish-stage REQ→change traceability is owned by the publish stage, not finalize
---

# Factory run: build-basic starter factory (workflow ga-2ea1)

| ID | Status |
| --- | --- |
| ga-o98t | covered |
| ga-sfnj | covered |
| ga-5b9m | covered |
| ga-x4j3 | covered |
| ga-ldrg | covered |
| AC-6 | out_of_scope |

## Summary

The `build-basic` starter factory (methodology: **build-basic starter
factory**, workflow `ga-2ea1`) ran end to end in rig `gascity.el`:
requirements → plan → plan review → decomposition → implementation
(five work items in the implementation convoy `ga-w8sg`) → review →
finalize. The implemented feature is the TRAMP history-flood fix set
from `plans/tramp-history-flood/requirements.md` (REQ-001 … REQ-005
covered; REQ-006 deferred to publish as AC-6/`out_of_scope` in the
review trace). The implementation lives in five verified per-anchor
git worktrees (`ga-o98t`, `ga-sfnj`, `ga-5b9m`, `ga-x4j3`, `ga-ldrg`
under `/home/roman/workspace/gascity.el/worktrees/`), not in the
launcher checkout — this is normal for the source-anchor model, and
the review stage approved on that basis.

## Outcome

**approved.** The starter review loop closed with
`code_review.verdict=done`: the acceptance/correctness, test-evidence,
and simplicity/maintainability lanes each independently approved, the
synthesis recorded zero required fixes, and the fix lane applied no
changes. The normalized review artifact
(`plans/tramp-history-flood/review-report.md`, `gc.build.review.v1`,
status `approved`) is recorded on the workflow root as
`gc.build.review_report_path`.

- **Review lanes that ran** — acceptance/correctness
  (`acceptance-review.md`), test evidence (`test-evidence-review.md`),
  simplicity/maintainability (`review-simplicity.md`), followed by
  synthesis (`starter-review-synthesis.md`) and fix application
  (`review-fix.md`).
- **Proof commands recorded** — full gate per worktree
  (`scripts/gate.sh`: byte-compile clean with warnings-as-errors, ERT
  suite 322/323 green per worktree, the ±1 delta being per-branch
  doc-only vs one-new-test differences), two new ERTs passing 1/1,
  `make -C doc` clean, and live TRAMP re-runs against
  `/ssh:localhost:/home/roman/bright-lights` inside the AC-2 bound.
- **Publish outcome** — not published from this step. No implementation
  worktree was merged to the launcher root; propagation to the rig root
  is owned by the publish stage.
- **Next human action** — run the publish stage (or the equivalent
  manual publish) to propagate the five approved anchor worktrees, then
  review the deferred items below before any future iteration.

## Artifacts

Artifact paths are recorded on the workflow root bead `ga-2ea1`:

- Requirements: `plans/tramp-history-flood/requirements.md`
  (`gc.build.requirements_path`)
- Implementation plan: `plans/tramp-history-flood/implementation-plan.md`
  (`gc.build.plan_path`)
- Plan review: `plans/tramp-history-flood/plan-review.md`
  (`gc.build.plan_review_report_path`)
- Decomposition: `plans/tramp-history-flood/decomposition.md`
  (`gc.build.decomposition_path`)
- Implementation summary: `plans/tramp-history-flood/implementation-summary.md`
  (`gc.build.implementation_summary_path`, valid
  `gc.build.implementation-summary.v1`)
- Review report: `plans/tramp-history-flood/review-report.md`
  (`gc.build.review_report_path`, valid `gc.build.review.v1`)
- Review context: `plans/tramp-history-flood/starter-review-context.md`
  (`gc.build.code_review_context_path`)
- Implementation convoy id: `ga-w8sg` (`gc.build.implementation_convoy_id`)

## Remaining Risks

Non-blocking items deferred by the review fix lane
(`plans/tramp-history-flood/review-fix.md`), all classified low by the
synthesis:

- **ME-1** — W1's pooling experiment script was ephemeral
  (`/tmp/w1-pooling-experiment.el`); the measurement is recorded but
  not byte-for-byte reproducible from the artifacts alone. W5's ERT and
  the README live procedure cover the same regression class.
- **ME-2** — `make -C doc` can pass vacuously on stale doc artifacts;
  a forced fresh rebuild passed clean. Future proof commands should use
  `make -C doc clean all`.
- **RR-1 / RR-2** — assessed benign by the acceptance and
  test-evidence lanes; no code change required.
- **RR-3 / RR-4** — one-commit-sized optional polish in the `ga-x4j3`
  and `ga-sfnj` worktrees; deferred to avoid invalidating the recorded
  proof commands of approved worktrees.

The next human action after publish is to decide whether any deferred
polish (RR-3/RR-4) is worth a follow-up workflow.
