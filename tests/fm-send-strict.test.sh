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
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "pane get")
    if [ "${FM_HERDR_MISSING:-0}" = 1 ]; then printf '{"error":{"code":"pane_not_found"}}\n'
    else printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "${3:-}"; fi ;;
  "pane send-text") : ;;
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
    "herdr_tab_id=t1" "herdr_pane_id=$rest" \
    "worktree=/tmp/$id" "project=/tmp/project" "harness=pi" "kind=ship"
}

run_send() { # <home> <fakebin> <log> <args...>
  local home=$1 fb=$2 log=$3; shift 3
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" \
    FM_HERDR_LOG="$log" FM_HERDR_STATE="$home/herdr.state" FM_SEND_SETTLE=0 \
    "$SEND" "$@"
}

test_exact_id_send() {
  local home=$TMP_ROOT/exact fb log out
  mkdir -p "$home/state"; fb=$(make_stubs "$home"); log=$home/herdr.log; : > "$log"
  write_meta "$home" lane-a
  run_send "$home" "$fb" "$log" lane-a 'lost dispatch' >/dev/null 2>&1 \
    || fail "exact task id send should succeed"
  out=$(cat "$log")
  assert_contains "$out" 'pane send-text w1:p1 lost dispatch' "exact id did not reach its recorded pane"
  assert_contains "$out" 'pane send-keys w1:p1 enter' "exact id did not submit with Enter"
  pass "fm-send strict: exact task ids use exact Herdr metadata"
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
  assert_contains "$out" "missing, empty, or ambiguous Herdr endpoint" "duplicate endpoint refusal should name the ambiguity"
  [ ! -s "$log" ] || fail "invalid endpoint metadata reached Herdr"
  pass "fm-send strict: ambiguous and foreign endpoint identities fail closed"
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
test_ambiguous_or_foreign_metadata_refuses
test_unset_home_and_unresolved_refuse
test_legacy_shapes_and_prefixless_panes_refuse
test_explicit_exact_target_and_key
