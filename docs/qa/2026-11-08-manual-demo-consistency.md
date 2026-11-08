# Manual black-box QA — manual demo consistency (P7, ga-dsqrf)

Bead: `ga-dsqrf` (P7 of `plans/manual-demo-consistency/implementation-plan.md`,
REQ-013; docs-only, REQ-014). Date: 2026-11-08.

Base tree: the P6 dependency chain at `2c163ac` (P1–P6; the prepared
worktree `worktrees/ga-dsqrf` was fast-forwarded from `main` to that
commit). No `lisp/` file changed in this pass.

## Method

A reader pass, not a code review: build the manual first, then read only
`doc/gascity.info`/HTML (no `lisp/*.el`, no tests) and drive a fresh,
uniquely named non-graphical Emacs with real keystrokes in tmux. Every
`emacs`/`emacsclient`/`tmux` call ran under `timeout(1)` per
`scripts/e2e-harness.sh`; the session was checked before every
`send-keys`/`capture-pane`; no unbounded blocking call was left running.

Evidence for the pass:

| Fact | Value |
| --- | --- |
| `emacs --version` | GNU Emacs 31.1 |
| `guix describe` | channel `https://github.com/r0man/guix-channel`, branch `main`, commit `9446304dd81dee40de99afa43f2e254207e1dc4d` |
| `gc` | 1.5.1 (Health view), `GC_HOME` = `/tmp/gascity-fixture/gc-home` |
| Fixture dataset | `doc/screenshots/fixtures/beads-fixture.jsonl`, SHA-256 `6504c508bd25f3a2efc8a0e99bc940767b3306ae41352077fa446d2d6c319ca8` |
| Fixture | city `/tmp/gascity-fixture`, project/rig `/tmp/demo-project` (`demo-rig`) |
| QA Emacs | `emacs -nw -Q` in tmux, server `ga-dsqrf-bbqa`/`ga-dsqrf-bbqa2`, `-l` an init that only adds the three documented `load-path` entries, requires `gascity`, and calls `gascity-dashboard` |
| Manual build | `./autogen.sh && ./configure --with-beads-dir=$HOME/workspace/beads.el && make -C doc` (the worktree had no generated `doc/Makefile`; warning-free) |

The fixture was created exactly as the corrected demo recipe now reads:

```sh
doc/screenshots/fixture.sh --create
doc/screenshots/fixture.sh --seed
export GC_HOME="$TMPDIR/gascity-fixture/gc-home"
cd "$TMPDIR/gascity-fixture"
gc import install
tmux -L gascity-fixture new-session -d -s demo-agent
tmux -L gascity-fixture new-session -d -s demo-reviewer
```

## First-pass section log (tried / happened / sufficient)

Keys are the exact keys sent. "Sufficient" means the manual alone let me
predict and use the behaviour.

| # | Section | Tried | Happened | Sufficient |
| --- | --- | --- | --- | --- |
| 1 | Open the city | `M-x gascity-dashboard` from the city | Cockpit in `gascity-dashboard-mode`; header `■ controller down`, summary `agents 0/4 ▲   sessions 0   runs 1 ⬣   ready 9   mail 0`; Needs you 4; Moving `1 run · 0 workers` with the ladder and the `demo-3` worker row; Work 9 ready/1 in progress/1 blocked; Activity one `gc events` retry line; Rigs 2 | Yes after the text fix (summary glyph `⬣` not `●`, plus `mail 0`; Moving also shows the bead row) |
| 2 | Read the cockpit | `TAB`/`S-TAB`, `SPC`, `RET`, `+`/`-`, `/`, `g`, `W`, `?`, `q` | TAB moves between things; SPC opens a row drawer, closes the run inspector and folds a section; RET on the Needs-you header opened Events; `+`/`-` change the row cap; `/` opens the filter transient; `g` refreshes; `W` toggles to `○ live off` and back; `?` shows the dispatch (Jump/Agent at point/Work/City); `q` buries | Yes after two fixes (filter menus had no close key — `q` is an unbound suffix; `W` off state) |
| 3 | Agents | `j a`, `/ -s all`, `M`, `i`, `v` | Default table empty with mode line `Agents 4 stopped [1/1] (state=running)`; `/ -s all` reveals `bd.dog-1`, `bd.dog-2`, `core.control-dispatcher`, `core.control-dispatcher` (rig `demo-rig`), all `○ stopped`; `M` echoes `bd.dog-1 has no session; pool slots start when work arrives`; `i` opens the detail | Yes after the nudge wording fix (`gc`'s refusal → the refusal; the message is gascity's) |
| 4 | Sessions and attach | `j s`, `RET`/`t`, `i` | Two rows: `demo-rig/gc.implementation-worker … asleep claude /tmp/demo-project` and `demo-rig/gc.reviewer …`; attach opened `*gc-agent-demo-agent@…*` with a live prompt; `i` detail showed the Work join (`⬣ demo-3 in_progress`, `· demo-4 blocked`), transcript failure line, Mail none, History 3 | Yes after the recipe fix (attach fails with `Can't find tmux session: demo-agent` unless the session is on the city's tmux socket) |
| 5 | Runs, run detail, inspector | `j r`, `RET`, `!`, `SPC`, `T`, `C`, `b` | `1 active · 0 waiting · 0 done · 0 failed (all time)`; card `◆◆◆◆◆◆◆◆✕··  review  8/11  ✕ build-basic.review  code_review`; detail header root/step/class/reason/store/scope/formula and `Steps 8/11 · 12 beads` grouped Intake→Finalization; `!` expanded Review and iteration 1 with `assignee/session gone` and `events unavailable`; `T` toggled the needs tree; `b` opened the root bead in beads.el (store `demo-project`); `C` toggled control nodes | Yes |
| 6 | Beads and work | `TAB` to `demo-1`, `RET`, `j b`, `c` | RET opened `*beads-show[demo-project]/demo-1 …*` scoped to the rig; `j b` prompted `Beads for:` (beads dashboard for the chosen store); `c` opened the bead actions menu | Yes after the tour text fix (`j b` is the dashboard, not the bead at point) |
| 7 | Events and Health | `j e`, `j h`, `!` | Events header `■ gc events: … could not auto-discover the supervisor API …` above an empty table; Health `■ attention`, `■ controller down · ■ unusable · not suspended`, `gc 1.5.1 · store BdStore`, `Store  none`, `Rig stores 1` (`demo-rig … beads initialized`), `Doctor not run`, then `Doctor running…` after `!` | Yes after `Store  none` wording |
| 8 | Convoys and Orders | `j v`, `j o` | Convoy list empty; order list contains `demo-health cooldown 5m` and `demo-nightly cron 0 3 * * *` among the pack orders, with paging/filter keys documented | Yes |
| 9 | Mail | `j m` | `gascity-fixture mail  0 unread / 0`, empty table, `○ live: supervisor down` | Yes |
| 10 | Sling and preview | `S`, `q`, `S`, `f` → `mol-do-work`, `A` → `demo-3`, `T` → `demo-rig/gc.implementation-worker`, `s`, `q` | Plain shape pre-seeded the bead at point (`Sling bead demo-1 …` with point on `demo-1`), footer `⚠ No target — T to choose, or s will prompt`; remembered state survived `q`+`S`; `x` produced `Sling (no work — A or point at a bead) to (no target — T or default)`; with the formula and no work: `Run mol-do-work (formula) on …`; with `demo-3`: `Run mol-do-work against bead demo-3, drained by …`; preview Validation `✓ target`, `✓ work demo-3 (the formula requires it)`, `✓ no required vars`, Recipe DAG, Routing plan dry run failing with `agent "demo-rig/gc.implementation-worker" not found in city.toml`; `q` aborted the preview | Yes after three tour fixes (preseed is the bead at point; cold menu is `x`, not `q`+`S`; the sling menu already closed when the preview opened) |
| 11 | Cities, costs, dolt, rig lists | `j c`, `j $`, `j d d`, `j l` | Cities listed only `gascity-fixture` (with the documented `GC_HOME`); Costs two rows (`demo-run-build`, `demo-run-review`) with the "no usage recorded" note; Dolt list reads `nothing to do` for the proxied scope; rig list shows `demo-rig` and the HQ `gascity-fixture` | Yes |
| 12 | Bookmarks / lighter | `C-x r m` (default `gascity: gascity-fixture`), `M-x gascity-mode-line-mode` | Bookmark default name matched; the global lighter reads `GC` in the mode line | Yes |

Additional manual-only checks that passed: `RET` on a section header opens
the view behind it (Needs you → Events), `SPC` on a run row opens its
ladder drawer, `W` is on both the cockpit and Health, and the agent
detail header prints the same hints (`f follow  a v peek  ? help`).

## Gap / fix list (all docs-only)

1. **Demo recipe did not export `GC_HOME`.** A literal copy of the recipe
   left `gc` on the real `GC_HOME`: `gc cities` listed the developer's
   live cities and the Cities view contradicted the manual. Fixed: the
   recipe exports the printed `FIXTURE_GC_HOME` and explains why.
2. **Demo recipe did not make the seeded tmux sessions attachable.** The
   sessions live on the city tmux socket (`gascity-tmux-socket`
   auto-detects the city name), so `RET`/`t` failed with `Can't find tmux
   session: demo-agent` after following the recipe. Proven by creating
   `demo-agent` on the default socket (attach still failed) and then with
   `tmux -L gascity-fixture new-session -d -s demo-agent` (attach
   worked). Fixed: the recipe starts `demo-agent` and `demo-reviewer` on
   that socket; `Attach to a Terminal` now names the socket rule and the
   demo command.
3. **Cold fixture `GC_HOME`.** After a teardown/recreate the city's pack
   imports were not cached: the first paint showed a `store health:
   runtime status probe incomplete` row and agents as `unknown`. Fixed
   in the manual by adding `gc import install` (the one networked step)
   and a sentence about the warm-up row/`g`; the fixture-side fix is
   filed as `ga-dkxzm`.
4. **Filter menus had no documented close key.** `q` in the filter
   transient echoes `Unbound suffix: 'q' … [gascity-tabulated-quit]`;
   `C-g` closes it. Fixed: `Filter menus` now says the menu stays open
   and `C-g` closes it (the menu has no `q` binding).
5. **`Agent Detail` key table was wrong.** The detail binds the agent
   actions under the `a` prefix (`a n/s/k/w/D/r/u/d/t/v/i`), because the
   view can hold bead rows (DESIGN-write-actions §10); only `f`, `c`,
   `S`, `g`, `q` and `RET` are direct. The old table promised direct
   `M`/`s`/`K`/`w`/`D`/`R`/`U`/`d`/`t`; `t` was `undefined`. Fixed the
   table and the two sentences that sent `t` to the detail
   (`Attach to a Terminal`, the tour).
6. **Tour summary line** said `runs 1 ●`; the view renders `runs 1 ⬣`
   and includes `mail 0`. Moving also lists the `demo-3` worker row
   under `1 run · 0 workers`. Fixed.
7. **Tour nudge wording** attributed the refusal to `gc`; it is
   gascity's pre-flight refusal. Fixed (and the exact echo is now
   quoted).
8. **Tour `j b`** claimed it opens the bead at point; it opens the beads
   dashboard for the rig at point / a chosen rig (`Beads for:`). Fixed.
9. **Tour sling state.** Plain `S` pre-seeds the bead at point (so the
   sentence is now "demo-3 in the screenshot", not an unconditional
   preseed); the cold menu is reached with `x` (the menu remembers
   work/formula/target across openings, per `Remembered state`), not
   `q`+`S`; and `q` in the preview only aborts the preview because the
   sling menu already closed when the preview opened. Fixed.
10. **Tour `W`** now names both header strings (`○ live: supervisor
    down` and `○ live off`); **Health** now says `Store  none` instead of
    an empty `Store`.

## Second pass (fresh Emacs, corrected manual)

A second session (`ga-dsqrf-bbqa2`, fresh fixture created with the
corrected recipe, including both city-socket tmux sessions) re-ran every
section above with the same keys. Result: the corrected text matched the
screen in every step — cockpit summary/Needs you/Moving, `W` on/off,
Agents default-empty then `/ -s all` + nudge echo, sessions `t` attach
(live prompt), `i` detail Work join and `a t` attach, run detail and
`!`, `j b` prompt, Events/Health, convoys/orders, mail, and the full
sling path (`S` preseed → `x` cold → `f` → `A demo-3` → `T` → `s`
preview → `q`). `make -C doc` is warning-free after the edits.

Remaining open manual gaps: none found. Remaining observed defects are
runtime/fixture work, filed separately:

- `ga-0onhi` — the rig dashboard shows `unknown` for
  `demo-rig/core.control-dispatcher` while the cockpit/Agents table show
  `stopped` for the same idle agent (runtime, out of scope by REQ-014).
- `ga-dkxzm` — a cold fixture `GC_HOME` starts with uninstalled city
  imports (fixture, documented in the manual for now).

## Limitations

- This pass covers the local fixture city. The remote-city and
  `bright-lights` flows (`docs/DESIGN`/`AGENTS.md` e2e protocol) were not
  re-driven here; they are unchanged by this plan and were covered by
  earlier QA reports.
- The transient "store health" row is timing-dependent (probe warm-up);
  the report records the settled states after `g`, which is what the
  tour documents.
- Access-control and secret handling are untouched (docs-only change).
