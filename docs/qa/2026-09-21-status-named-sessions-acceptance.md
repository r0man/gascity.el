# gascity-status named sessions — tmux-Emacs TRAMP acceptance pass

- Date: 2026-09-21
- Item: WI-4 ("Acceptance pass: gate, tmux-Emacs TRAMP e2e, QA report") of
  the gascity-status named-sessions workflow (root `ga-wi6z`, drain root
  `ga-x86d`, source anchor bead `ga-3g8w`); worktree
  `worktrees/ga-3g8w` at the feature tip `d694b59` (test(status): cover
  named-session rendering and read-failure isolation) on top of
  `31332d5` (section) and `9f1fac5` (domain synthesis).
- Environment: fresh `emacs -nw -Q` inside tmux (`gce-e2e`), package
  loaded from the item worktree with the sibling beads.el checkout and
  the Eldev-resolved deps (transient 0.13.8, sesman 0.3.2, vui 1.4.0,
  compat, cond-let) on the load path; every emacs/tmux call wrapped in
  `timeout(1)` via `scripts/e2e-harness.sh`; `emacsclient --eval` probes
  against a private `server-name` socket.
- Cities: local **emacs-city** (`/home/roman/emacs-city`, controller up,
  mayor awake) and remote **bright-lights** opened over TRAMP as
  `/sshx:localhost:/home/roman/bright-lights` (the `sshx` method with its
  own TRAMP connection, per the known plain-`ssh` ControlPath contention
  on this host — prior e2e F4).

## What was exercised and observed

### 1. Gate

`scripts/gate.sh` from the item worktree root (whole-package
`eldev compile --warnings-as-errors` + full ERT): **PASS** — compile
clean, then 303/303 tests, 0 unexpected.

### 2. Local emacs-city — CLI fidelity comparison (REQ-001)

`gascity-status` opened with `default-directory` pinned to
`/home/roman/emacs-city/` → `*gascity-status@/home/roman/emacs-city/*`.
Buffer text at the moment of capture:

```
Named sessions
  core.control-dispatcher awake
  mayor awake
  mode unavailable from gc JSON (gce-8ey)
```

`gc status` at the same moment (seconds apart, no state change between):

```
Named sessions:
  mayor                   awake (always)
```

- **Mayor row matches**: `mayor` is listed awake, from the same
  `gc session list --json` row (`name` == `template` == `mayor`,
  city-scoped, `state` active) the CLI derives from; the row carries the
  enriched `gascity-agent` text properties (work-dir, session name,
  socket) so the standard action keys apply, exactly like a City-block
  agent row.
- **Mode gap, as planned**: gc 1.4.2 exposes no `mode` in any JSON
  surface, so the row renders without the `(always)` suffix and the
  section carries the single dim footnote `mode unavailable from gc
  JSON (gce-8ey)` — the documented residual fidelity gap (REQ-001's
  fallback clause). The moment gc fills a mode field the suffix renders
  (unit-pinned by
  `gascity-test-status-named-sessions-row-asleep-and-mode`).

### 3. False-positive trade-off — now observed, not theoretical (REQ-001 caveat)

The plan asserted "neither acceptance city exhibits one" false positive.
**The local pass disproves that**: emacs-city's
`core.control-dispatcher` session is city-scoped with `name` ==
`template` (`core.control-dispatcher`), so the derivation classifies it
as a named session and the dashboard prints
`core.control-dispatcher awake` where the CLI prints only `mayor`. The
CLI's `gc status` recognizes it as an infrastructure agent, not a
`[[named_session]]` — the distinction lives only in gc's config state,
which no `--json` payload exposes. This is precisely the accepted
trade-off from the requirements ("a plain city agent whose materialized
session carries name == template"): the dashboard renders one extra row
(a false positive), never a missing one. The row is still truthful —
that session exists and is awake. Recorded here as the standing
behavior; a future gc JSON that distinguishes named sessions removes it.

### 4. TRAMP parity — bright-lights (REQ-004, REQ-005 AC-5)

`gascity-status` opened at `/sshx:localhost:/home/roman/bright-lights/`
→ separate host-qualified buffer
`*gascity-status@/sshx:localhost:/home/roman/bright-lights/*` (the local
dashboard stayed mounted beside it). Buffer text:

```
Named sessions
  mayor awake
  mode unavailable from gc JSON (gce-8ey)
```

`gc status` over ssh at the same moment (partial-status probe timeout on
the agents block, but the named-sessions block printed):

```
Named sessions:
  mayor                   awake (always)
```

The remote city's own payload (`gc session list --json` over TRAMP:
one row, `mayor`, city-scoped, name == template, active) derives exactly
one named session — **no false positive on bright-lights**. The section
renders from the remote city's data with the remote city's identity;
buffer host-qualification and `default-directory` pinning behaved as on
every other remote view.

### 5. Grep-level review (REQ-002, REQ-005 AC-2)

- No reading of `city.toml`, `.gc/system/`, or token files: the only
  matches for those strings in `gascity-domain.el` / `gascity-status.el`
  are comments (the REQ-002 rationale comment and the docstring's
  "state token" wording).
- No new gc call site: `gascity-reader.el` was untouched by the feature
  commits (`9f1fac5`, `31332d5`, `d694b59`); the derivation is a pure
  function over the already-decoded `gc session list --json` rows the
  dashboard already fetches.

## Verdict

**PASS.** The `Named sessions` block renders with CLI fidelity in both
acceptance cities from JSON-derived data alone; the two documented
residual gaps hold exactly as designed:

| Gap | Status |
| --- | --- |
| `(mode)` suffix | not derivable from gc 1.4.2 JSON; gap footnote renders until gc fills the field |
| Never-materialized `[[named_session]]` | invisible (no session row → no JSON surface) |
| name == template false positive | **observed** on emacs-city (`core.control-dispatcher` extra row, absent on bright-lights); accepted trade-off, recorded above instead of the plan's "neither city exhibits one" |
