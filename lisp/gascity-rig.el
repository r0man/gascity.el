;;; gascity-rig.el --- vui rig dashboard -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The rig dashboard (DESIGN.md §6, §7 P4): a hand-built (magit/forge
;; style) detail view of one rig, rendered with vui.  It is the `RET'
;; target of a row in the rig list and of a rig section in the status
;; dashboard, replacing the read-only MVP's Dired stand-in.
;;
;; Sections, each backed by an independent `gc … --json' read so a slow
;; or failing one never blanks the others:
;;
;; - header        rig name, prefix, branch, suspended/running, beads,
;;                 and the city it belongs to (`gc rig status').
;; - agents        the rig's agents (polecat/refinery/witness/…), joined
;;                 to `gc session list' for each one's worktree and tmux
;;                 target so `d'/`t'/`i'/`RET' act on the agent at point.
;; - beads         the rig's ready and in-progress beads (`gc bd ready'
;;                 / `gc bd list --status in_progress', both `--rig'
;;                 scoped); `RET' opens one in beads.el (DESIGN.md §4.3).
;; - orders        the rig-scoped orders (`gc order list', filtered).
;; - dolt          the rig's Dolt database stats (`gc dolt health',
;;                 matched on the rig prefix — the per-rig db is named
;;                 after the prefix).
;;
;; `g' refreshes in place (preserving point); `RET' drills into the bead
;; at point or attaches the agent at point's terminal, while `i' opens an
;; agent's detail view; `b' opens the rig's whole bead store as a
;; beads.el board (DESIGN.md §4.3); the agent action keys
;; (`d'/`t'/`M'/`s'/`K'/`w'/`D'/`p') match the status dashboard and
;; session list, and `N'/`P' jump between the dashboard's sections.

;;; Code:

(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-reader)             ; gascity-reader-read-async (per-section loads)
(require 'gascity-types)             ; gascity-command-rig-list! (rig-name completion)
(require 'gascity-section)
(require 'gascity-tabulated)         ; shared cell formatters (--str, --vector->list)
(require 'gascity-status)            ; session-map + agent-plist join helpers

;; Detail/list openers and agent actions live in sibling modules loaded
;; alongside this one; reference them by name (resolved at call time).
(declare-function gascity-polecat-detail-at-point "gascity-session")
(declare-function gascity-dired-at-point "gascity-section")
(declare-function gascity-tmux-at-point "gascity-section")
(declare-function gascity-bead-visit "gascity-section")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")

;;; Buffer

(defvar-local gascity-rig-dashboard--rig-name nil
  "The rig name this dashboard buffer is showing.
Set when the buffer is created so buffer-wide actions (e.g. `b', which
opens the rig's beads in beads.el) act on the dashboard's rig regardless
of point.")

(defun gascity-rig-dashboard--buffer-name (rig-name)
  "Return the dashboard buffer name for RIG-NAME."
  (format "*gascity-rig: %s*" rig-name))

;;; Data shaping (pure)

(defun gascity-rig--db-for-prefix (databases prefix)
  "Return the Dolt database alist in DATABASES whose name is PREFIX, or nil.
Gas City names a rig's per-rig database after the rig's bead prefix (the
city HQ is `hq', the beads-meta store `beads'), so the rig dashboard
matches on PREFIX."
  (and prefix (not (string-empty-p prefix))
       (seq-find (lambda (db) (equal (alist-get 'name db) prefix))
                 (append databases nil))))

(defun gascity-rig--rig-orders (orders rig-name)
  "Return the ORDERS scoped to RIG-NAME.
City-wide orders carry a nil `rig' and are excluded."
  (seq-filter (lambda (o) (equal (alist-get 'rig o) rig-name))
              (append orders nil)))

;;; Rendering (vnodes)

(defun gascity-rig--header-vnode (rig city-name)
  "Return the header vnode for the RIG alist within CITY-NAME."
  (let* ((name (alist-get 'name rig))
         (prefix (alist-get 'prefix rig))
         (branch (alist-get 'default_branch rig))
         (suspended (alist-get 'suspended rig))
         (beads (alist-get 'beads rig)))
    (vui-vstack
     (vui-hstack :spacing 1
                 (vui-text "Rig:" :face 'gascity-header 'gascity-section t)
                 (vui-text (or name "?")
                           :face (if suspended 'gascity-suspended 'gascity-rig))
                 (when suspended (vui-text "(suspended)" :face 'gascity-suspended)))
     (vui-text (format "  prefix %s · branch %s · beads %s · city %s"
                       (or prefix "?") (or branch "—")
                       (or beads "?") (or city-name "?"))
               :face 'gascity-dim))))

(defun gascity-rig--agent-row (agent rig-name session-map socket)
  "Return a vnode for AGENT (an alist) under RIG-NAME.
Reuses the status dashboard's session join so the row carries a
`gascity-agent' plist (with the tmux SOCKET) for `d'/`t'/`RET'."
  (let* ((qname (alist-get 'qualified_name agent))
         (short (or (alist-get 'name agent) qname "?"))
         (running (alist-get 'running agent))
         (suspended (alist-get 'suspended agent))
         (draining (alist-get 'draining agent))
         (state (cond (suspended "suspended") (draining "draining")
                      (running "running") (t "stopped")))
         (plist (gascity-status--agent-plist agent rig-name session-map socket)))
    (vui-text (format "  %s %-30s %-9s %s"
                      (if running "●" "○") (or qname short) state short)
              :face (gascity-section-state-face running suspended)
              'gascity-agent plist)))

(defun gascity-rig--agents-vnode (agents rig-name session-map socket)
  "Return the agents-table vnode for AGENTS under RIG-NAME."
  (let ((rows (mapcar (lambda (a)
                        (gascity-rig--agent-row a rig-name session-map socket))
                      (append agents nil))))
    (apply #'vui-vstack
           (vui-text (format "Agents (%d)" (length rows))
                     :face 'gascity-header 'gascity-section t)
           (or rows (list (vui-text "  (no agents)" :face 'gascity-dim))))))

(defun gascity-rig--bead-row (bead)
  "Return a vnode for BEAD (an alist), stamped with its id for `RET'."
  (let ((id (gascity-tabulated--str (alist-get 'id bead)))
        (status (gascity-tabulated--str (alist-get 'status bead)))
        (title (gascity-tabulated--str (alist-get 'title bead))))
    (vui-text (format "  %-12s %-12s %s" id status title)
              'gascity-bead id)))

(defun gascity-rig--beads-section (title beads res)
  "Return a vnode for a beads section TITLE from async RES holding BEADS.
RES is a `vui-use-async' plist; while pending or on error the section
degrades to a dim placeholder rather than blanking the dashboard."
  (apply #'vui-vstack
         (vui-text (format "%s (%d)" title (length beads))
                   :face 'gascity-header 'gascity-section t)
         (pcase (plist-get res :status)
           ('pending (list (vui-text "  loading…" :face 'gascity-dim)))
           ('error   (list (vui-text "  (unavailable)" :face 'gascity-dim)))
           (_ (or (mapcar #'gascity-rig--bead-row beads)
                  (list (vui-text "  (none)" :face 'gascity-dim)))))))

(defun gascity-rig--orders-vnode (orders res)
  "Return the orders-section vnode for ORDERS, guarded by async RES."
  (apply #'vui-vstack
         (vui-text (format "Orders (%d)" (length orders))
                   :face 'gascity-header 'gascity-section t)
         (pcase (plist-get res :status)
           ('pending (list (vui-text "  loading…" :face 'gascity-dim)))
           ('error   (list (vui-text "  (unavailable)" :face 'gascity-dim)))
           (_ (or (mapcar
                   (lambda (o)
                     (vui-text (format "  %-28s %-8s %s"
                                       (gascity-tabulated--str
                                        (or (alist-get 'scoped_name o)
                                            (alist-get 'name o)))
                                       (gascity-tabulated--str (alist-get 'type o))
                                       (if (alist-get 'enabled o) "on" "off"))))
                   orders)
                  (list (vui-text "  (none)" :face 'gascity-dim)))))))

(defun gascity-rig--dolt-vnode (db res)
  "Return the Dolt-health vnode for database DB, guarded by async RES.
Shows only the Dolt commit count, not `gc dolt health''s `open_beads':
that metric reads 0 for every database in practice, so rendering it here
contradicted the Ready/In-progress bead sections shown just above (gce-ziz).
Open-bead counts belong to those sections, which read live `bd' data."
  (vui-vstack
   (vui-text "Dolt" :face 'gascity-header 'gascity-section t)
   (pcase (plist-get res :status)
     ('pending (vui-text "  loading…" :face 'gascity-dim))
     ('error   (vui-text "  (unavailable)" :face 'gascity-dim))
     (_ (if db
            (vui-text (format "  %s: %s commits"
                              (gascity-tabulated--str (alist-get 'name db))
                              (gascity-tabulated--str (alist-get 'commits db))))
          (vui-text "  (no database for this rig)" :face 'gascity-dim))))))

(defun gascity-rig--error-vnode (message)
  "Return a vnode reporting MESSAGE and how to retry."
  (vui-vstack
   (vui-text (format "Could not load rig: %s" (or message "?"))
             :face 'gascity-failed)
   (vui-text "Press g to retry." :face 'gascity-dim)))

;;; Component

(vui-defcomponent gascity-rig-dashboard-app (rig-name)
  "Root component of the rig dashboard for RIG-NAME."
  :state ((refresh-tick 0))
  :render
  ;; All async hooks run unconditionally, in order, every render.
  (let* ((status-res
          (vui-use-async (list 'rig refresh-tick rig-name)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            (list "rig" "status" rig-name) resolve reject))))
         (sessions-res
          (vui-use-async (list 'sessions refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("session" "list") resolve reject))))
         (ready-res
          (vui-use-async (list 'ready refresh-tick rig-name)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            (list "bd" "ready" "--rig" rig-name) resolve reject))))
         (inprog-res
          (vui-use-async (list 'inprog refresh-tick rig-name)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            (list "bd" "list" "--rig" rig-name
                                  "--status" "in_progress") resolve reject))))
         (orders-res
          (vui-use-async (list 'orders refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("order" "list") resolve reject))))
         (dolt-res
          (vui-use-async (list 'dolt refresh-tick)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("dolt" "health") resolve reject))))
         (status-state (plist-get status-res :status)))
    (cond
     ((eq status-state 'error)
      (gascity-rig--error-vnode (plist-get status-res :error)))
     ((eq status-state 'pending)
      (vui-text (format "Loading rig %s…" rig-name) :face 'gascity-dim))
     (t
      (let* ((data (plist-get status-res :data))
             (rig (alist-get 'rig data))
             (city-name (alist-get 'city_name data))
             (prefix (alist-get 'prefix rig))
             (agents (alist-get 'agents data))
             (sessions (and (eq (plist-get sessions-res :status) 'ready)
                            (alist-get 'sessions (plist-get sessions-res :data))))
             (session-map (gascity-status--session-map (or sessions [])))
             (socket (gascity-resolve-tmux-socket city-name))
             (ready (and (eq (plist-get ready-res :status) 'ready)
                         (gascity-section-beads (plist-get ready-res :data))))
             (inprog (and (eq (plist-get inprog-res :status) 'ready)
                          (gascity-section-beads (plist-get inprog-res :data))))
             (orders (and (eq (plist-get orders-res :status) 'ready)
                          (gascity-rig--rig-orders
                           (alist-get 'orders (plist-get orders-res :data))
                           rig-name)))
             (db (and (eq (plist-get dolt-res :status) 'ready)
                      (gascity-rig--db-for-prefix
                       (alist-get 'databases (plist-get dolt-res :data)) prefix))))
        (vui-vstack
         :spacing 1
         (gascity-rig--header-vnode rig city-name)
         (gascity-rig--agents-vnode agents rig-name session-map socket)
         (gascity-rig--beads-section "Ready" ready ready-res)
         (gascity-rig--beads-section "In progress" inprog inprog-res)
         (gascity-rig--orders-vnode orders orders-res)
         (gascity-rig--dolt-vnode db dolt-res)
         (vui-text (concat "g refresh · RET open/tmux · i detail · b beads · "
                           "d dired · t tmux · M/s/K/w/D session · p peek · "
                           "N/P section · q bury")
                   :face 'gascity-dim)))))))

;;; Commands

(defun gascity-rig-dashboard-activate ()
  "Drill into the thing at point: a bead opens in beads.el, an agent attaches.
On an agent row, RET attaches the agent's terminal (its tmux session) —
the primary action; `i' opens the agent's detail/info view instead.
Falls back to pressing a widget, else reports there is nothing to open."
  (interactive)
  (cond
   ((gascity-bead-at-point) (gascity-bead-visit))
   ((gascity-agent-at-point) (gascity-tmux-at-point))
   ((widget-at (point)) (widget-button-press (point)))
   (t (user-error "Nothing to open here"))))

(defun gascity-rig-dashboard-refresh ()
  "Reload the rig dashboard's data, preserving point."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No rig dashboard to refresh here")))

(defun gascity-rig-dashboard-beads ()
  "Open beads.el's board for this dashboard's rig, scoped to its store.
Acts on the rig the dashboard is showing (DESIGN.md §4.3), not the row at
point — the whole dashboard is one rig."
  (interactive)
  (gascity-rig-beads (or gascity-rig-dashboard--rig-name
                         (user-error "No rig dashboard here"))))

;;;###autoload
(defun gascity-rig-dashboard-at-point ()
  "Open the rig dashboard for the rig at point.
The city HQ (e.g. bright-lights) is listed by `gc rig list' for its beads,
but it is not a `city.toml' rig and has no rig dashboard: `gc rig status'
rejects it, so mounting one only yields an error screen whose `g' retry
can never succeed.  Refuse the HQ with a clear message instead; use
\\[gascity-status] for the city, or `b' for the HQ's beads."
  (interactive)
  (let ((rig (gascity-rig-at-point)))
    (unless rig (user-error "No rig at point"))
    (when (gascity-rig-at-point-hq-p)
      (user-error
       "%s is the city HQ, not a rig — no rig dashboard; use M-x gascity-status, or `b' for its beads"
       rig))
    (gascity-rig-dashboard rig)))

;;; Mode

(defvar-keymap gascity-rig-dashboard-mode-map
  :doc "Keymap for `gascity-rig-dashboard-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-rig-dashboard-refresh
  "RET" #'gascity-rig-dashboard-activate
  "i"   #'gascity-polecat-detail-at-point
  "b"   #'gascity-rig-dashboard-beads
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  ;; Nudge moves off `N' (now next-section, inherited from
  ;; `gascity-section-mode-map') to `M' (Message); `N'/`P' jump sections.
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "p"   #'gascity-session-peek-at-point)

(define-derived-mode gascity-rig-dashboard-mode gascity-section-mode "GC-Rig"
  "Major mode for the gascity rig dashboard.

\\{gascity-rig-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              (concat " Rig dashboard  (g refresh · RET open/tmux · i detail · b beads"
                      " · d dired · t tmux · M/s/K/w/D/p session · N/P section · q bury)")))

;;;###autoload
(defun gascity-rig-dashboard (rig-name)
  "Show the dashboard for rig RIG-NAME.
Prompts for the rig when called interactively, defaulting to the
contextual rig."
  (interactive
   (list (completing-read "Rig: "
                          (condition-case nil
                              (delq nil (mapcar (lambda (r) (alist-get 'name r))
                                                (append (alist-get 'rigs (gascity-command-rig-list!)) nil)))
                            (gascity-error nil))
                          nil nil nil nil (gascity-context-rig-name))))
  (let ((buf (get-buffer-create (gascity-rig-dashboard--buffer-name rig-name))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-rig-dashboard-mode)
        (gascity-rig-dashboard-mode))
      (setq gascity-rig-dashboard--rig-name rig-name))
    (unless (gascity-section-refresh-instance buf)
      ;; vui-mount switch-to-buffers internally; contain that so the buffer is
      ;; displayed once, via pop-to-buffer, on both the cold and refresh paths.
      (save-window-excursion
        (vui-mount (vui-component 'gascity-rig-dashboard-app :rig-name rig-name)
                   (gascity-rig-dashboard--buffer-name rig-name))))
    (pop-to-buffer buf)))

(provide 'gascity-rig)
;;; gascity-rig.el ends here
