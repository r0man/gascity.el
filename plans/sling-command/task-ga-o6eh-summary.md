---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-pkb9
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
    - path: beads/ga-o6eh
      hash: bead:ga-o6eh
      ids:
        - REQ-006
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: lisp/gascity-formula.el
      hash: sha256:ab470a7911aaa4f7f4ccc78480411d78d89ca98d8596a0f4eba24e1d4f5798de
    - path: lisp/gascity-action.el
      hash: sha256:a21e48e0fbf7d73892067b95126bc9289cc0fb344b58362bd09c2d948ed485a2
    - path: lisp/test/gascity-test.el
      hash: sha256:5208e58e8b96ac8327040bb917468852a8515d2f8e7f06d12141002d989e0e0e
  coverage:
    - id: REQ-006
      status: covered
---

# Implementation summary — WI-5: Typed How vars (ga-o6eh)

## Summary

Work item WI-5 of the sling command redesign is implemented in
worktree `worktrees/ga-o6eh`, commit `2f83f30` ("feat(sling): typed
How vars read like their shape (WI-5)"), on top of origin/main
`69eed1c`.  The How group's generated infixes now follow each var's
shape (REQ-006): four new infix subclasses beside the existing
enum/bool/string ones — a file option (`read-file-name` completing
relative to the target rig's workdir, the read's `default-directory`
pinned there, TRAMP-safe), a directory option
(`read-directory-name`), an agent option (the `T` roster
completion), and a numeric option whose read refuses any non-digit
entry with `Var %s must be numeric (got %s)` before any gc call
could run.  The `gascity-sling-formula--var-class` heuristic picks
the class: the overridable `gascity-sling-var-readers` alist first
(typed reader, infix class, or any custom function wrapped as the
var's custom reader), then the naming conventions (`context_path`
and `*_path` → file; `artifact_root` → directory; `*_target` →
agent; numeric by an all-digit declared default or the
`max_*`/`*_iterations` convention); anything unrecognized fails
soft to the string option.  `gascity-sling--title-slug` derives the
`artifact_root` seed `plans/<slug>/` from the work bead's title
(downcase, non-alphanumeric runs → `-`), falling back to freeform
task text and then the formula name — never the bare bead id;
`rig_name` seeds the chosen target's rig and `*_target` vars seed
the target itself.  Menu entry records the work title at point into
the scope (`:work-title`), the seeds feed the infixes through
`gascity-sling-formula--var-seed`, and the infix descriptions carry
the mockups' `[file]`/`[dir]`/`[agent]`/`[numeric]` markers.
`gascity-sling-formula--current-values` and the deterministic key
assignment are unchanged; vars whose natural key candidates run out
group under the mockups' `…  (N more vars)` overflow subgroup while
keeping their deterministic keys.

## Intended Behavior

Per `plans/sling-command/implementation-plan.md` WI-5 and
`menu-mockups.md` §4, and the source-anchor bead ga-o6eh:

- **Typed readers (REQ-006)**: each typed read runs with
  `default-directory` pinned to the target rig's workdir
  (`gascity-sling-formula--rig-workdir`: the qualified target's rig
  via `gascity-beads--rig-path`, else the work bead's owning rig via
  `gascity-beads--bead-path-cached`, each read I/O-free through the
  rig memo; neither resolves → the entered-from city
  `gascity-sling--city-dir`, never a foreign buffer's directory).
  An erased/empty answer unsets the var; the current value, then the
  declared default, then the seed pre-fill the read.  The agent
  read's roster candidates come from the store's last good
  `session list` payload (`gascity-store-peek`, D9 — never a
  blocking read); free entry always answers (REQ-016).  The numeric
  read's `user-error` fires client-side, before dispatch could build
  any gc call.
- **Class heuristic**: `gascity-sling-formula--var-class` is pure;
  the override alist wins over every convention (including a
  declared enum), an infix-class override passes through as the
  class, any other function wraps as
  `gascity-sling-formula--function-option` whose read calls the
  site-local reader with the live infix object (absent reader
  degrades to the string read).
- **Seeds**: `gascity-sling-formula--var-seed` derives from the
  scope plist (`:work-title`, `:target`, `:work`, `:formula`) — no
  reads, no transient state; a seed overrides the declared default
  at setup (`transient-init-value`) and stays editable like any
  value; a bare session target (no rig) and a nil scope seed
  nothing (REQ-016 fail-soft).
- **Key assignment unchanged (REQ-D)**: the deterministic
  `<char><digit>` positional stage marks a var as overflow; the How
  group renders those under a `…  (N more vars)` subgroup (mockup
  §4), every var still settable under its own deterministic key.
- **Delegated rig scoping**: the rig memo reads run pinned to the
  entered-from city (`gascity-sling--city-dir`), so the memo key is
  the entered city's host.

## Changed Files

- `lisp/gascity-formula.el` — the typed infix subclasses and
  readers (`--read-file`, `--read-directory`, `--read-agent`,
  `--read-numeric`, `--var-initial`); the
  `gascity-sling-var-readers` defcustom and the
  `gascity-sling-formula--var-class` heuristic with
  `--reader-classes` and `--class-tag`; the scope seeds
  (`gascity-sling--slug`, `gascity-sling--title-slug`,
  `gascity-sling--bead-id-regexp`,
  `gascity-sling-formula--target-rig`, `--rig-workdir`,
  `--agent-candidates`, `--var-seed`, `--work-title-at-point`);
  the overflow-split `--var-children` / `--var-infix-assignments`
  and the seed-carrying `--var-infix-spec`; the `var-seed` slot on
  the option base class.
- `lisp/gascity-action.el` — the menu entry records the at-point
  work title into the scope (`:work-title`) both for a fresh and a
  remembered state; the `--var-children` call passes the scope.
- `lisp/test/gascity-test.el` — the var-children shape test
  updated (`summary_path` is now a `[file]`-tagged file option; the
  patterned `branch` var stays a plain string option); new WI-5
  tests: naming-convention class selection, override-alist
  precedence (reader/class-symbol/custom-function), numeric refusal
  message and unset behavior, slug derivation and fallbacks (title
  wins, freeform text, id skipped, formula fallback, nil),
  var-seed conventions, infix-spec seed/tag carrying, file/dir
  reads pinning `default-directory` to the rig workdir with the
  cold-memo degrade, and the dispatch seeding `:work-title`.

## Coverage

| ID | Status |
| --- | --- |
| REQ-006 | covered |

## Verification

First verification command (from the worktree, after porting the
pre-existing shape test to the typed classes):

    eldev test sling

observed: 44/44 passed (2026-09-27 16:50) — the eight new WI-5
tests plus the updated shapes test.  Before the test work the same
selector showed the one expected failure
(`gascity-test-formula-sling-var-children-shapes`, which asserted
the pre-WI-5 string classification of `summary_path`).

Final proof command (from the worktree, the repo's standard gate):

    scripts/gate.sh

observed: PASS — `eldev compile --warnings-as-errors` clean and the
full ERT suite green (674/674 tests, 2026-09-27 16:51).

## Remaining Risks

- **Sibling-wave seams**: WI-5 lands in a parallel drain whose base
  (origin/main `69eed1c`) does not yet carry the sibling waves.  The
  How group title is still the pre-WI-4 `Variables — <name>` — the
  retitle to `How — <formula> vars` is WI-4's deliverable and the
  tests assert the local shape; the publish chain merges the waves
  in order.  The agent read's roster is `session list`-based —
  WI-2's roster accessor can tighten it; the conventions degrade
  unchanged either way.
- **No live smoke of the typed reads**: the interactive TRAMP
  acceptance (bright-lights: a file var completing over a remote
  rig's workdir, the roster prompt, a numeric refusal) was not run
  in this item; it belongs to the plan's e2e walk (WI-11).  The
  unit tests pin the pinned-`default-directory` contract instead.
- **Bead-id regexp**: `gascity-sling--bead-id-regexp` mirrors
  beads.el's id shape; a work string that is freeform text but
  happens to match the id shape (a quoted id plus suffix is safe)
  skips to the formula-name fallback — fail-soft by design.
- **Pre-existing flaky test** (not this item's defect, fixed by the
  operator in the same worktree, commit `56b5acf`):
  `gascity-test-agent-detail-follow-log-stderr-goes-with-it` raced
  its stderr line against the end note; the gate run above was
  green with that fix in.
