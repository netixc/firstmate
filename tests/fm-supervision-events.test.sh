#!/usr/bin/env bash
# tests/fm-supervision-events.test.sh - unit tests for the watcher's native
# event-wait splice (event_wait_or_sleep in bin/fm-watch.sh and
# handle_push_transition in bin/fm-push-transition-lib.sh). The watcher's source
# guard lets this file source it to load
# the functions WITHOUT acquiring the singleton lock or entering the blocking
# loop; wake/sleep and the Herdr primitives are overridden so the exemptions,
# capability memo, and fail-closed disable are asserted deterministically with no
# real herdr, watcher process, or blocking sleeps.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot fm-supervision-events)
STATE_DIR="$TMP/state"
FAKEBIN="$TMP/fakebin"
ENDPOINT_MAP="$TMP/endpoints"
mkdir -p "$STATE_DIR" "$FAKEBIN"
: > "$ENDPOINT_MAP"
cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "session list") printf '{"sessions":[{"name":"%s","running":true,"socket_path":"%s/herdr.sock"}]}\n' "${HERDR_SESSION:-lab}" "${FM_HOME:-/tmp}" ;;
  "pane get")
    row=$(awk -F '\t' -v pane="${3:-}" '$1 == pane { print; exit }' "$FM_TEST_ENDPOINT_MAP")
    [ -n "$row" ] || exit 1
    IFS="$(printf '\t')" read -r pane tab workspace <<EOF
$row
EOF
    printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s","workspace_id":"%s"}}}\n' "$pane" "$tab" "$workspace"
    ;;
  "tab get")
    workspace=$(awk -F '\t' -v tab="${3:-}" '$2 == tab { print $3; exit }' "$FM_TEST_ENDPOINT_MAP")
    [ -n "$workspace" ] || exit 1
    printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"%s"}}}\n' "${3:-}" "$workspace"
    ;;
esac
SH
chmod +x "$FAKEBIN/herdr"
export FM_TEST_ENDPOINT_MAP="$ENDPOINT_MAP"
export PATH="$FAKEBIN:$PATH"

# Source the watcher with an isolated state/home. The guard returns before the
# lock/loop, so only the functions load.
export FM_STATE_OVERRIDE="$STATE_DIR"
export FM_ROOT_OVERRIDE="$ROOT"
# Production modules are independently linted canonical roots. Keep this test's
# ShellCheck context local while preserving its unchanged runtime source path.
# shellcheck source=/dev/null
. "$ROOT/bin/fm-watch.sh"

# Overrides: capture wake reasons and neutralize real sleeps (POLL is 15s).
WAKE_LOG="$TMP/wakes"
SLEEP_LOG="$TMP/sleeps"
wake() { printf '%s\n' "$1" >> "$WAKE_LOG"; return 0; }
sleep() { printf 'SLEEP\n' >> "$SLEEP_LOG"; }

reset_state() {
  rm -f "$STATE_DIR"/*.meta "$STATE_DIR"/*.status "$STATE_DIR"/.wake-queue \
    "$STATE_DIR"/.wake-queue.seq "$STATE_DIR"/.watch-triage.log \
    "$STATE_DIR"/.herdr-escalated-* "$TMP"/panes "$TMP"/wtcalls "$TMP"/wtcalled 2>/dev/null || true
  : > "$WAKE_LOG"
  : > "$SLEEP_LOG"
  : > "$ENDPOINT_MAP"
  _event_cap_key=""
  _event_cap_ok=0
  _event_cap_fails=0
}

mkrec() {  # <pane_id> <status>
  fm_herdr_transition_record "$1" "wG" "" "$2" pi
}

write_endpoint_meta() {  # <id> <target> <kind>
  local id=$1 target=$2 kind=$3 rest
  rest=${target#*:}
  fm_write_meta "$STATE_DIR/$id.meta" \
    "backend=herdr" "window=$target" "endpoint_task_id=$id" \
    "herdr_session=${target%%:*}" "herdr_workspace_id=${rest%%:*}" \
    "herdr_tab_id=${rest%%:*}:t-$id" "herdr_pane_id=$rest" \
    "worktree=/tmp/$id" "project=/tmp/project" "kind=$kind" "harness=pi"
  printf '%s\t%s:t-%s\t%s\n' "$rest" "${rest%%:*}" "$id" "${rest%%:*}" >> "$ENDPOINT_MAP"
}

# --- handle_push_transition: enqueue + wake for a non-paused blocked crew -----

reset_state
write_endpoint_meta tk1 default:wG:pQ ship
handle_push_transition default "$(mkrec wG:pQ blocked)"
[ -e "$STATE_DIR/.wake-queue" ] || fail "handle_push_transition should enqueue a wake for a blocked crew"
grep -q 'stale' "$STATE_DIR/.wake-queue" || fail "the enqueued wake must be a stale record: $(cat "$STATE_DIR/.wake-queue")"
grep -q 'default:wG:pQ' "$STATE_DIR/.wake-queue" || fail "the stale record must name the crew's window"
grep -q 'herdr: agent blocked' "$STATE_DIR/.wake-queue" || fail "the stale payload must name the herdr-blocked cause"
[ -s "$WAKE_LOG" ] || fail "handle_push_transition must wake the supervisor for a blocked crew"
[ -e "$STATE_DIR/.herdr-escalated-default_wG_pQ" ] || fail "handle_push_transition must commit dedupe only after enqueue"
pass "handle_push_transition: a blocked crew enqueues a stale wake naming its window and wakes the supervisor"

reset_state
write_endpoint_meta tk1 default:wG:pQ ship
(
  # shellcheck disable=SC2329 # Runtime override called by the isolated production owner.
  fm_wake_append() { return 1; }
  handle_push_transition default "$(mkrec wG:pQ blocked)"
) >/dev/null 2>&1 || true
[ ! -e "$STATE_DIR/.herdr-escalated-default_wG_pQ" ] || fail "a failed durable enqueue must leave the blocked edge eligible for reconnect reconciliation"
pass "handle_push_transition: enqueue failure cannot commit the Herdr dedupe marker"

# --- handle_push_transition: absorb (no wake, no enqueue) for a declared pause -

reset_state
write_endpoint_meta tk2 default:wG:pQ ship
printf 'paused: waiting on the upstream release\n' > "$STATE_DIR/tk2.status"
handle_push_transition default "$(mkrec wG:pQ blocked)"
if [ -e "$STATE_DIR/.wake-queue" ] && grep -q 'stale' "$STATE_DIR/.wake-queue"; then
  fail "a declared-pause crew must NOT be fast-escalated: $(cat "$STATE_DIR/.wake-queue")"
fi
[ ! -s "$WAKE_LOG" ] || fail "a declared-pause crew must not wake the supervisor from the event fast-path"
grep -q 'absorbed push' "$STATE_DIR/.watch-triage.log" 2>/dev/null || fail "the paused absorb should be logged to the triage log"
pass "handle_push_transition: a declared-pause crew is absorbed (no fast wake), left to the poll loop's long cadence"

# --- event_wait_or_sleep: secondmate windows are excluded from the pane list --

reset_state
write_endpoint_meta tk3 default:wG:pQ ship
write_endpoint_meta sm1 default:wA:pS secondmate
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_events_capable() { return 0; }
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_wait_transition() { shift 3; printf '%s\n' "$*" > "$TMP/panes"; return 1; }
event_wait_or_sleep
PANES=$(cat "$TMP/panes" 2>/dev/null || true)
case "$PANES" in *"default:wG:pQ"*) : ;; *) fail "the ship window must be in the event pane list, got '$PANES'" ;; esac
case "$PANES" in *"default:wA:pS"*) fail "a kind=secondmate window must be EXCLUDED from the event pane list, got '$PANES'" ;; *) : ;; esac
pass "event_wait_or_sleep: herdr windows go on the event pane list, but kind=secondmate endpoints are excluded"

reset_state
write_endpoint_meta tk3 default:wG:pQ ship
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_events_capable() { return 0; }
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_wait_transition() {
  local lock
  lock=$(fm_herdr_presentation_session_lock_path default) || fail "event wait could not resolve its session lock"
  fm_lock_try_acquire "$lock" || fail "event wait monopolized the endpoint-control lock"
  fm_lock_release "$lock"
  return 1
}
event_wait_or_sleep
pass "event_wait_or_sleep: blocking transition waits leave endpoint control unlocked"

reset_state
write_endpoint_meta tk3 default:wG:pQ ship
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_events_capable() { return 0; }
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_wait_transition() {
  printf 'wG:pQ\twG:t-foreign\twG\n' > "$ENDPOINT_MAP"
  mkrec wG:pQ blocked
}
event_wait_or_sleep
[ ! -s "$WAKE_LOG" ] || fail "a transition for an endpoint that moved during the wait reached supervision"
[ ! -e "$STATE_DIR/.wake-queue" ] || fail "a moved endpoint transition was durably acknowledged"
pass "event_wait_or_sleep: returned transitions are revalidated before acknowledgement"

reset_state
write_endpoint_meta tk3 default:wG:pQ ship
marker=$(fm_herdr_escalation_marker "$STATE_DIR" default:wG:pQ)
: > "$marker"
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_events_capable() { return 0; }
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_wait_transition() {
  printf 'wG:pQ\twG:t-foreign\twG\n' > "$ENDPOINT_MAP"
  mkrec wG:pQ working
}
event_wait_or_sleep
[ -e "$marker" ] || fail "an unvalidated working transition cleared the task's dedupe marker"
pass "event_wait_or_sleep: foreign working transitions cannot mutate dedupe state"

reset_state
write_endpoint_meta tk3 default:wG:pQ ship
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_events_capable() { return 0; }
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_wait_transition() { fm_herdr_transition_record wG:pQ "" "" blocked pi; }
event_wait_or_sleep
[ -s "$WAKE_LOG" ] || fail "a live-validated level reconcile did not reach supervision"
[ -e "$STATE_DIR/.wake-queue" ] || fail "a live-validated level reconcile was not durably queued"
pass "event_wait_or_sleep: level reconciliation accepts live component identity"

reset_state
write_endpoint_meta tk3 default:wG:pQ ship
printf 'wG:pQ\twG:t-foreign\twG\n' > "$ENDPOINT_MAP"
# shellcheck disable=SC2329 # Runtime override called by the isolated watcher.
fm_herdr_events_capable() { return 0; }
# shellcheck disable=SC2329 # Runtime override called by the isolated watcher.
fm_herdr_wait_transition() { printf 'CALLED\n' > "$TMP/wtcalled"; return 1; }
event_wait_or_sleep
[ ! -e "$TMP/wtcalled" ] || fail "a mismatched live endpoint reached watcher observation"
grep -q 'SLEEP' "$SLEEP_LOG" || fail "a mismatched live endpoint did not leave the watcher on its safe polling path"
pass "event_wait_or_sleep: mismatched live endpoint identity is excluded from observation"

reset_state
write_endpoint_meta tk3 default:wG:pQ ship
CAP_CALLS=0
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_events_capable() { CAP_CALLS=$((CAP_CALLS + 1)); return 0; }
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_wait_transition() {
  [ "${FM_HERDR_EVENTS_CAPABILITY_CONFIRMED:-0}" = 1 ] || fail "cached capability verdict was not passed to the wait"
  return 1
}
event_wait_or_sleep
event_wait_or_sleep
[ "$CAP_CALLS" = 1 ] || fail "capability probe must be memoized across waits, got $CAP_CALLS calls"
pass "event_wait_or_sleep: one cached capability probe owns validation across bounded waits"

# --- event_wait_or_sleep: a retired fieldless home never runs the event path ----------

reset_state
fm_write_meta "$STATE_DIR/tk4.meta" "window=fmses:fm-tk4" "kind=ship"   # no backend= -> retired legacy metadata
# shellcheck disable=SC2329 # Runtime override called by the isolated watcher.
fm_herdr_wait_transition() { printf 'CALLED\n' > "$TMP/wtcalled"; return 1; }
event_wait_or_sleep
[ ! -e "$TMP/wtcalled" ] || fail "a retired fieldless home must never invoke the event wait path"
grep -q 'SLEEP' "$SLEEP_LOG" || fail "a retired fieldless home must sleep POLL exactly as before"
pass "event_wait_or_sleep: a home with no current Herdr window is inert (sleeps POLL, never touches the event path)"

# --- event_wait_or_sleep: runtime failures disable the event path (fail-closed)

reset_state
write_endpoint_meta tk5 default:wG:pQ ship
export EVENT_CAP_FAIL_MAX=2
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_events_capable() { return 0; }
# shellcheck disable=SC2329 # Runtime overrides called by the isolated watcher.
fm_herdr_wait_transition() { printf 'WT\n' >> "$TMP/wtcalls"; return 2; }
: > "$TMP/wtcalls"
event_wait_or_sleep   # fails=1
event_wait_or_sleep   # fails=2 -> disable
event_wait_or_sleep   # disabled: sleeps without calling wait_transition
WTN=$(wc -l < "$TMP/wtcalls" | tr -d '[:space:]')
[ "$WTN" = 2 ] || fail "after EVENT_CAP_FAIL_MAX connect failures the event path must be disabled for the process (expected 2 wait_transition calls, got $WTN)"
pass "event_wait_or_sleep: consecutive event-path failures disable the fast-path and revert to pure polling (fail-closed)"

echo "# fm-supervision-events.test.sh: all assertions passed"
