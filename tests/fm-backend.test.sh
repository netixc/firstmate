#!/usr/bin/env bash
# tests/fm-backend.test.sh - Herdr-only session-provider contract tests.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh" operational

TMP_ROOT=$(fm_test_tmproot fm-backend-tests)
STATE="$TMP_ROOT/state"
mkdir -p "$STATE"

test_required_tools_are_herdr_only() {
  local tools
  tools=$(fm_backend_required_tools)
  [ "$tools" = "herdr jq treehouse" ] \
    || fail "required tools should be the Herdr endpoint stack, got '$tools'"
  pass "required session-provider tools are Herdr-only"
}

test_metadata_without_provider_resolves() {
  printf 'window=lab:pane-a\n' > "$STATE/alpha.meta"
  [ "$(fm_backend_target_of_meta "$STATE/alpha.meta")" = "lab:pane-a" ] \
    || fail "provider-free task metadata did not resolve its Herdr pane"
  [ "$(fm_backend_resolve_selector alpha "$STATE")" = "lab:pane-a" ] \
    || fail "task id did not resolve through provider-free metadata"
  [ "$(fm_backend_resolve_selector fm-alpha "$STATE")" = "lab:pane-a" ] \
    || fail "fm- task label did not resolve through provider-free metadata"
  pass "provider-free task metadata resolves Herdr panes"
}

test_legacy_herdr_metadata_is_accepted() {
  printf 'backend=herdr\nwindow=lab:pane-b\n' > "$STATE/bravo.meta"
  [ "$(fm_backend_target_of_meta "$STATE/bravo.meta")" = "lab:pane-b" ] \
    || fail "legacy Herdr metadata should remain upgrade-compatible"
  pass "legacy Herdr metadata remains upgrade-compatible"
}

test_removed_provider_metadata_fails_closed() {
  local out status
  printf 'backend=removed-provider\nwindow=foreign-target\n' > "$STATE/legacy.meta"
  out=$(fm_backend_target_of_meta "$STATE/legacy.meta" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "legacy alternative-provider metadata should fail closed"
  assert_contains "$out" "removed session provider" "failure should explain the migration condition"
  [ -z "$(fm_backend_meta_for_window foreign-target "$STATE" 2>/dev/null || true)" ] \
    || fail "foreign endpoint metadata should never participate in Herdr lookup"
  pass "legacy alternative-provider metadata fails closed with migration guidance"
}

test_explicit_target_is_preserved() {
  [ "$(fm_backend_resolve_selector named-session:pane-z "$STATE")" = "named-session:pane-z" ] \
    || fail "explicit Herdr target should pass through unchanged"
  pass "explicit Herdr targets pass through unchanged"
}

test_missing_task_metadata_fails_closed() {
  local out status
  out=$(fm_backend_resolve_selector fm-missing "$STATE" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "missing task metadata should fail closed"
  assert_contains "$out" "no metadata" "missing-task error should identify the absent metadata"
  pass "missing task metadata fails closed"
}

test_bare_selector_uses_herdr_resolution() {
  fm_backend_herdr_resolve_bare_selector() {
    [ "$1" = "live" ] || return 1
    printf '%s' 'named-session:pane-live'
  }
  [ "$(fm_backend_resolve_selector live "$STATE")" = "named-session:pane-live" ] \
    || fail "bare task label should resolve through Herdr discovery"
  pass "bare selectors use Herdr discovery"
}

test_wrappers_call_herdr_implementation_directly() {
  local log="$TMP_ROOT/wrappers.log"
  : > "$log"
  fm_backend_herdr_capture() { printf 'capture:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_send_key() { printf 'key:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_send_text_submit() { printf 'submit:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_kill() { printf 'kill:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_busy_state() { printf 'busy:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_composer_state() { printf 'composer:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_agent_alive() { printf 'alive:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_events_capable() { printf 'events:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_wait_transition() { printf 'wait:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_commit_transition() { printf 'commit:%s\n' "$*" >> "$log"; }
  fm_backend_herdr_clear_transition() { printf 'clear:%s\n' "$*" >> "$log"; }

  fm_backend_capture lab:pane 10 fm-alpha
  fm_backend_send_key lab:pane Enter fm-alpha
  fm_backend_send_text_submit lab:pane hello 2 0 1 fm-alpha
  fm_backend_kill lab:pane
  fm_backend_busy_state lab:pane
  fm_backend_composer_state lab:pane
  fm_backend_agent_alive lab:pane
  fm_backend_events_capable lab
  fm_backend_wait_transition lab 5 "$STATE" lab:pane
  fm_backend_commit_transition "$STATE" lab record
  fm_backend_clear_transition "$STATE" lab:pane

  assert_contains "$(cat "$log")" "capture:lab:pane 10 fm-alpha" "capture wrapper did not forward to Herdr"
  assert_contains "$(cat "$log")" "submit:lab:pane hello 2 0 1 fm-alpha" "submit wrapper did not forward to Herdr"
  assert_contains "$(cat "$log")" "wait:lab 5 $STATE lab:pane" "event wrapper did not forward to Herdr"
  assert_contains "$(cat "$log")" "clear:$STATE lab:pane" "clear wrapper did not forward to Herdr"
  pass "shared endpoint wrappers call the Herdr implementation directly"
}

test_operational_load_rejects_legacy_settings() {
  local home="$TMP_ROOT/legacy-settings" out status
  mkdir -p "$home/config" "$home/state"

  out=$(FM_HOME="$home" FM_BACKEND=tmux bash -c '. "$1" operational; printf reached' \
    _ "$ROOT/bin/fm-backend.sh" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "operational backend load accepted FM_BACKEND"
  [ "$out" = "error: FM_BACKEND is obsolete; unset it because Herdr is Firstmate's only session provider" ] \
    || fail "operational FM_BACKEND refusal was not immediate: $out"

  printf '%s\n' zellij > "$home/config/backend"
  out=$(FM_HOME="$home" bash -c '. "$1" operational; printf reached' \
    _ "$ROOT/bin/fm-backend.sh" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "operational backend load accepted config/backend"
  [ "$out" = "error: config/backend is obsolete; remove it because Herdr is Firstmate's only session provider" ] \
    || fail "operational config/backend refusal was not immediate: $out"

  out=$(FM_HOME="$home" FM_BACKEND=tmux "$ROOT/bin/fm-send.sh" missing hello 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "fm-send accepted FM_BACKEND"
  [ "$out" = "error: FM_BACKEND is obsolete; unset it because Herdr is Firstmate's only session provider" ] \
    || fail "fm-send did work before the shared refusal: $out"
  pass "operational backend loading rejects legacy provider settings"
}

test_required_tools_are_herdr_only
test_metadata_without_provider_resolves
test_legacy_herdr_metadata_is_accepted
test_removed_provider_metadata_fails_closed
test_explicit_target_is_preserved
test_missing_task_metadata_fails_closed
test_bare_selector_uses_herdr_resolution
test_wrappers_call_herdr_implementation_directly
test_operational_load_rejects_legacy_settings
