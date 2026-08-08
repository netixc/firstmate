#!/usr/bin/env bash
# Own Firstmate's Pi semantic busy-state contract.
#
# Pi task extensions write a generation-bound record through fm-busy-event.sh.
# Missing, malformed, stale, unsupported, or untrusted state is unknown, never idle.
# A gone endpoint is the only process-level override and is reported as dead.

FM_BUSY_LIB_VERSION=v1

fm_busy_record_path() { # <state-dir> <id>
  printf '%s/%s.busy-state' "$1" "$2"
}

fm_busy_gen_path() { # <state-dir> <id>
  printf '%s/%s.busy-gen' "$1" "$2"
}

fm_busy_token_valid() { # <value>
  case "${1:-}" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

fm_busy_current_gen() { # <state-dir> <id>
  local gen_file gen
  gen_file=$(fm_busy_gen_path "$1" "$2")
  [ -f "$gen_file" ] || return 1
  IFS= read -r gen < "$gen_file" 2>/dev/null || gen=
  fm_busy_token_valid "$gen" || return 1
  printf '%s' "$gen"
}

fm_busy_sources_for_harness() { # <runtime>
  case "${1:-}" in
    pi) printf '%s' 'pi-ext fm-spawn fm-interrupt fm-recovery' ;;
    *) printf '%s' '' ;;
  esac
}

fm_busy_source_trusted() { # <runtime> <source>
  local trusted
  trusted=$(fm_busy_sources_for_harness "$1")
  case " $trusted " in *" $2 "*) return 0 ;; esac
  return 1
}

# Print "<state> <source> <event> <seq>" for a valid current record.
# On failure print missing, malformed, or gen-mismatch and return nonzero.
fm_busy_record_read() { # <state-dir> <id>
  local state=$1 id=$2 rec gen line ver f
  local r_gen='' r_seq='' r_state='' r_source='' r_event='' r_ts=''
  local -a fields
  rec=$(fm_busy_record_path "$state" "$id")
  if [ ! -f "$rec" ]; then
    printf 'missing'
    return 1
  fi
  if ! gen=$(fm_busy_current_gen "$state" "$id"); then
    printf 'malformed'
    return 1
  fi
  { IFS= read -r line && ! IFS= read -r _; } < "$rec" 2>/dev/null || {
    printf 'malformed'
    return 1
  }
  IFS=' ' read -r -a fields <<< "$line"
  ver=${fields[0]:-}
  [ "$ver" = "$FM_BUSY_LIB_VERSION" ] || { printf 'malformed'; return 1; }
  for f in "${fields[@]:1}"; do
    case "$f" in
      gen=*) r_gen=${f#gen=} ;;
      seq=*) r_seq=${f#seq=} ;;
      state=*) r_state=${f#state=} ;;
      source=*) r_source=${f#source=} ;;
      event=*) r_event=${f#event=} ;;
      ts=*) r_ts=${f#ts=} ;;
      *) printf 'malformed'; return 1 ;;
    esac
  done
  if ! fm_busy_token_valid "$r_gen" \
    || ! fm_busy_token_valid "$r_source" \
    || ! fm_busy_token_valid "$r_event"; then
    printf 'malformed'
    return 1
  fi
  case "$r_seq" in ''|*[!0-9]*) printf 'malformed'; return 1 ;; esac
  case "$r_ts" in ''|*[!0-9]*) printf 'malformed'; return 1 ;; esac
  case "$r_state" in busy|idle|unknown) ;; *) printf 'malformed'; return 1 ;; esac
  if [ "$r_gen" != "$gen" ]; then
    printf 'gen-mismatch'
    return 1
  fi
  printf '%s %s %s %s' "$r_state" "$r_source" "$r_event" "$r_seq"
}

# Delivery-only rendered busy signature for the primary pane.
# Task state uses Pi lifecycle records rather than rendered text.
FM_PI_BUSY_REGEX_DEFAULT='Working\.\.\.'
fm_busy_lines_match() { # [runtime]
  local runtime=${1:-pi} lines regex
  IFS= read -r -d '' lines || true
  case "$runtime" in pi) ;; *) return 1 ;; esac
  regex=${FM_BUSY_REGEX:-$FM_PI_BUSY_REGEX_DEFAULT}
  printf '%s' "$lines" | grep -qiE "$regex"
}

# Print "busy|idle|unknown <source>" for an established endpoint.
fm_busy_classify() { # <backend> <target> <runtime> <id> <state-dir> [unused-tail]
  local backend=$1 target=$2 runtime=$3 id=$4 state=$5
  local out rc r_state r_source native
  [ "$runtime" = pi ] || {
    printf 'unknown unsupported-runtime'
    return 0
  }
  out=$(fm_busy_record_read "$state" "$id") && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    r_state=${out%% *}
    out=${out#* }
    r_source=${out%% *}
    if fm_busy_source_trusted "$runtime" "$r_source"; then
      printf '%s %s' "$r_state" "$r_source"
    else
      printf 'unknown source-mismatch'
    fi
    return 0
  fi
  case "$out" in
    malformed|gen-mismatch)
      printf 'unknown %s' "$out"
      return 0
      ;;
  esac
  if [ "$backend" = herdr ] && command -v fm_backend_busy_state >/dev/null 2>&1; then
    native=$(fm_backend_busy_state "$backend" "$target" 2>/dev/null || true)
    if [ "$native" = busy ]; then
      printf 'busy herdr-native'
      return 0
    fi
  fi
  printf 'unknown missing'
}

fm_busy_classify_live() { # <backend> <target> <runtime> <id> <state-dir> [expected-label]
  local backend=$1 target=$2 runtime=$3 id=$4 state=$5 label=${6-}
  if [ -z "$target" ]; then
    printf 'unknown no-target'
    return 0
  fi
  if ! fm_backend_target_exists "$backend" "$target" "$label" 2>/dev/null; then
    printf 'dead endpoint-gone'
    return 0
  fi
  fm_busy_classify "$backend" "$target" "$runtime" "$id" "$state"
}

fm_busy_classify_meta() { # <meta-file> <id> <state-dir> [unused-tail]
  local meta=$1 id=$2 state=$3 backend target runtime
  [ -f "$meta" ] || { printf 'unknown missing'; return 0; }
  backend=$(fm_backend_of_meta "$meta")
  target=$(fm_backend_target_of_meta "$meta")
  runtime=$(fm_meta_get "$meta" harness)
  if [ -z "$target" ]; then
    printf 'unknown no-target'
    return 0
  fi
  fm_busy_classify "$backend" "$target" "$runtime" "$id" "$state"
}

fm_busy_is_busy() {
  local verdict
  verdict=$(fm_busy_classify "$@")
  [ "${verdict%% *}" = busy ]
}
