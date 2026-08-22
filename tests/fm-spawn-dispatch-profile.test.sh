#!/usr/bin/env bash
# Behavior tests for fm-spawn.sh concrete dispatch profile flags.
#
# These tests drive fm-spawn through meta writing and launch construction with a
# structured Herdr CLI seam and a real isolated git worktree. The fixture
# captures literal `pane send-text` payloads, so assertions pin the
# command firstmate would run without starting any real harness.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/remote-herdr-fixture.sh
. "$ROOT/tests/remote-herdr-fixture.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-dispatch-profile)

make_spawn_pi_probe() {
  local fakebin=$1 tool=$2
  cat > "$fakebin/$tool" <<'SH'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = --help ]; then
  if [ "${FM_FAKE_PI_VERSION:-0.84.0}" = 0.82.0 ]; then
    printf '%s\n' 'Pi 0.82.0' 'Options: --help'
  else
    printf '%s\n' "Pi ${FM_FAKE_PI_VERSION:-0.84.0}" 'Options: --help --tui-mode <mode>'
  fi
fi
exit 0
SH
  chmod +x "$fakebin/$tool"
}

make_spawn_fakebin() {
  local dir=$1 fakebin herdr_root
  fakebin=$(fm_fakebin "$dir")
  herdr_root="$dir/herdr-root"
  install_remote_herdr_fixture "$herdr_root" "$dir/herdr.state" "$dir/herdr.log" \
    "$dir/herdr-send-fail" "$dir/herdr.sock"
  ln -s "$herdr_root/bin/herdr" "$fakebin/herdr"
  fm_fake_exit0 "$fakebin" treehouse
  make_spawn_pi_probe "$fakebin" pi
  make_spawn_pi_probe "$fakebin" pi
  printf '%s\n' "$fakebin"
}

make_spawn_case() {
  local name=$1 _legacy_harness=$2 case_dir home proj wt fakebin launchlog id
  shift 2
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  launchlog="$case_dir/launch.log"
  fakebin=$(make_spawn_fakebin "$case_dir/fake")
  mkdir -p "$home/data" "$home/projects" "$home/state" "$home/config"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  touch "$home/state/.last-watcher-beat"
  for id in "$@"; do
    mkdir -p "$home/data/$id"
    printf 'brief for %s\n' "$id" > "$home/data/$id/brief.md"
  done
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin|$launchlog"
}

enable_dispatch_profile() {
  local home=$1
  printf '%s\n' '{"rules":[{"when":"current events","use":{"model":"xai/grok-4","effort":"high"}}],"default":{"model":"gpt-5","effort":"medium"}}' \
    > "$home/config/crew-dispatch.json"
}

make_seeded_secondmate_home() {
  local home=$1 id=$2
  mkdir -p "$home/bin" "$home/data"
  printf '# Firstmate\n' > "$home/AGENTS.md"
  printf '%s\n' "$id" > "$home/.fm-secondmate-home"
  printf 'charter for %s\n' "$id" > "$home/data/charter.md"
}

run_spawn() {
  local home=$1 wt=$2 fakebin=$3 launchlog=$4
  shift 4
  : > "$launchlog"
  : > "$launchlog.text"
  env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_SOCKET \
    FM_ROOT_OVERRIDE='' FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 HERDR_SESSION=lab FM_FAKE_HERDR_PANE_PATH="$wt" \
    FM_FAKE_HERDR_LAUNCH_LOG="$launchlog" FM_FAKE_PI_VERSION="${FM_TEST_PI_VERSION:-0.84.0}" \
    PATH="$fakebin:$PATH" \
    "$SPAWN" "$@" 2>&1
}

# Ship spawns carry an explicit delivery contract (AGENTS.md section 7); these
# tests are about profile resolution, so they pass a fixed valid one.
run_ship_spawn() {
  run_spawn "$@" --mode no-mistakes --yolo off
}

read_case_record() {
  IFS='|' read -r CASE_DIR HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR LAUNCH_LOG <<EOF
$1
EOF
}

assert_meta_profile() {
  local meta=$1 harness=$2 model=$3 effort=$4
  assert_grep "harness=$harness" "$meta" "meta missing harness=$harness"
  assert_grep "model=$model" "$meta" "meta missing model=$model"
  assert_grep "effort=$effort" "$meta" "meta missing effort=$effort"
}

test_relative_home_overrides_launch_with_absolute_cross_process_paths() {
  local rec id out status launch home_real
  id=profile-relative-paths-z1b
  rec=$(make_spawn_case profile-relative-paths pi "$id")
  read_case_record "$rec"
  home_real=$(cd "$HOME_DIR" && pwd -P)
  mkdir -p "$CASE_DIR/cdpath/home/state" "$CASE_DIR/cdpath/home/data"
  : > "$LAUNCH_LOG"

  out=$(
    cd "$CASE_DIR" || exit 1
    CDPATH="$CASE_DIR/cdpath" FM_ROOT_OVERRIDE='' FM_HOME=home \
      FM_STATE_OVERRIDE=home/state FM_DATA_OVERRIDE=home/data \
      FM_PROJECTS_OVERRIDE=home/projects FM_CONFIG_OVERRIDE=home/config \
      FM_SPAWN_NO_GUARD=1 TMUX='' TMUX_PANE='' HERDR_ENV='' HERDR_PANE_ID='' HERDR_SOCKET_PATH='' HERDR_SESSION=lab FM_FAKE_HERDR_PANE_PATH="$WT_DIR" \
      FM_FAKE_HERDR_LAUNCH_LOG="$LAUNCH_LOG" \
      PATH="$FAKEBIN_DIR:$PATH" \
      "$SPAWN" "$id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1
  )
  status=$?
  expect_code 0 "$status" "spawn with relative home overrides should succeed"
  launch=$(cat "$LAUNCH_LOG")
  assert_contains "$launch" "FM_WORKER_LIFECYCLE_CONTEXT='$home_real/state/$id.meta'" \
    "relative FM_STATE_OVERRIDE leaked into Pi's worker context path"
  assert_contains "$launch" "-e '$ROOT/.pi/worker-extensions/fm-worker-lifecycle.ts'" \
    "Pi did not explicitly load the tracked worker-lifecycle extension"
  assert_contains "$launch" "< '$home_real/data/$id/brief.md'" \
    "relative FM_DATA_OVERRIDE leaked into the cross-process brief path"
  pass "relative home overrides ignore CDPATH and become absolute before spawn launch construction"
}

test_home_defaults_preserve_absolute_or_resolve_relative_paths() {
  local rec relative_id absolute_id out status launch home_real linked_home
  relative_id=profile-relative-home-defaults-z1c
  absolute_id=profile-absolute-home-defaults-z1d
  rec=$(make_spawn_case profile-home-defaults pi "$relative_id" "$absolute_id")
  read_case_record "$rec"
  home_real=$(cd "$HOME_DIR" && pwd -P)

  : > "$LAUNCH_LOG"
  out=$(
    cd "$CASE_DIR" || exit 1
    FM_ROOT_OVERRIDE='' FM_HOME=home \
      FM_STATE_OVERRIDE='' FM_DATA_OVERRIDE='' \
      FM_PROJECTS_OVERRIDE=home/projects FM_CONFIG_OVERRIDE=home/config \
      FM_SPAWN_NO_GUARD=1 TMUX='' TMUX_PANE='' HERDR_ENV='' HERDR_PANE_ID='' HERDR_SOCKET_PATH='' HERDR_SESSION=lab FM_FAKE_HERDR_PANE_PATH="$WT_DIR" \
      FM_FAKE_HERDR_LAUNCH_LOG="$LAUNCH_LOG" \
      PATH="$FAKEBIN_DIR:$PATH" \
      "$SPAWN" "$relative_id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1
  )
  status=$?
  expect_code 0 "$status" "spawn with relative FM_HOME defaults should succeed"
  launch=$(cat "$LAUNCH_LOG")
  assert_contains "$launch" "FM_WORKER_LIFECYCLE_CONTEXT='$home_real/state/$relative_id.meta'" \
    "relative FM_HOME leaked into Pi's default worker context path"
  assert_contains "$launch" "< '$home_real/data/$relative_id/brief.md'" \
    "relative FM_HOME leaked into the default cross-process brief path"

  linked_home="$CASE_DIR/home-link"
  ln -s "$HOME_DIR" "$linked_home"
  : > "$LAUNCH_LOG"
  out=$(
    FM_ROOT_OVERRIDE='' FM_HOME="$linked_home" \
      FM_STATE_OVERRIDE='' FM_DATA_OVERRIDE='' \
      FM_PROJECTS_OVERRIDE="$linked_home/projects" FM_CONFIG_OVERRIDE="$linked_home/config" \
      FM_SPAWN_NO_GUARD=1 TMUX='' TMUX_PANE='' HERDR_ENV='' HERDR_PANE_ID='' HERDR_SOCKET_PATH='' HERDR_SESSION=lab FM_FAKE_HERDR_PANE_PATH="$WT_DIR" \
      FM_FAKE_HERDR_LAUNCH_LOG="$LAUNCH_LOG" \
      PATH="$FAKEBIN_DIR:$PATH" \
      "$SPAWN" "$absolute_id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1
  )
  status=$?
  expect_code 0 "$status" "spawn with absolute symlink-spelled FM_HOME defaults should succeed"
  launch=$(cat "$LAUNCH_LOG")
  assert_contains "$launch" "FM_WORKER_LIFECYCLE_CONTEXT='$home_real/state/$absolute_id.meta'" \
    "Pi's worker context path did not canonicalize an absolute symlink-spelled home"
  assert_contains "$launch" "< '$linked_home/data/$absolute_id/brief.md'" \
    "absolute FM_HOME spelling changed in the default cross-process brief path"
  pass "FM_HOME defaults resolve relative paths and preserve absolute spellings"
}

test_absolute_override_spelling_is_preserved_in_launch_paths() {
  local rec id out status launch linked_home home_real
  id=profile-absolute-paths-z1c
  rec=$(make_spawn_case profile-absolute-paths pi "$id")
  read_case_record "$rec"
  linked_home="$CASE_DIR/home-link"
  ln -s "$HOME_DIR" "$linked_home"
  home_real=$(cd "$HOME_DIR" && pwd -P)
  : > "$LAUNCH_LOG"

  out=$(
    FM_ROOT_OVERRIDE='' FM_HOME="$linked_home" \
      FM_STATE_OVERRIDE="$linked_home/state" FM_DATA_OVERRIDE="$linked_home/data" \
      FM_PROJECTS_OVERRIDE="$linked_home/projects" FM_CONFIG_OVERRIDE="$linked_home/config" \
      FM_SPAWN_NO_GUARD=1 TMUX='' TMUX_PANE='' HERDR_ENV='' HERDR_PANE_ID='' HERDR_SOCKET_PATH='' HERDR_SESSION=lab FM_FAKE_HERDR_PANE_PATH="$WT_DIR" \
      FM_FAKE_HERDR_LAUNCH_LOG="$LAUNCH_LOG" \
      PATH="$FAKEBIN_DIR:$PATH" \
      "$SPAWN" "$id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1
  )
  status=$?
  expect_code 0 "$status" "spawn with absolute symlink-spelled overrides should succeed"
  launch=$(cat "$LAUNCH_LOG")
  assert_contains "$launch" "FM_WORKER_LIFECYCLE_CONTEXT='$home_real/state/$id.meta'" \
    "Pi's worker context path did not canonicalize an absolute symlink-spelled override"
  assert_contains "$launch" "< '$linked_home/data/$id/brief.md'" \
    "absolute FM_DATA_OVERRIDE spelling changed in the cross-process brief path"
  pass "absolute override spellings are preserved in spawn launch paths"
}

test_unresolvable_relative_overrides_fail_loudly() {
  local rec id out status
  id=profile-unresolvable-paths-z1d
  rec=$(make_spawn_case profile-unresolvable-paths pi "$id")
  read_case_record "$rec"

  out=$(
    cd "$CASE_DIR" || exit 1
    FM_ROOT_OVERRIDE='' FM_HOME=missing-home \
      FM_STATE_OVERRIDE='' FM_DATA_OVERRIDE='' \
      "$SPAWN" "$id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1
  )
  status=$?
  expect_code 1 "$status" "spawn with an unresolvable relative home should fail"
  assert_contains "$out" "FM_HOME directory cannot be resolved: missing-home" \
    "spawn did not name the unresolvable FM_HOME"

  out=$(
    cd "$CASE_DIR" || exit 1
    FM_ROOT_OVERRIDE='' FM_HOME=home \
      FM_STATE_OVERRIDE=missing-state FM_DATA_OVERRIDE=home/data \
      "$SPAWN" "$id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1
  )
  status=$?
  expect_code 1 "$status" "spawn with an unresolvable relative state override should fail"
  assert_contains "$out" "FM_STATE_OVERRIDE directory cannot be resolved: missing-state" \
    "spawn did not name the unresolvable FM_STATE_OVERRIDE"

  out=$(
    cd "$CASE_DIR" || exit 1
    FM_ROOT_OVERRIDE='' FM_HOME=home \
      FM_STATE_OVERRIDE=home/state FM_DATA_OVERRIDE=missing-data \
      "$SPAWN" "$id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1
  )
  status=$?
  expect_code 1 "$status" "spawn with an unresolvable relative data override should fail"
  assert_contains "$out" "FM_DATA_OVERRIDE directory cannot be resolved: missing-data" \
    "spawn did not name the unresolvable FM_DATA_OVERRIDE"
  pass "unresolvable relative spawn overrides fail with named diagnostics"
}

test_active_dispatch_profile_uses_direct_pi_for_ship() {
  local rec id out status
  id=profile-required-ship-z11
  rec=$(make_spawn_case profile-required-ship pi "$id")
  read_case_record "$rec"
  enable_dispatch_profile "$HOME_DIR"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$PROJ_DIR")
  status=$?
  expect_code 0 "$status" "ship spawn should run Pi directly when dispatch profiles are active"
  assert_meta_profile "$HOME_DIR/state/$id.meta" pi default default
  pass "active crew-dispatch profiles no longer select the ship runtime"
}

test_active_dispatch_profile_uses_direct_pi_for_scout() {
  local rec id out status
  id=profile-required-scout-z12
  rec=$(make_spawn_case profile-required-scout pi "$id")
  read_case_record "$rec"
  enable_dispatch_profile "$HOME_DIR"

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$PROJ_DIR" --scout)
  status=$?
  expect_code 0 "$status" "scout spawn should run Pi directly when dispatch profiles are active"
  assert_meta_profile "$HOME_DIR/state/$id.meta" pi default default
  pass "active crew-dispatch profiles no longer select the scout runtime"
}

test_harness_option_is_retired() {
  local rec id out status
  id=profile-explicit-z13
  rec=$(make_spawn_case profile-explicit pi "$id")
  read_case_record "$rec"
  enable_dispatch_profile "$HOME_DIR"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$PROJ_DIR" --harness pi)
  status=$?
  expect_code 1 "$status" "the retired harness option should fail"
  assert_contains "$out" "--harness is retired because Pi is the sole worker runtime" "retired harness option was not explained"
  assert_absent "$HOME_DIR/state/$id.meta" "retired harness option published metadata"
  pass "the worker-runtime command-line selector is retired"
}

test_launch_delivery_holds_endpoint_lock() {
  local rec id out status expected_lock
  id=profile-launch-lock-z13b
  rec=$(make_spawn_case profile-launch-lock pi "$id")
  read_case_record "$rec"
  expected_lock=$(PATH="$FAKEBIN_DIR:$PATH" HERDR_SESSION=lab \
    bash -c '. "$1/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path lab' _ "$ROOT") \
    || fail "could not resolve the spawn presentation lock"
  out=$(FM_FAKE_HERDR_EXPECTED_LOCK="$expected_lock" \
    run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$PROJ_DIR")
  status=$?
  expect_code 0 "$status" "spawn delivery should retain its endpoint authorization lock: $out"
  assert_present "$HOME_DIR/state/$id.meta" "locked spawn delivery did not publish metadata"
  assert_contains "$(cat "$LAUNCH_LOG")" "FM_WORKER_LIFECYCLE_CONTEXT=" \
    "locked spawn delivery did not type the Pi launch"
  pass "spawn delivery retains endpoint authorization through Enter"
}

test_positional_harness_is_retired() {
  local rec id out status
  id=profile-positional-z14
  rec=$(make_spawn_case profile-positional pi "$id")
  read_case_record "$rec"
  enable_dispatch_profile "$HOME_DIR"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
    "$id" "$PROJ_DIR" pi --model gpt-5 --effort high)
  status=$?
  expect_code 1 "$status" "positional harness should be retired"
  assert_contains "$out" "worker-runtime positional arguments are retired" "retired positional harness was not explained"
  assert_absent "$HOME_DIR/state/$id.meta" "retired positional harness published metadata"
  pass "the worker-runtime positional selector is retired"
}

test_production_spawn_rejects_raw_launch_command() {
  local rec id out status
  id=profile-raw-z15
  rec=$(make_spawn_case profile-raw pi "$id")
  read_case_record "$rec"
  enable_dispatch_profile "$HOME_DIR"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
    "$id" "$PROJ_DIR" "custom-agent --flag")
  status=$?
  expect_code 1 "$status" "production spawn must reject a raw launch command"
  assert_contains "$out" "worker-runtime positional arguments are retired" \
    "raw launch refusal did not name the Pi-only contract"
  assert_absent "$HOME_DIR/state/$id.meta" "raw launch refusal published task metadata"
  [ ! -s "$LAUNCH_LOG" ] || fail "raw launch refusal typed a launch command"
  pass "production spawn rejects raw non-Pi launch commands"
}

test_pi_threads_model_and_max_effort() {
  local rec id out status launch state_real
  id=profile-pi-z8
  rec=$(make_spawn_case profile-pi pi "$id")
  read_case_record "$rec"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$PROJ_DIR" \
    --model openai-codex/gpt-5.6-luna --effort max)
  status=$?
  expect_code 0 "$status" "pi spawn with max effort should succeed"
  assert_meta_profile "$HOME_DIR/state/$id.meta" pi openai-codex/gpt-5.6-luna max
  launch=$(cat "$LAUNCH_LOG")
  state_real=$(cd "$HOME_DIR/state" && pwd -P)
  assert_contains "$launch" "'$FAKEBIN_DIR/pi' --tui-mode regular --model 'openai-codex/gpt-5.6-luna' --thinking 'max' -e" \
    "pi launch did not force the regular TUI while threading the requested model and max thinking level"
  assert_not_contains "$launch" "FM_FIRSTMATE_PI_LAUNCH_BRIEF=" \
    "pi launch still exports the removed Calm input-reroute binding"
  assert_contains "$launch" "fm-operational-input.sh' encode launch-brief" \
    "pi launch lost the canonical typed launch-brief envelope"
  assert_absent "$HOME_DIR/state/$id.pi-ext.ts" "Pi launch generated a per-task extension artifact"
  assert_present "$HOME_DIR/state/$id.busy-gen" "pi spawn did not arm the busy-state contract"
  assert_contains "$(cat "$HOME_DIR/state/$id.busy-state")" "state=busy source=fm-spawn" \
    "pi spawn did not seed the busy-state record from the launch brief"
  assert_contains "$launch" "FM_WORKER_LIFECYCLE_CONTEXT='$state_real/$id.meta'" \
    "Pi launch did not pass the bounded task context"
  assert_contains "$launch" "-e '$ROOT/.pi/worker-extensions/fm-worker-lifecycle.ts'" \
    "Pi launch did not explicitly load the tracked worker extension"
  pass "Pi receives its profile, tracked lifecycle extension, and bounded task context"
}

test_pi_tui_mode_probe_is_safe_for_old_and_new_pi() {
  local harness=pi version rec id out status launch
  for version in 0.82.0 0.84.0; do
      id="profile-${harness}-tui-${version//./}-z8d"
      rec=$(make_spawn_case "profile-__MODELFLAG__-${harness}-tui-${version//./}" "$harness" "$id")
      read_case_record "$rec"

      out=$(FM_TEST_PI_VERSION="$version" \
        run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
        "$id" "$PROJ_DIR")
      status=$?
      expect_code 0 "$status" "$harness $version spawn should succeed"
      launch=$(cat "$LAUNCH_LOG")
      assert_contains "$launch" "'$FAKEBIN_DIR/$harness'" \
        "$harness $version launch must use the executable selected for probing"
      if [ "$version" = 0.82.0 ]; then
        assert_not_contains "$launch" "--tui-mode" \
          "$harness $version launch must omit unsupported --tui-mode"
      else
        assert_contains "$launch" "'$FAKEBIN_DIR/$harness' --tui-mode regular" \
          "$harness $version launch must preserve the regular TUI"
      fi
  done
  pass "Pi launch probing omits --tui-mode on older Pi and preserves it on supporting Pi"
}

test_pi_missing_binary_refuses_before_endpoint_or_metadata() {
  local rec id out status
  id=profile-pi-missing-z8c
  rec=$(make_spawn_case profile-pi-missing pi "$id")
  read_case_record "$rec"
  rm -f "$FAKEBIN_DIR/pi"
  : > "$LAUNCH_LOG"

  out=$(FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
    FM_SPAWN_NO_GUARD=1 TMUX='' TMUX_PANE='' HERDR_ENV='' HERDR_PANE_ID='' HERDR_SOCKET_PATH='' HERDR_SESSION=lab FM_FAKE_HERDR_PANE_PATH="$WT_DIR" \
    FM_FAKE_HERDR_LAUNCH_LOG="$LAUNCH_LOG" PATH="$FAKEBIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$SPAWN" "$id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1)
  status=$?
  expect_code 1 "$status" "a missing pi executable should refuse the spawn"
  assert_contains "$out" "pi executable not found on PATH" \
    "missing pi refusal did not name the actionable requirement"
  assert_absent "$HOME_DIR/state/$id.meta" "missing pi refusal wrote task metadata"
  [ ! -s "$LAUNCH_LOG" ] || fail "missing pi refusal typed a launch command"
  pass "pi refuses safely and actionably when the selected executable is unavailable"
}

test_pi_persistent_secondmate_uses_primary_extensions() {
  local rec id sm out status launch
  id=profile-pi-secondmate-z8d
  rec=$(make_spawn_case profile-pi-secondmate pi "$id")
  read_case_record "$rec"
  sm="$CASE_DIR/secondmate-home"
  make_seeded_secondmate_home "$sm" "$id"
  sm=$(cd "$sm" && pwd -P)

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$sm" --secondmate)
  status=$?
  expect_code 0 "$status" "pi persistent secondmate spawn should succeed"
  assert_contains "$out" "spawned $id harness=pi kind=secondmate" \
    "pi secondmate spawn did not preserve its runtime identity"
  assert_meta_profile "$HOME_DIR/state/$id.meta" pi default default
  launch=$(cat "$LAUNCH_LOG")
  assert_contains "$launch" "'$FAKEBIN_DIR/pi' --tui-mode regular -e '$sm/.pi/extensions/fm-primary-turnend-guard.ts' -e '$sm/.pi/extensions/fm-primary-pi-watch.ts'" \
    "pi secondmate did not force the regular TUI with Pi's primary extension launch shape"
  pass "pi persistent secondmates use Pi supervision semantics"
}

test_batch_forwards_shared_profile_flags() {
  local rec id1 id2 out status
  id1=profile-batch-a-z9
  id2=profile-batch-b-z10
  rec=$(make_spawn_case profile-batch pi "$id1" "$id2")
  read_case_record "$rec"
  enable_dispatch_profile "$HOME_DIR"

  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
    "$id1=$PROJ_DIR" "$id2=$PROJ_DIR" --model gpt-5 --effort high)
  status=$?
  expect_code 0 "$status" "batch spawn with shared profile flags should succeed"
  assert_contains "$out" "spawned $id1 harness=pi" "first batch task did not use shared harness"
  assert_contains "$out" "spawned $id2 harness=pi" "second batch task did not use shared harness"
  assert_meta_profile "$HOME_DIR/state/$id1.meta" pi gpt-5 high
  assert_meta_profile "$HOME_DIR/state/$id2.meta" pi gpt-5 high
  pass "batch dispatch runs Pi directly and forwards shared model and effort"
}

test_retired_worker_config_is_rejected() {
  local rec id config_id unsupported out status
  id=profile-unsupported-harness-z20
  rec=$(make_spawn_case profile-unsupported-harness pi "$id")
  read_case_record "$rec"
  unsupported=legacy-agent
  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$PROJ_DIR" --harness "$unsupported")
  status=$?
  expect_code 1 "$status" "an unsupported harness must be refused"
  assert_contains "$out" "--harness is retired because Pi is the sole worker runtime" "unsupported harness selector was not retired"
  [ ! -e "$HOME_DIR/state/$id.meta" ] || fail "unsupported harness refusal published task metadata"

  config_id=profile-stale-config-z21
  rec=$(make_spawn_case profile-stale-config "$unsupported" "$config_id")
  read_case_record "$rec"
  printf '%s\n' "$unsupported" > "$HOME_DIR/config/crew-harness"
  out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$config_id" "$PROJ_DIR")
  status=$?
  expect_code 1 "$status" "stale unsupported configuration must be refused"
  assert_contains "$out" "crew-harness is retired because Pi is the sole worker runtime" "stale worker config was not clearly retired"
  [ ! -e "$HOME_DIR/state/$config_id.meta" ] || fail "stale config refusal published task metadata"
  pass "fm-spawn rejects retired worker-runtime selectors"
}

test_active_dispatch_profile_does_not_block_secondmate_launch() {
  local rec id sm out status
  id=profile-secondmate-z16
  rec=$(make_spawn_case profile-secondmate pi "$id")
  read_case_record "$rec"
  enable_dispatch_profile "$HOME_DIR"
  sm="$CASE_DIR/secondmate-home"
  make_seeded_secondmate_home "$sm" "$id"

  out=$(run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" "$id" "$sm" --secondmate)
  status=$?
  expect_code 0 "$status" "secondmate spawn should be exempt from the dispatch-profile explicit harness requirement"
  assert_contains "$out" "spawned $id harness=pi kind=secondmate" "secondmate launch did not use secondmate harness resolution"
  assert_grep "kind=secondmate" "$HOME_DIR/state/$id.meta" "secondmate meta missing kind=secondmate"
  assert_meta_profile "$HOME_DIR/state/$id.meta" pi default default
  pass "active crew-dispatch profile does not block secondmate launches"
}

test_relative_home_overrides_launch_with_absolute_cross_process_paths
test_home_defaults_preserve_absolute_or_resolve_relative_paths
test_absolute_override_spelling_is_preserved_in_launch_paths
test_unresolvable_relative_overrides_fail_loudly
test_active_dispatch_profile_uses_direct_pi_for_ship
test_active_dispatch_profile_uses_direct_pi_for_scout
test_harness_option_is_retired
test_launch_delivery_holds_endpoint_lock
test_positional_harness_is_retired
test_production_spawn_rejects_raw_launch_command
test_pi_threads_model_and_max_effort
test_pi_tui_mode_probe_is_safe_for_old_and_new_pi
test_pi_missing_binary_refuses_before_endpoint_or_metadata
test_pi_persistent_secondmate_uses_primary_extensions
test_batch_forwards_shared_profile_flags
test_retired_worker_config_is_rejected
test_active_dispatch_profile_does_not_block_secondmate_launch

echo "# all fm-spawn-dispatch-profile tests passed"
