# Pi session-start delivery

Pi's tracked primary extension delivers the one required `bin/fm-session-start.sh` invocation when a Firstmate session starts, resumes, reloads, forks, or begins a new session.
The extension injects the instruction through Pi's supported message path.
It does not run the digest, acquire the lock, drain wakes, bootstrap, or arm supervision itself.

Firstmate confirms that the complete digest is present and runs the command itself only when the extension did not deliver it.
The session-start command remains the sole owner of ordering, lock safety, bootstrap, wake drain, and emitted Pi supervision instructions.
A trusted project loads the tracked `.pi/extensions/` files automatically.

See [supervision verification](verification/supervision.md) for current Pi delivery evidence.
