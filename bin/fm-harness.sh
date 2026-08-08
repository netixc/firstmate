#!/usr/bin/env bash
# Detect the agent harness this process tree runs on.
# Usage: fm-harness.sh                         print own harness: claude|codex|grok|pi|unknown
#        fm-harness.sh crew                    print the effective CREWMATE harness
#                                               (config/crew-harness; "default" resolves to own)
#        fm-harness.sh secondmate [<id>]       print the harness the PRIMARY uses to launch
#                                               one SECONDMATE agent. With no id, use the
#                                               legacy global resolution; with an id, use
#                                               the id-aware profile resolver.
#        fm-harness.sh secondmate-model [<id>] print the optional resolved MODEL token.
#        fm-harness.sh secondmate-effort [<id>] print the optional resolved EFFORT token.
#        fm-harness.sh secondmate-profile <id> print one tab-separated resolved profile:
#                                               harness, model, effort, source.
# docs/configuration.md "Harness support" owns both profile schemas and precedence.
# An existing malformed per-secondmate profile is an error, never a fallback.
# Model/effort come only from the selected secondmate profile or global file -
# config/crew-harness stays a bare adapter name and is never parsed for a model.
# Detection layers: verified environment markers first, then process ancestry.
# Record each newly verified env marker here.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"

validate_configured_harness() {
  local harness=$1 source=$2
  case "$harness" in
    claude|codex|grok|pi) return 0 ;;
    *)
      printf "error: unsupported harness '%s' in %s; expected claude, codex, grok, or pi\n" "$harness" "$source" >&2
      return 1
      ;;
  esac
}

detect_own() {
  # Layer 1: environment markers for verified harnesses.
  # Keep marker detection before ancestry detection as an explicit precedence rule.
  # Claude, Pi, and Grok set verified markers of their own; Codex is markerless,
  # so ancestry remains its detection path.
  [ "${CLAUDECODE:-}" = "1" ] && { echo claude; return; }
  [ "${PI_CODING_AGENT:-}" = "true" ] && { echo pi; return; }
  # grok sets GROK_AGENT=1 for its child/tool processes (verified, grok 0.2.73).
  # It does NOT set CLAUDECODE despite being Claude-Code-compatible, so this marker
  # is unambiguous when firstmate runs natively on grok.
  [ "${GROK_AGENT:-}" = "1" ] && { echo grok; return; }
  # Layer 2: walk the parent chain and match the command name.
  local pid=$$ comm args
  for _ in 1 2 3 4 5 6 7 8; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null) || break
    case "$(basename -- "$comm")" in
      *claude*) echo claude; return ;;
      *codex*) echo codex; return ;;
      *grok*) echo grok; return ;;
      pi) echo pi; return ;;
      node*|python*)
        # Bare interpreter: match the harness name in its script path.
        args=$(ps -o args= -p "$pid" 2>/dev/null)
        case "$args" in
          *claude*) echo claude; return ;;
          *codex*) echo codex; return ;;
          *grok*) echo grok; return ;;
          *" pi "*|*/pi) echo pi; return ;;
        esac ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -z "$pid" ] || [ "$pid" -le 1 ]; then
      break
    fi
  done
  echo unknown
}

# Resolve the effective crewmate harness: config/crew-harness (a bare adapter
# name) wins; absent or "default" mirrors firstmate's own harness.
resolve_crew() {
  local crew=
  [ -f "$CONFIG/crew-harness" ] && crew=$(tr -d '[:space:]' < "$CONFIG/crew-harness" || true)
  if [ -z "$crew" ] || [ "$crew" = "default" ]; then
    detect_own
    return
  fi
  validate_configured_harness "$crew" config/crew-harness || return 1
  printf '%s\n' "$crew"
}

# Print the first non-empty, non-comment line of config/secondmate-harness
# (leading/trailing whitespace trimmed), or nothing when the file is absent or
# holds only blank/comment lines.
secondmate_line() {
  local line
  [ -f "$CONFIG/secondmate-harness" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    case "$line" in
      '#'*) continue ;;
    esac
    printf '%s\n' "$line"
    return 0
  done < "$CONFIG/secondmate-harness"
}

# Print the 1-based whitespace-separated token (1=harness, 2=model, 3=effort) of
# the resolved secondmate_line, or nothing if the line or that field is absent.
secondmate_field() {
  local idx=$1 line
  line=$(secondmate_line)
  [ -n "$line" ] || return 0
  # shellcheck disable=SC2086  # deliberate word-splitting: tokenizing the line into fields
  set -- $line
  case "$idx" in
    1) printf '%s\n' "${1:-}" ;;
    2) printf '%s\n' "${2:-}" ;;
    3) printf '%s\n' "${3:-}" ;;
  esac
}

# Resolve the legacy global secondmate harness while preserving its historical
# absent/default compatibility behavior.
resolve_secondmate() {
  local sm
  sm=$(secondmate_field 1)
  if [ -z "$sm" ] || [ "$sm" = "default" ]; then
    resolve_crew
    return
  fi
  validate_configured_harness "$sm" config/secondmate-harness || return 1
  printf '%s\n' "$sm"
}

# Print the optional model token (2nd field) from config/secondmate-harness, or
# empty when the harness token is absent/"default" or when no model is present.
resolve_secondmate_model() {
  local sm
  sm=$(secondmate_field 1)
  [ -n "$sm" ] && [ "$sm" != "default" ] || return 0
  validate_configured_harness "$sm" config/secondmate-harness || return 1
  secondmate_field 2
}

# Print the optional effort token (3rd field) from config/secondmate-harness,
# the same way.
resolve_secondmate_effort() {
  local sm
  sm=$(secondmate_field 1)
  [ -n "$sm" ] && [ "$sm" != "default" ] || return 0
  validate_configured_harness "$sm" config/secondmate-harness || return 1
  secondmate_field 3
}

# Read exactly one non-comment profile line for <id>. Return 1 only when no
# profile exists, so callers can use the unchanged global fallback. Any present
# but unsafe or malformed profile returns 2 after a source-naming diagnostic.
secondmate_profile_line() {
  local id=$1 directory path line selected='' count=0
  case "$id" in
    ''|*[!A-Za-z0-9._-]*)
      printf "error: invalid secondmate profile id '%s'; expected [A-Za-z0-9._-]+\n" "$id" >&2
      return 2
      ;;
  esac
  directory="$CONFIG/secondmate-profiles"
  if [ ! -e "$directory" ] && [ ! -L "$directory" ]; then
    return 1
  fi
  if [ ! -d "$directory" ] || [ -L "$directory" ]; then
    printf "error: unsafe config/secondmate-profiles directory; expected a non-symlink directory\n" >&2
    return 2
  fi
  path="$directory/$id"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 1
  fi
  if [ ! -f "$path" ] || [ -L "$path" ]; then
    printf "error: unsafe secondmate profile in config/secondmate-profiles/%s; expected a regular non-symlink file\n" "$id" >&2
    return 2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    case "$line" in
      '#'*) continue ;;
    esac
    count=$((count + 1))
    selected=$line
  done < "$path"
  if [ "$count" -ne 1 ]; then
    printf "error: malformed secondmate profile in config/secondmate-profiles/%s; expected exactly one non-comment line\n" "$id" >&2
    return 2
  fi
  printf '%s\n' "$selected"
}

# Parse config/secondmate-profiles/<id> into globals for the one caller that
# needs all three axes atomically. Return 1 only when that profile is absent.
parse_secondmate_profile() {
  local id=$1 line rc harness model='' effort=''
  local -a fields
  SECONDMATE_PROFILE_HARNESS=
  SECONDMATE_PROFILE_MODEL=
  SECONDMATE_PROFILE_EFFORT=
  line=$(secondmate_profile_line "$id")
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  IFS=$' \t\n' read -r -a fields <<< "$line"
  case "${#fields[@]}" in
    1) harness=${fields[0]} ;;
    2) harness=${fields[0]}; model=${fields[1]} ;;
    3) harness=${fields[0]}; model=${fields[1]}; effort=${fields[2]} ;;
    *)
      printf "error: malformed secondmate profile in config/secondmate-profiles/%s; expected <harness> [<model>] [<effort>]\n" "$id" >&2
      return 2
      ;;
  esac
  validate_configured_harness "$harness" "config/secondmate-profiles/$id" || return 2
  case "$model" in
    default|-)
      printf "error: malformed secondmate profile in config/secondmate-profiles/%s; model must be a concrete token\n" "$id" >&2
      return 2
      ;;
  esac
  case "$effort" in
    ''|low|medium|high|xhigh|max) ;;
    *)
      printf "error: malformed secondmate profile in config/secondmate-profiles/%s; effort must be low, medium, high, xhigh, or max\n" "$id" >&2
      return 2
      ;;
  esac
  SECONDMATE_PROFILE_HARNESS=$harness
  SECONDMATE_PROFILE_MODEL=$model
  SECONDMATE_PROFILE_EFFORT=$effort
}

# Print the profile that governs <id>: per-secondmate profile first, otherwise
# the legacy global setting. The final field identifies the source for callers
# that preserve the legacy global effort-token compatibility behavior.
resolve_secondmate_profile() {
  local id=$1 rc harness model effort
  parse_secondmate_profile "$id"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\t%s\t%s\t%s\n' \
      "$SECONDMATE_PROFILE_HARNESS" "$SECONDMATE_PROFILE_MODEL" "$SECONDMATE_PROFILE_EFFORT" \
      "config/secondmate-profiles/$id"
    return 0
  fi
  [ "$rc" -eq 1 ] || return "$rc"
  harness=$(resolve_secondmate) || return 1
  model=$(resolve_secondmate_model) || return 1
  effort=$(resolve_secondmate_effort) || return 1
  printf '%s\t%s\t%s\t%s\n' "$harness" "$model" "$effort" config/secondmate-harness
}

secondmate_profile_field() {
  local id=$1 field=$2 record harness model effort remainder
  record=$(resolve_secondmate_profile "$id") || return 1
  harness=${record%%$'\t'*}
  remainder=${record#*$'\t'}
  model=${remainder%%$'\t'*}
  remainder=${remainder#*$'\t'}
  effort=${remainder%%$'\t'*}
  case "$field" in
    harness) printf '%s\n' "$harness" ;;
    model) printf '%s\n' "$model" ;;
    effort) printf '%s\n' "$effort" ;;
  esac
}

secondmate_profile_usage() {
  printf 'error: %s requires exactly one secondmate id\n' "$1" >&2
  return 2
}

case "${1:-}" in
  crew) resolve_crew ;;
  secondmate)
    case "$#" in
      1) resolve_secondmate ;;
      2) secondmate_profile_field "$2" harness ;;
      *) secondmate_profile_usage secondmate ;;
    esac
    ;;
  secondmate-model)
    case "$#" in
      1) resolve_secondmate_model ;;
      2) secondmate_profile_field "$2" model ;;
      *) secondmate_profile_usage secondmate-model ;;
    esac
    ;;
  secondmate-effort)
    case "$#" in
      1) resolve_secondmate_effort ;;
      2) secondmate_profile_field "$2" effort ;;
      *) secondmate_profile_usage secondmate-effort ;;
    esac
    ;;
  secondmate-profile)
    if [ "$#" -ne 2 ]; then
      secondmate_profile_usage secondmate-profile
      exit $?
    fi
    resolve_secondmate_profile "$2"
    ;;
  *) detect_own ;;
esac
