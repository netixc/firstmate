#!/usr/bin/env bash
# Opt-in real Pi 0.84.4 proof for supervision and lifecycle control.
set -eu
if [ "${FM_PI_ONLY_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_PI_ONLY_LIVE_E2E=1 to run the real plain Pi integration"
  exit 0
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FM_GATE_REFUSE_BYPASS=1
command -v pi >/dev/null 2>&1 || { echo "not ok - pi unavailable" >&2; exit 1; }
PI_BIN=$(command -v pi)
PI_VERSION=$($PI_BIN --version 2>/dev/null || true)
[ "$PI_VERSION" = 0.84.4 ] || { printf 'not ok - real Pi 0.84.4 required, found %s\n' "${PI_VERSION:-unknown}" >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "not ok - tmux unavailable for real Pi lifecycle control" >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-pi-only-live.XXXXXX")
WORKTREE="$TMP/worktree"
SESSION="fm-pi-control-$$"
cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  git -C "$ROOT" worktree remove --force "$WORKTREE" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
git -C "$ROOT" worktree add --detach "$WORKTREE" HEAD >/dev/null
mkdir -p "$TMP/state" "$TMP/data/control" "$TMP/pi-agent"

out=$(cd "$ROOT" && FM_HOME="$TMP" "$PI_BIN" \
  --print --approve --no-session --no-context-files --no-extensions \
  -e "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
  -e "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" \
  --model openai-codex/gpt-5.6-sol --thinking low \
  "Use the bash tool to run PI_CODING_AGENT=true bin/fm-harness.sh. Reply with exactly the command's one-word stdout and nothing else.")
[ "$out" = pi ] || { printf 'not ok - real Pi returned %q\n' "$out" >&2; exit 1; }
printf 'ok - real Pi supervision extensions preserve plain-Pi identity (Pi %s)\n' "$PI_VERSION"

tmux new-session -d -c "$WORKTREE" -s "$SESSION" -n fm-control
tmux send-keys -l -t "$SESSION:fm-control" \
  "export FM_HOME='$TMP' PI_CODING_AGENT_DIR='$TMP/pi-agent'; '$PI_BIN' --no-session --no-extensions -e '$ROOT/.pi/extensions/fm-primary-pi-watch.ts' -e '$ROOT/.pi/extensions/fm-primary-turnend-guard.ts'"
tmux send-keys -t "$SESSION:fm-control" Enter
printf 'Real Pi lifecycle control validation.\n' > "$TMP/data/control/brief.md"
printf 'window=%s:fm-control\nendpoint_task_id=control\nworktree=%s\nproject=%s\nkind=ship\nmode=no-mistakes\nyolo=off\nharness=pi\nmodel=%s\neffort=low\n' \
  "$SESSION" "$WORKTREE" "$ROOT" 'openai-codex/gpt-5.6-sol' > "$TMP/state/control.meta"
for _ in $(seq 1 100); do
  if FM_HOME="$TMP" "$ROOT/bin/fm-control.sh" control interrupt >/dev/null 2>&1; then
    interrupted=1
    break
  fi
  sleep 0.1
done
[ "${interrupted:-0}" = 1 ] || { echo "not ok - real Pi interrupt control failed" >&2; exit 1; }
printf 'ok - real Pi interrupt lifecycle control succeeds (Pi %s)\n' "$PI_VERSION"
FM_HOME="$TMP" FM_SPAWN_NO_GUARD=1 \
  "$ROOT/bin/fm-control.sh" control relaunch --harness pi \
  --model openai-codex/gpt-5.6-sol --effort low --note 'Verify Pi transactional relaunch.' >/dev/null
[ "$(sed -n 's/^harness=//p' "$TMP/state/control.meta" | tail -1)" = pi ] || { echo "not ok - Pi relaunch lost harness metadata" >&2; exit 1; }
[ "$(sed -n 's/^model=//p' "$TMP/state/control.meta" | tail -1)" = openai-codex/gpt-5.6-sol ] || { echo "not ok - Pi relaunch lost model metadata" >&2; exit 1; }
[ "$(sed -n 's/^effort=//p' "$TMP/state/control.meta" | tail -1)" = low ] || { echo "not ok - Pi relaunch lost effort metadata" >&2; exit 1; }
printf 'ok - real Pi transactional relaunch preserves executable and profile selection (Pi %s)\n' "$PI_VERSION"
FM_HOME="$TMP" "$ROOT/bin/fm-control.sh" control exit >/dev/null
printf 'ok - real Pi replacement exit lifecycle control succeeds (Pi %s)\n' "$PI_VERSION"
