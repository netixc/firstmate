# Herdr session provider

Herdr is Firstmate's sole session provider.
It owns every task, scout, secondmate, supervisor, send, capture, state, recovery, and cleanup endpoint.
Treehouse remains the worktree provider for ship and scout tasks and the durable-home lease provider for secondmates.
Worker runtimes remain independently selectable through the harness configuration.

## Setup

Install the pinned Herdr build with `bin/fm-install-herdr.sh` and install Treehouse with `bin/fm-install-treehouse.sh`.
The full shared toolchain is owned by [configuration.md](configuration.md#toolchain).
Firstmate requires a Herdr client protocol of at least 14 and refuses older or unreadable builds.
Native transition events and presentation ordering require protocol 16; their absence degrades only those optional optimizations and never changes endpoint ownership.

`HERDR_SESSION` selects the normal named session and defaults to `default`.
It is not a provider-selection surface and is never sufficient isolation for destructive test cleanup.

## Container model and durable routing

Each Firstmate home has one reusable Herdr workspace and each direct report has one tab with one authoritative pane.
The primary home uses workspace label `firstmate`.
A home containing `.fm-secondmate-home` uses workspace label `2ndmate-<id>`.
A primary launching a secondmate derives the destination label from that secondmate's home so the persistent agent and its future crews share the same isolated workspace.

Task metadata records `window=<session>:<pane-id>` plus `herdr_session=`, `herdr_workspace_id=`, `herdr_tab_id=`, and `herdr_pane_id=`.
The `window=` value is endpoint authority for send, peek, state, supervision, recovery, and teardown.
Workspace and tab ids support exact cleanup and presentation recovery but never replace the authoritative pane target.
The selector vocabulary and legacy-metadata upgrade behavior are owned by [configuration.md](configuration.md#herdr-session-provider).

Workspace and task labels are adopted only after an unambiguous exact match.
Duplicate or ambiguous labels fail closed.
A restored tab with no registered agent is a husk and may be replaced only after the replacement tab is created successfully.
A live or ambiguously classified tab is never closed as a husk.
The seeded default tab is pruned only when its exact id came from the response that created the workspace; an adopted workspace never gains a heuristic prune candidate.

## Endpoint behavior

`bin/fm-backend.sh` is the Herdr-only shared endpoint abstraction.
`bin/backends/herdr.sh` owns protocol checks, workspace and tab lifecycle, bounded capture, send and submit confirmation, semantic busy state, composer classification, event waiting, agent liveness, focus-safe presentation operations, and exact endpoint cleanup.
Consumers call the shared functions without a provider argument.

Herdr's registered-agent state supplies confident `alive`, `dead`, and `unknown` liveness for secondmate recovery.
The watcher uses semantic agent state first and falls back to bounded captured output when a foreground tool temporarily makes native state inconclusive.
Protocol-16 sessions may subscribe to `pane.agent_status_changed` for immediate blocked transitions; connection, schema, or repeated runtime failure falls back to polling.

Text is typed once and Enter is retried only through the shared verified-submit contract.
An idle or done native baseline is confirmed by observing a working or blocked transition.
Unreadable state returns `unknown`, and a composer that remains populated returns `pending`; neither is treated as successful delivery.
The composer classifier accepts only verified agent-composer shapes and treats an ordinary shell prompt as unknown.
Dim, faint, and dark-truecolor suggestion text is stripped through `bin/fm-composer-lib.sh` before typed-content classification.

Herdr reports a pane's live process directory through `foreground_cwd`; the creation-time `cwd` field is not used for worktree discovery.
Bounded capture internally compensates for Herdr builds whose `pane read --lines N` may return empty at small values.

## Optional disposable single-task presentation spaces

The local presence flag `config/herdr-presentation-spaces` enables a default-off visual projection for newly spawned work.
It does not change task identity, endpoint authority, worktree ownership, durable routing, recovery, or teardown gates.
The task still has one authoritative pane and one metadata record.

Projection is attempted only when the pre-create layout is unambiguous and the target task is new.
Firstmate journals the exact projection id and created workspace before mutating layout.
Create, ordering, focus restoration, and cleanup serialize through a machine-private session lock whose ownership and mode are validated before use.
If projection, ordering, or focus restoration is ambiguous, Firstmate keeps the worker alive and records enough state for conservative recovery.
Cleanup closes only exact recorded ids and refuses any action that could close the captain's active tab or disturb an unverified focus snapshot.
Stale or malformed journals are quarantined rather than guessed from labels.
Secondmate homes inherit the flag under the `secondmate-provisioning` contract.

## Away-mode supervision

The away-mode daemon injects only into Firstmate's Herdr pane.
`FM_SUPERVISOR_TARGET=<session>:<pane-id>` is the explicit target override.
Otherwise discovery requires `HERDR_PANE_ID` and combines it with `${HERDR_SESSION:-default}`.
The daemon checks exact pane existence, semantic busy state, and an affirmatively empty composer before typing a digest.
It defers on pending or unknown composer state and raises the configured wedge alarm after the bounded defer window.
The helper terminal created by `bin/fm-afk-launch.sh` is a non-visible Herdr workspace and is removed by exact workspace id on return.

## Isolated Herdr verification

Every local lifecycle experiment must use `bin/fm-herdr-lab.sh` and a generated non-default session.
The helper is the sole owner of lab provisioning, command routing, deliberate stop, and teardown.

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh
HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name my-check)
trap '"$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION"' EXIT
"$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION"
"$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" status --json
```

The helper appends a trailing `--session <name>` to every Herdr call and rejects caller-supplied session flags, server operations, and session lifecycle operations through `run`.
Use its guarded `stop` only for a deliberate mid-run stop.
Use its guarded `teardown` for cleanup.
Never call a server-global operation or direct session stop/delete in a test.

Before provisioning, the helper records the one running `default` session as a fleet-state tripwire.
It rechecks that the lab target is non-default immediately before every destructive call and requires the identical default-session state after teardown.
A missing, stopped, changed, or ambiguous default session is a hard failure.

The real-Herdr regression family is selected with `bin/fm-test-run.sh --family real-herdr-gated`.
Those tests use isolated generated sessions and must never operate the captain's default fleet.

## Known limitations

- A long foreground tool can temporarily leave native agent state reading idle, so busy detection corroborates non-busy verdicts with bounded pane output.
- The verified-submit path cannot prove a busy OpenCode queued-Enter acknowledgement until the composer clears or native state supplies a usable transition, so it fails closed as pending instead of risking duplicate input.
- Native push events require protocol 16 and fall back to polling when unavailable or unstable.
- Mid-session secondmate liveness is reconciled by normal supervision and targeted recovery; the deterministic respawn sweep runs at session start.

Focused fake-CLI coverage lives in `tests/fm-backend-herdr.test.sh` and the shared Herdr-only contract lives in `tests/fm-backend.test.sh`.
