---
schema: gc.build.review-report.v1
workflow:
  id: ga-eavt
  formula: build-basic
review:
  step: review.acceptance-review
  reviewer_bead: ga-qigo
  lane: starter-factory-acceptance
  date: 2026-09-27
  subject: implementation commit e44dcf0d (merged item worktree ga-3wpi)
  verdict: iterate
---

# Acceptance review — Sling command redesign (workflow ga-eavt)

Reviewed against `plans/sling-command/requirements.md` (REQ-001…REQ-015),
`implementation-plan.md` (WI-1…WI-12), `decomposition.md`, the task
summaries, and `build/review-context.md`. Code under review: the recorded
implementation anchor **e44dcf0d** in `worktrees/ga-3wpi` (merged item
worktrees WI-1 ga-510r `8fc52c0`, WI-2 ga-0okd `338d2cb`, WI-3 ga-ntop
`9d2acbf`, WI-4 ga-f7a4 `83c5367`, WI-5 ga-o6eh `cc5d836`, WI-6 ga-pkpi
`80c35dd`, WI-9 ga-me2n `af56c49`, plus the WI-11 work). The launcher root
was not used as review target.

## What verifies

- **Gate green, re-run by this review** in `worktrees/ga-3wpi`
  (`pwd -P` = the worktree; HEAD e44dcf0d): `scripts/gate.sh` →
  `>>> gate: PASS (compile clean + tests green)`, 723/723, 2026-09-27.
- **WI-1** shape inference + one-sentence header
  (`gascity-sling--shape`, `gascity-sling--header-sentence`): pure,
  display-only, dispatch keeps `gascity-formula--needs-convoy`
  authoritative — matches the plan. Verified live (e2e report §1–§4).
- **WI-2** client-side validators (`gascity-sling--binding-targets-p`,
  `--v2-trap-p`, `--cross-store-p`, missing-work/vars/target): pure over
  cached data, degrade silently, never block `s`. Verified live (§3).
- **WI-3** derived Who default (`gascity-sling--derive-target`): the
  design's rule order, pure, memory recorded on real launches only.
  Verified live (§2/§4 zero-prompt behavior).
- **WI-5** typed How vars: classes, overridable `gascity-sling-var-readers`,
  fail-soft heuristics, `plans/<slug>/` seed, numeric guard, TRAMP-pinned
  completion dir. Verified live (§2, numeric refusal verbatim).
- **WI-6** live footer: rendered as a function description (recomputes on
  redraw), feeds the derived target into the checks (post-e2e fix),
  never blocks. Verified live (§3 wording verbatim).
- **WI-8** follow offer: `molecule_id` payload root, store-backed fallback
  read, momentary `F` map, plain route untouched. Verified live (§1/§2).
- **WI-9** state/memory: target memory recorded post-dispatch only
  (a validation `user-error` records nothing), remembered per-city state
  preserved, `:work-title` added without breaking the S-2 contract.
- **WI-11** four-scenario e2e pass over TRAMP against bright-lights with
  `gc --city` everywhere; dogfood report committed with three
  integration fixes and their regression tests.
- **Out-of-scope check: clean.** The diff (origin/main..e44dcf0d) touches
  exactly the sling files, tests, plan artifacts, the QA report and
  doc/gascity.texi; the non-goals (ga-tbte worktree, plans/dashboard-v2
  deletions, gc-side changes) are untouched; no sync gc on render paths
  found (`gascity-store-get`/`-peek` never spawn; `gascity-rigs-cached`
  is the memo).

## Required fixes (iterate)

### F-1 — The staged mockup layout (WI-4 core) was never implemented (REQ-011, REQ-003, REQ-011 acceptance criterion 9)

The merged tree renders the **old** layout. Proof:

- `worktrees/ga-3wpi/lisp/gascity-action.el`, `gascity-sling--children-specs`
  (line ~1788): groups are still `Formula` / `Destination` /
  `Routing flags` / `Actions`; routing flags render **unconditionally**,
  not plain-only; there is no What/Who/How staging and no collapsed
  answered-stage lines.
- Same file, `gascity-sling--reserved-keys` (line 1620): still
  `f g T A c a n m t s p r x q` — `p` is not freed, `P` is absent, `g`
  still sits in the Formula group; the mockup §10 set
  `A f T c a n m t s P r g x q` is not in effect.
- `A` is still `gascity-sling-dispatch-arg` → plain `read-string
  "Bead id or task text: "` (line ~1901): the smart work picker over
  open beads + convoys with `title · status · store` annotations and the
  `C-u` freeform escape (REQ-003, mockup §6a) does not exist in any
  commit of any sling worktree (`git grep gascity-sling-dispatch-work`
  finds it only in unmerged test files).
- The scope plist has no `:work` generalization in the merged tree.

The plan's handoff and acceptance criterion 9 (layout matches
menu-mockups.md state for state) fail on the reviewed implementation.

### F-2 — WI-4's commit and task summary do not describe their own tree (reporting integrity feeding the trace)

`git -C worktrees/ga-f7a4 show --stat 83c5367` shows the commit titled
"feat(sling): adaptive mockup layout, What/Who/How stages, A work picker"
contains **only the follow-offer code** (`gascity-sling--run-roots-key`
… `gascity-sling--launch-handler`) — byte-identical (md5) to WI-8's
`0853cd9` block — plus test tweaks. No staged layout, no work picker, no
reserved-key change. The WI-4 task summary
(`plans/sling-command/task-ga-f7a4-summary.md`, traced by the canonical
implementation-summary) claims `gascity-sling--work-line`,
`--scope-work`, `--work-beads`, `--work-convoys`,
`gascity-sling-dispatch-work`, the mockup-state layout tests and a gate
run — none of which exist in any sling commit. The canonical
implementation-summary's REQ-001/REQ-003/REQ-011 coverage rationale
inherits this claim, so the trace is currently wrong for three
requirements. The e2e report's own F7 concedes "WI-4's staged layout has
not landed". The fix loop needs the record corrected (commit relabel or
summary correction) on top of F-1's implementation.

### F-3 — `P` full preview buffer (WI-7) is not in the reviewed implementation (REQ-008)

`gascity-sling-dispatch-full-preview` exists only in
`worktrees/ga-ub2r` @ `683cece`, which is **not merged** into the
recorded implementation e44dcf0d (`grep dispatch-full-preview lisp/` →
empty). The merged tree's preview is still the `p` dry-run text view;
the recipe-DAG/validation/routing-plan buffer with launch-from-preview
is absent. Either merge ga-ub2r (reconciled with F-1's reserved-key
change) or REQ-008 and acceptance criterion 6 fail. Same status for
WI-10 (ga-gonl `426d2fd`, conditional tests) and WI-12 (ga-1wl7
`f21af52`) — both unmerged; WI-12 is expected at finalize, but the
review contract reviews the recorded implementation anchor, so the
finalize stage must actually merge ga-ub2r/ga-gonl/ga-1wl7 or these
requirements stay unmet on `main`.

### F-4 — The Who picker is still session completion, unannotated (REQ-005, mockup §6c)

The `T` suffix (`gascity-sling-dispatch-target`, line ~1919) reads via
`gascity-action--read-session`, which completes over **session aliases**
from `gc session list` (`gascity-action--session-names`, line 285) with
no grouping or annotation. The built-for-this accessor —
`gascity-agents-roster` / `gascity-agents-roster-candidates` /
`gascity-agents-roster-scope` (WI-2, ga-0okd), tested in
`lisp/test/gascity-agents-test.el` — has **zero non-test callers**
(`grep -rn "gascity-agents-roster-candidates" lisp/` matches only its
definition and its test). REQ-005's "completion over agents (not
sessions), grouped/annotated by rig with scope and live state" and the
`derived` tag in the picker (the derived default only pre-fills the
minibuffer input) are unmet; wire the roster accessor into the `T` read.

## Minor findings (record, fix opportunistically)

- **M-1** — `gascity-sling--missing-target-warning` is defined twice:
  `defvar` (nil) in `gascity-action.el` and `defconst` (the wording) in
  `gascity-formula.el`. Works only because the package load order loads
  action before formula; a standalone `action` load would see nil. Drop
  the action-side defvar (declare-function suffices).
- **M-2** — `gascity-sling--binding-targets-p` docstring says "23 of 38"
  steps; the e2e report says 24. Doc-only drift.
- **M-3** — the e2e report's recorded risks (F1 refused read closes the
  menu; F2 answers after the last re-setup lost on reopen; F3 TRAMP
  paths returned TRAMP-prefixed; F4 HQ rig missing from the rig memo;
  F5 `*_target` seeds ignore the derived default; F9 formula path never
  nudges) are real UX gaps against the mockups' quality bar; the fix
  loop should schedule them alongside F-1..F-4, F3 (TRAMP names gc
  cannot consume) being the most consequential.

## Verdict

**iterate.** The landed half (inference, validators, derived Who,
typed vars, footer, follow offer, memory, e2e) is correct, well-tested,
and live-verified; the gate passes on the reviewed anchor. But the
mockup layout (F-1/F-2), the `P` preview (F-3) and the annotated agent
Who picker (F-4) — three of the redesign's most user-visible
requirements (REQ-003, REQ-005, REQ-008, REQ-011) — are absent from the
reviewed implementation, and the WI-4 provenance mislabels what landed.
Smallest path to approve: implement F-1 (or merge the real staged
layout if it exists outside the recorded anchors), merge ga-ub2r/ga-
gonl (F-3), wire the roster into `T` (F-4), and correct the WI-4
summary/commit record (F-2).
