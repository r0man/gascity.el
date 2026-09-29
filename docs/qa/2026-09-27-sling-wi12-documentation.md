# Sling command documentation (WI-12) — build QA report

- Date: 2026-09-27
- Item: WI-12 of the sling command redesign (bead ga-1wl7, workflow root
  ga-eavt, drain `ga-wnsv` unit 11); plan `plans/sling-command/
  implementation-plan.md`, section "WI-12 — Documentation" (REQ-015).
- Worktree: `worktrees/ga-1wl7`, based at origin/main tip `69eed1c`
  (the separate-context drain base for every unit).

## Deliverables

1. **`doc/gascity.texi`** — a new chapter, `The Sling Command`, at the
   PostgreSQL-documentation bar: the unified flow (What → Who → How →
   Preview → Launch → Follow), all three shapes with the one-sentence
   header, the `A`/`f`/`T` pickers, the typed variable readers (file,
   directory, agent, numeric, choice, bool, fail-soft string), the live
   footer, the bl-bdj trap and cross-store warnings, the `P` full
   preview buffer, the launch/follow offer, remembered state, and the
   key summary (mockup §10). Every requirement behavior REQ-001 through
   REQ-012 is documented. The four-line Sling item in "Dispatch and
   lifecycle" is now a pointer to the chapter, and the Top menu carries
   the chapter entry.
2. **`docs/DESIGN-write-actions.md`** — §10's "Unified sling transient"
   subsection rewritten to the staged adaptive redesign (it supersedes
   the earlier unified layout), with a pointer to the manual chapter.
3. **`doc/images/sling-*.png`** (7 states + thumbnails) — the sling
   menu's states, wired with the existing `@shot` macro.

## Screenshots are mockup renderings (the documented fallback)

All seven sling images (`sling-plain`, `sling-cold`, `sling-formula`,
`sling-on`, `sling-trap`, `sling-preview`, `sling-follow`) are
**mockup renderings** of the signed-off menu mockups
(`plans/sling-command/menu-mockups.md`), not live captures. Under the
separate-context drain the redesigned transient exists only in the
parallel work items' worktrees (WI-1…WI-11), so no live session of this
item's code contains the new UI to capture; the requirements' Open
Question explicitly leaves ephemeral or infeasible states to "mockup
renderings as the documented fallback". Real captures from the live
verification pass (WI-11's bright-lights session) replace these files
under the same names when that session's code merges; the `@shot`
wiring needs no change.

## Verification

- `make -C doc` (makeinfo info + styled multi-page HTML) builds clean —
  no node, menu, or cross-reference warnings; the chapter's 13 nodes
  (chapter + 12 sections) render in both outputs.
- `scripts/gate.sh` (`eldev compile --warnings-as-errors` + full ERT)
  passes on the docs-only change (recorded in the item summary).
- Image wiring mirrors the existing pipeline outputs: palette PNGs plus
  520px thumbnails under `doc/images/`, embedded via the `@shot` macro.

## Remaining work

- Replace the mockup renderings with real captures from the live
  verification session (same file names, same wiring) when that pass
  runs against the merged redesign.
