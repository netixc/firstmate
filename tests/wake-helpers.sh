#!/usr/bin/env bash
# tests/wake-helpers.sh - shared fixtures and mocks for the wake-queue,
# watcher/lock, and supervise-daemon suites. The fake herdr surfaces here encode
# watcher/daemon/composer behavior, so they live here rather than in the generic
# tests/lib.sh. Generic reporters/assertions come from lib.sh, pulled in below.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# fm-wake-drain.sh now calls fm-guard.sh to assert watcher liveness on every
# drain. fm-guard.sh's first check warns when the firstmate PRIMARY checkout
# (FM_ROOT) sits on a feature branch; with no override FM_ROOT resolves to the
# test runner's own checkout, which during validation is on a feature branch, so
# each drain would emit a spurious worktree-tangle banner. Point the tangle check
# at a fresh non-git dir to keep it inert across these suites - the same trick the
# direct fm-guard.sh tests use. A per-call FM_ROOT_OVERRIDE still wins where a
# suite sets its own (e.g. the watcher-lock guard-banner cases).
if [ -z "${FM_ROOT_OVERRIDE:-}" ]; then
  FM_ROOT_OVERRIDE="$(fm_test_tmproot fm-wake-tangle-root)"
  export FM_ROOT_OVERRIDE
fi

# Daemon-library tests use one explicit synthetic supervisor endpoint rather
# than inheriting or inventing a target from the host session.
FM_SUPERVISOR_TARGET=${FM_SUPERVISOR_TARGET:-default:w1:p1}
export FM_SUPERVISOR_TARGET

# Wedge-alarm notifier recorder (safety seam). The away-mode wedge alarm fires a
# real OS-level desktop notification by default. Point its FM_WEDGE_ALARM_EXEC
# seam at a recorder for every
# daemon/wake suite, so no test - present or future - can post a real macOS,
# herdr, or command: notification: it is impossible to forget, because sourcing this harness
# installs it. The recorder is an on-disk script (a real daemon a test spawns
# inherits the path and records too). It logs "<channel>\t<summary>" to
# $FM_WEDGE_ALARM_LOG, which a test sets to its own file to assert on; unset means
# /dev/null. FM_WEDGE_ALARM_FAIL=<channel> makes the recorder exit non-zero for
# that channel, to exercise graceful degradation. Suites that do not source this
# harness still cannot fire a real notification: the daemon defaults the seam to
# "discard" whenever it is sourced (its library-mode guard).
_fm_wedge_rec_dir=$(fm_test_tmproot fm-wedge-rec)
cat > "$_fm_wedge_rec_dir/rec" <<'REC'
#!/usr/bin/env bash
printf '%s\t%s\n' "${1:-}" "${2:-}" >> "${FM_WEDGE_ALARM_LOG:-/dev/null}"
case " ${FM_WEDGE_ALARM_FAIL:-} " in *" ${1:-} "*) exit 1 ;; esac
exit 0
REC
chmod +x "$_fm_wedge_rec_dir/rec"
export FM_WEDGE_ALARM_EXEC="$_fm_wedge_rec_dir/rec"

# append_wake <state> <kind> <key> <payload>: append a wake record to the durable
# queue in a subshell scoped to <state>, using the production wake library.
append_wake() {
  local state=$1 kind=$2 key=$3 payload=$4 lib="$ROOT/bin/fm-wake-lib.sh"
  FM_STATE_OVERRIDE="$state" bash -c '
    # shellcheck disable=SC1090,SC1091
    . "$1"
    fm_wake_append "$2" "$3" "$4"
  ' _ "$lib" "$kind" "$key" "$payload"
}

write_fake_herdr() {  # <fakebin> <plain|bordered>
  local fakebin=$1 mode=${2:-plain}
  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
mode=${FM_FAKE_HERDR_MODE:-__FM_FAKE_MODE__}
capture=${FM_FAKE_HERDR_CAPTURE:-}
sent=${FM_FAKE_HERDR_SENT:-/dev/null}
write_composer() {
  local text=$1 width border= i=0
  if [ "$mode" != bordered ]; then
    [ -n "$capture" ] && printf '%s\n' "$text" >> "$capture"
    return
  fi
  width=$((${#text} + 4))
  while [ "$i" -lt "$width" ]; do border="${border}─"; i=$((i + 1)); done
  printf '╭%s╮\n│ > %s │\n╰%s╯\n' "$border" "$text" "$border" > "$capture"
}
case "${1:-} ${2:-}" in
  'status --json')
    printf '{"client":{"version":"0.7.5","protocol":16},"server":{"running":true}}\n'
    ;;
  'session list')
    exit 1
    ;;
  'pane get')
    [ "${FM_FAKE_HERDR_PANE_ALIVE:-1}" = 1 ] \
      || { printf '{"error":{"code":"pane_not_found"}}\n'; exit 1; }
    pane=${3:-w1:p1}
    workspace=${pane%%:*}
    [ "$workspace" != "$pane" ] || workspace=w1
    printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s:t1","workspace_id":"%s","foreground_cwd":"%s"}}}\n' \
      "$pane" "$workspace" "$workspace" "${FM_FAKE_HERDR_PANE_PATH:-/tmp}"
    ;;
  'pane read')
    [ "${FM_FAKE_HERDR_PANE_ALIVE:-1}" = 1 ] || exit 1
    [ -n "$capture" ] && cat "$capture" 2>/dev/null
    ;;
  'pane send-text')
    [ "${FM_FAKE_HERDR_SEND_FAIL:-0}" != 1 ] || exit 1
    text=${4:-}
    printf '%s\n' "$text" >> "$sent"
    write_composer "$text"
    ;;
  'pane send-keys')
    key=${4:-}
    case "$key" in
      enter)
        if [ -n "${FM_FAKE_HERDR_SWALLOW_FILE:-}" ] && [ -f "$FM_FAKE_HERDR_SWALLOW_FILE" ]; then
          [ "${FM_FAKE_PERSIST_SWALLOW:-0}" = 1 ] || rm -f "$FM_FAKE_HERDR_SWALLOW_FILE"
        else
          printf '[ENTER]\n' >> "$sent"
          write_composer ""
        fi
        ;;
      *) printf '[%s]\n' "$key" >> "$sent" ;;
    esac
    ;;
  'pane run')
    printf '%s\n' "${4:-}" >> "$sent"
    ;;
  'pane close')
    printf '[CLOSE]\n' >> "$sent"
    ;;
  'agent get')
    case "${FM_FAKE_HERDR_AGENT_STATUS:-working}" in
      missing) exit 1 ;;
      none) printf '{"error":{"code":"agent_not_found"}}\n' ;;
      status:*) printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "${FM_FAKE_HERDR_AGENT_STATUS#status:}" ;;
      *) printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$FM_FAKE_HERDR_AGENT_STATUS" ;;
    esac
    ;;
  'workspace list')
    printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"}]}}\n'
    ;;
  'tab list')
    printf '{"result":{"tabs":[]}}\n'
    ;;
  'pane list')
    printf '{"result":{"panes":[]}}\n'
    ;;
  *) exit 0 ;;
esac
SH
  sed "s/__FM_FAKE_MODE__/$mode/" "$fakebin/herdr" > "$fakebin/herdr.tmp"
  mv "$fakebin/herdr.tmp" "$fakebin/herdr"
  chmod +x "$fakebin/herdr"
}

make_case() {
  local name=$1 dir fakebin
  dir="$TMP_ROOT/$name"
  fakebin="$dir/fakebin"
  mkdir -p "$dir/state" "$fakebin"
  write_fake_herdr "$fakebin" plain
  make_fake_crew_state "$fakebin" >/dev/null
  printf '%s\n' "$dir"
}

# Install a hermetic fake fm-crew-state.sh into <fakebin> and echo its path.
make_fake_crew_state() {  # <fakebin>
  local fakebin=$1
  cat > "$fakebin/fm-crew-state.sh" <<'SH'
#!/usr/bin/env bash
set -u
id=${1:-}
key=$(printf '%s' "$id" | tr -c 'A-Za-z0-9' '_')
var="FM_FAKE_CREW_STATE_$key"
val=${!var:-${FM_FAKE_CREW_STATE:-}}
printf '%s\n' "${val:-state: unknown · source: none · fake default}"
exit 0
SH
  chmod +x "$fakebin/fm-crew-state.sh"
  printf '%s\n' "$fakebin/fm-crew-state.sh"
}

make_supercase() {
  local name=$1 dir fakebin
  dir="$TMP_ROOT/$name"
  fakebin="$dir/fakebin"
  mkdir -p "$dir/state" "$fakebin"
  write_fake_herdr "$fakebin" plain
  printf '%s\n' "$dir"
}

make_bordered_case() {
  local name=$1 dir fakebin
  dir="$TMP_ROOT/$name"
  fakebin="$dir/fakebin"
  mkdir -p "$dir/state" "$fakebin"
  printf '╭─────╮\n│ >   │\n╰─────╯\n' > "$dir/composer"
  write_fake_herdr "$fakebin" bordered
  printf '%s\n' "$dir"
}

wait_for_exit() {
  local pid=$1 limit=${2:-50} i=0
  while [ "$i" -lt "$limit" ]; do
    if ! is_live_non_zombie "$pid"; then
      wait "$pid"
      return "$?"
    fi
    sleep 0.1
    i=$((i + 1))
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 124
}

is_live_non_zombie() {
  local pid=$1 stat
  kill -0 "$pid" 2>/dev/null || return 1
  stat=$(ps -p "$pid" -o stat= 2>/dev/null || true)
  case "$stat" in
    Z*) return 1 ;;
  esac
  return 0
}

hash_text() {
  if command -v md5 >/dev/null 2>&1; then
    printf '%s' "$1" | md5 -q
  else
    printf '%s' "$1" | md5sum | cut -d' ' -f1
  fi
}

dead_pid() {
  local p=999999
  while kill -0 "$p" 2>/dev/null; do
    p=$((p + 1))
  done
  printf '%s\n' "$p"
}
