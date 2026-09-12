---
plan_slug: formula-sling-ui
phase: requirements
rig: gascity.el
rig_root: /home/roman/workspace/gascity.el
artifact_root: /home/roman/workspace/gascity.el/plans
status: approved
created_at: 2026-09-10T13:30:00Z
updated_at: 2026-09-10T13:30:00Z
---

# Requirements: Formula-aware sling UI for gascity.el

## Problem Statement

Slinging work is the central dispatch verb of Gas City, and formulas are how
recurring work should be dispatched (`gc sling <target> <formula> --formula`,
or `gc sling <target> <bead> --on <formula>` for convoy-first/drain
formulas). gascity.el's current sling UI (`gascity-sling-dispatch` in
`lisp/gascity-action.el`) treats formulas as an afterthought:

- `-f` is a bare `--formula` toggle; the formula name must be typed from
  memory. There is no discovery of what formulas exist (`gc formula catalog
  --json` is never consulted), no descriptions shown, no way to browse.
- Formula variables are collected by a crude repeated `read-string` loop
  (`gascity-sling--read-vars`) asking for raw `key=value` strings. The user
  must know each variable's name, whether it is required, what its default
  is, and which values are legal — none of which is surfaced.
- There is no history: every sling re-types identical values from scratch.
- `enum` and `pattern` constraints declared by the formula are not enforced
  client-side, so errors only surface as gc failures after the fact.
- The compiled recipe (`gc formula show <name> --json` — steps, deps,
  substituted titles) is invisible while composing the sling.

All of this must work over TRAMP (a remote city such as
`/ssh:localhost:/home/roman/bright-lights`), like everything else in
gascity.el.

## Solution

A formula-aware sling transient in gascity.el, built dynamically from gc's
own JSON metadata. Formulas are dynamic — different formulas declare
different variables with different shapes — so the UI is **generated per
formula** from `gc formula show <name> --json` rather than hand-written per
formula:

1. **Formula selection.** A new infix in the sling transient opens a
   completing-read over `gc formula catalog --json` candidates, annotated
   with each formula's `description` (via `:annotation-function`).
   Selecting one re-builds the transient with a Variables section generated
   from that formula's `vars[]`. The catalog read goes through the existing
   gc reader (`process-file` on the view's `default-directory`) and is
   cached per city/host identity.

2. **Generated per-variable infixes.** Each declared var becomes its own
   transient infix, shaped by its metadata:
   - `enum` vars render as choice infixes (`:choices` completion or radio
     group) — illegal values are unrepresentable.
   - vars whose default is `true`/`false` render as boolean toggles.
   - all others render as string options reading from the minibuffer with
     the var's `description` as prompt and its `default` as the initial
     placeholder.
   - `required` vars are visually marked and enforced before dispatch;
     `pattern` vars are regex-validated client-side on entry, failing fast
     with a clear message instead of a post-hoc gc error.
   - The infix description carries the var's description and default so the
     transient is self-documenting.

3. **Per-variable history.** Each variable keeps its own minibuffer history
   (a history list per formula+var key, not one shared history), so `M-p`
   in a var prompt recalls previous values for *that* variable — e.g.
   previous `artifact_root` values, previous `drain_policy` choices.
   Histories persist across Emacs sessions (savehist-compatible).

4. **Live recipe preview.** A suffix re-runs `gc formula show <name> --json`
   with the currently-set `--var` values and displays the compiled recipe
   (steps, dependency edges, substituted titles) in the existing view-buffer
   affordance, so the user sees what will be materialized before slinging.
   The existing `--dry-run` routing-plan preview stays.

5. **Both sling shapes.** Targetless (`gc sling <target> <formula>
   --formula --var …`) and targeted (`gc sling <target> <bead> --on
   <formula> --var …`, for convoy/drain formulas — pre-seeded from the bead
   or convoy at point). The transient detects whether the chosen formula
   references `{{convoy_id}}`/has drain steps and offers the appropriate
   shape.

6. **TRAMP-transparent.** Catalog reads, recipe previews, and the sling
   itself all run through the existing single gc call site against the
   view's `default-directory`; caches (catalog, per-formula recipe) are
   keyed by remote identity so a local and a remote city never cross-contaminate.
   Buffer names continue through `gascity-remote-buffer-name`.

The implementation may touch beads.el only if it can reuse existing
transient-generation or history infrastructure from there (its
`beads-meta` machinery is the reference pattern); gascity.el is the primary
target. Nothing in the gc CLI changes.

## User Stories

- As a mayor dispatching a build, I press `S` on a convoy, pick
  `build-from-convoy` from the catalog list (reading its description), set
  `drain_policy` from a radio of `separate`/`same-session`, accept defaults
  for the rest, and preview the compiled graph — all without leaving the
  transient and without typing a single `--var` string.
- As a user who slings `implement` daily, I press `M-p` in the
  `artifact_root` prompt and get the path I used last time, and my
  `context_path` history is distinct from my `summary_path` history.
- As a user on a remote city over TRAMP, the formula catalog I browse and
  the recipe I preview come from the remote host's gc, and the sling lands
  in the remote store.
- As a user who forgot a required var, I am told *which* vars are missing
  when I try to sling — before any gc call — instead of a raw gc error.
- As a curious user, I can preview a formula's compiled steps from the
  transient without slinging anything.

Acceptance criteria:

- Formula picker lists every `gc formula catalog` entry with description
  annotation; empty/broken catalog yields a clear message, not a cryptic error.
- The transient's Variables section is generated from the selected formula's
  `vars[]` and rebuilds when a different formula is chosen; a formula with
  no vars shows no Variables section.
- enum vars restrict input to declared values; boolean-default vars toggle;
  required vars block dispatch with a message naming the missing var(s);
  pattern violations are rejected at entry time.
- Each var has an independent history list; histories survive restart
  (savehist) and are keyed per formula+variable.
- Preview shows the compiled recipe with current var values substituted;
  `--dry-run` routing plan preview still works.
- `--on` shape works from a bead/convoy at point; targetless `--formula`
  shape works from the status dashboard.
- The full flow works against `/ssh:localhost:/home/roman/bright-lights`
  in a fresh Emacs inside tmux (see AGENTS.md "Remote test city &
  end-to-end testing"); ERT unit tests cover the mocked units with the
  standard `cl-letf` reader stubbing.
- `scripts/gate.sh` passes.

## Out Of Scope

- No changes to the gc CLI, formula spec, or pack formulas.
- No formula authoring/editing UI (writing or editing `.formula.toml`).
- No orders UI (`gc order` remains CLI-only).
- No rework of the non-formula sling path (text/bead slings keep today's
  behavior, including the existing flag infixes).
- No var-value persistence beyond minibuffer history (no per-city saved
  presets; a future enhancement).
- No new dependency on packages outside gascity.el's current set (transient
  is already a dependency).

## Other Notes

- `gc formula show <name> --json` returns `vars[]` with `name`,
  `description`, `default`, and (per the formula spec v2) `required`,
  `enum`, `pattern`; the compiled recipe also includes `steps[]` and
  `deps[]`, and drain/`{{convoy_id}}` formulas are detectable from the
  compiled steps/metadata (`gc.drain_formula`, `{{convoy_id}}` references).
  Confirm exact JSON shapes against the live gc during planning; where a
  field is absent from the JSON, degrade gracefully (string infix) rather
  than erroring.
- Per-variable history should be keyed `formula:var` so the same variable
  name in different formulas keeps separate histories.
- The existing transient (`gascity-sling-dispatch`) is bound from several
  views (`gascity.el`, `gascity-rig.el`, `gascity-session.el`,
  `gascity-status.el`); keep those bindings and the DESIGN-write-actions.md
  §5.2/§10 conventions — commit subjects cite design sections.
- Commit convention: `type(scope): summary` with body citing the design
  section; live QA report goes under `docs/qa/` after the tmux-Emacs e2e
  pass.
