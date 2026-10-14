# gascity.el NEWS

User-visible and API-breaking changes, newest first.

## Unreleased

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
