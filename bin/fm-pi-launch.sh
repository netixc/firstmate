#!/usr/bin/env bash
# fm-pi-launch.sh - launch canonical Pi with parent-owned process evidence.
set -eu

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FM_ROOT=${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}
state=${FM_STATE_OVERRIDE:-${FM_HOME:-$FM_ROOT}/state}
extension=${FM_PI_REGISTRATION_EXTENSION:-$FM_ROOT/.pi/extensions/fm-pi-process-registration.ts}

while [ $# -gt 0 ]; do
  case "$1" in
    --state) state=$2; shift 2 ;;
    --extension) extension=$2; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || set -- pi

# shellcheck source=bin/fm-harness-identity-lib.sh
. "$SCRIPT_DIR/fm-harness-identity-lib.sh"
cli=$(type -P -- "$1" 2>/dev/null || true)
if [ -z "$cli" ] || ! fm_harness_pi_cli_canonical "$cli"; then
  printf 'error: canonical plain Pi 0.84.4 is required\n' >&2
  exit 2
fi
shift

child=
trap '[ -z "$child" ] || kill -INT "$child" 2>/dev/null || true' INT
trap '[ -z "$child" ] || kill -TERM "$child" 2>/dev/null || true' TERM
"$cli" "$@" &
child=$!
if ! fm_harness_pi_launch_record_publish "$state" "$child" "$extension" "$cli"; then
  kill "$child" 2>/dev/null || true
  wait "$child" 2>/dev/null || true
  printf 'error: could not publish parent-owned Pi launch evidence\n' >&2
  exit 1
fi
set +e
wait "$child"
status=$?
set -e
child=
exit "$status"
