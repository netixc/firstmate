#!/usr/bin/env bash
# Pi runtime bootstrap diagnostics tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOOTSTRAP="$ROOT/bin/fm-bootstrap.sh"
TMP_ROOT=$(fm_test_tmproot fm-bootstrap-pi)

make_home() {
  local home=$1
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects"
}

run_bootstrap() {
  local home=$1
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_BOOTSTRAP_DETECT_ONLY=1 "$BOOTSTRAP" 2>&1
}

test_obsolete_runtime_config_is_reported() {
  local home="$TMP_ROOT/obsolete" out
  make_home "$home"
  printf 'retired-runtime\n' > "$home/config/crew-harness"
  out=$(run_bootstrap "$home")
  assert_contains "$out" 'PI_RUNTIME_MIGRATION:' "bootstrap did not report obsolete runtime configuration"
  assert_contains "$out" 'no local configuration was changed' "bootstrap migration check wrote private configuration"
  pass "bootstrap reports the explicit Pi migration boundary"
}

test_invalid_pi_dispatch_is_reported() {
  local home="$TMP_ROOT/invalid-dispatch" out
  make_home "$home"
  cat > "$home/config/crew-dispatch.json" <<'JSON'
{"rules":[{"when":"test","use":{"model":"","effort":"high"}}]}
JSON
  out=$(run_bootstrap "$home")
  assert_contains "$out" 'CREW_DISPATCH: invalid config/crew-dispatch.json' "bootstrap did not report malformed Pi dispatch"
  pass "bootstrap rejects malformed Pi dispatch profiles"
}

test_valid_pi_dispatch_is_silent() {
  local home="$TMP_ROOT/valid-dispatch" out
  make_home "$home"
  cat > "$home/config/crew-dispatch.json" <<'JSON'
{"rules":[{"when":"test","use":{"model":"openai-codex/gpt-5.6-luna","effort":"high"}}]}
JSON
  out=$(run_bootstrap "$home")
  assert_not_contains "$out" 'CREW_DISPATCH: invalid' "bootstrap rejected a valid Pi dispatch"
  pass "bootstrap accepts Pi model and thinking dispatch profiles"
}

test_runtime_axis_in_dispatch_is_rejected() {
  local home="$TMP_ROOT/runtime-axis" out
  make_home "$home"
  cat > "$home/config/crew-dispatch.json" <<'JSON'
{"rules":[{"when":"test","use":{"harness":"retired-runtime","model":"openai-codex/gpt-5.6-luna"}}]}
JSON
  out=$(run_bootstrap "$home")
  assert_contains "$out" 'obsolete runtime field: harness' "bootstrap accepted a runtime-choice dispatch field"
  pass "bootstrap rejects a runtime-choice field in Pi dispatch profiles"
}

test_obsolete_runtime_config_is_reported
test_invalid_pi_dispatch_is_reported
test_valid_pi_dispatch_is_silent
test_runtime_axis_in_dispatch_is_rejected
