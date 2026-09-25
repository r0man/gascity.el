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

;;; Times

(defun gascity-ui-parse-time (ts)
  "Return ISO-8601 timestamp TS as a float of seconds, or nil.
gc mixes zones (`last_active' carries a local offset, `created_at' is
UTC) and `gc events' adds nanoseconds; `iso8601-parse' reads all of
them.  A nil, empty or malformed TS yields nil, never an error."
  (when (and (stringp ts) (not (string-empty-p ts)))
    (condition-case nil
        (float-time (encode-time (iso8601-parse ts)))
      (error nil))))

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

(defun gascity-ui-clock (ts)
  "Return the local wall-clock `HH:MM' of timestamp TS, or \"\".
The ISO TS rides along as `help-echo'."
  (let ((time (gascity-ui-parse-time ts)))
    (if time
        (propertize (format-time-string "%H:%M" time) 'help-echo ts)
      "")))

;;; Text helpers

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

(defun gascity-ui-partial-mark (err)
  "Return a `◐' mark whose `help-echo' carries ERR, or \"\" when ERR is nil."
  (if err
      (propertize (concat " " (gascity-ui-glyph 'partial))
                  'help-echo (format "%s" err))
    ""))

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
