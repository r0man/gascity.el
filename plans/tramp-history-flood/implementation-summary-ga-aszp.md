---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-ioaq
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
    - path: beads/ga-sfnj
      hash: bead:ga-sfnj
      ids:
        - ga-sfnj
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - REQ-004
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
  coverage:
    - id: ga-sfnj
      status: covered
    - id: REQ-004
      status: covered
    - id: AC-4
      status: covered
---

# Implementation Summary: W3 — HISTFILE=/dev/null for TRAMP inner shells

### Trace Coverage

| ID       | Status  |
| -------- | ------- |
| ga-sfnj  | covered |
| REQ-004  | covered |
| AC-4     | covered |

## Summary

Implemented plan section W3 (`plans/tramp-history-flood/implementation-plan.md`,
"HISTFILE=/dev/null for TRAMP inner shells", REQ-004 / AC-4) in the item
worktree `/home/roman/workspace/gascity.el/worktrees/ga-sfnj` at commit
`3e3fc20` on the item work branch:

1. `lisp/gascity-remote.el` — new *History hygiene* section:
   `gascity-remote-history-silencer` (`"HISTFILE=/dev/null"`),
   `gascity-remote-history-environment` (pure append helper: the silencer is
   appended to the environment, never rebound wholesale, so TRAMP's own
   default entries — `HISTORY=`, `ENV=''`, … — survive; idempotent), and
   `gascity-remote-silence-shell-history` (buffer-locally applies the
   override, no-op for a local directory). The docstring documents the
   truncation of an already-bloated `~/.tramp_history` as a user-run command.
2. `lisp/gascity-context.el` — `gascity-view-get-buffer-create` (the one view
   buffer factory, i.e. where gascity owns buffers) calls
   `gascity-remote-silence-shell-history` on the pinned buffer, re-applied on
   every call to heal re-pinned buffers. On a remote city this makes the
   environment TRAMP consults when spawning (`tramp-remote-process-environment`
   read in the spawning buffer) carry the override for every gc read a view
   issues, without touching the user's other TRAMP usage.
3. `lisp/test/gascity-test.el` — pure ERT
   `gascity-test-remote-connection-local-histfile-override`: asserts the
   append semantics over TRAMP's default environment, that the override
   reaches the environment of a buffer created by the factory on the mock
   remote connection with every default entry preserved, that the global
   value stays untouched, and that a local buffer gets no override.
4. `doc/gascity.texi` — new *TRAMP shell history hygiene* section in the
   Customization chapter: explains the `~/.tramp_history` growth
   (`tramp-histfile-override`), the scoped append override, the
   `tramp-remote-process-environment` recipe for users who want it everywhere,
   and the truncation of an existing bloated file as a user-run command.

Scoping decision: the plan asks for the override "in gascity-remote.el's
connection-local setup … scoped the same way the existing path/executable
connection-locals are scoped". Registering a criteria-registered
connection-local profile was rejected on purpose: file visits apply those
profiles to *every* remote buffer on the host (`hack-local-variables`), which
would leak the override into the user's non-gascity TRAMP usage — exactly
what the plan forbids. The path/executable connection-locals are scoped by
being read only at gascity's own invocation sites; the environment override
is scoped the same way, by being applied buffer-locally at gascity's own
buffer install site. `gascity-remote-history-environment` is the connection-
local-shaped pure core, unit-tested directly.

## Intended Behavior

- Every remote view buffer created through `gascity-view-get-buffer-create`
  carries a buffer-local `tramp-remote-process-environment` equal to TRAMP's
  current value plus one appended `HISTFILE=/dev/null` entry.
- TRAMP reads that variable in the buffer a remote process is spawned from,
  so the inner shells behind gascity's remote reads record no shell history;
  the host's `~/.tramp_history` stops growing from gascity usage.
- Append semantics: no default entry is lost or reordered; repeated
  application adds nothing.
- Scope: the global `tramp-remote-process-environment` — and therefore the
  user's other TRAMP buffers — is never modified; local gascity buffers get
  no buffer-local override at all.
- The workflow never edits or truncates the user's `~/.tramp_history`
  (REQ-003/REQ-004 counterexample clause); truncation is documented as a
  user-run command: `: > ~/.tramp_history`.

## Changed Files

All changes are in worktree `/home/roman/workspace/gascity.el/worktrees/ga-sfnj`,
commit `3e3fc20` (`feat(remote): HISTFILE=/dev/null for TRAMP inner shells
(ga-sfnj)`), item work branch `main`:

- `lisp/gascity-remote.el` — history hygiene section (silencer const, pure
  append helper, buffer-local application), module commentary bullet.
  sha256:6aae699f86a723522442c257f34e5cbdda2de8c7355bc37452f7a5e84abe3be4
- `lisp/gascity-context.el` — factory wiring + docstring update.
  sha256:0150ff5aa9a899feed9a88f3b0da8d3d79608aea7f8ec285eabf3f80f18ce002
- `lisp/test/gascity-test.el` — new ERT.
  sha256:0afa8b96ab5abd595d01d66167a704d58d78190ee9a2c656dcad5e4bd3d369b2
- `doc/gascity.texi` — Customization § TRAMP shell history hygiene.
  sha256:5719fb475077b1ff1063f8c66b2e69fe7de25b154c31e61c6a4ae614c4381f65

## Verification

First verification command (pure ERT, no live `gc` needed) — **pass**:

```
eldev test gascity-test-remote-connection-local-histfile
→ passed  1/1  gascity-test-remote-connection-local-histfile-override
  Ran 1 tests, 1 results as expected, 0 unexpected
```

Full quality gate (final proof command) run from the item worktree — **pass**:

```
scripts/gate.sh    # eldev compile --warnings-as-errors + eldev test
→ byte-compile clean (no warnings)
→ Ran 323 tests, 323 results as expected, 0 unexpected
```

`make -C doc` (manual build) also passes with the new section.

## Remaining Risks

- TRAMP's sync `process-file` path sends commands over the connection shell
  whose environment was exported when the connection opened, so the override
  reaches the connection shell's own history only when a gascity spawn opens
  the connection. The async `make-process` path (the dashboard refresh ticks
  that caused the observed bloat) reads the variable in the spawning buffer
  and is covered directly.
- The override does not shrink an existing `~/.tramp_history`; the user-run
  truncation command is documented but never executed by the workflow.
- The new `doc/gascity.texi` section is anchored before `@node Contributing`,
  deliberately disjoint from the sibling W4 (`.bashrc` guard recipe) commit's
  hunk so the two branches merge without conflict.
