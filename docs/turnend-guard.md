# Primary turn-end supervision guard

This is the authoritative current contract for the "no turn ends blind" primary backstop referenced from AGENTS.md section 8.
The predicate lives in `bin/fm-turnend-guard.sh`.
Primary scope lives in `bin/fm-primary-scope-lib.sh`, shared with Pi's native session-start extension in [`sessionstart-nudge.md`](sessionstart-nudge.md).
The Pi turn-end extension applies that shared predicate.

Related PreToolUse guards deny unsafe commands before execution rather than detecting a blind turn end afterward.
Their separate owners are [`arm-pretool-check.md`](arm-pretool-check.md) and [`cd-guard.md`](cd-guard.md).
Do not infer this guard's scope, loop safety, or compatibility tradeoffs for those guards.

## Current invariant

`bin/fm-guard.sh` is a pull-based warning that runs only when another supervision command invokes it.
The turn-end guard closes the remaining gap at the primary's own turn boundary.
When work, a process-event source, or Relay polling needs supervision at that boundary and no identity-matched watcher has a fresh beacon, Pi forces one bounded follow-up that uses the recovery instruction from the emitted session-start protocol.
The mid-turn pull warning uses the model-aware supervision verdict described below, while the turn-end guard keeps the PID-strict watcher predicate.
The guard remains a backstop; [`watcher-continuity.md`](watcher-continuity.md) owns normal continuity.

## Guard predicates

The guard first calls the shared primary scope.
A secondmate home runs its own primary Firstmate session, so a genuine `.fm-secondmate-home` marker includes it whether the home is a linked worktree or plain clone.
The marker must be a regular non-symlink file whose whitespace-stripped first line is a non-empty identifier containing only letters, digits, dots, underscores, and dashes.
An unmarked checkout or invalid marker falls through to the git-dir check.
That check keeps crewmate and scout linked worktrees inert because their git dir differs from their git common dir.
It also requires `AGENTS.md`, `bin/`, and the effective state directory.

For an in-scope primary, the guard counts in-flight work from `state/*.meta`.
Registered `state/procevent/*.source` records also require supervision even though they have no task metadata.
The default Pi mode exits silently with no supervision need.
Every mode treats `state/relay-watch.check.sh` as supervision need, so Relay polling remains guarded without an in-flight task.
Otherwise it calls `fm_watcher_healthy <state-dir> <watch-path> [grace-seconds] [home]` from `bin/fm-wake-lib.sh`, the same PID-strict identity-matched lock and fresh-beacon check used by `bin/fm-watch-arm.sh`: a stale beacon blocks even when a watcher pid is live, and a fresh leftover beacon blocks when the lock is missing, dead, or identity-mismatched.
The turn-end guard needs that strict check because it fires at the turn boundary and must not trust a beacon left by the cycle that just ended.
`bin/fm-guard.sh`, the pull warning, instead uses the model-aware `fm_watcher_supervision_verdict` from the same library so Pi's extension-owned hand-off can be recognized without weakening the turn-end check.
Under the Pi extension model a live identity-matched watcher is the ordinary healthy state, but a genuinely unheld lock with a beacon fresh within grace is also healthy while a live Pi session provably owns continuity, because `.pi/extensions/fm-primary-pi-watch.ts` tears the watcher down on every actionable wake and spawns the replacement itself.
A lock is genuinely unheld only when the lock directory or its symlinked owner directory is absent, or when the existing lock records no pid at all.
Any lock with a recorded pid remains down when its pid, home, watcher path, or process identity fails the strict watcher health check.
That ownership proof is `fm_pi_extension_owns_supervision` in `bin/fm-wake-lib.sh`: both Pi primary extensions must be recorded in their state markers at their current on-disk builds by the process named in `state/.lock`, and that process must still be alive.
Requiring the turn-end guard extension as well as the watch extension is deliberate, because a home without that structural backstop has no benign hand-off to tolerate.
Without that proof an unheld lock alarms exactly as it did before, so an unloaded, version-drifted, or exited Pi session is loud immediately, and a cycle the extension never restores is loud once the beacon passes grace.
Outside Pi's extension-owned hand-off, a live identity-matched watcher with a fresh beacon is still required, so the pull guard keeps strict semantics.
Its banner names the true failing condition, either a missing live watcher process or a genuinely stale beacon with its real age, and keys the once-per-episode dedup on that condition rather than the beacon mtime.

`FM_STATE_OVERRIDE` wins over `FM_HOME/state`, and `FM_HOME` wins over repository-root `state/`.
`FM_GUARD_GRACE` controls beacon freshness and defaults to 300 seconds.

## Pi integration

- Pi listens for `agent_settled` in `.pi/extensions/fm-primary-turnend-guard.ts`, runs once per logical agent run, and calls `pi.sendUserMessage(..., { deliverAs: "followUp" })` once when the guard returns 2.

Pi exposes passive callbacks for this purpose.
Its adapter steps aside at the hook boundary to protect the user session but schedules one bounded follow-up when the predicate blocks.
The generated prompts use the canonical `turn-end-guard` kind after the U+2063 `FIRSTMATE_OP: ` prefix, so Ahoy does not treat them as captain messages.
The Pi adapter owns a loop latch.
Pi keeps the latch across internal tool turns and clears it only when the generated follow-up settles or delivery fails.

If the Pi extension cannot invoke its SDK, the next pull-based `fm-guard.sh` call reports the problem.
That warning uses `bin/fm-supervision-instructions.sh --repair-line`, so it points to the Pi repair protocol rather than embedding another repair command.

## Compatibility limits

- Child crewmate and scout worktrees are outside scope.
- A valid secondmate home is in scope; an idle secondmate endpoint with no Relay poll remains healthy because it has no supervision need.
- The blocking and bounded-follow-up mechanisms are limited to the Pi primary integration above.
- The Pi extension does not use a shell ampersand to manufacture supervision.

## Regression coverage

`tests/fm-turnend-guard.test.sh` covers the predicate, main and secondmate primary scope, child-worktree exclusion, `FM_HOME` and `FM_STATE_OVERRIDE` precedence, the live-lock and fresh-beacon guard predicate, Pi logical-run latching, primary registration, and exactly-one-path safety.
`tests/fm-guard-stale-banner.test.sh` covers the pull-guard predicate, including the persistent-model fresh-leftover-beacon negative control and the extension model's live-watcher path, ownership-qualified fresh hand-off, held-lock failures, independently broken ownership signals, stale-beacon alarm, queued-wake warning, and Pi harness routing.
It also covers true-reason banner wording and reason-keyed episode dedup surviving a beacon mtime change.
`tests/fm-supervision-instructions.test.sh` covers Pi recovery-line ownership and retired-selector refusal.
`FM_AFK_PI_HERDR_E2E=1 tests/fm-afk-pi-herdr-return-e2e.test.sh` is the opt-in isolated Pi-and-Herdr continuity path.
[`verification/supervision.md`](verification/supervision.md#turn-end-guard) records the active Pi empirical evidence.
