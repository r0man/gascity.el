# gascity.el NEWS

User-visible and API-breaking changes, newest first.

## Unreleased

### Toolchain: autotools replaces Eldev

The build system is now a real GNU autotools project.  From a clean checkout,
`./autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el" &&
make && make check` byte-compiles every `lisp/*.el` with warnings promoted to
errors, runs the full ERT suite, and installs the package and its Info manual
(`make install`).  `make` replaces `eldev compile --warnings-as-errors`,
`make check` replaces `eldev test`, and `make lint` (backed by
`scripts/lint.el`) replaces `eldev -p -dtT lint`; `scripts/gate.sh` and
`scripts/lint.sh` keep their semantics.  The non-ELPA `beads.el`/`vui`
dependencies are resolved by `configure --with-beads-dir`/`--with-vui-dir`,
with the vui bundled in the `beads.el` checkout taking precedence over any vui
installed in the host Emacs.  `Eldev` and `.eldev/` are removed.

### Task-organized user manual and reproducible screenshots (REQ-001 to REQ-008)

`doc/gascity.texi` gains a task-organized **Task Guide** part that covers every
user-visible feature area, each with an embedded real screenshot; the
Area-to-Screenshot Map says which image documents which area.  Screenshots are
now produced from a deterministic, throwaway fixture city instead of a live
store, so they can be regenerated from a clean checkout.

The pipeline lives in `doc/screenshots/` and is driven by the repo-local
formula `.beads/formulas/user-manual-screenshots.formula.toml` with one `scope`
variable (`all`, `changed`, or a comma-separated view list).  It reuses the
existing capture engine (`screenshot.el` unchanged), seeds a role-addressed
`demo-<role>` fixture, and asserts byte-identical reruns (`--verify`) plus
subset isolation (`--check-isolation`).  `AGENTS.md` and
`doc/screenshots/README.md` §Cross-repo contract document the regenerate and
verify commands and the contract shared with the sibling `beads.el` build;
`eldev test gascity-test-manual` guards the fixture, the scope parser, the
manifest/shot/`@shot` coverage, and the image references offline.
