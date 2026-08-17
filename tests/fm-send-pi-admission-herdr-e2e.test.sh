#!/usr/bin/env bash
# Guarded real Pi/Herdr busy-steer smoke for fm-send's exact admission receipt.
# Opt-in because it launches a real Pi in a named non-default Herdr lab. Every
# Herdr operation, including production adapter calls, is routed through
# bin/fm-herdr-lab.sh; teardown's default-session tripwire is authoritative.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "${FM_SEND_PI_ADMISSION_HERDR_E2E:-0}" != 1 ]; then
  echo "skip: set FM_SEND_PI_ADMISSION_HERDR_E2E=1 to run the real Pi/Herdr busy-steer admission smoke"
  exit 0
fi
for tool in herdr jq pi node treehouse; do
  command -v "$tool" >/dev/null 2>&1 || { echo "skip: $tool not found"; exit 0; }
done

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
SESSION=$($LAB_HELPER name fix-fm-send-admission-r7)
TMP_ROOT=$(fm_test_tmproot fm-send-pi-admission-herdr-e2e)
HOME_DIR="$TMP_ROOT/home"
STATE="$HOME_DIR/state"
PROJECT="$TMP_ROOT/project"
FAKEBIN="$TMP_ROOT/fakebin"
PI_DIR="$TMP_ROOT/pi-agent"
ID=busy-pi-live
MESSAGE='LIVE_BUSY_STEER_EXACT_ONCE'
ORIGINAL_PATH=$PATH

cleanup() {
  local rc=$?
  trap - EXIT
  if ! "$LAB_HELPER" teardown "$SESSION"; then rc=1; fi
  if [ "${FM_TEST_KEEP:-0}" = 1 ]; then
    echo "kept live admission fixture at $TMP_ROOT" >&2
  else
    rm -rf "$TMP_ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT
"$LAB_HELPER" provision "$SESSION"

mkdir -p "$HOME_DIR"/{state,data,config,projects} "$HOME_DIR/data/$ID" "$FAKEBIN" "$PI_DIR"
printf 'pi\n' > "$HOME_DIR/config/crew-harness"
printf 'Live busy-steer fixture. Remain within the isolated test provider.\nDelivery contract: mode=no-mistakes\n' \
  > "$HOME_DIR/data/$ID/brief.md"
touch "$STATE/.last-watcher-beat"
fm_git_init_commit "$PROJECT"
git -C "$PROJECT" remote add origin "$PROJECT"
git -C "$PROJECT" fetch -q origin
printf '%s\n' '{"followUpMode":"all"}' > "$PI_DIR/settings.json"

PROVIDER_EXT="$TMP_ROOT/slow-provider.ts"
cat > "$PROVIDER_EXT" <<'TS'
import {
  type AssistantMessage,
  createAssistantMessageEventStream,
} from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync } from "node:fs";

let providerCalls = 0;
export default function (pi: ExtensionAPI): void {
  pi.on("project_trust", () => ({ trusted: "yes", remember: false }));
  pi.registerProvider("fm-admission-fixture", {
    baseUrl: "http://127.0.0.1/unused",
    apiKey: "isolated-test-only",
    api: "fm-admission-fixture-api",
    models: [{
      id: "slow",
      name: "Isolated slow busy-steer fixture",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 131072,
      maxTokens: 128,
    }],
    streamSimple(model) {
      providerCalls += 1;
      const stream = createAssistantMessageEventStream();
      const output: AssistantMessage = {
        role: "assistant",
        content: [],
        api: model.api,
        provider: model.provider,
        model: model.id,
        usage: {
          input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
        },
        stopReason: "stop",
        timestamp: Date.now(),
      };
      queueMicrotask(() => {
        stream.push({ type: "start", partial: output });
        const block = { type: "text" as const, text: "fixture remains working" };
        output.content.push(block);
        stream.push({ type: "text_start", contentIndex: 0, partial: output });
        stream.push({ type: "text_delta", contentIndex: 0, delta: block.text, partial: output });
        const finish = () => {
          stream.push({ type: "text_end", contentIndex: 0, content: block.text, partial: output });
          stream.push({ type: "done", reason: "stop", message: output });
          stream.end();
        };
        if (providerCalls === 1) {
          const timer = setInterval(() => {
            if (!existsSync(process.env.FM_FIXTURE_RELEASE!)) return;
            clearInterval(timer);
            finish();
          }, 25);
        } else {
          setTimeout(finish, 30000);
        }
      });
      return stream;
    },
  });
}
TS

# Production adapter calls already append a validated trailing --session pair.
# Strip only that exact pair, then let the guarded helper append it again.
cat > "$FAKEBIN/herdr" <<EOF
#!/usr/bin/env bash
set -euo pipefail
helper='$LAB_HELPER'
session='$SESSION'
real_path='$ORIGINAL_PATH'
args=("\$@")
n=\${#args[@]}
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "\$session" ] || exit 97
  args=("\${args[@]:0:\$((n-2))}")
else
  [ "\${HERDR_SESSION:-}" = "\$session" ] || exit 98
fi
if [ -e '$TMP_ROOT/armed' ] && [ "\${args[0]:-}" = pane ] \
  && [ "\${args[1]:-}" = send-keys ] && [ "\${args[3]:-}" = enter ]; then
  PATH="\$real_path" "\$helper" run "\$session" "\${args[@]}"
  rc=\$?
  touch '$TMP_ROOT/release'
  exit "\$rc"
fi
PATH="\$real_path" exec "\$helper" run "\$session" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"

REAL_PI=$(type -P pi)
cat > "$FAKEBIN/pi" <<EOF
#!/usr/bin/env bash
set -e
if [ "\${1:-}" = --help ] || [ "\${1:-}" = --version ]; then
  exec '$REAL_PI' "\$@"
fi
export PI_CODING_AGENT_DIR='$PI_DIR'
export FM_FIXTURE_RELEASE='$TMP_ROOT/release'
exec '$REAL_PI' -e '$PROVIDER_EXT' --provider fm-admission-fixture --model slow "\$@"
EOF
chmod +x "$FAKEBIN/pi"

spawn_out=$(env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID \
  PATH="$FAKEBIN:$ORIGINAL_PATH" HERDR_SESSION="$SESSION" FM_BACKEND=herdr \
  FM_HOME="$HOME_DIR" FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$HOME_DIR/data" \
  FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
  FM_SPAWN_NO_GUARD=1 \
  "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJECT" --mode no-mistakes --yolo off 2>&1)
expect_code 0 $? "real Herdr fixture spawn failed: $spawn_out"
META="$STATE/$ID.meta"
PANE=$(sed -n 's/^herdr_pane_id=//p' "$META" | tail -1)
TARGET=$(sed -n 's/^window=//p' "$META" | tail -1)
GEN=$(sed -n 's/^busy_gen=//p' "$META" | tail -1)
[ -n "$PANE" ] && [ -n "$TARGET" ] && [ -n "$GEN" ] || fail "spawn omitted the live target identity"

wait_for_working() {
  local status
  for _ in $(seq 1 240); do
    status=$("$LAB_HELPER" run "$SESSION" agent get "$PANE" 2>/dev/null \
      | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)
    [ "$status" = working ] && return 0
    sleep 0.25
  done
  return 1
}
wait_for_working || fail "real Pi fixture did not become working before the steer"
BEFORE=$("$LAB_HELPER" run "$SESSION" agent get "$PANE" | jq -r '.result.agent.agent_status')
touch "$TMP_ROOT/armed"

set +e
PATH="$FAKEBIN:$ORIGINAL_PATH" HERDR_SESSION="$SESSION" FM_HOME="$HOME_DIR" \
  FM_SEND_SETTLE=0 "$ROOT/bin/fm-send.sh" "$ID" "$MESSAGE" \
  >"$TMP_ROOT/send.out" 2>"$TMP_ROOT/send.err"
SEND_RC=$?
set -e
expect_code 0 "$SEND_RC" "real busy Pi steer was not confirmed: $(cat "$TMP_ROOT/send.err")"
AFTER=$("$LAB_HELPER" run "$SESSION" agent get "$PANE" | jq -r '.result.agent.agent_status')
[ "$BEFORE" = working ] && [ "$AFTER" = working ] \
  || fail "real Pi was not working both before and after the steer (before=$BEFORE after=$AFTER)"

SESSION_FILE=$(find "$PI_DIR/sessions" -type f -name '*.jsonl' 2>/dev/null | head -1)
[ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ] || fail "real Pi did not persist its isolated session transcript"
[ "$(find "$PI_DIR/sessions" -type f -name '*.jsonl' | wc -l | tr -d ' ')" -eq 1 ] \
  || fail "isolated Pi fixture produced an ambiguous session transcript set"
count=0
for _ in $(seq 1 80); do
  count=$(jq -r --arg text "$MESSAGE" \
    'select(.type == "message" and .message.role == "user") | .message.content | if type == "array" then map(select(.type == "text") | .text) else [.] end | .[]' \
    "$SESSION_FILE" 2>/dev/null | grep -Fxc "$MESSAGE" || true)
  [ "$count" -eq 1 ] && break
  sleep 0.1
done
[ "$count" -eq 1 ] || fail "real Pi transcript contains the steer $count times instead of exactly once"

IFS=$'\t' read -r hash bytes <<EOF
$(printf '%s' "$MESSAGE" | "$ROOT/bin/fm-pi-admission.sh" hash)
EOF
"$ROOT/bin/fm-pi-admission.sh" match "$(cd "$STATE" && pwd -P)" "$ID" \
  --gen "$GEN" --after 0 --sha256 "$hash" --bytes "$bytes" \
  || fail "real Pi did not publish its exact current-generation admission receipt"
pass "real guarded Pi/Herdr busy steer appears exactly once, returns success, and stays working before and after"
