# Run rendering: three formula-agnostic alternatives

Status: design spike, design only. No lisp, Go or web changes accompany this
document.
Bead: `ga-p1gss` (revision of `ga-zp2v9`; the original spike is commit
`2ccab5a`).
Date: 2026-11-09.
Surfaces: the gascity.el Runs view (`*gascity-runs:CITY*`) and run detail
(`*gascity-run:ID*`), and the web dashboard's `/city/CITY/runs` and
`/city/CITY/runs/ID` pages.

This revision removes the original spike's dependence on formula-specific
stage tables. The design must work for **any** graph.v2 formula. A formula's
stage table, when one exists, is optional enrichment at most: it may add
header text, but it may not define the information architecture, the row
order, the grouping, or the set of facts the page needs. A formula without a
stage table is the normal case, not a degraded exception.

Three worked examples are used throughout:

| case | run | formula | drain | source | stage table |
| --- | --- | --- | --- | --- | --- |
| rich | `be-0kjzs` (emacs-city, live) | `build-basic` | separate, 8 members | `be-tnd3z` | present (optional) |
| flat | `ga-4hdav` (gascity.el, closed) | `do-work` | none | `ga-mszco` | absent |
| standalone | `ga-6iwrx` (gascity.el, closed) | `review` | none | none | absent |

The rich case is the live run from the original spike. The flat and
standalone cases are real runs from the gascity.el store, chosen because they
have no stage table and no drain; the standalone case also has no input
convoy. Their ids are real; the mockups use their real step titles and
outcomes. An inline-drain variant (a drain step with no member roots) is drawn
where it changes the layout.

## 1. Model

The model is the complete set of inputs the design may require. Everything
below is engine-generic graph.v2 data. No formula name, stage name, stage
table, `mol-*` table, phase grammar, or per-formula layout rule is an input.

### 1.1 Primitives

| primitive | where it comes from | required? | notes |
| --- | --- | --- | --- |
| run root `R` | a bead with `gc.kind=workflow` that is not a drain member (no `gc.drain_control_id`) | yes | the run's identity |
| graph `G(R)` | every bead whose `gc.root_bead_id` is `R.id` | yes | steps, iterations, checks, drains, control nodes, and sometimes business items |
| node fields | each bead: `id`, `title`, `status`, `gc.kind`, `gc.step_ref`, `gc.step_id`, `gc.attempt`, `gc.logical_bead_id`, `dependencies`, `gc.outcome`, timestamps | as present | missing fields are omitted, never invented |
| structural tree | `gc.step_ref` prefix nesting; iteration/attempt beads attach through `gc.logical_bead_id` | yes | a step's children are the beads whose ref is beneath it |
| order | `blocks` dependencies; `tracks` and `parent-child` are fallbacks when `blocks` is absent | yes | topological, cycle-guarded |
| node kind | `gc.kind` | yes | see §1.2 |
| status | `status` + `gc.outcome` | yes | done / active / pending / failed |
| drain node `D` | a node with `gc.kind=drain` | optional | a drain may be inline (no member roots) |
| member root `M` | a workflow root whose `gc.drain_control_id` is `D.id` | optional | lives outside `G(R)` |
| deliverable pair `(B, M)` | `M.gc.drain_member_id` names business bead `B`; `gc.drain_index`/`gc.drain_count` order the members | optional | `B` may be in the same or another store; a `B` may have 0, 1 or N `M` |
| source | root `gc.var.convoy_id` → convoy status → tracked members | optional | exactly one member is a source bead; zero or many is a convoy label/count; absent is no source |
| implementation convoy | root `gc.input_convoy_id` or `gc.build.implementation_convoy_id` | optional | provenance only; not the source |
| provenance | `gc.formula_name`, `gc.formula_contract`, `gc.root_store_ref`, scope, plans, `gc.formula_source` | display only | root and store are required; the rest is omitted when absent |
| stage table | a formula-provided ordered list of stage labels and step ids | optional | enrichment only; never structural |

### 1.2 Node kinds

`gc.kind` is the only kind vocabulary the design uses. Unknown kinds are
rendered as work, not dropped.

| kind | role in the model | default rendering |
| --- | --- | --- |
| `workflow` | run root (or a workflow latch) | header, not a row |
| `step` | a work node | a work row |
| `ralph` | a looping work node; its iterations are children | a work row with an iteration badge |
| `check` | a check attached to a work node | a badge/child, not a top-level row |
| `drain` | a work node whose members are separate runs | a work row; deliverables nest beneath it when members exist |
| `scope`, `scope-check`, `workflow-finalize` | control/gate nodes | folded under `C`; never a work row |
| anything else | unknown | a work row, with its kind shown as a badge |

Iteration and attempt beads are not separate work rows. They attach to the
node named by `gc.logical_bead_id` (or by the `gc.step_ref` prefix when that
is absent) and contribute to its attempt/check badge.

### 1.3 Derived concepts

- **Work unit.** A top-level work node, or a deliverable when its drain has
  member roots. This is the unit the page counts and the user acts on. A
  drain with no member roots is one work unit (the drain itself); it does not
  invent per-item rows.
- **Progress.** Counts over work units, plus separate counts over steps and
  beads. The three denominators are always labeled; they are never mixed.
- **Deliverable state.** When both `B` and `M` exist: `matched` (both agree),
  `in flight` (member active), `drift` (the two records disagree), or
  `unpaired` (one side missing). When only one side exists, the row shows the
  plain state (`done`, `active`, `pending`, `failed`) and never a verdict.
- **Source.** The input convoy's tracked members. One member → the source
  bead. Zero or many → the convoy itself with a count. No input convoy → no
  source row. The formula is never used as a fake source.
- **Bands.** The dependency rank of a top-level work node: the longest
  `blocks` path from a root of the top-level DAG. Bands are the only generic
  grouping primitive. They are derived, not authored.
- **Provenance.** Root, store, formula name/contract, scope, plans, formula
  source, input convoy, implementation convoy. Display-only; absent facts are
  omitted.

### 1.4 Ordering and grouping

**Default order is a flat dependency-ordered tree.** Top-level work nodes are
sorted by `blocks` depth, then by their authored `gc.step_ref`/`gc.step_id`
as a stable tiebreak. Nested nodes follow their parent. Control nodes are
folded. This is the fallback for every formula and the only order the design
requires.

**Grouping is optional and decorative.** Two generic groupings may add
headers without changing the order or membership:

1. **Rank bands.** If a rank contains more than one top-level work node, a
   `Band N` header may be inserted. A linear chain has one node per rank and
   may be rendered without headers at all.
2. **Formula stage table.** If the formula supplies one, its labels may be
   placed above contiguous runs of the derived order. A step the table does
   not name stays in the flat order under `Other` or no header. The table may
   not reorder, split, or hide a step, and a formula without one is not a
   special case.

**Board columns (Alternative C) are rank bands.** Column 1 is rank 0, column
2 is rank 1, and so on. A stage table may replace a column label only when
the stage covers a contiguous range of ranks; otherwise the column keeps its
rank label and the stage name, if any, is a badge. No formula-specific column
set is ever required.

### 1.5 Required vs optional

| required for every run | optional, omitted or degraded gracefully |
| --- | --- |
| run root, graph, node fields, structural tree, order, node kind, status | drain node and member roots |
| root id and store ref | deliverables and their business beads |
| | source / input convoy |
| | implementation convoy |
| | formula name/contract, plans, formula source, scope |
| | stage table |
| | worker/session, timestamps, artifacts |

A design that cannot render a run with only the left column is wrong. A
design that treats the right column as required is also wrong.

### 1.6 What the design must not assume

- No formula name list, no `build-basic`/`build-base` table, no `mol-*`
  table, no Intake/Implementation/Review/Approval/Finalization vocabulary.
- No web phase grammar and no `stagesForFormula` mapping.
- No drain, no member roots, no business beads, no input convoy, no
  implementation convoy, no source.
- No per-formula layout selector. One default layout must serve every
  graph.v2 formula; optional enrichment may change labels, not structure.

## 2. Current state critique

### 2.1 What works and should survive any redesign

- **One ladder vocabulary.** `◆` done, `⬣` active, `·` pending, `✕` failed,
  `▸`/`▾` folds, `└` member nesting. It reads in greyscale and stays legible
  at 100 columns. All three alternatives keep it.
- **The flat dependency-ordered tree already exists.** `gascity-run-stage`
  returns nil for a formula with no table, and the run detail keeps its flat
  step table. That fallback is the right default; the redesign promotes it
  instead of treating it as an exception.
- **The header is provenance, not invention.** Root, store, scope, source,
  formula, key, formula source, plans and convoy come from the run root's own
  metadata; absent facts are omitted. The `source` row (commit `223e0d7`) is
  the first outcome-oriented fact on the page.
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

### 2.2 What the user must already know today

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
9. The stage headers (`Intake`, `Implementation`, …) are not gc data. They
   come from an Emacs-authored table in `gascity-run-stage.el` (a port of
   gc's `stagesForFormula` plus a local `build-basic` entry). A formula
   outside that table already renders a different page: the flat step table.
   The web has its own phase grammar. The two surfaces can disagree, and a
   new formula gets no stages at all.

### 2.3 Observed cross-surface defects worth fixing regardless

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
- **The IA is formula-specific.** A run with a stage table gets stage groups;
  a run without one gets a flat table. The same page therefore has two
  information architectures, and the richer one is unavailable to most
  formulas. The web's phase grammar is a third, independent mapping.

### 2.4 Data that exists but is not surfaced

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
| dependency ranks | `blocks` edges in the graph | generic bands/columns | computed for the ladder, not shown as structure |

### 2.5 What this means for the design

The pages are rich in *execution* facts and poor in *deliverable* facts. The
root/formula is treated as the identity; the business feature is a row; the
8 deliverables and their 8 member runs are two parallel lists with no join.
A redesign should not add more execution detail. It should make the work unit
— a deliverable when one exists, otherwise a step — the unit of reading, and
derive execution detail from it. The same layout must work when there is no
drain, no source, and no stage table.

## 3. Three alternatives

All three are defined over §1's model. They keep the existing glyphs and add
no new keys: `RET`, `SPC`, `C`, `I`, `w`, `!`, `g`, `q` keep their meanings
("object at point" changes with the layout). Web mockups are drawn at about
72 columns to represent a 560–720 px card; the responsive rules are stated
per alternative.

Shared rules:

- **Order is always the flat dependency-ordered tree.** Optional headers may
  label contiguous runs; they never reorder rows.
- **A work unit is a deliverable when its drain has member roots, otherwise
  the work node itself.** A drain with no member roots is one row, not an
  empty section.
- **Absent data is omitted, never fabricated.** No source → no source row. No
  drain → no deliverables section. No stage table → no stage headers. A
  failed read shows `unavailable`, not a guessed value.
- **The three denominators are labeled.** Steps, work units/deliverables, and
  beads are never mixed in one count.
- **The stage table is optional enrichment.** When present it may add header
  text; when absent the page is identical in structure.

### Alternative A — Work spine (outcome-first hierarchy)

**Idea.** Make the run's outcome the page, and the machinery a footnote. The
source feature is the headline when it exists; the body is the run's work
units in dependency order. A drain's deliverables are first-class rows with
their member run nested immediately beneath them; a run with no drain shows
its work nodes as the same rows. The formula, root, key, plans and convoys
become a provenance block at the bottom, and the existing step tree stays
below it, folded under a `Machinery` header (`SPC` folds it; `C` still shows
its control nodes and `T` its needs tree). "What is being delivered" is
answered before "which formula is running".

**Mapping.** Source (`gc.var.convoy_id` → one tracked member) → work units in
dependency order → for a drain with members, each deliverable `(B, M)` in
`gc.drain_index` order, business title first and member run nested → for a
drain without members, the drain row itself → for no drain, the work nodes.
Optional stage headers may label contiguous runs. The member line is the
execution half of the same deliverable, not a separate list.

**New vs available.** The only new Emacs data is the reverse drain map (a
hash built from the already-loaded bead graph: `gc.drain_member_id` →
member root) plus the source read on the Runs card. The join is in-memory;
the card read is one convoy-status read per visible run. Web needs the same
projection in the BFF, plus source on the lane summary. No stage table is
needed.

#### A — gascity.el, rich run detail (100×35)

```text
  Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el,
  default-theme screenshots, black-box QA
  be-tnd3z  open            run be-0kjzs build-basic · beads.el · started 3h

  Work  5/10 steps · 7/8 deliverables · 1 in flight · 0 failed
  ─────────────────────────────────────────────────────────────────────────────
  ◆ prepare                 be-nasax  pass      ec                        3h
  ◆ requirements            be-8lclw  iter 1    ec                        3h
  ◆ plan                    be-rexyi  iter 1    ec                        3h
  ◆ plan-review             be-w4zzs  pass      ec                        3h
  ◆ decompose               be-bbp6v  iter 1    ec                        3h
  ⬣ implement               be-9sbk2  drain 7/8 · 1 in flight             3h
    ◆ 1  Retarget the demo fixture to the shared /tmp/demo-project contract
         be-rtqte  closed    └ do-work be-b9jhp  ◆◆◆ 3/3 pass
    ◆ 2  Remove third-party themes from the capture/test path and rewrite th…
         be-95bl3  closed    └ do-work be-ybleu  ◆◆◆ 3/3 pass
    ◆ 3  Complete the warning-free Texinfo node, menu, and xref structure
         be-k8nn0  closed    └ do-work be-rtqoj  ◆◆◆ 3/3 pass
    ◆ 4  Regenerate and verify every screenshot under Emacs default faces
         be-vrjbu  closed    └ do-work be-wm8j0  ◆◆◆ 3/3 pass
    ◆ 5  Complete reference, keybinding, and index coverage plus manual-vs-U…
         be-o597j  closed    └ do-work be-w7pjp  ◆◆◆ 3/3 pass
    ◆ 6  Write the shared /tmp/demo-project walkthrough and Tested-with sect…
         be-gn247  closed    └ do-work be-s3joe  ◆◆◆ 3/3 pass
    ◆ 7  Run the manual-only black-box QA pass and commit the report
         be-7japy  closed    └ do-work be-sqrl5  ◆◆◆ 3/3 pass
    ⬣ 8  Pin the new manual contracts in tests, add NEWS, land green gates
         be-s61jf  open      └ do-work be-dhu31  ◆◆⬣ 2/3 ⬣ close-source-…  ● run-operator-1
  · summarize-implementation be-o4q0j  iter 1                             3h
  · review                  be-thq3n  loop                                3h
  · finalize                be-8t31o  iter 1                             3h
  · publish                 be-eyn10                                      3h
  ─────────────────────────────────────────────────────────────────────────────
  Run      be-0kjzs · 45 beads · formula build-basic · implementation convoy be-o4er1 7/8
  Source   input convoy be-hzrwd · 1 tracked member
  Machinery  control nodes folded (C) · needs tree (T) · SPC fold
  Keys     RET open   SPC drawer   I inspect   w copy   ! diagnose   g refresh   q bury
```

Reading order is the work-unit order. `RET` on a deliverable title opens the
business bead; `RET` on its `└ do-work` line opens the member run (text
properties distinguish the two things at point); `SPC` opens the member
inspector inline; `I` on the member opens its drawer; `w` copies the id at
point; `!` diagnoses the member without moving point. The existing step tree
remains below the `Machinery` header and is folded with `SPC`; `C` and `T`
keep their current meanings inside it, so no information is lost. If the
formula supplies a stage table, headers such as `Intake`/`Implementation` may
be inserted above contiguous runs; the rows and order do not change.

#### A — gascity.el, flat case (no stage table, no drain)

`ga-4hdav`, a failed `do-work` run with a source and no drain:

```text
  drain unit 6 for ga-tx45i
  ga-mszco  closed          run ga-4hdav do-work · gascity.el · 2h

  Work  2/3 steps · 0 in flight · 1 failed
  ─────────────────────────────────────────────────────────────────────────────
  ◆ prepare item worktree        ga-2ee5m  pass
  ✕ implement owned work         ga-bt89r  skipped · iteration ga-u565r fail
  ✕ close owned source anchor    ga-4yee3  fail
  ─────────────────────────────────────────────────────────────────────────────
  Run      ga-4hdav · 6 beads · formula do-work · no drain members
  Source   input convoy ga-mszco · 1 tracked member
  Machinery  workflow-finalize ga-ihghs (control, folded)
  Keys     RET open   SPC drawer   I inspect   w copy   ! diagnose   g refresh   q bury
```

The same layout, with no stage headers and no deliverable section. The
`implement` row is a `ralph` node; its failed iteration is a badge, not a
separate row.

#### A — gascity.el, standalone case (no source, no drain)

`ga-6iwrx`, a `review` run with no input convoy:

```text
  review
  (no source)               run ga-6iwrx review · gascity.el · 1d

  Work  2/2 steps · 0 in flight · 0 failed
  ─────────────────────────────────────────────────────────────────────────────
  ◆ validate report context      ga-ed78s  pass
  ◆ write review report          ga-w3xz7  pass · iteration ga-f1ctf pass
  ─────────────────────────────────────────────────────────────────────────────
  Run      ga-6iwrx · 5 beads · formula review · no drain members
  Source   none (root has no gc.var.convoy_id)
  Machinery  workflow-finalize ga-its4e (control, folded)
  Keys     RET open   SPC drawer   I inspect   w copy   ! diagnose   g refresh   q bury
```

The headline falls back to the formula/root title; there is no fake source.
The body is the same flat tree.

**Inline drain variant.** A drain with no member roots is one work row, not an
empty section:

```text
  ⬣ drain implementation convoy   be-xxxx  inline · 8 items · no per-item runs
```

No member children are invented; the row's state is the drain node's own
state.

#### A — gascity.el, Runs cards (rich, flat, standalone)

```text
  ⬣ Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el, default-theme scr…
     be-tnd3z  open    7/8 deliverables   ◆◆◆◆◆◆◆···   ● run-operator-1
     be-0kjzs  build-basic · beads.el · 3h · 5/10 steps · 45 beads

  ✕ drain unit 6 for ga-tx45i
     ga-mszco  closed  2/3 steps · 1 failed   ◆◆✕   ga-4hdav  do-work · gascity.el · 2h

  ◆ review
     (no source)  2/2 steps   ◆◆   ga-6iwrx  review · gascity.el · 1d
```

The source title (cut, full text in `help-echo`) replaces the anonymous
formula line; the formula and root move to the dim third line. Two
`build-basic` runs are now distinguishable at a glance. If the source read is
cold, the line renders `source loading…` (SWR) and never blocks the list. A
run with no source shows `(no source)` and keeps the formula/root identity.

#### A — web, rich Runs card (≈72 columns)

```text
BEADS.EL
ACTIVE                                                         3h ago
Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el,
default-theme screenshots, black-box QA
be-tnd3z · 7/8 deliverables   ◆◆◆◆◆◆◆···
be-0kjzs  build-basic · 45 beads · 5/10 steps
────────────────────────────────────────────────────────────────────────────
```

The title link is the source feature; the formula becomes secondary metadata
at the bottom and appears once. On narrow screens the metadata line wraps
under the title. The lane status (`ACTIVE`) is generic; no phase label is
required.

#### A — web, rich run detail (responsive: text column → stacked cards)

```text
Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el,
default-theme screenshots, black-box QA
be-tnd3z open · be-0kjzs build-basic · beads.el · started 3h ago

5/10 steps · 7/8 deliverables · 1 in flight
── WORK ────────────────────────────────────────────────────────────────────
◆ prepare · be-nasax pass
◆ requirements · be-8lclw iter 1
◆ plan · be-rexyi iter 1
◆ plan-review · be-w4zzs pass
◆ decompose · be-bbp6v iter 1
⬣ implement · be-9sbk2 drain 7/8 · 1 in flight
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
· summarize-implementation · be-o4q0j iter 1
· review · be-thq3n loop
· finalize · be-8t31o iter 1
· publish · be-eyn10
▸ Run machinery (collapsed) · 45 beads · formula build-basic · convoy be-o4er1 7/8
```

Above `md` this is a single readable column; below `md` the same DOM stacks
(item title, then the `be-… closed` line, then the member line), so no
information depends on horizontal position. The graph and stage inspector
move under the collapsed "Run machinery" disclosure, which keeps the
existing `Formula Graph` and node selection intact.

#### A — web, generic cases

The same card and detail rules, with the optional facts absent:

```text
FLAT (ga-4hdav)                                      CLOSED · 2h ago
drain unit 6 for ga-tx45i
ga-mszco · 2/3 steps · 1 failed
ga-4hdav  do-work · 6 beads
────────────────────────────────────────────────────────────────────────────

STANDALONE (ga-6iwrx)                                CLOSED · 1d ago
review
(no source) · 2/2 steps
ga-6iwrx  review · 5 beads
────────────────────────────────────────────────────────────────────────────
```

The detail body is the same `WORK` list: three rows for the flat case, two
for the standalone case, with no `DELIVERABLES` section and no stage ribbon.

**Optimizes.** Learnability and recognizability: a new operator can answer
"what is this run for, what is left, who is on it" without knowing gc's
terminology. Best accessibility of the three (linear document order). It is
also the only alternative whose structure is identical for every formula.

**Scales** to many items: one row per work unit, done items collapse to
`◆ N done · show`; `/` filters by state or text; optional headers remain. At
40+ items the work list is a scroll region with a sticky count.

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
- *Emacs vs web lane:* Emacs first. The web needs the BFF work-unit
  projection (it cannot join bead metadata in the browser).
- *Degradation:* no drain → the work nodes are the spine; no source → the
  formula/root is the headline; no stage table → no headers. None of these
  changes the layout.

### Alternative B — Work ledger (paired what/how columns)

**Idea.** Keep the run as the unit, but render it as a reconciliation ledger:
one row per work unit, the "what" side on the left, the "how" side on the
right, joined by a gutter and a state column (`matched`, `in flight`,
`drift`, `unstarted`, or the plain state). The page's job is to prove that
every thing asked for has exactly one thing being done for it — and to make a
disagreement loud. When there is no drain, the same ledger pairs each work
node with its own execution evidence (step bead, attempts, checks); the
verdict column then carries the plain state.

**Mapping.** Left side = the work unit: a deliverable's business bead when a
drain has members, otherwise the work node's title. Right side = the
deliverable's member run root (with its ladder, progress, active step and
worker) when it exists, otherwise the work node's own bead and attempt/check
evidence. `drift` is a derived verdict only when both sides exist: business
closed while the member has not passed, business open while the member
passed, or a member with no business item. The input convoy and source
feature are header provenance, not rows.

**New vs available.** All facts are already loaded in Emacs; the new work is
the join and the verdict rule. Web needs the same join in the BFF, and the
two-column layout must collapse to a stacked card under ~700px.

#### B — gascity.el, rich run detail (100×35)

```text
  be-0kjzs  build-basic · beads.el · 3h · source be-tnd3z open · 7 matched · 1 in flight
  WHAT  work unit                                  │ HOW  execution                         STATE
  ──────────────────────────────────────────────────────────────────────────────────────────
  ◆ prepare                                        │ ◆ be-nasax  pass                       done
  ◆ requirements                                   │ ◆ be-8lclw  iter 1                     done
  ◆ plan                                           │ ◆ be-rexyi  iter 1                     done
  ◆ plan-review                                    │ ◆ be-w4zzs  pass                       done
  ◆ decompose                                      │ ◆ be-bbp6v  iter 1                     done
  ⬣ implement  drain 7/8                           │ ⬣ be-9sbk2  drain                      active
  ◆ be-rtqte  Retarget the demo fixture to the …   │ ◆ be-b9jhp  do-work ◆◆◆ 3/3 pass       matched
  ◆ be-95bl3  Remove third-party themes from th…   │ ◆ be-ybleu  do-work ◆◆◆ 3/3 pass       matched
  ◆ be-k8nn0  Complete the warning-free Texinfo…   │ ◆ be-rtqoj  do-work ◆◆◆ 3/3 pass       matched
  ◆ be-vrjbu  Regenerate and verify every scree…   │ ◆ be-wm8j0  do-work ◆◆◆ 3/3 pass       matched
  ◆ be-o597j  Complete reference, keybinding, a…   │ ◆ be-w7pjp  do-work ◆◆◆ 3/3 pass       matched
  ◆ be-gn247  Write the shared /tmp/demo-projec…   │ ◆ be-s3joe  do-work ◆◆◆ 3/3 pass       matched
  ◆ be-7japy  Run the manual-only black-box QA …   │ ◆ be-sqrl5  do-work ◆◆◆ 3/3 pass       matched
  ⬣ be-s61jf  Pin the new manual contracts in t…   │ ⬣ be-dhu31  do-work ◆◆⬣ 2/3 close-src… in flight
  · summarize-implementation                       │ · be-o4q0j  iter 1                     pending
  · review                                         │ · be-thq3n  loop                       pending
  · finalize                                       │ · be-8t31o  iter 1                     pending
  · publish                                        │ · be-eyn10                             pending
  ──────────────────────────────────────────────────────────────────────────────────────────
  Reconcile  7 matched · 1 in flight · 0 drift · 0 unstarted      ! failures   w copy id
  Provenance  be-0kjzs build-basic · input convoy be-hzrwd · implementation be-o4er1 7/8
  Keys     RET side   SPC drawer   I inspect   w copy   ! failures   g refresh   q bury
```

`RET` on the left column opens the business bead; `RET` on the right column
opens the member run; `I` on the right opens the member drawer; `SPC` on
either side opens the corresponding inspector. The gutter is a real column
(`│`, already used by the inspector), not decoration. The drain row itself
is a work unit; its deliverables follow it in `gc.drain_index` order.

#### B — gascity.el, flat case (no stage table, no drain)

```text
  ga-4hdav  do-work · gascity.el · 2h · source ga-mszco closed · 2/3 steps · 1 failed
  WHAT  work unit                    │ HOW  execution                         STATE
  ─────────────────────────────────────────────────────────────────────────────
  ◆ prepare item worktree            │ ◆ ga-2ee5m  pass                       done
  ✕ implement owned work             │ ✕ ga-bt89r  ralph · iter ga-u565r fail  failed
  ✕ close owned source anchor        │ ✕ ga-4yee3  fail                       failed
  ─────────────────────────────────────────────────────────────────────────────
  Reconcile  2 done · 1 failed · 0 drift · 0 unstarted
  Provenance  ga-4hdav do-work · input convoy ga-mszco · no implementation convoy
  Keys     RET side   SPC drawer   I inspect   w copy   ! failures   g refresh   q bury
```

The right side is the work node's own execution evidence; there is no member
run to pair with, so the state is the plain state, not a verdict.

#### B — gascity.el, standalone case (no source, no drain)

```text
  ga-6iwrx  review · gascity.el · 1d · no source · 2/2 steps
  WHAT  work unit                    │ HOW  execution                         STATE
  ─────────────────────────────────────────────────────────────────────────────
  ◆ validate report context          │ ◆ ga-ed78s  pass                       done
  ◆ write review report              │ ◆ ga-w3xz7  ralph · iter ga-f1ctf pass  done
  ─────────────────────────────────────────────────────────────────────────────
  Reconcile  2 done · 0 drift · 0 unstarted
  Provenance  ga-6iwrx review · no input convoy · no implementation convoy
  Keys     RET side   SPC drawer   I inspect   w copy   ! failures   g refresh   q bury
```

**Inline drain variant.** The drain is one row; the right side says `inline`
and the state is the drain's own state:

```text
  ⬣ drain implementation convoy      │ ⬣ be-xxxx  inline · 8 items · no member roots  active
```

#### B — gascity.el, Runs cards (rich, flat, standalone)

```text
  ⬣ be-0kjzs  build-basic                                  beads.el   3h
     ledger  8 units · 7 matched · 1 in flight · 0 drift    source be-tnd3z
     ◆◆◆◆◆⬣····  implement  5/10   ● run-operator-1  be-dhu31

  ✕ ga-4hdav  do-work                                      gascity.el 2h
     ledger  3 units · 2 done · 1 failed · 0 drift          source ga-mszco
     ◆◆✕  close-source-anchor  2/3

  ◆ ga-6iwrx  review                                       gascity.el 1d
     ledger  2 units · 2 done · 0 drift                     no source
     ◆◆  write-report  2/2
```

The third line is the new signal; `SPC` still opens the full step drawer, and
the ledger itself opens on `RET`.

#### B — web, rich Runs card (≈72 columns)

```text
BEADS.EL
ACTIVE                                                         3h ago
build-basic                        be-0kjzs
8 units · 7 matched · 1 in flight · 0 drift      source be-tnd3z
be-0kjzs  build-basic · 45 beads · 5/10 steps
────────────────────────────────────────────────────────────────────────────
```

The formula is demoted to a metadata line and the ledger counts lead. The
source is named once; the card no longer repeats the title as the formula.

#### B — web, rich run detail (desktop table, mobile stacked cards)

```text
be-0kjzs build-basic · beads.el · 3h ago · source be-tnd3z
8 units · 7 matched · 1 in flight · 0 drift

┌ WHAT (work unit) ────────────────────┬ HOW (execution) ───────────────┬ STATE ────┐
│ ◆ prepare                            │ ◆ be-nasax pass                │ done      │
│ ◆ requirements                       │ ◆ be-8lclw iter 1              │ done      │
│ ◆ plan                               │ ◆ be-rexyi iter 1              │ done      │
│ ◆ plan-review                        │ ◆ be-w4zzs pass                │ done      │
│ ◆ decompose                          │ ◆ be-bbp6v iter 1              │ done      │
│ ⬣ implement drain 7/8                │ ⬣ be-9sbk2 drain               │ active    │
│ ◆ Retarget the demo fixture…         │ ◆ be-b9jhp ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Remove third-party themes…         │ ◆ be-ybleu ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Complete the warning-free Texinfo… │ ◆ be-rtqoj ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Regenerate and verify every screen…│ ◆ be-wm8j0 ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Complete reference, keybinding…    │ ◆ be-w7pjp ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Write the shared /tmp/demo-project…│ ◆ be-s3joe ◆◆◆ 3/3 pass        │ matched   │
│ ◆ Run the manual-only black-box QA…  │ ◆ be-sqrl5 ◆◆◆ 3/3 pass        │ matched   │
│ ⬣ Pin the new manual contracts…      │ ⬣ be-dhu31 ◆◆⬣ 2/3 close-src… │ in flight │
│ · summarize-implementation           │ · be-o4q0j iter 1              │ pending   │
│ · review                             │ · be-thq3n loop                │ pending   │
│ · finalize                           │ · be-8t31o iter 1              │ pending   │
│ · publish                            │ · be-eyn10                     │ pending   │
└───────────────────────────────────────┴───────────────────────────────┴───────────┘
▸ Run machinery · 45 beads · formula build-basic · convoy be-o4er1 7/8
```

At `md` the table becomes a 3-column grid; below `md` each row stacks as a
small card: title, `be-rtqte · closed`, `do-work be-b9jhp · ◆◆◆ 3/3 pass`,
then the state word. The state word is always present, so color is never the
only signal.

#### B — web, generic cases

```text
FLAT (ga-4hdav)                                      CLOSED · 2h ago
drain unit 6 for ga-tx45i
3 units · 2 done · 1 failed · 0 drift      source ga-mszco
┌ WHAT ────────────────────────┬ HOW ────────────────────────┬ STATE ────┐
│ ◆ prepare item worktree      │ ◆ ga-2ee5m pass             │ done      │
│ ✕ implement owned work       │ ✕ ga-bt89r iter fail        │ failed    │
│ ✕ close owned source anchor  │ ✕ ga-4yee3 fail             │ failed    │
└──────────────────────────────┴─────────────────────────────┴───────────┘

STANDALONE (ga-6iwrx)                                CLOSED · 1d ago
review
2 units · 2 done · 0 drift      no source
┌ WHAT ────────────────────────┬ HOW ────────────────────────┬ STATE ────┐
│ ◆ validate report context    │ ◆ ga-ed78s pass             │ done      │
│ ◆ write review report        │ ◆ ga-w3xz7 iter pass        │ done      │
└──────────────────────────────┴─────────────────────────────┴───────────┘
```

**Optimizes.** Correspondence and auditability. It is the only alternative
whose primary question is "is every deliverable actually being executed, and
do the two records agree?" — the question an operator asks when a run is
half-done or a bead closes without its work. For a run with no drain it
becomes a compact step ledger, which is still useful.

**Scales** linearly, one row per work unit; long runs need collapsing of
matched/done rows. The fixed 34-column title budget truncates more
aggressively than A; the execution column is always visible, which is the
point.

**Trade-offs.**
- *Data:* needs the reverse join plus a drift rule (a product decision, not a
  data fact). No new reads in the Emacs detail.
- *Async/no-spawn:* none in detail; the Runs card's ledger counts need the
  member roots and are already in the run index (no read).
- *Remote/TRAMP:* no extra reads; the same store payload backs both columns.
- *Accessibility:* the visual two-column layout must have a DOM/linear reading
  order of "work unit, execution, state"; on Emacs, point movement is already
  linear and the gutter is a character, so this is natural. On web, the
  mobile stack must preserve that order.
- *Emacs vs web lane:* Emacs first; web is a real table/grid, which needs the
  BFF join.
- *Degradation:* no drain → the right side is the step's own evidence; no
  source → the header omits it; no stage table → no headers. The ledger never
  requires a deliverable.

### Alternative C — Flow board (dependency waves)

**Idea.** Render the run as a flow board: columns are dependency ranks
(waves), and every work unit is a lane that sits in the column where it
currently is. The question is no longer "what is this step's parent" but
"where is each work unit in the dependency order, and what is next?" Run-level
work (prepare, review, finalize) occupies its own lanes in its rank. A
formula's stage table, when present, may label a contiguous range of columns;
it never defines the columns.

**Mapping.** Columns = rank bands from §1.4: rank 0, rank 1, … in `blocks`
order. Lanes = work units: a drain with members contributes one lane per
deliverable in its column; a drain without members is one lane; a work node
is one lane. A lane's cell is its member run (ladder/progress) or the work
node's own state. The source feature is the board's title when present; the
two convoys are the header's provenance. Optional stage labels may replace
`Rank N` only when the stage covers a contiguous range of ranks.

**New vs available.** All board facts are in the Emacs run index already
(steps, member roots, business beads, dependency ranks). The new work is the
lane projection and a fixed-width board layout. Web needs the BFF work-unit
projection (same as A/B) plus a horizontal board; it is the most natural home
for this alternative.

#### C — gascity.el, rich run detail (100×35, viewport)

```text
  be-0kjzs build-basic · source be-tnd3z · 5/10 steps · 7/8 deliverables · 3h
  columns 5–9 of 10   h/l scroll   SPC machinery   RET open
  Rank 5        │ Rank 6              │ Rank 7        │ Rank 8      │ Rank 9
  decompose     │ implement (drain)   │ summarize     │ review      │ finalize
  ◆ be-bbp6v    │ ⬣ be-9sbk2 7/8      │ · be-o4q0j    │ · be-thq3n  │ · be-8t31o
                │  ◆ be-rtqte 3/3     │               │             │
                │  ◆ be-95bl3 3/3     │               │             │
                │  ◆ be-k8nn0 3/3     │               │             │
                │  ◆ be-vrjbu 3/3     │               │             │
                │  ◆ be-o597j 3/3     │               │             │
                │  ◆ be-gn247 3/3     │               │             │
                │  ◆ be-7japy 3/3     │               │             │
                │  ⬣ be-s61jf 2/3     │               │             │
  ────────────────────────────────────────────────────────────────────────────────────────
  Legend   ◆ done  ⬣ active  · pending  ✕ failed   RET lane/cell   SPC cell
  Keys     RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

At 100 columns the board shows a viewport of five rank columns; `h`/`l`
scroll. The `5/10 steps` and `7/8 deliverables` counts are labeled separately.
Deliverables occupy the `implement` column because that is their drain's rank;
later rank columns fill in when per-item review/fix steps exist.
`RET` on a lane label opens the business bead; `RET` on a cell opens the
member run; `SPC` on a cell opens the member inspector. The existing step
tree stays below the board, folded, so `C` and `T` keep their meanings. The
board is an overview; it does not try to show every control node.

#### C — gascity.el, flat case (no stage table, no drain)

```text
  ga-4hdav do-work · source ga-mszco · 2/3 steps · 1 failed · 2h
  columns 1–3 of 3   SPC machinery   RET open
  Rank 1              │ Rank 2                    │ Rank 3
  prepare-worktree    │ implement                 │ close-source-anchor
  ◆ ga-2ee5m pass     │ ✕ ga-bt89r iter fail      │ ✕ ga-4yee3 fail
  ─────────────────────────────────────────────────────────────────────────────
  Legend   ◆ done  ⬣ active  · pending  ✕ failed   RET lane/cell   SPC cell
  Keys     RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

Three columns, one lane each. No stage labels are needed; the rank labels are
derived from the dependency order.

#### C — gascity.el, standalone case (no source, no drain)

```text
  ga-6iwrx review · no source · 2/2 steps · 1d
  columns 1–2 of 2   SPC machinery   RET open
  Rank 1                    │ Rank 2
  validate-context          │ write-report
  ◆ ga-ed78s pass           │ ◆ ga-w3xz7 pass · iter ga-f1ctf pass
  ─────────────────────────────────────────────────────────────────────────────
  Legend   ◆ done  ⬣ active  · pending  ✕ failed   RET lane/cell   SPC cell
  Keys     RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

**Inline drain variant.** The drain is one lane in its rank; there are no
member lanes:

```text
  Rank 2
  ⬣ drain implementation convoy   be-xxxx  inline · 8 items · no member roots
```

#### C — gascity.el, Runs cards (rich, flat, standalone)

```text
  ⬣ be-0kjzs  build-basic                              beads.el   3h
     flow  ranks 10 · 5/10 steps · 7/8 deliverables    source be-tnd3z
     ◆◆◆◆◆⬣····  implement  5/10   ● run-operator-1  be-dhu31

  ✕ ga-4hdav  do-work                                  gascity.el 2h
     flow  ranks 3 · 2/3 steps · 1 failed              source ga-mszco
     ◆◆✕  close-source-anchor  2/3

  ◆ ga-6iwrx  review                                   gascity.el 1d
     flow  ranks 2 · 2/2 steps · no source
     ◆◆  write-report  2/2
```

The middle line is the board in miniature: rank count, step count, work-unit
count, and the source when present.

#### C — web, rich Runs card (≈72 columns)

```text
BEADS.EL
ACTIVE                                                         3h ago
build-basic · be-0kjzs · source be-tnd3z
ranks 10 · 5/10 steps · 7/8 deliverables
be-0kjzs  build-basic · 45 beads
────────────────────────────────────────────────────────────────────────────
```

#### C — web, rich run detail (kanban: horizontal scroll on small screens)

```text
build-basic · be-0kjzs · source be-tnd3z · beads.el · 3h ago · 7/8 deliverables
┌ Rank 5 ────────┬ Rank 6 ─────────────┬ Rank 7 ───────┬ Rank 8 ──────┬ Rank 9 ──────┐
│ ◆ decompose    │ ⬣ implement 7/8     │ · summarize   │ · review     │ · finalize   │
│                │ ◆ be-rtqte 3/3      │               │              │              │
│                │ ◆ be-95bl3 3/3      │               │              │              │
│                │ ◆ be-k8nn0 3/3      │               │              │              │
│                │ ◆ be-vrjbu 3/3      │               │              │              │
│                │ ◆ be-o597j 3/3      │               │              │              │
│                │ ◆ be-gn247 3/3      │               │              │              │
│                │ ◆ be-7japy 3/3      │               │              │              │
│                │ ⬣ be-s61jf 2/3      │               │              │              │
└────────────────┴─────────────────────┴───────────────┴──────────────┴──────────────┘
▸ Run flow · Formula Graph · steps (collapsed)
```

Each card shows the work-unit title, its id and its member run's ladder; the
card is a link to the deliverable, with a secondary link to the member run.
Below `md` the columns become a horizontally scrollable strip with snap
points (the standard kanban fallback); below `sm` they stack as sections with
the rank label repeated. DOM order is rank-major so a screen reader hears
"Rank 5: decompose done; Rank 6: eight deliverables, seven done, one active;
…". If a stage table exists, its labels may replace the rank labels for
contiguous ranges; the columns and order do not change.

#### C — web, generic cases

```text
FLAT (ga-4hdav)                                      CLOSED · 2h ago
drain unit 6 for ga-tx45i · source ga-mszco
ranks 3 · 2/3 steps · 1 failed
┌ Rank 1 ──────────┬ Rank 2 ──────────────┬ Rank 3 ────────────────┐
│ ◆ prepare        │ ✕ implement          │ ✕ close-source-anchor  │
└──────────────────┴──────────────────────┴────────────────────────┘

STANDALONE (ga-6iwrx)                                CLOSED · 1d ago
review · no source
ranks 2 · 2/2 steps
┌ Rank 1 ──────────┬ Rank 2 ──────────────┐
│ ◆ validate       │ ◆ write-report       │
└──────────────────┴──────────────────────┘
```

**Optimizes.** Flow and position. It is the best answer to "where are we,
what is next, what is stuck in this rank" and the best use of the web's
width. It also makes the per-rank totals directly readable instead of hidden
in a header rail.

**Scales** to many items within a rank by scrolling a column; across ranks by
horizontal scroll. At 100 Emacs columns, lane titles are truncated hard (12
characters), so the board is an overview that needs `RET` for detail; on the
web, cards carry full titles. With 40+ items the active column becomes a
scroll region with a count and `/`-style filter, not 40 cards in one viewport.

**Trade-offs.**
- *Data:* Emacs needs only the existing index; web needs the BFF work-unit
  projection (work unit + member root + ladder + state).
- *Async/no-spawn:* no new reads. The board re-projects the loaded payload, so
  `g`/live refresh keeps folds and lane positions.
- *Remote/TRAMP:* identical to A/B: no synchronous stat, no extra gc call on
  render.
- *Accessibility:* the board is the weakest of the three spatially. Every cell
  must carry a word (`done`, `running`, `pending`), each column a rank label,
  and the DOM order must be rank-major; mobile must stack, not shrink.
- *Emacs vs web lane:* **web first.** The board's value comes from width and
  cards; doing it in Emacs first would spend the most effort for the least
  legible result. Emacs gets a compact board later (or never) if the web
  board proves the IA.
- *Degradation:* no drain → one lane per work node; no source → the title is
  the formula/root; no stage table → rank labels. The board never requires a
  stage table.

### 3.4 Same layout, cases

The three alternatives differ in reading order, not in the facts they
require. This matrix is a summary; the ASCII above is the contract.

| case | A work spine | B work ledger | C flow board |
| --- | --- | --- | --- |
| rich: drain + source + optional table | source headline; deliverables under the drain; optional headers | one row per deliverable; what/how/state; optional headers | rank columns; deliverable lanes in the drain's column |
| flat: no table, no drain, source | source headline; work nodes as rows | one row per work node; own evidence on the right | one lane per work node in its rank |
| standalone: no source, no drain | formula/root headline; work nodes as rows | one row per work node; no source in header | one lane per work node; no source in title |
| inline drain: no member roots | one drain row; no member children | one drain row; `inline` on the right | one drain lane; no member lanes |
| no stage table | no headers; flat order | no headers; flat order | rank labels |
| stage table present | optional headers over contiguous runs | optional headers over contiguous runs | optional labels for contiguous rank ranges |

## 4. Comparison and recommendation

### 4.1 Comparison

| | A Work spine | B Work ledger | C Flow board |
| --- | --- | --- | --- |
| Primary question | "What is this run for, and what is left?" | "Does every work unit have exactly one execution, and do they agree?" | "Where is each work unit in the dependency order, and what is next?" |
| Information architecture | Document: source → work units → execution → provenance | Table: what ↔ how, with a state column | Board: rank columns × work-unit lanes |
| Works with no drain? | Yes: work nodes are the spine | Yes: right side is the node's own evidence | Yes: one lane per work node |
| Works with no source? | Yes: formula/root headline | Yes: header omits source | Yes: title is formula/root |
| Works with no stage table? | Yes: flat order, no headers | Yes: flat order, no headers | Yes: rank labels |
| Learnability | Highest: business vocabulary first; formula last | High for mapping, but the two columns and verdict need a legend | Medium: rank vocabulary is generic; lane/cell reading needs a legend |
| Density | Medium (2 lines per deliverable) | Highest (1 line per work unit) | Medium-low in Emacs (hard truncation), high on web |
| Drill-down | `RET` title / `RET` member; `SPC`/`I` member drawer; `SPC` machinery fold, `C` control | `RET` per column; `SPC` per side; `!` failures | `RET` lane / `RET` cell; `SPC` cell; `SPC` machinery fold |
| Emacs implementation cost | **Low**: reverse drain join + reorder + source card read | **Low-medium**: join + drift rule + two-column renderer | **Medium-high**: new board renderer, cell properties, truncation rules |
| Web implementation cost | Medium: BFF work-unit projection + hero + card de-dup | Medium: same projection + responsive table | Medium-high: same projection + board with horizontal scroll/snap |
| Data risk | Low: source read on the card is the only new read | Low: join + a product rule (drift) | Low-medium: the lane projection and rank-major DOM |
| Failure mode | A long feature title dominates; done items still need collapsing | Dense; long titles truncate; drift rule can be argued | Emacs board is unreadable for long titles; mobile board can become a horizontal trap |
| Accessible order | Strongest (linear document) | Good if rows read "work unit, execution, state" | Weakest spatially; needs explicit words + DOM order |
| Formula-agnostic? | Yes, by construction | Yes, by construction | Yes, by construction |

### 4.2 Recommendation

**Build A first in gascity.el, and make it the default for every run.** It is
the smallest honest change with the largest comprehension gain, and it is the
only alternative whose structure is identical for a formula with a stage
table, a formula without one, a run with a drain, and a run without one:

1. The source read already exists (`gascity-run--source`), so the detail's
   first question — *what feature is this run for?* — is one layout change
   away.
2. The business↔member join is a pure addition to `gascity-runs-index`
   (`gc.drain_member_id` → member root). No new gc call, no new parser, no
   change to the store.
3. The Runs card's source line is the only new read, and it fits the existing
   store/TTL/scheduler contract; it can ship with a placeholder and a
   `source unavailable` state.
4. It changes no keys and requires no stage vocabulary, so it is testable
   with the existing render harness and screenshot fixture.
5. When the optional facts are absent, A degrades to the flat
   dependency-ordered tree that already exists. There is no second IA and no
   per-formula selector.

**The Go/web lane owns the work-unit projection and the board.** Add one
read-only `workUnits` projection to the run summary/detail DTO: source bead,
input/implementation convoy identity, dependency ranks, and per-unit
`{business bead, member root, ladder, state, worker}` plus counts. The BFF
already joins bead and session data for detail; this is the same kind of
join, done once on the server so Emacs and the browser agree. On top of that
projection:

- Web run card: de-duplicate the formula, lead with the source when present,
  show the work-unit count (A) or the ledger counts (B).
- Web detail: A's hero/work-unit column is the safest first web change
  because it reuses the detail's existing node data plus the new projection.
- Web C board: second web step. The board is the strongest use of the web's
  width, but it must not be built until the projection exists; otherwise it
  would repeat the current defect in a prettier layout. Its columns are
  dependency ranks, not formula stages.

**B is a refinement, not a first build.** Its same-line pairing is the right
treatment for A's deliverable row; the drift verdict is the only genuinely
new concept. If the team wants one layout, implement A's row as B's two
columns and skip a separate B view. If not, add B as a second layout
selected from the run view's existing `/` menu after A lands (it would
otherwise need a new key, which this design avoids). B must not become a
per-formula selector.

**C is optional and web-first.** It is a different question (flow position),
not a different formula. It must use rank columns and degrade to rank labels
when no stage table exists. It is not the default and not a prerequisite for
A.

**Optional enrichment, explicitly.** A formula stage table, an implementation
convoy, plans, formula source, worker/session and timestamps may add labels
or rows. None of them may change the order, the grouping, or the set of
required facts. A formula without any of them is a normal run.

### 4.3 Phased rollout

0. **Model and projection (both lanes).** Add the generic work-unit
   projection: source, input/implementation convoy identity, dependency
   ranks, per-unit `{business bead, member root, ladder, state, worker}` and
   counts. No formula table is consulted. Acceptance: `be-0kjzs` returns
   `be-tnd3z` as source and the eight pairs above; `ga-4hdav` returns three
   work units and no deliverables; `ga-6iwrx` returns two work units, no
   deliverables and no source; a run with an inline drain returns one drain
   unit and no member roots.
1. **Emacs A, detail.** Source as headline when present, work-unit spine,
   paired member line, machinery below and folded (`C` still controls its
   control nodes), provenance footer. Add the reverse drain map to
   `gascity-runs-index`; no new read. Optional stage headers only if a table
   is present. Update the manual's Run Detail section and the deterministic
   screenshot fixture.
2. **Emacs A, Runs card.** Source title/id line through the store with a
   placeholder; `SPC` keeps the drawer; `RET` opens the run. Acceptance in
   tmux and against the TRAMP test city `bright-lights`.
3. **Emacs polish.** Collapse completed work units, `/` filter, `w`/`I`/`!`
   on the correct half of a row, TTY and greyscale checks.
4. **Web A.** Hero + work-unit cards + machinery disclosure; fix the stage
   ladder disagreement by removing the formula-specific ladder from the
   required path (acceptance below).
5. **Web C.** Rank-column flow board on top of the work-unit projection;
   responsive horizontal strip; rank-major DOM order.
6. **Emacs C (optional).** A compact board as an optional detail layout (no
   new key) only if the web board proves it; otherwise leave Emacs with A/B.
7. **Retire the stage table as IA.** Keep `gascity-run-stage.el` only as an
   optional header source, or delete it if the generic rank headers are
   enough. The web phase grammar follows the same rule: labels only, never
   structure.

## 5. Open questions

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
   with `separate`, every item should have one. What does the work-unit row
   show for an item with no member root yet: `unstarted`, `not dispatched`,
   or nothing? (Recommend an explicit word, never a fabricated run.) The
   inline drain itself is one work unit; do not invent per-item rows.
4. **Drift.** Define the verdict precisely: business `closed` + member
   `gc.outcome != pass`; business `open` + member pass; member with no
   business item; business with two members. Is drift a warning or an error?
   The verdict only exists when both sides exist.
5. **One-call principle.** Should `gc` expose `run work-units --json` instead
   of the BFF joining bead metadata? The server join duplicates knowledge of
   `gc.drain_*` keys; a gc projection would keep that knowledge in one place
   and serve both surfaces. This is the largest architectural question in the
   document.
6. **Summary weight.** `runs/summary` is already 53 KB for 5 lanes. Full
   work units for every lane would grow it; counts only in the summary and
   the full list in detail is the likely compromise.
7. **Cross-store members.** A member root names `gc.root_store_ref`; can it
   differ from the parent's? If yes, the join must read both stores and the
   per-city buffer identity rules apply.
8. **Empty ranks.** Is an empty rank meaningful in a board? Keep it only if
   it is a real dependency gap; do not let an empty column read as "failed".
9. **Naming.** "Work unit", "deliverable", "business item", "step", "bead" —
   pick one word for the UI and use it in both surfaces. The bead is the
   data; the user's unit is the work unit (a deliverable when one exists).
10. **Live updates.** Does a member root's event invalidate the parent detail
    today? If not, A/B/C all need the parent view to refresh on member events,
    or the per-item progress will be stale while the page claims to be live.
11. **Optional stage table.** Keep it as a header source, or drop it entirely
    in favor of rank headers? If kept, it must never reorder or hide a step,
    and a formula without one must be indistinguishable in structure.
12. **Cycles and unknown deps.** The order is cycle-guarded; what does the UI
    show for a cycle or a dependency on a bead outside the run? (Recommend:
    keep the authored order for the cycle members and mark the edge, never
    drop the node.)

## 6. Acceptance checks for a later implementation

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
   source. `ga-6iwrx` is the fixture.
3. **No formula-specific input.** A run with no stage table (`ga-4hdav`,
   `ga-6iwrx`) renders with the same IA as `be-0kjzs`: same row order rules,
   same keys, same provenance. No stage name or table is required to render
   any of the three.
4. **Flat/no-drain/no-source cases.** The flat case (`ga-4hdav`) and the
   standalone case (`ga-6iwrx`) are drawn in all three alternatives and
   implemented with the same layout rules as the rich case. An inline drain
   renders as one work unit with no member children.
5. **Stage agreement only when a table exists.** If a stage table is present,
   its headers agree with the step nodes for the same run, and Emacs and the
   web agree on the label. If no table exists, neither surface claims a
   stage. (Today the web and Emacs disagree on `Intake 5/5`; this is a
   prerequisite.)
6. **Runs card identity.** Two active `build-basic` runs are distinguishable
   by source title/id in both surfaces; the formula appears once per card. A
   run with no source is distinguishable by formula/root and says `(no
   source)`.
7. **Non-blocking.** No synchronous `gc` call on render, redisplay, timers or
   eldoc; the Runs card's source read is async, TTL'd, deduped, and
   visible-first; a cold read shows a placeholder, and a failed read shows
   `source unavailable`. The ERT non-blocking guard is updated if a new
   input-free verb is added (none is expected).
8. **Remote.** Open the same views against `/ssh:localhost:~/bright-lights`
   from a fresh tmux Emacs; the layout, pairing and source render identically,
   and no render path stats a file or spawns a blocking process over TRAMP.
9. **Keys and folds.** `RET`, `SPC`, `C`, `I`, `w`, `!`, `g`, `q` keep their
   current meanings at the new objects; `g` and live refresh keep point and
   folds; the needs toggle (`T`) still restores the flat layout byte-for-byte.
10. **Accessibility.** In greyscale, every state has a word as well as a glyph;
    the web's mobile stack preserves the reading order work unit → execution
    → state; the board's DOM is rank-major and each cell names its rank.
11. **Scale.** With 40 work units the Emacs list collapses completed rows and
    keeps the active one visible; the web board scrolls a column, not the
    whole page; the `/` filter still works.
12. **Docs and gates.** `doc/gascity.texi`'s Run Detail section and the
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

### A.2 Generic-case metadata

Flat case `ga-4hdav` (`do-work`, no stage table, no drain):

```text
gc.kind=workflow                      gc.formula_name=do-work
gc.root_store_ref=rig:gascity.el      gc.var.convoy_id=ga-mszco
gc.input_convoy_id=ga-mszco           gc.drain_control_id=ga-k9jd2
gc.drain_member_id=ga-tx45i           gc.drain_index=6  gc.drain_count=7
gc.outcome=fail
```

Its graph: `ga-2ee5m` prepare-worktree pass, `ga-bt89r` implement ralph
skipped with iteration `ga-u565r` fail, `ga-4yee3` close-source-anchor fail,
`ga-ihghs` workflow-finalize pass, `ga-war76` spec pass. The run is a drain
member, but its own detail has no drain node; the flat layout is the same as
any standalone `do-work`.

Standalone case `ga-6iwrx` (`review`, no stage table, no drain, no source):

```text
gc.kind=workflow                      gc.formula_name=review
gc.root_store_ref=rig:gascity.el      gc.var.convoy_id=(absent)
gc.outcome=pass
```

Its graph: `ga-ed78s` validate-context pass, `ga-w3xz7` write-report ralph
pass with iteration `ga-f1ctf` pass, `ga-yx3o5` spec pass, `ga-its4e`
workflow-finalize pass. No `gc.var.convoy_id`, so no source row.

### A.3 Live web payload (trimmed)

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
The `stages`/`phaseLabel` fields are the web's formula-specific mapping; the
design treats them as optional labels, not as required data.

### A.4 Reproduction notes

- Emacs capture: fresh `emacs -nw -Q`, `lisp/` of gascity.el and beads.el on
  `load-path`, default-directory `/home/roman/emacs-city`, `M-x
  gascity-runs`, `RET` on `be-0kjzs`, `C` to show control nodes. Pane size
  120×40; the mockups above are drawn at 100 columns per the brief.
- Generic-case capture: the same Emacs against the gascity.el store, `RET` on
  `ga-4hdav` and `ga-6iwrx`; both are closed, so the mockups show their final
  state. The ids and titles are real; the relative times are illustrative.
- Web evidence: the SPA at `http://127.0.0.1:8372/city/emacs-city/runs` and
  the BFF endpoints above; the SPA's `LaneCard.tsx`, `FormulaRunDetail.tsx`,
  `RunMetadata`, `StageLadder.tsx` and `FormulaRunDiagram.tsx` were read to
  confirm the rendered structure. No state was mutated.
- No manual `build-basic` worktree was touched.
