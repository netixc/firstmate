#!/usr/bin/env bash
# Pi process-control behavior through exact Herdr task identity.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL="$ROOT/bin/fm-control.sh"
TMP_ROOT=$(fm_test_tmproot fm-control)

make_world() { # <name> <id>
  local name=$1 id=$2 world home project wt fb
  world=$TMP_ROOT/$name; home=$world/home; project=$world/project; wt=$world/wt; fb=$world/fakebin
  mkdir -p "$home/state" "$home/data/$id" "$home/config" "$fb"
  fm_git_worktree "$project" "$wt" "fm/$id"
  printf 'instructions\n' > "$home/data/$id/brief.md"
  printf alive > "$world/agent"; : > "$world/log"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_CONTROL_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "pane get")
    if [ "${FM_CONTROL_MISSING:-0}" = 1 ]; then printf '{"error":{"code":"pane_not_found"}}\n'
    else
      workspace=${3%%:*}; task=${workspace#w-}
      printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s:t-%s","workspace_id":"%s","foreground_cwd":"%s"}}}\n' "${3:-}" "$workspace" "$task" "$workspace" "$FM_CONTROL_WT"
    fi ;;
  "tab get") printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"%s"}}}\n' "${3:-}" "${3%%:*}" ;;
  "pane send-text") printf '%s' "${4:-}" > "$FM_CONTROL_LAST" ;;
  "pane send-keys")
    key=${4:-}
    if [ "$key" = escape ]; then :
    elif grep -Fxq /quit "$FM_CONTROL_LAST" 2>/dev/null; then printf dead > "$FM_CONTROL_AGENT"; fi
    ;;
  "pane read") printf '╭────╮\n│    │\n╰────╯\n' ;;
  "agent get")
    if [ "$(cat "$FM_CONTROL_AGENT")" = alive ]; then printf '{"result":{"agent":{"agent_status":"idle","provider":"pi"}}}\n'
    else printf '{"error":{"code":"agent_not_found"}}\n'; fi ;;
esac
SH
  chmod +x "$fb/herdr"
  fm_write_meta "$home/state/$id.meta" \
    "backend=herdr" "window=lab:w-$id:p1" "endpoint_task_id=$id" \
    "herdr_session=lab" "herdr_workspace_id=w-$id" "herdr_tab_id=w-$id:t-$id" \
    "herdr_pane_id=w-$id:p1" "worktree=$wt" "project=$project" \
    "harness=pi" "kind=ship" "mode=no-mistakes" "yolo=off" \
    "model=default" "effort=default" "spawn_gen=initial"
  printf '%s|%s|%s|%s\n' "$world" "$home" "$wt" "$fb"
}

run_control() { # <rec> <id> <verb...>
  local rec=$1 id=$2 world home wt fb
  shift 2
  IFS='|' read -r world home wt fb <<EOF
$rec
EOF
  env -u TMUX -u TMUX_PANE -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH \
    PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" HERDR_SESSION=lab \
    FM_CONTROL_LOG="$world/log" FM_CONTROL_AGENT="$world/agent" \
    FM_CONTROL_LAST="$world/last" FM_CONTROL_WT="$wt" \
    FM_CONTROL_POLL=0.01 FM_CONTROL_EXIT_WAIT=1 "$CONTROL" "$id" "$@"
}

test_interrupt_preserves_agent_and_endpoint() {
  local id=worker-a rec world home wt fb out
  rec=$(make_world interrupt "$id")
  IFS='|' read -r world home wt fb <<EOF
$rec
EOF
  out=$(run_control "$rec" "$id" interrupt) || fail "Pi interrupt should succeed"
  assert_contains "$out" 'interrupt-delivered' "interrupt completion missing"
  [ "$(cat "$world/agent")" = alive ] || fail "interrupt stopped Pi"
  grep -F 'pane send-keys w-worker-a:p1 escape' "$world/log" >/dev/null \
    || fail "interrupt did not deliver Pi Escape through Herdr"
  [ -f "$home/state/$id.meta" ] || fail "interrupt removed durable task identity"
  pass "interrupt delivers one Pi Escape and preserves agent, endpoint, and work"
}

test_exit_is_verified_and_idempotent() {
  local id=worker-b rec world home wt fb out
  rec=$(make_world exit "$id")
  IFS='|' read -r world home wt fb <<EOF
$rec
EOF
  out=$(run_control "$rec" "$id" exit) || fail "Pi exit should succeed"
  assert_contains "$out" "stopped $id" "exit did not report verified stop"
  [ "$(cat "$world/agent")" = dead ] || fail "exit did not stop Pi"
  [ -d "$wt" ] && [ -f "$home/state/$id.meta" ] || fail "exit removed work or endpoint identity"
  out=$(run_control "$rec" "$id" exit) || fail "second exit should be idempotent"
  assert_contains "$out" 'already-stopped' "idempotent exit did not report existing stop"
  pass "exit proves Pi stopped while preserving work and is idempotent"
}

test_exact_target_and_legacy_boundaries() {
  local id=worker-c rec world home wt fb out before
  rec=$(make_world boundaries "$id")
  IFS='|' read -r world home wt fb <<EOF
$rec
EOF
  out=$(run_control "$rec" 'lab:w-worker-c:p1' interrupt 2>&1) && fail "explicit endpoint should not enter task control"
  assert_contains "$out" 'accepts an exact task id only' "explicit target refusal was unclear"
  grep -v '^backend=' "$home/state/$id.meta" > "$home/state/$id.meta.tmp" && mv "$home/state/$id.meta.tmp" "$home/state/$id.meta"
  before=$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')
  : > "$world/log"
  out=$(run_control "$rec" "$id" exit 2>&1) && fail "legacy fieldless identity should refuse"
  assert_contains "$out" 'retired legacy tmux metadata' "legacy refusal did not name preservation"
  [ ! -s "$world/log" ] || fail "legacy refusal reached Herdr"
  [ "$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')" = "$before" ] || fail "legacy refusal rewrote metadata"
  pass "control accepts only exact task ids backed by current Herdr metadata"
}

test_interrupt_preserves_agent_and_endpoint
test_exit_is_verified_and_idempotent
test_exact_target_and_legacy_boundaries
