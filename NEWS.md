# gascity.el NEWS

User-visible and API-breaking changes, newest first.

## Unreleased

### The cockpit's Agents section leads with live workers

The cockpit shows up to eight Agents rows by default (new option
`gascity-dashboard-agent-rows', the other sections keep
`gascity-dashboard-section-rows' at five), and running agents come
first, ordered by most recent activity, before stalled/unknown and idle
ones; suspended and stopped agents stay in the `▸ stopped' fold, which
counts as one of the eight.  A live worker can no longer be pushed out
of the section by idle or stopped rows.  The Agents view and the rig
dashboard keep the shared attention-first order, and the section
summary line is unchanged (ga-boawq).

### Cockpit and run diagnostics

A failed run in the cockpit's Needs you section now explains its
failure on the spot: the row's right column carries the failure class
(cut to 20 columns, full text in help-echo), and the drawer names the
class, the failed step and the first line of the reason, with the full
reason in help-echo and the `RET run detail`/`b root bead` hints; the
rig moves to the drawer (ga-shl0s).

The Runs history facts line budgets each of its four values separately
from its dim label (`stage` 6, `step` 16, `fail` 17, `work` 7 columns),
so a stage reads `Review` instead of `Rev…` and every cell keeps its
full text in help-echo when cut; the line stays exactly 78 columns
(ga-v67dq).

Long `gc.failure_reason`/`close_reason` text in a Runs failed card, the
run-detail step and drain-member drawers, and the cockpit's failed-run
drawer is now cut to the width the line leaves with the full reason in
help-echo, instead of running off the window edge (ga-wjlx6).

The Events detail for a `bead.closed` (or `bead.updated`) payload now
lists the bead's `close_reason` and `gc.failure_class` as their own
`key value` lines, fitted to the drawer width with the full value in
help-echo, and never repeats a key already shown for the event
(ga-th2e2).

A stalled agent's cockpit row now says how long it has been stalled,
and its drawer adds the timestamp that age counts from plus the hooked
bead's lease expiry and heartbeat when `gc` reports them; the reason
(`running, no live session`) is never squeezed out by a long qualified
name, and an unknown timestamp reads `unknown` (ga-vinoi).

### The run detail's header names the run's provenance

The header now labels every fact it holds instead of printing one
unlabelled formula line: a `root` row (the run bead, its formula and
`gc.outcome`, with the rig and start/close time), a `store` row
(`gc.root_store_ref`, the rig and the city), a `scope` row
(`gc.scope_ref`, else `(none)`) and a `formula` row (name and
`gc.formula_contract`, with the graph root key and the formula source
on aligned continuation lines).  Nothing is derived: an absent optional
fact is omitted or reads `(none)` where the row exists for it
(ga-kci2d).

### `o` opens the artifact at point

The run detail's new `o` key visits the artifact or plan path at point
--- the header's `plans` and `source` entries and a step inspector's
artifact lines --- exactly as `RET` does, and says `No artifact at
point` elsewhere.  A missing local file is now a clear user error
instead of Emacs's raw `file-missing`, and a remote city still reads
`remote: not checked` without statting on render (ga-kci2d).

### The step inspector stacks attempt history

Expanding a step whose beads carry iterations or attempts now lists
one row per attempt, oldest first, under an `attempts` heading: the
attempt number, outcome, worker, relative time and failure class and
reason (`(none)` for a healthy attempt).  Every row comes from the
run's already-loaded bead graph, so the drawer reads no `gc` the step
did not already need; the collapsed row keeps its `iter N` summary
(ga-n6qh5).

### `B`/`Y`: open or copy the run's web dashboard URL

The run detail binds `B` to open the current run in the configured web
dashboard and `Y` to copy that URL.  The new user option
`gascity-dashboard-url` supplies the base (`/city/<city>/runs/<id>` is
appended to it); it is `nil` by default, and then both keys only say
`No dashboard URL configured; set gascity-dashboard-url` --- gascity
never guesses or probes a host.  `W` stays the cross-view live toggle
(ga-obuvt).

### Changed run facts are highlighted, with a last-update stamp

A live delivery now highlights the steps and Runs cards whose visible
facts changed since the previous render (state, progress, worker,
failed step) and stamps the view's summary with the delivery's
`updated HH:MM:SS`.  The first paint marks nothing, and both the
highlight and the stamp are sticky: a refresh that changes no fact
leaves the buffer visually unchanged.  Collapse state and point
survive the repaint (ga-grkql).

### The Runs view states its time basis and adds history columns

The summary count line now ends `(all time)`, only the Failed section
is windowed (`last 24h`), and the Closed history header states its own
basis (`all time`, or `last <window>` when filtered).  Every history
row gains a second dim facts line with `stage`, `step`, `failure` and
`worker` columns inside the existing 78-column budget; both lines
belong to the same run, so point, `TAB` and `RET` behave the same on
either (ga-28pbg).

### `I`/`w`/`!` work on drain-member run rows

A `└ …` drain-member row is a run of its own: `I` opens an in-place
member drawer (root, formula, progress, worker, failure, `RET run`
hint), `w` copies the member's root bead id, and `!` echoes the
member's own failed step, class and reason without moving point or
leaving the buffer.  A healthy member says so, and `RET` still drills
into the member's run detail.  Everything comes from the loaded index,
so no `gc` read is added (ga-28pbg).

### `T` renders the step `needs` tree

The run detail's new `T` toggles a `needs`-aware step tree: the flat,
stage-grouped layout stays the default and returns byte-for-byte, while
the tree reorders and indents each stage's members by their `blocks`
dependencies (falling back to formula step-ref `needs` lists).  A
parent in another stage is shown as a dim `↳ needs <parent>` note
instead of extra indentation, a cycle is cut and marked `(cycle)`, and
a formula without edge data falls back to the flat layout.  The toggle
re-renders from the loaded payload, so it adds no `gc` read and
survives `g` (ga-x9qb9).

### The run inspector separates session liveness from a claim lease

A live worker's step inspector used to read `lease expired 4m ago
heartbeat 9m ago`, which looked like a dead assignee even though the
session was still active.  The claim lease is bead metadata, not session
liveness, and Pi workers do not currently run `gc bd heartbeat`, so an
active claim's lease lapses while it works.  The worker line now names
the two facts apart: `session live · active 20s ago` from the session
row, and `claim lease 3m left · heartbeat 30s ago` from the bead.  A
lapsed lease on a session active after the deadline reads `(Pi heartbeat
gap)`, never a dead worker; a session quiet past the deadline reads
`(stale claim)`, the same rule as the cockpit's Needs you; with no live
session it reads `assignee/session gone` and the lease age.  The root
cause is tracked in ga-p2lfj and the cockpit rule in ga-o7vtw; this
change is UI only (ga-v8hah).


A run whose formula has a stage table (the `mol-*` review, design and bug
flows, and `build-base`/`build-basic`) now renders its top-level steps
under lifecycle stage headers in table order, each with a state glyph and
`done/total` progress, instead of one flat list.  A stage is `failed` if
any member failed, `active` if any runs, `done` only when every member is
done, and `pending` otherwise; an empty stage stays visible (`Approval`
reads `0/0` in a build run).  A failed stage appends `failed` and carries
the failure class and reason in its help text.  `SPC` folds a stage
independently of the step folds, and `C` lifts control nodes (spec, scope
check, finalize) out of the stages into one trailing `Control` group.
Anchors matching no table entry collect in an `Other` group, and a formula
with no table keeps the flat list rather than guessing (ga-tkxsx).

### The run detail's summary counts every bead in the run

The steps section now reads `Steps N/M · G beads` for mapped and flat runs
alike.  `N/M` is the step ladder over top-level anchors; `G` is the size of
the run's whole bead graph, including iterations, nested steps and control
nodes.  A mapped formula's stage progress counts top-level anchors, not
graph beads, so nested ids collapse into their anchor.  This is the in-view
half of the anchor-versus-graph-bead distinction the manual now spells out
(ga-tkxsx, run-view-v2 REQ-004).

### A step's drawer is a full inspector

`SPC` on a step row (or `I` on any row, fold rows included) opens the step
inspector: the step's ref, bead, status and outcome; its attempt and
iteration bead; its worker with session liveness, lease and heartbeat; the
run's and the step's artifacts with existence and age; the three newest
matching events; and the failure class and reason (or `(none)`).  Artifact
entries are visitable with `RET`; on a remote city they read `remote: not
checked` rather than statting over TRAMP, and a missing local file reads
`(missing)`.  The events read starts only while a drawer is open and uses
the cockpit's store key, so it dedupes and live events invalidate it.  The
step, iteration and worker lines carry the same identity properties as
their rows, so `RET`, `i`, `v` and `t` work from the drawer unchanged
(ga-ti6ah, ga-en6f5).

### The run detail opens its beads in the run's store

Opening a run by id (`M-x gascity-run-show ga-tkxsx`) used to leave the
detail without a rig, so `RET` on a step and `b` on the root delegated
the bead to the city store, which cannot see a rig's beads; beads.el
reported `Error loading issue`.  With no rig passed, the view now reads
the run root's `gascity-rig` stamp from the payload it already renders,
so both keys open the bead in the rig store.  A run opened from the Runs
view still uses the rig it carried (ga-rv28a).

### New run-detail keys: `I` inspect, `w` copy id, `!` diagnose

The run detail binds `I` (`gascity-run-inspect`) to toggle the inspector,
`w` (`gascity-run-copy-id`) to copy the step or iteration bead id, and `!`
(`gascity-run-diagnose`) to reveal and diagnose the run's failed step,
expanding a collapsed stage and any folded loop above it and echoing
`✕ ref  class: reason`.  `w` is the reserved key's cross-package bead-row
meaning (copy id) and is recorded as the sanctioned exception in
docs/DESIGN-write-actions.md §10; `I` and `!` were unbound in the run
detail before.  `doc/generated/keys.texi` includes the new keys
(ga-en6f5).

### Failure diagnosis is one key, not separate diagnose views

The run-detail failure class/reason resolution and the one-key `!`
diagnose supersede the separate diagnose beads `ga-32wpi` and `ga-lpnpb`;
their user-visible behavior now lives in `gascity-run-diagnose` and the
step inspector.

### The Agents table is the single Agents view

The alternative Agents tree (`gascity-agents-tree`, `T`) is removed.  It
rendered the same observed agents as the table (`gascity-agents`, `j a`),
but without the table's state/rig/provider/search filters, sortable
columns, paging, bookmarks or shared list keys.  `T` is now unbound in the
Agents table; its bookmark kind and its two screenshots are gone.  Pool
topology, if it is wanted later, belongs as a `Group by rig`/pool option on
the table rather than as a second view (ga-2mmet).

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

### Dashboard polish: show — for absent cells, refresh the inbox after send

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
