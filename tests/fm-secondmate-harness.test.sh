#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP=$(fm_test_tmproot secondmate-pi)
mkdir -p "$TMP/config"
printf 'pi model/test high\n' > "$TMP/config/secondmate-harness"
H="$ROOT/bin/fm-harness.sh"
[ "$(FM_HOME="$TMP" "$H" secondmate)" = pi ] || fail "secondmate did not resolve Pi"
[ "$(FM_HOME="$TMP" "$H" secondmate-model)" = model/test ] || fail "secondmate model lost"
[ "$(FM_HOME="$TMP" "$H" secondmate-effort)" = high ] || fail "secondmate effort lost"
pass "plain Pi secondmate model and effort resolve"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
 printf '%s\n' "$old" > "$TMP/config/secondmate-harness"
 set +e; out=$(FM_HOME="$TMP" "$H" secondmate 2>&1); rc=$?; set -e
 [ "$rc" -eq 2 ] || fail "$old secondmate identity accepted"
 assert_contains "$out" 'unsupported harness' "$old secondmate identity reports migration"
done
