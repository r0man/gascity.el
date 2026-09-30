# Dogfood run report — bright-lights (rw), 2026-09-30

Triage of the `gascity-dogfood` run. Target city `/home/roman/bright-lights`,
mode **rw** (full-user operations), 20 min wall clock, report cadence 10 min,
anti-flood cap 5 issues.

## Setup

| Item | Value |
| --- | --- |
| Run epic | `ga-94fvy` (open) |
| Workflow bead (formula `gascity-dogfood`, graph.v2) | `ga-qm276` |
| Setup-epic bead | `ga-b7a9q` (closed, `gc.outcome=pass`) |
| Dogfood step bead | `ga-cushb` (closed, `gc.outcome=pass`) |
| Wrap-up step bead | `ga-klg0w` |
| Worktree under test | `/home/roman/workspace/gascity.el/worktrees/gc-dogfood-20260930-rw` @ `750a55c` (= `origin/main`) |
| Emacs | `emacs -nw -Q` in tmux, own server socket `gce-e2e-rw`; gascity.el + `~/workspace/beads.el/lisp` + bundled vui on `load-path` |
| Session log | `worktrees/gc-dogfood-20260930-rw/SESSION-LOG.org` |

Run wall clock ~19:40Z–20:02Z. The setup step adopted the existing run worktree
and epic `ga-94fvy` (no second epic created). Two situation reports were mailed
to the emacs-city mayor during the run; this report is the final summary.

## What was exercised

Checklist from the session log (`SESSION-LOG.org`), read + full-user (`rw`)
navigation:

| View / action | Key | Result |
| --- | --- | --- |
| Cockpit (status) | `j` | PASS — agents 1/5 running, sessions 2, ready 12, dolt ~256 MB, mail 6 unread, supervisor ok |
| Agents list | `j a` | PASS — mayor (active) + core.control-dispatcher (idle); rig "—" |
| Runs | `j r` | PASS — header 0 active / 6 waiting / 29 done / 3 failed; "Active" section lists waiting 0-progress rows (see nit) |
| Events | `j e` | PASS — 1044 events/2 h, churn folded (1035); order.fired/completed bursts every ~15 min |
| Mail | `j m` | PASS — 6 unread: 1 HIGH "ESCALATION: JSONL spike detected", 5 MEDIUM "Dolt health advisory" |
| Health | `j h` | PASS — supervisor pid 15438 ok, gc 1.4.2 NativeDoltStore, dolt :41586 22 ms, 2 databases |
| Cities | `j c` | PASS for listing (rows fill async) — bright-lights 1/5 runs 0 mail 6; emacs-city 2/7 |
| Dolt | `j D` | PASS — hq 645 commits, hw 1002 commits |
| Convoys | `j v` | PASS — bl-106, bl-35p, bl-3bhn, bl-5x3, bl-b9u, bl-ej6a (6 open) |
| Rig dashboard | `j g` → bright-lights | **FAIL** — `gc rig status` exit 1; see finding `ga-94fvy.1` |

Non-findings / confirmations (deliberately **not** filed):

- Runs "Active" heading contains waiting (0-progress) rows rather than running
  ones. Same labeling nit as the ro run (`ga-ns592`), cosmetic.
- `j g` rig-picker minibuffer: neither hex `0d`, the `Enter` token, nor `C-m`
  submitted the prompt (`C-g` did quit), and an emacsclient eval during the
  active minibuffer blocked ~60 s. Could be a tmux key-delivery artifact or a
  real minibuffer bug; needs a clean repro before filing. Worked around by
  calling `gascity-rig-dashboard` via emacsclient.

City-health observations (belong to the bright-lights owner, not gascity.el):

- 6 `pancakes` runs waiting ~3 days at 0/5 progress.
- 1 HIGH "JSONL spike" escalation + 5 Dolt health advisories unread in mail.
- Heavy `order.fired`/`order.completed` churn (hundreds per burst every ~15 min).
- Dolt store growth: ~159 MB (ro run) → ~256 MB (rw run), ~1.6x in ~25 min.

## Findings filed

One issue, under the run epic:

- **`ga-94fvy.1`** (bug, P2, labels `dogfood` `gc-bug`, parent `ga-94fvy`) —
  *`gc rig status` rejects the hq city rig that `gc rig list` returns; the rig
  dashboard for it fails (exit 1).*

Triage:

- **Real** — reproduced outside Emacs against the live city:
  `gc --city /home/roman/bright-lights rig list --json` advertises
  `bright-lights` (`hq: true`), while
  `gc --city /home/roman/bright-lights rig status bright-lights --json` exits 1
  with `rig "bright-lights" not found in city.toml; available rigs: hello-world`.
  `rig list` treats the city hq as a rig; `rig status` does not. The gascity.el
  dashboard surfaces only "command failed; see stderr for diagnostics (exit 1)"
  with no gc error line, so the failure is opaque to the user.
- **Deduped** — searched open beads in both rigs (gascity.el `ga`, beads.el
  `be`); no existing open bead covers this defect (the only rig-status hit is
  `ga-94fvy.1` itself). Unrelated capability beads `ga-ik26`/`ga-jcv1` do not
  overlap.
- **Routed correctly** — gc CLI defect → gascity.el rig, label `gc-bug`;
  parent link to `ga-94fvy`.
- **Severity honest** — P2/bug: functional (rig picker offers a target whose
  dashboard cannot load, with a silent reconnect spinner), no data loss.

## Findings NOT filed

- Minibuffer submit failure on the rig-picker prompt (above) — not reproducible
  under controlled conditions; needs a clean repro first.
- Runs "Active" heading labeling nit (above) — cosmetic.
- City-health observations (stale runs, JSONL spike, Dolt advisories, order
  churn, store growth) — the target city's operational state, not a gascity.el
  defect.
- No further capability gap reached the filing bar; the run stayed under the
  cap of 5 (1 filed).

## Improvement suggestions

- **Rig list vs. rig status**: make `gc rig status` accept the hq/city name that
  `gc rig list` advertises, or stop advertising the hq as a selectable rig; if
  neither, gascity.el should not offer it as a dashboard target.
- **Rig dashboard errors**: surface gc's actual stderr/error line instead of the
  generic "(exit 1) + g retry", and stop the live `connecting`/`reconnecting`
  spinner on a terminal failure.
- **Runs header**: separate waiting (0-progress) from active runs so the
  "Active" count means what it says.

## Capability gaps

None beyond `ga-94fvy.1`. The rig picker offers a rig the dashboard cannot load,
and the dashboard gives no actionable error to distinguish "bad target" from
"city unreachable".

## Run verdict

- Issues filed: 1 → run epic `ga-94fvy` stays **open**.
- `ga-94fvy.1` verified: real, deduped, correctly routed, honest severity, linked.
