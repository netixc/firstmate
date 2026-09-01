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
[ "$(pi --version 2>/dev/null || true)" = 0.84.4 ] || fail "real Pi 0.84.4 is required"

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
SESSION=$($LAB_HELPER name fm-herdr-pi-real-model-e2e)
TMP_ROOT=$(fm_test_tmproot fm-herdr-pi-real-model-e2e)
MODEL=${FM_HERDR_PI_REAL_MODEL:-openai-codex/gpt-5.6-sol}
TOKEN=FM_HERDR_ONLY_REAL_MODEL_OK
PANE=

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
PANE=$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty')
[ -n "$PANE" ] || fail "the isolated workspace returned no pane identity"

prompt='Use the bash tool to run sleep 3. Then reply with exactly the concatenation of FM_HERDR_ONLY_REAL_ and MODEL_OK, with no other text.'
printf -v command 'pi --approve --no-session --no-context-files --no-extensions --model %q --thinking low %q' \
  "$MODEL" "$prompt"
"$LAB_HELPER" run "$SESSION" pane run "$PANE" "$command" >/dev/null \
  || fail "could not launch real Pi in the isolated Herdr pane"

working=0
for _ in $(seq 1 100); do
  state=$("$LAB_HELPER" run "$SESSION" agent get "$PANE" 2>/dev/null \
    | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)
  case "$state" in working|blocked) working=1; break ;; esac
  sleep 0.1
done
[ "$working" -eq 1 ] || fail "Herdr never observed the real Pi provider turn running"

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

"$LAB_HELPER" run "$SESSION" pane get "$PANE" >/dev/null \
  || fail "the exact Herdr endpoint disappeared after the provider turn"
pass "real Pi 0.84.4 model turn runs inside an exact named Herdr endpoint"
