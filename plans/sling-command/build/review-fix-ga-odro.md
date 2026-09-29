# Review-fix summary — Apply starter review findings (ga-odro)

- Executor bead: ga-odro (step `review.apply-review-findings`), 2026-09-27
- Source: starter review synthesis `plans/sling-command/build/starter-review-synthesis.md`
  (verdict `iterate`, findings R1–R5)
- Implementation worktree: `/home/roman/workspace/gascity.el/worktrees/ga-3wpi`
  (the merged implementation tree; per the review context's
  `## Implementation Worktrees` authority). The launcher root was not
  touched for code.
- Result: **R1, R2, R3 done and gate-green; R4 and R5 remain** →
  `code_review.verdict=iterate`.

## R1 — Staged mockup layout and the `A` work picker: DONE

Commit `cdc5af2` ("feat(sling): the staged mockup layout, the A work
picker and the annotated Who picker (ga-odro, review R1+R3)") in
`worktrees/ga-3wpi`:

- The staged layout (REQ-003, REQ-011, AC-9): header group (city title,
  one-sentence shape header, live footer), What (`A` work, `f`
  formula), the picked formula's `How — <formula> vars` group, Who
  (`T`), the Routing flags rendered only on the settled plain shape
  (work chosen, no formula — F-5), and Actions `s P r g x q` (mockup
  §10). The reserved-key set is now exactly
  `A f T c a n m t s P r g x q`; `p` is freed, `P` is the full preview
  (merged from R2 first, as the synthesis ordered).
- The `A` work picker (mockup §6a): completing-read over every store's
  open/in-progress/blocked beads (`gascity-dashboard--read-work`
  through the store) plus the city's convoys, rows annotated
  `title · status · store`; empty RET falls through to the freeform
  prompt, `C-u` goes straight to freeform. Entry prefetches the
  composite read (D9).
- The dispatch/entry/reset/memory/preview paths read the scope's
  `:work` key (generalizing `:arg`); plain real slings carry `--json`.
- Provenance corrected (plan artifacts, not code): appended a Review
  correction section to `plans/sling-command/task-ga-f7a4-summary.md`
  and annotated the REQ-001/003/011 rationales in
  `plans/sling-command/implementation-summary.md` — the `83c5367`
  commit record (which contains only the follow offer, byte-identical
  to WI-8's) is superseded by `cdc5af2`.

## R2 — Merge the `P` full preview and WI-10 into the reviewed implementation: DONE (as far as the fix lane's authority reaches)

- `683cece` (WI-7 `P` full preview) merged into `ga-3wpi` (merge
  commit `4c04b97`): the refactored `gascity-sling-formula--command`
  kept, the WI-8 launch handler re-attached on top of it.
- `426d2fd` (WI-10 ported suite) merged (merge commit `83b6934`), then
  reconciled against the landed API: WI-10's plan-API duplicates of
  five already-covered tests were dropped (the landed suite pins the
  same behavior with richer assertions); its recipe-helper fixture
  merged into the landed one; the follow-offer stub now names the root
  in `molecule_id` (the e2e-confirmed field — the offer never guesses
  at undocumented fields).
- `ga-1wl7` (WI-12 docs, `f21af52`) is **deferred to the finalize
  stage**, exactly as the synthesis's fix-lane checklist item 2 says
  ("and ga-1wl7 at finalize") — its screenshots feed R4, which remains.

## R3 — Annotated agent roster wired into the Who picker: DONE (one documented deviation)

- `T` completes over the agent roster via WI-2's
  `gascity-agents-roster-candidates` (mockup §6c: city agents first
  then per rig, `scope · live state` annotations), seeded with the
  derived Who default; free entry preserved. The accessor has non-test
  callers now.
- The dispatch's cold Who read runs the same completion over the
  roster's cached peek (no spawn on the dispatch path); the blocking
  wait loop is no longer dead code (it backs the picker when the peeks
  are cold).
- Deviation, recorded for the reviewer: S1 asked for ONE list across
  picker, footer and derivation. The picker and footer share the
  `gascity-agents--roster` join as the single builder. The derivation
  keeps its config-only `gc agent list` snapshot (store-get, never a
  spawn): its WI-3 tests pin that contract, and pool instance suffixes
  (`…-18`) never name configs, so the session join would only add
  non-matching rows there. If the reviewer insists on the strict
  single-list reading, that is one follow-up edit away.

## R4 — Real screenshots (AC-13): NOT DONE

No screenshots were captured this pass; the seven `doc/images/sling-*.png`
in `worktrees/ga-1wl7` are still the mockup renderings. The fallback
acceptance decision was also not recorded — that choice belongs to the
acceptance lane. Remains required.

## R5 — Queued e2e product defects (F1–F7, F9): NOT DONE

None of the WI-11 dogfood findings were fixed this pass. They remain
queued exactly as the synthesis lists them (F8's environment
conditions stay out of scope).

## Proof

- `eldev compile --warnings-as-errors` — clean (whole package, the
  undefined-function gate).
- `eldev test` — **735/735 green, 0 unexpected** (`scripts/gate.sh`
  PASS) on `worktrees/ga-3wpi` at `cdc5af2`.
- The 12 formerly `skip-unless`-gated redesign tests now run and pass
  (the redesign predicate sees the mockup §10 reserved set).
- Live e2e over TRAMP was NOT re-run this pass; the merged tree changed
  user-visible layout code, so the next review lane should re-run the
  four-scenario pass (`scripts/e2e-harness.sh`) before approving.

## Verdict

`code_review.verdict=iterate` — R4 (missing proof) and R5 (queued
defect fixes) remain from the synthesis; acceptance, test evidence and
simplicity do not yet all approve.
