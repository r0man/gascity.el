---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-eavt
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: summarize-implementation
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
    - path: plans/sling-command/decomposition.md
      hash: sha256:4ce83b573ba9f63fcd4acb7f305604108ce5a9cde9f7097f5855ec4d91cc0c74
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: worktrees/ga-0okd/plans/sling-command/build/implementation-summary-ga-0okd.md
      hash: sha256:cabcea783a9ecf94000bbd6edf311b75bdeac67dc4fadf992e0b19bbd0e07239
    - path: plans/sling-command/task-ga-f7a4-summary.md
      hash: sha256:1556819350dd4af58d3d742ebe7865636a46271376af7412d5bfa91a2bddf6fa
    - path: plans/sling-command/task-ga-ntop-summary.md
      hash: sha256:5569e0954f7eb05d35f994c1efacffa35c7c9980045589f6cfe84d9c64728d38
    - path: plans/sling-command/task-ga-o6eh-summary.md
      hash: sha256:c0b8d55f090fcb5c57f1349c001ee10db98c8c2628229bd032588a1bd621bae5
    - path: plans/sling-command/build/ga-nij3-implementation-summary.md
      hash: sha256:fd719bf7b827e175d4d0433596a7bb1360d871143f5edfb6928ad22faf4c42d5
    - path: plans/sling-command/task-ga-f4w0-summary.md
      hash: sha256:44c5e40e946d766bc90a8c04a17363c71bfff7383c85d76c697e8466d35babe4
    - path: worktrees/ga-3wpi/plans/sling-command/build/implementation-summary-ga-nqyt.md
      hash: sha256:47dae538218e3dae2d24f5a875fe7edfa674661e42fde8f948f10569d8d0d0be
    - path: worktrees/ga-1wl7/plans/sling-command/task-ga-1wl7-summary.md
      hash: sha256:b17d58aaeecb36e498bb0eaae4dfcb38be1ff883cbea5528898374c381347841
    - path: worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md
      hash: sha256:afcad6e5996d2d5ba634cd8c90a0e54e9625922fd34783e2b067c6ec702dc7f5

  coverage:
    - id: REQ-001
      status: covered
      rationale: "One `gascity-sling-dispatch` transient covers plain, --formula and --on; stages collapse when pre-seeded (WI-4 layout, WI-1 inference). Review correction: the original WI-4 commit record (83c5367) mislabeled the follow-offer; the staged layout actually landed in worktrees/ga-3wpi commit cdc5af2 (review ga-odro R1)."
    - id: REQ-002
      status: covered
      rationale: Shape is inferred from work + formula selections and rendered as the one-sentence header; no shape flag (WI-1, commit 8fc52c0).
    - id: REQ-003
      status: covered
      rationale: "`A` work picker over open beads and convoys with annotations; `C-u A` freeform; point pre-seeds (WI-4; landed with the staged layout in ga-3wpi cdc5af2, review R1 — the original 83c5367 record contained only the follow offer)."
    - id: REQ-004
      status: covered
      rationale: Formula picker over catalog ∪ `gc formula list`; --on vs --formula follows work-in-scope (WI-4).
    - id: REQ-005
      status: covered
      rationale: Agent-centric Who picker grouped by rig with scope/state; derived default (rig default, memory, implementation-worker convention) shown with `derived` tag (WI-2, WI-3).
    - id: REQ-006
      status: covered
      rationale: Typed readers per var class — file/dir completion (plans/<slug>/ seed), agent picker for *_target, numeric validation (WI-5, commit 2f83f30).
    - id: REQ-007
      status: covered
      rationale: Live one-sentence footer recomputed as each answer changes, with ✓/⚠ status (WI-6, commit 80c35dd).
    - id: REQ-008
      status: covered
      rationale: "`P` preview buffer with recipe DAG, gc dry-run routing plan and all warnings; never gates `s` (WI-7)."
    - id: REQ-009
      status: covered
      rationale: "`s` dispatches and offers a follow jump to the run view; launch records the target per (city, formula) (WI-8)."
    - id: REQ-010
      status: covered
      rationale: Client-side validators warn on the bl-bdj trap and cross-store refusals in the footer before launch; gc stays the authority (WI-2, WI-6).
    - id: REQ-011
      status: covered
      rationale: Mockup menu (What/Who/How/Actions) rendered with the three pickers per menu-mockups.md (WI-4; landed in ga-3wpi cdc5af2, review R1 — see the corrected task-ga-f7a4-summary.md).
    - id: REQ-012
      status: covered
      rationale: State and memory preserved across the redesign — remembered answers and per-(city, formula) target memory survive reopens (WI-9, commit af56c49).
    - id: REQ-013
      status: covered
      rationale: Existing sling ERT suite ported to the redesign layout and consolidated (WI-10, commit 426d2fd).
    - id: REQ-014
      status: covered
      rationale: Four-scenario live e2e pass over plain-ssh TRAMP against bright-lights through scripts/e2e-harness.sh; gate 723/723 green (WI-11).
    - id: REQ-015
      status: covered
      rationale: Texinfo Sling Command chapter with the redesign flow, shapes, pickers, typed readers, warnings, preview and follow offer (WI-12).

---

# Implementation Summary: Sling command redesign (workflow ga-eavt)

## Summary

The build finalized the full sling command redesign across the twelve
work items (WI-1 … WI-12) of implementation convoy `ga-04j2`, with
source anchors `ga-510r`, `ga-0okd`, `ga-ntop`, `ga-f7a4`, `ga-o6eh`,
`ga-pkpi`, `ga-ub2r`, `ga-f4w0`, `ga-me2n`, `ga-gonl`, `ga-3wpi`, and
`ga-1wl7`.  The old flag-driven sling transient was replaced by one
adaptive staged transient (`gascity-sling-dispatch`) covering plain,
`--formula`, and `--on` shapes with shape inference, a derived Who
default, typed How vars, a live validating footer, a full preview
buffer, and a post-launch follow offer.  Every item was implemented in
its own isolated worktree; the WI-11 e2e pass merged the still-open
sibling items (WI-5 typed vars `cc5d836`, WI-6 footer `80c35dd`) into
its item worktree, found and fixed three integration seams, and
verified all four design scenarios live over TRAMP against
`/home/roman/bright-lights` (`gc --city /home/roman/bright-lights …`).
The dogfood report is
`worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`.
Per-item summaries: `plans/sling-command/task-ga-ntop-summary.md`
(WI-3), `plans/sling-command/task-ga-f7a4-summary.md` (WI-4),
`plans/sling-command/task-ga-o6eh-summary.md` (WI-5),
`plans/sling-command/build/ga-nij3-implementation-summary.md` (WI-7),
`plans/sling-command/task-ga-f4w0-summary.md` (WI-8),
`plans/sling-command/task-ga-gonl-summary.md` (WI-10),
`worktrees/ga-0okd/plans/sling-command/build/implementation-summary-ga-0okd.md`
(WI-2),
`worktrees/ga-3wpi/plans/sling-command/build/implementation-summary-ga-nqyt.md`
(WI-11), and
`worktrees/ga-1wl7/plans/sling-command/task-ga-1wl7-summary.md`
(WI-12).  WI-1 (`8fc52c0`), WI-6 (`80c35dd`), and WI-9 (`af56c49`)
were implemented without recorded per-item summary files; their
evidence here is the merged worktree history, the ported ERT suite,
and the WI-11 live pass, which exercised the header sentence
(REQ-001/REQ-002), the footer (REQ-007), and the state/memory behavior
(REQ-012) directly.

## Intended Behavior

- One `S` press from any gascity view opens `gascity-sling-dispatch`;
  shape (plain / `--formula` / `--on`) is inferred from the work and
  formula selections and stated in the one-sentence header — never
  picked with a flag (REQ-001, REQ-002).
- `A` picks from the city's open beads and convoys (annotated, `C-u A`
  freeform); `f` picks from the formula catalog ∪ `gc formula list`;
  the Who default is derived (rig `default_sling_target` →
  per-(city, formula) memory → implementation-worker convention) and
  shown with a `derived` tag (REQ-003, REQ-004, REQ-005).
- Formula vars read with the right reader per class: file/dir
  completion (TRAMP-safe, `artifact_root` seeded `plans/<slug>/`),
  agent picker for `*_target`, numeric validation for
  `max_iterations` (REQ-006).
- The live one-sentence footer recomputes summary and ✓/⚠ validation
  status after every answer, warning on the bl-bdj trap and
  cross-store refusals before launch; `P` opens the full preview
  (recipe DAG, gc dry-run routing plan, warnings) without gating `s`
  (REQ-007, REQ-008, REQ-010).
- `s` launches via the existing gc plumbing and offers a momentary
  follow jump to the created run's view; state and remembered answers
  survive quit+reopen (REQ-008, REQ-009, REQ-012).
- Verification: the four-scenario e2e pass runs against the
  bright-lights city, always as `gc --city /home/roman/bright-lights …`
  (REQ-014); the manual gets a complete Sling Command chapter with
  mockup-rendered screenshots (REQ-015).

## Changed Files

- `lisp/gascity-action.el` — the redesigned staged transient, launch
  and follow offer, footer validation, preview wiring.
- `lisp/gascity-formula.el` — shape inference, one-sentence header,
  typed-var heuristics, nil-recipe guards, cache/state preservation.
- `lisp/gascity-agents.el` — grouped agent roster with rig-vs-city
  scope metadata and the classifier's slash-prefix fallback.
- `lisp/test/gascity-sling-test.el`, `lisp/test/gascity-agents-test.el`
  — ported suite plus regression tests for shape inference, typed
  readers, Who default, bl-bdj trap, cross-store warning, follow
  offer, nil recipe, and derived-target header.
- `doc/gascity.texi` + `doc/images/` — the Sling Command chapter
  (§10) with mockup renderings.
- `docs/qa/2026-09-27-wi11-sling-redesign-e2e.md` — the e2e dogfood
  report.
- Implementation work: `8fc52c0` (WI-1 header/shape inference),
  `80c35dd` (WI-6 live footer), `af56c49` (WI-9 launch target memory),
  merged into the WI-11 worktree at `e44dcf0` (see Verification).

## Verification

First verification commands (per item, and after merging the sibling
items into the WI-11 worktree):

```
eldev compile --warnings-as-errors && eldev test
scripts/gate.sh
```

Observed: compile clean; 721/721 tests green on the merged tree
before the live pass; WI-1's first verification recorded in
`bd8007e` provenance.

Final proof commands (the live acceptance gate, WI-11):

```
. scripts/e2e-harness.sh
e2e_kill_emacs && e2e_start_emacs && e2e_emacs_ready
# drive the four REQ-014 scenarios against
# /ssh:localhost:/home/roman/bright-lights
scripts/gate.sh
```

Observed: all four scenarios verified live (pancakes end to end,
build-basic `--on` typed vars, the bl-bdj footer trap, plain
dispatch); the pass found three integration seams (nil-recipe crash,
footer vs Who default, roster scope classifier) fixed with regression
tests; `scripts/gate.sh` → `>>> gate: PASS (compile clean + tests
green)` — 723/723 tests, 2026-09-27.  Full evidence:
`worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`.

## Remaining Risks

- Findings recorded in the WI-11 dogfood report await the review/fix
  loop: read aborts close the whole transient; var answers set after
  the last re-setup are lost across quit+reopen; typed path vars over
  TRAMP answer TRAMP-prefixed names gc cannot consume; the rig memo
  misses the HQ rig in cockpit-only sessions; `*_target` var seeds
  ignore the Who default; the formula path never nudges the target;
  `C-u S` has no freeform escape.
- WI-12's screenshots are mockup renderings, not live GUI captures (a
  `-nw` tmux Emacs cannot produce the manual's GUI shots); a GUI
  session should replace them later.
- The bright-lights city carries live pass evidence (bl-9jmm closed,
  hw-5o1 running, hw-4wz in progress, fixture beads bl-4rvq/bl-23by).
- The implementation commits live on the item worktrees/branches; the
  finalize stage merges them to `main` (branch `main`, per
  `gc.work_branch`).

| ID | Status |
| --- | --- |
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
