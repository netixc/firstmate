#!/usr/bin/env bash
# Pi PreToolUse transport for the persistent-cwd command policy.
# Usage: fm-cd-pretool-check.sh --command <command>
#
# bin/fm-cd-command-policy.mjs owns the block or allow decision.
# This wrapper applies it only in a real Firstmate primary checkout.
# It never evaluates submitted text.
# Exit 0 permits the call or leaves a non-primary checkout untouched.
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
  *) case "$PREFILTER" in *cd*|*pushd*|*popd*) ;; *) exit 0 ;; esac ;;
esac

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 0
FM_ROOT=${FM_ROOT_OVERRIDE:-$(CDPATH='' cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P)} || exit 0
[ -f "$FM_ROOT/AGENTS.md" ] && [ -d "$FM_ROOT/bin" ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
GIT_DIR=$(git -C "$FM_ROOT" rev-parse --git-dir 2>/dev/null) || exit 0
GIT_COMMON_DIR=$(git -C "$FM_ROOT" rev-parse --git-common-dir 2>/dev/null) || exit 0
[ "$GIT_DIR" = "$GIT_COMMON_DIR" ] || exit 0

POLICY="$FM_ROOT/bin/fm-cd-command-policy.mjs"
command -v node >/dev/null 2>&1 || exit 0
[ -f "$POLICY" ] || exit 0
POLICY_OUTPUT=$(node "$POLICY" --command "$CMD" 2>/dev/null) || exit 0
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
