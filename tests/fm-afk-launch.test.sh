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

test_record_round_trip() {
  reset_record
  fm_afk_launch_record_write herdr lab:w1:p1 ws1 || fail "Herdr record write failed"
  fm_afk_launch_record_read || fail "Herdr record read failed"
  [ "$FM_AFK_REC_KIND" = herdr ] && [ "$FM_AFK_REC_TARGET" = lab:w1:p1 ] \
    || fail "Herdr record identity changed"
  pass "away launcher round-trips exact Herdr terminal identity"
}

test_legacy_record_is_preserved() {
  reset_record
  printf 'tmux\tfm-afk-old\t\n' > "$FM_AFK_LAUNCH_RECORD"
  before=$(shasum -a 256 "$FM_AFK_LAUNCH_RECORD" | awk '{print $1}')
  fm_afk_launch_record_read >/dev/null 2>&1 && fail "retired tmux record should refuse"
  [ "$(shasum -a 256 "$FM_AFK_LAUNCH_RECORD" | awk '{print $1}')" = "$before" ] \
    || fail "legacy record refusal rewrote exact identity"
  pass "retired away-terminal records stay intact for manual reconciliation"
}

test_native_record_has_no_terminal() {
  reset_record
  fm_afk_launch_record_write native - native || fail "native record write failed"
  fm_afk_launch_record_read || fail "native record read failed"
  fm_afk_launch_close_recorded || fail "native record cleanup failed"
  [ ! -e "$FM_AFK_LAUNCH_RECORD" ] || fail "native no-terminal record survived cleanup"
  pass "native tracked background mode records and cleans up no terminal"
}

test_confirmed_absence_retires_exact_record() {
  reset_record
  fm_afk_launch_record_write herdr lab:w1:p1 ws1 || fail "record write failed"
  fm_afk_launch_record_read || fail "record read failed"
  fm_afk_launch_close_terminal() { return 1; }
  fm_afk_launch_terminal_absent() { [ "$1" = lab:w1:p1 ]; }
  fm_afk_launch_close_recorded || fail "confirmed absence should retire record despite close error"
  [ ! -e "$FM_AFK_LAUNCH_RECORD" ] || fail "confirmed absence retained record"
  pass "exact confirmed absence is the only terminal-record retirement authority"
}

test_unconfirmed_close_preserves_record() {
  reset_record
  fm_afk_launch_record_write herdr lab:w1:p1 ws1 || fail "record write failed"
  fm_afk_launch_record_read || fail "record read failed"
  fm_afk_launch_close_terminal() { return 0; }
  fm_afk_launch_terminal_absent() { return 1; }
  fm_afk_launch_close_recorded >/dev/null 2>&1 && fail "unconfirmed teardown should refuse"
  [ -f "$FM_AFK_LAUNCH_RECORD" ] || fail "unconfirmed teardown lost exact id"
  pass "unconfirmed Herdr close preserves exact reconciliation identity"
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
test_native_record_has_no_terminal
test_confirmed_absence_retires_exact_record
test_unconfirmed_close_preserves_record
test_launcher_lock_identity
