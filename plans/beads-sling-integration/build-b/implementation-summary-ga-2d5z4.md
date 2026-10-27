---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-x6yz3
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
    - path: beads/ga-2d5z4
      hash: "bead:ga-2d5z4"
      title: "gascity: B8 gates, tmux/TRAMP E2E, QA report, PR (REQ-009, AC-B13/14/15/16)"
      ids:
        - REQ-009
        - AC-B13
        - AC-B14
        - AC-B15
        - AC-B16
    - path: lisp/gascity-beads-sling.el
      hash: "sha256:80c3c6a0621bf03cc1be83942817730d59ae71a6064de32651808e1b016b0152"
      title: "The B1–B5 registration module under test (workstream B chain at 6670dad)"
    - path: lisp/test/gascity-beads-sling-test.el
      hash: "sha256:ba9ba6a73fa582565d4760829189cb39a522f723d90c5e5ba804382f28229346"
      title: "The B6 ERT suite (21 tests) that the gate runs"
    - path: docs/qa/2026-10-27-beads-sling-e2e.md
      hash: "sha256:9a0ea77f6ed058f6b168da97b88a71b4c42687e1b3b1be35692ce5111a91f75a"
      title: "This pass's E2E report: local + TRAMP launches, argv, store effects, cold start"
    - path: doc/gascity.texi
      hash: "sha256:4cdaef1d8541616ee5e55978430cd7d3f2555ba8597c12719797d3a46c9e54cd"
      title: "B7 manual section that the doc gate builds (Slinging from beads)"
  coverage:
    - id: REQ-009
      status: covered
    - id: AC-B13
      status: covered
    - id: AC-B14
      status: covered
    - id: AC-B15
      status: covered
    - id: AC-B16
      status: covered
---

# B8 — Gates, tmux/TRAMP E2E, QA report, PR

## Summary

B8 closes workstream B by proving the B1–B7 registration on real cities
instead of mocks:

- `scripts/gate.sh` is green: the whole package byte-compiles with
  warnings-as-errors and the full ERT suite passes (843/843, including the 21
  `gascity-test-beads-sling-*` tests).
- `scripts/lint.sh` is green (checkdoc; package-lint 0.26 is clean when placed
  on the load path exactly as CI does).
- The manual builds: `make -C doc` (Texinfo 6.8) and `make -C doc html`, both
  including the B7 "Slinging from beads" section.
- A live tmux-Emacs pass through `scripts/e2e-harness.sh` exercised the real
  flow — beads show buffer → `S` → `T` (Who picker) → a `:backend "gc"` target
  → `s` — against the local city `emacs-city` and the TRAMP city
  `/ssh:localhost:/home/roman/bright-lights`, with disposable beads and full
  cleanup.
- The pass is recorded in `docs/qa/2026-10-27-beads-sling-e2e.md`, and the
  diff against `origin/main` touches only gascity.el paths.

Coverage:

| ID | Status |
| --- | --- |
| REQ-009 | covered |
| AC-B13 | covered |
| AC-B14 | covered |
| AC-B15 | covered |
| AC-B16 | covered |

## Intended Behavior

The shipped behavior (B1–B7) is that gascity.el registers itself on beads.el's
public sling seams — target provider, `"gc"` backend, advisory validators,
`[City]` menu group, additive action, after-action refresh — so `S` on a bead
can route it through `gc sling` without gascity ever rendering bead UI or
rebuilding a bead read path.

B8 is the acceptance step for that behavior; it changes no product code. It
must demonstrate, in a live Emacs:

- The Who picker of beads.el's `S` transient shows Gas City targets
  (`:backend "gc"`) once a gascity view has warmed the store, in both a local
  and a remote city.
- Choosing one and pressing `s` builds and runs exactly the documented argv —
  plain: `("sling" TARGET BEAD)` (plus the backend's `--json`), on/ formula
  shapes per B3a — asynchronously (`gascity-command-act-async`), echoing
  `Slung BEAD to TARGET` and invalidating the affected store kinds.
- The launch lands in the city: `gc.routed_to` on the bead, the auto-convoy in
  gascity's convoy view, no blocking of the command loop (a remote action is
  still pending 1 s after `s` while the UI is responsive).
- A fresh Emacs with no gascity view shows the documented cold-start
  limitation: no gc targets until a city is known.
- The gates, the doc build, the repository boundary, and the E2E report are all
  in place for the PR.

## Changed Files

B8's own changes (this commit):

- `docs/qa/2026-10-27-beads-sling-e2e.md` — the acceptance report (commands,
  captured panes, argv, store effects, cold start, cleanup, findings).
- `plans/beads-sling-integration/build-b/implementation-summary-ga-2d5z4.md` —
  this artifact.

Carried on the same branch by B1–B7 (already reviewed in their own steps):

- `lisp/gascity-beads-sling.el` (new registration module, 502 lines).
- `lisp/test/gascity-beads-sling-test.el` (new ERT suite, 21 tests).
- `lisp/gascity.el`, `lisp/gascity-context.el`, `lisp/gascity-types.el` (load
  order, known-city-roots, command support).
- `lisp/test/gascity-store-test.el`, `lisp/test/gascity-test-helpers.el`
  (non-blocking guard and fixture additions noted by B6).
- `docs/cross-repo-ownership.md`, `docs/key-registry.md`,
  `docs/DESIGN-write-actions.md`, `doc/gascity.texi` (B7 docs).
- `plans/beads-sling-integration/task-*.md` (per-item summaries).

`git diff --stat origin/main` shows no `beads.el` path, no vendored
`beads-sling.el`, and no `gc` CLI change.

## Verification

First verification command, run from the worktree
`/home/roman/workspace/gascity.el/worktrees/ga-2d5z4`:

```console
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 843 tests, 843 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)          # PASS
```

The other gates:

```console
$ scripts/lint.sh
lint: package-lint is not installed; skipping package metadata checks
                                                      # PASS (checkdoc; CI's
                                                      # package-lint 0.26 also
                                                      # clean when on the
                                                      # load path)
$ make -C doc            # PASS — doc/gascity.info built (Texinfo 6.8)
$ make -C doc html       # PASS — gascity.html/ incl. Slinging-from-beads.html
```

Live E2E (tmux Emacs 31.1 from the worktree, harness-timeboxed):

- local `emacs-city`: `S` → `T` → `mayor` → `s` echoed
  `Slung ec-6dhcw to mayor`; captured argv
  `("gc" "sling" "mayor" "ec-6dhcw" "--json")`; store
  `gc.routed_to=mayor` and convoy `ec-bijp0 sling-ec-6dhcw` (open 0/1)
  visible in `*gascity-convoys@/home/roman/emacs-city/*`.
- remote `/ssh:localhost:/home/roman/bright-lights`: same flow over TRAMP,
  echoed `Slung bl-rawe to mayor`; argv
  `("gc" "sling" "mayor" "bl-rawe" "--json")`; the action was still pending one
  second after `s` (non-blocking); store `gc.routed_to=mayor` and convoy
  `bl-07l0 sling-bl-rawe` (open 0/1) visible in the remote convoy view.
- cold start: a fresh Emacs with no gascity view provided nil targets, a cold
  `("agent" "list")` store, and only beads' five local targets in the Who
  picker.

Final proof command (store effects, both cities):

```console
$ (cd /home/roman/emacs-city && bd show ec-6dhcw --json) | jq -r .metadata.gc.routed_to
mayor
$ ssh localhost 'cd /home/roman/bright-lights && bd show bl-rawe --json' \
    | jq -r .metadata.gc.routed_to
mayor
# both returned mayor; the sling-<bead> convoys were listed by gc convoy list
# and rendered by gascity's convoy views. PASS (then both beads and convoys
# were closed as cleanup).
```

## Remaining Risks

- The live pass exercised the **plain** route (the documented B8 step). AC-B14's
  wording also mentions a "workflow root visible in gascity's run/status view",
  which only a formula/workflow launch produces; this pass did not instantiate
  a v2 workflow on disposable state (it would spawn real work). The formula and
  `--on` argv shapes are covered by ERT (`backend-formula-argv`,
  `backend-on-argv`) and the audit trail in B3a/B3b, not by this live pass.
- The disposable beads were routed to `mayor` (whose `sling_query` only sets
  `gc.routed_to`), so the pass proves routing and convoy creation, not an
  agent actually picking the bead up.
- The Who-picker counts depend on which providers contribute project-scoped
  rows for the current directory (beads' role/worktree targets); the gc rows are
  stable per city once the store is warm. Documented in the QA report (F5).
- Minor out-of-scope UX finding: `gascity-dispatch` has no `q` suffix
  (`C-g` only), contrary to the `q` convention; recorded in the QA report (F1)
  for a follow-up instead of being changed here.
- Remote acceptance used the documented `/ssh:localhost:` method, which worked
  in this pass; if the older `ssh`-method hang (F4 in a previous report)
  recurs on another host, the same flow is expected over `sshx` with no code
  change.
