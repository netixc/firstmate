#!/usr/bin/env bash
# Shared Firstmate host-platform detection and refusal.
#
# A Firstmate host is the machine executing a primary or secondmate home.
# Only uname -s values Darwin and Linux are supported. WSL2 reports Linux and
# follows that path. Native Windows compatibility shells report another value
# and are refused with every other unsupported or unknown host.

fm_host_platform_raw() { # [raw-platform]
  local raw
  if [ "$#" -gt 0 ]; then
    raw=$1
  else
    raw=$(uname -s 2>/dev/null || true)
  fi
  [ -n "$raw" ] || raw=unknown
  printf '%s\n' "$raw"
}

fm_host_platform_supported() { # [raw-platform]
  local raw
  raw=$(fm_host_platform_raw "$@")
  case "$raw" in
    Darwin|Linux) return 0 ;;
    *) return 1 ;;
  esac
}

fm_host_platform_name() { # [raw-platform]
  local raw
  raw=$(fm_host_platform_raw "$@")
  case "$raw" in
    Darwin) printf 'darwin\n' ;;
    Linux) printf 'linux\n' ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

fm_host_platform_diagnostic() { # [raw-platform]
  local raw
  raw=$(fm_host_platform_raw "$@")
  printf 'UNSUPPORTED_HOST: %s - Firstmate hosts require macOS or Linux; native Windows, Git Bash, MSYS, and Cygwin are unsupported. WSL2 remains supported when Firstmate runs inside its Linux environment.\n' "$raw"
}

fm_host_platform_require() { # [raw-platform]
  local raw
  raw=$(fm_host_platform_raw "$@")
  if fm_host_platform_supported "$raw"; then
    return 0
  fi
  fm_host_platform_diagnostic "$raw"
  return 1
}
