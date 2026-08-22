#!/usr/bin/env bash
# Away-mode daemon classification, durable buffering, and Herdr injection guards.
set -u

# shellcheck source=tests/wake-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/wake-helpers.sh"
# shellcheck source=bin/fm-supervise-daemon.sh
. "$ROOT/bin/fm-supervise-daemon.sh"

TMP_ROOT=$(fm_test_tmproot fm-daemon)

new_state() { local d=$TMP_ROOT/$1; mkdir -p "$d/state"; printf '%s\n' "$d/state"; }

test_signal_classification() {
  local state out kw
  state=$(new_state classify)
  printf 'working: implementation under way\n' > "$state/a.status"
  out=$(classify_signal "$state/a.status" "$state")
  case "$out" in self\|*) ;; *) fail "routine status should self-handle: $out" ;; esac
  for kw in 'done: report complete' 'needs-decision: choose A' 'blocked: credential needed' 'failed: check failed'; do
    printf '%s\n' "$kw" > "$state/a.status"
    out=$(classify_signal "$state/a.status" "$state")
    case "$out" in escalate\|*) ;; *) fail "captain-relevant status did not escalate: $kw" ;; esac
  done
  case "$(classify_check 'check: merged')" in escalate\|*) ;; *) fail "check should escalate" ;; esac
  case "$(classify_heartbeat)" in self\|*) ;; *) fail "heartbeat should self-handle" ;; esac
  case "$(classify_unknown strange)" in escalate\|*) ;; *) fail "unknown should fail safe" ;; esac
  pass "daemon classification separates routine and captain-relevant work"
}

test_pause_classification_and_tracking() {
  local state out key
  state=$(new_state pause)
  fm_write_meta "$state/held.meta" \
    "backend=herdr" "window=lab:w-held:p1" "endpoint_task_id=held" \
    "herdr_session=lab" "herdr_workspace_id=w-held" "herdr_tab_id=w-held:t-held" \
    "herdr_pane_id=w-held:p1" "worktree=/tmp/held" "project=/tmp/project" "harness=pi"
  printf 'paused: waiting for an external release\n' > "$state/held.status"
  out=$(classify_stale 'lab:w-held:p1' "$state")
  case "$out" in pause\|*) ;; *) fail "declared pause should use its long-cadence class: $out" ;; esac
  reconcile_pause_tracking 'lab:w-held:p1' "$state" 'paused: waiting externally'
  key=$(_stale_key held)
  [ -f "$state/.subsuper-paused-$key" ] || fail "pause marker was not recorded"
  pass "declared external waits retain separate durable tracking"
}

test_unmatched_stale_escalates_without_shared_markers() {
  local state out
  state=$(new_state unmatched-stale)
  out=$(classify_stale 'sess:fm-victim' "$state")
  case "$out" in
    escalate\|*unsupported*preserved*) ;;
    *) fail "unmatched stale endpoint did not escalate as preserved evidence: $out" ;;
  esac
  FM_ESCALATE_BATCH_SECS=90 handle_wake 'stale: sess:fm-victim' "$state"
  assert_contains "$(cat "$state/.subsuper-escalations")" 'unsupported stale endpoint preserved' \
    "unmatched stale wake was acknowledged without durable escalation"
  [ ! -e "$state/.subsuper-stale-" ] || fail "unmatched stale wake created the shared empty-identity marker"
  pass "unmatched stale endpoints escalate durably without shared identity markers"
}

test_escalation_buffer_is_durable() {
  local state
  state=$(new_state buffer)
  escalate_add "$state" 'decision A'
  escalate_add "$state" 'failure B'
  [ "$(wc -l < "$state/.subsuper-escalations" | tr -d ' ')" = 2 ] \
    || fail "escalation buffer lost a row"
  [ -s "$state/.subsuper-escalations.since" ] || fail "escalation age sidecar missing"
  pass "daemon escalation buffering is durable and age-tracked"
}

test_injection_presence_and_target_guards() {
  local state calls=0
  state=$(new_state inject-guards)
  FM_SUPERVISOR_TARGET=lab:w-primary:p1
  fm_herdr_target_exists() { return 0; }
  pane_is_busy() { return 1; }
  fm_herdr_composer_state() { printf empty; }
  fm_herdr_send_text_submit() { calls=$((calls + 1)); printf empty; }
  inject_msg hello "$state" && fail "injection should refuse while away mode is off"
  touch "$state/.afk"
  fm_herdr_target_exists() { return 1; }
  inject_msg hello "$state" && fail "injection should refuse a missing exact target"
  [ "$calls" -eq 0 ] || fail "a guard refusal reached transport"
  pass "daemon injection requires away mode and an existing exact Herdr target"
}

test_injection_busy_and_composer_guards() {
  local state calls=0
  state=$(new_state inject-composer)
  touch "$state/.afk"
  FM_SUPERVISOR_TARGET=lab:w-primary:p1
  fm_herdr_target_exists() { return 0; }
  fm_herdr_send_text_submit() { calls=$((calls + 1)); printf empty; }
  pane_is_busy() { return 0; }
  inject_msg hello "$state" && fail "busy Firstmate pane should defer"
  pane_is_busy() { return 1; }
  for verdict in pending pending-unproven unknown; do
    fm_herdr_composer_state() { printf '%s' "$verdict"; }
    inject_msg hello "$state" && fail "$verdict composer should defer"
  done
  [ "$calls" -eq 0 ] || fail "unsafe composer reached submit"
  pass "daemon busy and composer guards defer every unsafe verdict"
}

test_injection_types_once_through_herdr() {
  local state submit_log
  state=$(new_state inject-success)
  submit_log=$state/submit.log
  touch "$state/.afk"
  FM_SUPERVISOR_TARGET=lab:w-primary:p1
  fm_herdr_target_exists() { return 0; }
  pane_is_busy() { return 1; }
  fm_herdr_composer_state() { printf empty; }
  fm_herdr_send_text_submit() { printf '%s\n' "$2" >> "$submit_log"; printf empty; }
  inject_msg 'one line' "$state" || fail "safe Herdr injection should succeed"
  [ "$(wc -l < "$submit_log" | tr -d ' ')" -eq 1 ] || fail "daemon invoked submit more than once"
  assert_contains "$(cat "$submit_log")" 'FIRSTMATE_OP: v1 away-supervisor:' "operational envelope missing"
  pass "daemon sends one operationally marked payload through Herdr"
}

test_wedge_alarm_preserves_buffer() {
  local state
  state=$(new_state wedge)
  printf 'blocked: decision needed\n' > "$state/.subsuper-escalations"
  printf '0\n' > "$state/.subsuper-escalations.since"
  FM_WEDGE_ALARM_CHANNEL=off FM_MAX_DEFER_SECS=1 inject_wedge_alarm "$state" 500
  [ -s "$state/.subsuper-inject-wedged" ] || fail "wedge marker missing"
  [ -s "$state/.subsuper-escalations" ] || fail "wedge alarm erased buffered work"
  pass "wedge alarm remains visible without losing buffered work"
}

test_supervisor_target_is_herdr_only() {
  local out
  out=$(FM_SUPERVISOR_TARGET=lab:w1:p1 HERDR_ENV='' HERDR_PANE_ID='' discover_supervisor_target) \
    || fail "exact Herdr override should resolve"
  [ "$out" = lab:w1:p1 ] || fail "exact target changed"
  out=$(FM_SUPERVISOR_BACKEND=tmux discover_supervisor_target 2>&1) \
    && fail "retired supervisor selection should refuse"
  assert_contains "$out" 'tmux supervision is retired' "retired refusal should be actionable"
  out=$(TMUX=fake discover_supervisor_target 2>&1) \
    && fail "tmux environment should refuse"
  assert_contains "$out" 'leave the tmux environment' "tmux environment refusal should be actionable"
  pass "supervisor discovery accepts only exact Herdr identity"
}

test_stale_observation_refuses_moved_live_endpoint() {
  local state capture_log rc=0
  state=$(new_state stale-live-identity)
  capture_log=$state/capture.log
  fm_write_meta "$state/task.meta" \
    "backend=herdr" "window=lab:w-task:p1" "endpoint_task_id=task" \
    "herdr_session=lab" "herdr_workspace_id=w-task" "herdr_tab_id=w-task:t1" \
    "herdr_pane_id=w-task:p1" "worktree=/tmp/task" "project=/tmp/project" "harness=pi"
  fm_herdr_presentation_session_lock_path() { printf '%s' "$state/live.lock"; }
  fm_lock_try_acquire() { mkdir "$1" 2>/dev/null; }
  fm_lock_release() { rmdir "$1" 2>/dev/null || true; }
  fm_herdr_cli() {
    case "${2:-} ${3:-}" in
      "pane get") printf '{"result":{"pane":{"pane_id":"w-task:p1","tab_id":"w-task:t2","workspace_id":"w-task"}}}\n' ;;
      "tab get") printf '{"result":{"tab":{"tab_id":"w-task:t1","workspace_id":"w-task"}}}\n' ;;
    esac
  }
  fm_herdr_capture() { : > "$capture_log"; }
  stale_window_is_busy 'lab:w-task:p1' "$state" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "moved stale endpoint should be unreadable, got $rc"
  [ ! -e "$capture_log" ] || fail "daemon captured a stale pane after its live identity moved"
  pass "daemon stale observation refuses a moved live endpoint"
}

test_signal_classification
test_pause_classification_and_tracking
test_unmatched_stale_escalates_without_shared_markers
test_escalation_buffer_is_durable
test_injection_presence_and_target_guards
test_injection_busy_and_composer_guards
test_injection_types_once_through_herdr
test_wedge_alarm_preserves_buffer
test_supervisor_target_is_herdr_only
test_stale_observation_refuses_moved_live_endpoint
