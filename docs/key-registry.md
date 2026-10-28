# gascity.el key registry

The cross-package key contract between **gascity.el** and **beads.el**.
gascity layers on beads.el (`gascity-section-mode` derives
`beads-section-mode`; every menu is a `beads-define-prefix`), so a
physical key that means one thing in a beads buffer and another in a
gascity buffer is a trap — above all the destructive `D`/`K`/`s` cases.

This file is the prose half; `lisp/test/gascity-key-registry-test.el`
enforces it against each view’s **effective** keymap (the binding
`keymap-lookup` returns, local over inherited). The beads.el half lives
in the sibling checkout’s `docs/key-registry.md` and uses the same
table; keep the two identical.

Source of record: `plans/ux/magit-parity-plan.md` §4.1/§5.2, and
`docs/DESIGN-write-actions.md` §10 (cross-package key registry).

## Universal navigation contract

Every gascity view binds these, and the registry test asserts them
everywhere:

| Key | Meaning |
|---|---|
| `RET` | activate the thing at point (drill in) |
| `TAB` / `S-TAB` | next / previous thing |
| `SPC` | toggle / fold the thing at point |
| `n` / `p` | next / previous line |
| `N` / `P` | next / previous section (vui views) |
| `q` | bury |
| `g` | refresh |
| `?` | dispatch (`gascity-dispatch`) |
| `j` | jump prefix |

## At-point keys by row type

| Key | bead row | agent/session row | rig row | list/tabulated |
|---|---|---|---|---|
| `RET` | visit bead | open detail | rig dashboard | drill in |
| `SPC` | fold/toggle | toggle drawer | fold | row detail |
| `d` | close bead | — | — | close bead |
| `D` | delete… | drain | — | — |
| `s` | set status | suspend | suspend rig | — |
| `S` | sling… | sling… | sling… | sling… |
| `w` | copy id | wake | resume | copy |
| `K` | — | kill | — | — |
| `M` | — | nudge | — | — |
| `C` | claim | — | — | claim |
| `#` | priority | — | — | priority |
| `x` | — | — | — | clear filter |
| `?` | beads-dispatch | gascity-dispatch | gascity-dispatch | per package |

`d`, `s`, `w`, `i`, `t`, `D`, `C` and `#` are **reserved for beads.el
verbs** in any view that can also show a bead. gascity never rebinds one
of them to a non-bead verb there.

In **beads.el's own view buffers** `S` is beads.el's `S`:
`beads-sling-for-issue` opens the `beads-sling` transient seeded with the
issue at point.  gascity contributes no competing `S` binding there; its
registration module adds the `[City]` group to `beads-dispatch` and the
additive `V` cockpit entry to the bead action bars.  beads.el only
prints provider keys, so gascity binds `V` itself in
`beads-list-mode-map` and `beads-show-mode-map` (free in both).  The
`gc` targets, the `gc` backend and the formula/vars passthrough appear
because gascity is loaded, not because gascity binds `S` in a beads
buffer.  gascity's own views keep binding `S` to
`gascity-sling-dispatch`; both menus dispatch the same `gc sling`
command.

## The `[City]` group (delegated `beads-dispatch`)

gascity appends exactly one group to beads.el's `beads-dispatch` menu.
Its keys are gascity's, not beads.el's:

| Key | Meaning |
|---|---|
| `E` | cockpit (`gascity-dashboard`) |
| `J` | rig dashboard at point (`gascity-rig-dashboard-at-point`) |
| `K` | rig dashboard, chosen (`gascity-rig-dashboard`) |
| `A` | agents table (`gascity-agents`) |
| `Q` | the gascity sling menu (`gascity-sling-dispatch`) |

Conflict audit (P4): beads.el's own `beads-dispatch` keys are
`l c / i u x o e r b d # C s m G w S T a F v D H R Y t X L k . W ! * g q`,
so none of `E J K A Q` collides.  The bead action bars get one additive
`V` cockpit entry on `:list` and `:show`, bound in both maps by
`gascity-beads-sling--bind-actions`; it shadows nothing, and in
particular never `S`, `RET` or `TAB`.

## The `a` agent/rig prefix (F1)

In any gascity view that can also show beads — the rig dashboard and the
session detail — the agent verbs move under an `a` prefix, so a bead row
always keeps its beads.el meaning:

| Key | Agent verb |
|---|---|
| `a n` | nudge |
| `a s` | suspend (agent at point, else rig) |
| `a w` | wake |
| `a k` | kill |
| `a D` | drain |
| `a r` | reset |
| `a u` | undrain |
| `a t` | attach (tmux) |
| `a d` | dired |
| `a i` | polecat / agent detail |
| `a v` | peek |

### Sanctioned exception: agent-only views

The cockpit (`gascity-dashboard`) and the other **agent-only** views
(the Agents table and tree, the Sessions list) also keep the fast
single-letter aliases (`s`, `w`, `K`, `D`, `R`, `U`, `t`, `d`, `i`, `v`,
`M`) alongside the `a` prefix. Their rows are agents, never beads, so
the aliases cannot change meaning for a bead. This is a declared
exception, not an accident: `gascity-key-registry-test.el` names those
views and asserts both the single letters and the `a` prefix there.

## One dispatch (F4)

`M-x gascity` and `?` open the same hand-written verb menu,
`gascity-dispatch`; its Jump group reaches every porcelain view and its
Agent/Work/City groups route the mutating actions. There is no second,
differently-keyed `gascity` transient.
