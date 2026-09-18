#!/usr/bin/env bash
# Pi posture lifecycle: away is the confirmed contract record, quiet is a small
# durable marker, and neither entry starts another process or session backend.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"
LAUNCH="$ROOT/bin/fm-afk-launch.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-afk-launch-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

new_home() {
  local name=$1 home
  home="$TMP_ROOT/$name"
  mkdir -p "$home/state"
  printf '%s\n' "$home"
}

run_launch() {  # <home> <args...>
  local home=$1
  shift
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$LAUNCH" "$@"
}

test_help_names_only_posture_commands() {
  local out
  out=$($LAUNCH --help) || fail "--help failed"
  assert_contains "$out" 'fm-afk-launch.sh propose' "help omitted propose"
  assert_contains "$out" 'fm-afk-launch.sh confirm' "help omitted confirm"
  assert_contains "$out" 'fm-afk-launch.sh quiet' "help omitted quiet"
  assert_contains "$out" 'fm-afk-launch.sh stop' "help omitted stop"
  pass "afk launcher exposes only Pi posture lifecycle commands"
}

test_quiet_records_marker_without_launch_state() {
  local home out
  home=$(new_home quiet)
  out=$(run_launch "$home" quiet 2>&1) || fail "quiet entry failed: $out"
  [ "$(sed -n '1p' "$home/state/.afk")" = quiet ] || fail "quiet entry did not record its mode"
  sed -n '2p' "$home/state/.afk" | grep -Eq '^[0-9]+$' || fail "quiet marker lacks its epoch"
  [ ! -e "$home/state/.afk-contract" ] || fail "quiet entry created an away contract"
  assert_contains "$out" 'Pi ordinary supervision remains active' "quiet entry did not state supervision ownership"
  pass "quiet posture records only its posture marker"
}

test_quiet_refresh_is_idempotent_and_stop_clears_it() {
  local home first second out
  home=$(new_home quiet-refresh)
  run_launch "$home" quiet >/dev/null 2>&1 || fail "first quiet entry failed"
  first=$(sed -n '2p' "$home/state/.afk")
  sleep 1
  run_launch "$home" quiet >/dev/null 2>&1 || fail "quiet refresh failed"
  second=$(sed -n '2p' "$home/state/.afk")
  [ "$second" -ge "$first" ] || fail "quiet refresh moved its epoch backwards"
  out=$(run_launch "$home" stop 2>&1) || fail "quiet stop failed: $out"
  [ ! -e "$home/state/.afk" ] || fail "quiet stop left the posture marker"
  assert_contains "$out" 'posture ended' "quiet stop omitted its outcome"
  pass "quiet posture refreshes and stops without another process"
}

test_quiet_refuses_malformed_existing_marker_without_overwrite() {
  local home before out rc
  home=$(new_home quiet-malformed)
  printf 'away\n123\n' > "$home/state/.afk"
  before=$(cat "$home/state/.afk")
  set +e
  out=$(run_launch "$home" quiet 2>&1)
  rc=$?
  set -e
  expect_code 1 "$rc" "quiet entry should refuse a non-quiet marker"
  assert_contains "$out" 'not a valid quiet posture marker' \
    "malformed marker refusal omitted its reason"
  [ "$(cat "$home/state/.afk")" = "$before" ] \
    || fail "quiet entry overwrote a non-quiet marker"

  home=$(new_home quiet-symlink)
  printf 'quiet\n123\n' > "$home/target"
  ln -s "$home/target" "$home/state/.afk"
  set +e
  out=$(run_launch "$home" quiet 2>&1)
  rc=$?
  set -e
  expect_code 1 "$rc" "quiet entry should refuse a symlink marker"
  [ -L "$home/state/.afk" ] || fail "quiet entry replaced a symlink marker"
  [ "$(readlink "$home/state/.afk")" = "$home/target" ] \
    || fail "quiet entry changed the symlink target"
  pass "quiet posture refuses malformed and symlink markers without overwriting"
}

test_away_confirm_uses_contract_and_clears_quiet() {
  local home out
  home=$(new_home away-confirm)
  run_launch "$home" quiet >/dev/null 2>&1 || fail "quiet setup failed"
  run_launch "$home" propose --words 'back later' >/dev/null 2>&1 || fail "away proposal failed"
  out=$(run_launch "$home" confirm 2>&1) || fail "away confirmation failed: $out"
  [ -f "$home/state/.afk-contract" ] || fail "away confirmation did not create the contract"
  [ ! -e "$home/state/.afk" ] || fail "away confirmation left quiet posture active"
  assert_contains "$out" 'Away posture confirmed at ' "away confirmation omitted the entry announcement"
  pass "away confirmation makes the contract the sole posture record"
}

test_quiet_refuses_during_away_posture() {
  local home out rc
  home=$(new_home quiet-during-away)
  run_launch "$home" propose >/dev/null 2>&1 || fail "away proposal failed"
  run_launch "$home" confirm >/dev/null 2>&1 || fail "away confirmation failed"
  set +e
  out=$(run_launch "$home" quiet 2>&1)
  rc=$?
  set -e
  expect_code 1 "$rc" "quiet entry should refuse during away posture"
  assert_contains "$out" 'away posture is already active' "quiet refusal omitted its reason"
  [ ! -e "$home/state/.afk" ] || fail "refused quiet entry wrote a marker"
  pass "quiet posture cannot overlap an active away posture"
}

test_stop_archives_away_contract() {
  local home entered out archive
  home=$(new_home away-stop)
  run_launch "$home" propose --words 'return soon' >/dev/null 2>&1 || fail "away proposal failed"
  run_launch "$home" confirm >/dev/null 2>&1 || fail "away confirmation failed"
  entered=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$ROOT/bin/fm-afk-contract.sh" field entered_epoch)
  out=$(run_launch "$home" stop 2>&1) || fail "away stop failed: $out"
  archive="$home/state/afk-contracts/$entered.afk-contract"
  [ ! -e "$home/state/.afk-contract" ] || fail "away stop left the live contract"
  [ -f "$archive" ] || fail "away stop did not archive the contract"
  assert_contains "$out" "$archive" "away stop omitted the archive path"
  pass "away stop archives exactly the confirmed posture record"
}

test_pending_return_catchup_blocks_entry() {
  local home out rc
  home=$(new_home pending-catchup)
  : > "$home/state/.afk-return-catchup"
  set +e
  out=$(run_launch "$home" quiet 2>&1)
  rc=$?
  set -e
  expect_code 1 "$rc" "quiet entry should refuse while return catch-up is pending"
  assert_contains "$out" 'return catch-up is still pending' "catch-up refusal omitted its reason"
  [ ! -e "$home/state/.afk" ] || fail "catch-up refusal wrote quiet posture"
  pass "pending return catch-up blocks new posture entry"
}

test_unknown_command_is_rejected_generically() {
  local home out rc
  home=$(new_home unknown-command)
  set +e
  out=$(run_launch "$home" unsupported-action 2>&1)
  rc=$?
  set -e
  expect_code 2 "$rc" "an unsupported action should be outside the posture interface"
  assert_contains "$out" 'Usage:' "unsupported action did not return generic usage"
  [ ! -e "$home/state/.afk" ] || fail "unsupported action wrote posture state"
  pass "unsupported posture actions receive only generic rejection"
}

test_help_names_only_posture_commands
test_quiet_records_marker_without_launch_state
test_quiet_refresh_is_idempotent_and_stop_clears_it
test_quiet_refuses_malformed_existing_marker_without_overwrite
test_away_confirm_uses_contract_and_clears_quiet
test_quiet_refuses_during_away_posture
test_stop_archives_away_contract
test_pending_return_catchup_blocks_entry
test_unknown_command_is_rejected_generically
