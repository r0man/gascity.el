---
schema: gc.build.review.v1
workflow:
  id: ga-rv5
  formula: build-from-requirements
methodology:
  pack: gascity
  name: review
producer:
  formula: review
  stage: review
  attempt: 1
status: changes_required
trace:
  upstream:
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved requirements artifact (gc.build.requirements.v1; matches root metadata gc.build.requirements_hash)"
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
      title: "Approved implementation plan (matches root metadata gc.build.plan_hash; D1 records the @<city-root> qualifier shape)"
    - path: plans/multi-city-keying/build/decomposition.md
      hash: sha256:7c4b2f3a120c2a59c46656bf50dd180cd5b9991caaee614002ca1e56bb0e8c20
      title: "Work-item decomposition (WI-1..WI-4, convoy ga-wxj)"
    - path: plans/multi-city-keying/build/plan-review.md
      hash: sha256:93a98b10c8667e12cc31967d4258da259135a204e967925f8d24303d8b7a0ca5
      title: "Plan review (advisory: no formula-cache module existed at decomposition time → REQ-010 governs)"
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
      title: "Reviewed implementation chain tip, commit 4/4: docs(qa) dual-city tmux-Emacs e2e pass (docs/qa/2026-09-10-multi-city-keying.md)"
    - path: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      hash: git:96727cd8cf0e9900e3bc23d5f8e2b8b74fd7de65
      title: "origin/main tip: formula-sling-ui landed here AFTER this branch forked (merge-base 69585b6) — brings lisp/gascity-formula.el with its own cache keying (finding C1)"
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

# Review report — multi-city-keying implementation (review iteration 1)

Reviewed subject: implementation convoy **ga-wxj** (4 drain items, all
pass), delivered as the chain `a4e3ab8` → `75423fa` → `719042e` →
`e75c5f7` on top of merge-base `69585b6`, in worktree
`worktrees/ga-fza`. The chain re-keys gascity.el's city-scoped state
onto one `gascity-context-scope-key` identity: the governing city root
(buffer names, rig-list memo, terminal attach) with the remote-prefix
fallback outside any city.

**Verdict: `changes_required`** — one blocking finding (C1), caused by
the formula-sling-ui caches landing on `main` after this branch forked.
The porcelain re-keying itself is well-executed and fully verified; the
fix is small and bounded (re-key `gascity-formula`'s caches onto the
shared helper). No findings against the delivered WI-1..WI-4 code
itself.

## Verdict

- **Verdict:** `changes_required`
- **Blocking:** C1 — REQ-009's "one key helper, one API" clause is
  violated on the merged result (see Findings).
- **Unresolved:** none besides C1.
- **review_mode:** `agent` — the structured fix handoff for the
  fix-loop stage is the FIX-1 block under finding C1.
- **Existing fix-attempt count:** 0 (first review iteration;
  `gc.attempt=1` on the review step; no fix loop has run for this
  workflow yet).

Requirement disposition (reviewed against
`plans/multi-city-keying/requirements.md` REQ-001..016):

| Requirement rows | Disposition | Evidence |
|---|---|---|
| REQ-001 (city-root buffer qualification, local cities included) | pass | `gascity-view-get-buffer-create` computes the governing root once and passes it as `gascity-remote-buffer-name`'s new QUALIFIER (`gascity-context.el` view factory, commit `75423fa`); test `gascity-test-buffer-name-per-city` asserts the D1 shapes `*gascity-status@/home/…/emacs-city/*` and `*gascity-status@/ssh:u@h:/city/*` |
| REQ-002 (host-only shape outside any city) | pass | Factory falls back to `(file-remote-p dir)`; nil remote keeps BASE bare; asserted in `gascity-test-buffer-name-per-city` and the extended `gascity-test-remote-buffer-name` |
| REQ-003 (exactly one scheme, documented, one naming function) | pass for view/attach call sites (see C1 for the formula caches) | Only two `gascity-remote-buffer-name` callers exist: the factory and `gascity-terminal-attach-tmux` (which derives the same qualifier and is documented as the one intentional non-factory site). Scheme ownership documented in both module commentaries |
| REQ-004 (coexistence, no cross re-pin) | pass | Per-city buffer names make cross-city buffer lookup impossible; factory pins `default-directory` to the governing root of its own DIR. Unit-tested; e2e QA report checks 1–3 |
| REQ-005 (rigs memo keyed by city root + remote prefix) | pass | `gascity-context--rigs-key` delegates to `gascity-context-scope-key`; the key embeds the TRAMP prefix (the root is TRAMP-qualified), so one TRAMP connection hosting two cities still partitions |
| REQ-006 (prefix-less guard per city) | pass | `gascity-rigs-remember` computes the key first and guards against `old` under that key only; asserted for local and TRAMP city pairs in `gascity-test-rigs-memo-per-city` |
| REQ-007 (cold stays cold, no gc from UI path) | pass | `gascity-context-scope-key` uses only the memoized `gascity-context--root-cache` walk; `gascity-test-rigs-cached-never-spawns` and `-rigs-memo-per-city` stub `gascity-reader-run`/`-rig-list!` to error and a third city stays cold |
| REQ-008 (clear-cache clears every city) | pass | `gascity-context-clear-cache` `clrhash`es the whole memo (plus root/city/rig caches and remote executables); asserted in `gascity-test-clear-cache-cities` |
| REQ-009 (formula caches, if landed, key via the shared API) | **fail** | See C1: the formula caches landed on main with an independent key |
| REQ-010 (ship the shared helper + record the integration point) | pass | `gascity-context-scope-key` shipped; the module commentary in `gascity-context.el` names the formula catalog/recipe caches as the next consumer |
| REQ-011 (override keys by the overridden root) | pass | `gascity-context-city-root` consults the override first, never caches it; `gascity-test-override-keys-by-overridden-root` proves the override-opened buffer is distinct and A's buffer untouched |
| REQ-012 (single override variable unchanged) | pass | `gascity-context-city-root`'s override branch is byte-identical in meaning to before |
| REQ-013 (single-city users, plan records the name shape) | pass, with M1 wording note | Plan D1 records the `@<city-root>` splice shape; no-city dirs keep the unchanged host-only/bare shape. See M1 for the QA report's self-contradictory sentence |
| REQ-014 (ERT: two local cities + two cities under one TRAMP prefix, distinct keys/values; existing remote tests keep passing) | pass | `gascity-test-rigs-memo-per-city`, `-scope-key-per-city`, `-buffer-name-per-city`, `-clear-cache-cities`, `-override-keys-by-overridden-root`; all 252 tests green (Verification) |
| REQ-015 (tmux-Emacs dual-city e2e, both cities simultaneously, docs/qa/ report) | pass | `docs/qa/2026-09-10-multi-city-keying.md` (commit `e75c5f7`): ten coexisting city-keyed buffers over `/sshx:localhost:` + local, per-city memo keys and prefixes read back from the live session; sshx-not-ssh deviation documented with a standalone repro |
| REQ-016 (`scripts/gate.sh` passes) | pass | Re-run by this review in the worktree at `e75c5f7`: compile clean + 252/252 (Verification) |

### Traceability

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |

## Findings

### C1 — BLOCKING (REQ-009): the formula-sling-ui caches landed on main with a second, independent keying scheme

`main` advanced past this branch's merge-base (`69585b6`) with the
formula-sling-ui chain (`02304e3` → … → `96727cd8`), which added
`lisp/gascity-formula.el`. Its caches key by `gascity-formula--city-key`
= `(concat (file-remote-p dir) (expand-file-name dir))` — a *different*
city identity from `gascity-context-scope-key`, with three concrete
divergences once this branch lands:

1. **Two keying schemes.** REQ-009 (and REQ-003's "exactly one keying
   scheme") require the formula caches to key by the shared
   `gascity-context` API. `gascity-formula--city-key` neither calls it
   nor derives the same value.
2. **Not the governing root.** The formula key hashes the raw
   `default-directory`, not the memoized city-root walk: a caller whose
   `default-directory` is a rig repo *inside* a city (rig dashboards pin
   views to the city root, but at-point actions and programmatic callers
   do not have to) gets a different key than the city root — a cache
   split the shared scheme cannot produce.
3. **Override blindness.** `gascity-context-scope-key` honours
   `gascity-context-city` (REQ-011); `gascity-formula--city-key` does
   not, so under an override the formula caches and the view/rig keys
   disagree.

There is no data-contamination bug today (the formula key is still
per-city distinct), which is why this was invisible to the dual-city
e2e pass — but the merge result violates the approved requirements, and
the requirements make the clause mandatory now that the caches have
landed. The branch could not have pre-empted this (the module did not
exist at the fork point; plan-review advisory confirmed REQ-010
governing), so this is a land-time integration item, not a WI-1..WI-4
implementation defect — but it must be fixed before the workflow
finalizes on a tree that carries both schemes.

**Fix handoff (for the fix-loop stage, review_mode=agent):**

- **FIX-1** — Make `gascity-formula--city-key` delegate to
  `gascity-context-scope-key` (or replace its uses with the helper
  directly): the catalog cache, the recipe cache, and
  `gascity-formula-invalidate` all key by the one shared identity
  (REQ-009, REQ-003). Rebase the branch onto `main` first (the module
  only exists there).
- **FIX-1 tests** — Extend the formula-cache tests: two local cities
  hold distinct catalog/recipe entries; two cities under one TRAMP
  prefix stay distinct; a `gascity-context-city` override keys the
  caches by the overridden root (REQ-011, REQ-014); the existing
  per-city formula tests keep passing under the shared key.
- **FIX-1 docs** — Update `gascity-formula.el`'s cache commentary to
  name `gascity-context-scope-key` as the keying identity (dropping the
  local "remote-qualified directory" description), so exactly one
  documented scheme remains.

### M1 — Minor (REQ-013 wording): the QA report's user-visible-surface paragraph is self-contradictory

`docs/qa/2026-09-10-multi-city-keying.md` states "Local-city
single-city users are unaffected" and, in the same paragraph, records
that local cities *do* now qualify by their absolute city root and that
this is "the one user-visible churn of the re-keying". The behavior is
correct and exactly what REQ-001 mandates (local cities MUST get
distinct city-root-qualified names) and what plan D1 records; REQ-013
is satisfied in its reconciled reading (data, pinning and timers
unchanged; the name shape changes as REQ-001 requires and the plan
records it). Only the "unaffected" sentence overstates. No action
required; fix the sentence opportunistically if the file is touched
again.

### D1 — Drift observation: implementation branch stranded off main, main moved under it

The reviewed chain lives on detached HEAD in `worktrees/ga-fza`
(merge-base `69585b6`); `main` is `f8a1f6e` and carries the whole
formula-sling-ui chain. This is expected mid-workflow (a later stage
owns landing), but the land step should note that both chains modified
`lisp/test/gascity-test.el` heavily (this branch +406 lines; the
formula chain rewrote large parts of the same file) — expect rebase
conflicts there, plus trivial ones in module commentaries. FIX-1's
rebase is the natural point to resolve them.

### D2 — Drift observation: `gc.build.review_subject` base reference

The workflow root's `gc.build.review_subject` names "implementation
convoy ga-wxj (4 drain items, all pass)". For the record: the four
drain summaries live at
`plans/multi-city-keying/build/ga-{3fe,dpu,eu6,fza}-implementation-summary.md`
and match the four chain commits; `ga-fza`'s summary is currently
untracked on `main` (committed only on the chain). The land commit
should include it.

## Verification

1. **Full diff read.** `git diff 69585b6..e75c5f7` — 5 files: the two
   re-keyed modules (`gascity-context.el`, `gascity-remote.el`), the
   attach-buffer call site (`gascity-terminal.el`), the test suite
   (+406 lines), and the QA report. No other porcelain file touched;
   scope matches the requirements' "How much".
2. **Requirement-by-requirement audit** — the disposition table above,
   each row checked against the actual code (not the summaries) in the
   worktree.
3. **Gate re-run (REQ-016, AC-5).** `scripts/gate.sh` executed by this
   review in `worktrees/ga-fza` at `e75c5f7` (clean tree): whole-package
   `eldev compile --warnings-as-errors` clean, full ERT suite
   **252/252, 0 unexpected** (`>>> gate: PASS`). Independent
   confirmation of the summaries' and QA report's gate claims.
4. **E2E report audit (REQ-015, AC-4).** Read
   `docs/qa/2026-09-10-multi-city-keying.md` in full: PASS/FAIL matrix
   of ten checks with live buffer inventories and per-city memo state
   read back via `emacsclient`; deviation (sshx vs ssh) is evidenced by
   a standalone batch repro and correctly scoped as an environment
   issue; the report honestly records the mid-pass worktree deletion
   incident. The e2e acceptance gate per AGENTS.md has run against both
   cities simultaneously.
5. **Test-quality review.** The new tests stub the gc boundary per the
   house convention (`cl-letf` on `gascity-reader-run` /
   `gascity-command-rig-list!` / `locate-dominating-file`), use real
   temp cities for local walks, assert the *counter-examples* from the
   requirements' example mapping (identical lists don't evict,
   prefix-less never blanks per city, cold stays cold, override doesn't
   disturb the natural buffer), and never contact the fictitious
   `/ssh:u@h:` host.
