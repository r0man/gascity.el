---
schema: gc.build.plan.v1
workflow:
  id: ga-c0e
  formula: build-from-requirements
methodology:
  pack: gascity
  name: planning-base
producer:
  formula: build-from-plan-base
  stage: plan
  attempt: 1
status: draft
trace:
  upstream:
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved formula-sling-ui requirements this plan implements"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
        - AC-6
        - AC-7
        - AC-8
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
        - REQ-016
        - REQ-017
        - REQ-018
    - path: plans/formula-sling-ui/build/requirements-input.md
      hash: sha256:516aefdc11c39a67031000eb8f7f49ea6b90ebc5005e9f5c2c53588180c7dfaf
      title: "The approved requirements draft the requirements artifact restructured (upstream hash preserved)"
    - path: lisp/gascity-action.el
      hash: git:16c2d7b8a77baea264c762f93caef86d26591941
      title: "The current sling transient (gascity-sling-dispatch, gascity-sling--read-vars, gascity-sling--run) this plan reworks"
    - path: lisp/gascity-types.el
      hash: git:d4bd21c84ae09e55e7d9c7a2bf324c50b65b1c76
      title: "gascity-command-sling command class this plan extends with an --on slot"
    - path: docs/DESIGN-write-actions.md
      hash: git:cdae3a365a98f6ebff1ff025be2ff5e39a342317
      title: "Binding design this plan must hold (§5.2 sling, §10 key conventions)"
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
    - id: REQ-016
      status: covered
    - id: REQ-017
      status: covered
    - id: REQ-018
      status: covered
---

# Implementation Plan: Formula-aware sling UI for gascity.el

## Summary

Build a formula-aware sling transient for gascity.el that replaces the
bare `--formula` toggle plus raw `key=value` read loop with: a formula
picker generated from `gc formula catalog --json` (description-annotated),
per-variable infixes generated from the selected formula's `vars[]`
metadata, per-`(formula,var)` minibuffer history persisted by savehist,
client-side enforcement of `required`/`pattern`/enum constraints, a
compiled-recipe preview, and both sling shapes (`--formula` targetless
and `--on <formula>` targeted at a bead/convoy at point). All gc reads go
through the existing single gc call site (`gascity-reader`) against the
view's `default-directory`; the catalog and per-formula recipes are
memoized per city identity so local and TRAMP cities never
cross-contaminate.

The plan records the exact gc payload shapes observed against the live
local city (`/home/roman/emacs-city`, 2026-09-10) and resolves the three
open questions from the requirements (payload shapes, shape-detection
heuristic, cache lifetime) below.

**Interaction mode.** This workflow runs autonomously; every decision
below is recorded rather than asked. No unresolved ambiguity remains —
the one item that cannot be confirmed without a live dispatch (`--var`
combined with `--on`) is listed as a Verification step and is exercised
in the tmux-Emacs TRAMP pass before the feature is called done.

## Current System

- `gascity-sling-dispatch` (`lisp/gascity-action.el`, §5.2) is a static
  transient: `--formula` is a boolean toggle, vars are collected by
  `gascity-sling--read-vars` as repeated raw `key=value` `read-string`
  prompts, and the only preview is `gascity-sling--show-plan` over gc's
  `--dry-run` routing plan. `gascity-sling--run` reads the bead/text
  (seeded from `gascity-bead-at-point`) and the target, builds a
  `gascity-command-sling`, and acts via `gascity-command-act` followed by
  `gascity--refresh-current-view`.
- `gascity-command-sling` (`lisp/gascity-types.el`) has slots for
  `target`, `arg`, `formula`, `nudge`, `no-convoy`, `reassign`, `merge`,
  `title`, `var`, `dry-run`. It has **no `--on` slot**, so the targeted
  convoy-first shape (`gc sling <target> <bead> --on <formula>`) cannot
  be issued today.
- `gc formula` is never invoked by gascity.el: there is no catalog
  reader, no recipe reader, no cache, and no domain decoding for formula
  payloads. Load order in `lisp/gascity.el` is
  custom → error → remote → reader → command → context → types → domain →
  command-status → terminal → section → tabulated → status → action → rig
  → session; a new module slots between `domain` and `command-status`.
- Tests stub the gc boundary with `cl-letf` on `gascity-reader-read` or
  on the bang executor under test; the whole suite lives in
  `lisp/test/gascity-test.el`, gated by `scripts/gate.sh`.
- gc facts confirmed live (see *Payload shapes* in Proposed
  Implementation): `gc formula catalog --json` returns 13 formulas with
  `name`+`description` only; `gc formula show <name> --json` returns the
  compiled recipe with `vars[]`, `steps[]`, `deps[]` and `metadata`.

## Proposed Implementation

### D1 — Recorded payload shapes (Open Question: exact JSON shapes)

Confirmed against `gc formula catalog --json` and `gc formula show
implement --json` / `gc formula show build-from-convoy --json` on
2026-09-10:

- **Catalog** (`gc formula catalog --json`):
  `{schema_version, ok, formulas: [{name, description}], summary: {count}}`.
  No per-formula vars in the catalog; descriptions are one-liners
  suitable for `:annotation-function`.
- **Recipe** (`gc formula show <name> --json`):
  `{schema_version, ok, city_path, name, description, metadata,
  search_paths, vars: [...], steps: [{id, title, description, type,
  priority?, is_root?, metadata}], deps: [{step_id, depends_on_id,
  type}]}`.
- **`vars[]` entries observed in the wild** carry `name`, `description`,
  `default` (always a string), and optionally `required` (boolean).
  **No shipped formula declares `enum` or `pattern` on a var** (grep over
  the gc pack formulas confirms). Enum-like value sets live in formula
  metadata instead: `metadata.gc.methodology.{allowed_drain_policies,
  interaction_modes, review_modes}` (e.g. `build-from-convoy` declares
  `allowed_drain_policies = ["separate", "same-session"]` for its
  `drain_policy` var).
- Per REQ-016 the UI therefore honors `vars[].enum` and `vars[].pattern`
  when present (contractually implemented and unit-tested with stub
  payloads), and **degrades gracefully to plain string input** when a
  field is absent. For enum-like behavior today, the UI consults a small
  built-in mapping of var name → methodology key
  (`drain_policy` → `allowed_drain_policies`, `interaction_mode` →
  `interaction_modes`, `review_mode` → `review_modes`); a var that maps
  to a declared methodology list renders as a choice infix, everything
  else as a string infix. `vars[].enum`, when gc ever ships it, wins
  over the metadata mapping.

### D2 — Shape detection heuristic (Open Question: `--formula` vs `--on`)

gc's own `sling --help` states the rule: *"A v2 formula that references
`{{convoy_id}}` or contains a drain step requires a target convoy: route
it with `gc sling <target> <bead> --on <formula>`"*. The transient
applies exactly that rule to the compiled recipe: a formula **requires
the targeted `--on` shape** iff any `steps[]` entry has `metadata
["gc.kind"] == "drain"` or any step's `title`/`description`/metadata
values contain the literal `{{convoy_id}}` (case-sensitive string scan).
Otherwise the targetless `--formula` shape is offered. If a
convoy-requiring formula is picked with no bead/convoy at point, the
transient says so (`user-error` naming the condition) instead of
dispatching a sling gc will reject.

### D3 — Cache lifetime (Open Question: cache lifetime)

- The catalog cache and the per-formula recipe cache live for the Emacs
  session, keyed by city identity `(concat (file-remote-p dir) dir)` for
  the view's `default-directory` (the path `gascity-view-get-buffer-create`
  pins). A local city and `/ssh:localhost:/home/roman/bright-lights`
  therefore never share entries.
- Recipe cache entries are keyed `(city-key . formula-name)`.
- Invalidation is explicit: re-picking "refresh catalog" in the picker
  and a new public `gascity-formula-invalidate` (called by an explicit
  refresh binding) clear the per-city entries. Nothing re-reads gc from
  redisplay-time code; caches are only consulted from user-initiated
  transient setup and previews (TS-3, TS-4).

### Module layout

- **`lisp/gascity-types.el`** — read command classes (house convention:
  read classes live here):
  - `gascity-command-formula-catalog` (`formula catalog`, JSON read, no
    filters);
  - `gascity-command-formula-show` (`formula show`, positional formula
    name). The `gascity-defcommand` macro emits the
    `gascity-command-formula-catalog!` / `-show!` sync bang executors the
    rest of the code uses.
  - `gascity-command-sling` gains an `on` slot (`:long-option "on"`,
    `:option-type :string`); `gascity-sling--parse-transient-args`
    learns `"--on=..."`.
- **`lisp/gascity-domain.el`** — EIEIO payload classes decoded once via
  `beads-from-json` (remember: gc JSON decodes `false`/`null` to nil, so
  optional slots are `(or null ...)`):
  - `gascity-formula-catalog-entry`: `name`, `description`;
  - `gascity-formula-var`: `name`, `description`, `default`, `required`,
    `enum` (list), `pattern`;
  - `gascity-formula`: `name`, `description`, `metadata`, `vars` (list of
    `gascity-formula-var`), `steps`, `deps`.
- **`lisp/gascity-formula.el`** (new; loaded after `gascity-domain`,
  before `command-status`; load order and Eldev file updated in
  `lisp/gascity.el`):
  - caches (`gascity-formula-catalog-cached`, `gascity-formula-recipe-cached`,
    `-invalidate`) per D3;
  - catalog access `gascity-formula-catalog` (read-or-error with the
    REQ-002 clear empty/broken-catalog message);
  - enum mapping (`gascity-formula--enum-choices` per D1);
  - shape detection (`gascity-formula--needs-convoy` per D2);
  - validation (`gascity-formula--validate-values`: missing-required and
    pattern checks over a var→value alist, error naming the vars, no gc
    call);
  - history registry (`gascity-formula--history-var` producing ordinary
    minibuffer history variables named
    `gascity-formula-history-<formula>-<var>` — standard `…-history`
    naming so savehist tracks them automatically via
    `savehist-minibuffer-history-variables` (savehist.el adds every used
    `minibuffer-history-variable`); names sanitized to word characters);
  - the transient (`gascity-sling-formula-dispatch`, below);
  - the recipe preview renderer.
- **`lisp/gascity-action.el`** — `gascity-sling-dispatch` keeps its
  bindings and non-formula flag infixes; the `-f` toggle becomes the
  entry into the formula flow: selecting it pops the catalog picker, and
  picking a formula rebuilds the transient's Variables section from that
  formula's `vars[]`. `gascity-sling--read-vars` is deleted; var values
  now flow through generated infixes into the same `--var k=v`
  accumulation `gascity-sling--parse-transient-args` already collects.
- **View files** (`gascity.el`, `gascity-rig.el`, `gascity-session.el`,
  `gascity-status.el`): bindings unchanged (REQ-015).

### Transient construction (REQ-004 … REQ-009, TS-2)

- The transient keeps a scope plist `(formula target arg on-bead)` set at
  entry: the bead/convoy at point seeds `arg`, `gascity-action--read-session`
  seeds `target`.
- Formula picker: a suffix reading the cached catalog via completion with
  `:annotation-function` supplying each formula's `description`; on
  choice the scope's `formula` is replaced and the prefix re-runs
  `transient-setup` so the Variables section is rebuilt from that
  formula's `vars[]`. A formula with no vars renders no Variables
  section (REQ-004).
- Per var, one generated infix:
  - enum (per D1): a fixed-`choices` option — illegal values are
    unrepresentable;
  - default `"true"`/`"false"`: a boolean toggle infix whose value
    serializes to `name=true`/`name=false` (REQ-006);
  - otherwise a string option: minibuffer read with the var's
    `description` as prompt, `default` as initial value, and an infix
    description carrying the var description and default (REQ-007);
    missing `description`/`default` degrade to a generic prompt and empty
    initial (REQ-016);
  - `required` vars are marked "(required)" in the infix description;
  - `pattern` vars are validated in the reader with `string-match`,
    failing with a message naming the var and the pattern; a pattern
    that does not compile as an Emacs regexp degrades to no validation
    (REQ-009, REQ-016).
- Dispatch suffix: run `gascity-formula--validate-values` first — a
  missing required var produces `user-error "Missing required formula
  vars: …"` and **no gc invocation** (REQ-008). Then build the shape per
  D2: targetless → `gascity-command-sling :formula t :arg <formula>`;
  targeted → `:arg <bead-id> :on <formula>`; either carries the collected
  `:var` list, and everything refreshes the originating view through the
  existing `gascity-command-act` path.
- Preview suffixes (REQ-012): a recipe preview renders the cached recipe
  — steps with ids/titles, dependency edges from `deps[]`, `{{var}}`
  occurrences substituted with current infix values (client-side
  approximation of gc's server-side substitution) — into a host-qualified
  read-only view buffer via `gascity-view-get-buffer-create`; the
  existing `--dry-run` routing-plan preview suffix is untouched.

### TRAMP behavior (REQ-014, TS-4)

Every read is a bang executor over `gascity-reader-read` bound to the
transient's `default-directory` (captured when the transient opens, from
the originating view buffer `gascity-view-get-buffer-create` pinned);
caches key by that directory's remote-qualified identity (D3); preview
buffers go through `gascity-view-get-buffer-create` (host-qualified
names); no new TRAMP traffic exists outside user-initiated actions, so
no eldoc/redisplay channel impact.

### Phases

1. **Plumbing** — `gascity-command-sling :on` slot + parser support;
   `gascity-command-formula-catalog`/`-show` read classes; domain
   classes for catalog entry/var/recipe; unit tests for decoding and
   command-line construction (both shapes, `--var` repetition, `--on`).
2. **`gascity-formula.el` core** — caches, catalog access with REQ-002
   messaging, enum mapping, shape detection, validation, history
   registry; unit tests with fixture payloads (enum/bool/string/required/
   pattern/absent-field vars) stubbing the bang executors with
   `cl-letf`.
3. **Transient + preview** — dynamic Children generation (pure function,
   unit-tested), picker with annotation, recipe preview renderer, wiring
   into `gascity-sling-dispatch` with bindings preserved.
4. **Gate + e2e** — `scripts/gate.sh` green (REQ-017); the AGENTS.md
   tmux-Emacs TRAMP acceptance pass against
   `/ssh:localhost:/home/roman/bright-lights`: open the remote dashboard,
   press `S`, pick a formula from the remote catalog, set vars through
   the generated infixes, preview the recipe, dispatch the real sling,
   confirm it lands in the remote store, confirm `M-p` history and
   savehist persistence, and record the run in a `docs/qa/` report
   (REQ-018).

## Non-Goals

From the requirements' out-of-scope list, unchanged:

- No changes to the gc CLI, formula spec, or pack formulas (read only).
- No formula authoring/editing UI.
- No orders UI (`gc order` stays CLI-only).
- No rework of the non-formula sling path: text/bead slings and the
  existing flag infixes keep today's behavior.
- No var-value persistence beyond minibuffer history (no per-city
  presets).
- No new dependency outside gascity.el's current set; beads.el's
  `beads-meta` machinery is a reference pattern only.

## Verification

1. **ERT (mocked, house convention)** — in `lisp/test/gascity-test.el`:
   - payload decoding: catalog entry, var with/without `required`/`enum`
     /`pattern`/`default` (absent-field degradation), recipe steps/deps;
   - command construction: `gascity-command-sling` with `:on` and
     multiple `:var`s produces the expected CLI (`--on <formula>`
     `--var k=v` repetition, `--formula` shape); parse of `--on=…`;
   - caches: two keys (local dir + stubbed remote dir) stay isolated;
     invalidate clears only its own city;
   - enum choices: `drain_policy` maps to `allowed_drain_policies`;
     unknown var falls back to string; explicit `vars[].enum` wins;
   - shape detection: drain-step metadata and `{{convoy_id}}` scan hit;
     plain formula does not;
   - validation: missing required names the vars; bad pattern rejected
     with the pattern in the message; absent fields degrade silently;
   - transient children: generated infix set matches `vars[]` (count,
     kinds, required marks); no vars → no Variables section;
   - history naming: distinct symbols per `formula:var`.
   All gc-boundary stubs via `cl-letf` on
   `gascity-command-formula-catalog!`/`-show!` (or `gascity-reader-read`);
   no live city needed.
2. **Gate** — `scripts/gate.sh` (eldev compile `--warnings-as-errors`
   over the whole package + eldev test) passes with zero warnings; whole
   package always compiled, never a subset.
3. **Acceptance gate (interactive, not ERT)** — fresh Emacs inside tmux
   attached to `/ssh:localhost:/home/roman/bright-lights`, exercising the
   real flow end-to-end per AGENTS.md ("Remote test city & end-to-end
   testing"), including the `--var` + `--on` combination check from D2
   and savehist persistence across an Emacs restart; result recorded in
   a `docs/qa/` dogfood report before the feature is called done.

### Coverage

| ID | Status |
| --- | --- |
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |
| AC-6 | covered |
| AC-7 | covered |
| AC-8 | covered |
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
| REQ-016 | covered |
| REQ-017 | covered |
| REQ-018 | covered |