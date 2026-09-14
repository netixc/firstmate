#!/usr/bin/env bash
# Behavior tests for the AGENTS.md-only project memory helper.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ENSURE="$ROOT/bin/fm-ensure-agents-md.sh"
TMP_ROOT=$(fm_test_tmproot fm-ensure-agents-md)

new_repo() {
  local name=$1 repo
  repo="$TMP_ROOT/$name"
  mkdir -p "$repo"
  printf '%s\n' "$repo"
}

test_absent_file_creates_skeleton() {
  local repo out
  repo=$(new_repo absent)
  out=$("$ENSURE" "$repo") || fail "helper refused an empty project: $out"
  [ -f "$repo/AGENTS.md" ] || fail "helper did not create AGENTS.md"
  [ ! -L "$repo/AGENTS.md" ] || fail "helper created AGENTS.md as a symlink"
  assert_grep '# Project agent memory' "$repo/AGENTS.md" "skeleton heading missing"
  assert_grep '## Maintaining this file' "$repo/AGENTS.md" "maintenance section missing"
  assert_contains "$out" "created: AGENTS.md" "creation result missing"
  pass "fm-ensure-agents-md: creates the AGENTS.md skeleton"
}

test_existing_file_is_extended_once() {
  local repo before out
  repo=$(new_repo existing)
  printf '# Existing instructions\n\nKeep this.\n' > "$repo/AGENTS.md"
  out=$("$ENSURE" "$repo") || fail "helper refused an existing AGENTS.md: $out"
  assert_grep '# Existing instructions' "$repo/AGENTS.md" "existing content was lost"
  [ "$(grep -c '^## Maintaining this file$' "$repo/AGENTS.md")" -eq 1 ] \
    || fail "maintenance section was not added exactly once"
  cp "$repo/AGENTS.md" "$repo/before"
  out=$("$ENSURE" "$repo") || fail "idempotent rerun failed: $out"
  cmp -s "$repo/before" "$repo/AGENTS.md" || fail "idempotent rerun changed AGENTS.md"
  assert_contains "$out" "unchanged: AGENTS.md" "idempotent result missing"
  pass "fm-ensure-agents-md: extends an existing file once"
}

test_project_owned_marker_preserves_custom_guidance() {
  local repo out
  repo=$(new_repo marker)
  printf '<!-- firstmate:maintained-by-project -->\n# Custom guidance\n' > "$repo/AGENTS.md"
  out=$("$ENSURE" "$repo") || fail "helper refused the project-owned marker: $out"
  assert_no_grep '## Maintaining this file' "$repo/AGENTS.md" "marker did not suppress canonical injection"
  assert_contains "$out" "unchanged: AGENTS.md" "marker result missing"
  pass "fm-ensure-agents-md: honors project-owned maintenance guidance"
}

test_crlf_file_keeps_crlf() {
  local repo
  repo=$(new_repo crlf)
  printf '# Existing\r\n' > "$repo/AGENTS.md"
  "$ENSURE" "$repo" >/dev/null || fail "helper refused a CRLF AGENTS.md"
  python3 - "$repo/AGENTS.md" <<'PY' || fail "helper introduced bare LF into a CRLF file"
import pathlib, sys
b = pathlib.Path(sys.argv[1]).read_bytes()
assert b.replace(b'\r\n', b'').find(b'\n') == -1
PY
  pass "fm-ensure-agents-md: preserves CRLF style"
}

test_case_variant_is_refused() {
  local repo out status
  repo=$(new_repo lowercase)
  printf '# Wrong case\n' > "$repo/agents.md"
  out=$("$ENSURE" "$repo" 2>&1); status=$?
  [ "$status" -ne 0 ] || fail "helper accepted lowercase agents.md"
  assert_contains "$out" "rename it to AGENTS.md" "case-variant refusal is unclear"
  [ "$(ls -1 "$repo")" = agents.md ] || fail "case-variant refusal changed the directory entry"
  [ "$(cat "$repo/agents.md")" = '# Wrong case' ] || fail "case-variant refusal changed the existing file"
  pass "fm-ensure-agents-md: refuses case-variant memory files"
}

test_symlink_and_nonregular_are_refused() {
  local repo out status
  repo=$(new_repo symlink)
  printf '# Target\n' > "$repo/target"
  ln -s target "$repo/AGENTS.md"
  out=$("$ENSURE" "$repo" 2>&1); status=$?
  [ "$status" -ne 0 ] || fail "helper accepted an AGENTS.md symlink"
  assert_contains "$out" "AGENTS.md is a symlink" "symlink refusal is unclear"

  repo=$(new_repo directory)
  mkdir "$repo/AGENTS.md"
  out=$("$ENSURE" "$repo" 2>&1); status=$?
  [ "$status" -ne 0 ] || fail "helper accepted an AGENTS.md directory"
  assert_contains "$out" "not a regular file" "nonregular refusal is unclear"
  pass "fm-ensure-agents-md: refuses symlink and nonregular targets"
}

test_absent_file_creates_skeleton
test_existing_file_is_extended_once
test_project_owned_marker_preserves_custom_guidance
test_crlf_file_keeps_crlf
test_case_variant_is_refused
test_symlink_and_nonregular_are_refused

echo "# all fm-ensure-agents-md tests passed"
