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
(require 'beads-prefix)
(require 'view)
(require 'beads-pager)            ; pure pagination arithmetic (window size / count / slice)
(require 'gascity-custom)
(require 'gascity-context)            ; pin-directory (view keyed to its city)
(require 'gascity-error)
(require 'gascity-domain)             ; typed row objects (rig/session/agent/convoy/mail/order)
(require 'gascity-remote)             ; host-qualified names + path localization
(require 'gascity-section)
(require 'gascity-command)
(require 'gascity-reader)
(require 'gascity-store)              ; shared, scheduled list reads
(require 'gascity-types)
(require 'gascity-ui)                 ; filter-menu builders, relative times

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
(declare-function gascity-sling-dispatch "gascity-action")
(declare-function gascity-session-nudge-at-point "gascity-action")
(declare-function gascity-session-suspend-at-point "gascity-action")
(declare-function gascity-session-kill-at-point "gascity-action")
(declare-function gascity-session-wake-at-point "gascity-action")
(declare-function gascity-session-drain-at-point "gascity-action")
(declare-function gascity-session-peek-at-point "gascity-action")
;; Write verbs (DESIGN-write-actions.md phase 1): session reset/undrain and
;; the mail inbox read/archive/mark-unread at-point actions.
(declare-function gascity-session-reset-at-point "gascity-action")
(declare-function gascity-session-undrain-at-point "gascity-action")
(declare-function gascity-mail-read-at-point "gascity-action")
(declare-function gascity-mail-archive-at-point "gascity-action")
(declare-function gascity-mail-mark-unread-at-point "gascity-action")
;; Write verbs (DESIGN-write-actions.md phase 2): mail reply (compose) and
;; the mail-dispatch menu (`c').
(declare-function gascity-mail-reply-at-point "gascity-action")
(declare-function gascity-mail-dispatch "gascity-action")

;; Detail-view openers (the `RET' targets) live in gascity-rig /
;; gascity-session, loaded after this module via gascity.el.
(declare-function gascity-rig-dashboard-at-point "gascity-rig")
(declare-function gascity-polecat-detail-at-point "gascity-session")

;;; Shared helpers

(defun gascity-tabulated--vector->list (data)
  "Return DATA as a list, converting a vector when needed."
  (if (vectorp data) (append data nil) data))

(defun gascity-tabulated--format-timestamp (ts)
  "Return ISO timestamp TS as \"YYYY-MM-DD HH:MM\", or \"\" when empty.
Keeps the wall-clock time exactly as TS records it, so the displayed
clock matches the zone `gc' encoded: it emits `last_active' with a local
UTC offset and `created_at' in UTC, each shown in its own zone — so a
session's \"last active\" reads in local time.  This is a pure string
reshape (no parsing/conversion), so it is stable regardless of the
system clock or time zone.  Falls back to the date alone when TS carries
no time part, and to the bare \"YYYY-MM-DD\" prefix for any shape this
does not recognize."
  (if (and ts (stringp ts) (not (string-empty-p ts)))
      (if (string-match
           "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)\\(?:[T ]\\([0-9]\\{2\\}:[0-9]\\{2\\}\\)\\)?"
           ts)
          (let ((date (match-string 1 ts))
                (time (match-string 2 ts)))
            (if time (concat date " " time) date))
        (substring ts 0 (min 10 (length ts))))
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
\(LABEL . PROPS) cons.  Mirrors how the built-in string sorter reads a cell."
  (let ((cell (aref (cadr entry) n)))
    (if (stringp cell) cell (car cell))))

(defun gascity-tabulated--numeric-sorter (n &optional key)
  "Return a `tabulated-list-format' sort predicate for numeric column N.
The built-in string sorter compares cells as strings, so numeric columns
order lexicographically (\"110\" sorts before \"8\").  This predicate
instead maps each cell's display string through KEY (default
`string-to-number') and compares the results with `<', giving true
numeric order.  KEY lets a column derive its sort number from a richer
cell, e.g. a \"closed/total\" progress string."
  (let ((key (or key #'string-to-number)))
    (lambda (a b)
      (< (funcall key (gascity-tabulated--cell-string a n))
         (funcall key (gascity-tabulated--cell-string b n))))))

(defun gascity-tabulated--time-sorter (n)
  "Return a sort predicate for column N holding `gascity-ui-time' cells.
A relative time (`3m', `yesterday') does not sort as a string, so the
predicate compares the ISO timestamps the cells carry in `help-echo'."
  (let ((key (lambda (entry)
               (or (gascity-ui-parse-time
                    (get-text-property
                     0 'help-echo (gascity-tabulated--cell-string entry n)))
                   0))))
    (lambda (a b) (< (funcall key a) (funcall key b)))))

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
  "Pop to BUFFER-NAME in major mode MODE-SYM and run REFRESH-FN.
The buffer comes from `gascity-view-get-buffer-create', so it is keyed
to the city it is opened for: BUFFER-NAME is host-qualified for a
remote city (a local and a remote list coexist) and the buffer's
`default-directory' is pinned to that city's root, so `g' refreshes and
at-point actions keep resolving the same gc — and, remotely, the same
host — regardless of where they are invoked from."
  (let ((buf (gascity-view-get-buffer-create buffer-name)))
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

;; Pagination arithmetic is single-sourced from beads.el's `beads-pager'
;; pure core (gce-9aw); the helpers below only thread this buffer's local
;; state (entry list, current page, explicit page size) into those public
;; buffer-agnostic functions.

(defun gascity-tabulated--effective-page-size ()
  "Return the active page size, computing it from the window if unset.
The window computation is `beads-pager-window-page-size', the single
source of truth shared with beads.el's own list buffers."
  (or gascity-tabulated--page-size (beads-pager-window-page-size)))

(defun gascity-tabulated--total-pages ()
  "Return the total number of pages for the current entries (at least 1).
Delegates the arithmetic to `beads-pager-page-count'."
  (beads-pager-page-count (length gascity-tabulated--all-entries)
                          (gascity-tabulated--effective-page-size)))

(defun gascity-tabulated--page-slice ()
  "Return the entries on `gascity-tabulated--current-page'.
Delegates the slice arithmetic to `beads-pager-slice'."
  (beads-pager-slice gascity-tabulated--all-entries
                     gascity-tabulated--current-page
                     (gascity-tabulated--effective-page-size)))

(defvar-local gascity-tabulated--stale-errors nil
  "Count of consecutive failed refreshes behind the visible rows, or nil.
Set by a list's failure handler (e.g. the session list's auto-refresh
error hygiene); rendered by `gascity-tabulated--stale-suffix' and
cleared by the list's success path or a manual `g'.")

(defun gascity-tabulated--stale-suffix ()
  "Mode-line suffix for a list whose last refresh failed, or \"\".
`gascity-tabulated--stale-errors' non-nil means the refresh behind the
visible rows failed (the rows are stale); the suffix names the failure
count so the state stays visible while the error itself is deduped out
of the echo area (ga-eyw9)."
  (if gascity-tabulated--stale-errors
      (format " [stale: %d failed refresh%s]"
              gascity-tabulated--stale-errors
              (if (= gascity-tabulated--stale-errors 1) "" "es"))
    ""))

(defun gascity-tabulated--update-mode-name ()
  "Set `mode-name' to \"BASE [page/total]\" and refresh the mode line.
When a filter is active, its description is appended in parentheses
\(e.g. \"Sessions [1/1] (rig=gascity)\"), so a filtered list is never
mistaken for a complete one.  A list whose last refresh failed shows a
stale marker (see `gascity-tabulated--stale-suffix')."
  (setq mode-name (format "%s [%d/%d]%s%s"
                          gascity-tabulated--base-name
                          gascity-tabulated--current-page
                          (gascity-tabulated--total-pages)
                          (if gascity-tabulated--filter-description
                              (format " (%s)" gascity-tabulated--filter-description)
                            "")
                          (gascity-tabulated--stale-suffix)))
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

(defun gascity-tabulated--sort-all-entries ()
  "Sort `gascity-tabulated--all-entries' in place by the active sort key.
The visible page is a slice of this list, so ordering the whole list here
— rather than letting `tabulated-list-print' sort only the current slice
— makes the sort span page boundaries instead of reordering one page at a
time.  The comparison is the sort column's own `tabulated-list-format'
predicate, obtained via `tabulated-list--get-sorter', so the numeric
sorters from gce-94g and the ascending/descending flag both apply; a nil
sort key (no active sort) leaves the gc-return order untouched."
  (let ((sorter (tabulated-list--get-sorter)))
    (when sorter
      (setq gascity-tabulated--all-entries
            (sort gascity-tabulated--all-entries sorter)))))

(defvar-local gascity-tabulated--refresh-process nil
  "The gc process of the refresh in flight for this buffer, or nil.
Set by `gascity-tabulated--refresh-async' from the store's shared read
\(`gascity-store-fetch') — for liveness checks only, never killed: other
views may be waiting on the same read.")

(defvar-local gascity-tabulated--awaiting nil
  "Non-nil while this buffer's last refresh request is unanswered.
Covers a read queued by the store's scheduler that has no process yet.")

(defvar-local gascity-tabulated--store-sub nil
  "This buffer's `gascity-store-subscribe' handle, or nil.
Repaints the list when its read completes on someone else's request —
another view, or an invalidation by the event router (§8.2).")

(defvar-local gascity-tabulated--painted-at nil
  "The store `:fetched-at' stamp of the payload the rows show.")

(defun gascity-tabulated-refresh-pending-p (&optional buffer)
  "Return non-nil while BUFFER's (default current) list refresh is in flight."
  (let ((buffer (or buffer (current-buffer))))
    (and (buffer-live-p buffer)
         (or (process-live-p
              (buffer-local-value 'gascity-tabulated--refresh-process buffer))
             (buffer-local-value 'gascity-tabulated--awaiting buffer)))))

(defvar-local gascity-tabulated--refresh-generation 0
  "Counter stamping each refresh request of this buffer.
A fetch that completes after a newer request was issued is discarded
\(`gascity-tabulated--refresh-async'), so a slow remote read can never
overwrite the rows of a later `g'.")

(defun gascity-tabulated--set-loading ()
  "Show the fetch in progress in the mode line.
`gascity-tabulated--update-mode-name' replaces it when rows arrive."
  (setq mode-name (format "%s [loading…]%s"
                          gascity-tabulated--base-name
                          (if gascity-tabulated--filter-description
                              (format " (%s)" gascity-tabulated--filter-description)
                            "")))
  (force-mode-line-update))

(defun gascity-tabulated--refresh-async (base-name command decode-fn
                                                   &optional filter error-fn
                                                   success-fn)
  "Fetch COMMAND asynchronously and repaint the current tabulated buffer.
The non-blocking counterpart of `gascity-tabulated--refresh', and what
every list's `g' runs: COMMAND is a `gascity-command' read (its argv
via `gascity-command-line', its validation as in
`gascity-command-execute'), read through the store
\(`gascity-store-fetch': shared with every view of the city, scheduled
per host, deadline-bounded) so a slow link — a remote `gc session
list' takes seconds — never stalls the UI.  DECODE-FN receives the
decoded JSON payload (what `gascity-command-parse' would have
produced) and returns the `(ID . [COLUMNS])' entries.  While the read
runs the mode line reads
\"BASE [loading…]\" and the previous rows stay put.

A refresh issued while one is in flight joins the shared read instead
of killing it; each request bumps `gascity-tabulated--refresh-generation'
and a result is applied only if its stamp is still current and the
buffer is alive, so out-of-order completion cannot show stale rows.
The buffer also subscribes to the read, so a completion requested by
someone else (another view, an invalidation) repaints the rows.  A
failure — launch error, non-zero exit, malformed JSON — is echoed as
one clean line and leaves the list empty, exactly like the synchronous
path (gce-dfe).  BASE-NAME and FILTER as for `gascity-tabulated--refresh'.
ERROR-FN, when given, replaces the default echo for that failure line
\(the session list's auto-refresh hygiene dedupes and counts through
it); SUCCESS-FN, when given, runs just before the rows settle — the
success half of that hygiene.  Both run in the list buffer.  Returns
the shared read's process when one is running, else nil."
  (when-let* ((error-msg (gascity-command-validate command)))
    (signal 'gascity-validation-error
            (list (format "Command validation failed: %s" error-msg)
                  :command command
                  :error error-msg)))
  (setq gascity-tabulated--filter-description
        (gascity-tabulated--format-filter filter)
        gascity-tabulated--base-name base-name)
  (let* ((buffer (current-buffer))
         (generation (cl-incf gascity-tabulated--refresh-generation))
         ;; The argv tail: `gascity-command-line' leads with the
         ;; executable, which the reader adds itself.
         (args (cdr (gascity-command-line command)))
         (current-p (lambda ()
                      (and (buffer-live-p buffer)
                           (= generation
                              (buffer-local-value
                               'gascity-tabulated--refresh-generation buffer)))))
         ;; ENTRIES-FN runs in the list buffer (its `default-directory'
         ;; scopes the rig memo and any decode-time context).
         (paint (lambda (entries-fn)
                  (with-current-buffer buffer
                    (setq gascity-tabulated--refresh-process nil
                          gascity-tabulated--awaiting nil
                          gascity-tabulated--painted-at
                          (plist-get (gascity-store-get args) :fetched-at))
                    (gascity-tabulated--init-paged
                     base-name (funcall entries-fn)))))
         (decoded (lambda (payload)
                    (lambda ()
                      (condition-case err
                          (funcall decode-fn payload)
                        (gascity-error
                         (message "gascity: %s" (gascity-error-detail err))
                         nil))))))
    (gascity-tabulated--set-loading)
    (setq gascity-tabulated--awaiting t)
    ;; Passive repaint: the same read completing for anyone else — the
    ;; dashboard, an action's invalidation — refreshes these rows too.
    (gascity-store-unsubscribe gascity-tabulated--store-sub)
    (setq gascity-tabulated--store-sub
          (gascity-store-subscribe
           args
           (lambda (snapshot)
             (when (and (buffer-live-p buffer)
                        (eq (plist-get snapshot :status) 'ready)
                        (not (plist-get snapshot :error))
                        (not (buffer-local-value 'gascity-tabulated--awaiting
                                                 buffer))
                        (not (equal (plist-get snapshot :fetched-at)
                                    (buffer-local-value
                                     'gascity-tabulated--painted-at buffer))))
               (funcall paint (funcall decoded (plist-get snapshot :data)))))
           :buffer buffer))
    (setq gascity-tabulated--refresh-process
          (gascity-store-fetch
           args
           (lambda (payload)
             (when (funcall current-p)
               (when success-fn
                 (with-current-buffer buffer (funcall success-fn)))
               (funcall paint (funcall decoded payload))))
           (lambda (msg)
             ;; Only the current request gets to speak.
             (when (funcall current-p)
               (with-current-buffer buffer
                 (if error-fn
                     (funcall error-fn msg)
                   (message "gascity: %s" msg)))
               (funcall paint #'ignore)))
           ;; An explicit refresh re-reads; a read already in flight
           ;; (another view's, or an earlier `g') is joined, not killed.
           :force t))))

(defconst gascity-tabulated--status-columns '("Status" "State" "New" "On")
  "Column names that are a row's status slot, where `…' marks a pending action.")

(defun gascity-tabulated--row-target (id)
  "Return the object id an action on row ID names, or nil."
  (cond ((gascity-agent-p id) (gascity-agent-name id))
        ((gascity-rig-p id) (gascity-rig-name id))
        ((gascity-mail-p id) (gascity-mail-id id))
        ((gascity-order-p id) (or (gascity-order-name id)
                                  (gascity-order-scoped-name id)))
        ((stringp id) id)))

(defun gascity-tabulated--mark-pending (id cols)
  "Return COLS with `…' in the status slot while an action on row ID runs.
The status slot is the first column named in
`gascity-tabulated--status-columns' (else the first column).  COLS is
returned untouched when nothing is pending (dashboard-v3 §8.5)."
  (let ((target (gascity-tabulated--row-target id)))
    (if (not (gascity-ui-pending-p target))
        cols
      (let* ((names (mapcar #'car (append tabulated-list-format nil)))
             (i (or (cl-some (lambda (n) (cl-position n names :test #'equal))
                             gascity-tabulated--status-columns)
                    0))
             (out (copy-sequence cols)))
        (aset out i (gascity-ui-pending-glyph target (aref out i)))
        out))))

(defun gascity-tabulated--refresh-display ()
  "Slice the current page into `tabulated-list-entries' and redraw.
The full entry list is first ordered by the active sort key across every
page (`gascity-tabulated--sort-all-entries'), so the visible slice is a
window onto the globally-sorted data rather than a per-page sort.  Each
row's cells are then truncated to their column widths via
`gascity-tabulated--truncate-row' so long values keep the columns
aligned; row ids are preserved verbatim, so RET/d/t still act on
the full data."
  (gascity-tabulated--sort-all-entries)
  (setq tabulated-list-entries
        (mapcar (lambda (entry)
                  (list (car entry)
                        (gascity-tabulated--mark-pending
                         (car entry)
                         (gascity-tabulated--truncate-row (cadr entry)))))
                (gascity-tabulated--page-slice)))
  (tabulated-list-print t)
  (gascity-tabulated--update-mode-name))

(defun gascity-tabulated--init-paged (base-name all-entries)
  "Initialise paging state for the current buffer and display page 1.
BASE-NAME labels the mode line; ALL-ENTRIES is the full entry list."
  (setq gascity-tabulated--all-entries all-entries
        gascity-tabulated--current-page 1
        gascity-tabulated--page-size (beads-pager-window-page-size)
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

(defun gascity-tabulated-sort (&optional n)
  "Sort the whole paged list by a column and return to page 1.
Like the inherited `tabulated-list-sort' (the `S' binding), but the order
spans every page instead of only the visible one: it updates
`tabulated-list-sort-key' through the built-in — reusing its column
validation and ascending/descending toggle — then re-sorts
`gascity-tabulated--all-entries' and shows page 1 via
`gascity-tabulated--refresh-display', whose pre-slice sort makes the order
global.  Page 1 then holds the new order's global extreme.  N is passed to
`tabulated-list-sort': a numeric prefix selects a column, and -1 restores
the original gc-return order across every page.

With no prefix and point on the leading padding — column 0, where the
cursor rests right after the list opens and which `n'/`p' navigation
preserves — the built-in would have no column at point and signal \"Cannot
sort by nil\".  In that case sort by the list's default column, the one
named in `tabulated-list-sort-key' (set for every list except mail), so
`S' works from the default cursor position exactly as if point were on
that column's cell."
  (interactive "P")
  ;; Point rests on the leading padding (no `tabulated-list-column-name')
  ;; after the list opens, and `n'/`p' keep it there; with no prefix the
  ;; built-in would signal "Cannot sort by nil".  Fall back to the default
  ;; sort column's index so `S' toggles it, as if point were on its cell.
  (when (and (null n)
             (null (get-text-property (point) 'tabulated-list-column-name))
             (car tabulated-list-sort-key))
    (setq n (cl-position (car tabulated-list-sort-key) tabulated-list-format
                         :key #'car :test #'equal)))
  ;; Let the built-in flip/set the sort key and validate the column (it
  ;; signals `user-error' for an unsortable column, leaving our state
  ;; untouched); then re-sort the full dataset and jump back to page 1.
  (tabulated-list-sort n)
  (setq gascity-tabulated--current-page 1)
  (gascity-tabulated--refresh-display))

(defun gascity-tabulated--frame-resize (frame)
  "Recompute page size for paged buffers shown in FRAME after a resize."
  (dolist (win (window-list frame))
    (let ((buf (window-buffer win)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when (local-variable-p 'gascity-tabulated--all-entries)
            (let ((new-size (with-selected-window win
                              (beads-pager-window-page-size))))
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
of `tabulated-list-mode-map'.  `S' is sling in every gascity view
\(dashboard-v3 §5.3), so tabulated-list's `S' sort moves to a header
click and the `-S' suffix of every `/' menu (`gascity-tabulated-sort'
spans every page).  Each list's own keymap parents off this and adds
`g' refresh, `/' filter, and `RET'."
  :parent tabulated-list-mode-map
  "]" #'gascity-tabulated-next-page
  "[" #'gascity-tabulated-prev-page
  "G" #'gascity-tabulated-goto-page
  "S" #'gascity-sling-dispatch
  "C-o" #'gascity-tabulated-detail-show
  "C-c C-f" #'gascity-tabulated-detail-follow-mode
  "q" #'gascity-tabulated-quit)

;; §5.4 in every list: TAB/S-TAB next/previous row, `?' dispatch, `j'
;; jump; SPC shows the row's detail in a side window (rows cannot host
;; an inline drawer), replacing tabulated-list's SPC = next line.
(gascity-thing-define-keys gascity-tabulated-base-map)

(defun gascity-tabulated--toggle-row (thing)
  "Toggle the detail window for a list row THING (a `beads-thing' handler).
Rows cannot host an inline drawer, so SPC on a row shows its detail in
the `*gascity-detail*' side window, or closes it."
  (when (eq (beads-thing-kind thing) 'row)
    (gascity-tabulated-detail-toggle)
    t))

(defun gascity-tabulated--setup-things ()
  "Route SPC on this list's rows to the detail window (§5.4).
Installs `gascity-tabulated--toggle-row' on the buffer-local
`beads-thing-toggle-functions', the shared primitive's one dispatch
path.  Run from every list mode's body."
  (add-hook 'beads-thing-toggle-functions #'gascity-tabulated--toggle-row nil t))

;;; Detail side window (§5.4)

(defconst gascity-tabulated-detail-buffer-name "*gascity-detail*"
  "Base name of the side window showing the list row at point.")

(defun gascity-tabulated--detail-lines (id entry)
  "Return the detail lines of a list row: its ID object, then its ENTRY.
An EIEIO object lists its slots, an alist its keys; anything else its
printed form.  Pure over the row already in hand (no gc call)."
  (append
   (cond
    ((eieio-object-p id)
     (mapcar (lambda (slot)
               (format "%-14s %s" slot
                       (gascity-tabulated--str
                        (and (slot-boundp id slot) (slot-value id slot)))))
             (mapcar #'eieio-slot-descriptor-name
                     (eieio-class-slots (eieio-object-class id)))))
    ((and (consp id) (consp (car id)))
     (mapcar (lambda (kv) (format "%-14s %s" (car kv)
                                  (gascity-tabulated--str (cdr kv))))
             id))
    (t (list (format "%s" id))))
   (and entry
        (cons ""
              (cl-loop for col across tabulated-list-format
                       for cell across entry
                       collect (format "%-14s %s" (car col)
                                       (if (consp cell) (car cell) cell)))))))

(defun gascity-tabulated--detail-window ()
  "Return the live window showing the detail buffer of this list, or nil."
  (let ((buf (get-buffer (gascity-remote-buffer-name
                          gascity-tabulated-detail-buffer-name))))
    (and buf (get-buffer-window buf))))

(defun gascity-tabulated-detail-show ()
  "Show the row at point in the `*gascity-detail*' side window (`C-o').
The list keeps focus, like `C-o' in occur, compilation and Dired."
  (interactive)
  (let ((id (tabulated-list-get-id))
        (entry (tabulated-list-get-entry)))
    (unless id (user-error "No row at point"))
    (let ((buf (get-buffer-create (gascity-remote-buffer-name
                                   gascity-tabulated-detail-buffer-name)))
          (lines (gascity-tabulated--detail-lines id entry)))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (string-join lines "\n") "\n")
          (goto-char (point-min)))
        (special-mode))
      (display-buffer buf '((display-buffer-in-side-window)
                            (side . right) (window-width . 0.4))))))

(defun gascity-tabulated-detail-toggle ()
  "Toggle the `*gascity-detail*' side window for the row at point (SPC)."
  (interactive)
  (let ((win (gascity-tabulated--detail-window)))
    (if win
        (delete-window win)
      (gascity-tabulated-detail-show))))

(defun gascity-tabulated--detail-follow ()
  "Update an open detail window to the row at point (follow mode)."
  (when (and (gascity-tabulated--detail-window) (tabulated-list-get-id))
    (gascity-tabulated-detail-show)))

(define-minor-mode gascity-tabulated-detail-follow-mode
  "Make the `*gascity-detail*' window follow point in this list (`C-c C-f').
The counterpart of `next-error-follow-minor-mode'."
  :lighter " Fol"
  (if gascity-tabulated-detail-follow-mode
      (add-hook 'post-command-hook #'gascity-tabulated--detail-follow nil t)
    (remove-hook 'post-command-hook #'gascity-tabulated--detail-follow t)))

(defun gascity-tabulated-quit ()
  "Close the detail window when one is open, else bury the list (`q')."
  (interactive)
  (let ((win (gascity-tabulated--detail-window)))
    (if win
        (delete-window win)
      (quit-window))))

;;; Filter menus (dashboard-v3 §5.5)
;;
;; Every list keeps its filter as a plist of command initargs in its own
;; buffer-local variable.  `gascity-tabulated--install-filter' points the
;; shared `/' menu plumbing (`gascity-filter-*' in gascity-ui) at that
;; variable and the list's refresh command, so a suffix applies its
;; change at once, and `x' clears everything.

(defun gascity-tabulated--plist-drop (plist key)
  "Return a copy of PLIST without KEY."
  (cl-loop for (k v) on plist by #'cddr
           unless (eq k key) append (list k v)))

(defun gascity-tabulated--install-filter (var refresh)
  "Wire this list's `/' menu to filter variable VAR and command REFRESH.
VAR names the list's buffer-local filter plist; REFRESH re-reads the
list.  Run from each list mode's body (after `kill-all-local-variables')."
  (setq-local gascity-filter-get-function
              (lambda (key) (plist-get (symbol-value var) key)))
  (setq-local gascity-filter-set-function
              (lambda (key value)
                (set var (if value
                             (plist-put (copy-sequence (symbol-value var))
                                        key value)
                           (gascity-tabulated--plist-drop
                            (symbol-value var) key)))
                (funcall refresh)))
  (setq-local gascity-filter-reset-function
              (lambda () (set var nil) (funcall refresh))))

(defun gascity-tabulated--sort-description ()
  "Describe the active sort column for the `-S' suffix."
  (gascity-filter-describe
   "sort by…"
   (and (car tabulated-list-sort-key)
        (format "%s%s" (car tabulated-list-sort-key)
                (if (cdr tabulated-list-sort-key) " ↓" "")))
   "none"))

(transient-define-suffix gascity-tabulated-sort-by ()
  "Sort the whole list by a column chosen by name (the `/ -S' suffix).
Choosing the active column again flips its direction."
  :transient t
  :description #'gascity-tabulated--sort-description
  (interactive)
  (let* ((columns (cl-loop for col across tabulated-list-format
                           when (nth 2 col) collect (car col)))
         (column (completing-read "Sort by: " columns nil t)))
    (gascity-tabulated-sort
     (cl-position column tabulated-list-format :key #'car :test #'equal))))

;;; ============================================================
;;; Rigs
;;; ============================================================

(defconst gascity-rig-list-buffer-name "*gascity-rigs*")

(defvar-local gascity-rig-list--filter nil
  "Active rig-list filter as command initargs (e.g. (:status \"running\")), or nil.")

(defun gascity-rig-list--status (rig)
  "Return a propertized status cell for RIG (a `gascity-rig')."
  (propertize (gascity-rig-status-label rig)
              'face (gascity-section-state-face (gascity-rig-running rig)
                                                (gascity-rig-suspended rig))))

(defun gascity-rig-list--match-p (rig status)
  "Return non-nil when RIG (a `gascity-rig') matches STATUS (nil matches all)."
  (or (null status)
      (string= status (gascity-rig-status-label rig))))

(defun gascity-rig-list--entry (rig)
  "Map RIG (a `gascity-rig') to a tabulated-list entry.
The entry id is the typed rig, so `RET'/`d'/`b' act on it."
  (list rig
        (vector (gascity-tabulated--str (gascity-rig-name rig))
                (gascity-tabulated--str (gascity-rig-prefix rig))
                (gascity-rig-list--status rig)
                ;; A nil default-branch renders as "—" for every rig: the
                ;; HQ-only "—" left non-HQ rigs an empty cell for the same
                ;; value (ga-1kdu, bright-lights dogfood §2).
                (gascity-tabulated--str (or (gascity-rig-default-branch rig) "—"))
                (gascity-tabulated--str (gascity-rig-store rig)))))

(defun gascity-rig-list-dired ()
  "Open Dired on the path of the rig at point.
The rig's `path' is host-local (as gc reports it); for a remote city it
is re-prefixed so Dired opens it on the city's host."
  (interactive)
  (let* ((rig (tabulated-list-get-id))
         (path (gascity-remote-localize-path
                (and (gascity-rig-p rig) (gascity-rig-path rig)))))
    (if (and path (file-directory-p path))
        (dired path)
      (user-error "No rig directory at point"))))

(defun gascity-rig-list-refresh ()
  "Refresh the rig list, applying the current filter.
Asynchronous (`gascity-tabulated--refresh-async'): the list stays
responsive while `gc rig list' runs, remotely too."
  (interactive)
  (let ((cmd (apply #'gascity-command-rig-list gascity-rig-list--filter)))
    (gascity-tabulated--refresh-async
     "Rigs" cmd
     (lambda (payload)
       (let ((rigs (gascity-rigs-remember
                    (gascity-domain-decode-list 'gascity-rig
                                                (alist-get 'rigs payload)))))
         (mapcar #'gascity-rig-list--entry
                 (seq-filter (lambda (r)
                               (gascity-rig-list--match-p r (oref cmd status)))
                             rigs))))
     gascity-rig-list--filter)))

(gascity-filter-define-choice gascity-rig-list-filter-state
  :status "state" '("running" "suspended" "stopped"))

(beads-define-prefix gascity-rig-list-filter ()
  "Filter the rig list; each change applies at once (§5.5)."
  ["Filter rigs"
   ("-s" gascity-rig-list-filter-state)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

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
        ;; "Store", not "Beads": the cell renders `gc rig list''s `beads'
        ;; field, which is the bead store's STATUS string ("initialized")
        ;; for every rig, not a count.  A "Beads" header implied a count it
        ;; never showed; "Store" reads the value as the status it is (gce-79f).
        [("Name" 24 t) ("Prefix" 8 t) ("Status" 11 t)
         ("Branch" 14 t) ("Store" 12 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "Name" nil))
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things)
  (gascity-tabulated--install-filter 'gascity-rig-list--filter
                                     #'gascity-rig-list-refresh))

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

(defun gascity-session-list--entry (session socket)
  "Map SESSION (a `gascity-session') to a tabulated-list entry on tmux SOCKET.
The entry id is the agent action object (`gascity-agent', built by
`gascity-agent-from-session'), so the d/t/RET action keys act on it."
  (let* ((state (gascity-tabulated--str (gascity-session-state session)))
         (running (gascity-session-running-p session)))
    (list (gascity-agent-from-session session socket)
          (vector (gascity-tabulated--str (gascity-session-qualified-name session))
                  (gascity-tabulated--str (gascity-session-rig session))
                  (propertize state 'face
                              (gascity-section-state-face running nil))
                  (gascity-tabulated--str (gascity-session-provider session))
                  (gascity-tabulated--abbreviate-path
                   (gascity-session-work-dir session))))))

(defun gascity-session-list--match-p (session rig)
  "Return non-nil when SESSION's rig contains RIG (nil/empty matches all).
SESSION is a `gascity-session'; RIG is matched case-insensitively as a
substring of its `rig'."
  (or (null rig) (string-empty-p rig)
      (let ((case-fold-search t))
        (string-match-p (regexp-quote rig)
                        (gascity-tabulated--str (gascity-session-rig session))))))

;;; Auto-refresh failure hygiene (ga-eyw9)
;;
;; The incident this closes: over a flaky TRAMP link, seven identical
;; \"no such directory\" echoes in ~35s — one per auto-refresh tick —
;; while the city itself was intact.  The hygiene: one visible error
;; per distinct failure message, a failure counter in the mode line
;; \(`gascity-tabulated--stale-errors'), and an exponential tick
;; backoff (1, 2, 4 … capped at `gascity-session-list--backoff-max-ticks'
;; ticks, i.e. interval × 6) so a wedged link is probed ever more
;; rarely instead of once per tick.  A successful refresh heals
;; silently; a manual `g' resets everything.

(defconst gascity-session-list--backoff-max-ticks 6
  "Auto-refresh backoff ceiling, in ticks.
At the 5s default interval the pause tops out at 30s = interval × 6.")

(defvar-local gascity-session-list--refresh-failures 0
  "Consecutive failed refreshes of this session-list buffer.
Drives the backoff exponent and the stale marker; cleared on success
or by a manual `g'.")

(defvar-local gascity-session-list--refresh-backoff 0
  "Auto-refresh ticks still to skip before the next attempt.
Armed by `gascity-session-list--note-refresh-error', consumed by the
timer tick, cleared by success or a manual `g'.")

(defvar-local gascity-session-list--last-error nil
  "The failure message currently deduped, or nil.
A new distinct message is echoed once; repeats of the same one only
count (ga-eyw9: seven identical echoes for one episode).")

(defun gascity-session-list--note-refresh-error (msg)
  "Record a failed refresh (errback message MSG) in the current buffer.
First failure of an episode — or a changed message — is echoed once;
repeats of the same message are silent, only bumping the counters and
the mode-line stale marker.  Arms the backoff: the tick then skips
1, 2, 4 … ticks, capped at `gascity-session-list--backoff-max-ticks'."
  (cl-incf gascity-session-list--refresh-failures)
  (setq gascity-session-list--refresh-backoff
        (min (ash 1 (1- gascity-session-list--refresh-failures))
             gascity-session-list--backoff-max-ticks)
        gascity-tabulated--stale-errors gascity-session-list--refresh-failures)
  (unless (equal msg gascity-session-list--last-error)
    (setq gascity-session-list--last-error msg)
    (message "gascity: %s" msg)))

(defun gascity-session-list--clear-refresh-errors ()
  "Clear the session list's failure/backoff state in the current buffer.
The success half of the hygiene — a refresh that works again heals the
view silently, no banner, no message — and also what a manual `g'
runs first: the user driving resets the backoff outright."
  (setq gascity-session-list--refresh-failures 0
        gascity-session-list--refresh-backoff 0
        gascity-session-list--last-error nil
        gascity-tabulated--stale-errors nil))

(defun gascity-session-list-refresh (&optional from-auto-refresh)
  "Refresh the session list, applying the current filter.
The `state' filter is sent to `gc' (`--state'); the `rig' filter is
applied client-side to the decoded rows.  Asynchronous
\(`gascity-tabulated--refresh-async'), so the seconds a remote `gc
session list' takes never freeze the UI.

FROM-AUTO-REFRESH non-nil (the timer tick) engages the failure hygiene
\(`gascity-session-list--note-refresh-error'): consecutive identical
errors are echoed once, counted in the mode line, and back off the
timer.  A manual `g' (nil) resets all of that state — the user driving
outranks the backoff — and also clears the stale marker."
  (interactive)
  (unless from-auto-refresh
    (gascity-session-list--clear-refresh-errors))
  (let ((cmd (apply #'gascity-command-session-list gascity-session-list--filter))
        ;; Resolve the tmux socket once per refresh — it is constant across
        ;; rows, and `gc session list' does not carry the city name.
        ;; Resolved up front (cached after the first call) rather than in
        ;; the callback, which runs with the process buffer current.
        (socket (gascity-resolve-tmux-socket)))
    (gascity-tabulated--refresh-async
     "Sessions" cmd
     (lambda (payload)
       (let ((sessions (gascity-domain-decode-list
                        'gascity-session (alist-get 'sessions payload))))
         (mapcar (lambda (s) (gascity-session-list--entry s socket))
                 (seq-filter (lambda (s)
                               (gascity-session-list--match-p s (oref cmd rig)))
                             sessions))))
     gascity-session-list--filter
     ;; Auto-refresh error hygiene (ga-eyw9): dedupe + backoff on
     ;; failure, silent self-heal on success.
     #'gascity-session-list--note-refresh-error
     #'gascity-session-list--clear-refresh-errors)))

;;; Auto-refresh timer
;;
;; Mirrors the status dashboard's auto-refresh (gascity-status.el): a
;; buffer-local repeating timer re-runs `gascity-session-list-refresh'
;; on an interval, but only while the buffer is displayed in a visible
;; window and no async read is already in flight — a buried list must
;; not poll `gc', and a tick during an in-flight read would delete and
;; restart that fetch (`gascity-tabulated--refresh-async' supersedes),
;; so a link slower than the interval would never complete a read.  The
;; TRAMP guards match the dashboard tick exactly.

(defvar-local gascity-session-list--refresh-timer nil
  "Repeating timer auto-refreshing this session-list buffer, or nil.")

(defun gascity-session-list--auto-refresh-tick (buffer)
  "Refresh the session list in BUFFER, but only while it is visible and idle.
Timer callback.  Skips when BUFFER is buried or its frame invisible, when
its TRAMP connection is mid-operation (`gascity-remote-connection-locked-p'
— a timer firing inside another TRAMP call's `accept-process-output' would
signal \"Forbidden reentrant call of Tramp\"; the lock is read off the
list's OWN pinned `default-directory', since the timer runs with whatever
buffer is current), or when an async refresh is still in flight (the live
`gascity-tabulated--refresh-process'; starting one supersedes the pending
fetch).  `non-essential' is bound so the timer can never make TRAMP
establish a NEW connection — after a dropped link the tick degrades to
an error line and a manual `g' reconnects.

A failed episode backs the tick off (skip 1, 2, 4 … ticks, capped at
`gascity-session-list--backoff-max-ticks', ga-eyw9): a wedged link is
probed ever more rarely, and each skipped tick only decrements the
backoff counter.  A manual `g' resets it."
  (when (and (buffer-live-p buffer)
             (get-buffer-window buffer 'visible)
             (not (gascity-remote-connection-locked-p
                   (buffer-local-value 'default-directory buffer)))
             (not (gascity-tabulated-refresh-pending-p buffer)))
    (let ((non-essential t))
      (with-current-buffer buffer
        (if (> gascity-session-list--refresh-backoff 0)
            ;; Backing off after failures: spend this tick on the pause
            ;; instead of another doomed `gc session list'.
            (cl-decf gascity-session-list--refresh-backoff)
          (gascity-session-list-refresh 'auto))))))

(defun gascity-session-list--auto-refresh-teardown ()
  "Cancel the current buffer's auto-refresh timer.
Run from `kill-buffer-hook' so a killed list leaves no live timer."
  (when (timerp gascity-session-list--refresh-timer)
    (cancel-timer gascity-session-list--refresh-timer))
  (setq gascity-session-list--refresh-timer nil))

(defun gascity-session-list--auto-refresh-setup (&optional buffer)
  "Start BUFFER's auto-refresh timer per `gascity-session-list-auto-refresh'.
BUFFER defaults to the current buffer.  Idempotent: cancels any existing
timer first, so re-running never leaks a second one.  Creates a repeating
timer only when `gascity-session-list-auto-refresh' is non-nil and
`gascity-session-list-auto-refresh-interval' is a positive number;
otherwise the list stays manual-refresh only.  When a timer is created,
arrange teardown on `kill-buffer-hook' so it dies with the buffer."
  (with-current-buffer (or buffer (current-buffer))
    (when (timerp gascity-session-list--refresh-timer)
      (cancel-timer gascity-session-list--refresh-timer))
    (setq gascity-session-list--refresh-timer nil)
    (when (and gascity-session-list-auto-refresh
               (numberp gascity-session-list-auto-refresh-interval)
               (> gascity-session-list-auto-refresh-interval 0))
      (setq gascity-session-list--refresh-timer
            (run-with-timer gascity-session-list-auto-refresh-interval
                            gascity-session-list-auto-refresh-interval
                            #'gascity-session-list--auto-refresh-tick
                            (current-buffer)))
      (add-hook 'kill-buffer-hook
                #'gascity-session-list--auto-refresh-teardown nil t))))

(defun gascity-session-list-toggle-auto-refresh ()
  "Toggle automatic refresh of the GC-Sessions list.
Flips `gascity-session-list-auto-refresh' and (re)starts or cancels the
current buffer's refresh timer to match.  While on, the list re-reads
`gc session list' every `gascity-session-list-auto-refresh-interval'
seconds whenever its buffer is visible."
  (interactive)
  (setq gascity-session-list-auto-refresh (not gascity-session-list-auto-refresh))
  (gascity-session-list--auto-refresh-setup)
  (message "Session list auto-refresh %s"
           (if gascity-session-list-auto-refresh
               (format "on (every %ss while visible)"
                       gascity-session-list-auto-refresh-interval)
             "off")))

(gascity-filter-define-choice gascity-session-list-filter-state
  :state "state" '("active" "suspended" "closed" "all"))

(gascity-filter-define-choice gascity-session-list-filter-rig
  :rig "rig" (mapcar #'gascity-rig-name (gascity-rigs-cached)))

(beads-define-prefix gascity-session-list-filter ()
  "Filter the session list; each change applies at once (§5.5)."
  ["Filter sessions"
   ("-s" gascity-session-list-filter-state)
   ("-r" gascity-session-list-filter-rig)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

(defvar-keymap gascity-session-list-mode-map
  :doc "Keymap for `gascity-session-list-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-session-list-refresh
  ;; `W' (watch) toggles auto-refresh; `G' is taken by pagination
  ;; (goto-page on `gascity-tabulated-base-map'), unlike the status
  ;; dashboard where `G' is free for the toggle.
  "W"   #'gascity-session-list-toggle-auto-refresh
  "/"   #'gascity-session-list-filter
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  "RET" #'gascity-tmux-at-point
  "i"   #'gascity-polecat-detail-at-point
  ;; Nudge is `M' (Message) here too, matching the vui dashboards where
  ;; `N' became next-section; this flat list has no sections, so `N'/`P'
  ;; are simply unbound (it does not inherit `gascity-section-mode-map').
  "M"   #'gascity-session-nudge-at-point
  "s"   #'gascity-session-suspend-at-point
  "K"   #'gascity-session-kill-at-point
  "w"   #'gascity-session-wake-at-point
  "D"   #'gascity-session-drain-at-point
  ;; Write verbs (DESIGN-write-actions.md phase 1): reset/undrain at point.
  "R"   #'gascity-session-reset-at-point
  "U"   #'gascity-session-undrain-at-point
  ;; `S' sling-dispatch, matching the status dashboard, rig dashboard and
  ;; session detail (the bright-lights dogfood pass, ga-hirj: the flat list
  ;; was the only agent view where `S' was unbound, so dispatching a bead
  ;; from the session list meant hunting for another view).
  "S"   #'gascity-sling-dispatch
  ;; This flat list has no sections, so unlike the vui dashboards (which
  ;; inherit `n'/`p' from `gascity-section-mode-map') it binds line movement
  ;; locally.  Peek moves off `p' to `v' so `p' can mean previous-line.
  "n"   #'next-line
  "p"   #'previous-line
  "v"   #'gascity-session-peek-at-point)

(define-derived-mode gascity-session-list-mode tabulated-list-mode "GC-Sessions"
  "Major mode listing the city's agent sessions.
RET (or t) attaches to the session's tmux session — the primary
action; `i' opens the session/polecat detail view; `d' opens its
worktree in Dired.  `M' nudges (sends a message), `s' suspends, `K'
force-kills the runtime of, `w' wakes, `D' drains, and `v' peeks at the
output of the session at point.  `S' opens the unified sling-dispatch
transient for the session at point.  `n'/`p' move by line.  When
`gascity-session-list-auto-refresh' is on (the default), the list
re-reads `gc' every `gascity-session-list-auto-refresh-interval' seconds
while visible; `W' toggles that live.
\\{gascity-session-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("Agent" 40 t) ("Rig" 14 t) ("State" 9 t)
         ("Provider" 9 t) ("Working dir" 40 t)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key (cons "Agent" nil))
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things)
  (gascity-tabulated--install-filter 'gascity-session-list--filter
                                     #'gascity-session-list-refresh)
  (gascity-session-list--auto-refresh-setup))

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
  "Return non-nil when CONVOY (a `gascity-convoy') matches STATUS.
A nil STATUS matches every convoy."
  (or (null status)
      (string= status (gascity-tabulated--str (gascity-convoy-status convoy)))))

(defun gascity-convoy-list--entry (convoy)
  "Map CONVOY (a `gascity-convoy') to a tabulated-list entry.
The entry id is the typed convoy, so `RET' can open it (by bead id) in
beads.el."
  (let* ((progress (gascity-convoy-progress convoy))
         (closed (or (and progress (gascity-progress-closed progress)) 0))
         (total (or (and progress (gascity-progress-total progress)) 0)))
    (list convoy
          (vector (gascity-tabulated--str (gascity-convoy-id convoy))
                  (gascity-tabulated--str (gascity-convoy-title convoy))
                  (gascity-tabulated--str (gascity-convoy-status convoy))
                  (format "%d/%d" closed total)))))

(cl-defmethod gascity-at-point-visit ((convoy gascity-convoy))
  "Visit CONVOY: open its bead in beads.el, scoped to its store.
Convoys are city-level beads (`rig: null') listed via `gc convoy list';
`gascity-bead-show' resolves the owning rig store by id prefix and opens it
with `bd --directory' (-C), which works even when the shared Dolt server
would misroute the working directory to another database (gce-bhr)."
  (gascity-bead-show (gascity-convoy-id convoy)))

(defun gascity-convoy-list-visit ()
  "Open the convoy bead at point in beads.el, scoped to its store."
  (interactive)
  (let ((convoy (tabulated-list-get-id)))
    (if (gascity-convoy-p convoy)
        (gascity-at-point-visit convoy)
      (user-error "No convoy at point"))))

(defun gascity-convoy-list-refresh ()
  "Refresh the convoy list, applying the current filter.
Asynchronous (`gascity-tabulated--refresh-async')."
  (interactive)
  (let ((cmd (apply #'gascity-command-convoy-list gascity-convoy-list--filter)))
    (gascity-tabulated--refresh-async
     "Convoys" cmd
     (lambda (payload)
       (let ((convoys (gascity-domain-decode-list
                       'gascity-convoy (alist-get 'convoys payload))))
         (mapcar #'gascity-convoy-list--entry
                 (seq-filter (lambda (c)
                               (gascity-convoy-list--match-p c (oref cmd status)))
                             convoys))))
     gascity-convoy-list--filter)))

(gascity-filter-define-choice gascity-convoy-list-filter-state
  :status "state" '("open" "closed"))

(beads-define-prefix gascity-convoy-list-filter ()
  "Filter the convoy list; each change applies at once (§5.5)."
  ["Filter convoys"
   ("-s" gascity-convoy-list-filter-state)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

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
  (gascity-tabulated--install-filter 'gascity-convoy-list--filter
                                     #'gascity-convoy-list-refresh)
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things))

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
  "Return non-nil when MESSAGE (a `gascity-mail') is unread.
`gc mail inbox --json' gives each message a required boolean `read' field
\(v1 `mail_message' schema); unread is its negation.  JSON `false' decodes
to nil (see `gascity-reader-parse-json'), so an unread message reads nil."
  (not (gascity-mail-read message)))

(defun gascity-mail-inbox--match-p (message unread)
  "Return non-nil when MESSAGE (a `gascity-mail') passes the UNREAD-only filter.
A nil UNREAD keeps every message."
  (or (not unread) (gascity-mail-inbox--unread-p message)))

(defun gascity-mail-inbox--entry (message)
  "Map MESSAGE (a `gascity-mail') to a tabulated-list entry.
Columns follow the `gc mail inbox --json' v1 `mail_message' schema —
`from', `subject', `created_at', and the boolean `read' (for the unread
marker).  The entry id is the typed message, so `RET' can show every field."
  (list message
        (vector (gascity-tabulated--str (gascity-mail-from message))
                (gascity-tabulated--str (gascity-mail-subject message))
                (gascity-ui-time (gascity-mail-created-at message))
                (if (gascity-mail-inbox--unread-p message) "●" ""))))

(cl-defmethod gascity-at-point-visit ((message gascity-mail))
  "Visit MESSAGE: show its typed fields in a read-only view buffer.
Renders the data already fetched, without contacting `gc'; each slot of the
`gascity-mail' is shown as \"slot: value\".  The buffer is keyed and
pinned to the inbox's city (`gascity-view-get-buffer-create'), so a
remote city's message view carries that host's `default-directory'."
  (let ((buf (gascity-view-get-buffer-create "*gascity-mail-message*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (slot (beads-meta-command-slots 'gascity-mail))
          (insert (format "%-14s %s\n"
                          (concat (symbol-name slot) ":")
                          (gascity-tabulated--str (slot-value message slot)))))
        (goto-char (point-min)))
      (view-mode 1))
    (pop-to-buffer buf)))

(defun gascity-mail-inbox-show ()
  "Show the fields of the mail message at point in a view buffer."
  (interactive)
  (let ((message (tabulated-list-get-id)))
    (if (gascity-mail-p message)
        (gascity-at-point-visit message)
      (user-error "No message at point"))))

(defun gascity-mail-inbox-refresh ()
  "Refresh the mail inbox, applying the current filter.
Asynchronous (`gascity-tabulated--refresh-async')."
  (interactive)
  (let ((cmd (apply #'gascity-command-mail-inbox gascity-mail-inbox--filter)))
    (gascity-tabulated--refresh-async
     "Mail" cmd
     (lambda (payload)
       (let ((messages (gascity-domain-decode-list
                        'gascity-mail (alist-get 'messages payload))))
         (mapcar #'gascity-mail-inbox--entry
                 (seq-filter (lambda (m)
                               (gascity-mail-inbox--match-p m (oref cmd unread)))
                             messages))))
     gascity-mail-inbox--filter)))

(gascity-filter-define-toggle gascity-mail-inbox-filter-unread
  :unread "unread only")

(beads-define-prefix gascity-mail-inbox-filter ()
  "Filter the mail inbox; each change applies at once (§5.5)."
  ["Filter mail"
   ("-u" gascity-mail-inbox-filter-unread)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

(defvar-keymap gascity-mail-inbox-mode-map
  :doc "Keymap for `gascity-mail-inbox-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-mail-inbox-refresh
  "/"   #'gascity-mail-inbox-filter
  "RET" #'gascity-mail-inbox-show
  ;; Write verbs.  `RET' stays the cheap, gc-free field view; `r' is the
  ;; gc-contacting read (shows the body and marks read).  `a' archives
  ;; (confirmed); `u' marks unread.  Phase 2 adds `R' reply (compose) and
  ;; `c' for the mail-dispatch menu (which also exposes send).
  "r"   #'gascity-mail-read-at-point
  "R"   #'gascity-mail-reply-at-point
  "a"   #'gascity-mail-archive-at-point
  "u"   #'gascity-mail-mark-unread-at-point
  "c"   #'gascity-mail-dispatch)

(define-derived-mode gascity-mail-inbox-mode tabulated-list-mode "GC-Mail"
  "Major mode showing the current agent's mail inbox.
`RET' shows the cached message fields; `r' reads it via gc (shows the body,
marks read); `a' archives (confirmed); `u' marks unread.
\\{gascity-mail-inbox-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        `[("From" 24 t) ("Subject" 50 t)
          ("When" 10 ,(gascity-tabulated--time-sorter 2))
          ("New" 3 nil)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key nil)
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things)
  (gascity-tabulated--install-filter 'gascity-mail-inbox--filter
                                     #'gascity-mail-inbox-refresh))

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
ORDER is a `gascity-order'.  ENABLED non-nil keeps only enabled orders;
TYPE (when non-empty) keeps only orders whose `type' matches it exactly.
Nil/empty values match every order."
  (and (or (not enabled) (and (gascity-order-enabled order) t))
       (or (null type) (string-empty-p type)
           (string= type (gascity-tabulated--str (gascity-order-type order))))))

(defun gascity-order-list--entry (order)
  "Map ORDER (a `gascity-order') to a tabulated-list entry.
The entry id is the typed order, so `RET' can open its source."
  (list order
        (vector (gascity-tabulated--str (gascity-order-display-name order))
                (gascity-tabulated--str (gascity-order-rig order))
                (gascity-tabulated--str (gascity-order-type order))
                (gascity-tabulated--str (gascity-order-trigger order))
                (gascity-tabulated--str (gascity-order-cadence order))
                (if (gascity-order-enabled order) "●" ""))))

(cl-defmethod gascity-at-point-visit ((order gascity-order))
  "Visit ORDER: open its source file.
The `source' path is host-local (as gc reports it); for a remote city it
is re-prefixed so the file opens on the city's host."
  (let ((source (gascity-remote-localize-path (gascity-order-source order))))
    (if (and source (file-readable-p source))
        (find-file source)
      (user-error "No readable source for the order at point"))))

(defun gascity-order-list-visit ()
  "Open the source file of the order at point."
  (interactive)
  (let ((order (tabulated-list-get-id)))
    (if (gascity-order-p order)
        (gascity-at-point-visit order)
      (user-error "No order at point"))))

(defun gascity-order-list-refresh ()
  "Refresh the order list, applying the current filter.
Asynchronous (`gascity-tabulated--refresh-async')."
  (interactive)
  (let ((cmd (apply #'gascity-command-order-list gascity-order-list--filter)))
    (gascity-tabulated--refresh-async
     "Orders" cmd
     (lambda (payload)
       (let ((orders (gascity-domain-decode-list
                      'gascity-order (alist-get 'orders payload))))
         (mapcar #'gascity-order-list--entry
                 (seq-filter (lambda (o)
                               (gascity-order-list--match-p
                                o (oref cmd enabled) (oref cmd type)))
                             orders))))
     gascity-order-list--filter)))

(gascity-filter-define-toggle gascity-order-list-filter-enabled
  :enabled "enabled only")

(gascity-filter-define-choice gascity-order-list-filter-type
  :type "type" '("exec" "formula"))

(beads-define-prefix gascity-order-list-filter ()
  "Filter the order list; each change applies at once (§5.5)."
  ["Filter orders"
   ("-e" gascity-order-list-filter-enabled)
   ("-t" gascity-order-list-filter-type)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

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
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things)
  (gascity-tabulated--install-filter 'gascity-order-list--filter
                                     #'gascity-order-list-refresh))

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
  "Refresh the Dolt database list (from `gc dolt health').
Asynchronous (`gascity-tabulated--refresh-async')."
  (interactive)
  (gascity-tabulated--refresh-async
   "Dolt" (gascity-command-dolt-health)
   (lambda (payload)
     (mapcar #'gascity-dolt-list--entry
             (gascity-tabulated--vector->list
              (alist-get 'databases payload))))))

(beads-define-prefix gascity-dolt-list-filter ()
  "Sort the Dolt database list (§5.5: `/' is the one menu in every view)."
  ["Dolt databases"
   ("-S" gascity-tabulated-sort-by)])

(defvar-keymap gascity-dolt-list-mode-map
  :doc "Keymap for `gascity-dolt-list-mode'.
Dolt has no filter dimension, so its `/' menu only sorts; pagination
\(`]'/`['/`G') comes from the parent map."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-dolt-list-refresh
  "/"   #'gascity-dolt-list-filter
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
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things))

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
