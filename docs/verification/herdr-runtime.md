# Herdr runtime verification

This is active empirical maintainer evidence for Firstmate's sole Pi-and-Herdr
session path.
[`docs/herdr-backend.md`](../herdr-backend.md) owns current setup, safety
boundaries, and limitations; this file records exact measurements that justify
those contracts.


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
| Native state | `herdr agent get <pane>` | Working and done transitions were visible; native `busy` remains positive activity evidence, while native `idle` cannot close a turn and the integration's semantic lifecycle decides worker state. |
| Restart | guarded named-session stop then start | Workspace, tab, pane, and labels persisted; the agent process and registration did not. |
| Close | `herdr pane close <pane> --session <name>` | The exact one-pane task tab closed; closing a final tab could remove the workspace. |

All destructive verification used `bin/fm-herdr-lab.sh` with a non-default `fm-lab-` name and a byte-identical default-session tripwire.
No ambient `herdr server stop` command is a supported test operation.

### Prune and respawn

The real label-collision reproduction is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-prune-safety-e2e.test.sh
```

Observed guarantee: a pre-existing captain-owned workspace with a seed-shaped tab was adopted for routing but its tab was never eligible for prune because the current create call did not return that seed id.

Restart-husk replacement is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-respawn-idem-e2e.test.sh
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
  tests/fm-herdr-launcher-workspace-e2e.test.sh
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
The no-parent fixture verifies a defensive Herdr placement seam and does not make running the primary outside Herdr a supported path.
Cross-session and contradictory bindings are covered deterministically in `tests/fm-herdr.test.sh`, which can script a second server's socket without provisioning one.

### Per-home and presentation topology

Per-home behavior is owned by:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-workspace-per-home-e2e.test.sh
```

Observed guarantee: the primary and secondmate used distinct home workspaces, a child launched by the secondmate stayed in that secondmate workspace, list-live remained home-scoped, and exact cleanup did not affect sibling homes.

The complete projection suite ran on 2026-07-21 against Herdr 0.7.4 protocol 16:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-presentation-e2e.test.sh
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
  tests/fm-herdr-presentation-e2e.test.sh
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
  tests/fm-herdr-presentation-e2e.test.sh
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
  tests/fm-herdr-focus-flash-e2e.test.sh
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
tests/fm-herdr.test.sh
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

Two real-hardware conditions were required for the pane-death path to engage and are now encoded in the integration and its unit fixtures: BSD `ps` reports a login shell's `comm` as `-zsh`, and an idle shell transiently hosts a prompt helper (starship) as a second foreground process immediately after a `workspace.move` relayout, which the bounded settle window absorbs.

The rules match the v0.7.5 tag source (`close_selected_workspace` reassigns focus from the closing workspace's index; `handle_pane_died` only clamps the stale focused index), and the upstream default branch resolves both paths by workspace id (PR #1877, commit `165dca45`, for the explicit close; PR #1912, commit `a979916`, for pane death), so the plan degrades to a harmless reorder-then-remove once a release carries them.

The full projection and restored-shell suites were re-run on 2026-07-28 on Herdr 0.7.5 with the updated close path; the presentation suite completed with `real Herdr lab validation completed on Herdr 0.7.5 with the default-session tripwire intact`, and the restored-shell cleanup guarantee above was unchanged.

The teardown-level record-retention gate was verified on 2026-07-28 with metadata fixtures and a live contending lock holder:

```sh
tests/fm-teardown.test.sh
tests/fm-herdr.test.sh
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
The U+2063 operational and routed-request separators plus lifecycle control and teardown were reverified on 2026-08-21 with Herdr 0.8.0 and Pi 0.84.2; the active real Pi-on-Herdr regression is:

```sh
FM_SEND_MARKER_HERDR_E2E=1 \
  tests/fm-send-secondmate-marker-herdr-e2e.test.sh
```

```text
evidence: exact-id carrier=from-firstmate corr=valid body=exact
ok - real Pi/Herdr: exact-id FM_HOME send delivers exactly one from-firstmate marker
evidence: direct-input received-hex=464d5f4d41524b45525f48455244525f444952454354206361707461696e20696e707574
ok - real Pi/Herdr: direct captain terminal input stays unmarked
ok - real Pi/Herdr: lifecycle control preserves the live exact endpoint
ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata
```

### Native blocked event

The protocol-16 event path was measured on 2026-07-11 with Herdr 0.7.3 and Python 3.13:

```sh
HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-herdr-eventwait-smoke.test.sh
```

Observed output:

```text
ok - real herdr: events.subscribe capability gate passes
ok - real herdr: a driven idle->blocked transition returns the blocked record in 0.129s
ok - real herdr: the watcher fast-path enqueues a stale wake naming the task window
```

Polling remained active and is covered as the fallback for capability, connect, subscribe, and repeated reader failure.

### Sole-path spawn and cleanup revalidation

Reverified on 2026-08-21 with absent runtime selection, Pi 0.84.2, and Herdr 0.8.0 protocol 19.
The task-specific lab was provisioned and removed only through `/Users/control/firstmate/bin/fm-herdr-lab.sh`; its captured status was:

```text
{"client":{"version":"0.8.0","channel":"stable","protocol":19,"binary":"/Users/control/.local/bin/herdr","session":"fm-lab-remove-tmux-herd-10551-25664"},"server":{"status":"running","running":true,"version":"0.8.0","protocol":19,"capabilities":{"live_handoff":true,"detached_server_daemon":false},"compatible":true,"socket":"/Users/control/.config/herdr/sessions/fm-lab-remove-tmux-herd-10551-25664/herdr.sock","session":"fm-lab-remove-tmux-herd-10551-25664","restart_needed":false}}
```

Exact cleanup command and output:

```sh
HERDR_LAB_HELPER='/Users/control/firstmate/bin/fm-herdr-lab.sh' \
  bash tests/fm-herdr-default-smoke.test.sh
```

```text
ok - real Herdr: fm-spawn.sh uses Herdr with no runtime selection
ok - real herdr: default Herdr spawn records explicit backend=herdr and herdr_session/workspace/tab/pane fields in meta
ok - real herdr: the default Herdr spawn's launch command actually ran in the herdr pane
ok - real herdr: teardown completes the default Herdr spawn/teardown cycle (meta cleared, pane closed)
ok - real herdr: isolated lab session removed and default fleet session unchanged
```

### Agent lifecycle control

Herdr's recovery-grade agent-state classifier is the process-control authority ([agent-control.md](../agent-control.md)), so its lifecycle gating is measured against the real binary; reverified 2026-08-21 on Herdr 0.8.0, and first measured 2026-08-02 on Herdr 0.7.5 with identical results:

```sh
HERDR_LAB_HELPER='/Users/control/firstmate/bin/fm-herdr-lab.sh' \
  bash tests/fm-control-herdr-smoke.test.sh
```

Observed output:

```text
ok - real herdr: exit on a pane with no registered agent is idempotent success
ok - real herdr: interrupt refuses when herdr's own agent registry reports no agent
ok - real herdr: interrupt delivers the harness's key and proves the agent survived it
ok - real herdr: no control verb removed the endpoint or the task's local copy
ok - real herdr: an agent that does not stop fails closed instead of being reported as stopped
```

The registry read through `herdr pane report-agent` is the same source `fm_herdr_agent_state` classifies, so registering and not registering an agent on a plain shell pane exercises exactly the gate every lifecycle verb depends on, with no real agent launched.
That command is the guard that refreshes this record; run it after every Herdr upgrade rather than trusting the version above.

### Away-mode transport

The Pi/Herdr return and injection path was reverified on Herdr 0.7.3 and Pi 0.80.7:

```sh
FM_AFK_PI_HERDR_E2E=1 HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
  tests/fm-afk-pi-herdr-return-e2e.test.sh
```

Observed guarantees: pending composer input refused injection and raised one alert; idle Pi accepted one marked escalation; the return gate refused ordinary work while a live blocker remained; resolving the blocker allowed the return flow.
The dedicated Herdr daemon workspace topology is covered by `tests/fm-afk-launch.test.sh` and preserves the captain tab's pane count.

## 2026-08-22 Herdr-only review evidence

The final portable session-path run used:

```sh
bin/fm-test-run.sh --family herdr-session
```

```text
FM_TEST_SUMMARY total=12 failed=0 skipped_gate=0 duration_ms=493007
FM_TEST_SUMMARY_FAMILY family=herdr-session count=12 duration_ms=492517 failed=0
```

Remote and local Secondmate routing used:

```sh
bin/fm-test-run.sh tests/fm-secondmate-safety.test.sh tests/fm-remote-secondmate-lifecycle-e2e.test.sh tests/fm-remote-secondmate-parent-binding.test.sh tests/fm-remote-secondmate-trace-context.test.sh
```

```text
FM_TEST_SUMMARY total=4 failed=0 skipped_gate=0 duration_ms=179589
FM_TEST_SUMMARY_FAMILY family=secondmate count=3 duration_ms=150315 failed=0
FM_TEST_SUMMARY_FAMILY family=unclassified count=1 duration_ms=29075 failed=0
```

Watcher durability, native transition fallback, and away-mode guards used:

```sh
bin/fm-test-run.sh tests/fm-watch-triage.test.sh tests/fm-wake-queue.test.sh tests/fm-supervision-events.test.sh tests/fm-daemon.test.sh
```

```text
FM_TEST_SUMMARY total=4 failed=0 skipped_gate=0 duration_ms=164675
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=4 duration_ms=164494 failed=0
```

The final session-lock and native-transition regression rerun used:

```sh
bin/fm-test-run.sh tests/fm-send-strict.test.sh tests/fm-supervision-events.test.sh
```

```text
FM_TEST_SUMMARY total=2 failed=0 skipped_gate=0 duration_ms=16131
FM_TEST_SUMMARY_FAMILY family=herdr-session count=1 duration_ms=8021 failed=0
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=1 duration_ms=8003 failed=0
```

The final admission, live-identity snapshot, watcher, and real Pi-on-Herdr lifecycle rerun used:

```sh
bash -n bin/fm-fleet-snapshot.sh bin/fm-session-start.sh bin/fm-watch.sh tests/fm-bearings-snapshot.test.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-session-start.test.sh tests/fm-watch-triage.test.sh && \
  bin/fm-test-run.sh tests/fm-session-start.test.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-bearings-snapshot.test.sh tests/fm-watch-triage.test.sh && \
  lifecycle=$(FM_SEND_MARKER_HERDR_E2E=1 HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
    bash tests/fm-send-secondmate-marker-herdr-e2e.test.sh) && \
  printf '%s\n' "$lifecycle" && \
  printf '%s\n' "$lifecycle" | grep -F 'ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata' >/dev/null && \
  git diff --check && \
  printf '%s\n' 'focused admission, identity, watcher, snapshot, and lifecycle verification: ok'
```

```text
FM_TEST_SUMMARY total=4 failed=0 skipped_gate=0 duration_ms=294080
FM_TEST_SUMMARY_FAMILY family=session-bootstrap count=1 duration_ms=207082 failed=0
FM_TEST_SUMMARY_FAMILY family=snapshot-bearings count=2 duration_ms=7702 failed=0
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=1 duration_ms=79100 failed=0
warning: secondmate marker-pi-sm sync skipped before launch: primary default-branch commit cannot be resolved
●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
●  WATCHER DOWN - SUPERVISION IS OFF
●  1 task(s) in flight, but no watcher has a fresh beacon (last beat: never, grace 300s).
●  Trust the emitted Pi supervision protocol; do not use shell & for watcher repair.
●  This is a supervision warning only; the requested message WILL still be sent.
●  repair a missing or failed watcher cycle with the Pi tool fm_watch_arm_pi, or restart Pi with -e /Users/control/.no-mistakes/worktrees/874f0de57f61/01M0JV34M9BNN5H9SSWGKW5BG2/.pi/extensions/fm-primary-turnend-guard.ts -e /Users/control/.no-mistakes/worktrees/874f0de57f61/01M0JV34M9BNN5H9SSWGKW5BG2/.pi/extensions/fm-primary-pi-watch.ts if the extensions are not loaded.
●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
evidence: exact-id carrier=from-firstmate corr=valid body=exact
ok - real Pi/Herdr: exact-id FM_HOME send delivers exactly one from-firstmate marker
evidence: direct-input received-hex=464d5f4d41524b45525f48455244525f444952454354206361707461696e20696e707574
ok - real Pi/Herdr: direct captain terminal input stays unmarked
ok - real Pi/Herdr: lifecycle control preserves the live exact endpoint
ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata
focused admission, identity, watcher, snapshot, and lifecycle verification: ok
```

The final paused-endpoint reconciliation and Pi supervision wording rerun used:

```sh
bash -n bin/fm-watch.sh bin/fm-guard.sh tests/fm-watch-triage.test.sh tests/fm-guard-stale-banner.test.sh && \
  bin/fm-test-run.sh tests/fm-watch-triage.test.sh tests/fm-guard-stale-banner.test.sh && \
  bin/fm-lint.sh bin/fm-watch.sh bin/fm-guard.sh tests/fm-watch-triage.test.sh tests/fm-guard-stale-banner.test.sh && \
  bin/fm-doc-audience-check.sh && \
  lifecycle=$(FM_SEND_MARKER_HERDR_E2E=1 HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
    bash tests/fm-send-secondmate-marker-herdr-e2e.test.sh) && \
  printf '%s\n' "$lifecycle" && \
  printf '%s\n' "$lifecycle" | grep -F 'ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata' >/dev/null && \
  git diff --check && \
  printf '%s\n' 'focused watcher reconciliation and Pi supervision verification: ok'
```

```text
FM_TEST_SUMMARY total=2 failed=0 skipped_gate=0 duration_ms=83376
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=2 duration_ms=83263 failed=0
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
warning: secondmate marker-pi-sm sync skipped before launch: primary default-branch commit cannot be resolved
●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
●  WATCHER DOWN - SUPERVISION IS OFF
●  1 task(s) in flight, but no watcher has a fresh beacon (last beat: never, grace 300s).
●  Trust the emitted Pi supervision protocol; do not use shell & for watcher repair.
●  This is a supervision warning only; the requested message WILL still be sent.
●  repair a missing or failed watcher cycle with the Pi tool fm_watch_arm_pi, or restart Pi with -e /Users/control/.no-mistakes/worktrees/874f0de57f61/01M0JV34M9BNN5H9SSWGKW5BG2/.pi/extensions/fm-primary-turnend-guard.ts -e /Users/control/.no-mistakes/worktrees/874f0de57f61/01M0JV34M9BNN5H9SSWGKW5BG2/.pi/extensions/fm-primary-pi-watch.ts if the extensions are not loaded.
●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
evidence: exact-id carrier=from-firstmate corr=valid body=exact
ok - real Pi/Herdr: exact-id FM_HOME send delivers exactly one from-firstmate marker
evidence: direct-input received-hex=464d5f4d41524b45525f48455244525f444952454354206361707461696e707574
ok - real Pi/Herdr: direct captain terminal input stays unmarked
ok - real Pi/Herdr: lifecycle control preserves the live exact endpoint
ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata
focused watcher reconciliation and Pi supervision verification: ok
```

The final recovery-grade unreachable-endpoint rerun used:

```sh
bash -n bin/fm-fleet-snapshot.sh bin/fm-watch.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-watch-triage.test.sh && \
  bin/fm-test-run.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-watch-triage.test.sh && \
  bin/fm-lint.sh bin/fm-fleet-snapshot.sh bin/fm-watch.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-watch-triage.test.sh && \
  git diff --check && \
  printf '%s\n' 'focused recovery-grade Herdr liveness verification: ok'
```

```text
FM_TEST_SUMMARY total=2 failed=0 skipped_gate=0 duration_ms=80105
FM_TEST_SUMMARY_FAMILY family=snapshot-bearings count=1 duration_ms=4747 failed=0
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=1 duration_ms=75264 failed=0
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
focused recovery-grade Herdr liveness verification: ok
```

The final exact Pi admission, Pi-only spawn, and live-agent supervision rerun used:

```sh
bin/fm-test-run.sh tests/fm-session-lock-ancestry.test.sh tests/fm-session-start.test.sh tests/fm-spawn-dispatch-profile.test.sh tests/fm-daemon.test.sh
```

```text
FM_TEST_SUMMARY total=4 failed=0 skipped_gate=0 duration_ms=275078
FM_TEST_SUMMARY_FAMILY family=herdr-session count=1 duration_ms=48776 failed=0
FM_TEST_SUMMARY_FAMILY family=session-bootstrap count=1 duration_ms=222228 failed=0
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=2 duration_ms=3862 failed=0
```

The final live-agent injection boundary rerun used:

```sh
bash -n bin/fm-supervise-daemon.sh tests/fm-daemon.test.sh && \
  bin/fm-test-run.sh tests/fm-daemon.test.sh && \
  bin/fm-lint.sh bin/fm-supervise-daemon.sh tests/fm-daemon.test.sh && \
  git diff --check
```

```text
FM_TEST_SUMMARY total=1 failed=0 skipped_gate=0 duration_ms=2186
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=1 duration_ms=2122 failed=0
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
```

The final exact Pi process-identity and public Herdr behavior rerun used:

```sh
bash -n bin/fm-session-lock-lib.sh tests/fm-session-lock-ancestry.test.sh tests/fm-herdr-selection.test.sh && \
  bin/fm-test-run.sh tests/fm-session-lock-ancestry.test.sh tests/fm-herdr-selection.test.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-on.test.sh tests/fm-send-strict.test.sh && \
  bin/fm-lint.sh bin/fm-session-lock-lib.sh tests/fm-session-lock-ancestry.test.sh tests/fm-herdr-selection.test.sh && \
  bin/fm-doc-audience-check.sh && \
  git diff --check
```

```text
FM_TEST_SUMMARY total=5 failed=0 skipped_gate=0 duration_ms=35303
FM_TEST_SUMMARY_FAMILY family=herdr-session count=2 duration_ms=9119 failed=0
FM_TEST_SUMMARY_FAMILY family=secondmate count=1 duration_ms=16261 failed=0
FM_TEST_SUMMARY_FAMILY family=snapshot-bearings count=1 duration_ms=4772 failed=0
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=1 duration_ms=4936 failed=0
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final real Herdr presentation and real Pi-on-Herdr lifecycle rerun used:

```sh
bash tests/fm-herdr-presentation-e2e.test.sh && \
  lifecycle=$(FM_SEND_MARKER_HERDR_E2E=1 HERDR_LAB_HELPER=bin/fm-herdr-lab.sh bash tests/fm-send-secondmate-marker-herdr-e2e.test.sh) && \
  printf '%s\n' "$lifecycle" && \
  printf '%s\n' "$lifecycle" | grep -F 'ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata' >/dev/null && \
  bin/fm-lint.sh bin/fm-spawn.sh bin/fm-session-lock-lib.sh bin/fm-supervise-daemon.sh tests/herdr-test-safety.sh tests/fm-spawn-dispatch-profile.test.sh tests/fm-session-lock-ancestry.test.sh tests/fm-daemon.test.sh tests/fm-herdr-default-smoke.test.sh tests/fm-herdr-presentation-e2e.test.sh tests/fm-herdr-launcher-workspace-e2e.test.sh tests/fm-herdr-workspace-per-home-e2e.test.sh && \
  bin/fm-doc-audience-check.sh && \
  git diff --check
```

```text
ok - real Herdr lab: an opted-out spawn retains the Stage 1 Herdr command sequence with zero ordering calls
ok - real Herdr lab: a home that configured nothing is projected by default on herdr 0.8.0
ok - real Herdr lab: every projected create, task-tab create, seeded prune, and move preserves active workspace and tab
ok - real Herdr lab: active seeded-tab pruning refuses the exact pane and preserves exact focus
ok - real Herdr lab: bounded lock contention warns and falls back flat without projection or focus drift
ok - real Herdr lab: concurrent primary workers form one stable contiguous block without active workspace/tab drift
ok - real Herdr lab: forced workspace.move failure leaves a successful worker in default order with a warning and no cleanup
ok - real Herdr lab: concurrent post-create abort cleanup stays serialized with exact focus restoration
ok - real Herdr lab: Treehouse commands and metadata shape are byte-identical except for endpoint IDs and spawn incarnation
ok - real Herdr lab: exact task-pane close removes the projected workspace with no unrestored wrong-focus interval
evidence: exact-id carrier=from-firstmate corr=valid body=exact
ok - real Pi/Herdr: exact-id FM_HOME send delivers exactly one from-firstmate marker
evidence: direct-input received-hex=464d5f4d41524b45525f48455244525f444952454354206361707461696e20696e707574
ok - real Pi/Herdr: direct captain terminal input stays unmarked
ok - real Pi/Herdr: lifecycle control preserves the live exact endpoint
ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final Herdr-bound Pi lifecycle and direct Pi documentation rerun used:

```sh
npm install --silent --no-audit --no-fund --prefix .review-typescript typescript@5.9.3 && tests/fm-busy-adapter-wiring.test.sh && PATH="$PWD/.review-typescript/node_modules/.bin:$PATH" tests/fm-pi-primary-types.test.sh && bin/fm-doc-audience-check.sh && git diff --check; result=$?; find .review-typescript -depth -delete; exit $result
```

```text
ok - tracked Pi lifecycle preserves busy, idle, turn-end, ordering, and stale-generation behavior
ok - worker lifecycle context rejects unsafe, non-Herdr, and inconsistent inputs
all fm-busy-adapter-wiring tests passed
ok - tracked Pi extensions pass strict no-emit typecheck against Pi 0.84.2
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final direct Herdr away-lifecycle rerun used:

```sh
bash -n bin/fm-afk-launch.sh tests/fm-afk-launch.test.sh tests/fm-afk-return.test.sh && tests/fm-afk-launch.test.sh && tests/fm-afk-return.test.sh && bin/fm-lint.sh bin/fm-afk-launch.sh tests/fm-afk-launch.test.sh tests/fm-afk-return.test.sh && bin/fm-doc-audience-check.sh && git diff --check
```

```text
ok - away launcher round-trips exact Herdr terminal identity
ok - retired away-terminal records stay intact for manual reconciliation
fm-afk-launch: terminal close command failed, but exact absence was confirmed
ok - exact confirmed absence is the only terminal-record retirement authority
ok - unconfirmed Herdr close preserves exact reconciliation identity
ok - away launcher lock binds and releases exact process identity
ok - return catch-up precedes Bearings, owns live blocker remediation, preserves evidence once, and clears idempotently
ok - Herdr blockers require an explicit durable reclassification before ordinary work
ok - needs-decision remains reportable without masquerading as a firstmate-actionable blocker
ok - AFK return re-drains published wakes until handling acknowledges
ok - away-mode re-entry fails closed while the prior return catch-up is pending
ok - check retries recorded terminal teardown and keeps catch-up gated until success
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final native-transition executable transport rerun used:

```sh
bash -n tests/fm-herdr-transition.test.sh && tests/fm-herdr-transition.test.sh && shellcheck -x tests/fm-herdr-transition.test.sh && bin/fm-doc-audience-check.sh && git diff --check
```

```text
ok - event reader subscribes to the requested pane through Herdr's executable wire interface
ok - event reader emits only normalized four-field Herdr transition records
# fm-herdr-transition.test.sh: all assertions passed
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final direct Pi-on-Herdr AFK entrypoint lint used:

```sh
bash -n bin/fm-afk-start.sh && bin/fm-lint.sh bin/fm-afk-start.sh && bin/fm-doc-audience-check.sh && git diff --check
```

```text
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final Pi-only runtime contract documentation check used:

```sh
bash -n bin/fm-watch-arm.sh && bin/fm-lint.sh bin/fm-watch-arm.sh && bin/fm-doc-audience-check.sh && git diff --check
```

```text
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final direct Herdr rationale and Pi entrypoint lint used:

```sh
bash -n bin/fm-herdr.sh bin/fm-session-start.sh bin/fm-afk-start.sh && bin/fm-lint.sh bin/fm-herdr.sh bin/fm-session-start.sh bin/fm-afk-start.sh && bin/fm-doc-audience-check.sh && git diff --check
```

```text
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final Pi lock admission and Herdr evidence-owner rerun used:

```sh
bash -n bin/fm-lock.sh bin/fm-herdr.sh tests/fm-session-lock-ancestry.test.sh && tests/fm-session-lock-ancestry.test.sh && bin/fm-lint.sh bin/fm-lock.sh bin/fm-herdr.sh tests/fm-session-lock-ancestry.test.sh && bin/fm-doc-audience-check.sh && git diff --check
```

```text
ok - session-lock: Pi ancestry owns its exact lock
ok - session-lock: nested Pi ancestry preserves the exact inner owner
ok - session-lock: ancestry never crosses a non-Pi gap
ok - session-lock: a live competing pi session is live but never self
ok - session-lock: public admission requires the exact Pi executable identity
ok - session-lock: explicit tmux environment refuses before state creation
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final Pi-hook and live Pi/Herdr test-family check used:

```sh
bash -n bin/fm-startup-network.sh bin/fm-watch.sh bin/fm-test-run.sh bin/fm-composer-lib.sh tests/fm-test-run.test.sh && \
  bin/fm-test-run.sh --list-families | grep -Fx live-pi-herdr-optin && \
  tests/fm-test-run.test.sh | tail -1 && \
  bin/fm-lint.sh bin/fm-test-run.sh tests/fm-test-run.test.sh && \
  bin/fm-doc-audience-check.sh && \
  git diff --check
```

```text
live-pi-herdr-optin
ok - aggregate-json merges lane timing artifacts
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

Review-phase changed-source lint and the documentation check used:

```sh
bin/fm-lint.sh bin/fm-bootstrap.sh bin/fm-control.sh bin/fm-crew-state.sh bin/fm-fleet-snapshot.sh bin/fm-herdr.sh bin/fm-peek.sh bin/fm-pending-reply-lib.sh bin/fm-remote-secondmate-control.sh bin/fm-send.sh bin/fm-stow-cascade.sh bin/fm-supervise-daemon.sh bin/fm-watch.sh tests/fm-daemon.test.sh tests/fm-secondmate-safety.test.sh tests/fm-send-strict.test.sh tests/fm-supervision-events.test.sh
bin/fm-lint.sh bin/fm-herdr.sh bin/fm-watch.sh tests/fm-send-strict.test.sh tests/fm-supervision-events.test.sh
bin/fm-doc-audience-check.sh
```

```text
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=52 local_links=168
```

The final exact-target, unreadable-recheck, authorized-socket, and real Pi/Herdr lifecycle rerun used:

```sh
set -o pipefail && \
  send=$(tests/fm-send-strict.test.sh) && \
  printf '%s\n' "$send" | grep -F 'ok - fm-send strict: explicit targets stay on their authorized Herdr generation' && \
  daemon=$(tests/fm-daemon.test.sh) && \
  printf '%s\n' "$daemon" | grep -E '^ok - daemon (preserves and surfaces unreadable endpoint rechecks|read-only liveness ignores unrelated presentation lock contention)$' && \
  lifecycle=$(FM_SEND_MARKER_HERDR_E2E=1 HERDR_LAB_HELPER=bin/fm-herdr-lab.sh \
    bash tests/fm-send-secondmate-marker-herdr-e2e.test.sh) && \
  printf '%s\n' "$lifecycle" | grep -E '^ok - real Pi/Herdr:' && \
  printf 'versions: ' && herdr --version && printf 'Pi ' && pi --version && \
  bin/fm-lint.sh bin/fm-herdr.sh bin/fm-peek.sh bin/fm-send.sh bin/fm-supervise-daemon.sh tests/fm-daemon.test.sh tests/fm-send-strict.test.sh && \
  bin/fm-doc-audience-check.sh && \
  git diff --check
```

```text
ok - fm-send strict: explicit targets stay on their authorized Herdr generation
ok - daemon preserves and surfaces unreadable endpoint rechecks
ok - daemon read-only liveness ignores unrelated presentation lock contention
ok - real Pi/Herdr: exact-id FM_HOME send delivers exactly one from-firstmate marker
ok - real Pi/Herdr: direct captain terminal input stays unmarked
ok - real Pi/Herdr: lifecycle control preserves the live exact endpoint
ok - real Pi/Herdr: teardown removes the endpoint, home, and metadata
versions: herdr 0.8.0
Pi 0.84.2
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final malformed-marker and ambiguous-endpoint cadence rerun used:

```sh
set -o pipefail && \
  daemon=$(tests/fm-daemon.test.sh) && \
  printf '%s\n' "$daemon" | grep -F 'ok - daemon preserves and surfaces unreadable endpoint rechecks' && \
  bin/fm-lint.sh bin/fm-supervise-daemon.sh tests/fm-daemon.test.sh && \
  bin/fm-doc-audience-check.sh && \
  git diff --check
```

```text
ok - daemon preserves and surfaces unreadable endpoint rechecks
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

The final Pi state-label rerun used:

```sh
set -o pipefail && \
  crew=$(tests/fm-crew-state.test.sh) && \
  printf '%s\n' "$crew" | grep -E '^ok - (no run \+ a busy semantic record reads working, attributed to its source|Pi never reads working from rendered footer text)$' && \
  bin/fm-lint.sh bin/fm-bootstrap.sh bin/fm-busy-event.sh bin/fm-cd-pretool-check.sh bin/fm-crew-state.sh bin/fm-send.sh bin/fm-sessionstart-nudge.sh bin/fm-supervise-daemon.sh tests/fm-crew-state.test.sh tests/fm-watch-triage.test.sh && \
  bin/fm-doc-audience-check.sh && \
  git diff --check
```

```text
ok - no run + a busy semantic record reads working, attributed to its source
ok - Pi never reads working from rendered footer text
fm-lint.sh: ShellCheck 0.11.0 (pinned 0.11.0)
fm-doc-audience-check: ok surfaces=51 local_links=166
```

Tracked physical line counts were measured with deleted paths excluded:

```sh
count_paths() { local n=0 files=0 f lines; while IFS= read -r f; do [ -f "$f" ] || continue; lines=$(wc -l < "$f"); n=$((n+lines)); files=$((files+1)); done; printf '%s %s\n' "$n" "$files"; }
printf 'all '; git ls-files | count_paths
printf 'bin '; git ls-files 'bin/**' | count_paths
printf 'tests '; git ls-files 'tests/**' | count_paths
printf 'pi '; { git ls-files '.pi/extensions/**'; git ls-files '.pi/worker-extensions/**'; } | sort -u | count_paths
printf 'agents '; wc -l < AGENTS.md
git diff 5f5fa0980aacf5c89f5ac1c47f6d52eedf911457 --numstat | awk '{a+=$1;d+=$2} END{print "added="a,"deleted="d,"net="a-d}'
```

```text
all 132468 313
bin 54426 126
tests 57459 117
pi 2048 9
agents 559
added=9441 deleted=34177 net=-24736
```

The baseline was 157,204 tracked lines, including 55,808 in `bin/`, 80,837 in `tests/`, 2,044 in Pi extensions, and 563 in `AGENTS.md`; the final tree is 24,736 lines smaller.
