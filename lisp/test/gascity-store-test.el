;;; gascity-store-test.el --- ERT for the payload store and scheduler -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 §8.4: the scheduler suite (dedup, per-host cap, TTL,
;; deadline, offline pause/resume, priority), the store's vui hook, the
;; async action lane, remote code paths through the TRAMP mock method,
;; the render guard, and the D9 non-blocking guard over every
;; input-free action verb.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(defconst gascity-test-store--remote "/mock::/tmp/store-city/"
  "A remote-looking city directory; no connection is ever made to it.")

(defmacro gascity-test-store--remote-host (&rest body)
  "Run BODY with the mock method known and remote completions synchronous.
The fake remote host is marked primed, so dispatch is synchronous too."
  (declare (indent 0) (debug t))
  `(progn
     (gascity-test-ensure-mock-method)
     (let ((gascity-store-synchronous-delivery t)
           (tramp-verbose 0))
       (setf (gascity-store--host-primed
              (gascity-store--host (file-remote-p gascity-test-store--remote)))
             t)
       ,@body)))

(defun gascity-test-store--wait (pred &optional seconds)
  "Run timers and process output until PRED is non-nil or SECONDS (2) pass."
  (let ((deadline (+ (float-time) (or seconds 2))))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (funcall pred)))

;;; Payloads, dedup, TTL

(ert-deftest gascity-test-store-dedup-joins-inflight ()
  "Two requests for one argv spawn one read and both get its payload."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/") got)
      (gascity-store-fetch '("status") (lambda (d) (push (list 1 d) got)))
      (gascity-store-fetch '("status" "--json") (lambda (d) (push (list 2 d) got)))
      (should (= (length reads) 1))
      (should (equal (car (car reads)) '("status")))
      (funcall (nth 1 (car reads)) '((ok . t)))
      (should (equal (sort (mapcar #'car got) #'<) '(1 2)))
      (should (equal (cadr (car got)) '((ok . t)))))))

(ert-deftest gascity-test-store-ttl-serves-cache-then-rereads ()
  "A fresh entry answers without a read; past its TTL it is re-read.
The `manual' TTL (doctor) never expires; FORCE always re-reads."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/") got)
      (gascity-store-fetch '("status") #'ignore)
      (funcall (nth 1 (car reads)) 'v1)
      (gascity-store-fetch '("status") (lambda (d) (push d got)))
      (should (= (length reads) 1))
      (should (equal got '(v1)))
      ;; Age the payload past the status TTL (5s).
      (setf (gascity-store-entry-fetched-at
             (gascity-store--entry "/tmp/city/" '("status")))
            (- (float-time) 60))
      (gascity-store-fetch '("status") (lambda (d) (push d got)))
      (should (= (length reads) 2))
      (funcall (nth 1 (car reads)) 'v2)
      (should (equal (car got) 'v2))
      ;; doctor: manual TTL.
      (gascity-store-fetch '("doctor") #'ignore)
      (funcall (nth 1 (car reads)) 'd1)
      (setf (gascity-store-entry-fetched-at
             (gascity-store--entry "/tmp/city/" '("doctor")))
            (- (float-time) 3600))
      (gascity-store-fetch '("doctor") #'ignore)
      (should (= (length reads) 3))
      (gascity-store-fetch '("doctor") #'ignore nil :force t)
      (should (= (length reads) 4)))))

(ert-deftest gascity-test-store-keeps-last-good-data-on-error ()
  "A failed refresh keeps the payload: status stays `ready' with :error."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/") err)
      (gascity-store-fetch '("convoy" "list") #'ignore)
      (funcall (nth 1 (car reads)) 'good)
      (gascity-store-fetch '("convoy" "list") #'ignore (lambda (m) (setq err m))
                           :force t)
      (should (plist-get (gascity-store-get '("convoy" "list")) :pending))
      (funcall (nth 2 (car reads)) "boom")
      (should (equal err "boom"))
      (let ((snap (gascity-store-get '("convoy" "list"))))
        (should (eq (plist-get snap :status) 'ready))
        (should (eq (plist-get snap :data) 'good))
        (should (equal (plist-get snap :error) "boom"))
        (should-not (plist-get snap :pending))))))

(ert-deftest gascity-test-store-invalidate-refetches-watched-entries ()
  "Invalidation re-reads entries with live subscribers; others go stale.
Routing by event type maps `session.' onto the session/status kinds."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/") seen)
      (with-temp-buffer
        (gascity-store-subscribe '("session" "list")
                                 (lambda (snap) (push (plist-get snap :data) seen)))
        (gascity-store-fetch '("session" "list") #'ignore)
        (gascity-store-fetch '("mail" "inbox") #'ignore)
        (funcall (nth 1 (nth 1 reads)) 's1)
        (funcall (nth 1 (nth 0 reads)) 'm1)
        (should (equal seen '(s1)))
        (setq reads nil)
        (should (= (gascity-store-invalidate-event "session.woke" "/tmp/city/") 1))
        (should (equal (mapcar #'car reads) '(("session" "list"))))
        (funcall (nth 1 (car reads)) 's2)
        (should (equal seen '(s2 s1)))
        ;; Unwatched: marked stale, re-read on its next request only.
        (should (= (gascity-store-invalidate :kind 'mail) 1))
        (should (null (cdr reads)))
        (should (plist-get (gascity-store-get '("mail" "inbox")) :stale))
        (gascity-store-fetch '("mail" "inbox") #'ignore)
        (should (equal (car (car reads)) '("mail" "inbox")))))))

;;; Scheduler: per-host cap, priority, deadline, offline

(ert-deftest gascity-test-store-remote-cap-and-fifo ()
  "A remote host runs at most `gascity-remote-max-inflight' reads; local is uncapped."
  (gascity-test-store--remote-host
    (gascity-test-with-store-stubs reads _actions
      (let ((default-directory gascity-test-store--remote)
            (gascity-remote-max-inflight 3))
        (dotimes (i 5)
          (gascity-store-fetch (list "bd" "list" (format "%d" i)) #'ignore))
        (should (= (length reads) 3))
        (should (equal (plist-get (gascity-store-host-status) :reads) 3))
        (should (equal (plist-get (gascity-store-host-status) :queued) 2))
        ;; Finishing one starts the next, in FIFO order.
        (funcall (nth 1 (car (last reads))) 'x)
        (should (= (length reads) 4))
        (should (equal (car (car reads)) '("bd" "list" "3")))
        ;; Local reads are never queued.
        (let ((default-directory "/tmp/city/"))
          (dotimes (i 6)
            (gascity-store-fetch (list "rig" (format "%d" i)) #'ignore)))
        (should (= (length reads) 10))))))

(ert-deftest gascity-test-store-visible-buffer-goes-first ()
  "A queued read requested from a visible buffer jumps the FIFO."
  (gascity-test-store--remote-host
    (gascity-test-with-store-stubs reads _actions
      (let ((default-directory gascity-test-store--remote)
            (gascity-remote-max-inflight 1)
            (hidden (generate-new-buffer " hidden"))
            (shown (generate-new-buffer " shown")))
        (unwind-protect
            (cl-letf (((symbol-function 'get-buffer-window)
                       (lambda (b &rest _) (and (eq b shown) 'window))))
              (with-current-buffer hidden
                (setq default-directory gascity-test-store--remote)
                (gascity-store-fetch '("status") #'ignore)
                (gascity-store-fetch '("mail" "count") #'ignore))
              (with-current-buffer shown
                (setq default-directory gascity-test-store--remote)
                (gascity-store-fetch '("session" "list") #'ignore))
              (should (= (length reads) 1))
              (funcall (nth 1 (car reads)) 'done)
              (should (equal (car (car reads)) '("session" "list"))))
          (kill-buffer hidden)
          (kill-buffer shown))))))

(ert-deftest gascity-test-store-deadline-kills-and-frees-slot ()
  "A read past `gascity-remote-async-timeout' is killed, flagged, and its slot freed."
  (gascity-test-store--remote-host
    (let* ((default-directory gascity-test-store--remote)
           (gascity-remote-max-inflight 1)
           (gascity-remote-async-timeout 0.1)
           (procs nil) (starts 0) err)
      (cl-letf (((symbol-function 'gascity-reader-read-async)
                 (lambda (_args callback &optional _errback &rest _)
                   (cl-incf starts)
                   (if (= starts 1)
                       ;; A local stand-in for the wedged remote gc.
                       (let* ((default-directory temporary-file-directory)
                              (p (make-process :name "gascity-test-sleep"
                                               :command '("sleep" "30")
                                               :noquery t)))
                         (push p procs) p)
                     (funcall callback 'second)
                     nil))))
        (gascity-store-fetch '("status") #'ignore (lambda (m) (setq err m)))
        (gascity-store-fetch '("session" "list") #'ignore)
        (should (= starts 1))
        (should (gascity-test-store--wait (lambda () err)))
        (should (string-match-p "timed out after 0.1s" err))
        (should-not (process-live-p (car procs)))
        (should (plist-get (gascity-store-get '("status")) :timed-out))
        ;; The freed slot ran the queued read.
        (should (= starts 2))
        (should (eq (plist-get (gascity-store-get '("session" "list")) :data)
                    'second))))))

(ert-deftest gascity-test-store-offline-pauses-and-recovers ()
  "A connection failure flips the host offline without erroring the read;
the read is re-queued, a backoff probe runs it again, and success
brings the host back online and answers the waiter."
  (gascity-test-store--remote-host
    (let* ((default-directory gascity-test-store--remote)
           (gascity-store-offline-backoff '(0.05))
           (up nil) (starts 0) got err states)
      (cl-letf (((symbol-function 'gascity-reader-read-async)
                 (lambda (_args callback &optional errback &rest _)
                   (cl-incf starts)
                   (if up (funcall callback 'fresh)
                     (funcall errback
                              "ssh: connect to host h port 22: Connection refused"))
                   nil)))
        (let ((gascity-store-host-state-functions
               (list (lambda (_h state _r) (push state states)))))
          (gascity-store-fetch '("status") (lambda (d) (setq got d))
                               (lambda (m) (setq err m)))
          (should (gascity-store-offline-p))
          (should (plist-get (gascity-store-get '("status")) :offline))
          (should-not err)
          ;; Paused: a second read queues, nothing spawns.
          (gascity-store-fetch '("mail" "count") #'ignore)
          (should (= starts 1))
          (setq up t)
          (should (gascity-test-store--wait (lambda () got)))
          (should (eq got 'fresh))
          (should-not (gascity-store-offline-p))
          (should (eq (plist-get (gascity-store-get '("mail" "count")) :data)
                      'fresh))
          (should (equal (reverse states) '(offline probing online))))))))

(ert-deftest gascity-test-store-local-errors-never-offline ()
  "A local read failure is a plain section error, never an offline host."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/") err)
      (gascity-store-fetch '("status") #'ignore (lambda (m) (setq err m)))
      (funcall (nth 2 (car reads)) "Connection refused")
      (should (equal err "Connection refused"))
      (should-not (gascity-store-offline-p)))))

(ert-deftest gascity-test-store-first-remote-dispatch-is-deferred ()
  "The first read on an unprimed remote host starts from a timer, not inline.
Its synchronous first-contact resolution must not run inside the
command that opened the view (§8.5)."
  (gascity-test-ensure-mock-method)
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory gascity-test-store--remote)
          (tramp-verbose 0))
      (gascity-store-fetch '("status") #'ignore)
      (should (null reads))
      (should (gascity-test-store--wait (lambda () reads)))
      (should (equal (car (car reads)) '("status"))))))

;;; vui hook

(vui-defcomponent gascity-test-store--app ()
  "A one-read component for the hook tests."
  :state ((tick 0))
  :render
  (let ((res (gascity-store-use '("status") :tick tick)))
    (vui-text (format "%s:%S:%s" (plist-get res :status) (plist-get res :data)
                      (if (plist-get res :pending) "pending" "idle")))))

(ert-deftest gascity-test-store-use-renders-and-revalidates ()
  "The hook re-renders on arrival, keeps data while a refresh is pending,
and a refresh tick re-reads once even when the entry is fresh."
  (gascity-test-with-store-stubs reads _actions
    (let ((vui-render-delay nil)
          (default-directory "/tmp/city/"))
      (save-window-excursion
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-test-store--app) "*store-hook*")
              (with-current-buffer "*store-hook*"
                (should (string-match-p "pending:nil:pending" (buffer-string)))
                (funcall (nth 1 (car reads)) 'v1)
                (should (string-match-p "ready:v1:idle" (buffer-string)))
                ;; Refresh: bump the tick.
                (let ((state (vui-instance-state vui--root-instance)))
                  (setf (vui-instance-state vui--root-instance)
                        (plist-put state :tick 1))
                  (vui-flush-sync))
                (should (= (length reads) 2))
                (should (string-match-p "ready:v1:pending" (buffer-string)))
                (funcall (nth 1 (car reads)) 'v2)
                (should (string-match-p "ready:v2:idle" (buffer-string)))
                ;; Another requester's read of the same entry re-renders too.
                (gascity-store-fetch '("status") #'ignore nil :force t)
                (funcall (nth 1 (car reads)) 'v3)
                (should (string-match-p "ready:v3:idle" (buffer-string)))))
          (when (get-buffer "*store-hook*") (kill-buffer "*store-hook*")))))))

(ert-deftest gascity-test-store-render-dispatch-is-deferred ()
  "A read requested from a vui render starts from the scheduler timer,
never inside the render or mount (QA F8 hardening)."
  (gascity-test-with-store-stubs reads _actions
    (let ((vui-render-delay nil)
          (gascity-store-inline-render-dispatch nil)
          (default-directory "/tmp/city/"))
      (save-window-excursion
        (unwind-protect
            (progn
              (vui-mount (vui-component 'gascity-test-store--app) "*store-defer*")
              (should (null reads))
              (should (gascity-test-store--wait (lambda () reads)))
              (should (equal (car (car reads)) '("status"))))
          (when (get-buffer "*store-defer*") (kill-buffer "*store-defer*")))))))

;;; Actions

(ert-deftest gascity-test-store-action-serializes-per-target ()
  "Actions on one target run one at a time; the target is pending until
the last returns; another target runs concurrently."
  (gascity-test-with-store-stubs _reads actions
    (let ((default-directory "/tmp/city/") (msgs nil) pending-log)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (let ((gascity-store-pending-functions
               (list (lambda (target _dir p) (push (cons target p) pending-log)))))
          (gascity-store-action '("session" "suspend" "a") :target "a"
                                :label "Suspended a")
          (gascity-store-action '("session" "wake" "a") :target "a"
                                :label "Woke a")
          (gascity-store-action '("session" "wake" "b") :target "b")
          (should (equal (mapcar #'car actions)
                         '(("session" "wake" "b") ("session" "suspend" "a"))))
          (should (gascity-store-action-pending-p "a"))
          (should (equal (sort (gascity-store-pending-targets) #'string<)
                         '("a" "b")))
          (funcall (nth 1 (nth 1 actions))
                   (list :exit-code 0 :stdout "" :stderr ""))
          (should (equal (car msgs) "Suspended a"))
          (should (equal (car (car actions)) '("session" "wake" "a")))
          (should (gascity-store-action-pending-p "a"))
          (funcall (nth 1 (car actions)) (list :exit-code 0 :stdout "" :stderr ""))
          (should (equal (car msgs) "Woke a"))
          (should-not (gascity-store-action-pending-p "a"))
          (should (equal (assoc "a" pending-log) '("a"))))))))

(ert-deftest gascity-test-store-action-failure-echoes-and-logs ()
  "A failed action echoes its first stderr line and logs the whole stderr."
  (gascity-test-with-store-stubs _reads actions
    (let ((default-directory "/tmp/emacs-city/") msgs)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (gascity-store-action '("session" "kill" "x") :target "x")
        (funcall (nth 1 (car actions))
                 (list :exit-code 1 :stdout ""
                       :stderr "session x not found\nhint: gc session list\n"))
        (should (equal (car msgs) "gc session kill x failed: session x not found"))
        (with-current-buffer "*gascity-log: emacs-city*"
          (should (string-search "hint: gc session list" (buffer-string))))
        (kill-buffer "*gascity-log: emacs-city*")))))

(ert-deftest gascity-test-store-action-success-invalidates-routes ()
  "A completed session action re-reads the watched session reads."
  (gascity-test-with-store-stubs reads actions
    (let ((default-directory "/tmp/city/"))
      (with-temp-buffer
        (gascity-store-subscribe '("session" "list") #'ignore)
        (gascity-store-fetch '("session" "list") #'ignore)
        (funcall (nth 1 (car reads)) 's1)
        (setq reads nil)
        (gascity-store-action '("session" "suspend" "a") :target "a" :echo nil)
        (funcall (nth 1 (car actions)) (list :exit-code 0 :stdout "" :stderr ""))
        (should (member '("session" "list") (mapcar #'car reads)))))))

(ert-deftest gascity-test-store-action-lane-not-behind-reads ()
  "Actions have their own lane: a full read lane never delays them."
  (gascity-test-store--remote-host
    (gascity-test-with-store-stubs reads actions
      (let ((default-directory gascity-test-store--remote)
            (gascity-remote-max-inflight 1))
        (gascity-store-fetch '("status") #'ignore)
        (gascity-store-fetch '("session" "list") #'ignore)
        (should (= (length reads) 1))
        (gascity-store-action '("session" "suspend" "a") :target "a" :echo nil)
        (should (= (length actions) 1))))))

(ert-deftest gascity-test-store-formula-refresh-async-swaps-caches ()
  "The sling menu's `g' re-reads catalog and recipe through the store and
swaps each cache entry only when its read answers."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/")
          (gascity-formula-catalog-cache nil)
          (gascity-formula-recipe-cache nil)
          done)
      (cl-letf (((symbol-function 'gascity-context-scope-key)
                 (lambda (&optional _) "/tmp/city/")))
        (push (cons "/tmp/city/" '(old)) gascity-formula-catalog-cache)
        (gascity-formula-refresh-async "do-work" (lambda () (setq done t)))
        (should (equal (sort (mapcar #'car reads)
                             (lambda (a b) (string< (format "%s" a) (format "%s" b))))
                       '(("formula" "catalog") ("formula" "show" "do-work"))))
        ;; Nothing swapped yet: the menu keeps what it had.
        (should (equal (cdr (assoc "/tmp/city/" gascity-formula-catalog-cache))
                       '(old)))
        (dolist (r reads)
          (funcall (nth 1 r)
                   (if (equal (car r) '("formula" "catalog"))
                       '((formulas . [((name . "do-work"))]))
                     '((name . "do-work")))))
        (should done)
        (should (equal (mapcar #'gascity-formula-catalog-entry-name
                               (cdr (assoc "/tmp/city/" gascity-formula-catalog-cache)))
                       '("do-work")))
        (should (gascity-formula-p
                 (cdr (assoc '("/tmp/city/" . "do-work")
                             gascity-formula-recipe-cache))))))))

;;; Remote code paths over the TRAMP mock method

(ert-deftest gascity-test-store-run-async-over-mock-tramp ()
  "`gascity-reader-run-async' splits stdout/stderr/exit over a real TRAMP
connection (the mock method), with no stderr pipe or remote temp file."
  (gascity-test-with-mock-remote
    (let ((gascity-executable "sh")
          (gascity-reader-city-args-function nil)
          result)
      (gascity-reader-run-async '("-c" "echo out; echo err >&2; exit 3")
                                (lambda (r) (setq result r)))
      (should (gascity-test-store--wait (lambda () result) 20))
      (should (eql (plist-get result :exit-code) 3))
      (should (equal (string-trim (plist-get result :stdout)) "out"))
      (should (equal (string-trim (plist-get result :stderr)) "err")))))

(ert-deftest gascity-test-store-read-and-action-over-mock-tramp ()
  "A store read and a failing store action both complete over the mock
method: the read's payload lands, the action logs its stderr."
  (gascity-test-with-mock-remote
    (let ((gascity-reader-city-args-function nil)
          (gascity-remote-async-timeout 20)
          data msgs)
      ;; The executable binding must outlive the call: the first
      ;; dispatch on a new remote host runs from a timer (§8.5).
      (let ((gascity-executable "echo"))
        (gascity-store-fetch '("{\"a\":1}") (lambda (d) (setq data d)))
        (should (gascity-test-store--wait (lambda () data) 20)))
      (should (equal data '((a . 1))))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
        (let ((gascity-executable "sh"))
          (gascity-store-action '("-c" "echo nope >&2; exit 1") :target "t")
          (should (gascity-test-store--wait
                   (lambda () (not (gascity-store-action-pending-p "t"))) 20))))
      (should (string-match-p "failed: nope" (car msgs)))
      (let ((log (get-buffer (gascity-store-log-buffer-name default-directory))))
        (should log)
        (kill-buffer log)))))

(ert-deftest gascity-test-store-native-json-shape ()
  "The native parser keeps the old decode shape: symbol-keyed alists,
vectors, null AND false as nil; leading and trailing chatter ignored."
  (should (equal (gascity-reader-parse-json
                  "Warning: banner\n{\"a\":null,\"b\":false,\"c\":[1,{\"d\":true}],\"e\":{}} tail")
                 '((a) (b) (c . [1 ((d . t))]) (e))))
  (should (equal (gascity-reader-parse-json "[]") []))
  (should-error (gascity-reader-parse-json "{\"a\":") :type 'gascity-json-parse-error)
  (should-error (gascity-reader-parse-json "") :type 'gascity-json-parse-error))

;;; ssh pipe transport

(ert-deftest gascity-test-store-ssh-command-round-trips-argv ()
  "The ssh transport's remote command survives one shell evaluation with
the argv intact (spaces, quotes), runs in the host-local directory with
the city env and PATH fragment, and the local argv carries BatchMode,
the ControlMaster options and the TRAMP user/port/host."
  (let* ((local (make-temp-file "gascity test dir " t))
         (default-directory (concat "/ssh:alice@example.org#2222:" local "/"))
         (gascity-remote-ssh-options '("-o" "ControlMaster=auto")))
    (unwind-protect
        (let ((beads-remote-search-path '("/opt/gc/bin" "~/.guix-home/profile/bin")))
          (let* ((argv (gascity-test-with-render-guard
                         ;; Built with no TRAMP I/O at all (R2, §8.5).
                         (gascity-reader--ssh-command
                        "printf" '("%s\n" "status" "a b'c" "$HOME")
                        '(("GC_CITY" . "/home/alice/my city/")))))
                 (cmd (car (last argv))))
            (should (equal (car argv) "ssh"))
            (should (member "BatchMode=yes" argv))
            (should (member "ControlMaster=auto" argv))
            ;; Pipe stdio hygiene (QA F8): stdin from /dev/null, no X11.
            (should (member "-n" argv))
            (should (member "ForwardX11=no" argv))
            (should (member "-T" argv))
            ;; gascity's own ControlPath, never TRAMP's tramp.%C.
            (should (cl-some (lambda (o) (and (string-prefix-p "ControlPath=" o)
                                              (string-match-p "gascity-ssh-%C" o)))
                             argv))
            (should (equal (cl-subseq argv (- (length argv) 7) (1- (length argv)))
                           '("-l" "alice" "-p" "2222" "example.org" "--")))
            (should (string-match-p "GC_CITY=" cmd))
            (should (string-match-p
                     "PATH=/opt/gc/bin:\"\\$HOME\"/.guix-home/profile/bin:\"\\$PATH\" exec printf"
                     cmd))
            ;; Evaluate the remote command locally, as the login shell would.
            (with-temp-buffer
              (should (eql 0 (call-process "/bin/sh" nil t nil "-c"
                                           (concat cmd))))
              (should (equal (split-string (buffer-string) "\n" t)
                             '("status" "a b'c" "$HOME"))))
            ;; It runs in the host-local directory.
            (with-temp-buffer
              (call-process "/bin/sh" nil t nil "-c"
                            (car (last (gascity-reader--ssh-command "pwd" nil nil))))
              (should (equal (string-trim (buffer-string)) local)))))
      (delete-directory local t))))

(ert-deftest gascity-test-store-ssh-transport-selection ()
  "ssh-family single-hop cities use the ssh pipe; other methods, multi-hop
names and `gascity-remote-transport' = tramp keep TRAMP's make-process."
  (let ((gascity-remote-transport 'ssh))
    (should (gascity-reader--ssh-pipe-p "/ssh:localhost:/home/roman/bright-lights/"))
    (should (gascity-reader--ssh-pipe-p "/scp:u@h:/c/"))
    (should-not (gascity-reader--ssh-pipe-p "/tmp/city/"))
    (gascity-test-ensure-mock-method)
    (should-not (gascity-reader--ssh-pipe-p "/mock::/tmp/"))
    (should-not (gascity-reader--ssh-pipe-p "/ssh:a|ssh:b:/c/")))
  (let ((gascity-remote-transport 'tramp))
    (should-not (gascity-reader--ssh-pipe-p "/ssh:localhost:/c/"))))

(ert-deftest gascity-test-store-ssh-read-async-is-a-local-process ()
  "Over the ssh transport an async read spawns a LOCAL process (no file
handler, no TRAMP), with no directory probe, and decodes stdout while
stderr stays separate; a failure reports the remote stderr."
  (let ((default-directory "/ssh:u@h:/c/")
        (gascity-reader-city-args-function nil)
        spawned data err)
    (cl-letf (((symbol-function 'gascity-reader--bounded-executable)
               (lambda () "/h/bin/gc"))
              ((symbol-function 'gascity-remote-path-assignment) #'ignore)
              ((symbol-function 'gascity-reader--async-dir-probe)
               (lambda () (error "probe must not run")))
              ((symbol-function 'gascity-reader--ssh-command)
               (lambda (_exe args _env)
                 (setq spawned args)
                 (list "/bin/sh" "-c"
                       (if (member "fail" args)
                           "echo 'gc: boom' >&2; exit 2"
                         "echo 'warn' >&2; echo '{\"ok\":true}'")))))
      (let ((p (gascity-reader-read-async '("status") (lambda (d) (setq data d))
                                          (lambda (m) (setq err m)))))
        (should (processp p))
        (should-not (process-get p 'remote-tty))
        (should (equal (process-get p 'tramp-vector) nil)))
      (should (gascity-test-store--wait (lambda () data) 5))
      (should (equal data '((ok . t))))
      (should (equal spawned '("status" "--json")))
      (gascity-reader-read-async '("fail") #'ignore (lambda (m) (setq err m)))
      (should (gascity-test-store--wait (lambda () err) 5))
      (should (string-match-p "gc: boom" err)))))

;;; Render guard (R2)

(ert-deftest gascity-test-store-render-guard-fixture ()
  "The guard refuses I/O on remote names and lets pure name ops through."
  (gascity-test-ensure-mock-method)
  (gascity-test-with-render-guard
    (should (equal (file-name-directory "/mock::/tmp/x/y") "/mock::/tmp/x/"))
    (should (string-prefix-p "/mock:" (file-remote-p "/mock::/tmp/x")))
    (should (string-suffix-p ":/tmp/x/y" (expand-file-name "y" "/mock::/tmp/x/")))
    (should-error (file-exists-p "/mock::/tmp/x") :type 'gascity-test-render-guard-io)
    (should-error (abbreviate-file-name "/mock::/tmp/x")
                  :type 'gascity-test-render-guard-io)
    (should (assq 'file-exists-p gascity-test-render-guard-violations))
    ;; Local names are untouched.
    (should (file-exists-p "/"))))

(ert-deftest gascity-test-store-hook-render-is-io-free-remotely ()
  "Mounting and re-rendering a store-backed component on a remote
`default-directory' does no file I/O (R2): scheduling, snapshots and
subscriber re-renders are pure."
  (gascity-test-store--remote-host
    (gascity-test-with-store-stubs reads _actions
      (let ((vui-render-delay nil)
            (default-directory gascity-test-store--remote))
        (save-window-excursion
          (unwind-protect
              (gascity-test-with-render-guard
                (vui-mount (vui-component 'gascity-test-store--app) "*store-guard*")
                (with-current-buffer "*store-guard*"
                  (funcall (nth 1 (car reads)) 'remote-data)
                  (should (string-match-p "ready:remote-data" (buffer-string))))
                (should (null gascity-test-render-guard-violations)))
            (when (get-buffer "*store-guard*") (kill-buffer "*store-guard*"))))))))

(ert-deftest gascity-test-store-prompts-never-block ()
  "Completion candidates come from memory and refresh in the background:
a cold prompt offers nothing (free entry), the next one the fresh list;
nothing runs gc synchronously (§8.5, QA F4)."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/"))
      (cl-letf (((symbol-function 'gascity-reader-run)
                 (lambda (&rest _) (error "sync gc")))
                ((symbol-function 'gascity-context-rig-name)
                 (lambda (&rest _) (error "sync rig status"))))
        (should (null (gascity-action--session-names)))
        (should (member '("session" "list") (mapcar #'car reads)))
        (funcall (nth 1 (assoc '("session" "list") reads))
                 '((sessions . [((agent_name . "mayor"))])))
        (should (equal (gascity-action--session-names) '("mayor")))
        (clrhash gascity-context--rigs-cache)
        (should (null (gascity-action--rig-names)))
        (funcall (nth 1 (assoc '("rig" "list") reads))
                 '((rigs . [((name . "alpha") (path . "/r/a") (prefix . "al"))])))
        (should (equal (gascity-action--rig-names) '("alpha")))
        (should (null (gascity-context-rig-name-cached "/nowhere/")))))))

;;; Rendered flags: ◐ stale / timed out, offline header, pending `…'

(ert-deftest gascity-test-store-flags-section-stale-marks ()
  "A store snapshot that kept good data over a failed or timed-out refresh
marks its section `◐ stale' / `◐ timed out', the reason in help-echo."
  (let* ((stale (gascity-ui-effective-load
                 '(:status ready :data (x) :error "gc status failed: boom")
                 (list nil)))
         (late (gascity-ui-effective-load
                '(:status ready :data (x) :error "gc status timed out after 30s"
                          :timed-out t)
                (list nil)))
         (m1 (gascity-ui-stale-mark (list stale)))
         (m2 (gascity-ui-stale-mark (list stale late))))
    (should (string-match-p "◐ stale" m1))
    (should (equal (get-text-property 1 'help-echo m1) "gc status failed: boom"))
    (should (string-match-p "◐ timed out" m2))
    (should (string-search "timed out after 30s" (get-text-property 1 'help-echo m2)))
    (should (equal (gascity-ui-stale-mark
                    (list (gascity-ui-effective-load '(:status ready :data (x))
                                                     (list nil))))
                   ""))))

(ert-deftest gascity-test-store-flags-offline-header ()
  "The cockpit header shows `○ offline @host' while the store paused the host."
  (with-temp-buffer
    (setq default-directory "/ssh:farhost:/c/")
    (should-not (string-search "offline" (gascity-dashboard--header-line)))
    (gascity-store--set-state (gascity-store--host "/ssh:farhost:") 'offline
                              "ssh: Connection refused")
    (let ((line (gascity-dashboard--header-line)))
      (should (string-search "offline @farhost" line))
      (should (string-search "@farhost" line))
      (should (equal (get-text-property (string-search "offline" line)
                                        'help-echo line)
                     "ssh: Connection refused")))))

(ert-deftest gascity-test-store-flags-pending-rows ()
  "While an action on a target runs, its rows show `…' in the status slot:
the vui glyph helper and a tabulated list's status column, redrawn by
the pending hook; the mark goes when the action settles."
  (gascity-test-with-store-stubs _reads actions
    (let ((default-directory "/tmp/city/")
          (buf (get-buffer-create "*gascity-test-pending*")))
      (unwind-protect
          (progn
            (with-current-buffer buf
              (setq default-directory "/tmp/city/")
              (tabulated-list-mode)
              (setq tabulated-list-format [("Agent" 12 t) ("State" 8 t)])
              (tabulated-list-init-header)
              (gascity-tabulated--init-paged
               "Sessions" (list (list "rig/a" (vector "rig/a" "active"))
                                (list "rig/b" (vector "rig/b" "active")))))
            (should (equal (gascity-ui-pending-glyph "rig/a" "●") "●"))
            (gascity-store-action '("session" "suspend" "rig/a") :target "rig/a"
                                  :echo nil)
            (should (equal (substring-no-properties
                            (gascity-ui-pending-glyph "rig/a" "●"))
                           "…"))
            (with-current-buffer buf
              (should (equal (mapcar (lambda (e) (substring-no-properties
                                                  (aref (cadr e) 1)))
                                     tabulated-list-entries)
                             '("…" "active"))))
            (funcall (nth 1 (car actions)) (list :exit-code 0 :stdout "" :stderr ""))
            (with-current-buffer buf
              (should (equal (mapcar (lambda (e) (substring-no-properties
                                                  (aref (cadr e) 1)))
                                     tabulated-list-entries)
                             '("active" "active")))))
        (kill-buffer buf)))))

(ert-deftest gascity-test-store-jump-rig-cold-cache ()
  "`j g' on a cold rig memo offers only \"city\" (the cockpit) and starts
a background `gc rig list'; nothing runs gc synchronously."
  (gascity-test-with-store-stubs reads _actions
    (let ((default-directory "/tmp/city/") offered opened)
      (clrhash gascity-context--rigs-cache)
      (cl-letf (((symbol-function 'gascity-reader-run)
                 (lambda (&rest _) (error "sync gc")))
                ((symbol-function 'gascity-rig-at-point) #'ignore)
                ((symbol-function 'completing-read)
                 (lambda (_p coll &rest _) (setq offered coll) "city"))
                ((symbol-function 'gascity-dashboard)
                 (lambda (&rest _) (setq opened 'cockpit))))
        (gascity-jump-rig)
        (should (equal offered '("city")))
        (should (eq opened 'cockpit))
        (should (member '("rig" "list") (mapcar #'car reads)))))))

(ert-deftest gascity-test-store-views-leave-no-timer-behind ()
  "Views refresh from the live event stream, not timers: the session list
and the cockpit start no repeating timer, and killing them leaves none
\(a leaked one fired remote refreshes inside later tests' event loops)."
  (let ((before (copy-sequence timer-list))
        (list-buf (generate-new-buffer "*gascity-test-timer-list*"))
        (cockpit (generate-new-buffer "*gascity-test-timer-cockpit*")))
    (with-current-buffer list-buf (gascity-session-list-mode))
    (with-current-buffer cockpit (gascity-dashboard-mode))
    (kill-buffer list-buf)
    (kill-buffer cockpit)
    (should-not (seq-some (lambda (tm) (and (timer--repeat-delay tm)
                                            (not (memq tm before))))
                          timer-list))))

;;; D9 non-blocking guard

(defconst gascity-test-store--sync-exempt
  '(gascity-start gascity-stop)
  "Input-free verbs exempt from the non-blocking guard (§8.5 exceptions).
City start/stop keep their streaming `async-shell-command' buffer.")

(defun gascity-test-store--verbs ()
  "Return (NAME . THUNK) for every input-free action verb, prompts answered."
  (let ((mail (gascity-domain-decode 'gascity-mail
                                     '((id . "m-1") (from . "mayor")
                                       (subject . "hi")))))
    `((gascity-session-suspend . ,(lambda () (gascity-session-suspend "r/a")))
      (gascity-session-wake . ,(lambda () (gascity-session-wake "r/a")))
      (gascity-session-drain . ,(lambda () (gascity-session-drain "r/a")))
      (gascity-session-undrain . ,(lambda () (gascity-session-undrain "r/a")))
      (gascity-session-kill . ,(lambda () (gascity-session-kill "r/a")))
      (gascity-session-reset . ,(lambda () (gascity-session-reset "r/a")))
      (gascity-session-nudge . ,(lambda () (gascity-session-nudge "r/a" "hi")))
      (gascity-session-suspend-at-point . gascity-session-suspend-at-point)
      (gascity-session-wake-at-point . gascity-session-wake-at-point)
      (gascity-session-drain-at-point . gascity-session-drain-at-point)
      (gascity-session-undrain-at-point . gascity-session-undrain-at-point)
      (gascity-session-kill-at-point . gascity-session-kill-at-point)
      (gascity-session-reset-at-point . gascity-session-reset-at-point)
      (gascity-session-nudge-at-point . gascity-session-nudge-at-point)
      (gascity-session-peek . ,(lambda () (gascity-session-peek "r/a")))
      (gascity-rig-suspend . ,(lambda () (gascity-rig-suspend "rig1")))
      (gascity-rig-resume . ,(lambda () (gascity-rig-resume "rig1")))
      (gascity-rig-restart . ,(lambda () (gascity-rig-restart "rig1")))
      (gascity-rig-suspend-at-point . gascity-rig-suspend-at-point)
      (gascity-rig-resume-at-point . gascity-rig-resume-at-point)
      (gascity-rig-restart-at-point . gascity-rig-restart-at-point)
      (gascity-mail-read-at-point . gascity-mail-read-at-point)
      (gascity-mail-archive-at-point . gascity-mail-archive-at-point)
      (gascity-mail-mark-read-at-point . gascity-mail-mark-read-at-point)
      (gascity-mail-mark-unread-at-point . gascity-mail-mark-unread-at-point)
      (gascity-order-run . ,(lambda () (gascity-order-run "digest")))
      (gascity-order-run-at-point . gascity-order-run-at-point)
      (gascity-reload . ,(lambda () (gascity-reload)))
      (gascity-sling . ,(lambda () (gascity-sling "r/a" "task text")))
      (gascity-costs-refresh
       . ,(lambda () (with-temp-buffer (gascity-costs-mode) (gascity-costs-refresh))))
      (gascity-sling-formula--dispatch
       . ,(lambda ()
            (gascity-sling-formula--dispatch
             (gascity-domain-decode 'gascity-formula '((name . "do-work")))
             "r/a" nil nil)))
      (gascity-mail-send
       . ,(lambda ()
            (gascity-mail-send "mayor" "subject")
            (with-current-buffer (get-buffer (gascity-remote-buffer-name
                                              "*gc-mail to mayor*" nil
                                              (gascity-context-scope-key)))
              (goto-char (point-max))
              (insert "body")
              (gascity-compose-finish))))
      (gascity-mail-reply-at-point
       . ,(lambda ()
            (cl-letf (((symbol-function 'gascity-mail-at-point) (lambda () mail)))
              (gascity-mail-reply-at-point)
              (with-current-buffer (get-buffer (gascity-remote-buffer-name
                                                "*gc-mail reply m-1*" nil
                                                (gascity-context-scope-key)))
                (goto-char (point-max))
                (insert "body")
                (gascity-compose-finish))))))))

(ert-deftest gascity-test-store-non-blocking-guard ()
  "Every input-free action verb returns having only started a process (D9).
The synchronous gc path (`gascity-reader-run', `process-file',
`call-process') signals; prompts are answered; each verb must start
exactly its gc call on the async runner and return.  The §8.5
exceptions (city start/stop) are exempt by name."
  (let ((default-directory "/tmp/city/")
        (sync-calls nil))
    (cl-letf (((symbol-function 'gascity-reader-run)
               (lambda (args) (push args sync-calls)
                 (error "synchronous gc run: %S" args)))
              ((symbol-function 'process-file)
               (lambda (prog &rest _) (push prog sync-calls)
                 (error "process-file %s" prog)))
              ((symbol-function 'call-process)
               (lambda (prog &rest _) (push prog sync-calls)
                 (error "call-process %s" prog)))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'y-or-n-p) (lambda (&rest _) t))
              ((symbol-function 'read-string) (lambda (&rest _) "answer"))
              ((symbol-function 'completing-read) (lambda (&rest _) "answer"))
              ((symbol-function 'pop-to-buffer) (lambda (b &rest _) b))
              ((symbol-function 'gascity-action--session-at-point)
               (lambda () "r/a"))
              ((symbol-function 'gascity-action--rig-at-point) (lambda () "rig1"))
              ((symbol-function 'gascity-action--order-at-point) (lambda () "digest"))
              ((symbol-function 'gascity-mail--id-at-point) (lambda () "m-1"))
              ((symbol-function 'gascity-bead-at-point) (lambda () nil))
              ((symbol-function 'gascity-context-city-root)
               (lambda (&optional _) "/tmp/city/")))
      (dolist (verb (gascity-test-store--verbs))
        (unless (memq (car verb) gascity-test-store--sync-exempt)
          (gascity-store-clear)
          (gascity-test-with-store-stubs reads actions
            (let ((start (float-time)))
              (condition-case err
                  (funcall (cdr verb))
                (error (ert-fail (list (car verb) err))))
              (should (< (- (float-time) start) 1.0))
              (ert-info ((format "%s" (car verb)))
                (should (null sync-calls))
                (should (null reads))
                (should (= (length actions) 1))
                ;; Only started: nothing has answered, the target is
                ;; still pending.
                (should (gascity-store-pending-targets))))))))
    (dolist (b (buffer-list))
      (when (string-match-p "\\`\\*gc-\\(mail\\|peek\\)" (buffer-name b))
        (kill-buffer b)))))

(provide 'gascity-store-test)
;;; gascity-store-test.el ends here
