# Watcher continuity

The watcher remains intentionally one-shot: one actionable reason closes one watcher cycle.
Must-work continuity now lives above that process boundary instead of depending on the model remembering a re-arm step.

## Ownership

Pi's `.pi/extensions/fm-primary-pi-watch.ts` and OpenCode's `.opencode/plugins/fm-primary-watch-arm.js` own continuous re-arm after an actionable child close.
Each adapter starts the next arm before delivering the wake prompt, checks current session-lock ownership at launch, preserves one child or scheduled retry at a time, and applies bounded exponential retry after an unexpected or failed close.
A failed follow-up never cancels continuity restoration.

## Actionable wake ordering

After an actionable Pi or OpenCode child close, the adapter starts and verifies one singleton successor before it delivers the original wake.
It waits at most one readiness timeout per attempt, then sends TERM and waits a bounded retirement confirmation before the next lock-verified exponential retry.
If the unready arm does not retire within that bound, the adapter keeps ownership, starts no overlapping retry, and delivers the typed fallback immediately.
When that retained arm later closes, its actual close is classified as a new supervised event without replaying the earlier fallback.
After the configured retry bound is exhausted, it delivers the original wake with a typed continuity-restoration failure even if every successor arm hung without reporting readiness.
This is deliberate Option B ordering: the fleet is protected before the model handles the wake whenever restoration succeeds, but the model is never left blind when it does not.

## Single-flight operational turns on Pi

Pi documents every queued follow-up as starting another agent turn, so N wakes used to produce N turns.
On 2026-07-23 that turned into repeated captain-facing answers: an assistant final, a hidden watcher input, a byte-identical final, another hidden input, and a third identical final.
`.pi/extensions/lib/fm-operational-turn.ts` closes that by coalescing.

While one operational follow-up is queued or in progress, another wake never queues a second turn:

- The durable wake queue is never touched. The watcher enqueues before it prints an actionable reason, so a coalesced ordinary wake is still delivered - by the drain the single operational turn performs.
- Only extension-generated text no queue record can replay, currently a typed `watcher: FAILED` continuity report, is retained and carried into the next follow-up.
- Successor continuity is untouched. The latch wraps prompt delivery only, so `restoreAfterActionableClose` still starts and verifies one successor before anything is delivered, and a failed follow-up still never cancels restoration.
- Pi's busy-turn queue behavior is preserved: the presentation row appends immediately while the context-bearing custom message appends when Pi dequeues it, and only the latter starts the follow-up turn.
- The latch is time-bounded by `FM_PI_OPERATIONAL_LATCH_MAX_MS` (default 300000), so a Pi session that somehow loses its settle owner resumes delivering wakes rather than going permanently quiet.

Pi loads each extension through its own jiti instance with `moduleCache: false`, so the two extensions hold two module instances of that library.
State is mirrored over the shared `pi.events` bus, which dispatches synchronously through a Node `EventEmitter`, so a claim taken in one extension is visible in the other before the claiming call returns.
`.pi/extensions/fm-primary-turnend-guard.ts` owns `agent_settled` and is therefore the single settle owner; `docs/turnend-guard.md` owns what it does there.

Claude retains its native tracked background-task completion path.
Its new PreToolUse continuity gate allows wake drain, arm recovery, and independently fail-closed teardown, but refuses other fleet commands while tasks are in flight and no identity-matched live watcher holds the home lock.
Allowing an ordinary literal teardown prevents a terminal wake from creating a recovery circle: forced or dynamically constructed teardown remains blocked, ordinary teardown itself still refuses dirty, unlanded, incomplete-scout, and unresolved-decision cases, and the turn-end guard continues to require supervision for any tasks left in flight.
Codex retains its bounded foreground checkpoint protocol.
Grok retains its tracked background-task notification protocol.
No adapter starts a replacement with shell `&`.

The shared shell guard and non-Pi adapters are unchanged.
They remain the final backstop rather than the normal continuity mechanism; Pi's changed settle adapter is owned by `docs/turnend-guard.md`.

## Arm-layer cycle contract

`bin/fm-watch-arm.sh` never returns a clean empty success.
An actionable child output returns that reason normally.
A zero/empty child return rechecks the home lock and beacon, attaches to a verified healthy successor when one exists, or emits `watcher: FAILED - cycle ended without an actionable reason` and exits nonzero.
An attached arm follows verified identity-matched successors and reports the same typed failure if that chain ends without one.

The arm layer appends one tab-separated record per observed cycle to `state/.watch-cycle-exits.log`.
Each record includes arm and watcher PIDs, start and end timestamps, exit code and signal, classified reason, beacon age, lock identity before and after close, and successor disposition.
The file is size-capped through `FM_WATCH_CYCLE_LOG_MAX_BYTES` and `FM_WATCH_CYCLE_LOG_KEEP_LINES`.
`state/.watch-triage.log` remains only the watcher's bounded absorbed-wake debug log and carries no lifecycle semantics.

The default 300-second grace is unchanged.
Only the watcher process touches `state/.last-watcher-beat`; no helper process can make a wedged watcher appear healthy.

### Cross-harness and Herdr impact

Everything in this section is Pi-only by construction: the changed files are `.pi/extensions/*.ts` and `.pi/extensions/lib/*.ts`, and the only tracked scripts that name them are `bin/fm-session-start.sh`'s Pi extension-loaded reminder, `bin/fm-supervision-instructions.sh`'s emitted Pi protocol, and `bin/fm-spawn.sh`'s Pi secondmate launch template.
Claude, Codex, OpenCode, and Grok load their own tracked adapters and reference none of these files, so those paths are not applicable rather than merely untested.
No Herdr surface is touched: the extensions read `state/.lock` and `state/.wake-queue` and spawn `bin/fm-watch-arm.sh`, and they write no `state/<id>.meta`, endpoint, or lab state.

Four adjacent behaviors were checked rather than assumed:

- X mode survives because coalescing never touches the durable queue. An `x-mention` or `x-mode-error` `check:` record is drained by the single operational turn exactly as before, and `fmx-respond` still triggers on the drained record rather than on the follow-up text.
- Away mode is unaffected. The sub-supervisor daemon injects `away-supervisor` messages into the pane, which arrive as ordinary Pi input rather than through this latch, so an escalation can never be coalesced away. `bin/fm-turnend-guard.sh` already passes `--afk` to the shared repair line, and that path is unchanged.
- Watcher cleanup on exit is unchanged: the one-shot process `exit` listener and the `session_shutdown` handler still stop the arm child, and the latch owns prompt delivery only.
- Sibling-home isolation holds: every path the coordinator reads is derived from the same `FM_STATE_OVERRIDE`/`FM_HOME` resolution the extensions already used, and a Pi secondmate launched by `bin/fm-spawn.sh` claims its own marked home rather than the main one.

## Pi 0.81.1 isolated single-flight evidence on 2026-07-24

Both runs used a throwaway primary-shaped repository, an isolated `PI_CODING_AGENT_SESSION_DIR`, and an isolated `FM_HOME`, driven over Pi RPC so no tmux is required.
The captain's live home, lock, watcher, queue, and Pi session were never touched, and the model was pinned to `openai-codex/gpt-5.6-sol` at low thinking.
A fixture `bin/fm-watch-arm.sh` reported `watcher: attached`, then closed with an actionable `signal:` reason twice in quick succession before settling into a long-lived cycle.

Reproduction, against the tracked extensions before this change, with the prompt `Use the fm_watch_arm_pi tool once to start supervision, then reply with exactly ANSWER_B.`:

```text
[  5] assistant    "ANSWER_B"
[  6] custom       "firstmate-synthetic-input"
[  8] assistant    "" calls=bash
[ 10] assistant    "Wake queue drained: 0 records."
[ 11] custom       "firstmate-synthetic-input"
[ 12] assistant    "" calls=bash
[ 14] assistant    "Wake queue drained: 0 records."
{"assistantFinals":3,"operationalContextMessages":2,"presentationEntries":2,
 "repeatedFinalsSeparatedOnlyByOperationalInput":1}
```

Two actionable closes produced two hidden operational deliveries, two extra model turns, and one byte-identical repeated final.
Entry order also confirmed Pi's documented busy-turn behavior directly: the `custom` presentation row for the first wake was persisted while the turn was still streaming, and its context-bearing `custom_message` was persisted only when Pi dequeued it.

Verification of the fix, same isolated shape and the same fixture closes, now asserted by `tests/fm-pi-primary-live-e2e.test.sh`:

```sh
FM_PI_LIVE_E2E=1 FM_PI_LIVE_E2E_ONLY=continuity tests/fm-pi-primary-live-e2e.test.sh
```

Observed result: `ok - Pi 0.81.1 live E2E covered the deterministic session claim and single-flight operational turns`.
The isolated session file held exactly one operational delivery for the two closes, zero assistant finals repeated across an operational input, an empty durable wake queue after the single operational turn drained both seeded records, and a fixture arm count of at least three proving extension-owned successor continuity survived the coalescing.

The delivery shape that assertion reads changed when this repository integrated `kunchenguid/firstmate` on 2026-07-24.
That integration removed Calm's input interception, so an operational delivery is no longer a `firstmate-synthetic-input` context message paired with a presentation entry: it stays an ordinary user message carrying the canonical `bin/fm-operational-input.sh` envelope, hidden at presentation only by the Pi 0.81.1 adapter that [`docs/calm-mode-feasibility.md`](calm-mode-feasibility.md) owns.
The single-flight contract this section verifies is unchanged, and the live assertion now counts those envelope-carrying user messages instead; the count itself has not been re-observed on a credentialed run since the integration.

## Regression coverage

`tests/fm-pi-watch-extension.test.sh` checks Pi's first-cycle-or-explicit-repair tool metadata and ownership-based redundant-call no-ops, then simulates actionable and empty child closes against the actual Pi and OpenCode close handlers, blocks prompt delivery to prove the successor launches first, verifies single-flight behavior, changes the session lock before close to prove ownership is rechecked, and hangs each successor arm to prove bounded fallback delivery includes the typed restoration failure.
`tests/fm-watcher-lock.test.sh` covers verified-successor attach, the typed self-eviction failure, bounded and successor-linked lifecycle rows, and a SIGSTOP counterfactual that distinguishes a live PID from a stale beacon before classifying termination.
`tests/fm-continuity-pretool-check.test.sh` proves the Claude gate rejects only non-recovery fleet execution in the precise unhealthy state and preserves the existing Stop registration.
`tests/fm-pi-operational-turn.test.sh` drives both Pi extensions against a fake Pi that dispatches handler lists and a real synchronous event bus, and proves signal plus stale during a busy turn produce one follow-up and one drain, that records queued after that drain earn exactly one more turn, that a coalesced `watcher: FAILED` report is carried rather than dropped, and that a repeated answer is a failed delivery with one bounded retry and then a compact escalation.
`tests/fm-pi-watch-extension.test.sh`'s late-unretired-close case now asserts the coalescing side of the same contract: a late ordinary wake restores its successor without queueing a second operational turn.

## Sanitized live evidence, 2026-07-17

All five harnesses ran against git-initialized scratch projects and isolated `FM_HOME` state.
Existing harness-managed credentials remained in place, no credential bytes were copied into a fixture or transcript, and no account was created.
Pi used the existing shared Pi auth store with the explicit `openai-codex/gpt-5.6-sol` provider/model pin and low thinking.
Each run used the smallest prompt needed to exercise the harness-native path.

Harness versions:

```text
Claude Code 2.1.214
codex-cli 0.144.4
OpenCode 1.17.18
Pi 0.80.10
grok 0.2.103 (89c3d36fb6f1) [stable]
```

Claude ran an arm fixture through its native tracked background option, observed background completion, allowed the wake drain, and refused the next unrelated fleet command before its body executed.
The captured system message exactly named `[watcher-continuity]`, `bin/fm-wake-drain.sh`, tracked Claude re-arm through `bin/fm-watch-arm.sh`, and the blocked `fm-crew-state.sh` command.
Command: `FM_CLAUDE_LIVE_E2E=1 tests/fm-claude-continuity-live-e2e.test.sh`.
Observed result: `ok - Claude 2.1.214 (Claude Code) live E2E refused only the post-completion fleet command with exact re-arm guidance`.

Codex ran the real one-second foreground watcher checkpoint and returned `checkpoint: no actionable wake within 1s` without switching to the arm wrapper.
Command: `FM_CODEX_LIVE_E2E=1 tests/fm-codex-continuity-live-e2e.test.sh`.
Observed result: `ok - codex-cli 0.144.4 live E2E preserved the one-second foreground checkpoint path`.

OpenCode ran its persistent TUI plugin, established the first watcher from `session.idle`, received an actionable close, and ledger-linked a live successor before the model handled the wake.
The model executed no watcher-arm command and the turn-end backstop did not fire.
Command: `FM_OPENCODE_LIVE_E2E=1 tests/fm-opencode-primary-live-e2e.test.sh`.
Observed result: `ok - OpenCode 1.17.18 live E2E auto-started one successor before prompt handling without a model re-arm`.

Pi loaded the tracked extensions in its interactive TUI, called `fm_watch_arm_pi` once, received an actionable close, and ledger-linked a successor before the handling turn ended.
The turn-end backstop did not fire, and `/quit` removed both the watcher and arm child.
Command: `FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh`.
Observed result: `ok - Pi 0.80.10 live E2E used shared Codex auth, auto-started one successor before turn end, and cleaned up`.

Grok ran the real arm wrapper through `run_terminal_command` with its tracked background option, surfaced its native task-completion notification after the actionable close, and recorded `reason=actionable-signal` in the cycle ledger.
No shell ampersand was used.
Command: `FM_GROK_LIVE_E2E=1 tests/fm-grok-continuity-live-e2e.test.sh`.
Observed result: `ok - grok 0.2.103 (89c3d36fb6f1) [stable] live E2E preserved tracked background completion and shared ledger classification`.

The goal is continuity with fewer supervision tokens and no Pi/OpenCode model-memory re-arm step.
No zero-latency guarantee is claimed; lock verification, watcher startup, and bounded retry delays remain deliberate safety work.
