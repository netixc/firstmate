# Plain Pi supervision verification

## Real plain Pi model and identity

The current guard requires Pi 0.84.4 and runs the authenticated `openai-codex/gpt-5.6-sol` model with low thinking.
It asks the model to execute the public harness detector from a Pi child process and requires exact `pi` output.
It then validates extension registration, interrupt, exit, and transactional relaunch through exact task-bound metadata in a generated non-default Herdr lab.
The pane launch uses the preflighted Pi executable, an isolated agent directory containing only copied authentication, explicit Firstmate home/state/data routing, and only the two supervision extensions named on the command line.

```sh
FM_PI_ONLY_LIVE_E2E=1 tests/fm-pi-only-live-e2e.test.sh
```

Current acceptance lines are:

```text
ok - real Pi supervision extensions preserve plain-Pi identity
ok - real Pi interrupt lifecycle control succeeds through Herdr
ok - real Pi transactional relaunch preserves profile and exact Herdr identity
ok - real Pi replacement exit lifecycle control succeeds through Herdr
```

The separate production Herdr model lifecycle guard is `FM_HERDR_PI_REAL_MODEL_E2E=1 tests/fm-herdr-pi-real-model-e2e.test.sh`; it covers exact identity, steering, interrupt, native watcher delivery, liveness, and cleanup with user-level extensions disabled.
`tests/fm-pi-only-harness.test.sh` supplies portable public-interface coverage for exact identity, migration refusal, control, and semantic busy state.

## Wedge-alarm channels

The two real notification channels were bounded manually on 2026-07-10 on macOS 26.5.2 with Herdr 0.7.3.
Automated suites never execute these real notification commands.

```sh
/usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "FIRSTMATE TEST - IGNORE" sound name "Basso"' -e 'end run' 'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)'
herdr notification show 'FIRSTMATE TEST - IGNORE' --body 'FIRSTMATE TEST - IGNORE (wedge-alarm channel verification)' --sound request
```

Observed Notification Center output was empty stdout with exit 0 and one banner.
Observed Herdr output was `{"id":"cli:notification:show","result":{"reason":"shown","shown":true,"type":"notification_show"}}`.
`tests/fm-daemon.test.sh` covers command-channel argument and process-group safety without producing a notification.
