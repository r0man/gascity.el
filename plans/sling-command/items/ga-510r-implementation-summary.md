---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-81eo
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
    - path: beads/ga-510r
      hash: bead:ga-510r
      ids: [REQ-001, REQ-002]
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: lisp/gascity-formula.el
      hash: git:8fc52c0
    - path: lisp/gascity-action.el
      hash: git:8fc52c0
    - path: lisp/test/gascity-sling-test.el
      hash: git:8fc52c0
    - path: lisp/test/gascity-test.el
      hash: git:8fc52c0
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
---

# WI-1 — Shape inference and the one-sentence header

Work item WI-1 of the sling command redesign, implemented in the
per-bead worktree `/home/roman/workspace/gascity.el/worktrees/ga-510r`
(commit `8fc52c0`, source anchor `ga-510r`).

## Summary

The sling menu's header no longer lists raw scope fields. It is now one
sentence that states the inferred sling shape: `gascity-sling--shape`
infers `plain` / `formula` / `on` from the work + formula selections,
and `gascity-sling--header-sentence` renders the signed-off mockup
§1–§4 wording. `gascity-sling--scope-info` (the transient's `:info`
header spec) now carries that sentence instead of the old
`Arg: … · Formula: … · Target: …` field list. Everything is display
only: dispatch keeps `gascity-formula--needs-convoy` as the
authoritative shape rule and gained no new blocking prompt.

## Intended Behavior

- `gascity-sling--shape` over (work, formula): no formula ⇒ `plain`;
  formula + non-blank work ⇒ `on` (`--on`); formula without work ⇒
  `formula` (`--formula`). Display only — dispatch re-derives the real
  shape through `gascity-formula--needs-convoy` (plan D2).
- `gascity-sling--header-sentence` over (work, formula, target, recipe)
  with the exact mockup wordings:
  - §1 plain: `Sling bead bl-5ja to mayor`
  - §2 cold: `Sling (no work — A or point at a bead) to (no target — T or default)`
  - §3 formula: `Run pancakes (formula) on mayor`
  - §4 on: `Run build-basic against bead bl-5ja, drained by hello-world/gc.implementation-worker`
- The `drained by` clause consults `gascity-formula--needs-convoy` on
  the cached recipe passed in; a recipe that needs no convoy renders
  `on <target>` like the `--formula` shape, and a nil recipe (cold
  cache) degrades to the same wording — no synchronous gc read on a
  render path (D9).
- A bead/convoy id in the work slot renders as `bead <id>`; freeform
  task text renders as the text itself; blank slots render the mockup
  §2 hints.
- `gascity-sling--scope-info` reads the work from `:work` (falling back
  to the legacy `:arg` slot) and passes the recipe the menu setup
  already read, so the header never doubles the cached read.

## Changed Files

- `lisp/gascity-formula.el` — new section "Shape inference and the
  header sentence": `gascity-sling--shape`,
  `gascity-sling--work-id-p`, `gascity-sling--work-phrase`,
  `gascity-sling--target-phrase`, the two mockup §2 hint constants,
  and `gascity-sling--header-sentence` (all pure).
- `lisp/gascity-action.el` — `gascity-sling--scope-info` now takes the
  cached RECIPE and renders the sentence; `gascity-sling--children-specs`
  passes its already-read recipe through; a forward
  `declare-function` for the renderer.
- `lisp/test/gascity-sling-test.el` — new tests:
  `gascity-test-sling-shape-inference` (every shape × work-presence
  combination),
  `gascity-test-sling-header-sentence-mockups` (exact §1–§4/§5a
  sentences),
  `gascity-test-sling-header-sentence-partial-scopes` (hint stand-ins,
  freeform text),
  `gascity-test-sling-header-sentence-non-convoy-recipe` (non-convoy
  and nil-recipe degradation),
  `gascity-test-sling-scope-info-renders-the-sentence` (header wiring,
  `:work`/`:arg` fallback); drain/plain recipe fixtures.
- `lisp/test/gascity-test.el` — the header-pinning tests updated from
  the old field list to the sentence:
  `gascity-test-sling-unified-layout`,
  `gascity-test-sling-target-set-and-header`,
  `gascity-test-sling-arg-edit-re-setups-in-place`.

## Verification

First verification command (from the worktree):

    bash scripts/gate.sh

Observed: FAIL — `eldev compile` passed, test loading failed with
"Invalid read syntax: \")\", 1678, 96" (one extra closing paren in the
rewritten `gascity-test-sling-unified-layout` assertion); fixed, and a
full-suite rerun also surfaced one unexpected result
(`gascity-test-agent-detail-follow-log-stderr-goes-with-it`) which
passes both alone on the clean tree and in a full-suite rerun —
a timing flake, unrelated to this change (no agent/terminal code
touched).

Final proof command (from the worktree):

    bash scripts/gate.sh

Observed: PASS — byte-compile clean under `--warnings-as-errors`,
`eldev test` green: `Ran 671 tests, 671 results as expected, 0
unexpected`. The five new WI-1 tests pass and pin every shape ×
work-presence combination and the exact mockup sentences.

Non-blocking D9: no new synchronous gc anywhere — the header renders
from the scope plus the recipe the setup already cached, and a nil
recipe degrades instead of reading.

## Remaining Risks

- The `on`-shape sentence for a formula that needs no convoy
  (`Run <formula> against bead <id>, on <target>`) and the nil-recipe
  degradation are not pinned by a mockup (the mockups only show the
  drain case); wording chosen for consistency with §3's `on <target>`.
  WI-4/WI-6 may revisit when the adaptive layout and live footer land.
- The work-slot bead-id heuristic (`[a-z0-9]+-[a-z0-9]+`) classifies
  dash-joined single-word freeform text as a bead id in the sentence;
  cosmetic only. WI-4's `A` picker generalizes the slot to `:work` and
  can carry a real kind.
- A convoy-requiring formula with no work still hits the pre-existing
  dispatch-time `user-error`; per the plan it becomes the mockup §5c
  footer warning with WI-2 (missing-pieces checks) and WI-6 (live
  footer), which are separate work items in this convoy.
- The interactive bright-lights end-to-end pass for the redesigned menu
  is WI-11's scope, not this item's.

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
