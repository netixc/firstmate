# Plain Pi

Verified with real Pi; [`docs/verification/runtime-backends.md`](../../../../../docs/verification/runtime-backends.md) owns current versioned evidence and refresh commands.

## Operating facts

| Fact | Value |
|---|---|
| Busy state | The Firstmate extension's `agent_start` marks busy and `agent_settled`, confirmed by `ctx.isIdle()`, marks idle. |
| Exit command | `/quit`. |
| Interrupt | Single Escape. |
| Skill invocation | Use natural language when an exact command is not documented. |
| Model flag | `--model <model>`. |
| Effort flag | `--thinking <low\|medium\|high\|xhigh\|max>`. |
| Model discovery | `pi --list-models [search]`. |

Pi has no permission system, so workers are autonomous.
`bin/fm-spawn.sh` pins the concrete `pi` executable and starts it through `bin/fm-pi-launch.sh`, which publishes the parent-owned identity evidence required by liveness and control.
Instructions remain one positional argument because multiple positional arguments become separate queued messages.
A first-run project trust dialog is accepted with Enter only after the path is verified, followed by proof that instructions started processing.

`bin/fm-spawn.sh` writes the worker lifecycle extension under private state, outside the project copy.
The extension listens for Pi's semantic lifecycle and turn-end events, but does not create or upgrade its own parent launch evidence.
Pi identifies child processes with `PI_CODING_AGENT=true`.

The primary retains `.pi/extensions/fm-primary-turnend-guard.ts` and `.pi/extensions/fm-primary-pi-watch.ts`.
The watcher cycle is armed through `fm_watch_arm_pi`, and `docs/supervision-protocols/pi.md` owns the protocol.
Secondmates launch plain Pi with both primary extensions explicitly loaded.

Any recorded identity other than exact `pi`, including the former signed wrapper identity, is unsupported migration input and is never relabeled.
