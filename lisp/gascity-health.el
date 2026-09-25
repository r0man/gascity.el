;;; gascity-health.el --- City health view and gc costs -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Two read-mostly views reached from the cockpit's `j' prefix:
;;
;; - `gascity-health' (`j h', dashboard-v3 §7.10): a vui view of the
;;   city's plumbing, one store read per section so one failure never
;;   blanks the others:
;;
;;     Supervisor   `gc status' controller + health
;;     Versions     `gc version'; bd/dolt versions from the last doctor
;;                  run (gc exposes them nowhere else)
;;     Store        `gc status' store_health, `gc dolt health' server
;;                  and databases, the session's store-size sparkline
;;     Rig stores   `gc rig status NAME' per rig
;;     Doctor       `gc doctor' on demand (`!'), `--fix' confirmed (`F')
;;
;;   `gc doctor' is slow (~40 s) and is never run on open or refresh:
;;   `!' starts it in the background, the header shows `running…', the
;;   rest of the view stays usable, and the result is cached in the
;;   store for the session (`ran 4m ago').  It runs under its own
;;   deadline (`gascity-health-doctor-timeout'), longer than the store's
;;   default read deadline.
;;
;; - `gascity-costs' (`j $', §5.2): `gc costs' output as text in a
;;   read-only buffer.  gc has no JSON mode for it (§11 gap 1), so the
;;   text is shown as gc prints it.
;;
;; Rendering is pure over store snapshots (§8.3 R2): no gc call, no
;; file operation on a remote name while a view renders.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-ui)
(require 'gascity-context)
(require 'gascity-reader)
(require 'gascity-store)
(require 'gascity-section)
(require 'gascity-dashboard)
(require 'gascity-pulse)

(declare-function gascity-action--confirm "gascity-action")
(declare-function gascity-rig-dashboard "gascity-rig")
(declare-function gascity-rig-list "gascity-tabulated")
(declare-function gascity-dolt-list "gascity-tabulated")

(defcustom gascity-health-doctor-timeout 300
  "Seconds before a `gc doctor' run is killed.
Doctor runs every check in sequence (~40 s on a small city, each check
bounded by gc's own one-minute budget), so it gets a longer deadline
than the store's `gascity-remote-async-timeout'."
  :type 'natnum
  :group 'gascity)

(defconst gascity-health-buffer-name "*gascity-health: %s*"
  "Base name of the health view, formatted with the city name.")

(defvar-local gascity-health--city nil
  "The city this health view shows.")

(defvar-local gascity-health--doctor-sub nil
  "This buffer's store subscription to the doctor entry.")

;;; Reads

(defconst gascity-health--doctor-args '("doctor")
  "Store key of the doctor result (kind `doctor': fresh until re-run).")

(defun gascity-health--doctor-result (result fix)
  "Return the doctor payload of `gascity-reader-run-async' RESULT, or a string.
Doctor exits non-zero when checks fail but still prints its report,
so the report is taken from stdout whatever the exit code; only an
unreadable stdout is an error (the returned string).  FIX marks the
payload as a `--fix' run."
  (let* ((stdout (plist-get result :stdout))
         (payload (and (stringp stdout)
                       (condition-case nil (gascity-reader-parse-json stdout)
                         (error nil)))))
    (if (and (consp payload) (assq 'results payload))
        (cons (cons 'gascity-fix fix) payload)
      (format "gc doctor%s failed: %s" (if fix " --fix" "")
              (or (gascity-ui-first-line (plist-get result :stderr))
                  (gascity-reader--error-envelope-message stdout)
                  (gascity-ui-first-line stdout)
                  (format "exit %s" (plist-get result :exit-code)))))))

(defun gascity-health--doctor-loader (fix)
  "Return the store loader running `gc doctor --json' (with `--fix' if FIX).
The loader's process is bounded by `gascity-health-doctor-timeout'."
  (lambda (resolve reject)
    (let* ((done nil) (timer nil)
           (settle (lambda (fn value)
                     (unless done
                       (setq done t)
                       (when (timerp timer) (cancel-timer timer))
                       (funcall fn value))))
           (proc (gascity-reader-run-async
                  (append '("doctor" "--json") (and fix '("--fix")))
                  (lambda (result)
                    (let ((payload (gascity-health--doctor-result result fix)))
                      (if (stringp payload)
                          (funcall settle reject payload)
                        (funcall settle resolve payload)))))))
      (unless done
        (setq timer
              (run-at-time gascity-health-doctor-timeout nil
                           (lambda ()
                             (when (process-live-p proc)
                               (ignore-errors (delete-process proc)))
                             (funcall settle reject
                                      (format "gc doctor timed out after %ss (killed)"
                                              gascity-health-doctor-timeout))))))
      proc)))

(defun gascity-health--rig-names (status)
  "Return the rig names of `gc status' payload STATUS (the HQ excluded)."
  (delq nil (mapcar (lambda (r) (and (not (alist-get 'hq r)) (alist-get 'name r)))
                    (append (alist-get 'rigs status) nil))))

(defun gascity-health--read-rig-stores (names resolve reject)
  "Read `gc rig status NAME' for each of NAMES through the store.
RESOLVE gets a list of (NAME . PAYLOAD) or (NAME :error MESSAGE), in
NAMES order, once every read settled; REJECT is never called (a failed
rig is a row of its own)."
  (ignore reject)
  (let ((force gascity-store-loader-force)
        (table (make-hash-table :test 'equal))
        (pending (length names)))
    (if (null names)
        (funcall resolve nil)
      (dolist (name names)
        (let ((settle (lambda (value)
                        (puthash name value table)
                        (setq pending (1- pending))
                        (when (zerop pending)
                          (funcall resolve
                                   (mapcar (lambda (n) (cons n (gethash n table)))
                                           names))))))
          (gascity-store-fetch (list "rig" "status" name)
                               settle
                               (lambda (err) (funcall settle (list :error err)))
                               :force force))))))

;;; Loads

(defun gascity-health--load (res)
  "Return store snapshot RES as a section load plist (see `gascity-ui-section')."
  (let ((status (plist-get res :status)))
    (cond ((eq status 'ready)
           (list :state 'ready :data (plist-get res :data)
                 :error (and (not (plist-get res :pending)) (plist-get res :error))
                 :timed-out (plist-get res :timed-out)))
          ((eq status 'error) (list :state 'error :error (plist-get res :error)))
          (t (list :state 'pending)))))

(defun gascity-health--data (ctx key)
  "Return the usable data of load KEY in CTX."
  (gascity-dashboard--data (plist-get (plist-get ctx :loads) key)))

;;; Pieces

(defun gascity-health--row (text &optional right &rest props)
  "Return a body row TEXT (indented), RIGHT right-aligned, with PROPS."
  (apply #'gascity-dashboard--row (concat "  " text) right props))

(defun gascity-health--version-of (doctor check regexp)
  "Return the version DOCTOR's CHECK message matches with REGEXP, or nil."
  (when-let* ((result (seq-find (lambda (r) (equal (alist-get 'name r) check))
                                (append (alist-get 'results doctor) nil)))
              (message (alist-get 'message result)))
    (and (string-match regexp message) (match-string 1 message))))

(defun gascity-health--doctor-data (ctx)
  "Return the cached doctor report of CTX, or nil."
  (plist-get (plist-get ctx :doctor) :data))

;;; Sections

(defun gascity-health--supervisor-lines (ctx)
  "Return the Supervisor section lines of CTX."
  (let* ((status (gascity-health--data ctx :status))
         (controller (alist-get 'controller status))
         (health (alist-get 'health status))
         (parts
          (and status
               (list
                (if (alist-get 'running controller)
                    (format "pid %s · %s" (or (alist-get 'pid controller) "?")
                            (or (alist-get 'mode controller) "controller"))
                  (concat (gascity-ui-glyph 'fail)
                          (propertize " controller down" 'face 'gascity-failed)))
                (cond ((not (alist-get 'usable health))
                       (concat (gascity-ui-glyph 'fail)
                               (propertize " unusable" 'face 'gascity-failed)))
                      ((alist-get 'degraded health)
                       (concat (gascity-ui-glyph 'watch)
                               (propertize
                                (format " degraded%s"
                                        (let ((sig (append (alist-get 'signals health) nil)))
                                          (if sig (format " (%s)" (string-join sig ", ")) "")))
                                'face 'gascity-warning)))
                      (t "health ok"))
                (if (alist-get 'suspended status)
                    (propertize "suspended" 'face 'gascity-suspended)
                  "not suspended")))))
    (gascity-dashboard--section-lines
     "supervisor" "Supervisor" nil
     (and parts (list (gascity-health--row (string-join parts " · "))))
     ctx :loads '(:status) :label "status")))

(defun gascity-health--versions-lines (ctx)
  "Return the Versions section lines of CTX."
  (let* ((version (gascity-health--data ctx :version))
         (status (gascity-health--data ctx :status))
         (doctor (gascity-health--doctor-data ctx))
         (gc (alist-get 'version version))
         (commit (alist-get 'commit version))
         (bd (gascity-health--version-of doctor "bd:check-bd"
                                         "version \\([0-9][^ ]*\\)"))
         (dolt (gascity-health--version-of doctor "dolt-version"
                                           "dolt \\([0-9][^ ]*\\)"))
         (store (alist-get 'beads_store (alist-get 'beads status)))
         (parts (delq nil
                      (list (and gc (propertize
                                     (concat "gc " gc)
                                     'help-echo (and commit (not (equal commit "unknown"))
                                                     (concat "commit " commit))))
                            (and bd (concat "bd " bd))
                            (and dolt (concat "dolt " dolt))
                            (and store (concat "store " store))))))
    (gascity-dashboard--section-lines
     "versions" "Versions" nil
     (and parts (list (gascity-health--row (string-join parts " · "))))
     ctx :loads '(:version) :label "version")))

(defun gascity-health--store-lines (ctx)
  "Return the Store section lines of CTX."
  (let* ((status (gascity-health--data ctx :status))
         (store (alist-get 'store_health (alist-get 'summary status)))
         (partial (gascity-dashboard--partial-errors status))
         (dolt (gascity-health--data ctx :dolt))
         (server (alist-get 'server dolt))
         (sizes (plist-get ctx :sizes))
         (rows nil))
    (cl-flet ((add (row) (push row rows)))
      (when store
        (add (gascity-health--row
              (concat (gascity-ui-fit (gascity-dashboard--path (alist-get 'path store)) 34)
                      " " (gascity-ui-fit (gascity-dashboard--bytes
                                           (alist-get 'size_bytes store))
                                          8)
                      " " (gascity-dashboard--dim
                           (concat
                            (if (and (numberp (alist-get 'live_rows store))
                                     (> (alist-get 'live_rows store) 0))
                                (format "%s/row · " (gascity-dashboard--ratio store))
                              "")
                            (format "threshold %s MB/row"
                                    (or (alist-get 'threshold_mb_per_row store) "?")))))))
        (when (alist-get 'warning store)
          (add (gascity-health--row
                (concat (gascity-ui-glyph 'watch) " "
                        (format "%s per row over threshold"
                                (gascity-dashboard--ratio store)))))))
      (dolist (p partial)
        (add (gascity-health--row
              (concat (gascity-ui-glyph 'partial) " "
                      (gascity-dashboard--dim (concat "store health: " p))))))
      (when server
        (add (gascity-health--row
              (cond
               ((not (alist-get 'running server))
                (concat (gascity-ui-glyph 'fail)
                        (propertize " dolt server not running" 'face 'gascity-failed)))
               ((not (alist-get 'reachable server))
                (concat (gascity-ui-glyph 'watch)
                        (propertize " dolt server unreachable" 'face 'gascity-warning)))
               (t (concat (gascity-ui-glyph 'ok)
                          (format " dolt :%s · pid %s · %s ms · %d databases"
                                  (or (alist-get 'port server) "?")
                                  (or (alist-get 'pid server) "?")
                                  (or (alist-get 'latency_ms server) "?")
                                  (length (alist-get 'databases dolt))))))
              nil
              'gascity-dashboard-target #'gascity-dolt-list))
        (let ((orphans (length (alist-get 'orphans dolt)))
              (zombies (or (alist-get 'zombie_count (alist-get 'processes dolt)) 0))
              (backups (alist-get 'backups dolt)))
          (when (> orphans 0)
            (add (gascity-health--row
                  (concat (gascity-ui-glyph 'watch)
                          (format " %d orphan database%s" orphans
                                  (if (= orphans 1) "" "s"))))))
          (when (and (numberp zombies) (> zombies 0))
            (add (gascity-health--row
                  (concat (gascity-ui-glyph 'watch)
                          (format " %d zombie dolt process%s" zombies
                                  (if (= zombies 1) "" "es"))))))
          (when (alist-get 'dolt_stale backups)
            (add (gascity-health--row
                  (concat (gascity-ui-glyph 'watch)
                          (format " backup stale%s"
                                  (let ((f (alist-get 'dolt_freshness backups)))
                                    (if (and f (not (string-empty-p f)))
                                        (concat " (" f ")") "")))))))))
      (when (cdr sizes)
        (add (gascity-health--row
              (concat (gascity-dashboard--dim "size (this session)  ")
                      (propertize (gascity-pulse-sparkline sizes)
                                  'help-echo
                                  (format "%d samples, %s … %s"
                                          (length sizes)
                                          (gascity-dashboard--bytes (apply #'min sizes))
                                          (gascity-dashboard--bytes (apply #'max sizes)))))))))
    (gascity-dashboard--section-lines
     "store" "Store"
     (and partial (string-trim-left
                   (gascity-ui-partial-mark (string-join partial "\n"))))
     (nreverse rows)
     ctx :loads '(:status :dolt) :label "status")))

(defun gascity-health--rig-state (payload dbs)
  "Return (LEVEL . TEXT) for rig status PAYLOAD given dolt database names DBS.
DBS is nil when `gc dolt health' has not answered."
  (let* ((rig (alist-get 'rig payload))
         (beads (alist-get 'beads rig)))
    (cond ((alist-get 'suspended rig) (cons 'idle "suspended"))
          ((and beads (not (equal beads "initialized")))
           (cons 'watch (format "beads %s" beads)))
          ((and dbs (not (member (alist-get 'prefix rig) dbs)))
           (cons 'watch "no dolt database"))
          (dbs (cons 'ok "dolt ok"))
          (t (cons 'ok (format "beads %s" (or beads "?")))))))

(defun gascity-health--rig-drawer (payload)
  "Return the drawer lines of rig status PAYLOAD."
  (let* ((rig (alist-get 'rig payload))
         (agents (append (alist-get 'agents payload) nil)))
    (cons (format "prefix %s%s · agents %d/%d running"
                  (or (alist-get 'prefix rig) "?")
                  (if (alist-get 'default_branch rig)
                      (format " · branch %s" (alist-get 'default_branch rig))
                    "")
                  (seq-count (lambda (a) (alist-get 'running a)) agents)
                  (length agents))
          (mapcar (lambda (a)
                    (format "%s  %s%s" (or (alist-get 'qualified_name a)
                                           (alist-get 'name a))
                            (or (alist-get 'status a) "?")
                            (if (alist-get 'draining a) " · draining" "")))
                  agents))))

(defun gascity-health--rigs-lines (ctx)
  "Return the Rig stores section lines of CTX."
  (let* ((rigs (gascity-health--data ctx :rigs))
         (dbs (mapcar (lambda (d) (alist-get 'name d))
                      (alist-get 'databases (gascity-health--data ctx :dolt))))
         (groups
          (mapcar
           (lambda (entry)
             (let* ((name (car entry))
                    (payload (cdr entry))
                    (err (and (eq (car-safe payload) :error) (cadr payload))))
               (if err
                   (list (gascity-health--row
                          (concat (gascity-ui-glyph 'fail) " " (gascity-ui-fit name 14) " "
                                  (gascity-dashboard--dim
                                   (concat "gc rig status: "
                                           (or (gascity-ui-first-line err) "failed"))))
                          nil 'gascity-rig name))
                 (let* ((rig (alist-get 'rig payload))
                        (state (gascity-health--rig-state payload dbs))
                        (path (alist-get 'path rig)))
                   (gascity-dashboard--object-row
                    (concat "rig:" name)
                    (concat "  " (gascity-ui-glyph (car state)) " "
                            (gascity-ui-fit name 14) " "
                            (gascity-dashboard--dim
                             (gascity-ui-fit (gascity-dashboard--path path) 32)))
                    (if (eq (car state) 'ok)
                        (gascity-dashboard--dim (cdr state))
                      (propertize (cdr state) 'face (if (eq (car state) 'watch)
                                                        'gascity-warning
                                                      'gascity-dim)))
                    (lambda () (gascity-health--rig-drawer payload))
                    'gascity-rig name
                    'gascity-rig-dir path)))))
           rigs)))
    (gascity-dashboard--section-lines
     "rig-stores" "Rig stores"
     (and rigs (number-to-string (length rigs)))
     (apply #'append groups)
     ctx :loads '(:rigs) :label "rig status")))

(defun gascity-health--check-level (result)
  "Return the glyph level of doctor check RESULT: `ok', `watch' or `fail'."
  (pcase (alist-get 'status result)
    ("ok" 'ok)
    ("warning" 'watch)
    (_ 'fail)))

(defun gascity-health--check-drawer (result)
  "Return the drawer lines of doctor check RESULT."
  (append (list (or (alist-get 'message result) ""))
          (and (alist-get 'fix_hint result)
               (list (concat "fix: " (alist-get 'fix_hint result))))
          (let ((details (append (alist-get 'details result) nil)))
            (append (seq-take details 8)
                    (and (> (length details) 8)
                         (list (format "… %d more" (- (length details) 8))))))))

(defun gascity-health--check-row (result indent)
  "Return the row (and open drawer) of doctor check RESULT at INDENT."
  (let ((name (or (alist-get 'name result) "?")))
    (gascity-dashboard--object-row
     (concat "check:" name)
     (concat indent (gascity-ui-glyph (gascity-health--check-level result)) " "
             (gascity-ui-fit name 28) " "
             (gascity-dashboard--dim (gascity-ui-fit (or (alist-get 'severity result) "") 9))
             " " (gascity-ui-truncate (or (alist-get 'message result) "")
                                      (max 10 (- gascity-dashboard--width
                                                 (length indent) 41))))
     nil
     (lambda () (gascity-health--check-drawer result))
     'gascity-health-check name)))

(defun gascity-health--doctor-summary (snapshot now)
  "Return the Doctor header summary for store SNAPSHOT at NOW."
  (let* ((data (plist-get snapshot :data))
         (ran (and data (plist-get snapshot :fetched-at)
                   (format "ran %s ago"
                           (gascity-ui-duration (- now (plist-get snapshot :fetched-at))))))
         (counts (and data
                      (concat
                       (format "%s passed · %s warned · %s failed"
                               (or (alist-get 'passed data) 0)
                               (or (alist-get 'warned data) 0)
                               (or (alist-get 'failed data) 0))
                       (let ((fixed (alist-get 'fixed data)))
                         (if (and (numberp fixed) (> fixed 0))
                             (format " · %d fixed" fixed) ""))))))
    (cond
     ((plist-get snapshot :pending)
      (string-join (delq nil (list "running…" ran)) " · "))
     (data (concat counts " · " ran
                   (gascity-ui-partial-mark (plist-get snapshot :error))))
     ((plist-get snapshot :error) nil)
     (t "not run"))))

(defun gascity-health--doctor-lines (ctx)
  "Return the Doctor section lines of CTX (from the cached report)."
  (let* ((snapshot (plist-get ctx :doctor))
         (data (plist-get snapshot :data))
         (results (append (alist-get 'results data) nil))
         (bad (seq-remove (lambda (r) (eq (gascity-health--check-level r) 'ok)) results))
         (bad (append (seq-filter (lambda (r) (eq (gascity-health--check-level r) 'fail)) bad)
                      (seq-remove (lambda (r) (eq (gascity-health--check-level r) 'fail)) bad)))
         (ok (seq-filter (lambda (r) (eq (gascity-health--check-level r) 'ok)) results))
         (expanded (member "doctor-ok" (plist-get gascity-dashboard--view :expanded)))
         (body
          (cond
           (data
            (append
             (apply #'append (mapcar (lambda (r) (gascity-health--check-row r "  ")) bad))
             (and ok
                  (cons (gascity-health--row
                         (concat (gascity-ui-glyph (if expanded 'expanded 'folded))
                                 (format " %d checks ok" (length ok)))
                         nil
                         'beads-thing (gascity-dashboard--thing
                                       'fold "doctor-ok"
                                       (lambda ()
                                         (gascity-dashboard--flip :expanded "doctor-ok"))))
                        (and expanded
                             (apply #'append
                                    (mapcar (lambda (r) (gascity-health--check-row r "    "))
                                            ok)))))))
           ((and (plist-get snapshot :error) (not (plist-get snapshot :pending)))
            (list (gascity-health--row
                   (concat (gascity-ui-glyph 'fail) " "
                           (gascity-dashboard--dim
                            (format "%s   ! retry"
                                    (or (gascity-ui-first-line (plist-get snapshot :error))
                                        "gc doctor failed")))))))))
         (summary (gascity-health--doctor-summary snapshot (plist-get ctx :now))))
    (gascity-dashboard--section-lines
     "doctor" "Doctor" summary body ctx
     :hint "! run  F run --fix")))

(defun gascity-health--overall (ctx)
  "Return the overall (LEVEL . WORD) of CTX for the top line."
  (let* ((status (gascity-health--data ctx :status))
         (controller (alist-get 'controller status))
         (health (alist-get 'health status))
         (store (alist-get 'store_health (alist-get 'summary status)))
         (server (alist-get 'server (gascity-health--data ctx :dolt)))
         (doctor (gascity-health--doctor-data ctx))
         (rigs (gascity-health--data ctx :rigs))
         (dbs (mapcar (lambda (d) (alist-get 'name d))
                      (alist-get 'databases (gascity-health--data ctx :dolt))))
         (rig-levels (mapcar (lambda (e)
                               (if (eq (car-safe (cdr e)) :error)
                                   'fail
                                 (car (gascity-health--rig-state (cdr e) dbs))))
                             rigs)))
    (cond
     ((null status) nil)
     ((or (not (alist-get 'running controller))
          (not (alist-get 'usable health))
          (and server (not (alist-get 'running server)))
          (and (numberp (alist-get 'failed doctor)) (> (alist-get 'failed doctor) 0))
          (memq 'fail rig-levels))
      (cons 'fail "attention"))
     ((or (alist-get 'degraded health)
          (alist-get 'warning store)
          (gascity-dashboard--partial-errors status)
          (and server (not (alist-get 'reachable server)))
          (and (numberp (alist-get 'warned doctor)) (> (alist-get 'warned doctor) 0))
          (memq 'watch rig-levels))
      (cons 'watch "watch"))
     (t (cons 'ok "ok")))))

(defun gascity-health--top-line (ctx)
  "Return the decoration line `Health  CITY @host   ● ok' of CTX."
  (let* ((status (gascity-health--data ctx :status))
         (city (or (alist-get 'city_name status) (plist-get ctx :city) "?"))
         (host (file-remote-p default-directory 'host))
         (offline (and host (gascity-store-offline-p)))
         (overall (gascity-health--overall ctx)))
    (gascity-ui-right-align
     (concat (propertize "Health" 'face 'gascity-header) "  "
             (propertize city 'face 'gascity-city)
             (if host (concat " " (gascity-dashboard--dim (concat "@" host))) ""))
     (cond
      ;; The store paused this host (§8.3 R5): one state, not an error
      ;; per section.
      (offline (propertize (concat (gascity-ui-glyph 'idle)
                                   (propertize (concat " offline @" host)
                                               'face 'gascity-failed))
                           'help-echo
                           (or (plist-get (gascity-store-host-status) :reason)
                               "host unreachable; retrying")))
      (overall (concat (gascity-ui-glyph (car overall)) " " (cdr overall)))
      (t ""))
     gascity-dashboard--width)))

(defun gascity-health--lines (ctx)
  "Return every health view line for render context CTX."
  (let ((gascity-dashboard--view (plist-get ctx :view)))
    (append (list (gascity-health--top-line ctx))
            (gascity-health--supervisor-lines ctx)
            (gascity-health--versions-lines ctx)
            (gascity-health--store-lines ctx)
            (gascity-health--rigs-lines ctx)
            (gascity-health--doctor-lines ctx))))

;;; Component

(vui-defcomponent gascity-health-app ()
  "Root component of the health view (dashboard-v3 §7.10)."
  :state ((refresh-tick 0)
          (collapsed nil)
          (drawers nil)
          (expanded nil))
  :render
  (let* ((status-res (gascity-store-use '("status") :tick refresh-tick))
         (version-res (gascity-store-use '("version") :tick refresh-tick))
         (dolt-res (gascity-store-use '("dolt" "health") :tick refresh-tick))
         (status (and (eq (plist-get status-res :status) 'ready)
                      (plist-get status-res :data)))
         (names (gascity-health--rig-names status))
         (rigs-res (gascity-store-use
                    (and status (list "rig" "status" :stores names))
                    :tick refresh-tick
                    :loader (lambda (resolve reject)
                              (gascity-health--read-rig-stores names resolve reject))))
         (loads (list :status (gascity-health--load status-res)
                      :version (gascity-health--load version-res)
                      :dolt (gascity-health--load dolt-res)
                      :rigs (if status
                                (gascity-health--load rigs-res)
                              (gascity-health--load status-res)))))
    (when status
      (gascity-pulse-record-store-size default-directory status))
    (vui-text
     (string-join
      (gascity-health--lines
       (list :city gascity-health--city
             :now (float-time)
             :loads loads
             :doctor (or (gascity-store-get gascity-health--doctor-args) nil)
             :sizes (gascity-pulse-store-sizes default-directory)
             :view (list :collapsed collapsed :drawers drawers :expanded expanded)))
      "\n"))))

(defun gascity-health--rerender (buffer)
  "Re-render the health view in BUFFER from what is in hand (no read)."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let* ((root (gascity-dashboard--root)))
        (vui--rerender-instance root)))))

;;; Commands

(defun gascity-health-refresh ()
  "Re-read every health section (doctor excepted: `!' runs it)."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No health view to refresh here")))

(defun gascity-health--doctor-start (fix)
  "Start `gc doctor' (with `--fix' when FIX) for this buffer's city.
Returns at once; the Doctor section shows `running…' until it ends."
  (let ((buffer (current-buffer))
        (city (or gascity-health--city (gascity-context-city-name) "city")))
    (if (plist-get (gascity-store-get gascity-health--doctor-args) :pending)
        (message "gc doctor is already running for %s" city)
      (gascity-store-fetch
       gascity-health--doctor-args
       (lambda (data)
         (message "Doctor %s%s: %s passed · %s warned · %s failed%s"
                  city (if fix " --fix" "")
                  (alist-get 'passed data) (alist-get 'warned data)
                  (alist-get 'failed data)
                  (let ((fixed (alist-get 'fixed data)))
                    (if (and (numberp fixed) (> fixed 0)) (format " · %d fixed" fixed) "")))
         (gascity-health--rerender buffer))
       (lambda (err)
         (message "%s" (or (gascity-ui-first-line err) "gc doctor failed"))
         (gascity-health--rerender buffer))
       :loader (gascity-health--doctor-loader fix)
       :force t)
      (gascity-health--rerender buffer)
      (message "Running gc doctor%s for %s…" (if fix " --fix" "") city))))

(defun gascity-health-doctor ()
  "Run `gc doctor' in the background (`!'); the view stays usable."
  (interactive)
  (gascity-health--doctor-start nil))

(defun gascity-health-doctor-fix ()
  "Run `gc doctor --fix' after confirmation (`F'), in the background."
  (interactive)
  (when (gascity-action--confirm "Run gc doctor --fix in %s? "
                                 (or gascity-health--city
                                     (gascity-context-city-name) "this city"))
    (gascity-health--doctor-start t)))

(defconst gascity-health--section-targets
  '(("store" . gascity-dolt-list)
    ("rig-stores" . gascity-rig-list)
    ("doctor" . gascity-health-doctor))
  "What RET on a health section header does.")

(defun gascity-health-activate ()
  "Act on the thing at point: a rig opens its dashboard (RET)."
  (interactive)
  (let ((section (get-text-property (point) 'gascity-dashboard-section))
        (target (get-text-property (point) 'gascity-dashboard-target))
        (rig (get-text-property (point) 'gascity-rig))
        (check (get-text-property (point) 'gascity-health-check)))
    (cond
     ((and section (assoc section gascity-health--section-targets))
      (call-interactively (cdr (assoc section gascity-health--section-targets))))
     (target (call-interactively target))
     (rig (gascity-rig-dashboard rig))
     (check (beads-thing-toggle))
     (t (user-error "Nothing to act on here")))))

(defvar-keymap gascity-health-mode-map
  :doc "Keymap for `gascity-health-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-health-refresh
  "!"   #'gascity-health-doctor
  "F"   #'gascity-health-doctor-fix
  "l"   #'gascity-dashboard-rig-log
  "RET" #'gascity-health-activate)

(define-derived-mode gascity-health-mode gascity-section-mode "GC-Health"
  "Major mode for the city health view (dashboard-v3 §7.10).

`!' runs `gc doctor' in the background, `F' runs `gc doctor --fix'
after confirmation; `g' re-reads everything else.

\\{gascity-health-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t))

;;;###autoload
(defun gascity-health ()
  "Show the health of this city: supervisor, versions, stores, doctor."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
         (city (or (gascity-context-city-name dir) "city"))
         (buf (gascity-view-get-buffer-create
               (format gascity-health-buffer-name city) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-health-mode)
        (gascity-health-mode))
      (setq gascity-health--city city)
      (unless gascity-health--doctor-sub
        (setq gascity-health--doctor-sub
              (gascity-store-subscribe
               gascity-health--doctor-args
               (lambda (_snapshot) (gascity-health--rerender buf))
               ;; A refetch after a blanket invalidation runs doctor
               ;; itself, never a plain `gc doctor' read.
               :loader (gascity-health--doctor-loader nil)
               :buffer buf))))
    (unless (gascity-section-refresh-instance buf)
      (save-window-excursion
        (vui-mount (vui-component 'gascity-health-app) (buffer-name buf))))
    (pop-to-buffer buf)))

;;; Costs (`j $')

(defconst gascity-costs-buffer-name "*gascity-costs: %s*"
  "Base name of the `gc costs' buffer, formatted with the city name.")

(defun gascity-costs--fill (buffer text &optional error)
  "Show TEXT (gc's output) in costs BUFFER; ERROR marks a failure line."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (line (line-number-at-pos)))
        (erase-buffer)
        (insert (if error
                    (concat (gascity-ui-glyph 'fail) " "
                            (gascity-dashboard--dim (concat text "   g retry")))
                  text))
        (unless (bolp) (insert "\n"))
        (goto-char (point-min))
        (forward-line (1- line))
        (setq-local gascity-costs--at (float-time))))))

(defvar-local gascity-costs--at nil
  "When this costs buffer last got gc's answer.")

(defun gascity-costs-refresh ()
  "Re-run `gc costs' in the background for this buffer's city (`g')."
  (interactive)
  (let ((buffer (current-buffer)))
    (when (= (buffer-size) 0)
      (let ((inhibit-read-only t))
        (insert (gascity-dashboard--dim "…") "\n")))
    (gascity-store-action
     '("costs")
     :target "gascity-costs"
     :invalidate nil :echo nil
     :on-success (lambda (out) (gascity-costs--fill buffer (or out "")))
     :on-error (lambda (msg) (gascity-costs--fill buffer msg t)))))

(defun gascity-costs--header-line ()
  "Return the costs buffer header line (pure)."
  (concat " " (propertize "gc costs" 'face 'gascity-header)
          "  " (propertize (or (gascity-context-city-name) "") 'face 'gascity-city)
          (if gascity-costs--at
              (gascity-dashboard--dim
               (format "  ↻ %s ago" (gascity-ui-duration (- (float-time) gascity-costs--at))))
            "")
          (gascity-dashboard--dim "   list-price estimates · g refresh")))

(defvar-keymap gascity-costs-mode-map
  :doc "Keymap for `gascity-costs-mode'."
  :parent special-mode-map
  "g" #'gascity-costs-refresh
  "?" 'gascity-dispatch
  "j" 'gascity-jump-prefix)

(define-derived-mode gascity-costs-mode special-mode "GC-Costs"
  "Major mode showing `gc costs' output as text (dashboard-v3 §5.2).
\\{gascity-costs-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format '(:eval (gascity-costs--header-line))))

;;;###autoload
(defun gascity-costs ()
  "Show `gc costs' (recorded usage by run) for this city (`j $').
gc prints a text table; it is shown as-is, read in the background."
  (interactive)
  (let* ((dir (beads-prefix-invocation-directory))
         (city (or (gascity-context-city-name dir) "city"))
         (buf (gascity-view-get-buffer-create
               (format gascity-costs-buffer-name city) dir)))
    (with-current-buffer buf
      (unless (derived-mode-p 'gascity-costs-mode)
        (gascity-costs-mode))
      (gascity-costs-refresh))
    (pop-to-buffer buf)))

(provide 'gascity-health)
;;; gascity-health.el ends here
