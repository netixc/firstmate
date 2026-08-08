# Pi watcher continuity

Pi's `fm-primary-pi-watch.ts` extension owns one watcher child for the active session generation.
It starts that child through `bin/fm-watch-arm.sh`, validates its readiness, observes its close, and restores a successor before delivering an actionable wake.
A replacement Pi session gets a new generation, while a terminal Pi exit stops the active generation.
Stale callbacks cannot rearm a replaced or stopped session.

## Arm-layer cycle contract

`bin/fm-watch-arm.sh` records an identity-bound watcher cycle and reports either an actionable reason or an explicit failure.
The extension retries bounded restoration failures with exponential delay.
Firstmate calls `fm_watch_arm_pi` only for the first required cycle or after a notification says the cycle is missing, failed, or unhealthy.
No shell `&`, direct child management, or alternative primary waiting shape is supported.

The turn-end guard checks the same liveness predicate after settled Pi runs.
See [supervision verification](verification/supervision.md) for executable and live evidence.
