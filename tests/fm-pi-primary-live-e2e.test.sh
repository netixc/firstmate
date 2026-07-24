#!/usr/bin/env bash
# Opt-in credentialed Pi continuity regression on a private tmux socket and
# isolated project/home state. It uses the existing shared Pi auth store without
# copying credentials and pins the captain-approved openai-codex model.
set -u

if [ "${FM_PI_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_PI_LIVE_E2E=1 to run the isolated interactive Pi regression"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unset NO_MISTAKES_GATE

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

command -v pi >/dev/null 2>&1 || fail "pi not found"

TMUX=$(command -v tmux || true)
SOCKET="fm-pi-live-e2e-$$"
SESSION=pi-live-e2e
LAB="$ROOT/.pi-live-e2e.$$"
PROJECT="$LAB/project"
AHOY_PROJECT="$LAB/ahoy-project"
HOME_DIR="$LAB/fmhome"
PI_VERSION=$(pi --version)
# shellcheck source=/dev/null
. "$ROOT/bin/fm-operational-input.sh"
# shellcheck disable=SC2016 # Backticks are literal prompt markup.
LEGACY_START='Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.'
LEGACY_AWAY=$'\xE2\x81\xA3Supervisor escalate (1 event(s)): done: legacy rollout'
MARKER_NEAR_MISS=$'\xE2\x81\xA3Captain note: this invisible separator is intentional.'
# shellcheck disable=SC2016 # Backticks are literal prompt markup.
START_NEAR_MISS='Captain quote: Run `bin/fm-session-start.sh` now, exactly once, before executing any other instructions.'
fm_operational_input_encode watcher "CURRENT_AHOY_WATCHER_BODY" CURRENT_WATCHER \
  || fail "could not construct current Ahoy watcher fixture"
QUOTED_CURRENT="Captain quote: $CURRENT_WATCHER"
ASCII_ONLY='FIRSTMATE_OP: v1 watcher: captain-authored text'

capture() {
  "$TMUX" -L "$SOCKET" capture-pane -p -t "$SESSION" -S -600 2>/dev/null || true
}

wait_for_text() {
  local expected=$1 attempts=${2:-120} i=0
  while [ "$i" -lt "$attempts" ]; do
    if capture | grep -Fq "$expected"; then
      return 0
    fi
    sleep 0.5
    i=$((i + 1))
  done
  capture >&2
  return 1
}

wait_for_exact_line() {
  local expected=$1 attempts=${2:-120} i=0
  while [ "$i" -lt "$attempts" ]; do
    if capture | grep -Fxq " $expected"; then
      return 0
    fi
    sleep 0.5
    i=$((i + 1))
  done
  capture >&2
  return 1
}

lab_pid_is_safe() {
  local pid=$1 command
  command=$(ps -p "$pid" -o command= 2>/dev/null || true)
  case "$command" in
    *"$LAB"*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  local pid_file watcher_pid arm_pid
  pid_file=$(find "$HOME_DIR/state" -maxdepth 3 -type f -name pid 2>/dev/null | head -1 || true)
  watcher_pid=
  arm_pid=
  if [ -n "$pid_file" ]; then
    watcher_pid=$(sed -n '1p' "$pid_file" 2>/dev/null || true)
    arm_pid=$(ps -p "$watcher_pid" -o ppid= 2>/dev/null | tr -d ' ' || true)
  fi
  "$TMUX" -L "$SOCKET" kill-server 2>/dev/null || true
  sleep 0.1
  if [ -n "$watcher_pid" ] && lab_pid_is_safe "$watcher_pid"; then
    kill -TERM "$watcher_pid" 2>/dev/null || true
  fi
  if [ -n "$arm_pid" ] && lab_pid_is_safe "$arm_pid"; then
    kill -TERM "$arm_pid" 2>/dev/null || true
  fi
  rm -rf "$LAB"
}
trap cleanup EXIT

send_prompt() {
  local prompt=$1
  "$TMUX" -L "$SOCKET" send-keys -t "$SESSION" -l "$prompt"
  "$TMUX" -L "$SOCKET" send-keys -t "$SESSION" Enter
}

wait_pid_dead() {
  local pid=$1 i=0
  while [ "$i" -lt 50 ]; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

run_ahoy_case() {
  local label=$1 preceding=$2 expected=$3 out status=0
  out=$(
    cd "$PROJECT" &&
      pi --print --approve --no-session --no-context-files --no-extensions \
        --no-skills --skill .agents/skills --tools read \
        --model openai-codex/gpt-5.6-sol --thinking low \
        "$preceding" "/ahoy"
  ) || status=$?
  [ "$status" -eq 0 ] || fail "Pi Ahoy $label case exited $status: $out"
  case "$expected" in
    bearings)
      printf '%s\n' "$out" | grep -Fq "AHOY_BEARINGS_BRANCH" \
        || fail "Pi Ahoy $label case did not take Bearings: $out"
      ;;
    boundary)
      printf '%s\n' "$out" | grep -Fq "AHOY_BEARINGS_BRANCH" \
        && fail "Pi Ahoy $label near miss was treated as operational: $out"
      ;;
  esac
}

run_ahoy_transcript_regressions() {
  mkdir -p "$PROJECT/.agents/skills/ahoy" "$PROJECT/.agents/skills/bearings"
  cp "$ROOT/.agents/skills/ahoy/SKILL.md" "$PROJECT/.agents/skills/ahoy/SKILL.md"
  # shellcheck disable=SC2016 # Backticks are literal prompt markup.
  printf '%s\n' \
    '---' \
    'name: bearings' \
    'description: Test-only Bearings branch sentinel.' \
    '---' \
    '' \
    '# bearings' \
    '' \
    'Respond exactly `AHOY_BEARINGS_BRANCH`.' \
    > "$PROJECT/.agents/skills/bearings/SKILL.md"

  run_ahoy_case legacy-start "$LEGACY_START" bearings
  run_ahoy_case legacy-away "$LEGACY_AWAY" bearings
  run_ahoy_case marker-near-miss "$MARKER_NEAR_MISS" boundary
  run_ahoy_case startup-near-miss "$START_NEAR_MISS" boundary
  run_ahoy_case quoted-current "$QUOTED_CURRENT" boundary
  run_ahoy_case ascii-only "$ASCII_ONLY" boundary
}

run_native_ahoy_regressions() {
  local first_home="$LAB/pi-ahoy-first-home"
  local later_home="$LAB/pi-ahoy-later-home"
  local first_out later_out

  mkdir -p \
    "$AHOY_PROJECT/.pi/extensions/lib" \
    "$AHOY_PROJECT/.agents/skills/ahoy" \
    "$AHOY_PROJECT/.agents/skills/bearings" \
    "$AHOY_PROJECT/bin" \
    "$first_home/state" "$first_home/config" \
    "$later_home/state" "$later_home/config"
  git init -q "$AHOY_PROJECT"
  cp "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" "$AHOY_PROJECT/.pi/extensions/"
  cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" "$AHOY_PROJECT/.pi/extensions/lib/"
  cp "$ROOT/.pi/extensions/lib/fm-operational-turn.ts" "$AHOY_PROJECT/.pi/extensions/lib/"
  cp \
    "$ROOT/bin/fm-sessionstart-nudge.sh" \
    "$ROOT/bin/fm-primary-scope-lib.sh" \
    "$ROOT/bin/fm-gate-refuse-lib.sh" \
    "$ROOT/bin/fm-operational-input.sh" \
    "$AHOY_PROJECT/bin/"
  cp "$ROOT/.agents/skills/ahoy/SKILL.md" "$AHOY_PROJECT/.agents/skills/ahoy/SKILL.md"
  chmod +x "$AHOY_PROJECT/bin/fm-sessionstart-nudge.sh"
  # shellcheck disable=SC2016 # Variables expand in the generated script, not this test shell.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -u' \
    'file="${FM_HOME:?}/state/session-start-count"' \
    'count=0' \
    '[ ! -f "$file" ] || count=$(sed -n "1p" "$file")' \
    'count=$((count + 1))' \
    'printf "%s\n" "$count" > "$file"' \
    'printf "SESSION_START_DONE count=%s\n" "$count"' \
    > "$AHOY_PROJECT/bin/fm-session-start.sh"
  chmod +x "$AHOY_PROJECT/bin/fm-session-start.sh"
  # shellcheck disable=SC2016 # Backticks are literal prompt markup.
  printf '%s\n' \
    '---' \
    'name: bearings' \
    'description: Test-only Bearings branch sentinel.' \
    '---' \
    '' \
    '# bearings' \
    '' \
    'Respond exactly `AHOY_BEARINGS_BRANCH`.' \
    > "$AHOY_PROJECT/.agents/skills/bearings/SKILL.md"
  # shellcheck disable=SC2016 # Backticks are literal prompt markup.
  printf '%s\n' \
    '# Native Pi Ahoy regression fixture' \
    '' \
    'Run `bin/fm-session-start.sh` exactly once at session start.' \
    > "$AHOY_PROJECT/AGENTS.md"

  first_out=$(
    cd "$AHOY_PROJECT" &&
      FM_HOME="$first_home" pi --print --approve --no-session --no-context-files --no-extensions \
        -e .pi/extensions/fm-primary-turnend-guard.ts \
        --no-skills --skill .agents/skills \
        --model openai-codex/gpt-5.6-sol --thinking low \
        "/ahoy"
  )
  printf '%s\n' "$first_out" | grep -Fq "AHOY_BEARINGS_BRANCH" \
    || fail "Pi native first-message Ahoy did not take Bearings: $first_out"
  [ "$(sed -n '1p' "$first_home/state/session-start-count")" = 1 ] \
    || fail "Pi native first-message Ahoy did not preserve one session-start execution"

  later_out=$(
    cd "$AHOY_PROJECT" &&
      FM_HOME="$later_home" pi --print --approve --no-session --no-context-files --no-extensions \
        -e .pi/extensions/fm-primary-turnend-guard.ts \
        --no-skills --skill .agents/skills \
        --model openai-codex/gpt-5.6-sol --thinking low \
        "Respond exactly PRIOR_BOUNDARY_ACK." "/ahoy"
  )
  printf '%s\n' "$later_out" | grep -Fq "PRIOR_BOUNDARY_ACK" \
    || fail "Pi native later-message setup did not preserve the genuine captain boundary: $later_out"
  printf '%s\n' "$later_out" | grep -Fq "AHOY_BEARINGS_BRANCH" \
    && fail "Pi native later-message Ahoy gathered Bearings: $later_out"
  [ "$(sed -n '1p' "$later_home/state/session-start-count")" = 1 ] \
    || fail "Pi native later-message Ahoy reran session start"
}

# Session-continuity regressions for the two proven Pi primary defects. They run
# against real Pi runtimes with an isolated PI_CODING_AGENT_SESSION_DIR and an
# isolated FM_HOME, and never touch the captain's live home, lock, or session.
build_continuity_repo() {  # <repo>
  local repo=$1
  mkdir -p "$repo/.pi/extensions/lib" "$repo/bin"
  git init -q "$repo"
  printf '# Pi continuity regression fixture\n' > "$repo/AGENTS.md"
  cp "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" \
     "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
     "$ROOT/.pi/extensions/fm-calm.ts" \
     "$repo/.pi/extensions/"
  cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" \
     "$ROOT/.pi/extensions/lib/fm-operational-turn.ts" \
     "$ROOT/.pi/extensions/lib/fm-calm-visibility.ts" \
     "$repo/.pi/extensions/lib/"
  cp "$ROOT/bin/fm-sessionstart-nudge.sh" \
     "$ROOT/bin/fm-primary-scope-lib.sh" \
     "$ROOT/bin/fm-gate-refuse-lib.sh" \
     "$ROOT/bin/fm-operational-input.sh" \
     "$ROOT/bin/fm-lock.sh" \
     "$repo/bin/"
  chmod +x "$repo/bin/fm-sessionstart-nudge.sh" "$repo/bin/fm-operational-input.sh" "$repo/bin/fm-lock.sh"
  # Fixture session start: the real ancestry-walking lock plus a marked digest,
  # so the claim is proven end to end without running fleet-mutating sweeps.
  # shellcheck disable=SC2016 # Variables expand in the generated script, not this test shell.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -u' \
    'file="${FM_HOME:?}/state/session-start-count"' \
    'count=0' \
    '[ ! -f "$file" ] || count=$(sed -n "1p" "$file")' \
    'count=$((count + 1))' \
    'printf "%s\n" "$count" > "$file"' \
    'root="$(cd "$(dirname "$0")/.." && pwd)"' \
    '"$root/bin/fm-lock.sh" >/dev/null 2>&1 || true' \
    'holder=$(sed -n "1p" "${FM_HOME}/state/.lock" 2>/dev/null || true)' \
    'ps -o comm= -p "${holder:-0}" 2>/dev/null | tr -d " " > "${FM_HOME}/state/lock-holder-comm"' \
    'printf "PI_CONTINUITY_DIGEST_SENTINEL count=%s\n" "$count"' \
    > "$repo/bin/fm-session-start.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$repo/bin/fm-arm-pretool-check.sh"
  cp "$repo/bin/fm-arm-pretool-check.sh" "$repo/bin/fm-cd-pretool-check.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'exit 0' > "$repo/bin/fm-turnend-guard.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "drained: 0 record(s)\n"' > "$repo/bin/fm-wake-drain.sh"
  chmod +x "$repo"/bin/*.sh
}

run_session_claim_regression() {
  local repo="$LAB/continuity-claim" home="$LAB/continuity-claim-home" out count holder
  mkdir -p "$home/state" "$home/config"
  build_continuity_repo "$repo"
  # --tools read makes model obedience impossible, which is exactly the state the
  # incident recorded: nothing but the extension can claim the session.
  out=$(
    cd "$repo" &&
      FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" \
      PI_CODING_AGENT_SESSION_DIR="$LAB/continuity-claim-sessions" \
        pi --print --approve --no-session --no-context-files --no-extensions \
          -e .pi/extensions/fm-primary-turnend-guard.ts \
          --no-skills --tools read \
          --model openai-codex/gpt-5.6-sol --thinking low \
          'Quote the session-start sentinel you were given.'
  ) || fail "Pi session-claim regression exited nonzero: $out"
  [ -n "$out" ] || fail "Pi produced no captain-facing answer, so claim ordering is untested"
  count=$(sed -n '1p' "$home/state/session-start-count" 2>/dev/null || printf 'ABSENT')
  [ "$count" = 1 ] || fail "Pi runtime claimed the session $count time(s) instead of exactly once"
  holder=$(sed -n '1p' "$home/state/lock-holder-comm" 2>/dev/null || printf 'ABSENT')
  [ "$holder" = pi ] || fail "the home lock does not name the Pi harness process: $holder"
  printf '%s\n' "$out" | grep -Fq PI_CONTINUITY_DIGEST_SENTINEL \
    || fail "the complete session-start digest did not reach model context: $out"
}

run_single_flight_regression() {
  local repo="$LAB/continuity-flight" home="$LAB/continuity-flight-home"
  local sessions="$LAB/continuity-flight-sessions" driver="$LAB/rpc-drive.mjs" session_file summary
  mkdir -p "$home/state" "$home/config" "$sessions"
  build_continuity_repo "$repo"
  # shellcheck disable=SC2016 # Variables expand in the generated script, not this test shell.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -u' \
    'counter="${FM_HOME:?}/state/arm-count"' \
    'n=0' \
    '[ ! -f "$counter" ] || n=$(sed -n "1p" "$counter")' \
    'n=$((n + 1))' \
    'printf "%s\n" "$n" > "$counter"' \
    'printf "watcher: attached fixture arm %s\n" "$n"' \
    'if [ "$n" -le 2 ]; then' \
    '  sleep 1' \
    '  printf "signal: continuity wake %s\n" "$n"' \
    '  exit 0' \
    'fi' \
    'trap "exit 0" TERM INT' \
    'for _ in $(seq 1 600); do sleep 0.1; done' \
    > "$repo/bin/fm-watch-arm.sh"
  chmod +x "$repo/bin/fm-watch-arm.sh"
  printf '1784835678\t710\tsignal\talpha\tdone: alpha\n1784835679\t711\tstale\tbeta\tstale 900s\n' \
    > "$home/state/.wake-queue"
  # shellcheck disable=SC2016 # Variables expand in the generated script, not this test shell.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -u' \
    ': > "${FM_HOME:?}/state/.wake-queue"' \
    'printf "drained: 2 record(s) seq 710 711\n"' \
    > "$repo/bin/fm-wake-drain.sh"
  chmod +x "$repo/bin/fm-wake-drain.sh"

  cat > "$driver" <<'JS'
import { spawn } from "node:child_process";
const [, , cwd, prompt, ...piArgs] = process.argv;
const child = spawn("pi", ["--mode", "rpc", ...piArgs], { cwd, env: process.env, stdio: ["pipe", "pipe", "inherit"] });
let buffer = "";
let lastEventAt = Date.now();
child.stdout.on("data", (chunk) => {
  buffer += chunk.toString();
  let index;
  while ((index = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, index).replace(/\r$/, "");
    buffer = buffer.slice(index + 1);
    if (line.trim()) lastEventAt = Date.now();
  }
});
await new Promise((resolve) => setTimeout(resolve, 3000));
child.stdin.write(`${JSON.stringify({ id: "p1", type: "prompt", message: prompt })}\n`);
await new Promise((resolve) => {
  const timer = setInterval(() => {
    if (Date.now() - lastEventAt > 25000) {
      clearInterval(timer);
      resolve();
    }
  }, 500);
});
child.kill("SIGTERM");
await new Promise((resolve) => setTimeout(resolve, 1000));
process.exit(0);
JS

  (
    cd "$repo" &&
      FM_HOME="$home" FM_ROOT_OVERRIDE="$repo" PI_CODING_AGENT_SESSION_DIR="$sessions" \
        node "$driver" "$repo" \
          'Use the fm_watch_arm_pi tool once to start supervision, then reply with exactly PI_FLIGHT_ANSWER.' \
          --approve --no-context-files --no-extensions \
          -e .pi/extensions/fm-primary-turnend-guard.ts \
          -e .pi/extensions/fm-calm.ts \
          -e .pi/extensions/fm-primary-pi-watch.ts \
          --model openai-codex/gpt-5.6-sol --thinking low
  ) || fail "Pi single-flight RPC regression could not run"

  session_file=$(find "$sessions" -name '*.jsonl' | head -1)
  [ -n "$session_file" ] || fail "the isolated Pi session file was not written"
  summary=$(node -e '
const { readFileSync } = require("node:fs");
const rows = [];
for (const line of readFileSync(process.argv[1], "utf8").split("\n")) {
  if (!line.trim()) continue;
  let entry;
  try { entry = JSON.parse(line); } catch { continue; }
  if (entry.type === "custom") { rows.push({ kind: "presentation", customType: entry.customType }); continue; }
  if (entry.type === "custom_message") { rows.push({ kind: "context", customType: entry.customType }); continue; }
  if (entry.type !== "message") continue;
  const message = entry.message ?? {};
  if (message.role === "assistant") {
    const text = (message.content ?? []).filter((b) => b.type === "text").map((b) => b.text).join("").trim();
    rows.push({ kind: "assistant", text });
    continue;
  }
  if (message.role === "user") {
    const text = typeof message.content === "string"
      ? message.content
      : (message.content ?? []).filter((b) => b.type === "text").map((b) => b.text).join("");
    // Calm hides operational user rows at presentation only, so a delivered
    // wake stays an ordinary user message carrying the canonical envelope.
    if (text.startsWith(process.argv[2])) rows.push({ kind: "operational" });
    continue;
  }
  if (message.role === "toolResult") rows.push({ kind: "toolResult" });
}
const finals = rows.map((row, index) => ({ ...row, index })).filter((row) => row.kind === "assistant" && row.text);
let repeats = 0;
for (let i = 1; i < finals.length; i += 1) {
  if (finals[i].text !== finals[i - 1].text) continue;
  const between = rows.slice(finals[i - 1].index + 1, finals[i].index);
  if (between.some((row) => row.kind === "operational")) repeats += 1;
}
console.log(JSON.stringify({
  wakeContext: rows.filter((row) => row.kind === "operational").length,
  repeatedFinals: repeats,
}));
' "$session_file" "$FM_OPERATIONAL_PREFIX")
  printf '%s' "$summary" | grep -q '"repeatedFinals":0' \
    || fail "Pi repeated an assistant final separated only by hidden operational input: $summary"
  printf '%s' "$summary" | grep -q '"wakeContext":1' \
    || fail "two actionable closes did not coalesce into one operational delivery: $summary"
  [ ! -s "$home/state/.wake-queue" ] \
    || fail "durable wake records survived the operational turn: $(cat "$home/state/.wake-queue")"
  [ "$(sed -n '1p' "$home/state/arm-count")" -ge 3 ] \
    || fail "extension-owned successor continuity did not survive coalescing"
}

mkdir -p "$LAB"
run_session_claim_regression
run_single_flight_regression
# Each live section costs real model turns. FM_PI_LIVE_E2E_ONLY=continuity runs
# just the session-continuity sections when re-verifying that behavior alone;
# the default remains the complete regression.
if [ "${FM_PI_LIVE_E2E_ONLY:-}" = continuity ]; then
  printf 'ok - Pi %s live E2E covered the deterministic session claim and single-flight operational turns\n' "$PI_VERSION"
  exit 0
fi
git clone -q "$ROOT" "$PROJECT"
run_ahoy_transcript_regressions
run_native_ahoy_regressions
[ -n "$TMUX" ] || fail "tmux not found for the interactive Pi continuity section"
mkdir -p "$PROJECT/.pi/extensions/lib"
cp "$ROOT/.pi/extensions/fm-calm.ts" "$PROJECT/.pi/extensions/fm-calm.ts"
cp "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" "$PROJECT/.pi/extensions/fm-primary-pi-watch.ts"
cp "$ROOT/.pi/extensions/lib/fm-calm-assistant-layout.ts" "$PROJECT/.pi/extensions/lib/fm-calm-assistant-layout.ts"
cp "$ROOT/.pi/extensions/lib/fm-calm-operational-user-layout.ts" "$PROJECT/.pi/extensions/lib/fm-calm-operational-user-layout.ts"
cp "$ROOT/.pi/extensions/lib/fm-calm-visibility.ts" "$PROJECT/.pi/extensions/lib/fm-calm-visibility.ts"
cp "$ROOT/.pi/extensions/lib/fm-operational-input.ts" "$PROJECT/.pi/extensions/lib/fm-operational-input.ts"
cp "$ROOT/.pi/extensions/lib/fm-operational-turn.ts" "$PROJECT/.pi/extensions/lib/fm-operational-turn.ts"
cp "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" "$PROJECT/.pi/extensions/fm-primary-turnend-guard.ts"
cp "$ROOT/bin/fm-watch-arm.sh" "$PROJECT/bin/fm-watch-arm.sh"
cp "$ROOT/bin/fm-operational-input.sh" "$PROJECT/bin/fm-operational-input.sh"
cp "$ROOT/bin/fm-supervision-instructions.sh" "$PROJECT/bin/fm-supervision-instructions.sh"
chmod +x "$PROJECT/bin/fm-operational-input.sh"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"

"$TMUX" -L "$SOCKET" new-session -d -s "$SESSION" -c "$PROJECT" \
  "env FM_HOME='$HOME_DIR' FM_ROOT_OVERRIDE='$PROJECT' FM_POLL=1 FM_SIGNAL_GRACE=0 FM_HEARTBEAT=600 bash -lc 'printf \"%s\\n\" \"\$\$\" > \"\$FM_HOME/state/.lock\"; pi --approve --no-session --no-context-files --no-extensions -e .pi/extensions/fm-calm.ts -e .pi/extensions/fm-primary-turnend-guard.ts -e .pi/extensions/fm-primary-pi-watch.ts --model openai-codex/gpt-5.6-sol --thinking low; rc=\$?; printf \"PI_EXIT=%s\\n\" \"\$rc\"; sleep 300'"

i=0
while [ "$i" -lt 120 ]; do
  [ -f "$HOME_DIR/state/.pi-turnend-extension-loaded" ] && [ -f "$HOME_DIR/state/.pi-watch-extension-loaded" ] && break
  sleep 0.5
  i=$((i + 1))
done
[ -f "$HOME_DIR/state/.pi-turnend-extension-loaded" ] || fail "Pi turn-end extension did not load"
[ -f "$HOME_DIR/state/.pi-watch-extension-loaded" ] || fail "Pi watcher extension did not load"
wait_for_text "(openai-codex)" 120 || fail "Pi did not reach its ready composer"
sleep 1

send_prompt "/calm"
sleep 0.2
send_prompt "Reply exactly CALM_LIVE_WORKING_VISIBLE"
i=0
while [ "$i" -lt 240 ]; do
  pane=$(capture)
  if printf '%s\n' "$pane" | grep -Fq "Working..."; then
    break
  fi
  sleep 0.05
  i=$((i + 1))
done
printf '%s\n' "$pane" | grep -Fq "Working..." \
  || fail "Calm hid Pi's built-in Working row on the credentialed provider path"
wait_for_exact_line "CALM_LIVE_WORKING_VISIBLE" 120 \
  || fail "Pi did not settle the Calm Working-row provider probe"
pane=$(capture)
printf '%s\n' "$pane" | grep -Fq "calm transcript" \
  && fail "Calm added a persistent Calm status row on the credentialed provider path"
send_prompt "/calm"
sleep 0.2

: > "$HOME_DIR/state/pi-e2e.meta"
send_prompt "Start supervision with fm_watch_arm_pi and never use bash to arm supervision. After the watcher wake arrives, run bin/fm-wake-drain.sh and reply exactly HANDLED."
wait_for_text "watcher: started Pi extension arm child 1" || fail "Pi did not render the initial watcher tool result"

printf 'done: pi live e2e watcher fire\n' > "$HOME_DIR/state/pi-e2e.status"
i=0
while [ "$i" -lt 240 ]; do
  grep -Eq 'reason=actionable-signal.*successor=started:[0-9]+' "$HOME_DIR/state/.watch-cycle-exits.log" 2>/dev/null && break
  sleep 0.5
  i=$((i + 1))
done
grep -Eq 'reason=actionable-signal.*successor=started:[0-9]+' "$HOME_DIR/state/.watch-cycle-exits.log" 2>/dev/null \
  || fail "Pi extension did not start and ledger-link a successor after the actionable close"
wait_for_exact_line "HANDLED" 120 || fail "Pi did not drain and settle after its extension-owned successor started"

pane=$(capture)
guard_count=$(printf '%s\n' "$pane" | grep -Fc "TURN WOULD END BLIND - supervision is off." || true)
[ "$guard_count" -eq 0 ] || fail "successor was not protecting Pi before its next turn end (guard count $guard_count)"
foreground_arm='$ bin/fm-watch-arm.sh'
if printf '%s\n' "$pane" | grep -Fq "$foreground_arm"; then
  fail "Pi used a foreground bash watcher arm"
fi
arm_tool_result_count=$(printf '%s\n' "$pane" | grep -Ec 'watcher: (started|unchanged|not armed|read-only)' || true)
[ "$arm_tool_result_count" -eq 1 ] || fail "Pi model re-armed from memory instead of the extension (tool-result count $arm_tool_result_count)"

pid_file=$(find "$HOME_DIR/state" -maxdepth 3 -type f -name pid | head -1)
[ -n "$pid_file" ] || fail "re-armed watcher pid was not recorded"
watcher_pid=$(sed -n '1p' "$pid_file")
arm_pid=$(ps -p "$watcher_pid" -o ppid= | tr -d ' ')
[ -n "$arm_pid" ] || fail "re-armed watcher parent was not live"

"$TMUX" -L "$SOCKET" send-keys -t "$SESSION" -l '/quit'
sleep 1
"$TMUX" -L "$SOCKET" send-keys -t "$SESSION" Enter
wait_for_text "PI_EXIT=0" 60 || fail "Pi did not exit cleanly"
wait_pid_dead "$watcher_pid" || fail "watcher child survived clean Pi exit"
wait_pid_dead "$arm_pid" || fail "arm child survived clean Pi exit"

printf 'ok - Pi %s live E2E covered native Calm Working visibility, Ahoy first/later messages, legacy transcripts, near misses, and watcher continuity\n' "$PI_VERSION"
