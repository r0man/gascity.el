---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-x76w
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
    - path: beads/ga-f4w0
      hash: bead:ga-f4w0
      ids:
        - REQ-009
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: lisp/gascity-action.el
      hash: sha256:b808ab4fdac2797eafc3be03b4eae374fe70e81201e4badcd09edc6633cbb148
    - path: lisp/gascity-formula.el
      hash: sha256:0a9d33bffb844c8709c929d3f8b7641eb5f88e8121a03d6ddc63f4d076bd7e3b
    - path: lisp/test/gascity-sling-test.el
      hash: sha256:c4520677f2e9b8473822bd6733c972c5111f0273512bdf3e70548e378b06b663
  coverage:
    - id: REQ-009
      status: covered
---

# Implementation summary — WI-8: launch and follow offer (ga-f4w0)

## Summary

Work item WI-8 of the sling command redesign is implemented in
worktree `worktrees/ga-f4w0`, commit `0853cd9d6e90`
("feat(sling): a formula launch echoes the created root and offers F
to follow it (ga-f4w0)"), on top of origin/main `69eed1c`.  A
successful formula-path sling launch now echoes
`Launched workflow <id> (<formula> on <work>) — F: run view` and
installs a momentary follow map (`set-transient-map`): the next `F`
jumps to `gascity-run-show` on the created workflow root — in its
owning rig store when the root id's prefix resolves one — and any
other key dismisses the map and runs its own binding, so the user
stays put.  The workflow root is named by the `gc sling --json`
payload's root field; when the payload does not name one, the newest
run root created since the launch is resolved through a store
`bd list` read — never a guess.  Plain-route launches keep the plain
echo and no offer.  The launch stays async throughout (D9): the
handler runs only from the act's `:on-success`, never blocking the
command loop.

## Intended Behavior

Per `plans/sling-command/implementation-plan.md` WI-8 and
requirements REQ-009:

- **`s` dispatches exactly as today**: the formula path runs
  `gascity-sling-formula--dispatch` and the plain path
  `gascity-command-act-async` on the parsed routing flags; the
  launch is started and the function returns (D9, non-blocking).
- **The follow offer (REQ-009)**: on a formula-path success the act
  handler `gascity-sling--launch-handler` fires.  When the `gc sling
  --json` payload names the created workflow root
  (`gascity-sling--launched-root`), it echoes
  `Launched workflow <id> (<formula> on <work>) — F: run view` and
  `gascity-sling--follow-offer` installs a one-keypress transient
  map: `F` calls `gascity-run-show` on the root (the owning rig
  store resolved from the id prefix against the rig memo,
  `gascity-sling--root-rig`, so `b`/RET inside open its beads in the
  right store; a city-store root or a cold memo reads as the city
  store).  Any other key dismisses.  No map is installed over an
  active minibuffer, whose input it would hijack.
- **The fallback (never a guess)**: a payload without a root field
  takes `gascity-sling--resolve-launched-root`: the run roots of the
  city's stores are read once through the store
  (`gascity-sling--read-run-roots` under key
  `gascity-sling--run-roots-key`; the completed action has already
  invalidated the `bd` kind, so the read answers post-launch) and
  `gascity-sling--newest-run-root` picks the newest bead created at
  or after the launch's start (a two-second allowance covers
  whole-second rounding and clock skew); rows without an id or a
  parseable timestamp are skipped.  A launch that resolves no root
  at all keeps the plain success echo
  (`gascity-action--success-text`).
- **Plain route unchanged**: only the formula path attaches the
  launch handler; the plain route keeps its plain echo and no
  offer.
- The `gc sling --json` root field itself is confirmed in the e2e
  pass (WI-11); until then the fallback above covers a missing
  field.

## Changed Files

- `lisp/gascity-action.el` — the follow offer machinery: the
  payload readers (`gascity-sling--launched-root`,
  `--launched-formula`, `--launched-work`), the owning-rig
  resolver (`--root-rig`), the store-backed newest-root fallback
  (`--read-run-roots`, `--run-roots-key`, `--newest-run-root`,
  `--resolve-launched-root`), the echo + momentary map
  (`--follow-offer`) and the act handler (`--launch-handler`); the
  formula path's act is started with `:on-success` wired to it.
- `lisp/gascity-formula.el` — the formula dispatch passes
  `:on-success (gascity-sling--launch-handler command name arg)`
  to `gascity-command-act-async` (the plain path's act is
  untouched); commentary mentions the follow offer.
- `lisp/test/gascity-sling-test.el` — the launch follow offer tests:
  the payload-named root case (echo text, the transient map
  installed, `F` jumps to `gascity-run-show` with the root and the
  resolved rig), the newest-root fallback case (store read
  stubbed, the resolved root offered), the no-root plain-echo case
  (no map, plain success text), the minibuffer guard, and the
  payload field readers.

## Verification

First verification command (from the worktree):

    eldev test gascity-test-sling

observed: PASS — 36/36 sling tests green (2026-09-27 16:51:18+0200),
including the follow-offer cases: the echo text
`Launched workflow ga-1 (do-work on gce-9) — F: run view`, the `F`
jump into `gascity-run-show`, the newest-root fallback through the
store read, the plain echo with no map, and the minibuffer guard.

Final proof command (from the worktree, the repo's standard gate):

    scripts/gate.sh

observed: PASS — `eldev compile --warnings-as-errors` clean and the
full ERT suite green (674/674 tests passed, 2026-09-27 16:51:07+0200).

## Coverage

| ID | Status |
| --- | --- |
| REQ-009 | covered |

## Remaining Risks

- **Parallel-wave seam**: this commit sits on origin/main `69eed1c`,
  which does not yet carry the sibling sling waves (WI-1's shape
  header, WI-4's adaptive layout and work picker, WI-5's typed How
  vars).  The follow offer is written against the dispatch as it
  stands there (`:arg` scope slot); the publish chain merges the
  unit commits in dependency order.
- **Cross-unit content crossing (needs convoy-level
  reconciliation)**: the parallel WI-4 unit (ga-f7a4, closed) committed
  this same follow-offer patch as its unit commit `83c53672cfbd`,
  mislabeled "adaptive mockup layout … (ga-f7a4)", while its own
  summary describes the WI-4 layout machinery — which is *not* in
  that commit.  The WI-4 machinery was found uncommitted in this
  unit's worktree (`worktrees/ga-f4w0`) and is preserved verbatim in
  this repository's stash
  ("WI-4 layout+picker machinery found uncommitted in ga-f4w0
  worktree …").  The two unit commits carry identical follow-offer
  content (per-file sha256 traces match), so merging the chain is
  clean; the WI-4 unit's commit/summary mismatch and the stranded
  layout machinery should be reconciled by the convoy's review or
  finalize stage, not by this unit.
- The echo's `<work>` shows the payload's `bead_id` when it answers,
  else the slung work; a launch that somehow carried neither renders
  `…` (defensive; the dispatch's shapes always carry one).