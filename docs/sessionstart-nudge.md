# Pi session-start delivery

Pi's tracked `fm-primary-turnend-guard.ts` extension runs `bin/fm-sessionstart-run.sh` for supported session lifecycle events and injects the wrapper's output through Pi's non-displayed custom-message path.
For a startup, the wrapper runs the one required `bin/fm-session-start.sh` digest before Pi's first model turn.
For Pi's same-process `new` event and for compaction, it re-emits the digest after a proven complete startup and otherwise finishes the full startup first.
For resume and fork events, it delegates to the marked nudge wrapper because prior context is restored.

`bin/fm-sessionstart-run.sh` owns source routing, completion proof, and the fallback for malformed sources.
`bin/fm-session-start.sh` remains the sole owner of ordering, lock safety, bootstrap, wake drain, and emitted Pi supervision instructions.
The extension retains at most 512 KiB of wrapper output and appends a loud truncation marker with direct-inspection guidance when delivery exceeds that bound.
It does not arm supervision itself.

Firstmate confirms that the complete digest is present and runs `bin/fm-session-start.sh` itself only when the extension did not deliver it.
A trusted project loads the tracked `.pi/extensions/` files automatically.

`tests/fm-sessionstart-nudge.test.sh`, `tests/fm-session-start.test.sh`, and `tests/fm-pi-primary-types.test.sh` are the deterministic entry points.
See [supervision verification](verification/supervision.md) for current Pi delivery evidence.
