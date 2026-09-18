---
name: quiet
description: >-
  Enter quiet posture when the captain invokes /quiet or asks for quiet mode, quiet-while-present, or fewer routine updates while they stay in the session.
  It records quiet posture, keeps Pi's ordinary supervision cycle active, and exits only on an explicit `/quiet off`.
user-invocable: true
metadata:
  internal: true
---

# quiet

Quiet posture is presentation-only: the captain stays present, Pi's ordinary supervision cycle remains active, routine updates stay batched, and captain-relevant decisions, failures, credentials, or review-ready work still surface.

## Enter

1. Run `bin/fm-afk-launch.sh quiet`.
   This records `quiet` in `state/.afk` through the posture owner while the existing supervision cycle continues.
   If an away-posture record is already active, the command refuses; complete the `/afk` return first.
2. Confirm: "Captain, quiet mode is active; I will batch routine updates and surface only decisions, failures, credentials, or review-ready work - ordinary chat will not exit this, say `/quiet off` when you want normal per-notification responses back."
3. Keep the existing Pi supervision cycle active exactly as in ordinary posture.

## Exit

Only an explicit `/quiet off`, or a plain request to leave quiet mode, exits it.
Run `bin/fm-afk-return.sh` and follow its durable catch-up procedure, then resume normal presentation.

Every other captain message is ordinary work and leaves quiet posture active.
A repeated `/quiet` refreshes the marker through `bin/fm-afk-launch.sh quiet`.

## Authority

Quiet posture changes presentation, never approval authority.
Merge, destructive, irreversible, security-sensitive, credential, and decision boundaries remain unchanged.
