#!/usr/bin/env bash
set -eu

ROOT=$1
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/fm-selfann-evidence.XXXXXX")
trap 'FM_HOME="$FIXTURE/home" FM_PROCEVENT_CLAIM_ROOT="$FIXTURE/claims" "$ROOT/bin/fm-procevent.sh" sweep-home >/dev/null 2>&1 || true; rm -rf "$FIXTURE"' EXIT
HOME_DIR="$FIXTURE/home"
ADAPTER_ROOT="$FIXTURE/adapters"
SOURCE_ID="self-src-evidence-$$"
mkdir -p "$HOME_DIR/state" "$ADAPTER_ROOT/bin" "$FIXTURE/claims"

cat > "$ADAPTER_ROOT/bin/fm-procevent-selfann.sh" <<'SH'
#!/usr/bin/env bash
case "${1-}" in
  self-announcing) exit 0 ;;
  autohandle)
    [ ! -e "$FM_HOME/state/selfann-fail" ] || exit 1
    printf '%s %s\n' "$2" "$3" >> "$FM_HOME/state/applied"
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
  FM_HOME="$HOME_DIR" \
    "$ROOT/bin/fm-procevent.sh" "$@"
}

printf 'SOURCE_ID=%s\n' "$SOURCE_ID"
pe register selfann "$SOURCE_ID" -- /bin/echo 'self announced'
first_start=$(pe start "$SOURCE_ID" 2>&1)
printf '%s\n' "$first_start"
case "$first_start" in *"autohandled: $SOURCE_ID"*) ;; *) exit 1 ;; esac
test -f "$HOME_DIR/state/procevent-inbox/$SOURCE_ID.1.handled"
printf 'HANDLED_MARKER_1=present\n'

pe retire "$SOURCE_ID"
reconcile_out=$(pe reconcile)
printf '%s\n' "$reconcile_out"
case "$reconcile_out" in *"published=0 started=0"*) ;; *) exit 1 ;; esac
test ! -f "$HOME_DIR/state/procevent/$SOURCE_ID.source"
test ! -f "$FIXTURE/claims/$SOURCE_ID.claim"
printf 'REGISTERED_AFTER_RECONCILE=no\n'
printf 'CLAIM_AFTER_RECONCILE=no\n'

: > "$HOME_DIR/state/selfann-fail"
pe register selfann "$SOURCE_ID" -- /bin/echo 'self announced'
second_start=$(pe start "$SOURCE_ID" 2>&1)
printf '%s\n' "$second_start"
case "$second_start" in *"not-autohandled: $SOURCE_ID"*) ;; *) exit 1 ;; esac
test ! -f "$HOME_DIR/state/procevent-inbox/$SOURCE_ID.2.handled"
wake_2=$(awk -F '\t' '{print $5}' "$HOME_DIR/state/.wake-queue" | grep -F "procevent selfann $SOURCE_ID 2")
test -n "$wake_2"
printf 'HANDLED_MARKER_2=missing\n'
printf 'WAKE_2=%s\n' "$wake_2"

pe retire "$SOURCE_ID"
test ! -f "$HOME_DIR/state/procevent/$SOURCE_ID.source"
test ! -f "$FIXTURE/claims/$SOURCE_ID.claim"
printf 'REGISTERED_AFTER_CLEANUP=no\n'
printf 'CLAIM_AFTER_CLEANUP=no\n'
