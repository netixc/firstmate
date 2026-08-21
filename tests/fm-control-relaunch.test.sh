#!/usr/bin/env bash
# Transactional Pi relaunch through the sole Herdr process-control seam.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL="$ROOT/bin/fm-control.sh"
TMP_ROOT=$(fm_test_tmproot fm-control-relaunch)

make_world() { # <name> <id>
  local name=$1 id=$2 world home project wt fb
  world=$TMP_ROOT/$name
  home=$world/home
  project=$world/project
  wt=$world/wt
  fb=$world/fakebin
  mkdir -p "$home/state" "$home/data/$id" "$home/config" "$fb"
  fm_git_worktree "$project" "$wt" "fm/$id"
  printf 'task instructions\n' > "$home/data/$id/brief.md"
  printf alive > "$world/agent"
  : > "$world/herdr.log"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_CONTROL_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "pane get")
    workspace=${3%%:*}; task=${workspace#w-}
    printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s:t-%s","workspace_id":"%s","foreground_cwd":"%s"}}}\n' "${3:-}" "$workspace" "$task" "$workspace" "$FM_CONTROL_WT"
    ;;
  "tab get") printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"%s"}}}\n' "${3:-}" "${3%%:*}" ;;
  "pane send-text") printf '%s' "${4:-}" > "$FM_CONTROL_LAST_TEXT" ;;
  "pane send-keys")
    if grep -Fxq /quit "$FM_CONTROL_LAST_TEXT" 2>/dev/null; then printf dead > "$FM_CONTROL_AGENT"
    else printf alive > "$FM_CONTROL_AGENT"; fi
    ;;
  "pane run") : ;;
  "pane read") printf '╭────╮\n│    │\n╰────╯\n' ;;
  "agent get")
    if [ "$(cat "$FM_CONTROL_AGENT")" = alive ]; then
      printf '{"result":{"agent":{"agent_status":"idle","provider":"pi"}}}\n'
    else
      printf '{"error":{"code":"agent_not_found"}}\n'
    fi
    ;;
esac
SH
  cat > "$fb/pi" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != --help ] || printf '%s\n' 'Pi options: --tui-mode --model --thinking'
exit 0
SH
  chmod +x "$fb/herdr" "$fb/pi"
  fm_write_meta "$home/state/$id.meta" \
    "backend=herdr" "window=lab:w-$id:p1" "endpoint_task_id=$id" \
    "herdr_session=lab" "herdr_workspace_id=w-$id" "herdr_tab_id=w-$id:t-$id" \
    "herdr_pane_id=w-$id:p1" "worktree=$wt" "project=$project" \
    "harness=pi" "kind=ship" "mode=no-mistakes" "yolo=off" \
    "model=default" "effort=default" "spawn_gen=initial" "tasktmp=$world/tasktmp"
  printf '%s|%s|%s|%s|%s\n' "$world" "$home" "$project" "$wt" "$fb"
}

run_control() { # <record> <id> <verb args...>
  local rec=$1 id=$2 world home project wt fb
  shift 2
  IFS='|' read -r world home project wt fb <<EOF
$rec
EOF
  env -u TMUX -u TMUX_PANE -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH \
    PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    HERDR_SESSION=lab FM_CONTROL_AGENT="$world/agent" \
    FM_CONTROL_HERDR_LOG="$world/herdr.log" FM_CONTROL_LAST_TEXT="$world/last-text" \
    FM_CONTROL_WT="$wt" FM_CONTROL_POLL=0.01 FM_CONTROL_EXIT_WAIT=1 FM_CONTROL_LAUNCH_WAIT=1 \
    "$CONTROL" "$id" "$@"
}

test_relaunch_preserves_identity_and_work() {
  local id=relaunch-a rec world home project wt fb out before after
  rec=$(make_world relaunch-a "$id")
  IFS='|' read -r world home project wt fb <<EOF
$rec
EOF
  printf 'local change\n' > "$wt/local.txt"
  before=$(git -C "$wt" status --porcelain)
  out=$(run_control "$rec" "$id" relaunch --note 'continue after controlled restart') \
    || fail "same-Pi relaunch should succeed"
  assert_contains "$out" "relaunched $id" "relaunch did not report completion"
  [ "$(cat "$world/agent")" = alive ] || fail "replacement Pi was not alive"
  after=$(git -C "$wt" status --porcelain)
  [ "$after" = "$before" ] || fail "relaunch changed uncommitted work"
  assert_grep 'window=lab:w-relaunch-a:p1' "$home/state/$id.meta" "relaunch changed exact endpoint identity"
  assert_grep 'continue after controlled restart' "$home/data/$id/brief.md" "replacement instructions lost the progress note"
  assert_grep 'phase=complete' "$home/state/$id.control-relaunch" "successful relaunch did not complete its transaction journal"
  pass "Pi relaunch preserves exact Herdr endpoint, worktree, and progress note"
}

test_relaunch_requires_note_before_control() {
  local id=relaunch-note rec world home project wt fb before out
  rec=$(make_world relaunch-note "$id")
  IFS='|' read -r world home project wt fb <<EOF
$rec
EOF
  before=$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')
  out=$(run_control "$rec" "$id" relaunch 2>&1) && fail "ship relaunch without note should refuse"
  assert_contains "$out" 'requires --note' "note refusal was not actionable"
  [ "$(cat "$world/agent")" = alive ] || fail "note refusal stopped Pi"
  [ "$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')" = "$before" ] || fail "note refusal rewrote metadata"
  pass "relaunch refuses before lifecycle action when the replacement lacks a note"
}

test_legacy_metadata_is_preserved() {
  local id=legacy rec world home project wt fb out before
  rec=$(make_world legacy "$id")
  IFS='|' read -r world home project wt fb <<EOF
$rec
EOF
  grep -v '^backend=' "$home/state/$id.meta" > "$home/state/$id.meta.tmp" && mv "$home/state/$id.meta.tmp" "$home/state/$id.meta"
  before=$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')
  : > "$world/herdr.log"
  out=$(run_control "$rec" "$id" relaunch --note continue 2>&1) && fail "fieldless legacy metadata should refuse relaunch"
  assert_contains "$out" 'retired legacy tmux metadata' "legacy refusal did not name preservation"
  [ ! -s "$world/herdr.log" ] || fail "legacy refusal reached Herdr"
  [ "$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')" = "$before" ] || fail "legacy refusal rewrote metadata"
  pass "legacy metadata remains untouched for manual reconciliation"
}

test_relaunch_preserves_identity_and_work
test_relaunch_requires_note_before_control
test_legacy_metadata_is_preserved
