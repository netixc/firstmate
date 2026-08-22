---
name: harness-adapters
description: >-
  Agent-only reference for firstmate harness operations.
  Use before spawning or recovering a crewmate or secondmate, handling a trust dialog, sending a harness-specific skill invocation, interrupting or exiting an agent, resuming an exited agent, or verifying a new harness adapter.
  Contains verified facts for Pi.
user-invocable: false
metadata:
  internal: true
---

# harness-adapters

Use this reference before any harness-specific firstmate operation: spawn, recovery, trust-dialog handling, skill invocation, interrupt, exit, resume, or adapter verification.

Crewmates, scouts, and secondmates run Pi directly.
Optional dispatch profiles in `config/crew-dispatch.json` select concrete model and effort axes at intake.
When a matched rule or default is a profile array, load `quota-array-dispatch` for the completion-aware candidate choice after this skill establishes harness and model/provider facts.
The captain may override model or effort at session start or later.
The [`secondmate-provisioning` skill](../secondmate-provisioning/SKILL.md) owns the complete inherited-local-material allowlist and propagation contract.
Inheritance copies `config/crew-dispatch.json`, so secondmates apply the same best-fit Pi model and effort rules for their own crewmates.

Each adapter splits into mechanics and knowledge.
The per-task mechanics, including launch command, autonomy flag, and any enabled crewmate turn-end hook, live in `bin/fm-spawn.sh`.
Agent lifecycle mechanics - which key interrupts a turn, how many times it must be sent, whether the composer needs clearing afterwards, which command exits the agent, and which task kinds the adapter can run - are owned by the executable control plane in `bin/fm-control-lib.sh` and delivered by `bin/fm-control.sh <task-id> interrupt|exit|relaunch`.
Never hand-type an interrupt key or exit command through `fm-send`: a routing-marked lifecycle command becomes chat the agent reasons about instead of executing, which is the defect the control plane exists to remove ([`docs/agent-control.md`](../../../docs/agent-control.md)).
The per-adapter `Exit command` and `Interrupt` rows below remain the verification record for those values; the executable owner is what firstmate actually runs, so a newly verified adapter is not reachable by the control plane until its rows land in that owner.
The primary-session "no turn ends blind" guard contract and harness hook installation paths live in `docs/turnend-guard.md`.
The primary-session watcher wake protocols are rendered from `docs/supervision-protocols/` by `bin/fm-supervision-instructions.sh`.
The supervision knowledge lives here: busy state, exit command, interrupt, dialogs, resume behavior, skill invocation, and quirks.
Each adapter's `Busy state` row names only which semantic source that harness uses; `bin/fm-busy-lib.sh` owns the contract itself, including verdicts, source attribution, and the verification gates that keep an unverified harness at unknown.

Never dispatch a crewmate or secondmate on an unverified adapter.
If `config/crew-harness` or `config/secondmate-harness` names an unverified adapter, tell the captain under `AGENTS.md` section 9 that the requested worker runtime is not verified yet, use firstmate's own verified runtime for current work, and ask only whether to verify the requested runtime before future use.
Do not pause current work for that future-verification choice, and never launch an unverified adapter.
If the captain asks for a new harness, explain that production spawn supports only Pi and propose a separate verification and implementation task.
A new adapter is not production-reachable until its mechanics, semantic busy source, composer behavior, liveness classification, tests, and verified knowledge land together.

## Detection

`bin/fm-harness.sh` prints firstmate's own harness, using the verified `PI_CODING_AGENT=true` environment marker first and then exact Pi process ancestry.
`bin/fm-harness.sh` detects whether the current process is running under Pi; worker launches do not resolve a runtime because Pi is fixed.
`bin/fm-spawn.sh` uses `crew` mode for a crewmate/scout launch and `secondmate` mode for a `--secondmate` launch, re-resolving on every spawn so the split is durable across respawns; an explicit per-spawn harness arg overrides either.
On `unknown`, ask the captain instead of guessing.
A captain override always beats detection.
When verifying a new adapter, record its env marker and command name in `bin/fm-harness.sh`.

For stuck recovery, the target window's harness is recorded as `harness=` in `state/<id>.meta`.
Use that value for interrupt, exit, resume, and skill-invocation facts.

## Primary turn-end guard

The primary Pi integration has an empirically validated hook path for the "no turn ends blind" guard.
It exposes passive lifecycle callbacks and forces one bounded follow-up when the shared predicate blocks.
The exact hook files, commands, scoping rules, and fail-open tradeoffs are owned by `docs/turnend-guard.md`.
`docs/verification/supervision.md` "Turn-end guard" owns active validation evidence.
When changing any primary turn-end hook, validate the real harness behavior in a scratch project or throwaway home before trusting it, then update that doc and the relevant concise fact below.

## Primary pre-arm (PreToolUse) seatbelt

The primary Pi integration also has wired PreToolUse-equivalent hooks that deny a watcher-arm anti-pattern (shell `&`, truncating pipe, bundling, broad `pkill -f fm-watch`) before it runs.
They block by returning `{block: true}` from `tool_call`.
The exact hook files, commands, output-shaping quirks, and validation transcripts are owned by `docs/arm-pretool-check.md`.
When changing any watcher-arm PreToolUse hook, validate the real harness behavior in a scratch project before trusting it, then update that doc.
## Primary session start

AGENTS.md section 3 remains the behavioral owner for session start, while tracked native adapters enforce it idempotently at session open through one of two tiers.
Before inspecting or changing session-open behavior, read `docs/sessionstart-nudge.md`, the single owner of tier assignment, per-surface transports, source routing, the runtime bound, and fail-open behavior.
`docs/verification/supervision.md` "Native session-start delivery" owns active dated commands, payloads, and evidence.

## Primary watcher supervision

At session start, `bin/fm-session-start.sh` prints exactly one watcher supervision block for the detected primary harness.
Do not substitute another harness's wait shape when resuming supervision.
Pi uses the tracked `.pi/extensions/fm-primary-turnend-guard.ts` plus the tracked `.pi/extensions/fm-primary-pi-watch.ts`, both project-local extensions the Pi engine auto-discovers once trusted.
When changing any primary watcher adapter, update `docs/supervision-protocols/`, `docs/turnend-guard.md` if a shared idle or turn-end hook changed, and the relevant concise fact below.

## Launch profile axes

`bin/fm-spawn.sh` accepts concrete `--harness`, `--model`, and `--effort` values chosen by firstmate at intake.
Do not make the shell scripts parse or match natural-language dispatch rules.

Effort precedence is an explicit per-task captain instruction first, then any applicable standing dispatch profile or secondmate pin, then the generic fallback below.
Never replace an effort value supplied by either higher-precedence source.
Use the fallback only when neither the captain nor applicable standing configuration specifies effort.
Use `low` for well-understood work with an explicit bounded path and `xhigh` for ambiguous investigation or design.
Choose intermediate levels proportionally as complexity, uncertainty, blast radius, or open-ended reasoning increases.
When a verified adapter lacks `xhigh`, cap the choice at its highest supported non-`max` level rather than omitting the intended effort silently.
Never select `max` from this fallback; use it only when the captain has explicitly expressed that per-task or standing preference.

The supported launch-profile flags below are verified locally; each row records its evidence.

| Harness | Model flag | Effort flag | Notes |
|---|---|---|---|
| pi | `--model <model>` | `--thinking <low\|medium\|high\|xhigh\|max>` | Pi exposes the accepted thinking levels and completed the model-qualified max-thinking smoke. |

The concrete `harness` field owns adapter identity independently of the model provider: `harness=pi` with `model=xai/grok-*` is Pi using xAI.
No script resolves that split for you: establish which credential store a tuple reads from the discovery surfaces below plus `quota-axi auth --json`'s per-provider sources, and show that reasoning rather than inferring it from a harness, model, or source name.

### Model support discovery

Treat model and provider knowledge as current source-of-truth discovery, not as a permanent namespace or provider mapping.
Use the discovery surface in the current authenticated environment because supported and available models can change by version, account, and configuration.

| Harness | Authoritative discovery surface |
|---|---|
| pi | Run `pi --list-models [search]`; Pi's installed `docs/models.md` owns how built-in, extension-registered, and custom provider/model entries reach that list. |

For an unfamiliar harness or model namespace, establish support and provider identity from that harness's authoritative CLI help, model listing, or current documentation rather than guessing from a name or prefix.
A listing that reaches the account and does not contain the model is concrete evidence the model is unsupported: block that candidate and quote the result.
A discovery surface you could not reach establishes nothing; report that as uncertainty rather than turning it into a supported or unsupported verdict.

When a requested effort value is outside the harness-specific accepted set, `fm-spawn` records the requested `effort=` in meta but emits no effort flag for that harness.
This preserves launch success instead of passing a known-bad value.

## no-mistakes skill invocation

Send the validation skill using the target harness's skill invocation form.
Natural language is acceptable if uncertain.

- Pi has no separate verified skill invocation beyond normal command behavior; use natural language if the exact skill command is uncertain.

## Pi

| Fact | Value |
|---|---|
| Busy state | The Firstmate-owned extension's `agent_start` (busy) and `agent_settled` confirmed by `ctx.isIdle()` (idle), which covers retries, compaction, tool loops, and queued continuations. |
| Exit command | `/quit` |
| Interrupt | single Escape |

Pi has no permission system, so crewmates are always autonomous.
Pi's `packages/coding-agent/docs/settings.md` UI and display section documents `regular` as the `tuiMode` default and `fullscreen` as experimental; fullscreen can bury steers by rewriting scrollback, so Firstmate avoids it when the installed CLI supports the override.
`fm-spawn.sh --help` owns the executable-pinning and version-safe launch mechanics.
Herdr native agent registration is the recovery-grade Pi liveness source; ambiguous or unreadable identity never authorizes recovery.
Keep the brief as one positional argument.
Multiple positional args become separate queued messages; `fm-spawn`'s template already does this correctly.

Project trust can still appear for a fresh target's own local resources, but Pi loads Firstmate's explicit external worker extension before that decision and the extension does not create a trust prompt.
`fm-spawn` explicitly loads `.pi/worker-extensions/fm-worker-lifecycle.ts` outside primary auto-discovery and gives it one validated task-metadata path; `bin/fm-busy-lib.sh` remains the lifecycle contract owner.
Pi sets `PI_CODING_AGENT=true` for its children; this is its harness-detection env marker.

**Primary-session guard fact (verified 2026-07-09, Pi 0.80.5).**
The firstmate PRIMARY's own `.pi/extensions/fm-primary-turnend-guard.ts` listens for logical-run `agent_settled`, not per-tool-loop `turn_end`, and uses `pi.sendUserMessage(..., { deliverAs: "followUp" })` to force one guarded follow-up when `bin/fm-turnend-guard.sh` returns 2.
Without `deliverAs: "followUp"`, Pi rejects the send while the agent is still processing.
Pi's primary watcher protocol also requires the tracked `.pi/extensions/fm-primary-pi-watch.ts` extension, same trust-once discovery as the turn-end guard.
The model arms through `fm_watch_arm_pi`, never a foreground bash arm; the watcher tool result and clean-exit fallback are owned by `docs/supervision-protocols/pi.md`.
`bin/fm-session-start.sh` reports when the live Pi session has not loaded both the turn-end guard and watcher extensions, and points at Pi after project trust as the fix, with `-e` as a trust-free fallback.
When a secondmate is launched on Pi, `fm-spawn.sh --secondmate` launches Pi with both `-e .pi/extensions/fm-primary-turnend-guard.ts` and `-e .pi/extensions/fm-primary-pi-watch.ts`, both already present in the secondmate home's git worktree.
