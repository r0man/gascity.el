---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-7ts
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
    - path: beads/ga-il1
      hash: bead:ga-il1
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-013
        - AC-1
        - AC-3
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
    - path: lisp/gascity-remote.el
      hash: sha256:6a3c1172580d15c6c717097efb88ccad10d6e4fa08237b3adc23c8e7ef2d8841
    - path: lisp/gascity-context.el
      hash: sha256:7b0cf7d80859871200a9cf1c2815a1cde05646b224720f13585ad4d58a4a662d
    - path: lisp/gascity-terminal.el
      hash: sha256:26cce32a0c523715601637e14eb7386a327fef4b491986f49d54dc94937aad12
    - path: lisp/test/gascity-test.el
      hash: sha256:f77ffa61a483e326035fbae4e484d607e8ac984eee9e38dc5ee8102db03a0cbd
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-013
      status: covered
    - id: AC-1
      status: covered
    - id: AC-3
      status: covered
---

# Implementation summary — WI-2: city-root buffer naming (plan Steps 3–5)

## Summary

Work item WI-2 of the multi-city-keying decomposition (plan Steps 3–5) is
implemented in worktree `/home/roman/workspace/gascity.el/worktrees/ga-il1`,
focused commit `75423fa` (`fix(remote): qualify view buffers by city root,
not remote prefix`), based on WI-1's commit `a4e3ab8`
(`gascity-context-scope-key`, the one keying identity this item consumes).
View buffer names are now keyed by the **governing city root** instead of
the bare remote prefix: two cities on one host — the standing
`emacs-city`/`bright-lights` pair — get distinct view buffers, a remote
city's buffer name carries host AND city path, and outside any city
today's host-only shapes are byte-identical. Gate green: compile clean
(`--warnings-as-errors`), 249/249 tests pass.

## Intended Behavior

- `gascity-remote-buffer-name` (lisp/gascity-remote.el) takes an explicit
  third argument QUALIFIER, spliced in verbatim before the trailing `*`.
  Without QUALIFIER the behavior is today's host-only qualification
  (DIR's remote prefix; a local DIR returns BASE unchanged), so the 2-arg
  contract is byte-identical and `gascity-test-remote-buffer-name` passes
  unchanged. The "Buffer identity" block of the Commentary names the city
  root as the qualifier the factory passes and `gascity-context-scope-key`
  as the scheme owner (REQ-003).
- `gascity-view-get-buffer-create` (lisp/gascity-context.el) computes the
  governing city root once and reuses it for BOTH pinning and naming
  (REQ-001, REQ-004): inside a city the qualifier is the city root —
  local cities included, so `*gascity-status@/home/roman/emacs-city/*`
  and `*gascity-status@/home/roman/bright-lights/*` coexist — and outside
  any city it degrades to the remote prefix or nil, preserving today's
  host-only naming (REQ-002). Per plan-review advisory 1, the factory
  reuses `gascity-context-pin-directory` for the out-of-city pin fallback
  instead of re-deriving it inline, so the pinning rule lives in one
  place. The docstring documents this as the one naming entry point and
  that the terminal attach buffer goes through the same scheme.
- `gascity-terminal-attach-tmux` (lisp/gascity-terminal.el) derives the
  same qualifier — the city root of `default-directory`, falling back to
  the remote prefix — instead of calling `gascity-remote-buffer-name`
  with no DIR (host-only by accident). It is deliberately NOT routed
  through the factory: attach buffers pin their own `default-directory`
  and install their own project/eldoc wiring. The docstring now says
  "city-qualified".

Coverage:

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-013 | covered |
| AC-1 | covered |
| AC-3 | covered |

(REQ-005..011/014 — the rig-memo half of the scheme — were WI-1's scope
and are covered by its summary; REQ-012 holds: the single
`gascity-context-city` override is unchanged and keys by the overridden
root through `gascity-context-scope-key`. REQ-015 e2e is the
workflow-level acceptance pass. The factory-level override case of the
plan's Step 6 is left to WI-3 per the decomposition: "may land here or
in WI-3; do not duplicate".)

## Changed Files

- `lisp/gascity-remote.el` — `gascity-remote-buffer-name` extended to
  `(base &optional dir qualifier)`; "Buffer identity" Commentary block
  rewritten to the city-root scheme.
- `lisp/gascity-context.el` — `gascity-view-get-buffer-create` computes
  the city root once, reuses it for pinning and naming, and documents the
  one-naming-entry-point contract; Commentary updated to
  "city-qualified".
- `lisp/gascity-terminal.el` — `gascity-terminal-attach-tmux` derives the
  city-root qualifier (remote-prefix fallback) for the attach buffer
  name; docstring updated.
- `lisp/test/gascity-test.el` — new `gascity-test-buffer-name-per-city`
  pinning the D1 name-shape table (two local cities distinct with pinned
  roots, a remote city's full city-root name distinguishable from a local
  one, host-only shapes outside any city) plus the explicit-QUALIFIER
  cases of `gascity-remote-buffer-name`.

## Verification

- First verification command: `eldev compile --warnings-as-errors` (whole
  package, from the worktree) — observed PASS (exit 0, no warnings).
- Targeted tests: `eldev test gascity-test-buffer-name-per-city` —
  observed PASS (1/1); `gascity-test-remote-buffer-name`,
  `gascity-test-remote-localize-path`,
  `gascity-test-remote-attach-spawns-local-ssh`,
  `gascity-test-view-get-buffer-create`,
  `gascity-test-agent-attach-passes-rig-store` all pass unchanged.
- Full existing suite: `eldev test` — observed PASS (one initial failure
  was the new test itself comparing the factory's buffer object instead
  of its name; fixed the assertion, no production change involved).
- Final proof command: `scripts/gate.sh` — observed PASS ("gate: PASS
  (compile clean + tests green)", 249/249 tests, 0 unexpected).

## Remaining Risks

- User-visible name churn (plan-review advisory 2): remote *city* view
  names grow the city path (e.g. `*gascity-status@/ssh:localhost:/home/
  roman/bright-lights/*`); existing buffers under the old host-only names
  are simply orphaned, not corrupted. The tmux-Emacs e2e pass (REQ-015,
  plan Step 7, `docs/qa/` report) is the workflow-level acceptance gate
  and must confirm both cities' dashboards coexist side by side.
- Attach buffers for an agent of a *local* city now carry the city path
  in their name where they were previously bare; terminal reuse of a live
  process buffer is by name, so a pre-change attach buffer is orphaned
  the same way. Covered by the same e2e pass.
- Out-of-scope here: WI-3 owns the remaining plan steps (override test
  placement, per the decomposition).
