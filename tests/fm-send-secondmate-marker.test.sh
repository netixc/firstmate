#!/usr/bin/env bash
# Marked parent-to-second-mate delivery over Herdr.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-send-secondmate-marker)
SEND="$ROOT/bin/fm-send.sh"

make_case() {  # <name> <kind>
  local dir="$TMP_ROOT/$1" home="$TMP_ROOT/$1/home" fb
  mkdir -p "$home/state"
  fb=$(fm_fakebin "$dir")
  fm_fake_herdr_terminal "$fb"
  printf '╭────╮\n│ >  │\n╰────╯\n' > "$dir/capture"
  cat > "$home/state/target.meta" <<EOF_META
backend=herdr
endpoint_task_id=target
window=default:w1:p1
worktree=/tmp/target-worktree
project=/tmp/target-project
harness=pi
kind=$2
herdr_session=default
herdr_workspace_id=w1
herdr_tab_id=w1:t1
herdr_pane_id=w1:p1
EOF_META
  printf '%s\n%s\n%s\n' "$dir" "$home" "$fb"
}

send_case() {  # <name> <kind> <message>
  local values dir home fb
  values=$(make_case "$1" "$2")
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  : > "$dir/log"
  PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$dir/log" \
    FM_FAKE_HERDR_CAPTURE="$dir/capture" FM_BACKEND_HERDR_SUBMIT_MIN_SLEEP=0 \
    FM_SEND_SLEEP=0 FM_SEND_SETTLE=0 "$SEND" target "$3" >/dev/null
  printf '%s\n%s\n' "$dir" "$home"
}

test_secondmate_text_is_marked_and_correlated() {
  local values dir home records
  values=$(send_case secondmate secondmate 'please inspect the report')
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  assert_grep '[fm-from-firstmate]' "$dir/log" "second-mate message lacked the parent carrier"
  assert_grep 'corr=' "$dir/log" "second-mate message lacked its correlation id"
  records=$(find "$home/state/pending-replies" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$records" -eq 1 ] || fail "second-mate delivery should retain one pending reply record, got $records"
  pass "fm-send marker: second-mate text is marked, correlated, and retained pending"
}

test_ship_text_is_unmarked() {
  local values dir
  values=$(send_case ship ship 'please continue')
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  assert_grep 'TEXT:please continue' "$dir/log" "ship message was not delivered verbatim"
  assert_no_grep '[fm-from-firstmate]' "$dir/log" "ordinary worker message was marked as a parent request"
  pass "fm-send marker: ordinary worker text remains unmarked"
}

test_key_path_is_unmarked() {
  local values dir home fb
  values=$(make_case key secondmate)
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  : > "$dir/log"
  PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$dir/log" \
    FM_FAKE_HERDR_CAPTURE="$dir/capture" "$SEND" target --key Enter >/dev/null
  assert_grep 'KEY:enter' "$dir/log" "key was not delivered"
  assert_no_grep '[fm-from-firstmate]' "$dir/log" "key delivery was unexpectedly marked"
  assert_absent "$home/state/pending-replies" "key delivery created a pending reply"
  pass "fm-send marker: key delivery remains unmarked and uncorrelated"
}

test_secondmate_text_is_marked_and_correlated
test_ship_text_is_unmarked
test_key_path_is_unmarked
