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
;;   `gc events --after SEQ' poll every `gascity-live-poll-interval'
;;   seconds through the async reader.
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
(declare-function gascity-context-city-root "gascity-context" (&optional dir))

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

(defcustom gascity-live-poll-interval 30
  "Seconds between event polls for a city without a stream.
Used for remote methods a plain ssh cannot reach (docker, sudo,
multi-hop)."
  :type 'number
  :group 'gascity-live)

(defconst gascity-live-routes
  '(("session." agents)
    ("agent." agents)
    ("bead." work runs)
    ("mail." mail)
    ("order." activity)
    ("convoy." work runs))
  "View kinds each gc event type prefix invalidates (§8.2).
Every event also reaches the raw subscribers (the Events view appends
without a re-read).  The store keeps its own read-kind table
\(`gascity-store-event-routes').")

(defvar gascity-live-invalidate-functions nil
  "Abnormal hook run once per debounced event batch.
Called with (ROOT KINDS TYPES): ROOT the city root, KINDS the view
kinds from `gascity-live-routes' (the symbol `all' after a resume,
which calls for a full refresh), TYPES the event types in the batch.")

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
  started stopping resume)

(defvar-local gascity-live--refresh nil
  "Function refreshing this view on an invalidation, or nil.")

(defvar-local gascity-live--kinds nil
  "View kinds this view depends on; nil means every kind.")

(defvar-local gascity-live--root nil
  "City root this view is attached to.")

(defvar gascity-live--streams (make-hash-table :test 'equal)
  "City root → `gascity-live--stream'.")

(defun gascity-live--root (&optional dir)
  "Return the city root for DIR (default `default-directory').
The memoized city walk; view buffers are pinned to their root, so
this is a cache hit for them."
  (let ((dir (or dir default-directory)))
    (or (ignore-errors (gascity-context-city-root dir))
        (file-name-as-directory dir))))

(defun gascity-live--find (&optional dir)
  "Return the stream covering DIR (default `default-directory'), or nil.
Pure string matching on known roots: no file-name handler I/O, safe
in header lines and redisplay."
  (let ((dir (file-name-as-directory (or dir default-directory)))
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
  "Return the view kinds event TYPE invalidates (`gascity-live-routes')."
  (and type
       (cl-loop for (prefix . kinds) in gascity-live-routes
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
      (gascity-live--queue stream type))))

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

(defun gascity-live--invalidate (root kinds types)
  "Route one debounced batch for the city at ROOT.
KINDS are view kinds (or `all'), TYPES the event types.  Calls the
store's event invalidation when the store is loaded, runs
`gascity-live-invalidate-functions', then each attached view's
REFRESH whose kinds intersect KINDS.  Views reading through the store
repaint from the store's own refetch; REFRESH is for the others."
  (if (eq kinds 'all)
      (gascity-store-invalidate :dir root)
    (dolist (type types)
      (gascity-store-invalidate-event type root)))
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

(defconst gascity-live--exit-reporter
  (concat "exec 3<&0; "
          "\"$0\" \"$@\" </dev/null & p=$!; "
          "{ cat >/dev/null; kill $p; } <&3 >/dev/null 2>&1 & w=$!; "
          "wait $p; s=$?; kill $w 2>/dev/null; "
          "echo \"gascity-live-exit $s\" >&2")
  "Host-side sh script running gc ($0 and $@) for a remote stream.
It reports gc's exit status as a last \"gascity-live-exit N\" stderr
line, so a gc that died is told apart from a dropped connection (ssh
exits 255 without it).  A watcher kills gc as soon as the session's
stdin reaches EOF: with no pty there is no SIGHUP, and a stopped
stream's gc would otherwise linger until its next write fails.")

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
          (gascity-remote-ssh-pipe-argv
           root
           ;; gc runs under a host shell that reports its exit on stderr,
           ;; so a gc that died (killed, supervisor gone) is told apart
           ;; from a dropped connection, where ssh exits 255 without it.
           (append (list "/bin/sh" "-c" gascity-live--exit-reporter executable)
                   (gascity-live--args stream))
           :resolve nil))
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
         proc)
    (setf (gascity-live--stream-mode stream) 'stream
          (gascity-live--stream-partial stream) ""
          (gascity-live--stream-started stream) (float-time))
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
      (gascity-live--set-state stream 'live nil))
    proc))

(defun gascity-live--filter (stream chunk)
  "Feed CHUNK of STREAM's stdout to the parser and deliver the events."
  (let ((parsed (gascity-live-parse-chunk
                 (gascity-live--stream-partial stream) chunk)))
    (setf (gascity-live--stream-partial stream) (cdr parsed))
    (when (car parsed)
      (unless (eq (gascity-live--stream-state stream) 'live)
        (gascity-live--set-state stream 'live nil))
      (gascity-live--deliver stream (car parsed)))))

(defun gascity-live--exited (stream proc mark)
  "Handle the exit of STREAM's process PROC; stderr began at MARK."
  (when (eq proc (gascity-live--stream-process stream))
    (setf (gascity-live--stream-process stream) nil)
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
  "Run STREAM as a `gc events --after SEQ' poll."
  (setf (gascity-live--stream-mode stream) 'poll)
  (gascity-live--set-state stream 'polling nil)
  (unless (timerp (gascity-live--stream-poll-timer stream))
    (setf (gascity-live--stream-poll-timer stream)
          (run-at-time 0 gascity-live-poll-interval
                       #'gascity-live--poll stream))))

(defun gascity-live--poll (stream)
  "Fetch the events STREAM missed since its last seq."
  (unless (gascity-live--stream-poll-busy stream)
    (let ((default-directory (gascity-live--stream-root stream))
          (seq (gascity-live--stream-seq stream))
          (non-essential t))
      (setf (gascity-live--stream-poll-busy stream) t)
      (condition-case err
          (gascity-reader-read-async
           (if seq
               (list "events" "--after" (number-to-string seq))
             (list "events" "--since" "1m"))
           (lambda (result)
             (setf (gascity-live--stream-poll-busy stream) nil)
             (let ((events (car result)))
               (if seq
                   (gascity-live--deliver stream events)
                 ;; Bootstrap: only learn the head, the past is not news.
                 (dolist (e events)
                   (let ((s (alist-get 'seq e)))
                     (when (and (integerp s)
                                (> s (or (gascity-live--stream-seq stream) -1)))
                       (setf (gascity-live--stream-seq stream) s))))))
             (gascity-live--set-state stream 'polling nil))
           (lambda (msg)
             (setf (gascity-live--stream-poll-busy stream) nil)
             (gascity-live--set-state
              stream
              (if (string-match-p "request failed\\|dial tcp" msg)
                  'supervisor-down 'offline)
              msg))
           :lines t)
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
KINDS (a list of `gascity-live-routes' kinds; nil means any) or after
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
        (remhash root gascity-live--streams)))))

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
Keys: :state (`live', `polling', `off', `reconnecting',
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
One of `● live', `● live (polling)', `○ live off',
`○ live: reconnecting (Ns)', `○ live: supervisor down',
`○ offline @host'.  Pure; safe at redisplay."
  (when-let* ((status (gascity-live-status dir)))
    (pcase (plist-get status :state)
      ('live (propertize "● live" 'face 'success))
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

(defun gascity-live-active-p (&optional dir)
  "Return non-nil when a running live stream covers DIR.
The store's `gascity-store-live-p-function': while it answers non-nil,
completed actions leave invalidation to the stream."
  (when-let* ((stream (gascity-live--find dir)))
    (and (gascity-live--stream-enabled stream)
         (memq (gascity-live--stream-state stream) '(live polling))
         t)))

;;; Commands

(defun gascity-live-reconnect (&optional dir)
  "Restart DIR's city stream now if it is not running.
The `g' path: a view's manual refresh calls this, so a stream waiting
out its backoff (or offline) retries at once.  A no-op while live."
  (interactive)
  (when-let* ((stream (gascity-live--find dir)))
    (when (and (gascity-live--stream-enabled stream)
               (gascity-live--allowed-p)
               (not (memq (gascity-live--stream-state stream) '(live polling))))
      (setf (gascity-live--stream-attempt stream) 0)
      (gascity-live--start stream))))

(defun gascity-live-toggle (&optional dir)
  "Turn DIR's city stream off, or back on (`W' in gascity views)."
  (interactive)
  (let ((stream (or (gascity-live--find dir) (gascity-live-attach))))
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

(setq gascity-store-live-p-function #'gascity-live-active-p)

(provide 'gascity-live)
;;; gascity-live.el ends here
