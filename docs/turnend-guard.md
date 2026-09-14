# Primary turn-end supervision guard

This is the authoritative current contract for the "no turn ends blind" primary backstop referenced from AGENTS.md section 8.
The predicate lives in `bin/fm-turnend-guard.sh`.
Primary scope lives in `bin/fm-primary-scope-lib.sh`, shared with the native session-start adapters in [`sessionstart-nudge.md`](sessionstart-nudge.md).
Harness hook files adapt each enabled primary harness integration's turn-end mechanism to that shared predicate.

Related PreToolUse guards deny unsafe commands before execution rather than detecting a blind turn end afterward.
Their separate owners are [`arm-pretool-check.md`](arm-pretool-check.md), [`cd-guard.md`](cd-guard.md), and [`subagent-guard.md`](subagent-guard.md).
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
The turn-end guard needs that strict check because it fires at the turn boundary, where the auto-arm is bringing a fresh watcher up for the upcoming idle period, and it cooperates with that arm rather than trusting a beacon left by the cycle that just ended.
`bin/fm-guard.sh`, the pull warning, instead uses the model-aware `fm_watcher_supervision_verdict` from the same library, because it fires mid-turn when the auto-arm model runs no watcher at all.
Under the Claude Stop auto-arm model a beacon fresh within grace is healthy even with no live watcher process.
A stale beacon is still healthy while `fm_autoarm_midturn_healthy` in `bin/fm-wake-lib.sh` proves a Claude rewake explains the mid-turn gap: the rewake is bound to the current recovery generation and live session-lock owner, and no later watcher beacon or exhausted-failure marker supersedes it, because that session's turn-end will re-arm.
Without that proof a stale or absent beacon is a genuine lapse and alarms.
Under the extension model (Pi, pi-signed, and omp) a live identity-matched watcher is the ordinary healthy state, but a genuinely unheld lock with a beacon fresh within grace is also healthy while a live Pi or omp session provably owns continuity, because `.pi/extensions/fm-primary-pi-watch.ts` and `.omp/extensions/fm-primary-omp-watch.ts` tear the watcher down on every actionable wake and spawn the replacement themselves.
A lock is genuinely unheld only when the lock directory or its symlinked owner directory is absent, or when the existing lock records no pid at all.
Any lock with a recorded pid remains down when its pid, home, watcher path, or process identity fails the strict watcher health check.
That ownership proof is `fm_extension_owns_supervision` in `bin/fm-wake-lib.sh`, which accepts either the Pi pair (`fm_pi_extension_owns_supervision`) or the omp pair (`fm_omp_extension_owns_supervision`): both primary extensions of one family must be recorded in their state markers at their current on-disk builds by the process named in `state/.lock`, and that process must still be alive; omp never inherits the Pi tolerance because its proof is keyed on its own two files and markers.
Requiring the turn-end guard extension as well as the watch extension is deliberate, because a home without that structural backstop has no benign hand-off to tolerate.
Without that proof an unheld lock alarms exactly as it did before, so an unloaded, version-drifted, or exited Pi or omp session is loud immediately, and a cycle the extension never restores is loud once the beacon passes grace.
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
If `jq` is missing or hook stdin is empty, the guard exits 0 because it cannot safely read loop-guard fields.

### Guard grace and the poll cadence

`bin/fm-watch.sh` touches `state/.last-watcher-beat` once per cycle, immediately before its terminal wait (`event_wait_or_sleep`) as well as at the top of the next cycle, so a healthy watcher's beacon can legitimately age up to `FM_POLL` seconds between touches.
A fixed 300-second grace default stops correctly bounding staleness once a home's `FM_POLL` reaches or exceeds it: a perfectly healthy watcher mid-wait would then read stale at the edge of every full poll cycle by definition, which is exactly what a long-poll home (`FM_POLL=300`) hit against the Claude Stop-hook auto-arm (`bin/fm-claude-stop-autoarm.sh`).
That hook and `bin/fm-watch.sh`'s own pre-acquisition staleness check (the "lock held by live pid but heartbeat is stale" refusal) both derive their default grace from the configured poll instead of a bare constant: `max(300, FM_POLL + 60)`, so the default never drops below the historical 300-second floor for the common short-poll case but grows with the poll cadence once that cadence would otherwise outrun it.
`fm_poll_derived_grace` in `bin/fm-wake-lib.sh` is the single owner of that formula.
The auto-arm hook additionally exports its resolved `FM_GUARD_GRACE` when it forks `bin/fm-watch-arm.sh`, so the arm wrapper and the watcher it may start judge staleness with the exact same value the hook just judged it with, whether that value came from an operator override or the poll-derived default.
`bin/fm-turnend-guard.sh`'s daemon-ownership branch (`fm_afk_daemon_owns_supervision`, above, covering both away and quiet mode) also derives its beacon grace from `fm_poll_derived_grace` rather than falling back to the bare 300-second default, for the same reason: the daemon's watcher-restart cadence there is not a fixed poll loop, so a flat grace misreads a daemon that is genuinely still cycling as down.
Every other direct `FM_GUARD_GRACE` reader (`bin/fm-guard.sh`, the strict-watcher checks in `bin/fm-turnend-guard.sh` and its harness-specific wrappers, `bin/fm-wake-lib.sh`) still falls back to the bare 300-second default unless `FM_GUARD_GRACE` is set explicitly in the environment.

## Harness integrations

- Claude registers two `Stop` hooks in `.claude/settings.json`, both anchored through `CLAUDE_PROJECT_DIR`: `bin/fm-turnend-guard.sh --claude`, and `bin/fm-claude-stop-autoarm.sh` with `asyncRewake: true` and `timeout: 28800`.
- Codex registers a `Stop` hook in `.codex/hooks.json`, anchors the executable to the hook process working directory, verifies a Firstmate-shaped hook-bearing root, and passes the original payload to the shared guard.
- OpenCode listens for `session.idle` in `.opencode/plugins/fm-primary-turnend-guard.js`, lets the watcher coordinator act first, and calls `client.session.promptAsync` once when the guard returns 2.
- Pi listens for `agent_settled` in `.pi/extensions/fm-primary-turnend-guard.ts`, runs once per logical agent run, and calls `pi.sendUserMessage(..., { deliverAs: "followUp" })` once when the guard returns 2.
- omp answers its blocking `session_stop` hook in `.omp/extensions/fm-primary-turnend-guard.ts`, passing the payload's own `stop_hook_active` to the shared guard and returning `{ continue: true, additionalContext }` when the guard returns 2, so the continuation is compelled rather than requested; the continuation's stop carries `stop_hook_active: true`, which bounds it to one per turn, and omp's own cap of eight consecutive continuations is the second backstop. `session_stop` never fires for an interrupted turn or a task session, so those boundaries are deliberately unguarded.
- Grok registers a `Stop` hook in `.grok/hooks/fm-primary-turnend-guard.json` and delegates capability selection to `bin/fm-turnend-guard-grok.sh`.
  The tracked Claude Stop entries are inert when `GROK_AGENT` or `GROK_HOOK_EVENT` is present, so Grok's Claude-compatible settings loading cannot create a second continuation path.
  Both markers are required because Grok does not inject the same variables into every process kind: grok 0.2.73 set `GROK_AGENT` for child and tool processes, while grok 1.0.0 hook processes carry `GROK_HOOK_EVENT`, `GROK_HOOK_NAME`, `GROK_SESSION_ID`, and `GROK_WORKSPACE_ROOT` but no `GROK_AGENT`.
  A guard keyed on `GROK_AGENT` alone therefore stopped firing on grok 1.0.0, and the resulting Claude-only auto-arm ran synchronously under Grok - Grok has no `asyncRewake`, so it waited on the foregrounded watcher for the declared 28800-second timeout and the Grok turn never ended.
  Do NOT widen this guard to `GROK_SESSION_ID`: Grok injects that into every child process, so it can survive into a Claude session that Grok launched and would silently disable Claude's own continuity.
  The same marker guard carries every tracked `.claude/settings.json` entry whose event Grok already covers through its own `.grok/hooks/` registration, which is both `Stop` entries, the `SessionStart` entry, and the two `PreToolUse` Bash entries; `bin/fm-subagent-pretool-check.sh` is the one deliberate unguarded exception because no Grok registration covers the subagent-spawn event, recorded in [`subagent-guard.md`](subagent-guard.md) "Known residual gap".
  `tests/fm-turnend-guard.test.sh` pins that inventory so neither the guarded set nor the exception can change silently.

Claude and Codex can block a Stop directly with exit status 2 and stderr.
Both payloads carry `stop_hook_active`.
In the default Codex mode, a true value lets the second stop finish after one forced continuation.

Claude runs the guard with `--claude`, which ignores `stop_hook_active` and cooperates with the Stop-owned auto-arm.
Claude Code sets `stop_hook_active=true` on every stop after any stop-hook continuation, including `asyncRewake` rewakes, which re-opened the 2026-07-21 blind window under the default one-shot behavior.
The Claude mode waits up to `FM_CLAUDE_AUTOARM_SYNC_WAIT_MS` (default 800 milliseconds) and allows the stop when the watcher is healthy, the auto-arm's generation claim is open, or `state/.claude-autoarm-epoch` contains a fresh actionable rewake owned by this event epoch.
The claim is the ledger entry itself: the epoch sequence in `state/.claude-autoarm-epoch` is a monotonic claim generation, line 1 records the claim and terminal outcome, and line 2 records the claiming process's mandatory pid-identity; `fm_autoarm_claim_open` and `fm_autoarm_claim_next` in `bin/fm-wake-lib.sh` own the format contract.
A claim is open while its outcome is `arming`, its owner pid is alive, its recorded identity successfully recomputes and matches that pid, and it is not stuck - stuck meaning the entry and the watcher beacon are both older than the guard grace, which proves the owner hung mid-arm (a healthy hours-long foregrounded cycle keeps the beacon beating, and every arming phase with no watcher is bounded in seconds).
Anything else - a finished outcome, a dead or identity-mismatched owner, a stuck owner, an identityless entry, or no entry - lets the next Stop-owned firing take the next generation and arm; taking a newer generation is the reclaim, and a steady-state predecessor is never signalled or revoked.
No mutex is held across arming or output: `state/.claude-autoarm.lock` survives only as a micro-mutex serializing individual ledger writes, and a superseded owner goes completely silent - ownership is re-verified before every arm invocation, episode-state mutation, ledger write, and continuation.
The irrevocable commit point of a translation is the exit status, because the harness delivers the collected stderr banner only on exit 2, so an owned terminal commit decides the exit: markerless outcomes commit with the ledger write, while the once-per-episode failure notice commits only when its marker is created after the winning failed write in the same critical section.
A generation whose required marker cannot be created is refused and exits 0 silently even after printing; its terminal ledger entry is superseded by a later firing, which retries the notice.
Without those boundaries a cycle that armed, delivered one rewake, and exited left both Stop participants deferring to its leftover lock indefinitely (2026-08-14: two tasks in flight, a beacon 40 minutes cold, every turn blind until an operator intervened), and a hook that hung mid-arm kept a live pid on the lock so the watcher was never auto-re-armed again (2026-08-26).
Two bounded residuals are accepted intent, each costing at most one extra continuation turn absorbed by the durable idempotent wake queue: an owner that dies between its owned terminal write and its own process exit, and a hung old-build owner that resumes during the one legacy upgrade window.
A legacy build's lock-holding claim (recognizable by its `autoarm` role file) still defers or reclaims under the legacy abandonment proof, with a live identity-verified stuck owner retired via TERM before its lock is removed and an unverified pid never signalled, so an upgrade mid-session can neither double-arm nor deadlock, and a failed reclaim re-blocks rather than allowing a blind stop.
Fresh `failed` and `failed-suppressed` outcomes enter or advance the failure progression instead of acting as unconditional recovery proof.
The auto-arm itself rechecks the healthy watcher predicate and retries a bounded number of times before reporting a genuine failure.
The first fresh exhausted-failure epoch preserves its handoff without consuming a blocked-stop count, while later fresh failed epochs advance the same monotonic progression instead of resetting it.
When none of those proofs appears, it re-blocks up to `FM_CLAUDE_TURNEND_BLOCK_BUDGET` times (default 3, below Claude's 8-block override).
In Claude mode, positive watcher recovery clears the block budget, failure notice, and attended alarm together under the existing budget lock before either hook reports ordinary recovery.
The one loud attended fail-open is available only when the auto-arm has recorded an exhausted failure, its one notice is already consumed, the block budget is exhausted, and a final check finds neither a healthy watcher nor an automatic continuation.
Each epoch identity is charged at most once per Stop under the budget lock, and a re-block against an epoch the auto-arm did not advance past the previous re-block is charged as well.
That second rule is what bounds an inert auto-arm: a hook kept silent by a session lock held by a live harness outside its ancestry, a hook that never fires, or a hook failing before its generation claim leaves the ledger frozen at its last outcome.
Charging only epoch changes let the count freeze with that ledger, so the guard re-blocked without limit and the attended fail-open was never reachable; `budget_account_current_epoch` in `bin/fm-turnend-guard.sh` owns the rule.
Whenever both coordination locks are needed, positive auto-arm recovery and the terminal check acquire the auto-arm owner lock before the budget lock.
After that alarm, the Stop auto-arm suppresses further exit-2 continuations until positive watcher recovery, so the final fail-open remains reachable.
The alarm cannot repeat during that failure episode, and a later unhealthy stop blocks again.
A positively verified healthy watcher clears the failure notice, alarm, and block budget for a future independent episode.
A Claude failure notice describes the automatic mechanism as broken and does not direct a routine manual background arm.

OpenCode, Pi, and pi-signed expose passive callbacks for this purpose.
Their adapters fail open at the hook boundary to protect the user session but schedule one bounded follow-up when the predicate blocks.
omp is the exception among the Pi-derived harnesses: its `session_stop` hook blocks like Codex's `Stop` hook, so no passive latch is needed and the `stop_hook_active` loop guard applies unchanged.
The generated prompts use the canonical `turn-end-guard` kind after the U+2063 `FIRSTMATE_OP: ` prefix, so Ahoy does not treat them as captain messages.
Each passive adapter owns a loop latch.
Pi keeps the latch across internal tool turns and clears it only when the generated follow-up settles or delivery fails.
OpenCode's forced follow-up is supported for persistent TUI sessions and remains fail-open in headless `opencode run`.

Grok makes exactly one typed capability decision from each running Stop payload.
A boolean `stopHookActive` selects native blocking, including both false on the initial stop and true on the bounded continuation.
The camel-case field has precedence when both spellings appear; when it is absent, a boolean `stop_hook_active` selects the same native path for compatibility.
The native path returns the shared guard's status and stderr to the same Grok process and never starts `grok --resume`.
When both capability spellings are absent, the adapter preserves one pre-native `grok --resume` fallback guarded by `GROK_TURNEND_GUARD_ACTIVE` and intentionally omits `--permission-mode`.
Malformed JSON, a selected field with a non-boolean type, missing `jq`, missing hook prerequisites, or an already-active legacy guard allows the stop without starting either continuation path.
Grok's project hook requires the checkout to be trusted with `/hooks-trust` or launch-time `--trust`; genuine pre-native builds can run the same tracked hook from an isolated global hook directory.

If a passive adapter cannot invoke its SDK, or the Grok legacy fallback cannot find `grok` or a session id, the next pull-based `fm-guard.sh` call reports the problem.
That warning uses `bin/fm-supervision-instructions.sh --repair-line`, so it always points to the active harness protocol rather than embedding another repair command.

## Compatibility limits

- Child crewmate and scout worktrees are outside scope.
- A valid secondmate home is in scope; an idle secondmate endpoint with no Relay poll remains healthy because it has no supervision need.
- The blocking and bounded-follow-up mechanisms are limited to the primary integrations listed above.
- OpenCode headless mode and untrusted Grok project hooks remain fail-open at the host boundary.
- Kimi Code CLI 0.29.1 exposes only global `[[hooks]]` configuration in `~/.kimi-code/config.toml`, including a `Stop` event with snake_case payload fields `hook_event_name`, `session_id`, `cwd`, and `stop_hook_active`.
- Kimi has no project-level hook configuration and remains outside the primary guard integrations above.
- Captain-approved Kimi crew wake support uses `bin/fm-kimi-turnend-hook.sh` to edit only one marker-delimited Firstmate region in that global config and install a silent always-zero hook.
- The hook remains inert unless the payload `cwd` contains a per-task token pointer that resolves through Firstmate's private registry to one `state/<id>.turn-ended` marker.
- Installation refuses before writing unless `python3` with `tomllib` and `jq` are available.
- If `jq` is removed after installation, the hook remains silent and exits 0, turn-end wakes stop, and Kimi crews fall back to idle detection.
- Unreadable hook input remains fail-open.
- No harness adapter uses a shell ampersand to manufacture supervision.

## Regression coverage

`tests/fm-turnend-guard.test.sh` covers the predicate, main and secondmate primary scope, child-worktree exclusion, `FM_HOME` and `FM_STATE_OVERRIDE` precedence, the live-lock and fresh-beacon guard predicate, the cooperative `--claude` open-generation claim wait, monotonic failed-epoch progression, bounded attended fail-open, the same bound against a ledger frozen by an inert auto-arm with and without a verified failure episode, post-alarm continuation suppression, positive recovery reset, generation and legacy claim cases that must block or clear instead of allowing a blind stop, away-mode daemon ownership between watcher cycles and over a watcher lock left behind by an exited watcher, plus its dead, pid-reused, absent, stale-beacon, and away-mode-off negatives, the away-mode beacon's poll-derived grace widening for a live daemon still mid-cycle and its bound against a dead daemon, a beacon older than that wider grace, and FM_POLL's inapplicability with away mode off, Pi logical-run latching, missing-`jq` behavior, every supported primary registration, Grok native and legacy selection, typed field precedence, malformed input, and exactly-one-path safety.
`tests/fm-guard-stale-banner.test.sh` covers the pull-guard predicate, including the persistent-model fresh-leftover-beacon negative control; the auto-arm model's healthy fresh-beacon-without-a-watcher case, session-and-recovery-bound long-turn rewake tolerance, independently broken tolerance signals, open-claim negative control, stale-beacon alarm, and isolation from other models; and the extension model's live-watcher path, ownership-qualified fresh hand-off, held-lock failures, independently broken ownership signals, stale-beacon alarm, queued-wake warning, and Pi and pi-signed harness routing.
It also covers true-reason banner wording and reason-keyed episode dedup surviving a beacon mtime change.
`tests/fm-kimi-harness.test.sh` covers the separate Kimi crew hook's format preservation, idempotence, refusal cases, token guard, spawn registration, and teardown cleanup.
`tests/fm-supervision-instructions.test.sh` covers recovery-line ownership and pi-signed's identity-preserving reuse of Pi's protocol.
`FM_PI_LIVE_E2E=1 tests/fm-pi-primary-live-e2e.test.sh` is the opt-in isolated Pi path.
`tests/fm-omp-harness.test.sh` covers the omp extension pair over a fake omp API (forced continuation on exit 2, the `stop_hook_active` bound, the seatbelt block, the ownership proof), and `FM_OMP_LIVE_E2E=1 tests/fm-omp-primary-live-e2e.test.sh` is the opt-in isolated omp path.
[`verification/supervision.md`](verification/supervision.md#turn-end-guard) records the active cross-harness empirical evidence, including the 2026-07-24 Claude `asyncRewake` revalidation.
