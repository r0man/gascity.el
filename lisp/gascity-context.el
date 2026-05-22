;;; gascity-context.el --- Resolve the current city and rig -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Determine which Gas City and rig the user is "in", based on
;; `default-directory', with explicit overrides.
;;
;; - The city is found by walking up for the `city.toml' marker
;;   (`gascity-context-city-root'); its name is the root directory's
;;   basename (`gascity-context-city-name').
;; - Rigs live outside the city tree and are tracked in gc's registry,
;;   so there is no reliable local marker; `gascity-context-rig-name'
;;   asks gc to resolve the rig from `default-directory', caching the
;;   answer per directory.
;;
;; Override `gascity-context-city' / `gascity-context-rig' to pin the
;; context (e.g. for a switch-rig command, arriving in later phases).

;;; Code:

(require 'cl-lib)
(require 'gascity-reader)

(defvar gascity-context-city nil
  "When non-nil, an absolute path that overrides city auto-detection.")

(defvar gascity-context-rig nil
  "When non-nil, a rig name that overrides rig auto-detection.")

(defconst gascity-context-city-file "city.toml"
  "Marker file identifying a Gas City root directory.")

(defvar gascity-context--rig-cache (make-hash-table :test 'equal)
  "Cache mapping an absolute directory to its resolved rig name.")

(defun gascity-context-clear-cache ()
  "Forget cached rig resolutions.
Call after the city's rig set changes, or to force re-resolution."
  (interactive)
  (clrhash gascity-context--rig-cache))

(defun gascity-context-city-root (&optional dir)
  "Return the Gas City root governing DIR (default `default-directory').
Honours `gascity-context-city'.  Otherwise walks up from DIR looking
for `gascity-context-city-file'.  Returns an absolute directory name
\(with trailing slash), or nil when DIR is not inside a city."
  (if gascity-context-city
      (file-name-as-directory (expand-file-name gascity-context-city))
    (when-let* ((start (expand-file-name (or dir default-directory)))
                (found (locate-dominating-file start gascity-context-city-file)))
      (file-name-as-directory (expand-file-name found)))))

(defun gascity-context-city-name (&optional dir)
  "Return the city name governing DIR, or nil.
Derived from the basename of `gascity-context-city-root'."
  (when-let ((root (gascity-context-city-root dir)))
    (file-name-nondirectory (directory-file-name root))))

(defun gascity-context-rig-name (&optional dir)
  "Return the current rig name for DIR (default `default-directory'), or nil.
Honours `gascity-context-rig'.  Otherwise asks gc to resolve the rig
from DIR via `gc rig status', returning nil when DIR is not inside a
rig.  Answers are cached per directory; clear with
`gascity-context-clear-cache'."
  (or gascity-context-rig
      (let* ((key (expand-file-name (or dir default-directory)))
             (cached (gethash key gascity-context--rig-cache 'miss)))
        (if (not (eq cached 'miss))
            cached
          (puthash key
                   (condition-case nil
                       (let* ((default-directory key)
                              (rig (alist-get
                                    'rig (gascity-reader-read "rig" "status"))))
                         (alist-get 'name rig))
                     (gascity-error nil))
                   gascity-context--rig-cache)))))

(provide 'gascity-context)
;;; gascity-context.el ends here
