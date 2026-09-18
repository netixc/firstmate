#!/usr/bin/env bash
# Real plain-Pi spawn proof.
#
# Drives fm-spawn.sh and fm-teardown.sh through a private tmux socket and a
# scratch Treehouse project. A test executable named `pi` records the argv
# fm-spawn produced, removes only the final task prompt to avoid a provider call,
# then execs the installed npm Pi CLI with its profile and extension unchanged. This
# proves the provider/model, effort, generated extension, metadata identity,
# exact live Pi process identity, isolated worktree, and tmux cleanup together.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate default-on FM_PI_SPAWN_PROFILE_LIVE tmux treehouse pi

REAL_TMUX=$(command -v tmux)
REAL_PI=$(command -v pi)
PI_VERSION=$($REAL_PI --version 2>/dev/null | head -1 | tr -d '\r')
MODEL=${FM_PI_SPAWN_PROFILE_MODEL:-openai-codex/gpt-5.6-sol}
EFFORT=${FM_PI_SPAWN_PROFILE_EFFORT:-xhigh}
ID=pi-profile-live
TMP_ROOT=$(fm_test_tmproot fm-pi-spawn-profile-live)
SOCKET="fm-pi-profile-$$"
SHIM="$TMP_ROOT/shim"
HOME_DIR="$TMP_ROOT/home"
STATE="$HOME_DIR/state"
DATA="$HOME_DIR/data"
CONFIG="$HOME_DIR/config"
PROJECT="$TMP_ROOT/project"
ARGS_LOG="$TMP_ROOT/pi-args.log"
WT=
mkdir -p "$SHIM" "$STATE" "$DATA/$ID" "$CONFIG" "$PROJECT"

cleanup() {
  local status=$?
  "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  if [ -n "$WT" ] && [ -d "$WT" ]; then
    treehouse return --force "$WT" >/dev/null 2>&1 || true
  fi
  fm_test_cleanup || true
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

cat > "$SHIM/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
EOF
cat > "$SHIM/pi" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >> "$ARGS_LOG"
printf '\n' >> "$ARGS_LOG"
args=("\$@")
if [ "\${1:-}" != --help ] && [ "\${#args[@]}" -gt 0 ]; then
  last=\$((\${#args[@]} - 1))
  unset 'args[last]'
fi
exec "$REAL_PI" "\${args[@]}"
EOF
chmod +x "$SHIM/tmux" "$SHIM/pi"
PATH="$SHIM:$PATH"
export PATH

# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
fm_backend_source tmux || fail "could not load the tmux adapter"

cat > "$DATA/$ID/brief.md" <<'EOF'
You are a worker in a disposable test project.

# Task
## Captain's intent
Reply with PROFILE_PROOF_OK and do not use tools or change files.

## Firstmate spec
Exercise only the launch profile.

# Definition of done
Delivery contract: mode=no-mistakes
EOF

git -C "$PROJECT" init -q
git -C "$PROJECT" checkout -qb main
printf '# Pi profile proof\n' > "$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial
git clone --quiet --bare "$PROJECT" "$TMP_ROOT/origin.git"
git -C "$PROJECT" remote add origin "file://$TMP_ROOT/origin.git"

FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$HOME_DIR" \
  FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" \
  FM_CONFIG_OVERRIDE="$CONFIG" FM_PROJECTS_OVERRIDE="$TMP_ROOT/projects" \
  FM_SPAWN_NO_GUARD=1 PI_SKIP_VERSION_CHECK=1 \
  "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJECT" --harness pi \
    --model "$MODEL" --effort "$EFFORT" --backend tmux \
    --mode no-mistakes --yolo off >/dev/null \
  || fail "real Pi spawn failed"

META="$STATE/$ID.meta"
assert_present "$META" "real Pi spawn did not publish task metadata"
grep -Fx 'harness=pi' "$META" >/dev/null || fail "spawn did not record plain Pi identity"
grep -Fx "model=$MODEL" "$META" >/dev/null || fail "spawn did not preserve the requested provider/model"
grep -Fx "effort=$EFFORT" "$META" >/dev/null || fail "spawn did not preserve the requested effort"
if grep -q '^backend=' "$META"; then
  fail "default tmux spawn should encode its backend by omitting backend= metadata"
fi
WT=$(sed -n 's/^worktree=//p' "$META" | tail -1)
[ -n "$WT" ] && [ -d "$WT" ] || fail "spawn did not create an isolated worktree"
[ "$(cd "$WT" && pwd -P)" != "$(cd "$PROJECT" && pwd -P)" ] \
  || fail "spawn reused the primary project copy"

TARGET=$(sed -n 's/^window=//p' "$META" | tail -1)
[ -n "$TARGET" ] || fail "spawn metadata omitted the tmux endpoint"
STATE_NOW=
COMMS=
for _ in $(seq 1 150); do
  STATE_NOW=$(fm_backend_agent_state tmux "$TARGET" 2>/dev/null || true)
  COMMS=$(fm_backend_tmux_foreground_comms "$TARGET" 2>/dev/null || true)
  if [ "$STATE_NOW" = alive ] && printf '%s\n' "$COMMS" | grep -Fx pi >/dev/null; then
    break
  fi
  sleep 0.2
done
[ "$STATE_NOW" = alive ] \
  || fail "the real Pi process did not classify alive on its isolated tmux endpoint (got ${STATE_NOW:-empty})"
if ! printf '%s\n' "$COMMS" | grep -Fx pi >/dev/null; then
  TITLE=$(fm_backend_tmux_current_command "$TARGET" 2>/dev/null || true)
  PANE_TTY=$(tmux display-message -p -t "$TARGET" '#{pane_tty}' 2>/dev/null || true)
  PANE_PROCS=
  [ -z "$PANE_TTY" ] || PANE_PROCS=$(ps -t "${PANE_TTY#/dev/}" -o pid=,ppid=,pgid=,tpgid=,comm=,args= 2>/dev/null || true)
  fail "the endpoint became alive without an exact foreground Pi executable (title=${TITLE:-none}; comms=${COMMS:-none}; processes=${PANE_PROCS:-none})"
fi

LAUNCH_LINE=$(grep -F -- "--model $MODEL" "$ARGS_LOG" | tail -1)
[ -n "$LAUNCH_LINE" ] || fail "the Pi launch argv omitted --model $MODEL"
assert_contains "$LAUNCH_LINE" "--thinking $EFFORT" "the Pi launch argv omitted --thinking $EFFORT"
assert_contains "$LAUNCH_LINE" "-e $STATE/$ID.pi-ext.ts" "the Pi launch argv omitted the generated tracked extension"
assert_present "$STATE/$ID.pi-ext.ts" "the generated Pi extension was not published"
pass "plain Pi $PI_VERSION launched with provider/model=$MODEL effort=$EFFORT and exact live Pi identity"

FM_GATE_REFUSE_BYPASS=1 FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$HOME_DIR" \
  FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" \
  FM_CONFIG_OVERRIDE="$CONFIG" FM_PROJECTS_OVERRIDE="$TMP_ROOT/projects" \
  "$ROOT/bin/fm-teardown.sh" "$ID" >/dev/null 2>"$TMP_ROOT/teardown.err" \
  || fail "isolated tmux lifecycle did not cleanly tear down the real Pi task: $(cat "$TMP_ROOT/teardown.err")"
[ ! -e "$META" ] || fail "tmux lifecycle cleanup retained task metadata"
if "$REAL_TMUX" -L "$SOCKET" has-session -t firstmate 2>/dev/null; then
  "$REAL_TMUX" -L "$SOCKET" list-windows -t firstmate -F '#{window_name}' 2>/dev/null \
    | grep -Fx "fm-$ID" >/dev/null \
    && fail "tmux lifecycle cleanup retained the task window"
fi
WT=
pass "isolated tmux spawn and cleanup completed without touching the ambient tmux server"

cleanup
