#!/usr/bin/env bash
# fm-peek remote-secondmate capture routing.
#
# A remote secondmate's pane lives on its own host. The old path resolved the
# meta's "remote:<id>" window through the local backend adapters and handed it
# to tmux, which failed with "can't find session: remote" - a healthy remote
# mate misreported as an unreadable endpoint. These tests drive the real
# fm-peek + fm-on executables with a stubbed ssh transport (FM_SSH_BIN seam)
# and a poisoned local tmux, pinning:
#   1. A remote selector routes the capture over the remote transport and
#      prints the remote pane tail; the local adapters are never consulted.
#   2. An unreachable host fails loudly naming the host, without claiming the
#      mate is dead.
#   3. Backend-less remote metadata refuses as ambiguous before either runtime
#      transport is touched.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PEEK="$ROOT/bin/fm-peek.sh"

TMP_ROOT=$(fm_test_tmproot fm-peek-remote)

# fake-ssh prints the canned remote capture; the poisoned tmux records any
# local read attempt so the "never consulted" property is a real assertion.
make_stubs() {  # <dir> -> echoes fakebin dir
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/fake-ssh" <<'SH'
#!/usr/bin/env bash
cat > /dev/null
[ -z "${FM_FAKE_SSH_TOUCHED:-}" ] || printf 'ssh\n' >> "$FM_FAKE_SSH_TOUCHED"
[ -z "${FM_FAKE_REMOTE_CAPTURE:-}" ] || printf '%s\n' "$FM_FAKE_REMOTE_CAPTURE"
exit "${FM_FAKE_SSH_RC:-0}"
SH
  chmod +x "$fb/fake-ssh"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
printf 'tmux\n' >> "${FM_FAKE_TMUX_TOUCHED:?}"
exit 1
SH
  chmod +x "$fb/tmux"
  printf '%s\n' "$fb"
}

setup_remote_home() {  # <name> -> echoes home dir with remote meta + registry
  local home="$TMP_ROOT/$1-$RANDOM"
  mkdir -p "$home/state" "$home/data"
  fm_write_meta "$home/state/rsm.meta" \
    "window=remote:rsm" \
    "endpoint_task_id=rsm" \
    "harness=pi" \
    "kind=secondmate" \
    "mode=secondmate" \
    "remote_host=remote-mac" \
    "remote_root=/remote/root" \
    "backend=herdr" \
    "remote_backend=herdr" \
    "remote_herdr_session=fm-remote" \
    "remote_target=fm-remote:w1:p1"
  cat > "$home/data/secondmates.md" <<EOF
- rsm - remote test domain (host: remote-mac; root: /remote/root; home: /remote/home; scope: remote testing; projects: alpha; added 2026-08-02)
EOF
  printf '%s\n' "$home"
}

test_remote_peek_reads_remote_pane() {
  local dir fb home touched rc out
  dir="$TMP_ROOT/peek-ok"; mkdir -p "$dir"
  fb=$(make_stubs "$dir")
  home=$(setup_remote_home peek-ok)
  touched="$dir/tmux-touched"; : > "$touched"

  out=$(env PATH="$fb:$PATH" \
    FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_SSH_BIN="$fb/fake-ssh" FM_FAKE_SSH_RC=0 \
    FM_FAKE_REMOTE_CAPTURE='● the remote mate is mid-refactor' \
    FM_FAKE_TMUX_TOUCHED="$touched" \
    "$PEEK" rsm 20 2>"$dir/err"); rc=$?
  expect_code 0 "$rc" "a healthy remote peek should succeed"
  assert_contains "$out" "the remote mate is mid-refactor" \
    "the remote pane tail should be printed"
  assert_not_contains "$out" "can't find session" \
    "a remote peek must not fall into a local session lookup"
  [ ! -s "$touched" ] || fail "the local tmux adapter was consulted for a remote target"
  pass "fm-peek remote: the capture routes over the remote transport, local adapters untouched"
}

test_remote_peek_unreachable_fails_loudly_without_death_claim() {
  local dir fb home touched rc err
  dir="$TMP_ROOT/peek-down"; mkdir -p "$dir"
  fb=$(make_stubs "$dir")
  home=$(setup_remote_home peek-down)
  touched="$dir/tmux-touched"; : > "$touched"

  env PATH="$fb:$PATH" \
    FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_SSH_BIN="$fb/fake-ssh" FM_FAKE_SSH_RC=255 \
    FM_FAKE_TMUX_TOUCHED="$touched" \
    "$PEEK" rsm >"$dir/out" 2>"$dir/err"; rc=$?
  err=$(cat "$dir/err")
  [ "$rc" -ne 0 ] || fail "an unreachable remote peek must exit nonzero"
  assert_contains "$err" "remote pane of rsm on remote-mac" \
    "the failure must name the remote mate and host"
  assert_contains "$err" "not thereby dead" \
    "an unreadable remote pane must not be presented as a dead mate"
  pass "fm-peek remote: an unreachable host fails loudly without a false death claim"
}

test_remote_peek_backendless_refuses_before_transport() {
  local dir fb home touched ssh_touched rc err
  dir="$TMP_ROOT/peek-backendless"; mkdir -p "$dir"
  fb=$(make_stubs "$dir")
  home=$(setup_remote_home peek-backendless)
  grep -v '^backend=' "$home/state/rsm.meta" > "$home/state/rsm.meta.tmp"
  mv "$home/state/rsm.meta.tmp" "$home/state/rsm.meta"
  touched="$dir/tmux-touched"; : > "$touched"
  ssh_touched="$dir/ssh-touched"; : > "$ssh_touched"

  env PATH="$fb:$PATH" \
    FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_GATE_REFUSE_BYPASS='' \
    FM_SSH_BIN="$fb/fake-ssh" FM_FAKE_SSH_TOUCHED="$ssh_touched" \
    FM_FAKE_TMUX_TOUCHED="$touched" \
    "$PEEK" rsm >"$dir/out" 2>"$dir/err"; rc=$?
  err=$(cat "$dir/err")
  [ "$rc" -ne 0 ] || fail "backend-less remote metadata unexpectedly reached capture"
  assert_contains "$err" "no usable explicit backend identity" \
    "backend-less remote refusal did not explain its ambiguity"
  [ ! -s "$ssh_touched" ] || fail "backend-less remote metadata reached the remote transport"
  [ ! -s "$touched" ] || fail "backend-less remote metadata reached the local tmux adapter"
  pass "fm-peek remote: backend-less metadata refuses before every runtime transport"
}

test_remote_peek_reads_remote_pane
test_remote_peek_unreachable_fails_loudly_without_death_claim
test_remote_peek_backendless_refuses_before_transport

echo "all fm-peek-remote tests passed"
