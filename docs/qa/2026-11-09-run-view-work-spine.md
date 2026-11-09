# run-view work spine — live acceptance — 2026-11-09

Scope: WP-3 of `plans/run-view-work-spine/implementation-plan.md` (REQ-013,
REQ-014; AC-11, AC-12, plus the evidence halves of AC-1…AC-10).  This pass
exercises the shipped run-detail work spine, the Runs source card, the manual's
keys and the TRAMP path against the live `emacs-city` and `bright-lights`
cities, from a fresh non-graphical Emacs inside tmux.

**Result: PASS (executed) on the integration tree.**  The tree was
`9cf967e` (`feat(run-view): lead the run detail with the deliverable`) plus
`5b376ff` (`feat(runs): name each card's source business bead`), with the
WP-0 model, the WP-1 detail and the WP-2 card in one commit graph.  The one
merge conflict was resolved by keeping the WP-1 keyword unit kinds
(`:drain`/`:deliverable`/`:work`) that `gascity-run.el` consumes while keeping
the WP-2 card/source read; the fixture seeds the business beads under their
member runs so they are loaded without polluting the root run's machinery.
The fixture was regenerated from `doc/screenshots/fixtures/` and the two
changed views were captured and verified independently.

## Method

The pass used `scripts/e2e-harness.sh`: every Emacs/tmux call was bounded by
`timeout(1)`, the session was checked with `has-session` before keys/captures,
and the visible pane was read, not a synthetic buffer.  A fresh Emacs ran in
a dedicated tmux session at 200x60:

```sh
tmux new-session -d -s gce-wp3 -x 200 -y 60 \
  "cd /home/roman/emacs-city && EMACSLOADPATH='$LP:' emacs -nw -Q \
     --eval '(progn (require (quote gascity)) (setq server-name \"gce-wp3\") (server-start))'"
# $LP = <beads.el>/lisp:<beads.el>/.eldev/.../vui-1.4.0:<integration>/lisp
```

The live stores were read only.  No workflow was slung, retried, closed,
suspended or woken; the only writes in this pass are this report and the
item's own bookkeeping.

## 1. Local Runs cards (REQ-007, AC-6)

`M-x gascity-runs` in `/home/roman/emacs-city` shows the new three-line cards,
with the source line first and the formula/root on the identity line:

```
Active  1 · 2 sub-runs
  ⬣ Implement run-rendering design A (work spine) in gascity.…  ga-5klxs  open
     ga-036m5  build-basic · gascity.el · 56m            5/10 steps · 41 beads
     ◆◆◆◆◆⬣····  2/4 deliverables  implement    ● implementation-worker-3
    └ ⬣ Polish and docs: manual, screenshots, NEWS, QA report   ga-x37it  open
         ga-b373v  do-work · gascity.el · 33m              1/3 steps · 6 beads
         ◆⬣·  implement                    ● implementation-worker-3
    └ ⬣ Run detail: lead with the deliverable work spine        ga-4hsxy  open
         ga-4ot0u  do-work · gascity.el · 33m              1/3 steps · 6 beads
         ◆⬣·  implement                    ● implementation-worker-2
```

The two `build-basic`/`do-work` cards are told apart by their source titles,
not only by root id; the formula appears once per card.  `RET` still opens the
run and the source title is part of the card text, so the existing `/` filter
sees it.

## 2. Local rich run detail (REQ-001…REQ-006, REQ-009, REQ-010)

`M-x gascity-run-show RET be-0kjzs` renders the headline, identity line and
Work spine:

```
  Manual overhaul: Emacs-doc quality + shared demo fixture with gascity.el,
  default-theme screenshots, black-box QA
  be-tnd3z  open              run be-0kjzs build-basic · beads.el · closed 18h
  close    not recorded

Work  10/10 steps · 8/8 deliverables · 0 in flight · 0 failed · 45 beads
  Intake
  ◆ prepare                   be-nasax  pass      ec                       23h
  ...
  Implementation
  ◆ implement                 be-9sbk2   drain 8/8                         19h
    ◆ 1  Retarget the demo fixture to the shared /tmp/demo-…  be-rtqte  closed
    └ do-work    be-b9jhp   ◆◆◆ 3/3 pass                                   22h
    ...
  Run      be-0kjzs · 45 beads · formula build-basic
  Source   input convoy be-hzrwd · 1 tracked member
  Store    rig:beads.el   rig beads.el   city emacs-city
  Scope    (none)
  Formula  build-basic  contract graph.v2
  ...
  Implementation convoy be-o4er1  closed 8/8  manual-demo-consistency-implementation
▸ Machinery  control nodes folded (C) · needs tree (T) · SPC fold
Keys     RET open   SPC drawer   I inspect   w copy   ! diagnose   g refresh   q bury
```

Every delivery is paired with its member run by `gc.drain_member_id` and
ordered by `gc.drain_index`; no row is paired by position.  The three
denominators are labeled and separate.  The source is the input convoy,
the implementation convoy is named separately, and Machinery is folded.

## 3. Flat and standalone degradation (REQ-004)

`ga-4hdav` renders the same Work section with no stage table and no
deliverables phrase; its failed `do-work.implement` step carries the failure
header and the owner's close/failure facts.  `ga-6iwrx` (`review`, no
convoy) renders the formula headline plus `(no source)`, the flat two-step
spine, and the same provenance/Machinery shape:

```
  review
  (no source)                 run ga-6iwrx review · gascity.el · closed Oct  8
  close    not recorded

Work  2/2 steps · 0 in flight · 0 failed · 5 beads
  ◆ validate-context          ga-ed78s  pass      ec                    Oct  8
  ◆ write-report              ga-w3xz7  iter 1    ec                    Oct  8
  Run      ga-6iwrx · 5 beads · formula review
  Store    rig:gascity.el   rig gascity.el   city emacs-city
  Scope    (none)
  Formula  review  contract graph.v2
  Formula source ~/.gc/cache/…/review.formula.toml
  Plans    review-report.md
▸ Machinery  control nodes folded (C) · needs tree (T) · SPC fold
```

The fixture adds a third shape, `demo-inline`, where a `gc.kind=drain` node
has no member roots: it is exactly one work row, with no invented per-item
rows (seen in the regenerated `runs-default` image).

## 4. Keys on the live detail

With point on the `Machinery` header the sequence `SPC`, `T`, `C`, `I`, `w`
was driven through the real mode map:

- `SPC` unfolded the machinery; the existing step tree appeared below the
  spine, keeping the folded default on a fresh open.
- `T` toggled the needs tree and `C` the control nodes; both re-rendered from
  the already-loaded payload (no new `gc` read).
- `I` on the section header reported no step; `w` echoed `No bead id here`
  and left the kill ring untouched.  On a step row `I` opens the inspector
  and `w` copies the step's bead id (also exercised on the failed step in
  the `run-detail-default` capture).
- The detail re-rendered in place without blocking; the header's
  `updated 15:50:42` stamp appeared after a live delivery while the buffer
  was attached, and point stayed on the Machinery row.

The deliverable row's two objects are the business title (RET opens the
business bead) and the nested `└ do-work` line (RET opens the member run);
the source tests cover both halves plus `SPC`/`I`/`w`/`!` dispatch.

## 5. TRAMP (REQ-012)

From the same fresh Emacs, `default-directory` was switched to
`/ssh:localhost:~/bright-lights/`.  `gascity-runs` rendered the remote cards
without blocking and with the same source placeholders:

```
Runs  bright-lights   0 active · 4 waiting · 45 done · 9 failed (all time)

Waiting  4
  · (no source)
     bl-otov  pancakes · city · Sep 27                     0/5 steps · 6 beads
     ·····  dry                                                        waiting
  ...
```

`gascity-run-show bl-hdo3` then rendered the remote stand-alone detail:

```
  pancakes
  (no source)                     run bl-hdo3 pancakes · city · started Sep 27

Work  0/5 steps · 0 in flight · 0 failed · 6 beads
  · dry                       bl-r9f5                                   Sep 27
  · wet                       bl-oaba                                   Sep 27
  · combine                   bl-d302                                   Sep 27
  · cook                      bl-n3mk                                   Sep 27
  · serve                     bl-kj1v                                   Sep 27
  Run      bl-hdo3 · 6 beads · formula pancakes
  Store    city:bright-lights   city bright-lights
  Scope    (none)
  Formula  pancakes  contract graph.v2
  Formula source ~/bright-lights/formulas/pancakes.toml
▸ Machinery  control nodes folded (C) · needs tree (T) · SPC fold
```

No synchronous `gc`, file stat or TRAMP channel work runs on the render path;
the views kept their last payload while the remote read was pending.

## 6. Screenshots and docs

The deterministic fixture now carries the four shapes from the plan (rich
source-bearing run, flat run, standalone run, inline drain).  The rich run's
business beads are anchored under their member runs, so `gc convoy status
demo-convoy` resolves to canonical `demo-10` and the root machinery stays
clean.  From the fixture city:

```console
$ doc/screenshots/capture.sh --scope runs,run-detail
...
  run-detail-default         full= 83378  thumb= 81513
  runs-default               full= 20206  thumb= 19357
$ doc/screenshots/capture.sh --verify all
...
capture verified: 22 images byte-identical over two runs
$ doc/screenshots/capture.sh --check-isolation cockpit
...
capture isolated: 21 image(s) outside cockpit unchanged
```

The committed `run-detail-default` shows the Work spine, the failed Review
inspector and the folded Machinery; `runs-default` shows the source title/id
line on every card, the labeled deliverable progress, and the inline drain's
single row.  No image shows `source loading…`; the capture waits for the
per-visible-card source read before exporting.  `make -C doc` builds the
manual with the rewritten `Run Detail` sample and key table.

## 7. Live member change

The parent detail (`ga-036m5`) was left attached while member work continued.
A store invalidation for the member's `bead.*` event repainted the parent's
Work/machinery rows and added the `updated` stamp without a manual `g`; this
is the same `gascity-store-invalidate-event` route the live stream uses.  The
changed facts landed in place with point and folds preserved.  The pass did
not mutate any workflow to provoke a second change.

## Remaining risks / notes

- The live-refresh check above exercised the store route, not a separate
  synthetic member state transition; the existing ERT delta tests remain the
  regression guard for the face/stamp details.
- The integration tree is the WP-1/WP-2 merge used for this pass.  The final
  merge queue must keep the keyword unit kinds (`:drain`, `:deliverable`,
  `:work`) when it resolves the same conflict; symbol kinds would render every
  deliverable as a plain work row.
- The manual's Work sample is the historical `be-0kjzs` snapshot at 5/10
  steps; the live run is now 10/10 closed.  The layout and keys are what the
  sample documents; a later manual refresh can update the counts.
