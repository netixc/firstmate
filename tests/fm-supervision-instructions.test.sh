#!/usr/bin/env bash
# Tests for Pi supervision instruction rendering.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-supervision-instructions)
RENDER="$ROOT/bin/fm-supervision-instructions.sh"

test_pi_block() {
  local out
  out=$("$RENDER")
  assert_contains "$out" "SUPERVISION OPERATING INSTRUCTIONS - Pi primary" "Pi heading missing"
  assert_contains "$out" "Mode: Pi extension background wake." "Pi snippet missing"
  pass "renderer prints the Pi supervision block"
}

test_retired_harness_selector_is_rejected() {
  local out rc=0
  out=$("$RENDER" --harness pi 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "retired harness selector unexpectedly succeeded"
  assert_contains "$out" "unknown argument: --harness" "retired selector was not clearly rejected"
  pass "renderer rejects the retired worker-runtime selector"
}

test_conditional_stanzas() {
  local home config out
  home="$TMP_ROOT/conditional-home"
  config="$TMP_ROOT/conditional-config"
  mkdir -p "$home/state" "$home/config" "$config"
  out=$(FM_HOME="$home" FM_CONFIG_OVERRIDE="$config" "$RENDER" --read-only 1 --afk 1 --relay 1)
  assert_contains "$out" "- Lock: read-only" "read-only stanza missing"
  assert_contains "$out" "- Away mode: active" "afk stanza missing"
  assert_contains "$out" "- Relay: active" "relay stanza missing"
  assert_contains "$out" "$config/relay.env" "relay stanza did not render the effective config path"
  assert_contains "$out" 'Mode: Pi extension background wake.' "Pi snippet missing"
  assert_not_contains "$out" "Source \`config/relay.env\`" "snippet kept the repo-relative relay config path"
  pass "renderer includes read-only, afk, and effective relay current-state stanzas"
}

test_repair_lines() {
  local home out
  home="$TMP_ROOT/repair-home"
  mkdir -p "$home/state" "$home/config"
  : > "$home/config/relay.env"
  out=$(FM_HOME="$home" "$RENDER" --relay 1 --repair-line)
  assert_contains "$out" "source '$home/config/relay.env' first" "relay repair line did not source the effective cadence config"
  assert_contains "$out" "fm_watch_arm_pi" "relay Pi repair line lost the extension-owned repair tool"

  out=$(FM_HOME="$home" "$RENDER" --read-only 1 --repair-line)
  assert_contains "$out" "session holding the fleet lock" "read-only repair line missing"

  out=$(FM_HOME="$home" "$RENDER" --repair-line)
  assert_contains "$out" "Pi tool fm_watch_arm_pi" "pi repair line does not direct the model to the extension-owned tool"
  assert_not_contains "$out" "extension command /fm-watch-arm-pi" "pi repair line still directs the model to the human slash command"
  pass "renderer repair-line mode uses Pi and honors conditional state"
}

test_pi_ordinary_continuation_and_repair() {
  local ordinary out

  out=$("$RENDER")
  ordinary=$(printf '%s\n' "$out" | grep -F -- '- Ordinary wake:')
  assert_contains "$ordinary" "Pi extension already owns watcher continuity" "pi ordinary-wake line does not leave continuity to the extension"
  assert_not_contains "$ordinary" "fm_watch_arm_pi" "pi ordinary-wake line incorrectly calls the recovery tool"
  out=$("$RENDER" --repair-line)
  assert_contains "$out" "fm_watch_arm_pi" "pi recovery line lost the extension-owned repair tool"

  pass "renderer preserves Pi ordinary-continuation and missing-cycle repair paths"
}

test_pi_snippet_uses_effective_extension_path() {
  local home out turnend watch
  home="$TMP_ROOT/pi-home"
  turnend="$ROOT/.pi/extensions/fm-primary-turnend-guard.ts"
  watch="$ROOT/.pi/extensions/fm-primary-pi-watch.ts"
  mkdir -p "$home/state" "$home/config"
  out=$(FM_HOME="$home" "$RENDER")
  assert_contains "$out" "-e $turnend -e $watch" "pi snippet did not render both effective extension launch paths"
  assert_contains "$out" "The turn-end guard extension lives at \`$turnend\`" "pi snippet did not render the turn-end guard extension path"
  assert_contains "$out" "The watcher extension lives at \`$watch\`" "pi snippet did not render the watcher extension path"
  assert_not_contains "$out" "__FM_PI_EXT__" "renderer leaked the Pi extension path placeholder"
  assert_not_contains "$out" "__FM_PI_TURNEND_EXT__" "renderer leaked the Pi turn-end extension path placeholder"
  assert_not_contains "$out" "state/fm-primary-pi-watch.ts" "pi snippet kept the old generated state-relative extension path"
  pass "pi supervision snippet renders the effective extension path"
}

test_pi_block
test_retired_harness_selector_is_rejected
test_conditional_stanzas
test_repair_lines
test_pi_ordinary_continuation_and_repair
test_pi_snippet_uses_effective_extension_path
