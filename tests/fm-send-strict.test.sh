#!/usr/bin/env bash
# Herdr-only strict target resolution and key delivery reporting.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SEND="$ROOT/bin/fm-send.sh"
TMP_ROOT=$(fm_test_tmproot fm-send-strict)

make_stubs() {
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${FM_HERDR_LOG:?}"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.2","protocol":16},"server":{"running":true}}\n' ;;
  "session list") printf '%s\n' '{"sessions":[{"name":"lab","running":true,"socket_path":"/tmp/fm-send-strict-lab.sock"}]}' ;;
  "workspace list") printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"}]}}' ;;
  "tab list") printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1","label":"fm-lane"}]}}' ;;
  "tab get") printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t1","workspace_id":"w1","label":"fm-lane"}}}' ;;
  "pane get")
    [ "${FM_FAKE_HERDR_UNREACHABLE:-0}" != 1 ] || exit 1
    printf '{"result":{"pane":{"pane_id":"%s","workspace_id":"%s","tab_id":"%s"}}}\n' \
      "${3:-}" "${FM_FAKE_HERDR_WORKSPACE:-w1}" "${FM_FAKE_HERDR_TAB:-w1:t1}"
    ;;
  "pane read") printf '%s\n' '❯' ;;
  "pane send-keys") [ -z "${FM_FAKE_HERDR_SEND_KEY_FAIL:-}" ] ;;
esac
SH
  chmod +x "$fb/herdr"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fb/sleep"
  printf '%s\n' "$fb"
}

setup_home() {
  local home="$TMP_ROOT/$1-$RANDOM"
  mkdir -p "$home/state"
  printf '%s\n' "$home"
}

write_herdr_meta() {
  local meta=$1 id=$2 pane=$3
  fm_write_meta "$meta" \
    "backend=herdr" "window=lab:$pane" "endpoint_task_id=$id" \
    "worktree=$TMP_ROOT/worktree" "project=$TMP_ROOT/project" "kind=ship" "harness=pi" \
    "herdr_session=lab" "herdr_workspace_id=w1" "herdr_tab_id=w1:t1" "herdr_pane_id=$pane"
}

test_exact_task_send_uses_recorded_herdr_endpoint() {
  local dir fb home log rc
  dir="$TMP_ROOT/exact"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home exact); log="$dir/herdr.log"; : > "$log"
  write_herdr_meta "$home/state/lane.meta" lane w1:p1

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" FM_SEND_SETTLE=0 \
    "$SEND" lane "lost dispatch" >/dev/null 2>"$dir/err"; rc=$?
  expect_code 0 "$rc" "an exact Herdr task send should succeed"
  grep -qF 'lost dispatch' "$home/state/lane.inbox/001.msg" \
    || fail "the task send did not durably record its message"
  assert_contains "$(cat "$log")" "pane send-text w1:p1" "the task send did not ring its recorded Herdr pane"
  pass "fm-send routes exact task identity through recorded Herdr metadata"
}

test_ambiguous_metadata_refuses_before_send() {
  local dir fb home log rc
  dir="$TMP_ROOT/ambiguous"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home ambiguous); log="$dir/herdr.log"; : > "$log"
  fm_write_meta "$home/state/lane.meta" \
    "backend=legacy-provider" "backend=herdr" "window=legacy:fm-lane" "window=lab:w1:p1" \
    "endpoint_task_id=lane" "worktree=$TMP_ROOT/worktree" "project=$TMP_ROOT/project" \
    "kind=ship" "harness=pi" "herdr_session=lab" "herdr_workspace_id=w1" \
    "herdr_tab_id=w1:t1" "herdr_pane_id=w1:p1"

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    "$SEND" lane "must not route" >/dev/null 2>"$dir/err"; rc=$?
  [ "$rc" -ne 0 ] || fail "ambiguous metadata unexpectedly sent"
  assert_contains "$(cat "$dir/err")" "explicit migration" "ambiguous metadata did not produce a migration blocker"
  [ ! -s "$log" ] || fail "ambiguous metadata reached Herdr"
  [ ! -e "$home/state/lane.inbox" ] || fail "ambiguous metadata created a durable delivery record"
  pass "fm-send refuses ambiguous provider and endpoint metadata before delivery"
}

test_prefixless_and_legacy_explicit_targets_refuse() {
  local dir fb home log rc
  dir="$TMP_ROOT/explicit"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home explicit); log="$dir/herdr.log"; : > "$log"
  write_herdr_meta "$home/state/lane.meta" lane w1:p1

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    "$SEND" w1:p1 "nudge" >/dev/null 2>"$dir/prefixless.err"; rc=$?
  [ "$rc" -ne 0 ] || fail "a prefixless Herdr pane unexpectedly sent"
  assert_contains "$(cat "$dir/prefixless.err")" "not a recorded task selector" \
    "the prefixless pane blocker did not require a task selector"

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    "$SEND" lab:w1:p1 "nudge" >/dev/null 2>"$dir/exact-window.err"; rc=$?
  [ "$rc" -ne 0 ] || fail "a recorded task's raw endpoint unexpectedly sent"
  assert_contains "$(cat "$dir/exact-window.err")" "not a recorded task selector" \
    "the raw endpoint blocker did not require its task selector"

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    "$SEND" legacy:window "nudge" >/dev/null 2>"$dir/legacy.err"; rc=$?
  [ "$rc" -ne 0 ] || fail "a legacy explicit target unexpectedly sent"
  assert_contains "$(cat "$dir/legacy.err")" "ad hoc endpoint selection is unsupported" \
    "the legacy target blocker did not require a recorded task selector"
  [ ! -s "$log" ] || fail "an invalid explicit target reached Herdr"
  pass "fm-send refuses prefixless and legacy explicit endpoint identities"
}

test_unrecorded_and_contradictory_live_targets_refuse() {
  local dir fb home log rc
  dir="$TMP_ROOT/live-identity"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home live-identity); log="$dir/herdr.log"; : > "$log"
  write_herdr_meta "$home/state/lane.meta" lane w1:p1

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    "$SEND" lab:w9:p9 "must not route" >/dev/null 2>"$dir/unrecorded.err"; rc=$?
  [ "$rc" -ne 0 ] || fail "an unrecorded live-shaped target unexpectedly sent"
  assert_contains "$(cat "$dir/unrecorded.err")" "ad hoc endpoint selection is unsupported" \
    "the unrecorded endpoint blocker did not require task metadata"

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    FM_FAKE_HERDR_TAB=w1:t9 "$SEND" lane "must not route" >/dev/null 2>"$dir/hierarchy.err"; rc=$?
  [ "$rc" -ne 0 ] || fail "a contradictory live tab unexpectedly sent"
  assert_contains "$(cat "$dir/hierarchy.err")" "contradicts the recorded workspace, tab, or pane" \
    "the contradictory live hierarchy did not produce a blocker"

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    FM_FAKE_HERDR_UNREACHABLE=1 "$SEND" lane "must not route" >/dev/null 2>"$dir/unreachable.err"; rc=$?
  [ "$rc" -ne 0 ] || fail "an unreachable recorded pane unexpectedly sent"
  assert_contains "$(cat "$dir/unreachable.err")" "is unreachable" \
    "the unreachable pane did not produce a concrete blocker"
  [ ! -e "$home/state/lane.inbox" ] || fail "a refused live identity created a durable delivery record"
  pass "fm-send requires task binding and exact live Herdr hierarchy"
}

test_key_exit_status_follows_herdr_delivery() {
  local dir fb home log rc
  dir="$TMP_ROOT/key"; mkdir -p "$dir"
  fb=$(make_stubs "$dir"); home=$(setup_home key); log="$dir/herdr.log"; : > "$log"
  write_herdr_meta "$home/state/lane.meta" lane w1:p1

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    "$SEND" lane --key Escape >/dev/null 2>"$dir/err"; rc=$?
  expect_code 0 "$rc" "a delivered Herdr key should report success"

  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    FM_FAKE_HERDR_SEND_KEY_FAIL=Escape "$SEND" lane --key Escape >/dev/null 2>"$dir/fail.err"; rc=$?
  [ "$rc" -ne 0 ] || fail "an undelivered Herdr key reported success"
  assert_contains "$(cat "$dir/fail.err")" "key 'Escape' not sent" "the key failure did not name the undelivered key"
  pass "fm-send Herdr key exit status follows delivery"
}

test_exact_task_send_uses_recorded_herdr_endpoint
test_ambiguous_metadata_refuses_before_send
test_prefixless_and_legacy_explicit_targets_refuse
test_unrecorded_and_contradictory_live_targets_refuse
test_key_exit_status_follows_herdr_delivery
