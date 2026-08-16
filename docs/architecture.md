# Architecture

How firstmate works, in depth.

The [README](../README.md) carries the high-level diagram and a short synopsis.
This document expands every part of it.
firstmate's always-loaded operating contract and routing index for conditional procedures is [`AGENTS.md`](../AGENTS.md); this is the human-facing companion.

## Event-driven supervision

A zero-token bash watcher (`bin/fm-watch.sh`) sleeps on the fleet, classifies detected wakes in bash, and wakes the first mate only when something is actionable.
Actionable wakes include captain-relevant status signals, no-verb signals whose crew is not provably working, authenticated check output such as PR merge polling or a Relay mention, stale panes whose crew is not provably working whether their status log looks terminal or non-terminal, provably-working stale panes that persist past `FM_STALE_ESCALATE_SECS`, declared external waits that remain paused past `FM_PAUSE_RESURFACE_SECS`, and heartbeat backstop hits.
Repeated provably-working stale escalations on the same unchanged pane add an escalation count to the wake reason and, at `FM_WEDGE_DEMAND_INSPECT_COUNT`, a `demand-deep-inspection` marker.
A busy pane is otherwise exempt from staleness, but only until its latest `state/<id>.turn-ended` marker reaches `FM_BUSY_TURN_MAX_SECS`, or its `state/<id>.meta` spawn record reaches that age before any turn completes; past that bound it is routed through the same wedge escalation, with the identical reason, escalation count, and `demand-deep-inspection` marker, for inspection only - never an automatic interrupt, signal, or restart.
Those actionable wakes are written to a durable local queue (`state/.wake-queue`) only after generation-bound recovery evidence is published, so an interrupted watcher or handling turn can be recovered without losing the queue record.
When a canonical validated PR poll returns exactly `merged`, the watcher appends that durable notification before publishing a private receipt bound to the poll's registration, bytes, file identities, metadata, provider, URL, and task ID.
The receipt makes retirement safely retryable across restarts: fixed-path recovery revalidates the same evidence, removes the runnable check first, removes its registration and data sidecars, removes the receipt last, and preserves task metadata including `pr=` and `pr_head=`.
A non-executing upgrade scan quarantines unsupported or invalid nonterminal poll artifacts without running their bytes or contacting a forge, while an already-terminal unsupported receipt permits only exact identity- and hash-bound data cleanup that preserves its durable merged notification and task metadata.
A concurrent replacement remains armed, every non-merged or invalid observation remains unchanged, and retirement never performs task or persistent-secondmate cleanup.
`bin/fm-pr-lib.sh` owns the receipt format and strict identity mechanics, while `bin/fm-watch.sh` owns queue-before-retirement ordering.
No-verb wakes, such as `working:` notes and bare turn-ended signals, are benign only when `bin/fm-crew-state.sh` reports positive evidence that the crew is still working: an actively running no-mistakes step attributed to that crew's current code, or an exact busy verdict from the semantic busy-state contract.
A `kind=secondmate` task's status signal is the parent-directed reply stream and is never absorbed as provably working; only its bare turn-ended signal retains the ordinary absorb rule.
A crew that declares `paused:` for a known external wait is separately absorbed while idle and re-surfaced only on the longer pause cadence, rather than being treated as a possible wedge.
For an ordinary crew that has stopped, the normal-mode watcher first surfaces one stale wake, then applies that same cadence to an unchanged `paused:` or durable `captain-held` endpoint only when the backend confidently reports its agent dead.
Live or inconclusive liveness remains fail-open at that initial surface, and the secondmate idle-endpoint exemption is unchanged.
Its initial normal-mode status signal still surfaces through the no-verb path, while away mode self-handles that routine signal and owns the later recheck.
Fresh stale panes use the same current-state read before trusting the status log, so an active run or a proven busy worker outranks an old captain-relevant status-log line left behind before validation.
No-change heartbeats are also benign.
Separately from heartbeat backoff and wedge handling, the watcher poll runs `bin/fm-inactive-reconcile.sh` on its own bounded cadence, while locked session start performs the same bounded local scan immediately.
In each home the scan considers only that home's long-inactive direct ordinary crewmates, excludes captain-held work, and accepts only `done` or `failed` from `bin/fm-crew-state.sh`.
A secondmate retains a durable receipt for its idempotent report through the established parent route, and main-home captain presentation retains a separate receipt; neither path performs a forge or PR check.
Absorbed wakes advance their suppression markers, log to `state/.watch-triage.log`, and keep the watcher blocking without a queue record or LLM turn.
Each `fm-wake-drain.sh` presentation runs the same liveness guard as the supervision scripts, so a lapsed watcher chain surfaces even on a turn that only handles queued wakes.
Routine watcher polling, supervision no-ops, elapsed waiting time, and absorbed benign wakes stay silent.
A declared external wait trades that silence for one bounded recheck per pause window, so a forgotten pause cannot remain invisible indefinitely.
Crew status files are append-only wake-event logs, not current-state fields.
Because of that, a per-wake read of only the latest line can bury an earlier still-open `needs-decision`/`blocked` under later unrelated appends; `fm-wake-drain.sh` prints a separate, fleet-wide OPEN DECISIONS section on every presentation (including the empty-queue path session-start relies on), built through `fm-classify-lib.sh`'s cursor-backed incremental scan using the authoritative `status_open_decisions` fold semantics so the buried decision keeps surfacing until it is explicitly resolved while each presentation folds only new status-log appends.
The drain coordinates that fold and its annotations through a locked fleet-wide snapshot whose `.status-presentation-cursor` manifest records each status file's identity and last-presented byte offset.
A queued signal annotation prints every status line still unread at that cursor, while the fleet-wide UNREAD STATUS section prints `note:` lines and reserved-key pending-reply resolutions once even on an empty-queue drain because those verbs never enter the OPEN DECISIONS fold.
A failed read, output, or concurrent-replacement check prevents the snapshot cursor from advancing across uncertain bytes, and teardown retires a task's manifest row before that task ID can be reused.
The explicit resolution is written by the actor that answers, not the busy worker: `fm-send`'s `--resolve-key` appends the closing `resolved` line to this home's own copy of the ledger at answer time, which covers crewmates, local secondmates, and remote secondmates identically because a remote mate's escalations reach that local copy through the parent-replies ingest and only the answer message itself crosses the transport.
This home's answerer close, pending-reply escalation close, and captain-held transfer use the provenance-guarded append owned by `bin/fm-wake-lib.sh`, so they advance the watcher marker only across their own bytes when all earlier bytes were already announced; pending or interleaved foreign bytes fail toward an ordinary wake.
A turn-ended-only queue row omits its historical status annotation when that status file exactly matches the same seen marker.
Any direct or remaining historical annotation prints every status line unread at the presentation cursor instead of replaying only the latest line.
`bin/fm-crew-state.sh <id>` is the cheap current-state read for an actionable heartbeat review: it attributes a no-mistakes run, active or terminal, only when it matches the crew's branch and current code identity, then keeps that run-step authoritative even if the pane has closed.
The script header owns the exact run-head ancestry rules.
During no-mistakes' `ci` monitor phase, it also reads the ci step log tail because `axi status` reports both "still waiting on checks" and "checks green, waiting on merge" as `ci,running`.
The most recent recognized ci log marker wins, so checks-green monitoring reports done while a later re-arm, failed-check, or issue marker returns the crew to working.
Only when no matching run exists does it consult semantic busy state; exact busy reports working, exact idle permits fallback to a status-log event whose verb maps to a recognized run-state, and unknown or a dead pane stays unknown instead of trusting a stale log.
Decision-only events such as `resolved` never become current state or leak their prose into the current-state detail.
In that status-log fallback, a declared external wait reports the distinct `paused` state with its reason.
The semantic branch reports working only on an exact busy verdict and names the source that produced it; an unknown verdict never becomes working, never permits the status-log fallback, and never becomes a silent idle.
For whole-fleet read-only review, `bin/fm-fleet-snapshot.sh --json` emits schema `fm-fleet-snapshot.v1` from the backlog, task metadata, current crew state, endpoint probes, PR/report pointers, scout reports, bounded current summaries from registered secondmate homes, and secondmate return-channel guidance.
`bin/fm-fleet-view.sh` renders that snapshot as Markdown for humans, while `bin/fm-bearings-snapshot.sh` provides the bounded bearings projection, so both views consume one structured contract instead of reparsing raw fleet files.
The script header owns the exact JSON schema.

### Registered secondmate current state

A registered secondmate's validated home is the authority for bearings current state because it owns the child metadata inventory, each child's current-state result, endpoint observations, backlog holds and dependencies, keyed unresolved decisions, and recent Done baseline.
The original cross-home projection instead treated the secondmate agent as an ordinary parent task, so an idle secondmate's `fm-crew-state` fallback selected the latest append-only parent status event even when structured state in the registered home contradicted it.
The parent-status contract also required explicit keyed resolution for decisions and blockers but not for a material `working` phase, so a start event could remain unsuperseded after the corresponding home backlog had moved the work to Done.
Generated secondmate charters reject generic receipt or start acknowledgements, key only supervisor-actionable material phase reports, and close an opened phase with a same-key later state or `resolved` event, while the structured home remains authoritative even if that closure is missing.
Cross-home reads validate the seeded identity and operational-directory boundaries, use per-home time and output bounds, and classify unavailable, malformed, or inconsistent structured state as unknown rather than reviving a parent event as current work.
When only an owned child's current classification is unavailable, the home classification stays unknown while independently trustworthy structured decisions, holds, queued and landed records, endpoint identities, counts, and provenance remain available; every other invalid path stays strict and exposes none of those child-derived surfaces.
A bounded direct-report terminal tail can help diagnose a mismatch by showing that historical parent wording is still visible, but it is untrusted supplemental evidence because scrollback, prompts, copied output, idle shells, and agent prose are not durable state.
The snapshot strips control sequences, retains only capture metadata and literal event-corroboration flags, and never lets terminal evidence override a valid structured classification.
The default path remains local-only; live GitHub enrichment exists only behind the bearings `--include-prs` opt-in.
Optional Relay integrates with the watcher only after explicit opt-in; [configuration.md](configuration.md#relay-env) owns its generated-artifact and dispatch mechanics.

At session start, `bin/fm-session-start.sh` emits exactly one primary-harness supervision block rendered by `bin/fm-supervision-instructions.sh` from `docs/supervision-protocols/`.
That block owns the live wait shape for the running primary harness: Pi uses two tracked primary extensions.
`bin/fm-watch-arm.sh` remains the verified arm wrapper for protocols that call it; it forks the watcher as a tracked child, verifies it is genuinely alive with a fresh liveness beacon, and prints an honest `started`, `attached`, or nonzero `FAILED` status.
[`watcher-continuity.md`](watcher-continuity.md#arm-layer-cycle-contract) owns the arm layer's successor, terminal-delivery, re-arm recovery, and typed clean-close failure contract.
The arm layer records one bounded lifecycle row per observed cycle in `state/.watch-cycle-exits.log`; `state/.watch-triage.log` remains exclusively the absorbed-wake debug log.
Pi verifies session-lock ownership and launches one singleton successor from its child-close handler before delivering an actionable wake prompt, with bounded exponential retry for failed restoration.
The existing turn-end guard remains the final backstop for Pi's protocol.
Its `--restart` mode signals only the watcher recorded in the current home's `state/.watch.lock`, so restarting one home cannot kill sibling secondmate watchers.
A pull-based guard (`bin/fm-guard.sh`) warns through supervision tool output if the primary checkout is tangled, if work, process-event sources, or Relay polling has an unhealthy model-aware supervision verdict, or if queued wakes are waiting to be drained.
The drain script calls that guard after presenting the queue; records remain durable, and may keep the queued-wakes warning visible, until the exact generation-bound acknowledgement printed by the drain succeeds after handling.
It leads with a prominent bordered tangle banner, while `bin/fm-guard.sh` owns the watcher-down banner and reminder policy so repeated guarded commands stay noisy without reprinting the full banner in the same episode.
The tracked Pi hook integration gives the primary session a push-based backstop: when work, a process-event source, or Relay polling needs supervision and no identity-matched watcher lock with a fresh beacon is live, it forces one bounded follow-up.
The guard covers the main primary and genuinely marked secondmate homes, exempts child crewmate/scout worktrees, is loop-safe per harness, and is documented in [turnend-guard.md](turnend-guard.md).

A presence-gated sub-supervisor (`bin/fm-supervise-daemon.sh`) extends this for walk-away supervision: the `/afk` skill starts it through the tracked foreground helper `bin/fm-afk-start.sh`, after which the watcher reverts to daemon-managed one-shot mode and the daemon self-handles routine wakes in bash.
The watcher and daemon share `bin/fm-classify-lib.sh` for captain-relevant status verbs, declared-external-wait vocabulary, and status-scan primitives.
Terminal verbs remain captain-relevant, while a nonterminal progress verb cannot become terminal merely because its prose contains a legacy free-text token such as `merged`; bare legacy free-text lines remain compatible.
The always-on watcher also uses that library's absorb classification on no-verb signals and first-sighting stale panes before status-log terminality is trusted, while the daemon maintains distinct wedge and declared-pause recheck cadences.
In away mode, seen-status dedupe does not clear possible-wedge aging for nonterminal progress, so housekeeping still re-escalates an unchanged idle pane at the configured bound.
The daemon escalates captain-relevant events, plus a bounded recheck for a declared pause that remains idle, as one batched, single-line digest using the canonical `away-supervisor` kind from `bin/fm-operational-input.sh` so firstmate can distinguish it structurally from real messages.
Its supervisor injection path supports tmux and herdr panes, with `FM_SUPERVISOR_BACKEND` and `FM_SUPERVISOR_TARGET` resolved independently from the task-spawn backend.
Pane existence, busy checks, composer checks, capture, and verified submit route through `bin/fm-backend.sh`: tmux keeps the same submit core used by the tmux send backend, while herdr uses native agent-state submit confirmation on idle baselines and conservative composer confirmation when that baseline is unavailable.
Composer classification has one shared owner, `bin/fm-composer-lib.sh`: tmux and Herdr contribute only a screen capture plus declarative styled, cursor, identity, and row capabilities, while the shared classifier owns every shape and the `empty`/`pending`/`pending-unproven`/`unknown` verdict.
The daemon injects only into an affirmatively `empty` composer, so every other or future verdict defers; positive container proof is required, and a blank unidentified row or bare dead-shell prompt cannot receive an escalation.
The current operator boundary is in [Composer and injection safety](herdr-backend.md#composer-and-injection-safety).
Unsupported supervisor backends refuse at daemon startup.
Stalled escalation delivery writes `state/.subsuper-inject-wedged` and attempts a configured backend-independent active alert after `FM_MAX_DEFER_SECS` instead of silently deferring forever.
On an unmarked return, `bin/fm-afk-return.sh` owns ordered shutdown, durable catch-up evidence, and the fail-closed gate that keeps ordinary work behind every live firstmate-actionable blocker.
`fm-send.sh` selects a pre-Enter popup-settle for slash commands, then adds its own `FM_SEND_SETTLE` pause after successful text sends so immediate peeks catch the receiving turn starting; the sub-supervisor uses only the shared submit core and does not pay that post-submit pause.

Text for a worker to read and commands that drive a worker's process are separate planes.
`fm-send.sh` is the data plane and always routing-marks a `kind=secondmate` target, which is right for a message and wrong for a lifecycle command, because a marked exit command arrives as chat the agent reasons about instead of executing.
`bin/fm-control.sh` is the control plane: an allowlisted `interrupt`, `exit`, and transactional `relaunch` addressed to an exact task id, with per-harness mechanics owned by `bin/fm-control-lib.sh`, a verified postcondition per verb, and no arbitrary-text or raw-key entry point.
[`docs/agent-control.md`](agent-control.md) owns the verb contract, the capability matrix, the relaunch transaction, and the fail-closed boundaries.

## Busy state is semantic, per adapter

`bin/fm-busy-lib.sh` is the single owner of what "this worker is busy" means, and `bin/fm-busy-event.sh` is the only writer of the per-task records it reads.
Every classification returns a verdict of busy, idle, unknown, or dead together with the source that produced it, so a consumer or a diagnostic can never confuse semantic state with a fallback.

Pi reports its turn lifecycle through the Firstmate-owned extension's machine-readable `agent_start` and `agent_settled` callbacks, with idle confirmed by `ctx.isIdle()` rather than rendered footer text.

Missing, malformed, stale, untrusted, or unverified semantic state is unknown, never idle, and unknown is never promoted to busy either.
Ordinary task-state consumers act only on an exact busy verdict, so an unreadable worker surfaces for a closer look instead of being absorbed as still-working or written off as finished.
Endpoint death is the only process-level override and yields dead; child processes, CPU, process sleep state, and marker modification times are not state signals.
`state/<id>.turn-ended` files remain wake notifications, not current state.

Each record is bound to an incarnation token minted when the task's wiring is armed, so an event from a superseded incarnation is rejected rather than applied, and a record left behind by one classifies unknown.
Rendered-text checks deliberately remain outside this contract because they answer delivery questions: submit acknowledgement and the away-mode supervisor-pane busy guard consume the shared delivery-footer matcher owned by `bin/fm-composer-lib.sh`, while `bin/fm-pending-reply-lib.sh` owns the secondmate delivery-confirmation observation.
All are harness-scoped rather than a global pattern union, and none is a recorded worker state source.

## Runtime session backends

The runtime backend is the session-provider layer below Firstmate's scripts.
It owns task endpoint creation, bounded capture, text and key sends, current-path reads for spawn-time worktree discovery, agent-process liveness probes, and endpoint cleanup.
`bin/fm-backend.sh` centralizes backend selection, metadata helpers, cleanup identity validation, selector resolution, and operation dispatch.
The supported adapters are the tmux reference adapter in `bin/backends/tmux.sh` and experimental Herdr adapter in `bin/backends/herdr.sh`.
[`configuration.md`](configuration.md#runtime-backend-configbackend--fm_backend) owns selection precedence and authorization.
Runtime auto-detection is innermost-first: `$TMUX` wins over `HERDR_ENV=1`; auto-detected Herdr prints an opt-out notice and tmux stays silent.
Unknown backend names fail loudly.
Default tmux tasks omit `backend=tmux`, and every reader treats a missing `backend=` field as tmux.
Herdr's native `agent.get` contributes busy evidence and its native event stream can replace a watcher sleep with a bounded transition wait, while polling remains the fallback.
Both adapters provide recovery-grade secondmate agent-state classifiers.
Herdr remains experimental, uses Treehouse worktrees, and is documented in [`herdr-backend.md`](herdr-backend.md) with active evidence in [`verification/runtime-backends.md`](verification/runtime-backends.md#herdr).

## Worktrees, not branches in your checkout

Crewmates never intentionally touch your project clone; [treehouse](https://github.com/kunchenguid/treehouse) pools clean worktrees for tmux and Herdr tasks.
For ship and scout work, `fm-spawn.sh` refuses to launch unless the resolved task path is a real git worktree root that is distinct from the project primary checkout.
`fm-spawn.sh` also owns the base-freshness boundary for every fresh ship and scout: no worker starts until its clean task worktree matches the fetched tip of origin's resolved default branch, and any unsafe or unverifiable base stops the spawn.
Its header owns the exact refusal mechanics, while `tests/fm-spawn-pool-base-freshen.test.sh` owns the portable regression coverage.

The firstmate repo has one extra exposure because it can dispatch crewmates to work on itself.
Its operating checkout (`FM_ROOT`) and the disposable crewmate worktrees are all linked git worktrees of the same repository, so the valid discriminator is branch state, not whether the checkout is linked.
The primary checkout is healthy on its default branch, and linked worktrees or secondmate homes are healthy at detached HEAD.
Only a named non-default branch checked out in `FM_ROOT` is a worktree tangle.

`fm-tangle-lib.sh` resolves the default branch from `origin/HEAD`, then local `main` or `master`, and classifies that named non-default primary branch as the tangle.
`fm-guard.sh` prints the repair command on the next mutable fleet action, while `bin/fm-session-start.sh` reports the same condition through bootstrap as a `TANGLE:` line at session start.
If another live session holds the fleet lock, both surfaces keep the alarm but switch to read-only wording with no repair command.
Ship briefs also tell the crewmate to verify `pwd -P` and `git rev-parse --show-toplevel` before creating `fm/<id>`, then stop with a blocked status if it landed in the primary checkout.

## No-mistakes gate authority boundary

Firstmate's own no-mistakes gate runs agents inside a checkout that also contains the fleet-captain identity in `AGENTS.md`, so gate execution needs an authority boundary separate from ordinary crewmate worktree isolation.
The tracked `.no-mistakes.yaml` sets `disable_project_settings: true`; no-mistakes honors that setting only from the trusted default-branch copy, so a pushed branch cannot enable its own project instructions during validation.
Independently, `fm-spawn.sh`, `fm-send.sh`, `fm-control.sh`, and `fm-teardown.sh` source `bin/fm-gate-refuse-lib.sh` and exit with status 3 before fleet mutation when the gate environment marker is present or the current checkout matches the default no-mistakes gate-repository topology.
A normal primary checkout or crewmate worktree has neither signal and remains unaffected.
The helper's header owns the exact signal detection, relocated-home limitation, test-harness bypass, and relationship to no-mistakes' HEAD-continuity guard.

## Two task shapes

Ship tasks change projects and ship by project mode (`no-mistakes`, `direct-PR`, or `local-only`); scout tasks leave standalone investigation reports at `data/<id>/report.md` and never push.
The intake and authority contract in `AGENTS.md` owns when separate scout research is warranted.

## Dispatch profiles

Crewmate and scout dispatch can stay on the static crewmate harness resolved by `config/crew-harness`, or it can use local dispatch profiles in `config/crew-dispatch.json`.
The dispatch file is intentionally judgment-based: firstmate reads the natural-language rules at intake, chooses the best matching rule, resolves profile arrays itself from current quota output under the `AGENTS.md` section 4 intake boundary and the `quota-array-dispatch` selection procedure, and passes only concrete `--harness`, `--model`, and `--effort` axes to `fm-spawn.sh`.
The shell scripts validate the JSON shape and verified harness/effort combinations, but they do not parse task intent, match natural-language rules, or own array selection.
The session-start bootstrap step keeps valid dispatch configuration silent unless verbose facts are enabled and surfaces a concise invalid-config line when validation fails.
When the file exists, `fm-spawn.sh` refuses crewmate and scout launches without an explicit harness, so `config/crew-harness` is only automatic when no dispatch profile file is active.
Secondmate launches are exempt because they resolve the secondmate harness and any optional secondmate model or effort tokens instead.
Unsupported effort values are still recorded in task meta when passed to `fm-spawn.sh`, but the launch template omits any effort flag that the selected harness does not accept.
That keeps Pi spawn launch compatible while preserving the requested profile for later audit.

## Optional secondmates

`data/secondmates.md` records persistent secondmates with natural-language scopes, project clone lists, and home paths.
A local route points directly at its home, while a remote route adds an SSH alias and remote Firstmate code root so the entire home and all of its child work stay on that host.
Remote placement pins the remote second-mate agent to Herdr while leaving the remote home's worker backend selection independent, and every non-doctor primary-to-remote `fm-on` command runs through the remote account's Firstmate-owned job worker rather than its SSH process or a Herdr pane.
[`remote-secondmates.md`](remote-secondmates.md) owns current setup, supplied-origin provisioning, transport, relay, failure, and retirement behavior.
`fm-home-seed.sh` provisions a local isolated home, clones the listed PR-based projects into it, initializes newly cloned `no-mistakes` projects, copies the charter to `data/charter.md`, and `fm-spawn.sh --secondmate` launches it through the same session-provider and status-file path as any direct report.
For a domain whose subject is the firstmate repo itself, a deliberate `--no-projects` seed creates a project-less home whose crews take pooled worktrees of that repo instead of separate clones.
The signal cannot be mixed with project names or omitted accidentally, and a populated home cannot be converted in place; the full seed contract is in [configuration.md](configuration.md#secondmate-routes-datasecondmatesmd).
Herdr secondmate and child placement follows the launcher-binding contract in [Watching and task containers](herdr-backend.md#watching-and-task-containers).
When seeded with `-`, the home is a durable treehouse lease under the secondmate id, so it survives with no live process and is not recycled by later `treehouse get` or pruning.
Retirement or seed rollback returns the leased home; normal restart/recovery keeps it leased.
If returning the lease fails during teardown, firstmate leaves the route and home intact instead of hiding a still-held lease.
Seeding is transactional: if validation, cloning, initialization, or registry update fails, generated briefs, new homes, new project clones, and registry edits are rolled back.
`local-only` projects stay with the main first mate because they merge into the main local checkout instead of a remote-backed PR path.
The same project may appear in multiple secondmate homes when their scopes differ, such as issue triage versus feature development.
Secondmates are idle by default: after startup recovery reconciles only work already in their own home, an empty queue waits silently for routed tasks, and they never self-initiate surveys or audits.
When called with `FM_HOME=<this-firstmate-home>` or when `FM_HOME` is already set to the active firstmate home, metadata-routed `fm-send.sh` requests to a live `kind=secondmate` use the live-charter-compatible `from-firstmate` carrier owned by `bin/fm-operational-input.sh`, so the secondmate returns terse answers through status lines and detailed answers through docs plus status pointers instead of replying only in its own chat.
The parent guards every marked request against a missing correlated report without reading the secondmate conversation; `bin/fm-pending-reply-lib.sh` owns the correlation, recovery, escalation, and retention contract.
Explicit backend-target sends and direct human typing stay unmarked, so captain intervention in a secondmate pane remains conversational.
After seeding a secondmate, `fm-backlog-handoff.sh` validates the fleet-specific handoff, then atomically delegates already-judged in-scope queued item moves to `tasks-axi mv` so the domain queue starts in the right place.
Remote routes move that dependency-closed set into a non-dispatchable backlog-format outbox before transfer, then use an idempotent remote receive under the destination backlog's own lock.
The outbox is the complete retry record, so no two-phase journal or transport-level retry is needed.
An unreachable remote host is unknown rather than dead, preserves its route and durable work, and is never failed over or relaunched locally.
Idle secondmate panes are healthy; teardown is explicit and refuses while the secondmate home has in-flight work unless the captain has approved discard with `--force`.

Secondmate homes converge conservatively to the primary's version and declared inherited local material at launch and during locked session start.
The [`secondmate-provisioning` skill](../.agents/skills/secondmate-provisioning/SKILL.md) owns the full guarded sync, propagation, nudge, and mid-session local-material push contract.

Secondmate agents can run a different Pi model and effort profile than crewmates.
`config/secondmate-harness` controls the primary's secondmate launch profile and may carry optional model and effort tokens as `<harness> [<model>] [<effort>]` on the first non-empty, non-comment line.
A bare harness line remains harness-only, so existing `config/secondmate-harness` files keep their previous behavior.
When the harness token is unset or `default`, launch falls back to `config/crew-harness`, then to the primary's own harness, and the model and effort tokens are ignored.
Those optional tokens are re-read on every secondmate spawn or respawn and are overridden by explicit per-spawn `--model` or `--effort` flags.
For a local route, an explicit per-spawn harness does not inherit model or effort tokens from `config/secondmate-harness`.
All routes accept only Pi as the verified harness.
`config/crew-harness` remains the crewmate harness and is inherited into secondmate homes.
`config/crew-dispatch.json` is inherited too; secondmates use the same natural-language dispatch profiles when spawning their own crewmates.
The [`secondmate-provisioning` skill](../.agents/skills/secondmate-provisioning/SKILL.md) owns the complete inherited-local-material allowlist and propagation contract.

The `data/secondmates.md` line contract is owned by the [`secondmate-provisioning` skill](../.agents/skills/secondmate-provisioning/SKILL.md#routing-table), and the secondmate environment variables are documented in [configuration.md](configuration.md).

## Delivery modes are explicit per task

`no-mistakes` tasks run the full validation pipeline, `direct-PR` tasks open PRs without that pipeline, and `local-only` tasks stay local until firstmate performs an approved fast-forward merge.
Each task's mode and `yolo` posture are firstmate's decision at intake and are passed explicitly to `bin/fm-brief.sh`, `bin/fm-spawn.sh`, and `bin/fm-promote.sh`, which refuse a ship task that does not carry them.
A ship brief records its mode as a fixed machine-readable line and the spawn refuses to launch on a different one, so the worker's instructions and the recorded task delivery cannot diverge.
`data/projects.md` records each project's standing posture and optional `+yolo` flag as the captain's default and as context for that decision, including the conditional `no-mistakes-prod-only` policy; a ship spawn that drops below the registered rigor prints a deviation notice and continues.
`bin/fm-project-mode.sh` remains the one registry parser for the mechanical consumers that have no task in hand: fleet sync's `local-only` skip and home seeding's refusal and no-mistakes initialization.
When a selected delivery path calls for a diff, `bin/fm-review-diff.sh` refreshes the authoritative base and, when task meta records `pr=`, always fetches and compares against `refs/pull/<n>/head` by default (recorded `pr_head=` is only an offline fallback) before falling back to the local branch with a warning.
For target project repos shipped through their own no-mistakes pipeline, commits under `.no-mistakes/evidence/` are the pipeline's PR-viewable validation evidence and are expected to stay in the crew branch until the evidence-hosting design changes.
The firstmate repo itself is the exception: its `.no-mistakes/` directory is local state, stays gitignored, and is rejected by CI if tracked.
PR-based task merges go through `bin/fm-pr-merge.sh`, which records `pr=` and any available `pr_head=` through `bin/fm-pr-check.sh` before calling `gh-axi pr merge`.
The helper requires a full `https://github.com/<owner>/<repo>/pull/<n>` URL, invokes `gh-axi pr merge <n> --repo <owner>/<repo>`, defaults to `--squash`, preserves explicit merge-method flags, and rejects malformed URLs or repository override flags before recording merge state.
Teardown is fail-closed for ship worktrees: dirty worktrees refuse, and committed work must be landed before the worktree is returned.
[`bin/fm-teardown.sh`](../bin/fm-teardown.sh)'s header owns the landed-work proofs, PR-discovery fallback, and stale-lock recovery procedure.

## Optional Relay

Relay is the optional Discord-only public-mention subsystem hosted by [myfirstmate.io](https://myfirstmate.io).
The dashboard owns Discord identity linking, bot installation, and pairing-token issuance, while the Firstmate home remains a polling client and never opens a Discord Gateway connection or runs a local transport daemon.
A non-empty `FMX_PAIRING_TOKEN` in the home's gitignored `.env` activates the existing authenticated check path; without it, hosted polling and replies remain inactive.

Locked bootstrap creates the validated `state/relay-watch.check.sh` identity shim and `config/relay.env` cadence file.
The same bootstrap path performs one bounded migration of legacy local connector artifacts into `relay-*` state, Relay task metadata, and `FM_RELAY_*` optional settings, leaving the pairing-token key stable.
The watcher invokes `bin/fm-relay-poll.sh`, which accepts only explicitly identified Discord payloads from myfirstmate.io, stores them in `state/relay-inbox/`, records per-request Discord budgets in `state/relay-context/`, and emits `relay-mention <request_id>` once per bounded offer marker.
No platform message-id inference or alternate platform fallback exists.

The `relay-respond` skill owns owner-only request classification, public-safety constraints, optional Discord conversation context, lifecycle intake, replies, dismissals, and task linking.
`bin/fm-relay-reply.sh` sends request-bound answers and follow-ups through the hosted connector endpoints, splits long text into Discord-sized ordered chunks, and attaches an optional image to the opening message.
`bin/fm-relay-dismiss.sh` drops mentions that need no reply.
`bin/fm-relay-link.sh` and `bin/fm-relay-followup.sh` preserve the original request binding, Discord budget, seven-day window, and three-follow-up cap across long-running work and safe recovery.

A promised final reply becomes a typed `tasks-axi public-followup` obligation rather than conversation memory.
`bin/fm-public-followup.sh` owns home-side registration, typed terminal-result reconciliation, idempotent hosted delivery, receipt validation, and task-link cleanup.
Remote workers report only typed outcomes through `bin/fm-public-followup-emit.sh`; the home that owns Relay consent and Discord thread context remains the sole outward poster.
Reconciliation rides the existing Relay poll and session-start digest, so it adds no second process, timer, or transport.
The [Relay configuration reference](configuration.md#relay-env) owns the operator setup, wire fields, generated state, limits, migration, and opt-out contract.

## Project memory belongs to projects

Durable project-intrinsic agent knowledge lives in each project's committed `AGENTS.md`.
Ship briefs prompt crewmates to create or update those files through the normal delivery path; `data/projects.md` stays a thin private registry.
Each project `AGENTS.md` carries a short `## Maintaining this file` self-governance section; `bin/fm-ensure-agents-md.sh` owns the canonical wording and injects it idempotently when creating the skeleton or reconciling an existing `AGENTS.md` that still lacks it.
It refuses a case-variant real memory file such as a lowercase `agents.md` and surfaces the mismatch for manual reconciliation.
The full ownership rule - what is project-intrinsic versus fleet-private, and how firstmate keeps the two apart without writing into project clones - is owned by [`AGENTS.md`](../AGENTS.md) (project and knowledge management).

## Operational memory routing

`/stow` sweeps the current session for durable knowledge that only exists in conversation and routes each finding to the most specific disk home.
Home-domain captain preferences go to `data/captain.md`, cross-domain shared captain preferences go to the primary home's `data/captain-shared.md`, fleet-local operational facts and gotchas go to home-local `data/learnings.md`, project-intrinsic knowledge goes through normal crewmate delivery into that project's committed `AGENTS.md`, and task-scoped notes or undone next steps go to the backlog.
Memory writes use inspect-then-update rather than blind append; the internal [`stow` skill](../.agents/skills/stow/SKILL.md) owns tier markers, decay, cold archival, and offload.
Task-scoped notes use `tasks-axi show <id> --full` followed by `tasks-axi update <id> --body-file <path>`, adding `--archive-body` when the prior body should remain recoverable.
The stow pass never writes a skill, but a separately executed, captain-approved migration may move conditional knowledge into a user-owned local skill excluded from the Firstmate clone; changes to Firstmate's tracked skills remain deliberate repository work through the normal PR pipeline.
Invoked in a primary home, `/stow` then cascades the same sweep to every registered secondmate, enumerated through `bin/fm-stow-cascade.sh`: each home is accounted and curated against its own startup-memory allowance, a live secondmate sweeps its own session, and a slow or unreachable home is reported as an exception rather than blocking the primary.

## Local clones stay fresh

The locked session-start deferred network stage, PR-based teardown, and merged-PR wake handling refresh remote-backed project clones when the clone is safe to move.
Wake-time refreshes can target a single clone by project name, so the primary home also catches up when a secondmate reports a merge from its own home.
Clean default-branch clones fast-forward to `origin/<default>`, and a clean detached HEAD that holds no unique commits is re-attached to the default branch before the same fast-forward path runs.
Dirty clones, non-default branches, detached HEADs with unique commits, diverged defaults, and default branches checked out in another worktree are reported as `STUCK:` with their behind count and left untouched.
Fetches blocked by an orphaned `.git/packed-refs.lock` use bounded retries and remove the lock only when the shared staleness proof can prove it abandoned; [configuration.md](configuration.md#toolchain) owns the recovery details and tuning knobs.
Local-only projects, clones without an origin remote, and fetch failures remain benign skips.
The refresh also prunes local branches whose remote is gone and that no worktree still needs.

## Self-updates stay safe

`/updatefirstmate` fast-forwards the running firstmate repo and registered secondmate homes from `origin`, then re-reads updated instructions and nudges updated secondmates without touching project clones.
For a remote route, the configured code root updates from its own origin on that host before the persistent home fast-forwards to the code-root commit.
The update is fast-forward only: dirty, diverged, offline, and off-default targets are reported and left untouched.
Local homes share the guarded fast-forward helper, while remote updates delegate the same safety decision to the configured host through the generic transport.
The mechanics are owned by the `/updatefirstmate` skill and firstmate's operating manual in [`AGENTS.md`](../AGENTS.md) (self-update).

## Restart-proof

Fleet state lives in each task's session-provider backend (tmux by hard default or Herdr when selected or auto-detected), no-mistakes run records, status event logs, local markdown under `data/` including `data/captain.md`, `data/captain-shared.md`, and `data/learnings.md`, and persistent secondmate homes.
For herdr, respawning after a server-restored layout closes and replaces confirmed no-agent or dead task-tab husks instead of requiring manual tab cleanup.
At session start, confirmed-dead secondmate agent endpoints are closed and relaunched through the same secondmate spawn path, while ambiguous liveness reads are left untouched to avoid duplicate supervisors.
Use `/stow` before an intentional reset when the conversation may hold durable knowledge that has not yet been written to disk; after that, the next firstmate session can reconcile and carry on.

## Development notes

The current watcher reliability work combines always-on bash triage with a durable queue for actionable wakes, generation-bound post-handling acknowledgement, deterministic re-arm recovery after watcher downtime, a race-proof singleton lock, duplicate self-eviction, drain-time liveness assertion, and a self-verifying tracked-child arm wrapper.
The presence-gated sub-supervisor (`bin/fm-supervise-daemon.sh`) provides walk-away supervision via the `/afk` skill while reusing the same shared wake classifier as the always-on watcher.
