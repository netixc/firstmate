#!/usr/bin/env bash
# Print the tail of a crewmate endpoint (bounded, for cheap diagnosis).
# Usage: fm-peek.sh <target> [lines=40]
#   <target> may be an exact task id, a legacy fm-<id> task label resolved
#   through this home's state/<id>.meta, or an explicit Herdr target.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# shellcheck source=bin/fm-backend.sh
. "$SCRIPT_DIR/fm-backend.sh" operational

"$SCRIPT_DIR/fm-guard.sh" || true

RAW_TARGET=$1
T=$(fm_backend_resolve_selector "$RAW_TARGET" "$STATE")
N=${2:-40}

EXPECTED_LABEL=$(fm_backend_expected_label_of_selector "$RAW_TARGET" "$STATE")

fm_backend_capture "$T" "$N" "$EXPECTED_LABEL"
