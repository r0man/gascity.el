---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-9esm
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-gonl
      hash: bead:ga-gonl
      ids:
        - REQ-013
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: lisp/test/gascity-sling-test.el
      hash: sha256:a7d9192c6affbd0323df542bc30844ff9700f892345cba307fdcb9c5cfd45b92
    - path: lisp/test/gascity-test.el
      hash: sha256:280b304aacc5e07314691b28d37f811d1d886135867da4a70bcb42947b93eedf
    - path: lisp/test/gascity-test-helpers.el
      hash: sha256:2ff6b311fb8e8de63ac284b3338fc68ec76e1dc0ea94342c3b29634a660edcaf
    - path: lisp/test/gascity-store-test.el
      hash: sha256:b2a298180c4c839f345ac71f84167759d81d06cb8b3caccac35c753b67a0c64b
    - path: lisp/test/gascity-agents-test.el
      hash: sha256:203c81dbcd9822e78b57ca79ff1ee3ac93b5cce436d7b56dd06821b9b725014a
  coverage:
    - id: REQ-013
      status: covered
---

# Implementation summary — WI-10: ERT consolidation (ga-gonl)

## Summary

Work item WI-10 of the sling command redesign is implemented in
worktree `worktrees/ga-gonl`, commits `d8a57d8` ("test(agent): the
stderr-race assertion only pins the note's stderr line") and `426d2fd`
("test(sling): port the sling suite to the redesign layout (WI-10)"),
on top of origin/main `69eed1c`.  Because the redesign itself
(WI-1..WI-9) lands as parallel drain waves and none of it is on
origin/main yet, the consolidated suite is written against the
redesign's specified behavior and runs against whichever layout the
load path presents: a new helper `gascity-test-sling-redesign-p` tells
the generations apart by the reserved set (`P` present, `p` freed —
mockup §10), redesign-coupled tests skip until WI-1..WI-9 land, and
tests of retained plumbing run under both.  The seven
`gascity-sling-test.el` tests are ported (`p`→`P` full preview, `A`/`T`
pickers, scope `:work`); the nine redesign contracts get new tests
(shape inference, header sentence, typed-var heuristics, Who default
derivation, the bl-bdj trap warning, the cross-store warning, the
follow offer, footer recompute, the reserved set); every layout-coupled
sling test in the shared suite `gascity-test.el` is ported the same
way; the non-blocking guard list in `lisp/test/gascity-store-test.el`
gains the input-free `P` preview verb; and the one pre-existing flake
that blocked a green gate (the follow-log stderr race, QA #11) is
fixed with the operator's accepted resolution.  Everything stubs the
gc boundary (`gascity-test-with-store-stubs`, `cl-letf` on the reader
functions), so the suite stays offline and fast.

## Intended Behavior

Per `plans/sling-command/implementation-plan.md` WI-10 and the source
anchor bead ga-gonl (REQ-013):

- **Two generations, one suite**: the redesign rewrites the sling
  transient's layout while WI-10's suite lands in a parallel wave, so
  a ported test must not fail the gate on a base without the
  redesign.  `gascity-test-sling-redesign-p` pins the generation test
  to a real observable (the reserved set), not to a version variable;
  ported and new redesign tests `skip-unless` on it, and
  layout-agnostic tests (command-line shapes, cache behavior, var-key
  determinism, city pinning, the S-1 picker union) run under both.
- **Ported S-1/S-2 regressions** (REQ-011/012): the picker union and
  prefetch tests are untouched (retained plumbing); the preview test
  now pins `P`'s full preview — the dry run started through the store
  on the action lane, the menu keeping its scope (`:work`, `:target`),
  `s` then slinging without prompting and forgetting the city; the
  re-entry test pins remembered state under the `:work` scope key with
  `x` clearing and forgetting.
- **New redesign contracts**: shape inference (`gascity-sling--shape`
  from (work, formula), never flags); the one-sentence header (mockup
  §1–§4 wording, asserted through the layout's header group via the
  `gascity-test-sling-header-text` helper so the renderer's `:info`
  split stays free); typed-var heuristics (`*_path` file,
  `artifact_root` directory, `*_target` agent, all-digit default and
  `max_*`/`*_iterations` numeric, unrecognized string — and `rig_name`
  stays a string); Who default derivation order (per-(city, formula)
  target memory, then exactly one rig-scoped
  `gc.implementation-worker`, ambiguity derives nothing); the bl-bdj
  trap warning (binding-qualified run targets fail against a
  city-scoped agent — the footer carries the §5a wording, a rig-scoped
  target shows ✓); the cross-store warning (the work bead's store vs
  the target's, §5b); the follow offer (`Launched workflow <id>
  (…)` + momentary `F` to `gascity-run-show`, nothing on the plain
  route, §9); footer recompute as a pure function of (scope, roster,
  recipe); the reserved set matching mockup §10 exactly.
- **Shared-suite ports** (WI-10's enumerated set): the var/reserved
  tests against the new key set and typed classes (`-var-children-shapes`
  now asserts the `How — <formula> vars` title, the file/numeric
  classes and the fail-soft string; `-reserved-keys-complete` carries
  both scope keys so it stays in sync with whichever layout is bound);
  the transient tests the `--children-specs`/`--run` rewrite touches
  (`-unified-wiring`, `-unified-layout`, `-target-set-and-header`,
  `-arg-edit-re-setups-in-place`, `-dispatch-target-fallback`,
  `-plain-path-unchanged`, `-preview-dry-run-paths`) are ported to the
  redesign's agents roster, derived default and zero-prompt seeded
  `s`; `-dispatch-suffixes-run-pinned` keeps its pinning assertions
  under both generations' target reads.
- **Non-blocking guard (D9)**: the `P` preview is input-free (it
  paints its buffer client-side and starts the dry run on the action
  lane), so the guard list in `lisp/test/gascity-store-test.el` gains
  it behind the same redesign gate.
- **QA #11 flake fixed with the accepted resolution**: the follow-log
  stderr line races the sentinel that writes the end note; the race is
  inherent to pipe scheduling, so the assertion now pins the note and
  the stderr buffer's death and asserts the line whenever it arrived —
  the operator's accepted fix in worktrees/ga-o6eh (cc5d836), ported
  so this worktree's gate is green too.  (An alternative production
  fix — draining the sentinel's stderr pipe until EOF — was tried in
  this worktree and measured not to fix the flake: 2 of 5 single-test
  runs still failed with it, 0 of 8 with the accepted resolution.)

## Changed Files

- `lisp/test/gascity-sling-test.el` — the seven tests ported to the
  redesign (`P` preview through the store, `A`/`T` pickers, `:work`
  scope); fixtures for the redesign tests (drain/v2 step recipes, a
  rig-scoped roster); new tests for shape inference, the header
  sentence, typed-var heuristics, the title slug, Who default
  derivation, the bl-bdj trap and cross-store warnings, the follow
  offer, footer recompute and the reserved set — all skip-gated on
  `gascity-test-sling-redesign-p`.
- `lisp/test/gascity-test.el` — the enumerated layout-coupled sling
  tests ported (`-unified-wiring`, `-unified-layout`,
  `-target-set-and-header`, `-arg-edit-re-setups-in-place`,
  `-dispatch-target-fallback`, `-plain-path-unchanged`,
  `-preview-dry-run-paths`, the var/reserved shapes tests, and the
  `:work`-key sync in `-reserved-keys-complete`); generation-agnostic
  dual branches where a test covers both layouts.
- `lisp/test/gascity-test-helpers.el` — `gascity-test-sling-redesign-p`
  (the generation test) and `gascity-test-sling-header-text` (join the
  header group's strings under store stubs).
- `lisp/test/gascity-store-test.el` — the non-blocking guard list
  gains the `P` preview verb (behind the redesign gate).
- `lisp/test/gascity-agents-test.el` — the QA #11 stderr-race
  resolution (separate commit `d8a57d8`, mirroring the operator's
  cc5d836 in worktrees/ga-o6eh).

## Coverage

| ID | Status |
| --- | --- |
| REQ-013 | covered |

## Verification

First verification command (from the worktree, while porting):

    eldev test sling

observed: PASS — 46 tests, 27 passed, 19 skipped (the redesign-gated
set — the redesign is not on this base yet), 0 unexpected
(2026-09-27 18:46).

Final proof command (from the worktree, the repo's standard gate):

    scripts/gate.sh

observed: PASS — `eldev compile --warnings-as-errors` clean and the
full ERT suite green: 676 tests, 657 results as expected, 19 skipped
(the same redesign-gated set), 0 unexpected (2026-09-27 18:52).  The
flaky follow-log test ran 8/8 green after the QA #11 resolution.

The artifact validator (`.gc/scripts/checks/build-artifact-valid.sh`,
schema `gc.build.implementation-summary.v1`) was run from the rig root
against this summary and passed before closing the step.

## Remaining Risks

- **The 19 skips are the point, and the risk**: the redesign-coupled
  assertions are unproven until WI-1..WI-9 merge and the tests
  activate.  Where the plan leaves an implementation name unpinned,
  the tests assert through pinned surfaces instead (`:info` spec shape
  and `gascity-sling--children-specs` for the header; `:work` scope
  key and `gascity-sling--reserved-keys` for the layout; the store's
  action list for the preview/run) — if WI-1..WI-9 name those
  surfaces differently, the tests will fail loudly at merge time
  rather than silently pass, which is the intended failure mode.
- **The follow-offer's workflow-root field is unpinned**: the plan
  leaves which sling-launch response field names the created workflow
  root to the e2e pass (WI-11); the test accepts any of
  `id`/`workflow_id`/`root_bead_id`/`workflow_root_id` and asserts the
  offer announces the same id.  WI-11 pins the real field.
- **QA #11 resolution duplicated across waves**: this worktree and
  worktrees/ga-o6eh (cc5d836) carry the same test-side fix; when the
  waves merge, git resolves it as the identical change.  If a third
  wave's base predates both, its gate can still flake once before the
  fix reaches it.
- **No live sling exercise**: WI-10 is offline by contract; the
  interactive TRAMP acceptance (bright-lights, the four REQ-014
  scenarios) is WI-11's deliverable and was not run here.