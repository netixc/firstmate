#!/usr/bin/env bash
# Secondmate routing marker and correlation behavior through Herdr.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-marker-lib.sh
. "$ROOT/bin/fm-marker-lib.sh"
SEND="$ROOT/bin/fm-send.sh"
TMP_ROOT=$(fm_test_tmproot fm-send-secondmate-marker)

make_world() { # <name> <id> <kind>
  local name=$1 id=$2 kind=$3 world home fb
  world=$TMP_ROOT/$name; home=$world/home; fb=$world/fakebin
  mkdir -p "$home/state" "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "pane get")
    workspace=${3%%:*}; task=${workspace#w-}
    printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s:t-%s","workspace_id":"%s"}}}\n' "${3:-}" "$workspace" "$task" "$workspace"
    ;;
  "tab get") printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"%s"}}}\n' "${3:-}" "${3%%:*}" ;;
  "pane send-text") printf '%s' "${4:-}" >> "$FM_SEND_LOG" ;;
  "pane send-keys") : > "$FM_HERDR_STATE" ;;
  "agent get")
    if [ -e "$FM_HERDR_STATE" ]; then status=working; else status=idle; fi
    printf '{"result":{"agent":{"agent_status":"%s","provider":"pi"}}}\n' "$status" ;;
esac
SH
  chmod +x "$fb/herdr"
  fm_write_meta "$home/state/$id.meta" \
    "backend=herdr" "window=lab:w-$id:p1" "endpoint_task_id=$id" \
    "herdr_session=lab" "herdr_workspace_id=w-$id" "herdr_tab_id=w-$id:t-$id" \
    "herdr_pane_id=w-$id:p1" "worktree=/tmp/$id" "project=/tmp/project" \
    "harness=pi" "kind=$kind" "home=/tmp/$id-home"
  printf '%s|%s|%s\n' "$world" "$home" "$fb"
}

run_send() { # <record> <id> <message>
  local rec=$1 id=$2 msg=$3 world home fb
  IFS='|' read -r world home fb <<EOF
$rec
EOF
  : > "$world/send.log"; rm -f "$world/herdr.state"
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" \
    FM_SEND_LOG="$world/send.log" FM_HERDR_STATE="$world/herdr.state" FM_SEND_SETTLE=0 \
    "$SEND" "$id" "$msg" >/dev/null 2>&1
  cat "$world/send.log"
}

test_secondmate_is_marked_and_correlated() {
  local id=domain-a rec sent corr
  rec=$(make_world secondmate "$id" secondmate)
  sent=$(run_send "$rec" "$id" 'audit the queue') || fail "Secondmate send should succeed"
  case "$sent" in "$FM_FROMFIRST_MARK"corr=*) ;; *) fail "Secondmate message lacked routing marker and correlation: $sent" ;; esac
  corr=$(printf '%s' "$sent" | grep -oE 'corr=[a-f0-9]{16}' | head -1)
  [ -n "$corr" ] || fail "Secondmate message lacked a valid correlation"
  assert_contains "$sent" 'audit the queue' "Secondmate payload changed"
  pass "Secondmate sends carry the routing marker and parent correlation"
}

test_crewmate_is_unmarked() {
  local id=worker-a rec sent
  rec=$(make_world worker "$id" ship)
  sent=$(run_send "$rec" "$id" 'continue implementation') || fail "worker send should succeed"
  [ "$sent" = 'continue implementation' ] || fail "ordinary worker send was marked: $sent"
  pass "ordinary worker sends remain unmarked"
}

test_legacy_record_refuses_before_send() {
  local id=legacy rec world home fb out
  rec=$(make_world legacy "$id" secondmate)
  IFS='|' read -r world home fb <<EOF
$rec
EOF
  grep -v '^backend=' "$home/state/$id.meta" > "$home/state/$id.meta.tmp" && mv "$home/state/$id.meta.tmp" "$home/state/$id.meta"
  : > "$world/send.log"
  out=$(PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" \
    FM_SEND_LOG="$world/send.log" FM_HERDR_STATE="$world/herdr.state" \
    "$SEND" "$id" hello 2>&1) && fail "legacy record should refuse delivery"
  assert_contains "$out" 'retired legacy tmux metadata' "legacy refusal did not name preservation"
  [ ! -s "$world/send.log" ] || fail "legacy refusal reached Herdr"
  pass "legacy Secondmate records are preserved rather than reinterpreted"
}

test_secondmate_is_marked_and_correlated
test_crewmate_is_unmarked
test_legacy_record_refuses_before_send
