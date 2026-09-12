---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-zan
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
    - path: beads/ga-wxt
      hash: bead:ga-wxt
      title: "WI-2: gascity-formula.el core — caches, catalog, enum mapping, shape detection, validation, history"
      ids:
        - REQ-002
        - REQ-003
        - REQ-005
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-013
        - REQ-014
        - REQ-016
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Approved implementation plan, Phase 2 (formula-metadata module) and decisions D1/D2/D3"
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements (the REQ ids this step covers)"
    - path: lisp/gascity-types.el
      hash: git:23462e5
      title: "Formula read command classes with NAME! bang executors (WI-1), the single gc call site this module reads through"
    - path: lisp/gascity-domain.el
      hash: git:23462e5
      title: "Typed formula payload classes (WI-1) the module decodes into"
    - path: lisp/gascity-formula.el
      hash: sha256:3bdbc4b9d4e2ea0933ad7c5a65c7f0d6af5d2263865ba66e21658acc645b3d0c
      title: "The new formula-metadata module as committed"
    - path: lisp/gascity.el
      hash: sha256:9ca64a2de25e3bfe8bc1df7fe819f42d08c4c11a72c3cf8ab95a52510ea9209c
      title: "Load-order insertion of gascity-formula between gascity-domain and command-status"
    - path: lisp/test/gascity-test.el
      hash: sha256:56454a6ca1362b767c40cb8bbafc308bffa25ff5164c96a0d3de9043eba886c7
      title: "ERT coverage for caches, enum mapping, shape detection, validation and history naming"
  coverage:
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-009
      status: covered
    - id: REQ-010
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
    - id: REQ-016
      status: covered
---

# Implementation Summary: WI-2 formula-metadata module (gascity-formula.el)

## Summary

Implemented work item WI-2 of the formula-sling-ui plan (source anchor
bead ga-wxt) in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-wxt`, committed as
`a9406233ce63fc75f288be702cba6c641acd81a1` ("feat(formula):
formula-metadata module for the sling UI") on the worktree's detached
HEAD.

The step creates `lisp/gascity-formula.el` — the formula-metadata module
the formula-aware sling transient (WI-3) will consume — and wires it
into the load order. It deliberately implements nothing gc-side: every
read goes through the single gc call site, and the pure helpers only
enforce, client-side, what gc's payloads declare. No UI arrives in this
step; the transient and recipe preview are WI-3.

## Intended Behavior

- **Caches (plan D3, REQ-003/REQ-014).** `gascity-formula-catalog-cache`
  (per city) and `gascity-formula-recipe-cache` (per (city, formula))
  are session-lifetime memos keyed by the city identity
  `(concat (file-remote-p dir) dir)` of the view's `default-directory`
  (the path `gascity-view-get-buffer-create` pins), so a local city and
  `/ssh:localhost:/home/roman/bright-lights` never share an entry.
  `gascity-formula-invalidate` clears only the current city's entries in
  both caches. Nothing on a redisplay path consults them — only
  user-initiated transient setup and previews.
- **Catalog access (REQ-001/002/003).** `gascity-formula-catalog` reads
  through `gascity-command-formula-catalog!` against
  `default-directory` and decodes the envelope's `formulas` into typed
  `gascity-formula-catalog-entry`s; an empty or unreadable catalog
  signals `user-error` with a clear message (REQ-002), never a cryptic
  error or a blank picker. `gascity-formula-recipe` /
  `gascity-formula-recipe-cached` read `gc formula show <name> --json`
  into a `gascity-formula` (defaults only — the cached read applies no
  `--var` substitutions; the preview re-runs the uncached read with
  values when it wants gc to substitute server-side).
- **Enum mapping (plan D1, REQ-005).** `gascity-formula--enum-choices`
  prefers an explicit `vars[].enum` when gc ever ships it; otherwise a
  small built-in mapping (`drain_policy` → `allowed_drain_policies`,
  `interaction_mode` → `interaction_modes`, `review_mode` →
  `review_modes`) consults the recipe's `metadata.gc.methodology`. A var
  with neither degrades to plain string input (REQ-016).
- **Shape detection (plan D2, REQ-013 detection half).**
  `gascity-formula--needs-convoy` applies gc's own documented sling rule
  verbatim: the targeted `--on` shape is required iff any `steps[]`
  entry has step metadata `gc.kind` = "drain", or any step's
  title/description/metadata values contain the literal `{{convoy_id}}`
  (case-sensitive, recursive over nested metadata). A plain formula
  gets the targetless `--formula` shape.
- **Validation (REQ-008/009).** `gascity-formula--validate-values`
  checks `required` and `pattern` over a var→value alist before any gc
  invocation: missing required vars are named together in one
  `user-error`; a pattern failure names the var and the pattern; a
  pattern that does not compile as an Emacs regexp degrades to no
  validation (REQ-016). A blank value is the required check's business,
  not the pattern's.
- **History registry (REQ-010/011).** `gascity-formula--history-var`
  returns ordinary minibuffer history symbols named
  `gascity-formula-history-<formula>-<var>` (non-word characters
  sanitized to hyphens), distinct per `(formula, var)`. Because WI-3's
  infixes will use them as `minibuffer-history-variable`, savehist
  tracks them automatically — no separate persistence mechanism.

## Changed Files

All changes are committed in the item worktree (commit `a940623`,
detached HEAD of `/home/roman/workspace/gascity.el/worktrees/ga-wxt`):

| File | Change |
| --- | --- |
| `lisp/gascity-formula.el` | New module: per-city caches, catalog/recipe reads, enum mapping, convoy shape detection, client-side validation, history registry. |
| `lisp/gascity.el` | `require 'gascity-formula` inserted between `gascity-domain` and `command-status` (dependency order); module commentary updated. |
| `lisp/test/gascity-test.el` | New ERT section (see Verification). |

`Eldev` needed no change: the file list still resolves through the main
file's requires.

Coverage matrix:

| ID | Status |
| --- | --- |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-005 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-013 | covered |
| REQ-014 | covered |
| REQ-016 | covered |

REQ-005's enforcement half (the choice infix itself) and REQ-008's
visual marking live in WI-3's transient, which consumes
`gascity-formula--enum-choices` / `gascity-formula--validate-values`;
this step delivers and pins the resolution and check logic they build
on. REQ-013 here is the detection half only — the dispatch half is
WI-3/WI-4.

## Verification

1. First verification command — the byte-compile gate over the whole
   package, never a subset:
   `eldev compile --warnings-as-errors` (run from
   `/home/roman/workspace/gascity.el/worktrees/ga-wxt`) — **pass**,
   zero warnings (the new file is compiled; the load-order edit in
   `lisp/gascity.el` recompiles clean).
2. ERT (mocked, house convention — `cl-letf` stubs on the bang
   executors, no live city needed): `eldev test gascity-test-formula`
   — **pass**, 8/8:
   - `gascity-test-formula-catalog-cached-memoizes-and-isolates-cities`
     — a local temp dir and a stubbed `/ssh:localhost:` dir read
     independently (2 gc calls), warm re-reads add none, and
     `gascity-formula-invalidate` in the local city clears only its own
     entry while the remote entry stays warm;
   - `gascity-test-formula-recipe-cached-and-invalidate` — recipe
     entries keyed `(city . formula)` (a second name re-reads;
     invalidate re-reads), the cached read substituting nothing;
   - `gascity-test-formula-catalog-empty-and-broken` — an empty
     payload and a `gascity-command-error` both degrade to
     `user-error` with a clear message;
   - `gascity-test-formula-enum-choices` — `drain_policy` maps to
     `allowed_drain_policies`, an unknown var falls back to nil,
     explicit `vars[].enum` wins, and a metadata-less formula has no
     choices;
   - `gascity-test-formula-needs-convoy` — drain-step metadata hit,
     `{{convoy_id}}` scan hit (description and nested metadata), plain
     formula and stepless formula miss;
   - `gascity-test-formula-validate-values` — missing required vars
     are named together, a pattern mismatch names var and pattern, a
     non-compiling pattern and absent fields degrade silently, and a
     varless formula validates anything;
   - `gascity-test-formula-history-var` — distinct symbols per
     `(formula, var)`, non-word characters sanitized to hyphens.
   During this work the fixtures were corrected against a real
   `gc formula show implement --json`: step metadata is a **flat**
   object (`"gc.kind": "workflow"`), which the detection helper reads
   with the dotted-symbol key `gc.kind` — the tests pin that shape.
3. Final proof command — the standard quality gate:
   `scripts/gate.sh` — **pass** ("gate: PASS (compile clean + tests
   green)"), which re-runs `eldev compile --warnings-as-errors` plus the
   whole ERT suite: 259 tests, 259 results as expected.

## Remaining Risks

- No shipped gc formula declares `vars[].enum` today (plan D1), so the
  "explicit enum wins" branch is exercised only against stub payloads;
  the metadata-methodology mapping is the path live formulas take, and
  its choice lists come from `gc formula show` payloads observed on the
  real city.
- Cache freshness is session-lifetime by design (D3): a formula edited
  on disk mid-session is invisible until `gascity-formula-invalidate`
  (WI-3's refresh binding). Acceptable per plan; worth remembering when
  dogfooding.
- The transient, picker and preview (WI-3) are unimplemented — this
  module's consumers do not exist yet, so its public surface is
  exercised only by its own unit tests until WI-3 lands. The end-to-end
  sling dispatch against the live TRAMP city (`bright-lights`) is the
  Phase 4 tmux-Emacs acceptance pass, not this step.
