#!/usr/bin/env bash
# tests/fm-composer-ghost.test.sh - ANSI ghost-text classification shared by current readers.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

test_dim_ghost_is_removed() {
  local out
  out=$(printf '\xe2\x9d\xaf \033[2mWhat should I do next?\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = '❯ ' ] || fail "dim suggestion text should be removed, got '$out'"
  pass "fm_composer_strip_ghost: removes dim suggestion text"
}

test_dark_truecolor_placeholder_is_removed() {
  local out
  out=$(printf '\xe2\x9d\xaf \033[38;2;80;76;100mType a message...\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = '❯ ' ] || fail "dark truecolor placeholder should be removed, got '$out'"
  pass "fm_composer_strip_ghost: removes dark truecolor placeholder text"
}

test_bright_truecolor_input_is_preserved() {
  local out
  out=$(printf '\xe2\x9d\xaf \033[38;2;224;222;244mShip the fix\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = '❯ Ship the fix' ] || fail "bright input should be preserved, got '$out'"
  pass "fm_composer_strip_ghost: preserves bright truecolor input"
}

test_plain_input_is_preserved() {
  local out
  out=$(printf ' > actual input\n' | fm_composer_strip_ghost)
  [ "$out" = ' > actual input' ] || fail "plain input should be preserved, got '$out'"
  pass "fm_composer_strip_ghost: preserves plain input"
}

test_content_classifier_distinguishes_empty_and_pending() {
  local out
  out=$(fm_composer_classify_content 1 '❯')
  [ "$out" = empty ] || fail "a bare prompt glyph should classify empty, got '$out'"
  out=$(fm_composer_classify_content 1 ' ❯ Ship the fix')
  [ "$out" = pending ] || fail "real composer input should classify pending, got '$out'"
  out=$(fm_composer_classify_content 0 '$')
  [ "$out" = unknown ] || fail "an unbordered shell prompt must classify unknown, got '$out'"
  pass "fm_composer_classify_content: separates empty, pending, and unsafe shell content"
}

test_dim_ghost_is_removed
test_dark_truecolor_placeholder_is_removed
test_bright_truecolor_input_is_preserved
test_plain_input_is_preserved
test_content_classifier_distinguishes_empty_and_pending
