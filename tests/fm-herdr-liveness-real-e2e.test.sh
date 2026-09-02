#!/usr/bin/env bash
# Opt-in real Pi 0.84.4 / Herdr liveness acceptance in one guarded named lab.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export FM_ROOT_OVERRIDE="$ROOT"
if [ -n "${_FM_BACKEND_HERDR_SOURCED:-}" ] \
  || declare -F fm_backend_herdr_pane_agent_state >/dev/null 2>&1; then
  fail "the acceptance invocation inherited a previously sourced Herdr adapter"
fi

if [ "${FM_HERDR_LIVENESS_REAL_E2E:-0}" != 1 ]; then
  echo "skip: set FM_HERDR_LIVENESS_REAL_E2E=1 to run the real Pi/Herdr liveness acceptance"
  exit 0
fi

for tool in herdr jq pi git; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
[ "$(pi --version 2>/dev/null)" = 0.84.4 ] || fail "real Pi 0.84.4 is required"

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
[ -x "$LAB_HELPER" ] || fail "the guarded Herdr lab helper is not executable at $LAB_HELPER"
SESSION=$("$LAB_HELPER" name herdr-liveness-real)
TMP_ROOT=$(fm_test_tmproot fm-herdr-liveness-real-e2e)
ORIGINAL_PATH=$PATH
FAKEBIN="$TMP_ROOT/fakebin"
HOME_DIR="$TMP_ROOT/home"
PROJ="$TMP_ROOT/project"
WT="$TMP_ROOT/worktree"
mkdir -p "$FAKEBIN" "$HOME_DIR/state" "$HOME_DIR/data/live-real" "$PROJ"
printf '# liveness acceptance\n' > "$HOME_DIR/data/live-real/brief.md"

git -C "$PROJ" init -q
printf '# fixture\n' > "$PROJ/README.md"
git -C "$PROJ" add README.md
git -C "$PROJ" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial
git -C "$PROJ" worktree add --quiet -b live-real "$WT"

cleanup() {
  local rc=$?
  trap - EXIT
  if ! PATH="$ORIGINAL_PATH" "$LAB_HELPER" teardown "$SESSION" >/dev/null; then
    rc=1
  fi
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
  exec env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" status --json
fi
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "$SESSION" ] || { echo "wrapper refused foreign session" >&2; exit 97; }
  args=("\${args[@]:0:\$((n-2))}")
else
  echo "wrapper requires trailing --session $SESSION" >&2
  exit 98
fi
exec env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"

"$LAB_HELPER" provision "$SESSION" >/dev/null || fail "could not provision the isolated Herdr lab"
lab() { env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "$@"; }

created=$(lab workspace create --cwd "$WT" --label fm-liveness-real --no-focus) \
  || fail "could not create the liveness workspace"
WORKSPACE=$(printf '%s' "$created" | jq -er '.result.workspace.workspace_id') \
  || fail "workspace create omitted its exact identity"
created=$(lab tab create --workspace "$WORKSPACE" --cwd "$WT" --label fm-live-real --no-focus) \
  || fail "could not create the exact task tab"
TAB=$(printf '%s' "$created" | jq -er '.result.tab.tab_id') \
  || fail "task tab create omitted its exact tab"
PANE=$(printf '%s' "$created" | jq -er '.result.root_pane.pane_id') \
  || fail "task tab create omitted its exact pane"
TARGET="$SESSION:$PANE"

cat > "$HOME_DIR/state/live-real.meta" <<EOF
window=$TARGET
endpoint_task_id=live-real
worktree=$WT
project=$PROJ
harness=pi
kind=scout
backend=herdr
herdr_session=$SESSION
herdr_workspace_id=$WORKSPACE
herdr_tab_id=$TAB
herdr_pane_id=$PANE
EOF

export PATH="$FAKEBIN:$ORIGINAL_PATH" FM_HOME="$HOME_DIR"
# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
[ "$FM_BACKEND_LIB_DIR" = "$ROOT/bin" ] \
  || fail "the acceptance invocation loaded fm-backend.sh from the wrong root"
fm_backend_source herdr || fail "could not load the Herdr adapter"
fm_backend_validate_task_endpoint "$HOME_DIR/state/live-real.meta" live-real \
  || fail "the exact lab endpoint did not validate"

agent_status() {
  lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty' 2>/dev/null
}
wait_status() { # <status> <polls>
  local wanted=$1 polls=$2 i=0 observed
  while [ "$i" -lt "$polls" ]; do
    observed=$(agent_status)
    [ "$observed" = "$wanted" ] && return 0
    i=$((i + 1))
    sleep 0.2
  done
  return 1
}
wait_agent_gone() { # <polls>
  local polls=$1 i=0 state
  while [ "$i" -lt "$polls" ]; do
    state=$(fm_backend_agent_state herdr "$TARGET")
    [ "$state" = dead ] && return 0
    i=$((i + 1))
    sleep 0.2
  done
  return 1
}
wait_idle_shell() { # <polls>
  local polls=$1 i=0
  while [ "$i" -lt "$polls" ]; do
    fm_backend_herdr_pane_idle_shell_sample "$SESSION" "$PANE" >/dev/null 2>&1 && return 0
    i=$((i + 1))
    sleep 0.2
  done
  return 1
}
launch_pi() {
  lab pane run "$PANE" "pi --approve --no-session" >/dev/null \
    || fail "could not launch Pi in the isolated pane"
  wait_status idle 150 || fail "Pi did not reach native idle state"
  [ "$(fm_backend_agent_state herdr "$TARGET")" = alive ] \
    || fail "valid idle Pi did not remain healthy"
}

launch_pi
pass "real Pi 0.84.4 startup and idle remain healthy in the named Herdr lab"

lab pane report-agent "$PANE" --source fm-liveness-real --agent pi --state working >/dev/null \
  || fail "could not publish the native working observation"
[ "$(fm_backend_agent_state herdr "$TARGET")" = alive ] \
  || fail "valid Pi foreground with native working status did not remain healthy"
lab pane report-agent "$PANE" --source fm-liveness-real --agent pi --state idle >/dev/null \
  || fail "could not restore the native idle observation"
pass "real Pi foreground remains healthy under native working status"

lab pane send-text "$PANE" /quit >/dev/null || fail "could not type the normal Pi exit"
lab pane send-keys "$PANE" enter >/dev/null || fail "could not submit the normal Pi exit"
wait_agent_gone 100 || fail "normal Pi exit did not clean up its registration"
pass "real Pi normal exit cleans up to a confirmed agent-free pane"

launch_pi
lab pane send-keys "$PANE" ctrl+d >/dev/null || fail "could not deliver the abrupt Pi exit"
wait_agent_gone 100 || fail "abrupt Pi exit did not clean up its registration"
pass "real Pi abrupt exit cleans up to a confirmed agent-free pane"

launch_pi
lab pane report-agent "$PANE" --source fm-liveness-real --agent pi --state working >/dev/null \
  || fail "could not stage the slow-exit working state"
control=$(FM_CONTROL_POLL=0.2 FM_CONTROL_EXIT_WAIT=8 "$ROOT/bin/fm-control.sh" live-real exit 2>&1) \
  || fail "production control did not complete the slow working exit: $control"
case "$control" in stopped\ live-real*) : ;; *) fail "slow working exit returned an unexpected result: $control" ;; esac
wait_agent_gone 40 || fail "slow working exit did not converge to agent-free"
pass "real Pi slow working exit is interrupted and cleans up normally"

# Use a fresh shell pane for the synthetic contradiction. A pane whose real Pi
# registration just exited may still receive Herdr's delayed native unregister,
# which correctly removes a later synthetic record and is not a stale fixture.
stale_created=$(lab tab create --workspace "$WORKSPACE" --cwd "$WT" --label fm-live-stale --no-focus) \
  || fail "could not create the synthetic stale-registration pane"
PANE=$(printf '%s' "$stale_created" | jq -er '.result.root_pane.pane_id') \
  || fail "the synthetic stale-registration tab omitted its exact pane"
TARGET="$SESSION:$PANE"
wait_idle_shell 50 || fail "fresh synthetic pane never reached the strict lone-idle-shell shape"
lab pane report-agent "$PANE" --source fm-liveness-real --agent pi --state idle >/dev/null \
  || fail "could not stage the synthetic stale registration"
strict_pid=$(fm_backend_herdr_pane_idle_shell_pid "$SESSION" "$PANE") \
  || fail "the exact post-registration pane no longer proved a lone idle shell"
pane_state=$(fm_backend_herdr_pane_agent_state "$SESSION" "$PANE")
[ "$pane_state" = ambiguous ] \
  || fail "fresh candidate source returned '$pane_state' despite strict shell pid $strict_pid"
recovery_state=$(fm_backend_agent_state herdr "$TARGET")
[ "$recovery_state" = ambiguous ] \
  || fail "recovery-grade liveness returned '$recovery_state' instead of preserving the synthetic contradiction"
lab agent get "$PANE" >/dev/null || fail "ambiguity must preserve the native registration"
lab pane get "$PANE" >/dev/null || fail "ambiguity must preserve the exact pane"
pass "synthetic stale registration is ambiguous without release, replacement, or cleanup"

printf '# real Pi/Herdr liveness acceptance passed in %s from source %s; inherited incident not reproduced\n' \
  "$SESSION" "$FM_BACKEND_LIB_DIR/backends/herdr.sh"
