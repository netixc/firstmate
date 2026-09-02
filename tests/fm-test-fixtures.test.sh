#!/usr/bin/env bash
# Behavior tests for tests/fixtures.sh fake-toolchain and spawn-world builders.
#
# These cases drive the builders as a test would: they write stubs into a
# fakebin and exec those stubs. Assertions are on the binaries' observable
# output, exit status, and files they create - never on fixtures.sh source
# text. Migrated spawn suites cover fm_test_run_spawn through the real
# fm-spawn.sh; this file pins the stubs those suites now share.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

TMP_ROOT=$(fm_test_tmproot fm-test-fixtures)

test_no_mistakes_version_constant() {
  local fakebin out
  fakebin=$(fm_fakebin "$TMP_ROOT/nm")
  fm_test_fake_no_mistakes "$fakebin"
  out=$("$fakebin/no-mistakes" --version)
  [ "$out" = "$FM_TEST_NO_MISTAKES_FAKE_VERSION" ] || \
    fail "fake no-mistakes --version should be the shared constant, got '$out'"
  out=$(FM_FAKE_NO_MISTAKES_VERSION="$FM_TEST_NO_MISTAKES_FAKE_VERSION_TS" \
    "$fakebin/no-mistakes" --version)
  [ "$out" = "$FM_TEST_NO_MISTAKES_FAKE_VERSION_TS" ] || \
    fail "timestamped banner override should round-trip, got '$out'"
  case "$out" in
    "$FM_TEST_NO_MISTAKES_FAKE_VERSION "*) ;;
    *) fail "timestamped banner '$out' is not the shared constant plus a suffix" ;;
  esac
  out=$(FM_FAKE_NO_MISTAKES_VERSION='no-mistakes version v9.9.9 (fake)' \
    "$fakebin/no-mistakes" --version)
  [ "$out" = 'no-mistakes version v9.9.9 (fake)' ] || \
    fail "FM_FAKE_NO_MISTAKES_VERSION should override the default banner, got '$out'"
  "$fakebin/no-mistakes" doctor
  expect_code 0 $? "fake no-mistakes non-version verbs should exit 0"
  pass "fake no-mistakes --version is the shared constant and overridable"
}

test_no_mistakes_init_doctor_markers() {
  local fakebin dir rc
  dir="$TMP_ROOT/nm-init"
  mkdir -p "$dir"
  fakebin=$(fm_fakebin "$dir")
  fm_test_fake_no_mistakes_init_doctor "$fakebin"
  ( cd "$dir" && "$fakebin/no-mistakes" init )
  assert_present "$dir/.no-mistakes-init" "init did not touch the marker"
  ( cd "$dir" && "$fakebin/no-mistakes" doctor )
  assert_present "$dir/.no-mistakes-doctor" "doctor did not touch the marker"
  rc=0
  ( cd "$dir" && "$fakebin/no-mistakes" axi ) || rc=$?
  expect_code 2 "$rc" "unknown no-mistakes verb should exit 2"
  pass "init/doctor no-mistakes stub touches markers and refuses other verbs"
}

test_fake_gh_and_gh_axi() {
  local fakebin out
  fakebin=$(fm_fakebin "$TMP_ROOT/gh")
  fm_test_fake_gh "$fakebin"
  fm_test_fake_gh_axi "$fakebin"
  "$fakebin/gh" auth status
  expect_code 0 $? "fake gh auth status should succeed"
  "$fakebin/gh" pr list
  expect_code 0 $? "fake gh other verbs should exit 0"
  out=$("$fakebin/gh-axi" --version)
  [ "$out" = "$FM_TEST_GH_AXI_VERSION" ] || \
    fail "fake gh-axi --version should be $FM_TEST_GH_AXI_VERSION, got '$out'"
  out=$(FM_FAKE_GH_AXI_VERSION=0.9.9 "$fakebin/gh-axi" --version)
  [ "$out" = 0.9.9 ] || fail "FM_FAKE_GH_AXI_VERSION should override, got '$out'"
  pass "fake gh authenticates and fake gh-axi reports the shared version"
}

test_spawn_herdr_and_fakebin() {
  local fakebin out log count
  fakebin=$(make_spawn_fakebin "$TMP_ROOT/spawn" gh-axi)
  log="$TMP_ROOT/spawn/launch.log"
  : > "$log"
  fm_test_assert_fake_herdr "$fakebin" || fail "spawn fixture did not bind its isolated Herdr binary"
  count="$TMP_ROOT/spawn/pane-count"
  out=$(FM_FAKE_PANE_COUNTFILE="$count" FM_FAKE_PANE_STALE_READS=1 \
    FM_FAKE_PANE_STALE=/tmp/stale FM_FAKE_PANE_PATH=/tmp/wt \
    "$fakebin/herdr" pane get w1:p2 | jq -r '.result.pane.foreground_cwd')
  [ "$out" = /tmp/stale ] || fail "first pane path should expose the configured stale value, got '$out'"
  out=$(FM_FAKE_PANE_COUNTFILE="$count" FM_FAKE_PANE_STALE_READS=1 \
    FM_FAKE_PANE_STALE=/tmp/stale FM_FAKE_PANE_PATH=/tmp/wt \
    "$fakebin/herdr" pane get w1:p2 | jq -r '.result.pane.foreground_cwd')
  [ "$out" = /tmp/wt ] || fail "spawn Herdr pane path should be FM_FAKE_PANE_PATH, got '$out'"
  out=$("$fakebin/herdr" session list | jq -r '.sessions[0].name')
  [ "$out" = default ] || fail "spawn Herdr session should be named default, got '$out'"
  FM_FAKE_HERDR_TASK_ID=isolated "$fakebin/herdr" tab create --workspace w1 --label fm-isolated >/dev/null
  out=$(FM_FAKE_HERDR_TASK_ID=isolated "$fakebin/herdr" tab list --workspace w1 | \
    jq -r '.result.tabs[] | select(.label == "fm-isolated") | .tab_id')
  [ "$out" = w1:t2 ] || fail "spawn fixture did not publish the exact task-bound Herdr tab"
  FM_FAKE_LAUNCH_LOG="$log" "$fakebin/herdr" pane run w1:p2 'pi --model test'
  assert_grep 'pi --model test' "$log" "pane run payload was not logged"
  [ -x "$fakebin/treehouse" ] || fail "spawn fakebin should include Treehouse"
  [ -x "$fakebin/gh-axi" ] || fail "extra exit-0 tools should land in the spawn fakebin"
  "$fakebin/treehouse" get
  expect_code 0 $? "fake Treehouse should exit 0"
  pass "spawn fakebin answers Herdr identity, logs launches, and installs extra tools"
}

test_send_stubs_and_ssh() {
  local fakebin log ssh_log out
  fakebin=$(make_stubs "$TMP_ROOT/send")
  log="$TMP_ROOT/send/send.log"
  ssh_log="$TMP_ROOT/send/ssh.log"
  : > "$log"
  fm_test_fake_ssh "$fakebin"
  FM_SEND_LOG="$log" "$fakebin/herdr" pane send-text w1:p2 'hello steer'
  assert_grep 'hello steer' "$log" "send stubs did not log literal text"
  out=$("$fakebin/herdr" pane read w1:p2 --format ansi)
  case "$out" in
    *'╭────╮'*) ;;
    *) fail "send Herdr pane read should render an empty composer, got '$out'" ;;
  esac
  printf 'ignored\n' | FM_SSH_LOG="$ssh_log" "$fakebin/fake-ssh" host -- cmd
  assert_grep 'host -- cmd' "$ssh_log" "fake ssh did not record argv"
  FM_FAKE_SSH_RC=7 "$fakebin/fake-ssh" x < /dev/null
  expect_code 7 $? "fake ssh should honor FM_FAKE_SSH_RC"
  pass "send stubs log typed text and fake ssh records argv with a controllable exit"
}

test_spawn_home_layout() {
  local home="$TMP_ROOT/home"
  fm_test_spawn_home "$home" claude
  fm_test_spawn_brief "$home" t1 'do the thing'
  assert_present "$home/data" "spawn home missing data/"
  assert_present "$home/state/.last-watcher-beat" "spawn home missing watcher beat"
  assert_grep claude "$home/config/crew-harness" "crew-harness was not pinned"
  assert_grep 'do the thing' "$home/data/t1/brief.md" "brief text was not written"
  pass "spawn-home layout writes harness pin, beat, and brief"
}

test_no_mistakes_version_constant
test_no_mistakes_init_doctor_markers
test_fake_gh_and_gh_axi
test_spawn_herdr_and_fakebin
test_send_stubs_and_ssh
test_spawn_home_layout
