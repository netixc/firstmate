#!/usr/bin/env bash
# tests/fm-backend.test.sh - Herdr runtime metadata and dispatch contract.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"

TMP_ROOT=$(fm_test_tmproot fm-backend-tests)

test_runtime_validation_accepts_only_herdr() {
  local out status
  fm_backend_validate herdr || fail "Herdr should be the supported runtime"
  out=$(fm_backend_validate stale-runtime 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "an unsupported runtime must be rejected"
  assert_contains "$out" "Firstmate requires Herdr" "the rejection should name the sole runtime"
  pass "runtime validation accepts only Herdr"
}

test_runtime_required_tools_match_ownership() {
  local out
  out=$(fm_backend_required_tools herdr)
  [ "$out" = "herdr jq treehouse" ] || fail "Herdr requirements mismatch: '$out'"
  if fm_backend_required_tools stale-runtime >/dev/null 2>&1; then
    fail "unsupported runtimes must have no dependency declaration"
  fi
  pass "Herdr declares the endpoint and worktree dependencies"
}

test_runtime_meta_requires_explicit_identity() {
  local meta out
  meta="$TMP_ROOT/meta-missing-runtime"
  printf 'window=default:w1:p2\n' > "$meta"
  out=$(fm_backend_of_meta "$meta")
  [ -z "$out" ] || fail "metadata without backend= must remain stale, got '$out'"
  pass "metadata routing does not reinterpret a missing runtime identity"
}

test_selector_resolution_prefers_durable_metadata() {
  local state out
  state="$TMP_ROOT/selectors"
  mkdir -p "$state"
  cat > "$state/example.meta" <<'EOF_META'
backend=herdr
window=lab:w2:p7
EOF_META
  out=$(fm_backend_resolve_selector example "$state")
  [ "$out" = lab:w2:p7 ] || fail "task-id selector should resolve its recorded endpoint, got '$out'"
  out=$(fm_backend_resolve_selector fm-example "$state")
  [ "$out" = lab:w2:p7 ] || fail "fm-<id> selector should resolve its recorded endpoint, got '$out'"
  out=$(fm_backend_resolve_selector direct:w9:p1 "$state")
  [ "$out" = direct:w9:p1 ] || fail "an explicit Herdr endpoint should pass through unchanged, got '$out'"
  pass "durable task selectors and explicit Herdr endpoints resolve exactly"
}

test_selector_runtime_rejects_stale_metadata() {
  local state out status
  state="$TMP_ROOT/selector-runtime"
  mkdir -p "$state"
  cat > "$state/herdr.meta" <<'EOF_META'
backend=herdr
window=default:w1:p1
EOF_META
  out=$(fm_backend_of_selector herdr default:w1:p1 "$state")
  [ "$out" = herdr ] || fail "a recorded Herdr selector should remain Herdr, got '$out'"
  cat > "$state/stale.meta" <<'EOF_META'
backend=stale-runtime
window=default:w1:p2
EOF_META
  out=$(fm_backend_of_selector stale default:w1:p2 "$state" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "a stale recorded runtime must be rejected"
  [ -z "$out" ] || fail "stale selector rejection should stay silent, got '$out'"
  out=$(fm_backend_of_selector unknown direct:w1:p3 "$state")
  [ "$out" = herdr ] || fail "an unrecorded explicit endpoint should use Herdr, got '$out'"
  pass "selector runtime resolution accepts Herdr and rejects stale metadata"
}

test_task_endpoint_validation_accepts_herdr() {
  local meta
  meta="$TMP_ROOT/herdr-endpoint.meta"
  cat > "$meta" <<'EOF_META'
backend=herdr
window=lab:w1:p2
endpoint_task_id=sample
worktree=/tmp/sample-worktree
project=/tmp/sample-project
herdr_session=lab
herdr_workspace_id=w1
herdr_tab_id=w1:t2
herdr_pane_id=w1:p2
EOF_META
  fm_backend_validate_task_endpoint "$meta" sample || fail "a consistent Herdr endpoint should validate"
  [ "$FM_BACKEND_VALIDATED_BACKEND" = herdr ] || fail "validated runtime should be Herdr"
  [ "$FM_BACKEND_VALIDATED_TARGET" = lab:w1:p2 ] || fail "validated Herdr target mismatch"
  pass "endpoint validation accepts a consistently bound Herdr endpoint"
}

test_task_endpoint_validation_rejects_stale_runtime() {
  local meta out status
  meta="$TMP_ROOT/stale-endpoint.meta"
  cat > "$meta" <<'EOF_META'
backend=stale-runtime
window=old:endpoint
endpoint_task_id=sample
worktree=/tmp/sample-worktree
project=/tmp/sample-project
EOF_META
  out=$(fm_backend_validate_task_endpoint "$meta" sample 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "stale endpoint metadata must be rejected"
  assert_contains "$out" "does not identify the Herdr runtime" "stale metadata rejection should name Herdr"
  pass "endpoint validation rejects stale runtime metadata without reinterpretation"
}

test_task_endpoint_validation_rejects_missing_binding() {
  local meta out status
  meta="$TMP_ROOT/missing-binding.meta"
  cat > "$meta" <<'EOF_META'
backend=herdr
window=lab:w1:p2
worktree=/tmp/sample-worktree
project=/tmp/sample-project
herdr_session=lab
herdr_workspace_id=w1
herdr_tab_id=w1:t2
herdr_pane_id=w1:p2
EOF_META
  out=$(fm_backend_validate_task_endpoint "$meta" sample 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "an endpoint without a task binding must be rejected"
  assert_contains "$out" "missing or ambiguous endpoint task binding" "the rejection should preserve strict task identity"
  pass "endpoint validation requires an exact task binding"
}

test_herdr_dispatch_retains_native_supervision() {
  fm_backend_has_push herdr || fail "Herdr should retain native transition support"
  if fm_backend_has_push stale-runtime; then
    fail "an unknown runtime must not claim Herdr's transition stream"
  fi
  pass "Herdr retains native supervision semantics"
}

test_runtime_validation_accepts_only_herdr
test_runtime_required_tools_match_ownership
test_runtime_meta_requires_explicit_identity
test_selector_resolution_prefers_durable_metadata
test_selector_runtime_rejects_stale_metadata
test_task_endpoint_validation_accepts_herdr
test_task_endpoint_validation_rejects_stale_runtime
test_task_endpoint_validation_rejects_missing_binding
test_herdr_dispatch_retains_native_supervision

echo "all fm-backend tests passed"
