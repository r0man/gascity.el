# Bookmarks — live check (2026-09-26)

Branch `v3-bookmarks`. Read-only: nothing was slung, mutated or written on
either city. A throwaway `bookmark-default-file` in the session scratch
directory was used, never `~/.emacs.d/bookmarks`.

## Method

Two batch Emacs sessions on the branch:

1. **Set.** Open each view, let it settle, `bookmark-set` it under its
   default name, `bookmark-save`.
2. **Jump.** A fresh Emacs with nothing memoized loads the file,
   `bookmark-jump`s each bookmark, then runs `bookmark-bmenu-list`.

## Result — PASS

| Bookmark (default name) | record | jump returns | settled view |
|---|---|---|---|
| `gascity: bright-lights` | 0.1 ms | 1 ms | cockpit, `/home/roman/bright-lights/` |
| `gascity: bright-lights@localhost` | 1.4 ms | 15 ms | cockpit, `/ssh:localhost:/home/roman/bright-lights/` |
| `gascity: burningswell@burningswell.com` | 2.5 ms | 4 ms | cockpit, `/ssh:gascity@burningswell.com:/home/gascity/burningswell/` |
| `gascity-run: bs-8jif@burningswell.com` | 0.3 ms | 3 ms | run detail `⬣ bs-8jif build-basic burningswell-cl` |

- **Records:** each one names the view, the city directory (`filename` and
  `location`), the view's arguments (`:run "bs-8jif" :rig
  "burningswell-cl"`) and filters, with `handler . gascity-bookmark-jump`.
- **Jumps:** every jump opened at once with `…` and filled in. No jump walked
  over TRAMP: the recorded city root is memoized before the view opens.
- **Listing:** `bookmark-bmenu-list` lists all four under the handler type
  `Gascity`, with their city directory as the location.
- **Unreachable host:** a hand-made record for
  `/ssh:nobody@unreachable.invalid:/srv/city/` jumped in 6 ms, with no error.
  The cockpit showed `…`, and after the first read failed the header read
  `○ offline @unreachable.invalid`. The store's host state was `offline`,
  with reason "ssh: Could not resolve hostname unreachable.invalid".
