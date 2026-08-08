#!/usr/bin/env bash
# Resolve Firstmate's fixed Pi runtime and its model/thinking profiles.
# Usage: fm-harness.sh                         print the detected primary runtime: pi|unknown
#        fm-harness.sh primary                 require the current primary session to be Pi
#        fm-harness.sh crew                    print the fixed worker runtime: pi
#        fm-harness.sh crew-profile            print model, thinking, and source as TSV
#        fm-harness.sh secondmate [<id>]       print the fixed secondmate runtime: pi
#        fm-harness.sh secondmate-model [<id>] print the resolved optional model token
#        fm-harness.sh secondmate-effort [<id>] print the resolved optional thinking token
#        fm-harness.sh secondmate-profile <id> print model, thinking, and source as TSV
#        fm-harness.sh validate-config         validate Pi-only local runtime configuration
#
# Firstmate supports Pi alone.
# config/crew-profile is the optional ordinary-worker profile.
# config/secondmate-profile is the optional global secondmate profile.
# config/secondmate-profiles/<id> overrides the global secondmate profile.
# Each new profile is one non-comment line: <model> [<thinking>].
# A model is concrete and a thinking value is low, medium, high, xhigh, or max.
# Obsolete config/crew-harness and config/secondmate-harness files are migration
# blockers rather than fallback configuration.
# bin/fm-pi-runtime-migrate.sh owns the explicit local transition procedure.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"

runtime_error() {
  printf 'error: Firstmate supports only the Pi runtime%s\n' "${1:+: $1}" >&2
}

pi_in_ancestry() {
  local pid=$$ comm args
  [ "${PI_CODING_AGENT:-}" = true ] && return 0
  for _ in 1 2 3 4 5 6 7 8; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    case "$(basename -- "$comm")" in
      pi) return 0 ;;
      node*|python*)
        args=$(ps -o args= -p "$pid" 2>/dev/null || true)
        case "$args" in *" pi "*|*/pi) return 0 ;; esac
        ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$pid" in ''|*[!0-9]*) break ;; esac
    [ "$pid" -gt 1 ] || break
  done
  return 1
}

detect_primary() {
  if pi_in_ancestry; then
    printf 'pi\n'
  else
    printf 'unknown\n'
  fi
}

require_primary_pi() {
  if pi_in_ancestry; then
    printf 'pi\n'
    return 0
  fi
  runtime_error 'start Firstmate with pi'
  return 1
}

legacy_runtime_config() {
  local path id line first
  for path in "$CONFIG/crew-harness" "$CONFIG/secondmate-harness"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      printf '%s\n' "config/${path##*/}"
      return 0
    fi
  done
  path="$CONFIG/secondmate-profiles"
  if [ -e "$path" ] || [ -L "$path" ]; then
    [ -d "$path" ] && [ ! -L "$path" ] || return 1
    for path in "$path"/*; do
      [ -e "$path" ] || [ -L "$path" ] || continue
      [ -f "$path" ] && [ ! -L "$path" ] || continue
      line=$(profile_line "$path" 2>/dev/null || true)
      [ -n "$line" ] || continue
      # shellcheck disable=SC2086 # Deliberate first-token extraction.
      set -- $line
      first=${1:-}
      case "$first" in
        pi|claude|codex|grok)
          id=${path##*/}
          printf 'config/secondmate-profiles/%s\n' "$id"
          return 0
          ;;
      esac
    done
  fi
  return 1
}

require_no_legacy_runtime_config() {
  local source
  if source=$(legacy_runtime_config); then
    runtime_error "obsolete runtime selection in $source; run bin/fm-pi-runtime-migrate.sh --check before launching work"
    return 1
  fi
  return 0
}

profile_line() { # <path>
  local path=$1 line selected='' count=0
  [ -e "$path" ] || [ -L "$path" ] || return 1
  [ -f "$path" ] && [ ! -L "$path" ] || {
    printf 'error: expected a regular non-symlink profile file at %s\n' "$path" >&2
    return 2
  }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    case "$line" in '#'* ) continue ;; esac
    count=$((count + 1))
    selected=$line
  done < "$path"
  if [ "$count" -ne 1 ]; then
    printf 'error: malformed profile in %s; expected exactly one non-comment line\n' "$path" >&2
    return 2
  fi
  printf '%s\n' "$selected"
}

parse_profile() { # <source> <line>
  local source=$1 line=$2
  local -a fields
  PROFILE_MODEL=
  PROFILE_EFFORT=
  IFS=$' \t\n' read -r -a fields <<< "$line"
  case "${#fields[@]}" in
    1) PROFILE_MODEL=${fields[0]} ;;
    2) PROFILE_MODEL=${fields[0]}; PROFILE_EFFORT=${fields[1]} ;;
    *)
      printf 'error: malformed Pi profile in %s; expected <model> [<thinking>]\n' "$source" >&2
      return 1
      ;;
  esac
  case "$PROFILE_MODEL" in
    ''|default|-|*[[:space:]]*)
      printf 'error: malformed Pi profile in %s; model must be a concrete token\n' "$source" >&2
      return 1
      ;;
  esac
  case "$PROFILE_EFFORT" in
    ''|low|medium|high|xhigh|max) ;;
    *)
      printf 'error: malformed Pi profile in %s; thinking must be low, medium, high, xhigh, or max\n' "$source" >&2
      return 1
      ;;
  esac
  return 0
}

resolve_profile_file() { # <path> <source>
  local path=$1 source=$2 line rc
  line=$(profile_line "$path")
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  parse_profile "$source" "$line" || return 2
  printf '%s\t%s\t%s\n' "$PROFILE_MODEL" "$PROFILE_EFFORT" "$source"
}

resolve_crew_profile() {
  local path="$CONFIG/crew-profile" record rc
  require_no_legacy_runtime_config || return 1
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    printf '\t\tbuilt-in\n'
    return 0
  fi
  record=$(resolve_profile_file "$path" config/crew-profile)
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "$record"
}

valid_profile_id() {
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

resolve_secondmate_default_profile() {
  local path="$CONFIG/secondmate-profile" record rc
  require_no_legacy_runtime_config || return 1
  if [ -e "$path" ] || [ -L "$path" ]; then
    record=$(resolve_profile_file "$path" config/secondmate-profile)
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    printf '%s\n' "$record"
    return 0
  fi
  resolve_crew_profile
}

resolve_secondmate_profile() { # <id>
  local id=$1 path record rc
  valid_profile_id "$id" || {
    printf "error: invalid secondmate profile id '%s'; expected [A-Za-z0-9._-]+\n" "$id" >&2
    return 2
  }
  require_no_legacy_runtime_config || return 1
  path="$CONFIG/secondmate-profiles"
  if [ -e "$path" ] || [ -L "$path" ]; then
    [ -d "$path" ] && [ ! -L "$path" ] || {
      printf 'error: unsafe config/secondmate-profiles directory; expected a non-symlink directory\n' >&2
      return 2
    }
    if [ -e "$path/$id" ] || [ -L "$path/$id" ]; then
      record=$(resolve_profile_file "$path/$id" "config/secondmate-profiles/$id")
      rc=$?
      [ "$rc" -eq 0 ] || return "$rc"
      printf '%s\n' "$record"
      return 0
    fi
  fi
  resolve_secondmate_default_profile
}

profile_field() { # <record> <field>
  local record=$1 field=$2 rest model effort
  model=${record%%$'\t'*}
  rest=${record#*$'\t'}
  effort=${rest%%$'\t'*}
  case "$field" in
    model) printf '%s\n' "$model" ;;
    effort) printf '%s\n' "$effort" ;;
  esac
}

validate_config() {
  local record id path
  require_no_legacy_runtime_config || return 1
  resolve_crew_profile >/dev/null || return 1
  path="$CONFIG/secondmate-profile"
  if [ -e "$path" ] || [ -L "$path" ]; then
    resolve_profile_file "$path" config/secondmate-profile >/dev/null || return 1
  fi
  path="$CONFIG/secondmate-profiles"
  if [ -e "$path" ] || [ -L "$path" ]; then
    [ -d "$path" ] && [ ! -L "$path" ] || {
      printf 'error: unsafe config/secondmate-profiles directory; expected a non-symlink directory\n' >&2
      return 1
    }
    for path in "$path"/*; do
      [ -e "$path" ] || [ -L "$path" ] || continue
      id=${path##*/}
      valid_profile_id "$id" || {
        printf "error: invalid secondmate profile id '%s'; expected [A-Za-z0-9._-]+\n" "$id" >&2
        return 1
      }
      resolve_profile_file "$path" "config/secondmate-profiles/$id" >/dev/null || return 1
    done
  fi
}

case "${1:-}" in
  primary) require_primary_pi ;;
  crew) resolve_crew_profile >/dev/null && printf 'pi\n' ;;
  crew-profile) resolve_crew_profile ;;
  secondmate)
    if [ "$#" -eq 1 ]; then
      resolve_secondmate_default_profile >/dev/null && printf 'pi\n'
    elif [ "$#" -eq 2 ]; then
      resolve_secondmate_profile "$2" >/dev/null && printf 'pi\n'
    else
      printf 'error: secondmate requires at most one secondmate id\n' >&2
      exit 2
    fi
    ;;
  secondmate-model|secondmate-effort)
    field=${1#secondmate-}
    if [ "$#" -eq 1 ]; then
      record=$(resolve_secondmate_default_profile) || exit $?
    elif [ "$#" -eq 2 ]; then
      record=$(resolve_secondmate_profile "$2") || exit $?
    else
      printf 'error: %s requires at most one secondmate id\n' "$1" >&2
      exit 2
    fi
    profile_field "$record" "$field"
    ;;
  secondmate-profile)
    [ "$#" -eq 2 ] || {
      printf 'error: secondmate-profile requires exactly one secondmate id\n' >&2
      exit 2
    }
    resolve_secondmate_profile "$2"
    ;;
  validate-config) validate_config ;;
  '') detect_primary ;;
  *)
    printf 'error: unknown fm-harness command: %s\n' "$1" >&2
    exit 2
    ;;
esac
