#!/usr/bin/env bash
# Behavior tests for the relevance-gated Herdr Mirror manager.
#
# These tests drive its public required/check/install/status interface through a
# fake Herdr plugin CLI. They cover route relevance, version/source/update
# decisions, release-binary integrity, idempotence, partial-install recovery,
# and the boundary that preserves user-owned config, plugins, and CLI paths.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC2153 # ROOT is assigned by the sourced test library.
MANAGER="$ROOT/bin/fm-herdr-mirror.sh"
TMP_ROOT=$(fm_test_tmproot fm-herdr-mirror-tests)
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
PINNED_COMMIT=a569217ae59166470aa6a1fc0bbca2dea196af64

new_case() {
  local case_dir="$TMP_ROOT/$1" fakebin real_jq
  mkdir -p "$case_dir/home/.config/herdr-mirror" "$case_dir/home/.local/bin" \
    "$case_dir/plugin-root/target/release" "$case_dir/state"
  printf '%s\n' 'user-owned hosts sentinel' > "$case_dir/home/.config/herdr-mirror/hosts.toml"
  printf '%s\n' 'unrelated plugin sentinel' > "$case_dir/state/unrelated-plugin"
  fakebin=$(fm_fakebin "$case_dir")
  real_jq=$(command -v jq) || fail "jq is required for Herdr Mirror tests"
  ln -s "$real_jq" "$fakebin/jq"
  fm_fake_exit0 "$fakebin" git curl

  cat > "$fakebin/uname" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' Darwin ;;
  -m) printf '%s\n' arm64 ;;
  *) printf '%s\n' Darwin ;;
esac
SH
  chmod +x "$fakebin/uname"

  cat > "$fakebin/shasum" <<'SH'
#!/usr/bin/env bash
file=
for arg in "$@"; do file=$arg; done
if [ -f "$file" ] && grep -qx 'release-v0.1.16' "$file"; then
  printf '%s  %s\n' '08483f7533f8097392c34ef4bd7d40fc2425ea0609bcfbf65d2bcae82c7bcdb4' "$file"
else
  printf '%064d  %s\n' 0 "$file"
fi
SH
  chmod +x "$fakebin/shasum"
  ln -s "$fakebin/shasum" "$fakebin/sha256sum"

  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -eu
state=${FM_FAKE_MIRROR_STATE:?}
root=${FM_FAKE_MIRROR_ROOT:?}
if [ "${1:-}" = plugin ] && [ "${2:-}" = list ]; then
  if [ ! -f "$state/installed" ]; then
    printf '%s\n' '{"id":"cli:plugin","result":{"plugins":[],"type":"plugin_list"}}'
    exit 0
  fi
  version=$(cat "$state/version")
  owner=$(cat "$state/owner")
  repo=$(cat "$state/repo")
  commit=$(cat "$state/commit")
  jq -n \
    --arg version "$version" --arg owner "$owner" --arg repo "$repo" \
    --arg commit "$commit" --arg root "$root" \
    '{id:"cli:plugin",result:{plugins:[{plugin_id:"mirror",version:$version,enabled:false,plugin_root:$root,source:{kind:"github",owner:$owner,repo:$repo,resolved_commit:$commit,managed_path:$root}}],type:"plugin_list"}}'
  exit 0
fi
if [ "${1:-}" = plugin ] && [ "${2:-}" = install ]; then
  printf '%s\n' "$*" >> "$state/install.log"
  count=0
  [ ! -f "$state/install-count" ] || count=$(cat "$state/install-count")
  printf '%s\n' "$((count + 1))" > "$state/install-count"
  mkdir -p "$root/target/release"
  printf '%s\n' release-v0.1.16 > "$root/target/release/herdr-mirror"
  chmod 755 "$root/target/release/herdr-mirror"
  : > "$state/installed"
  printf '%s\n' 0.1.16 > "$state/version"
  printf '%s\n' netixc > "$state/owner"
  printf '%s\n' herdr-mirror > "$state/repo"
  printf '%s\n' a569217ae59166470aa6a1fc0bbca2dea196af64 > "$state/commit"
  exit 0
fi
printf 'unexpected fake herdr invocation: %s\n' "$*" >&2
exit 64
SH
  chmod +x "$fakebin/herdr"
  printf '%s\n' "$case_dir"
}

seed_plugin() { # <case> <version> <owner> <repo> <commit> <binary-state>
  local case_dir=$1 version=$2 owner=$3 repo=$4 commit=$5 binary_state=$6 state root
  state="$case_dir/state"
  root="$case_dir/plugin-root"
  : > "$state/installed"
  printf '%s\n' "$version" > "$state/version"
  printf '%s\n' "$owner" > "$state/owner"
  printf '%s\n' "$repo" > "$state/repo"
  printf '%s\n' "$commit" > "$state/commit"
  rm -f "$root/target/release/herdr-mirror"
  case "$binary_state" in
    current) printf '%s\n' release-v0.1.16 > "$root/target/release/herdr-mirror" ;;
    corrupt) printf '%s\n' tampered > "$root/target/release/herdr-mirror" ;;
    absent) return 0 ;;
    *) fail "unknown binary state: $binary_state" ;;
  esac
  chmod 755 "$root/target/release/herdr-mirror"
}

run_manager() { # <case> <command...>
  local case_dir=$1
  shift
  PATH="$case_dir/fakebin:$BASE_PATH" \
    HOME="$case_dir/home" \
    FM_HERDR_MIRROR_HERDR_BIN="$case_dir/fakebin/herdr" \
    FM_HERDR_MIRROR_CLI_LINK="$case_dir/home/.local/bin/herdr-mirror" \
    FM_FAKE_MIRROR_STATE="$case_dir/state" \
    FM_FAKE_MIRROR_ROOT="$case_dir/plugin-root" \
    "$MANAGER" "$@"
}

run_bootstrap_install() { # <case>
  local case_dir=$1
  (
    unset TMUX TMUX_PANE HERDR_ENV HERDR_PANE_ID HERDR_SESSION HERDR_SOCKET_PATH \
      CMUX_WORKSPACE_ID CMUX_SURFACE_ID CMUX_SOCKET_PATH CMUX_TAB_ID CMUX_PANEL_ID 2>/dev/null || true
    PATH="$case_dir/fakebin:$BASE_PATH" \
      HOME="$case_dir/home" \
      FM_HERDR_MIRROR_HERDR_BIN="$case_dir/fakebin/herdr" \
      FM_HERDR_MIRROR_CLI_LINK="$case_dir/home/.local/bin/herdr-mirror" \
      FM_FAKE_MIRROR_STATE="$case_dir/state" \
      FM_FAKE_MIRROR_ROOT="$case_dir/plugin-root" \
      "$ROOT/bin/fm-bootstrap.sh" install herdr-mirror
  )
}

assert_user_state_preserved() {
  local case_dir=$1
  [ "$(cat "$case_dir/home/.config/herdr-mirror/hosts.toml")" = 'user-owned hosts sentinel' ] \
    || fail "hosts.toml was changed"
  [ "$(cat "$case_dir/state/unrelated-plugin")" = 'unrelated plugin sentinel' ] \
    || fail "an unrelated plugin entry was changed"
}

test_remote_route_relevance_gate() {
  local registry="$TMP_ROOT/relevance-secondmates.md"
  : > "$registry"
  "$MANAGER" required "$registry" >/dev/null 2>&1 \
    && fail "an empty registry enabled Herdr Mirror management"
  printf -- '- local - local route (home: /tmp/local-home; scope: local; projects: p; added 2026-08-05)\n' > "$registry"
  "$MANAGER" required "$registry" >/dev/null 2>&1 \
    && fail "a local second mate enabled Herdr Mirror management"
  printf -- '- remote - remote route (host: remote-alias; root: /srv/firstmate; home: /srv/home; scope: remote; projects: p; added 2026-08-05)\n' >> "$registry"
  "$MANAGER" required "$registry" >/dev/null 2>&1 \
    || fail "a valid registered remote route did not enable Herdr Mirror management"
  pass "Herdr Mirror management is gated on a valid registered remote route"
}

test_absent_install_and_idempotence_preserve_user_state() {
  local case_dir out
  case_dir=$(new_case absent)
  run_manager "$case_dir" check >/dev/null 2>&1 \
    && fail "an absent plugin passed detection"
  out=$(run_manager "$case_dir" status 2>/dev/null)
  assert_contains "$out" 'needs installation or repair' "status did not explain the absent installation"

  run_bootstrap_install "$case_dir" >/dev/null \
    || fail "the approved bootstrap install did not converge"
  run_manager "$case_dir" check \
    || fail "a newly installed plugin did not pass detection"
  [ "$(readlink "$case_dir/home/.local/bin/herdr-mirror")" = "$case_dir/plugin-root/target/release/herdr-mirror" ] \
    || fail "the managed CLI link does not target the release binary"
  assert_grep 'plugin install --ref a569217ae59166470aa6a1fc0bbca2dea196af64 --yes netixc/herdr-mirror' "$case_dir/state/install.log" \
    "install did not use the pinned supported Herdr plugin interface"
  [ "$(cat "$case_dir/state/install-count")" = 1 ] || fail "the first install count is wrong"

  run_manager "$case_dir" install >/dev/null \
    || fail "an idempotent install rerun failed"
  [ "$(cat "$case_dir/state/install-count")" = 1 ] \
    || fail "an already-current rerun needlessly reinstalled the plugin"
  assert_user_state_preserved "$case_dir"
  pass "absent installation converges idempotently without changing user config or other plugins"
}

test_outdated_source_and_version_update() {
  local case_dir
  case_dir=$(new_case outdated)
  seed_plugin "$case_dir" 0.1.15 other herdr-mirror deadbeef current
  ln -s "$case_dir/plugin-root/target/release/herdr-mirror" "$case_dir/home/.local/bin/herdr-mirror"
  run_manager "$case_dir" check >/dev/null 2>&1 \
    && fail "an outdated unsupported plugin passed detection"
  run_manager "$case_dir" install >/dev/null \
    || fail "an outdated plugin did not update"
  [ "$(cat "$case_dir/state/version")" = 0.1.16 ] || fail "the plugin version did not update"
  [ "$(cat "$case_dir/state/commit")" = "$PINNED_COMMIT" ] || fail "the plugin source commit did not converge"
  run_manager "$case_dir" check || fail "the updated plugin did not pass detection"
  assert_user_state_preserved "$case_dir"
  pass "outdated version and source converge to the supported release"
}

test_partial_binary_and_link_recovery() {
  local missing_case link_case
  missing_case=$(new_case partial-binary)
  seed_plugin "$missing_case" 0.1.16 netixc herdr-mirror "$PINNED_COMMIT" absent
  run_manager "$missing_case" check >/dev/null 2>&1 \
    && fail "a plugin with no binary passed detection"
  run_manager "$missing_case" install >/dev/null \
    || fail "a partial install with no binary did not recover"
  [ "$(cat "$missing_case/state/install-count")" = 1 ] \
    || fail "the missing binary did not trigger one supported reinstall"

  link_case=$(new_case partial-link)
  seed_plugin "$link_case" 0.1.16 netixc herdr-mirror "$PINNED_COMMIT" current
  run_manager "$link_case" check >/dev/null 2>&1 \
    && fail "a current plugin with no CLI link passed detection"
  run_manager "$link_case" install >/dev/null \
    || fail "a missing CLI link did not recover"
  [ ! -f "$link_case/state/install-count" ] \
    || fail "repairing only the CLI link needlessly reinstalled the plugin"
  run_manager "$link_case" check || fail "the repaired CLI link did not pass detection"
  assert_user_state_preserved "$missing_case"
  assert_user_state_preserved "$link_case"
  pass "partial binary and CLI-link states recover with the smallest safe action"
}

test_corrupt_binary_is_reinstalled() {
  local case_dir
  case_dir=$(new_case corrupt)
  seed_plugin "$case_dir" 0.1.16 netixc herdr-mirror "$PINNED_COMMIT" corrupt
  ln -s "$case_dir/plugin-root/target/release/herdr-mirror" "$case_dir/home/.local/bin/herdr-mirror"
  run_manager "$case_dir" check >/dev/null 2>&1 \
    && fail "a binary with the wrong release digest passed detection"
  run_manager "$case_dir" install >/dev/null \
    || fail "a corrupt release binary did not recover"
  [ "$(cat "$case_dir/state/install-count")" = 1 ] \
    || fail "the corrupt binary did not trigger one reinstall"
  run_manager "$case_dir" check || fail "the integrity-repaired binary did not pass detection"
  pass "release digest mismatch triggers a supported reinstall"
}

test_user_owned_cli_path_is_never_overwritten() {
  local case_dir before rc out
  case_dir=$(new_case user-cli)
  seed_plugin "$case_dir" 0.1.16 netixc herdr-mirror "$PINNED_COMMIT" current
  printf '%s\n' 'operator-owned command' > "$case_dir/home/.local/bin/herdr-mirror"
  before=$(cat "$case_dir/home/.local/bin/herdr-mirror")
  set +e
  out=$(run_manager "$case_dir" install 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "install overwrote or accepted a user-owned CLI path"
  assert_contains "$out" 'refusing to overwrite user-owned CLI path' \
    "the user-owned CLI refusal was not actionable"
  [ "$(cat "$case_dir/home/.local/bin/herdr-mirror")" = "$before" ] \
    || fail "the user-owned CLI path changed"
  [ ! -f "$case_dir/state/install-count" ] \
    || fail "a CLI-path conflict needlessly reinstalled the current plugin"
  assert_user_state_preserved "$case_dir"
  pass "user-owned CLI paths, hosts, and unrelated plugin state are preserved"
}

test_remote_route_relevance_gate
test_absent_install_and_idempotence_preserve_user_state
test_outdated_source_and_version_update
test_partial_binary_and_link_recovery
test_corrupt_binary_is_reinstalled
test_user_owned_cli_path_is_never_overwritten

printf '# all fm-herdr-mirror tests passed\n'
