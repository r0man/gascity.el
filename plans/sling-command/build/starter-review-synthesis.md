# Starter Review Synthesis — Sling command redesign (workflow ga-eavt)

- Synthesizer bead: ga-budi (step `review.synthesize-review`), 2026-09-27
- Source lanes: acceptance review (ga-qigo, `build/acceptance-review-ga-qigo.md`,
  verdict `iterate`), test evidence review (ga-jl7b, `build/test-evidence-report.md`,
  verdict `iterate`), simplicity review (ga-loxl, `build/simplicity-review.md`,
  verdict `iterate`)
- Subject: implementation commit e44dcf0d in worktree `worktrees/ga-3wpi`
  (merged item worktree ga-3wpi) + documentation commit f21af52 in
  `worktrees/ga-1wl7`; context `plans/sling-command/build/review-context.md`

**Combined verdict: iterate.** The gate is green (723/723, re-run independently
by two lanes) and the landed half of the redesign is well-tested and
live-verified, but three of the redesign's most user-visible requirements are
absent from the reviewed implementation, the WI-4 provenance mislabels what
landed, and one acceptance-criterion proof (real screenshots) was never
produced. One iteration of fixes is required before the review loop can
approve.

## How to read this

Every finding keeps its source lane tag (`[acceptance]`, `[test-evidence]`,
`[simplicity]`). Duplicates across lanes are merged into one item listing all
sources. Each item names the implementation worktree that owns the files —
never the launcher root (`work_dir` is the launcher rig root, not the code
under review).

## Required fixes

### R1 — Implement the staged mockup layout and the `A` work picker (REQ-003, REQ-011, AC-9)
Sources: [acceptance] F-1, F-2; [simplicity] S1 cross-ref; [test-evidence] T-3 (F7)
Owner: merged implementation worktree `/home/roman/workspace/gascity.el/worktrees/ga-3wpi` (`lisp/gascity-action.el`, `lisp/gascity-formula.el`)

The merged tree still renders the **old** transient layout: groups are
`Formula` / `Destination` / `Routing flags` / `Actions`, routing flags render
unconditionally, there is no What/Who/How staging, and the reserved-key set is
still `f g T A c a n m t s p r x q` (`p` not freed, `P` absent) instead of the
mockup §10 set `A f T c a n m t s P r g x q`. `A` is still plain
`gascity-sling-dispatch-arg` (`read-string "Bead id or task text: "`); the
smart work picker over open beads + convoys with `title · status · store`
annotations and the `C-u` freeform escape (mockup §6a, also e2e finding F7)
does not exist in any sling commit. Additionally, WI-4's commit (`83c5367` in
`worktrees/ga-f7a4`) and task summary (`plans/sling-command/task-ga-f7a4-summary.md`)
claim the staged layout, work picker, and mockup-state tests — none exist in
any commit; the commit contains only the follow-offer code (byte-identical to
WI-8's). Correct the WI-4 summary/commit record and the
implementation-summary coverage rationale that inherited it (REQ-001/003/011
traces are currently wrong).

### R2 — Merge the `P` full preview (and unmerged WI-10/WI-12) into the reviewed implementation (REQ-008, AC-6)
Sources: [acceptance] F-3
Owner: `worktrees/ga-ub2r` (merge into the merged tree, reconciled with R1's reserved-key change); `worktrees/ga-gonl`; `worktrees/ga-1wl7`

`gascity-sling-dispatch-full-preview` exists only in `worktrees/ga-ub2r` @
`683cece`, which is not merged into the recorded implementation e44dcf0d. The
merged tree's preview is still the `p` dry-run text view. WI-10 (ga-gonl
`426d2fd`, conditional tests) and WI-12 (ga-1wl7 `f21af52`) are likewise
unmerged. The finalize stage must actually merge ga-ub2r/ga-gonl/ga-1wl7 or
REQ-008 and the corresponding acceptance criteria stay unmet on `main`.

### R3 — Wire the annotated agent roster into the Who picker (REQ-005)
Sources: [acceptance] F-4; [simplicity] S1
Owner: merged implementation worktree `worktrees/ga-3wpi` (`lisp/gascity-action.el`, `lisp/gascity-agents.el`)

The `T` picker still completes over unannotated session aliases via
`gascity-action--read-session`. The WI-2 roster accessor
(`gascity-agents-roster` / `-candidates` / `-scope`, tested in
`lisp/test/gascity-agents-test.el`) has zero non-test callers. Wire the roster
candidates into `gascity-sling-dispatch-target` (annotated, grouped by rig
with scope and live state, `derived` tag). Simplicity lane addition: today
there are **three** roster builders (the unwired accessor, `--roster` for the
Who default, `--roster-cached` for the footer) answering from different data —
make one source feed the whole Who surface (keep `gascity-agents--roster` as
the single builder; derivation and footer must read the same list), and do not
keep the blocking `accept-process-output` wait loop as dead code.

### R4 — Produce the missing AC-13 screenshot proof (AC-13)
Sources: [test-evidence] T-2
Owner: `worktrees/ga-1wl7` / merged tree (`doc/images/`)

AC-13 requires real screenshots from the live session; all seven wired
`doc/images/sling-*.png` are mockup renderings (WI-12 could not run the
transient; the promised WI-11 replacement never happened). Fix-lane action:
capture the seven transient states from a GUI Emacs session against the merged
implementation and replace the images under the same names — or record an
explicit acceptance decision that the mockup renderings stand in.

### R5 — Fix the e2e product defects already queued (REQ-014 follow-through)
Sources: [acceptance] M-3 / F-3-item; [test-evidence] T-3
Owner: merged implementation worktree `worktrees/ga-3wpi` (`lisp/gascity-action.el`, `lisp/gascity-formula.el`)

The WI-11 dogfood report's own findings are real product defects awaiting the
fix loop: F1 (read abort closes the transient), F2 (var answers set after the
last re-setup lost on reopen), F3 (TRAMP-prefixed path vars gc cannot consume
— the most consequential), F4 (rig memo misses HQ rig from status-only
seeding), F5 (`*_target` var seeds ignore the Who default), F6
(`artifact_root` slug does not re-seed on `A`-set work), F7 (`C-u S` freeform
escape — overlaps R1), F9 (formula path never nudges a sleeping agent). F8
items are pre-existing environment conditions, out of scope.

## Missing evidence (fix lane must produce proof, not code)

- **AC-13 screenshots** — see R4 (the only missing-proof item; AC-1…AC-12
  evidence verified/reproduced: gate 723/723 re-run green in `worktrees/ga-3wpi`,
  `make -C doc` reproduced in `worktrees/ga-1wl7`).
- [test-evidence] T-1 (no action): WI-1/WI-6/WI-9 lack per-item summary files;
  the canonical implementation summary covers them collectively. Recorded as a
  structure note only.

## Residual risks (record; fix opportunistically)

- [simplicity] **S2–S7** — one-way-to-do-it cleanups, non-blocking: bead-id
  shape heuristics ×4 (S2), rig-name-before-slash rule ×3 (S3),
  `--var-key` recomputing the natural stage (S4), `:work`/`:arg` fallback
  inlined ×5 (S5), small cosmetics (S6), stale merge-scaffolding comments (S7).
- [acceptance] **M-1** — `gascity-sling--missing-target-warning` defined twice
  (`defvar` in action, `defconst` in formula; survives only on load order).
  Overlaps simplicity S7's defvar finding — one deletion covers both.
- [acceptance] **M-2** — doc drift: "23 of 38" vs e2e's 24 steps.
- [test-evidence] e2e findings not re-run live by the review lanes; the
  recorded four-scenario pass is trusted as same-day evidence (AC-12).

## Fix-lane checklist (smallest path to approve)

1. R1: implement staged layout + work picker in `worktrees/ga-3wpi`; correct
   the WI-4 summary/commit record.
2. R2: merge ga-ub2r and ga-gonl (and ga-1wl7 at finalize) into the merged tree.
3. R3: single roster source behind the annotated `T` picker.
4. R4: capture real screenshots from a GUI session (or record the fallback
   acceptance decision).
5. R5: fix the queued e2e defects F1–F7, F9 with regression tests.
6. Re-run `scripts/gate.sh` on the merged tree after each fix.
