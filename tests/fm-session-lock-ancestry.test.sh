#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$ROOT/bin/fm-session-lock-lib.sh"
for path in /opt/homebrew/bin/pi /usr/local/bin/pi-launcher /Applications/Pi; do
 fm_harness_process_matches "$path" "$path" || fail "plain Pi process not recognized: $path"
 pass "plain Pi process recognized: $path"
done
for path in /usr/bin/claude /usr/bin/codex /usr/bin/pi-signed /usr/bin/grok /usr/bin/kimi /usr/bin/muse /usr/bin/cursor-agent; do
 if fm_harness_process_matches "$path" "$path"; then fail "excluded process recognized: $path"; fi
 pass "excluded process remains unsupported: $path"
done
