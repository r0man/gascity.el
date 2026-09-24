# gascity.el UX design review — ga-pf3c pass (2026-09-24)

Reviewer: `gascity.el/gc.implementation-worker-2` (ec-egbe). Evidence: the
live dogfood pass recorded in `docs/qa/2026-09-24-ga-pf3c-dogfood-e2e.md`
(both access modes), plus the prior ga-hirj pass and the still-open
follow-up beads. Product bar: gascity.el should feel like magit — known
keys, transient menus, coherent sectioned buffers, everything discoverable
and reversible.

## What already meets the bar

- **Keybinding consistency** across views is real: `g`/`q`/`RET`/`N`/`P`
  behave identically in tabulated lists and vui dashboards; agent action
  keys (`d`/`t`/`i`/`M`/`s`/`K`/`w`/`D`/`S`) now match across the status
  dashboard, rig dashboard, session list and session detail (the ga-hirj
  `S` fix closed the last gap). The footer hint lines ("g refresh · RET
  open/tmux · …") are accurate to what is bound.
- **Transients**: the sling dispatch and the sessions `/` filter transients
  render cleanly, seed from point, and survive TRAMP (the city pin from
  ga-4ia4 keeps their minibuffers on the entered-from city).
- **Async discipline**: every section load is async, stale-while-revalidate
  keeps trees alive during reloads, and one failed section never blanks
  its neighbors — verified live (mail/beads sections erroring while the
  state block stays).
- **Error surfacing**: reader failures carry gc's envelope message (the
  ga-eyw9 ladder), not bare exit codes; this pass added the last swallowed
  case (agent-detail mail, ga-52t8).

## Concrete recommendations (ranked)

1. **Collapse the City block** (magit-section parity). `TAB` currently
   toggles only rigs and pool groups; the City and Named sessions headers
   carry `gascity-section` but no collapse state, so `TAB` on them now says
   "This section has no collapse state" (honest, but still a dead key).
   Give the root component a `:collapsed-city` list and fold the city tree
   under its header — the machinery (`gascity-status--toggle-collapsed`)
   already exists; only the city vnode needs a conditional body. ~15 lines
   + test. This is the single highest-value remaining polish item.
2. **Refresh after send.** Mail send and sling dispatch both refresh the
   originating view via `gascity--refresh-current-view`, but the mail
   *inbox list* doesn't re-read after `gascity-mail-send` is finished from
   its compose buffer (the compose's `:origin` buffer is the inbox, yet the
   finish closure doesn't refresh it). Make `gascity-compose-finish` call
   `gascity--refresh-current-view` in the origin buffer after a successful
   finish. Small, closes the "where did my message go?" gap.
3. **`—` for all absent tabulated values.** ga-1kdu's Branch fix is one
   instance of a general rule; the sessions list Provider cell still
   renders empty (not `—`) for pool workers. Audit
   `gascity-tabulated--str` call sites: either default the helper to
   `"—"` for nil (with an opt-out for genuinely blank-by-design columns)
   or fix the provider column. One-hour sweep, removes a whole class of
   "is that empty or broken?" moments.
4. **Discoverability of the events gap.** Until ga-69kj lands, the status
   dashboard should carry a dim pointer row under Store health, e.g.
   "recent activity: .gc/events.jsonl (no JSON yet)" — turning a silent
   absence into a documented one, the same move as the `(mode —)`
   placeholder.
5. **Confirmation prompts should use a transient/read-from-modeline
   pattern in headless contexts** — not a product change, but the
   y-or-n-p minibuffer is the one UI state that cannot be driven or
   observed through the eval channel (see the harness footgun). A
   `gascity-action--confirm` that falls back to echo-area + `y`/`n` keymap
   (like `yes-or-no-p`'s alternative) would make the whole write-action
   surface scriptable. Defer; file only if harness passes keep tripping.
6. **Bead-create echo could offer `RET` to open.** "gc bd create: created
   hw-smv in hello-world store" is good; magit would also hint the next
   action. A `M-x gascity-bead-show`-style prompt or a clickable id is
   nice-to-have; the rig dashboard row already covers it.

## Verdict

The core interaction model is magit-grade: sectioned vui dashboards,
consistent keys, transient-driven write actions, async reads with honest
error surfacing. Remaining gaps are one structural (city collapse), one
convenience (refresh-after-send), one sweep (`—` consistency) and one
blocked-on-upstream (events). Items 1–4 are small, independent, and would
together close every non-upstream finding from both dogfood passes.
