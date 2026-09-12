---
schema: gc.build.final-report.v1
workflow:
  id: ga-c0e
  formula: build-from-requirements
methodology:
  pack: gascity
  name: build-from-review-base
producer:
  formula: build-from-requirements
  stage: finalize
  attempt: 1
status: blocked
trace:
  upstream:
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements (gc.build.requirements.v1)"
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Approved implementation plan"
    - path: plans/formula-sling-ui/build/plan-review.md
      hash: sha256:aa5b4e6b891e4d293857d5f6b0579f88e6ea408412adf19aacc5694f286a2a76
      title: "Approved plan review"
    - path: plans/formula-sling-ui/build/decomposition.md
      hash: sha256:7ffdbd0b63b4305b1ab8c525e2cbe956adf71c94722319a4f29b04decbd2b6d7
      title: "Approved decomposition"
    - path: plans/formula-sling-ui/build/implementation-summary.md
      hash: sha256:6523bfaf373fb885b5a917c364526dada1074e592b3d60c18bbd2ece9154abd4
      title: "Implementation evidence index (convoy ga-x8m, drain ga-8xs, 4/4 pass)"
    - path: plans/formula-sling-ui/build/review-report.md
      hash: sha256:ee8fea809cd2b556f1a8f39c6802ca30e877e2a42bc125caffe5bc4a31b2cc41
      title: "Review report iteration 1 (verdict changes_required; findings C1/C2, minors M1-M4, drift D1-D5)"
    - path: git:90cdc6b9241ce3124e0567498fd5884848071295
      hash: git:90cdc6b9241ce3124e0567498fd5884848071295
      title: "Reviewed implementation chain tip (23462e5 -> a940623 -> 46c3706 -> 90cdc6b, base 69585b6) — stranded off main, see finding C1"
    - path: docs/qa/formula-sling-ui-e2e.md
      hash: sha256:80667081dd4b8da4c814e9c4c189e80189c65db939c96dcd7c8a1a82ab08c98c
      title: "tmux-Emacs TRAMP e2e acceptance pass (formula-dispatch half blocked gc-side, F3/C2)"
    - path: bead:ga-iso
      hash: bead:ga-iso
      title: "Dispatched fix-loop-base workflow (attempt 1) against the review findings; plan-fixes -> apply-fixes -> re-review, max_iterations=10"
  coverage:
    - id: AC-1
      status: covered
    - id: AC-2
      status: covered
    - id: AC-3
      status: covered
    - id: AC-4
      status: covered
    - id: AC-5
      status: covered
    - id: AC-6
      status: blocked
      rationale: "Review verdict changes_required with the fix loop dispatched but not yet approved (ga-iso); AC-6 additionally blocked gc-side in bright-lights (review finding C2 / e2e F3) until the formula-dispatch acceptance half is re-run."
    - id: AC-7
      status: covered
    - id: AC-8
      status: covered
---

# Final report — formula-sling-ui continuation (build-from-requirements, finalize iteration 1)

Continuation entrypoint: **`build-from-requirements`** (workflow root
`ga-c0e`, formula_contract `graph.v2`, methodology pack `gascity`, name
`build-from-review-base`). This continuation restarted from an already
approved upstream plan: planning, plan review, decomposition, and the
implementation convoy were **skipped because their approved artifacts
already existed** at the recorded paths (see Artifacts). Only the
review, repair-review, and finalize stages executed in this run.

## Summary

The formula-sling-ui implementation (convoy `ga-x8m`, 4/4 work items
pass, chain `23462e5`→`90cdc6b`) was reviewed by iteration 1 and got
verdict **`changes_required`**:

- **C1 (blocking, delivery):** the reviewed chain is stranded — it is
  reachable from no branch, tag or remote; `main` contains none of the
  implementation, and the `plans/` artifact tree plus the `AGENTS.md`
  e2e-section hunk are uncommitted. `git merge-tree` shows a
  conflict-free merge; the fix is mechanical.
- **C2 (acceptance gap, gc-side):** formula dispatch cannot be
  confirmed in the bright-lights test city (`unknown formulas v2 target
  "gc.run-operator"` after `gc reload`/`gc restart`); the
  formula-dispatch half of the remote acceptance pass is blocked until
  that is fixed and re-run.
- **M1–M4 (minors):** dead `gascity-formula-invalidate`, Emacs-regexp
  pattern checks, intentional `-f` semantics change, transient internal
  API coupling.

Per `review_mode=agent` the repair-review stage (`ga-g9h`) dispatched
the selected `review_fix_formula=fix-loop-base` as workflow **`ga-iso`**
(attempt 1; `findings_path` = the review report,
`implementation_target=gc.implementation-worker`, `max_iterations=10`)
against the recorded findings. `gc.build.review_fix_attempt_count=1`
and `gc.build.repair_status=repairable` are recorded on the workflow
root; the loop owns approval, blocked, and exhausted outcomes, and its
completion must restart the `build-from-review` entrypoint to reach an
approved terminal state.

## Outcome

- **Terminal outcome: `blocked`.** The review verdict is
  `changes_required` and `gc.build.repair_status=repairable` (not
  `approved`), so the workflow root cannot finalize as a pass.
- Workflow root records: `gc.outcome=fail`,
  `gc.build.status=blocked`, `gc.failure_class=review_changes_required`
  (machine-readable), with restart metadata preserved:
  `gc.restart.entrypoint=build-from-review`,
  `gc.restart.reason=review_changes_required`,
  `gc.restart.review_report_path`,
  `gc.restart.review_fix_formula=fix-loop-base`,
  `gc.restart.implementation_target=gc.implementation-worker`.
- Publish authorization: **none** — `open_pr=false` and `push=false`
  for this run, and the blocking delivery finding (C1) means nothing
  may be published from this workflow. The publish step must no-op and
  keep the workflow outcome unchanged.
- Next action: let fix-loop workflow `ga-iso` run (plan-fixes →
  apply-fixes → re-review). On its re-review approval, restart the
  `build-from-review` entrypoint so a fresh finalize can record
  `gc.build.repair_status=approved` and a passing terminal outcome; if
  the loop returns blocked or exhausts `max_iterations=10`, it records
  `gc.build.repair_status=blocked`/`exhausted` with
  `gc.failure_class=review_repair_failed` and the same restart
  entrypoint. The C2 bright-lights gc-side repair (formulas v2 target
  registration) is a prerequisite for closing AC-6.

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |
| AC-6 | blocked |
| AC-7 | covered |
| AC-8 | covered |

## Artifacts

- Requirements (approved):
  `plans/formula-sling-ui/requirements.md`
  (`sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31`)
- Implementation plan (approved):
  `plans/formula-sling-ui/build/implementation-plan.md`
  (`sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a`)
- Plan review (approved):
  `plans/formula-sling-ui/build/plan-review.md`
  (`sha256:aa5b4e6b891e4d293857d5f6b0579f88e6ea408412adf19aacc5694f286a2a76`)
- Decomposition:
  `plans/formula-sling-ui/build/decomposition.md`
  (`sha256:7ffdbd0b63b4305b1ab8c525e2cbe956adf71c94722319a4f29b04decbd2b6d7`)
- Implementation evidence (convoy `ga-x8m`, drain `ga-8xs`, 4/4 pass):
  `plans/formula-sling-ui/build/implementation-summary.md`
  (`sha256:6523bfaf373fb885b5a917c364526dada1074e592b3d60c18bbd2ece9154abd4`)
  with per-item summaries
  `implementation-summary-ga-dqm.md`, `-ga-wxt.md`, `-ga-udw.md`,
  `-ga-4ef.md`
- Review report (iteration 1, verdict `changes_required`):
  `plans/formula-sling-ui/build/review-report.md`
  (`sha256:ee8fea809cd2b556f1a8f39c6802ca30e877e2a42bc125caffe5bc4a31b2cc41`)
- Implementation chain tip: `git:90cdc6b9241ce3124e0567498fd5884848071295`
  (base `69585b6`), gate-verified by the review (`scripts/gate.sh`
  PASS: compile clean, 267/267 tests) but stranded off `main` (C1)
- E2E acceptance report:
  `docs/qa/formula-sling-ui-e2e.md`
  (`sha256:80667081dd4b8da4c814e9c4c189e80189c65db939c96dcd7c8a1a82ab08c98c`)
- Repair loop: fix-loop-base workflow root **`ga-iso`**
  (`findings_path=plans/formula-sling-ui/build/review-report.md`,
  `implementation_formula=implement`,
  `implementation_target=gc.implementation-worker`,
  `code_review_formula=review`, `max_iterations=10`), dispatched by
  repair-review `ga-g9h` at attempt 1

## Remaining Risks

- **C1 — stranded delivery (blocking):** until the fix loop's
  apply-fixes merges `90cdc6b` onto `main`, commits the `plans/` tree
  and the `AGENTS.md` e2e-section hunk, and pushes, the implementation
  exists nowhere durable. Every artifact path in this report resolves
  only in the current rig working tree.
- **C2 — bright-lights formulas v2 target gap:** formula dispatch fails
  gc-side in the remote test city (`unknown formulas v2 target
  "gc.run-operator"`); AC-6's formula-dispatch acceptance half stays
  blocked until the remote city's agent-pack/roles are repaired and the
  tmux-Emacs TRAMP pass is re-run (append to
  `docs/qa/formula-sling-ui-e2e.md`).
- **Drift (recorded by review):** D1 subject-vs-main mismatch (folded
  into C1); D2 untracked artifact tree (folded into C1); D4 e2e ran
  over `sshx`, not plain `ssh`; D5 dashboard auto-refresh busy-spin on
  sync TRAMP reads from transients — separate investigation owed, not a
  gate for this feature.
- **Minor debt accepted by review:** M1 `gascity-formula-invalidate`
  dead code (fix handoff F-M1), M2 Emacs-regexp pattern checks degrade
  to no-check, M4 transient internal API coupling. None block approval
  once C1/C2 close.
- The fix loop (`ga-iso`) may return blocked or exhaust
  `max_iterations=10`; the restart metadata on the root keeps the
  `build-from-review` entrypoint available either way.