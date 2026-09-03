#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/config" "$TMP/home/state"
FM_HOME="$TMP/home"
FM_CONFIG_OVERRIDE="$TMP/home/config"
# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"

fail() { echo "not ok - $1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (got '$1', want '$2')"; }

assert_eq "$(fm_backend_name)" herdr "the product default must be Herdr"
assert_eq "$FM_BACKEND_KNOWN" herdr "known provider set must contain only Herdr"
assert_eq "$(fm_backend_required_tools herdr)" "herdr jq treehouse" "Herdr toolchain must retain Treehouse and JSON parsing"

FM_BACKEND=legacy-provider
if fm_backend_name >"$TMP/out" 2>"$TMP/err"; then fail "an excluded provider must be refused"; fi
grep -q "requires backend=herdr" "$TMP/err" || fail "excluded provider refusal must name the migration"
unset FM_BACKEND
printf 'legacy-provider\n' > "$TMP/home/config/backend"
if fm_backend_name >"$TMP/out" 2>"$TMP/err"; then fail "an excluded configured provider must be refused"; fi
grep -q "never falls back" "$TMP/err" || fail "configured-provider refusal must state no fallback"
printf 'herdr\n' > "$TMP/home/config/backend"
assert_eq "$(fm_backend_name)" herdr "explicit Herdr config must pass"

cat > "$TMP/home/state/old.meta" <<EOF
window=legacy:0
worktree=$TMP/work
project=$TMP/project
EOF
assert_eq "$(fm_backend_of_meta "$TMP/home/state/old.meta")" unsupported-or-ambiguous "absent provider metadata must not be reinterpreted"
if fm_backend_validate_task_endpoint "$TMP/home/state/old.meta" old 2>"$TMP/err"; then fail "old absent provider metadata must block cleanup"; fi
grep -q "explicit migration to Herdr metadata is required" "$TMP/err" || fail "legacy blocker must be concrete"

mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "status --json")
    printf '{"client":{"version":"0.8.2","protocol":16},"server":{"running":%s}}\n' "${FM_FAKE_SERVER_RUNNING:-true}"
    ;;
  "pane get")
    [ "${3:-}" = w1:p2 ] || exit 1
    printf '{"result":{"pane":{"workspace_id":"%s","tab_id":"%s","pane_id":"%s"}}}\n' \
      "${FM_FAKE_LIVE_WORKSPACE:-w1}" "${FM_FAKE_LIVE_TAB:-w1:t1}" \
      "${FM_FAKE_LIVE_PANE:-w1:p2}"
    ;;
  "tab list")
    printf '{"result":{"tabs":[{"workspace_id":"w1","tab_id":"w1:t1","label":"%s"}]}}\n' \
      "${FM_FAKE_LIVE_LABEL:-fm-task}"
    ;;
  "pane read")
    printf 'task output\n'
    ;;
  "server ")
    printf 'started\n' >> "${FM_FAKE_SERVER_LOG:-/dev/null}"
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TMP/fakebin/herdr"
PATH="$TMP/fakebin:$PATH"
export PATH

cat > "$TMP/home/state/task.meta" <<EOF
window=lab:w1:p2
endpoint_task_id=task
worktree=$TMP/work
project=$TMP/project
backend=herdr
herdr_session=lab
herdr_workspace_id=w1
herdr_tab_id=w1:t1
herdr_pane_id=w1:p2
EOF
fm_backend_validate_task_endpoint "$TMP/home/state/task.meta" task || fail "exact Herdr metadata should validate"
assert_eq "$FM_BACKEND_VALIDATED_BACKEND" herdr "validated provider"
assert_eq "$FM_BACKEND_VALIDATED_TARGET" lab:w1:p2 "validated target"
assert_eq "$(fm_backend_resolve_selector task "$TMP/home/state")" lab:w1:p2 "task selectors must resolve through metadata"
fm_backend_target_exists herdr lab:w1:p2 fm-task || fail "exact live task hierarchy should exist"
mkdir -p "$TMP/override-state"
cp "$TMP/home/state/task.meta" "$TMP/override-state/task.meta"
FM_STATE_OVERRIDE="$TMP/override-state"
export FM_STATE_OVERRIDE
mv "$TMP/home/state/task.meta" "$TMP/home/state/task.meta.hidden"
fm_backend_target_exists herdr lab:w1:p2 fm-task \
  || fail "target existence must honor overridden task state"
mv "$TMP/home/state/task.meta.hidden" "$TMP/home/state/task.meta"
unset FM_STATE_OVERRIDE
assert_eq "$(fm_backend_capture herdr lab:w1:p2 10 fm-task)" "task output" \
  "task-bound capture must accept the exact live task hierarchy"
export FM_SUPERVISOR_BACKEND=herdr FM_SUPERVISOR_SESSION=lab \
  FM_SUPERVISOR_WORKSPACE_ID=w1 FM_SUPERVISOR_TAB_ID=w1:t1 \
  FM_SUPERVISOR_PANE_ID=w1:p2 FM_SUPERVISOR_TARGET=lab:w1:p2
assert_eq "$(fm_backend_capture herdr lab:w1:p2 10)" "task output" \
  "supervisor capture must accept the exact recorded live hierarchy"
export FM_FAKE_LIVE_WORKSPACE=w9
if fm_backend_capture herdr lab:w1:p2 10 >"$TMP/out" 2>"$TMP/err"; then
  fail "supervisor capture must reject a contradictory live workspace identity"
fi
unset FM_FAKE_LIVE_WORKSPACE
export FM_FAKE_LIVE_TAB=w1:t9
if fm_backend_capture herdr lab:w1:p2 10 >"$TMP/out" 2>"$TMP/err"; then
  fail "supervisor capture must reject a contradictory live tab identity"
fi
unset FM_FAKE_LIVE_TAB
export FM_FAKE_LIVE_PANE=w1:p9
if fm_backend_capture herdr lab:w1:p2 10 >"$TMP/out" 2>"$TMP/err"; then
  fail "supervisor capture must reject a contradictory live pane identity"
fi
unset FM_FAKE_LIVE_PANE
export FM_FAKE_LIVE_LABEL=fm-other
if fm_backend_target_exists herdr lab:w1:p2 fm-task; then
  fail "target existence must reject reused hierarchy IDs bound to another task label"
fi
if fm_backend_capture herdr lab:w1:p2 10 fm-task >"$TMP/out" 2>"$TMP/err"; then
  fail "task-bound capture must reject reused hierarchy IDs bound to another task label"
fi
unset FM_FAKE_LIVE_LABEL
export FM_FAKE_LIVE_TAB=w1:t9
if fm_backend_target_exists herdr lab:w1:p2 fm-task; then
  fail "target existence must reject a pane moved outside its recorded tab"
fi
if fm_backend_validate_active_task_endpoint "$TMP/home/state/task.meta" task 2>"$TMP/err"; then
  fail "a live pane contradicting the recorded tab must be refused"
fi
unset FM_FAKE_LIVE_TAB
grep -q "contradicts the recorded" "$TMP/err" || fail "live identity refusal must name the contradiction"
export FM_FAKE_SERVER_RUNNING=false FM_FAKE_SERVER_LOG="$TMP/server.log"
if fm_backend_herdr_capture lab:w1:p2 >/dev/null 2>"$TMP/err"; then
  fail "ordinary endpoint reads must refuse a stopped Herdr session"
fi
[ ! -e "$TMP/server.log" ] || fail "ordinary endpoint reads must never start Herdr"
unset FM_FAKE_SERVER_RUNNING FM_FAKE_SERVER_LOG
for mismatch in 'herdr_tab_id=w2:t1' 'herdr_pane_id=w2:p2'; do
  cp "$TMP/home/state/task.meta" "$TMP/mismatch.meta"
  key=${mismatch%%=*}
  value=${mismatch#*=}
  awk -v key="$key" -v value="$value" 'index($0, key "=") == 1 { print key "=" value; next } { print }' \
    "$TMP/mismatch.meta" > "$TMP/mismatch.next"
  mv "$TMP/mismatch.next" "$TMP/mismatch.meta"
  if fm_backend_validate_task_endpoint "$TMP/mismatch.meta" task 2>"$TMP/err"; then
    fail "a Herdr child outside the recorded workspace must be refused"
  fi
done
if fm_backend_resolve_selector 'legacy:0' "$TMP/home/state" 2>"$TMP/err"; then fail "ad hoc legacy endpoints must be refused"; fi
grep -Eq "unsupported in the Herdr-only edition|explicit migration|unsupported session provider" "$TMP/err" || fail "ad hoc refusal must explain the boundary"

fm_backend_herdr_agent_state() { printf '%s' "$FM_FAKE_AGENT_STATE"; }
FM_FAKE_AGENT_STATE=dead
export FM_FAKE_AGENT_STATE
assert_eq "$(fm_backend_task_agent_state "$TMP/home/state/task.meta" task)" dead \
  "an exact active Herdr husk must remain recoverable"
FM_FAKE_LIVE_TAB=w1:t9
export FM_FAKE_LIVE_TAB
assert_eq "$(fm_backend_task_agent_state "$TMP/home/state/task.meta" task)" unreadable \
  "a reachable pane outside its recorded hierarchy must never be recoverable as dead"
FM_FAKE_AGENT_STATE=alive
assert_eq "$(fm_backend_task_agent_state "$TMP/home/state/task.meta" task)" unreadable \
  "a reachable mismatched pane must never be classified alive"
FM_FAKE_AGENT_STATE=ambiguous
assert_eq "$(fm_backend_task_agent_state "$TMP/home/state/task.meta" task)" ambiguous \
  "an ambiguous endpoint must remain non-recoverable"
FM_FAKE_AGENT_STATE=missing
assert_eq "$(fm_backend_task_agent_state "$TMP/home/state/task.meta" task)" missing \
  "a structurally exact missing pane must remain recoverable without active validation"
unset FM_FAKE_AGENT_STATE FM_FAKE_LIVE_TAB

echo "ok - Herdr-only provider selection and metadata migration"
