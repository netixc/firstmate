#!/usr/bin/env bash
# Strict selector and backend routing tests for fm-send.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-send-strict)
SEND="$ROOT/bin/fm-send.sh"

make_world() {  # <name>
  local dir="$TMP_ROOT/$1" home fb
  home="$dir/home"
  mkdir -p "$home/state" "$home/config"
  fb=$(fm_fakebin "$dir")
  fm_fake_herdr_terminal "$fb"
  printf '╭────╮\n│ >  │\n╰────╯\n' > "$dir/capture"
  printf '%s\n%s\n%s\n' "$dir" "$home" "$fb"
}

write_herdr_meta() {  # <home> <id> [backend]
  local home=$1 id=$2 backend=${3:-herdr}
  cat > "$home/state/$id.meta" <<EOF_META
backend=$backend
endpoint_task_id=$id
window=default:w1:p1
worktree=/tmp/$id-worktree
project=/tmp/$id-project
harness=claude
herdr_session=default
herdr_workspace_id=w1
herdr_tab_id=w1:t1
herdr_pane_id=w1:p1
EOF_META
}

test_task_selector_routes_exact_herdr_endpoint() {
  local values dir home fb log
  values=$(make_world exact)
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  log="$dir/log"; : > "$log"
  write_herdr_meta "$home" exact
  PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$log" FM_FAKE_HERDR_CAPTURE="$dir/capture" \
    FM_SEND_SETTLE=0 FM_BACKEND_HERDR_SUBMIT_MIN_SLEEP=0 "$SEND" exact "ship it" >/dev/null
  assert_grep 'TEXT:ship it' "$log" "fm-send did not type the requested text"
  assert_grep 'KEY:enter' "$log" "fm-send did not submit Enter"
  pass "fm-send: task selectors route to their exact Herdr endpoint"
}

test_explicit_herdr_endpoint_is_supported() {
  local values dir home fb log
  values=$(make_world explicit)
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  log="$dir/log"; : > "$log"
  PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$log" FM_FAKE_HERDR_CAPTURE="$dir/capture" \
    FM_SEND_SETTLE=0 "$SEND" lab:w9:p7 --key Escape >/dev/null
  assert_grep 'KEY:escape' "$log" "explicit endpoint key did not route through Herdr"
  pass "fm-send: an explicit Herdr endpoint remains available for out-of-home targets"
}

test_missing_home_is_refused() {
  local values dir fb out status
  values=$(make_world missing-home)
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  out=$(env -u FM_HOME PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$dir" "$SEND" exact hello 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "fm-send should require an explicit Firstmate home"
  assert_contains "$out" "FM_HOME is not set" "missing-home refusal was unclear"
  pass "fm-send: missing Firstmate home is refused before endpoint lookup"
}

test_missing_task_metadata_has_no_live_label_fallback() {
  local values dir home fb log out status
  values=$(make_world missing-meta)
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  log="$dir/log"; : > "$log"
  out=$(PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$log" FM_FAKE_HERDR_CAPTURE="$dir/capture" \
    FM_FAKE_HERDR_BARE_LABEL=fm-lost "$SEND" fm-lost hello 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "fm-<id> without durable metadata should be refused"
  assert_contains "$out" "no metadata for fm-lost" "missing metadata refusal was unclear"
  assert_no_grep 'TEXT:hello' "$log" "missing task metadata still dispatched text"
  pass "fm-send: task-shaped selectors never fall back to an unrelated live label"
}

test_stale_backend_metadata_is_rejected() {
  local values dir home fb log out status
  values=$(make_world stale-backend)
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  log="$dir/log"; : > "$log"
  write_herdr_meta "$home" stale stale-runtime
  out=$(PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$log" FM_FAKE_HERDR_CAPTURE="$dir/capture" \
    "$SEND" stale hello 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "stale backend metadata should be rejected"
  assert_contains "$out" "supported: herdr orca" "stale backend rejection did not name current choices"
  assert_no_grep 'TEXT:hello' "$log" "stale backend metadata still dispatched text"
  pass "fm-send: stale backend values are rejected without reinterpretation"
}

test_task_selector_routes_exact_herdr_endpoint
test_explicit_herdr_endpoint_is_supported
test_missing_home_is_refused
test_missing_task_metadata_has_no_live_label_fallback
test_stale_backend_metadata_is_rejected
