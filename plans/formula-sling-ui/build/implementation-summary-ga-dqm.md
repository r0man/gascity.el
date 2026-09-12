---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-7vw
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
    - path: beads/ga-dqm
      hash: bead:ga-dqm
      title: "WI-1: formula plumbing — read command classes, formula domain classes, sling --on slot"
      ids:
        - REQ-003
        - REQ-012
        - REQ-013
        - REQ-014
        - REQ-016
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Approved implementation plan, Phase 1 (Plumbing) this step implements"
    - path: lisp/gascity-types.el
      hash: sha256:ad77fce9043f0fe30dd0b3244beae27ef82d54c81c7df07ab856b42311edb746
      title: "Sling --on slot and formula read command classes"
    - path: lisp/gascity-domain.el
      hash: sha256:278bb8fa9b49f1c9bc4b6c16dd5f9bc978abdf47db057f9667f9c798dcaccc5d
      title: "Formula payload domain classes"
    - path: lisp/gascity-action.el
      hash: sha256:365c8cce1fecd66c591c812aa47e7ca7e7b7bbd28ac26156a7dfcbe90b9405ba
      title: "--on=... clause in gascity-sling--parse-transient-args"
    - path: lisp/test/gascity-test.el
      hash: sha256:17ce6900bf7dbb836d475561f4eaf1fdfd45bd342920b9c331f66bbf208e43b9
      title: "ERT coverage for decoding, command lines, --on parse and validation"
  coverage:
    - id: REQ-003
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
    - id: REQ-016
      status: covered
---

# Implementation Summary: WI-1 formula plumbing (sling --on, formula reads, payload classes)

## Summary

Implemented the Phase 1 "Plumbing" work item of the formula-sling-ui plan
(work item WI-1, source anchor bead ga-dqm) in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-dqm`, committed as
`f2cfb7cb61cc24bdb121bb33a95f484bf49d8f8f` ("feat(formula): gc plumbing
for the formula-aware sling UI") on the worktree's detached HEAD.

The step adds the gc command and domain plumbing the formula-aware sling
transient (WI-2) will consume, and nothing else: the targeted `--on`
sling shape, the two formula read command classes with their generated
`NAME!` bang executors, and the typed domain classes for the formula
catalog/recipe payloads. No UI, no new module, no load-order change —
`gascity-formula.el` is explicitly WI-2's deliverable.

## Intended Behavior

- `gc sling <target> <bead> --on <formula>` is now expressible:
  `gascity-command-sling` carries an `on` slot (`:long-option "on"`,
  `:option-type :string`) so `gascity-command-line` emits
  `--on <formula>` (REQ-013), and
  `gascity-sling--parse-transient-args` maps a transient `"--on=…"`
  infix value onto `:on` — WI-2's generated infix can therefore drive
  the targeted convoy-first shape through the same parse path as the
  existing flags.
- Two new read command classes in `lisp/gascity-types.el`, defined with
  `gascity-defcommand` (house convention: read classes live here; the
  macro emits the `NAME!` sync bang executors WI-2 reads through the
  single gc call site — REQ-003):
  - `gascity-command-formula-catalog` → `gc formula catalog --json`
    (no filters);
  - `gascity-command-formula-show` → `gc formula show <name> --json`
    with a positional `name` slot plus a `:var` list slot carrying the
    repeated `--var k=v` stringArray flags the recipe preview needs when
    it re-runs the read with current infix values (REQ-012, plan-review
    verdict F-1).
- Typed payload classes in `lisp/gascity-domain.el`, decoded once via
  beads.el's reflective `beads-from-json` with explicit `:json-key`
  metadata (REQ-003/REQ-014):
  - `gascity-formula-catalog-entry` (`name`, `description`);
  - `gascity-formula-var` (`name`, `description`, `default`,
    `required`, `enum`, `pattern`) — optional slots are typed
    `(or null …)` because gascity's JSON reader decodes both `false` and
    `null` to nil, so an absent field reads as "no constraint" rather
    than a typed zero value (REQ-016); `enum` is typed
    `(or null (list-of string))` and coerces gc's JSON array into a list;
  - `gascity-formula` (`name`, `description`, `metadata`, `vars` decoded
    into typed `gascity-formula-var`s via the `(list-of class)` slot
    type, `steps`/`deps` kept as raw alist lists since only the WI-2/3
    preview renderer reads them).
- `gascity-command-formula-show` rejects a blank formula name through
  `gascity-command-validate` before gc is invoked.

## Changed Files

All changes are committed in the item worktree (commit `f2cfb7c`,
currently detached HEAD of `/home/roman/workspace/gascity.el/worktrees/ga-dqm`):

| File | Change |
| --- | --- |
| `lisp/gascity-types.el` | `gascity-command-sling` gains the `on` slot; new `gascity-command-formula-catalog` and `gascity-command-formula-show` read classes (with a `gascity-command-validate` method requiring the formula name). |
| `lisp/gascity-domain.el` | New `gascity-formula-catalog-entry`, `gascity-formula-var` and `gascity-formula` payload classes; module commentary updated. |
| `lisp/gascity-action.el` | `gascity-sling--parse-transient-args` learns the `--on=…` clause; docstring updated. |
| `lisp/test/gascity-test.el` | New ERT tests (see Verification). |

Coverage matrix:

| ID | Status |
| --- | --- |
| REQ-003 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-014 | covered |
| REQ-016 | covered |

## Verification

1. First verification command — the byte-compile gate over the whole
   package, never a subset:
   `eldev compile --warnings-as-errors` (run from
   `/home/roman/workspace/gascity.el/worktrees/ga-dqm`) — **pass**,
   zero warnings.
2. ERT (mocked, house convention — `cl-letf` stubs on the gc boundary,
   no live city needed):
   `eldev test` — **pass**, 252/252. New tests:
   - `gascity-test-domain-decode-formula-catalog-entry` — full decode
     plus absent-description degradation;
   - `gascity-test-domain-decode-formula-var` — every declared field,
     a `false` `required` staying nil, and absent-field degradation;
   - `gascity-test-domain-decode-formula-recipe` — vars nest into typed
     classes, steps/deps coerced from JSON arrays to alist lists, raw
     metadata preserved;
   - `gascity-test-sling-on-command-line` — `--on <formula>` emission,
     combined with repeated `--var`, and absent-slot suppression;
   - `gascity-test-formula-command-lines` — catalog/show command lines
     (`--json` placement verified live against the built classes),
     repeated `--var`, and blank-name validation.
   The existing `gascity-test-sling-parse-transient-args` gained the
   `--on=…` parse and its end-to-end line assertions.
3. Final proof command — the standard quality gate:
   `scripts/gate.sh` — **pass** ("gate: PASS (compile clean + tests
   green)"), which re-runs `eldev compile --warnings-as-errors` plus the
   whole ERT suite (REQ-017 scoped to this step's slice).

## Remaining Risks

- The `--var` + `--on` combination against a live `gc` is asserted only
  at the command-line level here; the plan's D2 note (recipe preview
  re-running `gc formula show <name> --var k=v` with `--on`) is exercised
  against a real store in the tmux-Emacs TRAMP acceptance pass that
  closes Phase 4 (REQ-018), recorded in a `docs/qa/` report.
- `gascity-formula-var`'s `enum`/`pattern` slots are contractually
  implemented and unit-tested with stub payloads; no shipped gc formula
  declares them today (plan D1), so live behavior for them is
  unverified by construction — they degrade to nil, which WI-2's UI
  treats as "no constraint".
- The worktree is one commit behind the launcher `main` (missing
  `ed28c2b`, an agent-registration metadata commit); the rebase at
  merge time is expected to be conflict-free since the changed files do
  not overlap.
