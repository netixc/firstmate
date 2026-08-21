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
record_pi_version_evidence() {
  local version=$1 context=$2
  [ -n "$version" ] || fail "$context could not determine the installed Pi version"
}

find_chrome() {
  local candidate
  if [ -n "${FM_CHROME_BIN:-}" ] && [ -x "$FM_CHROME_BIN" ]; then
    printf '%s\n' "$FM_CHROME_BIN"
    return 0
  fi
  for candidate in \
    google-chrome \
    google-chrome-stable \
    chromium \
    chromium-browser \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
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
  // Pi builds user rows with the registered markdown transformers from 0.83 onward and
  // without them before that; the stub answers both shapes with the empty list Pi and
  // Firstmate both use today.
  getMarkdownTransformers: () => [],
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
  let restoredReloadRow;
  let retiredRowRenderRequests = 0;
  if (["new", "resume", "fork"].includes(reason)) {
    const retiredRow = new ToolExecutionComponent(
      "read",
      `retired-${reason}-read`,
      { path: "sample.txt" },
      { showImages: false },
      tools.find((tool) => tool.name === "read"),
      { requestRender: () => { retiredRowRenderRequests += 1; } },
      process.cwd(),
    );
    retiredRow.markExecutionStarted();
    retiredRow.setArgsComplete();
    retiredRow.updateResult({
      content: [{ type: "text", text: `RETIRED_${reason.toUpperCase()}_READ_OUTPUT` }],
      details: {},
      isError: false,
    });
    if (retiredRow.render(100).length !== 0) {
      throw new Error(`${reason} retired row was visible before session shutdown`);
    }
    retiredRowRenderRequests = 0;
    await handlers.get("session_shutdown")[0]({ reason }, commandContext);
  }
  if (reason === "reload") {
    restoredReloadRow = new ToolExecutionComponent(
      "read",
      "restored-reload-read",
      { path: "sample.txt" },
      { showImages: false },
      tools.find((tool) => tool.name === "read"),
      renderUi,
      process.cwd(),
    );
    restoredReloadRow.markExecutionStarted();
    restoredReloadRow.setArgsComplete();
    restoredReloadRow.updateResult({
      content: [{ type: "text", text: "RESTORED_RELOAD_READ_OUTPUT" }],
      details: {},
      isError: false,
    });
    if (restoredReloadRow.render(100).length !== 0) {
      throw new Error("restored reload row was visible before session_start");
    }
  }
  await handlers.get("session_start")[0]({ reason }, commandContext);
  if (["new", "resume", "fork"].includes(reason)) {
    editorText = `/export ${reason}.html`;
    terminalInputHandler("\x1bs");
    editorText = "";
    await new Promise((resolve) => setTimeout(resolve, 0));
    if (retiredRowRenderRequests !== 0) {
      throw new Error(`${reason} export repainted a retired session row`);
    }
  }
  if (restoredReloadRow) {
    editorText = "/export reload.html";
    terminalInputHandler("\x1bs");
    restoredReloadRow.invalidate();
    if (!restoredReloadRow.render(100).join("\n").includes("RESTORED_RELOAD_READ_OUTPUT")) {
      throw new Error("restored reload row did not use stock rendering during export");
    }
    editorText = "";
    await new Promise((resolve) => setTimeout(resolve, 0));
    if (restoredReloadRow.render(100).length !== 0) {
      throw new Error("post-reload export did not restore Calm rendering for the restored row");
    }
  }
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

test_calm_mid_turn_working_notes() {
  local fixture out output_file status version
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "skip: node or npm not found for Pi calm mid-turn renderer test"
    return 0
  fi
  if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
    echo "skip: installed @earendil-works/pi-coding-agent package not found"
    return 0
  fi
  version=$(node -p "require('$PI_PACKAGE_DIR/package.json').version")
  record_pi_version_evidence "$version" "Pi calm mid-turn presentation"

  fixture="$TMP_ROOT/calm-mid-turn"
  mkdir -p "$fixture/home" "$fixture/lib" "$fixture/node_modules/@earendil-works"
  cp "$EXT" "$fixture/fm-calm.ts"
  cp "$ASSISTANT_LAYOUT" "$fixture/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/lib/fm-calm-working-ship.ts"
  cp "$PI_OPERATIONAL_INPUT" "$fixture/lib/fm-operational-input.ts"
  ln -s "$PI_PACKAGE_DIR" "$fixture/node_modules/@earendil-works/pi-coding-agent"
  ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$fixture/node_modules/@earendil-works/pi-tui"
  ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$fixture/node_modules/typebox"
  printf '%s\n' '{"type":"module"}' >"$fixture/package.json"

  output_file="$fixture/node-output"
  (cd "$fixture" && EXT="$fixture/fm-calm.ts" FM_HOME="$fixture/home" PI_PACKAGE_DIR="$PI_PACKAGE_DIR" node --input-type=module) >"$output_file" 2>&1 <<'JS'
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_PACKAGE_DIR;
const [{ AssistantMessageComponent }, { initTheme }, { setCapabilities }] = await Promise.all([
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/components/assistant-message.js`).href),
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/theme/theme.js`).href),
  import(pathToFileURL(`${packageRoot}/node_modules/@earendil-works/pi-tui/dist/index.js`).href),
]);
initTheme("dark");
setCapabilities({ images: null, trueColor: true, hyperlinks: false });

// Both extension instances below resolve their own relative "./lib/..." specifiers to
// the same module URLs, so they share one live visibility policy exactly the way a
// single Pi process does.
const visibility = await import(pathToFileURL(`${process.cwd()}/lib/fm-calm-visibility.ts`).href);
const calmPreferencePath = `${process.env.FM_HOME}/config/calm`;
const components = [];
const ui = {
  getEditorText: () => "",
  getToolsExpanded: () => false,
  onTerminalInput: () => () => {},
  setHiddenThinkingLabel(value) {
    // Pi's own fan-out: every mounted assistant row re-runs its layout.
    for (const component of components) component.setHiddenThinkingLabel(value ?? "Thinking...");
  },
  setStatus() {},
  setToolsExpanded() {},
  setWorkingVisible() {},
  notify() {},
};
const context = { ui };

async function loadCalmExtension() {
  const registeredTools = [];
  let sessionStart;
  let calmCommand;
  const pi = {
    events: { emit() {}, on() {} },
    on(event, handler) {
      if (event === "session_start") sessionStart = handler;
    },
    registerCommand(name, command) {
      if (name === "calm") calmCommand = command;
    },
    registerEntryRenderer() {},
    registerTool(tool) {
      registeredTools.push(tool.name);
    },
    getAllTools() {
      return [];
    },
  };
  const extension = await import(`${pathToFileURL(process.env.EXT).href}?instance=${Date.now()}-${Math.random()}`);
  extension.default(pi);
  if (!calmCommand || !sessionStart) {
    throw new Error("Calm extension did not register its command and session handler");
  }
  return { calmCommand, sessionStart, registeredTools };
}

const assistantBase = {
  role: "assistant",
  api: "calm-mid-turn-test",
  provider: "calm-mid-turn-test",
  model: "deterministic",
  usage: {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  },
  timestamp: 1,
};
const toolCall = { type: "toolCall", id: "calm-mid-turn-tool", name: "read", arguments: { path: "sample.txt" } };
const messages = {
  // The reported incident: narration emitted in the same assistant message as a tool call.
  midTurn: {
    ...assistantBase,
    stopReason: "toolUse",
    content: [{ type: "text", text: "MIDTURN_WORKING_NOTE" }, toolCall],
  },
  // The genuine reply that ends a response, which Calm never hides.
  finalReply: {
    ...assistantBase,
    stopReason: "stop",
    content: [{ type: "text", text: "FINAL_REPLY_TEXT" }],
  },
  // Still streaming: finality is unknown, and hiding here would stop a real reply.
  streaming: {
    ...assistantBase,
    stopReason: "pending",
    content: [{ type: "text", text: "STREAMING_NOTE_TEXT" }],
  },
  // Truncated with tool calls is mid-turn; Pi's own truncation notice stays.
  truncatedMidTurn: {
    ...assistantBase,
    stopReason: "length",
    content: [{ type: "text", text: "TRUNCATED_MIDTURN_NOTE" }, toolCall],
  },
  // Truncated without tool calls ended the response.
  truncatedFinal: {
    ...assistantBase,
    stopReason: "length",
    content: [{ type: "text", text: "TRUNCATED_FINAL_TEXT" }],
  },
};
const messagesBefore = JSON.stringify(messages);
const rows = {};
for (const [name, message] of Object.entries(messages)) {
  rows[name] = new AssistantMessageComponent(message, true);
  components.push(rows[name]);
}
const rendered = (name) => rows[name].render(100);
const renderedText = (name) => rendered(name).join("\n");
const snapshot = () => {
  const shot = {};
  for (const name of Object.keys(rows)) shot[name] = JSON.stringify(rendered(name));
  return shot;
};
const requireVisible = (name, needle, context) => {
  if (rendered(name).length === 0 || !renderedText(name).includes(needle)) {
    throw new Error(`${context}: ${name} lost ${needle}`);
  }
};
const requireHidden = (name, needle, context) => {
  if (renderedText(name).includes(needle)) {
    throw new Error(`${context}: ${name} still rendered ${needle}`);
  }
};

let calm = await loadCalmExtension();
if (calm.registeredTools.length !== 0) {
  throw new Error("Calm claimed built-in tools with no persisted preference");
}
await calm.sessionStart({ reason: "startup" }, context);
const stockRows = snapshot();
for (const name of Object.keys(rows)) {
  if (rendered(name).length === 0) throw new Error(`Calm-off rendering hid ${name}`);
}
requireVisible("midTurn", "MIDTURN_WORKING_NOTE", "Calm off");

await calm.calmCommand.handler("", context);
if (readFileSync(calmPreferencePath, "utf8") !== "on\n") {
  throw new Error("plain /calm from off did not persist on");
}
if (rendered("midTurn").length !== 0) {
  throw new Error(`Calm on left mid-turn working-note rows: ${JSON.stringify(rendered("midTurn"))}`);
}
requireHidden("truncatedMidTurn", "TRUNCATED_MIDTURN_NOTE", "Calm on");
// Pi owns the wording of its truncation notice; Calm must leave that row's own notice
// standing rather than collapsing an incomplete response to nothing.
if (rendered("truncatedMidTurn").length === 0) {
  throw new Error("Calm on removed Pi's own truncation notice with the working note");
}
requireVisible("streaming", "STREAMING_NOTE_TEXT", "Calm on");
requireVisible("truncatedFinal", "TRUNCATED_FINAL_TEXT", "Calm on");
requireVisible("finalReply", "FINAL_REPLY_TEXT", "Calm on");
if (JSON.stringify(rendered("finalReply")) !== stockRows.finalReply) {
  throw new Error("Calm on changed the genuine final reply row");
}
if (JSON.stringify(messages) !== messagesBefore) {
  throw new Error("Calm on mutated the assistant messages instead of a presentation copy");
}

// The removed third level: /calm parses no argument, so every invocation is the plain
// on/off toggle and no third literal is ever persisted.
await calm.calmCommand.handler("max", context);
if (readFileSync(calmPreferencePath, "utf8") !== "off\n") {
  throw new Error("/calm max was still read as a level instead of the plain toggle");
}
requireVisible("midTurn", "MIDTURN_WORKING_NOTE", "Calm off after /calm max");
const restoredRows = snapshot();
for (const name of Object.keys(rows)) {
  if (restoredRows[name] !== stockRows[name]) {
    throw new Error(`turning Calm off did not restore byte-identical ${name} rendering`);
  }
}
await calm.calmCommand.handler("  MaX  ", context);
if (readFileSync(calmPreferencePath, "utf8") !== "on\n" || rendered("midTurn").length !== 0) {
  throw new Error("a spaced, mixed-case argument did not fall through to the plain toggle");
}
await calm.calmCommand.handler("unrecognized", context);
if (readFileSync(calmPreferencePath, "utf8") !== "off\n") {
  throw new Error("an unrecognized /calm argument did not fall back to the plain toggle");
}

// Restart from each persisted value, including the legacy "max" a home upgraded from
// the removed third level still carries: every one restores ordinary Calm, never off.
for (const persisted of ["on\n", "max\n", "max"]) {
  writeFileSync(calmPreferencePath, persisted, "utf8");
  // Scramble the live state the way a fresh process starts, then let a newly loaded
  // extension restore from the persisted file alone.
  visibility.setCalmPresentation(false);
  ui.setHiddenThinkingLabel(undefined);
  requireVisible("midTurn", "MIDTURN_WORKING_NOTE", "scrambled live state");
  calm = await loadCalmExtension();
  if (calm.registeredTools.length !== 7) {
    throw new Error(
      `a session restored from ${JSON.stringify(persisted)} claimed ${calm.registeredTools.length} built-in tools instead of 7`,
    );
  }
  for (const reason of ["startup", "resume", "new", "fork", "reload"]) {
    await calm.sessionStart({ reason }, context);
    if (rendered("midTurn").length !== 0) {
      throw new Error(
        `a ${reason} session restored from ${JSON.stringify(persisted)} did not hide mid-turn working notes`,
      );
    }
    requireVisible("finalReply", "FINAL_REPLY_TEXT", `${reason} session`);
  }
  // A session restored as on toggles to off; one that had wrongly dropped to off would
  // persist "on" here instead.
  await calm.calmCommand.handler("", context);
  if (readFileSync(calmPreferencePath, "utf8") !== "off\n") {
    throw new Error(`${JSON.stringify(persisted)} did not restore as ordinary Calm on`);
  }
  requireVisible("midTurn", "MIDTURN_WORKING_NOTE", "Calm toggled off after restore");
}
if (!existsSync(calmPreferencePath)) {
  throw new Error("Calm stopped persisting its preference file");
}
JS
  status=$?
  out=$(cat "$output_file")
  [ "$status" -eq 0 ] || fail "Pi calm mid-turn contract failed: $out"
  [ -z "$out" ] || fail "Pi calm mid-turn test printed output: $out"
  pass "Pi calm on collapses mid-turn assistant working notes to zero height while Calm off keeps them, leaves streaming, truncated-final, and genuine final replies untouched, never mutates the messages, ignores every /calm argument, and restores a legacy persisted max as ordinary Calm on"
}

test_working_ship_geometry_and_lifecycle() {
  local fixture out status version
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "skip: node or npm not found for Pi Calm working-ship test"
    return 0
  fi
  if [ ! -f "$PI_PACKAGE_DIR/package.json" ]; then
    echo "skip: installed @earendil-works/pi-coding-agent package not found"
    return 0
  fi
  version=$(node -p "require('$PI_PACKAGE_DIR/package.json').version")
  record_pi_version_evidence "$version" "Pi Calm working-ship assumptions"

  fixture="$TMP_ROOT/working-ship"
  mkdir -p "$fixture/home" "$fixture/lib" "$fixture/node_modules/@earendil-works"
  cp "$EXT" "$fixture/fm-calm.ts"
  cp "$ASSISTANT_LAYOUT" "$fixture/lib/fm-calm-assistant-layout.ts"
  cp "$OPERATIONAL_USER_LAYOUT" "$fixture/lib/fm-calm-operational-user-layout.ts"
  cp "$VISIBILITY" "$fixture/lib/fm-calm-visibility.ts"
  cp "$WORKING_SHIP" "$fixture/lib/fm-calm-working-ship.ts"
  cp "$PI_OPERATIONAL_INPUT" "$fixture/lib/fm-operational-input.ts"
  ln -s "$PI_PACKAGE_DIR" "$fixture/node_modules/@earendil-works/pi-coding-agent"
  ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$fixture/node_modules/@earendil-works/pi-tui"
  ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$fixture/node_modules/typebox"
  printf '%s\n' '{"type":"module"}' >"$fixture/package.json"

  out=$(cd "$fixture" && EXT="$fixture/fm-calm.ts" FM_HOME="$fixture/home" PI_PACKAGE_DIR="$PI_PACKAGE_DIR" node --input-type=module 2>&1 <<'JS'
import { pathToFileURL } from "node:url";

const packageRoot = process.env.PI_PACKAGE_DIR;
const [{ initTheme, theme }, { visibleWidth, setCapabilities }] = await Promise.all([
  import(pathToFileURL(`${packageRoot}/dist/modes/interactive/theme/theme.js`).href),
  import(pathToFileURL(`${packageRoot}/node_modules/@earendil-works/pi-tui/dist/index.js`).href),
]);
initTheme("dark");
setCapabilities({ images: null, trueColor: true, hyperlinks: false });

const ship = await import(
  `${pathToFileURL(`${process.cwd()}/lib/fm-calm-working-ship.ts`).href}?ship=${Date.now()}`
);
const {
  CALM_WORKING_SHIP_WIDGET_KEY,
  CALM_WORKING_SHIP_TICK_MS,
  CALM_WORKING_SHIP_TICKS_PER_MOVE,
  createCalmWorkingShipAnimation,
  createCalmWorkingShipWidget,
} = ship;

const ESC = "\u001b";
const BLUE = `${ESC}[34m`;
const YELLOW = `${ESC}[33m`;
const RESET = `${ESC}[39m`;
const strip = (text) => text.replace(new RegExp(`${ESC}\\[[0-9;]*m`, "g"), "");
const check = (condition, message) => {
  if (!condition) throw new Error(message);
};
const sailOf = (frame) => {
  const row = strip(frame[0]);
  if (row.includes("<|")) return "<|";
  if (row.includes("|>")) return "|>";
  return "none";
};

// --- Calm cadence: the boat is materially slower than the water ------------------
{
  // The pre-revision boat moved one column every 140ms. The revised boat must be
  // plainly slower in real use while the water keeps rippling between its steps.
  const msPerColumn = CALM_WORKING_SHIP_TICK_MS * CALM_WORKING_SHIP_TICKS_PER_MOVE;
  check(msPerColumn >= 700, `boat cadence ${msPerColumn}ms per column is not materially slower`);
  check(
    CALM_WORKING_SHIP_TICKS_PER_MOVE >= 2,
    "the water cadence is not independent of and faster than the boat cadence",
  );
  check(
    CALM_WORKING_SHIP_TICK_MS < msPerColumn,
    "the water does not animate faster than the boat moves",
  );
}

// --- Water phases loop independently while the boat stays put --------------------
{
  const width = 40;
  const animation = createCalmWorkingShipAnimation();
  animation.render(width);
  const startPosition = animation.position();
  const waterRows = new Set();
  const phases = new Set();
  for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE - 1; step += 1) {
    animation.tick();
    check(
      animation.position() === startPosition,
      `the boat moved on tick ${step + 1} instead of waiting for its own cadence`,
    );
    waterRows.add(strip(animation.render(width)[1]));
    phases.add(animation.waterPhase());
  }
  check(waterRows.size > 1, "the water did not animate while the boat was stationary");
  check(phases.size > 1, "the water phase did not advance between boat movements");
  // The boat then moves on its own cadence tick.
  animation.tick();
  check(
    animation.position() !== startPosition,
    "the boat never moved on its own cadence tick",
  );
  // Water motion alone must not change the hull column.
  const beforeHull = strip(animation.render(width)[1]).indexOf("\\__/");
  animation.tick();
  const afterHull = strip(animation.render(width)[1]).indexOf("\\__/");
  check(beforeHull === afterHull, "advancing only the water appeared to move the boat");
}

// --- Water phases are bounded, fixed-cell, and never change geometry -------------
{
  const width = 30;
  const animation = createCalmWorkingShipAnimation();
  const seenPhases = new Set();
  for (let step = 0; step < 64; step += 1) {
    const frame = animation.render(width);
    seenPhases.add(animation.waterPhase());
    check(frame.length === 2, `water phase ${animation.waterPhase()} changed the row count`);
    check(
      visibleWidth(frame[1]) === width,
      `water phase ${animation.waterPhase()} changed the visible width`,
    );
    animation.tick();
  }
  check(seenPhases.size > 1 && seenPhases.size <= 8, `water phase set is not bounded: ${seenPhases.size}`);
}

// --- Standard ANSI colors, with resets that prevent bleed ------------------------
{
  const width = 24;
  const animation = createCalmWorkingShipAnimation();
  for (let step = 0; step < 12; step += 1) {
    const [sailRow, waterRow] = animation.render(width);

    // Standard codes only: no bright variants, no 256-color, no RGB.
    for (const row of [sailRow, waterRow]) {
      const codes = row.match(new RegExp(`${ESC}\\[[0-9;]*m`, "g")) ?? [];
      for (const code of codes) {
        check(
          code === BLUE || code === YELLOW || code === RESET,
          `non-standard ANSI escape ${JSON.stringify(code)} in ${JSON.stringify(row)}`,
        );
      }
      check(codes.length > 0, "a rendered row carried no color at all");
      // Every colored run is closed, so nothing bleeds into padding or later frames.
      check(
        codes.filter((c) => c !== RESET).length === codes.filter((c) => c === RESET).length,
        `unbalanced color/reset pairs in ${JSON.stringify(row)}`,
      );
      check(codes[codes.length - 1] === RESET, `row does not end color-reset: ${JSON.stringify(row)}`);
    }

    // Sail-row padding must be plain spaces outside any color run.
    const leading = sailRow.slice(0, sailRow.indexOf(ESC));
    check(/^ *$/.test(leading), `sail row padding was colored: ${JSON.stringify(leading)}`);

    // The complete boat is yellow; every water cell is blue.
    for (const piece of [`${YELLOW}<|${RESET}`, `${YELLOW}|>${RESET}`]) {
      if (sailRow.includes(piece.slice(0, -RESET.length))) {
        check(sailRow.includes(piece), `sail was not a closed yellow run: ${JSON.stringify(sailRow)}`);
      }
    }
    check(
      waterRow.includes(`${YELLOW}\\__/${RESET}`),
      `hull was not a closed yellow run: ${JSON.stringify(waterRow)}`,
    );
    for (const run of waterRow.split(YELLOW)) {
      const blueRuns = run.split(BLUE).slice(1);
      for (const blueRun of blueRuns) {
        const cells = blueRun.slice(0, blueRun.indexOf(RESET));
        check(cells.length > 0, "an empty blue run emitted a bare color escape");
        check(
          /^[~-]+$/.test(cells),
          `blue run contained a non-water cell: ${JSON.stringify(cells)}`,
        );
      }
    }
    animation.tick();
  }
}

// --- ANSI-stripped visible width is exact at every width and phase ---------------
for (let width = 1; width <= 120; width += 1) {
  const animation = createCalmWorkingShipAnimation();
  animation.render(width);
  for (let step = 0; step <= width + 8; step += 1) {
    const frame = animation.render(width);
    const expectedRows = width >= 4 ? 2 : 1;
    check(frame.length === expectedRows, `width ${width} rendered ${frame.length} rows`);
    for (const line of frame) {
      check(
        visibleWidth(line) <= width,
        `width ${width} rendered a ${visibleWidth(line)}-cell line and would wrap`,
      );
      check(
        visibleWidth(line) === strip(line).length,
        `width ${width} let ANSI bytes affect the measured geometry`,
      );
    }
    // The water row always fills the complete usable width.
    const waterRow = frame[frame.length - 1];
    check(
      visibleWidth(waterRow) === width,
      `width ${width} water row was ${visibleWidth(waterRow)} cells instead of full width`,
    );
    animation.tick();
  }
}

// --- Directional sail and exact bounce, including tiny spans ---------------------
for (const width of [40, 16, 8, 6, 5, 4, 3, 2]) {
  const animation = createCalmWorkingShipAnimation();
  animation.render(width);
  const span = width >= 4 ? width - 4 : Math.max(0, width - 2);
  const frames = [];
  for (let step = 0; step < span * CALM_WORKING_SHIP_TICKS_PER_MOVE * 3 + 16; step += 1) {
    const frame = animation.render(width);
    frames.push({ position: animation.position(), sail: sailOf(frame) });
    animation.tick();
  }
  for (const frame of frames) {
    check(
      frame.position >= 0 && frame.position <= span,
      `width ${width} left the track at column ${frame.position}`,
    );
  }
  if (width >= 2) {
    // Every frame must already show the heading it is about to travel, so no frame
    // at or after a reversal shows the old sail.
    for (let index = 1; index < frames.length; index += 1) {
      const previous = frames[index - 1];
      const current = frames[index];
      if (current.position > previous.position) {
        check(
          previous.sail === "<|",
          `width ${width} moved right showing ${previous.sail} at column ${previous.position}`,
        );
      }
      if (current.position < previous.position) {
        check(
          previous.sail === "|>",
          `width ${width} moved left showing ${previous.sail} at column ${previous.position}`,
        );
      }
    }
  }
  if (span > 0) {
    const sails = new Set(frames.map((frame) => frame.sail));
    check(sails.has("<|") && sails.has("|>"), `width ${width} never showed both headings`);
    const positions = frames.map((frame) => frame.position);
    check(Math.min(...positions) === 0, `width ${width} never reached the left edge`);
    check(Math.max(...positions) === span, `width ${width} never reached the right edge`);
    // Both reversals must be covered.
    let rightToLeft = false;
    let leftToRight = false;
    for (let index = 1; index < frames.length; index += 1) {
      if (frames[index - 1].sail === "<|" && frames[index].sail === "|>") rightToLeft = true;
      if (frames[index - 1].sail === "|>" && frames[index].sail === "<|") leftToRight = true;
    }
    check(rightToLeft, `width ${width} never reversed from right to left`);
    check(leftToRight, `width ${width} never reversed from left to right`);
  }
}

// --- Shrink and grow resize clamping ----------------------------------------------
{
  const animation = createCalmWorkingShipAnimation();
  animation.render(80);
  while (animation.position() < 76) animation.tick();
  check(animation.position() === 76, `boat did not reach the wide right edge: ${animation.position()}`);

  const shrunk = animation.render(20);
  check(animation.position() === 16, `shrink did not clamp the track immediately: ${animation.position()}`);
  check(visibleWidth(shrunk[1]) === 20, `shrunk water row was ${visibleWidth(shrunk[1])} cells instead of 20`);
  check(visibleWidth(shrunk[0]) <= 20, "shrunk sail row would wrap");
  check(sailOf(shrunk) === "|>", "the boat did not turn around after being clamped to the right edge");

  for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) animation.tick();
  const afterShrink = animation.render(20);
  check(animation.position() < 16, "the boat stalled at the edge after a shrink");
  check(visibleWidth(afterShrink[1]) === 20, "motion after a shrink broke the water row width");

  const grown = animation.render(60);
  check(visibleWidth(grown[1]) === 60, `grown water row was ${visibleWidth(grown[1])} cells`);
  for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) animation.tick();
  const afterGrow = animation.render(60);
  check(
    animation.position() >= 0 && animation.position() <= 56,
    `motion left the grown track: ${animation.position()}`,
  );
  check(visibleWidth(afterGrow[1]) === 60, "motion after a grow broke the water row width");
}

// --- Deterministic narrow fallbacks ------------------------------------------------
{
  const animation = createCalmWorkingShipAnimation();
  check(JSON.stringify(animation.render(0)) === "[]", "zero width rendered a line");
  for (const width of [1, 2, 3]) {
    const fallback = createCalmWorkingShipAnimation();
    for (let step = 0; step < 12; step += 1) {
      const frame = fallback.render(width);
      check(frame.length === 1, `width ${width} fallback was not a single row`);
      check(visibleWidth(frame[0]) === width, `width ${width} fallback was not exactly ${width} cells`);
      const bare = strip(frame[0]);
      if (width === 1) {
        check(/^[~-]$/.test(bare), `width 1 fallback was not a single water cell: ${bare}`);
      } else {
        check(
          bare.includes("<|") || bare.includes("|>"),
          `width ${width} fallback lost the sail: ${bare}`,
        );
      }
      fallback.tick();
    }
  }
}

// --- Freeze/resume continuity on one shared animation instance ---------------------
// Hiding the working presentation must freeze column and direction. The next widget
// bound to the same animation resumes exactly there; hidden wall time must not jump.
{
  const animation = createCalmWorkingShipAnimation();
  const tui = { requestRender() {} };
  animation.render(40);
  for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE * 7; step += 1) animation.tick();
  animation.render(40);
  const frozenColumn = animation.position();
  const frozenDirection = animation.direction();
  const frozenPhase = animation.waterPhase();
  check(frozenColumn > 0, `continuity setup never left the left edge: ${frozenColumn}`);

  const first = createCalmWorkingShipWidget(tui, animation);
  check(first.render(40) && animation.position() === frozenColumn, "binding a widget moved the frozen boat");
  first.dispose();
  // Dispose freezes; further wall time without ticks must not change logical state.
  check(animation.position() === frozenColumn, "dispose changed the frozen column");
  check(animation.direction() === frozenDirection, "dispose changed the frozen direction");
  check(animation.waterPhase() === frozenPhase, "dispose changed the frozen water phase");

  const resumed = createCalmWorkingShipWidget(tui, animation);
  const firstFrame = resumed.render(40);
  check(
    animation.position() === frozenColumn && animation.direction() === frozenDirection,
    `resume first frame left frozen state: col=${animation.position()} dir=${animation.direction()}`,
  );
  check(sailOf(firstFrame) === (frozenDirection >= 0 ? "<|" : "|>"), "resume first frame lost sail heading");
  check(animation.waterPhase() === frozenPhase, "resume advanced water phase without a tick");
  // After resume, motion continues from the frozen state rather than restarting.
  for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) animation.tick();
  check(
    animation.position() === frozenColumn + frozenDirection,
    `post-resume motion did not continue from frozen column: ${animation.position()}`,
  );
  resumed.dispose();

  // Hidden resize clamps without needing a live widget, and preserves a valid heading.
  animation.render(80);
  while (animation.position() < 76) animation.tick();
  animation.render(80);
  check(animation.position() === 76 && animation.direction() === -1, "endpoint setup failed before hidden resize");
  const beforeHiddenResize = { column: animation.position(), direction: animation.direction(), phase: animation.waterPhase() };
  animation.clampToWidth(20);
  check(animation.position() === 16, `hidden shrink did not clamp: ${animation.position()}`);
  check(animation.direction() === -1, "hidden shrink lost the leftward heading at the right edge");
  check(animation.waterPhase() === beforeHiddenResize.phase, "hidden clamp advanced water phase");
  // Growing while hidden must not invent motion either.
  animation.clampToWidth(60);
  check(animation.position() === 16, `hidden grow moved the boat: ${animation.position()}`);
  check(animation.direction() === -1, "hidden grow changed direction without cause");

  // Endpoint and bounce continuity: pause immediately before, at, and after each edge.
  for (const scenario of [
    { label: "before-right", setup(anim) {
      anim.reset(); anim.render(12);
      while (anim.position() < 7) anim.tick();
      check(anim.position() === 7 && anim.direction() === 1, "before-right setup");
    }},
    { label: "at-right", setup(anim) {
      anim.reset(); anim.render(12);
      while (anim.position() < 8) anim.tick();
      check(anim.position() === 8 && anim.direction() === -1, "at-right setup");
    }},
    { label: "after-right", setup(anim) {
      anim.reset(); anim.render(12);
      while (anim.position() < 8) anim.tick();
      for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) anim.tick();
      check(anim.position() === 7 && anim.direction() === -1, "after-right setup");
    }},
    { label: "before-left", setup(anim) {
      anim.reset(); anim.render(12);
      while (anim.position() < 8) anim.tick();
      while (!(anim.position() === 1 && anim.direction() === -1)) anim.tick();
    }},
    { label: "at-left", setup(anim) {
      anim.reset(); anim.render(12);
      while (anim.position() < 8) anim.tick();
      while (!(anim.position() === 0 && anim.direction() === 1)) anim.tick();
    }},
    { label: "after-left", setup(anim) {
      anim.reset(); anim.render(12);
      while (anim.position() < 8) anim.tick();
      while (!(anim.position() === 0 && anim.direction() === 1)) anim.tick();
      for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) anim.tick();
      check(anim.position() === 1 && anim.direction() === 1, "after-left setup");
    }},
  ]) {
    const edge = createCalmWorkingShipAnimation();
    scenario.setup(edge);
    edge.render(12);
    const frozen = { column: edge.position(), direction: edge.direction(), phase: edge.waterPhase() };
    const paused = createCalmWorkingShipWidget(tui, edge);
    paused.dispose();
    const again = createCalmWorkingShipWidget(tui, edge);
    again.render(12);
    check(
      edge.position() === frozen.column && edge.direction() === frozen.direction && edge.waterPhase() === frozen.phase,
      `${scenario.label} resume changed frozen edge state`,
    );
    for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) edge.tick();
    const expectedColumn = Math.min(8, Math.max(0, frozen.column + frozen.direction));
    let expectedDirection = frozen.direction;
    if (expectedColumn >= 8) expectedDirection = -1;
    else if (expectedColumn <= 0) expectedDirection = 1;
    check(
      edge.position() === expectedColumn && edge.direction() === expectedDirection,
      `${scenario.label} post-resume bounce drifted: col=${edge.position()} dir=${edge.direction()}`,
    );
    again.dispose();
  }

  // reset() returns a genuine fresh-session initial state.
  animation.reset();
  check(
    animation.position() === 0 && animation.direction() === 1 && animation.waterPhase() === 0,
    "reset() did not restore the normal initial boat state",
  );
  animation.render(40);
  check(sailOf(animation.render(40)) === "<|", "reset() first frame was not the initial rightward sail");

  // Two controller instances never share motion state.
  const left = createCalmWorkingShipAnimation();
  const right = createCalmWorkingShipAnimation();
  left.render(40);
  right.render(40);
  for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE * 3; step += 1) left.tick();
  check(left.position() === 3 && right.position() === 0, "separate animations leaked motion state");
}

{
  const realSetInterval = globalThis.setInterval;
  const realClearInterval = globalThis.clearInterval;
  const callbacks = [];
  const handles = new Set();
  globalThis.setInterval = (callback) => {
    callbacks.push(callback);
    const handle = { unref() {} };
    handles.add(handle);
    return handle;
  };
  globalThis.clearInterval = (handle) => {
    handles.delete(handle);
  };

  try {
    const tui = { renderRequests: 0, requestRender() { this.renderRequests += 1; } };
    const animation = createCalmWorkingShipAnimation();
    const first = createCalmWorkingShipWidget(tui, animation);
    first.render(40);
    callbacks[callbacks.length - 1]();
    callbacks[callbacks.length - 1]();
    check(tui.renderRequests === 2, "unpainted timer ticks did not request renders");
    first.dispose();
    check(handles.size === 0, "disposing the unpainted widget left its timer scheduled");
    check(
      animation.position() === 0 && animation.direction() === 1 && animation.waterPhase() === 0,
      "dispose retained state from unpainted timer ticks",
    );

    const resumed = createCalmWorkingShipWidget(tui, animation);
    resumed.render(40);
    for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) {
      callbacks[callbacks.length - 1]();
    }
    resumed.render(40);
    check(animation.position() === 1, "unpainted ticks leaked into the resumed cadence");
    check(animation.waterPhase() === 0, "resumed cadence did not restore the rendered water phase");
    resumed.dispose();

    const committed = createCalmWorkingShipAnimation();
    const progressing = createCalmWorkingShipWidget(tui, committed);
    progressing.render(40);
    callbacks[callbacks.length - 1]();
    progressing.render(40);
    const renderedPhase = committed.waterPhase();
    callbacks[callbacks.length - 1]();
    progressing.dispose();
    check(committed.position() === 0, "dispose changed the committed column after an unpainted tick");
    check(committed.waterPhase() === renderedPhase, "dispose changed the committed phase after an unpainted tick");

    const committedResume = createCalmWorkingShipWidget(tui, committed);
    committedResume.render(40);
    for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE - 2; step += 1) {
      callbacks[callbacks.length - 1]();
    }
    check(committed.position() === 0, "serviced render did not preserve the committed cadence");
    callbacks[callbacks.length - 1]();
    committedResume.render(40);
    check(committed.position() === 1, "serviced render did not commit progress for the next cadence");
    committedResume.dispose();

    const boundaryCases = [
      [7, 1], [8, -1], [7, -1], [1, -1], [0, 1], [1, 1],
    ];
    for (const [targetPosition, targetDirection] of boundaryCases) {
      const edge = createCalmWorkingShipAnimation();
      edge.render(12);
      let reached = false;
      for (let step = 0; step < 160; step += 1) {
        if (edge.position() === targetPosition && edge.direction() === targetDirection) {
          edge.render(12);
          reached = true;
          break;
        }
        edge.tick();
        edge.render(12);
      }
      check(reached, `could not prepare bounce state ${targetPosition}/${targetDirection}`);
      const before = { position: edge.position(), direction: edge.direction(), phase: edge.waterPhase() };
      const paused = createCalmWorkingShipWidget(tui, edge);
      paused.render(12);
      for (let step = 0; step < CALM_WORKING_SHIP_TICKS_PER_MOVE; step += 1) {
        callbacks[callbacks.length - 1]();
      }
      paused.dispose();
      check(
        edge.position() === before.position &&
          edge.direction() === before.direction &&
          edge.waterPhase() === before.phase,
        `unpainted bounce tick escaped ${targetPosition}/${targetDirection}`,
      );
      const resumedEdge = createCalmWorkingShipWidget(tui, edge);
      resumedEdge.render(12);
      check(
        edge.position() === before.position && edge.direction() === before.direction,
        `bounce state ${targetPosition}/${targetDirection} changed on resume`,
      );
      resumedEdge.dispose();
    }
  } finally {
    globalThis.setInterval = realSetInterval;
    globalThis.clearInterval = realClearInterval;
  }
}

// --- Lifecycle through the Calm extension's registered handlers --------------------
let liveTimers = 0;
const realSetInterval = globalThis.setInterval;
const realClearInterval = globalThis.clearInterval;
globalThis.setInterval = (...args) => {
  liveTimers += 1;
  return realSetInterval(...args);
};
globalThis.clearInterval = (timer) => {
  if (timer !== undefined) liveTimers -= 1;
  return realClearInterval(timer);
};

const sessionWrites = [];
const handlers = new Map();
let calmCommand;
const pi = {
  events: { emit() {}, on() {} },
  on(event, handler) {
    const existing = handlers.get(event) ?? [];
    existing.push(handler);
    handlers.set(event, existing);
  },
  registerCommand(name, command) {
    if (name === "calm") calmCommand = command;
  },
  registerEntryRenderer() {},
  registerTool() {},
  getAllTools() {
    return [];
  },
  appendEntry: (...args) => sessionWrites.push(["appendEntry", ...args]),
  sendMessage: (...args) => sessionWrites.push(["sendMessage", ...args]),
  sendUserMessage: (...args) => sessionWrites.push(["sendUserMessage", ...args]),
  setSessionName: (...args) => sessionWrites.push(["setSessionName", ...args]),
};
const extension = await import(`${pathToFileURL(process.env.EXT).href}?ship=${Date.now()}`);
extension.default(pi);
check(!!calmCommand, "Calm command was not registered");
for (const event of ["session_start", "agent_start", "agent_settled", "session_shutdown"]) {
  check(handlers.has(event), `Calm did not register a ${event} handler`);
}

let renderRequests = 0;
const tui = { requestRender: () => { renderRequests += 1; } };
const ui = {
  workingVisible: [],
  visibilityCalls: 0,
  widgetOps: [],
  widgets: new Map(),
  setWorkingVisible(visible) {
    this.visibilityCalls += 1;
    this.workingVisible.push(visible);
  },
  // Mirrors Pi's documented widget contract: the previous component under a key is
  // disposed before a replacement is installed, and clearing disposes it too.
  setWidget(key, content, options) {
    const existing = this.widgets.get(key);
    if (existing?.dispose) existing.dispose();
    this.widgets.delete(key);
    this.widgetOps.push({
      key,
      action: content === undefined ? "clear" : "set",
      placement: options?.placement,
    });
    if (content === undefined) return;
    this.widgets.set(key, typeof content === "function" ? content(tui, theme) : content);
  },
  getEditorText: () => "",
  getToolsExpanded: () => false,
  onTerminalInput: () => () => {},
  setHiddenThinkingLabel() {},
  setStatus() {},
  setToolsExpanded() {},
  notify() {},
  theme,
};
const ctx = { ui };
const fire = async (event, payload = {}) => {
  for (const handler of handlers.get(event) ?? []) await handler(payload, ctx);
};
const reset = () => {
  ui.workingVisible.length = 0;
  ui.widgetOps.length = 0;
  ui.visibilityCalls = 0;
};
const shipWidget = () => ui.widgets.get(CALM_WORKING_SHIP_WIDGET_KEY);

// --- Calm off leaves Pi's stock working behavior completely untouched -------------
await fire("session_start", { reason: "startup" });
reset();
for (const event of ["agent_start", "agent_settled", "session_shutdown"]) {
  await fire(event, { reason: "quit" });
}
check(
  ui.visibilityCalls === 0,
  `Calm off called setWorkingVisible ${ui.visibilityCalls} times from the run lifecycle`,
);
check(ui.widgetOps.length === 0, `Calm off registered a working widget: ${JSON.stringify(ui.widgetOps)}`);
check(liveTimers === 0, `Calm off started ${liveTimers} animation timers`);

// --- Turning Calm on while idle shows no boat until a run starts -------------------
reset();
await calmCommand.handler("", ctx);
check(ui.widgetOps.length === 0, "toggling Calm on while idle installed a working widget");
check(liveTimers === 0, "toggling Calm on while idle started an animation timer");

// --- Calm on plus an active run shows the boat instead of the stock row -----------
reset();
await fire("agent_start");
check(
  ui.widgetOps.length === 1 &&
    ui.widgetOps[0].key === CALM_WORKING_SHIP_WIDGET_KEY &&
    ui.widgetOps[0].action === "set",
  `Calm on did not install exactly one working widget: ${JSON.stringify(ui.widgetOps)}`,
);
check(ui.widgetOps[0].placement === undefined, "Calm working widget asked for a non-default placement");
check(
  ui.workingVisible[ui.workingVisible.length - 1] === false,
  "Calm on did not hide Pi's stock working row",
);
check(liveTimers === 1, `Calm on kept ${liveTimers} animation timers instead of one`);

const widget = shipWidget();
check(!!widget, "Calm on did not install the working-ship widget");
check(typeof widget.render === "function", "working widget has no render(width)");
check(typeof widget.invalidate === "function", "working widget has no invalidate()");
check(typeof widget.dispose === "function", "working widget has no dispose()");
// A focusable widget could steal input or swallow Escape; this one takes no keys.
check(widget.handleInput === undefined, "working widget accepts keyboard input");
check(widget.wantsKeyRelease === undefined, "working widget asked for key release events");
check(widget.render(60).length === 2, "installed working widget did not render the two-row sprite");
check(
  widget.render(60).every((line) => visibleWidth(line) <= 60),
  "installed working widget rendered a line wider than its viewport",
);

// --- Repeated low-level starts inside one logical run never duplicate anything -----
reset();
for (let repeat = 0; repeat < 5; repeat += 1) await fire("agent_start");
check(ui.widgetOps.length === 0, `repeated starts churned the working widget: ${JSON.stringify(ui.widgetOps)}`);
check(liveTimers === 1, `repeated starts left ${liveTimers} animation timers`);
check(ui.widgets.size === 1, `repeated starts left ${ui.widgets.size} widgets`);
check(shipWidget() === widget, "repeated starts replaced the running widget");

// --- The animation drives Pi's renderer -------------------------------------------
{
  const before = renderRequests;
  await new Promise((resolve) => setTimeout(resolve, CALM_WORKING_SHIP_TICK_MS * 3));
  check(renderRequests > before, "the working animation never requested a TUI render");
}

// --- Settling removes the boat, stops the animation, and restores the stock row ----
// Drive the live widget far enough that a left-edge reset would be observable.
{
  const moving = shipWidget();
  check(!!moving, "continuity setup lost the live working widget");
  moving.render(40);
  await new Promise((resolve) => setTimeout(resolve, CALM_WORKING_SHIP_TICK_MS * CALM_WORKING_SHIP_TICKS_PER_MOVE * 5 + 40));
  moving.render(40);
}
const hullColumn = (widget) => strip(widget.render(40)[1]).indexOf("\\__/");
const freezeColumn = hullColumn(shipWidget());
const freezeSail = sailOf(shipWidget().render(40));
check(freezeColumn > 0, `lifecycle continuity setup never left the left edge: ${freezeColumn}`);

reset();
await fire("agent_settled");
check(
  ui.widgetOps.length === 1 &&
    ui.widgetOps[0].key === CALM_WORKING_SHIP_WIDGET_KEY &&
    ui.widgetOps[0].action === "clear",
  `settling did not clear the working widget: ${JSON.stringify(ui.widgetOps)}`,
);
check(liveTimers === 0, `settling left ${liveTimers} animation timers`);
check(ui.widgets.size === 0, "settling left a residual widget");
check(
  ui.workingVisible[ui.workingVisible.length - 1] === true,
  "settling did not restore Pi's stock working row",
);
{
  // No stale rows survive the removal: the widget renders nothing once disposed.
  const renderRequestsAfterDispose = renderRequests;
  await new Promise((resolve) => setTimeout(resolve, CALM_WORKING_SHIP_TICK_MS * CALM_WORKING_SHIP_TICKS_PER_MOVE * 3));
  check(
    renderRequests === renderRequestsAfterDispose,
    "the animation kept running after the widget was removed",
  );
}

// --- Later working period resumes the frozen column and direction -----------------
reset();
await fire("agent_start");
check(liveTimers === 1, `resume start left ${liveTimers} animation timers instead of one`);
check(ui.widgets.size === 1, "resume start did not install exactly one working widget");
const resumedWidget = shipWidget();
const resumeColumn = hullColumn(resumedWidget);
const resumeSail = sailOf(resumedWidget.render(40));
check(
  resumeColumn === freezeColumn && resumeSail === freezeSail,
  `resume reset the boat instead of continuing: froze ${freezeColumn}/${freezeSail}, resumed ${resumeColumn}/${resumeSail}`,
);
// Repeated start/settle cycles must not duplicate scheduler or widget ownership.
for (let cycle = 0; cycle < 3; cycle += 1) {
  await fire("agent_settled");
  check(liveTimers === 0, `cycle ${cycle} settle left ${liveTimers} timers`);
  check(ui.widgets.size === 0, `cycle ${cycle} settle left a residual widget`);
  await fire("agent_start");
  check(liveTimers === 1, `cycle ${cycle} start left ${liveTimers} timers`);
  check(ui.widgets.size === 1, `cycle ${cycle} start left ${ui.widgets.size} widgets`);
  check(
    hullColumn(shipWidget()) >= freezeColumn,
    `cycle ${cycle} lost continuity after repeated settle/start`,
  );
}
await fire("agent_settled");
check(liveTimers === 0 && ui.widgets.size === 0, "repeated continuity cycles did not finish clean");

// A genuine fresh session resets to the normal initial position.
reset();
await fire("session_start", { reason: "new" });
check(liveTimers === 0 && ui.widgets.size === 0, "fresh session left a stale boat");
await fire("agent_start");
check(hullColumn(shipWidget()) === 0, "fresh session did not restart at the left edge");
check(sailOf(shipWidget().render(40)) === "<|", "fresh session lost the initial rightward sail");
await fire("agent_settled");

// --- Abort and failure share Pi's agent_settled path ------------------------------
// Pi emits agent_settled from a finally block, so an aborted or failed run reaches
// exactly this handler; the real-TUI regression covers the Escape abort path.
for (const outcome of ["abort", "failure"]) {
  reset();
  await fire("agent_start");
  check(liveTimers === 1, `${outcome} setup did not start the animation`);
  await fire("agent_settled");
  check(liveTimers === 0, `${outcome} left ${liveTimers} animation timers`);
  check(ui.widgets.size === 0, `${outcome} left a residual widget`);
  check(
    ui.workingVisible[ui.workingVisible.length - 1] === true,
    `${outcome} did not restore Pi's stock working row`,
  );
}

// --- Shutdown, reload, and session replacement all clean up -----------------------
for (const reason of ["quit", "reload", "new", "resume", "fork"]) {
  reset();
  await fire("agent_start");
  check(liveTimers === 1, `${reason} setup did not start the animation`);
  await fire("session_shutdown", { reason });
  check(liveTimers === 0, `session_shutdown(${reason}) left ${liveTimers} animation timers`);
  check(ui.widgets.size === 0, `session_shutdown(${reason}) left a residual widget`);
  check(
    ui.workingVisible[ui.workingVisible.length - 1] === true,
    `session_shutdown(${reason}) did not restore Pi's stock working row`,
  );
  if (reason === "quit") continue;
  reset();
  await fire("session_start", { reason });
  check(ui.widgets.size === 0, `session_start(${reason}) installed a stale widget`);
  check(liveTimers === 0, `session_start(${reason}) left ${liveTimers} animation timers`);
}

// --- Toggling Calm off during an active run restores the stock row immediately -----
await fire("session_start", { reason: "startup" });
reset();
await fire("agent_start");
check(liveTimers === 1, "active-run setup did not start the animation");
await calmCommand.handler("", ctx);
check(liveTimers === 0, "toggling Calm off during a run left the animation running");
check(ui.widgets.size === 0, "toggling Calm off during a run left the boat on screen");
check(
  ui.workingVisible[ui.workingVisible.length - 1] === true,
  "toggling Calm off during a run did not restore Pi's stock working row",
);

// Toggling Calm back on during the same run returns the boat.
reset();
await calmCommand.handler("", ctx);
check(liveTimers === 1, "toggling Calm on during a run did not return the boat");
check(
  ui.workingVisible[ui.workingVisible.length - 1] === false,
  "toggling Calm on during a run did not hide Pi's stock working row",
);
await fire("agent_settled");
check(liveTimers === 0, "the toggled-on run did not clean up");

// A run started after toggling Calm on while idle uses the boat.
reset();
await calmCommand.handler("", ctx);
await calmCommand.handler("", ctx);
await fire("agent_start");
check(liveTimers === 1, "a later run did not use the boat after an idle Calm toggle");
await fire("agent_settled");
check(liveTimers === 0, "the later run did not clean up");

// --- The visual-only widget never touches session, transcript, or export data ------
check(
  sessionWrites.length === 0,
  `the working presentation wrote session or transcript data: ${JSON.stringify(sessionWrites)}`,
);

globalThis.setInterval = realSetInterval;
globalThis.clearInterval = realClearInterval;
JS
)
  status=$?
  [ "$status" -eq 0 ] || fail "Pi Calm working-ship checks failed: $out"
  [ -z "$out" ] || fail "Pi Calm working-ship test printed output: $out"
  pass "Pi Calm working ship moves on a slow independent cadence over faster fixed-cell blue water, paints the complete boat standard yellow with balanced resets, keeps ANSI-stripped width exact, flips the directional sail on the exact bounce at both edges and every width, clamps visible and hidden resizes, falls back deterministically when narrow, freezes and resumes column/direction across settle/start without hidden-time jumps or duplicate timers, resets only on a fresh session, and installs and removes one scheduler-owning widget across starts, settle, abort, failure, shutdown, reload, replacement, and Calm toggles while leaving Calm-off visibility untouched"
}

test_home_resolution
test_pi_compat_no_upper_bound
test_pi_compat_degraded_adapter
test_pi_compat_missing_adapter_exports
test_builtin_gate_load_time
test_calm_activation_collision_and_regression_bound
test_rendering_and_session_lifecycle
test_calm_mid_turn_working_notes
test_working_ship_geometry_and_lifecycle
