# Dashboard v3 — post-fix QA (row expansion, Moving ladders, burningswell)

Date 2026-09-26 · QA agent · gascity.el `main` @ **16e1163** · beads.el
@ **0bef79f** · Emacs 31.1 `-nw` (v3qa restarted on this commit,
byte-compiled, real keystrokes via tmux) · data:
`~/workspace/gascity.el-wt/qa/out/postfix/`.

Cities:
- `~/emacs-city` and `/ssh:localhost:/home/roman/emacs-city` (read only).
- `/ssh:gascity@burningswell.com:/home/gascity/burningswell/`, a real
  remote host, **read only**: no slings, actions or mutations.

| # | Item | Result |
|---|---|---|
| 1 | `+`/`-` row expansion (cockpit, churn unfold, rig dashboard, Runs history), local and ssh | **PASS** (1 low nit) |
| 2 | Moving ladders equal the Runs cards on burningswell, `…` before data | **PASS** (1 low display bug) |
| 3 | All-view smoke on burningswell over ssh | **PASS** |

## 1. `+` / `-` — PASS

emacs-city cockpit, local and over ssh:localhost, point on a row of the
section:

- **Work** (5 shown, `… 34 more  + more  j b beads`):
  - `+` 6 → 16 → 26 rows (`… 24 more`, `… 14 more`); `-` back to 16 and 6.
  - A further `-` echoes **"Already at the default size"**.
  - Point stays on the same row throughout.
- **Activity:** `+` shows the remaining 7 events (fewer than 10 left) and
  drops the more line; `-` restores 5.
- **Churn unfold:** `SPC` on a `×39 wisp created/closed` row shows 20
  events plus `… 19 more  + more  RET j e events`. `+` inside it gives
  +10 (`… 9 more`), `-` gives −10, and the floor message appears.
- **`g` keeps the expansion; `C-u g` resets** every section, including the
  churn extra rows, to defaults.
- **Rig dashboard** (beads.el): `Ready  34  (3 convoy hidden)` is capped
  at 5 plus `… 29 more  + more  b beads`. `+`/`-` step by 10 with the floor
  message. In progress is `none`, so it couldn't be exercised.
- **Runs history** (`H`): 30 lines, `… 43 more  + more`. `+` adds a
  20-row page (50 lines), `-` removes it, and a further `-` gives the
  floor message.
- **Cost:**
  - Commands 0–59 ms; max stall 18–50 ms locally, 42 ms over ssh.
  - Zero TRAMP I/O.
  - **No gc spawned**: the only gc process during `+`/`-` was the
    already-running live `gc events --follow`.

Nit (low): `+` on a section without a cap is silent on **Rigs**, but
echoes "No section with more rows here" on **Agents**.

## 2. Moving vs Runs on burningswell — PASS

- **Cold opens:** 11 in total. 1 right after the v3qa start, 6 after
  `gascity-store-clear` + `tramp-cleanup-all-connections` (4 compared, 2
  state-tracked), and 4 TRAMP-cold opens with the store cache warm.
- **Comparison:** each open compared the Moving section to the Runs view
  (`j r`) for the same run, with a script
  (`out/postfix/cmp.py`). **9/9 comparisons: ALL MATCH.**
  - `bs-0c3f` do-work: `◆⬣·  implement  1/3` in both views.
  - `bs-8jif` build-basic: `◆◆◆◆◆·····  implement  5/10` in both views.
- **Loading order**, sampled every 0.25–0.3 s on store-cold opens:
  - `+0.1 s` Moving header `…`.
  - `+5.6–9.2 s` `2 runs · 1 worker` with each run's ladder shown as `…`.
  - `+8.7–11.0 s` the real ladders.
  - **A wrong count was never displayed.**
- Cockpit on burningswell: sync 7–38 ms, max stall 54–83 ms.

Display bug (low): Moving shows a flat worker row with an **empty agent
name** — `○ <blank>  bs-bidj.1 OIDC 1a: Hydra infrastruc…  1h`. The bead
`bs-bidj.1` is `in_progress` with **no assignee** and no run (no
`gc.root_bead_id`). An unassigned bead isn't a worker; it should be
omitted or labelled "unassigned". The header correctly says `1 worker`.

Observation (low, shared by both views so no mismatch): `bs-8jif`'s label
is `implement` (step 6), but its ladder has no `⬣` active glyph; step 6
renders `·`. The step is gc's `drain` kind, which may not be mapped to
"active".

## 3. burningswell smoke over ssh — PASS

10 views (cockpit, Agents, tree, Runs, Events, Mail, Health, Cities,
costs, rig dashboard `burningswell-cl`):

| | store-cold + TRAMP-cold | warm |
|---|---|---|
| command sync | 3–29 ms | 3–61 ms |
| max main-loop stall | 3–90 ms | 3–62 ms |
| settle | 1.6–10.8 s (cockpit 10.8 s) | 0.6–9.7 s |
| max remote gc | 3 reads + 1 stream | same |
| rows stuck at `…` | **0** | **0** |

Two warm checks (Agents tree, Runs) failed once in the harness: the Dired
prep over the real network didn't return. Both retried twice and passed
(sync 5–9 ms, stall ≤ 45 ms). This was harness-side, not the view.

State: nothing was changed on burningswell or emacs-city. v3qa is idle on
16e1163 with transport `'ssh`.
