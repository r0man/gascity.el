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
| 7 | `gascity-sling-formula--var-infixes`, deterministic var-key assignment, recipe preview | Generate per-var transient infixes and a deterministic key layout | none yet (candidate for `beads-sling.el` under WI-SF-03/WI-SF-08) | **deferred**: the sling transient still lives in gascity.el until the beads sling stage lands |

Hotspots 1–4 are the dedup this change activates; 5 is a deliberate partial
(command classes only); 6 was already done; 7 is deferred to the WI that lands
the beads.el sling stage.

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

## Verification

| Gate | Command |
|---|---|
| Byte-compile (warnings as errors) | `scripts/gate.sh` (`eldev compile --warnings-as-errors`) |
| Unit suite (incl. `gascity-test-formula-beads-seams`) | `eldev test` |
| CI lint | `scripts/lint.sh` |

`gascity-test-formula-beads-seams` asserts the seam consumption directly: the
typed var is a `beads-formula-var` subclass, and the enum, validation, missing
and reader-kind helpers call the beads functions rather than a local
implementation.

## Further reading

- `beads.el` `docs/cross-repo-ownership.md` — the authoritative seam list and
  its guard test.
- `plans/beads-standalone-formulas/requirements.md` — REQ-SF-100;
  `implementation-plan.md` — WI-SF-19.
