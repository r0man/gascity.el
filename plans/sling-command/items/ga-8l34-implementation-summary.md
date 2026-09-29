---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-ygzj
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
    - path: beads/ga-pkpi
      hash: bead:ga-pkpi
      ids: [REQ-007, REQ-010]
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: lisp/gascity-action.el
      hash: git:80c35dd
    - path: lisp/test/gascity-sling-test.el
      hash: git:80c35dd
  coverage:
    - id: REQ-007
      status: covered
    - id: REQ-010
      status: covered
---

# WI-6 — Live footer

Work item WI-6 of the sling command redesign, implemented in the
per-bead worktree `/home/roman/workspace/gascity.el/worktrees/ga-pkpi`
(commit `80c35dd`, source anchor `ga-pkpi`).

## Summary

The sling menu's second header line is the always-on live footer:
`gascity-sling--footer` over (scope, roster, recipe) composes the WI-2
client-side validators and the WI-1 shape inference into one sentence —
`✓ Ready — <shape> · target <name> (<scope>) · N of M vars set` — or a
stack of `⚠ <reason>` warnings with the mockup §5 wordings. It renders
as part of every transient setup through a function `:info` spec, so it
recomputes as each answer changes — including on a var edit's redraw,
without a re-setup — from cached data only: no gc on the render path
(D9). Warnings never block `s`; full detail is WI-7's `P` buffer.

## Intended Behavior

- `✓ Ready — <shape> · target <name> (<scope>) · <vars>` when every
  client-side check is clean (mockup §1/§3/§4):
  - shape from WI-1's `gascity-sling--shape`: `plain route` / `formula
    run` / `on run`;
  - target word: `mayor (city)` for a city-scoped agent (§1/§3), just
    `rig-scoped` when the roster classifies the target under a rig
    (§4 — the qualification is what a v2 launch needs, the name sits in
    the Who line), the bare name when neither (free entry, cold roster
    — never a guess), `(none)` when no target;
  - vars word: `no vars` on the plain shape, `0 vars` for a formula
    that declares none (§3), `N of M vars set` counting the non-blank
    answers against the declared vars (§4).
- One `⚠` line per warning, target-first (mockup §5, REQ-010), each
  decided by a WI-2 validator and worded by its builder:
  - §5a bl-bdj trap — `gascity-sling--v2-trap-p` on the recipe and the
    target's roster scope; the suggestion names the first rig-scoped
    roster row (`pick a hello-world/* agent with T`), generic on a cold
    roster;
  - §5b cross-store route — `gascity-sling--cross-store-p` over the
    work bead, the target's roster scope and the rig memo
    (`gascity-rigs-cached` of the scope's city);
  - §5c missing pieces, in mockup order — missing work for a drain
    formula, missing required vars (the non-signaling half of
    `gascity-formula--validate-values`), missing target.
- Pure over cached data (D9): the roster is peeked from the store's
  cache (`status`, `session list`, `agent list` — background refreshes
  scheduled when stale, never blocking); the recipe is the one the
  menu setup already read; the infix values are read at format time.
  A cold store degrades to a nil roster: scope-dependent checks stay
  silent and free entry keeps working.
- The footer renders as part of every transient setup (REQ-007): the
  header group of `gascity-sling--children-specs` carries the footer's
  `:info` spec beside the scope line, and its description is a FUNCTION
  — transient evaluates it at format time on every setup and every
  redraw, so a var infix edit's redraw recomputes the count without a
  re-setup. Like the scope info, the spec is passed unwrapped and never
  as a group's first element (both crash transient setup — founded in
  the tmux-Emacs TRAMP e2e pass).
- Warnings never block `s` (REQ-010): the footer is display only — gc
  stays the authority at launch; the footer never refuses.

## Changed Files

- `lisp/gascity-action.el` — new "live footer" section beside the
  sling transient: `gascity-sling--footer-rig` (the §5a suggestion
  rig), `gascity-sling--footer--target-word`,
  `gascity-sling--footer--vars-word`, the composing
  `gascity-sling--footer`, `gascity-sling--roster-cached` (the store
  peek of the roster's three reads) and `gascity-sling--footer-info`
  (the function `:info` spec); `gascity-sling--children-specs` now
  appends the footer spec to the header group on every shape, and the
  forward declarations name the sibling work items' functions the
  footer composes (WI-1 shape, WI-2 validators and roster accessors).
- `lisp/test/gascity-sling-test.el` — new tests:
  `gascity-test-sling-footer-ready-plain-sentence` (§1),
  `-ready-formula-sentence` (§3), `-ready-on-sentence` (§4, vars count
  and the `rig-scoped` target word), `-v2-trap-warning` (§5a verbatim,
  recipe + roster-scope inputs, cold-roster degradation),
  `-cross-store-warning` (§5b verbatim, work + scope + rig-memo
  inputs), `-missing-pieces-stack` (§5c order), 
  `-recomputes-across-scope-changes` (warnings peel off as answers
  land), `-footer-info-renders-in-every-setup` (the spec on every
  shape, function description, pure parse time), and
  `-roster-cached-peeks-the-store` (the three peeks, no bead read).
  The sibling work items are stubbed at their contract — the WI-2
  decision rules and the mockup-exact builder wordings, WI-1's real
  shape rule — so the composition is pinned now and the real functions
  take over at integration.

## Verification

First verification command (from the worktree):

    bash scripts/gate.sh

Observed: FAIL — `eldev compile --warnings-as-errors` passed; the test
suite reported 2 unexpected results:
`gascity-test-sling-footer-cross-store-warning` (real: the test's
stubbed `gascity-sling--cross-store-warning` did not mirror WI-2's
builder verbatim — it truncated the bead id to its store prefix, while
WI-2's real builder names the bead in full, as mockup §5b shows; fixed
the stub to mirror the real wording) and
`gascity-test-agent-detail-follow-log-stderr-goes-with-it` (see
Remaining Risks: pre-existing and unrelated — it reproduces on a
pristine checkout of the same base commit with no diff applied).

Final proof command (from the worktree):

    bash scripts/gate.sh

Observed: PASS for this item's boundary — `eldev compile
--warnings-as-errors` clean (whole package), and the full suite ran
`Ran 675 tests, 674 results as expected, 1 unexpected`, the one
unexpected being the pre-existing agent-detail flake above (verified
on the pristine base: `cd` to a fresh worktree at 69eed1c with no
diff, `eldev test` → the same 1 unexpected result). All 37
`gascity-test-sling-*` tests pass, including the nine new footer
tests.

Non-blocking D9: no new synchronous gc anywhere — the footer reads
only store peeks, the cached recipe and the live infix values; the
`gascity-store-peek` render path schedules background refreshes and
never blocks.

## Remaining Risks

- `gascity-test-agent-detail-follow-log-stderr-goes-with-it` fails
  under the current machine load (twelve workers running gates
  concurrently): the log follower's bounded stderr drain (20 × 10 ms in
  `gascity-session--log-sentinel`) can expire before the stderr pipe
  delivers its last line, and the end note then carries the pipe's own
  "finished" line instead. Reproduced on a pristine worktree at the
  base commit `69eed1c` with no diff applied — pre-existing, unrelated
  to the footer (no agent/terminal/session code touched); it passes in
  isolation on an idle machine. Flagged for the integration pass
  rather than fixed here: the follower lives outside this item's
  boundary.
- The footer composes the WI-1/WI-2 functions through forward
  declarations on this base (they land in their own work items' work
  trees); the tests stub them at their contract until integration. A
  wording drift in WI-2's builders would surface as a footer-wording
  mismatch at merge time; the stubs mirror ga-0okd's builders
  verbatim as of its commit `9c8b5ae`.
- The vars word counts non-blank answers of the live infix values but
  does not weigh per-var defaults (mockup §4's "6 of 18" counts
  answered non-blank values only); WI-5's typed infixes own the
  answer-collection details.
- The interactive bright-lights end-to-end pass for the redesigned
  menu is WI-11's scope, not this item's.

| ID | Status |
| --- | --- |
| REQ-007 | covered |
| REQ-010 | covered |
