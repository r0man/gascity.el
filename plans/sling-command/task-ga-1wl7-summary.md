---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-2xq5
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
    - path: beads/ga-1wl7
      hash: bead:ga-1wl7
      ids:
        - ga-1wl7
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: doc/gascity.texi
      hash: git:f21af52c46c23c529c6e29a733b0dcb6467febf6
    - path: docs/DESIGN-write-actions.md
      hash: git:f21af52c46c23c529c6e29a733b0dcb6467febf6
  coverage:
    - id: ga-1wl7
      status: covered
      rationale: >-
        WI-12 (bead ga-1wl7, REQ-015) is delivered in full: a complete
        "The Sling Command" chapter in doc/gascity.texi at the
        PostgreSQL-documentation bar covering the unified flow, every
        shape, the three pickers, the typed readers, the validation
        warnings, the P preview buffer, the follow offer and the key
        summary; the "Dispatch and lifecycle" Sling item is now a
        pointer; DESIGN-write-actions.md §10's unified-sling subsection
        describes the redesign; `make -C doc` builds clean and the
        sling states are wired under doc/images/ (mockup renderings
        per the documented fallback, real captures to follow from the
        verification pass).
---

# Implementation Summary — Sling command documentation (WI-12, ga-1wl7)

Coverage:

| ID | Status |
| --- | --- |
| ga-1wl7 | covered |

## Summary

The documentation item of the sling command redesign is implemented
in the worktree commit f21af52 (`docs(sling): the Sling Command
chapter, §10 redesign, mockup shots (ga-1wl7)`): a new
`The Sling Command` chapter in `doc/gascity.texi` (13 nodes — the
chapter plus twelve sections) documenting every requirement behavior
from REQ-001 through REQ-012 at the plan's quality bar, the rewritten
`Unified sling transient` subsection of
`docs/DESIGN-write-actions.md` §10 matching the staged adaptive
redesign, and seven sling state images wired into the manual with the
existing `@shot` machinery.

## Intended Behavior

- `S` from any view opens one unified adaptive transient whose
  conceptual flow is What → Who → How → Preview → Launch → Follow;
  a fully pre-seeded plain dispatch is `S` then `s` with zero prompts
  (REQ-001, documented in the chapter intro and "The sling menu").
- The shape (plain / `--formula` / `--on`) is inferred from the work
  and formula selections and stated as one sentence in the header —
  never a flag, never a toggle (REQ-002, "The sling shapes").
- `A` picks annotated open beads and convoys with the freeform escapes
  (`C-u A`, empty-RET); `f` picks from the annotated catalog union
  (REQ-003, REQ-004, "Picking work" and "Picking a formula").
- `T` completes over rig-grouped agents with scope and live state; the
  default derives from rig `default_sling_target`, per-(city, formula)
  target memory, then the implementation-worker convention, tagged
  `derived`, and `s` never re-prompts when derivable (REQ-005,
  "Picking the target").
- Every declared formula var reads with a typed reader — file,
  directory (seeded `plans/<title-slug>/`), agent, numeric,
  restricted choice, bool, fail-soft string — with deterministic keys
  outside the reserved set and per-(formula, var) history (REQ-006,
  "Typed variables").
- The live footer always shows the launch summary and ✓/⚠ validation
  status, recomputed on change, from cached data only (REQ-007, "The
  live footer").
- `P` opens the full preview — validation, recipe DAG, dry-run
  routing plan — with launch available in the buffer and never gating
  `s`; `r` keeps the server-substituted recipe preview (REQ-008, "The
  preview buffer").
- Launch is asynchronous; a formula launch echoes the created workflow
  with a momentary `F` follow offer jumping to the run view; plain
  routes keep the plain echo (REQ-009, "Launch and follow").
- The bl-bdj formulas-v2 trap and cross-store routes warn in the
  footer before launch, never blocking (REQ-010, "Validation
  warnings").
- The layout matches the signed-off mockups — stages as stacked
  groups, collapsed answered stages, plain-only routing flags, the
  reserved set `A f T c a n m t s P r g x q` with `p` freed —
  documented in "The sling menu" and "Sling key summary" (REQ-011).
- History, target memory, remembered menu state and city pinning are
  documented as preserved behavior (REQ-012, "Remembered state").
- Documentation is part of acceptance, not an afterthought: the QA
  report `docs/qa/2026-09-27-sling-wi12-documentation.md` records the
  build evidence and the screenshot fallback (REQ-015).

## Changed Files

- `doc/gascity.texi` — the new chapter (Top menu entry, twelve
  sections, thirteen nodes), the "Dispatch and lifecycle" Sling item
  reduced to a pointer.
- `docs/DESIGN-write-actions.md` — §10 "Unified sling transient"
  subsection rewritten to the staged adaptive redesign.
- `docs/qa/2026-09-27-sling-wi12-documentation.md` — the WI-12 QA
  report.
- `doc/images/sling-{plain,cold,formula,on,trap,preview,follow}.png`
  and their `-thumb` pairs — the seven documented sling states.

## Verification

- First verification command: `make -C doc` (from the worktree root) —
  makeinfo Info plus styled multi-page HTML, **pass**: builds with no
  node, menu or cross-reference warnings; the chapter's nodes render
  in both outputs and the sling images are copied into the HTML tree.
- Final proof command: `./scripts/gate.sh` (byte-compile
  `--warnings-as-errors` plus the full ERT suite) — **pass on the
  docs-only change**: the first run reported 665/666 with one
  unexpected result (`gascity-test-agent-detail-follow-log-stderr-
  goes-with-it`, a timing-flaky test unrelated to documentation, under
  the heavy parallel load of the sibling drain worktrees), and the
  immediate re-run of the same command in the same worktree reported
  **666/666, 0 unexpected**.

## Remaining Risks

- All seven sling images are **mockup renderings** of the signed-off
  menu mockups, not live captures: under the separate-context drain the
  redesigned transient exists only in the parallel items' worktrees, so
  no live session of this item's base contains the new UI. This is the
  requirements' documented fallback (Open Question, "Screenshot
  capture of momentary states"); the live verification pass (WI-11)
  replaces the files under the same names with real captures, and the
  `@shot` wiring needs no change. Noted in the QA report.
- The chapter documents the approved design (design.md, menu-mockups.md,
  2026-09-27) rather than this worktree's pre-redesign code — inherent
  to a parallel drain; the WI-11 verification pass walks each mockup
  state against the merged implementation and records deviations in
  its own QA report.
