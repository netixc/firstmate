#!/usr/bin/env bash
# fm-busy-lib.sh - owner of plain Pi semantic busy-state classification.
# Pi's per-task extension writes generation-bound lifecycle records. Missing,
# malformed, stale, or unsupported-harness evidence is unknown, never idle.

FM_BUSY_LIB_VERSION=v1

fm_busy_record_path() { printf '%s/%s.busy-state' "$1" "$2"; }
fm_busy_gen_path() { printf '%s/%s.busy-gen' "$1" "$2"; }

fm_busy_token_valid() {
  case "${1:-}" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
}

fm_busy_current_gen() {
  local path gen
  path=$(fm_busy_gen_path "$1" "$2")
  [ -f "$path" ] || return 1
  IFS= read -r gen < "$path" 2>/dev/null || gen=
  fm_busy_token_valid "$gen" || return 1
  printf '%s' "$gen"
}

fm_busy_sources_for_harness() {
  [ "${1:-}" = pi ] || { printf ''; return 0; }
  printf 'pi-ext fm-spawn fm-interrupt fm-recovery'
}

fm_busy_source_trusted() {
  local trusted
  trusted=$(fm_busy_sources_for_harness "$1")
  case " $trusted " in *" $2 "*) return 0 ;; esac
  return 1
}

fm_busy_record_read() {
  local state=$1 id=$2 rec gen line extra ver field
  local r_gen='' r_seq='' r_state='' r_source='' r_event='' r_ts=''
  rec=$(fm_busy_record_path "$state" "$id")
  [ -f "$rec" ] || { printf 'missing'; return 1; }
  gen=$(fm_busy_current_gen "$state" "$id") || { printf 'malformed'; return 1; }
  # shellcheck disable=SC2034 # second read proves the record has one line
  { IFS= read -r line && ! IFS= read -r extra; } < "$rec" 2>/dev/null || { printf 'malformed'; return 1; }
  local -a fields
  IFS=' ' read -r -a fields <<< "$line"
  ver=${fields[0]:-}
  [ "$ver" = "$FM_BUSY_LIB_VERSION" ] || { printf 'malformed'; return 1; }
  for field in "${fields[@]:1}"; do
    case "$field" in
      gen=*) r_gen=${field#gen=} ;; seq=*) r_seq=${field#seq=} ;;
      state=*) r_state=${field#state=} ;; source=*) r_source=${field#source=} ;;
      event=*) r_event=${field#event=} ;; ts=*) r_ts=${field#ts=} ;;
      *) printf 'malformed'; return 1 ;;
    esac
  done
  if ! fm_busy_token_valid "$r_gen" || ! fm_busy_token_valid "$r_source" || ! fm_busy_token_valid "$r_event"; then
    printf 'malformed'
    return 1
  fi
  case "$r_seq" in ''|*[!0-9]*) printf 'malformed'; return 1 ;; esac
  case "$r_ts" in ''|*[!0-9]*) printf 'malformed'; return 1 ;; esac
  case "$r_state" in busy|idle|unknown) ;; *) printf 'malformed'; return 1 ;; esac
  [ "$r_gen" = "$gen" ] || { printf 'gen-mismatch'; return 1; }
  printf '%s %s %s %s' "$r_state" "$r_source" "$r_event" "$r_seq"
}

fm_busy_classify() {
  local backend=$1 target=$2 harness=$3 id=$4 state=$5 explicit_meta=${7-}
  local out rc r_state r_source native
  if [ "$harness" != pi ]; then
    printf 'unknown unsupported-harness'
    return 0
  fi
  out=$(fm_busy_record_read "$state" "$id") && rc=0 || rc=$?
  if [ "$rc" = 0 ]; then
    r_state=${out%% *}; out=${out#* }; r_source=${out%% *}
    if fm_busy_source_trusted "$harness" "$r_source"; then
      printf '%s %s' "$r_state" "$r_source"
    else
      printf 'unknown source-mismatch'
    fi
    return 0
  fi
  case "$out" in malformed|gen-mismatch) printf 'unknown %s' "$out"; return 0 ;; esac
  if [ "$backend" = herdr ] && command -v fm_backend_busy_state >/dev/null 2>&1; then
    native=$(fm_backend_busy_state "$backend" "$target" "fm-$id" "$explicit_meta" 2>/dev/null || true)
    [ "$native" = busy ] && { printf 'busy herdr-native'; return 0; }
  fi
  printf 'unknown missing'
}

fm_busy_classify_live() {
  local backend=$1 target=$2 harness=$3 id=$4 state=$5 label=${6-}
  [ "$harness" = pi ] || { printf 'unknown unsupported-harness'; return 0; }
  [ -n "$target" ] || { printf 'unknown no-target'; return 0; }
  fm_backend_target_exists "$backend" "$target" "$label" 2>/dev/null \
    || { printf 'dead endpoint-gone'; return 0; }
  fm_busy_classify "$backend" "$target" "$harness" "$id" "$state"
}

fm_busy_classify_meta() {
  local meta=$1 id=$2 state=$3 backend target harness
  [ -f "$meta" ] || { printf 'unknown missing'; return 0; }
  backend=$(fm_backend_of_meta "$meta")
  target=$(fm_backend_target_of_meta "$meta")
  harness=$(fm_meta_get "$meta" harness)
  [ "$harness" = pi ] || { printf 'unknown unsupported-harness'; return 0; }
  [ -n "$target" ] || { printf 'unknown no-target'; return 0; }
  fm_busy_classify "$backend" "$target" "$harness" "$id" "$state" "" "$meta"
}

fm_busy_is_busy() {
  local verdict
  verdict=$(fm_busy_classify "$@")
  [ "${verdict%% *}" = busy ]
}
