# Cross-repo ownership — gascity.el side (WI-SF-19 / REQ-SF-100)

This is the gascity.el half of the cross-repo ownership record.  It is the
before/after hotspot list the work item asks for, and it mirrors the beads.el
hand-off contract in `beads.el`'s `docs/cross-repo-ownership.md` (which owns the
machine-checked seam list and the guard test).  The dependency stays one-way:
gascity.el consumes beads.el seams; beads.el never requires gascity.el.

## The rule

beads.el owns the generic, `bd`-driven machinery and its typed domain objects
(formula var reading/validation, enum resolution, launch porcelain,
terminal/tmux, faces, tabulated/section rendering).  gascity.el owns only
`gc`-specific enrichment (city/rig scoping, rosters, live sessions/pools, the
run view, `gc formula catalog`).  `gc` reporting a different JSON shape — the
recipe's raw `steps`/`deps` for the preview, and `false`/`null` decoding to nil
— is the only thing gascity keeps locally.

## Hotspot inventory (before → after)

| # | Hotspot in gascity.el | Duplicated beads-native logic | beads.el seam | After |
|---|---|---|---|---|
| 1 | `gascity-formula--enum-metadata-keys`, `gascity-formula--methodology`, `gascity-formula--enum-choices` (`gascity-formula.el`) | Resolve a var's allowed values: explicit `enum`, else the name → `metadata.gc.methodology` key mapping | `beads-formula-var-choices`, `beads-formula-methodology`, `beads-formula-enum-metadata-keys` | deleted the mapping table and fallback; `gascity-formula--enum-choices` is a one-line call of the beads generic; `gascity-formula` specializes `beads-formula-methodology` so the generic dispatches on the gc recipe |
| 2 | `gascity-formula--validate-values`, `gascity-sling--missing-required-vars` | Client-side required/pattern validation of formula var values before launch | `beads-formula-validate-vars`, `beads-formula-missing-required-vars` | both are thin callers of the beads functions (the nil-recipe guard stays local); the footer warning and launch refusal share the beads implementation |
| 3 | `gascity-sling-formula--var-class` type/name heuristic | Map a var's declared metadata (type, enum, name convention) to a reader kind | `beads-formula-var-reader`, `beads-formula-var-kind` | `var-class` switches on `beads-formula-var-kind` and keeps only the kind → transient-infix-class mapping; the sole local rule is the `true`/`false` default toggle, which the beads kind inference is default-agnostic about |
| 4 | `gascity-formula-var` class (`gascity-domain.el`) | Decode `gc formula show --json` vars into typed objects | `beads-formula-var` | `gascity-formula-var` is a no-field subclass of `beads-formula-var`; the `gascity-formula-var-*` accessors are thin `oref` aliases.  A `beads-from-json` specialization restores gascity's nil-boolean handling for the inherited `boolean` `required` slot |
| 5 | `gascity-formula-catalog`, `-list`, `-recipe` + caches; `gascity-formula` recipe class | Read a formula catalog/recipe and memoize it | `beads-command-formula-show/-list`; **no cache seam** | the city-scoped cache, the `gc formula catalog` read and the raw-`steps`/`deps` recipe class stay in gascity (gc-specific) |
| 6 | Terminal/tmux attach and scrolling | tmux probes, attach argv, status mirror, mouse, scroll | `beads-terminal-*` | already moved in PR #67; **no action** |
| 7 | `gascity-sling-formula--var-infixes`, deterministic var-key assignment, recipe preview | Generate per-var transient infixes and a deterministic key layout | `beads-sling` adaptive transient (beads.el) | **stays in gascity**: the `gc sling` transient is gascity's own menu; beads.el's delegated `S` opens beads' own transient and reaches gascity only through the `gc` backend |
| 8 | `gascity-beads-sling.el` (new) | Reimplement the Who picker, dispatch, validation, menu or refresh plumbing | `beads-sling-target-functions`, `beads-sling-backend-register`, `beads-sling-validators`, `beads-menu-providers`, `beads-action-providers`, `beads-after-action-functions` | registers the six seams once; no bead list/detail rendering, no second sling parser and no new CLI behaviour |

Hotspots 1–4 are the dedup this change activates; 5 is a deliberate partial
(command classes only); 6 was already done; 7 keeps the `gc sling` transient in
gascity while delegating the bead-view entry point; 8 is the new downstream
registration module.

## What gascity.el keeps (intentional, not duplication)

- `gascity-formula-catalog` / `gascity-formula-list` / `gascity-formula-recipe`
  and their per-city caches: `gc formula catalog` and the city-scoped keying
  have no beads equivalent.
- `gascity-formula` (recipe class) and `gascity-formula-catalog-entry`:
  gascity's decode keeps the recipe's raw `steps`/`deps` as alists for the
  preview, which the typed `beads-formula` cannot express without changing the
  decode.  It specializes `beads-formula-methodology` instead of subclassing.
- The `true`/`false` default → toggle rule in `gascity-sling-formula--var-class`:
  every shipped gc boolean var declares only `default = "false"`, never a
  `type`; the beads kind inference is default-agnostic, so the toggle is the
  sling's own presentation rule.
- gascity's nil-wins boolean decoding (`false`/`null` → nil): preserved by the
  `beads-from-json` specialization on `gascity-formula-var`.

## What `gascity-beads-sling` registers

`lisp/gascity-beads-sling.el` is the whole of the downstream registration.  It
is loaded by `lisp/gascity.el` after `gascity-action`, registers from one
idempotent function (`gascity-beads-sling-register`) and consumes exactly the
six seams beads.el publishes:

| Seam | What gascity contributes |
|---|---|
| `beads-sling-target-functions` | `gascity-beads-sling-targets`: one `beads-sling-target` per cached `gc agent list` row, `:backend "gc"`, `:kind agent`, `:scope` the rig name (nil for a city-level agent), `:metadata` carrying `:rig :city :qualified-name :source`.  Reads `gascity-store-get '("agent" "list")` with an explicit city directory; a cold store or unknown city returns nil (no spawn, no block). |
| `beads-sling-backend-register` | the named `"gc"` backend, `gascity-beads-sling--dispatch (target bead prompt context)`.  It builds a `gascity-command-sling` (never a hand-written argv), validates a missing work/target or required var with `user-error`, drops the prompt (no `gc sling` prompt flag) and launches asynchronously through `gascity-command-act-async`. |
| `beads-sling-validators` | one advisory function returning up to four cached-data warnings, joined with `"; "`: the cross-store route, the formulas-v2 city-scoped/pool target trap, a missing target (every shape, formula included) and missing required vars.  None refuses a launch. |
| `beads-menu-providers` | one `[City]` group (`E` cockpit, `J` rig dashboard at point, `K` rig dashboard, `A` agents, `Q` the gascity sling menu) spliced into `beads-dispatch`. |
| `beads-action-providers` | one additive `V` cockpit entry on the `:list` and `:show` action bars; beads.el keeps `S` and every other key. |
| `beads-after-action-functions` | `gascity-beads-sling--after-action`: after a beads mutation, one `gascity-store-invalidate` for the city's aggregate kinds (`status run session convoy agent`) under the cache-only city root, and one for the `bd` kind under each affected issue's memoized rig root, both with `:refetch t`.  Unresolved roots contribute nothing; no allow-list, no beads read, no timer. |

Target names are gc's qualified names: `rig/agent` for a rig agent
(`gascity.el/gc.implementation-worker`) and the bare name for a city-level one
(`mayor`).  The backend resolves the Who target from the context `:target` when
beads.el supplied one; otherwise it derives exactly as `gascity-sling-dispatch`
does (rig default → per-(city, formula) memory → implementation-worker
convention) over the cached roster.  Every shape requires a non-blank target —
`gc` refuses `--formula` without one — so a blank answer is a `user-error`
before any process starts, never an invented or empty target.

The argv is the existing builder's output, pinned by the context `:shape`:

| Shape | argv |
|---|---|
| `plain` | `("sling" TARGET BEAD)` |
| `on` | `("sling" TARGET BEAD "--on" FORMULA "--var" k=v ...)` |
| `formula` | `("sling" TARGET FORMULA "--formula" "--var" k=v ...)`; never the targetless `("sling" "--formula" ...)` shape |

Var order is the context's resolved `:values` order, and only vars the user or
template actually set are emitted.  `--on` versus `--formula` comes from
`:shape`; the builder never consults `gascity-formula--needs-convoy` (F5).
`gc sling` has no prompt flag, so a non-blank prompt is dropped with a message
rather than refused or put in the argv.

None of this duplicates beads.el rendering: beads.el still owns the bead
list/detail UI, the `S` transient and the dispatch menu; gascity supplies only
the `gc` target provider, backend, advisories, one menu group and one refresh
hook.  The dependency stays one-way — beads.el never requires gascity.el.

**Cold start (F4):** the target provider can name a city only from
`gascity-context-city`, a known city root whose memoized rigs contain the beads
buffer's rig repository, or a city a previous dispatch remembered.  A fresh
Emacs with no gascity view open and no override therefore shows only beads.el's
local targets in the Who picker until a city becomes known.  Nothing on that
path spawns `gc`, walks a remote file system or blocks.

## Verification

| Gate | Command |
|---|---|
| Byte-compile (warnings as errors) | `make` (via `scripts/gate.sh`) |
| Unit suite (incl. `gascity-test-formula-beads-seams`) | `make check` (via `scripts/gate.sh`) |
| CI lint | `scripts/lint.sh` |

`gascity-test-formula-beads-seams` asserts the seam consumption directly: the
typed var is a `beads-formula-var` subclass, and the enum, validation, missing
and reader-kind helpers call the beads functions rather than a local
implementation.  `gascity-beads-sling-test` covers the registration module:
the warm/cold target provider, the exact argv per shape, the advisory
validators, registration idempotence and the no-spawn guarantee.

## Further reading

- `beads.el` `docs/cross-repo-ownership.md` — the authoritative seam list and
  its guard test.
- `plans/beads-standalone-formulas/requirements.md` — REQ-SF-100;
  `implementation-plan.md` — WI-SF-19.
