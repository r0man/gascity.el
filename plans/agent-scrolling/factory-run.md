---
schema: gc.build.final-report.v1
workflow: {id: ga-jwtp, formula: build-basic}
methodology: {pack: gascity, name: build-basic}
producer: {formula: build-basic, stage: finalize, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-jwtp
      hash: bead:ga-jwtp
    - path: beads/ga-dta4
      hash: bead:ga-dta4
    - path: plans/agent-scrolling/requirements.md
      hash: sha256:f06b0f208f018008eb80c7f9123d84d508da9464ab2c37ce4e322488efba1fd4
      ids: [REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014]
    - path: plans/agent-scrolling/decomposition.md
      hash: sha256:375df3ce56df32d90d922f50c4b62ceb9d420cfa2de7777f8508db62874bbf51
    - path: plans/agent-scrolling/implementation-plan.md
      hash: sha256:4f92f8d9fb9268c8685e0405814a330b34e3997c6555bb10f5a428601a8be923
    - path: plans/agent-scrolling/plan-review-report.md
      hash: sha256:f684ee694f4a8609504150f833314a2b8461fb7df0ac7ec385d4386e9abd3664
    - path: plans/agent-scrolling/implementation-summary.md
      hash: sha256:9efe86a68f60392fb205b3d6dfdf4c2a5313fc3bbf5eddd40353dba6be8cf64a
    - path: plans/agent-scrolling/review-report.md
      hash: sha256:0eb1c04dd9a65d40fb3c4160b6c04468db6d88d2111f369a0dfd2df99eaf2f5a
    - path: plans/agent-scrolling/review-context.md
      hash: sha256:4eafb29da5bfc1b8b35c9281a35e81ba30610ea96c7508f660de3990131dfbf7
    - path: plans/agent-scrolling/starter-review-synthesis.md
      hash: sha256:cde2e5b25993d3c748bbbfa4c4c07ef172e18c8d0fa5c592e6910622ff726b98
    - path: plans/agent-scrolling/starter-review-fix-summary.md
      hash: sha256:f1d0ce46072f85190761bc2e65c50ce419d5f47b9511c99b36c2c4796e6449d3
    - path: worktrees/ga-q3vr
      hash: git:b088d2caf766867ea895dff1177f0e3fd8852b82
    - path: worktrees/ga-q3vr/docs/qa/2026-09-29-agent-scrolling-e2e.md
      hash: sha256:2e5abb055362ef3a365cdd38620a1f13de105a918080f834639fb6bb405dd7da
      ids: [REQ-014]
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
---

# Factory run — build-basic (agent-scrolling, workflow ga-jwtp)

Methodology: build-basic starter factory.

## Summary

The `build-basic` factory run for workflow root `ga-jwtp` implemented
transparent tmux mouse scrolling plus an Emacs-keys scroll sub-mode for
gascity terminal attach buffers (`lisp/gascity-terminal.el`,
`lisp/gascity-custom.el`, `doc/gascity.texi`, per docs/DESIGN-agent-scrolling.md).
Requirements were generated and approved
(`plans/agent-scrolling/requirements.md`), an implementation plan was written
and design-reviewed (`implementation-plan.md`, `plan-review-report.md`), the
work was decomposed into four work items (`decomposition.md`) executed in
implementation convoy `ga-dta4`, and the canonical implementation summary
(`implementation-summary.md`, schema `gc.build.implementation-summary.v1`,
status approved) plus the consolidated review report (`review-report.md`,
schema `gc.build.review.v1`, status approved) both passed their artifact
gates. All three starter review lanes (acceptance and correctness, test
evidence, simplicity and maintainability) returned **approve** with 0 required
fixes and 0 missing evidence; the fix lane (ga-prcc) was a no-op.

## Outcome

**Approved.** All acceptance criteria REQ-001…REQ-014 are covered, each with
unit evidence and, where the plan required it, live end-to-end evidence
re-executed from the owning implementation worktrees.

- Proof commands recorded: whole-package quality gate `scripts/gate.sh`
  (`eldev compile --warnings-as-errors` + full ERT) — PASS, 748/748 tests,
  0 unexpected at the aggregate chain tip `worktrees/ga-q3vr` `b088d2c`;
  docs build `make -C doc` clean; live TRAMP e2e acceptance pass
  (`/ssh:localhost:/home/roman/bright-lights`, fresh `emacs -Q` in tmux,
  session `scroll-e2e`) — PASS, full step/probe table in
  `worktrees/ga-q3vr/docs/qa/2026-09-29-agent-scrolling-e2e.md`.
- Review lanes that ran: acceptance and correctness (ga-m0ul), test evidence
  (ga-uotm), simplicity and maintainability (ga-zxf6), synthesized by ga-gizu
  into `starter-review-synthesis.md`; fix lane ga-prcc applied no changes.
- Implementation convoy: `ga-dta4` (`agent-scrolling-implementation`), all
  four work items closed with `gc.outcome=pass` (source anchors ga-7xhp,
  ga-lk9y, ga-lb0b, ga-q3vr; per-item summaries
  `plans/agent-scrolling/implementation-wi-{1,2,3,4}-summary.md`).

Publish outcome: **not published from this step** (finalize never publishes).
The launcher rig root `/home/roman/workspace/gascity.el` is unchanged; the
implementation commits live on the detached-HEAD source-anchor worktrees
(aggregate tip `worktrees/ga-q3vr` `b088d2c`). This is the expected state
entering the publish stage (`ga-zkq6`, `open_pr=true`, `push=true`), which
owns merging to `main`, pushing, and opening the PR.

Next human action: let the publish step (`ga-zkq6`) run — or, if reviewing by
hand, inspect `worktrees/ga-q3vr` and land the chain on `main`.

## Artifacts

- Requirements: `plans/agent-scrolling/requirements.md`
- Implementation plan: `plans/agent-scrolling/implementation-plan.md`
- Plan/design review: `plans/agent-scrolling/plan-review-report.md`
- Decomposition: `plans/agent-scrolling/decomposition.md`
- Review context: `plans/agent-scrolling/review-context.md`
- Canonical implementation summary:
  `plans/agent-scrolling/implementation-summary.md`
- Consolidated review report: `plans/agent-scrolling/review-report.md`
- Starter review synthesis: `plans/agent-scrolling/starter-review-synthesis.md`
- Starter review fix summary:
  `plans/agent-scrolling/starter-review-fix-summary.md`
- Live e2e QA report (on the source-anchor worktree):
  `worktrees/ga-q3vr/docs/qa/2026-09-29-agent-scrolling-e2e.md`
- Implementation convoy: `ga-dta4`
- This report: `plans/agent-scrolling/factory-run.md`

Requirement coverage (REQ IDs from `requirements.md`; statuses are coverage,
not artifact statuses):

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

## Remaining Risks

Carried from the review report's advisory findings (R1–R9, none gating
approval or publish):

- Landing: commits exist only on the source-anchor worktrees until the
  publish stage merges/pushes them (R2) — the single concrete next action.
- Backend coverage: the live e2e pass ran vterm on tmux 3.7c; ghostel/eat
  were not re-driven live (R4; eat 0.9.4 fails to spawn in this environment,
  upstream bug). Their no-interception contract is enforced by
  `gascity-terminal--backend-reports-mouse-p` and covered by pure ERT tests.
- The `M-<`/`M->` lock relies on tmux's default copy-mode emacs table; a
  host with those keys rebound scrolls differently (tmux-side, out of
  gascity's control).
- The optimistic copy-mode belief cannot detect an out-of-band copy-mode
  exit in v1; the first wheel-up notch and the self-healing `C-c s`
  re-toggle both recover it.
- Optional cosmetic follow-ups recorded by the review: duplicated
  C-Up/C-Down escape byte constants (R8) and naming/style debt in
  `gascity-terminal.el` (R9).
