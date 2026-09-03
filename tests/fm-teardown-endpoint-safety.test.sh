#!/usr/bin/env bash
# Regression tests for Herdr-only cleanup endpoint identity validation.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-teardown-endpoint-safety)

make_case() {
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/home/state" "$dir/home/data" "$dir/home/config" \
    "$dir/fakebin" "$dir/worktree" "$dir/project"
  : > "$dir/worktree/sentinel"
  : > "$dir/runtime.log"
  cat > "$dir/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
printf 'herdr <%s>\n' "$*" >> "${FM_RUNTIME_LOG:?}"
exit 0
SH
  cat > "$dir/fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
printf 'treehouse <%s>\n' "$*" >> "${FM_RUNTIME_LOG:?}"
exit 0
SH
  chmod +x "$dir/fakebin/herdr" "$dir/fakebin/treehouse"
  printf '%s\n' "$dir"
}

assert_refused_without_mutation() {
  local dir=$1 id=$2 description=$3 rc
  set +e
  FM_HOME="$dir/home" FM_ROOT_OVERRIDE="$ROOT" FM_RUNTIME_LOG="$dir/runtime.log" \
    PATH="$dir/fakebin:$PATH" "$TEARDOWN" "$id" --force > "$dir/stdout" 2> "$dir/stderr"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$description: teardown unexpectedly succeeded"
  assert_present "$dir/home/state/$id.meta" "$description: metadata changed before refusal"
  assert_present "$dir/worktree/sentinel" "$description: worktree changed before refusal"
  [ ! -s "$dir/runtime.log" ] || fail "$description: runtime command ran before refusal"
}

test_invalid_and_ambiguous_records_refuse_before_mutation() {
  local dir id=endpoint-a

  dir=$(make_case absent-backend)
  fm_write_meta "$dir/home/state/$id.meta" \
    "window=lab:w1:p1" "endpoint_task_id=$id" "worktree=$dir/worktree" "project=$dir/project"
  assert_refused_without_mutation "$dir" "$id" "absent provider"

  dir=$(make_case unsupported-backend)
  fm_write_meta "$dir/home/state/$id.meta" \
    "backend=legacy-provider" "window=legacy:fm-$id" "endpoint_task_id=$id" \
    "worktree=$dir/worktree" "project=$dir/project"
  assert_refused_without_mutation "$dir" "$id" "unsupported provider"

  dir=$(make_case duplicate-backend)
  fm_write_meta "$dir/home/state/$id.meta" \
    "backend=herdr" "backend=herdr" "window=lab:w1:p1" "endpoint_task_id=$id" \
    "worktree=$dir/worktree" "project=$dir/project" "herdr_session=lab" \
    "herdr_workspace_id=w1" "herdr_tab_id=w1:t1" "herdr_pane_id=w1:p1"
  assert_refused_without_mutation "$dir" "$id" "ambiguous provider"

  dir=$(make_case duplicate-window)
  fm_write_meta "$dir/home/state/$id.meta" \
    "backend=herdr" "window=lab:w1:p1" "window=lab:w1:p2" "endpoint_task_id=$id" \
    "worktree=$dir/worktree" "project=$dir/project" "herdr_session=lab" \
    "herdr_workspace_id=w1" "herdr_tab_id=w1:t1" "herdr_pane_id=w1:p2"
  assert_refused_without_mutation "$dir" "$id" "ambiguous endpoint"

  pass "cleanup refuses absent, unsupported, and ambiguous identity before mutation"
}

test_exact_herdr_record_validates() {
  local dir id=herdr-task
  dir=$(make_case valid-herdr)
  fm_write_meta "$dir/home/state/$id.meta" \
    "backend=herdr" "window=lab:w1:p2" "endpoint_task_id=$id" \
    "worktree=$dir/worktree" "project=$dir/project" "herdr_session=lab" \
    "herdr_workspace_id=w1" "herdr_tab_id=w1:t2" "herdr_pane_id=w1:p2"
  # shellcheck source=/dev/null
  . "$ROOT/bin/fm-backend.sh"
  fm_backend_validate_task_endpoint "$dir/home/state/$id.meta" "$id" \
    || fail "an exact Herdr endpoint was refused"
  [ "$FM_BACKEND_VALIDATED_BACKEND:$FM_BACKEND_VALIDATED_TARGET" = "herdr:lab:w1:p2" ] \
    || fail "Herdr endpoint validation returned the wrong identity"
  pass "cleanup accepts one exact task-bound Herdr endpoint identity"
}

test_live_identity_refuses_before_process_cleanup() {
  local dir id=live-mismatch sleeper rc
  dir=$(make_case "$id")
  fm_write_meta "$dir/home/state/$id.meta" \
    "backend=herdr" "window=lab:w1:p2" "endpoint_task_id=$id" \
    "worktree=$dir/worktree" "project=$dir/project" "herdr_session=lab" \
    "herdr_workspace_id=w1" "herdr_tab_id=w1:t2" "herdr_pane_id=w1:p2"
  cat > "$dir/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.2","protocol":16},"server":{"running":true}}\n' ;;
  "pane get") printf '{"result":{"pane":{"workspace_id":"w1","tab_id":"w1:t2","pane_id":"w1:p2"}}}\n' ;;
  "tab list") printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-another-task"}]}}\n' ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$dir/fakebin/herdr"
  (cd "$dir/worktree" && exec sleep 30) &
  sleeper=$!
  sleep 0.1
  set +e
  FM_HOME="$dir/home" FM_ROOT_OVERRIDE="$ROOT" FM_RUNTIME_LOG="$dir/runtime.log" \
    PATH="$dir/fakebin:$PATH" "$TEARDOWN" "$id" --force > "$dir/stdout" 2> "$dir/stderr"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "live identity mismatch unexpectedly allowed teardown"
  if ! kill -0 "$sleeper" 2>/dev/null; then
    fail "live identity mismatch terminated a worktree process before refusal"
  fi
  kill "$sleeper" 2>/dev/null || true
  wait "$sleeper" 2>/dev/null || true
  assert_present "$dir/home/state/$id.meta" "live identity mismatch removed metadata"
  assert_present "$dir/worktree/sentinel" "live identity mismatch changed the worktree"
  pass "cleanup validates live Herdr identity before process termination"
}

test_invalid_and_ambiguous_records_refuse_before_mutation
test_exact_herdr_record_validates
test_live_identity_refuses_before_process_cleanup
