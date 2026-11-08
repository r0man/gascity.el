# Run rendering: three alternatives

Status: design spike, design only. No lisp, Go or web changes accompany this
document.
Bead: `ga-zp2v9` (design spike, gascity.el).
Date: 2026-11-08.
Surfaces: the gascity.el Runs view (`*gascity-runs:CITY*`) and run detail
(`*gascity-run:ID*`), and the web dashboard's `/city/CITY/runs` and
`/city/CITY/runs/ID` pages.

Worked example used in every mockup, taken from the live emacs-city store on
2026-11-08:

| fact | value |
| --- | --- |
| run root | `be-0kjzs` `build-basic`, rig `beads.el`, started ~3h, `5/10` steps · `45` beads |
| source feature | `be-tnd3z` "Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el, default-theme screenshots, black-box QA" (open) |
| input convoy | `be-hzrwd` ("input convoy for be-tnd3z", tracks `be-tnd3z`) |
| implementation convoy | `be-o4er1` `manual-demo-consistency-implementation`, 7/8 |
| stages (formula order) | Intake 5/5 · Implementation 0/2 · Review 0/1 · Approval 0/0 · Finalization 0/2 |
| business items (8) | `be-rtqte`, `be-95bl3`, `be-k8nn0`, `be-vrjbu`, `be-o597j`, `be-gn247`, `be-7japy`, `be-s61jf` |
| `do-work` member run roots (8) | `be-b9jhp`, `be-ybleu`, `be-rtqoj`, `be-wm8j0`, `be-w7pjp`, `be-s3joe`, `be-sqrl5`, `be-dhu31` |

The pairing (drain index order) is:

| idx | business item | member run | its ladder |
| --- | --- | --- | --- |
| 0 | `be-rtqte` Retarget the demo fixture… | `be-b9jhp` | `◆◆◆ 3/3` pass |
| 1 | `be-95bl3` Remove third-party themes… | `be-ybleu` | `◆◆◆ 3/3` pass |
| 2 | `be-k8nn0` Complete the warning-free Texinfo… | `be-rtqoj` | `◆◆◆ 3/3` pass |
| 3 | `be-vrjbu` Regenerate and verify every screenshot… | `be-wm8j0` | `◆◆◆ 3/3` pass |
| 4 | `be-o597j` Complete reference, keybinding, index… | `be-w7pjp` | `◆◆◆ 3/3` pass |
| 5 | `be-gn247` Write the shared /tmp/demo-project… | `be-s3joe` | `◆◆◆ 3/3` pass |
| 6 | `be-7japy` Run the manual-only black-box QA… | `be-sqrl5` | `◆◆◆ 3/3` pass |
| 7 | `be-s61jf` Pin the new manual contracts… | `be-dhu31` | `◆◆⬣ 2/3`, active at `close-source-…` |

This pairing exists today only in bead metadata
(`gc.drain_control_id`, `gc.drain_member_id`, `gc.drain_index`,
`gc.drain_count`); neither surface presents it. That is the central finding
behind all three alternatives.

The brief recorded the last member at `1/3`; because the run is live, it had
advanced to `2/3` (active at `do-work.close-source-anchor`, worker
`run-operator-1`) when this document was written. The mockups use the live
state.

## 1. Current state critique

### 1.1 What works and should survive any redesign

- **One ladder vocabulary.** `◆` done, `⬣` active, `·` pending, `✕` failed,
  `▸`/`▾` folds, `└` member nesting. It reads in greyscale and stays legible
  at 100 columns. All three alternatives keep it.
- **Stages are named, ordered, and counted.** The manual's lifecycle stages
  (Intake, Implementation, Review, Approval, Finalization) are a stable
  contract; a stage with no members still shows `0/0`. Keep this.
- **The header is provenance, not invention.** Root, store, scope, source,
  formula, key, formula source, plans and convoy come from the run root's own
  metadata; absent facts are omitted. The new `source` row (commit
  `223e0d7`) is the first outcome-oriented fact on the page.
- **Drill-down is truthful.** `RET` opens the bead, artifact or worker at
  point; the step inspector shows attempt history, worker/lease state,
  artifacts and events; `I` on a drain member opens the member's own drawer.
  Nothing is fabricated when a read fails.
- **Reads are async, cached, and stored per city.** Detail reads go through
  `gascity-store-use` (stale-while-revalidate); live refresh is event-driven,
  not a timer. Any redesign must keep this, especially for remote cities.
- **The Runs card is compact.** Two lines (card + ladder) fit many runs in a
  window, and the drawer (`SPC`) expands the full ladder without leaving the
  list. That density is valuable.

### 1.2 What the user must already know today

The live run detail, captured from a fresh non-graphical Emacs (Emacs 31.1,
tmux, 120×40 pane, `gascity` loaded from `lisp/`, default-directory
`/home/roman/emacs-city`, with `C` pressed to reveal the control group), is:

```text
  root     ⬣ be-0kjzs  build-basic                       beads.el · started 3h
  store    rig:beads.el   rig beads.el   city emacs-city
  scope    (none)
  source   be-tnd3z  Manual overhaul: Emacs-doc quality + shared demo f…  open
  formula  build-basic  contract graph.v2
           key graphv2-root:be-hzrwd:build-basic:0a9a02d13936aa1b:default
           source ~/.gc/cache/…/build-basic.formula.toml
  plans    decomposition.md · factory-run.md · implementation-summary.md
           implementation-plan.md · plan-review.md · requirements.md
           review-report.md
  convoy   be-o4er1  open 7/8  manual-demo-consistency-implementation

Steps  5/10 · 45 beads                                    C show control nodes
  ▾ ◆ Intake         5/5
    ◆ prepare                 be-nasax  pass      ec                        3h
    ◆ requirements            be-8lclw  iter 1    ec                        3h
    ◆ plan                    be-rexyi  iter 1    ec                        3h
    ◆ plan-review             be-w4zzs  pass      ec                        3h
    ◆ decompose               be-bbp6v  iter 1    ec                        3h
  ▾ ⬣ Implementation 0/2
    ▾ implement               be-9sbk2  ⬣ drain                             3h
      └ ⬣ be-dhu31  do-work    ◆◆⬣  close-source-… 2/3                 RET run
      └ ◆ be-sqrl5  do-work    ◆◆◆                 3/3                 RET run
      └ ◆ be-s3joe  do-work    ◆◆◆                 3/3                 RET run
      └ ◆ be-w7pjp  do-work    ◆◆◆                 3/3                 RET run
      └ ◆ be-wm8j0  do-work    ◆◆◆                 3/3                 RET run
      └ ◆ be-rtqoj  do-work    ◆◆◆                 3/3                 RET run
      └ ◆ be-ybleu  do-work    ◆◆◆                 3/3                 RET run
      └ ◆ be-b9jhp  do-work    ◆◆◆                 3/3                 RET run
      ◆ Retarget the demo fixture to … be-rtqte  pass                       3h
      ◆ Remove third-party themes fro… be-95bl3  pass                       2h
      ◆ Complete the warning-free Tex… be-k8nn0  pass                       2h
      ◆ Regenerate and verify every s… be-vrjbu  pass                       1h
      ◆ Complete reference, keybindin… be-o597j  pass                       1h
      ◆ Write the shared /tmp/demo-pr… be-gn247  pass                      55m
      ◆ Run the manual-only black-box… be-7japy  pass                      18m
      · Pin the new manual contracts … be-s61jf                            19m
    · summarize-implementation be-o4q0j  iter 1                             3h
  ▾ · Review         0/1
    ▸ review                  be-thq3n  · loop                              3h
  ▾ · Approval       0/0
  ▾ · Finalization   0/2
    · finalize                be-8t31o  iter 1                             3h
    · publish                 be-eyn10                                      3h
  ▾ · Control        0/13
    · spec                    be-6wm80  spec                                3h
    · spec                    be-frotp  spec                                3h
    …
```

The Runs card for the same run is:

```text
  ⬣ be-0kjzs  build-basic                                 beads.el          3h
     ◆◆◆◆◆⬣····  implement      5/10   ● run-operator-1  be-dhu31
    └ ⬣ be-dhu31  do-work                                 beads.el          3h
         ◆◆⬣  close-source-… 2/3    ● run-operator-1  be-u0j2w
```

The web pages render this structure (from the live BFF payload and the SPA's
run components):

- `/runs`: a phase label (`Implementation`), the run title (`build-basic`),
  the **formula name again** (`build-basic`), the five-stage ladder, the root
  id, and bead status counts (`1 in progress · 23 open · 15 closed`).
- `/runs/be-0kjzs`: title `build-basic`; meta cells FORMULA `build-basic`,
  ROOT `be-0kjzs`, SCOPE `rig:beads.el`, STORE `rig:beads.el`; the stage
  ladder; a "Formula Graph" of 27 nodes and 63 edges (business items appear
  as ordinary `step` nodes with their titles); `RELATED` is empty.
  The payload has no source bead, no convoy, no drain members and no
  deliverables.

The web lane card renders, in order (text sketch, ≈72 columns; the product
has no card chrome, only hairlines and space):

```text
Implementation                                                 3h ago
build-basic
build-basic
· Intake   ⬣ Implementation   · Review   · Approval   · Finalization
be-0kjzs   1 in progress · 23 open · 15 closed
```

The run-detail structure, top to bottom (text sketch):

```text
Formula Run                                   Runs   v1 · seq 422428   [Refresh]
build-basic
27 nodes. 1 running, 12 done, 14 pending.
FORMULA build-basic   ROOT be-0kjzs   SCOPE rig:beads.el   STORE rig:beads.el
· Intake   ⬣ Implementation   · Review   · Approval   · Finalization
Formula Graph
  build-basic (run root, running)
  Prepare build context (step, done) …
  Retarget the demo fixture… (step, done)          ← business item, unlabeled
  Pin the new manual contracts… (step, pending)   ← business item, unlabeled
RELATED   none
```

To read this run correctly the user has to know all of the following:

1. `build-basic` is scaffolding. The feature is `be-tnd3z`.
2. `source` is the business feature, resolved as the first tracked member of
   the **input** convoy (`gc.var.convoy_id` = `be-hzrwd`). The row does not
   name that convoy.
3. The `convoy` row is a *different* convoy: the **implementation** convoy
   (`be-o4er1`, from `gc.input_convoy_id` / `gc.build.implementation_convoy_id`)
   whose members are the 8 business items. Nothing in the label says
   "implementation"; a reader reasonably assumes it is the input convoy.
4. `Implementation` contains a run-level drain step (`be-9sbk2`) plus 8
   business beads, and each business bead has a separate `do-work` workflow
   root. The 8 `do-work` rows are those roots, not steps of this run.
5. Which member root executes which business item is encoded only in
   `gc.drain_member_id` on the member root. The member row shows the member
   id, never the business id; the `I` drawer also omits it. The only reliable
   join is `gc bd show` or opening each member's detail.
6. Order matters and the two blocks disagree: member rows are rendered in
   reverse drain order (`be-dhu31` first, `be-b9jhp` last), while the business
   title rows follow graph order (`be-rtqte` first, `be-s61jf` last). Reading
   down either column and pairing them by position is wrong.
7. "How big is this run?" has three answers: `5/10` steps (anchors), `45`
   beads (the whole Emacs graph), and `27 nodes` (the web display graph).
   They are all defensible and all different.
8. `C` reveals 13 control nodes; `T` re-renders the step tree by `needs`;
   `I` inspects; `w` copies; `!` diagnoses. None of these affordances reach
   the business↔execution pairing.

### 1.3 Observed cross-surface defects worth fixing regardless

- **The web stage ladder disagrees with the web graph.** For `be-0kjzs` the
  live detail payload reports `Intake pending, Implementation active` and the
  summary lane reports the same, while the same payload lists all five Intake
  nodes (`build-basic.prepare`, `be-8lclw`, `be-rexyi`, `be-w4zzs`,
  `be-bbp6v` — five of the twelve completed nodes) as `completed`, and Emacs
  renders `Intake 5/5`. The two surfaces cannot both be right.
- **The web run card repeats the formula.** Title and formula are both
  `build-basic`; the card has no source, so two `build-basic` runs are
  indistinguishable. This is the exact defect the task names.
- **The Emacs runs card has no source either.** The card is correct but
  anonymous: the same two `build-basic` cards can only be told apart by id.
- **The detail header and the card disagree on the run's current step.** The
  card says `implement 5/10`, the header's `convoy` row says `7/8`, and the
  stage says `0/2`; each is a different denominator (anchors, convoy
  membership, steps). The redesign must label the denominators or show one.

### 1.4 Data that exists but is not surfaced

| data | where it lives | what it would buy | already read? |
| --- | --- | --- | --- |
| source feature `be-tnd3z` | `gc.var.convoy_id` → convoy status members | the run's title | Emacs detail yes (new), Emacs runs card no, web no |
| input convoy id `be-hzrwd` | `gc.var.convoy_id` | provenance; explains `source` | Emacs detail (used, not named); web no |
| implementation convoy `be-o4er1` | `gc.input_convoy_id`, `gc.build.implementation_convoy_id` | names the deliverable container | Emacs detail as unlabeled `convoy`; web no |
| item ↔ member join | `gc.drain_member_id` on each member root | one row per deliverable | Emacs beads loaded, not joined; web no |
| drain ordering | `gc.drain_index`, `gc.drain_count` | stable lane order | not shown |
| member ladder + worker + failure | member root graph | per-item progress | Emacs member rows; never paired; web absent |
| business outcome/status | business bead `status`, `gc.outcome`, close reason | per-item verdict | Emacs title rows (`pass`); web node status |
| per-item times | business `created_at`/`closed_at`, member step times | timeline / duration | Emacs relative times only |
| item root key | `gc.item_root_key` (`drain-item-root:be-9sbk2:N:be-…`) | stable grouping key | not shown |
| session link | member root `gc.session_name`, session list | who is on item 8 | Emacs member worker; web only `activeAssignees` |

### 1.5 What this means for the design

The pages are rich in *execution* facts and poor in *deliverable* facts. The
root/formula is treated as the identity; the business feature is a row; the
8 deliverables and their 8 member runs are two parallel lists with no join.
A redesign should not add more execution detail. It should make the
deliverable the unit of reading and derive execution detail from it.

## 2. Three alternatives

All three keep the manual's stage names and the existing glyphs, and add no
new keys: `RET`, `SPC`, `C`, `I`, `w`, `!`, `g`, `q` keep their meanings
("object at point" changes with the layout). Web mockups are drawn at about
72 columns to represent a 560–720 px card; the responsive rules are stated
per alternative.

### Alternative A — Business spine (outcome-first hierarchy)

**Idea.** Make the business feature the page, and the run a footnote. The
feature title is the headline; each of the 8 deliverables is a first-class
row with its own status and its `do-work` member run nested immediately
beneath it; the formula, root, key, plans and convoys become a provenance
block at the bottom, and the existing step tree stays below it, folded under
a `Machinery` header (`SPC` folds it; `C` still shows its control nodes and
`T` its needs tree). "What is being delivered" is answered before "which
formula is running".

**Mapping.** Feature (`be-tnd3z`) → input convoy (`be-hzrwd`, provenance) →
implementation convoy (`be-o4er1`, the deliverable set) → each business item
→ its member run, paired by `gc.drain_member_id` (falling back to
`gc.drain_index` order). The member line is the execution half of the same
deliverable, not a separate list.

**New vs available.** The only new Emacs data is the reverse drain map (a
hash built from the already-loaded bead graph: `gc.drain_member_id` →
member root) plus the source read on the Runs card. The join is in-memory;
the card read is one convoy-status read per visible run. Web needs the same
projection in the BFF, plus source on the lane summary.

#### A — gascity.el, Runs card (100 columns)

```text
  ⬣ Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el, default-theme scr…
     be-tnd3z  open    7/8 deliverables   ◆◆◆◆◆◆◆···   ● run-operator-1
     be-0kjzs  build-basic · beads.el · 3h · 5/10 steps · 45 beads
```

The source title (cut, full text in `help-echo`) replaces the anonymous
formula line; the formula and root move to the dim third line. Two
`build-basic` runs are now distinguishable at a glance. If the source read is
cold, the line renders `source loading…` (SWR) and never blocks the list.

#### A — gascity.el, run detail (100×35)

```text
  Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el,
  default-theme screenshots, black-box QA
  be-tnd3z  open            run be-0kjzs build-basic · beads.el · started 3h

  Deliverables  7/8 done · 1 in flight · 0 failed      SPC machinery   / filter   RET open
  ── Implementation ───────────────────────────────────────────────────────────────────────
  ◆ 1  Retarget the demo fixture to the shared /tmp/demo-project contract   be-rtqte  closed   3h
       └ do-work be-b9jhp  ◆◆◆  3/3  pass               RET run
  ◆ 2  Remove third-party themes from the capture/test path and rewrite th… be-95bl3  closed   2h
       └ do-work be-ybleu  ◆◆◆  3/3  pass               RET run
  ◆ 3  Complete the warning-free Texinfo node, menu, and xref structure     be-k8nn0  closed   2h
       └ do-work be-rtqoj  ◆◆◆  3/3  pass               RET run
  ◆ 4  Regenerate and verify every screenshot under Emacs default faces     be-vrjbu  closed   1h
       └ do-work be-wm8j0  ◆◆◆  3/3  pass               RET run
  ◆ 5  Complete reference, keybinding, and index coverage plus manual-vs-U… be-o597j  closed   1h
       └ do-work be-w7pjp  ◆◆◆  3/3  pass               RET run
  ◆ 6  Write the shared /tmp/demo-project walkthrough and Tested-with sect… be-gn247  closed  55m
       └ do-work be-s3joe  ◆◆◆  3/3  pass               RET run
  ◆ 7  Run the manual-only black-box QA pass and commit the report          be-7japy  closed  18m
       └ do-work be-sqrl5  ◆◆◆  3/3  pass               RET run
  ⬣ 8  Pin the new manual contracts in tests, add NEWS, land green gates    be-s61jf  open    19m
       └ do-work be-dhu31  ◆◆⬣  2/3  ⬣ close-source-…   ● run-operator-1
  ─────────────────────────────────────────────────────────────────────────────────────────
  Stages   ◆ Intake 5/5  ⬣ Implementation 0/2  · Review 0/1  · Approval 0/0  · Final 0/2
  Run      be-0kjzs · 45 beads · implementation convoy be-o4er1 7/8 · input be-hzrwd
  Machinery  prepare · requirements · plan · plan-review · decompose · summarize-implementation
             review · finalize · publish                    SPC fold   C control   T needs
  Keys     RET open   SPC drawer   I inspect   w copy   ! diagnose   g refresh   q bury
```

Reading order is the deliverable order. `RET` on a deliverable title opens the
business bead; `RET` on its `└ do-work` line opens the member run (text
properties distinguish the two things at point); `SPC` opens the member
inspector inline; `I` on the member opens its drawer; `w` copies the id at
point; `!` diagnoses the member without moving point. The existing step tree
remains below the `Machinery` header and is folded with `SPC`; `C` and `T`
keep their current meanings inside it, so no information is lost.

#### A — web, Runs card (≈72 columns)

```text
BEADS.EL
Implementation                                                 3h ago
Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el,
default-theme screenshots, black-box QA
be-tnd3z · 7/8 deliverables   ◆◆◆◆◆◆◆···
◆ Intake 5/5   ⬣ Implementation 0/2   · Review 0/1   · Approval 0/0   · Finalization 0/2
be-0kjzs  build-basic · 45 beads
────────────────────────────────────────────────────────────────────────────
```

The title link is the source feature; the formula becomes secondary metadata
at the bottom and appears once. On narrow screens the metadata line wraps
under the title; the stage ladder is already `flex-wrap`.

#### A — web, run detail (responsive: text column → stacked cards)

```text
Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el,
default-theme screenshots, black-box QA
be-tnd3z open · be-0kjzs build-basic · beads.el · started 3h ago

7 of 8 deliverables complete                       ◆◆◆◆◆◆◆···
── DELIVERABLES ────────────────────────────────────────────────────────────
◆ Retarget the demo fixture to the shared /tmp/demo-project contract
  be-rtqte closed · do-work be-b9jhp ◆◆◆ 3/3 pass
◆ Remove third-party themes from the capture/test path and rewrite theme captions
  be-95bl3 closed · do-work be-ybleu ◆◆◆ 3/3 pass
◆ Complete the warning-free Texinfo node, menu, and xref structure
  be-k8nn0 closed · do-work be-rtqoj ◆◆◆ 3/3 pass
◆ Regenerate and verify every screenshot under Emacs default faces
  be-vrjbu closed · do-work be-wm8j0 ◆◆◆ 3/3 pass
◆ Complete reference, keybinding, and index coverage plus manual-vs-UI spot check
  be-o597j closed · do-work be-w7pjp ◆◆◆ 3/3 pass
◆ Write the shared /tmp/demo-project walkthrough and Tested-with section
  be-gn247 closed · do-work be-s3joe ◆◆◆ 3/3 pass
◆ Run the manual-only black-box QA pass and commit the report
  be-7japy closed · do-work be-sqrl5 ◆◆◆ 3/3 pass
⬣ Pin the new manual contracts in tests, add NEWS, land green gates
  be-s61jf open · do-work be-dhu31 ◆◆⬣ 2/3 ⬣ close-source-…
  ● run-operator-1 · 20m
── RUN MACHINERY (collapsed) ───────────────────────────────────────────────
▸ 5/10 steps · 45 beads · Intake 5/5 · Implementation 0/2 · Review 0/1
  Approval 0/0 · Finalization 0/2 · formula build-basic · convoy be-o4er1 7/8
```

Above `md` this is a single readable column; below `md` the same DOM stacks
(item title, then the `be-… closed` line, then the member line), so no
information depends on horizontal position. The graph and stage inspector
move under the collapsed "Run machinery" disclosure, which keeps the
existing `Formula Graph` and node selection intact.

**Optimizes.** Learnability and recognizability: a new operator can answer
"what is this run for, what is left, who is on it" without knowing gc's
terminology. Best accessibility of the three (linear document order).

**Scales** to many items: one row per item, done items collapse to `◆ N done
· show`; `/` filters by state or text; stage headers remain. At 40+ items the
deliverable list is a scroll region with a sticky count.

**Trade-offs.**
- *Data:* Runs-card source needs one `gc convoy status` per visible run (TTL
  + dedup through the store; never on render). Detail is free (source already
  read; drain join is in-memory).
- *Async/no-spawn:* the card read must be a `gascity-store-use` keyed by
  `("convoy" "status" CONVOY)`, visible-first, with a placeholder line; no
  sync call in the render path.
- *Remote/TRAMP:* one extra async process per visible run over the existing
  pipe; TTL keeps it bounded; a failed read renders `source unavailable`
  rather than a fabricated title.
- *Emacs vs web lane:* Emacs first. The web needs the BFF deliverables
  projection (it cannot join bead metadata in the browser).

### Alternative B — Work ledger (paired what/how columns)

**Idea.** Keep the run as the unit, but render it as a reconciliation ledger:
one row per business deliverable, business side on the left, execution side on
the right, joined by a gutter and a verdict column (`matched`, `in flight`,
`drift`, `unstarted`). The page's job is to prove that every thing asked for
has exactly one thing being done for it — and to make a disagreement loud.

**Mapping.** Left side = the implementation convoy's member business beads, in
`gc.drain_index` order. Right side = the `do-work` member run root whose
`gc.drain_member_id` names that business bead, with its ladder, progress,
active step and worker. `drift` is a derived verdict: business closed while
the member has not passed, business open while the member passed, or a member
with no business item. The input convoy and source feature are header
provenance, not rows.

**New vs available.** All facts are already loaded in Emacs; the new work is
the join and the verdict rule. Web needs the same join in the BFF, and the
two-column layout must collapse to a stacked card under ~700px.

#### B — gascity.el, Runs card (100 columns)

```text
  ⬣ be-0kjzs  build-basic                                  beads.el   3h
     ledger  8 items · 7 matched · 1 in flight · 0 drift    source be-tnd3z
     ◆◆◆◆◆⬣····  implement  5/10   ● run-operator-1  be-dhu31
```

The third line is the new signal; `SPC` still opens the full step drawer, and
the ledger itself opens on `RET`.

#### B — gascity.el, run detail (100×35)

```text
  be-0kjzs  build-basic · beads.el · 3h · source be-tnd3z open · 7 matched · 1 in flight
  WHAT  business deliverable                      │ HOW  do-work member run              STATE
  ── Implementation ──────────────────────────────────────────────────────────────────────────
  ◆ be-rtqte  Retarget the demo fixture to the …  │ ◆ be-b9jhp   ◆◆◆ 3/3  pass            matched
  ◆ be-95bl3  Remove third-party themes from th…  │ ◆ be-ybleu   ◆◆◆ 3/3  pass            matched
  ◆ be-k8nn0  Complete the warning-free Texinfo…  │ ◆ be-rtqoj   ◆◆◆ 3/3  pass            matched
  ◆ be-vrjbu  Regenerate and verify every scree…  │ ◆ be-wm8j0   ◆◆◆ 3/3  pass            matched
  ◆ be-o597j  Complete reference, keybinding, a…  │ ◆ be-w7pjp   ◆◆◆ 3/3  pass            matched
  ◆ be-gn247  Write the shared /tmp/demo-projec…  │ ◆ be-s3joe   ◆◆◆ 3/3  pass            matched
  ◆ be-7japy  Run the manual-only black-box QA …  │ ◆ be-sqrl5   ◆◆◆ 3/3  pass            matched
  ⬣ be-s61jf  Pin the new manual contracts in t…  │ ⬣ be-dhu31   ◆◆⬣ 2/3  ⬣ close-src…    in flight
  ──────────────────────────────────────────────────────────────────────────────────────────
  Run flow   ◆ Intake 5/5   ⬣ Implementation 0/2   · Review 0/1   · Approval 0/0   · Final 0/2
  Reconcile  7 matched · 1 in flight · 0 drift · 0 unstarted      ! failures   w copy id
  Provenance  be-0kjzs build-basic · input convoy be-hzrwd · implementation be-o4er1 7/8
  Keys     RET side   SPC drawer   I inspect   w copy   ! failures   g refresh   q bury
```

`RET` on the left column opens the business bead; `RET` on the right column
opens the member run; `I` on the right opens the member drawer; `SPC` on
either side opens the corresponding inspector. The gutter is a real column
(`│`, already used by the inspector), not decoration.

#### B — web, Runs card (≈72 columns)

```text
BEADS.EL
Implementation                                                 3h ago
build-basic                        be-0kjzs
8 items · 7 matched · 1 in flight · 0 drift      source be-tnd3z
◆ Intake 5/5   ⬣ Implementation 0/2   · Review 0/1   · Approval 0/0   · Finalization 0/2
────────────────────────────────────────────────────────────────────────────
```

The formula is demoted to a metadata line and the ledger counts lead. The
source is named once; the card no longer repeats the title as the formula.

#### B — web, run detail (desktop table, mobile stacked cards)

```text
be-0kjzs build-basic · beads.el · 3h ago · source be-tnd3z
8 deliverables · 7 matched · 1 in flight · 0 drift

┌ WHAT (business) ─────────────────────┬ HOW (do-work run) ─────────────┬ STATE ────┐
│ ◆ Retarget the demo fixture…          │ ◆ be-b9jhp ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Remove third-party themes…          │ ◆ be-ybleu ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Complete the warning-free Texinfo…  │ ◆ be-rtqoj ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Regenerate and verify every screen… │ ◆ be-wm8j0 ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Complete reference, keybinding…     │ ◆ be-w7pjp ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Write the shared /tmp/demo-project… │ ◆ be-s3joe ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Run the manual-only black-box QA…   │ ◆ be-sqrl5 ◆◆◆ 3/3 pass        │ matched   │
│ ⬣ Pin the new manual contracts…       │ ⬣ be-dhu31 ◆◆⬣ 2/3 close-src… │ in flight │
└───────────────────────────────────────┴───────────────────────────────┴───────────┘
▸ Run flow  ◆ Intake 5/5 · ⬣ Implementation 0/2 · · Review 0/1 · · Approval 0/0 · · Finalization 0/2
```

At `md` the table becomes a 3-column grid; below `md` each row stacks as a
small card: title, `be-rtqte · closed`, `do-work be-b9jhp · ◆◆◆ 3/3 pass`,
then the state word. The state word is always present, so color is never the
only signal.

**Optimizes.** Correspondence and auditability. It is the only alternative
whose primary question is "is every deliverable actually being executed, and
do the two records agree?" — the question an operator asks when a run is
half-done or a bead closes without its work.

**Scales** linearly, one row per item; long runs need grouping by stage and
collapsing matched rows. The fixed 34-column title budget truncates more
aggressively than A; the member column is always visible, which is the point.

**Trade-offs.**
- *Data:* needs the reverse join plus a drift rule (a product decision, not a
  data fact). No new reads in the Emacs detail.
- *Async/no-spawn:* none in detail; the Runs card's ledger counts need the
  member roots and are already in the run index (no read).
- *Remote/TRAMP:* no extra reads; the same store payload backs both columns.
- *Accessibility:* the visual two-column layout must have a DOM/linear reading
  order of "business item, member run, state"; on Emacs, point movement is
  already linear and the gutter is a character, so this is natural. On web,
  the mobile stack must preserve that order.
- *Emacs vs web lane:* Emacs first; web is a real table/grid, which needs the
  BFF join.

### Alternative C — Stage board (flow lanes)

**Idea.** Render the run as a lifecycle board: stages are columns, and every
deliverable is a lane that sits in the column where it currently is. The
question is no longer "what is this step's parent" but "where is each
deliverable in the lifecycle, and what is next?" Run-level flow (intake,
review, finalization) occupies its own lanes above the deliverables.

**Mapping.** The implementation convoy's member business beads are lanes; a
lane's cell is its `do-work` member run, whose ladder/progress is the cell's
content. Intake/review/finalization are run-level lanes with the existing
step vocabulary. The source feature is the board's title; the two convoys are
the header's provenance.

**New vs available.** All board facts are in the Emacs run index already
(steps, member roots, business beads, stage table). The new work is the lane
projection and a fixed-width board layout. Web needs the BFF deliverables
projection (same as A/B) plus a horizontal board; it is the most natural
home for this alternative.

#### C — gascity.el, Runs card (100 columns)

```text
  ⬣ be-0kjzs  build-basic                              beads.el   3h
     stages ◆ 5/5  ⬣ 0/2  · 0/1  · 0/0  · 0/2   items 7/8   source be-tnd3z
     ◆◆◆◆◆⬣····  implement  5/10   ● run-operator-1  be-dhu31
```

The middle line is the stage board in miniature: five stage glyphs and
anchor counts (matching the detail rail's `Stages` line), plus the
deliverable count and the source.

#### C — gascity.el, run detail (100×35)

```text
  be-0kjzs build-basic · source be-tnd3z · 7/8 items · 3h       SPC machinery   RET open
  Lane                      │ Intake  5/5   │ Implementation  │ Review  0/1   │ Finalization 0/2
                            │               │ 7/8 items       │               │
  Run flow                  │ ◆ 5/5 steps   │ ⬣ drain be-9sbk2│ ▸ loop be-thq3n│ · 0/2
  ────────────────────────────────────────────────────────────────────────────────────────
  ◆ be-rtqte  Retarget the… │               │ ◆ 3/3 be-b9jhp  │ ·             │ ·
  ◆ be-95bl3  Remove thir…  │               │ ◆ 3/3 be-ybleu  │ ·             │ ·
  ◆ be-k8nn0  Complete th…  │               │ ◆ 3/3 be-rtqoj  │ ·             │ ·
  ◆ be-vrjbu  Regenerate …  │               │ ◆ 3/3 be-wm8j0  │ ·             │ ·
  ◆ be-o597j  Complete re…  │               │ ◆ 3/3 be-w7pjp  │ ·             │ ·
  ◆ be-gn247  Write the s…  │               │ ◆ 3/3 be-s3joe  │ ·             │ ·
  ◆ be-7japy  Run the man…  │               │ ◆ 3/3 be-sqrl5  │ ·             │ ·
  ⬣ be-s61jf  Pin the new…  │               │ ⬣ 2/3 be-dhu31  │ ·             │ ·
  ────────────────────────────────────────────────────────────────────────────────────────
  Stages   ◆ Intake 5/5  ⬣ Implementation 0/2  · Review 0/1  · Approval 0/0  · Final 0/2
  Legend   ◆ done  ⬣ active  · pending/not tracked   SPC cell   RET lane   w copy
  Keys     RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

At 100 columns the five stages cannot all be columns with readable titles;
the board uses four columns for the stages where deliverables live and keeps
Approval in the stage rail (it is a run-level gate with `0/0` here). The
`7/8 items` line is the deliverable count, while the `Stages` rail's
`Implementation 0/2` counts the formula's anchors; they answer different
questions and are labeled separately. Deliverables only occupy an
Implementation cell today; the Review and Finalization cells fill in when
per-item review/fix steps exist. `RET`
on a lane label opens the business bead; `RET` on a cell opens the member
run; `SPC` on a cell opens the member inspector. The existing step tree
stays below the board, folded, so `C` and `T` keep their meanings. The board
is an overview; it does not try to show every control node.

#### C — web, Runs card (≈72 columns)

```text
BEADS.EL
Implementation                                                 3h ago
build-basic · be-0kjzs · source be-tnd3z
stages ◆ 5/5  ⬣ 0/2  · 0/1  · 0/0  · 0/2       items 7/8
◆ Intake 5/5   ⬣ Implementation 0/2   · Review 0/1   · Approval 0/0   · Finalization 0/2
────────────────────────────────────────────────────────────────────────────
```

#### C — web, run detail (kanban: horizontal scroll on small screens)

```text
build-basic · be-0kjzs · source be-tnd3z · beads.el · 3h ago · 7/8 items
┌ Intake 5/5 ─────┬ Implementation 7/8 ┬ Review 0/1 ─────┬ Approval 0/0 ┬ Finalization 0/2 ┐
│ ◆ prepare       │ ◆ be-rtqte  3/3    │ ▸ review loop   │ (none)       │ · finalize       │
│ ◆ requirements  │ ◆ be-95bl3  3/3    │                 │              │ · publish        │
│ ◆ plan          │ ◆ be-k8nn0  3/3    │                 │              │                  │
│ ◆ plan-review   │ ◆ be-vrjbu  3/3    │                 │              │                  │
│ ◆ decompose     │ ◆ be-o597j  3/3    │                 │              │                  │
│                 │ ◆ be-gn247  3/3    │                 │              │                  │
│                 │ ◆ be-7japy  3/3    │                 │              │                  │
│                 │ ⬣ be-s61jf  2/3    │                 │              │                  │
└─────────────────┴────────────────────┴─────────────────┴──────────────┴──────────────────┘
▸ Run flow · Formula Graph · steps (collapsed)
```

Each card shows the business title, its id and its member run's ladder; the
card is a link to the deliverable, with a secondary link to the member run.
Below `md` the columns become a horizontally scrollable strip with snap
points (the standard kanban fallback); below `sm` they stack as sections with
the stage label repeated. DOM order is stage-major so a screen reader hears
"Intake: five done; Implementation: eight items, seven done, one active; …".

**Optimizes.** Flow and position. It is the best answer to "where are we,
what is next, what is stuck in this stage" and the best use of the web's
width. It also makes the per-stage totals (`5/5`, `0/1`, `0/0`, `0/2`)
directly readable instead of hidden in a header rail.

**Scales** to many items within a stage by scrolling a column; across stages
by keeping the five columns fixed. At 100 Emacs columns, lane titles are
truncated hard (12 characters), so the board is an overview that needs `RET`
for detail; on the web, cards carry full titles. With 40+ items the
Implementation column becomes a scroll region with a count and `/`-style
filter, not 40 cards in one viewport.

**Trade-offs.**
- *Data:* Emacs needs only the existing index; web needs the BFF deliverables
  projection (business item + member root + ladder + state).
- *Async/no-spawn:* no new reads. The board re-projects the loaded payload, so
  `g`/live refresh keeps folds and lane positions.
- *Remote/TRAMP:* identical to A/B: no synchronous stat, no extra gc call on
  render.
- *Accessibility:* the board is the weakest of the three spatially. Every cell
  must carry a word (`done`, `running`, `pending`), each column a stage label,
  and the DOM order must be stage-major; mobile must stack, not shrink.
- *Emacs vs web lane:* **web first.** The board's value comes from width and
  cards; doing it in Emacs first would spend the most effort for the least
  legible result. Emacs gets a compact matrix later (or never) if the web
  board proves the IA.

## 3. Comparison and recommendation

### 3.1 Comparison

| | A Business spine | B Work ledger | C Stage board |
| --- | --- | --- | --- |
| Primary question | "What feature is this, and what is left?" | "Does every deliverable have exactly one execution, and do they agree?" | "Where is each deliverable in the lifecycle, and what is next?" |
| Information architecture | Document: feature → deliverables → member runs → provenance | Table: what ↔ how, with a verdict column | Board: stage columns × deliverable lanes |
| Learnability | Highest: business vocabulary first; formula last | High for mapping, but the two columns and verdict need a legend | Medium: stage vocabulary is already known; lane/cell reading needs a legend |
| Density | Medium (2 lines per item) | Highest (1 line per item) | Medium-low in Emacs (hard truncation), high on web |
| Drill-down | `RET` title / `RET` member; `SPC`/`I` member drawer; `SPC` machinery fold, `C` control | `RET` per column; `SPC` per side; `!` failures | `RET` lane / `RET` cell; `SPC` cell; `SPC` machinery fold |
| Emacs implementation cost | **Low**: reverse drain join + reorder + source card read | **Low-medium**: join + drift rule + two-column renderer | **Medium-high**: new board renderer, cell properties, truncation rules |
| Web implementation cost | Medium: BFF deliverables + hero + card de-dup | Medium: same projection + responsive table | Medium-high: same projection + board with horizontal scroll/snap |
| Data risk | Low: source read on the card is the only new read | Low: join + a product rule (drift) | Low-medium: the lane projection and stage-major DOM |
| Failure mode | A long feature title dominates; done items still need collapsing | Dense; long titles truncate; drift rule can be argued | Emacs board is unreadable for long titles; mobile board can become a horizontal trap |
| Accessible order | Strongest (linear document) | Good if rows read "business, member, state" | Weakest spatially; needs explicit words + DOM order |

### 3.2 Recommendation

**Build A first in gascity.el.** It is the smallest honest change with the
largest comprehension gain:

1. The source read already exists (`gascity-run--source`), so the detail's
   first question — *what feature is this run for?* — is one layout change
   away.
2. The business↔member join is a pure addition to `gascity-runs-index`
   (`gc.drain_member_id` → member root). No new gc call, no new parser, no
   change to the store.
3. The Runs card's source line is the only new read, and it fits the existing
   store/TTL/scheduler contract; it can ship with a placeholder and a
   `source unavailable` state.
4. It changes no keys and no stage vocabulary, so it is testable with the
   existing render harness and screenshot fixture.

**The Go/web lane owns the deliverables projection and the board.** Add one
read-only `deliverables` projection to the run summary/detail DTO: source
bead, input/implementation convoy identity, and per-item `{business bead, member
root, ladder, state, worker}` plus counts. The BFF already joins bead and
session data for detail; this is the same kind of join, done once on the
server so Emacs and the browser agree. On top of that projection:

- Web run card: de-duplicate the formula, lead with the source, show the
  deliverable count (A) or the ledger counts (B).
- Web detail: A's hero/deliverable column is the safest first web change
  because it reuses the detail's existing node data plus the new projection.
- Web C board: second web step. The board is the strongest use of the web's
  width, but it must not be built until the projection exists; otherwise it
  would repeat the current defect in a prettier layout.

**B is a refinement, not a first build.** Its same-line pairing is the right
treatment for A's deliverable row; the drift verdict is the only genuinely
new concept. If the team wants one layout, implement A's row as B's two
columns and skip a separate B view. If not, add B as a second layout
selected from the run view's existing `/` menu after A lands (it would
otherwise need a new key, which this design avoids).

### 3.3 Phased rollout

0. **Go/BFF (both lanes).** `deliverables` projection on run detail; `source`
   + deliverable counts on the run summary lane; de-duplicate the run card's
   title/formula. Acceptance: `be-0kjzs` returns `be-tnd3z` as source and the
   eight pairs above; a run with no drain members returns an empty
   deliverables list and the UI omits the section.
1. **Emacs A, detail.** Source as headline, deliverable spine, paired member
   line, machinery below and folded (`C` still controls its control nodes),
   provenance footer. Add the reverse drain map
   to `gascity-runs-index`; no new read. Update the manual's Run Detail
   section and the deterministic screenshot fixture.
2. **Emacs A, Runs card.** Source title/id line through the store with a
   placeholder; `SPC` keeps the drawer; `RET` opens the run. Acceptance in
   tmux and against the TRAMP test city `bright-lights`.
3. **Emacs polish.** Collapse completed deliverables, `/` filter, `w`/`I`/`!`
   on the correct half of a row, TTY and greyscale checks.
4. **Web A.** Hero + deliverable cards + machinery disclosure; fix the stage
   ladder disagreement (acceptance below).
5. **Web C.** Stage board tab/section on top of the deliverables projection;
   responsive horizontal strip; stage-major DOM order.
6. **Emacs C (optional).** A compact board as an optional detail layout (no
   new key) only if the web board proves it; otherwise leave Emacs with A/B.

## 4. Open questions

1. **Source resolution.** `gc.var.convoy_id` can name a convoy with zero,
   one, or many tracked members. Today Emacs shows the first; what should a
   multi-member input convoy show? (Recommend: the convoy itself as the
   title, with "tracks N beads"; only a single member becomes the headline.)
2. **Two convoys, one name.** `gc.var.convoy_id` is the input convoy;
   `gc.input_convoy_id` / `gc.build.implementation_convoy_id` is the
   implementation convoy. The UI needs fixed words ("input" / "implementation")
   before any of these designs ships; the current generic `convoy` row is a
   trap.
3. **Drain policy.** With `drain_policy = inline`, there are no member runs;
   with `separate`, every item should have one. What does the deliverable row
   show for an item with no member root yet: `unstarted`, `not dispatched`,
   or nothing? (Recommend an explicit word, never a fabricated run.)
4. **Drift.** Define the verdict precisely: business `closed` + member
   `gc.outcome != pass`; business `open` + member pass; member with no
   business item; business with two members. Is drift a warning or an error?
5. **One-call principle.** Should `gc` expose `run deliverables --json`
   instead of the BFF joining bead metadata? The server join duplicates
   knowledge of `gc.drain_*` keys; a gc projection would keep that knowledge
   in one place and serve both surfaces. This is the largest architectural
   question in the document.
6. **Summary weight.** `runs/summary` is already 53 KB for 5 lanes. Full
   deliverables for every lane would grow it; counts only in the summary and
   the full list in detail is the likely compromise.
7. **Cross-store members.** A member root names `gc.root_store_ref`; can it
   differ from the parent's? If yes, the join must read both stores and the
   per-city buffer identity rules apply.
8. **Approval 0/0.** Is an empty stage meaningful in a board? Keep it (the
   manual's contract) but do not let `0/0` read as "failed".
9. **Naming.** "Deliverable", "business item", "work item", "bead" — pick one
   word for the UI and use it in both surfaces. The bead is the data; the
   user's unit is the deliverable.
10. **Live updates.** Does a member root's event invalidate the parent detail
    today? If not, A/B/C all need the parent view to refresh on member events,
    or the per-item progress will be stale while the page claims to be live.

## 5. Acceptance checks for a later implementation

These are the checks the eventual implementation should satisfy; they are
written so they can be copied into the bead's verification section.

1. **Truthful pairing.** With the live `emacs-city` run `be-0kjzs`, the
   deliverable view shows exactly these pairs and no others:
   `be-rtqte↔be-b9jhp`, `be-95bl3↔be-ybleu`, `be-k8nn0↔be-rtqoj`,
   `be-vrjbu↔be-wm8j0`, `be-o597j↔be-w7pjp`, `be-gn247↔be-s3joe`,
   `be-7japy↔be-sqrl5`, `be-s61jf↔be-dhu31`. The last row reads `2/3` and
   `close-source-…`; the first seven read `3/3 pass`. No id is invented.
2. **No source, no lie.** A run whose root has no `gc.var.convoy_id`, or
   whose convoy cannot be resolved, renders without a headline source (or
   with an honest `source unavailable`), not with the formula as a fake
   source.
3. **Stage agreement.** The stage ladder, the run card and the deliverable
   counts agree with the step nodes for the same run, and Emacs and the web
   agree on `Intake 5/5`. (Today they do not; this is a prerequisite.)
4. **Runs card identity.** Two active `build-basic` runs are distinguishable
   by source title/id in both surfaces; the formula appears once per card.
5. **Non-blocking.** No synchronous `gc` call on render, redisplay, timers or
   eldoc; the Runs card's source read is async, TTL'd, deduped, and
   visible-first; a cold read shows a placeholder, and a failed read shows
   `source unavailable`. The ERT non-blocking guard is updated if a new
   input-free verb is added (none is expected).
6. **Remote.** Open the same views against `/ssh:localhost:~/bright-lights`
   from a fresh tmux Emacs; the layout, pairing and source render identically,
   and no render path stats a file or spawns a blocking process over TRAMP.
7. **Keys and folds.** `RET`, `SPC`, `C`, `I`, `w`, `!`, `g`, `q` keep their
   current meanings at the new objects; `g` and live refresh keep point and
   folds; the needs toggle (`T`) still restores the flat layout byte-for-byte.
8. **Accessibility.** In greyscale, every state has a word as well as a glyph;
   the web's mobile stack preserves the reading order business → member →
   state; the board's DOM is stage-major and each cell names its stage.
9. **Scale.** With 40 deliverables the Emacs list collapses completed rows and
   keeps the active one visible; the web board scrolls a column, not the whole
   page; the `/` filter still works.
10. **Docs and gates.** `doc/gascity.texi`'s Run Detail section and the
    deterministic screenshot fixture are updated; `scripts/gate.sh` and
    `scripts/lint.sh` pass; the web tests cover the new projection and the
    responsive card/table states.

## Appendix — evidence

### A.1 Metadata that makes the mapping

Run root `be-0kjzs` (live `gc bd show --json`):

```text
gc.kind=workflow                      gc.formula_name=build-basic
gc.root_store_ref=rig:beads.el        gc.var.rig_name=beads.el
gc.var.convoy_id=be-hzrwd             gc.input_convoy_id=be-o4er1
gc.build.implementation_convoy_id=be-o4er1
gc.graphv2_root_key=graphv2-root:be-hzrwd:build-basic:0a9a02d13936aa1b:default
```

Member root example `be-b9jhp`:

```text
gc.kind=workflow                      gc.formula_name=do-work
gc.drain_control_id=be-9sbk2          gc.drain_member_id=be-rtqte
gc.drain_index=0                      gc.drain_count=8
gc.outcome=pass                       gc.var.issue=be-rtqte
gc.item_root_key=drain-item-root:be-9sbk2:0:be-rtqte
```

`be-dhu31` is the same shape with `drain_index=7`, `drain_member_id=be-s61jf`,
no `gc.outcome` yet, and `gc.session_name=gc__implementation-worker-…`.
This is the entire join; no naming convention or position is needed.

### A.2 Live web payload (trimmed)

`GET /api/city/emacs-city/runs/summary` (lane `be-0kjzs`):

```text
title build-basic · formula build-basic · scope rig:beads.el
phase active · phaseLabel Implementation
statusCounts {open:23, closed:15, in_progress:1}
stages [Intake pending, Implementation active, Review pending,
        Approval pending, Finalization pending]
progress {status: active_step, stepId: build-basic, stage: Implementation}
```

`GET /api/city/emacs-city/runs/be-0kjzs/detail`:

```text
runId be-0kjzs · rootBeadId be-0kjzs · title build-basic
formula build-basic · rootStoreRef rig:beads.el
progress {totalNodeCount:27, visibleNodeCount:27, edgeCount:63,
          statusCounts:{active:1, completed:12, pending:14}}
nodes: run root + 18 step/check-loop/control nodes + 8 business beads (be-rtqte … be-s61jf)
edges: 63 `blocks` edges
no source, no convoy, no drain member roots, no gc.drain_* fields
```

The eight business beads are nodes with `constructKind: "step"`, so the graph
cannot distinguish "a step of this run" from "a business item executed by a
separate member run". The member roots are absent from the payload entirely.

### A.3 Reproduction notes

- Emacs capture: fresh `emacs -nw -Q`, `lisp/` of gascity.el and beads.el on
  `load-path`, default-directory `/home/roman/emacs-city`, `M-x
  gascity-runs`, `RET` on `be-0kjzs`, `C` to show control nodes. Pane size
  120×40; the mockups above are drawn at 100 columns per the brief.
- Web evidence: the SPA at `http://127.0.0.1:8372/city/emacs-city/runs` and
  the BFF endpoints above; the SPA's `LaneCard.tsx`, `FormulaRunDetail.tsx`,
  `RunMetadata`, `StageLadder.tsx` and `FormulaRunDiagram.tsx` were read to
  confirm the rendered structure. No state was mutated.
- No manual `build-basic` worktree was touched.
