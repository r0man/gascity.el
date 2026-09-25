;;; gascity-live.el --- One live gc event stream per city -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Live refresh (dashboard-v3 §8.2, §8.3 R4).  Instead of every view
;; polling gc on a timer, each city runs ONE `gc events --follow'
;; stream while at least one of its views is open.  Events are parsed
;; as they arrive, debounced, and routed by type prefix to the views
;; (and store entries) they invalidate.
;;
;; Transport:
;;
;; - Local city: a plain local `make-process' of gc.
;; - Remote city over an ssh-family TRAMP method: a LOCAL pipe process
;;   running ssh (`gascity-remote-ssh-pipe-argv': -T, BatchMode, one
;;   quoted command string, gascity's ControlMaster), so the stream
;;   never holds a tramp-sh channel and its output is byte-exact JSONL.
;;   It is built with no TRAMP round trip, so (re)starts never block.
;; - Any other remote method (docker, sudo, multi-hop): no stream; a
;;   `gc events --watch --after SEQ' poll every `gascity-live-poll-interval'
;;   seconds through the store (`gascity-store-fetch').
;;
;; stderr of a stream goes to the `*gascity-live: CITY*' buffer; its
;; last line becomes the header reason.  Every event carries `seq'; the
;; stream remembers the last one and reconnects with `--after SEQ'
;; (gap-free resume, city scope), then asks for one full refresh.
;; Reconnects back off along `gascity-live-backoff'; `g' in a view
;; (`gascity-live-reconnect') retries at once.
;;
;; Public API for views:
;;
;; - `gascity-live-attach' / `gascity-live-detach': a view buffer joins
;;   its city's stream (starting it) and leaves it (the last one out
;;   stops it; `kill-buffer' detaches automatically).  A view may pass
;;   a REFRESH function and the KINDS it depends on.
;; - `gascity-live-subscribe' / `gascity-live-unsubscribe': raw events,
;;   undebounced, for the Events view.
;; - `gascity-live-status' (plist) and `gascity-live-header-string'
;;   (the header-line fragment); both pure, safe at redisplay.
;; - `gascity-live-invalidate-functions': abnormal hook run with
;;   (ROOT KINDS TYPES) per debounced batch; the store is invalidated
;;   first (`gascity-store-invalidate-event'), so store-backed views
;;   repaint on their own.
;; - `gascity-live-toggle' (`W'), `gascity-live-reconnect' (`g').

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'gascity-custom)
(require 'gascity-remote)
(require 'gascity-reader)
(require 'gascity-store)

(declare-function tramp-dissect-file-name "tramp")
(declare-function tramp-file-name-hop "tramp")
(declare-function tramp-file-name-localname "tramp")
(declare-function gascity-context-city-root-cached "gascity-context" (&optional dir))

;;; Options

(defgroup gascity-live nil
  "Live refresh from the gc event stream."
  :group 'gascity
  :prefix "gascity-live-")

(defcustom gascity-live-enabled t
  "When non-nil, gascity views keep their city's event stream running.
`gascity-live-toggle' (`W' in a view) flips it for one city."
  :type 'boolean
  :group 'gascity-live)

(defcustom gascity-live-in-batch nil
  "When non-nil, streams also start in a batch (noninteractive) Emacs.
Off by default so tests and batch scripts that open views never spawn
a long-lived `gc events --follow'."
  :type 'boolean
  :group 'gascity-live)

(defcustom gascity-live-debounce 2.5
  "Seconds events are collected before their views are invalidated.
The first event of a batch arms the timer; later ones join the batch,
so a view is at most this late even under a constant event trickle."
  :type 'number
  :group 'gascity-live)

(defcustom gascity-live-backoff '(2 5 15 60)
  "Seconds to wait before each reconnect attempt; the last one repeats.
The sequence restarts once a stream stayed up for
`gascity-live-stable-after' seconds."
  :type '(repeat number)
  :group 'gascity-live)

(defcustom gascity-live-stable-after 15
  "Seconds a stream must stay up before its backoff resets."
  :type 'number
  :group 'gascity-live)

(defcustom gascity-live-confirm-after 3
  "Seconds a (re)started stream must stay up before it counts as live.
gc prints nothing until an event arrives, so a fresh `gc events
--follow' cannot prove it connected; one that fails (ssh, the
supervisor) exits within this.  Its first event confirms it at once."
  :type 'number
  :group 'gascity)

(defcustom gascity-live-poll-interval 30
  "Seconds between event polls for a city without a stream.
Used for remote methods a plain ssh cannot reach (docker, sudo,
multi-hop)."
  :type 'number
  :group 'gascity-live)

(defvar gascity-live-invalidate-functions nil
  "Abnormal hook run once per debounced event batch.
Called with (ROOT KINDS TYPES): ROOT the city root, KINDS the store
read kinds the batch touched, per `gascity-store-event-routes' (the
symbol `all' after a resume, which calls for a full refresh), TYPES the
event types in the batch.")

(defvar gascity-live-state-functions nil
  "Abnormal hook run when a city's stream changes state.
Called with (ROOT STATE REASON).  Views redraw their header here.")

;;; Stream state

(cl-defstruct (gascity-live--stream
               (:constructor gascity-live--stream-create)
               (:copier nil))
  "One city's event stream."
  root host name
  process (partial "") seq
  (state 'off) reason
  (attempt 0) retry-timer retry-at
  (enabled t) views subscribers
  debounce-timer pending
  stderr-buffer
  mode poll-timer poll-busy
  started stopping resume confirm-timer)

(defvar-local gascity-live--refresh nil
  "Function refreshing this view on an invalidation, or nil.")

(defvar-local gascity-live--kinds nil
  "View kinds this view depends on; nil means every kind.")

(defvar-local gascity-live--root nil
  "City root this view is attached to.")

(defvar gascity-live--streams (make-hash-table :test 'equal)
  "City root → `gascity-live--stream'.")

(defun gascity-live-key (dir)
  "Return the canonical stream-table key of directory DIR.
`gascity-remote-canonical-dir': \"/mock::/c/\" and \"/mock:HOST:/c/\"
are one city.  Pure."
  (gascity-remote-canonical-dir dir))

(defun gascity-live--root (&optional dir)
  "Return the city root for DIR (default `default-directory'), as a key.
Canonical (`gascity-live-key'), so every spelling of a city is one.
The memoized city walk only (`gascity-context-city-root-cached'); view
buffers are pinned to their root, so DIR itself is the answer there."
  ;; Memo only (never the walk, which is TRAMP I/O on a remote city):
  ;; a view buffer's `default-directory' IS its pinned city root.
  (let ((dir (or dir default-directory)))
    (gascity-live-key (or (gascity-context-city-root-cached dir) dir))))

(defun gascity-live--find (&optional dir)
  "Return the stream covering DIR (default `default-directory'), or nil.
Pure string matching on known roots: no file-name handler I/O, safe
in header lines and redisplay."
  (let ((dir (gascity-live-key (or dir default-directory)))
        (best nil))
    (maphash (lambda (root stream)
               (when (and (string-prefix-p root dir)
                          (or (null best)
                              (> (length root)
                                 (length (gascity-live--stream-root best)))))
                 (setq best stream)))
             gascity-live--streams)
    best))

(defun gascity-live--city-name (root)
  "Return the display name of the city at ROOT, with @HOST when remote."
  (let ((name (file-name-nondirectory
               (directory-file-name (file-local-name root))))
        (host (file-remote-p root 'host)))
    (if host (format "%s@%s" name host) name)))

(defun gascity-live--allowed-p ()
  "Return non-nil when streams may start in this Emacs."
  (and gascity-live-enabled
       (or gascity-live-in-batch (not noninteractive))))

(defun gascity-live--set-state (stream state &optional reason)
  "Set STREAM's STATE and REASON; run `gascity-live-state-functions'."
  (unless (and (eq state (gascity-live--stream-state stream))
               (equal reason (gascity-live--stream-reason stream)))
    (setf (gascity-live--stream-state stream) state
          (gascity-live--stream-reason stream) reason)
    (run-hook-with-args 'gascity-live-state-functions
                        (gascity-live--stream-root stream) state reason)
    (dolist (buf (gascity-live--stream-views stream))
      (when (buffer-live-p buf)
        (with-current-buffer buf (force-mode-line-update))))))

;;; Parsing

(defun gascity-live-parse-chunk (partial chunk)
  "Split PARTIAL + CHUNK into complete JSONL lines.
Return (EVENTS . REST): EVENTS the decoded objects (alists) of every
complete line in order, REST the trailing incomplete line to keep for
the next chunk.  Lines that are not JSON objects (ssh banners, stray
text) are skipped."
  (let* ((text (concat partial chunk))
         (end (string-match-p "\n[^\n]*\\'" text))
         events)
    (if (null end)
        (cons nil text)
      (dolist (line (split-string (substring text 0 end) "\n" t))
        (when (string-match-p "\\`[[:space:]]*{" line)
          (condition-case nil
              (push (json-parse-string line :object-type 'alist
                                       :array-type 'list
                                       :null-object nil :false-object nil)
                    events)
            (json-error nil))))
      (cons (nreverse events) (substring text (1+ end))))))

(defun gascity-live--event-type (event)
  "Return EVENT's type string, or nil."
  (let ((type (alist-get 'type event)))
    (and (stringp type) type)))

(defun gascity-live-route (type)
  "Return the store read kinds event TYPE invalidates.
The one routing table is the store's, `gascity-store-event-routes'."
  (and type
       (cl-loop for (prefix . kinds) in gascity-store-event-routes
                when (string-prefix-p prefix type) append kinds)))

;;; Event delivery

(defun gascity-live--deliver (stream events)
  "Hand EVENTS to STREAM's subscribers and queue their invalidation."
  (dolist (event events)
    (let ((seq (alist-get 'seq event)))
      (when (and (integerp seq)
                 (> seq (or (gascity-live--stream-seq stream) -1)))
        (setf (gascity-live--stream-seq stream) seq)))
    (dolist (sub (gascity-live--stream-subscribers stream))
      (let ((fn (car sub)) (buf (cdr sub)))
        (when (or (null buf) (buffer-live-p buf))
          (condition-case err
              (if buf
                  (with-current-buffer buf (funcall fn event))
                (funcall fn event))
            (error (message "gascity-live: subscriber error: %s"
                            (error-message-string err)))))))
    (when-let* ((type (gascity-live--event-type event)))
      (gascity-live--queue stream type)
      ;; A mail message is a bead: its closing (archive elsewhere, gc's
      ;; mail sweeper) or update comes as `bead.*', which alone routes
      ;; to the bead reads — the inbox and `mail count' re-read too.
      (when (gascity-live--message-bead-event-p event)
        (gascity-live--queue stream "mail.bead")))))

(defun gascity-live--message-bead-event-p (event)
  "Return non-nil when EVENT is a `bead.*' event about a mail message."
  (and (string-prefix-p "bead." (or (gascity-live--event-type event) ""))
       (let* ((payload (alist-get 'payload event))
              (bead (and (listp payload) (alist-get 'bead payload))))
         (and (listp bead) (equal (alist-get 'issue_type bead) "message")))))

(defun gascity-live--queue (stream type)
  "Add event TYPE to STREAM's debounce batch, arming the timer."
  (push type (gascity-live--stream-pending stream))
  (unless (gascity-live--stream-debounce-timer stream)
    (setf (gascity-live--stream-debounce-timer stream)
          (run-at-time gascity-live-debounce nil
                       #'gascity-live--flush stream))))

(defun gascity-live--flush (stream)
  "Invalidate what STREAM's pending batch touched; empty the batch."
  (let* ((types (delete-dups (nreverse (gascity-live--stream-pending stream))))
         (all (memq :all types))
         (types (delq :all types))
         (kinds (if all 'all
                  (delete-dups (cl-mapcan (lambda (ty)
                                            (copy-sequence (gascity-live-route ty)))
                                          types)))))
    (setf (gascity-live--stream-pending stream) nil
          (gascity-live--stream-debounce-timer stream) nil)
    (when (or all types)
      (gascity-live--invalidate (gascity-live--stream-root stream)
                                kinds types))))

(defun gascity-live--store-dirs (root)
  "Return ROOT and the distinct directories of its attached views."
  (let ((dirs (list root)))
    (when-let* ((stream (gethash root gascity-live--streams)))
      (dolist (buf (gascity-live--stream-views stream))
        (when (buffer-live-p buf)
          (cl-pushnew (file-name-as-directory
                       (buffer-local-value 'default-directory buf))
                      dirs :test #'equal))))
    (nreverse dirs)))

(defun gascity-live--invalidate (root kinds types)
  "Route one debounced batch for the city at ROOT.
KINDS are view kinds (or `all'), TYPES the event types.  Calls the
store's event invalidation when the store is loaded, runs
`gascity-live-invalidate-functions', then each attached view's
REFRESH whose kinds intersect KINDS.  Views reading through the store
repaint from the store's own refetch; REFRESH is for the others."
  ;; The store matches entry directories as spelled (a view's
  ;; \"/mock::/c/\" is not the canonical \"/mock:host:/c/\"): invalidate
  ;; under the stream root and under each attached view's directory —
  ;; once per directory for the whole batch (the union of its kinds):
  ;; per type, an entry several types touch would be re-read again
  ;; each time its previous read had already finished.
  (dolist (dir (gascity-live--store-dirs root))
    (if (eq kinds 'all)
        (gascity-store-invalidate :dir dir)
      (gascity-store-invalidate-event types dir)))
  (run-hook-with-args 'gascity-live-invalidate-functions root kinds types)
  (when-let* ((stream (gethash root gascity-live--streams)))
    (dolist (buf (gascity-live--stream-views stream))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (let ((fn gascity-live--refresh)
                (want gascity-live--kinds))
            (when (and fn
                       (or (eq kinds 'all) (null want)
                           (cl-intersection want kinds)))
              (condition-case err
                  (funcall fn)
                (error (message "gascity-live: refresh error: %s"
                                (error-message-string err)))))))))))

;;; Process

(defun gascity-live--ssh-p (root)
  "Return non-nil when ROOT's host is reachable with a plain ssh."
  (and (file-remote-p root)
       (member (file-remote-p root 'method) beads-remote-ssh-methods)
       (not (ignore-errors
              (tramp-file-name-hop (tramp-dissect-file-name root))))))

(defun gascity-live--args (stream)
  "Return the gc argv tokens (after the program) for STREAM."
  (append (list "events" "--follow")
          (when-let* ((seq (gascity-live--stream-seq stream)))
            (list "--after" (number-to-string seq)))
          (list "--city" (file-local-name (gascity-live--stream-root stream)))))

(defconst gascity-live--exit-reporter gascity-remote-exit-reporter
  "The host-side wrapper of a remote stream (`gascity-remote-exit-reporter').")

(defun gascity-live-command (stream)
  "Return the local argv that runs STREAM's `gc events --follow'.
Remotely a no-pty ssh built by `gascity-remote-ssh-pipe-argv' without
host resolution (:resolve nil): `gascity-executable' as configured,
the pure PATH fragment, gascity's own ssh ControlMaster — no TRAMP
round trip, so starting or restarting a stream never blocks, not even
from a timer."
  (let ((root (gascity-live--stream-root stream)))
    (if (file-remote-p root)
        (let* ((default-directory root)
               (executable (with-connection-local-variables gascity-executable)))
          ;; gc runs under a host shell that reports its exit on stderr,
          ;; so a gc that died (killed, supervisor gone) is told apart
          ;; from a dropped connection, where ssh exits 255 without it;
          ;; its watcher kills gc when the stream stops (stdin EOF).
          (gascity-remote-ssh-stream-argv root executable
                                          (gascity-live--args stream)))
      (cons gascity-executable (gascity-live--args stream)))))

(defun gascity-live--stderr-buffer (stream)
  "Return STREAM's `*gascity-live: CITY*' stderr buffer."
  (let ((buf (gascity-live--stream-stderr-buffer stream)))
    (unless (buffer-live-p buf)
      (setq buf (get-buffer-create
                 (format "*gascity-live: %s*" (gascity-live--stream-name stream))))
      (with-current-buffer buf
        (setq-local default-directory temporary-file-directory))
      (setf (gascity-live--stream-stderr-buffer stream) buf))
    buf))

(defun gascity-live--stderr-lines (stream start)
  "Return the non-empty stderr lines STREAM wrote after START."
  (let ((buf (gascity-live--stream-stderr-buffer stream)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (split-string (buffer-substring-no-properties
                       (min start (point-max)) (point-max))
                      "\n" t "[ \t\r]+")))))

(defun gascity-live--classify-gc (line)
  "Return (STATE . REASON) for a gc exit whose last stderr line is LINE."
  (if (and line (string-match-p "request failed\\|dial tcp\\|connect: connection refused\\|supervisor" line))
      (cons 'supervisor-down line)
    (cons 'reconnecting line)))

(defun gascity-live--classify (stream status lines)
  "Return (STATE . REASON) for STREAM's exit with STATUS and stderr LINES.
Locally the exit is gc's own.  Remotely the host shell reports gc's
exit as a last \"gascity-live-exit N\" line
\(`gascity-live--exit-reporter'); without it the connection itself
dropped, which is `offline'."
  (let ((last (car (last lines))))
    (if (not (file-remote-p (gascity-live--stream-root stream)))
        (gascity-live--classify-gc last)
      (if (and last (string-match "\\`gascity-live-exit \\([0-9]+\\)\\'" last))
          (let ((code (string-to-number (match-string 1 last)))
                (msg (car (last lines 2))))
            (gascity-live--classify-gc
             (if (eq msg last)
                 (format "gc exited %d" code)
               msg)))
        (cons 'offline (or last (format "connection lost (ssh exit %s)" status)))))))

(defun gascity-live--start (stream)
  "Start STREAM's process, or its poll timer for a non-ssh remote city."
  (let ((root (gascity-live--stream-root stream)))
    (setf (gascity-live--stream-stopping stream) nil)
    (gascity-live--cancel-retry stream)
    (if (and (file-remote-p root) (not (gascity-live--ssh-p root)))
        (gascity-live--start-poll stream)
      (gascity-live--spawn stream))))

(defun gascity-live--spawn (stream)
  "Spawn STREAM's `gc events --follow' as a local pipe process."
  (let* ((root (gascity-live--stream-root stream))
         (stderr (gascity-live--stderr-buffer stream))
         (mark (with-current-buffer stderr (point-max)))
         ;; Our own stderr pipe: the default one's sentinel would append
         ;; "Process … stderr finished" to the buffer, which then reads
         ;; as the stream's last stderr line.
         (stderr-pipe (make-pipe-process
                       :name (format "gascity-live %s stderr"
                                     (gascity-live--stream-name stream))
                       :buffer stderr
                       :noquery t
                       :sentinel #'ignore))
         (default-directory (if (file-remote-p root)
                                temporary-file-directory
                              root))
         resumed proc)
    (setf (gascity-live--stream-mode stream) 'stream
          (gascity-live--stream-partial stream) ""
          (gascity-live--stream-started stream) (float-time))
    (setq resumed (gascity-live--stream-resume stream))
    (when (gascity-live--stream-resume stream)
      ;; A resumed stream replays what it missed; ask once for a full
      ;; refresh of whatever went stale meanwhile.
      (setf (gascity-live--stream-resume stream) nil)
      (gascity-live--queue stream :all))
    (condition-case err
        (setq proc
              (make-process
               :name (format "gascity-live %s" (gascity-live--stream-name stream))
               :command (gascity-live-command stream)
               :connection-type 'pipe
               :coding 'utf-8-unix
               :noquery t
               :stderr stderr-pipe
               :file-handler nil
               :filter (lambda (_proc chunk)
                         (gascity-live--filter stream chunk))
               :sentinel (lambda (proc _event)
                           (unless (process-live-p proc)
                             ;; Collect the last stderr bytes first.
                             (when (process-live-p stderr-pipe)
                               (accept-process-output stderr-pipe 0.05 nil t))
                             (delete-process stderr-pipe)
                             (gascity-live--exited stream proc mark)))))
      (error
       (setq proc nil)
       (delete-process stderr-pipe)
       (with-current-buffer stderr
         (goto-char (point-max))
         (insert (error-message-string err) "\n"))
       (gascity-live--set-state stream 'reconnecting (error-message-string err))
       (gascity-live--schedule-retry stream)))
    (when proc
      (setf (gascity-live--stream-process stream) proc)
      ;; Not live yet: the header says (re)connecting until the stream
      ;; delivers or has stayed up `gascity-live-confirm-after' seconds.
      (gascity-live--set-state stream (if resumed 'reconnecting 'connecting) nil)
      (gascity-live--arm-confirm stream proc))
    proc))

(defun gascity-live--cancel-confirm (stream)
  "Cancel STREAM's pending live confirmation."
  (when (timerp (gascity-live--stream-confirm-timer stream))
    (cancel-timer (gascity-live--stream-confirm-timer stream)))
  (setf (gascity-live--stream-confirm-timer stream) nil))

(defun gascity-live--arm-confirm (stream proc)
  "Mark STREAM live once PROC has stayed up `gascity-live-confirm-after'."
  (gascity-live--cancel-confirm stream)
  (setf (gascity-live--stream-confirm-timer stream)
        (run-at-time gascity-live-confirm-after nil
                     (lambda ()
                       (setf (gascity-live--stream-confirm-timer stream) nil)
                       (when (and (eq proc (gascity-live--stream-process stream))
                                  (process-live-p proc))
                         (gascity-live--set-state stream 'live nil))))))

(defun gascity-live--filter (stream chunk)
  "Feed CHUNK of STREAM's stdout to the parser and deliver the events."
  (let ((parsed (gascity-live-parse-chunk
                 (gascity-live--stream-partial stream) chunk)))
    (setf (gascity-live--stream-partial stream) (cdr parsed))
    (when (car parsed)
      (unless (eq (gascity-live--stream-state stream) 'live)
        (gascity-live--cancel-confirm stream)
        (gascity-live--set-state stream 'live nil))
      (gascity-live--deliver stream (car parsed)))))

(defun gascity-live--exited (stream proc mark)
  "Handle the exit of STREAM's process PROC; stderr began at MARK."
  (when (eq proc (gascity-live--stream-process stream))
    (setf (gascity-live--stream-process stream) nil)
    (gascity-live--cancel-confirm stream)
    (unless (gascity-live--stream-stopping stream)
      (let* ((status (process-exit-status proc))
             (class (gascity-live--classify
                     stream status (gascity-live--stderr-lines stream mark)))
             (uptime (- (float-time) (or (gascity-live--stream-started stream) 0))))
        (when (>= uptime gascity-live-stable-after)
          (setf (gascity-live--stream-attempt stream) 0))
        (setf (gascity-live--stream-resume stream)
              (and (gascity-live--stream-seq stream) t))
        (gascity-live--set-state stream (car class) (cdr class))
        (gascity-live--schedule-retry stream)))))

;;; Reconnect

(defun gascity-live-backoff-delay (attempt)
  "Return the reconnect delay for ATTEMPT (0-based), per `gascity-live-backoff'."
  (let ((seq gascity-live-backoff))
    (or (nth attempt seq) (car (last seq)) 60)))

(defun gascity-live--cancel-retry (stream)
  "Cancel STREAM's pending reconnect."
  (when (timerp (gascity-live--stream-retry-timer stream))
    (cancel-timer (gascity-live--stream-retry-timer stream)))
  (setf (gascity-live--stream-retry-timer stream) nil
        (gascity-live--stream-retry-at stream) nil))

(defun gascity-live--schedule-retry (stream)
  "Schedule STREAM's next reconnect along the backoff sequence."
  (gascity-live--cancel-retry stream)
  (let* ((attempt (gascity-live--stream-attempt stream))
         (delay (gascity-live-backoff-delay attempt)))
    (setf (gascity-live--stream-attempt stream) (1+ attempt)
          (gascity-live--stream-retry-at stream) (+ (float-time) delay)
          (gascity-live--stream-retry-timer stream)
          (run-at-time delay nil
                       (lambda ()
                         (setf (gascity-live--stream-retry-timer stream) nil)
                         (when (and (gascity-live--stream-views stream)
                                    (gascity-live--stream-enabled stream))
                           ;; A timer must never make TRAMP open a
                           ;; connection; the stream is plain ssh.
                           (let ((non-essential t))
                             (gascity-live--start stream))))))))

(defun gascity-live--stop (stream)
  "Stop STREAM's process, poll and timers; leave it `off'."
  (setf (gascity-live--stream-stopping stream) t)
  (gascity-live--cancel-retry stream)
  (gascity-live--cancel-confirm stream)
  (dolist (timer (list (gascity-live--stream-debounce-timer stream)
                       (gascity-live--stream-poll-timer stream)))
    (when (timerp timer) (cancel-timer timer)))
  (setf (gascity-live--stream-debounce-timer stream) nil
        (gascity-live--stream-poll-timer stream) nil
        (gascity-live--stream-pending stream) nil)
  (let ((proc (gascity-live--stream-process stream)))
    (setf (gascity-live--stream-process stream) nil)
    (when (processp proc)
      (delete-process proc)))
  (gascity-live--set-state stream 'off nil))

;;; Polling (remote methods a plain ssh cannot reach)

(defun gascity-live--start-poll (stream)
  "Run STREAM as a periodic `gc events --watch --after' poll (the store)."
  (setf (gascity-live--stream-mode stream) 'poll)
  (gascity-live--set-state stream 'polling nil)
  (unless (timerp (gascity-live--stream-poll-timer stream))
    (setf (gascity-live--stream-poll-timer stream)
          (run-at-time 0 gascity-live-poll-interval
                       #'gascity-live--poll stream))))

(defcustom gascity-live-poll-watch "2s"
  "How long each poll waits for a first event when none is pending.
A poll is `gc events --watch --after SEQ --timeout' this: gc replays
every event after SEQ and exits at once, or waits this long for one."
  :type 'string
  :group 'gascity-live)

(defcustom gascity-live-poll-bootstrap "60s"
  "The `gc events --since' window of a poll that knows no seq yet.
It only learns the head seq; must cover `gascity-live-poll-interval'."
  :type 'string
  :group 'gascity-live)

(defconst gascity-live--poll-entry '("events" "--live-poll")
  "Store key of the polls: one stable entry for every poll of a city.
The argv changes with the seq, so it is the entry's loader that runs
it (`gascity-live--poll'); keyed by argv, every seq would leave its
own payload in the store.")

(defun gascity-live--poll-argv (stream)
  "Return the gc argv of STREAM's next poll.
With a seq: `events --watch --after SEQ --timeout W', gap-free by seq
\(gc 1.4.2 rejects --after without --watch or --follow).  Without one:
`events --since B' to learn the head."
  (if-let* ((seq (gascity-live--stream-seq stream)))
      (list "events" "--watch" "--after" (number-to-string seq)
            "--timeout" gascity-live-poll-watch)
    (list "events" "--since" gascity-live-poll-bootstrap)))

(defun gascity-live--poll-result (stream events)
  "Hand STREAM the EVENTS of a poll.
A poll that knew no seq only learns the head (the past is not news);
otherwise every event past the last seq is delivered."
  (let ((last (gascity-live--stream-seq stream)))
    (if (null last)
        (let ((seqs (delq nil (mapcar (lambda (e)
                                        (let ((s (alist-get 'seq e)))
                                          (and (integerp s) s)))
                                      events))))
          (when seqs
            (setf (gascity-live--stream-seq stream) (apply #'max seqs))))
      (gascity-live--deliver
       stream (seq-filter (lambda (e)
                            (let ((s (alist-get 'seq e)))
                              (and (integerp s) (> s last))))
                          events)))))

(defun gascity-live--poll (stream)
  "Fetch the events STREAM missed, through the store.
`gascity-store-fetch' with :force on the stable entry
`gascity-live--poll-entry', whose loader runs `gascity-live--poll-argv':
the host's read cap, deadline and offline pause apply, and a poll never
overlaps its own previous one.  Once a poll has succeeded the reader's
directory probe is skipped, as the store skips it for a known-good
directory."
  (unless (gascity-live--stream-poll-busy stream)
    (let ((root (gascity-live--stream-root stream))
          (argv (gascity-live--poll-argv stream))
          (known-good (eq (gascity-live--stream-state stream) 'polling)))
      (setf (gascity-live--stream-poll-busy stream) t)
      (condition-case err
          (gascity-store-fetch
           gascity-live--poll-entry
           (lambda (events)
             (setf (gascity-live--stream-poll-busy stream) nil)
             (gascity-live--poll-result stream events)
             (gascity-live--set-state stream 'polling nil))
           (lambda (msg)
             (setf (gascity-live--stream-poll-busy stream) nil)
             (gascity-live--set-state
              stream
              (if (string-match-p "request failed\\|dial tcp" msg)
                  'supervisor-down 'offline)
              msg))
           :dir root :force t
           :loader (lambda (resolve reject)
                     (let ((default-directory root)
                           (gascity-reader-skip-dir-probe
                            (or gascity-reader-skip-dir-probe known-good)))
                       (gascity-reader-read-async
                        argv (lambda (result) (funcall resolve (car result)))
                        reject :lines t))))
        (error
         (setf (gascity-live--stream-poll-busy stream) nil)
         (gascity-live--set-state stream 'offline (error-message-string err)))))))

;;; View attachment

(cl-defun gascity-live-attach (&optional buffer &key refresh kinds)
  "Attach BUFFER (default current) to its city's event stream.
The city is the root of BUFFER's `default-directory'.  The first view
of a city starts its stream (when `gascity-live-enabled' and not in
batch unless `gascity-live-in-batch').  REFRESH, when non-nil, is
called with BUFFER current after a debounced batch touching one of
KINDS (store read kinds, see `gascity-store-event-routes'; nil means
any) or after
a resume.  Killing BUFFER detaches it.  Returns the stream."
  (with-current-buffer (or buffer (current-buffer))
    (let* ((root (gascity-live--root))
           (stream (or (gethash root gascity-live--streams)
                       (puthash root
                                (gascity-live--stream-create
                                 :root root
                                 :host (file-remote-p root 'host)
                                 :name (gascity-live--city-name root))
                                gascity-live--streams))))
      (setq gascity-live--refresh refresh
            gascity-live--kinds kinds
            gascity-live--root root)
      (add-hook 'kill-buffer-hook #'gascity-live-detach nil t)
      (unless (memq (current-buffer) (gascity-live--stream-views stream))
        (push (current-buffer) (gascity-live--stream-views stream)))
      (when (and (gascity-live--allowed-p)
                 (gascity-live--stream-enabled stream)
                 (not (process-live-p (gascity-live--stream-process stream)))
                 (not (gascity-live--stream-retry-timer stream))
                 (not (timerp (gascity-live--stream-poll-timer stream))))
        (gascity-live--start stream))
      stream)))

(defun gascity-live-detach (&optional buffer)
  "Detach BUFFER (default current) from its city's stream.
The last view out stops the stream and forgets the city."
  (with-current-buffer (or buffer (current-buffer))
    (when-let* ((root gascity-live--root)
                (stream (gethash root gascity-live--streams)))
      (setf (gascity-live--stream-views stream)
            (delq (current-buffer) (gascity-live--stream-views stream)))
      (setf (gascity-live--stream-subscribers stream)
            (cl-remove-if (lambda (sub) (eq (cdr sub) (current-buffer)))
                          (gascity-live--stream-subscribers stream)))
      (setq gascity-live--root nil)
      (unless (cl-some #'buffer-live-p (gascity-live--stream-views stream))
        (gascity-live--stop stream)
        (let ((stderr (gascity-live--stream-stderr-buffer stream)))
          (when (buffer-live-p stderr) (kill-buffer stderr)))
        (remhash root gascity-live--streams)
        ;; The city is gone from the stream table: let the lighter know.
        (run-hook-with-args 'gascity-live-state-functions root 'gone nil)))))

(defun gascity-live-subscribe (fn &optional buffer)
  "Call FN with every raw event of BUFFER's city, as it arrives.
BUFFER (default current) must be an attached view; FN runs with it
current and stops when it is killed.  Returns a handle for
`gascity-live-unsubscribe'.  Events are alists (`type', `seq',
`subject', `actor', `ts', `payload', ...)."
  (with-current-buffer (or buffer (current-buffer))
    (let ((stream (or (and gascity-live--root
                           (gethash gascity-live--root gascity-live--streams))
                      (gascity-live-attach))))
      (let ((sub (cons fn (current-buffer))))
        (push sub (gascity-live--stream-subscribers stream))
        (cons stream sub)))))

(defun gascity-live-unsubscribe (handle)
  "Remove the subscription HANDLE from `gascity-live-subscribe'."
  (when (consp handle)
    (let ((stream (car handle)))
      (setf (gascity-live--stream-subscribers stream)
            (delq (cdr handle) (gascity-live--stream-subscribers stream))))))

;;; State for header lines

(defun gascity-live-status (&optional dir)
  "Return the live state of DIR's city as a plist, or nil.
Keys: :state (`live', `polling', `off', `connecting', `reconnecting',
`supervisor-down', `offline'), :reason (stderr line or nil),
:retry-in (seconds until the next reconnect, or nil), :seq, :host.
Pure; safe at redisplay."
  (when-let* ((stream (gascity-live--find dir)))
    (list :state (if (gascity-live--stream-enabled stream)
                     (gascity-live--stream-state stream)
                   'off)
          :reason (gascity-live--stream-reason stream)
          :retry-in (when-let* ((at (gascity-live--stream-retry-at stream)))
                      (max 0 (ceiling (- at (float-time)))))
          :seq (gascity-live--stream-seq stream)
          :host (gascity-live--stream-host stream))))

(defun gascity-live-header-string (&optional dir)
  "Return the header-line fragment for DIR's city stream, or nil.
One of `● live', `● live (polling)', `○ live off', `○ live: connecting',
`○ live: reconnecting (Ns)', `○ live: supervisor down',
`○ offline @host'.  Pure; safe at redisplay."
  (when-let* ((status (gascity-live-status dir)))
    (pcase (plist-get status :state)
      ('live (propertize "● live" 'face 'success))
      ('connecting (propertize "○ live: connecting" 'face 'shadow))
      ('polling (propertize "● live (polling)" 'face 'success))
      ('off (propertize "○ live off" 'face 'shadow))
      ('supervisor-down
       (propertize "○ live: supervisor down" 'face 'warning
                   'help-echo (plist-get status :reason)))
      ('offline
       (propertize (format "○ offline @%s" (or (plist-get status :host)
                                               "localhost"))
                   'face 'error 'help-echo (plist-get status :reason)))
      (_ (propertize
          (if-let* ((n (plist-get status :retry-in)))
              (format "○ live: reconnecting (%ds)" n)
            "○ live: reconnecting")
          'face 'warning 'help-echo (plist-get status :reason))))))

(defun gascity-live-cities ()
  "Return (ROOT . STATUS) for every city with a stream, sorted by name.
STATUS is the `gascity-live-status' plist plus :name.  Pure: the
stream table only, safe at redisplay (the mode-line lighter)."
  (let (out)
    (maphash (lambda (root stream)
               (push (cons root (append (list :name (gascity-live--stream-name stream))
                                        (gascity-live-status root)))
                     out))
             gascity-live--streams)
    (sort out (lambda (a b) (string< (format "%s" (plist-get (cdr a) :name))
                                     (format "%s" (plist-get (cdr b) :name)))))))

(defun gascity-live-active-p (&optional dir)
  "Return non-nil when a running live stream covers DIR.
The store's `gascity-store-live-p-function': while it answers non-nil,
completed actions leave invalidation to the stream."
  (when-let* ((stream (gascity-live--find dir)))
    (and (gascity-live--stream-enabled stream)
         (memq (gascity-live--stream-state stream) '(live polling))
         t)))

;;; Commands

(defun gascity-live--running-p (stream)
  "Return non-nil when STREAM has a process or poll going.
A stream still confirming its connection (`connecting', or
`reconnecting' right after a respawn) is running: restarting it
would orphan its process."
  (or (process-live-p (gascity-live--stream-process stream))
      (timerp (gascity-live--stream-poll-timer stream))))

(defun gascity-live-reconnect (&optional dir)
  "Restart DIR's city stream now if it is not running.
The `g' path: a view's manual refresh calls this, so a stream waiting
out its backoff (or offline) retries at once.  A no-op while its
process runs (`gascity-live--running-p')."
  (interactive)
  (when-let* ((stream (gascity-live--find dir)))
    (when (and (gascity-live--stream-enabled stream)
               (gascity-live--allowed-p)
               (not (gascity-live--running-p stream)))
      (setf (gascity-live--stream-attempt stream) 0)
      (gascity-live--start stream)))
  ;; An offline host's reads are paused too; `g' retries them now.
  (when (gascity-store-offline-p dir)
    (gascity-store-reconnect dir)))

(defvar-local gascity-live-city-function nil
  "Function of no arguments returning the city directory `W' acts on, or nil.
For views that are not about one city (Cities: the city at point).
Nil means the buffer's own city.")

(defun gascity-live-toggle (&optional dir)
  "Turn DIR's city stream off, or back on (`W' in every gascity view).
DIR defaults to the buffer's city — or, in a view listing several
cities, the one `gascity-live-city-function' names.  A city with no
open view has no stream: that says so instead of starting one for a
buffer that is not its view."
  (interactive)
  (let* ((dir (or dir (and gascity-live-city-function
                           (or (funcall gascity-live-city-function)
                               (user-error "No city at point")))))
         (stream (or (gascity-live--find dir)
                     (if gascity-live-city-function
                         (user-error "No live stream for that city (open one of its views)")
                       (gascity-live-attach)))))
    (if (gascity-live--stream-enabled stream)
        (progn
          (setf (gascity-live--stream-enabled stream) nil)
          (gascity-live--stop stream)
          (message "Live refresh off for %s" (gascity-live--stream-name stream)))
      (setf (gascity-live--stream-enabled stream) t
            (gascity-live--stream-attempt stream) 0)
      (when (gascity-live--allowed-p)
        (gascity-live--start stream))
      (message "Live refresh on for %s" (gascity-live--stream-name stream)))))

(defun gascity-live-stop-all ()
  "Stop every city stream (e.g. before unloading gascity)."
  (interactive)
  (maphash (lambda (_root stream) (gascity-live--stop stream))
           gascity-live--streams)
  (clrhash gascity-live--streams))

(defun gascity-live--host-state-changed (host state _reason)
  "Reconnect the streams on HOST at once when the store sees it online again.
Runs from `gascity-store-host-state-functions': a store read that
succeeds after an outage is news the stream's backoff should not wait
out."
  (when (eq state 'online)
    (maphash (lambda (root stream)
               (when (and (equal (or (gascity-remote-prefix root) "")
                                 (or (gascity-remote-prefix host) host))
                          (gascity-live--stream-enabled stream)
                          (gascity-live--stream-views stream)
                          (not (gascity-live--running-p stream)))
                 (setf (gascity-live--stream-attempt stream) 0)
                 (run-at-time 0 nil #'gascity-live--start stream)))
             gascity-live--streams)))

(add-hook 'gascity-store-host-state-functions #'gascity-live--host-state-changed)

(setq gascity-store-live-p-function #'gascity-live-active-p)

(provide 'gascity-live)
;;; gascity-live.el ends here
