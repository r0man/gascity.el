;;; gascity-beads-eldoc.el --- Per-city bead-id map and its install path -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The one prefix -> bead-store map of a gascity city (plans/beads-eldoc-prefix
;; §A, §H item 1).  beads.el's eldoc resolves a bead id by handing a store
;; directory to `bd'; gascity knows which store owns an id from the id's
;; prefix, and that knowledge is a property of the city, not of the buffer
;; the id happens to appear in.  This module keeps it that way:
;;
;; - One `gascity-beads-eldoc--map' per `gascity-context-scope-key' (a city
;;   root, TRAMP-qualified): the prefix -> store alist, the flat prefix list
;;   beads.el's allowlist consumes, and the fill bookkeeping.
;; - One asynchronous fill per city, `gc rig list' through
;;   `gascity-store-fetch' with `:dir' the city root (never a worktree), so it
;;   joins an in-flight read, runs on the host's read lane, and respects the
;;   store's deadline and offline backoff.  Nothing here runs gc or bd
;;   synchronously: no render, redisplay, timer, or eldoc hook (REQ-005,
;;   REQ-012).
;; - One pure resolver, `gascity-beads-eldoc--store-for', the only
;;   implementation of prefix -> store in the package.  It reads the map and
;;   nothing else — no `default-directory', no TRAMP work, no spawn — and the
;;   directories it answers with were localized once, at fill time.
;;
;; Rows are taken from the decoded `gc rig list' payload with the plan's
;; decisions: the HQ row declares the city store (REQ-003, D7 — without it
;; there is no city entry, never an invented one); a prefixed, initialized rig
;; row declares its repo store (REQ-004, D5); an unusable row contributes
;; nothing; the first row claiming a prefix wins and later duplicates are
;; dropped with one logged line per fill (D4).
;;
;; Refresh is stale-while-revalidate: a map past `gascity-beads-eldoc-map-ttl'
;; keeps answering while one refill runs (at most every
;; `gascity-beads-eldoc-refill-min-interval'; after a failure no sooner than
;; `gascity-beads-eldoc-retry-delay').  Outside a city there is no scope, so
;; there is no map and no fill (D8): a map keyed by the bare host prefix would
;; be shared by every local city on the host (REQ-007).
;;
;; Eldoc resolves an id by its prefix, so a buffer needs two related
;; buffer-locals from beads.el: `beads-eldoc-directory', a function of the id
;; answering the store that owns the id's prefix (never a bare store string:
;; a transcript in one rig must still resolve another rig's id, REQ-002), and
;; `beads-issue-id-prefixes', the city's real prefixes, so a random
;; hyphenated token in the transcript never costs a `bd show'.
;;
;; `gascity-beads-eldoc-install' is the only writer of that contract in the
;; package.  The view factory (`gascity-view-created-functions') and
;; `after-change-major-mode-hook' both funnel into
;; `gascity-beads-eldoc--apply', so every view and every terminal/attach
;; buffer gets the same wiring and keeps it across the major mode's
;; `kill-all-local-variables' (TS-5).  The city scope is captured at install
;; time, never re-derived from `default-directory' later: an attach buffer in
;; a polecat worktree outside the city tree still resolves the city and its
;; rigs (REQ-008, TS-4).  No city context means no install and no fill (D8).
;;
;; Cold start admits nothing: `gascity-beads-eldoc--deny-all-prefixes' is
;; `'("")', which beads.el's `beads-issue-id--allowed-p' can never match, so
;; a cold buffer never falls back to `default-directory' (REQ-006).  When a
;; fill lands, `gascity-beads-eldoc--land' re-applies the map to the buffers
;; already open for that scope (`gascity-beads-eldoc--reapply-buffers'), so
;; they heal without being reopened or reverted.  The caller migration
;; (`C-c b', `gascity-beads--bead-path-cached') is the plan's item 3 and
;; reuses the same resolver.

;;; Code:

(require 'cl-lib)
(require 'gascity-context)
(require 'gascity-domain)
(require 'gascity-remote)
(require 'gascity-section)
(require 'gascity-store)

(declare-function gascity--log "gascity")

;;; Options

(defcustom gascity-beads-eldoc-map-ttl 600
  "Seconds a city's bead-id prefix to store map stays fresh.
Past it the map is marked stale and one refill starts, while the old
map keeps answering (stale-while-revalidate).  The live stream and rig
actions invalidate the map earlier; this covers a city with no stream."
  :type 'integer
  :group 'gascity)

(defcustom gascity-beads-eldoc-refill-min-interval 30
  "Minimum seconds between two successful bead-id map fills of one city.
Bounds the refill rate when the live stream's frequent session/agent
batches keep marking the map stale."
  :type 'integer
  :group 'gascity)

(defcustom gascity-beads-eldoc-retry-delay 60
  "Seconds to wait after a failed bead-id map fill before retrying.
A cold city stays cold meanwhile; a warm map keeps serving its last
good payload."
  :type 'integer
  :group 'gascity)

;;; Data model

(cl-defstruct (gascity-beads-eldoc--map
               (:constructor gascity-beads-eldoc--map-create))
  scope                                 ; gascity-context-scope-key
  city                                  ; the city root, localized
  stores                                ; alist: prefix -> store directory
  prefixes                              ; flat list, gc rig list order
  fetched-at                            ; float-time of the last good fill
  (stale nil)                           ; serve the map, refill it
  (fetching nil)                        ; a fill is in flight
  (failed-at 0))                        ; float-time of the last failure

(defvar gascity-beads-eldoc--maps (make-hash-table :test 'equal)
  "Map from `gascity-context-scope-key' to `gascity-beads-eldoc--map'.
One entry per city, never shared across cities on one host (REQ-007).")

;;; The pure resolver

(defun gascity-beads-eldoc--store-for (map id)
  "Return MAP's store directory for bead ID, or nil.
Pure: ID's prefix is looked up in MAP's stores and nothing else — no
`default-directory', no path expansion, no TRAMP call, no spawn.  A nil
MAP, an id without a prefix, and a prefix the map does not know all
answer nil; the caller's allowlist is the same map's `prefixes', so
beads.el has already rejected ids the map cannot store."
  (when-let* ((prefix (and map (gascity-beads--id-prefix id))))
    (cdr (assoc prefix (gascity-beads-eldoc--map-stores map)))))

;;; Buffer state

(defvar-local gascity-beads-eldoc--scope nil
  "The city scope this buffer's bead eldoc resolves against.
Captured by `gascity-beads-eldoc-install' from the install context
\(a `gascity-context-scope-key'), never re-derived from the buffer's
`default-directory'.  Nil in buffers gascity does not own.  Permanent
local: every view enables its major mode after the factory installed
the wiring, and `kill-all-local-variables' must not lose the city the
buffer was opened for (TS-4, TS-5).")
(put 'gascity-beads-eldoc--scope 'permanent-local t)

(defvar-local gascity-beads-eldoc--map nil
  "The city map snapshot installed in this buffer, or nil while cold.
The resolver closure installed as `beads-eldoc-directory' captures this
object, so a fill that mutates the map in place is visible to it.
Permanent local for the same reason as `gascity-beads-eldoc--scope'.")
(put 'gascity-beads-eldoc--map 'permanent-local t)

(defconst gascity-beads-eldoc--deny-all-prefixes '("")
  "The cold-map allowlist: a prefix that matches no bead id.
beads.el's `beads-issue-id--allowed-p' accepts a prefix P when
`(string-prefix-p (concat P \"-\") ID)'; ids begin with a letter, so
a \"-\" prefix never matches and the buffer admits nothing while the
map is cold.  Nil would mean \"accept any id\" — exactly the
wrong-store lookup REQ-006 forbids — and an empty list would mean the
same.  Pinned by an ERT test against the installed beads.el, so an
upstream change to that predicate fails loudly instead of silently
re-enabling the bug.")

;;; Buffer registry

(defvar gascity-beads-eldoc--buffers nil
  "Alist mapping a city scope to the buffers installed for it.
The fill re-applies the completed map to these buffers
\(`gascity-beads-eldoc--reapply-buffers'), so a buffer installed while
the map was cold heals without being reopened (REQ-006).  Dead buffers
are pruned on every use; the registry holds no other state.")

(defun gascity-beads-eldoc--live-buffers (scope)
  "Return the live buffers registered for SCOPE, pruning dead ones.
SCOPE is a string (`gascity-context-scope-key'), so the lookup is
`assoc'/`equal', never `eq'."
  (let ((cell (assoc scope gascity-beads-eldoc--buffers)))
    (when cell
      (setcdr cell (seq-filter #'buffer-live-p (cdr cell)))
      (if (cdr cell)
          (cdr cell)
        (setq gascity-beads-eldoc--buffers
              (assoc-delete-all scope gascity-beads-eldoc--buffers))
        nil))))

(defun gascity-beads-eldoc--register (buffer)
  "Register BUFFER under its installed scope; return BUFFER.
Idempotent: a re-install moves the buffer to the front instead of
duplicating it."
  (let* ((scope gascity-beads-eldoc--scope)
         (cell (assoc scope gascity-beads-eldoc--buffers)))
    (if cell
        (setcdr cell (cons buffer (delq buffer (cdr cell))))
      (push (cons scope (list buffer)) gascity-beads-eldoc--buffers))
    buffer))

(defun gascity-beads-eldoc--reapply-buffers (scope)
  "Re-resolve SCOPE's map and re-apply it to its registered buffers.
Called when a fill completes: a buffer installed cold goes from
deny-all to the city's prefixes and per-id resolver without being
reopened or reverted (REQ-006).  Buffers whose scope changed since
registration are left alone; dead ones are pruned.  Reads the landed
map directly — this runs from the fill's own completion, so it must
never start another read."
  (when-let* ((map (gethash scope gascity-beads-eldoc--maps))
              ((gascity-beads-eldoc--map-fetched-at map)))
    (dolist (buffer (gascity-beads-eldoc--live-buffers scope))
      (with-current-buffer buffer
        (when (equal gascity-beads-eldoc--scope scope)
          (setq gascity-beads-eldoc--map map)
          (gascity-beads-eldoc--apply buffer))))))

;;; Fill

(defun gascity-beads-eldoc--ensure (scope city)
  "Return the map for SCOPE, creating it for the city rooted at CITY."
  (or (gethash scope gascity-beads-eldoc--maps)
      (puthash scope
               (gascity-beads-eldoc--map-create :scope scope :city city)
               gascity-beads-eldoc--maps)))

(defun gascity-beads-eldoc--row-store (rig city-store)
  "Return RIG's store directory for the map, or nil when the row is unusable.
CITY-STORE is the city root's store, used for the HQ row.  A row needs a
non-empty prefix and path and a `beads' status that is absent or
\"initialized\" (D5); a non-HQ row maps to its rig repo, the HQ row to
CITY-STORE.  Nothing is invented for an unusable row — in particular a
prefix-less row is not a wildcard, and no HQ row means no city entry
\(D7)."
  (let ((prefix (gascity-rig-prefix rig))
        (path (gascity-rig-path rig))
        (beads (gascity-rig-store rig)))
    (when (and (stringp prefix)
               (not (string-empty-p prefix))
               (stringp path)
               (not (string-empty-p path))
               (or (null beads) (equal beads "initialized")))
      (if (gascity-rig-hq rig)
          city-store
        (gascity-beads--rig-path rig)))))

(defun gascity-beads-eldoc--land (map city payload)
  "Fill MAP from a `gc rig list' PAYLOAD read for the city rooted at CITY.
Decodes the rigs once, remembers them for the existing spawn-free
readers, and builds the stores and prefixes in `gc rig list' order.
Directories are localized for CITY's host here, once, so the resolver
stays pure.  A duplicate prefix keeps the first row's store and logs one
line per fill (D4)."
  (let* ((default-directory city)
         (rigs (gascity-domain-decode-list 'gascity-rig
                                           (alist-get 'rigs payload)))
         (city-store (gascity-beads--city-store city))
         (stores nil)
         (prefixes nil)
         (warned nil))
    (gascity-rigs-remember rigs city)
    (dolist (rig rigs)
      (let ((prefix (gascity-rig-prefix rig)))
        (when-let* ((store (and (stringp prefix)
                                (not (string-empty-p prefix))
                                (gascity-beads-eldoc--row-store
                                 rig city-store))))
          (cond
           ((assoc prefix stores)
            (unless warned
              (setq warned t)
              (when (fboundp 'gascity--log)
                (gascity--log
                 'info
                 (concat "Duplicate bead-id prefix %s in gc rig list; "
                         "keeping the first store")
                 prefix))))
           (t
            (push (cons prefix store) stores)
            (push prefix prefixes))))))
    (setf (gascity-beads-eldoc--map-city map) city
          (gascity-beads-eldoc--map-stores map) (nreverse stores)
          (gascity-beads-eldoc--map-prefixes map) (nreverse prefixes)
          (gascity-beads-eldoc--map-fetched-at map) (float-time)
          (gascity-beads-eldoc--map-stale map) nil
          (gascity-beads-eldoc--map-fetching map) nil
          (gascity-beads-eldoc--map-failed-at map) 0)
    ;; The map is warm now: apply it to the buffers installed while it was
    ;; cold, so they heal without being reopened (REQ-006, plan §B).
    (gascity-beads-eldoc--reapply-buffers (gascity-beads-eldoc--map-scope map))
    map))

(defun gascity-beads-eldoc--fail (map err)
  "Record a failed fill of MAP with ERR.
The map keeps its last good payload (a cold city stays cold) and no
retry starts before `gascity-beads-eldoc-retry-delay'."
  (setf (gascity-beads-eldoc--map-fetching map) nil
        (gascity-beads-eldoc--map-failed-at map) (float-time))
  (when (fboundp 'gascity--log)
    (gascity--log 'error "gc rig list for the bead-id map failed: %s"
                  (if (stringp err) err (format "%s" err)))))

(defun gascity-beads-eldoc--fill (scope city)
  "Start at most one `gc rig list' read for SCOPE, the city rooted at CITY.
The read goes through the payload store with `:dir' CITY, so it joins an
in-flight read and runs on the host's read lane; the map is updated when
the payload lands and every attached buffer of SCOPE should be re-applied
by the install path.  Returns the map, or nil when SCOPE already has a
fill in flight."
  (let ((map (gascity-beads-eldoc--ensure scope city)))
    (unless (gascity-beads-eldoc--map-fetching map)
      (setf (gascity-beads-eldoc--map-fetching map) t)
      (gascity-store-fetch
       '("rig" "list")
       (lambda (payload) (gascity-beads-eldoc--land map city payload))
       (lambda (err) (gascity-beads-eldoc--fail map err))
       :dir city)
      map)))

;;; Refresh policy

(defun gascity-beads-eldoc--too-soon-p (map)
  "Return non-nil when MAP must not start another fill yet.
A good fill is not repeated within
`gascity-beads-eldoc-refill-min-interval'; a failed one not before
`gascity-beads-eldoc-retry-delay'."
  (let ((now (float-time))
        (fetched (gascity-beads-eldoc--map-fetched-at map))
        (failed (gascity-beads-eldoc--map-failed-at map)))
    (or (and failed
             (> failed 0)
             (< (- now failed) gascity-beads-eldoc-retry-delay))
        (and fetched
             (< (- now fetched) gascity-beads-eldoc-refill-min-interval)))))

(defun gascity-beads-eldoc--expired-p (map)
  "Return non-nil when MAP is past `gascity-beads-eldoc-map-ttl'."
  (when-let* ((fetched (gascity-beads-eldoc--map-fetched-at map)))
    (> (- (float-time) fetched) gascity-beads-eldoc-map-ttl)))

(defun gascity-beads-eldoc--refill (map scope city)
  "Start one refill of MAP (or of a new map for SCOPE) in CITY.
No refill while one is in flight, or too soon after the last good or
failed fill (`gascity-beads-eldoc--too-soon-p')."
  (let ((map (or map (gascity-beads-eldoc--ensure scope city))))
    (unless (or (gascity-beads-eldoc--map-fetching map)
                (gascity-beads-eldoc--too-soon-p map))
      (gascity-beads-eldoc--fill scope city))
    map))

;;; Entry point

(defun gascity-beads-eldoc-map (&optional dir)
  "Return the prefix to store map of DIR's city, or nil while it is cold.
DIR defaults to `default-directory'.  A cold map starts one asynchronous
fill and answers nil; a warm map is returned as is, and when it is stale
\(past `gascity-beads-eldoc-map-ttl', or marked stale by an
invalidation) it keeps answering while one refill runs — at most every
`gascity-beads-eldoc-refill-min-interval'.  Nil outside every city: no
city root, no scope, no fill (D8, REQ-007).

This is the map's only read path; it never runs gc or bd synchronously
\(REQ-005, REQ-012)."
  (when-let* ((city (gascity-context-city-root dir)))
    (let* ((scope (gascity-context-scope-key city))
           (map (gethash scope gascity-beads-eldoc--maps)))
      (cond
       ((or (null map) (null (gascity-beads-eldoc--map-fetched-at map)))
        (gascity-beads-eldoc--refill map scope city)
        nil)
       (t
        (when (or (gascity-beads-eldoc--map-stale map)
                  (gascity-beads-eldoc--expired-p map))
          (setf (gascity-beads-eldoc--map-stale map) t)
          (gascity-beads-eldoc--refill map scope city))
        map)))))

;;; Install

(defun gascity-beads-eldoc--apply (buffer)
  "Apply BUFFER's installed map to beads.el's buffer-local contract.
Sets, boundp-guarded and after a soft `require' of beads-eldoc,
`beads-eldoc-directory' to a closure over the buffer's map snapshot and
`beads-issue-id-prefixes' to that snapshot's prefixes — or to
`gascity-beads-eldoc--deny-all-prefixes' while cold, so no id is
admitted before the map lands.  A no-op against a beads.el without the
variables.  Returns BUFFER."
  (when (buffer-live-p buffer)
    (require 'beads-eldoc nil t)
    (with-current-buffer buffer
      (when (boundp 'beads-eldoc-directory)
        (setq-local beads-eldoc-directory
                    (let ((map gascity-beads-eldoc--map))
                      (lambda (id)
                        (and map
                             (gascity-beads-eldoc--store-for map id))))))
      (when (boundp 'beads-issue-id-prefixes)
        (setq-local beads-issue-id-prefixes
                    (or (and gascity-beads-eldoc--map
                             (gascity-beads-eldoc--map-prefixes
                              gascity-beads-eldoc--map))
                        gascity-beads-eldoc--deny-all-prefixes))))
    buffer))

(defun gascity-beads-eldoc-install (&optional buffer dir)
  "Install per-id bead eldoc in BUFFER.
BUFFER defaults to the current buffer.  DIR is the city context to
capture, defaulting to BUFFER's `default-directory'; it is the city
root for a view and the origin city's root for an attach.  The scope is
captured now (TS-4): a later refresh, an attach buffer pinned to a
worktree, or a major-mode switch never re-derives it from
`default-directory'.

No city context — DIR outside any city tree — installs nothing and
starts no fill (D8): the buffer keeps beads.el's own behavior.  A
beads.el without the eldoc variables is likewise left alone.  Returns
BUFFER when installed, nil otherwise."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (let* ((dir (or dir (buffer-local-value 'default-directory buffer)))
             (city (gascity-context-city-root dir)))
        (when city
          (with-current-buffer buffer
            (setq gascity-beads-eldoc--scope (gascity-context-scope-key dir))
            (setq gascity-beads-eldoc--map (gascity-beads-eldoc-map dir))
            (gascity-beads-eldoc--register buffer)
            (gascity-beads-eldoc--apply buffer)
            buffer))))))

(defun gascity-beads-eldoc--reinstall ()
  "Re-apply this buffer's installed bead eldoc after a major-mode switch.
On `after-change-major-mode-hook', mirroring
`gascity-context--reinstall-project': every view enables its major mode
AFTER the factory installed the wiring, and the mode's
`kill-all-local-variables' drops `beads-eldoc-directory' and
`beads-issue-id-prefixes' (auto buffer-local).  The scope and map are
permanent-local, so they survive to re-apply from.  A no-op in buffers
gascity does not own (no scope)."
  (when gascity-beads-eldoc--scope
    (gascity-beads-eldoc--apply (current-buffer))))

(defun gascity-beads-eldoc--buffers-go-cold ()
  "Put every installed buffer back in the cold deny-all state.
Runs after `gascity-beads-eldoc-clear-cache' dropped every city map: the
resolver closure installed as `beads-eldoc-directory' captured the old
map object, so an open buffer would otherwise keep answering from a map
the clear dropped (REQ-007, REQ-010).  Each buffer is reinstalled against
its own captured scope — never its `default-directory', so an attach
buffer pinned to a worktree outside the city stays scoped to the city it
was opened for.  The install sees the cold map table, applies deny-all,
and starts the one deduplicated fill; `gascity-beads-eldoc--reapply-buffers'
heals the buffer when that fill lands."
  (dolist (scope (mapcar #'car gascity-beads-eldoc--buffers))
    (dolist (buffer (gascity-beads-eldoc--live-buffers scope))
      (with-current-buffer buffer
        (when (equal gascity-beads-eldoc--scope scope)
          (gascity-beads-eldoc-install buffer scope))))))

;;; Wiring

;; Every buffer the view factory creates, and every attach buffer the
;; terminal opens (which calls the installer itself), goes through the one
;; install path (REQ-001, TS-1).
(add-hook 'gascity-view-created-functions #'gascity-beads-eldoc-install)

;; Major-mode setup must not lose the wiring (TS-5).
(add-hook 'after-change-major-mode-hook #'gascity-beads-eldoc--reinstall)

;; An explicit clear drops the maps, so the buffers that installed one must
;; go cold instead of answering from the dropped snapshot (REQ-010).  The
;; seam is owned by the refresh/invalidation slice; `add-hook' needs no
;; value, so this registration is load-order independent.
(add-hook 'gascity-beads-eldoc-clear-cache-functions
          #'gascity-beads-eldoc--buffers-go-cold)
;;; The buffer-aware resolver (plan §C — caller migration)

;; The install path (`gascity-beads-eldoc-install', plan §B) captures each
;; buffer's city scope and map snapshot in `gascity-beads-eldoc--scope' /
;; `gascity-beads-eldoc--map'.  This accessor is the one place a caller
;; asks "which store owns this id": `C-c b'
;; (`gascity-bead-show-at-point'), `gascity-beads--bead-path-cached' and
;; the read-side views all go through it, so the command opens exactly the
;; store beads eldoc named (REQ-013) and no caller re-resolves from
;; `default-directory'.
;;
;; The two variables are reached by symbol, not by a forward `defvar': the
;; install path owns them, and this accessor must stay usable (and
;; byte-compile clean) on a tree where that module half has not landed
;; yet — it then answers from the city map of `default-directory', which
;; is what a cold install would do anyway.

(defun gascity-beads-eldoc-store-for-id (id)
  "Return the store directory owning bead ID, or nil.
Answers, in order: this buffer's installed map snapshot when its city
matches, the city map of `default-directory' (starting at most one
asynchronous fill when it is cold), else nil.  Never runs gc or bd, never
uses `default-directory' as a store, never expands a path: the map's
directories were localized once at fill time (REQ-005, REQ-012)."
  (let* ((scope (and (boundp 'gascity-beads-eldoc--scope)
                     (symbol-value 'gascity-beads-eldoc--scope)))
         (snapshot (and scope
                        (boundp 'gascity-beads-eldoc--map)
                        (symbol-value 'gascity-beads-eldoc--map)))
         (map (if (and snapshot
                       (equal (gascity-beads-eldoc--map-scope snapshot) scope))
                  snapshot
                (gascity-beads-eldoc-map))))
    (and map (gascity-beads-eldoc--store-for map id))))

(defun gascity-beads-eldoc-map-ready-p (&optional dir)
  "Return non-nil when DIR's city map has landed at least one store.
The counterpart of a nil `gascity-beads-eldoc-store-for-id': it tells a
caller whether \"no store owns this id\" is final (a warm map that simply
does not carry the prefix) or still pending (no map yet, or a first fill
that has landed nothing).  Callers use it to defer rather than report a
wrong answer (REQ-006/REQ-011).  DIR defaults to `default-directory'.
Pure: it reads the cached map and starts the one asynchronous fill when
cold, exactly like `gascity-beads-eldoc-map'."
  (when-let* ((map (gascity-beads-eldoc-map dir)))
    (gascity-beads-eldoc--map-prefixes map)))

(provide 'gascity-beads-eldoc)
;;; gascity-beads-eldoc.el ends here
