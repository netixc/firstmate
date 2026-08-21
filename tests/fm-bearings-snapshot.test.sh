#!/usr/bin/env bash
# Bearings projection over the Herdr-only fleet snapshot contract.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BEARINGS="$ROOT/bin/fm-bearings-snapshot.sh"
TMP_ROOT=$(fm_test_tmproot fm-bearings)

make_world() {
  local home=$TMP_ROOT/home fb=$TMP_ROOT/fakebin gen
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
  printf 'blocked [key=choice]: choose the release window\n' > "$home/state/current.status"
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$home/state" current)
  "$ROOT/bin/fm-busy-event.sh" apply "$home/state" current idle --gen "$gen" --source pi-ext --event stop
  fm_write_meta "$home/state/legacy.meta" \
    "window=firstmate:fm-legacy" "worktree=/tmp/legacy" "project=alpha" \
    "harness=pi" "kind=ship" "mode=direct-PR"
  printf 'working: old record needs reconciliation\n' > "$home/state/legacy.status"
  printf '%s|%s\n' "$home" "$fb"
}

run_bearings() { # <home> <fakebin> <args...>
  local home=$1 fb=$2
  shift 2
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" FM_BEARINGS_NOW=2026-08-21T00:00:00Z \
    "$BEARINGS" --json "$@"
}

test_projection_uses_session_path() {
  local rec home fb json
  rec=$(make_world); IFS='|' read -r home fb <<EOF
$rec
EOF
  json=$(run_bearings "$home" "$fb" --fields endpoints --all-unhealthy) || fail "Bearings JSON failed"
  printf '%s' "$json" | jq -e '
    (.in_flight | any(.id=="current"))
    and (.endpoints | any(.id=="current" and .session_path=="herdr" and .exists==true))
    and (.endpoints | any(.id=="legacy" and .session_path=="retired-tmux" and .exists==null))
    and ([.endpoints[] | has("backend")] | any | not)
  ' >/dev/null || fail "Bearings did not preserve the Herdr session contract: $json"
  pass "Bearings projects current Herdr identity and legacy preservation without provider framing"
}

test_json_output_is_bounded_and_structured() {
  local rec home fb out
  rec=$(make_world); IFS='|' read -r home fb <<EOF
$rec
EOF
  out=$(run_bearings "$home" "$fb") || fail "Bearings JSON failed"
  printf '%s' "$out" | jq -e '.schema=="fm-bearings.v1" and (.in_flight|length)==2 and (.omitted|length)>0' >/dev/null \
    || fail "Bearings output lost its bounded schema"
  pass "Bearings retains bounded structured output over the Herdr snapshot"
}

test_projection_uses_session_path
test_json_output_is_bounded_and_structured
