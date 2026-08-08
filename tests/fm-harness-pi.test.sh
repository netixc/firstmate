#!/usr/bin/env bash
# Pi-only runtime/profile executable-interface tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-harness-pi)

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

test_builtin_pi_profile() {
  local config="$TMP_ROOT/builtin/config" record
  mkdir -p "$config"
  [ "$(run_harness "$config" primary)" = pi ] || fail "Pi marker did not satisfy primary runtime detection"
  [ "$(run_harness "$config" crew)" = pi ] || fail "ordinary worker runtime was not Pi"
  [ "$(run_harness "$config" secondmate)" = pi ] || fail "secondmate runtime was not Pi"
  record=$(run_harness "$config" crew-profile)
  [ "$record" = $'\t\tbuilt-in' ] || fail "unexpected built-in Pi profile: $record"
  pass "Pi is the fixed primary, worker, and secondmate runtime"
}

test_pi_profiles_and_precedence() {
  local config="$TMP_ROOT/profiles/config" record
  mkdir -p "$config/secondmate-profiles"
  printf 'openai-codex/gpt-5.6-luna high\n' > "$config/crew-profile"
  printf 'xai/grok-4.1 medium\n' > "$config/secondmate-profile"
  printf 'openai-codex/gpt-5.6-luna xhigh\n' > "$config/secondmate-profiles/remote"
  record=$(run_harness "$config" crew-profile)
  [ "$record" = $'openai-codex/gpt-5.6-luna\thigh\tconfig/crew-profile' ] || fail "unexpected crew profile: $record"
  record=$(run_harness "$config" secondmate-profile remote)
  [ "$record" = $'openai-codex/gpt-5.6-luna\txhigh\tconfig/secondmate-profiles/remote' ] || fail "per-secondmate profile did not win: $record"
  record=$(run_harness "$config" secondmate-profile other)
  [ "$record" = $'xai/grok-4.1\tmedium\tconfig/secondmate-profile' ] || fail "global secondmate profile did not win: $record"
  [ "$(run_harness "$config" secondmate-model remote)" = openai-codex/gpt-5.6-luna ] || fail "wrong secondmate model"
  [ "$(run_harness "$config" secondmate-effort remote)" = xhigh ] || fail "wrong secondmate thinking"
  run_harness "$config" validate-config >/dev/null || fail "valid Pi profiles were rejected"
  pass "Pi model and thinking profiles resolve with per-secondmate precedence"
}

test_obsolete_selection_blocks_launch() {
  local config="$TMP_ROOT/obsolete/config" out rc=0
  mkdir -p "$config"
  printf 'legacy-runtime\n' > "$config/crew-harness"
  out=$("$ROOT/bin/fm-pi-runtime-migrate.sh" --config "$config" --check 2>&1) || rc=$?
  [ "$rc" -eq 1 ] || fail "obsolete runtime config did not require explicit migration"
  printf '%s' "$out" | grep -Fq 'PI_RUNTIME_MIGRATION:' || fail "migration output missing diagnostic"
  expect_fail 'obsolete runtime selection' run_harness "$config" crew
  pass "obsolete runtime selection blocks Pi launch pending explicit migration"
}

test_invalid_pi_profile_rejected() {
  local config="$TMP_ROOT/invalid/config"
  mkdir -p "$config"
  printf 'default high\n' > "$config/crew-profile"
  expect_fail 'model must be a concrete token' run_harness "$config" validate-config
  printf 'openai-codex/gpt-5.6-luna impossible\n' > "$config/crew-profile"
  expect_fail 'thinking must be low, medium, high, xhigh, or max' run_harness "$config" crew-profile
  pass "invalid Pi profile values are refused"
}

test_dispatch_validation() {
  local config="$TMP_ROOT/dispatch/config"
  mkdir -p "$config"
  printf '%s\n' '{"rules":[{"when":"test","use":{"model":"xai/grok-4.1","effort":"high"}}]}' > "$config/crew-dispatch.json"
  run_harness "$config" validate-dispatch || fail "valid Pi dispatch was rejected"
  printf '%s\n' '{"rules":[{"when":"test","use":{"harness":"codex","model":"xai/grok-4.1"}}]}' > "$config/crew-dispatch.json"
  expect_fail 'obsolete runtime field: harness' run_harness "$config" validate-dispatch
  pass "Pi dispatch validation is shared by launch and bootstrap"
}

test_builtin_pi_profile
test_pi_profiles_and_precedence
test_obsolete_selection_blocks_launch
test_invalid_pi_profile_rejected
test_dispatch_validation
