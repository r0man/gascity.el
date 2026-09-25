# Dashboard v3 — acceptance re-check on bc6d6ba

Date 2026-09-25 · QA agent · gascity.el `main` @ **bc6d6ba** · beads.el
@ badee17 · v3qa (restarted on this commit) · data:
`~/workspace/gascity.el-wt/qa/out/final/`. Follows
`2026-09-25-dashboard-v3-acceptance.md` and
`2026-09-25-dashboard-v3-cockpit-live.md`.

## Fixed and verified

| Issue | Now |
|---|---|
| cockpit #1 render stalls | `g` 37 ms (was 321–845), SPC 0–3 ms (was 117–150), warm open 20 ms sync / 48 ms stall. ssh master killed mid-read: max stall 60 ms (was 2.9 s), offline 16 s then `● live` |
| cockpit #5 `M` nudge block | RET 7 ms (was 898) |
| cockpit #6 Needs-you pool noise | one row, `■ session bd.dog cold start timeout ×7` |
| cockpit #7 agent count | `agents 0/6` agrees with the Agents section |
| cockpit #8 event drawer | key/value lines, nested `{8 fields}` |
| cockpit #9 churn unfold | capped (+21 lines) |
| cockpit #10 `?` | has `j $ costs` and `● live` |

## Passed (new coverage)

- **tmux attach `t`**, local and ssh: 1 ms command, stall ≤ 10 ms, zero
  TRAMP I/O; the remote argv is plain `ssh -t localhost … tmux attach`;
  killing the buffer leaves no attach process.
- **Mail compose** (bright-lights): `c c` → To/Subject → compose buffer →
  `C-c C-c` returns in 2 ms and closes it → "Sent to human" → delivered;
  marked read afterwards.
- **Rig dashboard:** header line, TAB/S-TAB/SPC; `l` magit-log (1.5 s sync,
  a §8.5 exception); `d` Dired.
- **Remote key probes** (Agents, tree, Runs, Events, Mail, Health, Cities,
  rig dashboard over ssh:localhost): zero TRAMP I/O on TAB/S-TAB/SPC, max
  stall 1–28 ms.
- **Remote Agent detail:** `i`, `v` peek and `f` follow; the host-side
  `gc session logs -f` exits on `q`.
- **Remote Run detail:** RET 2 ms.
- **Remote doctor `!`:** async, 12 s, 47 ms stall.

## Still open

1. **Medium — Mail inbox misses external read-state changes.** bright-lights:
   `gc mail mark-unread bl-wisp-a7gsqc` → gc reports 4 unread, but more than
   30 s later the inbox still says `3 unread / 3` and the row is missing. An
   external `mark-read` took ~18 s to show (budget 5 s; the comms agent's
   concurrent test mails make this one less certain). `mail.sent` updates
   within ~3.7 s.
2. **Medium — Agent detail Work still lists another agent's session bead.**
   The mayor (bright-lights, local and ssh) shows `Work 2` with
   `bl-5a5i core.control-dispatcher` (issue_type session, assignee none)
   and its own session bead `bl-rpq`.
3. **Low-Medium — A1 not effective.** After `M` nudge mayor, gc's
   `last_active` changes (22:01:25) but the cockpit row still says
   `active 10m` 20 s later. The action-completion re-read runs before the
   agent bumps `last_active`, and no event follows. A delayed second
   invalidation is needed.
4. **Low — rig dashboard Ready is uncapped (37 rows) and includes convoy beads**
   (`input convoy for …`, `drain unit …`).
5. **Low — event drawer** repeats the key `message` (event field and
   `payload.message`), with uneven alignment.
