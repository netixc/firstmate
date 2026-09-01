# Pi watcher-arm pre-tool protection

`bin/fm-arm-command-policy.mjs` owns command classification.
`bin/fm-arm-pretool-check.sh --command <exact-command>` is the plain Pi transport used by `.pi/extensions/fm-primary-turnend-guard.ts`.
Exit 0 allows a call.
Exit 2 with a stderr reason makes the Pi extension return `{block: true}`.
Malformed input or an unavailable optional classifier steps aside without executing submitted text.

The protected behavior forbids shell-backgrounded, piped, bundled, or broad-kill watcher commands while permitting the owned Pi watcher tool and documented standalone recovery.
`tests/fm-arm-pretool-check.test.sh` exercises the executable interface.
Run `FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` for real Pi integration coverage.
