# gascity.el — Dogfood QA Report (gce-284)

A **verification** dogfood pass: the counterpart to gce-osd. Where gce-osd (the
third dogfood) *filed* five of the bugs below, this pass confirms the merged
fixes actually work, **interactively against the live Gas Town** at
`/home/roman/bright-lights`. A real Emacs is driven with real keystrokes in a
tmux pane, and state is read back via `emacsclient -e`, cross-checked against
`gc … --json` at the same instant. This is **test + file only** — no porcelain
code was changed; the one new papercut found is a linked follow-up bead.

The brief named six fixes; the description listed **seven** beads (gce-dw4 was
flagged as possibly still merging at dispatch). gce-dw4 is confirmed on
`origin/main`, so all seven were verified.

## Setup

| | |
|---|---|
| Target | `origin/main` @ `803438c` — worktree HEAD is identical to `origin/main` (`git log origin/main..HEAD` empty both ways). All seven fix commits present: gce-4hk `803438c`, gce-0d5 `2491538`, gce-dzs `bda14a5`, gce-79f `ab8bdaa`, gce-6bq `fe30999`, gce-d16 `b657db0`, gce-dw4 `6baf956`. |
| Gate | Byte-compile **clean** (no errors/warnings, `lisp/gascity*.el`); **ERT 101/101 pass** — both run offline against HEAD with the project load-path. |
| Env | GNU Emacs 30.2, tmux 3.6a; deps transient / sesman / vui 1.0.0 + the `beads.el` sibling checkout, all from the Guix-home profile. Terminal backend pinned to built-in `term` so the attach buffer is scrapeable. |
| City | `bright-lights` — controller down (`controller.running:false`) · health degraded (`health.degraded:true`) · 11→10 agents running (live drift mid-pass); tmux socket = city name `bright-lights`. The status header rendered each of these verbatim from `gc status --json`. |
| Method | `emacs -nw -Q -l <harness>` in a dedicated tmux server (`-L furiosa-qa`) running an Emacs server (`-s furiosa-qa`). Driven by **real keystrokes** (`M-x`, `RET`, `i`, `t`, `q`, `S`, `]`, `[`, `d`, `g`) sent to the pane, and by `emacsclient -e` reading buffers / point / keymaps / pagination — cross-checked against `gc … --json` / `gc bd` live. `gascity-tmux-socket` set to `bright-lights` so the attach path targets the live tmux server. |
| Write-side safety | Read-only QA. The only writes to live state: one clearly-named throwaway tmux session (`qa-attach-target`) created **and killed** on the `bright-lights` socket to exercise attach/reuse without touching any real agent, and one follow-up bead (`gce-a8d`). No live agent was attached to; no destructive town mutation fired; no porcelain changed. |

## PASS / FAIL matrix — the seven fixes

| Bead | Fix | Verdict |
|------|-----|---------|
| `gce-4hk` | RET attaches an agent's terminal; `i` opens its info view; `t` attaches; re-RET reuses the buffer | **WORKS** |
| `gce-0d5` | `q` buries in the vui views (status / rig / session-detail) — no "Text is read-only" | **WORKS** |
| `gce-dzs` | tabulated lists sort across the **full** paged dataset (default + `S`), spanning page boundaries | **WORKS** |
| `gce-79f` | rig list bead-store column titled **"Store"**, not "Beads" | **WORKS** |
| `gce-6bq` | RET on the HQ rig (`bright-lights`) refuses cleanly instead of dead-ending | **WORKS** |
| `gce-d16` | timestamps show `HH:MM` (session-detail "last active", mail "Date") | **WORKS** |
| `gce-dw4` | agent-detail "Recent history" lists recent **closed** beads for a productive polecat | **WORKS** |

**Net: 7/7 fixes verified working.** Re-swept dashboard / navigation / dired /
lists / detail for regressions from the seven changes — **none found**. One
adjacent usability papercut surfaced by gce-dzs is filed as `gce-a8d` (P3).

## Detail — each fix

### gce-4hk — RET attaches, `i` info, `t` attaches, re-RET reuses — WORKS
Runtime keymaps in all three agent views:

| Mode | `RET` | `i` | `t` |
|------|-------|-----|-----|
| `gascity-dashboard-mode` (status) | `gascity-status-activate` → on an agent: `gascity-tmux-at-point` | `gascity-polecat-detail-at-point` | `gascity-tmux-at-point` |
| `gascity-rig-dashboard-mode` | `gascity-rig-dashboard-activate` → on an agent: `gascity-tmux-at-point` | `gascity-polecat-detail-at-point` | `gascity-tmux-at-point` |
| `gascity-session-list-mode` | `gascity-tmux-at-point` (direct) | `gascity-polecat-detail-at-point` | `gascity-tmux-at-point` |

- **At-point resolution on live data:** on the refinery row in the gascity.el
  rig dashboard, `gascity-agent-at-point` → `:session-name
  "gascity__el--gastown__refinery"`, `:socket "bright-lights"` — RET there would
  attach the real session.
- **`i` opens the detail live:** `i` on the session-list row opened
  `*gascity-agent: example-town-cl/gastown.furiosa*`.
- **Attach + reuse (the gce-952 path RET inherits), end-to-end:** against a
  controlled `qa-attach-target` session on the live `bright-lights` socket —
  first `gascity-agent-attach-tmux` spawned `*gc-agent-qa-attach-target*`
  running `env -u TMUX tmux -L bright-lights attach-session -t qa-attach-target`
  (live process; terminal showed the target's shell). Re-invoking on the same
  target: **`error=nil`, same buffer reused, still one process** — no "already
  has a running process".
- **Regression guard:** RET on a rig **header** (a widget) still toggles
  collapse (`▼ gascity.el` ⇄ `▶ gascity.el`, bidirectional), not attach; RET on
  a **bead** still routes to beads.el (dispatcher `cond` order intact). RET on a
  real rig opens its dashboard (see gce-6bq).

### gce-0d5 — `q` buries the vui views — WORKS
`q` → `quit-window` in `gascity-dashboard-mode`, `gascity-rig-dashboard-mode`,
and `gascity-session-detail-mode` (all inherit it from `gascity-section-mode-map`).
Live keystroke: `q` in the rig dashboard and in the session detail both buried
the buffer (selected window returned to the prior buffer), with **no
"read-only" error** in `*Messages*`. The vui content is read-only via text
properties (`buffer-read-only` is nil), which is exactly why the old self-insert
fallback errored — `q`→`quit-window` sidesteps it. (Covered by ERT
`gascity-test-vui-q-buries`.)

### gce-dzs — sort spans the full paged dataset — WORKS
On the order list (48 entries), forcing a 5-row page (10 pages):
- **Default sort** (`("Order")` ascending): walking all 10 rendered pages, the
  concatenated "Order" sequence is **globally ascending** — page 1 ends
  `cross-rig-deps:rig:example.city`, page 2 begins `digest-generate` (monotonic
  across the boundary), last row `wisp-compact:rig:example.city`. Not per-page.
- **`S` keystroke** (point on the Order column): toggled to descending
  (`("Order" . t)`), **returned to page 1**, page 1 now leads with the **global
  max** `wisp-compact:rig:example.city`, and the full 10-page sequence is globally
  descending (boundary monotonic). `S` is bound to `gascity-tabulated-sort` on
  every paged list.
- **Pagination intact:** on convoys (54 entries), `]`→page 2 (`bs-vrme`),
  `[`→page 1 (`bs-0dca`).

### gce-79f — rig list "Store" column — WORKS
`tabulated-list-format` headers = `(Name Prefix Status Branch Store)` — "Store"
present, "Beads" absent. Cell renders the `beads` field's status string
(`initialized`) for all four rigs, faithfully.

### gce-6bq — RET on the HQ rig refuses cleanly — WORKS
On the `bright-lights` row (`hq=t`, `gascity-rig-at-point-hq-p`→t), `RET`
signalled: *"bright-lights is the city HQ, not a rig — no rig dashboard; use M-x
gascity-status, or `b` for its beads"* — **no dashboard buffer created, no
dead-end**, buffer stays the rig list. Guard doesn't break the normal path: RET
on `gascity.el` opened `*gascity-rig: gascity.el*` (7 agents, Ready/In-progress,
Orders, Dolt sections).

### gce-d16 — `HH:MM` timestamps — WORKS
- `gascity-tabulated--format-timestamp`: `…T15:30:20Z`→`2026-06-02 15:30`,
  `…+02:00`→`2026-06-02 17:35`, date-only preserved, empty→empty.
- **Mail "Date":** column width widened to 16; the entry function builds the
  cell from the formatter — a real-shaped `mail_message` renders
  `2026-06-02 16:34`. (Every live inbox in the town is empty, so the cell was
  verified through `gascity-mail-inbox--entry` itself.)
- **Session-detail "last active":** rendered `2026-06-02 18:50` (furiosa) and
  `2026-06-02 18:56` (mayor) — live, with the time. The formatter is used in
  exactly these two places, so there is **no truncation regression** in the
  other lists (none have a timestamp column through it).

### gce-dw4 — handed-off history recovered — WORKS
The detail for the productive polecat `example-town-cl/gastown.furiosa` lists
**"Recent history (10)"** — ten **closed** beads (`bs-xt6`, `bs-fxf`, `bs-9bf`,
…). Mechanism confirmed: `bs-xt6` is `status=closed`, `assignee=
example-town-cl/gastown.refinery` (handed off — would **not** match by
assignee), yet appears because its `metadata.work_dir`
(`…/worktrees/example-town-cl/polecats/gastown.furiosa`) nests under furiosa's
worktree — exactly the durable signal the gce-dw4 read recovers. (gce-osd saw
this list empty before the fix.) Robustness: a service agent with no polecat
worktree (`gastown.mayor`) renders fine — "On hook (0) idle", history-by-assignee
intact, no error.

## Regression re-sweep — clean

| Area | Result |
|------|--------|
| Status dashboard | Renders city→rig→agent tree; header matches `gc status --json`; rig headers toggle (bidirectional); agent rows carry `gascity-agent` (RET→attach); `g` refresh works; `n`/`p`/TAB standard. |
| Rig dashboard | Renders 6 sections live; RET on real rig opens; RET on bead→beads.el; agent at-point resolves. |
| Session list / detail | RET→attach, `i`→detail, `d`→Dired; detail renders for productive **and** service agents. |
| Rig list | "Store" column; RET on HQ refuses, on real rig opens; `S`/`/`/`g`/`q` bound. |
| Lists (order/convoy/dolt/mail) | All render; untouched RET bindings intact (`convoy-list-visit`, `order-list-visit`, `mail-inbox-show`, `dolt-list-show`); `]`/`[` paging works; `S`→`gascity-tabulated-sort` uniformly; `q`→`quit-window`. |
| Dired | `d` on an agent opened `dired-mode` on its worktree. |
| Build/test | byte-compile clean; ERT 101/101. |

gce-4hk's RET change is correctly scoped to the three agent views only — the
other lists' RET bindings are unchanged. gce-dzs's per-refresh sort is a no-op
when no sort key is active (mail) and gracefully refuses an invalid column
(state left intact). No regression observed in any area.

## New follow-up filed (linked `discovered-from: gce-284`, labels `qa`,`dogfood`,`tabulated`)

| Bead | Type | Pri | Title |
|------|------|-----|-------|
| `gce-a8d` | bug | P3 | gascity tabulated `S`-sort: "Cannot sort by nil" from the default (padding) cursor column |

**gce-a8d detail.** All gascity tabulated lists set `tabulated-list-padding = 1`,
so column 0 of every row is a 1-char margin with no `tabulated-list-column-name`.
Point rests at column 0 after a list opens, and `n`/`p` preserve goal-column 0,
so pressing the advertised `S` from the natural cursor position yields a cryptic
*"Cannot sort by nil"* (from the built-in `tabulated-list-sort` that
`gascity-tabulated-sort` delegates to) until the user moves point right onto a
data column. This is **not** a failure of gce-dzs — sorting works correctly once
point is on a column — but gce-dzs elevates `S` to a primary documented action,
so the inherited papercut is now visible on the advertised key. Suggested fix:
in `gascity-tabulated-sort`, fall back to the `tabulated-list-sort-key` column
when point carries no column-name and no prefix is given.

## Minor observations (noted, not filed — to avoid bead pollution)

- **"controller down / health degraded"** in the status header is **faithful**
  to live `gc status --json` (`controller.running:false`, `health.degraded:true`)
  — a real town condition, not a gascity defect. The agent count drifted
  11→10 between opening the dashboard and a later `gc` cross-check (live data,
  `g` re-fetches) — expected, not a staleness bug.
- **Attach terminal shows the tmux status bar.** The `*gc-agent-*` buffer
  includes the attached session's tmux status line — already tracked by the
  in-progress gce-hjj ("hide the tmux status bar"); not re-filed.
