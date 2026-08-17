## Recovery

For local `kind=secondmate` meta with no window, treat the secondmate as a dead persistent direct report and respawn it with:

```sh
bin/fm-spawn.sh <id> --secondmate
```

Use the recorded `home=` in meta.
If meta is missing but `data/secondmates.md` still registers the secondmate, respawn from the registry entry and its persistent home.
For a remote route, the same command probes and relaunches only on the configured host.
An SSH transport failure or unreadable remote endpoint remains unknown and must be reconciled on that host; never launch a local replacement.
`fm-crew-state`'s `unknown` or `worktree gone` result and an unconfirmed `fm-send` to a remote second mate can be false negatives, so confirm the endpoint on the configured host before relaunching it only through `bin/fm-spawn.sh <id> --secondmate`; never close or kill its Herdr pane directly because that strands the endpoint binding.
Respawn re-resolves the secondmate harness from current config, uses the same guarded pre-launch sync, and re-propagates inherited local material, so recovered secondmates converge inherited config items and shared captain preferences whenever their home validates; tracked-file sync remains guarded separately.
If the secondmate is already running and only inherited local material changed, prefer `bin/fm-config-push.sh` over respawning.
To move a live LOCAL secondmate onto a newly pinned harness, model, or effort without a full recovery, set `config/secondmate-harness` and then relaunch it with `bin/fm-control.sh <id> relaunch`, which re-resolves that pin, stops the agent, and launches the replacement in the same home ([`docs/agent-control.md`](../../../docs/agent-control.md)).
That plane refuses a remotely placed secondmate by name, because its agent runs on another host where none of the plane's postconditions can be read; use the remote route's own relaunch path for those.

Do not reconstruct a secondmate's whole tree from the main home.
The main firstmate reconciles only direct reports.
Each secondmate is a firstmate in its own home, so it runs recovery on startup and reconciles its own crewmates.
A secondmate's recovery reconciles only work that is already its own and then idles.
It never initiates a survey or audit during recovery.

