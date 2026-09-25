;;; gascity-consistency-test.el --- One key, one meaning, in every view -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The dashboard-v3 §10 P2 key acceptance, extended to every view on
;; main and driven by tables:
;;
;; - `gascity-consistency--views': every view keymap, its kind (`vui' or
;;   `list') and whether it shows agents.  Add a view (runs, comms, …)
;;   by adding a row.
;; - `gascity-consistency--globals', `--section-keys', `--agent-keys'
;;   (and `--verb-families'): every key with a fixed meaning (§5.1
;;   globals, §5.3 agent keys) and the commands allowed under it.  A
;;   key bound to anything outside its set is a collision: the same key
;;   meaning an unrelated verb in some view.
;;
;; The `?' dispatch is checked against the same table, so it keeps
;; teaching the view keys.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)

(defconst gascity-consistency--views
  '((cockpit        gascity-dashboard-mode-map      vui  t)
    (agents         gascity-agents-mode-map         list t)
    (agents-tree    gascity-agents-tree-mode-map    vui  t)
    (agent-detail   gascity-session-detail-mode-map vui  t :skip ("i"))
    (rig-dashboard  gascity-rig-dashboard-mode-map  vui  t)
    (runs           gascity-runs-mode-map           vui  nil)
    (run-detail     gascity-run-mode-map            vui  nil)
    (health         gascity-health-mode-map         vui  nil)
    (cities         gascity-cities-mode-map         list nil)
    (rig-list       gascity-rig-list-mode-map       list nil)
    (session-list   gascity-session-list-mode-map   list t)
    (convoy-list    gascity-convoy-list-mode-map    list nil)
    (mail-inbox     gascity-mail-inbox-mode-map     list nil)
    (events         gascity-events-mode-map         list nil)
    (mail-thread    gascity-mail-thread-mode-map    text nil)
    (order-list     gascity-order-list-mode-map     list nil)
    (dolt-list      gascity-dolt-list-mode-map      list nil))
  "Every gascity view: (NAME MAP KIND SHOWS-AGENTS &rest PLIST).
KIND is `vui' (sectioned: `N'/`P' jump sections), `list' (tabulated:
no sections, SPC opens the detail window, `q' closes it first) or
`text' (a `special-mode' reader such as a mail thread: globals only).
PLIST :skip names agent keys the view does not bind on purpose (the
agent detail is already the agent's detail: no `i').")

(defconst gascity-consistency--globals
  '(("g")                               ; bound; each view's own refresh
    ("W" gascity-live-toggle)
    ("q" quit-window gascity-tabulated-quit)
    ("?" gascity-dispatch)
    ("j j" gascity-jump-cockpit)
    ("j a" gascity-jump-agents)
    ("TAB" gascity-thing-forward)
    ("<tab>" gascity-thing-forward)
    ("<backtab>" gascity-thing-backward)
    ("S-<tab>" gascity-thing-backward)
    ("SPC" gascity-thing-toggle)
    ("DEL" undefined)
    ("RET")                             ; bound; acts on the thing at point
    ("/")                               ; bound; the view's filter or none
    ("S" gascity-sling-dispatch))
  "§5.1 globals: (KEY . ALLOWED); an empty ALLOWED only requires a binding.")

(defconst gascity-consistency--section-keys
  '(("N" gascity-section-next)
    ("P" gascity-section-previous))
  "Section jumps: every sectioned (vui) view.")

(defconst gascity-consistency--agent-keys
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
  "§5.3 agent keys and the commands they may mean in a view with agents.
The cockpit's `s'/`R' decide by row (agent or rig).")

(defconst gascity-consistency--verb-families
  '(("s" gascity-rig-suspend-at-point)
    ("R" gascity-rig-restart-at-point gascity-mail-reply-at-point)
    ("d" gascity-rig-list-dired)
    ("t" gascity-runs-agent-tmux)
    ("i" gascity-runs-agent-detail gascity-events-agent)
    ("v" gascity-runs-agent-peek))
  "Other members of an agent key's verb family, allowed in views without
agent rows (§4.5: `s' suspends a rig too; `R' reply shares with the
confirmed reset/restart; the run views reach a step's live worker).")

(defun gascity-consistency--map (view)
  "Return the keymap of VIEW."
  (symbol-value (nth 1 view)))

(defun gascity-consistency--lookup (map key)
  "Return MAP's command for KEY, the symbol when it is one."
  (let ((cmd (keymap-lookup map key)))
    (if (and (consp cmd) (eq (car cmd) 'lambda)) 'lambda cmd)))

(ert-deftest gascity-test-consistency-globals ()
  "§5.1: every view binds the globals, each to its one meaning."
  (dolist (view gascity-consistency--views)
    (let ((map (gascity-consistency--map view)))
      (pcase-dolist (`(,key . ,allowed) gascity-consistency--globals)
        (let ((cmd (gascity-consistency--lookup map key)))
          (ert-info ((format "%s: %s → %S" (car view) key cmd))
            (should cmd)
            (when allowed (should (memq cmd allowed))))))
      (when (eq (nth 2 view) 'vui)
        (pcase-dolist (`(,key . ,allowed) gascity-consistency--section-keys)
          (ert-info ((format "%s: %s" (car view) key))
            (should (memq (gascity-consistency--lookup map key) allowed))))))))

(ert-deftest gascity-test-consistency-agent-keys ()
  "§5.3: the agent keys mean the same command in every view with agents."
  (dolist (view gascity-consistency--views)
    (when (nth 3 view)
      (let ((map (gascity-consistency--map view))
            (skip (plist-get (nthcdr 4 view) :skip)))
        (pcase-dolist (`(,key . ,allowed) gascity-consistency--agent-keys)
          (unless (member key skip)
            (let ((cmd (gascity-consistency--lookup map key)))
              (ert-info ((format "%s: %s → %S" (car view) key cmd))
                (should (memq cmd allowed))))))))))

(ert-deftest gascity-test-consistency-no-collisions ()
  "No view binds a fixed key to an unrelated verb, agents or not."
  (dolist (view gascity-consistency--views)
    (let ((map (gascity-consistency--map view)))
      (pcase-dolist (`(,key . ,allowed) gascity-consistency--agent-keys)
        (let ((cmd (gascity-consistency--lookup map key)))
          (when (and cmd (not (eq cmd 'undefined)))
            (ert-info ((format "%s: %s → %S" (car view) key cmd))
              (should (memq cmd (append allowed
                                        (cdr (assoc key gascity-consistency--verb-families)))))))))
      ;; Section jumps never mean anything else where they are bound.
      (pcase-dolist (`(,key . ,allowed) gascity-consistency--section-keys)
        (let ((cmd (gascity-consistency--lookup map key)))
          (when cmd
            (ert-info ((format "%s: %s → %S" (car view) key cmd))
              (should (memq cmd allowed)))))))))

(ert-deftest gascity-test-consistency-lists-close-detail-first ()
  "Every list binds `q' to close the detail window before burying, and
routes SPC on a row to that window through the thing hook."
  (dolist (view gascity-consistency--views)
    (when (eq (nth 2 view) 'list)
      (should (eq (keymap-lookup (gascity-consistency--map view) "q")
                  #'gascity-tabulated-quit))))
  ;; Behaviour, on one list: SPC opens the window, `q' closes it and
  ;; leaves the list; a second `q' buries.
  (let ((buf (get-buffer-create "*gascity-consistency-list*"))
        (buried nil))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (switch-to-buffer buf)
          (cl-letf (((symbol-function 'gascity-convoy-list-refresh) #'ignore)
                    ((symbol-function 'quit-window) (lambda (&rest _) (setq buried t))))
            (gascity-convoy-list-mode)
            (gascity-tabulated--init-paged
             "Convoys" (list (list '((id . "ga-1")) (vector "ga-1" "t" "open" "0/1"))))
            (goto-char (point-min))
            (gascity-thing-toggle)
            (should (gascity-tabulated--detail-window))
            (gascity-tabulated-quit)
            (should-not (gascity-tabulated--detail-window))
            (should-not buried)
            (gascity-tabulated-quit)
            (should buried)))
      (kill-buffer buf)
      (when (get-buffer "*gascity-detail*") (kill-buffer "*gascity-detail*")))))

(ert-deftest gascity-test-consistency-dispatch-teaches-view-keys ()
  "Every `?' suffix under a fixed key means what that key means in the
views; the dispatch's keys are unique."
  (let ((table (append gascity-consistency--globals
                       gascity-consistency--agent-keys
                       gascity-consistency--section-keys))
        (keys nil))
    (dolist (key '("j j" "j a" "j r" "j b" "j m" "j e" "j h" "j c" "j o" "j v"
                   "j d" "j g" "M" "s" "w" "K" "D" "R" "U" "t" "S" "c" "m" "L"
                   "C" "O" "W" "g" "/"))
      (let* ((suffix (transient-get-suffix 'gascity-dispatch key))
             (cmd (plist-get (cdr suffix) :command))
             (allowed (cdr (assoc key table))))
        (push key keys)
        (ert-info ((format "? %s → %S" key cmd))
          (should cmd)
          (when allowed (should (memq cmd allowed))))))
    (should (= (length keys) (length (delete-dups (copy-sequence keys)))))))

(ert-deftest gascity-test-consistency-needs-you-ret-routes ()
  "RET on a Needs-you row opens the real view: a lost session the Agents
view, mail the inbox, store health the Health view, a failed run its
run detail."
  (require 'gascity-cockpit-test)
  (let* ((events (list '((type . "session.cold_start_timeout") (seq . 1)
                         (subject . "gc__w-ec-abc1") (ts . "2026-09-25T12:00:00Z"))
                       '((type . "bead.closed") (seq . 2) (ts . "2026-09-25T12:01:00Z")
                         (payload . ((bead . ((id . "be-j2b")
                                              (metadata . ((gc.kind . "workflow")
                                                           (gc.outcome . "fail"))))))))))
         (ctx (gascity-cockpit-test--ctx
               :events events :mail '((unread . 2))
               :status '((rigs . [((name . "beads.el") (prefix . "be"))])
                         (summary . ((store_health . ((warning . t))))))))
         (opened nil))
    (with-temp-buffer
      (let ((gascity-dashboard--view nil))
        (insert (string-join (gascity-dashboard--needs-you-lines ctx) "\n")))
      (cl-letf (((symbol-function 'gascity-jump-agents)
                 (lambda () (interactive) (push 'agents opened)))
                ((symbol-function 'gascity-jump-mail)
                 (lambda () (interactive) (push 'mail opened)))
                ((symbol-function 'gascity-jump-health)
                 (lambda () (interactive) (push 'health opened)))
                ((symbol-function 'gascity-run-show)
                 (lambda (id _c rig) (push (list 'run id rig) opened))))
        (dolist (re '("cold start timeout" "be-j2b" "unread" "per row"))
          (goto-char (point-min))
          (re-search-forward re)
          (gascity-dashboard-activate))))
    (should (equal (reverse opened)
                   '(agents (run "be-j2b" "beads.el") mail health)))))

(provide 'gascity-consistency-test)
;;; gascity-consistency-test.el ends here
