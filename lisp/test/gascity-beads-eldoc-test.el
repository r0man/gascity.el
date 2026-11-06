;;; gascity-beads-eldoc-test.el --- Tests for the bead-id store map -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; The per-city prefix->store map (plan §A, §H item 1): one asynchronous
;; `gc rig list' fill per city, a pure prefix resolver, the D4/D5/D7 row
;; shapes, per-city isolation, and the no-synchronous-spawn invariant.
;; The gc boundary is stubbed with the shared store helpers; nothing talks
;; to a live city or a real remote host (the TRAMP "mock" method is a
;; local sh behind the full TRAMP machinery).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)
(require 'gascity-test-helpers)

;;; Fixtures

(defun gascity-beads-eldoc-test--fresh-state ()
  "Forget every map and city memo a previous test could have left."
  (clrhash gascity-beads-eldoc--maps)
  (clrhash gascity-context--root-cache)
  (clrhash gascity-context--rigs-cache))

(defun gascity-beads-eldoc-test--city ()
  "Create a temporary city root (a directory holding `city.toml').
Return its absolute name, with a trailing slash."
  (let ((dir (file-name-as-directory (make-temp-file "gascity-eldoc-city" t))))
    (write-region "" nil (expand-file-name "city.toml" dir))
    dir))

(defun gascity-beads-eldoc-test--payload (&rest rows)
  "Return a `gc rig list' payload whose `rigs' vector holds ROWS.
ROWS are alists in gc's JSON shape."
  `((rigs . ,(vconcat rows))))

(defun gascity-beads-eldoc-test--hq (city prefix)
  "Return an HQ rig row for CITY carrying PREFIX."
  `((name . "test-city") (path . ,city) (prefix . ,prefix) (hq . t)
    (beads . "initialized")))

(defun gascity-beads-eldoc-test--rig (name prefix path &optional beads)
  "Return a non-HQ rig row: NAME, PREFIX, PATH and optional BEADS status."
  `((name . ,name) (prefix . ,prefix) (path . ,path)
    (hq . nil) (beads . ,(or beads "initialized"))))

(defun gascity-beads-eldoc-test--settle (read &optional payload)
  "Fire the parked READ's callback with PAYLOAD."
  (funcall (nth 1 read) payload))

;;; City prefix

(ert-deftest gascity-test-beads-eldoc-map-city-prefix-local ()
  "The HQ row maps the city prefix to the city root store.
The fill is one `gc rig list' read; the map is cold until the payload
lands (REQ-003, REQ-005)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city))
        map)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (should-not (gascity-beads-eldoc-map city))
          (should (= (length reads) 1))
          (should (equal (car (car reads)) '("rig" "list")))
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city "tc")))
          (setq map (gascity-beads-eldoc-map city))
          (should map)
          (should (equal (gascity-beads-eldoc--map-prefixes map) '("tc")))
          (should (equal (gascity-beads-eldoc--store-for map "tc-ab12")
                         city))
          ;; An unknown prefix has no store; the id is not in the allowlist.
          (should-not (gascity-beads-eldoc--store-for map "zz-ab12"))
          (should-not (gascity-beads-eldoc--store-for map "noprefix"))
          (should-not (gascity-beads-eldoc--store-for nil "tc-ab12")))
      (delete-directory city t))))

(ert-deftest gascity-test-beads-eldoc-map-city-prefix-remote ()
  "For a remote city the map, its store and its fill's directory are remote.
The fill read runs with `:dir' = the city root, never the calling
buffer's directory, and entries are TRAMP-prefixed names (REQ-009)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((local (gascity-beads-eldoc-test--city))
        (rig-local (file-name-as-directory
                    (make-temp-file "gascity-eldoc-rig" t)))
        reads map)
    (unwind-protect
        (progn
          (gascity-test-ensure-mock-method)
          (let ((city (concat "/mock::" local)))
            (let ((gascity-store-synchronous-delivery t)
                  (tramp-verbose 0))
              (setf (gascity-store--host-primed
                     (gascity-store--host (file-remote-p city)))
                    t)
              (cl-letf (((symbol-function 'gascity-reader-read-async)
                         (lambda (args callback &optional _errback &rest _)
                           (push (list args callback default-directory) reads)
                           nil)))
                (should-not (gascity-beads-eldoc-map city))
                (should (= (length reads) 1))
                (should (equal (nth 2 (car reads))
                               (file-name-as-directory
                                (expand-file-name city))))
                (gascity-beads-eldoc-test--settle
                 (car reads)
                 (gascity-beads-eldoc-test--payload
                  (gascity-beads-eldoc-test--hq local "ec")
                  (gascity-beads-eldoc-test--rig "rig.el" "gr" rig-local)))
                (setq map (gascity-beads-eldoc-map city))
                (should map)
                (should (equal (gascity-beads-eldoc--map-prefixes map)
                               '("ec" "gr")))
                (should (equal (gascity-beads-eldoc--store-for map "ec-ab12")
                               (file-name-as-directory
                                (expand-file-name city))))
                (should (equal (gascity-beads-eldoc--store-for map "gr-ab12")
                               (file-name-as-directory
                                (expand-file-name
                                 (concat "/mock::" rig-local)))))))))
      (delete-directory local t)
      (delete-directory rig-local t))))

;;; Rig prefixes

(ert-deftest gascity-test-beads-eldoc-map-rig-prefixes-local ()
  "Every prefixed, initialized rig row maps its prefix to its repo path."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city))
        (rig-a (file-name-as-directory (make-temp-file "gascity-eldoc-a" t)))
        (rig-b (file-name-as-directory (make-temp-file "gascity-eldoc-b" t)))
        map)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (gascity-beads-eldoc-map city)
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city "tc")
            (gascity-beads-eldoc-test--rig "a.el" "aa" rig-a)
            (gascity-beads-eldoc-test--rig "b.el" "bb" rig-b)))
          (setq map (gascity-beads-eldoc-map city))
          (should (equal (gascity-beads-eldoc--map-prefixes map)
                         '("tc" "aa" "bb")))
          (should (equal (gascity-beads-eldoc--store-for map "aa-1") rig-a))
          (should (equal (gascity-beads-eldoc--store-for map "bb-1") rig-b)))
      (delete-directory city t)
      (delete-directory rig-a t)
      (delete-directory rig-b t))))

(ert-deftest gascity-test-beads-eldoc-map-rig-prefixes-remote ()
  "A remote city's rig rows localize once, at fill time."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((local (gascity-beads-eldoc-test--city))
        (rig-local (file-name-as-directory
                    (make-temp-file "gascity-eldoc-remote-rig" t)))
        reads map)
    (unwind-protect
        (progn
          (gascity-test-ensure-mock-method)
          (let ((city (concat "/mock::" local)))
            (let ((gascity-store-synchronous-delivery t)
                  (tramp-verbose 0))
              (setf (gascity-store--host-primed
                     (gascity-store--host (file-remote-p city)))
                    t)
              (gascity-test-with-store-stubs reads _actions
                (gascity-beads-eldoc-map city)
                (gascity-beads-eldoc-test--settle
                 (car reads)
                 (gascity-beads-eldoc-test--payload
                  (gascity-beads-eldoc-test--rig "rig.el" "gr" rig-local)))
                (setq map (gascity-beads-eldoc-map city))
                (should (equal (gascity-beads-eldoc--store-for map "gr-1")
                               (file-name-as-directory
                                (expand-file-name
                                 (concat "/mock::" rig-local)))))))))
      (delete-directory local t)
      (delete-directory rig-local t))))

;;; Cold start and fill dedup

(ert-deftest gascity-test-beads-eldoc-map-cold-starts-one-fill ()
  "A cold map answers nil and starts exactly one deduplicated fill.
The same map answers warm afterwards without another read (REQ-005,
REQ-006)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city)))
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (should-not (gascity-beads-eldoc-map city))
          (should-not (gascity-beads-eldoc-map city))
          (should-not (gascity-beads-eldoc-map city))
          (should (= (length reads) 1))
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city "tc")))
          ;; Warm: answers from the map, no new read.
          (should (gascity-beads-eldoc-map city))
          (should (= (length reads) 1)))
      (delete-directory city t))))

(ert-deftest gascity-test-beads-eldoc-map-outside-city-is-nil ()
  "Outside a city there is no scope and no fill (D8, REQ-007)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((plain (file-name-as-directory (make-temp-file "gascity-no-city" t))))
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (should-not (gascity-beads-eldoc-map plain))
          (should-not reads))
      (delete-directory plain t))))

;;; Per-city isolation

(ert-deftest gascity-test-beads-eldoc-map-is-per-city ()
  "Two warm cities never share a map, a store or an allowlist (REQ-007)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city-a (gascity-beads-eldoc-test--city))
        (city-b (gascity-beads-eldoc-test--city))
        map-a map-b)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (gascity-beads-eldoc-map city-a)
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city-a "ta")))
          (gascity-beads-eldoc-map city-b)
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city-b "tb")))
          (setq map-a (gascity-beads-eldoc-map city-a)
                map-b (gascity-beads-eldoc-map city-b))
          (should-not (eq map-a map-b))
          (should (equal (gascity-beads-eldoc--map-prefixes map-a)
                         '("ta")))
          (should (equal (gascity-beads-eldoc--map-prefixes map-b)
                         '("tb")))
          ;; A resolves only its own city; B's prefix and store are absent.
          (should (equal (gascity-beads-eldoc--store-for map-a "ta-1")
                         city-a))
          (should-not (gascity-beads-eldoc--store-for map-a "tb-1"))
          (should-not (gascity-beads-eldoc--store-for map-b "ta-1")))
      (delete-directory city-a t)
      (delete-directory city-b t))))

;;; Row shapes: D4, D5, D7

(ert-deftest gascity-test-beads-eldoc-map-duplicate-prefix-keeps-first ()
  "A duplicate prefix keeps the first (HQ) entry and logs one warning (D4)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city))
        (squatter (file-name-as-directory
                   (make-temp-file "gascity-eldoc-squatter" t)))
        logs map)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (cl-letf (((symbol-function 'gascity--log)
                     (lambda (level fmt &rest args)
                       (push (cons level (apply #'format fmt args)) logs))))
            (gascity-beads-eldoc-map city)
            (gascity-beads-eldoc-test--settle
             (car reads)
             (gascity-beads-eldoc-test--payload
              (gascity-beads-eldoc-test--hq city "tc")
              (gascity-beads-eldoc-test--rig "squatter.el" "tc" squatter)
              (gascity-beads-eldoc-test--rig "other.el" "tc" squatter)))
            (setq map (gascity-beads-eldoc-map city))
            (should (equal (gascity-beads-eldoc--map-prefixes map) '("tc")))
            (should (equal (gascity-beads-eldoc--store-for map "tc-1") city))
            (should (= (length logs) 1))
            (should (string-match-p "tc" (cdr (car logs))))))
      (delete-directory city t)
      (delete-directory squatter t))))

(ert-deftest gascity-test-beads-eldoc-map-skips-unusable-rows ()
  "Prefix-less and uninitialized rows contribute nothing (D5)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city))
        (rig (file-name-as-directory (make-temp-file "gascity-eldoc-ok" t)))
        (cold (file-name-as-directory (make-temp-file "gascity-eldoc-cold" t)))
        map)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (gascity-beads-eldoc-map city)
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city "tc")
            ;; No prefix at all: not a wildcard.
            `((name . "no-prefix.el") (path . ,rig) (hq . nil)
              (beads . "initialized"))
            ;; Initialized but no path.
            `((name . "no-path.el") (prefix . "np") (hq . nil)
              (beads . "initialized"))
            ;; A store that is not initialized.
            (gascity-beads-eldoc-test--rig "cold.el" "cc" cold
                                           "uninitialized")
            ;; The one usable rig.
            (gascity-beads-eldoc-test--rig "ok.el" "ok" rig)))
          (setq map (gascity-beads-eldoc-map city))
          (should (equal (gascity-beads-eldoc--map-prefixes map)
                         '("tc" "ok")))
          (should-not (gascity-beads-eldoc--store-for map "np-1"))
          (should-not (gascity-beads-eldoc--store-for map "cc-1"))
          (should (equal (gascity-beads-eldoc--store-for map "ok-1") rig)))
      (delete-directory city t)
      (delete-directory rig t)
      (delete-directory cold t))))

(ert-deftest gascity-test-beads-eldoc-map-without-hq-has-no-city-store ()
  "No HQ row means no invented city store: city ids are not detected (D7)."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city))
        (rig (file-name-as-directory (make-temp-file "gascity-eldoc-only" t)))
        map)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (gascity-beads-eldoc-map city)
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--rig "only.el" "on" rig)))
          (setq map (gascity-beads-eldoc-map city))
          (should (equal (gascity-beads-eldoc--map-prefixes map) '("on")))
          (should-not (gascity-beads-eldoc--store-for map "tc-1"))
          (should (equal (gascity-beads-eldoc--store-for map "on-1") rig)))
      (delete-directory city t)
      (delete-directory rig t))))

;;; Stale-while-revalidate

(ert-deftest gascity-test-beads-eldoc-map-stale-map-keeps-serving ()
  "A stale map keeps answering while one refill is in flight (REQ-007).
The refill lands the new rig set; a removed prefix disappears and a new
one resolves."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city))
        (old (file-name-as-directory (make-temp-file "gascity-eldoc-old" t)))
        (new (file-name-as-directory (make-temp-file "gascity-eldoc-new" t)))
        map)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (gascity-beads-eldoc-map city)
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city "tc")
            (gascity-beads-eldoc-test--rig "old.el" "ol" old)))
          (setq map (gascity-beads-eldoc-map city))
          (should (equal (gascity-beads-eldoc--store-for map "ol-1") old))
          ;; Age the map past its TTL and its store entry past its own:
          ;; the old snapshot keeps answering while the refill runs.
          (setf (gascity-beads-eldoc--map-fetched-at map)
                (- (float-time) (1+ gascity-beads-eldoc-map-ttl)))
          (gascity-store-invalidate :dir city :kind 'rig :refetch nil)
          (should (eq (gascity-beads-eldoc-map city) map))
          (should (equal (gascity-beads-eldoc--store-for map "ol-1") old))
          (should (= (length reads) 2))
          ;; A second stale call while the refill is in flight adds no read.
          (gascity-beads-eldoc-map city)
          (should (= (length reads) 2))
          (gascity-beads-eldoc-test--settle
           (car reads)
           (gascity-beads-eldoc-test--payload
            (gascity-beads-eldoc-test--hq city "tc")
            (gascity-beads-eldoc-test--rig "new.el" "nw" new)))
          (should (equal (gascity-beads-eldoc--store-for map "nw-1") new))
          (should-not (gascity-beads-eldoc--store-for map "ol-1"))
          (should (member "nw" (gascity-beads-eldoc--map-prefixes map)))
          (should-not (member "ol" (gascity-beads-eldoc--map-prefixes map))))
      (delete-directory city t)
      (delete-directory old t)
      (delete-directory new t))))

;;; No synchronous spawn

(ert-deftest gascity-test-beads-eldoc-no-synchronous-spawn ()
  "Fill, install-time map lookup and resolution never run gc or bd (REQ-012).
`gascity-reader-run' (the synchronous gc) and
`beads-command-execute' (the synchronous bd) are made to signal."
  (gascity-beads-eldoc-test--fresh-state)
  (let ((city (gascity-beads-eldoc-test--city))
        map)
    (unwind-protect
        (gascity-test-with-store-stubs reads _actions
          (cl-letf (((symbol-function 'gascity-reader-run)
                     (lambda (&rest _)
                       (error "Synchronous gc from the bead-id map")))
                    ((symbol-function 'beads-command-execute)
                     (lambda (&rest _)
                       (error "Synchronous bd from the bead-id map"))))
            (should-not (gascity-beads-eldoc-map city))
            (gascity-beads-eldoc-test--settle
             (car reads)
             (gascity-beads-eldoc-test--payload
              (gascity-beads-eldoc-test--hq city "tc")))
            (setq map (gascity-beads-eldoc-map city))
            (should (equal (gascity-beads-eldoc--store-for map "tc-1") city))))
      (delete-directory city t))))

(provide 'gascity-beads-eldoc-test)
;;; gascity-beads-eldoc-test.el ends here
