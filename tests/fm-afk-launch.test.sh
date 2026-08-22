#!/usr/bin/env bash
# Away-mode Herdr terminal record, cleanup, and lock safety.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-afk-launch)
HOME_DIR=$TMP_ROOT/home
mkdir -p "$HOME_DIR/state"
export FM_HOME=$HOME_DIR FM_STATE_OVERRIDE=$HOME_DIR/state FM_ROOT_OVERRIDE=$ROOT
# shellcheck source=bin/fm-afk-launch.sh
. "$ROOT/bin/fm-afk-launch.sh"

reset_record() { rm -f "$FM_AFK_LAUNCH_RECORD"; }
TEST_GENERATION="$HOME_DIR/herdr.sock"$'\t''1:2'
TEST_CURRENT_GENERATION=$TEST_GENERATION

fm_herdr_with_session_generation() {
  local required=$2 callback=$4
  shift 4
  [ "$required" = "$TEST_CURRENT_GENERATION" ] || return 2
  "$callback" "$@"
}

test_record_round_trip() {
  reset_record
  fm_afk_launch_record_write herdr lab:w1:p1 ws1 "$TEST_GENERATION" || fail "Herdr record write failed"
  fm_afk_launch_record_read || fail "Herdr record read failed"
  [ "$FM_AFK_REC_KIND" = herdr ] && [ "$FM_AFK_REC_TARGET" = lab:w1:p1 ] \
    || fail "Herdr record identity changed"
  [ "$FM_AFK_REC_WORKSPACE" = ws1 ] && [ "$FM_AFK_REC_GENERATION" = "$TEST_GENERATION" ] \
    || fail "Herdr record lost its workspace or session generation"
  pass "away launcher round-trips exact Herdr terminal and session identity"
}

test_legacy_record_is_preserved() {
  local record before
  for record in $'tmux\tfm-afk-old\t' $'herdr\tlab:w1:p1\tws1'; do
    reset_record
    printf '%s\n' "$record" > "$FM_AFK_LAUNCH_RECORD"
    before=$(shasum -a 256 "$FM_AFK_LAUNCH_RECORD" | awk '{print $1}')
    fm_afk_launch_record_read >/dev/null 2>&1 && fail "legacy record should refuse"
    [ "$(shasum -a 256 "$FM_AFK_LAUNCH_RECORD" | awk '{print $1}')" = "$before" ] \
      || fail "legacy record refusal rewrote exact identity"
  done
  pass "retired away-terminal records stay intact for manual reconciliation"
}

test_confirmed_absence_retires_exact_record() {
  reset_record
  fm_afk_launch_record_write herdr lab:w1:p1 ws1 "$TEST_GENERATION" || fail "record write failed"
  fm_afk_launch_record_read || fail "record read failed"
  # shellcheck disable=SC2329
  fm_herdr_cli() { printf '%s\n' '{"error":{"code":"pane_not_found"}}'; return 1; }
  fm_afk_launch_close_recorded || fail "confirmed absence should retire record despite close error"
  [ ! -e "$FM_AFK_LAUNCH_RECORD" ] || fail "confirmed absence retained record"
  pass "generation-bound confirmed absence retires the exact terminal record"
}

test_unconfirmed_close_preserves_record() {
  reset_record
  fm_afk_launch_record_write herdr lab:w1:p1 ws1 "$TEST_GENERATION" || fail "record write failed"
  fm_afk_launch_record_read || fail "record read failed"
  # shellcheck disable=SC2329
  fm_herdr_cli() {
    printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p1","workspace_id":"other"}}}'
  }
  fm_afk_launch_close_recorded >/dev/null 2>&1 && fail "unconfirmed teardown should refuse"
  [ -f "$FM_AFK_LAUNCH_RECORD" ] || fail "unconfirmed teardown lost exact id"
  pass "unconfirmed Herdr close preserves exact reconciliation identity"
}

test_replacement_generation_preserves_record() {
  local calls=0
  reset_record
  fm_afk_launch_record_write herdr lab:w1:p1 ws1 "$TEST_GENERATION" || fail "record write failed"
  fm_afk_launch_record_read || fail "record read failed"
  TEST_CURRENT_GENERATION="$HOME_DIR/herdr.sock"$'\t''1:3'
  fm_herdr_cli() { calls=$((calls + 1)); }
  fm_afk_launch_close_recorded >/dev/null 2>&1 && fail "replacement generation should refuse cleanup"
  [ "$calls" -eq 0 ] || fail "replacement generation reached terminal transport"
  [ -f "$FM_AFK_LAUNCH_RECORD" ] || fail "replacement generation lost the reconciliation record"
  TEST_CURRENT_GENERATION=$TEST_GENERATION
  pass "away cleanup preserves records across Herdr session replacement"
}

test_launcher_lock_identity() {
  rm -rf "$FM_AFK_LAUNCH_LOCK"
  fm_afk_launch_lock_acquire || fail "launcher lock acquisition failed"
  fm_afk_launch_lock_owned || fail "launcher lock did not bind process identity"
  fm_afk_launch_lock_release || fail "launcher lock release failed"
  [ ! -e "$FM_AFK_LAUNCH_LOCK" ] || fail "launcher lock survived release"
  pass "away launcher lock binds and releases exact process identity"
}

test_record_round_trip
test_legacy_record_is_preserved
test_confirmed_absence_retires_exact_record
test_unconfirmed_close_preserves_record
test_replacement_generation_preserves_record
test_launcher_lock_identity
