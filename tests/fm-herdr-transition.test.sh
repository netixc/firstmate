#!/usr/bin/env bash
# Herdr native-transition executable transport tests.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v python3 >/dev/null 2>&1 || { echo "skip: python3 not found"; exit 0; }

TMP=$(fm_test_tmproot fm-herdr-transition)
SOCK="$TMP/herdr.sock"
REQUEST="$TMP/request.json"
SERVER="$TMP/server.py"

cat > "$SERVER" <<'PY'
import json
import socket
import sys
import time

sock_path, request_path = sys.argv[1:]
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(1)
connection, _ = server.accept()
request = b""
while b"\n" not in request:
    request += connection.recv(65536)
with open(request_path, "wb") as output:
    output.write(request.split(b"\n", 1)[0])
messages = [
    {"result": {"type": "subscription_started"}},
    {"event": "unrelated", "data": {"pane_id": "ignored"}},
    {"event": "pane.agent_status_changed", "data": {"pane_id": "wG:pQ", "workspace_id": "wG", "agent_status": "blocked", "agent": "pi"}},
    {"event": "pane.agent_status_changed", "data": {"pane_id": "wG:pQ", "workspace_id": "", "agent_status": "working", "agent": "multi\tline\nagent"}},
]
for message in messages:
    connection.sendall((json.dumps(message) + "\n").encode())
time.sleep(1)
PY

python3 "$SERVER" "$SOCK" "$REQUEST" &
SERVER_PID=$!
i=0
while [ ! -S "$SOCK" ] && [ "$i" -lt 100 ]; do
  sleep 0.01
  i=$((i + 1))
done
[ -S "$SOCK" ] || fail "event fixture did not create its Herdr socket"

OUT=$(python3 "$ROOT/bin/fm-herdr-eventwait.py" "$SOCK" 0.4 wG:pQ)
RC=$?
wait "$SERVER_PID" 2>/dev/null || true
[ "$RC" -eq 0 ] || fail "event reader returned $RC instead of a clean bounded wait"

python3 - "$REQUEST" <<'PY' || fail "event reader sent the wrong Herdr subscription"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    request = json.load(source)
expected = {
    "id": "fm-eventwait",
    "method": "events.subscribe",
    "params": {"subscriptions": [{"type": "pane.agent_status_changed", "pane_id": "wG:pQ"}]},
}
raise SystemExit(0 if request == expected else 1)
PY
pass "event reader subscribes to the requested pane through Herdr's executable wire interface"

EXPECTED=$(printf '@subscribed\nwG:pQ\twG\tblocked\tpi\nwG:pQ\t\tworking\tmulti line agent')
[ "$OUT" = "$EXPECTED" ] || fail "event reader projected the transition stream incorrectly: $OUT"
pass "event reader emits only normalized four-field Herdr transition records"

echo "# fm-herdr-transition.test.sh: all assertions passed"
