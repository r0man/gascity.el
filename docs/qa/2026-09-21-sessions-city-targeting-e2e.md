# Sessions-list city targeting — tmux-Emacs TRAMP e2e dogfood pass (ga-80m3)

- Date: 2026-09-21
- Item: Step 4 (verification) of the approved plan
  `plans/sessions-list-city-targeting/implementation-plan.md`; source anchor
  bead `ga-80m3`, worktree `worktrees/ga-80m3` (HEAD `72303ad` — the merge of
  the three implementation commits: `6f82a95` city-args hook targeting,
  `b9f57e0` envelope error surfacing, `3138692` exit-9 characterization).
- Environment: fresh `emacs -nw -Q` inside a dedicated tmux session
  (`gce-e2e`, started by `scripts/e2e-harness.sh`), package loaded from the
  item worktree with the sibling `beads.el` checkout plus
  `vui-1.3.0`/`transient-0.13.5` from the Guix profile on the load path;
  `gascity-enable-debug` = t at `verbose` level so every gc argv is captured
  in `*gascity-log*`.
- Cities: the remote test city `/ssh:localhost:/home/roman/bright-lights`
  (TRAMP `ssh` method, per AGENTS.md), the co-hosted local
  `/home/roman/emacs-city`, and a **disposable** city
  `/tmp/gc-e2e-unhealthy` (created with `gc init --no-start`, its dolt store
  directory emptied to reproduce an unhealthy store).
- Method: all interaction through `emacsclient -e` evals wrapped by the
  harness (`e2e_eval`, every call under `timeout(1)`); state read back as
  buffer strings and the `*gascity-log*` argv record. No destructive gc
  action was fired against any real city; the unhealthy store is a
  throwaway city in `/tmp`, unregistered in `~/.gc/cities.toml`
  (`gc cities` lists only `bright-lights` and `emacs-city`).

## Observed results (per acceptance criterion)

- **AC-1 — explicit targeting + co-host isolation. PASS.**
  The remote sessions buffer `*gascity-sessions@/ssh:localhost:/home/roman/bright-lights/*`
  shows exactly bright-lights' sole live session (`mayor`), and the
  reader log records the argv carrying the city flag:

  ```
  Running async: /home/roman/.guix-home/profile/bin/gc --city /home/roman/bright-lights/ session list --json
  ```

  The co-hosted local buffer `*gascity-sessions@/home/roman/emacs-city/*`
  shows only emacs-city's six sessions (`gascity.el/…` rows); re-reading the
  remote buffer confirms it never picked them up. Both buffers keep their
  own `--city` argument (log shows both argv forms side by side).
- **AC-2 — every reader path targets the city. PASS.**
  The status dashboard over TRAMP
  (`*gascity-status@/ssh:localhost:/home/roman/bright-lights/*`) rendered
  `Gas City: bright-lights  /home/roman/bright-lights`, the `bd.dog` scaled
  rig, `hello-world`, and store health — with `status --json`,
  `session list --json`, and `agent list --json` all logged with `--city`.
  The agent/polecat read (`*gascity-agent: mayor@…*`, opened from the
  session-list row) rendered state/provider/mail/recent-history with
  bright-lights bead ids (`bl-*`), and its async reads (`bd list
  --assignee …`, `bd list --has-metadata-key work_dir …`, `mail inbox
  mayor`) all carry the flag. The local dashboard
  (`*gascity-status@/home/roman/emacs-city/*`) renders in the same Emacs
  coexisting with the remote one, per the host-qualified buffer naming.
- **AC-3 — envelope message surfaced. PASS.**
  With the throwaway city's store emptied, its sessions buffer
  (`*gascity-sessions@/tmp/gc-e2e-unhealthy/*`) refreshes asynchronously,
  and the failure reports the envelope message instead of a bare exit
  code. Echoed error line (captured from `*Messages*`):

  ```
  gascity: gc --city /tmp/gc-e2e-unhealthy/ session list --json failed:
  gc session list: listing sessions: listing session beads by type: bd
  list: exit status 1: Error: failed to open database: schema skew check:
  probing schema_migrations existence: Error 1105 (HY000): no root value
  found in session … (exit 1)
  ```

  `*gascity-log*` confirms each tick logged `Async gc exited 1: --city
  /tmp/gc-e2e-unhealthy/ session list --json`. Note: tabulated lists
  report gc errors through the echo area and leave the list empty — the
  pre-existing design of `gascity-tabulated--refresh` ("gc errors are
  caught and reported, leaving the list empty"), unchanged by this
  feature; the surfacing change is that the *text* now carries gc's
  envelope message rather than `failed (exit 1)`.
- **AC-4 — exit 9 characterized. PASS (ERT-covered, not forceable live).**
  An exit 9 could not be reproduced live in bounds (it needs a gc process
  killed mid-flight by a superseding refresh). The characterization is
  pinned by the ERT tests shipped with `3138692`:
  `gascity-test-exit-error-message-exit-9-hinted` (hint text
  `failed (exit 9 — process killed (SIGKILL) — exit 9 is the signal status
  Emacs reports for a torn-down gc process, … refresh to retry)`),
  `gascity-test-exit-error-message-exit-9-envelope-wins` (an envelope
  message still takes precedence), and the 126/127 precedence test.
- **AC-5 — TRAMP parity. PASS.** Over `/ssh:localhost:` the city
  argument arrives in the host-local form (`/home/roman/bright-lights/`
  — no TRAMP prefix), gc resolves on the host
  (`/home/roman/.guix-home/profile/bin/gc` appears in the logged argv),
  and results/errors are correct (items above).
- **AC-6 — gate. PASS.** `scripts/gate.sh` on the worktree before the
  pass: `eldev compile --warnings-as-errors` clean over the whole package
  plus the full ERT suite — **311 tests, 311 as expected, 0 unexpected**.

No new defects were found during this pass; no follow-up beads filed.

## Verification commands

- First verification command (whole-package gate, from the worktree):

  ```console
  $ scripts/gate.sh
  >>> gate: PASS (compile clean + tests green)   # 311/311 ERT
  ```

- Final proof command (live session, via the harness's bounded evals):

  ```elisp
  ;; e2e_eval '(with-current-buffer "*gascity-log*" (buffer-string))'
  "2026-09-21 21:14:07 [INFO] Running async:
     /home/roman/.guix-home/profile/bin/gc --city /home/roman/bright-lights/ session list --json"
  ;; e2e_eval '(with-current-buffer "*gascity-sessions@/ssh:localhost:/home/roman/bright-lights/*" (buffer-string))'
  " mayor                 active    pi        ~/bright-lights"
  ```

  The sessions buffer pinned to the remote city shows bright-lights'
  session, and the same read's argv in the log carries `--city
  /home/roman/bright-lights/`.
