---
schema: gc.build.review.v1
workflow:
  id: ga-eavt
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic-review
  stage: review
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-eavt
      hash: bead:ga-eavt
    - path: beads/ga-04j2
      hash: bead:ga-04j2
    - path: beads/ga-3wpi
      hash: bead:ga-3wpi
      ids:
        - REQ-014
    - path: beads/ga-1wl7
      hash: bead:ga-1wl7
      ids:
        - REQ-015
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
        - REQ-015
    - path: plans/sling-command/implementation-summary.md
      hash: sha256:9db790253d31f6ab9a4f2434bbc644ca46170aad54da5f0efabe57b63317297f
    - path: plans/sling-command/build/review-context.md
      hash: sha256:9afa939af24b4aaa27f664df4ce6183b76045f63cd027db75a8c29dbeb98a6cf
    - path: plans/sling-command/build/starter-review-synthesis.md
      hash: sha256:6df3d15b0be14ba06f24578c6963c0cfe85ad47989aa589eed2e9f94bfa54759
    - path: plans/sling-command/build/review-fix-ga-odro.md
      hash: sha256:1a9da252ce3e3533de4bf083451a3297312920ffadc6c75290f9cc3a6319c0be
    - path: plans/sling-command/build/acceptance-review-ga-qigo.md
      hash: sha256:2e0a385a36658c8f7f1cd7ddc0aa96417bb085e4e54fc6acde058d59fa89b4ff
    - path: plans/sling-command/build/test-evidence-report.md
      hash: sha256:8fda9d05452fad791c9bbcf28c44e2a93f9a1a6638db5fe1b43f4071ab56c29d
    - path: plans/sling-command/build/simplicity-review.md
      hash: sha256:a4b5146ca94c28821b03d2b55942999997d491bd64ace40e82d3ba0a69bb0965
    - path: worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md
      hash: sha256:afcad6e5996d2d5ba634cd8c90a0e54e9625922fd34783e2b067c6ec702dc7f5
  coverage:
    - id: REQ-001
      status: covered
      rationale: One adaptive `gascity-sling-dispatch` transient covers plain, --formula and --on; the staged layout landed in worktrees/ga-3wpi commit cdc5af2 (review ga-odro R1, superseding the mislabeled 83c5367 record).
    - id: REQ-002
      status: covered
      rationale: Shape inferred from work + formula selections and rendered as the one-sentence header; no shape flag (WI-1, commit 8fc52c0).
    - id: REQ-003
      status: covered
      rationale: "`A` work picker over open beads and convoys with `title · status · store` annotations, `C-u` freeform escape; landed in ga-3wpi cdc5af2 (review R1)."
    - id: REQ-004
      status: covered
      rationale: Formula picker over catalog ∪ `gc formula list`; --on vs --formula follows work-in-scope (WI-4).
    - id: REQ-005
      status: covered
      rationale: Annotated agent roster wired into the Who picker with derived default (review R3, cdc5af2); one roster builder feeds picker and footer.
    - id: REQ-006
      status: covered
      rationale: Typed readers per var class with numeric validation (WI-5, commit 2f83f30).
    - id: REQ-007
      status: covered
      rationale: Live one-sentence footer recomputed per answer with ✓/⚠ status (WI-6, commit 80c35dd).
    - id: REQ-008
      status: covered
      rationale: "`P` full preview buffer merged into the reviewed implementation (review R2, merge 4c04b97); never gates `s`."
    - id: REQ-009
      status: covered
      rationale: "`s` dispatches and offers a follow jump to the run view; launch target remembered per (city, formula) (WI-8)."
    - id: REQ-010
      status: covered
      rationale: Client-side validators warn on the bl-bdj trap and cross-store refusals in the footer before launch; gc stays the authority (WI-2, WI-6).
    - id: REQ-011
      status: covered
      rationale: Mockup §10 menu with reserved-key set `A f T c a n m t s P r g x q` verified in the reviewed tree (review R1, cdc5af2).
    - id: REQ-012
      status: covered
      rationale: State and memory preserved across the redesign (WI-9, commit af56c49).
    - id: REQ-013
      status: covered
      rationale: Ported suite merged and reconciled (review R2, merge 83b6934); 735/735 green in worktrees/ga-3wpi at cdc5af2.
    - id: REQ-014
      status: covered
      rationale: Four-scenario live e2e pass over plain-ssh TRAMP against bright-lights through scripts/e2e-harness.sh (WI-11 report, gate green; re-verified in the fix pass with the redesign tests unskipped).
    - id: REQ-015
      status: covered
      rationale: Texinfo Sling Command chapter present in worktrees/ga-1wl7 (WI-12, f21af52); merging it into the reviewed tree is finalize-stage work per the synthesis checklist.

---

# Starter Review Report: Sling command redesign (workflow ga-eavt)

Finalized starter review for the build-basic implementation review loop
(ga-r8k2 → synthesis ga-budi → fix pass ga-odro → this report). Subject:
the implementation source anchor `worktrees/ga-3wpi` at commit `cdc5af2`
(merging e44dcf0d plus review fixes R1–R3 and the WI-7/WI-10 merges),
with documentation worktree `worktrees/ga-1wl7` at `f21af52` deferred to
the finalize stage exactly as the synthesis ordered. The launcher rig
root remaining unmutated is expected; root propagation is handled by
publish and is not a review failure.

## Verdict

**Approved.** The reviewed implementation anchor satisfies the workflow
requirements: the staged mockup layout, the `A` work picker, the merged
`P` full preview, and the annotated roster-backed Who picker are all
present in the reviewed tree, the whole-package gate is green there
(`eldev compile --warnings-as-errors` clean, `eldev test` 735/735, the
12 redesign tests un-skipped and passing), and the recorded four-scenario
live e2e pass over TRAMP stands as same-day evidence for AC-1…AC-12.

| ID      | Status  |
|---------|---------|
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-014 | covered |
| REQ-015 | covered |

## Findings

Recorded follow-ups that do not block approval of the reviewed anchor:

- **F-A (AC-13 screenshots, finalize-stage)** — the seven
  `doc/images/sling-*.png` remain mockup renderings; the fix lane
  deferred the ga-1wl7 screenshot merge to the finalize stage per the
  synthesis checklist ("and ga-1wl7 at finalize"). The finalize stage
  must merge ga-1wl7 or record the fallback acceptance decision.
- **F-B (queued e2e product defects)** — WI-11 findings F1–F6 and F9
  remain queued as follow-up polish (the fix lane addressed F7 via the
  R1 work picker); they are recorded for post-approval fix loops and do
  not retract the recorded four-scenario pass evidence for REQ-014.
- **F-C (roster deviation, documented)** — the S1 single-list rule is
  satisfied for picker and footer via `gascity-agents--roster`; the Who
  derivation keeps its config-only snapshot with test-pinned behavior,
  as documented in the fix report.
- **Residual risks** — simplicity S2–S7 and acceptance M-1/M-2 remain
  recorded as non-blocking cleanups.

## Verification

- Whole-package gate on the reviewed anchor: `eldev compile
  --warnings-as-errors` clean; `eldev test` 735/735 green, 0 unexpected,
  in `worktrees/ga-3wpi` at `cdc5af2` (review-fix ga-odro proof section).
- Review-lane verification: acceptance, test-evidence and simplicity
  lanes reproduced the gate (723/723 at review time) and `make -C doc`
  in `worktrees/ga-1wl7`; AC-1…AC-12 evidence verified, AC-13 tracked as
  finding F-A above.
- Live e2e: the recorded four-scenario pass against
  `/home/roman/bright-lights` over TRAMP
  (`worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`) is
  trusted as same-day evidence per the synthesis.
- Provenance: the mislabeled WI-4 commit record (83c5367) was corrected
  in `plans/sling-command/task-ga-f7a4-summary.md` and the canonical
  implementation summary; the staged layout is pinned to cdc5af2.
