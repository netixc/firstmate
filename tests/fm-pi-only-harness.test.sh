#!/usr/bin/env bash
# Public-interface regression for exact plain Pi identity and migration refusal.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP=$(fm_test_tmproot fm-pi-only-harness)
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"; pass "$3"; }
mkdir -p "$TMP/config" "$TMP/state"
HARNESS="$ROOT/bin/fm-harness.sh"

assert_eq unknown "$(PI_CODING_AGENT=true FM_HOME="$TMP" "$HARNESS")" "mutable Pi environment marker cannot authorize plain Pi"
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/ps" <<'SH'
#!/usr/bin/env bash
pid=${!#}
if [ "${FAKE_CHAIN:-}" = signed-wrapper ]; then
  case "$pid:$*" in
    200:*comm=*) printf 'pi\n' ;;
    200:*args=*) printf 'pi\n' ;;
    200:*ppid=*) printf '300\n' ;;
    300:*comm=*) printf 'pi-signed\n' ;;
    300:*args=*) printf 'pi-signed\n' ;;
    300:*ppid=*) printf '1\n' ;;
    *:*comm=*) printf 'bash\n' ;;
    *:*args=*) printf 'bash\n' ;;
    *:*ppid=*) printf '200\n' ;;
  esac
elif [ "${FAKE_CHAIN:-}" = deep-excluded ]; then
  case "$pid:$*" in
    200:*comm=*|200:*args=*) printf 'pi\n' ;;
    220:*comm=*|220:*args=*) printf 'claude\n' ;;
    *:*comm=*|*:*args=*) printf 'bash\n' ;;
    220:*ppid=*) printf '1\n' ;;
    *:*ppid=*)
      if [ "$pid" -ge 200 ] 2>/dev/null && [ "$pid" -lt 220 ]; then printf '%s\n' "$((pid + 1))"; else printf '200\n'; fi
      ;;
  esac
else
  case "$*" in
    *comm=*) printf '%s\n' "$FAKE_COMM" ;;
    *args=*) printf '%s\n' "$FAKE_ARGS" ;;
    *ppid=*) printf '1\n' ;;
  esac
fi
SH
cat > "$TMP/fakebin/lsof" <<'SH'
#!/usr/bin/env bash
[ -n "${FAKE_EXECUTABLE:-}" ] || exit 1
printf 'p1\nftxt\nn%s\n' "$FAKE_EXECUTABLE"
SH
cat > "$TMP/fakebin/readlink" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  /proc/*/exe) [ -n "${FAKE_EXECUTABLE:-}" ] && { printf '%s\n' "$FAKE_EXECUTABLE"; exit 0; } ;;
esac
exec /usr/bin/readlink "$@"
SH
chmod +x "$TMP/fakebin/ps" "$TMP/fakebin/lsof" "$TMP/fakebin/readlink"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
  set +e
  out=$(env PI_CODING_AGENT=true FAKE_COMM="$old" FAKE_ARGS="$old" PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
  rc=$?
  set -e
  assert_eq 2 "$rc" "$old primary process is rejected"
  assert_contains "$out" "unsupported harness" "$old primary process reports migration"
done
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=cursor-agent FAKE_ARGS=cursor-agent PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "Cursor agent process is rejected"
assert_contains "$out" "unsupported harness" "Cursor agent process reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=muse-bin-1.2.3 FAKE_ARGS=muse-bin-1.2.3 PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "versioned Muse process is rejected"
assert_contains "$out" "unsupported harness" "versioned Muse process reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=2.1.220 FAKE_ARGS=/opt/claude/versions/2.1.220 PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "version-named excluded primary process is rejected"
assert_contains "$out" "unsupported harness" "version-named excluded primary reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=worker FAKE_ARGS=worker FAKE_EXECUTABLE=/opt/claude/versions/2.1.220 PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "immutable excluded executable path is rejected"
assert_contains "$out" "unsupported harness" "immutable excluded executable reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS='bash /opt/bin/pi-signed' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded shell script entrypoint is rejected"
assert_contains "$out" "unsupported harness" "excluded shell script entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS="bash '/tmp/user home/bin/pi-signed'" PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "spaced excluded shell entrypoint is rejected"
assert_contains "$out" "unsupported harness" "spaced excluded shell entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS='bash --rcfile /tmp/bashrc /opt/bin/pi-signed' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded shell entrypoint after option value is rejected"
assert_contains "$out" "unsupported harness" "option-bearing shell entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS='bash +O extglob /opt/bin/pi-signed' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded shell entrypoint after plus option value is rejected"
assert_contains "$out" "unsupported harness" "plus-option-bearing shell entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=deno FAKE_ARGS='deno run --cert /tmp/ca.pem /opt/bin/pi-signed' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "ambiguous interpreter options fail explicitly"
assert_contains "$out" "unsupported harness" "ambiguous interpreter options report migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node /opt/opencode/bin/opencode.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded Node script entrypoint is rejected"
assert_contains "$out" "unsupported harness" "excluded Node script entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node /tmp/pi-signed' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded basename Node entrypoint is rejected"
assert_contains "$out" "unsupported harness" "excluded basename Node entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node /opt/node_modules/@openai/codex/bin/codex.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded Codex Node entrypoint is rejected"
assert_contains "$out" "unsupported harness" "excluded Codex Node entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node --require /tmp/helper /opt/opencode/bin/opencode.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded Node entrypoint after option value is rejected"
assert_contains "$out" "unsupported harness" "option-bearing excluded Node entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node -C development /opt/opencode/bin/opencode.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded Node entrypoint after conditions value is rejected"
assert_contains "$out" "unsupported harness" "conditions-bearing excluded Node entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node --inspect-port 9229 /opt/opencode/bin/opencode.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "Node options with unproven arity fail explicitly"
assert_contains "$out" "unsupported harness" "unproven Node option arity reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node --title worker /opt/opencode/bin/opencode.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded Node entrypoint after title value is rejected"
assert_contains "$out" "unsupported harness" "title-bearing excluded Node entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_ARGS='node --env-file .env /opt/opencode/bin/opencode.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded Node entrypoint after env-file value is rejected"
assert_contains "$out" "unsupported harness" "env-file-bearing excluded Node entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=worker FAKE_EXECUTABLE="$(command -v node)" FAKE_ARGS='worker --env-file .env /opt/opencode/bin/opencode.js' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded Node entrypoint with rewritten title is rejected"
assert_contains "$out" "unsupported harness" "rewritten-title excluded Node entrypoint reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=worker FAKE_EXECUTABLE="$(command -v node)" FAKE_ARGS=worker PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "rewritten Node argv without launch provenance is rejected"
assert_contains "$out" "unsupported harness" "erased Node launch provenance reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_CHAIN=signed-wrapper PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded wrapper above an inner Pi process is rejected"
assert_contains "$out" "unsupported harness" "excluded wrapper above Pi reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_CHAIN=deep-excluded PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "deep excluded ancestry is rejected"
assert_contains "$out" "unsupported harness" "deep excluded ancestry reports migration"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS='bash ./claude' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "excluded basename shell entrypoint is rejected"
assert_contains "$out" "unsupported harness" "excluded basename shell entrypoint reports migration"
rm -f "$TMP/state/.session-start-complete" "$TMP/state/.session-start-agents-baseline"
set +e
out=$(env PI_CODING_AGENT=true FAKE_COMM=claude FAKE_ARGS=claude PATH="$TMP/fakebin:$PATH" \
  FM_HOME="$TMP" FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$TMP/state" \
  FM_DATA_OVERRIDE="$TMP/data" FM_CONFIG_OVERRIDE="$TMP/config" \
  "$ROOT/bin/fm-session-start.sh" 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "session start rejects an excluded primary"
assert_contains "$out" "unsupported harness" "session start preserves the primary identity failure"
assert_absent "$TMP/state/.session-start-complete" "excluded primary cannot publish session completion"
assert_absent "$TMP/state/.session-start-agents-baseline" "excluded primary cannot publish a session baseline"
assert_eq unknown "$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS='bash ./claude.sh' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS")" "ordinary similarly named shell script is not treated as a harness"
assert_eq unknown "$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS='bash ./script /tmp/bin/claude' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS")" "excluded install path used as data is not treated as a harness"
assert_eq unknown "$(env PI_CODING_AGENT=true FAKE_COMM=node FAKE_EXECUTABLE="$(command -v node)" FAKE_ARGS='node helper.js /opt/bin/codex' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS")" "excluded install path used as Node helper data is not treated as a harness"
assert_eq unknown "$(env PI_CODING_AGENT=true FAKE_COMM=python FAKE_ARGS='python muse.py' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS")" "ordinary similarly named Python script is not treated as a harness"
assert_eq unknown "$(env PI_CODING_AGENT=true FAKE_COMM=bash FAKE_ARGS='bash ./script anthropic/claude' PATH="$TMP/fakebin:$PATH" FM_HOME="$TMP" "$HARNESS")" "provider-qualified model text remains valid input"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
  printf '%s\n' "$old" > "$TMP/config/crew-harness"
  set +e
  out=$(PI_CODING_AGENT=true FM_HOME="$TMP" "$HARNESS" crew 2>&1)
  rc=$?
  set -e
  assert_eq 2 "$rc" "$old configuration is rejected"
  assert_contains "$out" "unsupported harness" "$old reports migration"
done
printf 'pi\n' > "$TMP/config/crew-harness"
assert_eq pi "$(FM_HOME="$TMP" "$HARNESS" crew)" "explicit plain Pi resolves"
printf 'default openai-codex/gpt-5.6-sol high\n' > "$TMP/config/secondmate-harness"
set +e
out=$(FM_HOME="$TMP" "$HARNESS" secondmate 2>&1)
rc=$?
set -e
assert_eq 2 "$rc" "default secondmate configuration rejects profile fields"
assert_contains "$out" '"default" does not accept model or effort fields' "invalid default profile reports its grammar"

printf 'claude\n' > "$TMP/config/secondmate-harness"
printf 'window=control:fm-mate\nworktree=%s\nproject=%s\nkind=secondmate\nharness=pi\n' "$TMP" "$TMP" > "$TMP/state/mate.meta"
meta_before=$(cksum "$TMP/state/mate.meta")
set +e
out=$(FM_HOME="$TMP" "$ROOT/bin/fm-control.sh" mate relaunch 2>&1)
rc=$?
set -e
assert_eq 1 "$rc" "excluded secondmate relaunch pin is rejected"
assert_contains "$out" "unsupported harness" "excluded secondmate relaunch pin reports migration"
assert_eq "$meta_before" "$(cksum "$TMP/state/mate.meta")" "excluded secondmate pin fails before metadata mutation"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-control-lib.sh"
fm_control_harness_supported pi || fail "plain Pi control is supported"
pass "plain Pi control is supported"
fm_control_harness_supports_kind pi ship || fail "plain Pi ship relaunch is supported"
pass "plain Pi ship relaunch is supported"
for old in pi-signed claude codex opencode grok kimi cursor muse; do
  if fm_control_harness_supported "$old"; then fail "$old control metadata is unsupported"; fi
  pass "$old control metadata is unsupported"
done
assert_eq Escape "$(fm_control_interrupt_key pi)" "Pi interrupt key"
assert_eq /quit "$(fm_control_exit_command pi)" "Pi exit command"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-busy-lib.sh"
printf 'generation\n' > "$TMP/state/task.busy-gen"
printf 'v1 gen=generation seq=1 state=idle source=pi-ext event=agent-settled ts=1\n' > "$TMP/state/task.busy-state"
assert_eq 'idle pi-ext' "$(fm_busy_classify tmux target pi task "$TMP/state")" "Pi semantic state is accepted"
assert_eq 'unknown unsupported-harness' "$(fm_busy_classify tmux target pi-signed task "$TMP/state")" "old metadata is not normalized"
