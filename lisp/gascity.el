;;; gascity.el --- Magit-style Emacs porcelain for Gas City -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Gas City Contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (transient "0.10.1") (vui "1.0.0") (beads "0.1.0") (sesman "0.3.2"))
;; Keywords: tools, processes
;; URL: https://github.com/r0man/gascity.el

;;; Commentary:

;; gascity.el is a Magit-style, keyboard-first Emacs porcelain for the
;; Gas City (`gc') CLI.  Every view is a function of `gc ... --json'
;; output: gascity renders gc's state and dispatches its commands, the
;; way Magit fronts git.
;;
;; The porcelain — the status dashboard, the lists, and the detail views
;; — is hand-built in the deliberate magit/forge style: sectioned,
;; keyboard-driven buffers (vui for the heterogeneous dashboard/detail
;; views, `tabulated-list-mode' for homogeneous lists).  The EIEIO
;; command layer (`gascity-command' on beads.el's `beads-meta') is used
;; only as the execution + parse layer — it runs `gc' commands and
;; decodes their `--json' output — not as an auto-generated UI.
;; Transient menus, where present (the `gascity' dispatcher), are a
;; command-dispatch backend, not the primary interface.  Bead UI is
;; delegated to beads.el.
;;
;; This entry point loads the porcelain: the gc -> JSON bridge
;; (`gascity-reader', sync and async), the command layer
;; (`gascity-command' + `gascity-types'), context resolution
;; (`gascity-context'), the status dashboard (`gascity-status'), the
;; tabulated lists (`gascity-tabulated'), the agent actions — Dired and
;; tmux attach via beads.el's terminal module (`gascity-terminal') — the
;; mutating-command dispatch (`gascity-action'), and the vui detail views:
;; the rig dashboard (`gascity-rig') and the session/polecat detail
;; (`gascity-session').  Bead UI is delegated to beads.el, scoped to a
;; rig's store (`gascity-rig-beads', and store-scoped bead detail in
;; `gascity-section'); remaining polish arrives in later phases — see
;; docs/DESIGN.md.

;;; Code:

(require 'transient)
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-reader)
(require 'gascity-command)
(require 'gascity-context)
(require 'gascity-types)
(require 'gascity-command-status)
(require 'gascity-terminal)
(require 'gascity-section)
(require 'gascity-tabulated)
(require 'gascity-status)
(require 'gascity-action)
(require 'gascity-rig)
(require 'gascity-session)

;;; Debug logging

(defun gascity--log (level format-string &rest args)
  "Append a log line to the `*gascity-log*' buffer when debugging is on.
LEVEL is `error', `info', or `verbose'.  FORMAT-STRING and ARGS are
passed to `format'.  Honours `gascity-enable-debug' and
`gascity-debug-level'."
  (when (and gascity-enable-debug
             (pcase gascity-debug-level
               ('error (eq level 'error))
               ('info (memq level '(error info)))
               ('verbose t)
               (_ nil)))
    (let ((line (format "%s [%-7s] %s\n"
                        (format-time-string "%F %T")
                        (upcase (symbol-name level))
                        (apply #'format format-string args))))
      (with-current-buffer (get-buffer-create "*gascity-log*")
        (goto-char (point-max))
        (let ((inhibit-read-only t))
          (insert line))))))

;;; Dispatcher

;;;###autoload (autoload 'gascity "gascity" nil t)
(transient-define-prefix gascity ()
  "Dispatch the Gas City porcelain.
A hand-written command-dispatch menu — the views in the left columns are
the deliberately-designed porcelain (not auto-generated from this
prefix), and the Dispatch column routes the mutating actions, prompting
for their arguments.  The same actions are also available at point in
the lists and the status dashboard."
  ["Gas City"
   ["Overview"
    ("s" "Status dashboard" gascity-status)
    ("d" "Rig dashboard…" gascity-rig-dashboard)
    ("b" "Beads (rig)…" gascity-rig-beads)]
   ["Lists"
    ("r" "Rigs" gascity-rig-list)
    ("a" "Sessions" gascity-session-list)
    ("c" "Convoys" gascity-convoy-list)
    ("m" "Mail inbox" gascity-mail-inbox)
    ("o" "Orders" gascity-order-list)
    ("D" "Dolt databases" gascity-dolt-list)]
   ["Dispatch"
    ("R" "Rig control…" gascity-rig-dispatch)
    ("A" "Session control…" gascity-session-dispatch)
    ("S" "Sling…" gascity-sling)
    ("O" "Run order…" gascity-order-run)
    ("L" "City lifecycle…" gascity-lifecycle-dispatch)]])

(provide 'gascity)
;;; gascity.el ends here
