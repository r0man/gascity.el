;;; gascity-bookmark.el --- Emacs bookmarks for every gascity view -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; `C-x r m' in any gascity view bookmarks it; `C-x r b' (and
;; `bookmark-bmenu-list', consult-bookmark, …) opens it again.  Modelled
;; on beads.el's `beads-show' bookmarks.
;;
;; A record names the view kind, the city directory the view is pinned
;; to (`default-directory', local or a TRAMP name, kept as a string),
;; the view's arguments (rig, run, agent, thread) and its filters.
;; Making one reads buffer state only: no I/O, no gc, no TRAMP (a remote
;; view is bookmarked with the host unreachable).
;;
;; Jumping binds `default-directory' to the recorded city and calls the
;; view's usual entry command, so the view opens the usual way: at once,
;; `…' while its reads run, the offline state when the host is down.  A
;; recorded city root is memoized first (`gascity-context-remember-
;; city-root'), so even the first jump to a remote city walks nothing
;; over TRAMP.  The filters are then made to match the record.
;;
;; Every view kind is one entry of `gascity-bookmark-kinds'; the mode
;; hooks installed at the end give each view mode its buffer-local
;; `bookmark-make-record-function'.

;;; Code:

(require 'bookmark)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'gascity-context)
(require 'gascity-domain)
(require 'gascity-ui)

(defvar gascity-section--agent)
(defvar gascity-rig-dashboard--rig-name)
(defvar gascity-run--current-run)
(defvar gascity-run--current-rig)
(defvar gascity-events--filter)
(defvar gascity-agents--filter)
(defvar gascity-mail-inbox--filter)
(defvar gascity-mail-thread--id)
(defvar gascity-mail-thread--messages)
(defvar gascity-rig-list--filter)
(defvar gascity-session-list--filter)
(defvar gascity-convoy-list--filter)
(defvar gascity-order-list--filter)
(declare-function gascity-dashboard--state "gascity-dashboard")
(declare-function gascity-dashboard "gascity-dashboard")
(declare-function gascity-rig-dashboard "gascity-rig")
(declare-function gascity-agents "gascity-agents")
(declare-function gascity-agents-tree "gascity-agents")
(declare-function gascity-polecat-detail "gascity-session")
(declare-function gascity-runs "gascity-runs")
(declare-function gascity-run-show "gascity-run")
(declare-function gascity-events "gascity-events")
(declare-function gascity-mail "gascity-mail")
(declare-function gascity-mail-thread-show "gascity-mail")
(declare-function gascity-health "gascity-health")
(declare-function gascity-costs "gascity-health")
(declare-function gascity-cities "gascity-cities")
(declare-function gascity-rig-list "gascity-tabulated")
(declare-function gascity-session-list "gascity-tabulated")
(declare-function gascity-convoy-list "gascity-tabulated")
(declare-function gascity-order-list "gascity-tabulated")
(declare-function gascity-dolt-list "gascity-tabulated")

;;; View state readers (pure)

(defun gascity-bookmark--root-filters ()
  "Return a vui view's filter plist from its root state (cockpit, Runs)."
  (gascity-dashboard--state :filters))

(defun gascity-bookmark--agent-args ()
  "Return the agent detail's subject as a plist of its slots."
  (let ((agent gascity-section--agent))
    (and (gascity-agent-p agent)
         (list :name (gascity-agent-name agent)
               :rig (gascity-agent-rig agent)
               :session-name (gascity-agent-session-name agent)
               :socket (gascity-agent-socket agent)
               :work-dir (gascity-agent-work-dir agent)))))

(defun gascity-bookmark--open-agent (args)
  "Open the agent detail of the agent in ARGS."
  (gascity-polecat-detail
   (make-instance 'gascity-agent
                  :name (plist-get args :name) :rig (plist-get args :rig)
                  :session-name (plist-get args :session-name)
                  :socket (plist-get args :socket)
                  :work-dir (plist-get args :work-dir))))

(defun gascity-bookmark--thread-args ()
  "Return the mail thread's id and its first message's headers.
The headers (never the body) let a jump show the thread's subject and
first sender at once, before `gc mail thread' answers."
  (let ((m (car gascity-mail-thread--messages)))
    (list :thread gascity-mail-thread--id
          :message (and m (list :id (gascity-mail-id m)
                                :from (gascity-mail-from m)
                                :to (gascity-mail-to m)
                                :subject (gascity-mail-subject m)
                                :created-at (gascity-mail-created-at m))))))

(defun gascity-bookmark--open-thread (args)
  "Open the mail thread in ARGS: its headers now, the thread when read."
  (let ((m (plist-get args :message)))
    (gascity-mail-thread-show
     (make-instance 'gascity-mail-message
                    :id (or (plist-get m :id) (plist-get args :thread))
                    :thread-id (plist-get args :thread)
                    :from (plist-get m :from) :to (plist-get m :to)
                    :subject (plist-get m :subject)
                    :created-at (plist-get m :created-at)))))

;;; The kinds

(defconst gascity-bookmark-kinds
  `((dashboard :mode gascity-dashboard-mode :prefix "gascity"
               :open ,(lambda (_) (gascity-dashboard))
               :filters gascity-bookmark--root-filters)
    (rig :mode gascity-rig-dashboard-mode :prefix "gascity-rig"
         :args ,(lambda () (list :rig gascity-rig-dashboard--rig-name))
         :subject ,(lambda (args) (plist-get args :rig))
         :open ,(lambda (args) (gascity-rig-dashboard (plist-get args :rig))))
    (agents :mode gascity-agents-mode :prefix "gascity-agents"
            :open ,(lambda (_) (gascity-agents))
            :filters ,(lambda () gascity-agents--filter))
    (agents-tree :mode gascity-agents-tree-mode :prefix "gascity-agents-tree"
                 :open ,(lambda (_) (gascity-agents-tree)))
    (agent :mode gascity-session-detail-mode :prefix "gascity-agent"
           :args gascity-bookmark--agent-args
           :subject ,(lambda (args) (plist-get args :name))
           :open gascity-bookmark--open-agent)
    (runs :mode gascity-runs-mode :prefix "gascity-runs"
          :open ,(lambda (_) (gascity-runs))
          :filters gascity-bookmark--root-filters)
    (run :mode gascity-run-mode :prefix "gascity-run"
         :args ,(lambda () (list :run gascity-run--current-run
                                 :rig gascity-run--current-rig))
         :subject ,(lambda (args) (plist-get args :run))
         :open ,(lambda (args) (gascity-run-show (plist-get args :run) nil
                                                 (plist-get args :rig))))
    (events :mode gascity-events-mode :prefix "gascity-events"
            :open ,(lambda (_) (gascity-events))
            :filters ,(lambda () gascity-events--filter))
    (mail :mode gascity-mail-inbox-mode :prefix "gascity-mail"
          :open ,(lambda (_) (gascity-mail))
          :filters ,(lambda () gascity-mail-inbox--filter))
    (mail-thread :mode gascity-mail-thread-mode :prefix "gascity-mail-thread"
                 :args gascity-bookmark--thread-args
                 :subject ,(lambda (args) (plist-get args :thread))
                 :open gascity-bookmark--open-thread)
    (health :mode gascity-health-mode :prefix "gascity-health"
            :open ,(lambda (_) (gascity-health)))
    (costs :mode gascity-costs-mode :prefix "gascity-costs"
           :open ,(lambda (_) (gascity-costs)))
    (cities :mode gascity-cities-mode :prefix "gascity-cities" :no-city t
            :open ,(lambda (_) (gascity-cities)))
    (rigs :mode gascity-rig-list-mode :prefix "gascity-rigs"
          :open ,(lambda (_) (gascity-rig-list))
          :filters ,(lambda () gascity-rig-list--filter))
    (sessions :mode gascity-session-list-mode :prefix "gascity-sessions"
              :open ,(lambda (_) (gascity-session-list))
              :filters ,(lambda () gascity-session-list--filter))
    (convoys :mode gascity-convoy-list-mode :prefix "gascity-convoys"
             :open ,(lambda (_) (gascity-convoy-list))
             :filters ,(lambda () gascity-convoy-list--filter))
    (orders :mode gascity-order-list-mode :prefix "gascity-orders"
            :open ,(lambda (_) (gascity-order-list))
            :filters ,(lambda () gascity-order-list--filter))
    (dolt :mode gascity-dolt-list-mode :prefix "gascity-dolt"
          :open ,(lambda (_) (gascity-dolt-list))))
  "Every bookmarkable gascity view: KIND and its plist.
:mode is the view's major mode; :prefix heads the default bookmark
name; :args (optional) returns the view's arguments as a plist from
buffer state and :subject (optional) names them in the default name,
else the city does; :open opens the view from those arguments with
`default-directory' bound to the city; :filters (optional) returns the
view's filter plist; :no-city marks a view not pinned to one city.")

(defun gascity-bookmark--kind ()
  "Return (KIND . SPEC) of the current buffer's view, or nil."
  (seq-find (lambda (k) (eq major-mode (plist-get (cdr k) :mode)))
            gascity-bookmark-kinds))

;;; Records

(defun gascity-bookmark--city-label (dir)
  "Return the city of view directory DIR as NAME[@HOST], with no I/O."
  (let ((host (file-remote-p dir 'host))
        (name (file-name-nondirectory
               (directory-file-name
                (file-local-name (or (gascity-context-city-root-cached dir) dir))))))
    (concat name (if host (concat "@" host) ""))))

(defun gascity-bookmark--default-name (spec args dir)
  "Return the default bookmark name of a SPEC view with ARGS in DIR.
\"gascity: bright-lights\", \"gascity-runs: burningswell@host\",
\"gascity-run: bs-8jif@host\": the view's prefix, then its subject (the
object it shows, else the city), `@host' for a remote city."
  (let ((subject-fn (plist-get spec :subject))
        (host (file-remote-p dir 'host)))
    (cond (subject-fn
           (format "%s: %s%s" (plist-get spec :prefix) (funcall subject-fn args)
                   (if host (concat "@" host) "")))
          ((plist-get spec :no-city)
           (concat (plist-get spec :prefix) (if host (concat "@" host) "")))
          (t (format "%s: %s" (plist-get spec :prefix)
                     (gascity-bookmark--city-label dir))))))

(defun gascity-bookmark-make-record ()
  "Return the bookmark record of this gascity view.
Pure: reads the view's kind, pinned `default-directory', arguments and
filters from buffer state — no gc, no TRAMP.  The record carries
`filename' and `location' (the city directory, for listings) and the
`handler' `gascity-bookmark-jump'."
  (let* ((kind (or (gascity-bookmark--kind)
                   (user-error "This gascity buffer cannot be bookmarked")))
         (spec (cdr kind))
         (dir default-directory)
         (args (and (plist-get spec :args) (funcall (plist-get spec :args))))
         (filters (and (plist-get spec :filters) (funcall (plist-get spec :filters)))))
    `(,(gascity-bookmark--default-name spec args dir)
      (filename . ,dir)
      (location . ,dir)
      (gascity-view . ,(car kind))
      (gascity-city-root . ,(and (not (plist-get spec :no-city))
                                 (equal (gascity-context-city-root-cached dir) dir)))
      (gascity-args . ,args)
      (gascity-filters . ,filters)
      (handler . gascity-bookmark-jump))))

;;; Jumping

(defun gascity-bookmark--restore-filters (filters current)
  "Make this view's filters equal FILTERS; CURRENT returns its plist now.
Each differing key goes through the view's own `/' setter
\(`gascity-filter-set'), so it is stored and remembered as if set by
hand; keys the view has and the record lacks are cleared."
  (when gascity-filter-set-function
    (let ((keys (delete-dups
                 (cl-loop for (k _v) on (append filters (funcall current)) by #'cddr
                          collect k))))
      (dolist (key keys)
        (let ((want (plist-get filters key)))
          (unless (equal want (gascity-filter-value key))
            (gascity-filter-set key want)))))))

;;;###autoload
(defun gascity-bookmark-jump (bookmark)
  "Open the gascity view BOOKMARK records and make its buffer current.
`default-directory' is bound to the recorded city (a recorded city
root is memoized first, so no walk runs over TRAMP) and the view's
entry command opens it the usual way — `…' while its reads run, the
offline state when the host is unreachable.  The recorded filters are
then applied.  bookmark.el displays the buffer."
  (let* ((kind (bookmark-prop-get bookmark 'gascity-view))
         (spec (or (alist-get kind gascity-bookmark-kinds)
                   (user-error "Unknown gascity bookmark view: %s" kind)))
         (dir (file-name-as-directory (bookmark-prop-get bookmark 'filename)))
         (filters (bookmark-prop-get bookmark 'gascity-filters))
         (buf nil))
    (when (bookmark-prop-get bookmark 'gascity-city-root)
      (gascity-context-remember-city-root dir))
    (let ((default-directory dir))
      ;; The entry commands display their buffer; bookmark.el displays
      ;; it itself (`bookmark-jump', `-other-window', `bmenu'), so only
      ;; the buffer is kept.
      (save-window-excursion
        (funcall (plist-get spec :open) (bookmark-prop-get bookmark 'gascity-args))
        (setq buf (current-buffer))))
    (set-buffer buf)
    (when (plist-get spec :filters)
      (gascity-bookmark--restore-filters filters (plist-get spec :filters)))
    buf))

(put 'gascity-bookmark-jump 'bookmark-handler-type "Gascity")

;;; Installation

(defun gascity-bookmark-setup ()
  "Make this gascity view bookmarkable (its mode hook)."
  (setq-local bookmark-make-record-function #'gascity-bookmark-make-record))

(dolist (kind gascity-bookmark-kinds)
  (add-hook (intern (format "%s-hook" (plist-get (cdr kind) :mode)))
            #'gascity-bookmark-setup))

(provide 'gascity-bookmark)
;;; gascity-bookmark.el ends here
