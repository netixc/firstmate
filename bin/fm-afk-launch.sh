#!/usr/bin/env bash
# fm-afk-launch.sh - the single entry and exit owner for Pi's away and quiet
# postures. Supervision ownership never changes: Pi's ordinary supervision
# cycle and supervision branch remain active.
#
# Usage:
#   fm-afk-launch.sh propose [fm-afk-contract.sh proposal options...]
#       Record the captain's away words and mandate fields and print the read-back.
#   fm-afk-launch.sh confirm
#       Confirm the proposed away posture and print its entry announcement.
#   fm-afk-launch.sh quiet
#       Record quiet posture in state/.afk.
#   fm-afk-launch.sh stop
#       Clear quiet posture and archive a confirmed away-posture record.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
case "$FM_HOME" in
  /*) ;;
  *)
    input=$FM_HOME
    FM_HOME=$(CDPATH='' cd -- "$input" 2>/dev/null && pwd -P) || {
      printf 'error: FM_HOME directory cannot be resolved: %s\n' "$input" >&2
      exit 1
    }
    ;;
esac
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
case "$STATE" in
  /*) ;;
  *)
    input=$STATE
    STATE=$(CDPATH='' cd -- "$input" 2>/dev/null && pwd -P) || {
      printf 'error: state directory cannot be resolved: %s\n' "$input" >&2
      exit 1
    }
    ;;
esac
mkdir -p "$STATE"

# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-afk-contract.sh
. "$SCRIPT_DIR/fm-afk-contract.sh"

CONTRACT="$SCRIPT_DIR/fm-afk-contract.sh"
LOCK="$STATE/.afk-launch.lock"

log() { printf 'fm-afk-launch: %s\n' "$*" >&2; }

usage() {
  sed -n '2,/^set -u$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

catchup_pending() {
  if [ -e "$STATE/.afk-return-catchup" ]; then
    log "return catch-up is still pending; run bin/fm-afk-return.sh check before changing posture"
    return 0
  fi
  return 1
}

record_quiet() {
  local pending marker="$STATE/.afk"
  catchup_pending && return 1
  if fm_afk_contract_present "$STATE"; then
    log "away posture is already active; return from it before entering quiet posture"
    return 1
  fi
  if [ -e "$marker" ] || [ -L "$marker" ]; then
    if [ -L "$marker" ] || [ ! -f "$marker" ] \
      || [ "$(sed -n '1p' "$marker")" != quiet ] \
      || ! sed -n '2p' "$marker" | grep -Eq '^[0-9]+$' \
      || [ "$(wc -l < "$marker" | tr -d ' ')" -ne 2 ]; then
      log "state/.afk is not a valid quiet posture marker"
      return 1
    fi
  fi
  pending=$(mktemp "$STATE/.afk.pending.XXXXXX") || return 1
  { printf 'quiet\n'; date '+%s'; } > "$pending" || { rm -f "$pending"; return 1; }
  mv "$pending" "$marker" || { rm -f "$pending"; return 1; }
  log "quiet posture recorded; Pi ordinary supervision remains active"
}

confirm_away() {
  catchup_pending && return 1
  "$CONTRACT" confirm || return 1
  rm -f "$STATE/.afk"
}

stop_posture() {
  local archived result=0
  rm -f "$STATE/.afk" || result=1
  if [ "$result" -eq 0 ] && fm_afk_contract_present "$STATE"; then
    if archived=$("$CONTRACT" archive); then
      log "away-posture record archived at $archived"
    else
      log "failed to archive the away-posture record; it still stands"
      result=1
    fi
  fi
  if [ "$result" -eq 0 ]; then
    log "posture ended; Pi ordinary supervision remains active"
  fi
  return "$result"
}

main() {
  local result
  trap 'fm_lock_release "$LOCK"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  fm_lock_acquire_wait_bounded "$LOCK" 10 || {
    log "could not acquire the posture lifecycle lock"
    return 1
  }
  case "${1:-}" in
    propose)
      shift
      if catchup_pending; then result=1; else "$CONTRACT" propose "$@"; result=$?; fi
      ;;
    confirm) confirm_away; result=$? ;;
    quiet) record_quiet; result=$? ;;
    stop) stop_posture; result=$? ;;
    -h|--help|help) usage; result=0 ;;
    *) usage >&2; result=2 ;;
  esac
  fm_lock_release "$LOCK" || result=1
  trap - EXIT INT TERM
  return "$result"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
