---
schema: gc.build.requirements.v1
workflow:
  id: ga-eavt
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: requirements
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-emog
      hash: bead:ga-emog
      ids:
        - REQ-001
        - REQ-013
        - REQ-014
        - REQ-015
    - path: beads/ga-hbsq
      hash: bead:ga-hbsq
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
      ids:
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-012
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
      ids:
        - REQ-011
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: covered
    - id: REQ-007
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-009
      status: covered
    - id: REQ-010
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
    - id: REQ-015
      status: covered
---

# Sling Command Redesign — Requirements

Input target: bead `ga-emog` ("Sling command redesign: implement, verify,
document"), delivered through the `build-basic` factory run rooted at
`ga-eavt`. The approved design (`plans/sling-command/design.md`) and the
signed-off menu mockups (`plans/sling-command/menu-mockups.md`) are the
sources of truth; this artifact restates them as verifiable requirements for
plan review and downstream stages.

## Problem Statement

The current `gascity-sling-dispatch` transient works but asks questions whose
answers are derivable, exposes the dispatch shape (plain / `--formula` /
`--on`) through flags instead of inferring it, offers untyped string entry
for formula vars, and gives the user no confidence signal before launch: no
live summary, no client-side validation of known gc failure modes (the bl-bdj
"unknown formulas v2 target" trap, cross-store route refusals), and no full
preview of the routing plan. Users dispatching work from Emacs to Gas City
need one world-class command that gets out of the way when context already
answers the questions, and that guides precisely when it doesn't. The
approved sling redesign (design.md, 2026-09-27) specifies that command; this
workflow implements it, verifies it end-to-end against the bright-lights
test city, and documents it at the quality bar of the PostgreSQL
documentation.

## W6H

- **Who**: The gascity.el user — an Emacs operator dispatching work to Gas
  City cities and rigs (the mayor-role human). Secondary: future maintainers
  of `lisp/gascity-action.el`, `lisp/gascity-formula.el`, and
  `lisp/gascity-agents.el`.
- **What**: A redesign of the sling command into one unified, adaptive,
  staged transient (`What → Who → How → Preview → Launch → Follow`) that
  covers all three sling shapes (plain, `--formula`, `--on`) with typed var
  entry, live validation, full preview, and a post-launch follow offer — plus
  ERT coverage and end-to-end verification.
- **When**: Interactive use, at dispatch time. Any `S` press from any
  gascity view; stages collapse whenever context pre-seeds an answer, so the
  common case is two keystrokes (`S` then `s`).
- **Where**: The gascity.el Emacs package — `lisp/gascity-action.el`
  (transient layout), `lisp/gascity-formula.el` (inference/typed vars),
  `lisp/gascity-agents.el` (agent roster) — with tests in
  `lisp/test/gascity-sling-test.el` and `lisp/test/gascity-test.el`, the
  manual in `doc/gascity.texi` with screenshots under `doc/screenshots/`.
  Verification ground: the bright-lights city (`/home/roman/bright-lights`),
  always invoked as `gc --city /home/roman/bright-lights …`.
- **Why**: Zero questions when answers are derivable; typed guidance when
  they aren't; confidence before launch. The current UI fails all three, and
  known gc-side failure modes (bl-bdj trap, cross-store refusals) currently
  surface only after launch.
- **How**: One transient that re-specializes after each stage answer, with
  client-side shape inference (never flags), typed completion derived from
  the recipe schema, a live one-sentence footer with validation status, an
  on-demand full preview buffer (`P`), and a lightweight follow offer after
  launch — implemented on the retained catalog/recipe/cache machinery, ported
  ERT tests, and a four-scenario live verification pass.

## User Stories

- **US-1 (plain, pre-seeded)**: As an operator with a bead at point, I press
  `S` and then `s` and the dispatch happens with zero further prompts, so
  that routine slings cost two keystrokes.
- **US-2 (shape confidence)**: As an operator, I see one sentence in the
  transient header telling me exactly what will be dispatched (plain route,
  formula run, or targeted drain and by whom), so I never wonder which shape
  I'm in — and I never had to pick it with a flag.
- **US-3 (picking work)**: As an operator with no bead at point, I press
  `A` and choose from the city's open beads and convoys with annotations;
  if I change my mind I press `C-u A` (or RET on empty) and type freeform
  task text instead.
- **US-4 (picking a formula)**: As an operator who wants a formula run, I
  press `f`, pick from the annotated catalog, and the header sentence flips
  immediately: with work in scope it becomes a targeted `--on` run, without
  work a targetless `--formula` run.
- **US-5 (choosing the target)**: As an operator, I press `T` only when I
  disagree with the derived default; the picker completes over agents
  grouped by rig with scope and live state, and the header shows the
  derived target so `s` just uses it.
- **US-6 (typed vars)**: As an operator filling formula vars, I get the
  right reader for each var — file completion for `context_path`,
  directory completion for `artifact_root` seeded with `plans/<slug>/`,
  an agent picker for `implementation_target`, numeric validation for
  `max_iterations`, enums as restricted choices — so illegal values are
  unrepresentable at entry.
- **US-7 (confidence before launch)**: As an operator, the footer always
  shows a one-sentence summary plus ✓/⚠ validation status recomputed as I
  change answers, and `P` gives me the full picture (recipe DAG, gc's dry-run
  routing plan, all warnings) without gating `s`.
- **US-8 (safe launch)**: As an operator about to hit the bl-bdj trap or a
  cross-store refusal, I see the warning in the footer before launching —
  unmissable, though never blocking, since gc stays the authority.
- **US-9 (follow)**: As an operator after a successful launch, I stay put
  by default; a momentary key offers to jump to the run view of the created
  workflow, and any other key dismisses the offer.
- **US-10 (documentation)**: As a user learning the sling command, I read a
  complete, accurate Texinfo chapter with real screenshots covering the
  unified flow, every shape, the pickers, the typed readers, the warnings,
  the preview, and the follow offer.

## Technical Stories

- **TS-1**: As the `gascity-action.el` maintainer, I get one transient
  whose stages are its groups (What, Who, How, Actions), where an answered
  stage collapses to one visible line while keeping its binding, replacing
  the current suffix/section layout without touching the
  `gascity-sling`/`gascity-command-sling` plumbing.
- **TS-2**: As the `gascity-formula.el` maintainer, I keep the
  catalog/recipe/cache machinery, enum/methodology/pattern readers, and
  per-(formula,var) history, and add shape inference, the one-sentence
  header, typed-var heuristics (file/dir/agent/numeric, overridable and
  fail-soft), and bl-bdj trap detection as pure, testable functions.
- **TS-3**: As the `gascity-agents.el` maintainer, I expose a
  grouped-by-rig agent roster with rig-vs-city scope metadata (and live
  state), consumed by the Who picker, the `*_target` var readers, and the
  validators.
- **TS-4**: As a test author, I port the seven existing sling ERT tests to
  the new layout and add tests for shape inference, typed-var heuristics,
  Who default derivation, the bl-bdj trap warning, the cross-store warning,
  and the follow offer — all against stubbed gc boundaries so the suite
  stays offline and fast.
- **TS-5**: As the verifier, I run the four-scenario e2e pass against
  bright-lights (pancake formula, build-basic typed vars, bl-bdj trap, plain
  dispatch) always with `--city /home/roman/bright-lights`, and capture
  screenshots from that same live session for the manual.
- **TS-6**: As the gate keeper, `scripts/gate.sh` (byte-compile
  warnings-as-errors plus full ERT) must be green before the work counts as
  done.

## Behavior Requirements

- **REQ-001 — Unified adaptive entry point.** One command (`S`) covers
  plain, `--formula`, and `--on` sling shapes via one transient
  (`gascity-sling-dispatch`) that re-specializes after each stage answer.
  Conceptual stages What → Who → How → Preview → Launch → Follow; stages
  collapse when pre-seeded (point, remembered state, memory defaults), and a
  fully pre-seeded plain dispatch is exactly `S` then `s` with zero prompts.
- **REQ-002 — Shape inference, never flags.** The shape is inferred from
  the work + formula selections and rendered as one sentence in the
  transient header (e.g. "Sling bead bl-5ja to mayor", "Run pancakes
  (formula) on mayor", "Run build-basic against bl-5ja, drained by
  hello-world/gc.implementation-worker"). There is no shape flag and no
  toggle key.
- **REQ-003 — Smart work picker (`A`).** Completing-read over the city's
  open beads plus convoys, annotated; prefix arg goes straight to freeform
  text; RET on empty input falls through to a text prompt; point pre-seeds
  (bead or convoy, as today).
- **REQ-004 — Formula picker (`f`).** The catalog ∪ `gc formula list`
  union, annotated as today; picking a formula with work in scope yields the
  `--on` shape, without work yields `--formula`.
- **REQ-005 — Agent-centric Who with derived default.** Completion over
  agents (not sessions), grouped/annotated by rig with scope and live state;
  free entry still works. The default is auto-derived in this order:
  rig `default_sling_target`, per-(city, formula) target memory, then the
  implementation-worker convention when the roster confirms exactly one
  rig-scoped `gc.implementation-worker`. The derived target is shown in the
  header and `T` picker with a `derived` tag; `s` never re-prompts when a
  target is derivable.
- **REQ-006 — Typed How vars.** One infix per declared formula var with
  deterministic keys avoiding the reserved set (`A f T c a n m t s P r g x
  q`). Enum/methodology/pattern vars read as today plus per-(formula,var)
  history; `context_path` and `*_path` vars read with file completion
  relative to the rig workdir (TRAMP-safe); `artifact_root` reads with
  directory completion defaulting to `plans/<slug>/` where the slug derives
  from the work bead's title (never the bare bead id), falling back to
  freeform text or the formula name; `rig_name` auto-derives from the chosen
  target (editable); `*_target` vars read with the agent picker; numeric
  vars validate digits and refuse bad entries before any gc call; bool vars
  toggle on key press. Heuristics are overridable per var (var-name →
  function or naming convention) and anything unrecognized fails soft to
  string entry.
- **REQ-007 — Live one-sentence footer.** Always visible: launch summary
  (shape, target, non-blank var count) + validation status (✓ or ⚠ with
  reason), recomputed as answers change.
- **REQ-008 — Full preview buffer (`P`).** Opens at once with everything
  computable client-side — the recipe DAG (steps → needs), the routing plan
  from `gc sling … --dry-run` when it answers, and all validation warnings —
  with launch available directly in the buffer. Preview is never a gate:
  `s` works in the menu at any time. `r` remains the server-substituted
  recipe preview.
- **REQ-009 — Launch and follow offer.** `s` dispatches via
  `gascity-command-execute` as today. On success: echo "launched workflow
  <id>" plus a lightweight follow offer — a momentary key that jumps to the
  run view for the created workflow root bead (reusing `gascity-runs.el`);
  anything else dismisses it; stay put by default. Plain-route launches keep
  the plain echo and no offer.
- **REQ-010 — Client-side pre-launch validation.** Warn on the bl-bdj trap
  (v2 formula with binding-qualified step `run_targets` + city-scoped
  target ⇒ the "formulas v2 target" warning, distinguishing rig- vs
  city-scoped agents from roster metadata) and on cross-store routes (work
  bead and target agent in different stores). Warnings appear in the live
  footer (unmissable) with full detail in the `P` buffer, and never block
  `s` — gc remains the authority.
- **REQ-011 — Layout matches the mockups.** The transient renders exactly
  as `menu-mockups.md` specifies: stages are stacked full-width groups; an
  answered stage collapses to its one line with the answer visible and the
  binding still changing it; routing flags render only on the plain shape
  (F-5 kept); the first group is the one-sentence header plus the live
  footer; keys as in the mockups' key summary (`A f T -- s P r g x q`, `p`
  freed).
- **REQ-012 — State and memory preserved.** Per-(formula,var) history,
  per-(city,formula) target memory (now driving the Who default), per-city
  remembered menu state (adapted so collapsed stages re-open from
  remembered values), the city pinning fix (ga-4ia4), and the async
  catalog/recipe/cache refresh machinery all keep working.
- **REQ-013 — Test coverage.** The seven existing ERT tests in
  `lisp/test/gascity-sling-test.el` are ported to the new layout; new tests
  cover shape inference, typed-var heuristics, Who default derivation, the
  bl-bdj trap warning, the cross-store warning, and the follow offer;
  affected sling tests in `lisp/test/gascity-test.el` are updated;
  `scripts/gate.sh` is green (warnings-as-errors compile + full ERT).
- **REQ-014 — End-to-end verification.** All four design scenarios run
  live against bright-lights (always `gc --city /home/roman/bright-lights`):
  (1) pancake formula e2e from Emacs — header sentence, launch, mayor
  session works it, follow offer jumps to run view; (2) build-basic `--on`
  with typed vars — `context_path` via file completion, `artifact_root`
  defaulting to `plans/<slug>/`, `rig_name`/`implementation_target` derived
  from the target; (3) bl-bdj trap — city-scoped target shows the footer
  warning before launch, rig-scoped shows ✓; (4) plain dispatch — bead at
  point, `S s` with zero prompts, freeform text via prefix arg.
- **REQ-015 — Documentation.** A complete Texinfo chapter for the sling
  command in `doc/gascity.texi` at the PostgreSQL-documentation quality bar
  — the unified flow, every shape, the pickers, typed var readers, validation
  warnings, preview buffer, follow offer, key summary — built with the
  existing toolchain (`doc/Makefile`), plus real screenshots of the
  transient's states under `doc/screenshots/` wired like existing images,
  captured from the live verification session. Documentation is part of
  acceptance, not an afterthought.

## Example Mapping

Illustrative examples tying the behavior requirements to concrete
bright-lights situations (mockups §1–§9 render these in full):

- **REQ-001 / REQ-002, plain pre-seeded**: Given point on bead `bl-5ja`
  and a remembered target for its rig, when I press `S`, then the header
  reads "Sling bead bl-5ja to mayor", every stage holds an answer, and `s`
  launches with no prompts.
- **REQ-002 / REQ-004, formula without work**: Given no work chosen, when I
  pick `pancakes` with `f`, then the header flips to "Run pancakes (formula)
  on mayor", no How group appears (pancakes declares no vars), and no
  routing flags group renders.
- **REQ-002 / REQ-006, targeted with typed vars**: Given bead `bl-5ja` at
  point, when I pick `build-basic` with `f`, then the header reads "Run
  build-basic against bead bl-5ja, drained by <rig>/gc.implementation-worker",
  the How group shows one typed infix per declared var with
  `artifact_root` seeded to `plans/<title-slug>/`, and the footer counts
  non-blank vars.
- **REQ-005, derived Who**: Given a build formula and a roster with exactly
  one rig-scoped `gc.implementation-worker`, when the Who stage renders,
  then the target shows with a `derived` tag and `s` uses it without
  prompting.
- **REQ-007 / REQ-010, bl-bdj trap**: Given build-basic (binding-qualified
  step run targets) and the city-scoped `mayor` as target, when the footer
  recomputes, then it shows the "formulas v2 target … rig-scoped … (bl-bdj)"
  warning and `s` still works; with a rig-scoped agent it shows ✓.
- **REQ-008, preview**: Given a fully answered `--on` dispatch, when I
  press `P`, then the preview buffer shows validation, the recipe DAG
  (prepare → requirements → plan → …), and the dry-run routing plan, and I
  can launch from there.
- **REQ-009, follow offer**: Given a successful formula launch, when gc
  reports the created workflow root, then the echo shows "Launched workflow
  <id> (formula on bead) — F: run view", `F` jumps to the run view, and any
  other key dismisses.
- **REQ-006, numeric guard**: Given `max_iterations` unset-to-edit, when I
  enter `lots`, then the reader refuses with "Var max_iterations must be
  numeric (got lots)" before any gc call.

## Acceptance Criteria

The stage is accepted when all of the following hold, each traced to its
requirement:

1. One unified transient covers all three shapes; shape is only ever
   inferred and displayed as one sentence; no shape flag or toggle exists
   (REQ-001, REQ-002).
2. `A` picks annotated open beads/convoys with freeform escape (prefix arg
   or empty RET); point pre-seeds (REQ-003).
3. `f` picks from the annotated catalog union; with-work ⇒ `--on`,
   without ⇒ `--formula` (REQ-004).
4. `T` completes over rig-grouped agents with scope and state; the derived
   default follows the rig `default_sling_target` → per-(city,formula)
   memory → implementation-worker-convention order, is tagged `derived`,
   and `s` never re-prompts when derivable (REQ-005).
5. Every declared formula var gets a typed reader per REQ-006 (file, dir
   with `plans/<slug>/` seed, agent, numeric, enum, bool), with
   overridable, fail-soft heuristics and deterministic keys outside the
   reserved set (REQ-006).
6. The live footer is always on and recomputes on change; `P` shows the DAG,
   dry-run routing plan, and full warnings, and never gates `s` (REQ-007,
   REQ-008).
7. Launch works from both the menu and the preview buffer; success echoes
   the workflow id plus the momentary follow offer jumping to the run view;
   plain routes keep the plain echo (REQ-009).
8. The bl-bdj trap and cross-store warnings render in the footer before
   launch (and in `P`), never blocking `s` (REQ-010).
9. The transient's rendering matches `menu-mockups.md` state for state —
   groups, collapsed answered stages, plain-only routing flags, key
   summary (REQ-011).
10. History, target memory, remembered state, city pinning, and async
    catalog/recipe/cache refresh all still work (REQ-012).
11. `lisp/test/gascity-sling-test.el` carries the ported seven tests plus
    new tests for shape inference, typed-var heuristics, Who default
    derivation, bl-bdj trap warning, cross-store warning, and follow offer;
    `lisp/test/gascity-test.el` sling tests updated; `scripts/gate.sh`
    green (REQ-013).
12. The four bright-lights e2e scenarios pass, all invoked as
    `gc --city /home/roman/bright-lights …` (REQ-014).
13. The Texinfo chapter exists at the stated quality bar, builds with the
    existing toolchain, and real screenshots from the live session are
    wired under `doc/screenshots/` (REQ-015).

## Out Of Scope

Per the approved design's explicit non-goals, plus the target bead's
constraints:

- **Named presets / repeat-last dispatches** — rejected; per-(formula,var)
  history and per-(city,formula) target memory already cover reuse.
- **Abort/pause affordance for running workflows** — out of scope
  (surfaced by the ga-kqo0 stop incident; revisit after the redesign lands,
  possibly upstream in gc).
- **A separate quick-sling command** — rejected; plain dispatches flow
  through the same unified transient.
- Upstream PRs — the polecat contract allows local commits to main only.
- Touching the unrelated stopped worktree `worktrees/ga-tbte`, or committing
  the pre-existing uncommitted deletions under `plans/dashboard-v2/`,
  `plans/bright-lights-dogfood/`, `plans/formula-sling-ui/` etc.
- gc-side changes (e.g. teaching gc about the trap instead of warning
  client-side) — the client warns, gc stays the authority.

## Open Questions

None blocking. The design was approved with the user (2026-09-27) and the
menu mockups signed off, resolving all previously open rendering decisions
(layout-as-groups, derived-Who presentation, `artifact_root` slug source,
key summary). Residual ambiguity is handled inside the implementation
contract rather than by a human gate:

- **Var-key collisions under new reserved letters**: the deterministic key
  algorithm must avoid the reserved set `A f T c a n m t s P r g x q`;
  if a collision is unavoidable the mockups' `…` fallback (grouped overflow
  rendering) applies — an implementation detail, not a requirements
  question.
- **Dry-run latency on remote cities**: `P` renders client-side instantly
  and the routing plan fills in when `--dry-run` answers; if a dry run is
  slow the preview must not block rendering (existing async machinery
  applies).
- **Screenshot capture of momentary states**: the follow offer and live
  footer variants are ephemeral; capture feasibility against the live
  session is left to the verification pass, with mockup renderings as the
  documented fallback if a state cannot be captured faithfully.

## Coverage

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-014 | covered |
| REQ-015 | covered |
