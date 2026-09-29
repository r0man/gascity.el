# Test Evidence Review — build-basic workflow ga-eavt (starter review lane)

- Reviewer bead: ga-jl7b (review.test-evidence-review), 2026-09-27
- Context authority: `plans/sling-command/build/review-context.md` §Implementation Worktrees
- Requirements: REQ-001…REQ-015; acceptance criteria AC-1…AC-13 (`requirements.md` §Acceptance Criteria)
- Verdict: **iterate** (evidence gaps only; core proof reproduced and green — see Verdict)

All commands below were run from the listed implementation worktrees
(`cd "$WORKTREE"` with `pwd -P` verified equal to the worktree before
execution), never from the launcher root.

## 1. Per-task evidence structure (12 accepted work items)

| WI | Bead | Per-item summary | Intended behavior | First verification cmd | Proof cmd | Changed files | Remaining risks |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | ga-510r | **absent** (evidence: worktree commit 8fc52c0 + ported suite + WI-11 pass) | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ |
| 2 | ga-0okd | worktrees/ga-0okd/plans/sling-command/build/implementation-summary-ga-0okd.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 3 | ga-ntop | plans/sling-command/task-ga-ntop-summary.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 4 | ga-f7a4 | plans/sling-command/task-ga-f7a4-summary.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 5 | ga-o6eh | plans/sling-command/task-ga-o6eh-summary.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 6 | ga-pkpi | **absent** (evidence: commit 80c35dd + WI-11 footer scenarios) | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ |
| 7 | ga-ub2r | plans/sling-command/build/ga-nij3-implementation-summary.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 8 | ga-f4w0 | plans/sling-command/task-ga-f4w0-summary.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 9 | ga-me2n | **absent** (evidence: commit af56c49 + WI-11 pass) | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ | via canonical summary ✓ |
| 10 | ga-gonl | plans/sling-command/task-ga-gonl-summary.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 11 | ga-3wpi | worktrees/ga-3wpi/plans/sling-command/build/implementation-summary-ga-nqyt.md ✓ + dogfood report ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 12 | ga-1wl7 | worktrees/ga-1wl7/plans/sling-command/task-ga-1wl7-summary.md ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

- All nine existing per-item summaries carry all five required fields
  (Intended Behavior / first verification command / proof command /
  Changed Files / Remaining Risks). Spot-read (WI-3, ga-ntop): intended
  behavior is concrete per design rule, commands and files are named,
  risks honest.
- Findings T-1 (structure, minor): WI-1, WI-6, WI-9 have no per-item
  summary files. The canonical implementation summary records their
  intended behavior, changed files, verification, and remaining risks
  explicitly (with commit hashes), so the evidence contract is met
  collectively, not per-task. Recorded as a structure gap, not a
  product defect; no fix-lane action required beyond noting it.
- Worktree/commit audit: all twelve worktrees exist and are distinct
  from the launcher root; every context-listed item commit is HEAD or
  an ancestor of HEAD (ga-o6eh HEAD cc5d836 = 2f83f30 + one test fix;
  ga-1wl7 HEAD fea91df = f21af52 + its summary-artifact commit). No
  drift that invalidates the recorded evidence.

## 2. Proof commands executed in this review (reproduction)

| Command | Worktree (pwd -P verified) | Recorded | Observed here |
| --- | --- | --- | --- |
| `scripts/gate.sh` | worktrees/ga-3wpi @ e44dcf05 (merged tree) | PASS, compile clean, 723/723 | **PASS — compile clean, `Ran 723 tests, 723 results as expected, 0 unexpected`** |
| `make -C doc` (forced: info removed first) | worktrees/ga-1wl7 @ fea91df | builds | **PASS — `makeinfo -I . -o gascity.info gascity.texi`, gascity.info (122 KB) produced** |

The two reproducible proof commands reproduce exactly as recorded.
AC-1…AC-11 are exercised by the 723-test suite (which includes the
ported seven sling tests and the new inference/heuristics/Who-default/
trap-warning/cross-store/follow-offer tests named in AC-11); AC-12 is
covered by the recorded WI-11 dogfood report; AC-13 is covered only
partially (see T-2).

## 3. Recorded live-pass evidence (WI-11, not re-run here)

`worktrees/ga-3wpi/docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`
records all four REQ-014 scenarios as verified live over TRAMP against
`/home/roman/bright-lights` with `gc --city` on every invocation,
including verbatim transient captures, three integration bugs found and
fixed with regression tests, and nine recorded findings F1–F9. The
report is concrete and internally consistent with the merged tree; this
lane did not re-run the interactive tmux acceptance pass (recorded
same-day evidence, and the reproducible halves — gate + doc build —
were re-run above).

- Findings T-3 (product defects, for the fix loop — **change code**):
  the e2e report's own findings are real product defects awaiting the
  fix loop, not evidence gaps: F1 (read abort closes the transient),
  F2 (var answers set after last re-setup lost across reopen), F3
  (TRAMP-prefixed path vars gc cannot consume), F4 (rig memo misses HQ
  rig from status-only seeding), F5 (`*_target` var seeds ignore the
  Who default), F6 (`artifact_root` slug does not re-seed on `A`-set
  work; build-basic declares no `rig_name` var), F7 (`C-u S` freeform
  escape missing), F9 (formula path never nudges a sleeping agent).
  F8 items are pre-existing city/environment conditions, out of scope
  for this implementation.

## 4. Acceptance-criteria coverage check

| AC | Claimed evidence | Verified |
| --- | --- | --- |
| 1–10 (transient behavior, shapes, pickers, readers, footer, preview, launch/follow, warnings, mockups, state) | 723-test ERT suite incl. ported + new sling tests; WI-11 live scenarios 1–4 | ✓ (gate re-run green; live report detailed) |
| 11 (ERT consolidation + `scripts/gate.sh` green) | task-ga-gonl-summary + merged gate | ✓ reproduced: 723/723, compile clean |
| 12 (four bright-lights e2e scenarios, `gc --city` everywhere) | WI-11 dogfood report | ✓ recorded (not re-run); four scenarios all ✓ in report |
| 13 (Texinfo chapter builds; **real screenshots from the live session** wired) | doc builds ✓; 7 `doc/images/sling-*.png` wired | **partial** — see T-2 |

- Findings T-2 (**missing proof** — the one actionable gap): AC-13
  requires "real screenshots from the live session". All seven wired
  sling images are mockup renderings: WI-12's worktree could not run
  the redesigned transient (separate-context drain; documented
  fallback), and the promised replacement by the WI-11 session never
  happened (that session was `emacs -nw`, and `git diff` shows no
  `doc/images/` changes on the merged tree e44dcf0d nor between
  ga-1wl7 and ga-3wpi). The WI-11 report itself defers this ("WI-12
  should capture from a GUI session or fall back"). The Texinfo
  chapter itself builds and is complete — this is missing proof, not a
  code defect. **Fix-lane action: run the missing proof command** —
  capture the seven transient states from a GUI Emacs session against
  the merged implementation and replace `doc/images/sling-*.png` under
  the same names — or record an explicit acceptance decision that the
  mockup renderings stand in as the requirements'-Open-Question
  fallback for AC-13.

## Verdict

`code_review.test_evidence_verdict=iterate`.

Reasoning: the reproducible proof (gate, doc build) reproduces green
from the correct implementation worktrees and covers AC-1…AC-12; the
live e2e evidence is concrete and recorded. But AC-13's screenshot
proof is missing (mockup renderings only, promised live capture never
ran) — a fixable proof gap, so the lane cannot approve test evidence
without it. The fix lane should run the missing screenshot capture
(T-2) and treat F1–F9 as code-change work already queued for the fix
loop; T-1 needs no action.
