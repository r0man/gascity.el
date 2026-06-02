;;; gascity-tabulated.el --- Tabulated-list views for gc lists -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; `tabulated-list-mode' views for the homogeneous `gc' lists: rigs,
;; sessions, convoys, mail, orders, and Dolt databases.  Per the design
;; matrix, lists use tabulated-list (sorting, navigation, and
;; `tabulated-list-get-id' for free); the heterogeneous status overview
;; and detail views use vui instead.
;;
;; Each view follows the same shape: a `--entry' function maps one
;; decoded JSON object to a `(ID . [COLUMNS])' row, a `-refresh' command
;; fetches via the matching `gascity-command-*!' runner and repaints, a
;; `define-derived-mode' sets the columns, and a `-show-buffer' entry
;; point opens it.  `RET' drills in, `g' refreshes — everywhere.  On a
;; session row, `d' opens its worktree in Dired and `t' attaches to its
;; tmux session.
;;
;; Columns are derived from the live `gc ... --json' shapes.  Long lists
;; are paged to the window height (`]'/`['/`G'; see
;; `gascity-tabulated-base-map'), and each list (except Dolt) offers a
;; `/' filter transient.  `gc' list subcommands expose almost no
;; server-side filter flags, so filtering is mostly client-side on the
;; decoded rows — the session `--state' filter is the lone server-side
;; exception; the filter criteria live as slots on the
;; `gascity-command-*' classes (see `gascity-types').

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'tabulated-list)
(require 'transient)
(require 'view)
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-section)
(require 'gascity-command)
(require 'gascity-types)

;; Bead delegation (convoy `RET' -> beads.el) goes through
;; `gascity-bead-show' in gascity-section, which scopes the store; the
;; rig list's `b' opens a rig's beads via `gascity-rig-beads-at-point'.
;; Both live in gascity-section, hard-required above.

;; At-point mutating actions live in gascity-action (loaded after this
;; module via gascity.el); the list keymaps below bind keys to them.
(declare-function gascity-rig-suspend-at-point "gascity-action")
(declare-function gascity-rig-resume-at-point "gascity-action")
(declare-function gascity-rig-restart-at-point "gascity-action")
(declare-function gascity-order-run-at-point "gascity-action")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")

;; Detail-view openers (the `RET' targets) live in gascity-rig /
;; gascity-session, loaded after this module via gascity.el.
(declare-function gascity-rig-dashboard-at-point "gascity-rig")
(declare-function gascity-polecat-detail-at-point "gascity-session")

;;; Shared helpers

(defun gascity-tabulated--vector->list (data)
  "Return DATA as a list, converting a vector when needed."
  (if (vectorp data) (append data nil) data))

(defun gascity-tabulated--format-timestamp (ts)
  "Return the YYYY-MM-DD date prefix of ISO timestamp TS, or \"\"."
  (if (and ts (stringp ts) (not (string-empty-p ts)))
      (substring ts 0 (min 10 (length ts)))
    ""))

(defun gascity-tabulated--abbreviate-path (path)
  "Return PATH with the home-directory prefix abbreviated to \"~\"."
  (if (and path (stringp path)) (abbreviate-file-name path) (or path "")))

(defun gascity-tabulated--str (value)
  "Coerce VALUE to a display string."
  (cond ((null value) "")
        ((stringp value) value)
        ((numberp value) (number-to-string value))
        ((eq value t) "yes")
        (t (format "%s" value))))

(defun gascity-tabulated--cell-string (entry n)
  "Return the display string of column N in tabulated-list ENTRY.
ENTRY has the form (ID [DESC...]), like the elements of
`tabulated-list-entries'; each DESC cell is either a string or a
\(LABEL . PROPS) cons.  Mirrors how the built-in `t' sorter reads a cell."
  (let ((cell (aref (cadr entry) n)))
    (if (stringp cell) cell (car cell))))

(defun gascity-tabulated--numeric-sorter (n &optional key)
  "Return a `tabulated-list-format' sort predicate for numeric column N.
The built-in `t' sorter compares cells as strings, so numeric columns
order lexicographically (\"110\" sorts before \"8\").  This predicate
instead maps each cell's display string through KEY (default
`string-to-number') and compares the results with `<', giving true
numeric order.  KEY lets a column derive its sort number from a richer
cell, e.g. a \"closed/total\" progress string."
  (let ((key (or key #'string-to-number)))
    (lambda (a b)
      (< (funcall key (gascity-tabulated--cell-string a n))
         (funcall key (gascity-tabulated--cell-string b n))))))

(defun gascity-tabulated--progress-fraction (cell)
  "Return the completion fraction of a \"closed/total\" progress CELL.
Parses the leading \"N/M\" and returns N/M as a float in [0,1]; a zero or
missing total yields 0.0, so convoys with nothing closed (or nothing to
do) sort below any with real progress.  Used as the KEY for the convoy
`Progress' column's numeric sorter."
  (if (string-match "\\([0-9]+\\)/\\([0-9]+\\)" cell)
      (let ((closed (string-to-number (match-string 1 cell)))
            (total (string-to-number (match-string 2 cell))))
        (if (> total 0) (/ (float closed) total) 0.0))
    0.0))

(defun gascity-tabulated--truncate (value width)
  "Return VALUE as a display string of at most WIDTH columns.
A value wider than WIDTH is truncated with a trailing ellipsis and
carries the full text as a `help-echo'; shorter values (and any text
properties they already carry, such as a face) are returned unchanged.

`tabulated-list-mode' elides an over-wide non-last column only with a
`display' text property, which keeps graphical frames aligned but leaves
the underlying string in place — so on a terminal (and in batch) the
extra characters spill over and push every later column out of
alignment.  Truncating the cell text itself keeps rows aligned on every
display."
  (let ((str (gascity-tabulated--str value)))
    (if (<= (string-width str) width)
        str
      ;; START-COLUMN 0, no PADDING, ELLIPSIS t: a real width-bounded
      ;; truncation (`…'), unlike tabulated-list's display-property elide.
      (propertize (truncate-string-to-width str width 0 nil t)
                  'help-echo str))))

(defvar-local gascity-tabulated--filter-description nil
  "Rendered description of the active filter, or nil when none is active.
Set by `gascity-tabulated--refresh' and appended in parentheses after the
page indicator by `gascity-tabulated--update-mode-name', so a filtered
list is visibly distinct from a complete one.  Re-derived from the live
filter plist on every refresh, so it tracks the filter across `g'.")

(defun gascity-tabulated--format-filter (filter)
  "Render FILTER, a plist of command initargs, as a mode-line description.
Each key is shown without its leading colon: a boolean t value as the
bare key (e.g. \"unread\"), any other value as \"key=value\".  Keys whose
value is nil are skipped.  Returns the joined description (e.g.
\"state=active rig=gascity\"), or nil when FILTER is empty or has no
active keys.  Used to surface the active filter in a list's mode line so
a filtered view is never mistaken for a complete one."
  (let ((parts (cl-loop for (key value) on filter by #'cddr
                        when value
                        collect (let ((name (substring (symbol-name key) 1)))
                                  (if (eq value t)
                                      name
                                    (format "%s=%s" name value))))))
    (when parts
      (mapconcat #'identity parts " "))))

(defun gascity-tabulated--refresh (base-name fetch-fn &optional filter)
  "Fetch rows via FETCH-FN and repaint the current tabulated buffer.
FETCH-FN returns a list of `(ID . [COLUMNS])' entries.  The full list is
stored for pagination and one window-sized page is shown; `gc' errors
are caught and reported, leaving the list empty.  BASE-NAME labels the
mode line, which shows the current page and total.  FILTER, when given,
is the list's active filter plist; its rendered description (see
`gascity-tabulated--format-filter') is shown in the mode line, and is
re-derived here on every refresh so it tracks the filter across `g'."
  (setq gascity-tabulated--filter-description
        (gascity-tabulated--format-filter filter))
  (let ((entries (condition-case err
                     (funcall fetch-fn)
                   (gascity-error
                    ;; `error-message-string' on a `gascity-command-error'
                    ;; renders the whole condition-data plist (:command,
                    ;; :exit-code, :stdout, :stderr); `gascity-error-detail'
                    ;; surfaces just gc's stderr (else the message) as one
                    ;; clean line.  (gce-dfe)
                    (message "gascity: %s" (gascity-error-detail err))
                    nil))))
    (gascity-tabulated--init-paged base-name entries)))

(defun gascity-tabulated--show (buffer-name mode-sym refresh-fn)
  "Pop to BUFFER-NAME in major mode MODE-SYM and run REFRESH-FN."
  (let ((buf (get-buffer-create buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p mode-sym) (funcall mode-sym))
      (funcall refresh-fn))
    (pop-to-buffer buf)))

;;; ============================================================
;;; Pagination
;;; ============================================================
;;
;; A window-sized paging layer ported from gastown.el's paged mixin.
;; `gascity-tabulated--refresh' stores the full entry list in
;; `gascity-tabulated--all-entries' and shows one window-sized page at a
;; time; `]'/`['/`G' move between pages (bound on
;; `gascity-tabulated-base-map', the shared parent of every list's
;; keymap), and the page size recomputes on window resize.  The mode
;; line reads "Name [page/total]".

(defvar-local gascity-tabulated--all-entries nil
  "All tabulated-list entries for this buffer, before paging.")

(defvar-local gascity-tabulated--current-page 1
  "Current page number (1-indexed).")

(defvar-local gascity-tabulated--page-size nil
  "Entries per page; nil means compute from the window height on demand.")

(defvar-local gascity-tabulated--base-name ""
  "Label shown before the page indicator in the mode line.")

(defun gascity-tabulated--compute-page-size ()
  "Return how many entries fit in the current window.
Two lines are reserved for the column header and the mode line."
  (max 1 (- (window-body-height) 2)))

(defun gascity-tabulated--effective-page-size ()
  "Return the active page size, computing it from the window if unset."
  (or gascity-tabulated--page-size (gascity-tabulated--compute-page-size)))

(defun gascity-tabulated--total-pages ()
  "Return the total number of pages for the current entries (at least 1)."
  (let ((total (length gascity-tabulated--all-entries))
        (size (gascity-tabulated--effective-page-size)))
    (max 1 (ceiling (/ (float total) size)))))

(defun gascity-tabulated--page-slice ()
  "Return the entries on `gascity-tabulated--current-page'."
  (let* ((all gascity-tabulated--all-entries)
         (size (gascity-tabulated--effective-page-size))
         (start (* (1- gascity-tabulated--current-page) size))
         (end (min (length all) (+ start size))))
    (if (>= start (length all))
        nil
      (seq-subseq all start end))))

(defun gascity-tabulated--update-mode-name ()
  "Set `mode-name' to \"BASE [page/total]\" and refresh the mode line.
When a filter is active, its description is appended in parentheses
\(e.g. \"Sessions [1/1] (rig=gascity)\"), so a filtered list is never
mistaken for a complete one."
  (setq mode-name (format "%s [%d/%d]%s"
                          gascity-tabulated--base-name
                          gascity-tabulated--current-page
                          (gascity-tabulated--total-pages)
                          (if gascity-tabulated--filter-description
                              (format " (%s)" gascity-tabulated--filter-description)
                            "")))
  (force-mode-line-update))

(defun gascity-tabulated--truncate-row (cols)
  "Return a copy of column vector COLS with over-wide cells truncated.
Each non-last string cell wider than its `tabulated-list-format' column
width is truncated to that width with an ellipsis (see
`gascity-tabulated--truncate'), so a long value never pushes later
columns out of alignment.  COLS itself is not modified, and the last
column is left intact — nothing follows it to misalign, and it may
legitimately need the full width (e.g. a working directory)."
  (let ((out (copy-sequence cols))
        (ncols (length cols)))
    (dotimes (i ncols)
      (when (< (1+ i) ncols)            ; never truncate the last column
        (let ((cell (aref out i))
              (width (nth 1 (aref tabulated-list-format i))))
          (when (and (stringp cell) (natnump width))
            (aset out i (gascity-tabulated--truncate cell width))))))
    out))

(defun gascity-tabulated--refresh-display ()
  "Slice the current page into `tabulated-list-entries' and redraw.
Each row's cells are truncated to their column widths via
`gascity-tabulated--truncate-row' so long values keep the columns
aligned; row ids are preserved verbatim, so `RET'/`d'/`t' still act on
the full data."
  (setq tabulated-list-entries
        (mapcar (lambda (entry)
                  (list (car entry)
                        (gascity-tabulated--truncate-row (cadr entry))))
                (gascity-tabulated--page-slice)))
  (tabulated-list-print t)
  (gascity-tabulated--update-mode-name))

(defun gascity-tabulated--init-paged (base-name all-entries)
  "Initialise paging state for the current buffer and display page 1.
BASE-NAME labels the mode line; ALL-ENTRIES is the full entry list."
  (setq gascity-tabulated--all-entries all-entries
        gascity-tabulated--current-page 1
        gascity-tabulated--page-size (gascity-tabulated--compute-page-size)
        gascity-tabulated--base-name base-name)
  (gascity-tabulated--refresh-display))

(defun gascity-tabulated-next-page ()
  "Advance to the next page."
  (interactive)
  (let ((total (gascity-tabulated--total-pages)))
    (if (>= gascity-tabulated--current-page total)
        (message "Already on the last page (%d/%d)"
                 gascity-tabulated--current-page total)
      (setq gascity-tabulated--current-page (1+ gascity-tabulated--current-page))
      (gascity-tabulated--refresh-display))))

(defun gascity-tabulated-prev-page ()
  "Go back to the previous page."
  (interactive)
  (if (<= gascity-tabulated--current-page 1)
      (message "Already on the first page")
    (setq gascity-tabulated--current-page (1- gascity-tabulated--current-page))
    (gascity-tabulated--refresh-display)))

(defun gascity-tabulated-goto-page (n)
  "Jump to page N (1-indexed); prompt when called interactively."
  (interactive
   (list (read-number (format "Go to page (1-%d): "
                              (gascity-tabulated--total-pages)))))
  (let ((total (gascity-tabulated--total-pages)))
    (if (or (< n 1) (> n total))
        (user-error "Page %d out of range (1-%d)" n total)
      (setq gascity-tabulated--current-page n)
      (gascity-tabulated--refresh-display))))

(defun gascity-tabulated--frame-resize (frame)
  "Recompute page size for paged buffers shown in FRAME after a resize."
  (dolist (win (window-list frame))
    (let ((buf (window-buffer win)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when (local-variable-p 'gascity-tabulated--all-entries)
            (let ((new-size (with-selected-window win
                              (gascity-tabulated--compute-page-size))))
              (unless (eql new-size gascity-tabulated--page-size)
                (setq gascity-tabulated--page-size new-size)
                (let ((total (gascity-tabulated--total-pages)))
                  (when (> gascity-tabulated--current-page total)
                    (setq gascity-tabulated--current-page total)))
                (gascity-tabulated--refresh-display)))))))))

(add-hook 'window-size-change-functions #'gascity-tabulated--frame-resize)

(defvar-keymap gascity-tabulated-base-map
  :doc "Shared parent keymap for gascity tabulated-list buffers.
Adds window-sized pagination (`]' next, `[' previous, `G' goto) on top
of `tabulated-list-mode-map'.  Each list's own keymap parents off this
and adds `g' refresh, `/' filter, and `RET'."
  :parent tabulated-list-mode-map
  "]" #'gascity-tabulated-next-page
  "[" #'gascity-tabulated-prev-page
  "G" #'gascity-tabulated-goto-page)

;;; ============================================================
;;; Rigs
;;; ============================================================

(defconst gascity-rig-list-buffer-name "*gascity-rigs*")

(defvar-local gascity-rig-list--filter nil
  "Active rig-list filter as command initargs (e.g. (:status \"running\")), or nil.")

(defun gascity-rig-list--status-label (rig)
  "Return RIG's status label: \"suspended\", \"running\", or \"stopped\"."
  (cond ((alist-get 'suspended rig) "suspended")
        ((alist-get 'running rig) "running")
        (t "stopped")))

(defun gascity-rig-list--status (rig)
  "Return a propertized status cell for RIG (an alist)."
  (propertize (gascity-rig-list--status-label rig)
              'face (gascity-section-state-face (alist-get 'running rig)
                                                (alist-get 'suspended rig))))

(defun gascity-rig-list--match-p (rig status)
  "Return non-nil when RIG matches STATUS (nil matches every rig)."
  (or (null status)
      (string= status (gascity-rig-list--status-label rig))))

(defun gascity-rig-list--entry (rig)
  "Map RIG (an alist) to a tabulated-list entry."
  (list rig
        (vector (gascity-tabulated--str (alist-get 'name rig))
                (gascity-tabulated--str (alist-get 'prefix rig))
                (gascity-rig-list--status rig)
                (gascity-tabulated--str (or (alist-get 'default_branch rig)
                                            (and (alist-get 'hq rig) "—")))
                (gascity-tabulated--str (alist-get 'beads rig)))))

(defun gascity-rig-list-dired ()
  "Open Dired on the path of the rig at point."
  (interactive)
  (let* ((rig (tabulated-list-get-id))
         (path (and rig (alist-get 'path rig))))
    (if (and path (file-directory-p path))
        (dired path)
      (user-error "No rig directory at point"))))

(defun gascity-rig-list-refresh ()
  "Refresh the rig list, applying the current filter."
  (interactive)
  (gascity-tabulated--refresh
   "Rigs"
   (lambda ()
     (let* ((cmd (apply #'gascity-command-rig-list gascity-rig-list--filter))
            (rigs (gascity-tabulated--vector->list
                   (alist-get 'rigs (oref (gascity-command-execute cmd) result)))))
       (mapcar #'gascity-rig-list--entry
               (seq-filter (lambda (r)
                             (gascity-rig-list--match-p r (oref cmd status)))
                           rigs))))
   gascity-rig-list--filter))

(transient-define-prefix gascity-rig-list-filter ()
  "Filter the rig list."
  ["Filter rigs"
   ("-s" "Status" "--status=" :choices ("running" "suspended" "stopped"))]
  ["Apply"
   ("a" "Apply" gascity-rig-list--apply-filter)
   ("c" "Clear" gascity-rig-list--clear-filter)])

(defun gascity-rig-list--apply-filter (&optional args)
  "Apply transient ARGS as the rig-list filter and refresh."
  (interactive (list (transient-args 'gascity-rig-list-filter)))
  (let ((status (transient-arg-value "--status=" args)))
    (setq gascity-rig-list--filter
          (and status (not (string-empty-p status)) (list :status status))))
  (gascity-rig-list-refresh))

(defun gascity-rig-list--clear-filter ()
  "Clear the rig-list filter and refresh."
  (interactive)
  (setq gascity-rig-list--filter nil)
  (gascity-rig-list-refresh))

(defvar-keymap gascity-rig-list-mode-map
  :doc "Keymap for `gascity-rig-list-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-rig-list-refresh
  "/"   #'gascity-rig-list-filter
  "RET" #'gascity-rig-dashboard-at-point
  "b"   #'gascity-rig-beads-at-point
  "d"   #'gascity-rig-list-dired
  "s"   #'gascity-rig-suspend-at-point
  "r"   #'gascity-rig-resume-at-point
  "R"   #'gascity-rig-restart-at-point)

(define-derived-mode gascity-rig-list-mode tabulated-list-mode "GC-Rigs"
  "Major mode listing the rigs registered in the city.
`RET' opens the rig's dashboard; `b' opens the rig's beads in beads.el
\(scoped to its store); `d' opens the rig's directory in Dired; `s'
suspends, `r' resumes, and `R' restarts (kills the agent sessions of)
the rig at point.
\\{gascity-rig-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("Name" 24 t) ("Prefix" 8 t) ("Status" 11 t)
         ("Branch" 14 t) ("Beads" 12 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "Name" nil))
  (tabulated-list-init-header))

;;;###autoload
(defun gascity-rig-list ()
  "Show the city's rigs in a tabulated list."
  (interactive)
  (gascity-tabulated--show gascity-rig-list-buffer-name
                           #'gascity-rig-list-mode
                           #'gascity-rig-list-refresh))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-rig-list))
  "Open the rig list buffer."
  (gascity-rig-list))

;;; ============================================================
;;; Sessions
;;; ============================================================

(defconst gascity-session-list-buffer-name "*gascity-sessions*")

(defvar-local gascity-session-list--filter nil
  "Active session-list filter as command initargs, or nil.
May carry a server-side :state and a client-side :rig substring.")

(defun gascity-session-list--name (session)
  "Return SESSION's qualified agent name.
Prefers `agent_name' (always qualified) over `name', which degrades to
the raw tmux id for non-active sessions."
  (or (alist-get 'agent_name session) (alist-get 'name session)))

(defun gascity-session-list--agent (session socket)
  "Return the agent plist for SESSION (an alist) on tmux SOCKET."
  (list :name (gascity-session-list--name session)
        :rig (alist-get 'rig session)
        :work-dir (alist-get 'work_dir session)
        :session-name (alist-get 'session_name session)
        :socket socket
        :running (string= (gascity-tabulated--str (alist-get 'state session))
                          "active")))

(defun gascity-session-list--entry (session socket)
  "Map SESSION (an alist) to a tabulated-list entry on tmux SOCKET.
The entry id is the agent plist, so `d'/`t'/`RET' act on it."
  (let* ((state (gascity-tabulated--str (alist-get 'state session)))
         (running (string= state "active")))
    (list (gascity-session-list--agent session socket)
          (vector (gascity-tabulated--str (gascity-session-list--name session))
                  (gascity-tabulated--str (alist-get 'rig session))
                  (propertize state 'face
                              (gascity-section-state-face running nil))
                  (gascity-tabulated--str (alist-get 'provider session))
                  (gascity-tabulated--abbreviate-path
                   (alist-get 'work_dir session))))))

(defun gascity-session-list--match-p (session rig)
  "Return non-nil when SESSION's rig contains RIG (nil/empty matches all).
RIG is matched case-insensitively as a substring of the decoded `rig'."
  (or (null rig) (string-empty-p rig)
      (let ((case-fold-search t))
        (string-match-p (regexp-quote rig)
                        (gascity-tabulated--str (alist-get 'rig session))))))

(defun gascity-session-list-refresh ()
  "Refresh the session list, applying the current filter.
The `state' filter is sent to `gc' (`--state'); the `rig' filter is
applied client-side to the decoded rows."
  (interactive)
  (gascity-tabulated--refresh
   "Sessions"
   (lambda ()
     ;; Resolve the tmux socket once per refresh — it is constant across
     ;; rows, and `gc session list' does not carry the city name.
     (let* ((cmd (apply #'gascity-command-session-list gascity-session-list--filter))
            (socket (gascity-resolve-tmux-socket))
            (sessions (gascity-tabulated--vector->list
                       (alist-get 'sessions
                                  (oref (gascity-command-execute cmd) result)))))
       (mapcar (lambda (s) (gascity-session-list--entry s socket))
               (seq-filter (lambda (s)
                             (gascity-session-list--match-p s (oref cmd rig)))
                           sessions))))
   gascity-session-list--filter))

(transient-define-prefix gascity-session-list-filter ()
  "Filter the session list."
  ["Filter sessions"
   ("-s" "State" "--state="
    :choices ("active" "suspended" "closed" "all"))
   ("-r" "Rig" "--rig=")]
  ["Apply"
   ("a" "Apply" gascity-session-list--apply-filter)
   ("c" "Clear" gascity-session-list--clear-filter)])

(defun gascity-session-list--apply-filter (&optional args)
  "Apply transient ARGS as the session-list filter and refresh."
  (interactive (list (transient-args 'gascity-session-list-filter)))
  (let ((state (transient-arg-value "--state=" args))
        (rig (transient-arg-value "--rig=" args)))
    (setq gascity-session-list--filter
          (append (and state (not (string-empty-p state)) (list :state state))
                  (and rig (not (string-empty-p rig)) (list :rig rig)))))
  (gascity-session-list-refresh))

(defun gascity-session-list--clear-filter ()
  "Clear the session-list filter and refresh."
  (interactive)
  (setq gascity-session-list--filter nil)
  (gascity-session-list-refresh))

(defvar-keymap gascity-session-list-mode-map
  :doc "Keymap for `gascity-session-list-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-session-list-refresh
  "/"   #'gascity-session-list-filter
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  "RET" #'gascity-polecat-detail-at-point
  "N"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  "p"   #'gascity-session-peek-at-point)

(define-derived-mode gascity-session-list-mode tabulated-list-mode "GC-Sessions"
  "Major mode listing the city's agent sessions.
`RET' opens the session/polecat detail view; `d' opens its worktree in
Dired; `t' attaches to its tmux session.  `N' nudges (sends a message),
`s' suspends, `K' force-kills the runtime of, `w' wakes, `D' drains, and
`p' peeks at the output of the session at point.
\\{gascity-session-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("Agent" 26 t) ("Rig" 14 t) ("State" 9 t)
         ("Provider" 9 t) ("Working dir" 40 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "Agent" nil))
  (tabulated-list-init-header))

;;;###autoload
(defun gascity-session-list ()
  "Show the city's agent sessions in a tabulated list."
  (interactive)
  (gascity-tabulated--show gascity-session-list-buffer-name
                           #'gascity-session-list-mode
                           #'gascity-session-list-refresh))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-session-list))
  "Open the session list buffer."
  (gascity-session-list))

;;; ============================================================
;;; Convoys
;;; ============================================================

(defconst gascity-convoy-list-buffer-name "*gascity-convoys*")

(defvar-local gascity-convoy-list--filter nil
  "Active convoy-list filter as command initargs (e.g. (:status \"open\")), or nil.")

(defun gascity-convoy-list--match-p (convoy status)
  "Return non-nil when CONVOY matches STATUS (nil matches every convoy)."
  (or (null status)
      (string= status (gascity-tabulated--str (alist-get 'status convoy)))))

(defun gascity-convoy-list--entry (convoy)
  "Map CONVOY (an alist) to a tabulated-list entry.
The entry id is the convoy's bead id, so `RET' can open it in beads.el."
  (let* ((progress (alist-get 'progress convoy))
         (closed (or (alist-get 'closed progress) 0))
         (total (or (alist-get 'total progress) 0)))
    (list (gascity-tabulated--str (alist-get 'id convoy))
          (vector (gascity-tabulated--str (alist-get 'id convoy))
                  (gascity-tabulated--str (alist-get 'title convoy))
                  (gascity-tabulated--str (alist-get 'status convoy))
                  (format "%d/%d" closed total)))))

(defun gascity-convoy-list-visit ()
  "Open the convoy bead at point in beads.el, scoped to its store.
Convoys are city-level beads (`rig: null') listed via `gc convoy list';
`gascity-bead-show' resolves the owning rig store by id prefix and opens
it with `bd --directory' (-C), which works even when the shared Dolt
server would misroute the working directory to another database (gce-bhr)."
  (interactive)
  (gascity-bead-show (or (tabulated-list-get-id)
                         (user-error "No convoy at point"))))

(defun gascity-convoy-list-refresh ()
  "Refresh the convoy list, applying the current filter."
  (interactive)
  (gascity-tabulated--refresh
   "Convoys"
   (lambda ()
     (let* ((cmd (apply #'gascity-command-convoy-list gascity-convoy-list--filter))
            (convoys (gascity-tabulated--vector->list
                      (alist-get 'convoys
                                 (oref (gascity-command-execute cmd) result)))))
       (mapcar #'gascity-convoy-list--entry
               (seq-filter (lambda (c)
                             (gascity-convoy-list--match-p c (oref cmd status)))
                           convoys))))
   gascity-convoy-list--filter))

(transient-define-prefix gascity-convoy-list-filter ()
  "Filter the convoy list."
  ["Filter convoys"
   ("-s" "Status" "--status=" :choices ("open" "closed"))]
  ["Apply"
   ("a" "Apply" gascity-convoy-list--apply-filter)
   ("c" "Clear" gascity-convoy-list--clear-filter)])

(defun gascity-convoy-list--apply-filter (&optional args)
  "Apply transient ARGS as the convoy-list filter and refresh."
  (interactive (list (transient-args 'gascity-convoy-list-filter)))
  (let ((status (transient-arg-value "--status=" args)))
    (setq gascity-convoy-list--filter
          (and status (not (string-empty-p status)) (list :status status))))
  (gascity-convoy-list-refresh))

(defun gascity-convoy-list--clear-filter ()
  "Clear the convoy-list filter and refresh."
  (interactive)
  (setq gascity-convoy-list--filter nil)
  (gascity-convoy-list-refresh))

(defvar-keymap gascity-convoy-list-mode-map
  :doc "Keymap for `gascity-convoy-list-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-convoy-list-refresh
  "/"   #'gascity-convoy-list-filter
  "RET" #'gascity-convoy-list-visit)

(define-derived-mode gascity-convoy-list-mode tabulated-list-mode "GC-Convoys"
  "Major mode listing the city's convoys.
`RET' opens the convoy bead in beads.el.
\\{gascity-convoy-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        `[("ID" 12 t) ("Title" 46 t) ("Status" 10 t)
          ("Progress" 10 ,(gascity-tabulated--numeric-sorter
                           3 #'gascity-tabulated--progress-fraction))])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "ID" nil))
  (tabulated-list-init-header))

;;;###autoload
(defun gascity-convoy-list ()
  "Show the city's convoys in a tabulated list."
  (interactive)
  (gascity-tabulated--show gascity-convoy-list-buffer-name
                           #'gascity-convoy-list-mode
                           #'gascity-convoy-list-refresh))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-convoy-list))
  "Open the convoy list buffer."
  (gascity-convoy-list))

;;; ============================================================
;;; Mail
;;; ============================================================

(defconst gascity-mail-inbox-buffer-name "*gascity-mail*")

(defvar-local gascity-mail-inbox--filter nil
  "Active mail-inbox filter as command initargs (e.g. (:unread t)), or nil.")

(defun gascity-mail-inbox--unread-p (message)
  "Return non-nil when MESSAGE (an alist) is unread.
`gc mail inbox --json' gives each message a required boolean `read' field
\(v1 `mail_message' schema); unread is its negation.  JSON `false' decodes
to nil (see `gascity-reader-parse-json'), so an unread message reads nil."
  (not (alist-get 'read message)))

(defun gascity-mail-inbox--match-p (message unread)
  "Return non-nil when MESSAGE passes the UNREAD-only filter.
A nil UNREAD keeps every message."
  (or (not unread) (gascity-mail-inbox--unread-p message)))

(defun gascity-mail-inbox--entry (message)
  "Map MESSAGE (an alist) to a tabulated-list entry.
Columns follow the `gc mail inbox --json' v1 `mail_message' schema —
`from', `subject', `created_at', and the boolean `read' (for the unread
marker).  The entry id is the whole message alist, so `RET' can show
every field."
  (list message
        (vector (gascity-tabulated--str (alist-get 'from message))
                (gascity-tabulated--str (alist-get 'subject message))
                (gascity-tabulated--format-timestamp (alist-get 'created_at message))
                (if (gascity-mail-inbox--unread-p message) "●" ""))))

(defun gascity-mail-inbox-show ()
  "Show the fields of the mail message at point in a view buffer.
Read-only: renders the data already fetched, without contacting `gc'."
  (interactive)
  (let ((message (tabulated-list-get-id)))
    (unless message (user-error "No message at point"))
    (let ((buf (get-buffer-create "*gascity-mail-message*")))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (dolist (cell message)
            (insert (format "%-14s %s\n"
                            (concat (symbol-name (car cell)) ":")
                            (gascity-tabulated--str (cdr cell)))))
          (goto-char (point-min)))
        (view-mode 1))
      (pop-to-buffer buf))))

(defun gascity-mail-inbox-refresh ()
  "Refresh the mail inbox, applying the current filter."
  (interactive)
  (gascity-tabulated--refresh
   "Mail"
   (lambda ()
     (let* ((cmd (apply #'gascity-command-mail-inbox gascity-mail-inbox--filter))
            (messages (gascity-tabulated--vector->list
                       (alist-get 'messages
                                  (oref (gascity-command-execute cmd) result)))))
       (mapcar #'gascity-mail-inbox--entry
               (seq-filter (lambda (m)
                             (gascity-mail-inbox--match-p m (oref cmd unread)))
                           messages))))
   gascity-mail-inbox--filter))

(transient-define-prefix gascity-mail-inbox-filter ()
  "Filter the mail inbox."
  ["Filter mail"
   ("-u" "Unread only" "--unread")]
  ["Apply"
   ("a" "Apply" gascity-mail-inbox--apply-filter)
   ("c" "Clear" gascity-mail-inbox--clear-filter)])

(defun gascity-mail-inbox--apply-filter (&optional args)
  "Apply transient ARGS as the mail-inbox filter and refresh."
  (interactive (list (transient-args 'gascity-mail-inbox-filter)))
  (setq gascity-mail-inbox--filter
        (and (member "--unread" args) (list :unread t)))
  (gascity-mail-inbox-refresh))

(defun gascity-mail-inbox--clear-filter ()
  "Clear the mail-inbox filter and refresh."
  (interactive)
  (setq gascity-mail-inbox--filter nil)
  (gascity-mail-inbox-refresh))

(defvar-keymap gascity-mail-inbox-mode-map
  :doc "Keymap for `gascity-mail-inbox-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-mail-inbox-refresh
  "/"   #'gascity-mail-inbox-filter
  "RET" #'gascity-mail-inbox-show)

(define-derived-mode gascity-mail-inbox-mode tabulated-list-mode "GC-Mail"
  "Major mode showing the current agent's mail inbox.
`RET' shows the message at point.
\\{gascity-mail-inbox-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("From" 24 t) ("Subject" 50 t) ("Date" 12 t) ("New" 3 nil)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key nil)
  (tabulated-list-init-header))

;;;###autoload
(defun gascity-mail-inbox ()
  "Show the current agent's mail inbox in a tabulated list."
  (interactive)
  (gascity-tabulated--show gascity-mail-inbox-buffer-name
                           #'gascity-mail-inbox-mode
                           #'gascity-mail-inbox-refresh))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-mail-inbox))
  "Open the mail inbox buffer."
  (gascity-mail-inbox))

;;; ============================================================
;;; Orders
;;; ============================================================

(defconst gascity-order-list-buffer-name "*gascity-orders*")

(defvar-local gascity-order-list--filter nil
  "Active order-list filter as command initargs, or nil.
May carry :enabled (enabled-only) and :type (exact type match).")

(defun gascity-order-list--match-p (order enabled type)
  "Return non-nil when ORDER passes the ENABLED-only and TYPE filters.
ENABLED non-nil keeps only enabled orders; TYPE (when non-empty) keeps
only orders whose `type' matches it exactly.  Nil/empty values match
every order."
  (and (or (not enabled) (and (alist-get 'enabled order) t))
       (or (null type) (string-empty-p type)
           (string= type (gascity-tabulated--str (alist-get 'type order))))))

(defun gascity-order-list--entry (order)
  "Map ORDER (an alist) to a tabulated-list entry.
The entry id is the whole order alist, so `RET' can open its source."
  (list order
        (vector (gascity-tabulated--str (or (alist-get 'scoped_name order)
                                            (alist-get 'name order)))
                (gascity-tabulated--str (alist-get 'rig order))
                (gascity-tabulated--str (alist-get 'type order))
                (gascity-tabulated--str (alist-get 'trigger order))
                (gascity-tabulated--str (or (alist-get 'interval order)
                                            (alist-get 'schedule order)))
                (if (alist-get 'enabled order) "●" ""))))

(defun gascity-order-list-visit ()
  "Open the source file of the order at point."
  (interactive)
  (let* ((order (tabulated-list-get-id))
         (source (and order (alist-get 'source order))))
    (if (and source (file-readable-p source))
        (find-file source)
      (user-error "No readable source for the order at point"))))

(defun gascity-order-list-refresh ()
  "Refresh the order list, applying the current filter."
  (interactive)
  (gascity-tabulated--refresh
   "Orders"
   (lambda ()
     (let* ((cmd (apply #'gascity-command-order-list gascity-order-list--filter))
            (orders (gascity-tabulated--vector->list
                     (alist-get 'orders
                                (oref (gascity-command-execute cmd) result)))))
       (mapcar #'gascity-order-list--entry
               (seq-filter (lambda (o)
                             (gascity-order-list--match-p
                              o (oref cmd enabled) (oref cmd type)))
                           orders))))
   gascity-order-list--filter))

(transient-define-prefix gascity-order-list-filter ()
  "Filter the order list."
  ["Filter orders"
   ("-e" "Enabled only" "--enabled")
   ("-t" "Type" "--type=")]
  ["Apply"
   ("a" "Apply" gascity-order-list--apply-filter)
   ("c" "Clear" gascity-order-list--clear-filter)])

(defun gascity-order-list--apply-filter (&optional args)
  "Apply transient ARGS as the order-list filter and refresh."
  (interactive (list (transient-args 'gascity-order-list-filter)))
  (let ((type (transient-arg-value "--type=" args)))
    (setq gascity-order-list--filter
          (append (and (member "--enabled" args) (list :enabled t))
                  (and type (not (string-empty-p type)) (list :type type)))))
  (gascity-order-list-refresh))

(defun gascity-order-list--clear-filter ()
  "Clear the order-list filter and refresh."
  (interactive)
  (setq gascity-order-list--filter nil)
  (gascity-order-list-refresh))

(defvar-keymap gascity-order-list-mode-map
  :doc "Keymap for `gascity-order-list-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-order-list-refresh
  "/"   #'gascity-order-list-filter
  "RET" #'gascity-order-list-visit
  "x"   #'gascity-order-run-at-point)

(define-derived-mode gascity-order-list-mode tabulated-list-mode "GC-Orders"
  "Major mode listing the city's orders.
`RET' opens the order's source file; `x' runs the order at point
manually (bypassing its trigger).
\\{gascity-order-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("Order" 28 t) ("Rig" 14 t) ("Type" 8 t)
         ("Trigger" 10 t) ("Schedule" 12 t) ("On" 3 nil)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "Order" nil))
  (tabulated-list-init-header))

;;;###autoload
(defun gascity-order-list ()
  "Show the city's orders in a tabulated list."
  (interactive)
  (gascity-tabulated--show gascity-order-list-buffer-name
                           #'gascity-order-list-mode
                           #'gascity-order-list-refresh))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-order-list))
  "Open the order list buffer."
  (gascity-order-list))

;;; ============================================================
;;; Dolt databases
;;; ============================================================

(defconst gascity-dolt-list-buffer-name "*gascity-dolt*")

(defun gascity-dolt-list--entry (db)
  "Map DB (an alist from dolt health) to a tabulated-list entry.
Carries the Dolt commit count but not `gc dolt health''s `open_beads':
that metric reads 0 for every database in practice, so the column was a
row of zeros.  Dropped here (gce-x72) as it was from the rig dashboard
\(gce-ziz); real open-bead counts come from `bd', not dolt health."
  (list db
        (vector (gascity-tabulated--str (alist-get 'name db))
                (gascity-tabulated--str (alist-get 'commits db)))))

(defun gascity-dolt-list-show ()
  "Echo the details of the Dolt database at point."
  (interactive)
  (let ((db (tabulated-list-get-id)))
    (unless db (user-error "No database at point"))
    (message "%s: %s commits"
             (gascity-tabulated--str (alist-get 'name db))
             (gascity-tabulated--str (alist-get 'commits db)))))

(defun gascity-dolt-list-refresh ()
  "Refresh the Dolt database list (from `gc dolt health')."
  (interactive)
  (gascity-tabulated--refresh
   "Dolt"
   (lambda ()
     (mapcar #'gascity-dolt-list--entry
             (gascity-tabulated--vector->list
              (alist-get 'databases (gascity-command-dolt-health!)))))))

(defvar-keymap gascity-dolt-list-mode-map
  :doc "Keymap for `gascity-dolt-list-mode'.
Dolt has no meaningful filter dimension, so no `/'; pagination
(`]'/`['/`G') comes from the parent map."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-dolt-list-refresh
  "RET" #'gascity-dolt-list-show)

(define-derived-mode gascity-dolt-list-mode tabulated-list-mode "GC-Dolt"
  "Major mode listing the Dolt databases and their stats.
\\{gascity-dolt-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        `[("Database" 20 t)
          ("Commits" 10 ,(gascity-tabulated--numeric-sorter 1))])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "Database" nil))
  (tabulated-list-init-header))

;;;###autoload
(defun gascity-dolt-list ()
  "Show the city's Dolt databases in a tabulated list."
  (interactive)
  (gascity-tabulated--show gascity-dolt-list-buffer-name
                           #'gascity-dolt-list-mode
                           #'gascity-dolt-list-refresh))

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-dolt-health))
  "Open the Dolt database list buffer."
  (gascity-dolt-list))

(provide 'gascity-tabulated)
;;; gascity-tabulated.el ends here
