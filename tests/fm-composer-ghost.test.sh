#!/usr/bin/env bash
# ANSI ghost/placeholder extraction used by Herdr composer classification.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-composer-lib.sh
. "$ROOT/bin/fm-composer-lib.sh"

test_dim_runs_drop() {
  local out
  out=$(printf '› \033[2mWhat is the largest country?\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = '› ' ] || fail "dim run not dropped: '$out'"
  out=$(printf '❯ real human text\n' | fm_composer_strip_ghost)
  [ "$out" = '❯ real human text' ] || fail "normal text was dropped"
  out=$(printf '\033[1mbold typed\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = 'bold typed' ] || fail "bold typed text was dropped"
  pass "composer ghost extraction drops dim runs and keeps typed text"
}

test_sgr_transitions() {
  local out
  out=$(printf '\033[2mghost\033[22mREALTAIL\n' | fm_composer_strip_ghost)
  [ "$out" = REALTAIL ] || fail "SGR 22 did not restore visible text"
  out=$(printf 'keep\033[0;2mdrop\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = keep ] || fail "combined reset/dim transition misclassified"
  out=$(printf '\033[38:2::224:222:244mcolored typed\033[0m\n' | fm_composer_strip_ghost)
  [ "$out" = 'colored typed' ] || fail "color payload containing 2 was mistaken for dim"
  pass "composer ghost extraction handles SGR transitions and color payloads"
}

test_dim_runs_drop
test_sgr_transitions
