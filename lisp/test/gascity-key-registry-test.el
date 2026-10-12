;;; gascity-key-registry-test.el --- Effective key registry (F1/F4/F7/F11) -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The cross-package key registry (plans/ux/magit-parity-plan.md §4.1 and
;; §5.2; docs/key-registry.md): the contract keys and the at-point agent
;; keys asserted against each view's *effective* keymap, so a parent-map
;; redefinition cannot silently re-point a reserved key (F11).  It also
;; pins the F1 namespacing (the `a' agent prefix in mixed views and the
;; declared agent-only single-letter exception), the F4 one dispatch
;; (`M-x gascity' is a thin front door to `gascity-dispatch'), and the
;; F7 header hint.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)

(defconst gascity-key-registry--views
  ;; (NAME MAP KIND SHOWS-AGENTS NAMESPACED)
  '((cockpit        gascity-dashboard-mode-map      vui  t nil)
    (rig-dashboard  gascity-rig-dashboard-mode-map  vui  t t)
    (agent-detail   gascity-session-detail-mode-map vui  t t)
    (agents-tree    gascity-agents-tree-mode-map    vui  t nil)
    (agents         gascity-agents-mode-map         list t nil)
    (session-list   gascity-session-list-mode-map   list t nil)
    (runs           gascity-runs-mode-map           vui  nil nil)
    (run-detail     gascity-run-mode-map            vui  nil nil)
    (health         gascity-health-mode-map         vui  nil nil)
    (cities         gascity-cities-mode-map         list nil nil)
    (rig-list       gascity-rig-list-mode-map       list nil nil)
    (convoy-list    gascity-convoy-list-mode-map    list nil nil)
    (order-list     gascity-order-list-mode-map     list nil nil)
    (dolt-list      gascity-dolt-list-mode-map      list nil nil)
    (events         gascity-events-mode-map         list nil nil)
    (mail-inbox     gascity-mail-inbox-mode-map     list nil nil)
    (mail-thread    gascity-mail-thread-mode-map    text nil nil))
  "Every gascity view: (NAME MAP KIND SHOWS-AGENTS NAMESPACED).
KIND is `vui', `list' or `text'; NAMESPACED means the view can also hold
beads, so its agent verbs live under the `a' prefix (F1).")

(defconst gascity-key-registry--contract
  '("q" "g" "?" "j" "TAB" "S-TAB" "SPC" "RET")
  "The universal navigation contract, in every view (mail thread included).")

(defconst gascity-key-registry--vui-contract
  '("n" "p" "N" "P")
  "Line and section movement: every vui view.")

(defconst gascity-key-registry--namespaced-verbs
  '(("n" . gascity-session-nudge-at-point)
    ("s" . gascity-dashboard-suspend)
    ("w" . gascity-session-wake-at-point)
    ("k" . gascity-session-kill-at-point)
    ("D" . gascity-session-drain-at-point)
    ("r" . gascity-dashboard-reset)
    ("u" . gascity-session-undrain-at-point)
    ("t" . gascity-tmux-at-point)
    ("d" . gascity-dired-at-point)
    ("i" . gascity-polecat-detail-at-point)
    ("v" . gascity-session-peek-at-point))
  "The `a' prefix: namespaced key → effective command (F1).")

(defconst gascity-key-registry--agent-only-verbs
  '(("t" gascity-tmux-at-point)
    ("i" gascity-polecat-detail-at-point)
    ("v" gascity-session-peek-at-point)
    ("d" gascity-dired-at-point)
    ("M" gascity-session-nudge-at-point)
    ("s" gascity-session-suspend-at-point gascity-dashboard-suspend)
    ("K" gascity-session-kill-at-point)
    ("w" gascity-session-wake-at-point)
    ("D" gascity-session-drain-at-point)
    ("R" gascity-session-reset-at-point gascity-dashboard-reset)
    ("U" gascity-session-undrain-at-point))
  "The agent-only exception: bare key → the commands it may mean.
These views never hold a bead, so the fast single-letter aliases cannot
change meaning for one.")

(defconst gascity-key-registry--forbidden
  '("d" "s" "w" "i" "t" "D" "C" "#")
  "Keys reserved for beads.el in any view that can hold a bead (F1).")

(defun gascity-key-registry--map (view)
  "Return VIEW's keymap."
  (symbol-value (nth 1 view)))

(defun gascity-key-registry--lookup (map key)
  "Return MAP's command for KEY, normalizing a lambda to `lambda'."
  (let ((cmd (keymap-lookup map key)))
    (if (and (consp cmd) (eq (car cmd) 'lambda)) 'lambda cmd)))

(ert-deftest gascity-test-key-registry-contract ()
  "The universal contract keys are bound in every view (F11); `?' is the
one dispatch everywhere."
  (dolist (view gascity-key-registry--views)
    (let ((map (gascity-key-registry--map view)))
      (dolist (key gascity-key-registry--contract)
        (ert-info ((format "%s: %s" (car view) key))
          (should (gascity-key-registry--lookup map key))))
      (when (eq (nth 2 view) 'vui)
        (dolist (key gascity-key-registry--vui-contract)
          (ert-info ((format "%s: %s" (car view) key))
            (should (gascity-key-registry--lookup map key)))))
      (should (eq (gascity-key-registry--lookup map "?") 'gascity-dispatch)))))

(ert-deftest gascity-test-key-registry-namespaced-agent-verbs ()
  "F1: a view that can hold beads carries its agent verbs under `a'."
  (dolist (view gascity-key-registry--views)
    (when (eq t (nth 4 view))
      (let ((map (gascity-key-registry--map view)))
        (ert-info ((format "%s: a" (car view)))
          (should (eq (gascity-key-registry--lookup map "a")
                      'gascity-agent-prefix)))
        (pcase-dolist (`(,key . ,cmd) gascity-key-registry--namespaced-verbs)
          (ert-info ((format "%s: a %s" (car view) key))
            (should (eq (gascity-key-registry--lookup map (concat "a " key))
                        cmd))))))))

(ert-deftest gascity-test-key-registry-bead-keys-stay-beads ()
  "F1: the beads.el-reserved keys never mean a gascity agent verb in a
view that can also hold a bead."
  (dolist (view gascity-key-registry--views)
    (when (eq t (nth 4 view))
      (let ((map (gascity-key-registry--map view)))
        (dolist (key gascity-key-registry--forbidden)
          (ert-info ((format "%s: %s" (car view) key))
            (should-not (gascity-key-registry--lookup map key))))))))

(ert-deftest gascity-test-key-registry-agent-only-exception ()
  "The declared exception: agent-only views keep the fast single letters."
  (dolist (view gascity-key-registry--views)
    (when (and (eq t (nth 3 view)) (null (nth 4 view)))
      (let ((map (gascity-key-registry--map view)))
        (pcase-dolist (`(,key . ,allowed) gascity-key-registry--agent-only-verbs)
          (ert-info ((format "%s: %s" (car view) key))
            (should (memq (gascity-key-registry--lookup map key) allowed))))))))

(ert-deftest gascity-test-key-registry-one-dispatch ()
  "F4: `M-x gascity' is a thin front door to `gascity-dispatch'."
  (should (commandp 'gascity))
  ;; There is no second, differently-keyed `gascity' transient menu.
  (should-not (get 'gascity 'transient--layout))
  (should (get 'gascity-dispatch 'transient--layout))
  ;; It opens the one dispatch.
  (let (called)
    (cl-letf (((symbol-function 'gascity-dispatch)
               (lambda () (interactive) (setq called t))))
      (gascity)
      (should called))))

(ert-deftest gascity-test-key-registry-header-hint ()
  "F7: the list header hint points at `?' and `j'."
  (should (string-match-p "? all verbs" gascity-tabulated-header-hint))
  (should (string-match-p "j jump" gascity-tabulated-header-hint))
  (with-temp-buffer
    (setq-local header-line-format "columns")
    (gascity-tabulated--install-header-hint)
    (should (string-match-p "\\? all verbs" header-line-format))
    (let ((once header-line-format))
      (gascity-tabulated--install-header-hint)
      (should (equal header-line-format once)))))

(provide 'gascity-key-registry-test)
;;; gascity-key-registry-test.el ends here
