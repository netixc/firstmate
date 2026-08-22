#!/usr/bin/env bash
# Portable Pi session-lock ancestry contract.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-session-lock-ancestry)
LIB="$ROOT/bin/fm-session-lock-lib.sh"
FM_TEST_READLINK=$(command -v readlink)
export FM_TEST_READLINK

lib_eval() {  # <fakebin> <expression>
  local fakebin=$1 expr=$2
  FM_TEST_PI_BIN="$fakebin" PATH="$fakebin:$PATH" bash -c '
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
  falsepath:*:comm=) printf '%s\n' /tmp/pi/not-agent ;;
  falsepath:*:args=) printf '%s\n' /tmp/pi/not-agent ;;
  falsepath:*:ppid=) printf '%s\n' 1 ;;
  falsearg:*:comm=) printf '%s\n' /usr/bin/node ;;
  falsearg:*:args=) printf '%s\n' '/usr/bin/node /tmp/runner.js pi' ;;
  falsearg:*:ppid=) printf '%s\n' 1 ;;
  falseargv0:*:comm=) printf '%s\n' /usr/bin/sleep ;;
  falseargv0:*:args=) printf '%s\n' pi ;;
  falseargv0:*:ppid=) printf '%s\n' 1 ;;
  falsedirect:*:comm=) printf '%s\n' /tmp/fake/pi ;;
  falsedirect:*:args=) printf '%s\n' /tmp/fake/pi ;;
  falsedirect:*:ppid=) printf '%s\n' 1 ;;
  falsebare:*:comm=) printf '%s\n' pi ;;
  falsebare:*:args=) printf '%s\n' pi ;;
  falsebare:*:ppid=) printf '%s\n' 1 ;;
  pathpi:*:comm=) printf '%s\n' pi ;;
  pathpi:*:args=) printf '%s\n' pi ;;
  pathpi:*:ppid=) printf '%s\n' 1 ;;
  nodescript:*:comm=) printf '%s\n' /usr/bin/node ;;
  nodescript:*:args=) printf '/usr/bin/node %s/pi\n' "$FM_TEST_PI_BIN" ;;
  nodescript:*:ppid=) printf '%s\n' 1 ;;
  pi:700:comm=|nested:700:comm=|gap:700:comm=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  pi:700:args=|nested:700:args=|gap:700:args=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  pi:700:ppid=) printf '%s\n' 1 ;;
  nested:700:ppid=) printf '%s\n' 710 ;;
  nested:710:comm=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  nested:710:args=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  nested:710:ppid=) printf '%s\n' 1 ;;
  gap:700:ppid=) printf '%s\n' 710 ;;
  gap:710:comm=) printf '%s\n' bash ;;
  gap:710:args=) printf '%s\n' 'bash tests/run.sh' ;;
  gap:710:ppid=) printf '%s\n' 720 ;;
  gap:720:comm=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  gap:720:args=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  gap:720:ppid=) printf '%s\n' 1 ;;
  competitor:600:comm=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  competitor:600:args=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  competitor:600:ppid=) printf '%s\n' 1 ;;
  competitor:650:comm=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  competitor:650:args=) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  competitor:650:ppid=) printf '%s\n' 1 ;;
  *:comm=) printf '%s\n' bash ;;
  *:args=) printf '%s\n' 'bash tests/run.sh' ;;
  pi:*:ppid=*|nested:*:ppid=*|gap:*:ppid=*) printf '%s\n' 700 ;;
  competitor:*:ppid=*) printf '%s\n' 650 ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$fakebin/ps"
  cat > "$fakebin/readlink" <<'SH'
#!/usr/bin/env bash
set -u
case "${FM_TEST_SHAPE:-}:$1" in
  pathpi:/proc/*/exe) printf '%s/pi\n' "$FM_TEST_PI_BIN" ;;
  falsebare:/proc/*/exe) printf '%s\n' /tmp/fake/pi ;;
  *) exec "$FM_TEST_READLINK" "$@" ;;
esac
SH
  chmod +x "$fakebin/readlink"
  cat > "$fakebin/pi" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin/pi"
  printf '%s' "$fakebin"
}

test_pi_owns_lock() {
  local dir fakebin got
  dir="$TMP_ROOT/pi"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" pi)
  got=$(FM_TEST_SHAPE=pi lib_eval "$fakebin" 'fm_pi_ancestry_pid') || fail "Pi ancestry was not found"
  [ "$got" = 700 ] || fail "Pi ancestry resolved $got instead of 700"
  printf '700\n' > "$dir/state/.lock"
  FM_TEST_SHAPE=pi lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'" || fail "Pi did not own its exact lock"
  pass "session-lock: Pi ancestry owns its exact lock"
}

test_nested_pi_process_keeps_inner_owner() {
  local dir fakebin got
  dir="$TMP_ROOT/nested"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" nested)
  got=$(FM_TEST_SHAPE=nested lib_eval "$fakebin" 'fm_pi_ancestry_pid') || fail "nested Pi ancestry was not found"
  [ "$got" = 700 ] || fail "Pi must select the inner process pid 700, got $got"
  printf '700\n' > "$dir/state/.lock"
  FM_TEST_SHAPE=nested lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'" || fail "inner Pi process did not own the lock"
  printf '710\n' > "$dir/state/.lock"
  if FM_TEST_SHAPE=nested lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "outer Pi process incorrectly replaced the exact inner owner"
  fi
  pass "session-lock: nested Pi ancestry preserves the exact inner owner"
}

test_gap_stops_ancestry() {
  local dir fakebin got
  dir="$TMP_ROOT/gap"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" gap)
  got=$(FM_TEST_SHAPE=gap lib_eval "$fakebin" 'fm_pi_ancestry_pid') || fail "inner Pi ancestry was not found"
  [ "$got" = 700 ] || fail "ancestry crossed a non-Pi gap: $got"
  printf '720\n' > "$dir/state/.lock"
  if FM_TEST_SHAPE=gap lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "a Pi process beyond a non-Pi gap claimed the lock"
  fi
  pass "session-lock: ancestry never crosses a non-Pi gap"
}

test_live_competitor_is_not_self() {
  local dir fakebin
  dir="$TMP_ROOT/competitor"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" competitor)
  printf '600\n' > "$dir/state/.lock"
  if FM_TEST_SHAPE=competitor lib_eval "$fakebin" "fm_session_lock_owned_by_self '$dir/state'"; then
    fail "a competing Pi session claimed this process's lock"
  fi
  FM_TEST_SHAPE=competitor lib_eval "$fakebin" 'fm_pi_pid_alive 600' || fail "live pi competitor was classified dead"
  pass "session-lock: a live competing pi session is live but never self"
}

test_public_lock_requires_exact_pi_identity() {
  local shape dir fakebin out rc
  for shape in falsepath falsearg falseargv0 falsedirect falsebare; do
    dir="$TMP_ROOT/$shape"; mkdir -p "$dir/state"
    fakebin=$(make_ps "$dir" "$shape")
    rc=0
    out=$(FM_TEST_SHAPE="$shape" FM_TEST_PI_BIN="$fakebin" \
      FM_STATE_OVERRIDE="$dir/state" PATH="$fakebin:$PATH" \
      "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
    [ "$rc" -ne 0 ] || fail "fm-lock accepted unrelated process shape $shape as Pi"
    assert_contains "$out" "cannot locate Pi process in ancestry" \
      "fm-lock did not clearly refuse unrelated process shape $shape"
    [ ! -e "$dir/state/.lock" ] || fail "fm-lock published ownership for unrelated process shape $shape"
  done
  dir="$TMP_ROOT/nodescript"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" nodescript)
  out=$(FM_TEST_SHAPE=nodescript FM_TEST_PI_BIN="$fakebin" \
    FM_STATE_OVERRIDE="$dir/state" PATH="$fakebin:$PATH" \
    "$ROOT/bin/fm-lock.sh" 2>&1) || fail "fm-lock refused the exact installed Pi script identity: $out"
  assert_contains "$out" "lock acquired: Pi pid" "fm-lock did not admit the exact Pi script identity"
  dir="$TMP_ROOT/pathpi"; mkdir -p "$dir/state"
  fakebin=$(make_ps "$dir" pathpi)
  out=$(FM_TEST_SHAPE=pathpi FM_TEST_PI_BIN="$fakebin" \
    FM_STATE_OVERRIDE="$dir/state" PATH="$fakebin:$PATH" \
    "$ROOT/bin/fm-lock.sh" 2>&1) || fail "fm-lock refused Pi launched through PATH: $out"
  assert_contains "$out" "lock acquired: Pi pid" "fm-lock did not admit Pi through OS executable identity"
  pass "session-lock: public admission requires the exact Pi executable identity"
}

test_public_lock_refuses_tmux_before_state_creation() {
  local dir fakebin out rc=0
  dir="$TMP_ROOT/tmux-refusal"
  mkdir -p "$dir"
  fakebin=$(make_ps "$dir" pathpi)
  out=$(TMUX=fake FM_TEST_SHAPE=pathpi FM_TEST_PI_BIN="$fakebin" \
    FM_STATE_OVERRIDE="$dir/state" PATH="$fakebin:$PATH" \
    "$ROOT/bin/fm-lock.sh" 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "fm-lock accepted an explicit tmux environment"
  assert_contains "$out" "tmux session execution is retired" \
    "fm-lock did not clearly refuse the explicit tmux environment"
  [ ! -e "$dir/state" ] || fail "fm-lock created state before refusing tmux"
  pass "session-lock: explicit tmux environment refuses before state creation"
}

test_pi_owns_lock
test_nested_pi_process_keeps_inner_owner
test_gap_stops_ancestry
test_live_competitor_is_not_self
test_public_lock_requires_exact_pi_identity
test_public_lock_refuses_tmux_before_state_creation
