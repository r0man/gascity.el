# gascity.el — Dogfood QA Report (gce-osd)

A third hands-on, **interactive** dogfood pass over the gascity.el porcelain, driven
against the **live** Gas Town at `/home/roman/bright-lights`. Like gce-tbd, this one
drives a real Emacs with real keystrokes in a tmux pane and reads back state via
`emacsclient -e`, cross-checking every datum against `gc … --json` at the same
instant. This is **test + file only** — no porcelain code was changed; each new
bug/improvement is a linked follow-up bead for the Mayor to dispatch.

The bar for this pass: the codebase has already been dogfooded twice (gce-ea7,
gce-tbd) and all 11 prior findings are merged. So the goal here was to find **new**
issues — pushing the less-travelled paths (the HQ rig, multi-page sorting, the most
basic key in the vui views) that the happy-path passes didn't reach.

## Setup

| | |
|---|---|
| Target | `origin/main` @ `7acb2b6` (MVP + pagination/filters + mutating + detail views + beads delegation + all gce-ea7/gce-tbd follow-ups + gce-952 terminal-reuse) |
| Env | GNU Emacs 30.2, tmux 3.6a; deps: transient 0.13.1 / sesman 0.3.4 / compat / eat / vterm from the Guix-home profile, vui 1.0.0 + the `beads.el` sibling checkout |
| City | `bright-lights` — controller down (supervisor-managed, PID 2155, `running:false`) · health degraded · **10/25 agents running**; tmux socket = city name `bright-lights` |
| Method | `emacs -nw -q -l <harness>` in a dedicated tmux server (`-L gce-dogfood`) running an Emacs server (`-s gce-dogfood`). Driven by **real keystrokes** (`M-x`, `RET`, `g`, `q`, `]`, `S`) sent to the pane and by `emacsclient -e` reading buffers / point / faces / keymaps / pagination — every datum cross-checked against `gc … --json` / `gc bd` / `gc rig status` / `gc dolt health` live. The package byte-compiles clean (`eldev compile`, exit 0, no warnings). |
| Write-side safety | **No destructive mutation was fired against the live town, and no beads beyond the five follow-ups were created.** Mutating paths were exercised read-only (peek on a stopped agent → clean error) or by construction; the only live executions against real state were reads. |

## PASS / FAIL matrix

| # | Feature | Verdict |
|---|---------|---------|
| 1 | Status dashboard — data, faces, collapse, `g` refresh, point | **PASS** — `q` broken (gce-0d5) |
| 2 | Tabulated lists — data, columns, truncation, pagination, `/` filter + indicator | **PASS** — sort broken across pages (gce-dzs) |
| 3 | Rig list — data; `RET`→dashboard, `b`→beads, `d`→Dired | **FAIL on `RET` for the HQ row** (gce-6bq); "Beads" column misleading (gce-79f) |
| 4 | Rig dashboard — 6 async sections (incl. suspended-rig + HQ edge cases) | **PASS** (HQ failure tracked as gce-6bq); `q` broken (gce-0d5) |
| 5 | Session/polecat detail — state/mail/on-hook/history | **PASS** (Recent history empty = gce-dw4, already owned); `q` broken (gce-0d5) |
| 6 | Convoy list — data; `RET`→beads.el (the gce-bhr case) | **PASS** — gce-bhr re-verified fixed |
| 7 | Order list — data, `RET`→source, `x` run | **PASS** |
| 8 | Dolt list — data, `RET` echo | **PASS** |
| 9 | Mail inbox — empty state, identity resolution | **PASS** |
| 10 | `gascity` dispatcher transient | **PASS** |
| 11 | Agent actions — Dired, tmux attach, peek | **PASS** |
| 12 | Conventions — `g`/`RET`/`/`/`]`/`G`, faces, customization | **PASS** except `q` in vui views (gce-0d5) |

Net: the porcelain remains in strong shape — async loads, error surfaces, filters,
pagination mechanics, and beads delegation all work. **2 bugs + 1 bug + 2 improvements
newly filed (5 total).** The headline is gce-0d5: `q` — the most basic porcelain key —
does not bury the three vui views.

## gce-dw4 — confirmed, NOT re-filed

Per the bead's instruction, the agent-detail "Recent history empty for productive
agents" bug was confirmed but **not** re-filed: the detail for `gascity.el/gastown.furiosa`
(which is itself working gce-dw4) shows `On hook (1) gce-dw4 in_progress` and
`Recent history (0) no recent beads`. (Root cause aligns with the
[gc-agent-work-history] note: a polecat's finished beads are reassigned to the
refinery, so the detail's `--assignee` query can't find its closed work — slightly
deeper than the bead's "queries OPEN-only" framing, but the same symptom; left for
gce-dw4's owner.)

## Prior follow-ups — re-verified still fixed

| Bead | Fix | Re-verified this pass |
|------|-----|-----------------------|
| `gce-gie` | `g` preserves rig collapse | ✅ collapsed `▶ example-town-cl` stayed collapsed across `g` (real keypress) |
| `gce-ey4` | active-filter indicator | ✅ session `rig=gascity.el` filter → mode line `Sessions [1/1] (rig=gascity.el)`, 4 rows |
| `gce-bhr` | convoy `RET` via `bd --directory` | ✅ `RET` on `bs-0q2z` opened `beads-show-mode` with real content (no "no issues found") |
| `gce-l5x` | long names truncated, not overflowing | ✅ `cross-rig-deps:rig:burnings…` with full-name `help-echo` |
| `gce-94g` | numeric column **comparator** | ✅ Dolt Commits sort numerically (note: scope-of-sort across pages is the new gce-dzs) |
| `gce-952` | reuse already-open agent terminal | ✅ terminal-reuse path present at HEAD |

## New follow-ups filed (linked `discovered-from: gce-osd`, label `dogfood`,`qa`)

| Bead | Type | Pri | Title |
|------|------|-----|-------|
| `gce-0d5` | bug | P2 | vui views (status/rig/session-detail): `q` doesn't bury — errors "Text is read-only" |
| `gce-dzs` | bug | P2 | Tabulated lists sort per-page, not across the full paginated dataset |
| `gce-6bq` | bug | P3 | Rig list: `RET` on the HQ rig (bright-lights) opens a dashboard that errors |
| `gce-79f` | feat | P3 | Rig list "Beads" column shows store status ("initialized"), not a count |
| `gce-d16` | feat | P3 | Timestamps show date only — "last active" / mail Date lose same-day recency |

## Detail

### 1. Status dashboard — PASS, but `q` broken (gce-0d5)
Header `Gas City: bright-lights · controller down · health degraded · agents 10/25
running` matches `gc status --json` (`controller.running:false`, `health.degraded:true`,
`summary` 10/25). City→rig→agent tree correct (city-scope dogs/boot/deacon/mayor under
"City"; collapsible per-rig sections for example-town-cl / example.city *(suspended)* /
gascity.el; the HQ correctly omitted as a rig section). `●`/`○` + faces correct.
`RET` toggles a rig / opens an agent's detail; **`g` preserves collapse** (gce-gie, real
keypress). **`q` → `self-insert-command: Text is read-only` and the buffer is not
buried (gce-0d5).**

### 2. Tabulated lists — PASS, but cross-page sort broken (gce-dzs)
Six lists render correct columns from live `--json` (rigs 4, sessions 10, convoys 47,
orders 48, dolt 4, mail 0). Long names truncate with `…`+`help-echo`. Pagination real:
orders `[1/2]`, `]`→`[2/2]`, `[`→`[1/2]`, `G 99`→ clean `user-error "Page 99 out of
range (1-2)"`. Filters apply and the **active-filter indicator** shows in the mode line
(gce-ey4). **But sorting only orders the visible page** — on 48 orders the default
ascending view strands d/p/s-prefixed `…:rig:example.city` orders on page 2 even though
page 1 already runs beads-health→wisp-compact; `S` re-sorts only the current page
(gce-dzs). Masked on single-page lists, which is why earlier passes (sorting the 4-row
Dolt list) didn't catch it.

### 3–4. Rig list + dashboard — HQ dead-end (gce-6bq), "Beads" column (gce-79f)
Rig list: 4 rigs, Name/Prefix/Status/Branch/Beads all matching `gc rig list`. `RET` on
**gascity.el** → full 6-section dashboard (header; Agents 7 with roles; Ready 3 /
In-progress 4 = rig-scoped `gc bd ready`/`--status in_progress`; Orders 10; Dolt
`gce: 277 commits`). `RET` on the **suspended** example.city → renders fine (all stopped,
Ready/In-progress empty). **`RET` on the HQ `bright-lights` → error dashboard**
("Could not load rig … `gc rig status bright-lights` failed (exit 1)") because the HQ
isn't a city.toml rig (gce-6bq) — yet `b` on that same row opens its beads fine.
The **"Beads" column shows "initialized"** (a store status) on every row, not a count
(gce-79f). `g` on the dashboard preserves point; `q` is broken here too (gce-0d5).

### 5. Session/polecat detail — PASS (Recent history = gce-dw4)
`gascity.el/gastown.furiosa` and the city-scope `gastown.mayor` both render
state/provider/attached/worktree/tmux + mail count + On-hook + Recent-history. Mail
count loads slowly (`gc mail inbox <name>` ~several s) behind a `mail …` placeholder
while the rest renders — the independent-async design, not a bug. "On hook" empty state
("idle — no work on hook") is clean. Recent history empty = gce-dw4. "last active" shows
date only (gce-d16). `q` broken (gce-0d5).

### 6–11. Convoy / Order / Dolt / Mail / dispatcher / agent actions — PASS
- **Convoy:** 47 = `gc convoy list`; `RET` on `bs-0q2z` opens it scoped via `bd
  --directory` with real content (gce-bhr fixed). Progress column varies correctly
  (4×`0/1`, 43×`1/1`).
- **Order:** 48 = `gc order list`; `RET` opens the source `.toml` (`conf-toml-mode`);
  rig-scoped vs city orders correct.
- **Dolt:** 4 DBs = `gc dolt health`; `RET` echoes "beads: 344 commits".
- **Mail:** clean empty state; `gc mail inbox` resolves to the ambient identity
  gracefully (a non-agent shell resolves to "human" with exit 0 — no error).
- **Dispatcher** `M-x gascity`: transient with all Overview/Lists/Dispatch bindings.
- **Agent actions:** Dired/tmux/peek wired; peek on a stopped agent → clean `user-error`.

### 12. Conventions — PASS except `q`
`g` refresh / `RET` drill-in / `/` filter / `]`/`[`/`G` pagination consistent;
all 5 custom vars bound, all 8 faces defined; error surfaces clean (rig "Could not
load … Press g to retry"; `G` out-of-range `user-error`). The lone convention break is
`q` in the vui views (gce-0d5) — the tabulated lists' `q`→`quit-window` is fine.

## Minor observations (noted, not separately filed — to avoid bead pollution)

- **Doubled command prefix in error messages.** Error surfaces wrap gc's stderr as
  `"gc <sub> failed: <stderr>"`, and gc's stderr usually already starts with
  `"gc <sub>:"`, so e.g. peek on a stopped agent reads `gc session peek failed: gc
  session peek: session not found: …`. Readable, but the prefix repeats. A one-line
  tidy if a maintainer touches `gascity-error-detail`/`gascity-command-act`; folded
  here rather than filed.
- **Agent display-name inconsistency (gc-data origin).** In the status dashboard's
  "City" section, `name` comes through verbatim from `gc status`: dogs show
  `gastown.dog-1` (name == qualified) while boot/deacon/mayor show short `boot`/etc.;
  rig sections likewise mix `gastown.furiosa` with `refinery`/`witness`. The rig
  dashboard instead shows full `qualified_name` + role. Faithful to gc's fields, so
  not filed — but a future polish could normalize display names across views.
- **"controller down" vs "supervisor-managed".** The header says "controller down"
  (faithful to `controller.running:false`), though `gc status` text now renders the
  same state as "supervisor-managed (PID 2155, unknown)". Faithful; not filed.
