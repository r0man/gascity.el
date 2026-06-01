;;; gascity-status.el --- vui status dashboard -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The town status dashboard: an interactive, hand-built (magit/forge
;; style) overview of the city, its rigs, and their agents — the same
;; information as `gc status', rendered with vui.
;;
;; Two `gc' reads run asynchronously and are joined client-side: `gc
;; status --json' supplies the city -> rig -> agent tree (its agents
;; list is flat, so the tree is assembled by splitting each agent's
;; qualified name on \"/\"), and `gc session list --json' supplies each
;; agent's worktree (`work_dir', for Dired) and tmux target
;; (`session_name', for attach).  Controller-down does not blank the
;; view — sessions are trusted independently.
;;
;; Rig sections are collapsible (component-local `:state', preserved
;; across in-place refreshes).  `g' refreshes, `q' buries, `d' opens an
;; agent's worktree in Dired, `t' attaches to its tmux session, RET
;; toggles/activates the thing at point.

;;; Code:

(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-reader)
(require 'gascity-command)
(require 'gascity-command-status)
(require 'gascity-section)

;;; Buffer

(defconst gascity-status-buffer-name "*gascity-status*"
  "Name of the gascity status dashboard buffer.")

;;; Data shaping (pure)

(defun gascity-status--city-agent-p (agent)
  "Return non-nil when AGENT (an alist) is a city-scope agent."
  (let ((scope (alist-get 'scope agent))
        (qname (alist-get 'qualified_name agent)))
    (or (equal scope "city")
        (and (stringp qname) (not (string-search "/" qname))))))

(defun gascity-status--rig-agents (rig-name agents)
  "Return the AGENTS whose qualified name is scoped to RIG-NAME."
  (let ((prefix (concat rig-name "/")))
    (seq-filter (lambda (a)
                  (let ((q (alist-get 'qualified_name a)))
                    (and (stringp q) (string-prefix-p prefix q))))
                agents)))

(defun gascity-status--session-map (sessions)
  "Return a hash table mapping a session's qualified agent name to its alist.
SESSIONS is the vector (or list) from `gc session list'.  Keyed on
`agent_name' — always the qualified name — with `name' as a fallback.
`name' degrades to the raw tmux session id for non-active (e.g.
draining) sessions, so it is not a reliable join key against a status
agent's `qualified_name'."
  (let ((map (make-hash-table :test 'equal)))
    (seq-do (lambda (s)
              (let ((key (or (alist-get 'agent_name s) (alist-get 'name s))))
                (when key (puthash key s map))))
            sessions)
    map))

(defun gascity-status--agent-plist (agent rig-name session-map socket)
  "Build the agent action plist for AGENT under RIG-NAME.
Enriches AGENT with `work_dir'/`session_name' from SESSION-MAP, keyed on
the agent's qualified name, and records the tmux SOCKET for attach."
  (let* ((qname (alist-get 'qualified_name agent))
         (session (and qname (gethash qname session-map))))
    (list :name qname
          :rig rig-name
          :work-dir (and session (alist-get 'work_dir session))
          :session-name (and session (alist-get 'session_name session))
          :socket socket
          :running (alist-get 'running agent))))

;;; Rendering (vnodes)

(defun gascity-status--agent-row (agent rig-name session-map socket)
  "Return a vnode for AGENT (an alist) under RIG-NAME.
Stamps the row with a `gascity-agent' text property (carrying the tmux
SOCKET) so `d'/`t'/RET act on it."
  (let* ((qname (alist-get 'qualified_name agent))
         (name (or (alist-get 'name agent) qname "?"))
         (running (alist-get 'running agent))
         (suspended (alist-get 'suspended agent))
         (plist (gascity-status--agent-plist agent rig-name session-map socket)))
    (vui-text (format "  %s %s" (if running "●" "○") name)
              :face (gascity-section-state-face running suspended)
              'gascity-agent plist)))

(defun gascity-status--header-vnode (status)
  "Return the dashboard header vnode for the STATUS alist."
  (let* ((city (alist-get 'city_name status))
         (controller (alist-get 'controller status))
         (c-running (and controller (alist-get 'running controller)))
         (health (alist-get 'health status))
         (degraded (and health (alist-get 'degraded health)))
         (summary (alist-get 'summary status))
         (running-agents (or (and summary (alist-get 'running_agents summary)) 0))
         (total-agents (or (and summary (alist-get 'total_agents summary)) 0)))
    (vui-vstack
     (vui-hstack :spacing 1
                 (vui-text "Gas City:" :face 'gascity-header)
                 (vui-text (or city "?") :face 'gascity-city))
     (vui-text (format "  controller %s · health %s · agents %s/%s running"
                       (if c-running "up" "down")
                       (if degraded "degraded" "ok")
                       running-agents total-agents)
               :face 'gascity-dim))))

(defun gascity-status--content-vnode (status sessions)
  "Return the dashboard body vnode from STATUS and SESSIONS data."
  (let* ((session-map (gascity-status--session-map (or sessions [])))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status)))
         (agents (alist-get 'agents status))
         (rigs (append (alist-get 'rigs status) nil))
         (city-agents (seq-filter #'gascity-status--city-agent-p agents)))
    (vui-vstack
     :spacing 1
     (gascity-status--header-vnode status)
     (when city-agents
       (apply #'vui-vstack
              (vui-text "City" :face 'gascity-header)
              (mapcar (lambda (a)
                        (gascity-status--agent-row a nil session-map socket))
                      city-agents)))
     (vui-list rigs
               (lambda (rig)
                 (vui-component 'gascity-status-rig
                                :rig rig :agents agents
                                :session-map session-map :socket socket))
               (lambda (rig) (alist-get 'name rig))))))

(defun gascity-status--error-vnode (message)
  "Return a vnode reporting MESSAGE and how to retry."
  (vui-vstack
   (vui-text (format "Could not load Gas City status: %s" (or message "?"))
             :face 'gascity-failed)
   (vui-text "Press g to retry." :face 'gascity-dim)))

;;; Components

(vui-defcomponent gascity-status-rig (rig agents session-map socket)
  "A collapsible section for one RIG and its scoped AGENTS."
  :state ((collapsed nil))
  :render
  (let* ((name (alist-get 'name rig))
         (suspended (alist-get 'suspended rig))
         (rig-agents (gascity-status--rig-agents name agents))
         (header (format "%s %s%s"
                         (if collapsed "▶" "▼")
                         name
                         (if suspended "  (suspended)" ""))))
    (vui-vstack
     (vui-button header
                 :no-decoration t
                 :face (if suspended 'gascity-suspended 'gascity-rig)
                 :on-click (lambda () (vui-set-state :collapsed (not collapsed))))
     (unless collapsed
       (apply #'vui-vstack
              (or (mapcar (lambda (a)
                            (gascity-status--agent-row a name session-map socket))
                          rig-agents)
                  (list (vui-text "  (no agents)" :face 'gascity-dim))))))))

(vui-defcomponent gascity-status-app ()
  "Root component of the gascity status dashboard."
  :state ((refresh-tick 0))
  :render
  (let* ((status-res
          (vui-use-async (list 'status refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async '("status") resolve reject))))
         (sessions-res
          (vui-use-async (list 'sessions refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("session" "list") resolve reject))))
         (status-state (plist-get status-res :status))
         (sessions-state (plist-get sessions-res :status)))
    (cond
     ((eq status-state 'error)
      (gascity-status--error-vnode (plist-get status-res :error)))
     ((eq status-state 'pending)
      (vui-text "Loading Gas City status…" :face 'gascity-dim))
     (t
      (gascity-status--content-vnode
       (plist-get status-res :data)
       (and (eq sessions-state 'ready)
            (alist-get 'sessions (plist-get sessions-res :data))))))))

;;; Commands

(defun gascity-status-activate ()
  "Activate the widget at point, or open Dired on an agent row."
  (interactive)
  (cond
   ((widget-at (point)) (widget-button-press (point)))
   ((get-text-property (point) 'gascity-agent) (gascity-dired-at-point))
   (t (user-error "Nothing to activate here"))))

(defun gascity-status--refresh-instance (buffer)
  "Bump the refresh tick of the dashboard mounted in BUFFER.
Returns non-nil when a live instance was refreshed in place (preserving
collapse state); nil when BUFFER has no mounted instance."
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

(defun gascity-status-refresh ()
  "Reload the status dashboard's data, preserving expanded rigs."
  (interactive)
  (unless (gascity-status--refresh-instance (current-buffer))
    (gascity-status)))

;;; Mode

(defvar-keymap gascity-dashboard-mode-map
  :doc "Keymap for `gascity-dashboard-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-status-refresh
  "RET" #'gascity-status-activate
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  "n"   #'next-line
  "p"   #'previous-line)

(define-derived-mode gascity-dashboard-mode gascity-section-mode "GC-Status"
  "Major mode for the gascity status dashboard.

\\{gascity-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              " Gas City  (g refresh · RET toggle · d dired · t tmux · q bury)"))

;;;###autoload
(defun gascity-status ()
  "Show the Gas City status dashboard."
  (interactive)
  (let ((buf (get-buffer-create gascity-status-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-dashboard-mode)
        (gascity-dashboard-mode)))
    (unless (gascity-status--refresh-instance buf)
      ;; vui-mount switch-to-buffers internally; contain that so the buffer is
      ;; displayed once, via pop-to-buffer, on both the cold and refresh paths.
      (save-window-excursion
        (vui-mount (vui-component 'gascity-status-app) gascity-status-buffer-name)))
    (pop-to-buffer buf)))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-status))
  "Open the status dashboard instead of streaming raw output."
  (gascity-status))

(provide 'gascity-status)
;;; gascity-status.el ends here
