;;; gascity-cities.el --- Every city on every host, one row each -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; `gascity-cities' (`j c', dashboard-v3 §7.11, §8.3 R8): a tabulated
;; list of the cities registered on this machine and on remote hosts.
;;
;; Hosts: the local one, every host in `gascity-remote-hosts', and every
;; remote host a gascity view has read from this session
;; (`gascity-store-hosts').  gc's own `~/.gc/contexts.toml' is not used:
;; it registers HTTPS cities for `gc --context', not ssh hosts.
;;
;; Reads, all through the store (async, deadline, per-host scheduler):
;; `gc cities' once per host, then per city its own `gc status' (Agents,
;; Health) and `gc mail count' (Mail).  Rows fill in as their reads
;; answer; one slow or dead host never holds up the others.  The Runs
;; column comes from the city's open cockpit (`gascity-pulse'), since no
;; single gc read gives it; it is blank for a city with no cockpit.
;;
;; `RET' opens the city's cockpit, with the directory host-qualified.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-context)
(require 'gascity-store)
(require 'gascity-tabulated)
(require 'gascity-dashboard)
(require 'gascity-pulse)

(defcustom gascity-remote-hosts nil
  "Remote hosts whose cities the Cities view lists (§8.3 R8).
Each element is a TRAMP prefix such as \"/ssh:build-box:\" or a bare
host name, meaning \"/ssh:HOST:\".  Hosts a gascity view has read from
this session are listed as well, without being named here."
  :type '(repeat string)
  :group 'gascity)

(defconst gascity-cities-buffer-name "*gascity-cities*"
  "Name of the Cities list buffer.")

(defvar-local gascity-cities--rows nil
  "Hash of the rows: key (HOST . PATH) → plist of what is known so far.
HOST is the TRAMP prefix (\"\" locally), PATH the host-local city path.")

(defvar-local gascity-cities--host-errors nil
  "Alist HOST → the error of its `gc cities' read.")

(defvar-local gascity-cities--hosts nil
  "The hosts this list read at its last refresh (see `gascity-cities-hosts').")

(defvar-local gascity-cities--subs nil
  "This list's store subscriptions (dropped on refresh and kill).")

(defvar-local gascity-cities--generation 0
  "Counter stamping each refresh; late answers of older ones are dropped.")

;;; Hosts

(defun gascity-cities--prefix (host)
  "Return the TRAMP prefix of configured HOST (a prefix or a bare name)."
  (substring-no-properties
   ;; Pure: a configured host is often host-only ("/ssh:h:"), which
   ;; `file-remote-p' would expand over TRAMP (`gascity-remote-prefix').
   (or (gascity-remote-prefix host)
       (format "/ssh:%s:" host))))

(defun gascity-cities-hosts ()
  "Return the hosts to list: \"\" (local), then the remote prefixes.
The configured `gascity-remote-hosts' and the hosts read from this
session, deduplicated, sorted.  Pure."
  (cons "" (sort (delete-dups
                  (append (mapcar #'gascity-cities--prefix gascity-remote-hosts)
                          (gascity-store-hosts)))
                 #'string<)))

(defun gascity-cities--host-dir (host)
  "Return the directory `gc cities' runs in on HOST.
Locally the home directory; remotely the host's root, a directory that
exists without asking the host where home is (§8.3 R2)."
  (if (string-empty-p host)
      (file-name-as-directory (expand-file-name "~"))
    (concat host "/")))

(defun gascity-cities--city-dir (host path)
  "Return the directory of the city at host-local PATH on HOST."
  (file-name-as-directory (concat host path)))

;;; Rows

(defun gascity-cities--where (host path)
  "Return the Where cell: PATH with `~/', prefixed by HOST's TRAMP name.
Pure: the remote home is the TRAMP user's `/home/USER/'."
  (let ((default-directory (if (string-empty-p host)
                               default-directory
                             (concat host "/"))))
    (concat host (gascity-dashboard--path path))))

(defun gascity-cities--health (status)
  "Return the Health cell of `gc status' payload STATUS."
  (let* ((health (alist-get 'health status))
         (store (alist-get 'store_health (alist-get 'summary status)))
         (partial (gascity-dashboard--partial-errors status)))
    (cond ((or (not (alist-get 'usable health))
               (not (alist-get 'running (alist-get 'controller status))))
           (propertize (gascity-ui-glyph 'fail) 'help-echo "unusable or controller down"))
          ((alist-get 'degraded health)
           (propertize (gascity-ui-glyph 'watch) 'help-echo "degraded"))
          (partial (gascity-ui-partial-mark (string-join partial "\n")))
          ((alist-get 'warning store)
           (propertize (gascity-ui-glyph 'watch) 'help-echo "store over its size threshold"))
          (t (gascity-ui-glyph 'ok)))))

(defun gascity-cities--entry (key row)
  "Return the tabulated entry of row KEY (HOST . PATH) with state ROW."
  (let* ((host (car key))
         (path (cdr key))
         (status (plist-get row :status))
         (serr (plist-get row :status-error))
         (summary (alist-get 'summary status))
         (mail (plist-get row :mail))
         (unread (alist-get 'unread mail))
         (pulse (gascity-pulse-city (gascity-cities--city-dir host path)))
         (runs (plist-get pulse :runs))
         (pending (propertize "…" 'face 'gascity-dim))
         (glyph (cond (status (if (alist-get 'running (alist-get 'controller status))
                                  (gascity-ui-glyph 'ok)
                                (gascity-ui-glyph 'fail)))
                      (serr (propertize (gascity-ui-glyph 'fail) 'help-echo serr))
                      (t pending))))
    (list (list (cons 'city (plist-get row :name))
                (cons 'dir (gascity-cities--city-dir host path)))
          (vector
           (concat glyph " " (propertize (or (plist-get row :name) "?")
                                         'face 'gascity-city))
           (gascity-cities--where host path)
           (cond (status (format "%s/%s" (or (alist-get 'running_agents summary) 0)
                                 (or (alist-get 'total_agents summary) 0)))
                 (serr (propertize (or (gascity-ui-first-line serr) "failed")
                                   'face 'gascity-dim 'help-echo serr))
                 (t pending))
           (cond ((not (numberp runs)) "")
                 ((> runs 0) (concat (number-to-string runs) " " (gascity-ui-glyph 'active)))
                 (t "0"))
           (cond ((numberp unread)
                  (if (> unread 0)
                      (concat (gascity-ui-glyph 'watch) (number-to-string unread))
                    "0"))
                 ((plist-get row :mail-error)
                  (propertize "?" 'help-echo (plist-get row :mail-error)))
                 (t pending))
           (cond (status (gascity-cities--health status))
                 (serr "")
                 (t pending))))))

(defun gascity-cities--host-entry (host err &optional offline)
  "Return the entry reporting HOST's `gc cities' read failing with ERR.
With OFFLINE the host is unreachable (the store retries it): `○'."
  (list (list (cons 'host host))
        (vector (concat (gascity-ui-glyph (if offline 'idle 'fail)) " "
                        (propertize (or (and (gascity-remote-prefix host)
                                             (tramp-file-name-host
                                              (tramp-dissect-file-name host)))
                                        "local")
                                    'face 'gascity-city))
                host "" "" ""
                (propertize (if offline "offline"
                              (or (gascity-ui-first-line err) "failed"))
                            'face 'gascity-dim 'help-echo err))))

(defun gascity-cities--offline-hosts ()
  "Return (HOST . REASON) for listed remote hosts the store has offline."
  (delq nil
        (mapcar (lambda (host)
                  (and (not (string-empty-p host))
                       (not (assoc host gascity-cities--host-errors))
                       (gascity-store-offline-p (gascity-cities--host-dir host))
                       (cons host (plist-get (gascity-store-host-status
                                              (gascity-cities--host-dir host))
                                             :reason))))
                gascity-cities--hosts)))

(defun gascity-cities--keys ()
  "Return the row keys in display order: local first, then by host, name."
  (let (keys)
    (maphash (lambda (k _) (push k keys)) gascity-cities--rows)
    (sort keys (lambda (a b)
                 (let ((na (plist-get (gethash a gascity-cities--rows) :name))
                       (nb (plist-get (gethash b gascity-cities--rows) :name)))
                   (if (equal (car a) (car b))
                       (string< (or na "") (or nb ""))
                     (string< (car a) (car b))))))))

(defun gascity-cities--redisplay ()
  "Rebuild the list from the rows in hand, keeping the page and point."
  (let* ((keys (gascity-cities--keys))
         (remote (seq-count (lambda (k) (not (string-empty-p (car k)))) keys)))
    (setq gascity-tabulated--base-name
          (format "Cities %d%s" (length keys)
                  (if (> remote 0) (format " · %d remote" remote) "")))
    (setq gascity-tabulated--all-entries
          (append (mapcar (lambda (k) (gascity-cities--entry
                                       k (gethash k gascity-cities--rows)))
                          keys)
                  (mapcar (lambda (e) (gascity-cities--host-entry (car e) (cdr e)))
                          gascity-cities--host-errors)
                  (mapcar (lambda (e) (gascity-cities--host-entry (car e) (cdr e) t))
                          (gascity-cities--offline-hosts))))
    (unless gascity-tabulated--page-size
      (setq gascity-tabulated--page-size
            (if (get-buffer-window (current-buffer))
                (with-selected-window (get-buffer-window (current-buffer))
                  (beads-pager-window-page-size))
              50)))
    (gascity-tabulated--refresh-display)))

;;; Reads

(defun gascity-cities--updater (buffer generation fn)
  "Return a callback applying FN in BUFFER while GENERATION is current."
  (lambda (value)
    (when (and (buffer-live-p buffer)
               (= generation (buffer-local-value 'gascity-cities--generation buffer)))
      (with-current-buffer buffer
        (funcall fn value)
        (gascity-cities--redisplay)))))

(defun gascity-cities--set (key &rest props)
  "Merge PROPS into row KEY."
  (let ((row (gethash key gascity-cities--rows)))
    (while props
      (setq row (plist-put row (pop props) (pop props))))
    (puthash key row gascity-cities--rows)))

(defun gascity-cities--subscribe (key args apply)
  "Keep row KEY following the store entry of ARGS in the row's city.
APPLY is called in this buffer with each ready snapshot's payload, or
with (:error MESSAGE) for a failure with no payload; the row is then
redrawn.  So a refetch by any view of that city (its cockpit's `g',
the event router) updates the row without a read of our own."
  (let* ((buffer (current-buffer))
         (dir (gascity-cities--city-dir (car key) (cdr key))))
    (push (gascity-store-subscribe
           args
           (lambda (snap)
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (cond ((eq (plist-get snap :status) 'ready)
                        (funcall apply (plist-get snap :data)))
                       ((plist-get snap :error)
                        (funcall apply (list :error (plist-get snap :error)))))
                 (gascity-cities--redisplay))))
           :dir dir :buffer buffer)
          gascity-cities--subs)))

(defun gascity-cities--read-city (key force)
  "Subscribe row KEY to its city's `gc status' and `gc mail count' entries
and request them.  FORCE re-reads even a fresh store entry."
  (let ((dir (gascity-cities--city-dir (car key) (cdr key))))
    (gascity-cities--subscribe
     key '("status")
     (lambda (s)
       (if (eq (car-safe s) :error)
           (gascity-cities--set key :status-error (cadr s))
         (gascity-pulse-record-store-size dir s)
         (gascity-cities--set key :status s :status-error nil))))
    (gascity-cities--subscribe
     key '("mail" "count")
     (lambda (m)
       (if (eq (car-safe m) :error)
           (gascity-cities--set key :mail-error (cadr m))
         (gascity-cities--set key :mail m :mail-error nil))))
    (dolist (args '(("status") ("mail" "count")))
      (gascity-store-request args :dir dir :force force))
    ;; Paint what the store already holds (no I/O).
    (let ((status (gascity-store-get '("status") dir))
          (mail (gascity-store-get '("mail" "count") dir)))
      (when (eq (plist-get status :status) 'ready)
        (gascity-cities--set key :status (plist-get status :data)))
      (when (eq (plist-get mail :status) 'ready)
        (gascity-cities--set key :mail (plist-get mail :data))))))

(defun gascity-cities--read-host (host force)
  "Start the `gc cities' read of HOST, then each city's own reads.
FORCE re-reads even fresh store entries."
  (let ((buffer (current-buffer))
        (gen gascity-cities--generation))
    (gascity-store-fetch
     '("cities")
     (gascity-cities--updater
      buffer gen
      (lambda (payload)
        (setq gascity-cities--host-errors
              (assoc-delete-all host gascity-cities--host-errors))
        (dolist (city (append (alist-get 'cities payload) nil))
          (let ((key (cons host (file-name-as-directory (alist-get 'path city)))))
            (gascity-cities--set key :name (alist-get 'name city))
            (gascity-cities--read-city key force)))))
     (gascity-cities--updater
      buffer gen
      (lambda (err)
        (setf (alist-get host gascity-cities--host-errors nil nil #'equal) err)))
     :dir (gascity-cities--host-dir host) :force force)))

(defun gascity-cities-refresh (&optional cached)
  "Re-read every host's cities and every city's status (`g').
With CACHED (non-interactive first open), fresh store entries answer
without a new read."
  (interactive)
  (cl-incf gascity-cities--generation)
  (mapc #'gascity-store-unsubscribe gascity-cities--subs)
  (setq gascity-cities--subs nil)
  (let ((force (not cached)))
    (unless gascity-cities--rows
      (setq gascity-cities--rows (make-hash-table :test 'equal)))
    (setq gascity-cities--hosts (gascity-cities-hosts))
    (gascity-cities--redisplay)
    (dolist (host gascity-cities--hosts)
      (gascity-cities--read-host host force))))

(defun gascity-cities--host-state-changed (host _state _reason)
  "Redisplay the Cities list when listed HOST goes offline or comes back."
  (when-let* ((buf (get-buffer gascity-cities-buffer-name)))
    (with-current-buffer buf
      (when (and (derived-mode-p 'gascity-cities-mode)
                 (member host gascity-cities--hosts))
        (gascity-cities--redisplay)))))

(add-hook 'gascity-store-host-state-functions #'gascity-cities--host-state-changed)

;;; Commands

(defun gascity-cities-visit ()
  "Open the cockpit of the city at point (RET)."
  (interactive)
  (let* ((id (tabulated-list-get-id))
         (dir (alist-get 'dir id)))
    (unless dir (user-error "No city at point"))
    (let ((default-directory dir))
      (gascity-dashboard))))

(defvar-keymap gascity-cities-mode-map
  :doc "Keymap for `gascity-cities-mode'."
  :parent gascity-tabulated-base-map
  "g"   #'gascity-cities-refresh
  "RET" #'gascity-cities-visit)

(define-derived-mode gascity-cities-mode tabulated-list-mode "GC-Cities"
  "Major mode listing every city on this machine and the remote hosts.
`RET' opens a city's cockpit; `g' re-reads every host.
\\{gascity-cities-mode-map}"
  :group 'gascity
  (setq tabulated-list-format
        [("City" 18 t) ("Where" 36 t) ("Agents" 7 t) ("Runs" 5 t)
         ("Mail" 5 t) ("Health" 6 nil)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key nil)
  (setq gascity-tabulated--base-name "Cities")
  (tabulated-list-init-header))

;;;###autoload
(defun gascity-cities ()
  "List every city on this machine and on the remote hosts (`j c').
Hosts: the local one, `gascity-remote-hosts', and every remote host a
gascity view has read from this session.  Rows fill in as each host
and city answers."
  (interactive)
  (let ((buf (gascity-view-get-buffer-create
              gascity-cities-buffer-name
              (file-name-as-directory (expand-file-name "~")))))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-cities-mode)
        (gascity-cities-mode))
      (gascity-cities-refresh 'cached))
    (pop-to-buffer buf)))

(provide 'gascity-cities)
;;; gascity-cities.el ends here
