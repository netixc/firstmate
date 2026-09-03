#!/usr/bin/env bash
# Live steering-inbox doorbell guard against exact Pi in an isolated Herdr lab.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

if [ "${FM_SEND_INBOX_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_SEND_INBOX_LIVE_E2E=1 to run the live steering-inbox doorbell guard"
  exit 0
fi

for tool in herdr jq pi; do
  command -v "$tool" >/dev/null 2>&1 || fail "FM_SEND_INBOX_LIVE_E2E=1 but $tool is not installed"
done
PI_VERSION=$(pi --version 2>/dev/null || true)
[ "$PI_VERSION" = 0.84.4 ] || fail "exact Pi 0.84.4 required, found ${PI_VERSION:-unknown}"

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
[ -x "$LAB_HELPER" ] || fail "the guarded Herdr lab helper is not executable at $LAB_HELPER"
SESSION=$($LAB_HELPER name inbox-doorbell-live)
TMP_ROOT=$(fm_test_tmproot fm-send-inbox-doorbell-live)
ORIGINAL_PATH=$PATH
FAKEBIN="$TMP_ROOT/fakebin"
HOME_DIR="$TMP_ROOT/home"
TIMEOUT=${FM_SEND_INBOX_LIVE_TIMEOUT:-240}
mkdir -p "$FAKEBIN" "$HOME_DIR/state"

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
created=$(lab workspace create --cwd "$ROOT" --label fm-inbox-live --no-focus) \
  || fail "could not create the isolated workspace"
WORKSPACE=$(printf '%s' "$created" | jq -er '.result.workspace.workspace_id') \
  || fail "workspace create omitted its identity"
created=$(lab tab create --workspace "$WORKSPACE" --cwd "$ROOT" --label fm-live-pi --no-focus) \
  || fail "could not create the task tab"
TAB=$(printf '%s' "$created" | jq -er '.result.tab.tab_id') || fail "task tab omitted its identity"
PANE=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id') || fail "task tab omitted its pane"
TARGET="$SESSION:$PANE"
META="$HOME_DIR/state/live-pi.meta"
FM_TEST_HERDR_SESSION=$SESSION FM_TEST_HERDR_WORKSPACE_ID=$WORKSPACE \
  FM_TEST_HERDR_TAB_ID=$TAB FM_TEST_HERDR_PANE_ID=$PANE \
  fm_write_herdr_task_meta "$META" "worktree=$ROOT" "project=$ROOT" "kind=ship" "harness=pi"

export PATH="$FAKEBIN:$ORIGINAL_PATH" FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT"
lab pane run "$PANE" "pi --approve --no-session" >/dev/null || fail "could not launch Pi in the lab pane"
ready=0
for _ in $(seq 1 120); do
  state=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)
  case "$state" in idle|done|blocked) ready=1; break ;; esac
  sleep 0.5
done
[ "$ready" -eq 1 ] || fail "Pi did not become steerable in the isolated Herdr pane"

acted="$TMP_ROOT/acted"
if ! "$ROOT/bin/fm-send.sh" live-pi \
  "Firstmate live check: run exactly this shell command now: touch $acted - then follow the mv instruction in this message. Reply with one short line." \
  >/dev/null 2>&1; then
  fail "fm-send refused the live Herdr steer"
fi
rec="$HOME_DIR/state/live-pi.inbox/001.msg"
handled="$HOME_DIR/state/live-pi.inbox/handled/001.msg"
[ -f "$rec" ] || fail "fm-send left no durable inbox record"

# shellcheck source=bin/fm-task-inbox-lib.sh
. "$ROOT/bin/fm-task-inbox-lib.sh"
for ((i = 0; i < TIMEOUT; i++)); do
  [ -f "$handled" ] && [ -e "$acted" ] && break
  if [ "$i" -eq $((TIMEOUT / 2)) ] && [ -f "$rec" ]; then
    fm_task_inbox_ring herdr "$TARGET" "$rec" fm-live-pi "$META" || true
  fi
  sleep 1
done
[ -f "$handled" ] && [ -e "$acted" ] \
  || fail "doorbell was not acted on and acknowledged within ${TIMEOUT}s"
pass "live Herdr doorbell reached Pi, which acted and acknowledged the record"
