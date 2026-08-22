#!/usr/bin/env bash
# Structured-CLI unit coverage for Firstmate's sole Herdr session owner.
# Assertions use logged canned Herdr responses plus real jq.
# The real-binary smoke test lives in tests/fm-herdr-smoke.test.sh,
# gated on the herdr binary actually being installed.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tests/herdr-test-safety.sh
. "$(dirname "${BASH_SOURCE[0]}")/herdr-test-safety.sh"

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found (required by the herdr adapter)"; exit 0; }

# These cases script a canned fake CLI; a Herdr pane identity leaked in from the
# developer's own terminal would make the adapter resolve a launcher that this
# fake never models. The launcher cases below set HERDR_PANE_ID themselves.
herdr_forget_inherited_pane

TMP_ROOT=$(fm_test_tmproot fm-herdr-tests)
# The suite's default per-home label assertions model a primary home. Bind
# them to scratch state so a developer's ignored .fm-secondmate-home marker
# cannot silently change canned response labels and fail before the subject.
export FM_HOME="$TMP_ROOT/home"
mkdir -p "$FM_HOME"
export FM_HERDR_SUBMIT_MIN_SLEEP=0

# make_herdr_fakebin: a `herdr` stub that logs every invocation (one line,
# unit-separated args, to $FM_HERDR_LOG) and returns the canned response for
# that call read from $FM_HERDR_RESPONSES/<n>.out, consumed IN ORDER (call 1
# reads 1.out, call 2 reads 2.out, ...) so a test can script a short sequence
# of calls precisely. A missing response file means "succeed with empty
# stdout" (mirrors send-text/send-keys/pane close/tab close, which are silent
# on success in the real CLI - verified in herdr-verification-p2.md).
make_herdr_fakebin() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
LOG="${FM_HERDR_LOG:?}"
RESP="${FM_HERDR_RESPONSES:?}"
COUNT_FILE="$RESP/.count"
next=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
{
  printf 'HERDR_SESSION=%s' "${HERDR_SESSION:-}"
  for a in "$@"; do printf '\x1f%s' "$a"; done
  printf '\n'
} >> "$LOG"
if [ "${1:-}" = status ] && [ "${2:-}" = --json ] && [ "${FM_HERDR_SCRIPT_STATUS:-0}" != 1 ]; then
  printf '{"client":{"version":"0.7.1","protocol":14},"server":{"running":true}}\n'
  exit 0
fi
n=$next
echo "$n" > "$COUNT_FILE"
if [ -f "$RESP/$n.exit" ]; then
  exit "$(cat "$RESP/$n.exit")"
fi
[ -f "$RESP/$n.out" ] && cat "$RESP/$n.out"
exit 0
SH
  chmod +x "$fb/herdr"
  printf '%s\n' "$fb"
}

# make_herdr_statefake: a STATEFUL `herdr` stub that models the parts of herdr's
# real container behavior the workspace-leak fix (and the default-tab-prune
# safety fix) depend on, so a full spawn->teardown cycle can be replayed
# repeatedly and the "one persistent firstmate workspace, no orphans"
# invariant asserted end to end (the canned, call-numbered make_herdr_fakebin
# above cannot model state carried ACROSS calls). Backed by a JSON state file
# ($FM_FAKE_HERDR_STATE) mutated with real jq. Modeled behaviors, all
# verified real-herdr facts recorded in docs/herdr-backend.md: `workspace
# create` seeds the new workspace with one auto-created default tab (label
# "1") and returns that tab's tab_id/pane_id in the SAME response
# (`.result.tab.tab_id` / `.result.root_pane.pane_id`, verified empirically
# against the real binary); `pane close` removes the pane's single-pane tab
# (closing a tab's only pane closes the tab); `workspace list` / `tab list` /
# `pane list` reflect live state; `agent get <pane>` reports the pane's preset
# agent_status (set via fake_herdr_set_agent_status, never through a CLI
# call - mirrors an out-of-band agent registering itself) or an
# agent_not_found error when none was preset (verified real-herdr behavior for
# a pane with no registered agent). Every call is logged to $FM_HERDR_LOG in
# the same unit-separated form as make_herdr_fakebin.
make_herdr_statefake() {  # <dir> -> echoes fakebin dir; seeds an empty state file
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  printf '{"next":1,"workspaces":[],"tabs":[],"agent_status":{}}\n' > "$dir/state.json"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
LOG="${FM_HERDR_LOG:?}"
STATE="${FM_FAKE_HERDR_STATE:?}"
{
  printf 'HERDR_SESSION=%s' "${HERDR_SESSION:-}"
  for a in "$@"; do printf '\x1f%s' "$a"; done
  printf '\n'
} >> "$LOG"

jq_state() { jq "$@" "$STATE"; }
save() { local tmp="$STATE.tmp.$$"; cat > "$tmp" && mv "$tmp" "$STATE"; }

cmd=${1:-}; sub=${2:-}
ws=""; label=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --workspace) ws=${args[$((i+1))]:-} ;;
    --label) label=${args[$((i+1))]:-} ;;
  esac
done

case "$cmd $sub" in
  "status --json")
    printf '{"client":{"version":"0.7.1","protocol":14},"server":{"running":true}}\n'
    ;;
  "workspace list")
    jq_state '{result:{workspaces:.workspaces}}'
    ;;
  "workspace create")
    n=$(jq_state -r '.next'); wsid="w$n"; dn=$((n + 1))
    jq_state --arg wsid "$wsid" --arg wlabel "$label" \
      --arg tabid "$wsid:t$dn" --arg paneid "$wsid:p$dn" \
      '.workspaces += [{workspace_id:$wsid, label:$wlabel}]
       | .tabs += [{tab_id:$tabid, label:"1", workspace_id:$wsid, pane_id:$paneid}]
       | .next = (.next + 2)' | save
    printf '{"result":{"workspace":{"workspace_id":"%s","label":"%s"},"tab":{"tab_id":"%s"},"root_pane":{"pane_id":"%s"}}}\n' \
      "$wsid" "$label" "$wsid:t$dn" "$wsid:p$dn"
    ;;
  "tab list")
    jq_state --arg w "$ws" '{result:{tabs:[.tabs[]|select(.workspace_id==$w)]}}'
    ;;
  "tab create")
    n=$(jq_state -r '.next'); tabid="$ws:t$n"; paneid="$ws:p$n"
    jq_state --arg w "$ws" --arg wlabel "$label" --arg tabid "$tabid" --arg paneid "$paneid" \
      '.tabs += [{tab_id:$tabid, label:$wlabel, workspace_id:$w, pane_id:$paneid}]
       | .next = (.next + 1)' | save
    printf '{"result":{"tab":{"tab_id":"%s"},"root_pane":{"pane_id":"%s"}}}\n' "$tabid" "$paneid"
    ;;
  "pane list")
    jq_state --arg w "$ws" '{result:{panes:[.tabs[]|select(.workspace_id==$w)|{pane_id:.pane_id, tab_id:.tab_id}]}}'
    ;;
  "pane close")
    pane=${3:-}
    jq_state --arg p "$pane" '.tabs |= [.[]|select(.pane_id != $p)]' | save
    ;;
  "tab close")
    tab=${3:-}
    jq_state --arg t "$tab" '.tabs |= [.[]|select(.tab_id != $t)]' | save
    ;;
  "agent get")
    pane=${3:-}
    status=$(jq_state -r --arg p "$pane" '.agent_status[$p] // empty')
    if [ -n "$status" ]; then
      printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$status"
    else
      printf '{"error":{"code":"agent_not_found","message":"agent target %s not found"}}\n' "$pane"
    fi
    ;;
  *) : ;;
esac
exit 0
SH
  chmod +x "$fb/herdr"
  printf '%s\n' "$fb"
}

# fake_herdr_set_agent_status: preset <pane_id>'s agent_status in the
# stateful fake's state file, mirroring an agent registering itself
# out-of-band (never through a CLI call the adapter itself would make).
# Used to exercise fm_herdr_workspace_prune_seeded_default_tab's
# defense-in-depth refuse-if-busy check.
fake_herdr_set_agent_status() {  # <state-file> <pane_id> <status>
  local state=$1 pane=$2 status=$3 tmp="$1.tmp.$$"
  jq --arg p "$pane" --arg s "$status" '.agent_status[$p] = $s' "$state" > "$tmp" && mv "$tmp" "$state"
}

# herdr_case <name> -> sets up FM_HERDR_LOG/FM_HERDR_RESPONSES/fb for one test,
# registers cleanup-free tmp dirs under TMP_ROOT.
herdr_env() {  # <name>
  local name=$1 dir
  dir="$TMP_ROOT/$name"
  mkdir -p "$dir/responses"
  : > "$dir/log"
  printf '%s\n%s\n' "$dir/log" "$dir/responses"
}

# --- version_check / tool_check ----------------------------------------------

test_version_check_accepts_current_protocol() {
  local dir log resp fb status
  dir="$TMP_ROOT/version-ok"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"client":{"version":"0.7.1","channel":"stable","protocol":14}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_version_check' "$ROOT"
  status=$?
  expect_code 0 "$status" "version_check should accept protocol 14 (>= the verified minimum)"
  assert_contains "$(cat "$log")" $'\x1f''status'$'\x1f''--json' "version_check did not call herdr status --json"
  pass "fm_herdr_version_check: accepts the current protocol (14)"
}

test_version_check_refuses_old_protocol() {
  local dir log resp fb out status
  dir="$TMP_ROOT/version-old"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"client":{"version":"0.3.0","channel":"stable","protocol":5}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_version_check' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "version_check should refuse protocol 5 (below min)"
  assert_contains "$out" "protocol 5" "version_check error did not name the rejected protocol"
  pass "fm_herdr_version_check: refuses an old protocol loudly"
}

test_version_check_refuses_missing_herdr() {
  local dir out status
  dir="$TMP_ROOT/version-missing"; mkdir -p "$dir/empty-fakebin"
  out=$( PATH="$dir/empty-fakebin:/usr/bin:/bin" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_version_check' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "version_check should refuse when herdr is not installed"
  assert_contains "$out" "not installed" "version_check did not report herdr as missing"
  pass "fm_herdr_version_check: refuses loudly when herdr is not installed"
}

# --- workspace_label: per-firstmate-HOME resolution (P3, herdr-sm-spaces-k4) -

test_workspace_label_primary_home_no_marker() {
  local home
  home="$TMP_ROOT/primary-home-no-marker"; mkdir -p "$home"
  out=$( FM_HOME="$home" bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_label' "$ROOT" )
  [ "$out" = "firstmate" ] || fail "a primary home (no .fm-secondmate-home marker) should resolve to label 'firstmate', got '$out'"
  pass "fm_herdr_workspace_label: a primary home (no marker) resolves to 'firstmate'"
}

test_workspace_label_secondmate_home_uses_marker_id() {
  local home
  home="$TMP_ROOT/secondmate-home"; mkdir -p "$home"
  printf 'sshhip-h7\n' > "$home/.fm-secondmate-home"
  out=$( FM_HOME="$home" bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_label' "$ROOT" )
  [ "$out" = "2ndmate-sshhip-h7" ] || fail "a secondmate home should resolve to '2ndmate-<id>', got '$out'"
  pass "fm_herdr_workspace_label: a secondmate home (.fm-secondmate-home) resolves to '2ndmate-<id>'"
}

test_workspace_label_secondmate_marker_trims_whitespace() {
  local home
  home="$TMP_ROOT/secondmate-home-ws"; mkdir -p "$home"
  printf '  sshhip-h7  \n\n' > "$home/.fm-secondmate-home"
  out=$( FM_HOME="$home" bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_label' "$ROOT" )
  [ "$out" = "2ndmate-sshhip-h7" ] || fail "the marker id should be trimmed of surrounding whitespace, got '$out'"
  pass "fm_herdr_workspace_label: trims whitespace around the marker's secondmate id"
}

test_workspace_label_empty_marker_falls_back_to_primary() {
  local home
  home="$TMP_ROOT/secondmate-home-empty"; mkdir -p "$home"
  : > "$home/.fm-secondmate-home"
  out=$( FM_HOME="$home" bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_label' "$ROOT" )
  [ "$out" = "firstmate" ] || fail "an empty/unreadable marker should fall back to 'firstmate', got '$out'"
  pass "fm_herdr_workspace_label: an empty marker file falls back to the primary label 'firstmate'"
}

test_workspace_label_different_secondmates_get_different_labels() {
  local home1 home2 out1 out2
  home1="$TMP_ROOT/secondmate-a"; mkdir -p "$home1"; printf 'alpha-a1\n' > "$home1/.fm-secondmate-home"
  home2="$TMP_ROOT/secondmate-b"; mkdir -p "$home2"; printf 'bravo-b2\n' > "$home2/.fm-secondmate-home"
  out1=$( FM_HOME="$home1" bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_label' "$ROOT" )
  out2=$( FM_HOME="$home2" bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_label' "$ROOT" )
  [ "$out1" = "2ndmate-alpha-a1" ] || fail "secondmate home1 label mismatch: $out1"
  [ "$out2" = "2ndmate-bravo-b2" ] || fail "secondmate home2 label mismatch: $out2"
  [ "$out1" != "$out2" ] || fail "two different secondmate homes must not collide on the same label"
  pass "fm_herdr_workspace_label: two different secondmate homes get two different, non-colliding labels"
}

# --- fm_herdr_cli: session targeting (2026-07-02 incident fix) -------

test_cli_helper_sets_env_and_appends_trailing_session_flag() {
  local dir log resp fb
  dir="$TMP_ROOT/cli-helper"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  fb=$(make_herdr_fakebin "$dir")
  PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_cli fmtest workspace list' "$ROOT"
  expect_code 0 $? "fm_herdr_cli should succeed"
  assert_contains "$(cat "$log")" "HERDR_SESSION=fmtest"$'\x1f''workspace'$'\x1f''list' \
    "fm_herdr_cli did not set the HERDR_SESSION env var"
  assert_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''list'$'\x1f''--session'$'\x1f''fmtest' \
    "fm_herdr_cli did not append a trailing --session <name> flag (the fix for the env-var-alone routing bug)"
  pass "fm_herdr_cli: sets HERDR_SESSION AND appends a trailing --session flag on every call"
}

# --- launcher_identity: the exact workspace a worker must be placed in -------
#
# Herdr injects HERDR_ENV/HERDR_PANE_ID/HERDR_SESSION/HERDR_SOCKET_PATH into
# every process it manages a pane for, so a firstmate or secondmate agent's own
# tool calls carry the identity of the workspace the captain is watching it in.
# Placement resolves from that identity because workspace labels are mutable and
# non-unique, and the globally focused workspace is unrelated to the launcher.
# The refusal cases matter as much as the resolution: a broken binding must stop
# the spawn, never quietly degrade back to picking a workspace by label.

test_launcher_identity_absent_without_a_herdr_pane() {
  local dir log resp fb status
  dir="$TMP_ROOT/launcher-none"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  fb=$(make_herdr_fakebin "$dir")
  ( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" )
  status=$?
  expect_code 2 "$status" "a process with no herdr pane must report 'no launcher to inherit' (2), not a refusal"
  [ ! -s "$log" ] || fail "resolving an absent launcher identity must not call herdr at all"$'\n'"$(cat "$log")"
  pass "fm_herdr_launcher_identity: a firstmate not running inside herdr has no launcher workspace to inherit"
}

test_launcher_identity_absent_when_herdr_env_alone_is_set() {
  local dir log resp fb status
  dir="$TMP_ROOT/launcher-env-only"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  fb=$(make_herdr_fakebin "$dir")
  ( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" HERDR_ENV=1 \
    \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" )
  status=$?
  expect_code 2 "$status" "HERDR_ENV=1 alone is a backend-selection marker, not a parent binding"
  pass "fm_herdr_launcher_identity: HERDR_ENV=1 without a pane id selects the backend but binds no parent"
}

test_launcher_identity_resolves_the_exact_pane_tab_and_workspace() {
  local dir log resp fb out
  dir="$TMP_ROOT/launcher-ok"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fm-herdr-unit/fmtest.sock"}]}\n' > "$resp/1.out"
  printf '{"result":{"pane":{"pane_id":"w7:p3","tab_id":"w7:t3","workspace_id":"w7"}}}\n' > "$resp/2.out"
  printf '{"result":{"tab":{"tab_id":"w7:t3","workspace_id":"w7"}}}\n' > "$resp/3.out"
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w7","label":"firstmate"}]}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest HERDR_SOCKET_PATH=/tmp/fm-herdr-unit/fmtest.sock \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest || exit 1
      printf "%s|%s|%s" "$FM_HERDR_LAUNCHER_PANE_ID" "$FM_HERDR_LAUNCHER_TAB_ID" "$FM_HERDR_LAUNCHER_WORKSPACE_ID"' "$ROOT" )
  [ "$out" = 'w7:p3|w7:t3|w7' ] \
    || fail "launcher_identity should resolve the launcher's own pane, tab, and workspace, got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''get'$'\x1f''w7:p3' "launcher_identity did not read its own pane"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''get'$'\x1f''w7:t3' "launcher_identity did not cross-check the owning tab"
  pass "fm_herdr_launcher_identity: resolves the launcher's exact workspace even when a same-labeled workspace sorts first"
}

test_launcher_identity_refuses_a_pane_from_another_session_name() {
  local dir log resp fb out status
  dir="$TMP_ROOT/launcher-xsession"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=someother \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" 2>&1 )
  status=$?
  expect_code 1 "$status" "a launcher pane naming another herdr session must refuse"
  assert_contains "$out" "cross-session parent identity" "the cross-session refusal did not explain itself"
  [ ! -s "$log" ] || fail "a cross-session launcher identity must be refused before any herdr call"
  pass "fm_herdr_launcher_identity: refuses a launcher pane that names a different herdr session"
}

test_launcher_identity_refuses_a_missing_server_socket() {
  local dir log resp fb out status
  dir="$TMP_ROOT/launcher-no-socket"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" 2>&1 )
  status=$?
  expect_code 1 "$status" "a launcher pane without an injected server socket must refuse"
  assert_contains "$out" "no injected socket identity" "the missing-socket refusal did not explain itself"
  [ ! -s "$log" ] || fail "a missing-socket launcher identity must be refused before any herdr call"
  pass "fm_herdr_launcher_identity: refuses a claimed pane without exact server identity"
}

test_launcher_identity_refuses_a_pane_from_another_server_socket() {
  local dir log resp fb out status
  dir="$TMP_ROOT/launcher-xsocket"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # 1: session list --json, resolving THIS session's own socket.
  printf '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fm-herdr-unit/fmtest.sock"}]}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest HERDR_SOCKET_PATH=/tmp/fm-herdr-unit/other.sock \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" 2>&1 )
  status=$?
  expect_code 1 "$status" "a launcher pane on a different herdr server socket must refuse"
  assert_contains "$out" "cross-session parent identity" "the cross-socket refusal did not explain itself"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''get' "a cross-server launcher identity must be refused before its pane is trusted"
  pass "fm_herdr_launcher_identity: refuses a launcher pane whose injected socket belongs to another herdr server"
}

test_launcher_identity_refuses_an_unreadable_pane() {
  local dir log resp fb out status
  dir="$TMP_ROOT/launcher-stale"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fm-herdr-unit/fmtest.sock"}]}\n' > "$resp/1.out"
  printf '1\n' > "$resp/2.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest HERDR_SOCKET_PATH=/tmp/fm-herdr-unit/fmtest.sock \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" 2>&1 )
  status=$?
  expect_code 1 "$status" "a launcher pane that no longer reads must refuse, not fall back to a label search"
  assert_contains "$out" "w7:p3" "the stale-pane refusal did not name the pane it could not resolve"
  pass "fm_herdr_launcher_identity: refuses when the launcher's own pane no longer resolves"
}

test_launcher_identity_refuses_a_pane_and_tab_that_disagree() {
  local dir log resp fb out status
  dir="$TMP_ROOT/launcher-contradictory"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fm-herdr-unit/fmtest.sock"}]}\n' > "$resp/1.out"
  printf '{"result":{"pane":{"pane_id":"w7:p3","tab_id":"w7:t3","workspace_id":"w7"}}}\n' > "$resp/2.out"
  # The tab claims a DIFFERENT owning workspace than the pane just did.
  printf '{"result":{"tab":{"tab_id":"w7:t3","workspace_id":"w9"}}}\n' > "$resp/3.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest HERDR_SOCKET_PATH=/tmp/fm-herdr-unit/fmtest.sock \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" 2>&1 )
  status=$?
  expect_code 1 "$status" "a pane and tab that disagree about their workspace must refuse"
  assert_contains "$out" "contradictory parent identity" "the contradictory-identity refusal did not explain itself"
  pass "fm_herdr_launcher_identity: refuses when the launcher's pane and tab disagree about their workspace"
}

test_launcher_identity_refuses_a_workspace_missing_from_the_session() {
  local dir log resp fb out status
  dir="$TMP_ROOT/launcher-gone"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fm-herdr-unit/fmtest.sock"}]}\n' > "$resp/1.out"
  printf '{"result":{"pane":{"pane_id":"w7:p3","tab_id":"w7:t3","workspace_id":"w7"}}}\n' > "$resp/2.out"
  printf '{"result":{"tab":{"tab_id":"w7:t3","workspace_id":"w7"}}}\n' > "$resp/3.out"
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"}]}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest HERDR_SOCKET_PATH=/tmp/fm-herdr-unit/fmtest.sock \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_launcher_identity fmtest' "$ROOT" 2>&1 )
  status=$?
  expect_code 1 "$status" "a launcher workspace absent from the session listing must refuse"
  assert_contains "$out" "stale parent identity" "the stale-workspace refusal did not explain itself"
  pass "fm_herdr_launcher_identity: refuses when the launcher's workspace is gone from its own session"
}

# --- workspace_ensure placement ---------------------------------------------

test_workspace_ensure_prefers_the_launcher_over_the_first_label_match() {
  local dir log resp fb out
  dir="$TMP_ROOT/ensure-launcher"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fm-herdr-unit/fmtest.sock"}]}\n' > "$resp/1.out"
  printf '{"result":{"pane":{"pane_id":"w7:p3","tab_id":"w7:t3","workspace_id":"w7"}}}\n' > "$resp/2.out"
  printf '{"result":{"tab":{"tab_id":"w7:t3","workspace_id":"w7"}}}\n' > "$resp/3.out"
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w7","label":"firstmate"}]}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest HERDR_SOCKET_PATH=/tmp/fm-herdr-unit/fmtest.sock \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_ensure fmtest /tmp' "$ROOT" )
  [ "$out" = w7 ] || fail "workspace_ensure should place the worker in the launcher's own workspace w7, got '$out'"
  assert_not_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''create' "the launcher's existing workspace must be reused, not duplicated"
  pass "fm_herdr_workspace_ensure: places a worker in the launcher's exact workspace, not the first same-labeled one"
}

test_workspace_ensure_refuses_an_ambiguous_label_with_no_launcher() {
  local dir log resp fb out status
  dir="$TMP_ROOT/ensure-ambiguous"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w7","label":"firstmate"}]}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_ensure fmtest /tmp' "$ROOT" 2>&1 )
  status=$?
  expect_code 3 "$status" "two same-labeled home workspaces with no launcher identity must refuse"
  assert_contains "$out" "labeled 'firstmate'" "the ambiguity refusal did not name the duplicated label"
  assert_contains "$out" "w1 w7" "the ambiguity refusal did not name the candidate workspaces"
  assert_not_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''create' "an ambiguous placement must not mint a third same-labeled workspace"
  pass "fm_herdr_workspace_ensure: refuses to guess between two same-labeled home workspaces"
}

test_workspace_ensure_other_home_ignores_the_launcher_identity() {
  local dir log resp fb out
  dir="$TMP_ROOT/ensure-other-home"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Only a workspace list: the launcher's own pane is never consulted, because a
  # --secondmate launch stands up a different home's workspace by design.
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"}]}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    HERDR_ENV=1 HERDR_PANE_ID=w7:p3 HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_ensure fmtest /tmp other-home' "$ROOT" )
  [ "$out" = w1 ] || fail "an other-home container should resolve by this home's own label, got '$out'"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''get' "an other-home container must not inherit the launcher's workspace"
  pass "fm_herdr_workspace_ensure: a --secondmate container resolves that home's own workspace, not the launcher's"
}

test_container_ensure_refuses_an_ambiguous_home_label() {
  local dir log resp fb out status
  dir="$TMP_ROOT/container-ambiguous"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w7","label":"firstmate"}]}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /tmp' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "container_ensure must fail when the home workspace is ambiguous"
  assert_contains "$out" "labeled 'firstmate'" "container_ensure buried the specific ambiguity it refused"
  assert_not_contains "$out" "failed to ensure herdr workspace" "container_ensure added a generic message over the specific one"
  pass "fm_herdr_container_ensure: surfaces the exact ambiguous-placement refusal instead of a generic failure"
}

# --- container_ensure / create_task ------------------------------------------

test_container_ensure_starts_server_and_workspace() {
  local dir log resp fb out
  dir="$TMP_ROOT/container"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # 1: version_check status --json (server not running yet, irrelevant to client check)
  printf '{"client":{"version":"0.7.1","protocol":14}}\n' > "$resp/1.out"
  # 2: server_ensure's status --json check -> not running
  printf '{"server":{"running":false}}\n' > "$resp/2.out"
  # 3/4: backgrounded server launch and server_ensure poll
  printf '{"server":{"running":true}}\n' > "$resp/3.out"
  printf '{"server":{"running":true}}\n' > "$resp/4.out"
  # 5: workspace list -> empty (no "firstmate" workspace yet)
  printf '{"result":{"workspaces":[]}}\n' > "$resp/5.out"
  # 6: workspace create -> w1, seeding default tab w1:t9 (real herdr returns
  # the seeded tab/pane ids in the SAME response - verified empirically).
  printf '{"result":{"workspace":{"workspace_id":"w1","label":"firstmate"},"tab":{"tab_id":"w1:t9"},"root_pane":{"pane_id":"w1:p9"}}}\n' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /tmp' "$ROOT" )
  [ "$out" = $'fmtest:w1\tw1:t9' ] || fail "container_ensure should echo '<session>:<workspace_id>\\t<seeded_default_tab_id>', got '$out'"
  assert_contains "$(cat "$log")" "HERDR_SESSION=fmtest"$'\x1f''server' "container_ensure did not start the herdr server"
  assert_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''create'$'\x1f''--cwd'$'\x1f''/tmp'$'\x1f''--label'$'\x1f''firstmate' \
    "container_ensure did not create the firstmate workspace with the given cwd"
  pass "fm_herdr_container_ensure: version-gates, starts the server, ensures the firstmate workspace, echoes session:workspace_id + the seeded default tab id"
}

test_container_ensure_reuses_existing_workspace() {
  local dir log resp fb out
  dir="$TMP_ROOT/container-reuse"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"client":{"version":"0.7.1","protocol":14}}\n' > "$resp/1.out"
  printf '{"server":{"running":true}}\n' > "$resp/2.out"
  printf '{"result":{"workspaces":[{"workspace_id":"w9","label":"firstmate"}]}}\n' > "$resp/3.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /tmp' "$ROOT" )
  [ "$out" = $'fmtest:w9\t' ] || fail "container_ensure should reuse the existing firstmate workspace id with an EMPTY seeded-tab field (an ADOPTED workspace is never a prune candidate), got '$out'"
  assert_not_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''create' "container_ensure should not create a workspace that already exists"
  pass "fm_herdr_container_ensure: reuses an existing firstmate workspace without recreating it, and reports no seeded default tab (adopted, not created)"
}

test_create_task_refuses_duplicate_label() {
  local dir log resp fb out status
  dir="$TMP_ROOT/dup-task"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-dup1","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-dup1 /tmp/proj' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "create_task should refuse an existing tab label (herdr itself does not enforce uniqueness)"
  assert_contains "$out" "already exists" "create_task did not report the duplicate label"
  pass "fm_herdr_create_task: refuses a duplicate tab label (herdr's own tab create has no uniqueness check)"
}

# --- restored-layout husk close-and-replace (herdr session.json restore) -----
#
# herdr persists and restores its whole session layout (workspaces/tabs/
# panes) across a server restart, including a reboot. A restored fm-<id> task
# tab comes back a HUSK - a dead pane, or a plain agent-less shell sitting in
# the saved cwd - never the crewmate that used to be there. Before this fix,
# create_task refused ANY same-labeled tab unconditionally, so every fleet
# respawn after such a restart needed the operator to manually close each
# husk pane first. These tests cover the four cases the fix must get right:
# a genuinely LIVE duplicate still refuses (unchanged), a DEAD pane husk and a
# NO-AGENT (restored plain shell) husk both close-and-replace, and an
# AMBIGUOUS/unparseable read refuses (fail-safe, never guesses toward
# closing).

test_create_task_refuses_duplicate_label_when_agent_live() {
  local dir log resp fb out status
  dir="$TMP_ROOT/dup-live"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # 1: tab list -> an existing same-labeled tab
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-dup1","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  # 2: pane list (pane_for_tab) -> resolves the duplicate's pane id
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"}]}}\n' > "$resp/2.out"
  # 3: pane get -> the pane structurally exists
  printf '{"result":{"pane":{"pane_id":"w1:p2"}}}\n' > "$resp/3.out"
  # 4: agent get -> a genuinely registered, live agent (idle, not just working)
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-dup1 /tmp/proj' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "create_task should still refuse when the duplicate's pane hosts a live (even idle) registered agent"
  assert_contains "$out" "already exists" "create_task did not report the duplicate label for a live agent"
  assert_not_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''create' "create_task must not create a replacement tab when the duplicate is live"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close' "create_task must not close a live agent's pane"
  pass "fm_herdr_create_task: a same-labeled tab with a live (even idle) registered agent still refuses exactly as before"
}

test_create_task_refuses_when_any_duplicate_label_is_live() {
  local dir log resp fb out status
  dir="$TMP_ROOT/dup-mixed-live"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-mixed1","workspace_id":"w1"},{"tab_id":"w1:t3","label":"fm-mixed1","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"},{"pane_id":"w1:p3","tab_id":"w1:t3"}]}}\n' > "$resp/2.out"
  printf '{"result":{"pane":{"pane_id":"w1:p2"}}}\n' > "$resp/3.out"
  printf '{"error":{"code":"agent_not_found","message":"agent target w1:p2 not found"}}\n' > "$resp/4.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"},{"pane_id":"w1:p3","tab_id":"w1:t3"}]}}\n' > "$resp/5.out"
  printf '{"result":{"pane":{"pane_id":"w1:p3"}}}\n' > "$resp/6.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/7.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-mixed1 /tmp/proj' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "create_task must refuse when any same-labeled tab hosts a live registered agent"
  assert_contains "$out" "already exists" "create_task did not report the duplicate label when one duplicate was live"
  assert_not_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''create' "create_task must not create a replacement tab when any duplicate is live"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close' "create_task must not close any duplicate pane when one duplicate is live"
  pass "fm_herdr_create_task: scans every same-labeled tab and refuses if any duplicate is live"
}

test_create_task_closes_and_replaces_dead_pane_husk() {
  local dir log resp fb out status tab pane
  dir="$TMP_ROOT/husk-dead"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-husk1","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"}]}}\n' > "$resp/2.out"
  # 3: pane get -> pane_not_found: the restored pane is dead
  printf '{"error":{"code":"pane_not_found","message":"pane w1:p2 not found"}}\n' > "$resp/3.out"
  # 4: tab create -> the replacement tab (created BEFORE the husk is closed)
  printf '{"result":{"tab":{"tab_id":"w1:t3"},"root_pane":{"pane_id":"w1:p3"}}}\n' > "$resp/4.out"
  printf '{"result":{"tabs":[{"tab_id":"w1:t3","label":"fm-husk1","workspace_id":"w1"}]}}\n' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-husk1 /tmp/proj' "$ROOT" ) \
    || fail "create_task should close-and-replace a dead-pane husk instead of refusing"
  read -r tab pane <<EOF
$out
EOF
  if [ "$tab" != "w1:t3" ] || [ "$pane" != "w1:p3" ]; then
    fail "create_task should echo the NEW tab/pane ids, got '$out'"
  fi
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''create'$'\x1f''--workspace'$'\x1f''w1'$'\x1f''--cwd'$'\x1f''/tmp/proj'$'\x1f''--label'$'\x1f''fm-husk1' \
    "create_task did not create the replacement tab"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''close'$'\x1f''w1:t2' "create_task did not close the dead husk's tab"
  pass "fm_herdr_create_task: closes and replaces a same-labeled tab whose pane is dead (pane_not_found)"
}

test_create_task_closes_and_replaces_no_agent_husk() {
  local dir log resp fb out status tab pane
  dir="$TMP_ROOT/husk-no-agent"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-husk2","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"}]}}\n' > "$resp/2.out"
  # 3: pane get -> the pane is alive (a session-restore restarts the shell)
  printf '{"result":{"pane":{"pane_id":"w1:p2"}}}\n' > "$resp/3.out"
  # 4: agent get -> agent_not_found: nothing registered - a restored plain shell
  printf '{"error":{"code":"agent_not_found","message":"agent target w1:p2 not found"}}\n' > "$resp/4.out"
  # 5: tab create -> the replacement tab (created BEFORE the husk is closed)
  printf '{"result":{"tab":{"tab_id":"w1:t3"},"root_pane":{"pane_id":"w1:p3"}}}\n' > "$resp/5.out"
  printf '{"result":{"tabs":[{"tab_id":"w1:t3","label":"fm-husk2","workspace_id":"w1"}]}}\n' > "$resp/7.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-husk2 /tmp/proj' "$ROOT" ) \
    || fail "create_task should close-and-replace a no-agent husk (restored plain shell) instead of refusing"
  read -r tab pane <<EOF
$out
EOF
  if [ "$tab" != "w1:t3" ] || [ "$pane" != "w1:p3" ]; then
    fail "create_task should echo the NEW tab/pane ids, got '$out'"
  fi
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''create'$'\x1f''--workspace'$'\x1f''w1'$'\x1f''--cwd'$'\x1f''/tmp/proj'$'\x1f''--label'$'\x1f''fm-husk2' \
    "create_task did not create the replacement tab"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''close'$'\x1f''w1:t2' "create_task did not close the no-agent husk's tab"
  pass "fm_herdr_create_task: closes and replaces a same-labeled tab whose pane is alive but hosts no registered agent (a restored plain shell)"
}

test_create_task_closes_all_duplicate_husks_after_replacement() {
  local dir log resp fb out tab pane create_line close_p2_line close_p3_line
  dir="$TMP_ROOT/husk-multiple"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-husk-many","workspace_id":"w1"},{"tab_id":"w1:t3","label":"fm-husk-many","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"},{"pane_id":"w1:p3","tab_id":"w1:t3"}]}}\n' > "$resp/2.out"
  printf '{"result":{"pane":{"pane_id":"w1:p2"}}}\n' > "$resp/3.out"
  printf '{"error":{"code":"agent_not_found","message":"agent target w1:p2 not found"}}\n' > "$resp/4.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"},{"pane_id":"w1:p3","tab_id":"w1:t3"}]}}\n' > "$resp/5.out"
  printf '{"result":{"pane":{"pane_id":"w1:p3"}}}\n' > "$resp/6.out"
  printf '{"error":{"code":"agent_not_found","message":"agent target w1:p3 not found"}}\n' > "$resp/7.out"
  printf '{"result":{"tab":{"tab_id":"w1:t4"},"root_pane":{"pane_id":"w1:p4"}}}\n' > "$resp/8.out"
  printf '{"result":{"tabs":[{"tab_id":"w1:t4","label":"fm-husk-many","workspace_id":"w1"}]}}\n' > "$resp/11.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-husk-many /tmp/proj' "$ROOT" ) \
    || fail "create_task should close-and-replace all same-labeled husks after creating a replacement"
  read -r tab pane <<EOF
$out
EOF
  if [ "$tab" != "w1:t4" ] || [ "$pane" != "w1:p4" ]; then
    fail "create_task should echo the NEW tab/pane ids, got '$out'"
  fi
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''close'$'\x1f''w1:t2' "create_task did not close the first duplicate husk"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''close'$'\x1f''w1:t3' "create_task did not close the second duplicate husk"
  create_line=$(grep -n $'\x1f''tab'$'\x1f''create' "$log" | head -1 | cut -d: -f1)
  close_p2_line=$(grep -n $'\x1f''tab'$'\x1f''close'$'\x1f''w1:t2' "$log" | head -1 | cut -d: -f1)
  close_p3_line=$(grep -n $'\x1f''tab'$'\x1f''close'$'\x1f''w1:t3' "$log" | head -1 | cut -d: -f1)
  [ -n "$create_line" ] || fail "expected a 'tab create' call in the log"
  if [ "$create_line" -ge "$close_p2_line" ] || [ "$create_line" -ge "$close_p3_line" ]; then
    fail "REGRESSION: duplicate husks were closed before the replacement tab was created"
  fi
  pass "fm_herdr_create_task: closes every confirmed same-labeled husk only after creating the replacement"
}

test_create_task_refuses_when_preexisting_husk_tab_remains() {
  local dir log resp fb out status
  dir="$TMP_ROOT/husk-close-fails"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-stale-husk","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"}]}}\n' > "$resp/2.out"
  printf '{"result":{"pane":{"pane_id":"w1:p2"}}}\n' > "$resp/3.out"
  printf '{"error":{"code":"agent_not_found","message":"agent target w1:p2 not found"}}\n' > "$resp/4.out"
  printf '{"result":{"tab":{"tab_id":"w1:t3"},"root_pane":{"pane_id":"w1:p3"}}}\n' > "$resp/5.out"
  printf '1\n' > "$resp/6.exit"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-stale-husk","workspace_id":"w1"},{"tab_id":"w1:t3","label":"fm-stale-husk","workspace_id":"w1"}]}}\n' > "$resp/7.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-stale-husk /tmp/proj' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "create_task must fail when a preexisting same-labeled husk remains after close-and-replace"
  assert_contains "$out" "failed to remove preexisting herdr tab" "create_task did not report the stale preexisting husk tab"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''close'$'\x1f''w1:t2' "create_task did not close the stale husk by tab id"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close'$'\x1f''w1:p2' "create_task should not rely on pane close for a preexisting husk"
  pass "fm_herdr_create_task: refuses success when a preexisting husk tab remains after replacement"
}

test_create_task_refuses_when_agent_state_ambiguous() {
  # An unexpected error code from agent get (neither agent_not_found nor a
  # successful read) must not be misread as a husk - fail-safe toward
  # refusal, exactly like today's unconditional-refusal behavior.
  local dir log resp fb out status
  dir="$TMP_ROOT/husk-ambiguous"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-ambig1","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"}]}}\n' > "$resp/2.out"
  printf '{"result":{"pane":{"pane_id":"w1:p2"}}}\n' > "$resp/3.out"
  # 4: agent get -> an unrecognized error code, not agent_not_found
  printf '{"error":{"code":"internal_error","message":"transient failure"}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-ambig1 /tmp/proj' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "create_task must refuse (fail-safe) when the agent state cannot be classified confidently, not treat it as a husk"
  assert_contains "$out" "already exists" "create_task did not report the duplicate label for an ambiguous state"
  assert_not_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''create' "create_task must not create a replacement tab on an ambiguous read"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close' "create_task must not close a pane whose state is ambiguous"
  pass "fm_herdr_create_task: refuses (fail-safe) rather than guessing when the duplicate's agent state cannot be classified confidently"
}

test_create_task_husk_replacement_creates_before_closing() {
  # Safety-critical ordering: the replacement tab must be created BEFORE the
  # husk tab is closed, never the reverse - closing a workspace's LAST
  # remaining tab deletes the whole workspace on real herdr (docs/herdr-
  # backend.md "Workspace lifecycle"), and a session-restore husk can
  # legitimately be that workspace's only tab. Verified here by log order
  # rather than by state, since herdr's destroy-on-last-tab-close side effect
  # is not modeled by the canned-response fake.
  local dir log resp fb out create_line close_line
  dir="$TMP_ROOT/husk-order"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[{"tab_id":"w1:t2","label":"fm-order1","workspace_id":"w1"}]}}\n' > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p2","tab_id":"w1:t2"}]}}\n' > "$resp/2.out"
  printf '{"error":{"code":"pane_not_found","message":"pane w1:p2 not found"}}\n' > "$resp/3.out"
  printf '{"result":{"tab":{"tab_id":"w1:t3"},"root_pane":{"pane_id":"w1:p3"}}}\n' > "$resp/4.out"
  printf '{"result":{"tabs":[{"tab_id":"w1:t3","label":"fm-order1","workspace_id":"w1"}]}}\n' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-order1 /tmp/proj' "$ROOT" ) \
    || fail "create_task should close-and-replace the dead-pane husk"
  create_line=$(grep -n $'\x1f''tab'$'\x1f''create' "$log" | head -1 | cut -d: -f1)
  close_line=$(grep -n $'\x1f''tab'$'\x1f''close' "$log" | head -1 | cut -d: -f1)
  [ -n "$create_line" ] || fail "expected a 'tab create' call in the log"
  [ -n "$close_line" ] || fail "expected a 'tab close' call in the log"
  [ "$create_line" -lt "$close_line" ] || fail "REGRESSION: the husk tab was closed (line $close_line) before (or at the same time as) the replacement tab was created (line $create_line) - risks deleting the whole workspace if the husk was its only tab"
  pass "fm_herdr_create_task: creates the replacement tab BEFORE closing the husk tab, never the reverse"
}

test_create_task_creates_and_parses_ids() {
  local dir log resp fb out
  dir="$TMP_ROOT/create-task"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[]}}\n' > "$resp/1.out"
  printf '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}\n' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-newtask /tmp/proj' "$ROOT" )
  [ "$out" = "w1:t2 w1:p2" ] || fail "create_task should echo '<tab_id> <pane_id>', got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''create'$'\x1f''--workspace'$'\x1f''w1'$'\x1f''--cwd'$'\x1f''/tmp/proj'$'\x1f''--label'$'\x1f''fm-newtask' \
    "create_task did not call tab create with workspace/cwd/label"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close' \
    "create_task must never prune when called with no seeded default tab id (the 4th arg defaults to empty)"
  pass "fm_herdr_create_task: creates a tab and parses tab_id/pane_id from the JSON response, prunes nothing when no seeded tab id is given"
}

# --- container_ensure / create_task: --no-focus and per-home label ----------

test_container_ensure_creates_with_no_focus_flag() {
  local dir log resp fb out
  dir="$TMP_ROOT/container-no-focus"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"client":{"version":"0.7.1","protocol":14}}\n' > "$resp/1.out"
  printf '{"server":{"running":true}}\n' > "$resp/2.out"
  printf '{"result":{"workspaces":[]}}\n' > "$resp/3.out"
  printf '{"result":{"workspace":{"workspace_id":"w1","label":"firstmate"},"tab":{"tab_id":"w1:t1"},"root_pane":{"pane_id":"w1:p1"}}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /tmp' "$ROOT" )
  [ "$out" = $'fmtest:w1\tw1:t1' ] || fail "container_ensure should still echo '<session>:<workspace_id>\\t<seeded_default_tab_id>', got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''create'$'\x1f''--cwd'$'\x1f''/tmp'$'\x1f''--label'$'\x1f''firstmate'$'\x1f''--no-focus' \
    "container_ensure's workspace create did not pass --no-focus (focus-safety: never steal the captain's attention on spawn)"
  pass "fm_herdr_container_ensure: workspace create passes --no-focus"
}

test_container_ensure_uses_secondmate_home_label() {
  local dir log resp fb out home
  dir="$TMP_ROOT/container-secondmate-label"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  home="$TMP_ROOT/container-secondmate-home"; mkdir -p "$home"; printf 'sshhip-h7\n' > "$home/.fm-secondmate-home"
  printf '{"client":{"version":"0.7.1","protocol":14}}\n' > "$resp/1.out"
  printf '{"server":{"running":true}}\n' > "$resp/2.out"
  printf '{"result":{"workspaces":[]}}\n' > "$resp/3.out"
  printf '{"result":{"workspace":{"workspace_id":"w9","label":"2ndmate-sshhip-h7"},"tab":{"tab_id":"w9:t1"},"root_pane":{"pane_id":"w9:p1"}}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HOME="$home" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /tmp' "$ROOT" )
  [ "$out" = $'fmtest:w9\tw9:t1' ] || fail "container_ensure did not echo the expected session:workspace_id + seeded default tab id, got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''create'$'\x1f''--cwd'$'\x1f''/tmp'$'\x1f''--label'$'\x1f''2ndmate-sshhip-h7' \
    "container_ensure did not create the workspace under this secondmate home's own label"
  pass "fm_herdr_container_ensure: creates the workspace under the SECONDMATE home's own label, not 'firstmate'"
}

test_create_task_creates_with_no_focus_flag() {
  local dir log resp fb out
  dir="$TMP_ROOT/create-task-no-focus"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"tabs":[]}}\n' > "$resp/1.out"
  printf '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}\n' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task fmtest:w1 fm-newtask /tmp/proj' "$ROOT" )
  [ "$out" = "w1:t2 w1:p2" ] || fail "create_task should still echo '<tab_id> <pane_id>', got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''create'$'\x1f''--workspace'$'\x1f''w1'$'\x1f''--cwd'$'\x1f''/tmp/proj'$'\x1f''--label'$'\x1f''fm-newtask'$'\x1f''--no-focus' \
    "create_task's tab create did not pass --no-focus"
  pass "fm_herdr_create_task: tab create passes --no-focus"
}

# --- default-on disposable presentation projection --------------------------

# make_release_fakebin: a `herdr` stub whose only job is `status --json`, so the
# presentation version floor can be exercised against scripted client and
# selected-session server releases with no herdr installed at all. An empty
# protocol or version omits that field; the literal client value "unreadable"
# makes the whole call fail, and a server-running value other than true or false
# omits that state.
make_release_fakebin() {  # <dir> <client-protocol> <client-version> [<server-running> <server-protocol> <server-version>] -> echoes fakebin dir
  local dir=$1 protocol=$2 version=$3 server_running=${4:-false} server_protocol=${5:-} server_version=${6:-}
  local fb="$1/release-fakebin" fields="" server_fields=""
  mkdir -p "$fb"
  if [ -n "$version" ]; then
    fields="\"version\":\"$version\""
  fi
  if [ -n "$protocol" ]; then
    [ -n "$fields" ] && fields="$fields,"
    fields="$fields\"protocol\":$protocol"
  fi
  case "$server_running" in
    true|false) server_fields="\"running\":$server_running" ;;
  esac
  if [ -n "$server_version" ]; then
    [ -n "$server_fields" ] && server_fields="$server_fields,"
    server_fields="$server_fields\"version\":\"$server_version\""
  fi
  if [ -n "$server_protocol" ]; then
    [ -n "$server_fields" ] && server_fields="$server_fields,"
    server_fields="$server_fields\"protocol\":$server_protocol"
  fi
  cat > "$fb/herdr" <<SH
#!/usr/bin/env bash
set -u
[ "\${1:-}" = status ] || exit 3
SH
  if [ "$protocol" = unreadable ] || [ "$version" = unreadable ]; then
    printf 'exit 4\n' >> "$fb/herdr"
  else
    printf 'printf %s\n' "'{\"client\":{$fields},\"server\":{$server_fields}}\\n'" >> "$fb/herdr"
  fi
  chmod +x "$fb/herdr"
  printf '%s\n' "$fb"
}

# fm_herdr_presentation_enabled is the one gate bin/fm-spawn.sh consults
# before projecting a crewmate or scout, so these cases pin the default-on
# contract, its explicit opt-out, its explicit opt-in, and the version floor
# that decides the unconfigured default at that interface.
presentation_enabled_verdict() {  # <config-dir> <fakebin> [state-dir] [session] -> "on"/"off"
  HERDR_SESSION="${4:-}" PATH="$2:$PATH" bash -c '
    . "$0/bin/fm-herdr.sh"
    if fm_herdr_presentation_enabled "$1" "$2"; then printf "on\n"; else printf "off\n"; fi
  ' "$ROOT" "$1" "${3:-}"
}

# The exact release identities measured against the real macOS aarch64 release
# binaries on 2026-08-05 and recorded in docs/verification/herdr-runtime.md.
AT_FLOOR_PROTOCOL=19
AT_FLOOR_VERSION=0.8.0
BELOW_FLOOR_PROTOCOL=17
BELOW_FLOOR_VERSION=0.7.5

test_presentation_defaults_on_at_or_above_the_floor() {
  local dir config fb verdict stderr
  dir="$TMP_ROOT/presentation-default-on"; config="$dir/config"; mkdir -p "$config"
  stderr="$dir/default-on.err"
  fb=$(make_release_fakebin "$dir" "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = on ] || fail "an absent presentation config at the floor must resolve on, got '$verdict'"
  [ ! -s "$stderr" ] || fail "a supported release must not warn: $(cat "$stderr")"
  verdict=$(presentation_enabled_verdict "$dir/missing-config-dir" "$fb" 2>/dev/null)
  [ "$verdict" = on ] || fail "a missing config dir at the floor must resolve on, got '$verdict'"
  pass "herdr presentation: a home that set nothing gets the projection by default at or above the floor"
}

test_presentation_default_falls_back_below_the_floor() {
  local dir config fb verdict stderr
  dir="$TMP_ROOT/presentation-below-floor"; config="$dir/config"; mkdir -p "$config"
  stderr="$dir/below-floor.err"
  fb=$(make_release_fakebin "$dir" "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = off ] || fail "an unconfigured home below the floor must fall back flat, got '$verdict'"
  assert_contains "$(cat "$stderr")" "$BELOW_FLOOR_VERSION" \
    "the below-floor warning must name the running release"
  assert_contains "$(cat "$stderr")" "0.8.0" \
    "the below-floor warning must name the upgrade that fixes it"
  pass "herdr presentation: an unconfigured home below the floor falls back flat with one naming warning"
}

test_presentation_unreadable_release_falls_back() {
  local dir config fb verdict stderr
  dir="$TMP_ROOT/presentation-unreadable"; config="$dir/config"; mkdir -p "$config"
  stderr="$dir/unreadable.err"
  fb=$(make_release_fakebin "$dir" unreadable unreadable)
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = off ] || fail "an unverifiable release must fall back flat, got '$verdict'"
  assert_contains "$(cat "$stderr")" "could not be read" \
    "an unverifiable release must say the floor could not be checked"
  pass "herdr presentation: an unreadable client release falls back flat instead of guessing"
}

test_presentation_explicit_opt_in_survives_the_floor() {
  local dir config fb verdict stderr
  dir="$TMP_ROOT/presentation-legacy-opt-in"; config="$dir/config"; mkdir -p "$config"
  stderr="$dir/legacy.err"
  fb=$(make_release_fakebin "$dir" "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION")
  # The historical opt-in was a bare `touch` of the file, so an empty file must
  # keep meaning a deliberate on - and must not warn, or every migrated home
  # warns on every spawn.
  : > "$config/herdr-presentation-spaces"
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = on ] || fail "a legacy empty opt-in file must resolve on below the floor, got '$verdict'"
  [ ! -s "$stderr" ] || fail "a legacy empty opt-in file must not warn: $(cat "$stderr")"
  printf '\n \n' > "$config/herdr-presentation-spaces"
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = on ] || fail "a whitespace-only opt-in file must resolve on below the floor, got '$verdict'"
  [ ! -s "$stderr" ] || fail "a whitespace-only opt-in file must not warn: $(cat "$stderr")"
  printf 'on\n' > "$config/herdr-presentation-spaces"
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = on ] || fail "an explicit on must resolve on below the floor, got '$verdict'"
  [ ! -s "$stderr" ] || fail "an explicit opt-in must not warn: $(cat "$stderr")"
  pass "herdr presentation: a deliberate opt-in is never silently downgraded below the floor"
}

test_presentation_explicit_off_opts_out() {
  local dir config fb verdict value
  dir="$TMP_ROOT/presentation-opt-out"; config="$dir/config"; mkdir -p "$config"
  fb=$(make_release_fakebin "$dir" "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION")
  for value in 'off' 'off
' '  off  ' 'OFF' 'Off'; do
    printf '%s' "$value" > "$config/herdr-presentation-spaces"
    verdict=$(presentation_enabled_verdict "$config" "$fb" 2>/dev/null)
    [ "$verdict" = off ] || fail "the opt-out value '$value' must resolve off, got '$verdict'"
  done
  pass "herdr presentation: an explicit off opts the home out"
}

test_presentation_unrecognized_value_warns_and_keeps_the_default() {
  local dir config fb verdict stderr
  dir="$TMP_ROOT/presentation-unrecognized"; config="$dir/config"; mkdir -p "$config"
  stderr="$dir/unrecognized.err"
  printf 'disabled\n' > "$config/herdr-presentation-spaces"
  fb=$(make_release_fakebin "$dir" "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = on ] || fail "an unrecognized value at the floor must keep the default on, got '$verdict'"
  assert_contains "$(cat "$stderr")" 'unrecognized value' \
    "an unrecognized value must warn so a typo is visible"
  # A typo is not a deliberate opt-in, so below the floor it takes the default's
  # flat fallback rather than forcing a focus-unsafe projection.
  fb=$(make_release_fakebin "$dir" "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" 2>"$stderr")
  [ "$verdict" = off ] || fail "an unrecognized value below the floor must follow the default, got '$verdict'"
  pass "herdr presentation: an unrecognized value warns and follows the default instead of failing a spawn"
}

test_presentation_floor_warning_is_one_per_release() {
  local dir config state fb first second third
  dir="$TMP_ROOT/presentation-floor-dedupe"; config="$dir/config"; state="$dir/state"
  mkdir -p "$config" "$state"
  fb=$(make_release_fakebin "$dir" "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION")
  first=$(presentation_enabled_verdict "$config" "$fb" "$state" 2>&1 >/dev/null)
  second=$(presentation_enabled_verdict "$config" "$fb" "$state" 2>&1 >/dev/null)
  [ -n "$first" ] || fail "the first below-floor spawn must warn"
  [ -z "$second" ] || fail "a repeat spawn on the same release must not warn again: $second"
  # A downgrade or an upgrade is a different release, so it is announced again.
  fb=$(make_release_fakebin "$dir/other" 16 0.7.3)
  third=$(presentation_enabled_verdict "$config" "$fb" "$state" 2>&1 >/dev/null)
  assert_contains "$third" '0.7.3' "a changed release must re-announce the floor"
  pass "herdr presentation: the below-floor warning is one per home per release, not one per spawn"
}

test_presentation_floor_warning_marker_is_atomic_and_symlink_safe() {
  local dir config state fb i pid warnings marker outside symlink_warning failure_state failure_warning
  local pids=()
  dir="$TMP_ROOT/presentation-floor-marker-safety"; config="$dir/config"; state="$dir/state"
  mkdir -p "$config" "$state"
  fb=$(make_release_fakebin "$dir" "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION")
  for i in {1..20}; do
    presentation_enabled_verdict "$config" "$fb" "$state" \
      >"$dir/concurrent-$i.out" 2>"$dir/concurrent-$i.err" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || fail "a concurrent presentation-floor verdict failed"
  done
  warnings=$(awk '/^warning:/ { count++ } END { print count + 0 }' "$dir"/concurrent-*.err)
  [ "$warnings" -eq 1 ] \
    || fail "concurrent below-floor spawns must publish exactly one warning, got $warnings"

  state="$dir/symlink-state"
  mkdir -p "$state"
  marker="$state/.herdr-presentation-floor-version-0-7-5--protocol-17-"
  outside="$dir/symlink-target"
  ln -s "$outside" "$marker"
  symlink_warning=$(presentation_enabled_verdict "$config" "$fb" "$state" 2>&1 >/dev/null)
  [ -z "$symlink_warning" ] \
    || fail "an existing dangling marker symlink must be treated as already claimed: $symlink_warning"
  [ ! -e "$outside" ] \
    || fail "publishing the floor marker followed a dangling symlink outside the state directory"

  failure_state="$dir/failure-state"
  mkdir -p "$failure_state"
  cat > "$fb/ln" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$fb/ln"
  failure_warning=$(presentation_enabled_verdict "$config" "$fb" "$failure_state" 2>&1 >/dev/null)
  [ -n "$failure_warning" ] \
    || fail "a non-collision marker publication failure must not suppress the warning"
  pass "herdr presentation: warning marker publication is atomic, symlink-safe, and fails visible"
}

test_presentation_running_server_release_is_load_bearing() {
  local dir config fb verdict stderr
  dir="$TMP_ROOT/presentation-running-server-floor"; config="$dir/config"
  mkdir -p "$config"
  stderr="$dir/server.err"

  fb=$(make_release_fakebin "$dir/old-server" "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION" \
    true "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" "" stale-session 2>"$stderr")
  [ "$verdict" = off ] \
    || fail "an old running server must keep a new client below the presentation floor, got '$verdict'"
  assert_contains "$(cat "$stderr")" "server version $BELOW_FLOOR_VERSION" \
    "the floor warning must name the selected running server release"

  fb=$(make_release_fakebin "$dir/new-server" "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION" \
    true "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" "" current-session 2>"$stderr")
  [ "$verdict" = on ] \
    || fail "an at-floor client and running server must project, got '$verdict'"
  [ ! -s "$stderr" ] || fail "an at-floor client and running server must not warn: $(cat "$stderr")"

  fb=$(make_release_fakebin "$dir/old-client" "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION" \
    true "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" "" current-session 2>"$stderr")
  [ "$verdict" = off ] \
    || fail "a below-floor client must conservatively block projection despite an at-floor server, got '$verdict'"
  assert_contains "$(cat "$stderr")" "$BELOW_FLOOR_VERSION" \
    "the conservative client/server warning must name the below-floor client"

  printf 'on\n' > "$config/herdr-presentation-spaces"
  fb=$(make_release_fakebin "$dir/opt-in-old-server" "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION" \
    true "$BELOW_FLOOR_PROTOCOL" "$BELOW_FLOOR_VERSION")
  verdict=$(presentation_enabled_verdict "$config" "$fb" "" stale-session 2>"$stderr")
  [ "$verdict" = on ] \
    || fail "an explicit opt-in must survive a below-floor running server, got '$verdict'"
  [ ! -s "$stderr" ] || fail "an explicit opt-in below the server floor must not warn: $(cat "$stderr")"
  unlink "$config/herdr-presentation-spaces"

  fb=$(make_release_fakebin "$dir/unknown-server" "$AT_FLOOR_PROTOCOL" "$AT_FLOOR_VERSION" unknown)
  verdict=$(presentation_enabled_verdict "$config" "$fb" "" unknown-session 2>"$stderr")
  [ "$verdict" = off ] \
    || fail "an unreadable selected-session server state must fail flat instead of substituting the client, got '$verdict'"
  assert_contains "$(cat "$stderr")" "could not be read" \
    "an unreadable selected-session server state must warn"
  pass "herdr presentation: client and selected server floors compose conservatively without overriding explicit opt-in"
}

# The floor classifier is pure, so these cases pin it against every release
# identity measured from the real binaries plus the deliberate signal-loss and
# signal-divergence shapes that decide which signal carried a verdict.
release_floor_verdict() {  # <protocol> <version> -> above|below|indeterminate
  bash -c '
    . "$0/bin/fm-herdr.sh"
    status=0
    fm_herdr_release_floor_verdict "$1" "$2" || status=$?
    case "$status" in
      0) printf "above\n" ;;
      1) printf "below\n" ;;
      *) printf "indeterminate\n" ;;
    esac
  ' "$ROOT" "$1" "$2"
}

test_release_floor_verdict_matches_the_measured_releases() {
  local expected protocol version got case_line
  # protocol<TAB>version<TAB>expected, from the 2026-08-05 measurement.
  while IFS=$'\t' read -r protocol version expected; do
    [ -n "$expected" ] || continue
    got=$(release_floor_verdict "$protocol" "$version")
    [ "$got" = "$expected" ] \
      || fail "protocol '$protocol' version '$version' should be $expected, got $got"
  done <<'CASES'
16	0.7.3	below
16	0.7.4	below
17	0.7.5	below
17	0.7.5-preview.2026-07-21-0f10e1453a7f	below
18	0.7.5-preview.2026-07-29-44b3adb12552	below
19	0.8.0-preview.2026-08-04-d78e3d3b5126	above
19	0.8.0	above
20	0.9.0	above
CASES
  case_line=$(release_floor_verdict 19 '')
  [ "$case_line" = above ] || fail "a floor protocol alone must carry an above verdict, got $case_line"
  case_line=$(release_floor_verdict 17 '')
  [ "$case_line" = below ] || fail "a below-floor protocol alone must carry a below verdict, got $case_line"
  case_line=$(release_floor_verdict '' 0.8.0)
  [ "$case_line" = above ] || fail "a floor version alone must carry an above verdict, got $case_line"
  case_line=$(release_floor_verdict '' 0.7.5)
  [ "$case_line" = below ] || fail "a below-floor version alone must carry a below verdict, got $case_line"
  case_line=$(release_floor_verdict '' '')
  [ "$case_line" = indeterminate ] || fail "losing both signals must be indeterminate, got $case_line"
  case_line=$(release_floor_verdict 'not-a-number' 'not-a-version')
  [ "$case_line" = indeterminate ] || fail "two unparseable signals must be indeterminate, got $case_line"
  pass "herdr presentation floor: every measured release, and each signal alone, classifies correctly"
}

test_release_floor_verdict_survives_losing_either_signal() {
  local got
  # Divergence, asserted explicitly so neither half can go vacuous: with a
  # floor protocol and a below-floor version the protocol carries the verdict,
  # and removing it flips the answer, which proves it was load-bearing there.
  got=$(release_floor_verdict 19 0.7.5)
  [ "$got" = above ] || fail "the protocol signal must carry an above verdict on its own, got $got"
  got=$(release_floor_verdict '' 0.7.5)
  [ "$got" = below ] || fail "the divergent case must flip once the protocol signal is gone, got $got"
  # The mirror image: a floor version with a stale protocol, and the same
  # removal check.
  got=$(release_floor_verdict 16 0.9.0)
  [ "$got" = above ] || fail "the version signal must carry an above verdict on its own, got $got"
  got=$(release_floor_verdict 16 '')
  [ "$got" = below ] || fail "the divergent case must flip once the version signal is gone, got $got"
  pass "herdr presentation floor: either signal alone can carry an above verdict, and each divergence is real"
}

test_presentation_preference_reports_three_distinct_states() {
  local dir config got
  dir="$TMP_ROOT/presentation-preference"; config="$dir/config"; mkdir -p "$config"
  preference() {
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_preference "$1"' "$ROOT" "$1" 2>/dev/null
  }
  got=$(preference "$config")
  [ "$got" = default ] || fail "an absent file must report the default, got '$got'"
  printf 'on\n' > "$config/herdr-presentation-spaces"
  got=$(preference "$config")
  [ "$got" = on ] || fail "an explicit on must report on, got '$got'"
  printf 'off\n' > "$config/herdr-presentation-spaces"
  got=$(preference "$config")
  [ "$got" = off ] || fail "an explicit off must report off, got '$got'"
  printf 'disabled\n' > "$config/herdr-presentation-spaces"
  got=$(preference "$config")
  [ "$got" = default ] || fail "an unrecognized value must report the default, got '$got'"
  pass "herdr presentation: config parsing separates a deliberate choice from an unconfigured default"
}

test_projection_journal_is_atomic_and_uses_128_bit_token() {
  local dir state out token parsed status
  dir="$TMP_ROOT/projection-journal"; state="$dir/state"; mkdir -p "$state"
  out=$(bash -c '
    . "$0/bin/fm-herdr.sh"
    token=$(fm_herdr_projection_journal_create "$1" task-p1) || exit 1
    parsed=$(fm_herdr_projection_journal_token "$1/task-p1.herdr-presentation" task-p1) || exit 1
    printf "%s\n%s\n" "$token" "$parsed"
    fm_herdr_projection_journal_create "$1" task-p1 >/dev/null 2>&1
  ' "$ROOT" "$state" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "a second presentation journal publication must fail instead of overwriting the first"
  token=$(printf '%s\n' "$out" | sed -n '1p')
  parsed=$(printf '%s\n' "$out" | sed -n '2p')
  [ "$token" = "$parsed" ] || fail "journal round-trip changed the projection id"
  [ "${#token}" -eq 22 ] || fail "a 128-bit base64url projection id must be 22 characters, got '${#token}'"
  case "$token" in *[!A-Za-z0-9_-]*) fail "projection id was not base64url: $token" ;; esac
  [ "$(wc -l < "$state/task-p1.herdr-presentation" | tr -d '[:space:]')" = 3 ] \
    || fail "presentation journal must contain only version, task id, and projection id"
  pass "herdr presentation journal: atomically publishes one non-authoritative 128-bit correlator and refuses overwrite"
}

test_projection_journal_v2_binds_and_advances_exact_endpoint() {
  local dir state home home_real out token
  dir="$TMP_ROOT/projection-journal-v2"; state="$dir/state"; home="$dir/home"
  mkdir -p "$state" "$home"
  home_real=$(cd "$home" && pwd -P)
  out=$(bash -c '
    . "$0/bin/fm-herdr.sh"
    token=$(fm_herdr_projection_journal_create "$1" fm-hibit-r1) || exit 1
    journal="$1/fm-hibit-r1.herdr-presentation"
    home=$(fm_herdr_projection_home_identity "$2") || exit 1
    label=$(fm_herdr_projection_workspace_label fm-hibit-r1 "$token")
    fm_herdr_projection_journal_bind \
      "$journal" fm-hibit-r1 "$home" lab-session w2 w2:t2 w2:p2 w1 firstmate "$label" fm-fm-hibit-r1 || exit 1
    fm_herdr_projection_journal_snapshot "$journal" fm-hibit-r1 || exit 1
    printf "%s|%s|%s|%s|%s|%s|%s\n" \
      "$FM_HERDR_JOURNAL_VERSION" \
      "$FM_HERDR_JOURNAL_HOME" \
      "$FM_HERDR_JOURNAL_WORKSPACE_ID" \
      "$FM_HERDR_JOURNAL_TAB_ID" \
      "$FM_HERDR_JOURNAL_PANE_ID" \
      "$FM_HERDR_JOURNAL_PARENT_WORKSPACE_ID" \
      "$FM_HERDR_JOURNAL_WORKSPACE_LABEL"
    fm_herdr_projection_journal_replace_endpoint \
      "$journal" fm-hibit-r1 w2:t2 w2:p2 w2:t3 w2:p3 || exit 1
    fm_herdr_projection_journal_snapshot "$journal" fm-hibit-r1 || exit 1
    printf "%s|%s\n" "$FM_HERDR_JOURNAL_TAB_ID" "$FM_HERDR_JOURNAL_PANE_ID"
  ' "$ROOT" "$state" "$home") || fail "version 2 projection journal binding failed"
  token=$(sed -n 's/^projection_id=//p' "$state/fm-hibit-r1.herdr-presentation")
  [ "$(printf '%s\n' "$out" | sed -n '1p')" = "2|$home_real|w2|w2:t2|w2:p2|w1|└ hibit-r1 · p:$token" ] \
    || fail "version 2 projection journal did not retain exact home/endpoint/parent binding: $out"
  [ "$(printf '%s\n' "$out" | sed -n '2p')" = "w2:t3|w2:p3" ] \
    || fail "version 2 projection journal did not advance the exact replacement endpoint: $out"
  [ "$(wc -l < "$state/fm-hibit-r1.herdr-presentation" | tr -d '[:space:]')" = 12 ] \
    || fail "version 2 projection journal must have exactly 12 fields"
  printf 'pane_id=duplicate\n' >> "$state/fm-hibit-r1.herdr-presentation"
  if bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_journal_snapshot "$1" fm-hibit-r1' \
    "$ROOT" "$state/fm-hibit-r1.herdr-presentation"; then
    fail "duplicate version 2 journal fields must be ambiguous"
  fi
  pass "herdr presentation journal: version 2 binds exact home/endpoint/parent identities and advances atomically"
}

test_projection_create_uses_exact_response_ids_and_leaves_one_task_pane() {
  local dir state log resp fb out token journal
  dir="$TMP_ROOT/projection-create"; state="$dir/state"; mkdir -p "$dir/responses" "$state"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1"},"root_pane":{"pane_id":"w9:p1"}}}\n' > "$resp/1.out"
  printf '{"result":{"tab":{"tab_id":"w9:t2"},"root_pane":{"pane_id":"w9:p2"}}}\n' > "$resp/2.out"
  printf '{"result":{"tabs":[{"tab_id":"w9:t1","label":"1","workspace_id":"w9"},{"tab_id":"w9:t2","label":"fm-task-p2","workspace_id":"w9"}]}}\n' > "$resp/3.out"
  printf '{"result":{"panes":[{"pane_id":"w9:p1","tab_id":"w9:t1"},{"pane_id":"w9:p2","tab_id":"w9:t2"}]}}\n' > "$resp/4.out"
  printf '{"error":{"code":"agent_not_found"}}\n' > "$resp/5.out"
  printf '{"result":{"pane":{"pane_id":"w9:p1","tab_id":"w9:t1","workspace_id":"w9"}}}\n' > "$resp/6.out"
  # The emptying-close plan's tab list proves the seeded prune is NOT
  # workspace-emptying (the task tab remains), so the close stays plain.
  printf '{"result":{"tabs":[{"tab_id":"w9:t1","label":"1","workspace_id":"w9"},{"tab_id":"w9:t2","label":"fm-task-p2","workspace_id":"w9"}]}}\n' > "$resp/7.out"
  printf '{"error":{"code":"pane_not_found"}}\n' > "$resp/9.out"
  printf '{"result":{"tabs":[{"tab_id":"w9:t2","label":"fm-task-p2","workspace_id":"w9"}]}}\n' > "$resp/10.out"
  printf '{"result":{"panes":[{"pane_id":"w9:p2","tab_id":"w9:t2"}]}}\n' > "$resp/11.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" HERDR_SESSION=fmtest \
    bash -c '
      . "$0/bin/fm-herdr.sh"
      fm_herdr_projection_focus_snapshot() { printf "captain-ws\tcaptain-tab"; }
      fm_herdr_projection_focus_restore() { return 0; }
      token=$(fm_herdr_projection_journal_create "$1" task-p2) || exit 1
      label=$(fm_herdr_projection_workspace_label task-p2 "$token")
      fm_herdr_projection_create_task /tmp/proj "$label" fm-task-p2 || exit 1
      printf "%s %s %s %s %s\n" \
        "$FM_HERDR_PROJECTION_WORKSPACE_ID" \
        "$FM_HERDR_PROJECTION_SEEDED_TAB_ID" \
        "$FM_HERDR_PROJECTION_SEEDED_PANE_ID" \
        "$FM_HERDR_PROJECTION_TAB_ID" \
        "$FM_HERDR_PROJECTION_PANE_ID"
    ' "$ROOT" "$state") || fail "projection create should succeed from complete exact responses"
  [ "$out" = "w9 w9:t1 w9:p1 w9:t2 w9:p2" ] || fail "projection create did not retain exact response IDs: $out"
  journal="$state/task-p2.herdr-presentation"
  token=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_journal_token "$1" task-p2' "$ROOT" "$journal") \
    || fail "projection journal was not readable"
  assert_contains "$(cat "$log")" $'workspace\x1fcreate\x1f--cwd\x1f/tmp/proj\x1f--label\x1f└ task-p2 · p:'"$token"$'\x1f--no-focus' \
    "projection workspace create did not use the corner label, full token, and --no-focus"
  assert_contains "$(cat "$log")" $'tab\x1fcreate\x1f--workspace\x1fw9\x1f--cwd\x1f/tmp/proj\x1f--label\x1ffm-task-p2\x1f--no-focus' \
    "projection task tab did not target the exact new workspace"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw9:p1' \
    "projection create did not prune the exact seeded root pane"
  assert_not_contains "$(cat "$log")" $'workspace\x1fclose' \
    "projection create must never call workspace close"
  pass "herdr presentation create: exact response IDs yield one normal task pane with no workspace-close authority"
}

test_projection_create_never_closes_a_concurrent_same_label_tab() {
  local dir log resp fb out status
  dir="$TMP_ROOT/projection-concurrent-tab"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1"},"root_pane":{"pane_id":"w9:p1"}}}\n' > "$resp/1.out"
  printf '{"result":{"tab":{"tab_id":"w9:t2"},"root_pane":{"pane_id":"w9:p2"}}}\n' > "$resp/2.out"
  printf '{"result":{"tabs":[{"tab_id":"w9:t1","label":"1","workspace_id":"w9"},{"tab_id":"w9:t2","label":"fm-task-p2","workspace_id":"w9"},{"tab_id":"w9:t3","label":"fm-task-p2","workspace_id":"w9"}]}}\n' > "$resp/3.out"
  printf '{"result":{"panes":[{"pane_id":"w9:p1","tab_id":"w9:t1"},{"pane_id":"w9:p2","tab_id":"w9:t2"},{"pane_id":"w9:p3","tab_id":"w9:t3"}]}}\n' > "$resp/4.out"
  printf '{"error":{"code":"agent_not_found"}}\n' > "$resp/5.out"
  printf '{"result":{"pane":{"pane_id":"w9:p1","tab_id":"w9:t1","workspace_id":"w9"}}}\n' > "$resp/6.out"
  printf '{"result":{"tabs":[{"tab_id":"w9:t1","label":"1","workspace_id":"w9"},{"tab_id":"w9:t2","label":"fm-task-p2","workspace_id":"w9"},{"tab_id":"w9:t3","label":"fm-task-p2","workspace_id":"w9"}]}}\n' > "$resp/7.out"
  printf '{"error":{"code":"pane_not_found"}}\n' > "$resp/9.out"
  printf '{"result":{"tabs":[{"tab_id":"w9:t2","label":"fm-task-p2","workspace_id":"w9"},{"tab_id":"w9:t3","label":"fm-task-p2","workspace_id":"w9"}]}}\n' > "$resp/10.out"
  printf '{"result":{"panes":[{"pane_id":"w9:p2","tab_id":"w9:t2"},{"pane_id":"w9:p3","tab_id":"w9:t3"}]}}\n' > "$resp/11.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_focus_snapshot() { printf "captain-ws\tcaptain-tab"; }; fm_herdr_projection_focus_restore() { return 0; }; fm_herdr_projection_create_task /tmp/proj label fm-task-p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "a concurrent tab should prevent exact one-pane projection convergence"
  assert_contains "$out" "did not converge to exactly one task pane" \
    "projection did not report the concurrent shape"
  assert_not_contains "$(cat "$log")" $'tab\x1fclose\x1fw9:t3' \
    "projection closed a concurrent same-label tab"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose\x1fw9:p3' \
    "projection closed a concurrent same-label pane"
  pass "herdr presentation create: concurrent same-label tabs are never prune targets"
}

test_projection_focus_snapshot_requires_exact_workspace_and_tab() {
  local dir log resp fb out
  dir="$TMP_ROOT/projection-focus-snapshot"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":true}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":false},{"tab_id":"w2:t2","focused":true}]}}' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_focus_snapshot fmtest' "$ROOT") \
    || fail "an exact active workspace and tab should produce a focus snapshot"
  [ "$out" = $'w2\tw2:t2' ] || fail "focus snapshot did not preserve exact response IDs: $out"
  pass "herdr presentation focus: snapshot requires one exact active workspace and tab"
}

test_projection_close_restores_exact_prior_focus() {
  local dir log resp fb out status
  dir="$TMP_ROOT/projection-focus-restore"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":true},{"workspace_id":"w9","active_tab_id":"w9:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":false},{"tab_id":"w2:t2","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w9:p2","tab_id":"w9:t2","workspace_id":"w9"}}}' > "$resp/3.out"
  # The emptying-close plan sees a second tab in w9, so the close stays plain
  # and the exact-tab restore backstop is what reclaims the stolen focus.
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w9:t1","workspace_id":"w9"},{"tab_id":"w9:t2","workspace_id":"w9"}]}}' > "$resp/4.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/6.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":false},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":true}]}}' > "$resp/7.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w3:t1","focused":true}]}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w2:t2","workspace_id":"w2","focused":true}}}' > "$resp/10.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/11.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":false},{"tab_id":"w2:t2","focused":true}]}}' > "$resp/12.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w9:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "an exact non-active projection close should succeed after restoring focus: $out"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw9:p2' \
    "focus-preserving cleanup did not close only the exact projection pane"
  assert_contains "$(cat "$log")" $'tab\x1ffocus\x1fw2:t2' \
    "focus-preserving cleanup did not restore the exact prior active tab"
  assert_not_contains "$(cat "$log")" $'workspace\x1fclose' \
    "focus-preserving cleanup introduced workspace-close authority"
  pass "herdr presentation focus: exact pane close restores the exact prior workspace and tab"
}

test_projection_close_refuses_active_tab() {
  local dir log resp fb out status
  dir="$TMP_ROOT/projection-focus-active-refusal"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w9","active_tab_id":"w9:t2","focused":true}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w9:t2","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w9:p2","tab_id":"w9:t2","workspace_id":"w9"}}}' > "$resp/3.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w9:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "cleanup must refuse when exact active-tab preservation is impossible"
  assert_contains "$out" "target is the captain's active tab" \
    "active-tab cleanup refusal did not explain the focus-safety boundary"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' \
    "active-tab cleanup refusal still closed the pane"
  pass "herdr presentation focus: cleanup refuses rather than close the captain's active tab"
}

test_projection_close_reports_focus_restore_failure() {
  local dir log resp fb out status
  dir="$TMP_ROOT/projection-focus-restore-failure"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w9","active_tab_id":"w9:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w9:p2","tab_id":"w9:t2","workspace_id":"w9"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w9:t1","workspace_id":"w9"},{"tab_id":"w9:t2","workspace_id":"w9"}]}}' > "$resp/4.out"
  : > "$resp/5.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/6.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true}]}}' > "$resp/7.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/9.out"
  : > "$resp/10.out"
  cp "$resp/7.out" "$resp/11.out"
  cp "$resp/8.out" "$resp/12.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w9:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 2 ] || fail "cleanup did not distinguish post-close focus uncertainty: $status"
  assert_contains "$out" "did not restore the exact prior workspace and tab" \
    "focus restoration failure was not reported"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw9:p2' \
    "focus restoration failure fixture did not reach the close boundary"
  pass "herdr presentation focus: pane close fails when exact focus restoration fails"
}

test_projection_close_rechecks_required_agent_state_at_boundary() {
  local dir log out status
  dir="$TMP_ROOT/projection-close-agent-boundary"; mkdir -p "$dir"
  log="$dir/log"; : > "$log"
  out=$(ROOT="$ROOT" LOG="$log" bash -c '
    . "$ROOT/bin/fm-herdr.sh"
    fm_herdr_projection_focus_snapshot() { printf "w1\tw1:t1"; }
    fm_herdr_pane_agent_state() { printf live; }
    fm_herdr_cli() {
      printf "%s\n" "$*" >> "$LOG"
      case "$2 $3" in
        "pane get") printf "{\"result\":{\"pane\":{\"pane_id\":\"w9:p2\",\"tab_id\":\"w9:t2\"}}}\n" ;;
      esac
    }
    set +e
    fm_herdr_projection_close_pane_focus_preserving fmtest w9:p2 no-agent
    rc=$?
    set -e
    printf "%s:%s" "$rc" "$FM_HERDR_PROJECTION_CLOSE_AGENT_STATE"
  ')
  status=${out%%:*}
  [ "$status" -ne 0 ] && [ "$out" = "$status:live" ] \
    || fail "required close-boundary agent state did not refuse live: $out"
  assert_not_contains "$(cat "$log")" "pane close" \
    "required close-boundary agent state still closed a live pane"
  pass "herdr presentation reclaim: live agent state at the close boundary refuses mutation"
}

# --- emptying-close focus-safe removal (Herdr 0.7.5 #1621 mitigation) ------
#
# The fixtures below model the verified 0.7.5 rules: an explicit close that
# empties a non-focused workspace moves focus to that workspace's neighbor,
# while a pane-death removal preserves focus whenever the dying workspace
# sits behind the focused one (or the focused one is last).

# make_death_lab <dir> <shell-pid>: a fake ps and a fake workspace mover for
# the pane-death close fixtures. The mover appends to $FM_FAKE_MOVER_LOG and
# exits 9 unless $FM_FAKE_MOVER_RESPONSE names a readable response file.
make_death_lab() {  # <dir> <shell-pid>
  local dir=$1 pid=$2
  mkdir -p "$dir"
  cat > "$dir/ps" <<SH
#!/usr/bin/env bash
case "\$*" in
  "-axo pid=,ppid=") printf '1 0\n$pid 1\n' ;;
  "-p $pid -o stat=") printf 'Ss+\n' ;;
  "-p $pid -o comm=") printf -- '-zsh\n' ;;
  *) exit 1 ;;
esac
SH
  cat > "$dir/mover" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FM_FAKE_MOVER_LOG"
calls=$(wc -l < "$FM_FAKE_MOVER_LOG" | tr -d ' ')
if [ "$calls" -ge 2 ] && [ -f "${FM_FAKE_MOVER_RESPONSE_2:-}" ]; then
  cat "$FM_FAKE_MOVER_RESPONSE_2"
  exit 0
fi
if [ -f "$FM_FAKE_MOVER_RESPONSE" ]; then
  cat "$FM_FAKE_MOVER_RESPONSE"
  exit 0
fi
exit 9
SH
  chmod +x "$dir/ps" "$dir/mover"
  : > "$dir/mover.log"
}

death_process_info_fixture() {  # <pane> <pid>
  printf '{"result":{"type":"pane_process_info","process_info":{"pane_id":"%s","shell_pid":%s,"foreground_process_group_id":%s,"foreground_processes":[{"pid":%s,"name":"zsh","argv0":"zsh"}]}}}\n' "$1" "$2" "$2" "$2"
}

test_projection_close_emptying_after_focus_uses_pane_death_without_move() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-death-after"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  # w1 focused; target w2 sits after it (r > a), so no repositioning is needed.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  sleep 300 & bgpid=$!
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/10.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  [ "$status" -eq 0 ] || fail "emptying close behind focus should succeed through the pane-death path: $out"
  [ ! -s "$dir/mover.log" ] || fail "a close already behind focus invoked the workspace mover"
  assert_contains "$(cat "$log")" $'pane\x1fprocess-info' "pane-death close skipped the idle-shell proof"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "emptying close behind focus used the focus-unsafe explicit close"
  assert_not_contains "$(cat "$log")" $'tab\x1ffocus' "focus moved despite the pane-death removal"
  pass "herdr presentation cleanup: emptying close behind focus ends the exact shell without a move or focus change"
}

test_projection_close_emptying_before_focus_repositions_then_uses_pane_death() {
  local dir log resp fb out status bgpid mover_line
  dir="$TMP_ROOT/close-death-before"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Target w1 sits BEFORE the focused w2, which is not last: reposition first.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  printf '%s\n' '{"client":{"version":"0.7.5","protocol":16},"server":{"running":true}}' > "$resp/7.out"
  # shellcheck disable=SC2016 # $defs is a literal JSON Schema key.
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/8.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/9.out"
  sleep 300 & bgpid=$!
  death_process_info_fixture w1:p1 "$bgpid" > "$resp/10.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/11.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/12.out"
  cp "$resp/12.out" "$resp/13.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/14.out"
  make_death_lab "$dir" "$bgpid"
  printf '%s\n' '{"id":"fm-workspace-move","result":{"type":"workspace_list","workspaces":[{"workspace_id":"w2","focused":true},{"workspace_id":"w3","focused":false},{"workspace_id":"w1","focused":false}]}}' > "$dir/mover-response"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/mover-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w1:p1' "$ROOT" 2>&1)
  status=$?
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  [ "$status" -eq 0 ] || fail "repositioned emptying close should succeed through the pane-death path: $out"
  [ "$(cat "$dir/mover.log")" = "$(cd /tmp && pwd -P)/fmtest.sock"$'\t'"w1"$'\t'"3" ] \
    || fail "the repositioning move did not target the exact doomed workspace at the list length: $(cat "$dir/mover.log")"
  mover_line=$(grep -n $'pane\x1fprocess-info' "$log" | head -1 | cut -d: -f1)
  [ -n "$mover_line" ] || fail "repositioned close skipped the idle-shell proof"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "repositioned emptying close used the focus-unsafe explicit close"
  assert_not_contains "$(cat "$log")" $'tab\x1ffocus' "focus moved despite the repositioned pane-death removal"
  pass "herdr presentation cleanup: emptying close before focus moves the doomed workspace to the end and ends its exact shell"
}

test_projection_close_emptying_before_last_focus_needs_no_move() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-death-focus-last"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Focused w3 is LAST, so the pane-death clamp preserves it without a move.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":false},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":true}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w3:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  sleep 300 & bgpid=$!
  death_process_info_fixture w1:p1 "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w2","active_tab_id":"w2:t1","focused":false},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":true}]}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w3:t1","focused":true}]}}' > "$resp/10.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w1:p1' "$ROOT" 2>&1)
  status=$?
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  [ "$status" -eq 0 ] || fail "emptying close with last focus should succeed through the pane-death path: $out"
  [ ! -s "$dir/mover.log" ] || fail "a last-focused close invoked the workspace mover"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "last-focused emptying close used the focus-unsafe explicit close"
  assert_not_contains "$(cat "$log")" $'tab\x1ffocus' "focus moved despite the pane-death removal"
  pass "herdr presentation cleanup: emptying close with the focused workspace last skips the move"
}

test_projection_close_emptying_last_workspace_needs_no_move() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-death-target-last"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Target w3 is already last (r > a), so no repositioning is needed.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":false},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w3:p1","tab_id":"w3:t1","workspace_id":"w3"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w3:t1","workspace_id":"w3"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w3:p1","tab_id":"w3:t1"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  sleep 300 & bgpid=$!
  death_process_info_fixture w3:p1 "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":false}]}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/10.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w3:p1' "$ROOT" 2>&1)
  status=$?
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  [ "$status" -eq 0 ] || fail "last-workspace emptying close should succeed through the pane-death path: $out"
  [ ! -s "$dir/mover.log" ] || fail "an already-last close invoked the workspace mover"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "last-workspace emptying close used the focus-unsafe explicit close"
  pass "herdr presentation cleanup: emptying close of the last workspace skips the move"
}

test_projection_close_non_emptying_stays_plain_without_proof_or_move() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-non-emptying"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","workspace_id":"w2"},{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/6.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":false}]}}' > "$resp/7.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/8.out"
  sleep 300 & bgpid=$!
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "non-emptying close should succeed through the plain close: $out"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw2:p2' "non-emptying close did not use the plain close"
  assert_not_contains "$(cat "$log")" $'pane\x1fprocess-info' "non-emptying close ran the idle-shell proof"
  [ ! -s "$dir/mover.log" ] || fail "non-emptying close invoked the workspace mover"
  kill -0 "$bgpid" 2>/dev/null || fail "non-emptying close signaled the pane's shell"
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  pass "herdr presentation cleanup: a non-emptying close stays plain with no proof, move, or signal"
}

test_projection_close_plain_without_move_requires_structured_removal() {
  local dir log out status
  dir="$TMP_ROOT/close-plain-unconfirmed"; mkdir -p "$dir"
  log="$dir/log"; : > "$log"
  out=$(ROOT="$ROOT" LOG="$log" bash -c '
    . "$ROOT/bin/fm-herdr.sh"
    fm_herdr_projection_focus_snapshot() { printf "w1\tw1:t1"; }
    fm_herdr_emptying_close_plan() { printf "plain\n"; }
    fm_herdr_projection_focus_restore() { return 0; }
    fm_herdr_cli() {
      printf "%s\n" "$*" >> "$LOG"
      case "$2 $3" in
        "pane get") printf "{\"result\":{\"pane\":{\"pane_id\":\"w2:p2\",\"tab_id\":\"w2:t2\",\"workspace_id\":\"w2\"}}}\n" ;;
      esac
    }
    fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2
  ' 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "a no-move plain close must fail while structured presence remains present: $out"
  assert_contains "$(cat "$log")" "pane close w2:p2" \
    "the no-move unconfirmed regression did not reach the explicit close"
  pass "herdr presentation cleanup: no-move plain close requires structured pane removal"
}

test_projection_close_ambiguous_positions_fall_back_to_plain_close() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-ambiguous-positions"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  # The position snapshot is ambiguous: the target workspace is absent.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/6.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/10.out"
  sleep 300 & bgpid=$!
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "an ambiguous position snapshot should fall back to the plain close: $out"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw2:p2' "ambiguous positions did not use the plain close"
  assert_not_contains "$(cat "$log")" $'pane\x1fprocess-info' "ambiguous positions ran the idle-shell proof"
  [ ! -s "$dir/mover.log" ] || fail "ambiguous positions invoked the workspace mover"
  kill -0 "$bgpid" 2>/dev/null || fail "ambiguous positions signaled the pane's shell"
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  pass "herdr presentation cleanup: an ambiguous workspace layout falls back to the plain close"
}

test_projection_close_move_failure_falls_back_to_plain_close() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-move-failure"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  printf '%s\n' '{"client":{"version":"0.7.5","protocol":16},"server":{"running":true}}' > "$resp/7.out"
  # shellcheck disable=SC2016 # $defs is a literal JSON Schema key.
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/8.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/9.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/11.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/12.out"
  cp "$resp/12.out" "$resp/13.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/14.out"
  sleep 300 & bgpid=$!
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w1:p1' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "a failed repositioning move should fall back to the plain close: $out"
  assert_contains "$out" "could not move the doomed workspace behind the focused one" \
    "a failed repositioning move did not warn about losing the focus-safe path"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw1:p1' "move failure did not use the plain close"
  assert_not_contains "$(cat "$log")" $'pane\x1fprocess-info' "move failure ran the idle-shell proof"
  kill -0 "$bgpid" 2>/dev/null || fail "move failure signaled the pane's shell"
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  pass "herdr presentation cleanup: a failed repositioning move falls back to the plain close with a warning"
}

test_projection_close_busy_pane_falls_back_to_plain_close() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-busy-pane"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  sleep 300 & bgpid=$!
  # The pane still has a foreground agent, so the idle-shell proof refuses.
  printf '{"result":{"type":"pane_process_info","process_info":{"pane_id":"w2:p2","shell_pid":%s,"foreground_process_group_id":%s,"foreground_processes":[{"pid":%s,"name":"zsh","argv0":"zsh"},{"pid":99999,"name":"pi","argv0":"pi"}]}}}\n' "$bgpid" "$bgpid" "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/10.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/11.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 FM_HERDR_IDLE_SHELL_PROOF_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "a busy pane should fall back to the plain close: $out"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw2:p2' "a busy pane did not use the plain close"
  kill -0 "$bgpid" 2>/dev/null || fail "a busy pane close signaled the pane's shell"
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  pass "herdr presentation cleanup: a pane with a live foreground process falls back to the plain close"
}

test_projection_close_transient_prompt_helper_settles_then_uses_pane_death() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-transient-helper"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  sleep 300 & bgpid=$!
  # Sample 1: the shell is transiently redrawing its prompt (real 0.7.5 shape:
  # a helper such as starship rides along as a second foreground process).
  printf '{"result":{"type":"pane_process_info","process_info":{"pane_id":"w2:p2","shell_pid":%s,"foreground_process_group_id":%s,"foreground_processes":[{"pid":99998,"name":"starship","argv":["/usr/local/bin/starship","prompt","--continuation"]},{"pid":%s,"name":"zsh","argv0":"zsh"}]}}}\n' "$bgpid" "$bgpid" "$bgpid" > "$resp/7.out"
  # Sample 2: the helper finished; the shell is provably alone and idle.
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/8.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/10.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/11.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 FM_HERDR_IDLE_SHELL_PROOF_POLLS=3 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  [ "$status" -eq 0 ] || fail "a transient prompt helper should settle into the pane-death path: $out"
  [ "$(grep -c $'pane\x1fprocess-info' "$log")" -ge 2 ] \
    || fail "the settle window did not retry the idle-shell proof"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "a transient prompt helper forced the focus-unsafe explicit close"
  assert_not_contains "$(cat "$log")" $'tab\x1ffocus' "focus moved despite the settled pane-death removal"
  pass "herdr presentation cleanup: a transient prompt helper settles into the pane-death path instead of the plain close"
}

test_projection_close_death_escalates_sigkill_after_sighup_survival() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-death-escalate"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  bash -c 'trap "" HUP; sleep 300' & bgpid=$!
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"error":{"code":"internal_error","message":"transient failure"}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/9.out"
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/10.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/11.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/12.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/13.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "a SIGHUP-surviving shell should be finished by the SIGKILL escalation: $out"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "the SIGKILL escalation used the focus-unsafe explicit close"
  if kill -0 "$bgpid" 2>/dev/null; then
    kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
    fail "the SIGKILL escalation left the trapped shell alive"
  fi
  wait "$bgpid" 2>/dev/null || true
  pass "herdr presentation cleanup: a SIGHUP-surviving shell is escalated to SIGKILL before giving up"
}

test_projection_close_death_failure_falls_back_to_plain_close() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-death-fallback"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  bash -c 'trap "" HUP; sleep 300' & bgpid=$!
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/9.out"
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/10.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/11.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/12.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/14.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/15.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/16.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "an unkillable shell should fall back to the plain close: $out"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw2:p2' "a failed pane-death close did not use the plain close fallback"
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  pass "herdr presentation cleanup: a failed pane-death close falls back to the plain close"
}

test_projection_close_death_still_restores_a_stolen_focus() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-death-restore"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  sleep 300 & bgpid=$!
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/8.out"
  # The backstop still fires when the post-close snapshot disagrees.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":true}]}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w3:t1","focused":true}]}}' > "$resp/10.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/11.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/13.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/14.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "the pane-death close with a restored backstop should succeed: $out"
  assert_contains "$(cat "$log")" $'tab\x1ffocus\x1fw1:t1' "the backstop did not restore the exact prior tab"
  pass "herdr presentation cleanup: the exact-tab restore remains the backstop behind the pane-death close"
}

test_projection_close_death_never_sigkills_a_reused_pid() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-death-pid-reuse"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  # The original shell survives SIGHUP; by SIGKILL time the pane's process
  # information shows a DIFFERENT shell pid, modeling the original pid having
  # been reused by an unrelated process the pane no longer owns.
  bash -c 'trap "" HUP; sleep 300' & bgpid=$!
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/7.out"
  cp "$resp/3.out" "$resp/8.out"   # SIGHUP poll 1: pane still present
  cp "$resp/3.out" "$resp/9.out"   # SIGHUP poll 2: pane still present
  death_process_info_fixture w2:p2 99997 > "$resp/10.out"
  : > "$resp/11.out"               # fallback explicit close: pane close ok
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/12.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/13.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/14.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w2:p2' "$ROOT" 2>&1)
  status=$?
  if ! kill -0 "$bgpid" 2>/dev/null; then
    wait "$bgpid" 2>/dev/null || true
    fail "the SIGKILL escalation signaled a pid the exact pane no longer owns"
  fi
  kill -KILL "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  [ "$status" -eq 0 ] || fail "the refused escalation should fall back to the plain close: $out"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw2:p2' "the refused escalation did not fall back to the plain close"
  pass "herdr presentation cleanup: SIGKILL never reaches a pid the exact pane no longer owns"
}

assert_projection_close_failed_removal_rolls_back_the_reposition() {
  local mode=$1 dir log resp fb out status bgpid
  dir="$TMP_ROOT/close-move-rollback-$mode"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Doomed w1 sits BEFORE the focused w2 (not last): the plan repositions it
  # to the end; then every removal path fails, so the exact original order
  # must be restored under the same session lock and the close must fail.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","workspace_id":"w1"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  printf '%s\n' '{"client":{"version":"0.7.5","protocol":16},"server":{"running":true}}' > "$resp/7.out"
  # shellcheck disable=SC2016 # $defs is a literal JSON Schema key.
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/8.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/9.out"
  bash -c 'trap "" HUP; sleep 300' & bgpid=$!
  death_process_info_fixture w1:p1 "$bgpid" > "$resp/10.out"
  if [ "$mode" = pane-gone-workspace-present ]; then
    printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/11.out"
    printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false},{"workspace_id":"w1","active_tab_id":"w1:t2","focused":false}]}}' > "$resp/12.out"
    printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t2","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/13.out"
    printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/14.out"
  else
    cp "$resp/3.out" "$resp/11.out"  # SIGHUP poll 1: pane still present
    cp "$resp/3.out" "$resp/12.out"  # SIGHUP poll 2: pane still present
    death_process_info_fixture w1:p1 "$bgpid" > "$resp/13.out"  # escalation resample: same owner
    cp "$resp/3.out" "$resp/14.out"  # SIGKILL poll 1: pane still present
    cp "$resp/3.out" "$resp/15.out"  # SIGKILL poll 2: pane still present
  fi
  if [ "$mode" = command-fails ]; then
    printf '9\n' > "$resp/16.exit"
    printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/17.out"
    printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/18.out"
  else
    : > "$resp/16.out"
    cp "$resp/3.out" "$resp/17.out"
    printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t1","focused":true},{"workspace_id":"w3","active_tab_id":"w3:t1","focused":false}]}}' > "$resp/18.out"
    printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t1","focused":true}]}}' > "$resp/19.out"
  fi
  make_death_lab "$dir" "$bgpid"
  printf '%s\n' '{"id":"fm-workspace-move","result":{"type":"workspace_list","workspaces":[{"workspace_id":"w2","focused":true},{"workspace_id":"w3","focused":false},{"workspace_id":"w1","focused":false}]}}' > "$dir/mover-response"
  printf '%s\n' '{"id":"fm-workspace-move","result":{"type":"workspace_list","workspaces":[{"workspace_id":"w1","focused":false},{"workspace_id":"w2","focused":true},{"workspace_id":"w3","focused":false}]}}' > "$dir/mover-response-2"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/mover-response" \
    FM_FAKE_MOVER_RESPONSE_2="$dir/mover-response-2" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_close_pane_focus_preserving fmtest w1:p1' "$ROOT" 2>&1)
  status=$?
  kill -KILL "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  [ "$status" -ne 0 ] || fail "an unconfirmed removal must report failure: $out"
  [ "$(wc -l < "$dir/mover.log" | tr -d ' ')" = 2 ] \
    || fail "a failed removal did not roll the reposition back exactly once: $(cat "$dir/mover.log")"
  [ "$(sed -n '1p' "$dir/mover.log")" = "$(cd /tmp && pwd -P)/fmtest.sock"$'\t'"w1"$'\t'"3" ] \
    || fail "the reposition did not move the doomed workspace to the end: $(sed -n '1p' "$dir/mover.log")"
  [ "$(sed -n '2p' "$dir/mover.log")" = "$(cd /tmp && pwd -P)/fmtest.sock"$'\t'"w1"$'\t'"0" ] \
    || fail "the rollback did not restore the doomed workspace to its exact original position: $(sed -n '2p' "$dir/mover.log")"
  assert_not_contains "$(cat "$log")" $'tab\x1ffocus' "a failed rolled-back removal moved focus"
}

test_projection_close_failed_removal_rolls_back_the_reposition() {
  assert_projection_close_failed_removal_rolls_back_the_reposition command-fails
  assert_projection_close_failed_removal_rolls_back_the_reposition command-succeeds-pane-present
  assert_projection_close_failed_removal_rolls_back_the_reposition pane-gone-workspace-present
  pass "herdr presentation cleanup: every unconfirmed removal restores the exact original workspace order and reports failure"
}

test_kill_emptying_non_focused_uses_pane_death() {
  local dir log resp fb out status bgpid lock_log lock_held
  dir="$TMP_ROOT/kill-death"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; lock_log="$dir/lock.log"; lock_held="$dir/lock-held"
  : > "$log"; : > "$lock_log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","workspace_id":"w2"}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/5.out"
  cp "$resp/1.out" "$resp/6.out"
  sleep 300 & bgpid=$!
  death_process_info_fixture w2:p2 "$bgpid" > "$resp/7.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/8.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":true}]}}' > "$resp/9.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/10.out"
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 FM_FAKE_LOCK_LOG="$lock_log" \
    FM_FAKE_LOCK_HELD="$lock_held" \
    bash -c '
      . "$0/bin/fm-herdr.sh"
      fm_herdr_target_ready() { fm_herdr_parse_target "$1"; }
      fm_herdr_presentation_session_lock_path() { printf "%s" "$FM_FAKE_LOCK_HELD.lock"; }
      fm_lock_try_acquire() {
        printf "acquire\n" >> "$FM_FAKE_LOCK_LOG"
        : > "$FM_FAKE_LOCK_HELD"
      }
      fm_lock_release() {
        [ -e "$FM_FAKE_LOCK_HELD" ] || return 1
        rm -f "$FM_FAKE_LOCK_HELD"
        printf "release\n" >> "$FM_FAKE_LOCK_LOG"
      }
      eval "$(declare -f fm_herdr_cli | sed "1s/fm_herdr_cli/fm_herdr_cli_locked/")"
      fm_herdr_cli() {
        [ -e "$FM_FAKE_LOCK_HELD" ] || return 97
        fm_herdr_cli_locked "$@"
      }
      fm_herdr_kill fmtest:w2:p2
    ' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "an emptying non-focused kill should stay best-effort: $out"
  [ "$(cat "$lock_log")" = "$(printf 'acquire\nrelease')" ] \
    || fail "the generic kill did not hold one presentation lock across its complete mutation: $(cat "$lock_log")"
  [ ! -e "$lock_held" ] || fail "the generic kill retained its presentation lock"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "an emptying non-focused kill used the focus-unsafe explicit close"
  assert_not_contains "$(cat "$log")" $'tab\x1ffocus' "an emptying non-focused kill moved focus"
  pass "fm_herdr_kill: one session lock covers the focus-safe emptying removal"
}

test_kill_focused_workspace_stays_plain_close() {
  local dir log resp fb out status bgpid
  dir="$TMP_ROOT/kill-focused"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","active_tab_id":"w1:t1","focused":false},{"workspace_id":"w2","active_tab_id":"w2:t2","focused":true}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","focused":true}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/3.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/5.out"
  sleep 300 & bgpid=$!
  make_death_lab "$dir" "$bgpid"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_PS_BIN="$dir/ps" FM_HERDR_WORKSPACE_MOVER="$dir/mover" \
    FM_FAKE_MOVER_LOG="$dir/mover.log" FM_FAKE_MOVER_RESPONSE="$dir/no-response" \
    FM_HERDR_DEATH_CLOSE_POLLS=2 \
    bash -c '
      . "$0/bin/fm-herdr.sh"
      fm_herdr_presentation_session_lock_path() { printf "/tmp/fm-herdr-test-lock"; }
      fm_lock_try_acquire() { return 0; }
      fm_lock_release() { return 0; }
      fm_herdr_kill fmtest:w2:p2
    ' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "a focused-workspace kill should stay best-effort: $out"
  assert_contains "$(cat "$log")" $'pane\x1fclose\x1fw2:p2' "a focused-workspace kill did not use the plain close"
  assert_not_contains "$(cat "$log")" $'pane\x1fprocess-info' "a focused-workspace kill ran the idle-shell proof"
  kill -0 "$bgpid" 2>/dev/null || fail "a focused-workspace kill signaled the pane's shell"
  kill "$bgpid" 2>/dev/null || true; wait "$bgpid" 2>/dev/null || true
  pass "fm_herdr_kill: killing the focused workspace's tab keeps the legitimate plain close"
}

test_kill_refuses_when_presentation_lock_is_unavailable() {
  local dir mode out status attempts
  dir="$TMP_ROOT/kill-lock-refusal"; mkdir -p "$dir"
  for mode in unresolved contended; do
    : > "$dir/cli.log"
    : > "$dir/attempts"
    out=$(ROOT="$ROOT" MODE="$mode" CLI_LOG="$dir/cli.log" ATTEMPTS="$dir/attempts" bash -c '
      . "$ROOT/bin/fm-herdr.sh"
      fm_herdr_target_ready() { fm_herdr_parse_target "$1"; }
      fm_herdr_presentation_session_lock_path() {
        [ "$MODE" = contended ] || return 1
        printf "/tmp/fm-herdr-contended-test-lock"
      }
      fm_lock_try_acquire() {
        printf "x\n" >> "$ATTEMPTS"
        return 1
      }
      fm_herdr_cli() {
        printf "%s\n" "$*" >> "$CLI_LOG"
        return 0
      }
      sleep() { :; }
      fm_herdr_kill fmtest:w2:p2
    ' 2>&1)
    status=$?
    [ "$status" -eq 0 ] || fail "$mode presentation lock refusal changed best-effort kill status: $status"
    [ ! -s "$dir/cli.log" ] || fail "$mode presentation lock refusal still mutated Herdr: $(cat "$dir/cli.log")"
    assert_contains "$out" "refusing an unlocked pane close" \
      "$mode presentation lock refusal did not report the deferred close"
    attempts=$(wc -l < "$dir/attempts" | tr -d ' ')
    if [ "$mode" = contended ]; then
      [ "$attempts" = 50 ] || fail "contended presentation lock did not use the bounded wait: $attempts attempts"
    else
      [ "$attempts" = 0 ] || fail "unresolved presentation lock path attempted acquisition: $attempts"
    fi
  done
  pass "fm_herdr_kill: unavailable session locks defer every pane close"
}

test_endpoint_confirmed_gone_gates_on_structured_presence() {
  local out
  out=$(bash -c '
    . "$0/bin/fm-herdr.sh"
    fm_herdr_cli() { printf "%s\n" "$FM_FAKE_PRESENCE_RESPONSE"; return "${FM_FAKE_PRESENCE_STATUS:-0}"; }
    check() {  # <label> <response> <status> <mode> <expected-rc>
      FM_FAKE_PRESENCE_RESPONSE=$2 FM_FAKE_PRESENCE_STATUS=$3
      rc=0
      fm_herdr_endpoint_confirmed_gone fmtest:w2:p2 "$4" || rc=$?
      [ "$rc" = "$5" ] || printf "MISMATCH %s: rc=%s expected=%s\n" "$1" "$rc" "$5"
    }
    check present-default "{\"result\":{\"pane\":{\"pane_id\":\"w2:p2\"}}}" 0 "" 1
    check present-strict "{\"result\":{\"pane\":{\"pane_id\":\"w2:p2\"}}}" 0 strict 1
    check notfound-default "{\"error\":{\"code\":\"pane_not_found\"}}" 1 "" 0
    check notfound-strict "{\"error\":{\"code\":\"pane_not_found\"}}" 1 strict 0
    check unknown-default "" 1 "" 1
    check unknown-strict "" 1 strict 1
    check othererror-default "{\"error\":{\"code\":\"internal\"}}" 1 "" 1
    check othererror-strict "{\"error\":{\"code\":\"internal\"}}" 1 strict 1
    # Missing or malformed endpoint identity is ambiguity, never proof of a
    # gone pane: it must refuse record removal.
    rc=0
    fm_herdr_endpoint_confirmed_gone malformed-target strict || rc=$?
    [ "$rc" = 1 ] || printf "MISMATCH malformed-target: rc=%s expected=1\n" "$rc"
    rc=0
    fm_herdr_endpoint_confirmed_gone "" || rc=$?
    [ "$rc" = 1 ] || printf "MISMATCH empty-target: rc=%s expected=1\n" "$rc"
  ' "$ROOT" 2>&1)
  [ -z "$out" ] || fail "endpoint confirmed-gone gate matrix mismatch: $out"
  pass "endpoint confirmed-gone: only structured not-found permits record removal and ambiguous identity refuses"
}

test_projection_seeded_prune_refuses_active_tab() {
  local dir log resp fb out status
  dir="$TMP_ROOT/projection-seeded-focus-active-refusal"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w9:t1","label":"1","workspace_id":"w9","focused":true},{"tab_id":"w9:t2","label":"fm-task","workspace_id":"w9","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w9:p1","tab_id":"w9:t1"},{"pane_id":"w9:p2","tab_id":"w9:t2"}]}}' > "$resp/2.out"
  printf '%s\n' '{"error":{"code":"agent_not_found"}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w9","active_tab_id":"w9:t1","focused":true}]}}' > "$resp/4.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w9:t1","focused":true},{"tab_id":"w9:t2","focused":false}]}}' > "$resp/5.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w9:p1","tab_id":"w9:t1","workspace_id":"w9"}}}' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_prune_seeded_default_tab fmtest w9 w9:t1 focus-preserving' "$ROOT" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "projected seeded pruning must refuse the active tab"
  assert_contains "$out" "target is the captain's active tab" \
    "projected seeded prune did not explain its active-tab refusal"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' \
    "projected seeded prune closed the captain's active tab"
  pass "herdr presentation focus: projected seeded pruning refuses the active tab"
}

test_projection_label_builder_uses_corner_and_strips_owner_prefixes() {
  local primary secondmate token
  token='AbCdEfGhIjKlMnOpQrStUv'
  [ "${#token}" -eq 22 ] || fail "fixture token must be 22 characters"
  primary=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_workspace_label task-p2 '"$token" "$ROOT")
  [ "$primary" = "└ task-p2 · p:$token" ] \
    || fail "primary child label was wrong: $primary"
  secondmate=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_workspace_label secondmate-child-demo '"$token" "$ROOT")
  [ "$secondmate" = "└ secondmate-child-demo · p:$token" ] \
    || fail "secondmate child label was wrong: $secondmate"
  primary=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_workspace_label firstmate/task-p2 '"$token" "$ROOT")
  [ "$primary" = "└ task-p2 · p:$token" ] \
    || fail "firstmate/ owner prefix was not stripped: $primary"
  secondmate=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_workspace_label 2ndmate-fmdev-f2/child '"$token" "$ROOT")
  [ "$secondmate" = "└ child · p:$token" ] \
    || fail "2ndmate owner prefix was not stripped: $secondmate"
  primary=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_workspace_label fm-task-p2 '"$token" "$ROOT")
  [ "$primary" = "└ task-p2 · p:$token" ] \
    || fail "presentation fm- owner prefix was not stripped: $primary"
  case "$primary" in $'└ '*) ;; *) fail "label must start with U+2514 and one space" ;; esac
  pass "herdr presentation labels: └ concise-task · p:<full-token> for primary and secondmate children"
}

test_projection_order_moves_only_exact_new_workspace_and_preserves_relative_order() {
  local dir log resp fb mover mover_log out status
  dir="$TMP_ROOT/projection-order"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; mover_log="$dir/mover.log"
  : > "$log"; : > "$mover_log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate","focused":false},{"workspace_id":"w2","label":"firstmate/old · p:AbCdEfGhIjKlMnOpQrStUv","focused":false},{"workspace_id":"w3","label":"2ndmate-alpha","focused":false},{"workspace_id":"w4","label":"2ndmate-bravo","focused":true},{"workspace_id":"w5","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"client":{"version":"0.7.4","protocol":16},"server":{"running":true}}' > "$resp/2.out"
  # shellcheck disable=SC2016 # $defs is a literal JSON Schema key.
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/3.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/4.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FM_FAKE_MOVER_LOG"
printf '%s\n' '{"id":"fm-workspace-move","result":{"type":"workspace_list","workspaces":[{"workspace_id":"w1","label":"firstmate","focused":false},{"workspace_id":"w2","label":"firstmate/old · p:AbCdEfGhIjKlMnOpQrStUv","focused":false},{"workspace_id":"w5","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe","focused":false},{"workspace_id":"w3","label":"2ndmate-alpha","focused":false},{"workspace_id":"w4","label":"2ndmate-bravo","focused":true}]}}'
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_LOG="$mover_log" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_focus_snapshot() { printf "w4\tw4:t2"; }; fm_herdr_projection_focus_restore() { return 0; }; fm_herdr_projection_order_best_effort fmtest w5 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "best-effort projection ordering must not fail the spawn"
  [ -z "$out" ] || fail "successful projection ordering emitted a warning: $out"
  [ "$(cat "$mover_log")" = "$(cd /tmp && pwd -P)/fmtest.sock"$'\t'"w5"$'\t'"2" ] \
    || fail "projection ordering did not move only the exact new response id to the owning-parent append index"
  assert_not_contains "$(cat "$log")" $'workspace\x1fclose' "projection ordering called workspace close"
  assert_not_contains "$(cat "$log")" $'session\x1fdelete' "projection ordering called session delete"
  assert_not_contains "$(cat "$log")" $'workspace\x1frename' "projection ordering called a label-based workspace mutation"
  pass "herdr presentation ordering: exact new workspace appends to the primary block while focus and relative orders stay stable"
}

test_projection_order_secondmate_parent_block() {
  local dir log resp fb mover mover_log out status
  dir="$TMP_ROOT/projection-order-secondmate"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; mover_log="$dir/mover.log"
  : > "$log"; : > "$mover_log"
  # firstmate, primary child, 2ndmate-A, A-child legacy, 2ndmate-B, human, NEW for A
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"└ primary · p:AbCdEfGhIjKlMnOpQrStUv"},{"workspace_id":"w3","label":"2ndmate-alpha"},{"workspace_id":"w4","label":"2ndmate-alpha/old · p:AbCdEfGhIjKlMnOpQrStU1"},{"workspace_id":"w5","label":"2ndmate-bravo"},{"workspace_id":"wH","label":"human-notes"},{"workspace_id":"w6","label":"└ new-a · p:ZyXwVuTsRqPoNmLkJiHgFe"}]}}' > "$resp/1.out"
  printf '%s\n' '{"client":{"version":"0.7.4","protocol":16},"server":{"running":true}}' > "$resp/2.out"
  # shellcheck disable=SC2016
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/3.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/4.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FM_FAKE_MOVER_LOG"
printf '%s\n' '{"id":"fm-workspace-move","result":{"type":"workspace_list","workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"└ primary · p:AbCdEfGhIjKlMnOpQrStUv"},{"workspace_id":"w3","label":"2ndmate-alpha"},{"workspace_id":"w4","label":"2ndmate-alpha/old · p:AbCdEfGhIjKlMnOpQrStU1"},{"workspace_id":"w6","label":"└ new-a · p:ZyXwVuTsRqPoNmLkJiHgFe"},{"workspace_id":"w5","label":"2ndmate-bravo"},{"workspace_id":"wH","label":"human-notes"}]}}'
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_LOG="$mover_log" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_focus_snapshot() { printf "w5\tw5:t1"; }; fm_herdr_projection_focus_restore() { return 0; }; fm_herdr_projection_order_best_effort fmtest w6 2ndmate-alpha' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "secondmate parent ordering must not fail the spawn: $out"
  [ -z "$out" ] || fail "successful secondmate ordering emitted a warning: $out"
  [ "$(cat "$mover_log")" = "$(cd /tmp && pwd -P)/fmtest.sock"$'\t'"w6"$'\t'"4" ] \
    || fail "secondmate child was not inserted after its parent block: $(cat "$mover_log")"
  assert_not_contains "$(cat "$log")" $'workspace\x1frename' "secondmate ordering renamed a legacy child"
  pass "herdr presentation ordering: secondmate children append under their owning parent block"
}

test_projection_order_foreign_legacy_child_is_read_only() {
  local dir log resp fb mover out status
  dir="$TMP_ROOT/projection-order-foreign-legacy"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"2ndmate-alpha"},{"workspace_id":"w3","label":"2ndmate-bravo/foreign · p:AbCdEfGhIjKlMnOpQrStUv"},{"workspace_id":"w4","label":"└ new-alpha · p:ZyXwVuTsRqPoNmLkJiHgFe"}]}}' > "$resp/1.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
echo called > "$FM_FAKE_MOVER_CALLED"
exit 0
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_CALLED="$dir/called" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_order_best_effort fmtest w4 2ndmate-alpha' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "foreign legacy ordering must not fail the spawn"
  assert_contains "$out" "ambiguous workspace layout" "foreign legacy child did not warn"
  [ ! -e "$dir/called" ] || fail "foreign legacy child attempted workspace.move"
  assert_not_contains "$(cat "$log")" $'workspace\x1fclose' "foreign legacy layout triggered workspace cleanup"
  assert_not_contains "$(cat "$log")" $'session\x1fdelete' "foreign legacy layout triggered session cleanup"
  assert_not_contains "$(cat "$log")" $'workspace\x1frename' "foreign legacy layout triggered workspace rename"
  pass "herdr presentation ordering: a foreign legacy child is warning-only and read-only"
}

test_projection_order_allows_intervening_parent_child_block() {
  local dir log resp fb mover mover_log out status
  dir="$TMP_ROOT/projection-order-intervening-parent"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; mover_log="$dir/mover.log"
  : > "$log"; : > "$mover_log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"firstmate/old · p:AbCdEfGhIjKlMnOpQrStUv"},{"workspace_id":"w3","label":"2ndmate-alpha"},{"workspace_id":"w4","label":"2ndmate-bravo"},{"workspace_id":"w5","label":"└ bravo-child · p:QqWwEeRrTtYyUuIiOoPpAa"},{"workspace_id":"w6","label":"└ new-first · p:ZyXwVuTsRqPoNmLkJiHgFe"}]}}' > "$resp/1.out"
  printf '%s\n' '{"client":{"version":"0.7.4","protocol":16},"server":{"running":true}}' > "$resp/2.out"
  # shellcheck disable=SC2016
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/3.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/4.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FM_FAKE_MOVER_LOG"
printf '%s\n' '{"id":"fm-workspace-move","result":{"type":"workspace_list","workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"firstmate/old · p:AbCdEfGhIjKlMnOpQrStUv"},{"workspace_id":"w6","label":"└ new-first · p:ZyXwVuTsRqPoNmLkJiHgFe"},{"workspace_id":"w3","label":"2ndmate-alpha"},{"workspace_id":"w4","label":"2ndmate-bravo"},{"workspace_id":"w5","label":"└ bravo-child · p:QqWwEeRrTtYyUuIiOoPpAa"}]}}'
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_LOG="$mover_log" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_focus_snapshot() { printf "w4\tw4:t1"; }; fm_herdr_projection_focus_restore() { return 0; }; fm_herdr_projection_order_best_effort fmtest w6 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "intervening parent ordering must not fail the spawn: $out"
  [ -z "$out" ] || fail "legitimate intervening parent ordering emitted a warning: $out"
  [ "$(cat "$mover_log")" = "$(cd /tmp && pwd -P)/fmtest.sock"$'\t'"w6"$'\t'"2" ] \
    || fail "intervening parent block prevented the owning-parent insertion: $(cat "$mover_log")"
  pass "herdr presentation ordering: intervening parent child blocks remain traversable"
}

test_projection_order_human_spaces_never_move_targets() {
  local dir log resp fb mover mover_log out status
  dir="$TMP_ROOT/projection-order-human"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; mover_log="$dir/mover.log"
  : > "$log"; : > "$mover_log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"wH1","label":"notes"},{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"wH2","label":"scratch"},{"workspace_id":"w2","label":"2ndmate-alpha"},{"workspace_id":"w3","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe"}]}}' > "$resp/1.out"
  printf '%s\n' '{"client":{"version":"0.7.4","protocol":16},"server":{"running":true}}' > "$resp/2.out"
  # shellcheck disable=SC2016
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/3.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/4.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FM_FAKE_MOVER_LOG"
printf '%s\n' '{"id":"fm-workspace-move","result":{"type":"workspace_list","workspaces":[{"workspace_id":"wH1","label":"notes"},{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w3","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe"},{"workspace_id":"wH2","label":"scratch"},{"workspace_id":"w2","label":"2ndmate-alpha"}]}}'
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_LOG="$mover_log" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_focus_snapshot() { printf "w2\tw2:t1"; }; fm_herdr_projection_focus_restore() { return 0; }; fm_herdr_projection_order_best_effort fmtest w3 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "human-interleaved ordering must not fail: $out"
  [ "$(cat "$mover_log")" = "$(cd /tmp && pwd -P)/fmtest.sock"$'\t'"w3"$'\t'"2" ] \
    || fail "human spaces changed the move target or insert index: $(cat "$mover_log")"
  pass "herdr presentation ordering: only the exact new id moves; human spaces keep relative order"
}

test_projection_order_failure_warns_without_cleanup_or_spawn_failure() {
  local dir log resp fb mover out status
  dir="$TMP_ROOT/projection-order-failure"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate","focused":true},{"workspace_id":"w2","label":"2ndmate-alpha","focused":false},{"workspace_id":"w3","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe","focused":false}]}}' > "$resp/1.out"
  printf '%s\n' '{"client":{"version":"0.7.4","protocol":16},"server":{"running":true}}' > "$resp/2.out"
  # shellcheck disable=SC2016 # $defs is a literal JSON Schema key.
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/3.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":"/tmp/fmtest.sock"}]}' > "$resp/4.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
exit 9
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_WORKSPACE_MOVER="$mover" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_focus_snapshot() { printf "w1\tw1:t1"; }; fm_herdr_projection_focus_restore() { return 0; }; fm_herdr_projection_order_best_effort fmtest w3 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "a workspace.move failure must not fail the projected spawn"
  assert_contains "$out" "workspace move failed or had an ambiguous response" \
    "workspace.move failure did not report the best-effort warning"
  assert_not_contains "$(cat "$log")" $'workspace\x1fclose' "workspace.move failure triggered workspace cleanup"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "workspace.move failure triggered pane cleanup"
  assert_not_contains "$(cat "$log")" $'session\x1fdelete' "workspace.move failure triggered session cleanup"
  pass "herdr presentation ordering: move failure warns, returns success, and grants no cleanup authority"
}

test_projection_order_ambiguous_existing_block_is_read_only() {
  local dir log resp fb mover out status
  dir="$TMP_ROOT/projection-order-ambiguous"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  # Detached legacy child after the next parent breaks the contiguous block.
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate","focused":true},{"workspace_id":"w2","label":"2ndmate-alpha","focused":false},{"workspace_id":"w3","label":"firstmate/old · p:AbCdEfGhIjKlMnOpQrStUv","focused":false},{"workspace_id":"w4","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe","focused":false}]}}' > "$resp/1.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
echo called > "$FM_FAKE_MOVER_CALLED"
exit 0
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_CALLED="$dir/called" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_order_best_effort fmtest w4 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "ambiguous projection ordering must not fail the spawn"
  assert_contains "$out" "ambiguous workspace layout" "ambiguous projection layout did not warn"
  [ ! -e "$dir/called" ] || fail "ambiguous projection layout attempted workspace.move"
  [ "$(wc -l < "$log" | tr -d '[:space:]')" = 1 ] \
    || fail "ambiguous projection ordering did more than one read-only workspace list"
  pass "herdr presentation ordering: an ambiguous existing worker block is warning-only and read-only"
}

test_projection_order_anchors_the_parent_by_exact_id() {
  local dir log resp fb mover layout out status
  layout='{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate","focused":false},{"workspace_id":"w7","label":"firstmate","focused":false},{"workspace_id":"wH","label":"human-notes","focused":false},{"workspace_id":"w8","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe","focused":false}]}}'

  # Without the exact parent id, two same-labeled parents make the whole layout
  # ambiguous and ordering steps aside.
  dir="$TMP_ROOT/projection-order-dup-label"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  printf '%s\n' "$layout" > "$resp/1.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
echo called > "$FM_FAKE_MOVER_CALLED"
exit 0
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_CALLED="$dir/called" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_order_best_effort fmtest w8 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "ambiguous projection ordering must not fail the spawn"
  assert_contains "$out" "ambiguous workspace layout" "a duplicated parent label should make label-anchored ordering step aside"
  [ ! -e "$dir/called" ] || fail "ambiguous parent label attempted workspace.move"

  # With the launcher's exact parent workspace id, the same layout is no longer
  # ambiguous: ordering gets past parent selection and stops later, on this
  # fake's protocol, having still moved nothing.
  dir="$TMP_ROOT/projection-order-exact-parent"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  printf '%s\n' "$layout" > "$resp/1.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
echo called > "$FM_FAKE_MOVER_CALLED"
exit 0
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_CALLED="$dir/called" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_order_best_effort fmtest w8 firstmate w7' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "exact-parent projection ordering must not fail the spawn"
  assert_not_contains "$out" "ambiguous workspace layout" "the exact parent id should have resolved the duplicated label"
  assert_contains "$out" "protocol" "exact-parent ordering did not reach its protocol gate"
  [ ! -e "$dir/called" ] || fail "exact-parent ordering attempted workspace.move below the required protocol"
  pass "herdr presentation ordering: the launcher's exact parent workspace id disambiguates a duplicated home label without moving anything"
}

test_projection_order_foreign_new_child_before_parent_is_read_only() {
  local dir log resp fb mover out status
  dir="$TMP_ROOT/projection-order-foreign-new"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate","focused":true},{"workspace_id":"wH","label":"human-notes","focused":false},{"workspace_id":"w2","label":"└ foreign · p:AbCdEfGhIjKlMnOpQrStUv","focused":false},{"workspace_id":"w3","label":"2ndmate-alpha","focused":false},{"workspace_id":"w4","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe","focused":false}]}}' > "$resp/1.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
echo called > "$FM_FAKE_MOVER_CALLED"
exit 0
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_CALLED="$dir/called" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_order_best_effort fmtest w4 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "foreign new-child ordering must not fail the spawn"
  assert_contains "$out" "ambiguous workspace layout" "foreign new child before its parent did not warn"
  [ ! -e "$dir/called" ] || fail "foreign new child before its parent attempted workspace.move"
  [ "$(wc -l < "$log" | tr -d '[:space:]')" = 1 ] \
    || fail "foreign new-child ordering did more than one read-only workspace list"
  pass "herdr presentation ordering: a foreign new-format child is warning-only and read-only"
}

test_projection_order_missing_parent_is_read_only() {
  local dir log resp fb mover out status
  dir="$TMP_ROOT/projection-order-missing-parent"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe"}]}}' > "$resp/1.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
echo called > "$FM_FAKE_MOVER_CALLED"
exit 0
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_CALLED="$dir/called" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_order_best_effort fmtest w2 2ndmate-missing' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "missing parent must not fail the spawn"
  assert_contains "$out" "ambiguous workspace layout" "missing parent did not warn"
  [ ! -e "$dir/called" ] || fail "missing parent attempted workspace.move"
  pass "herdr presentation ordering: missing owning parent is warning-only and read-only"
}

test_presentation_session_lock_path_is_shared_across_homes() {
  local dir log resp fb path_a path_b path_restarted path_other path_tmp path_private
  dir="$TMP_ROOT/presentation-session-lock"; mkdir -p "$dir/responses" "$dir/sockdir"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  : > "$dir/sockdir/fmtest.sock"
  printf '%s\n' "{\"sessions\":[{\"name\":\"fmtest\",\"running\":true,\"socket_path\":\"$dir/sockdir/fmtest.sock\"}]}" > "$resp/1.out"
  printf '%s\n' "{\"sessions\":[{\"name\":\"fmtest\",\"running\":true,\"socket_path\":\"$dir/sockdir/fmtest.sock\"}]}" > "$resp/2.out"
  printf '%s\n' "{\"sessions\":[{\"name\":\"fmtest\",\"running\":true,\"socket_path\":\"$dir/sockdir/fmtest-restarted.sock\"}]}" > "$resp/3.out"
  printf '%s\n' "{\"sessions\":[{\"name\":\"other\",\"running\":true,\"socket_path\":\"$dir/sockdir/other.sock\"}]}" > "$resp/4.out"
  : > "$dir/sockdir/fmtest-restarted.sock"
  : > "$dir/sockdir/other.sock"
  fb=$(make_herdr_fakebin "$dir")
  path_a=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path fmtest' "$ROOT") \
    || fail "session lock path resolution failed for home A"
  path_b=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path fmtest' "$ROOT") \
    || fail "session lock path resolution failed for home B"
  [ "$path_a" = "$path_b" ] || fail "same named session must resolve one shared lock path"
  path_restarted=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path fmtest' "$ROOT") \
    || fail "session lock path resolution failed after socket replacement"
  [ "$path_restarted" = "$path_a" ] || fail "a named session restart split its shared lock path"
  case "$path_a" in
    /tmp/firstmate-herdr-presentation/order-*.lock) ;;
    *) fail "session lock path must use the shared machine namespace: $path_a" ;;
  esac
  case "$path_a" in
    */state/*) fail "session lock path must not live under a home state directory: $path_a" ;;
  esac
  path_other=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path other' "$ROOT") \
    || fail "session lock path resolution failed for a different session"
  [ "$path_other" != "$path_a" ] || fail "different sessions must not share one lock path"
  # Symlink parents such as /tmp -> /private/tmp must not split the lock identity.
  if [ -L /tmp ] || [ "$(cd /tmp && pwd -P)" != /tmp ]; then
    : > /tmp/fm-herdr-lock-canon-$$.sock
    printf '%s\n' '{"sessions":[{"name":"canon","running":true,"socket_path":"/tmp/fm-herdr-lock-canon-'"$$"'.sock"}]}' > "$resp/5.out"
    printf '%s\n' "{\"sessions\":[{\"name\":\"canon\",\"running\":true,\"socket_path\":\"$(cd /tmp && pwd -P)/fm-herdr-lock-canon-$$.sock\"}]}" > "$resp/6.out"
    path_tmp=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
      bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path canon' "$ROOT") \
      || fail "lock path with /tmp socket failed"
    path_private=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
      bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path canon' "$ROOT") \
      || fail "lock path with canonical socket failed"
    rm -f /tmp/fm-herdr-lock-canon-$$.sock
    [ "$path_tmp" = "$path_private" ] \
      || fail "symlink parent socket paths must resolve one lock: $path_tmp vs $path_private"
  fi
  pass "herdr presentation lock: one stable path per named session across homes"
}

test_presentation_session_lock_path_rejects_malformed_socket() {
  local dir log resp fb path status
  dir="$TMP_ROOT/presentation-malformed-socket"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":null}]}' > "$resp/1.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true}]}' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  path=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path fmtest' "$ROOT" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "null socket_path must refuse the presentation lock path"
  [ -z "$path" ] || fail "null socket_path returned a lock path: $path"
  case "$path" in *null*) fail "null socket_path leaked into a lock path: $path" ;; esac
  path=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_presentation_session_lock_path fmtest' "$ROOT" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "missing socket_path must refuse the presentation lock path"
  [ -z "$path" ] || fail "missing socket_path returned a lock path: $path"
  pass "herdr presentation lock: null and missing socket paths fail closed"
}

test_projection_order_rejects_malformed_socket() {
  local dir log resp fb mover out status
  dir="$TMP_ROOT/projection-order-malformed-socket"; mkdir -p "$dir/responses"
  log="$dir/log"; resp="$dir/responses"; mover="$dir/mover"; : > "$log"
  printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"wH","label":"2ndmate-alpha"},{"workspace_id":"w2","label":"└ new · p:ZyXwVuTsRqPoNmLkJiHgFe"}]}}' > "$resp/1.out"
  printf '%s\n' '{"client":{"version":"0.7.4","protocol":16},"server":{"running":true}}' > "$resp/2.out"
  # shellcheck disable=SC2016
  printf '%s\n' '{"schemas":{"request":{"oneOf":[{"properties":{"method":{"const":"workspace.move"}}}],"$defs":{"WorkspaceMoveParams":{"required":["workspace_id","insert_index"],"properties":{"insert_index":{"type":"integer"}}}}}}}' > "$resp/3.out"
  printf '%s\n' '{"sessions":[{"name":"fmtest","running":true,"socket_path":null}]}' > "$resp/4.out"
  cat > "$mover" <<'SH'
#!/usr/bin/env bash
echo called > "$FM_FAKE_MOVER_CALLED"
exit 0
SH
  chmod +x "$mover"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SCRIPT_STATUS=1 \
    FM_HERDR_WORKSPACE_MOVER="$mover" FM_FAKE_MOVER_CALLED="$dir/called" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_order_best_effort fmtest w2 firstmate' "$ROOT" 2>&1)
  status=$?
  [ "$status" -eq 0 ] || fail "malformed ordering socket must not fail the spawn"
  assert_contains "$out" "ambiguous named session socket" "malformed ordering socket did not warn"
  [ ! -e "$dir/called" ] || fail "malformed ordering socket attempted workspace.move"
  pass "herdr presentation ordering: malformed socket metadata is warning-only and read-only"
}

test_projection_reclaim_refusal_matrix_is_non_mutating() {
  local dir state home other_home home_real journal legacy token label out mutation_log
  dir="$TMP_ROOT/projection-reclaim-refusals"; state="$dir/state"; home="$dir/home"; other_home="$dir/other-home"
  mkdir -p "$state" "$home" "$other_home"
  home_real=$(cd "$home" && pwd -P)
  token=$(bash -c '
    . "$0/bin/fm-herdr.sh"
    token=$(fm_herdr_projection_journal_create "$1" refusal-r1) || exit 1
    label=$(fm_herdr_projection_workspace_label refusal-r1 "$token")
    fm_herdr_projection_journal_bind \
      "$1/refusal-r1.herdr-presentation" refusal-r1 "$2" fmtest \
      w2 w2:t2 w2:p2 w1 firstmate "$label" fm-refusal-r1 || exit 1
    printf "%s" "$token"
  ' "$ROOT" "$state" "$home_real") || fail "could not create reclaim refusal fixture"
  journal="$state/refusal-r1.herdr-presentation"
  label="└ refusal-r1 · p:$token"
  mkdir -p "$state/legacy"
  bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_journal_create "$1" refusal-r1 >/dev/null' \
    "$ROOT" "$state/legacy" || fail "could not create legacy reclaim fixture"
  legacy="$state/legacy/refusal-r1.herdr-presentation"
  mutation_log="$dir/mutations.log"; : > "$mutation_log"
  out=$(ROOT="$ROOT" JOURNAL="$journal" LEGACY="$legacy" HOME_A="$home" HOME_B="$other_home" MUTATIONS="$mutation_log" \
    bash -c '
      . "$ROOT/bin/fm-herdr.sh"
      fm_herdr_cli() { printf "%s\n" "$*" >> "$MUTATIONS"; return 1; }
      run_case() {
        mode=$1; journal=$2; home=$3
        fm_herdr_projection_live_binding_matches() {
          [ "$mode" != ambiguous ]
        }
        fm_herdr_pane_agent_state() {
          case "$mode" in
            live) printf live ;;
            unknown) printf unknown ;;
            *) printf no-agent ;;
          esac
        }
        fm_herdr_projection_focus_snapshot() {
          [ "$mode" != focus-unknown ] || return 1
          printf "w1\tw1:t1"
        }
        set +e
        fm_herdr_projection_reclaim_task \
          fmtest "$journal" refusal-r1 "$home" w2 w2:t2 w2:p2 firstmate fm-refusal-r1 /tmp/project \
          >/dev/null 2>&1
        rc=$?
        set -e
        printf "%s:%s\n" "$mode" "$rc"
      }
      run_case legacy "$LEGACY" "$HOME_A"
      run_case cross-home "$JOURNAL" "$HOME_B"
      run_case ambiguous "$JOURNAL" "$HOME_A"
      run_case live "$JOURNAL" "$HOME_A"
      run_case unknown "$JOURNAL" "$HOME_A"
      run_case focus-unknown "$JOURNAL" "$HOME_A"
    ')
  [ "$out" = $'legacy:2\ncross-home:2\nambiguous:2\nlive:1\nunknown:1\nfocus-unknown:2' ] \
    || fail "reclaim refusal matrix returned wrong decisions: $out"
  [ ! -s "$mutation_log" ] \
    || fail "legacy, cross-home, ambiguous, live/unknown, or focus-unknown refusal mutated Herdr: $(cat "$mutation_log")"
  [ "$(sed -n 's/^workspace_label=//p' "$journal")" = "$label" ] \
    || fail "reclaim refusal matrix rewrote the bound workspace label"
  pass "herdr presentation reclaim: legacy, cross-home, ambiguous, live/unknown, and focus-unknown cases refuse without mutation"
}

test_projection_reclaim_replaces_only_exact_husk_and_advances_binding() {
  local dir state home home_real log resp fb journal token label out calls create_line close_line agent_line boundary_mutations
  dir="$TMP_ROOT/projection-reclaim-exact"; state="$dir/state"; home="$dir/home"
  mkdir -p "$dir/responses" "$state" "$home"
  home_real=$(cd "$home" && pwd -P)
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  token=$(bash -c '
    . "$0/bin/fm-herdr.sh"
    token=$(fm_herdr_projection_journal_create "$1" fm-hibit-r1) || exit 1
    label=$(fm_herdr_projection_workspace_label fm-hibit-r1 "$token")
    fm_herdr_projection_journal_bind \
      "$1/fm-hibit-r1.herdr-presentation" fm-hibit-r1 "$2" fmtest \
      w2 w2:t2 w2:p2 w1 firstmate "$label" fm-fm-hibit-r1 || exit 1
    printf "%s" "$token"
  ' "$ROOT" "$state" "$home_real") || fail "could not create exact reclaim journal fixture"
  journal="$state/fm-hibit-r1.herdr-presentation"
  label="└ hibit-r1 · p:$token"
  printf '%s\n' "{\"result\":{\"workspaces\":[{\"workspace_id\":\"w0\",\"label\":\"firstmate\",\"focused\":false,\"active_tab_id\":\"w0:t1\"},{\"workspace_id\":\"w1\",\"label\":\"firstmate\",\"focused\":true,\"active_tab_id\":\"w1:t1\"},{\"workspace_id\":\"w2\",\"label\":\"$label\",\"focused\":false,\"active_tab_id\":\"w2:t2\"}]}}" > "$resp/1.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","label":"fm-fm-hibit-r1"}]}}' > "$resp/2.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p2","tab_id":"w2:t2"}]}}' > "$resp/3.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/4.out"
  printf '%s\n' '{"error":{"code":"agent_not_found"}}' > "$resp/5.out"
  printf '%s\n' "{\"result\":{\"workspaces\":[{\"workspace_id\":\"w1\",\"label\":\"firstmate\",\"focused\":true,\"active_tab_id\":\"w1:t1\"},{\"workspace_id\":\"w2\",\"label\":\"$label\",\"focused\":false,\"active_tab_id\":\"w2:t2\"}]}}" > "$resp/6.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w1:t1","focused":true}]}}' > "$resp/7.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w2:t3"},"root_pane":{"pane_id":"w2:p3"}}}' > "$resp/8.out"
  cp "$resp/6.out" "$resp/9.out"
  cp "$resp/7.out" "$resp/10.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w2:t3","workspace_id":"w2"}}}' > "$resp/11.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p3","tab_id":"w2:t3","workspace_id":"w2"}}}' > "$resp/12.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/13.out"
  printf '%s\n' '{"error":{"code":"agent_not_found"}}' > "$resp/14.out"
  cp "$resp/6.out" "$resp/15.out"
  cp "$resp/7.out" "$resp/16.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2","tab_id":"w2:t2","workspace_id":"w2"}}}' > "$resp/17.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w2:p2"}}}' > "$resp/18.out"
  printf '%s\n' '{"error":{"code":"agent_not_found"}}' > "$resp/19.out"
  # The emptying-close plan sees the replacement tab alongside the old husk
  # tab, so the husk close stays plain.
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t2","label":"fm-fm-hibit-r1"},{"tab_id":"w2:t3","label":"fm-fm-hibit-r1"}]}}' > "$resp/20.out"
  : > "$resp/21.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/22.out"
  cp "$resp/6.out" "$resp/23.out"
  cp "$resp/7.out" "$resp/24.out"
  printf '%s\n' '{"error":{"code":"pane_not_found"}}' > "$resp/25.out"
  cp "$resp/1.out" "$resp/26.out"
  printf '%s\n' '{"result":{"tabs":[{"tab_id":"w2:t3","label":"fm-fm-hibit-r1"}]}}' > "$resp/27.out"
  printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p3","tab_id":"w2:t3"}]}}' > "$resp/28.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '
      . "$0/bin/fm-herdr.sh"
      fm_herdr_projection_reclaim_task \
        fmtest "$1" fm-hibit-r1 "$2" w2 w2:t2 w2:p2 firstmate fm-fm-hibit-r1 /tmp/project || exit 1
      printf "%s %s" "$FM_HERDR_PROJECTION_TAB_ID" "$FM_HERDR_PROJECTION_PANE_ID"
    ' "$ROOT" "$journal" "$home") || fail "exact agent-free projection reclaim failed"
  [ "$out" = "w2:t3 w2:p3" ] || fail "reclaim did not return exact replacement ids: $out"
  [ "$(sed -n 's/^tab_id=//p' "$journal")" = w2:t3 ] \
    && [ "$(sed -n 's/^pane_id=//p' "$journal")" = w2:p3 ] \
    || fail "reclaim did not advance the journal to the replacement endpoint"
  calls=$(cat "$log")
  create_line=$(grep -n $'tab\x1fcreate\x1f--workspace\x1fw2' "$log" | cut -d: -f1)
  close_line=$(grep -n $'pane\x1fclose\x1fw2:p2' "$log" | cut -d: -f1)
  [ -n "$create_line" ] && [ -n "$close_line" ] && [ "$create_line" -lt "$close_line" ] \
    || fail "reclaim did not create the exact replacement before closing the old husk"
  agent_line=$(grep -n $'agent\x1fget\x1fw2:p2' "$log" | tail -1 | cut -d: -f1)
  [ -n "$agent_line" ] && [ "$agent_line" -lt "$close_line" ] \
    || fail "reclaim did not recheck the old pane agent state before the close"
  boundary_mutations=$(sed -n "$((agent_line + 1)),$((close_line - 1))p" "$log" \
    | grep -Ev $'\x1f(tab\x1flist|pane\x1flist|workspace\x1flist)' || true)
  [ -z "$boundary_mutations" ] \
    || fail "reclaim mutated between the old pane agent recheck and the close: $boundary_mutations"
  assert_not_contains "$calls" $'workspace\x1fclose' "reclaim introduced workspace-close authority"
  assert_not_contains "$calls" $'workspace\x1frename' "reclaim renamed the projected workspace"
  assert_not_contains "$calls" $'tab\x1ffocus' "focus-preserving reclaim changed an already-stable focus snapshot"
  assert_not_contains "$calls" $'\x1fw0' "reclaim touched the same-labeled sibling parent"
  pass "herdr presentation reclaim: exact agent-free husk survives duplicate parent labels while its sibling stays untouched"
}

test_projection_recovery_is_read_only_and_refuses_live_duplicate_risk() {
  local dir state log resp fb token journal out status calls
  dir="$TMP_ROOT/projection-recovery"; state="$dir/state"; mkdir -p "$dir/responses" "$state"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  token=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_journal_create "$1" task-p3' "$ROOT" "$state")
  journal="$state/task-p3.herdr-presentation"
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate/task-p3 · p:%s"},{"workspace_id":"w2","label":"copy/task-p3 · p:%s"}]}}\n' "$token" "$token" > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"}]}}\n' > "$resp/2.out"
  printf '{"result":{"pane":{"pane_id":"w1:p1"}}}\n' > "$resp/3.out"
  printf '{"error":{"code":"agent_not_found"}}\n' > "$resp/4.out"
  printf '{"result":{"panes":[{"pane_id":"w2:p1","tab_id":"w2:t1"}]}}\n' > "$resp/5.out"
  printf '{"result":{"pane":{"pane_id":"w2:p1"}}}\n' > "$resp/6.out"
  printf '{"error":{"code":"agent_not_found"}}\n' > "$resp/7.out"
  fb=$(make_herdr_fakebin "$dir")
  PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_recovery_allows_flat fmtest "$1" task-p3' "$ROOT" "$journal" \
    >/dev/null || fail "agent-free duplicate token matches should allow flat fallback"
  calls=$(cat "$log")
  assert_not_contains "$calls" $'workspace\x1fcreate' "recovery inspection created a workspace"
  assert_not_contains "$calls" $'workspace\x1fclose' "recovery inspection closed a workspace"
  assert_not_contains "$calls" $'tab\x1fcreate' "recovery inspection created a tab"
  assert_not_contains "$calls" $'tab\x1fclose' "recovery inspection closed a tab"
  assert_not_contains "$calls" $'pane\x1fclose' "recovery inspection closed a pane"

  : > "$log"; rm -f "$resp"/*.out "$resp"/*.exit "$resp/.count"
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate/task-p3 · p:%s"}]}}\n' "$token" > "$resp/1.out"
  printf '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"}]}}\n' > "$resp/2.out"
  printf '{"result":{"pane":{"pane_id":"w1:p1"}}}\n' > "$resp/3.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/4.out"
  out=$(PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_projection_recovery_allows_flat fmtest "$1" task-p3' "$ROOT" "$journal" 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "a token match with a live registered agent must refuse duplicate launch"
  assert_contains "$out" "has a live pane" "live duplicate refusal did not explain the risk"
  assert_not_contains "$(cat "$log")" $'pane\x1fclose' "live duplicate refusal closed a pane"
  pass "herdr presentation recovery: duplicate-token inspection is read-only and live-agent risk refuses fallback"
}

# --- workspace_find: scoped to THIS home's own label, not just any match ----

test_workspace_find_matches_only_this_homes_own_label() {
  local dir log resp fb out home
  dir="$TMP_ROOT/find-scoped"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  home="$TMP_ROOT/find-scoped-home"; mkdir -p "$home"; printf 'bravo-b2\n' > "$home/.fm-secondmate-home"
  # A workspace list carrying BOTH the primary's "firstmate" space and this
  # secondmate's own "2ndmate-bravo-b2" space (as would be true once several
  # homes share one herdr session) - find must pick the one matching THIS
  # home's own label, never the primary's or a sibling secondmate's.
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"2ndmate-bravo-b2"},{"workspace_id":"w3","label":"2ndmate-alpha-a1"}]}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HOME="$home" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_workspace_find fmtest' "$ROOT" )
  [ "$out" = "w2" ] || fail "workspace_find should have matched this home's own label (2ndmate-bravo-b2 -> w2), got '$out'"
  pass "fm_herdr_workspace_find: matches only THIS home's own label among several coexisting workspaces"
}

# --- list_live: scoped to this home's own workspace only ---------------------

test_list_live_scoped_to_this_homes_workspace_only() {
  local dir log resp fb out home
  dir="$TMP_ROOT/list-live-scoped"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  home="$TMP_ROOT/list-live-scoped-home"; mkdir -p "$home"; printf 'bravo-b2\n' > "$home/.fm-secondmate-home"
  # 1: workspace_find's `workspace list` - two homes coexist, secondmate's is w2
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"},{"workspace_id":"w2","label":"2ndmate-bravo-b2"}]}}\n' > "$resp/1.out"
  # 2: tab list --workspace w2 (this secondmate's own tabs only)
  printf '{"result":{"tabs":[{"tab_id":"w2:t1","label":"fm-secondmatetask"}]}}\n' > "$resp/2.out"
  # 3: pane_for_tab's `pane list --workspace w2`
  printf '{"result":{"panes":[{"pane_id":"w2:p1","tab_id":"w2:t1"}]}}\n' > "$resp/3.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HOME="$home" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_list_live fmtest' "$ROOT" )
  [ "$out" = $'fmtest:w2:p1\tfm-secondmatetask' ] || fail "list_live should report only this home's own tab, got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''list'$'\x1f''--workspace'$'\x1f''w2' \
    "list_live did not scope the tab list call to this home's own workspace (w2)"
  assert_not_contains "$(cat "$log")" $'\x1f''tab'$'\x1f''list'$'\x1f''--workspace'$'\x1f''w1' \
    "list_live must never query the primary's (or a sibling secondmate's) workspace"
  pass "fm_herdr_list_live: scoped to this home's own workspace, never a sibling home's"
}

# --- target parsing, key normalization ---------------------------------------

test_parse_target() {
  ( . "$ROOT/bin/fm-herdr.sh"
    fm_herdr_parse_target "default:w1:p2" || exit 1
    [ "$FM_HERDR_SESSION" = default ] || { echo "session mismatch: $FM_HERDR_SESSION" >&2; exit 1; }
    [ "$FM_HERDR_PANE" = "w1:p2" ] || { echo "pane mismatch: $FM_HERDR_PANE" >&2; exit 1; }
  ) || fail "fm_herdr_parse_target did not split session:pane on the first colon only"
  pass "fm_herdr_parse_target: splits '<session>:<pane_id>' on the FIRST colon (pane_id itself contains one)"
}

test_normalize_key() {
  ( . "$ROOT/bin/fm-herdr.sh"
    [ "$(fm_herdr_normalize_key Enter)" = enter ] || exit 1
    [ "$(fm_herdr_normalize_key Escape)" = escape ] || exit 1
    [ "$(fm_herdr_normalize_key C-c)" = ctrl+c ] || exit 1
    [ "$(fm_herdr_normalize_key ctrl+c)" = ctrl+c ] || exit 1
  ) || fail "fm_herdr_normalize_key did not map firstmate's key vocabulary to herdr's verified names"
  pass "fm_herdr_normalize_key: Enter/Escape/C-c map to herdr's verified enter/escape/ctrl+c"
}

# --- capture / send_key / kill / current_path --------------------------------

test_capture_calls_pane_read() {
  local dir log resp fb out
  dir="$TMP_ROOT/capture"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf 'line one\nline two\nline three\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  # Requesting 250 (already >= the 200 floor) passes straight through as the
  # fetch bound; the adapter then trims to the caller's requested 250 lines
  # locally, so all 3 fake lines survive.
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_capture default:w1:p2 250' "$ROOT" )
  [ "$out" = $'line one\nline two\nline three' ] || fail "capture did not pass through pane read output, got '$out'"
  assert_contains "$(cat "$log")" "HERDR_SESSION=default"$'\x1f''pane'$'\x1f''read'$'\x1f''w1:p2'$'\x1f''--source'$'\x1f''recent'$'\x1f''--lines'$'\x1f''250' \
    "capture did not call pane read with the right pane id and line bound"
  pass "fm_herdr_capture: calls 'pane read <pane> --source recent --lines N' with the session set"
}

test_capture_works_around_small_lines_bug() {
  local dir log resp fb out
  # Verified herdr v0.7.1 bug (herdr-verification-p2.md): `pane read --lines N`
  # for a small N (below the pane's viewport height) returns EMPTY, not the
  # last N lines. The adapter must never ask herdr for a small --lines bound -
  # it always fetches >= 200 and trims locally with tail.
  dir="$TMP_ROOT/capture-small"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf 'a\nb\nc\nd\ne\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_capture default:w1:p2 2' "$ROOT" )
  [ "$out" = $'d\ne' ] || fail "a small --lines request should still return the last N lines (trimmed locally), got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''--lines'$'\x1f''200' \
    "capture should request a generous fetch (>=200), never the caller's small N, from herdr's own --lines flag"
  pass "fm_herdr_capture: works around the verified small-N '--lines' bug by over-fetching and trimming locally"
}

test_capture_preserves_pane_read_failure() {
  local dir log resp fb out status
  dir="$TMP_ROOT/capture-fail"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '1\n' > "$resp/1.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_capture default:w1:p2 2' "$ROOT" 2>&1 )
  status=$?
  [ "$status" -ne 0 ] || fail "capture should fail when pane read fails, got output '$out'"
  assert_contains "$(cat "$log")" "HERDR_SESSION=default"$'\x1f''status'$'\x1f''--json' \
    "capture did not ensure the herdr server before reading the pane"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''read'$'\x1f''w1:p2' \
    "capture did not try to read the requested pane"
  pass "fm_herdr_capture: ensures the session and preserves pane read failure"
}

test_send_key_normalizes_and_targets_pane() {
  local dir log resp fb
  dir="$TMP_ROOT/sendkey"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  fb=$(make_herdr_fakebin "$dir")
  PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_key default:w1:p2 Escape' "$ROOT"
  expect_code 0 $? "send_key should succeed"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''escape' "send_key did not normalize Escape to escape"
  pass "fm_herdr_send_key: normalizes the key and targets the right pane"
}

test_kill_is_best_effort() {
  local dir log resp fb
  dir="$TMP_ROOT/kill"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '1\n' > "$resp/1.exit"
  fb=$(make_herdr_fakebin "$dir")
  PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '
      . "$0/bin/fm-herdr.sh"
      fm_herdr_target_ready() { fm_herdr_parse_target "$1"; }
      fm_herdr_presentation_session_lock_path() { printf "/tmp/fm-herdr-test-lock"; }
      fm_lock_try_acquire() { return 0; }
      fm_lock_release() { return 0; }
      fm_herdr_kill default:w1:p2
    ' "$ROOT"
  expect_code 0 $? "kill must be best-effort (never fail even when the pane close call itself fails)"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close'$'\x1f''w1:p2' "kill did not call pane close on the right pane"
  pass "fm_herdr_kill: calls pane close and stays best-effort on failure"
}

test_current_path_reads_cwd() {
  local dir log resp fb out
  dir="$TMP_ROOT/cwd"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Verified pitfall (herdr-verification-p2.md): .result.pane.cwd is frozen at
  # pane-creation time and never updates; .foreground_cwd tracks the live
  # running process (e.g. a treehouse get subshell) and is what must be read.
  printf '{"result":{"pane":{"cwd":"/tmp/pane-creation-dir","foreground_cwd":"/tmp/fake-worktree"}}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_current_path default:w1:p2' "$ROOT" )
  [ "$out" = "/tmp/fake-worktree" ] || fail "current_path should read foreground_cwd (the live process), not the frozen creation-time cwd, got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''get'$'\x1f''w1:p2' "current_path did not call pane get"
  pass "fm_herdr_current_path: reads pane foreground_cwd (the live running process), not the frozen creation-time cwd"
}

# --- busy_state (semantic agent state) ---------------------------------------

test_busy_state_working_maps_to_busy() {
  local dir log resp fb out
  dir="$TMP_ROOT/busy-working"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_busy_state default:w1:p2' "$ROOT" )
  [ "$out" = busy ] || fail "agent_status=working should map to busy, got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''agent'$'\x1f''get'$'\x1f''w1:p2' "busy_state did not call agent get"
  pass "fm_herdr_busy_state: working -> busy"
}

test_busy_state_done_and_blocked_map_to_idle() {
  local dir log resp fb out
  dir="$TMP_ROOT/busy-done"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"done"}}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_busy_state default:w1:p2' "$ROOT" )
  [ "$out" = idle ] || fail "agent_status=done should map to idle, got '$out'"

  dir="$TMP_ROOT/busy-blocked"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"blocked"}}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_busy_state default:w1:p2' "$ROOT" )
  [ "$out" = idle ] || fail "agent_status=blocked should map to idle (stuck waiting on the human, not grinding), got '$out'"
  pass "fm_herdr_busy_state: done -> idle, blocked -> idle (surfaced like a stale pane, not suppressed as busy)"
}

test_busy_state_unknown_on_no_agent() {
  local dir log resp fb out
  dir="$TMP_ROOT/busy-unknown"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '1\n' > "$resp/1.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_busy_state default:w1:p2' "$ROOT" )
  [ "$out" = unknown ] || fail "a failed agent get should report unknown (the fallback-to-regex cue), got '$out'"
  pass "fm_herdr_busy_state: unparseable/absent agent state reports unknown, the regex-fallback cue"
}

# --- composer_state: structural border-row classification --------------------

test_composer_state_bordered_prompt_is_empty() {
  local dir log resp fb out
  dir="$TMP_ROOT/composer-bare"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '  ╭────────────────────────╮\n  │ ❯                      │\n  ╰────────────────────────╯\n\n  Shift+Tab:mode\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state default:w1:p2' "$ROOT" )
  [ "$out" = empty ] || fail "a bordered prompt glyph should read as empty, got '$out'"
  pass "fm_herdr_composer_state: a bordered composer row reads empty"
}

test_composer_state_styled_placeholder_draft_is_pending() {
  local dir log resp fb out
  dir="$TMP_ROOT/composer-ghost"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '  ╭────────────────────────╮\n  │ ❯ Type a message...    │\n  ╰────────────────────────╯\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state default:w1:p2' "$ROOT" )
  [ "$out" = pending ] || fail "bright placeholder-like text in a styled capture should remain pending, got '$out'"
  pass "fm_herdr_composer_state: bright placeholder-like text stays pending rather than being mistaken for an idle ghost"
}

test_composer_state_real_text_is_pending() {
  local dir log resp fb out
  dir="$TMP_ROOT/composer-pending"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '  ╭────────────────────────╮\n  │ ❯ hello captain        │\n  ╰────────────────────────╯\n\n  Enter:send\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state default:w1:p2' "$ROOT" )
  [ "$out" = pending ] || fail "real unsubmitted text should read as pending, got '$out'"
  pass "fm_herdr_composer_state: real composer text reads pending"
}

# A slash completion popup can consume the first Enter, close, and expand the
# composer into an argument-hint placeholder
# ("/compact compaction instructions") rather than submitting - the composer
# still reads real, unsubmitted text and the footer still shows "Enter:send".
# A prior raw-diff verification saw the popup vanish and the text change and
# declared this "submitted". The structural composer-row read must still call
# this pending.
test_composer_state_popup_placeholder_fill_is_pending() {
  local dir log resp fb out
  dir="$TMP_ROOT/composer-popup-placeholder"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '  ╭──────────────────────────────────────╮\n  │ ❯ /compact compaction instructions   │\n  ╰──────────────────────────────────────╯\n\n  Enter:send\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state default:w1:p2' "$ROOT" )
  [ "$out" = pending ] || fail "a popup-close-with-placeholder-fill must still read as pending (not yet submitted), got '$out'"
  pass "fm_herdr_composer_state: a slash-command popup's argument-hint placeholder still reads pending (the incident fix)"
}

test_composer_state_unknown_on_capture_failure() {
  local dir log resp fb out status
  dir="$TMP_ROOT/composer-capture-fail"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '1\n' > "$resp/1.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state default:w1:p2' "$ROOT" )
  status=$?
  [ "$status" -eq 0 ] || fail "composer_state should not itself fail the caller"
  [ "$out" = unknown ] || fail "an unreadable pane should read as unknown, got '$out'"
  pass "fm_herdr_composer_state: reports unknown when the pane cannot be captured"
}

test_composer_state_unknown_when_no_composer_row_found() {
  local dir log resp fb out glyph idx=1
  dir="$TMP_ROOT/composer-no-row"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  for glyph in '>' '❯' '$' '%' '#'; do
    printf '%s \n' "$glyph" > "$resp/$idx.out"
    idx=$((idx + 1))
  done
  fb=$(make_herdr_fakebin "$dir")
  for glyph in '>' '❯' '$' '%' '#'; do
    out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
      bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state default:w1:p2' "$ROOT" )
    [ "$out" = unknown ] || fail "a bare shell prompt '$glyph' should read as unknown, got '$out'"
  done
  pass "fm_herdr_composer_state: reports unknown for bare shell prompts with no composer row"
}

# Real Pi 0.80.7 on Herdr 0.7.3 renders no prompt glyph and no side border.
# Its content is the row(s) between two blue horizontal separators; the idle row
# carries only a reverse-video cursor. This exact shape was `unknown` for 4555s
# during the 2026-07-14 incident, so the safe injector never attempted submit.
test_composer_state_pi_separator_idle_is_empty() {
  local dir log resp fb out calls
  dir="$TMP_ROOT/composer-pi-separated-idle"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '│ stale bordered transcript row │\n\x1b[0m\x1b[38;2;129;162;190m─────────────────────────────────────────────────────\x1b[0m\n\x1b[0m\x1b[7m \x1b[0m                                                    \n\x1b[0m\x1b[38;2;129;162;190m─────────────────────────────────────────────────────\x1b[0m\n\x1b[0m\x1b[38;2;102;102;102m~/synthetic-primary (main)\x1b[0m\n' > "$resp/1.out"
  printf '{"result":{"agent":{"agent":"pi","agent_status":"idle"}}}\n' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state lab:w1:p2' "$ROOT" )
  [ "$out" = empty ] || fail "an idle native Pi separator composer should read empty, got '$out'"
  calls=$(grep -c $'\x1f''agent'$'\x1f''get' "$log")
  [ "$calls" -eq 1 ] || fail "Pi separator recognition must corroborate identity exactly once, made $calls agent calls"
  pass "fm_herdr_composer_state: a native idle Pi separator composer reads empty"
}

test_composer_state_pi_separator_real_text_is_pending() {
  local dir log resp fb out
  dir="$TMP_ROOT/composer-pi-separated-pending"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '\x1b[38;2;129;162;190m─────────────────────────────────────────────────────\x1b[0m\nprivacy safe human draft\x1b[7m \x1b[0m\n\x1b[38;2;129;162;190m─────────────────────────────────────────────────────\x1b[0m\n' > "$resp/1.out"
  printf '{"result":{"agent":{"agent":"pi","agent_status":"done"}}}\n' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state lab:w1:p2' "$ROOT" )
  [ "$out" = pending ] || fail "real text in a native Pi separator composer should read pending, got '$out'"
  pass "fm_herdr_composer_state: real Pi composer text remains pending"
}

test_composer_state_pi_incomplete_separator_below_stale_generic_is_unknown() {
  local dir log resp fb out
  dir="$TMP_ROOT/composer-pi-separated-incomplete"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '│   │\n─────────────────────────────────────────────────────\n\n' > "$resp/1.out"
  printf '{"result":{"agent":{"agent":"pi","agent_status":"idle"}}}\n' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state lab:w1:p2' "$ROOT" )
  [ "$out" = unknown ] || fail "an incomplete Pi separator below a stale generic row should remain unknown, got '$out'"
  pass "fm_herdr_composer_state: an incomplete lower Pi separator cannot inherit a stale empty row"
}

test_composer_state_pi_separator_requires_safe_native_identity() {
  local dir log resp fb out status case_id idx=0
  for case_id in working non-pi unreadable over-tall; do
    dir="$TMP_ROOT/composer-pi-separated-$case_id"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
    if [ "$case_id" = over-tall ]; then
      {
        printf '─────────────────────────────────────────────────────\n'
        for idx in $(seq 1 9); do printf 'line %s\n' "$idx"; done
        printf '─────────────────────────────────────────────────────\n'
      } > "$resp/1.out"
    else
      printf '─────────────────────────────────────────────────────\n\n─────────────────────────────────────────────────────\n' > "$resp/1.out"
    fi
    case "$case_id" in
      working) printf '{"result":{"agent":{"agent":"pi","agent_status":"working"}}}\n' > "$resp/2.out" ;;
      non-pi) printf '{"result":{"agent":{"agent":"shell","agent_status":"idle"}}}\n' > "$resp/2.out" ;;
      unreadable) printf '1\n' > "$resp/2.exit" ;;
      over-tall) printf '{"result":{"agent":{"agent":"pi","agent_status":"idle"}}}\n' > "$resp/2.out" ;;
    esac
    fb=$(make_herdr_fakebin "$dir")
    out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
      bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_composer_state lab:w1:p2' "$ROOT" )
    [ "$out" = unknown ] || fail "unsafe Pi separator case '$case_id' must remain unknown, got '$out'"
  done
  pass "fm_herdr_composer_state: Pi separators never authorize working, non-Pi, unreadable, or over-tall targets"
}

# --- wait_for_working: the native agent-state poll-and-classify primitive ---
# Direct unit coverage for fm_herdr_wait_for_working, the helper
# fm_herdr_send_text_submit now uses instead of composer scraping
# (docs/herdr-backend.md "Native agent-state submit confirmation").

test_wait_for_working_returns_busy_on_first_poll() {
  local dir log resp fb out calls
  dir="$TMP_ROOT/wait-busy-first"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_for_working default w1:p2 1 5' "$ROOT" )
  [ "$out" = busy ] || fail "wait_for_working should report busy once 'working' is observed, got '$out'"
  calls=$(grep -c $'\x1f''agent'$'\x1f''get' "$log")
  [ "$calls" -eq 1 ] || fail "wait_for_working should short-circuit on the FIRST busy poll instead of consuming the whole budget, made $calls call(s)"
  pass "fm_herdr_wait_for_working: reports 'busy' immediately on the first poll, without spending the rest of the budget"
}

test_wait_for_working_catches_a_slow_transition_mid_window() {
  local dir log resp fb out calls
  dir="$TMP_ROOT/wait-busy-slow"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Two idle samples, then working on the third - a transition that would be
  # MISSED by a single check-at-the-end design (the old composer approach's
  # shape) but is caught here because the budget is sampled repeatedly.
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/1.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/3.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_for_working default w1:p2 0.03 3' "$ROOT" )
  [ "$out" = busy ] || fail "wait_for_working should catch a transition that lands on a later sample within the SAME window, got '$out'"
  calls=$(grep -c $'\x1f''agent'$'\x1f''get' "$log")
  [ "$calls" -eq 3 ] || fail "expected exactly 3 agent-get polls (idle, idle, working), got $calls"
  pass "fm_herdr_wait_for_working: a slow transition landing on a later sample within one window is still caught (robust against the 'slow transition' failure direction)"
}

test_wait_for_working_samples_budget_endpoint_without_final_sleep() {
  local dir log resp fb out sleep_log sleeps
  dir="$TMP_ROOT/wait-budget-endpoint"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; sleep_log="$dir/sleeps"; : > "$log"; : > "$sleep_log"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/1.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/3.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/4.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/5.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_SLEEP_LOG="$sleep_log" \
    bash -c '. "$0/bin/fm-herdr.sh"; sleep() { printf "sleep:%s\n" "$1" >> "$FM_SLEEP_LOG"; }; fm_herdr_wait_for_working default w1:p2 0.5 6' "$ROOT" )
  [ "$out" = idle ] || fail "wait_for_working should report idle when every endpoint-spread poll is readable-idle, got '$out'"
  sleeps=$(grep -c '^sleep:0.1000$' "$sleep_log")
  [ "$sleeps" -eq 5 ] || fail "six polls across a 0.5s budget should sleep five times at 0.1000s, got $sleeps matching sleeps; log: $(cat "$sleep_log")"
  pass "fm_herdr_wait_for_working: spreads six samples across the full budget endpoint without a final trailing sleep"
}

test_send_text_submit_applies_herdr_minimum_confirm_budget() {
  local dir log resp fb out sleep_log sleeps
  dir="$TMP_ROOT/submit-min-budget"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; sleep_log="$dir/sleeps"; : > "$log"; : > "$sleep_log"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/4.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/5.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/6.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/7.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/8.out"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/9.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_SLEEP_LOG="$sleep_log" FM_HERDR_SUBMIT_POLLS=6 FM_HERDR_SUBMIT_MIN_SLEEP=0.6 \
    bash -c '. "$0/bin/fm-herdr.sh"; sleep() { printf "sleep:%s\n" "$1" >> "$FM_SLEEP_LOG"; }; fm_herdr_send_text_submit default:w1:p2 "hello captain" 1 0.4 0' "$ROOT" )
  [ "$out" = empty ] || fail "send_text_submit should catch a slow-but-valid transition inside the herdr minimum budget, got '$out'"
  sleeps=$(grep -c '^sleep:0.1200$' "$sleep_log")
  [ "$sleeps" -eq 5 ] || fail "a 0.4s caller budget should be expanded to five 0.1200s sleeps across the 0.6s herdr floor, got $sleeps; log: $(cat "$sleep_log")"
  [ "$(grep -c '^sleep:0.0800$' "$sleep_log")" -eq 0 ] || fail "send_text_submit used the caller's too-short 0.4s budget instead of the herdr floor: $(cat "$sleep_log")"
  pass "fm_herdr_send_text_submit: applies the herdr minimum confirmation budget before polling agent-state"
}

test_wait_for_working_returns_idle_when_never_busy_but_readable() {
  local dir log resp fb out
  dir="$TMP_ROOT/wait-idle"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/1.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_for_working default w1:p2 0.02 2' "$ROOT" )
  [ "$out" = idle ] || fail "wait_for_working should report idle when the target was legibly read but never busy, got '$out'"
  pass "fm_herdr_wait_for_working: reports 'idle' (readable, genuinely not yet working) when 'busy' never appears"
}

test_wait_for_working_returns_unknown_when_never_readable() {
  local dir log resp fb out
  dir="$TMP_ROOT/wait-unknown"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '1\n' > "$resp/1.exit"
  printf '1\n' > "$resp/2.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_for_working default w1:p2 0.02 2' "$ROOT" )
  [ "$out" = unknown ] || fail "wait_for_working should report unknown when every poll fails to read the target, got '$out'"
  pass "fm_herdr_wait_for_working: reports 'unknown' (a hard read failure, not a timing race) only when EVERY poll in the window fails"
}

test_wait_for_working_treats_blocked_as_submit_active() {
  local dir log resp fb out
  dir="$TMP_ROOT/wait-blocked"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"blocked"}}}\n' > "$resp/1.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_for_working default w1:p2 0.01 1' "$ROOT" )
  [ "$out" = busy ] || fail "wait_for_working should treat a post-Enter blocked state as submit-active, got '$out'"
  pass "fm_herdr_wait_for_working: treats blocked as submit-active for confirmation without changing watcher busy-state semantics"
}

# --- send_text_submit: native agent-state (agent get) verify-and-retry ------
# Confirmation no longer reads composer content in the normal idle-baseline
# path, so dynamic idle text cannot block or mis-confirm a send.
# FM_HERDR_SUBMIT_POLLS=1 pins most tests
# below to exactly one agent-get sample per Enter attempt for simple,
# deterministic call-count assertions; the multi-sample behavior itself is
# covered above by the wait_for_working tests and by
# test_send_text_submit_slow_transition_within_one_enter_needs_no_extra_enter.

test_send_text_submit_detects_landed_send() {
  local dir log resp fb out enter_count
  dir="$TMP_ROOT/submit-ok"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # 1: send-text (literal, no output)
  # 2: agent get - pre-Enter baseline is idle
  # 3: send-keys enter
  # 4: agent get - agent_status working (a real turn started: submitted)
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "hello captain" 3 0.01 0.01' "$ROOT" )
  [ "$out" = empty ] || fail "send_text_submit should report empty (submitted) once agent_status reports working, got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''send-text'$'\x1f''w1:p2'$'\x1f''hello captain' "send_text_submit did not type the literal text first"
  enter_count=$(grep -c $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''enter' "$log")
  [ "$enter_count" -eq 1 ] || fail "send_text_submit should not need a second Enter for a plain message with no popup, sent $enter_count Enter(s)"
  [ "$(grep -c $'\x1f''pane'$'\x1f''read' "$log")" -eq 0 ] || fail "send_text_submit must never read the composer/pane content for confirmation anymore"
  pass "fm_herdr_send_text_submit: reports 'empty' once agent_status reports working after one Enter, without ever reading the composer"
}

test_send_text_submit_detects_swallowed_enter() {
  local dir log resp fb out
  dir="$TMP_ROOT/submit-swallow"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # Every post-Enter agent-get read still reports idle: the Enter never
  # started a turn (swallowed), so wait_for_working never observes "busy".
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/4.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "hello captain" 2 0.01 0.01' "$ROOT" )
  [ "$out" = pending ] || fail "send_text_submit should report pending once retries are exhausted with agent_status never going busy, got '$out'"
  pass "fm_herdr_send_text_submit: reports 'pending' when agent_status never reports working after retried Enters (swallowed)"
}

# Regression coverage for the 2026-07-03 incident using the NEW mechanism: a
# slash command's first Enter can close a completion popup and fill an
# argument-hint placeholder WITHOUT submitting. In the idle-baseline path,
# filling a placeholder never starts a turn, so agent_status simply stays idle
# for Enter #1, and the retry loop sends a genuine second Enter exactly as it
# would for any other swallowed Enter.
test_send_text_submit_popup_autocomplete_requires_second_enter() {
  local dir log resp fb out enter_count
  dir="$TMP_ROOT/submit-popup-autocomplete"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # 1: send-text "/compact"
  # 2: agent get - pre-Enter baseline is idle
  # 3: send-keys enter (#1) - closes the popup, fills the placeholder; no turn starts
  # 4: agent get -> idle (not submitted yet)
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/4.out"
  # 5: send-keys enter (#2) - actually submits
  # 6: agent get -> working (submitted)
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "/compact" 3 0.01 1.2' "$ROOT" )
  [ "$out" = empty ] || fail "send_text_submit should eventually report empty once the SECOND Enter actually starts a turn, got '$out'"
  enter_count=$(grep -c $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''enter' "$log")
  [ "$enter_count" -eq 2 ] || fail "send_text_submit must send a SECOND Enter after the popup-placeholder fill's agent_status still reads idle, got $enter_count Enter(s)"
  pass "fm_herdr_send_text_submit: a slash-command popup's placeholder fill on Enter #1 never flips agent_status to working, so it does not short-circuit as submitted; Enter #2 is retried and lands it"
}

test_send_text_submit_confirms_blocked_after_enter() {
  local dir log resp fb out enter_count
  dir="$TMP_ROOT/submit-blocked"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"blocked"}}}\n' > "$resp/3.out"
  printf '{"result":{"agent":{"agent_status":"blocked"}}}\n' > "$resp/4.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "needs approval" 3 0.01 0.01' "$ROOT" )
  [ "$out" = empty ] || fail "send_text_submit should treat a blocked state after Enter as a confirmed delivered prompt, got '$out'"
  enter_count=$(grep -c $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''enter' "$log")
  [ "$enter_count" -eq 1 ] || fail "blocked after Enter must not provoke a retry into the prompt, sent $enter_count Enter(s)"
  pass "fm_herdr_send_text_submit: a post-Enter blocked state confirms delivery without retrying into the prompt"
}

# A slow transition landing partway through a single Enter attempt's own
# budget must not provoke a needless extra Enter - end-to-end through
# send_text_submit itself (test_wait_for_working_catches_a_slow_transition_mid_window
# above covers the primitive directly; this proves the caller wires it
# correctly).
test_send_text_submit_slow_transition_within_one_enter_needs_no_extra_enter() {
  local dir log resp fb out enter_count
  dir="$TMP_ROOT/submit-slow-transition"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  # 1: send-text  2: baseline idle  3: send-keys enter  4,5: agent get -> idle  6: agent get -> working
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/4.out"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/5.out"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/6.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=3 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "hello captain" 3 0.03 0.01' "$ROOT" )
  [ "$out" = empty ] || fail "send_text_submit should confirm once a later sample within the SAME Enter attempt observes working, got '$out'"
  enter_count=$(grep -c $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''enter' "$log")
  [ "$enter_count" -eq 1 ] || fail "a slow (but within-budget) transition must not provoke a needless extra Enter, sent $enter_count Enter(s)"
  pass "fm_herdr_send_text_submit: a slow transition landing on a later sample within one Enter's budget is confirmed WITHOUT sending a needless extra Enter"
}

test_send_text_submit_send_failed() {
  local dir log resp fb out
  dir="$TMP_ROOT/submit-fail"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '1\n' > "$resp/1.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "x" 2 0.01 0.01' "$ROOT" )
  [ "$out" = send-failed ] || fail "send_text_submit should report send-failed when the literal send itself fails, got '$out'"
  pass "fm_herdr_send_text_submit: reports 'send-failed' when the literal send-text call itself errors"
}

test_send_text_submit_enter_failure_is_send_failed() {
  local dir log resp fb out enter_count
  dir="$TMP_ROOT/submit-enter-fail"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/2.out"
  printf '1\n' > "$resp/3.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "x" 2 0.01 0.01' "$ROOT" )
  [ "$out" = send-failed ] || fail "send_text_submit should report send-failed when Enter transport fails, got '$out'"
  enter_count=$(grep -c $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''enter' "$log")
  [ "$enter_count" -eq 1 ] || fail "send_text_submit retried after Enter transport failed, sent $enter_count Enter(s)"
  pass "fm_herdr_send_text_submit: Enter transport failure is never promoted to confirmation uncertainty"
}

test_send_text_submit_later_enter_failure_stays_unconfirmed() {
  local dir log resp fb out enter_count
  dir="$TMP_ROOT/submit-later-enter-fail"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"working"}}}\n' > "$resp/2.out"
  printf '╭─────╮\n│ ❯ queued │\n╰─────╯\n' > "$resp/4.out"
  printf '1\n' > "$resp/5.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "x" 3 0.01 0.01' "$ROOT" )
  [ "$out" = pending ] || fail "send_text_submit should preserve unconfirmed submission after a later Enter failure, got '$out'"
  enter_count=$(grep -c $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''enter' "$log")
  [ "$enter_count" -eq 2 ] || fail "send_text_submit should attempt only the initial and failed retry Enter, sent $enter_count Enter(s)"
  pass "fm_herdr_send_text_submit: a later Enter failure preserves the earlier successful submission attempt"
}

test_send_text_submit_unknown_on_capture_failure() {
  local dir log resp fb out enter_count
  dir="$TMP_ROOT/submit-read-fail"; mkdir -p "$dir/responses"; log="$dir/log"; resp="$dir/responses"; : > "$log"
  printf '{"result":{"agent":{"agent_status":"idle"}}}\n' > "$resp/2.out"
  printf '1\n' > "$resp/4.exit"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" FM_HERDR_SUBMIT_POLLS=1 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_send_text_submit default:w1:p2 "x" 2 0.01 0.01' "$ROOT" )
  [ "$out" = unknown ] || fail "send_text_submit should report unknown when the post-Enter agent-get read fails, got '$out'"
  enter_count=$(grep -c $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''enter' "$log")
  [ "$enter_count" -eq 1 ] || fail "send_text_submit must never retry past an unreadable target (that is a hard I/O failure, not a timing race), sent $enter_count Enter(s)"
  pass "fm_herdr_send_text_submit: reports 'unknown' when the post-Enter agent-get read fails (never retries past an unreadable target)"
}

test_scripts_route_explicit_target_through_herdr_meta() {
  local dir state log resp fb neutral out
  dir="$TMP_ROOT/script-explicit-target"; state="$dir/state"; mkdir -p "$state" "$dir/responses"
  : > "$dir/herdr.sock"
  log="$dir/log"; resp="$dir/responses"; : > "$log"
  neutral="$dir/neutral-root"; mkdir -p "$neutral"
  fm_write_meta "$state/herdr-stale.meta" \
    "backend=herdr" "window=default:w1:p2" "endpoint_task_id=herdr-stale" \
    "herdr_session=default" "herdr_workspace_id=w1" "herdr_tab_id=w1:t1" \
    "herdr_pane_id=w1:p2" "worktree=/tmp/herdr-stale" "project=/tmp/project"
  touch "$state/.last-watcher-beat"
  printf '{"sessions":[{"name":"default","running":true,"socket_path":"%s/herdr.sock"}]}\n' "$dir" > "$resp/1.out"
  cp "$resp/1.out" "$resp/2.out"
  cp "$resp/1.out" "$resp/3.out"
  cp "$resp/1.out" "$resp/4.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p2","tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/5.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/6.out"
  printf 'captured herdr pane\n' > "$resp/7.out"
  fb=$(make_herdr_fakebin "$dir")
  out=$( PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$neutral" FM_STATE_OVERRIDE="$state" \
    FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    "$ROOT/bin/fm-peek.sh" default:w1:p2 5 2>/dev/null )
  [ "$out" = "captured herdr pane" ] || fail "fm-peek did not capture through herdr for an explicit metadata-matched target, got '$out'"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''read'$'\x1f''w1:p2' \
    "fm-peek did not route the explicit stale target through herdr capture"

  : > "$log"
  rm -f "$resp/.count" "$resp"/*.out
  printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p2","tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/1.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/2.out"
  printf '{"sessions":[{"name":"default","running":true,"socket_path":"%s/herdr.sock"}]}\n' "$dir" > "$resp/3.out"
  cp "$resp/3.out" "$resp/4.out"
  cp "$resp/3.out" "$resp/5.out"
  cp "$resp/3.out" "$resp/6.out"
  printf '%s\n' '{"result":{"pane":{"pane_id":"w1:p2","tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/7.out"
  printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t1","workspace_id":"w1"}}}' > "$resp/8.out"
  PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$neutral" FM_HOME="$neutral" FM_STATE_OVERRIDE="$state" \
    FM_HERDR_LOG="$log" FM_HERDR_RESPONSES="$resp" \
    "$ROOT/bin/fm-send.sh" default:w1:p2 --key Escape >/dev/null 2>&1
  expect_code 0 $? "fm-send --key should route an explicit metadata-matched target through herdr"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''send-keys'$'\x1f''w1:p2'$'\x1f''escape' \
    "fm-send did not route the explicit stale target through herdr send-key"

  pass "fm-peek/fm-send: explicit stale targets matching metadata use the recorded backend"
}

# --- workspace lifecycle: reuse, no orphans, default-tab pruning -------------

test_workspace_ensure_prunes_default_tab() {
  local dir log state fb raw container seeded wsid ids pane tabcount
  dir="$TMP_ROOT/prune-default"; mkdir -p "$dir"; log="$dir/log"; state="$dir/state.json"; : > "$log"
  fb=$(make_herdr_statefake "$dir")
  raw=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /proj' "$ROOT" ) \
    || fail "container_ensure failed against the stateful fake"
  container=${raw%%$'\t'*}
  seeded=${raw#*$'\t'}
  wsid=${container#*:}
  [ -n "$seeded" ] || fail "container_ensure should report the seeded default tab id for a freshly created workspace, got raw='$raw'"
  # herdr seeds a fresh workspace with one auto-created default tab (label "1")
  # and closing a workspace's LAST tab deletes the whole workspace on real
  # herdr, so the adapter must not prune it until a real task tab exists
  # alongside it - verify it is still present right after container_ensure.
  tabcount=$(jq -r --arg w "$wsid" '[.tabs[]|select(.workspace_id==$w)]|length' "$state")
  [ "$tabcount" = 1 ] || fail "expected the untouched default tab to remain after container_ensure alone, got $tabcount tab(s): $(jq -c '.tabs' "$state")"
  ids=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task "$1" "$2" /proj "$3"' "$ROOT" "$container" "fm-prunetest" "$seeded" ) \
    || fail "create_task failed against the stateful fake"
  read -r _ pane <<EOF
$ids
EOF
  [ -n "$pane" ] || fail "create_task returned no pane id"
  # Once the real task tab exists, create_task must prune the SEEDED default
  # tab id container_ensure captured, so only the real task tab remains.
  tabcount=$(jq -r --arg w "$wsid" '[.tabs[]|select(.workspace_id==$w)]|length' "$state")
  [ "$tabcount" = 1 ] || fail "the auto-created default tab should be pruned once a real task tab exists, $tabcount tab(s) remain: $(jq -c '.tabs' "$state")"
  jq -r --arg w "$wsid" '[.tabs[]|select(.workspace_id==$w)][0].label' "$state" | grep -qx 'fm-prunetest' \
    || fail "the surviving tab should be the real task tab, not the default: $(jq -c '.tabs' "$state")"
  assert_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close' "create_task did not close the default tab's pane"
  pass "fm_herdr_create_task: prunes exactly the seeded default tab container_ensure identified, once the first real task tab exists"
}

test_repeated_cycles_reuse_one_workspace_no_orphans() {
  local dir log state fb i raw container seeded wsid ids pane first_ws="" wscount total tabcount created
  dir="$TMP_ROOT/cycles"; mkdir -p "$dir"; log="$dir/log"; state="$dir/state.json"; : > "$log"
  fb=$(make_herdr_statefake "$dir")
  for i in 1 2 3; do
    raw=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
      bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /proj' "$ROOT" ) \
      || fail "cycle $i: container_ensure failed"
    container=${raw%%$'\t'*}
    seeded=${raw#*$'\t'}
    case "$container" in fmtest:w*) : ;; *) fail "cycle $i: unexpected container '$container'" ;; esac
    wsid=${container#*:}
    if [ -z "$first_ws" ]; then
      first_ws=$wsid
      [ -n "$seeded" ] || fail "cycle $i: the first cycle must create a fresh workspace and report its seeded default tab id"
    else
      [ "$wsid" = "$first_ws" ] || fail "cycle $i: workspace not reused ('$wsid' != '$first_ws')"
      [ -z "$seeded" ] || fail "cycle $i: a REUSED (adopted) workspace must never report a seeded default tab id, got '$seeded'"
    fi
    ids=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
      bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task "$1" "$2" /proj "$3"' "$ROOT" "$container" "fm-cycle$i" "$seeded" ) \
      || fail "cycle $i: create_task failed"
    read -r _ pane <<EOF
$ids
EOF
    [ -n "$pane" ] || fail "cycle $i: create_task returned no pane id"
    PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
      bash -c '
        . "$0/bin/fm-herdr.sh"
        fm_herdr_presentation_session_lock_path() { printf "/tmp/fm-herdr-cycle-test-lock"; }
        fm_lock_try_acquire() { return 0; }
        fm_lock_release() { return 0; }
        fm_herdr_kill "$1"
      ' "$ROOT" "fmtest:$pane" \
      || fail "cycle $i: kill failed"
  done
  # exactly one firstmate workspace survives three spawn/teardown cycles
  wscount=$(jq -r '[.workspaces[]|select(.label=="firstmate")]|length' "$state")
  [ "$wscount" = 1 ] || fail "expected exactly 1 firstmate workspace after 3 cycles, got $wscount: $(jq -c '.workspaces' "$state")"
  # and no orphaned workspaces of any label
  total=$(jq -r '.workspaces|length' "$state")
  [ "$total" = 1 ] || fail "expected no orphaned workspaces after 3 cycles, got $total total: $(jq -c '.workspaces' "$state")"
  # zero tabs remain: every fm- task tab torn down AND the default tab pruned
  tabcount=$(jq -r '.tabs|length' "$state")
  [ "$tabcount" = 0 ] || fail "expected 0 tabs after teardown (default tab pruned, task tabs killed), got $tabcount: $(jq -c '.tabs' "$state")"
  # the workspace was minted once and reused thereafter, never re-created
  created=$(grep -c $'\x1f''workspace'$'\x1f''create' "$log")
  [ "$created" = 1 ] || fail "workspace create should run exactly once across 3 cycles (reuse, not re-mint), ran $created times"
  pass "herdr repeated spawn/teardown: one persistent firstmate workspace reused, zero orphans, default tab pruned, create ran once"
}

# --- created-vs-adopted default-tab-prune safety (2026-07-02 self-kill fix) -
#
# Root cause and fix are documented at
# fm_herdr_workspace_prune_seeded_default_tab in bin/fm-herdr.sh
# and docs/herdr-backend.md's "Default-tab prune" section. These three tests
# cover the acceptance bar directly: an ADOPTED workspace's tab is never a
# prune candidate (regardless of label or count), a freshly CREATED
# workspace's seeded default tab IS pruned (already covered above by
# test_workspace_ensure_prunes_default_tab and
# test_repeated_cycles_reuse_one_workspace_no_orphans), and the exact
# label-collision startup-workspace shape that caused the real incident
# leaves the live tab alone.

test_adopted_workspace_never_prunes_default_tab() {
  # An ADOPTED workspace (fm_herdr_workspace_find matched a
  # pre-existing workspace by label) must never have any tab pruned by
  # create_task, regardless of that tab's label or count - the created-vs-
  # adopted gate is structural (an empty seeded_tab_id), never re-derived
  # from label patterns at create_task time.
  local dir log state fb raw container seeded ids pane
  dir="$TMP_ROOT/adopt-no-prune"; mkdir -p "$dir"; log="$dir/log"; state="$dir/state.json"; : > "$log"
  fb=$(make_herdr_statefake "$dir")
  # Pre-seed a workspace that ALREADY exists before this spawn runs (as if a
  # previous session created it), with a single tab labeled "1" - the same
  # shape herdr's own auto-seeded default tab has, but this run's own
  # container_ensure never ran a `workspace create` call to produce it.
  jq -n '{next:2,workspaces:[{workspace_id:"w1",label:"firstmate"}],tabs:[{tab_id:"w1:t1",label:"1",workspace_id:"w1",pane_id:"w1:p1"}],agent_status:{}}' > "$state"
  raw=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /proj' "$ROOT" ) \
    || fail "container_ensure failed against the stateful fake"
  container=${raw%%$'\t'*}
  seeded=${raw#*$'\t'}
  [ "$container" = "fmtest:w1" ] || fail "container_ensure should have ADOPTED the pre-existing workspace w1, got '$container'"
  [ -z "$seeded" ] || fail "an ADOPTED workspace must report an EMPTY seeded default tab id, got '$seeded'"
  assert_not_contains "$(cat "$log")" $'\x1f''workspace'$'\x1f''create' "container_ensure must not create a new workspace when one already exists to adopt"

  ids=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task "$1" "$2" /proj "$3"' "$ROOT" "$container" "fm-adopttest" "$seeded" ) \
    || fail "create_task failed against the stateful fake"
  read -r _ pane <<EOF
$ids
EOF
  [ -n "$pane" ] || fail "create_task returned no pane id"

  # The pre-existing tab (and its pane) must be COMPLETELY untouched.
  jq -e '.tabs[] | select(.tab_id == "w1:t1")' "$state" >/dev/null \
    || fail "the pre-existing (adopted) tab w1:t1 was removed - an adopted workspace's tab must never be pruned"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close'$'\x1f''w1:p1' \
    "create_task must never close a tab belonging to an ADOPTED workspace, no matter its label or count"
  pass "fm_herdr_create_task: an ADOPTED workspace's pre-existing tab is never pruned (the created-vs-adopted gate)"
}

test_label_collision_startup_workspace_leaves_live_tab_alone() {
  # The exact live-fire incident shape (2026-07-02): a captain launches herdr
  # directly inside a directory named "firstmate", so herdr auto-derives that
  # workspace's DISPLAYED label from the cwd basename - "firstmate" - byte-
  # identical to the primary firstmate home's own derived label, with no
  # --label ever passed and no firstmate involvement at all. That workspace's
  # single auto-created tab (label "1") holds the captain's own live agent.
  # The very next crewmate spawn must adopt-and-leave-alone, never prune.
  local dir log state fb raw container seeded ids pane
  dir="$TMP_ROOT/label-collision"; mkdir -p "$dir"; log="$dir/log"; state="$dir/state.json"; : > "$log"
  fb=$(make_herdr_statefake "$dir")
  # Mimic a bare `herdr workspace create --cwd <dir-named-firstmate>` (no
  # --label): the resulting workspace's label is the cwd basename, and its
  # one auto-created tab is still labeled "1" - indistinguishable, by label
  # alone, from firstmate's own freshly-seeded default tab. Its pane hosts a
  # live agent (agent_status=working), exactly like the captain's own pane.
  jq -n '{next:2,workspaces:[{workspace_id:"w1",label:"firstmate"}],tabs:[{tab_id:"w1:t1",label:"1",workspace_id:"w1",pane_id:"w1:p1"}],agent_status:{"w1:p1":"working"}}' > "$state"
  raw=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /proj' "$ROOT" ) \
    || fail "container_ensure failed against the stateful fake"
  container=${raw%%$'\t'*}
  seeded=${raw#*$'\t'}
  [ "$container" = "fmtest:w1" ] || fail "container_ensure should adopt the captain's coincidentally-labeled workspace, got '$container'"
  [ -z "$seeded" ] || fail "the coincidentally-labeled workspace was ADOPTED, not created, so seeded default tab id must be empty, got '$seeded'"

  ids=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task "$1" "$2" /proj "$3"' "$ROOT" "$container" "fm-collisiontest" "$seeded" ) \
    || fail "create_task failed against the stateful fake"
  read -r _ pane <<EOF
$ids
EOF
  [ -n "$pane" ] || fail "create_task returned no pane id"

  jq -e '.tabs[] | select(.tab_id == "w1:t1")' "$state" >/dev/null \
    || fail "REGRESSION: the captain's live tab was closed - this is the exact 2026-07-02 self-kill incident"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close'$'\x1f''w1:p1' \
    "REGRESSION: create_task closed the captain's live pane in the label-collision scenario"
  pass "fm_herdr_create_task: the label-collision startup-workspace scenario (2026-07-02 incident) leaves the captain's live tab untouched"
}

test_prune_refuses_a_working_agent_pane_defense_in_depth() {
  # Defense in depth (not the primary safety mechanism): even for a
  # freshly-created workspace with a genuine non-empty seeded default tab id,
  # if that specific pane's agent reports "working" by the time create_task
  # runs, the prune must refuse rather than close a live agent's pane.
  local dir log state fb raw container seeded seeded_pane ids pane
  dir="$TMP_ROOT/prune-busy-defense"; mkdir -p "$dir"; log="$dir/log"; state="$dir/state.json"; : > "$log"
  fb=$(make_herdr_statefake "$dir")
  raw=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_container_ensure /proj' "$ROOT" ) \
    || fail "container_ensure failed against the stateful fake"
  container=${raw%%$'\t'*}
  seeded=${raw#*$'\t'}
  [ -n "$seeded" ] || fail "expected a freshly created workspace to report a seeded default tab id"
  # Mark the seeded default tab's pane as hosting a working agent (simulates
  # some other path landing a live agent there between creation and prune).
  seeded_pane=$(jq -r --arg t "$seeded" '.tabs[] | select(.tab_id == $t) | .pane_id' "$state")
  [ -n "$seeded_pane" ] || fail "could not resolve the seeded default tab's pane id from state"
  fake_herdr_set_agent_status "$state" "$seeded_pane" working

  ids=$( PATH="$fb:$PATH" FM_HERDR_LOG="$log" FM_FAKE_HERDR_STATE="$state" HERDR_SESSION=fmtest \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_create_task "$1" "$2" /proj "$3"' "$ROOT" "$container" "fm-busytest" "$seeded" ) \
    || fail "create_task failed against the stateful fake"
  read -r _ pane <<EOF
$ids
EOF
  [ -n "$pane" ] || fail "create_task returned no pane id"

  jq -e --arg t "$seeded" '.tabs[] | select(.tab_id == $t)' "$state" >/dev/null \
    || fail "the seeded default tab was closed despite its pane reporting a working agent (defense-in-depth failed)"
  assert_not_contains "$(cat "$log")" $'\x1f''pane'$'\x1f''close'$'\x1f'"$seeded_pane" \
    "create_task must refuse to close a seeded default tab whose pane hosts a working agent"
  pass "fm_herdr_workspace_prune_seeded_default_tab: refuses to close the seeded default tab when its pane reports a working agent (defense in depth)"
}

# --- native event push: normalize / policy-routing / dedupe / wait ----------
#
# These exercise the herdr subscriber (fm_herdr_wait_transition and its
# helpers) with a FAKE socket reader and fake herdr CLI, so the policy routing,
# per-pane dedupe marker, reconnect level-reconcile, and fail-closed return
# codes are asserted without a real herdr server. The isolated real-herdr smoke
# that drives a live idle->blocked transition lives in
# tests/fm-herdr-eventwait-smoke.test.sh.

# make_herdr_eventfake: a herdr stub answering exactly the calls the event path
# makes - `session list --json` (echoes one session, name FM_FAKE_SESSION_NAME,
# socket FM_FAKE_SOCKET), `status --json`, and `agent get <pane>` (per-pane
# status read from $FM_FAKE_AGENT_DIR/<key>.status, else agent_not_found).
make_herdr_eventfake() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
LOG="${FM_HERDR_LOG:-/dev/null}"
{ printf 'HERDR_SESSION=%s' "${HERDR_SESSION:-}"; for a in "$@"; do printf '\x1f%s' "$a"; done; printf '\n'; } >> "$LOG"
cmd=${1:-}; sub=${2:-}
case "$cmd $sub" in
  "status --json")
    printf '{"client":{"version":"0.7.3","protocol":16},"server":{"running":true}}\n' ;;
  "session list")
    printf '{"sessions":[{"name":"%s","running":true,"default":false,"socket_path":"%s"}]}\n' \
      "${FM_FAKE_SESSION_NAME:-default}" "${FM_FAKE_SOCKET:-/tmp/fm-fake.sock}" ;;
  "agent get")
    if [ -n "${FM_FAKE_READER_READY_FILE:-}" ] && [ ! -e "$FM_FAKE_READER_READY_FILE" ]; then
      exit 9
    fi
    pane=${3:-}
    key=$(printf '%s' "$pane" | tr ':/.' '___')
    f="${FM_FAKE_AGENT_DIR:-/tmp}/$key.status"
    if [ -f "$f" ]; then
      printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(cat "$f")"
    else
      printf '{"error":{"code":"agent_not_found"}}\n' >&2
      exit 1
    fi ;;
  *) : ;;
esac
exit 0
SH
  chmod +x "$fb/herdr"
  printf '%s\n' "$fb"
}

# make_fake_reader: a stand-in for bin/fm-herdr-eventwait.py. It ignores
# the socket, streams the TAB-separated lines in $FM_FAKE_READER_LINES to stdout
# (one projected event per line: pane_id\tworkspace_id\tagent_status\tagent),
# then exits $FM_FAKE_READER_EXIT (default 0). A non-zero exit with no lines
# models a connect/subscribe failure.
make_fake_reader() {  # <dir> -> echoes reader path
  local dir=$1 path="$1/fake-reader.sh"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -u
# argv: <sock> <timeout> <pane...> - ignored; behavior is env-driven.
if [ -n "${FM_FAKE_READER_READY_FILE:-}" ]; then
  : > "$FM_FAKE_READER_READY_FILE"
fi
printf '%s\n' "${FM_FAKE_READER_ACK:-@subscribed}"
if [ -n "${FM_FAKE_READER_LINES:-}" ] && [ -f "$FM_FAKE_READER_LINES" ]; then
  cat "$FM_FAKE_READER_LINES"
fi
exit "${FM_FAKE_READER_EXIT:-0}"
SH
  chmod +x "$path"
  printf '%s\n' "$path"
}

set_fake_agent() {  # <agent-dir> <window-or-pane> <status>
  local dir=$1 target=$2 status=$3 key
  key=$(printf '%s' "$target" | tr ':/.' '___')
  mkdir -p "$dir"
  printf '%s' "$status" > "$dir/$key.status"
}

test_normalize_event_leaves_from_empty() {
  local rec
  rec=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_normalize_event wG:pQ wG blocked pi' "$ROOT")
  [ "$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_transition_pane_id "$1"' "$ROOT" "$rec")" = "wG:pQ" ] \
    || fail "normalize_event pane_id wrong: $rec"
  [ "$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_transition_from_status "$1"' "$ROOT" "$rec")" = "" ] \
    || fail "normalize_event should leave from_status empty (herdr carries no previous status): $rec"
  [ "$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_transition_to_status "$1"' "$ROOT" "$rec")" = "blocked" ] \
    || fail "normalize_event to_status wrong: $rec"
  pass "fm_herdr_normalize_event routes through the shared record with an empty from_status"
}

test_escalation_marker_keys_like_watcher() {
  local m
  m=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_escalation_marker /st default:wG:pQ' "$ROOT")
  [ "$m" = "/st/.herdr-escalated-default_wG_pQ" ] \
    || fail "escalation marker key must match the watcher's tr ':/.' '___' scheme, got '$m'"
  pass "fm_herdr_escalation_marker keys the dedupe marker exactly like the watcher's .stale-<key>"
}

test_apply_transition_blocked_requires_commit_to_dedupe() {
  local dir state rec out rc marker
  dir="$TMP_ROOT/apply-blocked"; state="$dir/state"; mkdir -p "$state"
  rec=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_transition_record wG:pQ wG "" blocked pi' "$ROOT")
  marker="$state/.herdr-escalated-default_wG_pQ"
  out=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_apply_transition "$1" "$2" "$3"' "$ROOT" "$state" default "$rec"); rc=$?
  [ "$rc" = 0 ] || fail "a fresh blocked edge must return 0 (actionable), got $rc"
  case "$out" in *blocked*) : ;; *) fail "apply_transition should print the record on a fresh actionable edge, got '$out'" ;; esac
  [ ! -e "$marker" ] || fail "detecting a blocked edge must not commit its marker before durable handling"
  bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_commit_transition "$1" "$2" "$3"' "$ROOT" "$state" default "$rec"
  [ -e "$marker" ] || fail "commit_transition must set the marker after the caller handles the edge"
  # Second identical blocked edge (marker present) must NOT re-fire.
  out=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_apply_transition "$1" "$2" "$3"' "$ROOT" "$state" default "$rec"); rc=$?
  [ "$rc" = 1 ] || fail "an already-marked blocked pane must return 1 (deduped), got $rc"
  [ -z "$out" ] || fail "an already-marked blocked pane must print nothing, got '$out'"
  pass "fm_herdr_apply_transition: blocked dedupe starts only after explicit commit"
}

test_apply_transition_working_clears_marker() {
  local dir state blocked working marker rc
  dir="$TMP_ROOT/apply-working"; state="$dir/state"; mkdir -p "$state"
  marker="$state/.herdr-escalated-default_wG_pQ"
  blocked=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_transition_record wG:pQ wG "" blocked pi' "$ROOT")
  working=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_transition_record wG:pQ wG "" working pi' "$ROOT")
  bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_commit_transition "$1" "$2" "$3"' "$ROOT" "$state" default "$blocked"
  [ -e "$marker" ] || fail "setup: committed blocked edge should have set the marker"
  bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_apply_transition "$1" "$2" "$3"' "$ROOT" "$state" default "$working"; rc=$?
  [ "$rc" = 1 ] || fail "a working (absorb) edge must return 1 (no wake), got $rc"
  [ ! -e "$marker" ] || fail "a working edge must CLEAR the escalation marker so a later re-block re-fires"
  # A re-block after the clear must fire again.
  bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_apply_transition "$1" "$2" "$3"' "$ROOT" "$state" default "$blocked" >/dev/null; rc=$?
  [ "$rc" = 0 ] || fail "a re-block after a working clear must re-fire (return 0), got $rc"
  pass "fm_herdr_apply_transition: a working edge clears the marker so the next ->blocked re-escalates"
}

test_clear_transition_removes_task_marker() {
  local dir state marker
  dir="$TMP_ROOT/clear-transition"; state="$dir/state"; mkdir -p "$state"
  marker="$state/.herdr-escalated-default_wG_pQ"
  : > "$marker"
  bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_clear_transition "$1" "$2"' "$ROOT" "$state" default:wG:pQ
  [ ! -e "$marker" ] || fail "clear_transition must remove the marker owned by a torn-down pane"
  pass "fm_herdr_clear_transition removes task-owned dedupe state"
}

test_apply_transition_defer_and_fallback_are_noops() {
  local dir state marker rc s
  dir="$TMP_ROOT/apply-defer"; state="$dir/state"; mkdir -p "$state"
  marker="$state/.herdr-escalated-default_wG_pQ"
  for s in idle "done" unknown ""; do
    local rec
    rec=$(bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_transition_record wG:pQ wG "" "$1" pi' "$ROOT" "$s")
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_apply_transition "$1" "$2" "$3"' "$ROOT" "$state" default "$rec"; rc=$?
    [ "$rc" = 1 ] || fail "defer/fallback status '$s' must return 1 (no fast action), got $rc"
    [ ! -e "$marker" ] || fail "defer/fallback status '$s' must not touch the escalation marker"
  done
  pass "fm_herdr_apply_transition: idle/done (defer) and unknown/empty (fallback) take no fast action"
}

test_wait_transition_no_panes_returns_2() {
  local rc
  bash -c '. "$0/bin/fm-herdr.sh"; FM_HERDR_EVENTS_FORCE=1 fm_herdr_wait_transition default 1 /tmp/st' "$ROOT"; rc=$?
  [ "$rc" = 2 ] || fail "wait_transition with no pane windows must return 2 (fall back to sleep), got $rc"
  pass "fm_herdr_wait_transition: a home with no herdr panes falls back to polling (rc 2)"
}

test_wait_transition_not_capable_returns_2() {
  local dir state fb rc
  dir="$TMP_ROOT/wt-incapable"; state="$dir/state"; mkdir -p "$state"
  fb=$(make_herdr_eventfake "$dir")
  rc=$(PATH="$fb:$PATH" FM_HERDR_EVENTS_FORCE=0 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 1 "$1" sess:wG:pQ; echo $?' "$ROOT" "$state" | tail -1)
  [ "$rc" = 2 ] || fail "wait_transition must return 2 when events are below capability (fail closed to poll), got $rc"
  pass "fm_herdr_wait_transition: below-capability protocol/schema falls back to polling (rc 2)"
}

test_wait_transition_reconcile_blocked_returns_record() {
  local dir state agent temp fb reader lines out rc marker
  dir="$TMP_ROOT/wt-reconcile"; state="$dir/state"; agent="$dir/agents"; temp="$dir/temp"; mkdir -p "$state" "$agent" "$temp"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" blocked
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"; : > "$lines"
  marker="$state/.herdr-escalated-sess_wG_pQ"
  out=$(PATH="$fb:$PATH" TMPDIR="$temp" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 1 "$1" sess:wG:pQ' "$ROOT" "$state"); rc=$?
  [ "$rc" = 0 ] || fail "reconcile of an already-blocked pane must return 0, got $rc"
  case "$out" in *blocked*) : ;; *) fail "reconcile must print the blocked record, got '$out'" ;; esac
  [ ! -e "$marker" ] || fail "reconcile must not mark a blocked pane before the caller durably handles it"
  [ -z "$(find "$temp" -mindepth 1 -print -quit)" ] || fail "actionable reconciliation must remove its private FIFO directory"
  pass "fm_herdr_wait_transition: reconnect level-reconcile returns an uncommitted blocked pane"
}

test_wait_transition_subscribes_before_reconcile() {
  local dir state agent fb reader lines ready rc
  dir="$TMP_ROOT/wt-subscribe-first"; state="$dir/state"; agent="$dir/agents"; mkdir -p "$state" "$agent"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" idle
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"; ready="$dir/subscribed"; : > "$lines"
  rc=$(PATH="$fb:$PATH" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" FM_FAKE_READER_READY_FILE="$ready" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 1 "$1" sess:wG:pQ; echo $?' "$ROOT" "$state" | tail -1)
  [ "$rc" = 1 ] || fail "subscription must be acknowledged before reconciliation begins, got $rc"
  pass "fm_herdr_wait_transition: subscribes before reconnect level-reconcile"
}

test_wait_transition_reconcile_dedupes_when_marked() {
  local dir state agent fb rc
  dir="$TMP_ROOT/wt-reconcile-dedupe"; state="$dir/state"; agent="$dir/agents"; mkdir -p "$state" "$agent"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" blocked
  # Pre-mark: this blocked was already escalated.
  : > "$state/.herdr-escalated-sess_wG_pQ"
  # No stream events, reader exits 0 -> a clean timeout (rc 1), NOT a re-fire.
  local reader lines
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"; : > "$lines"
  rc=$(PATH="$fb:$PATH" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 1 "$1" sess:wG:pQ; echo $?' "$ROOT" "$state" | tail -1)
  [ "$rc" = 1 ] || fail "an already-marked blocked pane must not re-fire on reconcile (expect clean timeout rc 1), got $rc"
  pass "fm_herdr_wait_transition: a still-blocked, already-escalated pane is not re-delivered on reconnect"
}

test_wait_transition_stream_blocked_returns_record() {
  local dir state agent fb reader lines out rc marker
  dir="$TMP_ROOT/wt-stream-blocked"; state="$dir/state"; agent="$dir/agents"; mkdir -p "$state" "$agent"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" idle   # reconcile sees idle -> proceeds to stream
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"
  printf 'wG:pQ\t\tblocked\tpi\n' > "$lines"
  marker="$state/.herdr-escalated-sess_wG_pQ"
  out=$(PATH="$fb:$PATH" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 2 "$1" sess:wG:pQ' "$ROOT" "$state"); rc=$?
  [ "$rc" = 0 ] || fail "a streamed blocked edge must return 0, got $rc"
  case "$out" in *blocked*) : ;; *) fail "a streamed blocked edge must print the record, got '$out'" ;; esac
  [ ! -e "$marker" ] || fail "a streamed blocked edge must remain uncommitted until durable handling"
  pass "fm_herdr_wait_transition: a streamed ->blocked edge returns the record sub-poll"
}

test_wait_transition_stream_absorb_returns_uncommitted_record() {
  local dir state agent fb reader lines out rc marker
  dir="$TMP_ROOT/wt-stream-absorb"; state="$dir/state"; agent="$dir/agents"; mkdir -p "$state" "$agent"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" idle
  : > "$state/.herdr-escalated-sess_wG_pQ"   # previously escalated
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"
  marker="$state/.herdr-escalated-sess_wG_pQ"
  printf 'wG:pQ\t\tworking\tpi\nwG:pQ\t\tidle\tpi\n' > "$lines"
  out=$(PATH="$fb:$PATH" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 2 "$1" sess:wG:pQ' "$ROOT" "$state"); rc=$?
  [ "$rc" = 0 ] || fail "a working edge with a marker must return for validated application, got $rc"
  case "$out" in *working*) : ;; *) fail "a working edge must print its normalized record, got '$out'" ;; esac
  [ -e "$marker" ] || fail "an unlocked transition wait cleared the escalation marker"
  pass "fm_herdr_wait_transition: working dedupe changes remain uncommitted"
}

test_wait_transition_reader_failure_returns_2() {
  local dir state agent temp fb reader lines rc
  dir="$TMP_ROOT/wt-reader-fail"; state="$dir/state"; agent="$dir/agents"; temp="$dir/temp"; mkdir -p "$state" "$agent" "$temp"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" idle
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"; : > "$lines"
  rc=$(PATH="$fb:$PATH" TMPDIR="$temp" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" FM_FAKE_READER_EXIT=2 \
    bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 1 "$1" sess:wG:pQ; echo $?' "$ROOT" "$state" | tail -1)
  [ "$rc" = 2 ] || fail "a reader connect/subscribe failure must return 2 (fall back to poll), got $rc"
  [ -z "$(find "$temp" -mindepth 1 -print -quit)" ] || fail "reader failure must remove its private FIFO directory"
  pass "fm_herdr_wait_transition: a reader/subscribe failure falls back to polling (rc 2)"
}

test_wait_transition_bad_ack_returns_2_and_cleans_up() {
  local dir state agent temp fb reader lines result rc fd_open
  dir="$TMP_ROOT/wt-bad-ack"; state="$dir/state"; agent="$dir/agents"; temp="$dir/temp"; mkdir -p "$state" "$agent" "$temp"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" idle
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"; : > "$lines"
  result=$(PATH="$fb:$PATH" TMPDIR="$temp" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" FM_FAKE_READER_ACK=invalid \
    /bin/bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 1 "$1" sess:wG:pQ; rc=$?; [ -e /dev/fd/9 ] && fd_open=yes || fd_open=no; printf "%s %s\n" "$rc" "$fd_open"' "$ROOT" "$state")
  rc=${result%% *}; fd_open=${result#* }
  [ "$rc" = 2 ] || fail "an invalid subscription acknowledgement must return 2, got $rc"
  [ "$fd_open" = no ] || fail "an invalid subscription acknowledgement must close fixed fd 9"
  [ -z "$(find "$temp" -mindepth 1 -print -quit)" ] || fail "an invalid subscription acknowledgement must remove its private FIFO directory"
  pass "fm_herdr_wait_transition: Bash 3.2-safe bad-ack path closes fd 9 and removes its FIFO"
}

test_wait_transition_clean_timeout_returns_1() {
  local dir state agent temp fb reader lines result rc fd_open
  dir="$TMP_ROOT/wt-timeout"; state="$dir/state"; agent="$dir/agents"; temp="$dir/temp"; mkdir -p "$state" "$agent" "$temp"
  fb=$(make_herdr_eventfake "$dir")
  set_fake_agent "$agent" "wG:pQ" idle
  reader=$(make_fake_reader "$dir"); lines="$dir/lines"; : > "$lines"   # no events, reader exits 0
  result=$(PATH="$fb:$PATH" TMPDIR="$temp" FM_HERDR_EVENTS_FORCE=1 FM_FAKE_SESSION_NAME=sess FM_FAKE_SOCKET="$dir/x.sock" FM_FAKE_AGENT_DIR="$agent" \
    FM_HERDR_EVENT_READER="$reader" FM_FAKE_READER_LINES="$lines" \
    /bin/bash -c '. "$0/bin/fm-herdr.sh"; fm_herdr_wait_transition sess 1 "$1" sess:wG:pQ; rc=$?; [ -e /dev/fd/9 ] && fd_open=yes || fd_open=no; printf "%s %s\n" "$rc" "$fd_open"' "$ROOT" "$state")
  rc=${result%% *}; fd_open=${result#* }
  [ "$rc" = 1 ] || fail "a clean full-budget wait with no actionable edge must return 1, got $rc"
  [ "$fd_open" = no ] || fail "a clean timeout must close fixed fd 9"
  [ -z "$(find "$temp" -mindepth 1 -print -quit)" ] || fail "a clean timeout must remove its private FIFO directory"
  pass "fm_herdr_wait_transition: stock macOS Bash clean timeout closes fd 9 and returns 1"
}

# shellcheck source=bin/fm-herdr.sh
. "$ROOT/bin/fm-herdr.sh"

test_version_check_accepts_current_protocol
test_version_check_refuses_old_protocol
test_version_check_refuses_missing_herdr
test_workspace_label_primary_home_no_marker
test_workspace_label_secondmate_home_uses_marker_id
test_workspace_label_secondmate_marker_trims_whitespace
test_workspace_label_empty_marker_falls_back_to_primary
test_workspace_label_different_secondmates_get_different_labels
test_cli_helper_sets_env_and_appends_trailing_session_flag
test_launcher_identity_absent_without_a_herdr_pane
test_launcher_identity_absent_when_herdr_env_alone_is_set
test_launcher_identity_resolves_the_exact_pane_tab_and_workspace
test_launcher_identity_refuses_a_pane_from_another_session_name
test_launcher_identity_refuses_a_missing_server_socket
test_launcher_identity_refuses_a_pane_from_another_server_socket
test_launcher_identity_refuses_an_unreadable_pane
test_launcher_identity_refuses_a_pane_and_tab_that_disagree
test_launcher_identity_refuses_a_workspace_missing_from_the_session
test_workspace_ensure_prefers_the_launcher_over_the_first_label_match
test_workspace_ensure_refuses_an_ambiguous_label_with_no_launcher
test_workspace_ensure_other_home_ignores_the_launcher_identity
test_container_ensure_refuses_an_ambiguous_home_label
test_container_ensure_starts_server_and_workspace
test_container_ensure_reuses_existing_workspace
test_container_ensure_creates_with_no_focus_flag
test_container_ensure_uses_secondmate_home_label
test_workspace_ensure_prunes_default_tab
test_repeated_cycles_reuse_one_workspace_no_orphans
test_adopted_workspace_never_prunes_default_tab
test_label_collision_startup_workspace_leaves_live_tab_alone
test_prune_refuses_a_working_agent_pane_defense_in_depth
test_create_task_refuses_duplicate_label
test_create_task_refuses_duplicate_label_when_agent_live
test_create_task_refuses_when_any_duplicate_label_is_live
test_create_task_closes_and_replaces_dead_pane_husk
test_create_task_closes_and_replaces_no_agent_husk
test_create_task_closes_all_duplicate_husks_after_replacement
test_create_task_refuses_when_preexisting_husk_tab_remains
test_create_task_refuses_when_agent_state_ambiguous
test_create_task_husk_replacement_creates_before_closing
test_create_task_creates_and_parses_ids
test_create_task_creates_with_no_focus_flag
test_presentation_defaults_on_at_or_above_the_floor
test_presentation_default_falls_back_below_the_floor
test_presentation_unreadable_release_falls_back
test_presentation_explicit_opt_in_survives_the_floor
test_presentation_explicit_off_opts_out
test_presentation_unrecognized_value_warns_and_keeps_the_default
test_presentation_floor_warning_is_one_per_release
test_presentation_floor_warning_marker_is_atomic_and_symlink_safe
test_presentation_running_server_release_is_load_bearing
test_release_floor_verdict_matches_the_measured_releases
test_release_floor_verdict_survives_losing_either_signal
test_presentation_preference_reports_three_distinct_states
test_projection_journal_is_atomic_and_uses_128_bit_token
test_projection_journal_v2_binds_and_advances_exact_endpoint
test_projection_create_uses_exact_response_ids_and_leaves_one_task_pane
test_projection_create_never_closes_a_concurrent_same_label_tab
test_projection_focus_snapshot_requires_exact_workspace_and_tab
test_projection_close_restores_exact_prior_focus
test_projection_close_refuses_active_tab
test_projection_close_reports_focus_restore_failure
test_projection_close_rechecks_required_agent_state_at_boundary
test_projection_close_emptying_after_focus_uses_pane_death_without_move
test_projection_close_emptying_before_focus_repositions_then_uses_pane_death
test_projection_close_emptying_before_last_focus_needs_no_move
test_projection_close_emptying_last_workspace_needs_no_move
test_projection_close_non_emptying_stays_plain_without_proof_or_move
test_projection_close_plain_without_move_requires_structured_removal
test_projection_close_ambiguous_positions_fall_back_to_plain_close
test_projection_close_move_failure_falls_back_to_plain_close
test_projection_close_busy_pane_falls_back_to_plain_close
test_projection_close_transient_prompt_helper_settles_then_uses_pane_death
test_projection_close_death_escalates_sigkill_after_sighup_survival
test_projection_close_death_failure_falls_back_to_plain_close
test_projection_close_death_still_restores_a_stolen_focus
test_projection_close_death_never_sigkills_a_reused_pid
test_projection_close_failed_removal_rolls_back_the_reposition
test_kill_emptying_non_focused_uses_pane_death
test_kill_focused_workspace_stays_plain_close
test_endpoint_confirmed_gone_gates_on_structured_presence
test_kill_refuses_when_presentation_lock_is_unavailable
test_projection_seeded_prune_refuses_active_tab
test_projection_label_builder_uses_corner_and_strips_owner_prefixes
test_projection_order_moves_only_exact_new_workspace_and_preserves_relative_order
test_projection_order_secondmate_parent_block
test_projection_order_foreign_legacy_child_is_read_only
test_projection_order_allows_intervening_parent_child_block
test_projection_order_human_spaces_never_move_targets
test_projection_order_failure_warns_without_cleanup_or_spawn_failure
test_projection_order_ambiguous_existing_block_is_read_only
test_projection_order_anchors_the_parent_by_exact_id
test_projection_order_foreign_new_child_before_parent_is_read_only
test_projection_order_missing_parent_is_read_only
test_presentation_session_lock_path_is_shared_across_homes
test_presentation_session_lock_path_rejects_malformed_socket
test_projection_order_rejects_malformed_socket
test_projection_reclaim_refusal_matrix_is_non_mutating
test_projection_reclaim_replaces_only_exact_husk_and_advances_binding
test_projection_recovery_is_read_only_and_refuses_live_duplicate_risk
test_workspace_find_matches_only_this_homes_own_label
test_list_live_scoped_to_this_homes_workspace_only
test_parse_target
test_normalize_key
test_capture_calls_pane_read
test_capture_works_around_small_lines_bug
test_capture_preserves_pane_read_failure
test_send_key_normalizes_and_targets_pane
test_kill_is_best_effort
test_current_path_reads_cwd
test_busy_state_working_maps_to_busy
test_busy_state_done_and_blocked_map_to_idle
test_busy_state_unknown_on_no_agent
test_composer_state_bordered_prompt_is_empty
test_composer_state_styled_placeholder_draft_is_pending
test_composer_state_real_text_is_pending
test_composer_state_popup_placeholder_fill_is_pending
test_composer_state_unknown_on_capture_failure
test_composer_state_unknown_when_no_composer_row_found
test_composer_state_pi_separator_idle_is_empty
test_composer_state_pi_separator_real_text_is_pending
test_composer_state_pi_incomplete_separator_below_stale_generic_is_unknown
test_composer_state_pi_separator_requires_safe_native_identity
test_wait_for_working_returns_busy_on_first_poll
test_wait_for_working_catches_a_slow_transition_mid_window
test_wait_for_working_samples_budget_endpoint_without_final_sleep
test_send_text_submit_applies_herdr_minimum_confirm_budget
test_wait_for_working_returns_idle_when_never_busy_but_readable
test_wait_for_working_returns_unknown_when_never_readable
test_wait_for_working_treats_blocked_as_submit_active
test_send_text_submit_detects_landed_send
test_send_text_submit_detects_swallowed_enter
test_send_text_submit_popup_autocomplete_requires_second_enter
test_send_text_submit_confirms_blocked_after_enter
test_send_text_submit_slow_transition_within_one_enter_needs_no_extra_enter
test_send_text_submit_send_failed
test_send_text_submit_enter_failure_is_send_failed
test_send_text_submit_later_enter_failure_stays_unconfirmed
test_send_text_submit_unknown_on_capture_failure
test_scripts_route_explicit_target_through_herdr_meta
test_normalize_event_leaves_from_empty
test_escalation_marker_keys_like_watcher
test_apply_transition_blocked_requires_commit_to_dedupe
test_apply_transition_working_clears_marker
test_clear_transition_removes_task_marker
test_apply_transition_defer_and_fallback_are_noops
test_wait_transition_no_panes_returns_2
test_wait_transition_not_capable_returns_2
test_wait_transition_reconcile_blocked_returns_record
test_wait_transition_subscribes_before_reconcile
test_wait_transition_reconcile_dedupes_when_marked
test_wait_transition_stream_blocked_returns_record
test_wait_transition_stream_absorb_returns_uncommitted_record
test_wait_transition_reader_failure_returns_2
test_wait_transition_bad_ack_returns_2_and_cleans_up
test_wait_transition_clean_timeout_returns_1
