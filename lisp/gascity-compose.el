;;; gascity-compose.el --- Multi-line compose buffer for gascity -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The one genuinely new UI surface the write layer needs
;; (DESIGN-write-actions.md §6).  Mail send/reply — and, in phase 3, bead
;; descriptions — carry multi-line bodies for which the minibuffer is
;; wrong.  `gascity-compose-mode' is a small `text-mode' derivative modeled
;; on `git-commit'/`log-edit': a read-only header (recipient + subject)
;; over an editable body area.
;;
;; A caller pops a buffer with `gascity-compose', handing it the header
;; lines, the buffer to refresh afterward, and a *finish closure*.  `C-c
;; C-c' (`gascity-compose-finish') runs the closure with the body text —
;; the closure builds the gc command and starts it asynchronously (D9;
;; the origin view refreshes when gc answers) — then discards the
;; buffer at once.  `C-c C-k'
;; (`gascity-compose-abort') throws the draft away.  The compose buffer
;; knows nothing about gc commands; it only collects a body and calls back.

;;; Code:

(require 'cl-lib)
(require 'text-mode)
(require 'text-property-search)
(require 'gascity-context)   ; view-buffer factory (buffer keyed to its city)

;; The refresh helper lives in gascity-action, which requires this module;
;; call it by name (guarded) after a finish to avoid a load cycle.

(defvar-local gascity-compose--finish-function nil
  "Closure run with the body string when the compose buffer is finished.")

(defvar-local gascity-compose--origin-buffer nil
  "Buffer whose gascity view is refreshed after a finish.")

(defvar-local gascity-compose--body-start nil
  "Marker at the first editable position, just past the read-only header.")

(defvar-local gascity-compose--notify 'unsupported
  "Whether the message nudges its recipient (`--notify'), or `unsupported'.
A compose buffer opened with `:notify' shows a `Notify:' header line
that `gascity-compose-toggle-notify' flips, and its finish closure
receives the flag.")

(defconst gascity-compose-separator "--text follows this line--"
  "The line between the read-only header and the body (dashboard-v3 §7.9).")

(defvar-keymap gascity-compose-mode-map
  :doc "Keymap for `gascity-compose-mode'."
  "C-c C-c" #'gascity-compose-finish
  "C-c C-k" #'gascity-compose-abort
  "C-c C-n" #'gascity-compose-toggle-notify)

(define-derived-mode gascity-compose-mode text-mode "GC-Compose"
  "Major mode for composing a multi-line gc body (mail, bead description).
Finalize with `\\[gascity-compose-finish]'; discard with \
`\\[gascity-compose-abort]'.

\\{gascity-compose-mode-map}"
  (setq-local header-line-format
              (substitute-command-keys
               "Compose — \\[gascity-compose-finish] to send, \
\\[gascity-compose-abort] to abort")))

(defun gascity-compose--insert-header (fields)
  "Insert read-only header FIELDS, then a separator; return the body start.
FIELDS is an alist of (LABEL . VALUE).  The inserted region is made
read-only but rear-non-sticky, so the body that follows stays editable."
  (let ((start (point)))
    (dolist (field fields)
      (insert (propertize (format "%s: %s\n" (car field) (cdr field))
                          'gascity-compose-field (car field))))
    (insert gascity-compose-separator "\n")
    (let ((body-start (point)))
      (add-text-properties start body-start '(read-only t rear-nonsticky t))
      body-start)))

(defun gascity-compose--body ()
  "Return the trimmed editable body of the current compose buffer."
  (string-trim
   (buffer-substring-no-properties
    (or (and (markerp gascity-compose--body-start)
             (marker-position gascity-compose--body-start))
        (point-min))
    (point-max))))

(defun gascity-compose--help (notify)
  "Return the dim help trailer shown below the body; NOTIFY adds C-c C-n."
  (propertize
   (substitute-command-keys
    (concat "\n# Write the message body above.  \\<gascity-compose-mode-map>\
\\[gascity-compose-finish] sends, \\[gascity-compose-abort] cancels."
            (if notify
                "\n# Notify toggles --notify with \\[gascity-compose-toggle-notify]."
              "")
            "\n"))
   'face 'shadow))

(cl-defun gascity-compose (&key buffer-name header finish origin (body "")
                                notify)
  "Pop a compose buffer BUFFER-NAME with a read-only HEADER over a body area.
HEADER is an alist of (LABEL . VALUE) lines.  FINISH is a function of one
argument, the body string, run by the compose finish key
\\<gascity-compose-mode-map>\\[gascity-compose-finish]; it
builds and starts the gc command.  ORIGIN is the buffer whose view is
refreshed after finishing.  BODY pre-fills the editable area.  NOTIFY
non-nil adds a `Notify: no' header line that
\\[gascity-compose-toggle-notify] flips; FINISH then takes a second
argument, the flag.  Help text below the body is display-only (an
overlay), never part of the body.  Returns the compose buffer.

The buffer is keyed and pinned to the city it is composed for
\(`gascity-view-get-buffer-create', from the invoking view's
`default-directory').  The pin is what routes the finish closure's gc
call: composing from a remote city's view must run gc on that host, not
wherever a same-named draft buffer happened to be created earlier."
  (let ((buf (gascity-view-get-buffer-create (or buffer-name "*gc-compose*"))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (gascity-compose-mode)
        (setq gascity-compose--notify (if notify nil 'unsupported))
        (setq gascity-compose--body-start
              (copy-marker (gascity-compose--insert-header
                            (if notify
                                (append header (list (cons "Notify" "no")))
                              header))))
        (when (and body (not (string-empty-p body)))
          (insert body))
        ;; Both ends advance, so the empty overlay stays at the end of
        ;; the buffer however the body grows.
        (overlay-put (make-overlay (point-max) (point-max) nil t t)
                     'after-string (gascity-compose--help notify))
        (goto-char (point-max)))
      (setq gascity-compose--finish-function finish
            gascity-compose--origin-buffer origin))
    (pop-to-buffer buf)
    buf))

(defun gascity-compose-finish ()
  "Finish the compose buffer: run its closure with the body, then discard.
The closure builds the gc command and STARTS it (dashboard-v3 D9, §8.5:
the send runs async and refreshes the originating view when gc
answers), so this draft buffer is killed at once."
  (interactive)
  (unless (derived-mode-p 'gascity-compose-mode)
    (user-error "Not in a gascity compose buffer"))
  (let ((finish gascity-compose--finish-function)
        (body (gascity-compose--body))
        (buf (current-buffer)))
    (unless finish (user-error "This compose buffer has no finish action"))
    (if (eq gascity-compose--notify 'unsupported)
        (funcall finish body)
      (funcall finish body gascity-compose--notify))
    (when (buffer-live-p buf)
      (let ((win (get-buffer-window buf)))
        (when (window-live-p win) (ignore-errors (quit-window nil win))))
      (kill-buffer buf))))

(defun gascity-compose-toggle-notify ()
  "Flip whether the message nudges its recipient (`--notify')."
  (interactive)
  (when (eq gascity-compose--notify 'unsupported)
    (user-error "This draft has no notify option"))
  (setq gascity-compose--notify (not gascity-compose--notify))
  (save-excursion
    (goto-char (point-min))
    (let ((match (text-property-search-forward 'gascity-compose-field "Notify" t)))
      (when match
        (let ((inhibit-read-only t))
          (goto-char (prop-match-beginning match))
          (delete-region (point) (prop-match-end match))
          (insert (propertize (format "Notify: %s\n"
                                      (if gascity-compose--notify "yes" "no"))
                              'gascity-compose-field "Notify"
                              'read-only t 'rear-nonsticky t))))))
  (message "Notify %s" (if gascity-compose--notify "on" "off")))

(defun gascity-compose-abort ()
  "Discard the compose buffer without acting."
  (interactive)
  (unless (derived-mode-p 'gascity-compose-mode)
    (user-error "Not in a gascity compose buffer"))
  (let ((buf (current-buffer)))
    (let ((win (get-buffer-window buf)))
      (when (window-live-p win) (ignore-errors (quit-window nil win))))
    (kill-buffer buf)
    (message "Compose aborted")))

(provide 'gascity-compose)
;;; gascity-compose.el ends here
