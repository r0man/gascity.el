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
;; `i' opens an agent's detail view, `b' opens the beads board (the rig's
;; store on a rig header, the agent's worktree on an agent row), and RET
;; toggles a rig header.

;;; Code:

(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-domain)             ; typed session/agent objects
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
  "Return a hash table mapping a session's qualified agent name to its object.
SESSIONS is the vector (or list) from `gc session list'; each row is decoded
into a `gascity-session' and keyed on its qualified name
\(`gascity-session-qualified-name', which prefers `agent_name' — always the
qualified name — over the volatile `name').  The qualified name is the
reliable join key against a status agent's `qualified_name'."
  (let ((map (make-hash-table :test 'equal)))
    (seq-do (lambda (s)
              (let ((key (gascity-session-qualified-name s)))
                (when key (puthash key s map))))
            (gascity-domain-decode-list 'gascity-session sessions))
    map))

(defun gascity-status--agent (agent rig-name session-map socket)
  "Build the action `gascity-agent' for AGENT under RIG-NAME.
AGENT is a raw `gc status' agent entry; this bridges it to the typed action
object, enriching it with the worktree and tmux name from the matching
`gascity-session' in SESSION-MAP (keyed on the agent's qualified name) and
recording the tmux SOCKET for attach."
  (let* ((qname (alist-get 'qualified_name agent))
         (session (and qname (gethash qname session-map))))
    (make-instance 'gascity-agent
                   :name qname
                   :rig rig-name
                   :work-dir (and session (gascity-session-work-dir session))
                   :session-name (and session (gascity-session-session-name session))
                   :socket socket
                   :running (and (alist-get 'running agent) t))))

;;; Rendering (vnodes)

(defun gascity-status--agent-row (agent rig-name session-map socket)
  "Return a vnode for AGENT (a raw `gc status' agent entry) under RIG-NAME.
Stamps the row with the action `gascity-agent' (carrying the tmux SOCKET) as
a text property so `d'/`t'/RET act on it."
  (let* ((qname (alist-get 'qualified_name agent))
         (name (or (alist-get 'name agent) qname "?"))
         (running (alist-get 'running agent))
         (suspended (alist-get 'suspended agent))
         (obj (gascity-status--agent agent rig-name session-map socket)))
    (vui-text (format "  %s %s" (if running "●" "○") name)
              :face (gascity-section-state-face running suspended)
              'gascity-agent obj)))

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
                 (vui-text "Gas City:" :face 'gascity-header 'gascity-section t)
                 (vui-text (or city "?") :face 'gascity-city))
     (vui-text (format "  controller %s · health %s · agents %s/%s running"
                       (if c-running "up" "down")
                       (if degraded "degraded" "ok")
                       running-agents total-agents)
               :face 'gascity-dim))))

(defun gascity-status--content-vnode (status sessions &optional sessions-state sessions-error collapsed-rigs)
  "Return the dashboard body vnode from STATUS and SESSIONS data.
SESSIONS-STATE/SESSIONS-ERROR describe the `gc session list' load so a
one-line hint can warn that `d'/`t' are disabled when it did not succeed.
COLLAPSED-RIGS is the app's list of collapsed rig names; each rig section
is told whether it is collapsed (lifted there so the keymap can toggle the
rig at point — see `gascity-status--toggle-rig')."
  (let* ((session-map (gascity-status--session-map (or sessions [])))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status)))
         (agents (alist-get 'agents status))
         (rigs (gascity-domain-decode-list 'gascity-rig (alist-get 'rigs status)))
         (city-agents (seq-filter #'gascity-status--city-agent-p agents)))
    (vui-vstack
     :spacing 1
     (gascity-status--header-vnode status)
     (gascity-status--sessions-note-vnode sessions-state sessions-error)
     (when city-agents
       (apply #'vui-vstack
              (vui-text "City" :face 'gascity-header 'gascity-section t)
              (mapcar (lambda (a)
                        (gascity-status--agent-row a nil session-map socket))
                      city-agents)))
     ;; `:spacing 1' renders a blank line between rig groups for visual
     ;; separation; the keyed `vui-list' still reconciles each rig in place,
     ;; so collapse state and point survive a refresh.
     (vui-list rigs
               (lambda (rig)
                 (vui-component 'gascity-status-rig
                                :rig rig :agents agents
                                :session-map session-map :socket socket
                                :collapsed (and (member (gascity-rig-name rig)
                                                        collapsed-rigs)
                                                t)))
               (lambda (rig) (gascity-rig-name rig))
               :spacing 1))))

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

;; Rig headers are property-carrying text (the magit/forge idiom this
;; dashboard follows), not widgets: a `gascity-rig' (name) / `gascity-rig-dir'
;; (path) text property lets the keymap commands act on the rig at point —
;; RET toggles collapse, `d' opens its directory.  This keymap restores the
;; click-to-toggle the old header button gave; only `mouse-1' is bound, so
;; RET and `n'/`p' fall through to the buffer keymap.  The binding is a
;; quoted symbol (not #') so the command may be defined later in the file
;; without a byte-compile forward-reference warning.
(defvar gascity-status-header-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] 'gascity-status-mouse-1)
    map)
  "Keymap placed on rig-header text so a left click toggles its collapse.")

(vui-defcomponent gascity-status-rig (rig agents session-map socket collapsed)
  "A collapsible section for one RIG (a `gascity-rig') and its scoped AGENTS.
COLLAPSED is supplied by the parent from the app's `collapsed-rigs' state
\(lifted there so the keymap can toggle the rig at point and the state
survives a refresh).  The header is stamped with `gascity-rig' (the rig
name, for the toggle) and `gascity-rig-dir' (its `path', for `d')."
  :render
  (let* ((name (gascity-rig-name rig))
         (path (gascity-rig-path rig))
         (suspended (gascity-rig-suspended rig))
         (rig-agents (gascity-status--rig-agents name agents))
         (header (format "%s %s%s"
                         (if collapsed "▶" "▼")
                         name
                         (if suspended "  (suspended)" ""))))
    (vui-vstack
     (vui-text header
               :face (if suspended 'gascity-suspended 'gascity-rig)
               'gascity-rig name
               'gascity-rig-dir path
               'gascity-section t
               'mouse-face 'highlight
               'keymap gascity-status-header-keymap)
     (unless collapsed
       (apply #'vui-vstack
              (or (mapcar (lambda (a)
                            (gascity-status--agent-row a name session-map socket))
                          rig-agents)
                  (list (vui-text "  (no agents)" :face 'gascity-dim))))))))

(vui-defcomponent gascity-status-app ()
  "Root component of the gascity status dashboard."
  :state ((refresh-tick 0) (collapsed-rigs nil))
  :render
  ;; Collapse state (`collapsed-rigs', a list of collapsed rig names) lives
  ;; here, in the root component, rather than per rig section: a keymap
  ;; command (`gascity-status--toggle-rig', reached via RET/`mouse-1' on a
  ;; header) can then flip the rig at point, and the list survives a refresh
  ;; since `g' only bumps `refresh-tick'.
  ;;
  ;; Stale-while-revalidate.  `g' refreshes by bumping `refresh-tick',
  ;; which changes every `vui-use-async' key and so restarts each load as
  ;; 'pending with nil data.  Rendering the pending branch (a bare
  ;; "Loading…" line) replaces the whole tree and blanks the view, losing
  ;; point, on *every* refresh.  Instead, cache the last good payload in a
  ;; ref and keep rendering it while the refreshed load is in flight,
  ;; swapping in fresh data only on 'ready.  Keyed children then reconcile
  ;; in place, so point survives a refresh.  The fallback screens (loading /
  ;; error) show only on the first, dataless load — never over a snapshot we
  ;; can still show.
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
       (plist-get sessions-res :error)
       collapsed-rigs)))))

;;; Commands

(defun gascity-status-activate ()
  "Activate the thing at point.
On a rig header this toggles its collapse; on an agent row it visits the
agent via `gascity-at-point-visit' — attaching its tmux terminal, the
primary action.  `i' opens the agent's detail/info view instead."
  (interactive)
  (let ((obj (gascity-object-at-point)))
    (cond
     ((get-text-property (point) 'gascity-rig)
      (gascity-status--toggle-rig (get-text-property (point) 'gascity-rig)))
     (obj (gascity-at-point-visit obj))
     (t (user-error "Nothing to activate here")))))

(defun gascity-status-mouse-1 (event)
  "Move point to the rig header clicked by mouse EVENT and activate it.
Bound on header text via `gascity-status-header-keymap', this restores the
click-to-toggle the old header button provided."
  (interactive "e")
  (mouse-set-point event)
  (gascity-status-activate))

(defun gascity-status-toggle-section ()
  "Toggle collapse of the rig section at point.
The magit-section convention binds `TAB' to \"toggle the visibility of the
section at point\"; this is the dashboard's `TAB'.  The status board's only
collapsible sections are its rig headers (stamped with a `gascity-rig' text
property); on one, this flips its collapse via `gascity-status--toggle-rig'
— the same toggle `RET' performs on a header (`gascity-status-activate').
Off a rig header (an agent row, the city block) there is nothing
collapsible, so it signals a clean `user-error' rather than acting on
something unrelated — `TAB' toggles, never attaches."
  (interactive)
  (let ((rig (get-text-property (point) 'gascity-rig)))
    (if rig
        (gascity-status--toggle-rig rig)
      (user-error "No section to toggle here"))))

(defun gascity-status--toggle-rig (name)
  "Toggle whether rig NAME is collapsed in the status dashboard.
Flips NAME in the root `gascity-status-app' component's `collapsed-rigs'
state and re-renders in place via `vui-flush-sync' — no re-fetch, since the
`vui-use-async' keys are unchanged.  Mirrors `gascity-status--refresh-instance'."
  (when (and (boundp 'vui--root-instance) vui--root-instance)
    (let* ((instance vui--root-instance)
           (state (vui-instance-state instance))
           (collapsed (plist-get state :collapsed-rigs)))
      (setf (vui-instance-state instance)
            (plist-put state :collapsed-rigs
                       (if (member name collapsed)
                           (remove name collapsed)
                         (cons name collapsed))))
      (vui-flush-sync))))

(defun gascity-status--refresh-instance (buffer)
  "Bump the refresh tick of the dashboard mounted in BUFFER.
Returns non-nil when a live instance was refreshed in place (preserving
collapse state and point); nil when BUFFER has no mounted instance."
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
  ;; `TAB' toggles the rig section at point — the magit-section convention
  ;; (TAB = toggle visibility).  It shadows the vui chain's `widget-forward'
  ;; (harmless: this view renders no widgets) and is bound here, not in the
  ;; shared `gascity-section-mode-map', because the status board is the only
  ;; dashboard with collapsible sections.  `RET' still toggles too (on a
  ;; header) and attaches the agent's terminal (on a row).
  "TAB" #'gascity-status-toggle-section
  "RET" #'gascity-status-activate
  "i"   #'gascity-polecat-detail-at-point
  "b"   #'gascity-beads-at-point
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  ;; Nudge moves off `N' (now next-section, inherited from
  ;; `gascity-section-mode-map') to `M' (Message).  Line movement (`n'/`p')
  ;; and section jumps (`N'/`P') are both inherited from the shared map.
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point)

(define-derived-mode gascity-dashboard-mode gascity-section-mode "GC-Status"
  "Major mode for the gascity status dashboard.

\\{gascity-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              (concat " Gas City  (g refresh · TAB toggle · RET tmux/toggle · i detail"
                      " · b beads · d dired · t tmux · M/s/K/w/D session · N/P section"
                      " · q bury)")))

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
