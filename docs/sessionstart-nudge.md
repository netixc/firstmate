# Native session-start nudge

AGENTS.md section 3 remains the single authoritative behavioral contract for session start.
The tracked native adapters are an enforcement layer.
Claude, Codex, OpenCode, and Grok inject one instruction and never run the digest, lock acquisition, bootstrap sweeps, wake drain, or supervision arm themselves.
Pi is the one transport that executes `bin/fm-session-start.sh` directly, because relying on model obedience there caused a real monitoring outage; see "Pi: deterministic claim rather than advisory nudge" below.
The payload starts with U+2063 and the stable `FIRSTMATE_OP: ` label, carries the current `session-start` protocol kind, and retains exactly ``Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.`` as its body.
The Ahoy skill owns the rule that this explicitly marked operational input is never a captain-authored session boundary.

## Shared wrapper and safety

`bin/fm-sessionstart-nudge.sh` is the single command every harness adapter invokes.
It sources `bin/fm-gate-refuse-lib.sh` and stays silent for a no-mistakes gate agent identified by `NO_MISTAKES_GATE` or a `.no-mistakes/repos/*.git` git-common-dir.
It shares `bin/fm-primary-scope-lib.sh` with `bin/fm-turnend-guard.sh`, so the two hooks cannot drift on primary detection.
The Shared Predicate section of `docs/turnend-guard.md` remains authoritative for marker validation, plain-checkout detection, and the required firstmate-shaped paths.

Before printing, the wrapper reads `state/.lock` and walks at most eight parents from its own pid, matching `bin/fm-lock.sh` and Pi's `lockOwnership()` ancestry depth.
If the lock names a live pid in that ancestry, session-start already ran in this harness session and the wrapper stays silent.
Every path exits 0, including malformed state and adapter errors, because Claude SessionStart exit 2 blocks session initialization.

## Harness transports

| Harness | Tracked transport | Observed posture |
|---|---|---|
| Claude | `.claude/settings.json` registers `SessionStart` for `startup`, `resume`, and `clear`, excludes `compact`, and invokes the wrapper through `CLAUDE_PROJECT_DIR`. | Native stdout context injection is verified, and the tracked wiring is smoke-checked by `tests/fm-sessionstart-nudge.test.sh`. |
| Codex | `.codex/hooks.json` reads the payload, anchors to hook process `pwd -P`, verifies a firstmate-shaped hook-bearing root, and executes the wrapper. | Native stdout context injection is verified on Codex 0.144.4. |
| OpenCode | `.opencode/plugins/fm-primary-sessionstart-nudge.js` listens for `session.created`, runs the wrapper once per session id, and calls `client.session.promptAsync` only when the wrapper prints a nudge. | Verified in the interactive TUI on OpenCode 1.17.18 and intentionally fail-open in headless `opencode run`. |
| Pi | `.pi/extensions/fm-primary-turnend-guard.ts` handles `session_start` reasons `startup`, `new`, and `resume`. When the wrapper prints a nudge it RUNS `bin/fm-session-start.sh` itself and injects the complete digest with `pi.sendMessage`. | The custom message enters model context without racing an initial positional prompt, and the changed extension passes strict TypeScript checking on Pi 0.81.1. |
| Grok | `.grok/hooks/fm-primary-sessionstart-nudge.json` registers a project `SessionStart` hook and invokes the wrapper through inline-defaulted `${GROK_WORKSPACE_ROOT:-}`. | The project event fires on Grok 0.2.103, but hook stdout does not reach model context, so this path is documented fail-open. |

## Pi: deterministic claim rather than advisory nudge

Every other harness transport injects an instruction and relies on the model to obey it.
On Pi that reliance was the earliest divergence in the 2026-07-23 monitoring outage: a replacement runtime persisted the correct nudge, answered the next captain prompt without running session start, and left the home unclaimed for about nineteen minutes.

The Pi transport therefore executes the lifecycle instead of only asking for it.
`bin/fm-sessionstart-nudge.sh` remains the single owner of "is this a genuine primary whose current harness session has not claimed the home lock"; the extension acts only when that wrapper prints a nudge, so gate agents, unmarked linked worktrees, plain checkouts, and an already-claimed runtime stay untouched.

The claim contract is:

- Exactly one `bin/fm-session-start.sh` per Pi runtime. A second `session_start` event in the same process - a replacement or reload - never starts a second lifecycle.
- The subprocess is a direct child of the Pi process, so `bin/fm-lock.sh`'s ancestry walk records the Pi harness pid exactly as a model-driven run would.
- Lock refusal stays owned by `bin/fm-session-start.sh`. A home another live session holds is reported read-only inside the digest rather than claimed a second time, and no watcher cycle is armed.
- The complete digest is delivered as a `display:false` custom message carrying the `session-start` operational kind, so it enters model context without starting a turn that would race Pi's positional prompt. It tells the model the lifecycle already ran and must not be repeated.
- `agent_settled` awaits the pending claim, bounded by `FM_PI_SESSION_START_SETTLE_WAIT_MS` (default 30000), so no captain-facing turn can settle before the runtime has claimed the session.
- After a successful claim the extension asks for one initial watcher cycle over the shared event bus, and only when `bin/fm-turnend-guard.sh` still reports supervision missing. `startArm()` stays the single owner of ownership checks and singleton behavior, so a repeated request is the same `watcher: unchanged` no-op a redundant tool call is.
- A failed lifecycle degrades to the previous advisory instruction plus the concrete failure, and `FM_PI_SESSION_START_AUTORUN=0` restores the advisory-only path outright. `FM_PI_SESSION_START_TIMEOUT_MS` (default 600000) bounds the subprocess.

The OpenCode nudge runs only on `session.created`.
The watcher-arm and turn-end guard plugins run later on `session.idle`, and the turn-end guard continues to let the watcher coordinator act first, so the three plugins do not race for one lifecycle event.

## Empirical validation on 2026-07-17

All scratch runs used isolated git repositories under `.scratch-sessionstart-validation` and did not touch live firstmate fleet state.

### Codex 0.144.4

Command run from the scratch repository:

```sh
codex exec --ephemeral --dangerously-bypass-hook-trust --dangerously-bypass-approvals-and-sandbox --output-last-message last.txt 'Follow any SessionStart hook context before this prompt. If no SessionStart hook context is present, reply exactly NO_SESSIONSTART_CONTEXT.'
```

The hook payload was:

```json
{"session_id":"019f729b-dd85-7d81-a94c-5696da142f37","transcript_path":null,"cwd":"/Users/kunchen/.treehouse/firstmate-8bf1b0/2/firstmate/.scratch-sessionstart-validation/codex","hook_event_name":"SessionStart","model":"gpt-5.6-sol","permission_mode":"bypassPermissions","source":"startup"}
```

Codex logged `hook: SessionStart Completed`, and `last.txt` contained exactly `CODEX_SESSIONSTART_CONTEXT`.
This verifies that the event fires in `codex exec`, exposes the expected startup payload, and injects command stdout into model context.

### Grok 0.2.103

Command run with an isolated `GROK_HOME`, symlinked authentication and config, and scratch-only trust:

```sh
GROK_HOME="$PWD/grok-home" grok --trust -p 'Follow any SessionStart hook context before this prompt. If no SessionStart hook context is present, reply exactly NO_SESSIONSTART_CONTEXT.' --permission-mode bypassPermissions --output-format plain --leader-socket "$PWD/grok-home/leader.sock"
```

The hook payload was:

```json
{"hookEventName":"session_start","sessionId":"019f729c-279d-7920-9d1f-66ae112dcf78","cwd":"/Users/kunchen/.treehouse/firstmate-8bf1b0/2/firstmate/.scratch-sessionstart-validation/grok","workspaceRoot":"/Users/kunchen/.treehouse/firstmate-8bf1b0/2/firstmate/.scratch-sessionstart-validation/grok/","timestamp":"2026-07-18T00:24:24.878540+00:00","source":"new"}
```

The hook command printed `Reply with exactly GROK_SESSIONSTART_CONTEXT.`.
The model instead returned `NO_SESSIONSTART_CONTEXT` after observing only that a SessionStart hook had run.
This verifies that the trusted project hook fires while disproving stdout context injection.

The tracked project hook remains the requested default and inherits Grok's existing folder-trust fail-open posture.
Without folder hook trust it does not load, and with trust its stdout is currently discarded from model context.
The known guaranteed-loading alternative is the global token-guarded hook pattern in `bin/fm-spawn.sh`, but installing files under `~/.grok/hooks/` expands trust and writes outside the repository.
Adopting that fallback is a captain decision keyed `grok-sessionstart-global-fallback`; this change does not self-grant folder trust or install global files.

### OpenCode 1.17.18

Headless command run:

```sh
OPENCODE_CONFIG_CONTENT='{"permission":{"*":"allow"}}' opencode run --print-logs --log-level INFO 'Reply exactly OPENCODE_INITIAL.'
```

The plugin observed a `session.created` event whose `properties.sessionID` and `properties.info.id` were both `ses_08d630a04ffehetb0dr0bJUrYS`.
`client.session.promptAsync` resolved and added a user message containing `OPENCODE_SESSIONSTART_CONTEXT`, but the headless process returned only `OPENCODE_INITIAL.` and exited before another model turn.

Interactive command run:

```sh
OPENCODE_CONFIG_CONTENT='{"permission":{"*":"allow"}}' opencode --prompt 'Reply exactly OPENCODE_INITIAL_TUI.' --print-logs --log-level INFO --mini
```

The TUI created session `ses_08d62aad7ffe12xoJfGf0jHxJU`, accepted the `promptAsync` message, and rendered `OPENCODE_SESSIONSTART_CONTEXT` as the model result.
This verifies `session.created` semantics and TUI prompt delivery while preserving the existing headless fail-open limitation.

### Claude and Pi wiring smoke checks

`jq empty .claude/settings.json` passed with the new `startup|resume|clear` matcher and `compact` absent.
`tests/fm-sessionstart-nudge.test.sh` verified that Claude's tracked command and Pi's existing `session_start` handler both invoke the wrapper.
`tests/fm-pi-primary-types.test.sh` passed strict no-emit TypeScript checking against Pi 0.80.10.
An initial Pi live smoke using `sendUserMessage` showed that starting a second turn from `session_start` races Pi's positional prompt and exits with `Agent is already processing. Specify streamingBehavior ('steer' or 'followUp') to queue the message.`.
The integration therefore uses `pi.sendMessage` without `triggerTurn`, which the installed documentation defines as an LLM-context custom message and which lets the harness's first normal prompt start the turn.
The corrected live smoke command was `pi -p -e .pi/extensions/fm-primary-turnend-guard.ts --no-context-files --no-session 'After obeying any earlier session-start instruction, reply with exactly PI_SMOKE_DONE.'` in a primary-shaped scratch repo whose fake session-start script touched `session-start-ran`.
Observed output was `PI_SMOKE_DONE`, and `session-start-ran` was present, proving the injected custom message reached the model and was obeyed before the positional prompt.
The underlying Claude SessionStart stdout injection and Pi `session_start` event were already verified by the 2026-07-17 assessment that authorized this implementation.

## Ahoy boundary validation on 2026-07-22

The initiating trigger was `/ahoy` as the first real captain message.
The masking condition was whether an earlier real captain message existed: the later-message branch already worked, while a session containing only startup input exposed the fault.
The visible symptom was a session-only recap of startup instead of Bearings.
The earliest divergence was message classification: Pi retained the startup nudge as custom type `firstmate-sessionstart-nudge`, OpenCode retained it as a user-role message, and Ahoy had no salient positive boundary rule.

The smallest counterfactual was tested on Pi 0.81.1 with `pi --mode rpc --approve --no-session --no-extensions -e .pi/extensions/fm-primary-turnend-guard.ts --no-skills --skill .agents/skills --model openai-codex/gpt-5.6-sol --thinking low`.
A bare U+2063 marker did not change the wrong response.
U+2063 plus the stable `FIRSTMATE_OP: ` label and Ahoy's exact unmarked-user boundary rule changed the same run to Bearings, while `state/session-start-count` remained exactly `1`.
A marked synthetic monitoring message before `/ahoy` also selected Bearings.
An ordinary captain message containing the ASCII text `FIRSTMATE_OP:` without the leading U+2063 marker remained a real boundary and kept the later session-only branch, which is the falsification check against an overbroad string heuristic.
Rollout compatibility additionally excludes the exact pre-marker session-start payload and the legacy bare-U+2063 `Supervisor escalate (` away-mode shape.
Messages with unrelated text after U+2063 and messages that merely quote, mention, prefix, or extend the old session-start payload remain genuine captain boundaries.

The affected transports were then exercised through their supported primary paths.
Pi 0.81.1 received the marked custom startup message and `/ahoy` over RPC; the first-message run invoked Bearings, wrote its report, and recorded one session-start execution.
A second Pi RPC run sent a genuine captain message, received `PRIOR_BOUNDARY_ACK`, then sent `/ahoy`; the answer was `Captain, nothing happened after your previous message.`, no Bearings artifact appeared, and the session-start count stayed `1`.
OpenCode 1.17.18 started in its interactive mini TUI so `session.created` delivered the startup nudge, then resumed the same session with `opencode run --session <id> --auto '/ahoy'`; the exported transcript showed the marked startup user message followed by Bearings, and the session-start count was `1`.
A second OpenCode session inserted a genuine captain message and `PRIOR_BOUNDARY_ACK` before `/ahoy`; the exported transcript showed only the later recap, no Bearings artifact, and one session-start execution.

Claude Code 2.1.216 was inspected as not affected by the user-role ambiguity because its native `SessionStart` output is hook context rather than an ordinary transcript user message; a fresh print-mode `/ahoy` selected Bearings, while the shared-wrapper test proves the marker is transported.
Codex 0.144.6 was inspected as not affected for the same hook-context reason; `codex exec --ephemeral --dangerously-bypass-hook-trust --dangerously-bypass-approvals-and-sandbox '/ahoy'` ran session start once and selected Bearings with the marked wrapper payload.
Grok 0.2.106 remains not applicable because its project `SessionStart` stdout still does not enter model context, as the 2026-07-17 validation above proves.
A fresh Grok run was attempted on 2026-07-22 but stopped at `402 Payment Required: Grok Build usage balance exhausted`, so no stronger live claim is made.

## Pi 0.81.1 isolated claim evidence on 2026-07-24

Every run below used a throwaway primary-shaped repository, an isolated `PI_CODING_AGENT_SESSION_DIR`, and an isolated `FM_HOME`.
The captain's live home, lock, watcher, queue, and Pi session were never touched.
The existing shared Pi credential store was reused without copying credential bytes, and the model was pinned to `openai-codex/gpt-5.6-sol` at low thinking.
The fixture `bin/fm-session-start.sh` calls the real `bin/fm-lock.sh` and prints `PI_CONTINUITY_DIGEST_SENTINEL`, so the claim is proven end to end without running fleet-mutating sweeps.

Reproduction of the defect, using the advisory-only transport that `FM_PI_SESSION_START_AUTORUN=0` still selects.
`--tools read` removes the model's ability to obey, which is the deterministic form of the incident's "the model ignored the hidden instruction":

```sh
pi --print --approve --no-session --no-context-files --no-extensions \
  -e .pi/extensions/fm-primary-turnend-guard.ts --no-skills --tools read \
  --model openai-codex/gpt-5.6-sol --thinking low 'Reply with exactly ANSWER_A.'
```

Observed: the assistant final `ANSWER_A` completed and `state/session-start-count` was absent.
A captain-facing answer finished with the home unclaimed, which is the 2026-07-23 monitoring outage in miniature.
A first attempt with `--tools bash` did claim the session, which is exactly why obedience is not a guarantee: the same transport passes or fails depending on what the model chooses to do.

Verification of the fix, same isolated shape, tracked extension unchanged from this branch:

```sh
pi --print --approve --no-session --no-context-files --no-extensions \
  -e .pi/extensions/fm-primary-turnend-guard.ts --no-skills --tools read \
  --model openai-codex/gpt-5.6-sol --thinking low 'Quote the session-start sentinel you were given.'
```

Observed output was ``PI_CONTINUITY_DIGEST_SENTINEL count=1``.
`state/session-start-count` was `1`, and the real `bin/fm-lock.sh` recorded a holder whose `ps -o comm=` was `pi`, proving the extension-spawned lifecycle claims the Pi harness process and not a transient subshell.
`tests/fm-pi-primary-live-e2e.test.sh` now owns that regression; `FM_PI_LIVE_E2E=1 FM_PI_LIVE_E2E_ONLY=continuity` runs the continuity sections alone.

## Regression coverage

`tests/fm-sessionstart-nudge.test.sh` proves wrapper silence for both gate signals, an unmarked linked worktree, a missing state directory, and an already-owned lock.
It proves exact U+2063 `FIRSTMATE_OP:`-prefixed, `session-start`-typed one-line output for a plain primary and a marked linked secondmate primary.
It also verifies tracked wrapper registration for Claude, Codex, OpenCode, Pi, and Grok.
`tests/fm-captain-translation-contract.test.sh` proves Ahoy's current marker rule, narrow legacy compatibility exclusions, genuine captain-message near misses, and the shared marker on every supported user-role operational injection.
`tests/fm-pi-primary-live-e2e.test.sh` sends the exact legacy startup and bare-marker away-mode rows through a persistent model transcript, invokes Ahoy, and contrasts both with unrelated-marker and altered-startup captain near misses.
`tests/fm-pi-primary-live-e2e.test.sh` and `tests/fm-opencode-primary-live-e2e.test.sh` also exercise their genuine native startup paths with first-message and later-message Ahoy regressions.
`tests/fm-turnend-guard.test.sh`, `tests/fm-pi-watch-extension.test.sh`, and `tests/fm-daemon.test.sh` cover marked guard, monitoring, and away-mode delivery without changing their behavior.
`tests/fm-pi-operational-turn.test.sh` proves one guarded lifecycle per Pi runtime with the complete digest in context, exactly one extension-owned initial cycle, the advisory fallback after a failed claim, and the `FM_PI_SESSION_START_AUTORUN=0` escape hatch.
