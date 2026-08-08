#!/usr/bin/env bash
# Guard Pi primary turn boundaries when supervision is required.
# Usage: fm-turnend-guard.sh
#
# Pi's primary extension invokes this predicate after a settled logical run.
# The extension owns the one bounded follow-up when this script exits 2.
# Child task worktrees stay out of scope.
set -u

[ "$#" -eq 0 ] || {
  echo "usage: $(basename "$0")" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
GRACE=${FM_GUARD_GRACE:-300}
WATCH="$SCRIPT_DIR/fm-watch.sh"

# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"
# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"

fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0
fm_supervision_status "$STATE" "$GRACE"
[ "$FM_SUP_NEEDED" = true ] || exit 0
fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME" && exit 0

afk=0
[ -e "$STATE/.afk" ] && afk=1
x_mode=0
[ -f "$CONFIG/x-mode.env" ] && x_mode=1
repair=$("$SCRIPT_DIR/fm-supervision-instructions.sh" --afk "$afk" --x-mode "$x_mode" --repair-line 2>/dev/null \
  || printf '%s' 'repair Pi watcher supervision according to the session-start operating instructions')
rule='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
{
  printf '●%s\n' "$rule"
  printf '●  TURN WOULD END BLIND - PI SUPERVISION IS OFF\n'
  if [ "$FM_SUP_IN_FLIGHT" -gt 0 ]; then
    printf '●  %s task(s) are in flight and no live watcher holds this home lock (last beat: %s).\n' "$FM_SUP_IN_FLIGHT" "$FM_SUP_BEACON_DESC"
  elif [ "$FM_SUP_SOURCES" -gt 0 ]; then
    printf '●  %s process-event source(s) need a live watcher (last beat: %s).\n' "$FM_SUP_SOURCES" "$FM_SUP_BEACON_DESC"
  else
    printf '●  Relay polling needs a live watcher (last beat: %s).\n' "$FM_SUP_BEACON_DESC"
  fi
  printf '●  %s\n' "$repair"
  printf '●%s\n' "$rule"
} >&2
exit 2
