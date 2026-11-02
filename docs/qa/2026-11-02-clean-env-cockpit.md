# Clean-environment cockpit — live QA and smoke guard

- Date: 2026-11-02
- Item: ga-ek9hy — live-verify the clean-env cockpit and add a clean-env
  smoke script (follow-up to ga-x40e / 80cf90d)
- Environment: Emacs 31.1 (pgtk) started as a fresh `emacs -nw -Q` inside
  a throwaway tmux session (`gce-cleanenv-qa`, 220x60), from this checkout
  (`lisp/` first on `EMACSLOADPATH`, sibling `beads.el/lisp` and vui
  1.4.0 next), and started with
  `env -i HOME=/home/roman PATH=… TERM=xterm-256color` so
  `XDG_RUNTIME_DIR` is absent.
- City: `/home/roman/emacs-city` (the local emacs-city city; this pass
  exercises the local clean-environment path, not TRAMP).

## Setup

The throwaway launcher used by tmux (kept outside the checkout):

```sh
#!/bin/sh
cd /home/roman/emacs-city || exit 1
exec env -i HOME=/home/roman \
  PATH=/home/roman/.guix-home/profile/bin:/usr/bin:/bin \
  TERM=xterm-256color \
  EMACSLOADPATH='/home/roman/workspace/gascity.el/lisp:/home/roman/workspace/beads.el/lisp:/home/roman/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0:…site-lisp package dirs…' \
  emacs -nw -Q --eval '(progn (setq load-prefer-newer t) (require (quote gascity)))'
```

```sh
tmux new-session -d -s gce-cleanenv-qa -x 220 -y 60 /tmp/gce-cleanenv-qa.sh
```

The `…site-lisp package dirs…` part is the Guix home site-lisp tree plus
the packages `transient`, `compat`, `cond-let` and `llama`; `-Q` does not
run site-start, so those explicitly stand in for the normal site-lisp
setup. `load-prefer-newer` guards against stale `.elc` in the checkout.

## What was exercised and observed

1. **The cockpit renders.** `M-x gascity-dashboard` opened
   `*gascity: emacs-city@/home/roman/emacs-city/*` with the normal
   section tree, not an abort or a backtrace. The top of the frame:

   ```
    emacs-city  ? live  ? 1s ago
   emacs-city  ~/emacs-city          ? degraded (agent_state_unknown)
    agents 4/8 ?   sessions 4   runs 0   ready 7   mail ?7

   Needs you  2
     ? mail     7 unread
     ? store    health: counting retained bead rows: hydrating ?

   Agents  4 running ? 4 stopped
     ? mayor                              pi             active  3s
     ? beads.el/gc.implementation-worker? pi             active  3s
     ? gascity.el/gc.implementation-work? pi             active  3s
     ? gascity.el/core.control-dispatcher                active  11m
   ```

   (`?` is tmux's substitute for a glyph the capture terminal could not
   draw; the state word `live` is the meaningful part.) The header says
   `live`, never `supervisor down`. The Agents, Work, Activity and Rigs
   sections all populated; Activity showed the city's recent events
   (`order.fired/completed`, `bead.updated`, `session.woke`, …).

2. **The live stream connected.** Evaluating

   ```elisp
   (gascity-live-status)
   ```

   in the cockpit returned:

   ```elisp
   (:state live :reason nil :retry-in nil :seq 365663 :host nil)
   ```

   No `could not auto-discover the supervisor API` message appeared.

3. **The environment really is clean.** Evaluating

   ```elisp
   (getenv "XDG_RUNTIME_DIR")
   ```

   returned `nil`, confirming the Emacs process itself, not just the gc
   child, is running without the variable. The read still worked because
   `gascity-reader--child-env-entries` adds `/run/user/1001` for the local
   gc child.

4. **Further local reads.** `j a` jumped to the Agents list and rendered
   the live rows (`mayor`, both `gc.implementation-worker-1` sessions,
   `core.control-dispatcher`). `i` on `mayor` opened
   `*gascity-agent: mayor@/home/roman/emacs-city/*` with the session
   handle (`session ec-grfr`), provider (`pi`), workdir, transcript tail
   and header `emacs-city  mayor  ● live`. Both are ordinary local gc
   reads under the same clean environment.

5. **No filesystem or supervisor error.** `C-h e` showed the `*Messages*`
   buffer with only the startup message and the `gascity-dashboard`
   discovery hint:

   ```
   For information about GNU Emacs and the GNU system, type C-h C-a.
   You can run the command `gascity-dashboard' with M-x ga-da
   ```

   No `files--ensure-directory`, no `/run/user` backtrace, no
   `supervisor down`, no `auto-discover` error.

## Smoke script

Added `scripts/clean-env-smoke.sh` (plus `scripts/clean-env-smoke.el`),
which performs the checks repeatably. It is not wired into CI: CI has no
live city. The wrapper starts the Emacs half under
`env -i HOME=… PATH=… TERM=…` (no `XDG_RUNTIME_DIR`), loads gascity from
this checkout, asserts the `/run/user/$(id -u)` fallback, runs a real
`gc status --json` through `gascity-reader-run` from the city root, and
requires exit 0 with a non-empty agents list.

From the city root:

```sh
$ /home/roman/workspace/gascity.el/scripts/clean-env-smoke.sh
>>> clean-env smoke: city=/home/roman/emacs-city (env -i, XDG_RUNTIME_DIR unset)
ok: unset XDG_RUNTIME_DIR falls back to /run/user/1001
ok: gc status --json exit 0, city=emacs-city, agents=8
PASS: clean environment (no XDG_RUNTIME_DIR) reads gc
```

With an explicit city from the repository root:

```sh
$ scripts/clean-env-smoke.sh /home/roman/emacs-city
>>> clean-env smoke: city=/home/roman/emacs-city (env -i, XDG_RUNTIME_DIR unset)
ok: unset XDG_RUNTIME_DIR falls back to /run/user/1001
ok: gc status --json exit 0, city=emacs-city, agents=8
PASS: clean environment (no XDG_RUNTIME_DIR) reads gc
```

The whole wrapper can also be started under `env -i`; this is the
strictest form and was green as well:

```sh
$ env -i HOME=/home/roman PATH=/home/roman/.guix-home/profile/bin:/usr/bin:/bin \
    TERM=xterm-256color scripts/clean-env-smoke.sh /home/roman/emacs-city
>>> clean-env smoke: city=/home/roman/emacs-city (env -i, XDG_RUNTIME_DIR unset)
ok: unset XDG_RUNTIME_DIR falls back to /run/user/1001
ok: gc status --json exit 0, city=emacs-city, agents=8
PASS: clean environment (no XDG_RUNTIME_DIR) reads gc
```

Skip path, run from the repository root with no city argument and no
`GC_CITY`:

```sh
$ env -u GC_CITY scripts/clean-env-smoke.sh
SKIP: no city.toml at or above /home/roman/workspace/gascity.el; pass a city root as the first argument
```

Exit status was 0 in all three cases.

## Not covered

- **Remote/TRAMP under a clean environment.** This pass is local only;
  remote/ssh runs deliberately leave the host environment alone (ga-x40e),
  and the remote matrix was not re-run here.
- **The `/run/user/<uid>`-missing skip branch** was reviewed but not
  executed, because the directory exists on this machine; the
  not-inside-a-city branch was executed above.
- **Sling preview / session peek** were not used as the extra read; the
  pass used the Agents list and the agent detail view, which exercise the
  same sync/async gc boundary. The sling preview path was covered by the
  earlier ga-51s4b acceptance pass.
- **A genuine supervisor outage** was not simulated; the header was
  observed in the healthy `live` state only.

## Result

Pass. The cockpit renders and stays live under `env -i`, the Agents /
Activity / Mail data and a second local read all populate, no runtime
directory backtrace appears, and `scripts/clean-env-smoke.sh` reproduces
the read-only half of the check locally.
