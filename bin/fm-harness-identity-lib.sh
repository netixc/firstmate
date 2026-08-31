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

fm_harness_process_identity() {
  local comm=$1 args=${2:-} executable=${3:-} image=${4:-} argv0 arg1 rest identity interpreter entrypoint
  argv0=${args%% *}
  rest=${args#* }
  [ "$rest" != "$args" ] || rest=
  arg1=${rest%% *}
  for entrypoint in "$comm" "$argv0" "$executable"; do
    identity=$(fm_harness_excluded_entrypoint "$entrypoint" || true)
    [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  done
  interpreter=$(basename -- "$comm")
  case "$interpreter:$arg1" in
    bash:/*|bash:./*|bash:../*|bash:*.sh|\
    sh:/*|sh:./*|sh:../*|sh:*.sh|\
    zsh:/*|zsh:./*|zsh:../*|zsh:*.sh|\
    dash:/*|dash:./*|dash:../*|dash:*.sh|\
    node:/*|node:./*|node:../*|node:*.js|node:*.mjs|node:*.cjs|\
    nodejs:/*|nodejs:./*|nodejs:../*|nodejs:*.js|nodejs:*.mjs|nodejs:*.cjs|\
    python:/*|python:./*|python:../*|python:*.py|\
    python[0-9]*:/*|python[0-9]*:./*|python[0-9]*:../*|python[0-9]*:*.py|\
    ruby:/*|ruby:./*|ruby:../*|ruby:*.rb|\
    perl:/*|perl:./*|perl:../*|perl:*.pl|\
    bun:/*|bun:./*|bun:../*|bun:*.js|bun:*.mjs|bun:*.cjs|\
    deno:/*|deno:./*|deno:../*|deno:*.js|deno:*.mjs|deno:*.ts)
      identity=$(fm_harness_excluded_install_path "$arg1" || true)
      [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
      ;;
  esac
  [ "$(basename -- "$comm")" = pi ] || return 1
  case "$(basename -- "$executable"):$image" in
    pi:*) printf 'pi\n' ;;
    node:*'/pi-coding-agent/'*|nodejs:*'/pi-coding-agent/'*) printf 'pi\n' ;;
    *) return 1 ;;
  esac
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
  identity=$(fm_harness_process_identity "$comm" "$args" "$executable" || true)
  if fm_harness_identity_excluded "$identity"; then
    printf '%s\n' "$identity"
    return 0
  fi
  [ "$(basename -- "$comm")" = pi ] || return 1
  image=$(fm_harness_pid_pi_image "$pid" || true)
  fm_harness_process_identity "$comm" "$args" "$executable" "$image"
}

fm_harness_identity_excluded() {
  case "$1" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) return 0 ;;
    *) return 1 ;;
  esac
}
