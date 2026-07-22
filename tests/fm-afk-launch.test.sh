#!/usr/bin/env bash
# Herdr-only away-daemon terminal lifecycle and topology regressions.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LAUNCH="$ROOT/bin/fm-afk-launch.sh"
START="$ROOT/bin/fm-afk-start.sh"
TMP_ROOT=$(fm_test_tmproot fm-afk-launch)

make_sleeper() {
  local path="$TMP_ROOT/sleeper"
  printf '#!/usr/bin/env bash\nexec sleep 600\n' > "$path"
  chmod +x "$path"
  printf '%s\n' "$path"
}

test_clear_stale_artifacts_preserves_queue() {
  local home="$TMP_ROOT/clear"
  mkdir -p "$home/state"
  : > "$home/state/.subsuper-escalations"
  : > "$home/state/.subsuper-escalations.since"
  : > "$home/state/.subsuper-inject-wedged"
  : > "$home/state/.wake-queue"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    bash -c '. "$1"; fm_afk_clear_stale_artifacts "$2"' _ "$START" "$home/state"
  assert_absent "$home/state/.subsuper-escalations" "stale escalation buffer survived"
  assert_absent "$home/state/.subsuper-escalations.since" "stale escalation timestamp survived"
  assert_absent "$home/state/.subsuper-inject-wedged" "stale wedge marker survived"
  [ -e "$home/state/.wake-queue" ] || fail "durable wake queue was removed"
  pass "away entry clears session-scoped delivery artifacts without dropping the wake queue"
}

test_record_contract_is_herdr_or_native_only() {
  local home="$TMP_ROOT/records" out
  mkdir -p "$home/state"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" bash -c '
    . "$1"
    fm_afk_launch_record_write "lab:w1:p2" "ws-daemon"
    fm_afk_launch_record_read
    [ "$FM_AFK_REC_TARGET" = "lab:w1:p2" ]
    [ "$FM_AFK_REC_WORKSPACE" = "ws-daemon" ]
    fm_afk_launch_record_write - native
    fm_afk_launch_record_read
    [ "$FM_AFK_REC_TARGET" = - ]
    [ "$FM_AFK_REC_WORKSPACE" = native ]
  ' _ "$LAUNCH" || fail "valid Herdr/native records did not round-trip"

  printf 'herdr\tlab:w1:p2\tws-daemon\n' > "$home/state/.afk-daemon-terminal"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" bash -c '
    . "$1"
    fm_afk_launch_record_read
    [ "$FM_AFK_REC_TARGET" = "lab:w1:p2" ]
    [ "$FM_AFK_REC_WORKSPACE" = "ws-daemon" ]
  ' _ "$LAUNCH" || fail "legacy Herdr record was not normalized"
  printf 'none\t-\tnative\n' > "$home/state/.afk-daemon-terminal"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" bash -c '
    . "$1"
    fm_afk_launch_record_read
    [ "$FM_AFK_REC_TARGET" = - ]
    [ "$FM_AFK_REC_WORKSPACE" = native ]
  ' _ "$LAUNCH" || fail "legacy native record was not normalized"

  printf 'legacy-provider\tlegacy-session\towned\n' > "$home/state/.afk-daemon-terminal"
  out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" bash -c '
    . "$1"
    ! fm_afk_launch_record_read
  ' _ "$LAUNCH" 2>&1)
  assert_contains "$out" "uses removed session provider 'legacy-provider'" \
    "foreign away record did not provide migration guidance"
  pass "away terminal records accept current and valid legacy Herdr/native shapes only"
}

test_exact_close_and_absence_verification() {
  local home="$TMP_ROOT/exact-close" log="$TMP_ROOT/exact-close.log"
  mkdir -p "$home/state"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" LOG_PATH="$log" bash -c '
    . "$1"
    fm_backend_herdr_cli() {
      [ "$1" = lab ] && [ "$2" = pane ] && [ "$3" = close ] && [ "$4" = "w1:p2" ] || return 1
      printf "%s\n" "$*" >> "$LOG_PATH"
    }
    fm_afk_launch_close_terminal "lab:w1:p2"
  ' _ "$LAUNCH" || fail "exact Herdr pane close failed"
  assert_contains "$(cat "$log")" "lab pane close w1:p2" "close did not use the exact recorded pane"

  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" bash -c '
    . "$1"
    fm_backend_herdr_cli() { printf %s "{\"error\":{\"code\":\"pane_not_found\"}}"; return 1; }
    fm_afk_launch_terminal_absent "lab:w1:p2"
    fm_backend_herdr_cli() { printf %s "{\"error\":{\"code\":\"transport_error\"}}"; return 1; }
    ! fm_afk_launch_terminal_absent "lab:w1:p2"
  ' _ "$LAUNCH" || fail "absence verification confused a transport failure with pane_not_found"
  pass "away cleanup mutates only the exact Herdr pane and confirms absence fail-closed"
}

test_create_publishes_exact_ids_before_run() {
  local home="$TMP_ROOT/create" log="$TMP_ROOT/create.log" sleeper
  mkdir -p "$home/state"
  sleeper=$(make_sleeper)
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_AFK_LAUNCH_ENTRY="$sleeper" \
    FM_AFK_LAUNCH_LABEL=afk-unit LOG_PATH="$log" bash -c '
    . "$1"
    fm_backend_herdr_server_ensure() { [ "$1" = lab ]; }
    fm_backend_herdr_cli() {
      printf "%s\n" "$*" >> "$LOG_PATH"
      case "$2 $3" in
        "workspace create")
          printf %s "{\"result\":{\"workspace\":{\"workspace_id\":\"ws1\"},\"root_pane\":{\"pane_id\":\"w1:p2\"}}}"
          ;;
        "pane run")
          [ -f "$FM_AFK_LAUNCH_RECORD" ] || return 1
          ;;
        "pane get")
          printf %s "{\"result\":{\"pane\":{\"pane_id\":\"w1:p2\"}}}"
          ;;
        *) return 1 ;;
      esac
    }
    fm_afk_launch_create_herdr "lab:w1:p1"
  ' _ "$LAUNCH" || fail "Herdr away terminal creation failed"
  assert_contains "$(cat "$home/state/.afk-daemon-terminal")" $'lab:w1:p2\tws1' "exact Herdr ids were not durably recorded"
  assert_contains "$(cat "$log")" "lab pane run w1:p2" "daemon entry was not started in the recorded pane"
  pass "Herdr away launch publishes exact workspace/pane ids before starting the daemon"
}

test_failed_entry_rolls_back_away_state() {
  local home="$TMP_ROOT/rollback"
  mkdir -p "$home/state"
  printf 'pending\n' > "$home/state/.subsuper-escalations"
  printf 'wedged\n' > "$home/state/.subsuper-inject-wedged"
  if FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_SUPERVISOR_TARGET="lab:w1:p1" bash -c '
    . "$1"
    fm_afk_launch_reconcile() { return 0; }
    fm_afk_launch_create_herdr() { return 1; }
    ! fm_afk_launch_start
  ' _ "$LAUNCH" \
    && [ ! -e "$home/state/.afk" ] \
    && [ "$(cat "$home/state/.subsuper-escalations")" = pending ] \
    && [ "$(cat "$home/state/.subsuper-inject-wedged")" = wedged ]; then
    pass "failed Herdr launch rolls back away state and delivery artifacts"
  else
    fail "failed Herdr launch left false away state or lost delivery artifacts"
  fi
}

test_native_lifecycle_uses_no_terminal() {
  local home="$TMP_ROOT/native"
  mkdir -p "$home/state"
  : > "$home/state/.subsuper-escalations"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$LAUNCH" start-native >/dev/null 2>&1 \
    || fail "native away lifecycle did not start"
  assert_contains "$(cat "$home/state/.afk-daemon-terminal")" $'-\tnative' "native sentinel record is wrong"
  [ -e "$home/state/.afk" ] || fail "native start did not set away mode"
  assert_absent "$home/state/.subsuper-escalations" "native start retained stale artifacts"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$LAUNCH" stop >/dev/null 2>&1 \
    || fail "native away lifecycle did not stop"
  assert_absent "$home/state/.afk" "native stop retained away mode"
  assert_absent "$home/state/.afk-daemon-terminal" "native stop retained the terminal record"
  pass "harness-native supervision shares lifecycle state without manufacturing a terminal"
}

test_stop_signals_daemon_before_clearing_afk() {
  local home="$TMP_ROOT/stop-order" marker="$TMP_ROOT/afk-at-term" pid lock identity
  mkdir -p "$home/state"
  : > "$home/state/.afk"
  printf '%s\n' $'none\t-\tnative' > "$home/state/.afk-daemon-terminal"
  bash -c '
    trap "if [ -f \"$1/state/.afk\" ]; then echo present > \"$2\"; else echo absent > \"$2\"; fi; exit 0" TERM
    while :; do sleep 0.1; done
  ' _ "$home" "$marker" &
  pid=$!
  lock="$home/state/.supervise-daemon.lock"
  mkdir -p "$lock"
  printf '%s' "$pid" > "$lock/pid"
  identity=$(bash -c '. "$1"; fm_pid_identity "$2"' _ "$ROOT/bin/fm-wake-lib.sh" "$pid") \
    || fail "could not identify the synthetic daemon"
  printf '%s\n' "$identity" > "$lock/pid-identity"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$LAUNCH" stop >/dev/null 2>&1 \
    || fail "ordered away stop failed"
  wait "$pid" 2>/dev/null || true
  [ "$(cat "$marker" 2>/dev/null)" = present ] || fail ".afk was removed before daemon shutdown flush"
  assert_absent "$home/state/.afk" "away flag survived ordered stop"
  pass "away stop lets the daemon flush while .afk exists, then clears it last"
}

test_reused_pid_is_never_signaled() {
  local home="$TMP_ROOT/reused-pid" pid lock
  mkdir -p "$home/state"
  : > "$home/state/.afk"
  printf '%s\n' $'-\tnative' > "$home/state/.afk-daemon-terminal"
  sleep 30 & pid=$!
  lock="$home/state/.supervise-daemon.lock"
  mkdir -p "$lock"
  printf '%s' "$pid" > "$lock/pid"
  printf 'different-process-identity' > "$lock/pid-identity"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$LAUNCH" stop >/dev/null 2>&1 \
    || fail "stop with a stale daemon lock failed"
  kill -0 "$pid" 2>/dev/null || fail "stale lock signaled an unrelated process"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pass "away stop rejects reused pids before signaling"
}

test_live_herdr_topology() (
  command -v herdr >/dev/null 2>&1 || { echo "skip: herdr not found (Herdr topology)"; exit 0; }
  command -v jq >/dev/null 2>&1 || { echo "skip: jq not found (Herdr topology)"; exit 0; }

  local HERDR_LAB_HELPER HERDR_LAB_SESSION home sleeper out captain_ws captain_tab captain_pane target
  local before during after workspaces_before workspaces_during workspaces_after daemon_target daemon_tab
  HERDR_LAB_HELPER='/home/control/firstmate/bin/fm-herdr-lab.sh'
  HERDR_LAB_SESSION=$("$HERDR_LAB_HELPER" name firstmate-herdr-only-backend) \
    || fail "could not generate a named Herdr lab session"
  trap '"$HERDR_LAB_HELPER" teardown "$HERDR_LAB_SESSION" >/dev/null 2>&1 || true' EXIT
  "$HERDR_LAB_HELPER" provision "$HERDR_LAB_SESSION" >/dev/null \
    || fail "could not provision the named Herdr lab session"

  home="$TMP_ROOT/live-home"
  mkdir -p "$home/state"
  sleeper=$(make_sleeper)
  out=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" workspace create --cwd "$ROOT" --label captain --no-focus) \
    || fail "could not create the lab captain workspace"
  captain_ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id // empty')
  captain_tab=$(printf '%s' "$out" | jq -r '.result.tab.tab_id // empty')
  captain_pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id // empty')
  [ -n "$captain_ws" ] && [ -n "$captain_tab" ] && [ -n "$captain_pane" ] \
    || fail "lab captain workspace returned incomplete ids"
  target="$HERDR_LAB_SESSION:$captain_pane"
  before=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" pane list --workspace "$captain_ws" \
    | jq --arg tab "$captain_tab" '[.result.panes[]? | select(.tab_id == $tab)] | length')
  workspaces_before=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" workspace list | jq '[.result.workspaces[]?] | length')

  HERDR_SESSION="$HERDR_LAB_SESSION" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_SUPERVISOR_TARGET="$target" FM_AFK_LAUNCH_ENTRY="$sleeper" \
    "$LAUNCH" start >/dev/null 2>&1 || fail "Herdr away launcher did not start in the lab"
  during=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" pane list --workspace "$captain_ws" \
    | jq --arg tab "$captain_tab" '[.result.panes[]? | select(.tab_id == $tab)] | length')
  workspaces_during=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" workspace list | jq '[.result.workspaces[]?] | length')
  daemon_target=$(cut -f1 "$home/state/.afk-daemon-terminal")
  daemon_tab=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" pane get "${daemon_target#*:}" | jq -r '.result.pane.tab_id // empty')

  [ "$during" = "$before" ] || fail "away launch changed the captain tab pane count"
  [ "$workspaces_during" -gt "$workspaces_before" ] || fail "away launch did not create a separate workspace"
  [ -n "$daemon_tab" ] && [ "$daemon_tab" != "$captain_tab" ] || fail "daemon pane shares the captain tab"
  case "$daemon_target" in "$HERDR_LAB_SESSION":*) ;; *) fail "daemon target escaped the named lab session" ;; esac

  HERDR_SESSION="$HERDR_LAB_SESSION" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_SUPERVISOR_TARGET="$target" "$LAUNCH" stop >/dev/null 2>&1 \
    || fail "Herdr away launcher did not stop in the lab"
  after=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" pane list --workspace "$captain_ws" \
    | jq --arg tab "$captain_tab" '[.result.panes[]? | select(.tab_id == $tab)] | length')
  workspaces_after=$("$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" workspace list | jq '[.result.workspaces[]?] | length')
  [ "$after" = "$before" ] || fail "away stop changed the captain tab topology"
  [ "$workspaces_after" = "$workspaces_before" ] || fail "away daemon workspace leaked"
  assert_absent "$home/state/.afk-daemon-terminal" "away stop retained its terminal record"
  assert_absent "$home/state/.afk" "away stop retained away mode"
  pass "live Herdr away lifecycle preserves captain topology in an isolated named lab"
)

test_clear_stale_artifacts_preserves_queue
test_record_contract_is_herdr_or_native_only
test_exact_close_and_absence_verification
test_create_publishes_exact_ids_before_run
test_failed_entry_rolls_back_away_state
test_native_lifecycle_uses_no_terminal
test_stop_signals_daemon_before_clearing_afk
test_reused_pid_is_never_signaled
test_live_herdr_topology
