---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-38ose
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
    - path: beads/ga-ixydb
      hash: bead:ga-ixydb
      title: "B3a source anchor: gc sling argv builders and backend registration"
      ids:
        - REQ-003
        - REQ-004
        - REQ-007
    - path: plans/beads-sling-integration/implementation-plan.md
      hash: sha256:9172aff2d78b0a6522bbeb911fc1edd6a4442ba72ad17b67399387dd3253d313
      title: "Approved plan, Workstream B3 part i (F6 split), B3/F5 and AC-6/AC-7/AC-8"
    - path: plans/beads-sling-integration/requirements.md
      hash: sha256:2046b64245d0f4a45b7252f5ca4ff46086e0ee4fa2cef53c4482d6906c12d09f
      title: "REQ-003 plain dispatch, REQ-004 formula/vars context, REQ-007 one-way registration"
    - path: plans/beads-sling-integration/decomposition.md
      hash: sha256:e7a28e51ccf05f5d73740b59c94ee212c3882b2b095ea294e9716fd8e3dec6e4
      title: "Work-item B3a boundary in the B workstream"
    - path: lisp/gascity-beads-sling.el
      hash: sha256:12eac0c0569b242b2d8051a04e67854d39e4003dc281e4dfb28aa67e52a64bfd
      title: "gc backend registration, argv builders, target resolution, refusal and convoy rule"
    - path: lisp/gascity-types.el
      hash: sha256:61934193c06ee20b17631cbbb131f9419eec95f7aaf5544b997571b6fbd9287b
      title: "gascity-command-sling slots and the targetless --formula validation exception"
  coverage:
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-007
      status: covered
---

# Implementation Summary — B3a: gc sling argv builders and backend registration (ga-ixydb)

## Summary

B3a owns the `"gc"` `beads-sling-backend` registration and the three argv
shapes the backend builds from the beads.el dispatch context. The backend and
builders landed in the B1 module commit `e8b6010`; this item verifies them
against B3a's contract and closes the one gap the verification found: the
plan's warm-recipe convoy rule (plan §B3 item 3, F5) was not applied to the
formula-only shape.

One source change was therefore needed on top of `e8b6010`:
`gascity-beads-sling--validate-launch` now takes an optional CITY, and when a
`gascity-formula` recipe for the context formula is already in
`gascity-formula-recipe-cache` and `gascity-formula--needs-convoy` holds, a
targetless `--formula` dispatch is refused with a `user-error` before any
process starts. A cold recipe cache skips the check and leaves the refusal to
gc, exactly as the plan requires. The `:shape` still decides `--on` versus
`--formula`; the warm recipe is consulted for the convoy rule only.

The async launch, echo and invalidation halves remain B3b (`ga-olwl5`), and the
exact-argv ERT suite remains B6 (`ga-hbeuz`); this item's proof is the
batch-Emacs builder check the bead asks for.

## Intended Behavior

- One backend named `"gc"` is registered with
  `:dispatch #'gascity-beads-sling--dispatch`; re-running
  `gascity-beads-sling-register` replaces it by name and does not duplicate any
  hook or provider.
- The builder is `gascity-beads-sling--command`, which constructs
  `gascity-command-sling` objects through the beads-meta slots (never a
  hand-built argv string, never a second argparse):
  - `plain`: `("sling" TARGET BEAD)`.
  - `on`: `("sling" TARGET BEAD "--on" FORMULA "--var" "k=v" ...)` in the
    context's `:values` order, only the values beads.el resolved as set.
  - `formula` with an explicit target:
    `("sling" TARGET FORMULA "--formula" "--var" ...)`; without a target:
    `("sling" FORMULA "--formula" ...)`. An empty or blank target is dropped,
    never emitted as an empty argv word.
- `--on` versus `--formula` comes from the context `:shape`, not from
  `gascity-formula--needs-convoy` on the beads recipe (F5). The warm gascity
  recipe is used only for the convoy rule (targetless formula refusal).
- An explicit context `:target` wins; otherwise `plain`/`on` derive through
  `gascity-sling--derive-target` with
  `(list :work BEAD :formula FORMULA :city CITY)`, the cached roster and
  `gascity-sling--target-memory`. The formula shape stays targetless when the
  context names no target.
- Client-side refusal happens before any process: missing work/target for
  `plain`/`on`, missing formula for `on`/`formula`, missing required vars via
  beads.el's `beads-formula-validate-vars` (the context recipe is a
  `beads-formula`, never passed to the gascity var validator), and the warm
  convoy rule above.
- A freeform prompt is not a `gc sling` flag and is dropped with a
  non-blocking message (documented in the module commentary and the dispatcher
  docstring) rather than altering the argv.

## Changed Files

- `lisp/gascity-beads-sling.el` — `gascity-beads-sling--validate-launch` gains
  the optional CITY and the warm-recipe convoy refusal; the dispatcher passes
  the resolved city. The builders, target resolution and backend registration
  are the B1 module content and were verified unchanged.
- `plans/beads-sling-integration/task-ga-ixydb-summary.md` — this summary.

`lisp/gascity-types.el` is unchanged on this branch; its targetless
`--formula` validation exception came in `e8b6010`.

## Verification

Baseline gate on the worktree (byte-compile with warnings as errors, then the
whole ERT suite):

```bash
BEADS_DIR=/home/roman/workspace/beads.el scripts/gate.sh
```

Result: PASS — all files byte-compiled clean; `Ran 822 tests, 822 results as
expected, 0 unexpected`. (The first run hit
`gascity-test-local-reader-read-async-generic-envelope-stderr-wins`, a known
async timing flake; it passed in isolation and on the full rerun.)

The CI lint bar (`scripts/lint.sh`, checkdoc over every file; package-lint is
not installed locally, so its metadata check was skipped exactly as the
wrapper reports): exit 0, no warnings.

Pinned argv, evaluated in batch Emacs against the real builder (output of
`gascity-command-line`; the leading `"gc"` is the executable, the pinned
argument list follows it):

```text
plain              ("gc" "sling" "gascity.el/gc.implementation-worker" "ga-ixydb")
on                 ("gc" "sling" "gascity.el/gc.implementation-worker" "ga-ixydb" "--on" "build-basic" "--var" "foo=1" "--var" "bar=two")
formula-targeted   ("gc" "sling" "mayor" "build-basic" "--formula" "--var" "foo=1")
formula-targetless ("gc" "sling" "build-basic" "--formula")
```

Stable var order / blank-target proof:

```text
var-order      ("gc" "sling" "mayor" "ga-1" "--on" "f" "--var" "zeta=1" "--var" "alpha=2")
blank-target   ("gc" "sling" "ga-1")
```

Target resolution proof (derive stubbed to name its arguments):

```text
explicit="mayor" derive-called=nil
derived="gascity.el/gc.implementation-worker"
derive-args=((:work "ga-1" :formula nil :city "/tmp/city/") (("a" . "b")) nil nil)
formula-no-target=nil
```

Registration/idempotence proof after two extra `gascity-beads-sling-register`
calls:

```text
backend="gc"  dispatch-fn-eq=t  backends=("gc")
target-hook-count=1  menu-count=1  action-count=1  after-action-count=1
```

Refusal proof (all `user-error`, no process started):

```text
plain no target        user-error: No sling target selected
plain no work          user-error: No work to sling
on no formula          user-error: No formula selected for a targeted sling
formula no formula     user-error: No formula selected
missing required var   user-error: Missing required formula vars: req
cold cache             OK                      ; gc's refusal stays authoritative
warm convoy formula    user-error: Formula drainy requires a target convoy -- pick work with A
warm plain formula     OK
```

The only argv construction in the module is `(apply #'gascity-command-sling
...)`; there is no other `beads-meta-build-command-line` call, hand-built argv
or process invocation in `lisp/gascity-beads-sling.el`.

Coverage:

| ID | Status |
| --- | --- |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-007 | covered |

## Remaining Risks

- **No B3a-specific ERT yet.** The plan assigns the exact-argv ERT (AC-6/
  AC-7/AC-8) to B6 (`ga-hbeuz`). Until then the batch proof above is the
  regression evidence, not a test.
- **Async launch/echo/invalidation are B3b.** `gascity-beads-sling--dispatch`
  already contains the B1-era async launch and invalidation; B3b owns their
  verification and the non-blocking guard entry, so this item does not claim
  that behavior as complete.
- **Convoy check needs a warm gascity recipe.** With a cold
  `gascity-formula-recipe-cache` the formula-only shape is not refused
  client-side; gc's own refusal is authoritative, per plan §B3 item 3 / F5.
  This is deliberate (no false-positive refusal, no synchronous read).
- **Branch is stacked on B2, not `origin/main`.** B1/B2 are closed but their
  branches are unmerged; this worktree bases on `beads-sling-b2` (`e8b6010`).
  B8 (`ga-lii6c`) must land B1, B2 and B3a in order before the PR.
