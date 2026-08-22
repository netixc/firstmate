#!/usr/bin/env bash
# Exact Herdr cleanup identity and legacy-record preservation regressions.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-herdr.sh
. "$ROOT/bin/fm-herdr.sh"
TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-teardown-endpoint-safety)

write_current() { # <meta> <id>
  local meta=$1 id=$2
  fm_write_meta "$meta" \
    "backend=herdr" "window=lab:w-$id:p1" "endpoint_task_id=$id" \
    "herdr_session=lab" "herdr_workspace_id=w-$id" "herdr_tab_id=w-$id:t-$id" \
    "herdr_pane_id=w-$id:p1" "worktree=/tmp/$id" "project=/tmp/project" \
    "harness=pi" "kind=ship" "mode=local-only"
}

test_exact_current_metadata_validates() {
  local state=$TMP_ROOT/current id=Task_A.1
  mkdir -p "$state"; write_current "$state/$id.meta" "$id"
  fm_herdr_validate_task_endpoint "$state/$id.meta" "$id" record-only || fail "exact Herdr metadata should validate"
  [ "$FM_HERDR_VALIDATED_TARGET" = "lab:w-$id:p1" ] || fail "exact endpoint identity changed"
  pass "cleanup identity accepts exact current Herdr metadata"
}

test_invalid_and_legacy_metadata_refuse_without_calls() {
  local state=$TMP_ROOT/refuse id=legacy-a out before
  mkdir -p "$state"
  fm_write_meta "$state/$id.meta" "window=firstmate:fm-$id" "worktree=/tmp/$id" "project=/tmp/project"
  before=$(shasum -a 256 "$state/$id.meta" | awk '{print $1}')
  out=$(fm_herdr_validate_task_endpoint "$state/$id.meta" "$id" 2>&1) \
    && fail "fieldless metadata should refuse"
  assert_contains "$out" 'retired legacy tmux metadata' "fieldless refusal did not name preservation"
  [ "$(shasum -a 256 "$state/$id.meta" | awk '{print $1}')" = "$before" ] || fail "fieldless validation rewrote metadata"

  for mutation in missing-window wrong-binding duplicate-backend malformed-target; do
    write_current "$state/$id.meta" "$id"
    case "$mutation" in
      missing-window) grep -v '^window=' "$state/$id.meta" > "$state/$id.tmp" && mv "$state/$id.tmp" "$state/$id.meta" ;;
      wrong-binding) perl -pi -e 's/^endpoint_task_id=.*/endpoint_task_id=other/' "$state/$id.meta" ;;
      duplicate-backend) printf 'backend=herdr\n' >> "$state/$id.meta" ;;
      malformed-target) perl -pi -e 's/^window=.*/window=lab:p1/' "$state/$id.meta" ;;
    esac
    fm_herdr_validate_task_endpoint "$state/$id.meta" "$id" >/dev/null 2>&1 \
      && fail "$mutation metadata should refuse"
  done
  pass "missing, duplicate, malformed, mismatched, and legacy identity all refuse"
}

make_teardown_world() { # <name> <id> <mode>
  local name=$1 id=$2 mode=$3 world home fb
  world=$TMP_ROOT/$name; home=$world/home; fb=$world/fakebin
  mkdir -p "$home/state" "$home/data" "$home/config" "$fb"
  write_current "$home/state/$id.meta" "$id"
  perl -pi -e "s|^worktree=.*|worktree=$world/missing-wt|; s|^project=.*|project=$world/missing-project|" "$home/state/$id.meta"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "session list")
    [ "${FM_HERDR_TEST_MODE:-}" != unreachable ] || exit 1
    printf '{"sessions":[{"name":"lab","running":true,"socket_path":"%s/herdr.sock"}]}\n' "${FM_HOME:-/tmp}" ;;
  "pane get")
    if [ "${FM_HERDR_TEST_MODE:-}" = ambiguous ]; then printf 'not-json\n'
    else printf '{"error":{"code":"pane_not_found"}}\n'; fi ;;
  *) printf '{"result":{}}\n' ;;
esac
SH
  chmod +x "$fb/herdr"
  fm_fake_exit0 "$fb" treehouse no-mistakes gh gh-axi
  printf '%s|%s|%s\n' "$world" "$home" "$fb"
}

test_unreachable_or_ambiguous_herdr_preserves_records() {
  local mode id=cleanup-a rec world home fb out before
  for mode in unreachable ambiguous; do
    rec=$(make_teardown_world "$mode" "$id" "$mode")
    IFS='|' read -r world home fb <<EOF
$rec
EOF
    before=$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')
    : > "$world/herdr.log"
    out=$(PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      FM_HERDR_LOG="$world/herdr.log" FM_HERDR_TEST_MODE="$mode" \
      "$TEARDOWN" "$id" --force 2>&1) && fail "$mode Herdr should refuse cleanup"
    assert_contains "$out" 'nothing was changed' "$mode refusal did not state the preservation boundary"
    [ "$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')" = "$before" ] || fail "$mode refusal changed metadata"
  done
  pass "unreachable and ambiguous Herdr stop cleanup with durable records intact"
}

test_locked_teardown_revalidates_live_identity() {
  local id=cleanup-race rec world home fb log changed lock ready release holder_pid teardown_pid sleeper_pid sleeper_alive rc waited
  rec=$(make_teardown_world locked-race "$id" present)
  IFS='|' read -r world home fb <<EOF
$rec
EOF
  log=$world/herdr.log
  changed=$world/component-changed
  ready=$world/lock-ready
  release=$world/lock-release
  : > "$log"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "session list") printf '{"sessions":[{"name":"lab","running":true,"socket_path":"%s/herdr.sock"}]}\n' "$FM_HOME" ;;
  "pane get")
    if [ -e "$FM_HERDR_COMPONENT_CHANGED" ]; then tab=w-cleanup-race:t-other
    else tab=w-cleanup-race:t-cleanup-race
    fi
    printf '{"result":{"pane":{"pane_id":"w-cleanup-race:p1","tab_id":"%s","workspace_id":"w-cleanup-race"}}}\n' "$tab"
    ;;
  "tab get") printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"w-cleanup-race"}}}\n' "${3:-}" ;;
  "pane close") printf 'closed\n' >> "$FM_HERDR_LOG" ;;
  *) printf '{"result":{}}\n' ;;
esac
SH
  chmod +x "$fb/herdr"
  lock=$(PATH="$fb:$PATH" FM_HOME="$home" FM_HERDR_LOG="$log" \
    FM_HERDR_COMPONENT_CHANGED="$changed" bash -c \
    '. "$1/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path lab' _ "$ROOT") \
    || fail "locked-race: could not resolve the presentation lock"
  ROOT="$ROOT" LOCK="$lock" READY="$ready" RELEASE="$release" bash -c '
    . "$ROOT/bin/fm-wake-lib.sh"
    fm_lock_try_acquire "$LOCK" || exit 1
    : > "$READY"
    while [ ! -e "$RELEASE" ]; do sleep 0.05; done
    fm_lock_release "$LOCK"
  ' &
  holder_pid=$!
  waited=0
  while [ ! -e "$ready" ] && [ "$waited" -lt 100 ]; do sleep 0.05; waited=$((waited + 1)); done
  [ -e "$ready" ] || fail "locked-race: lock holder did not start"
  mkdir -p "$world/missing-wt"
  (cd "$world/missing-wt" && exec sleep 300) &
  sleeper_pid=$!
  PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_HERDR_LOG="$log" \
    FM_HERDR_COMPONENT_CHANGED="$changed" "$TEARDOWN" "$id" --force \
    > "$world/stdout" 2> "$world/stderr" &
  teardown_pid=$!
  waited=0
  while ! grep -q '^pane get ' "$log" 2>/dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.05
    waited=$((waited + 1))
  done
  grep -q '^pane get ' "$log" 2>/dev/null || {
    : > "$release"
    wait "$holder_pid" 2>/dev/null || true
    wait "$teardown_pid" 2>/dev/null || true
    kill "$sleeper_pid" 2>/dev/null || true
    wait "$sleeper_pid" 2>/dev/null || true
    fail "locked-race: teardown never inspected the pane before waiting"
  }
  sleep 0.3
  : > "$changed"
  : > "$release"
  wait "$holder_pid" || fail "locked-race: lock holder failed"
  rc=0
  wait "$teardown_pid" || rc=$?
  sleeper_alive=0
  kill -0 "$sleeper_pid" 2>/dev/null && sleeper_alive=1
  kill "$sleeper_pid" 2>/dev/null || true
  wait "$sleeper_pid" 2>/dev/null || true
  [ "$rc" -ne 0 ] || fail "locked-race: teardown accepted a component identity replaced during its lock wait"
  [ "$sleeper_alive" -eq 1 ] || fail "locked-race: identity refusal reaped a task process before authorization"
  assert_present "$home/state/$id.meta" "locked-race: refusal removed the endpoint record"
  assert_no_grep 'pane close ' "$log" "locked-race: refusal closed the replaced pane"
  assert_grep 'does not match its recorded live pane' "$world/stderr" \
    "locked-race: refusal did not explain the changed live component identity"
  pass "teardown revalidates live Herdr identity after acquiring its presentation lock"
}

test_exact_current_metadata_validates
test_invalid_and_legacy_metadata_refuse_without_calls
test_unreachable_or_ambiguous_herdr_preserves_records
test_locked_teardown_revalidates_live_identity
