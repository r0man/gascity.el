# Bead-id eldoc by prefix — live acceptance (2026-11-06)

Docs/QA item `ga-uq5pl` (plan
`plans/beads-eldoc-prefix/implementation-plan.md`, §H item 5; requirements
REQ-016, REQ-017, AC-5).

**Status: PASS on the merged W1→W5 tree.**  The earlier pass ran on a QA-only
composite of the then-uncommitted item worktrees and marked the user-facing
half "blocked at the merge boundary" (`C-c b` binding, live agent transcript,
mouse hover).  This pass re-ran those legs on the real merged tree, with the
review-fix commits folded in, and they pass except mouse hover, which remains a
recorded headless limitation (§E).  The old composite numbers are kept in
§Earlier pass for history; they are superseded by §F.

## Merged tree under test

Local branch `beads-eldoc-integration` at `8c7cad5`, based on `origin/main`
`994b42f`, with W1→W5 cherry-picked in order and the review-synthesis merge
resolution applied:

| Item | Commit | Note |
| --- | --- | --- |
| W1 map core (`ga-3cc7x`) | `9058265` | per-city prefix→store map, tests, manual options |
| W2 install path (`ga-ewqlp`) | `2022e35`, `eee4e69`, `a2db778`, `0ff8d22` | one installer; S1 cold-reset handler/hook + ERTs; summary command fix (S5) |
| W3 caller migration (`ga-jaup5`) | `6d3ecfa`, `c01a7ff` | `C-c b`/reads through the map; S2 shared buffer-map rule + ERT |
| W4 refresh/invalidation (`ga-5bpu0`) | `4f1adce`, `cbec00b` | TTL/live/action invalidation; explicit clear drops maps; S3 negative-cache ERT |
| W5 docs and QA (`ga-uq5pl`) | `14e3531` | NEWS, manual section, this report |
| merge shape (`ga-tpj2y`) | `8c7cad5` | S6 conflict resolution; one hook section, direct buffer-local reads (S7 N1–N2) |

Conflict resolution follows review synthesis S6: W2 install + W3 resolver +
W4 invalidation sections concatenated in `lisp/gascity-beads-eldoc.el`, W2's
`gascity-test-terminal-beads-integrate` kept and W3's hunk for it dropped, W5
applied last.

## Method

Fresh non-graphical Emacs 31.1 (`emacs -nw -Q`) inside tmux session
`gce-eldoc-merged` (Emacs server of the same name), started and torn down
through `scripts/e2e-harness.sh` helpers (`timeout` on every tmux/emacsclient
call, session checked before every send/capture).  Load path:
`<merged-worktree>/lisp` → `~/workspace/beads.el/lisp` →
`~/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0`.  Batch Emacs with the
same load path for deterministic probes.  `load-prefer-newer` on throughout
(AGENTS.md: a stale `.elc` otherwise masks the merged sources).

Cities: local dogfood city `emacs-city` (rigs `ec` HQ, `be` beads.el, `ga`
gascity.el) and remote `/ssh:localhost:/home/roman/bright-lights` (rigs `bl`
HQ, `hw` hello-world).  No workflow was launched or mutated, no city
restarted, no `gc` change.

## A. AC-1 — per-id resolution and `C-c b` in a vui view (PASS)

`M-x gascity-dashboard` from `default-directory` `/home/roman/emacs-city/`:

```
buffer            *gascity: emacs-city@/home/roman/emacs-city/*
mode              gascity-dashboard-mode
scope             /home/roman/emacs-city/
cold prefixes     ("")
key C-c b         gascity-bead-show-at-point
map-ready (cold)  nil
warm prefixes     ("ec" "be" "ga")
```

Point on the stamped `ga-4hdav` row in **Needs you**:

```
(gascity-bead-at-point)                  => "ga-4hdav"
(gascity-beads-eldoc-store-for-id …)     => "/home/roman/workspace/gascity.el/"
```

Then `C-c b` sent as a tmux keystroke to the live session (not an elisp call):

```
opened buffer  *beads-show[gascity.el]/ga-4hdav do-work*
```

The id is a `gascity.el` rig bead shown in the `emacs-city` cockpit and it
opened in the gascity.el store while the view's `default-directory` is the
city root (AC-1, REQ-013).  The earlier pass's `C-c b` BLOCKED entry is
resolved: the merged key map reports `gascity-bead-show-at-point` and the
keystroke opens the rig store.

## B. AC-2 — live agent transcript, worktree capture and TRAMP (PASS)

### Live tmux transcript

A real terminal buffer attached to a live tmux session on the city's socket
(`qa-term`, a shell pane printing `agent transcript: ec-0yqc4 ga-4hdav
be-09wm3`):

```
buffer            *gc-agent-qa-term@/home/roman/emacs-city/*
mode              term-mode
scope             /home/roman/emacs-city/
prefixes          ("ec" "be" "ga")
key C-c b         gascity-bead-show-at-point
buffer text       agent transcript: ec-0yqc4 ga-4hdav be-09wm3
```

Eldoc on the `ga-` token (id from a rig other than the pane's city):

```
beads-eldoc--request-issue "ga-4hdav" => "ga-4hdav [closed]: do-work"
```

`C-c b` as a tmux keystroke, point on `ga-4hdav`, opened:

```
*beads-show[gascity.el]/ga-4hdav do-work*
```

`C-c b` on `be-09wm3` in the same pane opened:

```
*beads-show[beads.el]/be-09wm3 Finalize scope for Run preflight checks…*
```

The pre-existing `mayor` session was not re-attached for this pass: it is
already attached elsewhere and the spawned attach process exited
(`no sessions`) before showing a pane.  The `qa-term` terminal exercises the
identical attach path (same city socket, same `gascity-terminal-attach-map`,
same captured city), so the transcript leg is covered; the mayor pane itself
is still not part of the record.

### Worktree-pinned buffer (AC-2's original defect)

Batch probe, buffer `default-directory` `/home/roman/workspace/gascity.el/`
(the agent's worktree, outside the city tree), installed with the city:

```
scope               /home/roman/emacs-city/
default-directory   /home/roman/workspace/gascity.el/
prefixes            ("ec" "be" "ga")
resolver ec-0yqc4   /home/roman/emacs-city/
resolver ga-4hdav   /home/roman/workspace/gascity.el/
resolver be-09wm3   /home/roman/workspace/beads.el/
```

Echoes in that buffer:

```
ec-0yqc4 [open]:   graph.v2 drain closes succeeded on item root latch expansion, …
ga-4hdav [closed]: do-work
be-09wm3 [closed]: Finalize scope for Run preflight checks on the base branch
```

`C-c b` on each opened `*beads-show[emacs-city]/ec-0yqc4*`,
`*beads-show[gascity.el]/ga-4hdav*` and `*beads-show[beads.el]/be-09wm3*`
respectively — the worktree capture survives `default-directory` outside the
city tree.

### Remote city over TRAMP

Same Emacs, `(gascity-dashboard)` with
`default-directory` `/ssh:localhost:/home/roman/bright-lights/`:

```
buffer      *gascity: bright-lights@/ssh:localhost:/home/roman/bright-lights/*
scope       /ssh:localhost:/home/roman/bright-lights/
prefixes    ("bl" "hw")
store bl-   /ssh:localhost:/home/roman/bright-lights/
store hw-   /ssh:localhost:/home/roman/hello-world/

hover bl-bdj echo  bl-bdj [open]: Formula v2 step targets (gc.run-operator) fail
                   to resolve from HQ scope: 'unknown formulas v2 target'
tramp-list-connections before  1
tramp-list-connections after   1
```

Hovering opened no new TRAMP connection, and both remote prefixes resolved to
their host-localized stores (AC-2, REQ-008).

## C. AC-3 / AC-4 — cold start, in-place heal, unknown tokens (PASS)

Fresh batch process (`maps=0`) with a stamped `ga-4hdav` buffer for
`emacs-city`:

```
cold prefixes                       ("")
cold C-c b echo                     "Resolving bead stores…"
allowed-p "post-command"            nil
store-for-id "zz-abcde"             nil
map-ready after wait                ("ec" "be" "ga")
warm echo ga-4hdav                  "ga-4hdav [closed]: do-work"
```

The same buffer went from deny-all to the city's prefixes without a reopen
(the registry re-apply), and the plain-text `post-command` token and unknown
prefix never reach a store.  With `beads-eldoc--spawn` advised and a
known-prefix miss `ga-zzzzz`:

```
miss-1  pending  spawns=1
miss-2  cached   spawns=1
```

One lookup, then beads.el's negative cache (REQ-015).  The same contract is
now also pinned offline by the S3 ERT
(`gascity-test-beads-eldoc-known-prefix-miss-does-not-repeat`).

## D. AC-5 — merged-tree gates

| Check | Result |
| --- | --- |
| `make` (byte-compile, warnings as errors) | **PASS**, no warnings |
| `make check` (full ERT) | **PASS**, `Ran 1040 tests, 1040 results as expected, 0 unexpected` |
| `scripts/lint.sh` | **PASS**, exit 0 (package-lint unavailable locally; CI installs it) |
| `make -C doc` | **PASS**, `gascity.info` current, no makeinfo warnings |
| S1 guarded ERT | **ran, passed** (13/13 in `gascity-beads-eldoc-install-test.el`; not skipped on the merged tree) |
| S2 ERT | **passed** (`gascity-test-bead-show-at-point-buffer-map-outside-city`) |
| S3 ERT | **passed** (`gascity-test-beads-eldoc-known-prefix-miss-does-not-repeat`) |

## E. REQ-014 — mouse hover

**BLOCKED (headless), recorded, not silently skipped.**  `(display-graphic-p)`
is nil for the `emacs -nw` pass, so `eldoc-mouse-mode`/help-echo cannot be
exercised here.  Mouse hover calls the same `beads-eldoc-function` whose
buffer-local contract (per-id resolver + prefix allowlist) is verified in §A–C;
only the graphical event path is unverified.  Re-run in a graphical frame if
one is available in a later pass.

## Earlier pass (superseded)

The first pass ran on a QA-only composite assembled from the four item working
trees because none was merged: it verified the data plane, worktree capture
and TRAMP on that composite, and recorded `C-c b`, the live transcript and
mouse hover as deferred.  The composite gate showed 19 merge-shape failures
that were artifacts of composing unmerged item tests, not product defects.
Those deferred legs are the ones re-run above on `8c7cad5`; the composite
numbers must not be used as the shipped tree's result.

## Verdict

AC-1, AC-2, AC-3, AC-4 and AC-5 are verified on the merged W1→W5 tree,
including the `C-c b` halves, the live tmux transcript and the TRAMP boundary
(one connection before and after).  REQ-014 mouse hover remains a recorded
headless limitation with the same resolution path verified via the point path.
No new required finding was raised by this pass.
