# Dogfood run report — 2026-10-16 — /home/roman/bright-lights (ro)

- **Workflow:** `gascity-dogfood` root `ga-mkx99`, dogfood step `ga-teg3x`,
  setup step `ga-jdpur`, wrap-up `ga-3v5us`.
- **Run epic:** `ga-4mvlw` (created by the setup step).
- **Session:** `gascity.el/gc.implementation-worker-1` (`ec-wisp-z0b7po`).
- **Window:** ~09:57–10:10 CEST, 2026-10-16 (started late in the 30 min budget;
  the substantive pass below is the recorded result).
- **gascity.el:** `origin/main` @ `2b1bba0`, worktree
  `worktrees/gc-dogfood-20261016-ro`.
- **City:** local `/home/roman/bright-lights` (HQ `bright-lights` + `hello-world`).
- **Mode:** ro (read-only observation). Issue cap: 5 (2 filed).

## Setup

A non-graphical Emacs (`emacs -nw -Q`) on its own tmux server
`gc-dogfood-20261016`, session `gc-dogfood-20261016-ro`, loading gascity.el from
the run worktree plus `~/workspace/beads.el/lisp` and its bundled vui 1.4.0
(`.dogfood-init.el`). City env anchors (`GC_*`, `BEADS_*`) were unset so the UI
resolved the city from each buffer's `default-directory` — a real user
environment. The worktree itself has no `city.toml`; views were opened with
`default-directory` bound to the city, as a user visiting a city file would.
The target city is local `/home/roman/bright-lights` (rigs HQ + `hello-world`).

## What was exercised

Checklist from the raw log (`SESSION-LOG.org`), read-only navigation:

| View / action | Key | Result |
| --- | --- | --- |
| Cockpit (status) | `j j` | PASS — `▲ degraded (agent_state_unknown)`, agents 1/5, sessions 3, runs 0, ready 12, mail ▲8; `g` live refresh works |
| Needs-you store row | — | PASS with residual — store-health label is single (ga-jqt9q.1 fixed); `list timed out: context deadline exceeded` still fires (backend, not filed) |
| Agents section folds | `SPC` | PASS — `▸ stopped bd.dog-1 · bd.dog-2` |
| Agents list | `j a` | **FAIL** — Active column `1970-01-01` for the control-dispatchers (→ `.1`) |
| Runs | `j r` | PASS — `0 active · 7 waiting · 30 done · 3 failed`, explicit `Active none` (ga-jqt9q.2 verified) |
| Events | `j e` | PASS — churn folded (`order.fired/completed ×161`, `wisp ×36`); `order.failed order-tracking-sweep: context deadline exceeded` |
| Mail | `j m` | PASS — 8 unread, paging reaches the 2 older; matches `gc mail count` |
| Health | `j h` | PASS — supervisor pid 3288 degraded; gc 1.5.0 / BdStore; store ◐ single label; `Rig stores 1` (HQ excluded by design) |
| Cities | `j c` | PASS — bright-lights `1/5 ▲8`, emacs-city `3/7 ▲7` |
| Rigs | `j l` | PASS — bright-lights (bl, running), hello-world (hw, stopped) |
| Rig dashboard hello-world | — | PASS — 1 running, Ready 3 (5 convoys hidden); HQ asks a clear user error |
| Orders / Convoys / Dolt | `j o` / `j v` / `j d` | PASS — 5 orders, 10 open convoys, dolt placeholder |
| Costs | `j $` | PASS — 16 runs, `INVOCATIONS 0` explicitly annotated (ga-jqt9q.3 verified) |
| Beads delegation | `gascity-rig-beads` | PASS — hello-world Open 9; city branch Open 45; `gascity-bead-show "bl-bdj"` scoped correctly |
| Mail thread | RET | PASS — read-only thread buffer |
| Emacs-city cockpit | — | PASS — agents 3/7, `ga-mkx99 dogfood 1/3`, SITREP activity visible |
| Cockpit Rigs HQ row | — | **FAIL** — reads `0/0 agents` while the header counts city-level agents (→ `.2`) |
| Agent detail (control-dispatcher) | `i` | **FAIL** — `last active 1970-01-01`; Transcript dead: no session_key + ambiguous workdir (→ `.1`) |
| Sling transient | `S` | PASS (ro) — opens; `f` formula catalog lists; aborted with `C-g`, no mutation |

All views rendered against bright-lights; store/SWR behaviour held (`● live`,
repaint on the 2.5 s batch).

## Actions taken

ro mode: **no mutating gc command was completed.** The sling transient was
opened and aborted; no bead work, mail, or city state was changed. Three
SITREPs were mailed to the emacs-city mayor (`ec-wisp-xce3s2`,
`ec-wisp-3rmtuy`, final).

## Findings filed (2 of 5 cap), under epic `ga-4mvlw`

| id | pri | type | labels | title |
|---|---|---|---|---|
| `ga-4mvlw.1` | P3 | bug | dogfood, gc-bug | gc control-dispatcher sessions: 1970 timestamps, no session_key, transcript fails (ambiguous workdir) |
| `ga-4mvlw.2` | P4 | task | dogfood | Cockpit Rigs: city HQ row reads 0/0 agents while the city has running agents |

### Triage verification

- **Real** — both are reproduced by pane captures in `SESSION-LOG.org`; `.1` is
  corroborated outside Emacs (`gc session list --json` returns
  `created_at 1970-01-01T00:04:56Z`, `session_key null`; `gc session logs`
  reproduces the ambiguous-workdir failure). `.2` describes a wrong count in
  `gascity-dashboard--rigs-lines` (city-level agents carry no `:rig`, so the HQ
  row always shows 0/0).
- **Deduped** — searched OPEN beads in both rigs: the gascity.el rig had 10 open
  beads (none matched either finding) and the beads.el rig store is empty
  (`gc --rig beads.el bd list` → `[]`). The nearest prior bead, `ga-jqt9q.4`
  (cockpit Rigs omits HQ), is the predecessor of `.2`, not a duplicate — `.2` is
  the remaining count-semantics follow-up.
- **Routed** — both live in the gascity.el rig under the epic. `.1` is a
  gascity.el/gc-CLI defect and carries `gc-bug`. `.2` is a presentation/count
  defect filed as a `task`/improvement with `dogfood` only — consistent with
  how the prior run classified the HQ-row follow-up (`ga-jqt9q.4`, feature, no
  `gc-bug`).
- **Severity honest** — `.1` P3 (city-independent: every control-dispatcher in
  every city renders 1970 dates and a permanently dead transcript), `.2` P4
  (cosmetic count mismatch; the per-rig rows and header are correct).
- **Linked** — both are parent-child children of `ga-4mvlw`.

## Already-fixed regressions verified live (from `ga-jqt9q`)

- `ga-jqt9q.1` — store-health label rendered once.
- `ga-jqt9q.2` — Runs `Active`/`Waiting` split matches the summary.
- `ga-jqt9q.3` — zero-usage cost rows annotated.
- `ga-jqt9q.4` — cockpit Rigs includes the HQ row (its count semantics remain,
  now tracked as `ga-4mvlw.2`).

## Findings NOT filed

- **Store-health `list timed out: context deadline exceeded`** — recurs but is an
  environmental/backend condition on this busy city, already represented by the
  store-health work; not a new defect.
- **Transient agent-count differences** (`1/6` vs `1/5`) — resolved to live
  session churn; both views use the same counter. Not reproducible.
- **Health `Rig stores 1` omits HQ** — by design (the `hq` flag in
  `gascity-health--rig-names`).
- **Non-interactive prompt blocking** — `emacsclient -e` on a prompting verb
  (e.g. programmatic `j b`) wedges at the minibuffer until `C-g`. Harness
  guidance, not a product defect.
- **Harness artifact** — `emacsclient --eval` returns elisp-escaped strings; used
  a write-region dump helper for readable pane text.
- Over cap: none (2 of 5).

## Improvement suggestions

- **gc (`.1`)** — record real `created`/`last_active` and a `session_key` (or a
  stable workdir) for control-dispatcher sessions so `gc session logs`/the
  transcript resolve. Barring that, render `unknown`/`—` for epoch timestamps in
  the UI rather than `1970-01-01`.
- **Cockpit Rigs (`.2`)** — label the HQ row as the city (e.g. `emacs-city (HQ)`)
  and either count city-level agents there or omit the `N/M` column for it; keep
  the per-rig rows unchanged.

## Capability gaps

- The session transcript for control-dispatcher agents is unreachable through the
  UI because gc reports no `session_key` and an ambiguous workdir — filed as
  `.1`. No other capability gap was hit; ro mode intentionally did not exercise
  sling/watch-run.

## Deliverables

- `plans/dogfood/runs/2026-10-16-bright-lights-ro/report.md` (this file).
- `SESSION-LOG.org` (raw run log, in the run worktree
  `worktrees/gc-dogfood-20261016-ro`).

## Run verdict

- Issues filed: 2 → run epic `ga-4mvlw` stays **open**.
- `ga-4mvlw.1` and `ga-4mvlw.2` verified: real, deduped, correctly routed, honest
  severity, linked to the epic.
