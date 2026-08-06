#!/usr/bin/env bash
# Focused recovery-grade liveness tests for Herdr second-mate endpoints.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }
TMP_ROOT=$(fm_test_tmproot fm-secondmate-liveness)

make_fake() {  # <name> <present|missing|unreadable> <agent-status|none|unreadable>
  local presence=$2 agent=$3 dir="$TMP_ROOT/$1" fb
  mkdir -p "$dir"
  fb=$(fm_fakebin "$dir")
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  'pane get')
    case "${FM_FAKE_PRESENCE:-present}" in
      present) printf '{"result":{"pane":{"pane_id":"w1:p1"}}}\n' ;;
      missing) printf '{"error":{"code":"pane_not_found"}}\n' ;;
      *) printf 'not-json\n' ;;
    esac
    ;;
  'agent get')
    case "${FM_FAKE_AGENT:-working}" in
      none) printf '{"error":{"code":"agent_not_found"}}\n' ;;
      unreadable) printf 'not-json\n' ;;
      *) printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$FM_FAKE_AGENT" ;;
    esac
    ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$fb/herdr"
  printf '%s\n%s\n%s\n' "$fb" "$presence" "$agent"
}

classify() {  # <presence> <agent>
  local values fb presence agent
  values=$(make_fake "$1-$2" "$1" "$2")
  fb=$(printf '%s\n' "$values" | sed -n '1p')
  presence=$(printf '%s\n' "$values" | sed -n '2p')
  agent=$(printf '%s\n' "$values" | sed -n '3p')
  PATH="$fb:$PATH" FM_FAKE_PRESENCE="$presence" FM_FAKE_AGENT="$agent" \
    bash -c '. "$0/bin/fm-backend.sh"; fm_backend_agent_state herdr default:w1:p1' "$ROOT"
}

test_registered_agent_is_alive() {
  local out
  for status in working idle blocked "done"; do
    out=$(classify present "$status")
    [ "$out" = alive ] || fail "registered agent status $status should classify alive, got '$out'"
  done
  pass "Herdr liveness: every registered agent status remains alive"
}

test_missing_pane_authorizes_recovery() {
  local out
  out=$(classify missing none)
  [ "$out" = missing ] || fail "a structurally absent pane should classify missing, got '$out'"
  pass "Herdr liveness: a structurally absent pane classifies missing"
}

test_agentless_pane_authorizes_recovery() {
  local out
  out=$(classify present none)
  [ "$out" = dead ] || fail "an agentless restored pane should classify dead, got '$out'"
  pass "Herdr liveness: an agentless restored pane classifies dead"
}

test_unreadable_evidence_is_preserved() {
  local out
  out=$(classify unreadable working)
  [ "$out" = unreadable ] || fail "unreadable pane evidence should remain unreadable, got '$out'"
  out=$(classify present unreadable)
  [ "$out" = unreadable ] || fail "unreadable agent evidence should remain unreadable, got '$out'"
  pass "Herdr liveness: ambiguous reads never authorize recovery"
}

test_registered_agent_is_alive
test_missing_pane_authorizes_recovery
test_agentless_pane_authorizes_recovery
test_unreadable_evidence_is_preserved
