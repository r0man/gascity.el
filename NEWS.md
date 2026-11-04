# gascity.el NEWS

User-visible and API-breaking changes, newest first.

## Unreleased

### `j s` opens the Sessions view; the jump registry is complete

The flat session list (`gascity-session-list`, its own state/rig filters and
`gascity-sessions` bookmark) was reachable only via `M-x` or a bookmark.  It
now has `j s` in every view's `j` prefix and in the `?` dispatch's Jump
group.  The cockpit's "… N more" hints gain `j l` (rigs), and every hint
now names the same `gascity-jump-*` command the prefix and the dispatch bind
(`j o`/`j v`/`j d` previously pointed at the lists directly), so the three
registries cannot drift; a parity ERT test enforces it (ga-s3nt3).

### Sling Who lists every configured agent and derives the formula's run target

The sling's **T** picker now offers every agent `gc agent list` reports, not
only the ones a status or session row observes: a rig's `gc.run-operator` and
its other lane templates appear with state `configured` as soon as they are
configured, so a bright-lights cockpit can target
`hello-world/gc.run-operator` (ga-rghou).  Names stay qualified --- the bare
`gc.run-operator` never appears, because gc resolves that form only from the
rig directory.  The Agents table itself stays observed-only.

The Who default gains a formula-derived rule between the per-(city, formula)
memory and the implementation-worker convention: a picked formula whose steps
name a binding-qualified `gc.run_target` derives `<bead-rig>/<run-target>` ---
build-basic on an `hw-` bead derives `hello-world/gc.run-operator`.  The target
coordinating the most steps wins; a tie between two targets is ambiguous and
derives nothing, and freeform work, an unknown bead prefix, a cold rig memo or
an unread recipe cache fall through fail-soft.  The derivation records its
source as `formula-run-target`.

### Opening a view outside a city no longer silently reads another city

Every city-scoped view (cockpit, runs, events, mail, agents, health, costs,
and the rig/session/convoy/order/dolt lists) now resolves its city at open
time through `gascity-context-city-for-view`.  When the invoking buffer is
not inside a Gas City, the view prompts for a city root interactively and
refuses with a clear message in batch, instead of letting `gc`
auto-discover a city — which could render a **different** city's data with
no warning (ga-br1av, dogfood A5).  The resolved city is what names the
buffer and fills the header line, so the scope is always visible.

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
installed in the host Emacs.  `transient` 0.10.1 or later is resolved from the
ambient `EMACSLOADPATH` or `--with-transient-dir`, because Emacs 29/30 bundle an
older copy that lacks the macro `beads.el`'s menu macro expands to;
`scripts/ci-deps` installs it (and `package-lint`) for CI.  `Eldev` and
`.eldev/` are removed.

### Dashboard polish: fold the City block, show — for absent cells, refresh the inbox after send

The Agents tree's **City** header now folds and unfolds with `SPC`/`TAB` (and
`RET`), showing a `▸`/`▾` indicator like every rig and pool header, and the
fold survives `g`; the **Named sessions** block folds the same way, matching
the CLI's layout.

An absent value in a tabulated list no longer renders as a blank cell: the
shared cell helper draws an em-dash (`—`), so a pool worker's empty
**Provider** column reads as absent rather than broken.  Columns that are
genuinely blank by design opt out with the helper's `blank` argument.

Sending or replying to mail from the inbox already re-read the inbox on
success (`:origin`, since c876ceb); a regression test now pins that — no
change was needed.

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
