#!/usr/bin/env bash
# Portable session-lock ancestry contract for surviving verified harnesses.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-session-lock-ancestry)
LIB="$ROOT/bin/fm-session-lock-lib.sh"

lib_eval() {  # <fakebin> <expression>
  local fakebin=$1 expr=$2
  PATH="$fakebin:$PATH" bash -c '
    . "$0"
    kill() { return 0; }
    eval "$1"
  ' "$LIB" "$expr"
}

make_ps() {  # <dir> <shape>
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
set -u
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "${FM_TEST_SHAPE:-pi}:$pid:$field" in
  pi:700:comm=|signed:700:comm=|gap:700:comm=) printf '%s\n' pi ;;
  pi:700:args=|signed:700:args=|gap:700:args=) printf '%s\n' pi ;;
  pi:700:ppid=) printf '%s\n' 1 ;;
  signed:700:ppid=) printf '%s\n' 710 ;;
  signed:710:comm=) printf '%s\n' pi-signed ;;
  signed:710:args=) printf '%s\n' pi-signed ;;
  signed:710:ppid=) printf '%s\n' 1 ;;
  gap:700:ppid=) printf '%s\n' 710 ;;
  gap:710:comm=) printf '%s\n' bash ;;
  gap:710:args=) printf '%s\n' 'bash tests/run.sh' ;;
  gap:710:ppid=) printf '%s\n' 720 ;;
  gap:720:comm=) printf '%s\n' codex ;;
  gap:720:args=) printf '%s\n' codex ;;
  gap:720:ppid=) printf '%s\n' 1 ;;
  competitor:600:comm=) printf '%s\n' pi-signed ;;
  competitor:600:args=) printf '%s\n' pi-signed ;;
  competitor:600:ppid=) printf '%s\n' 1 ;;
  competitor:650:comm=) printf '%s\n' pi ;;
  competitor:650:args=) printf '%s\n' pi ;;
  competitor:650:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' 'bash tests/run.sh' ;;
  pi:*:ppid=*|signed:*:ppid=*|gap:*:ppid=*) printf '%s\n' 700 ;;
  competitor:*:ppid=*) printf '%s\n' 650 ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '%s' "$fakebin"
}

test_pi_owns_lock() {
  local dir fakebin got
  dir="$TMP_ROOT/pi"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" pi)
  got=$(FM_TEST_SHAPE=pi lib_eval "$fakebin" 'fm_harness_ancestry_pid') || fail "Pi ancestry was not found"
  [ "$got" = 700 ] || fail "Pi ancestry resolved $got instead of 700"
  printf '700\n' > "$dir/state/.lock"
  FM_TEST_SHAPE=pi lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'" || fail "Pi did not own its exact lock"
  pass "session-lock: Pi ancestry owns its exact lock"
}

test_signed_wrapper_keeps_inner_engine_owner() {
  local dir fakebin got
  dir="$TMP_ROOT/signed"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" signed)
  got=$(FM_TEST_SHAPE=signed lib_eval "$fakebin" 'fm_harness_ancestry_pid') || fail "signed Pi ancestry was not found"
  [ "$got" = 700 ] || fail "signed Pi must select the inner engine pid 700, got $got"
  printf '700\n' > "$dir/state/.lock"
  FM_TEST_SHAPE=signed lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'" || fail "inner Pi engine did not own the lock"
  printf '710\n' > "$dir/state/.lock"
  if FM_TEST_SHAPE=signed lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "outer pi-signed wrapper incorrectly replaced the exact inner owner"
  fi
  pass "session-lock: pi-signed preserves the exact inner Pi engine owner"
}

test_gap_stops_ancestry() {
  local dir fakebin got
  dir="$TMP_ROOT/gap"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" gap)
  got=$(FM_TEST_SHAPE=gap lib_eval "$fakebin" 'fm_harness_ancestry_pid') || fail "inner Pi ancestry was not found"
  [ "$got" = 700 ] || fail "ancestry crossed a non-harness gap: $got"
  printf '720\n' > "$dir/state/.lock"
  if FM_TEST_SHAPE=gap lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "a harness beyond a non-harness gap claimed the lock"
  fi
  pass "session-lock: ancestry never crosses a non-harness gap"
}

test_live_competitor_is_not_self() {
  local dir fakebin
  dir="$TMP_ROOT/competitor"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" competitor)
  printf '600\n' > "$dir/state/.lock"
  if FM_TEST_SHAPE=competitor lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "a competing signed session claimed this process's lock"
  fi
  FM_TEST_SHAPE=competitor lib_eval "$fakebin" 'fm_harness_pid_alive 600' || fail "live pi-signed competitor was classified dead"
  pass "session-lock: a live competing pi-signed session is live but never self"
}

test_pi_owns_lock
test_signed_wrapper_keeps_inner_engine_owner
test_gap_stops_ancestry
test_live_competitor_is_not_self
