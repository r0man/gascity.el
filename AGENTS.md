# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

gascity.el is a Magit-style Emacs porcelain for the Gas City `gc` CLI. Every
view is a function of `gc … --json` output: the package renders gc's state and
dispatches its commands; it never reimplements gc logic. The UI is hand-built
(magit/forge style, sectioned, keyboard-first), **not** auto-generated from
command metadata. Bead (issue) UI is delegated to beads.el, never rendered here.
The binding design is `docs/DESIGN.md` (read-only views) and
`docs/DESIGN-write-actions.md` (mutating actions); commits reference their
sections (e.g. "DESIGN.md §4.3").

Status is experimental. Emacs 29.1+. Dependencies `beads.el` and `vui` are not
on ELPA: the `Eldev` file resolves them from a sibling checkout at
`~/workspace/beads.el` (and the vui it bundles). `guix shell -D -f guix.scm`
gives a dev environment for the Guix-available deps only.

## Build & test

The standard quality gate, run from the repo root before every push:

```bash
scripts/gate.sh   # eldev compile --warnings-as-errors  +  eldev test
```

The halves, and how to narrow them:

```bash
eldev compile --warnings-as-errors      # byte-compile gate (offline)
eldev test                              # whole ERT suite (lisp/test/gascity-test.el)
eldev test gascity-test-remote          # tests whose name matches a selector (prefixes: status, remote, tabulated, rig, session, terminal, bd, beads, ...)
eldev test -s -b                        # stop on first failure, print backtraces
make -C doc                             # Texinfo manual → doc/gascity.info + doc/gascity.html/
make -C doc screenshots                 # regenerate doc/images/ from a live city (headless sway)
```

`--warnings-as-errors` is the only check that catches an undefined-function
reference. Action verbs are wired across files (a keymap or menu in one file
names a command defined in another), so a missing forward `declare-function`
compiles clean under plain `eldev compile` and is invisible to `eldev test`.
Always compile the whole package, never an "affected" subset.

All tests are named `gascity-test-*` and live in one file. Pure tests stub the
gc boundary with `cl-letf` on `gascity-reader-read` /
`gascity-reader-read-async` (or on the action verb under test); the few tests
that need a live `gc` and city guard themselves with `skip-unless`.

## Architecture

Load order in `lisp/gascity.el` is the dependency order:
custom → error → remote → reader → command → context → types → domain →
command-status → terminal → section → tabulated → status → action → rig →
session.

**Data plane (one gc call site).** `gascity-reader.el` is the only module that
runs `gc`: `gascity-reader-run` (sync `process-file`), `-parse-json`,
`-read` (sync `gc … --json` → payload) and `-read-async` (`make-process`,
backing `vui-use-async`). There are deliberately no per-subcommand accessors
here; a named sync read is the `gascity-command-<sub>!` bang function. JSON
decodes `false` **and** `null` to nil (unlike beads.el's `:json-false`), which
is why domain boolean slots are typed `(or null boolean)`.

**Command layer (beads-meta, execution + parse only).**
`gascity-defcommand` (`gascity-command.el`) defines an EIEIO class per gc
subcommand; the subcommand is derived from the class name
(`gascity-command-rig-list` → `rig list`), slots with `:long-option` become CLI
flags via beads.el's `beads-meta-build-command-line`, and the macro also emits
a `NAME!` executor returning the parsed payload. Read classes live in
`gascity-types.el`; list-filter slots there mostly carry **no** `:long-option`
because gc lists have almost no server-side filters, so `gascity-tabulated`
filters decoded rows client-side (session `--state` is the lone server-side
exception). Mutating classes derive from `gascity-command-action`
(`gascity-action.el`). `gascity-command-execute-interactive` is the generic
that turns a command object into UI: view modules specialize it to open their
buffer, actions specialize it to run synchronously and refresh the originating
view; city start/stop keep the streaming base method.

**Domain objects.** `gascity-domain.el` decodes payloads once into typed EIEIO
objects (rig, session, agent, convoy, mail, order) with `:json-key` slot
metadata, via beads.el's reflective `beads-from-json`. `gascity-agent` is
synthesized (a `session list` row joined with a `status` agent entry and the
tmux socket), never decoded directly. The "object at point" is one of these or
a bead-id string; `gascity-at-point-visit` is the generic whose methods (in
section/tabulated/rig) implement `RET` per class.

**Rendering, two mechanisms.** Homogeneous lists (rigs, sessions, convoys,
mail, orders, dolt) are `tabulated-list-mode` views in `gascity-tabulated.el`,
all following the same `--entry` / `-refresh` / mode / `-show-buffer` shape
with window-height paging and a `/` filter transient. Heterogeneous views are
vui: `gascity-section-mode` (derives from `beads-section-mode` → `vui-mode`)
underlies the status dashboard (`gascity-status.el`), rig dashboard
(`gascity-rig.el`) and session/polecat detail (`gascity-session.el`). Each vui
section is backed by an independent async read so one failure never blanks
the others, and refreshes are stale-while-revalidate: keep rendering the last
payload while the reload is pending (a pending state with nil data must not
unmount the tree). Collapse state is lifted to the root component so it
survives refresh.

**Context and buffer identity.** `gascity-context.el` finds the city by
walking up for `city.toml`; rigs live outside the city tree, so the rig is
resolved by asking gc and memoized. **Every view buffer must be created through
`gascity-view-get-buffer-create`**: it host-qualifies the buffer name (a local
and a remote dashboard coexist), pins `default-directory` to the city so
refresh timers keep hitting the right host, and installs an I/O-free `project`
instance (project.el's VC walk over TRAMP on every redisplay was a real hang).
Paths that must never spawn gc synchronously (eldoc in terminal buffers,
prefix tagging) read the rig memo `gascity-rigs-cached`.

**Remote cities (TRAMP).** `gascity-remote.el` owns the three remote concerns:
re-prefixing host-local paths that gc reports, the buffer-name keying scheme,
and turning a TRAMP name into a local `ssh -t HOST …` argv for tmux attach
(the terminal backend only spawns local processes). Bare `gc`/`tmux` names are
resolved on the host via `tramp-remote-path`, then by probing the Guix profile
dirs in `gascity-remote-search-path`, cached per connection; every remote
invocation also prepends those dirs to PATH so gc's own children (git, dolt)
resolve. Keep redisplay-time and eldoc code off the TRAMP channel.

**Bead delegation contract (DESIGN.md §4.3).** beads.el's entry points pick
their store from `default-directory`, so gascity scopes a delegated view by
binding `default-directory` to the owning rig's repo path (bead id prefix →
rig) before calling `beads-show` / `beads-dashboard`. Never call the
`beads-list` transient for programmatic scoping (its suffixes read
`default-directory` after the binding unwinds).

**Terminal / compose.** `gascity-terminal.el` wraps beads.el's
`beads-terminal-spawn` (vterm > eat > term) for tmux attach; attach buffers get
beads eldoc wired from the rig memo. `gascity-compose.el` is the one new UI
primitive: a git-commit-style buffer that collects a multi-line body and calls
a finish closure; it knows nothing about gc.

## Remote test city & end-to-end testing

`bright-lights` is a real second city at `/home/roman/bright-lights`, kept as
the TRAMP test target. Open it from a local Emacs as the remote file name
`/ssh:localhost:/home/roman/bright-lights` (the default user) — every gascity view must
work identically there (status dashboard, rig dashboards, lists, sling,
formula dispatch, mail). When a feature touches anything gc-invocation or
path related, verify it against that city over TRAMP, not only locally.

The end-to-end test protocol for user-facing features (e.g. the formula
sling UI) is interactive, not ERT: launch a **fresh Emacs inside tmux**
(`tmux new-session -d -s gce-e2e 'emacs'`, or `emacs -Q` with `lisp/` on the
`load-path`), connect it to `/ssh:localhost:/home/roman/bright-lights`,
and exercise the real flow — dispatch a sling with a formula, set its vars
through the transient, confirm the workflow root appears in the store. Do not
call the feature "done" until this pass has run; record the result in a
`docs/qa/` dogfood report. ERT covers the mocked units; the tmux-Emacs
TRAMP session is the acceptance gate.

## Conventions

- Everything is prefixed `gascity-`; one `gascity-command-<domain>.el` per gc
  domain where a domain outgrows `gascity-types.el`.
- `--json` for anything parsed; terminal backend for anything interactive.
- `q` buries, `g` refreshes, `RET` drills in, everywhere. Agent action keys
  (`d` Dired, `t` tmux, `i` detail, `M`/`s`/`K`/`w`/`D`) mean the same thing
  in the status dashboard, session list, rig dashboard and session detail;
  `N`/`P` jump sections in vui views. Check
  `docs/DESIGN-write-actions.md` §10 before adding a key.
- Confirmation: destructive actions (rig restart/remove, force-kill, city
  start/stop) go through `gascity-action--confirm`; quick mutations (nudge,
  suspend, wake, drain) run without a prompt and report in the echo area.
- Commit subjects follow `type(scope): summary`, optionally ending with the
  bead id in parentheses; the commit body cites the design section it
  implements.
- Live QA reports go under `docs/qa/`.

## Session completion

Before ending a session with code changes: run `scripts/gate.sh`, commit, then
`git pull --rebase && git push` and confirm `git status` is up to date with
origin. Work left only in the working tree or a local branch is considered
stranded.
