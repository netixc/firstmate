# Runtime backend verification

Audience: maintainer verification.

This record contains reusable version-scoped evidence for active runtime guarantees.
The backend guides own current setup, safety boundaries, and limitations.
Exact task chronology, branch names, temporary homes, local paths, process ids, thread ids, and delivery transcripts remain in private reports or PR evidence.

## Plain Pi runtime identity

`bin/fm-harness.sh` accepts only the plain npm-installed Pi CLI identity `pi`.
Process evidence requires an executable named exactly `pi`; Pi's own environment marker is a separate self-identification signal and never makes a generic Node process count as Pi liveness.
The portable regression builds synthetic process trees from renamed executables and pins marker-only and exact-ancestry cases:

```sh
bin/fm-test-run.sh tests/fm-harness-precedence.test.sh
```

Generic Node/Python processes, argument strings, parent directory names, mixed-case or prefixed lookalikes, and unknown runtime names remain unverified.
Provider/model identifiers such as `codex-native/*` are profile axes behind Pi and never runtime identities.

The authoritative executable checked for this contraction was `/opt/homebrew/bin/pi`, version 0.85.1, resolving to `@earendil-works/pi-coding-agent/dist/bundle/cli.js`.
The live guard launches that executable through a real isolated `fm-spawn.sh` path, records the exact arguments, removes only the final task prompt to avoid a provider call, then executes Pi with the requested provider/model, effort, and generated extension unchanged.
It proves the recorded runtime remains `pi`, the process has exact Pi identity, and cleanup removes the private tmux endpoint and worktree:

```sh
bin/fm-test-run.sh tests/fm-pi-spawn-profile-live-e2e.test.sh
```

Observed 2026-09-18 with Pi 0.85.1:

```text
ok - plain Pi 0.85.1 launched with provider/model=openai-codex/gpt-5.6-sol effort=xhigh and exact live Pi identity
ok - isolated tmux spawn and cleanup completed without touching the ambient tmux server
```

## tmux

Foreground-process behavior was verified on tmux with an isolated session: an idle shell reported its shell name, a directly executed command reported that command, and interruption returned the pane to the shell.
The task liveness classifier recognizes only exact Pi identity from the pane title or exact foreground executable fields.
A generic `node` process is ambiguous rather than alive, and names such as `Pi` or `pi-helper` do not borrow Pi identity.
Portable coverage lives in:

```sh
bin/fm-test-run.sh tests/fm-tmux-agent-liveness.test.sh tests/fm-secondmate-liveness.test.sh
```

The live drift guard uses a private tmux socket, spends no model tokens unless it actually launches Pi, and must be rerun after Pi upgrades:

```sh
FM_HARNESS_LIVENESS_DRIFT=1 bin/fm-test-run.sh tests/fm-harness-liveness-drift-live-e2e.test.sh
```

## Adapter instruction routing

`tests/fm-harness-adapter-references.test.sh` parses the router's declared contract and proves every Pi reference is readable.
`tests/fm-harness-adapter-instructions-live-e2e.test.sh` is an opt-in local-model evaluation of every operation scenario and makes no external-provider call:

```sh
FM_HARNESS_ADAPTER_INSTRUCTION_EVAL=1 \
FM_HARNESS_ADAPTER_LOCAL_MODEL=<local-model> \
bin/fm-test-run.sh tests/fm-harness-adapter-instructions-live-e2e.test.sh
```

That check demonstrates instruction routing only; native loader behavior remains the responsibility of the live Pi launch proof.

## Cleanup endpoint identity

Cleanup validation covers exactly tmux and Herdr before backend dispatch.
Missing, empty, malformed, ambiguous, unknown-backend, and task-mismatched endpoint records refuse before mutation, while valid task-bound records close only their exact endpoint.

```sh
bin/fm-test-run.sh \
  tests/fm-teardown-endpoint-safety.test.sh \
  tests/fm-teardown.test.sh \
  tests/fm-backend-herdr.test.sh
```

The dedicated tmux cell removes ambient tmux variables, uses a socket-bound wrapper, keeps an independent control window, and proves invalid metadata never invokes the backend.
Herdr cleanup additionally treats `lsof` as a preflight dependency because a closed Herdr pane has no safe process-group fallback for reparented task descendants.
`tests/fm-teardown.test.sh` proves both sides: with `lsof`, an exact cwd-bound leaked process is reaped before the isolated copy is returned; without `lsof`, cleanup refuses before endpoint mutation and preserves every durable task record.

## Composer classification matrix

The shared classifier in `bin/fm-composer-lib.sh` owns every composer verdict; tmux and Herdr contribute captures and declarative capabilities only.
The live matrix launches plain Pi in an isolated tmux session and proves its real idle composer classifies `empty`, while a blank shell row remains `unknown` and injection defers:

```sh
FM_COMPOSER_MATRIX_LIVE=1 tests/fm-composer-matrix-live-e2e.test.sh
```

Portable byte-capture coverage lives in `tests/fm-composer-lib.test.sh` and `tests/fm-composer-ghost.test.sh` under both UTF-8 and `LC_ALL=C`.
Herdr's idle-native submit confirmation is pinned by `tests/fm-backend-herdr.test.sh`.

## Steering-inbox doorbell

The live doorbell guard drives the real `bin/fm-send.sh` against plain Pi on an isolated tmux socket and requires Pi to list the named inbox, act on the record, and acknowledge it with the atomic move into `handled/`:

```sh
FM_SEND_INBOX_LIVE_E2E=1 tests/fm-send-inbox-doorbell-live-e2e.test.sh
```

The portable enqueue and retry ladder remain covered by `tests/fm-task-inbox.test.sh` and `tests/fm-send-inbox.test.sh`.

## Herdr

The production floor is Herdr 0.9.0 and protocol 22; both signals are required.
The pinned installer and the required real-Herdr CI matrix exercise that exact floor on hosted Linux x86_64 and hosted macOS.
Earlier 0.7.x and 0.8.0 measurements below remain historical evidence for defensive fallback behavior, not supported-runtime claims.
The event and workspace-move capability gates remain protocol 16, and the retained presentation capability gate remains Herdr 0.8.0 / protocol 19, but every supported production runtime exceeds all three.

Core read-only probes:

```sh
herdr --version
herdr status --json | jq -c '{client:.client.protocol,server:.server.protocol}'
herdr api schema --json | jq -c '.schemas.subscription_event["$defs"].SubscriptionEventKind.enum'
```

Active floor shape, observed 2026-09-18 on macOS aarch64:

```text
herdr 0.9.0
{"client":22,"server":22}
["pane.output_matched","pane.agent_status_changed","pane.scroll_changed"]
```

The CLI matrix was checked directly:

| Guarantee | Command shape | Result |
| --- | --- | --- |
| Explicit session routing | `herdr <verb> ... --session <name>` | Reached the named session even while another server was running. |
| Literal send | `herdr pane send-text <pane> <text> --session <name>` | Left text unsubmitted until Enter. |
| Keys | `herdr pane send-keys <pane> enter|escape|ctrl+c --session <name>` | Enter and Escape worked; Ctrl-C interrupted foreground work. |
| Capture | `herdr pane read <pane> --source recent --lines N` | Small N could return empty below viewport height; a 200-line request plus local trim was stable. |
| Native state | `herdr agent get <pane>` | Pi working and done transitions can be visible, but `agent_status=idle` may persist through a landed turn, so submit confirmation falls through to the shared composer verdict. Native `busy` remains positive activity evidence, while native `idle` cannot close a turn and the adapter's semantic lifecycle decides worker state. |
| Restart | guarded named-session stop then start | Workspace, tab, pane, and labels persisted; the agent process and registration did not. |
| Close | `herdr pane close <pane> --session <name>` | The exact one-pane task tab closed; closing a final tab could remove the workspace. |

All destructive verification used `bin/fm-herdr-lab.sh` with a non-default `fm-lab-` name and a byte-identical default-session tripwire.
No ambient `herdr server stop` command is a supported test operation.

### fm-remote server birth and login-keychain access

Measured 2026-09-09 on macOS 26 (Darwin 25.6.0) aarch64 with Herdr 0.9.0.
This is the guarantee behind `bin/fm-remote-herdr-guard.sh` and the doctor's `herdr-server` check: login-keychain access follows the audit session a process was born into, never the launch shape or shell.

The same user, `HOME`, and login-keychain test item were probed across three process births with `launchctl managername`, a compiled `getaudit_addr` probe, and `security find-generic-password -a "$USER" -w -s "<test-service>"` with the secret output withheld:

| Birth | `managername` | Audit session | Keychain read |
| --- | --- | --- | --- |
| `gui/501` LaunchAgent with bare `ProgramArguments` | Aqua | The `gui/501` asid with graphic, TTY, console, and authenticated access | exit 0 |
| `gui/501` LaunchAgent through `zsh -l -c 'exec ...'` | Aqua | The same `gui/501` asid and flags | exit 0 |
| `user/501` LaunchAgent with `LimitLoadToSessionType=Background` | Background | A separate asid with flags `0x0` | exit 36, `User interaction is not allowed.` |

Candidate birth markers were read with `ps -Eww -o command= -p <pid>` for same-uid processes.
macOS hides the environment of Apple platform binaries such as `/bin/sleep`, while the Herdr server is not a platform binary.

```text
launchd-born herdr server (child of launchd, gui/501): XPC_SERVICE_NAME=org.nix-community.home.herdr-server; no SSH_*
SSH-born herdr server (child of a remote-client bridge under sshd-session): SSH_CLIENT=... SSH_CONNECTION=...; no XPC_SERVICE_NAME
```

`XPC_SERVICE_NAME` identifies a launchd label but not its domain, because the Background `user/501` job also carried that variable while lacking keychain access.
The owner classifier therefore accepts that label only when `launchctl print gui/<uid>/<label>` identifies the owner pid or the label is loaded in `gui/<uid>` but not `user/<uid>`.
`XPC_SERVICE_NAME=0`, including a value inherited by a Herdr live-handoff child, remains unknown.
`FM_REMOTE_JOB_ACTIVE=1` proves the Aqua worker only when `dev.firstmate.remote-job` is loaded in `gui/<uid>` but not `user/<uid>`.

The SSH-born row came from a remote host where the launchd job repeatedly lost to a server that remote attach had started first in the SSH session.
`pgrep -f` did not expose that Herdr server's argv on macOS, while `lsof -U -a -c herdr -F pn` identified its socket owner.

A separate foreground-supervision check used a throwaway Aqua launch agent in a guarded named lab.
The Herdr server remained the foreground launchd job, owned the named session socket, stopped after the guarded session stop, stayed at rest through the throttle interval, and became the new socket owner after a second kickstart.
This proves the guard's final `exec` supplies launchd supervision and distinguishes an unrelated SSH-born server.

`bin/fm-test-run.sh tests/fm-remote-herdr-guard.test.sh` pins the resulting decision table against real marker-carrying processes, and `tests/fm-remote-doctor.test.sh` pins the doctor's verdicts on the same markers.

### Client selection

Measured 2026-09-08 on a macOS aarch64 host running a Herdr 0.9.0 server (protocol 22) for the `fm-remote` session while `~/.local/bin/herdr` still held the self-updated 0.8.2 client (protocol 20) ahead of the Nix-managed 0.9.0 client on the remote-job `PATH`.

```sh
~/.local/bin/herdr --version
~/.local/bin/herdr pane get wCY:p2 --session fm-remote; echo "rc=$?"
~/.local/bin/herdr status --json --session fm-remote | jq -c '{c:.client.protocol,s:{running:.server.running,protocol:.server.protocol,compatible:.server.compatible}}'
herdr status --json --session fm-remote | jq -c '{c:.client.protocol,s:{running:.server.running,protocol:.server.protocol,compatible:.server.compatible}}'
```

```text
herdr 0.8.2
{"id":"cli:pane:get","error":{"code":"protocol_mismatch","message":"client protocol 20 is older than server protocol 22; upgrade the Herdr client before using this command"}}
rc=1
{"c":20,"s":{"running":true,"protocol":22,"compatible":false}}
{"c":22,"s":{"running":true,"protocol":22,"compatible":true}}
```

The refusal is a JSON error on stderr with exit 1 and empty stdout, and both client generations report `.server.compatible` and `.server.protocol` per named session, which is what the selection in `bin/backends/herdr.sh` reads.
`tests/fm-backend-herdr.test.sh` pins the bypass, same-process same-session caching, cross-session isolation, forced reselection, and both status shapes against fakes; `tests/fm-backend-herdr-smoke.test.sh` refreshes the real status normalization against the installed binary's running lab server.

### Prune and respawn

The real label-collision reproduction is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-prune-safety-e2e.test.sh
```

Observed guarantee: a pre-existing captain-owned workspace with a seed-shaped tab was adopted for routing but its tab was never eligible for prune because the current create call did not return that seed id.

Restart-husk replacement is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-respawn-idem-e2e.test.sh
```

Observed guarantee: a restored no-agent tab was replaced create-before-close, while a registered live agent caused refusal.

### Launcher workspace placement

Herdr exports its pane identity into every process it manages, checked on 2026-07-30 against Herdr 0.7.5 protocol 17 inside a guarded lab pane:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh
"$HERDR_LAB_HELPER" run "$LAB" pane run "$PANE" "sh -c 'env | grep ^HERDR | sort > /tmp/env.txt'"
```

```text
HERDR_ENV=1
HERDR_PANE_ID=w1:p1
HERDR_SESSION=fm-lab-fm-herdr-env-pro-65961-25535
HERDR_SOCKET_PATH=/Users/kunchen/.config/herdr/sessions/fm-lab-fm-herdr-env-pro-65961-25535/herdr.sock
HERDR_TAB_ID=w1:t1
HERDR_WORKSPACE_ID=w1
```

This complete injection shape is verified only for Herdr 0.7.5.
Firstmate requires both `HERDR_PANE_ID` and `HERDR_SOCKET_PATH` before accepting claimed launcher ancestry.

`pane get` reports the pane's current owning tab and workspace, which is what placement resolves from; the injected `HERDR_TAB_ID` and `HERDR_WORKSPACE_ID` are creation-time snapshots and are not read as current identity:

```sh
"$HERDR_LAB_HELPER" run "$LAB" pane get w1:p1 | jq -c '.result.pane | {pane_id,tab_id,workspace_id}'
```

```text
{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"}
```

Placement is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-launcher-workspace-e2e.test.sh
```

Observed guarantees on 2026-07-30 against Herdr 0.7.5 protocol 17:

```text
ok - real herdr E2E: with one 'firstmate' workspace and no herdr parent, a crewmate still lands in this home's own workspace without stealing focus
ok - real herdr E2E: the normal unique-label path is unchanged when the launcher's own pane identifies the workspace
ok - real herdr E2E: presentation spaces still create the isolated child workspace and bind it under the launcher's exact parent, without stealing focus
ok - real herdr E2E: with two 'firstmate' workspaces, a worker spawned from inside the second one lands in that exact workspace
ok - real herdr E2E: the duplicate-labeled sibling workspace is left entirely untouched and focus is preserved
ok - real herdr E2E: with a duplicated home label, a projected worker still hangs off the launcher's exact workspace and the sibling stays untouched
ok - real herdr E2E: an ambiguous home label with no launcher identity refuses before any worker endpoint exists
ok - real herdr E2E: a launcher pane that no longer exists refuses before any worker endpoint exists
ok - real herdr E2E: a secondmate launching its own worker gets the same exact-workspace guarantee, and its same-labeled sibling is untouched
ok - real herdr E2E: a --secondmate launch still stands up that secondmate's own workspace instead of inheriting the launcher's
ok - real herdr E2E: teardown closes only the worker's own pane and leaves the launcher, its workspace, and the same-labeled sibling intact
```

That suite's headline case runs `bin/fm-spawn.sh` inside a real Herdr pane, so the parent identity comes from Herdr's own injection rather than a composed environment.
Cross-session and contradictory bindings are covered deterministically in `tests/fm-backend-herdr.test.sh`, which can script a second server's socket without provisioning one.

### Per-home and presentation topology

Per-home behavior is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-workspace-per-home-e2e.test.sh
```

Observed guarantee: the primary and secondmate used distinct home workspaces, a child launched by the secondmate stayed in that secondmate workspace, list-live remained home-scoped, and exact cleanup did not affect sibling homes.

The complete projection suite ran on 2026-07-21 against Herdr 0.7.4 protocol 16:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-presentation-e2e.test.sh
```

Observed guarantees included:

```text
ok - real Herdr lab: primary and two secondmate homes each own a top-level contiguous child block
ok - real Herdr lab: concurrent primary/A/B spawns stay session-locked with zero focus drift
ok - real Herdr lab: session lock contention from a secondmate home falls back flat with no journal
ok - real Herdr lab: legacy projection labels and flat secondmate tabs are left unmigrated
ok - real Herdr lab: multi-home exact-pane teardowns restore captain focus without workspace close authority
ok - real Herdr lab validation completed on Herdr 0.7.4 with the default-session tripwire intact
```

The suite also covers lost or failed move responses, restart husks, missing and duplicate tokens, manual renames, concurrent cleanup, and exact focus restoration.

The mandatory projection suite ran again on 2026-07-24 against Herdr 0.7.5 protocol 16:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-presentation-e2e.test.sh
```

Observed restart-reclaim guarantees:

```text
ok - real Herdr lab: Hi Bit and Wheelhouse-style same-identity restarts reclaim one nested space with exact focus and idempotence
ok - real Herdr lab: secondmate restart binding and reclaim stay isolated to the exact child home and parent
ok - real Herdr lab: concurrent cross-home recoveries replace exact husks under one session lock with no focus drift
ok - real Herdr lab: missing, renamed, and duplicate tokens trigger zero destructive or adoptive calls, and live duplicate risk refuses launch
ok - real Herdr lab validation completed on Herdr 0.7.5 with the default-session tripwire intact
```

The projection suite ran again on 2026-08-04 against Herdr 0.8.0 protocol 19 for the default-on flip, where an absent `config/herdr-presentation-spaces` enables the projection and the value `off` opts out; since 2026-08-05 an absent file enables the projection only at or above the 0.8.0 floor recorded under "Presentation version floor" below, and `on` is the explicit opt-in that survives the floor:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-presentation-e2e.test.sh
```

Observed default and opt-out guarantees:

```text
ok - real Herdr lab: an opted-out spawn retains the Stage 1 Herdr command sequence with zero ordering calls
ok - real Herdr lab: a home that configured nothing is projected by default
ok - real Herdr lab: the primary presentation setting inherits into real secondmate homes
ok - real Herdr lab validation completed on Herdr 0.8.0 with the default-session tripwire intact
```

The projected spawn in that run used the historical empty opt-in file, so a home that had already enabled the projection keeps it without any migration step.
One concurrent cross-home recovery case refused under contention on a loaded machine and passed on an immediate rerun; recovery-path presentation lock contention is a deliberate hard refusal rather than a flat fallback, which default-on now makes reachable from any Herdr home.
That run measured the default-on projection on Herdr 0.8.0 only, while the focus-flash regression below was last run on 0.7.5 before the flip, so neither run covered a defective release under default-on projection; the version floor and the focus-flash suite's Part C close that gap.

The restored-shell session-start cleanup ran on 2026-07-24 against Herdr 0.7.5 protocol 17:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-session-cleanup-e2e.test.sh
```

Observed guarantee: one exact home-local, journal-correlated, one-tab and one-pane childless idle shell was closed after restoration while the exact non-target focus and default fleet session remained unchanged, and a repeat run was a no-op.

### Workspace-removal focus safety

The focus-flash regression ran on 2026-08-05 against both Herdr 0.7.5 protocol 17 and Herdr 0.8.0 protocol 19 on macOS aarch64, with the 0.7.5 run using the pinned upstream release binary first on `PATH`:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-focus-flash-e2e.test.sh
```

Observed output on Herdr 0.7.5:

```text
ok - old path: the explicit last-pane close of a non-focused workspace stole focus (w3	w3:t1 -> w2	w2:t1)
ok - mitigation: every in-operation sample preserved exact focus while the doomed workspace was removed
ok - mitigation: no explicit close and no corrective focus were needed on the defective release
ok - fallback: a doomed pane holding a persistent child exhausts the proof and takes the plain explicit close
ok - fallback on a defective release: a bounded wrong-focus window of 4 samples was fully restored to the anchor
ok - version floor: herdr 0.7.5 protocol 17 remains conservatively below the floor with steal_live=1
ok - version floor: an unconfigured home falls back flat on herdr 0.7.5 and the explicit opt-in still projects
evidence: herdr=0.7.5 protocol=17 steal_live=1 floor_verdict=1 default-session-tripwire=armed
```

Observed output on Herdr 0.8.0:

```text
ok - old path note: this Herdr release preserves focus across the explicit close; continuing with outcome-only assertions
ok - mitigation: every in-operation sample preserved exact focus while the doomed workspace was removed
ok - fallback: a doomed pane holding a persistent child exhausts the proof and takes the plain explicit close
ok - fallback on a focus-preserving release: the plain explicit close preserved exact focus throughout
ok - version floor: herdr 0.8.0 protocol 19 is at or above the floor and preserves focus
ok - version floor: an unconfigured home stays projected on herdr 0.8.0 and the explicit opt-in agrees
evidence: herdr=0.8.0 protocol=19 steal_live=0 floor_verdict=0 default-session-tripwire=armed
```

The same guarded named-lab command passed on 2026-09-03 against Herdr 0.8.2 when this regression joined the then-required `real-herdr-gated` lane; that pre-0.9.0 result is retained as historical fallback evidence.
It reported `steal_live=0 floor_verdict=0 default-session-tripwire=armed`, with the fleet's default session unchanged before and after.

Part C is the case the suite could not reach before: a doomed pane whose shell holds a persistent background child fails the lone-idle-shell proof on every sample, so the plan takes the plain explicit close, in the geometry where the closing workspace's right neighbour is a spacer rather than the focused anchor.
On 0.7.5 that fallback exposed a bounded four-sample wrong-focus window and restored the anchor exactly; on 0.8.0 the same fallback exposed none, which is why default-on projection is floored at 0.8.0 rather than mitigated further below it.
The suite also cross-checks its own Part A measurement against the floor classifier on whatever release it runs, so a drifted protocol-to-release mapping fails there rather than silently gating on the wrong thing.

### Attached foreground viewer

A pseudo-terminal registers as a Herdr foreground client only when its window grid is non-zero.
`script` and a bare `pty.fork()` from a non-tty parent both start at 0x0, which is why PR #4131 could validate only the detached half of the teardown focus guard and left its four attached-client scenarios untested.
The guarded `viewer start` path fixes the pty at the proven 40-row by 120-column grid, sets that size on the master fd before the fork, and scrubs inherited `HERDR_*` variables, which makes the attached scenarios reachable from a headless runner.

Measured on 2026-09-11 against Herdr 0.9.0 protocol 22 on macOS 26.5.2 aarch64 with Python 3.14.6:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-attached-viewer-live-e2e.test.sh
```

```text
ok - attached viewer: a pty sized before the fork registers as a real Herdr foreground client
ok - attached viewer: a live client on the target tab refuses the close and keeps the pane
ok - attached viewer: focus moving onto the target between planning and mutation still blocks the close
ok - attached viewer: a close preserves the fresh non-target focus the viewer moved to
ok - attached viewer: the projection seeded-tab prune refuses while a live client watches it
ok - attached viewer: detaching releases the refusal, so the guard tracks the client and not the pointer
```

Both halves of the recipe are load-bearing, and each was measured by removing it from the helper and re-running the guard on the same host and release.
Dropping the `TIOCSWINSZ` call and dropping the environment scrub each left startup reporting `no_foreground_client`, followed by the guard failure:

```text
not ok - could not attach a real foreground Herdr viewer over a sized pty
```

Re-run this guard after every Herdr upgrade.
A release that changed the foreground-client contract, the window-grid requirement, or the nested-viewer refusal would fail here first, and the detached regressions would keep passing while saying nothing about it.

### Presentation version floor

Default-on presentation projection is floored at Herdr 0.8.0.
The floor's structural signal is the selected running server's protocol number, falling back to the client protocol only when that selected session positively reports no running server, and the release mapping was measured on 2026-08-05 by running each pinned upstream macOS aarch64 release asset's own `status --json` through the guarded lab helper:

| Release | Reported version | Protocol | Carries both upstream focus fixes | Floor verdict |
|---|---|---|---|---|
| v0.7.3 | 0.7.3 | 16 | no | below |
| v0.7.4 | 0.7.4 | 16 | no | below |
| v0.7.5 | 0.7.5 | 17 | no | below |
| preview-2026-07-21-0f10e1453a7f | 0.7.5-preview.2026-07-21-0f10e1453a7f | 17 | no | below |
| preview-2026-07-29-44b3adb12552 | 0.7.5-preview.2026-07-29-44b3adb12552 | 18 | yes | below |
| preview-2026-08-04-d78e3d3b5126 | 0.8.0-preview.2026-08-04-d78e3d3b5126 | 19 | yes | above |
| v0.8.0 | 0.8.0 | 19 | yes | above |

No build lacking both fixes reaches protocol 19, and every pre-fix build tops out at 17, so protocol 19 is a safe structural expression of the 0.8.0 floor.
The one post-fix build below it is a preview that still reports a 0.7.5 version, so it is conservatively treated as below the floor, which costs a preview build its projection and never lets an unfixed build through.
The 2026-08-05 named-lab cross-version probe started a server from Herdr 0.7.5 and queried it with the installed 0.8.0 client; status reported client version 0.8.0 protocol 19, server version 0.7.5 protocol 17, server running true, and server compatible false.
That ordinary post-upgrade shape proves the running server owns the focus behavior, so the unconfigured default composes client and selected-server verdicts conservatively and rechecks after server ensure before publishing a journal or creating a workspace.

Refresh this table with the opt-in guard, which re-downloads the pinned assets, verifies their digests, and fails naming any release whose reported version, protocol, or verdict has moved:

```sh
FM_HERDR_VERSION_FLOOR_LIVE_E2E=1 tests/fm-herdr-version-floor-live-e2e.test.sh
```

The classifier itself, the config preference it composes with, and the one-warning-per-release behavior are pinned portably with no Herdr installed:

```sh
tests/fm-backend-herdr.test.sh
```

Observed guarantees: every measured release classifies as the table records; either the protocol or the version signal alone carries an at-or-above verdict, and each divergent pair flips once the carrying signal is removed; client and running selected-session server verdicts compose conservatively, an unreadable server-running state and losing both release signals report indeterminate and fall back flat, the default is rechecked after server ensure before projection publication, an unconfigured home is projected only at or above the floor, an explicit `on`, including the historical empty opt-in file, is honored below it, and the below-floor warning is emitted once per home per detected release rather than once per spawn.

The pre-0.9.0 real-Herdr lane was run on 2026-08-05 against both the then-CI-pinned Herdr 0.7.4 protocol 16, which is below the floor, and Herdr 0.8.0 protocol 19, which is at the presentation floor:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh bin/fm-test-run.sh --lane real-herdr-gated
```

Both runs reported `family=real-herdr-gated count=11 failed=0`.
The projection suite's unconfigured-home case is release-aware rather than pinned to one outcome, so it proves the projected default on 0.8.0 and the flat fallback with its naming warning on 0.7.4:

```text
ok - real Herdr lab: a home that configured nothing is projected by default on herdr 0.8.0
ok - real Herdr lab: a home that configured nothing falls back flat on below-floor herdr 0.7.4 with one naming warning
```

Every other case in that suite uses an explicit opt-in or opt-out, so the floor leaves them unchanged on both releases.

Direct lab probes on 2026-07-28 established the removal rules the emptying-close plan relies on, each verified with `workspace list` focus reads around one mutation in a guarded `fm-lab-` session:

- An explicit `pane close` that emptied a non-focused workspace moved focus off the focused workspace in both before-focus and after-focus geometries.
- Ending a workspace's lone shell preserved the focused workspace exactly when the dying workspace sat behind it or the focused workspace was last, and moved focus to the focused workspace's right neighbor otherwise.
- The production focus-preserving close in the dangerous geometry repositioned the doomed workspace, ended its proved shell, and left every concurrent focus sample on the exact anchor with no corrective `tab focus` issued.

Two real-hardware conditions were required for the pane-death path to engage and are now encoded in the adapter and its unit fixtures: BSD `ps` reports a login shell's `comm` as `-zsh`, and an idle shell transiently hosts a prompt helper (starship) as a second foreground process immediately after a `workspace.move` relayout, which the bounded settle window absorbs.

The rules match the v0.7.5 tag source (`close_selected_workspace` reassigns focus from the closing workspace's index; `handle_pane_died` only clamps the stale focused index), and the upstream default branch resolves both paths by workspace id (PR #1877, commit `165dca45`, for the explicit close; PR #1912, commit `a979916`, for pane death), so the plan degrades to a harmless reorder-then-remove once a release carries them.

The full projection and restored-shell suites were re-run on 2026-07-28 on Herdr 0.7.5 with the updated close path; the presentation suite completed with `real Herdr lab validation completed on Herdr 0.7.5 with the default-session tripwire intact`, and the restored-shell cleanup guarantee above was unchanged.

The teardown-level record-retention gate was verified on 2026-07-28 with metadata fixtures and a live contending lock holder:

```sh
tests/fm-teardown.test.sh
tests/fm-backend-herdr.test.sh
```

Observed guarantees: a contended presentation lock refused the teardown before the isolated copy was returned, with the task branch, every durable record, and the endpoint intact and no pane close attempted; the retry after the contention cleared returned the copy, closed the pane under the lock, and removed the records; an unknown structured-presence result after an attempted projected close retained the journal and every record with a nonzero exit; and every presence-gate mode accepted only a structured not-found as gone.

The same fixtures verified three further boundaries on 2026-07-29: missing or malformed endpoint identity and an unparseable pane presence refused record removal with everything retained; the SIGKILL escalation re-read the exact pane's process information and refused to signal when a different shell pid owned the pane, falling back to the plain close with the original process untouched; and a reposition whose removal then failed on every path restored the exact original workspace order through a second verified move and reported the close as failed.

The teardown fixture was re-run on 2026-07-31 after extending the same fail-closed boundary through forced secondmate cleanup, including recursive cleanup of a nested secondmate whose Herdr grandchild close remains unconfirmed.

Observed output:

```text
ok - forced secondmate teardown preflights every Herdr child before cleanup mutation
ok - forced secondmate teardown retains Herdr child identity until exact pane disappearance
ok - forced teardown retains a nested secondmate home and its grandchild's Herdr identity when the grandchild close is unconfirmed
```

### Composer and operational input

Real captures verified these active distinctions:

- Pi uses content between complete separator rows and requires exact native Pi identity.
- Dim or faint suggestion text is ghost content, while normally styled text is pending input.
- A bare shell prompt has no safe agent-composer container and is unknown.

`tests/fm-composer-ghost.test.sh`, `tests/fm-composer-lib.test.sh`, and the Herdr composer cases pin the exact captured ANSI bytes.
The required credential-safe real Pi regression now exercises the current durable transport rather than the retired typed-marker path.
It drives production spawn, send, interrupt, exit, relaunch, and cleanup wrappers; reads and acts on the exact numeric inbox record; moves it into `handled/`; verifies pending-reply correlation and the routed parent response; and proves direct terminal input stays unmarked.
The same script retains one tmux reference run:

```sh
tests/fm-pi-lifecycle-wrappers-live-e2e.test.sh
```

Observed 2026-09-18 on macOS aarch64 with Herdr 0.9.0 / protocol 22 and Pi 0.85.1:

```text
ok - real Pi/herdr: exact durable routing, handled acknowledgement, correlation, and routed response all hold
ok - real Pi/herdr: interrupt, exit, and relaunch wrappers preserve the endpoint lifecycle
ok - real Pi/herdr: direct terminal input stays unmarked
ok - real Pi/herdr: production cleanup completed
ok - real Pi/tmux: exact durable routing, handled acknowledgement, correlation, and routed response all hold
ok - credential-safe real Pi lifecycle parity covers Herdr and the tmux reference backend
```

### Native blocked event

The protocol-16 event path was measured on 2026-07-11 with Herdr 0.7.3 and Python 3.13:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-backend-herdr-eventwait-smoke.test.sh
```

Observed output:

```text
ok - real herdr: events.subscribe capability gate passes
ok - real herdr: a driven idle->blocked transition returns the blocked record in 0.129s
ok - real herdr: the watcher fast-path enqueues a stale wake naming the task window
```

Polling remained active and is covered as the fallback for capability, connect, subscribe, and repeated reader failure.

### Agent lifecycle control

Herdr is one of the two backends whose recovery-grade agent-state classifier the control plane may trust ([agent-control.md](../agent-control.md)), so its lifecycle gating is measured against the real binary; reverified 2026-08-08 on Herdr 0.8.0, and first measured 2026-08-02 on Herdr 0.7.5 with identical results:

```sh
tests/fm-control-herdr-smoke.test.sh
```

Observed output, refreshed 2026-09-10 on Herdr 0.9.0 after the stale-registration fix (the two stale-registration lines are recorded under "Stale agent registration" below):

```text
ok - real herdr: exit on a pane with no registered agent is idempotent success
ok - real herdr 0.9.0: a gone session reads recoverable while a live pane and a malformed target do not
ok - real herdr: a drifted agent-free shell returns to its worktree and reuses the same endpoint
ok - real herdr: interrupt refuses when herdr's own agent registry reports no agent
ok - real herdr: interrupt delivers Pi's key and proves the agent survived it
ok - real herdr: no control verb removed the endpoint or the task's local copy
ok - real herdr 0.9.0: a registration Herdr keeps after its agent exits reads stale-agent and recovers as dead
ok - real herdr: exit on a pane with a stale registration is idempotent success
ok - real herdr: a stale registration no longer blocks relaunch, and the endpoint and local copy survive
ok - real herdr: an agent that does not stop fails closed instead of being reported as stopped
```

The registry read through `herdr pane report-agent` is the same source `fm_backend_herdr_agent_state` classifies, and that registration counts as an agent only while `pane process-info` shows exact Pi process identity behind it, so the guard backs the registration with a deterministic test Pi process and then stops it, with no provider prompt submitted.
That command is the guard that refreshes this record; run it after every Herdr upgrade rather than trusting the version above.

For Pi on Herdr 0.9.0, `herdr agent get` reflects whether the agent process remains live; its registration does not persist merely because the pane and parent shell do.
A Pi launched as a child of the pane shell (not via `exec`) that then `/quit`s or is SIGKILL'd leaves the pane and shell in place, and `agent get` returns `agent_not_found`.
A sibling live idle Pi stays `agent=pi` with `agent_status=idle`.
`fm_backend_herdr_pane_agent_state` maps that `agent_not_found` leftover shell to `no-agent` and `fm_backend_herdr_agent_state` maps it to `dead` (relaunch-allowed), while the live idle pane stays `alive`.
`herdr pane get` `.agent_status` can still read `idle` after the occupant is gone; liveness is `agent get`, never that pane field.

```sh
tests/fm-backend-herdr-agent-exit-shell-e2e.test.sh
```

Refresh that live pair after every Herdr upgrade. Observed 2026-09-10 on Herdr 0.9.0 / protocol 22 with Pi 0.82.0 in an isolated `fm-lab-` session:

```text
ok - agent get distinguishes leftover-shell (dead/no-agent) from live idle Pi
ok - pane get agent_status lag cannot keep an exited occupant classified alive
```

### Endpoint recovery classification

Measured 2026-09-10 on macOS aarch64 against Herdr 0.9.0 (protocol 22) in an isolated `fm-lab-` session.

An endpoint recorded in a session whose server is not running cannot be read by any operational call, and `status` is the one command that answers with a body instead of refusing:

```sh
herdr pane get w1:p2 --session fm-lab-never-started
herdr status --json --session fm-lab-never-started | jq -c "{running: .server.running, status: .server.status}"
```

```text
{"id":"cli:pane:get","error":{"code":"server_not_running","message":"no herdr server is running at /Users/kunchen/.config/herdr/sessions/fm-lab-never-started/herdr.sock; run `herdr session attach fm-lab-never-started` to start or attach it"}}
{"running":false,"status":"not_running"}
```

`fm_backend_herdr_agent_state` therefore settles an uninterpretable pane read with `.server.running` rather than with the `server_not_running` error code, which keeps the verdict working across the supported range: the field is present on 0.8.2 protocol 20 and 0.9.0 protocol 22 alike (measured in "Client selection" above), while the code is not.
Only that recovery-grade read is widened; the husk classifier under it stays strict, because it licenses closing panes.
Observed in the lab, in one run:

```text
live agent-free pane                 dead
endpoint in a session with no server missing
malformed target                     unreadable
```

The same run drove `bin/fm-spawn.sh --relaunch` against a real Herdr pane whose shell had been moved outside its recorded worktree: the shell was told once to return, ended in the recorded worktree, and the replacement was launched into the SAME pane, leaving one task tab.

Herdr 0.8.x is not installed on this host, so protocol-20 coverage is structural plus the adapter fixture exercising both response shapes; it is not a live result.
Refresh the live half, which fails naming the installed version, with:

```sh
tests/fm-control-herdr-smoke.test.sh
```

Observed 2026-09-10:

```text
ok - real herdr 0.9.0: a gone session reads recoverable while a live pane and a malformed target do not
ok - real herdr: a drifted agent-free shell returns to its worktree and reuses the same endpoint
```

`tests/fm-backend-herdr.test.sh` pins the logic portably by driving the two signals apart - the same failed pane read yields `missing` under a stopped server and `unreadable` under a running one - and asserts that the husk classifier still refuses on that identical read.
`tests/fm-control-herdr-smoke.test.sh` proves the Herdr-only drift recovery against a real binary in an isolated lab session.
`tests/fm-control-relaunch.test.sh` drives a tmux stub and proves that tmux retains its prior refusal without sending `cd` or any other input to the pane.
The Herdr refusal when a shell accepts the command but does not move is not exercised in this change.

### Stale agent registration

Measured 2026-09-10 on macOS aarch64 against Herdr 0.9.0 (protocol 22) and Pi 0.85.1 in an isolated `fm-lab-` session (upstream issue #4115, duplicates #3639, #3487, #2908, #3545).

Herdr keeps a Pi registration after the Pi process has exited to a shell when a nested interactive shell sits under the pane's top shell, which is the crew shape `treehouse get` leaves behind; a plain `/quit` directly under the top shell, and a `kill -9` of Pi, both released it on this version.
Reproduced in the lab with a nested `zsh` under the pane shell, then `pi` with no prompt, then `/quit`:

```sh
herdr pane run w1:p1 zsh --session "$LAB"; herdr pane run w1:p1 pi --session "$LAB"
herdr agent get w1:p1 --session "$LAB" | jq -c '.result.agent | {agent, agent_status}'
herdr pane process-info --pane w1:p1 --session "$LAB" | jq -c '.result.process_info | {shell_pid, fg: .foreground_process_group_id, procs: [.foreground_processes[] | {pid, name, argv0}]}'
herdr pane send-text w1:p1 '/quit' --session "$LAB"; herdr pane send-keys w1:p1 Enter --session "$LAB"
herdr agent get w1:p1 --session "$LAB" | jq -c '.result.agent | {agent, agent_status}'
herdr pane process-info --pane w1:p1 --session "$LAB" | jq -c '.result.process_info | {shell_pid, fg: .foreground_process_group_id, procs: [.foreground_processes[] | {pid, name, argv0}]}'
```

```text
{"agent":"pi","agent_status":"idle"}
{"shell_pid":87754,"fg":35952,"procs":[{"pid":35952,"name":"node","argv0":"pi"}]}
{"agent":"pi","agent_status":"idle"}
{"shell_pid":87754,"fg":35834,"procs":[{"pid":35834,"name":"zsh","argv0":"zsh"}]}
```

Before the fix `fm_backend_agent_state herdr` read that second state as `alive`, so `bin/fm-control.sh <id> relaunch` and `bin/fm-spawn.sh --relaunch` were refused for as long as the registration lived, which is hours.
The registration is still present after the wait, and Herdr's own `pane report-agent` leaves the same shape behind on any pane, which is what the lifecycle-control guard uses.

Two vendor facts the fix rests on, both read from the outputs above and from `fm_backend_herdr_pane_process_state`'s `pane process-info` parse:

- Pi's process presents with kernel name `node` and argv0 `pi` (its foreground group also carries Pi's child `node` helpers with argv0 such as `npm view ... version`), so a running Pi is attributed by argv[0] exactly as the tmux probe attributes it; a renamed symlink to `sleep` presents as name `sleep` with the symlink name in argv0.
- Herdr creates the record with its own placeholder `agent_status` of `unknown` the moment it notices Pi, before Pi's extension reports `idle`; that transient reads `unknown` in the pane classifier as it always did, and only a lifecycle status is subject to the process-level proof.

Subcommand presence below the 0.9.0 measurement, checked 2026-09-10 on macOS aarch64 against the pinned upstream release clients fetched from `https://github.com/ogulcancelik/herdr/releases/download/v<version>/herdr-macos-aarch64`:

| Release | sha256 |
|---------|--------|
| 0.7.1 | `16f4653f0491ea1e7d2b46b5b02542f18e1b82e88daaf9e2900572e5bb634df8` |
| 0.7.3 | `b31345392d004ec1f1b2c821e1ad601019fa8385fe1e4c6931321eb58a920773` |
| 0.7.4 | `24992e1625dbdcb18354a59e299e4b263c312400b31396cdc07cd46ed57f24a7` |
| 0.7.5 | `37350546b0012555943b92eaf962665de4e264395baeb44227b8015e8ff5b0d6` |

The command run against each client was `<client> pane --help`, which is client-side, session-independent, and opens no socket, and each printed the line:

```text
process-info  Show pane process information
```

This proves subcommand presence in the client only, not the server response shape, which is measured only on 0.9.0 above.

The live guard that refreshes this record runs by default wherever Herdr and Pi are installed, spends no model token, and fails naming both versions:

```sh
tests/fm-herdr-pi-stale-registration-live-e2e.test.sh
```

Observed 2026-09-10:

```text
# pi 0.85.1 under herdr 0.9.0: registered idle, foreground [{"name":"node","argv0":"node"},{"name":"node","argv0":"node"},{"name":"node","argv0":"rpiv-ask-user-question version"},{"name":"node","argv0":"npm view gentle-engram version"},{"name":"node","argv0":"pi"}]
ok - real herdr 0.9.0 + pi 0.85.1: a running registered pi classifies alive at process level
# herdr 0.9.0 kept the pi registration (idle) after /quit under a nested shell: the stale-registration branch is exercised
ok - real herdr 0.9.0 + pi 0.85.1: the registration left behind by a quit pi reads stale-agent and recovers as dead
```

`tests/fm-control-herdr-smoke.test.sh` proves the same shape through the control plane without a provider prompt (the two `stale` lines under "Agent lifecycle control" above): a registration over a deterministic Pi process reads `alive`, stopping that process makes the pane read `stale-agent` and recover as `dead` while `agent get` still reports the record, `exit` then reports `already-stopped`, and `--relaunch` reuses the same endpoint with the local copy intact.
`tests/fm-backend-herdr.test.sh` pins the logic portably with canned `process-info` bodies over real processes, driving the signals apart: the identical shell-only foreground reads `stale-agent` for a childless shell and `live` when an agent-named process is still a descendant of that shell, a `working`, `done`, or `blocked` record over a shell-only pane reads the same as `idle`, an unreadable process view reads `unknown` and refuses husk closing, a transient prompt helper beside the shell settles into `stale-agent` on the next shell-only sample while a foreground that never settles within the bound still reads `live`, and `busy_state` verifies a `working` record before reporting busy.
`tests/fm-crew-state.test.sh` pins the recovery classifier: a stale registration over a shell-only pane reports agent gone rather than alive or unreachable, and a stale `working` record never reports the pane working.
A stale-registration pane is never a husk: create, reclaim, presentation recovery, and session cleanup keep refusing it, and only recovery reuses it.

### Away posture

The away posture is the record `bin/fm-afk-contract.sh` owns; Pi's ordinary supervision cycle remains active.
`tests/fm-afk-launch.test.sh` pins that away confirmation and quiet entry create posture records only, expose no secondary-process lifecycle command, and leave ordinary Pi supervision active.
`tests/fm-afk-return.test.sh` pins the catch-up reporting boundary: Bearings continues through pending return catch-up, projects its posture as an action-free warning outside Captain's Call, and drops that warning after the gate clears, while an active away window still refuses.
`tests/fm-turnend-guard.test.sh`, `tests/fm-session-start.test.sh`, and `tests/fm-supervision-instructions.test.sh` prove that away and quiet posture keep the ordinary Pi watcher requirement and repair path.

## Pi supervision branch

The supervision-branch extension (`.pi/extensions/fm-branch-supervision.ts`, [docs/pi-supervision-branch.md](../pi-supervision-branch.md)) builds its second session through the Pi SDK surface: `createAgentSession` (including its `model`, `modelRuntime`, and `thinkingLevel` options), `DefaultResourceLoader` with `extensionFactories`, `SessionManager`, `createBashToolDefinition` with a `spawnHook`, `sendCustomMessage` for routine notes, `appendEntry` and `registerEntryRenderer` for captain outcomes, the `before_provider_request` hook, the command context's model registry for picker candidates, a fresh `ModelRuntime` for isolated-branch resolution, and Pi's own `getSupportedThinkingLevels`/`clampThinkingLevel` plus its `getThinkingLevel` and `thinking_level_select` extension surface for effort.
In TUI mode, its `/supervision-model` model list is drawn with Pi's own `SelectList`, `Input`, `fuzzyFilter`, and `DynamicBorder` through the extension context's `ui.custom` surface, which is what bounds and searches a long catalog.

Evidence produced 2026-08-25 on macOS 26.5.2 arm64, Node v24.13.1:

- Historical real-SDK guard: `FM_PI_BRANCH_LIVE_E2E=1 bin/fm-test-run.sh tests/fm-pi-branch-live-e2e.test.sh` against the globally installed `@earendil-works/pi-coding-agent` 0.81.1 printed `ok - real Pi SDK 0.81.1 accepts the branch session construction and preserves an unpromptable wake`.
  The guard read no credentials and made no provider call: an isolated empty `PI_CODING_AGENT_DIR` left model resolution empty, so the branch's first prompt failed fast and exercised the former direct-branch fallback.
  That fallback probe predates watcher-owned settlement and is not current evidence for the replacement-safe delivery boundary.
  The same run confirms that a real `ModelRegistry` over that empty agent dir still exposes the picker-facing availability surface, then pins `openai/no-such-live-model` and proves that the branch's own `ModelRuntime` refuses the unresolvable pin instead of silently running supervision on main's model.
- Model-pin precedence: the same guard run printed `ok - real Pi SDK 0.81.1 applies an explicit branch model on create and over a reopened session's recorded model`.
  It declares a local `fm-live-fake` provider in an isolated `models.json`, never contacts it, and proves through `session.model` that an explicit model is applied on create, still wins over the model a reopened session recorded, and is absent-pin-restorable - the SDK behavior needed when a model or effort change reopens the current main session's branch conversation.
- Effort-pin vendor contract: the same guard run printed `ok - real Pi SDK 0.81.1 reports its own supported effort levels and applies an explicit branch effort over a reopened session's recorded level`.
  Over its own local never-contacted provider it confirms that `getSupportedThinkingLevels` still returns `["off","minimal","low","medium","high","xhigh","max"]` for a model mapping every extended level, narrows to `["off","minimal","low","medium","high"]` for a reasoning model mapping none, returns `["off"]` for a non-reasoning model, and that `clampThinkingLevel` lowers `max` to `high` on the narrow model while collapsing an unrecognized token to `off` - which is why the extension rejects an unrecognized pin before that clamp can see it.
  It then proves through `session.thinkingLevel` that an explicit effort is applied on create, that a reopened session with no override restores its own recorded level, that an explicit effort beats that recorded level, and that an over-ceiling effort is clamped rather than refused.
  The recorded-level cases need a session file Pi will actually restore from, and Pi flushes one only once an assistant message exists, so the guard appends the level change and that message through the real `SessionManager` rather than hand-writing the format.
- Picker primitives: on 2026-08-26, after the final portable-shell and sentinel fixes, `bin/fm-test-run.sh tests/fm-pi-branch-extension.test.sh` again printed `ok - the installed Pi still bounds the picker's list and ranks its search` against the same installed 0.81.1 package.
  That case imports the real `SelectList`, `Input`, `fuzzyFilter`, and `DynamicBorder`, renders a 42-row catalog through the real `SelectList` at the visible bound the extension asks for, and fails naming the installed version if Pi stops exporting a primitive or stops bounding what it renders; it skips when no npm package is installed, and the portable stubbed cases in the same file hold the ordering, search, and branch-only-pin behavior everywhere.
- Strict typecheck: `tests/fm-pi-primary-types.test.sh` printed `ok - tracked Pi extensions pass strict no-emit typecheck against Pi 0.81.1` with the branch extension and its imported libraries included.
  This typecheck is also the enforcement for the extension's declared effort vocabulary: its bidirectional assertion against Pi's own `getThinkingLevel` return type fails the moment Pi adds or removes a thinking level, so the runtime list used to reject an unrecognized hand-edited pin cannot drift into a stale Firstmate catalog.
- Historical custom-message provider conversion: on 2026-08-26, `FM_PI_BRANCH_LIVE_E2E=1 bin/fm-test-run.sh tests/fm-pi-branch-live-e2e.test.sh` against installed `@earendil-works/pi-coding-agent` 0.84.1 printed `ok - real Pi SDK 0.84.1 delivers a custom message to the provider as user text carrying only content, so the captain outcome's typed envelope is what reaches the model`.
  The guard passes a typed captain outcome and a plain rendered routine note through Pi's exported `convertToLlm`, proves that `customType` and `display` are not model-visible identity, and classifies the resulting provider text with `bin/fm-operational-input.sh`.
  This evidence explains the superseded model-relay path but is no longer the captain-delivery contract.

### 2026-08-28 Pi 0.84.4 SDK compatibility refresh

The credential-free live guard and strict typecheck were rerun against the installed `@earendil-works/pi-coding-agent` 0.84.4 package after the Pi primary compatibility repair.
The live guard used an isolated empty `PI_CODING_AGENT_DIR`, inspected no credentials, and made no provider call.

```sh
npm exec --yes --package=typescript@5.9.3 -- bash tests/fm-pi-primary-types.test.sh
FM_PI_BRANCH_LIVE_E2E=1 bin/fm-test-run.sh tests/fm-pi-branch-live-e2e.test.sh
```

```text
ok - tracked Pi extensions pass strict no-emit typecheck against Pi 0.84.4
ok - real Pi SDK 0.84.4 accepts the branch session construction and preserves an unpromptable wake
ok - real Pi SDK 0.84.4 applies an explicit branch model on create and over a reopened session's recorded model
ok - real Pi SDK 0.84.4 reports its own supported effort levels and applies an explicit branch effort over a reopened session's recorded level
ok - real Pi SDK 0.84.4 delivers a custom message to the provider as user text carrying only content, so the captain outcome's typed envelope is what reaches the model
FM_TEST_END 2026-08-29T01:01:01Z tests/fm-pi-branch-live-e2e.test.sh exit=0 duration_ms=2520 gate_skip=false
```

The focused extension suite also exercised the installed Pi 0.84.4 picker and outcome-renderer consumers; [`calm-mode-feasibility.md`](../calm-mode-feasibility.md#2026-08-28-pi-0844-outcome-renderer-compatibility-verification) owns the version-scoped renderer evidence.

### 2026-08-29 deterministic captain-outcome delivery

The credential-free live guard, focused extension suite, store suite, and strict typecheck were run against the locally installed `@earendil-works/pi-coding-agent` 0.84.3 package.
No model was selected or prompted, no provider call was made, and the active Pi session was not changed.

```sh
bin/fm-test-run.sh tests/fm-pi-branch-extension.test.sh
bin/fm-test-run.sh tests/fm-branch-supervision.test.sh
npm exec --yes --package=typescript@5.9.3 -- bash tests/fm-pi-primary-types.test.sh
FM_PI_BRANCH_LIVE_E2E=1 bin/fm-test-run.sh tests/fm-pi-branch-live-e2e.test.sh
```

```text
ok - captain outcomes are exact and exactly once across crash, reload, busy main, compaction, and an unrelated assistant response
ok - startup replay cannot advance the cursor across an unrendered captain outcome
ok - tracked Pi extensions pass strict no-emit typecheck against Pi 0.84.3
ok - real Pi SDK 0.84.3 immediately renders appendEntry in the active transcript, persists it across reopen, and excludes it from model context
```

The live probe loads the extension through Pi's real resource loader and AgentSession, subscribes a stock InteractiveMode, verifies `ExtensionAPI.appendEntry` synchronously inserts the exact registered custom row into its active chat once, reopens the resulting session file to verify exact structured data, and verifies the entry is absent from `buildSessionContext().messages`.
The focused regression recreates the incident topology with stale compaction framing and an immediately preceding unrelated assistant response, then covers idle and busy delivery, cold startup with late fleet-lock acquisition, the crash boundary after entry persistence but before cursor advancement, and repeated reload without duplication.

### 2026-09-01 sequence-keyed captain-outcome processing

The focused extension suite, store suite, strict typecheck, and credential-free live guard were run against a locally installed `@earendil-works/pi-coding-agent` 0.84.4 package selected with `FM_PI_PACKAGE_DIR`, on macOS 26.5.0 arm64, Node v24.13.1.
No model was selected or prompted, no provider call was made, and the active Pi session was not changed.

```sh
FM_PI_PACKAGE_DIR=<pi-0.84.4 package> bin/fm-test-run.sh tests/fm-pi-branch-extension.test.sh
bin/fm-test-run.sh tests/fm-branch-supervision.test.sh
FM_PI_PACKAGE_DIR=<pi-0.84.4 package> npm exec --yes --package=typescript@5.9.3 -- bash tests/fm-pi-primary-types.test.sh
FM_PI_BRANCH_LIVE_E2E=1 FM_PI_PACKAGE_DIR=<pi-0.84.4 package> bin/fm-test-run.sh tests/fm-pi-branch-live-e2e.test.sh
```

```text
ok - a captain outcome reaches main's model as one typed, sequence-keyed processing request while routine notes stay plain
ok - a captain outcome opens one sequence-keyed processing turn, survives empty and unrelated answers, is re-presented at run end and session start, and closes only on its acknowledgement
ok - the processed marker is sequence-bound, never ahead of the read cursor, never backwards, and migrates delivered history once
ok - tracked Pi extensions pass strict no-emit typecheck against Pi 0.84.4
ok - real Pi SDK 0.84.4 immediately renders appendEntry in the active transcript, persists it across reopen, and excludes it from model context
```

The focused regression recreates the two 2026-08-31 incident shapes against the real store scripts: a delivered decision outcome whose processing turn returns an empty assistant message, and one whose turn repeats an unrelated prior answer.
In both, the processed marker holds, the same sequence is presented again at the run boundary and after a session replacement, the triggered-turn budget gives way to a next-prompt copy without duplicates, and only `fm_branch_processed` with the presented sequence closes the outcome; a routine outcome never enters the path, and delivered history from before the marker existed is migrated once rather than re-presented.
On this machine the globally installed npm package is 0.81.1, whose stock `ToolExecutionComponent` rendering differs from the 0.84 line and fails the suite's first rendering-consumer case before any delivery case runs, which is why `FM_PI_PACKAGE_DIR` points at the 0.84.4 install above.

### 2026-09-02 historical post-construction provider-error fallback

The focused extension suite, strict typecheck, and real-SDK guard were run against the npm `@earendil-works/pi-coding-agent` 0.84.4 package on macOS 26.5.0 arm64, Node v24.13.1, before fallback ownership moved from the branch extension to the watcher.
The real-SDK case configured an isolated local OpenAI-compatible model, intercepted its only `fetch` in-process with the incident's non-retryable 429 `Monthly usage limit reached` response, read no user credential, and allowed no external provider request.
It proved that Pi persisted an assistant message with `stopReason: "error"` and resolved the constructed branch prompt normally, after which the extension released the claimed-row grant, retained the durable queue row, and returned the exact wake to main as a follow-up.

```sh
FM_PI_PACKAGE_DIR="$HOME/.npm/_npx/1f276a68aabfc75c/node_modules/@earendil-works/pi-coding-agent" bash tests/fm-pi-branch-extension.test.sh
FM_PI_PACKAGE_DIR="$HOME/.npm/_npx/1f276a68aabfc75c/node_modules/@earendil-works/pi-coding-agent" bash tests/fm-pi-primary-types.test.sh
FM_PI_BRANCH_LIVE_E2E=1 FM_PI_PACKAGE_DIR="$HOME/.npm/_npx/1f276a68aabfc75c/node_modules/@earendil-works/pi-coding-agent" bash tests/fm-pi-branch-live-e2e.test.sh
```

```text
ok - a settled branch turn without a durable outcome falls back and releases its grant for main replay
ok - post-construction provider errors fall back immediately and repeated failures defer later wakes directly to main
ok - tracked Pi extensions pass strict no-emit typecheck against Pi 0.84.4
ok - real Pi SDK 0.84.4 returns a post-construction 429 wake to main without losing its durable row
```

The current portable regression proves that only consecutive provider errors count toward the two-error broken-branch latch: a durable report between errors resets the streak, the error that reaches the threshold rejects to watcher-owned fallback, and the next wake remains on main without another branch prompt.
`tests/fm-pi-watch-extension.test.sh` owns the provider-free integration evidence that watcher fallback remains pending until Pi accepts the main follow-up or the branch settles successfully, and that a follow-up accepted while main is streaming neither stalls the successor chain nor escapes replacement replay until Pi consumes it.
[`pi-supervision-branch.md`](../pi-supervision-branch.md) owns the current cooldown, recovery, and re-latch contract and points to the regression that now covers it.

The extension executes inside the installed Pi CLI's own runtime, so a CLI upgrade can drift ahead of the pinned npm surface; refresh the SDK construction, picker, renderer, and type evidence after every Pi upgrade by rerunning the applicable live guard probes, picker regression, and strict typecheck above (point `FM_PI_PACKAGE_DIR` at a matching npm install when one exists).
The live guard now drives both extensions through the watcher-owned settlement handshake, requires rejected branch settlement before main delivery, and verifies successor-delivery confirmation; rerun it against the matching importable Pi package to refresh end-to-end fallback evidence.

### 2026-09-02 streaming-time watcher delivery

The focused watcher suite, strict typecheck, and credential-free live guard were run against the npm `@earendil-works/pi-coding-agent` 0.84.4 package selected with `FM_PI_PACKAGE_DIR`, on macOS 26.6.2 arm64, Node v24.14.1, after the watcher extension stopped waiting for `before_agent_start` before settling a main delivery.
No credential was read, no request left the machine, and the active Pi session was not changed.

```sh
bin/fm-test-run.sh tests/fm-pi-watch-extension.test.sh
FM_PI_PACKAGE_DIR=<pi-0.84.4 package> npm exec --yes --package=typescript@5.9.3 -- bash tests/fm-pi-primary-types.test.sh
FM_PI_BRANCH_LIVE_E2E=1 FM_PI_PACKAGE_DIR=<pi-0.84.4 package> bin/fm-test-run.sh tests/fm-pi-branch-live-e2e.test.sh
```

```text
ok - Pi hung successor falls back to one typed actionable wake
ok - Pi streaming-time wake delivery keeps the successor chain and replays only unconsumed wakes
ok - Pi retries a verified successor that failed during wake delivery once that delivery settles
ok - tracked Pi extensions pass strict no-emit typecheck against Pi 0.84.4
ok - real Pi SDK 0.84.4 queues a streaming-time watcher wake without before_agent_start, keeps the successor chain, and surfaces consumption of both follow-ups
```

The live probe loads the tracked watcher extension through Pi's real resource loader into a real AgentSession whose only provider is a local fake with its fetch intercepted in-process and held open mid-stream.
It proved that a follow-up the extension sends while main is streaming raises no `before_agent_start` at queue time or when the run reaches it, joins the run as a user `message_start` carrying the exact wake text in its own model turn, and is followed by a verified successor and delivery of the next close; a follow-up sent to the idle main raises `before_agent_start` with the exact text before its user `message_start`.
The portable regression drives the same shape with a fake main that never raises `before_agent_start` while streaming, then proves a replacement replays only the follow-up Pi had not consumed and that an exhausted restoration delivers its typed failure without launching a further arm.
A second regression holds a branch settlement open while the verified successor exits with a failure, and proves that failure takes the ordinary bounded retry once the delivery settles rather than leaving the generation with no watcher and no retry.

## Native Codex through Pi

Verified on 2026-09-08 with Pi 0.85.1 and the installed `pi-codex-native` 0.2.1 adapter.
Run this token-free guard after updating Pi, Codex, or the adapter:

```sh
FM_PI_CODEX_NATIVE_LIVE=1 bash tests/fm-pi-codex-native.test.sh
```

Observed result: `"result": "PASS"`.
The guard runs the real Pi runtime, native adapter, three FirstMate primary extensions, native MCP transport, and FirstMate's durable outcome scripts in an isolated home.
It verifies native `ultra` on initial and operational turns and after restart, startup operational input, watcher arming, a notification while main is idle, outcome read and one acknowledgement, refusal of a duplicate acknowledgement, and no reprocessing after restart.
Its native App Server peer and watcher-close process are deterministic fixtures; it does not claim a real backend or a live model was tested by that command.
`tests/fm-busy-state.test.sh`, `tests/fm-busy-adapter-wiring.test.sh`, and `tests/fm-watch-triage.test.sh` cover separate progress notification, unchanged semantic busy state, rejection of a superseded worker's events, and progress refreshing the busy-age bound without fabricating a completed turn.
