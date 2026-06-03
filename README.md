# gascity.el

A [Gas City](https://github.com/gastownhall/gascity) porcelain inside Emacs,
integrated with [beads.el](https://github.com/r0man/beads.el).

Gas City's `gc` CLI is the *plumbing*; gascity.el is the *porcelain*. Every view
is a function of `gc … --json` output: gascity renders gc's state and dispatches
its commands, keyboard-first, the way Magit fronts git. The UI is hand-built in
the magit/forge style — deliberately designed, sectioned, keyboard-driven
buffers — not auto-generated. See [docs/DESIGN.md](docs/DESIGN.md).

## Status

A usable porcelain: an interactive status dashboard; tabulated list views with
window-sized pagination (`]`/`[`/`G`) and per-list `/` filters; agent actions
(Dired into a worktree, attach to a tmux session); mutating-command dispatch
(rig suspend/resume/restart, session nudge/suspend/kill/wake/drain, sling, order
run, city start/stop); and vui detail views — a rig dashboard and a
session/polecat detail. Bead-UI delegation and polish are planned (DESIGN.md §7,
§11).

## Requirements

- Emacs 29.1+
- The `gc` CLI on your `exec-path` (or set `gascity-executable`)
- [beads.el](https://github.com/r0man/beads.el) (provides `beads-meta`,
  `beads-section`, `beads-terminal`) and [vui](https://github.com/r0man/vui)
- Optional: `vterm` or `eat` for a nicer tmux-attach terminal (falls back to the
  built-in `term`)

## Install

With the dependencies on your `load-path`:

```elisp
(add-to-list 'load-path "/path/to/gascity.el/lisp")
(require 'gascity)
```

## Usage

`M-x gascity` opens a dispatcher; or call a view directly:

| Command | View |
|---|---|
| `M-x gascity-status` | Status dashboard (city → rigs → agents), collapsible |
| `M-x gascity-rig-dashboard` | Rig dashboard (agents, beads, orders, Dolt) |
| `M-x gascity-rig-list` | Rigs |
| `M-x gascity-session-list` | Agent sessions |
| `M-x gascity-convoy-list` | Convoys |
| `M-x gascity-mail-inbox` | Mail inbox |
| `M-x gascity-order-list` | Orders |
| `M-x gascity-dolt-list` | Dolt databases |

### Keys

Everywhere: `g` refreshes, `q` buries, `RET` drills in. In the tabulated lists,
`]`/`[`/`G` page and `/` opens a filter.

- **Status dashboard:** `TAB` toggles a rig section (the magit convention);
  `RET` toggles the rig at point too, or attaches the agent's terminal (`i`
  opens its detail); `d` Dired into the worktree; `t` tmux attach;
  `M`/`s`/`K`/`w`/`D` nudge/suspend/kill/wake/drain the agent; `n`/`p` move by
  line, `N`/`P` jump between sections (city/rig/…).
- **Rig list:** `RET` opens the rig dashboard; `d` Dired into the rig directory;
  `s`/`r`/`R` suspend/resume/restart.
- **Session list:** `RET` opens the session/polecat detail; `d` Dired; `t` tmux
  attach; `M`/`s`/`K`/`w`/`D` session actions; `p` peeks at recent output.
- **Rig dashboard:** agents table, ready/in-progress beads (`RET` → beads.el),
  rig-scoped orders, and Dolt stats; the agent action keys above act on the
  agent at point, and `N`/`P` jump between sections.
- **Session/polecat detail:** state, mail count, the bead on the hook, and
  recent history (`RET` → beads.el); `p` peek, `M` nudge, `D` drain, `s` suspend,
  `K` kill, `w` wake, `d` Dired, `t` tmux act on the subject agent; `N`/`P` jump
  between sections.
- **Convoys:** `RET` opens the convoy bead via beads.el.
- **Orders:** `RET` opens the order's source file; `x` runs the order manually.

## Customization

`M-x customize-group RET gascity RET`. Notably:

- `gascity-executable` — name/path of the `gc` binary (default `"gc"`).
- `gascity-terminal-backend` — `nil` (auto: vterm > eat > term), `vterm`, `eat`,
  or `term`, for tmux attach.
- `gascity-tmux-socket` — tmux server socket the agents run on. `nil`
  auto-detects it as the city name (gc runs one tmux server per city); set a
  string to override.
