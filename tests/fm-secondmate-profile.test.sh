#!/usr/bin/env bash
# Pi secondmate profile, inheritance, and retired-runtime recovery tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-config-inherit-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-secondmate-pi)

run_harness() {
  local config=$1
  shift
  PI_CODING_AGENT=true FM_CONFIG_OVERRIDE="$config" "$ROOT/bin/fm-harness.sh" "$@"
}

expect_fail() {
  local want=$1
  shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "expected command to fail: $*"
  printf '%s' "$out" | grep -Fq "$want" || fail "failure did not contain '$want': $out"
}

test_secondmate_profile_precedence() {
  local config="$TMP_ROOT/profiles/config" record
  mkdir -p "$config/secondmate-profiles"
  printf 'openai-codex/gpt-5.6-luna medium\n' > "$config/crew-profile"
  printf 'xai/grok-4.1 high\n' > "$config/secondmate-profile"
  printf 'openai-codex/gpt-5.6-luna xhigh\n' > "$config/secondmate-profiles/release"
  record=$(run_harness "$config" secondmate-profile release)
  [ "$record" = $'openai-codex/gpt-5.6-luna\txhigh\tconfig/secondmate-profiles/release' ] || fail "per-id profile did not win: $record"
  record=$(run_harness "$config" secondmate-profile support)
  [ "$record" = $'xai/grok-4.1\thigh\tconfig/secondmate-profile' ] || fail "global profile did not win: $record"
  [ "$(run_harness "$config" secondmate release)" = pi ] || fail "secondmate runtime was not fixed to Pi"
  pass "secondmate profiles select Pi model and thinking without a runtime axis"
}

test_only_ordinary_worker_profile_is_inherited() {
  local source="$TMP_ROOT/inherit/source" destination="$TMP_ROOT/inherit/destination"
  mkdir -p "$source" "$destination"
  printf 'openai-codex/gpt-5.6-luna high\n' > "$source/crew-profile"
  printf 'xai/grok-4.1 medium\n' > "$source/secondmate-profile"
  FM_INHERITABLE_CONFIG='crew-profile' propagate_inheritable_config "$source" "$destination" || fail "Pi profile inheritance failed"
  cmp "$source/crew-profile" "$destination/crew-profile" >/dev/null || fail "ordinary-worker Pi profile was not copied"
  [ ! -e "$destination/secondmate-profile" ] || fail "primary-only secondmate profile was inherited"
  pass "secondmate homes inherit ordinary Pi profiles but not primary-only secondmate pins"
}

write_remote_meta() {
  local path=$1 id=$2 runtime=$3
  cat > "$path" <<EOF
backend=herdr
window=fm-remote:pane1
endpoint_task_id=$id
worktree=/tmp/worktree
project=/tmp/project
harness=$runtime
herdr_session=fm-remote
herdr_workspace_id=workspace1
herdr_tab_id=tab1
herdr_pane_id=pane1
kind=secondmate
EOF
}

test_remote_recovery_refuses_retired_runtime_record() {
  local home="$TMP_ROOT/remote/home" id=remote-worker
  mkdir -p "$home/state/parent-route" "$home/data/.parent-route" "$home/config" "$home/bin"
  printf '%s\n' "$id" > "$home/.fm-secondmate-home"
  : > "$home/AGENTS.md"
  write_remote_meta "$home/state/parent-route/$id.meta" "$id" retired-runtime
  expect_fail 'not a Pi runtime' env FM_HOME="$home" "$ROOT/bin/fm-remote-secondmate-control.sh" route "$id"
  pass "remote secondmate recovery refuses a recorded retired runtime"
}

test_secondmate_profile_precedence
test_only_ordinary_worker_profile_is_inherited
test_remote_recovery_refuses_retired_runtime_record
