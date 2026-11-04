;;; gascity-status.el --- status/session joins shared by the dashboard views -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The joins the rig dashboard (and the cockpit's agent actions) use to
;; turn flat `gc' payloads into typed objects:
;;
;; - `gc session list --json' rows join on the qualified agent name
;;   (`gascity-status--session-map-rows') so an agent row can find its
;;   session's worktree, tmux name and last activity.
;; - `gascity-status--agent' bridges a raw `gc status' / `gc rig status'
;;   agent entry to the typed action object (`gascity-agent'), carrying
;;   the session data and the tmux socket the agent keys attach through.
;;
;; The former agent-tree toolkit (city -> rig -> pool -> agent grouping
;; and its vnodes) was retired with the Agents tree (ga-2mmet); only the
;; joins still consumed by the rig dashboard remain here.

;;; Code:

(require 'seq)
(require 'gascity-domain)             ; typed session/agent objects

;;; Data shaping (pure)

(defun gascity-status--session-map (sessions)
  "Return a hash table mapping a session's qualified agent name to its object.
SESSIONS is the vector (or list) from `gc session list'; each row is decoded
into a `gascity-session' and keyed on its qualified name
\(`gascity-session-qualified-name', which prefers `agent_name' — always the
qualified name — over the volatile `name').  The qualified name is the
reliable join key against a status agent's `qualified_name'.

Thin wrapper over `gascity-status--session-map-rows': callers that already
hold the decoded `gascity-session' rows use that directly."
  (gascity-status--session-map-rows
   (gascity-domain-decode-list 'gascity-session sessions)))

(defun gascity-status--session-map-rows (session-rows)
  "Return the join map for already-decoded SESSION-ROWS.
Same map `gascity-status--session-map' builds, but over the typed
`gascity-session' list a caller decoded once (no double decode, no plist
detour)."
  (let ((map (make-hash-table :test 'equal)))
    (seq-do (lambda (s)
              (let ((key (gascity-session-qualified-name s)))
                (when key (puthash key s map))))
            session-rows)
    map))

(defun gascity-status--agent (agent rig-name session-map socket)
  "Build the action `gascity-agent' for AGENT under RIG-NAME.
AGENT is a raw `gc status' agent entry; this bridges it to the typed action
object, enriching it with the worktree and tmux name from the matching
`gascity-session' in SESSION-MAP (keyed on the agent's qualified name) and
recording the tmux SOCKET for attach."
  (let* ((qname (alist-get 'qualified_name agent))
         (session (and qname (gethash qname session-map))))
    (make-instance 'gascity-agent
                   :name qname
                   :rig rig-name
                   :work-dir (and session (gascity-session-work-dir session))
                   :session-name (and session (gascity-session-session-name session))
                   :socket socket
                   :running (and (alist-get 'running agent) t))))

(provide 'gascity-status)
;;; gascity-status.el ends here
