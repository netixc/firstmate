#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$ROOT/bin/fm-busy-lib.sh"
TMP=$(fm_test_tmproot busy-pi)
mkdir -p "$TMP"
printf 'g1\n' > "$TMP/t.busy-gen"
printf 'v1 gen=g1 seq=1 state=busy source=pi-ext event=agent-start ts=1\n' > "$TMP/t.busy-state"
[ "$(fm_busy_classify tmux pane pi t "$TMP")" = 'busy pi-ext' ] || fail "Pi busy record rejected"
pass "Pi busy record accepted"
printf 'v1 gen=g1 seq=2 state=idle source=pi-ext event=agent-settled ts=2\n' > "$TMP/t.busy-state"
[ "$(fm_busy_classify tmux pane pi t "$TMP")" = 'idle pi-ext' ] || fail "Pi idle record rejected"
pass "Pi idle record accepted"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
 [ "$(fm_busy_classify tmux pane "$old" t "$TMP")" = 'unknown unsupported-harness' ] || fail "$old metadata normalized"
 pass "$old metadata remains unsupported"
done
