# Supervision integration verification

Audience: maintainer verification.

This record supports current session-start, turn-end, watcher-continuity, and wedge-alarm guarantees.
Operator behavior and active limits remain in the linked current guides.
Task-specific chronology, temporary paths, run identifiers, and delivery transcripts remain in private reports or PR evidence.

## Native session-start delivery


Pi command shape:

```sh
pi -p -e .pi/extensions/fm-primary-turnend-guard.ts \
  --no-context-files --no-session \
  'After obeying any earlier session-start instruction, reply with exactly PI_SMOKE_DONE.'
```

Observed result: `PI_SMOKE_DONE`, with one session-start execution.
The earlier `sendUserMessage` counterfactual raced the positional prompt; the current non-triggering `pi.sendMessage` custom message did not.

### Run-tier source vocabulary and context-reset injection

The run tier depends on three facts only the vendor can supply: the session-open source it reports, whether hook stdout reaches model context on a context-RESET open rather than only a cold one, and whether a worker the hook detaches survives the hook returning.
The first two were measured on 2026-08-05 against a throwaway Firstmate-shaped lab carrying each harness's own tracked registration with a recorder standing in for `bin/fm-sessionstart-run.sh`.
Each open printed a source-stamped token, and the model was asked to quote that token back, so producing hook stdout could never be mistaken for delivering it.
The third is recorded below.

| Harness | Version verified | Cold open | Context reset | Context-preserving reopen |
| --- | --- | --- | --- | --- |
| Pi | 0.82.0 | `source=startup`, token quoted back in both `-p` and the TUI | `/new` raises `session_start` reason `new`, which the extension maps to `clear`; `/compact` raises `session_compact`, and both freshly injected source-stamped tokens were quoted back | `pi -c` reports reason `startup`, not `resume` |

Pi compaction was verified on 2026-08-05 with Pi 0.82.0 in the same throwaway lab after setting `.pi/settings.json` `compaction.keepRecentTokens` to 200 and completing one substantial assistant-prose turn before issuing `/compact`.
Pi reported `Compacted from 7,697 tokens`, the recorder observed `session_compact`, and the model quoted the freshly injected `source=compact` token back.
Both preconditions are load-bearing: the stock 20,000-token keep window exceeds a small lab session, and `AgentSession.compact()` aborts an in-flight turn before measuring compactable history, which otherwise discards that turn and reports `Nothing to compact (session too small)`.
Tool output alone does not grow compactable context; the completed assistant prose does.

Observed compaction output and recorder source:

```text
Compacted from 7,697 tokens
compact
```

Current Pi source classification and baseline mechanics are owned by [`../sessionstart-nudge.md`](../sessionstart-nudge.md#harness-transports) and the `bin/fm-session-start.sh` header.
Their continuation classification is covered by portable tests, not claimed as live validation in this record.

### Post-start instruction refresh

Pi compaction and instruction refresh must be exercised in a guarded named Herdr session.
The tracked worker-lifecycle proof below covers current Pi+Herdr lifecycle delivery; portable session-start tests cover continuation classification, baseline immutability, and source routing.

## Semantic busy state

The tracked worker extension was reverified on 2026-08-21 with Pi 0.84.2 and Herdr 0.8.0 in a guarded named session.
A fresh disposable Git target explicitly loaded the extension outside auto-discovery with `--no-extensions -e <tracked-worker-extension>` and one canonical metadata path; no project-trust prompt appeared.
Two controlled prompts exposed `state: working · source: pane · harness busy (pi-ext)` through `bin/fm-crew-state.sh`, then settled to `v1 ... state=idle source=pi-ext event=agent-settled`; `turn-ended` was touched without becoming current-state truth.
Rearming between prompts changed the generation, and the first Pi process's late callbacks left the replacement seed unchanged before the replacement lifecycle took ownership.

Exact recovered invocation:

```sh
bash /Users/control/firstmate/data/pi-native-simplification-a1/live-proof-rerun.sh
```

Exact recorded stdout:

```text
PI_VERSION=0.84.2
HERDR_STATUS={"status":"running","running":true,"version":"0.8.0","protocol":19,"capabilities":{"live_handoff":true,"detached_server_daemon":false},"compatible":true,"socket":"/Users/control/.config/herdr/sessions/fm-lab-pi-native-simpli-10856-16772/herdr.sock","session":"fm-lab-pi-native-simpli-10856-16772","restart_needed":false}
FIRST_STATE=state: working · source: pane · harness busy (pi-ext)
SECOND_STATE=state: working · source: pane · harness busy (pi-ext)
FINAL_RECORD=v1 gen=g1787323619.20524.23545 seq=3 state=idle source=pi-ext event=agent-settled ts=1787323663
OLD_GENERATION_REJECTED=g1787323609.12672.23501->g1787323619.20524.23545
TRUST_PROMPT=absent
EXTERNAL_EXTENSION=/Users/control/.treehouse/firstmate-af9cb2/2/firstmate/.pi/worker-extensions/fm-worker-lifecycle.ts
```

Exact recorded stderr and exit status:

```text
STDERR_BEGIN
STDERR_END
EXIT_STATUS=0
```

Portable behavior and strict type entry points:

```sh
tests/fm-busy-state.test.sh
tests/fm-busy-adapter-wiring.test.sh
tests/fm-crew-state.test.sh
tests/fm-pi-primary-types.test.sh
```

## Turn-end guard

The bounded-follow-up mechanism was validated on the enabled integration path from 2026-07-08 through 2026-08-13.

| Harness | Version verified | Mechanism | Observed result |
| --- | --- | --- | --- |
| Pi | 0.80.5 | Passive `agent_settled` callback | Exactly one guard follow-up ran for an unhealthy cycle, with no recursion across tool turns. |

`tests/fm-session-lock-ancestry.test.sh` pins exact Pi lock-owner ancestry and competitor isolation behind a deterministic process table.
`tests/fm-watch-arm.test.sh` runs real watcher and arm cycles against durable on-disk state to verify that a delivered reason survives until post-handling acknowledgement and stops replaying after acknowledgement, while an unrelated queue append cannot make a watcher cycle that delivered nothing look successful.
The same suite ingests a keyed remote-secondmate parent reply through the real adapter, establishes the incremental OPEN DECISIONS cursor, interrupts supervision, and proves re-arm replays every unacknowledged queue row plus the still-open decision through the ordinary drain path.
It also covers decision-only recovery, interrupted handling, handling-window generation reuse, non-fatal moved-generation acknowledgement with sequence-bounded consumption, and a persistent successor remaining live after recovery is acknowledged.

Current entry points:

```sh
tests/fm-turnend-guard.test.sh
tests/fm-supervision-instructions.test.sh
FM_AFK_PI_HERDR_E2E=1 tests/fm-afk-pi-herdr-return-e2e.test.sh
```

Pi-only session admission, live endpoint identity in snapshots, and paused watcher reconciliation were verified on 2026-08-22 with isolated behavior suites.
The same run verifies that identity mismatches preserve supervision tracking and remain unknown rather than reporting a foreign endpoint as live.

```sh
bin/fm-test-run.sh tests/fm-session-start.test.sh tests/fm-fleet-snapshot-view.test.sh tests/fm-bearings-snapshot.test.sh tests/fm-watch-triage.test.sh
```

Observed output:

```text
FM_TEST_SUMMARY total=4 failed=0 skipped_gate=0 duration_ms=294080
FM_TEST_SUMMARY_FAMILY family=session-bootstrap count=1 duration_ms=207082 failed=0
FM_TEST_SUMMARY_FAMILY family=snapshot-bearings count=2 duration_ms=7702 failed=0
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=1 duration_ms=79100 failed=0
```

The final identity-reconciliation and Pi supervision wording pass used:

```sh
bin/fm-test-run.sh tests/fm-watch-triage.test.sh tests/fm-guard-stale-banner.test.sh
```

Observed output:

```text
FM_TEST_SUMMARY total=2 failed=0 skipped_gate=0 duration_ms=83376
FM_TEST_SUMMARY_FAMILY family=watcher-wake-lock count=2 duration_ms=83263 failed=0
```

The broader relevant regression pass was rerun on 2026-08-02 without live-home or daemon mutation.

```sh
bin/fm-test-run.sh tests/fm-watch-triage.test.sh tests/fm-watcher-lock.test.sh tests/fm-afk-return.test.sh tests/fm-relay.test.sh tests/fm-herdr-selection.test.sh tests/fm-secondmate-safety.test.sh
```

Observed output:

```text
FM_TEST_SUMMARY total=8 failed=0 skipped_gate=0 duration_ms=617507
```

## Watcher continuity

No credential material was copied into a fixture.

```text
Pi 0.80.10
```

| Harness | Exact opt-in command | Observed guarantee |
| --- | --- | --- |
| Pi | `FM_AFK_PI_HERDR_E2E=1 tests/fm-afk-pi-herdr-return-e2e.test.sh` | One initial tool call led to extension-owned successors and clean child retirement on exit. |

Pi 0.84.1 repeated the isolated primary continuity regression on 2026-08-16.

```sh
FM_AFK_PI_HERDR_E2E=1 bin/fm-test-run.sh tests/fm-afk-pi-herdr-return-e2e.test.sh
```

Observed bounded output:

```text
ok - Pi 0.84.1 live E2E covered the Calm working ship, Ahoy first/later messages, legacy transcripts, near misses, and watcher continuity
```

Pi same-process session-transition ownership was verified on 2026-07-27 against the tracked extension with a faithful in-process factory rebind (module cache retained, real arm children):

```sh
pi --version
tests/fm-pi-watch-extension.test.sh
tests/fm-pi-primary-types.test.sh
```

Observed guarantee: after ordinary `session_shutdown` for `/new`, `/resume`, and `/fork`, plus same-instance shutdown-plus-start, the replacement generation armed again without a Pi restart and without the `watcher: not armed - Pi session is shutting down` refusal.
Stale prior-generation tool callbacks could not mutate the active child, repeated transitions kept exactly one live arm cycle, and terminal `quit` still refused late rearm.
Pi uses the tracked `.pi/extensions/fm-primary-pi-watch.ts` path and inherits the generation owner; other primary harnesses are not applicable because they do not use this Pi extension lifecycle.

Deterministic entry points:

```sh
tests/fm-pi-watch-extension.test.sh
tests/fm-pi-primary-types.test.sh
tests/fm-watcher-lock.test.sh
tests/fm-watch-arm.test.sh
tests/fm-wake-queue.test.sh
tests/fm-turnend-guard.test.sh
```

## Wedge-alarm channels

The two real notification channels were bounded manually on 2026-07-10 on macOS 26.5.2 with Herdr 0.7.3.
Automated suites never execute these real notification commands.

Argv-safe Notification Center command:

```sh
/usr/bin/osascript \
  -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title "FIRSTMATE TEST - IGNORE" sound name "Basso"' \
  -e 'end run' \
  'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)'
```

Observed output: no stdout, exit 0, and one banner with the supplied body.

Herdr command:

```sh
herdr notification show 'FIRSTMATE TEST - IGNORE' \
  --body 'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)' \
  --sound request
```

Observed output:

```json
{"id":"cli:notification:show","result":{"reason":"shown","shown":true,"type":"notification_show"}}
```

The safe command-channel contract is covered without a notification by `tests/fm-daemon.test.sh`: the summary reaches both `$1` and stdin, every channel is process-group bounded, and a failed channel falls through.
