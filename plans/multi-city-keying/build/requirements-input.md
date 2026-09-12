---
plan_slug: multi-city-keying
phase: requirements
rig: gascity.el
rig_root: /home/roman/workspace/gascity.el
artifact_root: /home/roman/workspace/gascity.el/plans
status: approved
created_at: 2026-09-10T15:10:00Z
updated_at: 2026-09-10T15:10:00Z
---

# Requirements: Per-city keying — multiple cities in one Emacs

## Problem Statement

gascity.el resolves and executes against the right city per directory, and
coexists with a remote city on a *different host* (buffer names are
qualified with the TRAMP remote prefix). But all city-scoped keying — view
buffer names and the rig-list memo — uses the **remote prefix** (`file-remote-p`)
as its key, i.e. it distinguishes hosts, not cities. Two cities on the
**same host** — the common case, and exactly the standing setup
(`emacs-city` at `/home/roman/emacs-city` and `bright-lights` at
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

## Solution

Make the **city root** the keying identity for everything city-scoped. The
city root already encodes the host (its TRAMP prefix) *and* the city
(distinct path), so keying by it subsumes the current behavior for remote
cities while fixing same-host cities:

1. **Buffer names.** `gascity-remote-buffer-name` (or its caller
   `gascity-view-get-buffer-create`, whichever keeps the layering clean)
   qualifies BASE with the city root governing DIR when DIR resolves to a
   city (including nil/empty remote prefix — two local cities must get
   distinct names, e.g. `*gascity-status*/home/roman/emacs-city*`);
   outside any city keep today's host-only qualification. Keep the scheme
   single: one function decides the name, every view goes through
   `gascity-view-get-buffer-create`.

2. **City-scoped caches.** `gascity-context--rigs-cache` (and its
   `--rigs-key`) keys by city root + remote prefix instead of remote prefix
   alone; cities with identical rig sets must not evict each other, and a
   city with no rigs cached stays cold (never spawn on the UI path).
   `gascity-context-clear-cache` clears both keys' worth.

3. **Formula caches.** The formula-sling UI's catalog and recipe caches key
   by the same city-root identity (coordinate with the formula-sling-ui
   work — same key helper, one shared `gascity-context` API such as
   `gascity-context-scope-key` returning the city root or the remote
   prefix fallback).

4. **Per-city override.** Supporting simultaneous distinct overrides is out
   of scope; the single `gascity-context-city` override stays, but views
   opened under it must still key by the overridden root so two override
   values used at different times do not share buffers.

5. **No behavior change for single-city users** whose cities are one per
   host: the remote-prefix qualification for remote cities remains
   (optionally replaced by the city-root form — pick one scheme, document
   it in the module commentary, and migrate every caller).

The implementation is confined to gascity.el (`gascity-remote.el`,
`gascity-context.el`, plus the formula cache call sites from
formula-sling-ui if it has landed). beads.el is untouched: its store
scoping already rides on `default-directory`, which stays correctly pinned
per city.

## User Stories

- As a user with `emacs-city` and `bright-lights` both on localhost, I open
  `M-x gascity-status` from files in each city and see **two independent
  dashboards side by side**, each refreshing its own city forever.
- As a user on a remote host with two city directories, the same holds
  across one TRAMP connection.
- As a user jumping between cities, eldoc in each city's views narrows to
  that city's bead-id prefixes, and terminal attach resolves that city's
  rigs — never the last-visited city's.
- As a user of the formula sling UI, the formula catalog I browse in
  `bright-lights` is `bright-lights`' catalog, not `emacs-city`'s cached
  copy.

Acceptance criteria:

- Two views of the same kind for two same-host cities coexist with distinct
  buffer names; neither re-pins the other's `default-directory`.
- Rig memo, eldoc prefixes, and (if landed) formula caches are per city —
  verified by unit tests asserting distinct keys/values for two local dirs
  in different cities and for two cities under one TRAMP prefix.
- A remote city's buffer naming keeps working (existing remote tests pass);
  one documented keying scheme across all call sites.
- The multi-city flow is exercised in the tmux-Emacs e2e pass against
  `/ssh:localhost:/home/roman/bright-lights` *and* the local `emacs-city`
  simultaneously (see AGENTS.md "Remote test city & end-to-end testing").
- `scripts/gate.sh` passes.

## Out Of Scope

- No changes to beads.el or the gc CLI.
- No city-switching UI (a transient listing `gc cities` to jump between
  cities) — a natural follow-up once keying is correct, tracked separately.
- No per-city customization/state beyond the keying fix (no per-city
  faces, no per-city refresh intervals).
- Multiple simultaneous `gascity-context-city` override values.

## Other Notes

- The rig memo's "a prefix-less list never replaces a prefixed one" rule
  must survive the re-keying (same protection per city, not globally).
- `gascity-context--root-cache` (per start dir) is already correct and must
  not change.
- Buffer-name scheme choice (city-root splice vs separate qualifier) is an
  implementation-plan decision; requirement is only that same-host cities
  get distinct, stable, recognizable names and remote cities remain
  distinguishable from local ones.
- This work depends on nothing from formula-sling-ui except the cache
  call-site coordination; the two may proceed in parallel (different
  modules) with a shared key helper as the integration point.
