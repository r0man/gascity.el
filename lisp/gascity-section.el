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
(require 'vui)
(require 'wid-edit)
(require 'gascity-custom)
(require 'gascity-context)
(require 'gascity-terminal)

(declare-function beads-show "beads")

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

;;; In-place refresh

(defun gascity-section-refresh-instance (buffer)
  "Bump the `:refresh-tick' state of the vui component mounted in BUFFER.
gascity's vui views (status, rig dashboard, session/polecat detail) all
key their `vui-use-async' loads on a `refresh-tick' state field, so
incrementing it re-fetches every section while preserving component
state (collapse flags, point).  Returns non-nil when a live instance was
refreshed in place; nil when BUFFER has no mounted instance (the caller
then does a cold mount)."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (when (and (boundp 'vui--root-instance) vui--root-instance)
           (let* ((instance vui--root-instance)
                  (state (vui-instance-state instance))
                  (tick (or (plist-get state :refresh-tick) 0)))
             (setf (vui-instance-state instance)
                   (plist-put state :refresh-tick (1+ tick)))
             (vui-flush-sync)
             t)))))

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

(defvar-local gascity-section--agent nil
  "The subject agent plist of a single-agent detail buffer, or nil.
The session/polecat detail view renders one agent and sets this so the
agent actions act on the buffer's subject regardless of point.  List and
dashboard buffers leave it nil and resolve the agent per row instead.")

(defun gascity-agent-at-point ()
  "Return the agent plist at point, or nil.
Resolves, in order, from a `gascity-agent' text property (vui dashboard
rows), a plist entry id in a `tabulated-list-mode' buffer (the session
list), or the buffer-local `gascity-section--agent' subject (a
single-agent detail buffer)."
  (or (get-text-property (point) 'gascity-agent)
      (and (derived-mode-p 'tabulated-list-mode)
           (let ((id (tabulated-list-get-id)))
             (and (consp id) (keywordp (car id))
                  (plist-member id :session-name)
                  id)))
      gascity-section--agent))

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

;;; Bead at point — delegate display to beads.el (DESIGN.md §4.3)

(defun gascity-bead-at-point ()
  "Return the bead id at point, or nil.
Resolves from a `gascity-bead' text property (vui detail/dashboard rows,
stamped with the bead id string) or, in a `tabulated-list-mode' buffer
whose entry id is a bead id string, from `tabulated-list-get-id'."
  (or (get-text-property (point) 'gascity-bead)
      (and (derived-mode-p 'tabulated-list-mode)
           (let ((id (tabulated-list-get-id)))
             (and (stringp id) (not (string-empty-p id)) id)))))

(defun gascity-section-beads (data)
  "Return the bead list from a `gc bd …' JSON payload DATA.
gc emits either a bare array of beads or an object wrapping them under
`issues'; tolerate both and always return a list."
  (let ((beads (if (vectorp data) data (alist-get 'issues data))))
    (append beads nil)))

(defun gascity-bead-show (id)
  "Open bead ID in beads.el, or signal a `user-error'.
gascity does not render beads itself; it hands the id to beads.el's
existing detail view (DESIGN.md §4.3)."
  (cond ((or (null id) (and (stringp id) (string-empty-p id)))
         (user-error "No bead to show"))
        ((fboundp 'beads-show) (beads-show id))
        (t (user-error "beads.el is not available to show %s" id))))

;;;###autoload
(defun gascity-bead-visit ()
  "Open the bead at point in beads.el."
  (interactive)
  (gascity-bead-show (or (gascity-bead-at-point)
                         (user-error "No bead at point"))))

;;; Rig at point

(defun gascity-rig-at-point ()
  "Return the rig name at point, or nil.
Resolves, in order, from a `gascity-rig' text property (vui buffers), the
`name' of the rig alist that is a `gascity-rig-list-mode' entry id, or
the `:rig' of the agent at point (so the rig dashboard opens from an
agent row in the status dashboard or session list)."
  (or (get-text-property (point) 'gascity-rig)
      (and (derived-mode-p 'tabulated-list-mode)
           (let ((id (tabulated-list-get-id)))
             (and (consp id) (alist-get 'name id))))
      (let ((agent (gascity-agent-at-point)))
        (and agent (plist-get agent :rig)))))

(provide 'gascity-section)
;;; gascity-section.el ends here
