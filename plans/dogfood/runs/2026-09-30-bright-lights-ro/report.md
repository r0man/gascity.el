# Dogfood run report — bright-lights (ro), 2026-09-30

Triage of the `gascity-dogfood` run. Target city `/home/roman/bright-lights`,
mode **ro** (read-only observation), 20 min wall clock, report cadence 10 min,
anti-flood cap 5 issues.

## Setup

| Item | Value |
| --- | --- |
| Run epic | `ga-4hvvi` (open) |
| Duplicate epic (setup retry, closed) | `ga-ns592` |
| Workflow bead (formula `gascity-dogfood`, graph.v2) | `ga-yt3xd` |
| Setup-epic bead | `ga-vepiv` |
| Dogfood step bead | `ga-zabsp` (closed, `gc.outcome=pass`) |
| Wrap-up step bead | `ga-sdwgj` |
| Worktree under test | `/home/roman/workspace/gascity.el/worktrees/gc-dogfood-20260930` @ `0826b28` (= `origin/main`) |
| Emacs | `emacs -nw -Q` in tmux, own server socket `gce-dogfood`; gascity.el + `~/workspace/beads.el/lisp` + bundled vui on `load-path` |
| Session log | `worktrees/gc-dogfood-20260930/SESSION-LOG.org` |

The setup step ran twice (the first session dropped mid-step), creating two
epics; the retry closed its duplicate `ga-ns592` and kept `ga-4hvvi`. Situation
reports were mailed to the emacs-city mayor every ~10 min (2 reports); no final
report was sent before wrap-up, hence this one.

## What was exercised

Checklist from the session log (`SESSION-LOG.org`), read-only user navigation:

| View / action | Key | Result |
| --- | --- | --- |
| Cockpit (status) | `j` | PASS — agents 2/5, sessions 2, runs 0, ready 12, mail 6 unread, dolt ~160 MB; needs-you surfaced unread mail |
| Agents list | `j a` | PASS — mayor + core.control-dispatcher, rig "—", active |
| Runs | `j r` | PASS — header 0 active / 6 waiting / 29 done / 3 failed; see nit below |
| Events | `j e` | PASS — 496 events/2 h, churn folded, order.fired/completed bursts |
| Mail | `j m` | PASS — 6 unread (1 HIGH escalation, 4–5 MEDIUM Dolt advisories) |
| Health | `j h` | PASS — supervisor ok, gc 1.4.2 NativeDoltStore, dolt 42 ms |
| Cities | `j c` | PASS for listing (rows fill async); **FAIL for its jump suffixes** → filed |
| Convoys | `j v` | PASS — 6 convoys |
| Orders | `j o` | PASS — beads-health, dolt-health, gate-sweep, … |
| Dolt | `j d` | PASS — hq 645 / hw 1002 commits |
| Beads | `j b` (rig hello-world) | PASS — delegates to beads.el dashboard (Open 6 / Closed 190) |
| Filter menu on cockpit | `/` | PASS — Noise/Scope/Activity toggles + reset |
| Refresh | `g` | PASS |

Non-findings / confirmations (deliberately **not** filed):

- From a real city context every view loaded correctly (convoy, order, mail,
  beads, health, events, dolt).
- `RET` drill-in from the Cities list opens the cockpit correctly
  (`gascity-cities-visit`).
- `j g` / `j b` prompt for a rig; `j b` correctly delegates to beads.el.
- Runs "Active" heading contains waiting (0-progress) rows rather than running
  ones. A labeling nit, not a defect.

City-health observations (belong to the bright-lights owner, not gascity.el):

- 6 `pancakes` runs waiting ~3 days at 0/5 progress.
- 1 HIGH "JSONL spike" escalation + several Dolt health advisories in mayor mail.
- Heavy `order.fired`/`order.completed` churn (hundreds per burst).

## Findings filed

One issue, under the run epic:

- **`ga-4hvvi.2`** (bug, P2, labels `dogfood` `gc-bug`, parent `ga-4hvvi`) —
  *Cities view: `j`/`?` jumps open contextless `: city` views that fail gc reads
  and spin "connecting".*

Triage:

- **Real** — root cause confirmed in `lisp/gascity-cities.el`: the buffer is
  created with `default-directory` = local home
  (`gascity-view-get-buffer-create … (gascity-cities--local-home)`), while
  `?`/`j` are inherited from `gascity-tabulated-base-map`
  (`gascity-thing-define-keys`) and run city-scoped commands against that nil
  city. Reads then run with no `--city` and cwd `/home/roman/`, exiting 1, and
  the live indicator loops `connecting` → `reconnecting`.
- **Deduped** — searched open beads in both rigs (`gascity.el` prefix `ga`,
  `beads.el` prefix `be`); no existing open bead covers this defect.
- **Routed correctly** — gascity.el UI bug → gascity.el rig, label `gc-bug`;
  parent + `Discovered-from: ga-4hvvi` link the epic.
- **Severity honest** — P2/bug: functional (jump keys yield broken views and a
  silent infinite spinner), no data loss.

## Findings NOT filed

- Runs "Active" heading labeling nit (above) — cosmetic.
- City-health observations (stale runs, JSONL spike, Dolt advisories, order
  churn) — the target city's operational state, not a gascity.el defect.
- No capability gap reached the filing bar beyond the bug above; the run stayed
  under the cap of 5 (1 filed).

## Improvement suggestions

- **Cities list**: make `j`/`?` either target the city at point (as `RET` via
  `gascity-cities-visit` does) or be removed there with a clear "no city
  selected — `RET` to open one" message. At minimum, surface the failed read and
  stop the live `connecting` spinner instead of looping.
- **Runs header**: consider separating waiting (0-progress) from active runs so
  the "Active" count means what it says.

## Capability gaps

None beyond `ga-4hvvi.2`: the Cities list has no way to act with a per-row city
context for the inherited city-scoped jump keys.

## Run verdict

- Issues filed: 1 → run epic `ga-4hvvi` stays **open**.
- `ga-4hvvi.2` verified: real, deduped, correctly routed, honest severity, linked.
