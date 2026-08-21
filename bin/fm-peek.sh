#!/usr/bin/env bash
# Print the tail of a Herdr worker endpoint (bounded, for cheap diagnosis).
# Usage: fm-peek.sh <target> [lines=40]
#   <target> may be an exact task id, a legacy fm-<id> task label resolved
#   through this home's state/<id>.meta, or an exact Herdr session:pane id.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# shellcheck source=bin/fm-herdr.sh
. "$SCRIPT_DIR/fm-herdr.sh"
fm_herdr_require_runtime || exit 1

"$SCRIPT_DIR/fm-guard.sh" || true

RAW_TARGET=$1
N=${2:-40}
META=$(fm_meta_for_selector "$RAW_TARGET" "$STATE" 2>/dev/null || true)
if [ -z "$META" ]; then
  META_RC=0
  META=$(fm_endpoint_meta_for_target "$RAW_TARGET" "$STATE" 2>/dev/null) || META_RC=$?
  [ "$META_RC" -ne 2 ] || {
    echo "error: explicit target '$RAW_TARGET' has ambiguous or invalid task ownership; preserving endpoint records for manual reconciliation" >&2
    exit 1
  }
fi

if [ -n "$META" ]; then
  ID=${META##*/}
  ID=${ID%.meta}
  fm_herdr_live_capture_task_endpoint "$META" "$ID" "$N"
else
  T=$(fm_herdr_resolve_selector "$RAW_TARGET" "$STATE")
  fm_herdr_capture "$T" "$N"
fi
