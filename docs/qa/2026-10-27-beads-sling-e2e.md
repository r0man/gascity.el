# beads.el → gc sling E2E — B8 acceptance pass (local city + TRAMP)

- Date: 2026-10-27
- Bead: `ga-2d5z4` — "gascity: B8 gates, tmux/TRAMP E2E, QA report, PR"
  (workflow root `ga-x6yz3`, workstream B of
  `plans/beads-sling-integration/`, REQ-009, AC-B13/AC-B14/AC-B16)
- Worktree: `/home/roman/workspace/gascity.el/worktrees/ga-2d5z4`
- Branch: `beads-sling-b8-ga-2d5z4`, branched from the workstream-B chain
  (`beads-sling-b8`, B1–B7) on base `origin/main` `97e12cb`
- Package under test: `lisp/gascity-beads-sling.el` plus the B1–B7 wiring
  (`gascity.el`, `gascity-context.el`, `gascity-types.el`, the ERT suites and
  the B7 docs)
- Environment: GNU Emacs 31.1 (Guix profile), transient 0.13.8, Texinfo 6.8,
  `beads.el` checkout `a744ac25` (workstream A merged), `vui` 1.4.0 from the
  `beads.el` Eldev bundle
- Emacs start: `emacs -nw -Q -l /tmp/b8-e2e-init.el` inside a fresh tmux
  session, started with `env -i` (a real user session: no `GC_*`, `BEADS_*`
  or `GC_RIG` leakage from the worker's shell), load path = worktree `lisp/` +
  `beads.el/lisp` + bundled `vui`
- Harness: `scripts/e2e-harness.sh` sourced in every step — every
  `emacs`/`emacsclient`/`tmux` call bounded by `timeout(1)`, `tmux
  has-session` checked before `send-keys`/`capture-pane`
- Cities: local `/home/roman/emacs-city` (prefix `ec`) and remote
  `/ssh:localhost:/home/roman/bright-lights` (prefix `bl`)

TRAMP note: this pass used the documented `/ssh:localhost:` method directly.
The earlier `ssh`-method hang (`F4` of
`docs/qa/formula-sling-ui-e2e.md`) did **not** reproduce: the connection was
established in about a second, `city.toml` opened, and every remote read and
the remote `gc sling` round trip completed. No `sshx` workaround was needed.

## What was exercised

Every launch below is the real interactive path: a beads.el show buffer, `S`
(beads' own `beads-sling-for-issue`, no gascity binding), `T` (the Who
picker), `s` (launch). Nothing was driven by calling the backend directly.

### Local city (`emacs-city`)

1. `M-x gascity` opened the `gascity-dispatch` menu (the front door). The
   cockpit is `M-x gascity-dashboard`; opening it warmed the store and the rig
   memo for `/home/roman/emacs-city`:

   ```
   emacs-city  ○ live: supervisor down  ↻ 0s ago        ? help  j jump  g refresh
   agents 6/10 ●   sessions 6   runs 2 ⬣   ready 21   mail ▲7   dolt 6.9 GB ●
   ```

2. Disposable bead created in the city store:

   ```console
   $ cd /home/roman/emacs-city && bd create \
       "e2e beads-sling local 2026-10-27" -t task -p 4
   ec-6dhcw
   ```

3. `M-x beads-show RET ec-6dhcw RET` opened
   `*beads-show[emacs-city]/ec-6dhcw e2e beads-sling local 2026-...*`
   (store `emacs-city · /home/roman/emacs-city/.beads/dolt`).

4. `S` opened beads.el's adaptive sling transient, seeded from the bead:

   ```
   Sling — emacs-city
      Sling bead ec-6dhcw to emacs-city/task
      ✓ Ready — local route · target emacs-city/task · no vars

   What
    A Work: ec-6dhcw — e2e beads-sling local 2026-10-27
    f Formula: (none — f to pick)

   Who
    T Target: emacs-city/task · local · available
   ```

5. `T` opened the Who picker (`Target:`) and `TAB` listed 41 candidates, all in
   the `Agent` group, e.g. `bd.dog — agent · bd.dog`,
   `beads.el/core.control-dispatcher — agent · …`. A live evaluation in the
   same session confirmed the gc provider's rows:

   ```
   (:total 92 :gc 36
    :mayor ("mayor" "gc" agent nil)
    :sample (("bd.dog" "gc") ("beads.el/core.control-dispatcher" "gc")
             ("beads.el/gc.design-author" "gc")))
   ```

   (The picker's 41 in the city-root show buffer are 36 gc roster rows plus 5
   beads-local rows; the 92 includes the local role/worktree providers for the
   worktree directory the eval ran in — the gc rows are the same 36.)

6. `mayor` chosen; the rebuilt transient showed `T Target: mayor`. `s`
   launched. Echo:

   ```
   Slung ec-6dhcw to mayor
   ```

7. Captured action argv (advice on `gascity-reader-run-async`, the action
   lane):

   ```elisp
   ("gc" "sling" "mayor" "ec-6dhcw" "--json")
   ```

   i.e. the documented plain shape `("sling" TARGET BEAD)`, plus `--json` so
   the backend parses gc's result. No `--on`, no `--var`, no prompt argument.

8. Launch visible in gascity's views and store: the auto-convoy appears in the
   convoy list immediately after the launch's single invalidation:

   ```
   *gascity-convoys@/home/roman/emacs-city/*
    ec-bijp0     sling-ec-6dhcw                    open       0/1
   ```

   and the cockpit's `ready` count dropped 21 → 20. In the store:

   ```console
   $ cd /home/roman/emacs-city && bd show ec-6dhcw --json | jq .metadata
   {"gc.routed_to": "mayor", …}
   $ gc convoy list --json | jq '.[] | select(.title=="sling-ec-6dhcw")'
   {"id":"ec-bijp0","title":"sling-ec-6dhcw","status":"open",
    "progress":{"closed":0,"total":1},"child_ids":["ec-6dhcw"]}
   ```

9. `*gascity-log: emacs-city*` was not created: on success the action echoes
   (and the backend calls `on-success`), while the city log buffer only
   receives the failing call's full stderr
   (`gascity-store--complete-action`). The argv above is therefore captured
   from the action runner rather than read out of the log.

### Remote city (`/ssh:localhost:/home/roman/bright-lights`)

1. `C-x C-f /ssh:localhost:/home/roman/bright-lights/city.toml RET` (TRAMP
   connect ~1 s), then `M-x gascity-dashboard` opened the remote cockpit
   `*gascity: bright-lights@/ssh:localhost:/home/roman/bright-lights/*` with no
   blocking load; the store warmed in a couple of seconds
   (`gascity-store-peek '("agent" "list")` on the remote directory non-nil).
2. Disposable bead created on the host:

   ```console
   $ ssh localhost 'cd /home/roman/bright-lights && bd create \
       "e2e beads-sling tramp 2026-10-27" -t task -p 4'
   bl-rawe
   ```

3. `M-x beads-show RET bl-rawe RET` opened
   `*beads-show[/ssh:localhost:|bright-lights]/bl-rawe e2e beads-sling …*`
   (beads runs `bd` over TRAMP; store `bright-lights`).
4. `S` opened the transient with the remote city already known from the cached
   store — no file walk and no gc spawn at open time:

   ```
   Sling — bright-lights
      Sling bead bl-rawe to bright-lights/task
      ✓ Ready — local route · target bright-lights/task · no vars
   ```

5. `T` → 25 candidates, including gc rows (`bd.dog`,
   `hello-world/gc.design-implementation-reviewer`, …) next to beads' local
   `bright-lights/claude` / `bright-lights/pi` agent rows. Live evaluation in
   the remote scope:

   ```
   (:total 25 :gc 20 :mayor ("mayor" "gc" nil))
   ```

6. `mayor` chosen (`T Target: mayor`), `s` launched:

   ```
   Slung bl-rawe to mayor
   ```

   argv captured: `("gc" "sling" "mayor" "bl-rawe" "--json")`.

7. Non-blocking evidence: one second after `s`,
   `gascity-store-action-pending-p` for target `mayor` on the remote directory
   returned `t` — the launch was still in flight on the action lane while the
   Emacs was already accepting the next command; the echo arrived when the
   remote call completed. The remote `gc sling` ran through the existing
   ssh-pipe action lane (no TRAMP make-process), and the launch was
   subsequently visible in the remote views:

   ```
   *gascity-convoys@/ssh:localhost:/home/roman/bright-lights/*
    bl-07l0      sling-bl-rawe                           open       0/1
   ```

   Remote store after the launch:

   ```console
   $ ssh localhost 'cd /home/roman/bright-lights && bd show bl-rawe --json' \
       | jq .metadata.gc.routed_to
   "mayor"
   $ ssh localhost 'cd /home/roman/bright-lights && gc convoy list --json' \
       | jq '.[] | select(.title=="sling-bl-rawe")'
   {"id":"bl-07l0","title":"sling-bl-rawe","status":"open",
    "progress":{"closed":0,"total":1},"child_ids":["bl-rawe"]}
   ```

### Cold-start observation (B2/B7 caveat, confirmed live)

A third, fresh Emacs (`gce-cold`, same `-Q` init) opened a beads show buffer
*without* ever opening a gascity view. There the target provider answered nil
(the city is unknown and the cache is cold), `("agent" "list")` was not in the
store, and the Who picker offered only beads' own five targets
(`emacs-city/task`, `emacs-city/plan`, `emacs-city/review`, `emacs-city/pi`,
`emacs-city/claude` — i.e. `local`/`pi`/`claude` backends). No gc target, no
gc process, no file walk. This is exactly the documented cold-start limitation:
the first dispatch from a fresh Emacs needs a gascity view (or a remembered
city) before the Who picker can name gc agents.

## Cleanup

```console
# local
$ cd /home/roman/emacs-city
$ bd close ec-6dhcw --reason 'e2e disposable bead, B8 beads-sling local pass'
$ bd close ec-bijp0 --reason 'e2e auto-convoy cleanup, B8 local pass'
# remote
$ ssh localhost 'cd /home/roman/bright-lights && bd close bl-rawe --reason "…" \
    && bd close bl-07l0 --reason "…"'
```

Both tmux sessions (`gce-b8`, `gce-cold`) were killed with the harness helper;
the only persisted state is this report. No beads.el file was touched.

## Verification commands and results

Run from the worktree `/home/roman/workspace/gascity.el/worktrees/ga-2d5z4`:

| Command | Result |
| --- | --- |
| `scripts/gate.sh` (first verification) | **PASS** — whole-package byte-compile with warnings-as-errors, `make check` 843/843 ERT (incl. 21 `gascity-test-beads-sling-*` tests) |
| `scripts/lint.sh` (CI lint bar) | **PASS** — checkdoc clean; with package-lint 0.26 on the load path (as CI installs it) `make lint` is also clean |
| `make -C doc` (manual gate) | **PASS** — Texinfo 6.8 builds `doc/gascity.info` |
| `make -C doc html` | **PASS** — builds the HTML manual incl. `Slinging-from-beads.html` |
| `git diff --stat origin/main` (AC-B16) | only gascity.el paths: `lisp/gascity-beads-sling.el`, its ERT suite, `lisp/gascity{,-context,-types}.el`, `lisp/test/gascity-store-test.el`, `lisp/test/gascity-test-helpers.el`, the four docs, and the task summaries. No `beads.el` path, no vendored `beads-sling.el`, no `gc` CLI change. |

The final proof command for the live pass was the store check above
(`gc.routed_to` + `sling-<bead>` convoy on both cities) together with the
captured argv `("gc" "sling" "mayor" BEAD "--json")` for the local and remote
launches.

## Findings

- **F1 (minor UX, out of B scope):** `gascity-dispatch` has no `q` suffix, so
  `q` reports "Unbound suffix" and `C-g` is the only way out, contrary to the
  AGENTS.md "`q` buries everywhere" convention. Filed as a follow-up; not
  changed here.
- **F2 (task wording):** the B8 bead says "open `M-x gascity` once to warm
  store + rig memo"; `M-x gascity` is the verb menu and warms nothing. The
  cockpit (`M-x gascity-dashboard`, reachable from that menu's `j j`) is what
  warms the store; this pass opened both.
- **F3 (AC wording):** AC-B14 asks for a "workflow root visible in gascity's
  run/status view", while the documented B8 step is the plain route, which
  creates an auto-convoy, not a graph.v2 run. This pass verified the plain
  launch in the convoy view and the store (`gc.routed_to` + `sling-<bead>`),
  and did not launch a v2 formula workflow on disposable state (that would
  spawn real work). The formula/`--on` argv shapes remain covered by ERT
  (`gascity-test-beads-sling-backend-formula-argv`,
  `…-backend-on-argv`, `…-backend-plain-argv`).
- **F4 (by design, documented):** success paths do not write
  `*gascity-log: CITY*`; the log only carries failure stderr. The E2E captured
  argv from `gascity-reader-run-async` instead.
- **F5 (informational):** the Who picker's candidate count in a beads buffer
  reflects beads' own project-scoped role/backend/worktree targets plus the gc
  roster; the gc provider's rows are identical in every context once the city
  is known.

## Limitations

- No formula workflow was instantiated live (see F3), so the "new workflow
  root in the runs view" half of AC-B14's wording is evidenced by the
  backend's argv tests and B3b's ERT, not by this live pass.
- The disposable beads were routed to `mayor` (a session target whose
  `sling_query` only sets `gc.routed_to`), so the pass proves routing and
  convoy creation; it does not exercise an agent picking the bead up.
