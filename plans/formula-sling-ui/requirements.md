---
schema: gc.build.requirements.v1
workflow:
  id: ga-c0e
  formula: build-from-requirements
methodology:
  pack: gascity
  name: build-from-requirements
producer:
  formula: build-from-requirements-base
  stage: requirements
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/formula-sling-ui/build/requirements-input.md
      hash: sha256:516aefdc11c39a67031000eb8f7f49ea6b90ebc5005e9f5c2c53588180c7dfaf
      title: "The approved formula-sling-ui requirements draft this artifact restructures"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
        - AC-6
        - AC-7
        - AC-8
    - path: lisp/gascity-action.el
      hash: git:16c2d7b8a77baea264c762f93caef86d26591941
      title: "The current sling transient: gascity-sling-dispatch and its read-string var loop gascity-sling--read-vars"
    - path: docs/DESIGN-write-actions.md
      hash: git:cdae3a365a98f6ebff1ff025be2ff5e39a342317
      title: "Binding design for the mutating actions this UI extends (§5.2 sling, §10 key conventions)"
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
      status: covered
    - id: AC-7
      status: covered
    - id: AC-8
      status: covered
---

# Requirements: Formula-aware sling UI for gascity.el

## Problem Statement

Slinging work is the central dispatch verb of Gas City, and formulas are how
recurring work should be dispatched (`gc sling <target> <formula> --formula`,
or `gc sling <target> <bead> --on <formula>` for convoy-first/drain formulas).
gascity.el's current sling UI (`gascity-sling-dispatch` in
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
gascity.el. The fix is a formula-aware sling transient built dynamically from
gc's own JSON metadata — generated per formula from
`gc formula show <name> --json`, since formulas declare different variables
with different shapes.

## W6H

**What.** A formula-aware sling transient in gascity.el: formula discovery
from `gc formula catalog --json`, per-variable infixes generated from the
selected formula's `vars[]` metadata, per-variable minibuffer history, live
compiled-recipe preview, both sling shapes (`--formula` targetless and `--on
<formula>` targeted at a bead/convoy), all TRAMP-transparent and validated
client-side before dispatch.

**Why.** Dispatching by formula is Gas City's intended recurring-work path,
yet today it is *harder* than a raw CLI invocation from memory: no discovery,
no defaults surfaced, no constraints enforced, no history. Every sling
re-types identical `--var` strings, and mistakes surface only as post-hoc gc
errors.

**Who.** The mayor dispatching builds from the status dashboard, rig
dashboard, session views and convoy lists — anyone who presses `S` today.
Nobody is blocked; everybody retypes.

**Where.** `lisp/gascity-action.el` (the existing `gascity-sling-dispatch`
transient and its var loop), a new formula-metadata module for catalog/recipe
reads and their caches, the four view files that bind the transient
(`gascity.el`, `gascity-rig.el`, `gascity-session.el`,
`gascity-status.el` — bindings kept as-is), ERT stubs in
`lisp/test/gascity-test.el`, and a `docs/qa/` report. The gc CLI, formula
spec and pack formulas are **read, not changed**. beads.el's `beads-meta`
machinery is a reference pattern, reused only if its transient-generation or
history infrastructure fits.

**When.** After this artifact and its plan; the workflow runs autonomously
(interaction mode recorded in the plan). Nothing ships until
`scripts/gate.sh` passes and the tmux-Emacs TRAMP e2e pass has run.

**How.** Build the transient per selected formula from
`gc formula show <name> --json`: enum vars as choice infixes, boolean-default
vars as toggles, everything else as string options with the var's
description as prompt and default as placeholder; `required` and `pattern`
enforced client-side. All gc reads go through the existing single gc call
site (`gascity-reader`) against the view's `default-directory`; catalog and
recipe caches keyed by remote identity so local and remote cities never
cross-contaminate.

**How much.** One transient rework plus one new metadata/reader module and
tests. No new dependency outside gascity.el's current set (transient is
already a dependency). The plan decides module placement and the exact
cache shape; both are recorded there (REQ-012).

## User Stories

- **US-1 — As a mayor dispatching a build,** I press `S` on a convoy, pick
  `build-from-convoy` from the catalog list (reading its description), set
  `drain_policy` from a radio of the declared enum values, accept defaults
  for the rest, and preview the compiled graph — all without leaving the
  transient and without typing a single `--var` string.
- **US-2 — As a user who slings `implement` daily,** I press `M-p` in the
  `artifact_root` prompt and get the path I used last time, and my
  `context_path` history is distinct from my `summary_path` history —
  including across Emacs restarts.
- **US-3 — As a user on a remote city over TRAMP,** the formula catalog I
  browse and the recipe I preview come from the remote host's gc, and the
  sling lands in the remote store; nothing about the flow differs from the
  local city.
- **US-4 — As a user who forgot a required var,** I am told *which* vars are
  missing when I try to sling — before any gc call — instead of a raw gc
  error.
- **US-5 — As a curious user,** I can preview a formula's compiled steps
  (with my current var values substituted) from the transient without
  slinging anything.

## Technical Stories

- **TS-1 — As the gascity reader,** I am the only module that runs `gc`.
  Catalog and recipe reads go through `gascity-reader` (`process-file` /
  async) against the view's `default-directory`; a new module must not shell
  out on its own, and nothing here may spawn a synchronous gc from
  redisplay-time code.
- **TS-2 — As the transient,** I am generated per formula, not hand-written
  per formula. A formula with no `vars[]` renders no Variables section; a
  different selection rebuilds the section from that formula's metadata.
- **TS-3 — As a cache,** the formula catalog and per-formula compiled
  recipes are memoized keyed by city/host identity, so a local and a remote
  city never cross-contaminate and redisplay never re-reads them.
- **TS-4 — As a TRAMP city,** my reads run on the remote host through the
  existing remote path machinery (`tramp-remote-path`, Guix profile probing,
  `gascity-remote-buffer-name`); buffer names stay host-qualified and no
  eldoc or redisplay traffic rides the TRAMP channel because of the
  catalog cache.
- **TS-5 — As savehist,** per-variable histories are ordinary minibuffer
  history variables so they persist across sessions without a new
  persistence mechanism of their own.
- **TS-6 — As the ERT suite,** the mocked units stub the gc boundary with
  `cl-letf` on the reader functions (or the action verb under test), per the
  house test convention; nothing in the suite needs a live city except the
  skip-unless-guarded ones.

## Behavior Requirements

Requirement rows are the contract. `MUST` is binding; `SHOULD` is a default
the plan may override in writing.

### Formula discovery

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-001 | The sling transient MUST offer a formula picker listing every `gc formula catalog --json` entry, annotated with the formula's `description` (via `:annotation-function` or equivalent). | AC-1 |
| REQ-002 | An empty or unreadable formula catalog MUST produce a clear user-facing message, not a cryptic error or a blank picker. | AC-1 |
| REQ-003 | Catalog reads MUST go through the existing gc reader against the view's `default-directory` and MUST be cached per city/host identity. | AC-1, AC-7 |

### Generated variable UI

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-004 | The transient's Variables section MUST be generated from the selected formula's `vars[]` and rebuilt when a different formula is chosen; a formula with no vars shows no Variables section. | AC-2 |
| REQ-005 | `enum` vars MUST restrict input to the declared values (choice infix or equivalent completion) — illegal values are unrepresentable. | AC-3 |
| REQ-006 | Vars whose default is `true`/`false` MUST render as boolean toggles. | AC-3 |
| REQ-007 | All other vars MUST render as string options reading from the minibuffer with the var's `description` as prompt and its `default` as the initial value/placeholder. The infix description MUST carry the var's description and default so the transient is self-documenting. | AC-3 |
| REQ-008 | `required` vars MUST be visually marked and enforced before dispatch: attempting to sling with a missing required var MUST name the missing var(s) in the message and MUST NOT invoke gc. | AC-3, AC-6 |
| REQ-009 | `pattern` vars MUST be regex-validated client-side on entry, failing fast with a clear message instead of a post-hoc gc error. | AC-3 |

### History

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-010 | Each variable MUST have an independent minibuffer history keyed by `formula:var`, so the same variable name in different formulas keeps separate histories and `M-p` recalls previous values for *that* variable. | AC-4 |
| REQ-011 | Histories MUST persist across Emacs sessions (savehist-compatible ordinary history variables); no separate persistence mechanism is added. | AC-4 |

### Preview and sling shapes

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-012 | A preview suffix MUST re-run `gc formula show <name> --json` with the currently-set `--var` values and display the compiled recipe (steps, dependency edges, substituted titles) in the existing view-buffer affordance, without slinging. The existing `--dry-run` routing-plan preview MUST keep working. | AC-5 |
| REQ-013 | Both sling shapes MUST work: targetless (`gc sling <target> <formula> --formula --var …`) from the status dashboard, and targeted (`gc sling <target> <bead> --on <formula> --var …`, for convoy/drain formulas) pre-seeded from the bead or convoy at point. The transient detects whether the chosen formula references `{{convoy_id}}`/has drain steps and offers the appropriate shape. | AC-6 |
| REQ-014 | Catalog reads, recipe previews and the sling itself MUST be TRAMP-transparent: executed through the single gc call site against the view's `default-directory`, with caches keyed by remote identity and buffer names through `gascity-remote-buffer-name`. A local and a remote city MUST never cross-contaminate. | AC-7 |
| REQ-015 | The existing transient bindings from `gascity.el`, `gascity-rig.el`, `gascity-session.el` and `gascity-status.el` MUST be preserved, and the design conventions of `docs/DESIGN-write-actions.md` §5.2/§10 MUST hold (commits cite the section). | AC-6 |
| REQ-016 | Where a field is absent from the `gc formula show --json` payload, the UI MUST degrade gracefully (fall back to a plain string infix) rather than erroring. | AC-2, AC-3 |

### Verification

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-017 | ERT unit tests MUST cover the mocked units with the standard `cl-letf` reader stubbing, and `scripts/gate.sh` MUST pass (eldev compile `--warnings-as-errors` + eldev test). | AC-8, AC-7 |
| REQ-018 | The full flow MUST be verified against `/ssh:localhost:/home/roman/bright-lights` in a fresh Emacs inside tmux per AGENTS.md ("Remote test city & end-to-end testing"), and the result recorded in a `docs/qa/` dogfood report before the feature is called done. | AC-7 |

## Example Mapping

**Story:** a mayor presses `S` on a convoy and dispatches `build-from-requirements`
with two vars set, without typing a single `--var` string.

**Rule — the picker shows what exists.**
- *Example:* the picker lists `build-from-convoy`, `implement`,
  `build-from-requirements` with their one-line descriptions annotated; the
  mayor picks by reading, not memory.
- *Counter-example (a failure):* an empty picker with a "No match" minibuffer
  error because gc returned no formulas.

**Rule — declared shapes are honored; undeclared fields degrade.**
- *Example:* `drain_policy` is an enum var, so the infix is a radio of
  `separate`/`same-session`; typing `banana` is impossible by construction.
- *Example:* `artifact_root` is a plain var with a default, so the prompt
  starts pre-filled with the default and its description is visible.
- *Example:* a formula whose `vars[]` entry lacks `enum`, `pattern` and
  `required` renders as a plain string infix with no validation.
- *Counter-example (a failure):* the transient errors on a `vars[]` entry
  missing an optional metadata field.

**Rule — constraints bite before gc does.**
- *Example:* the mayor leaves a required `context_path` empty and presses the
  dispatch suffix; the echo area names `context_path` and no gc process runs.
- *Example:* a `pattern`-constrained var rejects a bad value at entry time
  with a message naming the pattern.
- *Counter-example (a failure):* dispatch proceeds, gc fails, and the user
  must diagnose a raw gc error to learn which var was wrong.

**Rule — history is per formula+variable.**
- *Example:* after slinging `implement` twice with different `artifact_root`
  values, `M-p` in the `artifact_root` prompt of a *later* `implement` sling
  cycles those two paths; the `build-from-requirements` sling's
  `artifact_root` history is unaffected.
- *Counter-example (a failure):* one shared history list across all vars, so
  `context_path` recalls old `summary_path` values.

**Rule — both shapes land where the point is, on the right host.**
- *Example:* from a convoy at point in the bright-lights remote dashboard,
  the `--on <formula>` sling reads the catalog from the remote host's gc and
  the convoy lands in the remote store.
- *Example:* from the local status dashboard, the targetless `--formula`
  shape slings into the local city.
- *Counter-example (a failure):* the local city's cached catalog (or buffer
  name) is served for the remote city.

**Questions raised by the mapping** are carried in *Open Questions* below.

## Acceptance Criteria

The criteria below restate the approved input draft's acceptance bullets
(`AC-*`) so each is mechanically checkable, and name the requirements that
carry them.

1. **AC-1 — Discovery works.** The formula picker lists every
   `gc formula catalog` entry with description annotation; an empty or broken
   catalog yields a clear message, not a cryptic error. *(REQ-001, REQ-002,
   REQ-003)*
2. **AC-2 — The Variables section is generated, not hand-written.** It is
   generated from the selected formula's `vars[]`, rebuilds when a different
   formula is chosen, is absent for a var-less formula, and degrades
   gracefully when a field is absent from the JSON. *(REQ-004, REQ-016)*
3. **AC-3 — Constraints are enforced client-side.** Enum vars restrict input
   to declared values; boolean-default vars toggle; required vars block
   dispatch naming the missing var(s); pattern violations are rejected at
   entry time. *(REQ-005, REQ-006, REQ-007, REQ-008, REQ-009)*
4. **AC-4 — History is per formula+variable and survives restart.** Each var
   has an independent history list keyed `formula:var`, savehist-persisted.
   *(REQ-010, REQ-011)*
5. **AC-5 — Preview shows what will be materialized.** The compiled recipe
   displays with current var values substituted; `--dry-run` routing-plan
   preview still works. *(REQ-012)*
6. **AC-6 — Both shapes work from the right surfaces.** `--on` shape from a
   bead/convoy at point; targetless `--formula` shape from the status
   dashboard; existing transient bindings and the
   DESIGN-write-actions.md §5.2/§10 conventions preserved. *(REQ-013,
   REQ-015)*
7. **AC-7 — TRAMP-transparent and proven remotely.** The full flow works
   against `/ssh:localhost:/home/roman/bright-lights` in a fresh Emacs inside
   tmux; ERT covers the mocked units with standard `cl-letf` reader stubbing.
   *(REQ-003, REQ-014, REQ-017, REQ-018)*
8. **AC-8 — The gate is green.** `scripts/gate.sh` passes. *(REQ-017)*

### Traceability

Every upstream identifier and its disposition in this artifact. `AC-*` are
the approved input draft's acceptance-criteria bullets; the behavioral
requirements above trace to them.

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |
| AC-6 | covered |
| AC-7 | covered |
| AC-8 | covered |

## Out Of Scope

- **No changes to the gc CLI, formula spec, or pack formulas.**
- **No formula authoring/editing UI** (writing or editing `.formula.toml`).
- **No orders UI** (`gc order` remains CLI-only).
- **No rework of the non-formula sling path** — text/bead slings keep
  today's behavior, including the existing flag infixes.
- **No var-value persistence beyond minibuffer history** — no per-city
  saved presets; a future enhancement.
- **No new dependency on packages outside gascity.el's current set**
  (transient is already a dependency; beads.el reuse is limited to existing
  `beads-meta`-style infrastructure).

## Open Questions

None of these blocks the plan; this workflow runs without a human in the
loop, so each is a decision the plan stage must record.

- **Exact JSON shapes.** `gc formula show <name> --json` is believed to
  return `vars[]` with `name`, `description`, `default`, `required`, `enum`,
  `pattern`, plus compiled `steps[]`/`deps[]` and drain/`{{convoy_id}}`
  detectability from the compiled steps/metadata (`gc.drain_formula`,
  `{{convoy_id}}` references). The plan must confirm the exact shapes against
  the live gc (`gc formula catalog --json`, `gc formula show implement
  --json`) and record them; REQ-016 governs absent fields.
- **Shape detection heuristic.** How exactly the transient decides between
  the targetless `--formula` and targeted `--on` shape (string scan of the
  compiled recipe for `{{convoy_id}}` vs. a metadata field) is the plan's
  call, subject to REQ-013.
- **Cache lifetime.** Whether the per-host catalog cache lives for the
  session or refreshes on `g`/explicit refresh is the plan's call, subject
  to REQ-003 and TS-3.
