---
name: pi-operations
description: >-
  Agent-only reference for Firstmate Pi operations.
  Use before spawning or recovering a crewmate or secondmate, handling a Pi trust dialog, sending a Pi-specific skill invocation, interrupting or exiting an agent, resuming an exited agent, or verifying Pi behavior.
  Contains verified facts for Pi.
user-invocable: false
metadata:
  internal: true
---

# pi-operations

Use this reference before a Pi-specific Firstmate operation: spawn, recovery, trust-dialog handling, skill invocation, interrupt, exit, resume, or verification.

Crewmates, scouts, and secondmates run Pi directly.
Optional dispatch profiles in `config/crew-dispatch.json` select concrete model and effort axes at intake.
When a matched rule or default is a profile array, load `quota-array-dispatch` for the completion-aware candidate choice after this skill establishes Pi model and provider facts.
The captain may override model or effort at session start or later.
The [`secondmate-provisioning` skill](../secondmate-provisioning/SKILL.md) owns the complete inherited-local-material allowlist and propagation contract.
Inheritance copies `config/crew-dispatch.json`, so secondmates apply the same best-fit Pi model and effort rules for their own crewmates.

Pi launch mechanics, including the launch command, model and effort flags, and enabled crewmate turn-end hook, live in `bin/fm-spawn.sh`.
Pi lifecycle mechanics are owned by `bin/fm-control-lib.sh` and delivered by `bin/fm-control.sh <task-id> interrupt|exit|relaunch`.
Never hand-type an interrupt key or exit command through `fm-send`: a routing-marked lifecycle command becomes chat the agent reasons about instead of executing, which is the defect the control plane exists to remove ([`docs/agent-control.md`](../../../docs/agent-control.md)).
The primary-session "no turn ends blind" guard contract and Pi hook installation paths live in `docs/turnend-guard.md`.
The primary-session watcher wake protocol is rendered from `docs/supervision-protocols/pi.md` by `bin/fm-supervision-instructions.sh`.
`bin/fm-busy-lib.sh` owns the busy-state contract, including verdicts, source attribution, and verification gates.

`--harness`, positional worker-runtime selection, `config/crew-harness`, and `config/secondmate-harness` are retired.
Do not reinterpret any of them as Pi.
If the captain asks for another worker runtime, explain that production spawn supports only Pi and treat adding one as a separate product change.

## Admission

Primary session start admits Pi directly from its verified environment marker or exact Pi process ancestry.
Worker launches do not resolve a runtime because Pi is fixed.
Current task records omit a worker-runtime selector; historical `harness=pi` remains compatible, while every other recorded value is preserved and refused.

## Primary turn-end guard

The primary Pi integration has an empirically validated hook path for the "no turn ends blind" guard.
It exposes passive lifecycle callbacks and forces one bounded follow-up when the shared predicate blocks.
The exact hook files, commands, scoping rules, and fail-open tradeoffs are owned by `docs/turnend-guard.md`.
`docs/verification/supervision.md` "Turn-end guard" owns active validation evidence.
When changing a primary turn-end hook, validate the real Pi behavior in a scratch project or throwaway home before trusting it, then update that doc and the relevant concise fact below.

## Primary pre-arm seatbelt

The primary Pi integration has wired PreToolUse-equivalent hooks that deny a watcher-arm anti-pattern before it runs.
They block by returning `{block: true}` from `tool_call`.
The exact hook files, commands, output-shaping quirks, and validation transcripts are owned by `docs/arm-pretool-check.md`.
When changing a watcher-arm hook, validate the real Pi behavior in a scratch project before trusting it, then update that doc.

## Primary session start and supervision

AGENTS.md section 3 remains the behavioral owner for session start.
Before inspecting or changing session-open behavior, read `docs/sessionstart-nudge.md`, the single owner of Pi delivery, source routing, the runtime bound, and fail-open behavior.
`docs/verification/supervision.md` "Native session-start delivery" owns active dated commands, payloads, and evidence.

At session start, `bin/fm-session-start.sh` prints the Pi watcher supervision block.
Pi uses the tracked `.pi/extensions/fm-primary-turnend-guard.ts` and `.pi/extensions/fm-primary-pi-watch.ts`, both project-local extensions the Pi engine auto-discovers once trusted.
When changing primary watcher behavior, update `docs/supervision-protocols/pi.md`, `docs/turnend-guard.md` if a shared idle or turn-end hook changed, and the relevant concise fact below.

## Model and effort axes

`bin/fm-spawn.sh` accepts concrete `--model` and `--effort` values chosen by Firstmate at intake.
Do not make shell scripts parse or match natural-language dispatch rules.

Effort precedence is an explicit per-task captain instruction first, then any applicable standing dispatch profile or secondmate pin, then the generic fallback below.
Never replace an effort value supplied by either higher-precedence source.
Use `low` for well-understood work with an explicit bounded path and `xhigh` for ambiguous investigation or design.
Choose intermediate levels proportionally as complexity, uncertainty, blast radius, or open-ended reasoning increases.
Never select `max` from this fallback; use it only when the captain has explicitly expressed that per-task or standing preference.

Pi uses `--model <model>` and `--thinking <low|medium|high|xhigh|max>`.
The recorded model provider does not select a worker runtime: `model=xai/grok-*` is still Pi using xAI.
Establish which credential store a tuple reads from Pi's model catalog plus `quota-axi auth --json`'s per-provider sources, and show that reasoning rather than inferring it from a model or source name.

Run `pi --list-models [search]` to discover supported models in the current authenticated environment.
Pi's installed `docs/models.md` owns how built-in, extension-registered, and custom provider/model entries reach that list.
A listing that reaches the account and does not contain the model is concrete evidence the model is unsupported; block that candidate and quote the result.
A discovery surface you could not reach establishes nothing; report that as uncertainty.

## no-mistakes skill invocation

Pi has no separate verified skill invocation beyond normal command behavior.
Use natural language if the exact skill command is uncertain.

## Verified Pi facts

Pi busy state comes from the Firstmate-owned extension's `agent_start` event and `agent_settled` confirmed by `ctx.isIdle()`, which covers retries, compaction, tool loops, and queued continuations.
Pi exits with `/quit` and interrupts with one `Escape`.
Pi has no permission system, so crewmates are always autonomous.
Pi's `packages/coding-agent/docs/settings.md` documents `regular` as the `tuiMode` default and `fullscreen` as experimental; fullscreen can bury steers by rewriting scrollback, so Firstmate avoids it when the installed CLI supports the override.
`fm-spawn.sh --help` owns the executable-pinning and version-safe launch mechanics.
Herdr native agent registration is the recovery-grade Pi liveness source; ambiguous or unreadable identity never authorizes recovery.
Keep the brief as one positional argument because multiple positional arguments become separate queued messages.

Project trust can still appear for a fresh target's own local resources, but Pi loads Firstmate's explicit external worker extension before that decision and the extension does not create a trust prompt.
`fm-spawn` explicitly loads `.pi/worker-extensions/fm-worker-lifecycle.ts` outside primary auto-discovery and gives it one validated task-metadata path; `bin/fm-busy-lib.sh` remains the lifecycle contract owner.
Pi sets `PI_CODING_AGENT=true` for its children.

**Primary-session guard fact (verified 2026-07-09, Pi 0.80.5).**
The primary's `.pi/extensions/fm-primary-turnend-guard.ts` listens for logical-run `agent_settled`, not per-tool-loop `turn_end`, and uses `pi.sendUserMessage(..., { deliverAs: "followUp" })` to force one guarded follow-up when `bin/fm-turnend-guard.sh` returns 2.
Without `deliverAs: "followUp"`, Pi rejects the send while the agent is still processing.
Pi's primary watcher protocol also requires `.pi/extensions/fm-primary-pi-watch.ts`.
The model arms through `fm_watch_arm_pi`, never a foreground bash arm; the watcher tool result and clean-exit fallback are owned by `docs/supervision-protocols/pi.md`.
`bin/fm-session-start.sh` reports when the live Pi session has not loaded both extensions and points at Pi after project trust as the fix, with `-e` as a trust-free fallback.
When a secondmate is launched, `fm-spawn.sh --secondmate` launches Pi with both `-e .pi/extensions/fm-primary-turnend-guard.ts` and `-e .pi/extensions/fm-primary-pi-watch.ts`, both already present in the secondmate home's git worktree.
