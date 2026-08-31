#!/usr/bin/env bash
# Detect and resolve the only supported agent harness: plain Pi.
# Usage: fm-harness.sh                    print own harness: pi|unknown
#        fm-harness.sh crew               print effective crewmate harness
#        fm-harness.sh secondmate          print effective secondmate harness
#        fm-harness.sh secondmate-model    print optional model token
#        fm-harness.sh secondmate-effort   print optional effort token
#
# config/crew-harness accepts only "pi" or "default". config/secondmate-harness
# accepts "pi [model] [effort]" or "default". Legacy and excluded harness names
# are rejected explicitly; they are never normalized or substituted with Pi.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
# shellcheck source=bin/fm-harness-identity-lib.sh
. "$SCRIPT_DIR/fm-harness-identity-lib.sh"

unsupported() {
  printf 'error: unsupported harness %q; migrate this configuration or task metadata to an explicitly selected plain pi harness\n' "$1" >&2
  return 2
}

detect_own() {
  local pid=$$ comm args identity pi_seen=0
  for _ in 1 2 3 4 5 6 7 8; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    identity=$(fm_harness_pid_identity "$pid" "$comm" "$args" || true)
    if fm_harness_identity_excluded "$identity"; then
      unsupported "$identity"
      return
    fi
    [ "$identity" != pi ] || pi_seen=1
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$pid" ] && [ "$pid" -gt 1 ] || break
  done
  if [ "$pi_seen" -eq 1 ]; then
    printf 'pi\n'
  else
    printf 'unknown\n'
  fi
}

crew_value() {
  local value=
  [ -f "$CONFIG/crew-harness" ] && value=$(tr -d '[:space:]' < "$CONFIG/crew-harness" || true)
  case "$value" in
    ''|default) detect_own ;;
    pi) printf 'pi\n' ;;
    *) unsupported "$value" ;;
  esac
}

secondmate_line() {
  local line
  [ -f "$CONFIG/secondmate-harness" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    case "$line" in '#'*) continue ;; esac
    printf '%s\n' "$line"
    return 0
  done < "$CONFIG/secondmate-harness"
}

secondmate_field() {
  local idx=$1 line
  line=$(secondmate_line)
  [ -n "$line" ] || return 0
  # shellcheck disable=SC2086 # intentional whitespace tokenization
  set -- $line
  [ "$#" -le 3 ] || { printf 'error: invalid secondmate harness configuration: expected "pi [model] [effort]"\n' >&2; return 2; }
  case "$idx" in 1) printf '%s\n' "${1:-}" ;; 2) printf '%s\n' "${2:-}" ;; 3) printf '%s\n' "${3:-}" ;; esac
}

resolve_secondmate() {
  local value
  value=$(secondmate_field 1) || return
  case "$value" in
    ''|default) crew_value ;;
    pi) printf 'pi\n' ;;
    *) unsupported "$value" ;;
  esac
}

resolve_secondmate_detail() {
  local value
  value=$(secondmate_field 1) || return
  case "$value" in
    ''|default) return 0 ;;
    pi) secondmate_field "$1" ;;
    *) unsupported "$value" ;;
  esac
}

case "${1:-}" in
  crew) crew_value ;;
  secondmate) resolve_secondmate ;;
  secondmate-model) resolve_secondmate_detail 2 ;;
  secondmate-effort) resolve_secondmate_detail 3 ;;
  *) detect_own ;;
esac
