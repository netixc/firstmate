#!/usr/bin/env bash
# Real Pi/Herdr regression for truthful fm-send results while Pi remains busy.
#
# This opt-in guard keeps a faithful provider response open after every tested
# Enter, sends through public fm-send, and releases the response only after the
# synchronous verdicts are recorded.
# It proves that Pi's earlier input event, transformed input, and handled input
# never become queue-acceptance success, while one ordinary queued steer is
# processed exactly once after release.
# Every Herdr call routes through bin/fm-herdr-lab.sh and its named-session
# default-fleet tripwire.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "${FM_SEND_BUSY_PI_HERDR_E2E:-0}" != 1 ]; then
  echo "skip: set FM_SEND_BUSY_PI_HERDR_E2E=1 to run the real busy-Pi fm-send regression"
  exit 0
fi
for tool in herdr jq node pi; do
  command -v "$tool" >/dev/null 2>&1 || { echo "skip: $tool not found"; exit 0; }
done

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
case "$LAB_HELPER" in /*) ;; *) LAB_HELPER="$ROOT/$LAB_HELPER" ;; esac
SESSION=$($LAB_HELPER name fm-send-busy-pi)
TMP_ROOT=$(fm_test_tmproot fm-send-busy-pi-herdr-e2e)
HOME_DIR="$TMP_ROOT/home"
STATE="$HOME_DIR/state"
PROJECT="$TMP_ROOT/project"
PI_DIR="$TMP_ROOT/pi-agent"
FAKEBIN="$TMP_ROOT/fakebin"
EVENTS="$TMP_ROOT/pi-events.jsonl"
RELEASE="$TMP_ROOT/release"
ORIGINAL_PATH=$PATH
PI_VERSION=$(pi --version 2>/dev/null || true)
ID=busy-pi-live
HOLD="FM_SEND_BUSY_HOLD_$$_${RANDOM:-0}"
HANDLED="FM_SEND_BUSY_HANDLED_$$_${RANDOM:-0}"
TRANSFORM_INPUT="FM_SEND_BUSY_TRANSFORM_$$_${RANDOM:-0}"
TRANSFORMED="FM_SEND_BUSY_TRANSFORMED_$$_${RANDOM:-0}"
STEER="FM_SEND_BUSY_STEER_$$_${RANDOM:-0}"
PANE=

[ -n "$PI_VERSION" ] || fail "real busy-send guard could not determine the installed Pi version"

cleanup() {
  local rc=$?
  trap - EXIT
  if ! "$LAB_HELPER" teardown "$SESSION"; then
    rc=1
  fi
  if [ "${FM_TEST_KEEP:-0}" = 1 ]; then
    echo "kept real busy-send fixture at $TMP_ROOT" >&2
  else
    rm -rf "$TMP_ROOT"
  fi
  exit "$rc"
}
trap cleanup EXIT
"$LAB_HELPER" provision "$SESSION" || fail "Pi $PI_VERSION busy-send guard could not provision its isolated Herdr lab"

mkdir -p "$HOME_DIR"/{state,data,config,projects} "$PROJECT" "$PI_DIR" "$FAKEBIN"
printf '# Isolated real busy-send regression\n' > "$PROJECT/AGENTS.md"
touch "$STATE/.last-watcher-beat"

# Production Herdr calls append a validated trailing session pair, while
# generation-bound calls carry only the exact session environment and socket.
# Strip only the former and route both forms through the guarded helper.
cat > "$FAKEBIN/herdr" <<EOF
#!/usr/bin/env bash
set -euo pipefail
helper='$LAB_HELPER'
session='$SESSION'
real_path='$ORIGINAL_PATH'
args=("\$@")
n=\${#args[@]}
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "\$session" ] || { echo 'wrapper refused foreign session' >&2; exit 97; }
  args=("\${args[@]:0:\$((n-2))}")
else
  [ "\${HERDR_SESSION:-}" = "\$session" ] || { echo 'wrapper requires isolated session' >&2; exit 98; }
  for arg in "\${args[@]}"; do
    case "\$arg" in
      --session|--session=*) echo 'wrapper refused non-trailing session flag' >&2; exit 99 ;;
    esac
  done
fi
PATH="\$real_path" exec "\$helper" run "\$session" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"

EVENTS_JSON=$(printf '%s' "$EVENTS" | jq -Rs .)
RELEASE_JSON=$(printf '%s' "$RELEASE" | jq -Rs .)
HANDLED_JSON=$(printf '%s' "$HANDLED" | jq -Rs .)
TRANSFORM_INPUT_JSON=$(printf '%s' "$TRANSFORM_INPUT" | jq -Rs .)
TRANSFORMED_JSON=$(printf '%s' "$TRANSFORMED" | jq -Rs .)
PROVIDER_EXT="$TMP_ROOT/busy-provider.ts"
cat > "$PROVIDER_EXT" <<EOF
import {
  type AssistantMessage,
  createAssistantMessageEventStream,
} from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync, existsSync } from "node:fs";

const eventsPath = $EVENTS_JSON;
const releasePath = $RELEASE_JSON;
const handled = $HANDLED_JSON;
const transformInput = $TRANSFORM_INPUT_JSON;
const transformed = $TRANSFORMED_JSON;
let providerCalls = 0;
const record = (event: string, text: string, extra: Record<string, unknown> = {}) =>
  appendFileSync(eventsPath, JSON.stringify({ event, text, ...extra }) + "\\n");
const userText = (message: any): string | undefined => {
  if (!message || message.role !== "user") return;
  if (typeof message.content === "string") return message.content;
  if (!Array.isArray(message.content) || message.content.length !== 1) return;
  const block = message.content[0];
  if (!block || block.type !== "text" || typeof block.text !== "string") return;
  return block.text;
};

export default function (pi: ExtensionAPI): void {
  pi.on("project_trust", () => ({ trusted: "yes", remember: false }));
  pi.on("input", (event) => {
    record("input", event.text, { source: event.source, streamingBehavior: event.streamingBehavior ?? null });
    if (event.text === handled) return { action: "handled" as const };
    if (event.text === transformInput) return { action: "transform" as const, text: transformed };
    return { action: "continue" as const };
  });
  pi.on("before_agent_start", (event) => record("before_agent_start", event.prompt));
  pi.on("message_start", (event) => {
    const text = userText(event.message);
    if (text !== undefined) record("message_start_user", text);
  });
  pi.registerProvider("fm-busy-send-fixture", {
    baseUrl: "http://127.0.0.1/unused",
    apiKey: "isolated-test-only",
    api: "fm-busy-send-fixture-api",
    models: [{
      id: "hold",
      name: "Isolated busy-send fixture",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 131072,
      maxTokens: 128,
    }],
    streamSimple(model) {
      providerCalls += 1;
      const call = providerCalls;
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
        const block = { type: "text" as const, text: call === 1 ? "provider response remains active" : "queued input processed" };
        output.content.push(block);
        stream.push({ type: "text_start", contentIndex: 0, partial: output });
        stream.push({ type: "text_delta", contentIndex: 0, delta: block.text, partial: output });
        const finish = () => {
          stream.push({ type: "text_end", contentIndex: 0, content: block.text, partial: output });
          stream.push({ type: "done", reason: "stop", message: output });
          stream.end();
        };
        if (call === 1) {
          const timer = setInterval(() => {
            if (!existsSync(releasePath)) return;
            clearInterval(timer);
            finish();
          }, 25);
        } else {
          setTimeout(finish, 25);
        }
      });
      return stream;
    },
  });
}
EOF

CREATE=$($LAB_HELPER run "$SESSION" workspace create --cwd "$PROJECT" --label fm-send-busy-pi --no-focus) \
  || fail "Pi $PI_VERSION busy-send guard could not create its isolated workspace"
WORKSPACE=$(printf '%s' "$CREATE" | jq -r '.result.workspace.workspace_id // empty')
TAB=$(printf '%s' "$CREATE" | jq -r '.result.tab.tab_id // empty')
PANE=$(printf '%s' "$CREATE" | jq -r '.result.root_pane.pane_id // empty')
[ -n "$WORKSPACE" ] && [ -n "$TAB" ] && [ -n "$PANE" ] \
  || fail "Pi $PI_VERSION busy-send guard did not receive exact Herdr endpoint identity"
TARGET="$SESSION:$PANE"

PI_CMD=$(printf 'exec env PI_CODING_AGENT_DIR=%q pi -e %q --provider fm-busy-send-fixture --model hold --no-context-files %q' \
  "$PI_DIR" "$PROVIDER_EXT" "$HOLD")
$LAB_HELPER run "$SESSION" pane run "$PANE" "$PI_CMD" >/dev/null \
  || fail "Pi $PI_VERSION busy-send guard could not launch real Pi"

wait_for_native() { # <wanted>
  local wanted=$1 status _ stable=0
  for _ in $(seq 1 240); do
    status=$($LAB_HELPER run "$SESSION" agent get "$PANE" 2>/dev/null \
      | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)
    if [ "$status" = "$wanted" ]; then
      stable=$((stable + 1))
      [ "$stable" -ge 3 ] && return 0
    else
      stable=0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_event_count() { # <event> <text> <count>
  local event=$1 text=$2 want=$3 got _
  for _ in $(seq 1 240); do
    got=$(jq -r --arg event "$event" --arg text "$text" \
      'select(.event == $event and .text == $text) | .event' "$EVENTS" 2>/dev/null | wc -l | tr -d ' ')
    [ "$got" -eq "$want" ] && return 0
    sleep 0.25
  done
  return 1
}

event_count() { # <event> <text>
  jq -r --arg event "$1" --arg text "$2" \
    'select(.event == $event and .text == $text) | .event' "$EVENTS" 2>/dev/null | wc -l | tr -d ' '
}

wait_for_event_count before_agent_start "$HOLD" 1 \
  || fail "Pi $PI_VERSION did not start the held provider turn"
wait_for_native working || fail "Pi $PI_VERSION did not remain working on the held provider response"

cat > "$STATE/$ID.meta" <<EOF
window=$TARGET
backend=herdr
kind=ship
mode=no-mistakes
harness=pi
endpoint_task_id=$ID
herdr_session=$SESSION
herdr_workspace_id=$WORKSPACE
herdr_tab_id=$TAB
herdr_pane_id=$PANE
worktree=$PROJECT
project=$PROJECT
EOF

run_unconfirmed_send() { # <message> <label>
  local message=$1 label=$2 out rc
  out=$(PATH="$FAKEBIN:$ORIGINAL_PATH" HERDR_SESSION="$SESSION" FM_HOME="$HOME_DIR" \
    FM_ROOT_OVERRIDE="$ROOT" FM_GATE_REFUSE_BYPASS=1 FM_SEND_RETRIES=1 FM_SEND_SLEEP=0.1 FM_SEND_SETTLE=0 \
    "$ROOT/bin/fm-send.sh" "$ID" "$message" 2>&1)
  rc=$?
  expect_code 3 "$rc" "Pi $PI_VERSION $label did not preserve delivered-but-unconfirmed status: $out"
  assert_contains "$out" 'submission is unconfirmed (verdict=unknown' \
    "Pi $PI_VERSION $label did not report truthful unknown confirmation"
  assert_contains "$out" 'do not retype or blindly resend' \
    "Pi $PI_VERSION $label invited a duplicate full-text send"
  assert_not_contains "$out" 'text not submitted' \
    "Pi $PI_VERSION $label made the disproven non-submission claim"
  wait_for_native working || fail "Pi $PI_VERSION provider response stopped during $label"
}

run_unconfirmed_send "$HANDLED" 'handled input'
run_unconfirmed_send "$TRANSFORM_INPUT" 'transformed input'
run_unconfirmed_send "$STEER" 'ordinary queued steer'

for text in "$HANDLED" "$TRANSFORM_INPUT" "$STEER"; do
  wait_for_event_count input "$text" 1 \
    || fail "Pi $PI_VERSION did not emit exactly one earlier input event for $text"
done
[ "$(event_count message_start_user "$HANDLED")" -eq 0 ] \
  || fail "Pi $PI_VERSION processed handled input as a user message"
[ "$(event_count message_start_user "$TRANSFORM_INPUT")" -eq 0 ] \
  || fail "Pi $PI_VERSION processed pre-transform input as an exact user message"
[ "$(event_count message_start_user "$STEER")" -eq 0 ] \
  || fail "Pi $PI_VERSION processed the ordinary steer before the held response was released"
pass "real Pi/Herdr: busy input, including transformed and handled input, stays unconfirmed while the provider response remains active"

touch "$RELEASE"
wait_for_event_count message_start_user "$TRANSFORMED" 1 \
  || fail "Pi $PI_VERSION did not process the transformed queued input exactly once after release"
wait_for_event_count message_start_user "$STEER" 1 \
  || fail "Pi $PI_VERSION did not process the ordinary queued steer exactly once after release"
wait_for_native idle || fail "Pi $PI_VERSION did not settle after processing the queued input"
[ "$(event_count message_start_user "$HANDLED")" -eq 0 ] \
  || fail "Pi $PI_VERSION later processed handled input"
[ "$(event_count message_start_user "$TRANSFORM_INPUT")" -eq 0 ] \
  || fail "Pi $PI_VERSION later processed the pre-transform payload"
[ "$(event_count message_start_user "$TRANSFORMED")" -eq 1 ] \
  || fail "Pi $PI_VERSION processed transformed input more than once"
[ "$(event_count message_start_user "$STEER")" -eq 1 ] \
  || fail "Pi $PI_VERSION processed the ordinary steer more than once"
HERDR_VERSION=$(herdr --version)
printf 'evidence: Pi %s; Herdr %s; input-before-release=1; handled-processed=0; transformed-processed=1; ordinary-steer-processed=1\n' \
  "$PI_VERSION" "${HERDR_VERSION#herdr }"
pass "real Pi/Herdr: release processes the one ordinary busy steer exactly once without resurrecting handled or pre-transform input"
