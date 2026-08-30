#!/usr/bin/env bash
# fm-control-lib.sh - executable owner of worker lifecycle control mechanics.
# Plain Pi is the only supported harness. Exact identity is required: legacy or
# excluded harness values are unsupported and are never normalized to Pi.

fm_control_verbs() {
  printf '%s\n' interrupt exit relaunch
}

fm_control_verb_allowed() {
  case "${1-}" in interrupt|exit|relaunch) return 0 ;; esac
  return 1
}

fm_control_harness_supported() {
  [ "${1-}" = pi ]
}

fm_control_harness_family() {
  [ "${1-}" = pi ] || return 1
  printf 'pi'
}

fm_control_harness_supports_kind() {
  [ "${1-}" = pi ] && case "${2-}" in crewmate|scout|secondmate) return 0 ;; esac
  return 1
}

fm_control_interrupt_key() {
  [ "${1-}" = pi ] || return 1
  printf 'Escape'
}

fm_control_interrupt_repeat() {
  [ "${1-}" = pi ] || return 1
  printf '1'
}

fm_control_interrupt_clear_key() {
  [ "${1-}" = pi ] || return 1
}

fm_control_interrupt_ack_source() {
  [ "${1-}" = pi ] || return 1
  printf 'none'
}

fm_control_exit_command() {
  [ "${1-}" = pi ] || return 1
  printf '/quit'
}

fm_control_backend_supports_key() {
  local backend=${1-} key=${2-}
  case "$backend" in
    tmux|herdr|zellij|cmux) case "$key" in Escape|Enter|C-c|C-u) return 0 ;; esac ;;
    orca) case "$key" in Enter|C-c) return 0 ;; esac ;;
  esac
  return 1
}

fm_control_backend_state_verified() {
  case "${1-}" in tmux|herdr) return 0 ;; esac
  return 1
}

fm_control_harness_wiring_paths() {
  local harness=${1-} state=${3-} id=${4-}
  [ "$harness" = pi ] && [ -n "$state" ] && [ -n "$id" ] || return 1
  printf '%s\n' "$state/$id.pi-ext.ts"
}

# Plain Pi has no global turn-end token registry.
fm_control_harness_turnend_token_path() {
  [ "${1-}" = pi ] || return 1
}

fm_control_harness_turnend_auth_path() {
  [ "${1-}" = pi ] || return 1
}
