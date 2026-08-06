#!/usr/bin/env bash
# tests/fm-backend.test.sh - runtime backend selection and dispatch contract.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"

TMP_ROOT=$(fm_test_tmproot fm-backend-tests)

backend_name() {  # <config-dir> [env-value]
  local config=$1 selected=${2:-}
  FM_BACKEND_CONFIG_DIR="$config" FM_BACKEND="$selected" fm_backend_name
}

test_backend_name_defaults_to_herdr() {
  local config out
  config="$TMP_ROOT/default/config"
  mkdir -p "$config"
  out=$(ORCA_WORKSPACE_ID=ambient backend_name "$config")
  [ "$out" = herdr ] || fail "an absent backend selection must resolve to Herdr, got '$out'"
  pass "fm_backend_name: an absent selection defaults to Herdr without environment detection"
}

test_backend_name_precedence() {
  local config out
  config="$TMP_ROOT/precedence/config"
  mkdir -p "$config"
  printf 'orca\n' > "$config/backend"
  out=$(backend_name "$config")
  [ "$out" = orca ] || fail "config/backend should select Orca explicitly, got '$out'"
  out=$(backend_name "$config" herdr)
  [ "$out" = herdr ] || fail "FM_BACKEND should outrank config/backend, got '$out'"
  pass "fm_backend_name: FM_BACKEND outranks config/backend, which outranks the Herdr default"
}

test_backend_validation_accepts_only_supported_choices() {
  local out status
  fm_backend_validate herdr || fail "Herdr should be a supported backend"
  fm_backend_validate orca || fail "Orca should be a supported backend"
  out=$(fm_backend_validate stale-runtime 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "an unsupported backend must be rejected"
  assert_contains "$out" "supported: herdr orca" "the rejection should name the complete current supported set"
  assert_not_contains "$out" "fallback" "the rejection must not promise fallback behavior"
  pass "fm_backend_validate: accepts only Herdr and Orca and reports the current choices"
}

test_backend_required_tools_match_ownership() {
  local out
  out=$(fm_backend_required_tools herdr)
  [ "$out" = "herdr jq treehouse" ] || fail "Herdr requirements mismatch: '$out'"
  out=$(fm_backend_required_tools orca)
  [ "$out" = orca ] || fail "Orca requirements mismatch: '$out'"
  if fm_backend_required_tools stale-runtime >/dev/null 2>&1; then
    fail "unsupported backends must have no dependency declaration"
  fi
  pass "fm_backend_required_tools: Herdr and Orca declare only their current dependencies"
}

test_backend_meta_requires_explicit_identity() {
  local meta out
  meta="$TMP_ROOT/meta-missing-backend"
  printf 'window=default:w1:p2\n' > "$meta"
  out=$(fm_backend_of_meta "$meta")
  [ -z "$out" ] || fail "metadata without backend= must remain stale, got '$out'"
  pass "metadata routing: a missing backend identity is not reinterpreted"
}

test_backend_meta_routes_explicit_orca() {
  local meta out
  meta="$TMP_ROOT/meta-orca"
  cat > "$meta" <<'EOF_META'
backend=orca
window=fm-example
terminal=term-42
EOF_META
  out=$(fm_backend_of_meta "$meta")
  [ "$out" = orca ] || fail "explicit Orca metadata should remain Orca, got '$out'"
  out=$(fm_backend_target_of_meta "$meta")
  [ "$out" = term-42 ] || fail "Orca metadata should route through terminal=, got '$out'"
  pass "metadata routing: explicit Orca remains supported and uses its terminal handle"
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
  pass "fm_backend_resolve_selector: durable task selectors and explicit Herdr endpoints resolve exactly"
}

test_selector_backend_uses_recorded_identity() {
  local state out
  state="$TMP_ROOT/selector-backends"
  mkdir -p "$state"
  cat > "$state/herdr.meta" <<'EOF_META'
backend=herdr
window=default:w1:p1
EOF_META
  cat > "$state/explicit.meta" <<'EOF_META'
backend=orca
window=fm-explicit
terminal=term-explicit
EOF_META
  out=$(fm_backend_of_selector herdr default:w1:p1 "$state")
  [ "$out" = herdr ] || fail "a recorded Herdr selector should remain Herdr, got '$out'"
  out=$(fm_backend_of_selector explicit term-explicit "$state")
  [ "$out" = orca ] || fail "an explicitly recorded Orca selector should remain Orca, got '$out'"
  out=$(fm_backend_of_selector unknown direct:w1:p3 "$state")
  [ "$out" = herdr ] || fail "an unrecorded explicit endpoint should use Herdr, got '$out'"
  pass "fm_backend_of_selector: recorded identity wins and explicit endpoints are Herdr"
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
  [ "$FM_BACKEND_VALIDATED_BACKEND" = herdr ] || fail "validated backend should be Herdr"
  [ "$FM_BACKEND_VALIDATED_TARGET" = lab:w1:p2 ] || fail "validated Herdr target mismatch"
  pass "fm_backend_validate_task_endpoint: accepts a consistently bound Herdr endpoint"
}

test_task_endpoint_validation_accepts_orca() {
  local meta
  meta="$TMP_ROOT/orca-endpoint.meta"
  cat > "$meta" <<'EOF_META'
backend=orca
window=fm-sample
endpoint_task_id=sample
worktree=/tmp/sample-worktree
project=/tmp/sample-project
terminal=term-9
orca_worktree_id=worktree-9
EOF_META
  fm_backend_validate_task_endpoint "$meta" sample || fail "a consistent Orca endpoint should validate"
  [ "$FM_BACKEND_VALIDATED_BACKEND" = orca ] || fail "validated backend should be Orca"
  [ "$FM_BACKEND_VALIDATED_TARGET" = term-9 ] || fail "validated Orca target mismatch"
  pass "fm_backend_validate_task_endpoint: preserves explicit Orca endpoint validation"
}

test_task_endpoint_validation_rejects_stale_backend() {
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
  assert_contains "$out" "supported: herdr orca" "stale metadata rejection should name only supported choices"
  pass "fm_backend_validate_task_endpoint: rejects stale backend metadata without reinterpretation"
}

test_dispatch_has_no_orca_busy_fallback() {
  local out
  out=$(fm_backend_busy_state orca term-1)
  [ "$out" = unknown ] || fail "Orca busy state should remain unverified instead of falling back, got '$out'"
  if fm_backend_has_push orca; then
    fail "Orca must not claim Herdr's native transition stream"
  fi
  fm_backend_has_push herdr || fail "Herdr should retain native transition support"
  pass "backend dispatch: Herdr owns native supervision semantics and Orca has no automatic fallback"
}

test_backend_name_defaults_to_herdr
test_backend_name_precedence
test_backend_validation_accepts_only_supported_choices
test_backend_required_tools_match_ownership
test_backend_meta_requires_explicit_identity
test_backend_meta_routes_explicit_orca
test_selector_resolution_prefers_durable_metadata
test_selector_backend_uses_recorded_identity
test_task_endpoint_validation_accepts_herdr
test_task_endpoint_validation_accepts_orca
test_task_endpoint_validation_rejects_stale_backend
test_dispatch_has_no_orca_busy_fallback
