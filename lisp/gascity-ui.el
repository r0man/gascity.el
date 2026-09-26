;;; gascity-ui.el --- Shared visual language: glyphs, times, section states -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The visual language every gascity view shares (dashboard-v3 §6.1):
;;
;; - glyphs and the face each one renders in (`gascity-ui-glyph');
;; - relative times (`3m', `2h', `yesterday', `Sep 22') with the ISO
;;   timestamp in `help-echo' (`gascity-ui-time');
;; - the uniform section states of the vui views: loading `…', an
;;   error line `■ gc status: <stderr>   g retry', `◐' over good data,
;;   and `none' in an empty section's summary slot
;;   (`gascity-ui-section-header', `gascity-ui-section-body').
;;
;; Everything here is pure over in-memory values: no gc call, no file
;; name handler, safe at render and redisplay time (dashboard-v3 §8.3 R2).

;;; Code:

(require 'iso8601)
(require 'seq)
(require 'subr-x)
(require 'transient)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-store)             ; pending actions (the `…' marks)
(require 'gascity-live)              ; live state in every header line

;;; Glyphs (§6.1)

(defconst gascity-ui-glyphs
  '((ok       "●" gascity-running)
    (idle     "○" gascity-dim)
    (watch    "▲" gascity-warning)
    (fail     "■" gascity-failed)
    (partial  "◐" gascity-dim)
    (active   "⬣" gascity-running)
    (done     "◆" default)
    (pending  "·" gascity-dim)
    (failed   "✕" gascity-failed)
    (folded   "▸" gascity-dim)
    (expanded "▾" gascity-dim))
  "The dashboard glyph table: (KIND GLYPH FACE), dashboard-v3 §6.1.")

(defun gascity-ui-glyph (kind)
  "Return the glyph for KIND, propertized with its face.
KIND is a key of `gascity-ui-glyphs'; an unknown KIND yields a space."
  (let ((entry (assq kind gascity-ui-glyphs)))
    (if entry
        (propertize (nth 1 entry) 'face (nth 2 entry))
      " ")))

;;; Header lines (§8.3 R1): city, @host, title, live state, hints

(defun gascity-ui-live-string (&optional dir)
  "Return the live/offline fragment for DIR's city, or nil.
`gascity-live-header-string' when the city has a stream; else
`○ offline @host' while the store has paused DIR's host.  Pure: stream
and scheduler tables only, safe at redisplay."
  (let ((dir (or dir default-directory)))
    (or (gascity-live-header-string dir)
        (and (gascity-store-offline-p dir)
             (let ((host (and (gascity-remote-prefix dir)
                              (file-remote-p dir 'host))))
               (propertize (format "○ offline @%s" (or host "localhost"))
                           'face 'error
                           'help-echo (plist-get (gascity-store-host-status dir)
                                                 :reason)))))))

(defun gascity-ui-header-line (title &optional city hints)
  "Return a view header line: CITY, `@host' when remote, TITLE, live, HINTS.
CITY defaults to the base name of the buffer's pinned directory (its
city root), HINTS to the global `? help  j jump  g refresh'.  The live
fragment is `gascity-ui-live-string'.  Pure: buffer-local state and
the TRAMP name only (§8.3 R2), for `header-line-format' `:eval'."
  (let* ((city (or city (file-name-nondirectory
                         (directory-file-name (file-local-name default-directory)))))
         (host (and (gascity-remote-prefix default-directory)
                    (file-remote-p default-directory 'host)))
         (live (gascity-ui-live-string))
         (hints (propertize (or hints "? help  j jump  g refresh") 'face 'gascity-dim)))
    (concat " " (propertize (or city "?") 'face 'gascity-city)
            (if host (concat " " (propertize (concat "@" host) 'face 'gascity-dim)) "")
            (if (and title (not (string-empty-p title))) (concat "  " title) "")
            (if live (concat "  " live) "")
            (propertize " " 'display
                        `(space :align-to (- right ,(1+ (string-width hints)))))
            hints)))

;;; Pending actions (§8.5): the `…' in a row's status slot

(defun gascity-ui-pending-p (target &optional dir)
  "Return non-nil while an async gc call on TARGET is outstanding.
TARGET is the object id an action names (a session alias, rig name,
message or bead id); DIR (default `default-directory') picks the host.
Pure: a store table lookup."
  (and (stringp target) (gascity-store-action-pending-p target dir)))

(defun gascity-ui-pending-glyph (target glyph &optional dir)
  "Return GLYPH, or a dim `…' while an action on TARGET is in flight.
The row status slot of every view (dashboard-v3 §8.5 \"Pending
state\"); the `help-echo' says why.  TARGET and DIR as for
`gascity-ui-pending-p'."
  (if (gascity-ui-pending-p target dir)
      (propertize "…" 'face 'gascity-dim
                  'help-echo (format "gc call on %s in flight" target))
    glyph))

(defvar vui--root-instance)
(declare-function vui--rerender-instance "vui")

(defun gascity-ui--pending-changed (_target dir _pending)
  "Re-render the gascity views of DIR's host so `…' marks follow.
Runs from `gascity-store-pending-functions' when an action starts or
settles: vui views re-render their root, tabulated lists redraw their
page (`gascity-tabulated--refresh-display').  Buffers of other hosts
are left alone; nothing here reads gc or touches a file."
  (let ((host (file-remote-p dir)))
    (dolist (buf (buffer-list))
      (when (and (string-prefix-p "*gascity" (buffer-name buf))
                 (equal host (file-remote-p
                              (buffer-local-value 'default-directory buf))))
        (with-current-buffer buf
          (condition-case nil
              (cond
               ((and (boundp 'vui--root-instance) vui--root-instance)
                (vui--rerender-instance vui--root-instance))
               ((and (derived-mode-p 'tabulated-list-mode)
                     (fboundp 'gascity-tabulated--refresh-display)
                     (bound-and-true-p gascity-tabulated--all-entries))
                (let ((pt (point)))
                  (funcall 'gascity-tabulated--refresh-display)
                  (goto-char (min pt (point-max))))))
            (error nil)))))))

(add-hook 'gascity-store-pending-functions #'gascity-ui--pending-changed)

;;; Times

(defconst gascity-ui--timestamp-rx
  (rx bos (group (= 4 digit)) "-" (group (= 2 digit)) "-" (group (= 2 digit))
      "T" (group (= 2 digit)) ":" (group (= 2 digit)) ":" (group (= 2 digit))
      (? "." (+ digit))
      (or (group "Z")
          (seq (group (any "+-")) (group (= 2 digit)) ":" (group (= 2 digit))))
      eos)
  "The timestamp shape gc prints: RFC 3339, `Z' or a `±HH:MM' offset.")

(defun gascity-ui--days-from-civil (year month day)
  "Return the days from 1970-01-01 to YEAR, MONTH, DAY (proleptic Gregorian)."
  (let* ((y (if (<= month 2) (1- year) year))
         (era (floor y 400))
         (yoe (- y (* era 400)))
         (doy (+ (/ (+ (* 153 (+ month (if (> month 2) -3 9))) 2) 5) (1- day)))
         (doe (+ (* yoe 365) (/ yoe 4) (- (/ yoe 100)) doy)))
    (+ (* era 146097) doe -719468)))

(defun gascity-ui-parse-time (ts)
  "Return ISO-8601 timestamp TS as a float of seconds, or nil.
gc mixes zones (`last_active' carries a local offset, `created_at' is
UTC) and `gc events' adds nanoseconds.  gc's own RFC 3339 shape is
computed directly — a day of events is 15k timestamps, which
`iso8601-parse' took half a second over — and anything else falls
back to `iso8601-parse'.  A nil, empty or malformed TS yields nil,
never an error."
  (when (and (stringp ts) (not (string-empty-p ts)))
    (if (string-match gascity-ui--timestamp-rx ts)
        (let ((n (lambda (i) (string-to-number (match-string i ts)))))
          (+ (* 86400 (gascity-ui--days-from-civil
                       (funcall n 1) (funcall n 2) (funcall n 3)))
             ;; Whole seconds, as `iso8601-parse' + `encode-time' gave.
             (* 3600 (funcall n 4)) (* 60 (funcall n 5)) (funcall n 6) 0.0
             (if (match-beginning 7)
                 0
               (* (if (equal (match-string 8 ts) "-") 1 -1)
                  (+ (* 3600 (funcall n 9)) (* 60 (funcall n 10)))))))
      (condition-case nil
          (float-time (encode-time (iso8601-parse ts)))
        (error nil)))))

(defun gascity-ui-duration (seconds)
  "Return SECONDS as a compact duration: `12s', `3m', `2h', `4d'."
  (let ((s (max 0 (truncate (or seconds 0)))))
    (cond ((< s 60) (format "%ds" s))
          ((< s 3600) (format "%dm" (/ s 60)))
          ((< s 86400) (format "%dh" (/ s 3600)))
          (t (format "%dd" (/ s 86400))))))

(defun gascity-ui-relative-time (ts &optional now)
  "Return timestamp TS relative to NOW, the dashboard way.
Under a minute `12s', under an hour `3m', under a day `2h'; then
`yesterday' when TS falls on the previous calendar day, else the
month and day (`Sep 22'), with the year added when it differs from
NOW's.  NOW defaults to the current time (a float).  TS is an ISO
string or a float; nil or malformed yields the empty string."
  (let* ((time (if (numberp ts) ts (gascity-ui-parse-time ts)))
         (now (or now (float-time))))
    (if (null time)
        ""
      (let ((age (- now time)))
        (if (< age 86400)
            (gascity-ui-duration age)
          (let* ((day (decode-time time))
                 (today (decode-time now))
                 (yesterday (decode-time (- now 86400))))
            (cond
             ((and (= (decoded-time-day day) (decoded-time-day yesterday))
                   (= (decoded-time-month day) (decoded-time-month yesterday))
                   (= (decoded-time-year day) (decoded-time-year yesterday)))
              "yesterday")
             ((= (decoded-time-year day) (decoded-time-year today))
              (format-time-string "%b %e" time))
             (t (format-time-string "%Y-%m-%d" time)))))))))

(defun gascity-ui-time (ts &optional now)
  "Return TS as a relative time string carrying the ISO TS as `help-echo'.
See `gascity-ui-relative-time' for NOW and the format.  An absent TS
renders as the empty string."
  (let ((rel (gascity-ui-relative-time ts now)))
    (if (or (string-empty-p rel) (not (stringp ts)))
        rel
      (propertize rel 'help-echo ts))))

(defun gascity-ui-ago (ts &optional now)
  "Return TS as `3m ago' / `2h ago', or `yesterday' / `Sep 22' as is.
NOW as for `gascity-ui-time'."
  (let ((rel (gascity-ui-time ts now)))
    (cond ((string-empty-p rel) rel)
          ((string-match-p "\\`[0-9]+[smhd]\\'" rel) (concat rel " ago"))
          (t rel))))

(defun gascity-ui-clock (ts)
  "Return the local wall-clock `HH:MM' of timestamp TS, or \"\".
The ISO TS rides along as `help-echo'."
  (let ((time (gascity-ui-parse-time ts)))
    (if time
        (propertize (format-time-string "%H:%M" time) 'help-echo ts)
      "")))

(defun gascity-ui-duration-seconds (window &optional default)
  "Return the duration WINDOW (`90s', `30m', `2h', `7d') in seconds.
An unparsable WINDOW yields DEFAULT (a day when omitted)."
  (if (and (stringp window)
           (string-match "\\`\\([0-9]+\\)\\([smhd]\\)\\'" window))
      (* (string-to-number (match-string 1 window))
         (pcase (match-string 2 window)
           ("s" 1) ("m" 60) ("h" 3600) ("d" 86400)))
    (or default 86400)))

;;; Text helpers

(defun gascity-ui-path (path)
  "Return host-local PATH with the home prefix shown as `~/'.
Pure string work (§8.3 R2): a remote city's home is `/home/USER/' of the
TRAMP user (default the local login), a local one `~' expanded."
  (let ((home (if (file-remote-p default-directory)
                  (format "/home/%s/" (or (file-remote-p default-directory 'user)
                                          user-login-name))
                (file-name-as-directory (expand-file-name "~")))))
    (cond ((not (stringp path)) "")
          ((string-prefix-p home path) (concat "~/" (substring path (length home))))
          (t path))))

(defun gascity-ui-fit (string width)
  "Return STRING padded or truncated (with `…') to exactly WIDTH columns.
Text properties of STRING survive; the full text rides in `help-echo'
when it had to be cut."
  (let* ((str (or string ""))
         (w (string-width str)))
    (cond ((= w width) str)
          ((< w width) (concat str (make-string (- width w) ?\s)))
          (t (let ((cut (truncate-string-to-width str width 0 nil "…")))
               (if (get-text-property 0 'help-echo cut)
                   cut
                 (propertize cut 'help-echo (substring-no-properties str))))))))

(defun gascity-ui-truncate (string width)
  "Return STRING cut to at most WIDTH columns with `…' (no padding).
The full text rides in `help-echo' when it had to be cut."
  (let ((str (or string "")))
    (if (<= (string-width str) width)
        str
      (propertize (truncate-string-to-width str width 0 nil "…")
                  'help-echo (substring-no-properties str)))))

(defun gascity-ui-right-align (left right width)
  "Return LEFT and RIGHT joined so RIGHT ends at column WIDTH.
At least two spaces separate them; a LEFT too wide to leave room just
gets the two spaces."
  (let ((gap (- width (string-width left) (string-width right))))
    (concat left (make-string (max 2 gap) ?\s) right)))

(defun gascity-ui-first-line (text)
  "Return the first non-empty line of TEXT, trimmed, or nil."
  (when (stringp text)
    (seq-find (lambda (line) (not (string-empty-p line)))
              (mapcar #'string-trim (split-string text "\n")))))

(defun gascity-ui-hidden-label (counts)
  "Return the dim `(N hidden)' tally for COUNTS, an alist (CATEGORY . N).
Names each category, e.g. `(71 nudge · 2 session hidden)'; nil when
nothing is hidden (D4: never hide silently)."
  (let ((parts (delq nil (mapcar (lambda (c) (and (> (cdr c) 0)
                                                  (format "%d %s" (cdr c) (car c))))
                                 counts))))
    (when parts
      (propertize (format "(%s hidden)" (string-join parts " · "))
                  'face 'gascity-dim))))

;;; Section states (§6.1)

(defun gascity-ui-section-header (title summary &rest props)
  "Return the header line vnode `TITLE  SUMMARY'.
TITLE renders in `gascity-header', SUMMARY (a string, may carry its own
faces; nil for none) dim.  PROPS are extra text properties stamped on
the whole line — callers put their section identity, the thing marker
and a `gascity-section' flag (the `N'/`P' target) there."
  (let ((text (concat (propertize title 'face 'gascity-header)
                      (if (and summary (not (string-empty-p summary)))
                          (let ((s (copy-sequence summary)))
                            ;; Appended: glyph faces in SUMMARY win.
                            (add-face-text-property 0 (length s)
                                                    'gascity-dim t s)
                            (concat "  " s))
                        ""))))
    (apply #'vui-text text 'gascity-section t props)))

(defun gascity-ui-error-line (label err)
  "Return the dim error line for a section whose read LABEL failed with ERR.
`  ■ gc status: <first line of stderr>   g retry' (§6.1)."
  (vui-text (concat "  " (gascity-ui-glyph 'fail) " "
                    (propertize (format "gc %s: %s" label
                                        (or (gascity-ui-first-line
                                             (and err (format "%s" err)))
                                            "failed"))
                                'face 'gascity-dim)
                    (propertize "   g retry" 'face 'gascity-dim))
            'gascity-ui-status 'error))

(defun gascity-ui-loading-line ()
  "Return the dim `…' line of a section whose first read is in flight."
  (vui-text (propertize "  …" 'face 'gascity-dim) 'gascity-ui-status 'loading))

(defun gascity-ui-stale-mark (loads)
  "Return the header mark of a section whose LOADS hold stale data, or \"\".
LOADS is a list of `gascity-ui-effective-load' plists.  A load that
kept its last good data over a failed refresh marks the section
`◐ timed out' (the read hit its deadline, dashboard-v3 §8.3 R5) or
`◐ stale' (it failed); the failure texts ride in `help-echo'.  Loads
with no data are the error line's business, not this mark's."
  (let* ((stale (seq-filter (lambda (l) (and (plist-get l :error)
                                             (plist-get l :data)))
                            loads))
         (errors (delq nil (mapcar (lambda (l) (plist-get l :error)) stale))))
    (if (null stale)
        ""
      (propertize (concat " " (gascity-ui-glyph 'partial)
                          (propertize (if (seq-some (lambda (l) (plist-get l :timed-out))
                                                    stale)
                                          " timed out"
                                        " stale")
                                      'face 'gascity-dim))
                  'help-echo (mapconcat (lambda (e) (format "%s" e)) errors "\n")))))

(defun gascity-ui-partial-mark (err)
  "Return a `◐' mark whose `help-echo' carries ERR, or \"\" when ERR is nil."
  (if err
      (propertize (concat " " (gascity-ui-glyph 'partial))
                  'help-echo (format "%s" err))
    ""))

;;; Section vnodes for the vui detail views

(defun gascity-ui-effective-load (res ref)
  "Return the normalized load plist for async result RES with snapshot REF.
`ready' adopts fresh data (and refreshes the REF cache); any other state
keeps rendering the cached snapshot — stale-while-revalidate — and only
reports `error'/`pending' when no snapshot is in hand.  A failed refresh
over a good snapshot rides along in `:error'."
  (let ((state (plist-get res :status)))
    (cond ((and (eq state 'ready) (plist-get res :error))
           ;; A store snapshot (`gascity-store-use'): the last good
           ;; payload plus the failure of the refresh that followed it.
           (list :state 'stale :data (setcar ref (plist-get res :data))
                 :error (plist-get res :error)
                 :timed-out (plist-get res :timed-out)))
          ((eq state 'ready)
           (list :state 'ready :data (setcar ref (plist-get res :data))))
          ((car ref)
           (list :state 'stale :data (car ref)
                 :error (and (eq state 'error) (plist-get res :error))))
          ((eq state 'error)
           (list :state 'error :error (plist-get res :error)))
          (t (list :state 'pending)))))

(defun gascity-ui-section (name label load collapsed rows-fn
                           &optional count-fn)
  "Return a section vnode in the §6.1 style, for the vui detail views.
NAME is the section's identity, LABEL its title, LOAD an
`gascity-ui-effective-load' plist, COLLAPSED whether it is
folded, ROWS-FN the body builder over the load's data and COUNT-FN
the summary count (default: `length'), or a summary string.  First
load: `…' in the summary; error with no data: a `■ gc …' line; error
over data: `◐ stale' or `◐ timed out' on the header
\(`gascity-ui-stale-mark'); empty: `none'."
  (let* ((state (plist-get load :state))
         (data (plist-get load :data))
         (usable (memq state '(ready stale)))
         (count (and usable (funcall (or count-fn #'length) data)))
         (summary (cond ((eq state 'pending) (propertize "…" 'face 'gascity-dim))
                        ((not usable) nil)
                        ((or (null count) (eql count 0)) "none")
                        ((stringp count) count)
                        (t (number-to-string count))))
         (header (gascity-ui-section-header
                  (concat (if collapsed (concat (gascity-ui-glyph 'folded) " ") "")
                          label)
                  (concat (or summary "")
                          (gascity-ui-stale-mark
                           (and (eq state 'stale) (list load))))
                  'gascity-dashboard-section name)))
    (apply #'vui-vstack
           header
           (unless collapsed
             (cond ((eq state 'error)
                    (list (gascity-ui-error-line name (plist-get load :error))))
                   ((and usable rows-fn (not (eql count 0)))
                    (funcall rows-fn data)))))))

(defun gascity-ui-store-load (snapshot)
  "Return the normalized load plist of a `gascity-store-use' SNAPSHOT.
The shape `gascity-ui-section' reads: ready data (`stale' with :error
when a refresh failed over it), `error' with no data, else `pending'."
  (let ((status (plist-get snapshot :status))
        (err (plist-get snapshot :error)))
    (pcase status
      ('ready (if err
                  (list :state 'stale :data (plist-get snapshot :data) :error err
                        :timed-out (plist-get snapshot :timed-out))
                (list :state 'ready :data (plist-get snapshot :data))))
      ('error (list :state 'error :error err))
      (_ (list :state 'pending)))))

;;; Filter menus (§5.5): apply on change, `x' resets

;; Every `/' menu edits its view's filter through three buffer-local
;; hooks the view installs, so one set of suffix builders serves the
;; tabulated lists (a plist variable + async refresh) and the vui
;; cockpit (root-component state) alike.  A suffix applies its change
;; at once and keeps the menu open (`:transient t'); there is no
;; `apply' step.  Descriptions and suffix bodies run in the buffer the
;; menu was opened from (transient's contract), so they read and write
;; that view's state.

(defvar-local gascity-filter-get-function nil
  "Function of one argument, a filter KEY, returning its current value.")

(defvar-local gascity-filter-set-function nil
  "Function of two arguments, KEY and VALUE, applying a filter change.
It stores the new value and refreshes the view; nil VALUE clears KEY.")

(defvar-local gascity-filter-reset-function nil
  "Function of no arguments clearing every filter of the view.")

(defun gascity-filter-value (key)
  "Return the current value of filter KEY in this view, or nil."
  (and gascity-filter-get-function
       (funcall gascity-filter-get-function key)))

(defun gascity-filter-set (key value)
  "Set filter KEY to VALUE in this view (nil clears) and refresh it."
  (unless gascity-filter-set-function
    (user-error "This buffer has no filter"))
  (funcall gascity-filter-set-function key value))

(defun gascity-filter-describe (label value &optional default)
  "Return a menu description: LABEL then VALUE in brackets.
A nil VALUE shows DEFAULT (`all' when omitted); t shows `on'."
  (concat (gascity-ui-fit label 20)
          (propertize (format "[%s]"
                              (cond ((eq value t) "on")
                                    ((null value) (or default "all"))
                                    (t value)))
                      'face 'transient-value)))

(defmacro gascity-filter-define-choice (name key label choices &optional default)
  "Define NAME, a filter-menu suffix choosing KEY's value.
LABEL heads the description; CHOICES is a form evaluated in the view
buffer yielding the completion candidates (any string is accepted; an
empty answer clears KEY).  DEFAULT names the cleared state."
  (declare (indent defun))
  `(transient-define-suffix ,name ()
     ,(format "Set the %s filter of this view (empty clears it)." label)
     :transient t
     :description (lambda () (gascity-filter-describe
                              ,(concat label "…") (gascity-filter-value ,key)
                              ,default))
     (interactive)
     (let ((value (completing-read (format "%s (empty = %s): " ,label
                                           (or ,default "all"))
                                   ,choices nil nil nil nil)))
       (gascity-filter-set ,key (and (not (string-empty-p value)) value)))))

(defmacro gascity-filter-define-toggle (name key label)
  "Define NAME, a filter-menu suffix toggling boolean filter KEY.
LABEL heads the description, which shows `[on]'/`[off]'."
  (declare (indent defun))
  `(transient-define-suffix ,name ()
     ,(format "Toggle the %s filter of this view." label)
     :transient t
     :description (lambda () (gascity-filter-describe
                              ,label (gascity-filter-value ,key) "off"))
     (interactive)
     (gascity-filter-set ,key (not (gascity-filter-value ,key)))))

(transient-define-suffix gascity-filter-reset ()
  "Clear every filter of this view and refresh it."
  :transient t
  :description "reset"
  (interactive)
  (unless gascity-filter-reset-function
    (user-error "This buffer has no filter"))
  (funcall gascity-filter-reset-function))

(provide 'gascity-ui)
;;; gascity-ui.el ends here
