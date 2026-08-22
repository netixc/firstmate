#!/usr/bin/env bash
# Per-task GOTMPDIR cleanup after exact Herdr endpoint retirement.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-gotmp)

make_world() { # <name> <id> [tasktmp]
  local name=$1 id=$2 tasktmp=${3:-} world home fb
  world=$TMP_ROOT/$name; home=$world/home; fb=$world/fakebin
  mkdir -p "$home/state" "$home/data" "$home/config" "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "session list") printf '{"sessions":[{"name":"lab","running":true,"socket_path":"%s/herdr.sock"}]}\n' "${FM_HOME:-/tmp}" ;;
  "pane get") printf '{"error":{"code":"pane_not_found"}}\n' ;;
  *) printf '{"result":{}}\n' ;;
esac
SH
  chmod +x "$fb/herdr"
  fm_fake_exit0 "$fb" treehouse no-mistakes gh gh-axi
  fm_write_meta "$home/state/$id.meta" \
    "backend=herdr" "window=lab:w-$id:p1" "endpoint_task_id=$id" \
    "herdr_session=lab" "herdr_workspace_id=w-$id" "herdr_tab_id=w-$id:t-$id" \
    "herdr_pane_id=w-$id:p1" "worktree=$world/missing-wt" "project=$world/missing-project" \
    "harness=pi" "kind=ship" "mode=local-only" "yolo=off"
  [ -z "$tasktmp" ] || printf 'tasktmp=%s\n' "$tasktmp" >> "$home/state/$id.meta"
  printf '%s|%s|%s\n' "$world" "$home" "$fb"
}

run_teardown() { # <record> <id>
  local rec=$1 id=$2 world home fb
  IFS='|' read -r world home fb <<EOF
$rec
EOF
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$TEARDOWN" "$id"
}

test_tasktmp_removed() {
  local id=gotmp-a tasktmp=$TMP_ROOT/tasktmp-a rec
  mkdir -p "$tasktmp/gotmp"
  printf artifact > "$tasktmp/gotmp/build"
  rec=$(make_world present "$id" "$tasktmp")
  run_teardown "$rec" "$id" >/dev/null 2>&1 || fail "cleanup with valid tasktmp failed"
  [ ! -e "$tasktmp" ] || fail "tasktmp directory survived cleanup"
  pass "cleanup removes the exact tasktmp root recorded in metadata"
}

test_absent_tasktmp_is_noop() {
  local id=gotmp-b sentinel=$TMP_ROOT/unrelated rec
  mkdir -p "$sentinel"; printf keep > "$sentinel/value"
  rec=$(make_world absent "$id")
  run_teardown "$rec" "$id" >/dev/null 2>&1 || fail "cleanup without tasktmp failed"
  [ "$(cat "$sentinel/value")" = keep ] || fail "absent tasktmp cleanup touched unrelated files"
  pass "older current Herdr metadata without tasktmp cleans up safely"
}

test_tasktmp_removed
test_absent_tasktmp_is_noop
