#!/bin/sh
# scripts/e2e-harness.sh - hardened helpers for the tmux-Emacs e2e protocol.
#
# Source this file from an e2e dogfood pass (see docs/qa/ for past passes):
#
#   . scripts/e2e-harness.sh
#
# Why this exists: pi's bash tool has no default timeout, so a blocking
# emacs/tmux call in an e2e pass can freeze a worker for hours.  Two real
# incidents (2026-09-13..15, city bead ec-abvq):
#
#   1. A batch-emacs elisp diagnostic with a buggy (while t ...) loop spun a
#      CPU core for 17h20m.
#   2. An e2e emacs (server-name gce-e2e) spun 100% CPU for 23h in a
#      TRAMP/ssh retry loop; its emacsclient evals blocked the worker 54min+.
#
# Rules encoded here:
#
#   - EVERY blocking emacs/emacsclient call goes through timeout(1).  Never
#     call emacs, emacsclient, or a foreground tmux attach without one.
#   - Never assume the tmux session exists: a dead tmux server makes
#     send-keys a silent no-op while the test still blocks.  Check
#     has-session first and fail fast with a clear message.
#   - Prefer batch emacs (emacs --batch --eval) over interactive emacs where
#     the test does not actually need a running server.
#   - Any elisp loop used in a diagnostic must carry a hard iteration cap
#     (see e2e_emacs_batch and the capped-loop idiom in its docstring).

set -eu

# ---------------------------------------------------------------------------
# Tunables (override in the environment before sourcing).

# Interactive emacs startup inside tmux (slow over TRAMP).
: "${E2E_EMACS_START_TIMEOUT:=120}"
# emacsclient -e evals against the live test Emacs.
: "${E2E_EVAL_TIMEOUT:=60}"
# Batch emacs diagnostics (compile checks, json probes, ...).
: "${E2E_BATCH_TIMEOUT:=120}"
# Keystroke delivery / pane captures (fast, but a dead server must not hang).
: "${E2E_TMUX_TIMEOUT:=15}"
# Default tmux session name for the e2e Emacs (matches AGENTS.md protocol).
: "${E2E_SESSION:=gce-e2e}"
# Default Emacs server socket name inside that session.
: "${E2E_SERVER_NAME:=gce-e2e}"

# ---------------------------------------------------------------------------
# tmux helpers: always verify the session exists BEFORE touching it.

e2e_tmux_session_exists() {
    tmux has-session -t "$1" 2>/dev/null
}

e2e_require_tmux_session() {
    if ! e2e_tmux_session_exists "$1"; then
        echo "e2e: tmux session '$1' does not exist (dead server or never started);" \
             "refusing to send keys / capture into a no-op target" >&2
        return 1
    fi
}

# e2e_send_keys SESSION KEYS
# Deliver keystrokes to a live tmux session, fail fast if it is gone.
# KEYS is split on whitespace and sent unquoted, so tmux treats each token
# as a KEY NAME when it knows one (Enter, Tab, C-x, M-x, ...) and as literal
# text otherwise.  Mind tmux 3.7c (ga-rs12): multi-word names like "Return"
# are NOT key names there — tmux types the word literally instead of
# pressing the key.  Use the single-word names (Enter, Space, BSpace,
# Escape, Up, Down, F1, Home, ...), hex via e2e_send_keys_hex, or -H codes
# for anything the names miss.
e2e_send_keys() {
    _s="$1"; _keys="$2"
    e2e_require_tmux_session "$_s" || return 1
    timeout "$E2E_TMUX_TIMEOUT" tmux send-keys -t "$_s" $_keys
}

# e2e_send_keys_literal SESSION TEXT
# Type TEXT as literal characters (tmux send-keys -l) — no key-name
# interpretation at all.  For prose, paths, and anything containing
# characters tmux would otherwise read as key names.
e2e_send_keys_literal() {
    _s="$1"; _text="$2"
    e2e_require_tmux_session "$_s" || return 1
    timeout "$E2E_TMUX_TIMEOUT" tmux send-keys -t "$_s" -l "$_text"
}

# e2e_send_keys_hex SESSION HEX...
# Send raw key codes by hex byte (tmux send-keys -H, tmux >= 3.4) —
# e.g. 0d for Enter, 09 for Tab.  The unambiguous escape hatch when a key
# name is unreliable on the installed tmux (ga-rs12).
e2e_send_keys_hex() {
    _s="$1"; shift
    e2e_require_tmux_session "$_s" || return 1
    timeout "$E2E_TMUX_TIMEOUT" tmux send-keys -t "$_s" -H "$@"
}

# e2e_capture SESSION
# Capture the visible pane of a live tmux session.
e2e_capture() {
    _s="$1"
    e2e_require_tmux_session "$_s" || return 1
    timeout "$E2E_TMUX_TIMEOUT" tmux capture-pane -p -t "$_s"
}

# e2e_start_emacs [LOAD_PATH_EXTRA]
# Start the e2e Emacs in a NEW dedicated tmux session (detached).  The tmux
# call itself is non-blocking; the Emacs it hosts is later probed with
# bounded evals only.  Refuses to clobber an existing session.
e2e_start_emacs() {
    if e2e_tmux_session_exists "$E2E_SESSION"; then
        echo "e2e: tmux session '$E2E_SESSION' already exists; kill it first" >&2
        return 1
    fi
    timeout "$E2E_EMACS_START_TIMEOUT" \
        tmux new-session -d -s "$E2E_SESSION" \
        "emacs -nw -Q --eval '(progn (setq server-name \"$E2E_SERVER_NAME\") (server-start))'"
}

# e2e_emacs_ready [TOTAL_SECS]
# Return once the e2e Emacs server answers evals (bounded total wait).
# Probes (emacs-pid) rather than (server-name): under -Q server.el is not
# preloaded, so the server-name variable is void and the probe would never
# fire even with the server up.
e2e_emacs_ready() {
    e2e_wait_for '(emacs-pid)' "${1:-60}" 2
}

# e2e_kill_emacs
# Tear the e2e session down (idempotent).
e2e_kill_emacs() {
    if e2e_tmux_session_exists "$E2E_SESSION"; then
        timeout "$E2E_TMUX_TIMEOUT" tmux kill-session -t "$E2E_SESSION" || true
    fi
}

# ---------------------------------------------------------------------------
# Emacs helpers: bounded, always.

# e2e_emacs_batch ELISP...
# Batch emacs for diagnostics that do not need a running server.  Any elisp
# loop passed here MUST carry a hard iteration cap, e.g.:
#
#   (let ((max-iter 10000)) (while (and (> max-iter 0) <cond>) (setq max-iter (1- max-iter))))
#
e2e_emacs_batch() {
    timeout "$E2E_BATCH_TIMEOUT" emacs -Q --batch --eval "$@"
}

# e2e_eval ELISP
# Evaluate ELISP in the live e2e Emacs.  Self-terminates within
# E2E_EVAL_TIMEOUT even if the Emacs is wedged (TRAMP retry loop, modal
# prompt, ...), so the worker is never blocked longer than that.
e2e_eval() {
    timeout "$E2E_EVAL_TIMEOUT" \
        emacsclient --socket-name "$E2E_SERVER_NAME" --eval "$@"
}

# e2e_eval_quiet ELISP
# Same as e2e_eval but returns non-zero without a traceback dump on timeout;
# useful inside polling loops.
e2e_eval_quiet() {
    e2e_eval "$@" 2>/dev/null
}

# e2e_wait_for ELISP [TOTAL_SECS] [POLL_SECS]
# Poll the live Emacs until ELISP evaluates non-nil, or give up after
# TOTAL_SECS (default 60).  Each probe is individually bounded, so a wedged
# Emacs surfaces as a timeout instead of a hang.
e2e_wait_for() {
    _elisp="$1"; _total="${2:-60}"; _poll="${3:-2}"
    _deadline=$(( $(date +%s) + _total ))
    while [ "$(date +%s)" -lt "$_deadline" ]; do
        if e2e_eval_quiet "$_elisp" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$_poll"
    done
    echo "e2e: waited ${_total}s for emacs to report true: $_elisp" >&2
    return 1
}
