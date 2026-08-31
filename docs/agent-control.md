# Plain Pi agent control

`bin/fm-control.sh <task-id> interrupt|exit|relaunch` is the only lifecycle control interface.
`bin/fm-control-lib.sh` owns Pi's exact mechanics: one Escape interrupts, `/quit` exits, and relaunch starts fresh plain Pi from durable instructions in the same isolated copy through the parent launcher.
Resume is unsupported because Pi has no deterministic pane-resume contract.

Control requires metadata recording exact `harness=pi`.
Any other value is an explicit unsupported migration result before keys or commands are delivered.
The selected session provider must support the required key and prove the postcondition; otherwise control refuses rather than guessing.
Text steering remains separate in `bin/fm-send.sh`.

`tests/fm-pi-only-harness.test.sh` pins the public identity and mechanics.
Retained session-provider smoke suites exercise delivery and endpoint postconditions.
