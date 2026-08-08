# Pi watcher-arm command guard

Pi's primary extension calls `bin/fm-arm-pretool-check.sh --command <command>` before shell commands that could create unsafe watcher lifecycle shapes.
The checker rejects shell backgrounding, truncating pipelines, bundled watcher operations, and broad watcher kills.
It accepts the narrowly owned Pi extension path and ordinary non-watcher commands.

The checker is a pre-execution seatbelt only.
Pi's watcher extension still owns child creation, liveness confirmation, retry, and wake delivery.
Do not invoke `bin/fm-watch-arm.sh` through shell backgrounding or append it to another command.
Use `fm_watch_arm_pi` only for the first required cycle or after the extension reports a missing, failed, or unhealthy cycle.

`bin/fm-arm-command-policy.mjs` owns command parsing and policy codes.
See [supervision verification](verification/supervision.md) for executable evidence.
