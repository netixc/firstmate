#!/usr/bin/env bash

fm_harness_excluded_name() {
  case "${1:-}" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) printf '%s\n' "$1"; return 0 ;;
    cursor-agent) printf 'cursor\n'; return 0 ;;
    muse-bin-*) printf 'muse\n'; return 0 ;;
  esac
  return 1
}

fm_harness_excluded_install_path() {
  local path=${1:-}
  case "$path" in
    */bin/pi-signed) printf 'pi-signed\n'; return 0 ;;
    */bin/claude|*/claude/versions/*) printf 'claude\n'; return 0 ;;
    */bin/codex) printf 'codex\n'; return 0 ;;
    */bin/opencode|*/opencode/bin/opencode.js) printf 'opencode\n'; return 0 ;;
    */bin/grok) printf 'grok\n'; return 0 ;;
    */bin/kimi) printf 'kimi\n'; return 0 ;;
    */bin/cursor|*/bin/cursor-agent) printf 'cursor\n'; return 0 ;;
    */bin/muse|*/bin/muse-bin-*) printf 'muse\n'; return 0 ;;
  esac
  return 1
}

fm_harness_excluded_entrypoint() {
  local path=${1:-} identity
  [ -n "$path" ] || return 1
  identity=$(fm_harness_excluded_name "$(basename -- "$path")" || true)
  [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  fm_harness_excluded_install_path "$path"
}

fm_harness_interpreter() {
  case "$(basename -- "${1:-}")" in
    bash|sh|zsh|dash|node|nodejs|python|python[0-9]*|ruby|perl|bun|deno) return 0 ;;
    *) return 1 ;;
  esac
}

fm_harness_command_entrypoint() {
  local comm=$1 args=${2:-}
  fm_harness_interpreter "$comm" || return 1
  python3 - "$args" <<'PY'
import shlex
import sys
try:
    words = shlex.split(sys.argv[1])
except ValueError:
    raise SystemExit(1)
for word in words[1:]:
    if word == "--":
        continue
    if not word.startswith("-"):
        print(word)
        break
PY
}

fm_harness_process_identity() {
  local comm=$1 args=${2:-} executable=${3:-} argv0 identity entrypoint
  argv0=${args%% *}
  for entrypoint in "$comm" "$argv0" "$executable"; do
    identity=$(fm_harness_excluded_entrypoint "$entrypoint" || true)
    [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  done
  entrypoint=$(fm_harness_command_entrypoint "$comm" "$args" || true)
  identity=$(fm_harness_excluded_install_path "$entrypoint" || true)
  [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  return 1
}

fm_harness_pid_excluded_argv() {
  local pid=$1 comm=$2 fallback=${3:-} arg entrypoint= index=0 identity
  fm_harness_interpreter "$comm" || return 1
  if [ -r "/proc/$pid/cmdline" ]; then
    while IFS= read -r -d '' arg; do
      index=$((index + 1))
      [ "$index" -gt 1 ] || continue
      case "$arg" in --|-*) continue ;; esac
      entrypoint=$arg
      break
    done < "/proc/$pid/cmdline"
  else
    entrypoint=$(fm_harness_command_entrypoint "$comm" "$fallback" || true)
  fi
  identity=$(fm_harness_excluded_install_path "$entrypoint" || true)
  [ -z "$identity" ] || printf '%s\n' "$identity"
  [ -n "$identity" ]
}

fm_harness_pid_pi_registration() {
  local pid=$1 root state_dir marker marker_pid marker_start current_start
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  state_dir=${FM_STATE_OVERRIDE:-${FM_HOME:-${FM_ROOT_OVERRIDE:-$root}}/state}
  marker="$state_dir/.pi-processes/$pid"
  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  marker_pid=$(sed -n '2p' "$marker" 2>/dev/null)
  marker_start=$(sed -n '3p' "$marker" 2>/dev/null)
  [ "$marker_pid" = "$pid" ] && [ -n "$marker_start" ] || return 1
  current_start=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ "$current_start" = "$marker_start" ]
}

fm_harness_pid_executable() {
  local pid=$1 path
  if [ -e "/proc/$pid/exe" ]; then
    readlink "/proc/$pid/exe" 2>/dev/null
    return
  fi
  path=$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

fm_harness_pid_pi_image() {
  local pid=$1
  if [ -r "/proc/$pid/maps" ]; then
    grep -m1 '/pi-coding-agent/' "/proc/$pid/maps"
    return
  fi
  lsof -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p' | grep -m1 '/pi-coding-agent/'
}

fm_harness_pid_identity() {
  local pid=$1 comm=$2 args=${3:-} identity executable image
  executable=$(fm_harness_pid_executable "$pid" || true)
  identity=$(fm_harness_pid_excluded_argv "$pid" "$comm" "$args" || true)
  if fm_harness_identity_excluded "$identity"; then
    printf '%s\n' "$identity"
    return 0
  fi
  identity=$(fm_harness_process_identity "$comm" "$args" "$executable" || true)
  if fm_harness_identity_excluded "$identity"; then
    printf '%s\n' "$identity"
    return 0
  fi
  [ "$(basename -- "$comm")" = pi ] || return 1
  fm_harness_pid_pi_registration "$pid" || return 1
  image=$(fm_harness_pid_pi_image "$pid" || true)
  case "$(basename -- "$executable"):$image" in
    node:*'/pi-coding-agent/'*|nodejs:*'/pi-coding-agent/'*) printf 'pi\n' ;;
    *) return 1 ;;
  esac
}

fm_harness_identity_excluded() {
  case "$1" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) return 0 ;;
    *) return 1 ;;
  esac
}
