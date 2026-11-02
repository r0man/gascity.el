;;; clean-env-smoke.el --- clean-environment smoke test for gascity -*- lexical-binding: t; -*-

;; Run by scripts/clean-env-smoke.sh under `env -i' (HOME, PATH and TERM
;; only, so XDG_RUNTIME_DIR is unset).  The shell wrapper owns the two
;; skip cases (not inside a city, no /run/user/<uid>); this file is the
;; part that must be green:
;;
;;   1. assert the runtime-directory fallback that ga-x40e added;
;;   2. perform one real local `gc status --json' read through the
;;      synchronous runner every read-only view shares;
;;   3. require exit 0 and a non-empty agents list.
;;
;; Batch Emacs exits non-zero on any assertion, so the wrapper's exit
;; status is the test result.  There is deliberately no ERT wrapper: the
;; check needs a live city, and CI has none.

;; Load the working tree, not a stale .elc from an older build.
(setq load-prefer-newer t)

(require 'gascity)

(defun clean-env-smoke--fail (fmt &rest args)
  "Print a FAIL line for FMT/ARGS and exit non-zero."
  (princ (concat "FAIL: " (apply #'format fmt args) "\n"))
  (kill-emacs 1))

(defun clean-env-smoke-main ()
  "Assert the runtime fallback and read `gc status' under a clean env."
  (let* ((uid (user-uid))
         (expected (format "/run/user/%d" uid))
         (actual (gascity-reader--default-runtime-dir)))
    (when (getenv "XDG_RUNTIME_DIR")
      (clean-env-smoke--fail
       "XDG_RUNTIME_DIR is set (%S); run the wrapper, which starts Emacs under env -i"
       (getenv "XDG_RUNTIME_DIR")))
    (unless (equal actual expected)
      (clean-env-smoke--fail
       "gascity-reader--default-runtime-dir is %S, expected %S"
       actual expected))
    (princ (format "ok: unset XDG_RUNTIME_DIR falls back to %s\n" actual)))
  (let* ((result (gascity-reader-run '("status" "--json")))
         (exit (plist-get result :exit-code))
         (stderr (plist-get result :stderr)))
    (unless (and (integerp exit) (zerop exit))
      (clean-env-smoke--fail "gc status --json exited %s: %s" exit stderr))
    (let* ((payload (gascity-reader-parse-json (plist-get result :stdout)))
           (agents (alist-get 'agents payload)))
      (unless (and (vectorp agents) (> (length agents) 0))
        (clean-env-smoke--fail
         "gc status --json returned no agents (city=%S, default-directory=%s)"
         (alist-get 'city_name payload) default-directory))
      (princ (format "ok: gc status --json exit 0, city=%s, agents=%d\n"
                     (alist-get 'city_name payload) (length agents)))))
  (princ "PASS: clean environment (no XDG_RUNTIME_DIR) reads gc\n"))

(provide 'clean-env-smoke)
;;; clean-env-smoke.el ends here
