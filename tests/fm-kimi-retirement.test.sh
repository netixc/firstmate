#!/usr/bin/env bash
# Compatibility tests for retiring Firstmate-owned standalone Kimi artifacts.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CLEANUP="$ROOT/bin/fm-retired-kimi-cleanup.sh"
BOOTSTRAP="$ROOT/bin/fm-bootstrap.sh"
LAB=$(fm_test_tmproot fm-kimi-retirement)
trap 'rm -rf "$LAB"' EXIT

write_generated_hook() {  # <home>
  local home=$1
  cat > "$home/.kimi-code/fm-turn-end.sh" <<'SH'
#!/usr/bin/env bash
# Firstmate Kimi turn-end hook. Managed by fm-kimi-turnend-hook.sh.
# This hook is deliberately passive: every path is silent and exits zero.
set +e
exec >/dev/null 2>&1
payload=
IFS= read -r payload || [ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
workspace=$(jq -er 'select(.hook_event_name == "Stop") | .cwd | strings | select(length > 0)' <<< "$payload" 2>/dev/null) || exit 0
pointer="$workspace/.fm-kimi-turnend"
[ -f "$pointer" ] || exit 0
first=
IFS= read -r -n 256 first < "$pointer" 2>/dev/null || [ -n "$first" ] || exit 0
case "$first" in token=*) token=${first#token=} ;; *) exit 0 ;; esac
case "$token" in fm.????????????) : ;; *) exit 0 ;; esac
case "$token" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
auth_dir=${HOME:-}/.kimi-code/fm-turn-end.d
[ -n "${HOME:-}" ] || exit 0
target=$(cat "$auth_dir/$token" 2>/dev/null) || exit 0
case "$target" in /*.turn-ended) : ;; *) exit 0 ;; esac
touch -- "$target" 2>/dev/null || true
exit 0
SH
  chmod 700 "$home/.kimi-code/fm-turn-end.sh"
}

write_config_with_owned_region() {  # <home> <expected-file>
  local home=$1 expected=$2
  cat > "$home/.kimi-code/config.toml" <<'TOML'
default_model = "keep-byte-for-byte"

[[hooks]]
event = "Custom"
command = "printf user-hook"

# BEGIN FIRSTMATE KIMI TURN-END HOOK
[[hooks]]
event = "Stop"
matcher = "^$"
command = "bash \"$HOME/.kimi-code/fm-turn-end.sh\" >/dev/null 2>&1 || true"
timeout = 1
# END FIRSTMATE KIMI TURN-END HOOK

[display]
theme = "captain"
TOML
  cat > "$expected" <<'TOML'
default_model = "keep-byte-for-byte"

[[hooks]]
event = "Custom"
command = "printf user-hook"


[display]
theme = "captain"
TOML
}

make_home() {  # <name>
  local home="$LAB/$1"
  mkdir -p "$home/.kimi-code" "$home/state" "$home/data" "$home/config" "$home/projects"
  printf '%s\n' "$home"
}

test_cleanup_preserves_external_config_bytes_and_removes_orphans() {
  local home expected token target
  home=$(make_home clean)
  expected="$home/expected.toml"
  write_config_with_owned_region "$home" "$expected"
  write_generated_hook "$home"
  mkdir -p "$home/.kimi-code/fm-turn-end.d"
  token=fm.123456789012
  target="$home/state/orphan.turn-ended"
  printf '%s\n' "$target" > "$home/.kimi-code/fm-turn-end.d/$token"

  HOME="$home" "$CLEANUP" || fail "retired Kimi cleanup refused exact owned artifacts"
  cmp -s "$expected" "$home/.kimi-code/config.toml" \
    || fail "retired Kimi cleanup changed external config bytes outside its owned region"
  assert_absent "$home/.kimi-code/fm-turn-end.sh" "retired Kimi cleanup left the generated hook"
  assert_absent "$home/.kimi-code/fm-turn-end.d" "retired Kimi cleanup left the orphan registry"
  pass "retired Kimi cleanup byte-preserves external TOML and removes only exact orphan artifacts"
}

test_cleanup_refuses_task_bound_token_without_mutation() {
  local home expected token target out rc=0
  home=$(make_home active)
  expected="$home/expected.toml"
  write_config_with_owned_region "$home" "$expected"
  write_generated_hook "$home"
  mkdir -p "$home/.kimi-code/fm-turn-end.d"
  token=fm.abcdefghijkl
  target="$home/state/live.turn-ended"
  printf '%s\n' "$target" > "$home/.kimi-code/fm-turn-end.d/$token"
  printf 'harness=kimi\n' > "$home/state/live.meta"
  cp "$home/.kimi-code/config.toml" "$home/config.before"
  cp "$home/.kimi-code/fm-turn-end.sh" "$home/hook.before"
  cp "$home/.kimi-code/fm-turn-end.d/$token" "$home/token.before"

  out=$(HOME="$home" "$CLEANUP" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "retired Kimi cleanup removed a task-bound token"
  assert_contains "$out" "task records exist" "task-bound refusal omitted its reason"
  cmp -s "$home/config.before" "$home/.kimi-code/config.toml" \
    || fail "task-bound refusal changed external config"
  cmp -s "$home/hook.before" "$home/.kimi-code/fm-turn-end.sh" \
    || fail "task-bound refusal changed the generated hook"
  cmp -s "$home/token.before" "$home/.kimi-code/fm-turn-end.d/$token" \
    || fail "task-bound refusal changed the registry token"
  pass "retired Kimi cleanup preserves every artifact while a task record still owns a token"
}

test_cleanup_preserves_cross_home_registry_entries() {
  local home other current_token current_target foreign_token foreign_target
  home=$(make_home cross-home)
  other="$LAB/other-home"
  mkdir -p "$other/state"
  write_config_with_owned_region "$home" "$home/expected.toml"
  mkdir -p "$home/.kimi-code/fm-turn-end.d"
  current_token=fm.123456789012
  foreign_token=fm.abcdefghijkl
  printf '%s\n' "$current_token" > "$home/state/current.kimi-turnend-token"
  current_target="$home/state/current.turn-ended"
  printf '%s\n' "$current_target" > "$home/.kimi-code/fm-turn-end.d/$current_token"
  foreign_target="$other/state/foreign.turn-ended"
  printf '%s\n' "$foreign_target" > "$home/.kimi-code/fm-turn-end.d/$foreign_token"

  HOME="$home" "$CLEANUP" || fail "retired Kimi cleanup refused current-home orphan cleanup"
  assert_absent "$home/.kimi-code/fm-turn-end.d/$current_token" "current-home orphan token was not removed"
  assert_present "$home/.kimi-code/fm-turn-end.d/$foreign_token" "cross-home registry token was removed"
  pass "retired Kimi cleanup preserves registry entries belonging to another home"
}

test_cleanup_refuses_unexpected_external_files() {
  local home expected out rc=0
  home=$(make_home unexpected)
  expected="$home/expected.toml"
  write_config_with_owned_region "$home" "$expected"
  printf '%s\n' '# user-owned replacement' > "$home/.kimi-code/fm-turn-end.sh"
  cp "$home/.kimi-code/config.toml" "$home/config.before"
  cp "$home/.kimi-code/fm-turn-end.sh" "$home/hook.before"

  out=$(HOME="$home" "$CLEANUP" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "retired Kimi cleanup deleted an unexpected hook file"
  assert_contains "$out" "unexpected content" "unexpected-hook refusal omitted its reason"
  cmp -s "$home/config.before" "$home/.kimi-code/config.toml" \
    || fail "unexpected-hook refusal changed external config"
  cmp -s "$home/hook.before" "$home/.kimi-code/fm-turn-end.sh" \
    || fail "unexpected-hook refusal changed the user-owned file"
  pass "retired Kimi cleanup refuses surprising external files without mutation"
}

test_cleanup_refuses_symlinked_root_and_malformed_markers() {
  local home target out rc

  home=$(make_home symlink-root)
  target="$home/external-kimi"
  mkdir -p "$target"
  rmdir "$home/.kimi-code"
  ln -s "$target" "$home/.kimi-code"
  printf '%s\n' 'external bytes' > "$target/config.toml"
  rc=0
  out=$(HOME="$home" "$CLEANUP" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "retired Kimi cleanup followed a symlinked config root"
  assert_contains "$out" "config root is not a regular directory" "symlinked-root refusal omitted its reason"
  [ "$(cat "$target/config.toml")" = "external bytes" ] \
    || fail "symlinked-root refusal changed external config"

  home=$(make_home malformed-markers)
  cat > "$home/.kimi-code/config.toml" <<'TOML'
keep = "exact"
# BEGIN FIRSTMATE KIMI TURN-END HOOK
# END FIRSTMATE KIMI TURN-END HOOK
# END FIRSTMATE KIMI TURN-END HOOK
TOML
  cp "$home/.kimi-code/config.toml" "$home/config.before"
  rc=0
  out=$(HOME="$home" "$CLEANUP" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "retired Kimi cleanup accepted malformed ownership markers"
  assert_contains "$out" "partial, duplicated, or altered" "malformed-marker refusal omitted its reason"
  cmp -s "$home/config.before" "$home/.kimi-code/config.toml" \
    || fail "malformed-marker refusal changed external config"
  pass "retired Kimi cleanup refuses symlinked roots and malformed ownership markers without mutation"
}

test_bootstrap_runs_cleanup_only_with_mutation_authority() {
  local home expected out
  home=$(make_home bootstrap)
  expected="$home/expected.toml"
  write_config_with_owned_region "$home" "$expected"
  write_generated_hook "$home"
  cp "$home/.kimi-code/config.toml" "$home/config.before"

  out=$(HOME="$home" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    FM_BOOTSTRAP_NETWORK=skip FM_BOOTSTRAP_DETECT_ONLY=1 "$BOOTSTRAP" 2>&1) \
    || fail "detect-only bootstrap failed: $out"
  cmp -s "$home/config.before" "$home/.kimi-code/config.toml" \
    || fail "detect-only bootstrap changed external Kimi config"
  assert_present "$home/.kimi-code/fm-turn-end.sh" "detect-only bootstrap removed the generated hook"

  out=$(HOME="$home" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
    FM_BOOTSTRAP_NETWORK=skip "$BOOTSTRAP" 2>&1) \
    || fail "mutable bootstrap failed: $out"
  cmp -s "$expected" "$home/.kimi-code/config.toml" \
    || fail "mutable bootstrap did not run byte-preserving retired Kimi cleanup"
  assert_absent "$home/.kimi-code/fm-turn-end.sh" "mutable bootstrap left the generated hook"
  pass "bootstrap retires old Kimi global artifacts only on its mutation-authorized path"
}

test_cleanup_preserves_external_config_bytes_and_removes_orphans
test_cleanup_refuses_task_bound_token_without_mutation
test_cleanup_preserves_cross_home_registry_entries
test_cleanup_refuses_unexpected_external_files
test_cleanup_refuses_symlinked_root_and_malformed_markers
test_bootstrap_runs_cleanup_only_with_mutation_authority

echo "# all retired Kimi cleanup tests passed"
