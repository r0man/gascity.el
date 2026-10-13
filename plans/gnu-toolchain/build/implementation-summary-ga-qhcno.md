---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-12whi
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
    - path: beads/ga-qhcno
      hash: bead:ga-qhcno
      title: "W5 — Manual reference completeness pass"
      ids:
        - REQ-012
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "Approved requirements (REQ-012; AC-6)"
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved implementation plan (W5, §4 manual quality)"
    - path: plans/gnu-toolchain/decomposition.md
      hash: sha256:b1eb1eee2d7310ed63f9348eba55e1219b11f6ac2e44c815a0ad7c28e82f3b58
      title: "Approved decomposition (W5 depends on W3)"
    - path: doc/gascity.texi
      hash: sha256:481a4efad4d71614ace7ef96a3477159864280237862c0f7e3937d0db799be26
      title: "Manual: new View and Key Reference chapter"
    - path: lisp/test/gascity-manual-test.el
      hash: sha256:31cae8f6ac722640e65fd2b1e715176e47ab28ef49ff15799c58a9a5d289c330
      title: "Mechanical key-registry completeness assertion"
  coverage:
    - id: REQ-012
      status: covered
---

# Implementation Summary: W5 — Manual reference completeness pass (source anchor ga-qhcno)

## Summary

Completed the task-organized reference coverage the manual is required to
carry (REQ-012, AC-6), using the existing `gascity-key-registry` test as the
coverage checklist. `doc/gascity.texi` gains a **View and Key Reference**
chapter that names every registered view with its mode map and its
namespaced/agent-only distinction, and every agent action verb with the Emacs
command it runs and both of its bindings (the `a` prefix in the namespaced
views, the bare key in the agent-only views). The universal keys stay
documented once in *Buffers and Navigation*, which the chapter references.

The completeness assertion is mechanical:
`gascity-test-manual-key-registry-coverage` in
`lisp/test/gascity-manual-test.el` reads the key registry's `defconst`s and
asserts that every registered view name, mode map, universal/vui contract key
(as `@kindex`) and verb command symbol appears in `doc/gascity.texi`. A new
view, key or verb therefore fails the suite until it is documented. The
test parses the registry file (as the rest of this test file already parses
`capture.sh`, `gascity-shots.el` and the fixture) rather than loading the
package, so it stays a pure source-reading test.

## Intended Behavior

- **Every view is registered and documented (REQ-012).** The chapter lists
  `cockpit`, `rig-dashboard`, `agent-detail`, `agents-tree`, `agents`,
  `session-list`, `runs`, `run-detail`, `health`, `cities`, `rig-list`,
  `convoy-list`, `order-list`, `dolt-list`, `events`, `mail-inbox` and
  `mail-thread` with their `gascity-*-mode-map` symbols, and says whether
  agent verbs live under `a` or on the bare keys.
- **Every agent verb is documented with its command (REQ-012).** Nudge,
  suspend, wake, kill, drain, undrain, reset, attach, Dired, detail and peek
  each name their `gascity-*` command and carry a `@findex` entry, so the
  action surface is complete in both the prose and the Command Index.
- **Completeness is machine-checked (REQ-012/AC-6).** Removing a registered
  view from the manual fails the test; the failure names the missing view.
- **No runtime change (REQ-020).** Only the manual source and one ERT file
  change; no Elisp behaviour, keymap or `gc` CLI surface is touched.

## Changed Files

- `doc/gascity.texi` (modified) — new `@node View and Key Reference` chapter
  (registered-views table, agent-action-verbs table with `@findex` entries),
  added to the `@node Top` menu. Referenced from *Buffers and Navigation* for
  the universal keys.
- `lisp/test/gascity-manual-test.el` (modified) — new
  `gascity-manual-test--key-registry-const` reader and the
  `gascity-test-manual-key-registry-coverage` assertion.
- `plans/gnu-toolchain/build/implementation-summary-ga-qhcno.md` (new) — this
  summary.

## Verification

First verification command (the completeness assertion in isolation, ten
manual tests):

```
$ emacs -Q --batch -L lisp -L lisp/test -l lisp/test/gascity-manual-test.el \
    --eval '(ert-run-tests-batch-and-exit "gascity-test-manual")'
Running 10 tests
   passed  gascity-test-manual-key-registry-coverage
Ran 10 tests, 10 results as expected, 0 unexpected
exit=0
```

Fault injection (the assertion must fail when a registered view is dropped):

```
$ sed -i 's/@code{agent-detail}/@code{agentdetail}/' doc/gascity.texi
$ emacs -Q ... --eval '(ert-run-tests-batch-and-exit "gascity-test-manual-key-registry-coverage")'
   FAILED  gascity-test-manual-key-registry-coverage
Ran 1 tests, 0 results as expected, 1 unexpected
exit=1                       # restored, then back to exit=0
```

Final proof command (the Eldev-free autotools build and the ERT suite):

```
$ ./autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el"
$ make html
exit=0
$ ls doc/gascity.html | wc -l
77                           # 76 pages + the new reference page
$ ls doc/gascity.html/View-and-Key-Reference.html
doc/gascity.html/View-and-Key-Reference.html

$ make check
Ran 773 tests, 772 results as expected, 1 unexpected
```

The single `make check` failure,
`gascity-test-local-reader-read-async-generic-envelope-stderr-wins`, is a
reader/stderr test in `lisp/test/gascity-test.el`; it reproduces in isolation
on this W1+W3 stack and touches neither file this change modifies. The
`gascity-test-manual-*` selector — including the new completeness assertion —
is green.

### Coverage

| ID | Status |
| --- | --- |
| REQ-012 | covered |

## Remaining Risks

- **The key index is asserted by notation, not by count.** The test requires
  `@kindex KEY` for each contract key, which matches the manual's existing
  `@table @kbd` style; a future edit that documents a key only in prose would
  fail it even though a reader could find the key's meaning.
- **Verb commands are asserted as literal symbols.** The test proves the
  command name is present, not that the surrounding sentence is correct; the
  verb/keys mapping is written by hand in the chapter.
- **`make check` has one unrelated pre-existing failure** on the W1+W3 stack
  (reader async stderr envelope). It is outside W5's file boundary and is
  recorded here rather than fixed, to avoid crossing into another bead's
  source.
