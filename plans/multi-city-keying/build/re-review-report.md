---
schema: gc.build.review.v1
workflow:
  id: ga-be2
  formula: fix-loop-base
methodology:
  pack: gascity
  name: review
producer:
  formula: review
  stage: re-review
  attempt: 3
status: approved
trace:
  upstream:
    - path: plans/multi-city-keying/build/review-report.md
      hash: sha256:020eef885994a3c4494cda2cb32f097d34b83e7ea77d539d76f21ba7a36d8868
      title: "Review report iteration 1 (verdict changes_required; C1 blocking, M1/D1/D2 non-blocking)"
    - path: plans/multi-city-keying/build/fix-plan.md
      hash: sha256:7580bad5fb5fef52c3e1573a04ed8609328df105fdf3172025494a81791fb8f5
      title: "Fix plan (FIX-1 land the chain, FIX-2 re-key formula caches, FIX-3 tests; hash matches root metadata gc.build.fix_plan_hash)"
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved requirements (gc.build.requirements.v1; REQ-009 governed the fix handoff)"
    - path: git:1a78f7a
      hash: git:1a78f7a
      title: "FIX-1: rebased implementation chain on main (7ef649c feat(context) scope-key → 6519fcb fix(remote) buffer qualification → 599e0b7 test(context) per-city tests → 1a78f7a docs(qa) dual-city e2e); worktrees/ga-fza removed"
    - path: git:24f9523
      hash: git:24f9523
      title: "FIX-1 landing artifacts: fix plan + final report + ga-fza-implementation-summary.md committed (review drift D2 resolved)"
    - path: git:45ff9fb
      hash: git:45ff9fb
      title: "FIX-2: fix(formula) key formula caches by gascity-context-scope-key (gascity-formula--city-key deleted)"
    - path: git:1725234
      hash: git:1725234
      title: "FIX-3: test(formula) shared scope-key cache identity suite + locate-dominating-file stub in the existing catalog-cache test"
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
---

# Re-review report — multi-city-keying fix loop (review iteration 2)

Attempt log: attempt 1 (`ga-okfo`) wrote this report with the verdict and
verification below, but the dispatcher-side validator run failed
environmentally — `gc bd show ga-okfo` died on a locked-but-uncached
remote pack import (`rig "beads.el" import "gc"` not cached under
`/home/roman/emacs-city/.gc/cache/repos/…`), not on the artifact. The
repair was `gc import install` (4 remote imports installed); attempt 2
(`ga-mgti`) re-ran the check gate
(`.gc/scripts/checks/build-artifact-valid.sh`, `GC_BEAD_ID=ga-mgti`) and
it passes: `build artifact valid: schema=gc.build.review.v1`. No schema
error was ever raised against the report; the report was repaired in
place per the re-review contract (attempt bump + this log only).

Attempt 2 (`ga-mgti`) closed with the gate passing in the reviewer
session, but the dispatcher-side validator failed again with the
identical "locked but not cached" error: the roles pack clone
(`…/gascity-packs/tree/main/gascity/roles`, cache key `af5bc89…`, pinned
`sha:3b3b89f`) was present in the user cache (`/home/roman/.gc/cache`)
but missing from the city-local cache
(`/home/roman/emacs-city/.gc/cache/repos`), which is where the
controller's `gc bd show` resolves it. `gc import install` (city- and
rig-scoped) reported "Installed 4 remote import(s)" but never materialized
that clone city-locally — the packs.lock entry already satisfied it, so
the dispatcher's suggested repair was insufficient. Attempt 3
(`ga-4ql2`) repaired the environment by copying the content-identical,
version-matched clone (HEAD `3b3b89f`, exactly the pinned version) into
the city-local cache, then re-ran the check gate from the controller's
own working context (`/home/roman/emacs-city`, `GC_BEAD_ID=ga-4ql2`):
`build artifact valid: schema=gc.build.review.v1`. Verdict unchanged:
`approved`.

Re-reviewed subject: the fix-loop commits on `main` that resolve review
iteration 1's findings the fix-loop commits on `main` that resolve review
iteration 1's findings — the landed chain (FIX-1: `7ef649c` → `6519fcb`
→ `599e0b7` → `1a78f7a`, artifacts `24f9523`) and the C1 re-keying
(FIX-2 `45ff9fb`, FIX-3 `1725234`), per
`plans/multi-city-keying/build/fix-plan.md`.

**Verdict: `approved`** — the blocking finding C1 is fully resolved, the
fix is exactly what the review's handoff block specified, and the full
gate re-run by this review is green on the merged tree. No new findings.

## Verdict

- **Verdict:** `approved`
- **Blocking:** none.
- **Resolved:** C1 (REQ-009/REQ-003 one keying scheme) — closed by
  FIX-2/FIX-3; D1/D2 drift — closed by the FIX-1 landing.
- **Carried, no action:** M1 (self-contradictory "unaffected" sentence
  in the QA report) — the review's own disposition stands ("no action
  required; fix the sentence opportunistically if the file is touched
  again"); the QA report was not touched by any fix commit, so no action
  was taken and none is owed.
- **review_mode:** `agent` — no fix handoff remains; the loop terminates
  at iteration 1 fix attempt (below `max_iterations=10`).
- **Fix-attempt count:** 1 (a single apply-fixes pass, `ga-wt7e`,
  `gc.attempt=1`; no repair loop was needed).

Requirement disposition (re-checked against the *fixed* tree, not the
summaries; only rows affected by the fix work are re-argued — rows
unchanged from iteration 1 remain pass):

| Requirement rows | Disposition | Evidence |
|---|---|---|
| REQ-009 (formula caches key via the shared API) | **pass** (was fail) | `gascity-formula--city-key` is deleted; all three key sites — `gascity-formula-catalog-cached` (l.136), `gascity-formula-recipe-cached` (l.160), `gascity-formula-invalidate` (l.172) — call `gascity-context-scope-key` directly (commit `45ff9fb`); no `file-remote-p`/`expand-file-name` keying computation remains in `lisp/gascity-formula.el` |
| REQ-003 (exactly one keying scheme, one documented API) | **pass** (was pass-with-C1-caveat) | Module commentary and both cache docstrings name `gascity-context-scope-key` as the identity and drop the old "remote-qualified directory" description; the `(require 'gascity-context)` wiring is present. Only two documented non-factory sites remain package-wide: `gascity-terminal-attach-tmux` (intentional, per iteration 1) and the formula caches now going through the shared helper |
| REQ-011 (override keys by the overridden root) | pass, extended to formula caches | `gascity-test-formula-cache-keys-by-scope-key`: with `gascity-context-city` bound, the catalog read misses (a fifth gc call), lands under the override's key, and the natural city's warm entry survives untouched |
| REQ-014 (ERT: distinct keys/values per city, incl. formula caches) | **pass** | New test asserts a rig repo inside a city shares the city-root entry (calls 1 not 2 — the intended FIX-2 convergence), two local cities distinct, two cities under one `/ssh:u@h:` prefix distinct with the walk stubbed and the host never contacted; the existing catalog/recipe tests keep passing with `locate-dominating-file` stubbed so the fictitious `/ssh:localhost:` directory is never walked |
| REQ-016 (`scripts/gate.sh` passes) | pass | Re-run by this review on `main` at `1725234` (clean tree): whole-package `eldev compile --warnings-as-errors` clean, full ERT suite **274/274, 0 unexpected** (`>>> gate: PASS`) — the first tree carrying both `gascity-context-scope-key` and `gascity-formula.el` passes |
| FIX-plan R2 (no caller relied on rig-level cache isolation) | pass | All cache consumers live inside `lisp/gascity-formula.el` (transient setup l.599/l.790, preview l.567, refresh l.636); grep over `lisp/` shows no external caller of the cached readers or `gascity-formula-invalidate`, so the widened staleness window has no affected caller |
| FIX-plan R3 (sling refresh still invalidates the right city) | pass | `gascity-sling-formula-refresh` calls `gascity-formula-invalidate`, which filters both caches under the shared key; `gascity-test-formula-sling-refresh-wiring` green in the gate re-run |

### Traceability

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |

## Findings

None. Blocking finding C1 (iteration 1) is resolved by FIX-2/FIX-3
exactly as handed off; drift D1/D2 were resolved by the FIX-1 landing
(`24f9523` carries `ga-fza-implementation-summary.md` per D2, and the
rebase onto `main` with the `gascity-test.el` union-conflict resolved
per D1); M1 remains the review's own no-action wording note and was
correctly left untouched. FIX-2's one behavior delta — a rig-repo-
resident caller now shares the city-root cache entry — is the intended
convergence REQ-009 mandates, and no caller depended on the old
isolation (R2, above).

## Verification

1. **Fix commits read in full.** `45ff9fb` (21+/21−, `lisp/gascity-formula.el` only) and `1725234` (118+/7−, test suite) reviewed line by line; `24f9523` confirms the land commit includes `ga-fza-implementation-summary.md` (D2) and the fix plan.
2. **Landing check (FIX-1).** `git merge-base --is-ancestor 1a78f7a origin/main` → true; `git worktree list` shows `worktrees/ga-fza` removed; `origin/main` tip is `1725234` with a clean tree (`plans/x.md` modification belongs to another workflow and was left alone, per the plan and `ga-wt7e`'s close note).
3. **Grep audit.** No `gascity-formula--city-key` definition or `file-remote-p` keying use survives in `lisp/gascity-formula.el`; every key computation goes through `gascity-context-scope-key`.
4. **Test-quality review.** The new `gascity-test-formula-cache-keys-by-scope-key` follows the house convention: real temp city trees with planted `city.toml` for the local legs, `cl-letf` stubs on the bang executors and `locate-dominating-file` for the TRAMP leg, the fictitious hosts never contacted, cache teardown via `gascity-context-clear-cache` in `unwind-protect`.
5. **Gate re-run.** `scripts/gate.sh` executed by this review at `1725234`: compile clean, **274/274, 0 unexpected**, `>>> gate: PASS`.
6. **No e2e re-run needed.** The fix is cache-identity only, no user-visible surface changes (the plan records this and the re-review concurs: no rendered string, buffer name, or gc invocation changes).