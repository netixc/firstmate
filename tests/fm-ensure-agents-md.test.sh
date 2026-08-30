#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP=$(fm_test_tmproot ensure-agents)
mkdir -p "$TMP/project"
"$ROOT/bin/fm-ensure-agents-md.sh" "$TMP/project" >/dev/null
assert_present "$TMP/project/AGENTS.md" "creates AGENTS.md"
assert_grep '## Maintaining this file' "$TMP/project/AGENTS.md" "adds maintenance section"
before=$(cksum "$TMP/project/AGENTS.md")
"$ROOT/bin/fm-ensure-agents-md.sh" "$TMP/project" >/dev/null
after=$(cksum "$TMP/project/AGENTS.md")
[ "$before" = "$after" ] || fail "second run changed AGENTS.md"
pass "second run is idempotent"
