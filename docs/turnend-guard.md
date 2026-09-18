# Primary turn-end supervision guard

This is the authoritative current contract for the "no turn ends blind" Pi backstop referenced from AGENTS.md section 8.
The predicate lives in `bin/fm-turnend-guard.sh`, and primary scope lives in `bin/fm-primary-scope-lib.sh`.
The tracked Pi extension adapts `agent_settled` to that shared predicate.
Related pre-execution guards are owned separately by [`arm-pretool-check.md`](arm-pretool-check.md) and [`cd-guard.md`](cd-guard.md).

## Current invariant

`bin/fm-guard.sh` is a pull-based warning that runs only when another supervision command invokes it.
The turn-end guard closes the remaining gap at Pi's own turn boundary.
When work, a process-event source, a registered custom check, or Relay polling needs supervision and no identity-matched watcher has a fresh beacon, Pi schedules one bounded follow-up using the recovery instruction from the emitted supervision protocol.
The guard remains a backstop; [`watcher-continuity.md`](watcher-continuity.md) owns normal continuity.
Away and quiet posture do not change the runtime: Pi keeps the same ordinary supervision session live.

## Scope and supervision predicate

The guard first calls the shared primary-scope check.
A genuine secondmate home is in scope, while ordinary worker and scout worktrees are excluded because their Git directory differs from their Git common directory.
An in-scope home must contain `AGENTS.md`, `bin/`, and the effective state directory.
A `.fm-secondmate-home` marker must be a regular non-symlink file whose trimmed first line is a non-empty identifier containing only letters, digits, dots, underscores, and dashes.

The guard counts in-flight work from `state/*.meta`.
Registered process-event sources, custom checks, and `state/x-watch.check.sh` also require supervision even when no task metadata exists.
Otherwise the guard exits silently.

The turn-end predicate uses the PID-strict watcher health check from `bin/fm-wake-lib.sh`: the lock must name the exact watcher process for this home and watcher path, and the beacon must be fresh.
A stale beacon blocks even when the process is live, and a fresh leftover beacon does not excuse a missing, dead, reused, or identity-mismatched owner.
The mid-turn pull guard uses the model-aware `fm_watcher_supervision_verdict` instead, because Pi deliberately retires a watcher after an actionable notification and starts its successor itself.
During that handoff, a genuinely unheld lock with a fresh beacon is healthy only while a live Pi session proves ownership through current, identity-bound markers for both tracked primary extensions.
Any lock that records a pid remains unhealthy when its process, home, watcher path, or identity fails the strict check.
An unloaded, version-drifted, or exited Pi session therefore becomes loud rather than borrowing a stale beacon.

`FM_STATE_OVERRIDE` wins over `FM_HOME/state`, and `FM_HOME` wins over repository-root `state/`.
If integration input is empty, the guard exits 0.

### Guard grace and poll cadence

`FM_GUARD_GRACE` controls beacon freshness and defaults to 300 seconds.
`bin/fm-watch.sh` touches `state/.last-watcher-beat` before its terminal wait and at the start of the next cycle, so its own stale-lock check derives the default as `max(300, FM_POLL + 60)` through `fm_poll_derived_grace`.
Other direct guard readers retain the 300-second default unless `FM_GUARD_GRACE` is set explicitly.

## Pi integration

`.pi/extensions/fm-primary-turnend-guard.ts` listens for `agent_settled`, runs once per logical Pi run, and calls `pi.sendUserMessage(..., { deliverAs: "followUp" })` once when the predicate returns 2.
The extension fails open at the SDK boundary to protect the session, but its loop latch prevents recursive follow-ups across internal tool turns.
The generated message uses the canonical `turn-end-guard` operational kind after the U+2063 `FIRSTMATE_OP: ` prefix, so Ahoy does not treat it as captain input.
If the extension cannot invoke the SDK, the next pull-based guard call reports the lapse and uses `bin/fm-supervision-instructions.sh --repair-line` for the Pi-owned repair instruction.

## Compatibility limits

- Plain Pi is the only supported primary runtime.
- Worker and scout worktrees are outside primary scope.
- A valid secondmate home is in scope; an idle secondmate with no work, process-event source, custom check, or Relay poll has no supervision need.
- No adapter uses a shell ampersand to manufacture supervision.

## Regression coverage

`tests/fm-turnend-guard.test.sh` covers primary and secondmate scope, worker-worktree exclusion, path precedence, strict watcher health, Pi logical-run latching, and exactly-one-follow-up safety.
`tests/fm-guard-stale-banner.test.sh` covers the model-aware pull predicate, Pi's ownership-qualified handoff, held-lock failures, stale beacons, queued notifications, and reason-keyed banner deduplication.
`tests/fm-supervision-instructions.test.sh` covers Pi continuation and repair ownership.
`FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` is the opt-in isolated live Pi path.
[`verification/supervision.md`](verification/supervision.md#turn-end-guard) records the empirical evidence.
