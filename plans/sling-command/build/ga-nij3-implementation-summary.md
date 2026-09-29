---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-a85f
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
    - path: beads/ga-ub2r
      hash: bead:ga-ub2r
      ids: [REQ-008]
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: lisp/gascity-action.el
      hash: git:683cece
    - path: lisp/gascity-formula.el
      hash: git:683cece
    - path: lisp/test/gascity-sling-test.el
      hash: git:683cece
    - path: lisp/test/gascity-store-test.el
      hash: git:683cece
    - path: lisp/test/gascity-test.el
      hash: git:683cece
  coverage:
    - id: REQ-008
      status: covered
---

# WI-7 — `P` full preview buffer

Work item WI-7 of the sling command redesign, implemented in the
per-bead worktree `/home/roman/workspace/gascity.el/worktrees/ga-ub2r`
(commit `683cece`, source anchor `ga-ub2r`).

## Summary

The sling menu's `p` shows gc's `--dry-run` routing plan alone. `P` now
opens the whole picture in one city-pinned buffer: the header sentence,
every client-side validation check with its full text, the cached
recipe's steps → needs DAG, and the dry-run routing plan filling in when
the async call answers. First paint is client-side and never blocks on
the dry run (D9); the preview is never a gate: `s` in the buffer
launches exactly what was previewed and `q` quits, while the menu's `s`
works anytime. The buffer is created through
`gascity-view-get-buffer-create`, so it is host-qualified
(a local and a remote preview coexist) and its `default-directory` stays
pinned to the city the menu was entered from. The command builder behind
dispatch and preview is factored into the shared
`gascity-sling-formula--command`.

## Intended Behavior

- `gascity-sling--full-preview` (the `P` suffix,
  `gascity-sling-dispatch-full-preview`) resolves the same dispatch the
  menu's `s`/`p` would run — without reading or prompting anything —
  paints the buffer at once, then starts the `--dry-run`.
- The paint (`gascity-sling--preview-paint`) renders, in order:
  - the header sentence (`gascity-sling--preview-header`, mockup §1–§4
    wording; missing pieces read as their §2 hints),
  - a **Validation** section (`gascity-sling--preview-validation-lines`):
    one full-text line per check, `✓` when it passes and `⚠` when it has
    something to say — the target, the work a convoy-requiring formula
    needs, required vars, patterns; further checks (the sling
    redesign's roster-based warnings) join through the
    `gascity-sling-preview-validation-functions` hook, called pure
    inside the city pin,
  - a **Recipe — <formula> (steps → needs)** section
    (`gascity-sling--preview-recipe-lines`): the cached recipe's
    step/deps data — what `gascity-sling-formula--render-recipe`
    renders — straight from gc's compiled recipe, never re-substituted
    (REQ-012); the plain dispatch says so,
  - a **Routing plan (gc sling … --dry-run)** section holding `…`
    (`gascity-sling--preview--plan-marker`) until the async dry run's
    stdout replaces from the marker down
    (`gascity-sling--preview-fill-plan`); a failure fills its first
    stderr line (also echoed); a killed buffer is left alone — a late
    answer never resurrects it (D9).
- First paint is client-side and never blocks on the dry run: the
  sections above render with no gc invocation; only the dry run runs gc
  (through `gascity-command-act-async` on the store's action lane,
  read-only `:invalidate nil`, `:dir` pinned to the city). A dispatch
  that cannot be built yet — no target, no work, a failing validation —
  still previews: the warning is in Validation and the Routing plan
  section keeps its reason.
- The preview is never a gate: `s` (`gascity-sling-preview-launch`) in
  the buffer launches exactly what was previewed — no input beyond what
  the menu's own `s` would read (a missing target is completed with the
  same one-shot prompt; the plain path also completes work) — then the
  call starts and returns (D9). `q` quits. The menu exits on `P` (the
  buffer is the interactive surface) but its state is remembered per
  city (bug S-2), so a later `S s` slings exactly what was previewed; a
  real launch clears it, like the menu's own `s`.
- The buffer is created through `gascity-view-get-buffer-create`
  (`gascity-sling-preview-buffer-name` = `*gc-sling: preview*`), so it
  is host-qualified (a local and a remote preview coexist), its
  `default-directory` is pinned to the city, and an I/O-free `project`
  instance keeps redisplay off TRAMP.
- `gascity-sling-formula--dispatch` is split: validation and the command
  shape live in `gascity-sling-formula--command` (returning the
  `gascity-command-sling` to act on, `--dry-run` when asked); the
  dispatch keeps its D9 start. The preview's dry run and the menu's `p`
  therefore build exactly the same command.
- `gascity-command-act-async` gains a `:dir` pin (default the calling
  buffer's directory) passed through to `gascity-store-action`, so the
  launch and the dry run hit the city the menu was entered from even
  when the current buffer's directory has moved.
- `P` is a non-transient suffix (`transient-quit` semantics: the menu
  exits); the reserved-key set `gascity-sling--reserved-keys` gains `P`
  so the generated var infixes avoid it.

## Changed Files

- `lisp/gascity-action.el` — new section "Sling — the full preview
  buffer (`P', REQ-008, mockup §8)": the buffer name constant, the
  buffer-local preview data (`:city`/`:scope`/`:launch`) and plan
  marker, the validation hook, the keymap (`s`/`q`) and derived mode,
  the header/validation/recipe line renderers, the plan fill/start
  helpers, the paint, `gascity-sling--full-preview`, the
  `gascity-sling-dispatch-full-preview` suffix, and
  `gascity-sling-preview-launch`; the plain-path launch thunk pins
  `default-directory` and passes `:dir` to the act; `P` joins
  `gascity-sling--reserved-keys` and the Actions group;
  `gascity-command-act-async` gains the `:dir` pin.
- `lisp/gascity-formula.el` — `gascity-sling-formula--dispatch` split
  into `gascity-sling-formula--command` (validation + command shape)
  and the dispatch (D9 start); docstrings updated.
- `lisp/test/gascity-sling-test.el` — the preview fixture macro
  (`gascity-sling-test--with-preview`, store-stubbed, recipe cached from
  a do-work-shaped fixture) and seven tests: sections render at first
  paint with exactly one gc spawn (the dry run),
  the plan fill on success and on failure, launch from the buffer
  (formula and plain paths, `--json`, no `--dry-run`, remembered state
  cleared), warnings-never-a-gate, the pattern warning with a refused
  dry run, the validation hook, and the suffix wiring (`P` in the
  Actions group, reserved-key sync).
- `lisp/test/gascity-test.el` —
  `gascity-test-remote-sling-full-preview`: the preview buffer from a
  remote view is host-qualified and remotely pinned; the launch spawns
  gc on the entered-from city; the unified-prefix test gains the new
  command.
- `lisp/test/gascity-store-test.el` — the non-blocking (input-free
  verb) guard gains `gascity-sling-dispatch-full-preview` and
  `gascity-sling-preview-launch`; the preview buffer joins the
  after-test sweep.

## Verification

First verification command (from the worktree):

    scripts/gate.sh

Observed: FAIL — `eldev compile` clean, but the test load aborted with
"End of file during parsing": the work-in-progress tests had three
unbalanced-sexp defects (a swallowed lambda body in
`gascity-sling--preview-start-plan`, a stray `)` closing
`gascity-test-sling-full-preview-suffix-is-wired` early, a mis-nested
block in `gascity-test-sling-full-preview-plain-path`, and one close too
few in the remote full-preview test). Fixed all four; the two remaining
sling failures (the validation-failure reason text and the
non-transient suffix assertion, whose `transient` slot is unbound on a
non-transient suffix) were fixed by passing the "see Validation above"
reason through and asserting the Actions group spec instead of the
slot; a merge of the landed WI-5 work (`cc5d836`) and a rerun followed.

Final proof command (from the worktree):

    scripts/gate.sh

Observed: PASS — `eldev compile --warnings-as-errors` clean and
`eldev test` green: `Ran 683 tests, 683 results as expected, 0
unexpected`. The seven new sling tests, the remote pinning test, and the
extended non-blocking guard all pass.

Non-blocking D9: the first paint runs no gc; the only gc call is the
`--dry-run` (read-only, no invalidation) started after the paint, and
the launch is the same async act the menu's `s` performs. No prompt, no
sync gc on render.

## Remaining Risks

- The roster-based validation checks (the bl-bdj trap, cross-store
  routing) are left to their own work item: the
  `gascity-sling-preview-validation-functions` hook is the defined
  seam, verified with a test hook, but no roster check is wired yet.
- The launch path re-uses the dispatch/`gascity-sling--run` prompts for
  a missing target/work; a formula launch from the preview has no live
  recipe-refresh — if gc's recipe changed since the menu opened, the
  preview can be stale (the dispatch re-reads only on `-f`/`g`).
- The interactive bright-lights end-to-end pass over TRAMP for the full
  preview is not part of this item; the remote ERT test
  (`gascity-test-remote-sling-full-preview`, mock TRAMP) covers the
  host-qualification and the pin.

| ID | Status |
| --- | --- |
| REQ-008 | covered |
