# Documentation screenshot pipeline

This directory captures the screenshots in the gascity.el manual. It is
written in two halves so a **sibling package (e.g. beads.el) can reuse it
unchanged**: a package-agnostic capture *engine* and a package-specific
*shot list*.

```
screenshots/
├── screenshot.el      reusable engine — knows nothing about gascity
├── gascity-shots.el   gascity load-path + one shot per view
├── capture.sh         orchestrator — scope, fixture, compositor, run, verify
├── fixture.sh         throwaway deterministic fixture city   (WI-3)
├── fixtures/          fixture config + role-addressed seed data (WI-3)
└── README.md          this file
```

## What it does

1. Creates (or reuses) the **throwaway deterministic fixture city** from
   `fixture.sh`, so no committed image ever comes from a live store.
2. Starts a **private, headless Wayland compositor** (`sway` with the
   wlroots headless backend) so capture frames never appear on your
   desktop. Windows are floated so Emacs's requested frame size is
   honored (sway tiles by default, which would force every frame to fill
   the output).
3. Runs a **graphical** Emacs once per theme. It loads the package, the
   engine, and the shot list; renders each view; waits for the view's
   asynchronous `gc` data to settle; normalizes any residual run-generated
   value to a role token; fits the frame tightly to the rendered content;
   and exports a raw PNG with `x-export-frames`.
4. **Compresses** each raw PNG to an 8-bit-palette full image plus a
   small thumbnail under `../images/` (committed). The raw PNGs are
   throwaway.

The manual embeds each screenshot as a click-to-enlarge thumbnail (see
the `@shot` macro in `../gascity.texi`).

## Requirements

| Tool | Why | Verified |
|------|-----|----------|
| Emacs (pgtk/GUI) | renders the views; `x-export-frames` | 31.1 |
| `sway` (wlroots headless) | private capture display | 1.11 |
| ImageMagick `convert` | compress + thumbnail | 6.9 |
| `gc` CLI + `git` | fixture city + `--scope changed` | — |
| `ef-themes` | the capture themes | 2.1.0 |
| a `beads.el` checkout | gascity's non-ELPA dependency | — |

`x-export-frames` needs a real frame, so this runs a **graphical** Emacs,
never `--batch`.

## Running it

```sh
./capture.sh                          # full pipeline: capture + compress, scope all
./capture.sh --scope cockpit,health   # only the named views
./capture.sh --scope changed          # only views whose owning sources changed
./capture.sh --verify cockpit         # capture twice, assert byte-identical
./capture.sh --check-isolation cockpit # prove other committed images untouched
./capture.sh --list-scope --scope all # print the selected view names
./capture.sh --self-test              # unit-check scope + isolation (no GUI)
./capture.sh --compress               # recompress existing raws only
make -C .. screenshots                # same as the default, via the doc Makefile
```

The committed image footprint is small (≈0.8 MiB for 20 views, full +
thumbnail). The capture is read-only with respect to the fixture city — it
only opens dashboards; it never mutates.

## Scopes, verification and isolation

`--scope` selects which manifest views are regenerated:

- `all` (default) — every view in the manifest.
- `changed` — the views whose owning source file(s) changed against `HEAD`
  (working tree **and** index) or is untracked. The explicit view→source
  mapping lives in `VIEW_SOURCES` in `capture.sh` (plan-review P2); it is
  not inferred in Elisp. Set `GASCITY_SHOT_BASE` to diff against another
  ref.
- a comma-separated list — exactly those view names. An unknown view name
  exits non-zero naming the offender.

`--verify <scope>` runs the scope twice into two `$TMPDIR` staging dirs and
fails, naming the first drifting file, unless every output is
byte-identical. It then runs the subset-isolation check.

`--check-isolation <scope>` regenerates the scope into a throwaway copy of
the committed `doc/images` and asserts that every image **outside** the
scope keeps its exact bytes and mtime (AC-4). The committed tree is never
modified by the check.

`--self-test` runs the scope resolver and isolation guard anonymously with
a stub engine — no compositor, no Emacs, no live city — so CI can guard
the logic even without the graphical stack. `--list-scope` prints the
resolved view names for a scope and is the seam the self-test uses.

### Allowed differences (D4: none)

The fixture pins role ids `demo-<role>` and fixed timestamps, and the
post-render normalization hook (below) maps any residual generated id,
port, or timestamp to a stable token. **There are no permitted pixel
differences**: `--verify` asserts byte-identical output. If a view is ever
proven genuinely nondeterministic, the exception must be enumerated here
and asserted by `--verify`; it must never be passed unconditionally.

### Post-render normalization

`gascity-shots.el` installs `:before` advice on `screenshot-export` and
`screenshot-export-frame` (the engine is reused verbatim, so the hook lives
at the call site). `gascity-shots-normalization-rules` maps
`demo-<hash>` run-generated bead ids to `demo-role`, the throwaway fixture
path to `/tmp/gascity-fixture`, and ISO-8601 timestamps to a fixed epoch.
All rewrites preserve text properties and leave the buffer's modified flag
unchanged.

## Configuration (environment variables)

`capture.sh` sets these; override any of them in the environment.

| Variable | Default | Meaning |
|----------|---------|---------|
| `BEADS_REPO` | `~/workspace/beads.el` | beads.el checkout (load path) |
| `GASCITY_SHOT_DIR` | fixture city | directory `gc` resolves the city from |
| `GASCITY_SHOT_WATCHDOG` | `400` | seconds before a capture Emacs kills itself |
| `GASCITY_SHOT_RIG` | `gascity.el` | rig featured in the rig dashboard |
| `GASCITY_SHOT_STAGING` | `/tmp/gascity-shots` | raw PNG staging dir |
| `GASCITY_SHOT_IMAGES` | `../images` | committed image directory |
| `GASCITY_SHOT_BASE` | `HEAD` | git ref for `--scope changed` |
| `GASCITY_SHOT_ENGINE` | — | capture executable override for tests |
| `GASCITY_SHOT_TERMINAL_SESSION` | `demo-agent` | tmux session for `terminal-attach` |

Source→view ownership for `--scope changed` is the `VIEW_SOURCES` map in
`capture.sh`; keep it in sync with the `@shot` invocations in
`../gascity.texi`.

The capture **manifest** — which views are shot in which theme — is a
short here-doc near the top of `capture.sh`:

```
ef-elea-dark  -dark   cockpit dispatch agents runs run-detail events health rig-dashboard session-list convoy-list dolt-list lighter costs bookmarks terminal-attach
ef-cyprus     -light  cockpit agents-tree agent-detail mail-inbox mail-thread cities rig-list order-list remote-cities
```

Each line is `THEME  SUFFIX  view view …`. A view named under two themes
is captured twice (the cockpit is, to show theming). Image geometry
(widths, palette sizes) is set just below the manifest.

## Provenance (reused engine)

`screenshot.el` is copied **verbatim** from the sibling `beads.el`
pipeline's engine (which is itself the gascity.el engine): the copy must
stay byte-identical so a divergence is caught and refreshed deliberately.
Record the upstream path and digest when refreshing:

| File | Upstream | Digest |
|------|----------|--------|
| `screenshot.el` | `beads.el/docs/manual/screenshots/screenshot.el` | `sha256:dd8b3313a1f440d04bd48986aa0c02e6bcbc4fa73fbe26d8e31bd3f3775459b1` |

Only the gascity-specific half (`gascity-shots.el`, `capture.sh`, the
manifest, and `VIEW_SOURCES`) may change.

## Cross-repo contract (sibling `beads.el`)

The shared interface, fixed in both repos:

- formula name `user-manual-screenshots`;
- one `scope` variable with the values `all` | `changed` | a
  comma-separated view list (the same D3 semantics);
- fixture ids `demo-<role>` (never run-generated ids);
- image naming `<view>-<theme>.png` and `<view>-<theme>-thumb.png`, with
  the repo-local directory prefix (`doc/images/` here, `docs/manual/images/`
  in `beads.el`).

Reconcile any divergence here, in one place.

## Reusing this for another package (e.g. beads.el)

1. **Copy `screenshot.el` unchanged.** It is package-agnostic.
2. **Write a sibling shot list** (`beads-shots.el`) modeled on
   `gascity-shots.el`: put your package on the `load-path`, set the
   engine variables, and define one thunk per view that opens it and
   returns the buffer to capture. Set `screenshot-async-process-regexp`
   to your package's async process name so the engine waits for data.
3. **Copy `capture.sh`** and edit four things: the `SHOTS_EL` path, the
   manifest, the `VIEW_SOURCES` map, and the `GASCITY_*` env exports.

The engine API (see the docstrings in `screenshot.el`):

| Function / variable | Purpose |
|---------------------|---------|
| `screenshot-init` | strip chrome, hide cursor, load theme + font |
| `screenshot-settle` | pump the event loop until async data loads |
| `screenshot-fit-frame` | size the frame to the rendered content |
| `screenshot-export` | display a buffer full-frame and write `NAME.png` |
| `screenshot-export-frame` | write the whole frame (overlay UIs, transients) |
| `screenshot-run` | capture a list of `(NAME THUNK . PROPS)` shots |
| `screenshot-theme` / `-theme-library` | theme symbol + library for the load path |
| `screenshot-output-dir` / `-font` / `-max-*` | output dir, font, frame bounds |

Shot props: `:settle SECONDS`, `:fixed-rows N` (paginated lists),
`:row-pad N`, `:whole-frame t` (capture the frame as arranged, for
transient popups).

## Notes & gotchas

- **sway tiles by default.** The config floats all windows
  (`for_window [app_id=".*"] floating enable`) so `set-frame-size` is
  honored; without it, every frame is forced to the output size.
- **Frame size persists between shots.** The engine resets the frame to a
  large baseline before each shot so a paginated list opens at full size
  before being fitted down (otherwise it inherits the previous shot's
  tiny frame and paginates into many short pages).
- **ef-themes load path.** The theme `*-theme.el` files may live outside
  the default `custom-theme-load-path` (e.g. a Guix profile);
  `screenshot-theme-library` adds the library's directory so `load-theme`
  finds them.
- **Empty views are not faked.** A view whose data genuinely cannot be
  produced from the fixture is excluded with a reason in
  `fixtures/README.md` rather than shown empty.
