#!/usr/bin/env bash
# Event-level regressions for Pi primary-session continuity: the deterministic
# session claim, the single-flight operational-turn latch, action accounting,
# and the compact provenance boundary. Every case runs against a fake Pi that
# dispatches handler LISTS the way Pi's extension runner does, in a throwaway
# primary-shaped repo and home; nothing here can reach the active firstmate home.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-pi-operational-turn)
export NODE_NO_WARNINGS=1

# Shared fake-Pi harness: handler lists, a real synchronous event bus (Pi uses a
# Node EventEmitter), entry/message capture, and the session-lock file the
# extensions read for ownership.
FAKE_PI=$(cat <<'JS'
import { writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export function createFakePi() {
  const handlers = new Map();
  const listeners = new Map();
  const state = {
    prompts: [],
    messages: [],
    entries: [],
    notifications: [],
    tools: new Map(),
    renderers: new Map(),
    deliver: null,
  };
  const pi = {
    events: {
      emit(channel, data) {
        for (const listener of listeners.get(channel) ?? []) listener(data);
      },
      on(channel, listener) {
        const list = listeners.get(channel) ?? [];
        list.push(listener);
        listeners.set(channel, list);
        return () => {};
      },
    },
    on(event, handler) {
      const list = handlers.get(event) ?? [];
      list.push(handler);
      handlers.set(event, list);
    },
    registerCommand() {},
    registerTool(tool) {
      state.tools.set(tool.name, tool);
    },
    registerEntryRenderer(customType, renderer) {
      state.renderers.set(customType, renderer);
    },
    appendEntry(customType, data) {
      state.entries.push({ customType, data });
    },
    sendMessage(message, options) {
      state.messages.push({ message, options });
    },
    async sendUserMessage(content, options) {
      state.prompts.push({ content, options });
      if (state.deliver) await state.deliver(content);
    },
  };
  const ctx = { ui: { notify(message, level) { state.notifications.push({ message, level }); } } };
  const dispatch = async (event, payload) => {
    let result;
    for (const handler of handlers.get(event) ?? []) {
      const handled = await handler(payload, ctx);
      if (handled) result = handled;
    }
    return result;
  };
  const toolCall = async (command, isError = false) => {
    const result = await dispatch("tool_call", { type: "tool_call", toolName: "bash", input: { command } });
    if (!result?.block) {
      await dispatch("tool_result", {
        type: "tool_result",
        toolCallId: "fixture-bash",
        toolName: "bash",
        input: { command },
        content: [],
        details: undefined,
        isError,
      });
    }
    return result;
  };
  const settle = () => dispatch("agent_settled", { type: "agent_settled" });
  return { pi, ctx, state, handlers, dispatch, toolCall, settle };
}

export async function loadExtension(path, pi) {
  const mod = await import(pathToFileURL(path).href);
  mod.default(pi);
}

export function claimLock(home, pid) {
  writeFileSync(`${home}/state/.lock`, `${pid}\n`);
}
JS
)

install_fixture() {  # <repo> [extensions...]
  local repo=$1
  shift
  mkdir -p \
    "$repo/.pi/extensions/lib" \
    "$repo/bin" \
    "$repo/node_modules/@earendil-works/pi-coding-agent" \
    "$repo/node_modules/@earendil-works/pi-tui" \
    "$repo/node_modules/typebox"
  cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" "$repo/.pi/extensions/lib/"
  cp "$ROOT/.pi/extensions/lib/fm-operational-turn.ts" "$repo/.pi/extensions/lib/"
  cp "$ROOT/.pi/extensions/lib/fm-calm-visibility.ts" "$repo/.pi/extensions/lib/"
  cp "$ROOT/bin/fm-operational-input.sh" "$repo/bin/"
  chmod +x "$repo/bin/fm-operational-input.sh"
  local ext
  for ext in "$@"; do
    cp "$ROOT/.pi/extensions/$ext" "$repo/.pi/extensions/"
  done
  cat > "$repo/node_modules/@earendil-works/pi-coding-agent/package.json" <<'JSON'
{"name":"@earendil-works/pi-coding-agent","type":"module","exports":"./index.js"}
JSON
  cat > "$repo/node_modules/@earendil-works/pi-coding-agent/index.js" <<'JS'
export function getMarkdownTheme() { return {}; }
export class UserMessageComponent {
  constructor(content) { this.content = content; }
  render() { return [this.content]; }
  invalidate() {}
}
JS
  cat > "$repo/node_modules/@earendil-works/pi-tui/package.json" <<'JSON'
{"name":"@earendil-works/pi-tui","type":"module","exports":"./index.js"}
JSON
  cat > "$repo/node_modules/@earendil-works/pi-tui/index.js" <<'JS'
export class Box { addChild() {} clear() {} setBgFn() {} }
export class Container {}
export class Text { constructor(content) { this.content = content; } render() { return [this.content]; } }
export function getKeybindings() { return { matches: () => false }; }
JS
  cat > "$repo/node_modules/typebox/package.json" <<'JSON'
{"name":"typebox","type":"module","exports":"./index.js"}
JSON
  cat > "$repo/node_modules/typebox/index.js" <<'JS'
export const Type = { Object(properties) { return { type: "object", properties }; } };
JS
  printf '%s\n' "$FAKE_PI" > "$repo/fake-pi.mjs"
}

install_session_start_fixture() {  # <repo> <mode>
  local repo=$1 mode=$2
  cp "$ROOT/bin/fm-sessionstart-nudge.sh" \
     "$ROOT/bin/fm-primary-scope-lib.sh" \
     "$ROOT/bin/fm-gate-refuse-lib.sh" \
     "$repo/bin/"
  chmod +x "$repo/bin/fm-sessionstart-nudge.sh"
  printf '# Fixture primary\n' > "$repo/AGENTS.md"
  git init -q "$repo"
  if [ "$mode" = failing ]; then
    cat > "$repo/bin/fm-session-start.sh" <<'SH'
#!/usr/bin/env bash
printf 'fixture session start refused\n' >&2
exit 3
SH
  elif [ "$mode" = timeout ]; then
    cat > "$repo/bin/fm-session-start.sh" <<'SH'
#!/usr/bin/env bash
set -u
trap '' TERM
(
  trap '' TERM
  printf '%s\n' "$BASHPID" > "${FM_HOME:?}/state/session-start-descendant"
  sleep 2
  printf 'escaped\n' > "${FM_HOME}/state/session-start-sentinel"
) &
wait
SH
  else
    cat > "$repo/bin/fm-session-start.sh" <<'SH'
#!/usr/bin/env bash
set -u
sleep "${FM_SESSION_START_FIXTURE_DELAY:-0}"
file="${FM_HOME:?}/state/session-start-count"
count=0
[ ! -f "$file" ] || count=$(sed -n '1p' "$file")
count=$((count + 1))
printf '%s\n' "$count" > "$file"
# Stand in for bin/fm-lock.sh: record the harness process that owns this home.
printf '%s\n' "$PPID" > "${FM_HOME}/state/.lock"
printf 'FIXTURE DIGEST LINE ONE count=%s\nFIXTURE DIGEST LINE TWO\n' "$count"
SH
  fi
  chmod +x "$repo/bin/fm-session-start.sh"
  cat > "$repo/bin/fm-arm-pretool-check.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cp "$repo/bin/fm-arm-pretool-check.sh" "$repo/bin/fm-cd-pretool-check.sh"
  chmod +x "$repo/bin/fm-arm-pretool-check.sh" "$repo/bin/fm-cd-pretool-check.sh"
}

write_guard() {  # <repo> <exit-code>
  cat > "$1/bin/fm-turnend-guard.sh" <<SH
#!/usr/bin/env bash
cat >/dev/null
printf 'fixture guard reason\n' >&2
exit $2
SH
  chmod +x "$1/bin/fm-turnend-guard.sh"
}

# --- deterministic session claim --------------------------------------------

test_session_claim_runs_before_any_answer_completes() {
  local repo home out status
  repo="$TMP_ROOT/claim-root"
  home="$TMP_ROOT/claim-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 0
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_SESSION_START_FIXTURE_DELAY=0.12 node --input-type=module 2>&1 <<'EOF'
import { existsSync, readFileSync } from "node:fs";
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, dispatch, settle } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);

const startedAt = Date.now();
await dispatch("session_start", { type: "session_start", reason: "startup" });
if (Date.now() - startedAt < 100) throw new Error("session_start returned before the claim lifecycle completed");
// A resumed runtime raising session_start twice must not start a second claim.
await dispatch("session_start", { type: "session_start", reason: "resume" });

const countFile = `${process.env.FM_HOME}/state/session-start-count`;
if (!existsSync(countFile)) throw new Error("the Pi runtime answered without claiming the session");
const count = readFileSync(countFile, "utf8").trim();
if (count !== "1") throw new Error(`session start ran ${count} times for one Pi runtime`);
if (state.messages.length !== 1) throw new Error(`expected one context delivery, saw ${state.messages.length}`);
const delivered = state.messages[0];
if (delivered.message.display !== false) throw new Error("session-start context was not delivered hidden");
if (delivered.options !== undefined) throw new Error("session-start context started a turn and can race Pi's positional prompt");
if (!delivered.message.content.startsWith("⁣FIRSTMATE_OP: v1 session-start: ")) {
  throw new Error(`session-start context is not typed operational input: ${delivered.message.content.slice(0, 80)}`);
}
if (!delivered.message.content.includes("FIXTURE DIGEST LINE ONE")
  || !delivered.message.content.includes("FIXTURE DIGEST LINE TWO")) {
  throw new Error("the complete session-start digest did not reach model context");
}
if (!delivered.message.content.includes("Do not run it again")) {
  throw new Error("the claim did not tell the model session start already ran");
}
await settle();
EOF
)
  status=$?
  expect_code 0 "$status" "Pi must claim the session deterministically before an answer completes"
  [ -z "$out" ] || fail "session claim test printed output: $out"
  pass "Pi session claim: one guarded lifecycle per runtime, complete digest in context"
}

test_session_claim_arms_one_initial_cycle() {
  local repo home out status
  repo="$TMP_ROOT/claim-arm-root"
  home="$TMP_ROOT/claim-arm-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts fm-primary-pi-watch.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 2
  cat > "$repo/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf 'arm\n' >> "${FM_ARM_LOG:?}"
printf 'watcher: started pid=%s (beacon fresh)\n' "$$"
trap 'exit 0' TERM INT
# Bounded so a fixture arm can never outlive its test.
for _ in $(seq 1 60); do sleep 0.1; done
SH
  chmod +x "$repo/bin/fm-watch-arm.sh"
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_ARM_LOG="$TMP_ROOT/claim-arm.log" node --input-type=module 2>&1 <<'EOF'
import { existsSync, readFileSync } from "node:fs";
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, dispatch } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-pi-watch.ts`, pi);

await dispatch("session_start", { type: "session_start", reason: "startup" });
for (let i = 0; i < 400; i += 1) {
  if (existsSync(process.env.FM_ARM_LOG)) break;
  await new Promise((resolve) => setTimeout(resolve, 10));
}
if (!existsSync(process.env.FM_ARM_LOG)) throw new Error("the claim did not start the initial watcher cycle");
// A second request is the same ownership-based no-op a redundant tool call is.
pi.events.emit("firstmate:arm-request", { reason: "session-start" });
await new Promise((resolve) => setTimeout(resolve, 120));
const arms = readFileSync(process.env.FM_ARM_LOG, "utf8").trim().split("\n").length;
if (arms !== 1) throw new Error(`claim started ${arms} watcher cycles`);
// Leave no attached arm child holding this fixture process open.
process.exit(0);
EOF
)
  status=$?
  expect_code 0 "$status" "the Pi session claim must start exactly one initial watcher cycle"
  [ -z "$out" ] || fail "claim-arm test printed output: $out"
  pass "Pi session claim: exactly one extension-owned initial watcher cycle"
}

test_session_claim_failure_falls_back_to_the_advisory_nudge() {
  local repo home out status
  repo="$TMP_ROOT/claim-fail-root"
  home="$TMP_ROOT/claim-fail-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" failing
  write_guard "$repo" 0
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" node --input-type=module 2>&1 <<'EOF'
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, dispatch, settle } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
await dispatch("session_start", { type: "session_start", reason: "startup" });
await settle();
if (state.messages.length !== 1) throw new Error(`expected one fallback delivery, saw ${state.messages.length}`);
const content = state.messages[0].message.content;
if (!content.includes("Run `bin/fm-session-start.sh` now, exactly once")) {
  throw new Error(`a failed claim did not fall back to the advisory instruction: ${content}`);
}
if (!content.includes("could not run it for you")) {
  throw new Error("a failed claim hid the reason from the model");
}
EOF
)
  status=$?
  expect_code 0 "$status" "a failed Pi session claim must fall back to the advisory nudge"
  [ -z "$out" ] || fail "claim-failure test printed output: $out"
  pass "Pi session claim: a failed lifecycle degrades to the advisory instruction"
}

test_session_claim_timeout_reaps_the_process_tree() {
  local repo home out status
  repo="$TMP_ROOT/claim-timeout-root"
  home="$TMP_ROOT/claim-timeout-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" timeout
  write_guard "$repo" 0
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_PI_SESSION_START_TIMEOUT_MS=100 \
    FM_PI_SESSION_START_KILL_GRACE_MS=50 node --input-type=module 2>&1 <<'EOF'
import { existsSync, readFileSync } from "node:fs";
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, dispatch } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
const startedAt = Date.now();
await dispatch("session_start", { type: "session_start", reason: "startup" });
if (Date.now() - startedAt < 140) throw new Error("timeout returned before process-tree escalation");
const descendant = Number(readFileSync(`${process.env.FM_HOME}/state/session-start-descendant`, "utf8").trim());
try {
  process.kill(descendant, 0);
  throw new Error(`session-start descendant ${descendant} survived timeout`);
} catch (error) {
  if ((error).message?.includes("survived timeout")) throw error;
}
if (existsSync(`${process.env.FM_HOME}/state/session-start-sentinel`)) {
  throw new Error("session-start descendant mutated state after timeout");
}
if (state.messages.length !== 1
  || !state.messages[0].message.content.includes("process tree was terminated")) {
  throw new Error("the confirmed timeout was not delivered to model context");
}
EOF
)
  status=$?
  expect_code 0 "$status" "a timed-out Pi session claim must reap its complete process tree"
  [ -z "$out" ] || fail "session claim timeout test printed output: $out"
  pass "Pi session claim: timeout escalation reaps the complete process tree"
}

test_session_claim_runtime_cleanup_reaps_the_process_tree() {
  local repo home exit_repo exit_home out status descendant
  repo="$TMP_ROOT/claim-shutdown-root"
  home="$TMP_ROOT/claim-shutdown-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" timeout
  write_guard "$repo" 0
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" node --input-type=module 2>&1 <<'EOF'
import { existsSync, readFileSync } from "node:fs";
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, dispatch } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
const pending = dispatch("session_start", { type: "session_start", reason: "startup" });
for (let index = 0; index < 100; index += 1) {
  if (existsSync(`${process.env.FM_HOME}/state/session-start-descendant`)) break;
  await new Promise((resolve) => setTimeout(resolve, 10));
}
await dispatch("session_shutdown", { type: "session_shutdown" });
await pending;
const descendant = Number(readFileSync(`${process.env.FM_HOME}/state/session-start-descendant`, "utf8").trim());
try {
  process.kill(descendant, 0);
  throw new Error(`session-start descendant ${descendant} survived session shutdown`);
} catch (error) {
  if ((error).message?.includes("survived session shutdown")) throw error;
}
EOF
)
  status=$?
  expect_code 0 "$status" "Pi session shutdown must reap the active session-start process tree"
  [ -z "$out" ] || fail "session shutdown cleanup test printed output: $out"

  exit_repo="$TMP_ROOT/claim-exit-root"
  exit_home="$TMP_ROOT/claim-exit-home"
  mkdir -p "$exit_home/state" "$exit_home/config"
  install_fixture "$exit_repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$exit_repo" timeout
  write_guard "$exit_repo" 0
  out=$(REPO="$exit_repo" FM_HOME="$exit_home" FM_ROOT_OVERRIDE="$exit_repo" node --input-type=module 2>&1 <<'EOF'
import { existsSync } from "node:fs";
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, dispatch } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
void dispatch("session_start", { type: "session_start", reason: "startup" });
for (let index = 0; index < 100; index += 1) {
  if (existsSync(`${process.env.FM_HOME}/state/session-start-descendant`)) break;
  await new Promise((resolve) => setTimeout(resolve, 10));
}
process.exit(0);
EOF
)
  status=$?
  expect_code 0 "$status" "Pi process exit must reap the active session-start process tree"
  [ -z "$out" ] || fail "process-exit cleanup test printed output: $out"
  descendant=$(sed -n '1p' "$exit_home/state/session-start-descendant")
  for _ in $(seq 1 100); do
    kill -0 "$descendant" 2>/dev/null || break
    sleep 0.01
  done
  if kill -0 "$descendant" 2>/dev/null; then
    fail "process-exit cleanup left session-start descendant $descendant alive"
  fi
  pass "Pi session claim: shutdown and process exit reap the active process tree"
}

test_session_claim_autorun_can_be_disabled() {
  local repo home out status
  repo="$TMP_ROOT/claim-off-root"
  home="$TMP_ROOT/claim-off-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 0
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_PI_SESSION_START_AUTORUN=0 node --input-type=module 2>&1 <<'EOF'
import { existsSync } from "node:fs";
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, dispatch, settle } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
await dispatch("session_start", { type: "session_start", reason: "startup" });
await settle();
// This is the pre-fix behavior the incident reproduced: a hidden, non-triggering
// instruction and no claim at all when the model does not obey it.
if (existsSync(`${process.env.FM_HOME}/state/session-start-count`)) {
  throw new Error("FM_PI_SESSION_START_AUTORUN=0 still ran the lifecycle");
}
if (state.messages.length !== 1
  || !state.messages[0].message.content.includes("Run `bin/fm-session-start.sh` now, exactly once")) {
  throw new Error("the advisory fallback did not deliver the wrapper instruction");
}
EOF
)
  status=$?
  expect_code 0 "$status" "FM_PI_SESSION_START_AUTORUN=0 must restore the advisory-only path"
  [ -z "$out" ] || fail "autorun-off test printed output: $out"
  pass "Pi session claim: the advisory-only path stays available as a documented fallback"
}

# --- single-flight operational turns ----------------------------------------

test_signal_and_stale_while_busy_coalesce_into_one_turn() {
  local repo home out status
  repo="$TMP_ROOT/coalesce-root"
  home="$TMP_ROOT/coalesce-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts fm-primary-pi-watch.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 0
  cat > "$repo/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
count=0
[ ! -f "${FM_ARM_LOG:?}" ] || count=$(wc -l < "$FM_ARM_LOG" | tr -d '[:space:]')
printf 'arm\n' >> "$FM_ARM_LOG"
printf 'watcher: started pid=%s (beacon fresh)\n' "$$"
if [ "$count" -eq 0 ]; then printf 'signal: alpha.status\n'; exit 0; fi
if [ "$count" -eq 1 ]; then printf 'stale: beta deep-inspection\n'; exit 0; fi
trap 'exit 0' TERM INT
# Bounded so a fixture arm can never outlive its test.
for _ in $(seq 1 60); do sleep 0.1; done
SH
  chmod +x "$repo/bin/fm-watch-arm.sh"
  printf '1784835678\t710\tsignal\talpha\tdone: alpha\n1784835679\t711\tstale\tbeta\tstale 900s\n' \
    > "$home/state/.wake-queue"
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_ARM_LOG="$TMP_ROOT/coalesce.log" \
    FM_PI_ARM_READY_TIMEOUT_MS=2000 node --input-type=module 2>&1 <<'EOF'
import { existsSync, readFileSync, writeFileSync } from "node:fs";
const { createFakePi, loadExtension, claimLock } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, settle, toolCall } = createFakePi();
claimLock(process.env.FM_HOME, process.pid);
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-pi-watch.ts`, pi);

const tool = state.tools.get("fm_watch_arm_pi");
await tool.execute("call-1", {}, undefined, undefined, {});
// Both actionable closes land while the turn that will handle them is busy.
for (let i = 0; i < 500; i += 1) {
  const rows = existsSync(process.env.FM_ARM_LOG)
    ? readFileSync(process.env.FM_ARM_LOG, "utf8").trim().split("\n").length
    : 0;
  if (rows >= 3) break;
  await new Promise((resolve) => setTimeout(resolve, 10));
}
await new Promise((resolve) => setTimeout(resolve, 150));
if (state.prompts.length !== 1) {
  throw new Error(`signal + stale queued ${state.prompts.length} operational turns`);
}
if (!state.prompts[0].content.startsWith("⁣FIRSTMATE_OP: v1 watcher: ")) {
  throw new Error("the coalesced wake lost its typed operational envelope");
}
// One operational turn drains every durable record, so the settle owner has no
// reason to start a second one.
await toolCall("bin/fm-wake-drain.sh");
writeFileSync(`${process.env.FM_HOME}/state/.wake-queue`, "");
await settle();
if (state.prompts.length !== 1) {
  throw new Error(`the settle owner queued an extra turn for already drained records: ${state.prompts.length}`);
}
if (!existsSync(process.env.FM_ARM_LOG)) throw new Error("supervision continuity was lost");
// Leave no attached arm child holding this fixture process open.
process.exit(0);
EOF
)
  status=$?
  expect_code 0 "$status" "signal plus stale during a busy turn must coalesce into one operational turn"
  [ -z "$out" ] || fail "coalescing test printed output: $out"
  pass "Pi operational turns: signal + stale during a busy turn produce one follow-up and one drain"
}

test_records_queued_after_the_drain_get_exactly_one_more_turn() {
  local repo home out status
  repo="$TMP_ROOT/requeue-root"
  home="$TMP_ROOT/requeue-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts fm-primary-pi-watch.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 0
  cat > "$repo/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
count=0
[ ! -f "${FM_ARM_LOG:?}" ] || count=$(wc -l < "$FM_ARM_LOG" | tr -d '[:space:]')
printf 'arm\n' >> "$FM_ARM_LOG"
printf 'watcher: started pid=%s (beacon fresh)\n' "$$"
if [ "$count" -eq 0 ]; then printf 'check: pr-merge alpha\n'; exit 0; fi
trap 'exit 0' TERM INT
# Bounded so a fixture arm can never outlive its test.
for _ in $(seq 1 60); do sleep 0.1; done
SH
  chmod +x "$repo/bin/fm-watch-arm.sh"
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_ARM_LOG="$TMP_ROOT/requeue.log" \
    node --input-type=module 2>&1 <<'EOF'
import { writeFileSync } from "node:fs";
const { createFakePi, loadExtension, claimLock } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, settle, toolCall } = createFakePi();
claimLock(process.env.FM_HOME, process.pid);
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-pi-watch.ts`, pi);
const tool = state.tools.get("fm_watch_arm_pi");
await tool.execute("call-1", {}, undefined, undefined, {});
for (let i = 0; i < 500; i += 1) {
  if (state.prompts.length >= 1) break;
  await new Promise((resolve) => setTimeout(resolve, 10));
}
await toolCall("bin/fm-wake-drain.sh");
// An X-mode check record arrives after this turn already drained.
writeFileSync(`${process.env.FM_HOME}/state/.wake-queue`, "1784835999\t712\tcheck\tx-mention\tx-mention 42\n");
await settle();
if (state.prompts.length !== 2) {
  throw new Error(`records queued after the drain got ${state.prompts.length - 1} follow-ups`);
}
writeFileSync(`${process.env.FM_HOME}/state/.wake-queue`, "");
await toolCall("bin/fm-wake-drain.sh");
await settle();
if (state.prompts.length !== 2) throw new Error("the settle owner kept generating turns for an empty queue");
// Leave no attached arm child holding this fixture process open.
process.exit(0);
EOF
)
  status=$?
  expect_code 0 "$status" "records queued after a drain must get exactly one more operational turn"
  [ -z "$out" ] || fail "re-queue test printed output: $out"
  pass "Pi operational turns: durable records queued after a drain get one more follow-up"
}

test_continuity_failure_survives_coalescing() {
  local repo home out status
  repo="$TMP_ROOT/failure-root"
  home="$TMP_ROOT/failure-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts fm-primary-pi-watch.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 0
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" node --input-type=module 2>&1 <<'EOF'
const { createFakePi, loadExtension, claimLock } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, settle, toolCall } = createFakePi();
claimLock(process.env.FM_HOME, process.pid);
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-pi-watch.ts`, pi);

// One operational turn is in flight; a typed continuity failure arrives behind
// it. No durable queue record can replay that text, so it must survive.
pi.events.emit("firstmate:operational-turn", {
  active: true, kind: "watcher", claimedAtMs: Date.now(), deferred: [], attempts: 0, actionPerformed: false,
});
pi.events.emit("firstmate:operational-turn", {
  active: true,
  kind: "watcher",
  claimedAtMs: Date.now(),
  deferred: ["watcher: FAILED - Pi extension could not restore watcher continuity after 5 retries"],
  attempts: 0,
  actionPerformed: false,
});
await toolCall("bin/fm-wake-drain.sh");
await settle();
if (state.prompts.length !== 1) throw new Error(`expected one carried follow-up, saw ${state.prompts.length}`);
if (!state.prompts[0].content.includes("could not restore watcher continuity")) {
  throw new Error(`the coalesced continuity failure was dropped: ${state.prompts[0].content}`);
}
EOF
)
  status=$?
  expect_code 0 "$status" "a coalesced continuity failure must still reach the model"
  [ -z "$out" ] || fail "continuity-failure carry test printed output: $out"
  pass "Pi operational turns: a coalesced continuity failure is carried, never dropped"
}

# --- action accounting and bounded failure ----------------------------------

test_repeating_the_previous_answer_is_a_failed_delivery() {
  local repo home out status
  repo="$TMP_ROOT/repeat-root"
  home="$TMP_ROOT/repeat-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 2
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_PI_SESSION_START_AUTORUN=0 node --input-type=module 2>&1 <<'EOF'
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, settle } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);

// Fixture model: every operational turn answers by repeating the same final and
// calling no tool at all - the exact behavior the incident recorded.
const finals = [];
state.deliver = async () => {
  finals.push("Captain, monitoring is restored.");
  await settle();
};
await settle();

if (state.prompts.length !== 2) {
  throw new Error(`bounded retry produced ${state.prompts.length} operational turns`);
}
if (!state.prompts[1].content.includes("OPERATIONAL DELIVERY NOT CARRIED OUT")) {
  throw new Error(`the retry did not name the failed delivery: ${state.prompts[1].content}`);
}
if (state.notifications.length !== 1 || state.notifications[0].level !== "warning") {
  throw new Error(`expected one compact escalation, saw ${JSON.stringify(state.notifications)}`);
}
const escalations = state.entries.filter((entry) => entry.customType === "firstmate-operational-escalation");
if (escalations.length !== 1 || !escalations[0].data.message.includes("stopped retrying")) {
  throw new Error(`escalation provenance was not recorded: ${JSON.stringify(state.entries)}`);
}
if (!state.renderers.has("firstmate-operational-escalation")) {
  throw new Error("the escalation row has no renderer, so the captain would never see it");
}
// Bounded: three repeated finals is the ceiling, not an unbounded recursion.
if (finals.length !== 2) throw new Error(`fixture model was re-prompted ${finals.length} times`);
EOF
)
  status=$?
  expect_code 0 "$status" "an operational turn that only repeats the previous answer must fail boundedly"
  [ -z "$out" ] || fail "repeated-answer test printed output: $out"
  pass "Pi operational turns: a repeated answer is a failed delivery with bounded retry then escalation"
}

test_performed_action_counts_as_delivery() {
  local repo home out status
  repo="$TMP_ROOT/action-root"
  home="$TMP_ROOT/action-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 2
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_PI_SESSION_START_AUTORUN=0 node --input-type=module 2>&1 <<'EOF'
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, settle, toolCall } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
state.deliver = async () => {
  await toolCall("bin/fm-wake-drain.sh");
  await settle();
};
await settle();
if (state.prompts.length !== 1) {
  throw new Error(`a compliant operational turn produced ${state.prompts.length} follow-ups`);
}
if (state.notifications.length !== 0) throw new Error("a compliant operational turn escalated");
EOF
)
  status=$?
  expect_code 0 "$status" "an operational turn that performs the action must count as delivered"
  [ -z "$out" ] || fail "performed-action test printed output: $out"
  pass "Pi operational turns: a performed wake drain settles the latch without a retry"
}

test_only_successful_executed_actions_count_as_delivery() {
  local repo home out status
  repo="$TMP_ROOT/action-proof-root"
  home="$TMP_ROOT/action-proof-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 2
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_PI_SESSION_START_AUTORUN=0 node --input-type=module 2>&1 <<'EOF'
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, dispatch, settle, toolCall } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);
let deliveries = 0;
state.deliver = async () => {
  deliveries += 1;
  if (deliveries === 1) {
    await toolCall("echo fm-wake-drain.sh");
    await toolCall("printf 'remember bin/fm-session-start.sh\\n'");
    await toolCall("echo checked # bin/fm-wake-drain.sh");
    await dispatch("tool_result", {
      type: "tool_result",
      toolCallId: "fixture-arm",
      toolName: "fm_watch_arm_pi",
      input: {},
      content: [],
      details: { ok: false, message: "watcher: read-only" },
      isError: false,
    });
    await dispatch("tool_call", {
      type: "tool_call",
      toolName: "bash",
      input: { command: "bin/fm-watch-arm.sh" },
    });
    await toolCall("bin/fm-wake-drain.sh", true);
    await settle();
    return;
  }
  await dispatch("tool_result", {
    type: "tool_result",
    toolCallId: "fixture-arm",
    toolName: "fm_watch_arm_pi",
    input: {},
    content: [],
    details: { ok: true, message: "watcher: started" },
    isError: false,
  });
  await settle();
};
await settle();
if (state.prompts.length !== 3) {
  throw new Error(`expected failed-action retry plus guard continuation, saw ${state.prompts.length} deliveries`);
}
if (!state.prompts[1].content.includes("OPERATIONAL DELIVERY NOT CARRIED OUT")) {
  throw new Error("non-actions incorrectly satisfied operational action accounting");
}
if (state.notifications.length !== 0) throw new Error("the successful retry escalated");
EOF
)
  status=$?
  expect_code 0 "$status" "only a successful executed operational action may satisfy delivery"
  [ -z "$out" ] || fail "successful-action proof test printed output: $out"
  pass "Pi operational turns: unsuccessful repairs, mentions, blocked calls, and errors do not count"
}

test_a_drain_that_never_clears_the_queue_stops_renotifying() {
  local repo home out status
  repo="$TMP_ROOT/stall-root"
  home="$TMP_ROOT/stall-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-primary-turnend-guard.ts
  install_session_start_fixture "$repo" ok
  write_guard "$repo" 2
  printf '1784835678\t710\tsignal\talpha\tdone: alpha\n' > "$home/state/.wake-queue"
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" FM_PI_SESSION_START_AUTORUN=0 node --input-type=module 2>&1 <<'EOF'
const { createFakePi, loadExtension } = await import(`${process.env.REPO}/fake-pi.mjs`);
const { pi, state, settle, toolCall } = createFakePi();
await loadExtension(`${process.env.REPO}/.pi/extensions/fm-primary-turnend-guard.ts`, pi);

// The model runs the drain every time, but the record never leaves the queue.
// Re-notifying forever would be an unbounded loop of visible answers.
state.deliver = async () => {
  await toolCall("bin/fm-wake-drain.sh");
  await settle();
};
await settle();
if (state.prompts.length !== 2) {
  throw new Error(`an unchanging queue produced ${state.prompts.length} operational turns`);
}
if (state.notifications.length !== 1
  || !state.notifications[0].message.includes("survived a drain")) {
  throw new Error(`the stalled queue was not escalated: ${JSON.stringify(state.notifications)}`);
}
EOF
)
  status=$?
  expect_code 0 "$status" "an unchanging wake queue must stop re-notifying and escalate"
  [ -z "$out" ] || fail "stalled-queue test printed output: $out"
  pass "Pi operational turns: a drain that never clears the queue stops re-notifying and escalates"
}

# --- provenance --------------------------------------------------------------

test_calm_keeps_one_compact_operational_boundary() {
  local repo home out status
  repo="$TMP_ROOT/boundary-root"
  home="$TMP_ROOT/boundary-home"
  mkdir -p "$home/state" "$home/config"
  install_fixture "$repo" fm-calm.ts
  out=$(REPO="$repo" FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" node --input-type=module 2>&1 <<'EOF'
const { createFakePi } = await import(`${process.env.REPO}/fake-pi.mjs`);
const visibility = await import(`${process.env.REPO}/.pi/extensions/lib/fm-calm-visibility.ts`);
const { pi, state } = createFakePi();
visibility.registerFirstmateOperationalBoundary(pi);

const boundary = state.renderers.get("firstmate-operational-boundary");
if (!boundary) throw new Error("the operational boundary renderer was not registered");
const entry = { data: { kind: "watcher" } };

visibility.setCalmPresentation(false);
if (boundary(entry) !== undefined) {
  throw new Error("calm-off duplicated the payload row with a boundary row");
}

visibility.setCalmPresentation(true);
const row = boundary(entry);
if (!row) throw new Error("calm hid the operational boundary as well as the payload");
const text = row.render(80).join("\n");
if (!text.includes("firstmate watcher follow-up")) {
  throw new Error(`the calm boundary does not name the operational cause: ${text}`);
}
if (text.includes("FIRSTMATE WATCHER WAKE") || text.length > 80) {
  throw new Error(`the calm boundary is not compact: ${text}`);
}
visibility.setCalmPresentation(false);
EOF
)
  status=$?
  expect_code 0 "$status" "calm must keep one compact operational boundary"
  [ -z "$out" ] || fail "boundary test printed output: $out"
  pass "Pi provenance: calm keeps a compact operational boundary and calm-off keeps the payload row"
}

test_plain_marker_quotation_stays_a_genuine_captain_message() {
  local classified status
  # The privacy boundary the fix must preserve: an ordinary captain message that
  # quotes the ASCII label without the U+2063 envelope is genuine human input.
  classified=$(printf '%s' 'Captain quote: FIRSTMATE_OP: v1 watcher: what does this mean?' \
    | "$ROOT/bin/fm-operational-input.sh" classify 2>/dev/null)
  status=$?
  [ "$status" -ne 0 ] || fail "a plain FIRSTMATE_OP quotation was classified as operational: $classified"
  classified=$(printf '%s' "$(printf '\xE2\x81\xA3')FIRSTMATE_OP: v1 watcher: signal: alpha" \
    | "$ROOT/bin/fm-operational-input.sh" classify)
  [ "$classified" = watcher ] || fail "a genuine marked watcher input was not classified: $classified"
  pass "Pi provenance: a captain quotation of plain FIRSTMATE_OP stays genuine human input"
}

test_session_claim_runs_before_any_answer_completes
test_session_claim_arms_one_initial_cycle
test_session_claim_failure_falls_back_to_the_advisory_nudge
test_session_claim_timeout_reaps_the_process_tree
test_session_claim_runtime_cleanup_reaps_the_process_tree
test_session_claim_autorun_can_be_disabled
test_signal_and_stale_while_busy_coalesce_into_one_turn
test_records_queued_after_the_drain_get_exactly_one_more_turn
test_continuity_failure_survives_coalescing
test_repeating_the_previous_answer_is_a_failed_delivery
test_performed_action_counts_as_delivery
test_only_successful_executed_actions_count_as_delivery
test_a_drain_that_never_clears_the_queue_stops_renotifying
test_calm_keeps_one_compact_operational_boundary
test_plain_marker_quotation_stays_a_genuine_captain_message
