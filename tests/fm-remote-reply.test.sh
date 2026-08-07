#!/usr/bin/env bash
# End-to-end remote reply relay through fm-on and the process-event runner.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP_ROOT=$(fm_test_tmproot fm-remote-reply)
mkdir -p "$TMP_ROOT"
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
PARENT="$TMP_ROOT/parent"
REMOTE="$TMP_ROOT/remote"
FAKEBIN=$(fm_fakebin "$TMP_ROOT/fake")
CLAIMS="$TMP_ROOT/claims"
mkdir -p "$PARENT/data" "$PARENT/state" "$REMOTE/state" "$REMOTE/data/reply" "$CLAIMS"
trap 'FM_HOME="$PARENT" FM_PROCEVENT_CLAIM_ROOT="$CLAIMS" "$ROOT/bin/fm-procevent.sh" sweep-home >/dev/null 2>&1 || true; if [ -f "$TMP_ROOT/remote-jobs/worker.pid" ]; then kill "$(cat "$TMP_ROOT/remote-jobs/worker.pid")" 2>/dev/null || true; fi; rm -rf -- "$TMP_ROOT"' EXIT

cat > "$PARENT/data/secondmates.md" <<EOF
- ios - iOS delivery (host: remote-mac; root: $ROOT; home: $REMOTE; scope: iOS work; projects: alpha; added 2026-08-02)
EOF
printf '# Detailed remote answer\n\nThe build is green.\n' > "$REMOTE/data/reply/report.md"
: > "$REMOTE/state/parent-replies.status"
SOURCE_BEFORE="$TMP_ROOT/source-before"
cp "$REMOTE/state/parent-replies.status" "$SOURCE_BEFORE"

cat > "$FAKEBIN/fake-ssh" <<'SH'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift 2 ;;
    --) shift; break ;;
    *) exit 90 ;;
  esac
done
host=$1
entry=$2
shift 2
[ "$host" = remote-mac ] || exit 91
[ "$entry" = fm-remote-entrypoint.sh ] || exit 92
exec "$FM_FAKE_REMOTE_ENTRYPOINT" "$@"
SH
chmod +x "$FAKEBIN/fake-ssh"

remote_env() {
  FM_HOME="$PARENT" \
  FM_ROOT_OVERRIDE="$ROOT" \
  FM_PROCEVENT_CLAIM_ROOT="$CLAIMS" \
  FM_SSH_BIN="$FAKEBIN/fake-ssh" \
  FM_FAKE_REMOTE_ENTRYPOINT="$ROOT/bin/fm-remote-entrypoint.sh" \
  FM_REMOTE_JOB_PLATFORM_OVERRIDE=Linux \
  FM_REMOTE_JOB_STATE_ROOT="$TMP_ROOT/remote-jobs" \
  FM_REMOTE_REPLY_WAIT_SECONDS=10 \
  FM_REMOTE_REPLY_MAX_LINE_BYTES=2048 \
  "$@"
}

wait_for() {
  local path=$1
  for _ in $(seq 1 100); do
    [ -e "$path" ] && return 0
    sleep 0.05
  done
  return 1
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

rewrite_result_payload() { # <source-result> <payload> <destination>
  local source=$1 payload=$2 destination=$3 boundary bytes hash
  boundary=$(grep -n -m 1 '^$' "$source" | cut -d: -f1)
  bytes=$(LC_ALL=C wc -c < "$payload" | tr -d ' ')
  hash=$(sha256_file "$payload")
  head -n "$boundary" "$source" \
    | sed "s/^payload_sha256=.*/payload_sha256=$hash/;s/^payload_bytes=.*/payload_bytes=$bytes/" \
    > "$destination.header"
  cat "$destination.header" "$payload" > "$destination"
  rm -f -- "$destination.header"
}

ADAPTER="$ROOT/bin/fm-procevent-remote-reply.sh"
# shellcheck source=bin/fm-pending-reply-lib.sh
. "$ROOT/bin/fm-pending-reply-lib.sh"
SID=$(remote_env "$ADAPTER" source-id ios)
out=$(remote_env "$ADAPTER" arm ios)
assert_contains "$out" "armed: $SID offset=0" "remote reply source was not armed at the empty cursor"

remote_env "$ROOT/bin/fm-procevent.sh" start "$SID" > "$TMP_ROOT/start-one.out" 2>&1 &
RUNNER=$!
wait_for "$CLAIMS/$SID.claim" || fail "process-event runner never claimed the remote reply source"
printf 'done [corr=0123456789abcdef]: build verified (data/reply/report.md)\n' \
  >> "$REMOTE/state/parent-replies.status"
wait "$RUNNER" || fail "remote reply source failed to capture its first delta"
RESULT=$(find "$PARENT/state/procevent-inbox" -name "$SID.1.result" -print -quit 2>/dev/null)
if [ -z "$RESULT" ]; then
  printf 'runner output:\n%s\n' "$(cat "$TMP_ROOT/start-one.out")" >&2
  fail "the remote reply delta was not durably captured"
fi
assert_grep 'done [corr=0123456789abcdef]' "$RESULT" "captured delta lost the correlated status line"
assert_grep "procevent remote-reply $SID 1" "$PARENT/state/.wake-queue" "runner did not publish the normalized remote-reply event"
assert_no_grep 'build verified' "$PARENT/state/.wake-queue" "reply payload leaked into the event queue"
cmp -s "$SOURCE_BEFORE" "$REMOTE/state/parent-replies.status" \
  && fail "fixture did not append the expected source line"
SOURCE_AFTER="$TMP_ROOT/source-after"
cp "$REMOTE/state/parent-replies.status" "$SOURCE_AFTER"
pass "a blocking non-destructive remote delta reaches durable process-event capture"

rm -rf "$PARENT/state/procevent"
: > "$PARENT/state/procevent"
set +e
remote_env "$ADAPTER" handle ios 1 "$RESULT" > "$TMP_ROOT/handle-arm-fail.out" 2>&1
handle_arm_rc=$?
set -e
[ "$handle_arm_rc" -ne 0 ] || fail "reply handling acknowledged a result whose re-arm failed"
assert_grep 'done [corr=0123456789abcdef]' "$PARENT/state/ios.status" "failed re-arm lost the ingested reply"
assert_grep 'ingested: ios appended=1' "$TMP_ROOT/handle-arm-fail.out" "failed re-arm did not commit the reply before retry"
rm -f "$PARENT/state/procevent"
mkdir "$PARENT/state/procevent"
reconcile_out=$(remote_env "$ROOT/bin/fm-procevent.sh" reconcile)
assert_contains "$reconcile_out" 'published=1' "failed re-arm did not leave the result eligible for retry"
out=$(remote_env "$ADAPTER" handle ios 1 "$RESULT")
assert_contains "$out" 'ingested: ios appended=0' "retried reply ingest was not idempotent"
assert_contains "$out" 'handled: remote-reply-ios 1' "captured generation was not acknowledged"
assert_grep 'done [corr=0123456789abcdef]' "$PARENT/state/ios.status" "parent status did not receive the correlated reply"
assert_grep 'data/remote-secondmates/ios/data/reply/report.md' "$PARENT/state/ios.status" "remote document pointer was not rewritten locally"
cmp -s "$REMOTE/data/reply/report.md" "$PARENT/data/remote-secondmates/ios/data/reply/report.md" \
  || fail "the path-confined remote document copy is not byte-identical"
cmp -s "$SOURCE_AFTER" "$REMOTE/state/parent-replies.status" \
  || fail "handling consumed or rewrote the remote append-only log"
expected_offset=$(LC_ALL=C wc -c < "$REMOTE/state/parent-replies.status" | tr -d ' ')
assert_grep "offset=$expected_offset" "$PARENT/state/remote-replies/ios.cursor" "reply cursor did not advance to the committed delta"
pass "ingest appends one validated line, fetches its document, and advances the cursor"

out=$(remote_env "$ADAPTER" handle ios 1 "$RESULT")
assert_contains "$out" 'ingested: ios appended=0' "replayed result was not deduplicated"
assert_contains "$out" 'already-handled: remote-reply-ios 1' "replayed generation was not acknowledged idempotently"
[ "$(grep -cF 'done [corr=0123456789abcdef]' "$PARENT/state/ios.status")" -eq 1 ] \
  || fail "replayed ingest duplicated the parent status line"
pass "replayed capture has one deduplicated append and one durable handling identity"

printf 'working [corr=1111111111111111]: second generation\n' \
  >> "$REMOTE/state/parent-replies.status"
remote_env "$ROOT/bin/fm-procevent.sh" start "$SID" >/dev/null \
  || fail "second reply generation was not captured"
RESULT_TWO="$PARENT/state/procevent-inbox/$SID.2.result"
ln -s "$TMP_ROOT/missing-handled-marker" "$PARENT/state/procevent-inbox/$SID.2.handled"
set +e
remote_env "$ADAPTER" handle ios 2 "$RESULT_TWO" > "$TMP_ROOT/handle-two-unacked.out" 2>&1
handle_two_rc=$?
set -e
[ "$handle_two_rc" -ne 0 ] || fail "second generation acknowledged through an unsafe handled marker"
assert_grep 'working [corr=1111111111111111]' "$PARENT/state/ios.status" "unacknowledged generation was not ingested"
printf 'done [corr=2222222222222222]: third generation\n' \
  >> "$REMOTE/state/parent-replies.status"
remote_env "$ROOT/bin/fm-procevent.sh" start "$SID" >/dev/null \
  || fail "third reply generation was not captured"
RESULT_THREE="$PARENT/state/procevent-inbox/$SID.3.result"
remote_env "$ADAPTER" handle ios 3 "$RESULT_THREE" >/dev/null \
  || fail "third reply generation was not handled"
rm -f "$PARENT/state/procevent-inbox/$SID.2.handled"
out=$(remote_env "$ADAPTER" handle ios 2 "$RESULT_TWO")
assert_contains "$out" 'ingested: ios appended=0' "earlier generation did not replay from its durable ingestion receipt"
assert_contains "$out" 'handled: remote-reply-ios 2' "earlier generation remained unacknowledged after later cursor advancement"
[ "$(grep -cF 'working [corr=1111111111111111]' "$PARENT/state/ios.status")" -eq 1 ] \
  || fail "earlier generation replay duplicated its parent status"
pass "later generations cannot invalidate an unacknowledged ingested result"

# Keyed decisions and transport correlation are separate metadata groups in the
# established status-line grammar. The adapter must ingest the combined shape,
# resolve its pending expectation, commit the cursor and receipt, and replay it
# without a second append.
TWO_GROUP_CORR=$(fm_pending_reply_create "$PARENT" "$PARENT/state" ios "remote auth decision") \
  || fail "could not create the pending correlation fixture"
fm_pending_reply_mark_delivered "$PARENT/state" "$TWO_GROUP_CORR" 1700000000 \
  || fail "could not mark the pending correlation delivered"
TWO_GROUP_LINE="needs-decision [key=dagu-observer-auth] [corr=$TWO_GROUP_CORR]: remote auth decision"
printf '%s\n' "$TWO_GROUP_LINE" >> "$REMOTE/state/parent-replies.status"
remote_env "$ROOT/bin/fm-procevent.sh" start "$SID" >/dev/null \
  || fail "the two-group remote reply was not captured"
RESULT_FOUR="$PARENT/state/procevent-inbox/$SID.4.result"
out=$(remote_env "$ADAPTER" handle ios 4 "$RESULT_FOUR") \
  || fail "the two-group remote reply was rejected by handle"
assert_contains "$out" 'ingested: ios appended=1' \
  "the two-group remote reply was not appended exactly once"
assert_grep "$TWO_GROUP_LINE" "$PARENT/state/ios.status" \
  "the two-group lifecycle line was not preserved in the parent status log"
[ "$(grep -cF "$TWO_GROUP_LINE" "$PARENT/state/ios.status")" -eq 1 ] \
  || fail "the two-group lifecycle line was appended more than once"
TWO_GROUP_RECORD=$(fm_pending_reply_path "$PARENT/state" "$TWO_GROUP_CORR")
assert_grep 'phase=resolved' "$TWO_GROUP_RECORD" \
  "the two-group remote reply did not resolve its pending correlation"
assert_grep 'resolved_via=status' "$TWO_GROUP_RECORD" \
  "the two-group remote reply resolved through an unexpected path"
assert_present "$PARENT/state/remote-replies/ios.4.ingested" \
  "the two-group remote reply did not commit its ingestion receipt"
expected_offset=$(LC_ALL=C wc -c < "$REMOTE/state/parent-replies.status" | tr -d ' ')
assert_grep "offset=$expected_offset" "$PARENT/state/remote-replies/ios.cursor" \
  "the two-group remote reply did not commit its cursor"
out=$(remote_env "$ADAPTER" handle ios 4 "$RESULT_FOUR")
assert_contains "$out" 'ingested: ios appended=0' \
  "the two-group replay was not idempotent"
assert_contains "$out" 'already-handled: remote-reply-ios 4' \
  "the two-group replay did not acknowledge its existing receipt"
[ "$(grep -cF "$TWO_GROUP_LINE" "$PARENT/state/ios.status")" -eq 1 ] \
  || fail "the two-group replay duplicated the parent status line"
pass "a two-group keyed decision reply resolves, commits, and replays idempotently"

# Each rejection below uses a transport-digest-valid result at the committed
# cursor, so the assertion exercises the adapter's public ingest boundary rather
# than an earlier result-integrity or cursor check.
CURSOR_BEFORE_INVALID="$TMP_ROOT/cursor-before-invalid"
cp "$PARENT/state/remote-replies/ios.cursor" "$CURSOR_BEFORE_INVALID"
try_reject_payload() { # <name> <payload-file>
  local name=$1 payload_file=$2 bad_result="$TMP_ROOT/$1.result"
  rewrite_result_payload "$RESULT_FOUR" "$payload_file" "$bad_result"
  if remote_env "$ADAPTER" ingest ios "$bad_result" > "$TMP_ROOT/$name.out" 2>&1; then
    fail "$name payload was accepted"
  fi
  cmp -s "$CURSOR_BEFORE_INVALID" "$PARENT/state/remote-replies/ios.cursor" \
    || fail "$name rejection changed the committed cursor"
  [ "$(grep -cF "$TWO_GROUP_LINE" "$PARENT/state/ios.status")" -eq 1 ] \
    || fail "$name rejection disturbed the accepted two-group reply"
}

printf 'done [key=unclosed [corr=%s: malformed\n' "$TWO_GROUP_CORR" \
  > "$TMP_ROOT/unclosed-group.payload"
printf 'done [key=unclosed [corr=%s]: malformed\n' "$TWO_GROUP_CORR" \
  > "$TMP_ROOT/nested-group.payload"
printf 'needs-decision [key=bad key] [corr=%s]: unsafe key\n' "$TWO_GROUP_CORR" \
  > "$TMP_ROOT/unsafe-key.payload"
printf 'done [corr=0123456789abcde]: short correlation\n' \
  > "$TMP_ROOT/short-correlation.payload"
printf 'done [corr=0123456789abcdef0]: long correlation\n' \
  > "$TMP_ROOT/long-correlation.payload"
printf 'unexpected done [corr=%s]: malformed prefix\n' "$TWO_GROUP_CORR" \
  > "$TMP_ROOT/arbitrary-prefix.payload"
printf 'needs-decision [key=missing-correlation]: no correlation\n' \
  > "$TMP_ROOT/missing-correlation.payload"
printf 'done [corr=%s]: control\001byte\n' "$TWO_GROUP_CORR" \
  > "$TMP_ROOT/control-byte.payload"
oversized_note=$(printf '%2050s' '' | tr ' ' x)
printf 'done [corr=%s]: %s\n' "$TWO_GROUP_CORR" "$oversized_note" \
  > "$TMP_ROOT/oversized.payload"
printf 'done [corr=%s]: data/../secret.md\n' "$TWO_GROUP_CORR" \
  > "$TMP_ROOT/unsafe-document.payload"
printf 'unsupported [corr=%s]: unsupported lifecycle\n' "$TWO_GROUP_CORR" \
  > "$TMP_ROOT/unsupported-verb.payload"
try_reject_payload unclosed-group "$TMP_ROOT/unclosed-group.payload"
try_reject_payload nested-group "$TMP_ROOT/nested-group.payload"
try_reject_payload unsafe-key "$TMP_ROOT/unsafe-key.payload"
try_reject_payload short-correlation "$TMP_ROOT/short-correlation.payload"
try_reject_payload long-correlation "$TMP_ROOT/long-correlation.payload"
try_reject_payload arbitrary-prefix "$TMP_ROOT/arbitrary-prefix.payload"
try_reject_payload missing-correlation "$TMP_ROOT/missing-correlation.payload"
try_reject_payload control-byte "$TMP_ROOT/control-byte.payload"
try_reject_payload oversized "$TMP_ROOT/oversized.payload"
try_reject_payload unsafe-document "$TMP_ROOT/unsafe-document.payload"
try_reject_payload unsupported-verb "$TMP_ROOT/unsupported-verb.payload"
pass "remote reply rejects malformed metadata, prefixes, missing correlations, control bytes, oversized lines, unsafe documents, and unsupported verbs"

# A digest-valid but uncorrelated line is still rejected at the public ingest
# boundary. Recalculate its payload commitment so the behavioral assertion is
# specifically about status validation, not incidental digest failure.
BAD_RESULT="$TMP_ROOT/bad.result"
printf 'done [corr=no-correlation]: no correlation\n' > "$TMP_ROOT/bad.payload"
rewrite_result_payload "$RESULT_FOUR" "$TMP_ROOT/bad.payload" "$BAD_RESULT"
if remote_env "$ADAPTER" ingest ios "$BAD_RESULT" >/dev/null 2>&1; then
  fail "ingest accepted a status line with no correlation token"
fi
[ "$(grep -cF 'done [corr=0123456789abcdef]' "$PARENT/state/ios.status")" -eq 1 ] \
  || fail "invalid ingest disturbed the accepted parent status line"
pass "ingest rejects uncorrelated payload even when its transport digest is valid"

# The adapter re-armed at the committed cursor. Truncation is detected from the
# next blocking source and escalated once; it is never silently treated as a new
# log or re-armed past the break.
printf 'failed [corr=fedcba9876543210]: source was replaced\n' > "$REMOTE/state/parent-replies.status"
remote_env "$ROOT/bin/fm-procevent.sh" start "$SID" > "$TMP_ROOT/start-two.out" 2>&1 &
RUNNER=$!
wait "$RUNNER" || fail "continuity break was not captured as a structured result"
RESULT_FIVE=$(find "$PARENT/state/procevent-inbox" -name "$SID.5.result" -print -quit)
[ -n "$RESULT_FIVE" ] || fail "continuity break produced no durable result"
[ "$(remote_env "$ADAPTER" classify "$RESULT_FIVE")" = continuity-broken ] \
  || fail "truncated source was not classified as a continuity break"
set +e
remote_env "$ADAPTER" handle ios 5 "$RESULT_FIVE" > "$TMP_ROOT/handle-five.out" 2>&1
handle_rc=$?
set -e
[ "$handle_rc" -eq 3 ] || fail "continuity handling returned an unexpected status: $handle_rc"
assert_grep 'blocked [key=remote-reply-continuity-ios]' "$PARENT/state/ios.status" "continuity break did not escalate"
assert_absent "$PARENT/state/procevent/$SID.source" "continuity break was re-armed without an operator rebase"
remote_env "$ADAPTER" ingest ios "$RESULT_FIVE" >/dev/null 2>&1 || true
[ "$(grep -cF 'blocked [key=remote-reply-continuity-ios]' "$PARENT/state/ios.status")" -eq 1 ] \
  || fail "continuity replay duplicated the escalation"
pass "truncation is detected, escalated once, and not silently rebased"

rm -f "$PARENT/state/procevent-inbox/$SID.5.handled"
if remote_env "$ADAPTER" retire ios > "$TMP_ROOT/retire-pending.out" 2>&1; then
  fail "remote reply retirement accepted an unhandled captured result"
fi
assert_grep 'unhandled captured result' "$TMP_ROOT/retire-pending.out" \
  "remote reply retirement did not explain its pending-result refusal"
assert_absent "$PARENT/state/procevent/$SID.source" \
  "refused retirement left the reply source running past its pending-result check"
remote_env "$ADAPTER" handle ios 5 "$RESULT_FIVE" >/dev/null 2>&1 || [ "$?" -eq 3 ] \
  || fail "pending continuity result could not be acknowledged after retirement refusal"
remote_env "$ADAPTER" retire ios >/dev/null
assert_absent "$PARENT/state/remote-replies/ios.cursor" "adapter retirement left its cursor"
pass "remote reply retirement quiesces and refuses unhandled captured results"

echo "ALL TESTS PASSED"
