;;; gascity-event.el --- The gc event model: signal levels, churn folding -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; What every view that shows `gc events' agrees on (dashboard-v3
;; §7.1 Activity, §7.8 Events):
;;
;; - the signal level of an event type (■ attention, ▲ watch, or a
;;   plain event), from the user-extensible `gascity-event-levels';
;; - the noise category of a bead (D4: wisps, nudges, order tracking,
;;   mail messages), which decides whether a `bead.*' event is churn;
;; - churn folding: order firings, noise-bead lifecycle, bead updates
;;   and dog patrols fold into one `×N' row per group per time bucket,
;;   while signal events never fold (`gascity-event-fold');
;; - the text of an event row (subject, detail, the `key value' lines
;;   of its detail drawer).
;;
;; An event is the alist `gc events' prints per JSON line: `seq',
;; `type', `ts', `actor', `ok', `payload', optional `subject',
;; `message', `session_id', `run_id'.  `ts' mixes zones (`+02:00' from
;; the controller, `Z' from gc), so times are parsed, never compared as
;; strings.  Everything here is pure over in-memory events.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'gascity-custom)
(require 'gascity-ui)

;;; Bead noise (D4)

(defun gascity-event-noise (bead)
  "Return BEAD's noise category, or nil for real work.
`nudge' — a nudge wisp (label `nudge:…' or title `nudge:…');
`order' — order-tracking churn (label `order-tracking'/`order-run:…');
`message' — a mail message bead; `wisp' — any other wisp (`…-wisp-…'
id); `session' — an agent's session bead; `convoy' — a convoy (counted
under Work's convoys, never a work row)."
  (let ((labels (append (alist-get 'labels bead) nil))
        (id (or (alist-get 'id bead) ""))
        (title (or (alist-get 'title bead) ""))
        (type (alist-get 'issue_type bead)))
    (cond
     ((or (seq-some (lambda (l) (string-prefix-p "nudge:" l)) labels)
          (string-prefix-p "nudge:" title))
      'nudge)
     ((seq-some (lambda (l) (or (equal l "order-tracking")
                                (string-prefix-p "order-run:" l)))
                labels)
      'order)
     ((equal type "message") 'message)
     ((string-match-p "-wisp-" id) 'wisp)
     ((equal type "session") 'session)
     ((equal type "convoy") 'convoy))))

(defconst gascity-event-noise-filters
  '((wisp . :wisps) (nudge . :nudges) (order . :orders) (message . :messages))
  "Noise category → the filter key that shows it (§7.2).")

(defun gascity-event-noise-shown-p (category filters)
  "Return non-nil when noise CATEGORY is shown under FILTERS."
  (let ((key (alist-get category gascity-event-noise-filters)))
    (and key (plist-get filters key))))

;;; Events

(defvar gascity-event--levels nil
  "Memo of `gascity-event-level': (TABLE . HASH), HASH mapping an event
type to its level (or `none'), valid while TABLE is still the value of
`gascity-event-levels'.")

(defun gascity-event-level (event)
  "Return EVENT's signal level: `attention', `watch' or nil.
Matched once per event type (a handful of types, thousands of events):
the answer is memoized until `gascity-event-levels' changes."
  (let ((type (or (alist-get 'type event) "")))
    (unless (eq (car gascity-event--levels) gascity-event-levels)
      (setq gascity-event--levels
            (cons gascity-event-levels (make-hash-table :test 'equal))))
    (let* ((memo (cdr gascity-event--levels))
           (level (gethash type memo)))
      (unless level
        (setq level (or (cdr (seq-find (lambda (entry) (string-match-p (car entry) type))
                                       gascity-event-levels))
                        'none))
        (puthash type level memo))
      (and (not (eq level 'none)) level))))

(defun gascity-event-level-glyph (level)
  "Return the glyph of signal LEVEL: ■, ▲, or a space."
  (pcase level
    ('attention (gascity-ui-glyph 'fail))
    ('watch (gascity-ui-glyph 'watch))
    (_ " ")))

(defun gascity-event-bead (event)
  "Return the bead a `bead.*' EVENT carries in its payload, or nil."
  (let ((payload (alist-get 'payload event)))
    (and (listp payload) (alist-get 'bead payload))))

(defvar gascity-event--times (make-hash-table :test 'eq :weakness 'key)
  "EVENT → its time as a float, parsed once per decoded event.
Weak on the event: a payload's times go when the payload does.")

(defun gascity-event-time (event)
  "Return EVENT's time as a float, or 0.
Parsed once per event object — the payload in the store, a live event —
and remembered (`gascity-event--times'); a render never re-parses."
  (or (gethash event gascity-event--times)
      (puthash event (or (gascity-ui-parse-time (alist-get 'ts event)) 0)
               gascity-event--times)))

(defun gascity-event-since-arg (window)
  "Return WINDOW as a `gc events --since' duration.
gc's durations have no day unit, so `7d' becomes `168h'; anything
else passes through."
  (if (and (stringp window) (string-match "\\`\\([0-9]+\\)d\\'" window))
      (format "%dh" (* 24 (string-to-number (match-string 1 window))))
    window))

(defun gascity-event-churn-group (event filters)
  "Return EVENT's churn group, or nil when it is signal worth a row.
Order firings, noise-bead lifecycle, bead updates and dog patrols fold
into `×N' rows (§7.1); FILTERS showing a noise category make its events
plain rows again.  Signal events never fold."
  (unless (gascity-event-level event)
    (let ((type (or (alist-get 'type event) "")))
      (cond
       ((member type '("order.fired" "order.completed"))
        (unless (plist-get filters :orders) "order.fired/completed"))
       ((string-prefix-p "bead." type)
        (let* ((bead (gascity-event-bead event))
               (noise (and bead (gascity-event-noise bead))))
          (cond ((and noise (memq noise '(wisp nudge order message))
                      (not (gascity-event-noise-shown-p noise filters)))
                 "wisp created/closed")
                ((equal type "bead.updated") "bead.updated"))))
       ((string-prefix-p "mol-dog-" type) "dog patrol")))))

(defun gascity-event-fold (events filters &optional bucket)
  "Fold EVENTS into rows under FILTERS, newest first.
Returns (ROWS . FOLDED): each row is (event EVENT) or (churn KEY GROUP
TIME EVENTS) — KEY identifies the fold, TIME is its newest event's and
EVENTS are newest first — and FOLDED counts the events folded into
churn rows.  Churn folds per GROUP per BUCKET seconds (default 900, a
quarter hour) unless FILTERS unfold it (`:unfold')."
  (let ((bucket (or bucket 900))
        (buckets (make-hash-table :test 'equal))
        (rows nil)
        (folded 0))
    (dolist (event events)
      (let ((group (gascity-event-churn-group event filters)))
        (if (or (null group) (plist-get filters :unfold))
            (push (list 'event event) rows)
          (let* ((time (gascity-event-time event))
                 (key (format "%s@%d" group (floor time bucket)))
                 (row (gethash key buckets)))
            (setq folded (1+ folded))
            (if row
                (progn (setf (nth 3 row) (max (nth 3 row) time))
                       (push event (nth 4 row)))
              (setq row (list 'churn key group time (list event)))
              (puthash key row buckets)
              (push row rows))))))
    ;; Sort on a key computed once per row, not in the comparator.
    (cons (mapcar #'cdr
                  (sort (mapcar (lambda (row)
                                  (cons (if (eq (car row) 'churn) (nth 3 row)
                                          (gascity-event-time (nth 1 row)))
                                        row))
                                rows)
                        (lambda (a b) (> (car a) (car b)))))
          folded)))

(defun gascity-event-fold-key (filters)
  "Return the part of FILTERS the churn fold depends on."
  (list (plist-get filters :orders) (plist-get filters :wisps)
        (plist-get filters :nudges) (plist-get filters :messages)
        (plist-get filters :unfold)))

(defun gascity-event-churn-detail (group events)
  "Return the detail text of a churn GROUP row over EVENTS."
  (cond
   ((equal group "order.fired/completed")
    (format "(%d orders)"
            (length (delete-dups (mapcar (lambda (e) (alist-get 'subject e)) events)))))
   ((equal group "wisp created/closed")
    (format "(%s)"
            (string-join
             (delete-dups
              (delq nil (mapcar (lambda (e)
                                  (let ((b (gascity-event-bead e)))
                                    (and b (symbol-name (gascity-event-noise b)))))
                                events)))
             ", ")))
   (t (format "(%d beads)"
              (length (delete-dups (mapcar (lambda (e) (alist-get 'subject e))
                                           events)))))))

(defun gascity-event-subject (event)
  "Return the subject text of EVENT: its bead's id and title, else `subject'."
  (let ((subject (or (alist-get 'subject event) ""))
        (bead (gascity-event-bead event)))
    (if bead
        (format "%s %s" (alist-get 'id bead) (or (alist-get 'title bead) ""))
      subject)))

(defun gascity-event--value (value)
  "Return VALUE as one short display line (no elisp printed forms)."
  (let ((text (cond ((stringp value) value)
                    ((numberp value) (number-to-string value))
                    ((eq value t) "true")
                    ((symbolp value) (symbol-name value))
                    ((vectorp value)
                     (mapconcat #'gascity-event--value (append value nil) ", "))
                    ((and (consp value) (consp (car value)))
                     (format "{%d fields}" (length value)))
                    (t (format "%s" value)))))
    (truncate-string-to-width (replace-regexp-in-string "\n" " " text)
                              60 nil nil "…")))

(defun gascity-event-fields (event)
  "Return EVENT's fields beyond time, type, seq and ok as `key value' lines.
The inline drawer of an event row (§5.4).  The payload's fields are
listed with the event's own (`routed_to  …'), each key once (a payload
`message' repeating the event's is dropped); a payload bead is one
line (id, title, status), not the whole bead.  Keys share one column;
values are cut at 60 columns and the drawer at 12 lines."
  (let (pairs)
    (dolist (field event)
      (let ((key (car field)) (v (cdr field)))
        (unless (or (memq key '(ts type seq ok)) (null v))
          (if (and (eq key 'payload) (consp v) (consp (car v)))
              (dolist (pf v)
                (when (cdr pf)
                  (push (if (and (eq (car pf) 'bead) (consp (cdr pf)))
                            (let ((b (cdr pf)))
                              (cons 'bead (format "%s %s (%s)" (alist-get 'id b)
                                                  (or (alist-get 'title b) "")
                                                  (or (alist-get 'status b) "?"))))
                          pf)
                        pairs)))
            (push (cons key v) pairs)))))
    (setq pairs (nreverse pairs))
    ;; Each key once: the event's own field wins over a payload one.
    (let ((seen nil) (unique nil))
      (dolist (pair pairs)
        (unless (memq (car pair) seen)
          (push (car pair) seen)
          (push pair unique)))
      (setq pairs (seq-take (nreverse unique) 12)))
    (let ((width (apply #'max 0 (mapcar (lambda (p) (length (symbol-name (car p)))) pairs))))
      (mapcar (lambda (p)
                (format "%s  %s" (string-pad (symbol-name (car p)) width)
                        (gascity-event--value (cdr p))))
              pairs))))

(provide 'gascity-event)
;;; gascity-event.el ends here
