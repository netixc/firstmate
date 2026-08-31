#!/usr/bin/env bash

fm_harness_excluded_entrypoint() {
  local path=${1:-} base
  [ -n "$path" ] || return 1
  base=$(basename -- "$path")
  case "$base" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) printf '%s\n' "$base"; return 0 ;;
    pi-signed.*) printf 'pi-signed\n'; return 0 ;;
    claude.*) printf 'claude\n'; return 0 ;;
    codex.*) printf 'codex\n'; return 0 ;;
    opencode.*) printf 'opencode\n'; return 0 ;;
    grok.*) printf 'grok\n'; return 0 ;;
    kimi.*) printf 'kimi\n'; return 0 ;;
    cursor.*) printf 'cursor\n'; return 0 ;;
    muse.*) printf 'muse\n'; return 0 ;;
  esac
  case "$path" in
    */claude/versions/*) printf 'claude\n'; return 0 ;;
    */codex/bin/*) printf 'codex\n'; return 0 ;;
    */opencode/bin/*) printf 'opencode\n'; return 0 ;;
    */grok/bin/*) printf 'grok\n'; return 0 ;;
    */kimi/bin/*) printf 'kimi\n'; return 0 ;;
    */cursor/bin/*) printf 'cursor\n'; return 0 ;;
    */muse/bin/*) printf 'muse\n'; return 0 ;;
  esac
  return 1
}

fm_harness_process_identity() {
  local comm=$1 args=${2:-} argv0 arg1 rest identity interpreter
  argv0=${args%% *}
  rest=${args#* }
  [ "$rest" != "$args" ] || rest=
  arg1=${rest%% *}
  identity=$(fm_harness_excluded_entrypoint "$comm" || true)
  [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  identity=$(fm_harness_excluded_entrypoint "$argv0" || true)
  [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
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
      identity=$(fm_harness_excluded_entrypoint "$arg1" || true)
      [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
      ;;
  esac
  [ "$(basename -- "$comm")" = pi ] || return 1
  printf 'pi\n'
}

fm_harness_identity_excluded() {
  case "$1" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) return 0 ;;
    *) return 1 ;;
  esac
}
