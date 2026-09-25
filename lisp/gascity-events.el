;;; gascity-events.el --- The Events view: gc events, churn folded -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; `gascity-events' (dashboard-v3 §7.8): the city's `gc events' for a
;; time window, newest first, in a tabulated list
;; (`*gascity-events: CITY*').
;;
;;    Time   Sig  Type                          Subject        Detail
;;    14:44       order.fired/completed ×124    3 orders       …
;;    13:03  ■    session.cold_start_timeout    gc__…-ec-rn5e  session …
;;    11:03  ▲    bead.dead_assignee_reopened   be-3z6o        reopened …
;;
;; About 95% of a quiet city's events are churn (order firings, wisp
;; lifecycle); they fold into one `×N' row per group per time bucket,
;; with the same rules as the cockpit's Activity section (the shared
;; event model in `gascity-event').  Signal events (■ attention, ▲
;; watch; `gascity-event-levels') never fold.
;;
;; Keys: SPC on a `×N' row unfolds it in place, on an event row it shows
;; the event's fields in the `*gascity-detail*' side window (§5.4
;; tabulated convention); RET drills in — a bead subject opens in
;; beads.el scoped to its store, a session subject opens the agent's
;; detail, a `×N' row narrows the view to that churn group; `/' filters
;; (window, type, actor, signal level, unfold churn, search; the state
;; shows in the header line); `W' toggles live; `g' re-reads.
;;
;; Reads go through the store (`gascity-store-fetch', `:lines': gc
;; events has no --json flag, it always prints JSON Lines).  The type
;; filter is server-side (`--type'), everything else filters the rows
;; in hand.  The city's live stream (`gascity-live') feeds raw events
;; to `gascity-events--append': the view appends, it never re-reads.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)
(require 'transient)
(require 'beads-prefix)
(require 'beads-pager)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-event)
(require 'gascity-context)
(require 'gascity-store)
(require 'gascity-live)                 ; raw events appended live (§8.2)
(require 'gascity-domain)
(require 'gascity-section)
(require 'gascity-tabulated)

(declare-function gascity-polecat-detail "gascity-session")

;;; State

(defconst gascity-events-buffer-name "*gascity-events: %s*"
  "Format of the Events buffer's base name; %s is the city name.")

(defconst gascity-events-windows '("1h" "2h" "24h" "7d")
  "The window choices of the `-W' filter (any gc duration is accepted).")

(defconst gascity-events-levels '("attention" "watch" "event")
  "The `-l' signal-level choices, most severe first.")

(defvar-local gascity-events--city nil
  "The city name this Events buffer shows.")

(defvar-local gascity-events--filter nil
  "The view's filter plist.
Keys: `:window' (a duration; nil = `gascity-events-window'), `:type'
\(server-side `--type'), `:actor', `:level' (\"attention\" or
\"watch\": that level or worse), `:unfold' (no churn folding),
`:search' (a substring of type, subject, message or actor) and
`:group' (only one churn group, unfolded — set by RET on a `×N' row).")

(defvar-local gascity-events--events nil
  "The events in hand, oldest first (the order gc prints them).")

(defvar-local gascity-events--status 'loading
  "Where the read stands: `loading', `ready', or (error . MESSAGE).")

(defvar-local gascity-events--generation 0
  "Stamp of the latest read; an older read's answer is dropped.")

(defvar-local gascity-events--expanded nil
  "Keys of the `×N' rows unfolded in place (view state, survives refresh).")

(defvar-local gascity-events--shown 0
  "Events that passed the filter at the last render.")

(defvar-local gascity-events--folded 0
  "Events folded into `×N' rows at the last render.")

(defvar-local gascity-events--queue nil
  "Live events waiting for the next append flush, newest first.")

(defvar-local gascity-events--flush-timer nil
  "The debounce timer of pending live appends.")

(defvar-local gascity-events--live nil
  "The live subscription handle, or nil.")

(defvar gascity-events-append-delay 0.5
  "Seconds live events are gathered before the view re-renders.")

;;; Model (pure)

(defun gascity-events--window ()
  "Return the view's window."
  (or (plist-get gascity-events--filter :window) gascity-events-window))

(defun gascity-events--args (filter)
  "Return the `gc events' argv for FILTER."
  (append (list "events" "--since"
                (gascity-event-since-arg
                 (or (plist-get filter :window) gascity-events-window)))
          (let ((type (plist-get filter :type)))
            (and type (list "--type" type)))))

(defun gascity-events--bucket (window)
  "Return the churn bucket in seconds for WINDOW.
A quarter hour up to two hours (as the cockpit), an hour up to a day,
six hours beyond — so a week of order churn stays a few dozen rows."
  (let ((seconds (gascity-ui-duration-seconds window)))
    (cond ((<= seconds 7200) 900)
          ((<= seconds 86400) 3600)
          (t 21600))))

(defun gascity-events--level-rank (level)
  "Return the severity rank of signal LEVEL: 2 attention, 1 watch, 0."
  (pcase level ('attention 2) ('watch 1) (_ 0)))

(defun gascity-events--match-p (event filter)
  "Return non-nil when EVENT passes the client-side part of FILTER."
  (let ((actor (plist-get filter :actor))
        (level (plist-get filter :level))
        (search (plist-get filter :search))
        (group (plist-get filter :group)))
    (and (or (null actor) (equal actor (alist-get 'actor event)))
         (or (null level)
             (>= (gascity-events--level-rank (gascity-event-level event))
                 (gascity-events--level-rank (intern level))))
         (or (null group)
             (equal group (gascity-event-churn-group event nil)))
         (or (null search)
             (let ((case-fold-search t)
                   (text (mapconcat (lambda (k) (format "%s" (or (alist-get k event) "")))
                                    '(type subject message actor)
                                    " ")))
               (string-match-p (regexp-quote search) text))))))

(defun gascity-events--rows (events filter)
  "Fold the EVENTS passing FILTER; return (ROWS SHOWN . FOLDED).
ROWS as `gascity-event-fold' returns them, newest first."
  (let* ((kept (seq-filter (lambda (e) (gascity-events--match-p e filter)) events))
         (fold-filter (if (plist-get filter :group)
                          (plist-put (copy-sequence filter) :unfold t)
                        filter))
         (model (gascity-event-fold
                 kept fold-filter
                 (gascity-events--bucket
                  (or (plist-get filter :window) gascity-events-window)))))
    (cons (car model) (cons (length kept) (cdr model)))))

(defun gascity-events--time-cell (time now)
  "Return the Time cell of TIME (a float): `HH:MM' today, else with the date.
NOW is the current time."
  (let ((ts (format-time-string "%FT%T%z" time)))
    (propertize (if (equal (format-time-string "%F" time)
                           (format-time-string "%F" now))
                    (format-time-string "%H:%M" time)
                  (format-time-string "%b %e %H:%M" time))
                'help-echo ts)))

(defun gascity-events--bead-id (event)
  "Return the bead EVENT is about, or nil.
Its payload bead, else the `bead_id' of the payload, else the subject
of a `bead.', `convoy.' or `mail.' event (a message is a bead)."
  (let ((type (or (alist-get 'type event) ""))
        (payload (alist-get 'payload event)))
    (or (alist-get 'id (gascity-event-bead event))
        (and (listp payload) (alist-get 'bead_id payload))
        (and (string-match-p "\\`\\(?:bead\\|convoy\\|mail\\)\\." type)
             (alist-get 'subject event)))))

(defun gascity-events--session-p (event)
  "Return non-nil when EVENT is about a session (and not a bead)."
  (and (not (gascity-events--bead-id event))
       (or (string-prefix-p "session." (or (alist-get 'type event) ""))
           (alist-get 'session_id event))))

(defun gascity-events--detail (event)
  "Return the Detail cell text of EVENT."
  (let ((bead (gascity-event-bead event)))
    (or (and bead (alist-get 'title bead))
        (gascity-ui-first-line (alist-get 'message event))
        "")))

(defun gascity-events--event-entry (event now &optional child)
  "Return the tabulated entry of EVENT at NOW; CHILD indents its type."
  (let ((level (gascity-event-level event)))
    (list event
          (vector (gascity-events--time-cell (gascity-event-time event) now)
                  (gascity-event-level-glyph level)
                  (let ((type (or (alist-get 'type event) "")))
                    (if child
                        (propertize (concat "  " type) 'face 'gascity-dim)
                      (if level (propertize type 'face 'bold) type)))
                  (or (and (gascity-event-bead event)
                           (alist-get 'id (gascity-event-bead event)))
                      (alist-get 'subject event)
                      "")
                  (gascity-events--detail event)))))

(defun gascity-events--churn-entry (row now)
  "Return the tabulated entry of churn ROW (churn KEY GROUP TIME EVENTS) at NOW."
  (pcase-let ((`(churn ,key ,group ,time ,events) row))
    (list row
          (vector (gascity-events--time-cell time now)
                  " "
                  (concat (if (member key gascity-events--expanded)
                              (gascity-ui-glyph 'expanded)
                            (gascity-ui-glyph 'folded))
                          " " group " "
                          (propertize (format "×%d" (length events))
                                      'face 'gascity-dim))
                  (propertize (gascity-event-churn-detail group events)
                              'face 'gascity-dim)
                  (propertize (string-join
                               (seq-take (delete-dups
                                          (delq nil (mapcar (lambda (e) (alist-get 'subject e))
                                                            events)))
                                         3)
                               ", ")
                              'face 'gascity-dim)))))

(defun gascity-events--entries (rows now)
  "Return the tabulated entries of ROWS at NOW, unfolded churn inline."
  (mapcan (lambda (row)
            (if (eq (car row) 'churn)
                (cons (gascity-events--churn-entry row now)
                      (and (member (nth 1 row) gascity-events--expanded)
                           (mapcar (lambda (e) (gascity-events--event-entry e now t))
                                   (nth 4 row))))
              (list (gascity-events--event-entry (nth 1 row) now))))
          rows))

;;; Rendering

(defun gascity-events--fit-time-column ()
  "Narrow the Time column to `HH:MM' while every row is from today."
  (let ((width (if (seq-every-p (lambda (e) (<= (string-width (aref (cadr e) 0)) 5))
                                gascity-tabulated--all-entries)
                   5 12)))
    (unless (eql width (nth 1 (aref tabulated-list-format 0)))
      (setq tabulated-list-format (copy-sequence tabulated-list-format))
      (aset tabulated-list-format 0 (list "Time" width nil))
      (tabulated-list-init-header))))

(defvar-local gascity-events--model nil
  "The last folded model, (ROWS SHOWN . FOLDED), reused by SPC.")

(defun gascity-events--render (&optional keep-page reuse)
  "Re-render the rows from the events in hand.
KEEP-PAGE stays on the current page (live appends, SPC); point stays
on the row it was on (tabulated-list's remembered position).  REUSE
keeps the last fold (SPC only changes what is unfolded; a day of
events takes a noticeable moment to fold)."
  (let* ((model (if (and reuse gascity-events--model)
                    gascity-events--model
                  (setq gascity-events--model
                        (gascity-events--rows gascity-events--events
                                              gascity-events--filter))))
         (page gascity-tabulated--current-page))
    (setq gascity-events--shown (cadr model)
          gascity-events--folded (cddr model))
    (setq gascity-tabulated--all-entries
          (gascity-events--entries (car model) (float-time))
          gascity-tabulated--base-name "Events")
    (gascity-events--fit-time-column)
    (setq gascity-tabulated--base-name "Events"
          gascity-tabulated--page-size (beads-pager-window-page-size))
    (setq gascity-tabulated--current-page
          (if keep-page (max 1 (min page (gascity-tabulated--total-pages))) 1))
    (gascity-tabulated--refresh-display)
    (force-mode-line-update)))

(defun gascity-events--filter-text ()
  "Return the active filters as `key=value' words, or nil."
  (let ((parts (cl-loop for (key value) on gascity-events--filter by #'cddr
                        unless (or (null value) (memq key '(:window :level)))
                        collect (if (eq value t)
                                    (substring (symbol-name key) 1)
                                  (format "%s=%s" (substring (symbol-name key) 1)
                                          value)))))
    (and parts (string-join parts " "))))

(defun gascity-events--header-line ()
  "Return the Events header line: city, window, count, level, filters.
Pure over buffer-local state (§8.3 R2)."
  (let* ((host (file-remote-p default-directory 'host))
         (status gascity-events--status)
         (count (pcase status
                  ('loading (propertize "…" 'face 'gascity-dim))
                  (`(error . ,msg)
                   (concat (gascity-ui-glyph 'fail) " "
                           (propertize (format "gc events: %s"
                                               (or (gascity-ui-first-line msg) "failed"))
                                       'face 'gascity-dim)))
                  (_ (number-to-string gascity-events--shown))))
         (filters (gascity-events--filter-text))
         (live (gascity-live-header-string))
         (right (concat (if (> gascity-events--folded 0)
                            (propertize (format "(%d churn folded)" gascity-events--folded)
                                        'face 'gascity-dim)
                          "")
                        (if live (concat "  " live) ""))))
    (concat " " (propertize (or gascity-events--city "?") 'face 'gascity-city)
            (if host (propertize (concat " @" host) 'face 'gascity-dim) "")
            " " (propertize "events" 'face 'gascity-header)
            "  " (propertize (format "last %s · " (gascity-events--window))
                             'face 'gascity-dim)
            count
            (propertize (format " · signal ≥ %s"
                                (or (plist-get gascity-events--filter :level) "event"))
                        'face 'gascity-dim)
            (if filters (concat "  " (propertize filters 'face 'transient-value)) "")
            (propertize " " 'display
                        `(space :align-to (- right ,(1+ (string-width right)))))
            right)))

;;; Reading

(defun gascity-events--read (args callback errback &optional force)
  "Read gc ARGS as JSON Lines through the store; CALLBACK gets (GOOD . BAD).
ERRBACK gets the failure text; FORCE re-reads a fresh entry.  The one
read call site of the view, named so tests stub it."
  (gascity-store-fetch args callback errback :lines t :force force))

(defun gascity-events-refresh (&optional force)
  "Re-read the events of this view's window (and type), then render.
Interactively (`g') the read is forced past the store's cache and a
waiting live stream is retried; FORCE likewise."
  (interactive (list t))
  (unless (derived-mode-p 'gascity-events-mode)
    (user-error "Not in an Events buffer"))
  (when force (gascity-live-reconnect))
  (let ((buffer (current-buffer))
        (generation (cl-incf gascity-events--generation)))
    (unless (eq gascity-events--status 'ready)
      (setq gascity-events--status 'loading))
    (gascity-events--read
     (gascity-events--args gascity-events--filter)
     (lambda (payload)
       (when (and (buffer-live-p buffer)
                  (= generation (buffer-local-value 'gascity-events--generation buffer)))
         (with-current-buffer buffer
           (setq gascity-events--events (car payload)
                 gascity-events--status 'ready)
           ;; Live events that arrived while the read was in flight.
           (gascity-events--merge (prog1 gascity-events--queue
                                    (setq gascity-events--queue nil)))
           (gascity-events--render))))
     (lambda (msg)
       (when (and (buffer-live-p buffer)
                  (= generation (buffer-local-value 'gascity-events--generation buffer)))
         (with-current-buffer buffer
           (setq gascity-events--status (cons 'error msg))
           (gascity-events--render)
           (force-mode-line-update))))
     force)))

;;; Live append (§8.2: the Events view appends, never re-reads)

(defun gascity-events--wanted-p (event)
  "Return non-nil when a live EVENT belongs in this view's read.
The server-side part of the filter (`:type') applies to live events
here; the rest filters at render like any other event."
  (let ((type (plist-get gascity-events--filter :type)))
    (or (null type) (equal type (alist-get 'type event)))))

(defun gascity-events--merge (events)
  "Merge EVENTS (any order) into the events in hand, oldest first.
Events already in hand (by `seq') are dropped, and events that fell
out of the window are trimmed."
  (when events
    (let* ((last (or (alist-get 'seq (car (last gascity-events--events))) -1))
           (new (sort (seq-filter (lambda (e)
                                    (let ((seq (alist-get 'seq e)))
                                      (and (numberp seq) (> seq last)
                                           (gascity-events--wanted-p e))))
                                  events)
                      (lambda (a b) (< (alist-get 'seq a) (alist-get 'seq b)))))
           (start (- (float-time)
                     (gascity-ui-duration-seconds (gascity-events--window)))))
      (setq gascity-events--events
            (seq-drop-while (lambda (e) (< (gascity-event-time e) start))
                            (append gascity-events--events
                                    (seq-uniq new (lambda (a b)
                                                    (equal (alist-get 'seq a)
                                                           (alist-get 'seq b))))))))))

(defun gascity-events--flush (buffer)
  "Merge BUFFER's queued live events and re-render it in place."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq gascity-events--flush-timer nil)
      (when (eq gascity-events--status 'ready)
        (gascity-events--merge (prog1 gascity-events--queue
                                 (setq gascity-events--queue nil)))
        (gascity-events--render t)))))

(defun gascity-events--append (events &optional buffer)
  "Append live EVENTS (event alists) to the Events view BUFFER.
The entry point of the live stream (§8.2 \"any → Events: append, no
re-read\"): BUFFER defaults to the current buffer.  Events are queued
and merged after `gascity-events-append-delay' seconds, so a burst of
order churn renders once; a read still in flight merges the queue
when it lands.  Duplicates (by `seq') and events outside the view's
type filter are dropped."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (derived-mode-p 'gascity-events-mode)
          (setq gascity-events--queue (append (reverse events) gascity-events--queue))
          (unless (timerp gascity-events--flush-timer)
            (setq gascity-events--flush-timer
                  (run-at-time gascity-events-append-delay nil
                               #'gascity-events--flush buffer))))))))

(defun gascity-events--live-setup ()
  "Join the city's live stream and append its raw events to this view.
The view never re-reads for an event batch (§8.2 \"any → Events:
append, no re-read\"); a resumed stream replays the missed events,
which the `seq' dedup absorbs."
  (unless gascity-events--live
    (let ((buffer (current-buffer)))
      (gascity-live-attach buffer)
      (setq gascity-events--live
            (gascity-live-subscribe
             (lambda (event) (gascity-events--append (list event) buffer))
             buffer)))))

(defun gascity-events--teardown ()
  "Drop the live subscription and the pending flush of this view."
  (when (timerp gascity-events--flush-timer)
    (cancel-timer gascity-events--flush-timer))
  (when gascity-events--live
    (gascity-live-unsubscribe gascity-events--live))
  (setq gascity-events--live nil))

;;; Things at point

(defun gascity-events--row ()
  "Return the id of the row at point: an event alist or a churn row."
  (tabulated-list-get-id))

(defun gascity-events--churn-p (row)
  "Return non-nil when ROW is a churn row."
  (eq (car-safe row) 'churn))

(defun gascity-events--detail-lines (row _entry)
  "Return the `*gascity-detail*' lines of ROW (§5.4)."
  (if (gascity-events--churn-p row)
      (pcase-let ((`(churn ,_key ,group ,_time ,events) row))
        (cons (format "%s ×%d %s" group (length events)
                      (gascity-event-churn-detail group events))
              (mapcar (lambda (e)
                        (format "%s  %-22s %s"
                                (gascity-ui-clock (alist-get 'ts e))
                                (alist-get 'type e)
                                (gascity-event-subject e)))
                      events)))
    (append (list (format "%-10s %s" "type" (alist-get 'type row))
                  (format "%-10s %s" "ts" (alist-get 'ts row))
                  (format "%-10s %s" "seq" (alist-get 'seq row)))
            (gascity-event-fields row))))

(defun gascity-events--toggle-churn (row)
  "Unfold churn ROW in place, or fold it again (a `beads-thing' handler).
SPC on a `×N' row lands here; any other row falls through to the
shared list handler, the `*gascity-detail*' window (§5.4).  Returns
non-nil when ROW was a churn row."
  (when (gascity-events--churn-p row)
    (let ((key (nth 1 row)))
      (setq gascity-events--expanded
            (if (member key gascity-events--expanded)
                (delete key gascity-events--expanded)
              (cons key gascity-events--expanded)))
      (gascity-events--render t t))
    t))

(defun gascity-events--open-agent (agent)
  "Open the agent detail (§7.4) of AGENT, a `gascity-agent'."
  (gascity-polecat-detail agent))

(defun gascity-events--session-row (event sessions)
  "Return the `session list' row of EVENT's session among SESSIONS, or nil.
Joins the event's `session_id' or `subject' (a session id, tmux
session name, alias or agent name) with the row's id, tmux name,
alias or qualified agent name."
  (let ((keys (delq nil (list (alist-get 'session_id event)
                              (alist-get 'subject event)))))
    (seq-find (lambda (s)
                (seq-some (lambda (k)
                            (member k (list (alist-get 'id s)
                                            (alist-get 'session_name s)
                                            (alist-get 'alias s)
                                            (alist-get 'agent_name s))))
                          keys))
              (append (alist-get 'sessions sessions) nil))))

(defun gascity-events--session-agent (event sessions)
  "Return the `gascity-agent' EVENT's session names, or nil.
A live row of SESSIONS gives the full agent (worktree, tmux name and
socket, for the detail's header and keys); a subject that is already
a qualified name gives a bare one."
  (let ((row (gascity-events--session-row event sessions))
        (subject (alist-get 'subject event)))
    (cond
     (row (gascity-agent-from-session
           (gascity-domain-decode 'gascity-session row)
           (gascity-resolve-tmux-socket gascity-events--city 'no-probe)))
     ((and subject (string-search "/" subject))
      (gascity-agent :name subject)))))

(defun gascity-events--visit-session (event)
  "Open the agent detail of session EVENT's session.
The session list (through the store) names the agent; a subject that
is already a qualified name opens without it."
  (let ((buffer (current-buffer)))
    (gascity-store-fetch
     '("session" "list")
     (lambda (sessions)
       (with-current-buffer (if (buffer-live-p buffer) buffer (current-buffer))
         (let ((agent (gascity-events--session-agent event sessions)))
           (if agent
               (gascity-events--open-agent agent)
             (message "Session %s is gone"
                      (or (alist-get 'session_id event)
                          (alist-get 'subject event)))))))
     (lambda (msg) (message "%s" msg)))))

(defun gascity-events-visit ()
  "Drill into the row at point (RET).
A bead subject opens in beads.el, scoped to its store; a session
subject opens the agent's detail; a `×N' row narrows the view to
that churn group (`x' in `/' resets); any other event shows its
fields."
  (interactive)
  (let ((row (gascity-events--row)))
    (cond
     ((null row) (user-error "No event at point"))
     ((gascity-events--churn-p row)
      (setq gascity-events--filter
            (plist-put (copy-sequence gascity-events--filter) :group (nth 2 row)))
      (gascity-events--render)
      (message "Only %s; / x resets" (nth 2 row)))
     ((gascity-events--bead-id row)
      (let ((id (gascity-events--bead-id row)))
        (gascity-bead-show id (gascity-beads--bead-path-cached id))))
     ((gascity-events--session-p row) (gascity-events--visit-session row))
     (t (gascity-tabulated-detail-show)))))

(defun gascity-events-bead ()
  "Open the bead of the event at point in beads.el (`b')."
  (interactive)
  (let ((id (and (not (gascity-events--churn-p (gascity-events--row)))
                 (gascity-events--bead-id (gascity-events--row)))))
    (unless id (user-error "No bead at point"))
    (gascity-bead-show id (gascity-beads--bead-path-cached id))))

(defun gascity-events-agent ()
  "Open the agent detail of the session event at point (`i')."
  (interactive)
  (let ((row (gascity-events--row)))
    (unless (and row (not (gascity-events--churn-p row))
                 (gascity-events--session-p row))
      (user-error "No session at point"))
    (gascity-events--visit-session row)))

;;; Filter (`/', §7.8, §5.5)

(defun gascity-events--seen (key)
  "Return the distinct values of event field KEY in hand, sorted."
  (sort (delete-dups (delq nil (mapcar (lambda (e) (alist-get key e))
                                       gascity-events--events)))
        #'string<))

(defun gascity-events--set-filter (key value)
  "Set filter KEY to VALUE (nil clears); re-read when the gc argv changes."
  (let ((old (gascity-events--args gascity-events--filter)))
    (setq gascity-events--filter
          (if value
              (plist-put (copy-sequence gascity-events--filter) key value)
            (gascity-tabulated--plist-drop gascity-events--filter key)))
    (when (eq key :level)
      (when (equal value "event")
        (setq gascity-events--filter
              (gascity-tabulated--plist-drop gascity-events--filter :level))))
    (if (equal old (gascity-events--args gascity-events--filter))
        (gascity-events--render)
      (setq gascity-events--status 'loading)
      (force-mode-line-update)
      (gascity-events-refresh))))

(defun gascity-events--install-filter ()
  "Point the shared `/' menu plumbing at this view's filter."
  (setq-local gascity-filter-get-function
              (lambda (key) (plist-get gascity-events--filter key)))
  (setq-local gascity-filter-set-function #'gascity-events--set-filter)
  (setq-local gascity-filter-reset-function
              (lambda ()
                (let ((old (gascity-events--args gascity-events--filter)))
                  (setq gascity-events--filter nil)
                  (if (equal old (gascity-events--args nil))
                      (gascity-events--render)
                    (gascity-events-refresh))))))

(gascity-filter-define-choice gascity-events-filter-window
  :window "window" gascity-events-windows gascity-events-window)
(gascity-filter-define-choice gascity-events-filter-type
  :type "type" (gascity-events--seen 'type))
(gascity-filter-define-choice gascity-events-filter-actor
  :actor "actor" (gascity-events--seen 'actor))
(gascity-filter-define-choice gascity-events-filter-level
  :level "signal level" gascity-events-levels "event")
(gascity-filter-define-toggle gascity-events-filter-unfold
  :unfold "unfold churn")
(gascity-filter-define-choice gascity-events-filter-search
  :search "search" nil "none")

(beads-define-prefix gascity-events-filter ()
  "Filter the Events view; each change applies at once (§7.8)."
  ["Filter events"
   ("-W" gascity-events-filter-window)
   ("-t" gascity-events-filter-type)
   ("-a" gascity-events-filter-actor)
   ("-l" gascity-events-filter-level)
   ("-c" gascity-events-filter-unfold)
   ("-q" gascity-events-filter-search)
   ("x" gascity-filter-reset)])

;;; Mode

(defvar-keymap gascity-events-mode-map
  :doc "Keymap for `gascity-events-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-events-refresh
  "/"   #'gascity-events-filter
  "RET" #'gascity-events-visit
  "b"   #'gascity-events-bead
  "i"   #'gascity-events-agent
  "W"   #'gascity-live-toggle)

(define-derived-mode gascity-events-mode tabulated-list-mode "GC-Events"
  "Major mode of the Events view: `gc events', churn folded (§7.8).
\\{gascity-events-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("Time" 12 nil) ("Sig" 3 nil) ("Type" 34 nil)
         ("Subject" 26 nil) ("Detail" 0 nil)])
  (setq tabulated-list-padding 1
        tabulated-list-sort-key nil
        ;; The column names are the buffer's first line; the header
        ;; line carries the view summary and filter state.
        tabulated-list-use-header-line nil)
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things)
  ;; Ahead of the shared row handler: SPC on a ×N row unfolds it.
  (add-hook 'beads-thing-toggle-functions #'gascity-events--toggle-churn -10 t)
  (setq header-line-format '(:eval (gascity-events--header-line)))
  (setq-local gascity-tabulated-detail-function #'gascity-events--detail-lines)
  (gascity-events--install-filter)
  (add-hook 'kill-buffer-hook #'gascity-events--teardown nil t))

;;;###autoload
(defun gascity-events (&optional filter)
  "Show the city's recent `gc events', churn folded (dashboard-v3 §7.8).
The buffer is keyed to the city (host-qualified name, pinned
`default-directory'); a second call shows it again and re-reads.
FILTER, from Lisp, replaces the view's filter plist (see
`gascity-events--filter'): the cockpit opens it narrowed to a churn
group with (:group GROUP :window WINDOW)."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
         (city (or (gascity-context-city-name dir) "city"))
         (buf (gascity-view-get-buffer-create
               (format gascity-events-buffer-name city) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-events-mode)
        (gascity-events-mode)
        (setq gascity-events--city city)
        (gascity-events--live-setup))
      (when filter (setq gascity-events--filter filter))
      (gascity-events-refresh))
    (pop-to-buffer buf)))

(provide 'gascity-events)
;;; gascity-events.el ends here
