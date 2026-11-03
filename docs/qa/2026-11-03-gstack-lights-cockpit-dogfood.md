# gstack-lights cockpit dogfood — 2026-11-03

Scope: `gascity.el` at `ee3796b`, a fresh **non-graphical** Emacs in tmux,
pinned to `/home/roman/gstack-lights` (the `gstack-lights` pi city, pack
`gstack` 0.1.1, rig `hello-world-gstack`, prefix `hwg`). Read-only pass: no
workflow was launched or mutated, no city restarted, no Go/gc change.

The brief was extended by the Mayor's focus note: use the modes only to answer
**what failed, where, why, and what to do next** for the in-progress
`hwg-onb` (`gstack-build`) run, and to propose realistic diagnostics
improvements. This report records that pass; the sling preview was also
inspected read-only (section C).

## Method and clean environment

The city env of the dispatching session leaks a different city
(`GC_CITY=/home/roman/emacs-city`), so the pass unset it before starting
Emacs. Every `gc` child then keeps `default-directory` pinned by gascity.

```bash
tmux new-session -d -s gstack-qa -c /home/roman/gstack-lights
tmux send-keys -t gstack-qa "export EMACSLOADPATH=/home/roman/workspace/beads.el/lisp:/home/roman/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0:\$EMACSLOADPATH:" Enter
tmux send-keys -t gstack-qa "unset GC_CITY GC_CITY_PATH GC_BEADS_SCOPE_ROOT GC_DIR GC_RIG GC_RIG_ROOT GC_SESSION_NAME GC_SESSION_ID GC_AGENT GC_TEMPLATE GC_TRIGGER_BEAD_ID GC_TRIGGER_WORK_BEAD_ID GC_TRIGGER_WORK_STORE_REF GC_TRIGGER_BEAD_STORE_REF GC_BEADS GC_CITY_RUNTIME_DIR GC_CONTROL_DISPATCHER_TRACE_DEFAULT GC_INSTANCE_TOKEN GC_RUNTIME_EPOCH GC_CONTINUATION_EPOCH GC_PROVIDER GC_SPAWN_ORIGIN GC_STARTUP_PROMPT_DELIVERED GC_SUPERVISOR_PRESERVE_SESSIONS_ON_SIGNAL" Enter
tmux send-keys -t gstack-qa "emacs -nw -Q -L /home/roman/workspace/gascity.el/lisp --eval '(progn (require (quote gascity)) (setq gascity-context-city \"/home/roman/gstack-lights\"))'" Enter
```

Every view below opened the correct city (`gstack-lights`,
`/home/roman/gstack-lights`), with `● live` and no emacs-city data. This
confirms the environment pin works when the leaking `GC_*` variables are
unset (consistent with `docs/qa/2026-11-02-clean-env-cockpit.md`).

Pane was resized to 210×70 (`tmux resize-window -t gstack-qa -x 210 -y 70`) so
the full cockpit fits without folding.

## A. Cockpit (`M-x gascity-dashboard`)

Observed at 14:26 local:

```
 gstack-lights  ● live  ↻ 0s ago                      ? help  j jump  g refresh
gstack-lights  ~/gstack-lights                ▲ degraded (agent_state_unknown)
 agents 4/8 ▲   sessions 5   runs 1 ⬣ · 3 ✕   ready 2   mail ▲1   dolt 206 MB ◐

Needs you  5
  ■ run      hwg-y10 gstack-work  failed                      31m   hello-world-gstack
  ■ run      hwg-ayr gstack-work  failed                      33m   hello-world-gstack
  ■ run      hwg-889 gstack-work  failed                      34m   hello-world-gstack
  ▲ mail     1 unread                                                j m inbox
  ▲ store    health: city work ready: reading complete ready…       j h health

Moving  1 run · 3 workers
  ⬣ hwg-onb   gstack-build ◆◆◆◆◆✕◆◆◆···  implement      8/12   1h  hello-world-gstack
    └ ○ gl                       hwg-6s9   gstack release: documenta… 29s

Agents  4 running · 1 idle · 3 stopped                                 j a all
  ● hello-world-gstack/gstack.docs-en… pi             active  1s
  ● hello-world-gstack/gstack.release… pi             active  1s
  ...
  ○ hello-world-gstack/core.control-d…                idle    1h
  ▸ stopped  bd.dog-1 · bd.dog-2 · core.control-dispatcher

Work  2 ready · 3 in progress · 0 blocked · 5 convoys
  hwg-1pl   P2  Create a hello world program in guile scheme        hello-world-gstack
  hwg-m4b   P2  Make this repo a guix project using guix.scm        hello-world-gstack

Rigs  2
  gstack-ligh… gl   ~/gstack-lights            1/4 agents   0 in progress  (HQ)
  hello-world… hwg  ~/hello-world-gstack       4/4 agents   4 in progress
```

What renders correctly:

- The city, the rig roster (city + `hello-world-gstack/gc.*` +
  `hello-world-gstack/gstack.*`, including configured-only rows), the live
  header, and the Work beads (`hwg-1pl`, `hwg-m4b`).
- The workflow root `hwg-onb` with its 12-step ladder
  `◆◆◆◆◆✕◆◆◆···` and the failed drain `implement` is visible on the
  **Moving** row. There are no control-dispatcher-driven gstack session
  lanes at this instant except the three release-readiness workers.
- The three failed member runs are correctly promoted into **Needs you**
  (a real success: they are not hidden in the run detail).

What does not answer the operator question yet:

- **Work** only counts `3 in progress`; it never lists in-progress beads.
  A step whose assignee is dead is invisible there (only a ready list is
  shown).
- The **Needs you** failed-run rows say only `failed`; there is no
  `gc.failure_class`, failed step, or reason. `SPC` on such a row opens a
  drawer that only repeats `run hwg-y10 gstack-work failed`
  (`gascity-dashboard--needs-you-drawer` has no run drawer).
- During the pass a transient `hello-world-gstack/gstack.release-engineer-2`
  stalled row appeared as
  `■ agent  hello-world-gstack/gstack.release-engineer-2  r…` — the
  qualified name consumed the 48-column fit, so the reason
  (`running, no live session`) rendered as `r…`. By 14:27 the agent was
  gone again; a stalled row has no age or lease data (its `:active` is nil
  because there is no session).

The `▲ store … bead cache unavailable` item is city-wide store health, not
a workflow diagnosis. It is persistent noise in this pass (also shown in
the Health view).

## B. Runs / run detail / Events / Agents / Health

### B1. Runs view (`j r`)

```
Runs  gstack-lights   1 active · 0 waiting · 0 done · 3 failed  H history  / filter

Active  1
  ⬣ hwg-onb   gstack-build                                hello-wor…        1h
     ◆◆◆◆◆✕◆◆◆···  implement      8/12   ○ gl  hwg-6s9

Failed  3 · last 24h
  ✕ hwg-y10   gstack-work                                 hello-wor…       32m
     ✕✕✕  prepare-workt… 0/3    final attempt 3: source anchor hwg-r55 still has no work_dir; rig still $
  ✕ hwg-ayr   gstack-work                                 hello-wor…       34m
     ✕✕✕  prepare-workt… 0/3    source anchor hwg-a2e has no work_dir; prepare-worktree hwg-lso failed c$
  ✕ hwg-889   gstack-work                                 hello-wor…       35m
     ✕✕✕  prepare-workt… 0/3    source anchor hwg-ayw has no work_dir metadata and no item worktree exis$
```

This is the best list-level answer: the failed runs and the parent's ✕
ladder are both visible. But the failure text is raw and **clipped at the
window edge** (the `$` above is the terminal truncation); the tail that says
the rig has no git remote is the part cut off. `gc.failure_class` is not
shown. The parent "Active 1" card carries no failure summary even though its
implement step failed.

### B2. Run detail (`RET` on hwg-onb, then `SPC` on a failed step)

`RET` on the Moving row opened `*gascity-run: hwg-onb*`:

```
⬣ hwg-onb  gstack-build                        hello-world-gstack · started 1h
  formula  gstack-build (graph.v2)
  plans    review-context.md · review-report.md · ...
  convoy   hwg-825  open 0/3  gstack implementation: guix.scm package and README

Steps  8/12                                               C show control nodes
  ◆ prepare                   hwg-98d   pass      gl                        1h
  ◆ requirements              hwg-60q   iter 1    gl                        1h
  ...
  ▾ implement                 hwg-2z9   ✕ drain                            30m
    └ ✕ hwg-y10   gstack-wo… ✕✕✕  prepare-workt… 0/3                   RET run
    └ ✕ hwg-ayr   gstack-wo… ✕✕✕  prepare-workt… 0/3                   RET run
    └ ✕ hwg-889   gstack-wo… ✕✕✕  prepare-workt… 0/3                   RET run
    · Add guix.scm package definiti… hwg-ayw                               18m
  ◆ summarize-implementation  hwg-67e   iter 1    gl                       29m
  ▸ review                    hwg-ud1   ◆ loop                             14m
  ...
```

`RET` on the failed member `hwg-y10` opened its own run detail:

```
✕ hwg-y10  gstack-work  fail                   hello-world-gstack · closed 31m
  formula  gstack-work (graph.v2)
  convoy   hwg-kjd  open 0/1  drain unit 2 for hwg-r55

Steps  0/3                                                C show control nodes
  ✕ prepare-worktree          hwg-b4h   fail      gl                       32m
  ✕ implement                 hwg-xj1   iter 3    gl                       31m
  ✕ close-source-anchor       hwg-hw2   fail      gl                       30m
```

`SPC` on `prepare-worktree` opens the only place in the run views that has the
reason:

```
  ✕ prepare-worktree          hwg-b4h   fail      gl                       32m
  │ closed · outcome fail
  │ ref      gstack-work.prepare-worktree
  │ assignee gl-wisp-imza
  │ failure  prepare-worktree cannot resolve a remote default branch: rig checkout has no git remote, no$
  │ title    Prepare item worktree
```

So **WHERE** is answerable (`prepare-worktree`, plus `implement` and
`close-source-anchor`), and **WHY** is *partly* answerable (the first line of
`gc.failure_reason`), but `gc.failure_class=environment_missing_origin` is
absent and the reason is clipped. The run header says only `fail`; it does
not name the first failed step or the class.

The definitive WHY/next-step text lives in the delegated bead view, reached
with `b` from the failed Runs card:

```
✓ Closed  P2  Task  hello-world-gstack/core.control-dispatcher
Assignee: gl-wisp-kh0e
Outcome: fail

CLOSE REASON
Environment blocked: item workflow root hwg-y10 claimed by implementation lane
with no executable work description; rig has no git remote/refs/remotes/origin/HEAD
and source anchor hwg-r55 has no work_dir, so no worktree can be prepared for
this item. Implement retries exhausted (attempts 1-3 failed closed). No source
files edited; environment repair required.

METADATA
  gc.failure_class: environment_missing_origin
  gc.failure_reason: item workflow root hwg-y10 has no executable work
  description and its item prepare-worktree step cannot succeed: rig has no git
  remote/refs/remotes/origin/HEAD, so no worktree or work_dir can be published;
  approved decomposition requires stopping the run until the rig provides a
  local resolvable origin
  gc.session_id: gl-wisp-kh0e
```

So the beads view *does* wrap the reason and show the class. gascity simply
does not carry that information into its run/needs-you surfaces.

### B3. Events (`j e`, then `/ -q hwg-y10`)

Filtering to the failed bead works and the rows are discoverable:

```
 gstack-lights events  last 2h · 7 · signal ≥ event  search=hwg-y10 ...
 Time  Sig Type            Subject   Detail
 13:56     bead.updated ×6 (1 beads) hwg-y10
 13:56     bead.closed     hwg-y10   gstack-work
```

`SPC` on `bead.closed` shows:

```
type       bead.closed
ts         2026-11-03T13:56:07.378028738+01:00
seq        2936
actor      cache-reconcile
bead       hwg-y10 gstack-work (closed)
run_id     hwg-y10
session_id gl-wisp-kh0e
step_id    gstack-work
depends_on_step_ids gstack-work.workflow-finalize
subject    hwg-y10
```

No `close_reason`, no `gc.failure_class` in the event detail. `RET` on the
row opens the bead (where both are visible, as above), so the information is
two hops away, not in the detail pane.

### B4. Agents and Health

`j a` lists the configured agents with state, active, bead, provider. It
defaults to the `state=running` filter; `core.control-dispatcher` shows
`idle 1h` (the operator's suspicion of an idle dispatcher was correct as an
observation, but by this pass the dispatcher had already moved the workflow
on). A stalled agent is listed but its row has no age/lease. `i` opens the
agent/session detail; for a stalled agent there is no live session to show.

`j h` reports the supervisor as `▲ degraded (agent_state_unknown)` and the
store as `◐ bead cache unavailable`. No run/step-level diagnosis is offered
there.

### B5. The suspected `hwg-6ga` stall was already resolved

The focus note said `hwg-6ga` ("Prepare gstack release readiness") was
claimed at 14:23 local by a session that no longer existed. By the time this
pass started, gc had already closed it:

```text
$ gc bd show hwg-6ga      # scoped to the hello-world-gstack rig
✓ hwg-6ga · Prepare gstack release readiness   [P2 · CLOSED]
Assignee: gl-wisp-t5uh

$ gc events --since 2h | grep hwg-6ga
14:23:21  bead.updated   hwg-6ga
14:23:24  execution.step_started  hwg-6ga
14:24:21  bead.closed    hwg-6ga   (gl-wisp-t5uh, gc.outcome=pass)
```

Claim to close was ~60 s; the session existed throughout. So this pass could
not reproduce a live dead-assignee/stale-lease step. The genuinely failed
work is the three implementation member runs from 13:51–13:56
(`environment_missing_origin`). The `stalled` release-engineer-2 row seen at
14:26 and gone by 14:27 shows that transient liveness signals do occur; the
modes render that state but not its age.

## C. Sling preview (read-only, no launch)

From the cockpit on `hwg-1pl` (`C-s hwg-1pl`, `RET`, `S`):

```
Sling — gstack-lights
   Sling bead hwg-1pl to hello-world-gstack/gc.implementation-worker
   ✓ Ready — plain route · target rig-scoped · no vars
...
Who
 T Target agent…
```

`T` opened a completion list of 36 agents that includes
`hello-world-gstack/gc.run-operator` and the gstack lanes
(`gstack.decomposer`, `gstack.docs-engineer`, `gstack.implementer`,
`gstack.release-engineer`, …), so the Who roster fix (ee3796b) works.

Choosing `gstack-build` with `f` re-rendered the menu:

```
Sling — gstack-lights
   Run gstack-build against bead hwg-1pl, drained by hello-world-gstack/gc.run-operator
   ✓ Ready — on run · target rig-scoped · 14 of 18 vars set

How — gstack-build vars
 if artifact_root (required) — Build artifact root.  [dir] (--var artifact_root=plans/gstack-build/)
 od code_review_formula … [default: gstack-review]
 on context_path …
 ...
Actions
 s Preview & launch…
 r Preview recipe…
 q Quit
```

The derived target is `hello-world-gstack/gc.run-operator` (the formula's
drain/run target), the required `artifact_root` is rendered, and the gstack
variables are present. `r` opened the compiled recipe buffer
(`*gc-formula: gstack-build*`) with the full 84-step ladder, including
`Drain gstack work [gstack-build.implement] (drain)`.

The **full launch preview** (`s`, "Preview & launch…") was deliberately not
entered because this pass must not risk dispatching a new sprint. The recipe
preview was used as the dry-run evidence; no bead, run, or session changed
(the Work section still showed `hwg-1pl` ready afterwards). A future pass can
exercise `s` up to its final confirmation when a throwaway bead exists.

## D. Answers to the operator question

Can a user tell, **using only the Emacs modes**?

| Question | Answer | Where / gap |
| --- | --- | --- |
| What failed? | **Yes, at card level.** Three failed member runs and the parent's ✕ implement step are visible. | Cockpit Needs you, Runs Failed section, run ladder. Needs-you rows say only `failed`. |
| Where? | **Yes, with one drill-in.** Run detail shows `prepare-worktree`, `implement` and `close-source-anchor` failed; `SPC` names the step ref. | Run detail + step drawer. Parent run header does not name the failed step. |
| Why? | **Partly — only after two hops the full text appears.** The step drawer has the first line of `gc.failure_reason` (clipped, no class); the bead view has the wrapped close reason, `gc.failure_class=environment_missing_origin`, and the session id. | Run detail step drawer (no `failure_class`, clipped) → `b` bead view (full). Events detail omits both. |
| What next? | **Only from the bead/close reason.** "No git remote … environment repair required" is in the bead view. No mode suggests an action or shows whether the assignee is alive. | Bead view is the only remediation text. No diagnose action. |
| Is the assignee/session alive? | **No, not directly.** The bead view shows `gc.session_id`/assignee but not liveness or lease; the user must compare against Agents/Sessions by hand. | No cross-check of in-progress beads against live sessions, no lease display. |
| What is keeping `hwg-onb` "active" past a failed drain? | **Visible but not explained.** The ladder shows `✕ implement` while later steps run; the run still appears under "Active". | The parent proceeds past a failed drain — **gc/workflow-side**, reported here rather than fixed (the bead's `gc.failure_reason` itself says "approved decomposition requires stopping the run"). |

## E. Findings filed (gascity.el only)

All filed against the `gascity.el` store with `discovered-from:ga-lowub`.

- `ga-o7vtw` (P1) — Needs you: flag in-progress beads whose assignee session
  is gone or whose lease expired; list oldest in-progress work in Work.
- `ga-g092a` (P1) — Needs you and Runs: surface an active run containing a
  failed step (hwg-onb's `✕ implement` while the root is still in progress).
- `ga-lpnpb` (P2) — Run detail: show `gc.failure_class` and the failed step,
  not just `outcome=fail`.
- `ga-wjlx6` (P2) — Long `gc.failure_reason` is clipped with no help-echo in
  Runs cards and run-detail drawers.
- `ga-shl0s` (P2) — Needs-you failed-run drawer repeats the row instead of
  the failure class, failed step, reason and next action.
- `ga-vinoi` (P3) — Stalled agent: no stall age/lease, and a long qualified
  name squeezes the reason out of the Needs-you row.
- `ga-th2e2` (P3) — Events `bead.closed` detail omits `close_reason` and
  `gc.failure_class`.
- `ga-32wpi` (P2) — Add a one-key diagnose action linking a run/step to its
  failure class, assignee liveness and recent events (the single-screen
  answer the Mayor asked for).

Prioritized next pass:

1. `ga-o7vtw` — dead-assignee/lease detection is the Mayor's core scenario.
2. `ga-g092a` — don't let an active run hide a failed step.
3. `ga-32wpi` — one-key diagnose; then the presentation fixes
   (`ga-lpnpb`, `ga-shl0s`, `ga-wjlx6`, `ga-vinoi`, `ga-th2e2`).

## F. Explicit non-findings / gc-side notes

- **Not a gascity.el defect:** the failed implement drain did not stop the
  parent `hwg-onb`; later `summarize-implementation`, `review`, `qa` and
  `release-readiness` steps continued. The failure text says the run must
  stop until the rig provides a local resolvable origin. This is
  gc/workflow behavior; gascity faithfully renders both the ✕ and the later
  active steps.
- The `▲ store … bead cache unavailable` item is a city store-health
  signal (Health view), not a workflow failure; it is noisy but not
  mislabeled.
- `gc status` reports `degraded (agent_state_unknown)` at the supervisor
  level throughout; the cockpit shows this honestly.
