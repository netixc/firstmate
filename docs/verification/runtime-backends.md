# Pi and Herdr verification

Firstmate supports Pi as its sole worker runtime and Herdr as its sole terminal workspace layer.

## Herdr

Herdr supplies the named terminal workspace, endpoint identity, and lifecycle boundaries for every Pi worker.
The maintained checks below cover the supported interface rather than a retired multi-runtime adapter matrix.

## Executable coverage

- `tests/fm-harness-pi.test.sh` proves Pi-only detection, profiles, migration rejection, and invalid configuration behavior.
- `tests/fm-spawn-dispatch-profile.test.sh` proves Pi-only ordinary-worker launch and model/thinking dispatch.
- `tests/fm-secondmate-profile.test.sh` proves Pi secondmate profile precedence and recovery refusal for non-Pi records.
- `tests/fm-secondmate-sync.test.sh` proves guarded local pre-launch sync completes before later Pi profile validation can refuse launch.
- `tests/fm-remote-secondmate-lifecycle-e2e.test.sh` proves remote secondmates negotiate mixed tracked controller versions, launch through Pi with a Herdr endpoint, and return Pi-only route identity.
- `tests/fm-backend-herdr.test.sh` and the Herdr smoke suites prove endpoint identity, task isolation, and safe pane lifecycle behavior.

## Workspace removal focus safety

The guarded Herdr tests cover exact workspace and pane identity before a removal or recovery action.
They keep a default session outside each task lab and refuse ambiguous bindings rather than closing a guessed workspace.

## Live verification boundary

Use `bin/fm-herdr-lab.sh` with a generated non-default lab session for real Pi and Herdr behavior checks.
The helper owns every task-specific Herdr lifecycle action and verifies the default fleet is unchanged after teardown.
Do not treat a shell mock as proof of installed Pi or Herdr behavior.

## Current live evidence

On 2026-08-08, `pi --version` reported `0.84.1`.
A generated guarded lab reported Herdr `0.8.0` with protocol `19`.
A new no-focus workspace and tab were created only through the lab helper, and `pi --version` captured from that isolated Herdr pane also reported `0.84.1`.
The helper teardown completed with its default-session tripwire intact.

[`herdr-backend.md`](../herdr-backend.md) owns operator setup and destructive-lab safety.
