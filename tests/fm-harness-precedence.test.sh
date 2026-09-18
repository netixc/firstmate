#!/usr/bin/env bash
# Behavior tests for plain Pi runtime detection and protocol selection.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

unset PI_CODING_AGENT
HARNESS="$ROOT/bin/fm-harness.sh"
RENDER="$ROOT/bin/fm-supervision-instructions.sh"
TMP_ROOT=$(fm_test_tmproot fm-harness-precedence)
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}

fake_ps_bin() {  # <dir> <comm-for-pid-1>
  local fakebin comm=$2
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
pid=
prev=
for arg in "$@"; do
  [ "$prev" = -p ] && pid=$arg
  prev=$arg
done
if [ "$pid" = 1 ]; then
  comm=${FM_TEST_PID1_COMM:-init}
  ppid=0
else
  comm=bash
  ppid=1
fi
case "$*" in
  *'ppid='*) printf '%s\n' "$ppid" ;;
  *'args='*) printf '%s\n' "$comm" ;;
  *) printf '%s\n' "$comm" ;;
esac
SH
  chmod +x "$fakebin/ps"
  FM_TEST_PID1_COMM=$comm printf '%s\n' "$fakebin"
}

named_pi() {  # <dir>
  mkdir -p "$1"
  cp "$(command -v bash)" "$1/pi"
  printf '%s\n' "$1/pi"
}

test_marker_identifies_pi_without_ancestry() {
  local fakebin out
  fakebin=$(fake_ps_bin "$TMP_ROOT/blind" init)
  out=$(PI_CODING_AGENT=true PATH="$fakebin:$BASE_PATH" "$HARNESS")
  [ "$out" = pi ] || fail "Pi marker should identify plain Pi, got '$out'"
  out=$(env -u PI_CODING_AGENT PATH="$fakebin:$BASE_PATH" "$HARNESS")
  [ "$out" = unknown ] || fail "silent ancestry without the Pi marker should be unknown, got '$out'"
  pass "plain Pi marker is the only supported runtime marker"
}

test_pi_ancestry_identifies_pi() {
  local bin out
  bin=$(named_pi "$TMP_ROOT/pi-tree")
  out=$(env -u PI_CODING_AGENT "$bin" -c "r=\$(\"$HARNESS\"); printf '%s' \"\$r\"")
  [ "$out" = pi ] || fail "exact pi ancestry should identify Pi, got '$out'"
  pass "exact pi process ancestry identifies plain Pi"
}

test_pid_namespace_pi_is_examined() {
  local fakebin out
  fakebin=$(fake_ps_bin "$TMP_ROOT/namespace" pi)
  out=$(env -u PI_CODING_AGENT FM_TEST_PID1_COMM=pi PATH="$fakebin:$BASE_PATH" "$HARNESS")
  [ "$out" = pi ] || fail "Pi at pid 1 should identify Pi, got '$out'"
  pass "Pi detection examines pid 1 in a namespace"
}

test_unsupported_configured_harness_is_rejected_at_resolution() {
  local source cfg err rc
  for source in crew-harness secondmate-harness; do
    cfg="$TMP_ROOT/config-$source"
    mkdir -p "$cfg"
    printf 'unsupported-runtime\n' > "$cfg/$source"
    err="$cfg/error"
    rc=0
    PATH="$BASE_PATH" PI_CODING_AGENT=true FM_CONFIG_OVERRIDE="$cfg" \
      "$HARNESS" "${source%-harness}" >/dev/null 2>"$err" || rc=$?
    [ "$rc" -ne 0 ] || fail "$source should fail during harness resolution"
    assert_contains "$(cat "$err")" "only 'pi' is supported" \
      "$source rejection should state the Pi-only boundary"
  done
  pass "unsupported harness configuration is rejected by the shared resolver"
}

test_unknown_runtime_uses_unknown_protocol() {
  local out
  out=$("$RENDER" --harness unknown)
  assert_contains "$out" "primary harness: unknown" "unknown runtime should use neutral protocol"
  assert_not_contains "$out" "fm_watch_arm_pi" "unknown runtime should not receive Pi repair instructions"
  pass "unknown runtime receives only neutral supervision instructions"
}

test_pi_protocol_and_effort_validation() {
  local out
  out=$("$RENDER" --harness pi)
  assert_contains "$out" "primary harness: pi" "Pi should select the Pi protocol"
  assert_contains "$out" "fm_watch_arm_pi" "Pi protocol should name the Pi repair tool"

  "$HARNESS" validate-native-effort pi codex-native/gpt-5 ultra >/dev/null \
    || fail "Pi codex-native model should accept ultra effort"
  if "$HARNESS" validate-native-effort pi anthropic/claude ultra >/dev/null 2>&1; then
    fail "non-native Pi model should reject ultra effort"
  fi
  pass "Pi protocol and native effort validation remain intact"
}

test_marker_identifies_pi_without_ancestry
test_pi_ancestry_identifies_pi
test_pid_namespace_pi_is_examined
test_unsupported_configured_harness_is_rejected_at_resolution
test_unknown_runtime_uses_unknown_protocol
test_pi_protocol_and_effort_validation
