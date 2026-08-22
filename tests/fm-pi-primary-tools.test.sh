#!/usr/bin/env bash
# Public-behavior fixture for the statically registered fm_send Pi tool.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-pi-primary-tools)
EXT="$ROOT/.pi/extensions/fm-primary-pi-watch.ts"
PI_PACKAGE_DIR=${FM_PI_PACKAGE_DIR:-"$(npm root -g 2>/dev/null)/@earendil-works/pi-coding-agent"}

command -v node >/dev/null 2>&1 || { echo "skip: node not found for Pi primary tool fixture"; exit 0; }
command -v npm >/dev/null 2>&1 || { echo "skip: npm not found for Pi primary tool fixture"; exit 0; }
[ -f "$PI_PACKAGE_DIR/package.json" ] || {
  echo "skip: installed @earendil-works/pi-coding-agent package not found"
  exit 0
}

PROJECT="$TMP_ROOT/project"
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$PROJECT/.pi/extensions/lib" "$PROJECT/node_modules/@earendil-works" "$PROJECT/bin" "$HOME_DIR/state"
cp "$EXT" "$PROJECT/.pi/extensions/fm-primary-pi-watch.ts"
cp "$ROOT/.pi/extensions/lib/fm-calm-visibility.ts" "$PROJECT/.pi/extensions/lib/fm-calm-visibility.ts"
cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" "$PROJECT/.pi/extensions/lib/fm-operational-input.ts"
ln -s "$PI_PACKAGE_DIR" "$PROJECT/node_modules/@earendil-works/pi-coding-agent"
ln -s "$PI_PACKAGE_DIR/node_modules/@earendil-works/pi-tui" "$PROJECT/node_modules/@earendil-works/pi-tui"
ln -s "$PI_PACKAGE_DIR/node_modules/typebox" "$PROJECT/node_modules/typebox"
printf '%s\n' '{"type":"module"}' > "$PROJECT/package.json"

cat > "$PROJECT/bin/fm-send-fixture.mjs" <<'NODE'
import { appendFileSync } from "node:fs";

appendFileSync(process.env.FM_FAKE_SEND_LOG, `${JSON.stringify(process.argv.slice(2))}\n`);
if (process.env.FM_FAKE_SEND_STDOUT) process.stdout.write(process.env.FM_FAKE_SEND_STDOUT);
if (process.env.FM_FAKE_SEND_STDERR) process.stderr.write(process.env.FM_FAKE_SEND_STDERR);
const delay = Number(process.env.FM_FAKE_SEND_DELAY_MS || 0);
if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));
process.exit(Number(process.env.FM_FAKE_SEND_EXIT || 0));
NODE
cat > "$PROJECT/bin/fm-send.sh" <<'SH'
#!/usr/bin/env bash
exec node "${FM_FAKE_SEND_HELPER:?}" "$@"
SH
chmod +x "$PROJECT/bin/fm-send.sh"

out=$(cd "$PROJECT" && env PROJECT="$PROJECT" HOME_DIR="$HOME_DIR" EXT="$PROJECT/.pi/extensions/fm-primary-pi-watch.ts" \
  FM_PACKAGE_DIR="$PI_PACKAGE_DIR" FM_FAKE_SEND_LOG="$TMP_ROOT/argv.log" \
  FM_FAKE_SEND_HELPER="$PROJECT/bin/fm-send-fixture.mjs" \
  node --input-type=module 2>&1 <<'JS'
import { readFileSync, realpathSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";
import { Value } from "typebox/value";

const project = realpathSync(process.env.PROJECT);
const home = process.env.HOME_DIR;
const calls = [];
const tools = [];
const handlers = new Map();

function run(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let killed = false;
    const abort = () => {
      killed = true;
      child.kill("SIGTERM");
    };
    if (options.signal?.aborted) abort();
    else options.signal?.addEventListener("abort", abort, { once: true });
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", reject);
    child.on("close", (code) => {
      options.signal?.removeEventListener("abort", abort);
      resolve({ stdout, stderr, code: code ?? 1, killed });
    });
  });
}

const pi = {
  events: { on() {} },
  on(event, handler) { handlers.set(event, handler); },
  registerCommand() {},
  registerTool(tool) { tools.push(tool); },
  sendUserMessage: async () => {},
  async exec(command, args, options) {
    calls.push({ command, args: [...args], options });
    return run(command, args, options);
  },
};

process.env.FM_HOME = home;
process.env.FM_ROOT_OVERRIDE = project;
process.env.FM_FAKE_SEND_LOG = process.env.FM_FAKE_SEND_LOG;
writeFileSync(`${home}/state/.lock`, `${process.pid}\n`);
const extension = await import(`${pathToFileURL(process.env.EXT).href}?fixture=${Date.now()}`);
extension.default(pi);
const tool = tools.find((candidate) => candidate.name === "fm_send");
if (!tool) throw new Error("fm_send was not statically registered");
if (tools.filter((candidate) => candidate.name === "fm_send").length !== 1) {
  throw new Error("fm_send was registered more than once");
}
if (tool.label !== "Send to Firstmate task") throw new Error(`unexpected fm_send label: ${tool.label}`);
const schema = tool.parameters;
if (schema.type !== "object") throw new Error("fm_send schema is not an object");
if (JSON.stringify(Object.keys(schema.properties).sort()) !== JSON.stringify(["message", "resolveKeys", "target"])) {
  throw new Error(`fm_send schema exposed unexpected fields: ${Object.keys(schema.properties)}`);
}
if (JSON.stringify(schema.required) !== JSON.stringify(["target", "message"])) {
  throw new Error(`fm_send schema required fields changed: ${JSON.stringify(schema.required)}`);
}
if (schema.properties.resolveKeys.uniqueItems !== true) throw new Error("fm_send schema does not reject duplicate resolveKeys");
if (Value.Check(schema, { target: "worker-1", message: "literal" }) !== true) {
  throw new Error("fm_send schema rejected a valid task selector");
}
for (const invalid of [
  { target: "lab:w1:p1", message: "literal" },
  { target: "worker-1", message: "" },
  { target: "worker-1", message: "literal", resolveKeys: ["bad key"] },
  { target: "worker-1", message: "literal", resolveKeys: ["same", "same"] },
  { target: "worker-1", message: "literal", endpoint: "lab:w1:p1" },
]) {
  if (Value.Check(schema, invalid)) throw new Error(`fm_send schema accepted invalid input: ${JSON.stringify(invalid)}`);
}

async function rejects(call, expected) {
  let error;
  try {
    await call();
  } catch (caught) {
    error = caught;
  }
  if (!(error instanceof Error) || !error.message.includes(expected)) {
    throw new Error(`expected rejection containing ${expected}, got ${error?.message}`);
  }
  return error;
}

const signalController = new AbortController();
const exactMessage = 'line "quoted" $ \u{1F6A2}\nnext line';
process.env.FM_FAKE_SEND_EXIT = "0";
process.env.FM_FAKE_SEND_STDOUT = "";
process.env.FM_FAKE_SEND_STDERR = "";
writeFileSync(process.env.FM_FAKE_SEND_LOG, "");
const confirmed = await tool.execute(
  "confirmed",
  { target: "worker-1", message: exactMessage, resolveKeys: ["decision.one", "key_two"] },
  signalController.signal,
  undefined,
  {},
);
if (confirmed.details?.schema !== "fm-send-result.v1" || confirmed.details?.status !== "confirmed" || confirmed.details?.exitCode !== 0) {
  throw new Error(`invalid confirmed fm_send result: ${JSON.stringify(confirmed.details)}`);
}
const confirmedCalls = calls.slice();
if (confirmedCalls.length !== 1) throw new Error(`confirmed fm_send retried ${confirmedCalls.length} times`);
if (confirmedCalls[0].command !== `${project}/bin/fm-send.sh`) throw new Error(`fm_send did not use the absolute tracked script: ${confirmedCalls[0].command}`);
if (confirmedCalls[0].options.cwd !== project || confirmedCalls[0].options.signal !== signalController.signal) {
  throw new Error("fm_send did not pass the required cwd and signal to pi.exec");
}
const argv = JSON.parse(readFileSync(process.env.FM_FAKE_SEND_LOG, "utf8").trim());
const expectedArgv = ["worker-1", "--resolve-key", "decision.one", "--resolve-key", "key_two", exactMessage];
if (JSON.stringify(argv) !== JSON.stringify(expectedArgv)) {
  throw new Error(`fm_send changed literal argv: got ${JSON.stringify(argv)}, expected ${JSON.stringify(expectedArgv)}`);
}

process.env.FM_FAKE_SEND_EXIT = "3";
const diagnosticLabel = "useful diagnostic ";
process.env.FM_FAKE_SEND_STDERR = `${diagnosticLabel}${"x".repeat(4083 - Buffer.byteLength(diagnosticLabel))}\u{1F6A2}tail`;
process.env.FM_FAKE_SEND_STDOUT = "";
writeFileSync(process.env.FM_FAKE_SEND_LOG, "");
const beforeUnconfirmed = calls.length;
const unconfirmed = await tool.execute("unconfirmed", { target: "worker-1", message: "once" }, undefined, undefined, {});
if (unconfirmed.details?.schema !== "fm-send-result.v1" || unconfirmed.details?.status !== "unconfirmed" || unconfirmed.details?.exitCode !== 3) {
  throw new Error(`invalid unconfirmed fm_send result: ${JSON.stringify(unconfirmed.details)}`);
}
if (!unconfirmed.details.diagnostic?.includes("useful diagnostic")) throw new Error("exit 3 lost the useful script diagnostic");
if (new TextEncoder().encode(unconfirmed.details.diagnostic).length > 4096) throw new Error("exit 3 diagnostic exceeded its byte bound");
if (unconfirmed.details.diagnostic.includes("\uFFFD")) throw new Error("exit 3 diagnostic split a UTF-8 character");
if (!unconfirmed.content[0].text.includes("do not retype or blindly resend")) {
  throw new Error("exit 3 did not instruct the caller to inspect without blindly resending");
}
if (calls.length !== beforeUnconfirmed + 1) throw new Error("exit 3 caused a retry");

process.env.FM_FAKE_SEND_EXIT = "7";
process.env.FM_FAKE_SEND_STDERR = `stderr ${"x".repeat(10000)}`;
process.env.FM_FAKE_SEND_STDOUT = `stdout ${"y".repeat(10000)}`;
writeFileSync(process.env.FM_FAKE_SEND_LOG, "");
const beforeFailure = calls.length;
const failureError = await rejects(
  () => tool.execute("failure", { target: "worker-1", message: "failure" }, undefined, undefined, {}),
  "exit code 7",
);
if (!failureError.message.includes("[truncated]") || failureError.message.length >= 10000) {
  throw new Error("other failure did not cap stdout/stderr diagnostics");
}
const failureCalls = calls.length - beforeFailure;
if (failureCalls !== 1) throw new Error(`nonzero fm_send failure caused ${failureCalls - 1} retries`);

const beforeInvalid = calls.length;
await rejects(
  () => tool.execute("bad-target", { target: "lab:w1:p1", message: "raw" }, undefined, undefined, {}),
  "not a raw Herdr endpoint",
);
await rejects(
  () => tool.execute("bad-keys", { target: "worker-1", message: "answer", resolveKeys: ["same", "same"] }, undefined, undefined, {}),
  "must not contain duplicates",
);
if (calls.length !== beforeInvalid) throw new Error("invalid fm_send input reached pi.exec");

const beforeMissingHome = calls.length;
delete process.env.FM_HOME;
await rejects(
  () => tool.execute("missing-home", { target: "worker-1", message: "missing" }, undefined, undefined, {}),
  "explicit inherited FM_HOME",
);
if (calls.length !== beforeMissingHome) throw new Error("missing FM_HOME still executed fm-send");
process.env.FM_HOME = home;

process.env.FM_FAKE_SEND_EXIT = "0";
process.env.FM_FAKE_SEND_STDOUT = "";
process.env.FM_FAKE_SEND_STDERR = "";
process.env.FM_FAKE_SEND_DELAY_MS = "1000";
const beforeCancellation = calls.length;
const cancellation = new AbortController();
const pending = tool.execute("cancelled", { target: "worker-1", message: "cancelled" }, cancellation.signal, undefined, {});
setTimeout(() => cancellation.abort(), 20);
await rejects(() => pending, "delivery is unconfirmed");
if (calls.length !== beforeCancellation + 1) throw new Error("cancellation caused a retry");
delete process.env.FM_FAKE_SEND_DELAY_MS;
JS
)
status=$?
expect_code 0 "$status" "fm_send public behavior fixture"
[ -z "$out" ] || fail "fm_send public behavior fixture printed output: $out"
pass "fm_send registers one typed selector/message/key surface, preserves argv, bounds diagnostics, and never retries"
