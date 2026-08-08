# Pi supervision verification

This record covers Firstmate's supported Pi primary supervision path.
Herdr remains the terminal workspace layer for the tests below.

## Executable coverage

- `tests/fm-supervision-instructions.test.sh` proves the renderer accepts Pi and rejects another runtime request.
- `tests/fm-turnend-guard.test.sh` proves Pi's guard blocks only when supervision is required and unhealthy.
- `tests/fm-session-start.test.sh` proves session start emits Pi instructions and reports invalid runtime configuration.
- `tests/fm-pi-watch-extension.test.sh` proves Pi's watcher extension owns one generation-bound child and bounded restoration.
- `tests/fm-arm-pretool-check.test.sh` and `tests/fm-cd-pretool-check.test.sh` prove the Pi command guards.
- `tests/fm-afk-launch.test.sh` proves away mode creates and removes an exact non-visible Herdr terminal record.

## Wedge-alarm channels

`tests/fm-daemon.test.sh` covers directive selection, bounded notifier execution, and fallback behavior.
Operator configuration remains in [`wedge-alarm.md`](../wedge-alarm.md).

## Live verification boundary

Run real Pi and Herdr checks only in a named non-default Herdr lab through `bin/fm-herdr-lab.sh`.
The lab helper owns provisioning, every Herdr command, stop, and teardown.
A task-specific check must preserve the default Herdr session before and after the lab.

The installed Pi extension surface must load from the trusted project before primary session-start, turn-end, or watcher behavior is considered verified.
`pi --version`, `pi --list-models`, and a real guarded lab turn are the authoritative evidence for installed behavior.
