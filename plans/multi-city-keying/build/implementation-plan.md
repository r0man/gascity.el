---
schema: gc.build.plan.v1
workflow:
  id: ga-rv5
  formula: build-from-requirements
methodology:
  pack: gascity
  name: planning-base
producer:
  formula: build-from-plan-base
  stage: plan
  attempt: 1
status: draft
plan_slug: multi-city-keying
phase: plan
rig: gascity.el
rig_root: /home/roman/workspace/gascity.el
trace:
  upstream:
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved multi-city-keying requirements this plan implements"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
    - path: plans/multi-city-keying/build/requirements-input.md
      hash: sha256:a08cc8c6a87f11f0b6e558f5ac4565498879b3bc65576c9485399ad03d92eae0
      title: "The approved requirements draft the requirements artifact restructured (upstream hash preserved)"
    - path: lisp/gascity-remote.el
      hash: git:3fa83997ca1689e9023aaf57a31acf76743c5fa7
      title: "gascity-remote-buffer-name, the buffer-name keying scheme this plan re-keys to the city root"
    - path: lisp/gascity-context.el
      hash: git:cac32df3638547f32e7361ccdcf7f2cf1150aefb
      title: "gascity-context--rigs-cache / --rigs-key, clear-cache, the view factory and the city-root resolution the shared key helper builds on"
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

# Implementation Plan: Per-city keying — multiple cities in one Emacs

## Summary

Re-key every city-scoped identity in gascity.el from the **remote prefix**
(host) to the **city root** (host + city path), so two cities on one host —
the standing `emacs-city`/`bright-lights` pair — get independent view
buffers, independent rig-list memos, and independent eldoc bead-id
prefixes, while single-city-per-host users see no behavior change.

The implementation is deliberately small: one new shared key helper
(`gascity-context-scope-key`), one re-keyed cache (`gascity-context--rigs-cache`
via `gascity-context--rigs-key`), one backward-compatible extension of the
buffer-name splicer (`gascity-remote-buffer-name` gains an explicit
qualifier argument), and migration of the two naming call sites — the view
factory `gascity-view-get-buffer-create` and the terminal attach buffer —
onto the one scheme. Everything else (refresh cadence, `gascity-context--root-cache`,
beads.el store scoping via `default-directory`) is unchanged. No new
dependencies, no changes outside gascity.el.

**Decisions the plan records** (the requirements' Open Questions, resolved
here; no human gate is required — the workflow root records
`interaction_mode: interactive` and no step below needs interactive input):

- **D1 — Buffer-name scheme.** One qualifier segment spliced before the
  trailing `*` of the base name, exactly as today's remote qualification
  does, with the qualifier being the **governing city root** when DIR is
  inside a city. Picked shapes (REQ-001, REQ-002, REQ-013):

  | DIR context | Buffer name |
  |-------------|-------------|
  | local city `/home/roman/emacs-city` | `*gascity-status@/home/roman/emacs-city/*` |
  | remote city `/ssh:localhost:/home/roman/bright-lights` | `*gascity-status@/ssh:localhost:/home/roman/bright-lights/*` |
  | local, outside any city | `*gascity-status*` (unchanged) |
  | remote, outside any city (`/ssh:u@h:`) | `*gascity-status@/ssh:u@h:*` (unchanged) |

  The splice shape is the existing one (`@…` before the trailing `*`), so
  remote cities stay host-qualified and recognizable under the same
  syntax users see today; the only change is *what* gets spliced for
  in-city directories (city root instead of bare remote prefix — for a
  remote city the root already embeds the TRAMP prefix, so the name
  carries both host and city). Distinctness, stability, and
  recognizability follow: two same-host cities differ in the path part,
  two cities under one TRAMP connection differ in the path part, and a
  remote city is distinguishable from a local one by the `ssh:` prefix
  inside the qualifier.

- **D2 — Key-helper placement.** `gascity-context-scope-key` lives in
  `gascity-context.el` (it must call `gascity-context-city-root`, and
  `gascity-remote.el` cannot require `gascity-context.el` without a
  load-order cycle — `gascity-context.el` already requires
  `gascity-remote.el`). It returns the city root (a TRAMP-qualified
  directory string) when DIR is inside a city, else the remote prefix
  (`""` for local) — the fallback the requirements name for REQ-002/REQ-009.
  It never spawns gc: it reads the memoized `gascity-context--root-cache`
  walk only.

- **D3 — Rigs-memo key semantics.** `gascity-context--rigs-key` returns
  `gascity-context-scope-key`'s value. Because a city root is a fully
  TRAMP-qualified file name, the city-root key *subsumes* the remote
  prefix (REQ-005's "city root + remote prefix"): no two distinct
  (city root, remote prefix) pairs can collide on the key, and out-of-city
  directories keep today's host-level keying. This is recorded here as the
  plan's reading of REQ-005; the per-city partition property it demands is
  what the tests assert (two same-host cities hold two entries; a
  prefix-less list never replaces a prefixed one *within a city* — the
  existing protection in `gascity-rigs-remember` becomes per-city
  automatically because it compares within one key).

- **D4 — Memo invalidation.** Unchanged: the memo still fills from `gc rig
  list` / `gc status` payloads on view refresh (`g` / explicit refresh) and
  clears via `gascity-context-clear-cache`. Re-keying only partitions
  entries per city; REQ-006/REQ-007 hold as today. `gascity-context-clear-cache`
  already `clrhash`es the whole table, so it clears every city key's entry
  (REQ-008) — no code change, one new test.

- **D5 — Formula-cache integration point.** The formula-sling-ui caches
  have **not** landed (verified: no formula-cache module under `lisp/`),
  so REQ-010 applies: this work ships the shared helper and records the
  integration point — the formula catalog and per-formula recipe caches
  MUST key by `gascity-context-scope-key` (same helper, one API), recorded
  in the `gascity-context.el` module commentary so the formula work adopts
  it without a second keying scheme.

## Current System

All three defects live in two modules; every view buffer is created through
the single factory `gascity-view-get-buffer-create`
(`lisp/gascity-context.el`), and the rig memo has one key function and two
readers.

**Call-site inventory** (complete; nothing else keys city-scoped state):

| Call site | File | Current key | Defect |
|-----------|------|-------------|--------|
| `gascity-remote-buffer-name` | `lisp/gascity-remote.el` | remote prefix; local DIR unqualified | two local cities share `*gascity-status*`, every list, compose, dry-run buffer |
| `gascity-view-get-buffer-create` | `lisp/gascity-context.el` | (delegates to the above) | re-pins the surviving shared buffer's `default-directory` to the new city; old view's timer then polls the wrong city |
| `gascity-terminal-attach-tmux` | `lisp/gascity-terminal.el` (~line 626) | calls `gascity-remote-buffer-name` directly | attach buffers key per host only; the one call site *outside* the factory |
| `gascity-context--rigs-key` | `lisp/gascity-context.el` | remote prefix (`""` local) | whichever city's `gc rig list` ran last serves every city on the host |
| `gascity-rigs-remember` / `-cached` / `-cached-prefixes` | `lisp/gascity-context.el` | via `--rigs-key` | same cross-city contamination; eldoc prefixes, terminal attach, view creation resolve the wrong rigs |
| `gascity-beads--rig-store-cached`, `-bead-path-cached` | `lisp/gascity-section.el` | ride on `gascity-rigs-cached` | fixed transitively once the memo is re-keyed |

**What is already correct and must not change** (REQ-006, REQ-012, TS-6):
`gascity-context--root-cache` (per start dir, nil cached too);
`gascity-context-pin-directory` (pins to the governing city root — correct
once buffers stop colliding); the single `gascity-context-city` override
(honored by `gascity-context-city-root`, consulted first, never cached);
the prefix-less-never-replaces-prefixed guard in `gascity-rigs-remember`;
`gascity-remote-localize-path`, ssh-argv, executable and terminfo caches
(host-scoped by nature). beads.el's store scoping rides on
`default-directory`, which stays correctly pinned per city.

**Existing tests that constrain the scheme:**
`gascity-test-remote-buffer-name` (2-arg host-only contract must keep
passing), `gascity-test-rigs-cached-never-spawns` (cold-stays-cold +
prefix protection, currently asserting per host — extended, not weakened),
`gascity-test-agent-attach-passes-rig-store` (attach store resolution from
the memo).

## Proposed Implementation

Order matters only for compile-cleanliness: the helper first, then its
consumers. All edits are in `lisp/gascity-context.el`,
`lisp/gascity-remote.el`, `lisp/gascity-terminal.el`,
`lisp/test/gascity-test.el`, plus one `docs/qa/` report. No new
dependencies; no changes to beads.el or gc.

### Step 1 — `gascity-context-scope-key` (gascity-context.el)

New function, the one city-scoped key API:

```elisp
(defun gascity-context-scope-key (&optional dir)
  "Return the city-scoped key for DIR (default `default-directory').
The governing city root when DIR is inside a city (a TRAMP-qualified
absolute directory string), else DIR's remote prefix (\"\" for local).
Never spawns gc — the city-root walk is the memoized
`gascity-context--root-cache' lookup.  This is the ONE keying identity
for city-scoped caches and buffer names; document any new cache keyed
by it here in this commentary (first consumer outside this file: the
formula catalog/recipe caches, plans/formula-sling-ui)."
  (or (gascity-context-city-root dir)
      (file-remote-p (or dir default-directory)) ""))
```

Update the `;;; Commentary:` of `gascity-context.el`: replace the
"keyed by remote prefix" description of the rig memo with the city-root
scheme (D1/D2/D5), stating that `gascity-remote-buffer-name`'s qualifier
and `gascity-context--rigs-key` both derive from
`gascity-context-scope-key` — the one keying scheme (REQ-003).

### Step 2 — Re-key the rig memo (gascity-context.el)

`gascity-context--rigs-key` body becomes `(gascity-context-scope-key dir)`;
update its and `gascity-context--rigs-cache`'s docstrings (key = city root,
which embeds the remote prefix; `""` only for a local non-city directory).
No change to `gascity-rigs-remember` (its prefix protection now holds per
city key automatically), `gascity-rigs-cached`, `-cached-prefixes`,
`gascity-beads--rig-store-cached` or `-bead-path-cached` — they all go
through the key function or the memo. `gascity-context-clear-cache` needs
no change (whole-table clear already covers every city key); assert it in
tests (D4, REQ-008).

### Step 3 — Buffer-name qualifier (gascity-remote.el)

Extend `gascity-remote-buffer-name` with an explicit QUALIFIER argument:

```elisp
(defun gascity-remote-buffer-name (base &optional dir qualifier)
  "Return BASE qualified by QUALIFIER, or by DIR's remote prefix.
QUALIFIER, when non-nil, is spliced in verbatim — the view factory passes
the governing city root (`gascity-context-scope-key').  Without QUALIFIER
the behavior is today's host-only qualification (remote prefix, local
unchanged), which the factory uses outside any city."
  (let ((qualifier (or qualifier (file-remote-p (or dir default-directory)))))
    (cond ((not qualifier) base)
          ((string-suffix-p "*" base)
           (format "%s@%s*" (substring base 0 -1) qualifier))
          (t (format "%s@%s" base qualifier)))))
```

The 2-arg contract is byte-identical to today (existing tests keep
passing). Update the "Buffer identity" block of `gascity-remote.el`'s
Commentary to name the city root as the qualifier the factory passes and
point at `gascity-context-scope-key` as the scheme owner.

### Step 4 — Re-key the view factory (gascity-context.el)

`gascity-view-get-buffer-create` computes the city root once and reuses it
for pinning *and* naming (one memoized walk, no extra file I/O):

```elisp
(let* ((root (gascity-context-city-root dir))
       (dir (or root (file-name-as-directory
                      (expand-file-name (or dir default-directory)))))
       (buf (get-buffer-create
             (gascity-remote-buffer-name
              base dir (or root (file-remote-p dir))))))
  ...)
```

Inside a city the qualifier is the city root — local cities included
(REQ-001, D1); outside any city it degrades to the remote prefix or nil,
preserving today's host-only naming (REQ-002). Pinning, project install,
and eldoc-prefix wiring keep their current form (they already resolve via
the pinned dir). Document in the factory's docstring that this is the one
naming entry point and the terminal attach buffer goes through the same
scheme (Step 5).

### Step 5 — Terminal attach buffers (gascity-terminal.el)

`gascity-terminal-attach-tmux` (~line 626) currently calls
`(gascity-remote-buffer-name (format "*gc-agent-%s*" session))` with no
DIR — host-only by accident. Replace with the same derivation as the
factory (read the city root of `default-directory`, pass it as QUALIFIER,
fall back to the remote prefix). Do **not** route the attach buffer
through `gascity-view-get-buffer-create`: attach buffers pin their own
`default-directory` (DIR re-prefixed for the host) and install their own
project/eldoc wiring afterwards. Update the docstring's "host-qualified"
sentence to "city-qualified".

### Step 6 — Tests (lisp/test/gascity-test.el)

House convention: stub the gc boundary with `cl-letf` on
`gascity-reader-run` / `gascity-command-rig-list!`; no live gc in unit
tests. New tests (all `gascity-test-*`):

- `gascity-test-scope-key-per-city` — `gascity-context-scope-key` is
  distinct for `/home/roman/emacs-city/…` and `/home/roman/bright-lights/…`
  (temp dirs with `city.toml`, `default-directory` bound), equals the
  remote prefix for a remote dir outside any city, `""` for a local dir
  outside any city, and honors the `gascity-context-city` override
  (REQ-011, REQ-014).
- `gascity-test-buffer-name-per-city` — factory-level names: two local
  cities get distinct names (D1 table shapes); a remote city under
  `/ssh:u@h:` carries the full city root, distinguishable from a local
  one; outside any city the 2-arg host-only shapes of
  `gascity-test-remote-buffer-name` still hold (REQ-002, REQ-013).
- `gascity-test-rigs-memo-per-city` — `gascity-rigs-remember` + `-cached`
  for two local cities and for two cities under one TRAMP prefix: distinct
  keys, distinct values, identical rig lists in both cities do not evict
  each other, a prefix-less list in city A never blanks city B's prefixed
  entry (nor its own — existing protection re-asserted per city), and the
  whole thing is cold for a third city (REQ-005, REQ-006, REQ-007, REQ-014).
- `gascity-test-clear-cache-cities` — after remembering rigs under two
  city keys, `gascity-context-clear-cache` leaves both cold (REQ-008).
- `gascity-test-override-keys-by-overridden-root` — with
  `gascity-context-city` bound to city B's root, the factory returns a
  buffer keyed under B's root, distinct from the naturally-resolved A
  buffer (REQ-011).
- `gascity-test-rigs-cached-never-spawns` — extend with a second-city
  assertion (cold memo in city B while city A is warm; no gc spawn from
  any read path).

Existing tests that must keep passing unchanged in meaning:
`gascity-test-remote-buffer-name` (2-arg contract),
`gascity-test-remote-localize-path`, `gascity-test-agent-attach-passes-rig-store`,
and the rest of the suite. Tests that bind `default-directory` to
`/ssh:u@h:/city/` for memo isolation keep working (out-of-city remote dirs
still key per host).

### Step 7 — E2E pass and QA report

Per AGENTS.md "Remote test city & end-to-end testing" (REQ-015, AC-4):
fresh Emacs inside tmux (`tmux new-session -d -s gce-e2e 'emacs'`), open
`/ssh:localhost:/home/roman/bright-lights` **and** local `emacs-city`
simultaneously, and verify: two `gascity-status` dashboards side by side
with independent refresh; rig dashboards and session lists per city; eldoc
prefix narrowing per city after visiting both; a sling dry-run / compose
buffer per city. Record the run (commands, observations, deviations) in
`docs/qa/<date>-multi-city-keying.md`. No ERT-only claim of AC-4.

### Step 8 — Gate

`scripts/gate.sh` (whole-package compile with `--warnings-as-errors` +
full ERT suite) — REQ-016. Commit subject: `fix(context): key views and rig memo by city root, not remote prefix`, body citing DESIGN.md §4.3 conventions and the requirements artifact.

## Non-Goals

- No changes to beads.el or the gc CLI.
- No city-switching UI (a transient listing `gc cities`); natural
  follow-up, tracked separately.
- No per-city customization beyond keying (no per-city faces, refresh
  intervals, or timers).
- No multiple simultaneous `gascity-context-city` override values (REQ-012).
- No change to `gascity-context--root-cache` semantics (TS-6).
- No formula-cache implementation here — only the shared helper and the
  recorded integration point (REQ-010; the caches have not landed).
- No change to refresh cadence or memo invalidation timing (D4).
- No changes outside gascity.el; no new dependencies; no buffer-rename
  migration shims for existing single-city sessions (a stale pre-upgrade
  buffer is simply an orphan until closed — single-city users are
  unaffected per REQ-013 because their names are unchanged).

## Verification

1. **Unit (REQ-014).** `eldev test` — the new per-city tests above green;
   `gascity-test-remote-buffer-name` and the existing remote/memo suite
   pass unchanged.
2. **Gate (REQ-016, AC-5).** `scripts/gate.sh` passes from a clean tree
   (whole-package byte-compile with `--warnings-as-errors` catches any
   missed `declare-function` across the re-keyed call sites).
3. **E2E (REQ-015, AC-4).** The tmux-Emacs dual-city pass of Step 7,
   recorded in `docs/qa/`, is the acceptance gate for AC-1/AC-2/AC-4
   end-to-end — both cities' dashboards, lists, rig dashboards, eldoc
   prefixes and compose buffers coexisting without re-pinning or
   wrong-city data.
4. **Traceability check.** Every AC-1…AC-5 maps to the steps above:
   AC-1 → Steps 1–4 + 6 (distinct names, no re-pin, override), AC-2 →
   Steps 1–3 + 5 + 6 (per-city memo, cold stays cold, clear-cache, shared
   helper), AC-3 → Steps 3–6 (one scheme, module commentary, remote tests
   green, single-city names unchanged), AC-4 → Step 7, AC-5 → Step 8.

## Traceability

Every upstream identifier and its disposition in this plan.

| ID | Status |
|----|--------|
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |

## Assumptions

- The `git:` upstream hashes record the blob hashes of
  `lisp/gascity-remote.el` and `lisp/gascity-context.el` at the approved
  requirements (`git rev-parse HEAD:<path>`, verified against the
  requirements front matter at plan time); the implementation step
  re-checks them before coding so drift is caught early.
- `plans/formula-sling-ui/` exists but its implementation has not landed
  in `lisp/` (no formula-cache module); REQ-010 is therefore the
  governing requirement for the coordination clause.
- The tmux-Emacs e2e environment (`bright-lights` over
  `/ssh:localhost:`, local `emacs-city`) is available as described in
  AGENTS.md; if `bright-lights` is unreachable at e2e time, that is an
  AC-4 blocker to record in the QA report, not a plan change.
- PyYAML is available to the artifact validator (it validated the
  requirements artifact of this same workflow).

## Risks

- **Buffer-name churn for remote single-city users.** A remote *city*
  view's name changes from `*gascity-status@/ssh:host:*` to
  `*gascity-status@/ssh:localhost:/home/roman/bright-lights/*` —
  recognizable, still host-qualified, and the existing tests keep the
  non-city 2-arg contract; the only regression surface is user code
  hard-coding the old remote-city name (none in-tree; noted for the QA
  report).
- **Extra `city.toml` walk on naming paths.** Mitigated: the factory
  already walks for pinning, and Step 4 computes the root once per call;
  `gascity-context-scope-key` for the memo path rides the same memoized
  `gascity-context--root-cache` — no new synchronous I/O class, and over
  TRAMP no new round trips beyond what pinning already paid.
- **Cold-path regression (REQ-007).** The shared helper must not be
  wired to anything spawning gc; the extended
  `gascity-test-rigs-cached-never-spawns` (spawn = error) is the tripwire.
- **Second naming call site drift (terminal).** Step 5 removes the one
  direct `gascity-remote-buffer-name` caller outside the factory; the
  gate's whole-package compile plus a test asserting attach buffer naming
  per city keeps it from regrowing.
