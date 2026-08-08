# Pi primary supervision protocol

Pi's tracked primary extensions own session-start delivery, turn-end protection, and watcher continuity.
When the first required supervision cycle is needed, call `fm_watch_arm_pi`.
Do not call it after ordinary work or ordinary notifications because the extension re-arms automatically.

On an actionable watcher notification, run `bin/fm-wake-drain.sh` before inspecting a worker or starting new work.
Follow the durable queued wake and current-state reconciliation rules in `AGENTS.md`.
If Pi reports a missing, failed, or unhealthy cycle, call `fm_watch_arm_pi` once to repair it.
Do not use shell backgrounding or invoke another watcher lifecycle shape.

While away mode is active, the away-mode daemon owns supervision instead.
