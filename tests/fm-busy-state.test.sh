#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$ROOT/bin/fm-busy-lib.sh"
TMP=$(fm_test_tmproot busy-pi)
mkdir -p "$TMP"
printf 'g1\n' > "$TMP/t.busy-gen"
printf 'v1 gen=g1 seq=1 state=busy source=pi-ext event=agent-start ts=1\n' > "$TMP/t.busy-state"
[ "$(fm_busy_classify legacy-provider pane pi t "$TMP")" = 'busy pi-ext' ] || fail "Pi busy record rejected"
pass "Pi busy record accepted"
printf 'v1 gen=g1 seq=2 state=idle source=pi-ext event=agent-settled ts=2\n' > "$TMP/t.busy-state"
[ "$(fm_busy_classify legacy-provider pane pi t "$TMP")" = 'idle pi-ext' ] || fail "Pi idle record rejected"
pass "Pi idle record accepted"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
 [ "$(fm_busy_classify legacy-provider pane "$old" t "$TMP")" = 'unknown unsupported-harness' ] || fail "$old metadata normalized"
 pass "$old metadata remains unsupported"
done

ALT=$(fm_test_tmproot busy-alt-state)
mkdir -p "$ALT"
META="$ALT/task.meta"
printf '%s\n' 'backend=herdr' 'window=lab:w1:p2' 'harness=pi' > "$META"
fm_backend_of_meta() { sed -n 's/^backend=//p' "$1" | tail -1; }
fm_backend_target_of_meta() { sed -n 's/^window=//p' "$1" | tail -1; }
fm_meta_get() { sed -n "s/^$2=//p" "$1" | tail -1; }
fm_backend_busy_state() {
  [ "$4" = "$META" ] || fail "busy classifier consulted ambient metadata: ${4:-missing}"
  printf busy
}
[ "$(fm_busy_classify_meta "$META" task "$ALT")" = 'busy herdr-native' ] \
  || fail "metadata classifier did not use its exact alternate-state metadata"
pass "metadata classifier preserves the exact alternate state root"
