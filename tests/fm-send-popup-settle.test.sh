#!/usr/bin/env bash
# Popup-settle selection for Herdr-backed worker messages.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-send-popup-settle)
SEND="$ROOT/bin/fm-send.sh"

run_case() {  # <name> <harness> <message>
  local harness=$2 message=$3 dir="$TMP_ROOT/$1" home="$TMP_ROOT/$1/home" fb
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
harness=$harness
herdr_session=default
herdr_workspace_id=w1
herdr_tab_id=w1:t1
herdr_pane_id=w1:p1
EOF_META
  : > "$dir/sleeps"
  PATH="$fb:$PATH" FM_HOME="$home" FM_FAKE_HERDR_LOG="$dir/runtime.log" \
    FM_FAKE_HERDR_CAPTURE="$dir/capture" FM_FAKE_SLEEP_LOG="$dir/sleeps" \
    FM_BACKEND_HERDR_SUBMIT_MIN_SLEEP=0 FM_SEND_SLEEP=0 FM_SEND_SETTLE=0 \
    "$SEND" task "$message" >/dev/null
  sed -n '1p' "$dir/sleeps"
}

test_slash_command_uses_long_settle() {
  local out
  out=$(run_case slash claude /no-mistakes)
  [ "$out" = 1.2 ] || fail "slash command should use 1.2s popup settle, got '$out'"
  pass "fm-send popup settle: slash commands use the long settle"
}

test_plain_text_uses_short_settle() {
  local out
  out=$(run_case plain claude 'continue the work')
  [ "$out" = 0.3 ] || fail "plain text should use 0.3s settle, got '$out'"
  pass "fm-send popup settle: plain text uses the short settle"
}

test_dollar_skill_is_codex_scoped() {
  local out
  out=$(run_case codex-dollar codex "\$no-mistakes")
  [ "$out" = 1.2 ] || fail "Codex dollar skill should use long settle, got '$out'"
  out=$(run_case claude-dollar claude "\$HOME is unchanged")
  [ "$out" = 0.3 ] || fail "ordinary dollar text outside Codex should use short settle, got '$out'"
  pass "fm-send popup settle: dollar-command delay is scoped to Codex"
}

test_slash_command_uses_long_settle
test_plain_text_uses_short_settle
test_dollar_skill_is_codex_scoped
