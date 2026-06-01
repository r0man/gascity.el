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
(require 'gascity-types)         ; gascity-command-rig-list! (rig-store lookup)
(require 'gascity-terminal)

;; Bead UI is delegated to beads.el (DESIGN.md §4.3).  Its entry points
;; live in modules we do not hard-require (so this package byte-compiles
;; without beads on the load path); reference them by name, soft-require
;; their providing module at call time, and guard with `fboundp'.
(declare-function beads-show "beads-command-show")
(declare-function beads-dashboard "beads-dashboard")

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
default tmux server.

The city-name step is a deliberate inference: gc does not expose the tmux
server socket in `--json' (the old `gt' did).  When gc grows a stable
socket field, read it here in preference to the inference (see gce-je4)."
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
AGENT is a plist with a `:work-dir' key.  When no directory was recorded
on the session bead, fall back to the live working directory of the
agent's tmux pane (resolved from `:session-name'/`:socket'), mirroring
gastown.  Signals a `user-error' when no directory can be resolved or the
resolved directory is missing on disk."
  (let* ((name (or (plist-get agent :name) "agent"))
         (recorded (plist-get agent :work-dir))
         (dir (if (and recorded (stringp recorded) (not (string-empty-p recorded)))
                  recorded
                (gascity-terminal-pane-cwd (plist-get agent :session-name)
                                           (plist-get agent :socket)))))
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

;;; Bead-store scoping (DESIGN.md §4.3, §9.1)
;;
;; beads.el resolves *which* store to act on from `default-directory'
;; (its entries walk up for a `.beads'/VC root; there is no store/prefix
;; argument on the high-level commands).  So gascity scopes a delegated
;; view by binding `default-directory' to the rig's repo path — the
;; directory holding its `.beads/', which gc reports as `path'.

(defun gascity-beads--rig-path (rig)
  "Return the absolute store directory for RIG, or nil.
RIG is a rig name (string) or a rig alist as returned by `gc rig
list'/`gc rig status'.  The store directory is the rig's repo `path' (the
directory that holds its `.beads/').  A name is resolved against
`gascity-command-rig-list!'; any failure degrades to nil."
  (let ((alist (cond ((and (consp rig) (not (stringp rig))) rig)
                     ((stringp rig)
                      (ignore-errors
                        (seq-find (lambda (r) (equal (alist-get 'name r) rig))
                                  (append (alist-get 'rigs (gascity-command-rig-list!)) nil)))))))
    (when-let* ((path (alist-get 'path alist))
                ((stringp path))
                ((not (string-empty-p path))))
      (file-name-as-directory (expand-file-name path)))))

(defun gascity-beads--id-prefix (id)
  "Return the store prefix of bead ID (text before the first `-'), or nil."
  (when (and (stringp id) (string-match "\\`\\([^-]+\\)-" id))
    (match-string 1 id)))

(defun gascity-beads--bead-path (id)
  "Return the store directory owning bead ID, or nil.
Gas City routes beads by id prefix (`gce-*' -> the gascity.el rig); this
maps ID's prefix to the owning rig's store via `gascity-command-rig-list!'.
Failures degrade to nil so callers fall back to the ambient directory."
  (when-let* ((prefix (gascity-beads--id-prefix id))
              (rig (ignore-errors
                     (seq-find (lambda (r) (equal (alist-get 'prefix r) prefix))
                               (append (alist-get 'rigs (gascity-command-rig-list!)) nil)))))
    (gascity-beads--rig-path rig)))

(defun gascity-bead-show (id &optional directory)
  "Open bead ID in beads.el, scoped to its rig's bead store.
gascity does not render beads itself; it hands ID to beads.el's detail
view (DESIGN.md §4.3).  beads.el resolves the store from
`default-directory', so bind it to DIRECTORY when supplied, else to the
store of the rig that owns ID's prefix; fall back to the ambient
directory when neither resolves (a single-rig checkout already sits in
the right tree).  Resolves DESIGN §9.1 by directory binding."
  (cond
   ((or (null id) (and (stringp id) (string-empty-p id)))
    (user-error "No bead to show"))
   (t
    (unless (fboundp 'beads-show)
      (require 'beads-command-show nil t))
    (if (fboundp 'beads-show)
        (let ((default-directory
               (or (and directory (file-name-as-directory
                                   (expand-file-name directory)))
                   (gascity-beads--bead-path id)
                   default-directory)))
          (beads-show id))
      (user-error "beads.el is not available to show %s" id)))))

;;;###autoload
(defun gascity-bead-visit ()
  "Open the bead at point in beads.el, scoped to its store."
  (interactive)
  (gascity-bead-show (or (gascity-bead-at-point)
                         (user-error "No bead at point"))))

;;; Rig beads — delegate a rig's whole store to beads.el (DESIGN.md §4.3)

;;;###autoload
(defun gascity-rig-beads (rig)
  "Open beads.el's board for RIG, scoped to that rig's bead store.
RIG is a rig name (string) or a rig alist.  Delegates to beads.el's
project board (`beads-dashboard') with `default-directory' bound to
RIG's store directory, so beads.el renders that rig's beads (DESIGN.md
§4.3).  Called interactively, prompts for the rig, defaulting to the
contextual one."
  (interactive
   (list (completing-read
          "Beads for rig: "
          (condition-case nil
              (delq nil (mapcar (lambda (r) (alist-get 'name r))
                                (append (alist-get 'rigs (gascity-command-rig-list!)) nil)))
            (gascity-error nil))
          nil nil nil nil (gascity-context-rig-name))))
  (let ((name (if (stringp rig) rig (alist-get 'name rig)))
        (dir (gascity-beads--rig-path rig)))
    (unless dir
      (user-error "Could not resolve the bead store for rig %s" (or name "?")))
    (unless (fboundp 'beads-dashboard)
      (require 'beads-dashboard nil t))
    (if (fboundp 'beads-dashboard)
        (let ((default-directory dir))
          (beads-dashboard))
      (user-error "beads.el is not available to show beads for %s"
                  (or name "?")))))

;;;###autoload
(defun gascity-rig-beads-at-point ()
  "Open beads.el's board for the rig at point, scoped to its store."
  (interactive)
  (gascity-rig-beads (or (gascity-rig-at-point)
                         (user-error "No rig at point"))))

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
