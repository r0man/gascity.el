---
schema: gc.build.requirements.v1
workflow:
  id: ga-rv5
  formula: build-from-requirements
methodology:
  pack: gascity
  name: build-from-requirements
producer:
  formula: build-from-requirements-base
  stage: requirements
  attempt: 1
status: approved
plan_slug: multi-city-keying
phase: requirements
rig: gascity.el
rig_root: /home/roman/workspace/gascity.el
trace:
  upstream:
    - path: plans/multi-city-keying/build/requirements-input.md
      hash: sha256:a08cc8c6a87f11f0b6e558f5ac4565498879b3bc65576c9485399ad03d92eae0
      title: "The approved multi-city-keying requirements draft this artifact restructures"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
    - path: lisp/gascity-remote.el
      hash: git:3fa83997ca1689e9023aaf57a31acf76743c5fa7
      title: "The remote identity machinery this work re-keys: gascity-remote-buffer-name and the buffer-name keying scheme"
    - path: lisp/gascity-context.el
      hash: git:cac32df3638547f32e7361ccdcf7f2cf1150aefb
      title: "The city resolution and rigs memo whose keys must become per-city: gascity-context--rigs-cache, --rigs-key, clear-cache and the single gascity-context-city override"
  coverage:
    - id: AC-1
      status: covered
    - id: AC-2
      status: covered
    - id: AC-3
      status: covered
    - id: AC-4
      status: covered
    - id: AC-5
      status: covered
---

# Requirements: Per-city keying — multiple cities in one Emacs

## Problem Statement

gascity.el resolves and executes against the right city per directory, and
coexists with a remote city on a *different host* (buffer names are
qualified with the TRAMP remote prefix). But all city-scoped keying — view
buffer names and the rig-list memo — uses the **remote prefix**
(`file-remote-p`) as its key, i.e. it distinguishes hosts, not cities. Two
cities on the **same host** — the common case, and exactly the standing
setup (`emacs-city` at `/home/roman/emacs-city` and `bright-lights` at
`/home/roman/bright-lights`, both local; or two city directories under one
TRAMP connection) — collide:

- `gascity-remote-buffer-name` (`lisp/gascity-remote.el`) returns the base
  name unchanged for any local dir, so both cities share
  `*gascity-status*`, `*gascity-rig: …*`, every list view, compose and
  dry-run buffer. Opening the second city's view takes over the first
  city's buffer: `gascity-view-get-buffer-create` re-pins the surviving
  buffer's `default-directory` to the new city, so the two cities can never
  be viewed side by side, and any refresh timer the old view left running
  now silently polls the *other* city.
- `gascity-context--rigs-cache` is keyed by `gascity-context--rigs-key` =
  the remote prefix (`""` for local). Whichever city's `gc rig list` ran
  last is the memoized rig list for *every* city on that host:
  `gascity-rigs-cached-prefixes` then narrows beads.el's
  `beads-issue-id-prefixes` to the wrong city's bead prefixes (e.g.
  `emacs-city`'s `ec`/`be`/`ga` leak into `bright-lights` views whose
  prefixes differ), terminal attach and view creation resolve the wrong
  rigs, and rig dashboards can be keyed to the wrong store.
- `gascity-context-city` is a single global override variable — only one
  city can be forced at a time.
- The formula-sling UI work (plans/formula-sling-ui) introduces catalog and
  per-formula recipe caches "keyed by remote identity" — if that keying
  follows the existing remote-prefix pattern it reproduces the same
  cross-city contamination for formula metadata.

## W6H

**What.** Make the **city root** the keying identity for everything
city-scoped in gascity.el: view buffer names (`gascity-remote-buffer-name`
or its caller `gascity-view-get-buffer-create`), the rig-list memo
(`gascity-context--rigs-cache` / `--rigs-key`), and — in coordination with
the formula-sling-ui work — the formula catalog and recipe caches. The city
root already encodes the host (its TRAMP prefix) *and* the city (distinct
path), so keying by it subsumes today's remote-city behavior while fixing
same-host cities.

**Why.** Two cities on one host are the normal Gas City setup, and today
they cannot be viewed side by side: the second city's dashboard silently
takes over the first's buffer, re-pins its `default-directory`, and hijacks
its refresh timers; the rigs memo serves the last-visited city's rig list
(and bead-id prefixes) to *every* city on the host, corrupting eldoc,
terminal attach and view creation. This is silent wrong-city data, the
worst kind of bug for a porcelain whose entire job is showing gc's state
truthfully.

**Who.** Anyone running more than one city — the standing local pair
(`emacs-city` + `bright-lights`), and remote hosts hosting several city
directories under one TRAMP connection. Single-city-per-host users must see
no behavior change.

**Where.** `lisp/gascity-remote.el` (buffer naming), `lisp/gascity-context.el`
(rigs memo keys, clear-cache, the shared key helper), the formula-cache call
sites in formula-sling-ui if landed, ERT stubs in
`lisp/test/gascity-test.el`, and a `docs/qa/` e2e report. beads.el is
untouched: its store scoping already rides on `default-directory`, which
stays correctly pinned per city. The gc CLI is read, not changed.

**When.** After this artifact and its plan; the workflow runs autonomously
(interaction mode recorded in the plan). Nothing ships until
`scripts/gate.sh` passes and the tmux-Emacs TRAMP e2e pass has run against
both cities simultaneously.

**How.** Pick **one** keying scheme (city-root splice into buffer names vs
a separate qualifier), document it in the module commentary, and migrate
every call site to a single shared `gascity-context` API — e.g.
`gascity-context-scope-key` returning the city root, or the remote-prefix
fallback outside any city. Buffer names qualify BASE with the governing
city root (including nil/empty remote prefix, so two local cities get
distinct names); the rigs cache keys by city root + remote prefix and never
lets a prefix-less list replace a prefixed one *per city*.

**How much.** Re-keying of one naming function, one cache plus its key
helper, and their call sites, with tests. No new dependencies; no changes
outside gascity.el. The plan decides the exact buffer-name shape and the
key-helper placement (REQ-013); the requirement is only that same-host
cities get distinct, stable, recognizable names and remote cities remain
distinguishable from local ones.

## User Stories

- **US-1 — As a user with `emacs-city` and `bright-lights` both on
  localhost,** I open `M-x gascity-status` from files in each city and see
  **two independent dashboards side by side**, each refreshing its own city
  forever — neither re-pins the other's `default-directory`, and no stale
  timer polls the wrong city.
- **US-2 — As a user on a remote host with two city directories,** the same
  holds across one TRAMP connection: each city's views, rig dashboards and
  lists stay distinct and correct.
- **US-3 — As a user jumping between cities,** eldoc in each city's views
  narrows to *that* city's bead-id prefixes, and terminal attach resolves
  that city's rigs — never the last-visited city's memoized list.
- **US-4 — As a user of the formula sling UI,** the formula catalog I
  browse in `bright-lights` is `bright-lights`' catalog, not `emacs-city`'s
  cached copy.

## Technical Stories

- **TS-1 — As `gascity-remote-buffer-name`,** I am the one function that
  decides a view buffer's name. The city-root qualification lives in me (or
  in `gascity-view-get-buffer-create`, whichever keeps the layering clean —
  one decision, documented in the module commentary), so every view goes
  through a single scheme.
- **TS-2 — As `gascity-context--rigs-cache`,** my key becomes city root +
  remote prefix instead of remote prefix alone. Cities with identical rig
  sets must not evict each other, and a city with no rigs cached stays
  cold: a UI-path reader (`gascity-rigs-cached`) must never spawn gc.
- **TS-3 — As `gascity-context-clear-cache`,** I clear both keys' worth —
  the per-city keys and whatever legacy host-only entries survive the
  migration.
- **TS-4 — As the formula-sling-ui caches,** I adopt the same key helper
  (`gascity-context-scope-key` or equivalent) so catalog and recipe caches
  are per-city; the two work items may proceed in parallel (different
  modules) with the shared helper as the integration point.
- **TS-5 — As the ERT suite,** I assert distinct keys/values for two local
  dirs in different cities and for two cities under one TRAMP prefix, stub
  the gc boundary with `cl-letf` on the reader functions per the house
  convention, and keep the existing remote buffer-naming tests passing.
- **TS-6 — As the existing views,** I must not change behavior for
  single-city users whose cities are one per host: the remote-prefix
  qualification for remote cities remains recognizable under whichever
  scheme is chosen, and `gascity-context--root-cache` (per start dir) is
  already correct and must not change.

## Behavior Requirements

Requirement rows are the contract. `MUST` is binding; `SHOULD` is a default
the plan may override in writing.

### Buffer naming

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-001 | `gascity-remote-buffer-name` (or `gascity-view-get-buffer-create`, per the layering decision) MUST qualify BASE with the city root governing DIR when DIR resolves to a city — including a nil/empty remote prefix, so two local cities get distinct names (e.g. `*gascity-status*/home/roman/emacs-city*`). | AC-1 |
| REQ-002 | Outside any city, buffer naming MUST keep today's host-only qualification. | AC-3 |
| REQ-003 | Exactly one keying scheme MUST exist across every call site (status, rig, session, tabulated lists, compose, dry-run, terminal attach); the scheme MUST be documented in the module commentary and every caller MUST go through the single naming function. | AC-3 |
| REQ-004 | Two views of the same kind for two same-host cities MUST coexist with distinct buffer names, and opening one MUST NOT re-pin the other's `default-directory`. | AC-1 |

### City-scoped caches

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-005 | `gascity-context--rigs-cache` (and `gascity-context--rigs-key`) MUST key by city root + remote prefix, not remote prefix alone. | AC-2 |
| REQ-006 | The rigs memo MUST preserve the "a prefix-less list never replaces a prefixed one" protection per city, not globally. | AC-2 |
| REQ-007 | A city with no rigs cached MUST stay cold: UI-path readers (`gascity-rigs-cached`, eldoc prefix narrowing, attach) MUST never spawn gc. | AC-2 |
| REQ-008 | `gascity-context-clear-cache` MUST clear every city key's entry, not just one host's. | AC-2 |

### Formula caches (coordination)

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-009 | If the formula-sling-ui caches have landed, they MUST key by the same city-root identity via a shared `gascity-context` API (e.g. `gascity-context-scope-key` returning the city root, or the remote-prefix fallback outside any city); one key helper, one API. | AC-2 |
| REQ-010 | If formula-sling-ui has not landed, this work MUST still ship the shared key helper and record the integration point, so the caches adopt it without a second keying scheme. | AC-2 |

### Override and compatibility

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-011 | Views opened under a `gascity-context-city` override MUST key by the overridden root, so two override values used at different times do not share buffers or cache entries. | AC-1 |
| REQ-012 | Multiple simultaneous override values are out of scope; the single override variable MUST keep working unchanged. | AC-3 |
| REQ-013 | Single-city-per-host users MUST see no behavior change: remote cities remain host-qualified (under the one chosen scheme), and the plan MUST record the exact buffer-name shape it picked. | AC-3 |

### Verification

| ID | Requirement | Traces |
|----|-------------|--------|
| REQ-014 | ERT unit tests MUST assert distinct keys/values for two local dirs in different cities and for two cities under one TRAMP prefix (rigs memo, eldoc prefixes, and formula caches if landed), with the standard `cl-letf` reader stubbing; existing remote buffer-naming tests MUST keep passing. | AC-2, AC-3 |
| REQ-015 | The multi-city flow MUST be exercised in the tmux-Emacs e2e pass against `/ssh:localhost:/home/roman/bright-lights` **and** the local `emacs-city` simultaneously, per AGENTS.md ("Remote test city & end-to-end testing"), recorded in a `docs/qa/` report. | AC-4 |
| REQ-016 | `scripts/gate.sh` MUST pass. | AC-5 |

## Example Mapping

**Story:** a user opens `M-x gascity-status` in `emacs-city`, then in
`bright-lights`, and works in both — with neither city ever seeing the
other's data.

**Rule — the city root is the key.**
- *Example:* the two dashboards are named distinctly (e.g. `*gascity
  status <city root 1>*` / `*gascity status <city root 2>*` under the
  chosen scheme) and refresh their own cities forever.
- *Counter-example (a failure):* opening `bright-lights`' status renames or
  re-pins `emacs-city`'s buffer, whose timer now polls `bright-lights`.

**Rule — the rigs memo never crosses cities.**
- *Example:* after `gc rig list` runs for `emacs-city`, opening a
  `bright-lights` view eldocs `bright-lights`' bead prefixes, because the
  memo key includes the city root.
- *Example:* two cities with identical rig lists still hold two memo
  entries; one never evicts the other.
- *Counter-example (a failure):* a prefix-less `rig list` result for one
  city overwrites another city's prefixed entry.

**Rule — cold stays cold.**
- *Example:* before any explicit refresh, a freshly opened view in an
  uncached city runs no gc from the UI path; the rig memo simply has no
  entry for that city key.
- *Counter-example (a failure):* re-keying introduces a lookup that spawns
  gc synchronously during redisplay or eldoc.

**Rule — override keys by the overridden root.**
- *Example:* with `gascity-context-city` pointing at `bright-lights`, the
  opened status buffer and its rigs-memo entries live under
  `bright-lights`' key; later pointing the override at `emacs-city` opens a
  different buffer, not the cached `bright-lights` one.
- *Counter-example (a failure):* override-opened views share buffers with
  naturally-resolved views of another city.

**Rule — one scheme everywhere, including remote.**
- *Example:* a remote city over `/ssh:localhost:` keeps a host-qualified,
  city-distinguishable buffer name under the chosen scheme, and the
  existing remote tests pass unchanged in meaning.
- *Counter-example (a failure):* status dashboards use the new scheme while
  tabulated lists or compose buffers still key by remote prefix alone.

**Questions raised by the mapping** are carried in *Open Questions* below.

## Acceptance Criteria

The criteria below restate the approved input draft's acceptance bullets
(`AC-*`) so each is mechanically checkable, and name the requirements that
carry them.

1. **AC-1 — Same-host cities coexist.** Two views of the same kind for two
   same-host cities have distinct buffer names; neither re-pins the other's
   `default-directory`. *(REQ-001, REQ-004, REQ-011)*
2. **AC-2 — City-scoped state is per city.** The rig memo, eldoc bead-id
   prefixes, and (if landed) formula caches are keyed per city — verified
   by unit tests asserting distinct keys/values for two local dirs in
   different cities and for two cities under one TRAMP prefix. *(REQ-005,
   REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-014)*
3. **AC-3 — One scheme, remote-compatible, no single-city regression.**
   A remote city's buffer naming keeps working (existing remote tests
   pass); one documented keying scheme across all call sites. *(REQ-002,
   REQ-003, REQ-012, REQ-013, REQ-014)*
4. **AC-4 — Proven on both cities at once.** The multi-city flow is
   exercised in the tmux-Emacs e2e pass against
   `/ssh:localhost:/home/roman/bright-lights` *and* the local `emacs-city`
   simultaneously (see AGENTS.md "Remote test city & end-to-end testing").
   *(REQ-015)*
5. **AC-5 — The gate is green.** `scripts/gate.sh` passes. *(REQ-016)*

### Traceability

Every upstream identifier and its disposition in this artifact. `AC-*` are
the approved input draft's acceptance-criteria bullets; the behavioral
requirements above trace to them.

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |

## Out Of Scope

- **No changes to beads.el or the gc CLI.**
- **No city-switching UI** (a transient listing `gc cities` to jump between
  cities) — a natural follow-up once keying is correct, tracked separately.
- **No per-city customization/state beyond the keying fix** (no per-city
  faces, no per-city refresh intervals).
- **Multiple simultaneous `gascity-context-city` override values.**
- **No change to `gascity-context--root-cache`** (per start dir; already
  correct).

## Open Questions

None of these blocks the plan; this workflow runs without a human in the
loop, so each is a decision the plan stage must record.

- **Buffer-name scheme.** City-root splice into the existing name vs a
  separate qualifier segment — the plan picks one, documents it in the
  module commentary, and migrates every caller (REQ-003, REQ-013). The
  requirement is only distinctness, stability and recognizability, with
  remote cities distinguishable from local ones.
- **Key-helper placement.** Whether `gascity-context-scope-key` (or
  equivalent) lives in `gascity-context.el` and what it returns outside any
  city (remote prefix vs an error) is the plan's call, subject to REQ-009
  and REQ-002.
- **Cache invalidation for the rigs memo.** Whether re-keying changes when
  the memo refreshes (today: `g`/explicit refresh per view) is the plan's
  call; REQ-006 and REQ-007 must still hold.
- **Formula-sling-ui landing order.** If that work lands first, its caches
  adopt the shared helper here (REQ-009); if this lands first, the
  integration point recorded under REQ-010 governs.