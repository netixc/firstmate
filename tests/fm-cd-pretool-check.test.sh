#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CHECK="$ROOT/bin/fm-cd-pretool-check.sh"
out=$("$CHECK" --command 'printf shipshape')
[ -z "$out" ] || fail "ordinary Pi command produced output"
pass "ordinary Pi command allowed"
for oldflag in --claude --cursor; do
 set +e; out=$("$CHECK" "$oldflag" --command true 2>&1); rc=$?; set -e
 [ "$rc" -eq 2 ] || fail "$oldflag transport was accepted"
 assert_contains "$out" 'unknown argument' "$oldflag transport is unsupported"
done
