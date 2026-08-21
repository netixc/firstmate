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
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "pane get") printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "${3:-}" ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"idle","provider":"pi"}}}\n' ;;
  "pane read") printf 'idle Pi pane\n' ;;
esac
SH
  chmod +x "$fb/herdr"
  fm_fake_exit0 "$fb" no-mistakes gh gh-axi curl
  fm_write_meta "$home/state/current.meta" \
    "backend=herdr" "window=lab:w-current:p1" "endpoint_task_id=current" \
    "herdr_session=lab" "herdr_workspace_id=w-current" "herdr_tab_id=t-current" \
    "herdr_pane_id=w-current:p1" "worktree=/tmp/current" "project=alpha" \
    "harness=pi" "kind=ship" "mode=direct-PR" "yolo=off"
  printf 'working: implementation\n' > "$home/state/current.status"
  fm_write_meta "$home/state/legacy.meta" \
    "window=firstmate:fm-legacy" "worktree=/tmp/legacy" "project=alpha" \
    "harness=pi" "kind=ship" "mode=direct-PR"
  printf 'blocked: manual reconciliation\n' > "$home/state/legacy.status"
  printf '%s|%s\n' "$home" "$fb"
}

run_snapshot() { # <home> <fakebin>
  PATH="$2:$PATH" FM_HOME="$1" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$1/state" FM_DATA_OVERRIDE="$1/data" \
    FM_CONFIG_OVERRIDE="$1/config" "$SNAPSHOT" --json
}

test_snapshot_session_contract() {
  local rec home fb json
  rec=$(make_world); IFS='|' read -r home fb <<EOF
$rec
EOF
  json=$(run_snapshot "$home" "$fb") || fail "fleet snapshot failed"
  printf '%s' "$json" | jq -e '
    (.tasks | length) == 2
    and (.tasks[] | select(.id=="current") | .session_path) == "herdr"
    and (.tasks[] | select(.id=="current") | .endpoint.exists) == true
    and (.tasks[] | select(.id=="legacy") | .session_path) == "retired-tmux"
    and (.tasks[] | select(.id=="legacy") | .endpoint.exists) == null
    and ([.tasks[] | has("backend")] | any | not)
  ' >/dev/null || fail "snapshot did not expose the Herdr-only session contract: $json"
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
