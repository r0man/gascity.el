# gascity.el — Design

*A Magit-style Emacs porcelain for [Gas City](https://github.com/gastownhall/gascity)
(`gc`), integrated with [beads.el](https://github.com/r0man/beads.el).*

Status: **MVP + command dispatch + detail views implemented** (P0 skeleton + P2
tabulated lists + P3 vui status dashboard + agent actions + P1 mutating-command
dispatch + P4 rig dashboard & session/polecat detail). Approach: **greenfield**,
built on beads.el's
command infrastructure and vui rendering. `gastown.el` (the pre-rename precursor
that targeted the old `gt` CLI) is a **reference**, not a fork.

> **UI direction (binding; supersedes the auto-generated-transient framing
> below).** The primary UI is **hand-built, magit/forge-style**: deliberately
> designed, keyboard-driven, sectioned buffers — the vui status dashboard and
> detail views, and `tabulated-list-mode` for homogeneous lists. The
> beads/gascity command **classes** (`beads-meta`) are reused **only as the
> execution + parse layer** — they run `gc` commands (synchronously or
> asynchronously) and decode `--json` into Elisp data. We do **not** make
> beads.el's *auto-generated* transients the primary interface. Transients are
> fine as a **command-dispatch backend** (the `gascity` entry menu, per-list
> `/` filters), never as the porcelain itself.

---

## 1. Thesis

Gas City's `gc` CLI is the *plumbing*; gascity.el is the *porcelain*. Every
view is a function of `gc … --json` output. We do not reimplement gc logic — we
render its state and dispatch its commands, keyboard-first, the way Magit fronts
git.

Three things we deliberately **reuse rather than rebuild**:

1. **`beads-meta`** — beads.el's EIEIO slot-metadata engine, reused as the
   **execution + parse layer**. A command class declares slots; beads-meta
   infers CLI options and builds the command line, and gascity runs it (sync or
   async) and decodes `--json`. (beads-meta *can* also generate a transient from
   the same metadata; per the UI direction above we use that only for
   command-dispatch backends, not as the porcelain.)
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
- `gascity-reader.el` — **the** read primitive layer (the single place `gc` is invoked): `gascity-reader-run` (sync `process-file`, captures stdout/stderr/exit), `gascity-reader-parse-json` (JSON → alist/vector), `gascity-reader-read` (sync `gc … --json` → payload), and `gascity-reader-read-async` (the `make-process` variant backing `vui-use-async`). There are deliberately **no** per-subcommand `gascity-reader-*` accessors: named sync reads are the `gascity-command-*!` bang functions below (e.g. `(gascity-command-rig-list!)` for the rig list), so there is one documented read path, not two parallel ones.

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

- A rig row / rig dashboard exposes **“beads”** (`b`) → opens beads.el's board
  **scoped to that rig's store** (resolve the rig's repo `path` — the directory
  holding its `.beads/` — from `gc rig status`/`gc rig list --json`, bind
  `default-directory` to it, then call beads.el).
- A routed/ready bead reference (in status, sling, convoy views) → `RET` opens
  **beads.el's bead detail** (already a vui buffer), scoped to the store that
  owns the bead's id prefix.
- “Sling” / “route” actions are gascity's (they call `gc sling` or set
  `gc.routed_to`); the *display* of the resulting beads is beads.el's.

**Scoping mechanism (resolves the §9.1 open question).** beads.el's
high-level entry points — `beads-show` (detail), `beads-dashboard` (board),
`beads-ready`/`beads-blocked` (lists) — resolve *which* store to act on from
`default-directory` (via `beads--project-root`, which walks up for a
`.beads`/VC root). There is **no explicit store/prefix argument** on these
interactive commands; the lower `beads-command` layer does carry `--db` and
`--directory`/`-C` slots, but the UI entries are purely directory-driven. So
gascity scopes a delegated view by **binding `default-directory` to the rig's
repo path**. A freshly created beads buffer inherits that bound directory, and
the detail/list entries persist it buffer-locally, so the scoping survives `g`
refreshes. (The `beads-list` *transient* is deliberately **not** used for
programmatic scoping: its suffixes read `default-directory` when the user later
picks one, after the `let` binding has unwound — so the rig's `b` opens the
directory-scoped board `beads-dashboard` instead.)

Bead **detail** is scoped the same way, keyed off the bead id's prefix: gc
routes beads by prefix (`gce-*` → the gascity.el rig), so the id determines the
owning store regardless of which (often city-wide) view the reference appears
in. `gascity-bead-show` maps the prefix to that rig's `path` and binds
`default-directory` before delegating to `beads-show`.

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

- ✅ **P0 — Skeleton & bridge.** Package metadata
  (`Package-Requires: ((emacs "29.1") (transient "0.10.1") (vui "1.0.0") (beads "…") (sesman "0.3.2"))`),
  `gascity-custom`, `gascity-error`, `gascity-reader`, `gascity-context`,
  `gascity-command` on beads-meta. `gascity-command-status!` round-trips
  `gc status --json` → alist.
- ✅ **P2 — Tabulated lists.** `gascity-tabulated`: rigs, sessions, convoys,
  mail, orders, dolt databases. `RET` drills in, `g` refreshes; on a session
  row, `d` opens its worktree in Dired and `t` attaches to its tmux session.
  Concrete command classes live in `gascity-types`. *(Pagination and per-list
  `/` filters landed as a follow-up — see §11.1-2, gce-ahl.)*
- ✅ **P3 — vui status dashboard.** `gascity-status` (`gascity-status-app`):
  collapsible per-rig sections, two async loads (`gc status` + `gc session
  list`) joined client-side, `g` refresh (in-place, preserves expanded rigs),
  agent rows actionable with `d`/`t`. (`gc status` returns the whole tree in one
  fast call, so a single async fetch replaces the originally-sketched
  per-rig fan-out; revisit if towns grow large enough to need it.)
- ✅ **Agent actions.** `gascity-section` (Dired + at-point dispatch) +
  `gascity-terminal` (tmux attach via beads.el's `beads-terminal-spawn`, the
  reused terminal module). Worktree comes from a session's `work_dir`; the tmux
  server socket is the city name (`gascity-tmux-socket` to override) — gc does
  not expose it in `--json`, unlike the old `gt`.
- ✅ **P1 — Command dispatch.** Mutating command classes
  (`gascity-command-action` base, `--json` off so success is read from the
  exit status): rig suspend/resume/restart, session nudge/suspend/kill/wake,
  sling, order run, and city start/stop. `gascity-action` runs the quick ones
  synchronously and reports the outcome (`gascity-command-act`), streaming the
  long-running lifecycle ones. Reached two ways, both hand-built (not an
  auto-generated UI): at point in the lists and the status dashboard (rig
  `s`/`r`/`R`; session `N`/`s`/`K`/`w`; order `x`), and by prompt from the
  broadened `gascity' dispatcher's sub-transients (`gascity-rig-dispatch',
  `gascity-session-dispatch', `gascity-lifecycle-dispatch'), which complete
  arguments over live `gc` data. *(Deferred: richer sling infixes
  (`--formula`/`--merge`/…) and `order run --rig` disambiguation — see §11.)*
- ✅ **P4 — vui detail views.** `gascity-rig` (`gascity-rig-dashboard`): a rig's
  header, agents table (joined to `gc session list` for `d`/`t`/`RET` actions),
  ready and in-progress beads (`gc bd ready` / `--status in_progress`, both
  `--rig` scoped; `RET` → beads.el), rig-scoped orders, and the rig's Dolt stats
  (matched on the bead prefix). `gascity-session`
  (`gascity-polecat-detail`): an agent's state, mail count, the bead on its hook,
  and recent history — beads fetched per assignee key (a polecat's runtime
  session name, a service agent's qualified name) via server-side `--assignee`
  (a broad window buries an agent's beads under a town's closed order beads),
  plus — since a polecat's finished work is reassigned to the refinery, matching
  no key — recent beads carrying a `work_dir` nested under the agent's worktree,
  with inline `p` peek / `N` nudge / `D` drain / `d` dired / `t` tmux actions on
  the subject. `RET` from the rig list, session list, and status dashboard opens
  these instead of the former Dired/`beads-show` stand-ins. Adds `peek`
  (read-only output capture) and `runtime drain` to the command surface.
- ✅ **P5 — beads.el bead-UI delegation.** Per-rig scoping done cleanly (§4.3,
  §9.1): gascity binds `default-directory` to a rig's repo `path` and hands off
  to beads.el, which resolves the store from that directory. `gascity-rig-beads`
  opens the rig's board (`beads-dashboard`); the rig list and rig dashboard bind
  it to `b`, and the `gascity` transient adds `b` (prompts, defaulting to the
  contextual rig). Bead `RET` (`gascity-bead-show`) now scopes detail to the
  store owning the bead id's prefix, so convoy / rig-dashboard / session-detail
  references open against the right store instead of the ambient directory.
- ⬜ **P6 — Polish.** completion, error surfaces, `whats-new`, Eldev/guix.scm.

The MVP (P0 + P2 + P3 + agent actions + P1 dispatch + P4 detail views) is
delivered and verified against a live town; it is already a usable porcelain.

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

1. **beads.el store scoping API** (§4.3) — *Resolved.* beads.el's interactive
   entries (`beads-show`, `beads-dashboard`, `beads-ready`) take no store/prefix
   argument; they resolve the store from `default-directory` via
   `beads--project-root`. (The `beads-command` layer carries `--db`/`--directory`
   slots, but the UI commands are directory-driven, and the `beads-list`
   transient can't be scoped programmatically — its suffixes read
   `default-directory` after the `let` unwinds.) gascity therefore binds
   `default-directory` to the rig's repo `path` and lets beads.el find the
   `.beads/` there. See §4.3.
2. **magit-section dependency** — the old vui doc kept magit-section for status;
   greenfield + vui-first means we can drop it (beads-section-mode is vui). Keep
   it out unless a view truly needs the tree. Decision: **vui-only** for status.
3. **sesman** — gastown.el used sesman 0.3.2 to associate buffers with sessions.
   Reuse for linking a code buffer ↔ its rig/polecat? Defer to P4+.
4. **Naming of the entry command** — `M-x gascity` (prefix transient). A short
   alias?
5. **Async transport** — *Resolved.* `gascity-reader-read-async` (make-process,
   separate stderr) backs `vui-use-async`; the status dashboard never blocks.
6. **City vs rig scope** — many gc commands are city-wide; some rig-scoped. The
   `gascity-context` must make “current rig” explicit and switchable (header
   line + a `R` switch-rig command).

---

## 10. References

- `gastown.el/lisp/*` — reference implementation (pre-rename, targets `gt`).
- `gastown.el/docs/vui-design.md` — the view-technology research this builds on.
- `beads.el/lisp/beads-meta.el` — the command-metadata engine we reuse.
- `beads.el/lisp/beads-section.el` — `beads-section-mode` (vui) base to derive from.
- `beads.el/lisp/beads-terminal.el` — `beads-terminal-spawn`, the reused terminal module.
- vui.el — bundled in `beads.el/.eldev/30.2/packages/vui-1.0.0/`.

---

## 11. Deferred work (read-only MVP follow-ups)

Tracked as beads off the MVP. None block the shipped porcelain.

1. ✅ **List pagination.** gastown's paged mixin (`]`/`[`/`G`, window-sized
   pages, mode-line `[page/total]`, resize-aware) ported into `gascity-tabulated`
   as a shared base keymap plus buffer-local paging state (gce-ahl).
2. ✅ **List filters.** Per-list `/` transient writing filter slots on the
   `gascity-command-*` classes (gce-ahl). `gc` list subcommands expose almost no
   server-side filter flags, so filtering is **client-side** on the decoded rows
   — the session `--state` filter is the lone server-side exception; client-side
   slots carry no `:long-option` and never reach the command line. Dolt has no
   meaningful filter dimension, so it keeps pagination only.
3. ✅ **vui detail views (P4).** Rig dashboard (`gascity-rig`) and
   session/polecat detail (`gascity-session`); `RET` from the rig list, session
   list, and status dashboard now opens them instead of the Dired stand-in
   (gce-3iq). Added `gc session peek` and `gc runtime drain` to the command
   surface for the detail action bar.
4. ✅ **beads.el bead-UI delegation (P5).** `gascity-rig-beads` opens beads.el's
   board scoped to a rig's store (rig list / rig dashboard `b`, plus a `b` entry
   on the `gascity` transient); `gascity-bead-show` scopes bead detail to the
   store owning the bead's id prefix, so convoy / rig-dashboard / session `RET`
   delegate against the right store instead of the ambient directory (gce-afq,
   §4.3 / §9.1).
5. ✅ **Mail row shape.** Confirmed against the `gc mail inbox --json` v1
   `mail_message` schema (`from` / `subject` / `created_at` / boolean `read`);
   `gascity-mail-inbox--entry` reads those keys directly and the tolerant
   key-guesser (`gascity-tabulated--field`) was removed (gce-384).
6. **tmux socket from gc** (gce-je4). gc does not expose the tmux server socket
   in `--json` (the old `gt` did); `gascity-resolve-tmux-socket` infers it from
   the city name (override via `gascity-tmux-socket`). Verified 2026-06-02 that
   `gc session list`/`gc status --json` still carry no socket field, so the
   read-side fix is blocked on an upstream `gc` change to expose it (or a stable
   accessor); the inference stays a deliberate fallback until then.
7. **Dashboard refresh ergonomics.** Optional auto-refresh/watch and semantic
   cursor preservation across re-renders (gastown has both).
8. **Richer sling infixes (P1 follow-up).** The `gascity-command-sling` class
   already models `--formula`/`--nudge`/`--dry-run`; the interactive
   `gascity-sling` only prompts target + bead/text. Add a sling sub-transient
   exposing those flags (plus `--merge`, `--no-convoy`) as infixes.
9. **`order run --rig` disambiguation (P1 follow-up).** `gascity-order-run`
   passes only the order name; add the rig (available on the at-point order
   row, and promptable elsewhere) so same-named orders across rigs resolve.
