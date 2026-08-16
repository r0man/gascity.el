;;; gascity-section.el --- Shared vui section mode + agent actions -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Foundations shared by gascity's rich (vui) views.
;;
;; `gascity-section-mode' derives from `beads-section-mode' (which
;; derives from `vui-mode'), inheriting the vui reconciler and widget
;; navigation (TAB/S-TAB).  The vui chain binds no `q', so this mode
;; adds `q' to bury (its keymap); gascity's detail/dashboard modes
;; derive from it and inherit that binding.
;;
;; It also provides the state->face helpers and the two agent actions
;; the read-only porcelain exposes from both the dashboard and the
;; session list: open the agent's worktree in Dired, and attach to its
;; tmux session.  Both act on the "agent at point", which is resolved
;; from a `gascity-agent' text property (vui buffers) or the
;; tabulated-list entry id (list buffers).  An agent is a `gascity-agent'
;; object (gascity-domain.el): name/work-dir/session-name/socket/running,
;; read through accessors rather than `plist-get'.

;;; Code:

(require 'seq)                    ; seq-find (section-header scan)
(require 'beads-section)
(require 'vui)
(require 'wid-edit)
(require 'gascity-custom)
(require 'gascity-context)
(require 'gascity-domain)        ; typed rig/agent objects + at-point generic
(require 'gascity-remote)        ; host-local path localization (remote cities)
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

;;; Section navigation

;; The vui dashboards render their content as a run of top-level sections
;; — the city and each rig on the status board; the header/agents/beads/
;; orders/dolt blocks of a rig; the state/hook/history blocks of an agent.
;; Each section's *header* line is stamped with a `gascity-section' text
;; property by the dashboards' render code (the gascity analogue of a
;; magit section's heading — but a plain property, since these views are
;; vui, not magit-section).  `N'/`P' walk between those headers: the
;; coarse counterpart to `n'/`p' line movement.  We scan for header
;; *starts* (a position carrying the property whose predecessor does not)
;; rather than leaning on `text-property-search''s NOT-CURRENT skip, whose
;; behaviour at a region's first/last position is position-sensitive.

(defun gascity-section--header-starts ()
  "Return the buffer positions that begin a `gascity-section' header, in order.
A header start is a position carrying the `gascity-section' property whose
preceding character does not — including `point-min' when it carries it."
  (let ((pos (point-min))
        (starts nil))
    (when (get-text-property pos 'gascity-section)
      (push pos starts))
    (while (setq pos (next-single-property-change pos 'gascity-section))
      (when (get-text-property pos 'gascity-section)
        (push pos starts)))
    (nreverse starts)))

(defun gascity-section-next ()
  "Move point to the next top-level section header.
Section headers are the city/rig/… lines the vui dashboards stamp with a
`gascity-section' text property; this jumps between them, the coarse
counterpart to `n' (`next-line').  Stops at the last section — signalling
a `user-error' rather than wrapping, matching `next-line' at end of
buffer."
  (interactive)
  (let ((next (seq-find (lambda (p) (> p (point)))
                        (gascity-section--header-starts))))
    (if next
        (goto-char next)
      (user-error "No next section"))))

(defun gascity-section-previous ()
  "Move point to the previous top-level section header.
The backward counterpart of `gascity-section-next' (see there); from a
section's body this lands on that section's own header.  Stops at the
first section — signalling a `user-error' rather than wrapping."
  (interactive)
  (let ((prev (seq-find (lambda (p) (< p (point)))
                        (reverse (gascity-section--header-starts)))))
    (if prev
        (goto-char prev)
      (user-error "No previous section"))))

(defvar-keymap gascity-section-mode-map
  :doc "Keymap for `gascity-section-mode'."
  :parent beads-section-mode-map
  ;; Shadow `beads-section-mode's RET (its beads issue visitor) with a
  ;; gascity-appropriate default, honouring \"RET drills in everywhere\".
  "RET" #'gascity-section-activate
  ;; Section navigation, bound here so every vui dashboard inherits it:
  ;; `N'/`P' jump between top-level sections (city/rig/…), the coarse
  ;; counterpart to `n'/`p' line movement — which are bound here too so
  ;; every vui dashboard moves by line uniformly (the status board used
  ;; to bind these locally).  (The at-point nudge that used to live on
  ;; `N' moves to `M' in the dashboards that bind it.)
  "N" #'gascity-section-next
  "P" #'gascity-section-previous
  "n" #'next-line
  "p" #'previous-line
  ;; Bind `q' to bury here so all three vui views — the status dashboard,
  ;; the rig dashboard, and the session/polecat detail — inherit it
  ;; through this parent map.  The vui keymap chain
  ;; (`beads-section-mode-map' -> `vui-mode-map' -> `widget-keymap')
  ;; binds no `q'; without this, `q' falls through to the global
  ;; `self-insert-command' and errors "Text is read-only" — yet every
  ;; view's header line promises "q bury".  `quit-window' matches the
  ;; tabulated lists (which inherit it from `tabulated-list-mode-map')
  ;; and the magit/forge convention (gce-0d5).
  "q" #'quit-window)

(define-derived-mode gascity-section-mode beads-section-mode "GasCity"
  "Base major mode for gascity vui section buffers.
Derives from `beads-section-mode' for the vui reconciler and widget
navigation.  The vui keymap chain binds no `q', so this mode binds
`q' to `quit-window' (bury); concrete views (the status dashboard,
detail views) derive from this, inherit `q', and add their own keys."
  :interactive nil
  :group 'gascity)

;;; Semantic cursor preservation across vui re-renders
;;
;; vui's re-render `erase-buffer's the whole buffer and then restores point by
;; WIDGET PATH (`vui--save-cursor-position' / `--restore-cursor-position').  Two
;; gaps surface once a section buffer refreshes on a timer (the status
;; dashboard's 5s tick, gce-pt6):
;;
;;   1. A widget path is unstable when async data changes a section's row count
;;      or order — a rig starts/stops, an agent appears/leaves — so point drifts
;;      off the row it was on.
;;   2. `erase-buffer' resets every window's `window-point' to 1, and vui
;;      restores only `window-start' (the viewport), never `window-point'.
;;      `goto-char' inside `with-current-buffer' moves only the buffer's own
;;      point, so a buffer shown in a NON-selected window jumps to the top on
;;      every tick.
;;
;; Layer semantic restoration on top of vui's widget-path pass with an `:around'
;; advice on `vui--rerender-instance': before the re-render remember the
;; SEMANTIC id of the row at point (its rig/agent/bead identity, stable across a
;; reorder) and the windows showing the buffer; after, put point back on the row
;; carrying that id and sync every one of those windows' `window-point' to it.
;; The advice gates on `gascity-section-mode', so it is a no-op for every other
;; buffer — beads.el's own vui dashboards included, since `beads-section-mode' is
;; this mode's PARENT, not a child.  It is purely additive: vui's own pass still
;; runs, and gascity-status.el's collapse + stale-while-revalidate behaviour is
;; untouched.  Ported from gastown.el (gastown-status-buffer.el).

(defun gascity-section--line-property (prop)
  "Return the value of text property PROP anywhere on the current line, or nil.
Scans from `line-beginning-position' to `line-end-position': a row's identity
property starts past its leading indent, not at column 0, so a bare
`get-text-property' at point would miss it when point sits in the margin."
  (let ((beg (line-beginning-position))
        (end (line-end-position)))
    (or (get-text-property beg prop)
        (let ((pos (next-single-property-change beg prop nil end)))
          (and pos (get-text-property pos prop))))))

(defun gascity-section--line-id ()
  "Return a semantic identifier for the row on the current line, or nil.
Reuses the identity text properties the vui dashboards already stamp, most
specific first: a `gascity-agent' object (by name), a `gascity-bead' id, then a
`gascity-rig' name.  Returns a cons of (KIND . IDENTITY-STRING) — stable across
a re-render even when rows are added, removed, or reordered, and comparable
with `equal' — or nil on a line carrying no such identity (a blank line or a
bare city/section header), which the caller leaves to vui's own restoration."
  (let ((agent (gascity-section--line-property 'gascity-agent))
        (bead (gascity-section--line-property 'gascity-bead))
        (rig (gascity-section--line-property 'gascity-rig)))
    (cond
     ((gascity-agent-p agent) (cons 'agent (or (gascity-agent-name agent) "")))
     ((and (stringp bead) (not (string-empty-p bead))) (cons 'bead bead))
     ((and (stringp rig) (not (string-empty-p rig))) (cons 'rig rig)))))

(defun gascity-section--restore-cursor-to-id (id col)
  "Move point to the first line whose semantic id is ID, then to column COL.
ID is a cons as returned by `gascity-section--line-id'.  Scans from
`point-min'; when no line matches (the row vanished in the re-render) point is
left at `point-min' — the same graceful degradation vui's widget-path restore
gives when its path no longer resolves."
  (goto-char (point-min))
  (catch 'found
    (while (not (eobp))
      (when (equal (gascity-section--line-id) id)
        (move-to-column col)
        (throw 'found t))
      (forward-line 1))))

(defun gascity-section--around-rerender (orig instance)
  "Advice around `vui--rerender-instance' for semantic cursor restoration.
ORIG is the wrapped `vui--rerender-instance'; INSTANCE the component instance
being re-rendered.  For a `gascity-section-mode' buffer, capture the semantic
id (`gascity-section--line-id') and column of the row at point plus the windows
showing the buffer, run ORIG, then restore point to the row with that id and
propagate it to every captured window's `window-point' (the fix for the
non-selected-window jump — see the section commentary).  For any other buffer
this is a pass-through, so vui's behaviour elsewhere is unchanged."
  (let* ((buf (vui-instance-buffer instance))
         (in-section (and buf
                          (buffer-live-p buf)
                          (with-current-buffer buf
                            (derived-mode-p 'gascity-section-mode)))))
    (if (not in-section)
        (funcall orig instance)
      (let ((id nil)
            (col 0)
            (windows (get-buffer-window-list buf nil t)))
        (with-current-buffer buf
          (let ((line-id (gascity-section--line-id)))
            (when line-id
              (setq id line-id
                    col (current-column)))))
        (funcall orig instance)
        (when id
          (with-current-buffer buf
            (gascity-section--restore-cursor-to-id id col)))
        ;; `erase-buffer' reset every window-point to 1; propagate the restored
        ;; buffer point to all windows that were showing the buffer so a
        ;; non-selected window does not jump to the top.
        (let ((pos (with-current-buffer buf (point))))
          (dolist (win windows)
            (when (window-live-p win)
              (set-window-point win pos))))))))

;; Install semantic cursor preservation for every gascity vui section buffer.
;; The advice gates itself on `gascity-section-mode', so it is a no-op for all
;; other buffers and safe to install once at load.  Guard against duplicate
;; advice when the module is reloaded.
(unless (advice-member-p #'gascity-section--around-rerender 'vui--rerender-instance)
  (advice-add 'vui--rerender-instance :around #'gascity-section--around-rerender))

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
`gc status' payload already in hand), then the city name resolved from
directory context, and finally a gc-backed lookup
\(`gascity-context-gc-city-name') so callers without a payload in hand
stay correct even when `default-directory' is outside the city tree.
May return nil (no city found), meaning the default tmux server.

The city-name step is a deliberate inference: gc does not expose the tmux
server socket in `--json' (the old `gt' did).  When gc grows a stable
socket field, read it here in preference to the inference (see gce-je4)."
  (or gascity-tmux-socket
      city-name
      (gascity-context-city-name)
      (gascity-context-gc-city-name)))

;;; State -> face

(defun gascity-section-state-face (running &optional suspended)
  "Return the gascity face for an agent/rig given RUNNING and SUSPENDED."
  (cond (suspended 'gascity-suspended)
        (running 'gascity-running)
        (t 'gascity-stopped)))

;;; Object at point — one resolver, polymorphic visit (gce-fjt)
;;
;; Every view stamps the typed domain object it renders: vui rows carry it
;; on a text property, tabulated lists carry it as the entry id, and a detail
;; buffer carries its subject buffer-locally.  `gascity-object-at-point' is
;; the single precedence ladder that recovers it; `gascity-at-point-visit'
;; (gascity-domain.el) dispatches the default drill-in action by the object's
;; class, replacing the per-payload-kind `cond' the activate commands carried.
;; The per-kind resolvers below (`gascity-agent-at-point' etc.) narrow the
;; result to one type for the action keys that act on a specific kind.

(defvar-local gascity-section--agent nil
  "The subject `gascity-agent' of a single-agent detail buffer, or nil.
The session/polecat detail view renders one agent and sets this so the
agent actions act on the buffer's subject regardless of point.  List and
dashboard buffers leave it nil and resolve the agent per row instead.")

(defun gascity-object-at-point ()
  "Return the typed domain object at point, or nil.
Resolves, in order, from a `gascity-agent' text property (vui agent rows),
a `gascity-bead' text property (vui bead rows — a bead-id string), the entry
id of a `tabulated-list-mode' buffer (a `gascity-rig'/`gascity-agent'/
`gascity-convoy'/`gascity-mail'/`gascity-order' for the typed lists), or the
buffer-local `gascity-section--agent' subject (a single-agent detail buffer).
The result is what `gascity-at-point-visit' dispatches on; the per-kind
resolvers below narrow it to a single type."
  (or (get-text-property (point) 'gascity-agent)
      (get-text-property (point) 'gascity-bead)
      (and (derived-mode-p 'tabulated-list-mode) (tabulated-list-get-id))
      gascity-section--agent))

(cl-defmethod gascity-at-point-visit ((agent gascity-agent))
  "Visit an agent: attach its tmux terminal (the porcelain's primary action)."
  (gascity-agent-attach-tmux agent))

(cl-defmethod gascity-at-point-visit ((id string))
  "Visit a bead id: open it in beads.el, scoped to its store."
  (gascity-bead-show id))

;;; Agent at point

(defun gascity-agent-at-point ()
  "Return the `gascity-agent' at point, or nil.
Narrows `gascity-object-at-point' to an agent: a `gascity-agent' text
property (vui rows), a session-list entry id, or a detail buffer's subject.
Rows whose object is a different type (a rig, convoy, …) yield nil."
  (let ((obj (gascity-object-at-point)))
    (and (gascity-agent-p obj) obj)))

;;; Agent actions

(defun gascity-agent--work-dir (agent)
  "Return AGENT's working directory as a path string, or signal a `user-error'.
AGENT is a `gascity-agent'.  Prefers the `work-dir' recorded on the agent's
session bead (its git worktree); when none was recorded, falls back to the
live working directory of the agent's tmux pane (resolved from its
`session-name'/`socket'), mirroring gastown.  Signals a clean `user-error'
— never an internal error — when no directory can be resolved or the
resolved directory is missing on disk.  Shared by `gascity-agent-dired' and
`gascity-agent-beads' so `d' and `b' resolve an agent's worktree identically."
  (let* ((name (or (gascity-agent-name agent) "agent"))
         (recorded (gascity-agent-work-dir agent))
         (dir (if (and recorded (stringp recorded) (not (string-empty-p recorded)))
                  recorded
                (gascity-terminal-pane-cwd (gascity-agent-session-name agent)
                                           (gascity-agent-socket agent)))))
    (unless (and dir (stringp dir) (not (string-empty-p dir)))
      (user-error "No working directory recorded for %s" name))
    ;; gc (and the tmux pane probe) report host-local paths; for a view of
    ;; a remote city, re-prefix so Dired/beads open it on that host.
    (setq dir (gascity-remote-localize-path dir))
    (unless (file-directory-p dir)
      (user-error "Directory not found for %s: %s" name dir))
    dir))

(defun gascity-agent-dired (agent)
  "Open Dired on AGENT's working directory.
AGENT is a `gascity-agent'; the directory is resolved by
`gascity-agent--work-dir' (the recorded worktree, else the live tmux pane
cwd), which signals a clean `user-error' when none can be resolved."
  (dired (gascity-agent--work-dir agent)))

(defun gascity-agent-attach-tmux (agent)
  "Attach to AGENT's tmux session in a terminal buffer.
AGENT is a `gascity-agent'; its `session-name' (and optional `socket' and
`work-dir') drive `gascity-terminal-attach-tmux'."
  (gascity-terminal-attach-tmux (gascity-agent-session-name agent)
                                (gascity-agent-socket agent)
                                (gascity-agent-work-dir agent)))

(defun gascity-rig-dired (name dir)
  "Open Dired on rig NAME's directory DIR.
DIR is the rig's `path' (as `gc rig list'/`gc status' report it) — a
host-local path, re-prefixed for a remote city.  Like
`gascity-agent-dired', this signals a clean `user-error' — never an
internal error — when DIR is absent (the rig has no local checkout) or
missing on disk, so `d' on such a rig no-ops gracefully."
  (let ((dir (gascity-remote-localize-path dir)))
    (cond
     ((or (null dir) (not (stringp dir)) (string-empty-p dir))
      (user-error "No local directory for rig %s" (or name "?")))
     ((not (file-directory-p dir))
      (user-error "Directory not found for rig %s: %s" (or name "?") dir))
     (t (dired dir)))))

;;;###autoload
(defun gascity-dired-at-point ()
  "Open Dired on the agent worktree or rig directory at point.
On an agent row, opens the agent's worktree (`gascity-agent-dired').  On a
rig header, opens the rig's local directory — the `path' gc reports for
it, stamped on the header as the `gascity-rig-dir' text property.  Signals
a clean `user-error' when neither is at point, or when the rig has no
recorded directory (it no-ops gracefully)."
  (interactive)
  (let ((agent (gascity-agent-at-point)))
    (cond
     (agent (gascity-agent-dired agent))
     ((get-text-property (point) 'gascity-rig)
      (gascity-rig-dired (get-text-property (point) 'gascity-rig)
                         (get-text-property (point) 'gascity-rig-dir)))
     (t (user-error "No agent or rig at point")))))

;;;###autoload
(defun gascity-tmux-at-point ()
  "Attach to the tmux session of the agent at point."
  (interactive)
  (let ((agent (gascity-agent-at-point)))
    (unless agent (user-error "No agent at point"))
    (gascity-agent-attach-tmux agent)))

;;; Bead at point — delegate display to beads.el (DESIGN.md §4.3)

(defun gascity-bead-at-point ()
  "Return the bead id (a string) at point, or nil.
Narrows `gascity-object-at-point' to a `gascity-bead' text-property string
\(vui detail/dashboard rows, stamped with the bead id)."
  (let ((obj (gascity-object-at-point)))
    (and (stringp obj) (not (string-empty-p obj)) obj)))

(defun gascity-mail-at-point ()
  "Return the `gascity-mail' message at point, or nil.
Narrows `gascity-object-at-point' to a mail message — the entry id of a
row in the `gascity-mail-inbox-mode' list.  Rows resolving to a different
type yield nil."
  (let ((obj (gascity-object-at-point)))
    (and (gascity-mail-p obj) obj)))

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

(defun gascity-rigs ()
  "Return the city's rigs as a list of `gascity-rig' objects.
Decodes `gc rig list''s `rigs' vector via `beads-from-json' (the single
decode site for rig payloads).  Signals like `gascity-command-rig-list!' on
failure; callers that tolerate absence wrap the call in `ignore-errors'."
  (gascity-domain-decode-list 'gascity-rig
                              (alist-get 'rigs (gascity-command-rig-list!))))

(defun gascity-beads--rig-path (rig)
  "Return the absolute store directory for RIG, or nil.
RIG is a rig name (string) or a `gascity-rig'.  The store directory is the
rig's repo `path' (the directory that holds its `.beads/'), re-prefixed
for a remote city so beads.el resolves the store on the city's host.  A
name is resolved against `gascity-rigs'; any failure degrades to nil."
  (let ((rig (cond ((gascity-rig-p rig) rig)
                   ((stringp rig)
                    (ignore-errors
                      (seq-find (lambda (r) (equal (gascity-rig-name r) rig))
                                (gascity-rigs)))))))
    (when-let* ((path (and rig (gascity-rig-path rig)))
                ((stringp path))
                ((not (string-empty-p path))))
      (file-name-as-directory
       (expand-file-name (gascity-remote-localize-path path))))))

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
                     (seq-find (lambda (r) (equal (gascity-rig-prefix r) prefix))
                               (gascity-rigs)))))
    (gascity-beads--rig-path rig)))

(defun gascity-beads--show-in-store (id store)
  "Display bead ID with beads.el, resolving its store at STORE.
STORE is the bead's store directory, or nil for the ambient directory.

beads.el picks which store to act on from `default-directory' — its `bd'
runs in cwd-mode — but Gas City's shared Dolt server can resolve a given
working directory to a *different* rig's database than its `.beads'
config names, so a cross-rig or city-level bead (a convoy listed via `gc
convoy list', say) errors with \"no issues found\" even though STORE is
correct (gce-bhr).  `bd --directory' (-C) re-resolves the store locally
and is not subject to that server state, so pass STORE through
`beads-show''s `:directory' keyword to force it.  `default-directory' is
still bound to STORE so beads.el names the detail buffer for the right
project.  With no STORE there is nothing to scope, so defer to beads.el's
own resolution.

For a remote city STORE is a TRAMP name: binding `default-directory' to
it makes beads.el run `bd' on the city's host (its runner is
`process-file'-based), while the `-C' flag must name the store as that
host sees it — so the `:directory' keyword gets `file-local-name' (the
identity for a local STORE)."
  (if store
      (let ((default-directory store))
        (beads-show id :directory (file-local-name store)))
    (beads-show id)))

(defun gascity-bead-show (id &optional directory)
  "Open bead ID in beads.el, scoped to its rig's bead store.
gascity does not render beads itself; it hands ID to beads.el's detail
view (DESIGN.md §4.3).  The store is DIRECTORY when supplied, else the
store of the rig that owns ID's prefix; with neither, beads.el falls back
to the ambient directory (a single-rig checkout already sits in the right
tree).  `gascity-beads--show-in-store' scopes beads.el to that store via
`bd --directory' (-C) rather than cwd-mode, so a city-level convoy opens
even when the shared Dolt server would misroute the working directory to
another rig's database (gce-bhr).  Resolves DESIGN §9.1."
  (cond
   ((or (null id) (and (stringp id) (string-empty-p id)))
    (user-error "No bead to show"))
   (t
    (unless (fboundp 'beads-show)
      (require 'beads-command-show nil t))
    (if (fboundp 'beads-show)
        (gascity-beads--show-in-store
         id
         (or (and directory (file-name-as-directory
                             (expand-file-name directory)))
             (gascity-beads--bead-path id)))
      (user-error "beads.el is not available to show %s" id)))))

;;;###autoload
(defun gascity-bead-visit ()
  "Open the bead at point in beads.el, scoped to its store."
  (interactive)
  (gascity-bead-show (or (gascity-bead-at-point)
                         (user-error "No bead at point"))))

;;; Beads board — delegate a rig store or agent worktree to beads.el (DESIGN.md §4.3)

;;;###autoload
(defun gascity-rig-beads (rig)
  "Open beads.el's board for RIG, scoped to that rig's bead store.
RIG is a rig name (string) or a `gascity-rig'.  Delegates to beads.el's
project board (`beads-dashboard'), scoping it to RIG's store directory
via its `:directory' keyword, so beads.el renders that rig's beads
\(DESIGN.md §4.3).  Called interactively, prompts for the rig, defaulting
to the contextual one."
  (interactive
   (list (completing-read
          "Beads for rig: "
          (condition-case nil
              (delq nil (mapcar #'gascity-rig-name (gascity-rigs)))
            (gascity-error nil))
          nil nil nil nil (gascity-context-rig-name))))
  (let ((name (if (stringp rig) rig (gascity-rig-name rig)))
        (dir (gascity-beads--rig-path rig)))
    (unless dir
      (user-error "Could not resolve the bead store for rig %s" (or name "?")))
    (unless (fboundp 'beads-dashboard)
      (require 'beads-dashboard nil t))
    (if (fboundp 'beads-dashboard)
        (beads-dashboard :directory dir)
      (user-error "beads.el is not available to show beads for %s"
                  (or name "?")))))

(defun gascity-agent-beads (agent)
  "Open beads.el's board scoped to AGENT's worktree.
AGENT is a `gascity-agent' — its `work-dir' is the git worktree gc records
on its session bead.  Resolves the directory via `gascity-agent--work-dir'
\(the recorded worktree, else the live tmux pane cwd) and passes it to
beads.el's board via its `:directory' keyword so it renders that
worktree's `.beads/' store.  Mirrors `gascity-rig-beads' for a rig
\(DESIGN.md §4.3); signals a clean `user-error' when no worktree resolves
or beads.el is unavailable."
  (let ((dir (gascity-agent--work-dir agent))
        (name (or (gascity-agent-name agent) "agent")))
    (unless (fboundp 'beads-dashboard)
      (require 'beads-dashboard nil t))
    (if (fboundp 'beads-dashboard)
        (beads-dashboard :directory (file-name-as-directory (expand-file-name dir)))
      (user-error "beads.el is not available to show beads for %s" name))))

;;;###autoload
(defun gascity-rig-beads-at-point ()
  "Open beads.el's board for the rig at point, scoped to its store."
  (interactive)
  (gascity-rig-beads (or (gascity-rig-at-point)
                         (user-error "No rig at point"))))

;;;###autoload
(defun gascity-beads-at-point ()
  "Open beads.el's board for the agent worktree or rig at point.
On an agent row, opens the board scoped to the agent's worktree
\(`gascity-agent-beads').  On a rig header — or any line resolving to a
rig but no agent — opens the rig's whole store (`gascity-rig-beads').
Mirrors `gascity-dired-at-point's agent-before-rig precedence so `b' on
an agent row opens its worktree's beads, not its rig's store.  Signals a
clean `user-error' when neither is at point."
  (interactive)
  (let ((agent (gascity-agent-at-point)))
    (cond
     (agent (gascity-agent-beads agent))
     ((gascity-rig-at-point) (gascity-rig-beads (gascity-rig-at-point)))
     (t (user-error "No agent or rig at point")))))

;;; Rig at point

(defun gascity-rig-at-point ()
  "Return the rig name at point, or nil.
Narrows `gascity-object-at-point': the name of a `gascity-rig' (the rig
list), or the rig of the agent at point (so the rig dashboard opens from an
agent row in the status dashboard or session list).  Falls back to a
`gascity-rig' text property — the name string a status-dashboard rig header
carries for its keymap — when no typed object is at point."
  (let ((obj (gascity-object-at-point)))
    (cond ((gascity-rig-p obj) (gascity-rig-name obj))
          ((gascity-agent-p obj) (gascity-agent-rig obj))
          ((get-text-property (point) 'gascity-rig)))))

(defun gascity-rig-at-point-hq-p ()
  "Return non-nil when the rig at point is the city HQ.
`gc rig list' includes the city HQ as a row with `hq' set, so it shows up
in `gascity-rig-list-mode'.  But the HQ is not a `city.toml' rig: `gc rig
status' rejects it, so it has no rig dashboard.  Only a rig-list entry
\(a `gascity-rig') carries `hq' — an agent's rig is a bare name — so this
returns nil outside the rig list."
  (let ((obj (gascity-object-at-point)))
    (and (gascity-rig-p obj) (gascity-rig-hq obj) t)))

(provide 'gascity-section)
;;; gascity-section.el ends here
