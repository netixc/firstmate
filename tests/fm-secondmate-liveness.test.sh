#!/usr/bin/env bash
# Herdr-only secondmate agent-liveness and session-start recovery regressions.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-secondmate-liveness)
BASE_PATH=$PATH

test_agent_alive_maps_herdr_state() {
  local state out
  for state in dead no-agent live unknown; do
    out=$(PANE_STATE="$state" bash -c '
      . "$1/bin/fm-backend.sh"
      fm_backend_herdr_pane_agent_state() { printf "%s" "$PANE_STATE"; }
      fm_backend_agent_alive "lab:w1:p1"
    ' _ "$ROOT")
    case "$state:$out" in
      dead:dead|no-agent:dead|live:alive|unknown:unknown) ;;
      *) fail "Herdr state '$state' mapped to unexpected liveness '$out'" ;;
    esac
  done
  out=$(bash -c '. "$1/bin/fm-backend.sh"; fm_backend_agent_alive malformed' _ "$ROOT")
  [ "$out" = unknown ] || fail "malformed Herdr target should be unknown, got '$out'"
  pass "Herdr agent liveness maps dead/no-agent/live/unknown conservatively"
}

make_bootstrap_tools() {  # <world>
  local world=$1 fakebin="$1/fakebin"
  mkdir -p "$fakebin"
  fm_fake_exit0 "$fakebin" node chrome-devtools-axi lavish-axi quota-axi
  cat > "$fakebin/gh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "$fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "$fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "get --help") printf '%s\n' 'Usage: treehouse get [--lease]' ;;
esac
exit 0
SH
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != --version ] || printf '%s\n' 'no-mistakes version v1.31.2 (fake)'
exit 0
SH
  cat > "$fakebin/tasks-axi" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "--version ") printf '%s\n' '0.1.1' ;;
  "update --help") printf '%s\n' 'usage: tasks-axi update <id> --archive-body' ;;
  "mv --help") printf '%s\n' 'usage: tasks-axi mv <id> [<id>...] --to <path-or-dir>' ;;
esac
exit 0
SH
  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${FM_HERDR_CALL_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"protocol":16,"version":"test"},"server":{"running":true}}\n' ;;
  "pane get")
    case "${FM_TEST_AGENT_STATE:-live}" in
      dead) printf '{"error":{"code":"pane_not_found"}}\n' >&2; exit 1 ;;
      unknown) printf '{"error":{"code":"transport_error"}}\n' >&2; exit 1 ;;
      *) printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "${3:-}" ;;
    esac
    ;;
  "agent get")
    case "${FM_TEST_AGENT_STATE:-live}" in
      no-agent) printf '{"error":{"code":"agent_not_found"}}\n' >&2; exit 1 ;;
      *) printf '{"result":{"agent":{"agent_status":"idle"}}}\n' ;;
    esac
    ;;
  "pane close") ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$fakebin"/*
  printf '%s\n' "$fakebin"
}

make_bootstrap_world() {  # <name> <harness>
  local harness=${2:-claude} world="$TMP_ROOT/$1" home="$TMP_ROOT/$1/home" sm="$TMP_ROOT/$1/sm1"
  mkdir -p "$world/root/bin" "$home/state" "$home/data" "$home/config" \
    "$sm/bin" "$sm/data" "$sm/state" "$sm/config" "$sm/projects"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf 'sm1\n' > "$sm/.fm-secondmate-home"
  printf 'charter\n' > "$sm/data/charter.md"
  fm_write_meta "$home/state/sm1.meta" \
    "window=default:w1:p1" "kind=secondmate" "harness=$harness" "home=$sm"
  cat > "$world/root/bin/fm-spawn.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FM_SPAWN_CALL_LOG:?}"
exit "${FM_SPAWN_EXIT:-0}"
SH
  chmod +x "$world/root/bin/fm-spawn.sh"
  printf '%s\n' "$world"
}

run_bootstrap() {  # <world> <agent-state> [harness]
  local world=$1 agent_state=$2 harness=${3:-claude} home="$1/home" fakebin log spawn_log
  fakebin=$(make_bootstrap_tools "$world")
  log="$world/herdr.log"; spawn_log="$world/spawn.log"
  : > "$log"; : > "$spawn_log"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$world/root" PATH="$fakebin:$BASE_PATH" \
    FM_TEST_AGENT_STATE="$agent_state" FM_HERDR_CALL_LOG="$log" FM_SPAWN_CALL_LOG="$spawn_log" \
    "$ROOT/bin/fm-bootstrap.sh" 2>&1
}

test_sweep_respawns_only_confident_dead() {
  local world out calls
  world=$(make_bootstrap_world dead)
  out=$(run_bootstrap "$world" dead)
  calls=$(cat "$world/herdr.log")
  assert_contains "$calls" "pane close w1:p1" "confirmed-dead endpoint was not closed before respawn"
  assert_contains "$(cat "$world/spawn.log")" "sm1 --secondmate" "confirmed-dead secondmate was not respawned"
  assert_not_contains "$out" "SECONDMATE_LIVENESS:" "successful respawn should stay silent"

  world=$(make_bootstrap_world alive)
  out=$(run_bootstrap "$world" live)
  [ ! -s "$world/spawn.log" ] || fail "live secondmate was respawned"
  assert_not_contains "$(cat "$world/herdr.log")" "pane close" "live secondmate endpoint was closed"

  world=$(make_bootstrap_world unknown)
  out=$(run_bootstrap "$world" unknown)
  assert_contains "$out" "SECONDMATE_LIVENESS: secondmate sm1: skipped: Herdr liveness probe inconclusive" \
    "inconclusive Herdr liveness was not surfaced"
  [ ! -s "$world/spawn.log" ] || fail "inconclusive secondmate was respawned"
  assert_not_contains "$(cat "$world/herdr.log")" "pane close" "inconclusive endpoint was closed"
  pass "session-start sweep respawns only a confidently dead Herdr secondmate"
}

test_unverified_harness_never_authorizes_respawn() {
  local world out
  world=$(make_bootstrap_world unverified custom-agent)
  out=$(run_bootstrap "$world" dead custom-agent)
  assert_contains "$out" "SECONDMATE_LIVENESS: secondmate sm1: skipped: Herdr liveness probe inconclusive" \
    "unverified harness did not force an inconclusive verdict"
  [ ! -s "$world/spawn.log" ] || fail "unverified harness authorized respawn"
  assert_not_contains "$(cat "$world/herdr.log")" "pane close" "unverified harness authorized endpoint cleanup"
  pass "an unverified runtime harness cannot turn a dead-looking pane into respawn authority"
}

test_detect_only_skips_liveness_mutation() {
  local world fakebin out
  world=$(make_bootstrap_world detect-only)
  fakebin=$(make_bootstrap_tools "$world")
  : > "$world/herdr.log"; : > "$world/spawn.log"
  out=$(FM_HOME="$world/home" FM_ROOT_OVERRIDE="$world/root" PATH="$fakebin:$BASE_PATH" \
    FM_BOOTSTRAP_DETECT_ONLY=1 FM_TEST_AGENT_STATE=dead FM_HERDR_CALL_LOG="$world/herdr.log" \
    FM_SPAWN_CALL_LOG="$world/spawn.log" "$ROOT/bin/fm-bootstrap.sh" 2>&1)
  assert_not_contains "$out" "SECONDMATE_LIVENESS:" "detect-only ran the liveness sweep"
  [ ! -s "$world/spawn.log" ] || fail "detect-only respawned a secondmate"
  assert_not_contains "$(cat "$world/herdr.log")" "pane close" "detect-only closed a Herdr endpoint"
  pass "bootstrap detect-only mode never mutates secondmate lifecycle state"
}

test_agent_alive_maps_herdr_state
test_sweep_respawns_only_confident_dead
test_unverified_harness_never_authorizes_respawn
test_detect_only_skips_liveness_mutation
