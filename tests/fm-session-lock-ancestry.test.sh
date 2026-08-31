#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$ROOT/bin/fm-session-lock-lib.sh"

fm_harness_process_matches /opt/homebrew/bin/pi /opt/homebrew/bin/pi \
  || fail "plain Pi process not recognized"
pass "exact plain Pi process is recognized"

if fm_harness_process_matches sleep 'pi 60'; then
  fail "mutable argv0 authorized a non-Pi process"
fi
pass "mutable argv0 cannot authorize a non-Pi process"

for path in \
  /usr/local/bin/pi-launcher \
  /tmp/pi/bash \
  /Applications/Pi \
  /usr/bin/claude \
  /usr/bin/codex \
  /usr/bin/pi-signed \
  /usr/bin/grok \
  /usr/bin/kimi \
  /usr/bin/muse \
  /usr/bin/cursor-agent
do
  if fm_harness_process_matches "$path" "$path"; then
    fail "excluded process recognized: $path"
  fi
  pass "excluded process remains unsupported: $path"
done

if (
  ps() {
    local pid=${!#}
    case "$pid:$*" in
      200:*comm=*) printf 'pi\n' ;;
      200:*args=*) printf 'pi\n' ;;
      200:*ppid=*) printf '300\n' ;;
      300:*comm=*) printf 'pi-signed\n' ;;
      300:*args=*) printf 'pi-signed\n' ;;
      300:*ppid=*) printf '1\n' ;;
      *:*comm=*) printf 'bash\n' ;;
      *:*args=*) printf 'bash\n' ;;
      *:*ppid=*) printf '200\n' ;;
    esac
  }
  fm_harness_ancestry_pids >/dev/null
); then
  fail "excluded wrapper ancestry authorized an inner Pi process"
fi
pass "excluded wrapper ancestry cannot authorize an inner Pi process"
