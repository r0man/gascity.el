---
schema: gc.build.fix-plan.v1
workflow:
  id: ga-be2
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
    - path: plans/multi-city-keying/build/review-report.md
      hash: sha256:020eef885994a3c4494cda2cb32f097d34b83e7ea77d539d76f21ba7a36d8868
      title: "Review report iteration 1 (verdict changes_required; C1 blocking, M1/D1/D2 non-blocking)"
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved requirements (gc.build.requirements.v1; REQ-009 governs the formula-cache clause)"
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
      title: "Approved implementation plan (D1 records the @<city-root> qualifier shape)"
    - path: plans/multi-city-keying/build/decomposition.md
      hash: sha256:7c4b2f3a120c2a59c46656bf50dd180cd5b9991caaee614002ca1e56bb0e8c20
      title: "Work-item decomposition (WI-1..WI-4, convoy ga-wxj)"
    - path: plans/multi-city-keying/build/plan-review.md
      hash: sha256:93a98b10c8667e12cc31967d4258da259135a204e967925f8d24303d8b7a0ca5
      title: "Plan review (advisory: no formula-cache module existed at decomposition time → REQ-010 governs)"
    - path: git:e75c5f75ede20b6679683a17a9018ed6fdf321b9
      hash: git:e75c5f75ede20b6679683a17a9018ed6fdf321b9
      title: "Reviewed implementation chain tip (a4e3ab8 -> 75423fa -> 719042e -> e75c5f7, merge-base 69585b6; detached in worktrees/ga-fza)"
    - path: git:c29b5de
      hash: git:c29b5de
      title: "main tip as of planning: carries the formula-sling-ui chain (tip 96727cd8) plus the two review-doc commits d1d913a/c29b5de"
  subject_state_as_of_planning:
    - "main at c29b5de; the reviewed chain a4e3ab8..e75c5f7 is reachable from NO branch/remote — verified at planning time (git branch --contains empty)"
    - "gascity-context-scope-key does NOT exist on main (git grep over main: no hits); it exists only at e75c5f7 — so FIX-2 cannot precede FIX-1"
    - "lisp/gascity-formula.el on main keys its catalog/recipe caches by gascity-formula--city-key = (concat (file-remote-p dir) (expand-file-name dir)) — the second, independent scheme of review finding C1"
    - "merge-tree(merge-base, main, e75c5f7) reports exactly one both-modified file: lisp/test/gascity-test.el (both chains appended tests near the file tail); no conflicts in the three re-keyed modules"
    - "disposable worktree present: worktrees/ga-fza (detached e75c5f7) — the only working copy of the chain"
    - "rig tree is otherwise clean except M plans/x.md and untracked plans/multi-city-keying/{final-report.md,ga-fza-implementation-summary.md}"
  fix_attempt_count: 0

# Fix plan — multi-city-keying review iteration 1

Source of every item below: the "Fix handoff (review_mode=agent)" block under
finding C1 of `plans/multi-city-keying/build/review-report.md` (attempt 1).
No defect was found in the delivered WI-1..WI-4 code — REQ-001..008 and
010..016 all pass. This plan is one land-time integration item (C1) split
into a landing step, a re-keying step, and a test step, plus the review's
M1 wording note as an opportunistic rider.

Findings dispositioned without fix work (per the review's own verdicts, no
action items created):

- M1 — self-contradictory "unaffected" sentence in
  `docs/qa/2026-09-10-multi-city-keying.md`; the review explicitly says "no
  action required; fix the sentence opportunistically if the file is touched
  again". The file is NOT touched by FIX-1..3, so no action — but if the
  file is touched anyway during landing, fix the sentence in the same
  commit (wording below, in FIX-1 step 3).
- D1 — drift observation, resolved by FIX-1 itself (the rebase/merge is the
  conflict-resolution point).
- D2 — drift observation, resolved by FIX-1 (the land commit includes the
  currently-untracked `ga-fza-implementation-summary.md`).

## FIX-1 — Land the reviewed chain on main (blocking; review C1 precondition)

**Fixes:** review drift D1/D2; prerequisite for C1's fix (the chain carries
`gascity-context-scope-key`, which main lacks).

The chain `a4e3ab8` → `75423fa` → `719042e` → `e75c5f7` (merge-base
`69585b6`) must become reachable from `main`. The review already verified
`scripts/gate.sh` PASSES at `e75c5f7`; `git merge-tree` against the current
main (c29b5de) shows a single both-modified file (`lisp/test/gascity-test.el`)
— both chains appended test content near the file tail, so the conflict is
adjacent-block noise, not semantic overlap. Resolve it by keeping BOTH
sides' tests (the per-city keying block and the formula block are
independent suites).

Ordered steps:

1. In `worktrees/ga-fza` (the only working copy of the chain): rebase the
   4-commit chain onto main (`git rebase main` from the detached tip, or
   `git rebase --onto` after branching `fix/multi-city-keying` at
   `e75c5f7`). Do not rewrite history beyond the rebase; commit subjects
   stay intact.
2. Resolve the `lisp/test/gascity-test.el` conflict by union-merging the
   two test blocks; also expect trivial commentary-context conflicts in
   `lisp/gascity-context.el` / `gascity-remote.el` headers if any.
3. Stage and commit on the rebased branch, in the same commit or the
   follow-up, the workflow's own untracked artifacts from the rig tree:
   `plans/multi-city-keying/build/{final-report.md,ga-fza-implementation-summary.md}`
   (review D2: the land commit must include `ga-fza-implementation-summary.md`)
   and this fix plan. Leave `M plans/x.md` alone unless it belongs to this
   workflow's publication.
4. Run `scripts/gate.sh` on the rebased tip (compile clean + full ERT).
   The formula chain's tests and the per-city keying tests must both pass
   on the merged tree — this is the first tree that carries both
   `gascity-context-scope-key` and `gascity-formula.el`.
5. Fast-forward `main` to the rebased tip, `git pull --rebase && git push`,
   confirm `git status` is clean vs origin.
6. Remove `worktrees/ga-fza` (`git worktree remove`) ONLY after the push is
   confirmed (it is the last working copy of the chain until then).

**Verification:** `git merge-base --is-ancestor e75c5f7-rebased origin/main`;
`scripts/gate.sh` exit 0 on main; `git status --porcelain` empty.

**Traceability:** unblocks FIX-2/3 (they ride on main); closes D1/D2.

## FIX-2 — Re-key `gascity-formula`'s caches onto the shared helper (blocking; review C1)

**Fixes:** review C1 (REQ-009/REQ-003 "one key helper, one API").

In `lisp/gascity-formula.el` (now on main after FIX-1):

1. Make `gascity-formula--city-key` delegate to
   `gascity-context-scope-key` — either `(defalias …)` wrapping the helper
   with DIR defaulted from `default-directory`, or replace its three uses
   (`gascity-formula-catalog-cached`, `gascity-formula-recipe-cached`,
   `gascity-formula-invalidate`) with direct `gascity-context-scope-key`
   calls. One call site shape, one identity; no second computation of
   `(concat (file-remote-p dir) (expand-file-name dir))` remains.
2. Update the cache docstrings (lines ~83–95) and the module commentary to
   name `gascity-context-scope-key` as the keying identity, dropping the
   local "remote-qualified directory" description (review FIX-1 docs), so
   exactly one documented scheme remains — mirroring how
   `gascity-context.el`'s commentary already names the formula caches as
   the next consumer (REQ-010).
3. Behavior notes for the implementer: the shared key is the governing
   city root (memoized walk), so a caller whose `default-directory` is a
   rig repo inside a city now shares the city's cache entry instead of
   splitting it; and the key honours `gascity-context-city` overrides
   (REQ-011). No cache-shape change: catalog stays `(key . entries)`,
   recipe stays `((key . NAME) . recipe)`; `gascity-formula-invalidate`
   keeps clearing only the current city's entries.
4. Commit subject: `fix(formula): key formula caches by gascity-context-scope-key`
   (body cites REQ-009/REQ-003 and the review report).

**Verification:** `grep -n 'file-remote-p' lisp/gascity-formula.el` returns
no keying use; gate green; the existing
`gascity-test-formula-catalog-cached-memoizes-and-isolates-cities` /
`gascity-test-formula-recipe-cached-and-invalidate` still pass under the
shared key (they use temp local dirs + a stubbed `/ssh:` prefix, which the
scope-key fallback maps to distinct keys exactly as before).

**Traceability:** REQ-009 → covered; REQ-003's "exactly one scheme" → pass
across all call sites.

## FIX-3 — Extend the formula-cache tests to the shared identity (review FIX-1 tests)

**Fixes:** review C1 test handoff (REQ-011, REQ-014).

In `lisp/test/gascity-test.el`, beside the existing formula cache tests:

1. Two local cities (real temp dirs, `locate-dominating-file` stubbed or a
   planted `city.toml` per the per-city rig memo tests' house pattern) hold
   distinct catalog/recipe entries — the rig-repo-inside-a-city case now
   shares the city-root entry.
2. Two cities under one TRAMP prefix (`/ssh:u@h:` stubs, never contacted)
   stay distinct.
3. A `gascity-context-city` override keys the caches by the overridden
   root (REQ-011): with the override bound, a read lands under the
   override's key and does not disturb the natural city's warm entry.
4. Keep the existing two formula cache tests passing unchanged (they are
   the "existing per-city formula tests keep passing" clause); adjust only
   if the docstring wording needs the new identity named.

Follow the house convention: `cl-letf` on `gascity-command-formula-catalog!`
/ `gascity-command-formula-show!` and the gc boundary; no live `gc`.
Gate: whole-package compile + full ERT.

**Verification:** new `gascity-test-formula-*` tests green; count of
`gascity-context-scope-key`-keyed caches documented = all of them.

**Traceability:** REQ-009/REQ-011/REQ-014 evidence for the re-review.

## Ordering and iteration contract

- FIX-1 first and strictly before FIX-2/3 (the helper does not exist on
  main; nothing else proceeds while the subject of record is stranded).
- FIX-2 and FIX-3 are one logical change but may be two commits
  (`fix(formula)` + `test(formula)`); both land on main before the
  re-review runs.
- `gc.build.review_fix_attempt_count` starts at 0 for this handoff (first
  review iteration). The re-review step (`fix-loop-base.re-review`) runs
  the `review` formula after apply-fixes and must record the follow-up
  report path on the fix-loop root ga-be2 as `gc.build.review_report_path`.
  Continue iterating only while the count is below `max_iterations` (10).
- No e2e re-run is required by this loop: the review found no behavioral
  gap in the delivered code (the C1 divergence is cache-identity only,
  invisible to the dual-city e2e by design), and FIX-2 does not change any
  user-visible surface. If the re-review disagrees, it owns ordering the
  acceptance pass.

## Risks

- R1: rebase assumed clean except `lisp/test/gascity-test.el` per
  `git merge-tree` at planning time; re-verify immediately before rebasing
  rather than trusting the snapshot — main can advance again.
- R2: FIX-2 changes which cache entry a rig-repo-resident caller hits
  (city-root entry instead of a rig-scoped one). This is the *intended*
  convergence, but if any programmatic caller depended on rig-level cache
  isolation for staleness, that staleness window widens to the city. The
  re-review should confirm no caller relies on that.
- R3: `gascity-formula-invalidate` is wired into the sling transient
  (commit 5595181 on main) — after re-keying it clears under the shared
  key; the transient's refresh must still invalidate the right city. The
  existing sling refresh test (`gascity-test-formula-sling-refresh-wiring`)
  guards this.
- R4: removing `worktrees/ga-fza` only after push confirmation (it holds
  the sole working copy of the chain until FIX-1 lands).

## Metadata to record on close of the fix loop

- `gc.build.fix_plan_path` = `plans/multi-city-keying/build/fix-plan.md`
  and its sha256 as `gc.build.fix_plan_hash`, recorded on the fix-loop
  root ga-be2 by the plan-fixes step (this step, ga-fsh).
- Follow-up review report path as `gc.build.review_report_path` on ga-be2
  (re-review step), plus per-iteration attempt counts on the build root.
- The apply-fixes step (ga-wt7e) commits cite FIX-1/2/3 from this plan.
