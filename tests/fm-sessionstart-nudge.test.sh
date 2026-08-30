#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
out=$("$ROOT/bin/fm-supervision-instructions.sh" --harness pi)
assert_contains "$out" 'primary harness: pi' "session startup renders plain Pi protocol"
for old in pi-signed claude codex opencode grok cursor; do
 set +e; out=$("$ROOT/bin/fm-supervision-instructions.sh" --harness "$old" 2>&1); rc=$?; set -e
 [ "$rc" -eq 2 ] || fail "$old startup protocol was accepted"
 assert_contains "$out" 'unsupported primary harness' "$old startup protocol reports migration"
done
