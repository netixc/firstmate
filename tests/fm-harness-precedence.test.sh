#!/usr/bin/env bash
# Behavior tests for bin/fm-harness.sh's marker-vs-ancestry precedence boundary,
# and for the supervision protocol session start selects from it.
#
# Structural ancestry must outrank unrelated inherited markers, while a marker
# still decides when ancestry is genuinely silent.
#
# Every case drives the two evidence layers APART deliberately and asserts each
# one alone as well as the combination, so no case can pass vacuously if a layer
# silently stops working:
#   marker alone   - ancestry blinded by a fake ps, proving the marker is live
#                    and is what the old precedence would have returned.
#   ancestry alone - marker cleared, proving the ancestry signal is live.
#   both together  - the precedence verdict this file exists to pin.
# The fake ps blinds only the ancestry walk, and the suite proves that rather
# than assuming it. The no-marker cases assert `unknown` under the fake ps, and
# fail if the blinding ever leaks a real ancestor through.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# This suite states the markers it means to test in every case. Drop the ambient
# ones so a verdict never depends on which harness launched the suite.
unset PI_CODING_AGENT FM_PI_HARNESS

HARNESS="$ROOT/bin/fm-harness.sh"
TMP_ROOT=$(fm_test_tmproot fm-harness-precedence)
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}

# A real process named after a harness, asked for its verdict from a child.
# The command substitution around the probe is load-bearing: a bare `-c <cmd>`
# lets the shell exec the probe in place, which REPLACES the harness-named
# process the walk is supposed to find.
under_process() {  # <named-executable> [VAR=VAL ...]
  local bin=$1
  shift
  env -u PI_CODING_AGENT -u FM_PI_HARNESS \
    "$@" \
    "$bin" -c "r=\$(\"$HARNESS\"); printf '%s' \"\$r\""
}

# A fake ps that reports a bash ancestor terminating at pid 1, so the ancestry
# layer proves nothing and only the marker layer can answer.
blind_ancestry_bin() {  # <dir>
  local fakebin
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *'ppid='*) printf '%s\n' 1 ;;
  *) printf '%s\n' bash ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '%s\n' "$fakebin"
}

# A fake ps that models a PID NAMESPACE: every process reports bash with ppid 1,
# and pid 1 reports whatever FM_TEST_PID1_COMM names. This is what a harness
# looks like from inside a container, where the harness is pid 1 of its own
# namespace rather than a child of a shell.
namespace_ancestry_bin() {  # <dir>
  local fakebin
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/ps" <<'SH'
#!/usr/bin/env bash
pid=
prev=
for a in "$@"; do
  [ "$prev" = -p ] && pid=$a
  prev=$a
done
if [ "$pid" = 1 ]; then
  comm=${FM_TEST_PID1_COMM:-init}
  ppid=0
else
  comm=bash
  ppid=1
fi
case "$*" in
  *'ppid='*) printf '%s\n' "$ppid" ;;
  *) printf '%s\n' "$comm" ;;
esac
SH
  chmod +x "$fakebin/ps"
  printf '%s\n' "$fakebin"
}

# Run the harness script under a fake ps, with the ambient markers dropped so
# each case states its own.
under_fake_ps() {  # <fakebin> <VAR=VAL ...> -- [harness args]
  local fakebin=$1
  shift
  local -a assignments=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    assignments+=("$1")
    shift
  done
  [ "${1:-}" = -- ] && shift
  env -u PI_CODING_AGENT -u FM_PI_HARNESS \
    "${assignments[@]}" \
    PATH="$fakebin:$BASE_PATH" "$HARNESS" "$@"
}

with_blind_ancestry() {  # <fakebin> [VAR=VAL ...]
  local fakebin=$1
  shift
  env -u PI_CODING_AGENT -u FM_PI_HARNESS \
    "$@" \
    PATH="$fakebin:$BASE_PATH" "$HARNESS"
}

named_bin() {  # <dir> <name>
  mkdir -p "$1"
  cp "$(command -v bash)" "$1/$2"
  printf '%s\n' "$1/$2"
}

# --- 1. A foreign marker never renames a markerless harness -----------------

# Retired harness names and markers must contribute no identity of their own.
test_retired_harness_identity_is_not_recognized() {
  local bin fakebin got name retired
  for retired in codex muse gemini rovo agy kimi; do
    for name in "$retired" "$retired-cli-0.58.0"; do
      bin=$(named_bin "$TMP_ROOT/retired-$name-tree" "$name")
      got=$(under_process "$bin")
      [ "$got" != "$retired" ] \
        || fail "retired $retired process '$name' still resolved as a supported harness"
    done
  done

  bin=$(named_bin "$TMP_ROOT/retired-rovo-native-tree" atlassian_cli_rovodev)
  got=$(under_process "$bin")
  [ "$got" != rovo ] \
    || fail "retired Atlassian Rovo executable still resolved as a supported harness"

  fakebin=$(blind_ancestry_bin "$TMP_ROOT/retired-gemini-marker")
  got=$(with_blind_ancestry "$fakebin" GEMINI_CLI=1)
  [ "$got" = unknown ] \
    || fail "retired GEMINI_CLI marker still selected a harness, got '$got'"
  got=$(with_blind_ancestry "$fakebin" GEMINI_CLI=1 PI_CODING_AGENT=true FM_PI_HARNESS=pi-signed)
  [ "$got" = pi-signed ] \
    || fail "retired GEMINI_CLI marker hid a retained Pi-signed marker, got '$got'"
  got=$(with_blind_ancestry "$fakebin" ATLASSIAN_AGENT_TYPE=rovo ROVODEV_CLI=1)
  [ "$got" = unknown ] \
    || fail "retired Rovo markers still selected a harness, got '$got'"
  got=$(with_blind_ancestry "$fakebin" ATLASSIAN_AGENT_TYPE=rovo ROVODEV_CLI=1 PI_CODING_AGENT=true FM_PI_HARNESS=pi-signed)
  [ "$got" = pi-signed ] \
    || fail "retired Rovo markers hid a retained Pi-signed marker, got '$got'"
  pass "retired harness process names and markers no longer identify an adapter or hide retained Pi"
}

# --- 2. A genuine harness in its own process tree still wins ----------------

test_genuine_marker_and_ancestry_agree() {
  local dir bin got
  dir="$TMP_ROOT/genuine"

  bin=$(named_bin "$dir/pi-tree" pi)
  got=$(under_process "$bin" PI_CODING_AGENT=true FM_PI_HARNESS=pi)
  [ "$got" = pi ] || fail "a genuine pi session resolved '$got', expected pi"
  # Hook subprocesses may omit Pi's launch marker, so ancestry alone must still
  # answer for them.
  got=$(under_process "$bin")
  [ "$got" = pi ] || fail "an unmarked pi hook process resolved '$got', expected pi"

  pass "a harness that publishes a marker inside its own process tree is unchanged"
}

# --- 3. Pi keeps the marker's more specific identity ------------------------

# Both Pi identities share the launcher name, so ancestry can only prove the
# family. A marker that agrees on the family must keep its finer verdict rather
# than being flattened to pi by the ancestry walk.
test_pi_signed_survives_agreeing_ancestry() {
  local bin got
  bin=$(named_bin "$TMP_ROOT/pi-tree" pi)
  got=$(under_process "$bin" PI_CODING_AGENT=true FM_PI_HARNESS=pi-signed)
  [ "$got" = pi-signed ] || fail "signed Pi over pi ancestry resolved '$got', expected pi-signed"
  got=$(under_process "$bin" PI_CODING_AGENT=true)
  [ "$got" = pi ] || fail "plain Pi over pi ancestry resolved '$got', expected pi"
  got=$(under_process "$bin")
  [ "$got" = pi ] || fail "unmarked pi ancestry resolved '$got', expected pi"

  bin=$(named_bin "$TMP_ROOT/pi-signed-tree" pi-signed)
  got=$(under_process "$bin" PI_CODING_AGENT=true FM_PI_HARNESS=pi-signed)
  [ "$got" = pi-signed ] \
    || fail "signed Pi over shared signed-wrapper ancestry resolved '$got', expected pi-signed"
  got=$(under_process "$bin")
  [ "$got" = pi ] \
    || fail "unmarked signed-wrapper ancestry resolved '$got', expected pi"
  pass "an agreeing marker keeps Pi's finer identity that ancestry cannot prove"
}

test_retired_harness_identity_is_not_recognized
test_genuine_marker_and_ancestry_agree
test_pi_signed_survives_agreeing_ancestry
