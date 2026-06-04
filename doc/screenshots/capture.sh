#!/usr/bin/env bash
#
# capture.sh --- Regenerate the gascity.el documentation screenshots.
#
# Pipeline, end to end:
#   1. Start a *private* headless Wayland compositor (sway) so capture
#      frames never appear on the user's desktop.
#   2. Run a graphical Emacs once per theme, loading gascity.el + the
#      reusable engine (screenshot.el) + the shot list (gascity-shots.el),
#      which renders each porcelain view and exports a raw PNG.
#   3. Compress each raw PNG to an 8-bit-palette full image and a small
#      thumbnail under doc/images/ (committed; the raws are throwaway).
#
# Requirements: emacs (pgtk/GUI), sway (wlroots headless backend),
# ImageMagick `convert`, the gc CLI on PATH, a running city, ef-themes,
# and a beads.el checkout (BEADS_REPO).  All verified on Emacs 30.2.
#
# Reuse (e.g. beads.el): copy screenshot.el unchanged, write a sibling
# beads-shots.el with your views, and point THEMES/SHOTS below at it.
# See README.md in this directory.
#
# Usage:
#   ./capture.sh              # full pipeline (capture + compress)
#   ./capture.sh --compress   # recompress existing raws only
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
IMAGES_DIR="$REPO/doc/images"
STAGING="${GASCITY_SHOT_STAGING:-/tmp/gascity-shots}"
SHOTS_EL="$HERE/gascity-shots.el"

export BEADS_REPO="${BEADS_REPO:-$HOME/workspace/beads.el}"
export GASCITY_REPO="$REPO"
export GASCITY_SHOT_DIR="${GASCITY_SHOT_DIR:-$HOME/bright-lights}"
export GASCITY_SHOT_RIG="${GASCITY_SHOT_RIG:-gascity.el}"

# Output image geometry.  UI screenshots are flat-colour, so 8-bit palette
# PNGs with dithering disabled compress small and stay crisp.
FULL_W=1500       # full image max width (px); narrower shots keep native size
FULL_COLORS=256   # palette size for the full images
THUMB_W=520       # thumbnail max width (px)
THUMB_COLORS=128  # a preview needs fewer colours

# ---- Capture manifest --------------------------------------------------
# One line per theme: "THEME  SUFFIX  view view view ...".  A view named
# in two themes is captured twice (e.g. the status board, to show theming).
read -r -d '' MANIFEST <<'EOF' || true
ef-elea-dark  -dark   status rig-dashboard session-list convoy-list dolt-list dispatch
ef-cyprus     -light  status session-detail rig-list order-list
EOF

log() { printf '\033[1;36m[capture]\033[0m %s\n' "$*" >&2; }

# ---- Headless compositor lifecycle ------------------------------------
SWAY_PID=""
start_sway() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local conf="$STAGING/sway.conf" logf="$STAGING/sway.log"
  # sway is a *tiling* compositor: by default it forces every window to
  # fill the output, overriding the frame size we set.  Float (and
  # de-chrome) all windows so Emacs's `set-frame-size' is honored and the
  # exported PNG is fitted tightly to the rendered content.
  cat > "$conf" <<'CONF'
xwayland disable
default_border none
default_floating_border none
for_window [app_id=".*"] floating enable, border none
output HEADLESS-1 resolution 2880x1800 position 0,0
CONF
  local before after
  before=$(ls -1 "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | sort || true)
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway -c "$conf" >"$logf" 2>&1 &
  SWAY_PID=$!
  local i=0
  WAYLAND_DISPLAY=""
  while [ $i -lt 50 ]; do
    kill -0 "$SWAY_PID" 2>/dev/null || { log "sway died:"; cat "$logf" >&2; exit 1; }
    after=$(ls -1 "$XDG_RUNTIME_DIR"/wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | sort || true)
    WAYLAND_DISPLAY=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
                        | head -1 | xargs -r basename || true)
    [ -n "$WAYLAND_DISPLAY" ] && break
    sleep 0.2; i=$((i+1))
  done
  [ -z "$WAYLAND_DISPLAY" ] && { log "no headless wayland socket appeared"; cat "$logf" >&2; exit 1; }
  export WAYLAND_DISPLAY GDK_BACKEND=wayland
  log "headless sway on WAYLAND_DISPLAY=$WAYLAND_DISPLAY (pid $SWAY_PID)"
}
stop_sway() { [ -n "$SWAY_PID" ] && kill "$SWAY_PID" 2>/dev/null || true; }
trap stop_sway EXIT INT TERM

# ---- Capture ----------------------------------------------------------
capture() {
  mkdir -p "$STAGING"; : > "$STAGING/capture.log"
  start_sway
  while IFS= read -r line; do
    [ -z "${line// }" ] && continue
    set -- $line
    local theme="$1" suffix="$2"; shift 2
    local views="$*"
    log "theme=$theme suffix=$suffix views=[$views]"
    GASCITY_SHOT_THEME="$theme" \
    GASCITY_SHOT_SUFFIX="$suffix" \
    GASCITY_SHOT_VIEWS="$views" \
    GASCITY_SHOT_OUTDIR="$STAGING" \
      timeout 150 emacs -Q -l "$SHOTS_EL" 2>>"$STAGING/emacs.log" || \
        log "emacs run for $theme exited non-zero (see $STAGING/emacs.log)"
  done <<< "$MANIFEST"
  log "raw captures:"; ls -l "$STAGING"/*.png 2>/dev/null | awk '{print "  "$5, $NF}' >&2 || true
  log "engine log:"; sed 's/^/  /' "$STAGING/capture.log" >&2 || true
}

# ---- Compress ---------------------------------------------------------
compress() {
  mkdir -p "$IMAGES_DIR"
  local total=0 raw
  shopt -s nullglob
  for raw in "$STAGING"/*.png; do
    local name; name="$(basename "$raw" .png)"
    local full="$IMAGES_DIR/$name.png" thumb="$IMAGES_DIR/$name-thumb.png"
    convert "$raw" -strip -resize "${FULL_W}x>" -dither None -colors "$FULL_COLORS" \
            -define png:compression-level=9 "$full"
    convert "$raw" -strip -resize "${THUMB_W}x>" -dither None -colors "$THUMB_COLORS" \
            -define png:compression-level=9 "$thumb"
    local fs ts; fs=$(stat -c%s "$full"); ts=$(stat -c%s "$thumb")
    total=$((total + fs + ts))
    printf '  %-26s full=%6d  thumb=%6d\n' "$name" "$fs" "$ts" >&2
  done
  shopt -u nullglob
  log "doc/images total: $(awk "BEGIN{printf \"%.1f\", $total/1024}") KiB"
}

case "${1:-}" in
  --compress) compress ;;
  *)          capture; compress ;;
esac
log "done."
