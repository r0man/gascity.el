---
schema: gc.build.decomposition.v1
workflow:
  id: ga-rv5
  formula: build-from-requirements
methodology:
  pack: gascity
  name: decomposition-base
producer:
  formula: build-from-decompose-base
  stage: decompose
  attempt: 1
status: approved
plan_slug: multi-city-keying
phase: decompose
rig: gascity.el
rig_root: /home/roman/workspace/gascity.el
interaction_mode: interactive
trace:
  upstream:
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved requirements the plan implements"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
      title: "Approved implementation plan decomposed into work items WI-1..WI-4"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
    - path: plans/multi-city-keying/build/plan-review.md
      hash: sha256:93a98b10c8667e12cc31967d4258da259135a204e967925f8d24303d8b7a0ca5
      title: "Approved plan-review verdict whose advisories are folded into the work items"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
    - path: lisp/gascity-remote.el
      hash: git:3fa83997ca1689e9023aaf57a31acf76743c5fa7
      title: "Buffer-naming module re-keyed by WI-2 (gascity-remote-buffer-name qualifier argument)"
    - path: lisp/gascity-context.el
      hash: git:cac32df3638547f32e7361ccdcf7f2cf1150aefb
      title: "Context module re-keyed by WI-1/WI-2 (scope-key helper, rigs memo, view factory)"
  coverage:
    - id: AC-1
      status: covered
    - id: AC-2
      status: covered
    - id: AC-3
      status: covered
    - id: AC-4
      status: covered
    - id: AC-5
      status: covered
---

# Decomposition: Per-city keying — multiple cities in one Emacs

## Summary

The approved plan (Steps 1–8) decomposes into **four runnable implementation
work items** on a single dependency chain: the shared city-root key helper
plus the re-keyed rig memo (WI-1), the city-root buffer naming across the
view factory and terminal attach (WI-2), the cross-cutting per-city ERT
suite (WI-3), and the gate + tmux-Emacs dual-city e2e acceptance pass with
its QA report (WI-4). The order follows the plan's compile-cleanliness rule
(helper first, then its consumers), and each item owns the tests for its
slice per the house convention (ERT stubs the gc boundary with `cl-letf`;
no live gc in unit tests). All work stays inside gascity.el; beads.el and
the gc CLI are untouched.

Skipped and out-of-scope work is recorded in *Skipped Work* below; there is
no blocked work at decomposition time.

## Selected Downstream Formulas

The drain policy on the workflow root is `separate`, so the implementation
convoy drains through the following formulas (workflow root `ga-rv5`
metadata `gc.var.*`):

- **Implementation drain:** `do-work` (formula `build-from-convoy-base`
  step `implement`, `drain_policy == separate`, `member_access =
  exclusive`) — one implementation session per convoy bead, running under
  `gc.implementation-worker`.
- **Per-item fallback:** `do-work-item` / `implementation-item-base` is the
  single-lane item formula for a `same-session` drain; it is **not active**
  under the recorded `separate` policy but is listed as the contract the
  beads satisfy either way (each bead is a self-contained, single-lane
  work item with its own verification).
- **Code review:** `review` (`gc.var.code_review_formula`).
- **Review fix loop:** `fix-loop-base` (`gc.var.review_fix_formula`).

Each work item below carries its own expected files, verification
expectations, and requirement/plan traceability so any implementation
formula can drain it without knowing the planning methodology.

## Implementation Convoy

A **new** implementation convoy was created for this continuation — it
reuses neither the original launch convoy (`ga-dzr`, "input convoy for
ga-c1z") nor any planning or workflow-control convoy, as the decompose step
contract requires:

- **Convoy ID: `ga-wxj`** — title "multi-city-keying implementation".
- Members and drain order (dependency DAG; a bead is ready when its
  dependencies close):

| WI | Bead | Title | Depends on |
|----|------|-------|------------|
| WI-1 | `ga-w8j` | gascity-context-scope-key helper + rig memo re-key (plan Steps 1–2) | — |
| WI-2 | `ga-il1` | city-root buffer naming: remote qualifier, view factory, terminal attach (plan Steps 3–5) | WI-1 |
| WI-3 | `ga-t2w` | cross-cutting per-city ERT suite (plan Step 6) | WI-1, WI-2 |
| WI-4 | `ga-fza` | gate + tmux-Emacs dual-city e2e pass + QA report (plan Steps 7–8) | WI-3 |

The convoy identity is recorded on the workflow root bead (`ga-rv5`) as
`gc.input_convoy_id=ga-wxj` (drain contract) and
`gc.build.implementation_convoy_id=ga-wxj` (continuation reporting); the
recorded convoy is verified distinct from the original launch convoy
`ga-dzr` (`gc.var.convoy_id`) and from every workflow-control bead.

### Requirement and plan traceability

Every requirement (REQ-001…REQ-016) and plan step maps to exactly one
owning work item; each bead description restates its slice:

| Plan step(s) | Requirements | Work item |
|--------------|--------------|-----------|
| 1–2 (scope-key helper, rigs memo re-key, commentary, D2–D5) | REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-014 | WI-1 |
| 3–5 (buffer-name qualifier, view factory, terminal attach) | REQ-001, REQ-002, REQ-003, REQ-004, REQ-013 | WI-2 |
| 6 (cross-cutting ERT suite: memo per city, clear-cache, override, bead-store path, regression guards) | REQ-005, REQ-006, REQ-007, REQ-008, REQ-011, REQ-014 | WI-3 |
| 7–8 (tmux-Emacs dual-city e2e pass, QA report, gate, commit) | REQ-015, REQ-016 | WI-4 |

Plan-review advisories are adopted at the owning item: advisory 1
(reuse/refactor `gascity-context-pin-directory` in the factory) → WI-2;
advisory 2 (record remote-city buffer-name churn in the QA report) → WI-4;
advisory 3 (one-line per-city bead-store assertion) → WI-3.

## Work Items

### WI-1 — `ga-w8j`: scope-key helper + rig memo re-key (plan Steps 1–2)

- **Requirements:** REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010,
  REQ-011, REQ-014 (traces AC-1, AC-2, AC-3).
- **Expected files:** `lisp/gascity-context.el` (helper `gascity-context-scope-key`,
  `gascity-context--rigs-key` body, both docstrings, module commentary with
  the REQ-010 integration point for the formula catalog/recipe caches);
  `lisp/test/gascity-test.el` (`gascity-test-scope-key-per-city`, extended
  `gascity-test-rigs-cached-never-spawns`).
- **Formula assets:** none — this is a code work item drained by `do-work`.
- **Verification:** `eldev compile --warnings-as-errors` over the whole
  package; targeted ERT of the new/extended tests; existing suite green.
- **Dependencies:** none (first item; the helper is the compile-order root).

### WI-2 — `ga-il1`: city-root buffer naming (plan Steps 3–5)

- **Requirements:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-013 (traces
  AC-1, AC-3).
- **Expected files:** `lisp/gascity-remote.el` (`gascity-remote-buffer-name`
  gains the QUALIFIER argument; 2-arg contract byte-identical; Commentary
  "Buffer identity" updated); `lisp/gascity-context.el` (view factory
  computes the city root once for pinning AND naming, adopting plan-review
  advisory 1); `lisp/gascity-terminal.el` (attach buffer derives the city
  root of `default-directory`; not routed through the factory);
  `lisp/test/gascity-test.el` (`gascity-test-buffer-name-per-city`).
- **Formula assets:** none.
- **Verification:** whole-package `eldev compile --warnings-as-errors`;
  new naming tests; `gascity-test-remote-buffer-name`,
  `gascity-test-remote-localize-path`,
  `gascity-test-agent-attach-passes-rig-store` pass unchanged.
- **Dependencies:** depends on WI-1 (the helper must exist first).

### WI-3 — `ga-t2w`: cross-cutting per-city ERT suite (plan Step 6)

- **Requirements:** REQ-005, REQ-006, REQ-007, REQ-008, REQ-011, REQ-014
  (traces AC-2, AC-3).
- **Expected files:** `lisp/test/gascity-test.el` only.
  `gascity-test-rigs-memo-per-city` (two local cities; two cities under one
  TRAMP prefix; identical rig lists do not evict each other; prefix-less
  never replaces prefixed per city; third city cold),
  `gascity-test-clear-cache-cities` (REQ-008),
  `gascity-test-override-keys-by-overridden-root` (REQ-011), one-line
  per-city bead-store assertion (plan-review advisory 3), and the
  regression guards (2-arg buffer-name contract, existing remote/memo
  suite unchanged).
- **Formula assets:** none.
- **Verification:** full `eldev test` suite green; whole-package compile
  with `--warnings-as-errors`.
- **Dependencies:** depends on WI-1 and WI-2.

### WI-4 — `ga-fza`: gate + tmux-Emacs dual-city e2e pass + QA report (plan Steps 7–8)

- **Requirements:** REQ-015, REQ-016 (traces AC-4, AC-5).
- **Expected files / formula assets:** `docs/qa/2026-09-10-multi-city-keying.md`
  (new QA report recording the dual-city run, the remote-city buffer-name
  churn per plan-review advisory 2, and any AC-4 environment blocker — a
  bright-lights outage is recorded as a blocker, never silently skipped);
  residual fixes only if the e2e pass exposes a re-keying gap.
- **Verification:** the tmux-Emacs dual-city pass against
  `/ssh:localhost:/home/roman/bright-lights` **and** local `emacs-city`
  simultaneously (two status dashboards side by side with independent
  refresh, per-city rig dashboards/session lists, per-city eldoc prefixes
  after visiting both, compose/dry-run buffer per city); `scripts/gate.sh`
  passes; commit subject `fix(context): key views and rig memo by city
  root, not remote prefix`.
- **Dependencies:** depends on WI-3.

### Skipped work

- **Formula-cache implementation** (REQ-009's "if landed" branch): the
  formula-sling-ui caches have not landed (no formula-cache module under
  `lisp/`), so per REQ-010 this decomposition ships only the shared key
  helper and the recorded integration point in the `gascity-context.el`
  commentary (WI-1). No work item implements the formula caches; the
  recorded integration point governs when that work lands.
- **City-switching UI, per-city faces/refresh intervals, multiple
  simultaneous override values, `gascity-context--root-cache` changes** —
  out of scope by the requirements artifact and plan Non-Goals; no work
  item carries them.
- **Refresh-cadence / memo-invalidation changes** — plan D4 keeps both
  unchanged; covered by test assertions only (WI-3), not code work.

### Blocked work

None at decomposition time. Every work item is runnable once its
dependencies close, and WI-1 has no upstream blocker. The only conditional
risk is the WI-4 e2e environment: if `/ssh:localhost:/home/roman/bright-lights`
is unreachable at e2e time, WI-4 records it as an AC-4 blocker in the QA
report (per the plan's Assumptions) rather than skipping; that is a
runtime contingency recorded in the bead, not a blocked work item.

## Verification

- Each work item carries its own verification expectations (above) and its
  bead description repeats them; every item ends with whole-package
  `eldev compile --warnings-as-errors` and the relevant ERT run.
- WI-3 runs the full ERT suite; WI-4 runs `scripts/gate.sh` and the
  interactive tmux-Emacs dual-city pass — the acceptance gate for AC-1,
  AC-2, AC-4 end-to-end.
- Coverage disposition for every upstream ID:

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |

AC-1 → WI-1/WI-2/WI-3 (distinct names, no re-pin, override) + WI-4 (e2e);
AC-2 → WI-1/WI-2/WI-3 (per-city memo, cold stays cold, clear-cache, shared
helper); AC-3 → WI-1/WI-2/WI-3 (one scheme, commentary, remote tests green,
single-city names unchanged); AC-4 → WI-4; AC-5 → WI-4.