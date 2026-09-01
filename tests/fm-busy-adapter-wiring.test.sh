#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP=$(fm_test_tmproot busy-wire-pi)
mkdir -p "$TMP"
gen=$("$ROOT/bin/fm-busy-event.sh" arm "$TMP" task)
"$ROOT/bin/fm-busy-event.sh" apply "$TMP" task idle --gen "$gen" --source pi-ext --event agent-settled
. "$ROOT/bin/fm-busy-lib.sh"
[ "$(fm_busy_classify legacy-provider pane pi task "$TMP")" = 'idle pi-ext' ] || fail "Pi lifecycle writer did not classify"
pass "Pi lifecycle writer and classifier integrate"
[ "$(fm_busy_classify legacy-provider pane pi-signed task "$TMP")" = 'unknown unsupported-harness' ] || fail "legacy signed identity was normalized"
pass "legacy signed identity remains unsupported"
for malformed in \
  "v1 gen=$gen seq=1:2 state=idle source=pi-ext event=agent-settled ts=3" \
  "v1 gen=$gen seq=1 state=idle source=pi-ext event=agent-settled ts=2:3"
do
  printf '%s\n' "$malformed" > "$(fm_busy_record_path "$TMP" task)"
  [ "$(fm_busy_classify legacy-provider pane pi task "$TMP")" = 'unknown malformed' ] \
    || fail "malformed numeric lifecycle field was accepted"
done
pass "Pi lifecycle classifier rejects non-decimal sequence and timestamp fields"
