;;; gascity-pb-test.el --- Tests for the beads.el groundwork adoption -*- lexical-binding: t; -*-

;;; Commentary:

;; dashboard-v3 phase PB: gascity's use of the shared beads.el pieces
;; (remote exec layer, store scoping).  Pure tests; the gc and bd
;; boundaries are stubbed.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gascity)

(ert-deftest gascity-test-pb-ssh-pipe-argv-resolves-gc ()
  "The pipe argv resolves gc on the host and splices the PATH fragment."
  (cl-letf (((symbol-function 'beads-remote-find-executable)
             (lambda (name &optional _dir)
               (concat "/home/u/.guix-home/profile/bin/" name)))
            ((symbol-function 'beads-remote-path-assignment)
             (lambda (&optional _dir) "PATH=/home/u/.guix-home/profile/bin:$PATH")))
    (should (equal (gascity-remote-ssh-pipe-argv
                    "/ssh:u@h:/home/u/city/" '("gc" "events" "--follow"))
                   '("ssh" "-T" "-o" "BatchMode=yes"
                     "-o" "ServerAliveInterval=15"
                     "-o" "ServerAliveCountMax=3"
                     "-l" "u" "h" "--"
                     "PATH=/home/u/.guix-home/profile/bin:$PATH exec /home/u/.guix-home/profile/bin/gc events --follow")))))

(ert-deftest gascity-test-pb-remote-cache-is-shared ()
  "gascity's cache is beads.el's, so clearing either clears both."
  (should (eq gascity-remote--executable-cache beads-remote--cache))
  (puthash '("/ssh:h:" . "gc") "/bin/gc" beads-remote--cache)
  (gascity-remote-forget-executables)
  (should-not (gethash '("/ssh:h:" . "gc") beads-remote--cache)))

(provide 'gascity-pb-test)
;;; gascity-pb-test.el ends here
