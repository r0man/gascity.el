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
;; scroll natively; explicit pagination is a future refinement.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'tabulated-list)
(require 'view)
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-section)
(require 'gascity-command)
(require 'gascity-types)

(declare-function beads-show "beads")

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

(defun gascity-tabulated--field (item keys)
  "Return the first non-empty value among KEYS in alist ITEM, or \"\".
KEYS is a list of symbols tried in order; used where a `gc' field name
may vary (e.g. mail, whose live shape could not be captured)."
  (catch 'hit
    (dolist (k keys)
      (let ((v (alist-get k item)))
        (when (and v (or (not (stringp v)) (not (string-empty-p v))))
          (throw 'hit v))))
    ""))

(defun gascity-tabulated--str (value)
  "Coerce VALUE to a display string."
  (cond ((null value) "")
        ((stringp value) value)
        ((numberp value) (number-to-string value))
        ((eq value t) "yes")
        (t (format "%s" value))))

(defun gascity-tabulated--refresh (base-name fetch-fn)
  "Fetch rows via FETCH-FN and repaint the current tabulated buffer.
FETCH-FN returns a list of `(ID . [COLUMNS])' entries.  `gc' errors are
caught and reported, leaving the list empty.  BASE-NAME labels the mode
line with the row count."
  (let ((entries (condition-case err
                     (funcall fetch-fn)
                   (gascity-error
                    (message "gascity: %s" (error-message-string err))
                    nil))))
    (setq tabulated-list-entries entries)
    (tabulated-list-print t)
    (setq mode-name (format "%s [%d]" base-name (length entries)))
    (force-mode-line-update)))

(defun gascity-tabulated--show (buffer-name mode-sym refresh-fn)
  "Pop to BUFFER-NAME in major mode MODE-SYM and run REFRESH-FN."
  (let ((buf (get-buffer-create buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p mode-sym) (funcall mode-sym))
      (funcall refresh-fn))
    (pop-to-buffer buf)))

;;; ============================================================
;;; Rigs
;;; ============================================================

(defconst gascity-rig-list-buffer-name "*gascity-rigs*")

(defun gascity-rig-list--status (rig)
  "Return a propertized status cell for RIG (an alist)."
  (let* ((running (alist-get 'running rig))
         (suspended (alist-get 'suspended rig))
         (label (cond (suspended "suspended")
                      (running "running")
                      (t "stopped"))))
    (propertize label 'face (gascity-section-state-face running suspended))))

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
  "Refresh the rig list."
  (interactive)
  (gascity-tabulated--refresh
   "Rigs"
   (lambda ()
     (mapcar #'gascity-rig-list--entry
             (gascity-tabulated--vector->list
              (alist-get 'rigs (gascity-command-rig-list!)))))))

(defvar-keymap gascity-rig-list-mode-map
  :doc "Keymap for `gascity-rig-list-mode'."
  :parent tabulated-list-mode-map
  "g"   #'gascity-rig-list-refresh
  "RET" #'gascity-rig-list-dired)

(define-derived-mode gascity-rig-list-mode tabulated-list-mode "GC-Rigs"
  "Major mode listing the rigs registered in the city.
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

(defun gascity-session-list-refresh ()
  "Refresh the session list."
  (interactive)
  (gascity-tabulated--refresh
   "Sessions"
   (lambda ()
     ;; Resolve the tmux socket once per refresh — it is constant across
     ;; rows, and `gc session list' does not carry the city name.
     (let ((socket (gascity-resolve-tmux-socket)))
       (mapcar (lambda (s) (gascity-session-list--entry s socket))
               (gascity-tabulated--vector->list
                (alist-get 'sessions (gascity-command-session-list!))))))))

(defvar-keymap gascity-session-list-mode-map
  :doc "Keymap for `gascity-session-list-mode'."
  :parent tabulated-list-mode-map
  "g"   #'gascity-session-list-refresh
  "d"   #'gascity-dired-at-point
  "t"   #'gascity-tmux-at-point
  "RET" #'gascity-dired-at-point)

(define-derived-mode gascity-session-list-mode tabulated-list-mode "GC-Sessions"
  "Major mode listing the city's agent sessions.
`d' opens a session's worktree in Dired; `t' attaches to its tmux
session.
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
  "Open the convoy bead at point in beads.el."
  (interactive)
  (let ((id (tabulated-list-get-id)))
    (cond ((not id) (user-error "No convoy at point"))
          ((fboundp 'beads-show) (beads-show id))
          (t (user-error "beads.el is not available to show %s" id)))))

(defun gascity-convoy-list-refresh ()
  "Refresh the convoy list."
  (interactive)
  (gascity-tabulated--refresh
   "Convoys"
   (lambda ()
     (mapcar #'gascity-convoy-list--entry
             (gascity-tabulated--vector->list
              (alist-get 'convoys (gascity-command-convoy-list!)))))))

(defvar-keymap gascity-convoy-list-mode-map
  :doc "Keymap for `gascity-convoy-list-mode'."
  :parent tabulated-list-mode-map
  "g"   #'gascity-convoy-list-refresh
  "RET" #'gascity-convoy-list-visit)

(define-derived-mode gascity-convoy-list-mode tabulated-list-mode "GC-Convoys"
  "Major mode listing the city's convoys.
`RET' opens the convoy bead in beads.el.
\\{gascity-convoy-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("ID" 12 t) ("Title" 46 t) ("Status" 10 t) ("Progress" 10 t)])
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

(defun gascity-mail-inbox--unread-p (message)
  "Return non-nil when MESSAGE (an alist) is unread."
  (or (alist-get 'unread message)
      (and (assq 'read message) (not (alist-get 'read message)))))

(defun gascity-mail-inbox--entry (message)
  "Map MESSAGE (an alist) to a tabulated-list entry.
Mail field names could not be captured live, so several candidate keys
are tried; the entry id is the whole message alist."
  (list message
        (vector (gascity-tabulated--str
                 (gascity-tabulated--field message '(from sender from_addr)))
                (gascity-tabulated--str
                 (gascity-tabulated--field message '(subject subj title)))
                (gascity-tabulated--format-timestamp
                 (gascity-tabulated--field
                  message '(date created_at sent_at timestamp)))
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
  "Refresh the mail inbox."
  (interactive)
  (gascity-tabulated--refresh
   "Mail"
   (lambda ()
     (mapcar #'gascity-mail-inbox--entry
             (gascity-tabulated--vector->list
              (alist-get 'messages (gascity-command-mail-inbox!)))))))

(defvar-keymap gascity-mail-inbox-mode-map
  :doc "Keymap for `gascity-mail-inbox-mode'."
  :parent tabulated-list-mode-map
  "g"   #'gascity-mail-inbox-refresh
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
  "Refresh the order list."
  (interactive)
  (gascity-tabulated--refresh
   "Orders"
   (lambda ()
     (mapcar #'gascity-order-list--entry
             (gascity-tabulated--vector->list
              (alist-get 'orders (gascity-command-order-list!)))))))

(defvar-keymap gascity-order-list-mode-map
  :doc "Keymap for `gascity-order-list-mode'."
  :parent tabulated-list-mode-map
  "g"   #'gascity-order-list-refresh
  "RET" #'gascity-order-list-visit)

(define-derived-mode gascity-order-list-mode tabulated-list-mode "GC-Orders"
  "Major mode listing the city's orders.
`RET' opens the order's source file.
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
  "Map DB (an alist from dolt health) to a tabulated-list entry."
  (list db
        (vector (gascity-tabulated--str (alist-get 'name db))
                (gascity-tabulated--str (alist-get 'commits db))
                (gascity-tabulated--str (alist-get 'open_beads db)))))

(defun gascity-dolt-list-show ()
  "Echo the details of the Dolt database at point."
  (interactive)
  (let ((db (tabulated-list-get-id)))
    (unless db (user-error "No database at point"))
    (message "%s: %s commits, %s open beads"
             (gascity-tabulated--str (alist-get 'name db))
             (gascity-tabulated--str (alist-get 'commits db))
             (gascity-tabulated--str (alist-get 'open_beads db)))))

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
  :doc "Keymap for `gascity-dolt-list-mode'."
  :parent tabulated-list-mode-map
  "g"   #'gascity-dolt-list-refresh
  "RET" #'gascity-dolt-list-show)

(define-derived-mode gascity-dolt-list-mode tabulated-list-mode "GC-Dolt"
  "Major mode listing the Dolt databases and their stats.
\\{gascity-dolt-list-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("Database" 20 t) ("Commits" 10 t) ("Open beads" 12 t)])
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
