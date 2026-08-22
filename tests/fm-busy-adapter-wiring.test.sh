#!/usr/bin/env bash
# Behavior tests for the tracked Pi worker-lifecycle extension installed by
# bin/fm-spawn.sh under the semantic contract in bin/fm-busy-lib.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=tests/remote-herdr-fixture.sh
. "$ROOT/tests/remote-herdr-fixture.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
EXTENSION="$ROOT/.pi/worker-extensions/fm-worker-lifecycle.ts"
TMP_ROOT=$(fm_test_tmproot fm-busy-adapter-wiring)

make_fakebin() {
  local root=$1 fakebin herdr_root
  fakebin=$(fm_fakebin "$root")
  herdr_root="$root/herdr-root"
  install_remote_herdr_fixture "$herdr_root" "$root/herdr.state" "$root/herdr.log" \
    "$root/herdr-send-fail" "$root/herdr.sock"
  ln -s "$herdr_root/bin/herdr" "$fakebin/herdr"
  fm_fake_exit0 "$fakebin" treehouse pi
  printf '%s\n' "$fakebin"
}

drive_extension() { # <worktree> <context-or-empty> <mode> <state> <id>
  local worktree=$1 context=$2 mode=$3 state=$4 id=$5
  (
    cd "$worktree" || exit 1
    EXT_PATH="$EXTENSION" FM_WORKER_LIFECYCLE_CONTEXT="$context" MODE="$mode" \
      STATE="$state" ID="$id" WRITER="$ROOT/bin/fm-busy-event.sh" \
      node --input-type=module <<'EOF'
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";
const handlers = {};
const mod = await import(pathToFileURL(process.env.EXT_PATH).href);
mod.default({ on: (name, handler) => { handlers[name] = handler; } });
if (process.env.MODE === "handlers") {
  console.log(Object.keys(handlers).sort().join(" "));
  process.exit(0);
}
const ctx = { isIdle: () => process.env.MODE !== "settle-continuing" };
if (process.env.MODE === "stale-settle") {
  execFileSync(process.env.WRITER, ["arm", process.env.STATE, process.env.ID], { stdio: "ignore" });
  await handlers.agent_settled({}, ctx);
} else if (process.env.MODE === "settle-then-start") {
  await handlers.agent_settled({}, ctx);
  await handlers.agent_start({}, ctx);
} else if (process.env.MODE === "turn-end") {
  await handlers.turn_end({}, ctx);
  await new Promise((done) => setTimeout(done, 200));
} else {
  const event = process.env.MODE === "agent-start" ? "agent_start" : "agent_settled";
  await handlers[event]({}, ctx);
}
EOF
  )
}

classify() { fm_busy_classify "lab:w-$1:p1" "$1" "$2"; }

setup_case() { # <name> <id>
  local name=$1
  CASE="$TMP_ROOT/$name"
  HOME_DIR="$CASE/home"
  PROJ="$CASE/project"
  WT="$CASE/wt"
  ID=$2
  FAKEBIN=$(make_fakebin "$CASE/fake")
  mkdir -p "$HOME_DIR/data/$ID" "$HOME_DIR/projects" "$HOME_DIR/state" "$HOME_DIR/config"
  printf 'brief\n' > "$HOME_DIR/data/$ID/brief.md"
  fm_git_worktree "$PROJ" "$WT" "busy-$name"
  touch "$HOME_DIR/state/.last-watcher-beat"
  out=$(env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_SOCKET \
    FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
    FM_SPAWN_NO_GUARD=1 HERDR_SESSION=lab FM_FAKE_HERDR_PANE_PATH="$WT" \
    PATH="$FAKEBIN:$PATH" "$SPAWN" "$ID" "$PROJ" \
    --mode no-mistakes --yolo off 2>&1)
  expect_code 0 $? "Pi spawn should succeed: $out"
  CONTEXT=$(cd "$HOME_DIR/state" && pwd -P)/$ID.meta
  assert_absent "$HOME_DIR/state/$ID.pi-ext.ts" "fresh Pi spawn generated a per-task TypeScript artifact"
}

test_lifecycle_and_generation() {
  local out
  setup_case lifecycle busy-pi-1
  [ "$(classify "$ID" "$HOME_DIR/state")" = "busy fm-spawn" ] \
    || fail "spawn did not seed busy state"
  out=$(drive_extension "$WT" "$CONTEXT" handlers "$HOME_DIR/state" "$ID")
  [ "$out" = "agent_settled agent_start turn_end" ] || fail "tracked lifecycle handlers did not load: $out"

  rm -f "$HOME_DIR/state/$ID.turn-ended"
  drive_extension "$WT" "$CONTEXT" turn-end "$HOME_DIR/state" "$ID" >/dev/null
  assert_present "$HOME_DIR/state/$ID.turn-ended" "turn_end did not touch its notification"
  [ "$(classify "$ID" "$HOME_DIR/state")" = "busy fm-spawn" ] \
    || fail "turn_end became current-state truth"

  drive_extension "$WT" "$CONTEXT" settle-idle "$HOME_DIR/state" "$ID" >/dev/null
  [ "$(classify "$ID" "$HOME_DIR/state")" = "idle pi-ext" ] || fail "idle settle was not recorded"
  drive_extension "$WT" "$CONTEXT" agent-start "$HOME_DIR/state" "$ID" >/dev/null
  drive_extension "$WT" "$CONTEXT" settle-continuing "$HOME_DIR/state" "$ID" >/dev/null
  [ "$(classify "$ID" "$HOME_DIR/state")" = "busy pi-ext" ] || fail "continuing settle overwrote busy"
  drive_extension "$WT" "$CONTEXT" settle-then-start "$HOME_DIR/state" "$ID" >/dev/null
  [ "$(classify "$ID" "$HOME_DIR/state")" = "busy pi-ext" ] || fail "immediate new work did not win"

  drive_extension "$WT" "$CONTEXT" stale-settle "$HOME_DIR/state" "$ID" >/dev/null
  [ "$(classify "$ID" "$HOME_DIR/state")" = "busy fm-spawn" ] \
    || fail "late callback from the captured old generation changed replacement state"
  pass "tracked Pi lifecycle preserves busy, idle, turn-end, ordering, and stale-generation behavior"
}

assert_inert() { # <path> <label>
  local out
  out=$(drive_extension "$WT" "$1" handlers "$HOME_DIR/state" "$ID")
  [ -z "$out" ] || fail "$2 context registered lifecycle handlers: $out"
}

test_context_validation() {
  local dir meta gen
  setup_case invalid-context busy-pi-2
  assert_inert "" absent

  dir="$CASE/invalid"
  mkdir -p "$dir/malformed" "$dir/symlink" "$dir/nonregular" "$dir/inconsistent" \
    "$dir/providerless" "$dir/retired-provider" "$dir/unsupported"
  meta="$dir/malformed/$ID.meta"
  printf 'not metadata\n' > "$meta"
  assert_inert "$meta" malformed

  meta="$dir/symlink/$ID.meta"
  ln -s "$CONTEXT" "$meta"
  assert_inert "$meta" symlinked

  meta="$dir/nonregular/$ID.meta"
  mkdir "$meta"
  assert_inert "$meta" non-regular

  meta="$dir/inconsistent/$ID.meta"
  cp "$CONTEXT" "$meta"
  gen=$(cat "$HOME_DIR/state/$ID.busy-gen")
  printf '%s\n' "$gen" > "$dir/inconsistent/$ID.busy-gen"
  perl -pi -e 's/^busy_gen=.*/busy_gen=wrong-generation/' "$meta"
  assert_inert "$meta" inconsistent

  meta="$dir/providerless/$ID.meta"
  sed '/^backend=/d' "$CONTEXT" > "$meta"
  printf '%s\n' "$gen" > "$dir/providerless/$ID.busy-gen"
  assert_inert "$meta" providerless

  meta="$dir/retired-provider/$ID.meta"
  sed 's/^backend=herdr$/backend=tmux/' "$CONTEXT" > "$meta"
  printf '%s\n' "$gen" > "$dir/retired-provider/$ID.busy-gen"
  assert_inert "$meta" retired-provider

  meta="$dir/unsupported/$ID.meta"
  cp "$CONTEXT" "$meta"
  printf '%s\n' "$gen" > "$dir/unsupported/$ID.busy-gen"
  printf 'harness=legacy-agent\n' >> "$meta"
  assert_inert "$meta" unsupported-runtime
  pass "worker lifecycle context rejects unsafe, non-Herdr, and inconsistent inputs"
}

test_lifecycle_and_generation
test_context_validation

echo "all fm-busy-adapter-wiring tests passed"
