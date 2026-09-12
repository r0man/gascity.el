---
schema: gc.build.fix-plan.v1
workflow:
  id: ga-k2w
  formula: fix-loop-base
  step_ref: fix-loop-base.plan-fixes
methodology:
  pack: gascity
  name: fix-loop-base
producer:
  stage: plan-fixes
  attempt: 1
status: ready
trace:
  upstream:
    - path: plans/formula-sling-ui/build/review-report.md
      hash: sha256:ee8fea809cd2b556f1a8f39c6802ca30e877e2a42bc125caffe5bc4a31b2cc41
      title: "Review report iteration 1 (verdict changes_required; C1 blocking, C2 unresolved)"
    - path: plans/formula-sling-ui/build/implementation-summary.md
      hash: sha256:6523bfaf373fb885b5a917c364526dada1074e592b3d60c18bbd2ece9154abd4
      title: "Implementation evidence index (convoy ga-x8m)"
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements (gc.build.requirements.v1)"
    - path: git:90cdc6b9241ce3124e0567498fd5884848071295
      hash: git:90cdc6b9241ce3124e0567498fd5884848071295
      title: "Canonical implementation chain tip (23462e5 -> a940623 -> 46c3706 -> 90cdc6b, base 69585b6)"
  subject_state_as_of_planning:
    - "main at ed28c2b; the reviewed chain is reachable from no branch/tag/remote (review C1 verified at planning time)"
    - "rig working tree contains none of the implementation; only M AGENTS.md and untracked plans/"
    - "disposable worktrees/ga-* checkouts present (ga-4ef ga-dqm ga-fza ga-il1 ga-t2w ga-udw ga-w8j ga-wxt)"
  fix_attempt_count: 0

# Fix plan — formula-sling-ui review iteration 1

Source of every item below: the "Fix handoff (review_mode=agent)" section of
`plans/formula-sling-ui/build/review-report.md` (attempt 1). No code defect was
found in the reviewed implementation; this plan is a delivery-repair plan (C1)
plus one small code-quality fix (M1) and one environment/acceptance-closure item
(C2) that lives outside gascity.el.

Findings dispositioned without fix work (per the review's own verdicts, no
action items created):

- M3 — intentional `-f` semantics change in `gascity-sling-dispatch`; recorded
  drift, no action.
- M2 — client-side pattern validation uses Emacs regexp syntax; the
  degrade-to-no-check behavior is the approved REQ-016 contract. No action in
  this loop; re-evaluate only if a shipped formula pattern relies on RE2
  features Emacs lacks.
- M4 — generated infixes alias `transient--default-infix-command`; accepted
  coupling, no action.
- D5 — status-dashboard auto-refresh busy-spin over sync TRAMP reads;
  explicitly separated from this fix loop, tracked as its own investigation.

## FIX-1 — Land the implementation on main and push (blocking; review F-C1)

**Fixes:** review finding C1 (implementation stranded), drift D1/D2.

The reviewed chain `23462e5` → `a940623` → `46c3706` → `90cdc6b` must become
reachable from `main`/`origin/main`, together with the workflow's own artifacts,
per AGENTS.md session completion. This is mechanical: the review verified
`scripts/gate.sh` PASSES at `90cdc6b` in `/tmp/review-ga-1wy` and
`git merge-tree` shows a conflict-free merge onto `main`.

Ordered steps:

1. On `main` in the rig checkout (`/home/roman/workspace/gascity.el`):
   `git merge 90cdc6b` (merge-base `69585b6`; expected zero conflicts — main's
   only extra commit `ed28c2b` touches nothing the chain touches). If the merge
   is somehow dirty, fall back to cherry-picking
   `23462e5 a940623 46c3706 90cdc6b` in order; do not rebase-rewrite the chain.
2. Stage and commit on `main`:
   - the untracked `plans/` tree (requirements, implementation plan,
     decomposition, per-item summaries, evidence index, plan review, review
     report, this fix plan);
   - the modified `AGENTS.md` hunk adding the "Remote test city & e2e testing"
     section that `docs/qa/formula-sling-ui-e2e.md` cites.
   One commit is fine (`docs(build): commit formula-sling-ui workflow
   artifacts`); the QA report itself lands with the merge, not with this commit.
3. Re-run `scripts/gate.sh` **on main** (compile clean + full ERT suite).
4. `git pull --rebase && git push`; confirm `git status` is clean vs `origin`
   and `origin/main` contains `90cdc6b`.
5. Remove the disposable `worktrees/ga-*` checkouts and their registration
   (`git worktree remove` per directory; they are not part of any approved
   artifact and must not outlive the loop).

**Verification:** `git merge-base --is-ancestor 90cdc6b origin/main`;
`scripts/gate.sh` exit 0 on main; `git status --porcelain` empty;
`worktrees/` empty.

**Traceability:** unblocks AC-6/AC-7 delivery acceptance (the artifact paths in
the store must resolve from a fresh clone); satisfies REQ-017 on the landed
tree.

## FIX-2 — Wire `gascity-formula-invalidate` (minor; review F-M1)

**Fixes:** review finding M1 (dead code, stale-recipe risk within one session).

In the landed tree, either:

- wire `gascity-formula-invalidate` into a user-reachable affordance — the
  natural fit is a refresh entry in the formula picker transient (`S` flow,
  `gascity-action.el`) that also invalidates the per-(formula,var) history
  caches — or, if wiring is judged premature, correct the docstring(s) in
  `lisp/gascity-formula.el` (lines ~29, ~89, ~95, ~166) to stop claiming callers
  that do not exist.

Preference is the wiring option: catalog staleness is real after editing a
formula mid-session. Keep the change small; add/adjust an ERT stub test in
`lisp/test/gascity-test.el` following the house `cl-letf` convention. No design
section change is expected; if a new key is introduced, check
`docs/DESIGN-write-actions.md` §10 first.

**Verification:** `scripts/gate.sh` green; new/adjusted
`gascity-test-formula-*` test passes.

## FIX-3 — Close the C2 acceptance gap in bright-lights (non-code; review F-C2)

**Fixes:** review finding C2 (formula dispatch fails gc-side in the remote
test city; e2e F3).

This work happens on the bright-lights city, not in gascity.el:

1. Diagnose and resolve `unknown formulas v2 target "gc.run-operator"` for
   remote formula instantiation in `/home/roman/bright-lights` (agent-pack
   roles / formula import state on that city). Reproduction is already
   documented: plain gc over ssh fails for every catalog formula after
   `gc reload` and `gc restart`, while the same formulas instantiate in the
   local emacs-city and `gc doctor` passes 89 ✓.
2. Re-run **only the formula-dispatch half** of the tmux-Emacs TRAMP
   acceptance pass against `/ssh:localhost:/home/roman/bright-lights`: dispatch
   a formula sling, set vars through the transient, confirm the workflow root
   appears in the remote store (AGENTS.md e2e protocol).
3. Append the result to `docs/qa/formula-sling-ui-e2e.md` (now on main after
   FIX-1) and note the bright-lights resolution.

**Verification:** live store confirmation of a formula-rooted workflow created
from the remote city; updated QA report.

**Traceability:** lifts AC-6 from `blocked` to `covered` (REQ-018 completion).

## Ordering and iteration contract

- FIX-1 first (it unblocks everything: nothing else should proceed while the
  subject of record is stranded). FIX-2 and FIX-3 are independent of each
  other; FIX-2 must land after FIX-1 so it rides on main.
- `gc.build.review_fix_attempt_count` starts at 0 for this handoff (already
  recorded on the build root ga-c0e). The re-review step
  (`fix-loop-base.re-review`) runs the `review` formula after apply-fixes; it
  must record the follow-up report path on the fix-loop root as
  `gc.build.review_report_path`. Continue iterating only while the count is
  below `max_iterations` (10).
- FIX-3 may complete after the re-review iteration that approves the code; the
  follow-up review report should record AC-6 as `covered` once the acceptance
  half is appended, otherwise `blocked` stays unresolved on the workflow root
  and finalize must not record a pass.

## Risks

- R1: `git merge 90cdc6b` assumed clean per review evidence; if the rig tree
  changed since, re-verify with `git merge-tree` before merging rather than
  force-anything.
- R2: FIX-3 is outside this rig's control (bright-lights agent-pack state); if
  it cannot be resolved in this iteration, record AC-6/REQ-018 as blocked with
  the concrete gc-side error rather than weakening the acceptance criterion.
- R3: removing `worktrees/ga-*` in FIX-1 step 5 must only happen after the
  push is confirmed — those worktrees currently hold the only working copies.

## Metadata to record on close of the fix loop

- `gc.build.fix_plan_path` = this file (on the fix-loop root ga-k2w, recorded
  by plan-fixes); its content hash is recorded as `gc.build.fix_plan_hash` in
  the same metadata update.
- Follow-up review report path as `gc.build.review_report_path` (re-review
  step), plus per-iteration attempt counts on the build root ga-c0e.
