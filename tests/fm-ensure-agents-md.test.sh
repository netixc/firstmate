#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-ensure-agents-md.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
LEGACY_NAME=$(printf 'CL%s.md' 'AUDE')

fail() { echo "not ok - $*" >&2; exit 1; }
pass() { echo "ok - $*"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$3"; }
assert_count() { local got; got=$(grep -Fc -- "$2" "$1" || true); [ "$got" = "$3" ] || fail "$4 (got $got)"; }

test_create_skeleton() {
  local repo="$TMP_ROOT/create"
  mkdir -p "$repo"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null
  [ -f "$repo/AGENTS.md" ] && [ ! -L "$repo/AGENTS.md" ] || fail "creation did not produce a real AGENTS.md"
  assert_contains "$repo/AGENTS.md" '# Project agent memory' "skeleton heading missing"
  assert_count "$repo/AGENTS.md" '## Maintaining this file' 1 "skeleton maintenance section count"
  pass "fm-ensure-agents-md: creates a real AGENTS.md skeleton with self-governance"
}

test_existing_injection_and_idempotence() {
  local repo="$TMP_ROOT/existing" first second
  mkdir -p "$repo"
  printf '# Existing\n\nKeep this.\n' > "$repo/AGENTS.md"
  first=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo")
  second=$("$ROOT/bin/fm-ensure-agents-md.sh" "$repo")
  case "$first" in updated:*) : ;; *) fail "first injection did not report updated: $first" ;; esac
  case "$second" in unchanged:*) : ;; *) fail "second injection did not report unchanged: $second" ;; esac
  assert_contains "$repo/AGENTS.md" 'Keep this.' "existing content was lost"
  assert_count "$repo/AGENTS.md" '## Maintaining this file' 1 "idempotence duplicated the section"
  pass "fm-ensure-agents-md: injects once and is idempotent"
}

test_no_trailing_newline_separator() {
  local repo="$TMP_ROOT/no-newline"
  mkdir -p "$repo"
  printf '# Existing\n\nKeep this.' > "$repo/AGENTS.md"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null
  python3 - "$repo/AGENTS.md" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert 'Keep this.\n\n## Maintaining this file\n' in s
PY
  pass "fm-ensure-agents-md: preserves a blank separator after a newline-less file"
}

test_crlf_preserved() {
  local repo="$TMP_ROOT/crlf"
  mkdir -p "$repo"
  printf '# Existing\r\n\r\nKeep this.\r\n' > "$repo/AGENTS.md"
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null
  python3 - "$repo/AGENTS.md" <<'PY'
from pathlib import Path
import sys
b=Path(sys.argv[1]).read_bytes()
assert b'## Maintaining this file\r\n' in b
assert b.replace(b'\r\n', b'').find(b'\n') == -1
PY
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null
  [ "$(LC_ALL=C grep -c $'## Maintaining this file\r' "$repo/AGENTS.md")" = 1 ] || fail "CRLF section duplicated"
  pass "fm-ensure-agents-md: preserves CRLF and remains idempotent"
}

test_case_variant_refused() {
  local repo="$TMP_ROOT/case"
  mkdir -p "$repo"
  printf '# wrong case\n' > "$repo/agents.md"
  if "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1; then
    fail "lowercase agents.md was accepted"
  fi
  [ "$(find "$repo" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 1 ] || fail "case refusal created another directory entry"
  grep -Fq '# wrong case' "$repo/agents.md" || fail "case refusal changed the existing file"
  pass "fm-ensure-agents-md: refuses a case-variant memory file"
}

test_agents_must_be_real_file() {
  local repo="$TMP_ROOT/real-file"
  mkdir -p "$repo"
  ln -s target "$repo/AGENTS.md"
  if "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1; then
    fail "AGENTS.md symlink was accepted"
  fi
  rm "$repo/AGENTS.md"
  mkdir "$repo/AGENTS.md"
  if "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null 2>&1; then
    fail "AGENTS.md directory was accepted"
  fi
  pass "fm-ensure-agents-md: requires AGENTS.md to be a real regular file"
}

test_unrelated_legacy_file_untouched() {
  local repo="$TMP_ROOT/legacy" before after
  mkdir -p "$repo"
  printf '# Unrelated legacy instructions\n\nDo not move me.\n' > "$repo/$LEGACY_NAME"
  before=$(shasum -a 256 "$repo/$LEGACY_NAME")
  "$ROOT/bin/fm-ensure-agents-md.sh" "$repo" >/dev/null
  after=$(shasum -a 256 "$repo/$LEGACY_NAME")
  [ "$before" = "$after" ] || fail "unrelated legacy memory file changed"
  [ -f "$repo/AGENTS.md" ] || fail "AGENTS.md was not created beside the unrelated file"
  [ ! -L "$repo/$LEGACY_NAME" ] || fail "unrelated legacy memory file became a symlink"
  pass "fm-ensure-agents-md: leaves an unrelated pre-existing legacy memory file untouched"
}

test_create_skeleton
test_existing_injection_and_idempotence
test_no_trailing_newline_separator
test_crlf_preserved
test_case_variant_refused
test_agents_must_be_real_file
test_unrelated_legacy_file_untouched
