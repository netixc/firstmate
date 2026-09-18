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
# verbs addressed to an exact task id, with Pi mechanics owned
# here rather than improvised per harness in agent prose.
#
# This file owns three capability tables plus their pure artifact-path tables
# and nothing else. It has no side effects, runs no backend command, and reads
# no state, so it can be sourced by a test as a pure contract:
#
#   1. Verb allowlist. There is no arbitrary-text and no generic raw-key entry
#      point on the control plane; a caller either names an allowlisted verb or
#      is refused.
#   2. Pi control mechanics: which key interrupts a running turn, how
#      many times it must be sent, whether the composer needs clearing after
#      that key, which adapter-owned cancellation acknowledgement is observable,
#      which command exits the agent, and which task kinds the adapter is
#      verified to run. These are the empirically verified facts previously
#      carried only in the harness-adapters skill's per-adapter tables; that
#      skill now points here so one executable owner holds them, and
#      bin/fm-send.sh's --key path reads the same table rather than a second
#      copy of it.
#   3. Per-backend capability: which named keys a runtime backend can deliver,
#      and whether the backend has a recovery-grade agent-state classifier
#      (bin/fm-backend.sh's fm_backend_agent_state) able to PROVE that an agent
#      stopped. A verb whose postcondition cannot be proven on the recorded
#      backend is refused rather than performed blind.
#
# `resume` is deliberately NOT a verb because Pi has no verified pane-resume
# contract. `relaunch` covers the same need deterministically,
# because the brief on disk - not a harness-private session - is the durable
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

# Pi is the only runtime whose control mechanics are supported. Mirrors
# AGENTS.md section 4; any other runtime is refused rather
# than guessed at, exactly as a spawn on it would be.
fm_control_harness_supported() {  # <harness>
  case "${1-}" in
    pi) return 0 ;;
  esac
  return 1
}

# The Pi adapter a recorded harness value belongs to. An unrecognized
# value returns nonzero rather than being guessed into a family.
fm_control_harness_family() {  # <recorded-harness>
  case "${1-}" in
    pi) printf 'pi' ;;
    *) return 1 ;;
  esac
}

# Which task kinds an adapter is verified to run. The control plane asks this
# BEFORE it stops anything, so an incompatible relaunch target is refused while
# the current agent is still running rather than after it has been stopped.
fm_control_harness_supports_kind() {  # <harness> <kind>
  local harness=${1-}
  fm_control_harness_supported "$harness" || return 1
  return 0
}

# The key that cancels a running turn.
fm_control_interrupt_key() {  # <harness>
  case "${1-}" in
    pi) printf 'Escape' ;;
    *) return 1 ;;
  esac
}

# How many times the interrupt key must be delivered.
fm_control_interrupt_repeat() {  # <harness>
  case "${1-}" in
    pi) printf '1' ;;
    *) return 1 ;;
  esac
}

# The key that must follow the interrupt key to leave the composer empty, or
# nothing when the adapter needs none. Prints the key or nothing; a harness
# with no verified mechanics returns nonzero, matching the tables above.
fm_control_interrupt_clear_key() {  # <harness>
  case "${1-}" in
    pi) ;;
    *) return 1 ;;
  esac
}

fm_control_interrupt_ack_source() {  # <harness>
  case "${1-}" in
    pi) printf 'none' ;;
    *) return 1 ;;
  esac
}

# The command that exits the agent from its own composer.
fm_control_exit_command() {  # <harness>
  case "${1-}" in
    pi) printf '/quit' ;;
    *) return 1 ;;
  esac
}

# Which named keys a backend adapter can deliver.
fm_control_backend_supports_key() {  # <backend> <key>
  local backend=${1-} key=${2-}
  case "$backend" in
    tmux|herdr)
      case "$key" in Escape|Enter|C-c|C-u) return 0 ;; esac
      ;;
  esac
  return 1
}

# Whether <backend> has a recovery-grade agent-state classifier.
fm_control_backend_state_verified() {  # <backend>
  case "${1-}" in
    tmux|herdr) return 0 ;;
  esac
  return 1
}

# The per-task wiring artifacts a harness leaves behind, so a relaunch that
# changes harness (or re-arms the same one with a fresh busy generation) can
# clear the previous incarnation's wiring instead of leaving a stale hook
# pointing at a retired generation. Prints zero or more absolute paths, one per
# line: worktree-resident hook files and firstmate-owned state tokens only,
# never a harness's own managed config.
fm_control_harness_wiring_paths() {  # <harness> <worktree> <state-dir> <id>
  local harness=${1-} wt=${2-} state=${3-} id=${4-}
  [ -n "$wt" ] && [ -n "$state" ] && [ -n "$id" ] || return 1
  case "$harness" in
    pi) printf '%s\n' "$state/$id.pi-ext.ts" ;;
  esac
}
