# Runtime backend verification

Audience: maintainer verification.

This record contains reusable version-scoped evidence for active runtime guarantees.
The backend guides own current setup, safety boundaries, and limitations.
Exact task chronology, branch names, temporary homes, local paths, process ids, thread ids, and delivery transcripts remain in private reports or PR evidence.

## tmux

Foreground-process behavior was verified on 2026-07-07 with tmux 3.6a on macOS.

```sh
tmux new-session -d -s fmtest -n testwin
tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
tmux send-keys -t fmtest:testwin 'sleep 30' Enter
tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
tmux send-keys -t fmtest:testwin C-c
tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
```

Observed output:

```text
zsh
sleep
zsh
```

A persistent parent shell waiting for a child remained reported as the parent process, while a shell that directly execed a simple command changed identity with the process itself.

### Agent liveness name sources

The earlier assumption that `#{pane_current_command}` always preserves executable identity no longer holds.
That reading can reflect a rewritable process title, so it is one of two independent name sources rather than the sole basis of a verdict.

Vanilla Pi 0.84.1 was verified on 2026-08-16 with tmux 3.6a on macOS arm64 through the live drift guard.

```sh
FM_HARNESS_LIVENESS_DRIFT=1 bin/fm-test-run.sh tests/fm-harness-liveness-drift-live-e2e.test.sh
```

Observed bounded output:

```text
# pi 0.84.1: title='node' foreground=[pi ]
ok - harness liveness: pi 0.84.1 classifies alive
# checked 1 installed harness(es)
```

`#{pane_current_command}` and foreground `ps -o comm=` read different name fields, but which one preserves executable identity is platform-dependent.
The portable Linux regression observes the reverse role assignment for a version-named native executable, with the identifying path retained in argv[0].
The classifier therefore accepts the exact Pi basename first, then an exact Pi path component in the full executable path, then the same component in argv[0], without depending on which field carries it on a given platform.
Exact `pi` and `Pi` process evidence remains accepted for vanilla Pi, while similar or prefixed helpers are rejected.

The portable regression is CI-enforced, while the real-harness drift guard is opt-in under the policy in `.agents/skills/firstmate-coding-guidelines/SKILL.md`.
Run the live guard after any Pi upgrade and update the version and bounded output above.

Backend applicability was reviewed across every spawn adapter.
Tmux uses exact Pi process evidence for recovery-grade liveness.
Herdr uses native registered-agent state and needs no process-name branch.

The current classifier matrix and its refresh guard are recorded in [Composer classification matrix](#composer-classification-matrix), with portable shape coverage in `tests/fm-composer-lib.test.sh` and `tests/fm-composer-ghost.test.sh`.

### Cleanup endpoint identity

The cleanup identity boundary was validated on 2026-07-28 with tmux 3.6a and metadata fixtures for every supported backend.

```sh
tests/fm-teardown-endpoint-safety.test.sh
tests/fm-teardown.test.sh
tests/fm-backend-herdr.test.sh
```

Bounded output from the incident regression:

```text
ok - fm-teardown: missing, empty, malformed, ambiguous, and task-mismatched endpoints refuse before every mutation or runtime call
ok - cleanup identity: valid tmux and Herdr records validate while every empty backend target refuses
ok - tmux backend: direct empty target returns nonzero without invoking tmux
ok - process cleanup: creation-time PID identity removes only the exact child and preserves the control child
ok - fm-teardown: dedicated-socket invalid cleanup preserves target/control and valid cleanup removes only the exact target
```

The dedicated tmux cell removed ambient tmux variables, required a socket-bound wrapper, kept one target and one independent control window, and proved the wrapper was not called for invalid metadata or a direct empty target.
Valid cleanup removed only the exact task-bound target and left the control window live.
The metadata-only validation covers tmux and Herdr before backend dispatch.
Pi shares that backend cleanup boundary; its harness-specific hook files are cleaned only after it, so the harness needs no separate endpoint parser.

## Composer classification matrix

The shared composer classifier (`bin/fm-composer-lib.sh`, `fm_composer_classify_screen`) owns every composer shape fleet-wide; each backend contributes only a capture and a capability descriptor.
The live half of that guarantee was verified on 2026-08-10 from an already-trusted checkout at the branch's final validated head, against every installed harness then covered by the empty-composer matrix on tmux 3.6a, macOS arm64, on an isolated private socket, with no prompt submitted to any harness.

```sh
FM_COMPOSER_MATRIX_LIVE=1 tests/fm-composer-matrix-live-e2e.test.sh
```

Observed output:

```text
ok - pi (0.84.1): real idle composer classifies empty
ok - strict posture live: a blank shell row classifies unknown and injection defers
ok - live composer-matrix guard verified 2 live surface(s)
```

The installed Pi harness's real idle composer reached a proven `empty` through the tmux foreground-process identity probe.
The strict blank-row posture held live: a blank shell row deferred injection.
Portable capture regressions in `tests/fm-composer-lib.test.sh` exercise each retained shape and capability profile under both a UTF-8 locale and `LC_ALL=C`.
This guard is the refresh command after an upgrade to any matrix-covered harness; rerun it and update the versions above rather than trusting this table across releases.

## Herdr

The compatibility floor is protocol 14.
The whole real-Herdr lane's latest active verification uses both Herdr 0.7.4 protocol 16 and Herdr 0.8.0 protocol 19 on macOS aarch64, while focused Herdr 0.7.5 protocol 17, earlier protocol-16, protocol-14, and 0.7.3 evidence is retained where it defines current behavior or fallbacks.
Protocol 17 keeps every protocol-16 feature gate satisfied; the event and workspace-move floors remain 16.
Default-on presentation projection has its own floor at Herdr 0.8.0, protocol 19, verified below.

Core read-only probes:

```sh
herdr --version
herdr status --json | jq -c '{client:.client.protocol,server:.server.protocol}'
herdr api schema --json | jq -c '.schemas.subscription_event["$defs"].SubscriptionEventKind.enum'
```

Observed protocol-16 compatibility shapes:

```text
herdr 0.7.5
{"client":17,"server":17}
["pane.output_matched","pane.agent_status_changed","pane.scroll_changed"]
```

The CLI matrix was checked directly:

| Guarantee | Command shape | Result |
| --- | --- | --- |
| Explicit session routing | `herdr <verb> ... --session <name>` | Reached the named session even while another server was running. |
| Literal send | `herdr pane send-text <pane> <text> --session <name>` | Left text unsubmitted until Enter. |
| Keys | `herdr pane send-keys <pane> enter|escape|ctrl+c --session <name>` | Enter and Escape worked; Ctrl-C interrupted foreground work. |
| Capture | `herdr pane read <pane> --source recent --lines N` | Small N could return empty below viewport height; a 200-line request plus local trim was stable. |
| Native state | `herdr agent get <pane>` | Working and done transitions were visible; native `busy` remains positive activity evidence, while native `idle` cannot close a turn and the adapter's semantic lifecycle decides worker state. |
| Restart | guarded named-session stop then start | Workspace, tab, pane, and labels persisted; the agent process and registration did not. |
| Close | `herdr pane close <pane> --session <name>` | The exact one-pane task tab closed; closing a final tab could remove the workspace. |

All destructive verification used `bin/fm-herdr-lab.sh` with a non-default `fm-lab-` name and a byte-identical default-session tripwire.
No ambient `herdr server stop` command is a supported test operation.

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

The suite also covers lost or failed move responses, active-tab refusal, restart husks, missing and duplicate tokens, manual renames, concurrent cleanup, and exact focus restoration.

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

Part C is the case the suite could not reach before: a doomed pane whose shell holds a persistent background child fails the lone-idle-shell proof on every sample, so the plan takes the plain explicit close, in the geometry where the closing workspace's right neighbour is a spacer rather than the focused anchor.
On 0.7.5 that fallback exposed a bounded four-sample wrong-focus window and restored the anchor exactly; on 0.8.0 the same fallback exposed none, which is why default-on projection is floored at 0.8.0 rather than mitigated further below it.
The suite also cross-checks its own Part A measurement against the floor classifier on whatever release it runs, so a drifted protocol-to-release mapping fails there rather than silently gating on the wrong thing.

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

The whole real-Herdr lane was run on 2026-08-05 against both the CI-pinned Herdr 0.7.4 protocol 16, which is below the floor, and Herdr 0.8.0 protocol 19, which is at it:

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
The U+2063 operational and routed-request separators were exercised through a real Pi-on-Herdr path; the byte-exact active regression is:

```sh
FM_SEND_MARKER_HERDR_E2E=1 \
  tests/fm-send-secondmate-marker-herdr-e2e.test.sh
```

### Busy Pi steer admission

The exact Pi admission receipt was verified on 2026-08-17 with Herdr 0.8.0, Pi 0.84.1, and the named-session helper's unchanged-default tripwire:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  FM_SEND_PI_ADMISSION_HERDR_E2E=1 \
  tests/fm-send-pi-admission-herdr-e2e.test.sh
```

Observed output:

```text
ok - real guarded Pi/Herdr busy steer appears exactly once, returns success, and stays working before and after
```

The fixture uses an isolated deterministic provider whose first active turn releases only after the terminal Enter is delivered, then keeps the next turn active.
The production `fm-send` path therefore sees working before and after with an unknown working composer, while the transcript contains the exact steer once and the current-generation journal contains its exact SHA-256 digest and UTF-8 byte length.
The portable public-interface regression drives the generated extension and real `fm-send` against a stateful fake Herdr, including old, malformed, stale-generation, wrong-digest, wrong-length, mixed-content, unreadable, truncated, unrelated, unsafe-path, working-boundary, lock-contention, transport-failure, swallowed-Enter, existing-proof, and concurrent-identical-send cases:

```sh
tests/fm-busy-adapter-wiring.test.sh
tests/fm-send-pi-admission.test.sh
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

Observed output:

```text
ok - real herdr: exit on a pane with no registered agent is idempotent success
ok - real herdr: interrupt refuses when herdr's own agent registry reports no agent
ok - real herdr: interrupt delivers the harness's key and proves the agent survived it
ok - real herdr: no control verb removed the endpoint or the task's local copy
ok - real herdr: an agent that does not stop fails closed instead of being reported as stopped
```

The registry read through `herdr pane report-agent` is the same source `fm_backend_herdr_agent_state` classifies, so registering and not registering an agent on a plain shell pane exercises exactly the gate every lifecycle verb depends on, with no real agent launched.
That command is the guard that refreshes this record; run it after every Herdr upgrade rather than trusting the version above.

### Away-mode transport

The Pi/Herdr return and injection path was reverified on Herdr 0.7.3 and Pi 0.80.7:

```sh
FM_AFK_PI_HERDR_E2E=1 HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-afk-pi-herdr-return-e2e.test.sh
```

Observed guarantees: pending composer input refused injection and raised one alert; idle Pi accepted one marked escalation; the return gate refused ordinary work while a live blocker remained; resolving the blocker allowed the return flow.
The dedicated Herdr daemon workspace topology is covered by `tests/fm-afk-launch.test.sh` and preserves the captain tab's pane count.
