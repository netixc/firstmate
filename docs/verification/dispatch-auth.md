# Pi dispatch and authentication evidence

Dispatch candidates are Pi model and thinking profiles, never alternate worker runtimes.
Model support and provider identity come from the current authenticated `pi --list-models [search]` catalog.
Quota evidence comes from one `quota-axi --json` snapshot and, when needed, `quota-axi auth --json`.

A provider/model identifier remains only a Pi catalog identifier.
For example, `openai-codex/gpt-5.6-luna` and `xai/grok-4.1` select Pi-hosted provider models rather than another terminal runtime.
Do not infer credentials, quota scopes, or provider family from a prefix alone.

`tests/fm-spawn-dispatch-profile.test.sh` proves dispatch JSON rejects a runtime field, requires a model, accepts only Pi thinking values, and passes the selected model and thinking to Pi.
`tests/fm-harness-pi.test.sh` proves obsolete local runtime-selection configuration blocks launch pending explicit local migration.
The `quota-array-dispatch` skill owns candidate accounting, uncertainty handling, runway, reserve, and tie procedures.
