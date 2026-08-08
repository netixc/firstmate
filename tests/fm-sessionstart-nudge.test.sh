#!/usr/bin/env bash
# Pi session-start nudge tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-session-nudge-pi)
fm_git_identity fmtest fmtest@example.invalid

make_primary() {
  local dir=$1
  mkdir -p "$dir/bin" "$dir/state"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m initial
  : > "$dir/AGENTS.md"
  cp "$ROOT/bin/fm-sessionstart-nudge.sh" "$ROOT/bin/fm-gate-refuse-lib.sh" \
    "$ROOT/bin/fm-primary-scope-lib.sh" "$ROOT/bin/fm-operational-input.sh" "$dir/bin/"
  chmod +x "$dir/bin/"*.sh
}

test_pi_nudge() {
  local root="$TMP_ROOT/primary" out
  make_primary "$root"
  out=$(FM_HOME="$root" FM_ROOT_OVERRIDE="$root" "$root/bin/fm-sessionstart-nudge.sh")
  assert_contains "$out" 'FIRSTMATE_OP:' "Pi nudge did not use the operational envelope"
  assert_contains "$out" "Run \`bin/fm-session-start.sh\` now" "Pi nudge did not name the session-start digest"
  pass "Pi session-start extension nudge carries one canonical instruction"
}

test_nonprimary_stays_silent() {
  local root="$TMP_ROOT/nonprimary" out
  mkdir -p "$root/state"
  out=$(FM_HOME="$root" FM_ROOT_OVERRIDE="$root" "$ROOT/bin/fm-sessionstart-nudge.sh")
  [ -z "$out" ] || fail "non-primary nudge emitted output: $out"
  pass "session-start nudge stays silent outside a Pi primary home"
}

test_pi_nudge
test_nonprimary_stays_silent
