#!/usr/bin/env bash

fm_harness_process_identity() {
  local comm=$1 args=${2:-} argv0 arg1 rest candidate base
  argv0=${args%% *}
  rest=${args#* }
  [ "$rest" != "$args" ] || rest=
  arg1=${rest%% *}
  for candidate in "$comm" "$argv0"; do
    [ -n "$candidate" ] || continue
    base=$(basename -- "$candidate")
    case "$base" in
      pi) printf 'pi\n'; return 0 ;;
      pi-signed|claude|codex|opencode|grok|kimi|cursor|muse)
        printf '%s\n' "$base"
        return 0
        ;;
    esac
    case "$candidate" in
      */claude/versions/*) printf 'claude\n'; return 0 ;;
    esac
  done
  case "$(basename -- "$argv0")" in
    node*|python*) candidate=$arg1 ;;
    *) candidate= ;;
  esac
  base=$(basename -- "${candidate:-.}")
  case "$base" in
    pi) printf 'pi\n'; return 0 ;;
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) printf '%s\n' "$base"; return 0 ;;
  esac
  case "$candidate" in
    */claude/versions/*) printf 'claude\n'; return 0 ;;
  esac
  return 1
}

fm_harness_identity_excluded() {
  case "$1" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) return 0 ;;
    *) return 1 ;;
  esac
}
