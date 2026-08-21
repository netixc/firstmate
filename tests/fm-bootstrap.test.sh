#!/usr/bin/env bash
# Bootstrap diagnostics for the sole Pi-and-Herdr session path.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BOOTSTRAP="$ROOT/bin/fm-bootstrap.sh"
TMP_ROOT=$(fm_test_tmproot fm-bootstrap)
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}

make_toolchain() { # <dir>
  local dir=$1 fb
  fb=$(fm_fakebin "$dir")
  fm_fake_exit0 "$fb" node ego-browser herdr
  fm_fake_version_tool "$fb" lavish-axi FM_FAKE_LAVISH_AXI_VERSION 0.1.46
  cat > "$fb/gh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat > "$fb/gh-axi" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != --version ] || printf '0.1.29\n'
exit 0
SH
  cat > "$fb/treehouse" <<'SH'
#!/usr/bin/env bash
[ "${1:-} ${2:-}" != 'get --help' ] || printf 'Usage: treehouse get [--lease]\n'
exit 0
SH
  cat > "$fb/no-mistakes" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != --version ] || printf 'no-mistakes version v1.31.2 (fake)\n'
exit 0
SH
  cat > "$fb/tasks-axi" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "--version ") printf '0.2.4\n' ;;
  "update --help") printf '%s\n' '--archive-body' ;;
  "mv --help") printf '%s\n' 'usage: tasks-axi mv <id> [<id>...]' ;;
esac
SH
  cat > "$fb/quota-axi" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != --version ] || printf 'quota-axi 0.1.25\n'
exit 0
SH
  chmod +x "$fb"/*
  printf '%s\n' "$fb"
}

new_home() { # <name>
  local home=$TMP_ROOT/$1/home
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects"
  printf '%s\n' "$home"
}

run_detect() { # <home> <fakebin>
  local home=$1 fb=$2
  env -u FM_BACKEND -u TMUX -u TMUX_PANE \
    PATH="$fb:$BASE_PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" \
    FM_BOOTSTRAP_DETECT_ONLY=1 "$BOOTSTRAP"
}

test_complete_toolchain_is_quiet() {
  local home fb out
  home=$(new_home quiet); fb=$(make_toolchain "$TMP_ROOT/quiet")
  out=$(run_detect "$home" "$fb")
  [ -z "$out" ] || fail "complete Pi+Herdr toolchain should be quiet: $out"
  pass "bootstrap accepts the complete Pi-and-Herdr toolchain silently"
}

test_missing_herdr_is_actionable() {
  local home fb out
  home=$(new_home missing-herdr); fb=$(make_toolchain "$TMP_ROOT/missing-herdr")
  rm -f "$fb/herdr"
  out=$(run_detect "$home" "$fb")
  assert_contains "$out" 'MISSING_MANUAL: herdr' "missing Herdr diagnostic absent"
  assert_contains "$out" 'https://herdr.dev' "missing Herdr diagnostic lacks setup owner"
  assert_not_contains "$out" 'MISSING: tmux' "missing Herdr fell back to tmux"
  pass "bootstrap requires Herdr directly and never substitutes tmux"
}

test_retired_and_unknown_selection_is_actionable() {
  local home fb out
  home=$(new_home invalid); fb=$(make_toolchain "$TMP_ROOT/invalid")
  printf 'tmux\n' > "$home/config/backend"
  out=$(run_detect "$home" "$fb")
  assert_contains "$out" 'SESSION_INVALID:' "retired config did not use the session diagnostic"
  assert_contains "$out" 'tmux session support is retired' "retired config refusal was not explicit"
  printf 'future-provider\n' > "$home/config/backend"
  out=$(run_detect "$home" "$fb")
  assert_contains "$out" "unsupported session selection 'future-provider'" "unknown config did not name its value"
  assert_contains "$out" 'Herdr is the only supported' "unknown config did not name the sole path"
  pass "bootstrap reports retired and unsupported selection without fallback"
}

test_tmux_environment_is_not_reinterpreted() {
  local home fb out
  home=$(new_home nested); fb=$(make_toolchain "$TMP_ROOT/nested")
  out=$(TMUX=fake PATH="$fb:$BASE_PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$home" \
    FM_BOOTSTRAP_DETECT_ONLY=1 "$BOOTSTRAP")
  assert_contains "$out" 'SESSION_INVALID:' "tmux environment did not stop bootstrap"
  assert_contains "$out" 'leave the tmux environment' "tmux environment refusal was not actionable"
  pass "bootstrap never reinterprets a tmux process as Herdr"
}

test_treehouse_requires_durable_leases() {
  local home fb out
  home=$(new_home lease); fb=$(make_toolchain "$TMP_ROOT/lease")
  cat > "$fb/treehouse" <<'SH'
#!/usr/bin/env bash
[ "${1:-} ${2:-}" != 'get --help' ] || printf 'Usage: treehouse get\n'
SH
  chmod +x "$fb/treehouse"
  out=$(run_detect "$home" "$fb")
  assert_contains "$out" 'MISSING: treehouse' "treehouse without durable leases was accepted"
  pass "bootstrap keeps Treehouse durable-lease isolation mandatory"
}

test_complete_toolchain_is_quiet
test_missing_herdr_is_actionable
test_retired_and_unknown_selection_is_actionable
test_tmux_environment_is_not_reinterpreted
test_treehouse_requires_durable_leases
