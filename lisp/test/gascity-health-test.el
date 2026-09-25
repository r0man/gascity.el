;;; gascity-health-test.el --- ERT tests for Health, Cities, costs, lighter -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 P4 (Health §7.10, Cities §7.11, `j $' costs) and P5
;; (mode-line lighter §7.12, store-size sparkline).  Pure tests: the gc
;; boundary (`gascity-reader-read-async' / `gascity-reader-run-async')
;; answers from the captured payloads in fixtures/v3.  Includes the
;; render guard over the health view with a remote directory and the
;; "lighter never runs gc" guard (P5 acceptance).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

;;; Fixtures

(defconst gascity-health-test--dir
  (expand-file-name "fixtures/v3/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the captured gc payloads.")

(defun gascity-health-test--text (name)
  "Return fixture NAME as a string."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name gascity-health-test--dir))
    (buffer-string)))

(defun gascity-health-test--json (name)
  "Return fixture NAME decoded as the reader decodes gc JSON."
  (gascity-reader-parse-json (gascity-health-test--text name)))

(defun gascity-health-test--read (args callback &optional errback &rest _)
  "Canned `gascity-reader-read-async': answer ARGS from the emacs-city fixtures.
Calls CALLBACK synchronously; ERRBACK for an unknown read."
  (let ((args (seq-drop-while (lambda (a) (member a '("--city")))
                              (remove "--json" args))))
    (pcase args
      (`("status") (funcall callback (gascity-health-test--json "emacs-city.status.json")))
      (`("version") (funcall callback (gascity-health-test--json "emacs-city.version.json")))
      (`("dolt" "health")
       (funcall callback (gascity-health-test--json "emacs-city.dolt-health.json")))
      (`("rig" "status" ,rig)
       (funcall callback (gascity-health-test--json
                          (format "emacs-city.rig-status-%s.json" rig))))
      (`("cities") (funcall callback (gascity-health-test--json "cities.json")))
      (`("mail" "count")
       (funcall callback (gascity-health-test--json "emacs-city.mail-count.json")))
      (_ (when errback (funcall errback (format "unexpected read %S" args))))))
  nil)

(defvar gascity-health-test--doctor-calls nil
  "Parked `gascity-reader-run-async' calls: (ARGS CALLBACK), newest first.")

(defmacro gascity-health-test--with-health (dir &rest body)
  "Mount the health view in DIR on canned reads and run BODY in its buffer.
`gc doctor' calls are parked in `gascity-health-test--doctor-calls'."
  (declare (indent 1))
  `(let ((vui-render-delay nil)
         (gascity-store-synchronous-delivery t)
         (gascity-health-test--doctor-calls nil)
         (buf (get-buffer-create "*gascity-health-test*")))
     (cl-letf (((symbol-function 'gascity-reader-read-async)
                #'gascity-health-test--read)
               ((symbol-function 'gascity-reader-run-async)
                (lambda (args callback)
                  (push (list args callback) gascity-health-test--doctor-calls)
                  nil)))
       (unwind-protect
           (save-window-excursion
             (with-current-buffer buf
               (setq default-directory ,dir)
               (gascity-health-mode)
               (setq gascity-health--city "emacs-city")
               (setq gascity-health--doctor-sub
                     (gascity-store-subscribe
                      gascity-health--doctor-args
                      (lambda (_) (gascity-health--rerender buf))
                      :buffer buf)))
             (vui-mount (vui-component 'gascity-health-app) (buffer-name buf))
             (with-current-buffer buf ,@body))
         (kill-buffer buf)))))

(defun gascity-health-test--doctor-result (&optional exit-code)
  "Return a run-async result carrying the doctor fixture, exiting EXIT-CODE."
  (list :exit-code (or exit-code 0)
        :stdout (gascity-health-test--text "bright-lights.doctor.json")
        :stderr ""))

(defun gascity-health-test--line (regexp)
  "Return the buffer line matching REGEXP, or nil."
  (save-excursion
    (goto-char (point-min))
    (and (re-search-forward regexp nil t)
         (buffer-substring-no-properties (line-beginning-position)
                                         (line-end-position)))))

;;; Health view (§7.10)

(ert-deftest gascity-test-health-renders-sections ()
  "The health view renders every section from real payloads, in order."
  (gascity-health-test--with-health "/tmp/"
    (let ((text (buffer-string)))
      (should (string-match-p "\\`Health  emacs-city" text))
      (let ((pos (mapcar (lambda (title) (string-match (concat "^" title) text))
                         '("Supervisor" "Versions" "Store" "Rig stores" "Doctor"))))
        (should (seq-every-p #'numberp pos))
        (should (equal pos (sort (copy-sequence pos) #'<))))
      (should (gascity-health-test--line "pid 22262 · supervisor · health ok · not suspended"))
      (should (gascity-health-test--line "gc 1.4\\.2 · store NativeDoltStore"))
      (should (gascity-health-test--line "~/emacs-city/\\.beads/dolt +168 MB"))
      (should (gascity-health-test--line "● dolt :37081 · pid 3146 · [0-9]+ ms · 3 databases"))
      (should (gascity-health-test--line "● beads\\.el .*dolt ok"))
      (should (gascity-health-test--line "● gascity\\.el .*dolt ok"))
      ;; Doctor never runs on open.
      (should (null gascity-health-test--doctor-calls))
      (should (gascity-health-test--line "^Doctor  not run.*! run  F run --fix"))
      ;; No apology line.
      (should-not (string-match-p "not exposed\\|no JSON\\|unavailable" text)))))

(ert-deftest gascity-test-health-doctor-on-demand ()
  "`!' starts doctor async: header `running…', then the cached report with
`ran … ago', failed/warned checks one row each, ok checks folded, and the
bd/dolt versions it carries."
  (gascity-health-test--with-health "/tmp/"
    (gascity-health-doctor)
    (should (= (length gascity-health-test--doctor-calls) 1))
    (should (equal (car (car gascity-health-test--doctor-calls)) '("doctor" "--json")))
    (should (gascity-health-test--line "^Doctor  running…"))
    ;; The rest of the view is still there and usable.
    (should (gascity-health-test--line "● beads\\.el"))
    ;; A second `!' while running starts nothing.
    (gascity-health-doctor)
    (should (= (length gascity-health-test--doctor-calls) 1))
    (funcall (nth 1 (car gascity-health-test--doctor-calls))
             (gascity-health-test--doctor-result))
    (should (gascity-health-test--line
             "^Doctor  88 passed · 5 warned · 0 failed · ran [0-9]+s ago"))
    (should (gascity-health-test--line "▲ formula-requirements +blocking"))
    (should (gascity-health-test--line "▲ order-firing-current"))
    (should (gascity-health-test--line "▸ [0-9]+ checks ok"))
    (should (gascity-health-test--line "gc 1\\.4\\.2 · bd 1\\.3\\.0 · dolt 2\\.3\\.5"))
    ;; SPC on the fold expands the ok checks in place.
    (goto-char (point-min))
    (re-search-forward "▸ [0-9]+ checks ok")
    (goto-char (match-beginning 0))
    (gascity-thing-toggle)
    (should (gascity-health-test--line "▾ [0-9]+ checks ok"))
    (should (gascity-health-test--line "● city-structure"))
    ;; SPC on a check row opens its drawer (fix hint / details).
    (goto-char (point-min))
    (re-search-forward "▲ order-firing-current")
    (goto-char (match-beginning 0))
    (gascity-thing-toggle)
    (should (gascity-health-test--line "│ dolt-health: last fired"))
    ;; A refresh re-reads everything but doctor, and keeps its report.
    (gascity-health-refresh)
    (should (= (length gascity-health-test--doctor-calls) 1))
    (should (gascity-health-test--line "^Doctor  88 passed"))))

(ert-deftest gascity-test-health-doctor-failing-exit-keeps-report ()
  "Doctor exits non-zero when checks fail; its report is still used."
  (let* ((failing (gascity-health-test--doctor-result 1))
         (payload (gascity-health--doctor-result failing nil)))
    (should (consp payload))
    (should (= (alist-get 'passed payload) 88)))
  (let ((err (gascity-health--doctor-result
              '(:exit-code 1 :stdout "" :stderr "gc: no city here\n") nil)))
    (should (stringp err))
    (should (string-match-p "no city here" err))))

(ert-deftest gascity-test-health-doctor-error-and-failed-rows ()
  "A failed check renders `■ name  severity  message' before warnings;
a doctor error with no report renders one `■' line."
  (gascity-health-test--with-health "/tmp/"
    (gascity-health-doctor)
    (funcall (nth 1 (car gascity-health-test--doctor-calls))
             '(:exit-code 1 :stdout "garbage" :stderr "boom\n"))
    (should (gascity-health-test--line "■ gc doctor failed: boom"))
    (should (string-match-p "attention\\|ok\\|watch" (gascity-health-test--line "^Health")))
    (let* ((report (gascity-health-test--json "bright-lights.doctor.json"))
           (results (append (alist-get 'results report) nil))
           (bad `((name . "city-config") (status . "error") (severity . "blocking")
                  (message . "city.toml broken"))))
      (setf (alist-get 'results report) (vconcat (cons bad results)))
      (setf (alist-get 'failed report) 1)
      (gascity-health-doctor)
      (funcall (nth 1 (car gascity-health-test--doctor-calls))
               (list :exit-code 1 :stdout (json-encode report) :stderr ""))
      (should (gascity-health-test--line "1 failed"))
      (let ((fail (gascity-health-test--line "■ city-config +blocking +city\\.toml broken"))
            (fail-pos (save-excursion (goto-char (point-min))
                                      (re-search-forward "■ city-config")))
            (warn-pos (save-excursion (goto-char (point-min))
                                      (re-search-forward "▲ formula-requirements"))))
        (should fail)
        (should (< fail-pos warn-pos)))
      (should (string-match-p "■ attention" (gascity-health-test--line "^Health"))))))

(ert-deftest gascity-test-health-doctor-fix-confirms ()
  "`F' asks first; declined runs nothing, accepted runs `doctor --fix'."
  (gascity-health-test--with-health "/tmp/"
    (cl-letf (((symbol-function 'gascity-action--confirm) (lambda (&rest _) nil)))
      (gascity-health-doctor-fix))
    (should (null gascity-health-test--doctor-calls))
    (cl-letf (((symbol-function 'gascity-action--confirm) (lambda (&rest _) t)))
      (gascity-health-doctor-fix))
    (should (equal (car (car gascity-health-test--doctor-calls))
                   '("doctor" "--json" "--fix")))))

(ert-deftest gascity-test-health-doctor-deadline ()
  "A doctor run past `gascity-health-doctor-timeout' is abandoned as an error."
  (let ((gascity-health-doctor-timeout 0.05)
        (got nil))
    (cl-letf (((symbol-function 'gascity-reader-run-async)
               (lambda (_args _callback) nil)))
      (funcall (gascity-health--doctor-loader nil)
               (lambda (d) (setq got (list :ok d)))
               (lambda (e) (setq got (list :error e))))
      (let ((deadline (+ (float-time) 2)))
        (while (and (not got) (< (float-time) deadline))
          (accept-process-output nil 0.02)))
      (should (eq (car got) :error))
      (should (string-match-p "timed out" (cadr got))))))

(ert-deftest gascity-test-health-rig-status-failure-is-a-row ()
  "One failing `gc rig status' is its own `■' row; the other rigs render."
  (cl-letf* ((orig (symbol-function 'gascity-health-test--read))
             ((symbol-function 'gascity-health-test--read)
              (lambda (args callback &optional errback &rest rest)
                (if (member "gascity.el" args)
                    (funcall errback "gc rig status gascity.el failed: boom (exit 1)")
                  (apply orig args callback errback rest)))))
    (gascity-health-test--with-health "/tmp/"
      (should (gascity-health-test--line "● beads\\.el"))
      (should (gascity-health-test--line "■ gascity\\.el .*gc rig status: .*boom")))))

(ert-deftest gascity-test-health-render-guard-remote ()
  "Rendering the health view on a remote city does no file I/O (§8.3 R2)."
  (gascity-test-ensure-mock-method)
  (let ((tramp-verbose 0)
        (dir "/mock::/home/roman/emacs-city/"))
    (setf (gascity-store--host-primed (gascity-store--host (file-remote-p dir))) t)
    (gascity-test-with-render-guard
      (gascity-health-test--with-health dir
        (should (string-match-p "Supervisor" (buffer-string)))
        (should (gascity-health-test--line "● beads\\.el"))
        (gascity-health-doctor)
        (funcall (nth 1 (car gascity-health-test--doctor-calls))
                 (gascity-health-test--doctor-result))
        (goto-char (point-min))
        (re-search-forward "▸ [0-9]+ checks ok")
        (goto-char (match-beginning 0))
        (gascity-thing-toggle)
        (should (gascity-health-test--line "▾ [0-9]+ checks ok"))
        (gascity-health-refresh)
        (should (string-match-p "@" (gascity-health-test--line "^Health"))))
      (should (null gascity-test-render-guard-violations)))))

(ert-deftest gascity-test-health-doctor-is-non-blocking ()
  "`!' and a confirmed `F' only start a process (D9): no sync gc."
  (gascity-health-test--with-health "/tmp/"
    (cl-letf (((symbol-function 'gascity-reader-run)
               (lambda (args) (error "Synchronous gc: %S" args)))
              ((symbol-function 'process-file)
               (lambda (prog &rest _) (error "Process-file %s" prog)))
              ((symbol-function 'call-process)
               (lambda (prog &rest _) (error "Call-process %s" prog)))
              ((symbol-function 'gascity-action--confirm) (lambda (&rest _) t)))
      (let ((start (float-time)))
        (gascity-health-doctor)
        (should (< (- (float-time) start) 1.0))
        (should (= (length gascity-health-test--doctor-calls) 1))
        (should (plist-get (gascity-store-get gascity-health--doctor-args) :pending))))))

(ert-deftest gascity-test-health-stale-and-offline ()
  "A refresh that times out over good data marks the section `◐ timed
out'; an offline host shows `○ offline @host' on the top line."
  (gascity-health-test--with-health "/tmp/"
    (let ((ctx (list :loads (list :status (gascity-health--load
                                           (list :status 'ready
                                                 :data (gascity-health-test--json
                                                        "emacs-city.status.json")
                                                 :error "gc status timed out"
                                                 :timed-out t)))
                     :view nil)))
      (should (string-match-p "^Supervisor +◐ timed out"
                              (substring-no-properties
                               (car (gascity-health--supervisor-lines ctx)))))))
  (cl-letf (((symbol-function 'gascity-store-offline-p) (lambda (&rest _) t)))
    (let ((default-directory "/mock::/home/roman/emacs-city/"))
      (should (string-match-p "○ offline @"
                              (substring-no-properties
                               (gascity-health--top-line (list :loads nil))))))))

;;; Store-size sparkline (P5)

(ert-deftest gascity-test-pulse-sparkline ()
  "Samples map onto ▁…█; a flat series is all ▁; nil is empty."
  (should (equal (gascity-pulse-sparkline '(1 2 3 4 5 6 7 8)) "▁▂▃▄▅▆▇█"))
  (should (equal (gascity-pulse-sparkline '(5 5 5)) "▁▁▁"))
  (should (equal (gascity-pulse-sparkline nil) ""))
  (should (equal (length (gascity-pulse-sparkline '(0 100 50))) 3)))

(ert-deftest gascity-test-pulse-store-samples ()
  "Each distinct status payload adds one sample; a re-render does not; the
ring is capped at `gascity-pulse-store-samples'."
  (let ((gascity-pulse--samples (make-hash-table :test 'equal))
        (gascity-pulse-store-samples 3)
        (mk (lambda (n) `((summary (store_health (size_bytes . ,n)))))))
    (let ((a (funcall mk 10)))
      (gascity-pulse-record-store-size "/c/" a)
      (gascity-pulse-record-store-size "/c/" a))
    (should (equal (gascity-pulse-store-sizes "/c") '(10)))
    (dolist (n '(20 30 40))
      (gascity-pulse-record-store-size "/c" (funcall mk n)))
    (should (equal (gascity-pulse-store-sizes "/c/") '(20 30 40)))
    ;; Keys are host-qualified.
    (should (null (gascity-pulse-store-sizes "/ssh:h:/c/")))))

(ert-deftest gascity-test-health-sparkline-line ()
  "Two or more samples draw the `size (this session)' sparkline."
  (let ((gascity-pulse--samples (make-hash-table :test 'equal)))
    (gascity-pulse-record-store-size "/tmp/" '((summary (store_health (size_bytes . 100)))))
    (gascity-health-test--with-health "/tmp/"
      (should (gascity-health-test--line "size (this session)  [▁▂▃▄▅▆▇█]\\{2\\}")))))

;;; Mode-line lighter (§7.12, P5)

(defmacro gascity-health-test--no-gc (&rest body)
  "Run BODY with every gc and process entry point signalling."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'gascity-reader-read-async)
              (lambda (&rest a) (error "Read-async %S" a)))
             ((symbol-function 'gascity-reader-read)
              (lambda (&rest a) (error "Read %S" a)))
             ((symbol-function 'gascity-reader-run)
              (lambda (&rest a) (error "Run %S" a)))
             ((symbol-function 'gascity-reader-run-async)
              (lambda (&rest a) (error "Run-async %S" a)))
             ((symbol-function 'gascity-store-fetch)
              (lambda (&rest a) (error "Store fetch %S" a)))
             ((symbol-function 'process-file)
              (lambda (&rest a) (error "Process-file %S" a)))
             ((symbol-function 'make-process)
              (lambda (&rest a) (error "Make-process %S" a))))
     ,@body))

(ert-deftest gascity-test-mode-line-lighter ()
  "The lighter shows one segment per open cockpit from published counts,
`●' at zero, never runs gc or touches a remote name, and drops a city
whose cockpit is killed."
  (let ((gascity-pulse--cities (make-hash-table :test 'equal))
        (global-mode-string nil)
        (ec (generate-new-buffer "*ec-cockpit*"))
        (bl (generate-new-buffer "*bl-cockpit*"))
        (rbl (generate-new-buffer "*rbl-cockpit*")))
    (unwind-protect
        (progn
          (gascity-mode-line-mode 1)
          (gascity-test-ensure-mock-method)
          (gascity-test-with-render-guard
            (gascity-health-test--no-gc
              (gascity-pulse-publish "/home/roman/emacs-city/" ec "emacs-city"
                                     :fail 1 :watch 2 :runs 1)
              (gascity-pulse-publish "/home/roman/bright-lights/" bl "bright-lights"
                                     :fail 0 :watch 1 :runs 0)
              ;; The construct is a symbol whose value is a plain string:
              ;; redisplay evaluates nothing (`format-mode-line' needs a
              ;; live frame, so the value is checked directly in batch).
              (should (memq 'gascity-mode-line--string global-mode-string))
              ;; A valid construct: a list led by a symbol would be read
              ;; as a (SYMBOL THEN ELSE) conditional (`*invalid*').
              (should (stringp (car global-mode-string)))
              (should (stringp gascity-mode-line--string))
              (should (equal (substring-no-properties gascity-mode-line--string)
                             " GC[bl ▲1 · ec ■1▲2]"))
              (gascity-pulse-publish "/mock::/home/roman/bright-lights/" rbl
                                     "bright-lights" :fail 0 :watch 0)
              (let ((text gascity-mode-line--string))
                (should (string-match-p "bl@[^ ]+ ●" text))
                ;; mouse-1 is bound on each segment.
                (should (keymapp (get-text-property
                                  (string-match "ec" text) 'local-map text))))
              (kill-buffer ec)
              (should-not (string-match-p "ec " gascity-mode-line--string))))
          (should (null gascity-test-render-guard-violations)))
      (gascity-mode-line-mode -1)
      (dolist (b (list ec bl rbl)) (when (buffer-live-p b) (kill-buffer b))))
    (should (equal gascity-mode-line--string ""))
    (should (null global-mode-string))))

(ert-deftest gascity-test-mode-line-keeps-other-segments ()
  "Enabling and disabling the lighter keeps other `global-mode-string' parts."
  (let ((global-mode-string '("" display-time-string)))
    (gascity-mode-line-mode 1)
    (should (equal global-mode-string
                   '("" display-time-string gascity-mode-line--string)))
    (gascity-mode-line-mode -1)
    (should (equal global-mode-string '("" display-time-string)))))

(ert-deftest gascity-test-mode-line-abbrev ()
  "City names shorten to their initials, one-word names to two letters."
  (should (equal (gascity-pulse-abbrev "emacs-city") "ec"))
  (should (equal (gascity-pulse-abbrev "bright-lights") "bl"))
  (should (equal (gascity-pulse-abbrev "gastown") "ga")))

(ert-deftest gascity-test-cockpit-publishes-needs-you ()
  "The cockpit publishes its Needs you ■/▲ totals when it renders."
  (let ((gascity-pulse--cities (make-hash-table :test 'equal))
        (ctx (gascity-dashboard--context
              (list :status (list :state 'ready
                                  :data (gascity-health-test--json
                                         "emacs-city.status.json"))
                    :mail (list :state 'ready :data '((unread . 3)))
                    :work (list :state 'ready :data (list :beads nil)))
              nil (float-time))))
    (with-temp-buffer
      (setq default-directory "/home/roman/emacs-city/")
      (gascity-dashboard--publish ctx)
      (let ((entry (gascity-pulse-city "/home/roman/emacs-city")))
        (should entry)
        (should (equal (plist-get entry :name) "emacs-city"))
        (should (>= (plist-get entry :watch) 1))
        (should (eql (plist-get entry :runs) 0))))))

;;; Cities (§7.11)

(defmacro gascity-health-test--with-cities (&rest body)
  "Open the Cities list on canned reads and run BODY in its buffer."
  (declare (indent 0))
  `(let ((gascity-store-synchronous-delivery t)
         (gascity-pulse--cities (make-hash-table :test 'equal)))
     (cl-letf (((symbol-function 'gascity-reader-read-async)
                #'gascity-health-test--read)
               ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b))))
       (save-window-excursion
         (unwind-protect
             (progn (gascity-cities)
                    (with-current-buffer gascity-cities-buffer-name ,@body))
           (when (get-buffer gascity-cities-buffer-name)
             (kill-buffer gascity-cities-buffer-name)))))))

(defun gascity-health-test--rows ()
  "Return the Cities rows as lists of plain cell strings."
  (mapcar (lambda (e) (mapcar #'substring-no-properties (append (cadr e) nil)))
          gascity-tabulated--all-entries))

(ert-deftest gascity-test-cities-local ()
  "Local cities come from `gc cities', each filled by its own status read."
  (let ((gascity-remote-hosts nil))
    (gascity-health-test--with-cities
      (let ((rows (gascity-health-test--rows)))
        (should (= (length rows) 2))
        (should (equal (mapcar #'car rows) '("● bright-lights" "● emacs-city")))
        (should (equal (nth 1 (car rows)) "~/bright-lights/"))
        (should (equal (nth 2 (cadr rows)) "1/5"))
        (should (string-match-p "▲" (nth 4 (cadr rows))))
        (should (equal (nth 5 (cadr rows)) "●"))
        ;; No cockpit open: Runs is blank, not an apology.
        (should (equal (nth 3 (cadr rows)) ""))))))

(ert-deftest gascity-test-cities-remote-hosts ()
  "Configured and visited hosts add host-qualified rows; RET targets the
host-qualified city directory."
  (gascity-test-ensure-mock-method)
  (let* ((gascity-remote-hosts '("/mock::"))
         (tramp-verbose 0)
         (host (substring-no-properties (file-remote-p "/mock::")))
         (visited nil))
    (setf (gascity-store--host-primed (gascity-store--host host)) t)
    (should (equal (gascity-cities-hosts) (list "" host)))
    (gascity-health-test--with-cities
      (let ((rows (gascity-health-test--rows)))
        (should (= (length rows) 4))
        (should (seq-find (lambda (r) (equal (nth 1 r) (concat host "~/bright-lights/")))
                          rows))
        (should (string-match-p "4 · 2 remote" gascity-tabulated--base-name)))
      (goto-char (point-min))
      (while (and (not (eobp))
                  (not (equal (alist-get 'dir (tabulated-list-get-id))
                              (concat host "/home/roman/emacs-city/"))))
        (forward-line 1))
      (cl-letf (((symbol-function 'gascity-dashboard)
                 (lambda () (setq visited default-directory))))
        (gascity-cities-visit))
      (should (equal visited (concat host "/home/roman/emacs-city/"))))))

(ert-deftest gascity-test-cities-host-failure-row ()
  "A host whose `gc cities' fails gets one `■' row; the others still list."
  (let ((gascity-remote-hosts '("/mock::"))
        (offline nil))
    (gascity-test-ensure-mock-method)
    (setf (gascity-store--host-primed
           (gascity-store--host (substring-no-properties (file-remote-p "/mock::"))))
          t)
    (cl-letf* ((orig (symbol-function 'gascity-health-test--read))
               ((symbol-function 'gascity-health-test--read)
                (lambda (args callback &optional errback &rest rest)
                  (if (and (file-remote-p default-directory) (member "cities" args))
                      (funcall errback (if offline
                                           "gc cities failed: Connection refused"
                                         "gc cities failed: unknown command (exit 1)"))
                    (apply orig args callback errback rest)))))
      (gascity-health-test--with-cities
        (let ((rows (gascity-health-test--rows)))
          (should (= (length rows) 3))
          (should (seq-find (lambda (r) (and (string-prefix-p "■" (car r))
                                             (string-match-p "unknown command" (nth 5 r))))
                            rows))))
      ;; An unreachable host is `○ offline', not an error storm.
      (gascity-store-clear)
      (setf (gascity-store--host-primed
             (gascity-store--host (substring-no-properties (file-remote-p "/mock::"))))
            t)
      (setq offline t)
      (gascity-health-test--with-cities
        (let ((rows (gascity-health-test--rows)))
          (should (= (length rows) 3))
          (should (seq-find (lambda (r) (and (string-prefix-p "○" (car r))
                                             (equal (nth 5 r) "offline")))
                            rows)))))))

(ert-deftest gascity-test-cities-runs-from-cockpit ()
  "The Runs column shows an open cockpit's published run count."
  (let ((gascity-remote-hosts nil)
        (cockpit (generate-new-buffer "*ec*")))
    (unwind-protect
        (gascity-health-test--with-cities
          (gascity-pulse-publish "/home/roman/emacs-city/" cockpit "emacs-city"
                                 :fail 0 :watch 0 :runs 2)
          (gascity-cities--redisplay)
          (should (equal (nth 3 (cadr (gascity-health-test--rows))) "2 ⬣")))
      (kill-buffer cockpit))))

(ert-deftest gascity-test-cities-follow-store-refetch ()
  "A refetch of a city's status by another view updates its row (subscribed)."
  (let ((gascity-remote-hosts nil))
    (gascity-health-test--with-cities
      (should (equal (nth 2 (cadr (gascity-health-test--rows))) "1/5"))
      (let ((status (gascity-health-test--json "emacs-city.status.json")))
        (setf (alist-get 'running_agents (alist-get 'summary status)) 4)
        (cl-letf (((symbol-function 'gascity-reader-read-async)
                   (lambda (_args callback &rest _) (funcall callback status) nil)))
          (let ((default-directory "/home/roman/emacs-city/"))
            (gascity-store-fetch '("status") #'ignore nil :force t))))
      (should (equal (nth 2 (cadr (gascity-health-test--rows))) "4/5"))
      ;; Refresh drops the old subscriptions (no duplicates).
      (let ((n (length gascity-cities--subs)))
        (gascity-cities-refresh)
        (should (= (length gascity-cities--subs) n))))))

;;; Costs (`j $')

(ert-deftest gascity-test-costs-shows-text ()
  "`gascity-costs' starts `gc costs' async and shows its text as-is."
  (let ((calls nil)
        (gascity-store-synchronous-delivery t))
    (cl-letf (((symbol-function 'gascity-reader-run-async)
               (lambda (args callback) (push (list args callback) calls) nil))
              ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b))))
      (save-window-excursion
        (let ((default-directory "/tmp/"))
          (gascity-costs))
        (unwind-protect
            (progn
              (should (= (length calls) 1))
              (should (equal (car (car calls)) '("costs")))
              (should (string-match-p "…" (buffer-string)))
              (funcall (nth 1 (car calls))
                       (list :exit-code 0
                             :stdout (gascity-health-test--text "emacs-city.costs.txt")
                             :stderr ""))
              (let ((deadline (+ (float-time) 2)))
                (while (and (not (string-match-p "EST_USD" (buffer-string)))
                            (< (float-time) deadline))
                  (accept-process-output nil 0.02)))
              (should (string-match-p "^RUN +INVOCATIONS" (buffer-string)))
              (should buffer-read-only)
              (should (eq (keymap-lookup (current-local-map) "g")
                          #'gascity-costs-refresh)))
          (kill-buffer (current-buffer)))))))

;;; Entry points

(ert-deftest gascity-test-health-views-are-commands ()
  "The `j' targets are interactive commands and `j $' is in `?'."
  (dolist (cmd '(gascity-health gascity-cities gascity-costs gascity-mode-line-mode))
    (should (commandp cmd)))
  (should (eq (keymap-lookup gascity-jump-map "$") #'gascity-jump-costs))
  (should (eq (plist-get (cdr (transient-get-suffix 'gascity-dispatch "j $")) :command)
              'gascity-jump-costs))
  (should (eq (keymap-lookup gascity-health-mode-map "!") #'gascity-health-doctor))
  (should (eq (keymap-lookup gascity-health-mode-map "F") #'gascity-health-doctor-fix))
  (should (eq (keymap-lookup gascity-health-mode-map "j") 'gascity-jump-prefix)))

(provide 'gascity-health-test)
;;; gascity-health-test.el ends here
