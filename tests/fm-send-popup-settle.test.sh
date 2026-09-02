#!/usr/bin/env bash
#
# Some TUIs open a completion popup when the composer's first character triggers
# for a leading `$<skill>` invocation (e.g. `$no-mistakes`). Submitting before the
# popup settles lets it swallow the Enter, so the line never submits. fm-send
# absorbs this by pausing `settle` seconds AFTER typing and BEFORE the (retried)
# Enter - the first sleep the submit core makes. These tests pin the
# settle-selection matrix hermetically with native Herdr and sleep fixtures:
#
# The settle matrix governs the typed Pi invocation plane. A task-selector
# message that is not an invocation rides the durable inbox instead, where only
# the constant doorbell with its fixed fast settle touches the terminal:
#   /...       -> 1.2
#   other text -> inbox plane for a selector
#
# The popup-settle is the first sleep recorded: the submit core types the text,
# then `sleep "$settle"`, then the Enter-retry loop (sleep 0.4 each) and finally
# fm-send's own post-submit FM_SEND_SETTLE pause. So tail-vs-head matters: this
# suite asserts on the head sleep, distinct from fm-send-settle.test.sh which pins
# the tail post-submit pause. The retried Enter in the submit core remains the
# real safety net; this settle is only the optimization that lets the popup clear so
# the first Enter lands.
#
# Every case below passes a LITERAL `$<skill>` / `$price` message in single quotes
# on purpose - the whole point is to send an unexpanded `$...` line to the agent -
# so SC2016 (which flags single-quoted `$` as a probably-forgotten expansion) is a
# false positive here and is disabled file-wide.
# shellcheck disable=SC2016
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

SEND="$ROOT/bin/fm-send.sh"

TMP_ROOT=$(fm_test_tmproot fm-send-popup-settle)

# Native Herdr returns an empty composer; fake sleep records every requested
# duration into FM_SLEEP_LOG instead of sleeping.
make_stubs() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb
  fb=$(fm_fakebin "$dir")
  fm_test_fake_herdr "$fb"
  fm_test_fake_sleep_log "$fb"
  printf '%s\n' "$fb"
}

# first_settle <expected> <label> <harness> <message> [selector-form]: build a
# fresh home, send <message> to a recorded task, and assert the first sleep
# (the popup-settle) equals <expected>. FM_SEND_SETTLE=0 strips the trailing
# post-submit pause so the log holds only the popup-settle plus the 0.4 Enter wait,
# keeping the head assertion crisp. FM_ROOT_OVERRIDE points at a non-repo dir so
# fm-guard's tangle check stays silent; its watcher-liveness note goes to stderr
# (discarded).
first_settle() {  # <expected> <label> <harness|--explicit> <message> [selector-form]
  local expected=$1 label=$2 harness=$3 msg=$4
  local selector_form=${5:-legacy}
  local dir fb log home target rc first
  dir="$TMP_ROOT/case-$RANDOM"; mkdir -p "$dir/state"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"; home="$dir"
  case "$selector_form" in
    exact) target="popupcase" ;;
    legacy) target="fm-popupcase" ;;
    *) fail "$label: unknown selector form '$selector_form'" ;;
  esac
  fm_write_herdr_task_meta "$home/state/popupcase.meta" "harness=$harness" "kind=ship"
  : > "$log"
  env FM_SEND_SETTLE=0 PATH="$fb:$PATH" \
    FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_SLEEP_LOG="$log" \
    FM_FAKE_HERDR_DUPLICATE=1 FM_FAKE_HERDR_TASK_ID=popupcase \
    "$SEND" "$target" "$msg" 2>/dev/null; rc=$?
  expect_code 0 "$rc" "$label: send should succeed"
  first=$(head -1 "$log")
  [ "$first" = "$expected" ] || fail "$label: expected popup-settle $expected, got '$first'"$'\n'"--- sleeps ---"$'\n'"$(cat "$log")"
  pass "fm-send popup-settle: $label -> ${expected}s"
}

# rides_inbox <label> <harness> <message>: a task-selector message that is NOT
# a harness-native invocation no longer types its payload at all - it rides
# the durable inbox, so no popup-settle question exists for it. Assert the
# routing (record enqueued, payload never typed) and that the doorbell's own
# never regress into slowing plain text again.
rides_inbox() {  # <label> <harness> <message>
  local label=$1 harness=$2 msg=$3
  local dir fb log home rc first
  dir="$TMP_ROOT/case-$RANDOM"; mkdir -p "$dir/state"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"; home="$dir"
  fm_write_herdr_task_meta "$home/state/popupcase.meta" "harness=$harness" "kind=ship"
  : > "$log"
  env FM_SEND_SETTLE=0 PATH="$fb:$PATH" \
    FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_SLEEP_LOG="$log" \
    FM_FAKE_HERDR_DUPLICATE=1 FM_FAKE_HERDR_TASK_ID=popupcase \
    "$SEND" fm-popupcase "$msg" 2>/dev/null; rc=$?
  expect_code 0 "$rc" "$label: send should succeed"
  grep -qF -- "$msg" "$home/state/popupcase.inbox/001.msg" \
    || fail "$label: the steer should be enqueued in the task inbox"
  first=$(head -1 "$log")
  [ "$first" = "0.3" ] || fail "$label: the doorbell ring should keep the fast settle, got '$first'"$'\n'"--- sleeps ---"$'\n'"$(cat "$log")"
  pass "fm-send popup-settle: $label -> inbox plane, fast doorbell"
}

# Plain Pi slash invocations use the long popup settle.
first_settle 1.2 'Pi /command -> long settle' pi '/no-mistakes'
first_settle 1.2 'Pi /command exact task id -> long settle' pi '/no-mistakes' exact

# Dollar-prefixed and plain text are ordinary durable-inbox steers for Pi.
rides_inbox 'Pi $-message' pi '$no-mistakes'
rides_inbox 'Pi plain text' pi 'just a normal steer'
