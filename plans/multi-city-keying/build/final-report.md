---
schema: gc.build.final-report.v1
workflow:
  id: ga-rv5
  formula: build-from-requirements
methodology:
  pack: gascity
  name: build-from-review-base
producer:
  formula: build-from-requirements
  stage: finalize
  attempt: 3
status: blocked
trace:
  upstream:
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved requirements (gc.build.requirements.v1; matches root metadata gc.build.requirements_hash)"
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
      title: "Approved implementation plan (matches root metadata gc.build.plan_hash)"
    - path: plans/multi-city-keying/build/plan-review.md
      hash: sha256:93a98b10c8667e12cc31967d4258da259135a204e967925f8d24303d8b7a0ca5
      title: "Approved plan review (advisory: no formula-cache module existed at decomposition time → REQ-010 governs)"
    - path: plans/multi-city-keying/build/decomposition.md
      hash: sha256:7c4b2f3a120c2a59c46656bf50dd180cd5b9991caaee614002ca1e56bb0e8c20
      title: "Work-item decomposition (WI-1..WI-4, convoy ga-wxj)"
    - path: plans/multi-city-keying/build/ga-3fe-implementation-summary.md
      hash: sha256:8ccd3cbf91482344277bc7f8a44f0dde2956b8639f4134549ab16ef0ba49aecc
      title: "WI-1 implementation summary (gascity-context-scope-key + per-city rigs memo)"
    - path: plans/multi-city-keying/build/ga-dpu-implementation-summary.md
      hash: sha256:d3539fa613dec4c774b70e1a51ae5cdcba189923e710d765eefc0141aec55dd8
      title: "WI-2 implementation summary (city-root buffer names + attach qualifier)"
    - path: plans/multi-city-keying/build/ga-eu6-implementation-summary.md
      hash: sha256:de30a12e678cdfaf7b74dfd6ecc0c47b16b79cde1ba057b22d921049b3b7419e
      title: "WI-3 implementation summary (per-city unit tests)"
    - path: plans/multi-city-keying/build/ga-fza-implementation-summary.md
      hash: sha256:322875311dae476cf59e4a245171b6440e98947cb730549fd4dc70a4531896e3
      title: "WI-4 implementation summary (gate + dual-city tmux-Emacs e2e pass + QA report)"
    - path: plans/multi-city-keying/build/review-report.md
      hash: sha256:020eef885994a3c4494cda2cb32f097d34b83e7ea77d539d76f21ba7a36d8868
      title: "Review report iteration 1 (verdict changes_required; blocking C1, minors M1, drift D1-D2)"
    - path: git:a4e3ab80cb76d90af9329055f2a02511b0c8570b
      hash: git:a4e3ab80cb76d90af9329055f2a02511b0c8570b
      title: "Reviewed implementation chain, commit 1/4: feat(context) gascity-context-scope-key + per-city rigs memo"
    - path: git:75423faf09f524d2591459d4ca16a7ae300ebe11
      hash: git:75423faf09f524d2591459d4ca16a7ae300ebe11
      title: "Reviewed implementation chain, commit 2/4: fix(remote) city-root-qualified view/attach buffer names"
    - path: git:719042ee49167291d8122aa92beef2cd4116bd1c
      hash: git:719042ee49167291d8122aa92beef2cd4116bd1c
      title: "Reviewed implementation chain, commit 3/4: test(context) per-city keying unit tests"
    - path: git:e75c5f75ede20b6679683a17a9018ed6fdf321b9
      hash: git:e75c5f75ede20b6679683a17a9018ed6fdf321b9
      title: "Reviewed implementation chain tip, commit 4/4: docs(qa) dual-city tmux-Emacs e2e pass (docs/qa/2026-09-10-multi-city-keying.md) — chain stranded off main, see C1"
    - path: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      hash: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      title: "origin/main tip: formula-sling-ui landed here AFTER this branch forked (merge-base 69585b6) — brings lisp/gascity-formula.el with its own cache keying (finding C1)"
    - path: docs/qa/2026-09-10-multi-city-keying.md
      hash: sha256:fe6ef417ea255e33993c2d935b932c1b1cdfa16e79d48f837f9545baf593f80d
      title: "tmux-Emacs TRAMP dual-city e2e acceptance pass (committed on the implementation chain at e75c5f7, not yet on main)"
    - path: bead:ga-be2
      hash: bead:ga-be2
      title: "Dispatched fix-loop-base workflow (attempt 1) against the review findings; plan-fixes -> apply-fixes -> re-review, max_iterations=10; in flight at finalize attempts 2 and 3 (plan-fixes step ga-fsh in progress, no fixes applied or re-reviewed yet, main tip unchanged at c29b5de)"
  coverage:
    - id: AC-1
      status: covered
    - id: AC-2
      status: blocked
      rationale: "Review verdict changes_required: blocking finding C1 — the formula caches landed on main with an independent keying scheme, violating REQ-009's one-key-helper clause; blocked until fix-loop ga-be2 applies FIX-1 and a re-review approves."
    - id: AC-3
      status: covered
    - id: AC-4
      status: covered
    - id: AC-5
      status: covered
---

# Final report — multi-city-keying continuation (build-from-requirements, finalize iteration 3)

Continuation entrypoint: **`build-from-review`** (workflow root
`ga-rv5`, formula_contract `graph.v2`, methodology pack `gascity`, name
`build-from-review-base`, restart reason
`gc.restart.reason=review_changes_required`). This continuation
restarted from the already reviewed implementation: requirements,
planning, plan review, decomposition, the implementation convoy, and
the iteration-1 review were **skipped because their approved artifacts
already existed** at the recorded paths (see Artifacts). Only the
repair-review stage (`ga-csc`, which dispatched the fix loop) and this
finalize stage executed in this run; the fix loop it dispatched
(`ga-be2`) is still in flight.

This is finalize **attempt 3** (`gc.attempt=3` on step bead `ga-5z5l`,
the control's final bounded attempt after attempt-1 subject `ga-fs3`
and attempt-2 subject `ga-a52n` both closed with the blocked outcome;
the control attempt log carries no validator errors, so the artifact
was repaired in place rather than rewritten).
Re-verification at attempts 2 and 3 found the blocked state
**unchanged**: review verdict still `changes_required` (unresolved C1),
`gc.build.repair_status=repairable`, fix loop `ga-be2` still at the
plan-fixes stage (`ga-fsh` in progress; apply-fixes `ga-wt7e`,
re-review `ga-okfo`/`ga-7hsb`, and loop finalize `ga-hb6w` still open),
and `main` tip still `c29b5de` with no fix commits landed. This
blocked outcome is a faithful terminal recording of the run, not a
producer defect; the fix loop's re-review must restart the
`build-from-review` entrypoint to reach an approved terminal state.

## Summary

The multi-city-keying implementation (convoy `ga-wxj`, 4/4 work items
pass, chain `a4e3ab8`→`75423fa`→`719042e`→`e75c5f7` on merge-base
`69585b6` in worktree `worktrees/ga-fza`) re-keys gascity.el's
city-scoped state onto one `gascity-context-scope-key` identity. The
review iteration 1 verified the delivered WI-1..WI-4 code fully
(requirement-by-requirement audit, gate re-run 252/252, e2e report
audit) and returned verdict **`changes_required`**:

- **C1 (blocking, REQ-009):** the formula-sling-ui caches
  (`lisp/gascity-formula.el`) landed on `main` after this branch
  forked and key by an independent scheme (`gascity-formula--city-key`
  = `(concat (file-remote-p dir) (expand-file-name dir))`), violating
  REQ-009's "one key helper, one API" clause on the merged result.
  FIX-1 handoff: re-key `gascity-formula` onto
  `gascity-context-scope-key`.
- **M1 (minor):** one self-contradictory "unaffected" sentence in the
  QA report — opportunistic wording fix only.
- **D1/D2 (drift):** the chain is stranded off `main` (expected
  mid-workflow; the land step should expect rebase conflicts in
  `lisp/test/gascity-test.el`), and `ga-fza`'s implementation summary
  is untracked on `main` (the land commit must include it).

Per `review_mode=agent` the repair-review stage (`ga-csc`) dispatched
the selected `review_fix_formula=fix-loop-base` as workflow **`ga-be2`**
(attempt 1; `findings_path` = the review report,
`implementation_target=gc.implementation-worker`,
`max_iterations=10`; dispatched 2026-09-12T17:23Z).
`gc.build.fix_attempt_count=1` and
`gc.build.repair_status=repairable` are recorded on the workflow root;
the loop owns approval, blocked, and exhausted outcomes, and its
completion must restart the `build-from-review` entrypoint to reach an
approved terminal state.

## Outcome

- **Terminal outcome: `blocked`.** The review verdict is
  `changes_required` with unresolved C1, and
  `gc.build.repair_status=repairable` (not `not_needed`/`approved`),
  so the workflow root cannot finalize as a pass. Finalize attempts 2
  and 3 re-verified this state after attempt 1 (`ga-fs3`) recorded it;
  the fix loop had not yet applied fixes or re-reviewed, so the
  blocked outcome carries over unchanged.
- Workflow root records: `gc.outcome=fail`,
  `gc.build.status=blocked`, `gc.failure_class=review_changes_required`
  (machine-readable), with restart metadata preserved:
  `gc.restart.entrypoint=build-from-review`,
  `gc.restart.reason=review_changes_required`,
  `gc.restart.review_report_path`,
  `gc.restart.review_fix_formula=fix-loop-base`,
  `gc.restart.implementation_target=gc.implementation-worker`.
- Publish authorization: **none** — `open_pr=false` and `push=false`
  for this run, and the blocking merged-result finding (C1) means
  nothing may be published from this workflow. The publish step must
  no-op and keep the workflow outcome unchanged.
- Next action: let fix-loop workflow `ga-be2` run (plan-fixes →
  apply-fixes → re-review). On its re-review approval, restart the
  `build-from-review` entrypoint so a fresh finalize can record
  `gc.build.repair_status=approved` and a passing terminal outcome; if
  the loop returns blocked or exhausts `max_iterations=10`, it records
  `gc.build.repair_status=blocked`/`exhausted` with
  `gc.failure_class=review_repair_failed` and the same restart
  entrypoint. The land step that closes the D1/D2 drift is the natural
  moment to resolve the expected `lisp/test/gascity-test.el` rebase
  conflicts against the formula-sling-ui chain.

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | blocked |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |

## Artifacts

- Requirements (approved):
  `plans/multi-city-keying/requirements.md`
  (`sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43`)
- Implementation plan (approved):
  `plans/multi-city-keying/build/implementation-plan.md`
  (`sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7`)
- Plan review (approved):
  `plans/multi-city-keying/build/plan-review.md`
  (`sha256:93a98b10c8667e12cc31967d4258da259135a204e967925f8d24303d8b7a0ca5`)
- Decomposition:
  `plans/multi-city-keying/build/decomposition.md`
  (`sha256:7c4b2f3a120c2a59c46656bf50dd180cd5b9991caaee614002ca1e56bb0e8c20`)
- Implementation evidence (convoy `ga-wxj`, 4/4 drain items pass):
  per-item summaries
  `plans/multi-city-keying/build/ga-3fe-implementation-summary.md`
  (`sha256:8ccd3cbf91482344277bc7f8a44f0dde2956b8639f4134549ab16ef0ba49aecc`),
  `ga-dpu-implementation-summary.md`
  (`sha256:d3539fa613dec4c774b70e1a51ae5cdcba189923e710d765eefc0141aec55dd8`),
  `ga-eu6-implementation-summary.md`
  (`sha256:de30a12e678cdfaf7b74dfd6ecc0c47b16b79cde1ba057b22d921049b3b7419e`),
  `ga-fza-implementation-summary.md`
  (`sha256:322875311dae476cf59e4a245171b6440e98947cb730549fd4dc70a4531896e3`)
- Review report (iteration 1, verdict `changes_required`, blocking C1):
  `plans/multi-city-keying/build/review-report.md`
  (`sha256:020eef885994a3c4494cda2cb32f097d34b83e7ea77d539d76f21ba7a36d8868`)
- Implementation chain tip: `git:e75c5f75ede20b6679683a17a9018ed6fdf321b9`
  (`a4e3ab8` → `75423fa` → `719042e` → `e75c5f7`, base `69585b6`),
  gate-verified by the review (`scripts/gate.sh` PASS: compile clean,
  252/252 tests) but stranded off `main` (D1)
- E2E acceptance report (on the chain, not yet on `main`):
  `docs/qa/2026-09-10-multi-city-keying.md`
  (`sha256:fe6ef417ea255e33993c2d935b932c1b1cdfa16e79d48f837f9545baf593f80d`)
- Repair loop: fix-loop-base workflow root **`ga-be2`**
  (`findings_path=plans/multi-city-keying/build/review-report.md`,
  `implementation_formula=implement`,
  `implementation_target=gc.implementation-worker`,
  `code_review_formula=review`, `max_iterations=10`), dispatched by
  repair-review `ga-csc` at attempt 1; **in flight** at finalize
  attempts 2 and 3 (plan-fixes `ga-fsh` in progress; apply-fixes
  `ga-wt7e`, re-review `ga-okfo`/`ga-7hsb`, loop finalize `ga-hb6w`
  open)

## Remaining Risks

- **C1 — second keying scheme on `main` (blocking):** until fix loop
  `ga-be2` applies FIX-1 (re-key `gascity-formula`'s catalog/recipe
  caches onto `gascity-context-scope-key`) and a re-review approves,
  the merged tree would carry two divergent city identities for
  key-scoped state, which is exactly what REQ-009 forbids.
- **D1 — stranded delivery:** the reviewed chain lives only on
  detached HEAD in `worktrees/ga-fza`; `main` contains none of the
  implementation. Every code reference in this report resolves only in
  that worktree or the rig working tree until the land step merges and
  commits the remaining artifacts (D2: `ga-fza` summary untracked on
  `main`).
- **Rebase hazard (D1):** both chains modified
  `lisp/test/gascity-test.el` heavily (this branch +406 lines; the
  formula chain rewrote large parts of the same file) — expect real
  conflicts during FIX-1's rebase.
- **Minor debt accepted by review:** M1 self-contradictory
  "unaffected" sentence in the QA report. None block approval once C1
  closes.
- The fix loop (`ga-be2`) may return blocked or exhaust
  `max_iterations=10`; the restart metadata on the root keeps the
  `build-from-review` entrypoint available for an explicit restart in
  either case.
