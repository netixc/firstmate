#!/usr/bin/env bash
# Pi session-lock identity tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-session-lock-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-session-lock-pi)

test_pi_matcher_is_narrow() {
  fm_pi_process_matches /usr/local/bin/pi 'pi --model openai-codex/gpt-5.6-luna' \
    || fail "exact Pi command was not recognized"
  fm_pi_process_matches /usr/local/bin/node '/opt/pi-coding-agent/dist/pi.js' \
    || fail "Pi node entrypoint was not recognized"
  if fm_pi_process_matches /usr/local/bin/bash 'bash /tmp/worker'; then
    fail "ordinary shell was recognized as Pi"
  fi
  pass "session lock recognizes only Pi process identities"
}

test_pi_ancestry_and_liveness() {
  local fakebin="$TMP_ROOT/fakebin" result
  mkdir -p "$fakebin"
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
field= pid=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$pid:$field" in
  *:comm=) printf '%s\n' /usr/local/bin/pi ;;
  *:args=) printf '%s\n' 'pi --model test/model' ;;
  *:ppid=) printf '%s\n' 1 ;;
esac
SH
  chmod +x "$fakebin/ps"
  result=$(PATH="$fakebin:$PATH" bash -c '
    . "$1"
    kill() { return 0; }
    fm_harness_pid_alive 4242 || exit 1
    fm_harness_ancestry_pid
  ' _ "$ROOT/bin/fm-session-lock-lib.sh")
  case "$result" in ''|*[!0-9]*) fail "Pi ancestry did not select a process id: $result" ;; esac
  pass "session lock ancestry and liveness use Pi identity"
}

test_pi_matcher_is_narrow
test_pi_ancestry_and_liveness
