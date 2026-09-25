;;; gascity-session.el --- vui session/polecat detail -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The agent detail (dashboard-v3 §7.4), `i' on an agent anywhere: one
;; agent in a vui buffer, `*gascity-agent: NAME*'.
;;
;;   header      glyph, name, state and last activity; the session id and
;;               tmux name, pool template and provider, worktree, created
;;   Work        the bead on the hook (⬣, with its run) and the agent's
;;               other open beads
;;   Run         the hooked bead's run: ladder, active step, progress
;;   Transcript  the last ten entries of `gc session logs --json --tail 10'
;;   Mail        the operator's mail from or to this agent
;;   History     the agent's recently closed beads
;;
;; Beads are gathered by assignee (the runtime session name and the
;; qualified name) and by worktree (`metadata.work_dir' — a polecat's
;; finished work is reassigned away from it), then merged.
;;
;; Every read goes through the store (`gascity-store-use'): deduplicated,
;; capped per host, bounded by its deadline, stale-while-revalidate.  `f'
;; follows the log (`gc session logs -f', raw text, in
;; `*gascity-log: TARGET*'; over TRAMP a local no-pty ssh pipe, §8.3 R4);
;; `v' peeks; the §5.3 agent keys act on the buffer's agent anywhere.

;;; Code:

(require 'seq)
(require 'wid-edit)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-context)            ; pin-directory (view keyed to its city)
(require 'gascity-domain)             ; typed agent (the detail view's subject)
(require 'gascity-reader)
(require 'gascity-store)              ; gascity-store-use (per-section loads)
(require 'gascity-section)
(require 'gascity-tabulated)         ; shared cell formatters
(require 'gascity-remote)
(require 'gascity-dashboard)          ; ladder, noise, header helpers
(require 'gascity-ui)                ; relative times

;; Openers and agent actions live in sibling modules
;; loaded alongside this one; reference them by name.
(declare-function gascity-dired-at-point "gascity-section")
(declare-function gascity-tmux-at-point "gascity-section")
(declare-function gascity-bead-visit "gascity-section")
(declare-function gascity-run-show "gascity-run")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")
;; Write verbs (DESIGN-write-actions.md phase 1/2) bound in the keymap:
;; reset/undrain this agent, the bead-dispatch (`c') and sling (`S')
;; menus on the hook/history bead reference at point.
(declare-function gascity-session-reset-at-point "gascity-action")
(declare-function gascity-session-undrain-at-point "gascity-action")
(declare-function gascity-bead-dispatch "gascity-action")
(declare-function gascity-sling-dispatch "gascity-action")

;;; Buffer

(defun gascity-session-detail--buffer-name (name)
  "Return the base detail buffer name for agent NAME.
The `view-buffer' factory (`gascity-view-get-buffer-create') qualifies it
with the host for a remote city, so a local and a remote agent detail
of the same name coexist."
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
AGENT is a `gascity-agent'.  A polecat's beads are assigned to its runtime
session name (`session-name'); a service agent's to its qualified name
\(`name').  Both are tried so the lookup works for either."
  (seq-uniq (seq-remove #'string-empty-p
                        (delq nil (list (gascity-agent-name agent)
                                        (gascity-agent-session-name agent))))))

(defun gascity-session--bead-args (key rig)
  "Return `gc bd list' args for the beads assigned to KEY, newest first.
Server-side `--assignee' (an exact match) is used rather than fetching a
broad window and filtering client-side: an agent's own beads are easily
buried under a town's many recently-closed order/molecule beads.  RIG,
when non-nil, scopes the query to that rig's bead store."
  (append (list "bd" "list" "--assignee" key)
          (and rig (list "--rig" rig))
          '("--status" "open,in_progress,blocked,deferred,closed"
            "--sort" "updated" "--reverse" "-n" "0")))

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
            "--sort" "updated" "--reverse" "-n" "0")))

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

;;; Reads — one named argv each, read through the store

(defun gascity-session--sessions-args ()
  "Return the `gc session list' argv of the agent detail."
  '("session" "list"))

(defun gascity-session--graph-args (root rig)
  "Return the argv reading every bead of run ROOT in store RIG."
  (append (list "bd" "list" "--all" "-n" "0" "--brief"
                "--metadata-field" (concat "gc.root_bead_id=" root))
          (and rig (list "--rig" rig))))

(defun gascity-session--logs-args (target)
  "Return the argv of session TARGET's last ten transcript entries."
  (list "session" "logs" target "--tail" "10"))

(defun gascity-session--mail-args ()
  "Return the argv of the operator's inbox (filtered to the agent)."
  '("mail" "inbox"))

;;; Data shaping (pure)

(defun gascity-session--target (agent session)
  "Return the session target of AGENT: its SESSION id, else its name."
  (or (and session (alist-get 'id session)) (gascity-agent-name agent)))

(defun gascity-session--graph-formula (graph)
  "Return the formula name of a run GRAPH (its beads' `gc.step_ref's).
The `workflow-finalize' node is `<formula>.workflow-finalize'; failing
that, the most common first segment of the two-segment step refs."
  (let ((refs (delq nil (mapcar (lambda (b) (alist-get 'gc.step_ref
                                                       (gascity-dashboard--meta b)))
                                graph))))
    (or (seq-some (lambda (r) (and (string-suffix-p ".workflow-finalize" r)
                                   (string-remove-suffix ".workflow-finalize" r)))
                  refs)
        (let ((counts (make-hash-table :test 'equal)) best)
          (dolist (r refs)
            (when (string-match "\\`\\([^.]+\\)\\.[^.]+\\'" r)
              (cl-incf (gethash (match-string 1 r) counts 0))))
          (maphash (lambda (k v) (when (or (null best) (> v (cdr best)))
                                   (setq best (cons k v))))
                   counts)
          (car best)))))

(defun gascity-session--entry-summary (entry)
  "Return (ROLE . SUMMARY) of a `gc session logs' transcript ENTRY."
  (let* ((type (alist-get 'type entry))
         (blocks (append (alist-get 'blocks entry) nil))
         (text (gascity-ui-first-line (alist-get 'text entry)))
         (block-text (seq-some (lambda (b) (and (equal (alist-get 'type b) "text")
                                                (gascity-ui-first-line
                                                 (alist-get 'text b))))
                               blocks))
         (tool (seq-find (lambda (b) (equal (alist-get 'type b) "tool_use")) blocks)))
    (cons (pcase type ("tool_result" "tool") ((pred stringp) type) (_ "?"))
          (or text block-text
              (and tool
                   (let ((input (alist-get 'input tool)))
                     (format "%s: %s" (or (alist-get 'name tool) "tool")
                             (or (and (listp input) (alist-get 'command input))
                                 (gascity-ui-first-line (format "%s" input))
                                 ""))))
              (and (equal type "tool_result") "result")
              (and (seq-find (lambda (b) (equal (alist-get 'type b) "thinking")) blocks)
                   "thinking…")
              ""))))

(defun gascity-session--operator-mail (inbox agent)
  "Return the INBOX messages from or to AGENT (a `gascity-agent'), newest first."
  (let* ((name (gascity-agent-name agent))
         (short (gascity-dashboard--short-agent name))
         (mine (lambda (who) (and (stringp who)
                                  (let ((w (string-remove-suffix "/" who)))
                                    (or (equal w name) (equal w short)
                                        (equal (gascity-dashboard--short-agent w)
                                               short)))))))
    (sort (seq-filter (lambda (m) (or (funcall mine (alist-get 'from m))
                                      (funcall mine (alist-get 'to m))))
                      (append (alist-get 'messages inbox) nil))
          (lambda (a b) (string> (or (alist-get 'created_at a) "")
                                 (or (alist-get 'created_at b) ""))))))

;;; Rendering (vnodes)

(defun gascity-session--header-vnode (agent session)
  "Return the §7.4 header of AGENT enriched by its live SESSION alist."
  (let* ((name (or (gascity-agent-name agent) "?"))
         (state (if session (or (alist-get 'state session) "active")
                  (if (gascity-agent-running agent) "running" "stopped")))
         (live (and session (equal state "active")))
         (active (and session (alist-get 'last_active session)))
         (row (lambda (label value &optional right)
                (and value (not (string-empty-p value))
                     (vui-text (gascity-ui-right-align
                                (concat "  " (propertize (gascity-ui-fit label 8)
                                                         'face 'gascity-dim)
                                        " " value)
                                (or right "") 78))))))
    (apply #'vui-vstack
           (delq nil
                 (list
                  (vui-text (gascity-ui-right-align
                             (concat (gascity-ui-glyph (if live 'ok 'idle)) " "
                                     (propertize name 'face 'gascity-header))
                             (propertize (concat state
                                                 (if active
                                                     (concat " · last active "
                                                             (gascity-ui-time active))
                                                   ""))
                                         'face 'gascity-dim)
                             78)
                            'gascity-section t)
                  (funcall row "session"
                           (and session (format "%s  %s" (or (alist-get 'id session) "")
                                                (or (alist-get 'session_name session) "")))
                           (and (gascity-agent-socket agent)
                                (propertize (concat "tmux " (gascity-agent-socket agent))
                                            'face 'gascity-dim)))
                  (funcall row "pool"
                           (and session (alist-get 'template session))
                           (and session (alist-get 'provider session)
                                (propertize (concat "provider "
                                                    (alist-get 'provider session))
                                            'face 'gascity-dim)))
                  (funcall row "workdir"
                           (gascity-ui-path (or (and session (alist-get 'work_dir session))
                                                (gascity-agent-work-dir agent)))
                           (and session (alist-get 'created_at session)
                                (propertize (concat "created "
                                                    (gascity-ui-ago
                                                     (alist-get 'created_at session)))
                                            'face 'gascity-dim))))))))

;; Kept for the section-header tests: the old state block is the header.
(defalias 'gascity-session--state-vnode #'gascity-session--header-vnode)

(defun gascity-session--bead-row (bead &optional glyph)
  "Return a row for BEAD (GLYPH first), stamped with its id for `RET'."
  (let ((id (gascity-tabulated--str (alist-get 'id bead)))
        (root (gascity-dashboard--root-of bead)))
    (vui-text (concat "  " (or glyph (gascity-ui-glyph 'pending)) " "
                      (gascity-ui-fit id 10) " "
                      (gascity-ui-fit (gascity-tabulated--str (alist-get 'title bead)) 34)
                      " " (gascity-ui-fit (gascity-tabulated--str (alist-get 'status bead)) 12)
                      (if root (propertize (concat " run " root) 'face 'gascity-dim) "")
                      " " (gascity-ui-time (alist-get 'updated_at bead)))
              'gascity-bead id)))

(defun gascity-session--beads-section (title beads status empty-msg)
  "Return the section TITLE listing BEADS at load STATUS.
STATUS is `pending', `error' or `ready'; EMPTY-MSG is kept for callers
of the old signature (an empty section reads `none', §6.1)."
  (ignore empty-msg)
  (gascity-ui-section
   (downcase title) title
   (pcase status
     ('pending (list :state 'pending))
     ('error (list :state 'error :error "bd list failed"))
     (_ (list :state 'ready :data beads)))
   nil
   (lambda (rows) (mapcar #'gascity-session--bead-row rows))))

(defun gascity-session--work-vnode (hook others status)
  "Return the Work section: HOOK beads (⬣) then the OTHERS assigned."
  (gascity-ui-section
   "work" "Work"
   (pcase status
     ('pending (list :state 'pending))
     ('error (list :state 'error :error "bd list failed"))
     (_ (list :state 'ready :data (append hook others))))
   nil
   (lambda (_)
     (append (mapcar (lambda (b) (gascity-session--bead-row b (gascity-ui-glyph 'active)))
                     hook)
             (mapcar #'gascity-session--bead-row others)))))

(defun gascity-session--run-vnode (root rig graph-load)
  "Return the Run section of run ROOT in RIG from GRAPH-LOAD, or nil."
  (when root
    (gascity-ui-section
     "run" "Run" graph-load nil
     (lambda (graph)
       (let* ((graph (gascity-section-beads graph))
              (formula (gascity-session--graph-formula graph))
              (ladder (gascity-dashboard--ladder
                       `((metadata . ((gc.formula_name . ,formula)))) graph))
              (label (gascity-dashboard--ladder-label ladder)))
         (list (vui-text (gascity-ui-right-align
                          (concat "  " (gascity-ui-glyph 'active) " "
                                  (gascity-ui-fit root 10) " "
                                  (gascity-ui-fit (or formula "") 14) " "
                                  (gascity-dashboard--ladder-string ladder) "  "
                                  (gascity-ui-fit (car label) 16) " " (cdr label))
                          (propertize "RET" 'face 'gascity-dim) 78)
                         'gascity-bead root
                         'gascity-run-rig (or rig "")))))
     (lambda (graph) (if (gascity-section-beads graph) 1 0)))))

(defun gascity-session--transcript-vnode (load)
  "Return the Transcript section from the `gc session logs' LOAD."
  (progn
    (gascity-ui-section
     "transcript" "Transcript" load nil
     (lambda (data)
       (mapcar (lambda (entry)
                 (let ((s (gascity-session--entry-summary entry)))
                   (vui-text (concat "  " (gascity-ui-clock (alist-get 'timestamp entry))
                                     "  " (gascity-ui-fit (car s) 10) " "
                                     (gascity-ui-truncate (cdr s) 56)))))
               (reverse (append (alist-get 'entries data) nil))))
     (lambda (data) (and (alist-get 'entries data)
                         (format "last %d · f follow  v peek"
                                 (length (alist-get 'entries data))))))))

(defun gascity-session--mail-vnode (load agent)
  "Return the Mail section: the operator's mail from or to AGENT, from LOAD."
  (gascity-ui-section
   "mail" "Mail with operator"
   (if (memq (plist-get load :state) '(ready stale))
       (plist-put (copy-sequence load) :data
                  (gascity-session--operator-mail (plist-get load :data) agent))
     load)
   nil
   (lambda (messages)
     (mapcar (lambda (m)
               (vui-text (concat "  " (if (alist-get 'read m) " "
                                        (gascity-ui-glyph 'watch))
                                 " " (gascity-ui-fit (gascity-ui-time
                                                      (alist-get 'created_at m))
                                                     5)
                                 " " (gascity-ui-fit (or (alist-get 'subject m) "") 40)
                                 (propertize (concat " from " (or (alist-get 'from m) "?"))
                                             'face 'gascity-dim))))
             (seq-take messages 5)))))

;;; Component

(vui-defcomponent gascity-session-detail-app (agent)
  "The agent detail of AGENT (a `gascity-agent'), dashboard-v3 §7.4.
Every read goes through the store (`gascity-store-use'): deduplicated,
capped per host, bounded by its deadline, stale-while-revalidate."
  :state ((refresh-tick 0))
  :render
  ;; All store hooks run unconditionally, in order, every render.
  (let* ((name (gascity-agent-name agent))
         (rig (gascity-agent-rig agent))
         (keys (gascity-session--assignee-keys agent))
         (key0 (nth 0 keys))
         (key1 (nth 1 keys))
         (work-dir (gascity-agent-work-dir agent))
         (sessions (gascity-ui-store-load
                    (gascity-store-use (gascity-session--sessions-args)
                                       :tick refresh-tick)))
         (session (gascity-session--find
                   (alist-get 'sessions (plist-get sessions :data)) name))
         (target (gascity-session--target agent session))
         (beads0-res (gascity-store-use (and key0 (gascity-session--bead-args key0 rig))
                                        :tick refresh-tick :default []))
         (beads1-res (gascity-store-use (and key1 (gascity-session--bead-args key1 rig))
                                        :tick refresh-tick :default []))
         (beads2-res (gascity-store-use (and (stringp work-dir)
                                             (not (string-empty-p work-dir))
                                             (gascity-session--worked-args rig))
                                        :tick refresh-tick :default []))
         (beads-status (gascity-session--combined-status
                        (list beads0-res beads1-res beads2-res)))
         (agent-beads (gascity-session--merge-beads
                       (list (and (eq (plist-get beads0-res :status) 'ready)
                                  (gascity-section-beads (plist-get beads0-res :data)))
                             (and (eq (plist-get beads1-res :status) 'ready)
                                  (gascity-section-beads (plist-get beads1-res :data)))
                             (and (eq (plist-get beads2-res :status) 'ready)
                                  (seq-filter
                                   (lambda (b) (gascity-session--worked-here-p b work-dir))
                                   (gascity-section-beads
                                    (plist-get beads2-res :data)))))))
         (hook (gascity-session--hook-beads agent-beads))
         (others (seq-filter (lambda (b) (member (alist-get 'status b)
                                                 '("open" "blocked" "deferred")))
                             agent-beads))
         (history (seq-take (seq-filter (lambda (b) (equal (alist-get 'status b) "closed"))
                                        agent-beads)
                            5))
         (root (seq-some #'gascity-dashboard--root-of hook))
         (graph (gascity-ui-store-load
                 (gascity-store-use (and root (gascity-session--graph-args root rig))
                                    :tick refresh-tick)))
         (logs (gascity-ui-store-load
                (gascity-store-use (gascity-session--logs-args target)
                                   :tick refresh-tick)))
         (mail (gascity-ui-store-load
                (gascity-store-use (gascity-session--mail-args) :tick refresh-tick))))
    (apply #'vui-vstack
           :spacing 1
           (delq nil
                 (list
                  (gascity-session--header-vnode agent session)
                  (gascity-session--work-vnode hook others beads-status)
                  (gascity-session--run-vnode root rig graph)
                  (gascity-session--transcript-vnode logs)
                  (gascity-session--mail-vnode mail agent)
                  (gascity-session--beads-section "History" history beads-status
                                                  "no recent beads"))))))

;;; Commands

(defun gascity-session-detail-activate ()
  "Act on the thing at point: a run opens run detail, a bead beads.el.
Anywhere else RET attaches the agent's terminal (§5.3)."
  (interactive)
  (let ((run-rig (get-text-property (point) 'gascity-run-rig))
        (bead (gascity-bead-at-point)))
    (cond
     (run-rig (gascity-run-show bead nil (and (not (string-empty-p run-rig)) run-rig)))
     (bead (gascity-bead-visit))
     ((widget-at (point)) (widget-button-press (point)))
     (gascity-section--agent (gascity-agent-attach-tmux gascity-section--agent))
     (t (user-error "Nothing to act on here")))))

(defun gascity-polecat-detail-refresh ()
  "Reload the agent detail, preserving point."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No agent detail to refresh here")))

;;;###autoload
(defun gascity-polecat-detail (agent)
  "Show the detail view for AGENT, a `gascity-agent' with at least a name.
AGENT is the action object carried by an agent row in any view."
  (let* ((name (or (gascity-agent-name agent) (user-error "Agent has no name")))
         (buf (gascity-view-get-buffer-create
               (gascity-session-detail--buffer-name name))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-session-detail-mode)
        (gascity-session-detail-mode))
      ;; Set before the mount: the header line and the keys read it.
      (setq-local gascity-section--agent agent))
    (unless (gascity-section-refresh-instance buf)
      ;; vui-mount switch-to-buffers internally; display once, below.
      (save-window-excursion
        (vui-mount (vui-component 'gascity-session-detail-app :agent agent)
                   (buffer-name buf))))
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

;;; Log follow (`f', §7.4, §8.3 R4)

(defvar-local gascity-session--log-process nil
  "The `gc session logs -f' follower feeding this log buffer.")

(define-derived-mode gascity-log-mode special-mode "GC-Log"
  "Major mode for a followed agent log (`gc session logs -f', raw text).
`q' kills the buffer and its follower."
  :group 'gascity
  (setq truncate-lines nil)
  (add-hook 'kill-buffer-hook #'gascity-session--log-teardown nil t))

(keymap-set gascity-log-mode-map "q" #'kill-current-buffer)

(defun gascity-session--log-teardown ()
  "Stop this buffer's log follower."
  (when (process-live-p gascity-session--log-process)
    (delete-process gascity-session--log-process)))

(defun gascity-session--log-argv (target dir)
  "Return the local argv following TARGET's log from a view in DIR.
Locally gc itself; for a remote DIR a no-pty ssh pipe under the host
watcher (`gascity-remote-ssh-stream-argv', §8.3 R4): no TRAMP channel,
no round trip, and killing the local process stops gc on the host.
`--city' and the env-city overrides as for any read."
  (let* ((default-directory dir)
         (sub (list "session" "logs" target "-f"))
         (city-env (gascity-reader--city-env-overrides sub))
         (args (if city-env sub (append (gascity-reader--city-args) sub)))
         (executable (with-connection-local-variables gascity-executable)))
    (cond ((gascity-reader--ssh-pipe-p dir)
           ;; The host watcher stops gc when `q' kills the local ssh.
           (gascity-remote-ssh-stream-argv dir executable args
                                           :cd t :env city-env))
          ((file-remote-p dir)
           (user-error "Log follow needs an ssh-based remote city"))
          (t (cons executable args)))))

(defun gascity-session--log-filter (proc chunk)
  "Append CHUNK from PROC to its log buffer, following the end."
  (let ((buf (process-buffer proc)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let* ((inhibit-read-only t)
               (windows (seq-filter (lambda (w) (= (window-point w) (point-max)))
                                    (get-buffer-window-list buf nil t)))
               (at-end (= (point) (point-max))))
          (save-excursion
            (goto-char (point-max))
            (insert (string-replace "\r" "" chunk)))
          (when at-end (goto-char (point-max)))
          (dolist (w windows) (set-window-point w (point-max))))))))

(defun gascity-session--log-sentinel (proc event)
  "Note in PROC's buffer that the follower ended with EVENT."
  (let ((buf (process-buffer proc)))
    (when (and (buffer-live-p buf) (memq (process-status proc) '(exit signal)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (save-excursion
            (goto-char (point-max))
            (insert (propertize (format "\n[follow ended: %s]\n" (string-trim event))
                                'face 'gascity-dim))))))))

(defun gascity-session-follow-log ()
  "Follow the log of this buffer's agent in `*gascity-log: TARGET*' (`f').
Runs `gc session logs -f' (raw text: gc has no JSON mode for -f); over
TRAMP as a local ssh pipe.  `q' in the log buffer stops it."
  (interactive)
  (let* ((agent (or (gascity-agent-at-point) (user-error "No agent here")))
         (target (or (gascity-agent-session-name agent) (gascity-agent-name agent)))
         (dir default-directory)
         (argv (gascity-session--log-argv target dir))
         (buf (gascity-view-get-buffer-create (format "*gascity-log: %s*" target))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-log-mode) (gascity-log-mode))
      (unless (process-live-p gascity-session--log-process)
        (let ((inhibit-read-only t)) (erase-buffer))
        (setq gascity-session--log-process
              ;; A local process always: remote cities go through ssh.
              (let ((default-directory (if (file-remote-p dir) "~/" dir)))
                (make-process :name (format "gascity-log %s" target)
                              :buffer buf
                              :command argv
                              :connection-type 'pipe
                              :noquery t
                              :stderr (get-buffer-create
                                       (format " *gascity-log-stderr: %s*" target))
                              :filter #'gascity-session--log-filter
                              :sentinel #'gascity-session--log-sentinel)))))
    (pop-to-buffer buf)))

;;; Mode

(defvar-keymap gascity-session-detail-mode-map
  :doc "Keymap for `gascity-session-detail-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-polecat-detail-refresh
  "RET" #'gascity-session-detail-activate
  "f"   #'gascity-session-follow-log
  "v"   #'gascity-session-peek-at-point
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  "R"   #'gascity-session-reset-at-point
  "U"   #'gascity-session-undrain-at-point
  "c"   #'gascity-bead-dispatch
  "S"   #'gascity-sling-dispatch)

(define-derived-mode gascity-session-detail-mode gascity-section-mode "GC-Agent"
  "Major mode for the agent detail (dashboard-v3 §7.4).

\\{gascity-session-detail-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              '(:eval (concat " " (propertize
                                   (or (and gascity-section--agent
                                            (gascity-agent-name gascity-section--agent))
                                       "Agent")
                                   'face 'gascity-header)
                              (propertize "   f follow  v peek  ? help  j jump  g refresh"
                                          'face 'gascity-dim)))))

(provide 'gascity-session)
;;; gascity-session.el ends here
