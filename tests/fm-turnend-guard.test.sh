#!/usr/bin/env bash
# Pi primary turn-end guard executable-interface tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-supervision-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-turnend-pi)
fm_git_identity fmtest fmtest@example.invalid

expect_code() {
  local expected=$1 actual=$2 message=$3
  [ "$actual" -eq "$expected" ] || fail "$message: got $actual, expected $expected"
}

make_primary() {
  local dir=$1
  mkdir -p "$dir/bin" "$dir/docs/supervision-protocols" "$dir/state" "$dir/config"
  git init -q "$dir"
  git -C "$dir" commit -q --allow-empty -m initial
  : > "$dir/AGENTS.md"
  cp "$ROOT/bin/fm-turnend-guard.sh" "$ROOT/bin/fm-supervision-lib.sh" \
    "$ROOT/bin/fm-primary-scope-lib.sh" "$ROOT/bin/fm-wake-lib.sh" \
    "$ROOT/bin/fm-supervision-instructions.sh" "$dir/bin/"
  cp "$ROOT/docs/supervision-protocols/pi.md" "$dir/docs/supervision-protocols/pi.md"
  chmod +x "$dir/bin/"*.sh
}

run_guard() {
  local dir=$1
  FM_HOME="$dir" FM_ROOT_OVERRIDE="$dir" FM_STATE_OVERRIDE="$dir/state" \
    FM_CONFIG_OVERRIDE="$dir/config" "$dir/bin/fm-turnend-guard.sh" 2>&1
}

test_semantic_predicate_requires_live_watcher() {
  local state="$TMP_ROOT/predicate/state"
  mkdir -p "$state"
  : > "$state/worker.meta"
  fm_supervision_unhealthy "$state" 300 || fail "missing watcher did not make Pi supervision unhealthy"
  touch "$state/.last-watcher-beat"
  verdict=$(FM_HOME="$TMP_ROOT/predicate-home" FM_STATE_OVERRIDE="$state" FM_ROOT_OVERRIDE="$ROOT" bash -c \
    '. "$1"; fm_watcher_supervision_verdict "$2" "$3" 300 "$4"; printf "%s:%s" "$FM_WATCHER_VERDICT_OK" "$FM_WATCHER_VERDICT_REASON"' \
    _ "$ROOT/bin/fm-wake-lib.sh" "$state" "$ROOT/bin/fm-watch.sh" "$TMP_ROOT/predicate-home")
  [ "$verdict" = false:no-watcher ] || fail "a fresh beacon without a live watcher was accepted: $verdict"
  pass "Pi supervision requires a live watcher rather than only a fresh beacon"
}

test_turnend_blocks_when_pi_supervision_is_missing() {
  local dir="$TMP_ROOT/missing" out rc=0
  make_primary "$dir"
  : > "$dir/state/worker.meta"
  out=$(run_guard "$dir") || rc=$?
  expect_code 2 "$rc" "Pi guard should block a blind turn"
  printf '%s' "$out" | grep -Fq 'PI SUPERVISION IS OFF' || fail "Pi guard did not name the missing supervision"
  printf '%s' "$out" | grep -Fq 'fm_watch_arm_pi' || fail "Pi guard did not give Pi repair guidance"
  pass "Pi turn-end guard blocks only a required blind turn"
}

test_turnend_allows_when_no_supervision_is_needed() {
  local dir="$TMP_ROOT/idle" out rc=0
  make_primary "$dir"
  out=$(run_guard "$dir") || rc=$?
  expect_code 0 "$rc" "Pi guard should allow an idle home"
  [ -z "$out" ] || fail "idle Pi guard emitted unexpected output: $out"
  pass "Pi turn-end guard allows an idle home"
}

test_runtime_choice_is_not_accepted_by_renderer() {
  local out rc=0
  out=$("$ROOT/bin/fm-supervision-instructions.sh" --unsupported-runtime 2>&1) || rc=$?
  expect_code 2 "$rc" "renderer accepted an unsupported runtime option"
  printf '%s' "$out" | grep -Fq 'unknown argument' || fail "renderer did not reject the unsupported option"
  pass "Pi supervision renderer exposes no runtime-choice option"
}

test_semantic_predicate_requires_live_watcher
test_turnend_blocks_when_pi_supervision_is_missing
test_turnend_allows_when_no_supervision_is_needed
test_runtime_choice_is_not_accepted_by_renderer
