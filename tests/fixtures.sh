#!/usr/bin/env bash
# tests/fixtures.sh - shared fake-toolchain and spawn-world builders.
#
# Source this from a test file:
#   # shellcheck source=tests/fixtures.sh
#   . "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"
#
# Generic reporters, temp roots, git fixtures, and fail/pass/fm_test_cleanup
# come from tests/lib.sh, pulled in below. This file owns the shared fake
# no-mistakes, gh, gh-axi, Herdr, ssh, and spawn-world helpers. Wake-queue mocks
# stay in wake-helpers.sh; secondmate-lifecycle mocks stay in
# secondmate-helpers.sh.
#
# FM_TEST_NO_MISTAKES_VERSION is the single default version for the shared fake
# no-mistakes banner. Override a single case with FM_FAKE_NO_MISTAKES_VERSION
# rather than editing a stub body.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ -n "${FM_TEST_FIXTURES_SOURCED:-}" ]; then
  return 0
fi
FM_TEST_FIXTURES_SOURCED=1

# Production floor lives in bin/fm-bootstrap.sh (NO_MISTAKES_MIN). Keep this
# equal to that floor so a bump is one constant here plus that production pin.
export FM_TEST_NO_MISTAKES_VERSION=1.46.0
export FM_TEST_NO_MISTAKES_FAKE_VERSION="no-mistakes version v${FM_TEST_NO_MISTAKES_VERSION} (fake)"
export FM_TEST_NO_MISTAKES_FAKE_VERSION_TS="${FM_TEST_NO_MISTAKES_FAKE_VERSION} 2026-06-27T00:02:18Z"
export FM_TEST_GH_AXI_VERSION=0.1.29

# --- fake no-mistakes -------------------------------------------------------

# fm_test_fake_no_mistakes <fakebin>
# Drops a no-mistakes stub that answers --version with
# FM_TEST_NO_MISTAKES_FAKE_VERSION (or FM_FAKE_NO_MISTAKES_VERSION when set)
# and exits 0 for every other invocation.
fm_test_fake_no_mistakes() {
  local fakebin=$1
  cat > "$fakebin/no-mistakes" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = --version ]; then
  printf '%s\\n' "\${FM_FAKE_NO_MISTAKES_VERSION:-$FM_TEST_NO_MISTAKES_FAKE_VERSION}"
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/no-mistakes"
}

# fm_test_fake_no_mistakes_init_doctor <fakebin>
# Secondmate-lifecycle stub: init/doctor touch marker files; other verbs exit 2.
# Does not answer --version (those suites never probe the floor).
fm_test_fake_no_mistakes_init_doctor() {
  local fakebin=$1
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -eu
case "${1:-}" in
  init) touch .no-mistakes-init ;;
  doctor) touch .no-mistakes-doctor ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fakebin/no-mistakes"
}

# --- fake gh / gh-axi -------------------------------------------------------

# fm_test_fake_gh <fakebin>
# Authenticates (`gh auth status` exits 0) and otherwise exits 0.
fm_test_fake_gh() {
  local fakebin=$1
  cat > "$fakebin/gh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/gh"
}

# fm_test_fake_gh_axi <fakebin>
# Answers --version with FM_FAKE_GH_AXI_VERSION or FM_TEST_GH_AXI_VERSION.
fm_test_fake_gh_axi() {
  local fakebin=$1
  fm_fake_version_tool "$fakebin" gh-axi FM_FAKE_GH_AXI_VERSION "$FM_TEST_GH_AXI_VERSION"
}

# --- fake Herdr / ssh / sleep -----------------------------------------------

# fm_test_fake_herdr <fakebin>
# Stateful-enough Herdr boundary for shared spawn and send fixtures.
fm_test_fake_herdr() {
  local fakebin=$1
  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
D=$(cd "$(dirname "$0")" && pwd)
S=${FM_FAKE_DIR:-$D}
[ -z "${FM_FAKE_HERDR_LOG:-}" ] || printf 'call %s\n' "$*" >> "$FM_FAKE_HERDR_LOG"
if [ -n "${FM_FAKE_HERDR_REQUIRE_SESSION:-}" ]; then
  requested_session=
  previous=
  for argument in "$@"; do
    [ "$previous" != --session ] || requested_session=$argument
    previous=$argument
  done
  case "${1:-} ${2:-}" in
    "status --json"|"session list") ;;
    *)
      if [ "$requested_session" != "$FM_FAKE_HERDR_REQUIRE_SESSION" ]; then
        printf 'rejected-session=%s\n' "${requested_session:-unscoped}" >> "$FM_FAKE_HERDR_LOG"
        exit 64
      fi
      ;;
  esac
fi
case "${1:-} ${2:-}" in
  "status --json") printf '%s\n' '{"client":{"protocol":14,"version":"0.12.3"},"server":{"running":true,"protocol":14,"version":"0.12.3"}}' ;;
  "session list")
    if [ -n "${FM_FAKE_HERDR_REQUIRE_SESSION:-}" ]; then
      printf '{"sessions":[{"name":"%s","running":true,"socket_path":"%s"}]}\n' \
        "$FM_FAKE_HERDR_REQUIRE_SESSION" "${FM_FAKE_HERDR_SOCKET:?}"
    else
      printf '%s\n' '{"sessions":[{"name":"default","running":true,"socket_path":"/tmp/fake-herdr.sock"},{"name":"lab","running":true,"socket_path":"/tmp/fake-herdr-lab.sock"}]}'
    fi
    ;;
  "workspace list")
    if [ -e "$D/herdr-workspace-created" ]; then
      printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"Firstmate","focused":true,"active_tab_id":"w1:t1"},{"workspace_id":"w2","label":"%s","focused":false,"active_tab_id":"w2:t1"}]}}\n' "${FM_FAKE_HERDR_WORKSPACE_LABEL:-2ndmate}"
    else
      printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"Firstmate","focused":true,"active_tab_id":"w1:t1"}]}}'
    fi
    ;;
  "workspace create") touch "$D/herdr-workspace-created"; printf '{"result":{"workspace":{"workspace_id":"w2","label":"%s","active_tab_id":"w2:t1"},"tab":{"tab_id":"w2:t1","workspace_id":"w2","label":"1"},"root_pane":{"pane_id":"w2:p1","tab_id":"w2:t1","workspace_id":"w2"}}}\n' "${FM_FAKE_HERDR_WORKSPACE_LABEL:-2ndmate}" ;;
  "workspace get")
    workspace=${3:-w1}
    label=Firstmate
    [ "$workspace" = w1 ] || label=${FM_FAKE_HERDR_WORKSPACE_LABEL:-2ndmate}
    printf '{"result":{"workspace":{"workspace_id":"%s","label":"%s","focused":true,"active_tab_id":"%s:t1"}}}\n' "$workspace" "$label" "$workspace"
    ;;
  "tab list")
    workspace=w1
    prev=
    for arg in "$@"; do [ "$prev" != --workspace ] || workspace=$arg; prev=$arg; done
    created_workspace=$(cat "$D/herdr-tab-created-workspace" 2>/dev/null)
    seeded_closed_workspace=$(cat "$D/herdr-seeded-pane-closed" 2>/dev/null)
    if { [ -e "$D/herdr-tab-closed" ] || [ "$seeded_closed_workspace" = "$workspace" ]; } \
      && [ -e "$D/herdr-tab-created" ] && [ "$created_workspace" = "$workspace" ]; then
      label=$(cat "$D/herdr-tab-created")
      printf '{"result":{"tabs":[{"tab_id":"%s:t2","workspace_id":"%s","label":"%s","focused":true}]}}\n' \
        "$workspace" "$workspace" "$label"
      exit 0
    fi
    seeded_label=captain
    [ "$workspace" = w1 ] || seeded_label=1
    printf '{"result":{"tabs":[{"tab_id":"%s:t1","workspace_id":"%s","label":"%s","focused":true}' \
      "$workspace" "$workspace" "$seeded_label"
    if { [ -e "$D/herdr-tab-created" ] && [ "$created_workspace" = "$workspace" ]; } \
      || [ "${FM_FAKE_HERDR_DUPLICATE:-0}" = 1 ]; then
      task_id=${FM_FAKE_HERDR_TASK_ID:-}
      case "$workspace" in
        w2) task_id=${FM_FAKE_HERDR_TASK_ID_W2:-$task_id} ;;
        w3) task_id=${FM_FAKE_HERDR_TASK_ID_W3:-$task_id} ;;
      esac
      task_label=${task_id:+fm-$task_id}
      [ -n "$task_label" ] || task_label=$(cat "$D/herdr-tab-created" 2>/dev/null)
      [ -n "$task_label" ] || task_label=fm-task
      printf ',{"tab_id":"%s:t2","workspace_id":"%s","label":"%s","focused":false}' "$workspace" "$workspace" "$task_label"
    else
      state_dir=${FM_STATE_OVERRIDE:-}
      [ -n "$state_dir" ] || [ -z "${FM_HOME:-}" ] || state_dir="$FM_HOME/state"
      if [ ! -e "$D/herdr-tab-closed" ] && [ -n "$state_dir" ]; then
      for meta in "$state_dir"/*.meta; do
        [ -f "$meta" ] || continue
        tab=$(sed -n 's/^herdr_tab_id=//p' "$meta" | tail -1)
        id=$(basename "$meta" .meta)
        case "$tab" in "$workspace":*) printf ',{"tab_id":"%s","workspace_id":"%s","label":"fm-%s","focused":false}' "$tab" "$workspace" "$id" ;; esac
        child_home=$(sed -n 's/^home=//p' "$meta" | tail -1)
        [ -d "$child_home/state" ] || continue
        [ "$(cd "$child_home/state" 2>/dev/null && pwd -P)" != "$(cd "$state_dir" 2>/dev/null && pwd -P)" ] || continue
        for child_meta in "$child_home/state"/*.meta; do
          [ -f "$child_meta" ] || continue
          child_tab=$(sed -n 's/^herdr_tab_id=//p' "$child_meta" | tail -1)
          child_id=$(basename "$child_meta" .meta)
          case "$child_tab" in "$workspace":*) printf ',{"tab_id":"%s","workspace_id":"%s","label":"fm-%s","focused":false}' "$child_tab" "$workspace" "$child_id" ;; esac
        done
      done
      fi
    fi
    printf ']}}\n'
    ;;
  "tab create")
    workspace=w1
    label=
    prev=
    for arg in "$@"; do
      [ "$prev" != --workspace ] || workspace=$arg
      [ "$prev" != --label ] || label=$arg
      prev=$arg
    done
    rm -f "$D/herdr-tab-closed" "$D/herdr-pane-closed"
    printf '%s\n' "$label" > "$D/herdr-tab-created"
    printf '%s\n' "$workspace" > "$D/herdr-tab-created-workspace"
    printf '{"result":{"tab":{"tab_id":"%s:t2","workspace_id":"%s"},"root_pane":{"pane_id":"%s:p2","tab_id":"%s:t2","workspace_id":"%s"}}}\n' "$workspace" "$workspace" "$workspace" "$workspace" "$workspace"
    ;;
  "tab get")
    tab=${3:-w1:t2}
    workspace=${tab%%:*}
    label=${FM_FAKE_HERDR_TASK_ID:+fm-$FM_FAKE_HERDR_TASK_ID}
    [ -n "$label" ] || label=$(cat "$D/herdr-tab-created" 2>/dev/null)
    state_dir=${FM_STATE_OVERRIDE:-}
    [ -n "$state_dir" ] || [ -z "${FM_HOME:-}" ] || state_dir="$FM_HOME/state"
    if [ -z "$label" ] && [ -n "$state_dir" ]; then
      for meta in "$state_dir"/*.meta; do
        [ -f "$meta" ] || continue
        [ "$(sed -n 's/^herdr_tab_id=//p' "$meta" | tail -1)" = "$tab" ] || continue
        label="fm-$(basename "$meta" .meta)"
        break
      done
    fi
    [ -n "$label" ] || label=fm-task
    case "$tab" in *:t1) label=captain ;; esac
    printf '{"result":{"tab":{"tab_id":"%s","workspace_id":"%s","label":"%s"}}}\n' "$tab" "$workspace" "$label"
    ;;
  "pane list")
    workspace=w1
    prev=
    for arg in "$@"; do [ "$prev" != --workspace ] || workspace=$arg; prev=$arg; done
    created_workspace=$(cat "$D/herdr-tab-created-workspace" 2>/dev/null)
    seeded_closed_workspace=$(cat "$D/herdr-seeded-pane-closed" 2>/dev/null)
    if [ -e "$D/herdr-tab-created" ] && [ "$created_workspace" = "$workspace" ] \
      && [ "$seeded_closed_workspace" != "$workspace" ]; then
      printf '{"result":{"panes":[{"pane_id":"%s:p1","tab_id":"%s:t1","workspace_id":"%s"},{"pane_id":"%s:p2","tab_id":"%s:t2","workspace_id":"%s"}]}}\n' \
        "$workspace" "$workspace" "$workspace" "$workspace" "$workspace" "$workspace"
    elif [ -e "$D/herdr-tab-created" ] && [ "$created_workspace" = "$workspace" ]; then
      printf '{"result":{"panes":[{"pane_id":"%s:p2","tab_id":"%s:t2","workspace_id":"%s"}]}}\n' \
        "$workspace" "$workspace" "$workspace"
    else
      printf '{"result":{"panes":[{"pane_id":"%s:p1","tab_id":"%s:t1","workspace_id":"%s"}]}}\n' \
        "$workspace" "$workspace" "$workspace"
    fi
    ;;
  "pane get")
    seeded_closed_workspace=$(cat "$D/herdr-seeded-pane-closed" 2>/dev/null)
    if [ -e "$D/herdr-pane-closed" ] || { case "${3:-}" in *:p1) [ "$seeded_closed_workspace" = "${3%%:*}" ] ;; *) false ;; esac; }; then
      printf '%s\n' '{"error":{"code":"pane_not_found"}}'
      [ -z "${FM_FAKE_HERDR_REQUIRE_SESSION:-}" ] || printf '%s\n' pane-not-found >> "$FM_FAKE_HERDR_LOG"
      exit 1
    fi
    pane=${3:-w1:p2}
    workspace=${pane%%:*}
    tab="$workspace:t2"
    case "$pane" in *:p1) tab="$workspace:t1" ;; esac
    state_dir=${FM_STATE_OVERRIDE:-}
    [ -n "$state_dir" ] || [ -z "${FM_HOME:-}" ] || state_dir="$FM_HOME/state"
    if [ -n "$state_dir" ]; then
      for meta in "$state_dir"/*.meta; do
        [ -f "$meta" ] || continue
        [ "$(sed -n 's/^herdr_pane_id=//p' "$meta" | tail -1)" = "$pane" ] || continue
        tab=$(sed -n 's/^herdr_tab_id=//p' "$meta" | tail -1)
        if [ "$(sed -n 's/^fixture_herdr_presence=//p' "$meta" | tail -1)" = dead ]; then
          printf '%s\n' '{"error":{"code":"pane_not_found"}}'
          exit 1
        fi
        break
      done
    fi
    path=${FM_FAKE_PANE_PATH:-}
    [ -n "$path" ] || [ ! -f "$S/cwd" ] || path=$(cat "$S/cwd")
    if [ -n "${FM_FAKE_PANE_COUNTFILE:-}" ]; then
      n=0
      [ -f "$FM_FAKE_PANE_COUNTFILE" ] && n=$(cat "$FM_FAKE_PANE_COUNTFILE")
      n=$((n + 1))
      printf '%s\n' "$n" > "$FM_FAKE_PANE_COUNTFILE"
      if [ "$n" -le "${FM_FAKE_PANE_STALE_READS:-0}" ]; then
        path=${FM_FAKE_PANE_STALE:-}
      fi
    fi
    printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s","workspace_id":"%s","foreground_cwd":"%s"}}}\n' "$pane" "$tab" "$workspace" "$path"
    ;;
  "pane read")
    pane=${3:-w1:p2}
    state_dir=${FM_STATE_OVERRIDE:-}
    [ -n "$state_dir" ] || [ -z "${FM_HOME:-}" ] || state_dir="$FM_HOME/state"
    task_id=
    if [ -n "$state_dir" ]; then
      for meta in "$state_dir"/*.meta; do
        [ -f "$meta" ] || continue
        [ "$(sed -n 's/^herdr_pane_id=//p' "$meta" | tail -1)" = "$pane" ] || continue
        task_id=$(basename "$meta" .meta)
        break
      done
    fi
    ticks=${FM_FAKE_HERDR_TICKS:-${FM_FAKE_TMUX_TICKS:-}}
    if [ -n "$ticks" ]; then
      n=$(( $(cat "$ticks" 2>/dev/null || echo 0) + 1 ))
      printf '%s\n' "$n" > "$ticks"
      printf 'Working... (%d.%ds) lavish-axi poll' "$((7200 + n))" "$((n % 10))"
    elif [ -n "$task_id" ] && [ -f "$D/herdr-capture-$task_id" ]; then
      cat "$D/herdr-capture-$task_id"
    elif [ -n "${FM_FAKE_HERDR_CAPTURE:-${FM_FAKE_TMUX_CAPTURE:-}}" ] \
      && [ -f "${FM_FAKE_HERDR_CAPTURE:-$FM_FAKE_TMUX_CAPTURE}" ]; then
      cat "${FM_FAKE_HERDR_CAPTURE:-$FM_FAKE_TMUX_CAPTURE}"
    elif [ -f "$S/pane" ]; then
      cat "$S/pane"
    elif [ "${FM_FAKE_HERDR_COMPOSER:-}" = pending ]; then
      printf '╭──────────────╮\n│ leftover txt │\n╰──────────────╯\n'
    else
      printf '╭────╮\n│    │\n╰────╯\n'
    fi
    ;;
  "pane send-text")
    [ "${FM_FAKE_HERDR_SEND_FAIL:-0}" = 1 ] && exit 1
    payload=${4:-}
    [ -n "${FM_FAKE_LAUNCH_LOG:-}" ] && printf '%s\n' "$payload" >> "$FM_FAKE_LAUNCH_LOG"
    printf '%s\n' "$payload" >> "${FM_SEND_LOG:-/dev/null}"
    [ ! -f "$S/literal" ] || printf '%s\n' "$payload" >> "$S/literal"
    if [ -n "${FM_ACK_RECORD:-}" ] && [ -f "$FM_ACK_RECORD" ]; then
      mkdir -p "${FM_ACK_RECORD%/*}/handled"
      mv "$FM_ACK_RECORD" "${FM_ACK_RECORD%/*}/handled/"
    fi
    if [ -z "${FM_FAKE_NEVER_DIES:-}" ] && [ "$payload" = /quit ] && [ -f "$S/command" ]; then
      printf zsh > "$S/command"
    fi
    ;;
  "pane run")
    case "${4:-}" in
      'export TRACEPARENT='*)
        if [ "${FM_FAKE_TRACEPARENT_SEND_UNSAFE:-0}" = 1 ]; then exit 2; fi
        if [ "${FM_FAKE_TRACEPARENT_SEND_FAIL:-0}" = 1 ]; then exit 1; fi
        if [ "${FM_FAKE_TRACE_METADATA_APPEND_FAIL:-0}" = 1 ] && [ -n "${FM_FAKE_META_PATH:-}" ]; then
          chmod a-w "$FM_FAKE_META_PATH"
        fi
        ;;
    esac
    [ -n "${FM_FAKE_LAUNCH_LOG:-}" ] && printf '%s\n' "${4:-}" >> "$FM_FAKE_LAUNCH_LOG"
    ;;
  "pane close")
    pane=${3:-}
    case "$pane" in
      *:p1) printf '%s\n' "${pane%%:*}" > "$D/herdr-seeded-pane-closed" ;;
      *) touch "$D/herdr-pane-closed" ;;
    esac
    ;;
  "pane send-keys")
    key=${4:-}
    [ ! -f "$S/keys" ] || printf '%s\n' "$key" >> "$S/keys"
    if [ -n "${FM_FAKE_INTERRUPT_STOPS_AGENT:-}" ] && { [ "$key" = escape ] || [ "$key" = ctrl-c ]; } && [ -f "$S/command" ]; then
      printf zsh > "$S/command"
    fi
    ;;
  "tab focus"|"workspace focus") ;;
  "tab close")
    tab=
    prev=
    for arg in "$@"; do
      [ "$prev" != --tab ] || tab=$arg
      prev=$arg
    done
    [ -n "$tab" ] || tab=${3:-}
    case "$tab" in
      *:t1) touch "$D/herdr-tab-closed" ;;
      *) rm -f "$D/herdr-tab-created" "$D/herdr-tab-created-workspace"; touch "$D/herdr-tab-closed" ;;
    esac
    ;;
  "agent get")
    command=
    [ ! -f "$S/command" ] || command=$(cat "$S/command")
    pane=${3:-w1:p2}
    state_dir=${FM_STATE_OVERRIDE:-}
    [ -n "$state_dir" ] || [ -z "${FM_HOME:-}" ] || state_dir="$FM_HOME/state"
    fixture_agent=
    if [ -n "$state_dir" ]; then
      for meta in "$state_dir"/*.meta; do
        [ -f "$meta" ] || continue
        [ "$(sed -n 's/^herdr_pane_id=//p' "$meta" | tail -1)" = "$pane" ] || continue
        fixture_agent=$(sed -n 's/^fixture_herdr_agent=//p' "$meta" | tail -1)
        break
      done
    fi
    if [ "${FM_FAKE_HERDR_AGENT_MISSING:-0}" = 1 ] || [ "$fixture_agent" = missing ] || [ "$command" = zsh ]; then
      printf '%s\n' '{"error":{"code":"agent_not_found"}}'
    elif [ -n "$command" ] && [ "$command" != pi ]; then
      printf '%s\n' '{"result":{"agent":{"agent_status":"unknown"}}}'
    else
      printf '{"result":{"agent":{"agent_status":"%s"}}}\n' \
        "${fixture_agent:-${FM_FAKE_HERDR_AGENT_STATUS:-idle}}"
    fi
    ;;
  *) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/herdr"
}

# fm_test_assert_fake_herdr <fakebin>
# Refuses a lifecycle fixture before any production command can fall through to
# the operator's real Herdr binary.
fm_test_assert_fake_herdr() {
  local fakebin=$1 resolved
  resolved=$(PATH="$fakebin:$PATH" command -v herdr 2>/dev/null || true)
  [ "$resolved" = "$fakebin/herdr" ] || {
    printf 'test fixture error: expected isolated Herdr at %s/herdr, resolved %s\n' \
      "$fakebin" "${resolved:-<absent>}" >&2
    return 1
  }
}

# fm_test_fake_ssh <fakebin> [name]
# Records argv to FM_SSH_LOG, consumes stdin, exits FM_FAKE_SSH_RC (default 0).
# Default name is fake-ssh so tests can point FM_SSH_BIN at it without
# shadowing a real ssh on PATH.
fm_test_fake_ssh() {
  local fakebin=$1 name=${2:-fake-ssh}
  cat > "$fakebin/$name" <<'SH'
#!/usr/bin/env bash
cat > /dev/null
printf '%s\n' "$*" >> "${FM_SSH_LOG:-/dev/null}"
exit "${FM_FAKE_SSH_RC:-0}"
SH
  chmod +x "$fakebin/$name"
}

# fm_test_fake_sleep_noop <fakebin>
fm_test_fake_sleep_noop() {
  local fakebin=$1
  cat > "$fakebin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin/sleep"
}

# fm_test_fake_sleep_log <fakebin>
# Records each requested duration to FM_SLEEP_LOG instead of sleeping.
fm_test_fake_sleep_log() {
  local fakebin=$1
  cat > "$fakebin/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >> "${FM_SLEEP_LOG:-/dev/null}"
exit 0
SH
  chmod +x "$fakebin/sleep"
}

# --- spawn-world ------------------------------------------------------------

# fm_test_spawn_home <home> [harness]
# Minimal firstmate home layout plus watcher-liveness beat. Optional harness
# pin is written to config/crew-harness.
fm_test_spawn_home() {
  local home=$1 harness=${2-}
  mkdir -p "$home/data" "$home/projects" "$home/state" "$home/config"
  printf 'off\n' > "$home/config/herdr-presentation-spaces"
  touch "$home/state/.last-watcher-beat"
  if [ -n "$harness" ]; then
    printf '%s\n' "$harness" > "$home/config/crew-harness"
  fi
}

# fm_test_spawn_brief <home> <id> [text]
fm_test_spawn_brief() {
  local home=$1 id=$2 text=${3:-brief for $2}
  mkdir -p "$home/data/$id"
  printf '%s\n' "$text" > "$home/data/$id/brief.md"
}

# fm_test_make_spawn_fakebin <dir> [extra-exit0-tool...]
# Creates <dir>/fakebin with the Herdr stub, a no-op Treehouse, and any
# extra exit-0 tools. Echoes the fakebin path.
fm_test_make_spawn_fakebin() {
  local dir=$1 fakebin
  shift
  fakebin=$(fm_fakebin "$dir")
  fm_test_fake_herdr "$fakebin"
  fm_fake_exit0 "$fakebin" treehouse "$@"
  printf '%s\n' "$fakebin"
}

# Drop-in name used by the spawn suites. Extra args are additional exit-0 tools
# (gh, gh-axi, pi, ...).
make_spawn_fakebin() {
  fm_test_make_spawn_fakebin "$@"
}

# fm_test_run_spawn <home> <pane-path> <fakebin> [fm-spawn args...]
# Common spawn env. Extra variables in the caller (GROK_HOME, FM_FAKE_LAUNCH_LOG,
# CLAUDE_CONFIG_DIR, ...) are inherited. Does not add --mode/--yolo; ship tests
# that need a delivery contract pass those flags themselves.
fm_test_run_spawn() {
  local home=$1 pane=$2 fakebin=$3 task
  shift 3
  task=${1:-task}
  fm_test_assert_fake_herdr "$fakebin" || return 1
  FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$pane" FM_FAKE_HERDR_TASK_ID="$task" FM_BACKEND=herdr \
    HERDR_ENV=1 HERDR_SESSION=default HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 HERDR_PANE_ID=w1:p1 \
    HERDR_SOCKET_PATH=/tmp/fake-herdr.sock PATH="$fakebin:$PATH" \
    "$ROOT/bin/fm-spawn.sh" "$@" 2>&1
}

# --- send-world stubs -------------------------------------------------------

# make_stubs <dir>
# Send-world fakebin: Herdr plus no-op sleep. Echoes the fakebin path.
# Suites that need recording sleep, herdr, or ssh add those on top of this
# fakebin (or replace sleep via fm_test_fake_sleep_log).
make_stubs() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  fm_test_fake_herdr "$fakebin"
  fm_test_fake_sleep_noop "$fakebin"
  printf '%s\n' "$fakebin"
}
