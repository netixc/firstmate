#!/usr/bin/env bash
# Hermetic away-daemon launcher and lifecycle tests for the Herdr-only supervisor.
set -u
# shellcheck disable=SC2031 # Process-identity probes intentionally run in subshells.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LAUNCH="$ROOT/bin/fm-afk-launch.sh"
START="$ROOT/bin/fm-afk-start.sh"
TMP_ROOT=$(fm_test_tmproot fm-afk-launch)

unit_clear_stale() {
  local home
  home="$TMP_ROOT/clear-stale"
  mkdir -p "$home/state"
  : > "$home/state/.subsuper-escalations"
  : > "$home/state/.subsuper-escalations.since"
  : > "$home/state/.subsuper-inject-wedged"
  : > "$home/state/.wake-queue"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    bash -c '. "$1"; fm_afk_clear_stale_artifacts "$2"' _ "$START" "$home/state"
  assert_absent "$home/state/.subsuper-escalations" "stale escalation buffer survived"
  assert_absent "$home/state/.subsuper-escalations.since" "stale escalation timestamp survived"
  assert_absent "$home/state/.subsuper-inject-wedged" "stale injection marker survived"
  assert_present "$home/state/.wake-queue" "durable wake queue was removed"
  pass "away lifecycle: fresh entry clears only stale delivery artifacts"
}

unit_relative_paths_are_absolute_before_daemon_launch() {
  local root home state out status
  root="$TMP_ROOT/relative"
  mkdir -p "$root/home/state" "$root/cdpath/home/state"
  home=$(cd "$root/home" && pwd -P)
  state="$home/state"
  out=$(cd "$root" && CDPATH="$root/cdpath" FM_HOME=home FM_STATE_OVERRIDE=home/state \
    bash -c '. "$1"; printf "%s\n%s\n" "$FM_HOME" "$FM_AFK_LAUNCH_STATE"' _ "$LAUNCH")
  [ "$out" = "$home"$'\n'"$state" ] || fail "relative launcher paths remained cwd-dependent: $out"
  out=$(cd "$root" && FM_HOME=missing-home "$LAUNCH" help 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "an unresolved home should fail"
  assert_contains "$out" "FM_HOME directory cannot be resolved: missing-home" "bad home diagnostic mismatch"
  pass "away launcher: relative paths resolve once and bad paths stop clearly"
}

unit_refresh_preserves_current_buffer() {
  local home pid lock
  home="$TMP_ROOT/refresh"
  mkdir -p "$home/state"
  : > "$home/state/.subsuper-escalations"
  : > "$home/state/.subsuper-inject-wedged"
  sleep 600 & pid=$!
  lock="$home/state/.supervise-daemon.lock"
  mkdir -p "$lock"
  printf '%s' "$pid" > "$lock/pid"
  FM_STATE_OVERRIDE="$home/state" bash -c ' . "$1"; fm_pid_identity "$2"' _ \
    "$ROOT/bin/fm-wake-lib.sh" "$pid" > "$lock/pid-identity"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$START" >/dev/null 2>&1
  assert_present "$home/state/.subsuper-escalations" "refresh discarded current escalation buffer"
  assert_present "$home/state/.subsuper-inject-wedged" "refresh discarded current wedge marker"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pass "away lifecycle: refresh preserves the current session's delivery buffer"
}

unit_stop_ordering() {
  local home lock marker pid
  home="$TMP_ROOT/stop-order"
  mkdir -p "$home/state"
  date '+%s' > "$home/state/.afk"
  marker="$home/afk-at-term"
  bash -c 'trap "[ -f \"$1/state/.afk\" ] && echo present > \"$2\" || echo absent > \"$2\"; exit 0" TERM; while :; do sleep 0.2; done' \
    _ "$home" "$marker" & pid=$!
  lock="$home/state/.supervise-daemon.lock"
  mkdir -p "$lock"
  printf '%s' "$pid" > "$lock/pid"
  FM_STATE_OVERRIDE="$home/state" bash -c ' . "$1"; fm_pid_identity "$2"' _ \
    "$ROOT/bin/fm-wake-lib.sh" "$pid" > "$lock/pid-identity"
  printf 'none\t-\tnative\n' > "$home/state/.afk-daemon-terminal"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$LAUNCH" stop >/dev/null 2>&1
  [ "$(cat "$marker" 2>/dev/null || true)" = present ] || fail "away flag cleared before the daemon flushed"
  assert_absent "$home/state/.afk" "away flag remained after stop"
  assert_absent "$home/state/.afk-daemon-terminal" "terminal record remained after stop"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pass "away lifecycle: stop signals the daemon before clearing durable away state"
}

unit_stop_rejects_reused_pid() {
  local home lock pid
  home="$TMP_ROOT/reused-pid"
  mkdir -p "$home/state"
  date '+%s' > "$home/state/.afk"
  sleep 600 & pid=$!
  lock="$home/state/.supervise-daemon.lock"
  mkdir -p "$lock"
  printf '%s' "$pid" > "$lock/pid"
  printf 'different-process-identity' > "$lock/pid-identity"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$LAUNCH" stop >/dev/null 2>&1
  kill -0 "$pid" 2>/dev/null || fail "stale lock signalled an unrelated live process"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pass "away lifecycle: stale process identity cannot signal an unrelated process"
}

unit_unresolved_target_rolls_back_state() {
  local home
  home="$TMP_ROOT/failed-start"
  mkdir -p "$home/state"
  printf 'pending\n' > "$home/state/.subsuper-escalations"
  printf 'wedged\n' > "$home/state/.subsuper-inject-wedged"
  if FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_SUPERVISOR_TARGET='' \
    HERDR_ENV='' HERDR_PANE_ID='' "$LAUNCH" start >/dev/null 2>&1; then
    fail "launch without an authoritative supervisor target unexpectedly succeeded"
  fi
  assert_absent "$home/state/.afk" "failed start left false away state"
  [ "$(cat "$home/state/.subsuper-escalations")" = pending ] || fail "failed start discarded escalations"
  [ "$(cat "$home/state/.subsuper-inject-wedged")" = wedged ] || fail "failed start discarded wedge marker"
  pass "away launcher: unresolved targets roll back without losing delivery artifacts"
}

unit_herdr_partial_create_recovery() {
  local home record
  home="$TMP_ROOT/herdr-partial"
  record="$home/recorded"
  mkdir -p "$home"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_AFK_LAUNCH_ENTRY=/bin/true \
    FM_AFK_LAUNCH_LABEL=afk-exact-label RECORDED="$record" bash -c '
      . "$1"
      fm_backend_source() { return 0; }
      fm_backend_herdr_server_ensure() { return 0; }
      fm_backend_herdr_cli() {
        if [ "$2 $3" = "workspace create" ]; then printf truncated; return 1; fi
        if [ "$2 $3" = "workspace list" ]; then
          printf "%s" "{\"result\":{\"workspaces\":[{\"workspace_id\":\"ws-partial\",\"label\":\"afk-exact-label\"}]}}"
        else
          printf "%s" "{\"result\":{\"panes\":[{\"pane_id\":\"pane-exact\"}]}}"
        fi
      }
      fm_afk_launch_record_write() { printf "%s:%s:%s" "$1" "$2" "$3" > "$RECORDED"; }
      fm_afk_launch_create_herdr lab:captain herdr
    ' _ "$LAUNCH"
  [ "$(cat "$record" 2>/dev/null || true)" = 'herdr:lab:pane-exact:ws-partial' ] \
    || fail "malformed create response did not recover exact Herdr ownership"
  pass "away launcher: partial Herdr creation recovers an exact durable endpoint"
}

unit_record_write_rejects_unsupported_backend() {
  local home out status
  home="$TMP_ROOT/record-validation"
  mkdir -p "$home/state"
  out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" bash -c '
    . "$1"
    fm_afk_launch_record_write unsupported endpoint owned
  ' _ "$LAUNCH" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "unsupported terminal record backend was accepted"
  assert_contains "$out" "supported: herdr" "record rejection did not name the current supported choice"
  assert_absent "$home/state/.afk-daemon-terminal" "unsupported record was published"
  pass "away launcher: terminal records accept only Herdr"
}

unit_clear_stale
unit_relative_paths_are_absolute_before_daemon_launch
unit_refresh_preserves_current_buffer
unit_stop_ordering
unit_stop_rejects_reused_pid
unit_unresolved_target_rolls_back_state
unit_herdr_partial_create_recovery
unit_record_write_rejects_unsupported_backend
