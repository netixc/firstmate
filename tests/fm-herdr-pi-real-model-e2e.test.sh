#!/usr/bin/env bash
# Opt-in real-model Pi 0.84.4 proof inside an isolated named Herdr lab.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "${FM_HERDR_PI_REAL_MODEL_E2E:-0}" != 1 ]; then
  echo "skip: set FM_HERDR_PI_REAL_MODEL_E2E=1 to run the real-model Pi/Herdr guard"
  exit 0
fi

for tool in herdr jq pi; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
PI_BIN=$(command -v pi)
PI_VERSION=$("$PI_BIN" --version 2>/dev/null || true)
[ "$PI_VERSION" = 0.84.4 ] || fail "real Pi 0.84.4 required, found ${PI_VERSION:-unknown}"
PANE_PATH="$(dirname "$PI_BIN"):$(dirname "$(command -v herdr)"):/usr/bin:/bin"

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
SESSION=$($LAB_HELPER name fm-herdr-pi-real-model-e2e)
TMP_ROOT=$(fm_test_tmproot fm-herdr-pi-real-model-e2e)
MODEL=${FM_HERDR_PI_REAL_MODEL:-openai-codex/gpt-5.6-sol}
TOKEN=FM_HERDR_ONLY_REAL_MODEL_OK
STEER_TOKEN=FM_HERDR_ONLY_STEERING_OK
PANE=
TAB=
WORKSPACE=
HOME_DIR="$TMP_ROOT/home"
PI_AGENT_DIR="$TMP_ROOT/pi-agent"
mkdir -p "$HOME_DIR/state" "$PI_AGENT_DIR"
source_pi_dir=${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}
if [ -f "$source_pi_dir/auth.json" ]; then
  cp "$source_pi_dir/auth.json" "$PI_AGENT_DIR/auth.json"
fi
export FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$ROOT" \
  FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
  PI_CODING_AGENT_DIR="$PI_AGENT_DIR"

cleanup() {
  local rc=$?
  trap - EXIT
  "$LAB_HELPER" teardown "$SESSION" >/dev/null 2>&1 || rc=1
  rm -rf "$TMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT

"$LAB_HELPER" provision "$SESSION"
created=$("$LAB_HELPER" run "$SESSION" workspace create --cwd "$ROOT" --label real-model --no-focus) \
  || fail "could not create the isolated real-model workspace"
WORKSPACE=$(printf '%s' "$created" | jq -r '.result.workspace.workspace_id // .result.root_pane.workspace_id // empty')
[ -n "$WORKSPACE" ] || fail "the isolated workspace returned no workspace identity"
created=$("$LAB_HELPER" run "$SESSION" tab create --workspace "$WORKSPACE" --cwd "$ROOT" --label fm-real-model --no-focus) \
  || fail "could not create the production-labeled real-model task tab"
PANE=$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty')
TAB=$(printf '%s' "$created" | jq -r '.result.tab.tab_id // .result.root_pane.tab_id // empty')
[ -n "$PANE" ] && [ -n "$TAB" ] || fail "the task tab omitted its exact tab or pane identity"
"$LAB_HELPER" run "$SESSION" pane get "$PANE" >/dev/null \
  || fail "could not read the exact endpoint identity"
cat > "$HOME_DIR/state/real-model.meta" <<EOF
window=$SESSION:$PANE
endpoint_task_id=real-model
worktree=$ROOT
project=$ROOT
harness=pi
kind=ship
backend=herdr
herdr_session=$SESSION
herdr_workspace_id=$WORKSPACE
herdr_tab_id=$TAB
herdr_pane_id=$PANE
EOF
export FM_SUPERVISOR_BACKEND=herdr FM_SUPERVISOR_SESSION="$SESSION" \
  FM_SUPERVISOR_WORKSPACE_ID="$WORKSPACE" FM_SUPERVISOR_TAB_ID="$TAB" \
  FM_SUPERVISOR_PANE_ID="$PANE" FM_SUPERVISOR_TARGET="$SESSION:$PANE"

# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
fm_backend_source herdr || fail "could not load the Herdr provider"
fm_backend_validate_task_endpoint "$HOME_DIR/state/real-model.meta" real-model \
  || fail "the real endpoint metadata did not preserve exact hierarchy"

fm_backend_events_capable herdr "$SESSION" || fail "native watcher events were unavailable"
watch_out="$TMP_ROOT/watch.out"
watch_rc_file="$TMP_ROOT/watch.rc"
# Pi executes an ordinary bash tool call without asking for input. Its native
# working -> idle edges must not be misreported as the watcher's actionable
# blocked transition.
( fm_backend_wait_transition herdr "$SESSION" 60 "$HOME_DIR/state" "$SESSION:$PANE" >"$watch_out"; printf '%s\n' "$?" >"$watch_rc_file" ) &
watch_pid=$!
sleep 0.5
prompt='Use the bash tool to run sleep 3. Then reply with exactly the concatenation of FM_HERDR_ONLY_REAL_ and MODEL_OK, with no other text.'
printf -v command \
  'env PATH=%q FM_HOME=%q FM_ROOT_OVERRIDE=%q FM_STATE_OVERRIDE=%q FM_DATA_OVERRIDE=%q PI_CODING_AGENT_DIR=%q %q --approve --no-session --no-context-files --no-extensions --model %q --thinking low %q' \
  "$PANE_PATH" "$FM_HOME" "$FM_ROOT_OVERRIDE" "$FM_STATE_OVERRIDE" "$FM_DATA_OVERRIDE" \
  "$PI_CODING_AGENT_DIR" "$PI_BIN" "$MODEL" "$prompt"
"$LAB_HELPER" run "$SESSION" pane run "$PANE" "$command" >/dev/null \
  || fail "could not launch real Pi in the isolated Herdr pane"
wait "$watch_pid"
watch_rc=$(cat "$watch_rc_file" 2>/dev/null || true)
watch_record=$(cat "$watch_out" 2>/dev/null || true)
[ "$watch_rc" = 1 ] || fail "native watcher misclassified the real Pi working/idle turn (rc=${watch_rc:-missing})"
[ -z "$watch_record" ] || fail "native watcher emitted an actionable record for a turn that never blocked"

answered=0
for _ in $(seq 1 180); do
  if "$LAB_HELPER" run "$SESSION" pane read "$PANE" --source recent --lines 200 2>/dev/null \
    | grep -Fq "$TOKEN"; then
    answered=1
    break
  fi
  sleep 1
done
[ "$answered" -eq 1 ] || fail "the real model did not return the required token"

[ "$(fm_backend_agent_state herdr "$SESSION:$PANE")" = alive ] \
  || fail "production liveness did not recognize the real Pi agent"

steer_prompt='Reply with exactly the concatenation of FM_HERDR_ONLY_ and STEERING_OK, with no other text.'
submit=$(fm_backend_send_text_submit herdr "$SESSION:$PANE" "$steer_prompt" 3 0.2 0.2)
[ "$submit" = empty ] || fail "production steering did not confirm delivery: $submit"
steered=0
for _ in $(seq 1 120); do
  if "$LAB_HELPER" run "$SESSION" pane read "$PANE" --source recent --lines 200 2>/dev/null \
    | grep -Fq "$STEER_TOKEN"; then
    steered=1
    break
  fi
  sleep 1
done
[ "$steered" -eq 1 ] || fail "the real model did not answer the production steering path"

control_prompt='Use the bash tool to run sleep 20. After it finishes, reply CONTROL_NOT_INTERRUPTED.'
submit=$(fm_backend_send_text_submit herdr "$SESSION:$PANE" "$control_prompt" 3 0.2 0.2)
[ "$submit" = empty ] || fail "the control turn was not delivered: $submit"
working=0
for _ in $(seq 1 100); do
  state=$("$LAB_HELPER" run "$SESSION" agent get "$PANE" 2>/dev/null \
    | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)
  case "$state" in working|blocked) working=1; break ;; esac
  sleep 0.1
done
[ "$working" -eq 1 ] || fail "Herdr never observed the real Pi control turn"
control=$(FM_CONTROL_POLL=0.2 FM_CONTROL_EXIT_WAIT=3 "$ROOT/bin/fm-control.sh" real-model interrupt 2>&1) \
  || fail "production control could not interrupt real Pi: $control"
case "$control" in *"interrupt-delivered real-model"*"verified=agent-alive"*) : ;; *) fail "control lacked real-agent liveness proof: $control" ;; esac
[ "$(fm_backend_agent_state herdr "$SESSION:$PANE")" = alive ] \
  || fail "real Pi did not survive production interrupt control"

fm_backend_kill herdr "$SESSION:$PANE" || fail "production cleanup could not close the exact real Pi pane"
if "$LAB_HELPER" run "$SESSION" pane get "$PANE" >/dev/null 2>&1; then
  fail "production cleanup left the exact real Pi endpoint alive"
fi
pass "real Pi 0.84.4 completes Herdr state, steering, control, watcher, and cleanup lifecycle"
