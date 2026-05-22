;;; gascity-command-status.el --- gc status command -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The `gascity-command-status' class for `gc status', plus the
;; generated `gascity-command-status!' convenience function.  This is
;; the P0 smoke command: `(gascity-command-status!)' round-trips
;; `gc status --json' into an alist.
;;
;; Richer status options (--fast, --watch, --interval) and the status
;; dashboard arrive in later phases (see docs/DESIGN.md).

;;; Code:

(require 'gascity-command)

(gascity-defcommand gascity-command-status (gascity-command-global-options)
  ()
  :documentation "Show the Gas City town status.
Reports the city, its rigs, and per-rig agents (polecats, witness,
refinery).")

(provide 'gascity-command-status)
;;; gascity-command-status.el ends here
