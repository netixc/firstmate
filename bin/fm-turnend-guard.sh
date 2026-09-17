#!/usr/bin/env bash
# Turn-end guard for any Firstmate primary session: the main home or a
# secondmate's own home.
#
# bin/fm-guard.sh is pull-based and can warn only when another command runs.
# This push-based guard is invoked by verified harness turn-end integrations so
# a primary cannot finish a turn while required supervision is absent.
# Pi adapters turn exit status 2 and stderr into one bounded
# continuation through their own native event surfaces.
#
# The guard scopes itself to a genuine primary checkout and stays inert inside
# child task worktrees.
# Away mode transfers supervision to the identity-matched away daemon, whose
# fresh beacon is accepted even while its one-shot watcher is between cycles.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
GRACE=${FM_GUARD_GRACE:-300}
WATCH="$SCRIPT_DIR/fm-watch.sh"

[ "$#" -eq 0 ] || { echo "usage: $(basename "$0")" >&2; exit 2; }

# Read the turn-end integration payload once; never block on unreadable or
# absent stdin. Retained integrations own their bounded-continuation guards.
PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0

# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"
# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"

fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0
fm_supervision_status "$STATE" "$GRACE"
[ "$FM_SUP_NEEDED" = true ] || exit 0

if fm_watcher_healthy "$STATE" "$WATCH" "$GRACE" "$FM_HOME"; then
  exit 0
fi

AFK_GRACE=${FM_GUARD_GRACE:-$(fm_poll_derived_grace)}
if [ "$(fm_path_age "$STATE/.last-watcher-beat")" -lt "$AFK_GRACE" ] \
  && fm_afk_daemon_owns_supervision "$STATE"; then
  exit 0
fi

afk=0
[ -e "$STATE/.afk" ] && afk=1
x_mode=0
[ -f "$CONFIG/x-mode.env" ] && x_mode=1
reason=$("$SCRIPT_DIR/fm-supervision-instructions.sh" --afk "$afk" --x-mode "$x_mode" --repair-line 2>/dev/null \
  || printf '%s\n' 'tasks in flight, no live watcher - repair missing watcher supervision according to the session-start operating block before ending the turn')
rule='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
{
  printf '●%s\n' "$rule"
  printf '●  TURN WOULD END BLIND - SUPERVISION IS OFF\n'
  if [ "$FM_SUP_IN_FLIGHT" -gt 0 ]; then
    printf '●  %s task(s) in flight, but no live watcher holds this home lock (last beat: %s).\n' "$FM_SUP_IN_FLIGHT" "$FM_SUP_BEACON_DESC"
  elif [ "$FM_SUP_SOURCES" -gt 0 ]; then
    printf '●  %s process-event source(s) registered, but no live watcher holds this home lock (last beat: %s).\n' "$FM_SUP_SOURCES" "$FM_SUP_BEACON_DESC"
  elif [ "$FM_SUP_CHECKS" -gt 0 ]; then
    printf '●  %s registered custom check(s), but no live watcher holds this home lock (last beat: %s).\n' "$FM_SUP_CHECKS" "$FM_SUP_BEACON_DESC"
  else
    printf '●  X-mode relay polling needs supervision, but no live watcher holds this home lock (last beat: %s).\n' "$FM_SUP_BEACON_DESC"
  fi
  printf '●  %s\n' "$reason"
  printf '●%s\n' "$rule"
} >&2
exit 2
