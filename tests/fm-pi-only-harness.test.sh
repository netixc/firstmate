#!/usr/bin/env bash
# Public-interface regression for exact plain Pi identity and migration refusal.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP=$(fm_test_tmproot fm-pi-only-harness)
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"; pass "$3"; }
mkdir -p "$TMP/config" "$TMP/state"
HARNESS="$ROOT/bin/fm-harness.sh"

[ ! -e "$ROOT/bin/fm-vendor-auth-probe.sh" ] \
  || fail "retired standalone vendor credential probe remains installed"
pass "retired standalone vendor credential probe is absent"

assert_eq pi "$(PI_CODING_AGENT=true FM_HOME="$TMP" "$HARNESS")" "Pi marker resolves to plain pi"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
  printf '%s\n' "$old" > "$TMP/config/crew-harness"
  set +e
  out=$(PI_CODING_AGENT=true FM_HOME="$TMP" "$HARNESS" crew 2>&1)
  rc=$?
  set -e
  assert_eq 2 "$rc" "$old configuration is rejected"
  assert_contains "$out" "unsupported harness" "$old reports migration"
done
printf 'pi\n' > "$TMP/config/crew-harness"
assert_eq pi "$(FM_HOME="$TMP" "$HARNESS" crew)" "explicit plain Pi resolves"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-control-lib.sh"
fm_control_harness_supported pi || fail "plain Pi control is supported"
pass "plain Pi control is supported"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
  if fm_control_harness_supported "$old"; then fail "$old control metadata is unsupported"; fi
  pass "$old control metadata is unsupported"
done
assert_eq Escape "$(fm_control_interrupt_key pi)" "Pi interrupt key"
assert_eq /quit "$(fm_control_exit_command pi)" "Pi exit command"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"
printf 'generation\n' > "$TMP/state/task.busy-gen"
printf 'v1 gen=generation seq=1 state=idle source=pi-ext event=agent-settled ts=1\n' > "$TMP/state/task.busy-state"
assert_eq 'idle pi-ext' "$(fm_busy_classify tmux target pi task "$TMP/state")" "Pi semantic state is accepted"
assert_eq 'unknown unsupported-harness' "$(fm_busy_classify tmux target pi-signed task "$TMP/state")" "old metadata is not normalized"
