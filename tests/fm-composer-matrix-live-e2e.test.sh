#!/usr/bin/env bash
# Live Pi composer guard in an isolated non-default Herdr session.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

if [ "${FM_COMPOSER_MATRIX_LIVE:-0}" != 1 ]; then
  echo "skip: set FM_COMPOSER_MATRIX_LIVE=1 to run the live composer-matrix guard"
  exit 0
fi
for tool in herdr jq pi; do
  command -v "$tool" >/dev/null 2>&1 || fail "FM_COMPOSER_MATRIX_LIVE=1 but $tool is not installed"
done
PI_BIN=$(command -v pi)
PI_VERSION=$($PI_BIN --version 2>/dev/null || true)
[ "$PI_VERSION" = 0.84.4 ] || fail "exact Pi 0.84.4 required, found ${PI_VERSION:-unknown}"

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
SESSION=$($LAB_HELPER name composer-live)
TMP_ROOT=$(fm_test_tmproot fm-composer-live)
ORIGINAL_PATH=$PATH
FAKEBIN="$TMP_ROOT/fakebin"
HOME_DIR="$TMP_ROOT/home"
PI_AGENT_DIR="$TMP_ROOT/pi-agent"
mkdir -p "$FAKEBIN" "$HOME_DIR/state" "$HOME_DIR/data" "$PI_AGENT_DIR"
source_pi_dir=${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}
if [ -f "$source_pi_dir/auth.json" ]; then
  cp "$source_pi_dir/auth.json" "$PI_AGENT_DIR/auth.json"
fi
cleanup() {
  local rc=$?
  trap - EXIT
  PATH="$ORIGINAL_PATH" "$LAB_HELPER" teardown "$SESSION" >/dev/null 2>&1 || rc=1
  rm -rf "$TMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT

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
created=$(lab workspace create --cwd "$ROOT" --label fm-composer-live --no-focus) \
  || fail "could not create the composer workspace"
WORKSPACE=$(printf '%s' "$created" | jq -er '.result.workspace.workspace_id') \
  || fail "workspace create omitted its identity"
created=$(lab tab create --workspace "$WORKSPACE" --cwd "$ROOT" --label fm-live-pi --no-focus) \
  || fail "could not create the Pi task tab"
PI_TAB=$(printf '%s' "$created" | jq -er '.result.tab.tab_id') || fail "Pi tab omitted its identity"
PI_PANE=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id') || fail "Pi tab omitted its pane"
PI_META="$HOME_DIR/state/live-pi.meta"
FM_TEST_HERDR_SESSION=$SESSION FM_TEST_HERDR_WORKSPACE_ID=$WORKSPACE \
  FM_TEST_HERDR_TAB_ID=$PI_TAB FM_TEST_HERDR_PANE_ID=$PI_PANE \
  fm_write_herdr_task_meta "$PI_META" "worktree=$ROOT" "project=$ROOT" "kind=ship" "harness=pi"

export PATH="$FAKEBIN:$ORIGINAL_PATH" FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
  FM_BACKEND=herdr HERDR_SESSION="$SESSION" HERDR_WORKSPACE_ID="$WORKSPACE" \
  HERDR_TAB_ID="$PI_TAB" HERDR_PANE_ID="$PI_PANE" PI_CODING_AGENT_DIR="$PI_AGENT_DIR"
# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
printf -v pane_command \
  'env PATH=%q FM_HOME=%q FM_ROOT_OVERRIDE=%q FM_STATE_OVERRIDE=%q FM_DATA_OVERRIDE=%q FM_BACKEND=herdr HERDR_SESSION=%q HERDR_WORKSPACE_ID=%q HERDR_TAB_ID=%q HERDR_PANE_ID=%q PI_CODING_AGENT_DIR=%q %q --approve --no-session' \
  "$PATH" "$FM_HOME" "$FM_ROOT_OVERRIDE" "$FM_STATE_OVERRIDE" "$FM_DATA_OVERRIDE" \
  "$HERDR_SESSION" "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID" \
  "$PI_CODING_AGENT_DIR" "$PI_BIN"
lab pane run "$PI_PANE" "$pane_command" >/dev/null || fail "could not launch Pi"
verdict=unknown
for _ in $(seq 1 "${FM_COMPOSER_MATRIX_LIVE_POLLS:-90}"); do
  verdict=$(fm_backend_composer_state herdr "$SESSION:$PI_PANE" fm-live-pi "$PI_META")
  [ "$verdict" = empty ] && break
  sleep 0.5
done
[ "$verdict" = empty ] || fail "Pi idle composer never classified empty (last verdict: $verdict)"
pass "Pi $PI_VERSION idle composer classifies empty through Herdr"

created=$(lab tab create --workspace "$WORKSPACE" --cwd "$ROOT" --label fm-strict-blank --no-focus) \
  || fail "could not create the strict blank task tab"
BLANK_TAB=$(printf '%s' "$created" | jq -er '.result.tab.tab_id') || fail "blank tab omitted its identity"
BLANK_PANE=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id') || fail "blank tab omitted its pane"
BLANK_META="$HOME_DIR/state/strict-blank.meta"
FM_TEST_HERDR_SESSION=$SESSION FM_TEST_HERDR_WORKSPACE_ID=$WORKSPACE \
  FM_TEST_HERDR_TAB_ID=$BLANK_TAB FM_TEST_HERDR_PANE_ID=$BLANK_PANE \
  fm_write_herdr_task_meta "$BLANK_META" "worktree=$ROOT" "project=$ROOT" "kind=ship" "harness=pi"
lab pane run "$BLANK_PANE" "bash -c 'printf \"────────────────────────\\n\\n\"; printf \"\\033[A\"; exec sleep 300'" >/dev/null \
  || fail "could not stage the strict blank shell pane"
sleep 1
verdict=$(fm_backend_composer_state herdr "$SESSION:$BLANK_PANE" fm-strict-blank "$BLANK_META")
[ "$verdict" = unknown ] || fail "blank unidentified shell row classified $verdict, expected unknown"
pass "strict blank shell posture remains unknown through Herdr"
