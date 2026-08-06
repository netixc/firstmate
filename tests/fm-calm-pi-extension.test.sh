#!/usr/bin/env bash
# Focused rendering, lifecycle, persistence, and interactive TUI checks for /calm.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-calm-pi-extension)
EXT="$ROOT/.pi/extensions/fm-calm.ts"
ASSISTANT_LAYOUT="$ROOT/.pi/extensions/lib/fm-calm-assistant-layout.ts"
OPERATIONAL_USER_LAYOUT="$ROOT/.pi/extensions/lib/fm-calm-operational-user-layout.ts"
VISIBILITY="$ROOT/.pi/extensions/lib/fm-calm-visibility.ts"
WORKING_SHIP="$ROOT/.pi/extensions/lib/fm-calm-working-ship.ts"
WATCH_EXT="$ROOT/.pi/extensions/fm-primary-pi-watch.ts"
OPERATIONAL_INPUT="$ROOT/bin/fm-operational-input.sh"
PI_OPERATIONAL_INPUT="$ROOT/.pi/extensions/lib/fm-operational-input.ts"
PI_PACKAGE_DIR=${FM_PI_PACKAGE_DIR:-"$(npm root -g 2>/dev/null)/@earendil-works/pi-coding-agent"}
# Verified against Pi 0.81.1 and 0.82.0 (docs/calm-mode-feasibility.md).
# This is known-good evidence, not a support ceiling.
record_pi_version_evidence() {
  local version=$1 context=$2
  [ -n "$version" ] || fail "$context could not determine the installed Pi version"
}

test_home_resolution() {
  local fixture out status version
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "skip: node or npm not found for Pi calm home-resolution test"
    return 0
  fi
  if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
    echo "skip: installed @earendil-works/pi-coding-agent package not found"
    return 0
  fi
  version=$(node -p "require('$PI_PACKAGE_DIR/package.json').version")
  record_pi_version_evidence "$version" "Pi calm compatibility assumptions"

  fixture="$TMP_ROOT/home-resolution"
  mkdir -p \
    "$fixture/project/.pi/extensions/lib" \
    "$fixture/project/node_modules/@earendil-works" \
    "$fixture/override" \
    "$fixture/launch-cwd"
  cp "$EXT" "$fixture/project/.pi/extensions/fm-calm.ts"
  cp "$ASSISTANT_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/project/.pi/extensions/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/project/.pi/extensions/lib/fm-calm-working-ship.ts"
  cp "$PI_OPERATIONAL_INPUT" "$fixture/project/.pi/extensions/lib/fm-operational-input.ts"
  ln -s "$PI_PACKAGE_DIR" "$fixture/project/node_modules/@earendil-works/pi-coding-agent"
  ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$fixture/project/node_modules/@earendil-works/pi-tui"
  ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$fixture/project/node_modules/typebox"
  printf '%s\n' '{"type":"module"}' >"$fixture/project/package.json"

  out=$(cd "$fixture/launch-cwd" && \
    EXT="$fixture/project/.pi/extensions/fm-calm.ts" \
    OVERRIDE_HOME="$fixture/override" \
    EXTENSION_HOME="$fixture/project" \
    node --input-type=module 2>&1 <<'JS'
import { existsSync, readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const extension = await import(`${pathToFileURL(process.env.EXT).href}?home=${Date.now()}`);

function registerCalm() {
  const handlers = new Map();
  let calmCommand;
  const pi = {
    events: {
      emit() {},
      on() {},
    },
    on(event, handler) {
      handlers.set(event, handler);
    },
    registerCommand(name, command) {
      if (name === "calm") calmCommand = command;
    },
    registerEntryRenderer() {},
    registerTool() {},
    getAllTools() {
      return [];
    },
  };
  extension.default(pi);
  if (!calmCommand || !handlers.has("session_start")) {
    throw new Error("Calm extension did not register its command and session handler");
  }
  return { calmCommand, sessionStart: handlers.get("session_start") };
}

const context = {
  ui: {
    getEditorText() {
      return "";
    },
    getToolsExpanded() {
      return false;
    },
    onTerminalInput() {
      return () => {};
    },
    setHiddenThinkingLabel() {},
    setStatus() {},
    setToolsExpanded() {},
    setWorkingVisible() {},
    notify() {},
  },
};

delete process.env.FM_HOME;
delete process.env.FM_CONFIG_OVERRIDE;
process.env.FM_ROOT_OVERRIDE = process.env.OVERRIDE_HOME;
let calm = registerCalm();
calm.sessionStart({ reason: "startup" }, context);
await calm.calmCommand.handler("", context);
if (readFileSync(`${process.env.OVERRIDE_HOME}/config/calm`, "utf8") !== "on\n") {
  throw new Error("Calm ignored FM_ROOT_OVERRIDE when FM_HOME was unset");
}

delete process.env.FM_ROOT_OVERRIDE;
calm = registerCalm();
calm.sessionStart({ reason: "startup" }, context);
await calm.calmCommand.handler("", context);
if (readFileSync(`${process.env.EXTENSION_HOME}/config/calm`, "utf8") !== "on\n") {
  throw new Error("Calm did not derive the Firstmate home from its extension path");
}
if (existsSync(`${process.cwd()}/config/calm`)) {
  throw new Error("Calm wrote its preference under Pi's launch directory");
}
JS
)
  status=$?
  [ "$status" -eq 0 ] || fail "Pi calm home resolution failed: $out"
  [ -z "$out" ] || fail "Pi calm home-resolution test printed output: $out"
  pass "Pi calm resolves its persistent home independently of Pi's launch directory"
}

test_pi_compat_no_upper_bound() {
  local version
  for version in 0.83.0 0.90.0 1.0.0 2.3.4 0.82.1 10.20.30; do
    record_pi_version_evidence "$version" "synthetic newer Pi" \
      || fail "record_pi_version_evidence rejected Pi $version solely for being newer than 0.82.0"
  done
  if (record_pi_version_evidence "" "malformed Pi version probe") 2>/dev/null; then
    fail "record_pi_version_evidence accepted a missing/malformed Pi version"
  fi
  pass "Pi calm compatibility evidence never rejects a Pi version for being newer than 0.82.0, and still fails closed on a missing or malformed version"
}

test_pi_compat_degraded_adapter() {
  local fixture out status
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "skip: node or npm not found for Pi calm degraded-adapter test"
    return 0
  fi
  if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
    echo "skip: installed @earendil-works/pi-coding-agent package not found"
    return 0
  fi

  fixture="$TMP_ROOT/degraded-adapter"
  mkdir -p \
    "$fixture/project/.pi/extensions/lib" \
    "$fixture/project/node_modules/@earendil-works"
  cp "$EXT" "$fixture/project/.pi/extensions/fm-calm.ts"
  cp "$ASSISTANT_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/project/.pi/extensions/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/project/.pi/extensions/lib/fm-calm-working-ship.ts"
  cp "$PI_OPERATIONAL_INPUT" "$fixture/project/.pi/extensions/lib/fm-operational-input.ts"
  ln -s "$PI_PACKAGE_DIR" "$fixture/project/node_modules/@earendil-works/pi-coding-agent"
  ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$fixture/project/node_modules/@earendil-works/pi-tui"
  ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$fixture/project/node_modules/typebox"
  printf '%s\n' '{"type":"module"}' >"$fixture/project/package.json"

  out=$(cd "$fixture/project" && \
    EXT="$fixture/project/.pi/extensions/fm-calm.ts" \
    PI_PACKAGE_DIR="$PI_PACKAGE_DIR" \
    node --input-type=module 2>&1 <<'JS'
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_PACKAGE_DIR;
const { AssistantMessageComponent } = await import(
  pathToFileURL(`${packageRoot}/dist/modes/interactive/components/assistant-message.js`).href
);
const originalUpdateContent = AssistantMessageComponent.prototype.updateContent;
if (typeof originalUpdateContent !== "function") {
  throw new Error(
    "fixture precondition failed: installed Pi lacks AssistantMessageComponent.prototype.updateContent",
  );
}
delete AssistantMessageComponent.prototype.updateContent;

const diagnostics = [];
const originalConsoleError = console.error;
console.error = (...args) => diagnostics.push(args.join(" "));

let calmCommand;
const handlers = new Map();
const pi = {
  events: { emit() {}, on() {} },
  on(event, handler) {
    handlers.set(event, handler);
  },
  registerCommand(name, command) {
    if (name === "calm") calmCommand = command;
  },
  registerEntryRenderer() {},
  registerTool() {},
};

let threw = false;
try {
  const extension = await import(`${pathToFileURL(process.env.EXT).href}?degraded=${Date.now()}`);
  extension.default(pi);
} catch {
  threw = true;
}
console.error = originalConsoleError;

if (threw) {
  throw new Error(
    "a missing presentation API crashed the whole Calm extension instead of degrading just that adapter",
  );
}
if (!calmCommand || !handlers.has("session_start")) {
  throw new Error(
    "Calm command/session lifecycle did not register when only one presentation adapter was unavailable",
  );
}
if (typeof AssistantMessageComponent.prototype.updateContent !== "undefined") {
  throw new Error(
    "the degraded adapter path patched updateContent anyway despite the missing API, which would claim false success",
  );
}
const sawClearSkipReason = diagnostics.some(
  (line) => line.includes("collapsed-thinking") && /unavailable|skip/i.test(line),
);
if (!sawClearSkipReason) {
  throw new Error(
    `missing a clear skip reason for the degraded collapsed-thinking adapter; saw: ${JSON.stringify(diagnostics)}`,
  );
}

AssistantMessageComponent.prototype.updateContent = originalUpdateContent;
JS
)
  status=$?
  [ "$status" -eq 0 ] || fail "Pi calm degraded-adapter path failed: $out"
  [ -z "$out" ] || fail "Pi calm degraded-adapter test printed output: $out"
  pass "a missing collapsed-thinking presentation API degrades only that Calm adapter with a clear skip reason, while the rest of Calm still registers"
}

test_pi_compat_missing_adapter_exports() {
  local fixture out status
  if ! command -v node >/dev/null 2>&1; then
    echo "skip: node not found for Pi calm missing-adapter-export test"
    return 0
  fi

  fixture="$TMP_ROOT/missing-adapter-exports"
  mkdir -p \
    "$fixture/project/.pi/extensions/lib" \
    "$fixture/project/node_modules/@earendil-works/pi-coding-agent"
  cp "$ASSISTANT_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/project/.pi/extensions/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/project/.pi/extensions/lib/fm-calm-working-ship.ts"
  cp "$PI_OPERATIONAL_INPUT" "$fixture/project/.pi/extensions/lib/fm-operational-input.ts"
  printf '%s\n' '{"type":"module"}' >"$fixture/project/package.json"
  printf '%s\n' \
    '{"name":"@earendil-works/pi-coding-agent","type":"module","exports":"./index.js"}' \
    >"$fixture/project/node_modules/@earendil-works/pi-coding-agent/package.json"
  printf '%s\n' \
    'export function getMarkdownTheme() { return {}; }' \
    'export class UserMessageComponent {}' \
    >"$fixture/project/node_modules/@earendil-works/pi-coding-agent/index.js"

  out=$(cd "$fixture/project" && node --input-type=module 2>&1 <<'JS'
const assistant = await import("./.pi/extensions/lib/fm-calm-assistant-layout.ts");
const operational = await import("./.pi/extensions/lib/fm-calm-operational-user-layout.ts");

for (const [name, install, expected] of [
  ["collapsed-thinking", assistant.installCalmAssistantLayout, "AssistantMessageComponent"],
  ["operational-user-row", operational.installCalmOperationalUserLayout, "InteractiveMode"],
]) {
  let reason;
  try {
    install();
  } catch (error) {
    reason = error instanceof Error ? error.message : String(error);
  }
  if (!reason?.includes(expected)) {
    throw new Error(
      `${name} adapter did not load and report its missing runtime export: ${String(reason)}`,
    );
  }
}
JS
)
  status=$?
  [ "$status" -eq 0 ] || fail "Pi calm missing-adapter-export path failed: $out"
  [ -z "$out" ] || fail "Pi calm missing-adapter-export test printed output: $out"
  pass "missing Pi presentation class exports reach the independent adapter degradation path"
}

test_builtin_gate_load_time() {
  local fixture out output_file status
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "skip: node or npm not found for Pi calm gate test"
    return 0
  fi
  if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
    echo "skip: installed @earendil-works/pi-coding-agent package not found"
    return 0
  fi

  fixture="$TMP_ROOT/gate-load-time"
  mkdir -p \
    "$fixture/project/.pi/extensions/lib" \
    "$fixture/project/node_modules/@earendil-works" \
    "$fixture/home-off/config" \
    "$fixture/home-on/config"
  cp "$EXT" "$fixture/project/.pi/extensions/fm-calm.ts"
  cp "$ASSISTANT_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/project/.pi/extensions/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/project/.pi/extensions/lib/fm-calm-working-ship.ts"
  cp "$PI_OPERATIONAL_INPUT" "$fixture/project/.pi/extensions/lib/fm-operational-input.ts"
  ln -s "$PI_PACKAGE_DIR" "$fixture/project/node_modules/@earendil-works/pi-coding-agent"
  ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$fixture/project/node_modules/@earendil-works/pi-tui"
  ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$fixture/project/node_modules/typebox"
  printf '%s\n' '{"type":"module"}' >"$fixture/project/package.json"
  printf '%s\n' on >"$fixture/home-on/config/calm"

  output_file="$fixture/node-output"
  (cd "$fixture/project" && \
    EXT="$fixture/project/.pi/extensions/fm-calm.ts" \
    HOME_OFF="$fixture/home-off" \
    HOME_ON="$fixture/home-on" \
    node --input-type=module) >"$output_file" 2>&1 <<'JS'
import { pathToFileURL } from "node:url";

function fakePi() {
  const tools = [];
  const handlers = new Map();
  const pi = {
    events: { emit() {}, on() {} },
    on(event, handler) {
      handlers.set(event, handler);
    },
    registerCommand() {},
    registerEntryRenderer() {},
    registerTool(tool) {
      tools.push(tool);
    },
    getAllTools() {
      return tools.map((tool) => ({ name: tool.name, sourceInfo: { source: "extension", path: "self" } }));
    },
  };
  return { pi, tools, handlers };
}

// Calm-off (config/calm absent for this home): load-time registration must be
// entirely skipped, so a non-Calm user contests nothing.
process.env.FM_HOME = process.env.HOME_OFF;
const offRun = fakePi();
const extensionOff = await import(`${pathToFileURL(process.env.EXT).href}?gate-off=${Date.now()}`);
extensionOff.default(offRun.pi);
if (offRun.tools.length !== 0) {
  throw new Error(`Calm registered ${offRun.tools.length} built-ins while config/calm was absent: ${offRun.tools.map((t) => t.name).join(",")}`);
}

// Calm-on (config/calm="on" for this home): registration must happen synchronously,
// during this same factory call, exactly the timing /reload's pre-session_start
// transcript render depends on - not deferred to session_start or later.
process.env.FM_HOME = process.env.HOME_ON;
const onRun = fakePi();
const extensionOn = await import(`${pathToFileURL(process.env.EXT).href}?gate-on=${Date.now()}`);
extensionOn.default(onRun.pi);
const names = onRun.tools.map((t) => t.name).sort();
const expected = ["bash", "edit", "find", "grep", "ls", "read", "write"];
if (JSON.stringify(names) !== JSON.stringify(expected)) {
  throw new Error(`Calm registered ${JSON.stringify(names)} synchronously at load with config/calm=on, expected ${JSON.stringify(expected)}`);
}
JS
  status=$?
  out=$(cat "$output_file")
  [ "$status" -eq 0 ] || fail "Pi calm gate-at-load-time path failed: $out"
  [ -z "$out" ] || fail "Pi calm gate-at-load-time test printed output: $out"
  pass "Calm registers none of its 7 built-in tool wrappers at load while config/calm is off, and all 7 synchronously at load while config/calm is on"
}

test_calm_activation_collision_and_regression_bound() {
  local fixture out output_file status
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "skip: node or npm not found for Pi calm activation test"
    return 0
  fi
  if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
    echo "skip: installed @earendil-works/pi-coding-agent package not found"
    return 0
  fi

  fixture="$TMP_ROOT/activation-collision"
  mkdir -p \
    "$fixture/project/.pi/extensions/lib" \
    "$fixture/project/node_modules/@earendil-works" \
    "$fixture/home/config"
  cp "$EXT" "$fixture/project/.pi/extensions/fm-calm.ts"
  cp "$ASSISTANT_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/project/.pi/extensions/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/project/.pi/extensions/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/project/.pi/extensions/lib/fm-calm-working-ship.ts"
  cp "$PI_OPERATIONAL_INPUT" "$fixture/project/.pi/extensions/lib/fm-operational-input.ts"
  ln -s "$PI_PACKAGE_DIR" "$fixture/project/node_modules/@earendil-works/pi-coding-agent"
  ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$fixture/project/node_modules/@earendil-works/pi-tui"
  ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$fixture/project/node_modules/typebox"
  printf '%s\n' '{"type":"module"}' >"$fixture/project/package.json"
  printf '%s\n' 'export default function () {}' >"$fixture/project/foreign-bash-extension.ts"

  output_file="$fixture/node-output"
  (cd "$fixture/project" && \
    EXT="$fixture/project/.pi/extensions/fm-calm.ts" \
    FOREIGN_EXT="$fixture/project/foreign-bash-extension.ts" \
    FM_HOME="$fixture/home" \
    PI_PACKAGE_DIR="$PI_PACKAGE_DIR" \
    node --input-type=module) >"$output_file" 2>&1 <<'JS'
import { fileURLToPath, pathToFileURL } from "node:url";

const packageRoot = process.env.PI_PACKAGE_DIR;
const { ToolExecutionComponent } = await import(
  pathToFileURL(`${packageRoot}/dist/modes/interactive/components/tool-execution.js`).href
);
const { initTheme } = await import(pathToFileURL(`${packageRoot}/dist/modes/interactive/theme/theme.js`).href);
const { setCapabilities } = await import(
  pathToFileURL(`${packageRoot}/node_modules/@earendil-works/pi-tui/dist/index.js`).href
);
initTheme("dark");
setCapabilities({ images: null, trueColor: true, hyperlinks: false });

// Reproduces the collision: a different, earlier-loaded extension already owns
// "bash" by the time Calm's first activation runs, exactly as Pi's real
// ExtensionRunner resolves same-name pi.registerTool() calls (first-registered-
// extension-per-name wins, verified in the installed Pi package's
// ExtensionRunner.getAllRegisteredTools).
const foreignPath = fileURLToPath(pathToFileURL(process.env.FOREIGN_EXT).href);
const FOREIGN_MARKER = "FOREIGN_BASH_EXECUTED";
const foreignBash = {
  name: "bash",
  label: "Foreign bash",
  description: "A different extension's own bash override, e.g. an approval gate.",
  parameters: { type: "object", properties: {} },
  async execute() {
    return { content: [{ type: "text", text: FOREIGN_MARKER }], details: {}, isError: false };
  },
};

const registry = new Map([["bash", { tool: foreignBash, ownerPath: foreignPath }]]);
const notifications = [];
const diagnostics = [];
const originalConsoleError = console.error;
console.error = (...args) => diagnostics.push(args.join(" "));

const handlers = new Map();
let calmCommand;
const extPath = fileURLToPath(pathToFileURL(process.env.EXT).href);
const pi = {
  events: { emit() {}, on() {} },
  on(event, handler) {
    handlers.set(event, handler);
  },
  registerCommand(name, command) {
    if (name === "calm") calmCommand = command;
  },
  registerEntryRenderer() {},
  // Mirrors Pi's own arbitration: first registrant for a name keeps it, silently.
  registerTool(tool) {
    if (!registry.has(tool.name)) {
      registry.set(tool.name, { tool, ownerPath: extPath });
    }
  },
  getAllTools() {
    return Array.from(registry.entries()).map(([name, { ownerPath }]) => ({
      name,
      sourceInfo: { source: "extension", path: ownerPath },
    }));
  },
};

let threw = false;
try {
  const extension = await import(`${pathToFileURL(process.env.EXT).href}?activation=${Date.now()}`);
  extension.default(pi);
} catch {
  threw = true;
}
if (threw) throw new Error("Calm's own factory threw while config/calm was absent and another extension already owned bash");
if (registry.size !== 1) {
  throw new Error(`Calm registered built-ins at load time despite config/calm being absent: ${JSON.stringify(Array.from(registry.keys()))}`);
}
if (!calmCommand || !handlers.has("session_start")) {
  throw new Error("Calm did not finish registering its command and session handler");
}

// A row constructed before Calm's first-ever activation this session: this is the
// captain-accepted, documented bound on the gate-at-load fix (see fm-calm.ts's file
// header and docs/calm.md) - Pi gives no way to re-point an already-constructed
// ToolExecutionComponent at a definition registered later, so this row can never
// retroactively collapse. Lock that in explicitly rather than let it regress further.
const renderUi = { requestRender() {} };
const preToggleReadArgs = { path: "sample.txt" };
const preToggleRead = new ToolExecutionComponent(
  "read",
  "pre-toggle-read",
  preToggleReadArgs,
  { showImages: false },
  registry.get("read")?.tool,
  renderUi,
  process.cwd(),
);
preToggleRead.markExecutionStarted();
preToggleRead.setArgsComplete();
preToggleRead.updateResult({ content: [{ type: "text", text: "PRE_TOGGLE_READ_OUTPUT" }], details: {}, isError: false });
const preToggleRenderedBefore = preToggleRead.render(100);
if (preToggleRenderedBefore.length === 0) {
  throw new Error("a tool row rendered as hidden before Calm was ever activated");
}

const ctx = {
  ui: {
    getEditorText: () => "",
    getToolsExpanded: () => false,
    onTerminalInput: () => () => {},
    setHiddenThinkingLabel() {},
    setStatus() {},
    setToolsExpanded() {},
    setWorkingVisible() {},
    notify(message, type) {
      notifications.push({ message, type });
    },
  },
};
console.error = (...args) => diagnostics.push(args.join(" "));
await calmCommand.handler("", ctx);
console.error = originalConsoleError;

const bashEntry = registry.get("bash");
if (bashEntry.tool !== foreignBash) {
  throw new Error("Calm replaced the foreign extension's bash registration instead of leaving it alone");
}
const bashResult = await bashEntry.tool.execute();
if (bashResult.content[0]?.text !== FOREIGN_MARKER) {
  throw new Error("the foreign extension's bash tool no longer executes its own real behavior");
}
for (const name of ["read", "edit", "write", "grep", "find", "ls"]) {
  const entry = registry.get(name);
  if (!entry || entry.ownerPath !== extPath) {
    throw new Error(`Calm failed to claim the uncontested built-in "${name}" on first activation`);
  }
}

// Part C: a single, prominent, user-facing warning naming the contested tool, not
// merely a console diagnostic.
if (notifications.length !== 1) {
  throw new Error(`expected exactly one contested-tool notification, saw ${JSON.stringify(notifications)}`);
}
if (notifications[0].type !== "warning") {
  throw new Error(`contested-tool notification was not type "warning": ${JSON.stringify(notifications[0])}`);
}
if (!notifications[0].message.includes("bash") || !notifications[0].message.toLowerCase().includes("calm")) {
  throw new Error(`contested-tool notification did not name the tool clearly: ${JSON.stringify(notifications[0])}`);
}
const sawBashDiagnostic = diagnostics.some((line) => line.includes("bash"));
if (!sawBashDiagnostic) {
  throw new Error(`expected a console diagnostic naming the skipped built-in too; saw: ${JSON.stringify(diagnostics)}`);
}

// The documented bound itself: still non-empty after Calm is now active, because it
// was constructed before Calm ever claimed anything.
if (preToggleRead.render(100).length === 0) {
  throw new Error("a pre-activation tool row retroactively hid after Calm turned on; the documented bound regressed");
}

// A row for the same tool constructed after activation behaves normally: it does hide.
const postToggleRead = new ToolExecutionComponent(
  "read",
  "post-toggle-read",
  preToggleReadArgs,
  { showImages: false },
  registry.get("read")?.tool,
  renderUi,
  process.cwd(),
);
postToggleRead.markExecutionStarted();
postToggleRead.setArgsComplete();
postToggleRead.updateResult({ content: [{ type: "text", text: "POST_TOGGLE_READ_OUTPUT" }], details: {}, isError: false });
if (postToggleRead.render(100).length !== 0) {
  throw new Error("a tool row constructed after Calm's activation did not hide");
}
JS
  status=$?
  out=$(cat "$output_file")
  [ "$status" -eq 0 ] || fail "Pi calm activation/collision/regression-bound path failed: $out"
  [ -z "$out" ] || fail "Pi calm activation/collision/regression-bound test printed output: $out"
  pass "Calm's first same-session /calm activation claims every uncontested built-in, leaves a foreign bash tool fully intact and callable, warns prominently and logs the contested name, and only rows constructed before that activation - the documented bound - fail to retroactively collapse"
}

test_rendering_and_session_lifecycle() {
  local fixture out output_file status version
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "skip: node or npm not found for Pi calm renderer test"
    return 0
  fi
  if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
    echo "skip: installed @earendil-works/pi-coding-agent package not found"
    return 0
  fi
  version=$(node -p "require('$PI_PACKAGE_DIR/package.json').version")
  record_pi_version_evidence "$version" "Pi calm compatibility assumptions"

  fixture="$TMP_ROOT/renderer"
  mkdir -p "$fixture/home" "$fixture/lib" "$fixture/node_modules/@earendil-works"
  cp "$EXT" "$fixture/fm-calm.ts"
  cp "$ASSISTANT_LAYOUT" "$fixture/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/lib/fm-calm-working-ship.ts"
  cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" "$fixture/lib/fm-operational-input.ts"
  cp "$WATCH_EXT" "$fixture/fm-primary-pi-watch.ts"
  ln -s "$PI_PACKAGE_DIR" "$fixture/node_modules/@earendil-works/pi-coding-agent"
  ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$fixture/node_modules/@earendil-works/pi-tui"
  ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$fixture/node_modules/typebox"
  printf '%s\n' '{"type":"module"}' >"$fixture/package.json"
  cat >"$fixture/operational-input-probe.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1-}" >>"$FM_OPERATIONAL_INPUT_CALLS"
exec "$FM_OPERATIONAL_INPUT_OWNER" "$@"
SH
  chmod +x "$fixture/operational-input-probe.sh"

  output_file="$fixture/node-output"
  (cd "$fixture" && EXT="$fixture/fm-calm.ts" WATCH_EXT="$fixture/fm-primary-pi-watch.ts" FM_HOME="$fixture/home" FM_OPERATIONAL_INPUT_SCRIPT="$fixture/operational-input-probe.sh" FM_OPERATIONAL_INPUT_OWNER="$OPERATIONAL_INPUT" FM_OPERATIONAL_INPUT_CALLS="$fixture/operational-input-calls" PI_PACKAGE_DIR="$PI_PACKAGE_DIR" node --input-type=module) >"$output_file" 2>&1 <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

// fm-calm.ts derives its own identity the same way (fileURLToPath(import.meta.url)),
// which normalizes away irregularities like a symlinked TMPDIR (macOS /tmp, /var);
// comparing against the raw env var would spuriously read this fixture's own
// registration as foreign.
const extPath = fileURLToPath(pathToFileURL(process.env.EXT).href);

const packageRoot = process.env.PI_PACKAGE_DIR;
const [{ AssistantMessageComponent }, { CustomEntryComponent }, { ToolExecutionComponent }, { UserMessageComponent }, { InteractiveMode }, { initTheme, theme }, { Text, getKeybindings, setCapabilities }, { createToolHtmlRenderer }] = await Promise.all([
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/components/assistant-message.js`).href),
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/components/custom-entry.js`).href),
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/components/tool-execution.js`).href),
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/components/user-message.js`).href),
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/interactive-mode.js`).href),
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/theme/theme.js`).href),
  import(pathToFileURL(`${packageRoot}/node_modules/@earendil-works/pi-tui/dist/index.js`).href),
  import(pathToFileURL(`${packageRoot}/dist/core/export-html/tool-renderer.js`).href),
]);
initTheme("dark");
setCapabilities({ images: null, trueColor: true, hyperlinks: false });

const tools = [];
const handlers = new Map();
const entryRenderers = new Map();
const eventListeners = new Map();
let calmCommand;
const pi = {
  events: {
    emit(name, data) {
      for (const listener of eventListeners.get(name) ?? []) listener(data);
    },
    on(name, listener) {
      const listeners = eventListeners.get(name) ?? [];
      listeners.push(listener);
      eventListeners.set(name, listeners);
    },
  },
  on(event, handler) {
    const eventHandlers = handlers.get(event) ?? [];
    eventHandlers.push(handler);
    handlers.set(event, eventHandlers);
  },
  registerCommand(name, command) {
    if (name === "calm") calmCommand = command;
  },
  registerEntryRenderer(customType, renderer) {
    entryRenderers.set(customType, renderer);
  },
  registerTool(tool) {
    const existingIndex = tools.findIndex((existing) => existing.name === tool.name);
    if (existingIndex === -1) tools.push(tool);
    else tools[existingIndex] = tool;
  },
  getAllTools() {
    // Only Calm itself has registered anything in this fixture, so every entry
    // reports Calm's own extension path; the dedicated collision fixture below is
    // what exercises a foreign extension already owning a name.
    return tools.map((tool) => ({
      name: tool.name,
      sourceInfo: { source: "extension", path: extPath },
    }));
  },
};
const extension = await import(`${pathToFileURL(process.env.EXT).href}?test=${Date.now()}`);
extension.default(pi);
const visibility = await import(`${pathToFileURL(`${process.cwd()}/lib/fm-calm-visibility.ts`).href}?policy=${Date.now()}`);
const operationalInput = await import(`${pathToFileURL(`${process.cwd()}/lib/fm-operational-input.ts`).href}?input=${Date.now()}`);

// Registration is gated on config/calm at load (see fm-calm.ts's file header); this
// fixture has no config/calm file, so nothing is registered yet. Every render-
// equivalence assertion below needs the wrapped definitions the way a user who kept
// Calm on across a previous session would already have them, so force that here via
// the same /calm command path a real activation uses, then round-trip back off so the
// rest of this fixture's own off/on toggle sequence still observes its usual starting
// state. This does not touch the calm-off/toggle-on assertions further down: those
// exercise activateBuiltInsIfNeeded's own contested-name skip and warning through the
// dedicated fixture below, not this one.
const earlyActivationUi = {
  getEditorText: () => "",
  getToolsExpanded: () => false,
  onTerminalInput: () => () => {},
  setHiddenThinkingLabel() {},
  setStatus() {},
  setToolsExpanded() {},
  setWorkingVisible() {},
  notify() {},
};
await calmCommand.handler("", { ui: earlyActivationUi });
await calmCommand.handler("", { ui: earlyActivationUi });

const names = tools.map((tool) => tool.name);
const expectedNames = ["read", "bash", "edit", "write", "grep", "find", "ls"];
if (JSON.stringify(names) !== JSON.stringify(expectedNames)) {
  throw new Error(`unexpected wrapped built-ins: ${names.join(",")}`);
}
if (!calmCommand || !handlers.has("session_start")) {
  throw new Error("calm command or session lifecycle handler was not registered");
}
if (handlers.has("input")) {
  throw new Error("Calm registered a semantic input interceptor");
}
if (
  calmCommand.description !==
  "Toggle Firstmate's supported conversation-only transcript presentation."
) {
  throw new Error(`unexpected calm command description: ${calmCommand.description}`);
}

for (const itemClass of visibility.CALM_TRANSCRIPT_CLASSES) {
  const visible = visibility.calmTranscriptClassIsVisible(itemClass);
  const expected =
    itemClass === "genuine-user-prompt" ||
    itemClass === "genuine-agent-response" ||
    itemClass === "working-status";
  if (visible !== expected) {
    throw new Error(`Calm allowlist classified ${itemClass} as visible=${visible}`);
  }
}
const watcherBody =
  "FIRSTMATE WATCHER WAKE: signal: /tmp/probe.status\n\n" +
  "Run bin/fm-wake-drain.sh first and handle the queued wake. Watcher continuity is extension-owned.";
const watcherMessage = operationalInput.encodeFirstmateOperationalInput("watcher", watcherBody);
const legacyAwayMessage = "\u2063Supervisor escalate (legacy presentation compatibility)";
const operationalHistory = [];
const operationalChat = {
  children: [new Text("VISIBLE_PREDECESSOR", 0, 0)],
  addChild(component) {
    this.children.push(component);
  },
};
const operationalMode = {
  chatContainer: operationalChat,
  editor: { addToHistory: (value) => operationalHistory.push(value) },
  getMarkdownThemeWithSettings: () => undefined,
  getUserMessageText: (message) => typeof message.content === "string"
    ? message.content
    : message.content.filter((item) => item.type === "text").map((item) => item.text).join(""),
  outputPad: 1,
};
const callsBeforePlainReplay = readFileSync(process.env.FM_OPERATIONAL_INPUT_CALLS, "utf8");
const plainReplayChat = {
  children: [],
  addChild(component) {
    this.children.push(component);
  },
};
for (let index = 0; index < 50; index += 1) {
  InteractiveMode.prototype.addMessageToChat.call(
    { ...operationalMode, chatContainer: plainReplayChat },
    { role: "user", content: `ORDINARY_REPLAY_${index}` },
  );
}
if (readFileSync(process.env.FM_OPERATIONAL_INPUT_CALLS, "utf8") !== callsBeforePlainReplay) {
  throw new Error("ordinary replay rows invoked operational subprocess classification");
}
InteractiveMode.prototype.addMessageToChat.call(
  operationalMode,
  { role: "user", content: [{ type: "text", text: watcherMessage }] },
  { populateHistory: true },
);
InteractiveMode.prototype.addMessageToChat.call(
  operationalMode,
  { role: "user", content: legacyAwayMessage },
);
const operationalComponent = operationalChat.children[1];
const legacyOperationalComponent = operationalChat.children[2];
const stockOperationalComponent = new UserMessageComponent(watcherMessage, undefined, 1);
const expectedCalmOffOperationalRows = ["", ...stockOperationalComponent.render(100)];
if (JSON.stringify(operationalComponent.render(100)) !== JSON.stringify(expectedCalmOffOperationalRows)) {
  throw new Error("Calm-off operational user rendering changed from Pi stock rows");
}
if (operationalHistory.length !== 1 || operationalHistory[0] !== watcherMessage) {
  throw new Error("operational user presentation changed Pi input history behavior");
}

writeFileSync("sample.txt", "alpha\n");
const cases = [
  ["read", { path: "sample.txt" }, { content: [{ type: "text", text: "alpha" }], details: {}, isError: false }],
  ["bash", { command: "printf 'CALM_RENDER_OUTPUT\\n'" }, { content: [{ type: "text", text: "CALM_RENDER_OUTPUT" }], details: {}, isError: false }],
  ["edit", { path: "sample.txt", edits: [{ oldText: "alpha", newText: "beta" }] }, { content: [{ type: "text", text: "Successfully replaced 1 block(s) in sample.txt." }], details: { diff: "-alpha\n+beta", patch: "", firstChangedLine: 1 }, isError: false }],
  ["write", { path: "sample.txt", content: "beta\n" }, { content: [{ type: "text", text: "Successfully wrote 5 bytes to sample.txt" }], details: undefined, isError: false }],
  ["grep", { pattern: "alpha", path: "." }, { content: [{ type: "text", text: "sample.txt:1:alpha" }], details: {}, isError: false }],
  ["find", { pattern: "*.txt", path: "." }, { content: [{ type: "text", text: "sample.txt" }], details: {}, isError: false }],
  ["ls", { path: "." }, { content: [{ type: "text", text: "sample.txt" }], details: {}, isError: false }],
];
const renderUi = { requestRender() {} };
const rows = [];
for (const [name, args, result] of cases) {
  const wrapped = tools.find((tool) => tool.name === name);
  const baseline = new ToolExecutionComponent(name, `baseline-${name}`, args, { showImages: false }, undefined, renderUi, process.cwd());
  const actual = new ToolExecutionComponent(name, `wrapped-${name}`, args, { showImages: false }, wrapped, renderUi, process.cwd());
  for (const row of [baseline, actual]) {
    row.markExecutionStarted();
    row.setArgsComplete();
    row.updateResult(result);
  }
  const collapsedExpected = baseline.render(100);
  const collapsedActual = actual.render(100);
  if (JSON.stringify(collapsedActual) !== JSON.stringify(collapsedExpected)) {
    throw new Error(`${name} collapsed rendering changed while calm mode was off`);
  }
  baseline.setExpanded(true);
  actual.setExpanded(true);
  const expandedExpected = baseline.render(100);
  const expandedActual = actual.render(100);
  if (JSON.stringify(expandedActual) !== JSON.stringify(expandedExpected)) {
    throw new Error(`${name} expanded rendering changed while calm mode was off`);
  }
  rows.push({ name, baseline, actual });
}

const watchPi = {
  ...pi,
  appendEntry() {},
  sendMessage() {},
  registerCommand() {},
  registerEntryRenderer() {},
};
const watchExtension = await import(`${pathToFileURL(process.env.WATCH_EXT).href}?test=${Date.now()}`);
watchExtension.default(watchPi);
const watchTool = tools.find((tool) => tool.name === "fm_watch_arm_pi");
if (!watchTool) throw new Error("Firstmate watcher extension did not register fm_watch_arm_pi");
const stockWatchTool = { ...watchTool };
delete stockWatchTool.renderCall;
delete stockWatchTool.renderResult;
delete stockWatchTool.renderShell;
const watchArgs = {};
const watchResult = {
  content: [{ type: "text", text: "watcher: started Pi extension arm child 1" }],
  details: { ok: true, message: "watcher: started Pi extension arm child 1" },
  isError: false,
};
const watchBaseline = new ToolExecutionComponent(
  "fm_watch_arm_pi",
  "watch-baseline",
  watchArgs,
  { showImages: false },
  stockWatchTool,
  renderUi,
  process.cwd(),
);
const watchActual = new ToolExecutionComponent(
  "fm_watch_arm_pi",
  "watch-actual",
  watchArgs,
  { showImages: false },
  watchTool,
  renderUi,
  process.cwd(),
);
for (const row of [watchBaseline, watchActual]) {
  row.markExecutionStarted();
  row.setArgsComplete();
  row.updateResult(watchResult);
}
if (JSON.stringify(watchActual.render(100)) !== JSON.stringify(watchBaseline.render(100))) {
  throw new Error("Firstmate watcher tool changed stock rendering while Calm was off");
}

const customDefinition = {
  name: "third_party_tool",
  label: "Third party tool",
  description: "Custom-tool boundary probe",
  parameters: { type: "object", properties: {} },
  renderShell: "self",
  async execute() {
    return { content: [{ type: "text", text: "CUSTOM_RESULT" }], details: {} };
  },
  renderCall() {
    return new Text("CUSTOM_CALL", 0, 0);
  },
  renderResult() {
    return new Text("CUSTOM_RESULT", 0, 0);
  },
};
const customRow = new ToolExecutionComponent(
  "third_party_tool",
  "custom-row",
  {},
  { showImages: false },
  customDefinition,
  renderUi,
  process.cwd(),
);
customRow.markExecutionStarted();
customRow.setArgsComplete();
customRow.updateResult({ content: [{ type: "text", text: "CUSTOM_RESULT" }], details: {}, isError: false });

setCapabilities({ images: "iterm2", trueColor: true, hyperlinks: true });
const imageRow = new ToolExecutionComponent(
  "read",
  "read-image-row",
  { path: "pixel.png" },
  { showImages: true },
  tools.find((tool) => tool.name === "read"),
  renderUi,
  process.cwd(),
);
imageRow.markExecutionStarted();
imageRow.setArgsComplete();
imageRow.updateResult({
  content: [
    {
      type: "image",
      data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
      mimeType: "image/png",
    },
  ],
  details: {},
  isError: false,
});
imageRow.setExpanded(true);
const imageVisibleBefore = imageRow.render(100);
if (!imageVisibleBefore.join("\n").includes("\x1b]1337;File=")) {
  throw new Error("image-capable Pi fixture did not render the built-in read image boundary");
}

const assistantBase = {
  role: "assistant",
  api: "calm-render-test",
  provider: "calm-render-test",
  model: "deterministic",
  usage: {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  },
  stopReason: "stop",
  timestamp: 1,
};
const assistantTextOnly = new AssistantMessageComponent({
  ...assistantBase,
  content: [{ type: "text", text: "VISIBLE_ASSISTANT_TEXT" }],
}, true);
const assistantThinkingText = new AssistantMessageComponent({
  ...assistantBase,
  content: [
    { type: "thinking", thinking: "HIDDEN_FINAL_THINKING" },
    { type: "text", text: "VISIBLE_ASSISTANT_TEXT" },
  ],
}, true);
const assistantThinkingTool = new AssistantMessageComponent({
  ...assistantBase,
  content: [
    { type: "thinking", thinking: "HIDDEN_TOOL_THINKING" },
    { type: "toolCall", id: "assistant-layout-tool", name: "read", arguments: { path: "sample.txt" } },
  ],
  stopReason: "toolUse",
}, true);
if (!assistantThinkingText.render(100).join("\n").includes("Thinking...")) {
  throw new Error("stock collapsed-thinking fixture did not render before Calm was active");
}

const assistantComponents = [assistantTextOnly, assistantThinkingText, assistantThinkingTool];
let expanded = true;
let editorText = "";
let terminalInputHandler;
let workingVisible;
let hiddenThinkingLabel = "unset";
const statuses = new Map();
const sessionEntries = [{ type: "message", message: { role: "toolResult", content: "kept" } }];
const entriesBefore = JSON.stringify(sessionEntries);
const commandContext = {
  sessionManager: { getEntries: () => sessionEntries },
  ui: {
    getEditorText: () => editorText,
    getToolsExpanded: () => expanded,
    onTerminalInput(handler) {
      terminalInputHandler = handler;
      return () => {
        if (terminalInputHandler === handler) terminalInputHandler = undefined;
      };
    },
    setHiddenThinkingLabel(value) {
      hiddenThinkingLabel = value;
      for (const component of assistantComponents) {
        component.setHiddenThinkingLabel(value ?? "Thinking...");
      }
    },
    setStatus(key, value) {
      statuses.set(key, value);
    },
    setToolsExpanded(value) {
      expanded = value;
      for (const row of rows) row.actual.setExpanded(value);
      watchActual.setExpanded(value);
      customRow.setExpanded(value);
      imageRow.setExpanded(value);
    },
    setWorkingVisible(value) {
      workingVisible = value;
    },
  },
};

await handlers.get("session_start")[0]({ reason: "startup" }, commandContext);
if (workingVisible !== true || hiddenThinkingLabel !== undefined) {
  throw new Error("session start did not restore Pi's stock working and thinking presentation");
}
const presentationRenderer = entryRenderers.get("firstmate-synthetic-input-presentation");
if (!presentationRenderer) throw new Error("legacy synthetic presentation renderer was not registered");
const presentationEntry = {
  customType: "firstmate-synthetic-input-presentation",
  data: { content: watcherMessage, kind: "watcher" },
};
const presentationComponent = new CustomEntryComponent(presentationEntry, presentationRenderer);
presentationComponent.setExpanded(expanded);
if (
  !presentationComponent.hasContent() ||
  !presentationComponent.render(100).join("\n").includes("FIRSTMATE WATCHER WAKE")
) {
  throw new Error("Calm-off legacy synthetic presentation did not use a stock user-message row");
}

await calmCommand.handler("", commandContext);
if (expanded !== true || workingVisible !== true || hiddenThinkingLabel !== "" || statuses.get("firstmate-calm") !== undefined) {
  throw new Error("Calm did not preserve working visibility or apply its thinking and footer presentation controls");
}
if (readFileSync(`${process.env.FM_HOME}/config/calm`, "utf8") !== "on\n") {
  throw new Error("Calm did not persist the active choice in the effective Firstmate home");
}
presentationComponent.setExpanded(!expanded);
if (presentationComponent.hasContent() || presentationComponent.render(100).length !== 0) {
  throw new Error("Calm left a synthetic Firstmate presentation row or spacer visible");
}
if (operationalComponent.render(100).length !== 0) {
  throw new Error("Calm left a current operational user row or its leading spacer visible");
}
if (legacyOperationalComponent.render(100).length !== 0) {
  throw new Error("Calm left the supported bare-marker legacy user row visible");
}
const operationalNearMisses = [
  {
    content: `Captain quote: ${watcherMessage}`,
    visible: "Captain quote:",
  },
  {
    content: "FIRSTMATE_OP: v1 watcher: ASCII_ONLY_CAPTAIN_MESSAGE",
    visible: "ASCII_ONLY_CAPTAIN_MESSAGE",
  },
  {
    content: `Ordinary captain text before ${watcherMessage}`,
    visible: "Ordinary captain text before",
  },
  {
    content: "\u2063ordinary captain text after an unrelated separator",
    visible: "ordinary captain text after an unrelated separator",
  },
  {
    content: "\u2063FIRSTMATE_OP: legacy untyped captain message",
    visible: "legacy untyped captain message",
  },
  {
    content: "Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.",
    visible: "before executing any other instructions",
  },
  {
    content:
      "FIRSTMATE WATCHER WAKE: captain-authored legacy-shaped message\n\n" +
      "Run bin/fm-wake-drain.sh first and handle the queued wake. Watcher continuity is extension-owned.",
    visible: "captain-authored legacy-shaped message",
  },
  {
    content:
      "TURN WOULD END BLIND - supervision is off. The watcher cycle is missing, failed, or unhealthy. " +
      "Follow the harness recovery instruction below before ending the turn.\n\n" +
      "captain-authored legacy-shaped message",
    visible: "captain-authored legacy-shaped message",
  },
  {
    content: [
      { type: "text", text: watcherMessage },
      { type: "image", data: "ignored-by-text-renderer", mimeType: "image/png" },
    ],
    visible: "FIRSTMATE WATCHER WAKE",
  },
];
for (const nearMiss of operationalNearMisses) {
  const chat = {
    children: [new Text("VISIBLE_PREDECESSOR", 0, 0)],
    addChild(component) {
      this.children.push(component);
    },
  };
  InteractiveMode.prototype.addMessageToChat.call(
    { ...operationalMode, chatContainer: chat },
    { role: "user", content: nearMiss.content },
  );
  const rendered = chat.children.flatMap((component) => component.render(180)).join("\n");
  if (!rendered.includes(nearMiss.visible)) {
    throw new Error(`Calm hid an operational near miss: ${nearMiss.visible}`);
  }
}
for (const { name, actual } of rows) {
  if (actual.render(100).length !== 0) {
    throw new Error(`${name} was not hidden before export rendering`);
  }
}
async function assertStockHtmlRendering(command, submitData) {
  editorText = command;
  terminalInputHandler(submitData);
  const htmlRenderer = createToolHtmlRenderer({
    getToolDefinition: (name) => tools.find((tool) => tool.name === name),
    theme,
    cwd: process.cwd(),
  });
  const exportCases = [
    ...cases.filter(([toolName]) => toolName === "grep" || toolName === "find"),
    ["fm_watch_arm_pi", watchArgs, watchResult],
  ];
  for (const [name, args, result] of exportCases) {
    const toolCallId = `${command}-${name}`;
    const callHtml = htmlRenderer.renderCall(toolCallId, name, args);
    const resultHtml = htmlRenderer.renderResult(
      toolCallId,
      name,
      result.content,
      result.details,
      result.isError,
    );
    if (!callHtml || !resultHtml?.expanded) {
      throw new Error(`${name} disappeared from ${command} HTML while calm mode was on`);
    }
  }
  editorText = "";
  await new Promise((resolve) => setTimeout(resolve, 0));
}

await assertStockHtmlRendering("/export calm.html", "\r");
getKeybindings().setUserBindings({ "tui.input.submit": "alt+s" });
editorText = "/export remapped.html";
terminalInputHandler("\r");
const unmatchedRenderer = createToolHtmlRenderer({
  getToolDefinition: (name) => tools.find((tool) => tool.name === name),
  theme,
  cwd: process.cwd(),
});
if (unmatchedRenderer.renderCall("unmatched-submit", "grep", { pattern: "alpha", path: "." })) {
  throw new Error("ordinary non-submit input activated HTML export rendering");
}
editorText = "";
await assertStockHtmlRendering("/share", "\x1bs");
for (const { name, actual } of rows) {
  const rendered = actual.render(100);
  if (rendered.length !== 0) {
    throw new Error(`${name} left residual tool rows while calm mode was on: ${JSON.stringify(rendered)}`);
  }
}
const calmImageOutput = imageRow.render(100).join("\n");
if (!calmImageOutput.includes("\x1b]1337;File=")) {
  throw new Error("calm mode hid the disclosed built-in read image boundary");
}
if (calmImageOutput.includes("pixel.png")) {
  throw new Error("calm mode left the built-in read call shell beside the disclosed image output");
}
if (!customRow.render(100).join("\n").includes("CUSTOM_CALL")) {
  throw new Error("calm mode incorrectly claimed or applied generic custom-tool coverage");
}
if (watchActual.render(100).length !== 0) {
  throw new Error("Calm left the fm_watch_arm_pi call/result shell visible");
}
if (assistantThinkingTool.render(100).length !== 0) {
  throw new Error("Calm-hidden thinking beside a tool call retained vertical height");
}
if (JSON.stringify(assistantThinkingText.render(100)) !== JSON.stringify(assistantTextOnly.render(100))) {
  throw new Error("Calm-hidden thinking changed final assistant row geometry");
}
assistantThinkingTool.setHideThinkingBlock(false);
if (!assistantThinkingTool.render(100).join("\n").includes("HIDDEN_TOOL_THINKING")) {
  throw new Error("expanding thinking did not restore the original reasoning content");
}
assistantThinkingTool.setHideThinkingBlock(true);
if (assistantThinkingTool.render(100).length !== 0) {
  throw new Error("collapsing thinking again restored residual Calm rows");
}
if (JSON.stringify(sessionEntries) !== entriesBefore) {
  throw new Error("calm mode changed session entries or model context");
}

for (const { baseline } of rows) baseline.setExpanded(expanded);
await calmCommand.handler("", commandContext);
presentationComponent.setExpanded(expanded);
if (
  !presentationComponent.hasContent() ||
  !presentationComponent.render(100).join("\n").includes("FIRSTMATE WATCHER WAKE")
) {
  throw new Error("turning Calm off did not restore a legacy synthetic presentation row");
}
if (JSON.stringify(operationalComponent.render(100)) !== JSON.stringify(expectedCalmOffOperationalRows)) {
  throw new Error("turning Calm off did not restore byte-identical operational user rows and spacing");
}
if (!legacyOperationalComponent.render(100).join("\n").includes("legacy presentation compatibility")) {
  throw new Error("turning Calm off did not restore the supported legacy operational row");
}
for (const { name, baseline, actual } of rows) {
  if (JSON.stringify(actual.render(100)) !== JSON.stringify(baseline.render(100))) {
    throw new Error(`${name} did not restore the expanded standard renderer`);
  }
}
if (JSON.stringify(imageRow.render(100)) !== JSON.stringify(imageVisibleBefore)) {
  throw new Error("built-in read image row did not restore its ordinary call shell and image output");
}
if (JSON.stringify(watchActual.render(100)) !== JSON.stringify(watchBaseline.render(100))) {
  throw new Error("fm_watch_arm_pi did not restore its stock call/result shell");
}
if (workingVisible !== true || hiddenThinkingLabel !== undefined || statuses.get("firstmate-calm") !== undefined) {
  throw new Error("turning Calm off did not restore stock presentation controls");
}
if (!assistantThinkingTool.render(100).join("\n").includes("Thinking...")) {
  throw new Error("turning Calm off did not restore the collapsed thinking label");
}
if (readFileSync(`${process.env.FM_HOME}/config/calm`, "utf8") !== "off\n") {
  throw new Error("Calm did not persist the inactive choice in the effective Firstmate home");
}
presentationComponent.setExpanded(expanded);
if (
  !presentationComponent.hasContent() ||
  !presentationComponent.render(100).join("\n").includes("FIRSTMATE WATCHER WAKE")
) {
  throw new Error("turning Calm off did not restore synthetic user-row presentation");
}

await calmCommand.handler("", commandContext);
for (const reason of ["startup", "new", "resume", "fork", "reload"]) {
  await handlers.get("session_start")[0]({ reason }, commandContext);
  for (const row of rows) row.actual.setExpanded(expanded);
  for (const { name, actual } of rows) {
    if (actual.render(100).length !== 0) {
      throw new Error(`${reason} session did not retain the active Calm choice for ${name}`);
    }
  }
  if (workingVisible !== true || hiddenThinkingLabel !== "" || statuses.get("firstmate-calm") !== undefined) {
    throw new Error(`${reason} session did not retain gapless Calm presentation with native working visibility`);
  }
}
await calmCommand.handler("", commandContext);

const readWrapper = tools.find((tool) => tool.name === "read");
const { createReadToolDefinition } = await import(pathToFileURL(`${packageRoot}/dist/index.js`).href);
const originalRead = createReadToolDefinition(process.cwd());
const executeContext = { cwd: process.cwd() };
const [originalResult, wrappedResult] = await Promise.all([
  originalRead.execute("original-read", { path: "sample.txt" }, undefined, undefined, executeContext),
  readWrapper.execute("wrapped-read", { path: "sample.txt" }, undefined, undefined, executeContext),
]);
if (JSON.stringify(wrappedResult) !== JSON.stringify(originalResult)) {
  throw new Error("calm wrapper changed built-in read execution or result data");
}
JS
  status=$?
  out=$(cat "$output_file")
  [ "$status" -eq 0 ] || fail "Pi calm renderer and lifecycle contract failed: $out"
  [ -z "$out" ] || fail "Pi calm renderer test printed output: $out"
  pass "Pi calm centralizes transcript visibility, preserves execution/export data, keeps Pi's stock working row visible while no run is active, and persists its choice across session starts"
}

test_home_resolution
test_pi_compat_no_upper_bound
test_pi_compat_degraded_adapter
test_pi_compat_missing_adapter_exports
test_builtin_gate_load_time
test_calm_activation_collision_and_regression_bound
test_rendering_and_session_lifecycle
