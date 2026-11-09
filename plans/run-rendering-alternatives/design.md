# Run rendering: three gascity.el alternatives

Status: design spike, design only. No lisp changes accompany this document.
Bead: `ga-p1gss` (revision of `ga-zp2v9`; the original spike is commit
`2ccab5a`). This revision (`ga-h8rma`) scopes the document to **gascity.el
only**.
Date: 2026-11-09.
Surface: the gascity.el Runs view (`*gascity-runs:CITY*`) and run detail
(`*gascity-run:ID*`).

**Out of scope.** The gascity web dashboard (Go/BFF/React) is not changed or
designed here; no web mockup, phase, recommendation or implementation step
appears below.

This revision also removes the original spike's dependence on formula-specific
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
      ◆ Write the shared /tmp/demo-pr… be-gn247  pass                       55m
      ◆ Run the manual-only black-box… be-7japy  pass                       18m
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
   beads (the whole Emacs graph), and `7/8` deliverables. They are all
   defensible and all different.
8. `C` reveals 13 control nodes; `T` re-renders the step tree by `needs`;
   `I` inspects; `w` copies; `!` diagnoses. None of these affordances reach
   the business↔execution pairing.
9. The stage headers (`Intake`, `Implementation`, …) are not gc data. They
   come from an Emacs-authored table in `gascity-run-stage.el` (a port of
   gc's `stagesForFormula` plus a local `build-basic` entry). A formula
   outside that table already renders a different page: the flat step table;
   a new formula gets no stages at all.

### 2.3 Observed defects worth fixing

- **The Emacs runs card has no source.** The card is correct but anonymous:
  two `build-basic` cards can only be told apart by id. This is the exact
  defect the task names.
- **The detail header and the card disagree on the run's current step.** The
  card says `implement 5/10`, the header's `convoy` row says `7/8`, and the
  stage says `0/2`; each is a different denominator (anchors, convoy
  membership, steps). The redesign must label the denominators or show one.
- **The IA is formula-specific.** A run with a stage table gets stage groups;
  a run without one gets a flat table. The same page therefore has two
  information architectures, and the richer one is unavailable to most
  formulas.

### 2.4 Data that exists but is not surfaced

| data | where it lives | what it would buy | already read? |
| --- | --- | --- | --- |
| source feature `be-tnd3z` | `gc.var.convoy_id` → convoy status members | the run's title | Emacs detail yes (new), Emacs runs card no |
| input convoy id `be-hzrwd` | `gc.var.convoy_id` | provenance; explains `source` | Emacs detail (used, not named) |
| implementation convoy `be-o4er1` | `gc.input_convoy_id`, `gc.build.implementation_convoy_id` | names the deliverable container | Emacs detail as unlabeled `convoy` |
| item ↔ member join | `gc.drain_member_id` on each member root | one row per deliverable | Emacs beads loaded, not joined |
| drain ordering | `gc.drain_index`, `gc.drain_count` | stable lane order | not shown |
| member ladder + worker + failure | member root graph | per-item progress | Emacs member rows; never paired |
| business outcome/status | business bead `status`, `gc.outcome`, close reason | per-item verdict | Emacs title rows (`pass`) |
| per-item times | business `created_at`/`closed_at`, member step times | timeline / duration | Emacs relative times only |
| item root key | `gc.item_root_key` (`drain-item-root:be-9sbk2:N:be-…`) | stable grouping key | not shown |
| session link | member root `gc.session_name`, session list | who is on item 8 | Emacs member worker |
| dependency ranks | `blocks` edges in the graph | generic bands/columns | computed for the ladder, not shown as structure |

### 2.5 What this means for the design

The pages are rich in *execution* facts and poor in *deliverable* facts. The
root/formula is treated as the identity; the business feature is a row; the
8 deliverables and their 8 member runs are two parallel lists with no join.
A redesign should not add more execution detail. It should make the work unit
— a deliverable when one exists, otherwise a step — the unit of reading, and
derive execution detail from it. The same layout must work when there is no
drain, no source, and no stage table.

## 3. Three gascity.el alternatives

All three are defined over §1's model. They keep the existing glyphs and add
no new keys: `RET`, `SPC`, `C`, `I`, `w`, `!`, `g`, `q` keep their meanings
("object at point" changes with the layout). Every mockup is an Emacs window;
the widths given are pane widths, and the rendering rules are stated per
alternative.

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

**New vs available.** The only new Emacs data is the ordered deliverable map
(a hash built from the already-loaded bead graph: `gc.drain_member_id` →
business bead, ordered by `gc.drain_index`) plus the source read on the Runs
card. The join is in-memory; the card read is one convoy-status read per
visible run. No stage table is needed.

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
be inserted above contiguous runs; the rows and order do not change. Only a
formula-provided table may add these headers.

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
  read; the drain join is in-memory).
- *Async/no-spawn:* the card read must be a `gascity-store-use` keyed by
  `("convoy" "status" CONVOY)`, visible-first, with a placeholder line; no
  sync call in the render path.
- *Remote/TRAMP:* one extra async process per visible run over the existing
  pipe; TTL keeps it bounded; a failed read renders `source unavailable`
  rather than a fabricated title.
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
the join and the verdict rule.

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
  member roots, which the run index already has.
- *Remote/TRAMP:* no extra reads; the same store payload backs both columns.
- *Accessibility:* point movement is linear and the gutter is a character, so
  the reading order "work unit, execution, state" is natural in Emacs.
- *Degradation:* no drain → the right side is the step's own evidence; no
  source → the header omits it; no stage table → no headers. The ledger never
  requires a deliverable.

### Alternative C — Compact board (dependency waves)

**Idea.** Render the run as a board: columns are dependency ranks (waves),
and every work unit is a lane that sits in the column where it currently is.
The question is no longer "what is this step's parent" but "where is each
work unit in the dependency order, and what is next?" Run-level work
(prepare, review, finalize) occupies its own lanes in its rank. A formula's
stage table, when present, may label a contiguous range of columns; it never
defines the columns.

**This is an optional later Emacs variant, not part of the first build.**
Its value depends on a wide pane, and A already answers the default
question. It would be offered as a display-layout choice in the run view's
existing `/` menu after A lands — no new key. It is Emacs-only; nothing below
requires a non-Emacs surface.

**Emacs form.** At ≥100 columns the board shows four or five rank columns and
scrolls horizontally with `h`/`l` (the run detail's existing scroll
bindings). A lane label is truncated to its column width; the full title is
in `help-echo` and `RET` opens the object. Below 90 columns the board does
**not** squeeze the columns: it stacks one section per rank, two or more
lanes per line, which is the same data in a vertical reading order. That
stacked fallback is what makes the board genuinely usable in Emacs rather
than a wide-screen-only gimmick.

**Mapping.** Columns = rank bands from §1.4: rank 0, rank 1, … in `blocks`
order. Lanes = work units: a drain with members contributes one lane per
deliverable in its column; a drain without members is one lane; a work node
is one lane. A lane's cell is its member run (ladder/progress) or the work
node's own state. The source feature is the board's title when present; the
two convoys are the header's provenance. Optional stage labels may replace
`Rank N` only when the stage covers a contiguous range of ranks.

**New vs available.** All board facts are in the run index already (steps,
member roots, business beads, dependency ranks). The new work is the lane
projection and a fixed-width board renderer with its stacked fallback.

#### C — gascity.el, rich run detail (100×35, viewport)

```text
  be-0kjzs build-basic · source be-tnd3z open · 5/10 steps · 7/8 deliverables · 3h
  ranks 5–9 of 10   h/l scroll ranks   SPC machinery   RET open
  Rank 5             │ Rank 6            │ Rank 7        │ Rank 8      │ Rank 9
  ───────────────────┼───────────────────┼───────────────┼─────────────┼─────────────
  decompose          │ implement (drain) │ summarize     │ review      │ finalize
  ◆ be-bbp6v         │ ⬣ be-9sbk2  7/8   │ · be-o4q0j    │ · be-thq3n  │ · be-8t31o
                     │  ◆ be-rtqte  3/3  │               │             │
                     │  ◆ be-95bl3  3/3  │               │             │
                     │  ◆ be-k8nn0  3/3  │               │             │
                     │  ◆ be-vrjbu  3/3  │               │             │
                     │  ◆ be-o597j  3/3  │               │             │
                     │  ◆ be-gn247  3/3  │               │             │
                     │  ◆ be-7japy  3/3  │               │             │
                     │  ⬣ be-s61jf  2/3  │               │             │
  ───────────────────┴───────────────────┴───────────────┴─────────────┴─────────────
  publish be-eyn10 · rank 10 (l to scroll)     Legend ◆ done ⬣ active · pending ✕ failed
  Keys   RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

At 100 columns the board shows five rank columns; `h`/`l` scroll. The `5/10
steps` and `7/8 deliverables` counts are labeled separately. Deliverables
occupy the `implement` column because that is their drain's rank; later rank
columns fill in when per-item review/fix steps exist. `RET` on a lane label
opens the business bead; `RET` on a cell opens the member run; `SPC` on a
cell opens the member inspector. The existing step tree stays below the
board, folded, so `C` and `T` keep their meanings. The board is an overview;
it does not try to show every control node.

#### C — gascity.el, the same rich run, narrow pane (stacked fallback)

```text
  be-0kjzs build-basic · source be-tnd3z open · 5/10 steps · 7/8 deliverables · 3h
  ranks 5–10 of 10 (stacked: pane < 90 columns)   SPC machinery   RET open
  ─────────────────────────────────────────────────────────────────────────────
  Rank 5   decompose          ◆ be-bbp6v
  Rank 6   implement (drain)  ⬣ be-9sbk2 7/8 · 1 in flight
           ◆ be-rtqte 3/3   ◆ be-95bl3 3/3   ◆ be-k8nn0 3/3   ◆ be-vrjbu 3/3
           ◆ be-o597j 3/3   ◆ be-gn247 3/3   ◆ be-7japy 3/3   ⬣ be-s61jf 2/3
  Rank 7   summarize          · be-o4q0j
  Rank 8   review             · be-thq3n
  Rank 9   finalize           · be-8t31o
  Rank 10  publish            · be-eyn10
  ─────────────────────────────────────────────────────────────────────────────
  Keys   RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

The stacked form is the board's real Emacs contract: rank ordering is
preserved, the active deliverable is still one row, and no title is truncated
to twelve characters.

#### C — gascity.el, flat case (no stage table, no drain)

```text
  ga-4hdav do-work · source ga-mszco closed · 2/3 steps · 1 failed · 2h
  ranks 0–2 of 3   SPC machinery   RET open
  Rank 0              │ Rank 1                    │ Rank 2
  ────────────────────┼───────────────────────────┼──────────────────────────────
  prepare-worktree    │ implement                 │ close-source-anchor
  ◆ ga-2ee5m pass     │ ✕ ga-bt89r iter fail      │ ✕ ga-4yee3 fail
  ────────────────────┴───────────────────────────┴──────────────────────────────
  Legend ◆ done ⬣ active · pending ✕ failed
  Keys   RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

Three columns, one lane each. No stage labels are needed; the rank labels are
derived from the dependency order.

#### C — gascity.el, standalone case (no source, no drain)

```text
  ga-6iwrx review · no source · 2/2 steps · 1d
  ranks 0–1 of 2   SPC machinery   RET open
  Rank 0                    │ Rank 1
  ──────────────────────────┼──────────────────────────────────────────────
  validate-context          │ write-report
  ◆ ga-ed78s pass           │ ◆ ga-w3xz7 pass · iter ga-f1ctf pass
  ──────────────────────────┴──────────────────────────────────────────────
  Legend ◆ done ⬣ active · pending ✕ failed
  Keys   RET lane/cell   SPC cell   I inspect   w copy   ! diagnose   g refresh   q bury
```

**Inline drain variant.** The drain is one lane in its rank; there are no
member lanes:

```text
  Rank 3
  ⬣ drain implementation convoy   be-xxxx  inline · 8 items · no member roots
```

#### C — gascity.el, Runs cards (rich, flat, standalone)

```text
  ⬣ be-0kjzs  build-basic                              beads.el   3h
     ranks 11 · 5/10 steps · 7/8 deliverables          source be-tnd3z
     ◆◆◆◆◆⬣····  implement  5/10   ● run-operator-1  be-dhu31

  ✕ ga-4hdav  do-work                                  gascity.el 2h
     ranks 3 · 2/3 steps · 1 failed                    source ga-mszco
     ◆◆✕  close-source-anchor  2/3

  ◆ ga-6iwrx  review                                   gascity.el 1d
     ranks 2 · 2/2 steps · no source
     ◆◆  write-report  2/2
```

The middle line is the board in miniature: rank count, step count, work-unit
count, and the source when present.

**Optimizes.** Flow and position. It is the best answer to "where are we,
what is next, what is stuck in this rank", and it makes the per-rank totals
directly readable instead of hidden in a header rail. At a wide pane it is
the most compact way to see the whole run's shape; at a narrow pane the
stacked fallback is a rank-grouped version of A.

**Scales** to many items within a rank by scrolling a column; across ranks by
horizontal scroll. At 100 Emacs columns, lane titles truncate hard, so the
board is an overview that needs `RET` for detail; the stacked fallback keeps
full titles. With 40+ items the active column becomes a scroll region with a
count and `/`-style filter, not 40 rows in one viewport.

**Trade-offs.**
- *Data:* needs only the existing run index; the lane projection is derived.
- *Async/no-spawn:* no new reads. The board re-projects the loaded payload, so
  `g`/live refresh keeps folds and lane positions.
- *Remote/TRAMP:* identical to A and B: no synchronous stat, no extra gc call
  on render.
- *Accessibility:* the most spatially dependent of the three. Every cell must
  carry a word (`done`, `running`, `pending`), each column a rank label, and
  the narrow pane must stack (which the design makes the default below 90
  columns).
- *Emacs implementation cost:* medium-high — a new board renderer, cell text
  properties, truncation rules, and the stacked fallback. This is why it is
  last and optional.
- *Degradation:* no drain → one lane per work node; no source → the title is
  the formula/root; no stage table → rank labels. The board never requires a
  stage table.

### 3.4 Same layout, cases

The three alternatives differ in reading order, not in the facts they
require. This matrix is a summary; the ASCII above is the contract.

| case | A work spine | B work ledger | C compact board |
| --- | --- | --- | --- |
| rich: drain + source + optional table | source headline; deliverables under the drain; optional headers | one row per deliverable; what/how/state; optional headers | rank columns; deliverable lanes in the drain's column |
| flat: no table, no drain, source | source headline; work nodes as rows | one row per work node; own evidence on the right | one lane per work node in its rank |
| standalone: no source, no drain | formula/root headline; work nodes as rows | one row per work node; no source in header | one lane per work node; no source in title |
| inline drain: no member roots | one drain row; no member children | one drain row; `inline` on the right | one drain lane; no member lanes |
| no stage table | no headers; flat order | no headers; flat order | rank labels |
| stage table present | optional headers over contiguous runs | optional headers over contiguous runs | optional labels for contiguous rank ranges |

## 3.5 Implementation feasibility (Emacs only)

The model in §1 was checked against the Emacs run view's own reads and
model code.

**What the Emacs view already loads.** `gascity-runs-read-beads` collects the
run roots and every graph bead from the city store and each rig store through
the store (§8.1); `gascity-runs-index` already builds `:roots`, `:graphs`,
`:owners`, `:drains` (`gc.drain_control_id` → member roots) and memoized
`:ladders`. `gascity-run--source` resolves `gc.var.convoy_id` → convoy status
→ first tracked member as `(:id :title :status)` and is already wired into
the run detail. `gascity-run-stage.el` maps a formula name to optional stage
labels, with a nil table for any formula it does not know. The run detail's
step tree, control fold (`C`), needs toggle (`T`), inspector (`I`) and drawer
(`SPC`) are all pure over that payload. Timestamps, sessions and events are
already read (sessions for the worker, events only while a drawer is open).

**What this design adds (Emacs).**

1. **An ordered deliverable map in `gascity-runs-index`.** Today `:drains`
   gives drain step id → member roots. The design needs the triplet
   `(drain id, gc.drain_index, business bead)` per member:
   - member root → `gc.drain_member_id` is the business bead id;
   - `gc.drain_index` / `gc.drain_count` give the order and total (a member
     without an index sorts after indexed members, by id);
   - the business bead is usually in the same run-beads payload; when it is
     not, the row keeps the id and shows the plain state rather than inventing
     a title. No new read.
   This is the only model change, and it is a pure addition to the index.
2. **The Runs card's source read.** The card currently reads the shared
   run-beads payload only. It needs the source title for a visible run, which
   means a `("convoy" "status" CONVOY)` store read per run, keyed and TTL'd
   like every other read, visible-first, with `source loading…` and
   `source unavailable` states. The detail already pays this read; the card
   is the only new process, and it is async.
3. **A rank function.** `gascity-runs-ladder` already computes a topological
   ladder; C needs the rank number per top-level node, which is the longest
   `blocks` path. That is a small pure function over the graph beads, with the
   existing cycle guard; no new payload.
4. **A renderer.** A/B reorder and re-bracket data the view holds. C adds a
   fixed-width board plus its stacked fallback. Neither needs a new gc
   command, a new parser, or a change to the store keys.

**What is not needed.** No formula name, stage table, phase grammar or
per-formula rule is required. No server-side projection, no extra payload
field, no dependency-rank field from another process: Emacs computes the join
and the ranks from beads it already has. The formula stage table stays an
optional label source and may be dropped as an IA (see §4.3).

**Cost/risk.** A is low (index join + reorder + one async card read). B is
low-medium (the same join, plus a drift rule and a two-column renderer). C is
medium-high (board renderer and fallback), which is why it is optional and
last. The only data risk is a business bead missing from the payload, which
degrades to an id-only row, never a fabricated title.

## 4. Comparison and recommendation

### 4.1 Comparison

| | A Work spine | B Work ledger | C Compact board |
| --- | --- | --- | --- |
| Primary question | "What is this run for, and what is left?" | "Does every work unit have exactly one execution, and do they agree?" | "Where is each work unit in the dependency order, and what is next?" |
| Information architecture | Document: source → work units → execution → provenance | Table: what ↔ how, with a state column | Board: rank columns × work-unit lanes (stacked when narrow) |
| Works with no drain? | Yes: work nodes are the spine | Yes: right side is the node's own evidence | Yes: one lane per work node |
| Works with no source? | Yes: formula/root headline | Yes: header omits source | Yes: title is formula/root |
| Works with no stage table? | Yes: flat order, no headers | Yes: flat order, no headers | Yes: rank labels |
| Learnability | Highest: business vocabulary first; formula last | High for mapping, but the two columns and verdict need a legend | Medium: rank vocabulary is generic; lane/cell reading needs a legend |
| Density | Medium (2 lines per deliverable) | Highest (1 line per work unit) | Medium at ≥100 columns; medium-low when stacked |
| Drill-down | `RET` title / `RET` member; `SPC`/`I` member drawer; `SPC` machinery fold, `C` control | `RET` per column; `SPC` per side; `!` failures | `RET` lane / `RET` cell; `SPC` cell; `SPC` machinery fold |
| Emacs implementation cost | **Low**: deliverable map + reorder + source card read | **Low-medium**: join + drift rule + two-column renderer | **Medium-high**: new board renderer, cell properties, truncation, stacked fallback |
| Data risk | Low: the card source read is the only new read | Low: join + a product rule (drift) | Low: existing index, pure projection |
| Failure mode | A long feature title dominates; done items still need collapsing | Dense; long titles truncate; drift rule can be argued | Board is unreadable for long titles at 100 columns unless it stacks |
| Accessible order | Strongest (linear document) | Good if rows read "work unit, execution, state" | Weakest spatially; requires words per cell, rank labels, and the stacked fallback |
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
   (`gc.drain_member_id` → business bead, ordered by `gc.drain_index`). No
   new gc call, no new parser, no change to the store.
3. The Runs card's source line is the only new read, and it fits the existing
   store/TTL/scheduler contract; it can ship with a placeholder and a
   `source unavailable` state.
4. It changes no keys and requires no stage vocabulary, so it is testable
   with the existing render harness and screenshot fixture.
5. When the optional facts are absent, A degrades to the flat
   dependency-ordered tree that already exists. There is no second IA and no
   per-formula selector.

**B is a refinement, not a first build.** Its same-line pairing is the right
treatment for A's deliverable row; the drift verdict is the only genuinely
new concept. If the team wants one layout, implement A's row as B's two
columns and skip a separate B view. If not, add B as a second layout
selected from the run view's existing `/` menu after A lands (it would
otherwise need a new key, which this design avoids). B must not become a
per-formula selector.

**C is optional, later, and Emacs-only.** It is a different question (flow
position), not a different formula. Its Emacs form is the wide board plus the
stacked narrow-pane fallback. It is not the default, not a prerequisite for
A, and not a deliverable of this round; it should only be built if A leaves a
real "where is each work unit?" gap that the rank headers do not close.

**Optional enrichment, explicitly.** A formula stage table, an implementation
convoy, plans, formula source, worker/session and timestamps may add labels
or rows. None of them may change the order, the grouping, or the set of
required facts. A formula without any of them is a normal run.

### 4.3 Phased rollout (gascity.el only)

0. **Model change.** Add the ordered deliverable map to
   `gascity-runs-index`: for each drain step, its member roots joined to
   `gc.drain_member_id` business beads and ordered by `gc.drain_index` /
   `gc.drain_count`; a missing business bead stays an id-only row. Keep the
   existing `:drains` map for the ladder. Pure, no new read. Acceptance:
   `be-0kjzs` yields the eight `(business, member)` pairs in index order;
   `ga-4hdav` and `ga-6iwrx` yield no deliverables; an inline drain yields
   one drain unit and no member roots.
1. **Emacs A, detail.** Source as headline when present, work-unit spine,
   paired member line, machinery below and folded (`C` still controls its
   control nodes), provenance footer. Optional stage headers only if a table
   is present. Update the manual's Run Detail section and the deterministic
   screenshot fixture.
2. **Emacs A, Runs card.** Source title/id line through the store with a
   placeholder; `SPC` keeps the drawer; `RET` opens the run. Acceptance in
   tmux and against the TRAMP test city `bright-lights`.
3. **Emacs polish.** Collapse completed work units, `/` filter, `w`/`I`/`!`
   on the correct half of a row, TTY and greyscale checks.
4. **Emacs B row refinement (optional).** Render A's deliverable row as the
   ledger's two columns with a state word; no separate B view unless the
   drift question proves worth its own layout.
5. **Emacs C board (optional, later).** The wide board plus the stacked
   fallback, offered from the existing `/` menu; no new key, no new read.
6. **Retire the stage table as IA.** Keep `gascity-run-stage.el` only as an
   optional header source, or delete it if the generic rank headers are
   enough. The stage table never defines structure again.

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
5. **Summary weight of the card read.** The Runs card's source read is one
   extra async process per visible run. What is the right TTL, and should
   the card show the source only for the visible window and the active
   section? (Recommend: yes — visible-first, the existing store scheduler,
   and no read for history rows until they scroll into view.)
6. **Cross-store members.** A member root names `gc.root_store_ref`; can it
   differ from the parent's? The run-beads read already spans the city and
   rig stores, but a member from a store the read did not include must render
   as an id with its plain state, not as a missing row.
7. **Empty ranks.** Is an empty rank meaningful in a board? Keep it only if
   it is a real dependency gap; do not let an empty column read as "failed".
8. **Naming.** "Work unit", "deliverable", "business item", "step", "bead" —
   pick one word for the UI and use it throughout. The bead is the data; the
   user's unit is the work unit (a deliverable when one exists).
9. **Live updates.** Does a member root's event invalidate the parent detail
   today? If not, A/B/C all need the parent view to refresh on member events,
   or the per-item progress will be stale while the page claims to be live.
10. **Optional stage table.** Keep it as a header source, or drop it entirely
    in favor of rank headers? If kept, it must never reorder or hide a step,
    and a formula without one must be indistinguishable in structure.
11. **Cycles and unknown deps.** The order is cycle-guarded; what does the UI
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
5. **Stage labels only when a table exists.** If a stage table is present,
   its headers agree with the step nodes for the same run. If no table
   exists, the view never claims a stage. A step the table does not name
   stays visible in the flat order.
6. **Runs card identity.** Two active `build-basic` runs are distinguishable
   by source title/id; the formula appears once per card. A run with no
   source is distinguishable by formula/root and says `(no source)`. A cold
   card read shows `source loading…`; a failed one shows
   `source unavailable`.
7. **Non-blocking.** No synchronous `gc` call on render, redisplay, timers or
   eldoc; the Runs card's source read is async, TTL'd, deduped, and
   visible-first; a cold read shows a placeholder. The ERT non-blocking
   guard is updated if a new input-free verb is added (none is expected).
8. **Remote.** Open the same views against `/ssh:localhost:~/bright-lights`
   from a fresh tmux Emacs; the layout, pairing and source render identically,
   and no render path stats a file or spawns a blocking process over TRAMP.
9. **Keys and folds.** `RET`, `SPC`, `C`, `I`, `w`, `!`, `g`, `q` keep their
   current meanings at the new objects; `g` and live refresh keep point and
   folds; the needs toggle (`T`) still restores the flat layout byte-for-byte.
10. **Accessibility.** In greyscale, every state has a word as well as a
    glyph; the reading order is work unit → execution → state; a board below
    90 columns stacks by rank and never truncates titles to illegibility.
11. **Scale.** With 40 work units the Emacs list collapses completed rows and
    keeps the active one visible; a board scrolls a column, not the whole
    page; the `/` filter still works.
12. **Docs and gates.** `doc/gascity.texi`'s Run Detail section and the
    deterministic screenshot fixture are updated; `scripts/gate.sh` and
    `scripts/lint.sh` pass.

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

### A.3 Reproduction notes

- Emacs capture: fresh `emacs -nw -Q`, `lisp/` of gascity.el and beads.el on
  `load-path`, default-directory `/home/roman/emacs-city`, `M-x
  gascity-runs`, `RET` on `be-0kjzs`, `C` to show control nodes. Pane size
  120×40; the mockups above are drawn at 100 columns per the brief.
- Generic-case capture: the same Emacs against the gascity.el store, `RET` on
  `ga-4hdav` and `ga-6iwrx`; both are closed, so the mockups show their final
  state. The ids and titles are real; the relative times are illustrative.
- No manual `build-basic` worktree was touched.
