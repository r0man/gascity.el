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
;; agent's worktree in Dired, `t' (or RET) attaches to its tmux session,
;; `i' opens an agent's detail view, and RET toggles a rig header.

;;; Code:

(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-reader)
(require 'gascity-command)
(require 'gascity-command-status)
(require 'gascity-section)

;; Session actions on the agent at point live in gascity-action, and the
;; polecat-detail opener in gascity-session — both loaded after this
;; module via gascity.el; the dashboard keymap binds to them.
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-polecat-detail-at-point "gascity-session")

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

(defun gascity-status--content-vnode (status sessions &optional sessions-state sessions-error)
  "Return the dashboard body vnode from STATUS and SESSIONS data.
SESSIONS-STATE/SESSIONS-ERROR describe the `gc session list' load so a
one-line hint can warn that `d'/`t' are disabled when it did not succeed."
  (let* ((session-map (gascity-status--session-map (or sessions [])))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status)))
         (agents (alist-get 'agents status))
         (rigs (append (alist-get 'rigs status) nil))
         (city-agents (seq-filter #'gascity-status--city-agent-p agents)))
    (vui-vstack
     :spacing 1
     (gascity-status--header-vnode status)
     (gascity-status--sessions-note-vnode sessions-state sessions-error)
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

(defun gascity-status--sessions-note-vnode (state error)
  "Return a one-line hint vnode when sessions are unavailable, else nil.
STATE is the `vui-use-async' status of the `gc session list' load and
ERROR its message.  The dashboard renders even when that load has not
succeeded, but without it agent rows carry no `work_dir'/`session_name',
so `d' (Dired) and `t' (tmux attach) silently no-op.  Surface why instead
of degrading invisibly; a `ready' load needs no note (returns nil)."
  (pcase state
    ('error
     (vui-text (format "  Sessions unavailable — d/t disabled (%s)"
                       (or error "load failed"))
               :face 'gascity-failed))
    ('pending
     (vui-text "  Sessions loading — d/t available once ready"
               :face 'gascity-dim))))

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
  ;; Stale-while-revalidate.  `g' refreshes by bumping `refresh-tick',
  ;; which changes every `vui-use-async' key and so restarts each load as
  ;; 'pending with nil data.  Rendering the pending branch (a bare
  ;; "Loading…" line) replaces the whole tree and unmounts every keyed
  ;; `gascity-status-rig' child — destroying its component-local collapse
  ;; `:state' (and blanking the view, losing point) on *every* refresh.
  ;; Instead, cache the last good payload in a ref and keep rendering it
  ;; while the refreshed load is in flight, swapping in fresh data only on
  ;; 'ready.  Keyed children then reconcile in place, so collapse state
  ;; survives a refresh.  The fallback screens (loading / error) show only
  ;; on the first, dataless load — never over a snapshot we can still show.
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
         (sessions-state (plist-get sessions-res :status))
         (last-status (vui-use-ref nil))
         (last-sessions (vui-use-ref nil))
         ;; `setcar' both refreshes the cache and returns the new value, so
         ;; on 'ready we adopt fresh data; otherwise we reuse the snapshot.
         (status (if (eq status-state 'ready)
                     (setcar last-status (plist-get status-res :data))
                   (car last-status)))
         (sessions (if (eq sessions-state 'ready)
                       (setcar last-sessions
                               (alist-get 'sessions (plist-get sessions-res :data)))
                     (car last-sessions)))
         ;; The sessions hint reflects whether usable data is in hand, not
         ;; the raw load state: a refresh still holding a snapshot keeps
         ;; `d'/`t' working, so it needs no "loading" note.
         (sessions-note-state (if sessions 'ready sessions-state)))
    (cond
     ((and (eq status-state 'error) (null status))
      (gascity-status--error-vnode (plist-get status-res :error)))
     ((and (eq status-state 'pending) (null status))
      (vui-text "Loading Gas City status…" :face 'gascity-dim))
     (t
      (gascity-status--content-vnode
       status sessions sessions-note-state
       (plist-get sessions-res :error))))))

;;; Commands

(defun gascity-status-activate ()
  "Activate the thing at point.
On a rig header (a widget) this toggles its collapse; on an agent row it
attaches the agent's terminal (its tmux session) — the primary action.
`i' opens the agent's detail/info view instead."
  (interactive)
  (cond
   ((widget-at (point)) (widget-button-press (point)))
   ((get-text-property (point) 'gascity-agent) (gascity-tmux-at-point))
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
  "i"   #'gascity-polecat-detail-at-point
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  "N"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "n"   #'next-line
  "p"   #'previous-line)

(define-derived-mode gascity-dashboard-mode gascity-section-mode "GC-Status"
  "Major mode for the gascity status dashboard.

\\{gascity-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              (concat " Gas City  (g refresh · RET tmux/toggle · i detail · d dired"
                      " · t tmux · N/s/K/w/D session · q bury)")))

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
