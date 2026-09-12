---
schema: gc.build.review.v1
workflow:
  id: ga-c0e
  formula: build-from-requirements
methodology:
  pack: gascity
  name: build-from-review-base
producer:
  formula: review
  stage: review
  attempt: 1
status: changes_required
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
    - path: git:90cdc6b9241ce3124e0567498fd5884848071295
      hash: git:90cdc6b9241ce3124e0567498fd5884848071295
      title: "Reviewed implementation chain tip (23462e5 -> a940623 -> 46c3706 -> 90cdc6b, base 69585b6)"
    - path: docs/qa/formula-sling-ui-e2e.md
      hash: sha256:80667081dd4b8da4c814e9c4c189e80189c65db939c96dcd7c8a1a82ab08c98c
      title: "tmux-Emacs TRAMP e2e acceptance pass (WI-4, in the reviewed chain)"
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
      rationale: "The porcelain-side halves are verified (both shapes' argv live; bindings and conventions intact), but the formula-dispatch half of the remote acceptance pass is blocked gc-side in bright-lights — review finding C2 / e2e report F3."
    - id: AC-7
      status: covered
    - id: AC-8
      status: covered
---

# Review report — formula-sling-ui implementation (review iteration 1)

Reviewed subject: the implementation chain `23462e5` → `a940623` →
`46c3706` → `90cdc6b` (base `69585b6`), i.e. the four work items of
implementation convoy `ga-x8m` as recorded in
`implementation-summary.md`. The review ran the full diff against the
approved requirements (`plans/formula-sling-ui/requirements.md`), re-ran
the quality gate in a throwaway worktree checked out at `90cdc6b`
(`/tmp/review-ga-1wy`), audited the 22 new ERT tests and the e2e dogfood
report, and traced every REQ-0xx row.

**Verdict: `changes_required`** — one blocking delivery finding (C1) and
one unresolved acceptance gap (C2). The reviewed code itself is sound;
nothing found requires a code rewrite.

## Verdict

- **Verdict:** `changes_required`
- **Blocking:** C1 (implementation stranded — the reviewed commits are
  not on `main`, on any branch, or pushed, and the rig working tree
  contains none of the code).
- **Unresolved (non-blocking for the code, blocking for full AC-6/AC-7
  acceptance):** C2 (gc-side formula instantiation broken in the
  bright-lights test city; porcelain behavior verified correct).
- **review_mode:** `agent` — the structured fix handoff is the
  "Fix handoff" section below; every required action is concrete.
- **Drift observations:** see the dedicated section (D1–D4).

Requirement coverage as reviewed:

| Requirement rows | Disposition | Evidence |
|---|---|---|
| REQ-001..003 (discovery) | pass | catalog picker w/ `:annotation-function`, clear `user-error` on empty/broken catalog, per-city-keyed session cache; e2e items 3, 10 |
| REQ-004 (generated section) | pass | pure children generation from `vars[]`, rebuilt on re-pick, nil-recipe degrades (e2e F1 fix + regression test) |
| REQ-005 (enum) | pass | choice option class, `completing-read` `require-match`; methodology fallback mapping per plan D1 |
| REQ-006 (boolean toggles) | pass | cycle infix for `true`/`false` defaults; observed in e2e (`open_pr` false→true) |
| REQ-007 (string options) | pass | `transient-prompt` method uses the var description; default seeds initial value; infix description self-documents name/required/description/default |
| REQ-008 (required enforcement) | pass | `gascity-formula--validate-values` runs before any gc call in `gascity-sling-formula--dispatch`; names all missing vars |
| REQ-009 (pattern) | pass | validated at entry in the string-option reader and again pre-dispatch; non-compiling pattern degrades to no check (REQ-016) |
| REQ-010/011 (history) | pass | per-(formula,var) ordinary history symbols; savehist persistence proven across an Emacs restart in e2e item 9 |
| REQ-012 (preview) | pass | preview re-runs `gc formula show` with current `--var`s (server-side substitution, plan-review F-1); `--dry-run` routing preview untouched |
| REQ-013 (both shapes) | pass | `--formula` targetless and `--on` targeted; shape from gc's documented drain/`{{convoy_id}}` rule; arg pre-seeded from bead/convoy at point; argv verified live in e2e item 7 |
| REQ-014 (TRAMP) | pass | all reads through the single reader/bang executors against the pinned `default-directory`; cache keys remote-qualified; preview buffers host-qualified; e2e over `/sshx:localhost:…bright-lights` |
| REQ-015 (bindings/conventions) | pass | `S` bindings untouched in all four views; `-f` repurposed as the formula-flow entry (drift D3); commits cite §5.2/§10 and the plan |
| REQ-016 (degradation) | pass | absent fields degrade everywhere; nil-formula crash fixed in `90cdc6b` with a regression test |
| REQ-017 (gate) | pass | `scripts/gate.sh` re-run by this review at `90cdc6b`: compile clean, 267/267 tests |
| REQ-018 (e2e) | blocked (half) | dogfood report exists and is thorough; the non-formula live sling succeeded (`bl-c3x` + convoy `bl-ohb` in the remote store), but the formula-dispatch half is blocked gc-side — see C2 |

### Traceability

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

AC-6 is `blocked` because the formula-dispatch half of the remote
acceptance pass (REQ-018) is blocked gc-side in bright-lights — see
finding C2 (e2e report F3). The porcelain-side halves of AC-6 (both
shapes' argv verified live; bindings and DESIGN conventions preserved)
are covered.

## Findings

### C1 — BLOCKING (delivery/drift): the implementation is stranded off `main`

The reviewed chain (`23462e5`, `a940623`, `46c3706`, `90cdc6b`) is
reachable from no branch, no tag and no remote: `main` sits at `ed28c2b`
(one commit past the chain base `69585b6`, containing only the unrelated
rig-registration commit), `origin/main` does not contain the chain, and
the rig working tree at `/home/roman/workspace/gascity.el` contains
**none** of the implementation (7 files, +1680/−24; only `M AGENTS.md`
and untracked `plans/` are present). The workflow-root metadata claims
the subject is "gascity.el@main implementation of formula-sling-ui" —
main has nothing to show for it. AGENTS.md is explicit: work left only
in the working tree or a local branch is considered stranded.

This is mechanical to repair, not a code problem:

- `scripts/gate.sh` **PASSES** at `90cdc6b` (verified by this review in
  `/tmp/review-ga-1wy`: `eldev compile --warnings-as-errors` clean +
  267/267 tests).
- `git merge-tree` shows the chain merges into `main` with **zero
  conflicts** (merge-base `69585b6`; main's only extra commit touches
  nothing the chain touches).
- The per-item worktrees under `worktrees/ga-*` are disposable; the
  canonical chain tip is `90cdc6b`.

Additionally, the workflow's own artifacts are untracked: `plans/`
(requirements, plan, decomposition, four item summaries, this report)
and the `AGENTS.md` hunk adding the "Remote test city & e2e testing"
section that the QA report cites. Neither is recoverable from a fresh
clone; both must land on `main` with the code.

### C2 — UNRESOLVED (acceptance gap, gc-side environment): formula dispatch not confirmable in bright-lights

The tmux-Emacs TRAMP acceptance pass (docs/qa/formula-sling-ui-e2e.md,
F3) shows every formula instantiation in the remote test city fails
inside gc — `unknown formulas v2 target "gc.run-operator"` — reproduced
with plain gc over ssh for every catalog formula, after `gc reload` and
`gc restart`, while the same formulas instantiate fine in the local
city emacs-city and `gc doctor` passes 89 ✓. The porcelain is
exonerated (right argv, clean `user-error`), and the non-formula live
sling over TRAMP succeeded and was confirmed in the remote store, but
the "dispatch a formula sling and confirm the workflow root appears in
the store" half of REQ-018/AC-6 remains unverified against
`/ssh:localhost:/home/roman/bright-lights`. This is a bright-lights
configuration/agent-pack issue, not gascity.el code; it must be resolved
and the formula-dispatch half of the acceptance pass re-run before the
feature is called done.

### M1 — minor: `gascity-formula-invalidate` is dead code

Its docstring claims it is "called by an explicit refresh binding and by
re-picking 'refresh catalog' in the picker"; in the reviewed tree
nothing calls it — the session-lifetime catalog/recipe caches can only
be cleared from `ielm`. Either wire it (a picker entry or a refresh key
that also invalidates the formula caches) or correct the docstring.
Stale-recipe risk after editing a formula within one Emacs session.

### M2 — minor: client-side `pattern` validation uses Emacs regexp syntax

`gascity-formula--check-pattern` compiles the declared pattern with
`string-match`; gc's patterns may be RE2/Go-flavored (`\d`, lookahead,
`\p{L}`) and fail to compile or match differently under Emacs. The
`invalid-regexp → no validation` degradation is the approved REQ-016
behavior, so a constraint can silently pass client-side and fail at gc.
Acceptable (gc remains the authority), worth remembering when someone
ships formulas with patterns.

### M3 — minor (drift, intentional): `-f` in `gascity-sling-dispatch` changed meaning

From a `--formula` flag toggle to the formula-flow entry point. The
requirements' Out-of-Scope says the non-formula path keeps "today's
behavior, including the existing flag infixes"; the old bare-flag path
(type the formula name blind) is no longer reachable from `S`. The
formula flow supersedes it and all other flag infixes are untouched;
the tradeoff is documented in the `46c3706` commit body. Recorded as
intentional; no action.

### M4 — minor: generated infixes alias an internal transient function

`gascity-sling-formula--set-var` is `transient--default-infix-command`
(internal API), verified against transient 0.13.8 in the e2e pass.
Version coupling is real but narrow; acceptable for an experimental
package.

## Verification

- `scripts/gate.sh` at `90cdc6b` in throwaway worktree
  `/tmp/review-ga-1wy` — **PASS**: `eldev compile --warnings-as-errors`
  clean over the whole package; 267/267 tests green (this review's own
  run, 2026-09-12 18:27).
- `git merge-tree <merge-base> main 90cdc6b` — 0 conflict markers;
  chain lands on main cleanly.
- ERT audit: 22 new `gascity-test-formula-*` / `-sling-on-` /
  `-formula-command-lines` tests follow the house convention (`cl-letf`
  stubbing of the reader bang executors and the action verbs; no live
  city needed). The transient-setup gap that the mocks missed (e2e F2)
  is exactly the gap AGENTS.md warns about; it is now closed by the
  acceptance pass plus the F1/F2 regression tests.
- Commit audit: subjects follow `type(scope): summary`; bodies cite the
  plan decisions and DESIGN-write-actions.md §5.2 (REQ-015).
- e2e dogfood report `docs/qa/formula-sling-ui-e2e.md` exists and meets
  the AGENTS.md protocol (fresh Emacs inside tmux, remote city, captured
  screen text, live store confirmation) — except the formula-dispatch
  half, blocked gc-side (C2).
- This artifact validated with `validate_build_artifact.py --schema
  gc.build.review.v1` before recording.

## Drift observations

- **D1 (subject metadata vs reality):** root metadata records the
  review subject as "gascity.el@main implementation", but main contains
  none of the implementation (see C1). This review treats the reviewed
  chain as the subject of record and its tip hash is in `trace`.
- **D2 (untracked artifact tree):** the entire `plans/formula-sling-ui/`
  tree and the `AGENTS.md` e2e-section hunk are uncommitted on the rig
  working tree; the store's artifact paths will not resolve from a fresh
  clone until they are committed (folded into C1's required action).
- **D3:** intentional `-f` semantics change, recorded as M3.
- **D4 (environment):** the e2e pass ran over TRAMP method `sshx` with a
  private ControlPath because plain `ssh` hangs on this host (QA F4);
  documented deviation from the literal `/ssh:` path in REQ-018.
- **D5 (environment):** status-dashboard auto-refresh timer busy-spins a
  sync TRAMP read started from inside a transient (QA F5); repro recorded,
  separate investigation owed.

## Fix handoff (review_mode=agent)

Ordered, concrete actions for the selected fix loop
(`review_fix_formula=fix-loop-base`); C1 first, everything else can go
in the same or a later repair iteration.

1. **F-C1 (blocking — deliver the work):** merge the implementation
   chain onto the rig's `main` and push, per AGENTS.md session
   completion:
   - `git merge 90cdc6b` on `main` (clean; alternatively cherry-pick
     `23462e5 a940623 46c3706 90cdc6b` in order).
   - Commit the workflow artifacts on `main`: `plans/` (including this
     report) and the `AGENTS.md` "Remote test city & e2e testing" hunk.
   - Re-run `scripts/gate.sh` **on main** after the merge and push
     (`git pull --rebase && git push`, `git status` clean vs origin).
   - Clean up the disposable `worktrees/ga-*` checkouts afterwards.
2. **F-M1:** wire `gascity-formula-invalidate` into a user-reachable
   refresh affordance (or fix its docstring); add/adjust the ERT stub
   accordingly. Safe fix, no design impact.
3. **F-C2 (acceptance closure, outside gascity.el):** resolve
   bright-lights' `unknown formulas v2 target "gc.run-operator"` (pack
   roles / agent import state on the remote city), then re-run the
   formula-dispatch half of the tmux-Emacs TRAMP acceptance pass and
   append the result to `docs/qa/formula-sling-ui-e2e.md`.
4. Record `gc.build.review_fix_attempt_count` (starting at 0 for this
   handoff) and keep C2's unresolved status on the workflow root until
   step 3 completes.

No code changes were made by this review stage (review_mode=agent:
findings recorded, repairs owned by the fix loop).