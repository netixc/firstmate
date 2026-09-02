#!/usr/bin/env bash
# Herdr-only secondmate liveness classifier regressions.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

test_herdr_agent_state_preserves_husk_classifier() {
  local pane_state expected out

  for row in 'dead missing' 'no-agent dead' 'live alive' 'ambiguous ambiguous' 'unknown unreadable'; do
    pane_state=${row%% *}
    expected=${row#* }
    out=$(FM_TEST_PANE_STATE="$pane_state" bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_pane_agent_state() { printf "%s" "$FM_TEST_PANE_STATE"; }; fm_backend_herdr_agent_state "sess:p1"' "$ROOT")
    [ "$out" = "$expected" ] || fail "Herdr pane state $pane_state should map to $expected, got '$out'"
  done

  out=$(bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_agent_state "no-colon-target"' "$ROOT")
  [ "$out" = unreadable ] || fail "an unparseable Herdr target should classify as unreadable, got '$out'"

  out=$(bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_pane_agent_state() { printf "no-agent"; }; fm_backend_herdr_agent_alive "sess:p1"' "$ROOT")
  [ "$out" = dead ] || fail "the Herdr compatibility view should keep a no-agent husk dead, got '$out'"

  pass "fm_backend_herdr_agent_state preserves recovery-grade liveness states"
}

test_registered_status_shell_contradiction_matrix() {
  local status out
  for status in working idle 'done' blocked; do
    out=$(FM_TEST_AGENT_STATUS="$status" FM_TEST_IDLE_SHELL=yes bash -c '
      . "$0/bin/backends/herdr.sh"
      fm_backend_herdr_pane_presence_state() { printf present; }
      fm_backend_herdr_cli() { printf "{\"result\":{\"agent\":{\"agent\":\"pi\",\"agent_status\":\"%s\"}}}\n" "$FM_TEST_AGENT_STATUS"; }
      fm_backend_herdr_pane_idle_shell_pid() { [ "$FM_TEST_IDLE_SHELL" = yes ] && printf "4242\n"; }
      printf "%s/%s" "$(fm_backend_herdr_pane_agent_state sess w1:p1)" "$(fm_backend_herdr_agent_state sess:w1:p1)"
    ' "$ROOT")
    [ "$out" = ambiguous/ambiguous ] \
      || fail "registered $status on a proven lone shell should be ambiguous, got '$out'"
  done

  for evidence in valid-pi malformed-process-info unreadable-process-info; do
    out=$(FM_TEST_AGENT_STATUS=idle FM_TEST_IDLE_SHELL=no bash -c '
      . "$0/bin/backends/herdr.sh"
      fm_backend_herdr_pane_presence_state() { printf present; }
      fm_backend_herdr_cli() { printf "{\"result\":{\"agent\":{\"agent\":\"pi\",\"agent_status\":\"%s\"}}}\n" "$FM_TEST_AGENT_STATUS"; }
      fm_backend_herdr_pane_idle_shell_pid() { return 1; }
      printf "%s/%s" "$(fm_backend_herdr_pane_agent_state sess w1:p1)" "$(fm_backend_herdr_agent_state sess:w1:p1)"
    ' "$ROOT")
    [ "$out" = live/alive ] \
      || fail "$evidence without positive lone-shell proof must preserve registry liveness, got '$out'"
  done

  out=$(bash -c '
    . "$0/bin/backends/herdr.sh"
    fm_backend_herdr_pane_presence_state() { printf dead; }
    printf "%s/%s" "$(fm_backend_herdr_pane_agent_state sess w1:p1)" "$(fm_backend_herdr_agent_state sess:w1:p1)"
  ' "$ROOT")
  [ "$out" = dead/missing ] || fail "pane disappearance should preserve dead/missing semantics, got '$out'"

  out=$(bash -c '
    . "$0/bin/backends/herdr.sh"
    FM_TEST_STEP=0
    fm_backend_herdr_pane_agent_state() {
      FM_TEST_STEP=$((FM_TEST_STEP + 1))
      [ "$FM_TEST_STEP" -eq 1 ] && printf ambiguous || printf no-agent
    }
    printf "%s\n" "$(fm_backend_herdr_agent_state sess:w1:p1)"
    FM_TEST_STEP=1
    printf "%s\n" "$(fm_backend_herdr_agent_state sess:w1:p1)"
  ' "$ROOT")
  [ "$out" = $'ambiguous\ndead' ] \
    || fail "a slow registry cleanup should preserve ambiguity before converging to dead, got '$out'"

  pass "registered Herdr status matrix preserves lone-shell contradictions without inferring from failed process evidence"
}

test_herdr_dispatcher_preserves_liveness_states() {
  local out
  out=$(bash -c '. "$0/bin/fm-backend.sh"; fm_backend_source herdr; fm_backend_herdr_pane_agent_state() { printf "live"; }; fm_backend_agent_state herdr sess:p1' "$ROOT")
  [ "$out" = alive ] || fail "Herdr dispatcher should report a live agent, got '$out'"

  out=$(bash -c '. "$0/bin/fm-backend.sh"; fm_backend_source herdr; fm_backend_herdr_pane_agent_state() { printf "no-agent"; }; fm_backend_agent_alive herdr sess:p1' "$ROOT")
  [ "$out" = dead ] || fail "Herdr compatibility dispatcher should report a husk dead, got '$out'"

  pass "Herdr-only dispatch preserves detailed and compatibility liveness views"
}

test_herdr_agent_state_preserves_husk_classifier
test_registered_status_shell_contradiction_matrix
test_herdr_dispatcher_preserves_liveness_states

printf '# all fm-secondmate-liveness tests passed\n'
