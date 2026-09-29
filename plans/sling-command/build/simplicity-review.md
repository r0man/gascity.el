# Starter Simplicity Review — Sling Command Redesign (workflow ga-eavt)

- Bead: ga-loxl (build-basic review loop, step `review.simplicity-review`)
- Reviewed: merged implementation worktree `ga-3wpi`, commit `e44dcf0d`
  (plus the documentation commit `f21af52` in worktree `ga-1wl7` for the
  doc surface), diffed against `origin/main` (`69eed1c`).
- Lane: simplicity and maintainability (starter factory). Concrete,
  beginner-actionable findings only; the correctness/design-adherence
  lanes own behavior and requirement conformance.
- Verdict: **iterate** — one required fix (S1), the rest recommended.

The implementation is in good shape for a first factory run: pure
validators are kept pure and unit-tested, no gc on the render path, the
docstrings carry the design trace, and the gate is green (723/723). The
findings below are about not leaving future readers two ways to do one
thing.

## Required fix

### S1 — Three roster builders, one Who surface (lisp/gascity-agents.el, lisp/gascity-action.el)

The Who stage now has three ways to produce "the agent roster", and only
one of them is wired to what the user actually completes against:

1. `gascity-agents-roster` / `gascity-agents-roster-candidates` /
   `gascity-agents--read-roster` (gascity-agents.el:261–333) — the
   planned WI-2 accessor: joined roster, city-first ordering, annotated
   candidates, and a **blocking busy-wait loop**. Production code never
   calls it; only its tests do. The `T` picker actually completes over
   `gascity-action--session-names` (unannotated), via
   `gascity-action--read-session`.
2. `gascity-sling--roster` (gascity-action.el:1314) — the Who default
   derivation's roster, built from the `gc agent list` payload only.
3. `gascity-sling--roster-cached` (gascity-action.el:1764) — the live
   footer's roster, built by a *different* join (`gascity-agents--roster`
   over three store peeks: status, session list, agent list).

Two risks follow, both easy for the next maintainer to trip on:

- The unused accessor looks like *the* roster API (exported, documented,
  tested) but answers from different data than the derivation and the
  footer use — a future caller wiring it in would silently change who
  the sling can derive or warn about.
- The header's derived target and the footer's scope classification can
  disagree for an agent that one roster knows and the other does not
  (session-list agents are in the footer's join, not the derivation's).
  This area already produced one integration seam during WI-11 (footer
  vs Who default, fixed in 806c0dc); two divergent data sources keep
  that class of bug available.

**Smallest useful fix** (one small commit, no behavior redesign): make
one roster source feed the Who surface. Keep `gascity-agents--roster`
(the pure join) as the single builder; have `gascity-sling--roster`
call `gascity-sling--roster-cached` (or both call the join) so the
derivation and footer read the same list; then either wire
`gascity-sling-dispatch-target` through `gascity-agents-roster-candidates`
(which is what the plan intended — annotated candidates) or delete the
unwired `gascity-agents-roster` / `-candidates` / `--read-roster` trio
and their tests. The blocking wait loop should not survive as dead
code either way — it is the second bespoke `accept-process-output`
poll loop in the package beside `gascity-formula-choices-wait`.

## Recommended (non-blocking)

### S2 — Four bead-id shape heuristics, three local (lisp/gascity-formula.el)

`gascity-sling--work-id-p` (line 423, `[a-z0-9]+-[a-z0-9]+`),
`gascity-sling--bead-prefix` (line 540, `[[:alnum:]]+-[[:alnum:]]+`),
and `gascity-sling--bead-id-regexp` (line 1290, the anchored beads.el
form) all answer "is this / what is the prefix of a bead id", each with
slightly different rules, and `gascity-beads--id-prefix`
(gascity-section.el:864) is a fourth that `gascity-action.el` already
uses for the same purpose. A new contributor cannot tell which to
reach for. Smallest fix: make `gascity-sling--bead-prefix` delegate to
`gascity-beads--id-prefix` (it already guards for non-ids), and have
`gascity-sling--work-id-p` note in one comment that it is the
deliberately narrower display rule (or just reuse the shared regexp).
Freeform text like `fix-thing` currently renders as "bead fix-thing" in
the header — harmless, but worth one sentence of comment where the
heuristic is defined.

### S3 — The rig-name-before-slash rule lives in three functions

`gascity-sling-formula--target-rig` (gascity-formula.el:1327),
`gascity-agents-scope`'s fallback, and `gascity-agents-roster-scope`'s
fallback (gascity-agents.el) all re-implement "scope = the substring
before the first `/`". Smallest fix: expose one helper in
gascity-agents (e.g. `gascity-agents-name-rig`) and call it from all
three — the scope classifier is exactly the contract the reviewers of
the bl-bdj trap will re-read.

### S4 — `gascity-sling-formula--var-key` recomputes the natural stage (lisp/gascity-formula.el:1099–1186)

`gascity-sling-formula--assign-var-keys` calls `--var-key` (which calls
`--var-key-natural` internally) and then calls `--var-key-natural`
*again* with the same `used` set to recover the natural/positional bit;
the positional branch inside `--var-key` filters the name's characters
a third time. It is correct today, but the two calls must stay
accidentally in sync. Smallest fix: have one internal function return
`(KEY . NATURAL-P)` and derive both `--var-key` and the assignment from
it. The `(nth 1 a)`/`(nth 2 a)` indexing over the assignment triples in
`--var-infix-assignments`/`--var-children` would also read easier as a
plist or `cl-destructuring`.

### S5 — The `:work`/`:arg` fallback is inlined five times

`(or (plist-get scope :work) (plist-get scope :arg))` appears in
`gascity-sling--work` (gascity-action.el:1232 — the helper!),
`gascity-sling--footer`, `gascity-sling--scope-info`, and in
`gascity-sling-formula--var-seed` and `--rig-workdir`
(gascity-formula.el). Smallest fix: move `gascity-sling--work` to
gascity-formula.el (which loads first) and use it everywhere, so the
`:work`-generalizes-`:arg` transition has exactly one definition to
delete later.

### S6 — Small cosmetics

- `gascity-sling--footer`'s `(pcase … (_ "run"))` catch-all is
  unreachable (`--shape` returns only plain/formula/on) — drop it or
  narrow the pcase.
- `gascity-sling--run`'s formula branch wraps a single form in `(progn
  …)` — remove the wrapper.
- `gascity-sling--footer--target-word` returning the bare word
  `rig-scoped` (no rig name) while the header sentence shows the real
  name is intentional per the docstring, but a one-line cross-reference
  between the two functions would save the next reader the detour.

### S7 — Merge-scaffolding comments can now be trimmed

Comments written while the work items lived in separate worktrees —
e.g. the `defvar gascity-sling--missing-target-warning` predeclaration
in gascity-action.el:1665 (the authoritative `defconst` is in
gascity-formula.el:626, which loads first) and the "while the work
items land as their own commits" paragraph in the declare-function
block (gascity-action.el:75–97) — describe a merge state that no longer
exists. Smallest fix: delete the defvar (the defconst is visible at
compile time now) and tighten the declaration comment to the ordinary
cross-file wiring note the file's other declarations use.

## Non-findings (checked, fine for this lane)

- Footer/preview recomputation stays off the gc path (`store-peek` /
  `store-get` only); the D9 rule holds on the redraw path.
- `gascity-sling--footer--vars-word` counts only non-blank values
  (`--current-values` filters), so "N of M vars set" is honest.
- The `…  (N more vars)` overflow subgroup keeps the deterministic key
  contract intact and is test-pinned.
- The remembered-state/target-memory split (menu state cleared on
  launch, memory surviving) is documented and reset in the shared test
  helper — a clean pattern.
- The documentation commit (`f21af52`) adds only a Texinfo pointer plus
  images; no doc/code drift in scope for this lane.

## Cross-lane notes

- The WI-11 QA report (`docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`,
  F1–F8) already records the behavior-level findings (read aborts close
  the menu, TRAMP path values, `*_target` seeds ignoring the Who
  default, `C-u S` escape) — not repeated here.
- S1 also touches REQ-005 conformance (the annotated Who candidates the
  plan promised are never shown to the user); the design-adherence lane
  may want to weigh in on the wire-or-remove decision.
