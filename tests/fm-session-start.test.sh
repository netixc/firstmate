#!/usr/bin/env bash
# Pi-only session-start behavior tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SESSION_START="$ROOT/bin/fm-session-start.sh"
TMP_ROOT=$(fm_test_tmproot fm-session-start-pi)
FAKEBIN="$TMP_ROOT/fakebin"
mkdir -p "$FAKEBIN"
PI_HOLDER_PID=$$

cat > "$FAKEBIN/ps" <<SH
#!/usr/bin/env bash
set -u
pid=
previous=
for argument in "\$@"; do
  [ "\$previous" = -p ] && pid=\$argument
  previous=\$argument
done
case "\$*" in
  *"comm="*)
    if [ "\$pid" = "$PI_HOLDER_PID" ]; then printf '%s\n' /usr/local/bin/pi
    else printf '%s\n' /bin/bash; fi
    ;;
  *"args="*)
    if [ "\$pid" = "$PI_HOLDER_PID" ]; then printf '%s\n' pi
    else printf '%s\n' bash; fi
    ;;
  *"ppid="*) printf '%s\n' "$PI_HOLDER_PID" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$FAKEBIN/ps"

make_home() {
  local home=$1
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects"
}

run_session_start() {
  local home=$1
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_BOOTSTRAP_DETECT_ONLY=1 \
    PI_CODING_AGENT=true PATH="$FAKEBIN:$PATH" "$SESSION_START" 2>&1
}

test_pi_session_start_block() {
  local home="$TMP_ROOT/normal" out
  make_home "$home"
  out=$(run_session_start "$home")
  assert_contains "$out" 'lock acquired: Pi pid' "session start did not acquire a Pi session lock"
  assert_contains "$out" 'SUPERVISION OPERATING INSTRUCTIONS - primary runtime: pi' "session start did not emit Pi supervision"
  assert_contains "$out" 'Pi extension owns watcher continuity' "session start did not emit Pi continuity guidance"
  assert_not_contains "$out" 'primary runtime: unknown' "session start emitted a fallback runtime"
  pass "session start emits the Pi-only operating block"
}

test_obsolete_runtime_config_is_actionable() {
  local home="$TMP_ROOT/obsolete" out
  make_home "$home"
  printf 'retired-runtime\n' > "$home/config/crew-harness"
  out=$(run_session_start "$home")
  assert_contains "$out" 'PI_RUNTIME_MIGRATION:' "session start did not surface obsolete runtime configuration"
  assert_contains "$out" 'no local configuration was changed' "migration diagnostic did not preserve private configuration"
  pass "session start reports an explicit safe runtime-configuration migration"
}

test_invalid_pi_profile_is_actionable() {
  local home="$TMP_ROOT/invalid" out
  make_home "$home"
  printf 'default high\n' > "$home/config/crew-profile"
  out=$(run_session_start "$home")
  assert_contains "$out" 'PI_RUNTIME_MIGRATION: invalid Pi profile configuration' "session start did not surface malformed Pi profile"
  pass "session start surfaces invalid Pi profile configuration"
}

test_pi_session_start_block
test_obsolete_runtime_config_is_actionable
test_invalid_pi_profile_is_actionable
