# Plain Pi turn-end guard

`.pi/extensions/fm-primary-turnend-guard.ts` is the only primary turn-end integration.
It listens for Pi's logical-run settlement and invokes `bin/fm-turnend-guard.sh` with Pi's event payload.
The script exits 0 when supervision is unnecessary or healthy and exits 2 with a concrete repair reason when the run would otherwise end blind.
The extension converts that refusal into one guarded Pi follow-up.

`.pi/extensions/fm-primary-pi-watch.ts` owns watcher continuity between actionable notifications.
Repair uses the `fm_watch_arm_pi` tool, never a shell-background substitute.
`docs/supervision-protocols/pi.md` owns the operator sequence.

`tests/fm-turnend-guard.test.sh`, `tests/fm-pi-watch-extension.test.sh`, and `tests/fm-pi-primary-types.test.sh` cover the executable and extension contracts.
`FM_PI_PRIMARY_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` refreshes real Pi evidence recorded in [`verification/supervision.md`](verification/supervision.md).
