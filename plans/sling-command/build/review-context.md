# Review Context: Sling command redesign (build-basic workflow ga-eavt)

Prepared by step ga-6k0g (build-basic.review.setup-build-basic-review), 2026-09-27.

- Workflow root: ga-eavt (build-basic)
- Implementation convoy: ga-04j2 (sling-command-implementation), closed
- Launcher rig root (NOT the code under review): /home/roman/workspace/gascity.el
- Requirements: plans/sling-command/requirements.md (REQ-001..REQ-015)
- Implementation plan: plans/sling-command/implementation-plan.md
- Decomposition: plans/sling-command/decomposition.md (WI-1..WI-12)
- Canonical implementation summary: plans/sling-command/implementation-summary.md
- Implementation commit (merged item worktree ga-3wpi): e44dcf05fac7a34c1d249871acf0523b59ef2dd3 (short e44dcf0d)
- Documentation commit (item worktree ga-1wl7): f21af52

Verification commands and observed results: see the Implementation Summary
excerpt below (gate 723/723 green; four-scenario live e2e pass over TRAMP
against /home/roman/bright-lights; reports
worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md and
worktrees/ga-1wl7/docs/qa/2026-09-27-sling-wi12-documentation.md).

## Implementation Worktrees

Every relative source path in this context is anchored to the real
implementation worktrees below, never to the launcher checkout
/home/roman/workspace/gascity.el, whose 'main' does not yet contain the
sling implementation (the finalize stage merges it; the launcher root
remaining unchanged is expected and is not a review failure).

### ga-510r — WI-1 Shape inference and the one-sentence header
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-510r
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 8fc52c0
- per-item summary: no per-item summary file; evidence: worktree commit + ported suite + WI-11 live pass (REQ-001, REQ-002)

### ga-0okd — WI-2 Roster accessor and client-side validators
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-0okd
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 338d2cb
- per-item summary: plans/sling-command/build/implementation-summary-ga-0okd.md in the worktree (REQ-005, REQ-010)

### ga-ntop — WI-3 Derived Who default
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-ntop
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 9d2acbf
- per-item summary: plans/sling-command/task-ga-ntop-summary.md in the launcher (REQ-005)

### ga-f7a4 — WI-4 Adaptive layout and the three pickers
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-f7a4
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 83c5367
- per-item summary: plans/sling-command/task-ga-f7a4-summary.md in the launcher (REQ-001, REQ-003, REQ-004, REQ-011)

### ga-o6eh — WI-5 Typed How vars
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-o6eh
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 2f83f30
- per-item summary: plans/sling-command/task-ga-o6eh-summary.md in the launcher (REQ-006)

### ga-pkpi — WI-6 Live footer
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-pkpi
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 80c35dd
- per-item summary: no per-item summary file; evidence: worktree commit + WI-11 live pass footer scenarios (REQ-007, REQ-010)

### ga-ub2r — WI-7 P full preview buffer
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-ub2r
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 683cece
- per-item summary: plans/sling-command/build/ga-nij3-implementation-summary.md in the launcher (REQ-008)

### ga-f4w0 — WI-8 Launch and follow offer
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-f4w0
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 0853cd9
- per-item summary: plans/sling-command/task-ga-f4w0-summary.md in the launcher (REQ-009)

### ga-me2n — WI-9 State and memory preserved
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-me2n
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: af56c49
- per-item summary: no per-item summary file; evidence: worktree commit + WI-11 live pass (REQ-012)

### ga-gonl — WI-10 ERT consolidation
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-gonl
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: 426d2fd
- per-item summary: plans/sling-command/task-ga-gonl-summary.md in the launcher (REQ-013)

### ga-3wpi — WI-11 End-to-end verification
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-3wpi
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: e44dcf0d
- per-item summary: worktrees/ga-3wpi/plans/sling-command/build/implementation-summary-ga-nqyt.md; merged WI-5/WI-6 siblings and the fixes (REQ-014)

### ga-1wl7 — WI-12 Documentation
- implementation worktree: /home/roman/workspace/gascity.el/worktrees/ga-1wl7
- launcher root for contrast: /home/roman/workspace/gascity.el
- item commit: f21af52
- per-item summary: worktrees/ga-1wl7/plans/sling-command/task-ga-1wl7-summary.md (REQ-015)

Setup warning: the canonical implementation summary's trace.upstream lists
only beads/ga-3wpi and beads/ga-1wl7 as beads/ source-anchor entries; the
other ten anchors (WI-1..WI-10) were recovered here from the convoy
ga-04j2 membership and decomposition.md, and all twelve work_dirs were
re-verified as existing git worktrees distinct from the launcher root.

## Changed files (merged item worktree ga-3wpi, origin/main..e44dcf0d)

```
M	doc/gascity.texi
A	docs/qa/2026-09-27-wi11-sling-redesign-e2e.md
M	lisp/gascity-action.el
M	lisp/gascity-agents.el
M	lisp/gascity-domain.el
M	lisp/gascity-formula.el
M	lisp/test/gascity-agents-test.el
M	lisp/test/gascity-sling-test.el
M	lisp/test/gascity-test-helpers.el
M	lisp/test/gascity-test.el
A	plans/sling-command/build/implementation-summary-ga-0okd.md
A	plans/sling-command/build/implementation-summary-ga-nqyt.md
```

## Changed files (item worktree ga-1wl7, origin/main..f21af52)

```
M	doc/gascity.texi
A	doc/images/sling-cold-thumb.png
A	doc/images/sling-cold.png
A	doc/images/sling-follow-thumb.png
A	doc/images/sling-follow.png
A	doc/images/sling-formula-thumb.png
A	doc/images/sling-formula.png
A	doc/images/sling-on-thumb.png
A	doc/images/sling-on.png
A	doc/images/sling-plain-thumb.png
A	doc/images/sling-plain.png
A	doc/images/sling-preview-thumb.png
A	doc/images/sling-preview.png
A	doc/images/sling-trap-thumb.png
A	doc/images/sling-trap.png
M	docs/DESIGN-write-actions.md
A	docs/qa/2026-09-27-sling-wi12-documentation.md
A	plans/sling-command/task-ga-1wl7-summary.md
```

## Proof commands

```
eldev compile --warnings-as-errors && eldev test   # per item, and on the merged tree
scripts/gate.sh                                    # final gate: PASS (compile clean + tests green, 723/723)
. scripts/e2e-harness.sh; e2e_kill_emacs && e2e_start_emacs && e2e_emacs_ready   # live REQ-014 pass
```

## Artifact excerpts

### requirements.md

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

### implementation-plan.md

---
schema: gc.build.plan.v1
workflow:
  id: ga-eavt
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: plan
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
        - REQ-015
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: beads/ga-emog
      hash: bead:ga-emog
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

# Sling Command Redesign — Implementation Plan

Implementation plan for the `build-basic` workflow rooted at bead
`ga-eavt`, producing the unified adaptive sling transient specified by
the approved design (`plans/sling-command/design.md`, approved with the
user 2026-09-27) and the signed-off menu mockups
(`plans/sling-command/menu-mockups.md`), against the verified
requirements (`plans/sling-command/requirements.md`, REQ-001…REQ-015).
The plan names the affected areas, the sequenced work items, the
risks, the test strategy, and the handoff criteria; every requirement
is covered by at least one work item (see the Coverage table).

## Summary

The current `gascity-sling-dispatch` transient works but asks questions
whose answers are derivable, exposes the dispatch shape through flags
instead of inferring it, offers untyped string entry for formula vars,
and gives no pre-launch confidence signal. This plan replaces its
layout with the mockups' staged adaptive form — **What** (`A` work, `f`
formula), **Who** (`T` agent target), **How** (typed var infixes),
**Actions** (`s P r g x q`) — with a one-sentence shape header, a live
validation footer, a full preview buffer (`P`), and a post-launch
follow offer. The `gascity-formula.el` catalog/recipe/cache machinery,
the deterministic var-key assignment, per-(formula,var) history, and
the async refresh are **retained**; the additions are shape inference,
typed-var readers, the agent roster view, client-side validation (the
bl-bdj trap, cross-store routes), and the follow offer reusing
`gascity-run-show`. Work lands in six waves on `main`, gated by
`scripts/gate.sh`, with the four-scenario end-to-end pass and the
documentation chapter produced from the same live bright-lights
session. Twelve work items (WI-1…WI-12) cover REQ-001 through REQ-015;
each is sized as one decomposition unit.

## Current System

What exists today, by area:

- **Entry and layout** (`lisp/gascity-action.el`, the `;;; Sling`
  section): `S` opens `gascity-sling-dispatch` (a `beads-define-prefix`
  whose children are generated per setup by
  `gascity-sling--children-specs` → `gascity-sling--setup-children`).
  The scope plist is `(:city :formula :target :arg)`; the header info
  line is `gascity-sling--scope-info` ("Arg: … · Formula: … ·
  Target: …"). Groups stack vertically: Formula (`-f` pick via
  `gascity-sling-dispatch-pick`, `g` refresh), Destination (`-T`
  target session read, `A` arg edit), Routing flags (`-c -a -n -m -t`),
  Actions (`s` run, `p` dry-run preview, `r` recipe preview, `x`
  reset, `q` quit), plus the picked formula's generated Variables group
  last. Single-letter reserved bindings are collected in
  `gascity-sling--reserved-keys` (`f g T A c a n m t s p r x q`).
- **Plain path**: `gascity-sling--run` reads the arg on demand
  (`read-string` seeded from the bead/convoy at point via
  `gascity-sling-formula--bead-or-convoy-at-point`) and the target via
  `gascity-action--read-session` (session completion), parses routing
  flags with `gascity-sling--parse-transient-args`, and dispatches
  through `gascity-command-act-async` (async, D9). Preview (`p`) is
  the `--dry-run` text view `gascity-sling--show-plan` on
  `gascity-action--async-text-view`.
- **Formula machinery** (`lisp/gascity-formula.el`): per-scope-key
  caches for the catalog, `gc formula list` and compiled recipes
  (`gascity-formula-catalog-cache` / `-list-cache` / `-recipe-cache`,
  keyed by `gascity-context-scope-key`); the union picker
  `gascity-formula-choices` / `gascity-sling-formula--read-formula`
  (S-1: catalog ∪ list); async refresh `gascity-formula-refresh-async`
  through the store; the enum mapping `gascity-formula--enum-metadata-keys`
  (var name → `metadata.gc.methodology` key, decision D1); shape
  detection `gascity-formula--needs-convoy` (gc's documented sling
  rule: a drain step or a `{{convoy_id}}` reference, decision D2);
  client-side validation `gascity-formula--validate-values` (required
  vars, patterns); per-(formula,var) history
  `gascity-formula--history-var`; the deterministic var-key assignment
  `gascity-sling-formula--var-key` / `--var-keys` avoiding the reserved
  set; the generated infix classes (enum / bool / string options) with
  slots carrying each var's payload; dispatch
  `gascity-sling-formula--dispatch` (validates, picks the shape by
  `needs-convoy`, `--on` requires a bead, runs async, supports dry
  run); the server-side substituted recipe preview
  `gascity-sling-formula--show-recipe` rendering steps/deps into a
  host-qualified view buffer.
- **State**: `gascity-sling--remembered` (per-city scope + infix
  values, restored at entry, cleared by `x` and a real sling — S-2);
  city pinning `gascity-sling--city-dir` with every catalog/recipe
  read pinned to the entered-from city (ga-4ia4).
- **Agent roster** (`lisp/gascity-agents.el`): the Agents view already
  builds agent rows from `gc status` + `gc session list` + `gc agent
  list` through the store (`gascity-agents--rows` over
  `gascity-dashboard--agents`), each plist carrying `:name`
  (rig-qualified, e.g. `hello-world/gc.implementation-worker`), `:rig`
  (nil ⇒ city), `:state` (`stalled/running/idle/stopped/suspended`),
  `:provider`, `:object`. No completion-facing accessor exists yet.
- **Runs view** (`lisp/gascity-run.el`): `gascity-run-show` shows the
  workflow run whose root bead id is given — the follow target.
- **Tests** (`lisp/test/gascity-sling-test.el`, seven tests):
  `gascity-test-sling-choices-union`,
  `gascity-test-sling-picker-offers-city-formulas`,
  `gascity-test-sling-picker-nothing-to-offer`,
  `gascity-test-sling-entry-prefetches-formulas`,
  `gascity-test-sling-preview-keeps-state-and-s-slings-it`,
  `gascity-test-sling-preview-is-transient`,
  `gascity-test-sling-reentry-restores-and-x-resets`. The shared suite
  (`lisp/test/gascity-test.el`) additionally pins the var machinery
  against the reserved set:
  `gascity-test-formula-sling-var-children-shapes`,
  `gascity-test-formula-sling-var-children-nil-formula-degrades`,
  `gascity-test-sling-var-key-deterministic`,
  `gascity-test-sling-var-keys-stable-and-unique`, and carries the
  layout-coupled transient tests the rewrite must port
  (`gascity-test-sling-unified-wiring`, `-unified-layout`,
  `-target-set-and-header`, `-arg-edit-re-setups-in-place`,
  `-dispatch-target-fallback`, `-plain-path-unchanged`,
  `-preview-dry-run-paths`, `gascity-test-formula-sling-dispatch-shapes`,
  `gascity-test-formula-sling-preview-fresh-show`, the city-pinning set
  `-city-dir-pins-entered-from-city`, `-dispatch-prefix-seeds-city-dir`,
  `-dispatch-pick-pins-city-dir`, `-children-specs-read-recipe-pinned`,
  `-dispatch-suffixes-run-pinned`, `-reserved-keys-complete`),
  while the command-line/cache tests
  (`-sling-command-line`, `-rich-command-line`, `-parse-transient-args`,
  `-on-command-line`, the `gascity-test-formula-*` cache/enum/history
  set, `gascity-test-store-formula-refresh-async-swaps-caches`,
  `gascity-test-remote-sling-plan-view`) exercise the retained plumbing.
- **Docs**: `doc/gascity.texi` carries a four-line Sling item under
  "Dispatch and lifecycle"; `docs/DESIGN-write-actions.md` §10
  documents the current unified transient (which this redesign
  supersedes).

Gaps against the requirements: the plain path prompts for derivable
answers (REQ-001/005); the shape is invisible until dispatch decides
it (REQ-002); the work picker is a plain `read-string` (REQ-003);
`--formula`/`--on` selection is implicit in dispatch, not displayed
(REQ-004); Who is session completion, not agent-centric, with no
derived default (REQ-005); vars are enum/bool/string only — no file,
directory, agent or numeric readers (REQ-006); there is no live footer
(REQ-007), no client-side preview buffer (REQ-008), no follow offer
(REQ-009), and no pre-launch validation of the known gc failure modes
(REQ-010). The layout does not match the signed-off mockups (REQ-011).

## Proposed Implementation

### Affected areas

| Area | Change | Work |
| --- | --- | --- |
| `lisp/gascity-formula.el` | shape inference + header sentence; typed var infix subclasses and heuristics; bl-bdj / cross-store / missing-piece predicates; title-slug helper | WI-1, WI-2, WI-5 |
| `lisp/gascity-agents.el` | completion-facing roster accessor: agents grouped city-first then per rig, annotated with scope and live state; scope classification | WI-2 |
| `lisp/gascity-action.el` | adaptive staged layout per the mockups; smart work picker `A`; agent-centric Who `T`; derived default; live footer; `P` preview buffer; follow offer; new reserved-key set | WI-3, WI-4, WI-6, WI-7, WI-8, WI-9 |
| `lisp/test/gascity-sling-test.el` | the seven tests ported; new tests for inference, heuristics, defaults, warnings, follow | WI-10 |
| `lisp/test/gascity-test.el` | var/reserved-key tests updated for the new key set | WI-10 |
| `doc/gascity.texi`, `doc/screenshots/`, `docs/DESIGN-write-actions.md` | full sling chapter, screenshots, §10 update | WI-12 |
| `docs/qa/` | e2e dogfood report of the four scenarios | WI-11 |

### Work items

**WI-1 — Shape inference and the one-sentence header** (REQ-001,
REQ-002). Pure functions in `gascity-formula.el`: a
`gascity-sling--shape` over (work, formula) returning `plain` /
`formula` / `on` (formula nil ⇒ plain; formula + work ⇒ `--on`;
formula without work ⇒ `--formula`), and a header-sentence renderer
with the mockups §1–§4 wording ("Sling bead bl-5ja to mayor", "Run
pancakes (formula) on mayor", "Run build-basic against bead bl-5ja,
drained by …"). The sentence's "drained by" clause consults
`gascity-formula--needs-convoy` on the cached recipe. Display only:
dispatch keeps `gascity-formula--needs-convoy` as the authoritative
shape rule, and a convoy-requiring formula with no work becomes a
footer warning (mockup §5c) rather than a new blocking prompt.
`gascity-sling--scope-info` is replaced by the sentence. Unit tests
pin every shape × work-presence combination and the exact mockup
sentences.

**WI-2 — Roster accessor and the client-side validators** (REQ-005,
REQ-010). In `gascity-agents.el`: a completion-facing accessor over
the existing loaders producing `(name . annotation)` candidates
city-first then per rig, annotated `<rig|city> · <state>` with
`gascity-agents--state-label`, plus a scope classifier (`city` or the
rig name — roster `:rig`, or the name's slash prefix; a cold roster
never dead-ends: free entry works, scope-dependent checks degrade).
In `gascity-formula.el`, pure predicates over cached data:
`gascity-sling--binding-targets-p` (any step of the cached recipe
carries a binding-qualified `metadata["gc.run_target"]` — a value
containing `.` and no `/`; verified against bright-lights: build-basic
exposes 24 such steps, e.g. `gc.run-operator`);
`gascity-sling--v2-trap-p` (binding-qualified run targets **and** a
city-scoped target ⇒ the bl-bdj warning, mockup §5a wording — the
trap fires at instantiation, dry run does not exercise it, so the
client warns); `gascity-sling--cross-store-p` (the work bead's store,
from its id prefix against the rig memo `gascity-rigs-cached` /
`gascity-rigs-cached-prefixes` — the same prefix-routing the bd verbs
use — vs the target's store: a rig-scoped agent names its rig, a city
agent the city store ⇒ warning, mockup §5b); plus the §5c
missing-pieces checks (no work for a drain formula, missing required
vars, no target). All are pure and unit-tested with fixture payloads.

**WI-3 — Derived Who default** (REQ-005). A
`gascity-sling--derive-target` over (scope, roster, memory), in the
design's order: (1) the work bead's rig `default_sling_target` /
`default_sling_targets` when resolvable from rig data gascity already
reads (fail-soft skip otherwise — recorded under Open Implementation
Details); (2) per-(city, formula) target memory — a new
`gascity-sling--target-memory` alist recorded on launch; (3) the
implementation-worker convention: the roster's exactly one rig-scoped
`gc.implementation-worker` when unambiguous. The derived target
carries a `derived` tag in the header and is the `T` picker's initial
input; `s` uses it without prompting. Tests pin the precedence order,
the exactly-one ambiguity rule, and memory hits/misses.

**WI-4 — Adaptive layout and the three pickers** (REQ-001, REQ-003,
REQ-004, REQ-011). Rewrite `gascity-sling--children-specs` in
`gascity-action.el` to the mockup layout: first group the city title +
one-sentence header + live footer (WI-6); `What` with `A` (completing
read over the city's open/in-progress/blocked beads plus convoys
through the store, annotated `title · status · store`; `C-u A` goes
straight to freeform; empty RET falls through to `Bead id or task
text:`; point pre-seeds as today) and `f` (the existing union picker,
annotations kept); `Who` with `T` (WI-2 candidates, derived default as
initial input); `How` — the picked formula's typed infixes (WI-5),
titled `How — <formula> vars`, full width, absent without a formula;
the routing-flags group rendered **only** on the plain shape (F-5);
`Actions` `s P r g x q`. An answered stage is its one line with the
answer visible and the binding still live; unanswered shows its pick
hint. The scope plist grows `:work` (bead/convoy id or freeform text,
generalizing `:arg`). `gascity-sling--reserved-keys` becomes
`A f T c a n m t s P r g x q` (`p` freed, `P` added). Tests assert the
children-specs shape per mockup state and the reserved-set sync.

**WI-5 — Typed How vars** (REQ-006). In `gascity-formula.el`, new
infix subclasses beside the existing enum/bool/string ones: a file
option (`read-file-name` relative to the target rig's workdir, pinned
`default-directory`, TRAMP-safe), a directory option
(`read-directory-name`), an agent option (the `T` roster completion),
and a numeric option (digit validation refusing `Var %s must be
numeric (got %s)` before any gc call). A `gascity-sling-formula--var-class`
heuristic picks the class: an overridable `gascity-sling-var-readers`
alist (var name → reader function) first, then naming conventions
(`context_path` / `*_path` → file; `artifact_root` → directory;
`*_target` → agent; `rig_name` → a string auto-derived from the
chosen target's rig, editable; numeric by all-digit declared default
or the `max_*`/`*_iterations` convention), and anything unrecognized
fails soft to the string option. A `gascity-sling--title-slug`
derives the `artifact_root` seed `plans/<slug>/` from the work bead's
**title** (repo practice `plans/dashboard-v3/`: downcase, non-alphanumeric
runs → `-`), falling back to freeform text or the formula name —
never the bare bead id. `gascity-sling-formula--current-values` and
the deterministic key assignment are unchanged. Tests: class
selection, numeric refusal, slug derivation and fallbacks, pinned
default-directory on the file/dir readers, override-alist precedence.

**WI-6 — Live footer** (REQ-007, REQ-010). A pure
`gascity-sling--footer` over (scope, roster, recipe): the one-sentence
launch summary — `✓ Ready — <shape> · target <name> (<scope>) · N of M
vars set` — or `⚠ <reason>`, per mockup §1–§5. The footer renders as
part of every transient setup, so it recomputes as each answer
changes, from cached data only (no gc on the render path). Full
warning detail lives in the `P` buffer; the footer never blocks `s`.
Tests recompute the footer across scope changes and pin the warning
wordings.

**WI-7 — `P` full preview buffer** (REQ-008). A
`gascity-sling-dispatch-full-preview` building its buffer through
`gascity-view-get-buffer-create` (host-qualified, city-pinned):
the header sentence; a **Validation** section (all WI-2 checks with
full text); a **Recipe — <formula> (steps → needs)** section from the
cached recipe (the step/deps data `gascity-sling-formula--render-recipe`
already renders); and a **Routing plan** section filled in when the
`--dry-run` async call answers (the `gascity-sling--show-plan` /
`gascity-action--async-text-view` pattern, rendered into the preview
buffer) — first paint is client-side and never blocks on the dry run.
`s` launches directly from the buffer; `q` quits. `r` keeps the
server-substituted recipe preview. Preview is never a gate: `s` in the
menu works anytime. Tests render the buffer with the store stubbed
and assert the sections, the async fill, and the launch binding.

**WI-8 — Launch and follow offer** (REQ-009). `s` dispatches exactly
as today (`gascity-sling-formula--dispatch` / the plain path via
`gascity-command-act-async`). On a formula-path success, the sling
result's created workflow root bead id (from the `gc sling --json`
payload in the act's `:on-success` — field confirmed in the e2e pass;
see Open Implementation Details) is echoed as `Launched workflow
<id> (<formula> on <work>) — F: run view`, and a momentary follow map
(`set-transient-map`) binds `F` to `gascity-run-show` on that root id;
any other key dismisses; the user stays put. Plain-route launches
keep the plain echo and no offer. Tests stub the result payload and
assert the map, the `F` jump, and the plain path's absence of both.

**WI-9 — State and memory preserved** (REQ-012). `gascity-sling--remembered`
keeps its per-city scope+values contract; the new layout renders from
the scope, so a remembered state reopens the collapsed stages with
their answers; `x` clears work/formula/target/values and forgets; `s`
still forgets after a real launch (S-2). Per-(formula,var) history is
untouched. The per-(city,formula) target memory (WI-3) is recorded on
launch. City pinning (`gascity-sling--city-dir`, ga-4ia4) extends to
every new reader (work picker, agent picker, file/dir completion),
and the entry prefetch plus `g` refresh machinery are unchanged. The
S-2 tests are ported alongside.

**WI-10 — ERT consolidation** (REQ-013). Port the seven
`gascity-sling-test.el` tests to the new layout (`p`→`P` preview
semantics, `A`/`T` pickers, scope `:work`), and update every
layout-coupled sling test in the shared suite `gascity-test.el`: the
var/reserved four (`gascity-test-formula-sling-var-children-shapes`,
`gascity-test-formula-sling-var-children-nil-formula-degrades`,
`gascity-test-sling-var-key-deterministic`,
`gascity-test-sling-var-keys-stable-and-unique`) against the new key
set and typed classes, plus the transient tests the rewrite of
`gascity-sling--children-specs` / `gascity-sling--run` touches:
`gascity-test-sling-reserved-keys-complete`,
`-city-dir-pins-entered-from-city`, `-dispatch-prefix-seeds-city-dir`,
`-dispatch-pick-pins-city-dir`, `-children-specs-read-recipe-pinned`,
`-dispatch-suffixes-run-pinned`, `-unified-wiring`, `-unified-layout`,
`-target-set-and-header`, `-arg-edit-re-setups-in-place`,
`-dispatch-target-fallback`, `-plain-path-unchanged`,
`-preview-dry-run-paths`, and
`gascity-test-formula-sling-dispatch-shapes` /
`gascity-test-formula-sling-preview-fresh-show`. The command-line and
cache tests (`-sling-command-line`, `-rich-command-line`,
`-parse-transient-args`, `-on-command-line`, the
`gascity-test-formula-*` cache/enum/history set,
`gascity-test-store-formula-refresh-async-swaps-caches`,
`gascity-test-remote-sling-plan-view`) exercise the retained plumbing
and are expected to pass unchanged. New tests: shape inference; header sentence; typed-var
heuristics; Who default derivation; the bl-bdj trap warning; the
cross-store warning; the follow offer; footer recompute; reserved-set
sync. Everything stubs the gc boundary (`gascity-test-with-store-stubs`,
`cl-letf` on the reader functions) so the suite stays offline and
fast; the non-blocking guard list in `lisp/test/gascity-store-test.el`
gains any new input-free verb. `scripts/gate.sh` (byte-compile
warnings-as-errors + full ERT) must be green.

**WI-11 — End-to-end verification** (REQ-014). Through
`. scripts/e2e-harness.sh` (timeout-wrapped emacs/emacsclient/tmux,
hard iteration caps): a fresh Emacs inside tmux connected to
`/ssh:localhost:/home/roman/bright-lights`, every gc invocation as
`gc --city /home/roman/bright-lights …`. The four design scenarios:
(1) pancake formula end to end — header sentence, launch, the mayor
session works it, the follow offer jumps to the run view; (2)
build-basic `--on` with typed vars — `context_path` file completion,
`artifact_root` defaulting to `plans/<slug>/`, `rig_name` and
`implementation_target` derived from the target; (3) the bl-bdj trap —
a city-scoped target shows the footer warning before launch, a
rig-scoped target shows ✓; (4) plain dispatch — bead at point, `S`
then `s` with zero prompts, freeform text via the prefix arg. The
dogfood report lands under `docs/qa/` and the screenshots (WI-12) are
captured from this same session.

**WI-12 — Documentation** (REQ-015). A complete Texinfo chapter for
the sling command in `doc/gascity.texi` at the PostgreSQL-documentation
quality bar: the unified flow (What → Who → How → Preview → Launch →
Follow), every shape, the three pickers, the typed readers, the
validation warnings, the `P` preview buffer, the follow offer, and
the key summary (mockup §10). The four-line Sling item in "Dispatch
and lifecycle" becomes a pointer; `docs/DESIGN-write-actions.md` §10's
unified-sling subsection is updated to the redesign (the design
supersedes it). `make -C doc` builds with the existing toolchain
(`doc/Makefile`, `manual.css`); real screenshots of the transient's
states live under `doc/screenshots/` wired like the existing images,
captured from the WI-11 session; momentary states that cannot be
captured faithfully fall back to mockup renderings (requirements Open
Question), noted in the QA report.

### Sequencing

Six waves, each ending with `scripts/gate.sh` green and one commit per
work item (`type(scope): summary (bead-id)`, e.g.
`feat(sling): …`):

1. **WI-1, WI-2** — pure foundations (inference, roster accessor,
   validators), fully testable offline before any UI churn.
2. **WI-3, WI-4** — the adaptive transient lands: new layout, pickers,
   derived default, reserved-key set change.
3. **WI-5** — typed vars, generating the How group against the final
   reserved set.
4. **WI-6, WI-7, WI-8** — footer, preview buffer, follow offer.
5. **WI-9, WI-10** — state/memory adaptation and the full ERT pass
   (port + new) with the gate green.
6. **WI-11, WI-12** — the live verification pass and the
   documentation chapter + screenshots from that session.

Rationale: inference-first keeps the layout rework test-driven; typed
vars come after the layout so generated keys are computed once against
the final reserved set; e2e and docs are last because the screenshots
must come from the verified live session. The order follows the
design's implementation sequence (shape → pickers/Who → vars →
footer/preview → follow → e2e).

### Risks and mitigations

- **Sling result payload** — the created-workflow root bead id needed
  by the follow offer must come out of `gc sling --json`. Confirmed
  in the e2e pass (WI-8/WI-11); fallback: resolve the newest workflow
  root via a store `bd list` read before showing the offer; never a
  guess. See Open Implementation Details.
- **Render-time gc** — the footer/preview must never spawn a
  synchronous gc (D9). Roster/recipe/catalog read through the store
  caches; validation is pure over cached payloads; a cold roster skips
  scope-dependent checks (free entry still works).
- **Reserved-key churn** (`p` freed, `P` added): the deterministic
  var-key algorithm already avoids the reserved set; the sync tests
  in `gascity-test.el` pin it; a var that previously took `p` now gets
  another key — acceptable (keys are per-formula deterministic, not
  user-stable).
- **TRAMP completion latency** on file/dir readers against a remote
  rig workdir: completion can be slow — the readers fail soft to
  typed text, the e2e harness wraps every call in `timeout(1)`, and
  the bright-lights pass exercises it.
- **Ephemeral screenshot states** (follow offer, footer variants):
  capture feasibility is left to the verification pass, with mockup
  renderings as the documented fallback (requirements Open Question).
- **Layout fidelity** to the mockups: acceptance walks each mockup
  state §1–§10 during WI-11; deviations are recorded in the QA report.
- **Test churn from the scope change** (`:arg` → `:work`): the seven
  ported `gascity-sling-test.el` tests **and** the ~18 layout-coupled
  `gascity-test.el` tests (enumerated in WI-10) are updated with the
  layout work (WI-4/WI-10 together) to avoid porting twice.

## Non-Goals

Per the approved design's explicit non-goals and the requirements'
Out Of Scope:

- **Named presets / repeat-last dispatches** — rejected;
  per-(formula,var) history and per-(city,formula) target memory
  already cover reuse.
- **Abort/pause affordance for running workflows** — out of scope
  (surfaced by the ga-kqo0 stop incident; revisit after the redesign
  lands, possibly upstream in gc).
- **A separate quick-sling command** — rejected; plain dispatches
  flow through the same unified transient.
- **Upstream PRs** — the polecat contract allows local commits to
  `main` only.
- **Touching the unrelated stopped worktree `worktrees/ga-tbte`**, or
  committing the pre-existing uncommitted deletions under
  `plans/dashboard-v2/`.
- **gc-side changes** (e.g. teaching gc about the bl-bdj trap) — the
  client warns; gc stays the authority.
- **Blocking validation** — warnings are unmissable but never block
  `s`.
- **Sessions as the Who** — Who is agent-centric; free text entry
  stays available.

## Verification

### Test strategy

All new logic is pure or stubbed at the gc boundary; the suite stays
offline and fast (repo conventions: `cl-letf` on
`gascity-reader-read*` / the action verb, `gascity-test-with-store-stubs`,
fresh store per test in `gascity-test-helpers.el`).

- Ported (WI-10): the seven `gascity-sling-test.el` tests above.
- Updated (WI-10): the var/reserved four
  (`gascity-test-formula-sling-var-children-shapes`,
  `gascity-test-formula-sling-var-children-nil-formula-degrades`,
  `gascity-test-sling-var-key-deterministic`,
  `gascity-test-sling-var-keys-stable-and-unique`) against the new
  reserved set, plus the layout-coupled transient tests enumerated in
  WI-10 (`-unified-wiring`, `-unified-layout`, `-target-set-and-header`,
  `-arg-edit-re-setups-in-place`, `-dispatch-target-fallback`,
  `-plain-path-unchanged`, `-preview-dry-run-paths`,
  `gascity-test-formula-sling-dispatch-shapes`,
  `gascity-test-formula-sling-preview-fresh-show`, the city-pinning and
  children-specs set, `-reserved-keys-complete`).
- New: shape inference (REQ-002), header sentence (REQ-001/002), work
  picker fallbacks (REQ-003), shape flip on formula pick (REQ-004),
  Who default derivation order (REQ-005), typed-var heuristics and the
  numeric guard (REQ-006), footer recompute (REQ-007), preview buffer
  sections and async fill (REQ-008), follow offer (REQ-009), bl-bdj
  trap warning (REQ-010), cross-store warning (REQ-010), layout
  states + reserved sync (REQ-011), remembered-state reopen
  (REQ-012).
- Gate: `scripts/gate.sh` (`eldev compile --warnings-as-errors` + the
  full ERT suite) green — acceptance criterion 11.

### End-to-end verification

The four scenarios of REQ-014 (pancake formula e2e; build-basic `--on`
with typed vars; the bl-bdj trap with city- vs rig-scoped targets;
plain dispatch with point pre-seed and freeform escape), run from a
fresh Emacs inside tmux over TRAMP against
`/ssh:localhost:/home/roman/bright-lights` through
`. scripts/e2e-harness.sh`, every gc call as
`gc --city /home/roman/bright-lights …`. The pass is recorded as a
dogfood report under `docs/qa/`; the same session produces the
screenshots for the manual. Documentation builds with
`make -C doc`; screenshots are wired under `doc/screenshots/` like the
existing images (acceptance criteria 12–13).

### Handoff criteria

- **To the decomposition stage**: each work item above is sized as one
  decomposition unit — it names its files, its new/changed functions,
  its REQ trace, and its tests; nothing here requires another
  planning pass.
- **To plan review**: traceability is the Coverage table below (every
  REQ-001…REQ-015 covered by named work items); feasibility risks are
  listed with mitigations; edge cases (warnings never block, cold
  roster, remote completion, missing dry-run) are carried by the
  requirements' acceptance criteria.
- **Definition of done**: the 13 acceptance criteria of
  `requirements.md` §Acceptance Criteria all hold, `scripts/gate.sh`
  is green, the e2e report and screenshots are committed, and the
  manual chapter builds.

## Open Implementation Details

Recorded here instead of asking (the run is autonomous/headless);
none is blocking — each has a decided default:

- **`gc sling --json` root field for the follow offer** (WI-8): the
  payload field naming the created workflow root is confirmed in the
  e2e pass; if it differs, the fallback (newest workflow root via a
  store `bd list` read, before the offer is shown) applies.
- **Rig `default_sling_target` client-side source** (WI-3): if the
  rig data gascity already reads does not expose the rig's sling
  defaults, derivation rule 1 is skipped fail-soft and rules 2–3
  drive the default; behavior is documented in the manual.
- **Var-key overflow rendering** (REQ-006): if a formula's var set
  cannot avoid all collisions, the mockups' `…` grouped-overflow
  fallback applies — an implementation detail, not a design change.

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

### decomposition.md

---
schema: gc.build.decomposition.v1
workflow:
  id: ga-eavt
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: decompose
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
        - REQ-015
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: beads/ga-emog
      hash: bead:ga-emog
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

# Sling Command Redesign — Decomposition

Decomposition of the approved requirements
(`plans/sling-command/requirements.md`, REQ-001…REQ-015) and implementation
plan (`plans/sling-command/implementation-plan.md`, WI-1…WI-12) for the
`build-basic` workflow rooted at bead `ga-eavt`. Each plan work item became
one work-item bead; the twelve beads are linked by a freshly created
implementation convoy that the `implement` stage will drain.

## Summary

The plan's twelve work items (WI-1…WI-12) map one-to-one to work-item
beads. Each bead's description restates the plan's deliverables for that
item — files, new/changed functions, REQ trace, tests, and acceptance — and
carries `gc.root_bead_id=ga-eavt`, `gc.build.work_item=WI-<n>`, and
`gc.trace.requirements=<REQ ids>` metadata for traceability back to the
requirements and the plan section. The beads are created independent
(no inter-bead dependencies): the plan's six-wave sequencing is recorded
below and enforced by the implement stage's drain order, not by bd
dependency edges, so the convoy drains without artificial gate blocking.
Every requirement REQ-001…REQ-015 is covered by at least one work item (see
Coverage).

Plan sequencing (waves, each ending with `scripts/gate.sh` green and one
commit per work item):

1. WI-1, WI-2 — pure foundations (shape inference, roster accessor,
   validators), testable offline before UI churn.
2. WI-3, WI-4 — the adaptive transient: new layout, pickers, derived
   default, reserved-key set change.
3. WI-5 — typed vars, generated against the final reserved set.
4. WI-6, WI-7, WI-8 — footer, preview buffer, follow offer.
5. WI-9, WI-10 — state/memory adaptation and the full ERT pass.
6. WI-11, WI-12 — live verification pass; documentation and screenshots
   from that session.

## Selected Downstream Formulas

- **`implement`** (`gc.var.implementation_formula`) — drains the
  implementation convoy `ga-04j2` recorded on the workflow root as
  `gc.input_convoy_id` / `gc.build.implementation_convoy_id`. Per-item
  formula `do-work-item` (`gc.var.implementation_item_formula`), execution
  target `gc.implementation-worker`
  (`gc.var.implementation_target`), drain policy `separate`
  (`gc.var.drain_policy`).
- **`review`** (`gc.var.code_review_formula`) — agent-mode code review of
  the implementation (`gc.var.review_mode=agent`).
- **`fix-loop-base`** (`gc.var.review_fix_formula`) — review-driven repair
  iterations, up to `gc.var.max_iterations=10`.
- Publish: the workflow opens a PR and pushes (`gc.var.open_pr=true`,
  `gc.var.push=true`) on `main`.

## Implementation Convoy

A new implementation convoy was created for these work units; the source /
launch convoy `ga-ix9n` (`gc.var.convoy_id`, containing only `ga-emog`) is
**not** reused.

- Name: `sling-command-implementation`
- Convoy id: `ga-04j2`
- Verified via `gc convoy list --json`: status `open`, 12 children,
  progress 0/12 closed.
- Children (WI order): `ga-510r` (WI-1), `ga-0okd` (WI-2), `ga-ntop`
  (WI-3), `ga-f7a4` (WI-4), `ga-o6eh` (WI-5), `ga-pkpi` (WI-6),
  `ga-ub2r` (WI-7), `ga-f4w0` (WI-8), `ga-me2n` (WI-9), `ga-gonl`
  (WI-10), `ga-3wpi` (WI-11), `ga-1wl7` (WI-12).

The workflow root `ga-eavt` records `gc.input_convoy_id=ga-04j2` and
`gc.build.implementation_convoy_id=ga-04j2` for the `implement` stage.

## Work Items

Each work item is one decomposition unit sized per the plan's handoff
criteria (files, functions, REQ trace, and tests named; no further
planning pass required).

| WI | Bead | Title | Requirements |
| --- | --- | --- | --- |
| WI-1 | ga-510r | Shape inference and the one-sentence header | REQ-001, REQ-002 |
| WI-2 | ga-0okd | Roster accessor and the client-side validators | REQ-005, REQ-010 |
| WI-3 | ga-ntop | Derived Who default | REQ-005 |
| WI-4 | ga-f7a4 | Adaptive layout and the three pickers | REQ-001, REQ-003, REQ-004, REQ-011 |
| WI-5 | ga-o6eh | Typed How vars | REQ-006 |
| WI-6 | ga-pkpi | Live footer | REQ-007, REQ-010 |
| WI-7 | ga-ub2r | P full preview buffer | REQ-008 |
| WI-8 | ga-f4w0 | Launch and follow offer | REQ-009 |
| WI-9 | ga-me2n | State and memory preserved | REQ-012 |
| WI-10 | ga-gonl | ERT consolidation | REQ-013 |
| WI-11 | ga-3wpi | End-to-end verification | REQ-014 |
| WI-12 | ga-1wl7 | Documentation | REQ-015 |

Traceability: each bead's `gc.trace.requirements` metadata names its REQ
ids; the plan section of the same name is the authoritative description.
The E2E pass (WI-11) and the documentation chapter (WI-12) close the loop
to REQ-014/REQ-015, including the bright-lights TRAMP acceptance gate and
the screenshots from that same session.

### Coverage

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

### implementation-summary.md (canonical)

---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-eavt
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: summarize-implementation
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-eavt
      hash: bead:ga-eavt
    - path: beads/ga-04j2
      hash: bead:ga-04j2
    - path: beads/ga-3wpi
      hash: bead:ga-3wpi
      ids:
        - REQ-014
    - path: beads/ga-1wl7
      hash: bead:ga-1wl7
      ids:
        - REQ-015
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
        - REQ-015
    - path: plans/sling-command/decomposition.md
      hash: sha256:4ce83b573ba9f63fcd4acb7f305604108ce5a9cde9f7097f5855ec4d91cc0c74
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: worktrees/ga-0okd/plans/sling-command/build/implementation-summary-ga-0okd.md
      hash: sha256:cabcea783a9ecf94000bbd6edf311b75bdeac67dc4fadf992e0b19bbd0e07239
    - path: plans/sling-command/task-ga-f7a4-summary.md
      hash: sha256:1556819350dd4af58d3d742ebe7865636a46271376af7412d5bfa91a2bddf6fa
    - path: plans/sling-command/task-ga-ntop-summary.md
      hash: sha256:5569e0954f7eb05d35f994c1efacffa35c7c9980045589f6cfe84d9c64728d38
    - path: plans/sling-command/task-ga-o6eh-summary.md
      hash: sha256:c0b8d55f090fcb5c57f1349c001ee10db98c8c2628229bd032588a1bd621bae5
    - path: plans/sling-command/build/ga-nij3-implementation-summary.md
      hash: sha256:fd719bf7b827e175d4d0433596a7bb1360d871143f5edfb6928ad22faf4c42d5
    - path: plans/sling-command/task-ga-f4w0-summary.md
      hash: sha256:44c5e40e946d766bc90a8c04a17363c71bfff7383c85d76c697e8466d35babe4
    - path: worktrees/ga-3wpi/plans/sling-command/build/implementation-summary-ga-nqyt.md
      hash: sha256:47dae538218e3dae2d24f5a875fe7edfa674661e42fde8f948f10569d8d0d0be
    - path: worktrees/ga-1wl7/plans/sling-command/task-ga-1wl7-summary.md
      hash: sha256:b17d58aaeecb36e498bb0eaae4dfcb38be1ff883cbea5528898374c381347841
    - path: worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md
      hash: sha256:afcad6e5996d2d5ba634cd8c90a0e54e9625922fd34783e2b067c6ec702dc7f5

  coverage:
    - id: REQ-001
      status: covered
      rationale: One `gascity-sling-dispatch` transient covers plain, --formula and --on; stages collapse when pre-seeded (WI-4 layout, WI-1 inference).
    - id: REQ-002
      status: covered
      rationale: Shape is inferred from work + formula selections and rendered as the one-sentence header; no shape flag (WI-1, commit 8fc52c0).
    - id: REQ-003
      status: covered
      rationale: "`A` work picker over open beads and convoys with annotations; `C-u A` freeform; point pre-seeds (WI-4)."
    - id: REQ-004
      status: covered
      rationale: Formula picker over catalog ∪ `gc formula list`; --on vs --formula follows work-in-scope (WI-4).
    - id: REQ-005
      status: covered
      rationale: Agent-centric Who picker grouped by rig with scope/state; derived default (rig default, memory, implementation-worker convention) shown with `derived` tag (WI-2, WI-3).
    - id: REQ-006
      status: covered
      rationale: Typed readers per var class — file/dir completion (plans/<slug>/ seed), agent picker for *_target, numeric validation (WI-5, commit 2f83f30).
    - id: REQ-007
      status: covered
      rationale: Live one-sentence footer recomputed as each answer changes, with ✓/⚠ status (WI-6, commit 80c35dd).
    - id: REQ-008
      status: covered
      rationale: "`P` preview buffer with recipe DAG, gc dry-run routing plan and all warnings; never gates `s` (WI-7)."
    - id: REQ-009
      status: covered
      rationale: "`s` dispatches and offers a follow jump to the run view; launch records the target per (city, formula) (WI-8)."
    - id: REQ-010
      status: covered
      rationale: Client-side validators warn on the bl-bdj trap and cross-store refusals in the footer before launch; gc stays the authority (WI-2, WI-6).
    - id: REQ-011
      status: covered
      rationale: Mockup menu (What/Who/How/Actions) rendered with the three pickers per menu-mockups.md (WI-4).
    - id: REQ-012
      status: covered
      rationale: State and memory preserved across the redesign — remembered answers and per-(city, formula) target memory survive reopens (WI-9, commit af56c49).
    - id: REQ-013
      status: covered
      rationale: Existing sling ERT suite ported to the redesign layout and consolidated (WI-10, commit 426d2fd).
    - id: REQ-014
      status: covered
      rationale: Four-scenario live e2e pass over plain-ssh TRAMP against bright-lights through scripts/e2e-harness.sh; gate 723/723 green (WI-11).
    - id: REQ-015
      status: covered
      rationale: Texinfo Sling Command chapter with the redesign flow, shapes, pickers, typed readers, warnings, preview and follow offer (WI-12).

---

# Implementation Summary: Sling command redesign (workflow ga-eavt)

## Summary

The build finalized the full sling command redesign across the twelve
work items (WI-1 … WI-12) of implementation convoy `ga-04j2`, with
source anchors `ga-510r`, `ga-0okd`, `ga-ntop`, `ga-f7a4`, `ga-o6eh`,
`ga-pkpi`, `ga-ub2r`, `ga-f4w0`, `ga-me2n`, `ga-gonl`, `ga-3wpi`, and
`ga-1wl7`.  The old flag-driven sling transient was replaced by one
adaptive staged transient (`gascity-sling-dispatch`) covering plain,
`--formula`, and `--on` shapes with shape inference, a derived Who
default, typed How vars, a live validating footer, a full preview
buffer, and a post-launch follow offer.  Every item was implemented in
its own isolated worktree; the WI-11 e2e pass merged the still-open
sibling items (WI-5 typed vars `cc5d836`, WI-6 footer `80c35dd`) into
its item worktree, found and fixed three integration seams, and
verified all four design scenarios live over TRAMP against
`/home/roman/bright-lights` (`gc --city /home/roman/bright-lights …`).
The dogfood report is
`worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`.
Per-item summaries: `plans/sling-command/task-ga-ntop-summary.md`
(WI-3), `plans/sling-command/task-ga-f7a4-summary.md` (WI-4),
`plans/sling-command/task-ga-o6eh-summary.md` (WI-5),
`plans/sling-command/build/ga-nij3-implementation-summary.md` (WI-7),
`plans/sling-command/task-ga-f4w0-summary.md` (WI-8),
`plans/sling-command/task-ga-gonl-summary.md` (WI-10),
`worktrees/ga-0okd/plans/sling-command/build/implementation-summary-ga-0okd.md`
(WI-2),
`worktrees/ga-3wpi/plans/sling-command/build/implementation-summary-ga-nqyt.md`
(WI-11), and
`worktrees/ga-1wl7/plans/sling-command/task-ga-1wl7-summary.md`
(WI-12).  WI-1 (`8fc52c0`), WI-6 (`80c35dd`), and WI-9 (`af56c49`)
were implemented without recorded per-item summary files; their
evidence here is the merged worktree history, the ported ERT suite,
and the WI-11 live pass, which exercised the header sentence
(REQ-001/REQ-002), the footer (REQ-007), and the state/memory behavior
(REQ-012) directly.

## Intended Behavior

- One `S` press from any gascity view opens `gascity-sling-dispatch`;
  shape (plain / `--formula` / `--on`) is inferred from the work and
  formula selections and stated in the one-sentence header — never
  picked with a flag (REQ-001, REQ-002).
- `A` picks from the city's open beads and convoys (annotated, `C-u A`
  freeform); `f` picks from the formula catalog ∪ `gc formula list`;
  the Who default is derived (rig `default_sling_target` →
  per-(city, formula) memory → implementation-worker convention) and
  shown with a `derived` tag (REQ-003, REQ-004, REQ-005).
- Formula vars read with the right reader per class: file/dir
  completion (TRAMP-safe, `artifact_root` seeded `plans/<slug>/`),
  agent picker for `*_target`, numeric validation for
  `max_iterations` (REQ-006).
- The live one-sentence footer recomputes summary and ✓/⚠ validation
  status after every answer, warning on the bl-bdj trap and
  cross-store refusals before launch; `P` opens the full preview
  (recipe DAG, gc dry-run routing plan, warnings) without gating `s`
  (REQ-007, REQ-008, REQ-010).
- `s` launches via the existing gc plumbing and offers a momentary
  follow jump to the created run's view; state and remembered answers
  survive quit+reopen (REQ-008, REQ-009, REQ-012).
- Verification: the four-scenario e2e pass runs against the
  bright-lights city, always as `gc --city /home/roman/bright-lights …`
  (REQ-014); the manual gets a complete Sling Command chapter with
  mockup-rendered screenshots (REQ-015).

## Changed Files

- `lisp/gascity-action.el` — the redesigned staged transient, launch
  and follow offer, footer validation, preview wiring.
- `lisp/gascity-formula.el` — shape inference, one-sentence header,
  typed-var heuristics, nil-recipe guards, cache/state preservation.
- `lisp/gascity-agents.el` — grouped agent roster with rig-vs-city
  scope metadata and the classifier's slash-prefix fallback.
- `lisp/test/gascity-sling-test.el`, `lisp/test/gascity-agents-test.el`
  — ported suite plus regression tests for shape inference, typed
  readers, Who default, bl-bdj trap, cross-store warning, follow
  offer, nil recipe, and derived-target header.
- `doc/gascity.texi` + `doc/images/` — the Sling Command chapter
  (§10) with mockup renderings.
- `docs/qa/2026-09-27-wi11-sling-redesign-e2e.md` — the e2e dogfood
  report.
- Implementation work: `8fc52c0` (WI-1 header/shape inference),
  `80c35dd` (WI-6 live footer), `af56c49` (WI-9 launch target memory),
  merged into the WI-11 worktree at `e44dcf0` (see Verification).

## Verification

First verification commands (per item, and after merging the sibling
items into the WI-11 worktree):

```
eldev compile --warnings-as-errors && eldev test
scripts/gate.sh
```

Observed: compile clean; 721/721 tests green on the merged tree
before the live pass; WI-1's first verification recorded in
`bd8007e` provenance.

Final proof commands (the live acceptance gate, WI-11):

```
. scripts/e2e-harness.sh
e2e_kill_emacs && e2e_start_emacs && e2e_emacs_ready
# drive the four REQ-014 scenarios against
# /ssh:localhost:/home/roman/bright-lights
scripts/gate.sh
```

Observed: all four scenarios verified live (pancakes end to end,
build-basic `--on` typed vars, the bl-bdj footer trap, plain
dispatch); the pass found three integration seams (nil-recipe crash,
footer vs Who default, roster scope classifier) fixed with regression
tests; `scripts/gate.sh` → `>>> gate: PASS (compile clean + tests
green)` — 723/723 tests, 2026-09-27.  Full evidence:
`worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`.

## Remaining Risks

- Findings recorded in the WI-11 dogfood report await the review/fix
  loop: read aborts close the whole transient; var answers set after
  the last re-setup are lost across quit+reopen; typed path vars over
  TRAMP answer TRAMP-prefixed names gc cannot consume; the rig memo
  misses the HQ rig in cockpit-only sessions; `*_target` var seeds
  ignore the Who default; the formula path never nudges the target;
  `C-u S` has no freeform escape.
- WI-12's screenshots are mockup renderings, not live GUI captures (a
  `-nw` tmux Emacs cannot produce the manual's GUI shots); a GUI
  session should replace them later.
- The bright-lights city carries live pass evidence (bl-9jmm closed,
  hw-5o1 running, hw-4wz in progress, fixture beads bl-4rvq/bl-23by).
- The implementation commits live on the item worktrees/branches; the
  finalize stage merges them to `main` (branch `main`, per
  `gc.work_branch`).

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
