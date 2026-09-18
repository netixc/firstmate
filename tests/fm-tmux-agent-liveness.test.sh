#!/usr/bin/env bash
# Portable real-tmux regression for plain Pi process attribution.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'not ok - %s\n' "$1" >&2; cleanup_all; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

command -v tmux >/dev/null 2>&1 || { echo "skip: tmux not found"; exit 0; }
SLEEP_BIN=$(command -v sleep) || { echo "skip: sleep not found"; exit 0; }
REAL_TMUX=$(command -v tmux)
SOCKET="fm-liveness-$$"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-liveness.XXXXXX")
SESSION=liveness

cleanup_all() {
  "$REAL_TMUX" -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ -n "${LAB:-}" ] && rm -rf "$LAB"
}
trap cleanup_all EXIT

mkdir -p "$LAB/shim" "$LAB/bin" "$LAB/wt"
cat > "$LAB/shim/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SH
chmod +x "$LAB/shim/tmux"
PATH="$LAB/shim:$PATH"
export PATH

ln -s "$SLEEP_BIN" "$LAB/bin/pi"
ln -s "$SLEEP_BIN" "$LAB/bin/pi-helper"
ln -s "$SLEEP_BIN" "$LAB/bin/not-a-worker"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
fm_backend_source tmux || fail "fm_backend_source tmux failed"

"$REAL_TMUX" -L "$SOCKET" new-session -d -s "$SESSION" -n idle -c "$LAB/wt" \
  || fail "could not start the private tmux server"

new_window() {
  local name=$1
  shift
  "$REAL_TMUX" -L "$SOCKET" new-window -d -t "$SESSION:" -n "$name" -c "$LAB/wt" -- "$@" \
    || fail "could not create window $name"
}

wait_for_state() {
  local target=$1 expected=$2 tries=${3:-100} got i=0
  while [ "$i" -lt "$tries" ]; do
    got=$(fm_backend_agent_state tmux "$target")
    [ "$got" = "$expected" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  printf 'last verdict for %s was %s (expected %s)\n' "$target" "${got:-<none>}" "$expected" >&2
  return 1
}

new_window agent "$LAB/bin/pi" 900
wait_for_state "$SESSION:agent" alive \
  || fail "an exact Pi foreground process must classify alive"
pass "tmux liveness: exact Pi foreground process classifies alive"

new_window lookalike "$LAB/bin/pi-helper" 900
wait_for_state "$SESSION:lookalike" ambiguous \
  || fail "a Pi lookalike must not classify as a worker"
pass "tmux liveness: a Pi lookalike remains ambiguous"

new_window unknown "$LAB/bin/not-a-worker" 900
wait_for_state "$SESSION:unknown" ambiguous \
  || fail "an unknown foreground process must remain ambiguous"
pass "tmux liveness: unknown process remains ambiguous"

if command -v node >/dev/null 2>&1; then
  new_window node "$(command -v node)" -e 'setInterval(() => {}, 1000)'
  wait_for_state "$SESSION:node" ambiguous \
    || fail "a generic Node process must not classify as Pi"
  pass "tmux liveness: generic Node is not broad-matched as Pi"
else
  pass "tmux liveness: generic Node check skipped (node not found)"
fi

wait_for_state "$SESSION:idle" dead \
  || fail "an idle shell pane must classify dead"
pass "tmux liveness: idle shell classifies dead"

new_window background bash -c "set -m; '$LAB/bin/pi' 900 & printf '%s\n' \"\$!\" > '$LAB/bg.pid'; exec /bin/sh"
bg_pid=
for _ in $(seq 1 100); do
  [ -s "$LAB/bg.pid" ] && bg_pid=$(cat "$LAB/bg.pid") && break
  sleep 0.1
done
[ -n "$bg_pid" ] || fail "the background Pi process never started"
wait_for_state "$SESSION:background" dead \
  || fail "a background-only Pi process must not make an idle pane alive"
pass "tmux liveness: background Pi does not claim an idle pane"

[ "$(fm_backend_agent_state tmux "$SESSION:no-such-window")" = missing ] \
  || fail "an absent window must classify missing"
pass "tmux liveness: absent window classifies missing"

cleanup_all
trap - EXIT
