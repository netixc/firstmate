#!/usr/bin/env bash
# Herdr-only Secondmate launch and preservation safety boundaries.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/remote-herdr-fixture.sh
. "$ROOT/tests/remote-herdr-fixture.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-secondmate-safety)

make_fakebin() { # <dir>
  local dir=$1 fb herdr_root
  fb=$(fm_fakebin "$dir")
  herdr_root=$dir/herdr-root
  install_remote_herdr_fixture "$herdr_root" "$dir/herdr.state" "$dir/herdr.log" \
    "$dir/herdr-send-fail" "$dir/herdr.sock"
  ln -s "$herdr_root/bin/herdr" "$fb/herdr"
  fm_fake_exit0 "$fb" treehouse pi no-mistakes gh gh-axi
  printf '%s\n' "$fb"
}

seed_home() { # <path> <id>
  local home=$1 id=$2
  mkdir -p "$home/bin" "$home/data" "$home/state" "$home/config" "$home/projects"
  git -C "$home" init -q
  printf '# Firstmate test home\n' > "$home/AGENTS.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home/bin/placeholder.sh"
  chmod +x "$home/bin/placeholder.sh"
  git -C "$home" add AGENTS.md bin/placeholder.sh
  git -C "$home" -c user.name=fmtest -c user.email=fmtest@example.invalid commit -qm seed
  printf '%s\n' "$id" > "$home/.fm-secondmate-home"
  printf 'charter\n' > "$home/data/charter.md"
}

run_spawn() { # <parent> <home> <id> <fakebin>
  local parent=$1 home=$2 id=$3 fb=$4
  env -u TMUX -u TMUX_PANE -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH \
    PATH="$fb:$PATH" FM_HOME="$parent" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$parent/state" FM_DATA_OVERRIDE="$parent/data" \
    FM_CONFIG_OVERRIDE="$parent/config" HERDR_SESSION=lab \
    FM_FAKE_HERDR_PANE_PATH="$home" FM_SPAWN_NO_GUARD=1 \
    "$SPAWN" "$id" "$home" --secondmate
}

test_projectless_secondmate_spawn() {
  local world parent home id=domain-a fb out
  world=$TMP_ROOT/projectless; parent=$world/parent; home=$world/home
  mkdir -p "$parent/state" "$parent/data/$id" "$parent/config" "$parent/projects"
  printf 'pi\n' > "$parent/config/crew-harness"
  printf 'charter instructions\n' > "$parent/data/$id/brief.md"
  seed_home "$home" "$id"
  fb=$(make_fakebin "$world/fake")
  out=$(run_spawn "$parent" "$home" "$id" "$fb") || fail "project-less Secondmate spawn failed"
  assert_contains "$out" "spawned $id" "Secondmate spawn did not report success"
  assert_grep 'backend=herdr' "$parent/state/$id.meta" "Secondmate metadata did not select the sole path"
  [ "$(cd "$(sed -n 's/^worktree=//p' "$parent/state/$id.meta")" && pwd -P)" = "$(cd "$home" && pwd -P)" ] \
    || fail "Secondmate home identity changed"
  assert_grep 'herdr_session=lab' "$parent/state/$id.meta" "Secondmate did not use the named Herdr session"
  pass "project-less Secondmates launch as Pi agents in exact Herdr endpoints"
}

test_retired_selection_stops_before_launch() {
  local world parent home id=domain-b fb out
  world=$TMP_ROOT/retired; parent=$world/parent; home=$world/home
  mkdir -p "$parent/state" "$parent/data/$id" "$parent/config"
  printf 'tmux\n' > "$parent/config/backend"
  printf 'charter\n' > "$parent/data/$id/brief.md"
  seed_home "$home" "$id"
  fb=$(make_fakebin "$world/fake")
  : > "$world/fake/herdr.log"
  out=$(run_spawn "$parent" "$home" "$id" "$fb" 2>&1) && fail "retired session setting should refuse"
  assert_contains "$out" 'tmux session support is retired' "retired setting refusal was not actionable"
  [ ! -s "$world/fake/herdr.log" ] || fail "retired setting reached Herdr"
  [ ! -e "$parent/state/$id.meta" ] || fail "retired setting published endpoint metadata"
  pass "retired Secondmate session selection stops before mutation"
}

test_legacy_child_record_blocks_forced_retirement() {
  local world parent home id=domain-c fb out before
  world=$TMP_ROOT/legacy-child; parent=$world/parent; home=$world/home
  mkdir -p "$parent/state" "$parent/data" "$parent/config"
  seed_home "$home" "$id"
  fb=$(make_fakebin "$world/fake")
  fm_write_meta "$parent/state/$id.meta" \
    "backend=herdr" "window=lab:w-$id:p1" "endpoint_task_id=$id" \
    "herdr_session=lab" "herdr_workspace_id=w-$id" "herdr_tab_id=w-$id:t-$id" \
    "herdr_pane_id=w-$id:p1" "worktree=$home" "project=$home" \
    "home=$home" "harness=pi" "kind=secondmate" "mode=secondmate"
  fm_write_meta "$home/state/legacy-child.meta" \
    "window=firstmate:fm-legacy-child" "worktree=$world/child-wt" \
    "project=$world/project" "harness=pi" "kind=ship"
  before=$(shasum -a 256 "$home/state/legacy-child.meta" | awk '{print $1}')
  out=$(PATH="$fb:$PATH" FM_HOME="$parent" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$parent/state" FM_DATA_OVERRIDE="$parent/data" \
    FM_CONFIG_OVERRIDE="$parent/config" "$TEARDOWN" "$id" --force 2>&1) \
    && fail "forced retirement should refuse ambiguous legacy child identity"
  assert_contains "$out" 'retired legacy tmux metadata' "legacy child refusal did not name preservation"
  [ -d "$home" ] || fail "legacy child refusal removed the Secondmate home"
  [ "$(shasum -a 256 "$home/state/legacy-child.meta" | awk '{print $1}')" = "$before" ] \
    || fail "legacy child refusal rewrote its record"
  pass "forced Secondmate retirement preserves legacy child records for manual reconciliation"
}

test_projectless_secondmate_spawn
test_retired_selection_stops_before_launch
test_legacy_child_record_blocks_forced_retirement
