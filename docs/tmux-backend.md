# tmux runtime backend

tmux is Firstmate's retained rollback session backend for explicit endpoints that already exist.
It remains a verified implementation and reference baseline, but cannot create fresh task or secondmate endpoints.
[`configuration.md`](configuration.md#runtime-backend-configbackend--fm_backend) owns shared backend selection and metadata semantics.

## Setup

Install tmux with `brew install tmux` or your platform package manager.
The universal harness and toolchain requirements are in [`configuration.md`](configuration.md#toolchain).

Fresh work defaults to Herdr.
A local `config/backend` containing `tmux`, `FM_BACKEND=tmux`, or an explicit `--backend tmux` request refuses before endpoint or isolated-copy creation and explains that tmux is rollback-only.
Runtime markers do not opt fresh work into tmux.

Keep tmux installed while this home has an exact existing `backend=tmux` record.
Bootstrap detects that recorded rollback need and reports a missing tmux executable even though fresh work resolves to Herdr.

## Watching the crew

An explicit existing rollback record names the tmux session and exact `fm-<id>` window it was created with.
Firstmate no longer creates or adopts a tmux session for fresh work.
To inspect a retained endpoint, attach to its recorded session:

```sh
tmux attach -t <recorded-session>
```

`tmux display-message -p '#S'` prints the attached session name.

```sh
tmux list-windows -t <session-name>
tmux select-window -t <session-name>:fm-<id>
```

Typing into an attached rollback task window is authoritative direct intervention.
Routine supervision does not require attachment: `bin/fm-peek.sh <id>` captures a bounded tail and `FM_HOME=<home> bin/fm-send.sh <id> '<text>'` steers an exact recorded endpoint.
Unrecorded tmux window names and backend-less records are refused rather than inferred.

Do not verify tmux by spawning a new Firstmate task.
Use the retained adapter regression entry points below or inspect an explicit existing rollback record.

## Current behavior and safety

### Agent liveness probe

A target-existence check proves only that the pane exists.
The deeper tmux agent-liveness probe first verifies exact window membership, then reads process names to distinguish a running harness from a bare idle shell.
It classifies exact plain-Pi process identity as `alive`, common shells as `dead`, an authoritatively absent window as `missing`, unreadable state as `unreadable`, and every other process as `ambiguous`.
The process-name vocabulary behind those verdicts is owned by `bin/fm-agent-process-lib.sh` and shared with the Herdr adapter, which proves a registered agent against the same names ([herdr-backend.md](herdr-backend.md) "Restart and liveness behavior").
Only `dead` and `missing` authorize recovery because a false dead result could launch a duplicate agent.

For positive attribution, the probe combines two independent name sources rather than making either one load-bearing.
`#{pane_current_command}` and the pane tty foreground process group's kernel `comm` values expose different name fields, and which one retains executable identity is platform-dependent.
The foreground probe also reads argv[0] so an exact `pi` install-path component can carry the verdict when another field exposes a rewritten title.
Either source naming exact Pi identity is enough for `alive`, because a false `dead` could start a duplicate agent on a live worktree, while a readable foreground process group settles the negative verdicts.

Scoping the second source to the foreground process group rather than to the pane's descendants is deliberate: a Pi-named process left running in the background of an otherwise idle pane must not read as the agent.
Generic Node processes, mixed-case names, and prefixed lookalikes remain ambiguous rather than borrowing Pi identity.
The CI-enforced portable regression and opt-in real-harness drift guard follow the split owned by `.agents/skills/firstmate-coding-guidelines/SKILL.md`.
Run the real-harness guard after any harness upgrade and before trusting refreshed evidence.

### Composer, busy state, and delivery

Agent liveness and composer safety are separate checks.
The tmux reader is a thin adapter over the fleet-wide classifier in `bin/fm-composer-lib.sh`: it contributes one styled full-pane capture, the `#{cursor_y}` cursor row, and foreground-process identity probes, and Pi's identified composer structure decides the verdict.
Real text in an identified shape is pending, while only positively proven emptiness reads empty.
A blank or otherwise unidentified cursor row is `unknown` and every consumer defers, so a modal dialog, a dead shell between stale rules, or a mid-redraw pane is never an injection target.
The shared classifier accepts a shell glyph as an empty agent composer only inside a bordered container.
A bare shell prompt is `unknown`, so away-mode escalation is never injected into a dead shell.

Busy state is not read from rendered text on this backend.
A task's busy, idle, unknown, or dead verdict comes from the semantic busy-state contract owned by `bin/fm-busy-lib.sh`; [architecture](architecture.md#busy-state-is-semantic-per-adapter) owns its boundaries.
No rendered-tail reader classifies worker state; missing semantic lifecycle evidence remains unknown.
The submit acknowledgement and away-mode supervisor-pane busy guard below still consult rendered output, but only to decide whether input can be delivered, never to decide recorded task state.
The supervisor guard uses only Pi's delivery signature rather than a global union of vendor patterns.

`bin/fm-tmux-lib.sh` owns exact type-and-submit mechanics.
It types a message once and retries Enter only until the composer clears.
Only a proven empty composer is a positive delivery acknowledgement.
Text left in established structure remains `pending`, text in ambiguous structure remains unproven, and unreadable or unsafe state remains unknown.
An ordinary local `fm-send.sh` text steer and every remote text steer no longer ride this verified submit at all: they become durable steering-inbox records plus best-effort constant doorbell lines (`bin/fm-task-inbox-lib.sh`).
The verdicts above are delivery-critical only for the local typed plane - harness-native invocations and explicit backend targets - where `fm-send.sh` still never retypes or assumes a confirmed submit for an unconfirmed verdict; its header owns the distinct delivered-unconfirmed exit status and operator response.

Pi replaces its separated composer while working, so a baseline-gated conversion handles mid-turn submission: when and only when the pane was idle before text was typed, an idle-to-busy transition across the submit's own Enter confirms delivery, the same turn-started signal Herdr reads natively.
Without that baseline, an `unknown` verdict is preserved untouched, so a busy-looking pane can never convert an unread composer into a confirmation.
`tests/fm-tmux-submit-busy.test.sh` covers busy and idle panes with proven, ambiguous, and cleared composers.

## Limits and regression entry points

- tmux supports exact existing task and secondmate rollback records but no fresh creation.

```sh
tests/fm-backend-tmux-smoke.test.sh
tests/fm-tmux-agent-liveness.test.sh
tests/fm-harness-liveness-drift-live-e2e.test.sh
tests/fm-composer-ghost.test.sh
tests/fm-tmux-submit-busy.test.sh
tests/fm-bootstrap.test.sh
```

[`verification/runtime-backends.md`](verification/runtime-backends.md#tmux) records the active foreground-process and submit evidence.
