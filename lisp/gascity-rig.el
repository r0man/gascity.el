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
(require 'gascity-context)            ; pin-directory (view keyed to its city)
(require 'gascity-domain)             ; typed agent + at-point visit generic
(require 'gascity-store)              ; gascity-store-use (per-section loads)
(require 'gascity-types)             ; gascity-command-rig-list! (rig-name completion)
(require 'gascity-section)
(require 'gascity-ui)
(require 'gascity-event)                ; noise classes
(require 'gascity-tabulated)         ; shared cell formatters (--str, --vector->list)
(require 'gascity-status)            ; session-map + agent join helpers

;; Detail/list openers and agent actions live in sibling modules loaded
;; alongside this one; reference them by name (resolved at call time).
(declare-function gascity-polecat-detail-at-point "gascity-session")
(declare-function magit-log-all "magit-log")
(declare-function vc-print-root-log "vc")
(declare-function gascity-dired-at-point "gascity-section")
(declare-function gascity-tmux-at-point "gascity-section")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-dashboard-suspend "gascity-dashboard")
(declare-function gascity-dashboard-reset "gascity-dashboard")
(declare-function gascity-rig-resume-at-point "gascity-action")
;; Write verbs (DESIGN-write-actions.md phase 1/2) bound in the keymap:
;; reset/undrain the agent at point, the bead-dispatch (`c') and sling
;; (`S') menus on a bead reference.
(declare-function gascity-session-reset-at-point "gascity-action")
(declare-function gascity-session-undrain-at-point "gascity-action")
(declare-function gascity-bead-dispatch "gascity-action")
(declare-function gascity-sling-dispatch "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")

;;; Buffer

(defvar-local gascity-rig-dashboard--rig-name nil
  "The rig name this dashboard buffer is showing.
Set when the buffer is created so buffer-wide actions (e.g. `b', which
opens the rig's beads in beads.el) act on the dashboard's rig regardless
of point.")

(defun gascity-rig-dashboard--buffer-name (rig-name)
  "Return the base dashboard buffer name for RIG-NAME.
The `view-buffer' factory (`gascity-view-get-buffer-create') qualifies it
with the host for a remote city, so a local and a remote rig dashboard
of the same name coexist."
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

;;; Rendering (vnodes, dashboard-v3 §6.1 / §7.13)

(defalias 'gascity-rig--path #'gascity-ui-path)

(defun gascity-rig--header-vnode (rig city-name)
  "Return the title line of the RIG alist within CITY-NAME.
`beads.el  be · main · ~/workspace/beads.el   city emacs-city' — the
line is a section header for `N'/`P'."
  (let* ((name (alist-get 'name rig))
         (suspended (alist-get 'suspended rig))
         (facts (string-join
                 (delq nil (list (alist-get 'prefix rig)
                                 (alist-get 'default_branch rig)
                                 (and (alist-get 'path rig)
                                      (gascity-rig--path (alist-get 'path rig)))))
                 " · ")))
    (vui-text (concat (propertize (or name "?") 'face (if suspended 'gascity-suspended
                                                        'gascity-rig))
                      (if suspended (propertize "  suspended" 'face 'gascity-suspended) "")
                      (if (string-empty-p facts) ""
                          (concat "  " (propertize facts 'face 'gascity-dim)))
                      (if city-name
                          (propertize (concat "   city " city-name) 'face 'gascity-dim)
                        ""))
              'gascity-section t
              'gascity-rig name
              'gascity-rig-dir (alist-get 'path rig))))

(defun gascity-rig--agent-row (agent rig-name session-map socket)
  "Return a vnode for AGENT (a raw `gc rig status' agent entry) under RIG-NAME.
SESSION-MAP and SOCKET join the row to its live session, whose last
activity renders as a relative time; the row carries the action
`gascity-agent' for the agent keys."
  (let* ((qname (alist-get 'qualified_name agent))
         (running (alist-get 'running agent))
         (suspended (alist-get 'suspended agent))
         (draining (alist-get 'draining agent))
         (state (cond (suspended "suspended") (draining "draining")
                      (running "running") (t "stopped")))
         (session (and qname (gethash qname session-map)))
         (obj (gascity-status--agent agent rig-name session-map socket)))
    (vui-text (concat "  " (gascity-ui-glyph (if running 'ok 'idle))
                      " " (gascity-ui-fit (or qname (alist-get 'name agent) "?") 40)
                      " " (gascity-ui-fit state 10)
                      (gascity-ui-time (and session (gascity-session-last-active session))))
              'gascity-agent obj)))

(defun gascity-rig--agents-summary (agents)
  "Return the Agents header summary of AGENTS: `1 running · 1 stopped'."
  (let ((running (seq-count (lambda (a) (alist-get 'running a)) agents)))
    (string-join (delq nil (list (and (> running 0) (format "%d running" running))
                                 (and (> (- (length agents) running) 0)
                                      (format "%d stopped" (- (length agents) running)))))
                 " · ")))

(defun gascity-rig--agents-vnode (agents rig-name session-map socket)
  "Return the Agents section vnode for AGENTS under RIG-NAME.
SESSION-MAP and SOCKET join each row to its live session."
  (let ((agents (append agents nil)))
    (apply #'vui-vstack
           (gascity-ui-section-header
            "Agents" (if agents (gascity-rig--agents-summary agents) "none"))
           (mapcar (lambda (a)
                     (gascity-rig--agent-row a rig-name session-map socket))
                   agents))))

(defun gascity-rig--bead-row (bead &optional key)
  "Return a vnode for BEAD (an alist), stamped with its id for `RET'.
KEY names the `+'/`-' expandable section the row belongs to."
  (let ((id (gascity-tabulated--str (alist-get 'id bead))))
    (vui-text (concat "  " (gascity-ui-fit id 10)
                      " " (gascity-ui-fit (format "P%s" (or (alist-get 'priority bead) "?")) 3)
                      " " (gascity-ui-fit (gascity-tabulated--str (alist-get 'title bead)) 48)
                      " " (gascity-ui-time (alist-get 'updated_at bead)))
              'gascity-bead id
              'gascity-expand-key key)))

(defun gascity-rig--beads-model (data)
  "Return (SHOWN . HIDDEN) for a `gc bd …' payload DATA.
SHOWN is the work beads; HIDDEN counts the noise left out per category
\(`gascity-event-noise': sessions, convoys, wisps, nudges, order churn,
messages), as the cockpit's Work does (D4)."
  (let (shown hidden)
    (dolist (b (gascity-section-beads data))
      (let ((noise (gascity-event-noise b)))
        (if noise
            (setf (alist-get noise hidden) (1+ (alist-get noise hidden 0)))
          (push b shown))))
    (cons (nreverse shown) (nreverse hidden))))

(defvar gascity-rig--extra nil
  "The rig dashboard's `+' expansions while it renders: (SECTION . ROWS).")

(defun gascity-rig--more-row (n title)
  "Return the `… N more' row of section TITLE; RET opens the rig's beads."
  (vui-text (gascity-ui-right-align
             (propertize (format "  … %d more" n) 'face 'gascity-dim)
             (propertize "+ more  b beads" 'face 'gascity-dim) 78)
            'gascity-rig-more t
            'gascity-expand-more t
            'gascity-expand-key (downcase title)
            'beads-thing (list :kind 'more :id (concat "more:" title))))

(defun gascity-rig--beads-section (title load)
  "Return the beads section TITLE for LOAD, a `gascity-ui-effective-load'.
The load's data is the raw `gc bd …' payload.  Noise is hidden with a
`(N hidden)' tally, and at most `gascity-dashboard-section-rows' rows
show; a `… N more' line opens the rig's beads in beads.el (§4.2)."
  (let* ((key (downcase title))
         (max (+ (or (bound-and-true-p gascity-dashboard-section-rows) 5)
                 (gascity-section-extra key gascity-rig--extra))))
    (gascity-ui-section
     key title load nil
     (lambda (data)
       (let ((shown (car (gascity-rig--beads-model data))))
         (append (mapcar (lambda (b) (gascity-rig--bead-row b key)) (seq-take shown max))
                 (and (> (length shown) max)
                      (list (gascity-rig--more-row (- (length shown) max) title))))))
     (lambda (data)
       (let* ((model (gascity-rig--beads-model data))
              (n (length (car model)))
              (hidden (gascity-ui-hidden-label (cdr model))))
         (cond ((and (zerop n) (null hidden)) 0)
               (hidden (format "%s  %s" (if (zerop n) "none" n) hidden))
               (t n))))
     key)))

(defun gascity-rig--orders-vnode (rig-name load)
  "Return the Orders section for RIG-NAME from the `gc order list' LOAD."
  (let ((orders (lambda (data) (gascity-rig--rig-orders (alist-get 'orders data)
                                                        rig-name))))
    (gascity-ui-section
     "orders" "Orders" load nil
     (lambda (data)
       (mapcar (lambda (o)
                 (vui-text (concat "  " (gascity-ui-glyph (if (alist-get 'enabled o) 'ok 'idle))
                                   " " (gascity-ui-fit
                                        (gascity-tabulated--str
                                         (or (alist-get 'scoped_name o) (alist-get 'name o)))
                                        40)
                                   " " (gascity-tabulated--str (alist-get 'type o)))))
               (funcall orders data)))
     (lambda (data) (length (funcall orders data))))))

(defun gascity-rig--dolt-vnode (prefix load)
  "Return the Dolt section: the rig's database (named PREFIX) from LOAD.
Only the commit count: `gc dolt health''s `open_beads' reads 0 for every
database in practice, contradicting the bead sections (gce-ziz)."
  (let ((db (lambda (data) (gascity-rig--db-for-prefix (alist-get 'databases data)
                                                       prefix))))
    (gascity-ui-section
     "dolt" "Dolt" load nil
     (lambda (data)
       (let ((d (funcall db data)))
         (list (vui-text (format "  %s  %s commits"
                                 (gascity-tabulated--str (alist-get 'name d))
                                 (gascity-tabulated--str (alist-get 'commits d)))))))
     (lambda (data) (if (funcall db data) 1 0)))))

;;; Component

(vui-defcomponent gascity-rig-dashboard-app (rig-name)
  "Root component of the rig dashboard for RIG-NAME.
Each section reads independently and refreshes stale-while-revalidate:
the last payload keeps rendering while a reload is in flight."
  :state ((refresh-tick 0) (extra nil))
  :render
  ;; All store hooks run unconditionally, in order, every render.
  (let* ((status-res
          (gascity-store-use (list "rig" "status" rig-name) :tick refresh-tick))
         (sessions-res
          (gascity-store-use '("session" "list") :tick refresh-tick))
         (ready-res
          (gascity-store-use (list "bd" "ready" "--rig" rig-name "-n" "0")
                             :tick refresh-tick))
         (inprog-res
          (gascity-store-use (list "bd" "list" "--rig" rig-name
                                   "--status" "in_progress" "-n" "0")
                             :tick refresh-tick))
         (orders-res
          (gascity-store-use '("order" "list") :tick refresh-tick))
         (dolt-res
          (gascity-store-use '("dolt" "health") :tick refresh-tick))
         (status (gascity-ui-store-load status-res))
         (sessions (gascity-ui-store-load sessions-res))
         (ready (gascity-ui-store-load ready-res))
         (inprog (gascity-ui-store-load inprog-res))
         (orders (gascity-ui-store-load orders-res))
         (dolt (gascity-ui-store-load dolt-res)))
    (pcase (plist-get status :state)
      ('error (vui-vstack
               (gascity-ui-section-header rig-name nil)
               (gascity-ui-error-line (format "rig status %s" rig-name)
                                      (plist-get status :error))))
      ('pending (gascity-ui-section-header rig-name (propertize "…" 'face 'gascity-dim)))
      (_
       (let* ((data (plist-get status :data))
              (rig (alist-get 'rig data))
              (city-name (alist-get 'city_name data))
              (session-map (gascity-status--session-map
                            (or (alist-get 'sessions (plist-get sessions :data)) [])))
              ;; Render: no synchronous gc fallback (`no-probe').
              (socket (gascity-resolve-tmux-socket city-name 'no-probe)))
         (vui-vstack
          :spacing 1
          (gascity-rig--header-vnode rig city-name)
          (gascity-rig--agents-vnode (alist-get 'agents data) rig-name
                                     session-map socket)
          (let ((gascity-rig--extra extra))
            (gascity-rig--beads-section "Ready" ready))
          (let ((gascity-rig--extra extra))
            (gascity-rig--beads-section "In progress" inprog))
          (gascity-rig--orders-vnode rig-name orders)
          (gascity-rig--dolt-vnode (alist-get 'prefix rig) dolt)))))))

;;; Commands

(defun gascity-rig-dashboard-activate ()
  "Drill into the thing at point: a bead opens in beads.el, an agent attaches.
Dispatches via `gascity-at-point-visit' on the object at point — a bead id
opens in beads.el, an agent attaches its terminal (the primary action; `i'
opens its detail view).  Falls back to pressing a widget, else reports there
is nothing to open."
  (interactive)
  (let ((obj (gascity-object-at-point)))
    (cond
     ((get-text-property (point) 'gascity-rig-more) (gascity-rig-dashboard-beads))
     (obj (gascity-at-point-visit obj))
     ((widget-at (point)) (widget-button-press (point)))
     (t (user-error "Nothing to open here")))))

(defun gascity-rig-dashboard-refresh (&optional reset)
  "Reload the rig dashboard's data, preserving point.
With a prefix argument RESET (`C-u g'), sections expanded with `+'
return to their cap."
  (interactive "P")
  (when reset (gascity-section-reset-extra))
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No rig dashboard to refresh here")))

(defun gascity-rig-dashboard-beads ()
  "Open beads.el's board for this dashboard's rig, scoped to its store.
Acts on the rig the dashboard is showing (DESIGN.md §4.3), not the row at
point — the whole dashboard is one rig."
  (interactive)
  (gascity-rig-beads (or gascity-rig-dashboard--rig-name
                         (user-error "No rig dashboard here"))))

(cl-defmethod gascity-at-point-visit ((rig gascity-rig))
  "Visit RIG: open its dashboard.
Refuses the city HQ (e.g. bright-lights): `gc rig list' lists it for its
beads, but it is not a `city.toml' rig and has no rig dashboard (`gc rig
status' rejects it, so mounting one only yields an un-retryable error
screen).  Directs to \\[gascity-dashboard] for the city, or `b' for its beads."
  (when (gascity-rig-hq rig)
    (user-error
     "%s is the city HQ, not a rig — no rig dashboard; use M-x gascity-dashboard, or `b' for its beads"
     (gascity-rig-name rig)))
  (gascity-rig-dashboard (gascity-rig-name rig)))

;;;###autoload
(defun gascity-rig-dashboard-at-point ()
  "Open the rig dashboard for the rig at point.
Dispatches through `gascity-at-point-visit', whose `gascity-rig' method
refuses the city HQ (which has no rig dashboard) with a clear message."
  (interactive)
  (let ((rig (gascity-object-at-point)))
    (if (gascity-rig-p rig)
        (gascity-at-point-visit rig)
      (user-error "No rig at point"))))

(defun gascity-rig-dashboard-log ()
  "Show the git log of this dashboard's rig repository (`l', §7.13).
`magit-log-all' when magit is installed, else `vc-print-root-log'; the
rig path is host-qualified first, so a remote rig logs on its host."
  (interactive)
  (let ((path (get-text-property (point-min) 'gascity-rig-dir)))
    (unless path (user-error "No repository path for this rig yet"))
    (let ((default-directory (file-name-as-directory
                              (gascity-remote-localize-path path))))
      (if (require 'magit-log nil t)
          (magit-log-all)
        (vc-print-root-log)))))

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
  ;; `gascity-section-mode-map') to `M' (Message); `N'/`P' jump sections
  ;; and `n'/`p' move by line (all inherited).  Peek moves off `p' to `v'.
  "M"   #'gascity-session-nudge-at-point
  ;; The title line is the rig's row (§5.3): `s'/`R' act on the agent
  ;; at point, else on the rig; `r' resumes the rig.
  "s"   #'gascity-dashboard-suspend
  "r"   #'gascity-rig-resume-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "v"   #'gascity-session-peek-at-point
  ;; Write verbs: reset/undrain the agent at point.  Phase 2 promotes `c'
  ;; to the bead-dispatch menu (note moved to its `o') and adds `S' for the
  ;; sling/route flag transient on a ready/in-progress bead reference.
  "R"   #'gascity-dashboard-reset
  "U"   #'gascity-session-undrain-at-point
  "c"   #'gascity-bead-dispatch
  "S"   #'gascity-sling-dispatch
  "l"   #'gascity-rig-dashboard-log)

(define-derived-mode gascity-rig-dashboard-mode gascity-section-mode "GC-Rig"
  "Major mode for the gascity rig dashboard.

\\{gascity-rig-dashboard-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              '(:eval (gascity-ui-header-line
                       (propertize (concat "rig " (or gascity-rig-dashboard--rig-name "?"))
                                   'face 'gascity-rig)))))

;;;###autoload
(defun gascity-rig-dashboard (rig-name)
  "Show the dashboard for rig RIG-NAME.
Prompts for the rig when called interactively, defaulting to the
contextual rig."
  (interactive
   ;; Candidates and default from memory only (§8.5: a prompt never
   ;; runs gc synchronously); the rig list refreshes in the background.
   (list (completing-read "Rig: " (gascity-rig-names-for-prompt)
                          nil nil nil nil (gascity-context-rig-name-cached))))
  (let ((buf (gascity-view-get-buffer-create
              (gascity-rig-dashboard--buffer-name rig-name))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-rig-dashboard-mode)
        (gascity-rig-dashboard-mode))
      (setq gascity-rig-dashboard--rig-name rig-name))
    (unless (gascity-section-refresh-instance buf)
      ;; vui-mount switch-to-buffers internally; contain that so the buffer is
      ;; displayed once, via pop-to-buffer, on both the cold and refresh paths.
      (save-window-excursion
        (vui-mount (vui-component 'gascity-rig-dashboard-app :rig-name rig-name)
                   (buffer-name buf))))
    (pop-to-buffer buf)))

(provide 'gascity-rig)
;;; gascity-rig.el ends here
