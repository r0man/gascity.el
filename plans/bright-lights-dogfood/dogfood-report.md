# Bright-lights dogfood UX report (ga-hirj)

Date: 2026-09-22. Runner: `gascity.el/gc.implementation-worker-1` (pi session
`ec-3j2y`), bead ga-hirj.

## How this pass was run

A fresh Emacs was launched inside tmux via `scripts/e2e-harness.sh`
(`e2e_start_emacs`, session `gce-e2e`, server socket `gce-e2e`), then
gascity.el was loaded from the working tree (`~/workspace/gascity.el/lisp` +
`~/workspace/beads.el/lisp`). Every checklist item below was exercised in that
live Emacs — `M-x` invocations, transient menus, tabulated keys and vui
sections — with the pane captured through tmux. Neither `gc` nor `bd` was used
for any UI action; they were used only to verify what landed after the fact.

Both access modes were run against `/home/roman/bright-lights`:

- **A. local**: `default-directory` `/home/roman/bright-lights`
- **B. TRAMP**: `default-directory` `/ssh:localhost:/home/roman/bright-lights`

## Checklist results

### 1. `M-x gascity-status` — works, but gc's health signal misleads

The dashboard rendered fully in both modes: city header, controller (PID,
mode), agent pool (`▼ bd.dog scaled` with members), named sessions (mayor,
core.control-dispatcher), rig section, store health. Collapse state (TAB on
`▼ bd.dog`) works.

Findings:

- **gc's `health.degraded` is env-sensitive** (upstream gc). In the dogfood
  Emacs, the *local* read rendered "health degraded · agents 0/4 running"
  while the identical view over TRAMP showed "health ok · 1/4 running" — and
  minutes later the local read agreed with TRAMP. Reproduced on the CLI:
  a scrubbed environment (`env -i`) makes `gc status --json` report
  `degraded: true, signals: ["no_agents_running"]` even though agents run;
  with `GC_CITY`/`GC_DIR` pointing at *another* city, `gc status` inside
  bright-lights reports **emacs-city's** `store_health` path and agent
  summary. The dashboard renders gc faithfully — this is an upstream gc
  bug — but a magit user staring at "health degraded" gets nothing to act
  on. Fix landed: the header now appends gc's own `signals` when degraded
  (e.g. `health degraded (no_agents_running)`).
- `TAB` on the bare "City" section header answers "No section to toggle
  here". The header carries the `gascity-section` text property, so the
  refusal reads as a bug to a magit user. (Minor; filed.)
- Agent detail (`i` on a city-scope agent) rendered dangling empty labels:
  `provider  ·`, `last active `, and bare `worktree` / `tmux` lines.
  Fixed: empty values now render as `—`, and the worktree/tmux lines are
  omitted when there is no value.

### 2. Rig list + rig dashboard — works

`M-x gascity-rig-list` lists bright-lights (HQ) and hello-world with
status/prefix/store columns; `RET` on hello-world opened
`*gascity-rig: hello-world@…*` with Agents/Ready/In-progress/Orders sections
and `hw-aij` under Ready. `RET` on a bead row opened beads.el's show buffer
with correct scoping (`*beads-show[hello-world]/hw-aij …`).

Findings: the Branch column renders `—` for one rig and an empty cell for
another with the same nil value (minor inconsistency). The Dolt section shows
"(unavailable)" — see the upstream findings below.

### 3. Sessions buffer — works; one keybinding gap fixed

`M-x gascity-session-list` renders rows (Agent/Rig/State/Provider/Working
dir) for mayor and core.control-dispatcher, local and TRAMP. The `/` filter
transient opens with `-s` State and `-r` Rig; auto-refresh is on by default
and re-reads without freezing (async). `RET`/`t` attach the session's tmux.

- **Fixed**: `S` (sling-dispatch) was bound in the status dashboard, rig
  dashboard and session detail but **not** in the flat sessions list — the
  only agent view where dispatch was unreachable. Added, matching
  DESIGN-write-actions.md §10's "same key everywhere" rule.
- `M` nudge / `v` peek / row actions resolve on the `gascity-agent` entry id;
  nudge dispatched cleanly from the list (no confirmation needed, reported in
  the echo area — matches the quick-mutation contract).
- Auto-refresh + a long synchronous TRAMP eval on the same connection can
  wedge Emacs (see TRAMP findings).

### 4. Bead lifecycle through the UI — works end to end

Created `bl-ysk` via `gascity-bead-create` (title/type/priority prompted), it
appeared in gc's store; opened it from the rig dashboard (`RET` on a bead row
→ beads.el show buffer, correctly scoped); updated priority `P3 → P2` via
`gascity-bead-set-priority` (verified in gc: `updated_at` bumped); closed it
via the UI close path with a reason. Cleanup done.

Note: gc's `bd create` echo and `bd`-CLI listing can disagree about store
routing when the gc env carries a foreign `GC_RIG`/`GC_CITY` (bl-ysk was
created via gc's native store and is invisible to a bare `bd show` in some
directories). Not a gascity defect, but the kind of surprise a user hits.

### 5. Sling through the UI — both paths land

- Simple sling (`M-x gascity-sling`, target `mayor`): created `bl-fqq`
  "dogfood test: …" routed to mayor. Confirmed with `gc bd list`; closed
  afterwards.
- Formula path: the unified `S` transient renders Sling header · Formula ·
  Destination · Routing flags · Actions. `-f` prompted "Formula:", `-T`
  offers target sessions, `s`/`p` dispatch/preview. Dispatching e2e-demo
  with `--var note=dogfood-formula-pass` created the workflow root
  (`bl-pvq`, metadata `gc.formula_name=e2e-demo`, `gc.var.note=…`) and the
  latch step `bl-77u` with the variable substituted into the step title.
  Verified in gc; cleaned up.

Findings (filed for follow-up):

- The formula **picker served the wrong city's catalog**: typing the
  bright-lights formula `e2e-demo` answered `[No match]` — the completion
  collection had been memoized from a read that ran outside the city context
  (the transient's minibuffer inherited a foreign `default-directory`, so
  `gascity-formula-catalog-cached` memoized emacs-city's formulas under an
  empty scope key). `g` (Refresh catalog) is the escape hatch; the pick
  should pin the city context it was entered from. Reproduction recorded in
  the bead.
- Pressing `RET` while the formula completing-read prompt is up can be
  intercepted by the transient's suffix map ("Unbound suffix: 'RET'
  [gascity-rig-dashboard-activate]") — needs confirmation on an interactive
  keyboard (several attempts were confounded by the harness key channel; see
  below).

### 6. Mail — inbox/read/send work; agent-detail count does not

- `M-x gascity-mail-inbox` renders the inbox tabulated view (sender, subject,
  date, unread ●) in both modes.
- `gascity-mail-send` opened the compose buffer (`*gc-mail to mayor*`), body
  via `C-c C-c` delivered `bl-wisp-afklkv` "dogfood mail test" to mayor —
  verified in `gc mail inbox mayor --json`, then deleted.
- `r` on an inbox row opened the message body and marked it read (unread
  count dropped 5 → 4).
- **Agent detail's mail section always shows "(unavailable)"** for
  rig-scoped agents: `gc mail inbox <rig-qualified-alias>` fails with
  "session not found" whenever `--city` is passed, and gc's mail identity
  resolution is env-dependent otherwise (filed, upstream-leaning).

### 7. "What's going on" — events / recent-beads: gap

The status dashboard has no events or recent-activity section; `gc event
list` exists but **does not declare JSON support** (`json_unsupported`
envelope), so there is no porcelain-renderable surface. The closest today is
the rig dashboard's Ready/In-progress sections and `gascity-dolt-list` /
`gascity-order-list`. A user asking "what's going on" must shell out. Filed a
bead: either a dim "recent events" section fed by `gc event` once gc gains
JSON, or a documented pointer to `.gc/events.jsonl`.

## TRAMP pass (mode B)

Everything verified locally re-verified over
`/ssh:localhost:/home/roman/bright-lights`:

- Buffers are correctly host-qualified (`*gascity-status@/ssh:localhost:…/*`
  coexists with the local one), `default-directory` pinned, reads run remote
  gc.
- Status dashboard: correct health (`ok`), running agent `●`, named sessions
  mayor + core.control-dispatcher, store health. Sessions list and rig list
  match local. Mail inbox renders. Rig dashboard renders with its async
  sections.
- **Latency**: one `gc session list` read over TRAMP measured ≈ 1.0 s; local
  reads measured ≈ 0.9–2.5 s each (`gc` process overhead dominates, not
  TRAMP). The window-paged tabulated lists and stale-while-revalidate vui
  sections absorb this fine.
- **Hazard (reproduced)**: with the status dashboard's auto-refresh ticking
  over TRAMP and a long synchronous eval occupying the same connection
  channel, Emacs spun up connection after connection (`gascity-gc<52>` …
  `<74>`) and pinned ~43% CPU; the emacsclient eval channel stopped answering
  and the session had to be killed. The dashboards guard ticks against
  in-flight reads, but a *synchronous* read plus ticks can still thrash the
  tramp-sh channel. Recommendation: serialize/queue TRAMP reads behind one
  connection-lock (the guard exists for the auto-refresh tick; extend it to
  any reader that must share the channel) and document "don't eval long
  sync reads while an auto-refresh dashboard is displayed".

## Friction points a magit user would curse at (ranked)

1. **gc health env-sensitivity** renders contradictory dashboards ("degraded,
   0/4 running" vs "ok, 1/4 running" for the same city, depending on which
   shell launched Emacs). Upstream gc must fix city/env resolution; gascity
   now at least shows gc's `signals` so the diagnosis starts in the UI.
2. **Dolt section permanently "(unavailable)"**: `gc dolt health/list` reject
   `--city` even though their help advertises it as a global flag, and their
   cwd resolution finds the machine-global dolt server (bright-lights' rig
   dashboard showed emacs-city's databases). Filed as gc-side bug with a
   gascity workaround proposal.
3. **Formula picker cross-city contamination** (wrong catalog, empty scope
   key) — transient state depends on ambient `default-directory` too much.
4. **Agent-detail mail "(unavailable)"** with the gc failure swallowed —
   surface the envelope detail in the placeholder.
5. **`mode unavailable from gc JSON (gce-8ey)`** in Named sessions — gc's
   session rows lack a `mode` field; render "mode —" dim instead of an
   internal-sounding message.
6. Small ones: TAB on the "City" header, Branch `—` vs `""`, `gc event` JSON
   gap (7).

## Fixes implemented in this pass (ga-hirj)

1. `lisp/gascity-tabulated.el` — `S` bound to `gascity-sling-dispatch` in
   `gascity-session-list-mode-map` (+ docstring; declare-function).
2. `lisp/gascity-session.el` — agent-detail state block: `—` instead of
   dangling empty provider/last-active labels; worktree/tmux lines omitted
   when empty.
3. `lisp/gascity-status.el` — the status header shows gc's health `signals`
   next to "degraded" (e.g. `health degraded (no_agents_running)`), so the
   most alarming display carries its own diagnosis.

`scripts/gate.sh` (compile --warnings-as-errors + 324 tests) passes.

## Test-harness footguns hit during this pass

- tmux 3.7c: `tmux send-keys -t s "Return"` types the literal text `Return`
  (`Enter` works as a key name). The harness's `e2e_send_keys` passes tokens
  unquoted, so a multi-character key name silently degrades to typing — it
  triggered a real "Restart rig?" confirm mid-pass. Use `-H` hex bytes or
  `Enter`/`Tab` key names only.
- When one elisp file fails to byte-compile (even a paren imbalance), the
  follow-up compile reports spurious "function not known to be defined"
  errors across dependent files — treat the *first* error as the real one.