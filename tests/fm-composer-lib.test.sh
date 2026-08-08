#!/usr/bin/env bash
# Pi composer-content classifier tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

classify() {
  fm_composer_classify_content "$1" "$2" '^Type a message\.\.\.$'
}

test_pi_empty_and_pending() {
  [ "$(classify 1 '❯')" = empty ] || fail "Pi empty prompt was not empty"
  [ "$(classify 1 '❯ Type a message...')" = empty ] || fail "Pi placeholder was not empty"
  [ "$(classify 1 '❯ write a message')" = pending ] || fail "Pi typed text was not pending"
  [ "$(classify 0 '$')" = unknown ] || fail "bare shell prompt was not unknown"
  pass "Pi composer classifier distinguishes empty, pending, and bare shell input"
}

test_ghost_extraction() {
  local result
  result=$(printf '\033[2mType a message...\033[0m' | fm_composer_strip_ghost)
  [ -z "$result" ] || fail "dim Pi placeholder was not removed: $result"
  result=$(printf '\033[38;2;240;240;240mreal text\033[0m' | fm_composer_strip_ghost)
  [ "$result" = 'real text' ] || fail "bright Pi text was removed: $result"
  pass "Pi ghost extraction preserves real input and removes placeholders"
}

test_pi_empty_and_pending
test_ghost_extraction
