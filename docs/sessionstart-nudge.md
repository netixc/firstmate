# Plain Pi session start

Pi's tracked project extensions are the only native startup and turn-end integration surface.
`bin/fm-session-start.sh` remains the one-shot startup owner and must run exactly once per session.
The primary Pi extension invokes the owned path and does not duplicate lock, bootstrap, queue, or network-stage mechanics.
A missing or unloaded extension is reported explicitly; restart plain `pi` with the tracked `-e` extension paths after verifying project trust.

`tests/fm-sessionstart-nudge.test.sh` and `tests/fm-session-start.test.sh` cover deterministic behavior.
`FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` is the real Pi integration guard.
Current plain Pi integration evidence is recorded in [`verification/supervision.md`](verification/supervision.md).
