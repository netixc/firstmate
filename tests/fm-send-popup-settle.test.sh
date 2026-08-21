#!/usr/bin/env bash
# fm-send pre-submit popup-settle selection.
#
# Slash commands can open a completion popup. Submitting before the popup
# settles lets it swallow Enter, so fm-send waits before the first Enter for
# `/...` messages and keeps the fast path for ordinary text, including `$...`.
#
# The popup-settle is the FIRST sleep recorded: the Herdr submit path types the text,
# then `sleep "$settle"`, then the Enter-retry loop (sleep 0.4 each) and finally
# fm-send's own post-submit FM_SEND_SETTLE pause. So tail-vs-head matters: this
# suite asserts on the HEAD sleep, distinct from fm-send-settle.test.sh which pins
# the TAIL (post-submit) pause. The retried Enter remains the
# real safety net; this settle is only the optimization that lets the popup clear so
# the first Enter lands.
#
# Every case below passes a LITERAL `$<skill>` / `$price` message in single quotes
# on purpose - the whole point is to send an unexpanded `$...` line to the agent -
# so SC2016 (which flags single-quoted `$` as a probably-forgotten expansion) is a
# false positive here and is disabled file-wide.
# shellcheck disable=SC2016
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SEND="$ROOT/bin/fm-send.sh"

TMP_ROOT=$(fm_test_tmproot fm-send-popup-settle)

# A fake Herdr CLI that drives the submit
# path to a clean "empty" verdict on the first Enter, and a fake sleep that records
# every requested duration (one per line) into FM_SLEEP_LOG instead of sleeping.
make_stubs() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "pane get") printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "${3:-}" ;;
  "pane send-text") : ;;
  "pane send-keys") : > "$FM_HERDR_STATE" ;;
  "agent get")
    if [ -e "$FM_HERDR_STATE" ]; then status=working; else status=idle; fi
    printf '{"result":{"agent":{"agent_status":"%s","provider":"pi"}}}\n' "$status"
    ;;
esac
SH
  chmod +x "$fb/herdr"
  cat > "$fb/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >> "$FM_SLEEP_LOG"
exit 0
SH
  chmod +x "$fb/sleep"
  printf '%s\n' "$fb"
}

# first_settle <expected> <label> <harness|--explicit> <message> [selector-form]: build a fresh
# home, send <message> to a target whose meta records <harness> (or to a explicit
# Herdr target with NO meta when --explicit), and assert the FIRST recorded sleep
# (the popup-settle) equals <expected>. FM_SEND_SETTLE=0 strips the trailing
# post-submit pause so the log holds only the popup-settle plus the 0.4 Enter wait,
# keeping the head assertion crisp. FM_ROOT_OVERRIDE points at a non-repo dir so
# fm-guard's tangle check stays silent; its watcher-liveness note goes to stderr
# (discarded).
first_settle() {  # <expected> <label> <harness|--explicit> <message> [selector-form]
  local expected=$1 label=$2 harness=$3 msg=$4
  local selector_form=${5:-legacy}
  local dir fb log herdr_log herdr_state err home target rc first meta_id
  dir="$TMP_ROOT/case-$RANDOM"; mkdir -p "$dir/state"
  fb=$(make_stubs "$dir"); log="$dir/sleep.log"; herdr_log="$dir/herdr.log"; herdr_state="$dir/herdr.state"; err="$dir/send.err"; home="$dir"
  if [ "$harness" = --explicit ]; then
    target="sess:w1:p1"
  else
    case "$selector_form" in
      exact)
        target="popupcase"
        meta_id=popupcase
        ;;
      legacy)
        target="fm-popupcase"
        meta_id=popupcase
        ;;
      *)
        fail "$label: unknown selector form '$selector_form'"
        ;;
    esac
    fm_write_meta "$home/state/$meta_id.meta" "backend=herdr" "window=sess:w1:p1" "endpoint_task_id=$meta_id" "herdr_session=sess" "herdr_workspace_id=w1" "herdr_tab_id=w1:t1" "herdr_pane_id=w1:p1" "worktree=/tmp/$meta_id" "project=/tmp/project" "harness=$harness"
  fi
  : > "$log"
  env FM_SEND_SETTLE=0 PATH="$fb:$PATH" \
    FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_SLEEP_LOG="$log" FM_HERDR_LOG="$herdr_log" FM_HERDR_STATE="$herdr_state" \
    "$SEND" "$target" "$msg" 2>"$err"; rc=$?
  [ "$rc" -eq 0 ] || fail "$label: send should succeed (exit $rc): $(cat "$err"); Herdr calls: $(cat "$herdr_log")"
  first=$(head -1 "$log")
  [ "$first" = "$expected" ] || fail "$label: expected popup-settle $expected, got '$first'"$'\n'"--- sleeps ---"$'\n'"$(cat "$log")"
  pass "fm-send popup-settle: $label -> ${expected}s"
}

# Same `$` message to pi keeps the fast path: `$` is ordinary text there.
first_settle 0.3 'pi $-message -> fast path' pi '$no-mistakes'

# `$`-prefixed plain text to pi must not popup-settle.
first_settle 0.3 'pi "$5/month" -> fast path' pi '$5/month is cheap'

# An explicit session:window target keeps the fast path for a `$` message.
first_settle 0.3 'explicit target $message -> fast path (unknown harness)' --explicit '$no-mistakes'

# The `/` slash case uses the long settle.
first_settle 1.2 'pi /command -> long settle (slash unchanged)' pi '/no-mistakes'

# Plain text to pi takes the fast path.
first_settle 0.3 'pi plain text -> fast path' pi 'just a normal steer'
