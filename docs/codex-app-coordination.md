# Codex App coordination

Codex App is a companion coordination surface, not a Firstmate worker runtime or session backend.
The only supported worker runtime is plain Pi, and the only supported session backends are tmux and Herdr.
`codex-app` is never accepted in `config/backend`, `FM_BACKEND`, task metadata, or worker launch arguments, and Firstmate has no `bin/backends/codex-app.sh`.

Codex Desktop host tools may create, read, steer, and archive visible companion threads when the current conversation is running inside Desktop and those tools are available.
Those host tools belong to the Desktop conversation; shell scripts and spawned Pi workers cannot assume access to them.
A thread ledger, control-socket proxy, or app-server experiment does not turn a Desktop thread into a backend.

The internal `firstmate-codexapp` skill owns supported choreography:

- confirm the target repository is already saved as a Desktop project;
- use Desktop host tools rather than shell imitation;
- keep writable repository work in the Desktop-created directory;
- verify any requested status-file return channel instead of assuming it;
- reconcile direct human intervention from the visible thread; and
- archive through the exposed Desktop host tool.

A companion thread that cannot write a requested Firstmate status path remains unsupervised companion work.
It must not be reported as a dispatched Firstmate task or used to bypass Pi, tmux, Herdr, isolated-copy, delivery, or merge rules.

[`verification/runtime-backends.md`](verification/runtime-backends.md#codex-app-host-tools) records the Desktop host-tool smoke evidence without making Codex App part of the runtime matrix.
