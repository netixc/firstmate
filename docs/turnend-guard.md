# Primary turn-end supervision guard

This is the authoritative current contract for the "no turn ends blind" primary backstop referenced from AGENTS.md section 8.
The predicate lives in `bin/fm-turnend-guard.sh`.
Primary scope lives in `bin/fm-primary-scope-lib.sh`, shared with the native session-start adapters in [`sessionstart-nudge.md`](sessionstart-nudge.md).
Harness hook files adapt each enabled primary harness integration's turn-end mechanism to that shared predicate.

Related PreToolUse guards deny unsafe commands before execution rather than detecting a blind turn end afterward.
Their separate owners are [`arm-pretool-check.md`](arm-pretool-check.md) and [`cd-guard.md`](cd-guard.md).
Do not infer this guard's scope, loop safety, or compatibility tradeoffs for those guards.

## Current invariant

`bin/fm-guard.sh` is a pull-based warning that runs only when another supervision command invokes it.
The turn-end guard closes the remaining gap at the primary's own turn boundary.
When work, a process-event source, a registered custom check, or Relay polling needs supervision at that boundary and no identity-matched watcher has a fresh beacon, the harness integration must either block the turn end or force one bounded follow-up that uses the recovery instruction from the emitted session-start protocol.
The mid-turn pull warning uses the model-aware supervision verdict described below, while the turn-end guard keeps the PID-strict watcher predicate.
Away and quiet mode are the one place the turn-end guard accepts a different supervisor: while `state/.afk` exists, in either mode (`bin/fm-wake-lib.sh`'s `fm_afk_mode`), the daemon owns supervision, so a live identity-matched daemon with a fresh beacon satisfies that boundary in place of a watcher process holding the lock.
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
The default cross-harness mode exits silently with no supervision need.
Every mode treats `state/x-watch.check.sh` as supervision need, so Relay polling remains guarded without an in-flight task.
A custom check registered with `bin/fm-check-register.sh` counts the same way, so an operator's home-level poll keeps running after the last task is torn down.
Otherwise it calls `fm_watcher_healthy <state-dir> <watch-path> [grace-seconds] [home]` from `bin/fm-wake-lib.sh`, the same PID-strict identity-matched lock and fresh-beacon check used by `bin/fm-watch-arm.sh`: a stale beacon blocks even when a watcher pid is live, and a fresh leftover beacon blocks when the lock is missing, dead, or identity-mismatched.
The turn-end guard needs that strict check because it fires at the turn boundary, where a fresh watcher must serve the upcoming idle period rather than relying on a beacon left by the cycle that just ended.
`bin/fm-guard.sh`, the pull warning, instead uses the model-aware `fm_watcher_supervision_verdict` from the same library, because it fires mid-turn and must distinguish extension-owned watcher hand-offs from persistent-watcher failures.
A stale or absent beacon is a genuine lapse and alarms.
Under the extension model (Pi and pi-signed) a live identity-matched watcher is the ordinary healthy state, but a genuinely unheld lock with a beacon fresh within grace is also healthy while a live Pi session provably owns continuity, because `.pi/extensions/fm-primary-pi-watch.ts` tears the watcher down on every actionable wake and spawns the replacement itself.
A lock is genuinely unheld only when the lock directory or its symlinked owner directory is absent, or when the existing lock records no pid at all.
Any lock with a recorded pid remains down when its pid, home, watcher path, or process identity fails the strict watcher health check.
That ownership proof is `fm_extension_owns_supervision` in `bin/fm-wake-lib.sh`: both Pi primary extensions must be recorded in their state markers at their current on-disk builds by the process named in `state/.lock`, and that process must still be alive.
Requiring the turn-end guard extension as well as the watch extension is deliberate, because a home without that structural backstop has no benign hand-off to tolerate.
Without that proof an unheld lock alarms exactly as it did before, so an unloaded, version-drifted, or exited Pi session is loud immediately, and a cycle the extension never restores is loud once the beacon passes grace.
Under every persistent-watcher harness a live identity-matched watcher with a fresh beacon is still required, so the pull guard keeps the same strict semantics there.
Its banner names the true failing condition, either a missing live watcher process or a genuinely stale beacon with its real age, and keys the once-per-episode dedup on that condition rather than the beacon mtime.

While `state/.afk` exists the daemon (`bin/fm-supervise-daemon.sh`) owns supervision and runs the watcher one-shot, in either away or quiet mode: the watcher exits on every wake and the daemon starts its replacement, so a turn boundary regularly lands in a hand-off where no watcher process holds the lock and nothing is wrong.
The turn-end guard therefore accepts `fm_afk_daemon_owns_supervision` from `bin/fm-wake-lib.sh` as proof of supervision on that path: `state/.afk` must exist (the predicate does not distinguish away from quiet mode), and this home's `state/.supervise-daemon.lock` must name a live pid whose current process identity still matches the identity the daemon recorded for itself.
That is the same identity discipline the watcher lock uses, so a recycled pid, a lock left behind by a killed daemon, and a daemon that never recorded its identity all fail it.
A daemon that cannot record its own identity at startup logs a warning and keeps running, because a supervisor must not refuse to run over an unreadable `ps`; that warning is what names the cause when the guard then keeps blocking away/quiet-mode turn boundaries for the rest of that daemon's life.
The proof covers ownership only, never freshness: the guard still requires a fresh beacon, so a daemon that stops restarting its watcher still blocks once the beacon passes grace, and a home with no daemon and no watcher blocks exactly as it did before.
That beacon check uses the poll-derived grace described below rather than the flat `FM_GUARD_GRACE` default, because the daemon starts a fresh one-shot watcher only after it finishes handling the previous wake, and that handling can legitimately outrun a fixed 300-second window under load (a slow registered check, a busy supervisor pane) with the daemon perfectly healthy throughout.
With `state/.afk` absent the daemon lock proves nothing and the strict watcher predicate is unchanged.

`FM_STATE_OVERRIDE` wins over `FM_HOME/state`, and `FM_HOME` wins over repository-root `state/`.
`FM_GUARD_GRACE` controls beacon freshness and defaults to 300 seconds.
If integration stdin is empty, the guard exits 0.

### Guard grace and the poll cadence

`bin/fm-watch.sh` touches `state/.last-watcher-beat` once per cycle, immediately before its terminal wait (`event_wait_or_sleep`) as well as at the top of the next cycle, so a healthy watcher's beacon can legitimately age up to `FM_POLL` seconds between touches.
A fixed 300-second grace default stops correctly bounding staleness once a home's `FM_POLL` reaches or exceeds it: a perfectly healthy watcher mid-wait would then read stale at the edge of every full poll cycle by definition.
`bin/fm-watch.sh`'s pre-acquisition staleness check (the "lock held by live pid but heartbeat is stale" refusal) derives its default grace from the configured poll instead of a bare constant: `max(300, FM_POLL + 60)`, so the default never drops below the historical 300-second floor for the common short-poll case but grows with the poll cadence once that cadence would otherwise outrun it.
`fm_poll_derived_grace` in `bin/fm-wake-lib.sh` is the single owner of that formula.
`bin/fm-turnend-guard.sh`'s daemon-ownership branch (`fm_afk_daemon_owns_supervision`, above, covering both away and quiet mode) also derives its beacon grace from `fm_poll_derived_grace` rather than falling back to the bare 300-second default, for the same reason: the daemon's watcher-restart cadence there is not a fixed poll loop, so a flat grace misreads a daemon that is genuinely still cycling as down.
Every other direct `FM_GUARD_GRACE` reader (`bin/fm-guard.sh`, the strict-watcher checks in `bin/fm-turnend-guard.sh` and its harness-specific wrappers, `bin/fm-wake-lib.sh`) still falls back to the bare 300-second default unless `FM_GUARD_GRACE` is set explicitly in the environment.

## Harness integrations

- Pi listens for `agent_settled` in `.pi/extensions/fm-primary-turnend-guard.ts`, runs once per logical agent run, and calls `pi.sendUserMessage(..., { deliverAs: "followUp" })` once when the guard returns 2.

Pi and pi-signed expose passive callbacks for this purpose.
Their adapters fail open at the hook boundary to protect the user session but schedule one bounded follow-up when the predicate blocks.
The generated prompts use the canonical `turn-end-guard` kind after the U+2063 `FIRSTMATE_OP: ` prefix, so Ahoy does not treat them as captain messages.
Each passive adapter owns a loop latch.
Pi keeps the latch across internal tool turns and clears it only when the generated follow-up settles or delivery fails.

If a passive adapter cannot invoke its SDK, the next pull-based `fm-guard.sh` call reports the problem.
That warning uses `bin/fm-supervision-instructions.sh --repair-line`, so it always points to the active harness protocol rather than embedding another repair command.

## Compatibility limits

- Child crewmate and scout worktrees are outside scope.
- A valid secondmate home is in scope; an idle secondmate endpoint with no Relay poll remains healthy because it has no supervision need.
- The blocking and bounded-follow-up mechanisms are limited to the primary integrations listed above.
- No harness adapter uses a shell ampersand to manufacture supervision.

## Regression coverage

`tests/fm-turnend-guard.test.sh` covers the predicate, main and secondmate primary scope, child-worktree exclusion, `FM_HOME` and `FM_STATE_OVERRIDE` precedence, the live-lock and fresh-beacon guard predicate, away-mode daemon ownership between watcher cycles and over a watcher lock left behind by an exited watcher, plus its dead, pid-reused, absent, stale-beacon, and away-mode-off negatives, the away-mode beacon's poll-derived grace widening for a live daemon still mid-cycle and its bound against a dead daemon, a beacon older than that wider grace, and FM_POLL's inapplicability with away mode off, Pi logical-run latching, the remaining primary registrations, and exactly-one-path safety.
`tests/fm-guard-stale-banner.test.sh` covers the pull-guard predicate, including the persistent-model fresh-leftover-beacon negative control, and the extension model's live-watcher path, ownership-qualified fresh hand-off, held-lock failures, independently broken ownership signals, stale-beacon alarm, queued-wake warning, and Pi and pi-signed harness routing.
It also covers true-reason banner wording and reason-keyed episode dedup surviving a beacon mtime change.
`tests/fm-kimi-retirement.test.sh` covers byte-preserving retirement of the removed Kimi hook and conservative refusal while task-bound tokens remain.
`tests/fm-supervision-instructions.test.sh` covers recovery-line ownership and pi-signed's identity-preserving reuse of Pi's protocol.
`FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` is the opt-in isolated Pi path.
[`verification/supervision.md`](verification/supervision.md#turn-end-guard) records the active cross-harness empirical evidence.
