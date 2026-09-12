# QA — multi-city keying: tmux-Emacs dual-city e2e pass (WI-4, ga-fza)

Acceptance pass for **AC-4** (REQ-015): the re-keyed porcelain driven against the
TRAMP test city `/home/roman/bright-lights` **and** the local `emacs-city`
**simultaneously** in one fresh tmux-Emacs, per AGENTS.md "Remote test city &
end-to-end testing". Plus the final gate (**AC-5**, REQ-016, plan Step 8).

Work item: WI-4 of the multi-city-keying decomposition (plan
`plans/multi-city-keying/build/implementation-plan.md` Steps 7–8, bead
`ga-fza`). Code under test: WI-1–WI-3's re-keying (`gascity-context-scope-key`,
per-city rigs memo, city-root-qualified buffer names) at `719042e` — **no
porcelain code was changed by this pass**; the expected outcome was "no
residual re-keying gaps", and none surfaced.

## Setup

| | |
|---|---|
| Code | worktree `/home/roman/workspace/gascity.el/worktrees/ga-fza` @ `719042e` (all of WI-1–WI-3: scope-key helper, per-city rigs memo, city-root buffer names, attach buffers, per-city unit tests) |
| Emacs | fresh `emacs -nw -q` 30.2 in a private tmux server (`tmux -L gce-e2e new-session -d -s w54`), harness adding the worktree `lisp/`, the beads.el sibling and vui 1.0.0 to `load-path`, then `gascity` + an Emacs server (`-s gce-w54`) |
| Cities | local **emacs-city** `/home/roman/emacs-city` (health ok, 1/5 agents) and TRAMP **bright-lights** `/sshx:localhost:/home/roman/bright-lights` (health degraded — `no_agents_running`, reachable; gc status cross-checked live) |
| Method | real keystrokes in the tmux pane (`M-x`, `RET`, `C-x o`, `g`, `C-n`, transient keys, `C-c C-k`) driven and cross-checked with `emacsclient -s gce-w54 -e` reading buffer names, `default-directory` pins, the rigs-memo hash table and the auto-refresh timers; every datum cross-checked against `gc status --json` for both cities |

## Deviation: TRAMP `sshx`, not `ssh` (F4, re-confirmed)

Per the plan-review advisory and the prior pass's F4 finding
(`docs/qa/formula-sling-ui-e2e.md`), the **plain `ssh` TRAMP method hangs on
this host**. Re-confirmed today, standalone, with no gascity loaded:

```bash
timeout 60 emacs -Q --batch --eval '(princ (file-exists-p "/ssh:localhost:/home/roman/bright-lights/city.toml"))'
# never returns (killed at 60 s); with `tramp-use-connection-share nil` also set: still hangs
timeout 45 emacs -Q --batch --eval '(princ (file-exists-p "/sshx:localhost:/home/roman/bright-lights/city.toml"))'
# prints t immediately
```

The pass therefore connected as **`/sshx:localhost:/home/roman/bright-lights`**
— still a TRAMP remote file name (qualified `default-directory`, remote
`gc`/`tmux` resolution, `tramp-remote-path`), exactly the setup F4 used and
recorded as behaviorally identical. This is an environment issue in this
host's ssh/shell setup (the remote login shell appends a vterm OSC-51
terminal-integration sequence after the prompt, which TRAMP's plain-ssh login
detect loop never matches), **not** a gascity.el defect; bright-lights being
unreachable would have been an AC-4 blocker, and it is reachable. Same
follow-up as F4: worth a `gc doctor` check.

## PASS/FAIL matrix

| # | Check (plan Step 7) | Verdict |
|---|---|---|
| 1 | Two `gascity-status` dashboards side by side (local + TRAMP), distinct buffer names | **PASS** — `*gascity-status@/home/roman/emacs-city/*` and `*gascity-status@/sshx:localhost:/home/roman/bright-lights/*` |
| 2 | Neither re-pins the other's `default-directory` | **PASS** — after opening and refreshing both directions, each buffer still pinned to its own city root |
| 3 | No stale timer polls the wrong city | **PASS** — exactly two `gascity-status--auto-refresh-tick` timers in `timer-list`, each bound to its own buffer with its own city `default-directory` |
| 4 | Rig lists / rig dashboards per city | **PASS** — `*gascity-rigs@/home/roman/emacs-city/*` (beads.el/emacs-city/gascity.el rows) vs `*gascity-rigs@/sshx:localhost:/home/roman/bright-lights/*` (bright-lights/hello-world rows); `RET` drill-in gave `*gascity-rig: beads.el@/home/roman/emacs-city/*` and `*gascity-rig: hello-world@/sshx:localhost:/home/roman/bright-lights/*`; RET on the bright-lights HQ row correctly says "city HQ, not a rig" |
| 5 | Session lists per city | **PASS** — `*gascity-sessions@/home/roman/emacs-city/*` (mayor `~/emacs-city`, gascity.el sessions) vs `*gascity-sessions@/sshx:localhost:/home/roman/bright-lights/*` (mayor `~/bright-lights`, hello-world sessions) |
| 6 | Eldoc prefix narrowing per city after visiting both (US-3) | **PASS** — the value beads-eldoc consumes (`gascity-rigs-cached-prefixes`) is per city after visiting both: emacs-city `("be" "ga")`, bright-lights `("hw")`, two memo keys in `gascity-context--rigs-cache` — under the pre-fix host-only key the last-visited city (`hw`) would have served both |
| 7 | Sling dry-run buffer per city | **PASS** — `gascity-sling-dispatch` → `p` (preview) → target `mayor` in each city: `*gc-sling: dry-run@/home/roman/emacs-city/*` and `*gc-sling: dry-run@/sshx:localhost:/home/roman/bright-lights/*`, each showing gc's own routing plan for its city's mayor (dry-run only; nothing dispatched) |
| 8 | Compose buffer per city | **PASS** — `gascity-mail-send` to `mayor` in each city opened `*gc-mail to mayor@/home/roman/emacs-city/*` and `*gc-mail to mayor@/sshx:localhost:/home/roman/bright-lights/*`, each pinned to its city root; both aborted with `C-c C-k`, nothing sent |
| 9 | `g` refresh over TRAMP while the local dashboard sits next to it | **PASS** — bright-lights session list refreshed over the TRAMP channel; the local dashboard's pin, memo entry and prefixes untouched |
| 10 | Cross-check vs `gc … --json` | **PASS** — dashboards matched live `gc status --json` for both cities (agents, health, session counts, rig sets) |

## User-visible surface change (plan-review advisory 2)

Confirmed live: remote-city view buffer names now carry the **city root**, not
just the host — `*gascity-status@/sshx:localhost:/home/roman/bright-lights/*`
instead of the old `*gascity-status@/sshx:localhost:*` shape. Local-city
single-city users are unaffected (a local city qualifies by its absolute city
root; no city → unchanged host-only names). This is the one user-visible churn
of the re-keying; no migration shim is planned (stale pre-upgrade buffers are
orphans until closed, per the plan's non-goals).

## Residual fixes surfaced

None. No re-keying gap was exposed by the dual-city pass; no porcelain code
was changed in this item.

## Environment notes

- The item worktree `worktrees/ga-fza` was deleted externally mid-pass
  (18:37, while the e2e Emacs was running); recreated immediately via
  `git worktree add … 719042e` (clean, `git status` empty) and the pass was
  then run to completion against it. Nothing in the city or the repo caused
  it; flagging in case another agent's cleanup raced this session.
- TRAMP plain-`ssh` hang: see the Deviation section (F4 re-confirmation).

## Verification

1. **E2E pass (REQ-015, AC-4)** — the tmux-Emacs dual-city session above is
   the acceptance run; this report is its record. First verification command
   of the pass (`sshx` reachability, fresh `emacs -Q` batch, no gascity):
   `timeout 45 emacs -Q --batch --eval '(princ (file-exists-p "/sshx:localhost:/home/roman/bright-lights/city.toml"))'`
   → **pass** (prints `t`). Final proof command of the run — buffer
   inventory + per-city memo state read back from the live session after the
   last cross-city refresh:

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

   → **pass** (ten coexisting per-city buffers; two distinct memo keys with
   per-city bead prefixes).

2. **Gate (REQ-016, AC-5)** — `scripts/gate.sh` from a clean worktree:
   whole-package `eldev compile --warnings-as-errors` + full ERT suite →
   **pass** (result recorded below in the commit body).

## Traceability

| ID | Status |
|----|--------|
| AC-4 | covered |
| AC-5 | covered |
| REQ-015 | covered |
| REQ-016 | covered |
