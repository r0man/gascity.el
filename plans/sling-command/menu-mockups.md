# Sling redesign — menu mockups

ASCII renderings of every user-facing element of the redesigned
`gascity-sling-dispatch` transient (per `design.md`), for review before
implementation.  All data in the mockups is real: build-basic's 18
declared vars (keys computed with the existing deterministic key
algorithm against the new reserved-key set), bright-lights' roster from
`gc agent list`/`gc status`/`gc session list`, and the enum choices from
build-basic's `metadata.gc.methodology`.

Layout conventions (the actual transient rendering rules):

- One transient, stacked full-width groups (no columns), like today.
- First group: the **one-sentence shape header** + the **live footer**
  (always visible — that is the "mini preview is always on" decision).
- Each stage is one group: **What** (work `A`, formula `f`), **Who**
  (target `T`), **How** (the picked formula's typed var infixes),
  **Actions**.  A stage with an answer shows the answer inline (the
  stage is collapsed to its one line — the answer is visible, the
  binding still lets you change it); a stage without one shows its
  pick hint.
- Routing flags appear **only on the plain shape** (they are consumed
  only by the plain path, F-5 kept).
- `s` launches anytime; `P` opens the full preview; `g` refreshes
  formulas; `x` resets; `q` quits.

Reserved single letters (the generated var keys avoid these):
`A f T c a n m t s P r g x q` (`p` is freed — it was `p` preview, now
`P`).

---

## 1. The happy path — fully pre-seeded plain dispatch

Point on a bead row (or a convoy), press `S`.  Work is pre-seeded from
point, the target from the rig default / memory.  **Press `s`.  Done.**
This is the design's "press S, press s" state — every stage holds an
answer, nothing prompts.

```
Sling — bright-lights
  Sling bead bl-5ja to mayor
  ✓ Ready — plain route · target mayor (city) · no vars

What
  A    Work: bl-5ja — e2e sling-v2: verify unified plain sling over TRAMP
  f    Formula: (none — f to pick)

Who
  T    Target: mayor · city · active
       (derived from memory for this bead's rig — s uses it)

Routing flags
  -c   Skip auto-convoy
  -a   Reassign (clear human assignee)
  -n   Nudge target after routing
  -m   Merge strategy
  -t   Wisp root title

Actions
  s    Launch            P    Full preview
  r    Recipe preview    g    Refresh formulas
  x    Reset             q    Quit
```

The footer recomputes on every change; `✓` means client-side validation
is clean, `⚠` (see §5) means it has something to say.

---

## 2. Cold entry — nothing pre-seeded

Pressed `S` in an empty area: no bead at point, no remembered state.
Both hints stare back; the header sentence still reads as one line.

```
Sling — bright-lights
  Sling (no work — A or point at a bead) to (no target — T or default)
  ⚠ No work chosen — pick work before launching

What
  A    Work: (none — A to pick an open bead or convoy)
  f    Formula: (none — f to pick)

Who
  T    Target: (no default derivable — T to choose)

Actions
  s    Launch            P    Full preview
  r    Recipe preview    g    Refresh formulas
  x    Reset             q    Quit
```

---

## 3. Formula shape — `pancakes` on `mayor` (no work)

`S f` → pick `pancakes`.  Shape inferred: formula + no work ⇒ the
targetless `--formula` shape.  Pancakes declares no vars, so no How
group at all — the flow is What → Who → `s`.  No routing flags group
(formula path ignores them).

```
Sling — bright-lights
  Run pancakes (formula) on mayor
  ✓ Ready — formula run · target mayor (city) · 0 vars

What
  A    Work: (none — a formula run needs no work)
  f    Formula: pancakes — Make pancakes from scratch

Who
  T    Target: mayor · city · active

Actions
  s    Launch            P    Full preview
  r    Recipe preview    g    Refresh formulas
  x    Reset             q    Quit
```

CLI equivalent shown in the footer's mental model:
`gc sling mayor pancakes --formula` (the verified bl-29ul path).

---

## 4. Targeted shape — `build-basic --on bl-5ja` (typed How)

`S` (bead at point) `f` → pick `build-basic`.  Shape inferred: formula +
work ⇒ the targeted `--on` drain shape.  The How group appears, full
width, one typed infix per declared var — real var keys as the
deterministic algorithm assigns them.  Values in `= …` are the
scope-derived defaults (each editable by pressing its key):

```
Sling — bright-lights
  Run build-basic against bead bl-5ja, drained by hello-world/gc.implementation-worker
  ✓ Ready — on run · target rig-scoped · 6 of 18 vars set

What
  A    Work: bl-5ja — e2e sling-v2: verify unified plain sling over TRAMP
  f    Formula: build-basic — Run the default Gas City full-lifecycle build …

How — build-basic vars
  if   artifact_root (required) — Build artifact root.
         = plans/e2e-sling-v2-verify-unified-plain-sling-over-tramp/   [dir]
  on   context_path — Optional source context bundle path.
         = (unset)                                          [file]
  d    decomposition_formula — Task decomposition methodology …
         = decomposition-base                              [choice]
  ec   decomposition_path — Task decomposition artifact path …
         = (unset)                                        [file]
  in   drain_policy — Implementation drain policy.
         = separate                                       [choice: separate|same-session]
  ip   implementation_item_formula — Single-item implementation …
         = do-work-item                                    [choice]
  il   implementation_target — Role target for implementation work.
         = hello-world/gc.implementation-worker            [agent]
  it   interaction_mode — Workflow interaction posture.
         = interactive                                    [choice: interactive|autonomous|headless]
  ie   max_iterations — Maximum implementation/review fix attempts.
         = 10                                             [numeric]
  op   open_pr — Set true to allow final PR creation …
         = false                                           [bool]
  p    plan_path — Plan or design artifact path …
         = (unset)                                        [file]
  us   push — Set true to allow final publish push …
         = false                                           [bool]
  eq   requirements_path — Requirements artifact path …
         = (unset)                                        [file]
  ei   review_mode — Review authority.
         = agent                                           [choice: report|agent|interactive]
  …    (remaining methodology-formula vars, same shape as d)

Who
  T    Target: hello-world/gc.implementation-worker · hello-world · derived
       (implementation-worker convention for build formulas — s uses it)

Actions
  s    Launch            P    Full preview
  r    Recipe preview    g    Refresh formulas
  x    Reset             q    Quit
```

Notes on the typed rendering:

- `artifact_root` seeds `plans/<slug>/` from the work title's slug
  (convention default; editable like any var).
- `implementation_target` seeds from the Who target's rig:
  `hello-world/gc.implementation-worker`.
- `[file]` infixes read with file completion relative to the target
  rig's workdir; `[dir]` with directory completion; `[agent]` with the
  same roster completion as `T`; `[numeric]` validates digits;
  `[choice: a|b|c]` are the methodology enums (restricted — illegal
  values unrepresentable); `[bool]` toggles on its key press.
- Only 6 of 18 show values because the rest carry declared defaults —
  the footer's "vars set" counts non-blank answers (required check
  still applies to `artifact_root` if cleared).

---

## 5. The live footer — validation states

The second header line, recomputed as answers change.  Warnings never
block `s` (gc stays the authority) but are unmissable.

### 5a. bl-bdj trap (city-scoped target on a v2 formula)

Target `T` → `mayor`, formula build-basic (steps name binding-qualified
run targets like `gc.run-operator`):

```
  Run build-basic against bead bl-5ja, drained by mayor
  ⚠ formulas v2 target: this formula needs a rig-scoped target — the chosen
    city agent will fail with "unknown formulas v2 target" (bl-bdj); pick a
    hello-world/* agent with T
```

Same formula with `hello-world/gc.implementation-worker` (rig-scoped):

```
  ✓ Ready — on run · target rig-scoped · 6 of 18 vars set
```

### 5b. Cross-store route (plain shape, gc would refuse)

Work bead in the hello-world store, target rig-scoped to another rig:

```
  Sling bead hw-ab12 to gascity.el/implementation-worker
  ⚠ cross-store route: bead hw-ab12 lives in the hello-world store but the
    target reads the gascity.el store — gc will refuse (pick a city agent or
    a hello-world agent)
```

### 5c. Missing pieces

```
  ⚠ build-basic drains a bead — pick work with A (or point at one)
  ⚠ Missing required vars: artifact_root
  ⚠ No target — T to choose, or s will prompt
```

---

## 6. The pickers (minibuffer reads)

### 6a. `A` — the work picker

Completing-read over the city's open/in-progress/blocked beads plus
convoys, annotated.  Empty RET falls through to a freeform text prompt;
`C-u A` goes straight to freeform.

```
Work (bead or convoy; RET-empty or C-u for freeform text): bl-5ja
  bl-5ja    e2e sling-v2: verify unified plain sling over TRAMP · open · city
  bl-70ac   e2e demo latch — gce-e2e demo · open · city
  bl-0q8w   e2e-demo · open · city
  hw-3fd    … · in_progress · hello-world
  hw-conv   …convoy row…  · convoy · hello-world
```

RET-empty falls to:

```
Bead id or task text: fix the flaky timer test
```

(freeform text becomes the plain shape's task text).

### 6b. `f` — the formula picker

As today: the catalog ∪ `gc formula list` union, annotated.

```
Formula: pancakes
  build-basic       Run the default Gas City full-lifecycle build …
  pancakes          Make pancakes from scratch
  e2e-demo          (city)
  mol-extra         (not in catalog)
```

Picking a formula **with** work in scope infers the `--on` shape;
**without** work, `--formula`.  The header sentence flips immediately —
shape is never a flag.

### 6c. `T` — the Who picker (agent-centric, grouped by rig)

Completion over agents — not sessions — ordered city-first then per
rig, annotated with scope and live state.  The derived default is the
initial input (RET keeps it).

```
Target agent: hello-world/gc.implementation-worker
  mayor                                    city · active
  pi                                       city · provider pi
  core.control-dispatcher                  city · active
  hello-world/gc.implementation-worker     hello-world · derived default
  hello-world/gc.run-operator              hello-world · stopped
  hello-world/gc.requirements-planner      hello-world · idle
  hello-world/gc.task-decomposer           hello-world · idle
  hello-world/gc.design-author             hello-world · stopped
  …                                        (the rest of the roles pack)
```

Free entry still works (a typed name is used verbatim — roster cold is
never a dead end).

---

## 7. Typed var reads (minibuffer)

```
context_path — Optional source context bundle path. (relative to /home/roman/hello-world): src/
  src/          docs/          plans/         .gc/

artifact_root — Build artifact root. (default plans/e2e-sling-v2-…-over-tramp/): RET

implementation_target — Role target for implementation work.: hello-world/gc.implementation-worker

max_iterations — Maximum implementation/review fix attempts. [default: 10]: 15
```

A bad numeric entry refuses before any gc call:

```
Var max_iterations must be numeric (got lots)
```

---

## 8. `P` — the full preview buffer

Opens at once with everything gascity can compute client-side; the
routing plan (gc `--dry-run`) fills in when it answers.  Launch is
available directly here; preview is never a gate — `s` works in the
menu at any time.

```
Sling preview — bright-lights                              (s launch · q quit)
────────────────────────────────────────────────────────────────────────────
  Run build-basic against bead bl-5ja, drained by hello-world/gc.implementation-worker

Validation
  ✓ target hello-world/gc.implementation-worker is rig-scoped (formula needs it)
  ✓ no cross-store route
  ✓ required vars set: artifact_root

Recipe — build-basic (steps → needs)
  prepare                    needs artifact_root
  requirements               needs prepare
  plan                       needs requirements
  plan-review                needs plan
  decompose                  needs plan-review
  implement                  needs decompose
  summarize-implementation   needs implement
  review.setup …             needs summarize-implementation
  review loop …              …
  finalize                   needs review
  publish                    needs finalize

Routing plan (gc sling … --dry-run)
  …
  Target:
    Session config: hello-world/gc.implementation-worker (min=0 max=…)
    Sling query: bd update … --set-metadata gc.routed_to=…
  Work:
    Bead: bl-5ja — "e2e sling-v2: …" · open
  …
```

With the city-scoped target instead, the Validation section shows the
bl-bdj warning verbatim and the routing plan still prints (gc's dry run
is routing-only; the trap fires at instantiation — hence the
client-side warning, per the bl-bdj post-mortem).

---

## 9. Post-launch follow offer

`s` echoes and stays put — no buffer yanked away.  A momentary key
follows in the echo area; any other key dismisses it:

```
Launched workflow bl-9xyz (build-basic on bl-5ja) — F: run view
```

`F` jumps to the run view for the created workflow root
(`gascity-run-show` on the root bead, nesting under it); anything else
dismisses.  Plain-route launches keep the plain echo
(`Routed bl-5ja to mayor`) — no run view exists for a plain route, so
no offer.

---

## 10. Key summary

```
A   Work (open beads + convoys; C-u = freeform text; point pre-seeds)
f   Formula (with work ⇒ --on shape; without ⇒ --formula)
T   Target (agents grouped by rig; default auto-derived in the header)
--  one typed infix per declared formula var (file/dir/agent/numeric/
    enum/bool; keys deterministic, avoiding the reserved set)
s   Launch (anytime — preview is never a gate)
P   Full preview buffer (DAG + routing plan + warnings; s launches there)
r   Recipe preview (server-side substituted, as today)
g   Refresh formulas
x   Reset (clear work, formula, target, vars)
q   Quit
```

Derived Who default, in order: rig `default_sling_target` (city.toml,
rig of the work bead) → per-(city, formula) target memory →
implementation-worker convention for build formulas (the single
rig-scoped `gc.implementation-worker` when unambiguous).  A derived
target is a seed, shown in the header; `T` overrides; `s` never
re-prompts when a target is derivable.