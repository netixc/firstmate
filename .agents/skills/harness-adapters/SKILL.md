---
name: harness-adapters
description: >-
  Agent-only reference for plain Pi worker operations.
  Use before spawning or recovering a worker or secondmate, handling trust, invoking a Pi skill, interrupting or exiting an agent, or verifying Pi integration.
user-invocable: false
metadata:
  internal: true
---

# harness-adapters

Plain Pi is Firstmate's only supported worker and primary harness.
Load the applicable common references plus [`references/harness/pi.md`](references/harness/pi.md).

Exact identity is mandatory.
`bin/fm-harness.sh`, `bin/fm-spawn.sh`, and `bin/fm-control.sh` reject legacy metadata, old configuration, raw commands, `pi-signed`, and every other harness identity.
Never reinterpret or substitute an excluded identity as Pi.

Use `bin/fm-control.sh <task-id> interrupt|exit|relaunch` for lifecycle control and the recorded exact `harness=pi` value for recovery.
An `unknown` primary is unsupported and requires migration rather than a guess.
Trust handling is complete only when inspection proves Pi started processing its instructions.

## References

- Dispatch: [`references/common/dispatch.md`](references/common/dispatch.md)
- Model and effort: [`references/common/model-and-effort.md`](references/common/model-and-effort.md)
- Control and recovery: [`references/common/control-and-recovery.md`](references/common/control-and-recovery.md)
- Primary hooks: [`references/common/primary-hooks.md`](references/common/primary-hooks.md)
- Pi adapter: [`references/harness/pi.md`](references/harness/pi.md)
