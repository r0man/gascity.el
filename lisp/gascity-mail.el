;;; gascity-mail.el --- Mail: inbox, thread, compose -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Mail (dashboard-v3 §7.9), three buffers:
;;
;; - The inbox, `gascity-mail' (`j m'; `*gascity-mail: CITY*'), a
;;   tabulated list of `gc mail inbox':
;;
;;      ●  From                     Subject                   When
;;      ●  mayor                    handoff: continue …       3h
;;         mayor                    re: sling-ga-rs12         yesterday
;;
;;   Unread rows carry `●' and are bold.  `gc mail inbox' lists unread
;;   mail only, so a message read here stays in the list (without `●')
;;   until `g', so `u' can take it back.  RET shows a message without
;;   marking it read (no gc call); `r' opens its thread and marks it
;;   read; `a' archives (confirmed), `u' marks unread; `R' replies.
;;   `r', `u' and `a' act on every row of an active region: one gc call
;;   per row, each row showing `…' until its call returns, then one
;;   summary (`Archived 7 of 8; 1 failed, see *gascity-log: CITY*').
;;
;; - The thread, `*gascity-mail-thread: THREAD*' (`special-mode'): it
;;   opens at once with `…' and fills from `gc mail thread --json';
;;   `R' reply, `a' archive, `u' unread, `q' quit.
;;
;; - Compose and reply: the `gascity-compose' buffer with a Notify
;;   toggle (C-c C-n → `--notify').  C-c C-c closes the draft at once
;;   and sends in the background; the body travels as an argv element
;;   (`--message'), never through a temp file.  A failed send puts the
;;   body on the kill ring.
;;
;; Every gc call is asynchronous (D9): reads go through the store
;; (`gascity-store-fetch'), mutations through the action lane
;; (`gascity-command-act-async' → `gascity-store-action'), which
;; serializes calls per message and logs failures.

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
(require 'gascity-context)
(require 'gascity-store)
(require 'gascity-domain)
(require 'gascity-types)
(require 'gascity-section)
(require 'gascity-tabulated)
(require 'gascity-compose)
(require 'gascity-action)

(declare-function gascity-live-header-string "gascity-live")

;;; State

(defconst gascity-mail-inbox-buffer-name "*gascity-mail: %s*"
  "Format of the inbox buffer's base name; %s is the city name.")

(defconst gascity-mail-thread-buffer-name "*gascity-mail-thread: %s*"
  "Format of a thread buffer's base name; %s is the thread id.")

(defconst gascity-mail-windows '("1h" "2h" "24h" "7d")
  "The window choices of the inbox's `-W' filter.")

(defconst gascity-mail--width 76
  "Width of the thread buffer's rules and right-aligned hints.")

(defvar-local gascity-mail--city nil
  "The city name this inbox shows.")

(defvar-local gascity-mail-inbox--filter nil
  "The inbox filter plist: `:unread' (unread only), `:from', `:window'
\(a duration: only mail newer than that) and `:search'.")

(defvar-local gascity-mail--messages nil
  "The messages of the last `gc mail inbox' payload.")

(defvar-local gascity-mail--payload nil
  "The last `gc mail inbox' payload adopted (to skip repeat deliveries).")

(defvar-local gascity-mail--status 'loading
  "Where the inbox read stands: `loading', `ready', or (error . MESSAGE).")

(defvar-local gascity-mail--overrides nil
  "Hash table: message id → `read' or `unread', as changed here.
gc's answer wins once it agrees; until then the row shows the change.")

(defvar-local gascity-mail--kept nil
  "Hash table: message id → message read here, kept visible until `g'.
`gc mail inbox' lists unread mail only; a message read here would
vanish on the next refresh, and with it the chance to `u' it.")

(defvar-local gascity-mail--archived nil
  "Hash table: message id → t, archived here (hidden at once).")

(defvar-local gascity-mail-thread--id nil
  "The thread (or message) id this buffer shows.")

(defvar-local gascity-mail-thread--messages nil
  "The thread's messages, oldest first.")

(defvar-local gascity-mail-thread--status 'loading
  "`loading', `ready' or (error . MESSAGE).")

(defvar-local gascity-mail-thread--inbox nil
  "The inbox buffer the thread was opened from, or nil.")

(defun gascity-mail--table (var)
  "Return the hash table in buffer-local VAR, creating it."
  (or (symbol-value var)
      (set var (make-hash-table :test 'equal))))

;;; Model (pure)

(defun gascity-mail--unread-p (message)
  "Return non-nil when MESSAGE is unread, counting changes made here."
  (pcase (and gascity-mail--overrides
              (gethash (gascity-mail-id message) gascity-mail--overrides))
    ('read nil)
    ('unread t)
    (_ (not (gascity-mail-read message)))))

(defun gascity-mail--visible ()
  "Return the messages the inbox shows, newest first, before filtering.
The payload's messages plus those read here, minus those archived here."
  (let* ((archived (or gascity-mail--archived (make-hash-table)))
         (payload (seq-remove (lambda (m) (gethash (gascity-mail-id m) archived))
                              gascity-mail--messages))
         (ids (mapcar #'gascity-mail-id payload))
         (kept nil))
    (when gascity-mail--kept
      (maphash (lambda (id m)
                 (unless (or (member id ids) (gethash id archived))
                   (push m kept)))
               gascity-mail--kept))
    (sort (append payload kept)
          (lambda (a b)
            (> (or (gascity-ui-parse-time (gascity-mail-created-at a)) 0)
               (or (gascity-ui-parse-time (gascity-mail-created-at b)) 0))))))

(defun gascity-mail-inbox--match-p (message filter &optional now)
  "Return non-nil when MESSAGE passes FILTER (the inbox filter plist).
NOW (default the current time) anchors the `:window' filter."
  (let ((from (plist-get filter :from))
        (window (plist-get filter :window))
        (search (plist-get filter :search)))
    (and (or (not (plist-get filter :unread)) (gascity-mail--unread-p message))
         (or (null from) (equal from (gascity-mail-from message)))
         (or (null window)
             (let ((time (gascity-ui-parse-time (gascity-mail-created-at message))))
               (and time (>= time (- (or now (float-time))
                                     (gascity-ui-duration-seconds window))))))
         (or (null search)
             (let ((case-fold-search t))
               (string-match-p (regexp-quote search)
                               (format "%s %s %s"
                                       (or (gascity-mail-from message) "")
                                       (or (gascity-mail-subject message) "")
                                       (or (gascity-mail-body message) ""))))))))

(defun gascity-mail-inbox--entry (message)
  "Return the tabulated entry of MESSAGE (a `gascity-mail-message').
The first column is `●' for unread mail; unread rows are bold."
  (let* ((unread (gascity-mail--unread-p message))
         (face (and unread 'bold)))
    (list message
          ;; `…' while an action runs comes from the shared list
          ;; renderer (`gascity-tabulated--mark-pending', column 0).
          (vector (if unread (gascity-ui-glyph 'ok) " ")
                  (propertize (or (gascity-mail-from message) "") 'face face)
                  (propertize (or (gascity-mail-subject message) "") 'face face)
                  (gascity-ui-time (gascity-mail-created-at message))))))

(defun gascity-mail--entries ()
  "Return the inbox entries under the current filter."
  (let ((now (float-time)))
    (mapcar #'gascity-mail-inbox--entry
            (seq-filter (lambda (m) (gascity-mail-inbox--match-p
                                     m gascity-mail-inbox--filter now))
                        (gascity-mail--visible)))))

(defun gascity-mail--adopt (payload)
  "Adopt the `gc mail inbox' PAYLOAD as the inbox's messages.
A change made here that gc now reports too is forgotten (gc's answer
wins from then on)."
  (setq gascity-mail--messages
        (gascity-domain-decode-list 'gascity-mail-message
                                    (alist-get 'messages payload))
        gascity-mail--status 'ready)
  (when gascity-mail--overrides
    (dolist (m gascity-mail--messages)
      ;; Listed means unread for gc.
      (when (eq (gethash (gascity-mail-id m) gascity-mail--overrides) 'unread)
        (remhash (gascity-mail-id m) gascity-mail--overrides)))))

;;; Rendering

(defun gascity-mail-inbox--render (&optional keep-page)
  "Re-render the inbox rows from the messages in hand.
KEEP-PAGE stays on the current page; point stays on its row."
  (when (derived-mode-p 'gascity-mail-inbox-mode)
    (let ((page gascity-tabulated--current-page))
      (setq gascity-tabulated--all-entries (gascity-mail--entries)
            gascity-tabulated--base-name "Mail"
            gascity-tabulated--page-size (beads-pager-window-page-size))
      (setq gascity-tabulated--current-page
            (if keep-page (max 1 (min page (gascity-tabulated--total-pages))) 1))
      (gascity-tabulated--refresh-display)
      (force-mode-line-update))))

(defun gascity-mail--filter-text ()
  "Return the active inbox filters as words, or nil."
  (let ((parts (cl-loop for (key value) on gascity-mail-inbox--filter by #'cddr
                        when value
                        collect (if (eq value t)
                                    (substring (symbol-name key) 1)
                                  (format "%s=%s" (substring (symbol-name key) 1)
                                          value)))))
    (and parts (string-join parts " "))))

(defun gascity-mail-inbox--header-line ()
  "Return the inbox header line: city, unread / total, filters, hints.
Pure over buffer-local state (§8.3 R2)."
  (let* ((host (file-remote-p default-directory 'host))
         (visible (gascity-mail--visible))
         (count (pcase gascity-mail--status
                  ('loading (propertize "…" 'face 'gascity-dim))
                  (`(error . ,msg)
                   (concat (gascity-ui-glyph 'fail) " "
                           (propertize (format "gc mail inbox: %s"
                                               (or (gascity-ui-first-line msg) "failed"))
                                       'face 'gascity-dim)))
                  (_ (format "%d unread / %d"
                             (seq-count #'gascity-mail--unread-p visible)
                             (length visible)))))
         (filters (gascity-mail--filter-text))
         (live (and (fboundp 'gascity-live-header-string)
                    (gascity-live-header-string)))
         (right (concat (propertize "/ filter  c compose" 'face 'gascity-dim)
                        (if live (concat "  " live) ""))))
    (concat " " (propertize (or gascity-mail--city "?") 'face 'gascity-city)
            (if host (propertize (concat " @" host) 'face 'gascity-dim) "")
            " " (propertize "mail" 'face 'gascity-header)
            "  " count
            (if filters (concat "  " (propertize filters 'face 'transient-value)) "")
            (propertize " " 'display
                        `(space :align-to (- right ,(1+ (string-width right)))))
            right)))

(defun gascity-mail--detail-lines (message _entry)
  "Return the `*gascity-detail*' lines of MESSAGE: header, first body lines."
  (if (gascity-mail-message-p message)
      (append (list (format "From     %s" (or (gascity-mail-from message) ""))
                    (format "To       %s" (or (gascity-mail-to message) ""))
                    (format "Subject  %s" (or (gascity-mail-subject message) ""))
                    (format "Date     %s" (or (gascity-mail-created-at message) ""))
                    "")
              (seq-take (split-string (or (gascity-mail-body message) "") "\n") 5))
    (list (format "%s" message))))

;;; Reading

(defvar-local gascity-mail--sub nil
  "The inbox's store subscription (repaints on any re-read of the inbox).")

(defun gascity-mail--inbox-args ()
  "Return the gc argv of the inbox read."
  '("mail" "inbox"))

(defun gascity-mail--paint (buffer payload)
  "Adopt PAYLOAD in inbox BUFFER and re-render it in place.
A payload already adopted is skipped: the store notifies subscribers
of a failed re-read too, with the old payload."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (unless (and gascity-mail--payload (eq payload gascity-mail--payload))
        (setq gascity-mail--payload payload)
        (gascity-mail--adopt payload)
        (gascity-mail-inbox--render t)))))

(defun gascity-mail-inbox-refresh (&optional force)
  "Re-read the inbox through the store and render it (`g').
The rows in hand stay while the read runs and when it fails (the
header line says so).  Interactively, or with FORCE, messages read
here since the last `g' leave the list: gc's inbox is the truth."
  (interactive (list t))
  (unless (derived-mode-p 'gascity-mail-inbox-mode)
    (user-error "Not in the mail inbox"))
  (when force
    (setq gascity-mail--kept nil
          gascity-mail--overrides nil))
  (let ((buffer (current-buffer))
        (args (gascity-mail--inbox-args)))
    ;; Passive repaint: the inbox re-read for anyone (an invalidation
    ;; after an action, the live router) refreshes these rows too.
    (unless gascity-mail--sub
      (setq gascity-mail--sub
            (gascity-store-subscribe
             args
             (lambda (snapshot)
               (when (eq (plist-get snapshot :status) 'ready)
                 (gascity-mail--paint buffer (plist-get snapshot :data))))
             :buffer buffer))
      (add-hook 'kill-buffer-hook
                (lambda () (gascity-store-unsubscribe gascity-mail--sub))
                nil t))
    (unless (eq gascity-mail--status 'ready)
      (setq gascity-mail--status 'loading))
    (gascity-store-fetch
     args
     (lambda (payload) (gascity-mail--paint buffer payload))
     (lambda (msg)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (setq gascity-mail--status (cons 'error msg))
           (force-mode-line-update)
           (message "gascity: %s" msg))))
     :force t)))

;;; Targets

(defun gascity-mail--id-at-point ()
  "Return the message id of the mail at point, or signal a `user-error'."
  (let* ((message (gascity-mail-at-point))
         (id (and message (gascity-mail-id message))))
    (if (and id (stringp id) (not (string-empty-p id)))
        id
      (user-error "No message at point"))))

(defun gascity-mail--targets ()
  "Return the messages a verb acts on: the region's rows, else the row at point.
In the inbox an active region selects every row it touches (and is
deactivated); elsewhere the message at point."
  (if (and (use-region-p) (derived-mode-p 'gascity-mail-inbox-mode))
      (let ((end (region-end)) messages)
        (save-excursion
          (goto-char (region-beginning))
          (while (and (< (point) end) (not (eobp)))
            (let ((id (tabulated-list-get-id)))
              (when (gascity-mail-message-p id) (push id messages)))
            (forward-line 1)))
        (deactivate-mark)
        (or (nreverse messages) (user-error "No messages in the region")))
    (list (or (gascity-mail-at-point)
              (gascity-mail-message :id (gascity-mail--id-at-point))))))

(defun gascity-mail--inbox ()
  "Return the inbox buffer the current mail buffer belongs to, or nil."
  (cond ((derived-mode-p 'gascity-mail-inbox-mode) (current-buffer))
        ((and (derived-mode-p 'gascity-mail-thread-mode)
              (buffer-live-p gascity-mail-thread--inbox))
         gascity-mail-thread--inbox)))

;;; Actions (D9: async, one call per message, one summary)

(defconst gascity-mail--verbs
  '((read   "Marked read"   gascity-command-mail-mark-read)
    (unread "Marked unread" gascity-command-mail-mark-unread)
    (archive "Archived"     gascity-command-mail-archive))
  "VERB → (DONE-LABEL COMMAND-CLASS) of the inbox's bulk actions.")

(defun gascity-mail--run (verb id on-success on-error)
  "Start the gc call of VERB on message ID on the action lane.
The one mutation call site of the inbox: ON-SUCCESS gets the result,
ON-ERROR the failure line (the store logs the full stderr).  Calls on
one message run in order; the message is pending meanwhile."
  (gascity-command-act-async
   (funcall (nth 2 (assq verb gascity-mail--verbs)) :id id)
   :target id :origin nil :invalidate nil
   :on-success on-success :on-error on-error))

(defun gascity-mail--note (inbox id verb message)
  "Record in INBOX that VERB succeeded on message ID (MESSAGE, when known)."
  (when (buffer-live-p inbox)
    (with-current-buffer inbox
      (pcase verb
        ('archive (puthash id t (gascity-mail--table 'gascity-mail--archived)))
        ('read
         (puthash id 'read (gascity-mail--table 'gascity-mail--overrides))
         (when message
           (puthash id message (gascity-mail--table 'gascity-mail--kept))))
        ('unread
         (puthash id 'unread (gascity-mail--table 'gascity-mail--overrides)))))))

(defun gascity-mail--summary (verb ids failures)
  "Return the one-line summary of VERB over IDS with FAILURES (messages)."
  (let ((label (nth 1 (assq verb gascity-mail--verbs)))
        (n (length ids))
        (failed (length failures)))
    (cond ((= failed 0)
           (if (= n 1) (format "%s %s" label (car ids))
             (format "%s %d messages" label n)))
          ((= n 1) (car failures))
          (t (format "%s %d of %d; %d failed, see %s"
                     label (- n failed) n failed
                     (gascity-store-log-buffer-name default-directory))))))

(defun gascity-mail--bulk (verb messages &optional quiet)
  "Start VERB (`read', `unread', `archive') on every one of MESSAGES.
One async call per message; each row shows `…' until its call returns.
When the last one returns, one summary is echoed (QUIET: failures
only) and the inbox re-renders and re-reads."
  (let* ((inbox (gascity-mail--inbox))
         (ids (mapcar #'gascity-mail-id messages))
         (left (length ids))
         (failures nil)
         (settle
          (lambda ()
            (when (= (cl-decf left) 0)
              (when (or failures (not quiet))
                (message "%s" (gascity-mail--summary verb ids (nreverse failures))))
              (when (buffer-live-p inbox)
                (with-current-buffer inbox
                  (gascity-mail-inbox--render t)
                  (gascity-mail-inbox-refresh))))
            (when (buffer-live-p inbox)
              (with-current-buffer inbox (gascity-mail-inbox--render t))))))
    (cl-loop for message in messages
             for id in ids
             do (let ((message message) (id id))
                  (gascity-mail--run
                   verb id
                   (lambda (_result)
                     (gascity-mail--note inbox id verb message)
                     (funcall settle))
                   (lambda (msg)
                     (push msg failures)
                     (funcall settle)))))
    ;; The rows are pending now: show `…'.
    (when (buffer-live-p inbox)
      (with-current-buffer inbox (gascity-mail-inbox--render t)))
    (when (derived-mode-p 'gascity-mail-thread-mode)
      (gascity-mail-thread--render))))

;;;###autoload
(defun gascity-mail-read-at-point ()
  "Read the message at point: open its thread and mark it read (`r').
The thread buffer opens at once and fills in when gc answers; the
mark-read is a separate async call.  With an active region, mark
every message in it read instead."
  (interactive)
  (if (and (use-region-p) (derived-mode-p 'gascity-mail-inbox-mode))
      (gascity-mail--bulk 'read (gascity-mail--targets))
    (let* ((message (car (gascity-mail--targets)))
           (inbox (gascity-mail--inbox)))
      (gascity-mail-thread-show message inbox)
      (when (gascity-mail--unread-p-in inbox message)
        (with-current-buffer (or inbox (current-buffer))
          (gascity-mail--bulk 'read (list message) t))))))

(defun gascity-mail--unread-p-in (inbox message)
  "Return non-nil when MESSAGE is unread as INBOX (or the current buffer) sees it."
  (with-current-buffer (if (buffer-live-p inbox) inbox (current-buffer))
    (gascity-mail--unread-p message)))

;;;###autoload
(defun gascity-mail-mark-read-at-point ()
  "Mark the message at point, or every message in the region, read."
  (interactive)
  (gascity-mail--bulk 'read (gascity-mail--targets)))

;;;###autoload
(defun gascity-mail-mark-unread-at-point ()
  "Mark the message at point, or every message in the region, unread (`u')."
  (interactive)
  (gascity-mail--bulk 'unread (gascity-mail--targets)))

;;;###autoload
(defun gascity-mail-archive-at-point ()
  "Archive the message at point, or every message in the region (`a').
Confirmed first; then one async call per message."
  (interactive)
  (let ((messages (gascity-mail--targets)))
    (when (if (cdr messages)
              (gascity-action--confirm "Archive %d messages? " (length messages))
            (gascity-action--confirm "Archive message %s? "
                                     (gascity-mail-id (car messages))))
      (gascity-mail--bulk 'archive messages))))

(defun gascity-mail-inbox-show ()
  "Show the message at point without marking it read (RET).
No gc call: the inbox payload carries the body."
  (interactive)
  (let ((message (tabulated-list-get-id)))
    (unless (gascity-mail-message-p message) (user-error "No message at point"))
    (gascity-mail-thread-show message (current-buffer) t)))

(cl-defmethod gascity-at-point-visit ((message gascity-mail-message))
  "Visit MESSAGE: show it in its thread buffer, without a gc call."
  (gascity-mail-thread-show message (gascity-mail--inbox) t))

;;; Thread buffer

(defun gascity-mail--date (ts)
  "Return TS as `2026-09-25 14:26 (12m ago)', local time."
  (let ((time (gascity-ui-parse-time ts)))
    (if (null time)
        (or ts "")
      (let ((rel (gascity-ui-relative-time time)))
        (format "%s (%s)" (format-time-string "%F %R" time)
                (if (< (- (float-time) time) 86400) (concat rel " ago") rel))))))

(defun gascity-mail--rule ()
  "Return the thread buffer's horizontal rule line."
  (propertize (concat (make-string gascity-mail--width ?─) "\n")
              'face 'gascity-dim))

(defun gascity-mail-thread--message-text (message)
  "Return the text block of MESSAGE in a thread, stamped with the message."
  (propertize
   (concat (gascity-ui-fit (concat (propertize "From  " 'face 'gascity-dim)
                                   (or (gascity-mail-from message) ""))
                           40)
           (propertize "To  " 'face 'gascity-dim) (or (gascity-mail-to message) "")
           "\n"
           (propertize "Date  " 'face 'gascity-dim)
           (gascity-mail--date (gascity-mail-created-at message))
           (if (and (buffer-live-p gascity-mail-thread--inbox)
                    (gascity-mail--unread-p-in gascity-mail-thread--inbox message))
               (concat "  " (gascity-ui-glyph 'ok) " unread")
             "")
           "\n\n"
           (let ((body (string-trim-right (or (gascity-mail-body message) ""))))
             (if (string-empty-p body) (propertize "(no body)" 'face 'gascity-dim) body))
           "\n\n")
   'gascity-mail-message message))

(defun gascity-mail-thread--render ()
  "Render the thread buffer from its messages and status."
  (let* ((inhibit-read-only t)
         (line (line-number-at-pos))
         (messages gascity-mail-thread--messages)
         (latest (car (last messages)))
         (subject (or (and messages (gascity-mail-subject (car messages))) "")))
    (erase-buffer)
    (insert (propertize
             (concat (gascity-ui-right-align
                      (propertize subject 'face 'gascity-header)
                      (propertize (or gascity-mail-thread--id "") 'face 'gascity-dim)
                      gascity-mail--width)
                     "\n")
             'gascity-mail-message latest))
    (insert (gascity-mail--rule))
    (pcase gascity-mail-thread--status
      ('loading (insert (propertize "…\n" 'face 'gascity-dim)))
      (`(error . ,msg)
       (insert (gascity-ui-glyph 'fail) " "
               (propertize (format "gc mail thread: %s\n"
                                   (or (gascity-ui-first-line msg) "failed"))
                           'face 'gascity-dim))))
    (let ((first t))
      (dolist (m messages)
        (unless first (insert (gascity-mail--rule)))
        (setq first nil)
        (insert (gascity-mail-thread--message-text m))))
    (insert (propertize
             (concat (make-string (- gascity-mail--width 36) ?\s)
                     "R reply  a archive  u unread  q quit\n")
             'face 'gascity-dim
             'gascity-mail-message latest))
    (goto-char (point-min))
    (forward-line (1- line))))

(defun gascity-mail-thread-show (message &optional inbox cached)
  "Show MESSAGE's thread; INBOX is the inbox it was opened from.
The buffer opens at once.  With CACHED it shows MESSAGE alone, no gc
call (RET); otherwise `…' until `gc mail thread' answers, then every
message of the thread."
  (let* ((tid (or (gascity-mail-thread-id message) (gascity-mail-id message)))
         (buf (gascity-view-get-buffer-create
               (format gascity-mail-thread-buffer-name tid))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-mail-thread-mode)
        (gascity-mail-thread-mode))
      (setq gascity-mail-thread--id tid
            gascity-mail-thread--inbox inbox)
      (unless (and gascity-mail-thread--messages (not cached))
        (setq gascity-mail-thread--messages (list message)))
      (setq gascity-mail-thread--status (if cached 'ready 'loading))
      (gascity-mail-thread--render)
      (unless cached (gascity-mail-thread-refresh)))
    (pop-to-buffer buf)
    buf))

(defun gascity-mail-thread-refresh ()
  "Re-read this thread with `gc mail thread --json' (`g')."
  (interactive)
  (let ((buffer (current-buffer)))
    (gascity-store-fetch
     (list "mail" "thread" gascity-mail-thread--id)
     (lambda (payload)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (let ((messages (gascity-domain-decode-list
                            'gascity-mail-message (alist-get 'messages payload))))
             (when messages (setq gascity-mail-thread--messages messages)))
           (setq gascity-mail-thread--status 'ready)
           (gascity-mail-thread--render))))
     (lambda (msg)
       (when (buffer-live-p buffer)
         (with-current-buffer buffer
           (setq gascity-mail-thread--status (cons 'error msg))
           (gascity-mail-thread--render))))
     :force t)))

(defun gascity-mail-thread-next (&optional n)
  "Move to the Nth next message of the thread."
  (interactive "p")
  (dotimes (_ (abs (or n 1)))
    (let ((match (if (> (or n 1) 0)
                     (progn (end-of-line)
                            (text-property-search-forward 'gascity-mail-message nil nil t))
                   (text-property-search-backward 'gascity-mail-message nil nil t))))
      (when match (goto-char (prop-match-beginning match))))))

(defun gascity-mail-thread-previous (&optional n)
  "Move to the Nth previous message of the thread."
  (interactive "p")
  (gascity-mail-thread-next (- (or n 1))))

(defvar-keymap gascity-mail-thread-mode-map
  :doc "Keymap for `gascity-mail-thread-mode'."
  :parent special-mode-map
  "g" #'gascity-mail-thread-refresh
  "R" #'gascity-mail-reply-at-point
  "a" #'gascity-mail-archive-at-point
  "u" #'gascity-mail-mark-unread-at-point
  "c" #'gascity-mail-dispatch
  "TAB" #'gascity-mail-thread-next
  "<tab>" #'gascity-mail-thread-next
  "<backtab>" #'gascity-mail-thread-previous
  "S-TAB" #'gascity-mail-thread-previous
  "S-<tab>" #'gascity-mail-thread-previous
  "j" 'gascity-jump-prefix
  "?" 'gascity-dispatch)

(define-derived-mode gascity-mail-thread-mode special-mode "GC-Thread"
  "Major mode of a mail thread (dashboard-v3 §7.9).
\\{gascity-mail-thread-mode-map}"
  :group 'gascity
  (setq truncate-lines nil)
  (visual-line-mode 1))

;;; Compose (send / reply)

(defun gascity-mail--reply-subject (subject)
  "Return a default reply subject for SUBJECT (prefix \"RE: \" once)."
  (let ((s (or subject "")))
    (if (string-match-p "\\`[Rr][Ee]: " s) s (concat "RE: " s))))

(defun gascity-mail--send-async (command origin done)
  "Start sending mail COMMAND; refresh ORIGIN and echo DONE on success.
On failure the draft body goes to the kill ring, so a closed compose
buffer loses nothing."
  (let ((body (oref command message)))
    (gascity-command-act-async
     command
     :origin origin
     :on-success (lambda (_) (message "%s" done))
     :on-error (lambda (msg)
                 (when (and (stringp body) (not (string-empty-p body)))
                   (kill-new body))
                 (message "%s (draft saved to the kill ring)" msg)))))

;;;###autoload
(defun gascity-mail-send (to subject)
  "Compose and send a new message to TO with SUBJECT (both prompted).
Opens a `gascity-compose' buffer for the body; in it,
\\<gascity-compose-mode-map>\\[gascity-compose-finish] sends (in the
background), \\[gascity-compose-toggle-notify] toggles `--notify' and
\\[gascity-compose-abort] aborts.  TO completes over session aliases
but accepts any address."
  (interactive
   (let ((to (gascity-action--read-assignee "Send mail to: ")))
     (list to (read-string (format "Subject (to %s): " to)))))
  (let ((origin (gascity-mail--inbox)))
    (gascity-compose
     :buffer-name (format "*gc-mail to %s*" to)
     :header (list (cons "To" to) (cons "Subject" subject))
     :origin origin
     :notify t
     :finish (lambda (body notify)
               (gascity-mail--send-async
                (gascity-command-mail-send
                 :to to :subject subject :message body :notify notify)
                origin (format "Sent to %s" to))))))

;;;###autoload
(defun gascity-mail-reply-at-point ()
  "Reply to the message at point — compose the body, then send to its sender.
The subject defaults to the original prefixed with \"RE: \"."
  (interactive)
  (let* ((message (or (gascity-mail-at-point) (user-error "No message at point")))
         (id (gascity-mail-id message))
         (to (or (gascity-mail-from message) "(sender)"))
         (subject (read-string
                   "Reply subject: "
                   (gascity-mail--reply-subject (gascity-mail-subject message))))
         (origin (gascity-mail--inbox)))
    (gascity-compose
     :buffer-name (format "*gc-mail reply %s*" id)
     :header (list (cons "To" to) (cons "Subject" subject))
     :origin origin
     :notify t
     :finish (lambda (body notify)
               (gascity-mail--send-async
                (gascity-command-mail-reply
                 :id id :subject subject :message body :notify notify)
                origin (format "Replied to %s" to))))))

;;;###autoload (autoload 'gascity-mail-dispatch "gascity-mail" nil t)
(beads-define-prefix gascity-mail-dispatch ()
  "Mail actions on the message at point (or the region), and compose."
  ["Mail"
   ("c" "Compose…" gascity-mail-send)
   ("r" "Read (thread)" gascity-mail-read-at-point)
   ("R" "Reply…" gascity-mail-reply-at-point)
   ("m" "Mark read" gascity-mail-mark-read-at-point)
   ("u" "Mark unread" gascity-mail-mark-unread-at-point)
   ("a" "Archive…" gascity-mail-archive-at-point)])

;;; Inbox filter (`/', §7.9, §5.5)

(defun gascity-mail--set-filter (key value)
  "Set inbox filter KEY to VALUE (nil clears) and re-render."
  (setq gascity-mail-inbox--filter
        (if value
            (plist-put (copy-sequence gascity-mail-inbox--filter) key value)
          (gascity-tabulated--plist-drop gascity-mail-inbox--filter key)))
  (gascity-mail-inbox--render))

(defun gascity-mail--senders ()
  "Return the senders of the messages in hand, sorted."
  (sort (delete-dups (delq nil (mapcar #'gascity-mail-from (gascity-mail--visible))))
        #'string<))

(gascity-filter-define-toggle gascity-mail-inbox-filter-unread
  :unread "unread only")
(gascity-filter-define-choice gascity-mail-inbox-filter-from
  :from "from" (gascity-mail--senders))
(gascity-filter-define-choice gascity-mail-inbox-filter-window
  :window "window" gascity-mail-windows)
(gascity-filter-define-choice gascity-mail-inbox-filter-search
  :search "search" nil "none")

(beads-define-prefix gascity-mail-inbox-filter ()
  "Filter the mail inbox; each change applies at once (§7.9)."
  ["Filter mail"
   ("-u" gascity-mail-inbox-filter-unread)
   ("-a" gascity-mail-inbox-filter-from)
   ("-W" gascity-mail-inbox-filter-window)
   ("-q" gascity-mail-inbox-filter-search)
   ("-S" gascity-tabulated-sort-by)
   ("x" gascity-filter-reset)])

;;; Inbox mode

(defvar-keymap gascity-mail-inbox-mode-map
  :doc "Keymap for `gascity-mail-inbox-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-mail-inbox-refresh
  "/"   #'gascity-mail-inbox-filter
  ;; RET is the cheap show (no gc call, stays unread); `r' fetches the
  ;; thread and marks read.  `r'/`u'/`a' take an active region.
  "RET" #'gascity-mail-inbox-show
  "r"   #'gascity-mail-read-at-point
  "R"   #'gascity-mail-reply-at-point
  "a"   #'gascity-mail-archive-at-point
  "u"   #'gascity-mail-mark-unread-at-point
  "c"   #'gascity-mail-dispatch)

(define-derived-mode gascity-mail-inbox-mode tabulated-list-mode "GC-Mail"
  "Major mode of the mail inbox (dashboard-v3 §7.9).
RET shows a message (stays unread); `r' reads its thread and marks it
read; `a' archives (confirmed); `u' marks unread; `r', `u' and `a'
act on every row of an active region.
\\{gascity-mail-inbox-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        `[("●" 1 nil) ("From" 34 t) ("Subject" 40 t)
          ("When" 10 ,(gascity-tabulated--time-sorter 3))])
  (setq tabulated-list-padding 1
        tabulated-list-sort-key nil
        tabulated-list-use-header-line nil)
  (tabulated-list-init-header)
  (gascity-tabulated--setup-things)
  (setq header-line-format '(:eval (gascity-mail-inbox--header-line)))
  (setq-local gascity-tabulated-detail-function #'gascity-mail--detail-lines)
  (setq-local gascity-filter-get-function
              (lambda (key) (plist-get gascity-mail-inbox--filter key)))
  (setq-local gascity-filter-set-function #'gascity-mail--set-filter)
  (setq-local gascity-filter-reset-function
              (lambda () (setq gascity-mail-inbox--filter nil)
                (gascity-mail-inbox--render))))

;;;###autoload
(defun gascity-mail ()
  "Show the city's mail inbox (`j m', dashboard-v3 §7.9).
The buffer is keyed to the city (host-qualified name, pinned
`default-directory')."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
         (city (or (gascity-context-city-name dir) "city"))
         (buf (gascity-view-get-buffer-create
               (format gascity-mail-inbox-buffer-name city) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-mail-inbox-mode)
        (gascity-mail-inbox-mode)
        (setq gascity-mail--city city))
      (gascity-mail-inbox-refresh))
    (pop-to-buffer buf)))

;;;###autoload
(defalias 'gascity-mail-inbox #'gascity-mail
  "Show the mail inbox (the name menus and older bindings use).")

(cl-defmethod gascity-command-execute-interactive ((_cmd gascity-command-mail-inbox))
  "Open the mail inbox buffer."
  (gascity-mail))

(provide 'gascity-mail)
;;; gascity-mail.el ends here
