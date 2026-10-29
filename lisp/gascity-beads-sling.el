;;; gascity-beads-sling.el --- Gas City registration on beads.el sling seams -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; Gas City's downstream registration on beads.el's public sling seams
;; (plans/beads-sling-integration/implementation-plan.md, workstream B).
;; The dependency stays one-way: gascity.el requires beads.el; beads.el
;; never requires gascity.el.
;;
;; This module consumes exactly six beads.el seams:
;;
;; - `beads-sling-target-functions'   contributes the cached Gas City
;;                                    agent targets to the Who picker;
;; - `beads-sling-backend-register'   registers the `gc' backend that
;;                                    runs `gc sling' for those targets;
;; - `beads-sling-validators'         contributes advisory, cached-data
;;                                    pre-launch warnings;
;; - `beads-menu-providers'           appends the `[City]' group to
;;                                    beads.el's dispatch menu;
;; - `beads-action-providers'         appends Gas City actions to the
;;                                    bead list/detail action bars;
;; - `beads-after-action-functions'   refreshes Gas City's store after a
;;                                    beads mutation.
;;
;; The module renders no bead UI and owns no bead store: beads.el remains
;; the bead porcelain and gascity.el remains a function of `gc --json'
;; output.  Loading it only registers the contributions above; there is
;; no `gc' spawn, synchronous read, file walk or timer at load time.
;;
;; Cold start: a fresh Emacs can resolve a local city from the machine
;; registry (`~/.gc/cities.toml') and each city's `.gc/site.toml' rig
;; paths, without a Gas City view or a `gc' spawn.  Opening the beads
;; sling menu warms the city's `gc agent list' in the background, so the
;; Who picker gains the gc targets once that read lands.  An
;; unregistered or remote directory still needs `gascity-context-city' or
;; a Gas City view; the backend resolves the city for the launch itself.

;;; Code:

(require 'beads-actions)
(require 'beads-menu)
(require 'beads-sling)
(require 'beads-formula)
(require 'gascity-action)
(require 'gascity-formula)
(require 'gascity-store)
(require 'gascity-context)
(require 'gascity-agents)
(require 'gascity-rig)
(require 'gascity-dashboard)

(declare-function beads-sling-backend-register "beads-sling"
                  (backend))
(declare-function beads-sling--launch-prompt "beads-sling" (context))
(declare-function gascity-agents "gascity-agents" ())
(declare-function gascity-dashboard "gascity-dashboard" ())
(declare-function gascity-rig-dashboard "gascity-rig" (rig-name))
(declare-function gascity-rig-dashboard-at-point "gascity-rig" ())
(declare-function gascity-rig-path "gascity-domain" (rig))
(declare-function gascity-rig-prefix "gascity-domain" (rig))
(declare-function gascity-remote-canonical-dir "gascity-remote" (dir))
(declare-function gascity-remote-localize-path "gascity-remote"
                  (path &optional dir))
(declare-function gascity-sling--roster "gascity-action" (&optional city))
(declare-function gascity-context-city-root-cached "gascity-context"
                  (&optional dir))
(declare-function gascity-context--known-city-roots "gascity-context" ())
(declare-function gascity-context-scope-key "gascity-context"
                  (&optional dir))
(declare-function gascity-rigs-cached "gascity-context" (&optional dir))
(declare-function gascity-rig-hq "gascity-domain" (rig))
(declare-function gascity-formula--nonblank "gascity-formula" (value))
(declare-function gascity-sling--cross-store-p "gascity-formula"
                  (work scope rigs))
(declare-function gascity-sling--cross-store-warning "gascity-formula"
                  (work scope rigs))
(declare-function gascity-sling--v2-trap-p "gascity-formula"
                  (recipe scope))
(declare-function gascity-sling--v2-trap-warning "gascity-formula"
                  (&optional rig))
(declare-function gascity-sling--missing-target-p "gascity-formula"
                  (target))
(declare-function gascity-sling--missing-required-vars "gascity-formula"
                  (recipe values))
(declare-function gascity-sling--missing-vars-warning "gascity-formula"
                  (names))
(defvar gascity-sling--missing-target-warning)
(defvar gascity-context-city)
(defvar gascity-formula-recipe-cache)
(declare-function gascity-sling-dispatch "gascity-action" ())

;; `beads-menu' and `beads-actions' are required above, so their provider
;; hooks and action maps are defined before registration.  The two value-less
;; map declarations stay for the byte compiler's `boundp' guards; package-lint
;; ignores value-less defvars, while a foreign defvar with a value would be
;; reported as a package-prefix violation (ga-ble40).
(defvar beads-list-mode-map)
(defvar beads-show-mode-map)

(defvar gascity-beads-sling--registered nil
  "Non-nil once `gascity-beads-sling-register' has run.
The flag records that this module installed its contributions; the
registration function remains safe to call again, because every seam
replaces or dedupes by identity.")

;;; City resolution

;; The remembered city is declared in `gascity-context' (a bare defvar, for
;; its `gascity-context-clear-cache' reset); this module owns its value and
;; documentation.

(defvar gascity-beads-sling--city nil
  "The city directory the last successful sling dispatch resolved, or nil.
Module-scoped, process-local memory (plan §B2, Open Question 3).  The
resolver `gascity-beads-sling--city' consults it only after
`gascity-context-city' and the known-city-root match fail, and it never
justifies a file-system read or a `gc' spawn.  Reset by
`gascity-context-clear-cache'.")

(defun gascity-beads-sling--directory (dir)
  "Return DIR as an expanded, slash-terminated directory name, or nil.
A DIR that is not a non-empty string yields nil.  Pure: `expand-file-name'
dissects a TRAMP name without asking its host."
  (when (and (stringp dir) (not (string-empty-p dir)))
    (file-name-as-directory (expand-file-name dir))))

(defun gascity-beads-sling--below-p (root dir)
  "Non-nil when directory DIR is ROOT or below it.
The test is lexical: both names are expanded and slash-terminated, then
compared with `string-prefix-p'.  Never `file-in-directory-p' — it falls
back to a truename plus `file-exists-p' comparison, a TRAMP round trip on
the Who picker's render path (plan P10)."
  (let ((root (gascity-beads-sling--directory root))
        (dir (gascity-beads-sling--directory dir)))
    (and root dir (string-prefix-p root dir))))

(defun gascity-beads-sling--city-owns-p (root dir)
  "Non-nil when DIR belongs to the city at ROOT.
DIR belongs when it is inside ROOT itself — a city-store bead buffer's
`default-directory' is the city root — or inside one of ROOT's memoized
rigs.  gc reports rig paths host-local, so they are re-prefixed for DIR's
host first (`gascity-remote-localize-path', a pure string operation).
Reads `gascity-rigs-cached' only: a cold rig memo contributes nothing."
  (and (or (gascity-beads-sling--below-p root dir)
           (seq-some (lambda (rig)
                       (when-let* ((path (gascity-rig-path rig)))
                         (gascity-beads-sling--below-p
                          (gascity-remote-localize-path path dir) dir)))
                     (gascity-rigs-cached root)))
       root))

(defvar gascity-beads-sling--cities-file
  (expand-file-name "~/.gc/cities.toml")
  "Gas City's machine-wide city registry.
Local directory → city discovery reads this file and each city's
`.gc/site.toml` when no city is already known; it is a small local file,
never a `gc' spawn or a TRAMP walk.")

(defvar gascity-beads-sling--registry-cities 'unread
  "Cached `((NAME . PATH) ...)' from the city registry, or `unread'.
Set to nil to retry a missing registry; `gascity-beads-sling--reset-cache'
clears the cache after a city or rig is registered.")

(defvar gascity-beads-sling--site-rigs-cache (make-hash-table :test #'equal)
  "Cache CITY-ROOT → its `.gc/site.toml' rig paths, including nil answers.")

(defun gascity-beads-sling--reset-cache ()
  "Forget the city-registry and per-city rig caches."
  (setq gascity-beads-sling--registry-cities 'unread)
  (clrhash gascity-beads-sling--site-rigs-cache))

(defun gascity-beads-sling--toml-blocks (file header)
  "Return the raw text of each `[[HEADER]]' block in FILE, in order.
Only a local, readable FILE is read; a remote or missing file yields
nil.  The caller extracts the one or two keys it needs."
  (when (and (stringp file) (not (file-remote-p file)) (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((re (format "^\\[\\[%s\\]\\]" (regexp-quote header))) blocks)
        (while (re-search-forward re nil t)
          (let ((start (point))
                (end (save-excursion
                       (if (re-search-forward "^\\[\\[" nil t)
                           (match-beginning 0)
                         (point-max)))))
            (push (buffer-substring-no-properties start end) blocks)))
        (nreverse blocks)))))

(defun gascity-beads-sling--toml-value (block key)
  "Return KEY's quoted value in BLOCK, or nil."
  (when (and block
             (string-match (format "^[ \t]*%s[ \t]*=[ \t]*\"\\([^\"]*\\)\""
                                    (regexp-quote key))
                           block))
    (match-string 1 block)))

(defun gascity-beads-sling--registry-cities ()
  "Return the cached `((NAME . PATH) ...)' city registry."
  (when (eq gascity-beads-sling--registry-cities 'unread)
    (setq gascity-beads-sling--registry-cities
          (delq nil
                (mapcar (lambda (block)
                          (let ((path (gascity-beads-sling--toml-value block "path"))
                                (name (gascity-beads-sling--toml-value block "name")))
                            (when (and path name) (cons name path))))
                        (gascity-beads-sling--toml-blocks
                         gascity-beads-sling--cities-file "cities")))))
  gascity-beads-sling--registry-cities)

(defun gascity-beads-sling--site-rig-paths (city)
  "Return CITY's registered rig paths from its `.gc/site.toml'.
Cached per city, including an empty answer; nil for a remote or
unreadable city."
  (let ((cached (gethash city gascity-beads-sling--site-rigs-cache 'missing)))
    (if (not (eq cached 'missing))
        cached
      (let ((paths
             (delq nil
                   (mapcar (lambda (block)
                             (gascity-beads-sling--toml-value block "path"))
                           (gascity-beads-sling--toml-blocks
                            (expand-file-name ".gc/site.toml" city) "rig")))))
        (puthash city paths gascity-beads-sling--site-rigs-cache)
        paths))))

(defun gascity-beads-sling--registry-city (dir)
  "Return the registered local city that owns DIR, or nil.
Reads the machine registry and each candidate city's `.gc/site.toml'.
DIR is owned when it is inside the city root or one of that city's
registered rig repositories.  Never used for a remote DIR and never
spawns `gc'."
  (when (and (stringp dir) (not (file-remote-p dir)))
    (seq-some
     (lambda (city)
       (let ((root (cdr city)))
         (when (and (stringp root) (not (file-remote-p root)))
           (when (or (gascity-beads-sling--below-p root dir)
                     (seq-some (lambda (path)
                                 (gascity-beads-sling--below-p path dir))
                               (gascity-beads-sling--site-rig-paths root)))
             root))))
     (gascity-beads-sling--registry-cities))))

(defun gascity-beads-sling--city (&optional dir)
  "Return the Gas City directory governing DIR, cache-only, or nil.
DIR defaults to `default-directory' and is expanded once, so a TRAMP name
stays a TRAMP name.  Resolution order, first hit wins:

1. `gascity-context-city', the user's override;
2. a root of `gascity-context-known-city-roots' that governs DIR — DIR is
   inside that city's tree or inside one of its memoized rigs;
3. a city registered in `~/.gc/cities.toml' whose root or `.gc/site.toml'
   rig contains DIR (local directories only);
4. `gascity-beads-sling--city', the city the last dispatch resolved.

A bead buffer's `default-directory' is its rig repository, outside the
city tree (plan F4), so step 2 is what makes the Who picker work from a
bead view; step 3 keeps it working once this session has dispatched.

Cache-only after the first call: no directory walk, no
`file-exists-p'/`file-truename' and no `gc' spawn.  The local registry
fallback reads the small `~/.gc/cities.toml' and `.gc/site.toml' files
once and caches them.  The answer is canonicalized like the store's
entry keys and ends in a slash.  Never walks DIR's parent chain."
  (let* ((dir (gascity-beads-sling--directory (or dir default-directory)))
         (known (gascity-context-known-city-roots)))
    (when-let* ((city (or (gascity-beads-sling--directory gascity-context-city)
                          (seq-some (lambda (root)
                                      (gascity-beads-sling--city-owns-p
                                       root dir))
                                    known)
                          (gascity-beads-sling--directory
                           (gascity-beads-sling--registry-city dir))
                          (gascity-beads-sling--directory
                           gascity-beads-sling--city))))
      (gascity-context-remember-city-root city)
      (gascity-remote-canonical-dir city))))

(defun gascity-beads-sling-targets ()
  "Return the city's qualified Gas City sling targets from cached data.
One `beads-sling-target' per configured agent of the cached
\(\"agent\" \"list\") payload (`gascity-sling--roster'), so the Who
picker offers exactly the names `gc sling' accepts: `rig/agent' for a
rig-scoped agent, the bare name for a city-scoped one.

The `beads-sling-target-functions' contract takes no arguments and must
never block, so this answers from the store's last good payload and the
city `gascity-beads-sling--city' resolves from memory.  A cold store or
an unresolved city returns nil in the same call, leaving beads.el's
local targets as the only Who choices.  Never spawns `gc', never reads
the work bead, and contributes no `default_sling_target' row (plan F3)."
  (when-let* ((city (gascity-beads-sling--city)))
    (mapcar (lambda (agent)
              (let ((name (plist-get agent :name))
                    (rig (plist-get agent :rig)))
                (beads-sling-target
                 :name name
                 :kind 'agent
                 :scope rig
                 :backend "gc"
                 :description name
                 :metadata (list :rig rig
                                 :city city
                                 :qualified-name name
                                 :source 'roster))))
            (gascity-sling--roster city))))

(defun gascity-beads-sling--warm (dir)
  "Start background reads of the city roster and rigs for DIR.
Called when the beads sling menu opens, so the Who picker has the gc
roster by the time the user reaches the T stage.  Never blocks: the
store answers from its last good payload and fills in when the read
completes."
  (when-let* ((city (gascity-beads-sling--city dir)))
    (gascity-store-fetch '("agent" "list") #'ignore #'ignore :dir city)
    (gascity-store-fetch '("rig" "list") #'ignore #'ignore :dir city)
    city))

(defun gascity-beads-sling--warm-at-point (&rest _)
  "Warm the sling stores for the current buffer's directory."
  (ignore-errors (gascity-beads-sling--warm default-directory)))

(defun gascity-beads-sling--validate-target-scope (target)
  "Return TARGET's scope: its slash prefix, or \"city\" for a bare name.
TARGET is the resolved target name from the launch context.  The
scope string is what the §5a trap and §5b cross-store validators
take, so a rig-qualified `rig/agent' classifies as its rig and a
bare city agent as \"city\".  A blank target classifies as nil."
  (when (gascity-formula--nonblank target)
    (if-let* ((slash (string-search "/" target)))
        (substring target 0 slash)
      "city")))

(defun gascity-beads-sling--validate-city (&optional dir)
  "Return a known city root for DIR (default `default-directory').
Cache-only: it consults `gascity-context-city-root-cached' and then
the known city roots crossed with the rig memo, matching a rig path
lexically against DIR's host-local name.  It never walks the file
system, never spawns `gc' and never reads the store; an unknown city
answers nil."
  (or (gascity-context-city-root-cached dir)
      (let* ((dir (file-name-as-directory
                   (expand-file-name (or dir default-directory))))
             (local (file-local-name dir)))
        (seq-find
         (lambda (root)
           (seq-some
            (lambda (rig)
              (let ((path (gascity-rig-path rig)))
                (and (stringp path)
                     (not (string-empty-p path))
                     (string-prefix-p
                      (file-name-as-directory
                       (file-local-name (expand-file-name path)))
                      local))))
            (gascity-rigs-cached root)))
         (gascity-context--known-city-roots)))))

(defun gascity-beads-sling--validate-recipe (city formula)
  "Return the warm `gascity-formula' recipe for CITY and FORMULA, or nil.
`gascity-formula-recipe-cache' is keyed
\((SCOPE-KEY . FORMULA) . RECIPE): the lookup is scope-keyed, never
by name alone (P8).  A cold recipe answers nil without a read."
  (when (and city formula)
    (cdr (assoc (cons (gascity-context-scope-key city) formula)
                gascity-formula-recipe-cache))))

(defun gascity-beads-sling--validate-rig (rigs)
  "Return the first rig-scoped rig in RIGS, or nil.
The bl-bdj warning's suggestion names a rig the city actually has;
an all-city memo answers nil and the wording stays generic."
  (seq-find (lambda (rig) (not (gascity-rig-hq rig))) rigs))

(defun gascity-beads-sling-validate (context)
  "Return advisory warnings for sling CONTEXT, or nil.
Part of `beads-sling-validators': warnings never refuse a dispatch,
because `gc' remains the authority.  Every input is cached data; an
input that is not available yields no warning.  The checks are the
§5a city-scoped/pool v2 trap, the §5b cross-store route, the §5c
missing target (every shape, formula included) and the §5c missing
required vars.  Multiple warnings are joined into one string with
\"; \", because `beads-sling-validate' maps one value per hook
function."
  (let* ((work (plist-get context :work))
         (formula (plist-get context :formula))
         (target (plist-get context :target))
         (target-scope (gascity-beads-sling--validate-target-scope target))
         (city (gascity-beads-sling--validate-city))
         (rigs (and city (gascity-rigs-cached city)))
         (recipe (gascity-beads-sling--validate-recipe city formula))
         (warnings
          (delq nil
                (list
                 (when (and rigs
                            (gascity-sling--cross-store-p
                             work target-scope rigs))
                   (gascity-sling--cross-store-warning
                    work target-scope rigs))
                 (when (gascity-sling--v2-trap-p recipe target-scope)
                   (gascity-sling--v2-trap-warning
                    (gascity-beads-sling--validate-rig rigs)))
                 (when (gascity-sling--missing-target-p target)
                   gascity-sling--missing-target-warning)
                 (gascity-sling--missing-vars-warning
                  (gascity-sling--missing-required-vars
                   (plist-get context :recipe)
                   (plist-get context :values)))))))
    (and warnings (mapconcat #'identity warnings "; "))))

(defun gascity-beads-sling--menu-group ()
  "Return the `[City]' group for beads.el's dispatch menu.
Pure: beads.el calls providers on every menu render, so building the
group must not read the store, spawn `gc' or depend on the current
buffer.  The group is a one-element list because
`beads-menu-provider-groups' appends provider lists."
  (list ["City"
         ("E" "Cockpit" gascity-dashboard)
         ("J" "Rig dashboard" gascity-rig-dashboard-at-point)
         ("K" "Rig dashboard…" gascity-rig-dashboard)
         ("A" "Agents" gascity-agents)
         ("Q" "Sling (gascity menu)" gascity-sling-dispatch)]))

(defun gascity-beads-sling-actions (context)
  "Return Gas City actions to append for beads CONTEXT.
CONTEXT is `:list' or `:show'.  The contributions are additive conses
of the form (KEY . COMMAND); nil elsewhere.  `V' opens the city
cockpit and never shadows a beads.el key (notably not its `S')."
  (pcase context
    ((or :list :show) '(("V" . gascity-dashboard)))
    (_ nil)))

(defun gascity-beads-sling--bind-actions ()
  "Bind the advertised `V' cockpit action in beads.el's bead maps.
`beads-action-providers' only advertises provider keys; beads.el
prints them in the action bar but binds none of them, so the advertised
`V' would otherwise say undefined.  `V' is free in both maps, so the
binding is additive and shadows nothing (in particular not `S', `RET'
or `TAB')."
  (when (boundp 'beads-show-mode-map)
    (define-key beads-show-mode-map (kbd "V") #'gascity-dashboard))
  (when (boundp 'beads-list-mode-map)
    (define-key beads-list-mode-map (kbd "V") #'gascity-dashboard)))

;;; Post-mutation refresh (plan §B5b, REQ-008)

(defconst gascity-beads-sling--city-refresh-kinds
  '(status run session convoy agent)
  "Store kinds a beads mutation re-reads under the city root.
The city's aggregate payloads embed bead data, so a mutation anywhere
changes them; `gascity-beads-sling--rig-refresh-kinds' covers the reads
that run inside the owning rig instead.")

(defconst gascity-beads-sling--rig-refresh-kinds '(bd)
  "Store kind a beads mutation re-reads under each affected rig root.
The store kind is the argv's first token, so bead reads are `bd' -- never
`bead', which no route and no read produces.")

(defun gascity-beads-sling--city-governs-p (root dir)
  "Non-nil when DIR belongs to the city rooted at ROOT.
DIR belongs when it is ROOT or below it, or below one of ROOT's memoized
rigs: the bead delegation contract pins a mutating buffer to its rig
repository, which lives outside the city tree.  `gascity-rigs-cached' is
the only rig source, so a cold memo contributes nothing.  Pure: gc
reports rig paths host-local, and `gascity-remote-localize-path' only
re-prefixes by string, without a TRAMP round trip."
  (and root
       (or (gascity-beads-sling--below-p root dir)
           (seq-some (lambda (rig)
                       (when-let* ((path (ignore-errors
                                          (gascity-rig-path rig))))
                         (gascity-beads-sling--below-p
                          (gascity-remote-localize-path path dir) dir)))
                     (gascity-rigs-cached root)))))

(defun gascity-beads-sling--after-action-city-root (&optional dir)
  "Return the city store root a beads mutation in DIR must refresh, or nil.
Cache-only, in the order the source anchor names: the city the last sling
lookup or dispatch resolved (`gascity-beads-sling--city') when it governs
DIR, then a root of `gascity-context-known-city-roots' that governs DIR
through its tree or one of its memoized rigs.  A remembered city that
does not govern DIR is skipped, so a mutation in another city's rig never
refreshes the wrong store.  Never walks the file system, never probes
with `file-exists-p' and never spawns `gc': an unresolved root answers
nil and the hook contributes nothing rather than invalidating broadly."
  (let ((dir (gascity-beads-sling--directory (or dir default-directory)))
        (remembered (gascity-beads-sling--directory
                     gascity-beads-sling--city)))
    (when dir
      (or (when (gascity-beads-sling--city-governs-p remembered dir)
            remembered)
          (seq-find (lambda (root)
                      (gascity-beads-sling--city-governs-p root dir))
                    (gascity-context-known-city-roots))))))

(defun gascity-beads-sling--issue-prefix (issue)
  "Return the bead-store prefix of ISSUE, or nil.
A beads id is `PREFIX-IDENTITY' and the prefix is the value of a rig's
`prefix' slot (`ga', `ec'), without the hyphen.  An id with no hyphen
contributes nil."
  (when (and (stringp issue)
             (string-match "\\`\\([^-]+\\)-" issue))
    (match-string 1 issue)))

(defun gascity-beads-sling--after-action-rig-roots (issues city)
  "Return the distinct rig repo roots owning ISSUES in CITY.
Each id's prefix is matched against CITY's memoized rig prefixes and the
rig's repository path becomes the store root, because beads reads run in
the rig, not in the city (DESIGN.md §4.3).  Cache-only: the rig list
comes from `gascity-rigs-cached', so a cold memo or an unknown prefix
contributes nothing.  Paths are re-prefixed for the city's host and
repeated rigs collapse to one root."
  (when city
    (let ((rigs (gascity-rigs-cached city))
          (roots nil))
      (dolist (issue issues)
        (when-let* ((prefix (gascity-beads-sling--issue-prefix issue))
                    (rig (seq-find
                          (lambda (rig)
                            (equal prefix (ignore-errors
                                            (gascity-rig-prefix rig))))
                          rigs))
                    (path (ignore-errors (gascity-rig-path rig)))
                    (root (gascity-beads-sling--directory
                           (gascity-remote-localize-path path city))))
          (push root roots)))
      (delete-dups (nreverse roots)))))

(defun gascity-beads-sling--after-action (action issues)
  "Invalidate the cached `gc' views a successful beads mutation changed.
ACTION is the mutation symbol beads.el ran and ISSUES the affected bead
ids.  The hook runs only after a successful mutation, so every delivered
action invalidates: there is no allow-list, and a guard -- if one is ever
wanted -- must key on the emitted symbol, never on an aspirational list.

Two store roots are refreshed, because rigs live outside the city tree
and one root cannot cover both:

- the city root (`gascity-beads-sling--after-action-city-root') re-reads
  `gascity-beads-sling--city-refresh-kinds';
- each affected issue's rig repository
  (`gascity-beads-sling--after-action-rig-roots') re-reads
  `gascity-beads-sling--rig-refresh-kinds'.

Both roots resolve cache-only; an unresolved root contributes nothing
rather than a broad invalidation, and an empty ISSUES list does nothing
at all, not even a city lookup.  The store joins a read already in
flight and re-reads an entry at most once, so repeated ids collapse
there.  The hook never calls a beads function, never mutates beads and
runs no timer, so it cannot loop."
  (ignore action)
  (when issues
    (let ((city (gascity-beads-sling--after-action-city-root)))
      (when city
        (gascity-store-invalidate
         :dir city
         :kind gascity-beads-sling--city-refresh-kinds
         :refetch t))
      (dolist (root (gascity-beads-sling--after-action-rig-roots issues city))
        (gascity-store-invalidate
         :dir root
         :kind gascity-beads-sling--rig-refresh-kinds
         :refetch t)))))

;;; Backend dispatch and argv (plan §B3a, REQ-003/REQ-004/REQ-007)

(declare-function beads-formula-validate-vars "beads-formula"
                  (formula vars))
(declare-function beads-sling-shape "beads-sling" (work formula))
(declare-function gascity-command-act-async "gascity-action"
                  (command &rest args))
(declare-function gascity-store-invalidate "gascity-store"
                  (&rest args))

(defconst gascity-beads-sling--invalidate-kinds
  '(agent run session convoy status)
  "The store kinds one completed sling in a city changes, in order.
Each kind stands for the store key the launch writes: `agent' for
`(\"agent\" \"list\")', `run' for `(\"run\" \"list\")', `session' for
`(\"session\" \"list\")', `convoy' for `(\"convoy\" \"list\")' and `status'
for `(\"status\")'.")

(defun gascity-beads-sling--invalidate (dir)
  "Invalidate the cached `gc' views a sling in DIR changes.
Exactly one `gascity-store-invalidate' call per store kind, with
`:refetch t', so each entry is re-read at most once per dispatch.  The
inherited sling route is switched off at the launch (`:invalidate nil'),
which would otherwise invalidate a different, narrower set and double
up.  Called once from the single success closure, never from a timer or
a render path.  A nil DIR invalidates nothing: the store treats a nil
`:dir' as a wildcard, which would touch every city's entries."
  (when dir
    (dolist (kind gascity-beads-sling--invalidate-kinds)
      (gascity-store-invalidate :dir dir :kind kind :refetch t))))

(defun gascity-beads-sling--blank-p (value)
  "Non-nil when VALUE is nil or a whitespace-only string."
  (or (null value)
      (and (stringp value) (string-empty-p (string-trim value)))))

(defun gascity-beads-sling--first-name (&rest names)
  "Return the first non-blank string among NAMES, or nil."
  (seq-find (lambda (name)
              (and (stringp name)
                   (not (gascity-beads-sling--blank-p name))))
            names))

(defun gascity-beads-sling--var-args (values)
  "Return VALUES as `--var' arguments, in order, skipping blanks.
VALUES is the context's `:values' — a (NAME . VALUE) alist.  Only a
non-blank value is emitted, formatted as \"name=value\" (plan §B3a
step 4); a value containing a comma is split by the shared list
formatter, a pre-existing limit of the beads command builder."
  (delq nil
        (mapcar (lambda (pair)
                  (let ((name (car pair))
                        (value (cdr pair)))
                    (unless (gascity-beads-sling--blank-p value)
                      (format "%s=%s" name value))))
                values)))

(defun gascity-beads-sling--command (shape target work formula values)
  "Build the `gascity-command-sling' for SHAPE on TARGET.
WORK is the work bead (or freeform text), FORMULA the formula name,
VALUES the raw (NAME . VALUE) alist.  The single argv builder (plan
§B3a step 6): every row carries a non-empty TARGET — `gc' refuses
`--formula' without an explicit target — and the formula shape puts
the formula name in the bead slot:

  plain    (\"sling\" TARGET WORK)
  on       (\"sling\" TARGET WORK \"--on\" FORMULA \"--var\" \"k=v\" …)
  formula  (\"sling\" TARGET FORMULA \"--formula\" \"--var\" \"k=v\" …)

Never the targetless (\"sling\" \"--formula\" …) shape.  This
builder never asks for JSON itself; `gascity-beads-sling--dispatch'
sets the command's `json' slot, which appends `--json' after the
positionals (the global options come before the subcommand flags) so
the success closure receives a parsed dispatch result (plan §B3)."
  (let ((vars (gascity-beads-sling--var-args values)))
    (pcase shape
      ('plain (gascity-command-sling :target target :arg work))
      ('on (gascity-command-sling :target target :arg work
                                  :on formula :var vars))
      ('formula (gascity-command-sling :target target :arg formula
                                       :formula t :var vars))
      (_ (user-error "No sling work or formula selected")))))

(defun gascity-beads-sling--prompt-lost-p (prompt context)
  "Return non-nil when PROMPT would carry something the launch lacks.
CONTEXT is the dispatch context plist.  beads.el generates a prompt for
a formula shape (`Run formula …' plus the variables) and for freeform
work (the work text); the gc backend
already passes both through `--on'/the formula/vars or the work argv, so
that prompt is redundant.  A prompt different from the generated one is
an extra instruction `gc sling' has no flag for; that one is worth a
message.  Never errors on a malformed context."
  (and (not (gascity-beads-sling--blank-p prompt))
       (not (equal (string-trim prompt)
                   (string-trim
                    (or (ignore-errors (beads-sling--launch-prompt context))
                        ""))))))

(defun gascity-beads-sling--dispatch (target bead prompt context)
  "Dispatch BEAD to TARGET through the `gc' backend.
TARGET is a `beads-sling-target' whose `backend' is \"gc\", BEAD the
work, PROMPT the freeform instruction and CONTEXT the
`beads-sling--scope-context' plist.  Everything is rebuilt from
CONTEXT — this never reads transient state (plan F1) — in the §B3a
order: work, shape, target, vars, prompt, command, then one
asynchronous launch.

WORK is `(or (plist-get context :work) BEAD)'; it is required for the
`plain' and `on' shapes and ignored by `formula', whose bead slot
carries the formula name.  SHAPE comes from the context's `:shape'
and only defensively falls back to `beads-sling-shape' — never to
gascity's formula cache or `gascity-formula--needs-convoy' (F5).

TARGET resolves in order: the dispatch argument's name (authoritative
— `beads-sling--launch' resolves the target but forwards the context
unchanged, P3), the context's `:target', then
`gascity-sling--derive-target' over the work, formula, resolved city,
cached roster and target memory.  A blank answer is a `user-error'
before any spawn, for every shape, because `gc' refuses `--formula'
without an explicit target (P1).

Vars are validated client-side before the launch when the context
carries a recipe: `beads-formula-validate-vars' is fail-fast and
signals `user-error' itself, so its return value is never tested —
plan P2.  A PROMPT is never refused and never put in argv: `gc sling'
has no prompt flag.  The prompt beads.el generates for a formula or for
freeform work is already carried by the formula/vars or the work argv,
so it is dropped silently.  Only a prompt that is not the one
`beads-sling--launch-prompt' would generate for this context — an extra
instruction that would otherwise be lost — is dropped with a message.

The launch is one `gascity-command-act-async' call on the resolved
city, started when the action begins — never blocking (D9): the command
asks for parsed JSON, the resolved target is recorded as the
`(city . formula)' launch memory, and the city is remembered for the
Who picker.  A formula shape (`on', `formula') hands its answer to
`gascity-sling--launch-handler' so the created workflow root is echoed
with the momentary `F' follow offer; a plain shape echoes the shared
success text for the sling and its target.  Either way the one success
closure then invalidates the launcher's cached views once per store
kind (`gascity-beads-sling--invalidate').  Failure keeps the inherited
first-stderr-line echo and city log, and invalidates nothing.  Returns
nil without blocking."
  (let* ((work (or (plist-get context :work) bead))
         (formula (plist-get context :formula))
         (values (plist-get context :values))
         (recipe (plist-get context :recipe))
         (shape (or (plist-get context :shape)
                    (beads-sling-shape work formula))))
    (cond
     ((and (memq shape '(plain on))
           (gascity-beads-sling--blank-p work))
      (user-error "No sling work selected"))
     ((and (memq shape '(on formula))
           (gascity-beads-sling--blank-p formula))
      (user-error "No sling formula selected"))
     ((not (memq shape '(plain on formula)))
      (user-error "No sling work or formula selected")))
    (let* ((city (gascity-beads-sling--city))
           (target-name
            (or (gascity-beads-sling--first-name
                 (and (beads-sling-target-p target) (oref target name))
                 (plist-get context :target))
                (gascity-beads-sling--first-name
                 (plist-get (gascity-sling--derive-target
                             (list :work work :formula formula :city city)
                             (gascity-sling--roster city)
                             gascity-sling--target-memory)
                            :target)))))
      (unless target-name
        (user-error "No sling target selected"))
      ;; Fail fast, client-side, before any process exists (P2).
      (when recipe
        (beads-formula-validate-vars recipe values))
      (when (gascity-beads-sling--prompt-lost-p prompt context)
        (message "gc sling has no prompt flag; dropping the extra instruction"))
      (let ((command (gascity-beads-sling--command
                      shape target-name work formula values)))
        ;; The launch handler reads parsed JSON from the answer.
        (oset command json t)
        ;; The launch itself is the (city . formula) memory's next
        ;; default, recorded when the action starts, exactly as the
        ;; gascity sling transient records it — and the city is
        ;; remembered so a cold Who picker can resolve it next time.
        (gascity-sling--remember-target city formula target-name)
        (setq gascity-beads-sling--city city)
        (gascity-command-act-async
         command
         :target target-name
         :dir city
         ;; One explicit invalidation per dispatch, in the single success
         ;; closure below: the built-in sling route would invalidate a
         ;; different, narrower set and double up.
         :invalidate nil
         :on-success
         (let ((handler (and (memq shape '(on formula))
                             (gascity-sling--launch-handler
                              command formula work))))
           (lambda (result)
             ;; A formula shape echoes the created workflow root with the
             ;; momentary `F' follow offer; a plain shape echoes the
             ;; shared success text for the sling and its target (a
             ;; non-nil `:on-success' replaces the inherited echo).
             (if handler
                 (funcall handler result)
               (message "%s" (gascity-action--success-text
                               command target-name result)))
             (gascity-beads-sling--invalidate city))))
        nil))))

(defun gascity-beads-sling-register ()
  "Register Gas City's contributions with beads.el's sling seams.
Idempotent: the backend is replaced by name, hook functions are added
once, and the menu provider is appended once.  Performs no `gc' read
or process spawn; only the registration data structures change."
  (beads-sling-backend-register
   (beads-sling-backend
    :name "gc"
    :dispatch #'gascity-beads-sling--dispatch
    :description "Gas City (gc sling)"))
  (add-hook 'beads-sling-target-functions #'gascity-beads-sling-targets)
  (add-hook 'beads-sling-validators #'gascity-beads-sling-validate)
  (add-to-list 'beads-menu-providers #'gascity-beads-sling--menu-group)
  (add-hook 'beads-action-providers #'gascity-beads-sling-actions)
  (gascity-beads-sling--bind-actions)
  (add-hook 'beads-after-action-functions #'gascity-beads-sling--after-action)
  (dolist (command '(beads-sling-for-issue beads-sling))
    (unless (advice-member-p #'gascity-beads-sling--warm-at-point command)
      (advice-add command :before #'gascity-beads-sling--warm-at-point)))
  (setq gascity-beads-sling--registered t))

(gascity-beads-sling-register)

(provide 'gascity-beads-sling)
;;; gascity-beads-sling.el ends here
