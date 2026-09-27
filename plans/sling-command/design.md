# Sling Command Redesign — Design

Status: design approved with the user (2026-09-27); menu mockups rendered and
attached for review (`menu-mockups.md`, this directory) — implementation
pending until the menus are signed off.
Supersedes the sling parts of `DESIGN-write-actions.md` §10 and the current
`gascity-sling-dispatch` transient.

## Goals

A world-class single command for dispatching work in Gas City from Emacs:

- One entry point (`S`) covering plain, `--formula`, and `--on` sling shapes.
- Zero questions when the answer is derivable; full typed guidance when it
  isn't.
- Confidence before launch: live summary + on-demand full preview.
- Test ground: bright-lights city (`/home/roman/bright-lights`). Pancake
  formula first, then build-basic.

## Non-goals (explicitly decided)

- **Named presets / repeat-last dispatches** — rejected. Per-(formula,var)
  history and per-(city,formula) target memory (both kept from the old
  implementation) already cover reuse.
- **Abort/pause affordance for running workflows** — out of scope for this
  redesign (surfaced by the ga-kqo0 stop incident; revisit after the redesign
  lands, possibly upstream in gc).
- **A separate quick-sling command** — rejected; plain dispatches flow
  through the same unified transient.

## CLI mechanics (what the Emacs layer drives)

- Shapes: plain (`gc sling <agent> <bead-id-or-text>`), `--formula`
  (untargeted: agent gets the formula run), `--on` (targeted drain:
  formula runs against a bead).
- Vars: `--var k=v`, repeatable. `--dry-run` prints gc's routing plan.
- Cross-store routes are refused by gc; the Emacs layer should catch these
  before launch (see Validation).
- Known trap (bl-bdj, 2026-09-16): a v2 formula with binding-qualified step
  `run_targets` fails against a **city-scoped** target agent ("unknown
  formulas v2 target"); the same dispatch to a **rig-scoped** agent works.
  The client-side validator must warn on this shape.

## Architecture: adaptive transient

One transient, `gascity-sling-dispatch`, that re-specializes after each
stage answer. Conceptual stages:

    What → Who → How → Preview → Launch → Follow

- Stages **collapse when pre-seeded by context**: point, remembered state,
  memory defaults. A fully pre-seeded dispatch is: press `S`, press `s`.
- The **shape is inferred** (plain / `--formula` / `--on`) from the chosen
  work + formula and **displayed as one sentence** in the transient header,
  e.g.:
  - "Sling bead ga-tbte to agent gascity.el/implementation-worker" (plain)
  - "Run pancakes (formula) on mayor" (`--formula`)
  - "Run build-basic against ga-tbte, drained by gascity.el/implementation-worker" (`--on`)
- Shape is never chosen via flags. (No toggle key either — decided: fully
  unified flow, inference only.)

### What (work slot)

One smart picker on `A`:

- completing-read over open beads + convoy in scope, annotated.
- Prefix arg = freeform text escape. RET on empty input = fall to a text
  prompt.
- Point still pre-seeds (bead or convoy at point, as today).
- Formula selection (`f`) when the user wants a formula; picking a formula
  with a work selection yields the `--on` shape, without work yields
  `--formula`.

### Who (target)

Agent-centric:

- Completion over **agents**, grouped/annotated by rig (not sessions).
- Default **auto-derived**, shown in the header so `s` launches with zero
  further questions. Derivation order:
  1. rig `default_sling_target`,
  2. per-(city, formula) target memory,
  3. implementation-worker convention for build formulas.
- Client-side validation (see below) warns on the bl-bdj trap and on
  cross-store route refusals before launch.

### How (formula vars)

Full typed completion, one infix per var, derived from the recipe schema:

- enum/methodology/pattern vars: as today (enum choices, methodology
  lookup, pattern validation) plus per-(formula,var) history.
- `context_path` and any `*_path`: **file completion** relative to the rig
  workdir (TRAMP-safe).
- `artifact_root`: **directory completion**, convention default
  `plans/<name>/`.
- `rig_name`: **auto-derived from the chosen target** (editable).
- `*_target` vars: **agent picker** (same agent list as Who).
- Numeric vars: numeric entry / validation.
- Heuristics are overridable per-var (an alist of var-name → function, or
  naming-convention-driven); anything unrecognized **fails soft to string
  entry**.

### Preview

- **Live mini footer always on**: one-sentence launch summary (shape, target,
  non-blank var count) + validation status (✓ / ⚠ with reason). Recomputed
  as the answers change.
- **`P` opens the full preview buffer**: recipe DAG (steps, dependencies),
  routing plan (which agent/session gets each step, from `--dry-run`),
  validation warnings. Launch is available directly from the preview buffer.
- `s` launches anytime — preview is never a gate.

### Launch and Follow

- `s` runs the real dispatch (as today, via `gascity-command-execute`).
- On success: echo "launched workflow <id>" **plus a lightweight follow
  offer** — a hint / momentary key that jumps to the run view for the
  created workflow root bead; anything else dismisses it. **Stay put by
  default** — no buffer yanked away. Reuse the existing runs view
  (`gascity-runs.el` nesting under the workflow root) as the jump target.

### Plain path

Fully unified: when the work is a bead or freeform text and no formula is
chosen, the formula/How stage simply doesn't appear; flow is What → Who →
`S`. Freeform text arrives via the prefix-arg / empty-RET escape.

## Validation (client-side, pre-launch)

- **bl-bdj trap**: v2 formula with binding-qualified step `run_targets` +
  city-scoped target ⇒ warn "formulas v2 target: this formula needs a
  rig-scoped target; the chosen city agent will fail with 'unknown
  formulas v2 target'". Distinguish rig-scoped vs city-scoped agents from
  the agent list metadata.
- **Cross-store routes**: work bead and target agent in different stores ⇒
  warn before launch (gc refuses these; catch it first).
- Validation result is part of the live footer; full detail in the `P`
  buffer. Warnings do not block `s` (gc remains the authority) but the
  footer must make them unmissable.

## State and memory (kept from old implementation)

- Per-(formula,var) history (`gascity-sling-formula--history`).
- Per-(city,formula) target memory (extended to drive the Who default).
- Per-city remembered menu state (`gascity-sling--remembered`) — kept,
  adapted so the collapsed stages re-open from remembered values.
- City pinning behavior (ga-4ia4 fix) preserved.
- Formula catalog/list/recipe caches with async refresh preserved
  (`gascity-formula.el` machinery is largely retained).

## Menu mockups (2026-09-27)

`menu-mockups.md` (this directory) renders every user-facing element of
this design in ASCII against real bright-lights data — the transient in
its fully-pre-seeded, cold, `--formula` and `--on` states, the live
footer's validation variants, all three pickers, the typed var reads,
the `P` preview buffer and the follow offer.  Mocking these up resolved
three rendering-level decisions (now part of this design):

- **Layout**: the stages ARE the transient groups — `What` (`A`, `f`),
  `Who` (`T`), the picked formula's `How` var group, then `Actions`.
  An answered stage collapses to its one line (answer visible, key
  still changes it); unanswered shows its pick hint.  Routing flags
  render only on the plain shape (F-5 kept).  Keys: `A f T c a n m t
  s P r g x q` — `p` is freed (preview is now `P`); `r` stays as the
  server-substituted recipe preview alongside `P`'s client-side DAG.
- **Derived Who default presentation**: the derived target carries a
  `derived` tag in the header and in the `T` picker (initial input);
  the implementation-worker convention applies only when the roster
  confirms exactly one rig-scoped `gc.implementation-worker`.
- **`artifact_root` slug source**: `plans/<slug>/` derives from the
  work bead's TITLE (repo practice: `plans/dashboard-v3/`), falling
  back to freeform text or the formula name; never the bare bead id.

## Documentation deliverable (added 2026-09-27, user decision)

The final result must be documented in the project manual, at the quality
bar of the PostgreSQL documentation: a complete Texinfo chapter for the
sling command in `doc/gascity.texi`, covering the unified flow
(What → Who → How → Preview → Launch → Follow), every shape, the typed
var readers, the validation warnings (bl-bdj trap, cross-store), the
preview buffer and the follow offer — built with the existing manual
toolchain (`doc/Makefile`, `manual.css`, `gascity.html/info`), plus
screenshots of the transient in its states (saved under `doc/screenshots/`,
wired like the existing images).  Screenshots are captured from a live
session against bright-lights — the same session that runs the e2e
verification.  Documentation is part of acceptance, not an afterthought.

## Implementation plan

Files:

- `lisp/gascity-formula.el` — keep catalog/recipe/cache machinery,
  enum/pattern/history helpers; extend with typed-var heuristics
  (file/dir/agent/numeric inference, overridable) and shape inference.
- `lisp/gascity-action.el` — replace the current `gascity-sling-dispatch`
  suffix/section layout with the staged adaptive layout; new work picker
  (`A`), agent-centric Who, live footer, `P` preview buffer, follow offer.
  The `gascity-sling` entry point and `gascity-command-sling` plumbing stay.
- `lisp/gascity-agents.el` — expose grouped-by-rig agent list with
  scope (rig vs city) metadata, needed by Who completion + validation.
- `lisp/test/gascity-sling-test.el` — port the 7 existing ERT tests to the
  new layout; add tests for shape inference, typed-var heuristics, Who
  default derivation, bl-bdj trap warning, follow offer.

Order:

1. Shape inference + one-sentence header (pure functions, fully testable).
2. Work picker + agent-centric Who + validation.
3. Typed How vars.
4. Live footer + `P` preview.
5. Follow offer.
6. End-to-end verification (below).

## Verification plan

Against bright-lights (`gc --city /home/roman/bright-lights …`; note bare
`gc` inside bright-lights misreports cwd discovery — always pass `--city`):

1. **Pancake end-to-end**: from Emacs, `S` → pick pancakes formula → verify
   header sentence (`--formula` shape) → `s` → workflow created, mayor
   session works it; follow offer jumps to run view.
2. **build-basic typed vars**: dispatch build-basic `--on` an open bead with
   `context_path` via file completion, `artifact_root` defaulting to
   `plans/<name>/`, `rig_name` auto-derived from target.
3. **bl-bdj trap**: choose a city-scoped agent for a v2 formula with
   binding-qualified step run_targets ⇒ footer shows the warning before
   launch; rig-scoped agent shows ✓.
4. **Plain dispatch**: bead at point → `S s` with zero prompts (defaulted
   Who); freeform text via prefix arg.
