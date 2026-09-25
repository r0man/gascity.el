;;; gascity-run.el --- run detail (step graph + input convoy) -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The run-detail view (S2 of plans/dashboard-v2): one buffer rendering
;; the step graph of a graph.v2 workflow run — the drill-in behind the
;; city dashboard's Runs section (`gascity-run-show', the run root bead
;; id or the run row at point).
;;
;; Data plane: the view reads the full `gc bd list --json' payload with
;; its OWN async read (one read, independent load) and filters it
;; client-side to the run.  Membership is metadata-driven, verified
;; live: the run's root bead carries `gc.kind workflow' and
;; `gc.graphv2_root_key', but the step beads carry only
;; `gc.root_bead_id' = the root id — so grouping walks that key, not
;; the root key (the requirements' `same root key' sketch does not
;; hold for steps).  The read carries every status — progress counts
;; closed steps, which a default `bd list' hides.
;;
;; A run lives in its dispatching rig's bead store; the read scopes to
;; it with `--rig NAME' (the dashboard's fan-out stamps each row with
;; `gascity-rig', so `RET' hands the owning store along — `RET' at point
;; never needs a second `rig list').  Without a rig the view keeps its
;; own single city-scoped read; the affected-list filter keeps runs in
;; the city's other rig stores visible.
;;
;; The input convoy is joined on the run root's `gc.input_convoy_id'
;; metadata.  A caller holding the dashboard's already-loaded
;; `convoy list' row passes it as the CONVOY argument (no extra read);
;; opened outside the dashboard the view falls back to its own async
;; `gc convoy status <id> --json' read — an INDEPENDENT load, so a
;; convoy failure dims one section while the step graph keeps
;; rendering (the per-section failure rule).
;;
;; Rendering follows the city dashboard's conventions: one section per
;; step (step id, title, kind — `gc.kind' or `gc.control_for' — status,
;; assignee) in payload order, a header with phase, progress
;; closed/total and formula, a dim convoy row when an input convoy
;; exists.  Refresh is stale-while-revalidate; a failing read renders
;; the standard inline error, dim, with a retry hint — never a blank
;; pane.  No synchronous `gc' call anywhere in the module.

;;; Code:

(require 'seq)
(require 'vui)
(require 'gascity-custom)
(require 'gascity-context)            ; gascity-view-get-buffer-create
(require 'gascity-reader)             ; gascity-reader-read-async
(require 'gascity-section)            ; mode, bead-at-point, refresh
(require 'gascity-tabulated)          ; shared cell formatters (--str)
(require 'gascity-dashboard)          ; shared section vnodes (header/body)

;;; Buffer

(defconst gascity-run-buffer-name "*gascity-run*"
  "Base name of the run-detail buffer.
The `view-buffer' factory (`gascity-view-get-buffer-create') qualifies it
with the city root for a local city and the TRAMP prefix for a remote
one, so run details of different cities coexist.")

(defvar-local gascity-run--current-run nil
  "The run root bead id the buffer's mounted component was opened for.")

(defvar-local gascity-run--current-rig nil
  "The rig store the buffer's mounted component reads (`--rig' scope).
Nil when the view was opened without a rig hint — the read is then
plain city-scoped, with the affected-list fallback for runs owned by
another rig's store.")

;;; Pure selectors (raw decoded `bd list' / `convoy status' alists)

(defun gascity-run--meta (bead key)
  "Return metadata KEY (a symbol) from the raw BEAD alist, or nil."
  (alist-get key (alist-get 'metadata bead)))

(defun gascity-run--root-id (row)
  "Return the run root id for a raw bead ROW.
The run root is the workflow bead itself (`gc.kind workflow', no
`gc.root_bead_id'); a step row carries the root id in its
`gc.root_bead_id' metadata, so opening a step id climbs to the run it
belongs to.  A row with neither returns its own id."
  (or (gascity-run--meta row 'gc.root_bead_id)
      (alist-get 'id row)))

(defun gascity-run--root-row (run-id rows)
  "Return the raw row whose id is RUN-ID from `bd list' ROWS, or nil."
  (seq-find (lambda (row) (equal (alist-get 'id row) run-id))
            (append rows nil)))

(defun gascity-run--steps (run-id rows)
  "Return the step ROWS of the run rooted at RUN-ID, in payload order.
A step is a bead whose metadata carries `gc.root_bead_id' = RUN-ID; the
root itself carries no such key (verified live) and is excluded.  The
order is the payload's — gc returns dependency order for `bd list'."
  (let ((steps nil))
    (dolist (row (append rows nil) (nreverse steps))
      (let ((id (alist-get 'id row)))
        (when (and (stringp id)
                   (not (equal id run-id))
                   (equal (gascity-run--meta row 'gc.root_bead_id) run-id))
          (push row steps))))))

(defun gascity-run--progress (steps)
  "Return (CLOSED . TOTAL) for the STEPS list.
CLOSED counts steps in the \"closed\" status; TOTAL is all steps."
  (cons (seq-count (lambda (step)
                     (equal (alist-get 'status step) "closed"))
                   (append steps nil))
        (length steps)))

(defun gascity-run--phase (root)
  "Return the run's phase: the ROOT row's bead status."
  (alist-get 'status root))

(defun gascity-run--formula (root)
  "Return the run's formula (`gc.formula_name') from the ROOT row."
  (gascity-run--meta root 'gc.formula_name))

(defun gascity-run--input-convoy-id (root)
  "Return the run ROOT row's `gc.input_convoy_id', or nil."
  (gascity-run--meta root 'gc.input_convoy_id))

(defun gascity-run--convoy-pair (payload)
  "Return (CONVOY . PROGRESS) from a `gc convoy status' PAYLOAD, or nil.
CONVOY is the payload's raw `convoy' object and PROGRESS its
`{closed,total}' progress (falling back to the convoy row's own
`progress', the shape the dashboard's `convoy list' rows carry).  A
payload with no convoy object — a failed lookup, an empty fallback —
yields nil."
  (let ((convoy (alist-get 'convoy payload)))
    (and convoy
         (cons convoy (or (alist-get 'progress payload)
                          (alist-get 'progress convoy))))))

;;; Rendering (vnodes)

(defun gascity-run--status-face (status)
  "Return the face for a bead STATUS string, or nil for the default."
  (pcase (downcase (or status ""))
    ((or "closed" "deferred") 'gascity-dim)
    ("in_progress" 'gascity-running)
    ((or "blocked" "failed" "errored") 'gascity-failed)
    (_ nil)))

(defun gascity-run--header (run-id root progress)
  "Return the run header vnodes for RUN-ID.
ROOT is the run root row (nil until the bead list load lands);
PROGRESS the `gascity-run--progress' pair.  The header shows phase,
progress closed/total and formula; the title line is stamped with
`gascity-section' so `N'/`P' land on it."
  (let ((closed (car progress))
        (total (cdr progress)))
    (vui-vstack
     (vui-text (format "Run %s — %s"
                       run-id
                       (or (and root (gascity-run--formula root)) "?"))
               :face (if root 'gascity-header 'gascity-dim)
               'gascity-section t)
     (vui-text (format "phase %s · progress %s/%s"
                       (or (and root (gascity-run--phase root)) "—")
                       (or closed 0) (or total 0))
               :face 'gascity-dim))))

(defun gascity-run--step-vnode (step)
  "Return the section vnode for one STEP row.
The header carries the step id and title and is stamped with the bead
id (`RET' opens it in beads.el, DESIGN.md §4.3); the body line carries
kind (`gc.kind', else `gc.control_for'), status and assignee."
  (let* ((id (gascity-tabulated--str (alist-get 'id step)))
         (title (gascity-tabulated--str (alist-get 'title step)))
         (kind (or (gascity-run--meta step 'gc.kind)
                   (gascity-run--meta step 'gc.control_for)
                   "—"))
         (status (alist-get 'status step))
         (assignee (gascity-tabulated--str (alist-get 'assignee step)))
         (face (gascity-run--status-face status)))
    (vui-vstack
     (vui-text (format "▼ %s %s" id title)
               :face (or face 'gascity-header)
               'gascity-section t
               'gascity-bead id)
     (vui-text (format "  %s · %s · %s" kind status (or (and (not (string-empty-p assignee)) assignee) "—"))
               :face (or face 'gascity-dim)
               'gascity-bead id))))

(defun gascity-run--convoy-vnode (convoy progress)
  "Return the dim row vnode for the input CONVOY with PROGRESS."
  (let ((id (gascity-tabulated--str (alist-get 'id convoy))))
    (vui-text
     (format "  input convoy %s %s %s/%s %s"
             id
             (gascity-tabulated--str (alist-get 'status convoy))
             (or (alist-get 'closed progress) "?")
             (or (alist-get 'total progress) "?")
             (gascity-tabulated--str (alist-get 'title convoy)))
     :face 'gascity-dim
     'gascity-bead id)))

;;; Component

(vui-defcomponent gascity-run-app (run-id convoy rig)
  "Root component of the run-detail view.
RUN-ID is the run's root bead id.  CONVOY, when non-nil, is the raw
input-convoy row the caller already loaded (the dashboard's
`convoy list' payload) — the view then skips its own convoy read.
Otherwise the convoy is joined from the run root's `gc.input_convoy_id'
metadata with an independent async `gc convoy status' read.  RIG, when
non-nil, is the dispatching rig's store name — the read scopes `bd
list' to it with `--rig' (the dashboard's fan-out stamps the owning
store on every row it hands the drill-in)."
  ;; Every hook runs unconditionally, in order, every render.  The
  ;; `bd list' load is keyed on the run id and the refresh tick; the
  ;; convoy load is keyed on the convoy id the bead list resolved, so
  ;; it fires only once the root's metadata is in hand — and stays an
  ;; independent load whose failure never blanks the step graph.
  :state ((refresh-tick 0))
  :render
  (let* ((beads-res
          (vui-use-async (list 'run run-id refresh-tick)
            (lambda (resolve reject)
              (gascity-reader-read-async
               `("bd" "list" "--status"
                 "open,in_progress,blocked,deferred,closed"
                 ,@(and rig (list "--rig" rig)))
               resolve reject))))
         (last-beads (vui-use-ref nil))
         (beads-load (gascity-dashboard--effective-load beads-res last-beads))
         (rows (and (memq (plist-get beads-load :state) '(ready stale))
                    (gascity-section-beads (plist-get beads-load :data))))
         (root (and rows (gascity-run--root-row run-id rows)))
         (steps (and rows (gascity-run--steps run-id rows)))
         (progress (gascity-run--progress steps))
         (convoy-id (and root (gascity-run--input-convoy-id root)))
         (convoy-res
          (vui-use-async (list 'convoy convoy-id (and convoy t) refresh-tick)
            (lambda (resolve reject)
              (if (and convoy-id (not convoy))
                  (gascity-reader-read-async
                   (list "convoy" "status" convoy-id) resolve reject)
                (funcall resolve nil)))))
         (last-convoy (vui-use-ref nil))
         (convoy-load (gascity-dashboard--effective-load convoy-res
                                                          last-convoy))
         (convoy-pair
          (or (and convoy (cons convoy (alist-get 'progress convoy)))
              (and (memq (plist-get convoy-load :state) '(ready stale))
                   (gascity-run--convoy-pair (plist-get convoy-load
                                                        :data))))))
    (vui-vstack
     :spacing 1
     (gascity-run--header run-id root progress)
     (gascity-dashboard--section
      "steps" "Steps"
      (list :state (plist-get beads-load :state)
            :error (plist-get beads-load :error)
            :data (or root steps))
      nil
      (lambda (data)
        (if root
            (mapcar #'gascity-run--step-vnode steps)
          ;; Not in this store: the live check found runs in other rigs
          ;; of the same city — render the affected list to climb to the
          ;; owning store, never a bare "not found".
          (append
           (list (vui-text (format "  run %s not found in this store" run-id)
                           :face 'gascity-dim))
           (if (listp data)
               (mapcar #'gascity-run--affected-row data)
             nil)
           (list (vui-text "  press g to retry" :face 'gascity-dim)))))
      (lambda (_) (and root (length steps))))
     (gascity-dashboard--section
      "convoy" "Input convoy"
      (list :state (if root (plist-get convoy-load :state) 'ready)
            :error (plist-get convoy-load :error)
            :data convoy-pair)
      nil
      (lambda (pair)
        (if pair
            (list (gascity-run--convoy-vnode (car pair) (cdr pair)))
          (list (vui-text "  (no input convoy)" :face 'gascity-dim))))
      (lambda (pair) (and pair 1)))
     (vui-text "g refresh · RET open bead · N/P section · q bury"
               :face 'gascity-dim))))

(defun gascity-run--affected-row (run)
  "Return a dim vnode for an affected RUN row (the not-found fallback).
RUN is a raw bead row from the city's affected-list read; the row is
stamped with the bead id so `RET' opens the run drill-in from here
with the owning rig resolved from the row's `gascity-rig' stamp."
  (let ((id (gascity-tabulated--str (alist-get 'id run))))
    (vui-text
     (format "  affected %s %s %s"
             id
             (gascity-tabulated--str (alist-get 'status run))
             (gascity-tabulated--str (alist-get 'title run)))
     :face 'gascity-dim
     'gascity-bead id
     'gascity-run-rig (alist-get 'gascity-rig run))))

;;; Mode

(defvar-keymap gascity-run-mode-map
  :doc "Keymap for `gascity-run-mode'."
  :parent gascity-section-mode-map
  "g"   #'gascity-run-refresh
  "RET" #'gascity-run-activate)

(define-derived-mode gascity-run-mode gascity-section-mode "GC-Run"
  "Major mode for the workflow run-detail view.

\\{gascity-run-mode-map}"
  :interactive nil
  :group 'gascity
  (setq truncate-lines t)
  (setq-local header-line-format
              " Run detail  (g refresh · RET open bead · N/P section · q bury)"))

;;; Commands

(defun gascity-run--mount (buffer run-id convoy rig)
  "Mount the run-detail component for RUN-ID in BUFFER.
CONVOY is the optional pre-joined input-convoy row; RIG the optional
owning rig store (see `gascity-run-app').  The buffer's run identity
is recorded in `gascity-run--current-run' / `gascity-run--current-rig'."
  (with-current-buffer buffer
    (unless (derived-mode-p 'gascity-run-mode)
      (gascity-run-mode)))
  ;; vui-mount switches to the buffer internally; contain that so the
  ;; buffer is displayed once, via `pop-to-buffer', by the caller.
  (save-window-excursion
    (vui-mount (vui-component 'gascity-run-app
                              :run-id run-id :convoy convoy :rig rig)
               (buffer-name buffer)))
  (with-current-buffer buffer
    (setq gascity-run--current-run run-id
          gascity-run--current-rig rig)))

(defun gascity-run-refresh ()
  "Reload the run detail's data, preserving point."
  (interactive)
  (unless (gascity-section-refresh-instance (current-buffer))
    (user-error "No run detail to refresh here")))

(defun gascity-run-activate ()
  "Open the thing at point.
An affected-list row (the not-found fallback, stamped with its owning
rig) re-drills into that run's detail scoped to the store; a plain bead
id opens in beads.el scoped to its store."
  (interactive)
  (cond ((and (get-text-property (point) 'gascity-run-rig)
              (gascity-bead-at-point))
         (gascity-run-show (gascity-bead-at-point) nil
                           (get-text-property (point) 'gascity-run-rig)))
        ((gascity-bead-at-point)
         (gascity-bead-show-at-point))
        (t (gascity-section-activate))))

;;;###autoload
(defun gascity-run-show (run &optional convoy rig)
  "Show the workflow run whose root bead id is RUN.
RUN is the run's root bead id, or the run row at point in the city
dashboard's Runs section (a step id climbs to its run root).  The
buffer is created through `gascity-view-get-buffer-create'
\(host-qualified name, pinned `default-directory'), so local and TRAMP
access modes coexist (REQ-011); the step graph renders from the view's
own async `gc bd list' read, filtered client-side to the run.

CONVOY, when non-nil, is the raw input-convoy row the caller already
loaded (the dashboard's `convoy list' payload) — the view skips its
own convoy read.  Without it, the input convoy is joined from the run
root's `gc.input_convoy_id' metadata with the view's own async
`gc convoy status <id> --json' read.

RIG, when non-nil, scopes the bead-list read to that rig's store with
`--rig' — the dashboard's fan-out stamps each run row with the store
it came from (`gascity-run-rig' property), so `RET' at point opens the
run against its owning store and never needs a second `rig list'.  A
run opened without a rig reads the city store city-scoped; when the
run is not there, the Steps section renders the city's affected-list
rows (whose rows re-drill with their own rig stamp).  Re-opening the
same run refreshes in place; a different run — or the same run with a
newly resolved rig — remounts the buffer."
  (interactive
   (list (or (gascity-bead-at-point)
             (read-string "Run root bead id: "))))
  (setq run (and (stringp run) (string-trim run)))
  (unless (and run (not (string-empty-p run)))
    (user-error "No run root bead id"))
  (let ((buf (gascity-view-get-buffer-create gascity-run-buffer-name)))
    (cond
     ;; Same run, same store: refresh in place when a component is live
     ;; (cold-mount otherwise — the buffer may have lost it).
     ((and (equal (buffer-local-value 'gascity-run--current-run buf) run)
           (equal (buffer-local-value 'gascity-run--current-rig buf) rig))
      (or (gascity-section-refresh-instance buf)
          (gascity-run--mount buf run convoy rig)))
     ;; A buffer never mounted for a run yet (fresh factory buffer or one
      ;; whose instance died): mount it directly.
     ((null (buffer-local-value 'gascity-run--current-run buf))
      (gascity-run--mount buf run convoy rig))
     ;; Same run re-opened with a resolved rig: remount so the read
     ;; re-scopes to the owning store.
     ((and (equal (buffer-local-value 'gascity-run--current-run buf) run)
           (not (equal (buffer-local-value 'gascity-run--current-rig buf) rig)))
      (gascity-run--mount buf run convoy rig))
     (t
      ;; A different run in this buffer: remount.
      (kill-buffer buf)
      (setq buf (gascity-view-get-buffer-create gascity-run-buffer-name))
      (gascity-run--mount buf run convoy rig)))
    (pop-to-buffer buf)))

(provide 'gascity-run)
;;; gascity-run.el ends here