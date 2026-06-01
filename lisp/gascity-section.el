;;; gascity-section.el --- Shared vui section mode + agent actions -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Foundations shared by gascity's rich (vui) views.
;;
;; `gascity-section-mode' derives from `beads-section-mode' (which
;; derives from `vui-mode'), inheriting the vui reconciler, widget
;; navigation (TAB/S-TAB), and `q'.  gascity's detail/dashboard modes
;; derive from it.
;;
;; It also provides the state->face helpers and the two agent actions
;; the read-only porcelain exposes from both the dashboard and the
;; session list: open the agent's worktree in Dired, and attach to its
;; tmux session.  Both act on the "agent at point", which is resolved
;; from a `gascity-agent' text property (vui buffers) or the
;; tabulated-list entry id (list buffers).  An agent is a plist:
;;
;;   (:name NAME :work-dir DIR :session-name TMUX :running BOOL [:socket S])

;;; Code:

(require 'beads-section)
(require 'wid-edit)
(require 'gascity-custom)
(require 'gascity-context)
(require 'gascity-terminal)

;;; Base mode

(defun gascity-section-activate ()
  "Activate the widget at point in a gascity section buffer.
The base \"drill in\" action: derived modes inherit this rather than
`beads-section-mode's issue visitor, and override it where they have a
richer notion of activation (the dashboard, for instance)."
  (interactive)
  (if (widget-at (point))
      (widget-button-press (point))
    (user-error "Nothing to drill into here")))

(defvar-keymap gascity-section-mode-map
  :doc "Keymap for `gascity-section-mode'."
  :parent beads-section-mode-map
  ;; Shadow `beads-section-mode's RET (its beads issue visitor) with a
  ;; gascity-appropriate default, honouring \"RET drills in everywhere\".
  "RET" #'gascity-section-activate)

(define-derived-mode gascity-section-mode beads-section-mode "GasCity"
  "Base major mode for gascity vui section buffers.
Derives from `beads-section-mode' for the vui reconciler, widget
navigation, and `q' to bury.  Concrete views (the status dashboard,
detail views) derive from this and add their own keys."
  :interactive nil
  :group 'gascity)

;;; tmux socket resolution

(defun gascity-resolve-tmux-socket (&optional city-name)
  "Return the tmux -L socket name for the city's agents.
Gas City runs one tmux server per city, named after the city.  Honours
`gascity-tmux-socket' when set; otherwise uses CITY-NAME (e.g. from a
`gc status' payload already in hand) or, failing that, the city name
resolved from context.  May return nil (no city found), meaning the
default tmux server."
  (or gascity-tmux-socket
      city-name
      (gascity-context-city-name)))

;;; State -> face

(defun gascity-section-state-face (running &optional suspended)
  "Return the gascity face for an agent/rig given RUNNING and SUSPENDED."
  (cond (suspended 'gascity-suspended)
        (running 'gascity-running)
        (t 'gascity-stopped)))

;;; Agent at point

(defun gascity-agent-at-point ()
  "Return the agent plist at point, or nil.
Resolves from a `gascity-agent' text property (vui section buffers) or,
in a `tabulated-list-mode' buffer, from a plist entry id."
  (or (get-text-property (point) 'gascity-agent)
      (and (derived-mode-p 'tabulated-list-mode)
           (let ((id (tabulated-list-get-id)))
             (and (consp id) (keywordp (car id))
                  (plist-member id :session-name)
                  id)))))

;;; Agent actions

(defun gascity-agent-dired (agent)
  "Open Dired on AGENT's working directory.
AGENT is a plist with a `:work-dir' key.  Signals a `user-error' when
the directory is unknown or missing on disk."
  (let ((dir (plist-get agent :work-dir))
        (name (or (plist-get agent :name) "agent")))
    (unless (and dir (stringp dir) (not (string-empty-p dir)))
      (user-error "No working directory recorded for %s" name))
    (unless (file-directory-p dir)
      (user-error "Directory not found for %s: %s" name dir))
    (dired dir)))

(defun gascity-agent-attach-tmux (agent)
  "Attach to AGENT's tmux session in a terminal buffer.
AGENT is a plist with `:session-name' (and optionally `:socket' and
`:work-dir').  Delegates to `gascity-terminal-attach-tmux'."
  (gascity-terminal-attach-tmux (plist-get agent :session-name)
                                (plist-get agent :socket)
                                (plist-get agent :work-dir)))

;;;###autoload
(defun gascity-dired-at-point ()
  "Open Dired on the working directory of the agent at point."
  (interactive)
  (let ((agent (gascity-agent-at-point)))
    (unless agent (user-error "No agent at point"))
    (gascity-agent-dired agent)))

;;;###autoload
(defun gascity-tmux-at-point ()
  "Attach to the tmux session of the agent at point."
  (interactive)
  (let ((agent (gascity-agent-at-point)))
    (unless agent (user-error "No agent at point"))
    (gascity-agent-attach-tmux agent)))

(provide 'gascity-section)
;;; gascity-section.el ends here
