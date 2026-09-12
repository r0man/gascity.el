---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-h5u
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
    - path: beads/ga-t2w
      hash: bead:ga-t2w
      ids:
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-011
        - REQ-014
        - AC-2
        - AC-3
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
    - path: lisp/gascity-context.el
      hash: sha256:7b0cf7d80859871200a9cf1c2815a1cde05646b224720f13585ad4d58a4a662d
    - path: lisp/gascity-section.el
      hash: sha256:24c34c9e92907a6755a0ffc7fbbc2d188a2a926f889b8e20aafb8839d07f0b4c
    - path: lisp/test/gascity-test.el
      hash: sha256:da0d1afeaadfed2831e9b05bad617adaf9cfeb9450c86d646df6aafb52c43ee6
  coverage:
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: covered
    - id: REQ-007
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-014
      status: covered
    - id: AC-2
      status: covered
    - id: AC-3
      status: covered
---

# Implementation summary — WI-3: per-city keying unit tests (plan Step 6)

## Summary

Work item WI-3 of the multi-city-keying decomposition (plan Step 6) is
implemented in worktree `/home/roman/workspace/gascity.el/worktrees/ga-t2w`
(commit `719042e`, on top of WI-1 `a4e3ab8` and WI-2 `75423fa`). It closes
out the cross-cutting per-city ERT coverage — the tests not owned by WI-1
or WI-2 — by adding three `ert-deftest`s to `lisp/test/gascity-test.el`,
per house convention (gc boundary stubbed, no live gc in unit tests):

- `gascity-test-rigs-memo-per-city` — `gascity-rigs-remember` +
  `gascity-rigs-cached` for two local cities AND two cities under one
  TRAMP prefix (`/ssh:u@h:/c/a` vs `/ssh:u@h:/c/b`): distinct keys,
  distinct values, identical rig lists in both cities do not evict each
  other, a prefix-less list in city A blanks neither city B's prefixed
  entry nor A's own, and a third city stays cold (REQ-005, REQ-006,
  REQ-007, REQ-014).
- `gascity-test-clear-cache-cities` — after rigs are remembered under a
  local city key and a remote city key, `gascity-context-clear-cache`
  leaves both cold (REQ-008). Test-only: no code change.
- `gascity-test-override-keys-by-overridden-root` — with
  `gascity-context-city` bound to city B's root, the view factory returns
  a buffer keyed under B's root (B's root in the name, B's root pinned as
  `default-directory`), distinct from the naturally-resolved A buffer,
  which is left untouched (REQ-011).
- The bead-store path one-liners (plan-review advisory 3,
  `plans/multi-city-keying/build/plan-review.md`):
  `gascity-beads--rig-store-cached` is asserted to resolve per city from
  `gascity-rigs-cached` in both the local-cities and the TRAMP-prefix
  sections of `gascity-test-rigs-memo-per-city`.
- Regression guard: the existing remote/memo suite
  (`gascity-test-remote-buffer-name`, `gascity-test-remote-localize-path`,
  `gascity-test-scope-key-per-city`, `gascity-test-buffer-name-per-city`,
  `gascity-test-rigs-cached-never-spawns`, …) passes unchanged in meaning.

Only `lisp/test/gascity-test.el` was modified, as the item expected.

## Intended Behavior

The per-city keying scheme shipped by WI-1/WI-2 keys every city-scoped
identity by `gascity-context-scope-key` — the governing city root (which
embeds the remote prefix) inside a city, the bare remote prefix outside
one. These tests pin the partition properties a user of two same-host
cities depends on, without spawning gc:

- Two cities on one host — local (`/tmp/…/a` vs `/tmp/…/b`, temp dirs
  with `city.toml`) or under one TRAMP prefix (`/ssh:u@h:/c/a/` vs
  `/ssh:u@h:/c/b/`, walk stubbed so the fictitious host is never
  contacted) — get distinct memo keys and values. Warming one city never
  rewrites another's entry, and two identical-content lists remembered
  for different cities coexist as separate entries.
- The "prefix-less list never replaces a prefixed one" protection holds
  per city key, not globally: a prefix-less payload remembered in city A
  keeps A's own prefixed map and leaves city B's intact.
- A city with nothing memoized stays cold: `gascity-rigs-cached`,
  `gascity-rigs-cached-prefixes` and the spawn-free bead resolvers
  (`gascity-beads--rig-store-cached`, `gascity-beads--bead-path-cached`)
  answer nil with `gascity-reader-run` and `gascity-command-rig-list!`
  stubbed to error — no gc on any UI path.
- `gascity-context-clear-cache` forgets every city's key (a local one and
  a remote one), not just one host's.
- The single `gascity-context-city` override re-keys the view factory to
  the overridden root, so two override values used at different times
  never share buffers or cache entries; the override's existing contract
  (one value at a time) is exercised unchanged.

Coverage table (statuses are trace.coverage statuses, not artifact
statuses):

| ID | Status |
| --- | --- |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-011 | covered |
| REQ-014 | covered |
| AC-2 | covered |
| AC-3 | covered |

## Changed Files

- `lisp/test/gascity-test.el` (modified only): +215 lines — the three new
  tests above in a "Suite completion — cross-cutting per-city keying"
  section before `provide`. No production file was touched (D4: the
  per-city partition is asserted against the WI-1/WI-2 code as landed).

## Verification

First verification command (worktree
`/home/roman/workspace/gascity.el/worktrees/ga-t2w`):

```
eldev compile --warnings-as-errors
```

Observed: pass — the whole package byte-compiles with no warnings
(`--warnings-as-errors` gate).

Final proof command:

```
eldev test
```

Observed: pass — `Ran 252 tests, 252 results as expected, 0 unexpected`;
the three new tests report `passed` individually
(`gascity-test-rigs-memo-per-city`, `gascity-test-clear-cache-cities`,
`gascity-test-override-keys-by-overridden-root`), and the existing
remote/memo regression tests
(`gascity-test-remote-buffer-name`, `gascity-test-remote-localize-path`,
`gascity-test-scope-key-per-city`, `gascity-test-buffer-name-per-city`,
`gascity-test-rigs-cached-never-spawns`) all pass unchanged.

## Remaining Risks

- REQ-015 (the tmux-Emacs e2e pass over `/ssh:localhost:/home/roman/bright-lights`
  and the local `emacs-city` simultaneously, recorded in a `docs/qa/`
  report) is the workflow's later acceptance gate, not covered by these
  unit tests.
- The TRAMP-prefix memo sections stub `locate-dominating-file` rather
  than walking a real remote; a real TRAMP walk is exercised only in the
  e2e pass. The stub contract matches the implementation's single call
  site, but a future second walk entry point would need its own stub.
- The out-of-city remote fallback (`/ssh:u@h:` with an empty local root)
  is covered by WI-1's `gascity-test-scope-key-per-city` /
  `-rigs-cached-never-spawns` and re-asserted here only for the
  third-city-cold property; no dedicated new test was added for it in
  this item (it was not in WI-3's scope list).
