---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-ubl
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
    - path: beads/ga-w8j
      hash: bead:ga-w8j
      ids:
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-014
        - AC-1
        - AC-2
        - AC-3
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
    - path: lisp/gascity-context.el
      hash: sha256:1d74e1abaee0acb6c72f9ddfdedb2b50a8c09a123cb3ec4265cced31fcec34d6
    - path: lisp/test/gascity-test.el
      hash: sha256:179a450c85cb2a950537aef2b71a7264702fb2e189ca030a4e1693752a9b3372
  coverage:
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
    - id: REQ-014
      status: covered
    - id: AC-1
      status: covered
    - id: AC-2
      status: covered
    - id: AC-3
      status: covered
---

# Implementation summary — WI-1: `gascity-context-scope-key` + rig memo re-key

## Summary

Work item WI-1 of the multi-city-keying decomposition (plan Steps 1–2) is
implemented in worktree `/home/roman/workspace/gascity.el/worktrees/ga-w8j`,
focused commit `a4e3ab8` on the item worktree. `lisp/gascity-context.el`
gains `gascity-context-scope-key`, the ONE city-scoped keying identity — the
governing city root (which embeds the remote prefix) when DIR is inside a
city, the bare remote prefix ("" for local) otherwise — and the rig-list
memo (`gascity-context--rigs-cache` via `gascity-context--rigs-key`) is
re-keyed onto it, so two cities on one host keep separate rig lists. The
module commentary records the REQ-010 integration point for the future
formula catalog/recipe caches. Tests: new `gascity-test-scope-key-per-city`
and a second-city extension of `gascity-test-rigs-cached-never-spawns`.
Gate green: compile clean, 248/248 tests pass.

## Intended Behavior

- `gascity-context-scope-key (&optional dir)` returns `gascity-context-city-root`
  of DIR when DIR resolves to a city (TRAMP-qualified absolute directory
  string), else `(file-remote-p dir)` — `""` for a local directory. It never
  spawns gc: the city-root walk is the memoized `gascity-context--root-cache`
  lookup, and the `gascity-context-city` override is honored first.
- `gascity-context--rigs-key` delegates to `gascity-context-scope-key`, so the
  rig memo is keyed per city, not per host: two same-host cities no longer
  share (or blank) each other's rig lists (REQ-005). Consequences asserted by
  test rather than code change (D3/D4): the prefix-less-never-replaces-
  prefixed guard in `gascity-rigs-remember` holds per city key (REQ-006); a
  city with no rigs cached stays cold — `gascity-rigs-cached`,
  `gascity-rigs-cached-prefixes`, `gascity-beads--rig-store-cached`,
  `gascity-beads--bead-path-cached` never spawn gc (REQ-007);
  `gascity-context-clear-cache` empties every city's key (REQ-008). No change
  to `gascity-rigs-remember` / `-cached` / `-cached-prefixes` or the beads
  resolvers — they all go through the key function or the memo.
- Docstrings and the `;;; Commentary:` now describe the city-root scheme and
  record that any new city-scoped cache (first consumer: the formula
  catalog/recipe caches of plans/formula-sling-ui) MUST key by
  `gascity-context-scope-key` — one key helper, one API, no second keying
  scheme (REQ-009/010). The override keys by the overridden root (REQ-011).

Coverage:

| ID | Status |
| --- | --- |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-014 | covered |
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |

(REQ-013 holds trivially at this stage: single-city-per-host users see no
behavior change — buffer naming is untouched, only the memo key changed, and
outside a city the key is still the remote prefix. REQ-001/002/003/004 and
REQ-012 belong to WI-2's factory/qualifier steps; REQ-015 e2e is the
workflow-level acceptance pass.)

## Changed Files

- `lisp/gascity-context.el` — new `gascity-context-scope-key`; re-keyed
  `gascity-context--rigs-key`; updated Commentary and the
  `gascity-context--rigs-cache` docstring to the city-root scheme with the
  REQ-010 integration point recorded.
- `lisp/test/gascity-test.el` — new `gascity-test-scope-key-per-city`;
  `gascity-test-rigs-cached-never-spawns` extended with the second-city
  assertions and its docstring corrected (per city, not per host); the
  fictitious-TRAMP-host tests (`gascity-test-rigs-cached-never-spawns`
  remote-context section, `gascity-test-remote-attach-spawns-local-ssh`)
  stub `locate-dominating-file` so the now city-root-aware memo key never
  contacts the nonexistent host.

## Verification

- First verification command: `eldev compile --warnings-as-errors` (whole
  package, from the worktree) — observed PASS (no warnings, exit 0).
- Targeted tests: `eldev test gascity-test-scope-key-per-city` and
  `eldev test gascity-test-rigs-cached` — observed PASS (1/1 each).
- Full existing suite: `eldev test` — observed PASS after the
  `locate-dominating-file` stubs (one initial failure,
  `gascity-test-remote-attach-spawns-local-ssh`, was the memo key now
  walking for a city root on a fictitious ssh host; fixed by stubbing the
  walk, not by weakening any assertion).
- Final proof command: `scripts/gate.sh` — observed PASS ("compile clean +
  tests green", 248/248 tests, 0 unexpected).

## Remaining Risks

- The memo-key computation now resolves the city root before the cache
  lookup; on a cold `gascity-context--root-cache` over TRAMP that is one
  channel round trip per path level (memoized per start dir thereafter, nil
  cached too). This is the plan's accepted trade (the walk replaces what
  used to be free) and matches how `gascity-context-pin-directory` already
  behaved; views pin to the city root, so the warm path stays I/O-free.
- WI-2/WI-3 (buffer-name qualifier, factory re-key) are not in this item's
  scope: buffer naming is still host-qualified until those land, so the full
  multi-city buffer-coexistence story is incomplete by design at this step.
- REQ-015 (tmux-Emacs e2e against `/ssh:localhost:/home/roman/bright-lights`
  and the local city) remains the workflow-level acceptance gate, not
  covered by this unit-tested item.
