#!/usr/bin/env bash
# End-to-end behavior tests for exact Pi admission proof on fm-send's
# metadata-routed Herdr path. The real fm-spawn generates the per-task Pi
# extension, a stateful fake Herdr drives its public lifecycle event, and the
# real fm-send owns target resolution, one-body injection, Enter handling, and
# final exit status. No assertion inspects implementation source bytes.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SEND="$ROOT/bin/fm-send.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
RECEIPT="$ROOT/bin/fm-pi-admission.sh"
TMP_ROOT=$(fm_test_tmproot fm-send-pi-admission)
CASE="$TMP_ROOT/case"
HOME_DIR="$CASE/home"
PROJ_DIR="$CASE/project"
WT_DIR="$CASE/wt"
FAKEBIN="$CASE/fakebin"
ID=pi-admission-e2e
MESSAGE=$'busy steer: café\nexact second line'
mkdir -p "$HOME_DIR/data/$ID" "$HOME_DIR/projects" "$HOME_DIR/state" "$HOME_DIR/config" "$FAKEBIN"
printf 'pi\n' > "$HOME_DIR/config/crew-harness"
printf 'brief\nDelivery contract: mode=no-mistakes\n' > "$HOME_DIR/data/$ID/brief.md"
touch "$HOME_DIR/state/.last-watcher-beat"
fm_git_worktree "$PROJ_DIR" "$WT_DIR" admission-e2e

cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "$FM_FAKE_PANE_PATH"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows|has-session|new-session|new-window|kill-window|send-keys) exit 0 ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/tmux"
fm_fake_exit0 "$FAKEBIN" treehouse pi

spawn_out=$(FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" \
  FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
  FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
  FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$WT_DIR" TMUX='fake,1,0' \
  PATH="$FAKEBIN:$PATH" \
  "$SPAWN" "$ID" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1)
expect_code 0 $? "fixture spawn should generate the Pi extension: $spawn_out"
EXT="$HOME_DIR/state/$ID.pi-ext.ts"
assert_present "$EXT" "fixture spawn did not generate its Pi extension"
GEN=$(sed -n 's/^busy_gen=//p' "$HOME_DIR/state/$ID.meta" | tail -1)
[ -n "$GEN" ] || fail "fixture spawn did not record busy_gen"

# Rebind the generated task record to the fake Herdr endpoint. fm-send still
# resolves this through the public exact task-selector path.
cat > "$HOME_DIR/state/$ID.meta" <<EOF
window=fm-lab-admission:w1:p2
endpoint_task_id=$ID
worktree=$WT_DIR
project=$PROJ_DIR
harness=pi
kind=ship
mode=no-mistakes
yolo=off
busy_gen=$GEN
backend=herdr
herdr_session=fm-lab-admission
herdr_workspace_id=w1
herdr_tab_id=w1:t1
herdr_pane_id=w1:p2
EOF

cat > "$FAKEBIN/fm-admission-drive" <<'JS'
#!/usr/bin/env node
const { pathToFileURL } = require("node:url");
const { readFileSync } = require("node:fs");
(async () => {
  const shape = process.argv[2];
  const mod = await import(pathToFileURL(process.env.FM_ADMISSION_EXT).href);
  const handlers = {};
  mod.default({ on: (name, fn) => { handlers[name] = fn; } });
  const text = shape === "unrelated"
    ? "different accepted user message"
    : readFileSync(process.env.FM_ADMISSION_BODY, "utf8");
  const content = shape === "mixed"
    ? [{ type: "text", text }, { type: "image", data: "not-a-receipt" }]
    : [{ type: "text", text }];
  await handlers.message_start({ message: { role: "user", content } }, {});
})().catch((error) => { console.error(error); process.exit(1); });
JS
chmod +x "$FAKEBIN/fm-admission-drive"

cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
set -u
action=${FM_ADMISSION_ACTION:-none}
log=${FM_ADMISSION_LOG:?}
state=${FM_ADMISSION_STATE:?}
id=${FM_ADMISSION_ID:?}
gen=${FM_ADMISSION_GEN:?}
receipt="$state/$id.pi-admission"
body=${FM_ADMISSION_BODY:?}
helper=${FM_ADMISSION_HELPER:?}

record_exact() { "$FM_ADMISSION_DRIVER" exact; }
record_direct() { # <sha> <bytes>
  "$helper" record "$state" "$id" --gen "$gen" --sha256 "$1" --bytes "$2" --ts "$(($(date +%s) * 1000))"
}
body_hash() { printf '%s' "$(cat "$body")" | "$helper" hash; }

case "${1:-} ${2:-}" in
  "status --json")
    printf '%s\n' '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"version":"0.8.0","protocol":19}}'
    ;;
  "pane get")
    printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p2"}}}'
    ;;
  "pane send-text")
    printf '%s' "${4:-}" > "$body"
    printf 'body\n' >> "$log"
    if [ "${FM_ADMISSION_CONCURRENCY_GUARD:-0}" = 1 ]; then
      mkdir "$FM_ADMISSION_GUARD" 2>/dev/null || exit 9
      /bin/sleep 0.2
      rmdir "$FM_ADMISSION_GUARD"
    fi
    if [ "$action" = literal-fail-receipt ]; then
      record_exact
      exit 1
    fi
    ;;
  "agent get")
    enter_count=$(grep -c '^enter$' "$log" 2>/dev/null || true)
    case "$action" in
      idle-native) status=idle; [ "$enter_count" -eq 0 ] || status=working ;;
      swallowed-enter) status=idle; [ "$enter_count" -lt 2 ] || status=working ;;
      empty-composer) status=blocked ;;
      stops-working) status=working; [ "$enter_count" -eq 0 ] || status=idle ;;
      *) status=working ;;
    esac
    printf '{"result":{"agent":{"agent":"pi","agent_status":"%s"}}}\n' "$status"
    ;;
  "pane send-keys")
    printf 'enter\n' >> "$log"
    enter_count=$(grep -c '^enter$' "$log" 2>/dev/null || true)
    case "$action" in
      exact|literal-fail-receipt) record_exact ;;
      concurrent-exact) record_exact ;;
      mixed) "$FM_ADMISSION_DRIVER" mixed ;;
      unrelated) "$FM_ADMISSION_DRIVER" unrelated ;;
      swallowed-enter) [ "$enter_count" -lt 2 ] || record_exact ;;
      wrong-digest)
        IFS=$'\t' read -r _hash bytes <<EOF
$(body_hash)
EOF
        record_direct "$(printf '0%.0s' {1..64})" "$bytes"
        ;;
      wrong-length)
        IFS=$'\t' read -r hash bytes <<EOF
$(body_hash)
EOF
        record_direct "$hash" $((bytes + 1))
        ;;
      malformed) printf 'v1 broken\n' > "$receipt" ;;
      stale)
        IFS=$'\t' read -r hash bytes <<EOF
$(body_hash)
EOF
        printf 'v1 gen=stale.gen seq=1 sha256=%s bytes=%s ts=%s\n' "$hash" "$bytes" "$(($(date +%s) * 1000))" > "$receipt"
        ;;
      unreadable)
        record_exact
        chmod 000 "$receipt"
        ;;
      truncated)
        IFS=$'\t' read -r hash bytes <<EOF
$(body_hash)
EOF
        printf 'v1 gen=%s seq=1 sha256=%s bytes=%s ts=%s' "$gen" "$hash" "$bytes" "$(($(date +%s) * 1000))" > "$receipt"
        ;;
      unsafe-symlink)
        IFS=$'\t' read -r hash bytes <<EOF
$(body_hash)
EOF
        outside="$state/outside-receipt"
        printf 'v1 gen=%s seq=1 sha256=%s bytes=%s ts=%s\n' "$gen" "$hash" "$bytes" "$(($(date +%s) * 1000))" > "$outside"
        ln -s "$outside" "$receipt"
        ;;
      unsafe-hardlink)
        IFS=$'\t' read -r hash bytes <<EOF
$(body_hash)
EOF
        outside="$state/outside-receipt"
        printf 'v1 gen=%s seq=1 sha256=%s bytes=%s ts=%s\n' "$gen" "$hash" "$bytes" "$(($(date +%s) * 1000))" > "$outside"
        chmod 600 "$outside"
        ln "$outside" "$receipt"
        ;;
      stops-working) record_exact ;;
    esac
    ;;
  "pane read")
    if [ "$action" = empty-composer ]; then
      printf '\033[38;2;129;162;190m─────────────────────────────────────────────────────\033[0m\n\033[7m \033[0m\n\033[38;2;129;162;190m─────────────────────────────────────────────────────\033[0m\n'
    else
      printf '%% bare shell-shaped unknown\n'
    fi
    ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/herdr"

RECEIPT_PATH="$HOME_DIR/state/$ID.pi-admission"
LOG="$CASE/herdr.log"
BODY="$CASE/body.txt"
DRIVER="$FAKEBIN/fm-admission-drive"
GUARD="$CASE/concurrent.guard"

reset_case() {
  chmod 600 "$RECEIPT_PATH" 2>/dev/null || true
  rm -f "$RECEIPT_PATH" "$HOME_DIR/state/outside-receipt" "$LOG" "$BODY"
  rmdir "$GUARD" 2>/dev/null || true
  : > "$LOG"
}

run_send() { # <action> [message]
  local action=$1 message=${2:-$MESSAGE}
  PATH="$FAKEBIN:$PATH" FM_HOME="$HOME_DIR" FM_SEND_SETTLE=0 \
    FM_SEND_SLEEP=0 FM_PI_ADMISSION_SLEEP=0 FM_PI_ADMISSION_POLLS=2 \
    FM_ADMISSION_ACTION="$action" FM_ADMISSION_LOG="$LOG" \
    FM_ADMISSION_STATE="$(cd "$HOME_DIR/state" && pwd -P)" FM_ADMISSION_ID="$ID" \
    FM_ADMISSION_GEN="$GEN" FM_ADMISSION_EXT="$EXT" FM_ADMISSION_BODY="$BODY" \
    FM_ADMISSION_HELPER="$RECEIPT" FM_ADMISSION_DRIVER="$DRIVER" \
    FM_ADMISSION_GUARD="$GUARD" \
    "$SEND" "$ID" "$message" >/dev/null 2>"$CASE/send.err"
}

assert_injection_counts() { # <bodies> <enters> <label>
  local want_bodies=$1 want_enters=$2 label=$3 got_bodies got_enters
  got_bodies=$(grep -c '^body$' "$LOG" 2>/dev/null || true)
  got_enters=$(grep -c '^enter$' "$LOG" 2>/dev/null || true)
  [ "$got_bodies" -eq "$want_bodies" ] || fail "$label typed $got_bodies bodies, expected $want_bodies"
  [ "$got_enters" -eq "$want_enters" ] || fail "$label sent $got_enters Enters, expected $want_enters"
}

test_busy_exact_receipt_confirms_once() {
  local rc
  reset_case
  run_send exact; rc=$?
  expect_code 0 "$rc" "already-working Pi with an exact admitted receipt should return success: $(cat "$CASE/send.err")"
  assert_injection_counts 1 1 "exact busy admission"
  [ "$(cat "$BODY")" = "$MESSAGE" ] || fail "exact busy admission changed the literal payload"
  pass "fm-send Pi admission: an already-working Pi can become UI-unknown, admit once, and return success from an exact receipt"
}

test_no_or_unusable_receipt_never_confirms() {
  local action rc
  for action in none malformed stale wrong-digest wrong-length mixed unreadable truncated unrelated unsafe-symlink unsafe-hardlink stops-working; do
    reset_case
    run_send "$action"; rc=$?
    [ "$rc" -ne 0 ] || fail "$action receipt case falsely confirmed delivery"
    assert_injection_counts 1 1 "$action receipt case"
  done
  pass "fm-send Pi admission: missing, malformed, stale-generation, mismatched, mixed, unreadable, truncated, unrelated, and unsafe-path receipts stay unconfirmed"
}

test_old_boundary_never_confirms() {
  local rc
  reset_case
  printf '%s' "$MESSAGE" > "$BODY"
  FM_ADMISSION_EXT="$EXT" FM_ADMISSION_BODY="$BODY" "$DRIVER" exact
  run_send none; rc=$?
  [ "$rc" -ne 0 ] || fail "a receipt present before the send boundary falsely confirmed delivery"
  assert_injection_counts 1 1 "old-boundary receipt"
  pass "fm-send Pi admission: an exact receipt at the old sequence boundary cannot acknowledge a later send"
}

test_literal_failure_cannot_be_rescued() {
  local rc
  reset_case
  run_send literal-fail-receipt; rc=$?
  [ "$rc" -ne 0 ] || fail "literal send failure was rescued by a receipt"
  assert_injection_counts 1 0 "literal failure"
  assert_contains "$(cat "$CASE/send.err")" "text not sent" "literal failure did not retain the hard transport diagnostic"
  pass "fm-send Pi admission: literal-send failure remains failure even if an exact receipt appears"
}

test_enter_retry_and_existing_proofs_unchanged() {
  local rc
  reset_case
  run_send swallowed-enter; rc=$?
  expect_code 0 "$rc" "a swallowed first Enter should recover on Enter-only retry"
  assert_injection_counts 1 2 "swallowed Enter"

  reset_case
  run_send idle-native; rc=$?
  expect_code 0 "$rc" "idle-to-working native proof should remain success"
  assert_injection_counts 1 1 "idle-to-working proof"
  assert_absent "$RECEIPT_PATH" "idle-to-working proof unexpectedly required a receipt"

  reset_case
  run_send empty-composer; rc=$?
  expect_code 0 "$rc" "provably empty composer should remain success"
  assert_injection_counts 1 1 "empty-composer proof"
  assert_absent "$RECEIPT_PATH" "empty-composer proof unexpectedly required a receipt"
  pass "fm-send Pi admission: swallowed Enter retries only Enter, while native and provably empty-composer proofs remain unchanged"
}

test_quick_identical_sends_have_distinct_boundaries() {
  local rc1 rc2
  reset_case
  PATH="$FAKEBIN:$PATH" FM_HOME="$HOME_DIR" FM_SEND_SETTLE=0 FM_SEND_SLEEP=0 \
    FM_PI_ADMISSION_SLEEP=0 FM_PI_ADMISSION_POLLS=2 FM_ADMISSION_ACTION=concurrent-exact \
    FM_ADMISSION_LOG="$LOG" FM_ADMISSION_STATE="$(cd "$HOME_DIR/state" && pwd -P)" \
    FM_ADMISSION_ID="$ID" FM_ADMISSION_GEN="$GEN" FM_ADMISSION_EXT="$EXT" \
    FM_ADMISSION_BODY="$BODY" FM_ADMISSION_HELPER="$RECEIPT" FM_ADMISSION_DRIVER="$DRIVER" \
    FM_ADMISSION_GUARD="$GUARD" FM_ADMISSION_CONCURRENCY_GUARD=1 \
    "$SEND" "$ID" "$MESSAGE" >/dev/null 2>"$CASE/send-1.err" &
  p1=$!
  /bin/sleep 0.03
  PATH="$FAKEBIN:$PATH" FM_HOME="$HOME_DIR" FM_SEND_SETTLE=0 FM_SEND_SLEEP=0 \
    FM_PI_ADMISSION_SLEEP=0 FM_PI_ADMISSION_POLLS=2 FM_ADMISSION_ACTION=concurrent-exact \
    FM_ADMISSION_LOG="$LOG" FM_ADMISSION_STATE="$(cd "$HOME_DIR/state" && pwd -P)" \
    FM_ADMISSION_ID="$ID" FM_ADMISSION_GEN="$GEN" FM_ADMISSION_EXT="$EXT" \
    FM_ADMISSION_BODY="$BODY" FM_ADMISSION_HELPER="$RECEIPT" FM_ADMISSION_DRIVER="$DRIVER" \
    FM_ADMISSION_GUARD="$GUARD" FM_ADMISSION_CONCURRENCY_GUARD=1 \
    "$SEND" "$ID" "$MESSAGE" >/dev/null 2>"$CASE/send-2.err" &
  p2=$!
  wait "$p1"; rc1=$?
  wait "$p2"; rc2=$?
  expect_code 0 "$rc1" "first concurrent exact send failed: $(cat "$CASE/send-1.err")"
  expect_code 0 "$rc2" "second concurrent exact send failed: $(cat "$CASE/send-2.err")"
  assert_injection_counts 2 2 "two serialized exact sends"
  [ "$(wc -l < "$RECEIPT_PATH" | tr -d ' ')" -eq 2 ] \
    || fail "two serialized sends did not receive two monotonic receipt records"
  pass "fm-send Pi admission: concurrent identical task sends serialize across distinct monotonic receipt boundaries"
}

test_held_send_lock_refuses_before_injection() {
  local lock ready holder rc i=0
  reset_case
  lock="$HOME_DIR/state/.$ID.pi-admission-send.lock"
  ready="$CASE/lock-ready"
  rm -f "$ready"
  (
    FM_STATE_OVERRIDE="$HOME_DIR/state"
    . "$ROOT/bin/fm-wake-lib.sh"
    fm_lock_try_acquire "$lock" || exit 1
    touch "$ready"
    sleep 2
  ) &
  holder=$!
  while [ ! -e "$ready" ] && [ "$i" -lt 100 ]; do
    sleep 0.01
    i=$((i + 1))
  done
  [ -e "$ready" ] || { kill "$holder" 2>/dev/null || true; fail "could not stage the held admission send lock"; }
  FM_PI_ADMISSION_LOCK_ATTEMPTS=2 FM_PI_ADMISSION_LOCK_SLEEP=0.01 run_send exact; rc=$?
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  [ "$rc" -ne 0 ] || fail "a held admission send lock did not refuse the send"
  assert_injection_counts 0 0 "held admission send lock"
  pass "fm-send Pi admission: a live-held serialization lock refuses promptly before injection"
}

test_busy_exact_receipt_confirms_once
test_no_or_unusable_receipt_never_confirms
test_old_boundary_never_confirms
test_literal_failure_cannot_be_rescued
test_enter_retry_and_existing_proofs_unchanged
test_quick_identical_sends_have_distinct_boundaries
test_held_send_lock_refuses_before_injection

echo "all fm-send Pi admission tests passed"
