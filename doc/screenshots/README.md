# Documentation screenshot pipeline

This directory captures the screenshots in the gascity.el manual. It is
written in two halves so a **sibling package (e.g. beads.el) can reuse it
unchanged**: a package-agnostic capture *engine* and a package-specific
*shot list*.

```
screenshots/
├── screenshot.el      reusable engine — knows nothing about gascity
├── gascity-shots.el   gascity load-path + one shot per view
├── capture.sh         orchestrator — headless compositor, run, compress
└── README.md          this file
```

## What it does

1. Starts a **private, headless Wayland compositor** (`sway` with the
   wlroots headless backend) so capture frames never appear on your
   desktop. Windows are floated so Emacs's requested frame size is
   honored (sway tiles by default, which would force every frame to fill
   the output).
2. Runs a **graphical** Emacs once per theme. It loads the package, the
   engine, and the shot list; renders each view; waits for the view's
   asynchronous `gc` data to settle; fits the frame tightly to the
   rendered content; and exports a raw PNG with `x-export-frames`.
3. **Compresses** each raw PNG to an 8-bit-palette full image plus a
   small thumbnail under `../images/` (committed). The raw PNGs are
   throwaway.

The manual embeds each screenshot as a click-to-enlarge thumbnail (see
the `@shot` macro in `../gascity.texi`).

## Requirements

| Tool | Why | Verified |
|------|-----|----------|
| Emacs (pgtk/GUI) | renders the views; `x-export-frames` | 30.2 |
| `sway` (wlroots headless) | private capture display | 1.11 |
| ImageMagick `convert` | compress + thumbnail | 6.9 |
| `gc` CLI + a running city | live data | — |
| `ef-themes` | the capture themes | 2.1.0 |
| a `beads.el` checkout | gascity's non-ELPA dependency | — |

`x-export-frames` needs a real frame, so this runs a **graphical** Emacs,
never `--batch`.

## Running it

```sh
./capture.sh              # full pipeline: capture + compress
./capture.sh --compress   # recompress existing raws only
make -C .. screenshots    # same, via the doc Makefile
```

The committed image footprint is small (≈0.5 MiB for all views, full +
thumbnail). The capture is read-only with respect to the city — it only
opens dashboards; it never mutates.

## Configuration (environment variables)

`capture.sh` sets these; override any of them in the environment.

| Variable | Default | Meaning |
|----------|---------|---------|
| `BEADS_REPO` | `~/workspace/beads.el` | beads.el checkout (load path) |
| `GASCITY_SHOT_DIR` | `~/bright-lights` | directory `gc` resolves the city from |
| `GASCITY_SHOT_RIG` | `gascity.el` | rig featured in the rig dashboard |
| `GASCITY_SHOT_STAGING` | `/tmp/gascity-shots` | raw PNG staging dir |

The capture **manifest** — which views are shot in which theme — is a
short here-doc near the top of `capture.sh`:

```
ef-elea-dark  -dark   status rig-dashboard session-list convoy-list dolt-list dispatch
ef-cyprus     -light  status session-detail rig-list order-list
```

Each line is `THEME  SUFFIX  view view …`. A view named under two themes
is captured twice (the status board is, to show theming). Image geometry
(widths, palette sizes) is set just below the manifest.

## Reusing this for another package (e.g. beads.el)

1. **Copy `screenshot.el` unchanged.** It is package-agnostic.
2. **Write a sibling shot list** (`beads-shots.el`) modeled on
   `gascity-shots.el`: put your package on the `load-path`, set the
   engine variables, and define one thunk per view that opens it and
   returns the buffer to capture. Set `screenshot-async-process-regexp`
   to your package's async process name so the engine waits for data.
3. **Copy `capture.sh`** and edit four things: the `SHOTS_EL` path, the
   manifest, `GASCITY_*` env exports, and the image geometry.

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
- **Empty views are not faked.** The mail inbox, for instance, is left
  out of the manifest when the city has no mail rather than shown empty;
  add it back when there is mail to show.
