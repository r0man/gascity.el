---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-a8076
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
    - path: beads/ga-hbeuz
      hash: bead:ga-hbeuz
      title: "B6 source anchor: beads-sling ERT suite and non-blocking guard"
      ids:
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-007
        - REQ-008
    - path: plans/beads-sling-integration/implementation-plan.md
      hash: sha256:9172aff2d78b0a6522bbeb911fc1edd6a4442ba72ad17b67399387dd3253d313
      title: "Approved plan §B6 (tests) and the verification table"
    - path: plans/beads-sling-integration/requirements.md
      hash: sha256:2046b64245d0f4a45b7252f5ca4ff46086e0ee4fa2cef53c4482d6906c12d09f
      title: "AC-4..AC-8, AC-10, AC-12, AC-13"
    - path: plans/beads-sling-integration/decomposition.md
      hash: sha256:e7a28e51ccf05f5d73740b59c94ee212c3882b2b095ea294e9716fd8e3dec6e4
      title: "Work item B6 boundary and its B2..B5 dependencies"
    - path: lisp/test/gascity-beads-sling-test.el
      hash: sha256:ba9ba6a73fa582565d4760829189cb39a522f723d90c5e5ba804382f28229346
      title: "Changed: the downstream seam suite (B5a/B5b tests kept, B6 coverage added)"
  coverage:
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-007
      status: covered
    - id: REQ-008
      status: covered
---

# Implementation Summary — B6: beads-sling ERT suite and non-blocking guard (ga-hbeuz)

## Summary

B6 is the test half of plan §B6: one ERT file covering the downstream
`gascity-beads-sling` registration against beads.el's public seams, so the
provider, backend argv, validators, registration idempotence and delegation
contract are pinned by tests rather than by the implementation commits' manual
proof.

The work tree was built for this item because B6 needs all of B2–B5 in one
tree while they landed on separate branches: `beads-sling-b6` starts at
`beads-sling-b3b` (B1 `e8b6010` + B2 + B3a `2a54631` + B3b `04bb525`) and
cherry-picks B4 `683a314`, B5a `89f275d`, B5b `b07bdce`. The only conflict was
B5a's and B5b's independently created `lisp/test/gascity-beads-sling-test.el`;
both suites are kept in full (B5b's tests renamed to the repo's
`gascity-test-*` convention), and no implementation file changed except through
those cherry-picks.

Coverage:

| ID | Status |
| --- | --- |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-007 | covered |
| REQ-008 | covered |

Tests added (all named `gascity-test-beads-sling-*`):

| AC | Test | What it pins |
| --- | --- | --- |
| AC-4 | `provider-warm-roster` | warm `gc agent list` → qualified names, `:backend "gc"`, rig + city targets, metadata `:rig`/`:city`/`:qualified-name`/`:source`, reader stubs signal |
| AC-4 (ext.) | `provider-rig-repo-directory` | a rig-repo `default-directory` outside the city tree resolves through the rig memo, cache-only |
| AC-5 | `provider-cold-store` | cold store → nil in the same call, no spawn, beads' sling transient still renders |
| AC-6 | `backend-plain-argv` | exact plain argv through the stubbed action runner; the action is pending, not blocking |
| AC-7 | `backend-on-argv` | exact `--on` argv with repeated `--var` in the context's order |
| AC-8 | `backend-formula-argv` | targeted and targetless `--formula` argv, no empty-string target |
| — | `backend-targetless-on-refuses` | a targetless `on` signals `user-error` before the runner |
| AC-6 | `backend-plain-echo-and-invalidate` | `Slung BEAD to TARGET`, then one invalidation per store kind (`agent run session convoy status`), `:refetch t`, city as `:dir` |
| AC-6 | `backend-failure-echo` | first stderr line echoed, full stderr in `*gascity-log: CITY*`, nothing invalidated |
| AC-10 | `validator-cross-store` | exactly one documented cross-store warning, no refusal |
| AC-10 | `validator-missing-vars` | exactly one `Missing required vars: …` warning, no refusal |
| AC-10 | `validator-clean-input` | a clean same-store input yields no warnings |
| REQ-005 | `validator-trap-needs-warm-gascity-cache` | the v2 target trap is silent on a cold gascity recipe cache and fires once the recipe is cached |
| AC-12 | `registration-idempotent` | one provider entry, one `"gc"` backend, one `[City]` group, stable target-list length, no spawn |
| AC-13 | `delegation-s-then-dispatch` | beads' `S` seeds `:work`, then a `gc` target dispatch reaches the stubbed runner with the expected argv |

The pre-existing B5a (`menu-and-actions`) and B5b (`after-action-*`) tests stay
in the file and keep covering AC-13's menu group and the after-action
invalidation. The D9 non-blocking guard entry for
`gascity-beads-sling--dispatch` (added by B3b in
`lisp/test/gascity-store-test.el`) is retained; B6 introduced no new
input-free verb, so the guard list needed no further entry.

## Intended Behavior

- With beads.el loaded and a warm cached roster, the Who picker offers the
  city's configured agents under their qualified gc names; the target list is a
  pure cache read (no synchronous `gc` at render or menu-setup time) and a cold
  store degrades to no gc targets while the menu still renders.
- Dispatching a bead to a `gc` target starts exactly one async `gc sling`
  action (`--json` follows the positional arguments), with `--on FORMULA
  --var k=v` for the targeted formula shape and `--formula` for the
  formula-only shape; an absent target drops out instead of becoming an empty
  argument.
- The registered backend suppresses the store's generic sling invalidation and
  invalidates each affected store kind once on success; a failure keeps the
  inherited first-stderr-line echo and the city log.
- The advisory validators return warnings only: one per documented condition,
  nil for clean input, and the gascity-only trap only when its gascity recipe
  is already cached (the beads recipe never triggers it).
- Registration is idempotent and load- and render-side-effect-free.

## Changed Files

| File | Change |
| --- | --- |
| `lisp/test/gascity-beads-sling-test.el` | Adds the B6 coverage above; keeps B5a's menu test and B5b's after-action tests (renamed to the `gascity-test-*` convention); merges the two branches' independently added files. |

No production file changed by this item; no beads.el path, no `gc` CLI/server
behavior, no second argparse.

## Verification

Byte-compile warnings-as-errors plus the whole ERT suite, and the CI lint bar,
from the item's worktree:

```
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 843 tests, 843 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)

$ scripts/lint.sh
lint: package-lint is not installed; skipping package metadata checks (CI installs it)
$ echo $?
0
```

Focused run of the new file alone: `Ran 21 tests, 21 results as expected`.

Both gates are green with the new file included (828 tests before B6's
additions, 843 after: 15 new tests).

## Remaining Risks

- The test file's transient-render case binds `overriding-terminal-local-map`
  and `transient--prefix` locally: in batch, `transient-quit-all` cannot
  restore the overriding map, and a leaked map shadowed later tests' key
  lookups (found and fixed in this item). If a future beads.el transient
  changes its cleanup, revisit that binding.
- AC-6's prose writes the argv as `("sling" TARGET BEAD)`; the accepted B3b
  implementation asks for the parsed payload, so the runner receives
  `("sling" TARGET BEAD "--json")` and `--json` follows the positionals before
  the routing flags. The tests pin the actual argv and say so in their
  docstrings.
- B6 does not rerun the interactive tmux/TRAMP acceptance pass (AC-15, B8);
  that pass and the PR/landing remain B8's work.
- The branch is stacked on B3b and carries B4/B5a/B5b as cherry-picks; the
  Refinery must merge those (or their equivalents) before or with `beads-sling-b6`.
