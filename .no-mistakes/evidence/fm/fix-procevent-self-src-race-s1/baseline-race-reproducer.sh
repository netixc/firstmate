#!/usr/bin/env bash
set -eu

ROOT=$1
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/fm-selfann-baseline.XXXXXX")
trap 'for home in "$FIXTURE"/home-*; do [ -d "$home" ] || continue; FM_HOME="$home" FM_PROCEVENT_CLAIM_ROOT="$FIXTURE/claims" "$ROOT/bin/fm-procevent.sh" sweep-home >/dev/null 2>&1 || true; done; rm -rf "$FIXTURE"' EXIT
ADAPTER_ROOT="$FIXTURE/adapters"
mkdir -p "$ADAPTER_ROOT/bin" "$FIXTURE/claims"

cat > "$ADAPTER_ROOT/bin/fm-procevent-selfann.sh" <<'SH'
#!/usr/bin/env bash
case "${1-}" in
  self-announcing) exit 0 ;;
  autohandle)
    [ ! -e "$FM_HOME/state/selfann-fail" ] || exit 1
    "$FM_PROCEVENT_UNDER_TEST" handled "$2" "$3" >/dev/null
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$ADAPTER_ROOT/bin/fm-procevent-selfann.sh"

pe() {
  FM_ROOT_OVERRIDE="$ADAPTER_ROOT" \
  FM_PROCEVENT_UNDER_TEST="$ROOT/bin/fm-procevent.sh" \
  FM_PROCEVENT_CLAIM_ROOT="$FIXTURE/claims" \
  FM_HOME="$1" "$ROOT/bin/fm-procevent.sh" "${@:2}"
}

for attempt in $(seq 1 30); do
  home="$FIXTURE/home-$attempt"
  source_id="self-src-baseline-$attempt-$$"
  mkdir -p "$home/state"
  pe "$home" register selfann "$source_id" -- /bin/echo 'self announced' >/dev/null
  pe "$home" start "$source_id" >/dev/null 2>&1
  reconcile_out=$(pe "$home" reconcile)
  : > "$home/state/selfann-fail"
  manual_out=$(pe "$home" start "$source_id" 2>&1 || true)
  if printf '%s\n' "$manual_out" | grep -F 'already owned' >/dev/null; then
    printf 'attempt=%s\n' "$attempt"
    printf '%s\n' "$reconcile_out"
    printf 'manual-start=%s\n' "$manual_out"
    pe "$home" retire "$source_id" >/dev/null
    printf 'cleanup-registration=%s\n' "$(test -f "$home/state/procevent/$source_id.source" && echo present || echo absent)"
    printf 'cleanup-claim=%s\n' "$(test -f "$FIXTURE/claims/$source_id.claim" && echo present || echo absent)"
    exit 0
  fi
  pe "$home" retire "$source_id" >/dev/null
done

printf 'race-not-observed-in-30-attempts\n' >&2
exit 1
