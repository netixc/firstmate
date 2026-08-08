#!/usr/bin/env bash
# Inspect local runtime settings that must be explicitly migrated to Pi-only profiles.
# Usage: fm-pi-runtime-migrate.sh [--config <dir>] --check
#
# This command never changes local configuration.
# It prints every obsolete runtime-selection surface and exits 1 when action is needed.
# Create config/crew-profile and config/secondmate-profile with <model> [<thinking>].
# Rewrite config/secondmate-profiles/<id> from "pi <model> [<thinking>]" to
# "<model> [<thinking>]".
# Remove config/crew-harness and config/secondmate-harness after copying any
# model/thinking selection into the new profile files.
# Rewrite crew-dispatch JSON profile objects without a harness field.
set -u

CONFIG=
MODE=
usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; $d' >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      CONFIG=$2
      shift 2
      ;;
    --config=*) CONFIG=${1#--config=}; shift ;;
    --check) MODE=check; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[ "$MODE" = check ] || { usage; exit 2; }
if [ -z "$CONFIG" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
  FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
  CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
fi

found=0
report() {
  found=1
  printf 'PI_RUNTIME_MIGRATION: %s\n' "$1"
}

if [ -e "$CONFIG/crew-harness" ] || [ -L "$CONFIG/crew-harness" ]; then
  report "config/crew-harness is obsolete; remove it and use config/crew-profile with <model> [<thinking>] when an ordinary-worker pin is needed"
fi
if [ -e "$CONFIG/secondmate-harness" ] || [ -L "$CONFIG/secondmate-harness" ]; then
  report "config/secondmate-harness is obsolete; move a Pi model/thinking pin to config/secondmate-profile, then remove the old file"
fi
if [ -e "$CONFIG/secondmate-profiles" ] || [ -L "$CONFIG/secondmate-profiles" ]; then
  if [ ! -d "$CONFIG/secondmate-profiles" ] || [ -L "$CONFIG/secondmate-profiles" ]; then
    report "config/secondmate-profiles must be a non-symlink directory before Pi-only profiles can be read"
  else
    for profile in "$CONFIG/secondmate-profiles"/*; do
      [ -e "$profile" ] || [ -L "$profile" ] || continue
      [ -f "$profile" ] && [ ! -L "$profile" ] || {
        report "config/secondmate-profiles/${profile##*/} must be a regular non-symlink file"
        continue
      }
      line=$(awk '
        /^[[:space:]]*($|#)/ { next }
        { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; exit }
      ' "$profile" 2>/dev/null || true)
      # shellcheck disable=SC2086 # Deliberate first-token extraction for a legacy schema check.
      set -- $line
      case "${1:-}" in
        pi)
          report "config/secondmate-profiles/${profile##*/} uses the old leading pi runtime token; remove that token and retain only <model> [<thinking>]"
          ;;
        claude|codex|grok)
          report "config/secondmate-profiles/${profile##*/} selects an unsupported runtime; choose a Pi model and rewrite it as <model> [<thinking>]"
          ;;
      esac
    done
  fi
fi
if [ -f "$CONFIG/crew-dispatch.json" ] && grep -q '"harness"' "$CONFIG/crew-dispatch.json"; then
  report "config/crew-dispatch.json contains obsolete harness fields; retain only Pi model and thinking fields in every profile object"
fi

if [ "$found" -eq 0 ]; then
  printf 'PI_RUNTIME_MIGRATION: no obsolete runtime selections found in %s\n' "$CONFIG"
  exit 0
fi
printf 'PI_RUNTIME_MIGRATION: no local configuration was changed; make the listed edits explicitly, then rerun this command\n'
exit 1
