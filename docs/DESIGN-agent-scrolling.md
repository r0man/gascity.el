# gascity.el — Agent buffers: transparent mouse + Emacs scrolling

Status: **proposal (research + plan, bead ga-n21o)** — no implementation yet.
Evidence for every load-bearing assumption: `docs/qa/2026-09-29-agent-scroll-mouse-experiments.md`
(E1–E9 below refer to its experiments).

---

## 1. Problem

gascity's agent buffers embed the agent's session through a tmux client
(`gascity-terminal-attach-tmux`). To read the transcript today the user
must press `C-b [`, drive tmux copy-mode with tmux keys, and exit with
`q`. Non-Emacs, and the mouse does nothing on most backends.

## 2. How it works today

- **Renderers.** An attach buffer is a plain terminal-emulator buffer
  created by beads.el's `beads-terminal-spawn` (beads.el/lisp/beads-terminal.el)
  through `gascity-terminal-run` (gascity-terminal.el). Backends:
  ghostel (priority 5), vterm (10), eat (20), ansi-term (40), term (50);
  `gascity-terminal--backend-class` maps `gascity-terminal-backend`,
  `auto` → first available (E1: vterm in a fresh Emacs — ghostel's
  availability is strict about being already loaded).
- **Embedding.** The argv is `env -u TMUX tmux [-L SOCKET] attach-session
  -t SESSION` (`gascity-terminal--attach-argv`), wrapped into a local
  `ssh -t HOST …` for remote cities (`gascity-remote-ssh-argv`). The
  tmux client is a local process in every case; keys and mouse bytes go
  over the local pty, so there is no TRAMP in the input path at all.
- **Keymaps.** `gascity-terminal-attach-map` adds only `C-c b`
  (bead at point) via an `emulation-mode-map-alists` entry keyed on
  `gascity-terminal--attach-keys` — deliberately above local/minor maps
  so it survives vterm/ghostel copy modes. Everything else belongs to
  the pty. `gascity-terminal--unshadow-keys` +
  `gascity-terminal-unshadow-minor-modes` (default
  `(pixel-scroll-precision-mode)`) neutralise global minor-mode keymaps
  (e.g. pixel-scroll's PageUp/PageDown) in terminal buffers, because
  they'd scroll a screen-only buffer for nothing (E2).
- **tmux configuration gascity touches.** Only `status off` (session-
  scoped, in the attach pre-step `gascity-terminal--attach-script`, and
  mirrored into the mode line by `gascity-terminal--status-install`).
  gascity sets **no** `mouse` option; `mouse on` comes from the user's
  `~/.tmux.conf` (E4), `mode-keys emacs` is the tmux default. Sessions
  live on per-city sockets (`gascity-tmux-socket`, resolved per city).

## 3. Option analysis

| # | Option | How it works | What breaks | Effort |
|---|---|---|---|---|
| a | tmux `mouse on` + copy-mode integration | Wheel over the pane → tmux `WheelUpPane/Down` bindings scroll scrollback (copy mode entered/left automatically at tmux's discretion) | Needs a mouse-reporting backend (ghostel/eat); vterm/term users get nothing (E3). Needs `mouse on` (E4). When the agent TUI claims mouse the wheel is a pass-through — correct, not a break (E5) | None–small (ensure the option) |
| b | Terminal mouse passthrough vs Emacs intercept | Same as (a) viewed from Emacs: forward mouse bytes vs intercept wheel events | Intercepting wheel in Emacs and translating to tmux keys is the only way to help vterm/term users; per-backend wheel handling must not break eat/ghostel's own passthrough (E5) | Small (one wheel translator) |
| c | Alternate-screen handling (copy-mode vs scrollback) | The tmux client is always on the alt screen (E2); the Emacs buffer has no scrollback worth scrolling | Any design that scrolls the *Emacs buffer* is dead for attach buffers. Scrolling must happen *inside* tmux (copy mode) | — (rules out alternatives) |
| d | Dedicated scroll sub-mode with Emacs keys | A buffer-local minor mode: first `C-b [` enters copy mode, then Emacs keys are translated to tmux copy-mode bytes; `q`/Esc leave both | Desync when the user leaves copy mode another way (mitigated: the toggle key re-syncs; `q`/Esc are also translated). Collides with nothing while active — the agent sees no keys (E9) | Medium |
| e | What the backend libraries already offer | ghostel: real scrollback + wheel intercept — useless for attach (E2, alt screen); eat: `eat-enable-mouse` passthrough; vterm: none; term: none. Raw-key APIs exist everywhere: `vterm-send-string`, `term-send-raw-string`, `eat-self-input`, `ghostel-send-key`/`-send-string` (control bytes need `-send-key` in semi-char mode, E6) | — | — |

Rejected: driving tmux scrollback via side-channel commands
(`tmux send-keys -X scroll-up` per wheel notch through
`gascity-terminal--run-async`) — one process per notch, latency and
process churn; also rejected: `cat | less`-style re-attach through
non-alt-screen clients — fights the tmux client contract (E2) and the
status mirror.

## 4. Recommended design

Two layers, both inside the attach buffer, no global rebinding:

### D1 — `gascity-terminal-scroll-mode` (the keyboard layer, all backends)

A buffer-local minor mode for attach buffers, toggled per buffer:

- **Enter:** `C-c s` (new binding in `gascity-terminal-attach-map`;
  no §10 collision — the attach map owns only `C-c` keys). It sends
  `C-b` `[` (copy mode on) and activates.
- **Active keys → byte translations** (E6/E7):

  | Emacs key | Sent bytes | tmux effect |
  |---|---|---|
  | `C-p` / `C-n` | `\e[1;5A` / `\e[1;5B` (C-Up/C-Down) | scroll ±1 line (viewport) |
  | `C-v` / `M-v` | `\e[6~` / `\e[5~` | page down/up |
  | `PageDown` / `PageUp` | `\e[6~` / `\e[5~` | page down/up |
  | `M-<` / `M->` | `g`+`0`+`RET` / `G`-equivalent via `M-Up`/`M-Down` until position settles | jump to top/bottom (top via the goto prompt; bottom: `End`/many `C-Down`) |
  | `q`, `Esc` | `q` / `\e` | leave copy mode; mode deactivates itself |

  The mode keys are exactly the keys a Magit-style user expects; inside
  the mode the agent's `C-p`/`C-n` are not reachable (E9) — that is the
  collision resolution: **scrolling is an explicit mode, not a shadowing
  of live keys.**
- **Raw-key adapter** (one function per backend, selected from the
  buffer's major mode — E6):
  - vterm → `vterm-send-string`
  - term/ansi-term → `term-send-raw-string`
  - eat → `eat-self-input`
  - ghostel → `ghostel-send-key` for control bytes,
    `ghostel-send-string` for escape sequences
- **State sync (optimistic + self-healing).** Mode activation assumes
  copy mode on. Each translation is a plain byte send; if the user left
  copy mode out-of-band (e.g. mouse wheel-down after the D3 binding),
  the next translated key shows up in the agent's editor — recoverable
  by re-toggling (`C-c s` sends `q` first if it thinks it is active).
  An optional async resync (`tmux display-message -p #{pane_in_mode}`
  via `gascity-terminal--run-async`, debounced) can refine this later;
  not needed for v1.
- **Indication.** Mode line already carries the status mirror; the
  mirrored string gains a `[scroll]` marker while the mode is active
  (same segment, `gascity-terminal--status-string`).

### D2 — transparent mouse (the wheel layer)

- **Mouse-reporting backends (ghostel/eat):** nothing to implement —
  wheel already scrolls the transcript through tmux's own bindings
  (E4), and is correctly a pass-through when the agent claims mouse
  (E5). gascity only **ensures the precondition**: the attach pre-step
  (`gascity-terminal--attach-script`, one host round trip it already
  makes) additionally runs `set-option -t SESSION mouse on` when
  `show-options -g mouse` reports `off` — session-scoped, undone by the
  same teardown that restores `status` (kill-buffer hook,
  `gascity-terminal--status-teardown`). New custom
  `gascity-terminal-ensure-mouse` (default t).
- **Non-reporting backends (vterm/term):** bind `<wheel-up>`/`<wheel-down>`
  in the scroll layer: first notch sends `C-b [` then 3 × C-Up (or, when
  already in copy mode, just the C-Up/Down runs); ~10 lines per notch,
  matching tmux's `-N 5` feel. These bindings live in the same minor
  mode as D1's map, so enabling scroll mode also arms the wheel —
  **toggling `C-c s` upgrades a vterm attach to full mouse + key
  scrolling with no tmux-side dependencies.** `mouse-follow` subtleties
  (window point vs pane cursor) do not apply: bytes only.

### D3 — wheel-down exits copy mode (tmux binding patch, all backends)

tmux 3.7c does not leave copy mode when wheeling to the bottom (E8) —
the transcript would never "snap back to live". The attach pre-step
installs one session-scoped binding alongside `status off`:

```
bind -T copy-mode WheelDownPane select-pane \
  \; if -F '#{==:#{scroll_position},0}' 'send -X cancel' 'send -X -N 5 scroll-down'
```

and teardown unbinds it (like the `set-option -u status` restore).
Gated by the same `gascity-terminal-ensure-mouse` switch.

### Interaction with existing conventions

- New keys: `C-c s` in `gascity-terminal-attach-map` only (an attach
  buffer's keys belong to the pty; `C-c` prefix is the established
  exception — `C-c b`). No §10 conflicts; dashboards (`t`/`RET` attach)
  are unchanged. `S` remains sling.
- Non-blocking (D9): every tmux change rides the pre-step's existing
  single host round trip; no new sync gc/tmux call.
- Remote cities: zero extra work — the terminal is a local client in
  both shapes (§2); bytes travel over the local ssh pty. The pre-step
  changes run through `gascity-terminal--run-async` for both local and
  remote, already the case.
- The status mirror, project pinning, eldoc wiring are untouched.

## 5. Phased plan + acceptance criteria

1. **P0 — mouse for everyone who can have it.** Pre-step ensures
   `mouse on` + installs the D3 wheel-exit binding; teardown restores.
   *Accept:* attach to bright-lights agent; wheel scrolls; wheeling to
   bottom returns to live tail; external `tmux attach` sees default
   bindings after buffer kill; all over TRAMP.
2. **P1 — scroll sub-mode.** `gascity-terminal-scroll-mode` with the
   D1 translation table + per-backend raw-key adapter + mode-line
   marker. *Accept:* on ghostel and vterm (and term), `C-c s` then
   `C-p`/`C-n`/`C-v`/`M-v`/`PageUp`/`q` drive copy mode exactly as the
   E6 table; agent never receives a key while the mode is active;
   `C-c s` re-syncs after an out-of-band copy-mode exit.
3. **P2 — wheel translation for non-reporting backends.** Wheel
   bindings in the scroll-mode map (D2). *Accept:* vterm attach, mouse
   scrolls the transcript after enabling the mode; eat/ghostel behaviour
   unchanged (their native passthrough wins).
4. **P3 — polish.** Documentation (doc/gascity.texi + the attach
   commentary), `gascity-terminal-ensure-mouse` custom, echo-area
   feedback on toggle, qa report from the live pass.

## 6. Test plan

- **ERT (pure, `cl-letf` stubs):**
  - translation table: `gascity-terminal--scroll-sequence` (PPage, C-Up,
    …) is a pure function of an Emacs key — table-driven tests;
  - raw-key adapter dispatch per backend major mode;
  - `gascity-terminal--attach-script` emits `mouse on` /
    `bind WheelDownPane` fragments when the new option is on (string
    assertions, as today's script tests do);
  - teardown restores (`-u` fragments) — no new store/async verbs, so
    the non-blocking verb guard in `lisp/test/gascity-store-test.el`
    needs no additions (the mode sends raw bytes, spawns nothing).
- **Live e2e (the acceptance gate; harness rules: timeouts, no
  unbounded loops):** fresh GUI emacs in tmux (the pass used for this
  research is the template), attach a bright-lights agent over
  `/ssh:localhost:…`, drive `C-c s`, wheel events (synthetic or real),
  assert host-side `pane_in_mode`/`scroll_position` after each step —
  exactly the E4–E8 probes; record under `docs/qa/`.
