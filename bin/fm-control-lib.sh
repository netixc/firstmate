#!/usr/bin/env bash
# fm-control-lib.sh - the ONE executable owner of firstmate's agent lifecycle
# CONTROL-PLANE mechanics.
#
# Data plane vs control plane (captain-approved root architecture, 2026-07-13).
# bin/fm-send.sh is the DATA plane: conversational text for the agent to read,
# always routing-marked for a kind=secondmate target so the reply comes back
# through the status path. That marking is exactly right for a message and
# exactly wrong for a lifecycle command: a marked "/quit" arrives as ordinary
# chat ("[fm-from-firstmate] /quit") that the agent reasons ABOUT instead of
# executing. bin/fm-control.sh is the CONTROL plane: allowlisted lifecycle
# verbs addressed to an exact task id, with Pi mechanics owned here rather
# than improvised in agent prose.
#
# This file owns the verb allowlist and fixed Pi lifecycle values.
# It has no side effects, runs no session command, and reads no state, so it can
# be sourced by a test as a pure contract:
#
#   1. Verb allowlist. There is no arbitrary-text and no generic raw-key entry
#      point on the control plane; a caller either names an allowlisted verb or
#      is refused.
#   2. Pi control mechanics: which key interrupts a running turn, how many
#      times it must be sent, and which command exits the agent.
# Herdr owns key delivery and recovery-grade process state. A verb whose
# postcondition cannot be proven by those direct primitives is refused rather
# than performed blind.
#
# `resume` is deliberately NOT a verb. Pi has no verified pane-resume
# contract. `relaunch` covers the same need deterministically,
# because the brief on disk - not a Pi-private session - is the durable
# instruction.

# The complete control-plane verb allowlist, one per line.
fm_control_verbs() {
  cat <<'EOF'
interrupt
exit
relaunch
EOF
}

fm_control_verb_allowed() {  # <verb>
  case "${1-}" in
    interrupt|exit|relaunch) return 0 ;;
  esac
  return 1
}

# The Pi key that cancels a running turn.
fm_control_interrupt_key() {
  printf 'Escape'
}

# How many times Pi's interrupt key must be delivered.
fm_control_interrupt_repeat() {
  printf '1'
}

# The command that exits Pi from its own composer.
fm_control_exit_command() {
  printf '/quit'
}
