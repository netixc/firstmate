#!/usr/bin/env bash
set -eu
# Real-process tmux proof for exact plain Pi liveness identity.
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v tmux >/dev/null 2>&1 || { echo 'skip: tmux unavailable'; exit 0; }
command -v pi >/dev/null 2>&1 || { echo 'skip: plain Pi unavailable'; exit 0; }
TMP=$(fm_test_tmproot tmux-pi-live)
mkdir -p "$TMP/bin" "$TMP/home/state"
REAL_PI=$(command -v pi)
cp "$(command -v sleep)" "$TMP/bin/pi"
if [ "$(uname -s)" = Darwin ]; then
  codesign --force --sign - "$TMP/bin/pi" >/dev/null 2>&1
fi
SOCK="fm-pi-live-$$"; trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TMP"' EXIT
tmux -L "$SOCK" -f /dev/null new-session -d -s live -n fake "$TMP/bin/pi 60"
tmux -L "$SOCK" new-window -d -t live -n pi "FM_HOME='$TMP/home' $REAL_PI --no-session --no-extensions -e '$ROOT/.pi/extensions/fm-primary-pi-watch.ts'"
# Backend commands call tmux directly, so expose a socket-bound shim.
cat > "$TMP/bin/tmux" <<EOF
#!/usr/bin/env bash
exec "$(command -v tmux)" -L "$SOCK" "\$@"
EOF
chmod +x "$TMP/bin/tmux"
PATH="$TMP/bin:$PATH"
FM_HOME="$TMP/home"; export FM_HOME
FM_PI_AUTHORIZED_BIN="$REAL_PI"; export FM_PI_AUTHORIZED_BIN
FM_BACKEND_LIB_DIR="$ROOT/bin"; export FM_BACKEND_LIB_DIR
# shellcheck source=/dev/null
. "$ROOT/bin/backends/tmux.sh"
state=$(fm_backend_tmux_agent_state live:fake 2>/dev/null || true)
[ "$state" != alive ] || fail "an unrelated native binary copied to pi classified alive"
pass "an arbitrary native binary named pi is not plain Pi"
for _ in $(seq 1 50); do
  state=$(fm_backend_tmux_agent_state live:pi 2>/dev/null || true)
  [ "$state" = alive ] && break
  sleep 0.1
done
[ "${state:-}" = alive ] || fail "real plain Pi process did not classify alive: ${state:-missing}"
pass "real plain Pi process classifies alive through immutable identity"
for old in pi-launcher Pi claude codex opencode pi-signed grok kimi cursor-agent muse; do
 ln -sf "$(command -v sleep)" "$TMP/bin/$old"
 tmux -L "$SOCK" new-window -d -t live -n old "$TMP/bin/$old 60"
 sleep 0.1
 state=$(fm_backend_tmux_agent_state live:old 2>/dev/null || true)
 [ "$state" != alive ] || fail "$old process classified as supported"
 tmux -L "$SOCK" kill-window -t live:old
 pass "$old process remains unsupported"
done
