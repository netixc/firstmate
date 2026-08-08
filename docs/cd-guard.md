# Pi working-directory command guard

Pi's primary extension calls `bin/fm-cd-pretool-check.sh --command <command>` before commands that would move the primary session outside its Firstmate root.
The guard protects session-start, supervision, and local operational paths from an accidental persistent directory change.
It does not replace ordinary task isolation, which `bin/fm-spawn.sh` and generated task briefs enforce independently.

The guard accepts scoped subshell or command forms that preserve the primary process directory and rejects unsafe persistent changes.
`bin/fm-arm-command-policy.mjs` owns the shared command parsing boundary.
See [supervision verification](verification/supervision.md) for executable evidence.
