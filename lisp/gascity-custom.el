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
absolute path is used as-is."
  :type 'string
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
