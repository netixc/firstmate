#!/usr/bin/env bash
# Backend-neutral Pi process identity.
# Sourced by bin/backends/tmux.sh and bin/backends/herdr.sh. This file is
# sourced by scripts and has no side effects on source.
#
# Why one owner: every runtime backend that proves an agent is alive does it by
# attributing operating-system processes - the pane's foreground process group
# on tmux, Herdr's `pane process-info` view plus the pane shell's descendants
# on Herdr - and the two must agree on what exact Pi identity means, or Pi can
# read as a dead pane on one backend.
# The classifier moved here verbatim from the tmux adapter, where it was born;
# docs/tmux-backend.md "Agent liveness probe" owns the empirical basis for the
# names below, and tests/fm-tmux-agent-liveness.test.sh plus
# tests/fm-harness-liveness-drift-live-e2e.test.sh keep them honest.

# shellcheck source=bin/fm-session-lock-lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/fm-session-lock-lib.sh"
# fm_agent_process_classify_name: the single owner of the process-name
# vocabulary shared by every liveness signal - `agent` for exact Pi identity,
# `shell` for an idle login/interactive shell, `other` for anything else.
# Keeping one classifier means independent name sources (a kernel process
# name, an argv[0], a rendered pane title) can never drift into disagreeing
# about what a given name means.
fm_agent_process_classify_name() {  # <path> [argv0] -> agent|shell|other
  local path=$1 argv0=${2:-} base
  base=${path##*/}
  base=${base#-}
  case "$base" in
    pi) printf 'agent' ;;
    zsh|bash|sh|dash|ash|ksh|mksh|tcsh|csh|fish) printf 'shell' ;;
    *)
      if fm_harness_path_name "$path" >/dev/null || fm_harness_path_name "$argv0" >/dev/null; then
        printf 'agent'
      else
        printf 'other'
      fi
      ;;
  esac
}

# fm_agent_process_classify: one process, from every identity surface a
# backend can hand over, as agent|shell|other. Any single surface naming an
# exact Pi executable carries `agent`, because a false negative is the one outcome
# that launches a duplicate agent onto a live worktree; `shell` needs every
# readable surface to agree the process is a shell; anything else is `other`.
#
#   <name>   the kernel process name (ps comm, or Herdr's process-info .name):
#            on Linux the exec name, on macOS argv[0] truncated to 16 bytes.
#   <argv0>  argv[0] as the process reports it - a bare name or an install
#            path, whichever the launcher used (empty when unknown).
#   <args>   the flattened command line (currently unused).
#   [pid]    the live process id (currently unused).
fm_agent_process_classify() {  # <name> <argv0> <args> [pid] -> agent|shell|other
  local name=${1:-} argv0=${2:-} by_name by_argv0
  by_name=$(fm_agent_process_classify_name "$name" "$argv0")
  [ "$by_name" != agent ] || { printf 'agent'; return 0; }
  if [ -n "$argv0" ]; then
    # argv[0] is classified as a path in its own right, so only its exact
    # executable basename can identify `pi` (or a login shell such as `-zsh`).
    by_argv0=$(fm_agent_process_classify_name "$argv0" "$argv0")
    [ "$by_argv0" != agent ] || { printf 'agent'; return 0; }
  else
    by_argv0=$by_name
  fi
  if [ "$by_name" = shell ] && [ "$by_argv0" = shell ]; then
    printf 'shell'
  else
    printf 'other'
  fi
}
