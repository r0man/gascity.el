---
schema: gc.build.review.v1
workflow:
  id: ga-iso
  formula: fix-loop-base
methodology:
  pack: gascity
  name: fix-loop-base
producer:
  formula: review
  stage: re-review
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements (gc.build.requirements.v1)"
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Approved implementation plan"
    - path: plans/formula-sling-ui/build/implementation-summary.md
      hash: sha256:6523bfaf373fb885b5a917c364526dada1074e592b3d60c18bbd2ece9154abd4
      title: "Implementation evidence index (convoy ga-x8m, drain ga-8xs, 4/4 pass)"
    - path: plans/formula-sling-ui/build/review-report.md
      hash: sha256:ee8fea809cd2b556f1a8f39c6802ca30e877e2a42bc125caffe5bc4a31b2cc41
      title: "Review report iteration 1 (verdict changes_required; C1 blocking, C2 unresolved, M1 minor)"
    - path: plans/formula-sling-ui/build/fix-plan-ga-iso.md
      hash: sha256:21b6151e10a7c50f4cf275804dc441890cd2c34915862f7745a690c50f52b034
      title: "This loop's fix plan (hash matches root metadata gc.build.fix_plan_hash); FIX-A/B/C"
    - path: docs/qa/formula-sling-ui-e2e.md
      hash: sha256:2ffb91c4bb707f0a0af7775cd22ebc41864a9e8aec8d9d0926c78630b1f987d9
      title: "tmux-Emacs TRAMP e2e acceptance pass + formula-dispatch closure appendix (FIX-3)"
    - path: git:d1d913a2cc64cba4b3b865bef19458f682a5db2a
      hash: git:d1d913a2cc64cba4b3b865bef19458f682a5db2a
      title: "Re-reviewed subject: main tip (implementation chain patch-identical to 90cdc6b; fix commits 97b0f6e, 5595181, 96727cd; artifact stragglers bd524fb); the one commit ahead of origin/main (d1d913a) is another loop's review report and touches nothing in the subject"
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
      status: covered
    - id: AC-7
      status: covered
    - id: AC-8
      status: covered
---

# Re-review report — formula-sling-ui fix loop ga-iso (re-review iteration 1)

Re-reviewed subject: the rig's `main` at `d1d913a2` — the implementation
chain (re-landed patch-identical as `02304e3` → `e6fa433` → `7370fa0` →
`3722346`, base `69585b6`; the reviewed chain tip `90cdc6b` is content
but not an ancestor) plus the fix-loop deliveries `97b0f6e` (workflow
artifacts), `5595181` (FIX-B: `gascity-formula-invalidate` wiring),
`96727cd` (FIX-C: e2e appendix closing the formula-dispatch acceptance
half) and `bd524fb` (FIX-A: artifact stragglers of this loop). This
loop (`ga-iso`) supersedes the sibling loop `ga-k2w`, whose re-review
(`review-report-2.md`, verdict `approved` at `96727cd8`) already
recorded closure of the same findings; this re-review independently
re-verifies against this loop's own fix plan rather than reusing that
verdict.

**Verdict: `approved`** — every finding from review iteration 1 is
closed with evidence re-verified by this pass on the current tip. No
new blocking findings. One recorded deviation (the kept
`worktrees/ga-fza` checkout) is owned by an active concurrent
workflow, not by this loop's subject, and does not gate approval.

## Verdict

- **Verdict:** `approved`
- **Blocking:** none (iteration-1 C1 closed — see F1 below).
- **Unresolved:** none (iteration-1 C2 closed — see F3 below).
- **review_mode:** `agent` — no fix handoff is issued; the loop can
  conclude. Iteration-1 minors M2/M3/M4 and drift D5 remain
  dispositioned without action by the fix plan; D4 (sshx workaround)
  stands as documented.
- **Reconciliation note:** the sibling loop `ga-k2w` (fix-plan
  `fix-plan.md`, re-review `review-report-2.md`, approved at
  `96727cd8`) reached the same closure independently and was completed
  first; per the `ga-iso` fix plan this loop reconciles and verifies
  rather than redoes, and nothing in the sibling's deliveries was
  unwound or contradicted.

Requirement coverage after fixes (deltas from iteration 1 marked):

| Requirement rows | Disposition | Evidence |
|---|---|---|
| REQ-001..017 | pass (unchanged) | The only code delta since iteration 1 is the FIX-B wiring (`5595181`: `lisp/gascity-formula.el` +22/−3 and its ERT stub); `git diff 90cdc6b main -- lisp/` shows exactly that and nothing else |
| REQ-018 (e2e) | pass (was: blocked half) | Formula-dispatch half closed by the `96727cd` appendix: workflow root `hw-470` re-confirmed CLOSED with `gc.outcome=pass` in the bright-lights store by this re-review over plain ssh; both acceptance halves now pass |

### Traceability

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |
| AC-6 | covered |
| AC-7 | covered |
| AC-8 | covered |

AC-6 (`blocked` in iteration 1) is `covered`: the formula-dispatch half
of the remote acceptance pass succeeded and its workflow root
(`hw-470`) is confirmed closed in the remote store.

## Findings

### F1 — CLOSED: C1 (implementation stranded off main)

Verified on the rig working tree during this re-review:

- The implementation content of the reviewed chain is on `main`:
  `git diff 90cdc6b main -- lisp/` shows only the FIX-B wiring
  (`lisp/gascity-formula.el` +22/−3, `lisp/test/gascity-test.el` +30);
  the docs delta against `90cdc6b` is the e2e appendix (+58 lines). No
  third-party rewrites of the implementation touched `main` since
  landing — the fact the fix plan asked this re-review to check.
- This loop's artifact stragglers landed in `bd524fb`:
  `plans/formula-sling-ui/build/fix-plan-ga-iso.md` and
  `final-report.md` are committed and pushed; the fix plan file's
  sha256 matches the workflow root's `gc.build.fix_plan_hash`.
- Gate re-run by this re-review on the current tip: **PASS** (see
  Verification).
- Residue, recorded as a deviation: the apply stage did not remove
  `worktrees/ga-fza` because it now holds active, unpushed other-loop
  work (`e75c5f7`, per-city keying loop). The fix plan's
  remove-disposable-worktrees step therefore does not apply to it;
  removal belongs to that loop, not to this one.

### F2 — CLOSED: M1 (dead `gascity-formula-invalidate`)

Verified in the working tree at the re-reviewed tip: the sling formula
transient defines the static suffix `gascity-sling-formula-refresh`
(`lisp/gascity-formula.el` ~629–641) which calls
`gascity-formula-invalidate` and re-runs `transient-setup` carrying
scope and set values (menu stays open, `:transient t`); docstrings at
~29/~89/~95 now state the real callers; the ERT stub
(`gascity-test.el` ~1058, `gascity-test-formula-sling-refresh-wiring`)
covers the mocked contract and is part of the 268/268 gate run below.
No issues found in the fix.

### F3 — CLOSED: C2 (formula dispatch not confirmable in bright-lights)

The `96727cd` appendix records the root cause (gc v2 run targets
resolve per rig; a city-level `mayor` target cannot instantiate
per-rig pack roles — reproduced identically in the local city, so
bright-lights was never broken) and the closure: the formula-dispatch
half re-run from tmux-Emacs on main over `/sshx:localhost:…`, workflow
root `hw-470` dispatched through the sling transient with entered
vars. This re-review independently confirmed the store state over
plain gc on the remote host: `hw-470` is **closed** with
`gc.outcome=pass` in bright-lights. REQ-018/AC-6 acceptance is
complete against the remote test city.

### No new findings

The only commits since the sibling re-review's subject (`96727cd8`)
are docs-only: `21410fc`/`f8a1f6e` (sibling re-review report) and
`bd524fb` (this loop's artifacts), plus `d1d913a2` (another loop's
multi-city-keying review report, present on the working tree but not
yet on `origin/main` at review time — it touches nothing in this
subject). Working-tree residue (`M plans/x.md`, untracked
`plans/multi-city-keying/…`) belongs to concurrent loops per the fix
plan's concurrency hazard note and is outside this verdict.

## Verification

- `scripts/gate.sh` on main at `d1d913a2` — **PASS**: `eldev compile
  --warnings-as-errors` clean over the whole package, 268/268 tests
  green (this re-review's own run, 2026-09-12 19:19).
- `git status -sb`: `main` at `d1d913a2`, one docs-only commit ahead
  of `origin/main` from a concurrent loop; this re-review's own
  artifact is committed by explicit path and pushed.
- `git diff 90cdc6b main -- lisp/ docs/`: FIX-B wiring + e2e appendix
  only — implementation content equivalent to the reviewed chain tip
  `90cdc6b` (F1).
- FIX-B audited in source (suffix, invalidate call, carried values,
  reserved keys, docstrings) and its ERT stub is green in the gate run
  (F2).
- `gc bd show hw-470 --json` over ssh on the bright-lights rig:
  status `closed`, `gc.outcome=pass` (F3).
- `sha256sum plans/formula-sling-ui/build/fix-plan-ga-iso.md` =
  `sha256:21b6151e…`, matching the workflow root's
  `gc.build.fix_plan_hash`; all three FIX items verified as delivered.
- Iteration-1 report (`review-report.md`) and the sibling re-review
  (`review-report-2.md`) re-read; their hashes match the traces of
  this loop's fix plan and the sibling workflow root respectively.
- This artifact validated with `validate_build_artifact.py --schema
  gc.build.review.v1` before recording.
