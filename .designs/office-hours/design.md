# Design: gascity-native "office hours"

*A forcing-questions product-discovery entry point that refines a raw idea
**before** work begins and emits a design that flows into gascity's
beads → dispatch → refinery pipeline. Inspired by
[gstack](https://github.com/garrytan/gstack)'s `/office-hours`.*

Status: **DRAFT — design only.** This doc proposes a capability; it does not
implement it. Tracked by `gce-20l`.

Scope note: this doc *describes the office-hours feature*. It lives at
`.designs/office-hours/design.md`. The feature, once built, writes a *separate*
per-idea brief to `.designs/<idea-slug>/office-hours.md` — do not confuse the
two paths.

---

## 0. TL;DR

gascity already has the **downstream** of a planning pipeline:
`mol-idea-to-plan` turns a *given* problem statement into a PRD, a reviewed
multi-dimension design doc, and a beads DAG; the `design` skill produces
multi-dimension design docs; `plan-to-beads` converts a plan into an
epic + tasks; `gc sling` routes the resulting beads to polecats and the
refinery merges them.

What gascity is **missing** is the **front door**: the Socratic,
anti-sycophantic *forcing-questions intake* that decides **whether and what**
to build before any artifact exists. `mol-idea-to-plan` takes the idea as a
`--var problem=` *given* and its single human gate is *reactive* (answer the
reviewers' questions about an already-drafted PRD). Nothing interrogates the
raw idea, challenges its premises, forces specificity about the user, or
generates effort-estimated alternatives **as a decision gate** up front.

**Recommendation:** ship office-hours as a **skill** (`office-hours`) — a
human-in-the-loop, `AskUserQuestion`-driven intake that produces a committed
`.designs/<slug>/office-hours.md` brief — and then **hand off into the pipeline
gascity already has** (seed `mol-idea-to-plan`'s `--var problem/context`, or run
`design` → `plan-to-beads`, or directly create a convoy + phase beads + `gc
sling`). Adopt gstack's *intake mechanics*; differ on the *handoff*: gascity's
output becomes **durable beads on a real work bus**, not a filesystem glob
convention.

---

## 1. gstack `/office-hours` — what it actually does

Source: `office-hours/SKILL.md` (v2.0.0) in `garrytan/gstack`, plus
`docs/skills.md`, `ARCHITECTURE.md`, `ETHOS.md`. gstack is "twenty-three
specialists and eight power tools, all slash commands, all Markdown" — it turns
Claude Code into a virtual eng team. `/office-hours` is the **product-thinking
entry point**: *"Start here. Six forcing questions that reframe your product
before you write code."*

### 1.1 Hard contract

> **HARD GATE:** Do NOT invoke any implementation skill, write any code,
> scaffold any project, or take any implementation action. Your only output is
> a design document.

It is a "YC office hours partner": its job is to ensure the problem is
understood before solutions are proposed.

### 1.2 Phase flow (the mechanics)

| Phase | What happens |
|---|---|
| **1. Context Gathering** | Read `CLAUDE.md`/`TODOS.md`, `git log`, map the codebase; list prior design docs; **ask the user their goal** → routes to a mode. |
| **2A. Startup mode** | YC product diagnostic — the six forcing questions (below). Anti-sycophancy rules, pushback patterns, "specificity is the only currency." |
| **2B. Builder mode** | "Design partner" — generative, enthusiastic questions ("what's the coolest version?"). For hackathon / OSS / learning / fun. |
| **2.5. Related Design Discovery** | grep prior design docs for keyword overlap; offer to build on a prior design. |
| **2.75. Landscape Awareness** | WebSearch *generalized* terms for conventional wisdom; "eureka check" = where is the conventional approach wrong here? |
| **3. Premise Challenge** | Emit premises as `agree/disagree?` statements; user must confirm before solutions. |
| **3.5. Cross-Model Second Opinion** *(optional)* | Independent cold read (Codex or a fresh Claude subagent) of the problem/premises; cross-model synthesis. |
| **4. Alternatives Generation (MANDATORY)** | 2–3 approaches, each `Effort S/M/L/XL · Risk · Pros · Cons · Reuses`. One *minimal-viable*, one *ideal-architecture*, one *creative/lateral*. A **HARD STOP gate** — the user must pick before anything is written. |
| **4.5. Founder Signal Synthesis** | Tally signals (named real users, pushed back, showed taste/agency…). |
| **5. Design Doc** | Write a templated doc (`# Design: …`, Problem / Demand Evidence / Status Quo / Wedge / Premises / Approaches / Recommended / Open Questions / Distribution / **The Assignment** / "What I noticed"). |
| **Spec Review Loop** | Dispatch an adversarial reviewer subagent (5 dimensions: completeness, consistency, clarity, scope, feasibility), fix, re-review (≤3 iterations). |
| **6. Handoff / Closing** | Approve → `Status: APPROVED`; relationship closing that deepens across sessions. |

### 1.3 The six forcing questions (startup mode)

Asked **one at a time** via `AskUserQuestion`; *push until the answer is
specific, evidence-based, and uncomfortable.* Smart-routed by product stage
(pre-product → Q1–Q3; has-users → Q2,Q4,Q5; paying → Q4–Q6).

1. **Q1 Demand Reality** — strongest evidence someone would be *genuinely upset
   if it disappeared* (not "interested", not waitlist signups).
2. **Q2 Status Quo** — what users do *right now* to solve this, even badly, and
   what the workaround costs. ("Nothing" usually means the pain is too small.)
3. **Q3 Desperate Specificity** — name the actual human: title, what gets them
   promoted/fired, what keeps them up at night. *"You can't email a category."*
4. **Q4 Narrowest Wedge** — smallest version someone would pay for *this week*,
   not after the platform is built.
5. **Q5 Observation & Surprise** — have you watched someone use it without
   helping, and what surprised you? ("Surveys lie. Demos are theater.")
6. **Q6 Future-Fit** — if the world looks different in 3 years, does this become
   *more* essential or less? (Growth rate is not a vision.)

### 1.4 How it chains (the crucial part)

The README says: **"Design doc feeds into every downstream skill."** Mechanically
this is a **filesystem-glob convention**, not a message bus:

- office-hours writes `~/.gstack/projects/{slug}/{user}-{branch}-design-{datetime}.md`.
- `/plan-ceo-review`, `/plan-eng-review`, `/autoplan` each do, verbatim:
  ```bash
  DESIGN=$(ls -t ~/.gstack/projects/$SLUG/*-$BRANCH-design-*.md 2>/dev/null | head -1)
  ```
  and read it as the source of truth. `/autoplan` will even **run `/office-hours`
  inline** if no design doc exists, then re-glob.
- A `Supersedes:` field links design revisions into a chain.

So in gstack the "pipeline" is: **a human runs the next slash command**, which
finds the latest design file by `ls -t`. There is no scheduler, no work queue,
no merge gate — just Markdown files and a disciplined human (or `/autoplan`)
driving the sequence.

### 1.5 gstack philosophy worth keeping

From `ETHOS.md`: **"Boil the Lake"** (be exhaustive, don't half-solve) and
**"Search Before Building"** (find what already exists first). The
anti-sycophancy posture ("take a position on every answer; state what evidence
would change your mind") is the substance of the intake — without it,
office-hours degrades into a friendly requirements interview.

---

## 2. gascity capability map — have / missing

gascity (the `~/.bright-lights` Gas City + the `gascity.el` rig) already has a
*richer* planning machine than gstack downstream of intake. The gap is purely
**upstream**.

### 2.1 What gascity HAS

| Capability | Surface | What it does | Overlaps office-hours? |
|---|---|---|---|
| **`mol-idea-to-plan`** | gastown-pack **formula** (`gc sling <coord> -f mol-idea-to-plan --var problem=…`) | Full pipeline: draft PRD → **6 parallel PRD-review legs** (requirements/gaps/ambiguity/feasibility/scope/stakeholders) → **one human-clarify gate** → **6 design legs** (api/data/ux/scale/security/integration) → `.designs/$ID/design-doc.md` → 3 PRD-alignment + 3 self-review rounds → **convoy + task beads + deps**. | **Heavily** — it owns the entire *downstream*. But its intake = `--var problem` (a given) + a *reactive* human gate. |
| **`design` skill** | built-in Claude Code **skill** | Multi-dimension design exploration → synthesized design doc (options, trade-offs, risks, phased plan) in `.designs/<slug>/`. | Partial — same multi-dimension design step `mol-idea-to-plan`'s design legs cover. |
| **`plan-to-beads` skill** | beads-marketplace **command** | Parse a plan/design `.md` → `bd create` epic + phase tasks + sequential deps. | The *idea→design→beads* tail end. |
| **Mayor** | agent **role** | Coordinates globally; owns the dispatch plan; slings work to rigs/pools. | The *dispatch* of resulting beads. |
| **epic → phase beads → `gc sling` → polecat → refinery** | the work bus | Phase beads carry metadata (`branch`, `target`, `work_dir`); `gc sling` routes; polecats implement on worktree branches; refinery merges & closes. Convoys are the modern first-class container ("epic beads are no longer first-class containers — migrate to convoys"). | The *execution* of the plan. |
| **`gc order`** | trigger rules (cron/cooldown) | Event/interval automation (health sweeps, patrols, digests). | **No** — orders are unattended infra triggers, not interactive intake. |
| **`bd remember`** | persistent knowledge | Durable cross-session memory (replaces MEMORY.md). | gstack's `gbrain`/builder-profile analog. |
| **Skill materialization** | packs | `gc` materializes pack skills (`.gc/system/packs/*/skills/<name>/SKILL.md`) into each agent's provider skill dir; `gc skill list` shows them with `FROM` = the pack. | This is the *delivery mechanism* a new skill would use. |

### 2.2 What gascity is MISSING

The **forcing-questions intake** — the part of gstack `/office-hours` that runs
**before** any PRD/design/beads exist:

1. **Demand/pain interrogation** — "is this worth building at all?" Nothing in
   gascity challenges the *premise* of an idea before drafting a PRD.
2. **Anti-sycophancy posture** — push for specificity; take a position; name the
   user by name. `mol-idea-to-plan`'s legs critique an *artifact*, not the *idea*.
3. **Existing-surface "Search Before Building" gate** — gascity has acute
   overlap risk (`design` vs `mol-idea-to-plan` vs `plan-to-beads` all do
   adjacent things; the `gascity.el` rig has a view-tech matrix and many
   existing commands). An intake that *forces* "what already does part of
   this?" is high-value here specifically.
4. **Effort-estimated alternatives as a decision gate** — `mol-idea-to-plan`
   explores design options inside legs, but there is no up-front
   *"pick A/B/C before we spend the fan-out"* gate. Today you pay for 12+
   review legs before a human picks a direction.
5. **Surface-choice forcing** — gascity-specific: *where does this belong* — a
   `gascity.el` `.el` view, a `gc` skill, a formula, an order, an agent role?
   This decision is first-order here and has no dedicated intake step.

> **Net:** gascity should not re-implement PRD/design/beads (it has the best one
> of those in the ecosystem). It should add the *thin, interactive, adversarial
> front door* and **wire its output into the existing pipeline**.

---

## 3. Proposed design: gascity-native office hours

### 3.1 Surface — recommendation: a **skill** that hands off to a **formula**

Evaluated surfaces:

| Surface | Fit | Verdict |
|---|---|---|
| **Skill** (`office-hours`) | Interactive, `AskUserQuestion`-driven, Socratic, human-in-the-loop — exactly what an intake is. Materialized via packs; invoked in a coordinator/crew/mayor session. | ✅ **Primary.** This is what gstack uses and what the flow demands. |
| **Formula/molecule** (`mol-office-hours`) | Great at orchestrating dispatched fan-out + gates; weaker at sustained 1:1 Socratic conversation. | ⚠️ **Not the intake.** But the *handoff target* (`mol-idea-to-plan`) is a formula, and a later `mol-office-hours` could wrap "intake → auto-sling" for unattended runs. |
| **Mayor workflow / agent role** | Mayor coordinates globally and owns dispatch; it does not do per-idea product interrogation. | ❌ Too heavy. Mayor is a *consumer* of the brief (it dispatches the resulting convoy), not the interrogator. |
| **Order** | Cron/cooldown triggers for unattended infra. | ❌ Intake is human-driven, not scheduled. |

**Decision: `office-hours` is a skill.** It produces a committed brief, then
**offers** to hand off to `mol-idea-to-plan` (or `design`→`plan-to-beads`, or a
direct convoy). The skill is thin; the heavy lifting reuses what exists.

### 3.2 Where the implementation lands

> The task notes gc-core (gastown) is **not** a local rig here — so be explicit.

- **The design artifact (this doc)** lands in **this rig**, `gascity.el`, at
  `.designs/office-hours/design.md`. ✅ (doc-only deliverable)
- **The skill implementation** lands in a **pack**, because skills are
  materialized from packs (`.gc/system/packs/<pack>/skills/<name>/SKILL.md` →
  `gc skill list`). Two real options:
  - **(a) Upstream gc-core / gastown pack PR.** Cleanest long-term home
    alongside `mol-idea-to-plan`. But gc-core is *not checked out as a local
    rig* — this is an upstream contribution, out-of-band from this town's repos.
  - **(b) City-local pack overlay.** A pack under the city config (system packs
    live in `.gc/system/packs/`; a runtime/overlay packs dir exists at
    `.gc/runtime/packs/`). This keeps office-hours *local to this town* with no
    upstream dependency. **Recommended for Phase 1** to iterate fast; promote to
    (a) once stable. *(Open question 5: confirm gc's pack-override precedence
    and the supported city-local pack path.)*
- A **formula** (`mol-office-hours`, optional, later) would land in the same
  pack as the skill.

### 3.3 Forcing questions — tailored to gascity (not a copy of gstack's)

gascity is a **developer-tools / multi-agent-infrastructure** context (an Emacs
porcelain over the `gc` CLI, beads, Dolt). The startup/VC framing
(paying customers, fundraising) does not fit; reframe around *real recurring
pain, existing surface, shippable wedge, and the porcelain's "function of `gc
--json`" reality.* Ask **one at a time**, push for specifics.

1. **Named pain (Q1+Q2+Q3 fused).** *"Whose workflow is broken today? Name the
   actual user — you, a specific agent role (mayor/refinery/polecat), or a
   specific command/view — the concrete steps they take **now**, and what it
   costs. Point at a transcript, a bead, or a moment it bit you. Not a
   hypothetical feature."*
   - Red flags: "it'd be nice if…", "users would want…", category answers.
2. **Existing surface ("Search Before Building").** *"What in gascity / `gc` /
   beads already does part of this — a command, skill, formula, view, or order?
   Why isn't that enough?"* (Force a concrete grep of `gc skill list`, `gc
   formula list`, `.designs/`, `gc bd list`. This is the highest-value question
   in *this* town given the design/plan-to-beads/mol-idea-to-plan overlap.)
3. **Narrowest wedge.** *"Smallest version that lands in **one merged PR** — one
   command, one view, one formula step — not the whole subsystem. What ships
   this week?"*
4. **Surface fit.** *"Where does this belong: a `gascity.el` `.el` view, a `gc`
   skill, a formula/molecule, an order trigger, or an agent role? Why that one
   and not the others?"* (Reuses `gascity.el`'s view-tech decision matrix
   thinking from `docs/DESIGN.md` §2.)
5. **Pipeline & observability fit.** *"How does this become **scheduled work**
   and how do you see it run? Does it produce beads, route via `gc sling`, get
   merged by the refinery? What does 'done' look like as a bead state and a
   green gate?"*
6. **Blast radius / future-fit.** *"What breaks if `gc`'s `--json`, the Dolt
   schema, or a formula contract changes under this? Does it survive the next
   `gc` upgrade, or is it pinned to today's quirks?"* (Echoes real lessons: the
   tmux-socket-not-in-`--json` deferral, the `session list` envelope shape, the
   beads store-routing trap.)

Smart-skip and an escape hatch (mirroring gstack: "the hard questions are the
value — let me ask two more, then we'll move") apply.

Two modes, reframed:
- **Ship-it mode** (default for product/infra work) ≈ gstack startup mode —
  rigorous, anti-sycophantic, all six questions.
- **Exploration mode** (research, spikes, "is this even possible") ≈ gstack
  builder mode — generative, "what's the most interesting version?"

### 3.4 Flow — idea → forcing questions → design artifact → beads

```
 raw idea  (human, in a coordinator / crew / mayor session)
    │   invoke skill:  office-hours
    ▼
┌─ Phase 1 · Context ────────────────────────────────────────────────┐
│  gc prime · bd prime · read CLAUDE.md / docs/DESIGN.md · git log    │
│  grep .designs/ + `gc bd list` for overlap · classify mode          │
└────────────────────────────────────────────────────────────────────┘
    ▼
┌─ Phase 2 · Forcing questions (AskUserQuestion, ONE AT A TIME) ──────┐
│  push for specificity · anti-sycophancy posture                     │
└────────────────────────────────────────────────────────────────────┘
    ▼
┌─ Phase 2.5 · Existing-surface discovery ───────────────────────────┐
│  gc skill list · gc formula list · grep .designs/ · gc bd list      │
│  surface overlap (esp. mol-idea-to-plan / design / plan-to-beads)   │
└────────────────────────────────────────────────────────────────────┘
    ▼
┌─ Phase 3 · Premise challenge  (agree / disagree gate) ──────────────┐
    ▼
┌─ Phase 4 · Alternatives (2–3, Effort S/M/L/XL · Risk · Reuses ·     │
│            **surface choice**)   ── HARD STOP: user picks ──────────┘
    ▼
┌─ Phase 5 · Write committed brief ───────────────────────────────────┐
│  .designs/<idea-slug>/office-hours.md  (problem · evidence · wedge · │
│  chosen surface · chosen approach · premises · open questions)      │
│  → git add/commit in the coordinator's repo                         │
└────────────────────────────────────────────────────────────────────┘
    ▼
┌─ Phase 5.5 · Adversarial spec-review (optional) ────────────────────┐
│  dispatch a review leg (mol-review-leg) OR inline subagent          │
│  5 dimensions: completeness/consistency/clarity/scope/feasibility   │
└────────────────────────────────────────────────────────────────────┘
    ▼
┌─ Phase 6 · HANDOFF gate (AskUserQuestion) ──────────────────────────┐
│  (a) sling mol-idea-to-plan  (--var problem/context seeded from the │
│      brief) → full PRD + 12 review legs + convoy + beads  [HEAVY]    │
│  (b) run `design` skill → `plan-to-beads`                 [MEDIUM]   │
│  (c) create convoy + phase beads + `gc sling` directly    [LIGHT —   │
│      when the wedge is small and already crisp]                     │
└────────────────────────────────────────────────────────────────────┘
    ▼
 scheduled work on the bus  →  polecats implement  →  refinery merges
```

### 3.5 The handoff — gascity's real differentiator vs gstack

This is where gascity diverges from gstack on purpose. gstack chains skills by
**`ls -t` over Markdown files** and a human re-running the next slash command.
gascity has a **real work bus**, so the brief becomes **durable, scheduled work**:

- **(a) Heavy — seed `mol-idea-to-plan`.** The brief's problem statement +
  chosen approach become the `--var problem=` / `--var context=` inputs. The
  brief has already done the *demand/wedge/surface* thinking, so the human gate
  inside `mol-idea-to-plan` becomes a confirmation, not a cold start.
  ```bash
  gc sling "<coordinator>" -f mol-idea-to-plan \
    --var problem="$(brief: problem + wedge)" \
    --var context="$(brief: chosen surface + approach + premises + .designs path)" \
    --var review_target="gascity.el/gastown.polecat"
  ```
- **(b) Medium — `design` → `plan-to-beads`.** For ideas that need a design pass
  but not the full 12-leg treatment.
- **(c) Light — direct convoy + phase beads.** When the wedge is small and
  crisp, skip the heavy pipeline:
  ```bash
  gc convoy create "<initiative>" --owned
  gc convoy target <id> integration/<id>
  gc bd create "<phase 1>" --rig gascity.el ...   # phase beads
  gc bd dep add <phase2> <phase1>                  # dependencies
  gc convoy add <id> <phase-ids...>
  gc sling gascity.el/gastown.polecat <first-phase>
  ```

In all three the office-hours output is **beads in Dolt** (recoverable,
queryable, mergeable), and the chosen approach is recorded with `bd remember` so
later office-hours sessions can "Search Before Building" against prior
decisions — gascity's answer to gstack's `gbrain`.

### 3.6 Output locations

| Artifact | Path | Lifetime |
|---|---|---|
| Per-idea intake brief | `.designs/<idea-slug>/office-hours.md` (in the target rig repo) | committed; superseded-chain like gstack's `Supersedes:` |
| Full design (if (a)/(b) run) | `.designs/<idea-slug>/design-doc.md` (mol-idea-to-plan / `design` already write here) | committed |
| Auto-filed work | a **convoy** + **phase beads** (+ deps), routed via `gc sling` | durable in Dolt |
| Decision memory | `bd remember` entries | persistent cross-session |

The `.designs/<slug>/` convention matches `mol-idea-to-plan`
(`.designs/$REVIEW_ID/`) and the `design` skill, so office-hours' brief sits
*next to* the design doc the pipeline later produces for the same idea.

---

## 4. gstack vs gascity — adopt / differ (honest comparison)

| Dimension | gstack | gascity-native plan | Why |
|---|---|---|---|
| Intake = forcing questions | ✅ core | ✅ **adopt** | This is the missing piece; it's the whole point. |
| Anti-sycophancy posture | ✅ | ✅ **adopt** | Without it, intake is a polite interview. |
| Two modes | startup / builder | **ship-it / exploration** | Reframe: gascity is a tools town, not a startup. |
| Mandatory alternatives gate (Effort/Risk) | ✅ | ✅ **adopt** + add **surface choice** | Surface (`.el`/skill/formula/order) is first-order here. |
| "Search Before Building" | ✅ ETHOS | ✅ **adopt, elevate** | gascity's overlap risk (design/plan-to-beads/mol-idea-to-plan) makes this critical. |
| Adversarial spec-review | subagent, ≤3 rounds | **adopt** — but as a dispatched `mol-review-leg` (or inline subagent) | Reuse the rig's review-leg primitive. |
| Chaining mechanism | **`ls -t` Markdown glob** + human re-runs slash command | **differ → beads + `gc sling`** | gascity has a real work bus; the file-glob is gstack working around *not* having one. |
| Downstream PRD/design/beads | separate skills, manual | **differ → reuse `mol-idea-to-plan`** | gascity's pipeline is richer than gstack's; don't rebuild it. |
| Persistent memory | `gbrain` / builder-profile / telemetry | **differ → `bd remember`** (+ beads history) | Drop gbrain/telemetry/builder-profile machinery; use what the town already has. |
| Distribution of the skill | npm/markdown install | **differ → pack materialization** (`gc skill`) | That's how gascity ships skills to agents. |

**Drop entirely:** gbrain cache/digests, developer-profile JSON, remote
telemetry, the relationship-tier closing, Codex-specific plumbing. They are
gstack-installation infrastructure, not intake substance.

---

## 5. Phased rollout

- **Phase 0 — this design.** ✅ doc-only (`gce-20l`).
- **Phase 1 — Skill MVP (gstack-parity intake).** Ship `office-hours` as a
  city-local pack skill: Phases 1–5 (context → forcing questions → premise →
  alternatives gate → committed `.designs/<slug>/office-hours.md`). **Manual
  handoff** — the human reads the brief and runs `mol-idea-to-plan` / `design`
  themselves. *Deliverable: a working interactive intake + a committed brief.*
- **Phase 2 — Pipeline handoff (the differentiator).** Phase 6 auto-handoff:
  seed `mol-idea-to-plan --var problem/context` from the brief and offer to
  sling it; or create a convoy + phase beads directly. Output becomes **beads on
  the bus**, not just a file.
- **Phase 3 — Adversarial review + memory.** Phase 5.5 spec-review via
  `mol-review-leg`; persist briefs/decisions with `bd remember` so prior
  sessions inform "Search Before Building."
- **Phase 4 — Porcelain surface (closes the loop in `gascity.el`).** A
  `gascity.el` entry point — an `office-hours` action in the status dashboard or
  a transient — that launches the intake in a coordinator session and shows the
  resulting convoy/beads in the rig dashboard. This is the *gascity.el-native*
  payoff: the porcelain both *starts* the intake and *visualizes* the work it
  schedules.

Each phase is independently shippable; Phase 1 delivers value alone.

---

## 6. Open questions

1. **Which session runs it?** Mayor, a dedicated crew "office-hours" role, or any
   coordinator with the target rig checked out? (`mol-idea-to-plan` says "run
   from a coordinator workspace / crew worker.") Leaning: any coordinator/crew;
   not the mayor (mayor consumes the resulting convoy).
2. **One human gate or two?** office-hours' up-front gate vs
   `mol-idea-to-plan`'s `human-clarify` gate. Keep both (they ask different
   things — *should we build this?* vs *resolve PRD ambiguities*), or have
   office-hours' findings pre-answer the latter? Leaning: keep both, but pass
   the brief so `human-clarify` starts warm.
3. **Does office-hours file an intake bead itself, or stay doc-only until
   handoff?** A "raw idea" bead gives recoverability mid-intake; doc-only keeps
   Dolt clean. Leaning: doc-only through Phase 1; optional intake bead in Phase 2.
4. **Mode taxonomy.** Is "ship-it / exploration" the right split for this town,
   or do we need a third (e.g. "infra/refactor" where demand questions don't
   apply and Q4/Q6 dominate, mirroring gstack's "pure engineering → Q2,Q4")?
5. **Pack placement & precedence.** Confirm gc's supported city-local pack path
   and override precedence (`.gc/runtime/packs/` vs `.gc/system/packs/`) so the
   Phase-1 skill can ship locally before an upstream gc-core PR.
6. **Convoy vs epic for auto-filed work.** Convoys are the modern container
   ("epic beads no longer first-class"), but `plan-to-beads` still emits an
   epic + tasks. Standardize office-hours' direct path on **convoy + phase
   beads**; treat `plan-to-beads` (epic) as the legacy medium path.
7. **Skill-vs-formula boundary for unattended runs.** Is a future
   `mol-office-hours` formula worth it for non-interactive "intake + auto-sling,"
   or does the interactive skill cover all real use? Defer until Phase 2 usage
   data exists.

---

## 7. References

- gstack: `office-hours/SKILL.md` (v2.0.0), `docs/skills.md`, `ARCHITECTURE.md`,
  `ETHOS.md` — https://github.com/garrytan/gstack
- gascity formula: `.gc/system/packs/gastown/formulas/mol-idea-to-plan.toml`
  (+ `mol-review-leg`)
- gascity skills: `core.gc-dispatch`, `core.gc-work`
  (`.gc/system/packs/core/skills/`)
- `plan-to-beads`:
  `~/.claude/plugins/marketplaces/beads-marketplace/integrations/claude-code/commands/plan-to-beads.md`
- `gascity.el` architecture & view-tech matrix: `docs/DESIGN.md` (§2)
- This rig's worked example of design → epic → phase beads:
  `docs/DESIGN-write-actions.md` + epic `gce-7rs`
