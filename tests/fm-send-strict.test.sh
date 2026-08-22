#!/usr/bin/env bash
# Strict Herdr target resolution and no-fallback delivery behavior.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SEND="$ROOT/bin/fm-send.sh"
TMP_ROOT=$(fm_test_tmproot fm-send-strict)

make_stubs() { # <dir>
  local fb=$1/fakebin
  mkdir -p "$fb"
  : > "$1/herdr.sock"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "session list")
    printf '{"sessions":[{"name":"%s","running":true,"socket_path":"%s/herdr.sock"}]}\n' "${HERDR_SESSION:-lab}" "${FM_HOME:-/tmp}"
    ;;
  "pane get")
    if [ "${FM_HERDR_MISSING:-0}" = 1 ]; then printf '{"error":{"code":"pane_not_found"}}\n'
    else
      workspace=${3%%:*}
      count=$(cat "${FM_HERDR_PANE_GET_COUNT:-/dev/null}" 2>/dev/null || printf 0)
      count=$((count + 1))
      [ -z "${FM_HERDR_PANE_GET_COUNT:-}" ] || printf '%s' "$count" > "$FM_HERDR_PANE_GET_COUNT"
      if [ "${FM_HERDR_MOVE_AFTER_FIRST:-0}" = 1 ] && [ "$count" -gt 1 ]; then tab="$workspace:t2"; else tab="$workspace:t1"; fi
      printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s","workspace_id":"%s"}}}\n' "${3:-}" "$tab" "$workspace"
    fi ;;
  "tab get")
    workspace=${3%%:*}
    count=$(cat "$FM_HOME/tab-get-count" 2>/dev/null || printf 0)
    count=$((count + 1))
    printf '%s' "$count" > "$FM_HOME/tab-get-count"
    printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"%s"}}}\n' "${3:-}" "${FM_HERDR_TAB_WORKSPACE:-$workspace}"
    if [ "${FM_HERDR_REPLACE_AFTER_VALIDATION:-0}" = 1 ] && [ "$count" -gt 1 ] && [ ! -e "$FM_HOME/session-replaced" ]; then
      mv "$FM_HOME/herdr.sock" "$FM_HOME/herdr-prior.sock"
      : > "$FM_HOME/herdr.sock"
      : > "$FM_HOME/session-replaced"
    fi
    ;;
  "pane send-text")
    [ -z "${FM_EXPECTED_LOCK:-}" ] || [ -e "$FM_EXPECTED_LOCK" ] || exit 1
    if [ "${FM_HERDR_REPLACE_AFTER_VALIDATION:-0}" = 1 ]; then
      [ -n "${HERDR_SOCKET_PATH:-}" ] || exit 1
      [ "$HERDR_SOCKET_PATH" -ef "$FM_HOME/herdr-prior.sock" ] || exit 1
      [ ! "$HERDR_SOCKET_PATH" -ef "$FM_HOME/herdr.sock" ] || exit 1
      : > "$FM_HOME/bound-generation-used"
    fi
    ;;
  "pane send-keys") : > "$FM_HERDR_STATE" ;;
  "agent get")
    if [ -e "$FM_HERDR_STATE" ]; then status=working; else status=idle; fi
    printf '{"result":{"agent":{"agent_status":"%s","provider":"pi"}}}\n' "$status"
    ;;
esac
SH
  chmod +x "$fb/herdr"
  printf '%s\n' "$fb"
}

write_meta() { # <home> <id> [target]
  local home=$1 id=$2 target=${3:-lab:w1:p1} rest=${3:-lab:w1:p1}
  rest=${target#*:}
  fm_write_meta "$home/state/$id.meta" \
    "backend=herdr" "window=$target" "endpoint_task_id=$id" \
    "herdr_session=${target%%:*}" "herdr_workspace_id=${rest%%:*}" \
    "herdr_tab_id=${rest%%:*}:t1" "herdr_pane_id=$rest" \
    "worktree=/tmp/$id" "project=/tmp/project" "harness=pi" "kind=ship"
}

run_send() { # <home> <fakebin> <log> <args...>
  local home=$1 fb=$2 log=$3; shift 3
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" \
    FM_HERDR_LOG="$log" FM_HERDR_STATE="$home/herdr.state" FM_SEND_SETTLE=0 \
    FM_HERDR_REPLACE_AFTER_VALIDATION="${FM_HERDR_REPLACE_AFTER_VALIDATION:-0}" \
    "$SEND" "$@"
}

test_exact_id_send() {
  local home=$TMP_ROOT/exact fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" lane-a
  FM_EXPECTED_LOCK=$(PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" HERDR_SESSION=lab \
    FM_HERDR_LOG="$log" FM_HERDR_STATE="$home/herdr.state" \
    bash -c '. "$1/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path lab' _ "$ROOT") \
    || fail "could not resolve the expected presentation lock"
  export FM_EXPECTED_LOCK
  run_send "$home" "$fb" "$log" lane-a 'lost dispatch' >/dev/null 2>&1 \
    || fail "exact task id send should succeed"
  out=$(cat "$log")
  assert_contains "$out" 'pane send-text w1:p1 lost dispatch' "exact id did not reach its recorded pane"
  assert_contains "$out" 'pane send-keys w1:p1 enter' "exact id did not submit with Enter"
  unset FM_EXPECTED_LOCK
  pass "fm-send strict: exact task ids use exact Herdr metadata"
}

test_live_identity_is_rechecked_under_send_lock() {
  local home=$TMP_ROOT/live-lock fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" lane-lock
  : > "$home/pane-get-count"
  out=$(FM_HERDR_MOVE_AFTER_FIRST=1 FM_HERDR_PANE_GET_COUNT="$home/pane-get-count" \
    run_send "$home" "$fb" "$log" lane-lock 'do not deliver' 2>&1) \
    && fail "send controlled an endpoint that moved after identity preflight"
  assert_contains "$out" "does not match its recorded live pane, tab, and workspace identity" \
    "send did not explain its locked live-identity refusal"
  assert_not_contains "$(cat "$log")" 'pane send-text' \
    "send reached the pane after its live component identity changed"
  pass "fm-send strict: live identity stays authorized through the locked send"
}

test_session_replacement_uses_bound_transport() {
  local home=$TMP_ROOT/session-restart fb log expected_lock
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  : > "$home/herdr.sock"
  write_meta "$home" lane-restart
  expected_lock=$(PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" HERDR_SESSION=lab \
    FM_HERDR_LOG="$log" FM_HERDR_STATE="$home/herdr.state" \
    bash -c '. "$1/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path lab' _ "$ROOT") \
    || fail "could not resolve the pre-restart presentation lock"
  export FM_EXPECTED_LOCK="$expected_lock"
  FM_EXPECTED_LOCK="$expected_lock" FM_HERDR_REPLACE_AFTER_VALIDATION=1 \
    run_send "$home" "$fb" "$log" lane-restart 'deliver to prior generation' >/dev/null 2>&1 \
    || fail "send lost its bound Herdr transport during session replacement"
  [ -e "$home/bound-generation-used" ] \
    || fail "send resolved the replacement session instead of its authorized socket generation"
  assert_contains "$(cat "$log")" 'pane send-text w1:p1 deliver to prior generation' \
    "send did not reach the socket generation authorized under the presentation lock"
  unset FM_EXPECTED_LOCK
  pass "fm-send strict: session replacement cannot retarget bound transport"
}

test_ambiguous_or_foreign_metadata_refuses() {
  local home=$TMP_ROOT/identity fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" foreign
  printf 'endpoint_task_id=another-task\n' >> "$home/state/foreign.meta"
  out=$(run_send "$home" "$fb" "$log" foreign hello 2>&1) \
    && fail "duplicate task binding should refuse"
  assert_contains "$out" "lacks one exact task binding" "duplicate binding refusal should name the identity defect"

  write_meta "$home" duplicate lab:w2:p1
  printf 'window=lab:w2:p2\n' >> "$home/state/duplicate.meta"
  out=$(run_send "$home" "$fb" "$log" lab:w2:p2 hello 2>&1) \
    && fail "duplicate endpoint should refuse through explicit target resolution"
  assert_contains "$out" "ambiguous or invalid task ownership" "duplicate endpoint refusal should name the ambiguity"
  [ ! -s "$log" ] || fail "invalid endpoint metadata reached Herdr"
  pass "fm-send strict: ambiguous and foreign endpoint identities fail closed"
}

test_duplicate_endpoint_owners_refuse() {
  local home=$TMP_ROOT/duplicate-owners fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" owner-a lab:w3:p1
  write_meta "$home" owner-b lab:w3:p1
  out=$(run_send "$home" "$fb" "$log" owner-a hello 2>&1) \
    && fail "a task selector sharing an endpoint should refuse"
  assert_contains "$out" "ambiguous or duplicate task ownership" "task selector refusal should name the ownership ambiguity"
  out=$(run_send "$home" "$fb" "$log" lab:w3:p1 hello 2>&1) \
    && fail "an endpoint recorded for two tasks should refuse"
  assert_contains "$out" "ambiguous or invalid task ownership" "duplicate owner refusal should name the ownership ambiguity"
  [ ! -s "$log" ] || fail "a multiply owned endpoint reached Herdr"
  pass "fm-send strict: duplicate endpoint owners fail closed"
}

test_cross_component_identity_refuses() {
  local home=$TMP_ROOT/cross-component fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" crossed lab:w1:p1
  perl -pi -e 's/^herdr_workspace_id=.*/herdr_workspace_id=w2/; s/^herdr_tab_id=.*/herdr_tab_id=w2:t1/' \
    "$home/state/crossed.meta"
  out=$(run_send "$home" "$fb" "$log" crossed hello 2>&1) \
    && fail "cross-workspace component identity should refuse"
  assert_contains "$out" "malformed or inconsistent" "component mismatch refusal should name inconsistent metadata"
  [ ! -s "$log" ] || fail "cross-workspace component metadata reached Herdr"
  pass "fm-send strict: cross-component endpoint identities fail closed"
}

test_live_tab_identity_refuses() {
  local home=$TMP_ROOT/live-tab fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" crossed-tab lab:w1:p1
  perl -pi -e 's/^herdr_tab_id=.*/herdr_tab_id=w1:t2/' "$home/state/crossed-tab.meta"
  out=$(run_send "$home" "$fb" "$log" crossed-tab hello 2>&1) \
    && fail "a pane bound to another live tab should refuse"
  assert_contains "$out" "does not match its recorded live pane, tab, and workspace identity" \
    "live tab mismatch refusal should name the exact identity defect"
  assert_not_contains "$(cat "$log")" "pane send-" "live tab mismatch reached Herdr delivery"
  pass "fm-send strict: live pane and tab identities must agree"
}

test_live_tab_workspace_owner_refuses() {
  local home=$TMP_ROOT/live-tab-owner fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" crossed-owner lab:w1:p1
  out=$(FM_HERDR_TAB_WORKSPACE=w2 run_send "$home" "$fb" "$log" crossed-owner hello 2>&1) \
    && fail "a tab independently bound to another workspace should refuse"
  assert_contains "$out" "does not match its independently recorded workspace identity" \
    "independent tab owner mismatch should name the identity defect"
  assert_not_contains "$(cat "$log")" "pane send-" "independent tab owner mismatch reached Herdr delivery"
  pass "fm-send strict: live tab ownership is independently verified"
}

test_unset_home_and_unresolved_refuse() {
  local home=$TMP_ROOT/refuse fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  out=$(env -u FM_HOME PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$home" \
    FM_HERDR_LOG="$log" FM_HERDR_STATE="$home/herdr.state" \
    "$SEND" lab:w1:p1 hello 2>&1) && fail "unset FM_HOME should refuse"
  assert_contains "$out" "FM_HOME is not set" "unset-home refusal should be explicit"
  out=$(run_send "$home" "$fb" "$log" lost-target hello 2>&1) \
    && fail "unresolved selector should refuse"
  assert_contains "$out" "not resolvable" "unresolved selector should name the problem"
  [ ! -s "$log" ] || fail "a refused selector reached Herdr"
  pass "fm-send strict: unresolved selection stops before transport"
}

test_legacy_shapes_and_prefixless_panes_refuse() {
  local home=$TMP_ROOT/legacy fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" nudge default:wB:p2
  out=$(run_send "$home" "$fb" "$log" wB:p2 nudge 2>&1) \
    && fail "prefixless pane id should refuse"
  assert_contains "$out" "use 'default:wB:p2'" "prefixless refusal should show the canonical target"
  out=$(run_send "$home" "$fb" "$log" old:window hello 2>&1) \
    && fail "retired one-colon target should refuse"
  assert_contains "$out" "retired tmux target shape" "legacy target refusal should be explicit"
  [ ! -s "$log" ] || fail "legacy target refusal invoked Herdr"
  pass "fm-send strict: legacy target shapes are never reinterpreted"
}

test_explicit_exact_target_and_key() {
  local home=$TMP_ROOT/explicit fb log
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  run_send "$home" "$fb" "$log" lab:w9:p7 hello >/dev/null 2>&1 \
    || fail "exact explicit Herdr target should send"
  rm -f "$home/herdr.state"
  run_send "$home" "$fb" "$log" lab:w9:p7 --key Escape >/dev/null 2>&1 \
    || fail "supported Pi key should send"
  grep -F 'pane send-keys w9:p7 escape' "$log" >/dev/null \
    || fail "Escape was not normalized for Herdr"
  pass "fm-send strict: explicit exact targets and Pi keys use Herdr"
}

test_exact_id_send
test_live_identity_is_rechecked_under_send_lock
test_session_replacement_uses_bound_transport
test_ambiguous_or_foreign_metadata_refuses
test_duplicate_endpoint_owners_refuse
test_cross_component_identity_refuses
test_live_tab_identity_refuses
test_live_tab_workspace_owner_refuses
test_unset_home_and_unresolved_refuse
test_legacy_shapes_and_prefixless_panes_refuse
test_explicit_exact_target_and_key
