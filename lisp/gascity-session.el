;;; gascity-session.el --- vui session/polecat detail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The session/polecat detail view (DESIGN.md §6, §7 P4): a hand-built
;; (magit/forge style) detail of one agent session, rendered with vui.
;; It is the `RET' target of a row in the session list, of an agent row
;; in the status dashboard, and of an agent row in the rig dashboard —
;; replacing the read-only MVP's Dired stand-in.
;;
;; Sections, each backed by an independent `gc … --json' read:
;;
;; - state       running/suspended/closed, provider, attached, last
;;               active, worktree, tmux target (`gc session list', the
;;               row matched by the agent's qualified name).
;; - mail        the agent's inbox message count (`gc mail inbox ALIAS').
;; - on hook     the bead currently in progress for the agent.
;; - history     the agent's other recent beads, newest first —
;;               including work it has already handed off.
;;
;; Beads are gathered two ways and merged (de-duped by id), each read
;; rig-scoped and newest-first:
;;
;; - By assignee.  A polecat's open work is filed under its runtime
;;   session name, a service agent's under its qualified name, so both
;;   keys are tried.
;; - By worktree.  A polecat's *finished* work is reassigned away from it
;;   — to the refinery, which merges and closes it — so by assignee alone
;;   a productive polecat shows no history at all.  But each such bead
;;   still records the `metadata.work_dir' it was built in, nested under
;;   the agent's worktree; so beads carrying a `work_dir' are fetched and
;;   kept when that path lies within the agent's own worktree.
;;
;; `RET' opens the bead at point in beads.el (DESIGN.md §4.3).
;;
;; The action keys act on the buffer's subject agent (set buffer-locally
;; via `gascity-section--agent', so `gascity-agent-at-point' resolves it
;; anywhere in the buffer): `p' peeks at recent output, `N' nudges, `D'
;; drains, `s' suspends, `K' kills, `w' wakes, `d' opens the worktree in
;; Dired, `t' attaches to tmux.  `g' refreshes in place.

;;; Code:

(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-reader)
(require 'gascity-section)
(require 'gascity-tabulated)         ; shared cell formatters

;; Agent actions and the shared bead visitor live in sibling modules
;; loaded alongside this one; reference them by name.
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

(defun gascity-session-detail--buffer-name (name)
  "Return the detail buffer name for agent NAME."
  (format "*gascity-agent: %s*" name))

;;; Data shaping (pure)

(defun gascity-session--find (sessions name)
  "Return the session alist in SESSIONS for agent NAME, or nil.
Matches NAME against the qualified `agent_name', the volatile `name',
and the `alias'."
  (seq-find (lambda (s)
              (member name (list (alist-get 'agent_name s)
                                 (alist-get 'name s)
                                 (alist-get 'alias s))))
            (append sessions nil)))

(defun gascity-session--assignee-keys (agent)
  "Return the distinct assignee strings AGENT's beads may be filed under.
A polecat's beads are assigned to its runtime session name
\(`:session-name'); a service agent's to its qualified name (`:name').
Both are tried so the lookup works for either."
  (seq-uniq (seq-remove #'string-empty-p
                        (delq nil (list (plist-get agent :name)
                                        (plist-get agent :session-name))))))

(defun gascity-session--bead-args (key rig)
  "Return `gc bd list' args for the beads assigned to KEY, newest first.
Server-side `--assignee' (an exact match) is used rather than fetching a
broad window and filtering client-side: an agent's own beads are easily
buried under a town's many recently-closed order/molecule beads.  RIG,
when non-nil, scopes the query to that rig's bead store."
  (append (list "bd" "list" "--assignee" key)
          (and rig (list "--rig" rig))
          '("--status" "open,in_progress,blocked,deferred,closed"
            "--sort" "updated" "--reverse" "--limit" "50")))

(defun gascity-session--worked-args (rig)
  "Return `gc bd list' args for recent beads carrying a `work_dir', newest first.
These are the candidates for an agent's handed-off history: a polecat's
finished beads are reassigned away from it, so they no longer match its
assignee, yet each still records the `metadata.work_dir' it was built in.
Server-side `--has-metadata-key work_dir' keeps the window to beads that
could match — orders, molecules and the like carry none — leaving the path
itself to be matched client-side by `gascity-session--worked-here-p'.  RIG,
when non-nil, scopes the query to that rig's bead store."
  (append (list "bd" "list" "--has-metadata-key" "work_dir")
          (and rig (list "--rig" rig))
          '("--status" "open,in_progress,blocked,deferred,closed"
            "--sort" "updated" "--reverse" "--limit" "100")))

(defun gascity-session--worked-here-p (bead work-dir)
  "Return non-nil when BEAD was built within WORK-DIR.
WORK-DIR is the agent's own worktree; a bead it worked records a
`metadata.work_dir' equal to it or nested under it (e.g. a polecat's
`…/<agent>/worktrees/<id>').  Both are compared as directories so a sibling
agent such as `…/<agent>-2' never matches.  A nil or empty path on either
side never matches."
  (let ((bwd (alist-get 'work_dir (alist-get 'metadata bead))))
    (and (stringp work-dir) (not (string-empty-p work-dir))
         (stringp bwd) (not (string-empty-p bwd))
         (string-prefix-p (file-name-as-directory work-dir)
                          (file-name-as-directory bwd)))))

(defun gascity-session--merge-beads (lists)
  "Concatenate bead LISTS, dropping later duplicates by id.
An agent filed under two assignee keys (qualified name and runtime
session name) cannot have the same bead under both, but de-duping keeps
the merge defensive."
  (let ((seen (make-hash-table :test 'equal))
        (out nil))
    (dolist (bead (apply #'append lists) (nreverse out))
      (let ((id (alist-get 'id bead)))
        (unless (gethash id seen)
          (puthash id t seen)
          (push bead out))))))

(defun gascity-session--combined-status (results)
  "Return one load status for the bead RESULTS (a list of async plists).
`pending' if any is still loading; `error' only if every one errored;
`ready' otherwise (a single key resolving is enough to show data)."
  (cond
   ((seq-some (lambda (r) (eq (plist-get r :status) 'pending)) results) 'pending)
   ((seq-every-p (lambda (r) (eq (plist-get r :status) 'error)) results) 'error)
   (t 'ready)))

(defun gascity-session--in-progress-p (bead)
  "Return non-nil when BEAD's status is in progress."
  (equal (gascity-tabulated--str (alist-get 'status bead)) "in_progress"))

(defun gascity-session--hook-beads (beads)
  "Return the in-progress BEADS — the work on the agent's hook."
  (seq-filter #'gascity-session--in-progress-p beads))

(defun gascity-session--history-beads (beads &optional limit)
  "Return the non-in-progress BEADS, newest first, capped at LIMIT."
  (let ((rest (seq-remove #'gascity-session--in-progress-p beads)))
    (if limit (seq-take rest limit) rest)))

;;; Rendering (vnodes)

(defun gascity-session--state-vnode (agent session)
  "Return the state-block vnode for AGENT, enriched by its SESSION alist."
  (let* ((name (plist-get agent :name))
         (state (and session (gascity-tabulated--str (alist-get 'state session))))
         (running (if session (equal state "active") (plist-get agent :running)))
         (suspended (and state (equal state "suspended"))))
    (vui-vstack
     (vui-hstack :spacing 1
                 (vui-text "Agent:" :face 'gascity-header)
                 (vui-text (or name "?")
                           :face (gascity-section-state-face running suspended)))
     (vui-text (format "  state %s · provider %s · attached %s · last active %s"
                       (or state (if running "running" "stopped"))
                       (gascity-tabulated--str
                        (and session (alist-get 'provider session)))
                       (if (and session (alist-get 'attached session)) "yes" "no")
                       (gascity-tabulated--format-timestamp
                        (and session (alist-get 'last_active session))))
               :face 'gascity-dim)
     (vui-text (format "  worktree %s"
                       (gascity-tabulated--abbreviate-path
                        (or (and session (alist-get 'work_dir session))
                            (plist-get agent :work-dir))))
               :face 'gascity-dim)
     (vui-text (format "  tmux %s"
                       (gascity-tabulated--str
                        (or (and session (alist-get 'session_name session))
                            (plist-get agent :session-name))))
               :face 'gascity-dim))))

(defun gascity-session--mail-vnode (mail-res)
  "Return the mail-count vnode from async MAIL-RES."
  (vui-text
   (pcase (plist-get mail-res :status)
     ('pending "  mail …")
     ('error "  mail (unavailable)")
     (_ (let ((n (length (alist-get 'messages (plist-get mail-res :data)))))
          (format "  mail %d message%s" n (if (= n 1) "" "s")))))
   :face 'gascity-dim))

(defun gascity-session--bead-row (bead)
  "Return a one-line vnode for BEAD, stamped with its id for `RET'."
  (let ((id (gascity-tabulated--str (alist-get 'id bead))))
    (vui-text (format "  %-12s %-12s %s" id
                      (gascity-tabulated--str (alist-get 'status bead))
                      (gascity-tabulated--str (alist-get 'title bead)))
              'gascity-bead id)))

(defun gascity-session--beads-section (title beads status empty-msg)
  "Return a vnode for beads section TITLE listing BEADS at load STATUS.
STATUS is `pending', `error', or `ready'.  EMPTY-MSG is shown (dimmed)
when the load succeeded but BEADS is empty."
  (apply #'vui-vstack
         (vui-text (format "%s (%d)" title (length beads)) :face 'gascity-header)
         (pcase status
           ('pending (list (vui-text "  loading…" :face 'gascity-dim)))
           ('error   (list (vui-text "  (unavailable)" :face 'gascity-dim)))
           (_ (or (mapcar #'gascity-session--bead-row beads)
                  (list (vui-text (concat "  " empty-msg) :face 'gascity-dim)))))))

;;; Component

(vui-defcomponent gascity-session-detail-app (agent)
  "Detail view of one session/polecat AGENT (a plist)."
  :state ((refresh-tick 0))
  :render
  ;; All async hooks run unconditionally, in order, every render, so the
  ;; hook count stays stable.  Beads arrive on three reads, then merged:
  ;; one per assignee key (a polecat's runtime session name and a service
  ;; agent's qualified name — see `gascity-session--bead-args'), plus one
  ;; for beads carrying a `work_dir', kept when built within this agent's
  ;; worktree (`gascity-session--worked-here-p') — that read recovers the
  ;; finished work a polecat has handed off, which no longer matches its
  ;; assignee.  Any of KEY0/KEY1/WORK-DIR may be nil, in which case that
  ;; thunk resolves empty without spawning gc.
  (let* ((name (plist-get agent :name))
         (rig (plist-get agent :rig))
         (keys (gascity-session--assignee-keys agent))
         (key0 (nth 0 keys))
         (key1 (nth 1 keys))
         (work-dir (plist-get agent :work-dir))
         (sessions-res
          (vui-use-async (list 'sessions refresh-tick name)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            '("session" "list") resolve reject))))
         (beads0-res
          (vui-use-async (list 'beads0 refresh-tick key0 rig)
                         (lambda (resolve reject)
                           (if key0
                               (gascity-reader-read-async
                                (gascity-session--bead-args key0 rig) resolve reject)
                             (funcall resolve [])))))
         (beads1-res
          (vui-use-async (list 'beads1 refresh-tick key1 rig)
                         (lambda (resolve reject)
                           (if key1
                               (gascity-reader-read-async
                                (gascity-session--bead-args key1 rig) resolve reject)
                             (funcall resolve [])))))
         (beads2-res
          (vui-use-async (list 'beads2 refresh-tick work-dir rig)
                         (lambda (resolve reject)
                           (if (and (stringp work-dir)
                                    (not (string-empty-p work-dir)))
                               (gascity-reader-read-async
                                (gascity-session--worked-args rig) resolve reject)
                             (funcall resolve [])))))
         (mail-res
          (vui-use-async (list 'mail refresh-tick name)
                         (lambda (resolve reject)
                           (gascity-reader-read-async
                            (list "mail" "inbox" name) resolve reject))))
         (sessions (and (eq (plist-get sessions-res :status) 'ready)
                        (alist-get 'sessions (plist-get sessions-res :data))))
         (session (and sessions (gascity-session--find sessions name)))
         (beads-status (gascity-session--combined-status
                        (list beads0-res beads1-res beads2-res)))
         (agent-beads (gascity-session--merge-beads
                       (list (and (eq (plist-get beads0-res :status) 'ready)
                                  (gascity-section-beads
                                   (plist-get beads0-res :data)))
                             (and (eq (plist-get beads1-res :status) 'ready)
                                  (gascity-section-beads
                                   (plist-get beads1-res :data)))
                             (and (eq (plist-get beads2-res :status) 'ready)
                                  (seq-filter
                                   (lambda (b)
                                     (gascity-session--worked-here-p b work-dir))
                                   (gascity-section-beads
                                    (plist-get beads2-res :data)))))))
         (hook (gascity-session--hook-beads agent-beads))
         (history (gascity-session--history-beads agent-beads 10)))
    (vui-vstack
     :spacing 1
     (gascity-session--state-vnode agent session)
     (gascity-session--mail-vnode mail-res)
     (gascity-session--beads-section "On hook" hook beads-status
                                     "idle — no work on hook")
     (gascity-session--beads-section "Recent history" history beads-status
                                     "no recent beads")
     (vui-text (concat "g refresh · RET open bead · p peek · N nudge · D drain · "
                       "d dired · t tmux · q bury")
               :face 'gascity-dim))))

;;; Commands

(defun gascity-session-detail-activate ()
  "Open the bead at point in beads.el, else press a widget at point."
  (interactive)
  (cond
   ((gascity-bead-at-point) (gascity-bead-visit))
   ((widget-at (point)) (widget-button-press (point)))
   (t (user-error "Move to a bead to open it"))))

(defun gascity-polecat-detail-refresh ()
  "Reload the session/polecat detail view, preserving point."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No session detail to refresh here")))

;;;###autoload
(defun gascity-polecat-detail (agent)
  "Show the detail view for AGENT, a plist with at least a `:name'.
AGENT is the action plist carried by a session-list row, a status
dashboard agent row, or a rig dashboard agent row."
  (let* ((name (or (plist-get agent :name) (user-error "Agent has no name")))
         (buffer-name (gascity-session-detail--buffer-name name))
         (buf (get-buffer-create buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-session-detail-mode)
        (gascity-session-detail-mode)))
    (unless (gascity-section-refresh-instance buf)
      ;; vui-mount switch-to-buffers internally; contain that so the buffer is
      ;; displayed once, via pop-to-buffer, on both the cold and refresh paths.
      (save-window-excursion
        (vui-mount (vui-component 'gascity-session-detail-app :agent agent)
                   buffer-name)))
    ;; Record the subject so the agent actions resolve it anywhere in the
    ;; buffer (set after mount so it survives the cold-mount render).
    (with-current-buffer buf
      (setq-local gascity-section--agent agent))
    (pop-to-buffer buf)))

;;;###autoload
(defun gascity-polecat-detail-at-point ()
  "Open the detail view for the session/agent at point."
  (interactive)
  (let ((agent (gascity-agent-at-point)))
    (unless agent (user-error "No session/agent at point"))
    (gascity-polecat-detail agent)))

;;; Mode

(defvar-keymap gascity-session-detail-mode-map
  :doc "Keymap for `gascity-session-detail-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-polecat-detail-refresh
  "RET" #'gascity-session-detail-activate
  "p"   #'gascity-session-peek-at-point
  "N"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point)

(define-derived-mode gascity-session-detail-mode gascity-section-mode "GC-Agent"
  "Major mode for the gascity session/polecat detail view.

\\{gascity-session-detail-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              (concat " Agent detail  (g refresh · RET open bead · p peek"
                      " · N nudge · D drain · d dired · t tmux · q bury)")))

(provide 'gascity-session)
;;; gascity-session.el ends here
