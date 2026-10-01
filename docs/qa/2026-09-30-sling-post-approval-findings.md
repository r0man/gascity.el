# Sling post-approval fix lane — WI-11 findings F1–F6, F9

- Date: 2026-09-30
- Bead: `ga-x4nt` (sling redesign post-approval fix lane)
- Source findings: `plans/sling-command/review-report.md` (F-B) and
  `docs/qa/2026-09-27-wi11-sling-redesign-e2e.md` §Findings
- Baseline: main at `54a9fb4` (sling redesign merged, PR #1)
- Verification: `scripts/gate.sh` PASS (compile clean, 761/761) and
  `scripts/lint.sh` PASS on the fix tree

## Reproduced and fixed

| ID  | Finding | Fix | Test |
|-----|---------|-----|------|
| F1  | A refused (`user-error`) or aborted (`C-g`) infix read quits the whole menu | `gascity-sling-formula--read-guarded` wraps every generated infix read; a refusal/quitting read reports and keeps the current value | `gascity-test-sling-refused-read-survives` |
| F2  | Answers set after the last re-setup are lost across quit+reopen | The live footer's format-time function now snapshots the scope+args into `gascity-sling--remembered` on every redraw, so a late var edit is saved before the menu closes | `gascity-test-sling-footer-redraw-remembers-late-values` |
| F3  | Typed path vars over TRAMP return `/ssh:HOST:…` names gc cannot consume | File/directory reads pass the returned name through `file-local-name` | `gascity-test-sling-file-dir-reads-host-localize` |
| F4  | The rig memo misses the HQ rig in cockpit-only sessions (`gc status` omits HQ) | The cockpit now reads `gc rig list` through the store and seeds the memo from it (falling back to status until it lands) via `gascity-dashboard--remember-rigs` | `gascity-test-dashboard-remembers-full-rig-list` |
| F5  | `*_target`/`rig_name` var seeds ignore the derived Who default | Menu setup injects the derived default as `:derived-target`; `gascity-sling-formula--var-seed` reads it when `:target` is unset | `gascity-test-sling-var-seed-uses-derived-target`, `gascity-test-sling-children-specs-seed-derived-target` |
| F6b | An `A`-picked work does not re-seed `artifact_root` (only a bead at point does) | The work picker peeks the picked bead/convoy's title from its cached payload and carries it into the scope's `:work-title` | `gascity-test-sling-work-title-peeks-picker-payload`, `gascity-test-sling-work-picker-carries-title` |

## Not a gascity defect

- **F6a — `build-basic` declares no `rig_name` var.** There is nothing
  to derive for that half of the WI-11 scenario wording; it is a
  formula-schema observation, not a gascity.el defect.

## Decided design follow-up

- **F9 — the formula launch path never nudges the routed agent.**
  Routing flags are deliberately consumed only by the plain path
  (design F-5), so the formula shape exposes no `--nudge`. The finding
  offers two remedies (nudge on formula routing, or make the wait
  visible); the run view already surfaces an idle run in the cockpit's
  Needs-you, so the second is arguably satisfied. **Decision (ga-ls1hw):
  expose `--nudge` as an opt-in routing flag on the formula shape; do
  not nudge automatically.** The full rationale and the implementation
  sketch for the follow-up bead are in
  `plans/sling-command/f9-formula-nudge-decision.md`.
- **F9-adjacent — `-t/--title` on the formula shape.**  Same
  "documented but not carved out" class: `gc sling --help` documents
  `-t` for `--formula`/`--on` and the command layer models it, but
  only the plain shape renders and threads it. **Decision (`ga-ybtm3`):
  expose `-t/--title` as an opt-in formula-shape routing flag and keep
  the `artifact_root` seed independent of it.**  Rationale,
  interaction table and implementation sketch are in
  `plans/sling-command/formula-title-decision.md`.

## Notes

- F7 was already fixed by the `A` picker before this pass; F-A
  (screenshots) and F-C/§S2–S7/M-1–M-2 remain tracked elsewhere.
- Every fix is offline-tested through the existing gc-boundary stubs;
  the live TRAMP acceptance pass for these edits is the remaining
  verification step if a stricter gc path is desired.
