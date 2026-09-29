---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-t9l5
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
    - path: beads/ga-me2n
      hash: bead:ga-me2n
      ids: [REQ-012]
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: lisp/gascity-action.el
      hash: git:af56c49
    - path: lisp/test/gascity-sling-test.el
      hash: git:af56c49
    - path: lisp/test/gascity-test-helpers.el
      hash: git:af56c49
  coverage:
    - id: REQ-012
      status: covered
---

# WI-9 — State and memory preserved

Work item WI-9 of the sling command redesign (REQ-012), implemented in
the per-bead worktree `/home/roman/workspace/gascity.el/worktrees/ga-me2n`
(commit `af56c49`, source anchor `ga-me2n`, workflow root `ga-t9l5`).

This worktree is the current-generation (transient-based) sling menu:
the adaptive staged layout of WI-1..WI-8 is being implemented in
parallel sibling worktrees, so WI-9 here lands on the layout this
anchor owns — every deliverable that names the new layout's readers is
either already held by this generation (and pinned by tests) or lands
as the contract the new readers must satisfy.

## Summary

`gascity-sling--remembered` keeps its per-city scope+values contract
unchanged: a re-entered `S` restores the remembered scope and infix
values, the layout renders from the scope, and `s` forgets the city's
state after a real launch while `p` keeps and remembers it (S-2). The
new piece of WI-9 is the per-(city, formula) launch target memory:
`gascity-sling--target-memory`, an alist `(CITY-DIR . FORMULA) →
TARGET` recorded in `gascity-sling--run` when a formula sling really
launches — after the dispatch returns, so a refused validation never
records, and never on a preview. It is launch memory, not menu state:
the `s` forget and the `x` reset that clear the remembered menu state
never clear it, and the per-test reset in `gascity-test--reset-store`
clears it beside `gascity-sling--remembered` so no test leaks it into
the next. `x`'s clearing of the infix values (the re-setup carries no
`:value`, so the transient re-initializes every infix from its
default) is now pinned by a test. The per-(formula, var) minibuffer
histories, the entry prefetch and the `g` refresh machinery are
untouched.

The worktree also contained an earlier in-progress draft of this same
item (uncommitted); this pass reviewed it, tightened the blank-target
guard to mirror the dispatch's own shape building (`gascity-formula--nonblank`),
added the per-test reset and the refused/blank-target/`x` tests, fixed
a nonexistent ERT macro (`should-null` → `(should (null …))`) and two
unbalanced-paren load failures, and committed the result.

## Intended Behavior

- `gascity-sling--remembered`: per-city alist CITY-DIR → (SCOPE .
  VALUE); remembered on every re-setup (`-f` pick, `-T`, `A`, `g`,
  `p`), restored at entry, cleared by `x` and by a real `s` (S-2). A
  remembered state reopens the menu with its scope and its answers
  (the bead at point still wins the arg). Retained and covered by the
  existing S-2/reentry tests.
- `gascity-sling--target-memory`: per-(city, formula) alist
  `((CITY . FORMULA) . TARGET)`; the key is the pinned city directory
  the launch ran against (`gascity-sling--city-dir`, so a launch from
  the no-`:city` fallback still records under the directory it really
  ran in) paired with the scope's formula. `gascity-sling--remember-target`
  records only a real launch's target: nil city/formula or a blank
  target records nothing — a blank target is dropped by the dispatch's
  own shape building, so it was never used.
- Recording runs in `gascity-sling--run` after
  `gascity-sling-formula--dispatch` returns: a validation `user-error`
  (missing required var, convoy-requiring formula with no work)
  never records; a preview (dry run) records nothing; the plain path
  records nothing (the memory is keyed by formula). The Who default
  derivation (WI-3's `gascity-sling--derive-target`) reads the memory
  back as its memory tier — the reader lands with WI-3.
- `x` (`gascity-sling-dispatch-reset`) clears the scope's formula,
  target and arg (this generation's work slot), forgets the city's
  remembered state, and re-setups with no `:value` so every infix
  value returns to its default — no var or routing flag survives. It
  keeps the launch memory.
- `s` still forgets the remembered state after a real launch (S-2)
  and now records the launch memory at the same time; the two are
  distinct: menu state is per-city and ephemeral, launch memory is
  per-(city, formula) and durable across `x` and launches, like the
  per-(formula, var) histories (REQ-010, untouched).
- City pinning (`gascity-sling--city-dir`, ga-4ia4): the contract now
  states that every reader the menu gains — the work picker, the
  agent picker, a file or directory completion — runs under the same
  pin, resolving against the entered-from city only through this
  function. All readers of this generation (formula picker, target
  read, dispatch, recipe preview, menu setup) are pinned and tested.
- The entry prefetch (warming catalog + `gc formula list` through the
  store) and the `g` refresh machinery are unchanged.

## Changed Files

- `lisp/gascity-action.el` — new `gascity-sling--target-memory` defvar
  and `gascity-sling--remember-target`; `gascity-sling--run` records
  the target after a real formula dispatch; `gascity-sling--city-dir`'s
  docstring gains the every-new-reader pin contract (REQ-012); a
  forward `declare-function` for `gascity-formula--nonblank`.
- `lisp/test/gascity-sling-test.el` — new WI-9 tests:
  `gascity-test-sling-launch-records-target-memory` (real launch
  records (city . formula) → target while the post-launch forget
  clears only the menu state),
  `gascity-test-sling-preview-records-no-target-memory`,
  `gascity-test-sling-plain-launch-records-no-target-memory`,
  `gascity-test-sling-refused-launch-records-no-target-memory`
  (a validation `user-error` records nothing),
  `gascity-test-sling-blank-target-records-no-target-memory`,
  `gascity-test-sling-reset-clears-values-too` (`x` clears scope and
  infix values, keeps the launch memory); the file commentary gains
  the WI-9 note.
- `lisp/test/gascity-test-helpers.el` — `gascity-test--reset-store`
  clears `gascity-sling--target-memory` beside
  `gascity-sling--remembered` (both are session-wide tables a test
  could leak into the next).

## Verification

First verification command (from the worktree):

    bash scripts/gate.sh

Observed: FAIL — `eldev compile` passed; `eldev test` reported 3
unexpected results: the two new recording tests used a nonexistent ERT
macro (`should-null`), and one unrelated timing flake
(`gascity-test-agent-detail-follow-log-stderr-goes-with-it`, which
passes alone and in a full rerun — the same flake the WI-1 item
recorded; no agent/terminal code is touched by this change). Fixed
the macro to `(should (null …))`; the next run then failed to load the
test file (a missing closing paren introduced by the fix), fixed
with `parenmedic diagnose` and a rerun of the sling selector (34/34).

Final proof command (from the worktree):

    bash scripts/gate.sh

Observed: PASS — byte-compile clean under `--warnings-as-errors`,
`eldev test` green: `Ran 672 tests, 672 results as expected, 0
unexpected`. The six new WI-9 tests pass alongside the retained S-2
and remembered-state reopen tests
(`gascity-test-sling-preview-keeps-state-and-s-slings-it`,
`gascity-test-sling-reentry-restores-and-x-resets`).

Non-blocking D9: the recording is pure alist bookkeeping after the
async dispatch call — no new synchronous gc anywhere.

## Remaining Risks

- `gascity-sling--derive-target` (WI-3) does not exist in this
  worktree; the memory is recorded but nothing reads it until WI-3
  lands. When the sibling worktrees are reconciled, the alist shape
  (cons key `(CITY-DIR . FORMULA)`, `equal`-tested, target string)
  must be kept — the defvar docstring documents the reader. If WI-3
  chooses a different shape, the recording and the three
  no-record guards are the pieces to re-point.
- The recording keys on the pinned `default-directory` (what
  `gascity-sling--city-dir` resolves to inside `gascity-sling--run`),
  which equals the scope's `:city` whenever the menu was entered
  through a view; a launch from the no-`:city` fallback records under
  the directory it actually ran in. That is the truthful key for
  "the city the launch really used", but a WI-3 derive that looks up
  strictly by `:city` must use the same resolution to hit.
- `x`'s value clearing relies on transient's fresh-setup semantics
  (a `transient-setup` without `:value` re-initializes every infix
  from its default); the test pins the absence of `:value`, not the
  transient internals — a transient upgrade that changes this would
  surface there first.
- No interactive bright-lights end-to-end pass for this item: the
  sling redesign's tmux-Emacs TRAMP acceptance is WI-11's scope, and
  the state/memory contracts here are fully stubbed at the gc
  boundary (offline ERT).

| ID | Status |
| --- | --- |
| REQ-012 | covered |
