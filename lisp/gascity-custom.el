;;; gascity-custom.el --- Customization for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; User-customizable variables and faces for gascity.el.  Configure via
;; M-x customize-group RET gascity RET or by setting the variables in
;; your Emacs configuration.

;;; Code:

;;; Customization group

(defgroup gascity nil
  "Magit-style Emacs porcelain for Gas City (the `gc' CLI)."
  :group 'tools
  :prefix "gascity-"
  :link '(url-link "https://github.com/r0man/gascity.el"))

;;; Executable

(defcustom gascity-executable "gc"
  "Name of, or path to, the Gas City `gc' executable.
A bare command name is resolved against the variable `exec-path'; an
absolute path is used as-is.

For a remote city (a TRAMP `default-directory'), a bare name is
resolved on the host by `gascity-remote-find-executable': first
against `tramp-remote-path' — NOT `exec-path' — then by probing the
profile directories in `gascity-remote-search-path', which covers
Guix hosts with zero setup.  When gc lives elsewhere, either extend
TRAMP's search path:

  (add-to-list \\='tramp-remote-path \\='tramp-own-remote-path)

add its directory to `gascity-remote-search-path', or set this
variable connection-locally to an absolute remote path — every
invocation site reads it under `with-connection-local-variables':

  (connection-local-set-profile-variables
   \\='gascity-remote-gc
   \\='((gascity-executable . \"/home/user/.guix-home/profile/bin/gc\")))
  (connection-local-set-profiles
   \\='(:machine \"example.com\") \\='gascity-remote-gc)"
  :type 'string
  :group 'gascity)

;;; Remote cities

(defcustom gascity-remote-search-path
  '("~/.guix-home/profile/bin"
    "~/.guix-profile/bin"
    "/run/current-system/profile/bin")
  "Remote directories probed for gc and tmux as a resolution fallback.
On a remote city, a bare program name (`gascity-executable', the tmux
probes) that `executable-find' cannot resolve on the host — TRAMP
searches `tramp-remote-path', which omits non-default profile
directories — is looked up in these directories instead, first hit
wins.  Entries are host-side paths; `~' expands to the remote home.
The defaults cover Guix hosts (guix home, user, and system profiles)
with zero configuration.

These directories are also prepended to the PATH exported to every
remote gc invocation (`gascity-remote-path-assignment'), so the
subprocesses gc spawns — git for pack imports, dolt — resolve on the
host as well; resolving gc alone would not survive its first fork.

Resolutions and the exported PATH fragment are cached per connection;
clear with `gascity-context-clear-cache' after installing a program
or changing this path."
  :type '(repeat string)
  :group 'gascity)

;;; Debug logging

(defcustom gascity-enable-debug nil
  "When non-nil, log `gc' invocations to the `*gascity-log*' buffer."
  :type 'boolean
  :group 'gascity)

(defcustom gascity-debug-level 'info
  "Verbosity of gascity debug logging.
Only consulted when `gascity-enable-debug' is non-nil.

- `error': log errors only.
- `info': log commands and important events (default).
- `verbose': log everything, including command output."
  :type '(choice (const :tag "Errors only" error)
                 (const :tag "Commands and events" info)
                 (const :tag "Everything, including output" verbose))
  :group 'gascity)

;;; Terminal backend

(defcustom gascity-terminal-backend nil
  "Terminal backend for attaching to an agent's tmux session.
gascity delegates the actual spawn to beads.el's terminal module
\(`beads-terminal-spawn'); this choice selects which backend class it
uses.  When nil, beads auto-detects the best available backend in the
order vterm > eat > term.  (Future interactive commands such as peek or
shell will share this setting.)

- nil:   auto-detect (vterm, then eat, then the built-in term).
- vterm: requires the `vterm' package.
- eat:   requires the `eat' package.
- term:  the built-in `term-mode' (always available)."
  :type '(choice (const :tag "Auto-detect (vterm > eat > term)" nil)
                 (const :tag "Vterm (requires vterm package)" vterm)
                 (const :tag "Eat (requires eat package)" eat)
                 (const :tag "Term mode (built-in)" term))
  :group 'gascity)

(defcustom gascity-tmux-socket nil
  "Name of the tmux server socket the city's agents run on (tmux -L).
Gas City runs one tmux server per city, named after the city, so when
this is nil the socket is auto-detected as the city name.  Set a string
to override (passed as `tmux -L NAME'); the literal \"default\" means
the default tmux server (no -L flag)."
  :type '(choice (const :tag "Auto-detect (city name)" nil)
                 (string :tag "Explicit socket name"))
  :group 'gascity)

;;; Terminal mode-line status

(defcustom gascity-terminal-mode-line-status t
  "When non-nil, mirror an attached agent's tmux status bar in the mode line.
On attaching to an agent's tmux session, gascity turns that session's own
tmux status bar off (`status off', scoped to the session) and renders the
same information — the friendly session name from `status-left' and the
window list with the current window emphasised — as a buffer-local
segment of the Emacs mode line.  The terminal then shows one status line
instead of two.  The tmux change is reverted when the terminal buffer is
killed, so an external `tmux attach' still sees its own status bar.

Set to nil to leave tmux's status bar untouched and add no mode-line
segment."
  :type 'boolean
  :group 'gascity)

(defcustom gascity-terminal-status-interval 5
  "Seconds between refreshes of the tmux status mode-line segment.
gascity polls the attached session with `tmux list-windows' /
`display-message' on this interval and updates the mode line, mirroring
tmux's own `status-interval'.  Only consulted when
`gascity-terminal-mode-line-status' is non-nil; values at or below zero
fall back to 5."
  :type 'number
  :group 'gascity)

(defcustom gascity-status-auto-refresh t
  "When non-nil, the Gas City status dashboard refreshes itself on a timer.
The `*gascity-status*' dashboard re-reads `gc' every
`gascity-status-auto-refresh-interval' seconds and re-renders in place,
but only while its buffer is displayed in a visible window.  A buried or
invisible dashboard does nothing: no timer work and no `gc' fetch.  The
refresh preserves collapsed rigs and point, exactly like the manual `g'.

Set to nil to refresh only manually with `g'; the command
`gascity-status-toggle-auto-refresh' (G on the dashboard) flips it live."
  :type 'boolean
  :group 'gascity)

(defcustom gascity-status-auto-refresh-interval 5
  "Seconds between automatic refreshes of the Gas City status dashboard.
Only consulted when `gascity-status-auto-refresh' is non-nil; a value at
or below zero disables the timer (refresh manually with `g').

For a remote city each refresh is an ssh round trip.  TRAMP reuses the
connection, so the default is usually fine, and a tick is skipped while
a previous load is still in flight — but on a slow link consider
raising this (say 15–30) so the dashboard is not perpetually fetching."
  :type 'number
  :group 'gascity)

;;; Faces

(defgroup gascity-faces nil
  "Faces used by gascity buffers."
  :group 'gascity
  :prefix "gascity-")

(defface gascity-header
  '((t :inherit bold))
  "Face for section headers."
  :group 'gascity-faces)

(defface gascity-city
  '((t :inherit font-lock-keyword-face))
  "Face for the city name."
  :group 'gascity-faces)

(defface gascity-rig
  '((t :inherit font-lock-function-name-face))
  "Face for a rig name."
  :group 'gascity-faces)

(defface gascity-running
  '((t :inherit success))
  "Face for a running agent or service."
  :group 'gascity-faces)

(defface gascity-stopped
  '((t :inherit shadow))
  "Face for a stopped agent or service."
  :group 'gascity-faces)

(defface gascity-suspended
  '((t :inherit warning))
  "Face for a suspended rig or agent."
  :group 'gascity-faces)

(defface gascity-failed
  '((t :inherit error))
  "Face for a failed or errored state."
  :group 'gascity-faces)

(defface gascity-dim
  '((t :inherit shadow))
  "Face for secondary, de-emphasized text."
  :group 'gascity-faces)

(provide 'gascity-custom)
;;; gascity-custom.el ends here
