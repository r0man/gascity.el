# Fresh `emacs -Q` manual walkthrough — gascity.el (2026-10-16)

Work bead `ga-hrin3` (WI-10, workflow `do-work`, convoy `ga-q0yk2`, owner
gascity.el). Plan workstream W8 (REQ-007, REQ-012), decision D6: prove from a
clean checkout that a **fresh Emacs** configured with **only the manual's own
Installation/Getting Started instructions** can load the porcelain and walk the
documented views, and fix every prose/ordering/screenshot gap found, in scope,
in `doc/gascity.texi`.

## Setup

| | |
|---|---|
| Target city | `~/bright-lights`, read as `/ssh:localhost:/home/roman/bright-lights` (never the live `burningswell` host) |
| Checkout | worktree `worktrees/ga-hrin3`, stacked on the WI-09 base `084899d` (clean) |
| Emacs | GNU Emacs 31.1, `emacs -nw -Q` inside tmux session `gce-hrin3` (server `gce-hrin3`), non-graphical |
| gc | 1.5.0 on `localhost` via `ssh -o BatchMode=yes localhost` |
| Load path | the manual's recipe: worktree `lisp/` + `~/workspace/beads.el/lisp` + bundled `vui-1.4.0` |
| Bounds | `. scripts/e2e-harness.sh`; every `emacs`/`emacsclient`/`tmux` call under `timeout(1)`; per-view settle deadline 90 s |

Method: start a fresh `emacs -nw -Q` (server only), then follow the manual's
**Loading from a checkout** recipe literally, first with no extra dependency
paths (to test the prose as written) and then with the dependency paths the
**Requirements** chapter names. Visit `city.toml` over TRAMP so
`default-directory` is the remote city (the manual's documented resolution
route), open each view with its real `M-x` command, wait for the store to
settle, and dump the rendered buffer. The sling, mail reply and nudge are
driven through the real tmux pane to their confirmation/prompt point. Rendered
pane text and dumped buffers are the evidence.

## Install / load

The manual's **Loading from a checkout** recipe, as written:

```elisp
(add-to-list 'load-path "/path/to/gascity.el/lisp")
(require 'gascity)
```

Observed against a fresh `emacs -Q`:

```
FAILED: (file-missing "Cannot open load file" "No such file or directory" "beads-prefix")
```

The **Requirements** chapter says `beads.el`, `vui` and `transient` must be on
`load-path`, but the loading recipe did not carry them and gave no example, so
a reader following the section verbatim cannot load the package. This is gap
**G1** below; fixed in `doc/gascity.texi`. With the dependency directories the
Requirements chapter names (`~/workspace/beads.el/lisp` and the bundled
`vui-1.4.0`), `(require 'gascity)` succeeds (`gascity`, `vui`, `beads-prefix`
features all present) and every view command is bound.

## Checklist

"Open" is the time the command blocked the command loop; the views mount
asynchronously, so this is near zero after first contact. "Ready" is open →
store settled.

| View | Command | Result | Open / ready (s) | Note |
|---|---|---|---|---|
| Cockpit | `gascity-dashboard` | **PASS** | ~0 / already settled | header `● live`, all six sections render |
| Agents | `gascity-agents` | **PASS** | 0.006 / 0.78 | 3 idle rows; stopped hidden by the default filter |
| Agents tree | `gascity-agents-tree` | **PASS** | 0.026 / 0.84 | City + hello-world nodes, stopped `bd.dog-1/2` |
| Sessions | `gascity-session-list` | **PASS** | 0.025 / 0.76 | 3 rows incl. `mayor` |
| Rigs list | `gascity-rig-list` | **PASS** | 0.002 / 0.50 | 2 rigs |
| Rig dashboard | `gascity-rig-dashboard` hello-world | **PASS** | 0.003 / 0.75 | Agents / Ready / In progress / Orders / Dolt |
| Runs | `gascity-runs` | **PASS** | 0.029 / 1.39 | 0 active · 7 waiting · 30 done · 3 failed |
| Events | `gascity-events` | **PASS** | 0.002 / ~0 | churn folded into `×N` rows |
| Mail inbox | `gascity-mail-inbox` | **PASS** | 0.028 / 0.65 | rows with `●` unread |
| Mail | `gascity-mail` | **PASS** | 0.005 / 0.50 | same buffer (alias; see O1) |
| Health | `gascity-health` | **PASS** | 0.003 / 1.03 | Store `◐` partial (bright-lights condition, correct UI) |
| Cities | `gascity-cities` | **PASS** | 0.005 / ~0 | local + TRAMP rows |
| Beads delegation | `gascity-rig-beads` hello-world | **PASS** | async / — | `beads-dashboard-mode` scoped to the remote store |

Everything renders from `gc … --json`; no `■ gc` failure line, no un-timeouted
evaluation, no hang. The Health view's `Store ◐` and the cockpit's
`▲ store health: …` line render the city's `partial` status (the
`bright-lights` Dolt/store latency recorded in the 2026-10-16 TRAMP QA pass),
not a gascity defect.

## Interactive keys exercised (through the pane)

- `M-x gascity-dashboard` from the TRAMP `city.toml` buffer → cockpit mounts;
  header reads `bright-lights @localhost  ● live`.
- Agents view → `TAB` moves to the first thing, `M` raises the nudge prompt
  `Message to core.control-dispatcher:`; `C-g` aborts cleanly.
- Sling (`S`) → the adaptive transient `Sling — bright-lights`, header
  `Sling (no work — A or point at a bead) to hello-world/gc.implementation-worker`,
  footer `✓ Ready — plain route · target rig-scoped · no vars`, groups
  `What` (`A`, `f`), `Who` (`T`) and `Actions` (`s Sling…`, `P`, `r`, `g`).
- Mail inbox → `RET` on a row shows the thread buffer
  `*gascity-mail-thread: thread-…*`; `R` reaches the `Reply subject:` prompt
  with the reply prefilled.

## Beads delegation

`b`, `j b` and the cockpit's bead rows delegate to beads.el, scoped to the
owning rig's store (`DESIGN.md` §4.3). Exercised with
`gascity-rig-beads "hello-world"` from the remote city buffer: it opens
`*beads-dashboard</ssh:localhost:|hello-world>*` in `beads-dashboard-mode`,
with `default-directory` `/ssh:localhost:/home/roman/hello-world/`, and renders
that rig's `bd`-owned store (Stats, Recently Closed, In progress, Ready,
Blocked, Epic Progress, Stale, Orphaned, Recent changes). The first call from
`*scratch*` (local city, cold rig memo) correctly echoed
`Could not resolve the bead store for rig hello-world` — the documented
no-silent-local-fallback behaviour, since the rig is not in the local city.

## Gaps and fixes

| ID | Gap | Fix | Files |
|---|---|---|---|
| **G1** | **Loading from a checkout is not runnable.** The recipe adds only gascity's `lisp/`; `(require 'gascity)` fails with `Cannot open load file: beads-prefix` on a fresh `emacs -Q`. The Requirements chapter names the deps, but the load example does not show them. | The section now says to put the dependencies on `load-path`, gives a complete four-form example (`gascity.el/lisp`, `beads.el/lisp`, the bundled `vui`), and explains that `beads.el`/`vui` are not on ELPA and where the bundled `vui` lives. | `doc/gascity.texi` |
| **G2** | **`M-x gascity-sling` does not open the adaptive menu.** The Task Guide and Sling chapter say `M-x gascity-sling` opens the `gascity-sling-dispatch` transient; in fact `gascity-sling` is a separate two-prompt command (`Sling to target:` + `Bead id or task text:`). The menu is `gascity-sling-dispatch` (what `S` is bound to). | The manual now names `M-x gascity-sling-dispatch` in all three prose spots and indexes `gascity-sling-dispatch`. | `doc/gascity.texi` |

No screenshot gap was found: every `@shot` in `doc/gascity.texi` resolves to a
committed `…-thumb.png` (`gascity-test-manual-texi-shots-resolve` passes), and
the walkthrough surfaced no view whose committed image is stale. No ordering
gap was found.

### Reconciled concurrent edit

A duplicate sibling worker session (the `implement` step assignee
`ec-wisp-oixtjh`, whose lease had expired and whose tmux session is gone) had
rewritten the Get Started **Install and Start** section into a three-step
Load / @command{gc} / Open list while this pass ran. The rewrite is coherent
and agrees with G1 (its Load step says "and its dependencies on the
`load-path`"), and the manual ERT suite passes over the combined tree, so it is
kept in the same commit. This report and the commit describe the reconciled
tree, not either worker's draft in isolation.

## Observations (not filed as gaps)

- **O1 — `gascity-mail` and `gascity-mail-inbox` are the same command.** In
  the source `gascity-mail-inbox` is a `defalias` of `gascity-mail`; the
  manual's "Mail View" and "The Mail list" sections both describe
  `gascity-mail-inbox-mode`. This is intentional (the alias is the name menus
  and older bindings use), not a defect; recorded here so the duplication in
  the Mail chapter is not mistaken for two views.
- **O2 — a view opened outside a city prompts to choose one.** Calling
  `gascity-dashboard` from `*scratch*` (local repo directory) echoed
  `No city at … choose a city` and blocked in the minibuffer. This is the
  documented, desirable guard (`open it from inside the city tree`), not a
  gap.
- **O3 — one transient message (`Unbound suffix: 'RET'`) was seen once while
  driving the sling transient.** It was not reproduced on the clean re-run
  (the transient rendered and `C-g` aborted normally) and is attributed to a
  stale echo from the interrupted programmatic probe, not a view defect.

## Verification

Manual-only load, as fixed (the manual's own recipe plus the dependency paths
its Requirements chapter names), in the fresh Emacs:

```
(require 'gascity)                          => loaded
(featurep 'vui) (featurep 'beads-prefix)    => t t
(gascity-dashboard) from the remote city    => cockpit mounts, ● live
```

Manual ERT suite against the edited `doc/gascity.texi`:

```
$ emacs --batch -Q -L lisp -L lisp/test \
    -L ~/workspace/beads.el/lisp \
    -L ~/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0 \
    -l lisp/test/gascity-manual-test.el \
    --eval '(ert-run-tests-batch-and-exit "^gascity-test-manual")'
Ran 20 tests, 20 results as expected, 0 unexpected
```

Observed: **pass** — including `gascity-test-manual-reference-coverage`,
`gascity-test-manual-reference-entry-indexes`,
`gascity-test-manual-texi-shots-resolve` and
`gascity-test-manual-no-burningswell`, so the two edits keep the reference,
index and screenshot contracts intact.

The standard quality gate (`scripts/gate.sh`: byte-compile warnings-as-errors
+ whole ERT suite) and the CI lint command (`scripts/lint.sh`) are run from
the worktree before this change is committed; see the summary file for the
final result.

## Remaining risks

- The walkthrough used Emacs 31.1; the manual still targets 29.1+, and the
  `transient` version note (GNU ELPA on 29.1--30) is asserted, not re-run
  here. The syntax added in G1 is version-agnostic.
- "Passes using only the manual" is proven by this recorded manual-only
  `emacs -Q` session; ERT cannot host a literal fresh interactive user
  session (decomposition open item, WI-10 proof form).
- The G2 fix documents the real command; it does not change the product, so
  `M-x gascity-sling` still runs the older two-prompt command if a user types
  it from memory.
