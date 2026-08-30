#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
GUARD="$ROOT/bin/fm-turnend-guard.sh"
set +e; out=$(printf '{}' | "$GUARD" --claude 2>&1); rc=$?; set -e
[ "$rc" -eq 2 ] || fail "excluded turn-end mode was accepted"
assert_contains "$out" 'usage:' "excluded turn-end mode reports unsupported interface"
# Empty and malformed payloads step aside safely.
printf '' | "$GUARD"
printf 'not-json' | "$GUARD"
pass "plain Pi guard safely ignores unusable payloads"
assert_grep 'fm-primary-turnend-guard.ts' "$ROOT/docs/turnend-guard.md" "Pi extension is documented owner"
