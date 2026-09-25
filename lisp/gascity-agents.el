;;; gascity-agents.el --- The Agents view: table and tree -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The Agents view (dashboard-v3 §7.3), `j a' from every view:
;;
;; - `gascity-agents': a tabulated list of every agent of the city —
;;   `gc status''s configured agents joined to their live sessions, plus
;;   the named sessions (the mayor) — with state, last activity, the
;;   bead on the hook and the provider.  Stalled agents (■) are pinned
;;   first.  `/' filters by state (running by default; stalled rows are
;;   always shown), rig, provider and a search string.
;; - `T' switches to the tree (`gascity-agents-tree'): city → rigs →
;;   pools → agents, built from the gascity-status.el components, and
;;   `T' there switches back.
;;
;; Reads (one named loader each, through the store — shared with the
;; cockpit, capped per host, bounded by its deadline): `gc status', `gc
;; session list', `gc agent list' (providers and pool bounds) and the
;; cockpit's work read (the hooked bead).  A refresh keeps the previous
;; rows while its reads are in flight and keeps the last good payload of
;; any read that fails.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)
(require 'transient)
(require 'vui)
(require 'beads-prefix)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-context)
(require 'gascity-domain)
(require 'gascity-store)
(require 'gascity-section)
(require 'gascity-tabulated)
(require 'gascity-status)
(require 'gascity-dashboard)

(declare-function gascity-polecat-detail-at-point "gascity-session")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-session-reset-at-point "gascity-action")
(declare-function gascity-session-undrain-at-point "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")

(defconst gascity-agents-buffer-name "*gascity-agents: %s*"
  "Format of the Agents table's base buffer name; %s is the city.")

(defconst gascity-agents-tree-buffer-name "*gascity-agents-tree: %s*"
  "Format of the Agents tree's base buffer name; %s is the city.")

;;; Reads

(defvar gascity-agents--force nil
  "Non-nil while an explicit `g' refresh reads past the store's TTL.")

(defun gascity-agents--read-status (resolve reject)
  "Read `gc status' for the Agents view; RESOLVE or REJECT."
  (gascity-store-fetch '("status") resolve reject :force gascity-agents--force))

(defun gascity-agents--read-sessions (resolve reject)
  "Read `gc session list' for the Agents view."
  (gascity-store-fetch '("session" "list") resolve reject
                       :force gascity-agents--force))

(defun gascity-agents--read-agents (resolve reject)
  "Read `gc agent list' (providers, pool bounds) for the Agents view."
  (gascity-store-fetch '("agent" "list") resolve reject
                       :force gascity-agents--force))

(defun gascity-agents--read-work (resolve reject)
  "Read the work beads (for each agent's hooked bead), as the cockpit does."
  (gascity-store-fetch '("bd" "list" :work-stores) resolve reject
                       :loader #'gascity-dashboard--read-work
                       :force gascity-agents--force))

(defconst gascity-agents--loaders
  '((:status . gascity-agents--read-status)
    (:sessions . gascity-agents--read-sessions)
    (:agents . gascity-agents--read-agents)
    (:work . gascity-agents--read-work))
  "The Agents view's reads: payload key → loader.")

;;; Model (pure)

(defun gascity-agents--providers (agent-list)
  "Return a hash: qualified agent/template name → provider, from AGENT-LIST."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (a (append (alist-get 'agents agent-list) nil))
      (when (and (alist-get 'qualified_name a) (alist-get 'provider a))
        (puthash (alist-get 'qualified_name a) (alist-get 'provider a) table)))
    table))

(defun gascity-agents--provider (agent providers)
  "Return AGENT's provider: its session's, else its template's in PROVIDERS."
  (or (plist-get agent :provider)
      (gethash (plist-get agent :name) providers)
      ;; A numbered pool member takes its template's provider.
      (let ((name (plist-get agent :name)))
        (and (stringp name) (string-match "\\`\\(.+\\)-[0-9]+\\'" name)
             (gethash (match-string 1 name) providers)))))

(defun gascity-agents--rows (data now)
  "Return the agent plists of the payloads DATA at NOW, stalled first.
DATA is a plist (:status :sessions :agents :work) of payloads (any may
be nil).  Each plist also carries :provider filled from `gc agent
list' when the agent has no session."
  (let* ((status (plist-get data :status))
         (sessions (append (alist-get 'sessions (plist-get data :sessions)) nil))
         (beads (plist-get (plist-get data :work) :beads))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status) 'no-probe))
         (providers (gascity-agents--providers (plist-get data :agents)))
         (rows (gascity-dashboard--agents status sessions beads socket now)))
    (sort (mapcar (lambda (a)
                    (plist-put (copy-sequence a) :provider
                               (gascity-agents--provider a providers)))
                  rows)
          #'gascity-dashboard--agent-order)))

(defun gascity-agents--match-p (agent filter)
  "Return non-nil when AGENT passes FILTER (a plist, §7.3).
:state `running' keeps running, idle and stalled agents; `all' or nil
keeps every one; any other value that state.  Stalled agents always
pass the state filter.  :rig, :provider and :search (a case-insensitive
substring of the name) narrow further."
  (let ((state (plist-get filter :state))
        (rig (plist-get filter :rig))
        (provider (plist-get filter :provider))
        (search (plist-get filter :search))
        (s (plist-get agent :state)))
    (and (or (null state) (equal state "all") (eq s 'stalled)
             (if (equal state "running")
                 (memq s '(running idle stalled))
               (equal state (symbol-name s))))
         (or (null rig)
             (equal rig (or (plist-get agent :rig) "city")))
         (or (null provider) (equal provider (plist-get agent :provider)))
         (or (null search)
             (let ((case-fold-search t))
               (string-match-p (regexp-quote search) (plist-get agent :name)))))))

(defun gascity-agents--state-label (agent)
  "Return AGENT's state column: active, idle, stopped, stalled, suspended."
  (pcase (plist-get agent :state)
    ('running "active")
    (s (symbol-name s))))

(defun gascity-agents--entry (agent now)
  "Return the tabulated entry of AGENT at NOW; its id is the action object."
  (let* ((state (plist-get agent :state))
         (name (plist-get agent :name))
         (rig (plist-get agent :rig))
         (short (if (and rig (string-prefix-p (concat rig "/") name))
                    (substring name (1+ (length rig)))
                  name)))
    (list (plist-get agent :object)
          (vector (gascity-ui-glyph (pcase state ('stalled 'fail)
                                      ('running 'ok) (_ 'idle)))
                  (propertize short 'face (if (eq state 'stalled)
                                              'gascity-failed
                                            'default))
                  (or rig "—")
                  (gascity-agents--state-label agent)
                  (let ((ts (plist-get agent :active)))
                    (if ts (gascity-ui-time ts now) "—"))
                  (or (plist-get agent :bead) "")
                  (or (plist-get agent :provider) "")))))

(defun gascity-agents--summary (rows)
  "Return `3 running · 1 idle · 3 stopped' for agent ROWS."
  (let ((count (lambda (states) (seq-count (lambda (a) (memq (plist-get a :state) states))
                                           rows))))
    (string-join
     (delq nil (list (let ((n (funcall count '(stalled)))) (and (> n 0) (format "%d stalled" n)))
                     (let ((n (funcall count '(running)))) (and (> n 0) (format "%d running" n)))
                     (let ((n (funcall count '(idle)))) (and (> n 0) (format "%d idle" n)))
                     (let ((n (funcall count '(stopped suspended))))
                       (and (> n 0) (format "%d stopped" n)))))
     " · ")))

;;; Table

(defvar-local gascity-agents--filter '(:state "running")
  "The Agents table's filter plist (§7.3); state defaults to running.")

(defvar-local gascity-agents--data nil
  "Last good payload of each read: a plist keyed like `gascity-agents--loaders'.")

(defvar-local gascity-agents--errors nil
  "Errors of the reads of the last refresh: a plist keyed like the data.")

(defvar-local gascity-agents--generation 0
  "Refresh counter; a read of an older refresh is ignored.")

(defun gascity-agents--render ()
  "Rebuild the table from `gascity-agents--data' (no gc call)."
  (let* ((now (float-time))
         (rows (gascity-agents--rows gascity-agents--data now))
         (shown (seq-filter (lambda (a) (gascity-agents--match-p a gascity-agents--filter))
                            rows))
         (errors (delq nil (cl-loop for (_k v) on gascity-agents--errors by #'cddr
                                    collect v))))
    (setq gascity-tabulated--filter-description
          (gascity-tabulated--format-filter gascity-agents--filter))
    (gascity-tabulated--init-paged
     (concat "Agents  " (gascity-agents--summary rows)
             (if errors (gascity-ui-partial-mark (string-join errors "\n")) ""))
     (mapcar (lambda (a) (gascity-agents--entry a now)) shown))))

(defun gascity-agents-refresh (&optional cached)
  "Re-read the Agents table's payloads; the old rows stay until they land.
With CACHED (opening the view), fresh store entries answer at once."
  (interactive)
  (let ((gen (cl-incf gascity-agents--generation))
        (buf (current-buffer))
        (gascity-agents--force (not cached)))
    (setq gascity-agents--errors nil)
    (gascity-tabulated--set-loading)
    (pcase-dolist (`(,key . ,loader) gascity-agents--loaders)
      (funcall
       loader
       (lambda (data)
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (when (= gen gascity-agents--generation)
               (setq gascity-agents--data (plist-put gascity-agents--data key data))
               (gascity-agents--render)))))
       (lambda (err)
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (when (= gen gascity-agents--generation)
               (setq gascity-agents--errors
                     (plist-put gascity-agents--errors key
                                (format "gc %s: %s" (substring (symbol-name key) 1)
                                        (or (gascity-ui-first-line (format "%s" err))
                                            "failed"))))
               (gascity-agents--render)))))))))

(gascity-filter-define-choice gascity-agents-filter-state
  :state "state" '("running" "idle" "stopped" "stalled" "suspended" "all") "all")
(gascity-filter-define-choice gascity-agents-filter-rig
  :rig "rig" (cons "city" (mapcar #'gascity-rig-name
                                  (seq-remove #'gascity-rig-hq (gascity-rigs-cached)))))
(gascity-filter-define-choice gascity-agents-filter-provider
  :provider "provider"
  (delete-dups (delq nil (mapcar (lambda (a) (plist-get a :provider))
                                 (gascity-agents--rows gascity-agents--data
                                                       (float-time))))))
(gascity-filter-define-choice gascity-agents-filter-search
  :search "search" nil "")

(beads-define-prefix gascity-agents-filter ()
  "Filter the Agents table; each change applies at once (§7.3, §5.5)."
  ["Filter agents"
   ("-s" gascity-agents-filter-state)
   ("-r" gascity-agents-filter-rig)
   ("-p" gascity-agents-filter-provider)
   ("-q" gascity-agents-filter-search)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

(defvar-keymap gascity-agents-mode-map
  :doc "Keymap for `gascity-agents-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-agents-refresh
  "/"   #'gascity-agents-filter
  "T"   #'gascity-agents-tree
  "RET" #'gascity-tmux-at-point
  "t"   #'gascity-tmux-at-point
  "i"   #'gascity-polecat-detail-at-point
  "d"   #'gascity-dired-at-point
  "v"   #'gascity-session-peek-at-point
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "R"   #'gascity-session-reset-at-point
  "U"   #'gascity-session-undrain-at-point
  "n"   #'next-line
  "p"   #'previous-line)

(define-derived-mode gascity-agents-mode tabulated-list-mode "GC-Agents"
  "Major mode for the Agents table (dashboard-v3 §7.3).
RET attaches the agent's terminal, `i' opens its detail, `T' the tree;
the §5.3 agent keys act on the row at point.

\\{gascity-agents-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("" 1 nil) ("Agent" 34 t) ("Rig" 12 t) ("State" 9 t)
         ("Active" 9 nil) ("Bead" 10 t) ("Prov" 6 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key nil)
  (tabulated-list-init-header)
  (gascity-tabulated--install-filter
   'gascity-agents--filter
   (lambda () (gascity-agents--render)))
  ;; `x' resets to every state, not to nothing shown.
  (setq-local gascity-filter-reset-function
              (lambda () (setq gascity-agents--filter nil) (gascity-agents--render))))

(defun gascity-agents--city (dir)
  "Return the city name for the buffer names of a view opened in DIR."
  (or (gascity-context-city-name dir) "city"))

;;;###autoload
(defun gascity-agents ()
  "Show the city's agents in a table (`j a', dashboard-v3 §7.3)."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
         (buf (gascity-view-get-buffer-create
               (format gascity-agents-buffer-name (gascity-agents--city dir)) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-agents-mode)
        (gascity-agents-mode)
        (gascity-agents--render))
      (gascity-agents-refresh 'cached))
    (pop-to-buffer buf)))

;;; Tree (`T')

(vui-defcomponent gascity-agents-tree-app ()
  "The Agents tree: city → rigs → pools → agents (dashboard-v3 §7.3)."
  :state ((refresh-tick 0) (collapsed-rigs nil) (collapsed-pools nil))
  :render
  (let* ((status (gascity-ui-store-load
                  (gascity-store-use '("status") :tick refresh-tick)))
         (sessions (gascity-ui-store-load
                    (gascity-store-use '("session" "list") :tick refresh-tick)))
         (agents (gascity-ui-store-load
                  (gascity-store-use '("agent" "list") :tick refresh-tick))))
    (pcase (plist-get status :state)
      ('pending (vui-text (propertize "  …" 'face 'gascity-dim)))
      ('error (gascity-ui-error-line "status" (plist-get status :error)))
      (_
       (gascity-agents--tree-vnode
        (plist-get status :data)
        (plist-get sessions :data)
        (gascity-status--pool-templates
         (alist-get 'agents (plist-get agents :data)))
        collapsed-rigs collapsed-pools)))))

(defun gascity-agents--tree-vnode (status sessions-payload templates
                                          collapsed-rigs collapsed-pools)
  "Return the tree of STATUS joined to SESSIONS-PAYLOAD, pools by TEMPLATES.
COLLAPSED-RIGS / COLLAPSED-POOLS name the folded groups.  Named
sessions without a status agent (the mayor) join the city scope."
  (let* ((session-rows (gascity-domain-decode-list
                        'gascity-session
                        (or (alist-get 'sessions sessions-payload) [])))
         (session-map (gascity-status--session-map-rows session-rows))
         (socket (gascity-resolve-tmux-socket (alist-get 'city_name status) 'no-probe))
         (agents (append (alist-get 'agents status) nil))
         (known (mapcar (lambda (a) (alist-get 'qualified_name a)) agents))
         (named (seq-keep
                 (lambda (s)
                   (let ((name (gascity-session-qualified-name s)))
                     (and name (not (member name known))
                          (null (gascity-session-rig s))
                          (gascity-session-running-p s)
                          `((name . ,name) (qualified_name . ,name)
                            (scope . "city") (running . t)))))
                 session-rows))
         (all (append agents named))
         (rigs (gascity-domain-decode-list 'gascity-rig (alist-get 'rigs status)))
         (city-agents (seq-filter #'gascity-status--city-agent-p all)))
    (vui-vstack
     :spacing 1
     (vui-vstack
      (gascity-ui-section-header "City" nil)
      (gascity-status--agent-group-vnodes
       (gascity-status--group-agents city-agents templates session-map)
       nil session-map socket collapsed-pools))
     (vui-list rigs
               (lambda (rig)
                 (vui-component 'gascity-status-rig
                                :rig rig :agents all :templates templates
                                :session-map session-map :socket socket
                                :collapsed-pools collapsed-pools
                                :collapsed (and (member (gascity-rig-name rig)
                                                        collapsed-rigs)
                                                t)))
               #'gascity-rig-name
               :spacing 1))))

(defun gascity-agents-tree--toggle (kind name)
  "Fold or unfold the tree's rig or pool (KIND `rig'/`pool') NAME."
  (when-let* ((root (and (boundp 'vui--root-instance) vui--root-instance)))
    (let* ((key (if (eq kind 'rig) :collapsed-rigs :collapsed-pools))
           (state (vui-instance-state root))
           (current (plist-get state key)))
      (setf (vui-instance-state root)
            (plist-put state key (if (member name current)
                                     (remove name current)
                                   (cons name current))))
      (vui-flush-sync))))

(defun gascity-agents-tree-refresh ()
  "Re-read the Agents tree, keeping folds and point."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No agents tree here")))

(defvar-keymap gascity-agents-tree-mode-map
  :doc "Keymap for `gascity-agents-tree-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-agents-tree-refresh
  "T"   #'gascity-agents
  "RET" #'gascity-tmux-at-point
  "t"   #'gascity-tmux-at-point
  "i"   #'gascity-polecat-detail-at-point
  "d"   #'gascity-dired-at-point
  "v"   #'gascity-session-peek-at-point
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "R"   #'gascity-session-reset-at-point
  "U"   #'gascity-session-undrain-at-point)

(define-derived-mode gascity-agents-tree-mode gascity-section-mode "GC-Agents-Tree"
  "Major mode for the Agents tree (dashboard-v3 §7.3).
SPC folds a rig or a pool, `T' returns to the table.

\\{gascity-agents-tree-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local gascity-status-toggle-function #'gascity-agents-tree--toggle)
  (setq-local header-line-format
              (concat " Agents (tree)"
                      (propertize "   T table  ? help  j jump  g refresh"
                                  'face 'gascity-dim))))

;;;###autoload
(defun gascity-agents-tree ()
  "Show the city's agents as a tree: city → rigs → pools → agents (`T')."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
         (buf (gascity-view-get-buffer-create
               (format gascity-agents-tree-buffer-name (gascity-agents--city dir)) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-agents-tree-mode)
        (gascity-agents-tree-mode)))
    (unless (gascity-section-refresh-instance buf)
      (save-window-excursion
        (vui-mount (vui-component 'gascity-agents-tree-app) (buffer-name buf))))
    (pop-to-buffer-same-window buf)))

(provide 'gascity-agents)
;;; gascity-agents.el ends here
