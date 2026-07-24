#!/usr/bin/env bash
# Ghost-text extraction and composer-classification regressions.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

test_strip_ghost_drops_dim_keeps_normal() {
  local out
  out=$(printf '\xe2\x9d\xaf \033[2mWhat is the largest country by area?\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "$(printf '\xe2\x9d\xaf ')" ] || fail "dim run not dropped: '$out'"
  out=$(printf '\xe2\x9d\xaf real human text\n' | fm_composer_strip_ghost)
  [ "$out" = "$(printf '\xe2\x9d\xaf real human text')" ] || fail "normal text changed: '$out'"
  out=$(printf '\033[1mbold typed\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "bold typed" ] || fail "bold text wrongly dropped: '$out'"
  pass "fm_composer_strip_ghost drops dim runs and keeps normal or bold text"
}

test_strip_ghost_handles_sgr_boundaries() {
  local out
  out=$(printf '\xe2\x9d\xaf \033[2;37mpredicted\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "$(printf '\xe2\x9d\xaf ')" ] || fail "combined dim and color not dropped: '$out'"
  out=$(printf '\033[2mghost\033[22mREALTAIL\n' | fm_composer_strip_ghost)
  [ "$out" = "REALTAIL" ] || fail "normal-intensity boundary did not end dim run: '$out'"
  out=$(printf 'keep\033[0;2mdrop\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "keep" ] || fail "reset then dim was not processed left to right: '$out'"
  pass "fm_composer_strip_ghost handles combined SGR and intensity boundaries"
}

test_strip_ghost_keeps_bright_color_payloads() {
  local out
  out=$(printf '\033[38;5;2mgreen typed\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "green typed" ] || fail "palette payload was treated as dim: '$out'"
  out=$(printf '\033[38;2;224;222;244mtruecolor typed\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "truecolor typed" ] || fail "bright truecolor was treated as ghost text: '$out'"
  out=$(printf '\033[38:2::224:222:244mcolon truecolor typed\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "colon truecolor typed" ] || fail "bright colon truecolor was treated as ghost text: '$out'"
  pass "fm_composer_strip_ghost keeps bright colored text"
}

test_strip_ghost_drops_dark_truecolor() {
  local out
  out=$(printf '\xe2\x9d\xaf \033[38;2;50;47;70mType a message...\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = "$(printf '\xe2\x9d\xaf ')" ] || fail "dark truecolor placeholder not dropped: '$out'"
  out=$(printf '\033[38:2::86:82:110mmuted\033[0m\n' | fm_composer_strip_ghost)
  [ -z "$out" ] || fail "dark colon truecolor placeholder not dropped: '$out'"
  pass "fm_composer_strip_ghost drops dark truecolor placeholders"
}

test_extracted_content_classifies_safely() {
  local content verdict
  content=$(printf '\xe2\x9d\xaf \033[2mrotating suggestion\033[0m\n' | fm_composer_strip_ghost)
  verdict=$(fm_composer_classify_content 1 "$content")
  [ "$verdict" = empty ] || fail "ghost-only agent composer should be empty, got '$verdict'"
  content=$(printf '\xe2\x9d\xaf real input \033[2msuggestion\033[0m\n' | fm_composer_strip_ghost)
  verdict=$(fm_composer_classify_content 1 "$content")
  [ "$verdict" = pending ] || fail "real text plus ghost should be pending, got '$verdict'"
  content=$(printf '$\033[38;2;50;47;70mhint\033[0m\n' | fm_composer_strip_ghost)
  verdict=$(fm_composer_classify_content 0 "$content")
  [ "$verdict" = unknown ] || fail "bare shell prompt should remain unknown, got '$verdict'"
  pass "ghost extraction preserves empty, pending, and dead-shell safety"
}

test_strip_ghost_drops_dim_keeps_normal
test_strip_ghost_handles_sgr_boundaries
test_strip_ghost_keeps_bright_color_payloads
test_strip_ghost_drops_dark_truecolor
test_extracted_content_classifies_safely
