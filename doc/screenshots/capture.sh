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
# The capture is *scoped*: `--scope all` regenerates every manifest view,
# a named subset regenerates only those views, and `--scope changed`
# selects the views whose owning source file changed in the working tree.
# A subset run never rewrites or deletes an image outside the selected
# scope, and `--verify` proves both reproducibility (two byte-identical
# runs) and subset isolation (non-selected committed images untouched).
#
# Requirements: emacs (pgtk/GUI), sway (wlroots headless backend),
# ImageMagick `convert`, the gc CLI on PATH, a city, ef-themes, and a
# beads.el checkout (BEADS_REPO).  All verified on Emacs 30.2/31.1.
#
# Reuse (e.g. beads.el): copy screenshot.el unchanged, write a sibling
# beads-shots.el with your views, and point THEMES/SHOTS and the manifest
# below at it.  See README.md in this directory.
#
# Usage:
#   ./capture.sh                          # full pipeline, scope all
#   ./capture.sh --scope cockpit,health   # only the named views
#   ./capture.sh --scope changed          # only views whose source changed
#   ./capture.sh --verify cockpit         # capture twice, assert identical
#   ./capture.sh --check-isolation cockpit # prove other images untouched
#   ./capture.sh --list-scope --scope all # print the selected view names
#   ./capture.sh --self-test              # unit-check scope + isolation
#   ./capture.sh --compress               # recompress existing raws only
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve the repository root from the script's own location, independent of
# the caller's working directory (`make screenshots' runs the script by path).
# Prefer the enclosing git work tree, so a copy in a VPATH build tree still
# finds the source root; fall back to the historical script-relative
# doc/screenshots -> repo-root assumption when git is unavailable or this is
# not a checkout (e.g. a distributed copy).
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO" ]; then
  REPO="$(cd "$HERE/../.." && pwd)"
fi
IMAGES_DIR="${GASCITY_SHOT_IMAGES:-$REPO/doc/images}"
STAGING="${GASCITY_SHOT_STAGING:-/tmp/gascity-shots}"
SHOTS_EL="$HERE/gascity-shots.el"
FIXTURE_SH="$HERE/fixture.sh"
WATCHDOG="${GASCITY_SHOT_WATCHDOG:-400}"

export BEADS_REPO="${BEADS_REPO:-$HOME/workspace/beads.el}"
export GASCITY_REPO="$REPO"
export GASCITY_SHOT_RIG="${GASCITY_SHOT_RIG:-gascity.el}"

# Output image geometry.  UI screenshots are flat-colour, so 8-bit palette
# PNGs with dithering disabled compress small and stay crisp.
FULL_W=1500       # full image max width (px); narrower shots keep native size
FULL_COLORS=256   # palette size for the full images
THUMB_W=520       # thumbnail max width (px)
THUMB_COLORS=128  # a preview needs fewer colours

# ---- Capture manifest --------------------------------------------------
# One line per theme: "THEME  SUFFIX  view view view ...".  A view named
# in two themes is captured twice (e.g. the cockpit, to show theming).
# The suffix is the "-<theme>" half of the committed name, so the output is
# exactly <view>-<theme>.png and <view>-<theme>-thumb.png.
# ef-deuteranopia-dark is the standard dark theme for every view; ef-cyprus
# is kept for the single deliberate light capture, cockpit-light, which
# pairs with cockpit-dark to demonstrate theming.
read -r -d '' MANIFEST <<'EOF' || true
ef-deuteranopia-dark  -dark   cockpit dispatch agents agents-tree runs events health rig-dashboard session-list convoy-list dolt-list lighter costs bookmarks mail-inbox cities rig-list order-list remote-cities terminal-attach sling-plain sling-cold sling-formula sling-on sling-preview
ef-cyprus             -light  cockpit
EOF

# Owning source file(s) per view, for `--scope changed` (plan-review P2).
# A view is selected when any of its sources changed against HEAD (working
# tree or index) or is untracked.  Keep in sync with the manual chapters
# and the `@shot` invocations in doc/gascity.texi.
declare -A VIEW_SOURCES=(
  [cockpit]="lisp/gascity-status.el lisp/gascity-dashboard.el lisp/gascity-section.el"
  [dispatch]="lisp/gascity-dashboard.el lisp/gascity-action.el"
  [agents]="lisp/gascity-agents.el lisp/gascity-tabulated.el"
  [agents-tree]="lisp/gascity-agents.el"
  [runs]="lisp/gascity-runs.el lisp/gascity-tabulated.el"
  [events]="lisp/gascity-events.el lisp/gascity-tabulated.el"
  [health]="lisp/gascity-health.el"
  [rig-dashboard]="lisp/gascity-rig.el"
  [session-list]="lisp/gascity-session.el lisp/gascity-tabulated.el"
  [convoy-list]="lisp/gascity-tabulated.el"
  [dolt-list]="lisp/gascity-tabulated.el"
  [lighter]="lisp/gascity-pulse.el lisp/gascity-dashboard.el"
  [mail-inbox]="lisp/gascity-mail.el lisp/gascity-tabulated.el"
  [cities]="lisp/gascity-cities.el"
  [rig-list]="lisp/gascity-rig.el lisp/gascity-tabulated.el"
  [order-list]="lisp/gascity-tabulated.el"
  [costs]="lisp/gascity-health.el"
  [bookmarks]="lisp/gascity-bookmark.el"
  [remote-cities]="lisp/gascity-remote.el lisp/gascity-cities.el"
  [terminal-attach]="lisp/gascity-terminal.el lisp/gascity-session.el"
  [sling-plain]="lisp/gascity-action.el"
  [sling-cold]="lisp/gascity-action.el"
  [sling-formula]="lisp/gascity-action.el"
  [sling-on]="lisp/gascity-action.el"
  [sling-preview]="lisp/gascity-action.el"
)

log() { printf '\033[1;36m[capture]\033[0m %s\n' "$*" >&2; }

usage_error() {
  printf 'capture.sh: %s\n' "$*" >&2
  printf 'Try --help for usage.\n' >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage: capture.sh [--scope SCOPE] [--verify [SCOPE]] [--check-isolation SCOPE]
                  [--list-scope] [--self-test] [--compress] [--help]

  --scope SCOPE       all (default), changed, or a comma-separated view list.
  --verify [SCOPE]    Capture SCOPE twice into two $TMPDIR staging dirs and
                      fail, naming the first drifting image, unless every
                      output is byte-identical.  Then run the subset-isolation
                      check.
  --check-isolation SCOPE
                      Capture SCOPE once and prove that every committed image
                      outside the scope stays byte-identical (digest + mtime).
  --list-scope        Print the selected view names, one per line, and exit.
  --self-test         Run the built-in scope + isolation unit checks and exit.
  --compress          Recompress the raw PNGs already in GASCITY_SHOT_STAGING.
  --help              Show this help.

Environment:
  GASCITY_SHOT_DIR       directory `gc' resolves the city from (a fixture
                         created by fixture.sh when present, else ~/emacs-city)
  GASCITY_SHOT_STAGING   raw PNG staging dir (default: /tmp/gascity-shots)
  GASCITY_SHOT_IMAGES    committed image dir (default: doc/images)
  GASCITY_SHOT_BASE      git ref for `--scope changed' (default: HEAD)
  GASCITY_SHOT_ENGINE    capture executable override (used by the tests;
                         skips the compositor and Emacs)
  GASCITY_SHOT_WATCHDOG  seconds before a capture Emacs kills itself (400)
EOF
}

# ---- Isolation ---------------------------------------------------------
# Unset every variable in beads-test-isolation-env-vars so a value inherited
# from an agent shell cannot reroute the capture into the repo or a live
# store.  fixture.sh hardcodes the same four names; keep them in sync.
for _var in BEADS_DIR BEADS_DOLT_PORT BEADS_DOLT_SERVER_PORT GC_DOLT_PORT; do
  unset "$_var"
done
unset _var
# The terminal-attach shot creates and attaches to a fixture tmux session.
# A leaked TMUX from a developer's own tmux client would split the pre-step
# and the terminal across two servers (the terminal backend does not forward
# it), and a leaked default socket would touch the developer's sessions.
# Use a fixture-private tmux server instead.
unset TMUX

# ---- Scope resolution --------------------------------------------------

all_views() {
  local line theme suffix
  local IFS=$' \t\n'
  while IFS= read -r line; do
    [ -z "${line// }" ] && continue
    # shellcheck disable=SC2086
    set -- $line
    theme="$1"; suffix="$2"; shift 2
    printf '%s\n' "$@"
  done <<< "$MANIFEST" | awk '!seen[$0]++'
}

all_output_names() {
  local line theme suffix v
  local IFS=$' \t\n'
  while IFS= read -r line; do
    [ -z "${line// }" ] && continue
    # shellcheck disable=SC2086
    set -- $line
    theme="$1"; suffix="$2"; shift 2
    for v in "$@"; do printf '%s%s\n' "$v" "$suffix"; done
  done <<< "$MANIFEST"
}

view_known() { all_views | grep -qxF "$1"; }

# `--scope changed`: the working tree against HEAD (covers index + worktree)
# plus untracked files from `git status'.  GASCITY_SHOT_CHANGED_FILES is the
# test seam; when set it is used verbatim (newline-separated).
changed_views() {
  local base="${GASCITY_SHOT_BASE:-HEAD}" changed view src hit
  local IFS=$' \t\n'
  if [ -n "${GASCITY_SHOT_CHANGED_FILES:-}" ]; then
    changed="$(printf '%s\n' "$GASCITY_SHOT_CHANGED_FILES")"
  else
    changed="$(
      { git -C "$REPO" diff --name-only "$base" 2>/dev/null || true
        git -C "$REPO" status --porcelain 2>/dev/null | awk '{print $NF}'
      } | sort -u
    )"
  fi
  SELECTED_VIEWS=()
  while read -r view; do
    [ -n "$view" ] || continue
    hit=0
    # shellcheck disable=SC2086
    for src in ${VIEW_SOURCES[$view]:-}; do
      if printf '%s\n' "$changed" | grep -qxF "$src"; then hit=1; break; fi
    done
    [ "$hit" = 1 ] && SELECTED_VIEWS+=("$view")
  done < <(all_views)
  return 0
}

resolve_scope() {
  local scope="$1" v
  SELECTED_VIEWS=()
  case "$scope" in
    all)
      while IFS= read -r v; do SELECTED_VIEWS+=("$v"); done < <(all_views) ;;
    changed)
      changed_views ;;
    *)
      local IFS=','
      for v in $scope; do
        [ -n "$v" ] || continue
        view_known "$v" || usage_error "unknown view in --scope: $v"
        SELECTED_VIEWS+=("$v")
      done
      [ "${#SELECTED_VIEWS[@]}" -gt 0 ] || usage_error "empty --scope" ;;
  esac
  [ "${#SELECTED_VIEWS[@]}" -gt 0 ] || log "no views selected for scope $scope"
}

view_selected() {
  local v
  for v in "${SELECTED_VIEWS[@]}"; do [ "$v" = "$1" ] && return 0; done
  return 1
}

# The exact committed names (view+suffix) a scope would write.
selected_output_names() {
  local line theme suffix v
  local IFS=$' \t\n'
  while IFS= read -r line; do
    [ -z "${line// }" ] && continue
    # shellcheck disable=SC2086
    set -- $line
    theme="$1"; suffix="$2"; shift 2
    for v in "$@"; do
      view_selected "$v" && printf '%s%s\n' "$v" "$suffix"
    done
  done <<< "$MANIFEST"
}

# NAME is a raw/committed image base name (e.g. cockpit-dark or
# cockpit-dark-thumb); true when the active scope writes it.
is_selected_output() {
  local name="${1%-thumb}" out
  while IFS= read -r out; do
    [ "$out" = "$name" ] && return 0
  done < <(selected_output_names)
  return 1
}

# ---- Fixture project lifecycle ----------------------------------------
# WI-3 owns fixture.sh; when it is present the capture runs against the
# throwaway fixture it creates.  Without it, fall back to a caller-provided
# GASCITY_SHOT_DIR (or the historical live ~/emacs-city default).

PROJECT="${GASCITY_SHOT_DIR:-}"
CREATED_PROJECT=""

ensure_project() {
  if [ -n "$PROJECT" ]; then
    [ -d "$PROJECT" ] || usage_error "GASCITY_SHOT_DIR is not a directory: $PROJECT"
    export GASCITY_SHOT_DIR="$PROJECT"
    return
  fi
  if [ -r "$FIXTURE_SH" ]; then
    # WI-3 fixture.sh contract: `--create' prints FIXTURE_CITY=/FIXTURE_RIG=/
    # FIXTURE_RIG_NAME= for the throwaway city and records it; `--seed' loads
    # the role-addressed data; `--teardown --city' removes it.  Parse the
    # FIXTURE_CITY line, not the first line of output.
    local created city gc_home
    created="$("$FIXTURE_SH" --create)"
    city="$(printf '%s\n' "$created" | sed -n 's/^FIXTURE_CITY=//p')"
    [ -n "$city" ] && [ -d "$city" ] || usage_error "fixture.sh --create returned no FIXTURE_CITY"
    PROJECT="$city"
    CREATED_PROJECT="$PROJECT"
    "$FIXTURE_SH" --seed --city "$PROJECT" >&2
    # Point gc's user-level state (the machine-wide city registry) at the
    # fixture, so the Cities view lists the fixture city and never the
    # developer's live cities.  GC_HOME is inherited by the capture Emacs.
    gc_home="$(printf '%s\n' "$created" | sed -n 's/^FIXTURE_GC_HOME=//p')"
    if [ -n "$gc_home" ] && [ -d "$gc_home" ]; then
      export GC_HOME="$gc_home"
      export GASCITY_SHOT_GC_HOME="$gc_home"
      log "fixture GC_HOME: $GC_HOME"
    fi
    # The fixture's only rig is demo-rig; the rig dashboard and rig
    # bookmark shots must feature it, not the historical live-city default.
    export GASCITY_SHOT_RIG="$(printf '%s\n' "$created" | sed -n 's/^FIXTURE_RIG_NAME=//p')"
    GASCITY_SHOT_RIG="${GASCITY_SHOT_RIG:-demo-rig}"
    # A fixture-private tmux server for the terminal-attach shot (see the
    # TMUX unset above): both the shot's `new-session' and the attach use it.
    export TMUX_TMPDIR="$PROJECT/tmux"
    mkdir -p "$TMUX_TMPDIR"
    export GASCITY_SHOT_DIR="$PROJECT"
    log "fixture city: $PROJECT (rig $GASCITY_SHOT_RIG)"
  else
    export GASCITY_SHOT_DIR="$HOME/emacs-city"
    log "GASCITY_SHOT_DIR default: $GASCITY_SHOT_DIR (no fixture.sh)"
  fi
}

teardown_project() {
  if [ -n "$CREATED_PROJECT" ] && [ -r "$FIXTURE_SH" ]; then
    [ -n "$TMUX_TMPDIR" ] && tmux kill-server >/dev/null 2>&1 || true
    "$FIXTURE_SH" --teardown --city "$CREATED_PROJECT" >/dev/null 2>&1 || true
  fi
}

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

cleanup() { stop_sway; teardown_project; }
trap cleanup EXIT INT TERM

# ---- Capture ----------------------------------------------------------

run_engine() {
  local theme="$1" suffix="$2" views="$3" outdir="$4"
  if [ -n "${GASCITY_SHOT_ENGINE:-}" ]; then
    # The override owns its own display; this is the seam the shell tests
    # use so scope/verify/isolation are exercisable without sway or Emacs.
    GASCITY_SHOT_THEME="$theme" GASCITY_SHOT_SUFFIX="$suffix" \
    GASCITY_SHOT_VIEWS="$views" GASCITY_SHOT_OUTDIR="$outdir" \
      timeout "$WATCHDOG" "$GASCITY_SHOT_ENGINE" \
      || log "engine exited non-zero for theme $theme"
  else
    GASCITY_SHOT_THEME="$theme" GASCITY_SHOT_SUFFIX="$suffix" \
    GASCITY_SHOT_VIEWS="$views" GASCITY_SHOT_OUTDIR="$outdir" \
      timeout "$WATCHDOG" emacs -Q -l "$SHOTS_EL" 2>>"$outdir/emacs.log" \
      || log "emacs exited non-zero for theme $theme (see $outdir/emacs.log)"
  fi
}

capture_into() {
  local outdir="$1"
  mkdir -p "$outdir"
  : > "$outdir/capture.log"
  local line theme suffix views filtered v
  while IFS= read -r line; do
    [ -z "${line// }" ] && continue
    # shellcheck disable=SC2086
    set -- $line
    theme="$1"; suffix="$2"; shift 2
    views="$*"
    filtered=""
    for v in $views; do
      if view_selected "$v"; then filtered="$filtered $v"; fi
    done
    [ -z "${filtered// }" ] && continue
    log "theme=$theme suffix=$suffix views=[$filtered]"
    run_engine "$theme" "$suffix" "$filtered" "$outdir"
  done <<< "$MANIFEST"
  log "raw captures:"; ls -l "$outdir"/*.png 2>/dev/null \
    | awk '{print "  "$5, $NF}' >&2 || true
}

# ---- Compress ---------------------------------------------------------
# Only scope-selected names are ever written: a subset run cannot touch an
# image outside the scope (the AC-4 isolation guarantee compress enforces).
compress() {
  local srcdir="$1" total=0 raw name full thumb fs ts
  mkdir -p "$IMAGES_DIR"
  shopt -s nullglob
  for raw in "$srcdir"/*.png; do
    name="$(basename "$raw" .png)"
    is_selected_output "$name" || continue
    full="$IMAGES_DIR/$name.png" thumb="$IMAGES_DIR/$name-thumb.png"
    convert "$raw" -strip -resize "${FULL_W}x>" -dither None -colors "$FULL_COLORS" \
            -define png:compression-level=9 "$full"
    convert "$raw" -strip -resize "${THUMB_W}x>" -dither None -colors "$THUMB_COLORS" \
            -define png:compression-level=9 "$thumb"
    fs=$(stat -c%s "$full"); ts=$(stat -c%s "$thumb")
    total=$((total + fs + ts))
    printf '  %-26s full=%6d  thumb=%6d\n' "$name" "$fs" "$ts" >&2
  done
  shopt -u nullglob
  log "doc/images total: $(awk "BEGIN{printf \"%.1f\", $total/1024}") KiB"
}

# ---- Verify -----------------------------------------------------------
verify_runs() {
  local a="$1" b="$2" name fa fb drift=0 count=0
  local afiles bfiles
  shopt -s nullglob
  afiles=("$a"/*.png)
  bfiles=("$b"/*.png)
  shopt -u nullglob
  if [ "${#afiles[@]}" -ne "${#bfiles[@]}" ]; then
    log "verify: DRIFT image count differs: run1=${#afiles[@]} run2=${#bfiles[@]}"
    drift=1
  fi
  for fa in "${afiles[@]:-}"; do
    [ -e "$fa" ] || continue
    name="$(basename "$fa")"
    fb="$b/$name"
    if [ ! -f "$fb" ]; then
      log "verify: DRIFT missing in second run: $name"; drift=1; continue
    fi
    if cmp -s "$fa" "$fb"; then count=$((count+1)); else log "verify: DRIFT $name"; drift=1; fi
  done
  for fb in "${bfiles[@]:-}"; do
    [ -e "$fb" ] || continue
    name="$(basename "$fb")"
    [ -f "$a/$name" ] || { log "verify: DRIFT extra in second run: $name"; drift=1; }
  done
  if [ "$drift" -ne 0 ]; then
    printf 'capture.sh: verify FAILED for scope %s; drifting image(s) above\n' "$SCOPE" >&2
    exit 1
  fi
  [ "$count" -gt 0 ] || { printf 'capture.sh: verify: no images captured for scope %s\n' "$SCOPE" >&2; exit 1; }
  log "verify: byte-identical for $count image(s) (scope $SCOPE)"
}

# Every selected manifest view must actually produce its image.  A thunk that
# errors (or a view the fixture cannot render) writes no file, and
# `verify_runs' would otherwise pass the scope silently.  `--verify' fails
# loudly on a missing selected output instead of treating "produced no image"
# as success.
coverage_check() {
  local outdir="$1" name missing=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ ! -f "$outdir/$name.png" ]; then
      log "coverage: MISSING image for selected view: $name"
      missing=1
    fi
  done < <(selected_output_names)
  if [ "$missing" -ne 0 ]; then
    printf 'capture.sh: coverage FAILED for scope %s; missing image(s) above\n' "$SCOPE" >&2
    exit 1
  fi
  log "coverage: every selected view produced an image (scope $SCOPE)"
}

# ---- Subset isolation -------------------------------------------------
# Snapshot the digest+mtime of every committed image a scope does NOT write.
snapshot_unselected() {
  local dir="$1" f full name
  shopt -s nullglob
  for f in "$dir"/*.png; do
    full="$(basename "$f")"
    name="${full%.png}"
    is_selected_output "$name" && continue
    printf '%s %s %s\n' \
      "$(sha256sum "$f" | awk '{print $1}')" "$(stat -c %Y "$f")" "$full"
  done
  shopt -u nullglob
}

# Regenerate SCOPE into a throwaway copy of the committed images and assert
# every non-selected image keeps its exact bytes and mtime (AC-4).
isolation_check() {
  local srcdir="$1" tmp before after unselected saved
  command -v convert >/dev/null 2>&1 || { log "isolation: convert missing; skipped"; return 0; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gascity-isolation.XXXXXX")"
  mkdir -p "$tmp/images"
  shopt -s nullglob
  local f
  for f in "$IMAGES_DIR"/*.png; do cp -p "$f" "$tmp/images/"; done
  shopt -u nullglob
  before="$tmp/before.txt"; after="$tmp/after.txt"
  snapshot_unselected "$tmp/images" > "$before"
  unselected="$(wc -l < "$before")"
  saved="$IMAGES_DIR"
  IMAGES_DIR="$tmp/images"
  compress "$srcdir"
  IMAGES_DIR="$saved"
  snapshot_unselected "$tmp/images" > "$after"
  if ! diff -u "$before" "$after" > "$tmp/diff" 2>&1; then
    log "isolation: FAILED; a non-selected image changed:"
    sed 's/^/  /' "$tmp/diff" >&2
    rm -rf "$tmp"
    exit 1
  fi
  rm -rf "$tmp"
  if [ "$unselected" -eq 0 ]; then
    log "isolation: OK (no non-selected committed image to check; scope $SCOPE)"
  else
    log "isolation: OK; $unselected non-selected image(s) byte-identical (scope $SCOPE)"
  fi
}

# ---- Self-test --------------------------------------------------------
# Anonymous coverage for the scope resolver and the isolation guard; only
# bash + ImageMagick.  Run by `capture.sh --self-test`.
self_test() {
  command -v convert >/dev/null 2>&1 || { log "self-test: convert missing; skipped"; return 0; }
  local tmp engine images failures=0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gascity-capture-self.XXXXXX")"
  engine="$tmp/engine.sh"; images="$tmp/images"
  mkdir -p "$images" "$tmp/city"
  cat > "$engine" <<'ENG'
#!/usr/bin/env bash
set -euo pipefail
for v in ${GASCITY_SHOT_VIEWS:-}; do
  convert -size 4x4 xc:white "$GASCITY_SHOT_OUTDIR/${v}${GASCITY_SHOT_SUFFIX:-}.png"
done
ENG
  chmod +x "$engine"

  local name
  while IFS= read -r name; do
    convert -size 4x4 xc:white "$images/$name.png"
    convert -size 2x2 xc:white "$images/$name-thumb.png"
  done < <(all_output_names)

  check() {
    local desc="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
      log "self-test: ok - $desc"
    else
      log "self-test: FAIL - $desc"
      printf '  want: %s\n  got:  %s\n' "$want" "$got" >&2
      failures=$((failures + 1))
    fi
  }

  check "--list-scope subset" "$("$0" --list-scope --scope cockpit,health)" \
        "$(printf 'cockpit\nhealth')"
  check "--list-scope all includes costs" \
        "$("$0" --list-scope --scope all | grep -c '^costs$')" "1"
  check "--list-scope changed from a source" \
        "$(GASCITY_SHOT_CHANGED_FILES='lisp/gascity-status.el' \
           "$0" --list-scope --scope changed | grep -c '^cockpit$')" "1"

  local rc=0 nope_out
  "$0" --list-scope --scope nope >/dev/null 2>&1 || rc=$?
  check "unknown view exits non-zero" "$([ "$rc" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
  nope_out="$("$0" --list-scope --scope nope 2>&1 || true)"
  if printf '%s' "$nope_out" | grep -q 'nope'; then
    log "self-test: ok - unknown view named"
  else
    log "self-test: FAIL - unknown view not named"; failures=$((failures + 1))
  fi

  local iso_log="$tmp/iso.log"
  if GASCITY_SHOT_IMAGES="$images" GASCITY_SHOT_ENGINE="$engine" \
     GASCITY_SHOT_STAGING="$tmp/staging" GASCITY_SHOT_DIR="$tmp/city" \
       "$0" --scope cockpit --check-isolation >"$iso_log" 2>&1; then
    log "self-test: ok - isolation check passes"
  else
    log "self-test: FAIL - isolation check exited non-zero"
    sed 's/^/  /' "$iso_log" >&2
    failures=$((failures + 1))
  fi

  rm -rf "$tmp"
  if [ "$failures" -ne 0 ]; then
    printf 'capture.sh: self-test FAILED (%d failure(s))\n' "$failures" >&2
    exit 1
  fi
  log "self-test: all checks passed"
}

# ---- Argument parsing -------------------------------------------------
SCOPE="all"
SCOPE_SET=0
VERIFY=0
CHECK_ISOLATION=0
COMPRESS_ONLY=0
LIST_SCOPE=0
POSITIONAL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)
      [ $# -ge 2 ] || usage_error "--scope requires an argument"
      SCOPE="$2"; SCOPE_SET=1; shift 2 ;;
    --scope=*)
      SCOPE="${1#--scope=}"; SCOPE_SET=1; shift ;;
    --verify)
      VERIFY=1; shift
      # `--verify cockpit' takes the next word as the scope.
      if [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then SCOPE="$1"; SCOPE_SET=1; shift; fi ;;
    --verify=*)
      VERIFY=1; SCOPE="${1#--verify=}"; SCOPE_SET=1; shift ;;
    --check-isolation)
      CHECK_ISOLATION=1; shift
      if [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then SCOPE="$1"; SCOPE_SET=1; shift; fi ;;
    --check-isolation=*)
      CHECK_ISOLATION=1; SCOPE="${1#--check-isolation=}"; SCOPE_SET=1; shift ;;
    --list-scope)
      LIST_SCOPE=1; shift ;;
    --self-test)
      self_test; exit $? ;;
    --compress)
      COMPRESS_ONLY=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    -*)
      usage_error "unknown argument: $1" ;;
    *)
      [ -z "$POSITIONAL" ] || usage_error "unexpected extra argument: $1"
      POSITIONAL="$1"; shift ;;
  esac
done

# A bare positional scope: `capture.sh --verify cockpit` and `--scope all
# cockpit` both resolve; a scope given twice is an error.
if [ -n "$POSITIONAL" ]; then
  if [ "$SCOPE_SET" = 1 ] && [ "$SCOPE" != "$POSITIONAL" ]; then
    usage_error "scope given twice: $SCOPE and $POSITIONAL"
  fi
  SCOPE="$POSITIONAL"
fi

resolve_scope "$SCOPE"

if [ "$LIST_SCOPE" = 1 ]; then
  for _view in "${SELECTED_VIEWS[@]}"; do printf '%s\n' "$_view"; done
  exit 0
fi

mkdir -p "$STAGING"

if [ "$COMPRESS_ONLY" = 1 ]; then
  compress "$STAGING"
  log "done."
  exit 0
fi

ensure_project

if [ -n "${GASCITY_SHOT_ENGINE:-}" ]; then
  log "using GASCITY_SHOT_ENGINE=$GASCITY_SHOT_ENGINE; skipping the compositor"
else
  start_sway
fi

if [ "$VERIFY" = 1 ]; then
  rm -rf "$STAGING/verify-a" "$STAGING/verify-b"
  capture_into "$STAGING/verify-a"
  capture_into "$STAGING/verify-b"
  coverage_check "$STAGING/verify-a"
  verify_runs "$STAGING/verify-a" "$STAGING/verify-b"
  isolation_check "$STAGING/verify-a"
elif [ "$CHECK_ISOLATION" = 1 ]; then
  rm -rf "$STAGING/run"
  capture_into "$STAGING/run"
  isolation_check "$STAGING/run"
else
  rm -rf "$STAGING"/run-*.png 2>/dev/null || true
  mkdir -p "$STAGING/run"
  capture_into "$STAGING/run"
  compress "$STAGING/run"
fi

log "done."
