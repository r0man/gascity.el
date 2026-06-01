# gascity.el

A [Gas City](https://github.com/gastownhall/gascity) porcelain inside Emacs,
integrated with [beads.el](https://github.com/r0man/beads.el).

Gas City's `gc` CLI is the *plumbing*; gascity.el is the *porcelain*. Every view
is a function of `gc … --json` output: gascity renders gc's state and dispatches
its commands, keyboard-first, the way Magit fronts git. The UI is hand-built in
the magit/forge style — deliberately designed, sectioned, keyboard-driven
buffers — not auto-generated. See [docs/DESIGN.md](docs/DESIGN.md).

## Status

Read-only MVP: an interactive status dashboard, tabulated list views, and agent
actions (Dired into a worktree, attach to a tmux session). Write/mutate actions
and richer detail views are planned (DESIGN.md §7, §11).

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
| `M-x gascity-rig-list` | Rigs |
| `M-x gascity-session-list` | Agent sessions |
| `M-x gascity-convoy-list` | Convoys |
| `M-x gascity-mail-inbox` | Mail inbox |
| `M-x gascity-order-list` | Orders |
| `M-x gascity-dolt-list` | Dolt databases |

### Keys

Everywhere: `g` refreshes, `q` buries, `RET` drills in.

- **Status dashboard:** `RET` toggles the rig section / activates the row;
  `d` opens the agent's worktree in Dired; `t` attaches to its tmux session;
  `n`/`p` move.
- **Session list:** `d` Dired into the worktree, `t` tmux attach, `RET` Dired.
- **Convoys:** `RET` opens the convoy bead via beads.el.
- **Orders:** `RET` opens the order's source file.

## Customization

`M-x customize-group RET gascity RET`. Notably:

- `gascity-executable` — name/path of the `gc` binary (default `"gc"`).
- `gascity-terminal-backend` — `nil` (auto: vterm > eat > term), `vterm`, `eat`,
  or `term`, for tmux attach.
- `gascity-tmux-socket` — tmux server socket the agents run on. `nil`
  auto-detects it as the city name (gc runs one tmux server per city); set a
  string to override.
