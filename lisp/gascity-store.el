;;; gascity-store.el --- Per-city payload store and per-host scheduler -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The read cache and process scheduler every gascity view reads
;; through (dashboard-v3 §8.3 R3/R5/R7, §8.5).  Before it, each view
;; section spawned its own `gc' read; over TRAMP that meant many
;; concurrent channel setups and reads that could run forever.  The
;; store owns three things:
;;
;; - Payloads.  One entry per (DIRECTORY . ARGV) — the directory a
;;   read runs in (a view's pinned city root, or a rig repo) and the
;;   gc argv without `--json'.  Every view of a city shares the one
;;   `gc status' entry.  An entry keeps its LAST GOOD payload forever:
;;   a pending refetch, a failure or a timeout only adds flags, so
;;   consumers render stale-while-revalidate and never unmount.
;;   A second request for an entry with a read in flight joins it
;;   (in-flight dedup).  Freshness is a TTL per read kind
;;   (`gascity-store-ttl-alist'); the kind is the argv's first token
;;   (`status', `bd', `session', …).
;;
;; - Scheduling.  Jobs run per host (the TRAMP prefix, \"\" for local)
;;   in two lanes — reads and actions — each capped at
;;   `gascity-remote-max-inflight' concurrent processes on a remote
;;   host (local is unlimited).  A queue is FIFO, except that a job
;;   whose requesting buffer is visible goes first.  Every job has a
;;   deadline (`gascity-remote-async-timeout'): on expiry the process
;;   is killed, the entry keeps its data flagged `:timed-out' and the
;;   slot is freed.  A connection-level failure flips the whole host
;;   `offline': its queues pause, the failed reads are re-queued (no
;;   per-section error storm) and one probe is retried with backoff
;;   (`gascity-store-offline-backoff').  The first dispatch on a
;;   remote host runs from a timer, so the view shows `…' before the
;;   synchronous first-contact resolution of gc on that host (§8.5).
;;
;; - Actions (D9).  `gascity-store-action' starts a mutating gc call
;;   in the action lane and returns at once.  Calls on the same target
;;   are serialized; the target is `pending' until its last call
;;   returns (`gascity-store-action-pending-p', for views that render
;;   `…').  Success echoes a label, failure echoes the first stderr
;;   line and appends the whole stderr to `*gascity-log: CITY*'.  No
;;   callback ever signals or prompts, and a completed action
;;   invalidates the read kinds it touches (§8.2 routing table) unless
;;   a live event stream covers the city.
;;
;; Consumers:
;;
;; - vui components call `gascity-store-use' in place of
;;   `vui-use-async'; it returns the same (:status :data :error) plist
;;   plus the store flags, and re-renders the component whenever the
;;   entry changes (a refetch triggered by any view or an
;;   invalidation).
;; - Callback code (tabulated lists, composite loaders) calls
;;   `gascity-store-fetch' (one shot) and/or `gascity-store-subscribe'.
;; - The event router (§8.2, phase P3) calls `gascity-store-invalidate'
;;   or `gascity-store-invalidate-event'.
;;
;; Process callbacks are never run inside a TRAMP operation: for a
;; remote host the store's own bookkeeping happens in the sentinel, and
;; everything that can touch TRAMP or the UI (payload delivery,
;; subscriber notification, starting the next queued job) runs from
;; `run-at-time' 0.  Locally delivery is immediate, as before.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-error)
(require 'gascity-remote)
(require 'gascity-reader)

(declare-function gascity--log "gascity")

;;; Customization

(defcustom gascity-remote-max-inflight 3
  "Maximum concurrent gc processes per remote host and lane.
The store (`gascity-store') runs reads and actions in two lanes per
TRAMP connection; each lane starts at most this many processes at a
time and queues the rest.  Local cities are never capped.  Nil means
unlimited."
  :type '(choice (natnum :tag "Processes") (const :tag "Unlimited" nil))
  :group 'gascity)

(defcustom gascity-remote-async-timeout 30
  "Seconds before an asynchronous gc process is killed, nil for never.
The deadline of every read and action the store schedules
\(dashboard-v3 §8.3 R5).  On expiry the process is killed, a read keeps
its last good payload flagged as timed out, and the scheduler slot is
freed.  Applies to local processes too: a wedged gc must never hold a
view forever."
  :type '(choice (natnum :tag "Seconds") (const :tag "Never" nil))
  :group 'gascity)

(defcustom gascity-store-ttl-alist '((status . 5) (bd . 15) (doctor . manual))
  "Freshness per read kind, in seconds.
Each element is (KIND . TTL): KIND is the symbol of a gc argv's first
token (`status', `bd', `session', …), TTL a number of seconds or the
symbol `manual' (fresh until invalidated).  Kinds not listed use
`gascity-store-default-ttl'.  A request for a fresh entry is answered
from the store without spawning gc; an explicit refresh (`g') always
re-reads."
  :type '(alist :key-type symbol
                :value-type (choice number (const manual)))
  :group 'gascity)

(defcustom gascity-store-default-ttl 5
  "Freshness in seconds of a read kind absent from `gascity-store-ttl-alist'."
  :type 'number
  :group 'gascity)

(defcustom gascity-store-offline-backoff '(2 5 15 60)
  "Seconds between reconnect probes of an offline host.
The Nth retry waits the Nth element; the last element repeats."
  :type '(repeat number)
  :group 'gascity)

(defvar gascity-store-offline-regexp
  (concat "\\(?:Connection \\(?:refused\\|closed\\|reset\\|timed out\\)"
          "\\|Could not resolve hostname\\|No route to host\\|Host is down"
          "\\|Network is unreachable\\|Tramp failed to connect"
          "\\|Permission denied (publickey\\|probe timed out"
          "\\|synchronous remote call timed out\\|(exit 255)\\)")
  "Regexp matching a read failure that means the host is unreachable.
Such a failure flips the host `offline' instead of erroring the one
section (§8.3 R5).")

(defvar gascity-store-host-state-functions nil
  "Abnormal hook run when a host goes offline or comes back.
Called with (HOST STATE REASON): HOST the TRAMP prefix (\"\" for
local), STATE `online', `offline' or `probing', REASON the failure
text or nil.  Header lines use it to show `○ offline @host'.")

(defvar gascity-store-pending-functions nil
  "Abnormal hook run when an action target becomes pending or settles.
Called with (TARGET DIR PENDING): TARGET the object id the action
named, DIR its directory, PENDING non-nil while calls are outstanding.
Views that render `…' on a pending row re-render from here.")

(defvar gascity-store-live-p-function nil
  "Function of a directory answering whether a live event stream covers it.
When it answers non-nil, a completed action leaves invalidation to the
stream (§8.5 \"Refresh\"); nil (the default, no stream yet) means
actions invalidate the kinds they touch themselves.")

(defvar gascity-store-synchronous-delivery nil
  "Non-nil delivers remote completions synchronously (tests only).
Normally a remote completion is deferred with `run-at-time' 0 so it
never runs inside a TRAMP operation.")

;;; Data structures

(cl-defstruct (gascity-store-entry (:constructor gascity-store--make-entry)
                                   (:copier nil))
  "One cached read."
  key dir args lines loader kind
  data has-data error timed-out fetched-at stale
  job waiters subscribers)

(cl-defstruct (gascity-store--host (:constructor gascity-store--make-host)
                                   (:copier nil))
  "Scheduler state of one host."
  name
  (reads nil) (actions nil)             ; FIFO job queues
  (running-reads 0) (running-actions 0)
  (state 'online) reason (backoff 0) retry-timer
  primed pump-timer)

(cl-defstruct (gascity-store--job (:constructor gascity-store--make-job)
                                  (:copier nil))
  "One scheduled gc process."
  lane host dir start entry buffers
  process timer done result
  ;; Actions only.
  target args label json on-success on-error echo invalidate)

(cl-defstruct (gascity-store--sub (:constructor gascity-store--make-sub)
                                  (:copier nil))
  "One subscription to an entry."
  entry fn buffer)

(defvar gascity-store--entries (make-hash-table :test 'equal)
  "Every store entry, keyed by (DIRECTORY . ARGV).")

(defvar gascity-store--hosts (make-hash-table :test 'equal)
  "Scheduler state per host name (TRAMP prefix, \"\" for local).")

(defvar gascity-store--good-dirs (make-hash-table :test 'equal)
  "Directories that answered a read this session (probe no more).")

(defvar gascity-store--targets (make-hash-table :test 'equal)
  "Outstanding action jobs per (HOST . TARGET), running one first.")

;;; Keys and kinds

(defun gascity-store--dir-host (dir)
  "Return the scheduler host name of DIR: its TRAMP prefix, or \"\"."
  (or (file-remote-p dir) ""))

(defun gascity-store--host (name)
  "Return the scheduler state of host NAME, creating it."
  (or (gethash name gascity-store--hosts)
      (puthash name (gascity-store--make-host :name name
                                              :primed (string-empty-p name))
               gascity-store--hosts)))

(defun gascity-store--dir (dir)
  "Normalize DIR (default `default-directory') to a directory name.
Pure string operation: no expansion, which could touch a remote host."
  (file-name-as-directory (or dir default-directory)))

(defun gascity-store-key (args &optional dir)
  "Return the store key of gc ARGS read in DIR (default `default-directory').
`--json' is dropped: the reader appends it, so a command object's argv
and a bare view argv name the same entry."
  (cons (gascity-store--dir dir) (remove "--json" args)))

(defun gascity-store-kind (args)
  "Return the read kind of gc ARGS: its first token as a symbol."
  (if (and (consp args) (stringp (car args)))
      (intern (car args))
    'custom))

(defun gascity-store--ttl (kind)
  "Return the TTL of read KIND: seconds or `manual'."
  (alist-get kind gascity-store-ttl-alist gascity-store-default-ttl))

(defun gascity-store--entry (dir args &optional lines loader)
  "Return the entry for ARGS read in DIR, creating it.
LINES and LOADER, when non-nil, are recorded on the entry (the latest
caller's closure wins; the key names the same read)."
  (let* ((key (gascity-store-key args dir))
         (entry (or (gethash key gascity-store--entries)
                    (puthash key (gascity-store--make-entry
                                  :key key :dir (car key) :args (cdr key)
                                  :kind (gascity-store-kind (cdr key)))
                             gascity-store--entries))))
    (when lines (setf (gascity-store-entry-lines entry) t))
    (when loader (setf (gascity-store-entry-loader entry) loader))
    entry))

(defun gascity-store--fresh-p (entry &optional max-age)
  "Return non-nil when ENTRY's payload may be served without a read.
MAX-AGE, when non-nil, overrides the kind's TTL."
  (and (gascity-store-entry-has-data entry)
       (not (gascity-store-entry-stale entry))
       (let ((ttl (or max-age (gascity-store--ttl (gascity-store-entry-kind entry)))))
         (or (eq ttl 'manual)
             (and (numberp ttl)
                  (< (- (float-time) (or (gascity-store-entry-fetched-at entry) 0))
                     ttl))))))

;;; Snapshots and subscribers

(defun gascity-store-offline-p (&optional dir)
  "Return non-nil when DIR's host (default `default-directory') is offline."
  (when-let* ((host (gethash (gascity-store--dir-host (gascity-store--dir dir))
                             gascity-store--hosts)))
    (memq (gascity-store--host-state host) '(offline probing))))

(defun gascity-store-host-status (&optional dir)
  "Return DIR's host scheduler status as a plist.
Keys: :state (`online', `offline' or `probing'), :reason, :reads and
:actions (running counts), :queued (waiting jobs).  Pure; DIR defaults
to `default-directory'."
  (let ((host (gascity-store--host
               (gascity-store--dir-host (gascity-store--dir dir)))))
    (list :state (gascity-store--host-state host)
          :reason (gascity-store--host-reason host)
          :reads (gascity-store--host-running-reads host)
          :actions (gascity-store--host-running-actions host)
          :queued (+ (length (gascity-store--host-reads host))
                     (length (gascity-store--host-actions host))))))

(defun gascity-store-snapshot (entry)
  "Return ENTRY's state as a `vui-use-async'-compatible plist.
:status is `ready' whenever a payload is held — also while a refetch
is pending or after a failure (stale-while-revalidate: consumers keep
rendering it) — else `error' after a failure, else `pending'.  :data is
the last good payload, :error the last failure text.  Flags: :pending
\(a read in flight), :timed-out, :offline (the host is unreachable),
:stale (invalidated, refetch not yet answered), :fetched-at."
  (let ((has-data (gascity-store-entry-has-data entry))
        (err (gascity-store-entry-error entry))
        (job (gascity-store-entry-job entry)))
    (list :status (cond (has-data 'ready)
                        ((and err (not job)) 'error)
                        (t 'pending))
          :data (gascity-store-entry-data entry)
          :error err
          :pending (and job t)
          :timed-out (gascity-store-entry-timed-out entry)
          :offline (and (gascity-store-offline-p (gascity-store-entry-dir entry)) t)
          :stale (gascity-store-entry-stale entry)
          :fetched-at (gascity-store-entry-fetched-at entry))))

(defun gascity-store-buffer-pending-p (&optional buffer)
  "Return non-nil when a read BUFFER subscribes to is in flight.
BUFFER defaults to the current buffer.  Pure; auto-refresh timers use
it to skip a tick while the previous refresh is still loading."
  (let ((buffer (or buffer (current-buffer)))
        (pending nil))
    (maphash (lambda (_key entry)
               (when (and (not pending)
                          (gascity-store-entry-job entry)
                          (cl-some (lambda (sub)
                                     (eq (gascity-store--sub-buffer sub) buffer))
                                   (gascity-store-entry-subscribers entry)))
                 (setq pending t)))
             gascity-store--entries)
    pending))

(defun gascity-store-get (args &optional dir)
  "Return the snapshot of ARGS read in DIR, or nil when never requested.
Never spawns anything; DIR defaults to `default-directory'."
  (when-let* ((entry (gethash (gascity-store-key args dir) gascity-store--entries)))
    (gascity-store-snapshot entry)))

(defun gascity-store--safe-call (fn &rest args)
  "Call FN with ARGS; report and swallow any error (never from a sentinel)."
  (condition-case err
      (apply fn args)
    (error
     (message "gascity: %s" (error-message-string err))
     nil)))

(defun gascity-store--notify (entry)
  "Call every live subscriber of ENTRY with its snapshot."
  (let ((snapshot (gascity-store-snapshot entry)))
    (dolist (sub (gascity-store-entry-subscribers entry))
      (let ((buffer (gascity-store--sub-buffer sub)))
        (if (and buffer (not (buffer-live-p buffer)))
            (gascity-store-unsubscribe sub)
          (gascity-store--safe-call (gascity-store--sub-fn sub) snapshot))))))

(defun gascity-store--subscribe-entry (entry fn &optional buffer)
  "Subscribe FN to ENTRY; drop it when BUFFER dies.  Return the handle."
  (let ((sub (gascity-store--make-sub :entry entry :fn fn :buffer buffer)))
    (push sub (gascity-store-entry-subscribers entry))
    sub))

(cl-defun gascity-store-subscribe (args fn &key dir lines loader buffer)
  "Call FN with a snapshot whenever the ARGS entry changes; return a handle.
The plain-callback consumer API (tabulated lists): FN receives the
plist of `gascity-store-snapshot' after every completed read of ARGS in
DIR (default `default-directory') — whoever requested it — and on host
state changes.  BUFFER (default the current buffer) owns the
subscription: it is dropped once BUFFER is killed.  LINES and LOADER
as for `gascity-store-fetch'.  Subscribing does not read; pair it with
`gascity-store-fetch' or `gascity-store-request'."
  (gascity-store--subscribe-entry
   (gascity-store--entry (gascity-store--dir dir) args lines loader)
   fn (or buffer (current-buffer))))

(defun gascity-store-unsubscribe (handle)
  "Remove subscription HANDLE (from `gascity-store-subscribe'); nil is a no-op."
  (when handle
    (let ((entry (gascity-store--sub-entry handle)))
      (setf (gascity-store-entry-subscribers entry)
            (delq handle (gascity-store-entry-subscribers entry))))))

;;; Deferral

(defun gascity-store--after (host fn)
  "Run FN now for a local HOST, else from `run-at-time' 0.
A remote completion must never run inside the TRAMP operation whose
`accept-process-output' dispatched the sentinel."
  (if (or gascity-store-synchronous-delivery
          (string-empty-p (gascity-store--host-name* host)))
      (funcall fn)
    (run-at-time 0 nil fn)))

(defun gascity-store--host-name* (host)
  "Return HOST's name (HOST a host struct or a name string)."
  (if (stringp host) host (gascity-store--host-name host)))

;;; Scheduler

(defun gascity-store--job-visible-p (job)
  "Return non-nil when one of JOB's requesting buffers is visible."
  (cl-some (lambda (b) (and (buffer-live-p b) (get-buffer-window b 'visible)))
           (gascity-store--job-buffers job)))

(defun gascity-store--capacity (host lane)
  "Return how many more LANE jobs HOST may start now (a number)."
  (let ((running (if (eq lane 'action)
                     (gascity-store--host-running-actions host)
                   (gascity-store--host-running-reads host)))
        (cap (and (not (string-empty-p (gascity-store--host-name host)))
                  gascity-remote-max-inflight)))
    (pcase (gascity-store--host-state host)
      ('offline 0)
      ('probing (if (> (+ (gascity-store--host-running-reads host)
                          (gascity-store--host-running-actions host))
                       0)
                    0 1))
      (_ (if (numberp cap) (max 0 (- cap running)) most-positive-fixnum)))))

(defun gascity-store--pop (host lane)
  "Remove and return the next LANE job of HOST: visible first, else FIFO."
  (let* ((queue (if (eq lane 'action)
                    (gascity-store--host-actions host)
                  (gascity-store--host-reads host)))
         (job (or (cl-find-if #'gascity-store--job-visible-p queue)
                  (car queue))))
    (when job
      (if (eq lane 'action)
          (setf (gascity-store--host-actions host) (delq job queue))
        (setf (gascity-store--host-reads host) (delq job queue))))
    job))

(defun gascity-store--pump-later (host &optional delay)
  "Pump HOST from a timer after DELAY seconds (default 0), once."
  (unless (timerp (gascity-store--host-pump-timer host))
    (setf (gascity-store--host-pump-timer host)
          (run-at-time (or delay 0) nil
                       (lambda ()
                         (setf (gascity-store--host-pump-timer host) nil)
                         (gascity-store--pump host t))))))

(defun gascity-store--pump (host &optional from-timer)
  "Start queued jobs of HOST while its lanes have capacity.
A remote host is pumped synchronously only once primed (its first
dispatch — the synchronous first-contact resolution of gc — runs from
a timer, FROM-TIMER non-nil) and while its TRAMP channel is not
mid-command (a spawn from inside another TRAMP call would be
reentrant); otherwise the pump is retried from a timer."
  (let ((name (gascity-store--host-name host)))
    (cond
     ((and (not (string-empty-p name))
           (not from-timer)
           (not (gascity-store--host-primed host))
           (or (gascity-store--host-reads host) (gascity-store--host-actions host)))
      (gascity-store--pump-later host))
     ((and (not (string-empty-p name))
           (or (gascity-store--host-reads host) (gascity-store--host-actions host))
           (gascity-remote-connection-locked-p name))
      (gascity-store--pump-later host 0.1))
     (t
      (dolist (lane '(action read))
        (let (job)
          (while (and (> (gascity-store--capacity host lane) 0)
                      (setq job (gascity-store--pop host lane)))
            (setf (gascity-store--host-primed host) t)
            (gascity-store--start job))))))))

(defun gascity-store--enqueue (job)
  "Queue JOB on its host and lane, then pump; virtual jobs start at once."
  (if (eq (gascity-store--job-lane job) 'virtual)
      (gascity-store--start job)
    (let ((host (gascity-store--job-host job)))
      (if (eq (gascity-store--job-lane job) 'action)
          (setf (gascity-store--host-actions host)
                (append (gascity-store--host-actions host) (list job)))
        (setf (gascity-store--host-reads host)
              (append (gascity-store--host-reads host) (list job))))
      (gascity-store--pump host))))

(defun gascity-store--adjust-running (job delta)
  "Add DELTA to the running count of JOB's host lane (not for virtual)."
  (let ((host (gascity-store--job-host job)))
    (pcase (gascity-store--job-lane job)
      ('action (cl-incf (gascity-store--host-running-actions host) delta))
      ('read (cl-incf (gascity-store--host-running-reads host) delta)))))

(defun gascity-store--start (job)
  "Start JOB: count its slot, arm its deadline, run its start function.
The start function receives a FINISH closure; its first call wins
\(the deadline, a sentinel, or a synchronous launch failure), frees the
slot at once, and hands the result to `gascity-store--complete' —
deferred for a remote host."
  (gascity-store--adjust-running job 1)
  (let* ((finish
          (lambda (result)
            (if (gascity-store--job-done job)
                ;; A second answer of the same read: only a good payload
                ;; after a good first answer counts (newest data wins);
                ;; the killed process's errback after a deadline, or
                ;; anything after a failure, is dropped.
                (when (and (eq (car result) :ok)
                           (eq (car (gascity-store--job-result job)) :ok)
                           (gascity-store--job-entry job))
                  (gascity-store--after
                   (gascity-store--job-host job)
                   (lambda () (gascity-store--complete-read job result))))
              (setf (gascity-store--job-done job) t
                    (gascity-store--job-result job) result)
              (when (timerp (gascity-store--job-timer job))
                (cancel-timer (gascity-store--job-timer job)))
              (gascity-store--adjust-running job -1)
              (gascity-store--after
               (gascity-store--job-host job)
               (lambda () (gascity-store--complete job result)))))))
    (when (and (numberp gascity-remote-async-timeout)
               (> gascity-remote-async-timeout 0)
               (not (eq (gascity-store--job-lane job) 'virtual)))
      (setf (gascity-store--job-timer job)
            (run-at-time gascity-remote-async-timeout nil
                         (lambda ()
                           (let ((proc (gascity-store--job-process job)))
                             (funcall finish (list :timeout gascity-remote-async-timeout))
                             (when (process-live-p proc)
                               (ignore-errors (delete-process proc))))))))
    (let ((proc (condition-case err
                    (let ((default-directory (gascity-store--job-dir job)))
                      (funcall (gascity-store--job-start job) finish))
                  (error
                   (funcall finish (list :error (error-message-string err)))
                   nil))))
      (when (processp proc)
        (setf (gascity-store--job-process job) proc)))))

;;; Host state

(defun gascity-store--offline-error-p (host message)
  "Return non-nil when MESSAGE on remote HOST means the host is unreachable."
  (and (not (string-empty-p (gascity-store--host-name host)))
       (stringp message)
       (string-match-p gascity-store-offline-regexp message)))

(defun gascity-store--set-state (host state &optional reason)
  "Set HOST's STATE with REASON; run the hook and notify on a change."
  (unless (eq (gascity-store--host-state host) state)
    (setf (gascity-store--host-state host) state
          (gascity-store--host-reason host) reason)
    (run-hook-with-args 'gascity-store-host-state-functions
                        (gascity-store--host-name host) state reason)
    (let ((name (gascity-store--host-name host)))
      (maphash (lambda (_key entry)
                 (when (equal (gascity-store--dir-host
                               (gascity-store-entry-dir entry))
                              name)
                   (gascity-store--notify entry)))
               gascity-store--entries))))

(defun gascity-store--go-offline (host reason)
  "Flip HOST offline for REASON and schedule the next reconnect probe."
  (when (timerp (gascity-store--host-retry-timer host))
    (cancel-timer (gascity-store--host-retry-timer host)))
  (let* ((steps gascity-store-offline-backoff)
         (n (gascity-store--host-backoff host))
         (delay (or (nth n steps) (car (last steps)) 60)))
    (setf (gascity-store--host-backoff host) (1+ n)
          (gascity-store--host-retry-timer host)
          (run-at-time delay nil
                       (lambda ()
                         (setf (gascity-store--host-retry-timer host) nil)
                         (gascity-store--probe host)))))
  (when (fboundp 'gascity--log)
    (gascity--log 'error "Host %s offline: %s"
                  (gascity-store--host-name host) reason))
  (gascity-store--set-state host 'offline reason))

(defun gascity-store--probe (host)
  "Let HOST run one job as a reconnect probe; online when nothing queued."
  (if (or (gascity-store--host-reads host) (gascity-store--host-actions host))
      (progn (gascity-store--set-state host 'probing
                                       (gascity-store--host-reason host))
             (gascity-store--pump host t))
    (gascity-store--go-online host)))

(defun gascity-store--go-online (host)
  "Mark HOST reachable again: reset the backoff and resume its queues."
  (when (timerp (gascity-store--host-retry-timer host))
    (cancel-timer (gascity-store--host-retry-timer host)))
  (setf (gascity-store--host-retry-timer host) nil
        (gascity-store--host-backoff host) 0)
  (unless (eq (gascity-store--host-state host) 'online)
    (gascity-store--set-state host 'online nil)
    (gascity-store--pump host)))

(defun gascity-store-reconnect (&optional dir)
  "Retry DIR's offline host now (default `default-directory').
The manual `g' path: skips the remaining backoff delay."
  (let ((host (gascity-store--host
               (gascity-store--dir-host (gascity-store--dir dir)))))
    (when (eq (gascity-store--host-state host) 'offline)
      (when (timerp (gascity-store--host-retry-timer host))
        (cancel-timer (gascity-store--host-retry-timer host)))
      (setf (gascity-store--host-retry-timer host) nil)
      (gascity-store--probe host))))

;;; Completion

(defun gascity-store--complete (job result)
  "Settle JOB with RESULT and start whatever its host can run next.
RESULT is (:ok DATA), (:error MESSAGE), (:timeout SECONDS) or, for an
action, the plist of `gascity-reader-run-async'."
  (let ((host (gascity-store--job-host job)))
    (if (eq (gascity-store--job-lane job) 'action)
        (gascity-store--complete-action job result)
      (gascity-store--complete-read job result))
    (gascity-store--pump host)))

(defun gascity-store--complete-read (job result)
  "Settle read JOB with RESULT: update its entry, waiters, subscribers."
  (let* ((entry (gascity-store--job-entry job))
         (host (gascity-store--job-host job))
         ;; A late answer of a superseded job (another read of the
         ;; entry is in flight) updates the payload but leaves that
         ;; read, and the waiters it will answer, alone.
         (own (memq (gascity-store-entry-job entry) (list job nil)))
         (waiters (and own (gascity-store-entry-waiters entry))))
    (when own
      (setf (gascity-store-entry-job entry) nil
            (gascity-store-entry-waiters entry) nil))
    (pcase (car result)
      (:ok
       (setf (gascity-store-entry-data entry) (cadr result)
             (gascity-store-entry-has-data entry) t
             (gascity-store-entry-error entry) nil
             (gascity-store-entry-timed-out entry) nil
             (gascity-store-entry-stale entry) nil
             (gascity-store-entry-fetched-at entry) (float-time))
       (puthash (gascity-store-entry-dir entry) t gascity-store--good-dirs)
       (unless (eq (gascity-store--job-lane job) 'virtual)
         (gascity-store--go-online host))
       (dolist (w (reverse waiters))
         (when (car w) (gascity-store--safe-call (car w) (cadr result))))
       (gascity-store--notify entry))
      (:error
       (let ((msg (cadr result)))
         (if (and own
                  (not (eq (gascity-store--job-lane job) 'virtual))
                  (gascity-store--offline-error-p host msg))
             ;; Connection-level: the read is not wrong, the host is
             ;; gone.  Re-queue it at the head (waiters kept) and pause
             ;; the host instead of erroring the section.
             (let ((retry (gascity-store--make-job
                           :lane 'read :host host
                           :dir (gascity-store--job-dir job)
                           :start (gascity-store--job-start job)
                           :entry entry
                           :buffers (gascity-store--job-buffers job))))
               (setf (gascity-store-entry-job entry) retry
                     (gascity-store-entry-waiters entry) waiters)
               (push retry (gascity-store--host-reads host))
               (gascity-store--go-offline host msg))
           (when (eq (gascity-store--host-state host) 'probing)
             (gascity-store--go-online host))
           (setf (gascity-store-entry-error entry) msg
                 (gascity-store-entry-timed-out entry) nil)
           (dolist (w (reverse waiters))
             (when (cdr w) (gascity-store--safe-call (cdr w) msg)))
           (gascity-store--notify entry))))
      (:timeout
       (let ((msg (format "gc %s timed out after %ss (killed)"
                          (mapconcat (lambda (a) (format "%s" a))
                                     (gascity-store-entry-args entry) " ")
                          (cadr result))))
         (when (eq (gascity-store--host-state host) 'probing)
           (gascity-store--go-offline host msg))
         (setf (gascity-store-entry-error entry) msg
               (gascity-store-entry-timed-out entry) t)
         (dolist (w (reverse waiters))
           (when (cdr w) (gascity-store--safe-call (cdr w) msg)))
         (gascity-store--notify entry))))))

;;; Reads

(defvar gascity-store-loader-force nil
  "Non-nil while a composite loader runs for a forced refresh.
A `:loader' (see `gascity-store-fetch') captures it when it starts and
passes it as `:force' to the store reads it fans out to, so an explicit
refresh of the composite re-reads its parts instead of answering from
their TTL.")

(defun gascity-store--read-start (entry &optional force)
  "Return the start function of a read job for ENTRY.
FORCE is bound as `gascity-store-loader-force' around a composite
loader."
  (let ((args (gascity-store-entry-args entry))
        (lines (gascity-store-entry-lines entry))
        (loader (gascity-store-entry-loader entry))
        (dir (gascity-store-entry-dir entry)))
    (lambda (finish)
      (let ((ok (lambda (data) (funcall finish (list :ok data))))
            (err (lambda (msg) (funcall finish (list :error msg)))))
        (cond
         (loader (let ((gascity-store-loader-force force))
                   (funcall loader ok err))
                 nil)
         (t
          (let ((gascity-reader-skip-dir-probe
                 (or gascity-reader-skip-dir-probe
                     (gethash dir gascity-store--good-dirs))))
            (if lines
                (gascity-reader-read-async args ok err :lines t)
              (gascity-reader-read-async args ok err)))))))))

(cl-defun gascity-store--request (entry &key force max-age buffer)
  "Make sure ENTRY is fresh: join its read in flight or schedule one.
FORCE re-reads even a fresh entry (joining one in flight all the
same); MAX-AGE overrides the TTL; BUFFER is the requesting buffer
\(visible buffers are served first).  Returns non-nil when a read is
in flight afterwards."
  (let ((job (gascity-store-entry-job entry)))
    (cond
     (job
      (when (and buffer (not (memq buffer (gascity-store--job-buffers job))))
        (push buffer (gascity-store--job-buffers job)))
      t)
     ((and (not force) (gascity-store--fresh-p entry max-age)) nil)
     (t
      (let* ((dir (gascity-store-entry-dir entry))
             (job (gascity-store--make-job
                   :lane (if (gascity-store-entry-loader entry) 'virtual 'read)
                   :host (gascity-store--host (gascity-store--dir-host dir))
                   :dir dir
                   :start (gascity-store--read-start entry force)
                   :entry entry
                   :buffers (and buffer (list buffer)))))
        (setf (gascity-store-entry-job entry) job)
        (gascity-store--enqueue job)
        (and (gascity-store-entry-job entry) t))))))

(cl-defun gascity-store-request (args &key dir lines loader force max-age buffer)
  "Refresh the ARGS entry read in DIR as needed, without a callback.
Keys as for `gascity-store-fetch'.  Returns non-nil when a read is in
flight afterwards."
  (gascity-store--request
   (gascity-store--entry (gascity-store--dir dir) args lines loader)
   :force force :max-age max-age :buffer (or buffer (current-buffer))))

(cl-defun gascity-store-fetch (args callback &optional errback
                                    &key dir lines loader force max-age buffer)
  "Deliver the payload of gc ARGS to CALLBACK once, through the store.
The drop-in replacement for `gascity-reader-read-async' (same
positional arguments and `:lines'): a fresh entry answers at once from
the store, a read in flight is joined, otherwise one is scheduled on
the host's read lane.  CALLBACK receives the payload; ERRBACK, when
non-nil, the failure text (a timeout included).  A read that fails
because the host is unreachable is not reported: it waits, queued,
for the host to come back.

DIR (default `default-directory') is where gc runs.  LINES reads JSON
Lines as `gascity-reader-read-async' does.  LOADER, a function of
\(RESOLVE REJECT), replaces the gc read by a composite computed from
other store reads — ARGS then only names the entry (its first token
still gives its kind).  FORCE re-reads even a fresh entry; MAX-AGE
overrides its TTL.  BUFFER (default the current buffer) is the
requester, for priority.  Returns nil — there is no process to kill:
the read is shared."
  (let* ((entry (gascity-store--entry (gascity-store--dir dir) args lines loader)))
    (if (and (not force) (not (gascity-store-entry-job entry))
             (gascity-store--fresh-p entry max-age))
        (funcall callback (gascity-store-entry-data entry))
      (setf (gascity-store-entry-waiters entry)
            (cons (cons callback errback) (gascity-store-entry-waiters entry)))
      (gascity-store--request entry :force force :max-age max-age
                              :buffer (or buffer (current-buffer))))
    nil))

;;; vui hook

(defun gascity-store--vui-notifier (instance buffer)
  "Return a subscriber re-rendering vui INSTANCE's root in BUFFER."
  (lambda (_snapshot)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when-let* ((root (vui--find-root instance)))
          (vui--rerender-instance root))))))

(defun gascity-store-use (args &rest keys)
  "Read gc ARGS through the store from inside a vui component.
The replacement for a `vui-use-async' over `gascity-reader-read-async':
call it unconditionally, in order, like any hook.  Returns the
`gascity-store-snapshot' plist — (:status :data :error) as
`vui-use-async' does, where :status stays `ready' with the last good
payload while a refresh is pending or after a failure, so a consumer
never unmounts on refresh — plus the store flags (:pending :timed-out
:offline :stale :fetched-at).  The component re-renders whenever the
entry changes, whoever caused it.

ARGS nil means \"nothing to read\" (a conditional load): the hook then
returns (:status ready :data DEFAULT) without touching the store.

KEYS: :tick — a refresh counter (the view's `refresh-tick'); a change
re-reads (joining a read already in flight, so several views
refreshing together cost one process).  :default — the data returned
for a nil ARGS.  :lines, :loader and :dir as for `gascity-store-fetch'."
  (let* ((instance vui--current-instance)
         (buffer (current-buffer))
         (tick (plist-get keys :tick))
         (entry (and args
                     (gascity-store--entry
                      (gascity-store--dir (plist-get keys :dir))
                      args (plist-get keys :lines) (plist-get keys :loader))))
         (key (and entry (gascity-store-entry-key entry)))
         (ref (vui-use-ref nil)))
    (vui-use-effect ()
      (lambda ()
        (gascity-store-unsubscribe (plist-get (car ref) :sub))
        (setcar ref nil)))
    (unless (bound-and-true-p vui--measuring-p)
      (let ((state (car ref)))
        (cond
         ((not (equal (plist-get state :key) key))
          (gascity-store-unsubscribe (plist-get state :sub))
          (setcar ref (list :key key :tick tick
                            :sub (and entry
                                      (gascity-store--subscribe-entry
                                       entry
                                       (gascity-store--vui-notifier instance buffer)
                                       buffer))))
          (when entry (gascity-store--request entry :buffer buffer)))
         ((not (equal (plist-get state :tick) tick))
          (setcar ref (plist-put state :tick tick))
          (when entry
            (gascity-store--request entry :force t :buffer buffer))))))
    (if entry
        (gascity-store-snapshot entry)
      (list :status 'ready :data (plist-get keys :default) :error nil))))

;;; Invalidation

(defconst gascity-store-event-routes
  '(("session." session status agent rig)
    ("agent." session status agent rig)
    ("bead." bd convoy)
    ("mail." mail)
    ("order." order events)
    ("convoy." convoy bd))
  "Read kinds each gc event type prefix invalidates (dashboard-v3 §8.2).")

(defconst gascity-store-action-routes
  '((session "session.") (runtime "session.") (rig "session." "bead.")
    (mail "mail.") (sling "bead." "session." "convoy.")
    (order "order." "bead.") (reload "session.") (bd "bead.")
    (convoy "convoy."))
  "Event prefixes a completed action of each argv kind stands for.
Mapped through `gascity-store-event-routes' when no live stream does
the invalidation (§8.5 \"Refresh\").")

(cl-defun gascity-store-invalidate (&key dir kind prefix (refetch t))
  "Mark matching store entries stale; refetch those somebody watches.
DIR restricts to entries read in DIR or below it (a city root covers
its rig repos); KIND is a kind symbol or list of them; PREFIX an argv
prefix list.  Omitted criteria match everything.  With REFETCH (the
default) an entry with live subscribers is re-read at once and they
re-render; the others refetch on their next request.  Returns the
number of entries matched.  The entry point of the event router
\(§8.2)."
  (let ((dir (and dir (gascity-store--dir dir)))
        (kinds (if (listp kind) kind (list kind)))
        (n 0))
    (maphash
     (lambda (_key entry)
       (when (and (or (null dir)
                      (string-prefix-p dir (gascity-store-entry-dir entry)))
                  (or (null kind) (memq (gascity-store-entry-kind entry) kinds))
                  (or (null prefix)
                      (equal prefix (seq-take (gascity-store-entry-args entry)
                                              (length prefix)))))
         (cl-incf n)
         (setf (gascity-store-entry-stale entry) t)
         (when (and refetch
                    (cl-some (lambda (sub)
                               (let ((b (gascity-store--sub-buffer sub)))
                                 (or (null b) (buffer-live-p b))))
                             (gascity-store-entry-subscribers entry)))
           (gascity-store--request entry :force t))))
     gascity-store--entries)
    n))

(defun gascity-store-invalidate-event (type &optional dir)
  "Invalidate the kinds gc event TYPE routes to, under DIR.
TYPE is an event type string (\"session.woke\"); the routing table is
`gascity-store-event-routes'.  Returns the number of entries matched."
  (let ((kinds (cl-loop for (prefix . ks) in gascity-store-event-routes
                        when (string-prefix-p prefix type) append ks)))
    (if kinds (gascity-store-invalidate :dir dir :kind (delete-dups kinds)) 0)))

(defun gascity-store--invalidate-for-action (args dir)
  "Invalidate what a completed action with gc ARGS in DIR touched."
  (unless (and gascity-store-live-p-function
               (funcall gascity-store-live-p-function dir))
    (let ((prefixes (alist-get (gascity-store-kind args) gascity-store-action-routes)))
      (dolist (p prefixes)
        (gascity-store-invalidate-event p dir))
      (gascity-store-invalidate :dir dir :kind 'events))))

;;; Actions

(defun gascity-store-log-buffer-name (dir)
  "Return the action log buffer name for the city at DIR.
\"*gascity-log: CITY*\", CITY the directory's base name, plus \"@HOST\"
for a remote DIR — computed from the name alone, no I/O."
  (let* ((local (file-local-name (directory-file-name dir)))
         (city (file-name-nondirectory local))
         (host (file-remote-p dir 'host)))
    (format "*gascity-log: %s%s*" city (if host (concat "@" host) ""))))

(defun gascity-store-log (dir format-string &rest args)
  "Append FORMAT-STRING with ARGS, time-stamped, to DIR's action log buffer."
  (with-current-buffer (get-buffer-create (gascity-store-log-buffer-name dir))
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format-time-string "%F %T ")
              (apply #'format format-string args)
              "\n"))))

(defun gascity-store--target-key (dir target)
  "Return the serialization key of TARGET on DIR's host."
  (cons (gascity-store--dir-host dir) target))

(defun gascity-store-action-pending-p (target &optional dir)
  "Return non-nil while an action on TARGET is outstanding on DIR's host.
DIR defaults to `default-directory'.  Pure; views render `…' on it."
  (and target
       (gethash (gascity-store--target-key (gascity-store--dir dir) target)
                gascity-store--targets)
       t))

(defun gascity-store-pending-targets (&optional dir)
  "Return the targets with outstanding actions on DIR's host."
  (let ((host (gascity-store--dir-host (gascity-store--dir dir)))
        (targets nil))
    (maphash (lambda (key jobs)
               (when (and jobs (equal (car key) host))
                 (push (cdr key) targets)))
             gascity-store--targets)
    targets))

(defun gascity-store--first-line (text)
  "Return the first non-blank line of TEXT, trimmed, or nil."
  (and (stringp text)
       (car (split-string (string-trim text) "\n" t "[ \t]+"))))

(defun gascity-store--complete-action (job result)
  "Settle action JOB with RESULT: echo, log, invalidate, run callbacks."
  (let* ((dir (gascity-store--job-dir job))
         (args (gascity-store--job-args job))
         (target (gascity-store--job-target job))
         (tkey (gascity-store--target-key dir target))
         (cmd (mapconcat #'identity args " "))
         (timeout (eq (car result) :timeout))
         (code (and (not timeout) (plist-get result :exit-code)))
         (stdout (and (not timeout) (plist-get result :stdout)))
         (stderr (and (not timeout) (plist-get result :stderr))))
    ;; Serialization: release this target, start its next call.
    (let ((rest (delq job (gethash tkey gascity-store--targets))))
      (if rest
          (progn (puthash tkey rest gascity-store--targets)
                 (gascity-store--enqueue (car rest)))
        (remhash tkey gascity-store--targets)
        (run-hook-with-args 'gascity-store-pending-functions target dir nil)))
    (cond
     ((eql code 0)
      (let ((payload (if (gascity-store--job-json job)
                         (condition-case nil
                             (gascity-reader-parse-json stdout)
                           (gascity-json-parse-error stdout))
                       stdout)))
        (when (gascity-store--job-invalidate job)
          (gascity-store--invalidate-for-action args dir))
        (if (gascity-store--job-on-success job)
            (gascity-store--safe-call (gascity-store--job-on-success job) payload)
          (when (gascity-store--job-echo job)
            (message "%s" (or (gascity-store--job-label job)
                              (format "gc %s: done" cmd)))))))
     (t
      (let* ((msg (cond
                   (timeout (format "gc %s timed out after %ss (killed)"
                                    cmd (cadr result)))
                   (t (format "gc %s failed: %s"
                              cmd
                              (or (gascity-store--first-line stderr)
                                  (gascity-reader--error-envelope-message stdout)
                                  (gascity-store--first-line stdout)
                                  (format "exit %s" code)))))))
        (gascity-store-log dir "%s\n  exit: %s\n  stderr:\n%s\n  stdout:\n%s"
                           msg (if timeout "timeout" code)
                           (or stderr "") (or stdout ""))
        (when (and (null code) (not timeout))
          (let ((host (gascity-store--job-host job)))
            (when (gascity-store--offline-error-p host stderr)
              (gascity-store--go-offline host stderr))))
        (if (gascity-store--job-on-error job)
            (gascity-store--safe-call (gascity-store--job-on-error job) msg)
          (message "%s" msg)))))))

(cl-defun gascity-store-action (args &key dir target label json
                                     on-success on-error (echo t)
                                     (invalidate t))
  "Start the mutating gc call ARGS in DIR and return at once (D9, §8.5).
ARGS is the gc argv (no executable); it runs on the action lane of
DIR's host (default `default-directory'), behind any earlier call on
the same TARGET (an object id string: session, rig, message, bead)
and under the `gascity-remote-async-timeout' deadline.  Until the call
returns TARGET is pending (`gascity-store-action-pending-p').

On success: ON-SUCCESS is called with the result (the decoded JSON
when JSON is non-nil, else stdout); without it LABEL (\"Suspended
foo\") is echoed when ECHO is non-nil.  The read kinds the call touched
are invalidated (`gascity-store-action-routes'), unless a live
stream covers DIR or INVALIDATE is nil (a read-only call such as
peek).  On failure the first stderr line is echoed — or passed to
ON-ERROR instead — and the whole stderr appended to the city's
`*gascity-log: CITY*' buffer.  Callbacks run outside any sentinel and
never signal.  Returns nil."
  (let* ((dir (gascity-store--dir dir))
         (host (gascity-store--host (gascity-store--dir-host dir)))
         (tkey (gascity-store--target-key dir (or target (list 'anonymous (random)))))
         (job (gascity-store--make-job
               :lane 'action :host host :dir dir
               :buffers (list (current-buffer))
               :target (or target (cdr tkey)) :args args :label label :json json
               :on-success on-success :on-error on-error :echo echo
               :invalidate invalidate)))
    (setf (gascity-store--job-start job)
          (lambda (finish) (gascity-reader-run-async args finish)))
    (let ((queue (gethash tkey gascity-store--targets)))
      (puthash tkey (append queue (list job)) gascity-store--targets)
      (unless queue
        (run-hook-with-args 'gascity-store-pending-functions
                            (gascity-store--job-target job) dir t)
        (gascity-store--enqueue job)))
    nil))

;;; Reset

(defun gascity-store-clear ()
  "Forget every payload and scheduler state; kill running store processes.
Subscribers are dropped too.  For tests and a hard reset."
  (maphash (lambda (_name host)
             (dolist (timer (list (gascity-store--host-retry-timer host)
                                  (gascity-store--host-pump-timer host)))
               (when (timerp timer) (cancel-timer timer))))
           gascity-store--hosts)
  (maphash (lambda (_key entry)
             (when-let* ((job (gascity-store-entry-job entry)))
               (setf (gascity-store--job-done job) t)
               (when (timerp (gascity-store--job-timer job))
                 (cancel-timer (gascity-store--job-timer job)))
               (when (process-live-p (gascity-store--job-process job))
                 (delete-process (gascity-store--job-process job)))))
           gascity-store--entries)
  (clrhash gascity-store--entries)
  (clrhash gascity-store--hosts)
  (clrhash gascity-store--good-dirs)
  (clrhash gascity-store--targets))

(provide 'gascity-store)
;;; gascity-store.el ends here
