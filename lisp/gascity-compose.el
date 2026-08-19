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
;; the closure builds and `gascity-command-act's the gc command — then
;; refreshes the originating view and discards the buffer.  `C-c C-k'
;; (`gascity-compose-abort') throws the draft away.  The compose buffer
;; knows nothing about gc commands; it only collects a body and calls back.

;;; Code:

(require 'cl-lib)
(require 'text-mode)
(require 'gascity-context)   ; view-buffer factory (buffer keyed to its city)

;; The refresh helper lives in gascity-action, which requires this module;
;; call it by name (guarded) after a finish to avoid a load cycle.
(declare-function gascity--refresh-current-view "gascity-action")

(defvar-local gascity-compose--finish-function nil
  "Closure run with the body string when the compose buffer is finished.")

(defvar-local gascity-compose--origin-buffer nil
  "Buffer whose gascity view is refreshed after a finish.")

(defvar-local gascity-compose--body-start nil
  "Marker at the first editable position, just past the read-only header.")

(defvar-keymap gascity-compose-mode-map
  :doc "Keymap for `gascity-compose-mode'."
  "C-c C-c" #'gascity-compose-finish
  "C-c C-k" #'gascity-compose-abort)

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
      (insert (format "%s: %s\n" (car field) (cdr field))))
    (insert "--- compose body below ---\n")
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

(cl-defun gascity-compose (&key buffer-name header finish origin (body ""))
  "Pop a compose buffer BUFFER-NAME with a read-only HEADER over a body area.
HEADER is an alist of (LABEL . VALUE) lines.  FINISH is a function of one
argument, the body string, run on `C-c C-c'; it builds and acts the gc
command.  ORIGIN is the buffer whose view is refreshed after finishing.
BODY pre-fills the editable area.  Returns the compose buffer.

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
        (setq gascity-compose--body-start
              (copy-marker (gascity-compose--insert-header header)))
        (when (and body (not (string-empty-p body)))
          (insert body))
        (goto-char (point-max)))
      (setq gascity-compose--finish-function finish
            gascity-compose--origin-buffer origin))
    (pop-to-buffer buf)
    buf))

(defun gascity-compose-finish ()
  "Finish the compose buffer: run its closure with the body, refresh, discard.
The closure builds and acts the gc command; the originating view is then
refreshed in place and this draft buffer is killed."
  (interactive)
  (unless (derived-mode-p 'gascity-compose-mode)
    (user-error "Not in a gascity compose buffer"))
  (let ((finish gascity-compose--finish-function)
        (origin gascity-compose--origin-buffer)
        (body (gascity-compose--body))
        (buf (current-buffer)))
    (unless finish (user-error "This compose buffer has no finish action"))
    (funcall finish body)
    (when (and (buffer-live-p origin) (not (eq origin buf)))
      (with-current-buffer origin
        (when (fboundp 'gascity--refresh-current-view)
          (gascity--refresh-current-view))))
    (when (buffer-live-p buf)
      (let ((win (get-buffer-window buf)))
        (when (window-live-p win) (ignore-errors (quit-window nil win))))
      (kill-buffer buf))))

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
