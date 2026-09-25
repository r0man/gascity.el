;;; gascity-pulse.el --- Session pulse of open cities: counts, samples, lighter -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; What the open cockpits already know, kept for the session so other
;; views can show it without a gc call (dashboard-v3 §7.11, §7.12, P5):
;;
;; - `gascity-pulse-publish': the cockpit reports, per city, its Needs
;;   you ■/▲ totals and active-run count every time it renders with a
;;   status payload in hand.  The Cities view reads the run count from
;;   here, the mode-line lighter the ■/▲ totals.
;; - `gascity-pulse-record-store-size': a per-city ring of store-size
;;   samples (from each `gc status' read the cockpit or Health view
;;   gets), drawn as a `▁▂▃…' sparkline by `gascity-pulse-sparkline'.
;; - `gascity-mode-line-mode': the global, opt-in lighter
;;   `GC[ec ■1▲2 · bl ▲1]'.  Its mode-line construct is a plain string
;;   variable rebuilt on publish and on cockpit kill, so redisplay
;;   evaluates nothing: it never runs gc, never touches TRAMP (§8.3 R2).
;;
;; Everything here is pure over in-memory values.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'gascity-custom)
(require 'gascity-ui)

(declare-function gascity-dashboard "gascity-dashboard")

(defcustom gascity-pulse-store-samples 40
  "How many store-size samples to keep per city (the sparkline width)."
  :type 'natnum
  :group 'gascity)

;;; City keys

(defun gascity-pulse-city-key (dir)
  "Return the pulse key of the city rooted at DIR: DIR as a directory.
A TRAMP name stays host-qualified, so a local and a remote city of the
same name are distinct keys.  Pure string work."
  (file-name-as-directory dir))

(defun gascity-pulse-abbrev (name)
  "Return the lighter abbreviation of city NAME: `emacs-city' → `ec'.
The initials of its `-'/`_'/`.'-separated words, or the first two
letters of a one-word name."
  (let ((words (split-string (or name "?") "[-_. ]+" t)))
    (if (cdr words)
        (mapconcat (lambda (w) (substring w 0 1)) words "")
      (let ((w (or (car words) "?")))
        (substring w 0 (min 2 (length w)))))))

;;; Published cockpit counts

(defvar gascity-pulse--cities (make-hash-table :test 'equal)
  "City key → plist (:name :buffer :fail :watch :runs :at).
Filled by `gascity-pulse-publish'; an entry whose buffer died is
dropped by `gascity-pulse--forget'.")

(defun gascity-pulse-publish (dir buffer name &rest counts)
  "Record the cockpit figures of the city rooted at DIR.
BUFFER is the cockpit showing it, NAME the city name; COUNTS is a
plist with `:fail' and `:watch' (the Needs you ■ and ▲ totals) and
`:runs' (active runs).  Rebuilds the lighter string only when a figure
changed, so a re-render with the same data costs nothing."
  (let* ((key (gascity-pulse-city-key dir))
         (old (gethash key gascity-pulse--cities))
         (new (list :name name :buffer buffer
                    :fail (or (plist-get counts :fail) 0)
                    :watch (or (plist-get counts :watch) 0)
                    :runs (plist-get counts :runs)
                    :at (float-time))))
    (unless (and old
                 (eq (plist-get old :buffer) buffer)
                 (equal (plist-get old :name) name)
                 (eql (plist-get old :fail) (plist-get new :fail))
                 (eql (plist-get old :watch) (plist-get new :watch))
                 (eql (plist-get old :runs) (plist-get new :runs)))
      (puthash key new gascity-pulse--cities)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (add-hook 'kill-buffer-hook #'gascity-pulse--forget nil t)))
      (gascity-mode-line-update))
    ;; Keep the timestamp fresh without a rebuild.
    (when old (plist-put (gethash key gascity-pulse--cities) :at (float-time)))))

(defun gascity-pulse--forget ()
  "Drop the pulse entries of the cockpit buffer being killed."
  (let ((buffer (current-buffer)) (dead nil))
    (maphash (lambda (key entry)
               (when (eq (plist-get entry :buffer) buffer) (push key dead)))
             gascity-pulse--cities)
    (when dead
      (dolist (key dead) (remhash key gascity-pulse--cities))
      (gascity-mode-line-update))))

(defun gascity-pulse-city (dir)
  "Return the published plist of the city rooted at DIR, or nil.
Only entries whose cockpit buffer is still live count."
  (let ((entry (gethash (gascity-pulse-city-key dir) gascity-pulse--cities)))
    (and entry (buffer-live-p (plist-get entry :buffer)) entry)))

(defun gascity-pulse-cities ()
  "Return the live published entries as (KEY . PLIST), sorted by name."
  (let (out)
    (maphash (lambda (key entry)
               (when (buffer-live-p (plist-get entry :buffer))
                 (push (cons key entry) out)))
             gascity-pulse--cities)
    (sort out (lambda (a b)
                (or (string< (plist-get (cdr a) :name) (plist-get (cdr b) :name))
                    (and (equal (plist-get (cdr a) :name) (plist-get (cdr b) :name))
                         (string< (car a) (car b))))))))

;;; Store-size samples (P5)

(defvar gascity-pulse--samples (make-hash-table :test 'equal)
  "City key → (LAST-PAYLOAD . SIZES), SIZES newest first.")

(defun gascity-pulse-record-store-size (dir status)
  "Sample the store size of `gc status' payload STATUS for the city at DIR.
A payload already sampled (the same object, re-rendered) is skipped, so
one read yields one sample however often its view re-renders.  Keeps at
most `gascity-pulse-store-samples' sizes."
  (let* ((key (gascity-pulse-city-key dir))
         (cell (gethash key gascity-pulse--samples))
         (size (alist-get 'size_bytes
                          (alist-get 'store_health (alist-get 'summary status)))))
    (when (and (numberp size) (not (eq (car cell) status)))
      (puthash key
               (cons status (seq-take (cons size (cdr cell))
                                      gascity-pulse-store-samples))
               gascity-pulse--samples))))

(defun gascity-pulse-store-sizes (dir)
  "Return the store-size samples of the city at DIR, oldest first."
  (reverse (cdr (gethash (gascity-pulse-city-key dir) gascity-pulse--samples))))

(defconst gascity-pulse--spark "▁▂▃▄▅▆▇█"
  "The sparkline levels, lowest first (§6.1).")

(defun gascity-pulse-sparkline (values)
  "Return VALUES (numbers) as a `▁▂▃…' sparkline string.
The range min..max maps onto the eight levels; a flat series is all
`▁'.  Nil VALUES yields the empty string."
  (if (null values)
      ""
    (let* ((lo (apply #'min values))
           (hi (apply #'max values))
           (span (- hi lo))
           (top (1- (length gascity-pulse--spark))))
      (mapconcat (lambda (v)
                   (let ((i (if (zerop span) 0
                              (min top (floor (* (/ (float (- v lo)) span)
                                                 (+ top 0.999)))))))
                     (string (aref gascity-pulse--spark i))))
                 values ""))))

;;; Mode-line lighter (§7.12)

(defvar gascity-mode-line--string ""
  "The lighter's current text; the mode line shows this variable as-is.")
(put 'gascity-mode-line--string 'risky-local-variable t)

(defun gascity-mode-line--visit (buffer)
  "Return a mouse command that shows cockpit BUFFER."
  (lambda (event)
    (interactive "e")
    (ignore event)
    (if (buffer-live-p buffer)
        (pop-to-buffer buffer)
      (message "That cockpit is gone"))))

(defun gascity-mode-line--segment (key entry)
  "Return the lighter segment of city KEY with published ENTRY."
  (let* ((host (file-remote-p key 'host))
         (label (concat (gascity-pulse-abbrev (plist-get entry :name))
                        (if host (concat "@" host) "")))
         (fail (plist-get entry :fail))
         (watch (plist-get entry :watch))
         (counts (if (and (zerop fail) (zerop watch))
                     (gascity-ui-glyph 'ok)
                   (concat (if (> fail 0)
                               (concat (gascity-ui-glyph 'fail) (number-to-string fail))
                             "")
                           (if (> watch 0)
                               (concat (gascity-ui-glyph 'watch) (number-to-string watch))
                             ""))))
         (map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1]
                (gascity-mode-line--visit (plist-get entry :buffer)))
    (propertize (concat label " " counts)
                'mouse-face 'mode-line-highlight
                'local-map map
                'help-echo (format "%s: %d attention, %d watch — mouse-1: cockpit"
                                   (plist-get entry :name) fail watch))))

(defun gascity-mode-line-string ()
  "Return the lighter text from the published cockpit figures.
Empty when no cockpit is open.  Pure (no gc, no file operation)."
  (let ((cities (gascity-pulse-cities)))
    (if (null cities)
        ""
      (concat " GC["
              (mapconcat (lambda (c) (gascity-mode-line--segment (car c) (cdr c)))
                         cities " · ")
              "]"))))

(defvar gascity-mode-line-mode)

(defun gascity-mode-line-update ()
  "Rebuild the lighter text (when the mode is on) and redisplay mode lines."
  (when (bound-and-true-p gascity-mode-line-mode)
    (setq gascity-mode-line--string (gascity-mode-line-string))
    (force-mode-line-update t)))

;;;###autoload
(define-minor-mode gascity-mode-line-mode
  "Show the open cities' Needs you totals in the mode line (§7.12).
One segment per open cockpit: `GC[ec ■1▲2 · bl ▲1]', `●' when a city
needs nothing.  mouse-1 on a segment shows that city's cockpit.  The
figures come from what the cockpits already read; the lighter never
runs gc or touches a remote host at redisplay."
  :global t
  :group 'gascity
  ;; `global-mode-string' must stay a mode-line construct: a list led
  ;; by a symbol would read as (SYMBOL THEN ELSE), so it leads with "".
  (let ((rest (delq 'gascity-mode-line--string
                    (cond ((null global-mode-string) nil)
                          ((listp global-mode-string) (copy-sequence global-mode-string))
                          (t (list global-mode-string))))))
    (setq global-mode-string
          (cond (gascity-mode-line-mode
                 (append (if (stringp (car rest)) rest (cons "" rest))
                         '(gascity-mode-line--string)))
                ((equal rest '("")) nil)
                (t rest))))
  (if gascity-mode-line-mode
      (gascity-mode-line-update)
    (setq gascity-mode-line--string "")
    (force-mode-line-update t)))

(provide 'gascity-pulse)
;;; gascity-pulse.el ends here
