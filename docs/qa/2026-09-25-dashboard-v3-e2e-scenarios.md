# Dashboard v3 — §8.4 e2e scenarios and formula sling over TRAMP

Date 2026-09-25 · QA agent · gascity.el `main` @ **6eb28ee** · beads.el
@ badee17 · v3qa (restarted on this commit) · remote city
`/ssh:localhost:/home/roman/bright-lights` · data:
`~/workspace/gascity.el-wt/qa/out/s84/`.

## Re-verified fixes

- **Acceptance #2** (agent detail listed bookkeeping session beads): the
  mayor's Work and History are `none`. FIXED.
- **Acceptance #1** (Mail misses external read state), using a freshly sent
  message `bl-wisp-mie2jt`: an external `gc mail mark-read` shows in the
  inbox in 4.1 s, and `mark-unread` in 4.2 s (budget 5 s). FIXED. The
  message is restored to read.

## §8.4 scenarios — all PASS

**1. Stream kill → resume, no missed seq.**
- With the remote cockpit live, I killed only this Emacs's host-side
  `gc events --follow` (matched by start time; other agents' streams
  survived).
- About 10 s later the stream respawned as
  `events --follow --after 84672 --city …`.
- Events delivered to Emacs (advice on `gascity-live--deliver`) compared
  with `gc events --since`: seq 84658–84699, gc 42, Emacs 42, **0 missed,
  0 duplicates**. The 4 events from the gap arrived in one batch.
- Max stall 144 ms.
- Nit: the header stayed `● live` during the ~10 s gap and never showed
  `○ live: reconnecting`.

**2. `ssh -O exit` on the gascity/beads master** (`/tmp/beads-ssh-%C`).
- The stream reconnected on its own within ~9 s (`--after 84718`); seq
  84719… delivered with no gap. Max stall 45 ms.
- The host stayed reachable, so no read failed and the header stayed
  `● live`.
- The offline path (`kill -9` on the master mid-read) was verified on
  bc6d6ba: `○ offline @localhost` for 16 s, then `● live`, max stall 60 ms.

**3. Contention** (remote cockpit live, then Agents, Runs and Health opened
back to back with no wait; 3 runs):

| Run | max stall | commands | TRAMP I/O | max remote gc | settle |
|---|---|---|---|---|---|
| 1 | 46 ms | 22 / 3 / 3 ms | 0 | 3 + stream | 4.3 s |
| 2 | 46 ms | 2 / 1 / 30 ms | 0 | 3 + stream | 4.4 s |
| 3 | 49 ms | 3 / 2 / 5 ms | 0 | 3 + stream | 5.3 s |

Budget < 200 ms: met.

## Formula sling over TRAMP (CLAUDE.md e2e protocol) — PASS, with a workaround

- **Formula:** bright-lights' own `e2e-demo`. It has one workflow-latch
  step, the control lane advances it, and no agent session is spawned.
  Every catalog formula (build-basic, implement, review, …) would spawn
  real agent work.
- **Steps:** remote cockpit → `S` → `-f e2e-demo` → `ot` note =
  `qa-v3-acceptance` → `-T mayor`.
  - `p` Preview (dry-run) buffer: `gc sling mayor e2e-demo --formula`,
    "Would run: gc formula cook e2e-demo … No side effects executed".
  - `s` → "GC sling: ok"; the command returned in 34 ms.
- **Store:** root `bl-en7g`, `gc.kind=workflow`,
  `gc.var.note=qa-v3-acceptance`, `gc.routed_to=mayor`, in_progress. Steps:
  `bl-8tfn` "e2e demo latch — qa-v3-acceptance" and `bl-47sd`
  workflow-finalize. No new agent session was created.
- **Cleanup:** all three beads closed, and the formula file restored.

**Workaround needed** (bug S-1 below): `e2e-demo` isn't offered by the
picker. For the pass, I temporarily added a `[catalog]` block to
`bright-lights/formulas/e2e-demo.formula.toml` (backup in
`qa/out/s84/`) and removed it afterwards (`gc formula catalog` no longer
lists it).

## Bugs

### S-1. Medium: the sling formula picker offers only `gc formula catalog`, so city-local formulas can't be slung

`gc formula catalog` lists only formulas with a `[catalog]` opt-in (13 pack
formulas). `gc formula list` shows 44, including the city's own `e2e-demo`
and `e2e-demo-on`. The `-f` prompt requires a match, so `e2e-demo` is
rejected; the 2026-09-24 dogfood pass could still sling it. Suggest
offering `gc formula list` (or marking non-catalog formulas) in the picker.

### S-2. Medium: the sling transient forgets its state after Preview, and a following `s` becomes a plain sling

`p` (dry-run) closes the transient. Reopening `S` shows `Formula: (none) ·
Target: (none)`: formula, target and vars are gone. Pressing `s` then
prompts "Bead id or task text:" — a plain sling. A user who previewed and
then pressed `S s` would dispatch something other than what they
previewed. I aborted with C-g; nothing was sent. Suggest keeping the state
per city (as the filters do) or returning to the transient after preview.

### S-3. Low: no `reconnecting` header state during a stream gap

It stayed `● live` for the ~10 s between the stream's death and its
respawn.
