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
;;
;; Every such buffer also gets an I/O-free `project' instance
;; (`gascity-context-install-project').  project.el's default backend,
;; `project-try-vc', walks up from `default-directory' with
;; `locate-dominating-file' and caches only successes; a city root has
;; no VCS root above it, so with `project-mode-line' on EVERY redisplay
;; of a remote view or attach buffer re-ran that walk over TRAMP
;; (\"File is missing: /ssh:…\", \"Error during redisplay … (quit)\").
;; The gascity project answers from a buffer-local root by string
;; prefix and touches no file, remote or local.
;;
;; City-scoped state is keyed by ONE identity, `gascity-context-scope-key':
;; the governing city root (which embeds the remote prefix) when DIR is
;; inside a city, the bare remote prefix ("" for local) otherwise.  The
;; rig-list memo (`gascity-context--rigs-cache') keys by it, so two cities
;; on one host keep separate rig lists; `gascity-remote-buffer-name'
;; takes the same value as its qualifier from the view factory.  Any
;; future city-scoped cache MUST key by `gascity-context-scope-key' too —
;; one keying scheme, one API (next consumer: the formula catalog/recipe
;; caches of the formula-sling-ui work, plans/formula-sling-ui; REQ-010
;; of plans/multi-city-keying/requirements.md).
;;
;; The rig-list memo (`gascity-rigs-cached') serves the paths that must
;; never spawn gc synchronously — a terminal buffer wiring beads eldoc
;; to a rig's store, a dashboard tagging its id prefixes — from the
;; last `gc rig list' or `gc status' payload any view decoded, kept per
;; city by `gascity-context-scope-key'.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'gascity-reader)
(require 'gascity-remote)

;; The typed rig object lives in gascity-domain, which is loaded by
;; everything that can fill the rig memo; this module only reads it.
(declare-function gascity-rig-prefix "gascity-domain" (rig))

;; Buffer-local contract of beads.el's eldoc (Part A of gce-eldoc): the
;; id-prefix allowlist.  Referenced by name and `boundp'-guarded so this
;; package byte-compiles and runs against a beads.el without it.
(defvar beads-issue-id-prefixes)

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

(defvar gascity-context--root-cache (make-hash-table :test 'equal)
  "Cache mapping an absolute start directory to its city root, or nil.
Memo of `gascity-context-city-root': nil is cached too — a directory
OUTSIDE any city is the expensive answer, the marker walk runs all the
way up to `/', one `file-exists-p' per level, and over TRAMP each is a
channel round trip.  Every view open and re-pin walks from its
`default-directory', so an uncached miss repeated on each refresh.")

(defvar gascity-context--rigs-cache (make-hash-table :test 'equal)
  "Cache mapping a `gascity-context-scope-key' to the city's rigs.
The key is the governing city root (which embeds the remote prefix,
so two cities on one host never share an entry); \"\" — the bare
remote prefix — only for a directory outside any city.  The value is
the last `gascity-rig' list any view decoded for that city — from `gc
rig list' (`gascity-rigs') or a `gc status' payload
\(`gascity-rigs-remember').  Read by `gascity-rigs-cached', which never
spawns gc: the callers that consult it (terminal attach, view
creation) run on the UI path where a synchronous remote `gc' is a
multi-second stall.")

(defun gascity-context-clear-cache ()
  "Forget cached rig, city, root, and remote-executable resolutions.
The one cache entry point: also clears the city-root memo, the rig-list
memo, and the per-connection gc/tmux resolutions (hits and TTL'd
misses) of `gascity-remote-find-executable'.  Call after the city's rig
set changes, after a program moved on a remote host, or to force
re-resolution."
  (interactive)
  (clrhash gascity-context--rig-cache)
  (clrhash gascity-context--city-cache)
  (clrhash gascity-context--root-cache)
  (clrhash gascity-context--rigs-cache)
  (gascity-remote-forget-executables))

(defun gascity-context-city-root (&optional dir)
  "Return the Gas City root governing DIR (default `default-directory').
Honours `gascity-context-city'.  Otherwise walks up from DIR looking
for `gascity-context-city-file'.  Returns an absolute directory name
\(with trailing slash), or nil when DIR is not inside a city.

The walk is memoized per start directory in
`gascity-context--root-cache' — nil included, since a miss is the
full walk up to `/' and, over TRAMP, one channel round trip per
level.  The override is consulted first and never cached.  Clear with
`gascity-context-clear-cache' (e.g. after `gc init' created a city
around a directory already looked up)."
  (if gascity-context-city
      (file-name-as-directory (expand-file-name gascity-context-city))
    (let* ((start (expand-file-name (or dir default-directory)))
           (cached (gethash start gascity-context--root-cache 'miss)))
      (if (not (eq cached 'miss))
          cached
        (puthash start
                 (when-let* ((found (locate-dominating-file
                                     start gascity-context-city-file)))
                   (file-name-as-directory (expand-file-name found)))
                 gascity-context--root-cache)))))

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
    ;; project.el must never do I/O from this buffer's redisplay: the
    ;; pinned root is the project (see `gascity-context-install-project').
    (gascity-context-install-project buf dir)
    ;; When the rig list is already known for this host, narrow beads
    ;; eldoc to the city's real id prefixes — cheap, and it keeps a
    ;; stray hyphenated token from costing a `bd show'.  A cold memo is
    ;; left alone: never spawn gc to open a buffer.
    (when-let* ((prefixes (gascity-rigs-cached-prefixes dir)))
      (with-current-buffer buf
        (when (boundp 'beads-issue-id-prefixes)
          (setq-local beads-issue-id-prefixes prefixes))))
    buf))

;;; An I/O-free `project' for every gascity buffer

(defvar-local gascity-context-project-root nil
  "The project root of a gascity buffer, an absolute directory name.
Set by `gascity-context-install-project'; nil in buffers gascity does
not own.  `gascity-context-project-find-function' answers from this
value alone, so `project-current' in the buffer touches no file.
Permanent-local: every view enables its major mode AFTER the factory
pinned the buffer, and the mode's `kill-all-local-variables' must not
lose the root (see `gascity-context--reinstall-project').")
(put 'gascity-context-project-root 'permanent-local t)

(cl-defmethod project-root ((project (head gascity)))
  "Return the root directory of the gascity PROJECT, (gascity . ROOT)."
  (cdr project))

(cl-defmethod project-name ((project (head gascity)))
  "Return the name of the gascity PROJECT: the basename of its root.
For a city root that is the city name, for a rig store the rig's
directory name — what `project-mode-line' shows."
  (file-name-nondirectory (directory-file-name (cdr project))))

(defun gascity-context-project-find-function (dir)
  "Return the gascity project (gascity . ROOT) when DIR lies under ROOT.
ROOT is the buffer's `gascity-context-project-root'; the test is a plain
string prefix on the directory names — no `expand-file-name' (which,
for a TRAMP name, may consult the connection) and no disk access, so
it is safe from redisplay.  Nil when DIR is elsewhere or the buffer has
no root.  Installed as the buffer's sole `project-find-functions'
entry by `gascity-context-install-project'."
  (when-let* ((root gascity-context-project-root)
              ((stringp dir))
              ((string-prefix-p root (file-name-as-directory dir))))
    (cons 'gascity root)))

(defun gascity-context-install-project (buffer root)
  "Make ROOT the I/O-free `project' of BUFFER.
Sets `gascity-context-project-root' to ROOT (as a directory name),
replaces `project-find-functions' buffer-locally with
`gascity-context-project-find-function' ALONE — no trailing `t', so
the global backends (`project-try-vc') never run here — and empties
`vc-handled-backends' locally so VC's own root walk stays out too.

Why: project.el's VC backend caches only successes.  A city root has
no `.git' above it, so with `project-mode-line' on, every redisplay of
a remote view or attach buffer walked `~/city/', `~/', `/' over TRAMP
\(`project-try-vc' → `locate-dominating-file' → `directory-files'),
which is the hang seen as \"Error during redisplay … signaled (quit)\"
and repeated \"File is missing: /ssh:…\" in `*Messages*'.  Idempotent:
re-installing with the same ROOT changes nothing.  Survives a later
major-mode switch: the root is permanent-local and
`gascity-context--reinstall-project' restores the two hook variables
from it.  Returns BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq gascity-context-project-root (file-name-as-directory root))
      (setq-local project-find-functions
                  (list #'gascity-context-project-find-function))
      (setq-local vc-handled-backends nil)))
  buffer)

(defun gascity-context--reinstall-project ()
  "Restore the current buffer's gascity project after a major-mode switch.
On `after-change-major-mode-hook'.  Every view creates its buffer
through `gascity-view-get-buffer-create' and THEN enables its major
mode (`gascity-tabulated--show', the dashboards' mode + `vui-mount'),
whose `kill-all-local-variables' wipes the local `project-find-functions'
and `vc-handled-backends' — only `gascity-context-project-root' survives,
being permanent-local.  Re-install from it; a no-op in buffers gascity
does not own (the root is nil there)."
  (when gascity-context-project-root
    (gascity-context-install-project (current-buffer)
                                     gascity-context-project-root)))

(add-hook 'after-change-major-mode-hook #'gascity-context--reinstall-project)

;;; City-scoped keying — the one identity for per-city caches

(defun gascity-context-scope-key (&optional dir)
  "Return the city-scoped key for DIR (default `default-directory').
The governing city root when DIR is inside a city (a TRAMP-qualified
absolute directory string), else DIR's remote prefix (\"\" for local).
Never spawns gc — the city-root walk is the memoized
`gascity-context--root-cache' lookup.  This is the ONE keying identity
for city-scoped caches and buffer names; document any new cache keyed
by it here in this commentary (first consumer outside this file: the
formula catalog/recipe caches, plans/formula-sling-ui)."
  (or (gascity-context-city-root dir)
      (file-remote-p (or dir default-directory)) ""))

;;; Rig-list memo — the rigs without a spawn

(defun gascity-context--rigs-key (&optional dir)
  "Return the `gascity-context--rigs-cache' key for DIR's city.
`gascity-context-scope-key' of DIR (default `default-directory'): the
governing city root — which embeds the remote prefix, so the key is
per city on a host, not just per host — or the remote prefix (\"\" for
local) outside any city."
  (gascity-context-scope-key dir))

(defun gascity-rigs-remember (rigs &optional dir)
  "Memoize RIGS, a list of `gascity-rig', as DIR's host's rig list.
Called by `gascity-rigs' after a successful `gc rig list' and by the
status dashboard for the rigs of each `gc status' payload, so any view
that has already paid for the read leaves the answer for the paths
that must not spawn (`gascity-rigs-cached').  A list carrying no id
prefixes never replaces one that does — a payload variant without
`prefix' must not blank the prefix→store map the eldoc wiring relies
on.  Always returns RIGS itself, so a caller can wrap its decode in
this and still render exactly what it read — the memo must never leak
into a view."
  (let* ((key (gascity-context--rigs-key dir))
         (old (gethash key gascity-context--rigs-cache))
         (prefixed-p (lambda (list)
                       (cl-some (lambda (rig) (gascity-rig-prefix rig)) list))))
    (unless (and old (funcall prefixed-p old) (not (funcall prefixed-p rigs)))
      (puthash key rigs gascity-context--rigs-cache))
    rigs))

(defun gascity-rigs-cached (&optional dir)
  "Return the memoized rig list for DIR's host, or nil when cold.
Never spawns gc — the reader for UI-path callers (terminal attach, view
creation) that want the city's rigs only if some view already fetched
them.  DIR defaults to `default-directory'."
  (gethash (gascity-context--rigs-key dir) gascity-context--rigs-cache))

(defun gascity-rigs-cached-prefixes (&optional dir)
  "Return the bead-id prefixes of DIR's memoized rigs, or nil when cold.
A list of strings (\"gce\" \"bs\" …) with nil prefixes dropped, ready
for beads.el's `beads-issue-id-prefixes'."
  (delq nil (mapcar #'gascity-rig-prefix (gascity-rigs-cached dir))))

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
