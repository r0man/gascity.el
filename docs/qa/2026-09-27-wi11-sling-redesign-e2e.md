# Sling redesign (WI-11) — tmux-Emacs TRAMP e2e acceptance pass

- Date: 2026-09-27
- Item: WI-11 — End-to-end verification of the sling command redesign
  (work item bead ga-3wpi, source anchor of the implementation step
  ga-nqyt; workflow root ga-eavt, plan
  `plans/sling-command/implementation-plan.md` §WI-11, REQ-014)
- Code under test: worktree `worktrees/ga-3wpi` — the item's prepared
  HEAD (WI-1…WI-4, WI-9 merged) with the still-open sibling items
  merged in before the pass: WI-5 typed How vars (`cc5d836`), WI-6
  live footer (`80c35dd`); WI-8's follow offer was already in the tree
  (its commit `0853cd9` duplicates code that landed with ga-f7a4, so
  its merge was aborted as a no-op).  Two integration fixes came out
  of this pass (§Findings) and are part of the item's commit.
- Environment: fresh `emacs -nw -Q` 30.2 in tmux (`gce-e2e`, harness
  `scripts/e2e-harness.sh`, every emacs/tmux call timeout-wrapped),
  package loaded from the worktree `lisp/` with
  `~/workspace/beads.el/lisp` and the Guix `emacs-vui-1.4.0` on the
  load path, eldoc off.
- City: `/ssh:localhost:/home/roman/bright-lights` (plain-ssh TRAMP,
  the repo's acceptance gate for gc-invocation features).  Every gc
  invocation is `gc --city /home/roman/bright-lights …`: probed live —
  `gascity-context-city-args` answers `("--city"
  "/home/roman/bright-lights/")` and both readers prepend it.

## The four scenarios (REQ-014)

### 1. Pancake formula end to end ✓

`S` on the cockpit with no work in scope, `-f` → `pancakes`, `-T` →
`mayor`.  The menu (captured verbatim from ` *transient*`):

```
Sling — bright-lights
   Run pancakes (formula) on mayor
   ✓ Ready — formula run · target mayor (city) · 0 vars
```

The exact mockup §1/§3 sentence and footer.  `s` launched and the
echo/follow offer fired: `Launched workflow bl-9jmm (pancakes on
bl-9jmm) — F: run view`; pressing `F` jumped to the run view
(`*gascity-run: bl-9jmm@/ssh:localhost:…*`: root ⬣ bl-9jmm, 5 steps
dry/wet/combine/cook/serve with their bead ids).  The mayor session
was nudged (gc's formula path has no nudge of its own — see F9) and
worked the workflow to completion inside a minute: `bl-aibt`…`bl-rzvq`
all closed, then the root: the run view repainted `◆ bl-9jmm pancakes
pass · closed`, `Steps 5/5`.  gc's `molecule_id` payload field is
confirmed live as the created root bead id (the WI-8 fallback read was
not needed).

### 2. build-basic `--on` with typed vars ✓ (with deviations, F3/F5/F6)

Setup through the menu: `-f` → `build-basic`, `A` → `hw-aij` (the
hello-world store's ready bead), target left to the Who default
(derived `hello-world/gc.implementation-worker`).  The menu:

```
Sling — bright-lights
   Run build-basic against bead hw-aij, drained by hello-world/gc.implementation-worker
   ✓ Ready — on run · target rig-scoped · 14 of 18 vars set

Variables — build-basic
 if artifact_root (required) — Build artifact root.  [dir] (--var artifact_root=plans/build-basic/)
 on context_path — Optional source context bundle path.  [file] (--var context_path=)
 il implementation_target — Role target for implementation work. [default: gc.implementation-worker]  [agent] (--var implementation_target=gc.implementation-worker)
 ie max_iterations — Maximum implementation/review fix attempts. [def…
```

Observed:

- **Typed classes render** — `[dir]`/`[file]`/`[agent]` tags with the
  deterministic keys (`if`, `on`, `il`, `ie`…), none colliding with
  the static bindings.
- **`context_path` file completion** — the `on` read is
  `read-file-name` over the target rig's workdir; typing `context-e2e`
  + TAB completed to `context-e2e-wi11.md` (a file created on the
  hello-world host for the pass), and the set value shows in the
  infix (`--var context_path=context-e2e-wi11.md`).
- **`artifact_root` seeds `plans/<slug>/`** — the seed renders as the
  infix default; with no work at entry it derives from the formula
  name (`plans/build-basic/`, the documented fallback — the work
  title's slug only seeds when the bead is at point at entry, F6a).
- **Numeric guard** — `max_iterations` refused `10abc` with the
  verbatim `Var max_iterations must be numeric (got 10abc)` before any
  gc call.  Note: the refusal also closed the menu (F1).
- **`implementation_target`** — shows the declared convention default
  (`gc.implementation-worker`); the derived-from-target seed only
  applies to a `-T`-set target today (F5).  `build-basic` declares no
  `rig_name` var, so that half of the scenario wording has nothing to
  derive (F6).
- **Launch `--on`** — `s` launched: `Launched workflow hw-5o1
  (build-basic on hw-5o1) — F: run view`; `F` opened the run view
  (`⬣ hw-5o1 build-basic … hello-world · started`, input convoy
  `hw-n3n`, 10 steps, `run-operator-1` session active on `prepare`).
  The workflow is live in the hello-world store (step specs and task
  beads spawning — visible in the cockpit's Activity stream).

### 3. The bl-bdj trap — city-scoped target warns, rig-scoped shows ✓

With `build-basic` picked (24 binding-qualified `gc.run_target` steps):

- `-T` → `mayor` (city): the footer warned, mockup §5a wording verbatim
  and with the roster-derived suggestion rig:

  ```
  ⚠ formulas v2 target: this formula needs a rig-scoped target — the chosen city agent will fail with "unknown formulas v2 target" (bl-bdj); pick a hello-world/* agent with T
  ```

- `-T` → `hello-world/gc.implementation-worker` (rig): the v2-trap
  warning is gone; with work `hw-aij` in scope the footer reads
  `✓ Ready — on run · target rig-scoped · 14 of 18 vars set` and the
  header carries the full mockup §4 sentence (`Run build-basic against
  bead hw-aij, drained by …`).

### 4. Plain dispatch — bead at point, `S` then `s` zero prompts; freeform

- **Freeform with zero prompts ✓** — `S` from a non-bead area (header:
  `Sling (no work — A or point at a bead) to
  hello-world/gc.implementation-worker` — the derived Who default), `s`
  → the task-text read → text → launch: `GC sling: ok`.  Confirmed in
  the store: `hw-4wz` created **in the derived target's store**
  (hello-world, `hw-` prefix), routed
  `gc.routed_to=hello-world/gc.implementation-worker`, auto-convoy
  `sling-hw-4wz`; a hello-world worker session picked it up.
- **Bead at point** — `S` on the cockpit Work row `bl-4rvq` → `s` ran
  with zero prompts (no target read; the derived target was used) and
  gc **refused**: `cross-rig routing — bead bl-4rvq (prefix "bl") →
  agent hello-world/gc.implementation-worker (rig prefix "hw")`.  This
  is gc's documented cross-rig refusal — the §5b trap, live.  The
  footer now warns exactly this before the launch (§Fixed-in-pass);
  before the fix it stayed at `⚠ No target` while the launch ran into
  the refusal.  The zero-prompt *mechanism* (derivation used, no
  prompt) is verified either way.
- **Prefix arg** — `C-u S` behaves exactly as `S` (no freeform escape
  keyed to the prefix arg; the mockup's `C-u A` freeform path belongs
  to WI-4's staged layout, which has not landed).  Freeform goes
  through the `s`/`A` read today (F7).

## Fixed in this pass (the item's own commit)

- **Nil-recipe setup crash** — with no formula picked, the footer's
  composition called `gascity-formula-vars` on nil
  (`gascity-sling--missing-required-vars`,
  `gascity-sling-formula--current-values`): the transient never opened
  (`No applicable method: gascity-formula-vars, nil` on every `S`).
  Both now degrade to "no required vars"; regression test
  `gascity-test-sling-missing-required-vars-nil-recipe-degrades`.
- **The footer answers the Who default** — `gascity-sling--footer`
  now feeds the derived target to the §5b/§5c checks (the derivation
  is what `s` will launch): the bl-4rvq case now renders
  `⚠ cross-store route: bead bl-4rvq lives in the bright-lights store
  but the target reads the hello-world store — gc will refuse …`
  before any launch (verified live after warming the rig memo), and
  the `⚠ No target` warning only fires when nothing derives.
  Test: `gascity-test-sling-footer-derived-target-answers-checks`.
- **Scope classifier slash fallback** —
  `gascity-agents-roster-scope` falls back to the target's own slash
  prefix when no roster row matches: the footer's joined roster
  carries pool instances (`…/gc.implementation-worker-1`) that never
  exact-match a config-name target, so rig-scoped targets degraded to
  free entry and the ✓ line showed the bare name.  After the fix the
  rig-scoped target renders as `rig-scoped` (mockup §4) and the
  §5b check classifies config-name targets.
  Test: extended `gascity-test-agents-roster-scope-free-entry-degrades`.
- **Test helper collision** — three merged definitions of
  `gascity-sling-test--recipe` (one per work item); one canonical
  remains, the footer's vars recipe reads
  `gascity-sling-test--vars-recipe`.

Gate after the fixes: `scripts/gate.sh` PASS (compile clean, 723/723
tests).

## Findings (recorded, not blocking the four scenarios)

- **F1 — a refused/aborted read closes the whole menu.**  The numeric
  guard's `user-error` (and `C-g` in any infix read) quits the
  transient instead of returning to it.  The validation itself is
  correct and pre-gc; the menu should survive a refused entry.
- **F2 — answers set after the last re-setup are lost across
  quit+reopen.**  The per-city remembered snapshot (`S-2`/WI-9) is
  captured on re-setups (re-pick, `A`, `-T`, preview); var answers
  typed afterwards die with the menu.  Observed: `context_path` set,
  transient quit (F1), reopen → `--var context_path=` empty.
- **F3 — typed path vars over TRAMP return TRAMP-expanded names.**
  The `[dir]` read over the remote rig workdir answered
  `/ssh:localhost:~/hello-world/plans/build-basic/` (and, on a
  second entry, a doubled `…/plans/build-basic/plans/build-basic/`).
  gc runs host-side and cannot consume `/ssh:…` names — the readers'
  documented host-local re-prefix (`gascity-remote-localize-path`)
  does not hold for the returned value (WI-5 seam).  The pass's
  launch still succeeded because gc tolerates the `--var` payload
  (artifact dirs are created); a stricter gc would refuse.
- **F4 — the rig memo misses the HQ rig in cockpit-only sessions.**
  `gc status`'s rigs payload omits the HQ rig (`bright-lights`/`bl`,
  `gc rig list` includes it), and the cockpit seeds the memo from
  status — so `gascity-rigs-cached` lacks the city prefix and the
  §5b check degrades until some rig-list read warms the memo (the
  pass warmed it and the warning fired immediately).  Either gc
  should include the HQ rig in status or gascity should seed the memo
  from `gc rig list`.
- **F5 — `*_target` var seeds ignore the Who default.**
  `gascity-sling-formula--var-seed` seeds `*_target` vars from the
  `-T`-set target only; with the derived default in scope the var
  keeps its declared default (`gc.implementation-worker`).
- **F6 — scenario wording vs the formula.**  `build-basic` declares
  no `rig_name` var (nothing to derive), and the work-title slug for
  `artifact_root` seeds only from a bead at point at entry (an `A`-set
  work does not re-seed).
- **F7 — no freeform prefix-arg path.**  `C-u S` ≡ `S`; the mockup's
  `C-u A` escape belongs to WI-4's staged layout (not landed).
- **F8 — pre-existing city/environment conditions** (not sling):
  the HQ rig's dashboard read fails (`gc rig status` refuses the HQ
  rig — bright-lights *is* the HQ); raw `bd` from the bright-lights
  tree resolves the emacs-city store (the gce-bhr family — gascity's
  `bd --directory` store scoping is the workaround and works); the
  prior session's four pancake runs sat unworked for 2h until a
  nudge.
- **F9 — the formula path never nudges.**  Routing flags are
  documented off the formula path, so a formula launch to a sleeping
  agent waits for a manual nudge (scenario 1 needed one).  Either the
  launch should nudge on routing or the run view should make the
  wait visible (the run view does show the idle run in the cockpit's
  Needs-you).

## Result

All four REQ-014 scenarios verified live over TRAMP against
bright-lights with `gc --city` on every invocation; three integration
bugs found by the pass are fixed with regression tests and the gate is
green.  The deviations above are recorded for the review/fix loop.
The screenshots for WI-12 were not captured from this session (a
terminal `-nw` session cannot produce the manual's GUI shots);
WI-12 should capture from a GUI session or fall back to the mockup
renderings per the requirements' Open Question.
