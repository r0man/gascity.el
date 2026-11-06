;;; gascity-beads-eldoc-install-test.el --- One bead-eldoc install path -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The install-path slice of the bead-id eldoc contract (plan §B, §H item
;; 2; REQ-001/002/006/008): one installer for every view and attach
;; buffer, a per-id resolver instead of a store string, the deny-all cold
;; sentinel, the captured city context, the open-buffer registry and the
;; major-mode reinstall.
;;
;; The per-city map core is the other slice of `gascity-beads-eldoc' (its
;; `gc rig list' fill and TTL).  These tests stand in for it at its public
;; seam — `gascity-beads-eldoc-map' plus the two accessors the install
;; path uses — so they exercise the install path alone, with no gc, no
;; store and no network.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

(require 'beads-util nil t)
(require 'beads-eldoc nil t)

;;; Fixtures

(defun gascity-test-eldoc--make-city ()
  "Create a temporary city directory and return it, with a trailing slash."
  (let ((dir (file-name-as-directory (make-temp-file "gascity-eldoc-city" t))))
    (with-temp-file (expand-file-name "city.toml" dir)
      (insert ""))
    dir))

(defun gascity-test-eldoc--map (prefixes stores)
  "Return a city map with PREFIXES and PREFIX -> STORE STORES.
A real map struct: its accessors are inlined into the compiled module,
so no test may stand in for them with a plist."
  (gascity-beads-eldoc--map-create :prefixes prefixes :stores stores
                                   :fetched-at (float-time)))

(defun gascity-test-eldoc--clear-maps ()
  "Forget every city map, so a landed map cannot leak into another test."
  (clrhash gascity-beads-eldoc--maps))

(defmacro gascity-test-eldoc--with-map (map &rest body)
  "Run BODY with the map's read entry point answering MAP.
Stubbing `gascity-beads-eldoc-map' is the seam: install asks it for the
city snapshot and the pure resolver reads the struct it returns."
  (declare (indent 1) (debug t))
  `(progn
     (gascity-test-eldoc--clear-maps)
     (cl-letf (((symbol-function 'gascity-beads-eldoc-map)
                (lambda (&optional _dir) ,map)))
       ,@body)))

(defmacro gascity-test-eldoc--with-contract (&rest body)
  "Run BODY with beads.el's two eldoc variables available."
  `(progn
     (require 'beads-eldoc nil t)
     (skip-unless (boundp 'beads-eldoc-directory))
     ,@body))

(defun gascity-test-eldoc--warm-map ()
  "Return a city map with a city prefix and two rig prefixes."
  (gascity-test-eldoc--map
   '("gce" "be")
   '(("gce" . "/p/gascity.el/")
     ("be" . "/p/beads.el/"))))

;;; The cold sentinel

(ert-deftest gascity-test-beads-eldoc-deny-all-prefixes ()
  "The cold allowlist admits no real id, against the installed beads.el.
`nil' or `()' would mean \"accept any id\" and send a cold buffer to
`default-directory' (REQ-006); `'(\"\")' must admit nothing, and the pin
must fail loudly if beads.el ever changes the predicate (plan D1)."
  (skip-unless (fboundp 'beads-issue-id--allowed-p))
  (should-not (beads-issue-id--allowed-p
               "gce-abc" gascity-beads-eldoc--deny-all-prefixes))
  (should-not (beads-issue-id--allowed-p
               "be-lc1lb.2" gascity-beads-eldoc--deny-all-prefixes))
  (should-not (beads-issue-id--allowed-p
               "post-command" gascity-beads-eldoc--deny-all-prefixes))
  ;; The property the sentinel exists for: nil admits everything.
  (should (beads-issue-id--allowed-p "gce-abc" nil))
  (should-not (beads-issue-id--allowed-p '("gce") '("be"))))

;;; Install

(ert-deftest gascity-test-beads-eldoc-install-warm-map ()
  "A warm map installs a per-id resolver and the map's prefixes.
The buffer's eldoc must resolve ids from every store of the city — not
only the buffer's own directory (REQ-002) — and an unknown prefix must
answer nil, never the ambient directory."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city))
          (map (gascity-test-eldoc--warm-map)))
      (unwind-protect
          (gascity-test-eldoc--with-map map
            (let ((buf (generate-new-buffer " *gascity-eldoc-warm*")))
              (unwind-protect
                  (progn
                    (with-current-buffer buf (setq default-directory city))
                    (should (eq (gascity-beads-eldoc-install buf) buf))
                    (with-current-buffer buf
                      (should (equal gascity-beads-eldoc--scope city))
                      (should (eq gascity-beads-eldoc--map map))
                      (should (functionp beads-eldoc-directory))
                      (should (equal beads-issue-id-prefixes '("gce" "be")))
                      (should (equal (funcall beads-eldoc-directory "be-abc")
                                     "/p/beads.el/"))
                      (should (equal (funcall beads-eldoc-directory "gce-abc")
                                     "/p/gascity.el/"))
                      (should-not (funcall beads-eldoc-directory "zzz-abc"))))
                (kill-buffer buf))))
        (delete-directory city t)))))

(ert-deftest gascity-test-beads-eldoc-install-cold-map ()
  "A cold map admits nothing, and the fill heals the open buffer.
Installing with no map sets the deny-all allowlist and a resolver that
answers nil; once the map lands, `gascity-beads-eldoc--reapply-buffers'
re-applies it to the already-open buffer — no reopen, no revert
\(REQ-006) — and prunes dead buffers from the registry."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city))
          (buf (generate-new-buffer " *gascity-eldoc-cold*"))
          (dead (generate-new-buffer " *gascity-eldoc-dead*")))
      (unwind-protect
          (progn
            (with-current-buffer buf (setq default-directory city))
            (gascity-test-eldoc--with-map nil
              (should (eq (gascity-beads-eldoc-install buf) buf))
              (with-current-buffer buf
                (should (equal gascity-beads-eldoc--scope city))
                (should-not gascity-beads-eldoc--map)
                (should (functionp beads-eldoc-directory))
                (should-not (funcall beads-eldoc-directory "gce-abc"))
                (should (equal beads-issue-id-prefixes
                               gascity-beads-eldoc--deny-all-prefixes)))
              (with-current-buffer dead
                (setq default-directory city)
                (gascity-beads-eldoc-install dead))
              (should (memq buf (gascity-beads-eldoc--live-buffers city)))
              (kill-buffer dead)
              ;; The fill lands: the landed map is in the city's map table,
              ;; and the registry re-applies it to the open buffer, pruning
              ;; the dead one.
              (puthash (gascity-context-scope-key city)
                       (gascity-test-eldoc--warm-map)
                       gascity-beads-eldoc--maps)
              (gascity-beads-eldoc--reapply-buffers city)
              (should-not (memq dead (gascity-beads-eldoc--live-buffers city)))
              (with-current-buffer buf
                (should (equal beads-issue-id-prefixes '("gce" "be")))
                (should (equal (funcall beads-eldoc-directory "be-abc")
                               "/p/beads.el/")))))
        (when (buffer-live-p buf) (kill-buffer buf))
        (when (buffer-live-p dead) (kill-buffer dead))
        (delete-directory city t)))))

(ert-deftest gascity-test-beads-eldoc-install-captures-context ()
  "The install captures the city at install time (REQ-008, TS-4).
An attach buffer whose `default-directory' sits in a worktree outside the
city tree still resolves the city and its rigs, and a later
`default-directory' change cannot re-scope it."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city))
          (worktree (file-name-as-directory
                     (make-temp-file "gascity-eldoc-worktree" t)))
          (asked nil)
          (map (gascity-test-eldoc--warm-map)))
      (unwind-protect
          (let ((buf (generate-new-buffer " *gascity-eldoc-attach*")))
            (unwind-protect
                (progn
                  (with-current-buffer buf (setq default-directory worktree))
                  ;; The attach passes the origin city explicitly.
                  (cl-letf (((symbol-function 'gascity-beads-eldoc-map)
                             (lambda (&optional dir)
                               (setq asked dir)
                               map)))
                    (should (eq (gascity-beads-eldoc-install buf city) buf))
                    (should (equal asked city))
                    (with-current-buffer buf
                      (should (equal gascity-beads-eldoc--scope city))
                      (should (equal (funcall beads-eldoc-directory "be-abc")
                                     "/p/beads.el/"))
                      ;; Re-pinning the buffer elsewhere cannot re-scope it.
                      (setq default-directory "/")
                      (should (equal gascity-beads-eldoc--scope city))
                      (should (equal (funcall beads-eldoc-directory "gce-a")
                                     "/p/gascity.el/")))))
              (kill-buffer buf)))
        (delete-directory city t)
        (delete-directory worktree t)))))

(ert-deftest gascity-test-beads-eldoc-install-no-city-is-a-no-op ()
  "Without a city root the install sets nothing and starts no fill (D8).
A map keyed by the bare host prefix would be shared by every local city
\(REQ-007), so the buffer keeps beads.el's own behavior instead."
  (gascity-test-eldoc--with-contract
    (let ((outside (file-name-as-directory
                    (make-temp-file "gascity-eldoc-inner" t)))
          (buf (generate-new-buffer " *gascity-eldoc-nocity*")))
      (unwind-protect
          (progn
            ;; The walk must find no `city.toml' above the temp root either:
            ;; a temp dir under /tmp is outside any city tree.
            (with-current-buffer buf (setq default-directory outside))
            (cl-letf (((symbol-function 'gascity-beads-eldoc-map)
                       (lambda (&rest _) (error "started a fill"))))
              (should-not (gascity-beads-eldoc-install buf))
              (with-current-buffer buf
                (should-not gascity-beads-eldoc--scope)
                (should-not gascity-beads-eldoc--map)
                (should-not (local-variable-p 'beads-eldoc-directory))
                (should-not (local-variable-p 'beads-issue-id-prefixes)))))
        (kill-buffer buf)
        (delete-directory outside t)))))

(ert-deftest gascity-test-beads-eldoc-install-without-contract ()
  "A beads.el without the eldoc variables is left alone, no error.
Same soft-require compatibility as the terminal wiring it replaces
\(REQ-018)."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city)))
      (unwind-protect
          (gascity-test-eldoc--with-map (gascity-test-eldoc--warm-map)
            (with-temp-buffer
              (setq default-directory city)
              ;; Void the automatically buffer-local variables in THIS
              ;; buffer only; a `setq-local' would re-bind them.
              (makunbound 'beads-eldoc-directory)
              (makunbound 'beads-issue-id-prefixes)
              (should-not (boundp 'beads-eldoc-directory))
              (gascity-beads-eldoc-install (current-buffer))
              (should-not (boundp 'beads-eldoc-directory))
              (should-not (boundp 'beads-issue-id-prefixes))))
        (delete-directory city t)))))

(ert-deftest gascity-test-beads-eldoc-install-cold-starts-one-async-read ()
  "A cold install starts the map's read asynchronously, never synchronously.
Installing is the map's first need (REQ-006): exactly one `gc rig list'
read through the store, no `gc`/`bd` on the command loop (REQ-005,
REQ-012, D9)."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city)))
      (unwind-protect
          (progn
            (gascity-test-eldoc--clear-maps)
            (gascity-test-with-store-stubs reads actions
              (cl-letf (((symbol-function 'gascity-reader-run)
                         (lambda (args) (error "synchronous gc run: %S" args)))
                        ((symbol-function 'process-file)
                         (lambda (program &rest _)
                           (error "process-file %s" program)))
                        ((symbol-function 'call-process)
                         (lambda (program &rest _)
                           (error "call-process %s" program))))
                (with-temp-buffer
                  (setq default-directory city)
                  (should (gascity-beads-eldoc-install (current-buffer)))
                  (should (= (length reads) 1))
                  (should (equal (car (car reads)) '("rig" "list")))
                  (should-not actions)
                  (should-not (buffer-local-value
                               'gascity-beads-eldoc--map (current-buffer)))))))
        (gascity-test-eldoc--clear-maps)
        (delete-directory city t)))))

(ert-deftest gascity-test-beads-eldoc-install-no-spawn ()
  "Installing a cold or warm buffer never runs gc or bd (REQ-012, D9).
Opening a view or an attach must stay spawn-free; the map's own async
fill is the only read."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city)))
      (unwind-protect
          (cl-letf (((symbol-function 'gascity-reader-run)
                     (lambda (&rest _) (error "spawned gc")))
                    ((symbol-function 'gascity-reader-run-async)
                     (lambda (&rest _) (error "spawned gc")))
                    ((symbol-function 'gascity-command-rig-list!)
                     (lambda (&rest _) (error "spawned gc rig list"))))
            (dolist (map (list nil (gascity-test-eldoc--warm-map)))
              (gascity-test-eldoc--with-map map
                (with-temp-buffer
                  (setq default-directory city)
                  (should (gascity-beads-eldoc-install (current-buffer)))))))
        (delete-directory city t)))))

;;; Major-mode survival (TS-5)

(ert-deftest gascity-test-beads-eldoc-install-survives-major-mode ()
  "Enabling a major mode keeps the wiring (TS-5).
The view factory installs before the mode runs, and the mode's
`kill-all-local-variables' drops both auto buffer-local variables; the
permanent-local scope and map reinstall them on
`after-change-major-mode-hook'."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city)))
      (unwind-protect
          (gascity-test-eldoc--with-map (gascity-test-eldoc--warm-map)
            (let ((buf (generate-new-buffer " *gascity-eldoc-mode*")))
              (unwind-protect
                  (progn
                    (with-current-buffer buf (setq default-directory city))
                    (gascity-beads-eldoc-install buf)
                    (with-current-buffer buf
                      (text-mode)
                      ;; The permanent-local snapshot survived the mode ...
                      (should (equal gascity-beads-eldoc--scope city))
                      (should gascity-beads-eldoc--map)
                      ;; ... and the hook reinstalled the contract.
                      (should (functionp beads-eldoc-directory))
                      (should (equal beads-issue-id-prefixes '("gce" "be")))
                      (should (equal (funcall beads-eldoc-directory "be-abc")
                                     "/p/beads.el/"))))
                (kill-buffer buf))))
        (delete-directory city t)))))

;;; The clear seam

(ert-deftest gascity-test-beads-eldoc-clear-cache-goes-cold ()
  "The clear seam puts an installed buffer back in the cold deny-all state.
`gascity-beads-eldoc-clear-cache-functions' is registered by the install
path (not only defined by the refresh slice): after the maps are dropped,
the same buffer's resolver must answer nil instead of the dropped map,
and its prefix set must go cold (REQ-007, REQ-010)."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city)))
      (unwind-protect
          (gascity-test-eldoc--with-map (gascity-test-eldoc--warm-map)
            (let ((buf (gascity-view-get-buffer-create
                        "*gascity-eldoc-cold-reset*" city)))
              (unwind-protect
                  (with-current-buffer buf
                    ;; Warm through the factory.
                    (should (equal beads-issue-id-prefixes '("gce" "be")))
                    (should (equal (funcall beads-eldoc-directory "be-abc")
                                   "/p/beads.el/"))
                    ;; The seam drops the maps and runs the hook; the reader
                    ;; is cold, so the reinstall starts the one fill.
                    (clrhash gascity-beads-eldoc--maps)
                    (cl-letf (((symbol-function 'gascity-beads-eldoc-map)
                               (lambda (&optional _dir) nil)))
                      (run-hooks 'gascity-beads-eldoc-clear-cache-functions))
                    (should (equal beads-issue-id-prefixes
                                   gascity-beads-eldoc--deny-all-prefixes))
                    (should-not (funcall beads-eldoc-directory "be-abc"))
                    (should-not gascity-beads-eldoc--map))
                (kill-buffer buf))))
        (gascity-test-eldoc--clear-maps)
        (gascity-context-clear-cache)
        (delete-directory city t)))))

(ert-deftest gascity-test-beads-eldoc-context-clear-goes-cold ()
  "An explicit context clear drops the map and cools the same buffer in place.
End to end on the merged tree: `gascity-context-clear-cache' drops every
city map, the install path's handler reinstalls the open buffer against the
cold table (deny-all, nil resolver, zero maps), and one landed fill heals
it in the same buffer without a reopen (REQ-010, REQ-006)."
  (skip-unless (fboundp 'gascity-beads-eldoc-clear-cache))
  (gascity-test-eldoc--with-contract
    (let* ((city (gascity-test-eldoc--make-city))
           (scope (gascity-context-scope-key city)))
      (unwind-protect
          (progn
            (gascity-test-eldoc--clear-maps)
            (puthash scope (gascity-test-eldoc--warm-map)
                     gascity-beads-eldoc--maps)
            (let ((buf (generate-new-buffer " *gascity-eldoc-clear-e2e*")))
              (unwind-protect
                  (progn
                    (with-current-buffer buf (setq default-directory city))
                    (should (eq (gascity-beads-eldoc-install buf) buf))
                    (with-current-buffer buf
                      (should (equal beads-issue-id-prefixes '("gce" "be")))
                      ;; Never start a real store read from the clear.
                      (cl-letf (((symbol-function 'gascity-beads-eldoc--fill)
                                 (lambda (&rest _) nil)))
                        (gascity-context-clear-cache))
                      ;; The clear dropped every warm map; the reinstall's
                      ;; one deduplicated fill may create a fresh COLD entry
                      ;; (S1 says it must start that fill), so assert no warm
                      ;; snapshot for the scope rather than an empty table.
                      (let ((entry (gethash scope gascity-beads-eldoc--maps)))
                        (should-not (and entry
                                         (gascity-beads-eldoc--map-fetched-at
                                          entry))))
                      (should (equal beads-issue-id-prefixes
                                     gascity-beads-eldoc--deny-all-prefixes))
                      (should-not (funcall beads-eldoc-directory "be-abc"))
                      ;; A later fill lands: the registered buffer heals in
                      ;; place through the registry re-apply.
                      (puthash scope (gascity-test-eldoc--warm-map)
                               gascity-beads-eldoc--maps)
                      (gascity-beads-eldoc--reapply-buffers city)
                      (should (equal beads-issue-id-prefixes '("gce" "be")))
                      (should (equal (funcall beads-eldoc-directory "be-abc")
                                     "/p/beads.el/"))))
                (kill-buffer buf))))
        (gascity-test-eldoc--clear-maps)
        (gascity-context-clear-cache)
        (delete-directory city t)))))

;;; The view factory

(ert-deftest gascity-test-beads-eldoc-view-factory-installs ()
  "Every factory view gets the contract, and the old memo shortcut is gone.
The factory no longer sets the allowlist from the warm rig memo: with a
cold map the buffer must deny every id, not accept the memo's prefixes
\(REQ-001, REQ-006)."
  (gascity-test-eldoc--with-contract
    (let ((city (gascity-test-eldoc--make-city)))
      (unwind-protect
          (progn
            ;; A warm rig memo must not leak into a cold-map view.
            (gascity-rigs-remember
             (gascity-domain-decode-list
              'gascity-rig
              (vector '((name . "gascity.el") (prefix . "gce")
                        (path . "/p/gascity.el"))))
             city)
            (gascity-test-eldoc--with-map nil
              (let ((buf (gascity-view-get-buffer-create
                          "*gascity-eldoc-view-cold*" city)))
                (unwind-protect
                    (with-current-buffer buf
                      (should (equal gascity-beads-eldoc--scope city))
                      (should (equal beads-issue-id-prefixes
                                     gascity-beads-eldoc--deny-all-prefixes)))
                  (kill-buffer buf))))
            (gascity-test-eldoc--with-map (gascity-test-eldoc--warm-map)
              (let ((buf (gascity-view-get-buffer-create
                          "*gascity-eldoc-view-warm*" city)))
                (unwind-protect
                    (with-current-buffer buf
                      (should (functionp beads-eldoc-directory))
                      (should (equal beads-issue-id-prefixes '("gce" "be")))
                      (should (equal (funcall beads-eldoc-directory "be-abc")
                                     "/p/beads.el/")))
                  (kill-buffer buf)))))
        (gascity-context-clear-cache)
        (delete-directory city t)))))

;;; Terminal attach

(ert-deftest gascity-test-terminal-attach-beads-eldoc-is-per-id ()
  "An attach buffer's eldoc resolves per id, even with a known agent store.
The attach's STORE keeps its `project' job only; bead ids resolve through
the captured city's map — a `be-' id opens the beads.el store, not the
agent's rig store (REQ-002, plan §B)."
  (gascity-test-eldoc--with-contract
    (let* ((city (gascity-test-eldoc--make-city))
           (rig (file-name-as-directory
                 (make-temp-file "gascity-eldoc-rig" t)))
           (store rig)
           (workdir (file-name-as-directory
                     (expand-file-name "worktrees/w" rig)))
           (sess "sess")
           spawned)
      (make-directory workdir t)
      (unwind-protect
          (gascity-test-eldoc--with-map (gascity-test-eldoc--warm-map)
            (let ((default-directory city))
              (cl-letf (((symbol-function 'gascity-terminal--run-async)
                         (lambda (_dir _script callback)
                           (funcall callback '(0 . "beads-ok\n"))))
                        ((symbol-function 'gascity-terminal--attach-argv)
                         (lambda (&rest _) '("true")))
                        ((symbol-function 'gascity-terminal--status-install)
                         (lambda (&rest _) nil))
                        ((symbol-function 'beads-terminal-spawn)
                         (lambda (_term buffer-name _argv dir _env)
                           (setq spawned (get-buffer-create buffer-name))
                           (with-current-buffer spawned
                             (setq default-directory dir))
                           spawned))
                        ((symbol-function 'pop-to-buffer)
                         (lambda (b &rest _) b)))
                (gascity-terminal-attach-tmux sess nil workdir store)
                (should spawned)
                (with-current-buffer spawned
                  (should (functionp beads-eldoc-directory))
                  (should (equal (funcall beads-eldoc-directory "be-abc")
                                 "/p/beads.el/"))
                  (should (equal (funcall beads-eldoc-directory "gce-abc")
                                 "/p/gascity.el/"))
                  (should (equal gascity-beads-eldoc--scope city))
                  (should (equal gascity-context-project-root store)))))
            (when (buffer-live-p spawned) (kill-buffer spawned)))
        (delete-directory city t)
        (delete-directory rig t)))))
