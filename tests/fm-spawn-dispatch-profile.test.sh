#!/usr/bin/env bash
# Pi-only spawn and dispatch executable-interface tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-pi)

make_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  'status --json') printf '{"client":{"version":"0.7.5","protocol":16},"server":{"running":true}}\n' ;;
  'workspace list') printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"}]}}\n' ;;
  'tab list') printf '{"result":{"tabs":[]}}\n' ;;
  'tab create') printf '{"result":{"tab":{"tab_id":"tab1"},"root_pane":{"pane_id":"pane1"}}}\n' ;;
  'pane get') printf '{"result":{"pane":{"pane_id":"pane1","tab_id":"tab1","workspace_id":"w1","foreground_cwd":"%s"}}}\n' "${FM_FAKE_PANE_PATH:?}" ;;
  'pane run'|'pane send-text')
    [ -z "${FM_FAKE_LAUNCH_LOG:-}" ] || printf '%s\n' "${4:-}" >> "$FM_FAKE_LAUNCH_LOG"
    ;;
  'pane send-keys'|'pane close') ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$fakebin/herdr"
  printf '%s\n' "$fakebin"
}

make_case() {
  local name=$1 id=$2 dir home project worktree fakebin
  dir="$TMP_ROOT/$name"
  home="$dir/home"
  project="$dir/project"
  worktree="$dir/worktree"
  mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config"
  printf 'openai-codex/gpt-5.6-luna high\n' > "$home/config/crew-profile"
  printf 'Delivery contract: mode=no-mistakes\nPi launch brief\n' > "$home/data/$id/brief.md"
  fm_git_worktree "$project" "$worktree" "spawn-$name"
  fakebin=$(make_fakebin "$dir/fake")
  printf '%s|%s|%s|%s|%s|%s\n' "$home" "$project" "$worktree" "$fakebin" "$dir/launch.log" "$id"
}

run_spawn() {
  local home=$1 worktree=$2 fakebin=$3 log=$4
  shift 4
  : > "$log"
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$worktree" FM_FAKE_LAUNCH_LOG="$log" \
    PATH="$fakebin:$PATH" "$SPAWN" "$@" 2>&1
}

expect_fail() {
  local want=$1
  shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "expected command to fail: $*"
  printf '%s' "$out" | grep -Fq -- "$want" || fail "failure did not contain '$want': $out"
}

test_pi_profile_launch() {
  local record home project worktree fakebin log id out launch
  record=$(make_case profile-launch launch-pi)
  IFS='|' read -r home project worktree fakebin log id <<EOF
$record
EOF
  out=$(run_spawn "$home" "$worktree" "$fakebin" "$log" "$id" "$project" --mode no-mistakes --yolo off)
  printf '%s' "$out" | grep -Fq "spawned $id runtime=pi" || fail "Pi launch did not report fixed runtime: $out"
  assert_grep 'harness=pi' "$home/state/$id.meta" "spawn metadata did not record Pi"
  assert_grep 'model=openai-codex/gpt-5.6-luna' "$home/state/$id.meta" "spawn metadata omitted Pi model"
  assert_grep 'effort=high' "$home/state/$id.meta" "spawn metadata omitted Pi thinking"
  launch=$(cat "$log")
  printf '%s' "$launch" | grep -Fq "pi --model 'openai-codex/gpt-5.6-luna' --thinking 'high'" \
    || fail "launch command did not select Pi model and thinking: $launch"
  pass "ordinary worker launch is fixed to Pi with profile model and thinking"
}

test_dispatch_requires_explicit_pi_model() {
  local record home project worktree fakebin log id
  record=$(make_case dispatch-required dispatch-pi)
  IFS='|' read -r home project worktree fakebin log id <<EOF
$record
EOF
  cat > "$home/config/crew-dispatch.json" <<'JSON'
{"rules":[{"when":"test","use":{"model":"openai-codex/gpt-5.6-luna","effort":"medium"}}]}
JSON
  expect_fail 'pass the selected Pi --model' run_spawn "$home" "$worktree" "$fakebin" "$log" "$id" "$project" --mode no-mistakes --yolo off
  run_spawn "$home" "$worktree" "$fakebin" "$log" "$id" "$project" --model xai/grok-4.1 --effort medium --mode no-mistakes --yolo off >/dev/null \
    || fail "selected Pi dispatch model was rejected"
  assert_grep 'model=xai/grok-4.1' "$home/state/$id.meta" "selected dispatch model was not recorded"
  pass "active dispatch requires an explicit Pi model and launches it"
}

test_runtime_override_rejected() {
  local record home project worktree fakebin log id
  record=$(make_case runtime-override override-pi)
  IFS='|' read -r home project worktree fakebin log id <<EOF
$record
EOF
  expect_fail 'unknown option' run_spawn "$home" "$worktree" "$fakebin" "$log" --unsupported-runtime "$id" "$project" --mode no-mistakes --yolo off
  pass "spawn rejects a runtime-choice override"
}

test_pi_profile_launch
test_dispatch_requires_explicit_pi_model
test_runtime_override_rejected
