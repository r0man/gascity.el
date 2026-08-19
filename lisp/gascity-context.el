;;; gascity-context.el --- Resolve the current city and rig -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Determine which Gas City and rig the user is "in", based on
;; `default-directory', with explicit overrides.
;;
;; - The city is found by walking up for the `city.toml' marker
;;   (`gascity-context-city-root'); its name is the root directory's
;;   basename (`gascity-context-city-name').
;; - Rigs live outside the city tree and are tracked in gc's registry,
;;   so there is no reliable local marker; `gascity-context-rig-name'
;;   asks gc to resolve the rig from `default-directory', caching the
;;   answer per directory.
;;
;; Override `gascity-context-city' / `gascity-context-rig' to pin the
;; context (e.g. for a switch-rig command, arriving in later phases).
;;
;; `gascity-view-get-buffer-create' composes this resolution with the
;; remote buffer-naming scheme of `gascity-remote' into the single
;; view-buffer factory: every buffer a gascity view opens gets a
;; host-qualified name and a `default-directory' pinned to its city.

;;; Code:

(require 'cl-lib)
(require 'gascity-reader)
(require 'gascity-remote)

(defvar gascity-context-city nil
  "When non-nil, an absolute path that overrides city auto-detection.")

(defvar gascity-context-rig nil
  "When non-nil, a rig name that overrides rig auto-detection.")

(defconst gascity-context-city-file "city.toml"
  "Marker file identifying a Gas City root directory.")

(defvar gascity-context--rig-cache (make-hash-table :test 'equal)
  "Cache mapping an absolute directory to its resolved rig name.")

(defvar gascity-context--city-cache (make-hash-table :test 'equal)
  "Cache mapping an absolute directory to its gc-resolved city name.")

(defun gascity-context-clear-cache ()
  "Forget cached rig, city, and remote-executable resolutions.
The one cache entry point: also clears the per-connection gc/tmux
resolutions of `gascity-remote-find-executable'.  Call after the
city's rig set changes, after a program moved on a remote host, or to
force re-resolution."
  (interactive)
  (clrhash gascity-context--rig-cache)
  (clrhash gascity-context--city-cache)
  (gascity-remote-forget-executables))

(defun gascity-context-city-root (&optional dir)
  "Return the Gas City root governing DIR (default `default-directory').
Honours `gascity-context-city'.  Otherwise walks up from DIR looking
for `gascity-context-city-file'.  Returns an absolute directory name
\(with trailing slash), or nil when DIR is not inside a city."
  (if gascity-context-city
      (file-name-as-directory (expand-file-name gascity-context-city))
    (when-let* ((start (expand-file-name (or dir default-directory)))
                (found (locate-dominating-file start gascity-context-city-file)))
      (file-name-as-directory (expand-file-name found)))))

(defun gascity-context-pin-directory (&optional dir)
  "Return the directory a gascity view opened from DIR should pin.
The city root governing DIR when DIR sits inside a city tree, else DIR
itself (default `default-directory').  A view buffer sets the result as
its `default-directory' at open time, so its refresh timers and at-point
actions keep resolving gc — and, for a remote city, the ssh/tmux host —
against the city the view was opened for, no matter where a later
refresh is invoked from.  The city root is preferred over DIR itself
because it outlives DIR (a polecat worktree the view was opened from may
be reclaimed while the view is still refreshing)."
  (let ((dir (expand-file-name (or dir default-directory))))
    (or (gascity-context-city-root dir)
        (file-name-as-directory dir))))

(defun gascity-view-get-buffer-create (base &optional dir)
  "Return the view buffer named BASE, keyed and pinned to DIR's city.
The one factory behind every buffer a gascity view opens — dashboards,
lists, detail views, mail message/body views, peek and dry-run output,
compose drafts.  BASE is the buffer's base name (\"*gascity-status*\");
DIR defaults to `default-directory' (the view or action context).  The
buffer's name is host-qualified for a remote city
\(`gascity-remote-buffer-name', so a local and a remote view of the same
kind coexist instead of one stealing the other's buffer) and its
`default-directory' is pinned to the city root governing DIR
\(`gascity-context-pin-directory') — re-pinned on every call, healing a
buffer that survived from another context.  So refresh timers, at-point
actions, and gc invocations keep resolving the city the view was opened
for, and `dired'/`find-file'/`shell' from any such buffer default to
that city's host.  Creating view buffers with a bare
`get-buffer-create' instead is what let a remote city's mail view open
with a local `default-directory' — new views must come through here."
  (let* ((dir (gascity-context-pin-directory dir))
         (buf (get-buffer-create (gascity-remote-buffer-name base dir))))
    (with-current-buffer buf
      (setq default-directory dir))
    buf))

(defun gascity-context-city-name (&optional dir)
  "Return the city name governing DIR, or nil.
Derived from the basename of `gascity-context-city-root', so it only
succeeds when DIR is inside the city tree.  For a gc-backed resolution
that stays robust outside the tree, see `gascity-context-gc-city-name'."
  (when-let ((root (gascity-context-city-root dir)))
    (file-name-nondirectory (directory-file-name root))))

(defun gascity-context-gc-city-name (&optional dir)
  "Return the city name gc resolves for DIR, or nil.
Unlike `gascity-context-city-name', which needs DIR inside the city
tree (it walks up for `gascity-context-city-file'), this asks `gc
status' — whose payload carries `city_name' regardless of
`default-directory' — so it stays robust when called from elsewhere.
This mirrors how the status and rig dashboards keep tmux-socket
resolution correct by reading `city_name' from a gc payload rather than
from directory context.  Answers are cached per directory; clear with
`gascity-context-clear-cache'."
  (let* ((key (expand-file-name (or dir default-directory)))
         (cached (gethash key gascity-context--city-cache 'miss)))
    (if (not (eq cached 'miss))
        cached
      (puthash key
               (condition-case nil
                   (let ((default-directory key))
                     (alist-get 'city_name (gascity-reader-read "status")))
                 (gascity-error nil))
               gascity-context--city-cache))))

(defun gascity-context-rig-name (&optional dir)
  "Return the current rig name for DIR (default `default-directory'), or nil.
Honours `gascity-context-rig'.  Otherwise asks gc to resolve the rig
from DIR via `gc rig status', returning nil when DIR is not inside a
rig.  Answers are cached per directory; clear with
`gascity-context-clear-cache'."
  (or gascity-context-rig
      (let* ((key (expand-file-name (or dir default-directory)))
             (cached (gethash key gascity-context--rig-cache 'miss)))
        (if (not (eq cached 'miss))
            cached
          (puthash key
                   (condition-case nil
                       (let* ((default-directory key)
                              (rig (alist-get
                                    'rig (gascity-reader-read "rig" "status"))))
                         (alist-get 'name rig))
                     (gascity-error nil))
                   gascity-context--rig-cache)))))

(provide 'gascity-context)
;;; gascity-context.el ends here
