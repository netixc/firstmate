#!/usr/bin/env bash
# Regression tests for the pinned shared no-mistakes gate action.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ACTION_REF=76fa0921a9797b09e120c8b5979c4d0e65f88922
TMP_ROOT=$(fm_test_tmproot fm-no-mistakes-required)
VERIFY="$TMP_ROOT/verify.py"
EVENT="$TMP_ROOT/event.json"
API_RESPONSE="$TMP_ROOT/api-response.json"
API_PORT="$TMP_ROOT/api-port"
OLD_SHA=1111111111111111111111111111111111111111
NEW_SHA=2222222222222222222222222222222222222222
SIGNATURE='Updates from [git push no-mistakes](https://github.com/kunchenguid/no-mistakes)'
COMPLETED_STEPS='[{"step":"review","status":"completed"},{"step":"test","status":"completed"},{"step":"document","status":"completed"}]'

fetch_shared_verifier() {
  command -v curl >/dev/null 2>&1 || fail "curl is required to exercise the pinned shared action"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to exercise the pinned shared action"
  curl --fail --silent --show-error --location \
    "https://raw.githubusercontent.com/kunchenguid/no-mistakes/${ACTION_REF}/.github/actions/require-no-mistakes/verify.py" \
    > "$VERIFY" || fail "could not fetch the pinned shared action verifier"
  [ -s "$VERIFY" ] || fail "the pinned shared action verifier was empty"
}

run_verifier() {
  local body=$1 head=$2
  PR_BODY="$body" PR_HEAD_SHA="$head" PR_AUTHOR=regression PR_NUMBER=3006 \
    python3 "$VERIFY" 2>&1
}

run_live_verifier() {
  local output rc api_pid attempts=0
  rm -f "$API_PORT"
  python3 - "$API_RESPONSE" "$API_PORT" <<'PY' &
import http.server
import pathlib
import sys

response_path = pathlib.Path(sys.argv[1])
port_path = pathlib.Path(sys.argv[2])

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = response_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
port_path.write_text(str(server.server_port), encoding="utf-8")
server.handle_request()
PY
  api_pid=$!
  trap 'kill "$api_pid" 2>/dev/null || true; wait "$api_pid" 2>/dev/null || true' EXIT
  while [ ! -s "$API_PORT" ] && kill -0 "$api_pid" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || break
    sleep 0.05
  done
  [ -s "$API_PORT" ] || fail "fake GitHub API did not start"
  rc=0
  output=$(env -u PR_BODY -u PR_HEAD_SHA \
    GITHUB_EVENT_PATH="$EVENT" GITHUB_TOKEN=test-token \
    GITHUB_REPOSITORY=example/project \
    GITHUB_API_URL="http://127.0.0.1:$(cat "$API_PORT")" \
    python3 "$VERIFY" 2>&1) || rc=$?
  kill "$api_pid" 2>/dev/null || true
  wait "$api_pid" 2>/dev/null || true
  trap - EXIT
  printf '%s\n%s' "$rc" "$output"
}

test_matching_head_and_completed_steps_pass() {
  local body output rc
  body="$SIGNATURE
<!-- no-mistakes-pipeline-attestation:v1 {\"head_sha\":\"$NEW_SHA\",\"steps\":$COMPLETED_STEPS} -->"
  rc=0
  output=$(run_verifier "$body" "$NEW_SHA") || rc=$?
  expect_code 0 "$rc" "shared action rejected an attestation bound to the current PR head"
  assert_contains "$output" "Found structurally compliant pipeline step attestation." \
    "shared action did not report the matching attestation as compliant"
  pass "shared action accepts a matching head_sha with completed required steps"
}

test_mismatched_head_fails_with_both_shas() {
  local body output rc
  body="$SIGNATURE
<!-- no-mistakes-pipeline-attestation:v1 {\"head_sha\":\"$OLD_SHA\",\"steps\":$COMPLETED_STEPS} -->"
  rc=0
  output=$(run_verifier "$body" "$NEW_SHA") || rc=$?
  [ "$rc" -ne 0 ] || fail "shared action accepted an attestation from a different PR head"
  assert_contains "$output" "$OLD_SHA" \
    "mismatched-head failure did not name the attestation head SHA"
  assert_contains "$output" "$NEW_SHA" \
    "mismatched-head failure did not name the actual PR head SHA"
  pass "shared action rejects a mismatched head_sha and names both SHAs"
}

test_missing_head_fails() {
  local body output rc
  body="$SIGNATURE
<!-- no-mistakes-pipeline-attestation:v1 {\"steps\":$COMPLETED_STEPS} -->"
  rc=0
  output=$(run_verifier "$body" "$NEW_SHA") || rc=$?
  [ "$rc" -ne 0 ] || fail "shared action accepted an attestation without head_sha"
  assert_contains "$output" "structured pipeline step attestation" \
    "missing-head failure did not explain that the attestation is invalid"
  pass "shared action rejects an attestation with no head_sha"
}

test_zero_input_path_uses_live_pr_facts() {
  local live_body result rc output
  live_body="$SIGNATURE
<!-- no-mistakes-pipeline-attestation:v1 {\"head_sha\":\"$NEW_SHA\",\"steps\":$COMPLETED_STEPS} -->"
  python3 - "$EVENT" "$API_RESPONSE" "$OLD_SHA" "$NEW_SHA" "$live_body" <<'PY'
import json
import pathlib
import sys

event_path, response_path, old_sha, new_sha, live_body = sys.argv[1:]
event = {
    "pull_request": {
        "number": 3006,
        "body": "stale archived body without a compliant attestation",
        "head": {"sha": old_sha, "ref": "regression"},
        "user": {"login": "regression"},
    }
}
response = {"body": live_body, "head": {"sha": new_sha}}
pathlib.Path(event_path).write_text(json.dumps(event), encoding="utf-8")
pathlib.Path(response_path).write_text(json.dumps(response), encoding="utf-8")
PY
  result=$(run_live_verifier)
  rc=${result%%$'\n'*}
  output=${result#*$'\n'}
  expect_code 0 "$rc" "zero-input gate judged the stale event payload instead of live PR facts"
  assert_contains "$output" "Found structurally compliant pipeline step attestation." \
    "zero-input gate did not accept the current-head live attestation"
  pass "shared action ignores stale event facts and validates live PR state"
}

fetch_shared_verifier
test_matching_head_and_completed_steps_pass
test_mismatched_head_fails_with_both_shas
test_missing_head_fails
test_zero_input_path_uses_live_pr_facts
