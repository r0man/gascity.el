# Starter review fix summary — build-basic (`ga-036m5`)

| Field | Value |
| --- | --- |
| Fix bead | `ga-psp3q` (`review.build-basic-review-loop.iteration.1.review.apply-review-findings`) |
| Starter review input | `/home/roman/workspace/gascity.el/plans/run-view-work-spine/review-report.md` (verdict `iterate`) |
| Review context | `/home/roman/workspace/gascity.el/plans/run-view-work-spine/code-review-context.md` |
| Implementation worktree | `/home/roman/workspace/gascity.el/worktrees/ga-x37it` (branch `run-view-integration`) |
| Launcher rig root | `/home/roman/workspace/gascity.el` — not edited; publish owns propagation |
| Integration commit | `07c11a0` — `fix(run-view): integrate the Runs card onto the W1/W2 model (ga-036m5)` |
| Commit stack | `e3fd295` (WP-3 docs) → `13d2dd6` (WP-0 model, cherry-pick of `a247d49`) → `b7134ca` (WP-1 detail, cherry-pick of `9e83594`) → `07c11a0` (WP-2 card integrated) → `a5c5622` (QA/summary re-record) |
| **Verdict** | **`done`** — acceptance, test evidence and simplicity all approve after this pass |

## What changed

The three review lanes returned `iterate` for one root cause: W1/W2/W3 were
never committed as one integrated tree, and W3 was an independent
re-implementation of the W1 model with a conflicting unit-kind vocabulary.
The fix lane built the real stack on `main` (which carries the W1 revert
`2f70727`) and committed one integration tree.

### RF-1 — Integrate W3 onto W1+W2 with one unit-kind vocabulary and one test copy

- Base is `9e83594` (W1 `a247d49` + W2), rebased onto `5094c71` via
  cherry-picks `13d2dd6` and `b7134ca`; no conflicts.
- W1's model API is kept: `gascity-runs-index` (`:beads`/`:deliverables`),
  `gascity-runs-bead`, `gascity-runs--root-bead`, `gascity-runs-deliverables`,
  `gascity-runs-work-units`, `gascity-runs-unit-counts`,
  `gascity-runs--unit-state`, `gascity-dashboard--step-ref` and the
  `gascity-runs--step-ref` alias.  W3's duplicate step-ref/number/
  deliverable helpers and its duplicate index/work-unit/counters code were
  deleted.
- The card/source layer is added from W3: `gascity-runs--source-of`,
  `--run-source`, `--source-line`, the three-line `--card`, `--visible-runs`,
  `--visible-convoys`, the buffer source cache and the store effect, and the
  `gascity-runs-summary` `:deliverable-progress` / `:beads` keys.  The two
  kind checks use the keyword vocabulary (`:deliverable`, `:drain`).
- Tests: W1's five model tests and W2's ten `run-detail-*` tests are kept;
  W3's five duplicate WP-0 tests, its
  `gascity-test-runs-unit-counts-labeled-separately` fixture-count test, and
  its restored stage-group tests were not carried.  W3's eight
  card/source tests and `gascity-test-runs-step-ref-is-total` were added.
  `make check` no longer aborts on redefined ERT names.
- W2's deletion of the stage-group IA in `lisp/gascity-run-stage.el` is
  preserved.

### RF-2 — Commit and verify the merged tree; re-record the QA/screenshot proof

- The integrated tree is committed (`07c11a0`, docs `a5c5622`).
- `docs/qa/2026-11-09-run-view-work-spine.md` now names the integration
  commit and records the re-run local and `bright-lights` tmux passes on it.
- The QA report no longer claims a scratch tree; it names the commit chain
  and the ten `run-detail-*` tests that cover both halves of a deliverable
  row.
- No deprecated `doc/gascity.info-*` outputs are carried.

### RF-3 — Keep W1's `gascity-runs-unit-counts`

- W1's counters and `gascity-runs--unit-state` are the only ones in the tree.
  `:in-flight`/`:failed` count every non-drain unit (a `:work` row included),
  so a flat/standalone run with an active step reports `1 in flight`.
- New ERT `gascity-test-runs-unit-counts-flat-in-flight` asserts exactly that
  for a two-step flat `do-work` run with one `in_progress` step.
- W2's duplicated `gascity-run--work-unit-done-p` now folds onto
  `gascity-runs--unit-state` (still ignoring `:drain` headers).

### RF-4 — Remove the write-only `:node` unit field

- `:node` is gone from every work-unit row; `gascity-runs--work-node`,
  `gascity-runs--tree` and the index `:trees` cache are deleted.  W2's
  `gascity-run--node-map` is the one id→node representation.

### RF-5 — Card source effect must not read closed-history runs

- `gascity-runs--visible-runs` is Active + Waiting + Failed only.  Closed
  history renders through `gascity-runs--history-row` with no source line and
  never triggers a `convoy status` read.
- The unused CTX `:visible-runs` key was not added; only `:visible-convoys`
  is written and read by the effect.

### RR-7 — Drop unused summary counters

- `:units` and `:deliverable-counts` were computed and documented but never
  rendered.  Both are removed from `gascity-runs-summary` and its docstring;
  `:beads` and `:deliverable-progress` stay because the card renders them.

### ME-1…ME-4

- **ME-1**: the real W1→W2→W3 stack now exists, so W3's “seeded with
  WP-0/WP-1” claim is true where it matters; the W3 item summary is not in
  the integration tree because the W3 commit was re-applied, not merged.
- **ME-2**: the WP-3 summary now states that a docs item has no red phase of
  its own and names the WP-0/WP-1/WP-2 red/green evidence.
- **ME-3**: the TRAMP pass was re-run on the integration commit and recorded
  in the QA report.
- **ME-4**: the QA report's “the source tests cover both halves” sentence is
  replaced with the specific ten `run-detail-*` tests and the executed key
  pass.

## Proof (from the integration worktree, `pwd -P` verified)

```console
$ cd /home/roman/workspace/gascity.el/worktrees/ga-x37it
$ pwd -P
/home/roman/workspace/gascity.el/worktrees/ga-x37it
$ find lisp -name '*.elc' -delete && scripts/gate.sh
>>> gate: PASS (compile clean + tests green)
Ran 1088 tests, 1088 results as expected, 0 unexpected

$ scripts/lint.sh
exit 0 (checkdoc clean; package-lint is not installed locally)

$ make -C doc
make: Nothing to be done for 'all'.

$ doc/screenshots/capture.sh --verify all
verify: byte-identical for 25 image(s) (scope all)

$ doc/screenshots/capture.sh --check-isolation cockpit
isolation: OK; 48 non-selected image(s) byte-identical (scope cockpit)
```

Interactive acceptance (fresh non-graphical Emacs inside tmux, `gce-fix`,
200x60, driven through the real mode maps):

- Local `emacs-city`, `/home/roman/emacs-city`: the `ga-036m5` card renders
  three lines (`Implement run-rendering design A …`, `ga-036m5 build-basic ·
  gascity.el · 1h  7/10 steps · 41 beads`, `◆◆◆◆◆◆◆···  4/4 deliverables
  review  ● implementation-worker-1`).  RET opens the run detail; the Work
  spine shows `4/4 deliverables` and the four business/member pairs.
- On the deliverable pair: SPC on the business title echoes `Business bead;
  RET opens it`; RET opens `ga-2i1hs` in `beads-show[gascity.el]`; RET on the
  `└ do-work ga-nvipz` half opens the member run detail.  On a step row `I`
  opens the inspector, `w` prints `Copied ga-qo230`, `!` prints `Run has no
  failed step`; `C`/`T` toggle the machinery tree, `g` restamps
  `updated 16:34:28`, `q` buries.
- Remote `/ssh:localhost:~/bright-lights`: the Runs view renders over TRAMP
  with `(no source)` placeholders and no blocking; `bl-hdo3` opens with
  `(no source)`, `Work 0/5 steps · 6 beads`.  `I`/`w`/`!` on the `dry` step
  work (`Copied bl-r9f5`, `Run has no failed step`); `C`/`T`/`g`/`q` work
  (`updated 16:35:23`).  The city has no drain run, so the remote arm has no
  deliverable row; the local arm is the deliverable-pair evidence.

## Residual risks / follow-ups (not execution failures)

- **RR-1** — `package-lint` is not installed locally; the local lint gate is
  checkdoc only.  CI installs it.  This summary does not claim CI parity.
- **RR-2** — the stale W4 source anchor `ga-x37it` is still `open` while its
  outcome bead `ga-b373v` is `closed`/`pass`.  Reconciliation is the
  finalizer's job; the worktree evidence is `e3fd295`.
- **RR-3** — W2's implementation summary is anchor-unrecorded; its evidence
  is `/home/roman/workspace/gascity.el/plans/run-view-work-spine/build/implementation-summary-ga-4hsxy.md`,
  `9e83594` and the QA report.  Traceability gap only.
- **RR-4** — one async `convoy status` per visible run is the accepted design
  cost; the TTL, dedup and buffer cache guards are preserved.
- **RR-5** — the collapse boundary is `> 40` units while REQ-011 says “40+”;
  ERT uses 41.  Pin a boundary test if the wording is tightened.
- **RR-6** — the manual's Work sample is the historical `be-0kjzs` 5/10
  snapshot; layout and keys are current.
- **RR-8** — optional polish (redundant `let`, stale `gascity-run-app` CONVOY
  docstring, two `pending` branches) was not taken; no behavior impact.
- **RR-9** — image determinism has no committed ERT in this tree;
  `capture.sh --verify all` is the manual guard.

## Publish notes

- Publish from `run-view-integration` in
  `/home/roman/workspace/gascity.el/worktrees/ga-x37it`; the branch is local at
  `a5c5622` and has not been pushed.
- The launcher checkout at `/home/roman/workspace/gascity.el` is intentionally
  unchanged (untracked plan artifacts only).  An unchanged launcher root is
  not a review failure.
