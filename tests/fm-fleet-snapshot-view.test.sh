#!/usr/bin/env bash
# Fleet snapshot/view render current Herdr identity and preserved legacy records.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SNAPSHOT="$ROOT/bin/fm-fleet-snapshot.sh"
VIEW="$ROOT/bin/fm-fleet-view.sh"
TMP_ROOT=$(fm_test_tmproot fm-fleet-snapshot-view)

make_world() {
  local home=$TMP_ROOT/home fb=$TMP_ROOT/fakebin
  mkdir -p "$home/state" "$home/data" "$home/config" "$fb"
  : > "$home/herdr.sock"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
[ -z "${FM_HERDR_LOG:-}" ] || printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "session list") printf '{"sessions":[{"name":"%s","running":true,"socket_path":"%s/herdr.sock"}]}\n' "${HERDR_SESSION:-lab}" "${FM_HOME:-/tmp}" ;;
  "pane get")
    [ "${3:-}" != w-unreachable:p1 ] || exit 1
    workspace=${3%%:*}; task=${workspace#w-}
    printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s:t-%s","workspace_id":"%s"}}}\n' "${3:-}" "$workspace" "$task" "$workspace"
    ;;
  "tab get") printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"%s"}}}\n' "${3:-}" "${3%%:*}" ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"idle","provider":"pi"}}}\n' ;;
  "pane read") printf 'idle Pi pane\n' ;;
esac
SH
  chmod +x "$fb/herdr"
  fm_fake_exit0 "$fb" no-mistakes gh gh-axi curl
  fm_write_meta "$home/state/current.meta" \
    "backend=herdr" "window=lab:w-current:p1" "endpoint_task_id=current" \
    "herdr_session=lab" "herdr_workspace_id=w-current" "herdr_tab_id=w-current:t-current" \
    "herdr_pane_id=w-current:p1" "worktree=/tmp/current" "project=alpha" \
    "harness=pi" "kind=ship" "mode=direct-PR" "yolo=off"
  printf 'working: implementation\n' > "$home/state/current.status"
  fm_write_meta "$home/state/legacy.meta" \
    "window=firstmate:fm-legacy" "worktree=/tmp/legacy" "project=alpha" \
    "harness=pi" "kind=ship" "mode=direct-PR"
  printf 'blocked: manual reconciliation\n' > "$home/state/legacy.status"
  fm_write_meta "$home/state/ambiguous.meta" \
    "backend=herdr" "window=lab:w-ambiguous:p1" "window=lab:w-foreign:p1" \
    "endpoint_task_id=ambiguous" "herdr_session=lab" \
    "herdr_workspace_id=w-ambiguous" "herdr_tab_id=w-ambiguous:t-ambiguous" \
    "herdr_pane_id=w-ambiguous:p1" "worktree=/tmp/ambiguous" "project=alpha" \
    "harness=pi" "kind=secondmate" "mode=direct-PR"
  fm_write_meta "$home/state/mismatch.meta" \
    "backend=herdr" "window=lab:w-mismatch:p1" "endpoint_task_id=mismatch" \
    "herdr_session=lab" "herdr_workspace_id=w-mismatch" "herdr_tab_id=w-mismatch:t-recorded" \
    "herdr_pane_id=w-mismatch:p1" "worktree=/tmp/mismatch" "project=alpha" \
    "harness=pi" "kind=secondmate" "mode=direct-PR"
  fm_write_meta "$home/state/unreachable.meta" \
    "backend=herdr" "window=lab:w-unreachable:p1" "endpoint_task_id=unreachable" \
    "herdr_session=lab" "herdr_workspace_id=w-unreachable" "herdr_tab_id=w-unreachable:t-unreachable" \
    "herdr_pane_id=w-unreachable:p1" "worktree=/tmp/unreachable" "project=alpha" \
    "harness=pi" "kind=secondmate" "mode=direct-PR"
  printf '%s|%s\n' "$home" "$fb"
}

run_snapshot() { # <home> <fakebin>
  PATH="$2:$PATH" FM_HOME="$1" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$1/state" FM_DATA_OVERRIDE="$1/data" \
    FM_CONFIG_OVERRIDE="$1/config" "$SNAPSHOT" --json
}

test_snapshot_session_contract() {
  local rec home fb json log
  rec=$(make_world); IFS='|' read -r home fb <<EOF
$rec
EOF
  log=$home/herdr.log
  json=$(FM_HERDR_LOG="$log" run_snapshot "$home" "$fb") || fail "fleet snapshot failed"
  printf '%s' "$json" | jq -e '
    (.tasks | length) == 5
    and (.tasks[] | select(.id=="current") | .session_path) == "herdr"
    and (.tasks[] | select(.id=="current") | .endpoint.exists) == true
    and (.tasks[] | select(.id=="legacy") | .session_path) == "retired-tmux"
    and (.tasks[] | select(.id=="legacy") | .endpoint.exists) == null
    and (.tasks[] | select(.id=="ambiguous") | .session_path) == "herdr"
    and (.tasks[] | select(.id=="ambiguous") | .endpoint.exists) == null
    and (.tasks[] | select(.id=="mismatch") | .session_path) == "herdr"
    and (.tasks[] | select(.id=="mismatch") | .endpoint.exists) == null
    and (.tasks[] | select(.id=="mismatch") | .endpoint.agent_alive) == "unknown"
    and (.tasks[] | select(.id=="unreachable") | .endpoint.exists) == null
    and (.tasks[] | select(.id=="unreachable") | .endpoint.agent_alive) == "unknown"
    and ([.tasks[] | has("backend")] | any | not)
  ' >/dev/null || fail "snapshot did not expose the Herdr-only session contract: $json"
  if grep -F 'w-ambiguous:p1' "$log" >/dev/null \
    || grep -F 'w-foreign:p1' "$log" >/dev/null; then
    fail "snapshot probed an ambiguous endpoint identity"
  fi
  pass "fleet snapshot reports current Herdr and preserved legacy identity without a provider field"
}

test_view_renders_session_column() {
  local rec home fb out
  rec=$(make_world); IFS='|' read -r home fb <<EOF
$rec
EOF
  out=$(PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$VIEW") || fail "fleet view failed"
  assert_contains "$out" '| Session |' "view did not rename the provider column"
  assert_contains "$out" '| current |' "current task missing from view"
  assert_contains "$out" '| herdr |' "current Herdr session missing from view"
  assert_contains "$out" '| retired-tmux |' "legacy preservation missing from view"
  pass "fleet view renders the session path and legacy preservation class"
}

test_snapshot_session_contract
test_view_renders_session_column
