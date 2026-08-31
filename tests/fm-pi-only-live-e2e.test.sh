#!/usr/bin/env bash
# Credentialed real-model proof that plain Pi exposes Firstmate's exact identity.
set -eu
if [ "${FM_PI_ONLY_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_PI_ONLY_LIVE_E2E=1 to run the real plain Pi integration"
  exit 0
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v pi >/dev/null 2>&1 || { echo "not ok - pi unavailable" >&2; exit 1; }
PI_VERSION=$(pi --version 2>/dev/null || true)
[ "$PI_VERSION" = 0.84.4 ] || { printf 'not ok - real Pi 0.84.4 required, found %s\n' "${PI_VERSION:-unknown}" >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-pi-only-live.XXXXXX")
SESSION="fm-pi-control-$$"
trap 'tmux kill-session -t "$SESSION" 2>/dev/null || true; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"
out=$(cd "$ROOT" && FM_HOME="$TMP" pi --print --approve --no-session --no-context-files --no-extensions \
  -e "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
  -e "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" \
  --model openai-codex/gpt-5.6-sol --thinking low \
  "Use the bash tool to run: bash -c '. bin/fm-session-lock-lib.sh; fm_harness_ancestry_pid >/dev/null && echo pi'. Reply with exactly the command's one-word stdout and nothing else.")
[ "$out" = pi ] || { printf 'not ok - real Pi returned %q\n' "$out" >&2; exit 1; }
printf 'ok - real Pi extensions register lifecycle identity (Pi %s)\n' "$PI_VERSION"
command -v tmux >/dev/null 2>&1 || { echo "not ok - tmux unavailable for real Pi lifecycle control" >&2; exit 1; }
PI_BIN=$(command -v pi)
tmux new-session -d -s "$SESSION" -n pi \
  "FM_HOME='$TMP' '$PI_BIN' --no-session --no-extensions -e '$ROOT/.pi/extensions/fm-primary-pi-watch.ts' -e '$ROOT/.pi/extensions/fm-primary-turnend-guard.ts'"
printf 'window=%s:pi\nworktree=%s\nproject=%s\nkind=ship\nharness=pi\n' "$SESSION" "$ROOT" "$ROOT" > "$TMP/state/control.meta"
for _ in $(seq 1 50); do
  if FM_HOME="$TMP" FM_PI_AUTHORIZED_BIN="$PI_BIN" "$ROOT/bin/fm-control.sh" control interrupt >/dev/null 2>&1; then
    interrupted=1
    break
  fi
  sleep 0.1
done
[ "${interrupted:-0}" = 1 ] || { echo "not ok - real Pi interrupt control failed" >&2; exit 1; }
FM_HOME="$TMP" FM_PI_AUTHORIZED_BIN="$PI_BIN" "$ROOT/bin/fm-control.sh" control exit >/dev/null
printf 'ok - real Pi interrupt and exit lifecycle control succeed (Pi %s)\n' "$PI_VERSION"
