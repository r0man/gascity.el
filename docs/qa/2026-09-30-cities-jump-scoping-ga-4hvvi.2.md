# Cities list: `j`/`?` jumps scope to the city at point (ga-4hvvi.2)

Date: 2026-09-30 · branch `main` · bead `ga-4hvvi.2` (dogfood
2026-09-30, bright-lights) · Emacs 31.1 · gc 1.4.x.

## Defect

`*gascity-cities*` pins `default-directory` to the local home, where no
`city.toml` walks up (`gascity-context-city-root` → nil). Its inherited
`j` jump prefix (and the `?` dispatch) ran the city-scoped views with
that contextless directory, so `gc convoy list` / `order list` / `mail
inbox` ran with no `--city` and exited 1; the views cached the failure
and their live indicator spun `connecting → reconnecting` forever.

## Fix

`lisp/gascity-dashboard.el`

- New buffer-local `gascity-jump-city-function`: when non-nil (the
  Cities list binds it, mirroring `gascity-live-city-function`), every
  city-scoped jump runs with `default-directory` bound to the city on
  the row at point; a row with no city (host/error line) echoes
  `No city selected — RET to open one`.
- `gascity-jump--scoped` / `gascity-jump--scoped-call` implement that,
  and `gascity-jump-cockpit`, `-agents`, `-runs`, `-events`, `-health`,
  `-mail`, `-costs`, `-rig`, `-beads` route through them.
- `-orders`, `-convoys`, `-dolt` become named scoped wrappers bound in
  `gascity-jump-map` and the `?` dispatch (previously the raw view
  commands). `-cities` stays unscoped: it lists every city.

`lisp/gascity-cities.el` sets the new buffer-local in
`gascity-cities-mode`, beside `gascity-live-city-function`.

## Tests

`lisp/test/gascity-health-test.el`

- `gascity-test-cities-jumps-target-city-at-point`: every city-scoped
  jump binds the target view's `default-directory` to the row's city.
- `gascity-test-cities-jumps-no-city-at-point`: a no-city row signals
  `user-error`; `j c` stays unscoped.

## Verification

- `scripts/gate.sh`: `eldev compile --warnings-as-errors` clean,
  `eldev test` 750/750.
- Scripted TRAMP acceptance against the real
  `/ssh:localhost:/home/roman/bright-lights/` city (temporary ERT
  driver, since a live Cities read starts async gc processes): the
  remote row appeared in the list, `j v` opened its Convoys view with
  `default-directory` equal to the remote city directory, and a jump
  with no city at point raised `user-error`. All assertions passed; the
  driver was removed after the pass.

Not reproduced interactively in tmux-Emacs: the behavior is pure
`default-directory` binding and is exercised identically to the
existing `gascity-cities-visit` remote test and the scripted TRAMP pass
above.
