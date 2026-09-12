---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-s7u
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-fza
      hash: bead:ga-fza
      title: "Source anchor: Per-city keying WI-4 — gate + tmux-Emacs dual-city e2e pass + QA report"
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved requirements artifact (REQ-015, REQ-016, AC-4, AC-5)"
      ids:
        - REQ-015
        - REQ-016
        - AC-4
        - AC-5
    - path: docs/qa/2026-09-10-multi-city-keying.md
      hash: git:e75c5f75ede20b6679683a17a9018ed6fdf321b9
      title: "QA record of the dual-city tmux-Emacs e2e pass and the green gate"
  coverage:
    - id: REQ-015
      status: covered
    - id: REQ-016
      status: covered
    - id: AC-4
      status: covered
    - id: AC-5
      status: covered
---

# Implementation summary — WI-4 dual-city e2e pass + gate (ga-fza)

## Summary

Ran the AC-4 acceptance pass for the multi-city-keying work: a fresh
tmux-Emacs (30.2, private tmux server `-L gce-e2e`, worktree
`worktrees/ga-fza` @ `719042e` on `load-path`) holding the local
`emacs-city` and the TRAMP test city
`/sshx:localhost:/home/roman/bright-lights` **simultaneously**, and
exercised the re-keyed porcelain across both: two status dashboards side
by side, rig lists + rig dashboards per city, session lists per city,
per-city eldoc bead-prefix narrowing, a sling dry-run buffer per city,
and a mail compose buffer per city — then `g` refresh over TRAMP while
the local dashboard sat next to it. Wrote the QA record to
`docs/qa/2026-09-10-multi-city-keying.md` and ran `scripts/gate.sh`
(REQ-016). No porcelain code was changed by this item — no residual
re-keying gap surfaced, which was the expected "residual fixes" outcome.

The pass was driven with real keystrokes in the tmux pane and verified
via `emacsclient -e` reads of buffer names, `default-directory` pins,
`gascity-context--rigs-cache` keys and the auto-refresh timers,
cross-checked against live `gc status --json` for both cities.

## Intended Behavior

Per the source anchor (`ga-fza`, plan Steps 7–8) and the requirements
artifact: the multi-city flow must be exercised in the tmux-Emacs e2e
pass against `/ssh:localhost:/home/roman/bright-lights` **and** the local
`emacs-city` simultaneously (REQ-015, AC-4), recorded in a `docs/qa/`
report that also notes the remote-city buffer-name churn (city-root
qualification replaces the old host-only shape); and `scripts/gate.sh`
must pass from a clean tree (REQ-016, AC-5). AGENTS.md's "Remote test
city & end-to-end testing" section makes the interactive pass — not ERT —
the acceptance gate for AC-4, with bright-lights unreachability being a
blocker to record, never a silent skip. bright-lights was reachable and
the full flow passed on both cities at once.

## Changed Files

| File | Change |
|---|---|
| `docs/qa/2026-09-10-multi-city-keying.md` | new — QA record of the dual-city pass (setup, PASS/FAIL matrix over the ten checks, TRAMP sshx deviation, surface-change note, verification commands) |

Commit: `e75c5f75ede20b6679683a17a9018ed6fdf321b9`
("docs(qa): dual-city tmux-Emacs e2e pass for per-city keying
(ga-fza)") in worktree `worktrees/ga-fza`. Gate run immediately before
the commit from the same clean tree (`git status` empty apart from the
report; `scripts/gate.sh` → compile clean + 252/252 ERT).

## Verification

1. First verification command of the pass — remote-city reachability from
   a fresh batch Emacs with no gascity loaded (also the F4 re-check):

   ```
   timeout 45 emacs -Q --batch --eval \
     '(princ (file-exists-p "/sshx:localhost:/home/roman/bright-lights/city.toml"))'
   ```

   Observed: **pass** (prints `t`). The plain `/ssh:` variant still hangs
   on this host (F4 re-confirmed standalone), so the pass ran over `sshx`
   — still a TRAMP remote file name, the same deviation the prior pass
   recorded and documented in the QA report.

2. Final proof command of the e2e run — buffer inventory + per-city rigs
   memo read back from the live session after the last cross-city
   refresh (excerpt, full transcript in the QA report):

   ```
   :all-gascity-bufs ("*gascity-sessions@/home/roman/emacs-city/*"
     "*gascity-sessions@/sshx:localhost:/home/roman/bright-lights/*"
     "*gc-sling: dry-run@/home/roman/emacs-city/*"
     "*gc-sling: dry-run@/sshx:localhost:/home/roman/bright-lights/*"
     "*gascity-status@/home/roman/emacs-city/*"
     "*gascity-rig: hello-world@/sshx:localhost:/home/roman/bright-lights/*"
     "*gascity-rigs@/sshx:localhost:/home/roman/bright-lights/*"
     "*gascity-status@/sshx:localhost:/home/roman/bright-lights/*"
     "*gascity-rigs@/home/roman/emacs-city/*"
     "*gascity-rig: beads.el@/home/roman/emacs-city/*")
   :emacs-city-prefixes ("be" "ga")  :bright-prefixes ("hw")
   ```

   Observed: **pass** — ten coexisting city-keyed buffers, two distinct
   rigs-memo keys with per-city bead prefixes, both auto-refresh timers
   bound to their own buffer/city, no `default-directory` re-pinning in
   either direction.

3. Gate (REQ-016, AC-5):

   ```
   scripts/gate.sh   # from worktrees/ga-fza
   ```

   Observed: **pass** — `>>> gate: PASS (compile clean + tests green)`,
   252/252 ERT, whole-package byte-compile with `--warnings-as-errors`.

## Remaining Risks

- **TRAMP plain-`ssh` hang on this host (environment, pre-existing F4):**
  re-confirmed standalone (`emacs -Q --batch` hangs on `/ssh:localhost:…`,
  `sshx` works). The remote login shell appends a vterm OSC-51
  terminal-integration sequence after the prompt, which TRAMP's plain-ssh
  login detect loop never matches. Not a gascity.el defect; follow-up
  worth a `gc doctor` check (also tracked from the prior pass).
- **`sshx` vs `ssh` identity:** the pass connected as
  `/sshx:localhost:…`, so the verified scope-key shape embeds the `sshx`
  prefix. Keying is by the resolved city root whatever the method, and
  the unit tests cover the `ssh:` shape, but a live pass over the plain
  `ssh` method remains blocked by the host issue above.
- **Worktree volatility:** `worktrees/ga-fza` was deleted externally
  mid-pass and was recreated from `719042e` before any file was written;
  the committed tree (`e75c5f7`) is intact. Cause unknown (likely another
  agent's cleanup); flagged in the QA report.
- bright-lights runs degraded (`no_agents_running` at pass time) — health
  banner rendered correctly; no bearing on the keying checks.

| ID | Status |
| --- | --- |
| REQ-015 | covered |
| REQ-016 | covered |
| AC-4 | covered |
| AC-5 | covered |
