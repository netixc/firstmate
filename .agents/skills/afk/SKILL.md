---
name: afk
description: >-
  Enter away-mode supervision when the captain invokes /afk, says they are going afk, `state/.afk` exists, an incoming message starts with `FM_INJECT_MARK`, or any `state/.subsuper-*` marker is involved.
  It sets a durable away-mode flag so the sub-supervisor daemon can self-handle routine wakes and escalate captain-relevant events plus bounded declared-external-wait rechecks as batched digests during walk-away stretches, then exits automatically when any real unmarked message returns firstmate to full per-wake responsiveness.
user-invocable: true
metadata:
  internal: true
---

# afk

Away-mode supervision. When invoked, `/afk` makes the daemon's token-saving
tradeoff **consented** and **explicit**: the captain is stepping away, so the
sub-supervisor may triage routine wakes in bash instead of waking firstmate's
LLM for each one. Escalations still reach the captain, but as one pre-read,
batched digest rather than per-wake injections.

## What it does

1. **Enter the lifecycle through `bin/fm-afk-launch.sh`.**
   This owns the durable state write, session-scoped stale-artifact clearing,
   terminal record, and rollback.
   The flag survives a firstmate restart, so recovery re-enters afk when it is present.

2. **Ensure the sub-supervisor daemon is running as a tracked background process.**
   Its hosting differs by harness.
   Pick the right path:
   - **Harness WITH a native in-pane tracked-background tool** (e.g. claude's
     background bash, grok's background tool): first run
     `bin/fm-afk-launch.sh start-native`, then run
     `FM_AFK_STATE_PREPARED=1 bin/fm-afk-start.sh` through that native tool.
     This is a deliberate no-separate-terminal exception because the harness-hosted job creates no terminal or layout mutation, and a shell launcher cannot invoke a harness-native background tool.
     The launcher still owns lifecycle state and records the no-terminal mode, while the daemon inherits and auto-discovers the captain pane.
     If the native launch fails, run `bin/fm-afk-launch.sh stop` to roll back the prepared lifecycle.
     Do not wrap it in `nohup ... &` (Codex/herdr can reap fire-and-forget shell children after a tool call returns).
   - **Harness WITHOUT one** (e.g. pi): run `bin/fm-afk-launch.sh start`.
     It creates a non-visible tracked Herdr `--no-focus` workspace, records its
     exact id, and passes the captain pane in as `FM_SUPERVISOR_TARGET` so the
     daemon injects into the captain, not its own new pane.
     **Never manufacture a terminal by splitting the captain's
     active pane** (`herdr pane split`): a split co-tenants the tab and visibly
     shrinks the captain's pane (docs/herdr-backend.md "Away-mode supervisor
     support").
   Both paths share `bin/fm-afk-start.sh` as the daemon entry.
   The native path tells it that the launcher already prepared lifecycle state; the terminal-backed path lets the entry perform its existing state setup inside the new terminal.
   It exits immediately if the identity-backed daemon lock already names a live process, otherwise it execs `bin/fm-supervise-daemon.sh` in the foreground.
   The daemon is **presence-gated**: it injects escalations only while
   `state/.afk` exists, and stays quiet otherwise.

3. **Do not separately arm `fm-watch.sh`.** The daemon manages the watcher as
   its child; the singleton lock no-ops a stray arm harmlessly.

4. **Acknowledge** in `AGENTS.md` section 9 language: "Captain, away mode is active; I will batch routine updates and surface only decisions, failures, credentials, or review-ready work until you return."

## How to exit afk

No `/back` is needed. The first genuine message is the return signal:

- A message **without** the current operational prefix or a legacy bare marker, and **not** starting with `/afk` -> the captain is back.
  Run `bin/fm-afk-return.sh` before acting on the message that brought the captain back.
  That script owns correct-ordered daemon shutdown, durable wake draining, escalation and wedge evidence, and the return-catch-up gate.
  If it reports a firstmate-actionable `blocked:` event, remediate it immediately through the normal lifecycle, or explicitly reclassify it with a durable reason and close its decision key with `resolved [key=...]`, then run `bin/fm-afk-return.sh check`.
  Once the daemon stops, resume full per-wake responsiveness through the emitted primary-harness supervision protocol while blocker handling proceeds, so the gate never creates a blind wait.
  Do not answer a Bearings request or perform any other ordinary captain work until the check exits successfully.
- A message **with** the current operational prefix (`FM_OPERATIONAL_PREFIX`, U+2063 INVISIBLE SEPARATOR followed by `FIRSTMATE_OP: `), or a legacy bare `FM_INJECT_MARK` daemon escalation -> stay afk and process it.
- Re-invoking `/afk` while already away -> stay afk (refresh the flag); this
  does **not** trigger an exit.

Bias ambiguous cases toward exit: a present captain beats token savings, and
a false exit is self-correcting (the captain re-runs `/afk`).

## Orthogonal to approval authority

afk changes how aggressively firstmate surfaces things, **not who approves what**.
"Away" never means "approves more" or "approves less."
A PR ready for merge or a needs-decision finding keeps the same configured authority and exceptions from `AGENTS.md` section 7, while anything requiring the captain still waits for the captain's explicit word.
The daemon only batches the notification.

## Operational prefix contract

The daemon constructs every current injection as the `away-supervisor` kind owned by `bin/fm-operational-input.sh`, beginning with `FM_OPERATIONAL_PREFIX`: `FM_INJECT_MARK` (U+2063 INVISIBLE SEPARATOR) followed by the stable `FIRSTMATE_OP: ` label.
The bare `FM_INJECT_MARK` form remains accepted for legacy daemon escalations during rollout.
U+2063 has no normal keyboard keystroke and survives terminal transport as UTF-8 text.
This is how firstmate tells a daemon escalation apart from a real message in the same pane.
The operational prefix travels with the message text; it does not rely on harness-level typed-vs-injected detection, which is not portable across Claude Code, Codex CLI, Grok, and Pi.

## Busy-guard and composer guard

The daemon never injects into an in-use pane. Two checks run before every
injection, dispatched through `bin/fm-backend.sh` for the Herdr supervisor pane:

- **Primary-pane busy guard** - `pane_is_busy` trusts Herdr native `busy` when available, otherwise matches rendered output against only the detected primary harness's signature.
  This narrow delivery guard never classifies a recorded worker task and never uses a global union of vendor patterns.
- **Composer-state guard** - `inject_msg` reads the full `empty`/`pending`/`unknown` verdict from `fm_backend_composer_state` and injects only when it is affirmatively `empty`.
  `pending` means real unsubmitted text, while `unknown` includes an unreadable pane and a bare shell prompt left after the agent exits, so both defer.
  The shared `bin/fm-composer-lib.sh` owns the content decision after the Herdr adapter captures and structurally identifies the composer's own row.
  It preserves idle bordered composers such as claude's `│ > … │` and bare agent glyphs as empty, but a bare shell glyph is unknown unless inside a genuine bordered composer box; see `docs/herdr-backend.md` "Composer and injection safety" for the complete contract.
  `pane_input_pending` remains the tested predicate for callers that only need to know whether real unsubmitted text is present, but it is insufficient for an injection-safety decision because it cannot distinguish `empty` from `unknown`.

A busy primary pane, or any composer verdict other than `empty`, defers the injection; the buffered escalation survives in `state/.subsuper-escalations` and is retried on the next housekeeping tick.
In afk mode the composer guard is belt-and-suspenders (no human is typing), but it protects against the race window between the captain returning and their message landing, a dead shell, and the daemon's own previous injection sitting unsent.

**Max-defer escape (the daemon must never silently wedge).**
If anything stays buffered past `FM_MAX_DEFER_SECS` (default 300), the daemon
attempts one normal flush, which still requires an idle pane and an affirmatively empty composer.
The alarm is defense in depth rather than a substitute for keeping every genuinely idle supported composer injectable.
If that submit cannot be confirmed, it raises a loud, rate-limited wedge alarm:
an ERROR in the daemon log, a durable
`state/.subsuper-inject-wedged` marker (surface it on the "while you were out"
catch-up if present) and a configurable pane-independent active alert.
`docs/wedge-alarm.md` owns the alert channel setup, and `docs/verification/supervision.md` "Wedge-alarm channels" owns active evidence.
So a guard false-positive becomes a visible stall, never an unbounded silent no-op.

## Submit model

The digest is typed once with Herdr's literal non-submitting text primitive, then submitted with Enter and verified.
Enter is retried without retyping until native agent state shows that a turn started or the conservative composer fallback confirms clearance.
A bordered-empty or ghost-only composer is recognized as empty, while pending or unreadable input preserves the escalation for retry.
`fm-send.sh` uses the same primitive and exits nonzero when delivery cannot be confirmed.

## Classification policy

The daemon wraps `fm-watch.sh`, runs the watcher as a child, classifies each
wake reason in bash, and self-handles the routine majority without consuming a
firstmate turn.
Captain-relevant events, plus a bounded recheck of a declared external wait that remains idle, escalate to firstmate's context as one pre-read, single-line, batched digest.
The classification predicates (the captain-relevant verb set, declared-pause vocabulary, signal/stale tests, and fleet-scan) live in the shared `bin/fm-classify-lib.sh`, the same library the always-on watcher uses for its own triage when afk is off, so the two modes apply one identical policy.
While `state/.afk` exists the daemon owns the watcher, so the watcher reverts to one-shot and lets the daemon do the triage - the two never run their triage at the same time.

Classify each wake this way:

- `signal` with a terminal captain verb (`done:`, `needs-decision:`, `blocked:`, or `failed:`) -> escalate.
  A nonterminal progress verb remains nonterminal even when its prose contains a legacy free-text token such as `PR ready`, `checks green`, `ready in branch`, or `merged`; only a bare legacy line with such a token escalates.
  Other signals with no captain-relevant status -> self-handle.
- `signal` or `stale` for a declared `paused:` external wait -> self-handle and track the pause rather than a wedge.
  If it remains declared and idle past `FM_PAUSE_RESURFACE_SECS` (default 3600s), housekeeping sends one awaiting-external recheck and resets the pause window.
- `check` -> always escalate. Check scripts print only when firstmate should wake.
- `stale` with a terminal status or bare legacy captain-relevant line -> escalate.
  Nonterminal progress remains transient even when its prose contains a legacy free-text token or its seen-status marker already matches, so record a marker and self-handle.
  If the pane is still idle past `FM_STALE_ESCALATE_SECS` (default 240s), housekeeping escalates it as a possible wedge.
  This bounds wedge-detection latency to the threshold plus a tick: a delay, never a loss.
  Healthy crewmates are autonomous and do not wait on firstmate mid-task.
- `heartbeat` -> self-handle. The daemon runs its own cheap bash fleet scan
  every `FM_HEARTBEAT_SCAN_SECS` (default 300s) as the catch-all for a
  captain-relevant status line the per-wake classifier might miss.
- Unknown reason, or any uncertainty -> escalate fail-safe.

Escalations are buffered up to `FM_ESCALATE_BATCH_SECS` (default 90s; 0 =
immediate) and flushed as one single-line digest prefixed with the current
operational prefix, carrying pre-read status summaries and a recommended action.
The single-line format makes the submission unambiguous across harnesses, and
the operational prefix lets firstmate distinguish it from a real captain message.

## Injection hardening

- **Single-line digest** - embedded newlines are collapsed before injection.
- **Busy and composer guards** - only an affirmatively empty Herdr agent composer permits injection; pending, unknown, unreadable, and bare-shell states preserve the buffer.
- **Shared composer owner** - Herdr routes ANSI-styled candidate rows through `fm_composer_strip_ghost` before `bin/fm-composer-lib.sh` classifies them, so de-emphasized placeholders disappear without admitting an unbordered shell prompt.
- **Max-defer escape** - after `FM_MAX_DEFER_SECS`, a failed normal flush writes the durable wedge marker and emits the configured pane-independent alert.
- **Verified type-once submit** - only Enter is retried, and the buffer clears only after the Herdr adapter reports confirmed delivery.
- **Marker strip** - current and legacy operational markers are removed before classification or relay.
- **Portable singleton lock** - the daemon uses `fm-wake-lib.sh` rather than a platform-specific lock tool.
- **Dedupe** - signal, stale, and scan paths share seen-status markers without suppressing possible-wedge aging for nonterminal progress.
- **Supervisor discovery** - `FM_SUPERVISOR_TARGET` wins, then `HERDR_ENV=1` plus `HERDR_PANE_ID` identifies the exact pane under `${HERDR_SESSION:-default}`.
  Missing target identity refuses at startup rather than guessing.

## Stale-artifact lifecycle

Treat `state/.subsuper-escalations`, its `.since` sidecar, and `state/.subsuper-inject-wedged` as session-scoped delivery artifacts, not as the durable work record.
Always enter through `bin/fm-afk-launch.sh`, which clears prior-session artifacts only for a fresh entry and preserves the current session's buffer on refresh.
Always exit through `bin/fm-afk-launch.sh stop`, which keeps `state/.afk` present through the daemon's shutdown flush and clears it last.
`docs/herdr-backend.md` "Away-mode supervisor support" owns the current mechanism, and `docs/verification/runtime-backends.md` "Away-mode transport" owns active evidence.

## Reliability properties

These properties must hold:

- Nothing is lost. The durable queue plus `fm-wake-drain.sh` recover any missed
  or crashed injection.
- Wedge detection is bounded-latency, not lossy.
- Declared external waits are rechecked on a separate, bounded cadence rather than being mislabeled as wedges.
- The catch-all scan backs up the keyword classifier.
- The daemon preserves a single-instance portable lock, crash-loop backoff,
  a pane-gone guard, and a signal-trapped shutdown that flushes buffered
  escalations before exit.

`FM_INJECT_SKIP` (default `heartbeat`) force-self-handles matching kinds,
overriding classification.
Use it sparingly.
