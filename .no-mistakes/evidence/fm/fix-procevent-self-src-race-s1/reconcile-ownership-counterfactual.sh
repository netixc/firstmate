#!/usr/bin/env bash
set -eu

ROOT=$1
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/fm-reconcile-counterfactual.XXXXXX")
HOME_DIR="$FIXTURE/home"
CLAIMS="$FIXTURE/claims"
SOURCE_ID="unique-reconcile-src-$$"
TRIGGER="$FIXTURE/trigger"
trap 'FM_HOME="$HOME_DIR" FM_PROCEVENT_CLAIM_ROOT="$CLAIMS" "$ROOT/bin/fm-procevent.sh" sweep-home >/dev/null 2>&1 || true; rm -rf "$FIXTURE"' EXIT
mkdir -p "$HOME_DIR/state" "$CLAIMS"

cat > "$FIXTURE/blocker.sh" <<'SH'
#!/usr/bin/env bash
while [ ! -e "$1" ]; do sleep 0.02; done
printf 'released\n'
SH
chmod +x "$FIXTURE/blocker.sh"

pe() { FM_HOME="$HOME_DIR" FM_PROCEVENT_CLAIM_ROOT="$CLAIMS" "$ROOT/bin/fm-procevent.sh" "$@"; }

printf 'WITH_RECONCILE\n'
pe register lavish "$SOURCE_ID" -- "$FIXTURE/blocker.sh" "$TRIGGER"
pe reconcile
for _ in $(seq 1 100); do [ -s "$CLAIMS/$SOURCE_ID.claim" ] && break; sleep 0.02; done
test -s "$CLAIMS/$SOURCE_ID.claim"
owned_out=$(pe start "$SOURCE_ID" 2>&1)
printf 'manual-start=%s\n' "$owned_out"
case "$owned_out" in *"already owned: $SOURCE_ID"*) ;; *) exit 1 ;; esac
: > "$TRIGGER"
for _ in $(seq 1 100); do [ -f "$HOME_DIR/state/procevent-inbox/$SOURCE_ID.1.result" ] && break; sleep 0.02; done
test -f "$HOME_DIR/state/procevent-inbox/$SOURCE_ID.1.result"
pe retire "$SOURCE_ID" >/dev/null
printf 'cleanup-claim=%s\n' "$(test -f "$CLAIMS/$SOURCE_ID.claim" && echo present || echo absent)"

printf 'WITHOUT_RECONCILE\n'
pe register lavish "$SOURCE_ID" -- /bin/echo 'manual succeeds'
manual_out=$(pe start "$SOURCE_ID" 2>&1)
printf '%s\n' "$manual_out"
case "$manual_out" in *"captured:"*) ;; *) exit 1 ;; esac
pe retire "$SOURCE_ID" >/dev/null
printf 'cleanup-registration=%s\n' "$(test -f "$HOME_DIR/state/procevent/$SOURCE_ID.source" && echo present || echo absent)"
printf 'cleanup-claim=%s\n' "$(test -f "$CLAIMS/$SOURCE_ID.claim" && echo present || echo absent)"
