;;; gascity-integrate-test.el --- Live stream wiring across views -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; dashboard-v3 integration: every view joins its city's live event
;; stream, binds `W' to toggle it, shows its state in the header or
;; mode line, and the mode-line lighter covers every city with a
;; stream — all without gc or TRAMP I/O at redisplay.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(defconst gascity-test-integrate--view-maps
  '(gascity-runs-mode-map gascity-run-mode-map gascity-agents-mode-map
    gascity-agents-tree-mode-map gascity-session-detail-mode-map
    gascity-health-mode-map gascity-rig-dashboard-mode-map
    gascity-rig-list-mode-map gascity-session-list-mode-map
    gascity-convoy-list-mode-map gascity-mail-inbox-mode-map
    gascity-order-list-mode-map gascity-dolt-list-mode-map)
  "Keymaps of the views that must toggle their city's stream with `W'.")

(ert-deftest gascity-test-integrate-w-toggles-live-everywhere ()
  "`W' is `gascity-live-toggle' in every view (§5.1); in Cities it acts on
the city at point (`gascity-live-city-function')."
  (dolist (map gascity-test-integrate--view-maps)
    (ert-info ((symbol-name map))
      (should (eq (keymap-lookup (symbol-value map) "W") 'gascity-live-toggle))))
  (should (eq (keymap-lookup gascity-cities-mode-map "W") 'gascity-live-toggle))
  (with-temp-buffer
    (gascity-cities-mode)
    (should (functionp gascity-live-city-function)))
  (should (memq (keymap-lookup gascity-dashboard-mode-map "W")
                '(gascity-dashboard-toggle-live gascity-live-toggle))))

(defmacro gascity-test-integrate--with-attach-log (log &rest body)
  "Run BODY recording the buffers `gascity-live-attach' is called for in LOG."
  (declare (indent 1) (debug t))
  `(let ((,log nil))
     (cl-letf (((symbol-function 'gascity-live-attach)
                (lambda (&optional buffer &rest _)
                  (push (or buffer (current-buffer)) ,log)
                  nil)))
       ,@body)))

(ert-deftest gascity-test-integrate-views-attach-on-mount ()
  "Every vui view (via `gascity-section-mode') and every tabulated list
\(via `gascity-tabulated--show' / its mode) joins its city's stream."
  (dolist (mode '(gascity-runs-mode gascity-run-mode gascity-agents-tree-mode
                  gascity-session-detail-mode gascity-health-mode
                  gascity-rig-dashboard-mode gascity-agents-mode))
    (ert-info ((symbol-name mode))
      (gascity-test-integrate--with-attach-log log
        (with-temp-buffer
          (setq default-directory "/tmp/city/")
          (funcall mode)
          (should (memq (current-buffer) log))))))
  (gascity-test-integrate--with-attach-log log
    (cl-letf (((symbol-function 'pop-to-buffer) #'ignore)
              ((symbol-function 'gascity-view-get-buffer-create)
               (lambda (name &rest _) (get-buffer-create name))))
      (unwind-protect
          (progn
            (gascity-tabulated--show "*gascity-test-convoys*"
                                     #'gascity-convoy-list-mode #'ignore)
            (should (memq (get-buffer "*gascity-test-convoys*") log))
            (with-current-buffer "*gascity-test-convoys*"
              (should (equal mode-line-process
                             '(:eval (let ((live (gascity-ui-live-string)))
                                       (if live (concat " " live) "")))))))
        (kill-buffer "*gascity-test-convoys*")))))

(defun gascity-test-integrate--fake-stream (root host name state)
  "Register a fake live stream for ROOT (no process); return it."
  (puthash root (gascity-live--stream-create :root root :host host :name name
                                             :state state)
           gascity-live--streams))

(ert-deftest gascity-test-integrate-header-shows-live-state ()
  "The shared header line carries the city, `@host' and the live state;
without a stream, a store-paused host reads `○ offline @host'."
  (let ((gascity-live--streams (make-hash-table :test 'equal)))
    (with-temp-buffer
      (setq default-directory "/ssh:farhost:/srv/bright-lights/")
      (gascity-test-integrate--fake-stream default-directory "farhost"
                                           "bright-lights" 'live)
      (let ((line (gascity-ui-header-line "Runs")))
        (should (string-search "bright-lights" line))
        (should (string-search "@farhost" line))
        (should (string-search "Runs" line))
        (should (string-search "● live" line)))
      (clrhash gascity-live--streams)
      (gascity-store--set-state (gascity-store--host "/ssh:farhost:") 'offline "gone")
      (should (string-search "○ offline @farhost" (gascity-ui-header-line "Runs"))))))

(ert-deftest gascity-test-integrate-lighter-covers-every-stream ()
  "The lighter shows every city with a live stream, remote ones with
`@host', besides the cities with a cockpit — computed with no gc and no
TRAMP I/O (render guard, reader stubbed to fail)."
  (let ((gascity-live--streams (make-hash-table :test 'equal))
        (gascity-mode-line-mode t))
    (gascity-test-ensure-mock-method)
    (gascity-test-integrate--fake-stream "/ssh:farhost:/srv/bright-lights/"
                                         "farhost" "bright-lights" 'live)
    (gascity-test-integrate--fake-stream "/tmp/emacs-city/" nil "emacs-city"
                                         'reconnecting)
    (cl-letf (((symbol-function 'gascity-reader-run)
               (lambda (&rest _) (error "gc at redisplay")))
              ((symbol-function 'gascity-reader-read-async)
               (lambda (&rest _) (error "gc at redisplay"))))
      (gascity-test-with-render-guard
        (let ((s (gascity-mode-line-string)))
          (should (string-search "bl@farhost ●" s))
          (should (string-search "ec ○" s))
          (should (string-prefix-p " GC[" s)))
        (should (null gascity-test-render-guard-violations))))))

(provide 'gascity-integrate-test)
;;; gascity-integrate-test.el ends here
