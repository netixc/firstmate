# Pi turn-end guard

Pi's tracked `fm-primary-turnend-guard.ts` extension is the primary-session "no turn ends blind" backstop.
After Pi settles a logical run, the extension invokes `bin/fm-turnend-guard.sh`.
The predicate exits successfully when no supervision is needed or the current home already has a healthy watcher.
It exits 2 only when work, a process-event source, or Relay needs supervision and Pi's watcher is missing or unhealthy.

On exit 2, the extension sends one bounded follow-up through Pi's supported follow-up delivery.
The follow-up tells Firstmate to drain the durable queue and repair supervision only if the extension reported a missing, failed, or unhealthy cycle.
The extension, not a shell background job, owns watcher continuity.
Child worker worktrees are out of scope.

Pi's primary extension also provides the turn-end behavior for persistent secondmate homes.
The guard never grants merge, discard, security, or approval authority.
It is a supervision backstop rather than permission to omit the live watcher cycle.

See [supervision verification](verification/supervision.md) for current executable and live Pi evidence.
