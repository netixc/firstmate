# Plain Pi supervision verification

## Real plain Pi model and identity

Date: 2026-08-30.
Version: Pi 0.84.4.
Model: `openai-codex/gpt-5.6-sol` with low thinking.

```sh
FM_PI_ONLY_LIVE_E2E=1 tests/fm-pi-only-live-e2e.test.sh
```

```text
ok - real Pi extensions register lifecycle identity (Pi 0.84.4)
ok - real Pi interrupt and exit lifecycle control succeed (Pi 0.84.4)
ok - real Pi transactional relaunch preserves profile metadata (Pi 0.84.4)
```

The test runs the real model through plain `pi`, asks it to execute the public harness detector from a Pi child process, and requires exact `pi` output.
The production Herdr endpoint lifecycle is covered by `FM_HERDR_PI_REAL_MODEL_E2E=1 tests/fm-herdr-pi-real-model-e2e.test.sh`, including exact identity, steering, interrupt, native watcher delivery, liveness, and cleanup.
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
