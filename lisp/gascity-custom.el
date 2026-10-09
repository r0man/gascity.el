;;; gascity-custom.el --- Customization for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; User-customizable variables and faces for gascity.el.  Configure via
;; M-x customize-group RET gascity RET or by setting the variables in
;; your Emacs configuration.

;;; Code:

(require 'beads-custom)

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
against `tramp-remote-path' — NOT the variable `exec-path' — then by probing the
profile directories in `beads-remote-search-path', which covers
Guix hosts with zero setup.  When gc lives elsewhere, either extend
TRAMP's search path:

  (add-to-list \\='tramp-remote-path \\='tramp-own-remote-path)

add its directory to `beads-remote-search-path', or set this
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

;; Remote executable resolution is beads.el's (`beads-remote'): one
;; search path and one miss TTL for bd, gc and tmux alike.
(define-obsolete-variable-alias 'gascity-remote-search-path
  'beads-remote-search-path "0.1.0")
(define-obsolete-variable-alias 'gascity-remote-miss-ttl
  'beads-remote-miss-ttl "0.1.0")

(defcustom gascity-remote-sync-timeout 30
  "Seconds before a synchronous remote call is abandoned, 0 to disable.
Every synchronous remote primitive gascity runs — the `process-file'
read of `gascity-reader-run' (including the executable resolution
ahead of it) and the tmux probes (`gascity-terminal--tmux',
`gascity-terminal-tmux-session-exists-p',
`gascity-terminal-pane-cwd') — waits inside TRAMP's
`accept-process-output' loop, where timers run.  A timeout therefore
can interrupt them when the channel is wedged: a half-dead ssh
connection (killed laptop, dropped VPN) would otherwise block the UI
for minutes on TCP retransmit timers, and a timer-driven probe would
freeze Emacs once per tick.  When the bound fires, the caller is
signalled with `gascity-remote-sync-timeout' after the connection has
been drained (`gascity-remote-drain-connection'), so a retried command
starts on a clean channel.

Local calls are deliberately never bound: a local `process-file' waits
in blocking C code that runs no timers, so a timeout could not fire —
and a local spawn cannot stall on a network.  Set to 0 (or nil) to
restore unbounded waits."
  :type '(choice (natnum :tag "Seconds")
                 (const :tag "Unbounded" nil))
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

;; The tmux terminal moved to beads.el (WI-14); gascity's options are now
;; aliases of the beads ones, so existing configurations keep working and
;; there is one source of truth (WI-15).

(define-obsolete-variable-alias 'gascity-terminal-backend
  'beads-terminal-tmux-backend "0.2.0")

(define-obsolete-variable-alias 'gascity-terminal-remote-term
  'beads-terminal-tmux-remote-term "0.2.0")

(define-obsolete-variable-alias 'gascity-terminal-unshadow-minor-modes
  'beads-terminal-tmux-unshadow-minor-modes "0.2.0")

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

(define-obsolete-variable-alias 'gascity-terminal-mode-line-status
  'beads-terminal-tmux-mode-line-status "0.2.0")

(define-obsolete-variable-alias 'gascity-terminal-ensure-mouse
  'beads-terminal-tmux-ensure-mouse "0.2.0")

(define-obsolete-variable-alias 'gascity-terminal-preload-idle
  'beads-terminal-tmux-preload-idle "0.2.0")

(define-obsolete-variable-alias 'gascity-terminal-status-interval
  'beads-terminal-tmux-status-interval "0.2.0")

;;; Events and mail (dashboard-v3 §7.8, §7.9)

(defcustom gascity-event-levels
  '(("\\.crashed\\'" . attention)
    ("\\.cold_start_timeout\\'" . attention)
    ("\\.failed\\'" . attention)
    ("quarantine" . attention)
    ("\\.dead_assignee_reopened\\'" . watch)
    ("\\.rate_limited\\'" . watch)
    ("escalat" . watch))
  "Signal level of a gc event type: (REGEXP . LEVEL), first match wins.
LEVEL is `attention' (■) or `watch' (▲); a type no entry matches is a
plain event.  Signal events are never folded into churn, in the
cockpit's Activity section or the Events view (dashboard-v3 §7.8)."
  :type '(alist :key-type regexp
                :value-type (choice (const attention) (const watch)))
  :group 'gascity)

(defcustom gascity-events-window "2h"
  "Default time window of the Events view (`gc events --since').
A duration such as `1h', `2h', `24h' or `7d'; days are passed to gc
as hours (gc's durations have no `d' unit)."
  :type 'string
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

(defface gascity-warning
  '((t :inherit warning))
  "Face for a watch-level (▲) signal: worth a look, not yet failing."
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
