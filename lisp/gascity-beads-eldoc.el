;;; gascity-beads-eldoc.el --- Per-city bead-id prefix to store map -*- lexical-binding: t; -*-

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
;; The install path (buffer-locals for beads.el's eldoc, the major-mode
;; re-install hook, the deny-all sentinel) and the caller migration (`C-c b`,
;; `gascity-beads--bead-path-cached') are the plan's items 2 and 3 and extend
;; this module.

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

(provide 'gascity-beads-eldoc)
;;; gascity-beads-eldoc.el ends here
