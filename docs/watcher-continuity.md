# Pi watcher continuity

Plain Pi's `.pi/extensions/fm-primary-pi-watch.ts` owns watcher continuity.
The first required cycle is armed with `fm_watch_arm_pi`.
After an actionable notification, the extension automatically replaces the consumed cycle, while a missing, failed, or unhealthy cycle requires the same tool's repair action.
No ordinary completion or empty notification manually re-arms it.

The durable queue remains authoritative until generation-bound acknowledgement.
The extension's ownership record and a fresh beacon may prove the bounded handoff between watcher generations, but an unhealthy held singleton remains a failure.
Away mode transfers supervision to its daemon and prevents a competing Pi cycle.

## Per-actor acknowledgement

The main Pi session and Pi supervision branch claim eligible queue rows before presentation.
Each actor may present and acknowledge only rows carrying its own durable claim, so neither can consume the other's work.

`tests/fm-pi-watch-extension.test.sh`, `tests/fm-watch-arm.test.sh`, and `tests/fm-guard-stale-banner.test.sh` cover deterministic behavior.
`FM_PI_PRIMARY_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` refreshes real Pi evidence recorded in [`verification/supervision.md`](verification/supervision.md).
