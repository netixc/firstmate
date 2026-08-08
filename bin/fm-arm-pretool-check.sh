#!/usr/bin/env bash
# Pi PreToolUse transport for the watcher-arm command policy.
# Usage: fm-arm-pretool-check.sh --command <command>
#
# bin/fm-arm-command-policy.mjs owns command classification and deny reasons.
# This wrapper passes Pi's exact bash command to that owner.
# It never evaluates submitted text.
# Exit 0 permits the call.
# Exit 2 writes the deny reason to stderr for the Pi extension.
set -u

CMD=
usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; $d' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --command)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      CMD=$2
      shift 2
      ;;
    --command=*) CMD=${1#--command=}; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[ -n "$CMD" ] || exit 0
PREFILTER=$CMD
PREFILTER=${PREFILTER//\\/}
PREFILTER=${PREFILTER//\"/}
PREFILTER=${PREFILTER//\'/}
PREFILTER=${PREFILTER//$'\n'/}
PREFILTER=${PREFILTER//$'\r'/}
case "$CMD" in
  *"\$'"*|*'$"'*) ;;
  *) case "$PREFILTER" in *fm-watch*) ;; *) exit 0 ;; esac ;;
esac

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 0
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || exit 0
ACTIVE_HOME=${FM_HOME:-$ROOT}
POLICY="$ROOT/bin/fm-arm-command-policy.mjs"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$POLICY" ] || exit 0

POLICY_OUTPUT=$(node "$POLICY" --command "$CMD" --root "$ROOT" --home "$ACTIVE_HOME" 2>/dev/null) || exit 0
TAB=$(printf '\t')
DECISION=${POLICY_OUTPUT%%"$TAB"*}
[ "$DECISION" = deny ] || exit 0
REST=${POLICY_OUTPUT#*"$TAB"}
[ "$REST" != "$POLICY_OUTPUT" ] || exit 0
CODE=${REST%%"$TAB"*}
REASON=${REST#*"$TAB"}
[ -n "$CODE" ] && [ -n "$REASON" ] && [ "$REASON" != "$REST" ] || exit 0
printf '[%s] %s\n' "$CODE" "$REASON" >&2
exit 2
