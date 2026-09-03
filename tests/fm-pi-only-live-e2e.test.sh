#!/usr/bin/env bash
# Opt-in real Pi proof for supervision and lifecycle control through Herdr.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

if [ "${FM_PI_ONLY_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_PI_ONLY_LIVE_E2E=1 to run the real plain Pi integration"
  exit 0
fi
for tool in herdr jq pi git; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
PI_BIN=$(command -v pi)
PI_VERSION=$($PI_BIN --version 2>/dev/null || true)
[ "$PI_VERSION" = 0.84.4 ] || fail "real Pi 0.84.4 required, found ${PI_VERSION:-unknown}"

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
SESSION=$($LAB_HELPER name pi-control-live)
TMP_ROOT=$(fm_test_tmproot fm-pi-only-live)
ORIGINAL_PATH=$PATH
FAKEBIN="$TMP_ROOT/fakebin"
HOME_DIR="$TMP_ROOT/home"
PI_AGENT_DIR="$TMP_ROOT/pi-agent"
WORKTREE="$TMP_ROOT/worktree"
mkdir -p "$FAKEBIN" "$HOME_DIR/state" "$HOME_DIR/data/control" "$PI_AGENT_DIR"
source_pi_dir=${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}
if [ -f "$source_pi_dir/auth.json" ]; then
  cp "$source_pi_dir/auth.json" "$PI_AGENT_DIR/auth.json"
fi

cleanup() {
  local rc=$?
  trap - EXIT
  PATH="$ORIGINAL_PATH" "$LAB_HELPER" teardown "$SESSION" >/dev/null 2>&1 || rc=1
  git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT

git -C "$ROOT" worktree add --detach "$WORKTREE" HEAD >/dev/null \
  || fail "could not create the isolated lifecycle worktree"
printf 'Real Pi lifecycle control validation.\n' > "$HOME_DIR/data/control/brief.md"

cat > "$FAKEBIN/herdr" <<EOF
#!/usr/bin/env bash
set -u
args=("\$@")
n=\${#args[@]}
if [ "\$n" -eq 2 ] && [ "\${args[0]}" = status ] && [ "\${args[1]}" = --json ]; then
  exec env PATH="$ORIGINAL_PATH" herdr status --json
fi
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "$SESSION" ] || exit 97
  args=("\${args[@]:0:\$((n-2))}")
else
  exit 98
fi
exec env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"
"$LAB_HELPER" provision "$SESSION" >/dev/null || fail "could not provision the isolated Herdr lab"
lab() { env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "$@"; }
created=$(lab workspace create --cwd "$WORKTREE" --label fm-pi-control --no-focus) \
  || fail "could not create the lifecycle workspace"
WORKSPACE=$(printf '%s' "$created" | jq -er '.result.workspace.workspace_id') \
  || fail "workspace create omitted its identity"
created=$(lab tab create --workspace "$WORKSPACE" --cwd "$WORKTREE" --label fm-control --no-focus) \
  || fail "could not create the lifecycle tab"
TAB=$(printf '%s' "$created" | jq -er '.result.tab.tab_id') || fail "lifecycle tab omitted its identity"
PANE=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id') || fail "lifecycle tab omitted its pane"
META="$HOME_DIR/state/control.meta"
FM_TEST_HERDR_SESSION=$SESSION FM_TEST_HERDR_WORKSPACE_ID=$WORKSPACE \
  FM_TEST_HERDR_TAB_ID=$TAB FM_TEST_HERDR_PANE_ID=$PANE \
  fm_write_herdr_task_meta "$META" "worktree=$WORKTREE" "project=$ROOT" "kind=ship" \
    "harness=pi" "mode=no-mistakes" "yolo=off" "model=openai-codex/gpt-5.6-sol" "effort=low"

export PATH="$FAKEBIN:$ORIGINAL_PATH" FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
  FM_BACKEND=herdr HERDR_SESSION="$SESSION" HERDR_WORKSPACE_ID="$WORKSPACE" \
  HERDR_TAB_ID="$TAB" HERDR_PANE_ID="$PANE" PI_CODING_AGENT_DIR="$PI_AGENT_DIR" \
  FM_GATE_REFUSE_BYPASS=1

out=$(cd "$ROOT" && "$PI_BIN" --print --approve --no-session --no-context-files --no-extensions \
  -e "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
  -e "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" \
  --model openai-codex/gpt-5.6-sol --thinking low \
  "Use the bash tool to run PI_CODING_AGENT=true bin/fm-harness.sh. Reply with exactly the command's one-word stdout and nothing else.")
[ "$out" = pi ] || fail "real Pi returned $out instead of its plain-Pi identity"
pass "real Pi supervision extensions preserve plain-Pi identity"

printf -v pane_command \
  'env PATH=%q FM_HOME=%q FM_ROOT_OVERRIDE=%q FM_STATE_OVERRIDE=%q FM_DATA_OVERRIDE=%q FM_BACKEND=herdr HERDR_SESSION=%q HERDR_WORKSPACE_ID=%q HERDR_TAB_ID=%q HERDR_PANE_ID=%q PI_CODING_AGENT_DIR=%q %q --no-session --no-extensions -e %q -e %q' \
  "$PATH" "$FM_HOME" "$FM_ROOT_OVERRIDE" "$FM_STATE_OVERRIDE" "$FM_DATA_OVERRIDE" \
  "$HERDR_SESSION" "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID" \
  "$PI_CODING_AGENT_DIR" "$PI_BIN" "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
  "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts"
lab pane run "$PANE" "$pane_command" >/dev/null || fail "could not launch Pi in the lifecycle pane"
interrupted=0
for _ in $(seq 1 100); do
  if "$ROOT/bin/fm-control.sh" control interrupt >/dev/null 2>&1; then
    interrupted=1
    break
  fi
  sleep 0.1
done
[ "$interrupted" = 1 ] || fail "real Pi interrupt control failed"
pass "real Pi interrupt lifecycle control succeeds through Herdr"

FM_SPAWN_NO_GUARD=1 "$ROOT/bin/fm-control.sh" control relaunch --harness pi \
  --model openai-codex/gpt-5.6-sol --effort low --note 'Verify Pi transactional relaunch.' >/dev/null \
  || fail "real Pi transactional relaunch failed"
# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
[ "$(fm_meta_get "$META" harness)" = pi ] || fail "Pi relaunch lost harness metadata"
[ "$(fm_meta_get "$META" model)" = openai-codex/gpt-5.6-sol ] || fail "Pi relaunch lost model metadata"
[ "$(fm_meta_get "$META" effort)" = low ] || fail "Pi relaunch lost effort metadata"
fm_backend_validate_active_task_endpoint "$META" control \
  || fail "Pi relaunch did not publish an exact active Herdr endpoint"
pass "real Pi transactional relaunch preserves profile and exact Herdr identity"

"$ROOT/bin/fm-control.sh" control exit >/dev/null || fail "real Pi replacement exit failed"
pass "real Pi replacement exit lifecycle control succeeds through Herdr"
