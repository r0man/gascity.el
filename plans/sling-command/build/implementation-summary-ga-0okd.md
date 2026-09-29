---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-ylw9
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
    - path: beads/ga-0okd
      hash: bead:ga-0okd
      ids:
        - REQ-005
        - REQ-010
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: lisp/gascity-agents.el
      hash: sha256:e507a72f1e80f2dd7497d7656a7216f2d422c4c22b2504c21e2dd4e137ea8817
    - path: lisp/gascity-formula.el
      hash: sha256:ba60f5c495490a989dfc186225fafe1c94fbd5d1c1d9bb106abe67f6c5a9176b
    - path: lisp/test/gascity-agents-test.el
      hash: sha256:13097673a43d7cee433d58ba898da13b68883f3e32db149de546a4927767fe63
    - path: lisp/test/gascity-sling-test.el
      hash: sha256:d62920c4b239b074bc4242a4de142201f7af302a5ee61d5216b3dcab90e87cc9
  coverage:
    - id: REQ-005
      status: covered
      rationale: >-
        The roster accessor half of the agent-centric Who: the
        completion-facing `gascity-agents-roster' over the Agents
        view's existing store reads (no new gc call site), candidates
        city-first then per rig annotated "<rig|city> · <state>"
        (mockup §6c), the scope classifier and the free-entry
        degradation, all pure and unit-tested with fixture payloads.
        The derived-default half is WI-3's own bead (ga-ntop), per
        the approved decomposition.
    - id: REQ-010
      status: covered
      rationale: >-
        All three client-side pre-launch validators are pure
        predicates with mockup-worded warning builders and
        degradations: the bl-bdj v2-trap (§5a, verified against
        live build-basic: 23 binding-qualified `gc.run_target' steps),
        the cross-store route check (§5b, matching `gc sling
        --dry-run' cross-rig refusal semantics exactly), and the §5c
        missing-pieces checks. Warnings never block `s' — gc stays
        the authority. Footer/preview wiring is WI-6/WI-7's bead.
---

# Implementation Summary: WI-2 — Roster accessor and the client-side validators (source anchor ga-0okd)

## Summary

Implemented WI-2 of the approved sling command redesign
(plans/sling-command/implementation-plan.md, "WI-2 — Roster accessor
and the client-side validators"; requirements REQ-005, REQ-010) for
source anchor bead ga-0okd, in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-0okd` (commit 9c8b5ae on
top of 69eed1c).

Two deliverables, both pure over cached data and unit-tested with
fixture payloads:

- `lisp/gascity-agents.el`: the completion-facing roster accessor the
  sling's Who stage (the `T` picker, REQ-005) reads through —
  `gascity-agents-roster` (the Agents view's own four store reads,
  never a new gc call site, bounded wait on a cold store),
  `gascity-agents--roster` (city agents first, then each rig's in
  `gc status' rig order), `gascity-agents-roster-candidates`
  (`(name . "<rig|city> · <state>")`, mockup §6c, the state through
  `gascity-agents--state-label`), `gascity-agents-scope` (the
  `city`-or-rig-name classifier: roster `:rig`, else the name's slash
  prefix, else `city`) and `gascity-agents-roster-scope` (free entry
  and a cold roster classify to nil — scope-dependent checks degrade,
  free entry keeps working).
- `lisp/gascity-formula.el`: the REQ-010 validators with their
  mockup-worded warning builders —
  `gascity-sling--binding-targets-p` (a step
  `metadata["gc.run_target"]` containing `.` and no `/`),
  `gascity-sling--v2-trap-p` + `-warning` (binding-qualified run
  targets with a city-scoped target ⇒ the bl-bdj warning, §5a
  wording), `gascity-sling--cross-store-p` + `-warning` (the work
  bead's store resolved from its id prefix against the rig memo — the
  same prefix routing the bd verbs use — vs a rig-scoped target; a
  city-scoped target never fires, §5b wording), and the §5c
  missing-pieces checks (a drain formula without work, missing
  required vars via the non-signaling
  `gascity-sling--missing-required-vars` — now shared by
  `gascity-formula--validate-values` — and no target).

## Intended Behavior

- Pressing `T` in the redesigned sling transient (WI-4 wires the
  picker) offers the city's agents — not sessions — grouped
  city-first then per rig, annotated with scope and live state
  ("mayor  city · active", "hello-world/gc.run-operator
  hello-world · stopped"); a cold store is read first and waited on
  deadline-bounded, and a roster that stays cold leaves free entry
  working — never a dead end.
- The live footer (WI-6) and `P` preview (WI-7) recompute three
  warnings as answers change, exactly as the signed-off mockups
  word them: the bl-bdj trap when a v2 formula with
  binding-qualified step run targets is aimed at a city agent (gc
  fails instantiation with "unknown formulas v2 target" — the dry
  run never exercises it, so the client warns first); a cross-store
  route when a bead is aimed at another rig's agent (gc refuses
  without --force; the mayor is exempt — verified by dry run); and
  the missing pieces of §5c. Warnings never block `s`: gc remains
  the authority.
- Everything degrades silently when its data is cold: free entry and
  freeform work classify to nil, an unknown bead prefix and an empty
  rig memo resolve no store — no warning is ever built on a guess.

## Changed Files

- `lisp/gascity-agents.el` — new "Roster — the sling's Who completion"
  section (scope classifier, pure roster builder, candidates,
  target-scope lookup, store-read orchestration, bounded-wait public
  accessor) + commentary. No existing behavior changed.
- `lisp/gascity-formula.el` — new "Sling validators (REQ-010, mockup
  §5)" section (binding-target detection, v2 trap, bead-store
  resolution, cross-store, missing-work/vars/target, warning
  builders); `gascity-formula--validate-values` refactored onto the
  shared non-signaling missing-vars collector (same messages, same
  refusal semantics) + commentary.
- `lisp/test/gascity-agents-test.el` — six roster tests on the v3
  fixtures (scope classifier; city-first-then-rigs ordering with a
  pinned fixture `now'; candidate annotations; roster-scope free-entry
  degradation; store-backed read; all-reads-fail cold answer).
- `lisp/test/gascity-sling-test.el` — four validator test groups
  (binding-targets; v2 trap and §5a wording; bead-store/cross-store
  and §5b wording with every degradation; §5c missing pieces and the
  still-refusing dispatch half) over inline decoded recipe/rig
  fixtures.

| ID | Status |
| --- | --- |
| REQ-005 | covered |
| REQ-010 | covered |

## Verification

- First verification command: `eldev test sling` (worktree
  `worktrees/ga-0okd`) — FAILED on first run: 2 unexpected results
  (`gascity-test-sling-cross-store-p-and-warning` — a warning wording
  that named the bead prefix instead of the bead id, fixed in
  `gascity-sling--cross-store-warning`; and a `should-null` typo that
  is no ERT form, replaced with `should-not`). Fixed and re-run green
  (40/40), plus `eldev test gascity-test-agents` 16/16 after pinning
  the fixture `now` (`gascity-agents-test--with-fixture-now`) so the
  fixtures' timestamps drive stable idle/active states.
- Live verification against the real bright-lights city
  (`/home/roman/bright-lights`): a batch ERT probe ran
  `gascity-agents-roster` and the validators against live gc — the
  roster came back city-first (mayor, core.control-dispatcher,
  bd.dog-1, bd.dog-2, then hello-world/core.control-dispatcher) with
  mockup-shaped annotations; build-basic reported binding-qualified
  targets; the v2 trap fired for the city-scoped `mayor' and not for
  a rig-scoped target; `bl-pa2` → a hello-world agent reported
  cross-store while `hw-aij` → hello-world/city did not — matching
  `gc sling --dry-run`'s own "Cross-rig … without --force, sling
  would refuse" line for the same pairs, and gc's help text
  (--force "allow cross-rig routing"). The probe file was deleted
  after the run.
- Final proof command: `scripts/gate.sh` (worktree root) — PASSED:
  `eldev compile --warnings-as-errors` clean and the full ERT suite
  676/676 results as expected (2026-09-27 16:22).

## Remaining Risks

- The cross-store rule was pinned to gc's observed behavior (prefix
  mismatch refused, city-scoped targets exempt) rather than the
  design doc's "a city agent [reads] the city store" phrasing, because
  the signed-off mockup §5b names a city agent as a remedy and gc's
  dry run confirms the mayor routes beads of every store. If gc ever
  tightens this, only `gascity-sling--cross-store-p` needs touching;
  the §5b wording is pinned by tests either way.
- WI-2 and WI-1 both extend `lisp/gascity-formula.el` in sibling
  worktrees off the same base commit; a small merge is expected when
  the convoy lands (both add new sections, no shared hunks).
- The `T` picker, derived default, live footer and preview buffer that
  consume these APIs are WI-3/WI-4/WI-6/WI-7's beads; until they land
  the validators are exercised by ERT and the live probe only.
- The summary artifact lives at
  `plans/sling-command/build/implementation-summary-ga-0okd.md` inside
  the item worktree; the plans/sling-command tree is still untracked
  in the launcher checkout, so the workflow-finalize stage should
  commit the artifact root along with the plan documents.
