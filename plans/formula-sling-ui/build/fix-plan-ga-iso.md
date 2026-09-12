---
schema: gc.build.fix-plan.v1
workflow:
  id: ga-iso
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
    - path: plans/formula-sling-ui/build/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements (gc.build.requirements.v1)"
    - path: docs/qa/formula-sling-ui-e2e.md
      hash: sha256:2ffb91c4bb707f0a0af7775cd22ebc41864a9e8aec8d9d0926c78630b1f987d9
      title: "tmux-Emacs TRAMP e2e acceptance pass + follow-up pass closing the formula-dispatch half (F3/C2, commit 96727cd)"
    - path: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      hash: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      title: "main == origin/main at planning time (implementation re-landed + artifacts 97b0f6e + FIX-2 wiring 5595181 + C2 acceptance closure 96727cd); gate PASS verified here"
  subject_state_as_of_planning:
    - "main == origin/main == 5595181 at planning time; the reviewed chain 23462e5 -> a940623 -> 46c3706 -> 90cdc6b was re-landed on main as recreated commits (02304e3, e6fa433, 7370f0a->7370fa0, 3722346), NOT merged — 90cdc6b is not an ancestor and never will be"
    - "content equivalence verified by this planning pass: git diff 90cdc6b main -- lisp/ shows only the FIX-2 wiring (gascity-formula.el +22/-3, test +30); AGENTS.md hunk and the plans/ tree landed with 97b0f6e"
    - "review C1 (stranded implementation) is substantively RESOLVED on main; FIX-1 of the sibling fix-loop plan (plans/formula-sling-ui/build/fix-plan.md, workflow ga-k2w) was already applied by that loop's apply stage (ga-aif, still in_progress)"
    - "review M1/F-M1 is RESOLVED: commit 5595181 wires gascity-formula-invalidate into the sling transient refresh (lisp/gascity-formula.el ~629-636) with an ERT stub (lisp/test/gascity-test.el ~1058); gate on main: compile clean + 268/268 tests (one more than the review's 267)"
    - "review C2 CLOSED during planning: the concurrent apply stage (ga-k2w/ga-aif) landed 96727cd — root cause was gc semantics, not a broken city: v2 pack formulas route steps at the per-rig gc.run-operator role, so a city-level sling target (mayor) cannot instantiate them in EITHER city; the acceptance half re-run from tmux-Emacs on main with a rig-scoped target (hello-world/gc.implementation-worker) dispatched the review formula and workflow root hw-470 was confirmed closed in the bright-lights store (verified by this planning pass over ssh); e2e report follow-up section appended and pushed; AC-6/REQ-018 now covered"
    - "superseded probe (kept for the record): at ~18:50, before 96727cd, this planning pass found no gc pack agents on the bright-lights rig and suspected a missing rig import; the concurrent apply's root-cause analysis disproved that (pack imports were fine, sha:3b3b89f in both cities; only a city-level target had been tried)"
    - "delivery residue: worktrees/ga-fza still checked out (detached 719042e); plans/formula-sling-ui/build/final-report.md untracked"
    - "CONCURRENCY HAZARD: the rig is shared by other live loops — main advanced mid-planning (037a926 docs(review): record blocked review report for missing subject plans/y.md, unpushed) and plans/x.md is modified in the working tree by another loop. All fix commits must be scoped by explicit path; never commit -a"
  fix_attempt_count: 0
---

# Fix plan — formula-sling-ui review iteration 1 (fix-loop ga-iso)

Source of every item: the "Fix handoff (review_mode=agent)" section of
`plans/formula-sling-ui/build/review-report.md` (attempt 1), re-planned
against the rig state at planning time (see `subject_state_as_of_planning`).
This loop supersedes the stalled sibling fix loop `ga-k2w` for execution:
ga-k2w planned the same findings (`fix-plan.md`) and its apply stage landed
most of the delivery work, but its loop never reached re-review. **This
loop must reconcile and verify, not redo.** Do not touch ga-k2w's beads;
its abandonment is operator business.

Disposition of review minors (unchanged from the sibling plan, still valid):

- M3 — intentional `-f` semantics change; recorded drift, no action.
- M2 — client-side Emacs-regexp pattern checks degrade to no-check
  (approved REQ-016 contract); no action in this loop.
- M4 — generated infixes alias `transient--default-infix-command`;
  accepted coupling, no action.
- D5 — dashboard auto-refresh busy-spin on sync TRAMP reads; separate
  investigation, not a gate for this feature.

## FIX-A — Reconcile and finish delivery on main (review C1/F-C1 — verify, then close the residue)

**Fixes:** review finding C1 and drift D1/D2 — already substantively applied
by the concurrent apply stage; this item is verification plus residue.

1. Re-verify at apply time (state may have moved again): `git rev-parse main
   origin/main`; confirm the implementation content is still present
   (`git diff 90cdc6b <main-tip> -- lisp/` must show only the FIX-2 wiring;
   if it shows more, another loop changed the implementation and the
   re-review must see that fact). Confirm the gate passes on the current
   tip: `scripts/gate.sh` (compile clean + full ERT suite). Planning-time
   evidence: PASS, 268/268 at 5595181.
2. Do **not** merge/cherry-pick `90cdc6b` — the chain was re-landed as
   recreated commits; merging now would duplicate history. The subject of
   record is the recreated chain on `main`; record that disposition in the
   re-review handoff (the review's `trace.upstream` git hash `90cdc6b…`
   refers to content that is now on main by way of
   02304e3 → e6fa433 → 7370fa0 → 3722346).
3. Commit the workflow-artifact stragglers **by explicit path only** (the
   working tree carries unrelated in-flight edits from other loops — at
   planning time `plans/x.md` was modified and `plans/y.md` work was
   landing):
   - `plans/formula-sling-ui/build/final-report.md` (untracked);
   - this fix plan (`plans/formula-sling-ui/build/fix-plan-ga-iso.md`).
   Suggested subject: `docs(build): fix-loop ga-iso plan + finalize artifacts`.
   Leave `plans/x.md` and everything else untracked/modified untouched.
4. `git pull --rebase && git push`; confirm `git status` is clean of *this
   loop's* paths and `origin/main` contains the tip.
5. Remove the leftover disposable worktree **after** the push is confirmed:
   `git worktree remove --force /home/roman/workspace/gascity.el/worktrees/ga-fza`
   (detached at 719042e; holds no unpushed implementation — the canonical
   content is on main). `git worktree list` must afterwards show only the
   main checkout, unless another loop registered a new worktree meanwhile —
   in that case remove only `ga-fza`.

**Verification:** `scripts/gate.sh` exit 0 on the pushed tip; this loop's
paths clean vs origin; `git worktree list` free of ga-fza.

**Traceability:** closes C1/D1/D2 for the re-review; keeps every artifact
path resolvable from a fresh clone (REQ-017 on the landed tree).

## FIX-B — Confirm the M1 wiring (review F-M1 — verify only; no code change expected)

**Fixes:** review finding M1 (dead `gascity-formula-invalidate`).

Applied by commit `5595181` (on main, pushed). The apply stage of this loop
must only verify, and record in its summary:

- the wiring is user-reachable: the sling transient's refresh path calls
  `gascity-formula-invalidate` (`lisp/gascity-formula.el` ~629-636), clearing
  the catalog and recipe memos, so mid-session formula edits are picked up;
- the docstrings at `lisp/gascity-formula.el` ~29/~89/~95 now match reality;
- an ERT stub covers it (`lisp/test/gascity-test.el` ~1058) and the gate is
  green (268/268 at planning time).

If any of these does not hold on the current tip, treat the delta as a
finding for the re-review rather than silently patching; a small corrective
commit is allowed but must be gated and pushed per FIX-A step 4.

**Verification:** gate green; the three checks above recorded in the apply
summary.

## FIX-C — Verify the C2 acceptance closure (review F-C2 — verify only; the concurrent apply closed it)

**Fixes:** review finding C2 (formula dispatch "fails gc-side" in the remote
test city; e2e F3). Closed during planning by the concurrent apply stage
(commit `96727cd`, on main and pushed): the failure was **gc semantics, not a
broken city** — v2 pack formulas route their steps at the per-rig
`gc.run-operator` role, so a city-level sling target (`mayor`) cannot
instantiate them in either city; the earlier acceptance pass had only tried
`mayor`. The re-run from tmux-Emacs on main used a rig-scoped target
(`hello-world/gc.implementation-worker`), dispatched the review formula, and
workflow root `hw-470` was confirmed closed in the bright-lights store
(re-verified by this planning pass over ssh). The e2e report's follow-up
section records root cause, re-run, and store confirmation.

The apply stage of this loop must only verify, and record in its summary:

1. `96727cd` is on `origin/main` and the appended e2e section is intact.
2. `gc bd show hw-470 --json` over ssh shows a closed formula-rooted
   workflow in the bright-lights store.
3. If any of the above does not hold (e.g. the closure was reverted), fall
   back to performing the acceptance re-run per AGENTS.md and appending the
   result to `docs/qa/formula-sling-ui-e2e.md`, then push per FIX-A step 4.

**Verification:** live store confirmation of `hw-470`; e2e follow-up section
on origin/main.

**Traceability:** AC-6 lifted from `blocked` to `covered` (REQ-018
completion). The re-review report should record AC-6 as covered with the
recreated-chain disposition from FIX-A.

## Ordering and iteration contract

- FIX-A first (small, delivery hygiene); FIX-B and FIX-C are verification
  folded into the same apply pass; all three are independent, but the
  re-review needs FIX-A done (findings must be assessed against a pushed
  tree).
- `gc.build.review_fix_attempt_count` starts at 0 for this handoff. The
  re-review step (`fix-loop-base.re-review`) runs the `review` formula
  after apply-fixes and records the follow-up report path on this loop
  root (`ga-iso`) as `gc.build.review_report_path`. Continue iterating only
  while the count is below `max_iterations` (10).
- The re-review report must record the recreated-chain disposition
  (FIX-A step 2) so the original review's `90cdc6b` trace hash is not
  mistaken for a missing subject.

## Risks

- R1 (concurrency): the rig is shared — main advanced and the working tree
  gained unrelated edits during planning. All commits by explicit path;
  re-verify main/tree state at apply time; never `commit -a` or
  `checkout/reset` shared paths.
- R2 (stalled sibling loop): ga-k2w's apply bead (`ga-aif`) was still
  `in_progress` at planning time and produced 96727cd (C2 closure) and the
  037a926/`plans/y.md` review commit while this plan was being written. If
  it makes further commits, fold them into the verification evidence
  instead of duplicating the work; do not close or modify ga-k2w beads from
  this loop.
- R3: FIX-C's closure (96727cd) was verified at planning time; if it is
  found reverted or incomplete at apply time, AC-6/REQ-018 must be recorded
  as blocked with the concrete gc-side error rather than weakening the
  criterion.
- R4: remove `worktrees/ga-fza` only after the push is confirmed.

## Metadata to record

- On this loop root `ga-iso` at close of plan-fixes:
  `gc.build.fix_plan_path` = this file, `gc.build.fix_plan_hash` = its
  content hash, `gc.build.fix_plan_stage=planned`.
- On the claimed step bead (`ga-4au`) at close: `gc.outcome=pass`.
- Follow-up review report path as `gc.build.review_report_path`
  (re-review step); per-iteration attempt counts stay on the build root
  `ga-c0e`.
