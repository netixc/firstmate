#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$ROOT/bin/fm-session-lock-lib.sh"

fm_harness_process_matches /opt/homebrew/bin/pi /opt/homebrew/bin/pi \
  || fail "plain Pi process not recognized"
pass "exact plain Pi process is recognized"

for path in \
  /usr/local/bin/pi-launcher \
  /Applications/Pi \
  /usr/bin/claude \
  /usr/bin/codex \
  /usr/bin/pi-signed \
  /usr/bin/grok \
  /usr/bin/kimi \
  /usr/bin/muse \
  /usr/bin/cursor-agent
do
  if fm_harness_process_matches "$path" "$path"; then
    fail "excluded process recognized: $path"
  fi
  pass "excluded process remains unsupported: $path"
done
