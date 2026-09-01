# Pi persistent-directory guard

`bin/fm-cd-command-policy.mjs` owns persistent top-level directory-change classification.
`bin/fm-cd-pretool-check.sh --command <exact-command>` is the plain Pi transport used by the tracked Pi extension.
Exit 0 allows the command.
Exit 2 with a stderr reason blocks it.
Subshell-local directory changes remain allowed while persistent changes that would move Firstmate outside its operating copy are denied.

`tests/fm-cd-pretool-check.test.sh` exercises the public executable interface.
Run `FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` for real Pi integration coverage.
