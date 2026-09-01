#!/usr/bin/env bash
# Shared AGENTS.md creation, maintenance, conflict, and idempotence behavior.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ENSURE="$ROOT/bin/fm-ensure-agents-md.sh"
TMP=$(fm_test_tmproot fm-ensure-agents-md)

new_case() {
  local dir="$TMP/$1"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

assert_no_crlf() {
  ! LC_ALL=C grep -q $'\r$' "$1" || fail "$2"
}

case_dir=$(new_case fresh)
out=$($ENSURE "$case_dir")
assert_contains "$out" "created: AGENTS.md" "fresh setup should report creation"
assert_grep '# Project agent memory' "$case_dir/AGENTS.md" "fresh setup should create the knowledge owner"
assert_grep '## Maintaining this file' "$case_dir/AGENTS.md" "fresh setup should include self-governance"
[ ! -e "$case_dir/CLAUDE.md" ] || fail "fresh setup must not create retired harness memory"
pass "fm-ensure-agents-md: fresh setup creates only AGENTS.md with self-governance"

case_dir=$(new_case existing)
printf '# Existing\n\nUseful project fact.\n' > "$case_dir/AGENTS.md"
out=$($ENSURE "$case_dir")
assert_contains "$out" "updated: added ## Maintaining this file" "existing file should report maintenance update"
assert_grep 'Useful project fact.' "$case_dir/AGENTS.md" "existing content should survive"
[ "$(grep -Fc '## Maintaining this file' "$case_dir/AGENTS.md")" -eq 1 ] || fail "maintenance section should appear once"
out=$($ENSURE "$case_dir")
assert_contains "$out" "unchanged: AGENTS.md" "second pass should be idempotent"
[ "$(grep -Fc '## Maintaining this file' "$case_dir/AGENTS.md")" -eq 1 ] || fail "idempotent pass duplicated maintenance"
pass "fm-ensure-agents-md: existing AGENTS.md is updated idempotently"

case_dir=$(new_case no-final-newline)
printf '# Existing' > "$case_dir/AGENTS.md"
$ENSURE "$case_dir" >/dev/null
assert_grep '# Existing' "$case_dir/AGENTS.md" "unterminated content should survive"
awk 'NR == 2 { exit($0 == "" ? 0 : 1) }' "$case_dir/AGENTS.md" || fail "maintenance section needs a blank separator"
pass "fm-ensure-agents-md: unterminated content receives a blank separator"

case_dir=$(new_case crlf)
printf '# Existing\r\n' > "$case_dir/AGENTS.md"
$ENSURE "$case_dir" >/dev/null
LC_ALL=C grep -q $'## Maintaining this file\r$' "$case_dir/AGENTS.md" || fail "CRLF file lost its line ending"
python3 - "$case_dir/AGENTS.md" <<'PY' || fail "CRLF update introduced mixed line endings"
import pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_bytes()
raise SystemExit(0 if b"\n" not in raw.replace(b"\r\n", b"") else 1)
PY
pass "fm-ensure-agents-md: CRLF line endings are preserved"

case_dir=$(new_case legacy-memory)
printf '# Legacy project memory\n\nKeep this durable fact.\n' > "$case_dir/CLAUDE.md"
if out=$($ENSURE "$case_dir" 2>&1); then fail "legacy project memory should be refused without explicit reconciliation"; fi
assert_contains "$out" "CLAUDE.md contains legacy project memory" "legacy-memory refusal should name the conflict"
assert_absent "$case_dir/AGENTS.md" "legacy-memory refusal must not create unrelated project memory"
assert_grep 'Keep this durable fact.' "$case_dir/CLAUDE.md" "legacy-memory refusal must preserve existing knowledge"
pass "fm-ensure-agents-md: legacy-only project memory is preserved and refused"

case_dir=$(new_case divergent-memory)
printf '# Current project memory\n\nKeep the current fact.\n' > "$case_dir/AGENTS.md"
printf '# Legacy project memory\n\nKeep the legacy fact.\n' > "$case_dir/CLAUDE.md"
cp "$case_dir/AGENTS.md" "$case_dir/agents.before"
cp "$case_dir/CLAUDE.md" "$case_dir/claude.before"
if out=$($ENSURE "$case_dir" 2>&1); then fail "divergent project memory should be refused without explicit reconciliation"; fi
assert_contains "$out" "CLAUDE.md contains legacy project memory" "divergent-memory refusal should name the conflict"
cmp -s "$case_dir/agents.before" "$case_dir/AGENTS.md" || fail "divergent-memory refusal modified AGENTS.md"
cmp -s "$case_dir/claude.before" "$case_dir/CLAUDE.md" || fail "divergent-memory refusal modified CLAUDE.md"
pass "fm-ensure-agents-md: divergent current and legacy memory is preserved and refused"

case_dir=$(new_case canonical-pointer)
printf '# Current project memory\n' > "$case_dir/AGENTS.md"
cat > "$case_dir/CLAUDE.md" <<'EOF'
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
EOF
cp "$case_dir/CLAUDE.md" "$case_dir/claude.before"
out=$($ENSURE "$case_dir")
assert_contains "$out" "updated: added ## Maintaining this file" "canonical pointer should permit AGENTS.md maintenance"
cmp -s "$case_dir/claude.before" "$case_dir/CLAUDE.md" || fail "canonical pointer was modified"
pass "fm-ensure-agents-md: canonical real pointer remains supported"

case_dir=$(new_case pointer-only)
cat > "$case_dir/CLAUDE.md" <<'EOF'
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
EOF
cp "$case_dir/CLAUDE.md" "$case_dir/claude.before"
out=$($ENSURE "$case_dir")
assert_contains "$out" "created: AGENTS.md" "canonical pointer should permit fresh AGENTS.md creation"
cmp -s "$case_dir/claude.before" "$case_dir/CLAUDE.md" || fail "pointer-only setup modified CLAUDE.md"
assert_grep '## Maintaining this file' "$case_dir/AGENTS.md" "pointer-only setup should create maintained AGENTS.md"
pass "fm-ensure-agents-md: canonical pointer supports fresh creation"

case_dir=$(new_case correct-symlink)
printf '# Current project memory\n' > "$case_dir/AGENTS.md"
ln -s AGENTS.md "$case_dir/CLAUDE.md"
out=$($ENSURE "$case_dir")
assert_contains "$out" "updated: added ## Maintaining this file" "correct symlink should permit AGENTS.md maintenance"
[ -L "$case_dir/CLAUDE.md" ] || fail "correct CLAUDE.md symlink was replaced"
[ "$(readlink "$case_dir/CLAUDE.md")" = 'AGENTS.md' ] || fail "correct CLAUDE.md symlink was retargeted"
pass "fm-ensure-agents-md: correct symlink pointer remains supported"

case_dir=$(new_case dangling-correct-symlink)
ln -s AGENTS.md "$case_dir/CLAUDE.md"
out=$($ENSURE "$case_dir")
assert_contains "$out" "created: AGENTS.md" "correct dangling pointer should permit fresh AGENTS.md creation"
[ -L "$case_dir/CLAUDE.md" ] || fail "correct dangling CLAUDE.md symlink was replaced"
[ "$(readlink "$case_dir/CLAUDE.md")" = 'AGENTS.md' ] || fail "correct dangling CLAUDE.md symlink was retargeted"
pass "fm-ensure-agents-md: dangling correct symlink supports fresh creation"

case_dir=$(new_case wrong-symlink)
printf '# Current project memory\n' > "$case_dir/AGENTS.md"
printf '# Other memory\n' > "$case_dir/OTHER.md"
ln -s OTHER.md "$case_dir/CLAUDE.md"
cp "$case_dir/AGENTS.md" "$case_dir/agents.before"
if out=$($ENSURE "$case_dir" 2>&1); then fail "wrong CLAUDE.md symlink should be refused"; fi
assert_contains "$out" "does not point to AGENTS.md" "wrong symlink refusal should name the conflict"
cmp -s "$case_dir/agents.before" "$case_dir/AGENTS.md" || fail "wrong symlink refusal modified AGENTS.md"
[ "$(readlink "$case_dir/CLAUDE.md")" = 'OTHER.md' ] || fail "wrong symlink refusal modified CLAUDE.md"
pass "fm-ensure-agents-md: wrong symlink is preserved and refused"

case_dir=$(new_case agents-symlink)
printf '# target\n' > "$case_dir/target"
ln -s target "$case_dir/AGENTS.md"
if out=$($ENSURE "$case_dir" 2>&1); then fail "AGENTS.md symlink should be refused"; fi
assert_contains "$out" "AGENTS.md is a symlink" "symlink refusal should name the conflict"
pass "fm-ensure-agents-md: AGENTS.md symlinks are refused"

case_dir=$(new_case agents-directory)
mkdir "$case_dir/AGENTS.md"
if out=$($ENSURE "$case_dir" 2>&1); then fail "AGENTS.md directory should be refused"; fi
assert_contains "$out" "not a regular file" "non-regular refusal should name the conflict"
pass "fm-ensure-agents-md: non-regular AGENTS.md is refused"

case_dir=$(new_case lowercase)
printf '# wrong case\n' > "$case_dir/agents.md"
if out=$($ENSURE "$case_dir" 2>&1); then fail "case-variant AGENTS.md should be refused"; fi
assert_contains "$out" "memory file is named agents.md" "case conflict should name the file"
[ "$(cat "$case_dir/agents.md")" = '# wrong case' ] || fail "case conflict should not modify the existing file"
pass "fm-ensure-agents-md: case-variant memory names are refused portably"

out=$($ENSURE --help 2>&1)
assert_contains "$out" "usage: fm-ensure-agents-md.sh" "help should document the interface"
pass "fm-ensure-agents-md: help remains available"
