#!/usr/bin/env bash
# Away-mode Herdr terminal record, cleanup, and lock safety.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-afk-launch)
HOME_DIR=$TMP_ROOT/home
mkdir -p "$HOME_DIR/state"
export FM_HOME=$HOME_DIR FM_STATE_OVERRIDE=$HOME_DIR/state FM_ROOT_OVERRIDE=$ROOT
# shellcheck source=tests/remote-herdr-fixture.sh
. "$ROOT/tests/remote-herdr-fixture.sh"
# shellcheck source=bin/fm-afk-launch.sh
. "$ROOT/bin/fm-afk-launch.sh"

setup_public_case() {
  local name=$1 dir
  dir=$TMP_ROOT/$name
  mkdir -p "$dir/home/state" "$dir/fake"
  install_remote_herdr_fixture "$dir/fake" "$dir/herdr.json" "$dir/herdr.log" \
    "$dir/send-fail" "$dir/herdr.sock"
  jq '.workspaces=[{workspace_id:"ws1",label:"afk",cwd:"/tmp"}]
      | .tabs=[{tab_id:"ws1:t1",label:"afk",workspace_id:"ws1",pane_id:"ws1:p1",cwd:"/tmp"}]' \
    "$dir/herdr.json" > "$dir/herdr.next"
  mv "$dir/herdr.next" "$dir/herdr.json"
  printf '%s' "$dir"
}

write_current_record() {
  local dir=$1 identity socket
  socket=$(fm_herdr_canonical_socket_path "$dir/herdr.sock") || fail "socket path unavailable"
  identity=$(fm_herdr_socket_identity "$socket") || fail "socket identity unavailable"
  printf 'herdr\tlab:ws1:p1\tws1\t%s\t%s\n' "$socket" "$identity" \
    > "$dir/home/state/.afk-daemon-terminal"
}

run_public_reconcile() {
  local dir=$1
  shift
  FM_HOME="$dir/home" FM_STATE_OVERRIDE="$dir/home/state" FM_ROOT_OVERRIDE="$ROOT" \
    FM_FAKE_HERDR_REQUIRE_BOUND_READ=1 PATH="$dir/fake/bin:$PATH" \
    "$ROOT/bin/fm-afk-launch.sh" reconcile "$@"
}

test_public_generation_bound_cleanup() {
  local dir out
  dir=$(setup_public_case public-cleanup)
  write_current_record "$dir"
  out=$(run_public_reconcile "$dir" 2>&1) || fail "public reconcile refused the recorded generation: $out"
  [ ! -e "$dir/home/state/.afk-daemon-terminal" ] || fail "public reconcile retained the closed record"
  [ "$(jq '[.tabs[] | select(.pane_id == "ws1:p1")] | length' "$dir/herdr.json")" = 0 ] \
    || fail "public reconcile did not close the exact Herdr pane"
  pass "public away reconcile closes only its generation-bound Herdr terminal"
}

test_public_replacement_generation_preserves_record() {
  local dir
  dir=$(setup_public_case public-replacement)
  write_current_record "$dir"
  mv "$dir/herdr.sock" "$dir/herdr.prior.sock"
  : > "$dir/herdr.sock"
  run_public_reconcile "$dir" >/dev/null 2>&1 && fail "replacement generation should refuse cleanup"
  [ -f "$dir/home/state/.afk-daemon-terminal" ] || fail "replacement generation lost the reconciliation record"
  [ "$(jq '[.tabs[] | select(.pane_id == "ws1:p1")] | length' "$dir/herdr.json")" = 1 ] \
    || fail "replacement generation closed the recorded pane"
  pass "public away reconcile preserves records across Herdr replacement"
}

test_public_legacy_records_are_preserved() {
  local dir record before out
  dir=$(setup_public_case public-legacy)
  for record in $'tmux\tfm-afk-old\t' $'herdr\tlab:ws1:p1\tws1'; do
    printf '%s\n' "$record" > "$dir/home/state/.afk-daemon-terminal"
    before=$(shasum -a 256 "$dir/home/state/.afk-daemon-terminal" | awk '{print $1}')
    out=$(run_public_reconcile "$dir" 2>&1) && fail "legacy record should refuse public reconciliation"
    [ "$(shasum -a 256 "$dir/home/state/.afk-daemon-terminal" | awk '{print $1}')" = "$before" ] \
      || fail "legacy refusal rewrote exact identity"
    case "$record" in
      tmux*) assert_contains "$out" 'retired tmux support' "historical tmux record was not classified as retired" ;;
      herdr*) assert_contains "$out" 'lacks session-generation identity' "historical Herdr record lost its actionable refusal" ;;
    esac
  done
  pass "public away reconcile preserves retired records for manual reconciliation"
}

test_launcher_lock_identity() {
  rm -rf "$FM_AFK_LAUNCH_LOCK"
  fm_afk_launch_lock_acquire || fail "launcher lock acquisition failed"
  fm_afk_launch_lock_owned || fail "launcher lock did not bind process identity"
  fm_afk_launch_lock_release || fail "launcher lock release failed"
  [ ! -e "$FM_AFK_LAUNCH_LOCK" ] || fail "launcher lock survived release"
  pass "away launcher lock binds and releases exact process identity"
}

test_public_generation_bound_cleanup
test_public_replacement_generation_preserves_record
test_public_legacy_records_are_preserved
test_launcher_lock_identity
