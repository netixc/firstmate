#!/usr/bin/env bash
# Endpoint identity safety tests for Herdr cleanup.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"

TMP_ROOT=$(fm_test_tmproot fm-teardown-endpoint-safety)

write_common() {  # <meta> <id> <backend>
  local meta=$1 id=$2 backend=$3
  cat > "$meta" <<EOF_META
backend=$backend
endpoint_task_id=$id
worktree=/tmp/$id-worktree
project=/tmp/$id-project
EOF_META
}

test_valid_herdr_endpoint() {
  local id=herdr-task meta="$TMP_ROOT/herdr.meta"
  write_common "$meta" "$id" herdr
  cat >> "$meta" <<'EOF_META'
window=lab:w1:p2
herdr_session=lab
herdr_workspace_id=w1
herdr_tab_id=w1:t2
herdr_pane_id=w1:p2
EOF_META
  fm_backend_validate_task_endpoint "$meta" "$id" || fail "valid Herdr endpoint was refused"
  [ "$FM_BACKEND_VALIDATED_BACKEND:$FM_BACKEND_VALIDATED_TARGET" = 'herdr:lab:w1:p2' ] \
    || fail "Herdr validation returned the wrong identity"
  pass "endpoint validation accepts an exactly bound Herdr endpoint"
}

test_missing_workspace_backend_identity_is_rejected() {
  local id=missing-backend meta="$TMP_ROOT/missing-backend.meta" out status
  cat > "$meta" <<EOF_META
endpoint_task_id=$id
window=default:w3:p4
worktree=/tmp/$id-worktree
project=/tmp/$id-project
herdr_session=default
herdr_workspace_id=w3
herdr_tab_id=w3:t4
herdr_pane_id=w3:p4
EOF_META
  out=$(fm_backend_validate_task_endpoint "$meta" "$id" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "metadata without backend= was accepted"
  assert_contains "$out" "missing or ambiguous workspace backend identity" "missing workspace backend refusal was unclear"
  pass "endpoint validation rejects a missing workspace backend identity as stale"
}

test_unsupported_endpoint_is_rejected_before_workspace_dispatch() {
  local id=unsupported meta="$TMP_ROOT/unsupported.meta" out status
  write_common "$meta" "$id" stale-runtime
  printf 'window=old:endpoint\n' >> "$meta"
  out=$(fm_backend_validate_task_endpoint "$meta" "$id" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "unsupported endpoint metadata was accepted"
  assert_contains "$out" "does not identify the Herdr workspace backend" "unsupported endpoint error did not name Herdr"
  pass "endpoint validation rejects unsupported workspace backend values without reinterpretation"
}

test_herdr_binding_mismatch_is_rejected() {
  local id=wrong-binding meta="$TMP_ROOT/wrong-binding.meta" out status
  cat > "$meta" <<EOF_META
backend=herdr
endpoint_task_id=another-task
window=lab:w1:p2
worktree=/tmp/$id-worktree
project=/tmp/$id-project
herdr_session=lab
herdr_workspace_id=w1
herdr_tab_id=w1:t2
herdr_pane_id=w1:p2
EOF_META
  out=$(fm_backend_validate_task_endpoint "$meta" "$id" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "mismatched task binding was accepted"
  assert_contains "$out" "belongs to task another-task" "binding refusal did not explain ownership"
  pass "endpoint validation refuses cross-task cleanup identity"
}

test_herdr_field_inconsistency_is_rejected() {
  local id=inconsistent meta="$TMP_ROOT/inconsistent.meta" out status
  cat > "$meta" <<EOF_META
backend=herdr
endpoint_task_id=$id
window=lab:w1:p9
worktree=/tmp/$id-worktree
project=/tmp/$id-project
herdr_session=lab
herdr_workspace_id=w1
herdr_tab_id=w1:t2
herdr_pane_id=w1:p2
EOF_META
  out=$(fm_backend_validate_task_endpoint "$meta" "$id" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "inconsistent Herdr fields were accepted"
  assert_contains "$out" "malformed or inconsistent" "field mismatch refusal was unclear"
  pass "endpoint validation refuses inconsistent Herdr endpoint fields"
}

test_valid_herdr_endpoint
test_missing_workspace_backend_identity_is_rejected
test_unsupported_endpoint_is_rejected_before_workspace_dispatch
test_herdr_binding_mismatch_is_rejected
test_herdr_field_inconsistency_is_rejected
