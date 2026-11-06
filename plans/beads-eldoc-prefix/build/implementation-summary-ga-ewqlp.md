---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-xpq5u
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
    - path: beads/ga-ewqlp
      hash: bead:ga-ewqlp
      title: "W2 — Install path: one eldoc installer for views and attach buffers"
      ids:
        - REQ-001
        - REQ-002
        - REQ-006
        - REQ-008
    - path: plans/beads-eldoc-prefix/requirements.md
      hash: sha256:e27383a7f11d968e0129e6bc870ce7de66da5d48db50f8ae9f48e022c3bff7f4
      title: "Approved requirements (REQ-001..REQ-018, AC-1..AC-5, TS-1/TS-4/TS-5)"
    - path: plans/beads-eldoc-prefix/implementation-plan.md
      hash: sha256:f32df57e032ad86e0ebe98c16f10cbd1c70be716a8ae4fd9f8b456288d42b710
      title: "Approved implementation plan (§B, §G D1/D8, §H item 2)"
    - path: lisp/gascity-beads-eldoc.el
      hash: sha256:c5f8ccadec33e96ae5b3f7df3ed0ab3fa5f4fc6e8face08957b9edb98be29d79
      title: "Map core (W1 commit 1e6e2bd) plus this change's install path, registry and fill hook"
    - path: lisp/gascity-terminal.el
      hash: sha256:b45f97cb84b9896f7ceb88904446e6f3b889b75bb4c3709bfccd1b1ba82f5eb1
      title: "Attach captures the city and delegates to the installer"
    - path: lisp/gascity-context.el
      hash: sha256:b66b24f4b595143a796f9dc1910f040fc56c04f5d18f700557e36ffa68fcc6e3
      title: "View factory drops the warm-memo allowlist shortcut"
    - path: lisp/gascity.el
      hash: sha256:4329c2f92524c274ee454bda57e5b9f4da6409caa626842f5fa5dff0144498bd
      title: "Load order: gascity-beads-eldoc after gascity-section"
    - path: lisp/test/gascity-beads-eldoc-install-test.el
      hash: sha256:646e64ec597077e59f80c638710ea993c165fa129c81e50ff0e161180cc0be84
      title: "Install-path ERT coverage (11 cases)"
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-006
      status: covered
    - id: REQ-008
      status: covered
---

# Implementation Summary: W2 — Install path, one bead-eldoc installer (source anchor ga-ewqlp)

## Summary

Added the single bead-id eldoc install path for every gascity buffer
(plan §B, §H item 2; REQ-001/002/006/008).  `gascity-beads-eldoc-install`
captures the city scope at install time, resolves the city's map through
the W1 map core, and sets both beads.el buffer-locals — a function of the
id for `beads-eldoc-directory` and the map's prefix list for
`beads-issue-id-prefixes` — boundp-guarded after a soft `require` of
`beads-eldoc`.  A cold map installs the deny-all sentinel `'("")`, which
`beads-issue-id--allowed-p` can never match, so a cold buffer admits no
id instead of falling back to `default-directory` (REQ-006); the map's
fill re-applies the landed map to the registered open buffers, so they
heal without being reopened.

The view factory now installs through
`gascity-view-created-functions` and its warm-memo allowlist shortcut is
gone; `after-change-major-mode-hook` re-applies from the permanent-local
scope and map, so the major mode's `kill-all-local-variables` cannot drop
the wiring (TS-5).  `gascity-terminal-attach-tmux` captures the city at
attach time — the calling buffer's installed scope first, then
`gascity-context-city-root`, else nil — and `gascity-terminal--beads-integrate`
delegates to the installer, so an attach in a polecat worktree outside
the city tree still resolves the city and its rigs (REQ-008, TS-4) and a
known agent store no longer pins every id to that rig (REQ-002).  No city
context installs nothing and starts no fill (D8).

This work item is the dependent W2 slice: its branch is stacked on W1's
`feat(beads-eldoc): per-city prefix to store map core (ga-3cc7x)`
(commit 1e6e2bd), which is the map core this change installs.

## Intended Behavior

- **One install path (REQ-001, TS-1).** Every buffer created through
  `gascity-view-get-buffer-create` gets the contract from
  `gascity-beads-eldoc-install` (registered on
  `gascity-view-created-functions`), and every terminal/attach buffer the
  terminal module opens calls the same installer.  No other module writes
  `beads-eldoc-directory`; a `grep` of `lisp/` shows the installer as the
  single setter.
- **Resolution is per id (REQ-002).** `beads-eldoc-directory` is a
  function closing over the buffer's map snapshot and answering
  `gascity-beads-eldoc--store-for`, so a city-store id and another rig's
  id resolve to their own stores even in an attach buffer whose agent
  store is known.  The attach's `STORE` argument now only scopes the
  buffer's `project` root.
- **Cold start is safe and self-healing (REQ-006).** The cold allowlist is
  `'("")`; nil or `()` would mean "accept any id".  An ERT test pins the
  sentinel against the installed `beads-issue-id--allowed-p`.  A cold
  install registers the buffer; `gascity-beads-eldoc--land` calls
  `gascity-beads-eldoc--reapply-buffers`, which re-applies the map to the
  live buffers of that scope (dead ones pruned), so the same buffer
  resolves correctly without a reopen or revert.
- **Captured context (REQ-008, TS-4).** The scope is computed once at
  install time from the install context; resolution never re-derives it
  from `default-directory`, so re-pinning a buffer elsewhere cannot
  re-scope its eldoc.
- **No city, no install (D8).** DIR outside any city tree sets neither
  variable and starts no fill; a beads.el without the eldoc variables is
  likewise left alone (soft-require compatibility, REQ-018).
- **Survives the major mode (TS-5).** The scope and map are
  `permanent-local`; `gascity-beads-eldoc--reinstall` on
  `after-change-major-mode-hook` re-applies both variables from them,
  mirroring `gascity-context--reinstall-project`.
- **No synchronous spawn (D9, REQ-012).** Installing only reads the map
  (a hash lookup) and, when cold, starts the map's one asynchronous
  `gc rig list` read through the store.  `gascity-reader-run`,
  `process-file` and `call-process` are asserted never to run from
  install.

Coverage:

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-006 | covered |
| REQ-008 | covered |

## Changed Files

- `lisp/gascity-beads-eldoc.el` — the install path on top of the W1 map
  core: buffer-locals (`gascity-beads-eldoc--scope/-map`, permanent-local),
  the deny-all sentinel, the scope→buffers registry,
  `gascity-beads-eldoc--apply`, `gascity-beads-eldoc-install`, the
  major-mode reinstall, `gascity-beads-eldoc--reapply-buffers`, the two
  load-time hooks, and the one-line re-apply at the end of
  `gascity-beads-eldoc--land`.  The file commentary now documents the
  single resolution path, the cold deny-all rationale and the captured
  context.
- `lisp/gascity-context.el` — `gascity-view-get-buffer-create` no longer
  sets `beads-issue-id-prefixes` from the warm rig memo; the install hook
  owns the whole contract.
- `lisp/gascity-terminal.el` — `gascity-terminal-attach-tmux` captures
  `eldoc-city` (calling buffer's scope, then the origin city root),
  threads it through `gascity-terminal--attach-finish`, and
  `gascity-terminal--beads-integrate` delegates to the installer; docstrings
  and the module commentary updated.
- `lisp/test/gascity-beads-eldoc-install-test.el` (new) — 11 ERT cases:
  deny-all pinned against beads.el, warm install, cold install + heal,
  captured worktree context, D8 no-op, no-contract no-op, no synchronous
  spawn, cold install starts exactly one async read, major-mode survival,
  view-factory install (cold deny-all versus warm), and an attach with a
  known agent store resolving per id.
- `lisp/test/gascity-test.el` — `gascity-test-terminal-beads-integrate`
  rewritten for the new contract (per-id resolver function, deny-all cold,
  D8 no-op, no-contract no-op); the view-creation tests that open real
  cities opt out of the map read with the new helper.
- `lisp/test/gascity-store-test.el` — the non-blocking guard ignores the
  `("rig" "list")` map fill a view-opening verb starts, still asserting
  no synchronous gc and exactly the verb's own actions.
- `lisp/test/gascity-health-test.el`, `lisp/test/gascity-test-helpers.el` —
  `gascity-test-without-bead-eldoc-map` helper and its two view-opening
  call sites, so a test without the gc boundary stubbed starts no real
  map read.

No `gc` CLI surface, key binding, transient, rendering or beads.el
delegation boundary changes (caller migration is W3, refresh hooks are W4,
docs/QA are W5).

## Verification

First verification command, from the worktree root (offline gate: whole
package byte-compiled with `byte-compile-error-on-warn t`, then the ERT
suite):

```
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 1021 tests, 1021 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)
```

Final proof (the CI lint job's exact command, plus the focused install
suite on its own):

```
$ scripts/lint.sh
lint: package-lint is not installed; skipping package metadata checks (CI installs it)
exit=0   # checkdoc clean on every lisp/*.el

$ EMACSLOADPATH="$HOME/workspace/beads.el/lisp:$HOME/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0:$EMACSLOADPATH:" \
    emacs --batch -Q -L lisp -L lisp/test \
    -l lisp/test/gascity-beads-eldoc-install-test.el \
    --eval '(ert-run-tests-batch-and-exit)'
Ran 11 tests, 11 results as expected, 0 unexpected (0.08 sec)
exit=0
```

Without that `EMACSLOADPATH` prefix the focused command fails before running a
test — the sibling beads.el checkout's `beads-prefix` is not on the bare
`-L lisp` path:

```
Cannot open load file: No such file or directory, beads-prefix
Error: file-missing ("Cannot open load file" "No such file or directory" "beads-prefix")
```

The whole-package `scripts/gate.sh` / `scripts/lint.sh` commands above supply
the same environment for the target tree, so only the focused command needed
the explicit prefix.

Evidence for the ask's other proofs:

```
$ grep -rn "setq-local beads-eldoc-directory" lisp/
lisp/gascity-beads-eldoc.el:386:        (setq-local beads-eldoc-directory
#                                ^ the installer is the only setter

$ grep -rn "gascity-beads-eldoc-install" lisp/
lisp/gascity-beads-eldoc.el:    (defun gascity-beads-eldoc-install …)
lisp/gascity-beads-eldoc.el:    (add-hook 'gascity-view-created-functions …)
lisp/gascity-terminal.el:      (declare-function …) + the delegate call
```

The ERT cases cover the cold→warm heal, the worktree attach
(`default-directory` outside the city tree), a known agent store
resolving another rig's id, major-mode survival, the view factory, and
"no synchronous spawn on install".

## Remaining Risks

- **Dependency stacking.** The branch sits on W1's local commit 1e6e2bd
  rather than a merged `origin/main`; the runtime dispatched this
  dependent item before W1 landed.  W1's commit content is unchanged here.
- **Fill→registry wiring is one line in shared code.** `--land` (W1's
  function in the same module) now calls
  `gascity-beads-eldoc--reapply-buffers`; an ERT case exercises the
  registry re-apply directly, and the cold-then-heal path through a real
  fill is covered at unit level (store stubbed).  If W1's module is
  rewritten before merge, that call must be carried over.
- **Live acceptance is W5.** This item has offline ERT + gate coverage;
  the tmux/TRAMP interactive pass and the manual/NEWS section are plan
  items 5 (also caller migration `C-c b` is item 3), so the interactive
  flows land with those items.
- **`STORE` remains a terminal argument** for the attach's `project`
  root; it no longer scopes eldoc.  A reviewer reading only
  `gascity-terminal-attach-tmux`'s signature could misread it as eldoc
  scoping — the docstring now states the split.
- **TRAMP eldoc dialing** stays beads.el's (`beads-eldoc--fetch-allowed-p`
  connected-only guard); the installer only hands it localized names, so
  an unconnected host is silent by design (REQ-009, D6).
