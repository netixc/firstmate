#!/usr/bin/env bash
# Pi task-extension busy-state wiring test.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-busy-wiring-pi)

make_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  'status --json') printf '{"client":{"version":"0.7.5","protocol":16},"server":{"running":true}}\n' ;;
  'workspace list') printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"}]}}\n' ;;
  'tab list') printf '{"result":{"tabs":[]}}\n' ;;
  'tab create') printf '{"result":{"tab":{"tab_id":"tab1"},"root_pane":{"pane_id":"pane1"}}}\n' ;;
  'pane get') printf '{"result":{"pane":{"pane_id":"pane1","tab_id":"tab1","workspace_id":"w1","foreground_cwd":"%s"}}}\n' "${FM_FAKE_PANE_PATH:?}" ;;
  'pane run'|'pane send-text'|'pane send-keys'|'pane close') ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$fakebin/herdr"
  printf '%s\n' "$fakebin"
}

make_case() {
  local dir="$TMP_ROOT/case" home="$TMP_ROOT/case/home" project="$TMP_ROOT/case/project" worktree="$TMP_ROOT/case/worktree" id=busy-pi fakebin
  mkdir -p "$home/data/$id" "$home/state" "$home/config" "$home/projects"
  printf 'openai-codex/gpt-5.6-luna high\n' > "$home/config/crew-profile"
  printf 'Delivery contract: mode=no-mistakes\nBusy extension test\n' > "$home/data/$id/brief.md"
  fm_git_worktree "$project" "$worktree" busy-pi
  fakebin=$(make_fakebin "$dir/fake")
  printf '%s|%s|%s|%s|%s\n' "$home" "$project" "$worktree" "$fakebin" "$id"
}

run_spawn() {
  local home=$1 worktree=$2 fakebin=$3 id=$4 project=$5
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$worktree" PATH="$fakebin:$PATH" \
    "$ROOT/bin/fm-spawn.sh" "$id" "$project" --mode no-mistakes --yolo off >/dev/null
}

drive_extension() {
  EXT_PATH=$1 MODE=$2 node --input-type=module <<'EOF'
import { pathToFileURL } from "node:url";
const extension = await import(pathToFileURL(process.env.EXT_PATH).href);
const handlers = {};
extension.default({ on: (name, fn) => { handlers[name] = fn; } });
const ctx = { isIdle: () => process.env.MODE !== "continuing" };
if (process.env.MODE === "start") await handlers.agent_start({}, ctx);
if (process.env.MODE === "settle" || process.env.MODE === "continuing") await handlers.agent_settled({}, ctx);
if (process.env.MODE === "turn-end") {
  handlers.turn_end();
  await new Promise((resolve) => setTimeout(resolve, 100));
}
EOF
}

test_generated_pi_extension() {
  local record home project worktree fakebin id state ext out
  record=$(make_case)
  IFS='|' read -r home project worktree fakebin id <<EOF
$record
EOF
  run_spawn "$home" "$worktree" "$fakebin" "$id" "$project"
  state="$home/state"
  ext="$state/$id.pi-ext.ts"
  assert_present "$ext" "Pi spawn did not create task extension"
  out=$(fm_busy_classify herdr endpoint pi "$id" "$state")
  [ "$out" = 'busy fm-spawn' ] || fail "Pi launch busy state wrong: $out"
  rm -f "$state/$id.turn-ended"
  drive_extension "$ext" turn-end
  [ -f "$state/$id.turn-ended" ] || fail "Pi extension did not publish turn-end notification"
  drive_extension "$ext" settle
  out=$(fm_busy_classify herdr endpoint pi "$id" "$state")
  [ "$out" = 'idle pi-ext' ] || fail "Pi settled state wrong: $out"
  drive_extension "$ext" start
  out=$(fm_busy_classify herdr endpoint pi "$id" "$state")
  [ "$out" = 'busy pi-ext' ] || fail "Pi start state wrong: $out"
  drive_extension "$ext" continuing
  out=$(fm_busy_classify herdr endpoint pi "$id" "$state")
  [ "$out" = 'busy pi-ext' ] || fail "continuing Pi settle should remain busy: $out"
  pass "generated Pi extension drives busy, idle, and turn-end state"
}

test_generated_pi_extension
