#!/usr/bin/env bash
# Post-submit settle behavior for Herdr text delivery.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-send-settle)
SEND="$ROOT/bin/fm-send.sh"

make_case() {  # <name>
  local dir="$TMP_ROOT/$1" home="$TMP_ROOT/$1/home" fb
  mkdir -p "$home/state"
  fb=$(fm_fakebin "$dir")
  fm_fake_herdr_terminal "$fb"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$FM_FAKE_SLEEP_LOG"
SH
  chmod +x "$fb/sleep"
  printf '╭────╮\n│ >  │\n╰────╯\n' > "$dir/capture"
  cat > "$home/state/task.meta" <<EOF_META
backend=herdr
endpoint_task_id=task
window=default:w1:p1
worktree=/tmp/task-worktree
project=/tmp/task-project
harness=claude
herdr_session=default
herdr_workspace_id=w1
herdr_tab_id=w1:t1
herdr_pane_id=w1:p1
EOF_META
  printf '%s\n%s\n%s\n' "$dir" "$home" "$fb"
}

run_send() {  # <name> <settle> <text-or-key>
  local values dir home fb
  values=$(make_case "$1")
  dir=$(printf '%s\n' "$values" | sed -n '1p')
  home=$(printf '%s\n' "$values" | sed -n '2p')
  fb=$(printf '%s\n' "$values" | sed -n '3p')
  : > "$dir/sleeps"
  if [ "$3" = key ]; then
    PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$dir/runtime.log" \
      FM_FAKE_HERDR_CAPTURE="$dir/capture" FM_FAKE_SLEEP_LOG="$dir/sleeps" \
      FM_SEND_SETTLE="$2" "$SEND" task --key Enter >/dev/null
  else
    PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$dir/runtime.log" \
      FM_FAKE_HERDR_CAPTURE="$dir/capture" FM_FAKE_SLEEP_LOG="$dir/sleeps" \
      FM_BACKEND_HERDR_SUBMIT_MIN_SLEEP=0 FM_SEND_SLEEP=0 FM_SEND_SETTLE="$2" \
      "$SEND" task hello >/dev/null
  fi
  printf '%s\n' "$dir"
}

test_successful_send_uses_configured_settle() {
  local dir
  dir=$(run_send configured 7 text)
  assert_grep '7' "$dir/sleeps" "successful send did not use configured post-submit settle"
  pass "fm-send settle: successful text delivery uses the configured pause"
}

test_zero_disables_post_submit_settle() {
  local dir
  dir=$(run_send disabled 0 text)
  assert_no_grep '1' "$dir/sleeps" "zero settle still invoked the default post-submit pause"
  pass "fm-send settle: zero disables the post-submit pause"
}

test_key_path_never_uses_post_submit_settle() {
  local dir
  dir=$(run_send key-path 9 key)
  [ ! -s "$dir/sleeps" ] || fail "key delivery unexpectedly used post-submit settle"
  pass "fm-send settle: key delivery bypasses the text-settle path"
}

test_successful_send_uses_configured_settle
test_zero_disables_post_submit_settle
test_key_path_never_uses_post_submit_settle
