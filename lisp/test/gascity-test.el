;;; gascity-test.el --- Tests for gascity P0 -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; This file is part of gascity.el.

;;; Commentary:

;; ERT tests for the P0 foundation.  The pure tests (JSON decoding,
;; command-line construction, subcommand derivation) run anywhere.  The
;; round-trip integration test needs a live `gc' and a city, and skips
;; itself otherwise.

;;; Code:

(require 'ert)
(require 'gascity)

;;; gascity-reader-parse-json

(ert-deftest gascity-test-parse-json-object ()
  "JSON objects decode to symbol-keyed alists."
  (let ((r (gascity-reader-parse-json "{\"a\":1,\"b\":\"x\"}")))
    (should (equal (alist-get 'a r) 1))
    (should (equal (alist-get 'b r) "x"))))

(ert-deftest gascity-test-parse-json-array-is-vector ()
  "JSON arrays decode to vectors."
  (should (equal (gascity-reader-parse-json "[1,2,3]") [1 2 3])))

(ert-deftest gascity-test-parse-json-booleans-and-null ()
  "Both false and null decode to nil; true decodes to t."
  (let ((r (gascity-reader-parse-json
            "{\"yes\":true,\"no\":false,\"nada\":null}")))
    (should (eq (cdr (assq 'yes r)) t))
    (should (assq 'no r))                ; key present ...
    (should (null (cdr (assq 'no r))))   ; ... value nil
    (should (assq 'nada r))
    (should (null (cdr (assq 'nada r))))))

(ert-deftest gascity-test-parse-json-invalid-signals ()
  "Malformed JSON signals `gascity-json-parse-error'."
  (should-error (gascity-reader-parse-json "{not json")
                :type 'gascity-json-parse-error))

;;; gascity-command-line / subcommand

(ert-deftest gascity-test-status-command-line ()
  "Status defaults to JSON output."
  (should (equal (gascity-command-line (gascity-command-status))
                 '("gc" "status" "--json"))))

(ert-deftest gascity-test-status-command-line-no-json ()
  "Disabling :json drops the flag."
  (should (equal (gascity-command-line (gascity-command-status :json nil))
                 '("gc" "status"))))

(ert-deftest gascity-test-status-command-line-verbose ()
  "The verbose global flag is emitted when set."
  (should (member "--verbose"
                  (gascity-command-line (gascity-command-status :verbose t)))))

(ert-deftest gascity-test-subcommand-derivation ()
  "The subcommand is derived from the class name."
  (should (equal (gascity-command-subcommand (gascity-command-status))
                 "status")))

(ert-deftest gascity-test-executable-honoured ()
  "`gascity-executable' leads the command line."
  (let ((gascity-executable "/usr/local/bin/gc"))
    (should (equal (car (gascity-command-line (gascity-command-status)))
                   "/usr/local/bin/gc"))))

;;; Round-trip integration (acceptance) — needs a live gc + city

(ert-deftest gascity-test-status-round-trip ()
  "`(gascity-command-status!)' round-trips `gc status --json' to an alist."
  (skip-unless (executable-find gascity-executable))
  (let ((result (condition-case nil
                    (gascity-command-status!)
                  (gascity-error 'unavailable))))
    (when (eq result 'unavailable)
      (ert-skip "gc status did not succeed in this environment"))
    (should (consp result))
    (should (assq 'ok result))))

(provide 'gascity-test)
;;; gascity-test.el ends here
