#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$ROOT/bin/fm-session-lock-lib.sh"

if fm_harness_process_matches pi pi /tmp/pi; then
  fail "arbitrary native binary named pi was recognized"
fi
pass "arbitrary native binary named pi is not trusted"

if fm_harness_process_matches sleep 'pi 60' /bin/sleep; then
  fail "mutable argv0 authorized a non-Pi process"
fi
pass "mutable argv0 cannot authorize a non-Pi process"
if fm_harness_process_matches pi 'pi' /usr/bin/node; then
  fail "mutable Node process title authorized a non-Pi process"
fi
pass "mutable Node process title cannot authorize a non-Pi process"
if fm_harness_process_matches pi pi /usr/bin/node /opt/pi-coding-agent/addon.node; then
  fail "a mapped Pi addon authorized an unregistered Node process"
fi
pass "a mapped Pi addon cannot replace Pi lifecycle registration"

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

if (
  ps() {
    local pid=${!#}
    case "$pid:$*" in
      200:*comm=*|200:*args=*) printf 'pi\n' ;;
      220:*comm=*|220:*args=*) printf 'claude\n' ;;
      *:*comm=*|*:*args=*) printf 'bash\n' ;;
      220:*ppid=*) printf '1\n' ;;
      *:*ppid=*)
        if [ "$pid" -ge 200 ] 2>/dev/null && [ "$pid" -lt 220 ]; then printf '%s\n' "$((pid + 1))"; else printf '200\n'; fi
        ;;
    esac
  }
  fm_harness_pid_identity() {
    case "$1" in 200) printf 'pi\n' ;; 220) printf 'claude\n' ;; esac
  }
  fm_harness_ancestry_pids >/dev/null
); then
  fail "deep excluded ancestry authorized an inner Pi process"
fi
pass "deep excluded ancestry cannot authorize an inner Pi process"
