;;; gascity-share-test.el --- TRAMP connection sharing suppressed for gc spawns -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; With `gascity-remote-transport' `tramp' on an ssh-family host, every
;; gc spawn is a tramp-sh process: by default an ssh ControlMaster mux
;; session with a pty, which the master blocks on when it fills while
;; TRAMP waits on another channel (F8, qa/f8-root-cause.md; the TRAMP
;; matrix re-run measured 0.6-45 s stalls and "Process has died").
;; gascity binds `tramp-use-connection-share' to `suppress' around its
;; own TRAMP spawns there; direct-async (no pty) is left alone.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)
(require 'tramp-sh)                    ; the connection-share option is special

(defmacro gascity-share-test--with-share (value &rest body)
  "Run BODY with TRAMP's connection-share option bound to VALUE.
Its name differs by Emacs version (`gascity-remote--share-variable')."
  (declare (indent 1))
  `(cl-progv (list (gascity-remote--share-variable)) (list ,value) ,@body))

(defun gascity-share-test--share ()
  "Return the current value of TRAMP's connection-share option."
  (symbol-value (gascity-remote--share-variable)))

(ert-deftest gascity-test-share-suppressed-for-ssh-only ()
  "`suppress' for an ssh-family host; the user's value for a local
directory, a non-ssh method and a direct-async connection."
  (gascity-test-ensure-mock-method)
  (gascity-share-test--with-share t
				  (should (eq (gascity-remote-connection-share "/ssh:gc-share.invalid:/c/")
					      'suppress))
				  (should (eq (gascity-remote-connection-share "/scp:gc-share.invalid:/c/")
					      'suppress))
				  (should (eq (gascity-remote-connection-share "/tmp/") t))
				  (should (eq (gascity-remote-connection-share "/mock::/tmp/") t))
				  (cl-letf (((symbol-function 'tramp-direct-async-process-p) (lambda (&rest _) t)))
				    (should (eq (gascity-remote-connection-share "/ssh:gc-share.invalid:/c/")
						t)))))

(ert-deftest gascity-test-share-binding-in-effect-during-spawn ()
  "The tramp-transport read path spawns with sharing suppressed on an
ssh host, and the binding does not leak past the spawn."
  (let ((default-directory "/ssh:gc-share.invalid:/city/")
        (gascity-remote-transport 'tramp)
        (gascity-reader-skip-dir-probe t)
        seen)
    (gascity-share-test--with-share t
				    (cl-letf (((symbol-function 'make-process)
					       (lambda (&rest _) (setq seen (gascity-share-test--share)) nil))
					      ((symbol-function 'gascity-remote-find-executable) (lambda (e) e))
					      ((symbol-function 'gascity-remote-path-assignment) (lambda (&rest _) ""))
					      ((symbol-function 'gascity-reader--stderr-delimiter) (lambda (&rest _) "D"))
					      ((symbol-function 'gascity-reader--city-args) (lambda (&rest _) nil))
					      ((symbol-function 'tramp-direct-async-process-p) (lambda (&rest _) nil)))
				      (ignore-errors (gascity-reader-read-async '("status") #'ignore #'ignore))
				      (should (eq seen 'suppress))
				      (setq seen nil)
				      (ignore-errors (gascity-reader-run-async '("session" "suspend" "x") #'ignore))
				      (should (eq seen 'suppress))
				      (should (eq (gascity-share-test--share) t))))))

(ert-deftest gascity-test-share-process-file-sites ()
  "The synchronous TRAMP calls (gc reader, tmux probes) run unshared too."
  (let ((default-directory "/ssh:gc-share.invalid:/city/")
        seen)
    (gascity-share-test--with-share t
				    (cl-letf (((symbol-function 'process-file)
					       (lambda (&rest _) (push (gascity-share-test--share) seen) 0))
					      ((symbol-function 'gascity-remote-find-executable) (lambda (e) e))
					      ((symbol-function 'tramp-direct-async-process-p) (lambda (&rest _) nil)))
				      (ignore-errors (gascity-terminal-tmux-session-exists-p "s" "sock"))
				      (should seen)
				      (should (seq-every-p (lambda (v) (eq v 'suppress)) seen))))))

(provide 'gascity-share-test)
;;; gascity-share-test.el ends here
