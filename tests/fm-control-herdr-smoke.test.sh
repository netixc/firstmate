#!/usr/bin/env bash
# tests/fm-control-herdr-smoke.test.sh - real-herdr smoke test for the agent
# lifecycle control plane (bin/fm-control.sh).
#
# legacy-provider is the control plane's reference backend and is covered hermetically in
# tests/fm-control.test.sh. herdr is the OTHER backend whose recovery-grade
# agent-state classifier the control plane is allowed to trust, so its
# behavior is pinned here against the REAL binary rather than a stub: whether
# an agent is running, and therefore whether a lifecycle verb may act at all,
# comes from herdr's own agent registry.
#
# No real agent is launched. herdr's `pane report-agent` is the same registry
# the adapter reads, so a synthetic registration on a proven lone shell
# exercises the conservative contradiction the control plane must preserve.
#
# Always runs on a private, named, throwaway lab session, never the default
# one (tests/herdr-test-safety.sh; the 2026-07-02 incident). Skips cleanly
# when herdr or jq is missing.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v herdr >/dev/null 2>&1 || { echo "skip: herdr not found"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "skip: jq not found (required by the herdr adapter)"; exit 0; }

# shellcheck source=tests/herdr-test-safety.sh
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane

SESSION="fm-lab-control-smoke-$$"
LAB_HELPER=${FM_HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
ORIGINAL_PATH=$PATH
export HERDR_SESSION="$SESSION"
SCRATCH=
cleanup_all() {
  local rc=$?
  trap - EXIT
  if [ -n "$SCRATCH" ]; then
    rm -rf "$SCRATCH"
  fi
  if ! PATH="$ORIGINAL_PATH" "$LAB_HELPER" teardown "$SESSION" >/dev/null; then
    rc=1
  fi
  return "$rc"
}
trap 'rc=$?; cleanup_all || rc=$?; exit "$rc"' EXIT
"$LAB_HELPER" provision "$SESSION" >/dev/null \
  || fail "could not prepare isolated Herdr lab session"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fm-control-herdr.XXXXXX")
SCRATCH=$(cd "$SCRATCH" && pwd)
FAKEBIN="$SCRATCH/fakebin"
HOME_DIR="$SCRATCH/home"
mkdir -p "$FAKEBIN" "$HOME_DIR/state" "$HOME_DIR/data/hsmoke"
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
export PATH="$FAKEBIN:$ORIGINAL_PATH" FM_ROOT_OVERRIDE="$ROOT"
lab() { env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "$@"; }
printf '# brief\n' > "$HOME_DIR/data/hsmoke/brief.md"

# A real git worktree so the control plane's checkpoint has a real local copy.
PROJ="$SCRATCH/proj"
WT="$SCRATCH/wt"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
printf '# proj\n' > "$PROJ/README.md"
git -C "$PROJ" add README.md
git -C "$PROJ" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial
git -C "$PROJ" worktree add --quiet -b hsmoke "$WT"

if [ -n "${_FM_BACKEND_HERDR_SOURCED:-}" ] \
  || declare -F fm_backend_herdr_pane_agent_state >/dev/null 2>&1; then
  fail "the smoke invocation inherited a previously sourced Herdr adapter"
fi
# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
[ "$FM_BACKEND_LIB_DIR" = "$ROOT/bin" ] \
  || fail "the smoke invocation loaded fm-backend.sh from the wrong root"
fm_backend_source herdr || fail "fm_backend_source herdr failed"

CONTAINER_RAW=$(fm_backend_herdr_container_ensure "$WT") || fail "container_ensure failed"
CONTAINER=${CONTAINER_RAW%%$'\t'*}
SEEDED_TAB_ID=${CONTAINER_RAW#*$'\t'}
WORKSPACE_ID=${CONTAINER#*:}
TASK_IDS=$(fm_backend_herdr_create_task "$CONTAINER" "fm-hsmoke" "$WT" "$SEEDED_TAB_ID") \
  || fail "create_task failed"
read -r TAB_ID PANE_ID <<EOF
$TASK_IDS
EOF
[ -n "$TAB_ID" ] && [ -n "$PANE_ID" ] || fail "create_task did not return tab/pane ids"

{
  echo "window=$SESSION:$PANE_ID"
  echo "endpoint_task_id=hsmoke"
  echo "worktree=$WT"
  echo "project=$PROJ"
  echo "harness=pi"
  echo "kind=ship"
  echo "mode=no-mistakes"
  echo "yolo=off"
  echo "model=default"
  echo "effort=default"
  echo "backend=herdr"
  echo "herdr_session=$SESSION"
  echo "herdr_workspace_id=$WORKSPACE_ID"
  echo "herdr_tab_id=$TAB_ID"
  echo "herdr_pane_id=$PANE_ID"
} > "$HOME_DIR/state/hsmoke.meta"

run_control() {
  env FM_HOME="$HOME_DIR" HERDR_SESSION="$SESSION" \
    FM_CONTROL_POLL=0.2 FM_CONTROL_EXIT_WAIT=2 \
    "$ROOT/bin/fm-control.sh" "$@" 2>&1
}

# --- no registered agent: the endpoint exists but hosts no agent ------------

OUT=$(run_control hsmoke exit) || fail "exit against an agent-free herdr pane should be idempotent success: $OUT"
case "$OUT" in
  "already-stopped hsmoke"*) : ;;
  *) fail "an agent-free herdr pane should report already-stopped, got: $OUT" ;;
esac
pass "real herdr: exit on a pane with no registered agent is idempotent success"

if OUT=$(run_control hsmoke interrupt 2>&1); then
  fail "interrupt should refuse when herdr reports no agent on the pane: $OUT"
fi
case "$OUT" in
  *"nothing to interrupt"*) : ;;
  *) fail "the interrupt refusal should say there is no agent, got: $OUT" ;;
esac
pass "real herdr: interrupt refuses when herdr's own agent registry reports no agent"

# --- stale registration: strict shell contradiction refuses every verb -------

lab pane report-agent "$PANE_ID" --source fm-control-smoke --agent pi \
  --state idle >/dev/null || fail "could not create the synthetic stale registration"

STATE=$(fm_backend_agent_state herdr "$SESSION:$PANE_ID")
[ "$STATE" = ambiguous ] \
  || fail "a registered native status on the proven lone shell should be ambiguous, got '$STATE'"

before=$("$LAB_HELPER" run "$SESSION" pane read "$PANE_ID" --source recent --lines 40 2>/dev/null || true)
if OUT=$(run_control hsmoke interrupt 2>&1); then
  fail "interrupt should refuse an ambiguous registered shell: $OUT"
fi
case "$OUT" in
  *"reads 'ambiguous' rather than a positively classified state"*) : ;;
  *) fail "interrupt should name the ambiguous liveness refusal, got: $OUT" ;;
esac
if OUT=$(run_control hsmoke exit 2>&1); then
  fail "exit should refuse an ambiguous registered shell: $OUT"
fi
case "$OUT" in
  *"reads 'ambiguous' rather than a positively classified state"*) : ;;
  *) fail "exit should name the ambiguous liveness refusal, got: $OUT" ;;
esac
after=$("$LAB_HELPER" run "$SESSION" pane read "$PANE_ID" --source recent --lines 40 2>/dev/null || true)
[ "$after" = "$before" ] || fail "control typed into the shell after ambiguous liveness"

lab pane get "$PANE_ID" >/dev/null \
  || fail "ambiguous control must preserve the endpoint"
lab agent get "$PANE_ID" >/dev/null \
  || fail "ambiguous control must preserve the registration"
[ -d "$WT" ] || fail "ambiguous control must preserve the task's local copy"
pass "real herdr: synthetic stale registration is ambiguous and control preserves every artifact without typing"
