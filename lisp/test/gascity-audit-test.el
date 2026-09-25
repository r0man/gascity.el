;;; gascity-audit-test.el --- Cross-cutting §8.4 guarantees over every view -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 §8.4, audited across the whole package rather than view
;; by view:
;;
;; - The render guard over EVERY view (`gascity-audit-views'): each is
;;   opened by its real command on a remote city (`/mock::'), fed from
;;   the captured payloads, then walked with TAB, every thing toggled
;;   with SPC, refreshed with `g' and its header line evaluated — with
;;   zero file I/O on a remote name (§8.3 R2).  Views still being built
;;   (Events, Mail) join by adding an entry; their entries are skipped
;;   until their command exists.
;; - The mode-line lighter with a live stream running for a remote
;;   city: events flow, cockpits re-render, the lighter follows — and
;;   rebuilding or showing it never reads gc or touches TRAMP.
;; - A static scan of every gascity source for file-name primitives that
;;   do remote I/O on a host-only name ("/method:host:") inside timer,
;;   sentinel and filter code (see `gascity-audit-test--scan').
;;
;; The first contact with a host (the city-root walk, §8.5) is done
;; before the guard goes up by priming the context memo, as a real
;; session would have.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'gascity)
(require 'gascity-test-helpers)

;;; Fixtures

(defconst gascity-audit--dir
  (expand-file-name "fixtures/v3/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the captured gc payloads.")

(defun gascity-audit--text (name)
  "Return fixture NAME as a string."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name gascity-audit--dir))
    (buffer-string)))

(defun gascity-audit--json (name)
  "Return fixture NAME decoded as the reader decodes gc JSON."
  (gascity-reader-parse-json (gascity-audit--text name)))

(defun gascity-audit--jsonl (name)
  "Return fixture NAME (JSON Lines) as a list of events."
  (delq nil (mapcar (lambda (l) (and (not (string-empty-p l))
                                     (gascity-reader-parse-json l)))
                    (split-string (gascity-audit--text name) "\n"))))

(defvar gascity-audit--unserved nil
  "Reads the canned reader had no fixture for (argvs), newest first.")

(defun gascity-audit--payload (args)
  "Return the canned payload of gc ARGS for emacs-city, or `:none'."
  (pcase args
    (`("status") (gascity-audit--json "emacs-city.status.json"))
    (`("version") (gascity-audit--json "emacs-city.version.json"))
    (`("dolt" "health") (gascity-audit--json "emacs-city.dolt-health.json"))
    (`("cities") (gascity-audit--json "cities.json"))
    (`("session" "list" . ,_) (gascity-audit--json "emacs-city.session-list.json"))
    (`("session" "logs" ,_ . ,_)
     (gascity-audit--json "bright-lights.session-logs-mayor-tail10.json"))
    (`("agent" "list") (gascity-audit--json "emacs-city.agent-list.json"))
    (`("mail" "count") (gascity-audit--json "emacs-city.mail-count.json"))
    (`("mail" "inbox" . ,_) (gascity-audit--json "emacs-city.mail-inbox.json"))
    (`("mail" "thread" . ,_) (gascity-audit--json "bright-lights.mail-thread.json"))
    (`("convoy" "list") (gascity-audit--json "emacs-city.convoy-list.json"))
    (`("convoy" "status" ,id)
     `((convoy . ((id . ,id) (status . "open") (title . "input")))
       (progress . ((closed . 0) (total . 1)))))
    (`("rig" "list") (gascity-audit--json "emacs-city.rig-list.json"))
    (`("rig" "status" ,rig)
     (gascity-audit--json (format "emacs-city.rig-status-%s.json" rig)))
    (`("order" "list" . ,_)
     '((orders . [((name . "digest") (scoped_name . "digest") (type . "formula")
                   (trigger . "cooldown") (interval . "1h") (enabled . t)
                   (rig . "beads.el"))])))
    (`("bd" "ready" . ,_) (gascity-audit--json "emacs-city.bd-ready.json"))
    (`("bd" "list" . ,rest)
     (cond ((member "--label-regex" rest) [])
           ((or (member "--all" rest) (member "--metadata-field" rest))
            (if (member "beads.el" rest)
                (gascity-audit--json "emacs-city.bd-list-all-beads.el-runs.json")
              []))
           ((member "--assignee" rest) [])
           ((member "beads.el" rest)
            (gascity-audit--json "emacs-city.bd-list-open-inprogress-beads.el.json"))
           ((member "gascity.el" rest)
            (gascity-audit--json "emacs-city.bd-list-open-inprogress-gascity.el.json"))
           (t (gascity-audit--json "emacs-city.bd-list-open-inprogress.json"))))
    (`("events" . ,_)
     (cons (gascity-audit--jsonl "emacs-city.events-2h.jsonl") 0))
    (_ :none)))

(defun gascity-audit--strip-city (args)
  "Return ARGS without leading `--city ROOT' tokens."
  (if (equal (car args) "--city") (cddr args) args))

(defun gascity-audit--read (args callback &optional errback &rest _)
  "Canned `gascity-reader-read-async': ARGS answered from the fixtures.
CALLBACK gets the payload at once; an argv with no fixture is recorded
in `gascity-audit--unserved' and reported through ERRBACK."
  (let* ((args (gascity-audit--strip-city (remove "--json" args)))
         (payload (gascity-audit--payload args)))
    (if (eq payload :none)
        (progn (push args gascity-audit--unserved)
               (when errback (funcall errback (format "no fixture for %S" args))))
      (funcall callback payload)))
  nil)

(defvar gascity-audit--actions nil
  "Argvs `gascity-reader-run-async' was asked to run, newest first.")

(defun gascity-audit--run (args callback)
  "Canned `gascity-reader-run-async': record ARGS, answer CALLBACK."
  (push args gascity-audit--actions)
  (funcall callback
           (list :exit-code 0
                 :stdout (pcase (gascity-audit--strip-city args)
                           (`("costs" . ,_) (gascity-audit--text "emacs-city.costs.txt"))
                           (`("doctor" . ,_) (gascity-audit--text "bright-lights.doctor.json"))
                           (_ ""))
                 :stderr ""))
  nil)

(defconst gascity-audit--root "/mock::/home/roman/emacs-city/"
  "The remote city every guarded view is opened on.")

(defun gascity-audit--agent ()
  "Return an agent object as the views carry at point."
  (make-instance 'gascity-agent :name "beads.el/gc.requirements-planner-1"
                 :rig "beads.el" :session-name "gc__requirements-planner-ec-fl8o"
                 :socket "emacs-city"))

(defmacro gascity-audit--with-remote-city (&rest body)
  "Run BODY in a primed remote city with the gc boundary canned.
The mock method is registered, the host marked primed (first contact
done) and the context memo seeded with the city root, the way a
session looks after its first view opened.  Streams stay off (batch)."
  (declare (indent 0))
  `(progn
     (gascity-test-ensure-mock-method)
     (let* ((tramp-verbose 0)
            (vui-render-delay nil)
            (gascity-store-synchronous-delivery t)
            (gascity-store-inline-render-dispatch t)
            (gascity-dashboard-filters nil)
            (gascity-runs-filters nil)
            (gascity-remote-hosts nil)
            (gascity-audit--unserved nil)
            (gascity-audit--actions nil)
            (default-directory gascity-audit--root))
       (clrhash gascity-context--root-cache)
       (let ((expanded (substring-no-properties (expand-file-name gascity-audit--root))))
         (dolist (key (list gascity-audit--root expanded))
           (puthash key expanded gascity-context--root-cache)))
       (setf (gascity-store--host-primed
              (gascity-store--host (file-remote-p gascity-audit--root)))
             t)
       (cl-letf (((symbol-function 'gascity-reader-read-async) #'gascity-audit--read)
                 ((symbol-function 'gascity-reader-run-async) #'gascity-audit--run)
                 ;; The mock method stands in for ssh: the ssh-only paths
                 ;; (log follow) take their ssh branch.
                 ((symbol-function 'gascity-reader--ssh-pipe-p)
                  (lambda (&optional dir) (gascity-remote-prefix (or dir default-directory))))
                 ((symbol-function 'gascity-session--log-argv)
                  (lambda (&rest _) (list "printf" "log line\\n")))
                 ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
                 ((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
         (unwind-protect
             (save-window-excursion ,@body)
           (clrhash gascity-context--root-cache)
           (dolist (b (buffer-list))
             (when (and (string-match-p "\\`\\*gascity" (buffer-name b))
                        (buffer-live-p b))
               (let ((kill-buffer-query-functions nil))
                 (kill-buffer b)))))))))

;;; The views

(defvar gascity-audit-views
  `(("cockpit" gascity-dashboard)
    ("agents" gascity-agents)
    ("agents tree" gascity-agents-tree)
    ("agent detail" ,(lambda () (gascity-polecat-detail (gascity-audit--agent))))
    ("runs" gascity-runs)
    ("run detail" ,(lambda () (gascity-run-show "be-52m5" nil "beads.el")))
    ("health" gascity-health)
    ("cities" gascity-cities)
    ("rig dashboard" ,(lambda () (gascity-rig-dashboard "beads.el")))
    ("rig list" gascity-rig-list)
    ("session list" gascity-session-list)
    ("convoy list" gascity-convoy-list)
    ("order list" gascity-order-list)
    ("dolt list" gascity-dolt-list)
    ("costs" gascity-costs :text t)
    ("log follower"
     ,(lambda ()
        (with-temp-buffer
          (setq default-directory gascity-audit--root)
          (setq-local gascity-section--agent (gascity-audit--agent))
          (gascity-session-follow-log)))
     :wait-output t :text t)
    ("events" gascity-events)
    ("mail" gascity-mail)
    ("mail thread"
     ,(lambda ()
        (gascity-mail-thread-show
         (gascity-mail-message :id "bl-wisp-a7gsqc" :thread-id "thread-b1b8bd38a599"
                               :from "human" :subject "Dolt health advisory")))))
  "Every view the render guard opens: (NAME OPENER . PROPS).
OPENER is a command (called interactively) or a function of no
arguments; the view is the buffer it leaves selected.  With `:pending'
the entry is skipped while OPENER is not a command yet; with
`:wait-output' the buffer is filled by a process, waited for; a
`:text' view has no things to walk.")

(defun gascity-audit--settle (buf props)
  "Wait (at most 2 s) for BUF to fill when PROPS ask for `:wait-output'."
  (when (plist-get props :wait-output)
    (let ((deadline (+ (float-time) 2)))
      (while (and (= (buffer-size buf) 0) (< (float-time) deadline))
        (accept-process-output nil 0.02)))))

(defun gascity-audit--open (opener)
  "Open a view with OPENER; return the buffer it shows."
  (if (functionp opener)
      (if (commandp opener) (call-interactively opener) (funcall opener))
    (error "Bad opener %S" opener))
  (window-buffer (selected-window)))

(defun gascity-audit--eval-header (form)
  "Evaluate the `:eval' parts of mode-line construct FORM; return a string.
`format-mode-line' needs a live frame, so batch evaluates it by hand."
  (cond ((stringp form) form)
        ((and (consp form) (eq (car form) :eval)) (format "%s" (eval (cadr form) t)))
        ((and (symbolp form) form (boundp form))
         (gascity-audit--eval-header (symbol-value form)))
        ((consp form) (mapconcat #'gascity-audit--eval-header
                                 (seq-filter (lambda (x) (not (keywordp x))) form)
                                 ""))
        (t "")))

(defun gascity-audit--walk (buffer)
  "TAB to every thing of BUFFER and SPC-toggle it, then refresh with `g'.
Returns the number of things visited."
  (with-current-buffer buffer
    (let ((seen 0) (starts nil))
      (goto-char (point-min))
      (catch 'none
        (dotimes (_ 60)
          ;; A text view (costs, a log) has no things: nothing to walk.
          (condition-case nil (gascity-thing-forward 1)
            (user-error (throw 'none nil)))
          (unless (member (point) starts)
          (push (point) starts)
          (cl-incf seen)
            (when (get-text-property (point) 'beads-thing)
              (ignore-errors (gascity-thing-toggle))))))
      (gascity-audit--eval-header header-line-format)
      (when-let* ((g (keymap-lookup (current-local-map) "g")))
        (call-interactively g))
      (gascity-audit--eval-header header-line-format)
      seen)))

(defconst gascity-audit--host-only-rx "\\`/[^/:|]+:[^/:|]*:\\'"
  "A host-only TRAMP name: \"/method:host:\", no local part.")

(defconst gascity-audit--host-only-reported nil
  "Callers known to hand a host-only name to a file primitive.
Empty: `gascity-store--pump' did (fixed in 4b78993, it now uses the
pure `gascity-remote-prefix').  Add an entry only with a reported
finding behind it.")

(defvar gascity-audit--host-only-hits nil
  "(PRIMITIVE NAME CALLERS) of host-only-name calls seen, newest first.")

(defun gascity-audit--gascity-callers ()
  "Return the gascity functions on the stack (innermost first), tests excluded."
  (let (out)
    (mapbacktrace
     (lambda (_evald fn _args _flags)
       (when (and (symbolp fn)
                  (string-prefix-p "gascity-" (symbol-name fn))
                  (not (string-prefix-p "gascity-audit" (symbol-name fn)))
                  (not (string-prefix-p "gascity-test" (symbol-name fn))))
         (push fn out))))
    (nreverse out)))

(defun gascity-audit--host-only-advice (primitive)
  "Return an :around advice recording PRIMITIVE's host-only-name calls."
  (lambda (orig name &rest args)
    (when (and (stringp name) (string-match-p gascity-audit--host-only-rx name))
      (push (list primitive name (gascity-audit--gascity-callers))
            gascity-audit--host-only-hits))
    (apply orig name args)))

(defmacro gascity-audit--recording-host-only (&rest body)
  "Run BODY recording host-only-name file primitive calls."
  (declare (indent 0))
  `(let ((native-comp-enable-subr-trampolines nil) ; advice on primitives
         (advices (mapcar (lambda (p) (cons p (gascity-audit--host-only-advice p)))
                          gascity-audit--io-primitives)))
     (dolist (a advices) (advice-add (car a) :around (cdr a)))
     (unwind-protect (progn ,@body)
       (dolist (a advices) (advice-remove (car a) (cdr a))))))

(defun gascity-audit--unreported-host-only ()
  "Return the recorded host-only calls not from a reported caller."
  (seq-remove (lambda (hit)
                (seq-intersection (nth 2 hit) gascity-audit--host-only-reported))
              gascity-audit--host-only-hits))

(ert-deftest gascity-test-audit-render-guard-every-view ()
  "Every view, opened on a remote city from canned payloads, walked with
TAB, every thing toggled with SPC, refreshed with `g', its header line
evaluated: zero file I/O on a remote name (§8.3 R2, §8.4), and no file
primitive called on a host-only name outside the reported store site."
  (gascity-audit--with-remote-city
    (setq gascity-audit--host-only-hits nil)
    (gascity-test-with-render-guard
     (gascity-audit--recording-host-only
      (dolist (view gascity-audit-views)
        (let ((name (car view)) (opener (cadr view)))
          (unless (and (plist-get (cddr view) :pending) (not (commandp opener)))
            (ert-info ((format "view: %s" name))
              (let ((buf (gascity-audit--open opener)))
                (gascity-audit--settle buf (cddr view))
                (should (buffer-live-p buf))
                (should (> (buffer-size buf) 0))
                (let ((things (gascity-audit--walk buf)))
                  (unless (plist-get (cddr view) :text)
                    (should (> things 0))))
                (should (null gascity-test-render-guard-violations)))))))))
    (should (null gascity-test-render-guard-violations))
    ;; No file primitive on a bare "/method:host:" name, but for the
    ;; reported store site (`gascity-audit--host-only-reported').
    (should (null (gascity-audit--unreported-host-only)))))

(ert-deftest gascity-test-audit-every-view-read-its-fixtures ()
  "The guard test really rendered data: every read had a fixture, and
the views show their data, not error lines."
  (gascity-audit--with-remote-city
    (dolist (view gascity-audit-views)
      (let ((opener (cadr view)))
        (unless (and (plist-get (cddr view) :pending) (not (commandp opener)))
          (ert-info ((format "view: %s" (car view)))
            (let ((buf (gascity-audit--open opener)))
              (should-not (string-match-p "no fixture for"
                                          (with-current-buffer buf (buffer-string)))))))))
    (should (null gascity-audit--unserved))))

;;; The lighter with a live remote stream (§7.12, P5)

(defun gascity-audit--wait (pred &optional secs)
  "Pump timers and process output until PRED holds or SECS (3) pass."
  (let ((deadline (+ (float-time) (or secs 3))))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (funcall pred)))

(ert-deftest gascity-test-audit-lighter-with-remote-live-stream ()
  "With a remote city's cockpit open and its event stream live, events
re-render the cockpit and the lighter follows; showing or rebuilding
the lighter never reads gc, starts a process or touches a remote name."
  (let ((global-mode-string nil)
        (gascity-pulse--cities (make-hash-table :test 'equal))
        (gascity-live--streams (make-hash-table :test 'equal))
        (gascity-live-in-batch t)
        (gascity-live-enabled t)
        (gascity-live-debounce 0.05)
        (reads 0))
    (gascity-audit--with-remote-city
      (cl-letf* ((canned (symbol-function 'gascity-reader-read-async))
                 ((symbol-function 'gascity-reader-read-async)
                  (lambda (&rest args) (cl-incf reads) (apply canned args)))
                 ;; The stream's ssh pipe, played by a local shell that
                 ;; emits two events and stays up.
                 ((symbol-function 'gascity-live--ssh-p) (lambda (&rest _) t))
               ;; tmux host scripts: a harmless local shell stands in for
               ;; the ssh pipe (the mock host is no ssh host).
               ((symbol-function 'gascity-terminal--host-argv)
                (lambda (&rest _) (list "sh" "-c" "echo gascity-no-session")))
                 ((symbol-function 'gascity-live-command)
                  (lambda (&rest _)
                    (list "sh" "-c"
                          (concat "sleep 0.2; "
                                  "echo '{\"type\":\"session.woke\",\"seq\":1}'; "
                                  "echo '{\"type\":\"mail.sent\",\"seq\":2}'; "
                                  "exec sleep 5")))))
        (unwind-protect
            (progn
              (gascity-mode-line-mode 1)
              (gascity-test-with-render-guard
                (gascity-audit--open #'gascity-dashboard)
                (should (eq (plist-get (gascity-live-status
                                        (expand-file-name gascity-audit--root))
                                       :state)
                            'live))
                (let ((before reads))
                  ;; Two events arrive, the debounced batch invalidates
                  ;; the cockpit's reads, which re-read and re-render.
                  (should (gascity-audit--wait
                           (lambda () (> reads before))))
                  (should (gascity-audit--wait
                           (lambda ()
                             (let ((s (gethash (substring-no-properties
                                                (expand-file-name gascity-audit--root))
                                               gascity-live--streams)))
                               (and s (eql (gascity-live--stream-seq s) 2))))))))
              (should (null gascity-test-render-guard-violations))
              (should (string-match-p "\\` GC\\[ec@[^ ]+ [■▲●]"
                                      (substring-no-properties gascity-mode-line--string)))
              ;; Showing and rebuilding the lighter: no gc, no process, no
              ;; remote I/O.
              (gascity-test-with-render-guard
                (cl-letf (((symbol-function 'gascity-reader-read-async)
                           (lambda (&rest a) (error "Lighter read gc: %S" a)))
                          ((symbol-function 'gascity-reader-run-async)
                           (lambda (&rest a) (error "Lighter ran gc: %S" a)))
                          ((symbol-function 'gascity-reader-run)
                           (lambda (&rest a) (error "Lighter ran gc: %S" a)))
                          ((symbol-function 'gascity-store-fetch)
                           (lambda (&rest a) (error "Lighter fetched: %S" a)))
                          ((symbol-function 'make-process)
                           (lambda (&rest a) (error "Lighter spawned: %S" a)))
                          ((symbol-function 'process-file)
                           (lambda (&rest a) (error "Lighter ran: %S" a))))
                  (dotimes (_ 3)
                    (should (string-match-p
                             "GC\\["
                             (gascity-audit--eval-header global-mode-string))))
                  (gascity-mode-line-update)
                  (should (string-match-p "ec@" gascity-mode-line--string))))
              (should (null gascity-test-render-guard-violations)))
          (gascity-mode-line-mode -1)
          (gascity-live-stop-all))))))

;;; D9: input-free verbs that start a read, a view or a stream

;; The store's guard (`gascity-test-store-non-blocking-guard') covers
;; the verbs that start ONE gc action.  These verbs open a view, start
;; an on-demand read or a stream instead; the promise is the same: no
;; synchronous gc, no synchronous process, back in well under a second.

(defun gascity-audit--at (props thunk)
  "Call THUNK in a temp buffer whose only line carries text PROPS."
  (with-temp-buffer
    (setq default-directory (or (plist-get props 'dir) default-directory))
    (insert (apply #'propertize "row" props))
    (goto-char (point-min))
    (funcall thunk)))

(defun gascity-audit--start-verbs ()
  "Return (NAME . THUNK) for every input-free verb that starts reads,
views or streams rather than one action (prompts answered)."
  (let ((agent (gascity-audit--agent)))
    `((agent-detail-i
       . ,(lambda () (gascity-audit--at (list 'gascity-agent agent)
                                        #'gascity-polecat-detail-at-point)))
      (agent-attach-t
       . ,(lambda () (gascity-audit--at (list 'gascity-agent agent)
                                        #'gascity-tmux-at-point)))
      (agent-follow-f
       . ,(lambda () (with-temp-buffer
                       (setq-local gascity-section--agent agent)
                       (gascity-session-follow-log))))
      (runs-root-bead-b
       . ,(lambda () (gascity-audit--at (list 'gascity-bead "be-52m5"
                                              'gascity-run-rig "beads.el")
                                        #'gascity-runs-root-bead)))
      (rig-beads-j-b
       . ,(lambda () (cl-letf (((symbol-function 'beads-dashboard) #'ignore))
                       (gascity-rig-beads "beads.el"))))
      (runs-agent-detail-i
       . ,(lambda () (gascity-audit--at (list 'gascity-agent agent)
                                        #'gascity-runs-agent-detail)))
      (health-doctor-!
       . ,(lambda () (with-temp-buffer (gascity-health-mode) (gascity-health-doctor))))
      (health-doctor-fix-F
       . ,(lambda () (with-temp-buffer (gascity-health-mode) (gascity-health-doctor-fix))))
      (cities-visit-RET
       . ,(lambda ()
            (gascity-audit--at
             (list 'tabulated-list-id
                   `((city . "emacs-city") (dir . ,default-directory)))
             #'gascity-cities-visit)))
      (live-toggle-W . ,(lambda () (gascity-live-toggle) (gascity-live-toggle)))
      (live-reconnect-g . ,(lambda () (gascity-live-attach) (gascity-live-reconnect))))))

(defmacro gascity-audit--with-no-sync (&rest body)
  "Run BODY with every synchronous gc/process path signalling.
Bind `gascity-audit--sync' to the list of the calls attempted."
  (declare (indent 0))
  `(let ((gascity-audit--sync nil)
         (gascity-executable "true")
         ;; The mock method stands in for ssh (attach builds ssh argvs).
         (beads-remote-ssh-methods (cons "mock" beads-remote-ssh-methods))
         (gascity-live--streams (make-hash-table :test 'equal))
         (gascity-live-in-batch t))
     (cl-letf (((symbol-function 'gascity-reader-run)
                (lambda (args) (push (cons 'gc args) gascity-audit--sync)
                  (error "Synchronous gc run: %S" args)))
               ((symbol-function 'process-file)
                (lambda (prog &rest _) (push (cons 'process-file prog) gascity-audit--sync)
                  (error "Process-file %s" prog)))
               ((symbol-function 'call-process)
                (lambda (prog &rest _) (push (cons 'call-process prog) gascity-audit--sync)
                  (error "Call-process %s" prog)))
               ;; Streams: a harmless local process stands in for gc/ssh.
               ((symbol-function 'gascity-live-command)
                (lambda (&rest _) (list "sleep" "2")))
               ((symbol-function 'gascity-live--ssh-p) (lambda (&rest _) t))
               ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b))
               ((symbol-function 'beads-show) #'ignore)
               ((symbol-function 'completing-read) (lambda (&rest _) "answer"))
               ((symbol-function 'read-string) (lambda (&rest _) "answer")))
       (unwind-protect (progn ,@body)
         (gascity-live-stop-all)))))

(defvar gascity-audit--sync nil
  "Synchronous gc/process calls a verb attempted (see the guard macro).")

(defconst gascity-audit--start-verb-exempt nil
  "Start verbs knowingly exempt from the guard, with the reason.
Empty: tmux attach was the last (its synchronous tmux probes became one
asynchronous host script on the v3-terminal branch).")

(defun gascity-audit--check-start-verbs ()
  "Run every start verb; assert none blocks or runs anything synchronously."
  (dolist (verb (seq-remove (lambda (v) (assq (car v) gascity-audit--start-verb-exempt))
                            (gascity-audit--start-verbs)))
    (ert-info ((format "verb: %s" (car verb)))
      (gascity-store-clear)
      (let ((start (float-time)))
        (condition-case err
            (funcall (cdr verb))
          (error (ert-fail (list (car verb) err))))
        (should (< (- (float-time) start) 1.0)))
      (should (null gascity-audit--sync)))))

(ert-deftest gascity-test-audit-start-verbs-non-blocking-local ()
  "Input-free verbs that start views, reads or streams never run gc or a
process synchronously and return at once (D9, §8.5) — local city, cold
rig memo."
  (gascity-audit--with-remote-city
    (let ((default-directory gascity-audit--root))
      (gascity-audit--with-no-sync
        (let ((default-directory (file-name-as-directory temporary-file-directory)))
          (cl-letf (((symbol-function 'gascity-context-city-root)
                     (lambda (&optional _) default-directory))
                    ((symbol-function 'gascity-rigs-cached) #'ignore))
            (gascity-audit--check-start-verbs)))))))

(ert-deftest gascity-test-audit-start-verbs-non-blocking-remote ()
  "The same verbs on a remote city: no synchronous gc and no file I/O on
a remote name (R2) — starting a stream or a read is pure."
  (gascity-audit--with-remote-city
    (gascity-test-with-render-guard
      (gascity-audit--with-no-sync
        (gascity-audit--check-start-verbs)))
    (should (null gascity-test-render-guard-violations))))

;;; View fixes found by the audit

(ert-deftest gascity-test-audit-runs-root-bead-cold-memo-is-async ()
  "`b' on a run whose rig is not memoized reads the rig list through the
store (no synchronous `gc rig list') and opens the bead when it arrives."
  (let ((default-directory "/tmp/city/")
        (shown nil) (fetched nil))
    (cl-letf (((symbol-function 'gascity-rigs-cached) #'ignore)
              ((symbol-function 'gascity-reader-run)
               (lambda (args) (error "Synchronous gc: %S" args)))
              ((symbol-function 'gascity-rigs-remember) #'ignore)
              ((symbol-function 'gascity-store-fetch)
               (lambda (args callback &rest _)
                 (setq fetched args)
                 (cl-letf (((symbol-function 'gascity-beads--rig-store-cached)
                            (lambda (rig) (and (equal rig "beads.el") "/srv/beads.el/"))))
                   (funcall callback '((rigs . []))))))
              ((symbol-function 'gascity-beads--show-in-store)
               (lambda (id store) (setq shown (list id store)))))
      (gascity-audit--at (list 'gascity-bead "be-52m5" 'gascity-run-rig "beads.el")
                         #'gascity-runs-root-bead))
    (should (equal fetched '("rig" "list")))
    (should (equal shown '("be-52m5" "/srv/beads.el/")))))

(ert-deftest gascity-test-audit-log-follower-g ()
  "`g' in a followed log restarts an ended follower, never `revert-buffer'."
  (let ((spawns 0))
    (with-temp-buffer
      (gascity-log-mode)
      (should (eq (keymap-lookup gascity-log-mode-map "g") #'gascity-session-log-restart))
      (setq gascity-session--log-spawn (lambda () (cl-incf spawns)))
      (gascity-session-log-restart)
      (should (= spawns 1))
      (setq gascity-session--log-spawn nil)
      (should-error (gascity-session-log-restart) :type 'user-error))))

;;; Static scan: remote-capable file primitives reachable from callbacks

(defconst gascity-audit--io-primitives
  '(file-remote-p expand-file-name abbreviate-file-name file-exists-p
    file-directory-p project-current locate-dominating-file)
  "File-name primitives that may do TRAMP I/O on a remote name.
`file-remote-p' and `expand-file-name' are pure on a full directory
name but not on a host-only one (\"/method:host:\"), where TRAMP may
look up the remote home.")

(defconst gascity-audit--reviewed-callback-io
  '(;; `file-remote-p' on a full directory name (a stream root, a
    ;; buffer's pinned `default-directory'): pure.
    ((gascity-live--classify . file-remote-p) . "stream root, full dir")
    ((gascity-live--start . file-remote-p) . "stream root, full dir")
    ((gascity-live-command . file-remote-p) . "stream root, full dir")
    ((gascity-live--spawn . file-remote-p) . "stream root, full dir")
    ((gascity-live--ssh-p . file-remote-p) . "stream root, full dir")
    ((gascity-reader--command . file-remote-p) . "default-directory, full dir")
    ((gascity-reader-read-async . file-remote-p) . "default-directory, full dir")
    ((gascity-reader--read-async-ssh . file-remote-p) . "default-directory, full dir")
    ((gascity-reader--remote-dir-absent-p . file-remote-p) . "default-directory, full dir")
    ((gascity-remote-flush-file-cache . file-remote-p) . "full dir")
    ((gascity-remote-spawn-error-hint . file-remote-p) . "full dir")
    ;; The city-root walk: memoized per start directory; a timer only
    ;; ever hits the memo of a pinned root.  After
    ;; `gascity-context-clear-cache' the next tick walks synchronously
    ;; (bounded by `gascity-remote-sync-timeout') — reported.
    ((gascity-context-city-root . expand-file-name) . "memoized walk")
    ((gascity-context-city-root . locate-dominating-file) . "memoized walk")
    ;; The reader's bounded directory probe, reached from the live poll
    ;; (non-ssh methods) through `gascity-store-fetch': the store binds
    ;; `gascity-reader-skip-dir-probe' for a known-good directory, so it
    ;; only probes on a cold first read, like every store read.  The
    ;; static scan cannot see that binding.
    ((gascity-reader--remote-dir-absent-bounded-p . file-directory-p)
     . "live poll via the store: skipped for a known-good dir"))
  "Exactly the (CALLEE . PRIMITIVE) pairs the static scan finds reachable
from a timer, sentinel or filter, each with why it is acceptable.  A new
pair fails `gascity-test-audit-callback-file-io-reviewed' until reviewed
here; a pair that disappeared must be dropped, so the list stays true.
\(The store scheduler's `file-remote-p' on host names left in 4b78993.)")

(defun gascity-audit--forms (file)
  "Return the top-level forms of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (out)
      (condition-case nil
          (while t (push (read (current-buffer)) out))
        (end-of-file nil))
      (nreverse out))))

(defun gascity-audit--scan (dir)
  "Return the (CALLEE . PRIMITIVE) pairs reachable from callbacks in DIR.
A callback is a function handed to `run-at-time', `run-with-timer',
`run-with-idle-timer', `set-process-sentinel', `set-process-filter' or
the :filter/:sentinel of `make-process'/`make-pipe-process' in any
gascity-*.el of DIR.  From its body the scan follows calls to gascity
functions (up to 7 deep) and records, for each I/O primitive call, the
innermost function that makes it (the callback itself: `lambda')."
  (let* ((files (directory-files dir t "\\`gascity-.*\\.el\\'"))
         (defuns (make-hash-table))
         (pairs nil))
    (dolist (f files)
      (dolist (form (gascity-audit--forms f))
        (pcase form
          (`(,(or 'defun 'cl-defun 'defsubst) ,name ,_ . ,body)
           (puthash name body defuns)))))
    (cl-labels
        ((fn-body (f)
           (pcase f
             (`(function (lambda . ,rest)) (list (cons 'lambda rest)))
             (`(lambda . ,rest) (list (cons 'lambda rest)))
             (`(,(or 'function 'quote) ,(and s (pred symbolp)))
              (cons s (gethash s defuns)))))
         (scan (body owner seen)
           (when (consp body)
             (when (memq (car body) gascity-audit--io-primitives)
               (cl-pushnew (cons owner (car body)) pairs :test #'equal))
             (let ((head (car body)))
               (when (and (symbolp head) (gethash head defuns)
                          (string-prefix-p "gascity-" (symbol-name head))
                          (not (memq head seen)) (< (length seen) 7))
                 (scan (gethash head defuns) head (cons head seen))))
             (let ((x body))
               (while (consp x) (scan (car x) owner seen) (setq x (cdr x))))))
         (callback (f)
           (let ((b (fn-body f)))
             (when b
               (if (symbolp (car b))
                   (scan (cdr b) (car b) (list (car b)))
                 (scan b 'lambda nil)))))
         (walk (form)
           (when (consp form)
             (pcase form
               (`(,(or 'run-at-time 'run-with-timer 'run-with-idle-timer) ,_ ,_ ,f . ,_)
                (callback f))
               (`(,(or 'set-process-sentinel 'set-process-filter) ,_ ,f)
                (callback f)))
             (when (memq (car form) '(make-process make-pipe-process))
               (dolist (key '(:filter :sentinel))
                 (let ((f (plist-get (cdr form) key)))
                   (when f (callback f)))))
             (let ((x form))
               (while (consp x) (walk (car x)) (setq x (cdr x)))))))
      (dolist (f files)
        (dolist (form (gascity-audit--forms f))
          (walk form))))
    pairs))

(ert-deftest gascity-test-audit-callback-file-io-reviewed ()
  "Every remote-capable file primitive reachable from a timer, sentinel
or filter is reviewed (`gascity-audit--reviewed-callback-io'); in
particular none of `abbreviate-file-name', `file-exists-p' and
`project-current' is reachable from a callback at all (§8.3 R2)."
  (let* ((lisp (expand-file-name "../../.." gascity-audit--dir))
         (pairs (gascity-audit--scan lisp))
         (unreviewed (seq-remove (lambda (p) (assoc p gascity-audit--reviewed-callback-io))
                                 pairs)))
    (should (> (length pairs) 5))
    (should (null unreviewed))
    ;; The list is exact: no reviewed pair that no longer occurs.
    (should (null (seq-remove (lambda (r) (member (car r) pairs))
                              gascity-audit--reviewed-callback-io)))
    (should-not (seq-find (lambda (p) (memq (cdr p) '(abbreviate-file-name
                                                      file-exists-p project-current)))
                          pairs))))

(provide 'gascity-audit-test)
;;; gascity-audit-test.el ends here
