#!/usr/bin/env bash
# Extension and plugin host refusal through the executable platform owner.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-extension-host-preflight)

install_fixture() {
  local fixture=$1
  mkdir -p \
    "$fixture/.pi/extensions/lib" \
    "$fixture/.omp/extensions" \
    "$fixture/.opencode/plugins/lib" \
    "$fixture/bin" \
    "$fixture/node_modules/@earendil-works/pi-ai" \
    "$fixture/node_modules/@earendil-works/pi-coding-agent" \
    "$fixture/node_modules/@earendil-works/pi-tui" \
    "$fixture/node_modules/typebox"
  cp "$ROOT/.pi/extensions/fm-branch-supervision.ts" \
    "$ROOT/.pi/extensions/fm-calm.ts" \
    "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
    "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" "$fixture/.pi/extensions/"
  cp "$ROOT/.pi/extensions/lib/fm-async-exec.ts" \
    "$ROOT/.pi/extensions/lib/fm-branch-dispatch.ts" \
    "$ROOT/.pi/extensions/lib/fm-branch-model-picker.ts" \
    "$ROOT/.pi/extensions/lib/fm-calm-assistant-layout.ts" \
    "$ROOT/.pi/extensions/lib/fm-calm-operational-user-layout.ts" \
    "$ROOT/.pi/extensions/lib/fm-calm-visibility.ts" \
    "$ROOT/.pi/extensions/lib/fm-calm-working-ship.ts" \
    "$ROOT/.pi/extensions/lib/fm-host-platform.ts" \
    "$ROOT/.pi/extensions/lib/fm-native-contract.ts" \
    "$ROOT/.pi/extensions/lib/fm-operational-input.ts" \
    "$ROOT/.pi/extensions/lib/fm-sessionstart-supervisor.mjs" \
    "$fixture/.pi/extensions/lib/"
  cp "$ROOT/.omp/extensions/fm-primary-omp-watch.ts" \
    "$ROOT/.omp/extensions/fm-primary-turnend-guard.ts" "$fixture/.omp/extensions/"
  cp "$ROOT/.opencode/plugins/fm-primary-cd-check.js" \
    "$ROOT/.opencode/plugins/fm-primary-pretool-check.js" \
    "$ROOT/.opencode/plugins/fm-primary-sessionstart-nudge.js" \
    "$ROOT/.opencode/plugins/fm-primary-turnend-guard.js" \
    "$ROOT/.opencode/plugins/fm-primary-watch-arm.js" \
    "$ROOT/.opencode/plugins/package.json" "$fixture/.opencode/plugins/"
  cp "$ROOT/.opencode/plugins/lib/fm-operational-input.js" "$fixture/.opencode/plugins/lib/"
  cp "$ROOT/bin/fm-host-platform-lib.sh" "$ROOT/bin/fm-operational-input.sh" "$fixture/bin/"
  chmod +x "$fixture/bin/"*.sh
  printf '%s\n' '{"name":"@earendil-works/pi-coding-agent","type":"module","exports":"./index.js"}' \
    > "$fixture/node_modules/@earendil-works/pi-coding-agent/package.json"
  cat > "$fixture/node_modules/@earendil-works/pi-ai/package.json" <<'JSON'
{"name":"@earendil-works/pi-ai","type":"module","exports":"./index.js"}
JSON
  cat > "$fixture/node_modules/@earendil-works/pi-ai/index.js" <<'JS'
export function clampThinkingLevel(value) { return value; }
export function getSupportedThinkingLevels() { return []; }
JS
  cat > "$fixture/node_modules/@earendil-works/pi-coding-agent/index.js" <<'JS'
export function createAgentSession() {}
export function createBashToolDefinition() { return {}; }
export function createEditToolDefinition() { return {}; }
export function createFindToolDefinition() { return {}; }
export function createGrepToolDefinition() { return {}; }
export function createLsToolDefinition() { return {}; }
export function createReadToolDefinition() { return {}; }
export function createWriteToolDefinition() { return {}; }
export function getAgentDir() { return ""; }
export function getMarkdownTheme() { return {}; }
export function keyHint() { return ""; }
export class DefaultResourceLoader {}
export class DynamicBorder {}
export class ModelRuntime {}
export class SessionManager {}
export class ToolExecutionComponent {}
export class UserMessageComponent { render() { return []; } invalidate() {} }
JS
  printf '%s\n' '{"name":"@earendil-works/pi-tui","type":"module","exports":"./index.js"}' \
    > "$fixture/node_modules/@earendil-works/pi-tui/package.json"
  cat > "$fixture/node_modules/@earendil-works/pi-tui/index.js" <<'JS'
export function fuzzyFilter() { return []; }
export function getKeybindings() { return {}; }
export class Box { addChild() {} clear() {} setBgFn() {} }
export class Container {}
export class Input {}
export class SelectList {}
export class Text {}
JS
  printf '%s\n' '{"name":"typebox","type":"module","exports":"./index.js"}' \
    > "$fixture/node_modules/typebox/package.json"
  printf '%s\n' 'export const Type = { Object(properties) { return { type: "object", properties }; } };' \
    > "$fixture/node_modules/typebox/index.js"
  : > "$fixture/AGENTS.md"
  git init -q "$fixture"
}

install_fake_uname() {
  local fixture=$1 platform=$2
  mkdir -p "$fixture/fakebin"
  cat > "$fixture/fakebin/uname" <<SH
#!/usr/bin/env bash
printf '%s\\n' '$platform'
SH
  chmod +x "$fixture/fakebin/uname"
}

install_extension_wrapper_fixture() {
  local fixture=$1
  mkdir -p "$fixture/bin"
  cp "$ROOT/bin/fm-extension.sh" "$ROOT/bin/fm-host-platform-lib.sh" "$fixture/bin/"
  cat > "$fixture/bin/fm-extension.mjs" <<'SH'
#!/usr/bin/env bash
mkdir -p "${FM_EXTENSION_WRAPPER_MARKERS:?}"
printf '%s\n' "$*" > "$FM_EXTENSION_WRAPPER_MARKERS/local-command"
printf 'transfer payload\n'
SH
  cat > "$fixture/bin/fm-on.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "${FM_EXTENSION_WRAPPER_MARKERS:?}"
printf '%s\n' "$*" > "$FM_EXTENSION_WRAPPER_MARKERS/remote-command"
cat > "$FM_EXTENSION_WRAPPER_MARKERS/remote-input"
printf 'remote bind complete\n'
SH
  chmod +x "$fixture/bin/"*
}

install_codex_shell_fixture() {
  local fixture=$1
  mkdir -p "$fixture/.codex" "$fixture/bin" "$fixture/fakebin"
  cp "$ROOT/.codex/hooks.json" "$fixture/.codex/hooks.json"
  cp "$ROOT/bin/fm-host-platform-lib.sh" \
    "$ROOT/bin/fm-sessionstart-run.sh" \
    "$ROOT/bin/fm-arm-pretool-check.sh" \
    "$ROOT/bin/fm-cd-pretool-check.sh" \
    "$ROOT/bin/fm-turnend-guard.sh" \
    "$fixture/bin/"
  : > "$fixture/AGENTS.md"
  chmod +x "$fixture/bin/"*.sh
  cat > "$fixture/fakebin/bash" <<'SH'
#!/bin/bash
if [ "${1:-}" = -lc ]; then
  shift
  exec /bin/bash -c "$1"
fi
exec /bin/bash "$@"
SH
  cat > "$fixture/fakebin/jq" <<'SH'
#!/bin/bash
: > "${FM_TEST_JQ_CALLED:?}"
exit 1
SH
  chmod +x "$fixture/fakebin/bash" "$fixture/fakebin/jq"
}

install_runtime_scripts() {
  local fixture=$1 script
  for script in fm-arm-pretool-check.sh fm-cd-pretool-check.sh; do
    cat > "$fixture/bin/$script" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "${FM_EXTENSION_SCRIPT_LOG:?}"
exit 0
SH
  done
  for script in fm-turnend-guard.sh fm-sessionstart-nudge.sh; do
    cat > "$fixture/bin/$script" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$(basename "$0")" >> "${FM_EXTENSION_SCRIPT_LOG:?}"
exit 0
SH
  done
  cat > "$fixture/bin/fm-watch-arm.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "${FM_EXTENSION_SCRIPT_LOG:?}"
printf 'watcher: started pid=%s (beacon 0s)\n' "$$"
sleep 30
SH
  chmod +x "$fixture/bin/"*.sh
}

run_unsupported_case() {
  local platform=$1 fixture="$TMP_ROOT/unsupported-$1" out status
  install_fixture "$fixture"
  install_fake_uname "$fixture" "$platform"
  install_runtime_scripts "$fixture"

  local wrapper="$fixture/remote-wrapper"
  install_fake_uname "$wrapper" "$platform"
  install_extension_wrapper_fixture "$wrapper"
  out=$(PATH="$wrapper/fakebin:$PATH" FM_EXTENSION_WRAPPER_MARKERS="$wrapper/markers" \
    "$wrapper/bin/fm-extension.sh" remote-bind ios "$wrapper/package" --adapter example 2>&1)
  status=$?
  expect_code 1 "$status" "$platform remote-bind wrapper refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform remote-bind refusal was not actionable"
  assert_absent "$wrapper/markers" "$platform remote-bind started local packing or remote transport"

  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/extension-home" \
    node "$ROOT/bin/fm-extension.mjs" list 2>&1)
  status=$?
  expect_code 1 "$status" "$platform external-extension CLI refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" \
    "$platform external-extension CLI refusal was not actionable"
  assert_absent "$fixture/extension-home" "$platform external-extension CLI created local state"

  out=$(PATH="$fixture/fakebin:$PATH" FIXTURE="$fixture" FM_HOME="$fixture/home" \
    FM_ROOT_OVERRIDE="$fixture" FM_EXTENSION_SCRIPT_LOG="$fixture/script.log" FM_TEST_PLATFORM="$platform" \
    node --input-type=module 2>&1 <<'JS'
import { existsSync } from "node:fs";
import { pathToFileURL } from "node:url";

const fixture = process.env.FIXTURE;
const load = (path) => import(`${pathToFileURL(`${fixture}/${path}`).href}?case=${Date.now()}-${Math.random()}`);
const guarded = [];
for (const path of [
  ".pi/extensions/fm-primary-turnend-guard.ts",
  ".omp/extensions/fm-primary-turnend-guard.ts",
]) {
  const handlers = new Map();
  const mod = await load(path);
  mod.default({ on(event, handler) { handlers.set(event, handler); } });
  if ([...handlers.keys()].some((event) => event !== "tool_call")) {
    throw new Error(`${path} registered active hooks on an unsupported host`);
  }
  const result = await handlers.get("tool_call")?.({ type: "tool_call", toolName: "bash", input: { command: "ls" } });
  if (result?.block !== true || !result.reason.includes(`UNSUPPORTED_HOST: ${process.env.FM_TEST_PLATFORM}`)) {
    throw new Error(`${path} did not fail its command guard closed: ${JSON.stringify(result)}`);
  }
  guarded.push(path);
}
for (const path of [
  ".pi/extensions/fm-primary-pi-watch.ts",
  ".omp/extensions/fm-primary-omp-watch.ts",
]) {
  const handlers = new Map();
  let registrations = 0;
  const mod = await load(path);
  mod.default({
    on(event, handler) { handlers.set(event, handler); },
    registerCommand() { registrations += 1; },
    registerTool() { registrations += 1; },
    sendUserMessage() {},
  });
  if (handlers.size !== 0 || registrations !== 0) throw new Error(`${path} activated on an unsupported host`);
}
for (const path of [
  ".pi/extensions/fm-calm.ts",
  ".pi/extensions/fm-branch-supervision.ts",
]) {
  let apiAccesses = 0;
  const api = new Proxy({}, {
    get() {
      apiAccesses += 1;
      return () => {};
    },
  });
  const mod = await load(path);
  mod.default(api);
  if (apiAccesses !== 0) throw new Error(`${path} registered behavior on an unsupported host`);
}
const client = { session: { promptAsync: async () => { throw new Error("prompted on unsupported host"); } } };
for (const [path, name] of [
  [".opencode/plugins/fm-primary-watch-arm.js", "FmPrimaryWatchArm"],
  [".opencode/plugins/fm-primary-turnend-guard.js", "FmPrimaryTurnendGuard"],
  [".opencode/plugins/fm-primary-sessionstart-nudge.js", "FmPrimarySessionstartNudge"],
]) {
  const mod = await load(path);
  const hooks = await mod[name]({ client, directory: fixture, worktree: fixture });
  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "unsupported" } } });
}
for (const [path, name] of [
  [".opencode/plugins/fm-primary-pretool-check.js", "FmPrimaryPretoolCheck"],
  [".opencode/plugins/fm-primary-cd-check.js", "FmPrimaryCdCheck"],
]) {
  const mod = await load(path);
  const hooks = await mod[name]({ directory: fixture, worktree: fixture });
  let denied = false;
  try {
    await hooks["tool.execute.before"]({ tool: "bash" }, { args: { command: "ls" } });
  } catch (error) {
    denied = String(error.message).includes(`UNSUPPORTED_HOST: ${process.env.FM_TEST_PLATFORM}`);
  }
  if (!denied) throw new Error(`${path} failed open on an unsupported host`);
}
if (existsSync(`${fixture}/home`) || existsSync(`${fixture}/script.log`)) {
  throw new Error("unsupported extensions wrote local records or executed a runtime script");
}
if (guarded.length !== 2) throw new Error("unsupported command guards were not exercised");
JS
  )
  status=$?
  expect_code 0 "$status" "$platform extension host refusal: $out"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform refusal was not actionable"
  assert_absent "$fixture/home" "$platform extensions created local state"
  assert_absent "$fixture/script.log" "$platform extensions executed runtime scripts"
  pass "extensions reject $platform before records, scripts, watcher arms, or command permission"
}

run_supported_case() {
  local platform=$1 fixture="$TMP_ROOT/supported-$1" out status
  install_fixture "$fixture"
  install_fake_uname "$fixture" "$platform"
  install_runtime_scripts "$fixture"

  local wrapper="$fixture/remote-wrapper"
  install_fake_uname "$wrapper" "$platform"
  install_extension_wrapper_fixture "$wrapper"
  out=$(PATH="$wrapper/fakebin:$PATH" FM_EXTENSION_WRAPPER_MARKERS="$wrapper/markers" \
    "$wrapper/bin/fm-extension.sh" remote-bind ios "$wrapper/package" --adapter example 2>&1)
  status=$?
  expect_code 0 "$status" "$platform remote-bind wrapper acceptance"
  [ "$out" = "remote bind complete" ] || fail "$platform remote-bind output changed: $out"
  assert_contains "$(cat "$wrapper/markers/local-command")" "pack-transfer $wrapper/package" \
    "$platform remote-bind did not pack the local package"
  assert_contains "$(cat "$wrapper/markers/remote-command")" \
    "--stdin ios fm-extension.sh receive-transfer-bind --adapter example" \
    "$platform remote-bind did not preserve the addressed transport command"
  [ "$(cat "$wrapper/markers/remote-input")" = "transfer payload" ] \
    || fail "$platform remote-bind did not pipe the package transfer"

  mkdir -p "$fixture/extension-home"
  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/extension-home" \
    node "$ROOT/bin/fm-extension.mjs" list 2>&1)
  status=$?
  expect_code 0 "$status" "$platform external-extension CLI acceptance"
  [ "$out" = "no extension bindings" ] || fail "$platform supported external-extension CLI output changed: $out"
  assert_absent "$fixture/extension-home/config" "$platform external-extension CLI created binding state while listing no bindings"

  mkdir -p "$fixture/home/state"
  out=$(PATH="$fixture/fakebin:$PATH" FIXTURE="$fixture" FM_HOME="$fixture/home" \
    FM_ROOT_OVERRIDE="$fixture" FM_EXTENSION_SCRIPT_LOG="$fixture/script.log" FM_TEST_PLATFORM="$platform" \
    node --input-type=module 2>&1 <<'JS'
import { existsSync, unlinkSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const fixture = process.env.FIXTURE;
const load = (path) => import(`${pathToFileURL(`${fixture}/${path}`).href}?case=${Date.now()}-${Math.random()}`);
writeFileSync(`${fixture}/home/state/.lock`, `${process.pid}\n`);
const piGuardHandlers = new Map();
const piGuard = await load(".pi/extensions/fm-primary-turnend-guard.ts");
piGuard.default({ on(event, handler) { piGuardHandlers.set(event, handler); }, sendMessage() {} });
const ompGuardHandlers = new Map();
const ompGuard = await load(".omp/extensions/fm-primary-turnend-guard.ts");
ompGuard.default({ on(event, handler) { ompGuardHandlers.set(event, handler); }, sendMessage() {} });
for (const handlers of [piGuardHandlers, ompGuardHandlers]) {
  const allowed = await handlers.get("tool_call")({ type: "tool_call", toolName: "bash", input: { command: "ls" } });
  if (allowed.block) throw new Error("a supported-host command was blocked");
}
for (const path of [
  ".pi/extensions/fm-primary-pi-watch.ts",
  ".omp/extensions/fm-primary-omp-watch.ts",
]) {
  const mod = await load(path);
  const handlers = new Map();
  mod.default({
    on(event, handler) { handlers.set(event, handler); },
    registerCommand() {},
    registerTool() {},
    sendUserMessage() {},
  });
  if (!handlers.has("session_start")) throw new Error(`${path} did not activate on a supported host`);
}
for (const marker of [
  ".pi-turnend-extension-loaded",
  ".pi-watch-extension-loaded",
  ".omp-turnend-extension-loaded",
  ".omp-watch-extension-loaded",
]) {
  if (!existsSync(`${fixture}/home/state/${marker}`)) throw new Error(`missing supported-host marker ${marker}`);
}
const client = { session: { promptAsync: async () => {} } };
const watchMod = await load(".opencode/plugins/fm-primary-watch-arm.js");
await watchMod.FmPrimaryWatchArm({ client, directory: fixture, worktree: fixture });
const turnendMod = await load(".opencode/plugins/fm-primary-turnend-guard.js");
const turnendHooks = await turnendMod.FmPrimaryTurnendGuard({ client, directory: fixture, worktree: fixture });
await turnendHooks.event({ event: { type: "session.idle", properties: { sessionID: "supported" } } });
const sessionMod = await load(".opencode/plugins/fm-primary-sessionstart-nudge.js");
const sessionHooks = await sessionMod.FmPrimarySessionstartNudge({ client, directory: fixture, worktree: fixture });
await sessionHooks.event({ event: { type: "session.created", properties: { sessionID: "supported" } } });
for (const [path, name] of [
  [".opencode/plugins/fm-primary-pretool-check.js", "FmPrimaryPretoolCheck"],
  [".opencode/plugins/fm-primary-cd-check.js", "FmPrimaryCdCheck"],
]) {
  const mod = await load(path);
  const hooks = await mod[name]({ directory: fixture, worktree: fixture });
  await hooks["tool.execute.before"]({ tool: "bash" }, { args: { command: "ls" } });
}
unlinkSync(`${fixture}/bin/fm-arm-pretool-check.sh`);
for (const handlers of [piGuardHandlers, ompGuardHandlers]) {
  const denied = await handlers.get("tool_call")({ type: "tool_call", toolName: "bash", input: { command: "ls" } });
  if (denied.block !== true || !denied.reason.includes("could not execute")) {
    throw new Error(`a missing supported-host checker failed open: ${JSON.stringify(denied)}`);
  }
}
const pretoolMod = await load(".opencode/plugins/fm-primary-pretool-check.js");
const pretoolHooks = await pretoolMod.FmPrimaryPretoolCheck({ directory: fixture, worktree: fixture });
let denied = false;
try {
  await pretoolHooks["tool.execute.before"]({ tool: "bash" }, { args: { command: "ls" } });
} catch {
  denied = true;
}
if (!denied) throw new Error("OpenCode missing checker failed open");
JS
  )
  status=$?
  expect_code 0 "$status" "$platform extension host acceptance and checker failure"
  [ -z "$out" ] || fail "$platform supported extension case printed output: $out"
  assert_present "$fixture/script.log" "$platform extensions did not execute supported runtime paths"
  pass "extensions preserve $platform behavior and fail closed when a checker cannot execute"
}

# Fixture-local environment exports are intentionally confined to command
# substitutions that exercise wrapper text from hooks.json.
# shellcheck disable=SC2030,SC2031
run_unsupported_shell_case() {
  local platform=$1 fixture="$TMP_ROOT/unsupported-shell-$1" out status guard harness payload
  local -a args
  install_fake_uname "$fixture" "$platform"

  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/home" FM_ROOT_OVERRIDE="$fixture/root" \
    "$ROOT/bin/fm-sessionstart-run.sh" --source startup 2>&1)
  status=$?
  expect_code 1 "$status" "$platform session-start wrapper refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform session-start wrapper refusal was not actionable"
  assert_absent "$fixture/home" "$platform session-start wrapper created home state"
  assert_absent "$fixture/root" "$platform session-start wrapper reached scope work"

  local codex_fixture="$fixture/codex" hook_command hook_label query
  local -a codex_queries codex_labels
  install_fake_uname "$codex_fixture" "$platform"
  install_codex_shell_fixture "$codex_fixture"
  codex_queries=(
    '.hooks.SessionStart[0].hooks[0].command'
    '.hooks.PreToolUse[0].hooks[0].command'
    '.hooks.PreToolUse[0].hooks[1].command'
    '.hooks.Stop[0].hooks[0].command'
  )
  codex_labels=(session-start arm-guard cd-guard turn-end)
  for query in "${!codex_queries[@]}"; do
    hook_command=$(jq -r "${codex_queries[$query]}" "$codex_fixture/.codex/hooks.json")
    hook_label=${codex_labels[$query]}
    out=$(
      {
        cd "$codex_fixture" || exit 99
        export PATH="$codex_fixture/fakebin:/usr/bin:/bin"
        export FM_TEST_JQ_CALLED="$codex_fixture/jq-called"
        printf '{"source":"startup","tool_input":{"command":"bin/fm-lock.sh status"}}' | eval "$hook_command"
      } 2>&1
    )
    status=$?
    expect_code 2 "$status" "$platform Codex $hook_label wrapper refusal"
    assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform Codex $hook_label refusal was not actionable"
    assert_absent "$codex_fixture/jq-called" "$platform Codex $hook_label parsed transport before host refusal"
    assert_absent "$codex_fixture/state" "$platform Codex $hook_label created state"
  done

  for guard in fm-arm-pretool-check.sh fm-cd-pretool-check.sh; do
    for harness in claude codex grok; do
      args=()
      case "$harness" in
        claude)
          payload='{"tool_input":{"command":"bin/fm-lock.sh status"}}'
          args=(--claude)
          ;;
        codex)
          payload='{"tool_input":{"command":"bin/fm-lock.sh status"}}'
          ;;
        grok)
          payload='{"toolInput":{"command":"bin/fm-lock.sh status"}}'
          ;;
      esac
      out=$(printf '%s' "$payload" | PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/guard-home" \
        "$ROOT/bin/$guard" "${args[@]}" 2>&1)
      status=$?
      expect_code 2 "$status" "$platform $harness $guard refusal"
      assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform $harness $guard refusal was not actionable"
      assert_absent "$fixture/guard-home" "$platform $harness $guard created state"
    done
  done

  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/guard-home" \
    "$ROOT/bin/fm-subagent-pretool-check.sh" --claude --tool Bash 2>&1)
  status=$?
  expect_code 2 "$status" "$platform delegation guard refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform delegation guard refusal was not actionable"
  assert_absent "$fixture/guard-home" "$platform delegation guard created state"

  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/nudge-home" FM_ROOT_OVERRIDE="$fixture/root" \
    "$ROOT/bin/fm-sessionstart-nudge.sh" 2>&1)
  status=$?
  expect_code 1 "$status" "$platform session-start nudge refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform session-start nudge refusal was not actionable"
  assert_absent "$fixture/nudge-home" "$platform session-start nudge created state"

  out=$(printf '{}' | PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/turnend-home" \
    "$ROOT/bin/fm-turnend-guard.sh" --claude 2>&1)
  status=$?
  expect_code 2 "$status" "$platform turn-end guard refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform turn-end guard refusal was not actionable"
  assert_absent "$fixture/turnend-home" "$platform turn-end guard created state"

  mkdir -p "$fixture/grok-tmp"
  out=$(printf '{"sessionId":"legacy"}' | PATH="$fixture/fakebin:$PATH" TMPDIR="$fixture/grok-tmp" \
    GROK_WORKSPACE_ROOT="$ROOT" FM_HOME="$fixture/grok-home" "$ROOT/bin/fm-turnend-guard-grok.sh" 2>&1)
  status=$?
  expect_code 2 "$status" "$platform Grok turn-end refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform Grok turn-end refusal was not actionable"
  assert_absent "$fixture/grok-home" "$platform Grok turn-end guard created state"
  if find "$fixture/grok-tmp" -mindepth 1 -print -quit | grep -q .; then
    fail "$platform Grok turn-end guard created a temporary file"
  fi

  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/wake-home" \
    bash -c '. "$1"; : > "$2"' _ "$ROOT/bin/fm-wake-lib.sh" "$fixture/after-source" 2>&1)
  status=$?
  expect_code 1 "$status" "$platform wake library refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: $platform" "$platform wake library refusal was not actionable"
  assert_absent "$fixture/wake-home" "$platform wake library created state"
  assert_absent "$fixture/after-source" "$platform wake library returned to its caller"
  pass "shell harness boundaries reject $platform before state or temporary-file mutation"
}

# shellcheck disable=SC2030,SC2031
run_supported_shell_case() {
  local platform=$1 fixture="$TMP_ROOT/supported-shell-$1" out status guard
  install_fake_uname "$fixture" "$platform"

  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/session-home" FM_ROOT_OVERRIDE="$fixture/root" \
    NO_MISTAKES_GATE=1 "$ROOT/bin/fm-sessionstart-run.sh" --source startup --pi-prerequisite 2>&1)
  status=$?
  expect_code 3 "$status" "$platform session-start wrapper acceptance"
  [ -z "$out" ] || fail "$platform supported session-start wrapper printed output: $out"

  local codex_fixture="$fixture/codex" hook_command
  install_fake_uname "$codex_fixture" "$platform"
  install_codex_shell_fixture "$codex_fixture"
  hook_command=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$codex_fixture/.codex/hooks.json")
  out=$(
    {
      cd "$codex_fixture" || exit 99
      export PATH="$codex_fixture/fakebin:/usr/bin:/bin"
      export FM_TEST_JQ_CALLED="$codex_fixture/jq-called"
      printf '{"tool_input":{"command":"bin/fm-lock.sh status"}}' | eval "$hook_command"
    } 2>&1
  )
  status=$?
  expect_code 0 "$status" "$platform Codex checker-owned fail-open"
  [ -z "$out" ] || fail "$platform supported Codex fail-open printed output: $out"
  assert_present "$codex_fixture/jq-called" "$platform Codex wrapper did not reach supported-host transport validation"

  for guard in fm-arm-pretool-check.sh fm-cd-pretool-check.sh; do
    out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/guard-home" \
      "$ROOT/bin/$guard" --claude --command 'bin/fm-lock.sh status' 2>&1)
    status=$?
    expect_code 0 "$status" "$platform $guard acceptance"
    [ -z "$out" ] || fail "$platform supported $guard printed output: $out"
  done
  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/guard-home" \
    "$ROOT/bin/fm-subagent-pretool-check.sh" --claude --tool Bash 2>&1)
  status=$?
  expect_code 0 "$status" "$platform delegation guard acceptance"
  [ -z "$out" ] || fail "$platform supported delegation guard printed output: $out"

  out=$(PATH="$fixture/fakebin:$PATH" FM_HOME="$fixture/wake-home" \
    bash -c '. "$1"; : > "$2"' _ "$ROOT/bin/fm-wake-lib.sh" "$fixture/after-source" 2>&1)
  status=$?
  expect_code 0 "$status" "$platform wake library acceptance"
  [ -z "$out" ] || fail "$platform supported wake library printed output: $out"
  assert_present "$fixture/wake-home/state" "$platform wake library did not preserve state initialization"
  assert_present "$fixture/after-source" "$platform wake library did not return to its caller"
  pass "session, guard, and wake entrypoints preserve $platform behavior"
}

run_missing_bash_case() {
  local fixture="$TMP_ROOT/missing-bash" node_bin node_platform out status
  node_bin=$(command -v node)
  node_platform=$("$node_bin" -p 'process.platform')
  install_fixture "$fixture"
  mkdir -p "$fixture/empty-bin"

  out=$(PATH="$fixture/empty-bin" FM_HOME="$fixture/extension-home" \
    "$node_bin" "$ROOT/bin/fm-extension.mjs" list 2>&1)
  status=$?
  expect_code 1 "$status" "external-extension CLI missing-bash refusal"
  assert_contains "$out" "UNSUPPORTED_HOST: Node $node_platform" \
    "external-extension CLI missing-bash refusal omitted the Node platform"
  assert_contains "$out" "Firstmate hosts require macOS or Linux" \
    "external-extension CLI missing-bash refusal omitted supported-host guidance"
  assert_contains "$out" "WSL2 remains supported" \
    "external-extension CLI missing-bash refusal omitted WSL2 guidance"
  assert_absent "$fixture/extension-home" "external-extension CLI missing-bash refusal created state"

  out=$(PATH="$fixture/empty-bin" FIXTURE="$fixture" FM_HOME="$fixture/home" \
    "$node_bin" --input-type=module 2>&1 <<'JS'
import { pathToFileURL } from "node:url";

const fixture = process.env.FIXTURE;
const handlers = new Map();
const mod = await import(`${pathToFileURL(`${fixture}/.pi/extensions/fm-primary-turnend-guard.ts`).href}?case=missing-bash`);
mod.default({ on(event, handler) { handlers.set(event, handler); } });
const result = await handlers.get("tool_call")?.({ type: "tool_call", toolName: "bash", input: { command: "ls" } });
if (result?.block !== true || !result.reason.includes(`UNSUPPORTED_HOST: Node ${process.platform}`)) {
  throw new Error(`Pi command guard did not return the missing-bash refusal: ${JSON.stringify(result)}`);
}
if (!result.reason.includes("Firstmate hosts require macOS or Linux") || !result.reason.includes("WSL2 remains supported")) {
  throw new Error(`Pi missing-bash refusal was not actionable: ${result.reason}`);
}
JS
  )
  status=$?
  expect_code 0 "$status" "Pi extension missing-bash refusal: $out"
  assert_contains "$out" "UNSUPPORTED_HOST: Node $node_platform" \
    "Pi extension missing-bash refusal omitted the Node platform"
  assert_absent "$fixture/home" "Pi extension missing-bash refusal created state"
  pass "Node entrypoints fail closed with actionable guidance when bash is unavailable"
}

for platform in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0 FreeBSD; do
  FM_TEST_PLATFORM=$platform run_unsupported_case "$platform"
  run_unsupported_shell_case "$platform"
done
for platform in Darwin Linux; do
  FM_TEST_PLATFORM=$platform run_supported_case "$platform"
  run_supported_shell_case "$platform"
done
run_missing_bash_case
