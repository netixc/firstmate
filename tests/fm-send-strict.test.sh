#!/usr/bin/env bash
# fm-send strict Herdr target resolution.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SEND="$ROOT/bin/fm-send.sh"
TMP_ROOT=$(fm_test_tmproot fm-send-strict)

make_stubs() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"protocol":16},"server":{"running":true}}\n' ;;
  "pane get")
    [ "${3:-}" != "${FM_FAKE_HERDR_DEAD_PANE:-}" ] || exit 1
    printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "${3:-}"
    ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"working"}}}\n' ;;
  "pane read") printf '\xe2\x94\x82 \xe2\x94\x82\n' ;;
esac
exit 0
SH
  chmod +x "$fb/herdr"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fb/sleep"
  printf '%s\n' "$fb"
}

setup_home() {  # <name> -> echoes home dir
  local home="$TMP_ROOT/$1-$RANDOM"
  mkdir -p "$home/state"
  printf '%s\n' "$home"
}

test_exact_task_id_send_works() {
  local dir fb home err log rc got
  dir="$TMP_ROOT/exact"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home exact); err="$dir/send.err"; log="$dir/herdr.log"; : > "$log"
  fm_write_meta "$home/state/mpf-lane-m8.meta" "window=sess:pane-m8" "kind=ship"

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_HERDR_LOG="$log" FM_SEND_SETTLE=0 \
    "$SEND" mpf-lane-m8 "lost dispatch" >/dev/null 2>"$err"; rc=$?
  expect_code 0 "$rc" "exact task id send should succeed when metadata exists"
  got=$(cat "$log")
  assert_contains "$got" "pane send-text pane-m8 lost dispatch" "exact id should type literal text to the Herdr pane"
  assert_contains "$got" "pane send-keys pane-m8 enter" "exact id should submit with Enter"
  pass "fm-send strict: exact task ids resolve through home metadata"
}

test_unset_fm_home_fails() {
  local dir fb err log rc
  dir="$TMP_ROOT/nohome"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); err="$dir/send.err"; log="$dir/herdr.log"; : > "$log"
  env -u FM_HOME PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$dir" FM_HERDR_LOG="$log" FM_SEND_SETTLE=0 \
    "$SEND" sess:pane "hello" >/dev/null 2>"$err"; rc=$?
  [ "$rc" -ne 0 ] || fail "unset FM_HOME should fail"
  assert_contains "$(cat "$err")" "FM_HOME is not set" "unset FM_HOME diagnostic should be explicit"
  [ ! -s "$log" ] || fail "unset FM_HOME still attempted a Herdr call"
  pass "fm-send strict: unset FM_HOME fails before target resolution"
}

test_unresolvable_target_does_not_guess() {
  local dir fb home err log rc
  dir="$TMP_ROOT/unresolved"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home unresolved); err="$dir/send.err"; log="$dir/herdr.log"; : > "$log"
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_HERDR_LOG="$log" FM_SEND_SETTLE=0 \
    "$SEND" lost-target "hello" >/dev/null 2>"$err"; rc=$?
  [ "$rc" -ne 0 ] || fail "unresolvable target should fail"
  assert_contains "$(cat "$err")" "not resolvable" "unresolvable diagnostic should be loud"
  assert_contains "$(cat "$err")" "recorded window metadata" "unresolvable diagnostic should name the attempted lookup"
  [ ! -s "$log" ] || fail "unresolvable target attempted a Herdr send"
  pass "fm-send strict: unresolvable selectors never guess a pane"
}

test_prefixless_herdr_pane_id_fails() {
  local dir fb home err log rc
  dir="$TMP_ROOT/herdr-pane"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home herdr); err="$dir/send.err"; log="$dir/herdr.log"; : > "$log"
  fm_write_meta "$home/state/nudge.meta" \
    "window=default:wB:p2" "herdr_session=default" "herdr_pane_id=wB:p2" "kind=ship"
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_HERDR_LOG="$log" FM_SEND_SETTLE=0 \
    "$SEND" wB:p2 "nudge" >/dev/null 2>"$err"; rc=$?
  [ "$rc" -ne 0 ] || fail "prefixless Herdr pane id should fail"
  assert_contains "$(cat "$err")" "matches herdr_pane_id" "diagnostic should name the metadata match"
  assert_contains "$(cat "$err")" "default:wB:p2" "diagnostic should show the canonical target"
  [ ! -s "$log" ] || fail "prefixless pane id attempted a Herdr send"
  pass "fm-send strict: prefixless Herdr pane ids are rejected"
}

test_explicit_target_must_exist() {
  local dir fb home err log rc
  dir="$TMP_ROOT/dead-explicit"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home deadexplicit); err="$dir/send.err"; log="$dir/herdr.log"; : > "$log"
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_HERDR_LOG="$log" \
    FM_FAKE_HERDR_DEAD_PANE=missing FM_SEND_SETTLE=0 \
    "$SEND" sess:missing "hello" >/dev/null 2>"$err"; rc=$?
  [ "$rc" -ne 0 ] || fail "dead explicit Herdr target should fail"
  assert_contains "$(cat "$err")" "not a live Herdr endpoint" "dead explicit target diagnostic should name Herdr"
  assert_not_contains "$(cat "$log")" "pane send-text" "dead explicit target should not attempt a send"
  pass "fm-send strict: explicit Herdr targets must verify live"
}

test_fm_label_send_works() {
  local dir fb home err log rc got
  dir="$TMP_ROOT/healthy"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home healthy); err="$dir/send.err"; log="$dir/herdr.log"; : > "$log"
  fm_write_meta "$home/state/lane-ok.meta" "window=sess:pane-ok" "kind=ship" "harness=codex"
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_HERDR_LOG="$log" FM_SEND_SETTLE=0 \
    "$SEND" fm-lane-ok "hello captain" >/dev/null 2>"$err"; rc=$?
  expect_code 0 "$rc" "healthy fm-id send should succeed"
  got=$(cat "$log")
  assert_contains "$got" "pane send-text pane-ok hello captain" "healthy send should type once"
  assert_contains "$got" "pane send-keys pane-ok enter" "healthy send should submit"
  assert_contains "$(cat "$err")" "requested message WILL still be sent" "guard banner should keep send-specific continuation wording"
  pass "fm-send strict: healthy fm-<id> sends type once and submit"
}

test_exact_task_id_send_works
test_unset_fm_home_fails
test_unresolvable_target_does_not_guess
test_prefixless_herdr_pane_id_fails
test_explicit_target_must_exist
test_fm_label_send_works
