#!/usr/bin/env bash
# Credential-safe real Pi/Herdr lifecycle regression through production wrappers.
#
# Drives one ordinary ship through fresh isolated spawn, durable inbox delivery
# and acknowledgement, interrupt, graceful exit, dead-shell classification,
# same-endpoint relaunch, and exact cleanup. A test-only Pi extension performs
# the inbox action before a provider turn, while deterministic launch turns use
# an offline local provider; every Herdr call is forced through one guarded
# non-default lab session.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/herdr-test-safety.sh
. "$(dirname "${BASH_SOURCE[0]}")/herdr-test-safety.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-task-inbox-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"

fm_live_gate opt-in FM_PI_LIFECYCLE_LIVE_E2E git herdr jq pi treehouse

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
SESSION=$("$LAB_HELPER" name firstmate-pi-herdr-foundation)
TMP_ROOT=$(fm_test_tmproot fm-pi-lifecycle-wrappers-live)
HOME_DIR="$TMP_ROOT/home"
PROJECT="$TMP_ROOT/project"
FAKEBIN="$TMP_ROOT/fakebin"
CAPTURE="$TMP_ROOT/pi-events.jsonl"
ACTED="$TMP_ROOT/acted.log"
ORIGINAL_PATH=$PATH
REAL_PI=$(command -v pi)
FIXTURE_MODEL=fm-test-offline/fixture
CAPTURE_EXTENSION="$TMP_ROOT/fm-pi-lifecycle-capture.ts"
ID=pi-herdr-life
REQUEST='durable Pi/Herdr lifecycle request'
HERDR_PROVISIONED=0
WORKTREE=

cleanup() {
  local rc=$?
  trap - EXIT
  if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    treehouse return --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  if [ "$HERDR_PROVISIONED" -eq 1 ] && ! "$LAB_HELPER" teardown "$SESSION"; then
    rc=1
  fi
  fm_test_cleanup || true
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$HOME_DIR/state" "$HOME_DIR/data/$ID" "$HOME_DIR/config" "$HOME_DIR/projects" "$FAKEBIN"
: > "$CAPTURE"
: > "$ACTED"
: > "$HOME_DIR/state/.last-watcher-beat"
printf 'off\n' > "$HOME_DIR/config/herdr-presentation-spaces"
herdr_forget_inherited_pane

cat > "$HOME_DIR/data/$ID/brief.md" <<'EOF'
# Task
## Captain's intent
Exercise the credential-safe real Pi worker lifecycle on Herdr.

## Firstmate spec
Acknowledge the durable instruction and otherwise leave the fixture unchanged.

Delivery contract: mode=no-mistakes
EOF

mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
printf '# Pi Herdr lifecycle fixture\n' > "$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial
git clone --quiet --bare "$PROJECT" "$PROJECT.origin.git"
git -C "$PROJECT" remote add origin "file://$PROJECT.origin.git"

# Production adapter calls already carry a validated trailing session pair.
# Remove only that pair, then let the lab helper append its own guarded pair.
cat > "$FAKEBIN/herdr" <<EOF
#!/usr/bin/env bash
set -euo pipefail
helper='$LAB_HELPER'
session='$SESSION'
real_path='$ORIGINAL_PATH'
args=("\$@")
n=\${#args[@]}
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "\$session" ] || { echo "wrapper refused foreign session" >&2; exit 97; }
  args=("\${args[@]:0:\$((n-2))}")
else
  [ "\${HERDR_SESSION:-}" = "\$session" ] || { echo "wrapper requires the isolated lab session" >&2; exit 98; }
  for arg in "\${args[@]}"; do
    case "\$arg" in
      --session|--session=*) echo "wrapper refused non-trailing session flag" >&2; exit 99 ;;
    esac
  done
fi
PATH="\$real_path" exec "\$helper" run "\$session" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"

# This extension is the deterministic worker for the regression. It records the
# production launch prompt, completes launch turns through a local offline
# provider, and intercepts each doorbell through Pi's input hook before a model
# turn. The doorbell path reads numeric inbox records in order, performs the
# requested action, and acknowledges each record by atomic rename.
CAPTURE_JSON=$(printf '%s' "$CAPTURE" | jq -Rs .)
ACTED_JSON=$(printf '%s' "$ACTED" | jq -Rs .)
cat > "$CAPTURE_EXTENSION" <<EOF
import { appendFileSync, mkdirSync, readFileSync, readdirSync, renameSync } from "node:fs";
import { join } from "node:path";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
const capturePath = $CAPTURE_JSON;
const actedPath = $ACTED_JSON;
function record(value: unknown) {
  appendFileSync(capturePath, JSON.stringify(value) + "\\n");
}
function handleDoorbell(prompt: string): boolean {
  const match = prompt.match(/list '([^']+)'\\/\\*\\.msg/);
  if (!match) return false;
  const inbox = match[1];
  const handled = join(inbox, "handled");
  mkdirSync(handled, { recursive: true });
  const files = readdirSync(inbox)
    .filter((name) => /^\\d+\\.msg$/.test(name))
    .map((name) => ({ name, sequence: Number(name.slice(0, -4)) }))
    .sort((left, right) => left.sequence - right.sequence);
  for (const file of files) {
    const source = join(inbox, file.name);
    const raw = readFileSync(source, "utf8");
    const separator = raw.indexOf("\\n--\\n");
    if (separator < 0) throw new Error("missing inbox separator in " + source);
    const body = raw.slice(separator + 4);
    appendFileSync(actedPath, body + "\\n");
    record({ kind: "inbox", inbox, file: file.name, body });
    renameSync(source, join(handled, file.name));
  }
  return true;
}
export default function (pi: any) {
  pi.registerProvider("fm-test-offline", {
    name: "Firstmate offline lifecycle fixture",
    baseUrl: "http://127.0.0.1:9/v1",
    apiKey: "test-only-no-network",
    api: "openai-completions",
    models: [{
      id: "fixture",
      name: "Firstmate offline fixture",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 4096,
      maxTokens: 64,
    }],
    streamSimple(model: any) {
      record({ kind: "provider-call" });
      const stream = createAssistantMessageEventStream();
      const message = {
        role: "assistant",
        content: [{ type: "text", text: "offline lifecycle fixture ready" }],
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
        stream.push({ type: "start", partial: message });
        stream.push({ type: "done", reason: "stop", message });
        stream.end();
      });
      return stream;
    },
  });
  pi.on("project_trust", () => ({ trusted: "yes", remember: false }));
  pi.on("input", (event: any) => {
    const prompt = String(event.text ?? "");
    record({ kind: "input", prompt });
    if (handleDoorbell(prompt)) return { action: "handled" };
    return { action: "continue" };
  });
  pi.on("before_agent_start", (event: any, ctx: any) => {
    const prompt = String(event.prompt ?? "");
    record({ kind: "prompt", home: process.env.FM_HOME ?? "", prompt });
    if (handleDoorbell(prompt)) ctx.abort();
  });
}
EOF

# Add only the credential-safe extension and offline provider to the exact Pi
# executable the production launch resolves. Capability probes pass through.
cat > "$FAKEBIN/pi" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" --help "*|*" --version "*) exec '$REAL_PI' "\$@" ;;
esac
exec '$REAL_PI' --offline --model '$FIXTURE_MODEL' -e '$CAPTURE_EXTENSION' "\$@"
EOF
chmod +x "$FAKEBIN/pi"

"$LAB_HELPER" provision "$SESSION"
HERDR_PROVISIONED=1

prod() { # <command...>
  PATH="$FAKEBIN:$ORIGINAL_PATH" HERDR_SESSION="$SESSION" TMUX='' \
    FM_GATE_REFUSE_BYPASS=1 FM_SPAWN_NO_GUARD=1 FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_CONFIG_OVERRIDE="$HOME_DIR/config" FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" \
    "$@"
}

wait_for_prompt_count() { # <needle> <count>
  local needle=$1 count=$2 found _
  for _ in $(seq 1 240); do
    found=$(jq -r --arg needle "$needle" \
      'select(.kind == "prompt" and (.prompt | contains($needle))) | 1' \
      "$CAPTURE" 2>/dev/null | wc -l | tr -d ' ')
    [ "$found" -ge "$count" ] && return 0
    sleep 0.25
  done
  return 1
}

find_inbox_record() { # <inbox>
  local inbox=$1 candidate name found='' count=0
  for candidate in "$inbox"/*.msg "$inbox/handled"/*.msg; do
    [ -f "$candidate" ] || continue
    name=${candidate##*/}
    case "${name%.msg}" in ''|*[!0-9]*) continue ;; esac
    found=$candidate
    count=$((count + 1))
  done
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$found"
}

wait_for_inbox_record() { # <inbox>
  local inbox=$1 record _
  for _ in $(seq 1 240); do
    if record=$(find_inbox_record "$inbox"); then
      printf '%s\n' "$record"
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_for_path() { # <path>
  local path=$1 _
  for _ in $(seq 1 240); do
    [ -e "$path" ] && return 0
    sleep 0.25
  done
  return 1
}

wait_for_idle() {
  local status _ stable=0
  for _ in $(seq 1 240); do
    status=$("$LAB_HELPER" run "$SESSION" agent get "$PANE" 2>/dev/null \
      | jq -r '.result.agent.agent_status // empty' 2>/dev/null || true)
    case "$status" in
      idle|done)
        stable=$((stable + 1))
        [ "$stable" -ge 4 ] && return 0
        ;;
      *) stable=0 ;;
    esac
    sleep 0.25
  done
  return 1
}

prod "$ROOT/bin/fm-spawn.sh" "$ID" "$PROJECT" --harness pi \
  --mode no-mistakes --yolo off --backend herdr >/dev/null \
  || fail "production spawn wrapper failed"

META="$HOME_DIR/state/$ID.meta"
[ -f "$META" ] || fail "fresh spawn did not publish task metadata"
[ "$(fm_meta_get "$META" kind)" = ship ] || fail "fresh spawn did not record an ordinary ship"
[ "$(fm_backend_of_meta "$META")" = herdr ] || fail "fresh spawn recorded the wrong backend"
[ "$(fm_meta_get "$META" harness)" = pi ] || fail "fresh spawn recorded a worker other than plain Pi"
[ -f "$HOME_DIR/state/$ID.pi-ext.ts" ] \
  || fail "fresh spawn did not materialize the current production Pi extension"
TARGET=$(fm_backend_target_of_meta "$META")
PANE=${TARGET#*:}
WORKTREE=$(fm_meta_get "$META" worktree)
case "$TARGET" in "$SESSION":w*:p*) : ;; *) fail "fresh spawn recorded an unexpected Herdr target: $TARGET" ;; esac
[ -d "$WORKTREE" ] || fail "fresh spawn did not retain its isolated worktree"
[ "$(cd "$WORKTREE" && pwd -P)" != "$(cd "$PROJECT" && pwd -P)" ] \
  || fail "fresh spawn reused the project checkout instead of an isolated worktree"
wait_for_prompt_count 'Exercise the credential-safe real Pi worker lifecycle on Herdr.' 1 \
  || fail "real Pi did not load the production launch brief"
wait_for_idle || fail "real Pi did not settle idle after the production launch brief"
"$LAB_HELPER" run "$SESSION" pane process-info --pane "$PANE" \
  | jq -e '.result.process_info.foreground_processes[]? | select(.argv0 == "pi")' >/dev/null \
  || fail "fresh spawn did not reach a plain Pi process through the production launch"
pass "real Pi/Herdr: production spawn reached a credential-safe session in a fresh isolated worktree"

prod "$ROOT/bin/fm-send.sh" "$ID" "$REQUEST" >/dev/null \
  || fail "production durable send wrapper failed"
INBOX="$HOME_DIR/state/$ID.inbox"
RECORD=$(wait_for_inbox_record "$INBOX") \
  || fail "durable send did not leave exactly one numeric inbox record"
HANDLED="$INBOX/handled/${RECORD##*/}"
wait_for_path "$HANDLED" || fail "real Pi did not acknowledge the durable inbox record; capture=$(tr '\n' ' ' < "$CAPTURE"); inbox=$(find "$INBOX" -maxdepth 2 -type f -print | tr '\n' ' '); pane=$("$LAB_HELPER" run "$SESSION" pane read "$PANE" --source recent --lines 40 2>&1 | tr '\n' ' ')"
[ ! -e "$INBOX/${RECORD##*/}" ] || fail "acknowledged inbox record remained pending"
BODY=$(fm_task_inbox_body "$HANDLED") || fail "handled inbox body could not be read"
assert_contains "$BODY" "$REQUEST" "handled inbox record did not carry the requested instruction"
assert_contains "$(cat "$ACTED")" "$REQUEST" "real Pi did not perform the durable inbox action"
pass "real Pi/Herdr: durable instruction delivery and handled acknowledgement complete through production wrappers"

prod "$ROOT/bin/fm-control.sh" "$ID" interrupt >/dev/null \
  || fail "production interrupt wrapper failed"
prod "$ROOT/bin/fm-control.sh" "$ID" exit >/dev/null \
  || fail "production graceful-exit wrapper failed"
[ "$(fm_backend_agent_state herdr "$TARGET")" = dead ] \
  || fail "the exited Pi pane did not classify as a recoverable dead shell"
"$LAB_HELPER" run "$SESSION" pane get "$PANE" >/dev/null \
  || fail "graceful exit removed the endpoint instead of preserving its shell"
pass "real Pi/Herdr: interrupt and graceful exit leave the exact pane as a recoverable dead shell"

prod "$ROOT/bin/fm-control.sh" "$ID" relaunch --note 'Credential-safe lifecycle relaunch.' >/dev/null \
  || fail "production relaunch wrapper failed"
wait_for_prompt_count 'Exercise the credential-safe real Pi worker lifecycle on Herdr.' 2 \
  || fail "real Pi did not restart through the production relaunch wrapper"
[ "$(fm_backend_target_of_meta "$META")" = "$TARGET" ] \
  || fail "relaunch replaced the endpoint instead of reusing it"
[ "$(fm_meta_get "$META" worktree)" = "$WORKTREE" ] && [ -d "$WORKTREE" ] \
  || fail "relaunch replaced or removed the isolated worktree"
pass "real Pi/Herdr: same-endpoint relaunch preserves the isolated worktree"

prod "$ROOT/bin/fm-teardown.sh" "$ID" --force >/dev/null \
  || fail "production cleanup wrapper failed"
[ ! -e "$META" ] || fail "cleanup left task metadata"
[ ! -e "$HOME_DIR/state/$ID.pi-ext.ts" ] || fail "cleanup left the worker extension"
[ ! -e "$INBOX" ] || fail "cleanup left the durable inbox"
if "$LAB_HELPER" run "$SESSION" pane get "$PANE" >/dev/null 2>&1; then
  fail "cleanup left the exact task pane alive"
fi
# treehouse intentionally keeps returned worktrees registered as clean reusable
# pool entries; production cleanup proves return before it removes the task
# metadata, so task-specific absence is the endpoint and durable-record checks.
WORKTREE=
PROVIDER_CALLS=$(jq -r 'select(.kind == "provider-call") | 1' "$CAPTURE" | wc -l | tr -d ' ')
[ "$PROVIDER_CALLS" -eq 2 ] \
  || fail "durable delivery unexpectedly started a provider turn (provider calls: $PROVIDER_CALLS, expected launch plus relaunch)"
pass "real Pi/Herdr: exact cleanup returns the isolated worktree and removes task endpoint, inbox, and worker records"

"$LAB_HELPER" teardown "$SESSION" \
  || fail "guarded lab teardown or default-session tripwire verification failed"
HERDR_PROVISIONED=0
pass "credential-safe plain Pi lifecycle completed on Herdr with the default session unchanged"
