#!/usr/bin/env bash
# Pi semantic busy-state tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-busy-pi)
EV="$ROOT/bin/fm-busy-event.sh"

new_state() {
  local state="$TMP_ROOT/$1/state"
  mkdir -p "$state"
  printf '%s\n' "$state"
}

test_pi_busy_lifecycle() {
  local state gen out
  state=$(new_state lifecycle)
  gen=$("$EV" arm "$state" worker)
  out=$(fm_busy_classify herdr endpoint pi worker "$state")
  [ "$out" = 'busy fm-spawn' ] || fail "Pi launch busy state wrong: $out"
  "$EV" apply "$state" worker idle --gen "$gen" --source pi-ext --event agent-settled || fail "Pi idle event failed"
  out=$(fm_busy_classify herdr endpoint pi worker "$state")
  [ "$out" = 'idle pi-ext' ] || fail "Pi idle state wrong: $out"
  "$EV" apply "$state" worker busy --gen "$gen" --source pi-ext --event agent-start || fail "Pi busy event failed"
  out=$(fm_busy_classify herdr endpoint pi worker "$state")
  [ "$out" = 'busy pi-ext' ] || fail "Pi busy state wrong: $out"
  pass "Pi extension lifecycle records are generation-bound and trusted"
}

test_pi_unknown_safety() {
  local state gen out
  state=$(new_state unknown)
  out=$(fm_busy_classify herdr endpoint pi worker "$state")
  [ "$out" = 'unknown missing' ] || fail "missing Pi state was not unknown: $out"
  gen=$("$EV" arm "$state" worker)
  printf 'v1 gen=%s seq=not-a-number state=busy source=pi-ext event=agent-start ts=1\n' "$gen" > "$state/worker.busy-state"
  out=$(fm_busy_classify herdr endpoint pi worker "$state")
  [ "$out" = 'unknown malformed' ] || fail "malformed Pi state was not unknown: $out"
  out=$(fm_busy_classify herdr endpoint retired-runtime worker "$state")
  [ "$out" = 'unknown unsupported-runtime' ] || fail "retired runtime was not refused: $out"
  pass "missing, malformed, and retired runtime busy state stays unknown"
}

test_pi_interrupt_and_retire() {
  local state gen out
  state=$(new_state retire)
  gen=$("$EV" arm "$state" worker)
  "$EV" apply "$state" worker idle --current-gen --source fm-interrupt --event interrupt || fail "Pi interrupt state update failed"
  out=$(fm_busy_classify herdr endpoint pi worker "$state")
  [ "$out" = 'idle fm-interrupt' ] || fail "Pi interrupt state wrong: $out"
  "$EV" retire "$state" worker --gen "$gen" || fail "Pi busy state retire failed"
  [ ! -e "$state/worker.busy-state" ] || fail "retire left Pi busy record"
  [ ! -e "$state/worker.busy-gen" ] || fail "retire left Pi generation record"
  pass "Pi interrupt and cleanup use the fixed lifecycle contract"
}

test_pi_busy_lifecycle
test_pi_unknown_safety
test_pi_interrupt_and_retire
