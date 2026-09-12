---
schema: gc.build.review.v1
workflow:
  id: ga-k2w
  formula: fix-loop-base
methodology:
  pack: gascity
  name: fix-loop-base
producer:
  formula: review
  stage: re-review
  attempt: 3
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
    - path: plans/formula-sling-ui/build/fix-plan.md
      hash: sha256:33a058c79289bd3f9e42736536621b08385d0d148b8573860e9f339b93eac278
      title: "Fix plan (gc.build.fix-plan.v1; FIX-1/FIX-2/FIX-3, hash matches root metadata gc.build.fix_plan_hash)"
    - path: docs/qa/formula-sling-ui-e2e.md
      hash: sha256:2ffb91c4bb707f0a0af7775cd22ebc41864a9e8aec8d9d0926c78630b1f987d9
      title: "tmux-Emacs TRAMP e2e acceptance pass + formula-dispatch closure appendix (FIX-3)"
    - path: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      hash: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      title: "Re-reviewed subject: origin/main tip (fix chain 97b0f6e -> 5595181 -> 96727cd on top of the patch-identical implementation chain)"
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

# Re-review report — formula-sling-ui after fixes (review iteration 2)

Re-reviewed subject: `origin/main` at `96727cd8`, i.e. the implementation
chain (now patch-identical as `02304e3` → `e6fa433` → `7370fa0` →
`3722346`, base `69585b6`) plus the fix-loop commits `97b0f6e` (workflow
artifacts + AGENTS.md hunk committed), `5595181` (FIX-2:
`gascity-formula-invalidate` wiring) and `96727cd8` (FIX-3: e2e
appendix closing the formula-dispatch acceptance half). This re-review
checks each iteration-1 finding against the delivered state, re-ran the
quality gate on `main`, audited the new fix commit and its test, and
re-read the e2e appendix.

**Verdict: `approved`** — every blocking and unresolved finding from
iteration 1 is closed with verifiable evidence. No new blocking or
minor findings were introduced by the fix commits.

## Verdict

- **Verdict:** `approved`
- **Blocking:** none (iteration-1 C1 closed — see F1 below).
- **Unresolved:** none (iteration-1 C2 closed — see F3 below).
- **review_mode:** `agent` — no fix handoff is issued; the loop can
  conclude. Remaining observations (M2, M4 from iteration 1; D5) were
  explicitly dispositioned without action by the fix plan and stay
  recorded there.

Requirement coverage after fixes (deltas from iteration 1 marked):

| Requirement rows | Disposition | Evidence |
|---|---|---|
| REQ-001..017 | pass (unchanged) | As reviewed in iteration 1; the only code change since (`5595181`) adds a suffix and its test, touched nothing else |
| REQ-018 (e2e) | pass (was: blocked half) | Formula-dispatch half re-run over TRAMP on main per the `96727cd8` appendix: review formula dispatched through the transient with entered vars, workflow root `hw-470` confirmed in the bright-lights store; both acceptance halves now pass |

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

AC-6 (`blocked` in iteration 1) is now `covered`: the formula-dispatch
half of the remote acceptance pass succeeded and was confirmed in the
remote store (e2e appendix, FIX-3).

## Findings

### F1 — CLOSED: C1 (implementation stranded off main)

Verified on the rig working tree against `origin/main`:

- `main` == `origin/main` at `96727cd8` (`git status -sb`, clean of
  this workflow's files).
- The reviewed implementation chain is patch-identical on `origin/main`
  as `02304e3` → `e6fa433` → `7370fa0` → `3722346`: `git cherry
  origin/main 69585b6..90cdc6b` reports no unique commits, and
  `git diff 90cdc6b origin/main -- lisp/ docs/` shows only the two
  post-landing fix commits' additions.
- Workflow artifacts landed: `97b0f6e` commits the `plans/` tree
  (including iteration-1 review-report.md and the fix plan) and the
  AGENTS.md e2e-testing section.
- Gate re-run by this re-review on main (below): PASS.
- Disposable `worktrees/ga-*` checkouts of this loop removed; the one
  remaining `worktrees/ga-fza` belongs to a different, still-active
  workflow and is out of scope here.

### F2 — CLOSED: M1 (dead `gascity-formula-invalidate`)

`5595181` wires it: the formula transient gains a static `g Refresh
catalog` suffix (`gascity-sling-formula-refresh`) that invalidates the
city's catalog/recipe memos and re-runs setup carrying scope and set
values (re-pick semantics, menu stays open). Generated var infix keys
now avoid `g` (`gascity-sling-formula--reserved-keys`), and the
docstring's caller claim is now true. New ERT
`gascity-test-formula-sling-refresh-wiring` asserts the binding, the
reserved-key avoidance, and the invalidate+re-setup behavior with
carried values (house `cl-letf` convention). Commit subject/body cite
DESIGN-write-actions.md §10 and FIX-2. No issues found in the fix.

### F3 — CLOSED: C2 (formula dispatch not confirmable in bright-lights)

`96727cd8` appends the closure to `docs/qa/formula-sling-ui-e2e.md`:
the root cause of the earlier `unknown formulas v2 target
"gc.run-operator"` is gc v2 semantics (run targets resolve per rig;
city-level `mayor` cannot instantiate per-rig pack roles), reproduced
identically in the local emacs-city — so bright-lights was never
broken. The formula-dispatch half was re-run from tmux-Emacs on main
(`5595181`) over `/sshx:localhost:/home/roman/bright-lights`: `S` →
`-f` → rig-scoped target → pick `review` → set vars → `s` dispatched
workflow `hw-470`, confirmed in the remote store by plain gc over ssh.
AC-6/REQ-018 are covered; the acceptance protocol (both halves) has now
run against the remote city.

### No new findings

The fix commit is minimal and correct; its test follows house
conventions; the e2e appendix is concrete (commands, echo text, store
confirmation). Working-tree residue (`M plans/x.md`, untracked
`plans/formula-sling-ui/build/final-report.md`,
`fix-plan-ga-iso.md`, `plans/multi-city-keying/…ga-fza…`) belongs to
concurrent workflows, not to this fix loop's subject, and does not
affect this verdict.

## Verification

- `scripts/gate.sh` on main at `96727cd8` — **PASS**: compile clean
  over the whole package, 268/268 tests (re-run by attempt 3 of this
  re-review, 2026-09-12 19:12; the +1 test vs iteration 1 is the FIX-2
  wiring test).
- `git status -sb`: main in sync with `origin/main`; `git cherry` /
  `git diff` evidence above confirms delivery (F1).
- `5595181` audit: suffix is `:transient t` (menu stays open), reserved
  keys updated, docstring truthful, test covers the mocked contract.
- `96727cd8` appendix read in full; store confirmation shows the
  workflow root `hw-470` with gc-side substituted vars in bright-lights.
- Fix-plan hash `sha256:33a058c7…` matches the workflow root's
  `gc.build.fix_plan_hash`; all three FIX items verified as landed.
- This artifact validated with `validate_build_artifact.py --schema
  gc.build.review.v1` before recording.
- **Attempt 3 note:** producer attempts 1 (`ga-vd9`) and 2 (`ga-aui`)
  wrote and committed this report unchanged but their dispatcher-side
  validator runs failed environmentally — the city's locked `beads.el`
  pack import (`gascity/roles`) was not cached. The environment was
  repaired with `gc import install`; attempt 3 re-verified the report
  against schema `gc.build.review.v1` (passes), confirmed the fix-plan
  hash still matches the workflow root, and re-ran the gate above. No
  report defect was ever recorded; the verdict and findings are
  unchanged from attempt 1.

## Drift observations

- **D6 (concurrent-workflow residue):** `plans/x.md` modified and three
  untracked plan artifacts from other workflows sit in the rig working
  tree at re-review time. Not this loop's subject; each owning workflow
  must land or clean its own files.