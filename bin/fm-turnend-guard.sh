#!/usr/bin/env bash
# Pi primary turn-end guard: block a logical run from ending while supervision
# is required and no healthy watcher cycle owns this home.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
GRACE=${FM_GUARD_GRACE:-300}
WATCH="$SCRIPT_DIR/fm-watch.sh"
[ "$#" -eq 0 ] || { echo "usage: $(basename "$0")" >&2; exit 2; }

# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"
# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"

PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
printf '%s' "$PAYLOAD" | jq -e 'type == "object"' >/dev/null 2>&1 || exit 0
fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0
fm_supervision_status "$STATE" "$GRACE"
[ "$FM_SUP_NEEDED" = true ] || exit 0
fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME" && exit 0

afk=0; [ -e "$STATE/.afk" ] && afk=1
x_mode=0; [ -f "$CONFIG/x-mode.env" ] && x_mode=1
reason=$("$SCRIPT_DIR/fm-supervision-instructions.sh" --harness pi --afk "$afk" --x-mode "$x_mode" --repair-line 2>/dev/null \
  || printf '%s' 'repair missing Pi watcher supervision before ending the turn')
printf 'TURN WOULD END BLIND - %s\n' "$reason" >&2
exit 2
