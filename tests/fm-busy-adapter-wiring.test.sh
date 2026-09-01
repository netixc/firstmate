#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP=$(fm_test_tmproot busy-wire-pi)
mkdir -p "$TMP"
gen=$("$ROOT/bin/fm-busy-event.sh" arm "$TMP" task)
"$ROOT/bin/fm-busy-event.sh" apply "$TMP" task idle --gen "$gen" --source pi-ext --event agent-settled
. "$ROOT/bin/fm-busy-lib.sh"
[ "$(fm_busy_classify tmux pane pi task "$TMP")" = 'idle pi-ext' ] || fail "Pi lifecycle writer did not classify"
pass "Pi lifecycle writer and classifier integrate"
[ "$(fm_busy_classify tmux pane pi-signed task "$TMP")" = 'unknown unsupported-harness' ] || fail "legacy signed identity was normalized"
pass "legacy signed identity remains unsupported"
