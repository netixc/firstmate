---
name: harness-adapters
description: Agent-only reference for Firstmate's Pi runtime operations. Use before spawning or recovering a crewmate or secondmate, handling Pi trust, sending a skill invocation, interrupting, exiting, or resuming an agent.
user-invocable: false
metadata:
  internal: true
---

# harness-adapters

Firstmate supports Pi alone for primary sessions, ordinary workers, scouts, persistent secondmates, recovery, validation, and supervision.
Herdr is the terminal workspace layer and is not a worker-runtime choice.
Do not add, select, or verify another worker runtime.
A model-provider identifier is not a runtime choice.

## Pi profiles and dispatch

`config/crew-profile` holds an optional ordinary-worker `<model> [<thinking>]` pin.
`config/secondmate-profile` holds an optional global secondmate pin.
`config/secondmate-profiles/<id>` overrides that global pin for one valid id.
An absent secondmate pin falls back to the ordinary-worker profile.
Pi thinking values are `low`, `medium`, `high`, `xhigh`, and `max`.
`config/crew-dispatch.json` profile objects contain a required Pi `model` and optional `effort` only.
`bin/fm-harness.sh` resolves profile model, thinking, and source.
`bin/fm-spawn.sh` accepts `--model` and `--effort` but rejects runtime selection.

An obsolete runtime-selection file is a hard migration boundary.
Run `bin/fm-pi-runtime-migrate.sh --check` to list the local edits required.
The command never rewrites private configuration.
Do not select around an obsolete file or silently substitute a model.

For a matched dispatch array, load `quota-array-dispatch` before choosing the Pi model and thinking candidate.
Use `pi --list-models [search]` and Pi's current authenticated catalog to establish model support and provider identity.
Use `quota-axi` evidence at the provider or model granularity it supplies.

## Spawn and trust

`bin/fm-spawn.sh` owns Pi's launch template, model flag, thinking flag, task isolation assertion, metadata publication, and task extensions.
A worker starts with one encoded launch brief positional message.
A secondmate starts with both tracked Pi primary extensions from its home.
Pi has no permission system, so a spawned worker is autonomous after any project-trust prompt is accepted.
A Pi trust prompt can appear for a fresh worktree path.
Accept it with Enter, then verify the worker has begun its instructions.

The metadata field is always `harness=pi` as a fixed identity guard.
A missing or non-Pi recorded value is not recoverable as another runtime.
Preserve its isolated work and durable records, then follow `stuck-crewmate-recovery` or `secondmate-provisioning` as applicable.

## Busy state, interruption, exit, and resume

Pi task extensions publish generation-bound busy and idle state.
`bin/fm-busy-lib.sh` owns the semantic interpretation.
Missing, malformed, stale, or untrusted state is unknown rather than idle.
A confirmed gone Herdr endpoint is the only process-level dead override.

Use a single Escape to interrupt Pi.
Use `/quit` to exit Pi when the applicable lifecycle owner instructs it.
Use Pi's supported resume behavior only after recovery has reconciled the recorded task identity.
Do not infer a resumable session from terminal text.

## Validation and skill invocation

Pi has no separate cross-runtime skill-invocation syntax.
Tell the worker to run `/no-mistakes` or give the equivalent clear natural-language instruction when validation is due.
`fm-send.sh` treats that message as ordinary Pi text and confirms submission through Herdr's agent state.
The worker that starts no-mistakes owns its run and every gate response.

## Primary supervision

The tracked Pi extensions own primary session-start delivery, turn-end protection, and watcher continuity.
`fm-primary-turnend-guard.ts` requests one bounded follow-up only when the shared guard says supervision is required and unhealthy.
`fm-primary-pi-watch.ts` owns the watcher child and its retry sequence.
Call `fm_watch_arm_pi` only for the first required cycle or after the extension reports a missing, failed, or unhealthy cycle.
Never substitute shell backgrounding, a direct watcher arm, or another runtime's waiting shape.

For real runtime behavior changes, verify Pi and Herdr in the guarded non-default Herdr lab specified by the task brief.
Update `docs/verification/runtime-backends.md` and `docs/verification/supervision.md` with concise current Pi evidence when behavior changes.
