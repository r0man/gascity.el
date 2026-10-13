---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-5vkd8
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
    - path: beads/ga-5ihzl
      hash: bead:ga-5ihzl
      title: "W7 — Screenshot pipeline under autotools"
      ids:
        - REQ-015
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "Approved requirements (REQ-001..REQ-023, AC-1..AC-10); REQ-015 / AC-7 / TS-4"
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved implementation plan; decision D5 and work item W7"
    - path: doc/screenshots/capture.sh
      hash: sha256:00be5a62a28707c353cf0e1c430df64fdce3ffffc72b0405f7fd762fca45fcec
      title: "Root resolution via git rev-parse --show-toplevel with script-relative fallback"
    - path: doc/screenshots/README.md
      hash: sha256:31da33e5cd1f1f3c460e6aa0ea621c8cc66513b6d1dc2c9c25abcfe5a5e100ea
      title: "Documents `make screenshots` and the local/graphical-only contract"
    - path: doc/gascity.texi
      hash: sha256:82ce75801bcbc69007274a36bb95b7fdcfb06842cf0620d0854f7cb1c24ef765
      title: "Screenshots node documents root resolution and no-CI contract"
    - path: README.md
      hash: sha256:99d554626361d246d7e3bfb509ddd816f8decc3851a809ec004e8c3231323630
      title: "Screenshot section points at `make screenshots` and the shipped images"
    - path: lisp/test/gascity-manual-test.el
      hash: sha256:9931a6fb7d2a258c0bb51f77eccd8e04700fe1a44b1d9cc0cccfe16f2d5b3783
      title: "gascity-test-manual-capture-root-resolution (REQ-015)"
  coverage:
    - id: REQ-015
      status: covered
---

# Implementation Summary: W7 — Screenshot pipeline under autotools (source anchor ga-5ihzl)

## Summary

Wired the deterministic fixture-city screenshot pipeline into the
autotools build and made `doc/screenshots/capture.sh` independent of the
caller's working directory (plan W7, decision D5, requirements REQ-015
/ AC-7 / TS-4). The top-level `make screenshots` target (added with the
autotools skeleton in W1, `Makefile.am`) delegates to
`doc/screenshots/capture.sh`; the script now resolves the repository
root with `git -C "$HERE" rev-parse --show-toplevel`, falling back to
its historical script-relative `doc/screenshots -> repo-root` assumption
when git is unavailable or the copy is not a checkout. Nothing else in
the pipeline changed: the `--verify`, `--check-isolation`, `--self-test`,
`--scope`, `--list-scope`, `--compress` behaviors, the `VIEW_SOURCES`
mapping, the pinned fixture, and the committed `doc/images/` output are
untouched.

The target is documented as a local/graphical-only step. It starts a
private headless compositor and needs a graphical Emacs, so CI never
runs it; the committed `doc/images/` are the shipped artifact. That
contract is now stated in `README.md`, `doc/gascity.texi` and
`doc/screenshots/README.md`. `lisp/test/gascity-manual-test.el` gains
`gascity-test-manual-capture-root-resolution`, an offline test that
asserts the root-resolution mechanism is present and that
`capture.sh --list-scope all` produces the full view list when invoked
by absolute path from an unrelated working directory.

## Intended Behavior

- **`make screenshots` delegates (D5, REQ-015).** `Makefile.am`'s
  `screenshots` target runs `cd '$(top_srcdir)/doc/screenshots' &&
  ./capture.sh`, the single documented entry point for the pipeline.
- **Root resolution is caller-independent (D5).** `capture.sh` computes
  `REPO` from its own location: `git -C "$HERE" rev-parse
  --show-toplevel` first, then `$(cd "$HERE/../.." && pwd)` when git is
  missing or the directory is not a work tree. `GASCITY_REPO`,
  `GASCITY_SHOT_IMAGES` and the fixture/engine paths all derive from
  `REPO`, so the pipeline runs from a build tree or any cwd.
- **No behavioral change (REQ-015).** The scopes, isolation checks,
  byte-identical verification, `VIEW_SOURCES` mapping, fixture and
  committed images are unchanged; only root discovery differs.
- **Local/graphical only; CI never runs it (REQ-015, TS-4, R5).**
  `README.md`, `doc/gascity.texi` and `doc/screenshots/README.md` all
  say so and point at the committed `doc/images/` as the shipped
  artifact.
- **Offline regression coverage (REQ-015).** The new ERT test fails if
  the `git rev-parse --show-toplevel` resolution is removed and proves
  `--list-scope all` is cwd-independent.

## Changed Files

- `doc/screenshots/capture.sh` — replace the fixed `doc/../..` root with
  `git rev-parse --show-toplevel` plus a script-relative fallback.
- `README.md` — the screenshot section references `make screenshots` and
  states the local/graphical-only, CI-never-runs-it contract.
- `doc/gascity.texi` — the screenshots node documents root resolution
  and the shipped-image contract.
- `doc/screenshots/README.md` — same, in the pipeline's own reference.
- `lisp/test/gascity-manual-test.el` — add
  `gascity-test-manual-capture-root-resolution`.
- `plans/gnu-toolchain/build/implementation-summary-ga-5ihzl.md` (new) —
  this summary.

`Makefile.am`'s `screenshots` target already exists from W1
(`ga-d4att`) and needed no change.

## Verification

First verification command — the pipeline's built-in offline unit
checks, run from the worktree:

```
$ doc/screenshots/capture.sh --self-test
[capture] self-test: ok - --list-scope subset
[capture] self-test: ok - --list-scope all includes costs
[capture] self-test: ok - --list-scope changed from a source
[capture] self-test: ok - unknown view exits non-zero
[capture] self-test: ok - unknown view named
[capture] self-test: ok - isolation check passes
[capture] self-test: all checks passed
exit=0
```

Final proof command — full deterministic capture, run twice and compared
byte-for-byte from the build tree (isolated `TMPDIR` /
`GASCITY_SHOT_STAGING` so no other process can disturb the fixture):

```
$ doc/screenshots/capture.sh --verify all
[capture] coverage: every selected view produced an image (scope all)
[capture] verify: byte-identical for 26 image(s) (scope all)
[capture] done.
exit=0
```

Supporting gate (compile clean, warnings as errors, then the whole ERT
suite including the new test):

```
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 773 tests, 773 results as expected, 0 unexpected (44.1 sec)
>>> gate: PASS (compile clean + tests green)
exit=0
```

The new test passed as `gascity-test-manual-capture-root-resolution`
(result 338/773).

An earlier `--verify all` attempt failed with a single drifting image
(`mail-inbox-light.png`, raw width 2286 px vs 2316 px) while a sibling
drain worker ran its own capture against the shared `/tmp` fixture;
`--verify mail-inbox` and the rerun above were byte-identical in
isolation, confirming contention rather than a pipeline defect.

## Remaining Risks

- The screenshot pipeline needs a graphical Emacs (pgtk), `sway`,
  ImageMagick and a seeded fixture; it cannot run in batch CI, which is
  why the committed images are the shipped artifact (REQ-015, TS-4). A
  future CI environment with a compositor would need an explicit job.
- `doc/screenshots/fixture.sh` uses a fixed fixture directory under
  `TMPDIR` and is not concurrency-safe: two captures sharing a `TMPDIR`
  corrupt each other and can produce layout drift. `--verify` is only
  reliable when the fixture and staging directories are private; this
  predates W7 and is outside its scope.
- Root resolution now trusts an enclosing git work tree. A distributed
  copy shipped inside an unrelated repository would resolve that
  repository as `REPO`; the fallback only triggers when git finds no
  work tree. This matches the plan's D5 wording.
- The committed images were not regenerated by this change (as
  required); `--verify all` proves the pipeline still reproduces them
  byte-for-byte from the fixture.

| ID | Status |
| --- | --- |
| REQ-015 | covered |
