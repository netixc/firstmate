---
name: afk
description: >-
  Enter away-mode supervision when the captain invokes /afk, says they are going afk, `state/.afk` exists, an incoming message starts with the current operational prefix or a legacy bare `FM_INJECT_MARK`, or any `state/.subsuper-*` marker is involved.
  It sets a durable away-mode flag so the sub-supervisor daemon can self-handle routine wakes and escalate captain-relevant events plus bounded declared-external-wait rechecks as batched digests during walk-away stretches, then exits automatically when any real unmarked message returns firstmate to full per-wake responsiveness.
user-invocable: true
metadata:
  internal: true
---

# afk

Away mode makes the daemon's token-saving tradeoff explicit and consented.
Routine wakes are classified in bash while captain-relevant events reach Firstmate as a batched, pre-read digest.

## Enter away mode

1. Enter only through `bin/fm-afk-launch.sh`.
   It owns the durable flag, stale-artifact clearing, terminal record, and rollback.
2. For a harness with a native tracked-background tool, run `bin/fm-afk-launch.sh start-native`, then run `FM_AFK_STATE_PREPARED=1 bin/fm-afk-start.sh` through that native tool.
   If native launch fails, run `bin/fm-afk-launch.sh stop` to roll back.
3. For a harness without a native tracked-background tool, run `bin/fm-afk-launch.sh start`.
   The launcher creates a non-visible Herdr workspace, records its exact id, and passes the captain pane as `FM_SUPERVISOR_TARGET` so the daemon never injects into its helper pane.
   Never split the captain's active pane to host the daemon.
4. Do not arm another watcher.
   The daemon manages the watcher as its child and the singleton lock harmlessly absorbs a stray arm.
5. Acknowledge using `AGENTS.md` section 9 language: "Captain, away mode is active; I will batch routine updates and surface only decisions, failures, credentials, or review-ready work until you return."

Both launch paths use `bin/fm-afk-start.sh` as the daemon entry.
It exits immediately if the identity-backed lock names a live daemon; otherwise it execs `bin/fm-supervise-daemon.sh` in the foreground.
The daemon injects only while `state/.afk` exists.

## Return lifecycle

The first message without the current operational prefix or a legacy bare marker is the return signal.
Run `bin/fm-afk-return.sh` before acting on that message.
The script owns ordered daemon shutdown, durable wake drain, escalation and wedge evidence, and the return catch-up gate.
If it reports a firstmate-actionable blocker, resolve or durably reclassify it, close any decision key with `resolved [key=...]`, and run `bin/fm-afk-return.sh check`.
Resume the emitted supervision protocol while blocker handling proceeds so the gate never creates a blind wait.
Do not perform ordinary captain work until the check succeeds.

A message beginning with the current operational prefix (`FM_OPERATIONAL_PREFIX`, U+2063 INVISIBLE SEPARATOR followed by `FIRSTMATE_OP: `), or a legacy bare `FM_INJECT_MARK`, is a daemon escalation, so remain away and process it.
Re-invoking `/afk` refreshes the flag and remains away.
Bias ambiguous input toward return because a present captain takes precedence over token savings.

Away mode changes notification cadence, not approval authority.
Merges, decisions, destructive actions, and security-sensitive actions retain their normal owners.

## Operational prefix and injection contract

The daemon prefixes every current injection with `FM_OPERATIONAL_PREFIX`: `FM_INJECT_MARK`, the U+2063 invisible separator, followed by the stable `FIRSTMATE_OP: ` label.
The bare `FM_INJECT_MARK` form remains accepted for legacy daemon escalations during rollout.
The operational prefix is carried in the typed message so it works consistently across verified worker runtimes.
`strip_injection_marker` removes the current operational prefix or legacy bare marker before classification or relay.

Before every injection, the daemon uses the Herdr-only operations in `bin/fm-backend.sh` to require all of these:

- The exact supervisor pane still exists.
- Native agent state and captured-output corroboration do not show an active turn.
- `fm_backend_composer_state` returns affirmatively `empty`.

`pending` protects unsubmitted input and `unknown` protects unreadable panes and dead-shell prompts, so either defers.
`bin/fm-composer-lib.sh` owns ghost, border, prompt, and typed-content classification after the Herdr implementation identifies a composer row.
Dim, faint, and dark-truecolor suggestions are stripped before classification.
The buffered escalation remains in `state/.subsuper-escalations` and is retried on the next housekeeping tick.

The digest is typed once with Herdr's literal send and submitted with Enter through the verified-submit primitive.
Enter may be retried but the text is never retyped.
An idle native baseline is confirmed by a real working transition; unreadable or still-populated composer state never counts as delivery.
`fm-send.sh` uses the same primitive and exits nonzero when it cannot prove the steer landed.

If a buffered digest exceeds `FM_MAX_DEFER_SECS`, the daemon attempts one ordinary safe flush.
If delivery still cannot be confirmed, it logs an error, writes `state/.subsuper-inject-wedged`, and fires the configured active alert.
`docs/wedge-alarm.md` owns the alert channels and verification record.

## Classification policy

The daemon wraps `fm-watch.sh`, classifies each wake in bash, and self-handles routine events without consuming a Firstmate turn.
`bin/fm-classify-lib.sh` is the shared owner of captain-relevant verbs, pause vocabulary, signal and stale predicates, and fleet scanning.

- A `signal` with terminal `done:`, `needs-decision:`, `blocked:`, or `failed:` escalates.
- A nonterminal progress verb remains nonterminal even when its prose contains an old free-text success token.
- A declared `paused:` external wait is tracked separately and resurfaces after `FM_PAUSE_RESURFACE_SECS` if still idle.
- A `check` always escalates.
- A `stale` terminal event escalates; nonterminal progress ages toward the bounded possible-wedge threshold.
- A `heartbeat` is self-handled while the daemon's cheap fleet scan provides the catch-all.
- Unknown or uncertain input escalates fail-safe.

Escalations batch for up to `FM_ESCALATE_BATCH_SECS` and flush as one single-line digest with the current operational prefix.
Embedded newlines are collapsed before injection.
Seen-status markers deduplicate signal, stale, and scan paths without suppressing wedge aging for unchanged nonterminal work.
The portable identity-backed lock prevents duplicate daemons.

## Supervisor target

`FM_SUPERVISOR_TARGET=<session>:<pane-id>` is the explicit override.
Without it, `bin/fm-supervisor-target-lib.sh` requires `HERDR_PANE_ID` and combines it with `${HERDR_SESSION:-default}`.
The daemon refuses to start if it cannot identify or verify that Herdr pane.

## Stale artifacts and reliability

Treat `state/.subsuper-escalations`, its `.since` sidecar, and `state/.subsuper-inject-wedged` as session-scoped delivery artifacts.
Always enter through `bin/fm-afk-launch.sh`, which clears old artifacts only for a fresh entry and preserves the current buffer on refresh.
Always exit through `bin/fm-afk-launch.sh stop`, which keeps `state/.afk` present through shutdown flush and clears it last.

The durable wake queue recovers missed or crashed injections.
Wedge detection is bounded-latency rather than lossy.
Declared external waits have their own bounded recheck cadence.
The catch-all scan backs up event classification.
The daemon preserves single-instance locking, crash-loop backoff, a pane-gone guard, and signal-trapped shutdown.

`FM_INJECT_SKIP` defaults to `heartbeat` and force-self-handles matching kinds.
Use it sparingly.
