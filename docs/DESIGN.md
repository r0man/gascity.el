# gascity.el — Design

*A Magit-style Emacs porcelain for [Gas City](https://github.com/gastownhall/gascity)
(`gc`), integrated with [beads.el](https://github.com/r0man/beads.el).*

Status: design draft. Approach: **greenfield**, built on beads.el's command
infrastructure and vui rendering. `gastown.el` (the pre-rename precursor that
targeted the old `gt` CLI) is a **reference**, not a fork.

---

## 1. Thesis

Gas City's `gc` CLI is the *plumbing*; gascity.el is the *porcelain*. Every
view is a function of `gc … --json` output. We do not reimplement gc logic — we
render its state and dispatch its commands, keyboard-first, the way Magit fronts
git.

Three things we deliberately **reuse rather than rebuild**:

1. **`beads-meta`** — beads.el's EIEIO slot-metadata engine. A command class
   declares slots; beads-meta infers CLI options, builds the command line, and
   generates the transient. We get auto-generated, consistent menus for free.
2. **vui** — beads.el's rendering layer. `beads-section-mode` *derives from
   `vui-mode`*; `beads-dashboard-mode` derives from that. gascity's rich views
   derive from `beads-section-mode`, inheriting vui's reconciler, layout
   primitives, faces, and `q`/`g` conventions.
3. **beads.el's bead UI** — gc manages issues via `gc bd` (prefix-routed per
   rig). We never render beads ourselves; we open beads.el's existing list /
   detail / dashboard, scoped to a rig's store.

What we build is the **gc-specific layer**: the command classes for gc's
surface, the city/rig/agent views, and the glue that scopes beads.el to a rig.

---

## 2. View-technology decision matrix

Per `gastown.el/docs/vui-design.md`, adapted for a vui-first greenfield:
**native modes for browse/act/menu; vui for view/edit/interact.**

| Surface | Mechanism | Rationale |
|---|---|---|
| Command dispatch & arg collection | **transient** | Best-in-class; infixes carry `--json`/flags |
| Homogeneous lists (rigs, sessions, convoys, mail, orders, dolt dbs) | **tabulated-list-mode** | Sorting, navigation, `tabulated-list-get-id` for free; fast |
| Town status overview (city → rigs → agents/polecats) | **vui** | Heterogeneous, collapsible, async per-rig loading |
| Rig detail dashboard | **vui** | Mixed sections + async + action bar |
| Session / polecat detail | **vui** | State + hook bead + history + inline actions |
| Bead list / detail / board | **delegate to beads.el** | Already vui; don't duplicate |
| Confirmations / previews | **transient + minibuffer** | — |

Anti-patterns (from the vui doc, still binding): never render content in
transient; never use vui for homogeneous lists tabulated handles better; never
`insert` inside a vui buffer; batch multi-field `vui-set-state`.

---

## 3. Module layout

All symbols prefixed `gascity-`; executable defcustom defaults to `"gc"`.

**Foundation**
- `gascity.el` — package header, top-level `gascity` transient, autoloads, glue.
- `gascity-custom.el` — defgroup, `gascity-executable` ("gc"), faces, terminal backend choice.
- `gascity-error.el` — `define-error` conditions (`gascity-command-error`, `gascity-json-parse-error`, `gascity-validation-error`).
- `gascity-context.el` — resolve current city/rig from `default-directory` (walk up) or explicit selection; cache.
- `gascity-reader.el` — run `gc … --json` via `process-file`, capture stdout/stderr/exit, parse JSON → alist/vector; typed accessors (`gascity-reader-rigs`, `-sessions`, `-convoys`, …).

**Command layer (built on beads-meta)**
- `gascity-command.el` — `gascity-defcommand` macro + EIEIO base classes
  (`gascity-command` abstract → `gascity-command-global-options` with
  `json`/`verbose`). `execute`, `command-line`, `parse`, `subcommand`
  (auto-derived from class name), `execute-interactive` (terminal). Reuses
  `beads-meta-build-command-line`, `beads-meta-define-transient`,
  `beads-meta-slot-property`, and the `beads--extract-option` /
  `beads--derive-transient-name` helpers. Bridge methods delegate
  `beads-command-validate/execute-interactive/preview` → `gascity-command-*`
  (the same pattern gastown.el used to drive beads-meta's generated suffixes).
- `gascity-types.el` — concrete command classes for the gc surface, one per
  subcommand, declaring slots with metadata that beads-meta turns into transient
  infixes.
- `gascity-command-<domain>.el` — the transient prefixes per domain (see §5).

**Rendering**
- `gascity-section.el` — `gascity-section-mode` derived from `beads-section-mode`
  (→ vui); shared vui helpers: status badges, agent-state faces, action bars,
  collapsible rig section.
- `gascity-status.el` — `gascity-status` command + `gascity-status-app` vui root.
- `gascity-rig.el` — `gascity-rig-dashboard` vui detail view.
- `gascity-session.el` / `gascity-polecat-detail.el` — vui session/polecat detail.
- `gascity-tabulated.el` — tabulated-list views + a `gascity-tabulated-mode`
  base with common keymap (RET → detail, `g` refresh, action keys).
- `gascity-beads.el` — the beads.el bridge (see §4.3).

**Support**
- `gascity-terminal.el` — vterm/eat/term backends for interactive commands
  (`peek`, `shell`, anything streaming). Lifted from gastown.el's proven impl.
- `gascity-completion.el` — completion sources for rigs, sessions, beads, targets.

---

## 4. beads.el integration — three layers

### 4.1 Command infrastructure (compile-time reuse)
`gascity-defcommand` is a thin wrapper over `beads-meta`. A class like:

```elisp
(gascity-defcommand gascity-command-rig-list (gascity-command-global-options)
  ((suspended :type boolean :long-option "suspended"))
  :global-section gascity-command-global-options
  :documentation "List rigs in the city.")
```

…yields the class, a `gascity-command-rig-list!` executor, **and** a transient
prefix — because beads-meta infers the infixes from slot metadata. This is the
same machinery beads.el uses for `bd`; we inherit consistency and tests.

### 4.2 Rendering (runtime reuse)
`gascity-section-mode` derives from `beads-section-mode` (vui). We reuse beads'
vui section helpers and faces so gascity and beads buffers look and behave
identically (same keymaps, same `g`/`q`, same collapsible idioms).

### 4.3 Bead UI delegation (the contract)
gc owns beads through `gc bd <…>` with **prefix-based routing** (e.g. `exc-*` →
example.city). gascity does **not** render beads. Instead:

- A rig row / rig dashboard exposes **“beads”** → opens beads.el's bead list
  **scoped to that rig's store** (resolve the rig's `.beads` path / prefix from
  `gc rig status --json`, hand it to beads.el's list command).
- A routed/ready bead reference (in status, sling, convoy views) → `RET` opens
  **beads.el's bead detail** (already a vui buffer).
- “Sling” / “route” actions are gascity's (they call `gc sling` or set
  `gc.routed_to`); the *display* of the resulting beads is beads.el's.

Open question for §9: does beads.el's list command already accept an explicit
store/prefix arg, or do we set its store via `default-directory` / a dynamic
var? This determines how clean the scoping is.

---

## 5. gc CLI → UI map

**Main transient** (`M-x gascity`, suggested groups):

- *Overview*: `s` status (vui dashboard) · `D` doctor · `i` info/version
- *Rigs*: `r` rig… (list/status/add/suspend/resume/restart) · `l` rig list (tabulated)
- *Work & dispatch*: `S` sling · `k` hook · `o` order… · `c` convoy… · `f` formula/mol…
- *Agents & sessions*: `a` session/agent… · `L` session list (tabulated) · `p` peek · `n` nudge
- *Beads*: `b` → beads.el (`beads`) scoped to current rig
- *Comms*: `m` mail · `H` handoff
- *Infra / data plane*: `U` service… · `d` dolt… · `G` config… · `P` pack/import…
- *Lifecycle*: `start`/`stop`/`suspend`/`resume`/`reload`/`restart`

**Tabulated views** (`gascity-tabulated.el`): rigs, sessions, convoys, mail
inbox, orders, dolt databases. Each: columns from JSON, `RET` → detail (vui or
delegate), domain action keys (e.g. on a session: `n` nudge, `k` drain, `RET`
detail, `t` open terminal).

**vui views**: status dashboard (§6), rig dashboard, session/polecat detail.

The full gc surface to cover (from `gc --help`): agent, analyze, bd→beads,
beads, cities, config, convoy, dashboard, doctor, dolt, event(s), formula,
graph, handoff, hook, import, init, lint, mail, mcp, nudge, order, pack, prime,
prompt, register, reload, restart, resume, rig, runtime, service, session,
shell, skill, sling, start/stop/suspend, status, supervisor, trace, version,
wait. Not all need rich UI — many are one-shot transient suffixes.

---

## 6. Concrete vui component sketches

```
gascity-status-app            ; root; state: refresh-tick, expanded-rigs
├── gascity-global-agents     ; mayor / deacon badges (vui-hstack)
└── vui-list of gascity-rig-section   ; keyed by rig name
    └── gascity-rig-section    ; vui-use-async per rig (loads independently)
        ├── vui-collapsible header (name, suspended?, running?)
        ├── witness / refinery rows
        └── vui-list of gascity-polecat-row (keyed by session id)
```
Each rig section loads its own `gc rig status --json` asynchronously, so a slow
rig never blocks the others; collapsed rigs defer loading (children-as-lambda).
Refresh = increment `refresh-tick` (invalidates `vui-use-async` keys).

```
gascity-rig-dashboard         ; header · agents table · ready/in-progress beads
                              ; (→ beads.el) · orders · dolt health · action bar
gascity-polecat-detail        ; state · hook bead · recent history · mail count
                              ; actions: peek / nudge / drain / open-terminal
```

Data flow: `gc … --json` → `gascity-reader` → alist → vui props.
`vui-use-async` with a refresh counter for loads; `vui-use-memo` keyed on
data-tick for expensive derivations.

---

## 7. Build phases

- **P0 — Skeleton & bridge.** Package metadata
  (`Package-Requires: ((emacs "29.1") (transient "0.10.1") (vui "1.0.0") (beads "…") (sesman "0.3.2"))`),
  `gascity-custom`, `gascity-error`, `gascity-reader`, `gascity-context`,
  `gascity-command` on beads-meta. Smoke test: `gascity-command-status!` round-trips
  `gc status --json` → alist.
- **P1 — Command menus.** `gascity-types` + `gascity-command-*` + the main
  `gascity` transient. Reaches functional parity (dispatch everything via
  transient; output to terminal or messages).
- **P2 — Tabulated lists.** rigs, sessions, convoys, mail, orders, dolt; `RET`
  → detail, action keys, `g` refresh.
- **P3 — vui status dashboard.** `gascity-status-app` (collapsible, async per-rig).
- **P4 — vui detail views.** rig dashboard, session/polecat detail.
- **P5 — beads.el bead-UI delegation.** Per-rig scoping done cleanly (§4.3).
- **P6 — Polish.** completion, error surfaces, README, `whats-new`, Eldev/guix.scm.

Each phase is independently shippable; P0–P2 already give a usable porcelain.

---

## 8. Conventions (match beads.el / gastown.el)

- One `gascity-command-<domain>.el` per gc domain; classes auto-derive their
  subcommand from the class name (`gascity-command-rig-list` → `rig list`).
- `--json` is the default for anything we parse; terminal backend for anything
  interactive/streaming.
- Faces and section idioms inherited from `beads-section-mode`.
- `q` buries, `g` refreshes, `RET` drills in — everywhere.

---

## 9. Open decisions

1. **beads.el store scoping API** (§4.3) — explicit arg vs `default-directory`
   vs dynamic var. Drives how clean rig-scoped bead views are. *Needs a look at
   beads.el's list command signature.*
2. **magit-section dependency** — the old vui doc kept magit-section for status;
   greenfield + vui-first means we can drop it (beads-section-mode is vui). Keep
   it out unless a view truly needs the tree. Decision: **vui-only** for status.
3. **sesman** — gastown.el used sesman 0.3.2 to associate buffers with sessions.
   Reuse for linking a code buffer ↔ its rig/polecat? Defer to P4+.
4. **Naming of the entry command** — `M-x gascity` (prefix transient). A short
   alias?
5. **Async transport** — `vui-use-async` wants a thunk; `gascity-reader` should
   offer an async variant (`make-process`) so dashboards never block redisplay.
6. **City vs rig scope** — many gc commands are city-wide; some rig-scoped. The
   `gascity-context` must make “current rig” explicit and switchable (header
   line + a `R` switch-rig command).

---

## 10. References

- `gastown.el/lisp/*` — reference implementation (pre-rename, targets `gt`).
- `gastown.el/docs/vui-design.md` — the view-technology research this builds on.
- `beads.el/lisp/beads-meta.el` — the command-metadata engine we reuse.
- `beads.el/lisp/beads-section.el` — `beads-section-mode` (vui) base to derive from.
- vui.el — bundled in `beads.el/.eldev/30.2/packages/vui-1.0.0/`.
