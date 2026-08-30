#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
out=$("$ROOT/bin/fm-supervision-instructions.sh" --harness pi)
assert_contains "$out" 'primary harness: pi' "Pi protocol heading"
assert_contains "$out" 'Pi extension already owns watcher continuity' "Pi ordinary wake owner"
for old in pi-signed claude codex opencode grok cursor; do
  set +e; out=$("$ROOT/bin/fm-supervision-instructions.sh" --harness "$old" 2>&1); rc=$?; set -e
  [ "$rc" -eq 2 ] || fail "$old primary was not rejected"
  assert_contains "$out" 'unsupported primary harness' "$old primary reports migration"
done
