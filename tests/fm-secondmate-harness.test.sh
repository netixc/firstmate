#!/usr/bin/env bash
# Pi-only harness resolution and current Secondmate config inheritance.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-config-inherit-lib.sh
. "$ROOT/bin/fm-config-inherit-lib.sh"
HARNESS="$ROOT/bin/fm-harness.sh"
TMP_ROOT=$(fm_test_tmproot fm-secondmate-harness)

test_harness_resolution_is_pi_only() {
  local home=$TMP_ROOT/harness out
  mkdir -p "$home/config"
  printf 'pi\n' > "$home/config/crew-harness"
  [ "$(FM_HOME="$home" "$HARNESS" crew)" = pi ] || fail "crew harness did not resolve Pi"
  [ "$(FM_HOME="$home" "$HARNESS" secondmate)" = pi ] || fail "Secondmate fallback did not resolve Pi"
  printf 'pi gpt-5 high\n' > "$home/config/secondmate-harness"
  [ "$(FM_HOME="$home" "$HARNESS" secondmate)" = pi ] || fail "pinned Secondmate harness did not resolve Pi"
  [ "$(FM_HOME="$home" "$HARNESS" secondmate-model)" = gpt-5 ] || fail "Secondmate model token lost"
  [ "$(FM_HOME="$home" "$HARNESS" secondmate-effort)" = high ] || fail "Secondmate effort token lost"
  printf 'unverified\n' > "$home/config/crew-harness"
  rm -f "$home/config/secondmate-harness"
  out=$(FM_HOME="$home" "$HARNESS" crew)
  [ "$out" = unverified ] || fail "static resolver hid the configured unverified value"
  pass "Pi resolution and Secondmate profile tokens remain explicit"
}

test_inheritable_config_excludes_retired_session_selection() {
  local d=$TMP_ROOT/inherit src dest
  src=$d/src; dest=$d/home/config
  mkdir -p "$src" "$dest"
  printf '{"default":{"harness":"pi"}}\n' > "$src/crew-dispatch.json"
  printf 'pi\n' > "$src/crew-harness"
  printf 'manual\n' > "$src/backlog-backend"
  printf 'off\n' > "$src/herdr-presentation-spaces"
  printf '4321\n' > "$src/startup-memory-budget"
  : > "$src/trace-context"
  # A retired file is not in the declared allowlist and must neither propagate
  # nor overwrite an independently preserved destination record.
  printf 'tmux\n' > "$src/backend"
  printf 'legacy-local\n' > "$dest/backend"
  propagate_inheritable_config "$src" "$dest" || fail "current config propagation failed"
  [ "$(cat "$dest/crew-dispatch.json")" = '{"default":{"harness":"pi"}}' ] || fail "dispatch config not copied"
  [ "$(cat "$dest/crew-harness")" = pi ] || fail "crew harness not copied"
  [ "$(cat "$dest/backlog-backend")" = manual ] || fail "backlog mode not copied"
  [ "$(cat "$dest/herdr-presentation-spaces")" = off ] || fail "Herdr presentation preference not copied"
  [ "$(cat "$dest/startup-memory-budget")" = 4321 ] || fail "memory budget not copied"
  [ -f "$dest/trace-context" ] || fail "trace-context flag not copied"
  [ "$(cat "$dest/backend")" = legacy-local ] || fail "retired runtime selection was propagated or overwritten"
  if fm_config_inherit_items | grep -Fxq config/backend; then
    fail "retired config/backend remains in the inherited-material allowlist"
  fi
  pass "Secondmate inheritance carries current config and excludes retired session selection"
}

test_absence_mirror_is_safe_and_idempotent() {
  local d=$TMP_ROOT/absence src dest before after outside
  src=$d/src; dest=$d/home/config; outside=$d/outside
  mkdir -p "$src" "$dest"
  printf 'pi\n' > "$src/crew-harness"
  propagate_inheritable_config "$src" "$dest" || fail "initial propagation failed"
  before=$(stat -f %m "$dest/crew-harness" 2>/dev/null || stat -c %Y "$dest/crew-harness")
  sleep 1
  propagate_inheritable_config "$src" "$dest" || fail "idempotent propagation failed"
  after=$(stat -f %m "$dest/crew-harness" 2>/dev/null || stat -c %Y "$dest/crew-harness")
  [ "$before" = "$after" ] || fail "unchanged propagation churned file identity"
  printf 'outside\n' > "$outside"
  rm -f "$dest/crew-harness"
  ln -s "$outside" "$dest/crew-harness"
  rm -f "$src/crew-harness"
  propagate_inheritable_config "$src" "$dest" || fail "absence mirror failed"
  [ ! -e "$dest/crew-harness" ] && [ ! -L "$dest/crew-harness" ] || fail "absence mirror retained an unsafe link"
  [ "$(cat "$outside")" = outside ] || fail "absence mirror changed the link target"
  pass "inherited config convergence is idempotent and symlink-safe"
}

test_harness_resolution_is_pi_only
test_inheritable_config_excludes_retired_session_selection
test_absence_mirror_is_safe_and_idempotent
