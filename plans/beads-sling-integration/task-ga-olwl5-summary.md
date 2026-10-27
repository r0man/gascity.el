---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-fgn0a
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
    - path: beads/ga-olwl5
      hash: bead:ga-olwl5
      title: "B3b source anchor: async gc sling launch, echo and single invalidation"
      ids:
        - REQ-003
        - REQ-004
        - REQ-007
    - path: plans/beads-sling-integration/build-b/implementation-plan.md
      hash: sha256:7bf8cb5ea946b88159f3a058ec16064109240a7e7197909b3d5ca6bdb6fe3cc0
      title: "Approved workstream-B plan, B3b (async, echo, single invalidation) and B6 guard rule"
    - path: plans/beads-sling-integration/requirements.md
      hash: sha256:2046b64245d0f4a45b7252f5ca4ff46086e0ee4fa2cef53c4482d6906c12d09f
      title: "REQ-003 plain dispatch echo, REQ-004 formula/vars launch, REQ-007 registration limits"
    - path: plans/beads-sling-integration/decomposition.md
      hash: sha256:e7a28e51ccf05f5d73740b59c94ee212c3882b2b095ea294e9716fd8e3dec6e4
      title: "Work-item B3b boundary and its B3a dependency"
    - path: lisp/gascity-beads-sling.el
      hash: sha256:e60c6145bfb4ac22f19da604391960023f37762f59c16369f436d7c32543498a
      title: "Changed: target memory at start, single success closure, per-kind invalidation"
    - path: lisp/test/gascity-store-test.el
      hash: sha256:8090ced5d89520055886290ecea53d26f053bef4ff54ce5ca95663d29b9c974d
      title: "Changed: D9 non-blocking guard entry for the backend dispatch"
    - path: lisp/test/gascity-test-helpers.el
      hash: sha256:e0ca9e77dedc7376e5c47c5abe0a75eedd280dbb0472685d242396d4ca490389
      title: "Changed: reset the backend's remembered city between tests"
    - path: lisp/gascity-beads-sling.el
      hash: git:5bb1b974ff38d70beadc0299615e9dabf8a7f17b
      title: "B3b commit on beads-sling-b3b (stacked on B3a 2a54631)"
  coverage:
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-007
      status: covered
---

# Implementation Summary — B3b: async gc sling launch, echo and single invalidation (ga-olwl5)

## Summary

B3b owns the launch half of plan §B3 (F6 split): the `"gc"`
`beads-sling-backend` dispatch must start `gc sling` asynchronously, echo the
verb/target (or the created workflow root with the `F` follow offer for a
formula shape), surface a failure's first stderr line through the inherited
action echo, and invalidate the launcher's cached store kinds exactly once per
dispatch.

The async call itself landed with the B1 module commit `e8b6010`, so this item
verified it against B3b's contract and fixed the three deviations it found:

1. The plain-shape success path used an ad-hoc `"Slung <bead> to <target>"`
   message instead of `gascity-action--success-text`, so the echo did not match
   the rest of the action surface. The success closure now echoes through
   `gascity-action--success-text` for `plain` and through
   `gascity-sling--launch-handler` for `on`/`formula`, and only then
   invalidates — the plan's single unconditional closure (P5).
2. The resolved target was never recorded as the (city, formula) launch memory,
   while the gascity sling transient records it at start. A beads dispatch now
   calls `gascity-sling--remember-target` before `gascity-command-act-async`, so
   the Who default is consistent across both entry points.
3. The invalidation used an argv-prefix list (`("agent" "list")` …). It now
   makes one `gascity-store-invalidate` call per store kind — `agent`, `run`,
   `session`, `convoy`, `status` — with `:refetch t`, matching plan §B3b and
   the B6 assertion shape. `:invalidate nil` keeps the store's built-in sling
   route from double invalidating.

The D9 non-blocking guard also gains the backend dispatch entry (it hands one
action to the store and returns) and the shared test helper resets the
backend's remembered city, so it cannot leak between tests. `:target (or target
bead)` is passed explicitly, as the plan pins the action lane's serialization
key.

## Intended Behavior

- Pressing `s` in beads.el's sling transient after choosing a `gc` target
  returns to the command loop immediately; `gc sling` runs on the action lane
  of the resolved city (`:dir`).
- Plain shape (`("sling" TARGET BEAD)`): a successful payload echoes the
  action's success text (`GC sling: ok` for the `ok` payload).
- `on` shape (`("sling" TARGET BEAD "--on" FORMULA "--var" k=v …)`): a
  successful payload echoes the created workflow root
  (`Launched workflow <id> (<formula> on <work>) — F: run view`) and offers the
  momentary `F` jump, exactly as the gascity sling transient does.
- `formula` shape keeps its targeted/targetless argv and the same root echo.
- A non-zero exit echoes the first stderr line (`gc sling … failed: <line>`)
  and appends the full stderr to `*gascity-log: CITY*`; nothing is invalidated
  because nothing changed.
- One success invalidates exactly one `gascity-store-invalidate` call per kind,
  with `:refetch t` and the launch's city as `:dir`; the store's in-flight
  dedupe collapses success + event/follow-up invalidations to at most one
  refetch per entry. No timer and no render path invalidates.
- The resolved target is recorded in `gascity-sling--target-memory` for
  `(city . formula)` when the action starts, and the city is remembered for the
  cold-start target provider.

## Changed Files

| File | Change |
| --- | --- |
| `lisp/gascity-beads-sling.el` | target memory at start; one success closure per plan B3b (success text vs launch handler, then invalidate); per-kind invalidation helper; `:target` pinned on the action. |
| `lisp/test/gascity-store-test.el` | D9 non-blocking guard entry for `gascity-beads-sling--dispatch`. |
| `lisp/test/gascity-test-helpers.el` | reset `gascity-beads-sling--remembered-city` between tests. |

No other file changed: no beads.el path, no `gc` CLI/server behavior, no second
decoder or argparse.

## Verification

First verification command (byte-compile warnings-as-errors + full ERT):

```
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 822 tests, 822 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)
```

Final proof command (the CI lint bar):

```
$ scripts/lint.sh
lint: package-lint is not installed; skipping package metadata checks (CI installs it)
```

Result: PASS — no checkdoc warnings on any `lisp/*.el`; `package-lint` is not
installed locally, exactly as CI documents.

Focused acceptance check (batch Emacs, not committed — the ERT form lands in
B6 as planned; `lisp/test/gascity-beads-sling-test.el` does not exist in this
run yet):

- one action per dispatch for `plain`, `on` and `formula`; argv
  `("sling" TARGET BEAD)` plus `--json`, `("sling" TARGET BEAD "--on" F "--var"
  "k=v")`, `("sling" TARGET F "--formula" "--var" "k=v")`;
- the plain success payload echoes `GC sling: ok`, the `on` payload echoes
  `Launched workflow ga-1 (do-work on bd-1) — F: run view`;
- one invalidation per kind in the order `agent run session convoy status`,
  each with `:refetch t` and the city as `:dir`, and a failing action
  invalidates nothing;
- a successful dispatch records `TARGET` under `(city . formula)` in
  `gascity-sling--target-memory`;
- the guard entry leaves exactly one action started on the store and zero
  synchronous reads.

## Remaining Risks

- The async/echo/invalidate-once ERT is B6's (`ga-hbeuz`), per plan §B6; this
  item's proof is the gate plus the batch acceptance check above. B6 must assert
  the `:kind`-per-call invalidation shape this commit implements, not the older
  prefix form.
- The invalidation fires only on success. A dispatch that fails after gc
  partially mutated state is not re-read; that matches "nothing changed on a
  non-zero exit" and the rest of the action surface, which relies on the
  success callback.
- `gascity-action--success-text` has no `sling` entry in
  `gascity-action--done-verbs`, so a plain launch echoes
  `GC sling: <summary>` rather than `Slung <target>`. That is the plan's
  prescribed echo; adding a verb row would change the existing gascity sling
  transient's fallback and is out of this item's scope.
- Plan B3b/B6 states the backend dispatch is not a command-loop verb and so
  need not join the D9 guard. It is nevertheless added here at the bead's
  request; the entry is harmless (the guard asserts one async action and no sync
  read) and it guards the non-blocking contract directly.
- The launcher root bead (`ga-fgn0a`) carries no `gc.work_dir`; the validator was
  run from the launcher rig root `/home/roman/workspace/gascity.el` as the
  durable rig root, with the summary recorded at an absolute worktree path.
