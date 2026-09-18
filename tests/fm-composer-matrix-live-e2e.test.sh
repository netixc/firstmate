#!/usr/bin/env bash
# tests/fm-composer-matrix-live-e2e.test.sh - the live composer-matrix guard
# (live-harness-optin family; task fm-composer-thin-adapter-refactor-r1).
#
# The shared composer classifier's shape catalogue (bin/fm-composer-lib.sh) is
# built entirely from vendor-rendered signals, so per
# .agents/skills/firstmate-coding-guidelines it must be proven against the
# REAL Pi: a stub can only confirm the assumption already written into the
# stub. This guard launches installed plain Pi idle in an
# isolated tmux server and requires the real fm_tmux_composer_state to reach
# `empty`, failing loudly with Pi's version. It also proves:
#   - the strict blank-row posture live: a plain shell pane with a blank
#     cursor row must classify unknown and defer injection;
#
# Run explicitly with FM_COMPOSER_MATRIX_LIVE=1. No prompt is submitted, so no
# model tokens are spent. Missing Pi is a failure. Refresh
# docs/verification/runtime-backends.md ("Composer classification matrix")
# from this guard's output after any Pi upgrade.
#
# Folder trust: Pi launches with the repo root as cwd, which the operator's
# machine has normally already trusted; a trust dialog is a real unreadable
# composer state and correctly fails the check.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fm_live_gate opt-in FM_COMPOSER_MATRIX_LIVE tmux

SOCKET="fm-cmx-live-$$"
SESSION="cmxlive"
CHECKED=0
FAILED=0

fail() { printf 'not ok - %s\n' "$1" >&2; cleanup; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
cleanup() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
}
trap cleanup EXIT

# The library under test, driven against the private socket through a PATH
# shim so its bare `tmux` calls stay isolated from any live fleet.
SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-cmx-live.XXXXXX")
REAL_TMUX=$(command -v tmux)
cat > "$SHIM_DIR/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SH
chmod +x "$SHIM_DIR/tmux"
PATH="$SHIM_DIR:$PATH"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-tmux-lib.sh"

tmux -L "$SOCKET" new-session -d -s "$SESSION" -x 220 -y 50 -c "$ROOT"

harness_version() {  # <binary>
  "$1" --version 2>/dev/null | head -1 || printf 'version-unknown'
}

check_harness_idle_empty() {  # <name> <launch-cmd...>
  local name=$1 win="hx-$1" verdict='' i=0 budget=${FM_COMPOSER_MATRIX_LIVE_POLLS:-45} version dismissed=0 startup_screen
  shift
  version=$(harness_version "$1")
  tmux -L "$SOCKET" new-window -d -t "$SESSION:" -n "$win" -c "$ROOT" -- "$@" \
    || fail "$name ($version): could not launch in the isolated tmux server"
  while [ "$i" -lt "$budget" ]; do
    verdict=$(fm_tmux_composer_state "$SESSION:$win")
    [ "$verdict" = empty ] && break
    i=$((i + 1))
    # Fresh Pi may park on a vendor update-available modal, which the strict classifier correctly
    # refuses to call a composer. Dismiss it once, mid-budget, with a single
    # Escape - the one key that submits nothing anywhere.
    if [ "$dismissed" -eq 0 ] && [ "$i" -ge $((budget / 3)) ]; then
      # Trust prompts also accept Escape, but there it exits Pi and
      # erases the actionable failure surface. Preserve those prompts; only
      # dismiss a non-trust startup modal.
      startup_screen=$(tmux -L "$SOCKET" capture-pane -p -t "$SESSION:$win" 2>/dev/null || true)
      if ! printf '%s\n' "$startup_screen" | grep -qi 'trust'; then
        tmux -L "$SOCKET" send-keys -t "$SESSION:$win" Escape 2>/dev/null || true
      fi
      dismissed=1
    fi
    sleep 1
  done
  if [ "$verdict" != empty ]; then
    printf '# %s pane tail at failure:\n' "$name" >&2
    tmux -L "$SOCKET" capture-pane -p -t "$SESSION:$win" 2>/dev/null \
      | grep '[^[:space:]]' | tail -8 | sed 's/^/#   /' >&2
    FAILED=1
    printf 'not ok - %s (%s): idle composer never classified empty (last verdict: %s)\n' \
      "$name" "$version" "${verdict:-unreadable}" >&2
  else
    CHECKED=$((CHECKED + 1))
    pass "$name ($version): real idle composer classifies empty"
  fi
  tmux -L "$SOCKET" kill-window -t "$SESSION:$win" 2>/dev/null || true
}

# --- 1. Installed Pi must reach a proven-empty composer ----------------------
h=pi
command -v "$h" >/dev/null 2>&1 || fail "plain Pi is not installed; live composer proof cannot run"
check_harness_idle_empty "$h" "$h"

# --- 2. The strict blank-row posture, live ----------------------------------
# A plain shell pane parked on a blank line between two rules (the audit's
# sleep-pane counterexample): the permissive rule read this empty; strict must
# defer.
tmux -L "$SOCKET" new-window -d -t "$SESSION:" -n strictblank -c "$ROOT" \
  -- bash -c 'printf "────────────────────────\n\n"; printf "\033[A"; exec sleep 300'
sleep 1
verdict=$(fm_tmux_composer_state "$SESSION:strictblank")
if [ "$verdict" = unknown ]; then
  if fm_pane_input_pending "$SESSION:strictblank"; then
    CHECKED=$((CHECKED + 1))
    pass "strict posture live: a blank shell row classifies unknown and injection defers"
  else
    FAILED=1
    printf 'not ok - strict posture live: pane_input_pending did not defer on an unknown verdict\n' >&2
  fi
else
  FAILED=1
  printf 'not ok - strict posture live: blank shell row classified %s, expected unknown\n' "${verdict:-unreadable}" >&2
fi
tmux -L "$SOCKET" kill-window -t "$SESSION:strictblank" 2>/dev/null || true

# --- refuse a vacuous pass ---------------------------------------------------
[ "$FAILED" -eq 0 ] || fail "live composer-matrix guard observed failures above"
[ "$CHECKED" -gt 0 ] || fail "live composer-matrix guard verified nothing; refusing a vacuous pass"
pass "live composer-matrix guard verified $CHECKED live surface(s)"
