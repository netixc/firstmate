# Agent lifecycle control plane

Firstmate talks to a running agent two ways, and they are not the same channel.

The **data plane** is [`bin/fm-send.sh`](../bin/fm-send.sh): conversational text for the agent to read.
For a `kind=secondmate` target it always prepends the from-firstmate routing marker, because a secondmate is itself a firstmate and its reply must come back through the status path rather than a chat nobody reads.

The **control plane** is [`bin/fm-control.sh`](../bin/fm-control.sh): allowlisted lifecycle verbs addressed to an exact task id.

The split exists because the data plane's marking is exactly right for a message and exactly wrong for a lifecycle command.
A routing-marked `/quit` arrives as ordinary chat - `[fm-from-firstmate] /quit` - which the agent reasons about instead of executing.
The failure repeated across homes, and the workaround (remember to use an unmarked send for agent-control commands and improvise Pi's key or command) lived only in agent prose, so it failed again every time a session did not happen to recall it.

## What the control plane owns

`bin/fm-control-lib.sh` is the side-effect-free executable owner of the closed verb list and Pi lifecycle mechanics:

- The **verb allowlist**: `interrupt`, `exit`, `relaunch`.
  There is no arbitrary-text and no generic raw-key entry point.
  A caller either names an allowlisted verb or is refused.
- **Pi mechanics**: the key that cancels a running turn, how many times it must be delivered, and the command that exits the agent.
  The [`pi-operations`](../.agents/skills/pi-operations/SKILL.md) skill carries the corresponding operator facts.

A recorded `harness=` must be exactly `pi`.
Any other or missing value is preserved and refused rather than reinterpreted.

## Verbs

| Verb | Effect | Postcondition |
| --- | --- | --- |
| `interrupt` | Deliver Pi's verified interrupt sequence while leaving the agent running. | Delivery succeeds, the exact Herdr endpoint still exists, and native state still reports Pi alive; cancellation is confirmed only from Pi's acknowledgement and otherwise reports `cancel=unconfirmed`. |
| `exit` | Stop the agent, preserving the endpoint, the worktree, and every uncommitted change. | Herdr's recovery-grade classifier reports the agent gone. Already-stopped is idempotent success. |
| `relaunch` | Replace the running Pi agent with a new one in the same endpoint and worktree, optionally changing model and effort. | The new agent is alive on the recorded endpoint, and the durable record names Pi as the runtime actually running. |

An exit that delivers lifecycle input but cannot prove the agent stopped fails with `exit=unconfirmed`, reports the observed agent state and any interrupt cancellation claim, and never claims that nothing changed.
Interrupt never rewrites busy state as proof of its own success.
**Teardown and discard are not verbs and will not become verbs.**
`exit` stops an agent and preserves everything else.
Removing a worktree, closing an endpoint, or discarding work stays with [`bin/fm-teardown.sh`](../bin/fm-teardown.sh), which owns the landed-work test.

**`resume` is not a verb.**
Pi has no verified pane-resume contract.
`relaunch` covers the same need on Pi, because the brief on disk - not a harness-private session - is the durable instruction.

## Transactional relaunch

`relaunch` is the only verb that changes durable records, so it runs as a transaction with a journal at `state/<id>.control-relaunch`, the prior record preserved beside it, and a ship or scout's prior instructions preserved when a progress note is appended.

1. **Resolve the profile.**
   Pi is fixed; an explicit `--model` or `--effort` replaces the matching recorded axis.
   A record that does not name Pi refuses before the checkpoint.
   A same-Pi relaunch retains its recorded model and effort unless explicit values replace them.
2. **Safe checkpoint.**
   The recorded worktree must exist and be a worktree root; its head and dirty state are recorded.
   For a `kind=secondmate` task, the home's identity marker must match and its child records must be readable, so a relaunch can never strand child work behind an unreadable home.
   A secondmate's own crewmates run in their own endpoints and outlive its relaunch; the relaunched secondmate reconciles them from its home's durable records at startup.
3. **Record the note.**
   A ship or scout relaunch requires `--note`, because the replacement inherits the local copy but none of the conversation; the note is appended to the instructions it reads.
   A secondmate relaunch does not require one and never rewrites its standing charter.
4. **Stop the old agent** through the `exit` verb, with its postcondition.
5. **Launch the replacement** through its single owner, `bin/fm-spawn.sh --relaunch`, which adopts the recorded endpoint and worktree instead of creating either and arms a fresh busy generation.

### Failure and rollback

- A refusal **before** the agent is stopped leaves the durable record and the instructions byte-identical.
- A launch failure **after** the agent is stopped restores the prior durable record, keeps the progress note so a later recovery still has it, marks the journal `failed:launching`, and reports plainly that no agent is running and where the work is preserved.
- If the launch owner already published the new record but no running agent can be confirmed, the new Pi record is kept, which is exactly what recovery reconciles.
  Rewriting it back to the prior record would be a second, worse inaccuracy.

## Fail-closed boundaries

- Targeting is exact.
  Only a bare task id with a `state/<id>.meta` record in this home is accepted, and that record must pass the shared endpoint-identity validation.
  A legacy `fm-<id>` window label, an explicit `session:window` endpoint, and a record whose `endpoint_task_id` names another task are all refused.
- A remotely placed secondmate is refused by name.
  Its agent runs on another host, so none of the postconditions this plane verifies could be read for it here; local exact-Herdr endpoint validation refuses the remote route record.
  Drive that lifecycle on its own host and reconcile it through the secondmate recovery path.
- A record that does not name Pi is refused before the agent or durable state is touched.
- `exit` and `relaunch` require Herdr's recovery-grade agent-state classifier because without it the "the agent stopped" postcondition cannot be proven.
- An ambiguous or unreadable endpoint state refuses.
  Only a positively classified state acts.
- `fm-spawn --relaunch` independently refuses unless the recorded endpoint is positively agent-free and its shell is sitting in the recorded worktree, so a replacement can never join a live agent or start outside the copy holding the work.

## Verified mechanics

Pi interrupts with `Escape` and exits with `/quit`.
Herdr delivers Pi's named keys and provides the recovery-grade native process state used for every postcondition.
The executable facts live in `bin/fm-control-lib.sh`; empirical evidence lives in the `pi-operations` skill and [`verification/herdr-runtime.md`](verification/herdr-runtime.md).

## Verification

- `tests/fm-control.test.sh` - exact-id scoping, the closed verb list, busy, idle, dead, and idempotent lifecycle cases through the Herdr seam.
- `tests/fm-control-relaunch.test.sh` - the Pi relaunch transaction: identity preservation, profile threading, the progress note, checkpoint refusals, and rollback after a failed launch.
- `tests/fm-control-herdr-smoke.test.sh` - process control against the real Herdr binary in an isolated lab session.
