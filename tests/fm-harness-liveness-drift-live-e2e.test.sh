#!/usr/bin/env bash
# tests/fm-harness-liveness-drift-live-e2e.test.sh - default-on drift guard proving
# installed plain Pi is classified `alive` by the tmux liveness probe and by
# the exact-executable ancestry walk.
#
# Both verdicts depend on Pi's real process name, which can change between
# releases. A stub cannot prove that vendor-owned surface. Pi is launched bare
# with no prompt, so the guard spends no model tokens and needs no credential.
# Generic Node processes and argument strings are never accepted as identity.
#
# Portable serial CI installs the public Pi package. The portable counterpart
# in tests/fm-tmux-agent-liveness.test.sh pins classifier logic. Run this guard
# after any Pi upgrade and before trusting refreshed evidence.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate default-on FM_HARNESS_LIVENESS_DRIFT tmux

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'not ok - %s\n' "$1" >&2; cleanup_all; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
note() { printf '# %s\n' "$1"; }

REAL_TMUX=$(command -v tmux)
SOCKET="fm-liveness-drift-$$"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-liveness-drift.XXXXXX")
SESSION=drift

cleanup_all() {
  "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ -n "${LAB:-}" ] && rm -rf "$LAB"
}
trap cleanup_all EXIT

mkdir -p "$LAB/shim" "$LAB/wt"
cat > "$LAB/shim/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SH
chmod +x "$LAB/shim/tmux"
PATH="$LAB/shim:$PATH"
export PATH

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
fm_backend_source tmux || fail "fm_backend_source tmux failed"

"$REAL_TMUX" -L "$SOCKET" new-session -d -s "$SESSION" -n control -c "$LAB/wt" \
  || fail "could not start the private tmux server"

resolve_harness_binary() {  # <harness>
  local candidate
  candidate=$(command -v "$1" 2>/dev/null || true)
  [ -n "$candidate" ] && [ -x "$candidate" ] || return 1
  printf '%s\n' "$candidate"
}

CHECKED=0

# Plain Pi is the only supported worker runtime.
harness=pi
if ! bin_path=$(resolve_harness_binary "$harness"); then
  fail "Pi is not installed on this machine, so runtime identity cannot be verified"
fi

  version=$("$bin_path" --version 2>/dev/null | head -1 | tr -d '\r') || version=
  [ -n "$version" ] || version="unknown"

  target="$SESSION:$harness"
  launch_args=""
  # shellcheck disable=SC2086  # deliberate: an empty value must add no argument
  "$REAL_TMUX" -L "$SOCKET" new-window -d -t "$SESSION:" -n "$harness" -c "$LAB/wt" -- "$bin_path" $launch_args \
    || fail "$harness ($version): could not launch a window for the liveness probe"

  state=
  for _ in $(seq 1 300); do
    state=$(fm_backend_agent_state tmux "$target")
    [ "$state" = alive ] && break
    sleep 0.2
  done

  title=$(fm_backend_tmux_current_command "$target")
  comms=$(fm_backend_tmux_foreground_comms "$target" | tr '\n' ' ')

  [ "$state" = alive ] || fail \
    "LIVENESS DRIFT: $harness $version is running but classifies '$state', not 'alive'. Supervision and lifecycle control treat this endpoint as unattributable. Observed process title '$title'; observed foreground process names [$comms]. Teach bin/fm-agent-process-lib.sh's fm_agent_process_classify_name the identity this release actually reports."

  note "$harness $version: title='$title' foreground=[$comms]"

  pass "harness liveness: $harness $version classifies alive"

  # Detection: ask the ancestry walk what it makes of this real harness process.
  expect_harness=$harness
  pane_pid=$("$REAL_TMUX" -L "$SOCKET" display-message -p -t "$target" '#{pane_pid}' 2>/dev/null | tr -d ' ')
  [ -n "$pane_pid" ] || fail "$harness ($version): could not read the pane pid for the detection probe"
  # Probe from below the pane shell, where Firstmate tool subprocesses actually
  # run. Follow only the foreground process group's deepest upward path, and
  # require exact `comm pi` evidence. Pi's native process can take a moment to
  # appear, so poll for it.
  pane_tty=$("$REAL_TMUX" -L "$SOCKET" display-message -p -t "$target" '#{pane_tty}' 2>/dev/null | tr -d ' ')
  verdicts=
  for _ in $(seq 1 150); do
    fg_pids=
    if [ -n "$pane_tty" ]; then
      fg_pids=$(LC_ALL=C ps -t "${pane_tty#/dev/}" -o pid=,pgid=,tpgid= 2>/dev/null \
        | while read -r fg_pid fg_pgid fg_tpgid; do
            [ -n "$fg_pid" ] || continue
            [ "$fg_pgid" = "$fg_tpgid" ] || continue
            printf '%s ' "$fg_pid"
          done)
    fi
    # shellcheck disable=SC2086  # deliberate: the foreground pids are separate arguments
    verdicts=$("$ROOT/bin/fm-harness.sh" ancestry-descent "$pane_pid" $fg_pids 2>/dev/null || true)
    case "$verdicts" in *"comm $expect_harness"*) break ;; esac
    sleep 0.2
  done

  drift_context="Observed process title '$title'; observed foreground process names [$comms]; observed ancestry verdicts [$(printf '%s' "$verdicts" | tr '\n' ';')]."

  [ -n "$verdicts" ] || fail \
    "DETECTION DRIFT: Pi $version is running but the ancestry walk found no exact Pi executable identity. $drift_context Update the exact Pi process identity contract for this release."

  SAW_COMM=0
  while read -r strength named; do
    [ -n "$strength" ] || continue
    [ "$strength" = comm ] || continue
    [ "$named" = "$expect_harness" ] || fail \
      "DETECTION DRIFT: Pi $version produced unexpected exact executable identity '$named'. $drift_context"
    SAW_COMM=1
  done <<EOF
$verdicts
EOF

  [ "$SAW_COMM" = 1 ] || fail \
    "DETECTION DRIFT: Pi $version has no exact executable identity on the foreground ancestry path. $drift_context"

  note "$harness $version: ancestry verdicts=[$(printf '%s' "$verdicts" | tr '\n' ';')]"
pass "Pi detection: $version is identified by the ancestry walk as exact pi"
CHECKED=$((CHECKED + 1))

[ "$CHECKED" -gt 0 ] || fail \
  "plain Pi is not installed here, so this run proved nothing"

note "checked $CHECKED installed Pi runtime"

cleanup_all
trap - EXIT
