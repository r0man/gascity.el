;;; gascity-live-test.el --- Tests for the live event stream -*- lexical-binding: t; -*-

;;; Commentary:

;; dashboard-v3 P3 (§8.2, §8.3 R4): JSONL chunking, seq tracking and
;; resume argv, backoff, routing and debounce, process lifetime (no
;; leaks after `kill-buffer'), the ssh pipe command's round trip
;; through `sh -c', header strings, and the view refresh guards that
;; replaced the 5 s timers.  Real processes are local fake gc scripts;
;; nothing talks to a live city.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-live)

;;; Helpers

(defmacro gascity-live-test--with-clean-state (&rest body)
  "Run BODY with a private stream table and batch streams allowed."
  (declare (indent 0))
  `(let ((gascity-live--streams (make-hash-table :test 'equal))
         (gascity-live-in-batch t)
         (gascity-live-enabled t))
     (unwind-protect (progn ,@body)
       (gascity-live-stop-all))))

(defun gascity-live-test--stream (&rest slots)
  "Return a detached stream struct with SLOTS."
  (apply #'gascity-live--stream-create
         (append slots (list :root (or (plist-get slots :root) "/tmp/city/")))))

(defun gascity-live-test--fake-gc (dir body)
  "Write an executable fake gc script with BODY into DIR; return its path."
  (let ((path (expand-file-name "fake gc" dir)))
    (with-temp-file path (insert "#!/bin/sh\n" body))
    (set-file-modes path #o755)
    path))

(defun gascity-live-test--wait (pred &optional secs)
  "Pump the event loop until PRED is non-nil or SECS (default 5) pass."
  (let ((deadline (+ (float-time) (or secs 5))))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall pred)))

(defun gascity-live-test--live-procs ()
  "Return the live processes this module started."
  (seq-filter (lambda (p) (and (process-live-p p)
                               (string-prefix-p "gascity-live" (process-name p))))
              (process-list)))

;;; JSONL chunking

(ert-deftest gascity-test-live-parse-chunk-splits-across-chunks ()
  "Complete lines decode; a partial line waits for the next chunk."
  (let* ((r1 (gascity-live-parse-chunk
              "" "{\"type\":\"a.x\",\"seq\":1}\n{\"type\":\"b.y\",\"se"))
         (r2 (gascity-live-parse-chunk (cdr r1) "q\":2}\n")))
    (should (equal (mapcar (lambda (e) (alist-get 'seq e)) (car r1)) '(1)))
    (should (equal (cdr r1) "{\"type\":\"b.y\",\"se"))
    (should (equal (alist-get 'type (car (car r2))) "b.y"))
    (should (equal (cdr r2) ""))))

(ert-deftest gascity-test-live-parse-chunk-skips-noise ()
  "Banner lines, blank lines and malformed JSON are skipped."
  (let ((r (gascity-live-parse-chunk
            "" "Warning: banner\n\n{bad json}\n{\"seq\":3,\"ok\":false,\"x\":null}\n")))
    (should (= (length (car r)) 1))
    (should (equal (car (car r)) '((seq . 3) (ok) (x))))))

(ert-deftest gascity-test-live-parse-chunk-no-newline ()
  "A chunk without a newline is all partial."
  (should (equal (gascity-live-parse-chunk "{\"a\"" ":1") '(nil . "{\"a\":1"))))

;;; seq tracking and resume argv

(ert-deftest gascity-test-live-seq-tracking-and-resume-args ()
  "The highest seq seen is remembered and resumes with --after SEQ."
  (let ((s (gascity-live-test--stream)))
    (should (equal (gascity-live--args s)
                   '("events" "--follow" "--city" "/tmp/city/")))
    (cl-letf (((symbol-function 'gascity-live--queue) #'ignore))
      (gascity-live--deliver s '(((seq . 41)) ((seq . 43)) ((seq . 42)))))
    (should (= (gascity-live--stream-seq s) 43))
    (should (equal (gascity-live--args s)
                   '("events" "--follow" "--after" "43" "--city" "/tmp/city/")))))

(ert-deftest gascity-test-live-remote-command-is-ssh-pipe ()
  "A remote ssh city streams through gascity's no-pty ssh pipe, built
without host resolution, resuming with --after."
  (let* ((gascity-executable "gc")
         (s (gascity-live-test--stream :root "/ssh:u@h#2222:/home/u/city/" :seq 7))
         (argv (gascity-live-command s)))
    (should (equal argv
                   (gascity-remote-ssh-pipe-argv
                    "/ssh:u@h#2222:/home/u/city/"
                    (list "/bin/sh" "-c" gascity-live--exit-reporter "gc"
                          "events" "--follow" "--after" "7"
                          "--city" "/home/u/city/")
                    :resolve nil :stdin t)))
    ;; stdin stays open (no -n): the host watcher stops gc at EOF.
    (should-not (member "-n" argv))
    (should (equal (car argv) "ssh"))
    (should (member "-T" argv))
    (should (member "BatchMode=yes" argv))
    (should (string-match-p "--after 7 --city /home/u/city/\\'" (car (last argv))))))

(ert-deftest gascity-test-live-remote-command-never-touches-tramp ()
  "Building (and rebuilding) the remote command does no file I/O."
  (let ((s (gascity-live-test--stream :root "/ssh:u@h:/home/u/city/")))
    (cl-letf (((symbol-function 'gascity-remote-find-executable)
               (lambda (&rest _) (error "Must not resolve on the host")))
              ((symbol-function 'gascity-remote-path-assignment)
               (lambda (&rest _) (error "Must not expand on the host")))
              ((symbol-function 'file-executable-p)
               (lambda (&rest _) (error "No file I/O"))))
      (should (gascity-live-command s)))))

(ert-deftest gascity-test-live-pipe-command-roundtrip ()
  "The ssh command string, evaluated by sh, runs the exact argv.
Paths with spaces in the program, PATH and city survive one shell."
  (let* ((dir (make-temp-file "gascity live " t))
         (printer (gascity-live-test--fake-gc
                   dir "for a in \"$@\"; do printf '%s\\0' \"$a\"; done\n")))
    (unwind-protect
        (let* ((gascity-executable printer)
               (beads-remote-search-path (list dir))
               (s (gascity-live-test--stream :root "/ssh:h:/home/u/my city/" :seq 12))
               (cmd (car (last (gascity-live-command s)))))
          (with-temp-buffer
            ;; Keep stdin open (as the ssh session does): at EOF the
            ;; host watcher kills gc.
            (should (zerop (call-process "sh" nil '(t nil) nil "-c"
                                         (concat "sleep 1 | { " cmd "; }"))))
            (should (equal (split-string (buffer-string) "\0" t)
                           '("events" "--follow" "--after" "12"
                             "--city" "/home/u/my city/")))))
      (delete-directory dir t))))

(ert-deftest gascity-test-live-ssh-detection ()
  "ssh-family methods stream; others (and multi-hop) poll."
  (should (gascity-live--ssh-p "/ssh:h:/c/"))
  (should (gascity-live--ssh-p "/scpx:u@h:/c/"))
  (should-not (gascity-live--ssh-p "/c/"))
  (should-not (gascity-live--ssh-p "/sudo:root@localhost:/c/"))
  (should-not (gascity-live--ssh-p "/ssh:a@b|ssh:c@d:/c/")))

;;; Backoff

(ert-deftest gascity-test-live-backoff-sequence ()
  "2 → 5 → 15 → 60, then 60 forever."
  (should (equal (mapcar #'gascity-live-backoff-delay '(0 1 2 3 4 9))
                 '(2 5 15 60 60 60))))

(ert-deftest gascity-test-live-schedule-retry-walks-backoff ()
  "Each failed attempt waits the next delay; a stable run resets it."
  (let ((s (gascity-live-test--stream))
        delays)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (secs &rest _) (push secs delays) 'fake-timer))
              ((symbol-function 'timerp) (lambda (x) (eq x 'fake-timer)))
              ((symbol-function 'cancel-timer) #'ignore))
      (dotimes (_ 5) (gascity-live--schedule-retry s))
      (should (equal (nreverse delays) '(2 5 15 60 60)))
      ;; An exit after a long uptime starts over at 2 s.
      (setq delays nil)
      (setf (gascity-live--stream-started s) (- (float-time) 100))
      (let ((proc (make-process :name "gascity-live-test" :command '("true"))))
        (gascity-live-test--wait (lambda () (not (process-live-p proc))))
        (setf (gascity-live--stream-process s) proc)
        (gascity-live--exited s proc 1))
      (should (equal delays '(2))))))

(ert-deftest gascity-test-live-classify-exit ()
  "Remote: no gc exit report means the link dropped (offline); a
report means gc itself exited.  gc API failures mean supervisor down."
  (let ((remote (gascity-live-test--stream :root "/ssh:h:/c/"))
        (local (gascity-live-test--stream :root "/c/"))
        (api "gc events: request failed: Get \"http://127.0.0.1:9/v0\": dial tcp 127.0.0.1:9: connect: connection refused"))
    (should (eq (car (gascity-live--classify remote 255 nil)) 'offline))
    (should (eq (car (gascity-live--classify
                      remote 255 '("ssh: connect to host h port 22: Connection refused")))
                'offline))
    (should (equal (gascity-live--classify remote 1 (list api "gascity-live-exit 1"))
                   (cons 'supervisor-down api)))
    (should (equal (gascity-live--classify remote 143 '("gascity-live-exit 143"))
                   '(reconnecting . "gc exited 143")))
    (should (eq (car (gascity-live--classify local 1 (list api))) 'supervisor-down))
    (should (eq (car (gascity-live--classify local 1 '("something else")))
                'reconnecting))
    (should (eq (car (gascity-live--classify local 255 nil)) 'reconnecting))))

(ert-deftest gascity-test-live-exit-reporter-kills-gc-on-eof ()
  "Closing the session's stdin (the stream stopped) kills the host gc."
  (let* ((dir (make-temp-file "gascity-live" t))
         (fake (gascity-live-test--fake-gc
                dir "echo $$ > \"$(dirname \"$0\")/pid\"; exec sleep 60\n"))
         (proc (make-process :name "gascity-live-test-reporter"
                             :command (list "/bin/sh" "-c"
                                            gascity-live--exit-reporter fake)
                             :connection-type 'pipe :noquery t
                             :stderr (get-buffer-create " live-rep-err"))))
    (unwind-protect
        (let ((pidfile (expand-file-name "pid" dir)))
          (should (gascity-live-test--wait (lambda () (file-exists-p pidfile))))
          (let ((pid (with-temp-buffer (insert-file-contents pidfile)
                                       (string-to-number (buffer-string)))))
            (should (process-attributes pid))
            (process-send-eof proc)
            (should (gascity-live-test--wait
                     (lambda () (not (process-live-p proc)))))
            (should (gascity-live-test--wait
                     (lambda () (null (process-attributes pid)))))
            (with-current-buffer " live-rep-err"
              (should (string-match-p "gascity-live-exit 143" (buffer-string))))))
      (when (process-live-p proc) (delete-process proc))
      (kill-buffer " live-rep-err")
      (delete-directory dir t))))

(ert-deftest gascity-test-live-exit-reporter-roundtrip ()
  "The host shell reports gc's exit status on stderr, stdout untouched."
  (let* ((dir (make-temp-file "gascity-live" t))
         (fake (gascity-live-test--fake-gc dir "echo out; echo err >&2; exit 3\n")))
    (unwind-protect
        (let ((err (make-temp-file "gascity-live-err")))
          (with-temp-buffer
            ;; stdin stays open, as in the ssh session.
            (call-process "/bin/sh" nil (list t err) nil "-c"
                          (concat "sleep 1 | /bin/sh -c "
                                  (shell-quote-argument gascity-live--exit-reporter)
                                  " " (shell-quote-argument fake) " x"))
            (should (equal (buffer-string) "out\n")))
          (with-temp-buffer
            (insert-file-contents err)
            (should (equal (buffer-string) "err\ngascity-live-exit 3\n")))
          (delete-file err))
      (delete-directory dir t))))

;;; Routing and debounce

(ert-deftest gascity-test-live-routing-table ()
  "Event type prefixes route to the §8.2 view kinds."
  (should (equal (gascity-live-route "session.woke") '(agents)))
  (should (equal (gascity-live-route "agent.idle") '(agents)))
  (should (equal (gascity-live-route "bead.created") '(work runs)))
  (should (equal (gascity-live-route "mail.sent") '(mail)))
  (should (equal (gascity-live-route "order.fired") '(activity)))
  (should (equal (gascity-live-route "convoy.closed") '(work runs)))
  (should-not (gascity-live-route "city.started"))
  (should-not (gascity-live-route nil)))

(ert-deftest gascity-test-live-debounce-batches-events ()
  "Events inside the window flush once, with the union of their kinds."
  (let ((s (gascity-live-test--stream))
        timers flushed)
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (secs _rep fn &rest args)
                 (push (list secs fn args) timers) 'fake-timer))
              ((symbol-function 'gascity-live--invalidate)
               (lambda (root kinds types) (push (list root kinds types) flushed))))
      (gascity-live--deliver s '(((type . "session.woke") (seq . 1))
                                 ((type . "order.fired") (seq . 2))
                                 ((type . "session.woke") (seq . 3))))
      (should (= (length timers) 1))
      (should (= (car (car timers)) gascity-live-debounce))
      (apply (nth 1 (car timers)) (nth 2 (car timers)))
      (should (equal flushed
                     '(("/tmp/city/" (agents activity)
                        ("session.woke" "order.fired")))))
      (should-not (gascity-live--stream-pending s))
      (should-not (gascity-live--stream-debounce-timer s)))))

(ert-deftest gascity-test-live-resume-requests-full-refresh ()
  "A resumed stream's batch carries KINDS `all'."
  (let ((s (gascity-live-test--stream))
        flushed)
    (cl-letf (((symbol-function 'run-at-time) (lambda (&rest _) 'fake-timer))
              ((symbol-function 'gascity-live--invalidate)
               (lambda (_root kinds types) (push (cons kinds types) flushed))))
      (gascity-live--queue s :all)
      (gascity-live--flush s)
      (should (equal flushed '((all)))))))

(ert-deftest gascity-test-live-invalidate-reaches-views-and-store ()
  "A batch calls the store per type, the hook, and matching views only."
  (gascity-live-test--with-clean-state
    (let ((root (file-name-as-directory (make-temp-file "gascity-live-city" t)))
          (gascity-live-enabled nil)
          store-calls hook-calls agents-hits mail-hits)
      (unwind-protect
          (cl-letf (((symbol-function 'gascity-store-invalidate-event)
                     (lambda (type dir) (push (cons type dir) store-calls)))
                    ((symbol-function 'gascity-store-invalidate)
                     (lambda (&rest args) (push args store-calls))))
            (let ((gascity-live-invalidate-functions
                   (list (lambda (r k ty) (push (list r k ty) hook-calls))))
                  (a (generate-new-buffer " live-a"))
                  (m (generate-new-buffer " live-m")))
              (unwind-protect
                  (progn
                    (dolist (spec (list (list a '(agents) (lambda () (push t agents-hits)))
                                        (list m '(mail) (lambda () (push t mail-hits)))))
                      (with-current-buffer (nth 0 spec)
                        (setq default-directory root)
                        (gascity-live-attach nil :kinds (nth 1 spec)
                                             :refresh (nth 2 spec))))
                    (gascity-live--invalidate root '(agents) '("session.woke"))
                    (should (equal store-calls (list (cons "session.woke" root))))
                    (should (equal hook-calls
                                   (list (list root '(agents) '("session.woke")))))
                    (should (equal agents-hits '(t)))
                    (should-not mail-hits)
                    (gascity-live--invalidate root 'all nil)
                    (should (equal (car store-calls) (list :dir root)))
                    (should (equal agents-hits '(t t)))
                    (should (equal mail-hits '(t))))
                (kill-buffer a) (kill-buffer m))))
        (delete-directory root t)))))

;;; Process lifetime

(ert-deftest gascity-test-live-stream-delivers-and-stops-on-kill ()
  "A real (fake gc) stream delivers events; killing the last view
stops it and leaves no process, timer or stream behind."
  (gascity-live-test--with-clean-state
    (let* ((root (file-name-as-directory (make-temp-file "gascity-live-city" t)))
           (gascity-executable
            (gascity-live-test--fake-gc
             root (concat "printf '%s\\n' '{\"type\":\"session.woke\",\"seq\":5}'\n"
                          "printf '{\"type\":\"mail.sent\",' ; sleep 0.2\n"
                          "printf '\"seq\":6}\\n'\n"
                          "exec sleep 30\n")))
           (buf (generate-new-buffer " live-view"))
           events)
      (unwind-protect
          (progn
            (with-current-buffer buf
              (setq default-directory root)
              (gascity-live-attach)
              (gascity-live-subscribe (lambda (e) (push e events))))
            (should (gascity-live-test--wait (lambda () (= (length events) 2))))
            (should (equal (mapcar (lambda (e) (alist-get 'seq e)) (reverse events))
                           '(5 6)))
            (let ((stream (gethash root gascity-live--streams)))
              (should (= (gascity-live--stream-seq stream) 6))
              (should (eq (plist-get (gascity-live-status root) :state) 'live))
              (should (gascity-live-active-p root))
              (kill-buffer buf)
              (should-not (gethash root gascity-live--streams))
              (should-not (process-live-p (gascity-live--stream-process stream)))
              (should-not (gascity-live--stream-debounce-timer stream))
              (should-not (gascity-live--stream-retry-timer stream))
              (should (gascity-live-test--wait
                       (lambda () (null (gascity-live-test--live-procs))) 3))))
        (when (buffer-live-p buf) (kill-buffer buf))
        (delete-directory root t)))))

(ert-deftest gascity-test-live-supervisor-down-then-reconnect ()
  "A gc API failure shows supervisor down and schedules a 2 s retry;
`gascity-live-reconnect' retries at once, resuming with --after."
  (gascity-live-test--with-clean-state
    (let* ((root (file-name-as-directory (make-temp-file "gascity-live-city" t)))
           (gascity-executable
            (gascity-live-test--fake-gc
             root (concat "echo \"$@\" >> \"$(dirname \"$0\")/argv.log\"\n"
                          "printf '%s\\n' '{\"type\":\"bead.created\",\"seq\":9}'\n"
                          "echo 'gc events: request failed: dial tcp 127.0.0.1:9: connect: connection refused' >&2\n"
                          "exit 1\n")))
           (buf (generate-new-buffer " live-view")))
      (unwind-protect
          (with-current-buffer buf
            (setq default-directory root)
            (let ((stream (gascity-live-attach)))
              (should (gascity-live-test--wait
                       (lambda () (eq (gascity-live--stream-state stream)
                                      'supervisor-down))))
              (should (equal (gascity-live-header-string root)
                             "○ live: supervisor down"))
              (should (gascity-live--stream-retry-timer stream))
              (should (<= (plist-get (gascity-live-status root) :retry-in) 2))
              (gascity-live-reconnect root)
              (should (gascity-live-test--wait
                       (lambda ()
                         (with-temp-buffer
                           (ignore-errors
                             (insert-file-contents (expand-file-name "argv.log" root)))
                           (string-match-p "--after 9" (buffer-string))))))))
        (kill-buffer buf)
        (should (gascity-live-test--wait
                 (lambda () (null (gascity-live-test--live-procs))) 3))
        (delete-directory root t)))))

(ert-deftest gascity-test-live-toggle-off-and-on ()
  "`W' stops the stream (live off) and starts it again."
  (gascity-live-test--with-clean-state
    (let* ((root (file-name-as-directory (make-temp-file "gascity-live-city" t)))
           (gascity-executable (gascity-live-test--fake-gc root "exec sleep 30\n"))
           (buf (generate-new-buffer " live-view")))
      (unwind-protect
          (with-current-buffer buf
            (setq default-directory root)
            (let ((stream (gascity-live-attach)))
              (should (process-live-p (gascity-live--stream-process stream)))
              (gascity-live-toggle)
              (should-not (gascity-live--stream-process stream))
              (should (equal (gascity-live-header-string) "○ live off"))
              (gascity-live-toggle)
              (should (process-live-p (gascity-live--stream-process stream)))
              (should (equal (gascity-live-header-string) "● live"))))
        (kill-buffer buf)
        (delete-directory root t)))))

(ert-deftest gascity-test-live-no-stream-in-batch-by-default ()
  "Views opened in batch (tests, scripts) start no stream by default."
  (let ((gascity-live--streams (make-hash-table :test 'equal))
        (gascity-live-in-batch nil))
    ;; A real buffer: `with-temp-buffer' inhibits `kill-buffer-hook'.
    (let ((buf (generate-new-buffer " live-view")))
      (with-current-buffer buf
        (setq default-directory temporary-file-directory)
        (let ((stream (gascity-live-attach)))
          (should-not (gascity-live--stream-process stream))
          (should (equal (gascity-live-header-string) "○ live off"))))
      (kill-buffer buf))
    (should (zerop (hash-table-count gascity-live--streams)))))

;;; Header strings

(ert-deftest gascity-test-live-header-strings ()
  "Each state renders its §8.3 header fragment."
  (let ((gascity-live--streams (make-hash-table :test 'equal))
        (s (gascity-live-test--stream :root "/ssh:h:/c/" :host "h")))
    (puthash "/ssh:h:/c/" s gascity-live--streams)
    (cl-flet ((hdr (state &optional retry-at)
                (setf (gascity-live--stream-state s) state
                      (gascity-live--stream-retry-at s) retry-at)
                (substring-no-properties (gascity-live-header-string "/ssh:h:/c/"))))
      (should (equal (hdr 'live) "● live"))
      (should (equal (hdr 'polling) "● live (polling)"))
      (should (equal (hdr 'off) "○ live off"))
      (should (equal (hdr 'supervisor-down) "○ live: supervisor down"))
      (should (equal (hdr 'offline) "○ offline @h"))
      (should (equal (hdr 'reconnecting (+ (float-time) 14.2))
                     "○ live: reconnecting (15s)"))
      (setf (gascity-live--stream-enabled s) nil)
      (should (equal (hdr 'live) "○ live off")))
    ;; Unknown city: no fragment.
    (should-not (gascity-live-header-string "/elsewhere/"))))

;;; View refresh guards (formerly the 5 s timer ticks)

(ert-deftest gascity-test-live-session-list-refresh-guards-and-backoff ()
  "The session list re-reads when visible and idle, spending backoff first."
  (let (calls (visible t) (inflight nil))
    (cl-letf (((symbol-function 'get-buffer-window) (lambda (&rest _) visible))
              ((symbol-function 'gascity-remote-connection-locked-p) #'ignore)
              ((symbol-function 'process-live-p) (lambda (_) inflight))
              ((symbol-function 'gascity-session-list-refresh)
               (lambda (&optional auto) (push auto calls))))
      (with-temp-buffer
        (setq-local gascity-session-list--refresh-backoff 1)
        (gascity-session-list--live-refresh)
        (should-not calls)
        (should (= gascity-session-list--refresh-backoff 0))
        (setq inflight t)
        (gascity-session-list--live-refresh)
        (should-not calls)
        (setq inflight nil visible nil)
        (gascity-session-list--live-refresh)
        (should-not calls)
        (setq visible t)
        (gascity-session-list--live-refresh)
        (should (equal calls '(auto)))))))

(ert-deftest gascity-test-live-keys-bound ()
  "`W' toggles the stream in the cockpit and the session list: the one
`gascity-live-toggle' of every view (§5.1, gascity-consistency-test)."
  (should (eq (keymap-lookup gascity-dashboard-mode-map "W")
              'gascity-live-toggle))
  (should (eq (keymap-lookup gascity-session-list-mode-map "W")
              #'gascity-live-toggle)))

(ert-deftest gascity-test-live-no-refresh-timers ()
  "Opening the cockpit or the session list starts no repeating timer."
  (let ((before (copy-sequence timer-list))
        (gascity-live--streams (make-hash-table :test 'equal))
        (bufs nil))
    (unwind-protect
        (progn
          (dolist (mode '(gascity-dashboard-mode gascity-session-list-mode))
            (let ((b (generate-new-buffer " live-mode")))
              (push b bufs)
              (with-current-buffer b
                (setq default-directory temporary-file-directory)
                (funcall mode))))
          (should-not (seq-some (lambda (tm) (and (timer--repeat-delay tm)
                                                  (not (memq tm before))))
                                timer-list)))
      (mapc #'kill-buffer bufs))))

(provide 'gascity-live-test)
;;; gascity-live-test.el ends here
