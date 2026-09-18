#!/usr/bin/env bash
# Credential-safe real Pi lifecycle regression through production wrappers.
#
# Runs the same spawn -> durable send -> interrupt -> exit -> relaunch ->
# cleanup path once on Herdr and once on the tmux reference backend. The Pi
# extension grants session-only trust, handles the production durable inbox,
# routes a correlated reply through fm-secondmate-report.sh, and aborts every
# turn before provider selection, so the required CI run needs no credential.
#
# Every Herdr command, including production adapter calls, is forced through
# bin/fm-herdr-lab.sh and one generated non-default session. Direct terminal
# input uses that helper too and proves it stays outside Firstmate routing.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/herdr-test-safety.sh
. "$(dirname "${BASH_SOURCE[0]}")/herdr-test-safety.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-marker-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-pending-reply-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-task-inbox-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"

fm_live_gate default-on FM_PI_LIFECYCLE_LIVE_E2E git herdr jq lsof pi tmux treehouse

LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}
SESSION=$("$LAB_HELPER" name firstmate-herdr-only-preflight)
TMP_ROOT=$(fm_test_tmproot fm-pi-lifecycle-wrappers-live)
FAKEBIN="$TMP_ROOT/fakebin"
CAPTURE="$TMP_ROOT/pi-events.jsonl"
ACTED_DIR="$TMP_ROOT/acted"
ORIGINAL_PATH=$PATH
REAL_PI=$(command -v pi)
CAPTURE_EXTENSION="$TMP_ROOT/fm-pi-lifecycle-capture.ts"
TMUX_TMPDIR_TEST=$(mktemp -d /tmp/fm-pi-life.XXXXXX)
HERDR_PROVISIONED=0

cleanup() {
  local rc=$?
  trap - EXIT
  TMUX='' TMUX_TMPDIR="$TMUX_TMPDIR_TEST" tmux kill-server >/dev/null 2>&1 || true
  if [ "$HERDR_PROVISIONED" -eq 1 ] && ! "$LAB_HELPER" teardown "$SESSION"; then
    rc=1
  fi
  rm -rf "$TMUX_TMPDIR_TEST"
  fm_test_cleanup || true
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$FAKEBIN" "$ACTED_DIR" "$TMUX_TMPDIR_TEST"
: > "$CAPTURE"
herdr_forget_inherited_pane

# Production Herdr calls must not bypass the guarded lab owner. The adapter
# already appends the validated trailing --session pair; strip only that pair
# before the helper adds its own mandatory trailing pair to the real binary.
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

# The extension is the worker for this regression. It records every prompt,
# processes every numeric durable-inbox record in order, emits the correlated
# parent response through the production helper, then acknowledges by moving
# the exact record into handled/. ctx.abort() prevents any provider request.
CAPTURE_JSON=$(printf '%s' "$CAPTURE" | jq -Rs .)
ACTED_JSON=$(printf '%s' "$ACTED_DIR" | jq -Rs .)
REPORT_JSON=$(printf '%s' "$ROOT/bin/fm-secondmate-report.sh" | jq -Rs .)
cat > "$CAPTURE_EXTENSION" <<EOF
import { appendFileSync, mkdirSync, readFileSync, readdirSync, renameSync } from "node:fs";
import { basename, join } from "node:path";
import { spawnSync } from "node:child_process";
const capturePath = $CAPTURE_JSON;
const actedDir = $ACTED_JSON;
const reportHelper = $REPORT_JSON;
function record(value: unknown) {
  appendFileSync(capturePath, JSON.stringify(value) + "\\n");
}
export default function (pi: any) {
  pi.on("project_trust", () => ({ trusted: "yes", remember: false }));
  pi.on("before_agent_start", (event: any, ctx: any) => {
    const prompt = String(event.prompt ?? "");
    record({ kind: "prompt", home: process.env.FM_HOME ?? "", prompt });
    const match = prompt.match(/list '([^']+)'\\/\\*\\.msg/);
    if (match) {
      const inbox = match[1];
      mkdirSync(join(inbox, "handled"), { recursive: true });
      const files = readdirSync(inbox).filter((name) => /^\\d+\\.msg$/.test(name)).sort();
      for (const name of files) {
        const source = join(inbox, name);
        const raw = readFileSync(source, "utf8");
        const separator = raw.indexOf("\\n--\\n");
        if (separator < 0) throw new Error("missing inbox separator in " + source);
        const body = raw.slice(separator + 4);
        const corr = body.match(/corr=([a-f0-9]{16})/)?.[1] ?? "";
        if (!corr) throw new Error("missing correlation in " + source);
        const report = spawnSync(reportHelper, ["done", corr, "live routed response"], {
          env: { ...process.env, FM_HOME: process.env.FM_HOME ?? "" },
          encoding: "utf8",
        });
        record({ kind: "inbox", inbox, file: name, body, corr, reportStatus: report.status, reportStderr: report.stderr });
        if (report.status !== 0) throw new Error("routed response failed: " + report.stderr);
        renameSync(source, join(inbox, "handled", name));
        mkdirSync(actedDir, { recursive: true });
        appendFileSync(join(actedDir, basename(inbox, ".inbox")), body + "\\n");
      }
    }
    ctx.abort();
  });
}
EOF

# Add only the credential-safe extension to the production Pi invocation.
# Capability probes are passed through untouched.
cat > "$FAKEBIN/pi" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" --help "*|*" --version "*) exec '$REAL_PI' "\$@" ;;
esac
exec '$REAL_PI' -e '$CAPTURE_EXTENSION' "\$@"
EOF
chmod +x "$FAKEBIN/pi"

"$LAB_HELPER" provision "$SESSION"
HERDR_PROVISIONED=1

prod() { # <backend> <parent-home> <command...>
  local backend=$1 parent=$2
  shift 2
  if [ "$backend" = herdr ]; then
    PATH="$FAKEBIN:$ORIGINAL_PATH" HERDR_SESSION="$SESSION" TMUX='' \
      FM_HOME="$parent" FM_STATE_OVERRIDE="$parent/state" FM_DATA_OVERRIDE="$parent/data" \
      FM_CONFIG_OVERRIDE="$parent/config" FM_PROJECTS_OVERRIDE="$parent/projects" \
      "$@"
  else
    PATH="$FAKEBIN:$ORIGINAL_PATH" TMUX='' TMUX_TMPDIR="$TMUX_TMPDIR_TEST" HERDR_SESSION='' \
      FM_HOME="$parent" FM_STATE_OVERRIDE="$parent/state" FM_DATA_OVERRIDE="$parent/data" \
      FM_CONFIG_OVERRIDE="$parent/config" FM_PROJECTS_OVERRIDE="$parent/projects" \
      "$@"
  fi
}

wait_for_capture_count() { # <home> <needle> <count>
  local home=$1 needle=$2 count=$3 found _
  # Hosted Herdr runners can be busy after the preceding real-Herdr family;
  # keep this bounded while allowing the production Pi startup to settle.
  for _ in $(seq 1 600); do
    found=$(jq -r --arg home "$home" --arg needle "$needle" \
      'select(.kind == "prompt" and .home == $home and (.prompt | contains($needle))) | 1' \
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
    case "${name%.msg}" in
      ''|*[!0-9]*) continue ;;
    esac
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

wait_for_handled() { # <handled-record>
  local handled=$1 _
  for _ in $(seq 1 240); do
    [ -f "$handled" ] && return 0
    sleep 0.25
  done
  return 1
}

run_backend_lifecycle() { # <herdr|tmux>
  local backend=$1 id="live-${1}" parent="$TMP_ROOT/${1}-parent" mate="$TMP_ROOT/${1}-mate"
  local request="durable request for $1" direct="direct terminal input for $1"
  local meta target record handled body corr pending phase got

  mkdir -p "$parent/state" "$parent/data" "$parent/config" "$parent/projects"
  printf 'pi\n' > "$parent/config/secondmate-harness"
  git clone -q --no-hardlinks "$ROOT" "$mate"
  git -C "$mate" checkout -q --detach HEAD
  mkdir -p "$mate/state" "$mate/data" "$mate/config" "$mate/projects"

  FM_SECONDMATE_CHARTER="Credential-safe lifecycle secondmate for $backend. Stay idle." \
    FM_SECONDMATE_SCOPE="lifecycle verification for $backend" \
    FM_HOME="$parent" FM_STATE_OVERRIDE="$parent/state" FM_DATA_OVERRIDE="$parent/data" \
    FM_PROJECTS_OVERRIDE="$parent/projects" \
    "$ROOT/bin/fm-home-seed.sh" "$id" "$mate" --no-projects >/dev/null \
    || fail "$backend: could not seed the isolated secondmate home"

  prod "$backend" "$parent" "$ROOT/bin/fm-spawn.sh" "$id" "$mate" \
    --secondmate --harness pi --backend "$backend" >/dev/null \
    || fail "$backend: production spawn wrapper failed"

  meta="$parent/state/$id.meta"
  [ -f "$meta" ] || fail "$backend: spawn did not publish task metadata"
  [ "$(fm_meta_get "$meta" kind)" = secondmate ] || fail "$backend: spawn did not record kind=secondmate"
  [ "$(fm_backend_of_meta "$meta")" = "$backend" ] || fail "$backend: spawn recorded the wrong backend"
  if [ "$backend" = tmux ]; then
    ! grep -q '^backend=' "$meta" || fail "tmux: backend-less metadata compatibility changed"
  fi
  target=$(fm_backend_target_of_meta "$meta")
  wait_for_capture_count "$mate" "Credential-safe lifecycle secondmate" 1 \
    || fail "$backend: real Pi did not load and abort the startup charter"
  pass "real Pi/$backend: production spawn reached a credential-safe trusted session"

  prod "$backend" "$parent" "$ROOT/bin/fm-send.sh" "$id" "$request" >/dev/null \
    || fail "$backend: production send wrapper failed"
  record=$(wait_for_inbox_record "$parent/state/$id.inbox") \
    || fail "$backend: send did not leave exactly one numeric task inbox record"
  record="$parent/state/$id.inbox/${record##*/}"
  handled="$parent/state/$id.inbox/handled/${record##*/}"
  wait_for_handled "$handled" || fail "$backend: worker did not acknowledge the durable inbox record"
  [ ! -e "$record" ] || fail "$backend: acknowledged inbox record remained unhandled"
  [ -f "$handled" ] || fail "$backend: acknowledged inbox record was not moved into handled/"
  body=$(fm_task_inbox_body "$handled") || fail "$backend: handled record body could not be read"
  assert_contains "$body" "$request" "$backend: handled record was not routed to the exact requested task"
  fm_message_from_firstmate "$body" || fail "$backend: secondmate inbox body lost its Firstmate routing marker"
  corr=$(fm_pending_reply_extract_corr "$body")
  [ -n "$corr" ] || fail "$backend: routed request did not carry a pending-reply correlation"
  [ -f "$ACTED_DIR/$id" ] || fail "$backend: exact inbox action was not recorded"
  [ -z "$(find "$parent/state" -maxdepth 1 -type d -name '*.inbox' ! -name "$id.inbox" -print -quit)" ] \
    || fail "$backend: send created an inbox for a task other than $id"

  pending=$(fm_pending_reply_path "$parent/state" "$corr")
  [ -f "$pending" ] || fail "$backend: parent pending-reply record is missing"
  [ "$(fm_pending_reply_get "$pending" task_id)" = "$id" ] \
    || fail "$backend: pending-reply correlation points at the wrong task"
  grep -Eq "^done \\[corr=$corr\\]: live routed response \\(via-helper\\)$" "$parent/state/$id.status" \
    || fail "$backend: correlated response did not return through the parent status channel"
  fm_pending_reply_try_resolve "$parent/state" "$corr" \
    || fail "$backend: correlated parent response did not resolve the pending reply"
  phase=$(fm_pending_reply_get "$pending" phase)
  [ "$phase" = resolved ] || fail "$backend: pending reply remained in phase $phase"
  pass "real Pi/$backend: exact durable routing, handled acknowledgement, correlation, and routed response all hold"

  prod "$backend" "$parent" "$ROOT/bin/fm-control.sh" "$id" interrupt >/dev/null \
    || fail "$backend: production interrupt wrapper failed"
  prod "$backend" "$parent" "$ROOT/bin/fm-control.sh" "$id" exit >/dev/null \
    || fail "$backend: production exit wrapper failed"
  prod "$backend" "$parent" "$ROOT/bin/fm-control.sh" "$id" relaunch >/dev/null \
    || fail "$backend: production relaunch wrapper failed"
  wait_for_capture_count "$mate" "Credential-safe lifecycle secondmate" 2 \
    || fail "$backend: real Pi did not restart through the production relaunch wrapper"
  pass "real Pi/$backend: interrupt, exit, and relaunch wrappers preserve the endpoint lifecycle"

  if [ "$backend" = herdr ]; then
    local pane=${target#*:}
    "$LAB_HELPER" run "$SESSION" pane send-text "$pane" "$direct" >/dev/null
    "$LAB_HELPER" run "$SESSION" pane send-keys "$pane" enter >/dev/null
  else
    TMUX='' TMUX_TMPDIR="$TMUX_TMPDIR_TEST" tmux send-keys -t "$target" -l -- "$direct"
    TMUX='' TMUX_TMPDIR="$TMUX_TMPDIR_TEST" tmux send-keys -t "$target" Enter
  fi
  wait_for_capture_count "$mate" "$direct" 1 || fail "$backend: direct terminal input never reached Pi"
  got=$(jq -r --arg home "$mate" --arg needle "$direct" \
    'select(.kind == "prompt" and .home == $home and (.prompt | contains($needle))) | .prompt' \
    "$CAPTURE" | tail -1)
  [ "$got" = "$direct" ] || fail "$backend: direct terminal input was changed"
  if fm_message_from_firstmate "$got"; then
    fail "$backend: unmarked direct terminal input was misclassified as Firstmate routing"
  fi
  pass "real Pi/$backend: direct terminal input stays unmarked"

  prod "$backend" "$parent" "$ROOT/bin/fm-teardown.sh" "$id" --force >/dev/null \
    || fail "$backend: production cleanup wrapper failed"
  [ ! -e "$meta" ] || fail "$backend: production cleanup left task metadata"
  pass "real Pi/$backend: production cleanup completed"
}

run_backend_lifecycle herdr
run_backend_lifecycle tmux

pass "credential-safe real Pi lifecycle parity covers Herdr and the tmux reference backend"
