#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
GUARD="$ROOT/bin/fm-turnend-guard.sh"
TMP=$(fm_test_tmproot fm-turnend-guard)
trap 'jobs -pr | xargs kill 2>/dev/null || true; rm -rf "$TMP"' EXIT

set +e
out=$(printf '{}' | "$GUARD" --claude 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "excluded turn-end mode was accepted"
assert_contains "$out" 'usage:' "excluded turn-end mode reports unsupported interface"
printf '' | "$GUARD"
printf 'not-json' | "$GUARD"
pass "plain Pi guard safely ignores unusable payloads"

home="$TMP/primary"
mkdir -p "$home/state" "$home/config" "$home/bin"
git init -q "$home"
fm_git_identity fmtest fmtest@example.invalid "$home"
touch "$home/AGENTS.md"
git -C "$home" add AGENTS.md
git -C "$home" commit -qm initial
printf 'kind=ship\nharness=pi\n' > "$home/state/task.meta"

set +e
out=$(printf '{}' | FM_ROOT_OVERRIDE="$home" FM_HOME="$home" "$GUARD" 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "unhealthy supervised Pi primary was allowed to end"
assert_contains "$out" 'TURN WOULD END BLIND' "unhealthy Pi primary reports blocking reason"
pass "Pi turn-end guard blocks an unhealthy supervised primary"

sleep 60 &
watcher_pid=$!
# shellcheck source=bin/fm-wake-lib.sh
. "$ROOT/bin/fm-wake-lib.sh"
identity=$(fm_pid_identity "$watcher_pid")
mkdir -p "$home/state/.watch.lock"
printf '%s\n' "$watcher_pid" > "$home/state/.watch.lock/pid"
printf '%s\n' "$home" > "$home/state/.watch.lock/fm-home"
printf '%s\n' "$ROOT/bin/fm-watch.sh" > "$home/state/.watch.lock/watcher-path"
printf '%s\n' "$identity" > "$home/state/.watch.lock/pid-identity"
touch "$home/state/.last-watcher-beat"
printf '{}' | FM_ROOT_OVERRIDE="$home" FM_HOME="$home" "$GUARD"
pass "Pi turn-end guard allows a healthy supervised primary"

child="$TMP/child"
git -C "$home" worktree add -q -b fm/turnend-child "$child"
mkdir -p "$child/state"
printf 'kind=ship\nharness=pi\n' > "$child/state/task.meta"
printf '{}' | FM_ROOT_OVERRIDE="$child" FM_HOME="$child" "$GUARD"
pass "Pi turn-end guard exempts child worktree scope"
