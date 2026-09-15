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
    "$fixture/node_modules/@earendil-works/pi-coding-agent" \
    "$fixture/node_modules/@earendil-works/pi-tui" \
    "$fixture/node_modules/typebox"
  cp "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
    "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" "$fixture/.pi/extensions/"
  cp "$ROOT/.pi/extensions/lib/fm-async-exec.ts" \
    "$ROOT/.pi/extensions/lib/fm-branch-dispatch.ts" \
    "$ROOT/.pi/extensions/lib/fm-calm-visibility.ts" \
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
  cat > "$fixture/node_modules/@earendil-works/pi-coding-agent/index.js" <<'JS'
export function getMarkdownTheme() { return {}; }
export class UserMessageComponent { render() { return []; } invalidate() {} }
JS
  printf '%s\n' '{"name":"@earendil-works/pi-tui","type":"module","exports":"./index.js"}' \
    > "$fixture/node_modules/@earendil-works/pi-tui/package.json"
  cat > "$fixture/node_modules/@earendil-works/pi-tui/index.js" <<'JS'
export class Box { addChild() {} clear() {} setBgFn() {} }
export class Container {}
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

for platform in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0 FreeBSD; do
  FM_TEST_PLATFORM=$platform run_unsupported_case "$platform"
done
for platform in Darwin Linux; do
  FM_TEST_PLATFORM=$platform run_supported_case "$platform"
done
