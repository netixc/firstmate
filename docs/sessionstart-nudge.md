# Native session-start adapters

AGENTS.md section 3 is the authoritative behavioral contract for session start.
This file owns how tracked native session-open adapters deliver that contract and the compatibility limits that require two tiers.

Firstmate ships two session-open tiers, and the tier is a property of the harness surface rather than the home.

| Tier | What the adapter does | Used by |
| --- | --- | --- |
| Run | Executes `bin/fm-session-start.sh` in the hook and lets its ordered digest reach model context before the first turn. | Claude, `codex exec`, and Pi. |
| Nudge | Asks the agent to run the digest through the native adapter or the tracked session-start instruction. | Grok, Codex interactive, and run-tier sources routed to the nudge. |

The run tier exists because an agent can defer an instruction, including when a first-command skill has its own read-only path.
Running the digest inside the hook removes that discretion, so even a session whose first command is a skill has already taken the helm.
The nudge tier remains the floor for surfaces that cannot carry hook output into model context, and it is never a second contract because both tiers end in `bin/fm-session-start.sh`.

## Source routing

`bin/fm-sessionstart-run.sh` is the single owner of what a session-open source means, so no harness matcher string encodes that policy.
It takes `--source <name>` when the adapter knows the source natively and otherwise reads the `source` field from a Claude/Codex-shaped JSON hook payload on stdin.

| Source | Action | Why |
| --- | --- | --- |
| `startup`, `new` | Full digest | This process has not taken the helm. |
| `clear`, `compact` | `--reemit` after a proven complete startup, otherwise full digest | This process normally has the helm and lost only its context, but an earlier hook may have been truncated after acquiring the lock. |
| `resume`, `reload`, `fork` | Delegate to the nudge wrapper | Prior context is restored, so re-running is redundant when the lock is still ours and an instruction is enough when a new process resumed an old session. |
| Unreadable or unrecognized | Full digest | Taking the helm redundantly is cheap and idempotent, while not taking it is the failure this tier prevents. |

Current harness ownership of the lock and its matching `state/.session-start-complete` record together are the idempotency interlock for the scheme.
The full digest clears that completion record after acquiring the lock and republishes the lock owner's pid only after every stage completes, so `clear` or `compact` cannot skip startup sweeps after a truncated run.
`bin/fm-session-start.sh --reemit` owns which work a re-emit skips, and its header is the single owner of that list.

## Runtime bound

The run tier blocks session initialization while the digest runs, so `bin/fm-session-start.sh` bounds itself rather than betting on each harness hook timeout.
The whole digest runs as one bounded child, defaulting to 120 seconds through `FM_SESSION_START_TIMEOUT`.
The shared timeout owner falls back to a pure-Bash process-group watchdog when timeout, gtimeout, and perl are unavailable, so no supported host runs the digest unbounded.
The child writes directly to hook output, then the parent prints a `STARTUP TRUNCATED` banner naming the incomplete stage and stages not emitted when the bound is hit.
The tracked hook timeouts sit above that budget so the harness does not preempt the banner.

## Shared wrapper and safety

`bin/fm-sessionstart-run.sh` and `bin/fm-sessionstart-nudge.sh` share the same two eligibility owners.
They source `bin/fm-gate-refuse-lib.sh` and stay silent for a no-mistakes gate agent identified by `NO_MISTAKES_GATE` or a `.no-mistakes/repos/*.git` git-common-dir.
They share `bin/fm-primary-scope-lib.sh` with `bin/fm-turnend-guard.sh`, so every hook uses one primary-detection owner.
The Guard Predicates section of [`turnend-guard.md`](turnend-guard.md#guard-predicates) owns marker validation, plain-checkout detection, and required Firstmate-shaped paths.

The nudge payload starts with U+2063 and the stable `FIRSTMATE_OP: ` label, carries the current `session-start` protocol kind, and retains exactly ``Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.`` as its body.
The Ahoy skill owns the rule that this marked operational input is never a captain-authored session boundary, including its narrow legacy compatibility cases.
Every path in both wrappers exits 0, including malformed state and adapter errors, because a Claude SessionStart exit 2 blocks session initialization.
A lock another session holds, broken GitHub authentication, and a truncated digest therefore surface as digest text rather than a refusal to open the session.

## Harness transports

| Harness | Tier | Tracked transport | Current compatibility |
| --- | --- | --- | --- |
| Claude | Run | `.claude/settings.json` registers one unmatched `SessionStart` hook through `CLAUDE_PROJECT_DIR` with a 180 second timeout, and the wrapper reads the hook payload source. | Native hook-output context injection is supported. |
| Codex exec | Run | `.codex/hooks.json` anchors to the hook process working directory, verifies a Firstmate-shaped hook-bearing root, and pipes the hook payload into the wrapper with a 180 second timeout. | Native hook-output context injection is supported under `codex exec`. |
| Codex interactive | Nudge | The tracked `AGENTS.md` session-start instruction and Ahoy step-zero fallback remain visible when the project hook does not fire. | The interactive surface does not provide the tracked project session-open delivery used by `codex exec`. |
| Pi | Run | `.pi/extensions/fm-primary-turnend-guard.ts` maps `session_start` reasons and `session_compact` onto wrapper sources, then injects the output with `pi.sendMessage`. | The custom message reaches model context without racing an initial positional prompt. |
| Grok | Nudge | `.grok/hooks/fm-primary-sessionstart-nudge.json` registers a project `SessionStart` hook through inline-defaulted `${GROK_WORKSPACE_ROOT:-}`. | The project hook runs when the checkout is trusted, but its output does not reach model context. |

Pi is the only adapter that injects a message rather than hook output, so whatever it injects must carry operational provenance or the Ahoy skill would have to guess whether it was captain-authored.
The extension encodes an unencoded digest as `session-start` operational input before sending it and leaves an already encoded nudge alone.
It retains at most 512 KiB for message delivery and appends a loud `PI SESSION-START DELIVERY TRUNCATED` marker with direct-inspection guidance whenever the digest is incomplete.

Pi's watcher and turn-end extensions coordinate their separate lifecycle events without racing session-start delivery.
Grok's guaranteed-loading alternative is a global token-guarded hook like the pattern used by `bin/fm-spawn.sh`.
That alternative expands trust and writes outside this repository, so Firstmate never installs it or grants folder trust automatically.

## Regression coverage

`tests/fm-sessionstart-nudge.test.sh` proves nudge-wrapper silence for both gate signals, an unmarked linked worktree, a missing state directory, and an already-owned lock.
It separately proves run-wrapper source routing end to end against a real `fm-session-start.sh`, including completion-gated `--reemit` selection, resume delegation, an unrecognized source falling through to the full digest, and bounded delivery of an oversized Pi digest.
`tests/fm-session-start.test.sh` proves the runtime bound through the forced pure-Bash fallback, including a resistant digest that exceeds its budget, its grandchild cleanup, its incomplete-stage banner, and absence of completion proof.
`tests/fm-turnend-guard.test.sh`, `tests/fm-pi-watch-extension.test.sh`, and `tests/fm-daemon.test.sh` cover marked guard, monitoring, and away-mode delivery.

[`verification/supervision.md`](verification/supervision.md#native-session-start-delivery) records active version-scoped transport evidence.
