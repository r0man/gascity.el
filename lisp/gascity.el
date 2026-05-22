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
;; It is built on beads.el's command infrastructure (`beads-meta', for
;; auto-generated transient menus from EIEIO slot metadata) and vui
;; rendering layer, and delegates all bead UI to beads.el.
;;
;; This is the P0 foundation: the gc -> JSON bridge (`gascity-reader'),
;; the EIEIO command layer (`gascity-command'), city/rig context
;; resolution (`gascity-context'), and a smoke command
;; (`gascity-command-status').  Command menus, tabulated lists, and vui
;; dashboards arrive in later phases — see docs/DESIGN.md.

;;; Code:

(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-reader)
(require 'gascity-command)
(require 'gascity-context)
(require 'gascity-command-status)

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

(provide 'gascity)
;;; gascity.el ends here
